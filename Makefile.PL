# Makefile.PL -- Makefile for album	-*-perl-*-
# Author          : Johan Vromans
# Created On      : Fri Jul  9 15:45:48 2004
# Last Modified By: Johan Vromans
# Last Modified On: Fri Jul  9 22:11:01 2004
# Update Count    : 15
# Status          : Experimental

use strict;
use ExtUtils::MakeMaker;
use Config;

my @scripts = qw (album);
my $usrbin = "/usr/bin";
my $installscript = $Config{installscript};

print STDERR <<EOD unless $installscript eq $usrbin;

WARNING: This Makefile will install user accessible scripts.
The location for these scripts is $installscript.
You may consider to pass INSTALLSCRIPT=$usrbin (or some other
convenient location) to "make install".
EOD

print STDERR <<EOD;

This program requires some helper programs.

  jpegtrans   will be used to rotate JPEG files loslessly.
	      If missing, JPEG files will be rotated with loss
	      of information.
EOD
checkexec("jpegtran");

print STDERR <<EOD;

  mencoder    is needed to manipulate MPEG files
EOD
checkexec("mencoder");

print STDERR <<EOD;

  mplayer     is needed extract audio from VOICE files
EOD
checkexec("mplayer");

print STDERR <<EOD;

  mpeg2decode is used to extract a still image from MPEG files.
	      For best performance, install the mpegstill program that
	      comes with this kit.
EOD
checkexec("mpegstill") || checkexec("mpeg2decode");

print STDERR ("\n");

WriteMakefile
  (
   NAME         => "$scripts[0]",
   VERSION_FROM => "script/$scripts[0]",
   ($] >= 5.005) ?
   ( AUTHOR	=> 'Johan Vromans (jvromans@squirrel.nl)',
     ABSTRACT	=> 'Creates HTML based photo albums' ) : (),
   PREREQ_PM	=> { 'Getopt::Long' => 2.1,
		     'Image::Info' => 1.16,
		     'Image::Magick' => 6,
		   },
   EXE_FILES    => [ map { "script/$_" } @scripts ],
 );

sub checkexec {
    my ($exec) = @_;
    my $path = findbin($exec);
    if ( $path ) {
	print STDERR ("\t      Good, found $path\n");
	return 1;
    }
    print STDERR ("\t      Hmm. Couldn't find $exec in PATH\n");
    0;
}

sub findbin {
    my ($bin) = @_;
    foreach ( split(":", $ENV{PATH}) ) {
	return "$_/$bin" if -x "$_/$bin";
    }
    undef;
}
