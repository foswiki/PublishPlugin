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

use constant DESCRIPTION =>
'PDF file with all content in it. Each topic will start on a new page in the PDF.';

use File::Path;

sub new {
    my ( $class, $params, $logger ) = @_;

    die "{Plugins}{PublishPlugin}{PDFCmd} not defined"
      unless $Foswiki::cfg{Plugins}{PublishPlugin}{PDFCmd};

    # We will generate using the 'file' generator first, then pack it
    my $save = {
        outfile => $params->{outfile} || 'pdf',
        relativedir => $params->{relativedir},
        relativeurl => $params->{relativeurl}
    };
    $params->{outfile} = "pdf_temp";
    undef $params->{relativedir};
    undef $params->{relativeurl};

    $Foswiki::cfg{Plugins}{PublishPlugin}{PDFCmd} //=
      $Foswiki::cfg{PublishPlugin}{PDFCmd};

    my $this = $class->SUPER::new( $params, $logger );
    $this->{save} = $save;
    return $this;
}

sub param_schema {
    my $class = shift;
    my $base  = $class->SUPER::param_schema();
    $base->{outfile}->{default} = 'pdf';
    return $base;
}

sub addRootFile {

    # None needed for pdf
}

sub close {
    my $this = shift;

    my @pdf_path = ();
    push( @pdf_path, $this->{save}->{relativedir} )
      if defined $this->{save}->{relativedir};
    push( @pdf_path, $this->{save}->{outfile} || 'pdf' );

    my $pdf_path = $this->pathJoin( grep { length($_) } @pdf_path );
    $pdf_path .= '.pdf' unless $pdf_path =~ /\.\w+$/;
    my $pdf_file =
      $this->pathJoin( $Foswiki::cfg{Plugins}{PublishPlugin}{Dir}, $pdf_path );

    $ENV{HTMLDOC_DEBUG} = 1;    # see man htmldoc - goes to apache err log
    $ENV{HTMLDOC_NOCGI} = 1;    # see man htmldoc

    my ( $data, $exit ) = Foswiki::Sandbox::sysCommand(
        undef,
        $Foswiki::cfg{Plugins}{PublishPlugin}{PDFCmd},
        FILE   => $pdf_file,
        FILES  => $this->{html_generated},
        EXTRAS => []
    );

    # htmldoc fails a lot, so log rather than dying
    $this->{logger}->logError("htmldoc failed: $exit/$data/$@") if $exit;

    # Get rid of the temporaries
    File::Path::rmtree( $this->{file_root} );

    return $this->pathJoin( $Foswiki::cfg{Plugins}{PublishPlugin}{URL},
        $pdf_path );
}

1;
