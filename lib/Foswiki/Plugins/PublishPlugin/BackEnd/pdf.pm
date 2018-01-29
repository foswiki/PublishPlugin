#
# Copyright (C) 2005-2018 Crawford Currie, http://c-dot.co.uk
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
use Foswiki::Plugins::PublishPlugin::BackEnd::flatfile;
our @ISA = ('Foswiki::Plugins::PublishPlugin::BackEnd::flatfile');

BEGIN {
    $Foswiki::cfg{Plugins}{PublishPlugin}{PDFCmd} //=
      $Foswiki::cfg{PublishPlugin}{PDFCmd};
}

use constant DESCRIPTION => 'PDF file with all content in it, generated using '
  . $Foswiki::cfg{Plugins}{PublishPlugin}{PDFCmd};

use File::Temp;

sub new {
    my ( $class, $params, $logger ) = @_;

    die "{Plugins}{PublishPlugin}{PDFCmd} not defined"
      unless $Foswiki::cfg{Plugins}{PublishPlugin}{PDFCmd};

    $params->{keep}               = 0;
    $params->{dont_scan_existing} = 0;

    my $this = $class->SUPER::new( $params, $logger );

    $this->{root}          = Foswiki::Func::getWorkArea('PublishPlugin');
    $this->{relative_path} = '';
    $this->{output}        = 'pdfdata';

    # file::getReady will purge the temp dir

    # Make the path to the ultimate output PDF file
    my @path = ();
    if ( $params->{relativedir} ) {
        push( @path, split( /\\+/, $params->{relativedir} ) );
    }
    push( @path, $params->{outfile} || 'pdf' );

    $this->{pdf_path} = join( '/', @path );
    $this->{pdf_path} .= '.pdf' unless $this->{pdf_path} =~ /\.\w+$/;

    return $this;
}

# Override Foswiki::Plugins::PublishPlugin::BackEnd::file
sub param_schema {
    my $class = shift;
    my $base  = $class->SUPER::param_schema();
    $base->{outfile}->{default} = 'pdf';
    delete $base->{googlefile};
    delete $base->{keep};
    return {
        %$base,
        extras => {
            default   => '',
            desc      => 'Extra parameters to pass to htmldoc',
            validator => sub {
                my ( $v, $k ) = @_;

                # Sandbox takes care of escaping dodgy stuff in command
                # lines.
                return $v;
              }
        },
        genopt => { renamed => 'extras' }
    };
}

sub validateCommandLineParams {
    my ( $v, $k ) = @_;

    # detect shell control chars
    die "Invalid '$v' in $k" if $v =~ /[`\$#|>&]/;
    return $v;
}

# Override Foswiki::Plugins::PublishPlugin::BackEnd::file
sub close {
    my $this = shift;

    $ENV{HTMLDOC_DEBUG} = 1;    # see man htmldoc - goes to apache err log
    $ENV{HTMLDOC_NOCGI} = 1;    # see man htmldoc

    my @extras = split( /\s+/, $this->{params}->{extras} || '' );

    my $pdf_file =
      "$Foswiki::cfg{Plugins}{PublishPlugin}{Dir}/$this->{pdf_path}";

    $this->addPath( $pdf_file, 1 );

    my ( $data, $exit ) = Foswiki::Sandbox::sysCommand(
        undef,
        $Foswiki::cfg{Plugins}{PublishPlugin}{PDFCmd},
        FILE   => $pdf_file,
        FILES  => ["$this->{root}/$this->{output}.html"],
        EXTRAS => \@extras
    );

    # htmldoc fails a lot, so log rather than dying
    $this->{logger}->logError(
        "$Foswiki::cfg{Plugins}{PublishPlugin}{PDFCmd} failed: $exit/$data/$@")
      if $exit;

    return $this->{pdf_path};
}

1;
