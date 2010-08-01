import std.string;
import std.contracts;
import std.date;

import image;

string cleanUpFileName(ubyte[] name, ubyte[] ext)
{
	char[] result;
	
	void custr(ubyte[] str)
	{
		foreach (c; str)
			if (c >= 0x20 && c <= 0x7E && c != '\\')
				result ~= c;
			else
				result ~= format("\\x%02x", c);
		result = result.stripr();
	}
	
	custr(name);
	result ~= ".";
	custr(ext);
	return result.chomp(".").idup;
}

interface AtariFile
{
	void read(ubyte[] buf);
	void write(ubyte[] buf);
	void seek(uint position);
	uint tell();
	void close();
}

struct FileInfo
{
	string name;
	uint length; // in bytes
	bool isReadOnly;
	bool isDirectory;
	bool isNotClosed;
	bool isDeleted;
}

interface FileSystem
{
	@property string name();

	AtariFile openFile(string path, string mode);
	void lockFile(string path, bool lock);
	void mkDir(string path);

	void listDir(bool delegate(const ref FileInfo) action, string path = "/");
	uint getFreeSectors();
	string getLabel();
	void initialize();
	void cleanUp();
	void close();

	static FileSystem open(Image img)
	{
		foreach (fsc; fileSystemConstructors_)
		{
			auto fs = fsc(img);
			if (fs !is null)
				return fs;
		}
		throw new Exception("Cannot detect filesystem");
	}
	
	static FileSystem create(Image img, string name)
	{
		auto fs = cast(FileSystem) Object.factory(tolower(name) ~ "." ~ capitalize(name) ~ "FileSystem");
		enforce(fs !is null, "Unknown filesystem: " ~ name ~ " - cannot create");
		fs.open(img);
		fs.initialize();
		return fs;
	}

	static add(FileSystem function(Image) ctor)
	{
		fileSystemConstructors_ ~= ctor;
	}
	
private:
	static FileSystem function(Image) [] fileSystemConstructors_;
}
