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
# File writer module for PublishPlugin. This is the reference
# implementation of BackEnd - it implements the directory structure
# described therein.
#
package Foswiki::Plugins::PublishPlugin::BackEnd::file;

use strict;

use Foswiki::Plugins::PublishPlugin::BackEnd;
our @ISA = ('Foswiki::Plugins::PublishPlugin::BackEnd');

use File::Copy ();
use File::Path ();

use constant DESCRIPTION =>
"A directory tree on the server containing a single HTML file for each topic and copies of all published attachments.";

sub new {
    my ( $class, $params, $logger ) = @_;

    my $this = $class->SUPER::new( $params, $logger );

    $this->{file_root} =
      $this->pathJoin( $this->{file_root}, $params->{relativedir} )
      if $params->{relativedir};
    $this->{file_root} =
      $this->pathJoin( $this->{file_root}, $params->{outfile} )
      if $params->{outfile};

    $this->{url_root} =
      $this->pathJoin( $this->{url_root}, $params->{relativeurl} )
      if $params->{relativeurl};
    $this->{url_root} = $this->pathJoin( $this->{url_root}, $params->{outfile} )
      if $params->{outfile};

    my $oldmask = umask(
        oct(777) - (
                 $Foswiki::cfg{RCS}{dirPermission}
              || $Foswiki::cfg{Store}{dirPermission}
        )
    );

    eval { File::Path::mkpath( $this->{file_root} ); };
    umask($oldmask);
    die $@ if $@;

    $this->{rsrc_path} = ( $params->{rsrcdir} || 'rsrc' );
    $this->{resource_id} = 0;

    # Capture HTML generated for use by subclasses
    $this->{html_generated} = [];

    return $this;
}

sub param_schema {
    my $class = shift;

    return {
        relativeurl => { default => '/' },
        outfile     => {
            default => 'file',
            validator =>
              \&Foswiki::Plugins::PublishPlugin::Publisher::validateFilename
        },
        googlefile => {
            default => '',
            validator =>
              \&Foswiki::Plugins::PublishPlugin::Publisher::validateFilenameList
        },
        defaultpage => { default => 'WebHome' },
        %{ $class->SUPER::param_schema }
    };
}

sub addDirectory {
    my ( $this, $name ) = @_;

    my $oldmask = umask(
        oct(777) - (
                 $Foswiki::cfg{RCS}{dirPermission}
              || $Foswiki::cfg{Store}{dirPermission}
        )
    );
    eval { File::Path::make_path("$this->{file_root}$name") };
    $this->{logger}->logError($@) if $@;
    umask($oldmask);
    push( @{ $this->{dirs} }, $name );
}

sub getTopicPath {
    my ( $this, $web, $topic ) = @_;
    my @path = split( /\/+/, $web );
    push( @path,, $topic . '.html' );
    return $this->pathJoin(@path);
}

sub addTopic {
    my ( $this, $web, $topic, $text ) = @_;

    my @path = grep { length($_) } split( /\/+/, $web );

    File::Path::mkpath( $this->pathJoin( $this->{file_root}, @path ) );
    push( @path, $topic . '.html' );

    my $file = $this->pathJoin( $this->{file_root}, @path );

    my $fh;

    if ( open( $fh, '>', $file ) ) {
        binmode($fh);
        print $fh $text;
        close($fh);
    }
    else {
        $this->{logger}->logError("Cannot write $file: $!");
    }

    push( @{ $this->{html_generated} }, $file );

    my $url = $this->pathJoin(@path);
    push( @{ $this->{urls} }, $url );

    $this->{logger}->logInfo($topic);

    return $url;
}

sub addAttachment {
    my ( $this, $web, $topic, $attachment, $data ) = @_;

    my @path = split( /\/+/, $web );
    push( @path, $topic . '.attachments' );

    File::Path::mkpath( $this->pathJoin( $this->{file_root}, @path ) );
    push( @path, $attachment );

    my $file = $this->pathJoin( $this->{file_root}, @path );
    my $fh;
    if ( open( $fh, '>', $file ) ) {
        print $fh $data;
        close($fh);
    }
    else {
        $this->{logger}->logError("Failed to write $file: $!");
    }
    return $this->pathJoin(@path);
}

sub addResource {
    my ( $this, $data, $ext ) = @_;
    $ext //= '';
    my $path = $this->{rsrc_path};
    File::Path::mkpath($path);

    while ( -e "$this->{file_root}/$path/rsrc$this->{resource_id}$ext" ) {
        $this->{resource_id}++;
    }
    $path = "$path/rsrc$this->{resource_id}$ext";

    my $fh;
    if ( open( $fh, '>', "$this->{file_root}/$path" ) ) {
        print $fh $data;
        close($fh);
    }
    else {
        $this->{logger}
          ->logError("Failed to write $this->{file_root}/$path: $!");
    }
    return $path;
}

# Abstracted for subclasses to override
sub addRootFile {
    my ( $this, $file, $data ) = @_;
    my $fh;
    unless ( open( $fh, ">", "$this->{file_root}/$file" ) ) {
        $this->{logger}->logError("Failed to write $file:  $!");
        return;
    }
    print $fh $data;
    close($fh);
    $this->{logger}->logInfo( '', 'Published ' . $file );
    return $file;
}

sub close {
    my $this = shift;

    # write sitemap.xml
    $this->addRootFile( 'sitemap.xml', $this->_createSitemap() );

    # write google verification files (comma separated list)
    if ( $this->{params}->{googlefile} ) {
        my @files = split( /[,\s]+/, $this->{params}->{googlefile} );
        for my $file (@files) {
            my $simplehtml =
                '<html><title>'
              . $file
              . '</title><body>just for google</body></html>';
            $this->addRootFile( $file, $simplehtml );
        }
    }

    # Write default.htm and index.html
    my $links =
      join( '</br>', map { "<a href='$_'>$_</a>" } @{ $this->{urls} } );
    $this->addRootFile( 'default.htm', $links );
    $this->addRootFile( 'index.html',  $links );
    return $this->{url_root};
}

sub _createSitemap {
    my $this = shift;
    return
        '<?xml version="1.0" encoding="UTF-8"?>'
      . '<urlset xmlns="http://www.google.com/schemas/sitemap/0.84">'
      . join( "\n",
        map { '<url><loc>' . $_ . '</loc></url>'; } @{ $this->{urls} } )
      . '</urlset>';
}

1;

