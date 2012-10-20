xedisk - Atari XL/XE Disk Image Utility
=======================================

`xedisk` is a small command-line utility for manipulating Atari disk image files.
It supports basic operations on raw sectors as well as on files contained on disks.

`xedisk` is written in [D programming language](http://www.digitalmars.com/d/2.0/) and tested
under Linux and, occasionally, Windows. However, it should be possible to build and run it
on any platform D compiler is available for.
It is designed to be easily embeddable in build scripts.

Supported disk image formats
----------------------------

Currently supported disk image file formats include:

* ATR (with 128, 256 and 512 bytes per sector and up to 65535 sectors);
* XFD (single and medium density).

Supported file systems
----------------------

Currently supported file systems include:

* MyDOS (full support);
* SpartaDOS (display file system information, list directory).

Installation
------------

You need [DMD 2.060](http://www.digitalmars.com/d/download.html) and a GNU-compatible `make` to build `xedisk`.

Go to console window, and, depending on your operating system, type

	$ make

or

	> mingw32-make

After a successful build, you can move the file `xedisk.exe` or `xedisk` to a directory within your `PATH`.

If you like hacking, you can easily do without `make` or use a different D compiler.

Usage
-----

A general syntax is:

	$ xedisk command [disk_image_file] [options] 

You can place options wherever you wish in the command line, as well as bundle
single-letter options together, if they do not require parameters.

If the command does not require writing into image, file is opened as read-only,
so you don't need write access rights to the file.

Until a complete documentation is available, try the following command to see
what may be implemented:

	$ xedisk help

Feedback
--------

Recommended way to deal with issues concerning `xedisk` is to clone the repo, fix the bug
or implement the missing feature, and commit the changes with a meaningful commit message.

If you don't feel so confident digging in someone else's sources, use [this tracker](http://github.com/epi/xedisk/issues).

Authors
-------

<dl>
<dt>Adrian Matoga</dt>
<dd>Idea, design, implementation, testing.</dd>
<dt>Piotr Fusik, Rafal Ciepiela</dt>
<dd>Idea, design.</dd>
<dt>Charles Marslett, Wordmark Systems<dt>
<dd>MyDOS 4.50.</dd>
</dl>

License
-------

`xedisk` is published under the terms of the GNU General Public License,
version 3. See the file `COPYING` for more information.
