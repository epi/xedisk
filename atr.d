/*	(Written in D programming language)

	Image interface implementation for ATR format.

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

import std.stdio;
import std.string;
import std.contracts;
import image;

class AtrImage : Image
{
	this()
	{
	}

	override void flush()
	{
		file_.flush();
	}

	override void close()
	{
		file_.close();
	}

	@property override uint totalSectors()
	{
		return totalSectors_;
	}
	
	@property override uint bytesPerSector()
	{
		return bytesPerSector_;
	}

	@property override uint singleDensitySectors()
	{
		return 3;
	}

	File file_;
	
	uint bytesPerSector_;
	uint totalSectors_;

	void seek(uint sector)
	{
		if (sector > 3)
			file_.seek(16 + 3 * 128 + (sector - 4) * bytesPerSector_);
		else
			file_.seek(16 + (sector - 1) * 128);
	}

protected:
	override void readSectorImpl(uint sector, ubyte[] buf)
	{
		seek(sector);
		file_.rawRead(buf);
	}

	override void writeSectorImpl(uint sector, ubyte[] buf)
	{
		seek(sector);
		file_.rawWrite(buf);
	}

	override void openImpl(string path, bool readOnly)
	{
		file_ = File(path, readOnly ? "rb" : "r+b");
		auto header = new ubyte[16];
		file_.rawRead(header);
		enforce(header[0] == 0x96 && header[1] == 0x02, "Invalid ATR file header");
		uint size = (header[2] | (header[3] << 8) | (header[6] << 16)) * 16;
		bytesPerSector_ = header[4] | (header[5] << 8);
		totalSectors_ = (size + 3 * 128) / bytesPerSector_;
	}

	override void createImpl(string path, uint totalSectors, uint bytesPerSector, uint singleDensitySectors)
	{
		throw new Exception("Not implemented");
/*		enforce(singleDensitySectors == 3, "ATR format does not support disks with single-density sector count other than 3");
		imin(0, totalSectors - 3)
		file_ = File(path, "wb");
		auto header = [ 0x96, 0x02, */
	}
}
