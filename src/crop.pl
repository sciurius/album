#!/usr/bin/perl -w

# crop.pl -- calculate cropping for some familiar print formats
# RCS Info        : $Id: crop.pl,v 1.1 2004/06/27 09:43:09 jv Exp $
# Author          : Johan Vromans
# Created On      : Sat Jun 26 10:30:58 2004
# Last Modified By: Johan Vromans
# Last Modified On: Sun Jun 27 11:42:36 2004
# Update Count    : 14
# Status          : Unknown, Use with caution!

use strict;
use constant EPS => 1e-2;

printf(" print   image                        ratio   crop\n");

while ( <DATA> ) {
    my ($h, $w) = /(\d+)x(\d+)/;
    my $r1 = $w/$h;
    my ($ph, $pw) = (1944, 2592);
    my $r2 = $pw/$ph;
    my ($ah, $aw) = ($ph, $pw);

    my $crop = 'w';
    # Adjust width.
    $aw = int($ah * $r1);
    if ( $aw == $pw ) {
	$crop = '-';
    }
    elsif ( $aw > $pw ) {
	# Adjust height.
	$aw = $pw;
	$ah = int($aw / $r1);
	$crop = 'h';
	if ( $ah > $ph ) {
	    $ah = $ph;
	    $aw = int($ah * $r1);
	    $crop = 'w';
	}
    }

    my $r = $aw/$ah;
    die("${h}x${w}: $r1 <> $r\n")
      unless abs($r1 - $r) < EPS;

    printf("%3dx%2d   %4dx%4d  -%s->  %4dx%4d   %-5s   %s\n",
	   $h, $w, $ph, $pw, $crop, $ah, $aw, rat($r),
	   ($ph == $ah ?
	    (($pw == $aw) ? "" : (($aw-$pw)."w")) :
	    (($ph == $ah) ? "" : (($ah-$ph)."h")))
	  );
}

sub rat {
    my ($r) = @_;
    for ( 2..19 ) {
	my $v = $r*$_;
	if ( abs($v - int($v)) < EPS ) {
	    return $_.":".int($v);
	}
    }
    return sprintf("%.3f", $r);
}

__END__
9x13
10x15
13x18
15x20
20x30
30x45
50x60
