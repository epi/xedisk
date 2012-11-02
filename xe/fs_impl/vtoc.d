// Written in the D programming language

/*
vtoc.d - VTOC manipulations
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

module xe.fs_impl.vtoc;

import std.exception;
import std.string;
import std.array;
import std.range;
import std.algorithm;
import xe.disk;
import xe.fs_impl.cache;

struct BitLocation
{
	uint sec;
	uint byt;
	uint bit;
}

// TODO: redesign/optimize
struct Vtoc
{
	private SectorCache _cache;
	private BitLocation delegate(uint sector) _bitLocation;

	this(SectorCache cache, BitLocation delegate(uint sector) bitLocation)
	{
		_cache = cache;
		_bitLocation = bitLocation;
	}

	/// Returns: true if the sector is free
	bool opIndex(uint sector)
	{
		assert (_cache);
		auto loc = _bitLocation(sector);
		auto buf = _cache.request(loc.sec);
		return 0 != (buf[loc.byt] & loc.bit);
	}

	void opIndexAssign(bool value, uint sector)
	{
		assert (_cache);
		auto loc = _bitLocation(sector);
		auto buf = _cache.request(loc.sec);
		if (value)
			buf[loc.byt] |= loc.bit;
		else
			buf[loc.byt] &= ~loc.bit;
	}

	/// Find requested number of contiguous free sectors in VTOC and mark them occupied.
	/// Params:
	///  count = Requested number of sectors.
	/// Returns: # of first allocated sector.
	uint allocContiguous(uint count, uint start = 4, bool throwIfNotFound = true)
	{
		assert (_cache);
		uint found;
		start = max(_lastFound + 1, start);
		foreach (sector; chain(iota(start, _cache.getSectors() + 1), iota(4U, start)))
		{
			if (this[sector])
			{
				found++;
				if (found == count)
				{
					import std.stdio;
					foreach (i; sector - count + 1 .. sector + 1)
						this[i] = false;
					_lastFound = sector;
					return sector - count + 1;
				}
			}
			else
				found = 0;
		}
		if (throwIfNotFound)
			throw new Exception("Disk full");
		return 0;
	}

	private uint _lastFound = 3;
}
