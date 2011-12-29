/*	sparta - SpartaDOS filesystem.

	Author: Adrian Matoga

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
import std.random;
import std.datetime;
import std.typecons;

import image;
import filesystem;
import vtoc;
import filename;

private const DirEntrySize = 23;

private enum DirEntryStatus : ubyte
{
	OpenForWrite = 0x80,
	Directory = 0x20,
	Deleted = 0x10,
	InUse = 0x08,
	Archive = 0x04,
	Hidden = 0x02,
	ReadOnly = 0x01
}

private ubyte[] createDirEntry(ubyte status, uint firstMapSector, uint size, FileName name, SysTime ctime)
out(result)
{
	assert(result.length == 23);
}
body
{
	ctime = ctime.toLocalTime();
	return [
		status,
		lobyte(firstMapSector),
		hibyte(firstMapSector),
		byte0(size),
		byte1(size),
		byte2(size)
	] ~ name.expand() ~ [
		cast(ubyte) ctime.day,
		cast(ubyte) ctime.month,
		cast(ubyte) (ctime.year % 100), // TODO: how sparta really interprets year?
		cast(ubyte) ctime.hour,
		cast(ubyte) ctime.minute,
		cast(ubyte) ctime.second
	];
}

private
{
	pure nothrow ubyte lobyte(uint x)
	{
		return x & 0xFF;
	}

	alias lobyte byte0;

	pure nothrow ubyte hibyte(uint x)
	{
		return (x >>> 8) & 0xFF;
	}

	alias hibyte byte1;

	pure nothrow ubyte byte2(uint x)
	{
		return (x >>> 16) & 0xFF;
	}
}

class SpartaFileSystem : FileSystem
{
	override @property string name()
	{
		return "SpartaDOS";
	}
	
	override @property BufferedImage image()
	{
		return image_;
	}

	override @property uint freeSectors()
	{
		auto sec1 = image_[1];
		return sec1[0x0D] | (sec1[0x0E] << 8);
	}

	override @property string label()
	{
		return cast(string) image_[1][0x16 .. 0x1E];
	}

	override @property void label(string label)
	{
		throw new FileSystemException("Not implemented");
	}

	override @property SpartaDirRange rootDir()
	{
		auto sec1 = image_[1];
		return new SpartaDirRange(this, sec1[0x09] | (sec1[0x0A] << 8));
	}

	override void initialize()
	{
		auto totalSectors = image_.totalSectors;
		if (totalSectors < 720 || totalSectors > 65535)
			throw new FileSystemException("Disk image has to have at least 720 and no more than 65535 sectors to set up Sparta filesystem on it, not " ~ to!string(totalSectors));
		auto bps = image_.bytesPerSector;
		if (bps != 128 && bps != 256)
			throw new FileSystemException("Only single and double density images are supported");

		uint vtocSectors = (totalSectors + bps * 8) / (bps * 8);
		writeln("vtoc capacity = ", vtocSectors * bps);
		uint firstVtocSector = 4;
		uint firstRootDirMapSector = firstVtocSector + vtocSectors;
		uint firstRootDirSector = firstRootDirMapSector + 1;
		uint firstFreeDirSector = firstRootDirSector + 1;
		uint firstFreeSector = firstFreeDirSector + 7;
		uint freeSectors = totalSectors - firstFreeDirSector + 1;
		ubyte tracks;
		switch (totalSectors)
		{
		case 720:
			tracks = 40;
			break;
		case 1440:
			tracks = 40 | 0x80;
			break;
		default:
			tracks = 1;
		}
		.writeln("nvtoc:      ", vtocSectors);
		.writeln("vtoc:       ", firstVtocSector);
		.writeln("rootdirmap: ", firstRootDirMapSector);
		.writeln("rootdir:    ", firstRootDirSector);
		.writeln("freedir:    ", firstFreeDirSector);
		.writeln("free:       ", firstFreeSector);
		.writeln("nfree:      ", freeSectors);

		auto boot = boot_.dup;
		boot[0x09 .. 0x2B] = [
			lobyte(firstRootDirMapSector),
			hibyte(firstRootDirMapSector),
			lobyte(totalSectors),
			hibyte(totalSectors),
			lobyte(freeSectors),
			hibyte(freeSectors),
			cast(ubyte) vtocSectors,
			lobyte(firstVtocSector),
			hibyte(firstVtocSector),
			lobyte(firstFreeSector),
			hibyte(firstFreeSector),
			lobyte(firstFreeDirSector),
			hibyte(firstFreeDirSector),
			cast(ubyte) 'X',
			cast(ubyte) 'E',
			cast(ubyte) 'D',
			cast(ubyte) 'I',
			cast(ubyte) 'S',
			cast(ubyte) 'K',
			cast(ubyte) ' ',
			cast(ubyte) ' ',
			tracks,
			bps == 128 ? 0x80 : 0,
			0x20, //  2.x <= sdx < 4.39...
			lobyte(bps), // ...but this is sdx >= 4.39 compliant
			hibyte(bps), //
			0,
			0,
			0,
			0,
			cast(ubyte) uniform(0, 256),
			0,
			0,
			0
		];
		image_[1] = boot[0 .. 128];
		image_[2] = boot[128 .. 256];
		image_[3] = boot[256 .. 384];

		auto vtoc = new SpartaVtoc(image_);
		foreach (i; 0 .. totalSectors + 1)
			vtoc[i] = true;
		vtoc.markSectors([0U, 1, 2, 3]); // boot sectors
		vtoc.markSectors(array(iota(firstVtocSector, firstFreeDirSector)));	// vtoc, root directory

		image_[firstRootDirMapSector] = [
			cast(ubyte) 0,
			cast(ubyte) 0,
			cast(ubyte) 0,
			cast(ubyte) 0,
			lobyte(firstRootDirSector),
			hibyte(firstRootDirSector)
		] ~ array(take(repeat(cast(ubyte) 0), bps - 6));

		image_[firstRootDirSector][0 .. DirEntrySize] =
			createDirEntry(DirEntryStatus.Directory | DirEntryStatus.InUse, 0, DirEntrySize, FileName("MAIN"), Clock.currTime());

		image_.flush();
	}

	override void writeDosFiles(string ver)
	{
		throw new FileSystemException("Not implemented");
	}

	override void close()
	{
		image_.flush();
	}

	static this()
	{
		add(&detectSparta);
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

	uint[] readSectorMap(uint firstMapSector, uint[] mapSectors = [])
	{
		uint bps = image_.bytesPerSector;
		alias firstMapSector secn;
		uint[] result;
		do
		{
			mapSectors ~= secn;
			auto secd = image_[secn];
			for (int i = 4; i < bps; i += 2)
				result ~= secd[i] | (secd[i + 1] << 8);
			secn = secd[0] | (secd[1] << 8);
		}
		while (secn);
		debug (SpartaSectorMap)
		{
			.writeln("read sector map");
			.writeln("map: ", mapSectors);
			.writeln("file:", array(filter!"a != 0"(result)));
		}
		return result;
	}

	@property void freeSectors(uint sectors)
	in
	{
		assert(sectors <= 65535);
	}
	body
	{
		image_[1][0x0D .. 0x0F] = [ lobyte(sectors), hibyte(sectors) ];
	}

	static FileSystem detectSparta(BufferedImage img)
	{
		if (img[1][6 .. 9] == [ cast(ubyte) 0x4C, 0x80, 0x30 ])
			return new SpartaFileSystem(img);
		return null;
	}

	BufferedImage image_;

	static immutable boot_ = cast(immutable(ubyte[])) import("sdxbootsec.bin");
}

class SpartaDirRange : DirRange
{
	override const @property bool empty()
	{
		return !positions_.length;
	}

	override @property void popFront()
	{
		positions_ = positions_[1 .. $];
	}

	override @property SpartaDirEntry front()
	{
		return new SpartaDirEntry(null, this, positions_[0]);
	}

	override @property SpartaDirRange save()
	{
		auto result = new SpartaDirRange();
		result.fs_ = fs_;
		result.firstMapSector_ = firstMapSector_;
		result.sectorMap_ = sectorMap_;
		result.fileSize_ = fileSize_;
		result.positions_ = positions_;
		return result;
	}
	
	override void rewind()
	{
		size_t pos = DirEntrySize;
		size_t i = 0;
		auto bps = fs_.image.bytesPerSector;
		ubyte stat;
		positions_.length = fileSize_ / DirEntrySize;
		while (pos < fileSize_)
		{
			stat = fs_.image[sectorMap_[pos / bps]][pos % bps];
			if ((stat & (DirEntryStatus.InUse | DirEntryStatus.Deleted)) == DirEntryStatus.InUse)
				positions_[i++] = pos;
			pos += DirEntrySize;
		}
		positions_.length = i;
	}

	// Create new empty file.
	override SpartaDirEntry createFile(string name)
	{
		throw new FileSystemException("createFile: Not implemented");
	}

	override SpartaDirEntry createDir(string name)
	{
		throw new FileSystemException("createDir: Not implemented");
	}

private:
	this() {}

	this(SpartaFileSystem fs, uint firstMapSector)
	{
		fs_ = fs;
		firstMapSector_ = firstMapSector;
		sectorMap_ = fs.readSectorMap(firstMapSector);
		auto sec1 = fs.image_[sectorMap_[0]];
		fileSize_ = sec1[3] | (sec1[4] << 8) | (sec1[5] << 16);
		rewind();
	}

	ubyte firstFreeEntry()
	{
		throw new FileSystemException("firstFreeEntry: not implemented");
	}

	SpartaFileSystem fs_;
	uint firstMapSector_;
	uint[] sectorMap_;
	size_t fileSize_;	
	size_t[] positions_;
}

class SpartaDirEntry : DirEntry
{
	override @property FileName name()
	{
		return name_;
	}

	override @property void name(string name)
	{
		enforce(!readOnly, "File is read only");
		name_ = FileName(name);
	}

	override @property uint size()
	{
		return size_;
	}

	override @property bool isDir()
	{
		return !!(stat_ & DirEntryStatus.Directory);
	}

	override @property bool readOnly()
	{
		return !!(stat_ & DirEntryStatus.ReadOnly);
	}

	override @property void readOnly(bool ro)
	{
		if (ro)
			stat_ |= DirEntryStatus.ReadOnly;
		else
			stat_ &= ~DirEntryStatus.ReadOnly;
		writeRawEntry();
	}

	override @property Nullable!SysTime time()
	{
		return Nullable!SysTime(time_);
	}

	override SpartaFileStream openFile(bool readable, bool writeable, bool append)
	{
		enforce(!isDir, this.name.fn ~ " is a directory");
		enforce(!append, "Appending not implemented");
		return new SpartaFileStream(this, readable, writeable, append);
	}

	override SpartaDirRange openDir()
	{
		enforce(isDir, this.name.fn ~ " is not a directory");
		return new SpartaDirRange(fs_, firstMapSector_);
	}

	override void remove()
	{
		if (stat_ & DirEntryStatus.Deleted)
			throw new FileSystemException("Already deleted");
		if (isDir)
			enforce(openDir().empty, new FileSystemException("Directory is not empty"));
		stat_ = (stat_ & ~DirEntryStatus.InUse) | DirEntryStatus.Deleted;
		uint[] mapSectors;
		auto dataSectors = array(filter!"a != 0"(fs_.readSectorMap(firstMapSector_, mapSectors)));
		(new SpartaVtoc(fs_.image_)).markSectors(dataSectors ~ mapSectors, true);
		writeRawEntry();
		fs_.freeSectors = cast(uint) (fs_.freeSectors + dataSectors.length + mapSectors.length);
		fs_.image.flush();
	}

private:
	this(SpartaDirEntry parent, SpartaDirRange range, size_t filePosition)
	{
		parent_ = parent;
		range_ = range;
		fs_ = range.fs_;
		filePosition_ = filePosition;
		readRawEntry();
	}

	void readRawEntry()
	{
		ubyte[] rawEntry;
		auto bps = fs_.image_.bytesPerSector;
		size_t posdivbps = filePosition_ / bps;
		size_t posmodbps = filePosition_ % bps;
		if (bps - posmodbps < DirEntrySize)
		{
			rawEntry = fs_.image[range_.sectorMap_[posdivbps]][posmodbps .. bps].dup;
			rawEntry ~= fs_.image[range_.sectorMap_[posdivbps + 1]][0 .. DirEntrySize - (bps - posmodbps)].dup;
		}
		else
		{
			rawEntry = fs_.image[range_.sectorMap_[filePosition_ / bps]][filePosition_ % bps .. filePosition_ % bps + DirEntrySize].dup;
		}
		stat_ = rawEntry[0];
		firstMapSector_ = rawEntry[1] | (rawEntry[2] << 8);
		size_ = rawEntry[3] | (rawEntry[4] << 8) | (rawEntry[5] << 16);
		name_ = FileName(rawEntry[6 .. 17]);
		// TODO: how sparta really interprets year?
		collectException(time_ = SysTime(DateTime((rawEntry[19] < 70 ? 2000 : 1900) + rawEntry[19], rawEntry[18], rawEntry[17], rawEntry[20], rawEntry[21], rawEntry[22])));
		debug (SpartaRawEntry) .writeln("readrawentry ", rawEntry, ", ", stat_, ", ", firstMapSector_, ", ", size_, ", ", name_, ", ", time_);
	}

	void writeRawEntry()
	{
		ubyte[] rawEntry = createDirEntry(stat_, firstMapSector_, size_, name_, time_);
		auto bps = fs_.image_.bytesPerSector;
		size_t posdivbps = filePosition_ / bps;
		size_t posmodbps = filePosition_ % bps; 
		if (bps - posmodbps < DirEntrySize)
		{
			fs_.image[range_.sectorMap_[posdivbps]][posmodbps .. bps] = rawEntry[0 .. bps - posmodbps];
			fs_.image[range_.sectorMap_[posdivbps + 1]][0 .. DirEntrySize - (bps - posmodbps)] = rawEntry[bps - posmodbps .. $];
		}
		else
		{
			fs_.image[range_.sectorMap_[posdivbps]][posmodbps .. posmodbps + DirEntrySize] = rawEntry[];
		}
		debug (SpartaRawEntry) .writeln("writerawentry ", rawEntry);
	}

	SpartaFileSystem fs_;
	SpartaDirEntry parent_;

	SpartaDirRange range_;
	size_t filePosition_;

	ubyte stat_;
	uint firstMapSector_;
	uint size_;
	FileName name_;
	SysTime	time_;
}

class SpartaFileStream : Stream
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
		auto fileSize = dirEntry_.size_;
		auto bps = fs_.image_.bytesPerSector;
		auto currSector = filePosition_ / bps;
		auto currByte = filePosition_ % bps;
		auto numSectors = (fileSize + bps - 1) / bps;
		auto bytesInLastSector = fileSize % bps;
		while (bytesRead < size && filePosition_ < fileSize)
		{
			auto thisSectorLength = (currSector == numSectors - 1 ? bytesInLastSector : bps);
			size_t l = min(size - bytesRead, thisSectorLength - currByte);
			auto sec = sectorMap_[currSector];
			if (sec == 0)
				throw new FileSystemException("Attempted to read outside file bounds");
			buffer[bytesRead .. bytesRead + l] = fs_.image_[sec][currByte .. currByte + l];
			assert ((currByte + l) <= thisSectorLength);
			if ((currByte += l) == thisSectorLength)
			{
				++currSector;
				currByte = 0;
			}
			bytesRead += l;
			filePosition_ += l;
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
		throw new FileSystemException("write not implemented");
	}
	
	override ulong seek(long offset, SeekPos whence)
	{
		auto fileSize = dirEntry_.size;
		switch (whence)
		{
		case SeekPos.Set:
			break;
		case SeekPos.Current:
			offset += filePosition_;
			break;
		case SeekPos.End:
			offset = fileSize - offset;
			break;
		default:
			throw new SeekException("Invalid seek mode");
		}
		// TODO: implement sparse files
		if (offset < 0 || offset > fileSize)
			throw new SeekException("Seek offset out of bounds");
		filePosition_ = offset;
		return offset;
	}

	override void close()
	{
		if (this.writeable)
			dirEntry_.stat_ &= ~DirEntryStatus.OpenForWrite;
		scope (exit) super.close();
		flush();
	}
	
	override void flush()
	{		
		super.flush();
		fs_.image.flush();
	}

private:
	this(SpartaDirEntry dirEntry, bool readable, bool writeable, bool append)
	{
		this.readable = readable;
		this.writeable = writeable;
		this.seekable = true;

		fs_ = dirEntry.fs_;
		dirEntry_ = dirEntry;
		filePosition_ = append ? dirEntry_.size_ : 0;
		sectorMap_ = fs_.readSectorMap(dirEntry.firstMapSector_);
	}

	SpartaFileSystem fs_;
	SpartaDirEntry dirEntry_;
	uint[] sectorMap_;
	size_t filePosition_;
}

/// Implements locating sector in VTOC ("bit map") for SpartaDOS
class SpartaVtoc : Vtoc
{
	this(BufferedImage img)
	{
		super(img);
		auto sec1 = img[1];
		firstVtocSector_ = sec1[16] | (sec1[17] << 8);
	}

	override @property Location sectorLocation(uint sector)
	{
		uint bps = image_.bytesPerSector;
		uint vb = sector / 8;
		return Location(firstVtocSector_ + vb / bps, vb % bps);
	}
	
	override @property ubyte sectorBitMask(uint sector)
	{
		return 0x80 >>> (sector % 8);
	}

private:
	uint firstVtocSector_;
}
