# Maintenace of icons

ICONS = index medium \
	first first-gr \
	last last-gr \
	next next-gr \
	prev prev-gr \
	up journal sound

all :
	rm -f uu
	for icon in $(ICONS); do \
	  tgif -print -ppm $$icon.obj; \
	  pnmscale -width=33 -height=33 $$icon.ppm | pnmtopng > $$icon.png; \
	  uuencode $$icon.png < $$icon.png >> uu; \
	  rm $$icon.ppm $$icon.png; \
	done
	uuencode movie.jpg < movie.jpg >> uu

clean :
	rm -f uu
	for icon in $(ICONS); do \
	  rm -f $$icon.png $$icon.ppm; \
	done
