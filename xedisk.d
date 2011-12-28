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

import std.stdio: File, write, writeln, writefln, stderr;
import std.string: toLower, lastIndexOf, startsWith;
import std.conv: to;
import std.getopt: getopt, config;
import std.exception: enforce;
import std.file: exists, isFile, mkdir, mkdirRecurse, dirEntries;
import std.algorithm: max;
import std.path: isabs, baseName;

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
	bool ignoreReadErrors;

	getopt(args,
		config.caseSensitive,
		"v|verbose", &verbose,
		"c|lowercase", &lowerCase,
		"g|ignore-read-errors", &ignoreReadErrors,
		"D|dest-dir", &destDir);
	if (destDir.length)
	{
		if (!exists(destDir))
			mkdirRecurse(destDir);
		destDir ~= "/";
	}

	enforce(args.length >= 4, "No source files specified");

	bool extractOne(DirEntry dirEntry)
	{
		string name;
		try
		{
			if (dirEntry.isDir)
			{
				auto destDirLen = destDir.length;
				destDir ~= lowerCase ? toLower(dirEntry.name.fn) : dirEntry.name.fn;
				name = destDir;
				if (verbose)
					writeln("Creating directory ", destDir);
				if (!exists(destDir))
					mkdir(destDir);
				destDir ~= "/";
				foreach (de; dirEntry.openDir())
				{
					if (!extractOne(de))
						return false;
				}
				destDir = destDir[0 .. destDirLen];
			}
			else
			{
				name = destDir ~ (lowerCase ? toLower(dirEntry.name.fn) : dirEntry.name.fn);
				if (verbose)
					writeln("Extracting ", name);
				auto ifile = dirEntry.openFile(true, false, false);
				scope (exit) ifile.close();
				auto ofile = File(name, "wb");
				auto blk = new ubyte[4096];
				for (size_t len; (len = ifile.read(blk)) > 0; )
					ofile.rawWrite(blk[0 .. len]);
			}
		}
		catch (Exception e)
		{
			if (!verbose)
				stderr.writeln("File:  ", name);
			stderr.writeln("Error: ", e.msg);
			if (!ignoreReadErrors)
			{
				stderr.writeln("Use -g to skip any corrupted files in the disk image");
				return false;
			}
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
		auto ofile = dr.openFile(baseName(fname), "wb");
		scope (exit) ofile.close();
		auto ifile = File(fname, "rb");
		auto blk = new ubyte[4096];
		for (ubyte[] rblk; (rblk = ifile.rawRead(blk)).length > 0; )
			ofile.write(rblk);
	}

/*	bool addOne(std.file.DirEntry* de)
	{
		writeln(de.name);
		if (de.isDir)
		{
			foreach (DirEntry nde; dirEntries(de.name))
				addOne(nde);
		}
		else
			copyFile(destDirRange, de.name);
		return true;
	}*/

/*		writeln(destDir ~ dirEntry.name.fn);
		if (dirEntry.isDir)
		{
			auto idir = dirEntry.openDir();
			destDir ~= lowerCase ? toLower(dirEntry.name.fn) : dirEntry.name.fn;
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
			auto ofile = File(destDir ~ (lowerCase ? toLower(dirEntry.name.fn) : dirEntry.name.fn), "wb");
			auto blk = new ubyte[4096];
			for (size_t len; (len = ifile.read(blk)) > 0; )
				ofile.rawWrite(blk[0 .. len]);
		}
		return true;
	}*/

	foreach (fname; args[3 .. $])
	{
		writeln(fname);
//		if (std.file.isDir(fname))
//			listdir(fname, &addOne);
//		else
			copyFile(destDirRange, fname);
//		listDir(&addOne, fname);
	}
}

void printHelp(string[] args)
{
	writeln("Atari XL/XE Disk Image Utility\nUsage:");
	if (args.length > 2 && args[1] == "help")
	{
		switch (args[2]) {
		case "i":
		case "info":
			write(args[0], " i|info\n" ~
				"  Show basic image information.\n");
			return;
		case "l":
		case "ls":
		case "list":
		case "dir":
			write(args[0], " l|ls|list|dir [options] disk_image_file [path]\n" ~
				"  List files in given directory (default is root)\n" ~
				"Available options:\n" ~
				" -v|--verbose               use long output format\n");
			return;
		case "n":
		case "create":
			write(args[0], " n|create [options] disk_image_file\n" ~
				"  Create empty disk image.\n" ~
				"Available options:\n" ~
				" -F|--filesystem=fs         initialize with specified filesystem\n" ~
				" -b|--bytes-per-sector=bps  set number of bytes per sector for created\n" ~
				"                            image; default is 256\n" ~
				" -s|--total-sectors=sec     set total number of sectors for created image;\n" ~
				"                            default is 720\n");
			return;
		case "a":
		case "add":
			write(args[0], " a|add [options] disk_image_file files...\n" ~
				"  Copy files and/or directories to disk image.\n" ~
				"Available options:\n" ~
				" -v|--verbose        list names of copied files\n" ~
				" -D|--dest-dir=dest  specify destination directory within image\n");
			return;
		case "x":
		case "extract":
			write(args[0], " x|extract [options] disk_image_file files...\n" ~
				"  Extract file[s] and/or directories from disk image.\n" ~
				"Available options:\n" ~
				" -v|--verbose               list names of extracted files\n" ~
				" -c|--lowercase             change case of all names to lowercase\n" ~
				" -g|--ignore-read-errors    continue after trying to read a corrupted file\n" ~
				" -D|--dest-dir=dest         specify destination directory, default is\n" ~
				"                            current working directory\n");
			return;
		case "boot":
			write(args[0], " boot [options] disk_image_file\n" ~
				"  Write DOS files to disk image.\n" ~
				"Available options:\n" ~
				" -d|--dos-version=version   specify DOS version, e.g. \"mydos450t\"\n");
			return;
		case "help":
			write(args[0], " help [command]\n" ~
				"  Print list of available commands or usage information for\n" ~
				"a specified command\n");
			return;
		default:
		}
	}
	write(args[0], " command [options] [disk_image_file] [files...]\n" ~
		"\nAvailable commands:\n\n" ~
		" i|info          Show basic image information.\n" ~
		" l|ls|list|dir   List files in the disk image\n" ~
		" n|create        Create an empty disk image.\n" ~
		" x|extract       Extract file[s] and/or directories from disk image.\n" ~
		" a|add           Copy file[s] and/or directories to disk image.\n" ~
		" boot            Write DOS files to disk image.\n" ~
		" help            Print usage information message\n" ~
		"\nType\n",
		args[0], " help [command] to show usage information for a specific command\n");
}

int main(string[] args)
{
	try
	{
		if (args.length > 1)
		{
			immutable funcs = [
				"a":&add,
				"add":&add,
				"x":&extract,
				"extract":&extract,
				"i":&info,
				"info":&info,
				"dump":&dump,
				"l":&list,
				"ls":&list,
				"list":&list,
				"dir":&list,
				"new":&create,
				"boot":&boot,
				"help":&printHelp,
				"-h":&printHelp,
				"--help":&printHelp
				];
			auto fun = funcs.get(args[1], null);
			if (fun !is null)
				return fun(args), 0;
		}
		printHelp(args);
		return 1;
	}
	catch (Exception e)
	{
		stderr.writeln("Ooops! " ~ e.msg);
		return 1;
	}
}
