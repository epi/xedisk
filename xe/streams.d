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
