import std.algorithm;
import std.datetime;
import std.exception;
import std.stdio;
import std.string;
import core.memory;
import core.exception;
import core.stdc.stdlib;
import core.stdc.time;

import xe.streams;
import xe.disk;
import xe.disk_impl.all;
import xe.fs;
import xe.fs_impl.all;

private string lastExceptionMsg;

private void resetLastException()
{
	lastExceptionMsg = null;
}

private void setLastException(string msg)
{
	lastExceptionMsg = msg ~ "\0";
	debug stderr.writeln("Exception: ", msg);
}

private mixin template FreeList(T) if (is(T == struct))
{
	static T* alloc()
	{
		T* p;
		if (_freelist)
		{
			p = _freelist;
			_freelist = p._next;
		}
		else
		{
			debug ++_nalloc;
			p = cast(T*) core.stdc.stdlib.malloc(T.sizeof);
			if (!p)
				throw new OutOfMemoryError();
			GC.addRange(p, T.sizeof);
			*p = T.init;
		}
		return p;
	}

	static void free(T* p)
	{
//		clear(p);
		p._next = _freelist;
		_freelist = p;
	}

	static ~this()
	{
		debug size_t i;
		while (_freelist)
		{
			T* p = _freelist;
			_freelist = p._next;
			GC.removeRange(p);
			core.stdc.stdlib.free(p);
			debug ++i;
		}
		debug
		{
			stderr.writefln("Freed %s objects (of %s allocated) of type %s",
				i, _nalloc, T.stringof);
			if (i != _nalloc)
				stderr.writefln(" %s object(s) haven't been returned!",
					_nalloc - i);
		}
	}

	static T* _freelist;
	static size_t _nalloc;
	T* _next;
}

private struct CXeString
{
	string impl;
	mixin FreeList!CXeString;
}

private struct CXeInputStream
{
	InputStream impl;
	mixin FreeList!CXeInputStream;
}

private struct CXeDisk
{
	XeDisk impl;
	string type;
	mixin FreeList!CXeDisk;
}

private struct CXeFileSystem
{
	XeFileSystem impl;
	string type;
	mixin FreeList!CXeFileSystem;
}

private struct CXeEntry
{
	XeEntry impl;
	string name;
	mixin FreeList!CXeEntry;
}

private struct CXeFile
{
	XeFile impl;
	mixin FreeList!CXeFile;
}

private struct CXeDirectory
{
	XeDirectory impl;
	mixin FreeList!CXeDirectory;
}

private const(char)[] cstrToString(const(char*) str)
{
	size_t i;
	while (str[i]) ++i;
	return str[0 .. i];
}

export extern (C)
const(char)* XeDisk_GetLastError()
{
	return lastExceptionMsg.ptr;
}

private T* XeAlloc(T)()
{
	return T.alloc();
}

private void XeFree(T)(T* p)
{
	if (!p)
		return;
	T.free(p);
}

export extern (C)
size_t XeInputStream_Read(CXeInputStream* cistream, void* buf, size_t len)
{
	resetLastException();
	try
		return cistream.impl.read((cast(ubyte*) buf)[0 .. len]);
	catch (Exception e)
		setLastException(e.msg);
	return size_t.max;
}

export extern (C)
void XeInputStream_Free(CXeInputStream* cistream)
{
	resetLastException();
	try
		XeFree(cistream);
	catch (Exception e)
		setLastException(e.msg);
}

export extern (C)
CXeDisk* XeDisk_OpenFile(const(char)* fileName, XeDiskOpenMode mode)
{
	resetLastException();
	try
	{
		string fmode;
		switch (mode)
		{
		case XeDiskOpenMode.ReadOnly:  fmode = "rb";  break;
		case XeDiskOpenMode.ReadWrite: fmode = "r+b"; break;
		default: throw new Exception("Invalid disk open mode");
		}
		auto cdisk = XeAlloc!CXeDisk();
		scope(failure) XeFree(cdisk);
		auto file = File(cstrToString(fileName).idup, fmode);
		scope(failure) file.close();
		auto stream = new FileStream(file);
		cdisk.impl = XeDisk.open(stream, mode);
		return cdisk;
	}
	catch (Exception e)
		setLastException(e.msg);
	return null;
}

export extern (C)
CXeDisk* XeDisk_CreateFile(const(char)* fileName, const(char)* type,
	uint numSectors, uint bytesPerSector)
{
	resetLastException();
	try
	{
		auto cdisk = XeAlloc!CXeDisk();
		scope(failure) XeFree(cdisk);
		auto file = File(cstrToString(fileName).idup, "w+b");
		scope(failure) file.close();
		auto stream = new FileStream(file);
		cdisk.impl = XeDisk.create(stream, cstrToString(type).idup,
			numSectors, bytesPerSector);
		return cdisk;
	}
	catch (Exception e)
		setLastException(e.msg);
	return null;
}

export extern (C)
void XeDisk_Free(CXeDisk* cdisk)
{
	resetLastException();
	try
		XeFree(cdisk);
	catch (Exception e)
		setLastException(e.msg);
}

export extern (C)
uint XeDisk_GetSectors(CXeDisk* cdisk)
{
	resetLastException();
	try
		return cdisk.impl.getSectors();
	catch (Exception e)
		setLastException(e.msg);
	return uint.max;
}

export extern (C)
uint XeDisk_GetSectorSize(CXeDisk* cdisk)
{
	resetLastException();
	try
		return cdisk.impl.getSectorSize();
	catch (Exception e)
		setLastException(e.msg);
	return uint.max;
}

export extern (C)
const(char)* XeDisk_GetType(CXeDisk* cdisk)
{
	resetLastException();
	try
	{
		if (!cdisk.type)
			cdisk.type = cdisk.impl.getType() ~ "\0";
		return cdisk.type.ptr;
	}
	catch (Exception e)
		setLastException(e.msg);
	return null;
}

export extern (C)
CXeFileSystem* XeFileSystem_Open(CXeDisk* cdisk)
{
	resetLastException();
	try
	{
		auto cfs = XeAlloc!CXeFileSystem();
		cfs.impl = XeFileSystem.open(cdisk.impl);
		return cfs;
	}
	catch (Exception e)
		setLastException(e.msg);
	return null;
}

export extern (C)
void XeFileSystem_Free(CXeFileSystem* cfs)
{
	resetLastException();
	try
		XeFree(cfs);
	catch (Exception e)
		setLastException(e.msg);
}

export extern (C)
const(char)* XeFileSystem_GetType(CXeFileSystem* cfs)
{
	resetLastException();
	try
	{
		if (!cfs.type)
			cfs.type = cfs.impl.getType() ~ "\0";
		return cfs.type.ptr;
	}
	catch (Exception e)
		setLastException(e.msg);
	return null;
}

export extern (C)
uint XeFileSystem_GetFreeSectors(CXeFileSystem* cfs)
{
	resetLastException();
	try
		return cfs.impl.getFreeSectors();
	catch (Exception e)
		setLastException(e.msg);
	return uint.max;
}

export extern (C)
ulong XeFileSystem_GetFreeBytes(CXeFileSystem* cfs)
{
	resetLastException();
	try
		return cfs.impl.getFreeBytes();
	catch (Exception e)
		setLastException(e.msg);
	return ulong.max;
}

export extern (C)
CXeDirectory *XeFileSystem_GetRootDirectory(CXeFileSystem* cfs)
{
	resetLastException();
	try
	{
		auto cdir = XeAlloc!CXeDirectory();
		cdir.impl = cfs.impl.getRootDirectory();
		return cdir;
	}
	catch (Exception e)
		setLastException(e.msg);
	return null;
}

export extern (C)
void XeDirectory_Free(CXeDirectory* cdir)
{
	resetLastException();
	try
		XeFree(cdir);
	catch (Exception e)
		setLastException(e.msg);
}


export extern (C)
void XeDirectory_Enumerate(
	CXeDirectory* cdir,
	int function(void *pUserData, CXeEntry *pEntry) callback,
	void *pUserData)
{
	foreach (entry; cdir.impl.enumerate())
	{
		CXeEntry centry;
		centry.impl = entry;
		callback(pUserData, &centry);
	}
}

export extern (C)
CXeEntry *XeDirectory_Find(CXeDirectory* cdir, const(char)* name)
{
	resetLastException();
	try
	{
		auto centry = XeAlloc!CXeEntry();
		scope(failure) XeFree(centry);
		centry.impl = enforce(cdir.impl.find(cstrToString(name).idup),
			format("Not found: `%s'", cstrToString(name)));
		return centry;
	}
	catch (Exception e)
		setLastException(e.msg);
	return null;
}

export extern (C)
void XeEntry_Free(CXeEntry* centry)
{
	resetLastException();
	try
		XeFree(centry);
	catch (Exception e)
		setLastException(e.msg);
}

export extern (C)
const(char)* XeEntry_GetName(CXeEntry* centry)
{
	resetLastException();
	try
	{
		if (!centry.name)
			centry.name = centry.impl.getName() ~ "\0";
		return centry.name.ptr;
	}
	catch (Exception e)
		setLastException(e.msg);
	return null;
}

export extern (C)
ulong XeEntry_GetSize(CXeEntry* centry)
{
	resetLastException();
	try
		return centry.impl.getSize();
	catch (Exception e)
		setLastException(e.msg);
	return ulong.max;
}

export extern (C)
time_t XeEntry_GetTimeStamp(CXeEntry* centry)
{
	resetLastException();
	try
		return SysTime(centry.impl.getTimeStamp()).toUnixTime();
	catch (Exception e)
		setLastException(e.msg);
	return ulong.max;
}

export extern (C)
int XeEntry_IsDirectory(CXeEntry* centry)
{
	resetLastException();
	try
		return centry.impl.isDirectory();
	catch (Exception e)
		setLastException(e.msg);
	return ulong.max;
}

export extern (C)
int XeEntry_IsFile(CXeEntry* centry)
{
	resetLastException();
	try
		return centry.impl.isFile();
	catch (Exception e)
		setLastException(e.msg);
	return ulong.max;
}

export extern (C)
CXeDirectory* XeEntry_AsDirectory(CXeEntry* centry)
{
	resetLastException();
	try
	{
		auto cdir = XeAlloc!CXeDirectory();
		scope(failure) XeFree(cdir);
		cdir.impl = enforce(cast(XeDirectory) centry.impl,
			"Not a directory");
		return cdir;
	}
	catch (Exception e)
		setLastException(e.msg);
	return null;
}

export extern (C)
CXeFile* XeEntry_AsFile(CXeEntry* centry)
{
	resetLastException();
	try
	{
		auto cdir = XeAlloc!CXeFile();
		scope(failure) XeFree(cdir);
		cdir.impl = enforce(cast(XeFile) centry.impl,
			"Not a file");
		return cdir;
	}
	catch (Exception e)
		setLastException(e.msg);
	return null;
}

export extern (C)
void XeFile_Free(CXeFile* cfile)
{
	resetLastException();
	try
		XeFree(cfile);
	catch (Exception e)
		setLastException(e.msg);
}

export extern (C)
CXeInputStream* XeFile_OpenReadOnly(CXeFile* cfile)
{
	resetLastException();
	try
	{
		auto cistream = XeAlloc!CXeInputStream();
		scope(failure) XeFree(cistream);
		cistream.impl = enforce(cfile.impl.openReadOnly(),
			"Failed to open");
		return cistream;
	}
	catch (Exception e)
		setLastException(e.msg);
	return null;
}
