#!/usr/bin/perl -w
my $RCS_Id = '$Id$ ';

# Author          : Johan Vromans
# Created On      : Sun May  9 17:49:55 2004
# Last Modified By: Johan Vromans
# Last Modified On: Tue May 18 12:31:17 2004
# Update Count    : 37
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

my $full = 0;			# include header
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

use constant MONTHS => [qw(januari februari maart april mei juni juli augustus september oktober november december)];

my $TMPDIR = $ENV{TMPDIR} || $ENV{TEMP} || '/usr/tmp';

################ The Process ################

if ( $full ) {
    print STDOUT <<EOD;
!title Onuitgezocht

!mediumsize 1024
EOD
}

foreach my $dir ( @ARGV ) {
    warn("$dir: Not a directory\n"), next unless -d $dir;
    opendir(my $dh, $dir);
    my @files = grep { /^(dsc0\d+|\d{14})\.jpg/i } readdir($dh);
    closedir($dh);
    warn("$dir: ", scalar(@files), " files\n") if $verbose;

    my %f;
    foreach my $f ( @files ) {
	my $file = $f;
	my $exif = get_exif("$dir/$file");
	if ( $file =~ /^dsc/i ) {
	    my $fd = $exif->{"date/time"} || "";
	    if ( $fd =~ /(\d\d\d\d):(\d\d):(\d\d) (\d\d):(\d\d):(\d\d)/ ) {
		my $new = "$1$2$3$4$5"."00";
		while ( -e "$dir/$new.jpg" ) {
		    $new++;
		}
		$new .= ".jpg";
		unless ( rename("$dir/$file", "$dir/$new") ) {
		    warn("Rename $file -> $new: $!\n");
		    next;
		}
		$file = $new;
	    }
	    else {
		warn("$file: Missing or unparsable file date [$fd]\n");
	    }
	}
	if ( $exif->{orientation} && $exif->{orientation} =~ /^rotate (\d+)$/i  ) {
	    $f{$file} = "-O:" . int($1/90) . " ";
	}
	else {
	    $f{$file} = "-O:0 ";
	}
	if ( $exif->{comment} ) {
	    $f{$file} .= $exif->{comment} . " ";
	}
    }


    my $date = "";
    foreach my $file ( sort(keys(%f) ) ) {
	my ($y,$m,$d) = $file =~ /^(\d{4})(\d\d)(\d\d)\d{4,6}\.jpg/i;
	if ( "$y$m$d" ne $date ) {
	    $date = "$y$m$d";
	    print "\n!tag ", 0+$d, " ",
	      MONTHS->[$m-1], "\n";
	}
	print "$file $f{$file}\n";
    }
}


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
    \%h;
}

################ Command Line Options ################

use Getopt::Long;

sub app_options {

    GetOptions(ident	   => \&app_ident,
	       verbose	   => \$verbose,
	       # application specific options go here
	       full	   => \$full,
	       # development options
	       test	   => \$test,
	       trace	   => \$trace,
	       debug	   => \$debug)
      or Getopt::Long::HelpMessage(2);
}

sub app_ident {
    print STDOUT ("This is $my_package [$my_name $my_version]\n");
}

__END__

=head1 NAME

mkdata - create data info for images

=head1 SYNOPSIS

mkdata [options] [dir ...]

Options:

   --full		include data preamble
   --ident		show identification
   --help		brief help message
   --verbose		verbose information

=head1 OPTIONS

=over 8

=item B<--full>

Include data preamble.

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

=head1 AUTHOR

Johan Vromans <jvromans@squirrel.nl>

=head1 COPYRIGHT

This programs is Copyright 2004, Squirrel Consultancy.

This program is free software; you can redistribute it and/or modify
it under the terms of the Perl Artistic License or the GNU General
Public License as published by the Free Software Foundation; either
version 2 of the License, or (at your option) any later version.

=cut
