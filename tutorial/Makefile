ALBUM	= perl $(HOME)/src/album/tools/album.pl
ISRC	= /spare1/Albums/2004-Ierland/dcim/101msdcf

COPY	= convert
COPY	= cp

init :
	rm -fr large medium thumbnails dcim icons import
	rm -f .cache info.dat index*html
	mkdir large
	$(COPY) $(ISRC)/dsc00058.jpg large/im023.jpg
	$(COPY) $(ISRC)/dsc00078.jpg large/im024.jpg
	$(COPY) $(ISRC)/dsc00090.jpg large/im025.jpg
	$(COPY) $(ISRC)/dsc00116.jpg large/im026.jpg
	$(COPY) $(ISRC)/dsc00147.jpg large/im027.jpg
	$(COPY) $(ISRC)/dsc00197.jpg large/im028.jpg
	$(COPY) $(ISRC)/dsc00203.jpg large/im029.jpg
	mkdir import
	$(COPY) $(ISRC)/dsc00221.jpg import/im030.jpg
	$(COPY) $(ISRC)/dsc00225.jpg import/im031.jpg
	mkdir -p dcim/101msdcf
	$(COPY) $(ISRC)/dsc00289.jpg dcim/101msdcf/im032.jpg
	$(COPY) $(ISRC)/dsc00248.jpg dcim/101msdcf/im033.jpg

tut1 :
	$(ALBUM) -v

tut2 :
	$(ALBUM) -v

tut3 :
	$(ALBUM) -v --medium --title "My First Album"

tut4 :
	touch info.dat
	$(ALBUM) -v --medium --title "My First Album"

tut5 :
	echo '!title My First Album' > info.dat
	echo '!medium' >> info.dat
	echo '!tag 2004/06/01' >> info.dat
	echo 'im023.jpg  Avondale House' >> info.dat
	echo 'im024.jpg  Country Park' >> info.dat
	echo 'im025.jpg  Dun an Oir' >> info.dat
	echo 'im026.jpg  Connor Pass' >> info.dat
	echo 'im027.jpg  Cill Mhailchéadair' >> info.dat
	echo 'im028.jpg  Camport Bay' >> info.dat
	echo 'im029.jpg  Moon over Clew Bay' >> info.dat
	$(ALBUM) -v

tut6 :
	$(ALBUM) -v --import import --update

tut7 :
	$(ALBUM) -v --dcim dcim/101msdcf --update

clean :
	rm -fr large medium thumbnails dcim icons import
	rm -f .cache info.dat index*html

