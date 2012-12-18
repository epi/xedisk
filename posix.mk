# based on posix.mak from the phobos project

# Set CFLAGS and DFLAGS
CFLAGS += -Wall
DFLAGS += -w -property
ifeq ($(BUILD),debug)
	CFLAGS += -g
	DFLAGS += -g -debug
else
	CFLAGS += -O3
	DFLAGS += -O -release -inline
endif

DFLAGS += -Jdos
DFLAGS_DDOC = -o- -Ddddoc

DMD := dmd
CC  := gcc
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

# fancy formatting
yellow := $(shell echo `tput bold && tput setf 6`)
white  := $(shell echo `tput sgr0`)
green  := $(shell echo `tput bold && tput setf 2`)
red    := $(shell echo `tput bold && tput setf 4`)

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
unittest : $(addprefix $(builddir)/unittest/,$(TEST_MODULES))
endif

$(EXE_XEDISK): $(src_exe_xedisk) $(LIB_XEBASE) $(LIB_XEDISK)
	@echo " DMD   $@"
	@$(DMD) $(DFLAGS) -of$@ $(src_exe_xedisk) $(LIB_XEDISK) $(LIB_XEBASE)

$(EXE_EFDISK): $(src_exe_efdisk) $(LIB_XEBASE)
	@echo " DMD   $@"
	@$(DMD) $(DFLAGS) -of$@ $(src_exe_efdisk) $(LIB_XEBASE)

$(LIB_XEBASE): $(src_lib_xebase)
	@echo " DMD   $@"
	@$(DMD) $(DFLAGS) -lib -of$@ $(src_lib_xebase)

$(LIB_XEDISK): $(src_lib_xedisk) $(src_lib_xebase)
	@echo " DMD   $@"
	@$(DMD) $(DFLAGS) -lib -of$@ $(src_lib_xedisk)

$(LIB_CXEDISK): c/c_api.d $(builddir)/c/c_init.o $(src_lib_xedisk) $(src_lib_xebase)
	@echo " DMD   $@"
	@$(DMD) $(DFLAGS) -lib -of$@ $^

$(LIB_DTOC): $(builddir)/emptymain.d
	@echo " DMD   $@"
	@$(DMD) $(DFLAGS) -lib -of$@ $^

$(EXE_XEFUSE): fuse/xefuse.c $(LIB_CXEDISK) $(LIB_DTOC) c/xe/stream.h c/xe/disk.h c/xe/fs.h
	@echo " CC    $@"
	@$(CC) $(CFLAGS) -D_FILE_OFFSET_BITS=64 -DFUSE_USE_VERSION=22 -Ic \
		fuse/xefuse.c -o $@ \
		-L$(builddir) -lfuse -lcxedisk -lphobos2 -lpthread -lrt -ldtoc

c/examples/libcxedisk.a: $(LIB_CXEDISK)
	@echo " CP    $@"
	@cp $< $@

c/examples/libdtoc.a: $(LIB_DTOC)
	@echo " CP    $@"
	@cp $< $@

$(builddir)/%.o : %.c
	@echo " CC    $@"
	@mkdir -p `dirname "$@"` && $(CC) $(CFLAGS) -c $< -o $@

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
	$(DMD) $(DFLAGS_DDOC) $(src_ddoc)
	sed -i -e 's/<big>abstract /<big>/' ddoc/*.html
.PHONY: doc
CLEAN += ddoc/*.html

CLEAN += build

.PHONY: release debug unittest clean

.DELETE_ON_ERROR:
