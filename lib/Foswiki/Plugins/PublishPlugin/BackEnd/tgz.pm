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

    my $pf = ( $params->{outfile} || 'tgz' );
    $params->{outfile} = '';
    my $this = $class->SUPER::new( $params, $logger );

    require Archive::Tar;

    $this->{tgzfile} = $pf;
    $this->{tgzfile} .= '.tgz' unless $this->{tgzfile} =~ /\.\w+$/;
    $this->{tgz}         = Archive::Tar->new();
    $this->{rsrc_path}   = ( $params->{rsrcdir} || 'rsrc' );
    $this->{resource_id} = 0;

    return $this;
}

sub param_schema {
    my $class = shift;
    my $base  = $class->SUPER::param_schema();
    $base->{outfile}->{default} = 'tgz';
    return $base;
}

sub addTopic {
    my ( $this, $web, $topic, $text ) = @_;
    my $path = "$web/$topic.html";
    $this->{logger}
      ->logError( "Error adding $web.$topic: " . $this->{tgz}->error() )
      unless $this->{tgz}->add_data( $path, $text );
    return $path;
}

sub getTopicPath {
    my ( $this, $web, $topic ) = @_;
    return "$web/$topic.html";
}

sub addAttachment {
    my ( $this, $web, $topic, $att, $data ) = @_;
    my $pth = "$web/$topic.attachments/$att";
    $this->{logger}->logError( "Error adding $pth: " . $this->{tgz}->error() )
      unless $this->{tgz}->add_data( $pth, $data );
    return $pth;
}

sub addRootFile {
    my ( $this, $file, $data ) = @_;
    $this->{logger}->logError( "Error adding $file: " . $this->{tgz}->error() )
      unless $this->{tgz}->add_data( $file, $data );
    return $file;
}

sub addResource {
    my ( $this, $data, $ext ) = @_;
    my $path = $this->{rsrc_path};
    $this->{resource_id}++;
    $ext //= '';
    $path = "$path/rsrc$this->{resource_id}$ext";
    $this->{logger}->logError( "Error adding $path: " . $this->{tgz}->error() )
      unless $this->{tgz}->add_data( $path, $data );
    return $path;
}

sub close {
    my $this = shift;
    my $u    = $this->SUPER::close();
    my $end  = $this->pathJoin( $this->{file_root}, $this->{tgzfile} );

    unless ( $this->{tgz}->write( $end, 1 ) ) {
        $this->{logger}->logError( $this->{tgz}->error() );
    }
    return $u . '/' . $this->{tgzfile};
}

1;
