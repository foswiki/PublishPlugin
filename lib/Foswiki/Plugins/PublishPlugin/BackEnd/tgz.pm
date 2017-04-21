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
package Foswiki::Plugins::PublishPlugin::BackEnd::tgz;

use strict;

use Foswiki::Plugins::PublishPlugin::BackEnd::file;
our @ISA = ('Foswiki::Plugins::PublishPlugin::BackEnd::file');

use constant DESCRIPTION =>
  'HTML compressed into a single tgz archive for shipping.';

use Foswiki::Func;
use File::Path;
use Assert;

sub new {
    my ( $class, $params, $logger ) = @_;

    $params->{dont_scan_existing} = 1;

    my $this = $class->SUPER::new( $params, $logger );
    require Archive::Tar;
    $this->{tgz} = Archive::Tar->new();

    $this->{tgz_path} = $this->{output_file};    # from superclass
    $this->{tgz_path} .= '.tgz' unless $this->{tgz_path} =~ /\.\w+$/;
    $this->{tgz_file} =
      $this->pathJoin( $Foswiki::cfg{Plugins}{PublishPlugin}{Dir},
        $this->{tgz_path} );
    $this->addPath( $this->{tgz_file}, 1 );

    return $this;
}

sub param_schema {
    my $class = shift;
    my $base  = $class->SUPER::param_schema();
    $base->{outfile}->{default} = 'tgz';
    return $base;
}

sub addByteData {
    my ( $this, $file, $data ) = @_;
    $this->{logger}->logError( "Error adding $file: " . $this->{tgz}->error() )
      unless $this->{tgz}->add_data( Encode::encode_utf8($file), $data );
    return $file;
}

sub close {
    my $this = shift;

    # SUPER::close to get index files
    $this->SUPER::close();

    unless ( $this->{tgz}->write( $this->{tgz_file}, 1 ) ) {
        $this->{logger}->logError( $this->{tgz}->error() );
    }
    return $this->{tgz_path};
}

1;
