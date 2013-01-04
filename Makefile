# Use GNU make 3.82 to run this script.
# Under Windows, run make under Cygwin.

VERSION  := 1.0.0
CLEAN    :=

ASCIIDOC := asciidoc

builddir = build/$(BUILD)

# what to test
TEST_MODULES := \
	xe/streams \
	xe/disk \
	xe/disk_impl/atr \
	xe/disk_impl/xfd \
	xe/disk_impl/idea \
	xe/disk_impl/msdos \
	xe/fs \
	xe/fs_impl/cache \
	xe/fs_impl/vtoc \
	xe/fs_impl/mydos \
	xe/fs_impl/sparta \
	xe/fs_impl/fat \
	xe/util \
	xedisk

# sources
src_lib_xebase := xe/streams.d xe/bytemanip.d xe/exception.d \
	xe/util.d
src_lib_xedisk := xe/disk.d xe/disk_impl/all.d xe/disk_impl/atr.d \
	xe/disk_impl/xfd.d xe/disk_impl/idea.d xe/disk_impl/msdos.d \
	xe/fs.d xe/fs_impl/cache.d xe/fs_impl/vtoc.d xe/fs_impl/all.d \
	xe/fs_impl/mydos.d xe/fs_impl/sparta.d xe/fs_impl/fat.d \

src_exe_xedisk := xedisk.d
src_exe_efdisk := efdisk.d $(builddir)/getgeo.o
src_exe_xedrive := xedrive/xedrive.d xedrive/serial.d xedrive/disk.d \
	xedrive/siodevice.d xedrive/sioserver.d \
	$(builddir)/xedrive/serial_c.o

src_ddoc    := xe/streams.d xe/bytemanip.d xe/exception.d xe/disk.d xe/fs.d \
	xe/fs_impl/cache.d xedisk.ddoc

src_efdisk  := efdisk.d xe/bytemanip.d getgeo.o

# include rules for target OS
ifeq (,$(OS))
OS := $(shell uname)
endif
ifneq (,$(findstring Windows,$(OS)))
	include win32.mk
else
	ifneq (,$(findstring Cygwin,$(OS)))
		include win32.mk
	else
		ifneq (,$(findstring CYGWIN,$(OS)))
			include win32.mk
		else
			include posix.mk
		endif
	endif
endif

# common rules
xedisk_manual.html: xedisk_manual.asciidoc
	$(ASCIIDOC) -o $@ $<
CLEAN += xedisk_manual.html

clean:
	rm -rf $(CLEAN)
.PHONY: clean

.DELETE_ON_ERROR:
