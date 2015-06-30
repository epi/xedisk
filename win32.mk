# Use GNU make from Cygwin to run this script:

# Set CFLAGS and DFLAGS
ifeq ($(BUILD),debug)
	CFLAGS += -g
	DFLAGS += -g -debug
else
	DFLAGS += -O -release -inline
endif
DFLAGS     += -w -Jdos
DFLAGS_DDOC = -o- -Ddddoc
CFLAGS     += -o$@

DOTEXE     := .exe
DOTOBJ     := .obj
RUN        :=
PATHSEP    := $(shell echo '\\')

DMD        := dmd.exe
CC         := dmc.exe
CANDLE     := candle -ext WixUtilExtension -nologo
LIGHT      := light -ext WixUtilExtension -nologo

LIB_XEBASE  := $(builddir)/xebase.lib
LIB_XEDISK  := $(builddir)/xedisk.lib
EXE_XEDISK  := $(builddir)/xedisk.exe

################################################################################
# Rules begin here
################################################################################

ifeq ($(BUILD),)
# No build was defined, so here we define release and debug
# targets. BUILD is not defined in user runs, only by recursive
# self-invocations. So the targets in this branch are accessible to
# end users.
release :
	@$(MAKE) --no-print-directory BUILD=release
debug :
	@$(MAKE) --no-print-directory BUILD=debug
unittest :
	@$(MAKE) --no-print-directory BUILD=debug unittest
	@$(MAKE) --no-print-directory BUILD=release unittest
setup :
	@$(MAKE) --no-print-directory BUILD=release setup
else
# This branch is normally taken in recursive builds. All we need to do
# is set the default build to $(BUILD) (which is either debug or
# release) and then let the unittest depend on that build's unittests.
$(BUILD) : $(LIB_XEBASE) $(LIB_XEDISK) $(EXE_XEDISK)
unittest : $(addsuffix $(DOTEXE),$(addprefix $(builddir)/unittest/,$(TEST_MODULES)))
setup    : build/xedisk-$(VERSION)-win32.msi
endif

$(EXE_XEDISK): $(src_exe_xedisk) $(LIB_XEBASE) $(LIB_XEDISK)
	@echo " DMD  $@"
	@$(DMD) $(DFLAGS) $(subst /,$(PATHSEP),-of$@ $(src_exe_xedisk) $(LIB_XEDISK) $(LIB_XEBASE))
# ^ OPTLINK is picky about path separators

$(LIB_XEBASE): $(src_lib_xebase)
	@echo " DMD  $@"
	@$(DMD) $(DFLAGS) -lib -of$@ $(src_lib_xebase)

$(LIB_XEDISK): $(src_lib_xedisk) $(src_lib_xebase)
	@echo " DMD  $@"
	@$(DMD) $(DFLAGS) -lib -of$@ $(src_lib_xedisk)

$(addprefix $(builddir)/unittest/,$(DISABLED_TESTS)) :
	@echo Testing $@ - disabled

$(builddir)/unittest/%$(DOTEXE) : %.d $(builddir)/emptymain.d xe/test.d $(LIB_XEDISK) $(LIB_XEBASE)
	@echo Testing $@
	@$(DMD) $(DFLAGS) -unittest -cov $(subst /,$(PATHSEP),-of$@ $^)
	@$(RUN)$@ || rm -f $@
	@mkdir -p $(builddir)/cov && mv $(subst /,-,$(<:.d=.lst)) $(builddir)/cov/$(subst /,-,$(<:.d=.lst))
	@cat $(builddir)/cov/$(subst /,-,$(<:.d=.lst)) | grep ".*covered$$"

$(builddir)/emptymain.d :
	@mkdir -p $(builddir) && echo 'void main(){}' >$@

build/xedisk-$(VERSION)-win32.msi: build/xedisk.wixobj setup/license.rtf setup/Website.url $(builddir)/xedisk.exe xedisk_manual.html
	$(LIGHT) -ext WixUIExtension -sice:ICE69 -o $@ $<

build/xedisk.wixobj: setup/xedisk.wxs
	$(CANDLE) -dVERSION=$(VERSION) -o $@ $<

CLEAN += build

.PHONY: release debug unittest setup

.DELETE_ON_ERROR:
