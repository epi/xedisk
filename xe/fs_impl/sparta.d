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
import xe.disk;
import xe.fs;
import xe.fs_impl.cache;
import xe.bytemanip;

private enum EntrySize = 23;

private enum EntryStatus : ubyte
{
	OpenForWriting = 0x80,
	Directory = 0x20,
	Deleted = 0x10,
	InUse = 0x08,
	Archive = 0x04,
	Hidden = 0x02,
	ReadOnly = 0x01
}

class SpartaFileSystem : XeFileSystem
{
	override uint getFreeSectors()
	{
		auto buf = _cache.request(1);
		return makeWord(buf[0xe], buf[0xd]);
	}

	override ulong getFreeBytes()
	{
		return cast(size_t) getFreeSectors() * _cache.getSectorSize();
	}

	override XeDirectory getRootDirectory()
	{
		assert (false);
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

	override string getType() { return "SpartaDOS"; }

	static this()
	{
		registerType("SPARTA", &tryOpen, &doCreate);
	}

private:
	this (XeDisk disk)
	{
		_cache = new SectorCache(disk);
	}

	static SpartaFileSystem tryOpen(XeDisk disk)
	{
		{
			scope cache = new SectorCache(disk);
			auto bps = cache.getSectorSize();
			if (bps != 128 && bps != 256 && bps != 512)
				return null;
			auto buf = cache.request(1);
			if (buf[6 .. 9] != [ cast(ubyte) 0x4c, 0x80, 0x30 ])
				return null;
		}
		return new SpartaFileSystem(disk);
	}

	static SpartaFileSystem doCreate(XeDisk disk)
	{
		assert (false);
	}

	SectorCache _cache;
}
