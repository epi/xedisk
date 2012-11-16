// Written in the D programming language

/*
cache.d - makes implementing file systems easier
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

module xe.fs_impl.cache;

debug import std.stdio;
import std.exception;
import std.algorithm;
import std.system;
import std.traits;
import xe.bytemanip;
import xe.disk;

version(unittest)
{
	import std.stdio;
	import streamimpl;
}

// TODO: transactions?
// TODO: underlying disk should notify the cache about changes done externally (by other processes)

// provides a buffered view on a given sector synchronized among all objects which use it.
// reference count is used by SectorCache to ensure the cached sector isn't removed from the cache while it's in use


private struct CachedSectorImpl
{
	// payload
	uint _sector;
	ubyte[] _data;
	bool _dirty;

	// refcounting
	uint _refs = uint.max / 2;

	// links to manage LRU list
	CachedSectorImpl* _prev;
	CachedSectorImpl* _next;
}

struct StructuredCachedSector(S, Endian en = Endian.littleEndian) if (is(S == struct) || is(S == void))
{
	~this()
	{
		if (!_impl) return;
		assert (_impl._refs > 1 && _impl._refs != _impl._refs.init);
		--_impl._refs;
	}

	this(this)
	{
		if (!_impl) return;
		assert (_impl._refs && _impl._refs != _impl._refs.init);
		++_impl._refs;
	}

	void opAssign(StructuredCachedSector!S rhs)
	{
		swap(_impl, rhs._impl);
	}

	ubyte opIndex(size_t index) const { assert (_impl); return _impl._data[index]; }
	T opIndexAssign(T)(T val, size_t index) { assert (_impl); _impl._dirty = true; return cast(T) (_impl._data[index] = cast(ubyte) val); }
	T opIndexOpAssign(string op, T)(T val, size_t index) { assert (_impl); _impl._dirty = true; return cast(T) (mixin("_impl._data[index] " ~ op ~ "= val")); }
	const(ubyte)[] opSlice() const { assert (_impl); return _impl._data[]; }
	const(ubyte)[] opSlice(size_t begin, size_t end) const { assert (_impl); return _impl._data[begin .. end]; }
	void opSliceAssign(ubyte data) { assert (_impl); _impl._data[] = data; _impl._dirty = true; }
	void opSliceAssign(in ubyte[] data) { assert (_impl); _impl._data[] = data[]; _impl._dirty = true; }
	void opSliceAssign(ubyte data, size_t begin, size_t end) { assert (_impl); _impl._data[begin .. end] = data; _impl._dirty = true; }
	void opSliceAssign(in ubyte[] data, size_t begin, size_t end) { assert (_impl); _impl._data[begin .. end] = data[]; _impl._dirty = true; }

	T get(T)(size_t index) const
	{
		assert (_impl);
		ubyte[T.sizeof] tmp = _impl._data[index .. index + T.sizeof][];
		static if (en == Endian.littleEndian)
			return leton!T(tmp);
		else static if (en == Endian.bigEndian)
			return beton!T(tmp);
		else static assert(false);
	}

	void put(T)(size_t index, T val)
	{
		assert (_impl);
		static if (en == Endian.littleEndian)
			_impl._data[index .. index + T.sizeof] = ntole(val);
		else static if (en == Endian.bigEndian)
			_impl._data[index .. index + T.sizeof] = ntobe(val);
		else static assert(false);
	}

	pure nothrow @property auto sector() const { assert (_impl); return _impl._sector; }
	pure nothrow @property auto length() const { assert (_impl); return _impl._data.length; }
	alias length opDollar;

	pure nothrow @property bool isNull()  const { return _impl is null; }

	static if (is(S == struct))
	{
		@property void opDispatch(string field, T)(T value)
			if (__traits(compiles, mixin("S.init." ~ field)))
		{
			mixin("alias typeof(S.init." ~ field ~ ") FT;");
			static if (is(FT : ubyte))
			{
				this[mixin("S.init." ~ field ~ ".offsetof")] = value;
			}
			else static if (isIntegral!FT && FT.sizeof >= 2)
			{
				static if (en == Endian.littleEndian)
					put!FT(mixin("S.init." ~ field ~ ".offsetof"), value);
				else
					put!FT(mixin("S.init." ~ field ~ ".offsetof"), value);
			}
			else static if (isStaticArray!FT || isDynamicArray!FT)
			{
				this[mixin("S.init." ~ field ~ ".offsetof") ..
					mixin("S.init." ~ field ~ ".offsetof") +
					mixin("S.init." ~ field ~ ".sizeof")] =
						cast(const(ubyte)[]) value[];
			}
			else static assert(false,
				"Set field forwarding not supported for type `" ~ FT.stringof ~ "'");
		}

		@property auto opDispatch(string field)()
			if (__traits(compiles, mixin("S.init." ~ field)))
		{
			mixin("alias typeof(S.init." ~ field ~ ") FT;");
			static if (isIntegral!FT && FT.sizeof >= 2)
			{
				static if (en == Endian.littleEndian)
					return get!FT(mixin("S.init." ~ field ~ ".offsetof"));
				else
					return get!FT(mixin("S.init." ~ field ~ ".offsetof"));
			}
			else static if (is(FT : ubyte))
			{
				return cast(FT) this[mixin("S.init." ~ field ~ ".offsetof")];
			}
			else static if (is(FT T : U[N], U : ubyte, size_t N))
			{
				return cast(const(U)[])
					this[mixin("S.init." ~ field ~ ".offsetof") ..
						mixin("S.init." ~ field ~ ".offsetof") + N];
			}
			else static assert(false,
				"Get field forwarding not supported for type `" ~ FT.stringof ~ "'");
		}

		void opAssign(ref S rhs)
		{
			foreach (field; __traits(allMembers, S))
				mixin("this." ~ field ~ " = rhs." ~ field ~ ";");
		}

		S opCast(Z)() if (is(Z == S))
		{
			S result;
			foreach (field; __traits(allMembers, S))
				mixin("result." ~ field ~ " = this." ~ field ~ ";");
			return result;
		}
	}

	auto as(Z)()
	{
		return StructuredCachedSector!Z(_impl);
	}

private:
	this(CachedSectorImpl* impl)
	{
		_impl = impl;
		++_impl._refs;
	}

	CachedSectorImpl* _impl;
}

alias StructuredCachedSector!void CachedSector;

// a sector may be removed from cache only when its refcount is 1, which means the only
// reference to it is maintained in the LRU list
// TODO: sectors may have an "importance" attribute - e.g. to keep sectors known to be
// often reused (vtoc, directory) in the cache and prefer removing less important data sectors.
final class SectorCache
{
	this(XeDisk disk, size_t sizeLimit = 16, bool softLimit = true)
	{
		_disk = disk;
		_freeSlots = sizeLimit;
		_softLimit = softLimit;
	}

	~this()
	{
		try
			flush();
		catch (Exception e)
			stderr.writeln("Exception while flushing the cache: ", e);
		debug
		{
			CachedSectorImpl* centry = _mru;
			while (centry)
			{
				auto next = centry._next;
				assert (centry._refs == 1);
				clear(*centry);
				centry = next;
			}
		}
		_mru = null;
		_lru = null;
		version (CacheStats)
		{
			writeln("Cache stats:");
			writefln("hits:       %10s", _hitCount);
			writefln("misses:     %10s", _missCount);
			writefln("total:      %10s", _hitCount + _missCount);
			writefln("miss ratio: %g", cast(real) _missCount / (_hitCount + _missCount));
		}
	}

	// request a given sector - read from disk if it's not in the cache
	CachedSector request(uint sector)
	{
		doAlloc(sector, true);
		return CachedSector(_mru);
	}

	// allocate empty buffer for a given sector
	CachedSector alloc(uint sector)
	{
		doAlloc(sector, false);
		return CachedSector(_mru);
	}

	// flush all buffers to disk
	void flush()
	{
		// TODO: reordering and coalescing
		auto centry = _mru;
		while (centry)
		{
			if (centry._dirty)
			{
				_disk.writeSector(centry._sector, centry._data);
				centry._dirty = false;
			}
			centry = centry._next;
		}
	}

	uint getSectors() { return _disk.getSectors(); }
	uint getSectorSize() { return _disk.getSectorSize(); }

private:
	XeDisk _disk;

	CachedSectorImpl*[uint] _hashTable;
	CachedSectorImpl* _mru;
	CachedSectorImpl* _lru;

	size_t _freeSlots;
	bool _softLimit;

	void doAlloc(uint sector, bool readFromDisk)
	{
		auto centry = _hashTable.get(sector, null);
		if (centry)
		{
			version (CacheStats) ++_hitCount;
			moveToFront(centry);
		}
		else
		{
			version (CacheStats) ++_missCount;
			if (_freeSlots)
				insert(sector);
			else
				replaceLru(sector);
			_mru._data.length = _disk.getSectorSize(sector);
			if (readFromDisk)
				_disk.readSector(sector, _mru._data);
		}
	}

	void moveToFront(CachedSectorImpl* centry)
	{
		assert (centry);
		assert (_mru);
		if (centry == _mru)
			return;
		// remove from old location
		if (centry._prev)
			centry._prev._next = centry._next;
		if (centry._next)
			centry._next._prev = centry._prev;
		else
			_lru = centry._prev;
		// insert as mru
		centry._prev = null;
		centry._next = _mru;
		_mru._prev = centry;
		_mru = centry;
	}

	void insert(uint sector)
	{
		if (!_freeSlots && !_softLimit)
			throw new Exception("Disk cache full");
		if (_freeSlots)
			--_freeSlots;
		auto centry = new CachedSectorImpl;
		centry._refs = 1;
		centry._sector = sector;
		centry._next = _mru;
		centry._prev = null;
		if (_mru)
			_mru._prev = centry;
		_mru = centry;
		if (!_lru)
			_lru = centry;
		_hashTable[sector] = centry;
	}

	// replaces the least recently used node that has
	// no references outside the cache (i.e. refs == 1)
	// with a new entry
	void replaceLru(uint sector)
	{
		auto centry = _lru;
		while (centry)
		{
			if (centry._refs == 1)
			{
				if (centry._dirty)
				{
					_disk.writeSector(centry._sector, centry._data);
					centry._dirty = false;
				}
				_hashTable.remove(centry._sector);
				centry._sector = sector;
				_hashTable[sector] = centry;
				moveToFront(centry);
				return;
			}
			centry = centry._prev;
		}
		insert(sector);
	}

	debug
	{
		public void dump() const
		{
			if (!_mru)
				return;
			writeln(" mru dirty refs  sec#");
			writeln("-----------------------");
			const(CachedSectorImpl)* centry = _mru;
			uint i;
			while (centry)
			{
				writefln("%3d. %5d %4d %5d %s-%s-%s",
					++i, centry._dirty, centry._refs, centry._sector, centry._prev, centry, centry._next);
				centry = centry._next;
			}
			writeln();
		}
	}
	else
	{
		const void dump() {}
	}

	version (CacheStats)
	{
		size_t _missCount;
		size_t _hitCount;
	}
}

unittest
{
	scope stream = new MemoryStream(new ubyte[0]);
	scope disk = XeDisk.create(stream, "ATR", 32, 256);
	{
		scope cache = new SectorCache(disk, 2, false);
		{
			auto csec1 = cache.request(19);
			assert (csec1._impl._refs == 2);
			assert (csec1.length == 256);
			assert (csec1.sector == 19);
			auto csec1a = csec1;
			assert (csec1._impl._refs == 3);
			assert (csec1a == csec1);
			auto csec2 = cache.request(3);
			assert (csec2._impl._refs == 2);
			assert (csec2 != csec1);
			assert (csec2.length == 128);
			assert (csec2.sector == 3);
			assertThrown (cache.request(4));
			cache.dump();
		}
		{
			cache.dump();
			auto csec1a = cache.request(22);
			auto csec1b = cache.request(22);
			cache.dump();
			assert (csec1a == csec1b);
			csec1a[15] = 0xde;
			csec1b[17] = 0xad;
			auto csec1c = cache.request(22);
			cache.dump();
			assert (csec1c[15] == 0xde);
			assert (csec1c[17] == 0xad);
			cache.request(23)[] = 0x5b;
		}
		// implicit flush();
		cache.dump();
	}
	{
		ubyte[256] buf;
		disk.readSector(22, buf);
		assert(buf[15] == 0xde);
		assert(buf[17] == 0xad);
		disk.readSector(23, buf);
		assert(buf[15] == 0x5b);
		assert(buf[99] == 0x5b);
	}
	writeln("SectorCache (1) Ok");
}

unittest
{
	struct SomeStruct
	{
		uint a;
		int b;
		ushort c;
	}

	scope stream = new MemoryStream(new ubyte[0]);
	scope disk = XeDisk.create(stream, "ATR", 32, 256);
	{
		scope cache = new SectorCache(disk, 2, false);
		{
			auto csec1 = cache.request(19).as!SomeStruct;
			csec1.a = 0xdeadbeef;
			csec1.b = -31337;
			csec1.c = cast(ushort) 0xcafe;
			assert (csec1.a == 0xdeadbeef);
			assert (csec1[0 .. 4] == [ 0xef, 0xbe, 0xad, 0xde ]);
			assert (csec1.b == -31337);
			assert (csec1.c == 0xcafe);
			auto ss = cast(SomeStruct) csec1;
			assert (ss.a == 0xdeadbeef);
			assert (ss.b == -31337);
			assert (ss.c == 0xcafe);
			csec1 = SomeStruct(10, 20, 30);
			assert (csec1.a == 10);
			assert (csec1.b == 20);
			assert (csec1.c == 30);
		}
	}
	writeln("SectorCache (2) Ok");
}
