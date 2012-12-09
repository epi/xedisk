// Written in the D programming language

/*
disk.d - common interface for manipulating disk images
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

module xe.disk;

debug import std.stdio;
import std.algorithm;
import std.exception;
import std.range;
import std.string;
import std.typecons;
import std.conv;
import xe.streams;
import xe.exception;

version(unittest)
{
	import xe.test;
}

///
enum XeDiskOpenMode
{
	ReadOnly, ///
	ReadWrite, ///
	ReadWriteDeferred,
}

///
class XeDisk
{
	///
	static XeDisk create(RandomAccessStream s, string type, uint totalSectors, uint bytesPerSector)
	{
		auto td = _types.get(toUpper(type), Nullable!TypeDelegates());
		if (td.isNull())
			throw new XeException(format("Unknown disk type `%s'", type));
		auto disk = td.doCreate(s, totalSectors, bytesPerSector);
		disk._openMode = XeDiskOpenMode.ReadWrite;
		return disk;
	}

	///
	static XeDisk open(RandomAccessStream s, XeDiskOpenMode mode = XeDiskOpenMode.ReadOnly)
	{
		foreach (type, td; _types)
		{
			// anything can be XFD...
			if (type == "XFD")
				continue;
			auto disk = td.get().tryOpen(s, mode);
			if (disk !is null)
				return disk;
		}
		// fallback - if XFD is supported, treat unrecognized file type as XFD
		auto td = _types.get("XFD", Nullable!TypeDelegates());
		if (td.isNull())
			throw new XeException("Could not recognize disk type");

		auto disk = td.get().tryOpen(s, mode);
		if (disk !is null)
			return disk;
		throw new XeException("Could not recognize disk type");
	}

	protected static void registerType(
		string type,
		XeDisk function(RandomAccessStream s, XeDiskOpenMode mode) tryOpen,
		XeDisk function(RandomAccessStream s, uint totalSectors, uint bytesPerSector) doCreate)
	{
		type = toUpper(type);
		_types[type] = TypeDelegates(tryOpen, doCreate);
		debug stderr.writefln("Registered disk type %s", type);
	}

	///
	final size_t readSector(uint sector, ubyte[] buffer)
	{
		enforce(sector >= 1 && sector <= this.getSectors(),
			new XeException(format("Sector number out of bounds (%s/%s)", sector, this.getSectors()), 139));
		auto result = doReadSector(sector, buffer);
		debug (SectorOp) writefln("sector %05d  read from disk   length %d", sector, result);
		enforce(result == min(buffer.length, this.getSectorSize(sector)), format("EOF while reading sector #%s", sector));
		return result;
	}

	///
	final void writeSector(uint sector, ubyte[] buffer)
	{
		enforce(sector >= 1 && sector <= this.getSectors(),
			new XeException(format("Sector number out of bounds (%s/%s)", sector, this.getSectors()), 139));
		enforce(_openMode != XeDiskOpenMode.ReadOnly, new XeException("Attempted to write to a disk opened read-only", 144));
		enforce(!isWriteProtected(), new XeException("Attempted to write to a write protected disk", 144));
		if (_openMode == XeDiskOpenMode.ReadWriteDeferred)
		{
			debug (SectorOp) writefln("sector %05d  deferred write   length %d", sector, len);
			_sectorsToWrite[sector] = buffer.idup[]; // only most recent write will be scheduled
		}
		else
		{
			debug (SectorOp) writefln("sector %05d  write to disk    length %d", sector, len);
			doWriteSector(sector, buffer);
		}
	}

	final bool isDirty()
	{
		return _sectorsToWrite.length > 0;
	}

	final void commit()
	{
		// TODO: serialize
		foreach (sector, data; _sectorsToWrite)
			doWriteSector(sector, data);
	}

	final void rollback()
	{
		_sectorsToWrite.clear();
	}

	///
	abstract uint getSectors();
	///
	abstract uint getSectorSize(uint sector = 0);
	///
	abstract bool isWriteProtected();
	///
	abstract void setWriteProtected(bool value);
	///
	abstract string getType() const pure nothrow;

	///
	final InputStream openBootLoader()
	{
		return new class(this) InputStream
		{
			this(XeDisk disk)
			{
				_disk = disk;
				_secbuf.length = 128;
				readNextSector();
				_secCount = _secbuf[1];
			}

			override size_t doRead(ubyte[] buffer)
			{
				size_t r;
				while (r < buffer.length)
				{
					size_t toCopy = min(_secbuf.length - _offset, buffer.length - r);
					buffer[r .. r + toCopy] = _secbuf[_offset .. _offset + toCopy];
					r += toCopy;
					_offset += toCopy;
					if (_offset >= _secbuf.length)
					{
						if (_sector == _secCount)
							return r;
						readNextSector();
					}
				}
				return r;
			}

			void readNextSector()
			{
				_sector++;
				_disk.readSector(_sector, _secbuf);
				_offset = 0;
			}

			XeDisk _disk;
			uint _secCount;
			ubyte[] _secbuf;
			uint _sector;
			uint _offset;
		};
	}

	///
	final OutputStream createBootLoader()
	{
		return new class(this) OutputStream
		{
			this(XeDisk disk)
			{
				_disk = disk;
				_secbuf.length = 128;
				_sector = 1;
			}

			override void doWrite(in ubyte[] buffer)
			{
				size_t w;
				while (w < buffer.length)
				{
					enforce(_sector <= _disk.getSectors(), "Disk full");
					size_t toCopy = min(_secbuf.length - _offset, buffer.length - w);
					_secbuf[_offset .. _offset + toCopy] = buffer[w .. w + toCopy];
					w += toCopy;
					_offset += toCopy;
					if (_offset >= _secbuf.length)
					{
						_disk.writeSector(_sector, _secbuf);
						_offset = 0;
						_secbuf[] = 0;
						_sector++;
					}
				}
				_disk.writeSector(_sector, _secbuf);
			}

			XeDisk _disk;
			ubyte[] _secbuf;
			uint _sector;
			uint _offset;
		};
	}

protected:
	XeDiskOpenMode _openMode;

	///
	abstract size_t doReadSector(uint sector, ubyte[] buffer);
	///
	abstract void doWriteSector(uint sector, in ubyte[] buffer);

private:
	struct TypeDelegates
	{
		XeDisk function(RandomAccessStream s, XeDiskOpenMode mode) tryOpen;
		XeDisk function(RandomAccessStream s, uint totalSectors, uint bytesPerSector) doCreate;
	}

	static Nullable!TypeDelegates[string] _types;

	immutable(ubyte)[][uint] _sectorsToWrite;
}

unittest
{
	mixin(Test!"XeDisk (1)");
	assertThrown(XeDisk.create(null, "Nonexistent disk type", 0, 0));
}

unittest
{
	mixin(Test!"XeDisk (2)");
	auto disk = new TestDisk("testfiles/MYDOS450.ATR", 16, 128, 3);
	auto buf1 = new ubyte[1024];
	auto buf2 = new ubyte[1024];
	scope istr = disk.openBootLoader();
	assert(384 == istr.read(buf1));
	assert(128 == disk.readSector(1, buf2));
	assert(128 == disk.readSector(2, buf2[128 .. 256]));
	assert(128 == disk.readSector(3, buf2[256 .. 384]));
	assert(buf1[0 .. 384] == buf2[0 .. 384]);
}

unittest
{
	mixin(Test!"XeDisk (3)");
	auto foo = cast(immutable(ubyte)[]) "foo";
	auto disk = new TestDisk(720, 128, 3);
	auto ostr = disk.createBootLoader();
	ostr.write(foo);
	auto buf = new ubyte[128];
	assert (disk.readSector(1, buf) == 128);
	assert (buf[0 .. 3] == foo);
	assert (buf[3 .. $] == new ubyte[125]);
	ostr.write(buf);
	ostr.write(buf);
	assert (disk.readSector(1, buf) == 128);
	assert (buf[0 .. 3] == foo);
	assert (buf[3 .. 6] == foo);
	assert (buf[6 .. $] == new ubyte[122]);
	assert (disk.readSector(2, buf) == 128);
	assert (buf[0 .. 3] == new ubyte[3]);
	assert (buf[3 .. 6] == foo);
	assert (buf[6 .. $] == new ubyte[122]);
}

class XePartition : XeDisk
{
	abstract ulong getPhysicalSectors();
	abstract ulong getFirstSector();
}

class XePartitionTable
{
	static XePartitionTable open(RandomAccessStream stream)
	{
		XePartitionTable[] found;
		foreach (t; _types)
		{
			auto pt = t.tryOpen(stream);
			if (pt)
				found ~= pt;
		}
		if (found.length == 0)
			return null;
		if (found.length == 1)
			return found[0];
		return new MultiTable(found);
	}

	protected static void registerType(
		string type,
		XePartitionTable function(RandomAccessStream s) tryOpen)
	{
		type = toUpper(type);
		_types[type] = TypeDelegates(tryOpen);
		debug stderr.writefln("Registered partition table type %s", type);
	}

	abstract ForwardRange!XePartition opSlice();
	abstract string getType();

private:
	struct TypeDelegates
	{
		XePartitionTable function(RandomAccessStream s) tryOpen;
	}

	static Nullable!TypeDelegates[string] _types;
}

private class MultiTable : XePartitionTable
{
	override ForwardRange!XePartition opSlice()
	{
		return inputRangeObject(_subtables.map!(pt => pt[])().joiner());
	}

	override string getType()
	{
		return "Combined(" ~
			std.string.join(map!(pt => pt.getType())(_subtables), ", ") ~ ")";
	}

private:
	this(XePartitionTable[] subtables)
	{
		_subtables = subtables;
	}

	XePartitionTable[] _subtables;
}

import std.stdio;
import xe.disk;
import std.algorithm;

private template TestImpl(string what)
	if (what == "Disk" || what == "Partition")
{
	mixin("private alias Xe" ~ what ~ " BaseType;");

	class TestImpl : BaseType
	{
		this(uint sectors, uint bytesPerSector, uint singleDensitySectors)
		{
			assert(sectors > 0);
			assert(singleDensitySectors <= sectors);
			_data = new ubyte[
				(sectors - singleDensitySectors) * bytesPerSector
				+ singleDensitySectors * 128];
			_sectors = sectors;
			_bytesPerSector = bytesPerSector;
			_singleDensitySectors = singleDensitySectors;
			_openMode = XeDiskOpenMode.ReadWrite;
		}

		unittest
		{
			mixin(Test!("Test" ~ what ~ " (1)"));
			auto d1 = new TestDisk(10, 256, 4);
			assert(d1._data.length == 2048);
			assert(d1._sectors == 10);
			assert(d1._bytesPerSector == 256);
			assert(d1._singleDensitySectors == 4);
		}

		/// Read contents of file from specified offset as a raw disk image
		/// data interpreted according to the specified bytesPerSector and
		/// singleDensitySectors parameters.
		this(string filename, ulong offset, uint bytesPerSector,
			uint singleDensitySectors)
		{
			auto f = File(filename);
			f.seek(offset);
			foreach (ubyte[] buf; f.byChunk(16384))
				_data ~= buf;
			assert(_data.length >= singleDensitySectors * 128);
			assert((_data.length - singleDensitySectors * 128) % bytesPerSector == 0,
				text((_data.length - singleDensitySectors * 128) % bytesPerSector));
			_sectors = cast(uint) (singleDensitySectors +
				(_data.length - singleDensitySectors * 128) / bytesPerSector);
			_bytesPerSector = bytesPerSector;
			_singleDensitySectors = singleDensitySectors;
			_openMode = XeDiskOpenMode.ReadWrite;
		}

		unittest
		{
			mixin(Test!("Test" ~ what ~ " (2)"));
			auto d1 = new TestDisk("testfiles/epi.atr", 16, 512, 0);
			assert(d1._data.length == 720 * 512);
			assert(d1._sectors == 720);
			assert(d1._bytesPerSector == 512);
			assert(d1._singleDensitySectors == 0);
		}

		override uint getSectors() { return _sectors; }

		override uint getSectorSize(uint sector = 0)
		{
			return (sector == 0 || sector > _singleDensitySectors)
				? _bytesPerSector : 128;
		}

		override bool isWriteProtected() { return false; }

		override void setWriteProtected(bool value)
		{
			throw new Exception("Not implemented");
		}

		override string getType() const pure nothrow { return "TEST"; }

		static if (what == "Partition")
		{
			override ulong getPhysicalSectors() { return _sectors; }
			override ulong getFirstSector() { return 1; }
		}

	protected:
		override size_t doReadSector(uint sector, ubyte[] buffer)
		{
			auto len = min(buffer.length, getSectorSize(sector));
			auto pos = streamPosition(sector);
			buffer[0 .. len] = _data[pos .. pos + len];
			return len;
		}

		override void doWriteSector(uint sector, in ubyte[] buffer)
		{
			auto len = min(buffer.length, getSectorSize(sector));
			auto pos = streamPosition(sector);
			_data[pos .. pos + len] = buffer[0 .. len];
		}

	private:
		uint streamPosition(uint sector)
		{
			if (sector > _singleDensitySectors)
				return _singleDensitySectors * 128
					+ (sector - _singleDensitySectors - 1) * _bytesPerSector;
			else
				return (sector - 1) * 128;
		}

		ubyte[] _data;
		uint _sectors;
		uint _bytesPerSector;
		uint _singleDensitySectors;
	}
}

alias TestImpl!"Partition" TestPartition;
alias TestImpl!"Disk" TestDisk;
