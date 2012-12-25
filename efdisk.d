import std.stdio;
import std.exception;
import std.getopt;
import std.string;
import std.bitmanip;
import std.array;
import std.conv;
import core.stdc.config;
import core.stdc.stdlib;
import xe.bytemanip;

enum PartitionStatus : ubyte
{
	Exists = 0x80,
	ReadOnly = 0x20,
	OnSlave = 0x10,
}

enum PartitionSectorSize : ubyte
{
	B256 = 0x00,
	B512 = 0x80,
}

struct PartitionInfo
{
	PartitionStatus status;
	ubyte index;
	uint begin;
	uint len;
	PartitionSectorSize clsize;
}

struct CHS
{
	ubyte[3] _data;

	@property ubyte head() { return _data[0]; }
	@property void head(ubyte h) { _data[0] = h; }
	@property ushort cylinder() { return _data[2] | ((_data[1] & 0xc0) << 2); }
	@property void cylinder(ushort c)
	{
		_data[2] = c & 0xff;
		_data[1] = (_data[1] & 0x3f) | ((c >> 2) & 0xc0);
	}
	@property ubyte sector() { return _data[1] & 0x3f; }
	@property void sector(ubyte s) { _data[1] = (_data[1] & 0xc0) | (s & 0x3f); }

	string toString()
	{
		return format("%4d-%3d-%2d", cylinder, head, sector);
	}

	this(ushort c, ubyte h, ubyte s)
	{
		cylinder = c;
		head = h;
		sector = s;
	}
}

struct DosPartition
{
	ubyte    status;
	CHS      first;
	ubyte    type;
	CHS      last;
	ubyte[4] _lbaFirst;
	ubyte[4] _sectors;

	@property uint lbaFirst() { return littleEndianToNative!uint(_lbaFirst); }
	@property void lbaFirst(uint f) { _lbaFirst = nativeToLittleEndian(f); }

	@property uint sectors() { return littleEndianToNative!uint(_sectors); }
	@property void sectors(uint s) { _sectors = nativeToLittleEndian(s); }

	@property bool isEmpty()
	{
		return (status | lbaFirst | sectors | type) == 0;
	}

	string toString()
	{
		return format(
			"status=%02x type=%02x first=%s last=%s LBA first=%s sectors=%s",
			status, type, first, last, lbaFirst, sectors);
	}
}

struct MBR
{
	PartitionStatus[0x10] pstats;
	ubyte[0x10]           pindex;
	ubyte[0x10]           pbeglo;
	ubyte[0x10]           pbegmd;
	ubyte[0x10]           pbeghi;
	ubyte[0x10]           plenlo;
	ubyte[0x10]           plenmd;
	ubyte[0x10]           plenhi;
	ubyte[0x02]           pmagic;
	ubyte[0xAC - 0x82]    pign1;
	PartitionSectorSize[0x10] pclsize;
	ubyte[0x1BE - 0xBC]   pign2;
	DosPartition[4]       dosPartitions;
	ubyte[2]              _dosSignature;

	@property bool hasValidIdeaSignature()
	{
		return littleEndianToNative!ushort(pmagic) == 0x728;
	}

	void setIdeaSignature()
	{
		pmagic = nativeToLittleEndian(cast(ushort) 0x728);
	}

	@property ushort hasValidDosSignature()
	{
		return littleEndianToNative!ushort(_dosSignature) == 0xAA55;
	}

	void setDosSignature()
	{
		_dosSignature = nativeToLittleEndian(cast(ushort) 0xAA55);
	}

	PartitionInfo opIndex(size_t i)
	{
		enforce(i < 16, "Invalid partition number");
		return PartitionInfo(pstats[i], pindex[i],
			makeWord(pbeghi[i], pbegmd[i], pbeglo[i]),
			makeWord(plenhi[i], plenmd[i], plenlo[i]),
			pclsize[i]);
	}

	void opIndex(PartitionInfo pi, size_t i)
	{
		enforce(i < 16, "Invalid partition number");
		pstats[i] = pi.status;
		pindex[i] = pi.index;
		pbeglo[i] = getByte!0(pi.begin);
		pbegmd[i] = getByte!1(pi.begin);
		pbeghi[i] = getByte!2(pi.begin);
		plenlo[i] = getByte!0(pi.len);
		plenmd[i] = getByte!1(pi.len);
		plenhi[i] = getByte!2(pi.len);
		pclsize[i] = pi.clsize;
	}

	bool isValid(uint i)
	{
		return (pstats[i] & PartitionStatus.Exists)
		   && !(pstats[i] & PartitionStatus.OnSlave)
		   &&  (pindex[i] == 0)
		   && (pclsize[i] == PartitionSectorSize.B256
		    || pclsize[i] == PartitionSectorSize.B512);
	}
}

static assert(MBR.sizeof == 0x200);

auto readMBR(string filename)
{
	auto f = File(filename, "rb");
	RawStruct!MBR result;
	enforce(f.rawRead(result.raw).length == 0x200,
		"EOF while reading MBR");
	return result.strukt;
}

void writeMBR(string filename, ref const(MBR) mbr)
{
	auto f = File(filename, "r+b");
	RawStruct!MBR data;
	data.strukt = mbr;
	f.rawWrite(data.raw);
}

enum HDIO_GETGEO = 0x0301;

struct hd_geometry
{
	ubyte heads;
	ubyte sectors;
	ushort cylinders;
	c_ulong start;
}

version(linux)
{
	import core.stdc.errno;
	extern(C)
	int getDriveGeometry(const(char)* dev, hd_geometry* geom);
}

struct Geometry
{
	this(string dev)
	{
		version(linux)
		{
			enforce(getDriveGeometry(dev.toStringz(), &geom) == 0,
				"Failed to get geometry for " ~ dev);
		}
		else
		{
			stderr.writeln("Reading drive geometry is only supported in Linux");
		}
	}

	CHS lbaToChs(uint lba)
	{
		CHS result;
		uint total = geom.cylinders * geom.heads * geom.sectors;
		if (lba >= total)
			lba = total - 1;
		result.cylinder = cast(ushort) (lba / (geom.heads * geom.sectors));
		auto j = lba % (geom.heads * geom.sectors);
		result.head = cast(ubyte) (j / geom.sectors);
		result.sector = cast(ubyte) (j % geom.sectors) + 1;
		return result;
	}

	hd_geometry geom;
}

void doWrap(string[] args)
{
	bool dryRun;
	getopt(args,
		config.caseSensitive,
		"n|dry-run", &dryRun);
	if (args.length != 3)
	{
		printHelp(args);
		exit(1);
	}
	auto fname = args[2];
	writefln("Reading partition table from device %s", fname);
	auto mbr = readMBR(fname);
	auto geom = Geometry(fname);
	enforce(mbr.hasValidIdeaSignature,
		"Device does not contain a KMK/JZ (IDEa) partition table");

	uint first = uint.max;
	uint last = uint.min;
	foreach (i; 0 .. 16)
	{
		auto pi = mbr[i];
		if ((pi.status & PartitionStatus.Exists)
		 && !(pi.status & PartitionStatus.OnSlave))
		{
			if (pi.begin + 1 < first)
				first = pi.begin + 1;
			if (pi.begin + pi.len > last)
				last = pi.begin + pi.len;
		}
	}
	uint size = last - first + 1;
	writefln("KMK/JZ partitions occupy sectors %s-%s (%s sectors)",
		first, last, size);
	DosPartition newpart;
	newpart.first = geom.lbaToChs(first);
	newpart.type = 0x5d;
	newpart.last = geom.lbaToChs(last);
	newpart.lbaFirst = first;
	newpart.sectors = size;
	writeln(newpart);

	size_t part = size_t.max;
	if (mbr.hasValidDosSignature)
	{
		writeln("Found an MS-DOS partition table");
		foreach (i, dp; mbr.dosPartitions)
		{
			if (dp.isEmpty())
			{
				part = i;
				break;
			}
		}
		enforce(part < 4, "Couldn't find a free primary partition slot");
	}
	else
	{
		writeln("Creating a new MS-DOS partition table");
		foreach (i; 1 .. 4)
			mbr.dosPartitions[i] = DosPartition.init;
		part = 0;
	}
	writefln("IDEa partition table wrapped as MS-DOS partition #%d", part);
	mbr.dosPartitions[part] = newpart;
	if (dryRun)
		writeln("Dry run, not writing anything to disk.");
	else
	{
		writeMBR(fname, mbr);
		writeln("MBR updated.");
	}
}

void doList(string[] args)
{
	if (args.length < 3)
	{
		printHelp(args);
		exit(1);
	}
	foreach (fname; args[2 .. $])
	{
		writefln("Reading partition table from device %s", fname);
		auto mbr = readMBR(fname);
		if (mbr.hasValidIdeaSignature)
		{
			writeln("\nFound a KMK/JZ (IDEa) partition table:");
			writefln("%2s  %4s %10s %10s %10s %5s",
				"#", "Attr", "Start", "End", "Sectors", "B/Sec");
			foreach (i; 0 .. 16)
			{
				auto pi = mbr[i];
				bool exists = !!(pi.status & PartitionStatus.Exists);
				writefln("%2s  %1s%1s%1s  %10s %10s %10s %5s",
					i,
					exists                               ? "E" : " ",
					pi.status & PartitionStatus.ReadOnly ? "R" : " ",
					pi.status & PartitionStatus.OnSlave  ? "S" : " ",
					pi.begin + (exists ? 1 : 0),
					pi.begin + pi.len,
					pi.len,
					!exists ? "0" :
						(pi.clsize == PartitionSectorSize.B512 ? "512" : "256"));
			}
		}
		else
		{
			writefln("Device does not contain a KMK/JZ (IDEa) partition table");
		}
		if (mbr.hasValidDosSignature)
		{
			writeln("\nFound an MS-DOS partition table:");
			writefln("%2s  %4s %13s %13s  %12s %12s",
				"#", "Boot", "Start", "End", "LBA Start", "Sectors");
			foreach (i, pi; mbr.dosPartitions)
			{
				writefln("%2s  %-4s %13s %13s  %12s %12s",
					i,
					pi.status & 0x80 ? "*" : " ",
					pi.first.toString(),
					pi.last.toString(),
					pi.lbaFirst,
					pi.sectors);
			}
		}
		else
		{
			writefln("Device does not contain a valid MS-DOS partition table");
		}
	}
}

void doRemove(string[] args)
{
	if (args.length < 4)
	{
		printHelp(args);
		exit(1);
	}
	auto part = to!uint(args[3]);
	auto dev = args[2];

	auto mbr = readMBR(dev);
	enforce(mbr.hasValidIdeaSignature,
		"Device does not contain a KMK/JZ (IDEa) partition table");
	enforce(part <= 3, "Specify a valid partition number");
	mbr.dosPartitions[part] = DosPartition.init;
	writeMBR(dev, mbr);
}

void printHelp(string[] args)
{
	writeln("Syntax:");
	writeln(" %s list device", args[0]);
	writeln(" %s wrap [-n|--dry-run] device", args[0]);
	writeln(" %s remove device part", args[0]);
	writeln("\ndevice - e.g. /dev/sdc");
	writeln("part - 0 .. 3");
}

int main(string[] args)
{
	if (args.length < 2)
	{
		printHelp(args);
		return 1;
	}
	switch (args[1])
	{
	case "list": doList(args); break;
	case "wrap": doWrap(args); break;
	case "remove": doRemove(args); break;
	default: printHelp(args); return 1;
	}
	return 0;
}
