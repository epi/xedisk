DC = dmd -O -release -inline -of$@
RM = rm -f
SOURCES = xedisk.d image.d filesystem.d atr.d mydos.d vtoc.d mydosvtoc.d filename.d directory.d

OS := $(shell uname -s)
ifneq (,$(findstring windows,$(OS)))
EXESUFFIX=.exe
endif
ifneq (,$(findstring Cygwin,$(OS)))
EXESUFFIX=.exe
endif
ifneq (,$(findstring MINGW,$(OS)))
EXESUFFIX=.exe
endif
XEDISK_EXE=xedisk$(EXESUFFIX)

all: $(XEDISK_EXE)

debug:
	$(MAKE) DC="dmd -of$(XEDISK_EXE)"

$(XEDISK_EXE): $(SOURCES) 
	$(DC) $(SOURCES) -J.

clean:
	$(RM) $(XEDISK_EXE) xedisk.o $(SOURCES:.d=.obj) $(SOURCES:.d=.map)

.DELETE_ON_ERROR:
