# See bottom of file for license and copyright details
#
# Publish site (generate static HTML)
#
package Foswiki::Plugins::PublishPlugin;

use strict;
use warnings;

use Foswiki       ();
use Foswiki::Func ();
use Error qw( :try );
use Assert;

our $VERSION = '3.5';
our $RELEASE = '07 Dec 2021';
our $SHORTDESCRIPTION =
'Generate static output (HTML, PDF) optionally upload (FTP) the output to a publishing site.';

sub initPlugin {

    # Compatibility
    $Foswiki::cfg{Plugins}{PublishPlugin}{Dir} //=
      $Foswiki::cfg{PublishPlugin}{Dir};
    $Foswiki::cfg{Plugins}{PublishPlugin}{URL} //=
      $Foswiki::cfg{PublishPlugin}{URL};

    unless ( defined $Foswiki::cfg{Plugins}{PublishPlugin}{Dir} ) {
        die
"Can't publish because {Plugins}{PublishPlugin}{Dir} was not set. Please notify your Wiki administrator";
    }
    unless ( $Foswiki::cfg{Plugins}{PublishPlugin}{URL} ) {
        die
"Can't publish because {Plugins}{PublishPlugin}{URL} was not set. Please notify your Wiki administrator";
    }
    if (   !-d $Foswiki::cfg{Plugins}{PublishPlugin}{Dir}
        && !-e $Foswiki::cfg{Plugins}{PublishPlugin}{Dir} )
    {
        mkdir( $Foswiki::cfg{Plugins}{PublishPlugin}{Dir}, 0777 )
          || die "Cannot mkdir {PublishPlugin}{Dir}";
    }
    unless ( -d $Foswiki::cfg{Plugins}{PublishPlugin}{Dir}
        && -w $Foswiki::cfg{Plugins}{PublishPlugin}{Dir} )
    {
        die
"Can't publish because no useable {Plugins}{PublishPlugin}{Dir} was found. Please notify your Wiki administrator";
    }

    Foswiki::Func::registerRESTHandler(
        'publish', \&_publishRESTHandler,
        authenticate => 1,             # Block save unless authenticated
        validate     => 1,             # Check the strikeone / embedded CSRF key
        http_allow   => 'GET,POST',    # Restrict to POST for updates
    );
    Foswiki::Func::registerTagHandler( 'PUBLISHERS_CONTROL_CENTRE',
        \&_PUBLISHERS_CONTROL_CENTRE );
    Foswiki::Func::registerTagHandler( 'PUBLISHING_GENERATORS',
        \&_PUBLISHING_GENERATORS );

    return 1;
}

sub _publishRESTHandler {

    require Foswiki::Plugins::PublishPlugin::Publisher;
    die $@ if $@;

    my $query = Foswiki::Func::getCgiQuery();

    my $logger = sub {

        # Command-line logger
        my $level = shift;
        my $msg = join( '', @_ );

        # Strip HTML tags from command-line output
        $msg =~ s/<\/?[a-z]+[^>]*>/ /g;
        $msg =~ s/&nbsp;/ /g;
        eval {
            require HTML::Entities;

            # decode entities
            $msg = HTML::Entities::decode_entities($msg);
        };
        $msg = Encode::encode_utf8($msg);
        if ( $level eq 'error' ) {
            print STDERR "ERROR ", $msg, "\n";
        }
        else {
            if ( $level ne 'info' ) {
                print "$level: ";
            }
            print $msg, "\n";
        }
    };

    my $footer;
    my $body = '';
    if ( defined $Foswiki::Plugins::SESSION->{response}
        && !Foswiki::Func::getContext()->{command_line} )
    {
        # running from CGI
        # Generate the progress information screen (based on the view template)
        my $tmpl = Foswiki::Func::readTemplate('view');
        ( $body, $footer ) = split( /%TEXT%/, $tmpl );
        $body .= "<noautolink>\n";
        $logger = sub {
            my $level = shift;
            if ( $level eq 'error' ) {
                print STDERR "ERROR ", @_, "\n";
            }
            my $col = '';
            if ( $level eq 'warn' ) {
                $col = '%ORANGE%';
            }
            elsif ( $level eq 'error' ) {
                $col = '%RED%';
            }
            elsif ( $level eq 'debug' ) {
                $col = '%BLUE%';
            }
            my $endcol = $col ? '%ENDCOLOR%' : '';
            $body .= join( '', $col, @_, $endcol ) . " <br/>\n";
        };
    }

    my $publisher = new Foswiki::Plugins::PublishPlugin::Publisher(
        $Foswiki::Plugins::SESSION, $logger );

    $publisher->publish(
        sub {
            my $p = $query->param( $_[0] );
            return Foswiki::Sandbox::untaintUnchecked($p);
        }
    );
    $publisher->finish();

    $body .= $footer if $footer;

    $body = Foswiki::Func::expandCommonVariables($body);
    $body = Foswiki::Func::renderText($body);

    return $body;
}

# Allow manipulation of $Foswiki::cfg{Plugins}{PublishPlugin}{Dir}
sub _PUBLISHING_GENERATORS {
    my ( $session, $params, $topic, $web, $topicObject ) = @_;

    my $format = defined $params->{format} ? $params->{format} : '$item';
    my $separator = defined $params->{separator} ? $params->{separator} : '';

    # Get a list of available generators
    my @gennys;
    foreach my $place (@INC) {
        my $d;
        if ( opendir( $d, "$place/Foswiki/Plugins/PublishPlugin/BackEnd" ) ) {
            foreach my $gen ( sort readdir $d ) {
                next unless ( $gen =~ /^(\w+)\.pm$/ );
                if ( defined $params->{generator} ) {
                    next unless $1 eq $params->{generator};
                }
                push( @gennys, $1 );
            }
        }
    }

    my @list;
    foreach my $name ( sort @gennys ) {
        my $entry = $format;
        $entry =~ s/\$name/$name/g;
        my $class;
        if ( $entry =~ /\$(help|params)/ ) {
            $class = "Foswiki::Plugins::PublishPlugin::BackEnd::$name";
            eval "require $class";
            if ($@) {
                $entry =~ s/\$help/$@/ge;
            }
            else {
                $entry =~ s/\$help/$class->DESCRIPTION/ge;
                $entry =~ s/\$params=\((.*?)\)/$class->describeParams($1)/ge;
            }
        }
        push( @list, $entry );
    }

    return Foswiki::Func::decodeFormatTokens( join( $separator, @list ) );
}

# Allow manipulation of $Foswiki::cfg{Plugins}{PublishPlugin}{Dir}
sub _PUBLISHERS_CONTROL_CENTRE {
    my ( $session, $params, $topic, $web, $topicObject ) = @_;

    my $query = Foswiki::Func::getCgiQuery();

    # Check access to this interface!
    if ( defined &Foswiki::Func::isAnAdmin && !Foswiki::Func::isAnAdmin() ) {
        return CGI::span( { class => 'foswikiAlert' },
            "Only admins can access the control interface" );
    }

    # Old code doesn't have isAnAdmin so will allow access to
    # the control UI for everyone. Caveat emptor.

    my $output = CGI::p(<<HERE);
<h1>Publishers Control Interface</h1>
This interface lets you perform basic management operations
on published output files and directories. Click on the name of the
output file to visit it.
HERE
    $output .= $query->Dump() if DEBUG;
    my $action = $query->param('action') || '';
    $query->delete('action');    # delete so we can redefine them
    my $file = $query->param('file');
    $query->delete('file');

    if ( $action eq 'delete' ) {
        $file =~ m#([\w./\\]+)#;    # untaint
        if ( -e "$Foswiki::cfg{Plugins}{PublishPlugin}{Dir}/$1" ) {
            File::Path::rmtree("$Foswiki::cfg{Plugins}{PublishPlugin}{Dir}/$1");
            $output .= CGI::p("$1 deleted");
        }
        else {
            $output .= CGI::p("Cannot delete $1 - no such file");
        }
    }
    if ( opendir( D, $Foswiki::cfg{Plugins}{PublishPlugin}{Dir} ) ) {
        my @files = sort grep( !/^\./, readdir(D) );
        if ( scalar(@files) ) {
            $output .= CGI::start_table();
            foreach $file (@files) {
                my $link = "$Foswiki::cfg{Plugins}{PublishPlugin}{URL}/$file";
                $link = CGI::a( { href => $link }, $file );
                my @cols   = ( CGI::th($link) );
                my $delcol = CGI::start_form(
                    {
                        action =>
                          Foswiki::Func::getScriptUrl( $web, $topic, 'view' ),
                        method => 'POST',
                        name   => $file
                    }
                );
                $delcol .= CGI::submit(
                    {
                        type => 'button',
                        name => 'Delete'
                    }
                );
                $delcol .= "<input type='hidden' name='file' value='$file'/>";
                $delcol .=
                  "<input type='hidden' name='action' value='delete' />";
                $delcol .= "<input type='hidden' name='control' value='1' />";
                $delcol .= CGI::end_form();
                push( @cols, $delcol );
                $output .= CGI::Tr( { valign => "baseline" },
                    join( '', map { CGI::td($_) } @cols ) );
            }
            $output .= CGI::end_table();
        }
        else {
            $output .= "The output directory is currently empty";
        }
    }
    else {
        $output .=
          "Failed to open '$Foswiki::cfg{Plugins}{PublishPlugin}{Dir}': $!";
    }

    return $output;
}

1;
__END__
#
# Copyright (C) 2001 Motorola
# Copyright (C) 2001-2007 Sven Dowideit, svenud@ozemail.com.au
# Copyright (C) 2002, Eric Scouten
# Copyright (C) 2005-2011 Crawford Currie, http://c-dot.co.uk
# Copyright (C) 2006 Martin Cleaver, http://www.cleaver.org
# Copyright (C) 2006-2018, Foswiki Contributors
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
# Removal of this notice in this or derivatives is forbidden.
