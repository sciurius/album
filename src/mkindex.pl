#!/usr/bin/perl -w
my $RCS_Id = '$Id$ ';

# Skeleton for Getopt::Long.

# Author          : Johan Vromans
# Created On      : Tue Sep 15 15:59:04 1992
# Last Modified By: Johan Vromans
# Last Modified On: Tue Dec 20 21:34:50 2005
# Update Count    : 62
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
my ($my_name, $my_version) = $RCS_Id =~ /: (.+).pl,v ([\d.]+)/;
# Tack '*' if it is not checked in into RCS.
$my_version .= '*' if length('$Locker$ ') > 12;

################ Command line parameters ################

use Getopt::Long 2.13;

# Command line options.
my $verbose = 0;		# verbose processing

# Development options (not shown with -help).
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

use File::Find;

@ARGV = qw(.) unless @ARGV;

my %index;

find(sub {
	 return unless $_ eq "index.html";
	 open(I, $_) or die("$File::Find::name: $!\n");
	 while ( <I>) {
	     if ( /^\s*\<title\>(.*?): Index/ ) {
		 $index{$File::Find::name} = $1;
		 return;
	     }
	 }
     }, @ARGV);

print STDOUT ("<html><title>Foto Albums</title>\n",
	      "<body bgcolor=\"#C0C0C0\">\n",
	      "<h1>Foto Albums</h1>\n",
	      "<table width='1005' border='1'>\n");
my @the_list = reverse sort(keys(%index));

my $cols = 3;

while ( @the_list % $cols ) {
    push(@the_list, "");
}

my $h = @the_list / $cols;

foreach my $i ( 0 .. $h-1 ) {
    my $index = $i;
    print STDOUT (" <tr bgcolor=\"#E0E0E0\">\n");
    my $file;
    my $title;

    foreach ( 1..$cols ) {
	$file = $the_list[$index];
	$title = $file ? $index{$file} : "";
	$file =~ s/^\.\///;
	print STDOUT ("   <td>",
		      $file ? "<a href=\"$file\">$title</a>" : "&nbsp;",
		      "</td>\n");
	$index += $h;
    }
    print STDOUT (" </tr>\n");
}
print STDOUT ("</table>\n",
	      "</body>\n",
	      "</html>\n");

exit 0;

################ Subroutines ################

sub app_options {
    my $help = 0;		# handled locally
    my $ident = 0;		# handled locally

    # Process options, if any.
    # Make sure defaults are set before returning!
    return unless @ARGV > 0;

    if ( !GetOptions(
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
    -help		this message
    -ident		show identification
    -verbose		verbose information
EndOfUsage
    exit $exit if defined $exit && $exit != 0;
}
