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

    my $pf = ( $params->{outfile} || 'zip' );
    $params->{outfile} = '';
    my $this = $class->SUPER::new( $params, $logger );

    $this->{zipfile} = $pf;
    $this->{zipfile} .= '.zip' unless $this->{zipfile} =~ /\.\w+$/;
    $this->{zip}         = Archive::Zip->new();
    $this->{rsrc_path}   = ( $params->{rsrcdir} || 'rsrc' );
    $this->{resource_id} = 0;

    return $this;
}

sub param_schema {
    my $class = shift;
    my $base  = $class->SUPER::param_schema();
    $base->{outfile}->{default} = 'zip';
    return $base;
}

sub addTopic {
    my ( $this, $web, $topic, $text ) = @_;
    my $path = "$web/$topic.html";
    $this->{logger}->logError("Error adding $web.$topic")
      unless $this->{zip}->addString( $text, $path );
    return $path;
}

sub getTopicPath {
    my ( $this, $web, $topic ) = @_;
    return "$web/$topic.html";
}

sub addAttachment {
    my ( $this, $web, $topic, $att, $data ) = @_;
    my $pth = "$web/$topic.attachments/$att";
    $this->{logger}->logError("Error adding $pth")
      unless $this->{zip}->addString( $data, $pth );
    return $pth;
}

sub addResource {
    my ( $this, $data, $ext ) = @_;
    my $path = $this->{rsrc_path};
    $this->{resource_id}++;
    $ext //= '';
    $path = "$path/rsrc$this->{resource_id}$ext";
    $this->{logger}->logError("Error adding $path")
      unless $this->{zip}->addString( $data, $path );
    return $path;
}

sub addRootFile {
    my ( $this, $file, $data ) = @_;
    $this->{logger}->logError("Error adding $file")
      unless $this->{zip}->addString( $data, $file );
    return $file;
}

sub close {
    my $this = shift;

    my $end = $this->pathJoin( $this->{file_root}, $this->{zipfile} );
    my $u = $this->SUPER::close();

    $this->{logger}->logError("Error writing $end")
      if $this->{zip}->writeToFileNamed($end);
    return $u . '/' . $this->{zipfile};
}

1;
