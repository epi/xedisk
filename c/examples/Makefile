progs   := diskinfo mkatr
libs    := libcxedisk.a libdtoc.a
headers := ../xe/disk.h ../xe/fs.h

all: $(progs)
.PHONY: all

$(libs):
	( cd ../.. && $(MAKE) --no-print-directory BUILD=release c/examples/$@ )

% : %.c $(libs) $(headers)
	gcc -Wall -O2 -I.. -o $@ $< -L. -lcxedisk -lphobos2 -lpthread -lrt -ldtoc

clean:
	rm -f  $(progs) $(libs)
.PHONY: clean
