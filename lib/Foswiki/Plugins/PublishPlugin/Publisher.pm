# See bottom of file for license and copyright details
package Foswiki::Plugins::PublishPlugin::Publisher;

use strict;

use Foswiki;
use Foswiki::Func;
use Error ':try';
use Assert;
use Foswiki::Plugins::PublishPlugin::PageAssembler;
use URI ();

# Parameters, passed to new()
my %PARAM_SCHEMA = (
    allattachments => { desc => 'Publish All Attachments' },
    copyexternal   => {
        default => 1,
        desc    => 'Copy Off-Wiki Resources'
    },
    enableplugins => {

        # Keep this list in sync with System.PublishPlugin
        default =>
'-CommentPlugin,-EditRowPlugin,-EditTablePlugin,-NatEditPlugin,-SubscribePlugin,-TinyMCEPlugin,-UpdatesPlugin',
        validator => \&_validateList,
        desc      => 'Enable Plugins'
    },
    exclusions => { desc => 'Topic Exclude Filter' },
    format     => {
        default   => 'file',
        validator => \&_validateWord,
        desc      => 'Output Generator'
    },
    history => {
        default   => '',
        validator => \&_validateTopicNameOrNull,
        desc      => 'History Topic'
    },
    inclusions  => { desc => 'Topic Include Filter' },
    preferences => {
        default => '',
        desc    => 'Extra Preferences'
    },
    publishskin => {
        validator => \&_validateList,
        desc      => 'Publish Skin'
    },
    relativedir => {
        default   => '/',
        validator => \&_validateRelPath,
        desc      => 'Relative Path'
    },
    rsrcdir => {
        default   => 'rsrc',
        validator => sub {
            my ( $v, $k ) = @_;
            $v = _validateRelPath( $v, $k );
            die "Invalid $k: '$v'" if $v =~ /^\./;
            return $v;
          }
    },
    template => {
        default => 'view',
        desc    => 'Template to use for publishing'
    },
    topics => {
        default        => '',
        allowed_macros => 1,
        validator      => \&_validateTopicNameList,
        desc           => 'Topics'
    },
    rexclude => {
        default   => '',
        validator => \&_validateRE,
        desc      => 'Content Filter'
    },
    versions => {
        validator => \&_validateList,
        desc      => 'Versions Topic'
    },
    webs => { validator => \&_validateWebName },

    # Renamed options
    filter      => { renamed => 'rexclude' },
    instance    => { renamed => 'relativedir' },
    genopt      => { renamed => 'extras' },
    topicsearch => { renamed => 'rexclude' },
    skin        => { renamed => 'publishskin' },
    topiclist   => { renamed => 'topics' },
    web         => { renamed => 'webs' }
);

sub _validateRE {
    my $v = shift;

    # SMELL: do a much better job of this!
    $v =~ /^(.*)$/;
    return $1;
}

# Parameter validators
sub _validateDir {
    my $v = shift;
    if ( -d $v ) {
        $v =~ /(.*)/;
        return $1;
    }
    my $k = shift;
    die "Invalid $k: '$v'";
}

sub _validateList {
    my $v = shift;
    if ( $v =~ /^([\w,. ]*)$/ ) {
        return $1;
    }
    my $k = shift;
    die "Invalid $k: '$v'";
}

sub _validateTopicNameList {
    my ( $v, $k ) = @_;
    my @ts;
    foreach my $t ( split( /\s*,\s*/, $v ) ) {
        push( @ts, _validateTopicName( $t, $k ) );
    }
    return join( ',', @ts );
}

sub _validateTopicNameOrNull {
    return _validateTopicName( $_[0] ) if $_[0];
    return $_[0];
}

sub _validateTopicName {
    my $v = shift;
    unless ( defined &Foswiki::Func::isValidTopicName ) {

        # Old code doesn't have this. Caveat emptor.
        return Foswiki::Sandbox::untaintUnchecked($v);
    }
    if ( Foswiki::Func::isValidTopicName( $v, 1 ) ) {
        return Foswiki::Sandbox::untaintUnchecked($v);
    }
    my $k = shift;
    die "Invalid $k: '$v'";
}

sub _validateWebName {
    my $v = shift;
    return '' unless defined $v && $v ne '';
    die "Invalid web name '$v'"
      unless $Foswiki::Plugins::SESSION->webExists($v);
    return Foswiki::Sandbox::untaintUnchecked($v);
}

sub _validateWord {
    my $v = shift;
    if ( $v =~ /^(\w+)$/ ) {
        return $1;
    }
    my $k = shift;
    die "Invalid $k: '$v'";
}

sub validateFilenameList {
    my ( $v, $k ) = @_;
    my @ts;
    foreach my $t ( split( /\s*,\s*/, $v ) ) {
        push( @ts, _validateFilename( $t, $k ) );
    }
    return join( ',', @ts );
}

sub validateFilename {
    my $v = shift;
    if ( $v =~ /^([\w ]*)$/ ) {
        return $1;
    }
    my $k = shift;
    die "Invalid $k: '$v'";
}

sub _validateRelPath {
    my $v = shift;
    return '' unless $v;
    $v .= '/';
    $v =~ s#//+#/#;
    $v =~ s#^/##;
    if ( $v =~ m#^(.*)$# ) {
        my $d = $1;
        return $d;
    }
    my $k = shift;
    die "Invalid $k: '$v'";
}

# Create a parameter hash from a hash of key=>value, applying validators
# and defaults to each parameter as appropriate
sub _loadParams {
    my ( $this, $data ) = @_;

    if ( ref($data) eq 'HASH' ) {
        my $d = $data;
        $data = sub { return $d->{ $_[0] }; };
    }

    if ( &$data('configtopic') ) {
        my ( $cw, $ct ) =
          Foswiki::Func::normalizeWebTopicName( $Foswiki::cfg{UsersWebName},
            $data->{config_topic} );
        my $d = _loadConfigTopic( $cw, $ct );
        $data = sub { return $d->{ $_[0] }; };
    }

    # Try and build the generator first, so we can pull in param defs
    my $format = &$data('format') || 'file';
    unless ( $format =~ /^(\w+)$/ ) {
        die "Bad output format '$format'";
    }

    # Implicit untaint
    $this->{generator} = 'Foswiki::Plugins::PublishPlugin::BackEnd::' . $1;
    eval 'use ' . $this->{generator};

    if ($@) {
        die "Failed to initialise '$this->{generator}': $@";
    }

    my $gen_schema = $this->{generator}->param_schema();

    my %schema;
    map { $schema{$_} = $PARAM_SCHEMA{$_} } keys %PARAM_SCHEMA;
    map { $schema{$_} = $gen_schema->{$_} } keys %$gen_schema;

    $this->{schema} = \%schema;
    my %opt;

    while ( my ( $k, $spec ) = each %schema ) {
        if ( defined( &$data($k) ) ) {
            my $v = &$data($k);

            while ( defined $spec->{renamed} ) {
                $k    = $spec->{renamed};
                $spec = $schema{$k};
            }
            if ( defined $spec->{allowed_macros} ) {
                $v = Foswiki::Func::expandCommonVariables($v);
            }
            if ( $spec->{default} && $v eq $spec->{default} ) {
                $opt{$k} = $spec->{default};
            }
            elsif ( defined $spec->{validator} ) {
                $opt{$k} = &{ $spec->{validator} }( $v, $k );
            }
            else {
                $opt{$k} = $v;
            }
        }
        else {
            $opt{$k} = $spec->{default};
        }
    }
    $this->{opt} = \%opt;
}

# Pull in a key=>value parameter hash from a topic
sub _loadConfigTopic {
    my ( $cw, $ct ) = @_;

    # Parameters are defined in config topic
    unless ( Foswiki::Func::topicExists( $cw, $ct ) ) {
        die "Specified configuration topic $cw.$ct does not exist!";
    }

    # Untaint verified web and topic names
    $cw = Foswiki::Sandbox::untaintUnchecked($cw);
    $ct = Foswiki::Sandbox::untaintUnchecked($ct);
    my ( $cfgm, $cfgt ) = Foswiki::Func::readTopic( $cw, $ct );
    unless (
        Foswiki::Func::checkAccessPermission(
            "VIEW", Foswiki::Func::getWikiName(),
            $cfgt, $ct, $cw
        )
      )
    {
        die "Access to $cw.$ct denied";
    }

    $cfgt = Foswiki::Func::expandCommonVariables( $cfgt, $ct, $cw, $cfgm );

    # SMELL: common preferences parser?
    my %data;
    foreach my $line ( split( /\r?\n/, $cfgt ) ) {
        next
          unless $line =~
          /^\s+\*\s+Set\s+(?:PUBLISH_)?([A-Z]+)\s*=\s*(.*?)\s*$/;

        my $k = lc($1);
        my $v = $2;

        $data{$k} = $v;
    }
    return \%data;
}

# Constructor
sub new {
    my ( $class, $params, $session ) = @_;

    my $this = bless(
        {
            session => $session,

            # serial number for giving unique names to external resources
            nextExternalResourceNumber => 0,
        },
        $class
    );

    $this->_loadParams($params);

    $this->{opt}->{publishskin} ||=
      Foswiki::Func::getPreferencesValue('PUBLISHSKIN')
      || 'basic_publish';

    if ( $this->{opt}->{history} ) {
        my ( $hw, $ht ) =
          Foswiki::Func::normalizeWebTopicName( undef,
            $this->{opt}->{history} );
        unless (
            Foswiki::Func::checkAccessPermission(
                'CHANGE', Foswiki::Func::getWikiName(),
                undef, $ht, $hw
            )
          )
        {
            $this->logError( <<TEXT );
Cannot publish because current user cannot CHANGE $hw.$ht.
This topic must be editable by the user doing the publishing.
TEXT
            return;
        }
        $this->{history} = [ $hw, $ht ];
    }
    return $this;
}

# Shutdown
sub finish {
    my $this = shift;
    $this->{session} = undef;
}

# Convert wildcarded comma-separated list to a regex
sub _wildcards2RE {
    my $v = shift;
    $v =~ s/([*?])/.$1/g;
    $v =~ s/\s*,\s*/|/g;
    return "^($v)\$";
}

sub publish {
    my ($this) = @_;

    # don't add extra markup for topics we're not linking too
    # NEWTOPICLINKSYMBOL LINKTOOLTIPINFO
    $Foswiki::Plugins::SESSION->renderer()->{NEWLINKSYMBOL} = '';

    $this->{historyText} = '';

    # Handle =enableplugins=. We simply muddy-boots the foswiki config.
    if ( $this->{opts}->{enableplugins} ) {

        # Make a map of plugins known to =configure=
        my %state = map { $_ => $Foswiki::cfg{Plugins}{$_}{Enabled} }
          grep { ref( $Foswiki::cfg{Plugins}{$_} ) }
          keys( %{ $Foswiki::cfg{Plugins} } );

        my %actions;
        my @actions = split( /\s*,\s*/, $this->{opt}->{enableplugins} );
        if ( $actions[0] eq '-*' ) {

            # Disable all
            shift @actions;
            while ( my ( $k, $v ) = each %state ) {
                $state{$k} = 0;
            }
        }
        foreach my $action (@actions) {
            if ( $action =~ s/^-// ) {
                $state{$action} = 0;
            }
            else {
                $state{$action} = 1;
            }
        }
        while ( my ( $plugin, $enable ) = each %state ) {
            $Foswiki::cfg{Plugins}{$plugin}{Enabled} = $enable;
        }
    }

    # Generate the progress information screen (based on the view template)
    my ( $header, $footer ) = ( '', '' );
    unless ( Foswiki::Func::getContext()->{command_line} ) {

        # running from CGI
        if ( defined $Foswiki::Plugins::SESSION->{response} ) {
            $Foswiki::Plugins::SESSION->generateHTTPHeaders();
            $Foswiki::Plugins::SESSION->{response}
              ->print( CGI::start_html( -title => 'Foswiki: Publish' ) );
        }
        ( $header, $footer ) =
          $this->_getPageTemplate( $Foswiki::cfg{SystemWebName} );
    }

    $this->logInfo( '',          "<h1>Publishing Details</h1>" );
    $this->logInfo( "Publisher", Foswiki::Func::getWikiName() );
    $this->logInfo( "Date",      Foswiki::Func::formatTime( time() ) );
    foreach my $p ( sort keys %{ $this->{schema} } ) {
        next if $this->{schema}->{$p}->{renamed};
        if ( $this->{$p} ) {
            $this->logInfo( $this->{schema}->{$p}->{desc} // $p, $this->{$p} );
        }
    }

    # Push preference values. Because we use session preferences (preferences
    # that only live as long as the request) these values will not persist.
    if ( defined $this->{opt}->{preferences} ) {
        my $sep =
          Foswiki::Func::getContext()->{command_line} ? qr/;/ : qr/\r?\n/;
        foreach my $setting ( split( $sep, $this->{opt}->{preferences} ) ) {
            if ( $setting =~ /^(\w+)\s*=(.*)$/ ) {
                my ( $k, $v ) = ( $1, $2 );
                Foswiki::Func::setPreferencesValue( $k, $v );
            }
        }
    }

    # Force static context for all published topics
    Foswiki::Func::getContext()->{static} = 1;

    # Start by making a master list of all published topics. We do this
    # so we can detect whether a topic is in the publish set when
    # remapping links. Note that we use /, not ., in the path. This is
    # to make matching URL paths easier.
    my @wl;
    if ( $this->{opt}->{webs} ) {
        @wl = split( /\s*,\s*/, $this->{opt}->{webs} );

        # Get subwebs
        @wl = map { $_, Foswiki::Func::getListOfWebs( undef, $_ ) } @wl
          unless $this->{opt}->{nosubwebs};

    }
    else {
        # get a list of ALL webs
        @wl = Foswiki::Func::getListOfWebs();

        # Filter subwebs
        @wl = grep { !m:/: } @wl if $this->{opt}->{nosubwebs};
    }

    # uniq
    my %wl       = map { $_ => 1 } @wl;
    my @webs     = sort keys %wl;
    my $firstWeb = $webs[0];

    my %topics = ();
    foreach my $web (@webs) {
        if ( $this->{opt}->{topics} ) {
            foreach my $topic ( split( /\s*,\s*/, $this->{opt}->{topics} ) ) {
                my ( $w, $t ) =
                  Foswiki::Func::normalizeWebTopicName( $web, $topic );
                $topics{"$w.$t"} = 1;
            }
        }
        else {
            foreach my $topic ( Foswiki::Func::getTopicList($web) ) {
                $topics{"$web.$topic"} = 1;
            }
        }
    }
    my @topics = sort keys %topics;

    if ( $this->{opt}->{inclusions} ) {
        my $re = _wildcards2RE( $this->{opt}->{inclusions} );
        @topics = grep { /$re$/ } @topics;
    }

    if ( $this->{opt}->{exclusions} ) {
        my $re = _wildcards2RE( $this->{opt}->{exclusions} );
        @topics = grep { !/$re$/ } @topics;
    }

    # Determine the set of topics for each unique web
    my %webset;
    foreach my $t (@topics) {
        my ( $w, $t ) = Foswiki::Func::normalizeWebTopicName( undef, $t );
        $webset{$w} //= [];
        push( @{ $webset{$w} }, $t );
    }

    $this->{archive} = $this->{generator}->new( $this->{opt}, $this );

    while ( my ( $w, $ts ) = each %webset ) {
        $this->_publishInWeb( $w, $ts );
    }

    # Close archive
    my $url = $this->{archive}->close();
    $this->logInfo( "Published to", "<a href='$url'>$url</a>" );

    if ( $this->{history} ) {

        my ( $meta, $text ) = Foswiki::Func::readTopic( $this->{history}->[0],
            $this->{history}->[1] );
        my $history =
          Foswiki::Func::loadTemplate( 'publish_history',
            $this->{opt}->{publishskin} );

        # See if we have history template. Unfortunately for compatibility
        # reasons, Func::readTemplate doesn't distinguish between no template
        # and an empty template :-(
        if ($history) {

            # Expand macros *before* we include the history text so we pick up
            # session preferences.
            Foswiki::Func::setPreferencesValue( 'PUBLISHING_HISTORY',
                $this->{historyText} );
            $history = Foswiki::Func::expandCommonVariables($history);
        }
        elsif (
            Foswiki::Func::topicExists(
                $this->{history}->[0],
                $this->{history}->[1]
            )
          )
        {

            # No template, use the last publish run (legacy)
            $text ||= '';
            $text =~ s/(^|\n)---\+ Last Published\n.*$//s;
            $history =
"$text---+ Last Published\n<noautolink>\n$this->{historyText}\n</noautolink>";
        }
        else {

            # No last run, make something up
            $history =
"---+ Last Published\n<noautolink>\n$this->{historyText}\n</noautolink>";
        }
        Foswiki::Func::saveTopic(
            $this->{history}->[0],
            $this->{history}->[1],
            $meta, $history, { minor => 1, forcenewrevision => 1 }
        );
        my $url = Foswiki::Func::getScriptUrl( $this->{history}->[0],
            $this->{history}->[1], 'view' );
        $this->logInfo( "History saved in", "<a href='$url'>$url</a>" );
    }

    Foswiki::Plugins::PublishPlugin::_display($footer);
}

# $web - the web to publish in
# \@topics - list of topics in this web to publish
sub _publishInWeb {
    my ( $this, $web, $topics ) = @_;

    $this->logInfo( '', "<h2>Publishing in web '$web'</h2>" );
    $this->{topicVersions} = {};

    if ( $this->{opt}->{versions} ) {
        my ( $vweb, $vtopic ) =
          Foswiki::Func::normalizeWebTopicName( $web,
            $this->{opt}->{versions} );
        die "Versions topic $vweb.$vtopic does not exist"
          unless Foswiki::Func::topicExists( $vweb, $vtopic );
        my ( $meta, $text ) = Foswiki::Func::readTopic( $vweb, $vtopic );
        $text =
          Foswiki::Func::expandCommonVariables( $text, $vtopic, $vweb, $meta );
        my $pending;
        my $count = 0;
        foreach my $line ( split( /\r?\n/, $text ) ) {

            if ( defined $pending ) {
                $line =~ s/^\s*//;
                $line = $pending . $line;
                undef $pending;
            }
            if ( $line =~ s/\\$// ) {
                $pending = $line;
                next;
            }
            if ( $line =~ /^\s*\|\s*(.*?)\s*\|\s*(?:\d\.)?(\d+)\s*\|\s*$/ ) {
                my ( $t, $v ) = ( $1, $2 );
                ( $vweb, $vtopic ) =
                  Foswiki::Func::normalizeWebTopicName( $web, $t );
                $this->{topicVersions}->{"$vweb.$vtopic"} = $v;
                $count++;
            }
        }
        die "Versions topic $vweb.$vtopic contains no topic versions"
          unless $count;
    }

    # Choose template. Note that $template_TEMPLATE can still override
    # this in specific topics.
    my $tmpl = Foswiki::Func::readTemplate( $this->{opt}->{template},
        $this->{opt}->{publishskin} );
    die "Couldn't find skin template $this->{opt}->{template}\n" if ( !$tmpl );

    # Keep a record of resources we copy, so we don't try to do them twice
    $this->{copied_resources} = {};

    # Attempt to render each included page.
    foreach my $topic (@$topics) {
        try {
            $this->_publishTopic( $web, $topic, $tmpl );
        }
        catch Error::Simple with {
            my $e = shift;
            $this->logError(
                "$web.$topic not published: " . ( $e->{-text} || '' ) );
        };
    }
}

# get a template for presenting output / interacting (*not* used
# for published content)
sub _getPageTemplate {
    my ($this) = @_;

    my $query = Foswiki::Func::getCgiQuery();
    my $web   = $Foswiki::cfg{SystemWebName};
    my $topic = 'PublishPlugin';
    my $tmpl  = Foswiki::Func::readTemplate('view');

    $tmpl =~ s/%META\{.*?\}%//g;
    for my $tag (qw( REVTITLE REVARG REVISIONS MAXREV CURRREV )) {
        $tmpl =~ s/%$tag%//g;
    }
    my ( $header, $footer ) = split( /%TEXT%/, $tmpl );
    $header = Foswiki::Func::expandCommonVariables( $header, $topic, $web );
    $header = Foswiki::Func::renderText( $header, $web );
    $header =~ s/<nop>//go;
    Foswiki::Func::writeHeader();
    Foswiki::Plugins::PublishPlugin::_display $header;

    $footer = Foswiki::Func::expandCommonVariables( $footer, $topic, $web );
    $footer = Foswiki::Func::renderText( $footer, $web );
    return ( $header, $footer );
}

# from http://perl.active-venture.com/pod/perlfaq4-dataarrays.html
sub arrayDiff {
    my ( $array1, $array2 ) = @_;
    my ( @union, @intersection, @difference );
    @union = @intersection = @difference = ();
    my %count = ();
    foreach my $element ( @$array1, @$array2 ) { $count{$element}++ }
    foreach my $element ( keys %count ) {
        push @union, $element;
        push @{ $count{$element} > 1 ? \@intersection : \@difference },
          $element;
    }
    return @difference;
}

sub logInfo {
    my ( $this, $header, $body ) = @_;
    $body ||= '';
    if ( defined $header and $header ne '' ) {
        $header = CGI::b("$header:&nbsp;");
    }
    else {
        $header = '';
    }
    Foswiki::Plugins::PublishPlugin::_display( $header, $body, CGI::br() );
    $this->{historyText} .= "$header$body%BR%\n";
}

sub logWarn {
    my ( $this, $message ) = @_;
    Foswiki::Plugins::PublishPlugin::_display(
        CGI::span( { class => 'foswikiAlert' }, $message ) );
    Foswiki::Plugins::PublishPlugin::_display( CGI::br() );
    $this->{historyText} .= "%ORANGE% *WARNING* $message %ENDCOLOR%%BR%\n";
}

sub logError {
    my ( $this, $message ) = @_;
    Foswiki::Plugins::PublishPlugin::_display(
        CGI::span( { class => 'foswikiAlert' }, "ERROR: $message" ) );
    Foswiki::Plugins::PublishPlugin::_display( CGI::br() );
    $this->{historyText} .= "%RED% *ERROR* $message %ENDCOLOR%%BR%\n";
}

#  Publish one topic from web.
#   * =$topic= - which topic to publish (web.topic)
sub _publishTopic {
    my ( $this, $w, $t, $tmpl ) = @_;

    # Read topic data.
    my ( $w, $t ) = Foswiki::Func::normalizeWebTopicName( $w, $t );

    return
         if $this->{history}
      && $w eq $this->{history}->[0]
      && $t eq $this->{history}->[1];    # never publish this

    # SMELL: Nasty. Should fix Item13387.
    if ( defined &Foswiki::Plugins::TablePlugin::initialiseWhenRender ) {
        Foswiki::Plugins::TablePlugin::initialiseWhenRender();
    }

    my ( $meta, $text );
    my $publishRev = $this->{topicVersions}->{"$w.$t"};

    my $topic = "$w.$t";

    ( $meta, $text ) = Foswiki::Func::readTopic( $w, $t, $publishRev );
    unless ($publishRev) {
        my $d;
        ( $d, $d, $publishRev, $d ) = Foswiki::Func::getRevisionInfo( $w, $t );
    }

    unless (
        Foswiki::Func::checkAccessPermission(
            "VIEW", Foswiki::Func::getWikiName(),
            $text, $t, $w
        )
      )
    {
        $this->logError("View access to $topic denied");
        return;
    }

    if ( $this->{opt}->{rexclude} && $text =~ /$this->{opt}->{rexclude}/ ) {
        $this->logInfo( $topic, "excluded by filter" );
        return;
    }

    # clone the current session
    my %old;
    my $query = Foswiki::Func::getCgiQuery();
    $query->param( 'topic', $topic );

    Foswiki::Func::pushTopicContext( $w, $t );

    # Remove disabled plugins from the context
    foreach my $plugin ( keys( %{ $Foswiki::cfg{Plugins} } ) ) {
        next unless ref( $Foswiki::cfg{Plugins}{$plugin} );
        my $enable = $Foswiki::cfg{Plugins}{$plugin}{Enabled};
        Foswiki::Func::getContext()->{"${plugin}Enabled"} = $enable;
    }

    # Because of Item5388, we have to re-read the topic to get the
    # right session in the $meta. This could be done by patching the
    # $meta object, but this should be longer-lasting.
    # $meta has to have the right session otherwise $WEB and $TOPIC
    # won't work in %IF statements.
    ( $meta, $text ) = Foswiki::Func::readTopic( $w, $t, $publishRev );

    $Foswiki::Plugins::SESSION->enterContext( 'can_render_meta', $meta );

    # Allow a local definition of VIEW_TEMPLATE to override the
    # template passed in (unless this is disabled by a global option)
    my $override = Foswiki::Func::getPreferencesValue('VIEW_TEMPLATE');
    if ($override) {
        $tmpl =
          Foswiki::Func::readTemplate( $override, $this->{opt}->{publishskin},
            $w );
        $this->logInfo( $topic, "has a VIEW_TEMPLATE '$override'" );
    }

    my ( $revdate, $revuser, $maxrev );
    ( $revdate, $revuser, $maxrev ) = $meta->getRevisionInfo();
    if ( ref($revuser) ) {
        $revuser = $revuser->wikiName();
    }

    # Expand and render the topic text
    $text = Foswiki::Func::expandCommonVariables( $text, $t, $w, $meta );

    my $newText = '';
    my $tagSeen = 0;
    my $publish = 1;
    foreach my $s ( split( /(%STARTPUBLISH%|%STOPPUBLISH%)/, $text ) ) {
        if ( $s eq '%STARTPUBLISH%' ) {
            $publish = 1;
            $newText = '' unless ($tagSeen);
            $tagSeen = 1;
        }
        elsif ( $s eq '%STOPPUBLISH%' ) {
            $publish = 0;
            $tagSeen = 1;
        }
        elsif ($publish) {
            $newText .= $s;
        }
    }
    $text = $newText;

    # Expand and render the template
    $tmpl = Foswiki::Func::expandCommonVariables( $tmpl, $t, $w, $meta );

    # Inject the text into the template. The extra \n is required to
    # simulate the way the view script splits up the topic and reassembles
    # it around newlines.
    $text = "\n$text" unless $text =~ /^\n/s;

    $tmpl =~ s/%TEXT%/$text/;

    # legacy
    $tmpl =~ s/<nopublish>.*?<\/nopublish>//gs;

    $tmpl =~ s/.*?<\/nopublish>//gs;
    $tmpl =~ s/%MAXREV%/$maxrev/g;
    $tmpl =~ s/%CURRREV%/$maxrev/g;
    $tmpl =~ s/%REVTITLE%//g;

    # trim spaces at start and end
    $tmpl =~ s/^[[:space:]]+//s;    # trim at start
    $tmpl =~ s/[[:space:]]+$//s;    # trim at end

    $tmpl = Foswiki::Func::renderText( $tmpl, $w, $t );

    $tmpl = Foswiki::Plugins::PublishPlugin::PageAssembler::assemblePage( $this,
        $tmpl );

    if ( $Foswiki::Plugins::VERSION and $Foswiki::Plugins::VERSION >= 2.0 )
    {

        # Note: Foswiki 1.1 supplies this same header text
        # when dispatching completePageHandler.
        my $hdr = "Content-type: text/html\r\n";
        $Foswiki::Plugins::SESSION->{plugins}
          ->dispatch( 'completePageHandler', $tmpl, $hdr );
    }

    $tmpl =~ s|( ?) *</*nop/*>\n?|$1|gois;

    # Remove <base.../> tag
    $tmpl =~ s/<base[^>]+\/>//i;

    # Remove <base...>...</base> tag
    $tmpl =~ s/<base[^>]+>.*?<\/base>//i;

    # Clean up unsatisfied WikiWords.
    $tmpl =~ s/<(span|a) class="foswikiNewLink">(.*?)<\/\1>/$2/ge;

    # Copy files from pub dir to rsrc dir in static dir.
    my $hs = $ENV{HTTP_HOST} || "localhost";

    # Modify links relative to server base
    $tmpl =~
      s/<a [^>]*\bhref=[^>]*>/$this->_rewriteTag($&, 'href', $w, $t)/geis;
    $tmpl =~
      s/<link [^>]*\bhref=[^>]*>/$this->_rewriteTag($&, 'href', $w, $t)/geis;
    $tmpl =~
      s/<img [^>]*\bsrc=[^>]*>/$this->_rewriteTag($&, 'src', $w, $t)/geis;
    $tmpl =~
      s/<script [^>]*\bsrc=[^>]*>/$this->_rewriteTag($&, 'src', $w, $t)/geis;
    $tmpl =~
s/<blockquote [^]*\bcite=[^>]*>/$this->_rewriteTag($&, 'cite', $w, $t)/geis;
    $tmpl =~ s/<q [^>]*\bcite=[^>]*>/$this->_rewriteTag($&, 'cite', $w, $t)/gei;

    # No support for OBJECT, APPLET, INPUT

    $tmpl =~ s/<nop>//g;

    # Archive the resulting HTML.
    my $url = $this->{archive}->addTopic( $w, $t, $tmpl );

    # Process any uncopied resources
    if ( $this->{opt}->{allattachments} ) {
        my @lst = Foswiki::Func::getAttachmentList( $w, $t );
        foreach my $att (@lst) {
            $this->_processInternalResource( $w, $t, $att );
        }
    }

    if ( defined &Foswiki::Func::popTopicContext ) {
        Foswiki::Func::popTopicContext();
        if ( defined $Foswiki::Plugins::SESSION->{SESSION_TAGS} ) {

            # In 1.0.6 and earlier, have to handle some session tags ourselves
            # because pushTopicContext doesn't do it. **
            foreach my $macro (
                qw(BASEWEB BASETOPIC
                INCLUDINGWEB INCLUDINGTOPIC)
              )
            {
                $Foswiki::Plugins::SESSION->{SESSION_TAGS}{$macro} =
                  $old{$macro};
            }
        }

    }
    else {
        $Foswiki::Plugins::SESSION = $old{SESSION};    # restore session
    }

    $this->logInfo( "$w.$t", "Rev $publishRev published" );

    return $publishRev;
}

sub _rewriteTag {
    my ( $this, $tag, $key, $web, $topic ) = @_;

    # Parse the tag
    return $tag unless $tag =~ /^<(\w+)\s*(.*)\s*>/;
    my ( $type, $attrs ) = ( $1, $2 );
    my %attrs;
    while ( $attrs =~ s/^\s*([-A-Z0-9_]+)=(["'])(.*?)\2//i ) {
        $attrs{$1} = $3;
    }
    return $tag unless $attrs{$key};
    my $new = $this->_processURL( $attrs{$key} );
    unless ( $new eq $attrs{$key} || $new =~ /^#/ ) {

#print STDERR "Rewrite $new (rel to ".$this->{archive}->getTopicPath( $web, $topic ).') ';
        $new =
          File::Spec->abs2rel( $new,
            $this->{archive}->getTopicPath( $web, $topic ) . '/..' );

        #print STDERR "as $new\n";
    }

    #print STDERR "$attrs{$key} = $new\n";
    $attrs{$key} = $new;

    return
      "<$type " . join( ' ', map { "$_=\"$attrs{$_}\"" } keys %attrs ) . '>';
}

# Rewrite a URL - be it internal or external. Internal URLs that point to
# anything in pub, or to scripts, are always rewritten.
sub _processURL {
    my ( $this, $url ) = @_;

    my $url = URI->new($url);

    # $url->scheme
    # $url->user
    # $url->password
    # $url->host
    # $url->port
    # $url->epath
    # $url->eparams
    # $url->equery
    # $url->frag

    #print STDERR "Process $url\n";
    if ( !defined $url->path() || $url->path() eq '' ) {

        #print STDERR "- no path\n";
        # is there a frag?
        if ( $url->can('fragment') && $url->fragment ) {
            return '#' . $url->fragment();
        }

        # URL has no path, no frag. Maybe it has params, but if
        # so it's not publishable.
        return '';
    }

    sub _matchPart {
        my ( $a, $b ) = @_;
        return 1 if !defined $a && !defined $b;
        return 0 unless defined $a && defined $b;
        return 1 if $a eq $b;
        return 0;
    }

    sub _match {
        my ( $abs, $url, $match ) = @_;

        # Some older parsers used to allow the scheme name to be present
        # in the relative URL if it was the same as the base URL
        # scheme. RFC1808 says that this should be avoided, so we assume
        # it's not so, and if there's a scheme, it's absolute.
        if ( $match->can('scheme') ) {
            return undef
              unless ( $url->can('scheme') )
              && _matchPart( $url->scheme, $match->scheme );
        }
        elsif ( $url->can('scheme') ) {
            return undef;
        }
        if ( $match->can('host') ) {
            return undef
              unless $url->can('host')
              && _matchPart( $url->host, $match->host );
        }
        elsif ( $url->can('host') ) {
            return undef;
        }
        if ( $match->can('port') ) {
            return undef
              unless $url->can('port')
              && _matchPart( $url->port, $match->port );
        }
        elsif ( $url->can('port') ) {
            return undef;
        }

        my @upath = split( '/', $url->path );
        my @mpath = split( '/', $match->path );
        while (
               scalar @mpath
            && scalar @upath
            && (   $mpath[0] eq $upath[0]
                || $mpath[0] eq 'SCRIPT' )
          )
        {
            #print STDERR "- trim $upath[0] match $mpath[0]\n";
            shift(@mpath);
            shift(@upath);
        }
        return \@upath if $mpath[0] eq 'WEB';
        return undef;
    }

    # Is this local?
    unless ( $this->{url_paths} ) {
        $this->{url_paths} = {
            script_rel => URI->new(
                Foswiki::Func::getScriptUrlPath( 'WEB', 'TOPIC', 'SCRIPT' )
            ),
            script_abs => URI->new(
                Foswiki::Func::getScriptUrlPath( 'WEB', 'TOPIC', 'SCRIPT' )
            ),
            pub_rel => URI->new(
                Foswiki::Func::getPubUrlPath( 'WEB', 'TOPIC', 'ATTACHMENT' )
            ),
            pub_abs => URI->new(
                Foswiki::Func::getPubUrlPath(
                    'WEB', 'TOPIC', 'ATTACHMENT', absolute => 1
                )
            ),
        };
    }

    my ( $is_script, $is_pub, $upath ) = ( 0, 0 );
    if ( $upath = _match( 1, $url, $this->{url_paths}->{script_abs} ) ) {
        $is_script = 1;
    }
    elsif ( $upath = _match( 1, $url, $this->{url_paths}->{pub_abs} ) ) {
        $is_pub = 1;
    }
    elsif ( $upath = _match( 0, $url, $this->{url_paths}->{script_rel} ) ) {
        $is_script = 1;
    }
    elsif ( $upath = _match( 0, $url, $this->{url_paths}->{pub_rel} ) ) {
        $is_pub = 1;
    }

    return $url unless $upath;

    #print STDERR "- leaving ".join('/',@$upath)."\n";

    my $web;
    my $topic;
    my $attachment;
    my $new = $url;

    $web   = shift(@$upath) if scalar(@$upath);
    $topic = shift(@$upath) if scalar(@$upath);

    # Is it an internal resource?
    if ($is_pub) {
        $attachment = shift(@$upath) if scalar(@$upath);
        $new = $this->_processInternalResource( $web, $topic, $attachment );
    }
    elsif ($is_script) {

        # return a link to the topic in the archive. This is named
        # for the template being generated. We do this even if the
        # topic isn't included in the processed outout, so we may
        # end up with broken links. C'est la guerre.
        $new = $this->{archive}->getTopicPath( $web, $topic );
    }
    else {
        # Otherwise we have to process it as an external resource
        $new = $this->_processExternalResource($url);
    }

    #print STDERR "-mapped $new";
    return $new;
}

# Copy a resource from pub (image, style sheet, etc.) to
# the archive. Return the path to the copied resource in the archive.
sub _processInternalResource {
    my ( $this, $web, $topic, $attachment ) = @_;

    my $rsrc = join( '/', $web, $topic, $attachment );

    # See if we've already copied this resource.
    return $this->{copied_resources}->{$rsrc}
      if ( defined $this->{copied_resources}->{$rsrc} );

    my $data;

    # See it it's an attachment
    if ( Foswiki::Func::attachmentExists( $web, $topic, $attachment ) ) {
        $data = Foswiki::Func::readAttachment( $web, $topic, $attachment );
    }
    else {
        # Not an attachment - pull on our muddy boots and puddle
        # around in directories - if they exist!
        my $pubDir = Foswiki::Func::getPubDir();
        my $src    = "$pubDir/$rsrc";
        if ( open( my $fh, '<', $src ) ) {
            local $/;
            binmode($fh);
            $data = <$fh>;
            close($fh);
        }
        else {
            $this->logError("$src is not readable");
            return 'MISSING RESOURCE $rsrc';
        }
    }
    if ( $attachment =~ /\.css$/i ) {
        $data =~ s/\burl\((["']?)(.*?)\1\)/$1.$this->_processURL($2).$1/ge;
    }
    $this->{copied_resources}->{$rsrc} =
      $this->{archive}->addAttachment( $web, $topic, $attachment, $data );
    return $this->{copied_resources}->{$rsrc};
}

sub _processExternalResource {
    my ( $this, $url ) = @_;

    return $url unless $this->{opt}->{copyexternal};

    return $this->{copied_resources}->{$url}
      if ( $this->{copied_resources}->{$url} );

    my $response = Foswiki::Func::getExternalResource($url);
    if ( $response->is_error() ) {
        $this->logError("$url is not fetchable");
    }

    my $ext;
    if ( $url =~ /(\.\w+)(\?|#|$)/ ) {
        $ext = $1;
    }
    $this->{copied_resources}->{$url} =
      $this->{archive}->addResource( $response->content(), $ext );

    return $this->{copied_resources}->{$url};
}

1;
__END__
#
# Copyright (C) 2001 Motorola
# Copyright (C) 2001-2007 Sven Dowideit, svenud@ozemail.com.au
# Copyright (C) 2002, Eric Scouten
# Copyright (C) 2005-2008 Crawford Currie, http://c-dot.co.uk
# Copyright (C) 2006 Martin Cleaver, http://www.cleaver.org
# Copyright (C) 2010 Arthur Clemens, http://visiblearea.com
# Copyright (C) 2010 Michael Tempest
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
