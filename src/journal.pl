#!/usr/bin/perl -w
my $RCS_Id = '$Id$ ';

# Skeleton for Getopt::Long.

# Author          : Johan Vromans
# Created On      : Thu Jun  3 20:43:47 2004
# Last Modified By: Johan Vromans
# Last Modified On: Thu Jun  3 23:04:35 2004
# Update Count    : 90
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

my $br = "<br>";

################ The Process ################


my $block = "";
my $tb = qq(<table width="500" border="0" cellpadding="0" cellspacing="10">);
print <<EOD;
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
EOD

my $havetb = 0;

while ( <> ) {
    chomp;
    next unless /\S/;
    if ( /#\s*(.*)/ ) {
	$block .= $1 . "\n";
	next;
    }
    if ( /^!tag\s*(.*)/ ) {
	block();
	head($1);
	next;
    }
    next if /^!/;
    if ( /^(\S+)\s*(.*)/ ) {
	if ( $1 eq "*" ) {
	    $block = "";
	    next;
	}
	image($1, $2);
    }
}
block();

print("  </table>\n") if $havetb;
print("</body>\n",
      "</html>\n");

exit 0;

################ Subroutines ################

sub head {
    print("  </table>\n") if $havetb;
    print("  ",
	  indent(2, $tb),
	  "\n");
    $havetb = 1;
    print("    ",
	  indent(4,
		 "<tr>",
		 "  <td bgcolor='#C0C0C0' colspan='2'>",
		 "    <p class='hd'>" . html($_[0]) . "</p>",
		 "  </td>",
		 "</tr>"),
	  "\n");
}

sub block {
    return unless $block;
    twocol($block, "&nbsp;");
    $block = "";
}

sub image {
    my ($name, $desc) = @_;
    twocol($block,
	   "<a href='medium/$name' border='0'>" .
	   "<img src='thumbnails/$name'></a>");
    $block = "";
}

sub twocol {
    my ($c1, $c2) = @_;
    print("  ",
	  indent(2, $tb),
	  "\n") unless $havetb++;
    print("    ",
	  indent(4,
		 "<tr>",
		 "  <td valign='middle' align='left'>",
		 "    " . indent(4, $c1),
		 "  </td>",
		 "  <td valign='top' align='left'>",
		 "    " . indent(4, $c2),
		 "  </td>",
		 "</tr>"),
	  "\n");
}

sub indent {
    # Shift contents to the right so it fits pretty.
    my ($n, @t) = @_;
    $n = " " x $n;
    return $n unless @t && "@t";
    my $t = join("\n", map { detab($_) } @t);
    $t =~ s/\n+$//;
    $t =~ s/\n/\n$n/g;
    $t;
}

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

sub detab {
    my ($line) = @_;

    my (@l) = split(/\t/, $line);

    # Replace tabs with blanks, retaining layout

    $line = shift(@l);
    $line .= " " x (8-length($line)%8) . shift(@l) while @l;

    $line;
}

################ Command Line Options ################

use Getopt::Long 2.34;		# will enable help/version

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

sample - skeleton for Getopt::Long applications

=head1 SYNOPSIS

sample [options] [file ...]

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

B<This program> will read the given input file(s) and do someting
useful with the contents thereof.

=head1 AUTHOR

Johan Vromans <jvromans@squirrel.nl>

=head1 COPYRIGHT

This programs is Copyright 2003, Squirrel Consultancy.

This program is free software; you can redistribute it and/or modify
it under the terms of the Perl Artistic License or the GNU General
Public License as published by the Free Software Foundation; either
version 2 of the License, or (at your option) any later version.

=cut
