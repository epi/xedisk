VERSION = 1.0.0
SOURCES = xedisk.d image.d filesystem.d atr.d mydos.d filename.d vtoc.d

DC = dmd -O -release -inline -Dddoc -of$@
ASCIIDOC = asciidoc -o $@ -a doctime
ASCIIDOC_POSTPROCESS = perl -pi.bak -e "s/527bbd;/20a0a0;/;END{unlink '$@.bak'}" $@
ASCIIDOC_VALIDATE = xmllint --valid --noout --nonet $@
ZIP = 7z a -mx=9 -tzip $@
RM = rm -f

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

all: $(XEDISK_EXE) xedisk.html

windist: xedisk-$(VERSION)-windows.zip
	
debug:
	$(MAKE) DC="dmd -debug -unittest -g -w -wi -ofdebug_$(XEDISK_EXE)"

$(XEDISK_EXE): $(SOURCES)
	$(DC) $(SOURCES) -Jdos

xedisk.html: README.asciidoc
	$(ASCIIDOC) $<
	$(ASCIIDOC_POSTPROCESS)
	$(ASCIIDOC_VALIDATE)

xedisk-$(VERSION)-windows.zip: xedisk.exe xedisk.html
	$(RM) $@
	$(ZIP) $^

clean:
	$(RM) $(XEDISK_EXE) xedisk.o $(SOURCES:.d=.obj) $(SOURCES:.d=.map) xedisk.html xedisk-$(VERSION)-windows.zip

.DELETE_ON_ERROR:
