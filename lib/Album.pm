package Album;

( $VERSION ) = '$Revision$ ' =~ /\$Revision:\s+([^\s]+)/;

# NOTE: This is a documentation-only module.

use strict;

=head1 NAME

Album - create and maintain HTML based photo albums

=head1 SYNOPSIS

A photo album consists of a number of (large) pictures, small thumbnail
images, and index pages. Optionally, medium sized images can be
generated as well. The album will be organised as follows:

  index.html       first or only index page
  indexN.html      subsequent index pages (N = 1, 2, ...)
  icons/           directory with navigation icons
  large/           original (large) images, with HTML pages
  medium/          optional medium sized images, with HTML pages
  thumbnail/       thumbnail images

Each image can be labeled with a description, a tag (applies to a
group of images, e.g. a date), the image name, and some
characteristics (size and dimensions).

Images can be handled 'in situ', or imported from e.g. a CD-ROM or
digital camera. Optionally, EXIF information from digital camera files
can be taken into account.

=head1 DESCRIPTION

For a description how to use the program, see L<Album::Tutorial>.

=head1 AUTHOR AND CREDITS

Johan Vromans (jvromans@squirrel.nl) wrote this module.

Web site: http://www.squirrel.nl/people/jvromans/Album/index.html

=head1 COPYRIGHT AND DISCLAIMER

This program is Copyright 2004 by Squirrel Consultancy. All
rights reserved.

This program is free software; you can redistribute it and/or modify
it under the terms of either: a) the GNU General Public License as
published by the Free Software Foundation; either version 1, or (at
your option) any later version, or b) the "Artistic License" which
comes with Perl.

This program is distributed in the hope that it will be useful, but
WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See either the
GNU General Public License or the Artistic License for more details.

=cut

1;

# $Id$
