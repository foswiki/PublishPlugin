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
'Single HTML file containing all topics. If =copyexternal= is selected, external resources will be saved to a top level =_files= directory next to the HTML file.';

sub new {
    my ( $class, $params, $logger ) = @_;

    $params->{dont_scan_existing} = 1;
    my $this = $class->SUPER::new( $params, $logger );

    my $flatfile = ( $params->{outfile} || 'flatfile' );
    $this->{flatfile} =~ s/\.\w+$//;
    $this->{flatfile_rsrc} = $flatfile . "_files";
    $this->{flatfile_html} = $flatfile . ".html";

    my $fn =
      "$Foswiki::cfg{Plugins}{PublishPlugin}{Dir}/$this->{flatfile_html}";
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

sub param_schema {
    my $class = shift;
    my $base  = $class->SUPER::param_schema();
    delete $base->{keep};
    delete $base->{defaultpage};    # meaningless in a flat file
    $base->{outfile}->{default} = 'flatfile';
    return $base;
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
    print $fh "<a name=\"$anchor\"'></a>";
    print $fh $text;
    return '#' . $anchor;
}

# Implement Foswiki::Plugins::PublishPlugin::BackEnd
sub addAttachment {

    # Default is to store attachments in a .attachments dir next to
    # the topic. That won't work for flatfile, as the topics are all
    # in one file, so whack them into the resource dir instead.
    my ( $this, $web, $topic, $attachment, $data ) = @_;
    return $this->addResource( $data, $attachment );
}

# Implement Foswiki::Plugins::PublishPlugin::BackEnd
sub addResource {
    my ( $this, $data, $name ) = @_;
    my $prefix = '';
    my $ext    = '';
    if ( $ext =~ /(.*)(\.\w+)$/ ) {
        $prefix = $1 // '';
        $ext = $2;
    }
    $this->{resource_id}++;
    my $path = "$this->{flatfile_rsrc}/$prefix$this->{resource_id}$ext";
    my $dest = "$Foswiki::cfg{Plugins}{PublishPlugin}{Dir}/$path";
    $this->addPath( $dest, 1 );
    my $fh;
    unless ( open( $fh, ">", $dest ) ) {
        $this->{logger}->logError("Failed to write $dest:  $!");
        return;
    }
    if ( defined $data ) {
        print $fh $data;
    }
    else {
        $this->{logger}->logError("$dest has no data, empty file created");
    }
    close($fh);
    $this->{logger}->logInfo( '', 'Published ' . $path );
    return $path;
}

# Implement Foswiki::Plugins::PublishPlugin::BackEnd
sub close {
    my $this = shift;

    close( $this->{flatfile} ) if $this->{flatfile};
    return $this->{flatfile};
}

1;

