#!/usr/bin/perl -w
my $RCS_Id = '$Id$ ';

# Author          : Johan Vromans
# Created On      : Tue Sep 15 15:59:04 2002
# Last Modified By: Johan Vromans
# Last Modified On: Wed Jun  9 19:39:36 2004
# Update Count    : 1032
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

################ The Process ################

# Storage for image info. Will be cached.
my $info;

# Load cached info, if possible.
load_cache();

foreach my $f ( @{$info->entries} ) {
    my $ii = $info->entry($f);
    my $orig;
    next unless $orig = $ii->orig_name;
    doit($orig, "large/$f");
}

exit 0;

sub doit {
    my ($old, $new) = @_;
    print STDERR ($old . " -> " . $new . "\n");
    unless ( differ($old, $new) ) {
	unlink($new) or die("unlink($new): $!\n");
	link($old, $new) or die("link($old,$new): $!\n");
    }
    else {
	warn("differ: $old $new\n");
    }

}

sub differ {
    # Perl version of the 'cmp' program.
    # Returns 1 if the files differ, 0 if the contents are equal.
    my ($old, $new) = @_;
    unless ( open (F1, $old) ) {
	print STDERR ("$old: $!\n");
	return 1;
    }
    unless ( open (F2, $new) ) {
	print STDERR ("$new: $!\n");
	return 1;
    }
    my ($buf1, $buf2);
    my ($len1, $len2);
    binmode(F1);
    binmode(F2);
    while ( 1 ) {
	$len1 = sysread (F1, $buf1, 10240);
	$len2 = sysread (F2, $buf2, 10240);
	return 0 if $len1 == $len2 && $len1 == 0;
	return 1 if $len1 != $len2 || ( $len1 && $buf1 ne $buf2 );
    }
}


#### Persistent info (cache) helpers.

sub load_cache {
    $info = new ImageInfo;
    $info->load(".cache");
}

sub update_cache {
    $info->store(".cache");
}

#### Miscellaneous.

sub squote {
    my ($t) = @_;
    $t =~ s/([\\\'])/\\$1/g;
    "'".$t."'";
}

################ Subroutines ################

sub app_options {
    my $help = 0;		# handled locally
    my $ident = 0;		# handled locally

    # Process options, if any.
    # Make sure defaults are set before returning!
    return unless @ARGV > 0;

    if ( !GetOptions(
		     'trace'	=> \$trace,
		     'help|?'	=> \$help,
		     'debug'	=> \$debug,
		    )
	 or $help
       )
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
Usage: $0 [options] [ directory ]
    --help		this message
    --ident		show identification
    --verbose		verbose information
EndOfUsage
    exit $exit if defined $exit && $exit != 0;
}

################ Modules ################

package ImageInfo;

sub new {
    my ($pkg, $file) = @_;
    $pkg = ref($pkg) || $pkg;
    my $self = bless({}, $pkg);
    $self->load($file) if defined($file);
    $self;
}

sub load {
    my ($self, $file) = @_;
    our $info;
    $info = undef;
    require $file;

    foreach my $f ( keys(%$info) ) {
	my $entry = $info->{$f};
	bless $entry, "ImageInfo::Entry"
	  unless UNIVERSAL::isa($entry, "ImageInfo::Entry");
	$self->{info}->{$f} = $entry;
    }
}

sub store {
    my ($self, $file) = @_;
    my $info = $self->{info};
    use Data::Dumper;
    $Data::Dumper::Indent = 1;
    $Data::Dumper::Sortkeys = 1;
    my $cache = do { local *C; *C };
    open($cache, ">$file")
      and print $cache (Data::Dumper->Dump([$info],[qw(info)]), "\n1;\n")
	and close($cache);
}

sub entry {
    my ($self, $file, $entry) = @_;
    $file =~ s;^\./;;;
    if ( defined $entry ) {
	$self->{info}->{$file} = $entry;
    }
    else {
	$entry = $self->{info}->{$file};
    }
    $entry;
}

sub entries {
    my ($self) = @_;
    [ sort(keys(%{$self->{info}})) ];
}

use Class::Struct "ImageInfo::Entry" =>
  [ large_size	 => '$',
    medium_size	 => '$',
    width	 => '$',
    height	 => '$',
    exif	 => '$',
    orig_name	 => '$',
  ];

sub ImageInfo::Entry::tostr {
    my ($self) = @_;
    "[" . join(" ",
	       $self->large_size,
	       $self->medium_size || 0,
	       $self->width,
	       $self->height,
	      ) . "]";
}

