module streamimpl;

import std.stdio;
import std.exception;
import std.algorithm;
import xe.streams;

version (unittest)
{
	import std.file;
}

class FileInputStream : InputStream
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
}

class FileOutputStream : OutputStream
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
	writeln("FileStream (1) ok");
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
