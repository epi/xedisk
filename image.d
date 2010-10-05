/*  image - Common interface for all atari disk image formats.

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
import std.exception;
import std.conv;
debug import std.stdio;

/// Location on disk.
struct Location
{
	uint sector;   /// sector, counted from 1
	size_t offset; /// starting byte in sector, counted from 0;
}

/// Simple interface 
interface Image
{
	void flush();
	void close();

	@property uint totalSectors();
	@property uint bytesPerSector();
	@property uint singleDensitySectors();

	final uint sectorSize(uint sector)
	{
		return sector > singleDensitySectors ? bytesPerSector : 128;
	}

	final void readSector(uint sector, ref ubyte[] data)
	{
		debug (SectorNumber) writefln("read  %5d", sector);
		enforce(sector >= 1 && sector <= totalSectors, format("Invalid sector number: %d", sector));
		data.length = sector > singleDensitySectors ? bytesPerSector : 128;
		readSectorImpl(sector, data);
	}

	final ubyte[] readSector(uint sector)
	{
		ubyte[] data;
		readSector(sector, data);
		return data;
	}

	final void writeSector(uint sector, in ubyte[] data)
	{
		debug (SectorNumber) writefln("write %5d", sector);
		enforce(sector >= 1 && sector <= totalSectors, format("Invalid sector number: %d", sector));
		enforce(data.length == sectorSize(sector), "Data size does not match sector size");
		writeSectorImpl(sector, data);
	}

	static Image create(string path, string type, uint totalSectors, uint bytesPerSector, uint singleDensitySectors = 3)
	{
		enforce(totalSectors >= singleDensitySectors && totalSectors <= 65535, "Total number of sectors should neither be less than number of single density sector, nor greater than 65535");
		enforce(bytesPerSector == 0x80 || bytesPerSector == 0x100, "The only supported sector sizes are 128 and 256 bytes, not" ~ to!string(bytesPerSector));

		auto img = newObj(path, type);
		img.createImpl(path, totalSectors, bytesPerSector, singleDensitySectors);
		return img;
	}

	static Image create(string path, uint totalSectors, uint bytesPerSector, uint singleDensitySectors = 3)
	{
		return create(path, autoType(path), totalSectors, bytesPerSector, singleDensitySectors);
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
	void writeSectorImpl(uint sector, in ubyte[] data);
	
private:
	static Image newObj(string path, string type)
	{
		auto image = cast(Image) Object.factory(tolower(type) ~ "." ~ capitalize(type) ~ "Image");
		version (unittest)
		{
			if (image is null)
				image = cast(Image) Object.factory("image." ~ capitalize(type) ~ "Image");
		}
		enforce(image, "Unknown image format: " ~ type);
		return image;
	}
	
	static string autoType(string path)
	{
		auto sp = path.split(".");
		return sp.length ? sp[$ - 1] : "";
	}
}

struct BufferedSector
{
	@property size_t length()
	{
		return size_;
	}

	@property uint number()
	{
		return sector_;
	}
	
	@property BufferedImage image()
	{
		return image_;
	}

	ubyte[] opSlice()
	{
		auto pBuf = sector_ in image_.buffers_;
		if (pBuf)
			return pBuf.data;
		else
			return (image_.buffers_[sector_] = new BufferedImage.Buffer(image_.image_.readSector(sector_))).data;
	}

	ubyte[] opSlice(size_t begin, size_t end)
	{
		return opSlice()[begin .. end];
	}

	ubyte opIndex(size_t index)
	{
		return opSlice()[index];
	}

	void opAssign(in ubyte[] data)
	in
	{
		assert(data.length == size_);
	}
	body
	{
		image_.image_.writeSector(sector_, data);
	}

	void opSliceAssign(in ubyte[] data)
	in
	{
		assert(data.length == size_);
	}
	body
	{
		image_.image_.writeSector(sector_, data);
	}

	void opSliceAssign(in ubyte[] data, size_t begin, size_t end)
	in
	{
		assert(end >= begin && end <= size_);
		assert(data.length == end - begin);
	}
	body
	{
		if (begin == 0 && end == size_)
			image_.image_.writeSector(sector_, data);
		else
		{
			auto buf = image_.buffers_.get(sector_, null);
			if (buf is null)
				buf = image_.buffers_[sector_] = new BufferedImage.Buffer(image_.image_.readSector(sector_));
			buf.data[begin .. end] = data[];
			buf.modified = true;
		}
	}

	void opIndexAssign(ubyte data, size_t index)
	{
		opSliceAssign([ data ], index, index + 1);
	}

private:
	this (BufferedImage img, uint sector)
	in
	{
		assert (sector >= 1 && sector <= img.totalSectors);
	}
	body
	{
		image_ = img;
		sector_ = sector;
		size_ = img.sectorSize(sector);
	}

	BufferedImage image_;
	uint sector_;
	uint size_;
}

class BufferedImage
{
	this(Image wrappedImage)
	{
		image_ = wrappedImage;
	}

	@property Image image()
	{
		return image_;
	}

	@property uint totalSectors()
	{
		return image_.totalSectors;
	}
	
	@property uint bytesPerSector()
	{
		return image_.bytesPerSector;
	}

	@property uint singleDensitySectors()
	{
		return image_.singleDensitySectors;
	}

	final uint sectorSize(uint sector)
	{
		return image_.sectorSize(sector);
	}

	/// Flush all buffers to disk.
	void flush()
	{
		foreach (sector, buf; buffers_)
		{
			if (buf.modified)
			{
				image_.writeSector(sector, buf.data);
				buf.modified = false;
			}
		}
		image_.flush();
	}

	void close()
	{
		flush();
		image_.close();
	}

	BufferedSector opIndex(uint sector)
	{
		return BufferedSector(this, sector);
	}

	void opIndexAssign(ubyte[] data, uint sector)
	{
		BufferedSector(this, sector) = data;
	}

private:
	static class Buffer
	{
		this(ubyte[] data)
		{
			this.data = data;
		}
		
		ubyte[] data;
		bool modified;
	}

	Image image_;
	Buffer[uint] buffers_;
}

version (unittest)
{
	import std.stdio;
	class ArrayImage : Image
	{
		this()
		{
		}

		override void flush()
		{
		}

		override void close()
		{
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
			return singleDensitySectors_;
		}

		override void readSectorImpl(uint sector, ubyte[] buf)
		{
			uint s = seek(sector);
			buf[] = storage_[s .. s + buf.length];
		}

		override void writeSectorImpl(uint sector, in ubyte[] buf)
		{
			uint s = seek(sector);
			storage_[s .. s + buf.length] = buf[];
		}

		override void openImpl(string path, bool readOnly)
		{
			throw new Exception("Go kill yourself");
		}

		override void createImpl(string path, uint totalSectors, uint bytesPerSector, uint singleDensitySectors)
		{
			totalSectors_ = totalSectors;
			bytesPerSector_ = bytesPerSector;
			singleDensitySectors_ = singleDensitySectors;
			uint size = (totalSectors - singleDensitySectors_) * bytesPerSector + 128 * singleDensitySectors_;
			storage_ = new ubyte[size];
		}

	private:
		ubyte[] storage_;
		bool readOnly_;
		uint bytesPerSector_;
		uint totalSectors_;
		uint singleDensitySectors_;

		size_t seek(uint sector)
		{
			if (sector > singleDensitySectors_)
				return singleDensitySectors_ * 128 + (sector - singleDensitySectors_ - 1) * bytesPerSector_;
			else
				return (sector - 1) * 128;
		}
	}
}

unittest
{
	uint sec = 720;
	auto img = cast(ArrayImage) Image.create("", "Array", sec, 256, 3);
	assert(img !is null);
	assert(!img.readOnly_);
	assert(img.singleDensitySectors == 3);
	assert(img.totalSectors == sec);
	assert(img.storage_.length == 183936);
	auto bimg = new BufferedImage(img);
	foreach (i; 1 .. sec + 1)
	{
		assert(bimg[i][0] == 0);
		assert(bimg[i][1] == 0);
		bimg[i][1] = i & 0xff;
	}
	assert(bimg.buffers_.length == sec);
	foreach (i; 1 .. sec + 1)
	{
		assert(bimg[i][0] == 0);
		assert(bimg[i][1] == (i & 0xff), to!string(bimg[i][1]) ~ " != " ~ to!string(i & 0xff));
		assert(img.readSector(i)[1] == 0);
	}
	bimg.flush();
	foreach (i; 1 .. sec + 1)
	{
		assert(img.readSector(i)[0] == 0);
		assert(img.readSector(i)[1] == bimg[i][1], to!string(i));
	}
	//assert(collectException(bimg[0]));
	//assert(collectException(bimg[sec + 1]));
}
