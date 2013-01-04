# based on posix.mak from the phobos project

# Set CFLAGS and DFLAGS
CFLAGS += -Wall
DFLAGS += -w -property

ifneq (,$(findstring debug,$(BUILD)))
	CFLAGS += -g
	DFLAGS += -g -debug
else
	ifneq (,$(findstring release,$(BUILD)))
		CFLAGS += -O3
		DFLAGS += -O -release -inline
	endif
endif

DFLAGS += -Jdos
DFLAGS_DDOC = -o- -Ddddoc

CROSS_COMPILE :=
ifneq (,$(CROSS_COMPILE))
DMD           := $(CROSS_COMPILE)gdmd
else
DMD           := dmd
endif
CC            := $(CROSS_COMPILE)gcc

RM  := rm -f

RUN := ./

# what to build
LIB_XEBASE  := $(builddir)/libxebase.a
LIB_XEDISK  := $(builddir)/libxedisk.a
EXE_XEDISK  := $(builddir)/xedisk
EXE_EFDISK  := $(builddir)/efdisk
LIB_CXEDISK := $(builddir)/libcxedisk.a
LIB_DTOC    := $(builddir)/libdtoc.a
EXE_XEFUSE  := $(builddir)/xefuse
EXE_XEDRIVE := $(builddir)/xedrive/xedrive

# fancy formatting
yellow := $(shell echo `tput bold && tput setf 6`)
white  := $(shell echo `tput sgr0`)
green  := $(shell echo `tput bold && tput setf 2`)
red    := $(shell echo `tput bold && tput setf 4`)

# commands

do_dmd_exe  = @echo " DMD   $@" && mkdir -p $(dir $@) && $(DMD) $(DFLAGS) -of$@
do_dmd_lib  = @echo " DMD   $@" && mkdir -p $(dir $@) && $(DMD) $(DFLAGS) -of$@ -lib
do_cc       = @echo " CC    $@" && mkdir -p $(dir $@) && $(CC) $(CFLAGS) -o $@ -c
do_ccld_exe = @echo " CCLD  $@" && mkdir -p $(dir $@) && $(CC) $(CFLAGS) -o $@
do_cp       = @echo " CP    $@" && mkdir -p $(dir $@) && cp $< $@

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
rpi-release :
	@$(MAKE) --no-print-directory OS=linux BUILD=rpi/release CROSS_COMPILE=arm-linux-gnueabihf- EXE_XEFUSE=
rpi-debug :
	@$(MAKE) --no-print-directory OS=linux BUILD=rpi/debug CROSS_COMPILE=arm-linux-gnueabihf- EXE_XEFUSE=
unittest :
	@$(MAKE) --no-print-directory OS=$(OS) BUILD=debug unittest
	@$(MAKE) --no-print-directory OS=$(OS) BUILD=release unittest
else
# This branch is normally taken in recursive builds. All we need to do
# is set the default build to $(BUILD) (which is either debug or
# release) and then let the unittest depend on that build's unittests.
$(BUILD) : $(LIB_XEBASE) $(LIB_XEDISK) $(LIB_CXEDISK) $(LIB_DTOC) $(EXE_XEDISK) $(EXE_EFDISK) $(EXE_XEFUSE) $(EXE_XEDRIVE)
unittest : $(addprefix $(builddir)/unittest/,$(TEST_MODULES))
endif
.PHONY: release debug unittest

$(EXE_XEDISK): $(src_exe_xedisk) $(LIB_XEDISK) $(LIB_XEBASE)
	$(do_dmd_exe) $^

$(EXE_EFDISK): $(src_exe_efdisk) $(LIB_XEBASE)
	$(do_dmd_exe) $^

$(LIB_XEBASE): $(src_lib_xebase)
	$(do_dmd_lib) $^

$(LIB_XEDISK): $(src_lib_xedisk) $(src_lib_xebase)
	$(do_dmd_lib) $(src_lib_xedisk)

$(LIB_CXEDISK): c/c_api.d $(builddir)/c/c_init.o $(src_lib_xedisk) $(src_lib_xebase)
	$(do_dmd_lib) $^

$(LIB_DTOC): $(builddir)/emptymain.d
	$(do_dmd_lib) $^

$(EXE_XEFUSE): fuse/xefuse.c $(LIB_CXEDISK) $(LIB_DTOC) c/xe/stream.h c/xe/disk.h c/xe/fs.h
	$(do_ccld_exe) -D_FILE_OFFSET_BITS=64 -DFUSE_USE_VERSION=22 -Ic \
		$< -L$(builddir) -lfuse -lcxedisk -lphobos2 -lpthread -lrt -ldtoc

$(EXE_XEDRIVE): $(src_exe_xedrive)
	$(do_dmd_exe) $^

c/examples/libcxedisk.a: $(LIB_CXEDISK)
	$(do_cp)

c/examples/libdtoc.a: $(LIB_DTOC)
	$(do_cp)

$(builddir)/%.o : %.c
	$(do_cc) $<

$(addprefix $(builddir)/unittest/,$(DISABLED_TESTS)) :
	@echo Testing $@ - disabled

$(builddir)/unittest/% : %.d $(builddir)/emptymain.d xe/test.d $(LIB_XEDISK) $(LIB_XEBASE)
	@echo "$(yellow)Testing $@$(white)"
	@$(DMD) $(DFLAGS) -unittest -cov -of$@ $^
	@$(RUN)$@ && echo -n "$(green)" || ( $(RM) $@ && echo -n "$(red)" )
	@mkdir -p $(builddir)/cov && mv $(subst /,-,$(<:.d=.lst)) $(builddir)/cov/$(subst /,-,$(<:.d=.lst))
	@cat $(builddir)/cov/$(subst /,-,$(<:.d=.lst)) | grep "$<.*covered" && echo -n `tput sgr0`

$(builddir)/emptymain.d :
	@echo " GEN   $@" && mkdir -p $(builddir) && echo 'void main(){}' >$@
CLEAN += *emptymain.lst

doc: $(src_ddoc) xedisk_manual.html
	@echo " DOC"
	@$(DMD) $(DFLAGS_DDOC) $(src_ddoc)
	@sed -i -e 's/<big>abstract /<big>/' ddoc/*.html
.PHONY: doc
CLEAN += ddoc/*.html

CLEAN += build
