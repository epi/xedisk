// Written in the D programming language

/*
xfd.d - support for XFD disk images
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

module xe.disk_impl.xfd;

import std.exception;
import std.algorithm;
import std.typecons;
import xe.disk;
import xe.streams;

version(unittest)
{
	import xe.test;
}

private:

class XfdDisk : XeDisk
{
	override @property uint sectorCount() const { return _sectorCount; }
	override @property uint sectorSize() const { return _sectorSize; }
	override @property bool isWriteProtected() const { return false; }
	override @property void isWriteProtected(bool value)
	{
		throw new Exception("Write protection is not supported for XFD");
	}
	override @property string type() const { return "XFD"; }

	static this()
	{
		registerType("XFD", &openXfd, &createXfd);
	}

protected:
	override size_t doReadSector(uint sector, ubyte[] buffer)
	{
		auto len = min(buffer.length, doGetSizeOfSector(sector));
		return _stream.read(getOffsetOfSector(sector), buffer[0 .. len]);
	}

	override void doWriteSector(uint sector, in ubyte[] buffer)
	{
		auto len = min(buffer.length, doGetSizeOfSector(sector));
		_stream.write(getOffsetOfSector(sector), buffer[0 .. len]);
	}

	override uint doGetSizeOfSector(uint sector) const
	{
		return sector > 3 ? _sectorSize : 128;
	}

private:
	this(RandomAccessStream stream, uint sectorCount, uint sectorSize,
		XeDiskOpenMode mode)
	{
		_stream = stream;
		_sectorCount = sectorCount;
		_sectorSize = sectorSize;
		_openMode = mode;
	}

	size_t getOffsetOfSector(uint sector)
	{
		return (sector - 1) * _sectorSize;
	}

	static XfdDisk openXfd(RandomAccessStream stream, XeDiskOpenMode mode)
	{
		auto len = stream.getLength();
		switch (len)
		{
		case 128 * 720:
			return new XfdDisk(stream, 720, 128, mode);
		case 128 * 1040:
			return new XfdDisk(stream, 1040, 128, mode);
		case 256 * 720:
			return new XfdDisk(stream, 720, 256, mode);
		default:
			return null;
		}
	}

	static XfdDisk createXfd(RandomAccessStream stream, uint sectorCount,
		uint sectorSize)
	{
		auto par = tuple(sectorCount, sectorSize);
		if (par == tuple(720, 128) || par == tuple(1040, 128)
		 || par == tuple(720, 256))
		{
			size_t size = sectorCount * sectorSize;
			stream.write(size - 1, [cast(ubyte) 0]);
			return new XfdDisk(stream, sectorCount, sectorSize,
				XeDiskOpenMode.ReadWrite);
		}
		else
			throw new Exception(
				"Sorry, xedisk only supports single, medium and double " ~
				"density for XFD. " ~
				"This limitation is permanent and intentional.");
	}

	RandomAccessStream _stream;
	uint _sectorCount;
	uint _sectorSize;
}

unittest
{
	mixin(Test!"XfdDisk (1)");
	scope stream = new FileStream(File("testfiles/DOS25.XFD"));
	scope disk = XfdDisk.openXfd(stream, XeDiskOpenMode.ReadOnly);
	assert (disk);
	auto buf = new ubyte[257];
	assert (disk.sectorCount == 720);
	assert (disk.getSizeOfSector(1) == 128);
	assert (disk.getSizeOfSector(720) == 128);
	assertThrown(disk.readSector(0, buf));
	assertThrown(disk.readSector(721, buf));
	assertThrown(disk.writeSector(1, buf));
	assert (disk.readSector(1, buf) == 128);
	assert (disk.readSector(1, buf[0 .. 6]) == 6);
	assert (disk.readSector(2, buf) == 128);
	assert (disk.readSector(3, buf) == 128);
	assert (disk.readSector(4, buf) == disk.getSizeOfSector(4));
	assert (disk.readSector(720, buf) == disk.getSizeOfSector(720));
}

unittest
{
	mixin(Test!"XfdDisk (2)");
	enum sectors = 720;
	enum size = sectors * 128;
	{
		auto stream = new MemoryStream(new ubyte[0]);
		scope disk = XeDisk.create(stream, "XFD", sectors, 256);
		assert (disk.sectorCount == sectors);
		assert (disk.sectorSize == 256);
		assert (disk.getSizeOfSector(1) == 128);
	}
	{
		auto stream = new MemoryStream(new ubyte[0]);
		assertThrown (XeDisk.create(stream, "XFD", 721, 128));
	}
	{
		auto stream = new MemoryStream(new ubyte[0]);
		scope disk = XeDisk.create(stream, "XFD", sectors, 128);
		assert (disk.sectorCount == sectors);
		assert (stream.getLength() == size);
		assert (stream.array.length == size);
		assert (!disk.isWriteProtected());
		assertThrown(disk.isWriteProtected = false);
		assertThrown(disk.isWriteProtected = true);
		assert (!disk.isWriteProtected());
	}
}
