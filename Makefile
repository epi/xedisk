# Large parts of this Makefile are stolen from the phobos project (posix.mak)

# OS can be linux, osx, freebsd, win32, win32wine. If left
# blank, the system will be determined by using uname
ifeq (,$(OS))
    OS:=$(shell uname)
    ifeq (Darwin,$(OS))
        OS:=osx
    else
        ifeq (Linux,$(OS))
            OS:=linux
        else
            ifeq (FreeBSD,$(OS))
                OS:=freebsd
            else
                $(error Unrecognized or unsupported OS for uname: $(OS))
            endif
        endif
    endif
endif

# Set CFLAGS
CFLAGS := -Wall
ifeq ($(BUILD),debug)
	CFLAGS += -g
else
	CFLAGS += -O3
endif

# Set DFLAGS
DFLAGS := -w -property
ifeq ($(BUILD),debug)
	DFLAGS += -g -debug
else
	DFLAGS += -O -release -inline
endif
DFLAGS += -Jdos
DFLAGS_DDOC = -o- -Ddddoc

# Set CC and DMD
ifeq ($(OS),win32wine)
	CC = wine dmc.exe
	DMD ?= wine dmd.exe
	RUN = wine #
else
	DMD ?= dmd
	ifeq ($(OS),win32)
		CC = dmc
		RUN =
	else
		CC = gcc
		RUN = ./
	endif
endif

# Set DOTOBJ and DOTEXE
ifeq (,$(findstring win,$(OS)))
	DOTEXE:=
else
	DOTEXE:=.exe
endif

TEST_MODULES = \
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
	xedisk

BUILDDIR = build
ifeq (,$(BUILDDIR))
	BUILDDIR = .
endif
builddir = $(BUILDDIR)/$(OS)/$(BUILD)

# Set LIB, the ultimate target
ifeq (,$(findstring win,$(OS)))
	LIB_XEBASE  := $(builddir)/libxebase.a
	LIB_XEDISK  := $(builddir)/libxedisk.a
	EXE_XEDISK  := $(builddir)/xedisk
	EXE_EFDISK  := $(builddir)/efdisk
	LIB_CXEDISK := $(builddir)/libcxedisk.a
	LIB_DTOC    := $(builddir)/libdtoc.a
	EXE_XEFUSE  := $(builddir)/xefuse
else
	LIB_XEBASE  := $(builddir)/xebase.lib
	LIB_XEDISK  := $(builddir)/xedisk.lib
	EXE_XEDISK  := $(builddir)/xedisk.exe
	EXE_EFDISK  := $(builddir)/efdisk.exe
	LIB_CXEDISK := $(builddir)/cxedisk.lib
	LIB_DTOC    := $(builddir)/dtoc.lib
endif

MARKDOWN = markdown
ZIP = 7z a -mx=9 -tzip $@
RM = rm -f

src_lib_xebase := xe/streams.d xe/bytemanip.d xe/exception.d
src_lib_xedisk := xe/disk.d xe/disk_impl/all.d xe/disk_impl/atr.d xe/disk_impl/xfd.d xe/disk_impl/idea.d xe/disk_impl/msdos.d \
	xe/fs.d xe/fs_impl/cache.d xe/fs_impl/vtoc.d xe/fs_impl/all.d xe/fs_impl/mydos.d xe/fs_impl/sparta.d xe/fs_impl/fat.d

src_exe_xedisk := xedisk.d
src_exe_efdisk := efdisk.d $(builddir)/getgeo.o

src_ddoc    := xe/streams.d xe/bytemanip.d xe/exception.d xe/disk.d xe/fs.d xe/fs_impl/cache.d xedisk.ddoc
src_all     := $(subst ./,,$(shell find . -name "*.d"))

src_efdisk  := efdisk.d xe/bytemanip.d getgeo.o

################################################################################
# Rules begin here
################################################################################

ifeq ($(BUILD),)
# No build was defined, so here we define release and debug
# targets. BUILD is not defined in user runs, only by recursive
# self-invocations. So the targets in this branch are accessible to
# end users.
release :
	@$(MAKE) --no-print-directory OS=$(OS) BUILD=release
debug :
	@$(MAKE) --no-print-directory OS=$(OS) BUILD=debug
unittest :
	@$(MAKE) --no-print-directory OS=$(OS) BUILD=debug unittest
	@$(MAKE) --no-print-directory OS=$(OS) BUILD=release unittest
else
# This branch is normally taken in recursive builds. All we need to do
# is set the default build to $(BUILD) (which is either debug or
# release) and then let the unittest depend on that build's unittests.
$(BUILD) : $(LIB_XEBASE) $(LIB_XEDISK) $(LIB_CXEDISK) $(LIB_DTOC) $(EXE_XEDISK) $(EXE_EFDISK) $(EXE_XEFUSE)
unittest : $(addsuffix $(DOTEXE),$(addprefix $(builddir)/unittest/,$(TEST_MODULES)))
endif

$(EXE_XEDISK): $(src_exe_xedisk) $(LIB_XEBASE) $(LIB_XEDISK)
	@echo " DMD  $@"
	@$(DMD) $(DFLAGS) -of$@ $(src_exe_xedisk) $(LIB_XEDISK) $(LIB_XEBASE)

$(EXE_EFDISK): $(src_exe_efdisk) $(LIB_XEBASE)
	@echo " DMD  $@"
	@$(DMD) $(DFLAGS) -of$@ $(src_exe_efdisk) $(LIB_XEBASE)

$(LIB_XEBASE): $(src_lib_xebase)
	@echo " DMD  $@"
	@$(DMD) $(DFLAGS) -lib -of$@ $(src_lib_xebase)

$(LIB_XEDISK): $(src_lib_xedisk) $(src_lib_xebase)
	@echo " DMD  $@"
	@$(DMD) $(DFLAGS) -lib -of$@ $(src_lib_xedisk)

$(LIB_CXEDISK): c/c_api.d $(builddir)/c/c_init.o $(src_lib_xedisk) $(src_lib_xebase)
	@echo " DMD  $@"
	@$(DMD) $(DFLAGS) -lib -of$@ $^

$(LIB_DTOC): $(builddir)/emptymain.d
	@echo " DMD  $@"
	@$(DMD) $(DFLAGS) -lib -of$@ $^

ifneq ($(EXE_XEFUSE),)
$(EXE_XEFUSE): fuse/xefuse.c $(LIB_CXEDISK) $(LIB_DTOC) c/xe/stream.h c/xe/disk.h c/xe/fs.h
	@echo " CC   $@"
	@$(CC) $(CFLAGS) -D_FILE_OFFSET_BITS=64 -DFUSE_USE_VERSION=22 -Ic fuse/xefuse.c -o $@ -L$(builddir) -lfuse -lcxedisk -lphobos2 -lpthread -lrt -ldtoc
endif

c/examples/libcxedisk.a: $(LIB_CXEDISK)
	@echo " CP   $@"
	@cp $< $@

c/examples/libdtoc.a: $(LIB_DTOC)
	@echo " CP   $@"
	@cp $< $@

$(builddir)/%.o : %.c
	@echo " CC   $@"
	@mkdir -p `dirname "$@"` && $(CC) $(CFLAGS) -c $< -o $@

$(builddir)/%.a : %.o
	$(AR) rc $@ $<

$(addprefix $(builddir)/unittest/,$(DISABLED_TESTS)) :
	@echo Testing $@ - disabled

$(builddir)/unittest/%$(DOTEXE) : %.d $(builddir)/emptymain.d xe/test.d $(LIB_XEDISK) $(LIB_XEBASE)
	@echo `tput bold && tput setf 6`Testing $@`tput sgr0`
	@$(DMD) $(DFLAGS) -unittest -cov -of$@ $^
# make the file very old so it builds and runs again if it fails
	@touch -t 197001230123 $@
# run unittest in its own directory
	@$(RUN)$@ && echo -n `tput bold && tput setf 2` || echo -n `tput bold && tput setf 4`
# succeeded, render the file new again
	@touch $@
	@mkdir -p $(builddir)/cov && mv $(subst /,-,$(<:.d=.lst)) $(builddir)/cov/$(subst /,-,$(<:.d=.lst))
	@cat $(builddir)/cov/$(subst /,-,$(<:.d=.lst)) | grep "$<.*covered" && echo -n `tput sgr0`

$(builddir)/unittest/%$(DOTEXE) : $(builddir)/getgeo.a

.PHONY: release debug unittest

$(builddir)/emptymain.d : $(builddir)/.directory
	@echo 'void main(){}' >$@

$(builddir)/.directory :
	mkdir -p $(builddir) || exists $(builddir)
	touch $@

xedisk.html: README.md
	$(MARKDOWN) $< >$@

doc: $(src_ddoc) xedisk.html
	$(DMD) $(DFLAGS_DDOC) $(src_ddoc)
	sed -i -e 's/<big>abstract /<big>/' ddoc/*.html
.PHONY: doc

clean:
	$(RM) -rf $(BUILDDIR) doc xedisk.html *emptymain.lst xe-test.lst
	$(RM) -rf ddoc/*.html

.PHONY: clean debug

.DELETE_ON_ERROR:
