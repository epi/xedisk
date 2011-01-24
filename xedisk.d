/*	xedisk - Atari XL/XE Disk Image Utility
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

import std.stdio: File, write, writeln, writefln;
import std.string: tolower, lastIndexOf, startsWith;
import std.conv: to;
import std.getopt: getopt, config;
import std.exception: enforce;
import std.file: exists, isfile, mkdir, listdir;
import std.algorithm: max;
import std.path: isabs, basename;

import image;
import filesystem;

BufferedImage openImage(string[] args, bool readOnly)
{
	if (args.length > 2)
		return new BufferedImage(Image.open(args[2], readOnly));
	throw new Exception("No image file name specified");
}

void info(string[] args)
{
	auto image = openImage(args, true);
	scope (exit) image.close();

	writeln("Total sectors:     ", image.totalSectors);
	writeln("Bytes per sectors: ", image.bytesPerSector);

	auto fs = FileSystem.open(image);
	scope (exit) fs.close();

	writeln("\nFilesystem:        ", fs.name);
	writeln("Label:             ", fs.label);
	writeln("Free sectors:      ", fs.freeSectors);
}

void dump(string[] args)
{
	throw new Exception("Not implemented");	
}

void list(string[] args)
{
	auto image = openImage(args, true);
	scope (exit) image.close();
	auto fs = FileSystem.open(image);
	scope (exit) fs.close();

	bool longFormat;

	getopt(args,
		config.caseSensitive,
		"v|verbose", &longFormat);

	if (longFormat)
	{
		uint files = 0;
		writeln("Filesystem: ", fs.name);
		writeln("Label:      ", fs.label, "\n");
		fs.listDir((DirEntry dirEntry)
		{
			writefln("%s%s %-12s %8d",
				dirEntry.isDir ? ":" : " ",
				dirEntry.readOnly ? "*" : " ",
				dirEntry.name.fn,
				dirEntry.size);
			++files;
			return true;
		}, args.length > 3 ? args[3] : "/");
		writefln("\n%11d files", files);
		writefln("%5d/%5d sectors free", fs.freeSectors, image.totalSectors);
	}
	else
	{
		fs.listDir((DirEntry dirEntry)
		{
			writeln(dirEntry.name);
			return true;
		}, args.length > 3 ? args[3] : "/");
	}
}

void create(string[] args)
{
	uint bytesPerSector = 256;
	uint totalSectors = 720;
	string fileSystem;

	getopt(args,
		config.caseSensitive,
		"b|bytes-per-sector", &bytesPerSector,
		"s|total-sectors", &totalSectors,
		"F|filesystem", &fileSystem);

	if (args.length < 3)
		throw new Exception("No image file name specified");
	auto img = new BufferedImage(Image.create(args[2], totalSectors, bytesPerSector));
	scope (exit) img.close();

	if (fileSystem.length)
		FileSystem.create(img, fileSystem).close();
}

void boot(string[] args)
{
	auto image = openImage(args, false);
	scope (exit) image.close();
	auto fs = FileSystem.open(image);
	scope (exit) fs.close();

	string dosVersion;
	
	getopt(args,
		config.caseSensitive,
		"d|dos-version", &dosVersion);

	enforce(dosVersion.length, "No DOS version specified");
	fs.writeDosFiles(dosVersion);
	//writeln("DOS files written");
}

void extract(string[] args)
{
	auto image = openImage(args, true);
	scope (exit) image.close();
	auto fs = FileSystem.open(image);
	scope (exit) fs.close();

	string destDir;
	bool lowerCase;
	bool verbose;

	getopt(args,
		config.caseSensitive,
		"v|verbose", &verbose,
		"c|lowercase", &lowerCase,
		"D|dest-dir", &destDir);
	if (destDir.length)
		destDir ~= "/";

	enforce(args.length >= 4, "No source files specified");

	bool extractOne(DirEntry dirEntry)
	{
		writeln(destDir ~ dirEntry.name.fn);
		if (dirEntry.isDir)
		{
			auto idir = dirEntry.openDir();
			destDir ~= lowerCase ? tolower(dirEntry.name.fn) : dirEntry.name.fn;
			if (!exists(destDir))
				mkdir(destDir);
			destDir ~= "/";
			foreach (de; idir)
				extractOne(de);
			writeln(destDir);
			destDir = destDir[0 .. max(lastIndexOf(destDir[0 .. $ - 1], "/"), 0)];
		}
		else
		{
			auto ifile = dirEntry.openFile(true, false, false);
			scope (exit) ifile.close();
			auto ofile = File(destDir ~ (lowerCase ? tolower(dirEntry.name.fn) : dirEntry.name.fn), "wb");
			auto blk = new ubyte[4096];
			for (size_t len; (len = ifile.read(blk)) > 0; )
				ofile.rawWrite(blk[0 .. len]);
		}
		return true;
	}

	foreach (fname; args[3 .. $])
	{
		fs.listDir(&extractOne, fname);
	}
}

void add(string[] args)
{
	auto image = openImage(args, false);
	scope (exit) image.close();
	auto fs = FileSystem.open(image);
	scope (exit) fs.close();

	string destDir;
	bool lowerCase;
	bool verbose;

	getopt(args,
		config.caseSensitive,
		"v|verbose", &verbose,
		"c|lowercase", &lowerCase,
		"D|dest-dir", &destDir);
//	if (destDir.length)
//		destDir ~= "/";

	auto destDirRange = fs.findDir(destDir);

	enforce(args.length >= 4, "No source files specified");

	void copyFile(DirRange dr, string fname)
	{
		writeln(fname);
		auto ofile = dr.openFile(basename(fname), "wb");
		scope (exit) ofile.close();
		auto ifile = File(fname, "rb");
		auto blk = new ubyte[4096];
		for (ubyte[] rblk; (rblk = ifile.rawRead(blk)).length > 0; )
			ofile.write(rblk);
	}

	bool addOne(std.file.DirEntry* de)
	{
		writeln(de.name);
		if (de.isdir)
			listdir(de.name, &addOne);
		else
			copyFile(destDirRange, de.name);
		return true;
	}

/*		writeln(destDir ~ dirEntry.name.fn);
		if (dirEntry.isDir)
		{
			auto idir = dirEntry.openDir();
			destDir ~= lowerCase ? tolower(dirEntry.name.fn) : dirEntry.name.fn;
			if (!exists(destDir))
				mkdir(destDir);
			destDir ~= "/";
			foreach (de; idir)
				extractOne(de);
			writeln(destDir);
			destDir = destDir[0 .. max(lastIndexOf(destDir[0 .. $ - 1], "/"), 0)];
		}
		else
		{
			auto ifile = dirEntry.openFile(true, false, false);
			scope (exit) ifile.close();
			auto ofile = File(destDir ~ (lowerCase ? tolower(dirEntry.name.fn) : dirEntry.name.fn), "wb");
			auto blk = new ubyte[4096];
			for (size_t len; (len = ifile.read(blk)) > 0; )
				ofile.rawWrite(blk[0 .. len]);
		}
		return true;
	}*/

	foreach (fname; args[3 .. $])
	{
		writeln(fname);
		if (std.file.isdir(fname))
			listdir(fname, &addOne);
		else
			copyFile(destDirRange, fname);
//		listDir(&addOne, fname);
	}
}

void printHelp(string[] args)
{
	write(
		"Atari XL/XE Disk Image Utility\n" ~
		"\nGeneral usage:\n",
		args[0], " command [disk_image_file] [options] [files...]\n" ~
		"\nAvailable commands:\n\n",
		args[0], " i[nfo] disk_image_file\n" ~
		"  Show basic image information.\n\n",
		args[0], " l[s]|l[ist] [-v] disk_image_file [path]\n" ~ 
		"  List files in given directory (default is root)\n" ~
		" -v|--verbose               use long output format\n\n",
		args[0], " n[ew] disk_image_file [-F=fs] [-b=bps] [-s=sec]\n" ~ 
		"  Create empty disk image.\n" ~
		" -F|--filesystem=fs         initialize with specified filesystem\n" ~
		" -b|--bytes-per-sector=bps  set number of bytes per sector for created\n" ~
		"                            image; default is 256\n" ~
		" -s|--total-sectors=sec     set total number of sectors for created image;\n" ~
		"                            default is 720\n\n",
		args[0], " b[oot] disk_image_file -d=version\n" ~
		"  Write DOS files to disk image.\n" ~
		" -d|--dos-version=version   specify DOS version, e.g. \"mydos450t\"\n\n",
		args[0], " e[xtract] [-D=dest] disk_image_file files...\n" ~
		"  Extract file[s] and/or directories from disk image.\n" ~
		" -v|--verbose               list names of extracted files\n" ~
		" -c|--lowercase             change case of all names to lowercase\n" ~
		" -D|--dest-dir=dest         specify destination directory, default is\n" ~
		"                            current working directory\n\n",
		args[0], " a[dd] [-D=dest] disk_image_file files...\n" ~
		"  Copy file[s] and/or directories to disk image.\n" ~
		" -v|--verbose               list names of copied files\n" ~
		" -D|--dest-dir=dest         specify destination directory within image\n\n",
		args[0], " h[elp]\n" ~
		"  Print this message\n"
		);
}

int main(string[] args)
{
	try
	{
		if (args.length > 1)
		{
			auto funcs = [
				"help":&printHelp,
				"info":&info,
				"dump":&dump,
				"ls":&list,
				"list":&list,
				"new":&create,
				"boot":&boot,
				"extract":&extract,
				"add":&add,
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
	catch (Exception e)
	{
		writeln("Ooops! " ~ e.msg);
		return 1;
	}
}
