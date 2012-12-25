// Written in the D programming language

/*
bytemanip.d - magic on bytes and words
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

module xe.bytemanip;

import std.algorithm;
import std.range;
import std.bitmanip;

pure nothrow uint makeWord(T)(T[] bytes...)
{
	return reduce!"(a << 8) | (b & 0xff)"(0, bytes);
}

unittest
{
	import std.stdio;
	assert (makeWord(0x69) == 0x69);
	assert (makeWord(0xde, 0xad) == 0xdead);
	assert (makeWord(0xc0, 0xff, 0xee) == 0xc0ffee);
	assert (makeWord(0xb1, 0x6b, 0x00, 0xb5) == 0xb16b00b5);
	assert (makeWord([0xb1, 0x6b, 0x00, 0xb5]) == 0xb16b00b5);
	assert (makeWord(array(retro([0xb5, 0x00, 0x6b, 0xb1]))) == 0xb16b00b5);
	static assert (makeWord(0xb1, 0x6b, 0x00, 0xb5) == 0xb16b00b5);
	writeln("makeWord (1) ok");
}

template byteMask(uint B)
{
	static if (B > 3)
		const byteMask = 0xffL << (B << 3);
	else
		const byteMask = 0xff << (B << 3);
}

unittest
{
	import std.stdio;
	assert(byteMask!7 == 0xff00000000000000);
	assert(byteMask!3 == 0xff000000);
	writeln("byteMask (1) ok");
}

pure nothrow ubyte getByte(int B, T)(T w)
{
	return (w & byteMask!B) >> (B << 3);
}

unittest
{
	import std.stdio;
	assert(getByte!3(0xdeadbeef) == 0xde);
	assert(getByte!2(0xdeadbeef) == 0xad);
	assert(getByte!1(0xdeadbeef) == 0xbe);
	static assert(getByte!0(0xdeadbeef) == 0xef);
	writeln("getByte (1) ok");
}

alias littleEndianToNative leton;
alias bigEndianToNative beton;
alias nativeToLittleEndian ntole;
alias nativeToBigEndian ntobe;

union RawStruct(T, string name = "strukt") if (is(T == struct))
{
	mixin("T " ~ name ~ "; alias " ~ name ~ " this;");
	ubyte[T.sizeof] raw;
}
