import std.algorithm;
import std.stdio;
import core.memory;
import core.stdc.stdlib;

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

private void setLastException(Exception e)
{
	lastExceptionMsg = e.msg ~ "\0";
}

private struct CXeDisk
{
	XeDisk impl;
	string type;
}

private struct CXeFileSystem
{
	XeFileSystem impl;
	string type;
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
		auto file = File(cstrToString(fileName).idup, fmode);
		auto stream = new FileStream(file);
		auto cdisk = new CXeDisk;
		cdisk.impl = XeDisk.open(stream, mode);
		GC.addRoot(cdisk);
		return cdisk;
	}
	catch (Exception e)
		setLastException(e);
	return null;
}

export extern (C)
CXeDisk* XeDisk_CreateFile(const(char)* fileName, const(char)* type,
	uint numSectors, uint bytesPerSector)
{
	resetLastException();
	try
	{
		auto file = File(cstrToString(fileName).idup, "w+b");
		auto stream = new FileStream(file);
		auto cdisk = new CXeDisk;
		cdisk.impl = XeDisk.create(stream, cstrToString(type).idup,
			numSectors, bytesPerSector);
		GC.addRoot(cdisk);
		return cdisk;
	}
	catch (Exception e)
		setLastException(e);
	return null;
}

export extern (C)
void XeDisk_Close(CXeDisk* cdisk)
{
	resetLastException();
	try
		GC.removeRoot(cdisk);
	catch (Exception e)
		setLastException(e);
}

export extern (C)
uint XeDisk_GetSectors(CXeDisk* cdisk)
{
	resetLastException();
	try
		return cdisk.impl.getSectors();
	catch (Exception e)
		setLastException(e);
	return 0;
}

export extern (C)
uint XeDisk_GetSectorSize(CXeDisk* cdisk)
{
	resetLastException();
	try
		return cdisk.impl.getSectorSize();
	catch (Exception e)
		setLastException(e);
	return 0;
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
		setLastException(e);
	return null;
}

export extern (C)
CXeFileSystem* XeFileSystem_Open(CXeDisk* cdisk)
{
	resetLastException();
	try
	{
		auto cfs = new CXeFileSystem;
		cfs.impl = XeFileSystem.open(cdisk.impl);
		GC.addRoot(cfs);
		return cfs;
	}
	catch (Exception e)
		setLastException(e);
	return null;
}

export extern (C)
void XeFileSystem_Close(CXeFileSystem* cfs)
{
	resetLastException();
	try
		GC.removeRoot(cfs);
	catch (Exception e)
		setLastException(e);
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
		setLastException(e);
	return null;
}

export extern (C)
uint XeFileSystem_GetFreeSectors(CXeFileSystem* cfs)
{
	resetLastException();
	try
		return cfs.impl.getFreeSectors();
	catch (Exception e)
		setLastException(e);
	return 0;
}

export extern (C)
ulong XeFileSystem_GetFreeBytes(CXeFileSystem* cfs)
{
	resetLastException();
	try
		return cfs.impl.getFreeBytes();
	catch (Exception e)
		setLastException(e);
	return 0;
}
