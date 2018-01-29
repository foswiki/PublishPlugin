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

Errors, warning, and debug info should be logged to the logger.

=cut

package Foswiki::Plugins::PublishPlugin::BackEnd;

use strict;
use Assert;

=begin TML

---++ ClassMethod new(\%params, $logger)

Construct a new back end.
   * =$params= - optional parameter hash, may contain generator-specific
     options
   * =$logger= - ref to an object that supports logDebug, logWarn, logInfo
     and logError methods (see Publisher.pm)
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

=begin TML

---++ ObjectMethod getReady()

Generator has been constructed; perform any appropriate cleanup steps
before executing.

Default does nothing.

=cut

sub getReady {
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

---++ ObjectMethod getTopicPath($web, $topic) -> $path

Return the relative path to the topic in the archive - even if it
isn't there!

=cut

sub getTopicPath {
    ASSERT( 0, "Pure virtual method requires implementation" );
}

=begin TML

---++ ObjectMethod addTopic($web, $topic, $text) -> $path

Add the given topic to the archive and return the relative path to
the topic in the archive.

=cut

sub addTopic {
    ASSERT( 0, "Pure virtual method requires implementation" );
}

=begin TML

---++ ObjectMethod getAttachmentPath($web, $topic, $attachment) -> $path

Return the path to the attachment in the archive - even if it
isn't there!

=cut

sub getAttachmentPath {
    ASSERT( 0, "Pure virtual method requires implementation" );
}

=begin TML

---++ ObjectMethod addAttachment($web, $topic, $att, $data) -> $path

Add the given attachment to the archive, and return the relative path
to the attachment in the archive.

=cut

sub addAttachment {
    ASSERT( 0, "Pure virtual method requires implementation" );
}

=begin TML

---++ ObjectMethod addResource($data [, $ext]) -> $path

Add the given resource to the archive, and return the relative path to
the resource in the archive.

$ext is an optional hint as to the mime type e.g. '.gif'

=cut

sub addResource {
    ASSERT( 0, "Pure virtual method requires implementation" );
}

=begin TML

---++ ObjectMethod close() -> $path

Close the archive, and return the path to the completed archive
relative to {PublishPlugin}{Dir}

=cut

sub close {
}

1;
