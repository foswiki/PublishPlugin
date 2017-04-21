#
# Copyright (C) 2005-2017 Crawford Currie, http://c-dot.co.uk
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

    $this->{zip_path} = $this->{output_file};    # from superclass
    $this->{zip_path} .= '.zip' unless $this->{zip_path} =~ /\.\w+$/;
    $this->{zip_file} =
      $this->pathJoin( $Foswiki::cfg{Plugins}{PublishPlugin}{Dir},
        $this->{zip_path} );
    $this->addPath( $this->{zip_file}, 1 );

    return $this;
}

sub param_schema {
    my $class = shift;
    my $base  = $class->SUPER::param_schema();
    $base->{outfile}->{default} = 'zip';
    return $base;
}

sub addByteData {
    my ( $this, $file, $data ) = @_;
    $this->{logger}->logError("Error adding $file")
      unless $this->{zip}->addString( $data, Encode::encode_utf8($file) );
    return $file;
}

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
