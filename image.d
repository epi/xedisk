/*	(Written in D programming language)

	Common interface for all atari disk image formats.

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

import std.string;
import std.contracts;

interface Image
{
	void flush();
	void close();

	@property uint totalSectors();
	@property uint bytesPerSector();
	@property uint singleDensitySectors();

	final ubyte[] readSector(uint sector, ref ubyte[] data)
	{
		enforce(sector >= 1 && sector <= totalSectors, format("Invalid sector number: %d", sector));
		data.length = sector > singleDensitySectors ? bytesPerSector : 128;
		readSectorImpl(sector, data);
		return data;
	}

	final ubyte[] readSector(uint sector)
	{
		ubyte[] data;
		readSector(sector, data);
		return data;
	}

	final void writeSector(uint sector, ubyte[] data)
	{
		enforce(sector >= 1 && sector <= totalSectors, format("Invalid sector number: %d", sector));
		enforce(data.length == (sector > singleDensitySectors ? bytesPerSector : 128), "Data size does not match sector size");
		writeSectorImpl(sector, data);
	}

	static Image create(string path, string type, uint totalSectors, uint bytesPerSector, uint singleDensitySectors = 3)
	{
		enforce(totalSectors >= 3 && totalSectors <= 65535, "Total number of sectors should be at least 3 and not greater than 65535");
		enforce(bytesPerSector == 0x80 || bytesPerSector == 0x100, "The only supported sector sizes are 128 and 256 bytes");
		enforce(singleDensitySectors <= totalSectors, "Number of single density sectors cannot be greater than total number of sectors");
		
		auto img = newObj(path, type);
		img.createImpl(path, totalSectors, singleDensitySectors, bytesPerSector);
		return img;
	}

	static Image create(string path, uint totalSectors, uint bytesPerSector, uint singleDensitySectors = 3)
	{
		return create(path, autoType(path), totalSectors, singleDensitySectors, bytesPerSector);
	}

	static Image open(string path, string type, bool readOnly = true)
	{
		auto img = newObj(path, type);
		img.openImpl(path, readOnly);
		return img;
	}

	static Image open(string path, bool readOnly = true)
	{
		return open(path, autoType(path), readOnly);
	}

protected:
	void openImpl(string path, bool readOnly);
	void createImpl(string path, uint totalSectors, uint bytesPerSector, uint singleDensitySectors);

	void readSectorImpl(uint sector, ubyte[] data);
	void writeSectorImpl(uint sector, ubyte[] data);
	
private:
	static Image newObj(string path, string type)
	{
		auto image = cast(Image) Object.factory(tolower(type) ~ "." ~ capitalize(type) ~ "Image");
		enforce(image, "Unknown image format");
		return image;
	}
	
	static string autoType(string path)
	{
		return path.split(".")[$ - 1];
	}
}
