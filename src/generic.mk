# Generic Makefile for albums.

HERE	= .
TOOLS	= $(HOME)/src/album/tools
CAMERA	= /mnt/camera
DCIM	= dcim/101msdcf
DSC	= $(CAMERA)/$(DCIM)
RAW	= $(HERE)/$(DCIM)

default : update

fetch :	mountc _fetch umountc

mountc :
	-mount $(CAMERA)

_fetch :
	rsync -av --modify-window=1 \
	    $(DSC)/ $(RAW)/
	chmod 0444 $(RAW)/*.?pg

umountc :
	-umount $(CAMERA)

update :
	perl -w $(TOOLS)/album.pl --verbose --update --dcim=$(RAW) $(HERE)

clobber :
	perl -w $(TOOLS)/album.pl --verbose --clobber --update --dcim=$(RAW) $(HERE)

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
