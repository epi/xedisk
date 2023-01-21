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

import std.stdio;
import std.algorithm;
import std.exception;
import std.range;
import std.string;
import std.typecons;
import std.conv;
import xe.streams;
import xe.exception;
import xe.bytemanip;

version(unittest)
{
	import xe.test;
}

mixin(CTFEGenerateExceptionClass("InvalidSectorNumberException", 139,
	"Invalid sector number"));
mixin(CTFEGenerateExceptionClass("DiskReadOnlyException", 144,
	"Disk is read-only"));

///
alias XeDisk function(RandomAccessStream s, XeDiskOpenMode mode)
	DiskOpenFunc;
///
alias XeDisk function(RandomAccessStream s, uint sectorCount, uint sectorSize)
	DiskCreateFunc;

///
enum XeDiskOpenMode
{
	ReadOnly, ///
	ReadWrite, ///
	ReadWriteDeferred,
}

///
enum PercomFlags : ubyte
{
	None = 0x00,
	EightInch = 0x02,
	FM = 0x00,
	MFM = 0x04,
	HardDisk = 0x08
}

/// Big-endian
struct Percom
{
align(1):
	ubyte tracks;
	ubyte headSpeed;
	ubyte[2] sectorsPerTrack;
	union
	{
		ubyte sectorsPerTrackHigh;
		ubyte sides;
	}
	PercomFlags flags;
	ubyte[2] sectorSize;
	ubyte _unused1 = 0xff;
	ubyte[3] _unused2;
}

static assert(Percom.sizeof == 12);

///
class XeDisk
{
	///
	static XeDisk create(RandomAccessStream stream, string type,
		uint sectorCount, uint sectorSize)
	{
		auto td = _types.get(toUpper(type), TypeDelegates.init);
		enforce(td.doCreate !is null, format("Unknown disk type `%s'", type));
		auto disk = td.doCreate(stream, sectorCount, sectorSize);
		disk._openMode = XeDiskOpenMode.ReadWrite;
		return disk;
	}

	static XeDisk tryOpen(RandomAccessStream stream,
		XeDiskOpenMode mode = XeDiskOpenMode.ReadOnly)
	{
		foreach (type, td; _types)
		{
			auto disk = td.tryOpen(stream, mode);
			if (disk !is null)
				return disk;
		}
		return null;
	}

	///
	static XeDisk open(RandomAccessStream stream,
		XeDiskOpenMode mode = XeDiskOpenMode.ReadOnly)
	{
		return enforce(tryOpen(stream, mode), "Could not recognize disk type");
	}

	protected static void registerType(
		string type, DiskOpenFunc tryOpen, DiskCreateFunc doCreate)
	{
		type = toUpper(type);
		_types[type] = TypeDelegates(tryOpen, doCreate);
		debug stderr.writefln("Registered disk type %s", type);
	}

	///
	final size_t readSector(uint sector, ubyte[] buffer)
	{
		enforce!InvalidSectorNumberException(
			sector >= 1 && sector <= this.sectorCount,
			format("Sector number out of bounds (%s/%s)",
				sector, this.sectorCount));
		auto result = doReadSector(sector, buffer);
		debug(SectorOp) writefln(
			"sector %05d  read from disk   length %d", sector, result);
		debug enforce(result == min(buffer.length, doGetSizeOfSector(sector)),
			format("EOF while reading sector #%s", sector));
		return result;
	}

	///
	final void writeSector(uint sector, ubyte[] buffer)
	{
		enforce!InvalidSectorNumberException(
			sector >= 1 && sector <= this.sectorCount,
			format("Sector number out of bounds (%s/%s)",
				sector, this.sectorCount));
		enforce!DiskReadOnlyException(_openMode != XeDiskOpenMode.ReadOnly,
			"Attempted to write to a disk opened read-only");
		enforce!DiskReadOnlyException(!isWriteProtected,
			"Attempted to write to a write-protected disk");
		if (_openMode == XeDiskOpenMode.ReadWriteDeferred)
			assert(false);
		debug(SectorOp) writefln(
			"sector %05d  write to disk    length %d", sector, buffer.length);
		doWriteSector(sector, buffer);
	}

	///
	abstract @property uint sectorCount() const;
	///
	abstract @property uint sectorSize() const;
	///
	uint getSizeOfSector(uint sector) const
	{
		enforce!InvalidSectorNumberException(
			sector >= 1 && sector <= this.sectorCount,
			format("Sector number out of bounds (%s/%s)",
				sector, this.sectorCount));
		return doGetSizeOfSector(sector);
	}
	///
	abstract @property bool isWriteProtected() const;
	///
	abstract @property void isWriteProtected(bool value);
	///
	abstract @property string type() const;

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
					enforce(_sector <= _disk.sectorCount, "Disk full");
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

	@property Percom percom()
	{
		Percom result;
		result.sectorSize = ntobe(cast(ushort) sectorSize);
		if ((sectorCount == 720 && sectorSize == 128)
		 || (sectorCount == 1040 && sectorSize == 128)
		 || (sectorCount == 720 && sectorSize == 256)
		 || (sectorCount == 1440 && sectorSize == 256))
		{
			result.tracks = 40;
			result.sides = sectorCount > 720 ? 2 : 1;
			with (PercomFlags) result.flags =
				(sectorCount == 720 && sectorSize == 128) ? FM : MFM;
			result.sectorsPerTrack = ntobe(cast(ushort)
				(sectorCount == 1040 ? 26 : 18));
		}
		else
		{
			result.tracks = 1;
			result.flags = cast(PercomFlags)
				(PercomFlags.MFM | PercomFlags.HardDisk);
			result.sectorsPerTrack = ntobe(cast(ushort) sectorCount);
			result.sectorsPerTrackHigh = getByte!2(sectorCount);
		}
		return result;
	}

protected:
	XeDiskOpenMode _openMode;

	///
	abstract size_t doReadSector(uint sector, ubyte[] buffer);
	///
	abstract void doWriteSector(uint sector, in ubyte[] buffer);
	///
	abstract uint doGetSizeOfSector(uint sector) const;

private:
	struct TypeDelegates
	{
		DiskOpenFunc tryOpen;
		DiskCreateFunc doCreate;
	}

	static TypeDelegates[string] _types;

	immutable(ubyte)[][uint] _sectorCountToWrite;
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

///
class XePartition : XeDisk
{
	///
	abstract @property ulong physicalSectorCount() const;

	///
	abstract @property ulong firstPhysicalSector() const;
}

///
alias XePartitionTable function(RandomAccessStream s) PartitionOpenFunc;

///
class XePartitionTable
{
	///
	static XePartitionTable tryOpen(RandomAccessStream stream)
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

	///
	static XePartitionTable open(RandomAccessStream stream)
	{
		return enforce(tryOpen(stream),
			"Disk does not contain a valid partition table");
	}

	protected static void registerType(
		string type, PartitionOpenFunc tryOpen)
	{
		type = toUpper(type);
		_types[type] = TypeDelegates(tryOpen);
		debug stderr.writefln("Registered partition table type %s", type);
	}

	abstract ForwardRange!XePartition opSlice();
	abstract @property string type() const;

private:
	struct TypeDelegates
	{
		PartitionOpenFunc tryOpen;
	}

	static TypeDelegates[string] _types;
}

private class MultiTable : XePartitionTable
{
	override ForwardRange!XePartition opSlice()
	{
		return inputRangeObject(_subtables.map!(pt => pt[])().joiner());
	}

	override @property string type() const
	{
		return "Combined(" ~
			std.string.join(map!(pt => pt.type)(_subtables), ", ") ~ ")";
	}

private:
	this(XePartitionTable[] subtables)
	{
		_subtables = subtables;
	}

	XePartitionTable[] _subtables;
}

private template TestImpl(string what)
	if (what == "Disk" || what == "Partition")
{
	mixin("private alias Xe" ~ what ~ " BaseType;");

	class TestImpl : BaseType
	{
		this(uint sectors, uint sectorSize, uint singleDensitySectors)
		{
			assert(sectors > 0);
			assert(singleDensitySectors <= sectors);
			_data = new ubyte[
				(sectors - singleDensitySectors) * sectorSize
				+ singleDensitySectors * 128];
			_sectorCount = sectors;
			_sectorSize = sectorSize;
			_singleDensitySectors = singleDensitySectors;
			_openMode = XeDiskOpenMode.ReadWrite;
		}

		unittest
		{
			mixin(Test!("Test" ~ what ~ " (1)"));
			auto d1 = new TestDisk(10, 256, 4);
			assert(d1._data.length == 2048);
			assert(d1._sectorCount == 10);
			assert(d1._sectorSize == 256);
			assert(d1._singleDensitySectors == 4);
		}

		/// Read contents of file from specified offset as a raw disk image
		/// data interpreted according to the specified sectorSize and
		/// singleDensitySectors parameters.
		this(string filename, ulong offset, uint sectorSize,
			uint singleDensitySectors)
		{
			auto f = File(filename);
			f.seek(offset);
			foreach (ubyte[] buf; f.byChunk(16384))
				_data ~= buf;
			assert(_data.length >= singleDensitySectors * 128);
			assert((_data.length - singleDensitySectors * 128) % sectorSize == 0,
				text((_data.length - singleDensitySectors * 128) % sectorSize));
			_sectorCount = cast(uint) (singleDensitySectors +
				(_data.length - singleDensitySectors * 128) / sectorSize);
			_sectorSize = sectorSize;
			_singleDensitySectors = singleDensitySectors;
			_openMode = XeDiskOpenMode.ReadWrite;
		}

		unittest
		{
			mixin(Test!("Test" ~ what ~ " (2)"));
			auto d1 = new TestDisk("testfiles/epi.atr", 16, 512, 0);
			assert(d1._data.length == 720 * 512);
			assert(d1._sectorCount == 720);
			assert(d1._sectorSize == 512);
			assert(d1._singleDensitySectors == 0);
		}

		override @property uint sectorCount() const { return _sectorCount; }

		override @property uint sectorSize() const { return _sectorSize; }

		override @property bool isWriteProtected() const { return false; }

		override @property void isWriteProtected(bool value)
		{
			throw new Exception("Not implemented");
		}

		override @property string type() const { return "TEST"; }

		static if (what == "Partition")
		{
			override @property ulong physicalSectorCount() const
			{
				return _sectorCount;
			}
			override @property ulong firstPhysicalSector() const { return 1; }
		}

	protected:
		override size_t doReadSector(uint sector, ubyte[] buffer)
		{
			auto len = min(buffer.length, doGetSizeOfSector(sector));
			auto pos = getOffsetOfSector(sector);
			buffer[0 .. len] = _data[pos .. pos + len];
			return len;
		}

		override void doWriteSector(uint sector, in ubyte[] buffer)
		{
			auto len = min(buffer.length, doGetSizeOfSector(sector));
			auto pos = getOffsetOfSector(sector);
			_data[pos .. pos + len] = buffer[0 .. len];
		}

		override uint doGetSizeOfSector(uint sector) const
		{
			return sector > _singleDensitySectors ? _sectorSize : 128;
		}

	private:
		uint getOffsetOfSector(uint sector)
		{
			if (sector > _singleDensitySectors)
				return _singleDensitySectors * 128
					+ (sector - _singleDensitySectors - 1) * _sectorSize;
			else
				return (sector - 1) * 128;
		}

		ubyte[] _data;
		uint _sectorCount;
		uint _sectorSize;
		uint _singleDensitySectors;
	}
}

alias TestImpl!"Partition" TestPartition;
alias TestImpl!"Disk" TestDisk;
