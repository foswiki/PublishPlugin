#
# Copyright (C) 2009 Crawford Currie, http://c-dot.co.uk
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

=begin TML

Abstract base class of back-end modules for !PublishPlugin.

This class defines the interface that must be implemented by back end
archive generators.

All archives are interfaced to by adding topics, attachments, and
(optionally) external resources. The archive is responsible for
storing the data at a unique url that can be used in topics to
link to that resource.

=cut

package Foswiki::Plugins::PublishPlugin::BackEnd;

use strict;
use Assert;

=begin TML

---++ ClassMethod new(\%params, $logger)

Construct a new back end.
   * =$params= - optional parameter hash, may contain generator-specific
     options
   * =$logger= - ref to an object that supports logWarn, logInfo and logError
     methods (see Publisher.pm)
=cut

sub new {
    my ( $class, $params, $logger ) = @_;

    my $this = bless(
        {
            params => $params || {},
            logger => $logger
        },
        $class
    );
    return $this;
}

# Like join, but for dir and url paths, for subclasses
sub pathJoin {
    my $this = shift;
    my $all = join( '/', grep { length($_) } @_ );
    $all =~ s://+:/:g;                   # doubled slash
    $all =~ s:/+$::;                     # trailing /
    $all =~ s!^([a-zA-Z0-9]+:/)!$1/!;    # reslash abs urls
    return $all;
}

=begin TML

---++ ClassMethod param_schema -> \%schema
Get schema of query parameters, in the same format as Publisher.pm

=cut

sub param_schema {
    ASSERT( 0, "Pure virtual method requires implementation" );
}

=begin TML

---++ ClassMethod describeParams($template, $sep) -> $string
Expand the given template to generate a string description. Expanded
tokens are: $pname, $phelp, $pdefault

=cut

sub describeParams {
    my ( $this, $template, $sep ) = @_;
    my $ps   = $this->param_schema();
    my $desc = '';
    $sep //= '';
    my @entries;
    my $entry;
    foreach my $p ( sort keys %$ps ) {
        my $spec = $ps->{$p};
        next if $spec->{renamed};
        $entry = $template;
        $entry =~ s/\$pname/$p/g;
        $entry =~ s/\$phelp/$spec->{desc} || ''/ge;
        my $def = $spec->{default} // '';
        $entry =~ s/\$pdefault/$def/g;
        push( @entries, $entry );
    }
    return join( $sep, @entries );
}

=begin TML

---++ ObjectMethod alreadyPublished( $web, $topic, $date ) -> $bool

Test if the given topic, which has the given date in the store, has
already been published. A true return value will cause the topic to
be skipped in this publishing step.

=cut

sub alreadyPublished {
    return 0;
}

=begin TML

---++ ObjectMethod addTopic($web, $topic, $text) -> $path

Add the given topic to the archive and return the absolute path to
the topic in the archive.

Errors should be logged to the logger.

=cut

sub addTopic {
    ASSERT( 0, "Pure virtual method requires implementation" );
}

=begin TML

---++ ObjectMethod getTopicPath($web, $topic) -> $path

Return the absolute path to the topic in the archive - even if it
isn't there!

Errors should be logged to the logger.

=cut

sub getTopicPath {
    ASSERT( 0, "Pure virtual method requires implementation" );
}

=begin TML

---++ ObjectMethod addAttachment($web, $topic, $att, $data) -> $path

Add the given attachment to the archive, and return the absolute path
to the attachment in the archive.

Errors should be logged to the logger.

=cut

sub addAttachment {
    ASSERT( 0, "Pure virtual method requires implementation" );
}

=begin TML

---++ ObjectMethod addResource($data, $ext) -> $path

Add the given resource to the archive, and return the url path to
the resource in the archive.

$ext is an optional hint as to the mime type e.g. '.gif'

Errors should be logged to the logger.

=cut

sub addResource {
    ASSERT( 0, "Pure virtual method requires implementation" );
}

=begin TML

---++ ObjectMethod close() -> $url

Close the archive, and return the absolute URL to the completed archive.

Errors should be logged to the logger.

=cut

sub close {
}

1;
