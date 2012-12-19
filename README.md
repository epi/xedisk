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
* XFD (single and medium density);
* KMK/JZ IDE (IDEa) partitions.

Supported file systems
----------------------

Currently supported file systems include:

* MyDOS (full support);
* SpartaDOS (display file system information, list directory, extract files and directories).

Feedback
--------

Recommended way to deal with issues found in `xedisk` is to clone the
github repository, fix the bug or implement the missing feature, commit the
changes with a meaningful commit message, and send a pull request to the
author.

If you don't feel so confident digging in someone else's sources, use
[this tracker](http://github.com/epi/xedisk/issues).

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
