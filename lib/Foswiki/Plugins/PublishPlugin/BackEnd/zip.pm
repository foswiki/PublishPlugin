#
# Copyright (C) 2005-2018 Crawford Currie, http://c-dot.co.uk
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details, published at
# http://www.gnu.org/copyleft/gpl.html
#
# Archive::Zip writer module for PublishPlugin
#
package Foswiki::Plugins::PublishPlugin::BackEnd::zip;

use strict;

use Foswiki::Plugins::PublishPlugin::BackEnd::file;
our @ISA = ('Foswiki::Plugins::PublishPlugin::BackEnd::file');

use constant DESCRIPTION =>
  'HTML compressed into a single zip file for shipping.';

use Foswiki::Func;
use File::Path;

sub new {
    my ( $class, $params, $logger ) = @_;

    eval 'use Archive::Zip qw( :ERROR_CODES :CONSTANTS )';
    die $@ if $@;

    $params->{dont_scan_existing} = 1;

    my $this = $class->SUPER::new( $params, $logger );

    $this->{zip} = Archive::Zip->new();

    my $zf = $params->{outfile} || 'zip';
    $zf .= '.zip' unless $zf =~ /\.\w+$/;
    my @path = ();
    if ( $params->{relativedir} ) {
        push( @path, split( /\/+/, $params->{relativedir} ) );
    }
    push( @path, $zf );

    $this->{zip_path} = join( '/', @path );
    $this->{zip_file} =
      join( '/', $Foswiki::cfg{Plugins}{PublishPlugin}{Dir}, @path );

    return $this;
}

# Override Foswiki::Plugins::PublishPlugin::BackEnd::file
sub param_schema {
    my $class = shift;
    my $base  = $class->SUPER::param_schema();
    delete $base->{keep};
    $base->{outfile}->{default} = 'zip';
    return $base;
}

# Override Foswiki::Plugins::PublishPlugin::BackEnd::file
sub addByteData {
    my ( $this, $file, $data ) = @_;
    $this->{logger}->logError("Error adding $file")
      unless $this->{zip}->addString( $data, Encode::encode_utf8($file) );
    return $file;
}

# Override Foswiki::Plugins::PublishPlugin::BackEnd::file
sub addPath {
}

# Override Foswiki::Plugins::PublishPlugin::BackEnd::file
sub close {
    my $this = shift;

    # SUPER::close to get index files
    $this->SUPER::close();

    if ( $this->{zip}->writeToFileNamed( $this->{zip_file} ) ) {
        $this->{logger}->logError("Error writing $this->{zip_file}");
    }
    return $this->{zip_path};
}

1;
