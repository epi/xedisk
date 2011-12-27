/*	filesystem - Set of interfaces for dealing with
	different filesystems in an unified manner.

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
import std.stream;

import image;
import filename;

class FileSystemException : Exception
{
	this(string msg)
	{
		super(msg);
	}
}

/// An abstract filesystem.
interface FileSystem
{
	/// Open existing filesystem, automatically detecting it based on image contents.
	/// Params:
	///  img = disk image containing a valid and supported file system.
    /// Returns:
    ///  A FileSystem object of opened filesystem.
	static FileSystem open(BufferedImage img)
	{
		foreach (fsc; fileSystemConstructors_)
		{
			auto fs = fsc(img);
			if (fs !is null)
				return fs;
		}
		throw new FileSystemException("Cannot detect filesystem");
	}
	
	/// Create empty filesystem on existing image.
	/// Params:
	///  img  = image to create filesystem on.
	///  name = name of filesystem (e.g. "Mydos"), case insensitive.
    /// Returns:
    ///  A FileSystem object of initialized filesystem.
	static FileSystem create(BufferedImage img, string name)
	{
		auto fs = cast(FileSystem) Object.factory(toLower(name) ~ "." ~ capitalize(name) ~ "FileSystem");
		enforce(fs !is null, new FileSystemException("Unknown filesystem: " ~ name ~ " - cannot create"));
		fs.image = img;
		fs.initialize();
		return fs;
	}

	/// Add support for a specific filesystem.
	/// Params:
	///  ctor = function that recognizes a filesystem on image it is given,
	///         and returns a FileSystem object if it it understands image format,
	///         or null otherwise.
	static void add(FileSystem function(BufferedImage) ctor)
	{
		fileSystemConstructors_ ~= ctor;
	}

	/// Resolve file or directory path.
	/// Params:
	///  path = path to file or directory.
	/// Returns:
	///  Directory entry of found match.
	final DirEntry find(string path)
	{
		auto spath = splitPath(path);
		return resolvePath(spath[0 .. $ - 1]).find(spath[$ - 1]);
	}

	final DirRange findDir(string path)
	{
		return resolvePath(splitPath(path));
	}

	/// Execute action on each valid entry under specified path.
	/// Params:
	///  action = action to execute. If returns false, iteration stops;
	///  path   = path to a directory, may end with a mask for files to list in the directory.
	final void listDir(bool delegate(DirEntry) action, string path = "/*.*")
	{
		if (!path.length)
			path = "/*.*";
		else if (path.stripRight()[$ - 1] == '/')
			path = path ~ "*.*";
		
		auto spath = splitPath(path);
		foreach (entry; resolvePath(spath[0 .. $ - 1]))
			if (entry.name.match(spath[$ - 1]) && !action(entry))
				break;
	}
	
	/// Return filesystem name.
	@property string name();
	
	/// Return underlying disk image.
	@property BufferedImage image();

	/// Return free sector count.
	@property uint freeSectors();

	/// Return volume label.
	@property string label();

	/// Set filesystem label.
	@property void label(string label);

	/// Return reference to root directory.
	@property DirRange rootDir();

	/// Initialize image with an empty filesystem (format).
	void initialize();

	/// Write bootable DOS files to filesystem.
	/// Params:
	///  ver = DOS version.
	void writeDosFiles(string ver);

	/// Close filesystem, flushing all changes.
	void close();

protected:
	/// Set underlying disk image.
	@property void image(BufferedImage img);
	
private:
	final DirRange resolvePath(string[] splitPath)
	{
		auto currentDir = rootDir();
		foreach (dirName; splitPath)
			currentDir = currentDir.find(dirName).openDir();
		return currentDir;
	}

	static FileSystem function(BufferedImage)[] fileSystemConstructors_;
}

/// A directory entry for file or subdirectory.
/// Gives access to file name, size and attributes.
/// Opens existing file or directory.
interface DirEntry
{
	@property FileName name();

	@property void name(string name);

	/// Exact size in bytes.
	@property uint size();
	
	@property bool readOnly();
	
	@property void readOnly(bool ro);

	@property bool isDir();

	// /// Parent directory.
	// DirEntry parent();

	/// Open as file.
	Stream openFile(bool readable = true, bool writeable = false, bool append = false);

	/// Open as directory.
	DirRange openDir();

	/// Delete file/directory.
	void remove();
}

/// Input range over directory contents.
interface DirRange
{
	/// Input range primitives.
	const @property bool empty();
	@property void popFront(); /// ditto
	@property DirEntry front(); /// ditto

	/// Get copy of current state.
	/// Returns:
	///  Copy of the range, including current position of front element.
	@property DirRange save();

	/// Rewind to first entry in this directory.
	void rewind();

	/// Create new file in this directory.
	/// Params:
	///  name    = _name of new file.
	/// Returns:
	///  directory entry of newly created file.
	DirEntry createFile(string name);

	/// Create new subdirectory in this directory.
	/// Params:
	///  name    = _name of new directory.
	/// Returns:
	///  directory entry of newly created directory.
	DirEntry createDir(string name);

	/// Find first file or directory matching the name in this directory.
	/// Searching starts from current front element of the range.
	/// Params:
	///  name    = _name of entry searched for, may include '?' and '*' wildcards.
	///  doThrow = if true, throws an Exception instead of returning null when
	///            entry is not found.
	/// Returns: a directory entry or null when no match found.
	final DirEntry find(string name, bool doThrow = true)
	{
		foreach (entry; this.save)
		{
			if (entry.name.match(name))
				return entry;
		}
		if (doThrow)
			throw new FileSystemException(name ~ " not found");
		return null;
	}
	
	/// Open or create file in this directory.
	/// Params:
	///  name = _name of file to open.
	///  mode = access _mode, has the same semantics as fopen in C.
	/// Returns: a Stream.
	final Stream openFile(string name, string mode)
	{
		bool plus = mode.length > 1 && (mode[1 .. $].startsWith("+") || mode[1 .. $].startsWith("b+"));
		if (mode.startsWith("r"))
			return find(name).openFile(true, plus, false);
		else if (mode.startsWith("w"))
			return createFile(name).openFile(plus, true, false);
		else if (mode.startsWith("a"))
		{
			auto de = find(name, false);
			if (!de)
				de = createFile(name);
			return de.openFile(plus, true, true);
		}
		throw new FileSystemException("Invalid file open mode");
	}
}

version (unittest)
{
	import std.random;
	import std.stdio;
	
	void unittestFileSystem(FileSystem fs)
	{
		auto freeSec = fs.freeSectors;
		auto secSize = fs.image.bytesPerSector;
		auto rnd = Random(0);

		// sprawdzic rozmiary plikow od 0 do takiego ktory sie przestanie miescic na dysku
		for (uint fsz = 0; fsz < freeSec * secSize / 2; ++fsz)
		{
			auto arr = new ubyte[fsz];
			foreach (ref b; arr)
			{
				b = cast(ubyte) uniform(0, 256, rnd);
			}
			auto exc = collectException(fs.rootDir.openFile("blah", "r"));
			assert(exc !is null, "file exists!");
			assert((cast(FileSystemException) exc) !is null,
				exc.classinfo.name ~ ": " ~ exc.msg);
			auto fw = fs.rootDir.openFile("blah", "w");
			for (size_t i = 0; i < arr.length; i += 100)
			{
				fw.write(arr[i .. i + 100 > arr.length ? arr.length : i + 100]);
			}
			fw.close();
			assert(fs.rootDir.find("blah").size == fsz, format("expected=%d, actual=%d", fsz, fs.rootDir.find("blah").size));
			auto fr = fs.rootDir.openFile("blah", "r");
			auto rarr = new ubyte[arr.length + 1];
			fr.read(rarr);
			fr.close();
			fs.rootDir.find("blah").remove();
		}
	}
}
