#!/usr/bin/perl -w
my $RCS_Id = '$Id$ ';

# Author          : Johan Vromans
# Created On      : Tue Sep 15 15:59:04 2002
# Last Modified By: Johan Vromans
# Last Modified On: Tue Jun 22 11:11:52 2004
# Update Count    : 1313
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
my $import_exif = 0;
my $import_dir;
my $add_new = 0;		# add new from import
my $dest_dir = ".";
my $image_info;
my $linkthem = 1;		# link orig to large, if possible
my $clobber = 0;
my $verbose = 0;		# verbose processing

# These are left undefined, for set_parameter_defaults.
my $index_columns;
my $index_rows;
my $thumb;
my $medium;			# medium size, between large and small
my $album_title;
my $caption;

# Development options (not shown with -help).
my $debug = 0;			# debugging
my $trace = 0;			# trace (show process)
my $test = 0;			# test mode.

# Process command line options.
app_options();

# Post-processing.
$trace |= ($debug || $test);

################ Presets ################

use constant DEFAULTS => { info       => "info.dat",
			   title      => "Photos",
			   mediumsize => 915,
			   thumbsize  => 200,
			   indexrows  => 3,
			   indexcols  => 4,
			   caption    => "fct",
			 };

my $TMPDIR = $ENV{TMPDIR} || $ENV{TEMP} || '/usr/tmp';

my $LGREY = "#E0E0E0";
my $MGREY = "#D0D0D0";
my $DGREY = "#C0C0C0";

my $fontfam = "font-family: Verdana, Arial, Helvetica";
my $css = <<EOD;
body  { font-size: 80%; $fontfam; }
td    { font-size: 80%; $fontfam; }
p.hd  { font-size: 140%; font-weight: bold; $fontfam; }
p.ft  { font-size: 80%; $fontfam; }
EOD
my $bodyatts = "text='#000000' link='#000000' vlink='#000000'".
               " alink='#FF0000' bgcolor='$DGREY'";
my $suffixpat = qr{\.(?:jpe?g|png|gif|mpg)}i;

my %capfun = ('c' => \&c_caption,
	      'f' => \&f_caption,
	      's' => \&s_caption,
	      't' => \&t_caption,
	     );

my $br = br();

use constant T_JPG   => 1;
use constant T_MPG   => 2;
use constant T_VOICE => 3;

################ The Process ################

use File::Path;
use File::Basename;
use Time::Local;
use Data::Dumper;

# The list of files, in the order to be processed.
my $filelist = new FileList;

# Storage for image info. Will be cached.
my $info;

# Individual file properties:
my %seen;			# to keep track
my %missing;			# to keep track

my %newfiles;			# info for new files
my $add_src = 0;		# * seen in info
my $journal;			# create journal

# Load image names and info from the info file, if any.
load_image_info();

# Apply defaults for other settings.
set_parameter_defaults();

# Load cached info, if possible.
load_cache();

# If files are to be imported, gather their names.
load_new_files() if $add_new && $import_dir;
load_src_files() if $add_src;

# Add image names from the source directory, if needed.
get_image_names() if $add_new || $add_src;
if ( %missing ) {
    foreach ( sort keys %missing ) {
	warn("$_: Missing\n");
    }
    die("Aborted!\n");
}

my $num_entries = $filelist->tally;
print STDERR ("Number of entries = $num_entries",
	      $add_new ? " ($add_new added)" : "",
	      "\n") if $verbose;
die("Nothing to do?\n") unless $num_entries > 0;

# Clean up and create directories.
if ( $clobber ) {
    rmtree([d_thumbnails(), d_medium()], 1);
}
mkpath([d_large(), d_thumbnails(), d_icons()], 1);
mkpath([d_medium()], 1) if $medium;

# Copy the button images over to the target directory.
add_button_images();

# Copy images in place, rotate if necessary, and create the thumbnails.
prepare_images();

# Update cache.
update_cache();

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
print STDERR ("Creating pages for ", $num_entries, " image",
	      $num_entries == 1 ? "" : "s", "\n") if $verbose;
my $mod = 0;

for my $el ( $filelist->entries ) {
    write_image_page($el, "large") && $mod++;
    write_image_page($el, "medium") && $mod++ if $medium;
}
uptodate("image", $mod) if $verbose;

# Write the index pages.
print STDERR ("Creating pages for ", $num_indexes, " index",
	      $num_indexes == 1 ? "" : "es", "\n") if $verbose;
$mod = 0;
for my $i ( 0 .. $num_indexes-1 ) {
    write_index_page($i) && $mod++;
}
uptodate("index", $mod) if $verbose;

# Cleanup excess indices.
for (my $i = $num_indexes ; ; $i++ ) {
    unlink(d_dest("index$i.html")) or last;
}

exit 0;

################ Subroutines ################

# Note: the HTML generators use the file names relatively.
sub d_large      { unshift(@_, "large");      goto &d_dest; }
sub d_medium     { unshift(@_, "medium");     goto &d_dest; }
sub d_thumbnails { unshift(@_, "thumbnails"); goto &d_dest; }
sub d_icons      { unshift(@_, "icons");      goto &d_dest; }
sub d_journal    { unshift(@_, "journal");    goto &d_dest; }
sub d_dest       { join("/", $dest_dir, @_); }

sub set_parameter_defaults {

    $album_title ||= DEFAULTS->{title};

    # Other settings.
    $index_rows ||= DEFAULTS->{indexrows};
    $index_columns ||= DEFAULTS->{indexcols};
    $thumb ||= DEFAULTS->{thumbsize};
    $medium ||= 0;

    # Caption values.
    $caption ||= DEFAULTS->{caption};
    die("Invalid value for caption: $caption\n")
      unless $caption =~ /^[fsct]+$/i;
    $caption = lc($caption);
}

sub load_image_info {

    my %typemap = ( 'p' => T_JPG, 'm' => T_MPG, 'v' => T_VOICE );

    # If an info has been supplied, it'd better exist.
    if ( $image_info ) {
	die("$image_info: $!\n") unless -s $image_info;
    }
    else {
	# Try default.
	$image_info = d_dest(DEFAULTS->{info});
	unless ( -s $image_info ) {
	    $add_new++ if $import_dir;
	    $add_src++ if -d d_large();
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
    die("$image_info: $!\n")
      unless open($fh, $image_info);

    my $el;
    local($/) = $/;
    while ( <$fh> ) {
	chomp;
	next if /^\s*#/;
	next unless /\S/;

	if ( /^\s+/ && $el ) {
	    $el->descriptions($el->description . "\n" . $_);
	    next;
	}

	if ( /^!\s*(\S.*)/ ) {
	    $_ = $1;
	    if ( /^title\s+(.*)/ ) {
		$album_title ||= $1;
	    }
	    elsif ( /^page\s+(\d+)x(\d+)/ ) {
		$index_rows ||= $1;
		$index_columns ||= $2;
	    }
	    elsif ( /^thumbsize\s*(\d+)/ ) {
		$thumb ||= $1;
	    }
	    elsif ( /^mediumsize\s*(\d+)/ ) {
		$medium = $1;
	    }
	    elsif ( /^medium\s*(\d+)?/ ) {
		$medium = $1 || DEFAULTS->{mediumsize};
	    }
	    elsif ( /^tag\s*(.*)/ ) {
		$tag = $1;
	    }
	    elsif ( /^caption\s*(.*)/ ) {
		$caption ||= $1;
	    }
	    elsif ( /^journal\s*(.*)/ ) {
		$journal++;
		# $/ = "";	# para mode
	    }
	    else {
		warn("Unknown control: !$_\n");
		$err++;
	    }
	    next;
	}
	($file, my $a) = split(' ', $_, 2);
	if ( $file eq "*" ) {
	    $add_src = 1;
	    $el = undef;
	    next;
	}

	$el = undef, next if $seen{$file};

	my $rotate = 0;
	my $type = T_JPG;
	while ( $a && $a =~ /^-(\w):(\S+)\s*(.*)/ ) {
	    if ( lc($1) eq 'o' ) {
		$rotate = 90 * ($2 % 4);
	    }
	    elsif ( lc($1) eq 't' ) {
		$type = $typemap{lc($2)}
		  or warn("$file (info): Illegal type: $2\n");
	    }
	    $a = $3;
	}
	$el = new FileEntry
	  (dest_name   => $file,
	   description => $a || "",
	   orientation => $rotate,
	   type        => $type);
	$el->tag($tag) if $tag;
	if ( $file =~ /^(.+)\.mpg$/i ) {
	    $el->type(T_MPG);
	    $el->assoc_name($1."s.jpg"); # associates still image
	}
	elsif ( $type == T_VOICE ) {
	    (my $t = $file) =~ s/\.jpg$/.mp3/i;
	    $el->assoc_name($t);
	}
	unless ( -s d_large($file) ) {
	    warn("$file (info): Missing\n");
	    $missing{$file} = $el;
	}
	else {
	    $seen{$file} = $el;
	}
	$filelist->add($el) unless $el->description =~ /^--/;
    }
    close($fh);
    die("Aborted\n") if $err;
}

sub load_src_files {
    my $dh = do { local *DH; *DH; };
    opendir($dh, d_large())
      or die("Cannot opendir " . d_large() . ": $!\n");

    foreach my $f ( sort grep { !/^\./ && /$suffixpat$/ } readdir($dh) ) {
	my $el = new FileEntry
	  (type => T_JPG, orig_name => $f, dest_name => $f);
	if ( $f =~ /^(.+)\.jpg$/ ) {
	    my $m = "$1.mp3";
	    if ( -s d_large($m) ) {
		$el->type(T_VOICE);
		$el->assoc_name($m);
		warn("$f: Changed to VOICE\n");
	    }
	}
	elsif ( $f =~ /^(.+)\.mpg$/ ) {
	    warn("$f: Changed to MPG\n");
	    $el->type(T_MPG);
	    $el->assoc_name($1."s.jpg");
	}
	$newfiles{$f} = $el;
    }

    close($dh);
}

sub load_new_files {
    my $dh = do { local *DH; *DH; };
    opendir($dh, $import_dir)
      or die("Cannot opendir $import_dir: $!\n");

    foreach my $f ( sort grep { !/^\./ && /$suffixpat$/ } readdir($dh) ) {
	if ( $import_exif ) {
	    do_exif($f);
	}
	else {
	    my $el = new FileEntry
	      (type => T_JPG, orig_name => $f, dest_name => $f);
	    if ( $f =~ /^(.+)\.mpg$/i ) {
		$el->type(T_MPG);
		$el->assoc_name($1."s.jpg");
	    }
	    $newfiles{$f} = $el;
	}
    }

    close($dh);
}

sub do_exif {
    my ($file) = @_;

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

    my $clashcheck = sub {
	my ($file, $new, $ext) = @_;
	$new .= "00";
	my $clash = 0;
	while ( $newfiles{"$new.$ext"} && !$missing{"$new.ext"} ) {
	    print STDERR ("Import $file -> $new.$ext clashes with ",
			  $newfiles{"$new.$ext"}->dest_name, "\n")
	      if $verbose;
	    $clash = 1;
	    $new++;
	}
	print STDERR ("Import $file -> $new.$ext\n") if $verbose && $clash;
	$new;
    };

    # Normal still image.
    if ( $file =~ /^(dsc0)(\d+)\.(jpg)$/i ) {
	my ($type, $seq, $ext) = ($1, $2, $3);
	my $exif = get_exif("$import_dir/$file");
	my $fd = $exif->{"date/time"} || "";
	if ( $fd =~ /(\d\d\d\d):(\d\d):(\d\d) (\d\d):(\d\d):(\d\d)/ ) {
	    my $time = timelocal($6,$5,$4,$3,$2-1,$1);
	    my $new = $clashcheck->($file, "$1$2$3$4$5", $ext);
	    my $ii = $info->entry("$new.$ext");
	    if ( $ii && !$ii->orig_name ) {
		my $f = "$import_dir/$file";
		$f =~ s;^\./;;;
		$ii->orig_name($f);
		$info->entry("$new.$ext", $ii);
	    }

	    $newfiles{"$new.$ext"} =
	      new FileEntry (type => T_JPG, orig_name => $file,
			     dest_name => "$new.$ext",
			     timestamp => $time);
	    $file = "$new.$ext";
	}
	else {
	    warn("$file: Missing or unparsable file date [$fd]\n");
	    $newfiles{$file} =
	      new FileEntry (type => T_JPG, orig_name => $file,
			     dest_name => $file);
	}
	if ( ($exif->{orientation}||"") =~ /^rotate (\d+)$/i  ) {
	    $newfiles{$file}->orientation(int($1/90));
	}
    }

    # Still image + sound clip.
    elsif ( $file =~ /^(dsc0)(\d+)\.(mpg)$/i ) {
	my ($type, $seq, $ext) = ($1, $2, $3);
	(my $f = $file) =~ s/\.mpg$/.jpg/;
	my $exif = get_exif("$import_dir/$f");
	unless ( $exif ) {
	    warn("$file: Clip without still image?\n");
	    return;
	}
	my $fd = $exif->{"date/time"} || "";
	if ( $fd =~ /(\d\d\d\d):(\d\d):(\d\d) (\d\d):(\d\d):(\d\d)/ ) {
	    my $time = timelocal($6,$5,$4,$3,$2-1,$1);
	    my $new = $clashcheck->($file, "$1$2$3$4$5", $ext);
	    my $ii = $info->entry("$new.$ext");
	    if ( $ii && !$ii->orig_name ) {
		my $f = "$import_dir/$file";
		$f =~ s;^\./;;;
		$ii->orig_name($f);
		$info->entry("$new.$ext", $ii);
	    }

	    # Since we process alphabetically, the .jpg should already
	    # be there.
	    $newfiles{"$new.jpg"}->type(T_VOICE);
	    $newfiles{"$new.jpg"}->assoc_name("$new.mp3");
	    $file = "$new.$ext";
	}
	else {
	    warn("$file: Missing or unparsable file date [$fd]\n");
	    (my $t = $file) =~ s/\.jpg$/.mp3/i;
	    $newfiles{$file} =
	      new FileEntry (type => T_VOICE, orig_name => $file,
			     dest_name => $file,
			     assoc_name => $t);
	}
    }

    # MPEG movie.
    elsif ( $file =~ /^(mov0)(\d+)\.(mpg)$/i ) {
	my ($type, $seq, $ext) = ($1, $2, $3);
	# We have to trust the file date...
	my $time = (stat("$import_dir/$file"))[9];
	my @tm = localtime($time);
	my $new = $clashcheck->($file,
				sprintf("%04d%02d%02d%02d%02d",
					1900+$tm[5], 1+$tm[4], @tm[3,2,1]),
				$ext);
	my $ii = $info->entry("$new.$ext") || new ImageInfo::Entry;
	if ( !$ii->orig_name ) {
	    my $f = "$import_dir/$file";
	    $f =~ s;^\./;;;
	    $ii->orig_name($f);
	}

	$newfiles{"$new.$ext"} =
	  new FileEntry (type => T_MPG, orig_name => $file,
			 dest_name => "$new.$ext",
			 assoc_name => $new."s.jpg",
			 timestamp => $time);
	$file = "$new.$ext";
	$info->entry("$new.$ext", $ii);
    }

    # Assume ordinary JPEG.
    else {
	# Copy as is.
	$newfiles{$file} =
	  new FileEntry (type => T_JPG, orig_name => $file,
			 dest_name => $file);
    }
}

sub get_image_names {

    my $newinfo = "";
    my $pdate = qr/(\d{4})(\d\d)(\d\d)\d{4}(?:\d\d|\w)/;
    my $date = "";
    $add_new = 0;

    my $t = "";
    foreach my $file ( sort(keys(%newfiles)) ) {
	next if $seen{$file}++;

	my $el = $newfiles{$file};

	my ($y,$m,$d) = $file =~ /^$pdate\./io;
	($y,$m,$d) = (0,0,0) unless defined($y);
	if ( "$y$m$d" ne $date ) {
	    $newinfo .= "\n!tag ";
	    $date = "$y$m$d";
	    if ( $date ne "000" ) {
		$t = sprintf("%02d/%02d/%04d", $d, $m, $y);
		$newinfo .= $t . "\n";
	    }
	    else {
		$newinfo .= "\n";
		$t = "";
	    }
	}

	$el->description("") unless $el->description;
	$el->orientation(0)  unless $el->orientation;
	$el->tag($t)         unless $el->tag;

	if ( $missing{$file} ) {
	    delete $missing{$file};
	}
	else {
	    $filelist->add($el);
	    $newinfo .= "$file " .
	      ($el->orientation ? ("-O:".$el->orientation." ") : "") .
		($el->type == T_VOICE ? "-T:V " : "") .
		  " \n";
	    $add_new++;
	}
    }

    unless ( $add_new ) {	# nothing to add
	warn("No new images imported\n") if $verbose;
	return;
    }
    unless ( -w $image_info ) {
	warn("$image_info: Cannot update (".
	     (-e _ ? "no write access" : "does not exist") .
	     ")\n");
	return;
    }
    my $infosize = -s $image_info;

    # Append new info.
    warn("Updating $image_info\n") if $verbose;
    my $fh = do { local *F; *F };
    open($fh, ">>", $image_info) || die("$image_info: $!\n");
    unless ( $infosize ) {
	print $fh ("# album control file created by $my_name $my_version, ".
	       localtime(time), "\n\n");
	print $fh ("!title $album_title\n") if $album_title;
	print $fh ("!medium\n") if $medium;
	print $fh ("!mediumsize $medium\n")
	  if $medium && $medium != DEFAULTS->{mediumsize};
	print $fh ("!thumbsize $thumb\n")
	  if $thumb != DEFAULTS->{thumbsize};
	print $fh ("!page ${index_rows}x${index_columns}\n")
	  if $index_rows != DEFAULTS->{indexrows}
	      || $index_columns != DEFAULTS->{indexcols};
    }
    else {
	print $fh ("\n");
    }
    print $fh ("# New entries added by $my_name $my_version, ".
	       localtime(time), "\n",
	       $newinfo,
	       "\n");
    close($fh);
}

sub prepare_images {

    foreach my $el ( $filelist->entries ) {
	my $file = $el->dest_name;
	print STDERR ("$file: ") if $verbose;

	# Check for directory names, e.g. f01/p01.jpg.
	my $dn = dirname($file);
	if ( $dn && $dn ne "." ) { # we have a dir name.
	    mkpath([d_thumbnails($dn), d_large($dn)], 1);
	    mkpath([d_medium($dn)], 1) if $medium;
	}

	my $i_large = d_large($file);
	my $w;
	my $h;
	my $i_src;
	my $movie = $el->type == T_MPG;

	# Copy the file into place. Rotate if needed.
	if ( ! -s $i_large && $import_dir ) {
	    $i_src = "$import_dir/" . $newfiles{$file}->orig_name;
	    if ( $movie ) {
		copy_mpg($i_src, $i_large,
			 d_large($el->assoc_name),
			 $newfiles{$file}->timestamp,
			 $el->orientation);
	    }
	    elsif ( $import_exif ) {
		# Unfortunately, jhead cannot rotate from->to, so
		# we need to copy first and rotate later.
		my $time = $newfiles{$file}->timestamp;

		if ( $linkthem && !$newfiles{$file}->orientation ) {
		    print STDERR ("link ") if $verbose;
		    unless ( link($i_src, $i_large) == 1 ) {
			unlink($i_large); # just in case
			print STDERR ("copy ") if $verbose;
			copy($i_src, $i_large, $time);
		    }
		}
		else {
		    print STDERR ("copy ") if $verbose;
		    copy($i_src, $i_large, $time);
		}
		if ( $newfiles{$file}->orientation ) {
		    print STDERR ("rotate ") if $verbose;
		    my $cmd = "jhead -autorot ".squote($i_large);
		    my $t = `$cmd 2>&1`;
		    print STDERR $t if $?;
		    utime($time, $time, $i_large);
		}
		print STDERR ("[", bytes(-s $i_large), "] ") if $verbose > 1;
	    }
	    elsif ( $el->orientation ) {
		print STDERR ("rotate ") if $verbose;
		my $t = convert
		  ($i_src, $i_large,
		   $verbose ? "-verbose" : (),
		   "-rotate", 90 * $el->orientation);
		print STDERR ("[", $t, "] ") if $verbose;
		($w, $h) = $t =~ /^(\d+)x(\d+)/ unless $w && $h;
	    }
	    else {
		print STDERR ("copy ") if $verbose;
		copy($i_src, $i_large);
		print STDERR ("[", bytes(-s $i_large), "] ") if $verbose > 1;
	    }
	    if ( $el->type == T_VOICE ) {
		copy_voice($i_src, d_large($el->assoc_name),
			   $newfiles{$file}->timestamp);
	    }
	}
	if ( $movie ) {
	    $info->entry($file,
			 new ImageInfo::Entry
			 (width => 0, height => 0,
			  large_size => -s $i_large));
	    $movie = $file;
	    $file = $el->assoc_name;
	    $i_large = d_large($file);
	}

	my $i_medium = d_medium($file);
	my $i_small  = d_thumbnails($file);

	if ( $medium && ! -s $i_medium ) {
	    print STDERR ("medium ") if $verbose;
	    my $t = convert
	      ($i_large, $i_medium,
	       $verbose ? "-verbose" : (),
	       # Read the docs.
	       "-size", "${medium}x$medium", "-resize", "${medium}x$medium",
	       # Remove unnecessary stuff.
	       "+profile", "*");
	    print STDERR ("[", $t, "] ") if $verbose > 1;
	    ($w, $h) = $t =~ /^(\d+)x(\d+)/ unless $w && $h;
	}

	if ( ! -s $i_small ) {
	    print STDERR ("thumbnail ") if $verbose;
	    my $t = convert
	      ($i_large, $i_small,
	       $verbose ? "-verbose" : (),
	       "-size", "${thumb}x$thumb", "-resize", "${thumb}x$thumb",
	       "+profile", "*");
	    print STDERR ("[", $t, "] ") if $verbose > 1;
	    ($w, $h) = $t =~ /^(\d+)x(\d+)/ unless $w && $h;
	}

	# Get image info.
	my $ii = $info->entry($file);
	if ( $ii ) {
	    print STDERR ("size (cached) ") if $verbose;
	    ($w, $h) = ($ii->width, $ii->height);
	    $ii->medium_size(-s $i_medium) if $medium;
	    $ii->orig_name($i_src) if $i_src;
	}
	elsif ( $movie ) {
	    print STDERR ("size ") if $verbose;
	    $ii = new ImageInfo::Entry (large_size => -s $i_large);

	    print STDERR ("(void) ") if $verbose;
	    $ii->width(0);
	    $ii->height(0);
	    $ii->medium_size(0);
	    $ii->large_size(-s d_large($movie));
	    $ii->orig_name($i_src) if $i_src;
	    print STDERR ($ii->tostr, " ") if $verbose > 1;
	}
	else {
	    print STDERR ("size ") if $verbose;
	    $ii = new ImageInfo::Entry (large_size => -s $i_large);

	    if ( $h && $w ) {
		print STDERR ("(known) ") if $verbose;
	    }
	    else {
		my $inf = `identify -verbose -format "%w %h" $i_large`;
		die("Aborted\n") if $? == 2;
		die(sprintf("identify error: 0x%02x%02x\n", $? >> 8, $? & 0xff))
		  if $? || $inf !~ /^(\d+)\s+(\d+)/;
		($w, $h) = ($1, $2);
	    }

	    $ii->width($w);
	    $ii->height($h);
	    $ii->medium_size(-s $i_medium) if $medium;
	    $ii->orig_name($i_src) if $i_src;
	    print STDERR ($ii->tostr, " ") if $verbose > 1;
	}

	# Update image info.
	$info->entry($file, $ii);

	print STDERR ("OK\n") if $verbose;
    }
}

#### Output generation.

sub button($$;$$);

sub ixname($);

sub write_image_page {
    my ($el, $dir) = @_;
    my $i = $el->seq - 1;
    my $file = $el->dest_name;

    # Try movie.
    my $movie = $el->type == T_MPG;
    if ( $movie ) {
	$file = $el->assoc_name;
    }

    my $tt = "$album_title: Image " . ($i+1);
    $tt .= " of " . $num_entries if $num_entries > 1;
    $tt = html($tt);
    my $it = html($el->description) || $tt;

    my $b = join("$br\n",
		 ($dir eq "large" && $medium) ?
		 button("medium", "../medium/".$htmllist[$i],              1, 1) :
		 button("index",  "../".ixname(int($i/$entries_per_page)), 1, 1),
		 button("first",  $htmllist[0],                            1, $i > 0),
		 button("prev",   $htmllist[$i-1],                         1, $i > 0),
		 button("next",   $htmllist[$i+1],                         1, $i < $num_entries-1),
		 button("last",   $htmllist[-1],                           1, $i < $num_entries-1));

    if ( $journal ) {
	$b .= "$br\n" .
	  button("journal", "../journal/index.html", 1, 1);
    }
    if ( $el->type == T_VOICE ) {
	my $sound = $el->assoc_name;
	$b .= "$br\n" .
	  button("sound", "../large/$sound", 1, 1);
    }

    my $imglink;
    if ( $dir eq "medium" ) {
	if ( $movie ) {
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
    my $auxleft  = html($el->tag || "");

    update_if_needed(d_dest($dir, $htmllist[$i]), <<EOD);
<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.01 Transitional//EN">
<html>
  <head>
    <title>$it</title>
    <style type='text/css'>
      <!--
      @{[indent($css, 6)]}
      a.info{position: relative;z-index:24;background-color:#ccc; color:#000; text-decoration:none}
      a.info:hover{z-index:25;background-color: #ff0}
      a.info span{display: none}
      a.info:hover span{display:block;
	  position:absolute; top:2em;left:2em; width:15em;
	  border:1px solid #0cf; background-color:#cff; color:#000;text-align: center}
      -->
    </style>
  </head>
  <body $bodyatts>
    <table>
      <tr>
	<td></td>
	<td align='left' valign='top'>
	  <p class='hd'>$it</p>
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
    if ( $num_indexes > 1) {
	$b = join("$br\n",
		  button("first", ixname(0),              0, $x > 0             ),
		  button("prev",  ixname($x-1),           0, $x > 0             ),
		  button("next",  ixname($x+1),           0, $x < $num_indexes-1),
		  button("last",  ixname($num_indexes-1), 0, $x < $num_indexes-1));
	$tt .= " " . ($x+1) . " of $num_indexes";
	foreach ( 0..$num_indexes-1 ) {
	    if ( $_ == $x ) {
		$t .= ($x+1) . "\n";
	    }
	    else {
		$t .= "<a href='" . ixname($_) . "'>" . ($_+1) . "</a>\n";
	    }
	}
    }
    if ( $journal ) {
	$b .= "$br\n" if $b;
	$b .= button("journal", "journal/index.html", 0, 1);
    }

    # Construct the actual index part.
    my $cc = "<table border='2' cellpadding='3' cellspacing='3'" .
             " bgcolor='$MGREY'>\n";

    my $first_in_row = $x * $entries_per_page;

    for ( my $i = 0; $i < $index_rows; $i++, $first_in_row += $index_columns ) {
	if ( $first_in_row < $num_entries ) {
	    $cc .= "  <tr bgcolor='$LGREY'>\n";
	    for ( my $j = 0; $j < $index_columns; $j++ ) {
		my $this = $first_in_row + $j;
		if ( $this < $num_entries ) {
		    my $el = $filelist->byseq($this+1);
		    my $file = $el->dest_name;
		    my $img = $el->type == T_MPG ? $el->assoc_name : $file;
		    my $base = $medium ? "medium/" : "large/";
		    $base .= $htmllist[$this];
		    $cc .= "    <td align='center' valign='bottom'>\n".
			  "      <table border='0' cellpadding='0' cellspacing='0' bgcolor='$LGREY'>\n".
			  "        <tr>\n".
			  "          <td align='center'>\n".
			  "            <a href='$base'>".img("thumbnails/$img", alt => "[Click for bigger image]", border => 0)."</a>\n".
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
      -->
    </style>
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

# These are to aid XHTML compliancy.
sub ixname($) {
    my ($x) = @_;
    "index" . ($x ? $x : "") . ".html";
}

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

#### Caption helpers.

sub f_caption {
    my ($el) = @_;
    html($el->dest_name);
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

sub load_cache {
    $info = new ImageInfo;
    $info->load(d_dest(".cache")) if !$clobber && -s d_dest(".cache");
}

sub update_cache {
    $info->store(d_dest(".cache"));
}

#### Miscellaneous.

sub squote {
    my ($t) = @_;
    $t =~ s/([\\\'])/\\$1/g;
    "'".$t."'";
}

sub convert {
    my ($from, $to, @args) = @_;
    my $cmd = "convert ".
      join(" ", map { squote($_) } @args, $from, $to);
    my $res = `$cmd 2>&1`;
    die("${res}Aborted\n") if $? == 2;
    die(sprintf("${res}convert error: 0x%02x%02x\n", $? >> 8, $? & 0xff))
      if $?;
    $res =~ /\d+x\d+=>\d+x\d+/ ? $& : $res;
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
	    print STDERR ("Creating icons ") if $verbose && !defined($name);
	    $did++;
            $name = d_icons($1);
	    print STDERR ("$1... ") if $verbose;
            open($out, ">$name");
            $doing = 1;         # Doing
            next;
        }
    }
    if ( $doing ) {
        warn("Error in DATA: still processing $name\n");
        unlink($name);
    }
    else {
	print STDERR ("done\n") if $did && $verbose;
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
    my $ii = $info->entry($el->dest_name);
    return "" unless $ii;
    my $ret = "";
    $ret .= $ii->width . "x" . $ii->height if $ii->width;
    for ( $med ? $ii->medium_size : $ii->large_size ) {
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
    my ($orig, $new, $still, $time, $rotate) = @_;
    $time = (stat($orig))[9] unless defined($time);

    print STDERR ($rotate ? "copy/rotate " : "copy ") if $verbose;

    # I'm not sure what this does. The resultant file is about 10% of
    # the original, without missing something...
    my $cmd = "mencoder ".
      "-of mpeg -ovc lavc -lavcopts vcodec=mpeg1video -oac copy ".
	($rotate ? "-vop rotate=".int($rotate/90)." " : "") .
	  squote($orig) . " -o ". squote($new);
    warn("\n+ $cmd\n") if $verbose > 1;

    my $res = `$cmd 2>&1`;
    die("${res}Aborted\n") if $?;

    utime($time, $time, $new);
    print STDERR ("still ") if $verbose;

    unless ( -s $still ) {
	copy("icons/movie.jpg", $still, $time);
    }
}

sub copy_voice {
    my ($orig, $new, $time) = @_;
    $time = (stat($orig))[9] unless defined($time);
    $orig =~ s/\.\w+$/.mpg/;
    return if -s $new;

    print STDERR ("sound ") if $verbose;
    # This will produce an MP2 file. Good enough for now...
    my $cmd = "mplayer -vo null ".
      "-dumpaudio -dumpfile " . squote($new) . " " . squote($orig);
    warn("\n+ $cmd\n") if $verbose > 1;
    my $res = `$cmd 2>&1`;
    die("${res}Aborted\n") if $?;
    die("${res}Aborted\n") unless -s $new;

    utime($time, $time, $new);
}

sub get_exif {
    my ($file) = @_;

    # Use cached info.
    my $ii = $info->entry($file);
    if ( $ii ) {
	my $e = $ii->exif;
	return $e if $e;
    }

    # Run jhead to collect the EXIF data.
    open(my $p, "-|", "jhead " . squote($file)) or die("$file: $!\n");
    my %h;
    while ( <$p> ) {
	s/\s+:\s+/: /;
	$h{lc($1)} = $2 if /^(.*?): (.*)/;
    }
    close($p) or die("$file: $!\n");

    return undef if exists($h{"not jpeg"});

    $h{exposure} ||= "manual";

    # Update cache.
    $ii ||= new ImageInfo::Entry(exif => \%h);
    $info->entry($file, $ii);

    # Return.
    \%h;
}

################ Subroutines ################

sub app_options {
    my $help = 0;		# handled locally
    my $ident = 0;		# handled locally

    # Process options, if any.
    # Make sure defaults are set before returning!
    return unless @ARGV > 0;

    if ( !GetOptions(
		     'import=s'	=> \$import_dir,
		     'exif'	=> \$import_exif,
		     'dcim=s'	=> sub { $import_dir = $_[1]; $import_exif++ },
		     'update'   => \$add_new,
		     'info=s'	=> \$image_info,
		     'cols=i'	=> \$index_columns,
		     'rows=i'	=> \$index_rows,
		     'thumbsize=i' => \$thumb,
		     'mediumsize:i' => \$medium,
		     'title=s'	=> \$album_title,
		     'clobber'	=> \$clobber,
		     'link!'	=> \$linkthem,
		     'caption=s' => \$caption,
		     'ident'	=> \$ident,
		     'verbose+'	=> \$verbose,
		     'trace'	=> \$trace,
		     'help|?'	=> \$help,
		     'debug'	=> \$debug,
		    )
	 or $help
	 or @ARGV > 1
	 or @ARGV && ! -d $ARGV[0]
       )
    {
	app_usage(2);
    }

    app_ident() if $ident;
    $dest_dir = shift(@ARGV) if @ARGV;
    $medium = DEFAULTS->{mediumsize} if defined($medium) && !$medium;
    if ( $add_new && !$import_dir ) {
	warn("--update ignored -- no import dir specified\n");
	$add_new = 0;
    }
    if ( $import_dir && ! -d $import_dir ) {
	die("$import_dir: Not a directory\n");
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
  Index:
    --cols NN		number of columns per page, default @{[DEFAULTS->{indexcols}]}
    --rows NN		number of rows per page, default @{[DEFAULTS->{indexrows}]}
    --thumbsize NNN	the max size of thumbnail images, default @{[DEFAULTS->{thumbsize}]}
    --captions XXX	f: filename s: size c: description t: tag
  Medium:
    --medium [ NNN ]	the max size of medium sized images, default @{[DEFAULTS->{mediumsize}]}
  Importing:
    --import XXX	original images
    --exif		use w/ EXIF info, if possible
    --dcim XXX		as --import with --exif
    --update		add new entries from import, if needed
    --[no]link		do [not] link large to original. Default is link.
  Miscellaneous:
    --clobber		recreate everything (except large)
    --help		this message
    --ident		show identification
    --verbose		verbose information
EndOfUsage
    exit $exit if defined $exit && $exit != 0;
}

################ Modules ################

package FileEntry;

use Class::Struct "FileEntry" =>
  [ type	 => '$',	#  T_JPG, T_MPG, ...
    seq          => '$',	#  1, 2, ...
    dest_name	 => '$',	#  20040618120400.jpg
    orig_name	 => '$',	#  dsc00058.jpg, if any
    assoc_name	 => '$',	#  20040618120400.mp3 (for a T_VOICE)
    timestamp    => '$',	#  1087556744
    orientation  => '$',	#  degrees
    tag		 => '$',	#  18 jun
    description  => '$',	#  Nice image
    annotation   => '$',	#  When walking through this beautiful landscape ...
  ];

sub html_name {
    my ($self) = @_;
    sprintf("img%04d.html", $self->seq);
}

sub clone {
    my ($self) = @_;
    bless [ @{$self} ], ref($self);
}

package FileList;

use Class::Struct "FileList" =>
  [ _data        => '$',
  ];

sub add {
    my ($self, $el) = @_;
    my $data = $self->_data;
    $self->_data($data = []) unless $data;
    $el->seq(@$data+1);
    push(@$data, $el);
    $self;
}

sub entries {
    my ($self) = @_;
    wantarray ? @{$self->_data} : $self->_data;
}

sub tally {
    my ($self) = @_;
    $self->_data ? scalar(@{$self->_data}) : 0;
}

sub byseq {
    my ($self, $seq) = @_;
    $self->_data->[$seq-1];
}

#### Cache maintenance.

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
    $Data::Dumper::Indent = 1;
    $Data::Dumper::Sortkeys = 1;
    $Data::Dumper::Sortkeys = 1;
    $Data::Dumper::Purity = 1;
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

package main;

__END__

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
begin 644 journal.png
MB5!.1PT*&@H````-24A$4@```"$````A"`,```!@.C)=````L5!,5$4```"Q
ML;&OKZ^GIZ>EI:6CHZ.AH:&?GY^5E963DY.-C8V'AX>!@8%U=W5'1T<U-34O
M+R\I*2DF)R8C(R,A(2'.SL[,S,S*RLK(R,C$Q,3"PL*^PKZ^OKZ\O+P'!P>V
MMK:TN+2TM+2JJJJHK*B@H*"8F)B6EI:,C(R`@(!\?'QV=G9P<'!L;&QJ:FI>
M7EY86%A`0$`P,C`H*"C-S<W'Q\?%Q<7!P<&_O[\,#`R[O[NUN;4S?"*<```!
M$DE$051XG)64VU*#0!!$QVLT"B8L+685$G-1HR9*U"#\_X?)#BS@LDIR7H8J
M3E%=4]/0;1=4SG1FDC:-S/%\,O$])]/&)":*!B8143PIC"RFX32!2?(PI#AC
MPZ%-T'JO"#;DL.'1%)_+G$O@=%EPS\H9><I(_2A!J+)]`^LR9I^-L#!F-`"^
M5CDOP&)5<-@R[#2-F[[F)/^0FEO#"*M%N8!0\]@P1F^:)^!5S?'>.8(><P3<
M]32!+8<`+JI$X2]#NLP:F+L:N6>.ZX,FTF+4^U`\6XSM59-'B]&=XT,RHWPS
MLGKLV(<PC$0P[\"YJ!ZUP3?V;PZ^4SOEG>YPZ]R7L$W=%^Z<%=TY[JV-NK>[
9_1W^Y@<C5%E2*SL"I@````!)14Y$KD)@@@``
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
begin 644 sound2.png
MB5!.1PT*&@H````-24A$4@```"$````A"`,```!@.C)=````^5!,5$4```"I
MJ:FGIZ>EI:6AH:&=G9V5E961D9&#@X.!@8%Y>7EU=W5Q<7%E965C8V-=75U9
M65E!04$]/3TS,S,O+R\M+2TI*2DF)R8A(2$='1W.SL[,S,S*RLH7%Q?(R,C&
MQL;$Q,3`P,"^PKZ^OKZ\O+P)"0D'!P>XN+@%!06VMK:TN+0#`P.TM+0!`0&R
MLK*JJJJHK*BDI*2<G)R6EI:,C(R$A(1\?'QX>'AJ:FI<7%Q86%A.3DY(2$A&
M1D9$1$1"0D)`0$`T-#0P,C`L+"PH*"@F)B8<'!S-S<W)R<D4%!02$A+!P<&_
MO[^]O;V[O[L&!@:UN;6UM;4"`@)(U\([```!04E$051XG(W4:5>"0!0&X&N[
M80L&`XT4E$2A%;;37J268D3]_Q\3#-LXT-C[A3EG'LXLW`OLSPJDSZ#')J!%
M*"@JL%$5(<Q$QP.P)#86@-=)1.@!<B:8S>0"@1<2(4!?HV9:^4CK@T"$`@X%
M](=BO`1*+`+5HI9PU'$R^#C$V$Q$#Z0"G(^`B(6-[8%6)5:[$(NU871:V2\+
M[?D'B'@#N?'=FEIE-YJQ3YODIB)1LY-7&+&\`YG(PH@LD3AVW7N$+CEBOAL/
MGC@"UZ]73-/GB9G[P)]FFR_L+SB2I%N..$,H.GJ#?Q^&;1NTT$11;.M-2K`[
M3;^+FWZ7%[2Y:%0)C*]&1,@G``=WU?51VR*KS-V\CM=S,5UC^F.ZCST_%TR=
MOM=+=<K6>I&\UDF_F.44_4)ZKC)9SY&^K4K1M__[._R=7]$S;]8[D-^%````
)`$E%3D2N0F""
`
end
begin 644 sound.png
MB5!.1PT*&@H````-24A$4@```"$````A"`,```!@.C)=````^5!,5$4```"I
MJ:FGIZ>EI:6AH:&=G9V5E961D9&#@X.!@8%Y>7EU=W5Q<7%E965C8V-=75U9
M65E!04$]/3TS,S,O+R\M+2TI*2DF)R8A(2$='1W.SL[,S,S*RLH7%Q?(R,C&
MQL;$Q,3`P,"^PKZ^OKZ\O+P)"0D'!P>XN+@%!06VMK:TN+0#`P.TM+0!`0&R
MLK*JJJJHK*BDI*2<G)R6EI:,C(R$A(1\?'QX>'AJ:FI<7%Q86%A.3DY(2$A&
M1D9$1$1"0D)`0$`T-#0P,C`L+"PH*"@F)B8<'!S-S<W)R<D4%!02$A+!P<&_
MO[^]O;V[O[L&!@:UN;6UM;4"`@)(U\([```!04E$051XG(W4:5>"0!0&X&N[
M80L&`XT4E$2A%;;37J268D3]_Q\3#-LXT-C[A3EG'LXLW`OLSPJDSZ#')J!%
M*"@JL%$5(<Q$QP.P)#86@-=)1.@!<B:8S>0"@1<2(4!?HV9:^4CK@T"$`@X%
M](=BO`1*+`+5HI9PU'$R^#C$V$Q$#Z0"G(^`B(6-[8%6)5:[$(NU871:V2\+
M[?D'B'@#N?'=FEIE-YJQ3YODIB)1LY-7&+&\`YG(PH@LD3AVW7N$+CEBOAL/
MGC@"UZ]73-/GB9G[P)]FFR_L+SB2I%N..$,H.GJ#?Q^&;1NTT$11;.M-2K`[
M3;^+FWZ7%[2Y:%0)C*]&1,@G``=WU?51VR*KS-V\CM=S,5UC^F.ZCST_%TR=
MOM=+=<K6>I&\UDF_F.44_4)ZKC)9SY&^K4K1M__[._R=7]$S;]8[D-^%````
)`$E%3D2N0F""
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
