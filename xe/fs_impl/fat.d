// Written in the D programming language

/*
fat.d - read minimum info about a FAT partition
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

module xe.fs_impl.fat;

import std.string;
import std.algorithm;
import std.exception;
import std.datetime;
import xe.disk;
import xe.fs;
import xe.fs_impl.cache;
import xe.bytemanip;
import xe.streams;

class FatFileSystem : XeFileSystem
{
	override uint getFreeSectors() { return 0; }
	override ulong getFreeBytes() { return 0; }

	override XeDirectory getRootDirectory()
	{
		throw new Exception("Not implemented");
	}

	override string getLabel()
	{
		return chomp(cast(string) _cache.request(1)[0x47 .. 0x47 + 11].idup);
	}

	override void setLabel(string value)
	{
		throw new Exception("Not implemented");
	}

	override bool isValidName(string value) { return false; }
	override string adjustName(string value) { return value; }
	override string getType() { return "FAT"; }

	override void writeDosFiles(string dosVersion)
	{
		throw new Exception("Not implemented");
	}

	static this()
	{
		registerType("FAT", &tryOpen, &doCreate);
	}

private:
	SectorCache _cache;

	this (XeDisk disk)
	{
		_cache = new SectorCache(disk);
	}

	static FatFileSystem tryOpen(XeDisk disk)
	{
		auto bps = disk.getSectorSize(4);
		if (bps != 512)
			return null;

		{
			scope cache = new SectorCache(disk);
			auto sec = cache.request(1);
			if (sec[0x1fe .. 0x200] != [ 0x55, 0xaa])
				return null;
		}
		return new FatFileSystem(disk);
	}

	static FatFileSystem doCreate(XeDisk disk)
	{
		assert (false);
	}
}
