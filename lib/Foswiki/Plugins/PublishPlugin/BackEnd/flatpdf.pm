#
# Copyright (C) 2005 Crawford Currie, http://c-dot.co.uk
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

package Foswiki::Plugins::PublishPlugin::BackEnd::flatpdf;

use strict;
use Foswiki::Plugins::PublishPlugin::BackEnd::flatfile;
our @ISA = ('Foswiki::Plugins::PublishPlugin::BackEnd::flatfile');

use constant DESCRIPTION =>
'PDF file with all topics and attachments inside it. Topics will follow one another with no intervening page breaks.';

use File::Path;

sub new {
    my $class = shift;
    my ($params) = @_;
    $params->{outfile} ||= "flatpdf";
    my $this = $class->SUPER::new(@_);
    return $this;
}

sub param_schema {
    my $class = shift;
    return {
        outfile => {
            default => 'flatpdf',
            validator =>
              \&Foswiki::Plugins::PublishPlugin::Publisher::validateFilename
        },
        %{ $class->SUPER::param_schema() }
    };
}

sub close {
    my $this = shift;
    my $dir  = $this->{path};
    eval { File::Path::mkpath($dir) };
    die $@ if ($@);

    my $tmpdir = "$dir$this->{params}->{outfile}";
    my @files  = ("$tmpdir/master.html");

    my $cmd = $Foswiki::cfg{PublishPlugin}{PDFCmd};
    die "{PublishPlugin}{PDFCmd} not defined" unless $cmd;

    my $landed = "$this->{params}->{outfile}.pdf";
    my @extras = split( /\s+/, $this->{extras} || '' );

    $ENV{HTMLDOC_DEBUG} = 1;    # see man htmldoc - goes to apache err log
    $ENV{HTMLDOC_NOCGI} = 1;    # see man htmldoc

    $this->{path} .= '/' unless $this->{path} =~ m#/$#;
    my ( $data, $exit ) = Foswiki::Sandbox::sysCommand(
        $Foswiki::sharedSandbox,
        $cmd,
        FILE   => "$this->{path}$landed",
        FILES  => \@files,
        EXTRAS => \@extras
    );

    # htmldoc failsa lot, so log rather than dying
    $this->{logger}->logError("htmldoc failed: $exit/$data/$@") if $exit;

    # Get rid of the temporaries
    File::Path::rmtree($tmpdir);

    return $landed;
}

1;
