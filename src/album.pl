#!/usr/bin/perl -w
my $RCS_Id = '$Id$ ';

# Author          : Johan Vromans
# Created On      : Tue Sep 15 15:59:04 2002
# Last Modified By: Johan Vromans
# Last Modified On: Wed Jun  9 16:49:14 2004
# Update Count    : 1011
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
my $suffixpat = qr{\.(?:jpe?g|png|gif)}i;

my %capfun = ('c' => \&c_caption,
	      'f' => \&f_caption,
	      's' => \&s_caption,
	      't' => \&t_caption,
	     );

my $br = br();

################ The Process ################

use File::Path;
use File::Basename;
use Time::Local;

# The list of files, in the order to be processed.
my @filelist;

# Storage for image info. Will be cached.
my $info;

# Individual file properties:
my %description;		# descriptions
my %rotate;			# rotate info (degrees clockwise)
my %tag;			# tag info
my %seen;			# to keep track

my %newfiles;			# info for new files
my $add_src = 0;		# * seen in info

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

my $num_entries = scalar(@filelist);
print STDERR ("Number of entries = $num_entries",
	      $add_new ? " ($add_new added)" : "",
	      "\n") if $verbose;
die("Nothing to do?\n") unless $num_entries > 0;

# Clean up and create directories.
if ( $clobber ) {
    rmtree(["$dest_dir/thumbnails", "$dest_dir/medium"], 1);
}
mkpath(["$dest_dir/large", "$dest_dir/thumbnails", "$dest_dir/icons"], 1);
mkpath(["$dest_dir/medium"], 1) if $medium;

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
    unlink("$dest_dir/medium/$excess");
    unlink("$dest_dir/large/$excess") or last;
}

# Map file names to html pages. Start with 1 to match "image N of M".
my @htmllist;
for my $i ( 0 .. $num_entries-1 ) {
    $htmllist[$i] = $fn++ . ".html";
}

# Cleanup excess files.
for (my $i = $num_entries ; ; $i++ ) {
    my $excess = $fn++ . ".html";
    unlink("$dest_dir/medium/$excess");
    unlink("$dest_dir/large/$excess") or last;
}

# Write the individual pages.
print STDERR ("Creating pages for ", $num_entries, " image",
	      $num_entries == 1 ? "" : "s", "\n") if $verbose;
my $mod = 0;
for my $i ( 0 .. $num_entries-1 ) {
    write_image_page($i, "large") && $mod++;
    write_image_page($i, "medium") && $mod++ if $medium;
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
    unlink("$dest_dir/index$i.html") or last;
}

# Copy the button images over to the target directory.
add_button_images();

exit 0;

################ Subroutines ################

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

    # If an info has been supplied, it'd better exist.
    if ( $image_info ) {
	die("$image_info: $!\n") unless -s $image_info;
    }
    else {
	# Try default.
	$image_info = "$dest_dir/" . DEFAULTS->{info};
	unless ( -s $image_info ) {
	    $add_new++ if $import_dir;
	    $add_src++ if -d "$dest_dir/large";
	    print STDERR ("No ", DEFAULTS->{info});
	    print STDERR (", adding images from ") if $add_src || $add_new;
	    print STDERR ("$dest_dir/large")       if $add_src;
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

    while ( <$fh> ) {
	chomp;
	next if /^\s*#/;
	next unless /\S/;

	if ( /^\s+/ && $file ) {
	    $description{$file} .= "\n" . $_;
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
	    else {
		warn("Unknown control: !$_\n");
		$err++;
	    }
	    next;
	}
	($file, my $a) = split(' ', $_, 2);
	if ( $file eq "*" ) {
	    $add_src = 1;
	    next;
	}
	my $rotate = 0;
	if ( $a && $a =~ /^-O:(\d)\s*(.*)/ ) {
	    $rotate = 90 * ($1 % 4);
	    $a = $2;
	}
	$description{$file} = $a || "";
	$rotate{$file} = $rotate;
	$tag{$file} = $tag if $tag;
	unless ( $newfiles{$file} || -s "$dest_dir/large/$file" ) {
	    warn("$file (info): Missing\n");
	    $err++;
	}
	$seen{$file}++;
	push(@filelist, $file) unless $description{$file} =~ /^--/;
    }
    close($fh);
    die("Aborted\n") if $err;
}

sub load_src_files {
    my $dh = do { local *DH; *DH; };
    opendir($dh, "$dest_dir/large")
      or die("Cannot opendir $dest_dir/large: $!\n");

    foreach my $f ( grep { !/^\./ && /$suffixpat$/ } readdir($dh) ) {
	$newfiles{$f} = [$f];
    }

    close($dh);
}

sub load_new_files {
    my $dh = do { local *DH; *DH; };
    opendir($dh, $import_dir)
      or die("Cannot opendir $import_dir: $!\n");

    foreach my $f ( grep { !/^\./ && /$suffixpat$/ } readdir($dh) ) {
	if ( $import_exif ) {
	    do_exif($f);
	}
	else {
	    $newfiles{$f} = [$f];
	}
    }

    close($dh);
}

sub do_exif {
    my ($file) = @_;
    my $exif = get_exif("$import_dir/$file");

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

    # We only deal with the normal JPG images.
    if ( $exif && $file =~ /^dsc0\d+\.jpg$/i ) {
	my $fd = $exif->{"date/time"} || "";
	if ( $fd =~ /(\d\d\d\d):(\d\d):(\d\d) (\d\d):(\d\d):(\d\d)/ ) {
	    my $time = timelocal($6,$5,$4,$3,$2-1,$1);
	    # YYYYMMDDhhmmSS (SS = sequence, not seconds).
	    # Note: jhead uses YYYYMMDDhhssX, where X is empty, a, b, ...
	    my $new = "$1$2$3$4$5"."00";
	    my $clash = 0;
	    while ( $newfiles{"$new.jpg"} ) {
		print STDERR ("Import $file -> $new.jpg clashes with ",
			      $newfiles{"$new.jpg"}->[0], "\n")
		  if $verbose;
		$clash = 1;
		$new++;
	    }
	    $new .= ".jpg";
	    print STDERR ("Import $file -> $new\n") if $verbose && $clash;

	    $newfiles{$new} = [ $file, $time, 0 ];
	    $file = $new;
	}
	else {
	    warn("$file: Missing or unparsable file date [$fd]\n");
	    $newfiles{$file} = [ $file, undef, 0 ];
	}
	if ( ($exif->{orientation}||"") =~ /^rotate (\d+)$/i  ) {
	    $newfiles{$file}->[2] = $1;
	}
    }
    else {
	# Copy as is.
	$newfiles{$file} = [ $file, undef, 0 ];
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
	push(@filelist, $file);

	$description{$file} = "";
	$rotate{$file}	    = 0;

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
	$tag{$file} = $t;

	$newinfo .= "$file " .
	  ($rotate{$file} ? "-O:$rotate{$file} " : "") . " \n";
	$add_new++;
    }

    unless ( $newinfo ) {	# nothing to add
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
	  if $medium != DEFAULTS->{mediumsize};
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

    foreach my $file ( @filelist ) {
	print STDERR ("$file: ") if $verbose;

	# Check for directory names, e.g. f01/p01.jpg.
	my $dn = dirname($file);
	if ( $dn && $dn ne "." ) { # we have a dir name.
	    mkpath(["$dest_dir/thumbnails/$dn", "$dest_dir/large/$dn"], 1);
	    mkpath(["$dest_dir/medium/$dn"], 1) if $medium;
	}

	my $i_large   = "$dest_dir/large/$file";
	my $w;
	my $h;

	# Copy the file into place. Rotate if needed.
	if ( ($clobber || ! -s $i_large) && $import_dir ) {
	    my $i_src = "$import_dir/" . $newfiles{$file}->[0];
	    if ( $import_exif ) {
		# Unfortunately, jhead cannot rotate from->to, so
		# we need to copy first and rotate later.
		print STDERR ("copy ") if $verbose;
		my $time = $newfiles{$file}->[1];
		copy($i_src, $i_large, $time);
		if ( $newfiles{$file}->[2] ) {
		    print STDERR ("rotate ") if $verbose;
		    my $cmd = "jhead -autorot ".squote($i_large);
		    my $t = `$cmd 2>&1`;
		    print STDERR $t if $?;
		    utime($time, $time, $i_large);
		}
		print STDERR ("[", bytes(-s $i_large), "] ") if $verbose > 1;
	    }
	    elsif ( $rotate{$file} ) {
		print STDERR ("rotate ") if $verbose;
		my $t = convert
		  ($i_src, $i_large,
		   $verbose ? "-verbose" : (),
		   "-rotate", "$rotate{$file}");
		print STDERR ("[", $t, "] ") if $verbose;
		($w, $h) = $t =~ /^(\d+)x(\d+)/ unless $w && $h;
	    }
	    else {
		print STDERR ("copy ") if $verbose;
		copy($i_src, $i_large);
		print STDERR ("[", bytes(-s $i_large), "] ") if $verbose > 1;
	    }
	}

	my $i_medium  = "$dest_dir/medium/$file";
	my $i_small   = "$dest_dir/thumbnails/$file";

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
    my ($i, $dir) = @_;
    my $file = $filelist[$i];

    my $tt = "$album_title: Image " . ($i+1);
    $tt .= " of " . $num_entries if $num_entries > 1;
    $tt = html($tt);
    my $it = html($description{$file}) || $tt;

    my $b = join("$br\n",
		 ($dir eq "large" && $medium) ?
		 button("medium", "../medium/".$htmllist[$i],              1, 1) :
		 button("index",  "../".ixname(int($i/$entries_per_page)), 1, 1),
		 button("first",  $htmllist[0],                            1, $i > 0),
		 button("prev",   $htmllist[$i-1],                         1, $i > 0),
		 button("next",   $htmllist[$i+1],                         1, $i < $num_entries-1),
		 button("last",   $htmllist[-1],                           1, $i < $num_entries-1));

    my $imglink;
    if ( $dir eq "medium" ) {
	$imglink = "<a href='../large/".$htmllist[$i]."'>" .
	  img($file, alt => "[Click for bigger image]", border => 2) . "</a>";
    }
    else {
	$imglink = img($file, alt => "[Image]", border => 2);
    }

    my $auxright = html($file . " (" . size_info($file) . ")");
    my $auxleft  = html($tag{$file} || "");

    update_if_needed("$dest_dir/$dir/".$htmllist[$i], <<EOD);
<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.01 Transitional//EN">
<html>
  <head>
    <title>$it</title>
    <style type='text/css'>
      <!--
      @{[indent($css, 6)]}
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
		    my $file = $filelist[$this];
		    my $base = $medium ? "medium/" : "large/";
		    $base .= $htmllist[$this];
		    $cc .= "    <td align='center' valign='bottom'>\n".
			  "      <table border='0' cellpadding='0' cellspacing='0' bgcolor='$LGREY'>\n".
			  "        <tr>\n".
			  "          <td align='center'>\n".
			  "            <a href='$base'>".img("thumbnails/$file", alt => "[Click for bigger image]", border => 0)."</a>\n".
			  "          </td>\n".
			  "        </tr>\n".
			  "        <tr>\n".
			  "          <td align='center'>\n".
			  "            <p class='ft'>" . join($br, map { $capfun{$_}->($file) } split(//, $caption)) . "</p>\n".
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

    update_if_needed("$dest_dir/".ixname($x), <<EOD);
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
    $active ? "<a href='$link' alt='[$Tag]'>$b</a>" : $b;
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
    my ($file) = @_;
    html($file);
}

sub s_caption {
    my ($file) = @_;
    size_info($file, $medium);
}

sub t_caption {
    my ($file) = @_;
    $tag{$file} ? html($tag{$file}) : "";
}

sub c_caption {
    my ($file) = @_;
    my $t = $description{$file} || "";
    $t =~ s/\n.*//;
    html($t);
}

#### Persistent info (cache) helpers.

sub load_cache {
    $info = new ImageInfo;
    $info->load("$dest_dir/.cache") if !$clobber && -s "$dest_dir/.cache";
}

sub update_cache {
    $info->store("$dest_dir/.cache");
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
	    next if !$clobber && -s "$dest_dir/$1";
	    print STDERR ("Creating ") if $verbose && !defined($name);
	    $did++;
            $name = "$dest_dir/$1";
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
    my ($file, $med) = @_;
    my $ii = $info->entry($file);
    $ii->width . "x" . $ii->height . ", " .
      bytes($med ? $ii->medium_size : $ii->large_size);
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

sub get_exif {
    my ($file) = @_;

    # Use cached info.
    my $ii = $info->entry($file);
    if ( $ii ) {
	my $e = $ii->exif;
	return $e if $e;
    }

    # Run jhead to collect the EXIF data.
    use 5.008;
    open(my $p, "-|", "jhead", $file) or die("$file: $!\n");
    my %h;
    while ( <$p> ) {
	s/\s+:\s+/: /;
	$h{lc($1)} = $2 if /^(.*?): (.*)/;
    }
    close($p) or die("$file: $!\n");

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
  Miscellaneous:
    --clobber		recreate everything (except large)
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
begin 644 icons/first-gr.png
MB5!.1PT*&@H````-24A$4@```"`````@"`````!6$24H```!YDE$051XG&63
MP6O:8!C&?_T:Z)#M@Q2J+%1HAP;MXAS"H#WDD)T\#GK99=#=]^?T/^C%VZY>
MN@P"11@$K1^U6&&',46%.@(+R&3L8!*2[#G]>)_GS9>$[]GY2JRI6LXFFU!6
M]+)E)-.=.*`&7I!,I=VTLH&IZP4%RZP7=5:+ASL52MLQ4@'5]:7MF,D3QJX7
MM-I6$E"7FUK[E+1Z75]^LH#="U"7F[./M8S/8?VO&KS48?>"Z>?%V8<#<GKZ
MXH_Z=?0,`:Y?>[^?]V'_7<MW0:`\V2Y%PR$I*+6E]QW!(+#C]QN.AFDXM8,O
MB*E7<!(_!T[AVU2HP#+C<3T'9FVCQ)*3Z.?$XP3@5;@4,ZK;M7Z]D06@RDQ,
M*$9K#3(`4&0B-NC`.%X;I_9!)Q`A`&OVR$*D@B:#50D:>WU,2`$`*S2MXB]*
M@(E:-T@#P(**IO,0&?WHXV,`1NBBS%UDO![E`,:4-4NJ\?90<QTG8A@K:0G#
M#MTHWZCGP`UM0]"4;B\Q&FGH>;*)P++#[CQ.D()Y-[`M!#@MO_/(?WKL^"T'
M!!CG\OIJGO?G5]>R;6QOM7[T^^;GD\.,W^O<;*^]!F"!?^_DBW-^#+GJG52W
MU;N]SU>/?'G?O#V.,`G`5/U838*"5GE^D*K_/Q0XR_]A^:_J`````$E%3D2N
#0F""
`
end
begin 644 icons/first.png
MB5!.1PT*&@H````-24A$4@```"`````@"`````!6$24H```!X4E$051XG(63
M/VO;0!C&GYPSI"8<5FAM7(E6'N(_<,4@FC]@M'GPGJ%+*?X>6;KT"_0C9$F'
M0J&3APP%(3`-%18],"H!R48:3$T%1Z(,]=`ATDD*F+[3P_/[Z3C$O3O?D$W@
MK9>+3:(I#;6CRW8G$[CKAK+5^GU6%@+;$E76:ZD*XLB?\X2:`[T@\*OOU!PP
M>0*W+7$\9%+@%Z$Q.D5QIA-'>\<`5,8`OPB'XVZ)0^O=S_QF':B,$7SUAF^?
MX='L'_[]<?>\!@+8CO'F(*T_0H:#@>'8P"ZX14>-M#Z/"X'=WEA';0)7F-G]
MSG^*8C@UQ35(8%4'DH.6PJ#J!L03C$D.40J,A1Y9HY=ST&(`>EB3)5HY+P4`
M+2S)`NI6#A4+LH&RE4/!AB2/?V%Y$J(A!O#A55K(``"(H1$%$;8:$132@(^M
MAH\&43''5F,.E70TSG,@2@;G6H?HW<3./Z59$`!@)WV=X)A:T\PP1*92`%.+
M]D'`3#%9I<9[,U.[P&HB3(;*&#1V[@^?/(#7V?5.\.?2-D8U5,:H47]VJ^^C
M/*O+*^VL_?"JZTU_%NUI)3[]9.?/'O7FG>/^WJM+S+]\#HRS?''^OWH`?EU;
K0IY`S:-V&J4`!%ZTBL/J[LL73POK_P\K=,7]/+GO5`````!)14Y$KD)@@@``
`
end
begin 644 icons/index.png
MB5!.1PT*&@H````-24A$4@```"`````@"`````!6$24H```"&4E$051XG'63
M06L341#'?WV)@J$\:JD$#*0)2&+A+8$%2R#L02(8*.82#[T(N?@I<MYOX&<H
M'NQE1<C!H+!$0@LK)0]B>FD2B-!2C*RX@O3@87>3C>@<EN']?S-OWNS,QD=B
MFXRO9].;0.[F=\J%Y>E&#.@S]R:(3Z554>O`I._ZF8=&,7>7Q?QBI`-IU0H)
M0+\_D58M#@+==_W])PH@#:#?#LU&E94I5>F>_$)%@'[EUP^SH=3!!J!:?-T#
M!:DV$V=2?W$OTH=7N@[`9NGKYY_WMQ#0]\S#[5B'82?TMU^:7A\$VI6-[$I?
M$=F&=,\1G/E6-:FOB*KEGY*>N)E:5+L)##%"!Z#VP:VEQ_Y^^/Z.V6I!$QLX
M]NSPM7HLKMF+\GNK/GC1+7O!M9A13-[O.,DZBLS$E%Q"I]DD0>28;CP(WMQ>
MQ3?C#V#8_'Z>$<M?_&\+A&0!M@$8CH,##HYCA`E8(,4N<R(B622&#<S9%7DN
M2!#-9D+G@KS8841(Q/T#S%!GQ$ZZ++56`#;''D`'S%8+`*UE.5VPWO55W#^`
M(1#J](.#@J`BW0$DZXCR,W!E!8&R_.YEDHCURZYO*5)MY,(+2G<`J.NKI?[M
MZ)/9V"+59DM^'_PH;D9$-HX_ZAD'I7"JU9S>(AK[2&;0]8QG\=CS-'?+^_+X
MK\4Q&PK65T_M_7?U@/-3UU]FD-:C4N0N@6C]_4QZ??W_`!TTUX71'EU>````
)`$E%3D2N0F""
`
end
begin 644 icons/last-gr.png
MB5!.1PT*&@H````-24A$4@```"`````@"`````!6$24H```",4E$051XG&V3
MSVO:8!C'/WVK2Z<CQ"*V="VM8$-TL19A8`\Y=!>]][+;NOO^G[%C;SUL=WLH
M#@*CEV5U#35HP<$8J(B&C`E.&3OD1ZO;<WKS?#YO>-^'][ORD;"&G=OQW7PB
MYU*%W:VHNQ(*=M/THJYLE/1%87AA>@E=S6?6&0VZ7^V);%33#P2[;LG&L1K]
MH=TPO7)-CX0O[^9:K<+#NJI;\AL=6#T%^^W\Z+6VP-G._[&;SU*P>LKP_>#H
M59JE>I+[;;MJ`@$7EO926>:@5,O6!0AL4ZYM`#<!F'V;^8N]FFS:")J>40%N
M6H'1[3B!43&\)F)H)H[][\"8CGNA<9PPAZ+CZ<']\[XAK:V%AJIY'7'+07@L
MWYBB;/8<%X`RM[$QF5`HTI)4)-C!E9)Q(,LX=D>6>^,:=0K)'?I3+0X9[F)S
MUGEH3$%"27[N22JLXXG)PG0D@"F0#!H)(3.ZY^WKPR+`S'%W,\"(F,@QB/B-
M<Z@"TB_'W<@JP("<2-&-]K<T%21&W]V-;!R@14H4L$+A.J_Z)^@IP<W:%,2N
M[+2#4>>+_N+GID8<H&W+^V++F#2"0?I<>KRY$X\#T)@8Z1@ELU&J0)%@?^;1
M4Q]S9<HE!+HQJ?<AY"A[`>_7/4-'0+5LG;O\4^ZY5:Z"@/2)?'G67^;]LTNY
MEO9?=6JOZ?Q8VU[@5^>?_&?O!Z?[X3_!.<G"4O0.LG[T+&<Y>BR']_F+\)5$
A0A!_+Q'+I0K[]SGZ"\%5UFJUEF59`````$E%3D2N0F""
`
end
begin 644 icons/last.png
MB5!.1PT*&@H````-24A$4@```"`````@"`````!6$24H```!XTE$051XG(63
M,6O;0!S%7\X=4A,.*[0VKD0K#XEMN&(0;6H0VCQXS]"E%'^/+EWZ!?H1LJ1#
MH=#)0X:"$)B$&IL>N,HBV5B#J:G@:)2A'CKD=)("HF_1X_V>_IS$_?>^(57H
M;U?+76)H#;UMJG0O+?#Y?*U2H]=CQ4+HN:+*NBU=0QP%"YY0QS9S!7YQ21V;
MJ0G<<\7)@*D"/UM;PS[RFHRGQEL&H#("^-EZ,.H4.(SN[2QHUH'*".%7?_#F
M,>[IX.CO]YLG-1#`FUJO#_$Q):DYM*VI!Q!PEPX;P,]W$BC#AM2]!L%<.'T`
MXH<$RJ#OB"N0T*W:`$`A@3*`79V'Q!>,`8"`!,H`C*U]LD57OBB!,@"ZV)(5
M6MFWJ>'2M+`B2^@H;>A8DATTE#8T[$AR_Q<6E1`#<3YX_B%O8AA$0U3*$4$C
M#02E'`$:1,>BE&,!G;0-S@NQR#CG1IN8G<2[RV5,LT%>TC,)3J@[`4`M&0O%
M)R[M@8`Y8KP!.N]E[*1\,Q8.0V4$&D]OCQZ^2D_Z0CY_GWO6L(;*"#4:S/Z8
M!RAJ<WYAG![?W>IZ,YA%^T:!3SYYV;5'O7DSG?_:KRO,OWP.K=-L<?Z_>@"N
MKURA)E#GY;&TJ@"$?K2)U]4'SYX^RJW_/Y;\Q-+/0K%7`````$E%3D2N0F""
`
end
begin 644 icons/medium.png
MB5!.1PT*&@H````-24A$4@```"`````@"`````!6$24H```!STE$051XG(63
M,6O;0!3'_SE["":(*+06KHY6'AK'<&`0)!B$-@_>,V0IQ9\@7R#?(A\A2QLH
M%#IYR%`0`M-08>$#HRR2C40Q,1$<C3K40X<V\DEVZ)ONWN_WWG'PWLY7/$44
M+.>S549536\9>7;G2>"^'^=9VNFPHA"YCJBQ=E-7D2;AE&>*;1F2P&^^*;;%
M\@[<=<1)C^4"OXK-?A=RC(8>?<\`5`8`OXI[@Z,"!VW_&H>-.E`9(/H2]-Z]
M1"GVWO[^_OAJ'U7`]<RS@S('#JP?7L,``7>4OK;)`=97G#L0^,+N;N-`UQ:W
M()%3LZ3DQ85TL6I^1`+!F,0G$\E@+`[($FV9`[+1QI+,T2SP@M'$G,R@%[EL
MZ)B1%=02EPP5*Y*5ZXL],D*1;O#<2$&K:IQH`"Y3*I2U(-++<P`)U*HV"4T`
MY]@6(32B8[J5`0"FT$F+<OX<YYRVB'&4N<\);M8Q"$X49[2=CQRE`P)FB^%B
M&U\,A<U``,OTKA\V^<.U9UI`98!])1S_-/;*]1]NZ.GAWZFN-\)QLDN+[W]T
MUV./>N/1\^]WZ^O_??X4F:?KQ?G_Z@&XNW5$WD&QCP__'7,!B()DD<:UZIO7
9+Z3U_P/BQ[<`/5AEWP````!)14Y$KD)@@@``
`
end
begin 644 icons/next-gr.png
MB5!.1PT*&@H````-24A$4@```"`````@"`````!6$24H```!TTE$051XG&63
MOVO;0!S%7RX"%]$>*!"'BAB28ALK/=?%$$B&&]1)8R%+ET*Z]\_)?Y#%6U<O
MJ0J"8"@(NSGBX!@RE,K8AK@<5%`J2@=7Q]WY35_>^]P/CGM;7U`J$\O9M,AI
MW:LQ7[E;)2!&B50NY1UF`EF<2)<U@ZJ'U>+^5N24A[X&B'Y*>=A4.TSB1'8C
MI@!Q4;2B$^@:]%/ZD0'8/@?$17'ZH67DV`_^BM%+#]@^1_9I<?I^%Y:>OO@C
M?AX\`P'BM/5NQ\Z!G;?=-`8(1$*CO=*]T8B]B"8/(!A)KNYW,]:)$RX_@V2)
M&VJF083NUXP(R9J:%^A$LU4(LL21<3>#>)4OG1D:!M#&N**V;&#F3%&%10Q1
M$E5,G0(>-HC?[?7H09(<&ZJ@HF:74*RL?#)\71ZQ@D/J6%BY4#D6J!,/]]9Z
M[5W&\$@-MP8P#+1WFZ!&&!43+1\';?TTRHC/\U@#]!QQSGV"#HT'I=,V\D%"
M.R!@/._/%:'E\[[D#`0(NVGO$1MZ[*7=$""`?T:O+N=V/K^\HI&__M7>P:_K
M'T_VC7S0NUY_>P<`&)#>A79QS@X!JWI'C77UOMW9U8-=WN,WA_]'!0"9^+Z:
=2M>I/]_5ZO\/L`FP$[WWEKH`````245.1*Y"8((`
`
end
begin 644 icons/next.png
MB5!.1PT*&@H````-24A$4@```"`````@"`````!6$24H```!TTE$051XG(63
M,6O;0!B&WYP[I"8<5FAM7(E6'A+'<,4@VA`0VCQXS]"E%/V/SOT#_0E9TJ%0
MZ.0A0T$(3$.$10]<9Y%LI,'45'`TRE`/'>*<3@JFWW2\S\/'?<=].]]P7_%L
MM9BO<T-KZ5U3ICOW`@_#1*9&O\_*0NQ[HLYZ'5U#ED93GE/'-A6!7WRGCLUD
M!^Y[XGC`I,#/$FMX`K7&H\!XQP#47("?)0/WJ,1A]&XG4;L)U%S$7V>#MT]1
MJ;V#OU<WSQH@@!]8;_;OTH^*L6];@0\0<(\.6YOPYWO%8$/J78,@%(Z\G_BA
M&B>.N`2)O;HM(XJ28=?#F,P$*^87*!F,)3.R0@]*A[+1PXHLT*D,J!@=+,@<
M>O4)"D/'G*RA587"T+`F^0-<JIP8R!ZD+S]L#AD,HB'=RI%"(RU$6SDBM(B.
MZ5:.*732-3B7@2ASSHTN,8]R7R:TQ.'G?9/@F'ICV:'$QQ[M@X`Y8K3<1([*
MER/A,-1<T"RX/7@,`'BE\-_GOC5LH.:B0:/)'W.O,NSR_,(X/;S[U<UV-$EW
MC1(??_*+;X]F^R8(?^TVB_F^?(ZMTV)Q_K]Z`*XO/5&\A_/Z<'.4`A#/TF66
=U!^]>/Y$6?]_`AZQ"95([D4`````245.1*Y"8((`
`
end
begin 644 icons/prev-gr.png
MB5!.1PT*&@H````-24A$4@```"`````@"`````!6$24H```!V4E$051XG&63
ML6O;0!C%7RZ"%-$>*!"'BAB28@LK.=?!4$@&#>JD,9"E2R'=^^?D/\CBK:N7
M5`%!,!2$71]Q4`P90F5L0UP.*@@5I8.C\YWRIN^^]_M.I^/>VA4*I7P^&><9
MK5E59LON6@'P021DEWHMI@-I&`F3.6[%PF)V=\,SZOFV`O!N3#W?D3LD823:
M`9,`/\\;P1%4];HQ_<H`K)\!_#P__M+0?.RX__C@P`+6SY!^FQU_WD))K]_]
MY;]WWX``8=SXM%GV@<V3=AP"!#RBP;9B#(MB.Z#1/0@&PE//-QQ)XL@3WT'2
MR/0U7UGXYH^4<,$<U7<5P&GDG,RQO^HDF@^\S^9D@OIJON\V-:"."1FCHLSK
M/BH8DQQ6X9?G`0N"9'+UA`V\D&E0L7B^IN9&'XYN+V"0&F;RKP[Y4`=FJ!D6
M[N27'?1U8`2+5'&S:CB'(PU(4"6,\D0A7)5(.&7$]K)0Z375JPPSSR9HT;"G
M$?)(O8BV0,"\K#M5B:*8=H7'0`"_'7<>\4*/G;CM`P2P3^GEQ;3L3R\N:6`O
M7[6U^^?ZUZL=S>]UKI?/W@``!L2W?CDXIWM`*7K[]67T?MZ6HX=R>#]\W'LN
C)0"D_&$Q%J91>[NEQ/\_BN>Q[4W6NT,`````245.1*Y"8((`
`
end
begin 644 icons/prev.png
MB5!.1PT*&@H````-24A$4@```"`````@"`````!6$24H```!UDE$051XG(63
M,6O;0!3'_SEG2$T05FAM7!VM/,2.X8I!-"$@M'GPGJ%+*?H>6;KT"_0C9$F'
M0J&3APP%(3`)%18],"H%R48:3$T%(E&&>NA@6[I+,'W+/;W?CX?N<6_G&S81
M!8O9=)E3M:%U]**ZLQ&X[\=%E?9Z3!8BU\FJK-O25*1)..&Y8IFZ(/"K:\4R
M6=&!NTYVTF>%P"]B8W`*,49#C[YC`"HVP"_BOGTD<=#N_3ALUH&*C>AKT'_[
M#`]B__#O][OG-1#`]8PW!P+ZN#H.3,-S@5UP1QDT!'Z>KA-V^\LY;A/XF27^
MW_F/;).>6MD-2.1438E#*3[,JA^1(&-,XB@Z@+$X(`MT92YT0!<+,D-+YF*T
M,"-3:%LY-$S)$NI6#A5+DC^J2I$3BLU@/KQZA%-0HB+!5B.!2AH(L=4(T2`:
M)MAJ3*"1#N5<-LI)<DX[1#_*74A&.4DW[^D$)XHS$@VCZ#!RE!X(F)4-YX+Q
MWEHG\V%F,51L**EW?_BD-%ZOCC^7KC&HH6*CIH3C6WW_P0WGEU?TK+UZU?5F
M.$[VJ,1'G]SRV:/>O//\WWOU\GY?/D?&6;DX_U\]`#]OG')"BG7<7J>%`$1!
@,D_CZN[+%T^%]?\'5"^R'?&3]F@`````245.1*Y"8((`
`
end
begin 644 icons/simtext.png
MB5!.1PT*&@H````-24A$4@```"`````@"`````!6$24H```"1$E$051XG(63
MP4L;013&?VX6$186D3(2D4B6TD*9Q1*$!D000R$0*D)[:%H*TAX\^@=XZ*G>
M>RQ4>I)XT$LED$LD$%I2*`MA!T&0#1$E9*`B*W,)"#VDVB8*?<?W??,]'F]^
M(S6N2ZO.2?O*N#.II!0WW9%K@VK6XYNNNS`K!PWZH!8[?EI.CG/1;:G0N(M+
MXA^#J@3NPKR\25#?ZG$F+P$2J\#/W</,JY6_<Q%S4R8X<Z?^&-1NE'O[D(&:
M?F2"KA"06$7O'>;>W&.HG`>7@;GO8,%!D"E.#.LP4<P$!V"C:FY>#&J-%A01
M^>.:E#;-N)`=U'L?#>0$V6:Y*2U==^:'PO<,T`7FG;JV5.SW]]=AV.L'?,4'
M!4@_5G8'"1!MA4!A#?AB>!D9`R`;'>L$`?0V0L<7E&N@R_B^1PL@S8G=Q@-.
ML_J=UWM!!TJPCB`"F*1M7S$.>.M$H8(DNDI.(#"]41CGRC;]S7<B`%*4H+6!
M@2,?P-AN?"'0F_A/4_M5QXNJ]-/Y!5S@VC-A5U"%]Z.$>&SA+`.4Z`!=9NQ4
MV/(!*F)?(\.0Y2+`CT@!BI25)("<P^=-`^S@/`=`T`5:)&WI'BDI/NR8)_F*
M22+3HP`\2P,J=.5(;;M<6+M];``^E0NO+6;=>N-NO5%W9[&0BW%%WZ7K2KPH
ML6`I$Y3.;^OGI2"S!(E5'/<LN/2<X??;56\EW?_5PNT&IV/3@_-+W[V5QX`-
M,#=6"8Z;=X,S@)Y,]]$+CH;1X[_P`FC5TNW820SB_QM6H.ZIC)2"H`````!)
'14Y$KD)@@@``
`
end
