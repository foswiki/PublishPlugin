# See bottom of file for license and copyright details
package Foswiki::Plugins::PublishPlugin::Publisher;

use strict;

use Foswiki;
use Foswiki::Func;
use Error ':try';
use Assert;
use URI ();

require Exporter;
our @ISA       = qw(Exporter);
our @EXPORT_OK = qw(validateWord validateBoolean);

# Parameters, passed to publish()
my %PARAM_SCHEMA = (
    allattachments => {
        default   => 0,
        desc      => 'Publish All Attachments',
        validator => \&validateBoolean
    },
    copyexternal => {
        default   => 0,
        desc      => 'Copy Off-Wiki Resources',
        validator => \&validateBoolean
    },
    debug => {
        default   => 0,
        desc      => 'Enable debug messages',
        validator => \&validateBoolean
    },
    enableplugins => {

        # Keep this list in sync with System.PublishPlugin
        default =>
'-CommentPlugin,-EditRowPlugin,-EditTablePlugin,-NatEditPlugin,-SubscribePlugin,-TinyMCEPlugin,-UpdatesPlugin',
        validator => sub {
            validateList( @_, \&validateWebTopicWildcard );
        },
        desc => 'Enable Plugins'
    },
    exclusions => {
        desc      => 'Topic Exclude Filter (deprecated, use =topics=)',
        validator => sub {
            validateList( @_, \&validateWebTopicWildcard );
          }
    },
    format => {
        default   => 'file',
        validator => \&validateWord,
        desc      => 'Output Generator'
    },
    history => {
        validator => \&validateWebTopicWildcard,
        desc      => 'History Topic'
    },
    inclusions => {
        desc      => 'Topic Include Filter (deprecated, use =topics=)',
        validator => sub {
            validateList( @_, \&validateWebTopicWildcard );
          }
    },
    preferences => {
        desc      => 'Extra Preferences',
        validator => sub {
            my ( $k, $v ) = @_;
            _parsePreferences(
                $v,
                sub {
                    my ( $pref, $val ) = @_;
                    validateWord( $pref, $k );
                }
            );
          }
    },
    publishskin => {
        default   => 'basic_publish',
        validator => sub {
                validateList( @_, \&validateWord );
                },
        desc      => 'Publish Skin'
    },
    template => {
        default   => 'view',
        desc      => 'Template to use for publishing',
        validator => \&validateWord
    },
    topiclist => {
        desc      => 'Deprecated, use =topics=',
        validator => sub {
            validateList( @_, \&validateWord );
          }
    },
    topics => {
        default        => '*.*',
        allowed_macros => 1,
        desc           => 'Topics',
        validator      => sub {
            validateList( @_, \&validateWebTopicWildcard );
          }
    },
    rexclude => {
        validator => \&validateRE,
        desc      => 'Content Filter'
    },
    unpublished => {
        default   => 'rewrite',
        desc      => ' How to handle links to unpublished topics',
        validator => \&validateWord
    },
    versions => {
        validator => \&validateWebTopicName,
        desc      => 'Versions Topic'
    },
    web => {
        desc      => 'Deprecated, use =topics=',
        validator => \&validateWord
    },

    # Renamed options
    filter      => { renamed => 'rexclude' },
    topicsearch => { renamed => 'rexclude' },
    skin        => { renamed => 'publishskin' }
);

# Parameter validators
sub validateList {
    my ( $v, $k, $fn ) = @_;

    return undef unless defined $v;

    foreach my $t ( split( /\s*,\s*/, $v ) ) {
        &$fn( $t, $k );
    }
    return $v;
}

sub validateBoolean {

    # Allow undef, '', 1, 0
    my ( $v, $k ) = @_;
    if ($v) {
        die "Invalid boolean '$v' in $k"
          unless $v =~ /^(y(es)?|t(rue)?|1|on)$/i;
    }
    return $v ? 1 : 0;
}

sub validateRE {
    my ( $v, $k ) = @_;

    return undef unless defined $v;

    my $re;
    eval { $re = qr/$v/; };
    die "Invalid regex '$v' in $k" if ($@);
    return $v;
}

sub validateWebTopicWildcard {
    my ( $v, $k ) = @_;

    return undef unless defined $v;

    # Replace wildcard components with Xx to make a simple name
    my $tv = $v;
    $tv =~ s/[][*?]/Xx/g;
    validateWebTopicName( $tv, $k );
    return $v;
}

sub validateWebTopicName {
    my ( $v, $k ) = @_;

    return undef unless defined $v;

    my ( $w, $t );
    if ( $v =~ /\./ ) {
        ( $w, $t ) = split( /\./, $v, 2 );
    }
    else {
        $t = $v;
    }
    if ( defined $t && $t ne '' ) {
        die "Invalid topic '$v' in $k"
          unless Foswiki::Func::isValidTopicName( $t, 1 );
    }

    if ( defined $w && $w ne '' ) {
        my $xx = $w;
        $xx =~ s/[][*?]/Xx/g;
        $xx =~ s/^-//;
        die "Invalid web '$v' in $k"
          unless Foswiki::Func::isValidWebName($xx);
    }
    return $v;
}

sub validateWord {
    my ( $v, $k ) = @_;

    return undef unless defined $v;

    die "Invalid word '$v' in $k" unless $v =~ /^(\w*)$/;
    return $v;
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
            &$data('configtopic') );
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

    my $format_prefix = ( &$data('format') // 'NONE' ) . '_';

    # Sort to make it deterministic
    foreach my $ok ( sort keys %schema ) {

        my $v;
        my $k    = $ok;
        my $spec = $schema{$k};

        # map file_outfile to outfile
        if ( defined( &$data( $format_prefix . $k ) ) ) {
            $v = &$data( $format_prefix . $k );
        }
        else {
            $v = &$data($k);
        }

        my $renamed = 0;
        while ( defined $spec->{renamed} ) {
            $k       = $spec->{renamed};
            $spec    = $schema{$k};
            $renamed = 1;

            #print STDERR "Rename $ok to $k\n";
        }

        next if defined $opt{$k};

        ASSERT( defined $spec->{validator}, $k ) if DEBUG;

        if ( !defined $v && defined $spec->{default} && !$renamed ) {

            #print STDERR "Default $ok to '$spec->{default}'\n";
            $v = $spec->{default};
        }
        elsif ( defined $v ) {
            $this->logInfo("$ok = '$v'");
        }

        next unless defined $v;

        if ( defined $spec->{allowed_macros} ) {
            $v = Foswiki::Func::expandCommonVariables($v);
        }

        $v = &{ $spec->{validator} }( $v, $k );

        $opt{$k} = $v;
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

# Parse preference settings from preferences= parameter
sub _parsePreferences {
    my ( $prefs, $callback ) = @_;
    foreach my $setting ( split( /\n+/, $prefs ) ) {
        if ( $setting =~ /^\s*(\w+)\s*=(.*)$/ ) {
            &$callback( $1, $2 );
        }
    }
}

# Constructor
sub new {
    my ( $class, $session, $logfn ) = @_;

    my $this = bless(
        {
            session => $session,
            logfn   => $logfn
        },
        $class
    );

    return $this;
}

# Shutdown
sub finish {
    my $this = shift;
    $this->{generator} = undef;
    $this->{session}   = undef;
}

# Convert wildcarded comma-separated list to a regex
sub _wildcards2RE {
    my $v = shift;
    $v =~ s/([*?])/.$1/g;
    $v =~ s/\s*,\s*/|/g;
    return qr/$v/;
}

sub publish {
    my ( $this, $params ) = @_;

    # don't add extra markup for topics we're not linking too
    # NEWTOPICLINKSYMBOL LINKTOOLTIPINFO
    $Foswiki::Plugins::SESSION->renderer()->{NEWLINKSYMBOL} = '';

    $this->logInfo( "*Publisher:* ", Foswiki::Func::getWikiName() );
    $this->logInfo( "*Date:* ",      Foswiki::Func::formatTime( time() ) );
    $this->_loadParams($params);

    # Handle =enableplugins=. We simply muddy-boots the foswiki config.
    if ( $this->{opt}->{enableplugins} ) {

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

    $this->{opt}->{publishskin} ||=
      Foswiki::Func::getPreferencesValue('PUBLISHSKIN')
      || 'basic_publish';

    if ( $this->{opt}->{history} ) {
        $this->{historyText} = '';
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

    # Push preference values. Because we use session preferences (preferences
    # that only live as long as the request) these values will not persist.
    # They may also be overridden locally in topics.
    if ( defined $this->{opt}->{preferences} ) {
        _parsePreferences(
            $this->{opt}->{preferences},
            sub {
                my ( $k, $v ) = @_;
                Foswiki::Func::setPreferencesValue( $k, $v );
            }
        );
    }

    # Start by making a total ordering of topics to be published
    my @topics;

    if ( $this->{opt}->{topics} ) {

        # Get a total list of webs (and subwebs)
        my %webs = map { $_ => undef }
          grep { !/^_/ } Foswiki::Func::getListOfWebs();

        my @wild = split( /\s*,\s*/, $this->{opt}->{topics} );

        foreach my $expr (@wild) {
            my $filter = ( $expr =~ s/^-// );

            # Split specification into web and topics
            my ( $w, $t ) = split( /\./, $expr, 2 );
            if ( $w && !$t ) {
                $t = $w;
                $w = '*';
            }

            # Web. means all topics in Web
            # . means all topics in all webs
            # .Fred means all topics called Fred in all webs
            $w = '*' unless length($w);
            $t = '*' unless length($t);

            my $wre = _wildcards2RE($w);
            my $tre = _wildcards2RE($t);
            if ($filter) {

                # Exclude topics matching this RE
                my @filtered;
                while ( my $twt = pop(@topics) ) {
                    ( $w, $t ) = split( /\./, $twt, 2 );
                    unless ( $twt =~ /^$wre\.$tre$/ ) {
                        unshift( @filtered, $twt );
                    }
                }
                @topics = @filtered;
            }
            else {
                foreach my $tw ( grep { /^$wre$/ } sort keys %webs ) {
                    unless ( defined $webs{$tw} ) {
                        $webs{$tw} =
                          [ sort map { "$tw.$_" }
                              Foswiki::Func::getTopicList($tw) ];
                    }
                    push( @topics, grep { /^$wre\.$tre$/ } @{ $webs{$tw} } );
                }
            }
        }
    }
    else {
        # Compatibility; handle =web=, =topiclist=, =inclusions=, =exclusions=
        my $web = $this->{opt}->{web};
        die "'topics' parameter missing" unless $web;

        if ( $this->{opt}->{topiclist} ) {
            my $tl =
              Foswiki::Func::expandCommonVariables( $this->{opt}->{topiclist} );
            @topics = map {
                my ( $w, $t ) =
                  Foswiki::Func::normalizeWebTopicName( $web, $_ );
                "$w.$t"
            } split( /\s*,\s*/, $tl );
        }
        else {
            @topics = map { "$web.$_" } Foswiki::Func::getTopicList($web);
        }

        if ( $this->{opt}->{inclusions} ) {
            my $re = _wildcards2RE( $this->{opt}->{inclusions} );
            @topics = grep { /$re$/ } @topics;
        }

        if ( $this->{opt}->{exclusions} ) {
            my $re = _wildcards2RE( $this->{opt}->{exclusions} );
            @topics = grep { !/$re$/ } @topics;
        }
    }

    # Choose template. Note that $template_TEMPLATE can still override
    # this in specific topics.
    $this->{skin_template} =
      Foswiki::Func::readTemplate( $this->{opt}->{template},
        $this->{opt}->{publishskin} );
    die "Couldn't find skin template $this->{opt}->{template}\n"
      if ( !$this->{skin_template} );

    $this->{copied_resources} = {};

    # Make a map of topic versions for every published web, if
    # 'versions' was given
    $this->{topicVersions} = {};
    if ( $this->{opt}->{versions} ) {
        my %webs;
        foreach my $topic (@topics) {
            my ( $w, $t ) = split( '.', $topic, 2 );
            $webs{$w} = 1;
        }
        foreach my $web ( keys %webs ) {
            my ( $vweb, $vtopic ) =
              Foswiki::Func::normalizeWebTopicName( $web,
                $this->{opt}->{versions} );
            next unless Foswiki::Func::topicExists( $vweb, $vtopic );
            next unless $vweb eq $web;
            my ( $meta, $text ) = Foswiki::Func::readTopic( $vweb, $vtopic );
            $text =
              Foswiki::Func::expandCommonVariables( $text, $vtopic, $vweb,
                $meta );
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
                if ( $line =~ /^\s*\|\s*(.*?)\s*\|\s*(?:\d\.)?(\d+)\s*\|\s*$/ )
                {
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
    }

    $this->{archive} = $this->{generator}->new( $this->{opt}, $this );

    $this->{archive}->getReady();

    # Force static context for all published topics
    Foswiki::Func::getContext()->{static} = 1;

    my $safe = $Foswiki::cfg{ScriptUrlPaths};
    undef $Foswiki::cfg{ScriptUrlPaths};

    # Complete set of topics to be published. May expand if
    # unpublished="follow"
    $this->{publishSet} = { map { $_ => 1 } @topics };

    # Working set of topics waiting to be published. May expand if
    # unpublished="follow"
    $this->{publishList} = \@topics;

    while ( scalar @topics ) {
        my $wt = shift(@topics);
        try {
            $this->_publishTopic( split( /\./, $wt, 2 ) );
        }
        catch Error::Simple with {
            my $e = shift;
            $this->logError( "$wt not published: " . ( $e->{-text} || '' ) );
        };
    }
    $Foswiki::cfg{ScriptUrlPaths} = $safe;

    # Close archive
    my $endpoint = $this->{archive}->close();
    if ( Foswiki::Func::getContext()->{command_line} ) {
        $endpoint = "$Foswiki::cfg{Plugins}{PublishPlugin}{Dir}/$endpoint";
    }
    else {
        my $u = $Foswiki::cfg{Plugins}{PublishPlugin}{URL} . '/' . $endpoint;
        $endpoint = "<a href='$u'>$u</a>";
    }
    $this->logInfo( "*Published to* ", $endpoint );

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
        $this->logInfo( "History saved in ", "<a href='$url'>$url</a>" );
    }
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

sub _log {
    my $this     = shift;
    my $level    = shift;
    my $preamble = shift;

    &{ $this->{logfn} }( $level, @_ );
    $this->{historyText} .=
      join( '', $preamble, @_, ( $preamble ? '%ENDCOLOR%' : '' ), "%BR%\n" )
      if ( $this->{opt}->{history} );
}

sub logInfo {
    my $this = shift;
    $this->_log( 'info', '', @_ );
}

sub logDebug {
    my $this = shift;
    return unless $this->{opt}->{debug};
    $this->_log( 'debug', '', @_ );
}

sub logWarn {
    my $this = shift;
    $this->_log( 'warn', '%ORANGE% *WARNING* ', @_ );
}

sub logError {
    my $this = shift;
    $this->_log( 'error', '%RED% *ERROR* ', @_ );
}

#  Publish one topic from web.
#   * =$topic= - which topic to publish (web.topic)
sub _publishTopic {
    my ( $this, $web, $topic ) = @_;

    return
         if $this->{history}
      && $web   eq $this->{history}->[0]
      && $topic eq $this->{history}->[1];    # never publish this

    if ( $this->{archive}->alreadyPublished( $web, $topic ) ) {
        $this->logInfo("$web.$topic is already up to date");
        return;
    }

    # SMELL: Nasty. Should fix Item13387.
    if ( defined &Foswiki::Plugins::TablePlugin::initialiseWhenRender ) {
        Foswiki::Plugins::TablePlugin::initialiseWhenRender();
    }

    my ( $meta, $text );
    my $publishRev = $this->{topicVersions}->{"$web.$topic"};

    ( $meta, $text ) = Foswiki::Func::readTopic( $web, $topic, $publishRev );
    unless ($publishRev) {
        my $d;
        ( $d, $d, $publishRev, $d ) =
          Foswiki::Func::getRevisionInfo( $web, $topic );
    }

    unless (
        Foswiki::Func::checkAccessPermission(
            "VIEW", Foswiki::Func::getWikiName(),
            $text, $topic, $web
        )
      )
    {
        $this->logError("View access to $web.$topic denied");
        return;
    }

    if ( $this->{opt}->{rexclude} && $text =~ /$this->{opt}->{rexclude}/ ) {
        $this->logInfo("$web.$topic excluded by filter");
        return;
    }

    # clone the current session
    my %old;

    Foswiki::Func::pushTopicContext( $web, $topic );

    # Remove disabled plugins from the context
    foreach my $plugin ( keys( %{ $Foswiki::cfg{Plugins} } ) ) {
        next unless ref( $Foswiki::cfg{Plugins}{$plugin} );
        my $enable = $Foswiki::cfg{Plugins}{$plugin}{Enabled};
        Foswiki::Func::getContext()->{"${plugin}Enabled"} = $enable;
    }

    # re-init enabled plugins
    foreach my $plugin ( %{ $Foswiki::cfg{Plugins} } ) {
        next
          unless ref( $Foswiki::cfg{Plugins}{$plugin} )
          && $Foswiki::cfg{Plugins}{$plugin}{Module}
          && $Foswiki::cfg{Plugins}{$plugin}{Enabled};
        my $module = $Foswiki::cfg{Plugins}{$plugin}{Module};
        my $initfn = $module . '::initPlugin';
        if ( defined &$initfn ) {
            eval {
                no strict 'refs';
                &$initfn(
                    $topic, $web,
                    Foswiki::Func::getWikiName(),
                    $Foswiki::cfg{SystemWebName}
                );
                use strict 'refs';
            };
        }
    }

    # Because of Item5388, we have to re-read the topic to get the
    # right session in the $meta. This could be done by patching the
    # $meta object, but this should be longer-lasting.
    # $meta has to have the right session otherwise $WEB and $TOPIC
    # won't work in %IF statements.
    ( $meta, $text ) = Foswiki::Func::readTopic( $web, $topic, $publishRev );

    $Foswiki::Plugins::SESSION->enterContext( 'can_render_meta', $meta );

    my $tmpl = $this->{skin_template};

    # Allow a local definition of VIEW_TEMPLATE to override the
    # template passed in (unless this is disabled by a global option)
    my $override = Foswiki::Func::getPreferencesValue('VIEW_TEMPLATE');
    if ($override) {
        my $alt_tmpl =
          Foswiki::Func::readTemplate( $override, $this->{opt}->{publishskin},
            $web );
        $this->logInfo("$web.$topic has a VIEW_TEMPLATE '$override'");
        if ( length($alt_tmpl) ) {
            $tmpl = $alt_tmpl;
        }
        else {
            $this->logWarn(
                "The VIEW_TEMPLATE '",
                $override,
                "' is empty for skin ",
                $this->{opt}->{publishskin},
                "- ignoring"
            );
        }
    }

    my ( $revdate, $revuser, $maxrev );
    ( $revdate, $revuser, $maxrev ) = $meta->getRevisionInfo();
    if ( ref($revuser) ) {
        $revuser = $revuser->wikiName();
    }

    # Expand and render the topic text
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

    Foswiki::Func::setPreferencesValue( 'TEXT',     $text );
    Foswiki::Func::setPreferencesValue( 'MAXREV',   $maxrev );
    Foswiki::Func::setPreferencesValue( 'CURRREV',  $publishRev || $maxrev );
    Foswiki::Func::setPreferencesValue( 'REVTITLE', '' );

    # Expand and render the template
    $tmpl = Foswiki::Func::expandCommonVariables( $tmpl, $topic, $web, $meta );

    # Inject the text into the template. The extra \n is required to
    # simulate the way the view script splits up the topic and reassembles
    # it around newlines.
    $text = "\n$text" unless $text =~ /^\n/s;

    # trim spaces at start and end
    $tmpl =~ s/^[[:space:]]+//s;    # trim at start
    $tmpl =~ s/[[:space:]]+$//s;    # trim at end

    $tmpl = Foswiki::Func::renderText( $tmpl, $web, $topic );

    if ( $Foswiki::Plugins::SESSION->can("_renderZones") ) {

        # Foswiki 1.1 up to 2.0
        $tmpl = $Foswiki::Plugins::SESSION->_renderZones($tmpl);
    }
    else {
        # Foswiki 2.1 and later
        $tmpl = $Foswiki::Plugins::SESSION->zones()->_renderZones($tmpl);
    }

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
      s/<a [^>]*\bhref=[^>]*>/$this->_rewriteTag($&, 'href', $web, $topic)/geis;
    $tmpl =~
s/<link [^>]*\bhref=[^>]*>/$this->_rewriteTag($&, 'href', $web, $topic)/geis;
    $tmpl =~
      s/<img [^>]*\bsrc=[^>]*>/$this->_rewriteTag($&, 'src', $web, $topic)/geis;
    $tmpl =~
s/<script [^>]*\bsrc=[^>]*>/$this->_rewriteTag($&, 'src', $web, $topic)/geis;
    $tmpl =~
s/<blockquote [^]*\bcite=[^>]*>/$this->_rewriteTag($&, 'cite', $web, $topic)/geis;
    $tmpl =~
      s/<q [^>]*\bcite=[^>]*>/$this->_rewriteTag($&, 'cite', $web, $topic)/gei;

    # No support for OBJECT, APPLET, INPUT

    $tmpl =~ s/<nop>//g;

    # Archive the resulting HTML.
    my $path = $this->{archive}->addTopic( $web, $topic, $tmpl );
    $this->logInfo("Published =$web.$topic= as =$path= ");

    # Process any uncopied resources
    if ( $this->{opt}->{allattachments} ) {
        my @lst = Foswiki::Func::getAttachmentList( $web, $topic );
        foreach my $att (@lst) {
            $this->_processInternalResource( $web, $topic, $att );
        }
    }

    Foswiki::Func::popTopicContext();
    if ( defined $Foswiki::Plugins::SESSION->{SESSION_TAGS} ) {

        # In 1.0.6 and earlier, have to handle some session tags ourselves
        # because pushTopicContext doesn't do it. **
        foreach my $macro (
            qw(BASEWEB BASETOPIC
            INCLUDINGWEB INCLUDINGTOPIC)
          )
        {
            $Foswiki::Plugins::SESSION->{SESSION_TAGS}{$macro} = $old{$macro};
        }
    }

    $this->logInfo("$web.$topic version $publishRev published");

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
    my $new = $this->_processURL( $attrs{$key}, "$web.$topic" );
    unless ( $new eq $attrs{$key} || $new =~ /^#/ ) {

        #$this->logDebug("Rewrite $new (rel to ",
        #   $this->{archive}->getTopicPath( $web, $topic ).')');
        $new =
          File::Spec->abs2rel( "/$new",
            '/' . $this->{archive}->getTopicPath( $web, $topic ) . "/.." );

        #$this->logDebug("as $new");
    }

    #$this->logDebug("$attrs{$key} = $new");
    $attrs{$key} = $new;

    return
      "<$type " . join( ' ', map { "$_=\"$attrs{$_}\"" } keys %attrs ) . '>';
}

# Rewrite a URL - be it internal or external. Internal URLs that point to
# anything in pub, or to scripts, are always rewritten.
sub _processURL {
    my ( $this, $url, $referrer ) = @_;

    $url = URI->new($url);

    # $url->scheme
    # $url->user
    # $url->password
    # $url->host
    # $url->port
    # $url->epath
    # $url->eparams
    # $url->equery
    # $url->frag

    $this->logDebug( "Processing URL ", $url );

    if ( !defined $url->path() || length( $url->path() ) == 0 ) {

        $this->logDebug("- no path in ");

        # is there a frag?
        if ( $url->can('fragment') && $url->fragment ) {
            $this->logDebug( "- frag " . $url->fragment );
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

        $this->logDebug("Test $url against $match");

        # Some older parsers used to allow the scheme name to be present
        # in the relative URL if it was the same as the base URL
        # scheme. RFC1808 says that this should be avoided, so we assume
        # it's not so, and if there's a scheme, it's absolute.
        if ( $match->can('scheme') && $match->scheme ) {
            if ( $url->can('scheme') ) {
                unless ( _matchPart( $url->scheme, $match->scheme ) ) {
                    $this->logDebug( "- scheme mismatch "
                          . $url->scheme . " and "
                          . $match->scheme );
                    return undef;
                }
            }
            else {
                $this->logDebug("- no scheme on url");
                return undef;
            }
        }
        elsif ( $url->can('scheme') && $url->scheme ) {
            $this->logDebug("- no scheme on match");
            return undef;
        }

        if ( $match->can('host') && $match->host ) {
            if ( $url->can('host') ) {
                unless ( _matchPart( $url->host, $match->host ) ) {
                    $this->logDebug("- host mismatch");
                    return undef;
                }
            }
            else {
                $this->logDebug("- no host on url");
                return undef;
            }
        }
        elsif ( $url->can('host') && $url->host ) {
            $this->logDebug("- no host on match");
            return undef;
        }

        if ( $match->can('port') && length( $match->port ) ) {
            if ( $url->can('port') ) {
                unless ( _matchPart( $url->port, $match->port ) ) {
                    $this->logDebug("- port mismatch");
                    return undef;
                }
            }
            else {
                $this->logDebug("- no port on url");
                return undef;
            }
        }
        elsif ( $url->can('port') && length( $url->port ) ) {
            $this->logDebug("- no port on match");
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
            $this->logDebug("- trim $upath[0] match $mpath[0]");
            shift(@mpath);
            shift(@upath);
        }
        if ( $mpath[0] eq 'WEB' ) {
            $this->logDebug( "- matched " . join( '/', @upath ) );
            return \@upath;
        }
        else {
            $this->logDebug("- no match at $mpath[0]");
            return undef;
        }
    }

    # Is this local?
    unless ( $this->{url_paths} ) {
        $this->{url_paths} = {
            script_rel => URI->new(
                Foswiki::Func::getScriptUrlPath( 'WEB', 'TOPIC', 'SCRIPT' )
            ),
            script_abs => URI->new(
                Foswiki::Func::getScriptUrl( 'WEB', 'TOPIC', 'SCRIPT' )
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

    my ( $type, $is_rel, $upath ) = ( 0, 0 );

    # Match pub first, because some forms of pub link (viewfile) will
    # also match script.
    if ( $upath = _match( 1, $url, $this->{url_paths}->{pub_abs} ) ) {
        $this->logDebug( "- matched pub_abs at " . join( '/', @$upath ) );
        $type = 'pub';
    }
    elsif ( $upath = _match( 0, $url, $this->{url_paths}->{pub_rel} ) ) {
        $this->logDebug( "- matched pub_rel at " . join( '/', @$upath ) );
        $type   = 'pub';
        $is_rel = 1;
    }
    elsif ( $upath = _match( 1, $url, $this->{url_paths}->{script_abs} ) ) {
        $this->logDebug( "- matched script_abs at " . join( '/', @$upath ) );
        $type = 'script';
    }
    elsif ( $upath = _match( 0, $url, $this->{url_paths}->{script_rel} ) ) {
        $this->logDebug( "- matched script_rel at " . join( '/', @$upath ) );
        $type   = 'script';
        $is_rel = 1;
    }

    #$this->logDebug( "- leaving ".join('/',@$upath));

    my $web;
    my $topic;
    my $attachment;
    my $new = $url;

    # Is it a pub resource? With no associated query?
    if ( $type eq 'pub' && !$url->query() ) {
        $attachment = pop(@$upath) if scalar(@$upath);
        $topic      = pop(@$upath) if scalar(@$upath);
        $web = join( '/', @$upath );
        $new = $this->_processInternalResource( $web, $topic, $attachment );
    }
    elsif ( $type eq 'script' ) {

        # return a link to the topic in the archive. This is named
        # for the template being generated.
        my $rewrite = 1;
        $topic = pop(@$upath) if scalar(@$upath);
        $web = join( '/', @$upath );

        unless ( $this->{publishSet}->{"$web.$topic"} ) {
            if ( $this->{opt}->{unpublished} eq 'rewrite' ) {
                $this->logWarn("$web.$topic is not in the publish set");
            }
            elsif ( $this->{opt}->{unpublished} eq 'follow' ) {
                $this->logWarn(
"Adding $web.$topic to the publish set, referred to from $referrer"
                );
                push( @{ $this->{publishList} }, "$web.$topic" );
                $this->{publishSet}->{"$web.$topic"} = $referrer;
            }
            elsif ( $this->{opt}->{unpublished} eq '404' ) {
                $rewrite = 0;
                $new     = "broken link to $web.$topic";
            }
            elsif ( $this->{opt}->{unpublished} eq 'ignore' ) {
                $this->logWarn("Ignoring link to unpublished $web.$topic");
                $rewrite = 0;
            }
        }
        if ($rewrite) {
            $new = $this->{archive}->getTopicPath( $web, $topic );
        }
    }
    else {
        # Otherwise it's either a real external resource, or a
        # pub resource with a query. In either case we have to
        # process it as an external resource
        $this->logDebug("- external resource");

        if ( $type eq 'pub' && $is_rel ) {

            # Relative URLs with queries can't be retrieved using
            # Foswiki::Func::getExternalResource; but it works if
            # we convert to an absolute URL, which we can do safely.
            $attachment = pop(@$upath) if scalar(@$upath);
            $topic      = pop(@$upath) if scalar(@$upath);
            $web = join( '/', @$upath );
            $url = URI->new(
                Foswiki::Func::getPubUrlPath( $web, $topic, $attachment,
                    absolute => 1 )
                  . '?'
                  . $url->query()
            );
        }

        $new = $this->_processExternalResource($url);
    }

    $this->logDebug("-mapped $url to $new");
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
    my $path =
      $this->{archive}->addAttachment( $web, $topic, $attachment, $data );
    $this->logInfo("Published =$web.$topic:$attachment= as =$path= ");
    $this->{copied_resources}->{$rsrc} = $path;

    return $path;
}

sub _processExternalResource {
    my ( $this, $url ) = @_;

    return $url unless $this->{opt}->{copyexternal};

    return $this->{copied_resources}->{$url}
      if ( $this->{copied_resources}->{$url} );

    my $response = Foswiki::Func::getExternalResource($url);
    if ( $response->is_error() ) {
        $this->logWarn( "Could not get =$url=, ", $response->message() );
        return $url;
    }

    my $ext;
    if ( $url =~ /(\.\w+)(\?|#|$)/ ) {
        $ext = $1;
    }
    my $path = $this->{archive}->addResource( $response->content(), $ext );

    $this->logInfo("Published =$url= as =$path= ");
    $this->{copied_resources}->{$url} = $path;

    return $path;
}

1;
__END__
#
# Copyright (C) 2001 Motorola
# Copyright (C) 2001-2007 Sven Dowideit, svenud@ozemail.com.au
# Copyright (C) 2002, Eric Scouten
# Copyright (C) 2005-2018 Crawford Currie, http://c-dot.co.uk
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
