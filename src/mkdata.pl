#!/usr/bin/perl -w
my $RCS_Id = '$Id$ ';

# Author          : Johan Vromans
# Created On      : Sun May  9 17:49:55 2004
# Last Modified By: Johan Vromans
# Last Modified On: Sun May  9 17:50:47 2004
# Update Count    : 3
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

my $TMPDIR = $ENV{TMPDIR} || $ENV{TEMP} || '/usr/tmp';

################ The Process ################

foreach my $dir ( @ARGV ) {
    warn("$dir: Not a directory\n"), next unless -d $dir;
    opendir(my $dh, $dir);
    my @files = grep { /^\d{12}\.jpg/i } readdir($dh);
    closedir($dh);
    warn("$dir: ", scalar(@files), " files\n") if $verbose;
    my $date = "";
    foreach my $file ( sort(@files ) ) {
	my ($y,$m,$d) = $file =~ /^(\d{4})(\d\d)(\d\d)\d{4}\.jpg/i;
	if ( "$y$m$d" ne $date ) {
	    $date = "$y$m$d";
	    print "\n!tag ", 0+$d, " ",
	      qw(januari februari maart april mei juni juli augustus september oktober november december)[$m-1], "\n";
	}
	print "$file -O:0 \n";
    }
}


exit 0;

################ Subroutines ################

################ Command Line Options ################

use Getopt::Long;

sub app_options {

    GetOptions(ident	   => \&app_ident,
	       verbose	   => \$verbose,
	       # application specific options go here

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

   --ident		show identification
   --help		brief help message
   --verbose		verbose information

=head1 OPTIONS

=over 8

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
