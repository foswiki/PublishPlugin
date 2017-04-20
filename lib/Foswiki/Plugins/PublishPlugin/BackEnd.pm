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

For example, a backend could be implemented using a directory structure
to reflect the hierarchical web structure of the wiki. Topics might be stored
by writing HTML files to paths relative to the root of this
structure. Thus, the topic =System.Web<nop>Home= would be stored to
=/System/WebHome.html=.  Attachments to topics are stored in a special
'.attachments' subdirectory next to the =.html= file, so attachment
'System.Web<nop>Home:example.gif' will be stored to
=/System/WebHome.attachments/example.gif=.

The special top-level directory '_external' could be reserved for storing
external resources (those referenced from topics and downloaded)

Broken links may be generated if the target topic is not included in
the list of topics to publish.

=cut

package Foswiki::Plugins::PublishPlugin::BackEnd;

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

    $Foswiki::cfg{Plugins}{PublishPlugin}{Dir};
    $Foswiki::cfg{Plugins}{PublishPlugin}{URL};

    my $this = bless(
        {
            file_root => $Foswiki::cfg{Plugins}{PublishPlugin}{Dir},
            url_root  => $Foswiki::cfg{Plugins}{PublishPlugin}{URL},
            params    => $params || {},
            logger    => $logger
        },
        $class
    );
    return $this;
}

# Like join, but for dir and url paths
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
    return {};
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
    my $this = shift;
    return $this->{url_root};
}

1;
