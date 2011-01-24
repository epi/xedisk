/*	vtoc - common VTOC (Volume Table of Contents,
	also called `bitmap') operations.

	Author: Adrian Matoga epi@atari8.info
	
	Poetic License:

	This work 'as-is' we provide.
	No warranty express or implied.
	We've done our best,
	to debug and test.
	Liability for damages denied.

	Permission is granted hereby,
	to copy, share, and modify.
	Use as is fit,
	free or for profit.
	These rights, on this notice, rely.
*/

import std.exception;
import std.string;
import std.conv;
import std.range;

import image;

/// Interface for dealing with VTOC.
interface Vtoc
{
	/// Compute location (_sector # and byte offset inside the _sector)
	/// of byte containing information on whether the sector is occupied.
	/// Returns: location within VTOC
	@property Location sectorLocation(uint sector);

	/// Returns: byte value in which the only bit set is the one corresponding
	/// to the sector within the byte determined by sectorLocation;
	@property ubyte sectorBitMask(uint sector);

	/// Returns: underlying disk image.
	@property BufferedImage image();

	/// Returns: true if sector is free, false if it is occupied.
	final bool opIndex(uint sector)
	{
		enforce(sector >= 0 && sector <= image.totalSectors, "Sector # out of range (" ~ to!string(sector) ~ ")");
		auto loc = sectorLocation(sector);
		ubyte b = image[loc.sector][loc.offset % image.bytesPerSector];
		return !!(b & sectorBitMask(sector));
	}

	/// Mark sector as _free or occupied.
	/// Params:
	///  free = true marks _sector as _free, false marks it as occupied.
	/// Returns: free.
	final void opIndexAssign(bool free, uint sector)
	{
		enforce(sector >= 0 && sector <= image.totalSectors, "Sector # out of range (" ~ to!string(sector) ~ ")");
		auto loc = sectorLocation(sector);
		ubyte b = image[loc.sector][loc.offset % image.bytesPerSector];
		auto mask = sectorBitMask(sector);
		b &= ~mask;
		if (free)
			b |= mask;
		image[loc.sector][loc.offset] = b;
	}

	/// Find free sectors in VTOC starting from the first full-sized sector in the underlying disk image.
	/// Params:
	///  count = Requested number of sectors.
	/// Returns: Array containing numbers of subsequent sectors. It may be shorter than requested number of sectors,
	/// in which case you will usually report a "Disk full" error.
	final uint[] findFreeSectors(uint count)
	{
		auto result = new uint[count];
		size_t l;
		for (uint sector = image.singleDensitySectors + 1; l < count && sector <= image.totalSectors; ++sector)
		{
			if (this[sector])
				result[l++] = sector;
		}
		result.length = l;
		return result;
	}

	/// Marking a set of _sectors as _free or occupied.
	/// Especially for use with arrays returned by findFreeSectors or findFreeSectorsContinuous.
	/// Params:
	///  sectors = Array containing numbers of subsequent sectors.
	///  free    = true marks sectors as _free, false marks them as occupied.
	final void markSectors(uint[] sectors, bool free = false)
	{
		foreach (sector; sectors)
		{
			if (this[sector] == free)
				throw new Exception(format("Sector %d already %s", sector, free ? "free" : "occupied"));
		}
		foreach (sector; sectors)
			this[sector] = free;
	}

	/// Find requested number of free sectors in VTOC, with the additional requirement that the sectors need to
	/// form a continuous area.
	/// Params:
	///  count = Requested number of sectors.
	/// Returns: Array containing numbers of subsequent sectors. It may be shorter than requested number of sectors,
	/// in which case you will usually report a "Disk full" error.
	final uint[] findFreeSectorsContinuous(uint count)
	{
		size_t l;
		uint maxL;
		uint firstSec;
		foreach (sector; image.singleDensitySectors + 1 .. image.totalSectors - count + 1)
		{
			if (!this[sector])
			{
				if (l > maxL)
				{
					firstSec = sector - l;
					maxL = l;
				}
				l = 0;
			}
			else
			{
				++l;
				if (l == count)
					return array(iota(sector - count + 1, sector + 1));
			}
		}
		return array(iota(firstSec, firstSec + maxL + 1));
	}
}
