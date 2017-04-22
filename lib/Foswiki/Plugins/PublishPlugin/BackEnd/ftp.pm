# Copyright (C) 2005-2017 Crawford Currie, http://c-dot.co.uk
# Copyright (C) 2006 Martin Cleaver, http://www.cleaver.org
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
# driver for writing html output to and ftp server, for hosting purposes
# adds sitemap.xml, google site verification file, and alias from
# index.html to WebHome.html (or other user specified default).
# I'd love to use LWP, but it tells me "400 Library does not
# allow method POST for 'ftp:' URLs"
# TODO: clean up ftp site, removing/archiving/backing up old version

package Foswiki::Plugins::PublishPlugin::BackEnd::ftp;

use strict;

use Foswiki::Plugins::PublishPlugin::BackEnd::file;
our @ISA = ('Foswiki::Plugins::PublishPlugin::BackEnd::file');

use constant DESCRIPTION =>
'Upload generated HTML and resources to an FTP site. The generated directory structure is the same as for the =file= generator';

use File::Temp qw(:seekable);
use File::Spec;

sub new {
    my ( $class, $params, $logger ) = @_;

    $params->{dont_scan_existing} = 1;
    my $this = $class->SUPER::new( $params, $logger );

    $this->{params}->{fastupload} ||= 0;
    if ( $this->{params}->{destinationftpserver} ) {
        if ( defined $this->{params}->{destinationftppath} ) {
            if ( $this->{params}->{destinationftppath} =~ /^\/?(.*)$/ ) {
                $this->{params}->{destinationftppath} = $1;
            }
        }
        else {
            $this->{params}->{destinationftppath} = '';
        }

        $this->{logger}->logInfo( '', "fastUpload = $this->{fastupload}" );
    }
    return $this;
}

sub param_schema {
    my $class = shift;
    my $base  = {
        destinationftpserver =>
          { desc => 'Server host name e.g. some.host.name' },
        destinationftppath =>
          { desc => 'Root path on the server to upload to' },
        destinationftpusername => { desc => 'FTP server username' },
        destinationftppassword => { desc => 'FTP server password' },
        fastupload             => {
            desc =>
'Speed up the ftp publishing by only uploading modified files. This will store a (tiny) checksum (.md5) file on the server alongside each uploaded file which will be used to optimise future uploads. Recommended.',
            default => 1
        },
        %{ $class->SUPER::param_schema() }
    };
    delete $base->{outfile};
    delete $base->{relativedir};
    delete $base->{keep};
    return $base;
}

sub addByteData {
    my ( $this, $file, $data ) = @_;
    $this->_upload( $data, $file );
    return $file;
}

sub _upload {
    my ( $this, $data, $to ) = @_;

    unless ( $this->{params}->{destinationftpserver} ) {
        $this->{logger}
          ->logInfo("Would upload to $to, but there's no FTP server specified");
        return;
    }

    my $localFilePath = "$Foswiki::cfg{TempfileDir}/pub$$";
    my $fh;
    unless ( open( $fh, '>', $localFilePath ) ) {
        $this->{logger}->logError( '', "Failed to upload $to: $!" );
        return;
    }
    print $fh $data;
    close($fh);

    my $attempts = 0;
    my $ftp;
    while ( $attempts < 2 ) {
        eval {
            $ftp = $this->_ftpConnect();
            if ( $to =~ /^\/?(.*\/)([^\/]*)$/ ) {
                $ftp->mkdir( $1, 1 )
                  or die "Cannot create directory ", $ftp->message;
            }

            if ( $this->{params}->{fastupload} ) {

                # Calculate checksum for local file
                my $fh;
                open( $fh, '<', $localFilePath )
                  or die
                  "Failed to open $localFilePath for checksum computation: $!";
                local $/;
                binmode($fh);
                my $data = <$fh>;
                close($fh);
                my $localCS = Digest::MD5::md5($data);

                # Get checksum for remote file
                my $remoteCS = '';
                my $tmpFile =
                  new File::Temp( DIR => File::Spec->tmpdir(), UNLINK => 1 );
                if ( $ftp->get( "$to.md5", $tmpFile ) ) {

                    # SEEK_SET to pos 0
                    $tmpFile->seek( 0, 0 );
                    $remoteCS = <$tmpFile>;
                }

                if ( $localCS eq $remoteCS ) {

                    # Unchanged
                    $this->{logger}->logInfo( '',
"skipped uploading $to to $this->{destinationftpserver} (no changes)"
                    );
                    $attempts = 2;
                    return;
                }
                else {
                    my $fh;
                    open( $fh, '>', "$localFilePath.md5" )
                      or die "Failed to open $localFilePath.md5 for write: $!";
                    binmode($fh);
                    print $fh $localCS;
                    close($fh);

                    $ftp->put( "$localFilePath.md5", "$to.md5" )
                      or die "put failed ", $ftp->message;
                }
            }

            $ftp->put( $localFilePath, $to )
              or die "put failed ", $ftp->message;
            $this->{logger}->logInfo( "FTPed",
                "$to to $this->{params}->{destinationftpserver}" );
            $attempts = 2;
        };

        if ($@) {

            # Got an error; try restarting the session a couple of times
            # before giving up
            $this->{logger}->logError( "FTP ERROR: " . $@ );
            if ( ++$attempts == 2 ) {
                $this->{logger}->logError("Giving up on $to");
                return;
            }
            $this->{logger}->logInfo( '', "...retrying in 30s)" );
            eval { $ftp->quit(); };
            $this->{ftp_interface} = undef;
            sleep(30);
        }
    }
}

sub _ftpConnect {
    my $this = shift;

    if ( !$this->{ftp_interface} ) {
        require Net::FTP;
        my $ftp = Net::FTP->new(
            $this->{params}->{destinationftpserver},
            Debug   => 1,
            Timeout => 30,
            Passive => 1
          )
          or die
          "Cannot connect to $this->{params}->{destinationftpserver}: $@";
        $ftp->login(
            $this->{params}->{destinationftpusername},
            $this->{params}->{destinationftppassword}
        ) or die "Cannot login ", $ftp->message;

        $ftp->binary();

        if ( $this->{params}->{destinationftppath} ne '' ) {
            $ftp->mkdir( $this->{params}->{destinationftppath}, 1 );
            $ftp->cwd( $this->{params}->{destinationftppath} )
              or die "Cannot change working directory ", $ftp->message;
        }
        $this->{ftp_interface} = $ftp;
    }
    return $this->{ftp_interface};
}

sub close {
    my $this = shift;

    # SUPER::close will generate index files and sitemap
    $this->SUPER::close();

    $this->{ftp_interface}->quit() if $this->{ftp_interface};
    $this->{ftp_interface} = undef;

    return $this->{params}->{destinationftpserver};
}

1;

