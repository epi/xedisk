// Written in the D programming language

/*
sparta.d - implementation of SpartaDOS file system
Copyright (C) 2010-2012 Adrian Matoga

xedisk is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

xedisk is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with xedisk.  If not, see <http://www.gnu.org/licenses/>.
*/

module xe.fs_impl.sparta;

import std.string;
import std.algorithm;
import std.exception;
import std.datetime;
import xe.disk;
import xe.fs;
import xe.fs_impl.cache;
import xe.bytemanip;
import xe.streams;

version (unittest)
{
	import std.stdio;
	import streamimpl;
}
	import std.stdio;

private enum DirEntrySize = 23;

private enum DirEntryStatus : ubyte
{
	OpenForWriting = 0x80,
	Directory = 0x20,
	Deleted = 0x10,
	InUse = 0x08,
	Archive = 0x04,
	Hidden = 0x02,
	ReadOnly = 0x01,
	None = 0
}

private enum LogicalSectorSize : int
{
	B128 = 128,
	B256 = 256,
	B512 = 512,
	Invalid = -1,
}

private enum FileSystemVersion : int
{
	V1_1 = 0x11,
	V2_0 = 0x20,
	V2_1 = 0x21,
	Invalid = -1,
}

// do not allocate on heap, please.
private struct Info
{
	CachedSector buf;
	this(SectorCache cache)
	{
		buf = cache.request(1);
	}
	uint getMagic() { return makeWord(buf[8], buf[7], buf[6]); }
	uint getRootDirMapFirstCluster() { return makeWord(buf[10], buf[9]); }
	uint getTotalClusters() { return makeWord(buf[12], buf[11]); }
	uint getFreeClusters() { return makeWord(buf[14], buf[13]); }
	uint getBitmapClusters() { return buf[15]; }
	uint getBitmapFirstCluster() { return makeWord(buf[17], buf[16]); }
	uint getFileAllocStartCluster() { return makeWord(buf[19], buf[18]); }
	uint getDirAllocStartCluster() { return makeWord(buf[21], buf[20]); }
	string getDiskName() { return cast(string) buf[22 .. 29].idup; }
	uint getTracks() { return buf[30] & 0x7f; }
	uint getSides() { return (buf[30] & 0x80) ? 2 : 1; }
	LogicalSectorSize getClusterSize()
	{
		switch (buf[31])
		{
		case 0x80: return LogicalSectorSize.B128;
		case 0x00: return LogicalSectorSize.B256;
		case 0x01: return LogicalSectorSize.B512;
		default: return LogicalSectorSize.Invalid;
		}
	}
	FileSystemVersion getVersion()
	{
		switch (buf[32])
		{
		case 0x11: return FileSystemVersion.V1_1;
		case 0x20: return FileSystemVersion.V2_0;
		case 0x21: return FileSystemVersion.V2_1;
		default: return FileSystemVersion.Invalid;
		}
	}
	int getSectorSize()
	{
		switch (getVersion())
		{
		case FileSystemVersion.V2_1: return makeWord(buf[34], buf[33]);
		default: return getClusterSize();
		}
	}
	uint getEntriesPerMapCluster()
	{
		switch (getVersion())
		{
		case FileSystemVersion.V2_1: return makeWord(buf[36], buf[35]);
		case FileSystemVersion.V1_1, FileSystemVersion.V2_0:
			return getSectorSize() / 2 - 2;
		default: return 0;
		}
	}
	uint getSectorsPerCluster()
	{
		switch (getVersion())
		{
		case FileSystemVersion.V2_1: return buf[37];
		case FileSystemVersion.V1_1, FileSystemVersion.V2_0:
			return 1;
		default: return 0;
		}
	}
	uint getSequentialId()
	{
		switch (getVersion())
		{
		case FileSystemVersion.V2_1, FileSystemVersion.V2_0:
			return buf[38];
		default: return 0;
		}
	}
	uint getRandomId()
	{
		switch (getVersion())
		{
		case FileSystemVersion.V2_1, FileSystemVersion.V2_0:
			return buf[39];
		default: return 0;
		}
	}
}

unittest
{
	scope stream = new FileStream(File("testfiles/epi.atr"));
	scope disk = XeDisk.open(stream);
	scope cache = new SectorCache(disk);
	auto info = Info(cache);
	assert (info.getSectorSize() == 512);
	assert (info.getClusterSize() == 512);
	assert (info.getTotalClusters() == 720);
	assert (info.getSectorsPerCluster() == 1);
	writeln("Info (1) ok");
}

// allocate wherever you wish
private struct ClusterMapIterator
{
	this(SectorCache cache, uint firstMapCluster, bool writable = false)
	{
		_cache = cache;
		_currentMapCluster = firstMapCluster;
		_currentEntry = 0;
		_entriesPerMapCluster = Info(cache).getEntriesPerMapCluster();
	}

	void moveForward(uint clusters = 1)
	{
		while (clusters)
		{
			uint inc = min(_entriesPerMapCluster - _currentEntry, clusters);
			_currentEntry += inc;
			clusters -= inc;
			if (_currentEntry >= _entriesPerMapCluster)
			{
				auto buf = _cache.request(_currentMapCluster);
				uint next = makeWord(buf[1], buf[0]);
				_currentMapCluster = next ? next : allocate();
				_currentEntry = 0;
			}
		}
	}

	void moveBackwards(uint clusters = 1)
	{
		while (clusters)
		{
			uint dec = min(_currentEntry, clusters);
			_currentEntry -= dec;
			clusters -= dec;
			if (_currentEntry == 0 && clusters)
			{
				auto buf = _cache.request(_currentMapCluster);
				uint prev = makeWord(buf[3], buf[2]);
				if (!prev)
					throw new Exception("BOF");
				_currentEntry = _entriesPerMapCluster;
			}
		}
	}

	@property uint current()
	{
		auto buf = _cache.request(_currentMapCluster);
		return makeWord(
			buf[4 + _currentEntry * 2 + 1],
			buf[4 + _currentEntry * 2]);
	}

	@property void current(uint cur)
	{
		auto buf = _cache.request(_currentMapCluster);
		buf[4 + _currentEntry * 2] = getByte!0(cur);
		buf[4 + _currentEntry * 2 + 1] = getByte!1(cur);
	}

	ClusterMapIterator save()
	{
		return this;
	}

	uint allocate()
	{
		debug assert (!_writable);
		throw new Exception("Not implemented");
	}

	SectorCache _cache;
	uint _currentMapCluster;
	uint _currentEntry;
	uint _entriesPerMapCluster;
	debug bool _writable;
}

private struct RawStream
{
	this(ClusterMapIterator clusterMap, uint offset)
	{
		assert (clusterMap._cache !is null);
		_cmi = clusterMap;
		_offset = offset;
		_clusterSize = Info(_cmi._cache).getClusterSize();
	}

	size_t read(ubyte[] buf)
	{
		size_t r;
		auto clusterSize = Info(_cmi._cache).getClusterSize();
		while (r < buf.length)
		{
			if (_offset >= clusterSize)
			{
				_offset = 0;
				_cmi.moveForward(1);
			}
			auto sec = _cmi._cache.request(_cmi.current);
			auto toRead = min(buf.length - r, clusterSize - _offset);
			buf[r .. r + toRead] = sec[_offset .. _offset + toRead];
			r += toRead;
			_offset += toRead;
		}
		return r;
	}

	void write(in ubyte[] buf)
	{
		assert (false);
	}

	RawStream save()
	{
		return this;
	}

	ClusterMapIterator _cmi;
	uint _offset;
	uint _clusterSize;
}

private struct DirEntry
{
	this(RawStream rs)
	{
		_rs = rs;
		_data.length = DirEntrySize;
		reload();
	}

	void reload()
	{
		_rs.save().read(_data);
	}

	void flush()
	{
		assert (false);
	}

	@property DirEntryStatus status() const pure
	{
		return cast(DirEntryStatus) _data[0];
	}

	@property uint firstMapCluster() const pure
	{
		return makeWord(_data[2], _data[1]);
	}

	@property size(uint s)
	{
		_data[5] = getByte!2(s);
		_data[4] = getByte!1(s);
		_data[3] = getByte!0(s);
	}
	
	@property uint size() const pure
	{
		return makeWord(_data[5], _data[4], _data[3]);
	}

	@property string name() const pure
	{
		string s = cast(string) _data[6 .. 6 + 11];
		string sname = s[0 .. 8].stripRight().toLower();
		string sext = s[8 .. 11].stripRight().toLower();
		return sext.length ? sname ~ "." ~ sext : sname;
	}

	@property DateTime timeStamp()
	{
		uint yr = _data[19] % 100;
		// TODO: is this really the simplest solution?
		try
		{
			return DateTime((yr >= 70 && yr <= 99) ? yr + 1900 : yr + 2000,
				_data[18], _data[17], _data[20], _data[21], _data[22]);
		}
		catch (Exception)
		{
			return DateTime.init;
		}
	}

	string toString()
	{
		return format("@%s %02x %s `%s'", firstMapCluster, status, size, name);
	}

	RawStream _rs;
	ubyte[] _data;
}

unittest
{
	scope stream = new FileStream(File("testfiles/epi.atr"));
	scope disk = XeDisk.open(stream);
	scope cache = new SectorCache(disk);
	auto info = Info(cache);
	auto rs = RawStream(ClusterMapIterator(cache, info.getRootDirMapFirstCluster()), 0);
	auto de = DirEntry(rs);
	assert (de.status != DirEntryStatus.None);
	assert (de.name == "main");
	assert (rs.read(new ubyte[DirEntrySize]) == DirEntrySize);
	de = DirEntry(rs);
	assert (de.name == "foo");
	assert (rs.read(new ubyte[DirEntrySize]) == DirEntrySize);
	de = DirEntry(rs);
	assert (de.name == "sd32g.arc");
	assert (rs.read(new ubyte[DirEntrySize]) == DirEntrySize);
	de = DirEntry(rs);
	assert (de.status == DirEntryStatus.None);
}

abstract class SpartaDirectory : XeDirectory
{
	DirEntry _entryInThis;
	SpartaFileSystem _fs;
}

class SpartaRootDirectory : SpartaDirectory
{
	mixin DirectoryEntry;

	this(SpartaFileSystem fs)
	{
		_fs = fs;
		_cache = fs._cache;
		assert (_cache);
		_entryInThis = DirEntry(RawStream(ClusterMapIterator(
			_cache, Info(_cache).getRootDirMapFirstCluster()), 0));
	}

	override string getName() { return _entryInThis.name; }
	override ulong getSize() { return _entryInThis.size; }
	override uint getSectors()
	{
		uint sectorSize = Info(_entryInThis._rs._cmi._cache).getSectorSize();
		return cast(uint) ((getSize() + sectorSize - 1) / sectorSize);
	}

	override SpartaDirectory getParent() { return null; }
	override void rename(string newName) { throw new Exception("Cannot rename root directory"); }
	override void doRemove() { throw new Exception("Cannot delete root directory"); }
	override bool isReadOnly() { return true; }
	override void setReadOnly(bool value) { throw new Exception("Cannot change `read only' flag for root directory"); }

	override bool isHidden() { return false; }
	override void setHidden(bool value) { throw new Exception("Cannot change `hidden' flag for root directory"); }
	override bool isArchive() { return false; }
	override void setArchive(bool value) { throw new Exception("Cannot change `archive' flag for root directory"); }
	override DateTime getTimeStamp() { return _entryInThis.timeStamp; }
	override void setTimeStamp(DateTime timeStamp) { throw new Exception("Not implemented"); }

	override SpartaDirectory createDirectory(string name) { throw new Exception("Not implemented"); }
	override OutputStream createFile(string name) { throw new Exception("Not implemented"); }

	SectorCache _cache;
}

mixin template DirectoryEntry()
{
	protected override int doEnumerate(int delegate(XeEntry entry) action)
	{
		auto rs = _entryInThis._rs.save();
		ubyte[DirEntrySize] discard;
		for (;;)
		{
			rs.read(discard);
			auto de = DirEntry(rs);
			if (de.status == DirEntryStatus.None)
				break;
			int result;
			auto status = de.status & (DirEntryStatus.Directory
				| DirEntryStatus.Deleted | DirEntryStatus.InUse);
			if (status == (DirEntryStatus.Directory | DirEntryStatus.InUse))
				result = action(new SpartaSubDirectory(this, de));
			else if (status == DirEntryStatus.InUse)
				result = action(new SpartaFile(this, de));
			else
				continue;
			if (result)
				return 1;
		}
		return 0;
	}
}

mixin template ContainedEntry()
{
	SpartaDirectory _parent;
	DirEntry _entryInParent;

	override SpartaDirectory getParent() { return _parent; }
	override bool isReadOnly() { return cast(bool) (_entryInParent.status & DirEntryStatus.ReadOnly); }
	override void setReadOnly(bool ro) { throw new Exception("Not implemented"); }
	override void rename(string newname) { throw new Exception("Not implemented"); }
	override string getName() { return _entryInParent.name; }
	override void doRemove() { throw new Exception("Not implemented"); }

	override ulong getSize() { return _entryInParent.size; }
	override uint getSectors()
	{
		uint sectorSize = Info(_entryInParent._rs._cmi._cache).getSectorSize();
		return cast(uint) ((getSize() + sectorSize - 1) / sectorSize);
	}

	override bool isHidden() { return cast(bool) (_entryInParent.status & DirEntryStatus.Hidden); }
	override void setHidden(bool value) { throw new Exception("Not implemented"); }
	override bool isArchive() { return cast(bool) (_entryInParent.status & DirEntryStatus.Archive); }
	override void setArchive(bool value) { throw new Exception("Not implemented"); }
	override DateTime getTimeStamp() { return _entryInParent.timeStamp; }
	override void setTimeStamp(DateTime timeStamp) { /+ ignore or throw? +/ }
}

class SpartaFile : XeFile
{
	mixin ContainedEntry;

	this(SpartaDirectory parent, DirEntry de)
	{
		_parent = parent;
		_entryInParent = de;
	}

	override OutputStream openWriteOnly(bool append) { throw new Exception("Not implemented"); }

	override InputStream openReadOnly()
	{
		return new class() InputStream
		{
			this()
			{
				_rawStream = RawStream(ClusterMapIterator(
					this.outer._parent._fs._cache,
					this.outer._entryInParent.firstMapCluster), 0);
				_length = this.outer._entryInParent.size;
			}

			override size_t doRead(ubyte[] buffer)
			{
				size_t toRead = min(buffer.length, _length - _offset);
				size_t r = _rawStream.read(buffer[0 .. toRead]);
				assert (r == toRead);
				_offset += r;
				return r;
			}

			RawStream _rawStream;
			uint _length;
			uint _offset;
		};
	}
}

class SpartaSubDirectory : SpartaDirectory
{
	mixin ContainedEntry;
	mixin DirectoryEntry;

	this(SpartaDirectory parent, DirEntry de)
	{
		_fs = parent._fs;
		_cache = _fs._cache;
		_parent = parent;
		_entryInParent = de;
		_entryInThis = DirEntry(RawStream(ClusterMapIterator(
			_cache, de.firstMapCluster), 0));
	}

	override SpartaDirectory createDirectory(string name) { throw new Exception("Not implemented"); }
	override OutputStream createFile(string name) { throw new Exception("Not implemented"); }
	SectorCache _cache;
}

class SpartaFileSystem : XeFileSystem
{
	override uint getFreeSectors()
	{
		auto info = Info(_cache);
		return info.getFreeClusters() * info.getSectorsPerCluster();
	}

	override ulong getFreeBytes()
	{
		return cast(size_t) getFreeSectors() * _cache.getSectorSize();
	}

	override XeDirectory getRootDirectory()
	{
		return new SpartaRootDirectory(this);
	}

	override string getLabel()
	{
		return chomp(cast(string) _cache.request(1)[0x16 .. 0x1E].idup);
	}

	override void setLabel(string value)
	{
		assert (false);
	}

	override bool isValidName(string value)
	{
		return false;
	}

	override string adjustName(string value)
	{
		return value;
	}

	override string getType()
	{
		switch (Info(_cache).getVersion())
		{
		case FileSystemVersion.V1_1: return "SpartaDOS v1.1";
		case FileSystemVersion.V2_0: return "SpartaDOS v2.0";
		case FileSystemVersion.V2_1: return "SpartaDOS v2.1";
		default: return "";
		}
	}

	override void writeDosFiles(string dosVersion)
	{
		throw new Exception("Not implemented");
	}

	static this()
	{
		registerType("SPARTA", &tryOpen, &doCreate);
	}

private:
	SectorCache _cache;

	this (XeDisk disk)
	{
		_cache = new SectorCache(disk);
	}

	static SpartaFileSystem tryOpen(XeDisk disk)
	{
		auto bps = disk.getSectorSize(4);
		if (bps != 128 && bps != 256 && bps != 512)
			return null;

		{
			scope cache = new SectorCache(disk);
			auto info = Info(cache);
			if (info.getSectorSize() != bps)
				return null;
			auto ver = info.getVersion();
			auto magic = info.getMagic();			
			switch (ver)
			{
			case FileSystemVersion.V1_1, FileSystemVersion.V2_0:
				if (magic != 0x30804c)
					return null;
				break;
			case FileSystemVersion.V2_1:
				if (magic == 0x30804c && (bps == 128 || bps == 256))
					break;
				if (magic == 0x04404c && bps == 512)
					break;
				return null;
			default:
				return null;
			}
			if (info.getSectorsPerCluster() != 1)
				return null;
		}
		return new SpartaFileSystem(disk);
	}

	static SpartaFileSystem doCreate(XeDisk disk)
	{
		assert (false);
	}
}
