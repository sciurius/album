#!/usr/bin/perl -w
my $RCS_Id = '$Id$ ';

# Author          : Johan Vromans
# Created On      : Tue Sep 15 15:59:04 2002
# Last Modified By: Johan Vromans
# Last Modified On: Fri Sep 17 20:00:42 2004
# Update Count    : 2275
# Status          : Unknown, Use with caution!

################ Common stuff ################

$VERSION = 0.09;

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

my $creator = "Created with <a href=\"http://search.cpan.org/~jv/Album/\">Album</a> $::VERSION";

################ Command line parameters ################

use Getopt::Long 2.13;

# Command line options.
my $import_exif = 0;
my $import_dir;
my $update = 0;			# add new from large/import
my $dest_dir = ".";
my $info_file;
my $linkthem = 1;		# link orig to large, if possible
my $clobber = 0;
my $mediumonly = 0;		# only medium size (for web export)
my $verbose = 1;		# verbose processing

# These are left undefined, for set_defaults. Note: our, not my.
our $index_columns;
our $index_rows;
our $thumb;
our $medium;			# medium size, between large and small
our $album_title;
our $caption;
our $datefmt;
our $icon;

# These are not command line options.
my $journal;			# create journal

# Development options (not shown with -help).
my $debug = 0;			# debugging
my $trace = 0;			# trace (show process)
my $test = 0;			# test mode.

# Process command line options.
app_options();

# Post-processing.
$trace |= ($debug || $test);
$dest_dir =~ s;^\./;;;
$import_dir =~ s;^\./;; if $import_dir;

################ Presets ################

use constant DEFAULTS => { info       => "info.dat",
			   title      => "Photo Album",
			   medium     => 0,
			   mediumsize => 915,
			   thumbsize  => 200,
			   indexrows  => 3,
			   indexcols  => 4,
			   caption    => "fct",
			   captionmin => "f",
			   dateformat => '%F',
			   icon	      => 0,
			 };

my $TMPDIR = $ENV{TMPDIR} || $ENV{TEMP} || '/usr/tmp';

my $WHITE = "#FFFFFF";
my $BLACK = "#000000";
my $RED   = "#FF0000";
my $LGREY = "#E0E0E0";
my $MGREY = "#D0D0D0";
my $DGREY = "#C0C0C0";

my $fontfam = "font-family: Verdana, Arial, Helvetica";
my $css = <<EOD;
body  { font-size:  80%; $fontfam; }
td    { font-size:  80%; $fontfam; }
p.hd  { font-size: 140%; font-weight: bold; $fontfam; }
p.ft  { font-size:  80%; $fontfam; }
EOD
my $bodyatts = "text='$BLACK' link='$BLACK' vlink='$BLACK'".
               " alink='$RED' bgcolor='$DGREY'";

my $suffixpat = qr{\.(?:jpe?g|png|gif|mpg)}i;

my %capfun = ('c' => \&c_caption,
	      'f' => \&f_caption,
	      's' => \&s_caption,
	      't' => \&t_caption,
	     );

my $br = br();

# Max.number of clickable index numbers (should be odd).
use constant IXLIST => 21;

# Helper programs
my $prog_jpegtran  = findexec("jpegtran");
my $prog_mplayer   = findexec("mplayer");
my $prog_mencoder  = findexec("mencoder");

################ The Process ################

use File::Path;
use File::Basename;
use Time::Local;
use Image::Info;
use Image::Magick;
use Data::Dumper;
use POSIX qw(strftime);
use locale;

# The files already there, if any.
my $gotlist = new FileList;
# The files in the import dir, if any.
my $implist = new FileList;

# The list of files, in the order to be processed.
# This list is initialy filled from info.dat, and (optionally) updated
# from the other lists.
my $filelist = new FileList;

# This is the list of all entries to be journalled (all images, plus
# possible interspersed loose annotations).
my @journal;

# Load cached info, if possible.
load_cache();

# Load image names and info from the info file, if any.
# This produces the initial file list.
load_info();
#print STDERR Data::Dumper->Dump([$filelist],[qw(filelist)]);

# Load image names and info for files we already got.
load_files()  if -d d_large();
#print STDERR Data::Dumper->Dump([$gotlist],[qw(gotlist)]);

# Load image names and info for files we can import.
load_import() if $import_dir && -d $import_dir;
#print STDERR Data::Dumper->Dump([$implist],[qw(implist)]);

# Apply defaults to unset parameters.
set_defaults();

# Verify and update the file list.
my $added = update_filelist();
#print STDERR Data::Dumper->Dump([$filelist],[qw(filelist)]);

my $num_entries = $filelist->tally;
print STDERR ("Number of entries = $num_entries",
	      $added ? " ($added added)" : "",
	      "\n") if $verbose > 1;
die("Nothing to do?\n") unless $num_entries > 0;
exit(0) if $test;

# Clean up and create directories.
if ( $clobber ) {
    rmtree([d_thumbnails(), d_medium()], $verbose > 1);
}
mkpath([d_large(), d_thumbnails(), d_icons()], $verbose > 1);
mkpath([d_medium()], $verbose > 1) if $medium;

# Copy the button images over to the target directory.
add_button_images();

# Copy images in place, rotate if necessary, and create the thumbnails.
prepare_images();

# Update cache.
update_cache();
my $cache_update = 0;

my $entries_per_page = $index_columns*$index_rows;
my $num_indexes = int(($num_entries - 1) / $entries_per_page) + 1;

my $fn = "img0000";
# Cleanup excess files.
for ( 0 ) {
    my $excess = $fn++ . ".html";
    unlink(d_medium($excess));
    unlink(d_large($excess)) or last;
}

# Map file names to html pages. Start with 1 to match "image N of M".
my @htmllist;
for my $i ( 0 .. $num_entries-1 ) {
    $htmllist[$i] = $fn++ . ".html";
}

# Cleanup excess files.
for (my $i = $num_entries ; ; $i++ ) {
    my $excess = $fn++ . ".html";
    unlink(d_medium($excess));
    unlink(d_large($excess)) or last;
}

# Write the individual pages.
print STDERR ("Creating ", $num_entries, " image page",
	      $num_entries == 1 ? "" : "s", "\n") if $verbose > 1;
my $mod = 0;

for my $el ( $filelist->entries ) {
    write_image_page($el, "large") && $mod++;
    write_image_page($el, "medium") && $mod++ if $medium;
}
uptodate("image", $mod) if $verbose > 1;

# Write the index pages.
print STDERR ("Creating ", $num_indexes, " index page",
	      $num_indexes == 1 ? "" : "s", "\n") if $verbose > 1;
$mod = 0;
for my $i ( 0 .. $num_indexes-1 ) {
    write_index_page($i) && $mod++;
}
uptodate("index", $mod) if $verbose > 1;

# Cleanup excess indices.
for (my $i = $num_indexes ; ; $i++ ) {
    unlink(d_dest("index$i.html")) or last;
}

if ( $journal ) {
    print STDERR ("Creating ", $journal, " journal page",
		  $journal == 1 ? "" : "s", "\n") if $verbose > 1;
    mkpath([d_journal()], $verbose > 1);
    $mod = write_journal();
    uptodate("journal", $mod) if $verbose > 1;
}

if ( $icon ) {
    print STDERR ("Creating index icon\n") if $verbose > 1;
    unless ( indexicon() ) {
	print STDERR ("(Index icon not modified)\n") if $verbose > 1;
    }
}

# Final update, if needed.
update_cache() if $cache_update;

exit 0;

################ Subroutines ################

# Image types.
use constant T_JPG   => 1;
use constant T_MPG   => 2;
use constant T_VOICE => 3;	# still image + sound
# Pseudo types.
use constant T_TAG   => -1;
use constant T_ANN   => -2;
use constant T_REF   => -3;

# List of possible subdirs to process.
my @subdirs;

# Journal tags
my %jnltags;

# Note: the HTML generators use the file names relatively.
sub d_large      { unshift(@_, "large");      goto &d_dest; }
sub d_medium     { unshift(@_, "medium");     goto &d_dest; }
sub d_thumbnails { unshift(@_, "thumbnails"); goto &d_dest; }
sub d_icons      { unshift(@_, "icons");      goto &d_dest; }
sub d_journal    { unshift(@_, "journal");    goto &d_dest; }
sub d_dest       { unshift(@_, $dest_dir) unless $dest_dir eq ".";
		   join("/", @_); }

my %optcfg;			# option set from config files

sub setopt {
    no strict qw(refs);
    return if defined(${$_[0]});
    print STDERR ("setopt $_[0] -> $_[1]\n") if $trace;
    ${$_[0]} = $_[1];
    $optcfg{$_[0]} = 1;
}

sub parse_line {
    local ($_) = (@_);
    my $err = 0;

    if ( /^!?\s*(\S.*)/ ) {
	$_ = $1;
	if ( /^title\s+(.*)/ ) {
	    setopt("album_title", $1);
	}
	elsif ( /^page\s+(\d+)x(\d+)/ ) {
	    setopt("index_rows", $1);
	    setopt("index_columns", $2);
	}
	elsif ( /^thumbsize\s*(\d+)/ ) {
	    setopt("thumb", $1);
	}
	elsif ( /^mediumsize\s*(\d+)/ ) {
	    setopt("medium", $1);
	}
	elsif ( /^medium\s*(\d+)?/ ) {
	    setopt("medium", $1 || DEFAULTS->{mediumsize});
	}
	elsif ( /^dateformat\s*(.*)/ ) {
	    setopt("datefmt", $1);
	}
	elsif ( /^caption\s*(.*)/ ) {
	    setopt("caption", $1);
	}
	elsif ( /^icon\s*(.*)/ ) {
	    setopt("icon", defined($1) && length($1) ? $1 : 1);
	}
	else {
	    warn("Unknown control: $_[0]\n");
	    $err++;
	}
    }
    else {
	warn("Invalid control: $_[0]\n");
	$err++;
    }
    $err;
}

sub set_defaults {

    # Load settings from user files.
    my $sl = $ENV{ALBUMCONFIG} || ".albumrc:".$ENV{HOME}."/.albumrc";
    foreach my $cf ( split(/:/, $sl) ) {
	unless ( -f $cf ) {
	    warn("$cf: $!\n") if $ENV{ALBUMCONFIG};
	    next;
	}
	open(my $fh, "<$cf") || next;
	warn("parsing: $cf\n") if $trace;
	my $err = 0;
	while ( <$fh> ) {
	    next if /^\s*#/;
	    next unless /\S/;
	    $err += parse_line($_);
	}
	close($fh);
	die("Errors in config file $cf, aborted\n") if $err;
    }

    # Finally, apply defaults if necessary.
    warn("apply defaults\n") if $trace;
    setopt("album_title",   DEFAULTS->{title});
    setopt("index_rows",    DEFAULTS->{indexrows});
    setopt("index_columns", DEFAULTS->{indexcols});
    setopt("thumb",         DEFAULTS->{thumbsize});
    setopt("datefmt",       DEFAULTS->{dateformat});
    setopt("icon",          DEFAULTS->{icon});

    $medium = DEFAULTS->{mediumsize} if defined($medium) && !$medium || $mediumonly;

    # Caption values.
    setopt("caption", DEFAULTS->{( -s $info_file || $import_dir) ?
				 "caption" : "captionmin" });
    die("Invalid value for caption: $caption\n")
      unless $caption =~ /^[fsct]*$/i;
    $caption = lc($caption);
}

sub load_info {

    my %typemap = ( 'p' => T_JPG, 'm' => T_MPG, 'v' => T_VOICE );

    # If an info has been supplied, it'd better exist.
    if ( $info_file ) {
	die("$info_file: $!\n") unless -s $info_file;
    }
    else {
	# Try default.
	$info_file = d_dest(DEFAULTS->{info});
	unless ( -s $info_file ) {
	    my $add_new; $add_new++ if $import_dir;
	    my $add_src; $add_src++ if -d d_large();
	    print STDERR ("No ", DEFAULTS->{info});
	    print STDERR (", adding images from ") if $add_src || $add_new;
	    print STDERR (d_large())               if $add_src;
	    print STDERR (" and ")                 if $add_src && $add_new;
	    print STDERR ($import_dir)             if $add_new;
	    print STDERR ("\n");
	    return;
	}
    }

    my $err = 0;
    my $file;
    my $tag;

    my $fh = do { local *FH; *FH };
    die("$info_file: $!\n")
      unless open($fh, $info_file);
    warn("parsing: $info_file\n") if $trace;

    my $el;
    my %dirs;

    while ( <$fh> ) {
	chomp;

	next if /^\s*#/;
	next unless /\S/;

	if ( /^\s+/ && $el ) {
	    $el->description($el->description . "\n" . $_);
	    next;
	}

	if ( /^!\s*(\S.*)/ ) {
	    $_ = $1;
	    if ( /^tag\s*(.*)/ ) {
		$tag = $1;
		$tag =~ s/\s$//;
		$tag =~ s/\s+/ /g;
	    }
	    elsif ( /^subdirs\s*(.*)/ ) {
		foreach ( split(' ', $1)) {
		    $dirs{$_}++;
		}
	    }
	    elsif ( /^journal\s*(.*)/ ) {
		if ( $filelist->tally ) {
		    warn("\"!journal\" must precede image info\n");
		    $err++;
		}
		load_info_journal($err, $fh);
		return;
	    }
	    else {
		$err += parse_line("!".$_);
	    }
	    next;
	}
	($file, my $a) = split(' ', $_, 2);

	my $rotate;
	my $type = T_JPG;
	my $assc;
	while ( $a && $a =~ /^-(\w):(\S+)\s*(.*)/ ) {
	    if ( lc($1) eq 'o' ) {
		$rotate = 90 * ($2 % 4);
	    }
	    elsif ( lc($1) eq 'i' ) {
		$assc = basename($file)."/".$2;
		unless ( -s $assc && -r _ ) {
		    warn("$file (info): $assc [$!]\n");
		    undef $assc;
		}
	    }
	    elsif ( lc($1) eq 't' ) {
		$type = $typemap{lc($2)}
		  or warn("$file (info): Illegal type: $2\n"), $err++;
	    }
	    $a = $3;
	}
	$el = new ImageInfo($file);
	$el->type($type);
	$el->description($a) if $a;
	$el->tag($tag) if $tag;
	$el->_rotation($rotate) if defined($rotate);
	if ( $file =~ /^(.+)\.mpg$/i ) {
	    $el->type(T_MPG);
	    $el->assoc_name($1."s.jpg"); # associates still image
	}
	elsif ( $type == T_VOICE ) {
	    (my $t = $file) =~ s/\.jpg$/.mp3/i;
	    $el->assoc_name($t);
	}
	elsif ( $file =~ /.\.html?$/i ) {
	    $type = T_REF;
	}
	if ( $type == T_REF ) {
	    for ( dirname($file)."/icon.jpg" ) {
		$assc = $_ if !defined $assc && -f $_;
	    }
	    $assc = "icons/extern.jpg" unless defined $assc;
	    $el->assoc_name($assc);
	    $el->dest_name($file);
	    $el->type($type);
	}
	$filelist->add($el);
	$dirs{$1} = 1 if $type != T_REF && $file =~ m;^(.+)/[^/]+$;;
    }
    close($fh);
    die("Aborted\n") if $err;
    @subdirs = sort(keys(%dirs));
}

sub load_info_journal {
    my $err = shift;
    my $fh = shift;

    #### WARNING: EXPERIMENTAL ####

    warn("parsing (journal mode)\n") if $trace;

    my %typemap = ( 'p' => T_JPG, 'm' => T_MPG, 'v' => T_VOICE );

    my $tag;
    my $nexttag = 0;
    my $annotation = "";
    my $tags = 0;
    my %dirs;
    local($/) = "";		# para mode
    while ( <$fh> ) {
	chomp;
	next if /^\s*#/;
	next unless /\S/;

	# Handle controls.
	if ( /^!\s*(\S.*)/ ) {
	    $_ = $1;
	    if ( /^tag\s*(.*)/ ) {
		$tag = $1;
		$tag =~ s/\s$//;
		$tag =~ s/\s+/ /g;

		if ( $tag !~ /\S/ ) {
		    warn("Tag may not be empty\n");
		    $err++;
		    next;
		}
		if ( exists($jnltags{$tag}) ) {
		    warn("Tag \"$tag\" is not unique\n");
		    $err++;
		}
		$jnltags{$tag} = sprintf("%04d", ++$nexttag);
		my $el = new ImageInfo;
		$el->tag($tag);
		$el->type(T_TAG);
		push(@journal, $el);
		$tags++;
	    }
	    elsif ( /^subdirs\s*(.*)/ ) {
		foreach ( split(' ', $1)) {
		    $dirs{$_}++;
		}
	    }
	    elsif ( /^journal\s*(.*)/ ) {
		if ( $filelist->tally ) {
		    warn("\"!journal\" must precede image info\n");
		    $err++;
		}
		# Ignore.
	    }
	    else {
		$err += parse_line("!".$_);
	    }
	    next;
	}

	if ( /^\*\s*(.*)/s ) {
	    $_ = $1;
	}
	else {
	    my $el = new ImageInfo;
	    $el->annotation($_);
	    $el->tag($tag);
	    $el->type(T_ANN);
	    push(@journal, $el);
	    next;
	}
	s/\s*\n\s+/ /g;
	my @a = split(/\n/, $_);
	$_ = shift(@a);
	my $annotation = join(" ", @a);
	my ($file, $a) = split(' ', $_, 2);

	my $rotate;
	my $type = T_JPG;
	my $assc;
	while ( $a && $a =~ /^-(\w):(\S+)\s*(.*)/ ) {
	    if ( lc($1) eq 'o' ) {
		$rotate = 90 * ($2 % 4);
	    }
	    elsif ( lc($1) eq 'i' ) {
		$assc = basename($file)."/".$2;
		unless ( -s $assc && -r _ ) {
		    warn("$file (info): $assc [$!]\n");
		    undef $assc;
		}
	    }
	    elsif ( lc($1) eq 't' ) {
		$type = $typemap{lc($2)}
		  or warn("$file (info): Illegal type: $2\n"), $err++;
	    }
	    $a = $3;
	}
	my $el = new ImageInfo($file);
	$el->type($type);
	$el->description($a) if $a;
	$el->tag($tag) if $tag;
	if ( $annotation ) {
	    $annotation =~ s/^\s+//;
	    $annotation =~ s/\s+$//;
	    $annotation =~ s/\s+/ /g;
	    $el->annotation($annotation);
	}

	$el->_rotation($rotate) if defined($rotate);
	if ( $file =~ /^(.+)\.mpg$/i ) {
	    $el->type(T_MPG);
	    $el->assoc_name($1."s.jpg"); # associates still image
	}
	elsif ( $type == T_VOICE ) {
	    (my $t = $file) =~ s/\.jpg$/.mp3/i;
	    $el->assoc_name($t);
	}
	elsif ( $file =~ /.\.html?$/i ) {
	    $type = T_REF;
	}
	if ( $type == T_REF ) {
	    for ( dirname($file)."/icon.jpg" ) {
		$assc = $_ if !defined $assc && -f $_;
	    }
	    $assc = "icons/extern.jpg" unless defined $assc;
	    $el->assoc_name($assc);
	    $el->dest_name($file);
	    $el->type($type);
	}
	$filelist->add($el);
	push(@journal, $el) if $a !~ /^--/;
	$dirs{$1} = 1 if $type != T_REF && $file =~ m;^(.+)/[^/]+$;;
    }
    close($fh);
    die("Aborted\n") if $err;
    @subdirs = sort(keys(%dirs));
    $journal = $tags;		# no tags -- no journal...
}

sub load_files {
    my $dh = do { local *DH; *DH; };
    opendir($dh, d_large())
      or die("Cannot opendir " . d_large() . ": $!\n");
    my @files = sort grep { !/^\./ && /$suffixpat$/ } readdir($dh);
    closedir($dh);

    foreach my $dir ( @subdirs ) {
	opendir($dh, d_large($dir))
	  or die("Cannot opendir " . d_large($dir) . ": $!\n");
	push(@files,
	     map { "$dir/$_" }
	         sort grep { !/^\./ && /$suffixpat$/ } readdir($dh));
	closedir($dh);
    }

    while ( @files ) {
	my $f = shift(@files);
	next unless -f d_large($f);
	my $el = new ImageInfo(d_large($f));
	$el->type(T_JPG);
	if ( $f =~ /^(.+)\.jpg$/ ) {
	    my $m = "$1.mp3";
	    if ( -s d_large($m) ) {
		$el->type(T_VOICE);
		$el->assoc_name($m);
		warn(d_large($f).": Changed to VOICE\n") if $verbose;
	    }
	}
	elsif ( $f =~ /^(.+)\.mpg$/ ) {
	    $el->type(T_MPG);
	    my $assoc = $1."s.jpg";
	    $el->assoc_name($assoc);
	    if ( @files && $files[0] eq $assoc ) {
		shift(@files);
		warn(d_large($assoc).": Skipped still\n") if $verbose;
	    }
	}
	$gotlist->add($el, $f);
    }
}

sub load_import {
    my $dh = do { local *DH; *DH; };
    opendir($dh, $import_dir)
      or die("Cannot opendir $import_dir: $!\n");

    my @files = sort grep { !/^\./ && /$suffixpat$/ } readdir($dh);
    closedir($dh);

    while ( @files ) {
	my $f = shift(@files);
	next unless -f "$import_dir/$f";

	my $el = new ImageInfo("$import_dir/$f");
	if ( $import_exif ) {
	    shift(@files) if handle_exif($f, $files[0], $el);
	}
	else {
	    $el->type(T_JPG);
	    if ( $f =~ /^(.+)\.mpg$/i ) {
		$el->type(T_MPG);
		$el->assoc_name($1."s.jpg");
	    }
	    $implist->add($el, $f);
	}
    }
}

sub handle_exif {
    my ($file, $next, $el) = @_;

    # Sony DSC-V1 produces the following files:
    #   DSC0nnnn.JPG	still image
    #   DSC0nnnn.JPE	mail mode image*
    #   DSC0nnnn.MPG	voice mode image*
    #   DSC0nnnn.TIF	uncompressed image*
    #   CLP0nnnn.GIF	clip motion file
    #   CLP0nnnn.HTM	clip motion file index
    #   MBL0nnnn.GIF	clip motion file, mobile mode
    #   MBL0nnnn.HTM	clip motion file index, mobile mode
    #   MOV0nnnn.MPG	movie
    # Files marked with * have a normal still image associated.

    # Normal still image.
    if ( $file =~ /^(.{4})(\d{4})\.(jpg)$/i ) {
	my ($type, $seq, $ext) = ($1, $2, $3);
	my $fd = $el->DateTime || "";
	if ( $fd =~ /(\d\d\d\d):(\d\d):(\d\d) (\d\d):(\d\d):(\d\d)/ ) {
	    my $time = timelocal($6,$5,$4,$3,$2-1,$1);
	    my $new = "$1$2$3$4$5$6$seq";
	    my $ii = cache_entry("$new.$ext");
	    if ( $ii && !$ii->orig_name ) {
		$ii->orig_name("$import_dir/$file");
	    }

	    $el->type(T_JPG);
	    $el->dest_name("$new.$ext");
	    $el->timestamp($time);
	    $file = "$new.$ext";
	    cache_entry($file, $el) unless $ii;
	}
	else {
	    warn("$import_dir/$file: Missing or unparsable file date [$fd]\n")
	      if $verbose;
	    $el->type(T_JPG);
	}
	if ( $next && $next eq "$type$seq.mpg" ) {
	    warn("$import_dir/$file: Changed to VOICE\n") if $verbose;
	    $el->type(T_VOICE);
	    (my $t = $file) =~ s/\.jpg$/.mp3/i;
	    $el->assoc_name($t);
	    $implist->add($el);
	    return 1;
	}
	$implist->add($el);
    }

    # MPEG movie.
    elsif ( $file =~ /^(mov0)(\d{4})\.(mpg)$/i ) {
	my ($type, $seq, $ext) = ($1, $2, $3);
	# We have to trust the file date...
	my $time = $el->timestamp;
	my @tm = localtime($time);
	my $new = sprintf("%04d%02d%02d%02d%02d%02d$seq",
			  1900+$tm[5], 1+$tm[4], @tm[3,2,1,0]);
	my $ii = cache_entry("$new.$ext");
	if ( $ii && !$ii->orig_name ) {
	    $ii->orig_name("$import_dir/$file");
	}

	$el->type(T_MPG);
	$el->dest_name("$new.$ext");
	$el->assoc_name($new."s.jpg");
	$implist->add($el, "$new.$ext");
	$file = "$new.$ext";
	cache_entry($file, $el) unless $ii;
    }

    # Assume ordinary JPEG.
    else {
	$el->type(T_JPG);
	$implist->add($el, $file);
    }
    return 0;
}

sub update_filelist {
    my $todo = new FileList;

    my $el;
    my %seen;
    my $missing;
    my $prev;

    foreach $el ( $filelist->entries ) {
	my $f = $el->dest_name;
	$seen{$f}++;
	print STDERR ("todo[inf]: $f") if $trace;
	my $entry = $gotlist->byname($f);
	if ( $entry ) {
	    print STDERR (" -- got") if $trace;
	}
	elsif ( $entry = $implist->byname($f) ) {
	    print STDERR (" -- imp") if $trace;
	}
	elsif ( $el->type == T_REF ) {
	    $entry = $el;
	    print STDERR (" -- ref") if $trace;
	}
	if ( $entry ) {
	    unless ( $el->description =~ /^--($|\s)/ ) {
		# Copy properties from info.
		$entry->tag($el->tag);
		$entry->description($el->description);
		$entry->annotation($el->annotation);
		$entry->_rotation($el->_rotation);
		# Add and create prev/next links.
		$entry->prev($prev->seq) if $prev;
		$todo->add($entry);
		$prev->next($entry->seq) if $prev;
		print STDERR ("\n") if $trace;
	    }
	    else {
		print STDERR (" (ignored)\n") if $trace;
		undef $entry;
	    }
	}
	elsif ( $trace ) {
		print STDERR ("\n");
	}
	else {
	    print STDERR ("todo[inf]: $f -- missing\n");
	    $missing++;
	}
	$prev = $entry if $entry && $entry->type != T_REF;
    }
    die("Aborted!\n") if $missing;

    unless ( $filelist->tally == 0 || $update ) {
	$filelist = $todo;
	return 0;
    }

    my $newinfo = "";
    my $date;
    my $new;

    foreach $el ( $gotlist->entries ) {
	my $f = $el->dest_name;
	print STDERR ("todo[got]: $f") if $trace;
	if ( $seen{$f}++ ) {
	    print STDERR (" -- seen\n") if $trace;
	    next;
	}
	print STDERR (" -- added\n") if $trace;
	my $nd = "";
	if ( $f =~ /^(\d{4})(\d\d)(\d\d)(\d\d)(\d\d)(\d\d)/ ) {
	    my $tl = timelocal($6,$5,$4,$3,$2-1,$1);
	    $nd = strftime($datefmt, localtime($tl));
	    $el->timestamp($tl);
	}
	if ( !defined($date) || $nd ne $date ) {
	    $newinfo .= "\n!tag $nd\n";
	    $date = $nd;
	}
	$newinfo .= $f . "\n";
	$el->tag($date) if $date;
	$el->prev($prev->seq) if $prev;
	$todo->add($el);
	$prev->next($el->seq) if $prev;
	$prev = $el unless $el->type == T_REF;
	push(@journal, $el) if $journal;
	$new++;
    }

    foreach $el ( $implist->entries ) {
	my $f = $el->dest_name;
	print STDERR ("todo[imp]: $f") if $trace;
	if ( $seen{$f}++ ) {
	    print STDERR (" -- seen\n") if $trace;
	    next;
	}
	print STDERR (" -- added\n") if $trace;
	my $nd = "";
	my $time = $el->timestamp;
	if ( $time ) {
	    $nd = strftime($datefmt, localtime($time));
	}
	if ( !defined($date) || $nd ne $date ) {
	    $newinfo .= "\n!tag $nd\n";
	    $date = $nd;
	}
	$newinfo .= "$f " .
	  ($el->rotation ? ("-O:".int($el->rotation/90)." ") : "") .
	    ($el->type == T_VOICE ? "-T:V " : "") .
	      " \n";
	$el->tag($date) if $date;
	$el->prev($prev->seq) if $prev;
	$todo->add($el);
	$prev->next($el->seq) if $prev;
	$prev = $el unless $el->type == T_REF;
	push(@journal, $el) if $journal;
	$new++;
    }

    $filelist = $todo;

    unless ( $new ) {		# nothing to add
	warn("No new images imported\n") if $verbose > 1;
	return 0;
    }

    return $new if $test;

    unless ( -w $info_file ) {
	warn("$info_file: Cannot update (".
	     (-e _ ? "no write access" : "does not exist") .
	     ")\n") if $verbose;
	return $new;
    }

    my $infosize = -s $info_file;

    # Append new info.
    warn("Updating $info_file\n") if $verbose > 1;
    my $fh = do { local *F; *F };
    open($fh, ">>", $info_file) || die("$info_file: $!\n");
    unless ( $infosize ) {
	print $fh ("# album control file created by $my_name $my_version, ".
	       localtime(time), "\n\n");
	print $fh ("!title $album_title\n") if $album_title;
	if ( $medium && !$optcfg{"medium"} ) {
	    print $fh ($medium != DEFAULTS->{mediumsize} ?
		       "!mediumsize $medium\n" : "!medium\n");
	}
	print $fh ("!thumbsize $thumb\n")
	  if !$optcfg{"thumb"} && $thumb != DEFAULTS->{thumbsize};
	print $fh ("!page ${index_rows}x${index_columns}\n")
	  if !$optcfg{index_rows} && $index_rows != DEFAULTS->{indexrows}
	      || !$optcfg{index_columns} && $index_columns != DEFAULTS->{indexcols};
	print $fh ("!caption $caption\n")
	  if !$optcfg{"caption"} && $caption ne DEFAULTS->{caption};
    }
    print $fh ("\n# New entries added by $my_name $my_version, ".
	       localtime(time), "\n",
	       $newinfo,
	       "\n");
    close($fh);

    $new;
}

sub prepare_images {

    my $ddot = 0;
    my $tdot = 0;
    my $fmt = "[%" . length($filelist->tally) . "d]\n";
    my $msgfile;
    my $msg = sub {
	return unless $verbose > 1;

	if ( $verbose > 2 ) {
	    if ( $msgfile ) {
		print STDERR ("$msgfile: ");
		$msgfile = "";
	    }

	    print STDERR (@_ ? @_ : "OK\n");
	}

	unless ( @_ ) {
	    unless ( $msgfile ) {
		print STDERR ("OK\n");
		return;
	    }
	    print STDERR (".");
	    $tdot++;
	    if ( ++$ddot >= 50 ) {
		printf STDERR ($fmt, $tdot);
		$ddot = 0;
	    }
	    return;
	}

	printf STDERR ($fmt, $tdot) if $ddot;
	$ddot = 0;

	if ( $msgfile ) {
	    print STDERR ("$msgfile: ");
	    $msgfile = "";
	    $tdot++;
	}

	print STDERR (@_);
    };

    my $image;
    my $i_large;

    my $readimage = sub {
	my ($file) = (@_, $i_large);
	$image = new Image::Magick;
	my $t = $image->Read($file);
	warn("read($file): $t\n") if $t;
#	$image->Profile(name => "*", profile => undef);
    };

    my $resize = sub {
	 my ($n) = @_;
	 my ($origx, $origy) = $image->Get(qw(width height));
	 my $ratio = $origx > $origy ? $origx / $n : $origy / $n;
	 my $t = $image->Resize(width => $origx/$ratio, height => $origy/$ratio);
	 warn("resize: $t\n") if $t;
    };

=begin checked_by_Makefile_PL

    unless ( $prog_jpegtran ) {
	foreach my $el ( $filelist->entries ) {
	    next unless $el->rotation || $el->mirror;
	    next if -s d_large($el->dest_name);
	    warn("WARNING: Helper program 'jpegtran' not found.\n",
		 "JPG files will be rotated with loss of information.\n");
	    last;
	}
    }

    unless ( $prog_mplayer ) {
	foreach my $el ( $filelist->entries ) {
	    next unless $el->type == T_MPG;
	    next if -s d_large($el->dest_name);
	    warn("WARNING: Helper program 'mplayer' not found.\n",
		 "\tNo stills will be produced, and VOICE files will remain silent.\n");
	    last;
	}
    }

    unless ( $prog_mencoder ) {
	foreach my $el ( $filelist->entries ) {
	    next unless $el->type == T_VOICE;
	    next if -s d_large($el->assoc_name);
	    warn("WARNING: Helper program 'mencoder' not found.\n",
		 "\tMPG files will be copied, and cannot be rotated.\n");
	    last;
	}
    }

=cut

    foreach my $el ( $filelist->entries ) {
	next unless $el->type > 0;
	my $file = $el->dest_name;
	$msgfile = $file;
	$image = undef;

	# Check for directory names, e.g. f01/p01.jpg.
	my $dn = dirname($file);
	if ( $dn && $dn ne "." ) { # we have a dir name.
	    mkpath([d_thumbnails($dn), d_large($dn)], 1);
	    mkpath([d_medium($dn)], 1) if $medium;
	}

	$i_large = d_large($file);
	my $movie = $el->type == T_MPG;

	# Copy the file into place.
	if ( ! -s $i_large && $el->orig_name ) {
	    my $i_src = $el->orig_name;
	    my $time = $el->timestamp;

	    if ( $movie ) {
		$msg->("copy");
		if ( $prog_mencoder ) {
		    $msg->("/rotate (be patient)") if $el->rotation;
		    $msg->(" ");
		    # Currently. movies have a bad ugly copy routine...
		    copy_mpg($i_src, $i_large, $time,
			     $el->rotation, $el->mirror);
		}
		else {
		    $msg->(" [no rotation]") if $el->rotation;
		    $msg->(" ");
		    copy($i_src, $i_large, $time);
		}
	    }
	    elsif ( $el->rotation || $el->mirror ) {
		$msg->("copy");
		$msg->("/rotate") if $el->rotation;
		$msg->("/mirror") if $el->mirror;
		$msg->(" ");

		# Use jpegtran to rotate jpg files.
		if ( ($el->file_ext || "") eq "jpg" && $prog_jpegtran ) {
		    my $cmd = "$prog_jpegtran -copy all -rotate " . $el->rotation . " ";
		    $cmd .= $el->mirror eq 'h' ? "-transpose " : "-transverse "
		      if $el->mirror;
		    $cmd .= "-outfile " . squote($i_large) .
		      " " . squote($i_src);
		    my $t = `$cmd 2>&1`;
		    $msg->($t) if $t;
		    utime($time, $time, $i_large);
		}
		# Otherwise, let Image::Magick handle it.
		else {
		    $readimage->($i_src);
		    $image->Rotate();
		    if ( $el->mirror ) {
			$image->Flip if $el->mirror eq 'h';
			$image->Flop if $el->mirror eq 'v';
		    }
		    my $t = $image->Write($i_large);
		    $msg->($t) if $t;
		    utime($time, $time, $i_large);
		}
	    }
	    elsif ( $linkthem ) {
		$msg->("link ");
		unless ( link($i_src, $i_large) == 1 ) {
		    unlink($i_large); # just in case
		    substr($msg,-5) = "copy ";
		    copy($i_src, $i_large, $time);
		}
	    }
	    else {
		$msg->("copy ");
		copy($i_src, $i_large, $time);
	    }
	    if ( $el->type == T_VOICE ) {
		$msg->("sound ");
		copy_voice($i_src, d_large($el->assoc_name),
			   $time);
	    }
	}
	if ( $movie ) {
	    $movie = $file;
	    $file = $el->assoc_name;
	    $i_large = d_large($file);
	    unless ( -s $i_large ) {
		$msg->("still ");
		$image = still($el);
	    }
	}

	my $i_medium = d_medium($file);
	my $i_small  = d_thumbnails($file);

	if ( $medium && ! -s $i_medium ) {
	    $readimage->() unless $image;
	    $msg->("medium ");
	    $resize->($medium);
	    my $t = $image->Write($i_medium);
	    $msg->($t) if $t;
	}
	$el->medium_size(-s $i_medium) if $medium && !$movie;

	if ( ! -s $i_small ) {
	    $readimage->() unless $image;
	    $msg->("thumbnail ");
	    $resize->($thumb);
	    my $t = $image->Write($i_small);
	    $msg->($t) if $t;
	}

	$msg->(); 		# flush

    }
    printf STDERR ($fmt, $tdot) if $ddot && $tdot;
}

#### Output generation.

sub button($$;$$);

sub ixname($);

sub write_image_page {
    my ($el, $dir) = @_;

    return unless $el->type > 0;

    my $i = $el->seq - 1;
    my $file = $el->dest_name;
    my $rf = $file;

    # Try movie.
    my $movie = $el->type == T_MPG;
    if ( $movie ) {
	$file = $el->assoc_name;
    }

    my $tt = "$album_title: Image " . ($i+1);
    $tt .= " of " . $num_entries if $num_entries > 1;
    $tt = html($tt);
    my $it = html($el->description);
    unless ( $it ) {
	$it = $tt;
	$tt = "";
    }

    my $next = ($el->next || $num_entries+1) - 1;
    my $prev = ($el->prev || 0) - 1;

    my $b = join("$br\n",
		 ($dir eq "large" && $medium) ?
		 button("medium", "../medium/".$htmllist[$i],              1, 1) :
		 button("index",  "../".ixname(int($i/$entries_per_page)), 1, 1),
		 button("first",  $htmllist[0],                            1, $i > 0),
		 button("prev",   $htmllist[$prev] || "",                  1, $prev >= 0),
		 button("next",   $htmllist[$next] || "",                  1, $next < $num_entries),
		 button("last",   $htmllist[-1],                           1, $i < $num_entries-1));

    if ( $journal ) {
	$b .= "$br\n" .
	  button("journal",
		 "../journal/jnl" . $jnltags{$el->tag} . ".html#img".sprintf("%04d", $i+1),
		 1, 1);
    }
    if ( $el->type == T_VOICE ) {
	my $sound = $el->assoc_name;
	$b .= "$br\n" .
	  button("sound", "../large/$sound", 1, 1);
    }

    my $imglink;
    if ( $dir eq "medium" ) {
	if ( $mediumonly ) {
	    $imglink = img($file, alt => "[Image]", border => 2);
	}
	elsif ( $movie ) {
	    $imglink = "<a href='../large/" . $el->dest_name . "'>" .
	      img($file, alt => "[Click to play movie]", border => 2) .
		"</a>";
	}
	else {
	    $imglink = "<a href='../large/".$htmllist[$i]."'>" .
	      img($file, alt => "[Click for bigger image]", border => 2) .
		"</a>";
	}
    }
    else {
	if ( $movie ) {
	    $imglink = "<a href='" . $el->dest_name . "'>" .
	      img($file, alt => "[Click to play movie]", border => 2) .
		"</a>";
	}
	else {
	    $imglink = img($file, alt => "[Image]", border => 2);
	}
    }

    my $auxright = html($el->dest_name);
    my $s = size_info($el);
    $auxright .= " ($s)" if $s;
    $auxright .= "&nbsp;&nbsp;&nbsp;$creator" if $creator;
    my $auxleft  = html($el->tag || "");

    my $it2 = $it;
    if ( $el->Make ) {		# EXIF info
	$it2 = "<a href='#' class='info'>" . $it .
	  "<span>" .
	    "<table border='1' width='100%' bgcolor='$MGREY'>\n" .
	      restyle_exif($el) . "</table>\n" .
		"</span></a>";
    }
    update_if_needed(d_dest($dir, $htmllist[$i]), <<EOD);
<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.01 Transitional//EN">
<html>
  <head>
    <title>$it</title>
    <style type='text/css'>
      <!--
      @{[indent($css, 6)]}
      a.info{position: relative;z-index:24;background-color:$DGREY; color:$BLACK; text-decoration:none}
      a.info:hover{z-index:25;background-color: $DGREY}
      a.info span{display: none}
      a.info:hover span{display:block;
	  position:absolute; top:2em;left:2em; width:15em;
	  border:0px; background-color:$MGREY; color:$BLACK;text-align: center}
      -->
    </style>
  </head>
  <body $bodyatts>
    <table>
      <tr>
	<td></td>
	<td align='left' valign='top'>
	  <p class='hd'>@{[indent($it2, 12)]}</p>
	</td>
	<td align='right' valign='top'>
	  <p class='hd'>$tt</p>
	</td>
      </tr>
      <tr>
	<td valign='top'>
	  @{[indent($b, 10)]}
	</td>
	<td align='center' valign='top' colspan='2'>
	  @{[indent($imglink, 10)]}
	</td>
      </tr>
      <tr>
	<td></td>
	<td align='left' valign='top'>
	  <p class='ft'>$auxleft</p>
	</td>
	<td align='right' valign='top'>
	  <p class='ft'>$auxright</p>
	</td>
      </tr>
    </table>
  </body>
</html>
EOD
}

sub write_index_page {
    my ($x) = @_;

    my $tt = $album_title.": Index"; # left title
    my $t = "";			# right (index select)
    my $b = "";			# buttons (vertical)

    # Construct buttons and index selector.
    if ( $num_indexes > 1 ) {
	$b = join("$br\n",
		  button("first", ixname(0),              0, $x > 0             ),
		  button("prev",  ixname($x-1),           0, $x > 0             ),
		  button("next",  ixname($x+1),           0, $x < $num_indexes-1),
		  button("last",  ixname($num_indexes-1), 0, $x < $num_indexes-1));
	$tt .= " " . ($x+1) . " of $num_indexes";
	my @ixlist = ( 0..$num_indexes-1 );
	if ( @ixlist > IXLIST ) {
	    @ixlist = ( $x );
	    while ( @ixlist < IXLIST ) {
		push(@ixlist, $ixlist[-1]+1)
		  if $ixlist[-1]+1 < $num_indexes;
		unshift(@ixlist, $ixlist[0]-1)
		  if @ixlist < IXLIST && $ixlist[0] > 0;
	    }
	}
	$t .= "...\n" if $ixlist[0];
	foreach ( @ixlist ) {
	    if ( $_ == $x ) {
		$t .= ($x+1) . "\n";
	    }
	    else {
		my $el = $filelist->byseq(($_ * $index_rows * $index_columns) + 1);
		$t .= "<a";
		if ( my $tag = $el->tag ) {
		    $t .= " onmouseover='return tip(\"$tag\")'" .
		      " onmouseout='return tip(\"\")' onclick='return tip(\"\")'";
		}
		$t .= " href='" . ixname($_) . "'>" . ($_+1) . "</a>\n";
	    }
	}
	$t .= "...\n" if $ixlist[-1] < $num_indexes-1;
    }

    my $first_in_row = $x * $entries_per_page;

    if ( $journal ) {
	$b .= "$br\n" if $b;
	$b .= button("journal",
		     "journal/jnl".
		     $jnltags{$filelist->byseq($first_in_row+1)->tag}.
		     ".html#img".sprintf("%04d", $first_in_row+1),
		     0, 1);
    }

    # Construct the actual index part.
    my $cc = "<table border='2' cellpadding='3' cellspacing='3'" .
             " bgcolor='$MGREY'>\n";

    for ( my $i = 0; $i < $index_rows; $i++, $first_in_row += $index_columns ) {
	if ( $first_in_row < $num_entries ) {
	    $cc .= "  <tr bgcolor='$LGREY'>\n";
	    for ( my $j = 0; $j < $index_columns; $j++ ) {
		my $this = $first_in_row + $j;
		if ( $this < $num_entries ) {
		    my $el = $filelist->byseq($this+1);
		    my $file = $el->dest_name;
		    my $img;
		    my $base;
		    my $target = "";
		    if ( $el->type == T_REF ) {
			$img = $el->assoc_name;
			$base = $el->orig_name;
			$target = " target=\"_blank\"";
		    }
		    else {
			$img = $el->type == T_MPG ? $el->assoc_name : $file;
			$img = "thumbnails/$img";
			$base = $medium ? "medium/" : "large/";
			$base .= $htmllist[$this];
		    }
		    $cc .= "    <td align='center' valign='bottom'>\n".
			  "      <table border='0' cellpadding='0' cellspacing='0' bgcolor='$LGREY'>\n".
			  "        <tr>\n".
			  "          <td align='center'>\n".
			  "            <a href='$base'$target>".img($img, alt => "[Click for bigger image]", border => 0)."</a>\n".
			  "          </td>\n".
			  "        </tr>\n".
			  "        <tr>\n".
			  "          <td align='center'>\n".
			  "            <p class='ft'>" . join($br, map { $capfun{$_}->($el) } split(//, $caption)) . "</p>\n".
			  "          </td>\n".
			  "        </tr>\n".
			  "      </table>\n".
			  "    </td>\n";
		}
		else {
		    $cc .= "    <td width='$thumb' bgcolor='$DGREY'>&nbsp</td>\n";
		}
	    }
	    $cc .= "  </tr>\n";
	}
    }
    $cc .= "</table>\n";

    update_if_needed(d_dest(ixname($x)), <<EOD);
<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.01 Transitional//EN">
<html>
  <head>
    <style type='text/css'>
      <!--
      @{[indent($css, 6)]}
      a.info{position: relative;z-index:24;background-color:$LGREY; color:$BLACK; text-decoration:none}
      a.info:hover{z-index:25;background-color: $LGREY}
      a.info span{display: none}
      a.info:hover span{display:block;
	  position:absolute; top:2em;left:2em; width:25em;
	  border:0px; background-color:$MGREY; color:$BLACK;text-align: center}
      -->
    </style>
    <script language="JavaScript">
    <!--
    function tip(tipText) {
      window.status = tipText;
      return true;
    }
    -->
    </script>
    <title>$tt</title>
  </head>
  <body $bodyatts>
    <table>
      <tr>
	<td></td>
	<td align='left'>
	  <p class='hd'>$tt</p>
	</td>
	<td align='right'>
	  <p class='hd'>
            @{[indent($t, 12)]}
          </p>
	</td>
      </tr>
      <tr>
	<td valign='top'>
	  @{[indent($b, 10)]}
	</td>
	<td valign='top' colspan='2'>
	  @{[indent($cc, 10)]}
	</td>
      </tr>
    </table>
  </body>
</html>
EOD
}

sub write_journal {

    my $jname = sub {
	sprintf("jnl%04d.html", shift);
    };

    my @ann;
    my $seq = 1;
    my $x = 0;
    my $tag;

    my $flush = sub {
	my $jnl = "";
	my $ix = int($seq / ($index_rows * $index_columns)) || "";
	foreach my $e ( @ann ) {
	    if ( $e->type == T_ANN ) {
		$jnl .= "<tr>\n".
			"  <td colspan='2' valign='middle' align='left'>".
			"    " . indent($e->annotation, 4) . "\n".
			"  </td>\n".
			"</tr>\n";
		next;
	    }
	    next if $e->type == T_REF; #### TODO

	    # We cannot use $el->seq, since that's the info.dat order
	    # which and includes the skipped entries.
	    my $dst = $e->type == T_MPG ? $e->assoc_name : $e->dest_name;
	    my $img = "<a name='" . sprintf("img%04d", $seq) . "' " .
		      "href='../" .
		      d_medium(sprintf("img%04d.html", $seq)) .
		      "' border='0'>" .
		      "<img src='../" .
		      d_thumbnails($dst) . "'></a>";

	    $jnl .= "<tr>\n".
	            "  <td valign='middle' align='left'>\n".
		    "    " . indent($e->annotation || "&nbsp;", 4) . "\n".
		    "  </td>\n".
		    "  <td valign='top' align='left'>\n".
		    "    " . indent($img, 4) . "\n".
		    "  </td>\n".
		    "</tr>\n";
	    $seq++;
	}
	my $b =
	  join("",
	       button("first", $jname->(1),         1, $x > 0         ),
	       button("prev",  $jname->($x),        1, $x > 0         ),
	       button("next",  $jname->($x+2),      1, $x < $journal-1),
	       button("last",  $jname->($journal),  1, $x < $journal-1),
	       button("index", "../index$ix.html",  1, 1             ),
	      );
	$x++;

	update_if_needed(d_journal("jnl" . $jnltags{$tag} . ".html"), <<EOD);
<html>
  <head>
    <style>
    <!--
    body  { font-family: Verdana, Arial, Helvetica; }
    p.hd  { font-size: 140%; font-weight: bold;
	    font-family: Verdana, Arial, Helvetica;
	    margin-left: 0.1in; margin-top: 0.1in; margin-bottom: 0.1in;
	  }
    -->
    </style>
  </head>
  <body>
    <table width="500" border="0" cellpadding="0" cellspacing="10">
      <tr bgcolor='#C0C0C0'>
	<td>
	  <p class='hd'>@{[html($tag)]}</p>
	</td>
        <td align='right'>
          @{[indent($b,10)]}
        </td>
      </tr>
      @{[indent($jnl,6)]}
      <tr bgcolor='#C0C0C0'>
	<td>&nbsp;</td>
        <td align='right'>
          @{[indent($b,10)]}
        </td>
      </tr>
    </table>
  </body>
</html>
EOD
    };

    my $mod = 0;

    foreach my $el ( @journal ) {
	my $t = $el->type;
	if ( $t == T_TAG ) {
	    $flush->() && $mod++ if @ann;
	    $tag = $el->tag;
	    @ann = ();
	}
	else {
	    push(@ann, $el);
	}
    }
    $flush->() && $mod++ if @ann;

    $mod;
}

sub button($$;$$) {
    my ($tag, $link, $level, $active) = @_;
    my $Tag = ucfirst($tag);

    $level  = 0 unless defined $level;
    $active = 1 unless defined $active;
    $tag .= "-gr" unless $active;
    $level = "../" x $level;
    my $b = img("${level}icons/$tag.png", align => "top",
		border => 0, alt => "[$Tag]");
    $active ? "<a class='info' href='$link' alt='[$Tag]'>$b</a>" : $b;
}

sub ixname($) {
    my ($x) = @_;
    "index" . ($x ? $x : "") . ".html";
}

# These are to aid XHTML compliancy.
sub br {
    "<br>";
}

#### HTML helpers.

sub html {
    # Escape HTML sensitive characters, and turn newlines into <br>.
    my $t = shift;
    return '' unless $t;
    $t =~ s/\&/&amp;/g;
    $t =~ s/\</&lt;/g;
    $t =~ s/\>/&gt;/g;
    $t =~ s/\n+/$br/go;
    $t;
}

sub indent {
    # Shift contents to the right so it fits pretty.
    my ($t, $n) = @_;
    $n = " " x $n;
    return $n unless $t;
    $t = detab($t);
    $t =~ s/\n+$//;
    $t =~ s/\n/\n$n/g;
    $t;
}

sub img {
    my ($file, %atts) = @_;
    my $ret = "<img src='" . $file . "'";
    foreach ( sort(keys(%atts)) ) {
	$ret .= " $_='" . $atts{$_} . "'";
    }
    $ret . ">";
}

sub restyle_exif {
    my ($el) = @_;
    my $ret = "";
    my $v;

    my $app = sub {
	$ret .= "<tr><td>".html($_[0])."</td>".
	            "<td>".html($_[1])."</td></tr>\n";
    };

    $app->("Date", $v) if $v = $el->DateTime;
    my $t = $el->ExposureTime || 0;
    if ( $t && $t <= 0.5 ) {
	$t = "1/".int(0.5 + 1/$t)."s";
    }
    $app->("Exposure",
	   join(" ", $el->ExposureMode || "",
		$el->ExposureProgram || "", $t));
    $app->("Aperture", sprintf("%.1f", $v))
      if $v = $el->FNumber;
    if ( $v = $el->FocalLength ) {
	if ( $el->Model eq "DSC-V1" ) {
	    $v .= sprintf("mm  (%.1fmm equiv.)", $v*4.857);
	}
	else {
	    $v .= "mm";
	}
	$app->("Focal length", $v);
    }
    $app->("ISO", $v) if $v = $el->ISOSpeedRatings;
    $app->("Flash", $v)
      if ($v = $el->Flash) && $v ne "Flash did not fire";
    $app->("Metering", $v) if $v = $el->MeteringMode;
    $app->("Scene", $v) if $v = $el->SceneCaptureType;
    $app->("Camera",
	   join(" ", $v, $el->Model))
      if $v = $el->Make;
}

#### Caption helpers.

sub f_caption {
    my ($el) = @_;
    my $s = html($el->dest_name);
    if ( $el->Make ) {
	$s = "&nbsp;$s<a href='#' class='info'>&nbsp;<span>".
	  "<table border='1' bgcolor='$MGREY' width='100%'>\n".
	    restyle_exif($el) . "</table>\n".
	      "</span></a>";
    }
    $s;
}

sub s_caption {
    my ($el) = @_;
    size_info($el, $medium);
}

sub t_caption {
    my ($el) = @_;
    $el->tag  ? html($el->tag) : "";
}

sub c_caption {
    my ($el) = @_;
    my $t = $el->description || "";
    $t =~ s/\n.*//;
    html($t);
}

#### Persistent info (cache) helpers.

{ my $cache;

  my @stats; INIT { @stats = (0, 0, 0); }

  sub load_cache {
    $cache = new ImageInfoCache
      ((!$clobber && -s d_dest(".cache")) ? d_dest(".cache") : undef);
  }

  sub update_cache {
    $cache->store(d_dest(".cache"));
  }

  sub cache_entry {
      if ( @_ == 1 ) {
	  $stats[0]++;
	  my $ii = $cache->entry(@_);
	  $stats[1]++ if $ii;
	  warn("Cache miss: $_[0]\n") if !$ii && $trace;
	  return $ii;
      }
      $stats[2]++;
      $cache->entry(@_);
  }

  END {
      print STDERR ("Cache: store = $stats[2], lookup = $stats[0], hits = $stats[1]\n")
	if $trace;
  }
}

#### Miscellaneous.

sub findexec {
    my ($bin) = @_;
    foreach ( split(":", $ENV{PATH}) ) {
	return "$_/$bin" if -x "$_/$bin";
    }
    undef;
}

sub squote {
    my ($t) = @_;
    $t =~ s/([\\\'])/\\$1/g;
    "'".$t."'";
}

sub update_if_needed {
    my ($fname, $new) = @_;

    # Do not overwrite unless modified.
    if ( -s $fname && -s _ == length($new) ) {
	local($/);
	my $hh = do { local *F; *F };
	my $old;
	open($hh, $fname) && ($old = <$hh>) && close($hh);
	if ( $old eq $new ) {
	    return 0;
	}
    }

    my $fh = do { local *F; *F };
    open($fh, ">$fname")
      or die("$fname (create): $!\n");
    print $fh $new;
    close($fh);
    1;
}

sub add_button_images {

    # Extract button images from DATA section.

    my $out = do { local *OUT; *OUT };
    my $name;
    my $doing = 0;
    my $did = 0;

    while ( <DATA> ) {
        if ( $doing ) {         # uudecoding...
            if ( /^end/ ) {
                close($out);
                $doing = 0;	# Done
		next;
            }
            # Select lines to process.
            next if /[a-z]/;
            next unless int((((ord() - 32) & 077) + 2) / 3)
              == int(length() / 4);
            # Decode.
            print $out unpack("u",$_);
            next;
        }

        # Otherwise, search for the uudecode 'begin' line.
        if ( /^begin\s+\d+\s+(.+)$/ ) {
	    next if !$clobber && -s d_icons($1);
	    print STDERR ("Creating icons ") if $verbose > 1 && !defined($name);
	    $did++;
            $name = d_icons($1);
	    print STDERR ("$1 ") if $verbose > 1;
            open($out, ">$name");
	    binmode($out);
            $doing = 1;         # Doing
            next;
        }
    }
    if ( $doing ) {
        die("Error in DATA: still processing $name\n");
        unlink($name);
    }
    else {
	print STDERR ("done\n") if $did && $verbose > 1;
    }
}

sub bytes {
    my $t = shift;
    return $t . "b" if $t < 10*1024;
    return ($t >> 10) . "kb" if $t < 10*1024*1024;
    ($t >> 20) . "Mb";
}

sub size_info {
    my ($el, $med) = @_;
    return unless $el->width;

    my $ret = "";
    $ret .= $el->width . "x" . $el->height if $el->width;
    for ( $med ? $el->medium_size : $el->file_size ) {
	next unless $_;
	$ret .= "," if $ret;
	$ret .= bytes($_);
    }
    $ret;
}

sub uptodate {
    my ($type, $mod) = @_;
    if ( $mod ) {
	print STDERR ("(Needed to write ", $mod,
		      " $type page", $mod == 1 ? "" : "s", ")\n");
    }
    else {
	print STDERR ("(No $type pages needed updating)\n");
    }
}

sub detab {
    my ($line) = @_;

    my (@l) = split(/\t/, $line);

    # Replace tabs with blanks, retaining layout

    $line = shift(@l);
    $line .= " " x (8-length($line)%8) . shift(@l) while @l;

    $line;
}

sub copy {
    my ($orig, $new, $time) = @_;

    $time = (stat($orig))[9] unless defined($time);

    my $in = do { local *F; *F };
    open($in, "<", $orig) or die("$orig: $!\n");
    binmode($in);

    my $out = do { local *F; *F };
    open($out, ">", $new) or die("$new: $!\n");
    binmode($out);

    my $buf;

    for (;;) {
	my ($r, $w, $t);
	defined($r = sysread($in, $buf, 10240))
	  or die("$orig: $!\n");
	last unless $r;
	for ( $w = 0; $w < $r; $w += $t ) {
	    $t = syswrite($out, $buf, $r - $w, $w)
	      or die("$new: $!\n");
	}
    }
    close($in);
    close($out) or die("$new: $!\n");
    utime($time, $time, $new);
}

sub copy_mpg {
    my ($orig, $new, $time, $rotate, $mirror) = @_;
    $time = (stat($orig))[9] unless defined($time);

    # I'm not sure what this does. The resultant file is about 10% of
    # the original, without missing something...
    my $cmd = "$prog_mencoder -of mpeg -oac copy -ovc ".
	($rotate ? "lavc -lavcopts vcodec=mpeg1video -vop rotate=".int($rotate/90)." " : "copy ") .
	  squote($orig) . " -o ". squote($new);
    warn("\n+ $cmd\n") if $verbose > 2;

    my $res = `$cmd 2>&1`;
    die("${res}Aborted\n") if $?;

    utime($time, $time, $new);
}

sub still {
    my ($el) = @_;

    my $new = d_large($el->assoc_name);
    my $still = new Image::Magick;
    if ( $prog_mplayer ) {
	my $tmp = "00000001.jpg";
	if ( -e $tmp ) {
	    die("ERROR: mplayer needs to create a file $tmp, but it already exists!\n");
	}
	my $cmd = "$prog_mplayer -really-quiet -nosound -frames 1 -vo jpeg " .
	  squote(d_large($el->dest_name));
	my $t = `$cmd 2>&1`;
	warn("$t\n") unless -s $tmp;
	$still->Read($tmp);
	unlink($tmp);
    }
    else {
	# This may take minutes.
	$still->Read(d_large($el->dest_name)."[0]");
    }

    # Get still dimensions.
    my ($hs, $ws) = $still->Get(qw(height width));
    unless ( $hs && $ws ) {
	$still->Read(d_icons("movie.jpg"));
	$still->Write($new);
	return $still;
    }
    # Scale to 640x480 if needed.
    my $r = $hs > $ws ? 640 / $hs : 640 / $ws;
    if ( abs($r - 1) > 0.05 ) {
	$still->Resize(width => $r*$ws, height => $r*$hs);
	($hs, $ws) = $still->Get(qw(height width));
    }

    # Create black canvas.
    my $canvas = new Image::Magick;
    $canvas->Set(size => ($ws+240).'x'.($hs+180));
    $canvas->ReadImage('xc:black');
    my ($hc, $wc) = $canvas->Get(qw(height width));

    # Place the still on top of it.
    # Center image
    $canvas->Composite(image => $still, compose => 'Atop', x => 120, 'y' => 90);
    # Bottom slice.
    $canvas->Composite(image => $still, compose => 'Atop', x => 120, 'y' => $hs+135);
    # Top slice. Cannot place at negative offsets, so crop the still first.
    $still->Crop(width => $ws, height => 45, x => 0, 'y' => $hs-45);
    $canvas->Composite(image => $still, compose => 'Atop', x => 120, 'y' => 0);
    undef $still;

    # Drill spocket holes.
    my $hole = new Image::Magick;
    $hole->Set(size => '60x40');
    $hole->ReadImage("xc:grey90");
    $hole->Draw(primitive => 'polygon', fill => "black",
		points => " 0,0   5,0   0,5");
    $hole->Draw(primitive => 'polygon', fill => "black",
		points => "60,0  55,0  60,5");
    $hole->Draw(primitive => 'polygon', fill => "black",
		points => "60,40 55,40 60,35");
    $hole->Draw(primitive => 'polygon', fill => "black",
		points => " 0,40  5,40  0,35");

    for ( my $v = 0; $v < $hc;  $v += 80 ) {
	for my $h ( 30, $wc-90 ) {
	    $canvas->Composite(image => $hole, compose => 'Atop',
			    geometry => "+$h+$v");
	}
    }

    $canvas->Write($new);
    my $time = $el->timestamp;
    utime($time, $time, $new);
    $canvas;
}

sub copy_voice {
    my ($orig, $new, $time) = @_;
    $time = (stat($orig))[9] unless defined($time);
    $orig =~ s/\.\w+$/.mpg/;
    return if -s $new;
    return unless $prog_mplayer;

    # This will produce an MP2 file. Good enough for now...
    my $cmd = "$prog_mplayer -vo null ".
      "-dumpaudio -dumpfile " . squote($new) . " " . squote($orig);
    warn("\n+ $cmd\n") if $trace;
    my $res = `$cmd 2>&1`;
    die("${res}Aborted\n") if $?;
    die("${res}Aborted\n") unless -s $new;

    utime($time, $time, $new);
}

sub indexicon {

    my @imgs;
    for ( my $i = 0; $i < $index_rows*$index_columns; $i++ ) {
	next if $i >= $num_entries;
	my $el = $filelist->byseq($i+1);
	my $file = $el->dest_name;
	my $img;
	if ( $el->type == T_REF ) {
	    $img = $el->assoc_name;
	}
	else {
	    $img = $el->type == T_MPG ? $el->assoc_name : $file;
	    $img = "thumbnails/$img";
	}
	push(@imgs, $img);
    }

    my $iconfile = "icon.jpg";
    my $ii = cache_entry(" indexicon ");
    if ( -f $iconfile && $ii && $ii->dest_name eq "@imgs" ) {
	return 0;
    }
    my $el = new ImageInfo($iconfile);
    $el->dest_name("@imgs");
    cache_entry(" indexicon ", $el);
    $cache_update++;

    my $image = new Image::Magick->new;
    foreach ( @imgs ) {
	$image->Read($_);
    }

    my $width = $thumb;
    my $height = int($thumb*0.75);

    $image = $image->Montage(tile=>"${index_columns}x${index_rows}",
			     texture=>"xc:gray90");
    $image->Resize(geometry=>"${width}x${height}");
    $image->Write($iconfile);
    1;
}

################ Subroutines ################

sub app_options {
    my $help = 0;		# handled locally
    my $ident = 0;		# handled locally

    # Process options, if any.
    # Make sure defaults are set before returning!
    return unless @ARGV > 0;

    if ( !GetOptions(
	# Run time options.
	'clobber'        => \$clobber,
	'dcim=s'         => sub { $import_dir = $_[1]; $import_exif++ },
	'exif'           => \$import_exif,
	'import=s'       => \$import_dir,
	'info=s'         => \$info_file,
	'link!'          => \$linkthem,
	'update'         => \$update,
	'mediumonly'     => \$mediumonly,

        # Album options. Can also be set in info/config files.
	'caption=s'      => \$caption,
	'cols|columns=i' => \$index_columns,
	'icon!'          => \$icon,
	'medium'         => sub { $medium = 0 },
	'mediumsize=i'   => \$medium,
	'rows=i'         => \$index_rows,
	'thumbsize=i'    => \$thumb,
	'title=s'        => \$album_title,

	# Miscellaneous.
	'debug'          => \$debug,
	'help|?'         => \$help,
	'ident'          => \$ident,
	'quiet'          => sub { $verbose = 0 },
	'test'           => \$test,
	'trace'          => \$trace,
	'verbose+'       => \$verbose,
        )
	 or $help
	 or @ARGV > 1
	 or @ARGV && ! -d $ARGV[0]
       )
    {
	app_usage(2);
    }

    app_ident() if $ident;
    $dest_dir = @ARGV ? shift(@ARGV) : ".";
    $dest_dir =~ s;^\./;;;
    if ( $import_dir ) {
	die("$import_dir: Not a directory\n")
	  unless -d $import_dir;
	$import_dir =~ s;^\./;;;
    }
}

sub app_ident {
    print STDERR ("This is $my_package [$my_name $my_version]\n");
}

sub app_usage {
    my ($exit) = @_;
    app_ident();
    print STDERR <<EndOfUsage;
Usage: $0 [options] [ directory ]
  Album:
    --info XXX		description file, default "@{[DEFAULTS->{info}]}" (if it exists)
    --title XXX		album title, default "@{[DEFAULTS->{title}]}"
    --[no]icon		[do not] produce an album icon
  Index:
    --cols NN		number of columns per page, default @{[DEFAULTS->{indexcols}]}
    --rows NN		number of rows per page, default @{[DEFAULTS->{indexrows}]}
    --thumbsize NNN	the max size of thumbnail images, default @{[DEFAULTS->{thumbsize}]}
    --captions XXX	f: filename s: size c: description t: tag
  Medium:
    --medium    	produce medium sized images of size @{[DEFAULTS->{mediumsize}]}
    --mediumsize NNN	the max size of medium sized images, default @{[DEFAULTS->{mediumsize}]}
    --mediumonly	ignore large images and links (for web export)
  Importing:
    --import XXX	original images
    --exif		use w/ EXIF info, if possible
    --dcim XXX		as --import with --exif
    --update		add new entries from import, if needed
    --[no]link		[do not] link to original, instead of copying. Default is link.
  Miscellaneous:
    --clobber		recreate everything (except large)
    --test		verify only
    --help		this message
    --ident		show identification
    --verbose		verbose information
EndOfUsage
    exit $exit if defined $exit && $exit != 0;
}

################ Modules ################

package ImageInfo;

my @std_fields;
my @exif_fields;
my $exif_rot;

INIT {
    @std_fields  = qw(type seq next prev
		      dest_name orig_name assoc_name
		      timestamp file_size medium_size
		      tag description annotation
		      rotation mirror);

    @exif_fields = qw(DateTime ExifImageLength ExifImageWidth
		      ExposureMode ExposureProgram ExposureTime
		      FNumber Flash FocalLength ISOSpeedRatings
		      ImageDescription Make Model
		      MeteringMode SceneCaptureType Orientation
		      height width file_ext);

    $exif_rot = { top_left   => [   0, ''  ],    # 1: corr. needed
		  top_right  => [   0, 'v' ],    # 2: flop (V)
		  bot_right  => [ 180, ''  ],    # 3: 180
		  bot_left   => [   0, 'h' ],    # 4: flip (H)
		  left_top   => [  90, 'h' ],    # 5: flip 90
		  right_top  => [  90, ''  ],    # 6: 90
		  right_bot  => [  90, 'v' ],    # 7: flop 90
		  left_bot   => [ 270, ''  ],    # 8: 270
		};
}

sub new {
    my ($pkg, $file) = @_;
    $pkg = ref($pkg) if ref($pkg);

    my $self = { $file ?
		 (orig_name    => $file,
		  dest_name    => ::basename($file)) : (),
		 description  => "",
		 annotation   => "",
		 tag	      => "",
	       };

    if ( $file && -f $file ) {
	my @st = stat(_);
	my $ii = ::cache_entry($file);
	if ( $ii  ){
	    $self = $ii;
	    delete($self->{$_}) foreach grep { /^_/ } keys(%$self);
	}

	# Else, get image info.
	else {
	    my $ii = Image::Info::image_info($file);
	    $self->{file_size} = $st[7];
	    $self->{timestamp} = $st[9];
	    unless ( exists($ii->{error}) ) {
		for my $key ( @exif_fields ) {
		    my $val = $ii->{$key};
		    next unless defined $val;
		    if ( $key eq "Orientation" ) {
			($self->{rotation}, $self->{mirror}) =
			  @{$exif_rot->{$val}}
			    if exists $exif_rot->{$val};
		    }
		    else {
			$val = $val->as_float
			  if UNIVERSAL::can($val,"as_float");
			$self->{$key} = $val;
		    }
		}
		::cache_entry($file, $self);
	    }
	}
	# Actualize.
	$self->{file_size} = $st[7];
	$self->{timestamp} = $st[9];
    }

    bless($self, $pkg);
}

INIT {
    no strict 'refs';
    for my $sub ( @std_fields, @exif_fields ) {
	$sub = "_".$sub if $sub eq "rotation";
	*{"ImageInfo::$sub"} = sub {
	    my ($self, $value) = @_;
	    $self->{$sub} = $value if defined($value);
	    $self->{$sub};
	};
    }
}

sub rotation  {
    my ($self) = @_;
    defined($self->{_rotation}) ? $self->{_rotation} : $self->{rotation};
}

sub html_name {
    my ($self) = @_;
    sprintf("img%04d.html", $self->seq);
}

package FileList;

use Class::Struct "FileList" =>
  [ _tally	=> '$',
    _data       => '$',
    _hash	=> '$',
  ];

sub add {
    my ($self, $el, $name) = @_;
    my $data = $self->_data;
    my $hash = $self->_hash;
    $self->_hash($hash = {}) unless $hash;
    $self->_data($data = []) unless $data;
    push(@$data, $el);
    $hash->{$name || $el->dest_name || ""} = $el;
    $self->_tally(($self->_tally||0)+1);
    $el->seq($self->_tally);
    $self;
}

sub byname {
    my ($self, $file) = @_;
    $self->_hash ? $self->_hash->{$file} : undef;
}

sub entries {
    my ($self) = @_;
    $self->_data([]) unless $self->_data;
    wantarray ? @{$self->_data} : $self->_data;
}

sub tally {
    my ($self) = @_;
    $self->_tally || 0;
}

sub byseq {
    my ($self, $seq) = @_;
    $self->_data ? $self->_data->[$seq-1] : undef;
}

#### Cache maintenance.

package ImageInfoCache;

use constant CACHE_VERSION => 3;

sub new {
    my ($pkg, $file) = @_;
    $pkg = ref($pkg) || $pkg;
    my $self = bless({}, $pkg);
    if ( defined($file) ) {
	$self->load($file);
	if ( ($self->{_version} || 1) != CACHE_VERSION ) {
	    warn("Incompatible cache version " . $self->version .
		 " -- invalidated\n") if $verbose;
	    $self = bless({}, $pkg);
	}
    }
    $self->{_version} = CACHE_VERSION;
    $self;
}

sub load {
    my ($self, $file) = @_;
    our $info;
    $info = undef;
    eval {
	require $file;
    };
    if ( $@ ) {
	warn("Illegal cache -- invalidated\n") if $verbose;
	return;
    }
    @{$self}{keys(%$info)} = values(%$info);
}

sub store {
    my ($self, $file) = @_;
    $Data::Dumper::Indent = 1;
    $Data::Dumper::Sortkeys = 1;
    $Data::Dumper::Sortkeys = 1; # avoid warnings
    $Data::Dumper::Purity = 1;
    my $cache = do { local *C; *C };
    open($cache, ">$file")
      and print $cache (Data::Dumper->Dump([$self],[qw(info)]), "\n1;\n")
	and close($cache);
}

sub entry {
    my ($self, $file, $entry) = @_;
    $file =~ s;^\./;;;
    if ( defined $entry ) {
	$self->{$file} = $entry;
    }
    else {
	$entry = $self->{$file};
    }
    $entry;
}

sub entries {
    my ($self) = @_;
    [ sort(keys(%{$self})) ];
}

sub version {
    my ($self) = @_;
    $self->{_version};
}

package main;

=head1 NAME

Album - create and maintain HTML based photo albums

=head1 SYNOPSIS

A photo album consists of a number of (large) pictures, small thumbnail
images, and index pages. Optionally, medium sized images can be
generated as well. The album will be organised as follows:

  index.html       first or only index page
  indexN.html      subsequent index pages (N = 1, 2, ...)
  icons/           directory with navigation icons
  large/           original (large) images, with HTML pages
  medium/          optional medium sized images, with HTML pages
  thumbnail/       thumbnail images

Each image can be labeled with a description, a tag (applies to a
group of images, e.g. a date), the image name, and some
characteristics (size and dimensions).

Images can be handled 'in situ', or imported from e.g. a CD-ROM or
digital camera. Optionally, EXIF information from digital camera files
can be taken into account.

=head1 DESCRIPTION

For a description how to use the program, see L<Album::Tutorial>.

=head1 AUTHOR AND CREDITS

Johan Vromans (jvromans@squirrel.nl) wrote this module.

Web site: http://www.squirrel.nl/people/jvromans/Album/index.html

=head1 COPYRIGHT AND DISCLAIMER

This program is Copyright 2004 by Squirrel Consultancy. All
rights reserved.

This program is free software; you can redistribute it and/or modify
it under the terms of either: a) the GNU General Public License as
published by the Free Software Foundation; either version 1, or (at
your option) any later version, or b) the "Artistic License" which
comes with Perl.

This program is distributed in the hope that it will be useful, but
WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See either the
GNU General Public License or the Artistic License for more details.

=cut

__END__

begin 644 index.png
MB5!.1PT*&@H````-24A$4@```"$````A"`,```!@.C)=````=5!,5$4```"M
MK:VKJZN5E963DY-U=W4[.SLW-S<O+R\I*2DF)R8A(2$='1W.SL[,S,S*RLK(
MR,@5%14/#P^^PKZ\O+P'!P>TN+2JJJJHK*B6EI9\?'QJ:FI86%@P,C`H*"@B
M(B+-S<W'Q\?!P<&_O[^[O[L&!@:UN;44R\/V````R4E$051XG,V4VQ*"(!1%
M3R:F&&GE+14U-?[_$QN.D0YJV%.M%_:,:U28LX&K"7BM?:;33PU!J`\Z/B5"
M&0D'B%V=&(`G@R$X>&G'=+J;!UR@0:`*9L\E004$#0II$RGNK%6Q97N@TNC]
MN`O?_Y<S1T6'18.1@<M">'B2,QJUC+5N'/'+!1J6C-9OC$LA.:!1RECJAFFW
MIURQ8[:*]M18X:MW;#EU\U[^Y=0_S8=YQLQSNF'6L2_1G+$OV+E%5.>PMTN,
;O=UV.ZSS!'/7.?2F!-OE`````$E%3D2N0F""
`
end
begin 644 medium.png
MB5!.1PT*&@H````-24A$4@```"$````A"`,```!@.C)=````:5!,5$4```"G
MIZ>5E96'AX=Y>7EU=W5U=74O+R\I*2DF)R8A(2'.SL[*RLH1$1$/#P^^PKZ\
MO+P'!P>TN+0#`P,!`0&JJJJHK*BFIJ:6EI9V=G9T='0P,C`H*"@0$!#!P<&_
MO[^[O[NUN;4"`@+$?8!#````P$E$051XG,74[0Z"(!B&X:</5-1,+;7$$CK_
M@TPAAP&&6VO=?_SAM>GD?<71%UY77IOQN1"$QC"+*1&3*!E0A&8%P$HE!$-4
M]8E9?XG`A!0$76K='TL[$"DH*B=(DBWH*'A<V(]0Y4K4"!?`7T7O$^VA^2S:
M!V;$(=K3<&2:V"(XRU.]-4LBF`X^:]PBT+.1;5QB>$F=>I=W<=]?Y^V^^:8_
M$OX9\\_IBEF7^Y+;Z7V1.^=LVCFYMZ[TWJ[[.RSW!!/T,=8!(V$7`````$E%
&3D2N0F""
`
end
begin 644 first.png
MB5!.1PT*&@H````-24A$4@```"$````A"`,```!@.C)=````;U!,5$4```"5
ME95U=W5O;V]555534U,]/3T[.SLO+R\I*2DF)R8A(2'.SL[,S,S*RLJ^PKZ\
MO+P'!P>TN+0#`P.JJJJHK*BBHJ*@H*">GIZ6EI9P<'!86%A45%0P,C`H*"C-
MS<W+R\N_O[^[O[NUN;4"`@)5ZT`7````T$E$051XG(W4V0Z",!`%T"N([`@(
M+L@BR_]_HW9&`BEMVOLR"9Q`:6?`U13\ZU3+F?9B=J(8<N+(F5=1=D`1R"F`
MKF0Q=PBK,9$SOD)T,PD'?7:X+Y+U<$A$J)0@24Z(A)CBXO@*3LZB1K"[^."2
MWG7"O7#UWAK1+#[5%FHQN(`0J0>-^`$A/F=H1`,2!)3"74@,+32"`7P&"O%D
M@!MTPOP,BW58?(O%?ECLJ?E<;,Y6W1_F'C/WJ46OT[SDQVSS0C.GS#IS-+>J
<;'-K]W?0YPL&.S)%W$I>4`````!)14Y$KD)@@@``
`
end
begin 644 first-gr.png
MB5!.1PT*&@H````-24A$4@```"$````A"`,```!@.C)=````8U!,5$4```"R
MK[*QK[&?FY^5E95U=W4O+R\I*2DF)R8A(2'.SL[*RLK#PL.^PKZ\O+R[NKL'
M!P>XMKBTN+2JJJJHK*BIIJF>FIZ6EI8P,C`H*"C-S<W+R\O"P<*_O[^[O[N[
MN;NUN;4M,E&?````STE$051XG(W4VPZ#(`P&X.J&HF[.TSK4J;S_4T[*C$9I
MX+]I(E\\0"L\?8%_G;MSYJ/00F9P3B:%WD2C`*KDG`I`-59H!6D[Y>=,GQ24
M)B&@+R[K)D4/@H2$U@GR_`[2B#FKKH^P*:WH(#E<'&T91D[4+UOC+R-J7*A&
MR(@:20PQ,F(%1@P1,L*`51!P"@*K(.`2%N`2(R,>-[OR1D[X[Q'P'@'?$K`?
M`7L:<"X!9^ON#W^/^?LTH-=I7LIK]GFAF7-FFSF:6U?VN0W[._#Y`1,--!>D
/,0GZ`````$E%3D2N0F""
`
end
begin 644 last.png
MB5!.1PT*&@H````-24A$4@```"$````A"`,```!@.C)=````;U!,5$4```"5
ME95U=W5O;V]555534U,]/3T[.SLO+R\I*2DF)R8A(2'.SL[,S,S*RLJ^PKZ\
MO+P'!P>TN+0#`P.JJJJHK*BBHJ*@H*">GIZ6EI9P<'!86%A45%0P,C`H*"C-
MS<W+R\N_O[^[O[NUN;4"`@)5ZT`7````T$E$051XG)V4V0Z",!!%KR`"!1$0
M7)!%EO__1M.I!`.=#/&\3&A/*+1SBXL$OG4HUPR_QNBH"&LBY8RSD3=`%JS)
M@"8WQM@@+/IX3?\,T8QD.&B3S;PF:>&0H5!8A3@^0&ECB++M$H;4&"4">KR=
MS?"=-5Z>&3ZYK(&:JC]5K`%/+^0#;L<9.+[)@,L:6M$&*M9`W9$QN:R!F@RC
MV`U<39D>?[]#_`[Q7\3]$/=4/!?Q;/G^D'M,[M,=O4YY2;<L>:',69DS1[FU
<L>1VW^W`\P$(+S)%*AO?S0````!)14Y$KD)@@@``
`
end
begin 644 last-gr.png
MB5!.1PT*&@H````-24A$4@```"$````A"`,```!@.C)=````=5!,5$4```"O
MK:^LJ:REH:6AG:&?FY^5E95U=W4O+R\I*2DF)R8A(2'.SL[,S,S*RLJ^PKZ_
MOK^\O+P'!P>TN+2TLK2SL+.JJJJHK*BGI*>BGJ*AGJ&@G*">FIZ6EI8P,C`H
M*"C+R\O$P\3`O\"_O[^_O;^[O[NUN;7'-O7)````UDE$051XG)V4ZQ*"(!!&
M-\M0-/-26DE>4GG_1RP7S09AUNG\V1'/`,)^PID"ICH4.L.O(1D/0"?@3,Y&
M5@&DGDX*4&7*D!7X>1?J=$\?*HD&@SI:O1^):F!H<,B-0A@>@8_&$*3K)12)
M,@KP\+&9AANK<8G5\*ZU&5?WA=6YMS9#N#B+(PZMS1!NC\9761NB[-&8%8,A
MRA@-\6AMQF<O:"C%:(CRINK^].\<Y#[(;R'/@SQ3\E[HN[7W!]UC=)]NZ'7,
H2[)FR0MFSLB<.<RMB26WV_X.=M[O[#PGJ]"<S`````!)14Y$KD)@@@``
`
end
begin 644 next.png
MB5!.1PT*&@H````-24A$4@```"$````A"`,```!@.C)=````8U!,5$4```"5
ME95U=W4Y.3DO+R\I*2DF)R8A(2$='1W.SLX;&QO*RLJ^PKZ\O+P'!P>VMK:T
MN+2TM+2RLK*JJJJHK*B6EI8P,C`P,#`H*"@<'!P:&AH8&!C!P<&_O[^[O[NU
MN;6SL[-4@WEY````LDE$051XG*64:P^"(!B%3Z08FN8MLHO2__^53<C1$'?<
M>KZPP3.N[P%G!K[MU(=,OX81,D-()H59C%H#51)2`;IVAM%(NU&%C-<4VEA#
M8"A6XS/%`&$-B2XJ*'6`G(TIJ]9+.$IG]$A\WXL:QS<S3H\+,_!LF(&\90;N
M+3.\LFD@;YB!V]]ST'W0L]#[H'=*WX6_;;0^>(WQ.MU1ZS8OY1J?%YNY*$OF
?;&YC^-SN^QVV^0#@"BB#A-7F#0````!)14Y$KD)@@@``
`
end
begin 644 next-gr.png
MB5!.1PT*&@H````-24A$4@```"$````A"`,```!@.C)=````6E!,5$4```"E
MH:6DH:25E95U=W4O+R\I*2DF)R8A(2'.SL[*RLK(R,B^PKZ\O+P'!P>TN+2J
MJJJKJ*NHK*BIIJFDH*2>FIZ6EI8P,C`H*"C+R\O(Q\B_O[^[O[NUN;7NS3(>
M````LDE$051XG*64V0Z#(!1$1XOB4I?:4JS*__]F(]1@$#,F/2\D<,)Z!]P9
M^+7+$++L#2-D@9!""K,9G0;:+*0%=.<,HY'W<QDROW-H8PV!L3J,KU0CA#4D
M^JA0EC?(U5B*]KB$HW'&@,SW?:CQF)B1O&IFJ+T2-U0Z,4,E$S.\<FJHM&:&
M>OX]!]T'/0N]#WJG]%WXVT;K@]<8K],+M6[STASQ>;&9B[)ESN8VAL_MM=_A
6G"\3.BJ6%4:2\P````!)14Y$KD)@@@``
`
end
begin 644 prev.png
MB5!.1PT*&@H````-24A$4@```"$````A"`,```!@.C)=````:5!,5$4```"5
ME96+BXN)B8F'AX=U=W4O+R\I*2DF)R8A(2'.SL[*RLJ^PKZ\O+RZNKH'!P<%
M!06TN+0#`P.JJJJHK*B6EI:*BHJ(B(AD9&1>7EXP,C`H*"C!P<&_O[^[O[L&
M!@:UN;4$!`0"`@*5DT73````N$E$051XG(V4VQ*"(!1%=Q<4-4/3M#"5^O^/
M;,0<"XESU@LSL(;KV>!$@4\[U"[#MV&$3."22&$6H]2`BEP4H,O9,!IQU:<N
M_36&-M80Z++-^$3605A#HO(*:;J#G(PA4=LE9O+9J!']]C\HXW`CC/WE'C::
M%\)&6R!L'$>$C7820D93(&R<GR`,>@[&/AAG8=P'XTX9[\)X6T]]T#5&URFC
KUFU>\BUK7FSFO"R9L[GUL>:6]SO\YPUUDRQAT]LVZ@````!)14Y$KD)@@@``
`
end
begin 644 prev-gr.png
MB5!.1PT*&@H````-24A$4@```"$````A"`,```!@.C)=````6E!,5$4```"?
MFY^5E95U=W4O+R\I*2DF)R8A(2'.SL[*RLJ^PKZ^O+Z\O+P'!P>TN+2TLK2J
MJJJHK*B>FIZ6EI8P,C`H*"C+R\O)R<F_O[^_O;^^O;Z[O[NUN;6UL[4C?\V)
M````M4E$051XG*74ZQ*"(!`%X&,H8GD/RY3>_S4;EQP+"':F\\<9_<8+[!'G
M5/`^KH.;]5,8(4NX*:4PNV@UT.1N&D"W5AB-HI^5F_E:0!L2`E/E7=]231`D
M)/H@4.H$N8FU;/Q'V-16#,B_S]]28GDFQ"/KXF(9Q[BX9`FQ@:@@$!,+@8BX
M6_#7/1COP?@6QGHPUI2Q+XR]#<Q'>L;2<\J8=>I+[>?H"W4NF+USU-M0CM[R
9_@Z_\P*'^R8LF<,MN@````!)14Y$KD)@@@``
`
end
begin 644 journal.png
MB5!.1PT*&@H````-24A$4@```"$````A"`,```!@.C)=````MU!,5$4```"Q
ML;&OKZ^GIZ>EI:6CHZ.AH:&?GY^5E96-C8V!@8%U=W5'1T<U-34O+R\I*2DF
M)R8C(R,A(2$='1W.SL[,S,S*RLH7%Q?(R,C$Q,3"PL*^PKZ\O+P'!P>VMK:T
MN+2TM+2JJJJHK*B8F)B6EI:*BHJ(B(B`@(!\?'QP<'!L;&QJ:FID9&1>7EY8
M6%A24E)`0$`P,C`H*"@<'!S-S<W)R<G'Q\?%Q<7!P<&_O[\,#`R[O[NUN;6:
M;P.+```!'4E$051XG)64[5:"0!"&IP]-@Y3%B=1`4\M0LL+*(+C_ZVIWEE5:
M=LN>/\,Y/&?.N\L,</L74-5BKE/4C=+Q?-#Q/:=4QC0%B'HZ$4`ZE4:90G^6
MHTY^WX>T),.!;=!X+PBVX)#AP0QW,><2L1U+[DCI@">,PH]R#$6V+\1-%;-+
M1BB-.?00/Q/."G&12$X;AIFZ,>PJ6KR1J)EFA/N+<A&9J.>:,7I6/"*N19W\
M.T=P09S9C2H'LQMCE]CP;JYB8<DQW)\J_F%<GT@R;MQ0I!?-4/>QXL:`>B6:
MD5U)EE:CGL-LO(^)D3#>Z/')G(/9SY(SXA7Q@RD>E$$S]NMWH3DU4\WI$;-.
J^Q(V.>P+[9P1M7.TMR8.>WO<W\'.-U^06#7=M;9;`````$E%3D2N0F""
`
end
begin 644 sound.png
MB5!.1PT*&@H````-24A$4@```"$````A"`,```!@.C)=````]E!,5$4```"G
MIZ>;FYN5E96-C8V'AX=[>WMY>7EU=W5S<W-M;6UK:VMC8V-/3T\[.SLY.3DW
M-S<O+R\I*2DF)R8C(R,A(2$='1W.SL[,S,P9&1G*RLK(R,@5%17&QL;`P,"^
MPKZ^OKZ\O+P'!P<%!06VMK:TN+0#`P.PL+"NKJZLK*RJJJJHK*BHJ*B>GIZ8
MF)B6EI:4E)22DI*0D)"&AH9\?'QX>'AT='1P<'!J:FIF9F9D9&1>7EY86%A4
M5%1$1$1"0D(^/CXZ.CHP,C`L+"PH*"@F)B;+R\O)R<G'Q\<4%!00$!"_O[\,
M#`R[O[L("`BUN;4$!`2SL[/L_AE0```!,4E$051XG+W4:5.#,!`&X/6HHO6B
M"*G$*VBKMM[BA7@AI6J+V/__9X0TH8$FZHPSOE_(9)\9$F87V/HIP)YQNYQ8
M%(EFF%".:6@)%XT`P-'+<0""QE`D`=1:/51.[Z0&04*%!J$]5D?=\PH.0:/"
M@%:Q:)-3;ZD/@*?`R$1L.L(K!I/73QUV5DR&H@UZ7I]9;0JWD8F;PGW_))K]
MY?OI-Y5XM_S9B6QM*<3")E^KA(O^36R30V)_(_:?=](;=QRE./J0?['=2__!
MOUI,Q:/\FUZLLUVW'DK%7K[KHBI?OM0%,2>([MTG7:T,D"#.<E%)SW10]3SO
M&",NLAZ+=`;"#22$"=JGK_-66E^[+0#$^I3U>H0QC@IU9/->I_-"QC.:%SIS
CTO"9HW,KRVAN?_=W4.<+?R9D,6RK%5X`````245.1*Y"8((`
`
end
begin 644 movie.jpg
M_]C_X``02D9)1@`!`0$`2`!(``#_VP!#``4#!`0$`P4$!`0%!04&!PP(!P<'
M!P\+"PD,$0\2$A$/$1$3%AP7$Q0:%1$1&"$8&AT='Q\?$Q<B)"(>)!P>'Q[_
MVP!#`04%!0<&!PX("`X>%!$4'AX>'AX>'AX>'AX>'AX>'AX>'AX>'AX>'AX>
M'AX>'AX>'AX>'AX>'AX>'AX>'AX>'A[_P``1"`!:`'@#`2(``A$!`Q$!_\0`
M'P```04!`0$!`0$```````````$"`P0%!@<("0H+_\0`M1```@$#`P($`P4%
M!`0```%]`0(#``01!1(A,4$&$U%A!R)Q%#*!D:$((T*QP152T?`D,V)R@@D*
M%A<8&1HE)B<H*2HT-38W.#DZ0T1%1D=(24I35%565UA96F-D969G:&EJ<W1U
M=G=X>7J#A(6&AXB)BI*3E)66EYB9FJ*CI*6FIZBIJK*SM+6VM[BYNL+#Q,7&
MQ\C)RM+3U-76U]C9VN'BX^3EYN?HZ>KQ\O/T]?;W^/GZ_\0`'P$``P$!`0$!
M`0$!`0````````$"`P0%!@<("0H+_\0`M1$``@$"!`0#!`<%!`0``0)W``$"
M`Q$$!2$Q!A)!40=A<1,B,H$(%$*1H;'!"2,S4O`58G+1"A8D-.$E\1<8&1HF
M)R@I*C4V-S@Y.D-$149'2$E*4U155E=865IC9&5F9VAI:G-T=79W>'EZ@H.$
MA8:'B(F*DI.4E9:7F)F:HJ.DI::GJ*FJLK.TM;:WN+FZPL/$Q<;'R,G*TM/4
MU=;7V-G:XN/DY>;GZ.GJ\O/T]?;W^/GZ_]H`#`,!``(1`Q$`/P#ZI\=^,O#?
M@?0I-9\3:I#I]HG0N?FD/]U5ZL?85\I^._VQ]5O]1.F?#?PJ7W,5CN+Y2\LG
MNL2<#\2?H*X[_@H)JHU7XCZ)-;27!LUTPQJK,?++K*Y+JO8D,H)ZD!?2O1/V
M8_!EA;_!+2O&-MIEK%-=^8LUP0#-(RSO'UZA?DZ<<T`>*I\1/CG\1_'/_")O
MXOO--U&0RAH%G^R1QE068$KR.F/RJ;XD_#SXM^$_"=UXEUSXA_;K:RV!DAUJ
MXDE^=U08#`=V]>F:T?A[%8P?ML20:A=I:V4M]>F>620(%!MI'ZGIS@5Z/^U]
MJOAU/AQJFEZ%K=E>B26V^6.Y21F&]6/0^U`'D'P>M?V@-=\/W/B/P%K^M7=I
M9SM;R0_VGN;<%#D"*1CD8<<@=37H_@W]K'QSX/UI_#_Q2\-O>/;D+.8XQ;W<
M60""5/RMP0?X>O6NG_8_\/F#X%1ZW:ZE!'/)>7$\D*R8D`5O+SP<C[@Z^OTK
MY^^*DG_"3_M0W$6H,]VMSJ]I:3;NKHHCB(]^%QF@#[_^%OQ3\%?$FR:X\+ZQ
M'<3(,RVDH\N>,>Z'G`]1D5W61ZU\/_&/X&Z9X3TB[^)?PE\37.C-I*&YGLY;
MEDEB`/6)QSG)QM/7UKH/@#^UM:W2VOA_XFC[-.1L36(T`C8^LRC[O^\!C/4`
M9-`'V!15>PO;2_LXKRQN(KFVF4/%+$P974]"".HJQ0`4444`%%%)O%`"Y'K1
M7"GXD:%/\68/AUI\\=WJ0LIKR\,;@K;*A4*C?[9+9QV`]Q10!\:?MQ6GE:KX
M>G"][N$D=.&C('ZFN%\*?$7XJ7GP_L/AMX,%Y'IUNTCN+"$M-*SR%_FDZJH)
M'`('KFO6/V\+/;;:?<;.(M5N(P1T&\9Q_P".?H:L_L?RH_PQNE^4O'JDBG`P
M=NR,CGZDUPYEC7@L.ZJ5SNR_"+%5O9MV/+]._9]^)6M2O>:K)I]G-)\SF\O0
M\K$]SLW?J:WT_92\7.H(\0:1_P!\O_A7U9IYD`!ALXQ_M.:UX6<K\Y0G_9KY
M9<0XJ;TLCV)Y31AW?S/A_7/@3\8/"$37FD037L2C<SZ5<L7''/R<,?P!K@/`
M?BO^QOB?I/C#7H)-7^R:@EW=1NWS3$-D\GOW_"OT=\4:D="\`^(M:BNU4V6E
MW-QL88.4B9N.>N0*^#_V6O`&E?$CXIC0]=2:33(K"XN;@0N4<`*$4@CIAW4^
M^,5]+E^,G6HN=5;'A8FE&G4Y8'M'QX^)G@;Q;\&-9N?!6H2(]PL,4]G,2DT+
M-,N5V]P0#R"1[]JXK]D[X>>"/'7A'Q3;>,;24&6XMXK&_B)62U=5<M@]"#N7
M(((.![$-^+_[+?B?PQYVH^$;@^(=+&2(Q@7"+V!'1C].OIVIO[-_Q7\-_#[0
M=3\$^,=#N;:6:]>YCOU4AX)"B)Y<B'G`V9[]2,5VTZT*BO%F$H2CJT9<OC;X
M@_LZ?$?4/"6A>*8=6L+-T8V\H\RVD1T#K\IY1MK#.TBOJ#X6?M6_#OQ3!%;>
M(ISX8U$A0RW9)@9C_=D`P!_O8^M?&/BB[M_&/Q_>6T=+JVU#6X886&2LD>](
MP>>V!7H'[8'A/P5H?]CZOX<T1M(U#49IA=0P29MF50IRJ'E&RW0''XUJ2?H)
MINJZ=J5JMUI]];7<#C*R02JZG\035II%4%F95`YR37Y<^#/AY\4+_P`+6VM^
M%I;I=/O`S(MMJ'E$[79#D9`ZJ:R_!T_Q#\<ZO'X>TOQ'JUQ,8F;9-J,@0(.N
M<GI_C0!^FOBOXA>"?"MLUSX@\4:381JN<27*[V^BC+,?8`U\I?&_]KB?48)M
M!^%EM<0-.#$VJ31?O<'C]RG.">S'D9Z`\CYVG\!7]G\5K#P1KEVJW-S<V\4T
MT)W[1+@Y&>I`->OVW@/POX(_:+^'NDVTSVVGW",]U<W4P)9AY@W$G`7H!T`H
M`I?L4Q:K:_M.PPZN+A+Y[*Y:Y%P3YA+1AOFSSDY!YHKI_A/J^DW_`.WY/=^&
M[RWO-*O&N8XIXLE'5;,YVD]?F3KWP>O6BBX&]^WE9[O"LDH3F'68G)!Z!HI.
M?U'YURG[&-SO\)Z[:;@?*ODDVXY&Y,9_\<_2O2?VY;/S/`>NR>6#Y4MK,#GI
M\R)G_P`>->0_L53<>*+8E?\`EU<#O_RU!_I7C9_&^`G\OS/6R65L7'YGTU:?
M9RPW0RSMZ#I7060"HNV+R!_+\JP;-[D#"3QPKZG`K:T]P<#[1]H;T/\`A7P5
M$^FQ:W9R/[5&HRZ1^SOXFG\^"0W,45JA48)\R558?]\EJ\=_X)SZ,6U?Q=XB
M="1!;P6<9`Z[V9V_]%I^==5^WEJ4=I\)-)TQ+=[>:^U9&?GATCC<G_QYEK=_
M8(T0V7P/GU(Y275-3FE5P!G8@6,?^/(]?=X;]W@;]SXZM[U8]JU&.W=GDM)A
M')_'&>,_AZUYE\1OA=X-\=P/_;FE1B\8`"\@&R=<=/F'7Z'->D:J;A&V7<,;
M_P!R51@FLF5U1"S%L'T&:^9K5I4JO-#W7]Q[.&IJ4+2U/C3XA_`SQ)\,[C_A
M,O"^OQ75MI;BZ65T$4\!4Y!P<J^..G7TKS#XC?$+Q%X_-@_B`V\DED)!&\,0
M3=OV[B<<?PBOL3]IV_\`LWP0\1R1W:2K+'%#M9<M\TJ+U^F:\^_99T33;_X0
M31ZGIUO>PW.IS/LN(0Z'"1KT8>J_SKWL-G$X8-UZRO9V.:>61J8CV4';2YA_
M#WX[>"?#O@'2M#ET_61=6-JL4@$2%'?'S,IW9P6SU&>:\W_9O\7^&O!/C'4M
M9\327@A;2Y;>V6VBWEI6>,KGG@84U]*W?P@^'-S,\TGA6S#,<D(SH/R#`5D>
M+/A%X"MO">LSZ=X;MXKQ=/G,#AW)1O+)4C+$9!%.GQ+A9R4;.[+GP_7BF^9'
MA.L^.FUGX\V_COPYH5YJ!MI(9H+.1#N=HT`!.S/&X`_3TKT:V^%/Q"^,.L6V
MN>.KBU\/V4*;(X8HMTVPG)`3/'U8\9Z&M_\`9%^RR?#*0B%1*FI2I(RJ-S?*
MA&3_`,"_2OH73$*Q<0")".`3DGWK#'YY5IU94:<;6ZCH953=*-63O<^8/A5X
M9TKP#^W!HOA[2O.^Q1PNL6]MSY>P8DD^[$G\>/2BMZYC2#]O_P`-3%L>=$K-
MN/<VLJ@?H**]_"S=2A"4GK8\3$02JR2/2_VR[3[1X!\1IY8;=IT<QR?[D@.?
MPVBOC?X+_$5/AW/J]S_9YO9KR!$B&_:%96)Y/7&":^YOVJ+/[5X*UM-@9I-"
MN0N3P2$<C]2*^./V0O"NG^+_`(M'3-0T^WO1%I\MQ"L_W$D5TPY'?`+<'(R0
M>H%:UJ,*T'3FKIA2JSHS4X/5%#Q/\:/B=>[+@W[Z3:SY,*V]N$#`>C$$GKUS
M7H.E:1^TM;P+=VOB3'R[DB>\B;</H5*_G5?]M6P2VF\+RPQ!%5;J$[0`HP8B
M`!^+5]0V^C6-A\/M!U*WU#S_`+1:6W!((.Z'.016<,%AX*R@ON-)XJM-WE-_
M>?"?Q3^)_C7XAVNFZ5XJEBN9-&>?RVABVL=^T-NVG:<;."`.IKZM_96^,/PR
MM_AIH/@2XUC^S-4LX"CQWD?E)+([EV*/RIRS'`)!]J\%_9;TE]5^-.M,+0W2
M6ME<R.NW=@&5$R1W'S8K2_:Y\,^&]!MM(O=,TF"QU*]N)!*T0*;E0#.5Z9RP
MYZU53#PG#D6ABIM2N?;5Y(1%OMKM+NU<9P6#8'^%93DA243<?05\?_"VQ^-6
MA^#-,\2^$-;CU&RND,K:7=/O`4,0``W`R!GY2.*],\(?M'>'[B[;1_&MC<>&
M-6@?RYO-1GA5P<<_Q+^(_'O7RF891B(OGAJO+?[CV\'C*5K-V]1G[9=U:P_"
M-D16CGN-0@B*GY=PPS_C]VG_`+,MK/;?!/178.J7#SR\]/\`7.O\E!KE_P!M
M'Q!9:KX`\.KIU[9WMK<Z@\R3VLJRH^R,@\CH?WG2O0?@=9I;?"#PS$DNUFL%
ME:-CC[Y+?C]ZN;%0]GE,(M;R_P`ST<)+FQS?11.P'2H+R!;BTFMWP5E1D8$9
M&",5.*",U\U%VDF?1R5TT>&?L;331>']?TQ0!-;:D&8$<@L@7G_O@U])V!8#
M$UR)9"/N@]*^;/V<D6P^)7Q'T<[E2/4`4&/X5EF&<>^5KZ!.JZ3HNF2ZAJ$\
M&GV,0)ENKF0(OYG^E>[F<7+'2MJW9_@CP*#2PJOTNOQ/$?',<4/[<G@-QA3+
M';LQ)X)W3*/T`%%<=J7CS2/B#^UMX$U+189!:6FI6=HDSC!GVW!;?CL/GP,T
M5]S@H.&'A&:LTCY/%3O5;CL?7/QWM!=Z+Y&T'S[2YA.[H<J*_/'X'?$:[^%O
MC8^*;"QCOK@6DMNL$CE4._'+8Y(!`.!C..HK])?BM&KV%FQ&1YC*1ZY'3]*\
M*\#_`+/GA;372YM?#<FI39)$M[\RC_@)^7]*ZC$^3/'WC7QE\4-8\Z_A>YV2
M.\%I9VY*1;CS@#)[=R>E45T?XCK&D:Z7XK"(`$46]QA<<#`QQ7Z+Z=\/=1MK
M58;:VL;.)1Q$F%`_!1@58?P-K2@D/;-CH`Y_PH`_/+P%XJ^(7PGUYO$.D6M[
MI=Q,A@E:[LVV3+D,4;>.>0#Z\5/\9OBIJ?Q.FT^YU73K:RGM/.9_(9MDC2%2
M2%/W<;?4]:^_6\/^(K#=LM79#PRH0RL/0CO7G&K_``J^'6JWDH\1>$XH_,5@
MSVJ_9Y58_P`0Q@9SF@"U\'H_"]S\'-`D\/\`B:RU">RTVV2]M4<&2&8HH=2!
MR`&+<D<XZFODGPS90>+OVCFM[J%;BVN];N)98V&0\:N[D$#V6O9O&/[->G::
ML>L_#7QO>VUZC_);78*LG'7S$P1R/0YKS[P#X;^)_P`&?'=IX[E\"3ZS#:^<
MFY%,L3AT9&8,F2#ACR1WZ4`6_P!IGX=^%?!_A^QU/08KFUENK[RVM_-+0[=C
M$D`]#D*!STSQ6]\(/%_Q6;X?V-W8>'=+US1K0?9(8U;R;G9&`O!!P?3)!Z5Q
M/[1OQ9TWXF0:7]@T:ZTB2WGEDN;64@JA*H%"D?>_BR2`?:O<OA1-X=\/_L[Z
M1<67B#3[F]33[BYN;5)E\R%SND(8`YX#`=*PQ&&HXB/+5BFC:CB*E&7-3=F<
MMI?[2/AN=S'>Z)JELX'/EA9`,#GH0<5=E_:,\"JC%(-4=@.%\@<G\Z\^_8L\
M,7VN_$+5-7MX/.32].9F;.,/(P`Z^P>J?[7UBL?Q)TM[:*-/M&EH-L:X)82R
M\GU/('X5Y3X<P+=[/[STUGN+2M=?<8UK\6KC1/B%XD\5>']+C`U<;42ZR?*R
M5.XA3@G(/?O4/CR3XD^+/!B>./%6H.^C&18[6,N%1B25RD:\`?*>:]G_`&J]
M(L=!^$\>AN;2VO;6XMF\A2@=P%(S@=?O9->6^)O'NGZY\(=`^'&@Z=>7VH)%
M"9I%7A95))11C+=>O`^M>I3PM&#YE'7:_IL>;4Q-6HK2>G^9W&L^%].\$?$C
MX`RZ;8QQ_P!HFQNYRH(\R22:+.6ZD@,#^/I17=_LT?!'7-<US3O'7Q/U&XN;
MC1!!%I.G-+N\D1*OEECT&W:I"CN,GFBNC<P/KJ:"*;:)HDD"G*[E!P?7Z\T\
M*`,`#%.HH`****`#ZU6N[&TO(S'=6T4RGLZYJS10!R6I>!M.GRUH[VS>GWE_
M6LV/1?%6B+MTZ=+JWSS$#Q_WR>GX&N_I#WH`^?\`7?`?A+6->:\\8^#+2]W,
M[3%K8+(=V?XA@]3GK7&^-_@1\(]0>)O#FFZCI64(E6*Y?`/88<M[]Z^L'1&R
M&16'N*Q]8L+%T!>RMF.[O$I_I0!\W^#?V=[/PK;7%]X5^+^OZ"][`IN(;61%
MWX!(5O[V,G!/(R?6N1N_V>H_$^J?;?$_Q+U:4P1A8Y+B+S7QG.%YX_QKZL;3
M=.W?\>%KU_YXK_A3FTS3=I/]GVG7_GBO^%`'RO#^SGX2FU@S76K:_KP^4_Z0
MX5Y#CG.,G&?TKVGX;?!?0M`(DL]#M-)C8#<57=/(/0L<M^M>O6%O;PQ*(H(H
BP%Z*@%63]X#MB@"&QLK>QMEM[2%8HUZ!1^OUHJS10!__V0``
`
end
