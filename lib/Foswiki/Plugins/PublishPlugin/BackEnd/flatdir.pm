#
# Copyright (C) 2018 Crawford Currie, http://c-dot.co.uk
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
# File writer module for PublishPlugin. Generates a flat directory of HTML
# files, with a _rsrc subdirectory for external resources.
#
package Foswiki::Plugins::PublishPlugin::BackEnd::flatdir;

use strict;

use Foswiki::Plugins::PublishPlugin::BackEnd::file;
our @ISA = ('Foswiki::Plugins::PublishPlugin::BackEnd::file');

use constant DESCRIPTION =>
'Flat directory of HTML files. Attachments (and external resources if =copyexternal is selected=) will be saved to a top level =_rsrc= directory next to the HTML.';

# Override Foswiki::Plugins::PublishPlugin::BackEnd
sub getTopicPath {
    my ( $this, $web, $topic ) = @_;
    my @path = split( /\/+/, $web );
    return join( '_', @path, $topic . '.html' );
}

1;
