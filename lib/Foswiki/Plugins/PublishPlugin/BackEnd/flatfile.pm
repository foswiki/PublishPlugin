#
# Copyright (C) 2012 Crawford Currie, http://c-dot.co.uk
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
# File writer module for PublishPlugin
#
package Foswiki::Plugins::PublishPlugin::BackEnd::flatfile;

use strict;

use Foswiki::Plugins::PublishPlugin::BackEnd::file;
our @ISA = ('Foswiki::Plugins::PublishPlugin::BackEnd::file');

use constant DESCRIPTION =>
'Single HTML file containing all topics. Attachments will be saved to a resource directory on the server.';

sub new {
    my ( $class, $params, $logger ) = @_;
    my $this = $class->SUPER::new( $params, $logger );

    $this->{flatfile} = ( $params->{outfile} || 'flatfile' );
    $this->{flatfile} .= '.html' unless $this->{flatfile} =~ /\.\w+$/;

    my $fh;
    if ( open( $fh, '>', "$this->{file_root}/$this->{flatfile}" ) ) {
        binmode($fh);
        $this->{flatfile} = $fh;
    }
    else {
        $this->{logger}
          ->logError("Cannot write $this->{file_root}/$this->{flatfile}: $!");
    }
    return $this;
}

sub _makeAnchor {
    my ( $w, $t ) = @_;
    my $s = "$w/$t";
    $s =~ s![/.]!_!g;
    $s =~ s/([^ -~])/'_'.ord($1)/ge;
    return $s;
}

sub getTopicPath {
    my ( $this, $web, $topic ) = @_;
    return '#' . _makeAnchor( $web, $topic );
}

sub addTopic {
    my ( $this, $web, $topic, $text ) = @_;

    # Topics can be added inline to master with an anchor
    my $anchor = _makeAnchor( $web, $topic );
    my $fh = $this->{flatfile};
    print $fh "<a name='$anchor'></a>";
    print $fh $text;
    return '#' . $anchor;
}

sub close {
    my $this = shift;

    close( $this->{flatfile} ) if $this->{flatfile};
    return $this->SUPER::close() . '/' . $this->{flatfile};
}

1;

