/*	(Written in D programming language)

	xedisk - Atari XL/XE Disk Image Utility
	Command line interface for library modules.

	Author: Adrian Matoga epi@atari8.info
	
	Poetic License:

	This work 'as-is' we provide.
	No warranty express or implied.
	We've done our best,
	to debug and test.
	Liability for damages denied.

	Permission is granted hereby,
	to copy, share, and modify.
	Use as is fit,
	free or for profit.
	These rights, on this notice, rely.
*/

import std.stdio;
import std.string;
import std.conv;
import std.getopt;
import std.date;
import std.contracts;

import image;
import filesystem;

uint bytesPerSector = 256;
uint totalSectors = 720;
bool verbose;
string imageFileName;

struct OpenFileSystem
{
	this(string filename, bool readOnly = true, bool throwOnUnknownFilesystem = true)
	{
		image = Image.open(filename, readOnly);
		scope (failure) image.close();
		auto e = collectException(fs = FileSystem.open(image));
		if (e !is null && throwOnUnknownFilesystem)
			throw e;
	}

	~this()
	{
		if (fs !is null)
			fs.close();
		image.close();
	}

	Image image;
	FileSystem fs;
}

void info(string[] args)
{
	auto ofs = OpenFileSystem(imageFileName, true, false);

	writeln("Image file name:   ", imageFileName);
	writeln("Total sectors:     ", ofs.image.totalSectors);
	writeln("Bytes per sectors: ", ofs.image.bytesPerSector);

	writeln("\nFilesystem:        ", ofs.fs is null ? "n/a" : ofs.fs.name);
	writeln("Label:             ", ofs.fs is null ? "n/a" : ofs.fs.getLabel());
	writeln("Free sectors:      ", ofs.fs is null ? "n/a" : to!string(ofs.fs.getFreeSectors()));
}

void dir(string[] args)
{
	auto ofs = OpenFileSystem(imageFileName);
	if (verbose)
	{
		uint files = 0;
		writeln("Filesystem: ", ofs.fs.name);
		writeln("Label:      ", ofs.fs.getLabel(), "\n");
		ofs.fs.listDir((const ref FileInfo dirEntry)
		{
			writefln("%c%c%c%c %-12s %8d",
				dirEntry.isDeleted ? "x" : " ",
				dirEntry.isNotClosed ? "u" : " ",
				dirEntry.isDirectory ? ":" : " ",
				dirEntry.isReadOnly ? "*" : " ",
				dirEntry.name,
				dirEntry.length);
			++files;
			return true;
		}, args.length > 3 ? args[3] : "/*.*");
		writefln("\n%11d files", files);
		writefln("%5d/%5d sectors free", ofs.fs.getFreeSectors(), ofs.image.totalSectors);
	}
	else
	{
		ofs.fs.listDir((const ref FileInfo dirEntry)
		{
			writefln(dirEntry.name);
			return true;
		}, args.length > 3 ? args[3] : "/*.*");
	}
}

void extract(string[] args)
{
	auto ofs = OpenFileSystem(imageFileName);
	auto fs = ofs.fs;

	bool extractOne(const ref FileInfo dirEntry)
	{
		if (verbose)
			writeln(dirEntry.name);
		if (dirEntry.isDirectory || dirEntry.isDeleted || dirEntry.isNotClosed)
		{
			throw new Exception("Not implemented");
		}
		auto ifile = fs.openFile(dirEntry.name, "rb");
		scope (exit) ifile.close();
		auto ofile = File(dirEntry.name, "wb");

		auto blk = new ubyte[4096];
		
		for (size_t len; (len = ifile.read(blk)) > 0; )
			ofile.rawWrite(blk[0 .. len]);
		return true;
	}

	foreach (fname; args[3 .. $])
	{
		fs.listDir(&extractOne, fname);
	}
}

void printHelp(string[] args)
{
	write(
		"Atari XL/XE Disk Image Utility\n" ~
		"\nUsage:\n",
		args[0], " command disk_image_file [options]\n" ~
		"\nThe following commands are available:\n" ~
		" c[reate] [-b bytes] [-s sec] [files...]\n"
		"                              create empty disk image and optionally copy\n" ~
		"                              specified files to it\n" ~
		" i[nfo]                       show basic image information\n" ~
		" e[xtract] files...           extract files from disk image\n" ~
		" a[dd] files...               copy files to disk image\n" ~
		" d[ir] [path]                 list files in given directory (default is root)\n" ~
		" h[elp]                       print this message\n" ~
		"\nOptions:\n" ~
		" -b|--bytes-per-sector bytes  set number of bytes per sector for created\n" ~
		"                              image; default is ", bytesPerSector.init, "\n" ~
		" -s|--total-sectors sec       set total number of sectors for created image;\n" ~
		"                              default is ", totalSectors.init, "\n" ~
		" -v|--verbose                 emit more junk to stdout\n"
		);
}

int main(string[] args)
{
	getopt(args,
		config.caseSensitive,
		config.bundling,
		"b|bytes-per-sector", &bytesPerSector,
		"s|total-sectors", &totalSectors,
		"v|verbose", &verbose);

	if (args.length > 2)
	{
		imageFileName = args[2];
		
		auto funcs = [
			"help":&printHelp,
			"info":&info,
			"dir":&dir,
			"extract":&extract,
			];
		foreach (cmd, fun; funcs)
		{
			if (cmd.startsWith(args[1]))
				return fun(args), 0;
		}
	}
	printHelp(args);
	return 1;
}
