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

version (unittest)
{
	import std.stdio;
	import streamimpl;
}

private:

class XfdDisk : XeDisk
{
	override uint getSectors() { return _totalSectors; }
	override uint getSectorSize(uint) { return 128; }
	override bool isWriteProtected() { return false; }

	override void setWriteProtected(bool value)
	{
		if (value != false)
			throw new Exception("Write protection is not supported for XFD");
	}

	override string getType() const pure nothrow { return "XFD"; }

	static this()
	{
		registerType("XFD", &tryOpen, &doCreate);
	}

protected:
	override size_t doReadSector(uint sector, ubyte[] buffer)
	{
		auto len = min(buffer.length, 128);
		return _stream.read(streamPosition(sector), buffer[0 .. len]);
	}

	override void doWriteSector(uint sector, in ubyte[] buffer)
	{
		auto len = min(buffer.length, 128);
		_stream.write(streamPosition(sector), buffer[0 .. len]);
	}

private:
	this(RandomAccessStream s, uint totalSectors, XeDiskOpenMode mode)
	{
		_stream = s;
		_totalSectors = totalSectors;
		_openMode = mode;
	}

	size_t streamPosition(uint sector)
	{
		return (sector - 1) * 128;
	}

	// XFD is just a blob of raw data from the first byte of first sector of
	// disk. There's no metadata at all, file length may not be even aligned to
	// sector boundary, yet the file can still contain correct data.
	// File name extension may be wrong - people give the .XFD extension to
	// images in other formats, and conversely, other extensions to raw data
	// that can be interpreted as XFD. The recognition method applied here
	// first tries to match file length to a single or medium density disk.
	// If this fails, it assumes 128-byte sectors with a non-standard number
	// of sectors and opens the disk read-only to avoid data corruption.
	static XfdDisk tryOpen(RandomAccessStream s, XeDiskOpenMode mode)
	{
		auto len = s.getLength();
		switch (len)
		{
		case 128 * 720:
			return new XfdDisk(s, 720, mode);
		case 128 * 1040:
			return new XfdDisk(s, 1040, mode);
		default:
			return new XfdDisk(s, (cast(uint) len + 127) / 128,
				XeDiskOpenMode.ReadOnly);
		}
	}

	// OTOH, the creation of XFD images will only be allowed for single and
	// medium density. There's no valid reason to use XFDs whatsoever, as any
	// useful tool supports the ATR format, so that's not a big loss.
	static XfdDisk doCreate(RandomAccessStream s, uint totalSectors,
		uint bytesPerSector)
	{
		auto par = tuple(totalSectors, bytesPerSector);
		if (par == tuple(720, 128) || par == tuple(1040, 128))
		{
			size_t size = totalSectors * bytesPerSector;
			s.write(size - 1, [cast(ubyte) 0]);
			return new XfdDisk(s, totalSectors, XeDiskOpenMode.ReadWrite);
		}
		else
			throw new Exception(
				"Sorry, xedisk only supports single and medium density " ~
				"for XFD. This limitation is permanent and intentional.");
	}

	RandomAccessStream _stream;
	uint _totalSectors;
}

unittest
{
	scope stream = new FileStream(File("testfiles/DOS25.XFD"));
	scope disk = cast(XfdDisk) XeDisk.open(stream, XeDiskOpenMode.ReadOnly);
	assert (disk);
	auto buf = new ubyte[257];
	assert (disk.getSectors() == 720);
	assert (disk.getSectorSize(1) == 128);
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
	writeln("XfdDisk (1) ok");
}

unittest
{
	enum Sectors = 720;
	enum Size = Sectors * 128;

	scope stream = new MemoryStream(new ubyte[0]);
	assertThrown (XeDisk.create(stream, "XFD", Sectors, 256));
	assertThrown (XeDisk.create(stream, "XFD", 721, 128));
	scope disk = XeDisk.create(stream, "XFD", Sectors, 128);
	assert (disk.getSectors() == Sectors);
	assert (stream.getLength() == Size);
	assert (stream.array.length == Size);
	assert (!disk.isWriteProtected());
	disk.setWriteProtected(false);
	assertThrown(disk.setWriteProtected(true));
	assert (!disk.isWriteProtected());
	writeln("XfdDisk (2) ok");
}
