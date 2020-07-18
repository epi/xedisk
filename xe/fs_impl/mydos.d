// Written in the D programming language

/*
mydos.d - implementation of MyDOS file system
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

module xe.fs_impl.mydos;

debug import std.stdio;
import std.ascii;
import std.exception;
import std.typecons;
import std.datetime;
import std.range;
import std.string;
import std.bitmanip;
import std.regex;
import std.conv;
import std.algorithm;
import xe.disk;
import xe.fs;
import xe.fs_impl.vtoc;
import xe.fs_impl.cache;
import xe.bytemanip;
import xe.streams;

version (unittest)
{
	import std.file;
	import xe.test;
}

private struct CachedEntry
{
	private SectorCache _cache;
	private uint _sector;
	private uint _offset;

	private auto request() { return _cache.request(_sector + _offset / 128); }

	@property bool isNull() { return _cache is null; }

	this(SectorCache cache, uint sector, uint offset) { assert(sector >= 1 && sector <= cache.getSectors() && offset % 16 == 0); _cache = cache; _sector = sector, _offset = offset; }

	ubyte opIndex(size_t i)                          { assert (i < 16); return request()[_offset % 128 + i]; }
	T opIndexAssign(T)(T val, size_t i)              { assert (i < 16); return request()[_offset % 128 + i] = val; }
	T opIndexOpAssign(string op, T)(T val, size_t i) { assert (i < 16); return mixin("request()[_offset % 128 + i] " ~ op ~ "= val"); }

	const(ubyte)[] opSlice()                         { return request()[_offset % 128 .. _offset % 128 + 16]; }
	const(ubyte)[] opSlice(size_t b, size_t e)       { assert (e <= 16 && b <= e); return request()[_offset % 128 + b .. _offset % 128 + e]; }

	void opSliceAssign(ubyte data)                    { request()[_offset % 128 .. _offset %128 + 16] = data; }
	void opSliceAssign(in ubyte[] data)                  { request()[_offset % 128 .. _offset % 128 + 16] = data[]; }
	void opSliceAssign(in ubyte[] d, size_t b, size_t e) { assert (e <= 16 && b <= e); request()[_offset % 128 + b .. _offset % 128 + e] = d[]; }

	@property ubyte status() { return this[0]; }
	@property void status(ubyte val) { this[0] = val; }

	@property string name() { return cast(string) this[5 .. 16].idup; }
	@property void name(string s) { assert(s.length == 11); this[5 .. 16] = (cast(immutable(ubyte)[]) s)[]; }

	@property uint sectors() { auto a = this[1 .. 3]; return makeWord(a[1], a[0]); }
	@property void sectors(uint s) { assert(s < 65536); this[1 .. 3] = [ getByte!0(s), getByte!1(s) ]; }

	@property uint firstSector() { auto a = this[3 .. 5]; return makeWord(a[1], a[0]); }
	@property void firstSector(uint s) { assert(s < 65536); this[3 .. 5] = [ getByte!0(s), getByte!1(s) ]; }

	@property uint fileNumber() { return _offset / 16; }
}

unittest
{
	mixin(Test!"CachedEntry (1)");
	auto disk = new TestDisk(720, 256, 3);
	scope cache = new SectorCache(disk, 16, false);

	auto sec4 = cache.alloc(4);
	auto sec5 = cache.alloc(5);

	auto ep1 = CachedEntry(cache, 4, 16);
	auto ep2 = CachedEntry(cache, 4, 240);

	assert(CachedEntry.init.isNull);
	assert(!ep1.isNull);
	assert(!ep2.isNull);

	assert(ep1.fileNumber == 1);
	assert(ep2.fileNumber == 15);

	ep1[] = 0xa5;
	assert(ep1[] == array(std.range.repeat(cast(ubyte) 0xa5, 16)));
	ep2[] = cast(immutable(ubyte)[]) "0123456789ABCDEF";
	assert(ep2[] == cast(immutable(ubyte)[]) "0123456789ABCDEF");

	ep1[0] = 0x55;
	ep2.status = 0x99;
	assert(sec4[16] == 0x55);
	assert(sec5[112] == 0x99);
	assert(sec4[16] == ep1.status);
	assert(sec5[112] == ep2[0]);

	ep1.name = "NAME    EXT";
	ep2.name = "TEST       ";
	assert(sec4[16 + 5 .. 16 + 16] == cast(immutable(ubyte)[]) "NAME    EXT");
	assert(sec5[112 + 5 .. 112 + 16] == cast(immutable(ubyte)[]) "TEST       ");
	assert(sec4[16 + 5 .. 16 + 16] == ep1[5 .. 16]);
	assert(sec5[112 + 5 .. 112 + 16] == ep2[5 .. 16]);
	assert(ep1.name == "NAME    EXT");
	assert(ep2.name == "TEST       ");

	sec4[17 .. 19] = [ 0xad, 0xde ];
	assert(ep1.sectors == 0xdead);
	ep1.sectors = 31337;
	assert(ep1.sectors == 31337);

	sec5[115 .. 117] = [ 0xef, 0xbe ];
	assert(ep2.firstSector == 0xbeef);
	ep2.firstSector = 31337;
	assert(ep2.firstSector == 31337);
}

private struct EntryRange
{
	private SectorCache _cache;
	private uint _firstSector;
	private uint _fileNumber;

	this(SectorCache cache, uint firstSector) { _cache = cache; _firstSector = firstSector; }

	@property bool empty() { return _fileNumber >= 64; }
	@property CachedEntry front() { assert(_fileNumber < 64); return CachedEntry(_cache, _firstSector, _fileNumber * 16); }
	void popFront() { assert(_fileNumber < 64); ++_fileNumber; }
	@property EntryRange save() { return this; }
}

unittest
{
	mixin(Test!"EntryRange (1)");
	auto disk = new TestDisk("testfiles/MYDOS450.ATR", 16, 128, 3);
	scope cache = new SectorCache(disk, 16, false);

	string[] names;
	foreach (entry; EntryRange(cache, 361).save)
	{
		if (entry.status == 0x42)
			names ~= entry.name;
	}
	assert (names == [ "DOS     SYS", "DUP     SYS", "RAMBOOT M65", "RAMBOOT AUT", "RAMBOOT3M65", "RAMBOOT3AUT", "READ    ME " ]);
}

private	enum EntryStatus : ubyte
{
	Deleted = 0x80,
	File = 0x42,
	ReadOnly = 0x20,
	Directory = 0x10,
	LongLinks = 0x04,
	OpenForWriting = 0x01,
	Unused = 0x00
}

private string formatFileName(string name)
out(result)
{
	assert (result.length == 11);
}
body
{
	/* from MyDOS user manual:
	  "A fully specified file name consists of
	   one  to eight characters followed by a period (".") and zero to three
	   additional "extender" characters. The characters in the file name may
	   be  upper or lower case letters, numbers, the underscore ("_") or the
	   character "@". The only exception is the first character - it may not
	   be  a  number. "
	   MyDOS 4.50 actually allows names longer than 8 characters, ignoring the
	   extension in such case and truncating the name to 11 chars if it's even
	   longer. Also, both name and extension can be empty, as long as the
	   dot is present in the parsed string. In particular, the name "." is
	   accepted by MyDOS 4.50, and expanded to 11 space characters.
	   A dot may appear more than once. It seems that it is ignored (together
	   with all characters following it).
	   The parsing mechanism here is meant to follow the documented behavior only.
	*/
	auto m = match(name.toUpper(), r"^([A-Z_@][A-Z0-9_@]{0,7})(?:\.([A-Z0-9_@]{0,3}))?$");
	if (!m)
		throw new Exception(format("Invalid file name `%s'", name));
	auto c = m.captures;
	return format("%-8s%-3s", c[1], c[2]);
}

private string unformatFileName(string s)
{
	string sname = s[0 .. 8].stripRight().toLower();
	string sext = s[8 .. 11].stripRight().toLower();
	return sext.length ? sname ~ "." ~ sext : sname;
}

unittest
{
	assert (formatFileName("X") == "X          ");
	assert (formatFileName("duPa.r") == "DUPA    R  ");
	assert (formatFileName("@dupa.ext") == "@DUPA   EXT");
	assertThrown(formatFileName(""));
	assertThrown(formatFileName("."));
	assertThrown(formatFileName(".x"));
	assertThrown(formatFileName("nametoolong.a"));
	assertThrown(formatFileName("no#allow.ed"));
}

private mixin template ImplementCommon()
{
	override bool isHidden() { return false; }
	override void setHidden(bool value) { /+ ignore or throw? +/ }
	override bool isArchive() { return false; }
	override void setArchive(bool value) { /+ ignore or throw? +/ }
	override DateTime getTimeStamp() { return DateTime.init; }
	override void setTimeStamp(DateTime timeStamp) { /+ ignore or throw? +/ }
}

private mixin template ImplementRegularEntry()
{
	override MydosDirectory getParent() { return _parent; }
	override string getName() { return unformatFileName(_entry.name); }
	override void rename(string newName)
	{
		enforce (!isReadOnly(), format("Cannot rename read only file `%s'", getName()));
		_entry.name = formatFileName(newName);
	}
	override uint getSectors() { return _entry.sectors; }
	override bool isReadOnly() { return cast(bool) (_entry.status & EntryStatus.ReadOnly); }
	override void setReadOnly(bool value)
	{
		_entry.status = value ? (_entry.status | EntryStatus.ReadOnly) : (_entry.status & ~EntryStatus.ReadOnly);
	}
}

private mixin template ImplementDirectory()
{
	mixin ImplementCommon;

	override ulong getSize() { return _fs._cache.getSectorSize() * getSectors(); }

	override OutputStream createFile(string name)
	{
		auto status = EntryStatus.File;
		if (_fs._longLinks)
			status |= EntryStatus.LongLinks;
		auto entry = createEntry(status, name, 1);
		return (new MydosFile(this, entry)).openWriteOnly();
	}

	override MydosDirectory createDirectory(string name)
	{
		auto entry = createEntry(EntryStatus.Directory, name, 8);
		return new MydosSubDirectory(this, entry);
	}

	override int doEnumerate(int delegate(XeEntry entry) action)
	{
		foreach (entry; this[])
		{
			int result;
			auto status = entry.status & (EntryStatus.File | EntryStatus.Directory | EntryStatus.Deleted);
			if (status == EntryStatus.File)
				result = action(new MydosFile(this, entry));
			else if (status == EntryStatus.Directory)
				result = action(new MydosSubDirectory(this, entry));
			else
				continue;
			if (result)
				return 1;
		}
		return 0;
	}

	private auto createEntry(EntryStatus status, string name, uint sectors)
	{
		string fname = formatFileName(name);

		// find entry with the same name (overwrite)
		// or, if this fails, an unused entry.
		CachedEntry newEntry;
		foreach (entry; this[])
		{
			if (entry.status == EntryStatus.Deleted || entry.status == EntryStatus.Unused)
			{
				if (newEntry.isNull())
					newEntry = entry;
				newEntry.firstSector = 0;
				continue;
			}
			else if (entry.name == fname)
			{
				if (entry.status == EntryStatus.Directory)
					throw new Exception(format("Cannot overwrite directory `%s'", name));
				if (status == EntryStatus.Directory)
					throw new Exception(format("File `%s' already exists", name));
				if (entry.status & EntryStatus.ReadOnly)
					throw new Exception(format("Cannot overwrite read only %s `%s'",
						entry.status == EntryStatus.Directory ? "directory" : "file", name));
				// if (entry.status & EntryStatus.OpenForWriting)
				//	throw new Exception("File is busy");
				newEntry = entry;
				break;
			}
		}
		if (newEntry.isNull())
			throw new Exception("Directory full");
		if (!newEntry.firstSector)
		{
			newEntry.firstSector = _fs._vtoc.allocContiguous(sectors);
			_fs.setFreeSectors(_fs.getFreeSectors() - sectors);
			newEntry.sectors = sectors;
			foreach (sec; newEntry.firstSector .. newEntry.firstSector + sectors)
				_fs._cache.alloc(sec)[] = 0;
		}
		newEntry.status = status;
		newEntry.name = fname;
		return newEntry;
	}

	private auto opSlice() { return EntryRange(_fs._cache, firstSector); }
}

class MydosDirectory : XeDirectory
{
}

class MydosRootDirectory : MydosDirectory
{
	mixin ImplementDirectory;

	override MydosDirectory getParent() { return null; }
	override string getName() { return ""; }
	override void rename(string newName) { throw new Exception("Cannot rename root directory"); }
	override void doRemove() { throw new Exception("Cannot delete root directory"); }
	override uint getSectors() { return 8; }
	override bool isReadOnly() { return true; } // because you can't delete or rename it
	override void setReadOnly(bool value) { throw new Exception("Cannot change read only flag for root directory"); }

	private this(MydosFileSystem fs) { _fs = fs; }

	private enum firstSector = 361;

	private MydosFileSystem _fs;
}

unittest
{
	auto disk = new TestDisk(720, 256, 3);
	scope fs = cast(MydosFileSystem) XeFileSystem.create(disk, "mydos");
	assert (fs);
	scope dir = fs.getRootDirectory();
	assert (dir.getParent() is null);
	assert (dir.getName() == "");
	assertThrown (dir.rename("root"));
	assertThrown (dir.remove(true));
	assert (dir.getSectors() == 8);
	assert (dir.getSize() == 2048);
	assert (dir.isReadOnly());
	assertThrown (dir.setReadOnly(false));
	assertThrown (dir.setReadOnly(true));
}

class MydosSubDirectory : MydosDirectory
{
	mixin ImplementDirectory;
	mixin ImplementRegularEntry;

	override void doRemove()
	{
		_entry.status = EntryStatus.Deleted;
		foreach (sector; _entry.firstSector .. _entry.firstSector + 8)
			_fs._vtoc[sector] = true;
		_fs.setFreeSectors(_fs.getFreeSectors() + 8);
	}

	private this(T)(T parent, CachedEntry entry) if (is(T : MydosDirectory) && __traits(compiles, parent._fs))
	{
		this._fs = parent._fs;
		_parent = parent;
		_entry = entry;
	}

	private @property uint firstSector()
	{
		if (!_firstSector)
			_firstSector = _entry.firstSector;
		return _firstSector;
	}

	private uint _firstSector;

	private MydosFileSystem _fs;
	private MydosDirectory _parent;
	private CachedEntry _entry;
}

unittest
{
	mixin(Test!"MydosDirectory.doEnumerate (1)");
	auto disk = new TestDisk("testfiles/MYDOS450.ATR", 16, 128, 3);
	scope fs = XeFileSystem.open(disk);
	assert (cast(MydosFileSystem) fs);
	string[] names;
	foreach (entry; fs.getRootDirectory().enumerate())
		names ~= entry.getName();
	assert (names == [
		"dos.sys",
		"dup.sys",
		"ramboot.m65",
		"ramboot.aut",
		"ramboot3.m65",
		"ramboot3.aut",
		"read.me"
	]);
}

unittest
{
	mixin(Test!"MydosDirectory.doEnumerate (2)");
	auto disk = new TestDisk("testfiles/MYDIRS.ATR", 16, 128, 3);
	scope fs = XeFileSystem.open(disk);
	assert (cast(MydosFileSystem) fs);
	string[] names;
	foreach (entry; fs.getRootDirectory().enumerate(XeSpanMode.Breadth))
		names ~= entry.getFullPath();
	assert (names == [
		"/dir1",
		"/dir1/dir11",
		"/dir1/dir12",
		"/dir2",
		"/dir2/dir21",
		"/dir2/dir21/dir211",
		"/dir2/dir21/dir212",
		"/dir2/dir21/dir212/file2121",
		"/dir3",
		"/dir3/dir31",
		"/dir3/dir32",
		"/dir3/dir33",
		"/dir4"
	]);
}

unittest
{
	mixin(Test!"MydosDirectory.remove (1)");
	auto disk = new TestDisk("testfiles/MYDIRS.ATR", 16, 128, 3);
	scope fs = cast(MydosFileSystem) XeFileSystem.open(disk);
	assert (fs);
	scope root = fs.getRootDirectory();
	scope dir211 = cast(XeDirectory) root.find("dir2/dir21/dir211");
	assert (dir211);
	{
	scope file = dir211.find("../dir212/file2121");
	file.setReadOnly(true);
	assertThrown (file.remove(false));
	assertThrown (root.find("dir2").remove(true));
	}
	scope file = dir211.find("/dir2/./dir21/dir212/file2121");
	file.setReadOnly(false);
	assertThrown (root.find("dir2").remove(false));
	root.find("dir2").remove(true);

	root.find("dir1").remove(true);
	root.find("dir3").remove(true);
	root.find("dir4").remove(true);
	assert (fs.getFreeSectors() == 708);
	assert (fs.getVtocFreeSectors() == 708);
}

unittest
{
	mixin(Test!"MydosDirectory.createEntry (1)");
	auto disk = new TestDisk(720, 256, 3);
	scope fs = cast(MydosFileSystem) XeFileSystem.create(disk, "mydos");
	assert (fs);
	assert (fs.getFreeSectors() == 708);
	scope dir = cast(MydosRootDirectory) fs.getRootDirectory();
	assert (dir);
	auto entry = dir.createEntry(EntryStatus.Directory, "test1", 8);
	assert (entry.status == EntryStatus.Directory);
	assert (entry.name == "TEST1      ");
	assert (entry.sectors == 8);
	assert (entry.fileNumber == 0);
	assert (entry.firstSector != 0); // implementation is free to locate it anywhere
	assert (fs.getFreeSectors() == 700);
	assert (fs.getVtocFreeSectors() == 700);
	entry = dir.createEntry(EntryStatus.Directory, "test2", 8);
	assert (entry.status == EntryStatus.Directory);
	assert (entry.name == "TEST2      ");
	assert (entry.fileNumber == 1);
	assert (fs.getFreeSectors() == 692);
	assert (fs.getVtocFreeSectors() == 692);
	assertThrown (dir.createEntry(EntryStatus.File, "test2", 8));
	assertThrown (dir.createEntry(EntryStatus.Directory, "test2", 8));
	entry = dir.createEntry(EntryStatus.File, "test3", 1);
	assert (fs.getFreeSectors() == 691);
	assert (fs.getVtocFreeSectors() == 691);
	assert (entry.fileNumber == 2);
	assert (entry.sectors == 1);
	assert (fs._cache.request(entry.firstSector)[$ - 3] == 0);
	assert (fs._cache.request(entry.firstSector)[$ - 2] == 0);
	assert (fs._cache.request(entry.firstSector)[$ - 1] == 0);
	assertThrown (dir.createEntry(EntryStatus.Directory, "test3", 8));
	entry.status = entry.status | EntryStatus.ReadOnly;
	assertThrown (dir.createEntry(EntryStatus.File, "test3", 1));
	entry.status = entry.status & ~EntryStatus.ReadOnly;
	dir.createEntry(EntryStatus.File, "test3", 1);
	assert (fs.getFreeSectors() == 691);
	assert (fs.getVtocFreeSectors() == 691);

	foreach (i; 4 .. 65)
		entry = dir.createEntry(EntryStatus.File, format("test%d", i), 1);
	assert (entry.fileNumber == 63);
	assert (entry.name == "TEST64     ");
	assertThrown (dir.createEntry(EntryStatus.File, "test65", 1));
	assert (fs.getFreeSectors() == 630);
	assert (fs.getVtocFreeSectors() == 630);

	fs._vtoc[entry.firstSector] = true;
	fs.setFreeSectors(fs.getFreeSectors() + 1);
	entry.status = EntryStatus.Deleted;
	entry = dir.createEntry(EntryStatus.File, "test64", 31);
	assert (entry.sectors == 31);
	assert (fs.getFreeSectors() == 600);
	assert (fs.getVtocFreeSectors() == 600);
}

unittest
{
	mixin(Test!"MydosDirectory.createDirectory (1)");
	auto disk = new TestDisk(720, 256, 3);
	scope fs = XeFileSystem.create(disk, "mydos");
	assert (cast(MydosFileSystem) fs);
	assert (fs.getFreeSectors() == 708);
	auto dir = fs.getRootDirectory().createDirectory("newdir");
	assert (cast(MydosDirectory) dir);
	assert (dir.getName() == "newdir");
	assert (dir.getSize() == 8 * 256);
	assert (fs.getFreeSectors() == 700);
	int a;
	foreach (entry; fs.getRootDirectory().enumerate())
		++a;
	assert (a == 1);
	a = 0;
	foreach (entry; dir.enumerate())
		++a;
	assert (a == 0);
	auto ent = fs.getRootDirectory().find("newdir");
}

private final class MydosFile : XeFile
{
	mixin ImplementCommon;
	mixin ImplementRegularEntry;

	override ulong getSize() { return reduce!((a, cs) => a + cs[$ - 1])(0, this[]); }

	override void doRemove()
	{
		_entry.status = EntryStatus.Deleted;
		uint nsec;
		foreach (cs; this[])
		{
			_fs._vtoc[cs.sector] = true;
			++nsec;
		}
		_fs.setFreeSectors(_fs.getFreeSectors() + nsec);
	}

	override InputStream openReadOnly()
	{
		return new class(this[]) InputStream
		{
			this(Range r) { _r = r; }

			override size_t doRead(ubyte[] buffer)
			{
				size_t read;
				while (read < buffer.length && !_r.empty)
				{
					uint f = _r.front[$ - 1];
					size_t toRead = min(buffer.length - read, f - _sectorOffset);
					buffer[read .. read + toRead] = _r.front[0 .. toRead][];
					if ((_sectorOffset += toRead) >= f)
					{
						_sectorOffset = 0;
						_r.popFront();
					}
					read += toRead;
				}
				return read;
			}

			Range _r;
			uint _sectorOffset;
		};
	}

	unittest
	{
		mixin(Test!"MydosFile.openReadOnly (1)");
		auto disk = new TestDisk("testfiles/MYDOS450.ATR", 16, 128, 3);
		scope fs = XeFileSystem.open(disk);
		auto f = cast(XeFile) fs.getRootDirectory().find("ramboot3.m65");
		assert (f !is null);
		auto buf = new ubyte[8192];
		assert (f.openReadOnly().read(buf) == 7111);
	}

	private class MydosFileOutputStream : OutputStream
	{
		this()
		{
			auto r = this.outer[];
				while (r.next) r.popFront();
			_sector = r.front.sector;
			_sectorOffset = r.front[$ - 1];
		}

		override void doWrite(in ubyte[] buffer)
		{
			enforce(!isReadOnly(), "File is read only");
			uint written;
			auto dbps = _fs._cache.getSectorSize() - 3;
			CachedSector buf;

			void updateLink(uint nextSector, uint fill)
			{
				if (_longLinks)
					buf[$ - 3] = getByte!1(nextSector);
				else
					buf[$ - 3] = cast(ubyte) ((getByte!1(nextSector) & 3) | (_entry.fileNumber << 2));
				buf[$ - 2] = getByte!0(nextSector);
				buf[$ - 1] = cast(ubyte) fill;
			}

			while (written < buffer.length)
			{
				if (_sectorOffset < dbps)
				{
					buf = (_sectorOffset > 0) ? _fs._cache.request(_sector) : _fs._cache.alloc(_sector);
					uint toWrite = min(buffer.length - written, dbps - _sectorOffset);
					buf[_sectorOffset .. _sectorOffset + toWrite] =
						buffer[written .. written + toWrite];
					written += toWrite;
					_sectorOffset += toWrite;
				}
				else // _sectorOffset >= dbps
				{
					uint nextSector = _fs._vtoc.allocContiguous(1, 4, false);
					buf = _fs._cache.request(_sector);
					updateLink(nextSector, _sectorOffset);
					if (!nextSector)
						throw new Exception("Disk full");
					_fs.setFreeSectors(_fs.getFreeSectors() - 1);
					_entry.sectors = _entry.sectors + 1;
					_sector = nextSector;
					_sectorOffset = 0;
				}
			}
			if (!buf.isNull())
				updateLink(0, _sectorOffset);
		}
		uint _sector;
		uint _sectorOffset;
	}

	override OutputStream openWriteOnly(bool append = false)
	{
		enforce(!isReadOnly(), format("Cannot open read only file `%s' for writing", getName()));
		if (!append)
			truncate();
		return new MydosFileOutputStream();
	}

	unittest
	{
		mixin(Test!"MydosFile.openWriteOnly (1)");
		auto disk = new TestDisk(720, 256, 3);
		scope fs = cast(MydosFileSystem) XeFileSystem.create(disk, "mydos");
		{
			scope fstream = cast(MydosFile.MydosFileOutputStream) fs.getRootDirectory().createFile("dupa");
			assert (fstream);
			assert (fstream.outer._entry.status == EntryStatus.File);
			assert (!fstream.outer._longLinks);
			assert (fstream.outer.getSectors() == 1);
			assert (fstream.outer.getSize() == 0);
			assert (fstream.outer.getName() == "dupa");
			assert (!fstream.outer.isReadOnly());
			assert (fs.getFreeSectors() == 707);
			assert (fs.getVtocFreeSectors() == 707);

			fstream.write(new ubyte[253]);
			assert (fstream.outer.getSectors() == 1);
			assert (fstream.outer.getSize() == 253);
			fstream.write(new ubyte[0]);
			assert (fstream.outer.getSectors() == 1);
			assert (fstream.outer.getSize() == 253);
			fstream.write(new ubyte[1]);
			assert (fstream.outer.getSectors() == 2);
			assert (fstream.outer.getSize() == 254);
			fstream.write(new ubyte[253 * 700]);
			assert (fstream.outer.getSectors() == 702);
			assert (fstream.outer.getSize() == 254 + 253 * 700);
			fstream.outer.setReadOnly(true);
			assertThrown (fstream.write(new ubyte[1]));
		}
		{
			scope file = cast(MydosFile) fs.getRootDirectory().find("dupa");
			assert (file.isReadOnly());
			assertThrown (file.rename("somefile"));
			assertThrown (file.openWriteOnly(true));
			file.setReadOnly(false);
			file.rename("somefile");
			assert (file.getName() == "somefile");
			scope fstream = cast(MydosFile.MydosFileOutputStream) file.openWriteOnly(true);
			assert (fstream.outer.getSectors() == 702);
			assert (fstream.outer.getSize() == 254 + 253 * 700);
			fstream.write(new ubyte[259]);
			assert (fstream.outer.getSectors() == 703);
			assert (fstream.outer.getSize() == 254 + 253 * 700 + 259);
		}
		{
			scope fstream = cast(MydosFile.MydosFileOutputStream) (cast(MydosFile) fs.getRootDirectory().find("somefile")).openWriteOnly();
			assert (fstream.outer.getSectors() == 1);
			assert (fstream.outer.getSize() == 0);
			assert (fs.getFreeSectors() == 707);
			assert (fs.getVtocFreeSectors() == 707);
			fstream.write(new ubyte[31337]);
			assert (fstream.outer.getSectors() == (31337 + 252) / 253);
			assert (fstream.outer.getSize() == 31337);
		}
	}

	unittest
	{
		mixin(Test!"MydosFile.openWriteOnly (2)");
		auto disk = new TestDisk(5000, 128, 3);
		scope fs = cast(MydosFileSystem) XeFileSystem.create(disk, "mydos");
		scope fstream = cast(MydosFile.MydosFileOutputStream) fs.getRootDirectory().createFile("dupa");
		assert (fstream);
		assert (fstream.outer._longLinks);
		assert (fstream.outer._entry.status == (EntryStatus.File | EntryStatus.LongLinks));
		assert (fstream.outer.getSectors() == 1);
		assert (fstream.outer.getSize() == 0);
		assert (fstream.outer.getName() == "dupa");
		assert (!fstream.outer.isReadOnly());
		fstream.write(new ubyte[128 * 4000]);
		assert (fstream.outer.getSize() == 128 * 4000);
	}

	private static struct Range
	{
		private MydosFileSystem _fs;
		private uint _current;
		private bool _longLinks;

		this(MydosFile file)
		{
			_fs = file._fs;
			_current = file._entry.firstSector;
			_longLinks = !!(file._entry.status & EntryStatus.LongLinks);
		}

		@property bool longLinks() { return _longLinks; }
		@property bool empty() { return _current == 0; }
		@property auto front() { return _fs._cache.request(_current); }
		void popFront() { assert (!empty); _current = next(); }

		@property uint next()
		{
			auto l = front.length;
			auto n = makeWord(front[l - 3 .. l - 1]);
			return _longLinks ? n : n & 0x3ff;
		}

		@property auto save() { return this; }
	}

	private auto opSlice() { return Range(this); }

	private void truncate()
	{
		auto r = this[];
		auto first = r.front;
		r.popFront();
		// clear the sector (null link, 0 bytes of data);
		// r will span the remaining part of the file
		_fs._cache.alloc(first.sector)[] = 0;
		// reset length
		_entry.sectors = 1;
		// update vtoc and # of free sectors;
		uint nsec;
		foreach (sec; r)
		{
			_fs._vtoc[sec.sector] = true;
			++nsec;
		}
		_fs.setFreeSectors(_fs.getFreeSectors() + nsec);
	}

	private this(T)(T parent, CachedEntry entry) if (is(T : MydosDirectory) && __traits(compiles, parent._fs))
	{
		this._fs = parent._fs;
		_parent = parent;
		_entry = entry;
		_longLinks = !!(entry.status & EntryStatus.LongLinks);
	}

	private MydosFileSystem _fs;
	private MydosDirectory _parent;
	private CachedEntry _entry;
	private bool _longLinks;
}

class MydosFileSystem : XeFileSystem
{
	override uint getFreeSectors()
	{
		auto buf = _cache.request(360);
		return makeWord(buf[4], buf[3]);
	}

	override ulong getFreeBytes()
	{
		return (_cache.getSectorSize() - 3) * getFreeSectors();
	}

	override XeDirectory getRootDirectory() { return new MydosRootDirectory(this); }
	override string getLabel() { return ""; }
	override void setLabel(string value) { /+ ignore or throw? +/ }
	override string getType() { return "MyDOS"; }

	override bool isValidName(string name)
	{
		return !!match(name, r"^[A-Za-z_@][A-Za-z0-9_@]{0,7}(?:\.[A-Za-z0-9@_]{0,3})?$");
	}

	override string adjustName(string name)
	out (result)
	{
		assert (isValidName(result),
			format("Generated name `%s' is not valid", result));
	}
	body
	{
		name = name.toLower().tr("a-z0-9@.", "_", "sc");
		if (isDigit(name[0]))
			name = "@" ~ name;
		auto com = regex(r"^([^.]{1,8})[^.]*(\..{0,3})?.*$");
		return replace(name, com, "$1$2");
	}

	unittest
	{
		mixin(Test!"MydosFileSystem.adjustName (1) ok");
		MydosFileSystem nullfs = new MydosFileSystem();
		assert (nullfs.adjustName("inVaL!).chrS") == "inval_.chr");
		assert (nullfs.adjustName("this_name_is_.too_long") == "this_nam.too");
		assert (nullfs.adjustName("0DIGITS") == "@0digits");
	}

	override void writeDosFiles(string dosVersion)
	{
		switch (dosVersion.toLower())
		{
		case "mydos450":
		case "mydos450t":
		case "450":
		case "450t":
			auto rootDir = getRootDirectory();
			{
			scope f = rootDir.createFile("DOS.SYS");
			f.write(_dosSys450t[384 .. $]);
			}
			{
			scope f = rootDir.createFile("DUP.SYS");
			f.write(_dupSys450t);
			}
			auto firstSector =
				(cast(MydosFile) rootDir.find("DOS.SYS"))._entry.firstSector;
			auto init = _dosSys450t[0 .. 384].dup;
			init[14] = _cache.getSectorSize() == 256 ? 2 : 1;
			init[15] = getByte!0(firstSector);
			init[16] = getByte!1(firstSector);
			init[17] = cast(ubyte) (_cache.getSectorSize() - 3);
			_cache.alloc(1)[] = init[0 .. 128];
			_cache.alloc(2)[] = init[128 .. 256];
			_cache.alloc(3)[] = init[256 .. 384];
			break;
		default:
			throw new Exception(
				"Invalid or unsupported MyDOS version specified");
		}
	}

	static this()
	{
		registerType("MYDOS", &tryOpen, &doCreate);
	}

	version (unittest)
	{
		private this() {}
	}

	private this(XeDisk disk, bool create = false)
	{
		_cache = new SectorCache(disk);
		auto bps = _cache.getSectorSize();
		_vtoc = Vtoc(_cache, bps == 256 ? &bitLocation!256 : &bitLocation!128);

		if (create)
		{
			auto nsec = _cache.getSectors();
			enforce(nsec >= 369 && nsec <= 65535 && (bps == 128 || bps == 256), "Invalid disk geometry");

			auto vtocSize = vtocSizeFromGeometry(nsec, bps);
			auto lastVtocSector = 361 - vtocSize;
			foreach (sec; lastVtocSector .. 369)
				_cache.alloc(sec)[] = 0;

			_cache.alloc(1)[0] = 'M';
			_cache.request(360)[0] = vtocMarkFromGeometry(nsec, bps);

			// all sectors (except boot area, vtoc and root dir) free
			foreach (sec; 4 .. lastVtocSector)
				_vtoc[sec] = true;
			foreach (sec; 369 .. nsec + 1)
				_vtoc[sec] = true;
			setFreeSectors(nsec - 3 - vtocSize - 8);
			_cache.flush();
		}
		auto buf = _cache.request(360);
		_longLinks = buf[0] > 2;
	}

	~this()
	{
		if (_cache)
			_cache.flush();
	}

	private auto bitLocation(uint bps)(uint sector)
	{
		auto bit = (sector + 80) % 8;
		auto byt = (sector + 80) / 8;
		return BitLocation(360 - byt / bps, byt % bps, 0x80u >>> bit);
	}

	private static MydosFileSystem tryOpen(XeDisk disk)
	{
		{
			scope cache = new SectorCache(disk);
			auto bps = cache.getSectorSize();
			if (bps != 128 && bps != 256)
				return null;
			auto buf = cache.request(1);
			if (buf[0] != 'M')
				return null;
			buf = cache.request(360);
			if (vtocSizeFromVtocMark(buf[0], bps) != vtocSizeFromGeometry(cache.getSectors(), bps))
				return null;
		}
		return new MydosFileSystem(disk);
	}

	private static MydosFileSystem doCreate(XeDisk disk)
	{
		return new MydosFileSystem(disk, true);
	}

	private void setFreeSectors(uint val)
	{
		assert (val < _cache.getSectors());
		auto buf = _cache.request(360);
		buf[3] = getByte!0(val);
		buf[4] = getByte!1(val);
	}

	private uint getVtocFreeSectors()
	{
		uint result;
		foreach (sector; 1 .. _cache.getSectors() + 1)
			if (_vtoc[sector]) result++;
		return result;
	}

	private SectorCache _cache;
	private bool _longLinks;
	private Vtoc _vtoc;

	private static _dosSys450t =
		cast(immutable(ubyte[])) import("mydos450t_dos.sys");
	private static _dupSys450t =
		cast(immutable(ubyte[])) import("mydos450t_dup.sys");
}

unittest
{
	mixin(Test!"MydosFileSystem (1)");
	assert (MydosFileSystem.tryOpen(new TestDisk("testfiles/DOS25.XFD", 0, 128, 3)) is null);
	assert (cast(MydosFileSystem) MydosFileSystem.tryOpen(new TestDisk("testfiles/MYDOS450.ATR", 16, 128, 3)) !is null);
	assert (cast(MydosFileSystem) MydosFileSystem.tryOpen(new TestDisk("testfiles/MYDOS453.ATR", 16, 128, 3)) !is null);
}

unittest
{
	mixin(Test!"MydosFileSystem (2)");
	{
		auto disk = new TestDisk(720, 256, 3);
		scope fs = cast(MydosFileSystem) XeFileSystem.create(disk, "MYDOS");
		assert (fs);
		assert (fs.getFreeSectors() == 708);
		assert (fs.getVtocFreeSectors() == 708);
		assert (fs.getFreeBytes() == 708 * 253);
	}
	{
		auto disk = new TestDisk(31337, 256, 3);
		scope fs = cast(MydosFileSystem) XeFileSystem.create(disk, "MYDOS");
		assert (fs !is null);
		assert (fs.getFreeSectors() == 31310);
		assert (fs.getVtocFreeSectors() == 31310);
		bool f;
		foreach (sec; 361 - 16 .. 361)
			f |= fs._vtoc[sec];
		assert (!f);
		assert (vtocSizeFromVtocMark(fs._cache.request(360)[0], 256) == 16);
	}
	{
		auto disk = new TestDisk(31337, 128, 3);
		scope fs = cast(MydosFileSystem) XeFileSystem.create(disk, "MYDOS");
		assert (fs !is null);
		assert (fs.getFreeSectors() == 31294);
		assert (fs.getVtocFreeSectors() == 31294);
		bool f;
		foreach (sec; 361 - 32 .. 361)
			f |= fs._vtoc[sec];
		assert (!f);
		assert (vtocSizeFromVtocMark(fs._cache.request(360)[0], 128) == 32);
	}
}

unittest
{
	mixin(Test!"MydosFile read/write");
	auto data = cast(ubyte[]) std.file.read("testfiles/DOS25.XFD");
	auto disk = new TestDisk(720, 256, 3);
	scope fs = cast(MydosFileSystem) XeFileSystem.create(disk, "mydos");
	{
		scope fstream = fs.getRootDirectory().createFile("file1");
		fstream.write(data);
	}
	{
		auto buf = new ubyte[data.length + 1];
		scope fstream = (cast(MydosFile) fs.getRootDirectory().find("file1")).
			openReadOnly();
		auto r = fstream.read(buf);
		assert (r == data.length);
		assert (buf[0 .. r] == data[]);
	}
}

int vtocSizeFromGeometry(int totalSectors, int bytesPerSector)
{
	int vg = 1 + (totalSectors + 80) / (bytesPerSector * 8);
	if (bytesPerSector == 128 && vg > 1)
		return (vg + 1) & ~1;
	return vg;
}

unittest
{
	mixin(Test!"vtocSizeFromGeometry (1)");
	assert (vtocSizeFromGeometry(  721, 256) == 1);
	assert (vtocSizeFromGeometry( 1440, 256) == 1);
	assert (vtocSizeFromGeometry( 2880, 256) == 2);
	assert (vtocSizeFromGeometry( 4000, 256) == 2);
	assert (vtocSizeFromGeometry( 7000, 256) == 4);
	assert (vtocSizeFromGeometry(32768, 256) == 17);
	assert (vtocSizeFromGeometry(65535, 256) == 33);
	assert (vtocSizeFromGeometry(  720, 128) == 1);
	assert (vtocSizeFromGeometry( 1040, 128) == 2);
	assert (vtocSizeFromGeometry( 1440, 128) == 2);
	assert (vtocSizeFromGeometry(32768, 128) == 34);
	assert (vtocSizeFromGeometry(65535, 128) == 66);
}

int vtocSizeFromVtocMark(ubyte mark, int bytesPerSector)
{
	if (mark < 3)
		return 1;
	switch (bytesPerSector)
	{
	case 128:
		return (mark - 2) * 2;
	case 256:
		return mark - 2;
	default:
		return -1;
	}
}

unittest
{
	mixin(Test!"vtocSizeFromVtocMark (1)");
	assert (vtocSizeFromVtocMark( 2, 256) == 1);
	assert (vtocSizeFromVtocMark( 2, 128) == 1);
	assert (vtocSizeFromVtocMark( 3, 256) == 1);
	assert (vtocSizeFromVtocMark( 4, 256) == 2);
	assert (vtocSizeFromVtocMark( 4, 128) == 4);
	assert (vtocSizeFromVtocMark( 4, 512) == -1);
}

// compute VTOC mark (1st byte of sector 360)
// if =2, whole VTOC fits in sector 360 AND all sectors can be enumerated using 10-bit counter.
ubyte vtocMarkFromGeometry(int totalSectors, int bytesPerSector)
out (result)
{
	assert (result >= 2 && result <= 0x23);
}
body
{
	int vg = vtocSizeFromGeometry(totalSectors, bytesPerSector);
	switch (bytesPerSector)
	{
	case 128:
		return cast(ubyte) (vg == 1 ? 2 : (vg + 1) / 2 + 2);
	case 256:
		return cast(ubyte) (totalSectors < 1024 ? 2 : 2 + vg);
	default:
		assert (false);
	}
}

unittest
{
	mixin(Test!"vtocMarkFromGeometry (1)");
	assert (vtocMarkFromGeometry( 720, 256) == 2);
	assert (vtocMarkFromGeometry(1023, 256) == 2);
	assert (vtocMarkFromGeometry(1024, 256) == 3);
	assert (vtocMarkFromGeometry( 943, 128) == 2);  // (128 - 10) * 8 - 1
	assert (vtocMarkFromGeometry( 944, 128) == 3);
}
