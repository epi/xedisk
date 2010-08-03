import std.string;
import std.contracts;
import std.stream;

import image;

struct FileInfo
{
	string name;
	uint length; // in bytes
	bool isReadOnly;
	bool isDirectory;
	bool isNotClosed;
	bool isDeleted;
	uint firstSector;
}

interface FileSystem
{
	@property string name();
	@property Image image();

	Stream openFile(string path, string mode);
	void lockFile(string path, bool lock);
	void deleteFile(string path);
	void mkDir(string path);

	void listDir(bool delegate(const ref FileInfo) action, string path = "/*.*");
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
