/* Quick & Dirty program to fetch the first image from an MPEG file.
 *
 * Requires libmpeg2 (http:/libmpeg2.sourceforge.net).
 */

#include <stdio.h>
#include <stdlib.h>
#include <inttypes.h>
#include <errno.h>

#include "mpeg2.h"
#include "mpeg2convert.h"

#define BUFFER_SIZE 4096

FILE * ppmfile;

static void save_ppm(int width, int height, uint8_t * buf, int num) {
  fprintf(ppmfile, "P6\n%d %d\n255\n", width, height);
  fwrite(buf, 3 * width, height, ppmfile);
  fclose(ppmfile);
}

static struct fbuf_s {
  uint8_t * rgb[3];
  int used;
} fbuf[3];

static struct fbuf_s * get_fbuf(void) {
  int i;

  for (i = 0; i < 3; i++)
    if (!fbuf[i].used) {
      fbuf[i].used = 1;
      return fbuf + i;
    }
  fprintf(stderr, "Could not find a free fbuf.\n");
  exit(1);
}

static void first_frame_from_mpeg(FILE * mpgfile) {
  uint8_t buffer[BUFFER_SIZE];
  mpeg2dec_t * decoder;
  const mpeg2_info_t * info;
  mpeg2_state_t state;
  size_t size;
  int framenum = 0;
  int pixels;
  int i;
  struct fbuf_s * current_fbuf;

  decoder = mpeg2_init();
  if (decoder == NULL) {
    fprintf(stderr, "Could not allocate a decoder object.\n");
    exit(1);
  }
  info = mpeg2_info(decoder);

  size = (size_t)-1;
  do {
    state = mpeg2_parse(decoder);
    switch(state) {
    case STATE_BUFFER:
      size = fread(buffer, 1, BUFFER_SIZE, mpgfile);
      mpeg2_buffer(decoder, buffer, buffer + size);
      break;
    case STATE_SEQUENCE:
      mpeg2_convert(decoder, mpeg2convert_rgb24, NULL);
      mpeg2_custom_fbuf(decoder, 1);
      pixels = info->sequence->width * info->sequence->height;
      for (i = 0; i < 3; i++) {
	fbuf[i].rgb[0] = (uint8_t *) malloc(3 * pixels);
	fbuf[i].rgb[1] = fbuf[i].rgb[2] = NULL;
	if (!fbuf[i].rgb[0]) {
	  fprintf(stderr, "Could not allocate an output buffer.\n");
	  exit(1);
	}
	fbuf[i].used = 0;
      }
      for (i = 0; i < 2; i++) {
	current_fbuf = get_fbuf();
	mpeg2_set_buf(decoder, current_fbuf->rgb, current_fbuf);
      }
      break;
    case STATE_PICTURE:
      current_fbuf = get_fbuf();
      mpeg2_set_buf(decoder, current_fbuf->rgb, current_fbuf);
      break;
    case STATE_SLICE:
    case STATE_END:
    case STATE_INVALID_END:
      if (info->display_fbuf) {
	save_ppm(info->sequence->width, info->sequence->height,
		  info->display_fbuf->buf[0], framenum++);
	size = 0;		/* terminate */
      }
      if (info->discard_fbuf)
	((struct fbuf_s *)info->discard_fbuf->id)->used = 0;
      if (state != STATE_SLICE)
	for (i = 0; i < 3; i++)
	  free(fbuf[i].rgb[0]);
      break;
    default:
      break;
    }
  } while(size);
  
  mpeg2_close(decoder);
}

int main(int argc, char ** argv) {
  FILE * mpgfile;

  if (argc > 1) {
    mpgfile = fopen(argv[1], "rb");
    if (!mpgfile) {
      fprintf(stderr, "Could not open file \"%s\" (errno = %d)\n",
	       argv[1], errno);
      exit(1);
    }
    if (argc > 2) {
      ppmfile = fopen(argv[2], "wb");
      if (!ppmfile) {
	fprintf(stderr, "Could not create file \"%s\" (errno = %d)\n",
		 argv[2], errno);
	exit(1);
      }
    }
  }
  else
    mpgfile = stdin;

  if (ppmfile == NULL) {
    ppmfile = fopen("out.ppm", "wb");
    if (!ppmfile) {
      fprintf(stderr, "Could not create file \"out.ppm\" (errno = %d)\n",
	       errno);
      exit(1);
    }
  }

  first_frame_from_mpeg(mpgfile);

  return 0;
}
