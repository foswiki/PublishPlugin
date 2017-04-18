# See bottom of file for license and copyright details
package Foswiki::Plugins::PublishPlugin::Publisher;

use strict;

use Foswiki;
use Foswiki::Func;
use Error ':try';
use Assert;
use Foswiki::Plugins::PublishPlugin::PageAssembler;

sub CHECKLEAK { 0 }

BEGIN {
    if (CHECKLEAK) {
        eval "use Devel::Leak::Object qw{ GLOBAL_bless };";
        die $@ if $@;
        $Devel::Leak::Object::TRACKSOURCELINES = 1;
    }
}

my %PARAM_SCHEMA = (
    allattachments => { desc => 'Publish All Attachments' },
    copyexternal   => {
        default => 1,
        desc    => 'Copy Off-Wiki Resources'
    },
    enableplugins => {
        validator => \&_validateList,
        desc      => 'Enable Plugins'
    },
    exclusions => {
        validator => \&_wildcard2RE,
        desc      => 'Topic Exclude Filter'
    },
    format => {
        default   => 'file',
        validator => \&_validateWord,
        desc      => 'Output Generator'
    },
    history => {
        default   => '',
        validator => \&_validateTopicNameOrNull,
        desc      => 'History Topic'
    },
    inclusions => {
        validator => \&_wildcard2RE,
        desc      => 'Topic Include Filter'
    },
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
        default   => '/rsrc',
        validator => sub {
            my ( $v, $k ) = @_;
            $v = _validateRelPath( $v, $k );
            die "Invalid $k: '$v'" if $v =~ /^\./;
            return "/$v";
          }
    },
    templates => {
        default   => 'view',
        validator => \&_validateList,
        desc      => 'Using Templates'
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
    web => { validator => \&_validateWebName },

    # Renamed options
    filter      => { renamed => 'rexclude' },
    instance    => { renamed => 'relativedir' },
    genopt      => { renamed => 'extras' },
    topicsearch => { renamed => 'rexclude' },
    skin        => { renamed => 'publishskin' },
    topiclist   => { renamed => 'topics' }
);

sub _wildcard2RE {
    my $v = shift;
    $v =~ s/([*?])/.$1/g;
    $v =~ s/,/|/g;
    return _validateRE( $v, @_ );
}

sub _validateRE {
    my $v = shift;

    # SMELL: do a much better job of this!
    $v =~ /^(.*)$/;
    return $1;
}

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

# Create a parameter hash from a CGI query
sub _loadParams {
    my ( $this, $data ) = @_;

    if ( ref($data) eq 'HASH' ) {
        my $d = $data;
        $data = sub { return $d->{ $_[0] }; };
    }

    # Set up our context
    $this->{web} = &$data('web') // $Foswiki::cfg{SystemWebName};

    if ( &$data('configtopic') ) {
        my @wl = split( / *, */, $this->{web} );
        my ( $cw, $ct ) =
          Foswiki::Func::normalizeWebTopicName( $wl[0], $data->{config_topic} );
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

sub new {
    my ( $class, $params, $session ) = @_;

    my $this = bless(
        {
            session         => $session,
            templatesWanted => 'view',

            # this records which templates (e.g. view, viewprint, viuehandheld,
            # etc) have been referred to and thus should be generated.
            templatesReferenced => {},

            # serial number for giving unique names to external resources
            nextExternalResourceNumber => 0,
        },
        $class
    );

    $this->_loadParams($params);
    $this->{opt}->{publishskin} ||=
      Foswiki::Func::getPreferencesValue('PUBLISHSKIN')
      || 'basic_publish';

    $this->{historyText} = '';
    return $this;
}

sub finish {
    my $this = shift;
    $this->{session} = undef;
}

sub publish {
    my ($this) = @_;

    # don't add extra markup for topics we're not linking too
    # NEWTOPICLINKSYMBOL LINKTOOLTIPINFO
    if ( defined $Foswiki::Plugins::SESSION->{renderer} ) {
        $Foswiki::Plugins::SESSION->{renderer}->{NEWLINKSYMBOL} = '';
    }
    else {
        $Foswiki::Plugins::SESSION->renderer()->{NEWLINKSYMBOL} = '';
    }

    # Disable unwanted plugins
    my $enabledPlugins  = '';
    my $disabledPlugins = '';
    my @pluginsToEnable;

    if ( $this->{opts}->{enableplugins} ) {
        @pluginsToEnable = split( /[, ]+/, $this->{opt}->{enableplugins} );
    }

    foreach my $plugin ( keys( %{ $Foswiki::cfg{Plugins} } ) ) {
        next unless ref( $Foswiki::cfg{Plugins}{$plugin} ) eq 'HASH';
        my $enable = $Foswiki::cfg{Plugins}{$plugin}{Enabled};
        if ( scalar(@pluginsToEnable) > 0 ) {
            $enable = grep( /\b$plugin\b/, @pluginsToEnable );
            $Foswiki::cfg{Plugins}{$plugin}{Enabled} = $enable;
        }
        $enabledPlugins .= ', ' . $plugin if ($enable);
        $disabledPlugins .= ', ' . $plugin unless ($enable);
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
    foreach my $p (qw()) {
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
    my %wl;
    if ( $this->{web} ) {
        my @wl = split( / *, */, $this->{web} );

        # Get subwebs
        @wl = map { $_, Foswiki::Func::getListOfWebs( undef, $_ ) } @wl;
        %wl = map { $_ => 1 } @wl;
    }
    else {
        # get a list of ALL webs
        %wl = map { $_ => 1 } Foswiki::Func::getListOfWebs();
    }

    my @webs     = sort keys %wl;
    my $firstWeb = $webs[0];

    my %topics;
    foreach my $web (@webs) {
        if ( $this->{opt}->{topics} ) {
            foreach my $topic ( split( /[,\s]+/, $this->{opt}->{topics} ) ) {
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
        @topics = grep { /$this->{opt}->{inclusions}/ } @topics;
    }

    if ( $this->{opt}->{exclusions} ) {
        @topics = grep { !/$this->{opt}->{exclusions}/ } @topics;
    }

    # Determine the set of topics for each unique web
    my %webset;
    foreach my $t (@topics) {
        my ( $w, $t ) = Foswiki::Func::normalizeWebTopicName( undef, $t );
        $webset{$w} //= [];
        push( @{ $webset{$w} }, $t );
    }

    # Open an archive for each template
    $this->{templatesWanted} =
      [ sort grep { !/^\s*$/ } split( /\s*,\s*/, $this->{opt}->{templates} ) ];

    foreach my $template ( @{ $this->{templatesWanted} } ) {
        my $dir =
            $Foswiki::cfg{PublishPlugin}{Dir}
          . $this->{relativedir}
          . $this->_dirForTemplate($template);

        File::Path::mkpath($dir);

        $this->{archives}->{$template} =
          $this->{generator}->new( $this, $dir, $this );
    }

    while ( my ( $w, $ts ) = each %webset ) {
        $this->_publishInWeb( $w, $ts );
    }

    # Close archives
    foreach my $template ( @{ $this->{templatesWanted} } ) {
        my $landed = $this->{archives}->{$template}->close();
        my $url =
            $Foswiki::cfg{PublishPlugin}{URL}
          . $this->{opt}->{relativedir}
          . $landed;
        $this->logInfo( "Published to", "<a href=\"$url\">$url</a>" );
    }

    if ( $this->{history} ) {

        my ( $hw, $ht ) =
          Foswiki::Func::normalizeWebTopicName( $firstWeb, $this->{history} );
        unless (
            Foswiki::Func::checkAccessPermission(
                'CHANGE', Foswiki::Func::getWikiName(),
                undef, $ht, $hw
            )
          )
        {
            $this->logError( <<TEXT, $footer );
Cannot publish because current user cannot CHANGE $hw.$ht.
This topic must be editable by the user doing the publishing.
TEXT
            return;
        }
        $this->{history} = "$hw.$ht";

        my ( $meta, $text ) = Foswiki::Func::readTopic( $hw, $ht );
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
        elsif ( Foswiki::Func::topicExists( $hw, $ht ) ) {

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
        Foswiki::Func::saveTopic( $hw, $ht, $meta, $history,
            { minor => 1, forcenewrevision => 1 } );
        my $url = Foswiki::Func::getScriptUrl( $hw, $ht, 'view' );
        $this->logInfo( "History saved in", "<a href='$url'>$url</a>" );
    }

    Foswiki::Plugins::PublishPlugin::_display($footer);
}

# $web - the web to publish in
# \@topics - list of topics in this web to publish
sub _publishInWeb {
    my ( $this, $web, $topics ) = @_;

    $this->logInfo( '', "<h2>Publishing in web '$web'</h2>" );
    if ( $this->{opt}->{versions} ) {
        $this->{topicVersions} = {};
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

    foreach my $template ( @{ $this->{templatesWanted} } ) {
        next unless $template;
        $this->{templatesReferenced}->{$template} = 1;
        $this->_publishUsingTemplate( $template, $web, $topics );
    }

    # check the templates referenced, and that everything referenced
    # has been generated.
    my @templatesReferenced = sort keys %{ $this->{templatesReferenced} };

    my @difference =
      arrayDiff( \@templatesReferenced, $this->{templatesWanted} );
    if ( $#difference > 0 ) {
        $this->logInfo( "Templates Used", join( ",", @templatesReferenced ) );
        $this->logInfo( "Templates Specified",
            join( ",", @{ $this->{templatesWanted} } ) );
        $this->logWarn(<<BLAH);
There is a difference between the templates you specified and what you
needed. Consider changing the TEMPLATES setting so it has all Templates
Used.
BLAH
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

#  Publish a set of topics using the given template (e.g. view)
sub _publishUsingTemplate {
    my ( $this, $template, $web, $topics ) = @_;

    # Choose template. Note that $template_TEMPLATE can still override
    # this in specific topics.
    my $tmpl =
      Foswiki::Func::readTemplate( $template, $this->{opt}->{publishskin} );
    die "Couldn't find template\n" if ( !$tmpl );
    my $filetype = _filetypeForTemplate($template);

    # Attempt to render each included page.
    my %copied;
    foreach my $topic (@$topics) {
        next
          if $this->{opt}->{history}
          && $topic eq $this->{opt}->{history};    # never publish this
        try {
            my $rev =
              $this->publishTopic( $web, $topic, $filetype, $template,
                $tmpl, \%copied )
              || '0';
            $topic =
                '<a href="'
              . Foswiki::Func::getScriptUrl( $web, $topic, 'view', rev => $rev )
              . '">'
              . $topic . '</a>';
        }
        catch Error::Simple with {
            my $e = shift;
            $this->logError(
                "$web.$topic not published: " . ( $e->{-text} || '' ) );
        };

        # Prevent slowdown and unnecessary memory use if templates are
        # frequently reloaded, for some 1.1.x versions of Foswiki.
        # This is NOT a likely condition, and it is only known to manifest
        # when there are additional problems in the data being published.
        # However, if there is something wrong in the publishing configuration,
        # then it is possible for many pages to have at least one inline alert,
        # and Foswiki::inlineAlert reloads its template each time it is called
        # (at least, it does for some versions of Foswiki).
        # This can be problem when publishing several hundred topics.
        # Sure - the publishing configuration should be fixed,
        # but it can be tricky to debug that configuration if Apache is
        # killing the publishing process.
        if (   $Foswiki::cfg{PublishPlugin}{PurgeTemplates}
            && $Foswiki::Plugins::SESSION->can('templates')
            and $Foswiki::Plugins::SESSION->{templates}
            and ref $Foswiki::Plugins::SESSION->{templates}
            and $Foswiki::Plugins::SESSION->{templates}->can('finish') )
        {
            $Foswiki::Plugins::SESSION->{templates}->finish();
            undef $Foswiki::Plugins::SESSION->{templates};
        }

        Devel::Leak::Object::checkpoint() if CHECKLEAK;
    }
}

#  Publish one topic from web.
#   * =$topic= - which topic to publish (web.topic)
#   * =$filetype= - which filetype (pdf, html) to use as a suffix on the file generated

#   * =\%copied= - map of copied resources to new locations
sub publishTopic {
    my ( $this, $w, $t, $filetype, $template, $tmpl, $copied ) = @_;

    # Read topic data.
    my ( $w, $t ) = Foswiki::Func::normalizeWebTopicName( $w, $t );

    my ( $meta, $text );
    my $publishedRev =
        $this->{topicVersions}
      ? $this->{topicVersions}->{"$w.$t"}
      : undef;

    my $topic   = "$w.$t";
    my $archive = $this->{archives}->{$template};

    ( $meta, $text ) = Foswiki::Func::readTopic( $w, $t, $publishedRev );
    unless ($publishedRev) {
        my $d;
        ( $d, $d, $publishedRev, $d ) =
          Foswiki::Func::getRevisionInfo( $w, $t );
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

    # In 1.0.6 and earlier, have to handle some session tags ourselves
    # because pushTopicContext doesn't do it. **
    if ( defined $Foswiki::Plugins::SESSION->{SESSION_TAGS} ) {
        foreach my $macro (
            qw(BASEWEB BASETOPIC
            INCLUDINGWEB INCLUDINGTOPIC)
          )
        {
            $old{$macro} = Foswiki::Func::getPreferencesValue($macro);
        }
    }
    Foswiki::Func::pushTopicContext( $w, $t );
    if ( defined $Foswiki::Plugins::SESSION->{SESSION_TAGS} ) {

        # see ** above
        my $stags = $Foswiki::Plugins::SESSION->{SESSION_TAGS};
        $stags->{BASEWEB}        = $w;
        $stags->{BASETOPIC}      = $t;
        $stags->{INCLUDINGWEB}   = $w;
        $stags->{INCLUDINGTOPIC} = $t;
    }

    # Remove disabled plugins from the context
    foreach my $plugin ( keys( %{ $Foswiki::cfg{Plugins} } ) ) {
        next unless ref( $Foswiki::cfg{Plugins}{$plugin} ) eq 'HASH';
        my $enable = $Foswiki::cfg{Plugins}{$plugin}{Enabled};
        Foswiki::Func::getContext()->{"${plugin}Enabled"} = $enable;
    }

    # Because of Item5388, we have to re-read the topic to get the
    # right session in the $meta. This could be done by patching the
    # $meta object, but this should be longer-lasting.
    # $meta has to have the right session otherwise $WEB and $TOPIC
    # won't work in %IF statements.
    ( $meta, $text ) = Foswiki::Func::readTopic( $w, $t, $publishedRev );

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

    $tmpl = Foswiki::Func::renderText( $tmpl, $w );

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
    $tmpl =~ s/<span class="foswikiNewLink">(.*?)<\/span>/
      $this->_handleNewLink($1)/ge;

    # Copy files from pub dir to rsrc dir in static dir.
    my $hs = $ENV{HTTP_HOST} || "localhost";

    # Find and copy resources attached to the topic
    my $pub = Foswiki::Func::getPubUrlPath();
    $tmpl =~
      s!(['"\(])($Foswiki::cfg{DefaultUrlHost}|https?://$hs)?$pub/(.*?)(\1|\))!
      $1.$this->_rsrcpath( $w ,$this->_copyResource($3, $archive, $copied), $archive ).$4!ge;

    my $ilt;

    # Modify local links to topics relative to server base
    $ilt =
      $Foswiki::Plugins::SESSION->getScriptUrl( 0, 'NOISY', 'NOISE', 'NOISE' );
    $ilt =~ s!/NOISE/NOISE.*$!!;
    $ilt =~ s!/NOISY!/[a-z.]+!;
    $tmpl =~
s!href=(["'])$ilt/(.*?)\1!"href=$1".$this->_topicURL($ilt, $2, $w, $archive).$1!ge;

    # Handle simple topic links
    $tmpl =~
s!href=(["'])([$Foswiki::regex{mixedAlphaNum}_]+([#?].*?)?)\1!"href=$1".$this->_topicURL($ilt, "$w/$2", $w, $archive).$1!ge;

    # Modify absolute topic links.
    $ilt =
      $Foswiki::Plugins::SESSION->getScriptUrl( 1, 'view', 'NOISE', 'NOISE' );
    $ilt =~ s!/NOISE/NOISE.*$!!;

    $tmpl =~
s!href=(["'])$ilt/(.*?)\1!"href=$1".$this->_topicURL($ilt, $2, $w, $archive).$1!ge;

    # Modify topic-relative links

    # Handle topic creation links
    $tmpl =~ s!<a[^>]*class=(["'])foswikiNewLink\1[^>]*>(.*?)</a>!<a>$2</a>!g;

    # Modify topic-relative TOC links to strip out parameters (but not anchor)
    $tmpl =~ s!href=(["'])\?.*?(\1|#)!href=$1$2!g;

    # replace any external template references
    $tmpl =~ s!href=["'](.*?)\?template=(\w*)(.*?)["']!
      $this->_rewriteTemplateReferences($tmpl, $1, $2, $3)!e;

    # Handle image tags using absolute URLs not otherwise satisfied
    $tmpl =~ s!(<img\s+.*?\bsrc=)(["'])(.*?)\2(.*?>)!
      $1.$2.$this->_rsrcpath( $w, $this->_handleURL($3,\($this->{nextExternalResourceNumber})), $archive ).$2.$4!ge;

    $tmpl =~ s/<nop>//g;

    # Write the resulting HTML.
    $w =~ s#\.#/#g;
    $archive->addString( $tmpl, "$w/$t$filetype" );

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

    $this->logInfo( "$w.$t", "Rev $publishedRev published" );

    return $publishedRev;
}

# rewrite
#   Topic?template=viewprint%REVARG%.html?template=viewprint%REVARG%
# to
#   _viewprint/Topic.html
#
#   * =$this->{web}=
#   * =$tmpl=
#   * =$topic=
#   * =$template=
# return
#   *
# side effects

sub _rewriteTemplateReferences {
    my ( $this, $tmpl, $topic, $template, $redundantduplicate ) = @_;

# for an unknown reason, these come through with doubled up template= arg
# e.g.
# http://.../site/instance/Web/WebHome?template=viewprint%REVARG%.html?template=viewprint%REVARG%
#$link:
# Web/ContactUs?template=viewprint%REVARG%.html? "
    $topic =~ s#\.#/#g;
    my $newLink =
        $Foswiki::cfg{PublishPlugin}{URL}
      . $this->_dirForTemplate($template)
      . $topic
      . _filetypeForTemplate($template);
    $this->{templatesReferenced}->{$template} = 1;
    return "href='$newLink'";
}

# Where alternative templates (e.g. viewprint) renderings end up
sub _dirForTemplate {
    my ( $this, $template ) = @_;
    return '' if ( $template eq 'view' );
    return $template;
}

# SMELL this needs to be table driven
sub _filetypeForTemplate {
    my ($template) = @_;
    return '.pdf' if ( $template eq 'viewpdf' );
    return '.html';
}

#  Copy a resource (image, style sheet, etc.) from pub/%WEB% to
#   static HTML's rsrc directory.
#   * =$srcName= - name of resource (relative to pub/%WEB%)
#   * =$archive= - archive object
#   * =\%copied= - map of copied resources to new locations
sub _copyResource {
    my ( $this, $srcName, $archive, $copied ) = @_;

    # srcName is a URL. Expand it.
    $srcName = Foswiki::urlDecode($srcName);

    my $rsrcName = $srcName;

    # Trim the resource name, as they can sometimes pick up whitespaces
    $rsrcName =~ /^\s*(.*?)\s*$/;
    $rsrcName = $1;

    # This is covers up a case such as where rsrcname comes through like
    # configtopic=PublishTestWeb/WebPreferences/favicon.ico
    # this should be just WebPreferences/favicon.ico
    if ( $rsrcName =~ m/configtopic/ ) {
        die "rsrcName '$rsrcName' contains literal 'configtopic'";
    }

    # See if we've already copied this resource.
    unless ( exists $copied->{$rsrcName} ) {

        # strip off things like ?version=wossname arguments appended to .js
        my $bareRsrcName = $rsrcName;
        $bareRsrcName =~ s/\?.*//o;

        # Nope, it's new. Gotta copy it to new location.
        # Split resource name into path (relative to pub/%WEB%) and leaf name.
        my $file = $bareRsrcName;
        $file =~ s(^(.*)\/)()o;
        my $path = "";
        if ( $bareRsrcName =~ "/" ) {
            $path = $bareRsrcName;
            $path =~ s(\/[^\/]*$)()o;    # path, excluding the basename
        }

        # Copy resource to rsrc directory.
        my $pubDir = Foswiki::Func::getPubDir();
        my $src    = "$pubDir/$bareRsrcName";
        if ( -r "$pubDir/$bareRsrcName" ) {
            $archive->addDirectory( $this->{opt}->{rsrcdir} );
            $archive->addDirectory("$this->{opt}->{rsrcdir}/$path");
            my $dest = "$this->{opt}->{rsrcdir}/$path/$file";
            $dest =~ s!//!/!g;
            if ( -d $src ) {
                $archive->addDirectory( $src, $dest );
            }
            else {
                $archive->addFile( $src, $dest );
            }

            # Record copy so we don't duplicate it later.
            $copied->{$rsrcName} = $dest;
        }
        else {
            $this->logError("$src is not readable");
        }

        # check css for additional resources, ie, url()
        if ( $bareRsrcName =~ /\.css$/ ) {
            my @moreResources = ();
            my $fh;
            if ( open( $fh, '<', $src ) ) {
                local $/;
                binmode($fh);
                my $data = <$fh>;
                close($fh);
                $data =~ s#\/\*.*?\*\/##gs;    # kill comments
                foreach my $line ( split( /\r?\n/, $data ) ) {
                    if ( $line =~ /url\(["']?(.*?)["']?\)/ ) {
                        push @moreResources, $1;
                    }
                }
                my $pub = Foswiki::Func::getPubUrlPath();
                foreach my $resource (@moreResources) {

                    # if the resource is at an absolute URL (not path)
                    # don't try and make a local copy of it.  that
                    # would require rewriting the CSS file which is not
                    # currently supported.

                    unless ( $resource =~ /^http/ ) {

                        # recurse
                        if ( $resource !~ m!^/! ) {

                            # if the url is not absolute, assume it's
                            # relative to the current path
                            $resource = $path . '/' . $resource;
                        }
                        else {
                            if ( $resource =~ m!$pub/(.*)! ) {
                                my $old = $resource;
                                $resource = $1;
                            }
                        }
                        $this->_copyResource( $resource, $archive, $copied );
                    }
                }
            }
        }
    }
    return $copied->{$rsrcName} if $copied->{$rsrcName};
    $this->logError("MISSING RESOURCE $rsrcName");
    return "MISSING RESOURCE $rsrcName";
}

# Deal with a topic URL. The path passed is *after* removal of the prefix
# added by getScriptURL
# $root - the root of the URL path, recognised as being a URL on the wiki
# $path - the foswiki path to the topic from the URL
sub _topicURL {
    my ( $this, $root, $path, $web, $archive ) = @_;
    my $anchor = '';
    my $params = '';

    # Null path -> server root
    $path = $Foswiki::cfg{HomeTopicName} unless defined $path;

    if ( $path =~ s/(\?.*?)?(#.*?)?$// ) {
        $params = $1 if defined $1;
        $anchor = $2 if defined $2;
    }

    # Is this a path to a known topic? If not, reform the original URL
    # SMELL: don't do this, the URL matched something in this web, even
    # if it's not there we need to map it, even though it's a broken link.
    # return "$root/$path$params$anchor" unless $this->{topics}->{$path};

    # For here on we know we're dealing with a topic link, so we
    # ignore params in the rewritten URL - they won't be any use
    # when linking to static content.

    # See if the generator can deal with this topic
    if ( $archive && $archive->can('mapTopicURL') ) {
        my $gen = $archive->mapTopicURL( $path . $anchor );
        return $gen if $gen;
    }

    # Default handling; assumes we are recreating the hierarchy in
    # the output.
    $path .= $Foswiki::cfg{HomeTopicName} if $path =~ /\/$/;

    # Normalise
    $web  = join( '/', split( /[\/\.]+/, $web ) );
    $path = join( '/', split( /[\/\.]+/, $path ) );

    # make a path relative to the web
    $path = File::Spec->abs2rel( $path, $web );

    $path .= '.html';

    return $path . $anchor;
}

sub _handleURL {
    my ( $this, $src, $extras ) = @_;

    return $src unless $this->{opt}->{copyexternal};

    my $data;
    if ( defined(&Foswiki::Func::getExternalResource) ) {
        my $response = Foswiki::Func::getExternalResource($src);
        return $src if $response->is_error();
        $data = $response->content();
    }
    else {
        return $src unless $src =~ m!^([a-z]+)://([^/:]*)(:\d+)?(/.*)$!;
        my $protocol = $1;
        my $host     = $2;
        my $port     = $3 || 80;
        my $path     = $4;

        # Early getUrl didn't support protocol
        if ( $Foswiki::Plugins::SESSION->{net}->can('_getURLUsingLWP') ) {
            $data =
              $Foswiki::Plugins::SESSION->{net}
              ->getUrl( $protocol, $host, $port, $path );
        }
        else {
            $data =
              $Foswiki::Plugins::SESSION->{net}->getUrl( $host, $port, $path );
        }
    }

    # Note: no extension; rely on file format.
    # Images are pretty good that way.
    my $file = '___extra' . $$extras++;
    $this->{archive}->addDirectory( $this->{opt}->{rsrcdir} );

    my $fpath = "$this->{opt}->{rsrcdir}/$file";
    $this->{archive}->addString( $data, $fpath );
    return $fpath;
}

# Returns a pattern that will match the HTML used to represent an
# unsatisfied link. THIS IS NASTY, but I don't know how else to do it.
# SMELL: another case for a WysiwygPlugin-style rendering engine
sub _handleNewLink {
    my ( $this, $link ) = @_;
    $link =~ s!<a .*?>!!gi;
    $link =~ s!</a>!!gi;
    return $link;
}

# return a relative path to a resource given a location to a resource
# and the path to the current output directory.  the various stages of
# cleanup may cause a path to be run through this function multiple
# times; make sure that we only modify the path the first time.
sub _rsrcpath {

    my ( $this, $odir, $rsrcloc, $archive ) = @_;

    # if path is already relative or URLish, return it
    return $rsrcloc if $rsrcloc =~ m{^(\.+/|[a-z]+:)};

    $odir = "/$odir" unless $odir =~ /^\//;

    # See if the generator wants to deal with this resource
    my $nloc;
    if ( $archive && $archive->can('mapResourceURL') ) {
        $nloc = $archive->mapResourceURL( $odir, $rsrcloc );
    }

    unless ($nloc) {

        # relative path to rsrc dir from output dir
        $nloc = File::Spec->abs2rel( $rsrcloc, $odir );
    }

    # ensure there's an explicit relative path so it can
    # be identified next time 'round
    $nloc = './' . $nloc unless $nloc =~ /^\./;

    return $nloc;
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
