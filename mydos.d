import std.string;
import std.contracts;

import image;
import filesystem;
import mydosvtoc;

class MydosFile : AtariFile
{
	override void read(ubyte[] buf)		{ throw new Exception("Not Implemented"); }
	override void write(ubyte[] buf)	{ throw new Exception("Not Implemented"); }
	override void seek(uint position)	{ throw new Exception("Not Implemented"); }
	override uint tell()	{ throw new Exception("Not Implemented"); }
	override void close()	{ throw new Exception("Not Implemented"); }

private:
	this(MydosFileSystem fs, string name, string mode)
	{
		fileSystem_ = fs;
	}
	
	MydosFileSystem fileSystem_;
}

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

	override MydosFile openFile(string path, string mode)
	{
		return new MydosFile(this, path, mode);
	}

	override void lockFile(string path, bool lock)
	{
		throw new Exception("Not implemented");
	}

	override void mkDir(string path)
	{
		throw new Exception("Not implemented");
	}

	override void listDir(bool delegate(const ref FileInfo) action, string path = "/")
	{
		listDir(action, 361);
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

private:
	Image image_;
	MydosVtoc vtoc_;

	this(Image img)
	{
		image_ = img;
		vtoc_ = new MydosVtoc(img);
	}
	
	void listDir (bool delegate(const ref FileInfo) action, uint firstSector)
	{
		foreach (sector; firstSector .. firstSector + 8)
		{
			auto sec = image_.readSector(sector);
			foreach (i; 0 .. 8)
			{
				auto entry = sec[i * 16 .. i * 16 + 16];
				auto fi = FileInfo(cleanUpFileName(entry[5 .. 13], entry[13 .. 16]));
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
					continue;
				fi.isDeleted = !!(entry[0] & 0x80);
				fi.isReadOnly = !!(entry[0] & 0x20);
				fi.isNotClosed = !!(entry[0] & 0x01);
				if (!action(fi))
					return;
			}
		}
	}
}
