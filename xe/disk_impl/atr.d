// Written in the D programming language

/*
atr.d - support for ATR disk images
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

module xe.disk_impl.atr;

import std.exception;
import std.algorithm;
import std.bitmanip;
import std.range;
import xe.disk;
import xe.streams;
import xe.bytemanip;

version(unittest)
{
	import xe.test;
}

private:

enum ApeFlags : ubyte
{
	None = 0x00,
	WriteProtected = 0x01,
	HasCrc32 = 0x02
}

enum Sio2pcFlags : ubyte
{
	None = 0x00,
	HasBadSectors = 0x10,
	WriteProtected = 0x20
}

enum BootSectorLayout
{
	None,
	Full,   // 3 256-byte blocks used entirely
	Short,  // 3 128-byte blocks followed immediately by remaining 256-byte sectors
	Packed, // 3 128-byte blocks, then 384 bytes of 0
	Even,   // 3 256-byte blocks, first half of each contains data, second is all 0s
}

enum paragraph = 16;

struct AtrHeader
{
align(1):
	ubyte[2] magic = [ 0x96, 0x02 ];
	ubyte[2] pars;
	ubyte[2] sectorSize;
	ubyte parsHigh;
	union
	{
		struct
		{
			ubyte[4] crc32;
			ubyte[4] _apeUnused;
			ApeFlags apeFlags;
		}
		struct
		{
			ubyte sio2pcParsHigh;
			Sio2pcFlags sio2pcFlags;
			ubyte[2] firstBadSector;
			ubyte[5] _unused;
		}
	}

	this(uint pars, uint sectorSize)
	{
		this.pars = ntole(cast(ushort) pars);
		this.parsHigh = (pars >> 16) & 0xff;
		this.sectorSize = ntole(cast(ushort) sectorSize);
	}
}

static assert(AtrHeader.sizeof == 16);

class AtrDisk : XeDisk
{
	override @property uint sectorCount() const { return _sectorCount; }

	override @property uint sectorSize() const { return _sectorSize; }

	override @property bool isWriteProtected() const
	{
		return !_sio2pcFlags && !!(_apeFlags & ApeFlags.WriteProtected);
	}

	override @property void isWriteProtected(bool value)
	{
		enforce(_openMode != XeDiskOpenMode.ReadOnly,
			"Disk is opened as read-only");
		enforce(!_sio2pcFlags,
			"Write protection is an APE extension and cannot be set for " ~
			"a SIO2PC ATR disk image");

		RawStruct!AtrHeader header;
		enforce(_stream.read(0, header.raw) == header.sizeof,
			"EOF while reading ATR header");
		auto oldFlags = _apeFlags;
		scope(failure) _apeFlags = oldFlags;
		if (value)
			header.apeFlags = _apeFlags |= ApeFlags.WriteProtected;
		else
			header.apeFlags = _apeFlags &= ~ApeFlags.WriteProtected;
		_stream.write(0, header.raw);
	}

	override @property string type() const { return "ATR"; }

protected:
	override size_t doReadSector(uint sector, ubyte[] buffer)
	{
		ulong offset;
		uint size;
		getOffsetAndSizeOfSector(sector, offset, size);
		auto len = min(buffer.length, size);
		return _stream.read(offset, buffer[0 .. len]);
	}

	override void doWriteSector(uint sector, in ubyte[] buffer)
	{
		ulong offset;
		uint size;
		getOffsetAndSizeOfSector(sector, offset, size);
		auto len = min(buffer.length, size);
		_stream.write(offset, buffer[0 .. len]);
	}

	override uint doGetSizeOfSector(uint sector) const
	{
		ulong offset;
		uint size;
		getOffsetAndSizeOfSector(sector, offset, size);
		return size;
	}

private:
	this(RandomAccessStream stream, uint sectorCount, uint sectorSize,
		BootSectorLayout bootSectorLayout,
		Sio2pcFlags sio2pcFlags, ApeFlags apeFlags, XeDiskOpenMode mode)
	{
		_stream = stream;
		_sectorCount = sectorCount;
		_sectorSize = sectorSize;
		_bootSectorLayout = bootSectorLayout;
		_apeFlags = apeFlags;
		_sio2pcFlags = sio2pcFlags;
		_openMode = mode;
	}

	void getOffsetAndSizeOfSector(uint sector,
		out ulong offset, out uint size) const
	{
		offset = AtrHeader.sizeof;
		if (_bootSectorLayout == BootSectorLayout.Full)
		{
			size = _sectorSize;
			offset += (sector - 1) * _sectorSize;
		}
		else
		{
			size = sector > 3 ? _sectorSize : 128;
			if (_bootSectorLayout == BootSectorLayout.Even)
				offset += (sector - 1) * _sectorSize;
			else if (_bootSectorLayout == BootSectorLayout.Packed)
				offset += sector > 3 ? (sector - 1) * _sectorSize
					: (sector - 1) * 128;
			else if (_bootSectorLayout == BootSectorLayout.Short)
				offset += sector > 3 ? 384 + (sector - 4) * _sectorSize
					: (sector - 1) * 128;
		}
	}

	unittest
	{
		mixin(Test!"AtrDisk.getOffsetAndSizeOfSector");
		ulong offset;
		uint size;

		auto stream = new MemoryStream(new ubyte[0]);
		auto disk = AtrDisk.createAtr(stream, 720, 256);
		assert(stream.getLength() == 720 * 256 - 384 + 16);

		assert(disk._bootSectorLayout == BootSectorLayout.Short);
		disk.getOffsetAndSizeOfSector(3, offset, size);
		assert(offset == 16 + 256);
		assert(size == 128);
		disk.getOffsetAndSizeOfSector(4, offset, size);
		assert(offset == 16 + 384);
		assert(size == 256);

		disk._bootSectorLayout = BootSectorLayout.Full;
		disk.getOffsetAndSizeOfSector(3, offset, size);
		assert(offset == 16 + 512);
		assert(size == 256);
		disk.getOffsetAndSizeOfSector(4, offset, size);
		assert(offset == 16 + 768);
		assert(size == 256);

		disk._bootSectorLayout = BootSectorLayout.Even;
		disk.getOffsetAndSizeOfSector(3, offset, size);
		assert(offset == 16 + 512);
		assert(size == 128);
		disk.getOffsetAndSizeOfSector(4, offset, size);
		assert(offset == 16 + 768);
		assert(size == 256);

		disk._bootSectorLayout = BootSectorLayout.Packed;
		disk.getOffsetAndSizeOfSector(3, offset, size);
		assert(offset == 16 + 256);
		assert(size == 128);
		disk.getOffsetAndSizeOfSector(4, offset, size);
		assert(offset == 16 + 768);
		assert(size == 256);
	}

	shared static this()
	{
		registerType("ATR", &openAtr, &createAtr);
	}

	static AtrDisk openAtr(RandomAccessStream stream, XeDiskOpenMode mode)
	{
		RawStruct!AtrHeader header;
		if (stream.read(0, header.raw) != header.sizeof
		 || header.magic.leton!ushort() != 0x0296
		 || (header.sio2pcFlags && header.apeFlags))
			return null;
		uint sectorSize = header.sectorSize.leton!ushort();
		uint size = (header.pars.leton!ushort() + (header.parsHigh << 16))
			* paragraph;
		uint sectorCount;
		BootSectorLayout bootSectorLayout;
		switch (sectorSize)
		{
		case 128, 512:
			sectorCount = size / sectorSize;
			bootSectorLayout = BootSectorLayout.Full;
			break;
		case 256:
			auto buf = new ubyte[768];
			if (stream.read(header.sizeof, buf) != buf.length)
				return null;
			if (size % 256 == 0)
			{
				if (all!"a == 0"(buf[384 .. 768]))
					bootSectorLayout = BootSectorLayout.Packed;
				else if (all!"a == 0"(chain(buf[128 .. 256],
					buf[384 .. 512], buf[640 .. 768])))
					bootSectorLayout = BootSectorLayout.Even;
				else
					bootSectorLayout = BootSectorLayout.Full;
				sectorCount = size / 256;
			}
			else
			{
				bootSectorLayout = BootSectorLayout.Short;
				sectorCount = (size - 384) / 256 + 3;
			}
			break;
		default:
			return null;
		}
		return new AtrDisk(stream, sectorCount, sectorSize,
			bootSectorLayout, header.sio2pcFlags, header.apeFlags, mode);
	}

	unittest
	{
		mixin(Test!"AtrDisk.openAtr (1)");
		enum createAndOpen = q{
			RawStruct!AtrHeader header;
			header = AtrHeader(size / paragraph, sectorSize);
			scope stream = new MemoryStream(header.raw ~ new ubyte[size]);
			auto disk = AtrDisk.openAtr(stream, XeDiskOpenMode.ReadOnly);
		};

		{
			enum sectors = 720;
			enum sectorSize = 192;
			enum size = 3 * 128 + (sectors - 3) * sectorSize;
			mixin(createAndOpen);
			assert(!disk);
		}
		{
			enum sectors = 720;
			enum sectorSize = 256;
			enum size = 3 * 128 + (sectors - 3) * sectorSize;
			mixin(createAndOpen);
			assert(disk);
			assert(disk._sectorCount == 720);
			assert(disk._sectorSize == 256);
			assert(disk._bootSectorLayout == BootSectorLayout.Short);
			assert(disk._apeFlags == 0);
			assert(disk._sio2pcFlags == 0);
			assert(disk.sectorSize == 256);
			assert(disk.getSizeOfSector(1) == 128);
			assert(disk.getSizeOfSector(2) == 128);
			assert(disk.getSizeOfSector(3) == 128);
			assert(disk.getSizeOfSector(4) == 256);
			assert(!disk.isWriteProtected);
			assertThrown(disk.isWriteProtected = true);
			disk._openMode = XeDiskOpenMode.ReadWrite;
			disk.isWriteProtected = true;
			assert(disk.isWriteProtected);
			disk.isWriteProtected = false;
			assert(!disk.isWriteProtected);
			disk._sio2pcFlags = cast(Sio2pcFlags) 1;
			assertThrown(disk.isWriteProtected = false);
			assert(disk.type == "ATR");
		}
		{
			enum sectors = 65535;
			enum sectorSize = 256;
			enum size = sectors * sectorSize;
			mixin(createAndOpen);
			assert(disk);
			assert(disk._sectorCount == 65535);
			assert(disk._sectorSize == 256);
			assert(disk._bootSectorLayout == BootSectorLayout.Packed);
			assert(disk._apeFlags == 0);
			assert(disk._sio2pcFlags == 0);
		}
		{
			enum sectors = 65535;
			enum sectorSize = 512;
			enum size = sectors * sectorSize;
			mixin(createAndOpen);
			assert(disk);
			assert(disk._sectorCount == 65535);
			assert(disk._sectorSize == 512);
			assert(disk._bootSectorLayout == BootSectorLayout.Full);
			assert(disk._apeFlags == 0);
			assert(disk._sio2pcFlags == 0);
		}
		{
			enum sectors = 720;
			enum sectorSize = 256;
			enum size = sectors * sectorSize;
			RawStruct!AtrHeader header;
			header = AtrHeader(size / paragraph, sectorSize);
			auto content = new ubyte[size];
			content[512] = 1;
			auto stream = new MemoryStream(header.raw ~ content);
			auto disk = AtrDisk.openAtr(stream, XeDiskOpenMode.ReadOnly);
			assert(disk);
			assert(disk._sectorCount == 720);
			assert(disk._sectorSize == 256);
			assert(disk._bootSectorLayout == BootSectorLayout.Even);
			content[512] = 0;
			content[128] = 1;
			stream = new MemoryStream(header.raw ~ content);
			disk = AtrDisk.openAtr(stream, XeDiskOpenMode.ReadOnly);
			assert(disk);
			assert(disk._sectorCount == 720);
			assert(disk._sectorSize == 256);
			assert(disk._bootSectorLayout == BootSectorLayout.Packed);
			content[512] = 1;
			stream = new MemoryStream(header.raw ~ content);
			disk = AtrDisk.openAtr(stream, XeDiskOpenMode.ReadOnly);
			assert(disk);
			assert(disk._sectorCount == 720);
			assert(disk._sectorSize == 256);
			assert(disk._bootSectorLayout == BootSectorLayout.Full);
		}
	}

	static AtrDisk createAtr(RandomAccessStream stream,
		uint sectorCount, uint sectorSize)
	{
		enforce(sectorCount >= 3 && sectorCount <= 65535,
			"Number of sectors in an ATR disk image must be from 3 to 65535");
		uint size;
		BootSectorLayout bootSectorLayout;
		switch (sectorSize)
		{
		case 128, 512:
			bootSectorLayout = BootSectorLayout.Full;
			size = sectorCount * sectorSize;
			break;
		case 256:
			bootSectorLayout = BootSectorLayout.Short;
			size = 384 + (sectorCount - 3) * 256;
			break;
		default:
			throw new Exception("Sector size must be 128, 256 or 512 bytes");
		}
		static assert(512 * 65535 / paragraph < (1 << 24));
		auto header = RawStruct!AtrHeader(
			AtrHeader(size / paragraph, sectorSize));
		stream.write(0, header.raw);
		stream.write(header.sizeof + size - 1, cast(ubyte[]) [ 0 ]);
		return new AtrDisk(stream, sectorCount, sectorSize,
			bootSectorLayout, cast(Sio2pcFlags) 0, cast(ApeFlags) 0,
			XeDiskOpenMode.ReadWrite);
	}

	unittest
	{
		mixin(Test!"AtrDisk.createAtr (1)");
		{
			auto stream = new MemoryStream(new ubyte[0]);
			auto disk = AtrDisk.createAtr(stream, 65535, 512);
			assert(stream.getLength() == 65535 * 512 + 16);
			assert(disk.sectorCount == 65535);
			assert(disk.sectorSize == 512);
			assert(disk._bootSectorLayout == BootSectorLayout.Full);
		}
		{
			auto stream = new MemoryStream(new ubyte[0]);
			auto disk = AtrDisk.createAtr(stream, 720, 256);
			assert(stream.getLength() == 720 * 256 - 384 + 16);
			assert(disk._bootSectorLayout == BootSectorLayout.Short);
		}
		{
			scope stream = new MemoryStream(new ubyte[0]);
			assertThrown(AtrDisk.createAtr(stream, 720, 129));
			assert(stream.getLength() == 0);
		}
	}

	RandomAccessStream _stream;
	uint _sectorCount;
	uint _sectorSize;
	BootSectorLayout _bootSectorLayout;
	ApeFlags _apeFlags;
	Sio2pcFlags _sio2pcFlags;
}
