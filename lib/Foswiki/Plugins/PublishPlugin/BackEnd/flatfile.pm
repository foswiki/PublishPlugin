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

    my $this = $class->SUPER::new( $params, $logger );

    # {output} is the root for filenames in this generator.
    $this->{output} = $params->{outfile} || 'flatfile';

    # Append to {output} to save external resources to
    $this->{resource_path} = "_files";

    return $this;
}

sub getReady {
    my $this = shift;

    # Prune any existing resources
    File::Path::rmtree(
        "$this->{root}/$this->{relative_path}/$this->{output}_files");
}

# Override Foswiki::Plugins::PublishPlugin::BackEnd::file
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

# Override Foswiki::Plugins::PublishPlugin::BackEnd::file
sub getTopicPath {
    my ( $this, $web, $topic ) = @_;
    return '#' . _makeAnchor( $web, $topic );
}

# Override Foswiki::Plugins::PublishPlugin::BackEnd::file
sub addTopic {
    my ( $this, $web, $topic, $text ) = @_;

    # Topics can be added inline to master with an anchor
    my $anchor = _makeAnchor( $web, $topic );
    my $fh = $this->{html_fh};
    if ( !$fh ) {
        my $fn = "$this->{root}/$this->{relative_path}/$this->{output}.html";
        if ( open( $fh, '>', $fn ) ) {
            binmode($fh);
            $this->{html_fh} = $fh;
        }
        else {
            $this->{logger}->logError("Cannot write $fn: $!");
        }
    }
    print $fh "<a name=\"$anchor\"'></a>";
    print $fh Encode::encode_utf8($text);
    return '#' . $anchor;
}

# Override Foswiki::Plugins::PublishPlugin::BackEnd::file
sub getAttachmentPath {
    my ( $this, $web, $topic, $attachment ) = @_;

    # Default is to store attachments in a .attachments dir next to
    # the topic. That won't work for flatfile, as the topics are all
    # in one file, so whack them into the resource dir instead.
    return "_files/" . join( '_', split( /\/+/, $web ), $topic, $attachment );
}

sub addResource {
    my ( $this, $data, $ext ) = @_;
    my $p = $this->SUPER::addResource( $data, $ext );
    return "$this->{output}$p";
}

# Override Foswiki::Plugins::PublishPlugin::BackEnd::file
sub close {
    my $this = shift;

    close( $this->{html_fh} ) if $this->{html_fh};
    return "$this->{relative_path}/$this->{output}.html";
}

1;

