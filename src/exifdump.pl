#!/usr/bin/perl -w
# exifdump.pl -- dump EXIF info
# RCS Info        : $Id$
# Author          : Johan Vromans
# Created On      : Fri Jun 11 11:24:27 2004
# Last Modified By: Johan Vromans
# Last Modified On: Wed Jul 21 14:25:17 2004
# Update Count    : 2
# Status          : Unknown, Use with caution!

use strict;
use warnings;
use Image::Info qw(image_info);
use Data::Hexify;

foreach my $img ( @ARGV ) {
    my $ii = image_info($img);
    print("$img:\n") if @ARGV > 1;
    foreach my $key ( sort(keys(%$ii)) ) {
	my $val = $i->{$key};
	if ( $val =~ /[\001-\037\177-\377]/ && $key !~ /error/ ) {
	    print($key, " ->\n", Hexify($val));
	    next;
	}
	$val =~ s/\000//g;
	if ( ref($val) ) {
	    if ( UNIVERSAL::isa($val, "Image::TIFF::Rational") ) {
		print($key, " -> [", join("/", @{$val}), "] -> ",
		      $val->as_float(), "\n");
		next;
	    }
	    print($key, " -> ", deref(@{$val}), "\n");
	    next;
	}
	print($key, " -> ", $val, "\n");
    }
}

sub deref {
   my @args;
   if ( ref($_[0]) eq 'ARRAY' ) {
       foreach my $ref ( @_ ) {
	   push(@args, deref(@{$ref}));
       }
   }
   else {
       @args = @_;
   }
   '[' . join(',', @args) . ']';
}
