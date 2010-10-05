/*	mydos - Implementation of filesystem interfaces for MyDos.

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
import std.algorithm;
import std.stream;
import std.range;
import std.conv;
debug import std.stdio;

import image;
import filesystem;
import vtoc;
import filename;

class MydosFileSystem : FileSystem
{
	@property string name()
	{
		return "MyDos";
	}
	
	@property BufferedImage image()
	{
		return image_;
	}

	@property uint freeSectors()
	{
		auto vtoc = image_[360];
		return vtoc[3] | (vtoc[4] << 8);
	}

	@property string label()
	{
		return "n/a";
	}

	override @property void label(string label)
	{
		throw new Exception("MyDos filesystem does not support setting volume label");
	}

	override @property DirRange rootDir()
	{
		return new MydosDirRange(this, 361);
	}

	override void initialize()
	{
		enforce(image_.totalSectors >= 369 && image_.totalSectors <= 65535,
			"Disk image has to have at least 369 and no more than 65535 sectors to set up MyDos filesystem on it, not " ~ to!string(image_.totalSectors));
		auto bootSector = new ubyte[128];
		bootSector[0] = 'M';
		image_[1] = bootSector;
		
		auto vtoc = new MydosVtoc(image_);
		foreach (i; 0 .. 721)
			vtoc[i] = true;
		auto lastSector = vtoc.sectorLocation(image_.totalSectors).sector;
		auto vtocSectors = array(iota(360U, lastSector - 1, -1));
		vtoc.markSectors([0U, 1, 2, 3]);			// boot sectors
		vtoc.markSectors(array(iota(361U, 369)));	// root directory
		vtoc.markSectors(vtocSectors);				// vtoc itself

		ushort fs = cast(ushort) (image_.totalSectors - 3 - 8 - vtocSectors.length);
		image_[360][0 .. 5] = [computeVtocMark(image_.totalSectors), fs & 0xff, fs >>> 8, fs & 0xff, fs >>> 8];
		image_.flush();
	}

	override void writeDosFiles(string ver)
	{
		debug writeln("Republica Portuguesa!");
		
		auto lver = tolower(ver);
		if (lver.startsWith("mydos450") || lver.startsWith("450"))
		{
			auto d1 = rootDir.openFile("DOS.SYS", "wb");
			enforce(d1.write(dosSys_) == dosSys_.length);
			d1.close();
			
			auto d2 = rootDir.openFile("DUP.SYS", "wb");
			enforce(d2.write(dupSys_) == dupSys_.length);
			d2.close();
		}
		else
			throw new Exception("Invalid or unsupported MyDOS version specified");
	}

	override void close()
	{
		image_.flush();
	}


	static this()
	{
		add(&detectMydos);
	}

protected:
	override @property void image(BufferedImage img)
	{
		image_ = img;
	}

private:
	this() {}

	this(BufferedImage img)
	{
		image_ = img;
		std.stdio.writeln(image_[360][0 .. 10]);
	}

	static FileSystem detectMydos(BufferedImage img)
	{
		if (img[1][0] == 'M' && img[360][0] == computeVtocMark(img.totalSectors))
			return new MydosFileSystem(img);
		return null;
	}

	@property void freeSectors_(uint fsec)
	in
	{
		assert(fsec >= 0 && fsec < image_.totalSectors);
	}
	body
	{
		image_[360][3 .. 5] = [fsec & 0xFF, (fsec >>> 8) & 0xFF];
	}

	static ubyte computeVtocMark(uint sec)
	{
		return sec < 1024 ? 2 : ((sec / 8 + 10) >>> 8) & 0xFF;
	}

	BufferedImage image_;

	immutable dosSys_ = cast(immutable(ubyte[])) import("mydos450t_dos.sys");
	immutable dupSys_ = cast(immutable(ubyte[])) import("mydos450t_dup.sys");
}

class MydosDirRange : DirRange
{
	override const @property bool empty()
	{
		return current_.sector >= lastSector_;
	}
	
	override @property void popFront()
	{
		ubyte s;
		do
		{
			current_ = next(current_);
			s = fs_.image[current_.sector][current_.offset];
		} while (current_.sector < lastSector_ && ((s & 0x80) || !s));
	}
	
	override @property MydosDirEntry front()
	{
		return new MydosDirEntry(fs_, current_);
	}

	override @property MydosDirRange save()
	{
		auto result = new MydosDirRange();
		result.fs_ = fs_;
		result.current_ = current_;
		result.lastSector_ = lastSector_;
		return result;
	}
	
	override void rewind()
	{
		current_ = Location(lastSector_ - 9, 128 - 16);
		popFront();
	}

	override MydosDirEntry createFile(string name)
	{
		debug writefln("createFile: %s", name);
		auto de = cast(MydosDirEntry) find(name, false);
		if (de)
			de.remove();
		else
			de = new MydosDirEntry(fs_, firstFreeEntry());
		de.stat_ = 0x46;
		de.name = name;
		return de;
	}

	override MydosDirEntry createDir(string name)
	{
		throw new Exception("createDir: Not implemented");
	}

private:
	this() {}

	this(MydosFileSystem fs, uint firstSector)
	{
		fs_ = fs;
		current_ = Location(firstSector - 1, 128 - 16);
		lastSector_ = firstSector + 8;
		popFront();
	}

	Location firstFreeEntry()
	{
		for (auto loc = Location(lastSector_ - 8, 0); loc.sector < lastSector_; loc = next(loc))
		{
			ubyte s = fs_.image[loc.sector][loc.offset];
			if ((s & 0x80) || s == 0)
				return loc;
		}
		throw new Exception("Directory full");
	}

	Location next(Location loc)
	{
		auto result = Location(loc.sector, (loc.offset + 16) % 128);
		if (!result.offset)
			++result.sector;
		return result;
	}

	MydosFileSystem fs_;
	Location current_;
	uint lastSector_;
}

class MydosDirEntry : DirEntry
{
	override @property FileName name()
	{
		return FileName(entry_[5 .. 16]);
	}

	override @property void name(string name)
	{
		enforce(!readOnly, "File is read only");
		sector_[location_.offset + 5 .. location_.offset + 16] = cast(ubyte[]) FileName(name).expand();
	}

	/// Size in bytes (upper limit).
	override @property uint size()
	{
		auto entry = entry_;
		if ((entry[0] & 0x46) == 0x46)
			return (entry[1] | (entry[2] << 8)) * (fs_.image.bytesPerSector - 3);
		else if ((entry[0] & 0x10) == 0x10)
			return 8 * 128;
		return 0;
	}
	
	override @property bool isDir()
	{
		return !!(stat_ & 0x10);
	}

	override @property bool readOnly()
	{
		return !!(stat_ & 0x20);
	}

	override @property void readOnly(bool ro)
	{
		ubyte stat = stat_;
		enforce(!stat & 0, "file is deleted");
		auto sector = sector_;
		sector[location_.offset] = ro ? (stat | 0x20) : (stat & 0xdf);
	}

	override DirEntry parent()
	{
		return parent_;
	}

	override MydosFileStream openFile(bool readable, bool writeable, bool append)
	{
		debug writeln("AAA");
		enforce(!isDir, this.name.fn ~ " is a directory");
		enforce(!append, "Appending not implemented");
				debug writeln("open ok");

		return new MydosFileStream(this, readable, writeable, append);
	}

	override DirRange openDir()
	{
		enforce(isDir, this.name.fn ~ " is not a directory");
		return new MydosDirRange(fs_, firstSector_);
	}

	override void remove()
	{
		throw new Exception("remove: Not implemented");
	}

	uint[] readSectorMap()
	{
		if (isDir)
			return array(iota(firstSector_, firstSector_ + 8));
		auto result = new uint[](sectorCount_);
		debug writeln(result.length);
		auto secn = firstSector_;
		size_t l;
		while (secn)
		{
			auto sec = fs_.image_[secn][];
			if (result.length <= l)
				result.length = l + 1;
			result[l] = secn;
			secn = sec[$ - 3] << 8 | sec[$ - 2];
		}
		return result;
	}

private:
	this(MydosFileSystem fs, Location location)
	in
	{
		assert(location.sector != 0);
		assert(!(location.offset % 16));
	}
	body
	{
		fs_ = fs;
		location_ = location;
	}

	@property BufferedSector sector_()
	{
		return fs_.image_[location_.sector];
	}

	@property ubyte[] entry_()
	{
		return sector_[location_.offset .. location_.offset + 16];
	}

	@property ubyte stat_()
	{
		return sector_[location_.offset];
	}
	
	@property void stat_(ubyte stat)
	{
		fs_.image_[location_.sector][location_.offset] = stat;
	}

	@property uint firstSector_()
	{
		auto entry = entry_;
		return entry[3] | (entry[4] << 8);
	}

	@property void firstSector_(uint sector)
	in
	{
		assert(sector > fs_.image_.singleDensitySectors && sector <= fs_.image_.totalSectors);
	}
	body
	{
		fs_.image_[location_.sector][location_.offset + 3 .. location_.offset + 5] = [sector & 0xFF, (sector >>> 8) & 0xFF];
	}

	@property uint sectorCount_()
	{
		auto b = fs_.image_[location_.sector][location_.offset + 1 .. location_.offset + 3];
		return b[0] | (b[1] << 8);
	}

	@property void sectorCount_(uint sc)
	{
		fs_.image_[location_.sector][location_.offset + 1 .. location_.offset + 3] = [sc & 0xFF, (sc >>> 8) & 0xFF];
	}

	MydosFileSystem fs_;
	Location location_;
	DirEntry parent_;
}

class MydosFileStream : Stream
{
	/// Read up to size bytes into the buffer and return the number of bytes actually read. A return value of 0 indicates end-of-file.
	override size_t readBlock(void* buffer, size_t size)
	out (result)
	{
		assert (result <= size);
	}
	body
	{
		size_t rsize;
/*		while (rsize < size && thisSector_)
		{
			auto sec = requestSector(thisSector_);
			size_t l = min(size - rsize, thisSectorLen_ - byteOffset_);
			buffer[rsize .. rsize + l] = sec[byteOffset_ .. byteOffset_ + l];
			assert ((byteOffset_ + l) <= thisSectorLen_);
			if ((byteOffset_ += l) == thisSectorLen_)
			{
				prevSector_ = thisSector_;
				thisSector_ = nextSector_;
				byteOffset_ = 0;
			}
			rsize += l;
		}*/
		while (rsize < size && currSector_ < sectorMap_.length)
		{
			auto thisSectorLength_ = (currSector_ == sectorMap_.length - 1 ? bytesInLastSector_ : fileBytesPerSector_);
			size_t l = min(size - rsize, thisSectorLength_ - currByte_);
			buffer[rsize .. rsize + l] = fs_.image_[sectorMap_[currSector_]][currByte_ .. currByte_ + l];
			assert ((currByte_ + l) <= thisSectorLength_);
			if ((currByte_ += l) == thisSectorLength_)
			{
				++currSector_;
				currByte_ = 0;
			}
			rsize += l;
		}
		return rsize;
	}

	/// Write up to size bytes from buffer in the stream, returning the actual number of bytes that were written.
	override size_t writeBlock(const void* buffer, size_t size)
	out (result)
	{
		assert (result <= size);
	}
	body
	{
		debug writefln("writing %d bytes", size);
		uint freeSectors = fs_.freeSectors;
		uint allocCount = (filePosition_ + size + fileBytesPerSector_ - 1) / fileBytesPerSector_ - sectorMap_.length;
		debug writefln("need to allocate %d sectors", allocCount);
		if (allocCount > 0)
		{
			auto vtoc = new MydosVtoc(fs_.image_);
			auto allocSecs = vtoc.findFreeSectors(allocCount);
			sectorMap_ ~= allocSecs;
			freeSectors -= allocSecs.length;
		}
		size_t wsize;
		while (wsize < size && currSector_ < sectorMap_.length)
		{
			size_t l = min(size - wsize, fileBytesPerSector_ - currByte_);
			fs_.image_[sectorMap_[currSector_]][currByte_ .. currByte_ + l] = (cast(ubyte*) buffer)[wsize .. wsize + l];
			fs_.image_[sectorMap_[currSector_]][fileBytesPerSector_ .. fileBytesPerSector_ + 2] =
				(currSector_ == sectorMap_.length - 1) ?
				[cast(ubyte) 0, cast(ubyte) 0] :
				[cast(ubyte) (sectorMap_[currSector_ + 1] >>> 8), cast(ubyte) (sectorMap_[currSector_ + 1] & 0xFF)];
			fs_.image_[sectorMap_[currSector_]][fileBytesPerSector_ + 2] = cast(ubyte) l;
			if ((currByte_ += l) == fileBytesPerSector_)
			{
				++currSector_;
				currByte_ = 0;
			}
			wsize += l;
		}
		dirEntry_.sectorCount_ = sectorMap_.length;
		fs_.freeSectors_ = freeSectors;
		
		/*
		// write to sector(s) already allocated for this file
		while (wsize < size && thisSector_)
		{
			// we always need existing sector contents here because of link to next sector
			auto sec = requestSector(thisSector_);
			size_t l = min(size - wsize, fileBytesPerSector_ - byteOffset_);
			assert ((byteOffset_ + l) <= fileBytesPerSector_);
			sec[$ - 1] = cast(ubyte) (byteOffset_ + l);
			sec[byteOffset_ .. byteOffset_ + l] = (cast(ubyte*) buffer)[wsize .. wsize + l];
			fs_.image_[thisSector_][] = sec[];
			if ((byteOffset_ += l) == fileBytesPerSector_)
			{
				prevSector_ = thisSector_;
				thisSector_ = nextSector_;
				byteOffset_ = 0;
				++logSector_;
			}
			wsize += l;
		}
		// ...then allocate new sectors for remaining part of file
		// and write data to them
		if (!thisSector_)
		{
			auto vtoc = new MydosVtoc(fs_.image_);
			uint allocCount = (size - wsize + fileBytesPerSector_ - 1) / fileBytesPerSector_;
			auto allocSecs = vtoc.findFreeSectors(allocCount);
			// update directory entry (if we just allocated first sector of file)
			// or link in previous sector (for sectors #>=2)
			if (prevSector_ == 0)
				dirEntry_.firstSector_ = allocSecs[0];
			else
			{
				auto secn = allocSecs[0];
				fs_.image_[prevSector_][fileBytesPerSector_ .. fileBytesPerSector_ + 2] = [(secn >>> 8) & 0xFF, secn & 0xFF];
			}
			auto sec = new ubyte[fileBytesPerSector_ + 3];
			// write data to sectors, excluding the last sector
			foreach (i, secn; allocSecs[0 .. $ - 1])
			{
				sec[0 .. fileBytesPerSector_] = (cast(ubyte*) buffer) [wsize .. wsize + fileBytesPerSector_];
				sec[fileBytesPerSector_ + 2] = cast(ubyte) fileBytesPerSector_;
				auto nextSec = allocSecs[i + 1];
				sec[fileBytesPerSector_ .. fileBytesPerSector_ + 2] = [(nextSec >>> 8) & 0xFF, nextSec & 0xFF];
				fs_.image_[secn] = sec;
				wsize += fileBytesPerSector_;
			}
			assert(size - wsize <= fileBytesPerSector_);
			// write last allocated sector, update vtoc
			size_t l = size - wsize;
			sec[0 .. l] = (cast(ubyte*) buffer) [wsize .. size];
			sec[$ - 1] = cast(ubyte) l;
			fs_.image_[allocSecs[$ - 1]] = sec;
			vtoc.markSectors(allocSecs);
			// update pointers
			wsize = size;
			byteOffset_ = thisSectorLen_ = l;
			dirEntry_.sectorCount_ = dirEntry_.sectorCount_ + allocSecs.length;
			fs_.freeSectors_ = fs_.freeSectors - allocSecs.length;
			prevSector_ = allocSecs[$ - 1];
		}*/
		return wsize;
	}
	
	override ulong seek(long offset, SeekPos whence)
	{
		throw new SeekException("seek not implemented");
	}

	override void close()
	{
		flush();
		super.close();
	}
	
	override void flush()
	{
		std.stdio.writeln(to!string(&this) ~ "flush");
		super.flush();
		fs_.image.flush();
	}

private:
	this(MydosDirEntry de, bool readable, bool writeable, bool append)
	{
		debug writefln("MydosFileStream: ", de.name);
		this.readable = readable;
		this.writeable = writeable;
		this.seekable = true;
		append_ = append;

		dirEntry_ = de;
		fs_ = de.fs_;
		sectorMap_ = de.readSectorMap();
		std.stdio.writeln(sectorMap_);
		if (sectorMap_.length)
			bytesInLastSector_ = fs_.image_[sectorMap_[$ - 1]][][$ - 1];
//		firstSector_ = de.firstSector_;
		fileBytesPerSector_ = fs_.image_.bytesPerSector - 3;
//		thisSector_ = firstSector_;
	}

/*	ubyte[] requestSector(uint sector)
	{
		if (sector)
		{
			auto buf = fs_.image_[thisSector_][];
			thisSectorLen_ = buf[$ - 1];
			nextSector_ = buf[$ - 2] | (buf[$ - 3] << 8);
			enforce((thisSectorLen_ == fileBytesPerSector_) ^ (nextSector_ == 0), "file link corrupted");
			return buf;
		}
		thisSectorLen_ = 0;
		nextSector_ = 0;
		return [];
	}*/

	@property size_t fileSize_()
	{
		return (sectorMap_.length - 1) * fileBytesPerSector_ + bytesInLastSector_;
	}
	
	@property size_t filePosition_()
	{
		return currSector_ * fileBytesPerSector_ + currByte_;
	}
	
	size_t currSector_;
	size_t currByte_;
	size_t bytesInLastSector_;
	size_t fileBytesPerSector_;

	uint[] sectorMap_;

/*	uint firstSector_;
	uint prevSector_;
	uint thisSector_;
	uint nextSector_;
	uint logSector_;

	uint byteOffset_;
	uint thisSectorLen_;
	uint fileBytesPerSector_;*/

	bool append_;

	MydosFileSystem fs_;
	MydosDirEntry dirEntry_;
}

class MydosVtoc : Vtoc
{
	this(BufferedImage img)
	{
		image_ = img;
	}

	override @property Location sectorLocation(uint sector)
	{
		uint vb = 10 + sector / 8;
		return Location(360 - vb / image_.bytesPerSector, vb);
	}
	
	override @property ubyte sectorBitMask(uint sector)
	{
		return 0x80 >>> (sector % 8);
	}

	override @property BufferedImage image()
	{
		return image_;
	}

private:
	BufferedImage image_;
}

unittest
{
/*	auto img = Image.create("", "Array", 720, 256, 3);
	auto bimg = new BufferedImage(img);
	auto fs = FileSystem.create(bimg, "Mydos");
	auto f1de = fs.rootDir.createFile("file1");
	auto f1 = f1de.openFile(false, true); 
	f1.write(new ubyte[1024]);
	assert(f1.position() == 1024);
	f1.close();
	assert(f1de.size >= 1024);
	f1 = fs.rootDir.openFile("file1", "rb");
	assert(f1.position() == 0);
	f1.read(new ubyte[512]);
	assert(f1.position() == 512);
	f1.close();*/
}
