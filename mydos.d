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
import std.stdio;

import image;
import filesystem;
import vtoc;
import filename;

private
{
	pure nothrow ubyte lobyte(uint x)
	{
		return x & 0xFF;
	}

	pure nothrow ubyte hibyte(uint x)
	{
		return (x >>> 8) & 0xFF;
	}

	enum EntryStatus : ubyte
	{
		DELETED = 0x80,
		FILE = 0x42,
		READONLY = 0x20,
		DIRECTORY = 0x10,
		LONGLINKS = 0x04,
		NOTCLOSED = 0x01,
	}
}

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
		throw new FileSystemException("MyDos filesystem does not support setting volume label");
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
		image_[360][0 .. 5] = [computeVtocMark(image_.totalSectors), lobyte(fs), hibyte(fs), lobyte(fs), hibyte(fs)];
		image_.flush();
	}

	override void writeDosFiles(string ver)
	{
		auto lver = tolower(ver);
		switch (lver)
		{
		case "mydos450":
		case "mydos450t":
		case "450":
		case "450t":
			auto d1 = rootDir.openFile("DOS.SYS", "wb");
			enforce(d1.write(dosSys450t_[384 .. $]) == dosSys450t_.length - 384,
				new FileSystemException("Error writing DOS.SYS"));
			d1.close();
			auto d2 = rootDir.openFile("DUP.SYS", "wb");
			enforce(d2.write(dupSys450t_) == dupSys450t_.length,
				new FileSystemException("Error writing DUP.SYS"));
			d2.close();
			auto init = dosSys450t_[0 .. 384].dup;
			init[14] = image_.bytesPerSector == 256 ? 2 : 1;
			uint first = (cast(MydosDirEntry) rootDir.find("DOS.SYS")).firstSector_;
			init[15] = lobyte(first);
			init[16] = hibyte(first);
			init[17] = cast(ubyte) (image_.bytesPerSector - 3);
			image_[1] = init[0 .. 128];
			image_[2] = init[128 .. 256];
			image_[3] = init[256 .. 384];
			image_.flush();
			break;
		default:
			throw new FileSystemException("Invalid or unsupported MyDOS version specified");
		}
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
	}

	static FileSystem detectMydos(BufferedImage img)
	{
		if (img[1][0] == 'M' && img[360][0] == computeVtocMark(img.totalSectors))
			return new MydosFileSystem(img);
		return null;
	}

	@property void freeSectors(uint fsec)
	in
	{
		assert(fsec >= 0 && fsec < image_.totalSectors);
	}
	body
	{
		image_[360][3 .. 5] = [lobyte(fsec), hibyte(fsec)];
	}

	static ubyte computeVtocMark(uint sec)
	{
		return sec < 1024 ? 2 : hibyte(sec / 8 + 10);
	}

	BufferedImage image_;

	static immutable dosSys450t_ = cast(immutable(ubyte[])) import("mydos450t_dos.sys");
	static immutable dupSys450t_ = cast(immutable(ubyte[])) import("mydos450t_dup.sys");
	
//	static immutable dosSys453_ = cast(immutable(ubyte[])) import("mydos453_dos.sys");
//	static immutable dupSys453_ = cast(immutable(ubyte[])) import("mydos453_dup.sys");
}

class MydosDirRange : DirRange
{
	override const @property bool empty()
	{
		return current_ >= 64;
	}
	
	override @property void popFront()
	{
		ubyte s;
		do
		{
			++current_;
			Location loc = location(current_);
			s = fs_.image[loc.sector][loc.offset];
		} while (current_ < 64 && ((s & EntryStatus.DELETED) || !s));
	}
	
	override @property MydosDirEntry front()
	{
		return new MydosDirEntry(this, current_);
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
		current_ = 255;
		popFront();
	}

	// Create new empty file.
	override MydosDirEntry createFile(string name)
	{
		auto de = cast(MydosDirEntry) find(name, false);
		if (de)
			de.remove();
		else
			de = new MydosDirEntry(this, firstFreeEntry());
		de.clear();
		de.stat_ = fs_.image_[360][0] < 3 ?
			EntryStatus.FILE :
			EntryStatus.FILE | EntryStatus.LONGLINKS;
		de.name = name;
		return de;
	}

	override MydosDirEntry createDir(string name)
	{
		throw new FileSystemException("createDir: Not implemented");
	}

private:
	this() {}

	this(MydosFileSystem fs, uint firstSector)
	{
		fs_ = fs;
		current_ = 255; //-1; //Location(firstSector - 1, 128 - 16);
		lastSector_ = firstSector + 8;
		popFront();
	}

	ubyte firstFreeEntry()
	{
		for (ubyte i = 0; i < 64; ++i)
		{
			auto loc = location(i);
			ubyte s = fs_.image[loc.sector][loc.offset];
			if ((s & EntryStatus.DELETED) || s == 0)
				return i;
		}
		throw new FileSystemException("Directory full");
	}

	Location next(Location loc)
	{
		auto result = Location(loc.sector, (loc.offset + 16) % 128);
		if (!result.offset)
			++result.sector;
		return result;
	}

	Location location(ubyte index)
	{
		return Location(lastSector_ - 8 + (index / 8), (index % 8) * 16);
	}

	MydosFileSystem fs_;
	ubyte current_;
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

	/// Exact size in bytes.
	override @property uint size()
	{
		auto bps = fs_.image.bytesPerSector;
		if (isDir)
			return 8 * bps;
		if (sectorMap.length == 0)
			return 0;
		return (bps - 3) * (sectorMap.length - 1)
			+ fs_.image[sectorMap[$ - 1]][bps - 1];
	}
	
	override @property bool isDir()
	{
		return !!(stat_ & EntryStatus.DIRECTORY);
	}

	override @property bool readOnly()
	{
		return !!(stat_ & EntryStatus.READONLY);
	}

	override @property void readOnly(bool ro)
	{
		ubyte stat = stat_;
		enforce(!(stat & EntryStatus.DELETED), new FileSystemException("File is deleted"));
		enforce(!!stat, new FileSystemException("Empty entry"));
		auto sector = sector_;
		stat_ = ro ? (stat | EntryStatus.READONLY) : (stat & ~EntryStatus.READONLY);
	}

/*	override DirEntry parent()
	{
		return parent_;
	}*/

	override MydosFileStream openFile(bool readable, bool writeable, bool append)
	{
		enforce(!isDir, this.name.fn ~ " is a directory");
		enforce(!append, "Appending not implemented");
		return new MydosFileStream(this, readable, writeable, append);
	}

	override DirRange openDir()
	{
		enforce(isDir, this.name.fn ~ " is not a directory");
		return new MydosDirRange(fs_, firstSector_);
	}

	override void remove()
	{
		if (stat_ & EntryStatus.DELETED)
			throw new FileSystemException("Already deleted");
		auto sm = sectorMap();
		if (isDir)
			enforce(openDir().empty, new FileSystemException("Directory is not empty"));
		stat_ = EntryStatus.DELETED;
		fs_.freeSectors = fs_.freeSectors + sm.length;
		(new MydosVtoc(fs_.image_)).markSectors(sm, true);
		sectorMap_ = null;
		sectorMapValid_ = true;
		fs_.image.flush();
	}

	@property uint[] sectorMap()
	{
		if (sectorMapValid_)
			return sectorMap_;		
		if (stat_ & EntryStatus.DELETED)
			sectorMap_ = null;
		else
		{
			if (isDir)
				sectorMap_ = array(iota(firstSector_, firstSector_ + 8));
			else
			{
				bool indexed = fs_.image_[360][0] < 3;
				sectorMap_ = new uint[](sectorCount_);
				auto secn = firstSector_;
				size_t l;
				while (secn)
				{
					auto sec = fs_.image_[secn][];
					if (sectorMap_.length <= l)
						sectorMap_.length = l + 1;
					sectorMap_[l++] = secn;
					secn = sec[$ - 3] << 8 | sec[$ - 2];
					if (indexed)
						secn &= 0x3FF;
				}
			}
		}
		sectorMapValid_ = true;
		return sectorMap_;
	}

private:
	this(MydosDirRange parent, ubyte index)
	in
	{
		assert(index < 64);
	}
	body
	{
		parent_ = parent;
		fs_ = parent.fs_;
		location_ = Location(parent_.lastSector_ - 8 + index / 8, (index % 8) * 16);
		index_ = index;
	}

	void clear()
	{
		fs_.image_[location_.sector][location_.offset .. location_.offset + 16] = 0;
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
		sector_[location_.offset + 3 .. location_.offset + 5] =
			[lobyte(sector), hibyte(sector)];
	}

	@property uint sectorCount_()
	{
		auto b = sector_[location_.offset + 1 .. location_.offset + 3];
		return b[0] | (b[1] << 8);
	}

	@property void sectorCount_(uint sc)
	{
		sector_[location_.offset + 1 .. location_.offset + 3] =
			[lobyte(sc), hibyte(sc)];
	}
	
	MydosFileSystem fs_;
	Location location_;
	ubyte index_;
	MydosDirRange parent_;
	uint[] sectorMap_;
	bool sectorMapValid_;
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
		size_t bytesRead;
		while (bytesRead < size && currSector_ < sectorMap_.length)
		{
			auto thisSectorLength_ = (currSector_ == sectorMap_.length - 1 ? bytesInLastSector_ : fileBytesPerSector_);
			size_t l = min(size - bytesRead, thisSectorLength_ - currByte_);
			buffer[bytesRead .. bytesRead + l] =
				fs_.image_[sectorMap_[currSector_]][currByte_ .. currByte_ + l];
			assert ((currByte_ + l) <= thisSectorLength_);
			if ((currByte_ += l) == thisSectorLength_)
			{
				++currSector_;
				currByte_ = 0;
			}
			bytesRead += l;
		}
		return bytesRead;
	}

	/// Write up to size bytes from buffer in the stream, returning the actual number of bytes that were written.
	override size_t writeBlock(const void* buffer, size_t size)
	out (result)
	{
		assert (result <= size);
	}
	body
	{
		if (append_)
			seek(0, SeekPos.End);
		ubyte fileIndex = cast(ubyte) (fs_.image_[360][0] < 3 ? (dirEntry_.index_ << 2) : 0);
		uint allocCount = (filePosition_ + size + fileBytesPerSector_ - 1) / fileBytesPerSector_ - sectorMap_.length;
//		debug .writefln("need to allocate %d sectors", allocCount);
		if (allocCount > 0)
		{
			auto vtoc = new MydosVtoc(fs_.image_);
			auto allocSecs = vtoc.findFreeSectors(allocCount);
			sectorMap_ ~= allocSecs;
			if (!dirEntry_.firstSector_)
				dirEntry_.firstSector_ = sectorMap_[0];
			dirEntry_.sectorCount_ = sectorMap_.length;
			dirEntry_.sectorMapValid_ = false;
			vtoc.markSectors(allocSecs);
			fs_.freeSectors = (fs_.freeSectors - allocSecs.length);
		}
		size_t bytesWritten;
		while (bytesWritten < size && currSector_ < sectorMap_.length)
		{
			size_t l = min(size - bytesWritten, fileBytesPerSector_ - currByte_);
			auto currentSector = fs_.image_[sectorMap_[currSector_]];
			if (l == fileBytesPerSector_)
				currentSector.alloc();
			currentSector[currByte_ .. currByte_ + l] = 
				(cast(ubyte*) buffer)[bytesWritten .. bytesWritten + l];
			currByte_ += l;
			if (currSector_ == sectorMap_.length - 1)
			{
				currentSector[fileBytesPerSector_ .. fileBytesPerSector_ + 2] =
					[fileIndex, cast(ubyte) 0];
				bytesInLastSector_ = currByte_;
			}
			else
				currentSector[fileBytesPerSector_ .. fileBytesPerSector_ + 2] =
					[hibyte(sectorMap_[currSector_ + 1]) | fileIndex, lobyte(sectorMap_[currSector_ + 1])];
			currentSector[fileBytesPerSector_ + 2] = cast(ubyte) currByte_;
			if (currByte_ == fileBytesPerSector_)
			{
				++currSector_;
				currByte_ = 0;
			}
			bytesWritten += l;
		}

		return bytesWritten;
	}
	
	override ulong seek(long offset, SeekPos whence)
	{
		auto sz = dirEntry_.size;
		switch (whence)
		{
		case SeekPos.Set:
			break;
		case SeekPos.Current:
			offset += fileBytesPerSector_ * currSector_ + currByte_;
			break;
		case SeekPos.End:
			offset = sz - offset;
			break;
		default:
			throw new SeekException("Wrong mode");
		}
		if (offset < 0 || offset > sz)
			throw new SeekException("Seek offset out of bounds");
		currSector_ = cast(uint) (offset / fileBytesPerSector_);
		currByte_ = cast(uint) (offset % fileBytesPerSector_);
		return offset;
	}

	override void close()
	{
		if (this.writeable)
			dirEntry_.stat_ = dirEntry_.stat_ & ~EntryStatus.NOTCLOSED;
		scope (exit) super.close();
		flush();		
	}
	
	override void flush()
	{
		super.flush();
		fs_.image.flush();
	}

private:
	this(MydosDirEntry de, bool readable, bool writeable, bool append)
	{
		this.readable = readable;
		this.writeable = writeable;
		this.seekable = true;
		append_ = append;

		dirEntry_ = de;
		fs_ = de.fs_;
		sectorMap_ = de.sectorMap;
		if (sectorMap_.length)
			bytesInLastSector_ = fs_.image_[sectorMap_[$ - 1]][][$ - 1];
		fileBytesPerSector_ = fs_.image_.bytesPerSector - 3;
		if (writeable)
			dirEntry_.stat_ = dirEntry_.stat_ | EntryStatus.NOTCLOSED;
	}

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
	auto img = Image.create("", "Array", 720, 256, 3);
	auto bimg = new BufferedImage(img);
	auto fs = FileSystem.create(bimg, "Mydos");
	unittestFileSystem(fs);
}
