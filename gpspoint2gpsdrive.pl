#!/usr/bin/perl -w
#
# gpspoint2gpsdrive.pl
#
# Convert gpspoint track file to gpsdrive track file(s)
#
# Copyleft 2002 Stephen Merrony <steveATcygnetDOTcoDOTuk>
#
#    This program is free software; you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation; either version 2 of the License, or
#    (at your option) any later version.
#
#    This program is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with this program; if not, write to the Free Software
#    Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
#
# Change log:
#
# Author         Version       Details
#---------------------------------------------------------------------------------
# S.Merrony       0.0.2        Fix bogus track extraction, add waypoint extraction
# S.Merrony       0.0.3        Fix case where no altitude, add version number to help
#
# $Log$
# Revision 1.4  2006/07/31 08:20:08  tweety
# lat/long space problem fix
# http://bugzilla.gpsdrive.cc/show_bug.cgi?id=78
#
# Revision 1.3  2005/04/13 19:58:30  tweety
# renew indentation to 4 spaces + tabstop=8
#
# Revision 1.2  2005/04/10 00:15:58  tweety
# changed primary language for poi-type generation to english
# added translation for POI-types
# added some icons classifications to poi-types
# added LOG: Entry for CVS to some *.pm Files
#

BEGIN {
    my $dir = $0;
    $dir =~s,[^/]+/[^/]+$,,;
    unshift(@INC,"$dir/perl_lib");

    # For Debug Purpose in the build Directory
    unshift(@INC,"./perl_lib");
    unshift(@INC,"./scripts/perl_lib");
    unshift(@INC,"../scripts/perl_lib");

    # For DSL
    unshift(@INC,"/opt/gpsdrive/share/perl5");
    unshift(@INC,"/opt/gpsdrive"); # For DSL
};

my $Version = '$Revision: 2110 $'; 
$Version =~ s/\$Revision:\s*(\d+)\s*\$/$1/; 

use strict;

my %opts;
use Getopt::Std;
getopts('hf:wv', \%opts);

$opts{h} = 0 if (!defined( $opts{h} ));
$opts{w} = 0 if (!defined( $opts{w} ));
$opts{v} = 0 if (!defined( $opts{v} ));

my $trackfnprefix = "track";
my $trackfnext    = ".sav";
my $pointformat   = "%10.6f %10.6f %10.0d %s\n";  # <=== This is the gpsdrive track format ===
my $wayptfilename = "way.txt";
my $wayptformat   = "%s %10.6f %10.6f\n";      # <=== This is the gpsdrive waypoint format ===

my $wayptcnt      = 0;
my $trackcount    = 0;

# Help!
if ($opts{h} ) {
    my $help = <<'ENDOFHELP';

    gpspoint2gpsdrive.pl:
    =====================

	Extract gpsdrive-compatible track file(s) from a gpspoint file.
	Optionally also extracts waypoints and appends them to way.txt.

	-h                     This help message - you guessed that!
	-f <gpspointfilename>  The file to extract tracks from.
	-w                     Extract waypoints and append to way.txt
	-v                     Verbose mode - yada yada yada

	Version $Version

ENDOFHELP
	print $help;
    exit;
}

if (!$opts{f} or $opts{f} eq "" ) {
    print "Error: You must enter a filename via the -f switch.\n";
    exit;
}

use FileHandle;

my $infile;

# open the file for reading if we can - else bail out
$infile = new FileHandle "< $opts{f}";
if (!defined( $infile )) {
    print "Error: Unable to open file '$opts{f}' for input\n";
    exit;
}

my $am_writing = 0;

my ($latitude, $longitude,  $timestamp, $wayptname);
my $altitude = 1.0;
my $thisline;
my $trackfilename;
my $trackfile = new FileHandle;
my $wayptfile = new FileHandle;
my $blocktype;
my $dummytime = 0;

# plough through the file
while (<$infile>) {

    $thisline = $_;
    chomp( $thisline ); # remove newline

    # Gpspoint files contain comments starting with a # symbol, blank lines
    # and lines with comma separated lists of values and name-value pairs
    # We only want certain name-value pairs...

    # ignore comments and blank or very short lines
    if ( (substr( $thisline, 0, 1 ) ne "#") &&
	 (length( $thisline ) > 5 ) ) {
	
	my (@pairs, $pair);

	@pairs = split( /\s+/, $thisline );
	foreach $pair ( @pairs ) {
	    my $name = "";
	    my $value = "";
	    ($name, $value) = split( '=', $pair );
	    if (defined( $name ) && defined( $value )) { # only process pairs
		$value = substr( $value, 1, length( $value ) - 2 );  # remove quotes

		# starting a new track?
		if (($name eq "type") && ($value eq "track" )) {
		    # $trackfile->close if ($am_writing);
		    $am_writing = 0;
		    $blocktype = "TRACK";
		    print "Info: Found start of track\n" if ($opts{v} eq 1);
		}
		# new set of waypoints?
		elsif (($name eq "type") && ($value eq "waypointlist") && $opts{w}) {
		    $am_writing = 0;
		    $blocktype = "WAYPOINTS";
		    print "Info: Found start of waypoint list\n" if ($opts{v} eq 1);
		    if (!$wayptfile->open( ">> $wayptfilename" )) {
			print "Error: Unable to append to waypoint file '$wayptfilename'\n";
			exit;
		    }
		    $am_writing = 1;
		    print "Info: Starting writing waypoint s to '$wayptfilename'\n" if ($opts{v} eq 1);
		}
		elsif (($name eq "type") && ($value eq "route")) {
		    # not interested in routes at this stage
		    $blocktype = "";
		    $am_writing = 0;
		}
		
		# trap other info types here?

		# name of a new track
		if (defined( $name ) && ($name eq "name") && defined( $blocktype ) && ($blocktype eq "TRACK")) {
		    $trackfilename = $trackfnprefix . $value . $trackfnext;
		    if (!$trackfile->open("> $trackfilename" )) {
			print "Error: Unable to open track output file '$trackfilename'\n";
			exit;
		    }
		    $am_writing = 1;
		    $trackcount++;
		    print "Info: Starting to write track '$trackfilename'\n" if ($opts{v} eq 1);
		}

		# name of a new waypoint
		if (($opts{w} eq 1) && ($blocktype eq "WAYPOINTS") && ($name eq "name")) {
		    $wayptname = $value;
		    $wayptcnt++;
		}

		if ($name eq "latitude" ) {
		    $latitude  = $value;
		}
		if ($name eq "longitude" ) {
		    $longitude = $value;
		}
		if ($name eq "altitude" ) {
		    $altitude  = $value;
		}
		if ($name eq "unixtime" ) {
		    $timestamp = localtime( $value );
		}
	    }
	    $latitude  = $1 if $thisline =~ m/latitude=\"\s*([\+\-\d\.\,]+)\"/;
	    $longitude = $1 if $thisline =~ m/longitude=\"\s*([\+\-\d\.\,]+)\"/;
	    $altitude  = $1 if $thisline =~ m/altitude=\"\s*([\+\-\d\.\,]+)\"/;
	} # end of name-value pair loop
	#print $thisline;
    } #end if

    # done with this line - write out a trackfile line if we have one
    if ($am_writing && defined( $longitude )  && ($blocktype eq "TRACK")) {
	# some tracks have no time info - so we'll insert an early timestamp
	$timestamp = localtime(0) if (!defined( $timestamp ));
	printf $trackfile $pointformat, ($latitude, $longitude, $altitude, $timestamp);
    }

    # done with this line - write out a waypoint line if we have one
    if ($am_writing && defined( $latitude )  && ($blocktype eq "WAYPOINTS")) {
	printf $wayptfile $wayptformat, ($wayptname, $latitude, $longitude);
    }

} # end of per-line loop

# clean up nicely
$infile->close;
$trackfile->close if ($opts{w} eq 1);

print "Info: All done.\n" if ($opts{v} eq 1);
print "$trackcount tracks and $wayptcnt waypoints extracted\n";

__END__


=head1 NAME

B<gpspoint2gpsdrive.pl>

=head1 DESCRIPTION

B<gpspoint2gpsdrive.pl>

Extract gpsdrive-compatible track file(s) from a gpspoint file.
Optionally also extracts waypoints and appends them to way.txt.

=head1 SYNOPSIS

B<Common usages:>

=head1 OPTIONS


=over 8

=item B<-h>

This help message - you guessed that!

=item B<-f> <gpspointfilename>

The file to extract tracks from.

=item B<-w>

Extract waypoints and append to way.txt

=item B<-v>

Verbose mode - yada yada yada


=head1 AUTHOR

Written by 

=head1 COPYRIGHT

This is free software.  You may redistribute copies of it under the terms of the GNU General Pub-
lic  License <http://www.gnu.org/licenses/gpl.html>.  There is NO WARRANTY, to the extent permit-
ted by law.

=head1 SEE ALSO

gpsdrive(1)

=cut
