VERSION = 1.0.0

src_lib     := xe/streams.d xe/bytemanip.d xe/exception.d \
	xe/disk.d xe/disk_impl/atr.d xe/disk_impl/xfd.d \
	xe/fs.d xe/fs_impl/cache.d xe/fs_impl/vtoc.d xe/fs_impl/mydos.d xe/fs_impl/sparta.d
src_ddoc    := xe/streams.d xe/bytemanip.d xe/exception.d xe/disk.d xe/fs.d xe/fs_impl/cache.d xedisk.ddoc
src_libtest := $(src_lib) streamimpl.d xedisk.d
src_xedisk  := $(src_lib) streamimpl.d xedisk.d
src_all     := $(subst ./,,$(shell find . -name "*.d"))

DMD = dmd
#DFLAGS = -debug -wi -g
DFLAGS = -O -release -inline -w
DFLAGS_TEST = -debug  -unittest -g -wi -cov
DFLAGS_DDOC = -o- -Ddddoc

ASCIIDOC = asciidoc -o $@ -a doctime
ZIP = 7z a -mx=9 -tzip $@
RM = rm -f

EXEPREFIX := ./
OS := $(shell uname -s)
ifneq (,$(findstring windows,$(OS)))
EXESUFFIX := .exe
EXEPREFIX :=
endif
ifneq (,$(findstring Cygwin,$(OS)))
EXESUFFIX := .exe
EXEPREFIX :=
endif
ifneq (,$(findstring MINGW,$(OS)))
EXESUFFIX := .exe
EXEPREFIX :=
endif

XEDISK_EXE := xedisk$(EXESUFFIX)

all: $(XEDISK_EXE) xedisk.html

test: unittest$(EXESUFFIX)
	$(EXEPREFIX)unittest$(EXESUFFIX) && echo && tail -n 1 *.lst | grep covered
.PHONY: test

unittest: $(src_libtest)
	$(DMD) $(DFLAGS_TEST) -of$@ $^

wc:
	@wc $(wildcard $(sort $(src_xedisk) $(src_libtest)))
.PHONY: wc

windist: xedisk-$(VERSION)-windows.zip

$(XEDISK_EXE): $(src_xedisk)
	$(DMD) $(DFLAGS) -of$@ $^

xedisk.html: README.asciidoc
	$(ASCIIDOC) $<

doc: $(src_ddoc) xedisk.html
	$(DMD) $(DFLAGS_DDOC) $(src_ddoc)
	sed -i -e 's/<big>abstract /<big>/' ddoc/*.html
.PHONY: doc

xedisk-$(VERSION)-windows.zip: xedisk.exe xedisk.html
	$(RM) $@
	$(ZIP) $^

clean:
	$(RM) $(XEDISK_EXE) $(subst /,-,$(src_all:.d=.lst)) xedisk.html xedisk-$(VERSION)-windows.zip unittest testfile
	$(RM) -r doc

.PHONY: clean debug

.DELETE_ON_ERROR:
