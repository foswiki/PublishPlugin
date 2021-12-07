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
# File writer module for PublishPlugin. Generates a file structure
# suitable for dropping in as a web wite, complete with optional
# index and google verification file
#
package Foswiki::Plugins::PublishPlugin::BackEnd::file;

use strict;

use Foswiki::Plugins::PublishPlugin::BackEnd;
require Exporter;
our @ISA       = qw(Foswiki::Plugins::PublishPlugin::BackEnd Exporter);
our @EXPORT_OK = qw(validateHost validatePath);

use File::Copy ();
use File::Path ();

use constant DESCRIPTION =>
"Generates a directory tree on the server containing an HTML file for each topic, and copies of all published attachments. If you have selected =copyexternal=, then copied resources will be stored in a =_rsrc= directory at the root of the generated output.";

sub new {
    my ( $class, $params, $logger ) = @_;

    my $this = $class->SUPER::new( $params, $logger );

    # Kept for compactness.
    $this->{root} = $Foswiki::cfg{Plugins}{PublishPlugin}{Dir};

    # Path below {root} to the output.
    my @path = ();
    if ( $params->{relativedir} ) {
        $this->{relative_path} = $params->{relativedir};
    }
    else {
        $this->{relative_path} = '';
    }
    $this->{output} = $params->{outfile} || 'file';
    $this->{output} .= '/';

    # Path under {root}{relative_path}{output} to save external resources to
    $this->{resource_path} = "_rsrc";

    #    $this->{logger}->logDebug(
    #        '',
    #        'Publishing to ',
    #        "$this->{root}/$this->{relative_path}/$this->{output}"
    #    );

    # Initialise the resource unique ID's
    $this->{resource_id} = 0;

    # List of web.topic paths to already-published topics.
    $this->{last_published} = {};

    # Capture HTML generated.
    $this->{html_files} = [];

    # Note that both html_files and last_published are indexed on the
    # final generated path for the HTML. This *may* look like the
    # web.topic path, but that cannot be assumed as getTopicPath may
    # have changed it significantly.
    return $this;
}

sub getReady {
    my $this = shift;

    if ( !$this->{params}->{keep} || $this->{params}->{keep} eq 'nothing' ) {

        # Don't keep anything
        File::Path::rmtree(
            "$this->{root}/$this->{relative_path}/$this->{output}");
    }
    elsif ( !$this->{params}->{dont_keep_existing} ) {

        # See what's worth keeping
        $this->_scanExistingHTML('');
    }
}

# Find existing HTML in published dir structure to add to sitemap and act
# as targets for links.
# $w - path relative to publishing root
sub _scanExistingHTML {
    my ( $this, $w ) = @_;
    my $d;
    my $root = "$this->{root}/$this->{relative_path}/$this->{output}/";
    return unless ( opendir( $d, "$root$w" ) );
    while ( my $f = readdir($d) ) {
        next if $f =~ /^\./;
        if ( -d "$root$w/$f" ) {
            $this->_scanExistingHTML( $w ? "$w/$f" : $f );
        }
        elsif ( $w && $f =~ /^\.html$/ ) {
            my $p = "$w/$f";    # path relative to $root
            push( @{ $this->{html_files} }, $p );
            $this->{last_published}->{$p} = ( stat("$root$p") )[9];
        }
    }
    closedir($d);
}

# Validate a filename (not ..)
sub validateFilename {
    my ( $v, $k ) = @_;

    return $v unless length($v);
    die "invalid filename for $k: $_"
      if $v eq '..' || $v =~ /[\/|\r\n\t\013*"?<:>]/;
    return $v;
}

sub validateHost {
    my ( $v, $k ) = @_;
    die "Invalid host '$v' in $k"
      unless $v =~
/^(((([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])\.){3}([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5]))|(([a-zA-Z0-9]|[a-zA-Z0-9][a-zA-Z0-9\-]*[a-zA-Z0-9])\.)*([A-Za-z0-9]|[A-Za-z0-9][A-Za-z0-9\-]*[A-Za-z0-9]))$/;
    return $v;
}

# Validate a path with no .. components
sub validatePath {
    my ( $v, $k ) = @_;
    die "$k cannot start with /" if $v =~ /^\//;
    map { validateFilename( $_, $k ) } split( /\/+/, $v );
    return $v;
}

# Validate that the parameter refers to an existing web/topic
sub validateWebTopic {
    my ( $v, $k ) = @_;
    return $v unless $v;
    my @wt = Foswiki::Func::normalizeWebTopicName( 'NOT_A_WEB', $v );
    die "$k ($v) is not an existing topic " . join( ';', @wt )
      unless Foswiki::Func::topicExists(@wt);
    return $v;
}

# Implement  Foswiki::Plugins::PublishPlugin::BackEnd
sub param_schema {
    my $class = shift;

    return {
        outfile => {
            desc =>
'Filename at the root of your generated output. If you leave this blank, the name of the format will be used',
            default   => 'file',
            validator => \&validateFilename
        },
        defaultpage => {
            desc =>
'Web.Topic to redirect to from index.html / default.html. If you leave this blank, the index will contain a simple list of all the published topics.',
            default   => '',
            validator => \&validateWebTopic
        },
        googlefile => {
            desc =>
              'Comma-separated list of Google HTML verification file names.',
            default   => '',
            validator => \&validateFilename
        },
        relativedir => {
            desc =>
'Additional path components to put between the {PublishPlugin}{Dir} and the top of the published output. See [[%SYSTEMWEB%.PublishPlugin#PublishToTopic][here]] for one way this can be used.',
            default   => '',
            validator => \&validatePath
        },
        keep => {
            default => 'nothing',
            desc =>
"Set to =unchanged= to publish only those topics that have changed in the store since they were last published. Set to =unselected= to republish all selected topics, but also keep previously published topics in the output area that were not selected for publishing this time. Set to =nothing= to clear down the output before each time it is published. Does not work with =versions=.",
            validator => sub {
                my ( $v, $k ) = @_;
                die "Invalid keep '$v' in $k"
                  if $v
                  && $v !~ /^(nothing|unselected|unchanged)$/;
                return $v;
              }
        },
        instance => { renamed => 'relativedir' }
    };
}

# Implement  Foswiki::Plugins::PublishPlugin::BackEnd
sub alreadyPublished {
    my ( $this, $web, $topic ) = @_;
    return 0 unless ( $this->{params}->{keep} // '' ) eq 'unchanged';
    my $pd = $this->{last_published}->{ $this->getTopicPath( $web, $topic ) };
    return 0 unless $pd;
    my ($cd) = Foswiki::Func::getRevisionInfo( $web, $topic );
    return 0 unless $cd;
    return $cd <= $pd;
}

# Implement Foswiki::Plugins::PublishPlugin::BackEnd
sub getTopicPath {
    my ( $this, $web, $topic ) = @_;

    my @path = split( /\/+/, $web );
    push( @path, $topic . '.html' );
    return join( '/', @path );
}

# Implement  Foswiki::Plugins::PublishPlugin::BackEnd
sub addTopic {
    my ( $this, $web, $topic, $text ) = @_;

    my $path = $this->getTopicPath( $web, $topic );
    push( @{ $this->{html_files} }, $path );
    return $this->addByteData( $path, Encode::encode_utf8($text) );
}

# Implement Foswiki::Plugins::PublishPlugin::BackEnd
sub getAttachmentPath {
    my ( $this, $web, $topic, $attachment ) = @_;

    my @path = split( /\/+/, $web );
    push( @path, $topic . '.attachments' );
    push( @path, $attachment );
    return join( '/', @path );
}

# Implement Foswiki::Plugins::PublishPlugin::BackEnd
sub addAttachment {
    my ( $this, $web, $topic, $attachment, $data ) = @_;

    my $path = $this->getAttachmentPath( $web, $topic, $attachment );
    return $this->addByteData( $path, $data );
}

# Implement Foswiki::Plugins::PublishPlugin::BackEnd
sub addResource {
    my ( $this, $data, $ext ) = @_;
    my $prefix = '';
    if ( $ext =~ /(.*)(\.\w+)$/ ) {
        $prefix = $1 // '';
        $ext = $2;
    }
    $this->{resource_id}++;
    my $path = "$this->{resource_path}/$prefix$this->{resource_id}$ext";
    return $this->addByteData( $path, $data );
}

# Add a path to a directory - abstracted to allow subclasses to override
sub addPath {
    my ( $this, $path, $is_file ) = @_;

    if ($is_file) {
        my @p = split( '/', $path );
        pop(@p);
        $path = join( '/', @p );
    }
    File::Path::mkpath($path);
}

# Abstracted for subclasses to override
# Add a file of byte data at a relative path in the archive.
#    * =$file= - path to file within the archive (no leading /)
#    * =$data= - byte data to store in the file - long characters will
#      break many engines.
sub addByteData {
    my ( $this, $file, $data ) = @_;
    my $fn =
"$Foswiki::cfg{Plugins}{PublishPlugin}{Dir}/$this->{relative_path}/$this->{output}$file";
    $this->addPath( $fn, 1 );
    my $fh;
    unless ( open( $fh, ">", $fn ) ) {
        $this->{logger}->logError("Failed to write $fn:  $!");
        return;
    }
    if ( defined $data ) {
        print $fh $data;
    }
    else {
        $this->{logger}->logError("$fn has no data, empty file created");
    }
    close($fh);
    return $file;
}

# Implement Foswiki::Plugins::PublishPlugin::BackEnd
sub close {
    my $this = shift;

    Foswiki::Func::loadTemplate('PublishPlugin');

    # write sitemap.xml at the root of the archive
    my $smurl  = Foswiki::Func::expandTemplate('PublishPlugin:sitemap_url');
    my $smurls = join( "\n",
        map { my $x = $smurl; $x =~ s/%URL%/$_/g; $x }
          @{ $this->{html_files} } );
    my $sitemap = Foswiki::Func::expandTemplate('PublishPlugin:sitemap');
    $sitemap =~ s/%URLS%/$smurls/g;

    $this->addByteData( 'sitemap.xml', Encode::encode_utf8($sitemap) );

    # Write Google verification files (comma separated list)
    if ( $this->{params}->{googlefile} ) {
        my @files = split( /\s*,\s*/, $this->{params}->{googlefile} );
        for my $file (@files) {
            my $simplehtml =
              Foswiki::Func::expandTemplate('PublishPlugin:googlefile');
            $simplehtml =~ s/%FILE%/$file/g;
            $this->addByteData( $file, Encode::encode_utf8($simplehtml) );
        }
    }

    # Write default.htm and index.html at the root of the archive
    my $html;
    if ( $this->{params}->{defaultpage} ) {
        $html = Foswiki::Func::expandTemplate('PublishPlugin:index_redirect');
        my $wt = $this->getTopicPath(
            Foswiki::Func::normalizeWebTopicName(
                undef, $this->{params}->{defaultpage}
            )
        );
        $html =~ s/%REDIR_URL%/$wt/g;
    }
    else {
        $html = Foswiki::Func::expandTemplate('PublishPlugin:index_list');
        my $link = Foswiki::Func::expandTemplate('PublishPlugin:index_link');
        my $bod  = join( '',
            map { my $x = $link; $x =~ s/%URL%/$_/g; $x }
              @{ $this->{html_files} } );
        $html =~ s/%LINK_LIST%/$bod/g;
    }

    $html = Foswiki::Func::expandCommonVariables($html);
    $html = Encode::encode_utf8($html);
    $this->addByteData( 'default.htm', $html );
    $this->addByteData( 'index.html',  $html );

    # Return path to the directory at the root relative to {PublishPlugin}{Dir}
    return "$this->{relative_path}/$this->{output}";
}

1;
