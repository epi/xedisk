// Written in the D programming language

/*
msdos.d - support for MS-DOS partition table
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

module xe.disk_impl.msdos;

import std.algorithm;
import std.bitmanip;
import std.exception;
import std.range;
import xe.bytemanip;
import xe.disk;
import xe.exception;
import xe.streams;

private:

version (unittest)
{
	import std.stdio;
	import streamimpl;
}

class MsdosPartitionAsDisk : XeDisk
{
	override uint getSectors() { return _numSectors; }

	override uint getSectorSize(uint sector = 0) { return 512; }

	override bool isWriteProtected() { return false; }

	override void setWriteProtected(bool value)
	{
		throw new XeException("Not implemented");
	}

	override string getType() const pure nothrow
	{
		return "MS-DOS partition (" ~ _typeString ~ ")";
	}

protected:
	override size_t doReadSector(uint sector, ubyte[] buffer)
	{
		auto len = min(buffer.length, 512);
		return _stream.read(streamPosition(sector), buffer[0 .. len]);
	}

	override void doWriteSector(uint sector, in ubyte[] buffer)
	{
		auto len = min(buffer.length, 512);
		_stream.write(streamPosition(sector), buffer[0 .. len]);
	}

private:
	size_t streamPosition(uint sector)
	{
		return (cast(size_t) _firstSector + sector - 1) * 512;
	}

	this(RandomAccessStream stream, uint firstSector, uint numSectors,
		string typeString, XeDiskOpenMode mode)
	{
		_stream = stream;
		_firstSector = firstSector;
		_numSectors = numSectors;
		_typeString = typeString;
		_openMode = mode;
	}

	RandomAccessStream _stream;
	uint _firstSector;
	uint _numSectors;
	string _typeString;
}

class MsdosPartition : XePartition
{
	override XeDisk getAsDisk(XeDiskOpenMode mode)
	{
		if (!_disk)
		{
			_disk = new MsdosPartitionAsDisk(_stream, _entry.lbaFirst,
				_entry.sectors, _partitionTypeStrings.get(_entry.type,
				"Unknown type"), mode);
		}
		return _disk;
	}

	override ulong getSectors()
	{
		return _entry.sectors;
	}

	override ulong getFirstSector() { return _entry.lbaFirst; }

private:
	this(RandomAccessStream st, PartitionEntry entry)
	{
		_stream = st;
		_entry = entry;
	}

	static immutable(string[ubyte]) _partitionTypeStrings;
	static this()
	{
		_partitionTypeStrings = [
			0x01: "DOS 12-bit FAT",
			0x04: "DOS 3.0+ 16-bit FAT (up to 32M)",
			0x05: "DOS 3.3+ Extended Partition",
			0x06: "DOS 3.31+ 16-bit FAT (over 32M)",
			0x07: "Windows NT NTFS / exFAT",
			0x0b: "WIN95 OSR2 FAT32",
			0x0c: "WIN95 OSR2 FAT32, LBA-mapped",
			0x0e: "WIN95: DOS 16-bit FAT, LBA-mapped",
			0x0f: "WIN95: Extended partition, LBA-mapped",
			0x5d: "KMK/JZ (IDEa) Span",
			0x5e: "R0l0Player 3",
			0x7f: "Atari Partition Table Span",
			0x82: "Linux swap",
			0x83: "Linux native partition",
			0x85: "Linux extended partition"
		];
	}

	RandomAccessStream _stream;
	PartitionEntry _entry;
	XeDisk _disk;
}

struct CHS
{
	ubyte[3] _data;

	@property ubyte head() { return _data[0]; }
	@property ushort cylinder() { return _data[2] | ((_data[1] & 0xc0) << 2); }
	@property ubyte sector() { return _data[1] & 0x3f; }
}

struct PartitionEntry
{
	ubyte    status;
	CHS      first;
	ubyte    type;
	CHS      last;
	ubyte[4] _lbaFirst;
	ubyte[4] _sectors;

	@property uint lbaFirst() { return littleEndianToNative!uint(_lbaFirst); }
	@property void lbaFirst(uint f) { _lbaFirst = nativeToLittleEndian(f); }

	@property uint sectors() { return littleEndianToNative!uint(_sectors); }
	@property void sectors(uint s) { _sectors = nativeToLittleEndian(s); }

	@property bool isEmpty()
	{
		return (status | lbaFirst | sectors | type) == 0;
	}
}

struct MBR
{
	ubyte[0x1BE]          _ignore;
	PartitionEntry[4]     entries;
	ubyte[2]              _signature;

	@property bool hasValidSignature()
	{
		return littleEndianToNative!ushort(_signature) == 0xAA55;
	}

	void setSignature()
	{
		_signature = nativeToLittleEndian(cast(ushort) 0xAA55);
	}
}

static assert(MBR.sizeof == 0x200);

union RawStruct(T, string name = "strukt") if (is(T == struct))
{
	mixin("T " ~ name ~ "; alias " ~ name ~ " this;");
	ubyte[T.sizeof] raw;
}

struct MsdosPartitionRange
{
	@property bool empty() { return _partition >= 4; }
	@property XePartition front() { return _pt.getPartition(_partition); }

	void popFront()
	{
		enforce(_partition < 4);
		do { ++_partition; }
		while (_partition < 4 && _pt._mbr.entries[_partition].isEmpty);
	}

	@property MsdosPartitionRange save()
	{
		return MsdosPartitionRange(_pt, _partition);
	}

private:
	this(MsdosPartitionTable pt, uint partition = 0)
	{
		_pt = pt;
		_partition = partition;
		while (_partition < 4 && _pt._mbr.entries[_partition].isEmpty)
			++_partition;
	}

	MsdosPartitionTable _pt;
	uint _partition;
}

class MsdosPartitionTable : XePartitionTable
{
	override string getType()
	{
		return "MS-DOS";
	}

	override ForwardRange!XePartition opSlice()
	{
		return inputRangeObject(MsdosPartitionRange(this, 0));
	}

private:
	static this()
	{
		registerType("MS-DOS", &tryOpen);
	}

	static MsdosPartitionTable tryOpen(RandomAccessStream stream)
	{
		auto result = new MsdosPartitionTable(stream);
		if (stream.read(0, result._mbr.raw) < result._mbr.raw.length)
			return null;
		if (result._mbr.hasValidSignature)
			return result;
		return null;
	}

	this(RandomAccessStream stream)
	{
		_stream = stream;
	}

	MsdosPartition getPartition(uint part)
	{
		assert(part < 4);
		if (!_partitions[part])
		{
			if (_mbr.entries[part].isEmpty)
				return null;
			_partitions[part] = new MsdosPartition(
				_stream, _mbr.entries[part]);
		}
		return _partitions[part];
	}

	RandomAccessStream _stream;
	RawStruct!MBR _mbr;
	MsdosPartition[4] _partitions;
}

unittest
{
	scope stream = new FileStream(File("testfiles/sda.mbr", "rb"));
	scope pt = MsdosPartitionTable.tryOpen(stream);
	assert(pt);
	assert(walkLength(pt[]) == 3);

	auto r = pt[];
	auto part = cast(MsdosPartition) r.front;
	assert(!part._entry.isEmpty);
	assert(part._entry.status == 0x80);
	assert(part._entry.first.cylinder == 0);
	assert(part._entry.first.head == 32);
	assert(part._entry.first.sector == 33);
	assert(part._entry.last.cylinder == 1023);
	assert(part._entry.last.head == 254);
	assert(part._entry.last.sector == 63);
	assert(part._entry.lbaFirst == 2048);
	assert(part._entry.sectors == 78123008);
	assert(part._entry.type == 0x83);

	r.popFront();
	part = cast(MsdosPartition) r.front;
	assert(!part._entry.isEmpty);
	assert(part._entry.status == 0x00);
	assert(part._entry.lbaFirst == 78125056);
	assert(part._entry.sectors == 7813120);
	assert(part._entry.type == 0x82);

	r.popFront();
	part = cast(MsdosPartition) r.front;
	assert(!part._entry.isEmpty);
	assert(part._entry.status == 0x00);
	assert(part._entry.lbaFirst == 85938176);
	assert(part._entry.sectors == 890832896);
	assert(part._entry.type == 0x83);

	writeln("MsdosPartitionTable (1) ok");
}
