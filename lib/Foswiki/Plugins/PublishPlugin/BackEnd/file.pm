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
our @ISA = ('Foswiki::Plugins::PublishPlugin::BackEnd');

use File::Copy ();
use File::Path ();
use Foswiki::Plugins::PublishPlugin::Publisher
  qw(validateFilename validateRelPath);
use constant DESCRIPTION =>
"Generates a directory tree on the server containing an HTML file for each topic, and copies of all published attachments. If you have selected =copyexternal=, then copied resources will be stored in a top level =_rsrc= directory. %X% since April 2017 publishing is _incremental_ - it will not delete existing content. You need to do that yourself if you want to. Be careful that moved topics and attachments may end up remaining in published content if you don't.";

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

    # Capture HTML generated for use by subclasses
    $this->{html_files} = [];

    if ( $params->{keep} ) {
        $this->_scanExistingHTML( $this->{file_root}, '' );
    }
    else {
        File::Path::rmtree( $this->{file_root} );
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
        if ( -d "$root$relpath/$f" ) {
            $this->_scanExistingHTML( $root, $relpath ? "$relpath/$f" : $f );
        }
        elsif ( $relpath && $f =~ /\.html$/ ) {
            push( @{ $this->{html_files} },
                Encode::decode_utf8("$relpath/$f") );
        }
    }
    closedir($d);
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
            validator => \&validateRelPath,
        },
        keep => {
            default => 0,
            desc =>
"Enable to keep previously published topics. The default is to clear down the output each time it is published."
        }
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

