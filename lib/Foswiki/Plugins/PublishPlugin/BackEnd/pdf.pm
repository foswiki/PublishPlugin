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
# PDF writer module for PublishPlugin
#

package Foswiki::Plugins::PublishPlugin::BackEnd::pdf;

use strict;
use Foswiki::Plugins::PublishPlugin::BackEnd::file;
our @ISA = ('Foswiki::Plugins::PublishPlugin::BackEnd::file');

use constant DESCRIPTION => 'PDF file with all content in it';

use File::Path;

sub new {
    my ( $class, $params, $logger ) = @_;

    die "{Plugins}{PublishPlugin}{PDFCmd} not defined"
      unless $Foswiki::cfg{Plugins}{PublishPlugin}{PDFCmd};

    $Foswiki::cfg{Plugins}{PublishPlugin}{PDFCmd} //=
      $Foswiki::cfg{PublishPlugin}{PDFCmd};

    $params->{dont_scan_existing} = 1;

    my $this = $class->SUPER::new( $params, $logger );

    $this->{tempdir} = File::Temp::tempdir( CLEANUP => 1 );

    $this->{pdf_path} = $this->{output_file};    # from superclass
    $this->{pdf_path} .= '.pdf' unless $this->{pdf_path} =~ /\.\w+$/;
    $this->{pdf_file} =
      $this->pathJoin( $Foswiki::cfg{Plugins}{PublishPlugin}{Dir},
        $this->{pdf_path} );
    $this->addPath( $this->{pdf_file}, 1 );

    return $this;
}

# Override Foswiki::Plugins::PublishPlugin::BackEnd::file
sub param_schema {
    my $class = shift;
    my $base  = $class->SUPER::param_schema();
    $base->{outfile}->{default} = 'pdf';
    delete $base->{googlefile};
    return $base;
}

# Override Foswiki::Plugins::PublishPlugin::BackEnd::file
sub addByteData {
    my ( $this, $path, $data ) = @_;
    my $file = join( '_', split( '/', $path ) );
    my $fn = "$this->{tempdir}/$file";
    my $fh;
    unless ( open( $fh, '>', $fn ) ) {
        $this->{logger}->logError("Failed to write $file:  $!");
        return;
    }
    print $fh $data;
    close($fh);
    $this->{html_files}->{$fn} = 1 if $path =~ /\.html/;
    return $path;
}

# Override Foswiki::Plugins::PublishPlugin::BackEnd::file
sub close {
    my $this = shift;

    $ENV{HTMLDOC_DEBUG} = 1;    # see man htmldoc - goes to apache err log
    $ENV{HTMLDOC_NOCGI} = 1;    # see man htmldoc

    my @files = keys %{ $this->{html_files} };

    my ( $data, $exit ) = Foswiki::Sandbox::sysCommand(
        undef,
        $Foswiki::cfg{Plugins}{PublishPlugin}{PDFCmd},
        FILE   => $this->{pdf_file},
        FILES  => \@files,
        EXTRAS => []
    );

    # htmldoc fails a lot, so log rather than dying
    $this->{logger}->logError("htmldoc failed: $exit/$data/$@") if $exit;

    return $this->{pdf_path};
}

1;
