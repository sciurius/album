#!/usr/bin/perl -w
my $RCS_Id = '$Id$ ';

# Author          : Johan Vromans
# Created On      : Tue Sep 15 15:59:04 2002
# Last Modified By: Johan Vromans
# Last Modified On: Wed May 26 23:01:19 2004
# Update Count    : 686
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
my $src_dir;
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

unless ( $src_dir ) {
    $src_dir = "$dest_dir/raw";
    $src_dir = "$dest_dir/large" unless -d $src_dir;
}
mkpath(["$dest_dir/large"], 1);
my $target_is_source = do {
    my @src = stat($src_dir);
    my @dst = stat("$dest_dir/large");
    $src[0] == $dst[0] && $src[1] == $dst[1];
};

################ Presets ################

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
my $bodyatts = "text=\"#000000\" link=\"#000000\" vlink=\"#000000\"".
               " alink=\"#FF0000\" bgcolor=\"$DGREY\"";
my $suffixpat = qr{\.(?:jpe?g|png|gif)}i;

my %capfun = ('c' => \&c_caption,
	      'f' => \&f_caption,
	      's' => \&s_caption,
	      't' => \&t_caption,
	     );


################ The Process ################

use File::Path;
use File::Copy;
use File::Basename;

# The list of files, in the order to be processed.
my @filelist;
my @htmllist;			# map fn to html name

# Storage for image info. Will be cached.
my $info;

# Individual file properties:
my %description;		# descriptions
my %rotate;			# rotate info (degrees clockwise)
my %tag;			# tag info
my %seen;			# to keep track

my $add_from_src = 0;		# no info file, or wildcard seen

# Load image names and info from the info file, if any.
load_image_info();

set_parameter_defaults();

# Add image names from the source directory, if needed.
get_image_names();

my $num_entries = scalar(@filelist);
print STDERR ("Number of entries = $num_entries\n") if $verbose;
die("Nothing to do?\n") unless $num_entries > 0;

# Clean up and create directories.
if ( $clobber ) {
    rmtree(["$dest_dir/thumbnails", "$dest_dir/medium"], 1);
}
mkpath(["$dest_dir/thumbnails", "$dest_dir/images"], 1);
mkpath(["$dest_dir/medium"], 1) if $medium;

# Load cached info, if possible.
load_cache();

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
print STDERR ("Creating pages for ", $num_entries, " images\n") if $verbose;
my $mod = 0;
for my $i ( 0 .. $num_entries-1 ) {
    write_image_page($i, "large") && $mod++;
    write_image_page($i, "medium") && $mod++ if $medium;
}
uptodate("image", $mod) if $verbose;

# Write the index pages.
print STDERR ("Creating pages for ", $num_indexes, " indexes\n") if $verbose;
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

    $album_title ||= "Photos";

    # Other settings.
    $index_rows ||= 3;
    $index_columns ||= 4;
    $thumb ||= 200;
    $medium ||= 0;

    # Caption values.
    $caption ||= "fct";
    die("Invalid value for caption: $caption\n")
      unless $caption =~ /^[fsct]+$/i;
    $caption = lc($caption);
}

sub load_image_info {

    if ( $image_info ) {
	die("$image_info: $!\n") unless -s $image_info;
    }
    else {
	$image_info = "$dest_dir/info.dat";
    }
    $add_from_src++, return unless -s $image_info;

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

	if ( /^!(.*)/ ) {
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
	$add_from_src |= $file eq "*";
	my $rotate = 0;
	if ( $a && $a =~ /^-O:(\d)\s*(.*)/ ) {
	    $rotate = 90 * ($1 % 4);
	    $a = $2;
	}
	$description{$file} = $a || "";
	$rotate{$file} = $rotate unless $target_is_source;
	$tag{$file} = $tag if $tag;
	next if $file eq "*";
	unless ( -s "$src_dir/$file" || -s "$dest_dir/large/$file" ) {
	    warn("$src_dir/$file (info): $!\n");
	    $err++;
	}
	$seen{$file}++;
	push(@filelist, $file) unless $description{$file} =~ /^--/;
    }
    close($fh);
    die("Aborted\n") if $err;
}

sub get_image_names {
    return unless $add_from_src;

    my $dh = do { local *DH; *DH; };
    opendir($dh, $src_dir)
      or die("Cannot opendir $src_dir: $!\n");

    foreach ( sort grep { !/^\./ && /$suffixpat$/
			    && !/^(first|last|next|prev|index)(-gr)?\.png$/
			      && $_ ne "thumbnails" } readdir($dh) ) {
	next if $seen{$_}++;
	push(@filelist, $_);
	$description{$_} = $description{"*"};
	$rotate{$_} = $rotate{"*"};
    }

    close($dh);
}

sub prepare_images {

    foreach my $file ( @filelist ) {
	print STDERR ("$file... ") if $verbose;

	# Check for directory names, e.g. f01/p01.jpg.
	my $dn = dirname($file);
	if ( $dn && $dn ne "." ) { # we have a dir name.
	    mkpath(["$dest_dir/thumbnails/$dn", "$dest_dir/large/$dn"], 1);
	    mkpath(["$dest_dir/medium/$dn"], 1) if $medium;
	}

	my $i_src     = "$src_dir/$file";
	my $i_large   = "$dest_dir/large/$file";
	my $i_medium  = "$dest_dir/medium/$file";
	my $i_small   = "$dest_dir/thumbnails/$file";

	# Copy the file into place. Rotate if needed.
	if ( !$target_is_source and $clobber || ! -s $i_large ) {
	    if ( $rotate{$file} ) {
		print STDERR ("rotating... ") if $verbose;
		system("convert", "-rotate", "$rotate{$file}",
		       $i_src, $i_large);
		die("Aborted\n") if $? == 2;
		die(sprintf("rotate error: 0x%02x%02x\n", $? >> 8, $? & 0xff))
		  if $?;
	    }
	    else {
		print STDERR ("copying... ") if $verbose;
		copy($i_src, $i_large);
	    }
	}

	# Get image info.
	my $ii = $info->entry($file);
	if ( $ii ) {
	    print STDERR ("cached... ") if $verbose;
	}
	else {
	    my $inf = `identify -verbose -format "%w %h" $i_large`;
	    die("Aborted\n") if $? == 2;
	    die(sprintf("identify error: 0x%02x%02x\n", $? >> 8, $? & 0xff))
	      if $? || $inf !~ /^(\d+)\s+(\d+)/;
	    $ii = new ImageInfo::Entry
	      (large_size   => -s $i_large,
	       medium_size  => 0,
	       width	    => $1,
	       height	    => $2);
	}

	my $neednl = 0;
	if ( $medium && ($clobber  || ! -s $i_medium) ) {
	    my @t = ( $medium );
	    $t[1] = int(0.67 * $t[0]);
	    system("convert ".
		   ($verbose ? "-verbose" : "") ." -geometry ".
		   (( $ii->width > $ii->height )
		    ? "$t[0]x$t[1]" : "$t[1]x$t[0]") .
		   " $i_large $i_medium");
	    die("Aborted\n") if $? == 2;
	    die(sprintf("convert error: 0x%02x%02x\n", $? >> 8, $? & 0xff))
	      if $?;
	}
	else {
	    $neednl++;
	}
	$ii->medium_size(-s $i_medium) if $medium;

	# Update image info.
	$info->entry($file, $ii);
	print STDERR ($ii->tostr, " ") if $verbose;

	if ( $clobber || ! -s $i_small ) {
	    my @t;

	    if ( $ii->width > $ii->height ) {
		@t = ( $thumb,
		       int($thumb * ($ii->height/$ii->width)) );
	    }
	    else {
		@t = ( int($thumb * ($ii->width/$ii->height)),
		       $thumb );
	    }

	    system("convert",
		   $verbose ? "-verbose" : (),
		   "-geometry", "$t[0]x$t[1]",
		   $i_large, $i_small);
	    die("Aborted\n") if $? == 2;
	    die(sprintf("convert error: 0x%02x%02x\n", $? >> 8, $? & 0xff))
	      if $?;
	}
	else {
	    $neednl++;
	}

	print STDERR ("\n") if $verbose && $neednl;
    }
}

#### Output generation.

sub button($$;$$);

sub write_image_page {
    my ($i, $dir) = @_;

    my $file = $filelist[$i];
    my $it = html($description{$file});
    my $tt = "$album_title: Image " . ($i+1);
    $tt .= " of " . $num_entries if $num_entries > 1;
    $tt = html($tt);
    $it ||= $tt;

    my $b;
    if ( $dir eq "large" && $medium ) {
	$b = "<a href=\"../medium/".$htmllist[$i]."\">" .
	  "<img align=\"top\" src=\"../images/up.png\" " .
	  "border=\"0\" alt=\"[Medium size]\"></a><br>\n";
    }
    else {
	$b = "<a href=\"../index" .
	  (($i >= $entries_per_page) ? int($i / $entries_per_page) : "") .
	  ".html\">" .
	  "<img align=\"top\" src=\"../images/index.png\" " .
	  "border=\"0\" alt=\"[Index]\"></a><br>\n";
    }
    # Link to first/prev image.
    $b .= button("first", $htmllist[0],    1, $i > 0) . "<br>\n";
    $b .= button("prev",  $htmllist[$i-1], 1, $i > 0) . "<br>\n";

    # Link to next/last image.
    $b .= button("next", $htmllist[$i+1], 1, $i < $num_entries-1) . "<br>\n";
    $b .= button("last", $htmllist[-1],   1, $i < $num_entries-1) . "<br>\n";

    my $imglink;
    if ( $dir eq "medium" ) {
	$imglink = "<a href=\"../large/".$htmllist[$i]."\">" .
	  "<img src=\"$file\" alt=\"[Click for bigger image]\"></a>";
    }
    else {
	$imglink = "<img src=\"$file\">";
    }

    my $auxright = html($file . " (" . size_info($file) . ")");
    my $auxleft  = html($tag{$file} || "");

    my $new = <<EOD;
<html>
<head>
<title>$it</title>
<style type="text/css">
<!--
$css
-->
</style>
</head>
<body $bodyatts>
  <table>
    <tr>
      <td></td>
      <td align="left" valign="top">
        <p class="hd">$it</p>
      </td>
      <td align="right" valign="top">
        <p class="hd">$tt</p>
      </td>
    </tr>
    <tr>
      <td valign="top">
	$b
      </td>
      <td align="center" valign="top" colspan="2">
	$imglink
      </td>
    </tr>
    <tr>
      <td></td>
      <td align="left" valign="top">
        <p class="ft">$auxleft</p>
      </td>
      <td align="right" valign="top">
        <p class="ft">$auxright</p>
      </td>
    </tr>
  </table>
</body>
</html>
EOD

    update_if_needed("$dest_dir/$dir/".$htmllist[$i], $new);
}

sub write_index_page {
    my ($x) = @_;

    my $tt = $album_title.": Index";

    my $t = "";
    my $b = "";
    if ( $num_indexes > 1) {
	$b .= button("first", "index.html", 0, $x > 0) . "<br>\n";
	$b .= button("prev", "index.html", 0, 0) . "<br>\n"
	  unless $x;
	$b .= button("prev", "index.html", 0, 1) . "<br>\n"
	  if $x == 1;
	$b .= button("prev", "index".($x-1).".html", 0, 1) . "<br>\n"
	  if $x > 1;
	$b .= button("next", "index.html", 0, 0) . "<br>\n"
	  if $x == $num_indexes-1;
	$b .= button("next", "index".($x+1).".html", 0, 1) . "<br>\n"
	  if $x < $num_indexes-1;
	$b .= button("last", "index".($num_indexes-1).".html", 0,
		     $x < $num_indexes - 1) . "<br>\n";
	$tt .= " " . ($x+1) . " of $num_indexes";
	foreach ( 0..$num_indexes-1 ) {
	    if ( $_ == $x ) {
		$t .= " " . ($x+1);
	    }
	    else {
		$t .= " <a href=\"index".
		  ($_ ? $_ : ""). ".html\">".($_+1)."</a>";
	    }
	}
    }

    my $new = <<EOD;
<html>
<head>
<style type="text/css">
<!--
$css,
-->
</style>
<title>$tt</title>
</head>
<body $bodyatts>
<table>
<tr>
  <td></td>
  <td align="left">
    <p class="hd">$tt</p>
  </td>
  <td align="right">
    <p class="hd">$t</p>
  </td>
</tr>
<tr>
  <td valign="top">$b</td>
  <td valign="top" colspan="2">
EOD

    $new .= qq(<table border="2" cellpadding="3" cellspacing="3") .
            qq( bgcolor="$MGREY">\n);

    my $first_in_row = $x * $entries_per_page;

    for ( my $i = 0; $i < $index_rows; $i++, $first_in_row += $index_columns ) {
	if ( $first_in_row < $num_entries ) {
	    $new .= qq(  <tr bgcolor="$LGREY">\n);
	    for ( my $j = 0; $j < $index_columns; $j++ ) {
		my $this = $first_in_row + $j;
		if ( $this < $num_entries ) {
		    my $file = $filelist[$this];
		    my $base = $medium ? "medium/" : "large/";
		    $base .= $htmllist[$this];
		    $new .= "    <td align=\"center\" valign=\"bottom\">\n".
			  "      <table border=\"0\" cellpadding=\"0\" cellspacing=\"0\" bgcolor=\"$LGREY\">\n".
			  "        <tr>\n".
			  "          <td align=\"center\">".
			  "<a href=\"$base\"><img src=\"thumbnails/$file\" alt=\"[Click for bigger image]\" border=\"0\"></a>".
			  "</td>\n".
			  "        </tr>\n".
			  "        <tr>\n".
			  "          <td align=\"center\">\n".
			  "            <p class=\"ft\">".
			  join("", (map { $capfun{$_}->($file), "<br>\n" }
			     split(//, $caption))).
			  "</p>\n".
			  "          </td>\n".
			  "        </tr>\n".
			  "      </table>\n".
			  "    </td>\n";
		}
		else {
		    $new .= "    <td width=\"$thumb\" bgcolor=\"$DGREY\">&nbsp</td>\n";
		}
	    }
	    $new .= "  </tr>\n";
	}
    }
    $new .= "</table>\n";

    $new .= "</td>\n" . "</tr></table></body></html>\n";

    update_if_needed("$dest_dir/index".($x > 0 ? $x : ""). ".html", $new);
}

sub button($$;$$) {
    my ($tag, $link, $level, $active) = @_;
    my $Tag = ucfirst($tag);

    $level  = 0 unless defined $level;
    $active = 1 unless defined $active;
    $tag .= "-gr" unless $active;
    $level = "../" x $level;
    my $b = "<img align=\"top\" src=\"${level}images/$tag.png\"".
      " border=\"0\" alt=\"[$Tag]\">";
    $active ? "<a href=\"$link\" alt=\"[$Tag]\">$b</a>" : $b;
}

#### HTML helpers.

sub html {
    my $t = shift;
    return '' unless $t;
    $t =~ s/\&/&amp;/g;
    $t =~ s/\</&lt;/g;
    $t =~ s/\>/&gt;/g;
    $t =~ s/\n+/<br>/g;
    $t;
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
    $t;
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

################ Subroutines ################

sub app_options {
    my $help = 0;		# handled locally
    my $ident = 0;		# handled locally

    # Process options, if any.
    # Make sure defaults are set before returning!
    return unless @ARGV > 0;

    if ( !GetOptions(
		     'source=s'	=> \$src_dir,
		     'info=s'	=> \$image_info,
		     'cols=i'	=> \$index_columns,
		     'rows=i'	=> \$index_rows,
		     'thumbsize=i' => \$thumb,
		     'mediumsize=i' => \$medium,
		     'title=s'	=> \$album_title,
		     'clobber'	=> \$clobber,
		     'caption=s' => \$caption,
		     'ident'	=> \$ident,
		     'verbose'	=> \$verbose,
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
}

sub app_ident {
    print STDERR ("This is $my_package [$my_name $my_version]\n");
}

sub app_usage {
    my ($exit) = @_;
    app_ident();
    print STDERR <<EndOfUsage;
Usage: $0 [options] [ directory ]
    -info XXX		description and control file
    -title XXX		album title
    -source XXX		where the original images reside
    -cols NN		number of columns per page
    -rows NN		number of rows per page
    -thumbsize NNN	the max size of thumbnail images
    -medium NNN		the max size of medium sized images
    -captions XXX	f: filename s: size c: description t: tag
    -clobber		recreate everything
    -index-buttons	use index buttons instead of links
    -help		this message
    -ident		show identification
    -verbose		verbose information
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
  ];

sub ImageInfo::Entry::tostr {
    my ($self) = @_;
    "[ " . join(" ",
		$self->large_size,
		$self->medium_size,
		$self->width,
		$self->height,
	       ) . " ]";
}

package main;

__END__
begin 644 images/first.png
MB5!.1PT*&@H````-24A$4@```"(````B"`8````Z1PO"````!&=!34$``+&/
M"_QA!0````9B2T=$`/\`_P#_H+VGDP````EP2%ES```+$@``"Q(!TMU^_```
M``=T24U%!](&'@P%!C&J:IP```&O241!5'B<[9BQBL)`$(8_UZ#D;"SL?`"?
MP-KM+10L;"R$$`41KK&TR!O(=8%@(0H*XCO8WW,<V`<N%B%><9=P1N'V,(D6
M_K"0R0R9+Y/-L+OP(,K%[#KPDF'^3^`]#E('7H%JAB`?P%L($T*LI)0G(+/Q
MDV\%U,.*-``+D`!2RJ3?_$+[_3ZZ!"PM'B"EI%JM8IIF:A".XR"E_`W#!0B`
M:9HT&HW40``LRSJS1:K9_J$G2%S*(/E\'B$$0JBS3Z=3#H=#LB"GTRD:*II,
M)MBVC>=Y2O%7_YI;-1Z/62Z7N*Y+H5#('L3W?8;#(>OU.JI$YB">YS$8#-AL
M-OB^']TO%HO9@;BNBV$8['8[@B`X\V4*,AJ-V&ZW5WVJ(#?WD2`(:+?;Z+I^
MX5.='XF`""%HM5K,YW,T[;S`JM5(!`1`TS0ZG0Z.X]P7!+X_0[?;Q;;M^X(`
MZ+I.K]=C-IM%<*I*O+.62B7Z_3['XY'%8G$_$(!RN8QA&-1JM>1!XHWJ+U4J
M%9K-IG)\:NN17"Z7;1])2D^0N*Y.UGB'3%K7GO\P.[W0>)B];PASM].`ASD?
6^0(75+;=MXIF$0````!)14Y$KD)@@@``
`
end
begin 644 images/index.png
MB5!.1PT*&@H````-24A$4@```"(````B"`8````Z1PO"````!&=!34$``+&/
M"_QA!0````9B2T=$`/\`_P#_H+VGDP````EP2%ES```+$@``"Q(!TMU^_```
M``=T24U%!](&'@P%-8YZ"XH```&?241!5'B<[9A!BN)`%$!?#XW1OH(K#^':
MND(.H"`2=2$,@@?(P@OT3JB-T4;=U!U<N)MSS,J-$.PB9:&SZ31CM3.TCG%"
MXX."?/)3_Z6H2JB"G/#@Q%7@Z8;U7X$?KD@5^`Z4;RCR$WA.95*)%R'$`;A9
M>ZOW`E33$:D!(2``A!#7?O,/+)?+]TL@?'03A!"4RV6"(,A,0DJ)$.)W&3Z(
M``1!0*U6RTP$(`S#H_A;IM7.X&N(6&M12E&OUXGC^)]$3LZ1SV",02E%J]5"
M:TV2)$111*E4NJB_BT9$:\UL-J/1:*"U!D`I1;O=QEI[&Y'M=LMD,J'9;!X5
MW>_W+!8+.IU.]B*;S08I)=UN]^1]:RWS^9Q>KY>-R.%P8+U>,QJ-Z/?[?\W5
M6C.=3AD,!F>)?&JR[G8[5JL54111J50PQI`DR7LSQASEQW',>#RF6"PR'`ZO
M)U(H%/!]']_W_YCCBAECSEI!%R]?%\_S\#SOXN>_QI?UFMQ%7.XB+G<1E[N(
M2VY$3OYKI)29%CW5?VYV>FF0F[UO*O/?3@-R<S[R"XFFX$N)OY`F`````$E%
&3D2N0F""
`
end
begin 644 images/up.png
MB5!.1PT*&@H````-24A$4@```"(````B"`8````Z1PO"````!&=!34$``+&/
M"_QA!0````9B2T=$`/\`_P#_H+VGDP````EP2%ES```+$@``"Q(!TMU^_```
M``=T24U%!](&'@P%-8YZ"XH```&?241!5'B<[9A!BN)`%$!?#XW1OH(K#^':
MND(.H"`2=2$,@@?(P@OT3JB-T4;=U!U<N)MSS,J-$.PB9:&SZ31CM3.TCG%"
MXX."?/)3_Z6H2JB"G/#@Q%7@Z8;U7X$?KD@5^`Z4;RCR$WA.95*)%R'$`;A9
M>ZOW`E33$:D!(2``A!#7?O,/+)?+]TL@?'03A!"4RV6"(,A,0DJ)$.)W&3Z(
M``1!0*U6RTP$(`S#H_A;IM7.X&N(6&M12E&OUXGC^)]$3LZ1SV",02E%J]5"
M:TV2)$111*E4NJB_BT9$:\UL-J/1:*"U!D`I1;O=QEI[&Y'M=LMD,J'9;!X5
MW>_W+!8+.IU.]B*;S08I)=UN]^1]:RWS^9Q>KY>-R.%P8+U>,QJ-Z/?[?\W5
M6C.=3AD,!F>)?&JR[G8[5JL54111J50PQI`DR7LSQASEQW',>#RF6"PR'`ZO
M)U(H%/!]']_W_YCCBAECSEI!%R]?%\_S\#SOXN>_QI?UFMQ%7.XB+G<1E[N(
M2VY$3OYKI)29%CW5?VYV>FF0F[UO*O/?3@-R<S[R"XFFX$N)OY`F`````$E%
&3D2N0F""
`
end
begin 644 images/last.png
MB5!.1PT*&@H````-24A$4@```"(````B"`8````Z1PO"````!&=!34$``+&/
M"_QA!0````9B2T=$`/\`_P#_H+VGDP````EP2%ES```+$@``"Q(!TMU^_```
M``=T24U%!](&'@P%'U7!PEP```$5241!5'B<[=BQ;80P%,;Q?^+09`7FH.8M
M`1NXS@I>(;7;JV`)^LR1%=)!TL2GQ$<DS/EQCG2?9`E+R.\'LI$Q%)*'J-\`
MSP?6_P#>8D@#O`#U@9!WX#5@`N(D(I_`8>V[W@EHPAMI`0<(@(CD?O*+3--T
MO@3<4WR#B%#7-=9:-83W'A'YB>$"`F"MI6U;-0B`<^Y7_U&U6D+ND#B;(>,X
M;AZTJBJ,,1AC\D/ZOM^,69;EW+)#4C&I29XC6IA=DU4#LWO5Y,9<M7QS8J[^
MCA0!Z;J.81AN"\F)V`W)C=@%T4`D0[0021!-!/RQ0UM+"F*>YV3(_]N/:.<.
MB;,Z6;WWJD77QB_F3R]TBOGW#9B;G084<S[R!058F0YBC22O`````$E%3D2N
#0F""
`
end
begin 644 images/next.png
MB5!.1PT*&@H````-24A$4@```"(````B"`8````Z1PO"````!&=!34$``+&/
M"_QA!0````9B2T=$`/\`_P#_H+VGDP````EP2%ES```+$@``"Q(!TMU^_```
M``=T24U%!](&'@P$$T5LOS8```#]241!5'B<[=@Q#H(P%(#A7^/D%3@'<]\E
MX`:=O4*OX-S5"2[![CF\@JLNUFAAH-B'-?$E)+R$\+Y"2WB%0F(3Y36P7['^
M%3C'D!HX`-6*D`MP#)B`.(G(#5CM>-0[`75X(@9P@`"(2.Z1CV(8AN<IX';Q
M!2)"5558:]40WGM$Y!7#"`)@K<48HP8!<,Z]Y5O5:@GQA\0Q&]+WO:9C/J1M
M6U5,TJO1Q"3/$2W,HLFJ@5F\:G)C/EJ^.3$??T>*@#1-0]=UWX7D1"R&Y$8L
M@F@@DB%:B"2()B()HHF`7_P?T8X_)([)=L)[KUITZO[%='HA*:;W#9BO[084
8LS]R![)HC08-&VZ(`````$E%3D2N0F""
`
end
begin 644 images/prev.png
MB5!.1PT*&@H````-24A$4@```"(````B"`8````Z1PO"````!&=!34$``+&/
M"_QA!0````9B2T=$`/\`_P#_H+VGDP````EP2%ES```+$@``"Q(!TMU^_```
M``=T24U%!](&'@P$*VUN!Z@```&<241!5'B<[9B_:L)0%(>_A*"D+@YN>0"?
MP#EW=U!P<'$00A1$Z.+HD#>0;H'@(`H*XCNX]SD*[H'&(:0=VH0:,Z28?X,_
M".3DW)OSY23GA'NA(I)B=@=X*3#^)_`>!^D`KX!6(,@'\!;"A!`[(<074-CQ
M&V\'=,*,Z(`%"``A1-9/?J?S^1R=`I82'R"$0-,T3-/,#<)Q'(00?V&X`P$P
M31-=UW,#`;`LZ\:6<XWV#SU!XLH59+E<<KE<R@59+!;8MHWG>:G&)U;-HYK/
MYVRW6US7I5:K%0_B^S[3Z93]?A]EHG`0S_.83"8<#@=\WX^NU^OUXD!<U\4P
M#$ZG$T$0W/@*!9G-9AR/QT1?6I"'JR8(`OK]/JJJWOG2?A^9@,BR3*_78[U>
MHRBW"4Z;C4Q``!1%83`8X#A.N2#P\QJ&PR&V;9<+`J"J*J/1B-5J%<&E5>:=
MM=%H,!Z/N5ZO;#:;\D``FLTFAF'0;K=3S\GMI]=JM>AVN^6#2))4;!_)2D^0
MN!*K)MXALU;2_2NST@N-RJQ]0YC2=@,JLS_R#<Z)JM5*)O89`````$E%3D2N
#0F""
`
end
begin 644 images/first-gr.png
MB5!.1PT*&@H````-24A$4@```"(````B"`8````Z1PO"````!&=!34$``+&/
M"_QA!0````9B2T=$`*L`JP"K:IW=&0````EP2%ES```+$0``"Q$!?V1?D0``
M``=T24U%!],%`PH;""A1(L$```$U241!5'B<[9@Q;H0P$$5?XHB"C@Z)<]`A
M,1>@L,05J',%KI":=DL.09]SY`I0)LUZ1;PH,<$&%.V7D#S2V/,8C\:RX21Z
MLNP<B'>,/P+O-D@.O`+9CB`?P)N!,1`7$?D$=ONN\2Y`;C)2`BT@`"+B^\_O
M-`S#;0BT+[:#B)!E&4W3!(/HN@X1F<-P!P+0-`UE608#`6C;]IO]'#3:"CU`
M;"W6R)+ZOK^-Z[IVGE,4!6F:_NH;+",&?)HF)_\@(//L15%T#,@<`B".W8XN
MKR`V!$"2)/N"+$&LD1>0K1!PHC[B!<2UK_PD;QG9"N-U:[;`>*^1O\($*5:M
M->,X'@^BE**J*I12SG.<3]^U*4^2!*VUL___ZB,^]`"QM5BL7=<%#;JT_FEN
C>L8XS=W7P!SV&G":]Y$O&I:#2F!<C%$`````245.1*Y"8((`
`
end
begin 644 images/index-gr.png
MB5!.1PT*&@H````-24A$4@```"(````B"`8````Z1PO"````!&=!34$``+&/
M"_QA!0````9B2T=$`/\`_P#_H+VGDP````EP2%ES```+$0``"Q$!?V1?D0``
M``=T24U%!],%`PH<"_X9Y;P```%2241!5'B<[9BQ:H1`$(:_A'!R@7L"G\/:
MZ:Z_=[#.*_@*J6VOM#@.1`0+P3+/D>H:&R.W"J:)<MDSB1ZGL?"'A1UWG/F<
M95=V829ZT&P+>)XP_P?PIH-8P`M@3@CR#KPV,`W$7D1J8++VE6\/6$U%;,`%
M!$!$[OWE5TJ2I.T"[I/N("*8IHGC.*-!>)Z'B%S"<`4"X#@.MFV/!@+@NNXW
M^W'4;`,T&Y#.J>FKJJHX'`X`;+=;-IO-S;%NKHA2JH4`B**(HBBF!2F*@N/Q
M>/4\"`*JJIH&),]S@B#X<?RR2J.!9%E&&(9_^OF^/PY(7=><3B?B..X=>"A,
M+Y"R+$G3=%#@H3"]EN]JM6*WV_WJ<SZ?VZ:40BG%>KV^+T@?&8:!81@WOS^;
MG74!T;6`Z%I`="T@NA8079W_&L_S1DW:%7\V)[W&F,W9MX'YM]N`V=R/?`+I
3!JQ-F!I[D`````!)14Y$KD)@@@``
`
end
begin 644 images/last-gr.png
MB5!.1PT*&@H````-24A$4@```"(````B"`8````Z1PO"````!&=!34$``+&/
M"_QA!0````9B2T=$`*L`JP"K:IW=&0````EP2%ES```+$0``"Q$!?V1?D0``
M``=T24U%!],%`PH<.$')A*H```$,241!5'B<[=C/#<(@&(?A%^/)%3I'S_V&
MZ`J<78$5/'/UU@[1NW.X@E>]B%'41/Y\M2;^$I*2-/"TA0:`A<1$]1;8S-C_
M"3C$D!;8`LV,D".P"YB`V(O(&9BM7/O;`VUX(QW@``$0D=I/_I1IFFZ7@%O'
M-X@(3=-@K55#>.\1D7L,3Q``:RU=UZE!`)QS#_65:F\)^4/B?`P9AN'C1L=Q
MO)7J$&-,$B8U29]&$Y,\1K0P68-5`Y,]:VICBJ9O34SQ?\28>$F3EV)(W_<U
M'&606@@H@-1$0":D-@(R(!H(2(1H(>#-"JT4D0/^O?6(=OZ0."\'J_=>M=-7
G[2]FIQ<JB]G[!LS73@,6<SYR`:R7?Q#7F]Z8`````$E%3D2N0F""
`
end
begin 644 images/next-gr.png
MB5!.1PT*&@H````-24A$4@```"(````B"`8````Z1PO"````!&=!34$``+&/
M"_QA!0````9B2T=$`/\`_P#_H+VGDP````EP2%ES```+$0``"Q$!?V1?D0``
M``=T24U%!],%`PH7"?/C75L```$$241!5'B<[=@_#H(P%,?Q+^KD%3@'<]\9
MC%?H[!5Z!>>N;ER"W7-X!5==K-'"8/\\Q,1?0D(3POL`+6D+"TD3M3M@.V/]
M*W".(1UP`-H9(1?@&#`!<1*1&S#;\:AW`KKP1@S@``$0D=I//LHP#,]3P&WB
M"T2$MFVQUJHAO/>(R"N&$03`6HLQ1@T"X)Q[:Z]4JR7D#XGS,:3O>TW'YY!U
MTZABDCZ-)B:YCVAALCJK!B9[U-3&%`W?FICB_\BZB:<T>2F&[/;[&HXR2"T$
M%$!J(B`34AL!&1`-!"1"M!"0`-%$P"_.1[3SA\297$YX[U6+3MU_,2N]T%C,
?VC=@OK8;L)C]D3M7S7@&)IXTW`````!)14Y$KD)@@@``
`
end
begin 644 images/prev-gr.png
MB5!.1PT*&@H````-24A$4@```"(````B"`8````Z1PO"````!&=!34$``+&/
M"_QA!0````9B2T=$`*L`JP"K:IW=&0````EP2%ES```+$0``"Q$!?V1?D0``
M``=T24U%!],%`PH=-%%D^<````%2241!5'B<[=BQ:H-`&,#QOR(&ZY+!S>=P
MOF_($@PA+^'<5_`5.KMF='!Q<'//<Q2R!^H2T@ZMI3$63.MY#OE`\$[]OI_B
M<=S!3,+JM"/@:<+Z;\"A"XF`9R"<$/(*O+28%K$7D7=@LN.KWAZ(VB^B@!00
M`!$9^\UOHJ[K[U,@=;HWB`AA&)(DB39$EF6(R$\,-Q"`)$E02FF#`*1I>M6V
MM5:[(QZ0;FB%Y'G.\7@T"\GS'("F:<Q!6@2`Z[J#GND=OG^-\_E,4117?9-#
MFJ:A+,N;_L5B,1WD=#I1557OM:&04?Z1WQ"30BZ7RW]3`"-`;-MFM]N9AP`X
MCL-VNS4/@<]A&L>Q>0B`YWFLUVOS$`#?]UFM5N8A`,OE$J44MCT\O;9)+P@"
M-IN->8AE68/G&:V0>^,!Z4;O[)MEF=:B??EGL])K&[-9^[888[L!L]D?^0#`
3M8HSIG;M-P````!)14Y$KD)@@@``
`
end
