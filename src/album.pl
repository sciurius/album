#!/usr/bin/perl -w
my $RCS_Id = '$Id$ ';

# Skeleton for Getopt::Long.

# Author          : Johan Vromans
# Created On      : Tue Sep 15 15:59:04 1992
# Last Modified By: Johan Vromans
# Last Modified On: Thu Sep 12 13:59:13 2002
# Update Count    : 431
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
my $index_buttons = 0;
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

$src_dir = "$dest_dir/large" unless $src_dir;
mkpath(["$dest_dir"], 1);
my $target_is_source = do {
    my @src = stat($src_dir);
    my @dst = stat($dest_dir);
    $src[0] == $dst[0] && $src[1] == $dst[1];
};

################ Presets ################

my $TMPDIR = $ENV{TMPDIR} || $ENV{TEMP} || '/usr/tmp';

my $css = <<EOD;
body  { font-size: 80%; font-family: Verdana, Arial, Helvetica; }
td    { font-size: 80%; font-family: Verdana, Arial, Helvetica; }
EOD
my $bodyatts = "text=\"#000000\" link=\"#000000\" vlink=\"#000000\"".
               " alink=\"#FF0000\" bgcolor=\"#C0C0C0\"";
my $suffixpat = qr{\.(?:jpe?g|png|gif)}i;

################ The Process ################

use File::Path;
use File::Copy;

# The list of files, in the order to be processed.
my @filelist;

# Individual file properties:
my %captions;			# descriptions
my %rotate;			# rotate info (degrees clockwise)
my %tag;			# tag info
my %seen;			# to keep track

my $add_from_src = 0;		# no info file, or wildcard seen

# Storage for image info. Will be cached.
our $info;

# Load image names and info from the info file, if any.
load_image_info();

set_parameter_defaults();

# Add image names from the source directory, if needed.
get_image_names();

my $num_entries = scalar(@filelist);
print STDERR ("Number of entries = $num_entries\n") if $verbose;
die("Nothing to do?\n") unless $num_entries > 0;

# Clean up and create thumbnails directory.
if ( $clobber ) {
    rmtree(["$dest_dir/thumbnails", "$dest_dir/medium"], 1);
}
mkpath(["$dest_dir/thumbnails", "$dest_dir/large"], 1);
mkpath(["$dest_dir/medium"], 1) if $medium;

# Load cached info, if possible.
load_cache();

# Copy images in place, rotate if necessary, and create the thumbnails.
prepare_images();

# Update cache.
update_cache();

my $entries_per_page = $index_columns*$index_rows;
my $num_indexes = int(($num_entries - 1) / $entries_per_page) + 1;

# Write the individual pages.
print STDERR ("Creating pages for ", $num_entries, " images\n") if $verbose;
my $i;
for ( $i = 0; $i < $num_entries; $i++ ) {
    write_image_page($i, "large");
    write_image_page($i, "medium") if $medium;
}

# Number of pages.
print STDERR ("Creating pages for ", $num_indexes, " indexes\n") if $verbose;

# Write the index pages.
for ( $i = 0; $i < $num_indexes; $i++ ) {
    write_index_page($i);
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
    $add_from_src++, return unless $image_info;

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
	    $captions{$file} .= "\n" . $_;
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
	$captions{$file} = $a || "";
	$rotate{$file} = $rotate unless $target_is_source;
	$tag{$file} = $tag if $tag;
	next if $file eq "*";
	unless ( -s "$src_dir/$file" ) {
	    warn("$src_dir/$file (info): $!\n");
	    $err++;
	}
	$seen{$file}++;
	push(@filelist, $file) unless $captions{$file} =~ /^--/;
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
			    && !/^(first|last|next|prev|index)\.png$/
			      && $_ ne "thumbnails" } readdir($dh) ) {
	next if $seen{$_}++;
	push(@filelist, $_);
	$captions{$_} = $captions{"*"};
	$rotate{$_} = $rotate{"*"};
    }

    close($dh);
}

sub prepare_images {

    foreach my $file ( @filelist ) {
	print STDERR ("$file... ") if $verbose;

	my $i_src     = "$src_dir/$file";
	my $i_large   = "$dest_dir/large/$file";
	my $i_medium  = "$dest_dir/medium/$file";
	my $i_small   = "$dest_dir/thumbnails/$file";

	# Copy the file into place. Rotate if needed.
	if ( $clobber || ! -s $i_large ) {
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

	# Get info.
	if ( $info->{$file} ) {
	    print STDERR ("cached... ") if $verbose;
	}
	else {
	    my $inf = `identify -verbose -format "%w %h" $i_large`;
	    die("Aborted\n") if $? == 2;
	    die(sprintf("identify error: 0x%02x%02x\n", $? >> 8, $? & 0xff))
	      if $? || $inf !~ /^(\d+)\s+(\d+)/;
	    $info->{$file} = [ -s $i_large, 0, $1, $2 ];
	}

	my $neednl = 0;
	if ( $medium && ($clobber  || ! -s $i_medium) ) {
	    my @t = ( $medium );
	    $t[1] = int(0.67 * $t[0]);
	    system("convert ".
		   ($verbose ? "-verbose" : "") ." -geometry ".
		   (( $info->{$file}->[2] > $info->{$file}->[3] )
		    ? "$t[0]x$t[1]" : "$t[1]x$t[0]") .
		   " $i_large $i_medium");
	    die("Aborted\n") if $? == 2;
	    die(sprintf("convert error: 0x%02x%02x\n", $? >> 8, $? & 0xff))
	      if $?;
	}
	else {
	    $neednl++;
	}
	$info->{$file}->[1] = -s $i_medium if $medium;
	print STDERR ("@{$info->{$file}} ") if $verbose;

	if ( $clobber || ! -s $i_small ) {
	    my @t = ( $thumb );
	    $t[1] = int(0.67 * $t[0]);
	    system("convert ".
		   ($verbose ? "-verbose" : "") ." -geometry ".
		   (( $info->{$file}->[2] > $info->{$file}->[3] )
		    ? "$t[0]x$t[1]" : "$t[1]x$t[0]") .
		   " $i_large $i_small");
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

sub write_image_page {
    my ($i, $dir) = @_;

    my $file = $filelist[$i];
    my $base = $file;
    $base =~ s/$suffixpat$/.html/;
    my $html = do { local *H; *H };
    open($html, ">$dest_dir/$dir/$base" )
      or die("$base (create): $!\n");

    my $t = "$album_title: Image " . ($i+1);
    $t .= " of " . $num_entries if $num_entries > 1;
    print $html ("<style type=\"text/css\">\n",
		 "<!--\n",
		 $css,
		 "-->\n",
		 "</style>\n",
		 "<html>\n",
		 "<head>\n",
		 "<title>$t</title>\n",
		 "</head>\n",
		 "<body $bodyatts>\n",
		 "<center><h1>$t</h1>\n",
		 "<br>\n",
		 "<a href=\"../index",
		 ($i >= $entries_per_page) ? int($i / $entries_per_page) : "",
		 ".html\">",
		 "<img src=\"../index.png\" border=\"0\" alt=\"[Index]\"></a>\n");

    # Link to first image.
    ($base = $filelist[0]) =~ s/$suffixpat$/.html/;
    print $html (button("first", $base, $i > 0), "\n");
    ($base = $filelist[$i-1]) =~ s/$suffixpat$/.html/;
    print $html (button("prev", $base, $i > 0), "\n");
    # Link to next image.
    ($base = $filelist[$i+1]) =~ s/$suffixpat$/.html/
      if $i < $num_entries-1;
    print $html (button("next", $base, $i < $num_entries-1), "\n");
    ($base = $filelist[-1]) =~ s/$suffixpat$/.html/;
    print $html (button("last", $base, $i < $num_entries-1), "\n");

    ($base = $file) =~ s/$suffixpat$/.html/;
    print $html ("<br><br>\n",
		 "<h2>", html($captions{$file}), "</h2><p>\n",
		 ($dir eq "medium") ?
		 "<a href=\"../large/$base\"><img src=\"$file\" alt=\"[Click for bigger image]\">" : "<img src=\"$file\"></a>",
		 "<br>\n",
		 $file, " ", $tag{$file}||"", " (",
		 join("x", @{$info->{$file}}[2,3]), ", ",
		 bytes($info->{$file}->[0]), ")\n",
		 "<p>\n",
		 "</center></body></html>\n");

    close($html);
}

sub write_index_page {
    my ($x) = @_;

    # Open the page for writing
    my $html = do { local *H; *H };
    if ( $x > 0 ) {
	open($html, ">$dest_dir/index$x.html")
	  or die("index$x.html (create): $!\n");
    }
    else {
	open($html, ">$dest_dir/index.html")
	  or die("index.html (create): $!\n");
    }

    my $t = $album_title.": Index";
    my $tt = $t;

    if ( $num_indexes > 1) {
	$tt .= " " . ($x+1) . " of $num_indexes";
	if ( $index_buttons ) {
	    $t .= " " . ($x+1) . " of $num_indexes";
	}
	else {
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
    }

    print $html ("<style type=\"text/css\">\n",
		 "<!--\n",
		 $css,
		 "-->\n",
		 "</style>\n",
		 "<html>\n",
		 "<head>\n",
		 "<title>$tt</title>\n",
		 "</head>\n",
		 "<body $bodyatts>\n",
		 "<center>\n",
		 "<h1>$t</h1>\n",
		 "<p>\n");

    if ( $index_buttons ) {
	if ( $x > 0 ) {
	    print $html (button("first"), "\n")
	      if $num_indexes > 2;
	    print $html (button("prev",
				"index".($x > 1 ? $x-1 : "").".html"), "\n");
	}

	if ( $x < $num_indexes-1 ) {
	    print $html (button("next", "index".($x+1).".html"), "\n");
	    print $html (button("last", "index".($num_indexes-1).".html"), "\n")
	      if $num_indexes > 2;
	}
    }

    print $html ("<table border=\"2\" cellpadding=\"0\" cellspacing=\"3\"",
		 " bgcolor=\"#E0E0E0\">\n");

    my $first_in_row = $x * $entries_per_page;

    for ( my $i = 0; $i < $index_rows; $i++, $first_in_row += $index_columns ) {
	# First row is the image thumbnails.
	if ( $first_in_row < $num_entries ) {
	    print $html ("  <tr>\n");
	    for ( my $j = 0; $j < $index_columns; $j++ ) {
		my $this = $first_in_row + $j;
		if ( $this < $num_entries ) {
		    my $file = $filelist[$this];
		    my $base = $medium ? "medium/" : "large/";
		    $base .= $file;
		    $base =~ s/$suffixpat$/.html/;
		    print $html ("    <td><center><a href=\"$base\"><img src=\"thumbnails/$file\" alt=\"[Click for bigger image]\" border=\"0\"></a></center></td>\n");
		}
		else {
		    print $html ("    <td>&nbsp</td>\n");
		}
	    }
	    print $html ("  </tr>\n");

	    # Second row is the image stats and caption text.
	    print $html ("  <tr>\n");
	    for ( my $j = 0; $j < $index_columns; $j++ ) {
		my $this = $first_in_row + $j;
		if ( $this < $num_entries ) {
		    my $file = $filelist[$this];
		    print $html ("    <td align=\"center\">");
		    foreach ( split(//, $caption) ) {
			print $html ($file) if $_ eq 'f';
			print $html (join("x", @{$info->{$file}}[2,3]),
				     ", ", bytes($info->{$file}->[$medium ? 1 : 0]))
			  if $_ eq 's';
			if ( $_ eq 'c' ) {
			    my $t = $captions{$file} || "";
			    $t =~ s/\n.*//;
			    print $html (html($t));
			}
			if ( $_ eq 't' ) {
			    print $html (html($tag{$file})) if $tag{$file};
			    next;
			}
			print $html ("<br>\n");
		    }
		    print $html ("</td>\n");
		}
		else {
		    print $html ("    <td>&nbsp</td>\n");
		}
	    }
	    print $html ("  </tr>\n");
	}
    }
    print $html ("</table>\n");

    print $html ("<p>\n",
		 "</center></body></html>\n");
    close($html);
}

sub button {
    my ($tag, $index, $active) = (@_, 1);
    my $Tag = ucfirst($tag);

    if ( $active ) {
	return "<a href=\"$index\" alt=\"[$Tag]\">".
	  "<img src=\"../$tag.png\" border=\"0\" alt=\"[$Tag]\">".
	    "</a>";
    }
    "<img src=\"../$tag.png\" border=\"0\" alt=\"[$Tag]\">";
}

sub html {
    my $t = shift;
    return '' unless $t;
    $t =~ s/\n+/<br>/g;
    $t;
}

sub bytes {
    my $t = shift;
    return $t . "b" if $t < 10*1024;
    return ($t >> 10) . "kb" if $t < 10*1024*1024;
    ($t >> 20) . "Mb";
}

sub load_cache {
    do "$dest_dir/.cache" if !$clobber && -s "$dest_dir/.cache";
}

sub update_cache {
    use Data::Dumper;
    my $cache = do { local *C; *C };
    open($cache, ">$dest_dir/.cache")
      and print $cache (Data::Dumper->Dump([$info],[qw(info)]), "\n1\n")
	and close($cache);
}

sub add_button_images {

    # Extract button images form DATA section.

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

################ Subroutines ################

sub app_options {
    my $help = 0;		# handled locally
    my $ident = 0;		# handled locally

    # Process options, if any.
    # Make sure defaults are set before returning!
    return unless @ARGV > 0;

    if ( !GetOptions(
		     'source=s'	=> \$src_dir,
		     'dest=s'	=> \$dest_dir,
		     'info=s'	=> \$image_info,
		     'cols=i'	=> \$index_columns,
		     'rows=i'	=> \$index_rows,
		     'thumbsize=i' => \$thumb,
		     'mediumsize=i' => \$medium,
		     'title=s'	=> \$album_title,
		     'clobber'	=> \$clobber,
		     'index-buttons' => \$index_buttons,
		     'caption=s' => \$caption,
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
    -info XXX		description and control file
    -title XXX		album title
    -dest XXX		where to place all files
    -source XXX		where the original images reside
    -cols NN		number of columns per page
    -rows NN		number of rows per page
    -thumbsize NNN	the max size of thumbnail images
    -medium NNN		the max size of moderate sized images
    -captions XXX	f: filename s: size c: description t: tag
    -clobber		recreate everything
    -index-buttons	use index buttons instead of links
    -help		this message
    -ident		show identification
    -verbose		verbose information
EndOfUsage
    exit $exit if defined $exit && $exit != 0;
}

__END__
begin 644 first.png
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
begin 644 index.png
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
begin 644 last.png
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
begin 644 next.png
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
begin 644 prev.png
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
