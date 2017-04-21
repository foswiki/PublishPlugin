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
our @ISA = ('Foswiki::Plugins::PublishPlugin::BackEnd');

use constant DESCRIPTION =>
'Single HTML file containing all topics. Attachments (and external resources if =copyexternal is selected=) will be saved to a top level =_rsrc= directory next to the HTML file.';

sub new {
    my ( $class, $params, $logger ) = @_;

    $params->{dont_scan_existing} = 1;
    my $this = $class->SUPER::new( $params, $logger );

    $this->{flatfile} = ( $params->{outfile} || 'flatfile' );
    $this->{flatfile} .= '.html' unless $this->{flatfile} =~ /\.\w+$/;

    my $fn = "$Foswiki::cfg{Plugins}{PublishPlugin}{Dir}/$this->{flatfile}";
    my $fh;
    if ( open( $fh, '>', $fn ) ) {
        binmode($fh);
        $this->{flatfh} = $fh;
    }
    else {
        $this->{logger}->logError("Cannot write $fn: $!");
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
    my $fh = $this->{flatfh};
    print $fh "<a name='$anchor'></a>";
    print $fh $text;
    return '#' . $anchor;
}

sub addAttachment {

    # Default is to store attachments in a .attachments dir next to
    # the topic. That won't work for flatfile, as the topics are all
    # in one file, so whack them into the resource dir instead.
    my ( $this, $web, $topic, $attachment, $data ) = @_;
    return $this->addResource( $data, $attachment );
}

sub close {
    my $this = shift;

    close( $this->{flatfile} ) if $this->{flatfile};
    return $this->{flatfile};
}

1;

