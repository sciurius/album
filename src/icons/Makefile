
ICONS = first-gr first index journal last-gr last medium movie2 movie next-gr next prev-gr prev sound2 sound 

all :
	rm -f uu
	for icon in $(ICONS); do \
	  tgif -print -ppm $$icon.obj; \
	  pnmscale -width=33 -height=33 $$icon.ppm | pnmtopng > $$icon.png; \
	  uuencode icons/$$icon.png < $$icon.png >> uu; \
	done

clean :
	rm -f uu
	for icon in $(ICONS); do \
	  rm -f $$icon.png $$icon.ppm; \
	done
