// Written in the D programming language

/*
fs.d - common file system interface
Copyright (C) 2010-2012 Adrian Matoga

xedisk is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

xedisk is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with xedisk.  If not, see <http://www.gnu.org/licenses/>.
*/

module xe.fs;

debug import std.stdio;
import std.typecons;
import std.string;
import std.datetime;
import std.algorithm;
import std.exception;
import std.regex;
import xe.disk;
import xe.streams;
import xe.exception;

version (unittest)
{
	import xe.test;
}

mixin(CTFEGenerateExceptionClass("UnrecognizedDiskFormatException", 148,
	"Unrecognized disk format"));
mixin(CTFEGenerateExceptionClass("PathNotFoundException", 150,
	"Path not found"));
mixin(CTFEGenerateExceptionClass("FileExistsException", 151,
	"Invalid attempt to overwrite an existing file or directory"));
mixin(CTFEGenerateExceptionClass("DiskFullException", 162,
	"Disk full"));
mixin(CTFEGenerateExceptionClass("InvalidFileNameException", 165,
	"Invalid file name"));
mixin(CTFEGenerateExceptionClass("DirectoryFullException", 169,
	"Directory full"));
mixin(CTFEGenerateExceptionClass("FileNotFoundException", 170,
	"File not found"));

///
class XeEntry
{
	/// null if this entry is root directory
	abstract XeDirectory getParent();

	///
	abstract string getName();

	///
	final string getFullPath()
	{
		auto node = this;
		string result;
		while (node.getParent())
		{
			result = "/" ~ node.getName() ~ result;
			node = node.getParent();
		}
		return result;
	}

	///
	abstract void rename(string newName);

	///
	abstract void remove(bool forceRemoveContents);

	///
	abstract uint getSectors();
	///
	abstract ulong getSize();

	///
	abstract bool isReadOnly();
	///
	abstract void setReadOnly(bool value);

	///
	abstract bool isHidden();
	///
	abstract void setHidden(bool value);

	///
	abstract bool isArchive();
	///
	abstract void setArchive(bool value);

	///
	abstract bool isFile() pure nothrow;
	///
	abstract bool isDirectory() pure nothrow;

	///
	abstract DateTime getTimeStamp();
	///
	abstract void setTimeStamp(DateTime timeStamp);

	///
	protected abstract void doRemove();
}

///
class XeFile : XeEntry
{
	///
	abstract InputStream openReadOnly();
	///
	abstract OutputStream openWriteOnly(bool append = false);
	
	///
	version (xedisk_V2)
	{
		Stream openReadWrite(bool append = false);
	}

	final override void remove(bool forceRemoveContents)
	{
		if (isReadOnly())
			throw new XeException("Cannot remove read only " ~ toString());
		doRemove();
	}

	final override bool isFile() pure nothrow { return true; }
	final override bool isDirectory() pure nothrow { return false; }

	override string toString()
	{
		return format("file `%s'", getFullPath());
	}
}

/// Directory spanning policy for XeDirectory.enumerate()
enum XeSpanMode
{
	/// Do not descend into subdirectories
	Shallow,
	/// _Depth first, i.e. the content of any subdirectory is spanned
	/// before that subdirectory itself.
	/// Useful e.g. when recursively deleting files.
	Depth,
	/// _Breadth first, i.e. the content of any subdirectory is spanned
	/// right after that subdirectory itself.
	Breadth
}

///
class XeDirectory : XeEntry
{
	///
	abstract OutputStream createFile(string name); // or should it return XeFile?
	///
	abstract XeDirectory createDirectory(string name);

	private static struct Iterator
	{
		int opApply(int delegate(XeEntry entry) action)
		{
			int recurseDepthFirst(XeEntry entry)
			{
				auto dir = cast(XeDirectory) entry;
				if (dir && dir.doEnumerate(&recurseDepthFirst))
					return 1;
				return action(entry);
			}

			int recurseBreadthFirst(XeEntry entry)
			{
				if (action(entry))
					return 1;
				auto dir = cast(XeDirectory) entry;
				return (dir && dir.doEnumerate(&recurseBreadthFirst)) ? 1 : 0;
			}

			final switch (_spanMode)
			{
			case XeSpanMode.Shallow:
				return _dir.doEnumerate(action);
			case XeSpanMode.Depth:
				return _dir.doEnumerate(&recurseDepthFirst);
			case XeSpanMode.Breadth:
				return _dir.doEnumerate(&recurseBreadthFirst);
			}
		}

		private XeDirectory _dir;
		private XeSpanMode _spanMode;
	}

	/// Returns a range that can be iterated over using foreach
	final auto enumerate(XeSpanMode spanMode = XeSpanMode.Shallow)
	{
		return Iterator(this, spanMode);
	}

	/// Resolves slashes and ".."
	XeEntry find(string path, bool caseSensitive = false)
	{
		enforce(path.length > 0, "Empty path");
		XeEntry node = this;
		if (path[0] == '/')
		{
			while (node.getParent())
				node = node.getParent();
			path = path[1 .. $];
		}
		foreach (el; splitter(path, '/'))
		{
			if (el == "")
				continue;
			if (el == ".")
				continue;
			else if (el == "..")
				node = node.getParent();
			else
			{
				auto dir = cast(XeDirectory) node;
				enforce(dir, format("%s is not a directory", node.getName()));
				bool found;
				foreach (entry; dir.enumerate())
				{
					// TODO: ugly hack, maybe name matching should be
					// file system dependent?
					bool equal = caseSensitive
						? entry.getName() == el
						: entry.getName().toLower() == el.toLower();
					if (equal)
					{
						node = entry;
						found = true;
						break;
					}
				}
				if (!found)
					return null;
			}
		}
		return node;
	}

	override void remove(bool forceRemoveContents)
	{
		if (isReadOnly())
			throw new XeException(format(
				"Cannot remove read only directory `%s'", getName()), 167);
		string childName;
		bool hasAnyChild;
		bool hasReadOnlyChild;
		foreach (entry; enumerate(XeSpanMode.Breadth))
		{
			hasAnyChild = true;
			if (entry.isReadOnly())
			{
				childName = entry.getFullPath();
				hasReadOnlyChild = true;
				break;
			}
		}
		if (!forceRemoveContents && hasAnyChild)
			throw new XeException(format(
				"Cannot remove non-empty directory `%s'", getFullPath()), 175);
		if (hasReadOnlyChild)
			throw new XeException(format(
				"Cannot remove directory `%s' containing a read only child `%s'",
				getName(), childName), 175);
		foreach (entry; enumerate(XeSpanMode.Depth))
			entry.doRemove();
		doRemove();
	}

	final override bool isFile() pure nothrow { return false; }
	final override bool isDirectory() pure nothrow { return true; }

	override string toString()
	{
		return format("directory `%s'", getFullPath());
	}

protected:
	abstract int doEnumerate(int delegate(XeEntry entry) action);
}

private string maskToRegex(string mask)
{
	string result = "^";
	foreach (c; mask)
	{
		switch (c)
		{
		case 'A': .. case 'Z':
		case 'a': .. case 'z':
		case '0': .. case '9':
		case '@', '_':
			result = result ~ c;
			break;
		case '.':
			result = result ~ r"\.";
			break;
		case '*':
			result = result ~ ".*";
			break;
		case '?':
			result = result ~ ".";
			break;
		default:
			throw new XeException(format(
				"Invalid character in mask `%s'", c), 165);
		}
	}
	return result ~ "$";
}

unittest
{
	mixin(Test!"maskToRegex (1)");
	static assert (maskToRegex(r"*.*") == r"^.*\..*$");
	static assert (maskToRegex(r"a?b.*") == r"^a.b\..*$");
}

///
class XeFileSystem
{
	///
	static XeFileSystem create(XeDisk disk, string type)
	{
		auto td = types_.get(toUpper(type), Nullable!TypeDelegates());
		if (td.isNull())
			throw new XeException("Unknown file system type " ~ type, 156);
		return td.doCreate(disk);
	}

	/// Detects file system automatically. Throws if cannot recognize.
	static XeFileSystem open(XeDisk disk)
	{
		foreach (type, td; types_)
		{
			auto fs = td.get().tryOpen(disk);
			if (fs !is null)
				return fs;
		}
		throw new UnrecognizedDiskFormatException();
	}

	protected static void registerType(
		string type,
		XeFileSystem function(XeDisk disk) tryOpen,
		XeFileSystem function(XeDisk disk) doCreate)
	{
		type = toUpper(type);
		types_[type] = TypeDelegates(tryOpen, doCreate);
		debug stderr.writefln("Registered file system type %s", type);
	}

	///
	abstract uint getFreeSectors();
	///
	abstract ulong getFreeBytes();
	///
	abstract XeDirectory getRootDirectory();
	///
	abstract string getLabel();
	///
	abstract void setLabel(string value);
	///
	abstract string getType();

	///
	abstract bool isValidName(string name);
	///
	abstract string adjustName(string name);

	abstract void writeDosFiles(string dosVersion);

	/// Enumerate (non-recursively) contents of a directory specified by path
	/// filtered according to mask.
	/// Returns: range that can be iterated over using foreach.
	final auto listDirectory(string path, string mask)
	{
		auto ent = enforceEx!PathNotFoundException(
			getRootDirectory().find(path),
			format("Directory `%s' not found", path));
		enforceEx!PathNotFoundException(ent.isDirectory(),
			format("`%s' is not a directory", path));

		static struct Iterator
		{
			int opApply(int delegate(XeEntry) action)
			{
				foreach (entry; _impl)
				{
					if (entry.getName().match(_re) && action(entry))
						return 1;
				}
				return 0;
			}
			XeDirectory.Iterator _impl;
			Regex!char _re;
		}

		return Iterator((cast(XeDirectory) ent).enumerate(), regex(maskToRegex(mask)));
	}

private:
	struct TypeDelegates
	{
		XeFileSystem function(XeDisk disk) tryOpen;
		XeFileSystem function(XeDisk disk) doCreate;
	}

	static Nullable!TypeDelegates[string] types_;
}
