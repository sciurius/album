include ../src/generic.mk

clean ::
	rm -fr dcim import large journal

init ::
	mkdir -p $(DCIM)
	for i in dsc00248.jpg dsc00251.jpg dsc00251.mpg mov00085.mpg; do \
	  cp /spare1/Albums/2004-Ierland/$(DCIM)/$$i $(DCIM)/$$i; \
	done

virgo :
	rm -f index*.html .cache info.dat
	rm -fr large medium thumbnails icons
	echo "!title `basename $$PWD`" > info.dat
	echo "!medium" >> info.dat


