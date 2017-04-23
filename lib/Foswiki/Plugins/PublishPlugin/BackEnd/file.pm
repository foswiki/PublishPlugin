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
"Generates a directory tree on the server containing an HTML file for each topic, and copies of all published attachments. If you have selected =copyexternal=, then copied resources will be stored in a top level =_rsrc= directory.";

sub new {
    my ( $class, $params, $logger ) = @_;

    my $this = $class->SUPER::new( $params, $logger );

    $this->{output_file} = $params->{relativedir} || '';
    $this->{output_file} =
      $this->pathJoin( $this->{output_file}, $params->{outfile} )
      if $params->{outfile};

    $this->{file_root} =
      $this->pathJoin( $Foswiki::cfg{Plugins}{PublishPlugin}{Dir},
        $this->{output_file} );

    $this->{resource_id} = 0;

    $this->{last_published} = {};

    # Capture HTML generated for use by subclasses
    $this->{html_files} = [];

    if ( !$params->{keep} || $params->{keep} eq 'nothing' ) {

        # Don't keep anything
        File::Path::rmtree( $this->{file_root} );
    }
    elsif ( !$params->{dont_keep_existing} ) {

        # See what's worth keeping
        $this->_scanExistingHTML( $this->{file_root}, '' );
    }

    return $this;
}

# Find existing HTML in published dir structure to add to sitemap etc
sub _scanExistingHTML {
    my ( $this, $root, $relpath ) = @_;
    my $d;
    return unless ( opendir( $d, "$root/$relpath" ) );
    while ( my $f = readdir($d) ) {
        next if $f =~ /^\./;
        if ( -d "$root/$relpath/$f" ) {
            $this->_scanExistingHTML( $root, $relpath ? "$relpath/$f" : $f );
        }
        elsif ( $relpath && $f =~ /\.html$/ ) {
            my $p = "$relpath/$f";
            push( @{ $this->{html_files} }, Encode::decode_utf8($p) );
            $this->{last_published}->{$p} = ( stat("$root/$p") )[9];
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
        googlefile => {
            desc =>
'Google HTML verification file name (see https://sites.google.com/site/webmasterhelpforum/en/verification-specifics)',
            default   => '',
            validator => \&validateFilename
        },
        relativedir => {
            desc =>
'Additional path components to put above the top of the published output. See [[%SYSTEMWEB%.PublishPlugin#PublishToTopic][here]] for one way this can be used.',
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

# Implement Foswiki::Plugins::PublishPlugin::BackEnd
sub getTopicPath {
    my ( $this, $web, $topic ) = @_;
    my @path = split( /\/+/, $web );
    push( @path,, $topic . '.html' );
    return $this->pathJoin(@path);
}

# Implement  Foswiki::Plugins::PublishPlugin::BackEnd
sub alreadyPublished {
    my ( $this, $web, $topic ) = @_;
    return 0 unless ( $this->{params}->{keep} // '' ) eq 'unchanged';
    my $pd = $this->{last_published}->{"$web/$topic.html"};
    return 0 unless $pd;
    my ($cd) = Foswiki::Func::getRevisionInfo( $web, $topic );
    return 0 unless $cd;
    return $cd <= $pd;
}

# Implement  Foswiki::Plugins::PublishPlugin::BackEnd
sub addTopic {
    my ( $this, $web, $topic, $text ) = @_;

    my @path = grep { length($_) } split( /\/+/, $web );
    push( @path, $topic . '.html' );

    my $path = $this->pathJoin(@path);
    push( @{ $this->{html_files} }, $path );
    return $this->addByteData( $path, Encode::encode_utf8($text) );
}

# Implement Foswiki::Plugins::PublishPlugin::BackEnd
sub addAttachment {
    my ( $this, $web, $topic, $attachment, $data ) = @_;

    my @path = grep { length($_) } split( /\/+/, $web );
    push( @path, $topic . '.attachments' );
    push( @path, $attachment );

    my $path = $this->pathJoin(@path);
    return $this->addByteData( $path, $data );
}

# Implement Foswiki::Plugins::PublishPlugin::BackEnd
sub addResource {
    my ( $this, $data, $name ) = @_;
    my $prefix = '';
    my $ext    = '';
    if ( $ext =~ /(.*)(\.\w+)$/ ) {
        $prefix = $1 // '';
        $ext = $2;
    }
    $this->{resource_id}++;
    my $path = "_rsrc/$prefix$this->{resource_id}$ext";
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
# Both $file and $data must be byte data - long characters will
# break many engines.
sub addByteData {
    my ( $this, $file, $data ) = @_;
    my $fn = "$this->{file_root}/$file";
    $this->addPath( $fn, 1 );
    my $fh;
    unless ( open( $fh, ">", $fn ) ) {
        $this->{logger}->logError("Failed to write $fn:  $!");
        return;
    }
    print $fh $data;
    close($fh);
    $this->{logger}->logInfo( '', 'Published ' . $file );
    return $file;
}

# Implement Foswiki::Plugins::PublishPlugin::BackEnd
sub close {
    my $this = shift;

    # write sitemap.xml
    my $sitemap =
        '<?xml version="1.0" encoding="UTF-8"?>'
      . '<urlset xmlns="http://www.google.com/schemas/sitemap/0.84">'
      . join( "\n",
        map { '<url><loc>' . $_ . '</loc></url>'; } @{ $this->{html_files} } )
      . '</urlset>';
    $this->addByteData( 'sitemap.xml', Encode::encode_utf8($sitemap) );

    # Write Google verification files (comma separated list)
    if ( $this->{params}->{googlefile} ) {
        my @files = split( /\s*,\s*/, $this->{params}->{googlefile} );
        for my $file (@files) {
            my $simplehtml =
                '<html><title>'
              . $file
              . '</title><body>Google verification</body></html>';
            $this->addByteData( $file, Encode::encode_utf8($simplehtml) );
        }
    }

    # Write default.htm and index.html
    my $links = <<'HEAD';
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8" />
</head>
<body>
HEAD
    $links .=
      join( "</br>\n", map { "<a href='$_'>$_</a>" } @{ $this->{html_files} } );
    $links .= "\n</body>";
    $links = Encode::encode_utf8($links);
    $this->addByteData( 'default.htm', $links );
    $this->addByteData( 'index.html',  $links );

    return $this->{output_file};
}

1;

