// Written in the D programming language

/*
idea.d - implementation of partition table for KMK/JZ IDE (IDEa) interface
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

module xe.disk_impl.idea;

import std.algorithm;
import std.bitmanip;
import std.exception;
import std.range;
import xe.bytemanip;
import xe.disk;
import xe.exception;
import xe.streams;

private:

version(unittest)
{
	import xe.test;
}

class IdeaPartition : XePartition
{
	override uint getSectorSize(uint sector = 0)
	{
		if (_pi.clsize == PartitionSectorSize.B256)
		{
			if (sector >= 1 && sector <= 3)
				return 128;
			else
				return 256;
		}
		else if (_pi.clsize == PartitionSectorSize.B512)
		{
			return 512;
		}
		else
			assert(false);
	}

	override bool isWriteProtected()
	{
		return (_pi.status & PartitionStatus.ReadOnly) != 0;
	}

	override void setWriteProtected(bool value)
	{
		throw new XeException("Not implemented");
	}

	override string getType() const pure nothrow { return "IDEa partition"; }

	override uint getSectors()
	{
		return _pi.len;
	}

	override ulong getPhysicalSectors()
	{
		if (_pi.clsize == PartitionSectorSize.B256)
			return (_pi.len + 1) / 2;
		else if (_pi.clsize == PartitionSectorSize.B512)
			return _pi.len;
		assert(false);
	}

	override ulong getFirstSector() { return _pi.begin + 1; }

protected:
	override size_t doReadSector(uint sector, ubyte[] buffer)
	{
		auto len = min(buffer.length, getSectorSize(sector));
		auto res = _stream.read(streamPosition(sector), buffer[0 .. len]);
		return res;
	}

	override void doWriteSector(uint sector, in ubyte[] buffer)
	{
		auto len = min(buffer.length, getSectorSize(sector));
		_stream.write(streamPosition(sector), buffer[0 .. len]);
	}

private:
	this(RandomAccessStream st, PartitionInfo pi)
	{
		_stream = st;
		_pi = pi;
	}

	size_t streamPosition(uint sector)
	{
		if (_pi.clsize == PartitionSectorSize.B256)
			return (_pi.begin + 1) * 512 + (sector ^ 1) * 256;
		else if (_pi.clsize == PartitionSectorSize.B512)
			return (_pi.begin + sector) * 512;
		assert(false);
	}

	RandomAccessStream _stream;
	PartitionInfo _pi;
}

enum PartitionStatus : ubyte
{
	Exists = 0x80,
	ReadOnly = 0x20,
	OnSlave = 0x10,
}

enum PartitionSectorSize : ubyte
{
	B256 = 0x00,
	B512 = 0x80,
}

struct PartitionInfo
{
	PartitionStatus status;
	ubyte index;
	uint begin;
	uint len;
	PartitionSectorSize clsize;
}

struct PartitionTableData
{
	PartitionStatus[0x10] pstats;
	ubyte[0x10]           pindex;
	ubyte[0x10]           pbeglo;
	ubyte[0x10]           pbegmd;
	ubyte[0x10]           pbeghi;
	ubyte[0x10]           plenlo;
	ubyte[0x10]           plenmd;
	ubyte[0x10]           plenhi;
	ubyte[0x02]           pmagic;
	ubyte[0xAC - 0x82]    pign1;
	PartitionSectorSize[0x10] pclsize;
	ubyte[0x200 - 0xBC]   pign2;

	@property ushort magic() { return littleEndianToNative!ushort(pmagic); }
	@property void magic(ushort m) { pmagic = nativeToLittleEndian(m); }

	PartitionInfo opIndex(size_t i)
	{
		enforce(i < 16, "Invalid partition number");
		return PartitionInfo(pstats[i], pindex[i],
			makeWord(pbeghi[i], pbegmd[i], pbeglo[i]),
			makeWord(plenhi[i], plenmd[i], plenlo[i]),
			pclsize[i]);
	}

	void opIndex(PartitionInfo pi, size_t i)
	{
		enforce(i < 16, "Invalid partition number");
		pstats[i] = pi.status;
		pindex[i] = pi.index;
		pbeglo[i] = getByte!0(pi.begin);
		pbegmd[i] = getByte!1(pi.begin);
		pbeghi[i] = getByte!2(pi.begin);
		plenlo[i] = getByte!0(pi.len);
		plenmd[i] = getByte!1(pi.len);
		plenhi[i] = getByte!2(pi.len);
		pclsize[i] = pi.clsize;
	}

	bool isValid(uint i)
	{
		return (pstats[i] & PartitionStatus.Exists)
		   && !(pstats[i] & PartitionStatus.OnSlave)
		   &&  (pindex[i] == 0)
		   && (pclsize[i] == PartitionSectorSize.B256
		    || pclsize[i] == PartitionSectorSize.B512);
	}
}

static assert (PartitionTableData.sizeof == 0x200);

union RawStruct(T, string name = "strukt") if (is(T == struct))
{
	mixin("T " ~ name ~ "; alias " ~ name ~ " this;");
	ubyte[T.sizeof] raw;
}

struct IdeaPartitionRange
{
	@property bool empty() { return _partition >= 16; }
	@property XePartition front() { return _pt.getPartition(_partition); }

	void popFront()
	{
		enforce(_partition < 16);
		do { ++_partition; }
		while (_partition < 16 && !_pt._data.isValid(_partition));
	}

	@property IdeaPartitionRange save()
	{
		return IdeaPartitionRange(_pt, _partition);
	}

private:
	this(IdeaPartitionTable pt, uint partition = 0)
	{
		_pt = pt;
		_partition = partition;
		while (_partition < 16 && !_pt._data.isValid(_partition))
			++_partition;
	}

	IdeaPartitionTable _pt;
	uint _partition;
}

class IdeaPartitionTable : XePartitionTable
{
	override string getType()
	{
		return "IDEa";
	}

	override ForwardRange!XePartition opSlice()
	{
		return inputRangeObject(IdeaPartitionRange(this, 0));
	}

private:
	static this()
	{
		registerType("IDEa", &tryOpen);
	}

	static IdeaPartitionTable tryOpen(RandomAccessStream stream)
	{
		auto result = new IdeaPartitionTable(stream);
		if (stream.read(0, result._data.raw) < result._data.raw.length)
			return null;
		if (result._data.magic == 0x728)
			return result;
		return null;
	}

	this(RandomAccessStream stream)
	{
		_stream = stream;
	}

	IdeaPartition getPartition(uint part)
	{
		if (!_partitions[part])
			_partitions[part] = new IdeaPartition(_stream, _data[part]);
		return _partitions[part];
	}

	RandomAccessStream _stream;
	RawStruct!PartitionTableData _data;
	IdeaPartition[16] _partitions;
}

unittest
{
	mixin(Test!"IdeaPartitionTable (1)");
	scope stream = new FileStream(File("testfiles/sdc.mbr", "rb"));
	scope pt = IdeaPartitionTable.tryOpen(stream);
	assert(pt);
	assert(walkLength(pt[]) == 6);
	auto r = pt[];
	auto part = cast(IdeaPartition) r.front;
	assert(part._pi.begin == 0);
	assert(part._pi.len == 65535);
	assert(part._pi.clsize == PartitionSectorSize.B256);
	r.popFront();
	part = cast(IdeaPartition) r.front;
	assert(part._pi.begin == 32768);
	assert(part._pi.len == 65535);
	assert(part._pi.clsize == PartitionSectorSize.B512);
}
