#!/usr/bin/perl
# match gpsdrive poi_types with osm types and update the
# poi column inside the mapnik postgis db

# Get version number from version-control system, as integer 
my $version = '$Revision: 1824 $';
$Version =~ s/\$Revision:\s*(\d+)\s*\$/$1/;
 
my $VERSION ="gpsdrive-update-mapnik-poitypes.pl (c) Guenther Meyer
Version 0.1-$Version";


BEGIN {
    my $dir = $0;
    $dir =~s,[^/]+/[^/]+$,,;
    unshift(@INC,"$dir/perl_lib");

    # For Debug Purpose in the build Directory
    unshift(@INC,"./perl_lib");
    unshift(@INC,"./osm/perl_lib");
    unshift(@INC,"./scripts/osm/perl_lib");
    unshift(@INC,"../scripts/osm/perl_lib");

    # For DSL
    unshift(@INC,"/opt/gpsdrive/share/perl5");
    unshift(@INC,"/opt/gpsdrive"); # For DSL
};

use strict;
use warnings;

use DBI;
use Getopt::Long;
use Utils::Debug;
use Pod::Usage;

my ($man);
my ($help);
my $do_show_version=0;
my $do_not_add_column=0;
my $dbh_postgis;
my $sth_postgis;
my $dbh_sqlite;
my $sth_sqlite;

my $db_name = 'gis';
my $db_table = 'planet_osm_point';
my $db_file = '/usr/share/gpsdrive/geoinfo.db';

# Set defaults and get options from command line
Getopt::Long::Configure('no_ignore_case');
GetOptions
(
  'verbose'	=> \$VERBOSE,
  'v+'		=> \$VERBOSE,
  'h|help'	=> \$help,
  'man'    	=> \$man,
  'version'	=> \$do_show_version,
  'n'		=> \$do_not_add_column,
)
  or pod2usage(1);


if ( $do_show_version )
{
  print "$VERSION\n";
};
pod2usage(-verbose=>2) if $man;
pod2usage(1) if $help;


#############################################################################
# Connect to database and add column 'poi' if not yet available
#
sub update_poi_column()
{
  my %osm_types;
  my $i = 0;
  my $j = 0;

  my $db_query = 'SELECT key,value,poi_type FROM osm;';
  $sth_sqlite = $dbh_sqlite->prepare($db_query) or die $dbh_sqlite->errstr; 
  $sth_sqlite->execute() or die $sth_sqlite->errstr;

  while (my @row = $sth_sqlite->fetchrow_array)
  {
    $sth_postgis = $dbh_postgis->prepare(qq{UPDATE $db_table SET poi=? WHERE $row[0]=? AND poi IS NULL;});
    $i = $sth_postgis->execute($row[2], $row[1]);
    print "\n$i\t$row[0] = $row[1]\t--->\t$row[2]" if ($VERBOSE && $i > 0);
    $j += $i;
  }
  print "\n";
  print "$j rows updated.\n";

  $dbh_postgis->commit()
    or warn $sth_postgis->errstr;

  $sth_sqlite->finish;
  $sth_postgis->finish;
}


#############################################################################
#
#                     Main
#
#############################################################################

# connect to databases
$dbh_postgis = DBI->connect("dbi:Pg:dbname=$db_name",'','',{ RaiseError => 1, AutoCommit => 0 })
  or die $dbh_postgis->errstr;

$dbh_sqlite = DBI->connect("dbi:SQLite:dbname=$db_file",'','',{ RaiseError => 1, AutoCommit => 1 })
  or die $dbh_postgis->errstr;
$dbh_sqlite->{unicode} = 1;


# add poi column to database
unless ($do_not_add_column)
{
  print "Adding column 'poi' to database...\n" if ($VERBOSE);
  $sth_postgis = $dbh_postgis->prepare("ALTER TABLE $db_table ADD COLUMN poi text;");
  $sth_postgis->execute()
    or warn $sth_postgis->errstr;
  $dbh_postgis->commit()
    or warn $sth_postgis->errstr;
}


# fill poi column
print "Looking for known tags and updating poi column...\n";
update_poi_column();


# disconnect from database
$dbh_postgis->disconnect
  or warn $dbh_postgis->errstr;

$dbh_sqlite->disconnect
  or warn $dbh_sqlite->errstr;


__END__

=head1 NAME

B<gpsdrive-update-mapnik-poitypes.pl> Version 0.2

=head1 DESCRIPTION

B<gpsdrive-update-mapnik-poitypes.pl> is a program that looks for entries
indicating "Points of Interest" inside the mapnik database, and adds the
matching gpsdrive poi_types to a separate column called "poi".


=head1 SYNOPSIS

B<Common usages:>

gpsdrive-update-mapnik-poitypes.pl [-v] [-h] [-n] [--in=File_in.xml] [--out=File_out.xml]

=head1 OPTIONS

=over 2

=item B<--in [Filename]>

Filename to read


=item B<--out [Filename]>

Filename to write


=head1 WARNING: 

This program replaces some/all poi entries.
So any changes made to the database may be overwritten!!!

=back
