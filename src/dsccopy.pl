#!/usr/bin/perl -w
my $RCS_Id = '$Id$ ';

# Author          : Johan Vromans
# Created On      : Fri May 28 22:39:57 2004
# Last Modified By: Johan Vromans
# Last Modified On: Fri May 28 23:20:06 2004
# Update Count    : 29
# Status          : Unknown, Use with caution!

################ Common stuff ################

use strict;

# Package name.
my $my_package = 'Sciurix';
# Program name and version.
my ($my_name, $my_version) = $RCS_Id =~ /: (.+).pl,v ([\d.]+)/;
# Tack '*' if it is not checked in into RCS.
$my_version .= '*' if length('$Locker$ ') > 12;

################ Command line parameters ################

my $info;			# write info
  my $full = 0;			# include header
  my $title = "Unsorted";	# title
  my $mediumsize = 0;		# mediumsize
my $verbose = 0;		# more verbosity

# Development options (not shown with --help).
my $debug = 0;			# debugging
my $trace = 0;			# trace (show process)
my $test = 0;			# test mode.

# Process command line options.
app_options();

# Post-processing.
$trace |= ($debug || $test);

################ Presets ################

use constant MONTHS => [qw(januari februari maart april
			   mei juni juli augustus
			   september oktober november december)];

my $TMPDIR = $ENV{TMPDIR} || $ENV{TEMP} || '/usr/tmp';

################ The Process ################

use File::Copy;
use Time::Local;

my $inf = do { local *F; *F };
if ( $info ) {
    open($inf, ">$info") || die("$info: $!\n");
    if ( $full ) {
	print $inf ("!title $title\n\n");
	print $inf ("!mediumsize $mediumsize\n\n") if $mediumsize;
    }
}

my $pdate = qr/(\d{4})(\d\d)(\d\d)\d{4}(?:\d\d|\w)/;

my ($srcdir, $dstdir) = @ARGV;

opendir(my $dh, $srcdir);
my @files = grep { !/^\./ } readdir($dh);
closedir($dh);
warn("$srcdir: ", scalar(@files), " files\n") if $verbose;

# Gather the info for each file.
my %info;
foreach my $f ( @files ) {
    my $file = $f;		# file name for now
    my $exif = get_exif("$srcdir/$file");

    # Rename files from DSC.
    my $needcopy = 1;
    if ( $exif && $file =~ /^(dsc|mov)\d+\.(\w+)/i ) {
	my $ext = $2;
	my $fd = $exif->{"date/time"} || "";
	if ( $fd =~ /(\d\d\d\d):(\d\d):(\d\d) (\d\d):(\d\d):(\d\d)/ ) {
	    my $time = timelocal($6,$5,$4,$3,$2-1,$1);
	    # YYYYMMDDhhmmSS (SS = sequence, not seconds).
	    # Note: jhead uses YYYYMMDDhhssX, where X is empty, a, b, ...
	    my $new = "$1$2$3$4$5"."00";
	    while ( -e "$dstdir/$new.$ext" ) {
		$new++;
	    }
	    $new .= ".$ext";
	    print("Copy $srcdir/$file to $dstdir/$new\n") if $verbose;
	    unless ( copy("$srcdir/$file", "$dstdir/$new") ) {
		warn("Copy $srcdir/$file -> $dstdir/$new: $!\n");
		next;
	    }
	    $file = $new;
	    utime($time, $time, "$dstdir/$file");
	    $needcopy = 0;
	}
	else {
	    warn("$file: Missing or unparsable file date [$fd]\n");
	}
    }
    if ( $needcopy ) {
	my $time = (stat("$srcdir/$file"))[9];
	print("Copy $srcdir/$file to $dstdir/$file\n") if $verbose;
	unless ( copy("$srcdir/$file", "$dstdir/$file") ) {
	    warn("Copy $srcdir/$file -> $dstdir: $!\n");
	    next;
	}
	utime($time, $time, "$dstdir/$file");
    }
    # Handle orientation.
    # Note: it is better to have jhead handle this since it clears
    # the rotation info after rotation.
    if ( $exif && ($exif->{orientation}||"") =~ /^rotate (\d+)$/i  ) {
	system("jhead -autorot $dstdir/$file >&2");
	$exif = get_exif("$dstdir/$file");
    }
    if ( $exif && ($exif->{orientation}||"") =~ /^rotate (\d+)$/i  ) {
	$info{$file} = "-O:" . int($1/90) . " ";
    }
    else {
	$info{$file} = " ";
    }

    # Add JPEG comment ad description.
    if ( $exif && $exif->{comment} ) {
	$info{$file} .= $exif->{comment} . " ";
    }
}

# Create the list, interspersed with !tag commands to set the date.
my $date = "";
foreach my $file ( sort(keys(%info) ) ) {
    my ($y,$m,$d) = $file =~ /^$pdate\./io;
    ($y,$m,$d) = (0,0,0) unless defined($y);
    if ( defined($y) && "$y$m$d" ne $date ) {
	$date = "$y$m$d";
	if ( $date ne "000" ) {
	    print $inf ("\n!tag ", 0+$d, " ",
			MONTHS->[$m-1], "\n");
	}
	else {
	    print $inf ("\n!tag\n");
	}
    }
    print $inf ("$file $info{$file}\n");
}

close($inf);
exit 0;

################ Subroutines ################

sub get_exif {
    my ($file) = @_;
    use 5.008;
    open(my $p, "-|", "jhead", $file) or die("$file: $!\n");
    my %h;
    while ( <$p> ) {
	s/\s+:\s+/: /;
	$h{lc($1)} = $2 if /^(.*?): (.*)/;
    }
    close($p) or die("$file: $!\n");
    $h{exposure} ||= "manual";
    \%h;
}

################ Command Line Options ################

use Getopt::Long;

sub app_options {

    GetOptions(ident	   => \&app_ident,
	       verbose	   => \$verbose,
	       # application specific options go here
	       'info=s'    => \$info,
	       full	   => \$full,
	       "title=s"   => sub { $title = $_[1]; $full++; },
	       "mediumsize:i" => sub { $mediumsize = $_[1]||1024; $full++; },
	       # development options
	       test	   => \$test,
	       trace	   => \$trace,
	       debug	   => \$debug)
      && @ARGV == 2 && -d $ARGV[0] && -d $ARGV[1]
      or Getopt::Long::HelpMessage(2);
}

sub app_ident {
    print STDOUT ("This is $my_package [$my_name $my_version]\n");
}

__END__

=head1 NAME

dsccopy - copy images from Digital Still Camera

=head1 SYNOPSIS

dsccopy [options] srcdir dstdir

Options:

   --full		include data preamble
   --title XXX		title, implies --full
   --mediumsize [ NNN ] medium images, implies --full, size defaults to 1024
   --ident		show identification
   --help		brief help message
   --verbose		verbose information

=head1 OPTIONS

=over 8

=item B<--full>

Include data preamble.

=item B<--title> I<XXX>

Album title. Implies --full.

=item B<--mediumsize> [ I<NNN> ]

Include medium size images. Size defaults to 1024. Implies --full.

=item B<--verbose>

More verbose information.

=item B<--version>

Print a version identification to standard output and exits.

=item B<--help>

Print a brief help message to standard output and exits.

=item B<--ident>

Prints a program identification.

=item I<file>

Input file(s).

=back

=head1 DESCRIPTION

B<This program> will read the given input directory(ies) and write to
standard output a piece of data suitable for processing with the album
program.

Also, it will rename files from digital still camera (DSC0nnn.JPG) to
a more convenient YYYYMMDDHHMM.jpg using the EXIF info.

=head1 AUTHOR

Johan Vromans <jvromans@squirrel.nl>

=head1 COPYRIGHT

This programs is Copyright 2004, Squirrel Consultancy.

This program is free software; you can redistribute it and/or modify
it under the terms of the Perl Artistic License or the GNU General
Public License as published by the Free Software Foundation; either
version 2 of the License, or (at your option) any later version.

=cut
