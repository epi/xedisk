// Written in the D programming language

/*
atr.d - support for ATR disk images
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

module xe.disk_impl.atr;

import std.exception;
import std.algorithm;
import xe.disk;
import xe.streams;
import xe.bytemanip;

class AtrDisk : XeDisk
{
	override uint getSectors() { return _totalSectors; }
	override uint getSectorSize() { return _bytesPerSector; }
	override bool isWriteProtected() { return _writeProtected; }

	override void setWriteProtected(bool value)
	{
		auto header = new ubyte[HeaderLength];
		enforce(_stream.read(0, header) == HeaderLength);
		header[15] = (header[15] & 0xfe) | (value ? 1 : 0);
		_stream.write(0, header);
		_writeProtected = value;
	}

	override string getType() const pure nothrow { return "ATR"; }

	static this()
	{
		registerType("ATR", &tryOpen, &doCreate);
	}

protected:
	override size_t doReadSector(uint sector, ubyte[] buffer)
	{
		auto len = min(buffer.length, sector > 3 ? _bytesPerSector : 128);
		return _stream.read(streamPosition(sector), buffer[0 .. len]);
	}

	override void doWriteSector(uint sector, in ubyte[] buffer)
	{
		import std.stdio;
		auto len = min(buffer.length, sector > 3 ? _bytesPerSector : 128);
		_stream.write(streamPosition(sector), buffer[0 .. len]);
	}

private:
	this(RandomAccessStream s, uint totalSectors, uint bytesPerSector,
		bool writeProtected, XeDiskOpenMode mode)
	{
		_stream = s;
		_totalSectors = totalSectors;
		_bytesPerSector = bytesPerSector;
		_writeProtected = writeProtected;
		_openMode = mode;
	}

	uint streamPosition(uint sector)
	{
		if (sector > 3)
			return HeaderLength + 3 * 128 + (sector - 4) * _bytesPerSector;
		else
			return HeaderLength + (sector - 1) * 128;
	}

	static AtrDisk tryOpen(RandomAccessStream s, XeDiskOpenMode mode)
	{
		auto header = new ubyte[HeaderLength];
		if (s.read(0, header) != HeaderLength
		 || makeWord(header[1], header[0]) != 0x0296)
			return null;
		uint size = makeWord(header[6], header[3], header[2]) * Paragraph;
		uint bytesPerSector = makeWord(header[5], header[4]);
		uint totalSectors = (size + 3 * (bytesPerSector - 128)) / bytesPerSector;
		bool writeProtected = header[15] & 1;
		return new AtrDisk(s, totalSectors, bytesPerSector, writeProtected, mode);
	}

	static AtrDisk doCreate(RandomAccessStream s,
		uint totalSectors, uint bytesPerSector)
	{
		uint size = ((totalSectors - 3) * bytesPerSector + 128 * 3) / Paragraph;
		ubyte[] header = [
			0x96, 0x02,
			getByte!0(size), getByte!1(size),
			getByte!0(bytesPerSector), getByte!1(bytesPerSector),
			getByte!2(size),
			0, 0, 0, 0, 0, 0, 0, 0, 0 ];
		assert(header.length == 16);
		s.write(0, header);
		s.write(HeaderLength + size * Paragraph - 1, [cast(ubyte) 0]);
		return new AtrDisk(s, totalSectors, bytesPerSector,
			false, XeDiskOpenMode.ReadWrite);
	}

	RandomAccessStream _stream;
	uint _bytesPerSector;
	uint _totalSectors;
	bool _writeProtected;

	enum HeaderLength = 16;
	enum Paragraph = 16;
}

unittest
{
	import std.stdio;
	import streamimpl;

	auto stream = new FileStream(File("testfiles/MYDOS450.ATR"));
	auto disk = XeDisk.open(stream, XeDiskOpenMode.ReadOnly);
	auto buf = new ubyte[257];
	assert (disk.getSectors() == 720);
	assert (disk.getSectorSize() == 128);
	assertThrown(disk.readSector(0, buf));
	assertThrown(disk.readSector(721, buf));
	assertThrown(disk.writeSector(1, buf));
	assert (disk.readSector(1, buf) == 128);
	assert (disk.readSector(1, buf[0 .. 6]) == 6);
	assert (disk.readSector(2, buf) == 128);
	assert (disk.readSector(3, buf) == 128);
	assert (disk.readSector(4, buf) == disk.getSectorSize());
	assert (disk.readSector(720, buf) == disk.getSectorSize());
	clear(stream);
	writeln("AtrDisk (1) ok");
}

unittest
{
	import std.stdio;
	import streamimpl;

	enum Sectors = 720;
	enum Size = AtrDisk.HeaderLength + 3 * 128 + (Sectors - 3) * 256;
	enum NPar = (Size - AtrDisk.HeaderLength) / AtrDisk.Paragraph;

	scope stream = new MemoryStream(new ubyte[0]);
	{
		scope disk = XeDisk.create(stream, "ATR", Sectors, 256);
		assert (disk.getSectors() == Sectors);
		assert (stream.getLength() == Size);
		assert (stream.array.length == Size);
		auto buf = new ubyte[AtrDisk.HeaderLength];
		assert (stream.read(0, buf) == AtrDisk.HeaderLength);
		assert (buf[] == cast(ubyte[]) [
			0x96, 0x02, getByte!0(NPar), getByte!1(NPar), 0, 1, getByte!2(NPar),
			0, 0, 0, 0, 0, 0, 0, 0, 0 ]);
		assert (!disk.isWriteProtected());
		disk.setWriteProtected(true);
		assert (stream.read(0, buf) == AtrDisk.HeaderLength);
		assert (buf[] == cast(ubyte[]) [
			0x96, 0x02, getByte!0(NPar), getByte!1(NPar), 0, 1, getByte!2(NPar),
			0, 0, 0, 0, 0, 0, 0, 0, 1 ]);
		assert (disk.isWriteProtected());
	}
	{
		scope disk = XeDisk.open(stream, XeDiskOpenMode.ReadOnly);
		assert (disk.isWriteProtected());
	}

	writeln("AtrDisk (2) ok");
}
