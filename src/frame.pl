#!/usr/bin/perl -w

# Author          : Johan Vromans
# Created On      : Tue Sep 15 15:59:04 1992
# Last Modified By: Johan Vromans
# Last Modified On: Mon Aug 27 10:22:41 2018
# Update Count    : 162
# Status          : Unknown, Use with caution!

################ Common stuff ################

use strict;

# Package or program libraries, if appropriate.
# $LIBDIR = $ENV{'LIBDIR'} || '/usr/local/lib/sample';
# use lib qw($LIBDIR);
# require 'common.pl';

# Package name.
my $my_package = 'Sciurix';
# Program name and version.
my ($my_name, $my_version) = qw( frame 1.2 );

################ Command line parameters ################

use Getopt::Long 2.13;

# Command line options.
my $theyear = 0;
my $thisyear = 1900 + (localtime(time))[5];
my $cprcolor = "grey";
my $verbose = 0;		# verbose processing
my $d_medium = 500;
my $d_small = 138;
my $d_frame = 10;
my $strat = "normal";

# Development options (not shown with -help).
my $debug = 0;			# debugging
my $trace = 0;			# trace (show process)
my $test = 0;			# test mode.

# Process command line options.
app_options();

if ( $d_medium ) {
    $d_medium -= 2 * $d_frame;
}
if ( $d_small ) {
    $d_small -= 2 * 0.6 * $d_frame;
}

# Post-processing.
$trace |= ($debug || $test);

################ Presets ################

my $TMPDIR = $ENV{TMPDIR} || $ENV{TEMP} || '/usr/tmp';

################ The Process ################

use File::Basename;
use Image::Magick;

my $year;

my $cpr = "Copyright YEAR Johan Vromans. All rights reserved.\n".
  "Any form of reproduction is prohibited without prior written permission\n".
  "of the copyright holder.\n".
  "http://johan.vromans.org";

my $olay; # = new Image("/home/jv/wrk/cpr-black.xcf");

foreach my $file ( @ARGV ) {
    $file =~ s;\\;/;g;
    my $dir = dirname($file);
    my $med = $dir;
    my $sml = $dir;
    my $base = basename($file);
    $base =~ s/\.[^.]+$//;

    if ( $dir =~ m;^(.*/)?large$; ) {
	$med = ($1||"") . "medium/$base.jpg";
	$sml = ($1||"") . "index/$base.jpg";
    }
    else {
	$med = $dir . "/" . $base . "-med.jpg";
	$sml = $dir . "/" . $base . "-sml.jpg";
    }

    if ( $theyear ) {
	$year = $theyear;
    }
    elsif ( $base =~/^(\d\d\d\d)/ && $1 > 1900 && $1 < 2099 ) {
	$year = $1;
    }
    else {
	$year = $thisyear;
    }
    $cpr =~ s/YEAR/$year/g;

    my $im = new Image($file, strategy => $strat);
    if ( $d_medium ) {
	warn ("$file -> $med\n") if $verbose;
	$im->resize($d_medium)->clone->overlay($olay)->frame($d_frame)->write($med);
    }
    if ( $d_small ) {
	warn ("$file -> $sml\n") if $verbose;
	$im->resize($d_small)->frame(int($d_frame*0.6))->write($sml);
    }
}

exit 0;

################ Subroutines ################

package Image;

sub new {
    my ($pkg, $file, %props) = (@_);
    my $image = new Image::Magick;
    my $t = $image->Read($file);
    warn("read($file): $t\n") if $t;
    $image->Profile(name => "*", profile => '');
    $image->Comment($cpr);
    *resize = \&normal_resize;
    if ( $props{strategy} eq "alt" ) {
	*resize = \&alt_resize;
    }
    bless \$image;
}

sub normal_resize {
    my ($self, $n) = @_;
    return $self if $n < 0;

    # height may not exceed n.
    # width may not exceed 4/3 x n.

    my ($origx, $origy) = $$self->Get(qw(width height));
    my $ratioy = $origy / $n;
    my $ratiox = $origx / ((4 * $n) / 3);
    my $ratio = $ratiox > $ratioy ? $ratiox : $ratioy;
    warn("resize: width => ", $origx/$ratio, " height => ", $origy/$ratio, "\n")
      if $trace;
    my $t = $$self->Resize(width => $origx/$ratio, height => $origy/$ratio);
    warn("resize: $t\n") if $t;
    $self;
}

sub alt_resize {
    my ($self, $n) = @_;
    return $self if $n < 0;

    # max(width, height) may not exceed n.
    my ($origx, $origy) = $$self->Get(qw(width height));
    my $ratio = $origx > $origy ? $origx / $n : $origy / $n;
    warn("resize: width => ", $origx/$ratio, " height => ", $origy/$ratio, "\n")
      if $trace;
    my $t = $$self->Resize(width => $origx/$ratio, height => $origy/$ratio);
    warn("resize: $t\n") if $t;
    $self;
}

sub clone {
    my ($self) = @_;
    my $new = $$self->Clone();
    bless \$new;
}

sub frame {
    my ($self, $sz) = @_;
    return $self if defined($sz) && !$sz;
    $sz ||= 10;
    my $is = int($sz/2);
    warn("frame: width => $sz, height => $sz, inner => $is, outer => $is\n")
      if $trace;
    $$self->Frame(width => $sz, height => $sz, inner => $is, outer => $is);
    $self;
}

sub overlay {
    my ($self, $img) = @_;
    my ($origx, $origy) = $$self->Get(qw(width height));
    my $color = lc($cprcolor);
    my $align = "right";
    my @aa = (text => " \xa9 $year Johan Vromans ",
	      font => "Helvetica",
	      pointsize => 14,
	      antialias => 'true',
	      'y' => $origy - 4,
	      encoding => 'ISO-8859-1');
    if ( $color =~ /^([lr]):(.*)$/ ) {
	if ( $1 eq 'l' ) {
	    push(@aa, x => 0, align => 'left');
	}
	else {
	    push(@aa, x => $origx, align => 'right');
	}
	$color = $2;
    }
    else {
	push(@aa, x => $origx, align => 'right');
    }
    push(@aa, stroke => $color);
    warn("annotate: @aa\n") if $trace;
    my $t = $$self->Annotate(@aa);
    warn("annotate: $t\n") if $t;
    $self;
}
sub write {
    my ($self, $file) = @_;
    my $t = $$self->Write($file);
    warn("write: $t\n") if $t;
    $self;
}

package main;

################ Subroutines ################

sub app_options {
    my $help = 0;		# handled locally
    my $ident = 0;		# handled locally

    # Process options, if any.
    # Make sure defaults are set before returning!
    return unless @ARGV > 0;

    if ( !GetOptions(
		     'year=i'   => \$theyear,
		     'anncolor=s' => \$cprcolor,
		     'small=i'  => \$d_small,
		     'medium=i' => \$d_medium,
		     'frame=i'  => \$d_frame,
		     'strategy=s' => \$strat,
		     'ident'	=> \$ident,
		     'verbose'	=> \$verbose,
		     'trace'	=> \$trace,
		     'help|?'	=> \$help,
		     'debug'	=> \$debug,
		    ) or $help )
    {
	app_usage(2);
    }
    app_ident() if $ident;
}

sub app_ident {
    print STDERR ("This is $my_package [$my_name $my_version]\n");
}

sub app_usage {
    my ($exit) = @_;
    app_ident();
    print STDERR <<EndOfUsage;
Usage: $0 [options] [file ...]
    --year=YYYY         year (for copyright)
    --anncolor=NNNN     colour for annotation
    --small=NN          max dim of small image
    --medium=NN         max dim of medium image
    --frame=N           width of frame (small gets 60%)
    --strategy=XXX	resize strategty to use (normal / alt)
    --help		this message
    --ident		show identification
    --verbose		verbose information
EndOfUsage
    exit $exit if defined $exit && $exit != 0;
}
