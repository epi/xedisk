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

version (unittest)
{
	import std.stdio;
	import streamimpl;
}

class AtrDisk : XeDisk
{
	override uint getSectors() { return _totalSectors; }
	override uint getSectorSize(uint sector = 0)
	{
		return (sector == 0 || sector > _singleDensitySectors)
			? _bytesPerSector : 128;
	}
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
		auto len = min(buffer.length, getSectorSize(sector));
		return _stream.read(streamPosition(sector), buffer[0 .. len]);
	}

	override void doWriteSector(uint sector, in ubyte[] buffer)
	{
		auto len = min(buffer.length, getSectorSize(sector));
		_stream.write(streamPosition(sector), buffer[0 .. len]);
	}

private:
	this(RandomAccessStream s, uint totalSectors,
		uint singleDensitySectors, uint bytesPerSector,
		bool writeProtected, XeDiskOpenMode mode)
	{
		_stream = s;
		_totalSectors = totalSectors;
		_singleDensitySectors = singleDensitySectors;
		_bytesPerSector = bytesPerSector;
		_writeProtected = writeProtected;
		_openMode = mode;
	}

	uint streamPosition(uint sector)
	{
		if (sector > _singleDensitySectors)
			return HeaderLength
				+ _singleDensitySectors * 128
				+ (sector - _singleDensitySectors - 1) * _bytesPerSector;
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
		if (bytesPerSector != 128 && bytesPerSector != 256
		 && bytesPerSector != 512)
			return null;
		uint totalSectors;
		uint singleDensitySectors;
		if (bytesPerSector > 128 && size % bytesPerSector == 128)
		{
			totalSectors = (size + 3 * (bytesPerSector - 128)) / bytesPerSector;
			singleDensitySectors = 3;
		}
		else if (size % bytesPerSector == 0)
		{
			totalSectors = size / bytesPerSector;
			singleDensitySectors = 0;
		}
		bool writeProtected = header[15] & 1;
		return new AtrDisk(s, totalSectors, singleDensitySectors,
			bytesPerSector, writeProtected, mode);
	}

	static AtrDisk doCreate(RandomAccessStream s,
		uint totalSectors, uint bytesPerSector)
	{
		uint singleDensitySectors;
		switch (bytesPerSector)
		{
		case 128, 256: singleDensitySectors = 3; break;
		case 512:      break;
		default:       throw new Exception(
			"Sector size must be 128, 256 or 512 bytes");
		}
		uint size = ((totalSectors - singleDensitySectors) * bytesPerSector
			+ singleDensitySectors * 128) / Paragraph;
		s.write(0, makeHeader(totalSectors, bytesPerSector));
		s.write(HeaderLength + size * Paragraph - 1, [cast(ubyte) 0]);
		return new AtrDisk(s, totalSectors, singleDensitySectors,
			bytesPerSector, false, XeDiskOpenMode.ReadWrite);
	}

	static auto makeHeader(uint sectors, uint sectorSize,
		bool writeProtected = false)
	out(result)
	{
		assert(result.length == 16);
	}
	body
	{
		uint size = HeaderLength + 3 * 128 + (sectors - 3) * sectorSize;
		uint npar = (size - HeaderLength) / Paragraph;
		assert((size - HeaderLength) % Paragraph == 0);

		return cast(ubyte[]) [
			0x96, 0x02, getByte!0(npar), getByte!1(npar),
			getByte!0(sectorSize), getByte!1(sectorSize),
			getByte!2(npar),
			0, 0, 0, 0, 0, 0, 0, 0, writeProtected ? 1 : 0 ];
	}

	RandomAccessStream _stream;
	uint _totalSectors;
	uint _singleDensitySectors;
	uint _bytesPerSector;
	bool _writeProtected;

	enum HeaderLength = 16;
	enum Paragraph = 16;
}

unittest
{
	assert(AtrDisk.makeHeader(20720, 256, true) == cast(ubyte[]) [
		0x96, 0x02, 0xe8, 0x0e, 0x00, 0x01, 0x05, 0x00,
		0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01 ]);
	writeln("AtrDisk.makeHeader (1) ok");
}

unittest
{
	enum Sectors = 720;
	enum SectorSize = 192;
	enum Size = 3 * 128 + (Sectors - 3) * SectorSize;
	{
		scope stream = new MemoryStream(AtrDisk.makeHeader(
			Sectors, SectorSize) ~ new ubyte[Size]);
		assert (!AtrDisk.tryOpen(stream, XeDiskOpenMode.ReadOnly));
	}
	writeln("AtrDisk.tryOpen (1) ok");
}

unittest
{
	{
		scope stream = new MemoryStream(new ubyte[0]);
		scope disk = AtrDisk.doCreate(stream, 65535, 512);
		assert (stream.getLength() == 65535 * 512 + 16);
		assert (disk.getSectors() == 65535);
		assert (disk.getSectorSize() == 512);
	}
	{
		scope stream = new MemoryStream(new ubyte[0]);
		assertThrown(AtrDisk.doCreate(stream, 720, 129));
		assert (stream.getLength() == 0);
	}
	writeln("AtrDisk.doCreate (1) ok");
}

unittest
{
	scope stream = new FileStream(File("testfiles/MYDOS450.ATR"));
	scope disk = XeDisk.open(stream, XeDiskOpenMode.ReadOnly);
	auto buf = new ubyte[257];
	assert (disk.getSectors() == 720);
	assert ((cast(AtrDisk) disk)._singleDensitySectors == 0);
	assert (disk.getSectorSize(1) == 128);
	assert (disk.getSectorSize(4) == 128);
	assert (disk.getSectorSize(720) == 128);
	assertThrown(disk.readSector(0, buf));
	assertThrown(disk.readSector(721, buf));
	assertThrown(disk.writeSector(1, buf));
	assert (disk.readSector(1, buf) == 128);
	assert (disk.readSector(1, buf[0 .. 6]) == 6);
	assert (disk.readSector(2, buf) == 128);
	assert (disk.readSector(3, buf) == 128);
	assert (disk.readSector(4, buf) == disk.getSectorSize(4));
	assert (disk.readSector(720, buf) == disk.getSectorSize(720));
	writeln("AtrDisk (1) ok");
}

unittest
{
	enum Sectors = 720;
	enum Size = AtrDisk.HeaderLength + 3 * 128 + (Sectors - 3) * 256;
	enum NPar = (Size - AtrDisk.HeaderLength) / AtrDisk.Paragraph;

	scope stream = new MemoryStream(new ubyte[0]);
	{
		scope disk = XeDisk.create(stream, "ATR", Sectors, 256);
		assert (disk.getSectors() == Sectors);
		assert ((cast(AtrDisk) disk)._singleDensitySectors == 3);
		assert (stream.getLength() == Size);
		assert (stream.array.length == Size);
		auto buf = new ubyte[AtrDisk.HeaderLength];
		assert (stream.read(0, buf) == AtrDisk.HeaderLength);
		assert (buf[] == AtrDisk.makeHeader(Sectors, 256));
		assert (!disk.isWriteProtected());
		disk.setWriteProtected(true);
		assert (stream.read(0, buf) == AtrDisk.HeaderLength);
		assert (buf[] == AtrDisk.makeHeader(Sectors, 256, true));
		assert (disk.isWriteProtected());
	}
	{
		scope disk = XeDisk.open(stream, XeDiskOpenMode.ReadOnly);
		assert (disk.isWriteProtected());
	}

	writeln("AtrDisk (2) ok");
}

unittest
{
	scope stream = new FileStream(File("testfiles/epi.atr"));
	scope disk = XeDisk.open(stream);
	assert (disk.getSectors() == 720);
	assert ((cast(AtrDisk) disk)._singleDensitySectors == 0);
	assert (disk.getSectorSize(1) == 512);
	assert (disk.getSectorSize(4) == 512);
	assert (disk.getSectorSize(720) == 512);
	writeln("AtrDisk (3) ok");
}
