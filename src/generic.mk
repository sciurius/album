# Generic Makefile for albums.

HERE	= .
TOOLS	= $(HOME)/src/album/tools
CAMDEV	= /dev/sonydsc
CAMERA	= /mnt/camera
DCIM	= dcim/101msdcf
DSC	= $(CAMERA)/$(DCIM)
RAW	= $(HERE)/$(DCIM)

default : update

fetch :	mountc _fetch umountc

mountc :
	test -b $(CAMDEV) && mount $(CAMERA)

_fetch :
	rsync -av --modify-window=1 \
	    $(DSC)/ $(RAW)/
	chmod 0444 $(RAW)/*.?pg

__fetch :
	perl -w $(TOOLS)/dsccopy.pl --verbose \
		"--info=>$(HERE)/info.dat" $(DSC) $(HERE)/raw

umountc :
	umount $(CAMERA)

update :
	perl -w $(TOOLS)/album.pl --verbose --update --dcim=$(RAW) $(HERE)

clobber :
	perl -w $(TOOLS)/album.pl --verbose --clobber --update --dcim=$(RAW) $(HERE)

.PHONY : journal
journal : journal/index.html

journal/index.html : info.dat $(TOOLS)/journal.pl
	test -d journal || mkdir journal
	perl $(TOOLS)/journal.pl info.dat > journal/index.html

links :
	perl -w $(TOOLS)/linkthem.pl

init :
	mkdir -p $(DCIM)
	ln -s $(TOOLS)/shellrun.exe .
	ln -s $(TOOLS)/autorun.inf .

virgo :
	rm -f index*.html .cache info.dat
	rm -fr large medium thumbnails icons
	echo "!title `basename $$PWD`" > info.dat
	echo "!medium" >> info.dat

cvt :
	perl $(TOOLS)/cvt.pl > info.srp
	perl $(HOME)/src/srep/srep.pl --data=info.srp < info.dat > info.new
	perl -we 'print "$$_: ".localtime((stat($$_))[9])."\n" foreach @ARGV' \
	  $(DCIM)/*mpg
