# Generic Makefile for albums.

HERE	= .
TOOLS	= $(HOME)/src/album/src
CAMERA	= /mnt/camera
DCIM	= dcim/101msdcf
DSC	= $(CAMERA)/$(DCIM)
RAW	= $(HERE)/$(DCIM)
OPTS	=

IMPORT	= $(shell test -d $(DCIM) && echo "--dcim=$(DCIM)")

default : update

fetch :	mountc _fetch umountc

mountc :
	-mount $(CAMERA)

_fetch :
	rsync -av --modify-window=1 \
	    $(DSC)/ $(RAW)/
	find $(RAW) -type f -perm +333 -print -exec chmod 0444 {} \;

umountc :
	-umount $(CAMERA)

update :
	perl -w $(TOOLS)/album.pl $(OPTS) --verbose --update $(IMPORT) $(HERE)

clobber :
	perl -w $(TOOLS)/album.pl $(OPTS) --verbose --clobber --update $(IMPORT) $(HERE)

export-web :
	perl -w $(TOOLS)/album.pl $(OPTS) --verbose --mediumonly $(HERE)
	rm -f web.zip
	zip -r web.zip index*.html icons medium thumbnails journal

.PHONY : journal
journal : journal/index.html

journal/index.html : info.dat $(TOOLS)/journal.pl
	test -d journal || mkdir journal
	perl $(TOOLS)/journal.pl info.dat > journal/index.html

init ::
	mkdir -p $(DCIM)
	ln -s $(TOOLS)/shellrun.exe .
	ln -s $(TOOLS)/autorun.inf .

clean ::
	rm -f .cache *png index*html large/*html *~
	rm -f shellrun.exe ShellRun.exe autorun.inf
	rm -fr icons images medium thumbnails .xvpics
