// Written in the D programming language

/*
streams.d - stream interfaces
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

module xe.streams;

import std.stdio;
import std.algorithm;

version(unittest)
{
	import std.file;
	import xe.test;
}

///
interface InputStream
{
	/// for stream users only
	final size_t read(ubyte[] buffer)
	{
		// some additional checks may be done here in the future
		return doRead(buffer);
	}

	/// for stream implementors only
	protected size_t doRead(ubyte[] buffer);
}

///
interface OutputStream
{
	/// for stream users only
	final void write(in ubyte[] buffer)
	{
		// some additional checks may be done here in the future
		return doWrite(buffer);
	}

	/// for stream implementors only
	protected void doWrite(in ubyte[] buffer);
}

///
interface RandomAccessStream
{
	///
	size_t getLength();

	/// for stream users only
	final size_t read(size_t offset, ubyte[] buffer)
	{
		// some additional checks may be done here in the future
		return doRead(offset, buffer);
	}

	/// for stream users only
	final void write(size_t offset, in ubyte[] buffer)
	{
		// some additional checks may be done here in the future
		doWrite(offset, buffer);
	}

	/// for stream implementors only
	protected size_t doRead(size_t offset, ubyte[] buffer);
	/// for stream implementors only
	protected void doWrite(size_t offset, in ubyte[] buffer);
}

/*class FileInputStream : InputStream
{
	this(File f)
	{
		file_ = f;
	}

	override size_t doRead(ubyte[] buffer)
	{
		auto r = file_.rawRead(buffer);
		return cast(int) r.length;
	}

private:
	File file_;
}

unittest
{
	if (exists("testfiles/foo")) std.file.remove("testfiles/foo");
	scope (exit) if (exists("testfiles/foo")) std.file.remove("testfiles/foo");
	std.file.write("testfiles/foo", "foo");
	scope istream = new FileInputStream(File("testfiles/foo", "rb"));
	auto buf = new ubyte[20];
	auto r = istream.read(buf);
	assert (r == 3);
	assert (buf[0 .. r] == "foo");
	writeln("FileInputStream (1) ok");
}

unittest
{
	if (exists("testfiles/foo")) std.file.remove("testfiles/foo");
	scope (exit) if (exists("testfiles/foo")) std.file.remove("testfiles/foo");
	std.file.write("testfiles/foo", "foo bar baz");
	scope istream = new FileInputStream(File("testfiles/foo", "rb"));
	auto buf = new ubyte[4];
	auto r = istream.read(buf);
	assert (r == 4);
	assert (buf[0 .. r] == "foo ");
	writeln("FileInputStream (2) ok");
}*/

/*class FileOutputStream : OutputStream
{
	this(File f)
	{
		file_ = f;
	}

	override void doWrite(in ubyte[] buffer)
	{
		file_.rawWrite(buffer);
	}

private:
	File file_;
}

unittest
{
	if (exists("testfiles/foo")) std.file.remove("testfiles/foo");
	scope (exit) if (exists("testfiles/foo")) std.file.remove("testfiles/foo");
	auto foo = cast(immutable(ubyte[])) "foo";
	{
		scope ostream = new FileOutputStream(File("testfiles/foo", "wb"));
		ostream.write(foo);
	}
	assert(std.file.read("testfiles/foo") == foo);
	writeln("FileOutputStream (1) ok");
}
*/

class FileStream : RandomAccessStream
{
	this(File f)
	{
		file_ = f;
	}

	override size_t getLength()
	{
		auto l = file_.size();
		if (l == ulong.max || l > int.max)
			throw new Exception("Failed to determine file length");
		return l;
	}

	override size_t doRead(size_t offset, ubyte[] buffer)
	{
		file_.seek(offset);
		auto r = file_.rawRead(buffer);
		return r.length;
	}

	override void doWrite(size_t offset, in ubyte[] buffer)
	{
		file_.seek(offset);
		file_.rawWrite(buffer);
	}

private:
	File file_;
}

unittest
{
	mixin(Test!"FileStream (1)");
	if (exists("testfiles/foo")) std.file.remove("testfiles/foo");
	scope (exit) if (exists("testfiles/foo")) std.file.remove("testfiles/foo");
	scope fstream = new FileStream(File("testfiles/foo", "wb+"));
	assert (fstream.getLength() == 0);
	auto wbuf = cast(immutable(ubyte[])) "foo";
	auto rbuf = new ubyte[4];
	fstream.write(100, wbuf);
	assert (fstream.getLength() == 103);
	fstream.write(200, wbuf);
	assert (fstream.getLength() == 203);
	auto r = fstream.read(100, rbuf);
	assert (r == rbuf.length);
	assert (rbuf[0 .. 3] == wbuf[]);
	rbuf[] = 0;
	r = fstream.read(200, rbuf[0 .. 3]);
	assert (r == 3);
	assert (rbuf[0 .. 3] == wbuf[]);
}

class MemoryInputStream : InputStream
{
	this(ubyte[] array)
	{
		this.array = array;
	}

	override size_t doRead(ubyte[] buffer)
	{
		auto len = min(array.length, buffer.length);
		buffer[0 .. len] = array[0 .. len];
		array = array[len .. $];
		return len;
	}

	ubyte[] array;
}

class MemoryOutputStream : OutputStream
{
	this(ubyte[] array)
	{
		this.array = array;
	}

	override void doWrite(in ubyte[] buffer)
	{
		this.array ~= buffer[];
	}

	ubyte[] array;
}

class MemoryStream : RandomAccessStream
{
	this(ubyte[] array)
	{
		this.array = array;
	}

	override size_t getLength()
	{
		return array.length;
	}

	override size_t doRead(size_t offset, ubyte[] buffer)
	{
		if (offset >= array.length)
			return 0;
		auto len = min(array.length - offset, buffer.length);
		buffer[0 .. len] = array[offset .. offset + len];
		return len;
	}

	override void doWrite(size_t offset, in ubyte[] buffer)
	{
		if (offset + buffer.length > array.length)
			array.length = offset + buffer.length;
		array[offset .. offset + buffer.length] = buffer[];
	}

	ubyte[] array;
}
