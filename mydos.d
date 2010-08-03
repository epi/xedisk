import std.string;
import std.contracts;
import std.algorithm;
import std.stream;

import image;
import filesystem;
import mydosvtoc;
import filename;
import directory;

package:

class MydosFileSystem : FileSystem
{
	static this()
	{
		add(&detectMydos);
	}

	static FileSystem detectMydos(Image img)
	{
		if (img.readSector(1)[0] == 'M')
			return new MydosFileSystem(img);
		return null;
	}

	override MydosFileStream openFile(string path, string mode)
	{
		uint sector;
		if (mode == "r" || mode == "rb")
		{
			listDir((ref const FileInfo fi)
			{
				sector = fi.firstSector;
				return false;
			}, path);
			enforce(sector, "File not found: " ~ path);
		}
		else if (mode == "w" || mode == "wb")
		{
			throw new Exception("Not implemented");
		}
		else
			throw new Exception("Invalid file access mode");
			
		return new MydosFileStream(this, sector, mode);
	}

	override void lockFile(string path, bool lock)
	{
		throw new Exception("Not implemented");
	}

	override void deleteFile(string path)
	{
		throw new Exception("Not implemented");
	}

	override void mkDir(string path)
	{
		throw new Exception("Not implemented");
	}

	override void listDir(bool delegate(const ref FileInfo) action, string path)
	{
		auto spath = splitPath(path);
		uint sector = 361;
		foreach (dir; spath[0 .. $ - 1])
		{
			auto ddir = new AtaridosDirectory(image_, sector);
			sector = 0;
			foreach (i; 0 .. 63)
			{
				auto entry = ddir[i];
				if (entry[0])
				{
					auto fi = unpackDirEntry(entry);
					if (matchFileName(fi.name, dir))
					{
						sector = fi.firstSector;
						break;
					}
				}
			}
			if (!sector)
				throw new Exception("Directory " ~ dir ~ " not found");
		}
		auto ddir = new AtaridosDirectory(image_, sector);
		foreach (i; 0 .. 63)
		{
			auto entry = ddir[i];
			if (entry[0])
			{
				auto fi = unpackDirEntry(entry);
				if (matchFileName(fi.name, spath[$ - 1]) && !action(fi))
					break;
			}
		}
	}
	
	override void initialize()
	{
		throw new Exception("Not implemented");
	}

	override void cleanUp()
	{
		throw new Exception("Not implemented");
	}
	
	override void close()
	{
	}

	override uint getFreeSectors()
	{
		auto vtoc = image_.readSector(360);
		return vtoc[3] | (vtoc[4] << 8);
	}

	override string getLabel()
	{
		return "n/a";
	}

	override @property string name()
	{
		return "Mydos";
	}

	override @property Image image()
	{
		return image_;
	}

private:
	Image image_;

	this(Image img)
	{
		image_ = img;
	}

	FileInfo unpackDirEntry(ubyte[] entry)
	{
		auto fi = FileInfo();
		if ((entry[0] & 0x46) == 0x46)
		{
			fi.length = (entry[1] | (entry[2] << 8)) * (image_.bytesPerSector - 3);
		}
		else if ((entry[0] & 0x10) == 0x10)
		{
			fi.isDirectory = true;
			fi.length = 8 * 128;
		}
		else
			return fi;
		fi.name = cleanUpFileName(entry[5 .. 13], entry[13 .. 16]);
		fi.isDeleted = !!(entry[0] & 0x80);
		fi.isReadOnly = !!(entry[0] & 0x20);
		fi.isNotClosed = !!(entry[0] & 0x01);
		fi.firstSector = (entry[3] | (entry[4] << 8));
		return fi;
	}
	
	ubyte[] packDirEntry(ref const FileInfo fi)
	{
		return new ubyte[0];
	}
}

class MydosFileStream : Stream
{
	/** Read up to size bytes into the buffer and return the number of bytes actually read. A return value of 0 indicates end-of-file.
	*/
	override size_t readBlock(void* buffer, size_t size)
	{
		for (size_t pos = 0; pos < size; )
		{
			enforce(offset_ <= dataLen_, "File corrupted");
			if (offset_ == dataLen_)
				if (!readNextSector())
					return pos;
			size_t len = min(size - pos, dataLen_ - offset_);
			buffer[pos .. pos + len] = sector_[offset_ .. offset_ + len];
			offset_ += len;
			pos += len;
		}
		return size;
	}

	/** Write up to size bytes from buffer in the stream, returning the actual number of bytes that were written.
	*/
	override size_t writeBlock(const void* buffer, size_t size)
	{
		throw new WriteException("not implemented");
	}
	
	override ulong seek(long offset, SeekPos whence)
	{
		throw new SeekException("not implemented");
	}

	override void close()
	{
		super.close();
		if (mode_ != "r" && mode_ != "rb")
			throw new Exception("Not Implemented");
	}

private:
	this(MydosFileSystem fs, uint firstSector, string mode)
	{
		fileSystem_ = fs;
		firstSector_ = physSector_ = firstSector;
		mode_ = mode;

		writeable = false;
		readable = true;
		seekable = false;
	}

	bool readNextSector()
	{
		if (sector_.length)
		{
			if (modified_)
				fileSystem_.image.writeSector(physSector_, sector_);
			modified_ = false;
			++logSector_;
			physSector_ = sector_[$ - 2] | (sector_[$ - 3] << 8);
		}
		if (!physSector_)
			return false;
		offset_ = 0;
		fileSystem_.image.readSector(physSector_, sector_);
		dataLen_ = sector_[$ - 1];
		return true;
	}

	uint physSector_;
	uint logSector_;
	uint offset_;

	ubyte[] sector_;
	uint dataLen_;
	bool modified_;

	uint firstSector_;
	string mode_;

	MydosFileSystem fileSystem_;	
}
