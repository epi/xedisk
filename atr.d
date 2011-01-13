/*  atr - implementation of Image interface for
	the most common ATR disk image format.

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
import std.exception;
import std.algorithm;

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

private:
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
		debug (Atr) writefln("readSector %d (%d bytes)", sector, buf.length);
		seek(sector);
		file_.rawRead(buf);
	}

	override void writeSectorImpl(uint sector, in ubyte[] buf)
	{
		debug (Atr) writefln("writeSector %d (%d bytes)", sector, buf.length);
		seek(sector);
		debug (Atr) writefln("at %d", file_.tell);
		file_.rawWrite(buf);
		debug (Atr)
		{
			file_.flush();
			seek(sector);
			ubyte[] rbuf = new ubyte[buf.length];
			file_.rawRead(rbuf);
			assert(rbuf == buf);
		}
	}

	override void openImpl(string path, bool readOnly)
	{
		file_ = File(path, readOnly ? "rb" : "r+b");
		auto header = new ubyte[16];
		file_.rawRead(header);
		enforce(header[0] == 0x96 && header[1] == 0x02, "Invalid ATR file header");
		uint size = (header[2] | (header[3] << 8) | (header[6] << 16)) * 16;
		bytesPerSector_ = header[4] | (header[5] << 8);
		totalSectors_ = (size + 3 * (bytesPerSector_ - 128)) / bytesPerSector_;
	}

	override void createImpl(string path, uint totalSectors, uint bytesPerSector, uint singleDensitySectors)
	{
		enforce(singleDensitySectors == 3, "ATR format does not support disks with single-density sector count other than 3");
		uint size = ((totalSectors - 3) * bytesPerSector + 128 * 3) / 16;
		file_ = File(path, "wb");
		ubyte[] header = [
			0x96, 0x02,
			size & 0xFF, (size >>> 8) & 0xFF,
			bytesPerSector & 0xFF, (bytesPerSector >>> 8) & 0xFF,
			(size >>> 16) & 0xFF,
			0, 0, 0, 0, 0, 0, 0, 0, 0 ];
		assert(header.length == 16);
		file_.rawWrite(header);
		auto sector = new ubyte[max(bytesPerSector, 128)];
		file_.seek(16 + size * 16 - 1);
		file_.rawWrite([cast(ubyte) 0]);
		file_.close();
		
		file_ = File(path, "r+b");
		totalSectors_ = totalSectors;
		bytesPerSector_ = bytesPerSector;
	}
}
