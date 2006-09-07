#!/usr/bin/perl -w
# exifdump.pl -- dump EXIF info
# RCS Info        : $Id$
# Author          : Johan Vromans
# Created On      : Fri Jun 11 11:24:27 2004
# Last Modified By: Johan Vromans
# Last Modified On: Fri Jun 24 16:27:38 2005
# Update Count    : 6
# Status          : Unknown, Use with caution!

use strict;
use warnings;
use Image::Info qw(image_info);
use Data::Hexify;

foreach my $img ( @ARGV ) {
    my $ii = image_info($img);
    print("$img:\n") if @ARGV > 1;
    foreach my $key ( sort(keys(%$ii)) ) {
	my $val = $ii->{$key};
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
	    if ( UNIVERSAL::isa($val, 'ARRAY') ) {
		print($key, " -> ", deref(@{$val}), "\n");
		next;
	    }
	    print($key, " => ", ref($val), "\n");
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
