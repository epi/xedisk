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

import image;
import filesystem;

uint bytesPerSector = 256;
uint totalSectors = 720;
bool verbose;
string imageFileName;

void info(string[] args)
{
	auto image = Image.open(imageFileName, true);
	scope (exit) image.close();
	writeln("Image file name:   ", imageFileName);
	writeln("Total sectors:     ", image.totalSectors);
	writeln("Bytes per sectors: ", image.bytesPerSector);

	auto fs = FileSystem.open(image);
	scope (exit) fs.close();
	writeln("\nFilesystem:        ", fs.name);
	writeln("Label:             ", fs.getLabel());
	writeln("Free sectors:      ", fs.getFreeSectors());
}

void dir(string[] args)
{
	auto image = Image.open(imageFileName, true);
	scope (exit) image.close();
	auto fs = FileSystem.open(image);
	scope (exit) fs.close();
	
	fs.listDir((const ref FileInfo dirEntry)
	{
		writefln("%c%c%c%c %-12s %8d",
			dirEntry.isDeleted ? "x" : " ",
			dirEntry.isNotClosed ? "u" : " ",
			dirEntry.isDirectory ? ":" : " ",
			dirEntry.isReadOnly ? "*" : " ",
			dirEntry.name,
			dirEntry.length);
		return true;
	});
}

void printHelp(string[] args)
{
	debug {} else write(
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
