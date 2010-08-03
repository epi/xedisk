import std.contracts;
import std.string;

import image;

interface Vtoc
{
	bool opIndexImpl(uint sector);
	bool opIndexAssignImpl(bool value, uint sector);
	void flush();
	@property Image image();

	final bool opIndex(uint sector)
	{
		enforce(sector > image.singleDensitySectors && sector <= image.totalSectors, "Sector # out of range");
		return opIndexImpl(sector);
	}

	final bool opIndexAssign(bool value, uint sector)
	{
		enforce(sector > image.singleDensitySectors && sector <= image.totalSectors, "Sector # out of range");
		return opIndexAssignImpl(value, sector);
	}

	final uint[] findFreeSectors(uint count)
	{
		enforce(count <= image.totalSectors - image.singleDensitySectors, "Disk full");
		uint[] result;
		for (uint sector = image.singleDensitySectors + 1; count > 0 && sector <= image.totalSectors; ++sector)
		{
			if (this[sector])
			{
				result ~= sector;
				--count;
			}
		}
		enforce(result.length == count, "Disk full");
		return result;
	}
	
	final uint[] findFreeSectorsContinuous(uint count)
	{
		throw new Exception("Not implemented");
	}

	final void markSectors(uint[] sectors, bool free = false)
	{
		foreach (sector; sectors)
		{
			if (this[sector] == free)
				throw new Exception(format("Sector %d already occupied", sector));
		}
		foreach (sector; sectors)
			this[sector] = free;
	}
}
