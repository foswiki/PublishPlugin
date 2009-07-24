# See bottom of file for license and copyright details
package Foswiki::Plugins::PublishPlugin::Publisher;

use strict;

use Foswiki;
use Foswiki::Func;
use Error ':try';
use Assert;

my %parameters = (
    history          => { default => 'PublishPluginHistory',
                          validator => \&_validateTopic },
    inclusions       => { default  => '.*', validator => \&_wildcard2RE },
    exclusions       => { default  => '', validator => \&_wildcard2RE },
    topicsearch      => { default => '' },
    filter           => { renamed => 'topicsearch' },
    publishskin      => { },
    versions         => { },
    debug            => { default => 0 },
    templates        => { default => 'view', validator => \&_validateList },
    templatelocation => { validator => \&_validateDir },
    format           => { default => 'file', validator => \&_validateWord },
    relativedir      => { default => '', validator => \&_validateRelPath },
    instance         => { renamed => 'relativedir' },
    genopt           => { renamed => 'extras' },
    skin             => { renamed => 'publishskin' },
    enableplugins    => { validator => \&_validateList },
);

sub _wildcard2RE {
    my $v = shift;
    $v =~ s/([*?])/.$1/g;
    $v =~ s/,/|/g;
    return $v;
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
    if ($v =~ /^([\w, ]*)$/ ) {
        return $1;
    }
    my $k = shift;
    die "Invalid $k: '$v'";
}

sub _validateTopic {
    my $v = shift;
    unless (defined &Foswiki::Func::isValidTopicName) {
        # Old code doesn't have this. Caveat emptor.
        return Foswiki::Sandbox::untaintUnchecked($v);
    }
    if (Foswiki::Func::isValidTopicName($v, 1)) {
        return Foswiki::Sandbox::untaintUnchecked($v);
    }
    my $k = shift;
    die "Invalid $k: '$v'";
}

sub _validateWord {
    my $v = shift;
    if ($v =~ /^(\w+)$/ ) {
        return $1;
    }
    my $k = shift;
    die "Invalid $k: '$v'";
}

sub _validateRelPath {
    my $v = shift;
    $v .= '/';
    $v =~ s#//+#/#;
    $v =~ s#^/##;
    if ($v =~ m#^(.*)$# ) {
        return $1;
    }
    my $k = shift;
    die "Invalid $k: '$v'";
}

sub new {
    my ( $class, $session ) = @_;

    my $this = bless(
        {
            session         => $session,
            templatesWanted => 'view',

            # used to prefix alternate template renderings
            templateLocation => '',

            # this records which templates (e.g. view, viewprint, viuehandheld,
            # etc) have been referred to and thus should be generated.
            templatesReferenced => {},
        },
        $class
    );
    my $query = Foswiki::Func::getCgiQuery();
    if ( $query && $query->param('configtopic') ) {
        $this->{configtopic} = $query->param('configtopic');
        $query->delete('configtopic');
        $this->_configureFromTopic();
    }
    elsif ($query) {
        $this->_configureFromQuery($query);
    }
    foreach my $p ( keys %parameters ) {
        next if defined $this->{$p};
        $this->{$p} = $parameters{$p}->{default} || '';
    }
    $this->{publishskin} ||=
      Foswiki::Func::getPreferencesValue('PUBLISHSKIN') || 'basic_publish';
    return $this;
}

sub finish {
    my $this = shift;
    $this->{session} = undef;
}

sub _setArg {
    my ($this, $k, $v) = @_;
    $k = $parameters{$k}->{renamed}
      if defined $parameters{$k}->{renamed};
    if (defined $parameters{$k}->{validator}) {
        $this->{$k} = &{$parameters{$k}->{validator}}($v, $k);
    } else {
        $this->{$k} = $v;
    }
}

sub _configureFromTopic {
    my ($this) = @_;

    # Parameters are defined in config topic
    my ( $cw, $ct ) = Foswiki::Func::normalizeWebTopicName(
        $this->{web}, $this->{configtopic} );
    unless ( Foswiki::Func::topicExists( $cw, $ct ) ) {
        die "Specified configuration topic $cw.$ct does not exist!\n";
    }
    # Untaint verified web and topic names
    $cw = Foswiki::Sandbox::untaintUnchecked($cw);
    $ct = Foswiki::Sandbox::untaintUnchecked($ct);
    my ( $cfgm, $cfgt ) = Foswiki::Func::readTopic( $cw, $ct );
    unless (
        Foswiki::Func::checkAccessPermission(
            "VIEW", $this->{publisher}, $cfgt, $ct, $cw
        )
      )
    {
        die "Access to $cw.$ct denied";
    }

    $cfgt =
      Foswiki::Func::expandCommonVariables( $cfgt, $this->{configtopic},
        $this->{web}, $cfgm );

    # SMELL: common preferences parser?
    foreach my $line ( split( /\r?\n/, $cfgt ) ) {
        next
          unless $line =~
              /^\s+\*\s+Set\s+(?:PUBLISH_)?([A-Z]+)\s*=\s*(.*?)\s*$/;

        my $k = lc($1);
        my $v = $2;

        if (defined $parameters{$k}) {
            $this->_setArg($k, $v);
        }
    }
}

sub _configureFromQuery {
    my ( $this, $query ) = @_;

    # Parameters are defined in the query
    foreach my $k (keys %parameters) {
        if ( defined( $query->param($k) ) ) {
            my $v = $query->param($k);
            $this->_setArg($k, $v);
            $query->delete( $k );
        }
    }

    # 'compress' undocumented but retained for compatibility
    if ( defined $query->param('compress') ) {
        my $v = $query->param('compress');
        if ( $v =~ /(\w+)/ ) {
            $this->{format} = $1;
        }
    }
}

sub publishWeb {
    my ( $this, $web ) = @_;

    $this->{publisher} = Foswiki::Func::getWikiName();
    $this->{web}       = $web;

    #don't add extra markup for topics we're not linking too
    # NEWTOPICLINKSYMBOL LINKTOOLTIPINFO
    if ( defined $Foswiki::Plugins::SESSION->{renderer} ) {
        $Foswiki::Plugins::SESSION->{renderer}->{NEWLINKSYMBOL} = '';
    }
    else {
        $Foswiki::Plugins::SESSION->renderer()->{NEWLINKSYMBOL} = '';
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
        ( $header, $footer ) = $this->_getPageTemplate();
    }

    my ( $hw, $ht ) =
      Foswiki::Func::normalizeWebTopicName( $this->{web},
        $this->{history} );
    unless (
        Foswiki::Func::checkAccessPermission(
            'CHANGE', Foswiki::Func::getWikiName(),
            undef, $ht, $hw
        )
      )
    {
        $this->logError(<<TEXT, $footer);
Can't publish because $this->{publisher} can't CHANGE
$hw.$ht.
This topic must be editable by the user doing the publishing.
TEXT
        return;
    }
    $this->{historyWeb}   = $hw;
    $this->{history} = $ht;

    # Disable unwanted plugins
    my $enabledPlugins  = '';
    my $disabledPlugins = '';
    my @pluginsToEnable;
    if ( $this->{enableplugins} ) {
        @pluginsToEnable = split( /[, ]+/, $this->{enableplugins} );
    }
    foreach my $plugin ( keys( %{ $Foswiki::cfg{Plugins} } ) ) {
        next unless ref( $Foswiki::cfg{Plugins}{$plugin} ) eq 'HASH';
        my $enable = $Foswiki::cfg{Plugins}{$plugin}{Enabled};
        if ( scalar(@pluginsToEnable) > 0 ) {
            $enable = grep( /$plugin/, @pluginsToEnable );
            $Foswiki::cfg{Plugins}{$plugin}{Enabled} = $enable;
        }
        $enabledPlugins .= ', ' . $plugin if ($enable);
        $disabledPlugins .= ', ' . $plugin unless ($enable);
    }

    $this->logInfo( "Publisher",         $this->{publisher} );
    $this->logInfo( "Date",              Foswiki::Func::formatTime( time() ) );
    $this->logInfo( "Dir",               "$Foswiki::cfg{PublishPlugin}{Dir}$this->{relativedir}" );
    $this->logInfo( "URL",               "$Foswiki::cfg{PublishPlugin}{URL}$this->{relativedir}" );
    $this->logInfo( "Web",               $this->{web} );
    $this->logInfo( "Versions topic",    $this->{versions} )
      if $this->{versions};
    $this->logInfo( "Content Generator", $this->{format} );
    $this->logInfo( "Config topic",      $this->{configtopic} )
      if $this->{configtopic};
    $this->logInfo( "Skin",              $this->{publishskin} );
    $this->logInfo( "Inclusions",        $this->{inclusions} );
    $this->logInfo( "Exclusions",        $this->{exclusions} );
    $this->logInfo( "Content Filter",    $this->{topicsearch} );
    $this->logInfo( "Generator Options", $this->{extras} );
    $this->logInfo( "Enabled Plugins",   $enabledPlugins );
    $this->logInfo( "Disabled Plugins",  $disabledPlugins );

    if ( $this->{versions} ) {
        $this->{topicVersions} = {};
        my ( $vweb, $vtopic ) =
          Foswiki::Func::normalizeWebTopicName( $web, $this->{versions} );
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

    my @templatesWanted = split( /[, ]+/, $this->{templates} );

    foreach my $template (@templatesWanted) {
        next unless $template;
        $this->{templatesReferenced}->{$template} = 1;
        my $dir =
          "$Foswiki::cfg{PublishPlugin}{Dir}$this->{relativedir}"
            . $this->_dirForTemplate($template);

        File::Path::mkpath($dir);

        my $generator =
          'Foswiki::Plugins::PublishPlugin::' . $this->{format};
        eval 'use ' . $generator;
        unless ($@) {
            eval {
                $this->{archive} =
                  $generator->new( $dir, $this->{web}, $this->{extras}, $this,
                    Foswiki::Func::getCgiQuery() );
            };
        }
        if ( $@ || ( !$this->{archive} ) ) {
            $this->logError(<<ERROR, $footer);
Failed to initialise '$this->{format}' ($generator) generator:
<pre>$@</pre>
ERROR
            return;
        }
        $this->publishUsingTemplate($template);

        my $landed = $this->{archive}->close();

        $this->logInfo( "Published To", <<LINK);
<a href="$Foswiki::cfg{PublishPlugin}{URL}$this->{relativedir}$landed">$landed</a>
LINK
    }

    # check the templates referenced, and that everything referenced
    # has been generated.
    my @templatesReferenced = sort keys %{ $this->{templatesReferenced} };
    @templatesWanted = sort @templatesWanted;

    my @difference = arrayDiff( \@templatesReferenced, \@templatesWanted );
    if ( $#difference > 0 ) {
        $this->logInfo( "Templates Used", join( ",", @templatesReferenced ) );
        $this->logInfo( "Templates Specified", join( ",", @templatesWanted ) );
        $this->logWarn(<<BLAH);
There is a difference between the templates you specified and what you
needed. Consider changing the TEMPLATES setting so it has all Templates
Used.
BLAH
    }

    my ( $meta, $text ) =
      Foswiki::Func::readTopic( $this->{historyWeb}, $this->{history} );
    $text =~ s/(^|\n)---\+ Last Published\n.*$//s;
    Foswiki::Func::saveTopic(
        $this->{historyWeb}, $this->{history}, $meta,
        "$text---+ Last Published\n$this->{historyText}\n",
        { minor => 1, forcenewrevision => 1 }
    );
    my $url =
      Foswiki::Func::getScriptUrl( $this->{historyWeb}, $this->{history},
        'view' );
    $this->logInfo( "History saved in", "<a href='$url'>$url</a>" );

    Foswiki::Plugins::PublishPlugin::_display($footer);
}

# get a template for presenting output / interacting (*not* used
# for published content)
sub _getPageTemplate {
    my ($this) = @_;

    my $query = Foswiki::Func::getCgiQuery();
    my $topic = $query->param('publishtopic') || $this->{session}->{topicName};
    my $tmpl  = Foswiki::Func::readTemplate('view');

    $tmpl =~ s/%META{.*?}%//g;
    for my $tag qw( REVTITLE REVARG REVISIONS MAXREV CURRREV ) {
        $tmpl =~ s/%$tag%//g;
    }
    my ( $header, $footer ) = split( /%TEXT%/, $tmpl );
    $header =
      Foswiki::Func::expandCommonVariables( $header, $topic, $this->{web} );
    $header = Foswiki::Func::renderText( $header, $this->{web} );
    $header =~ s/<nop>//go;
    Foswiki::Func::writeHeader();
    Foswiki::Plugins::PublishPlugin::_display $header;

    $footer =
      Foswiki::Func::expandCommonVariables( $footer, $topic, $this->{web} );
    $footer = Foswiki::Func::renderText( $footer, $this->{web} );
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
    Foswiki::Plugins::PublishPlugin::_display( CGI::b("$header:&nbsp;"),
        $body, CGI::br() );
    $this->{historyText} .= "<b> $header </b>$body%BR%\n";
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

#  Publish the contents of one web using the given template (e.g. view)
sub publishUsingTemplate {
    my ( $this, $template ) = @_;

    # Get list of topics from this web.
    my @topics = Foswiki::Func::getTopicList( $this->{web} );

    # Choose template. Note that $template_TEMPLATE can still override
    # this in specific topics.
    my $tmpl = Foswiki::Func::readTemplate( $template, $this->{publishskin} );
    die "Couldn't find template\n" if ( !$tmpl );
    my $filetype = _filetypeForTemplate($template);

    # Attempt to render each included page.
    my %copied;
    foreach my $topic (@topics) {
        next if $topic eq $this->{history};    # never publish this
        try {
            my $dispo = '';
            if ( $this->{inclusions} && $topic !~ /^($this->{inclusions})$/ ) {
                $dispo = 'not included';
            }
            elsif ($this->{exclusions}
                && $topic =~ /^($this->{exclusions})$/ )
            {
                $dispo = 'excluded';
            }
            else {
                my $rev =
                  $this->publishTopic( $topic, $filetype, $template, $tmpl,
                    \%copied )
                  || '0';
                $dispo = "Rev $rev published";
                $topic = '<a href="'.Foswiki::Func::getScriptUrl(
                    $this->{web}, $topic, 'view', rev=>$rev).'">'
                      .$topic.'</a>';
            }
            $this->logInfo( $topic, $dispo );
        }
        catch Error::Simple with {
            my $e = shift;
            $this->logError( "$topic not published: " . ( $e->{-text} || '' ) );
        };
    }
}

#  Publish one topic from web.
#   * =$this->{web}= - which web to publish
#   * =$topic= - which topic to publish
#   * =$filetype= - which filetype (pdf, html) to use as a suffix on the file generated

#   * =\%copied= - map of copied resources to new locations
sub publishTopic {
    my ( $this, $topic, $filetype, $template, $tmpl, $copied ) = @_;

    # Read topic data.

    my ( $meta, $text );
    my $publishedRev =
        $this->{topicVersions}
      ? $this->{topicVersions}->{"$this->{web}.$topic"}
      : undef;

    ( $meta, $text ) =
      Foswiki::Func::readTopic( $this->{web}, $topic, $publishedRev );
    unless ($publishedRev) {
        my $d;
        ( $d, $d, $publishedRev, $d ) =
          Foswiki::Func::getRevisionInfo( $this->{web}, $topic );
    }

    unless (
        Foswiki::Func::checkAccessPermission(
            "VIEW", $this->{publisher}, $text, $topic, $this->{web}
        )
      )
    {
        $this->logError("View access to $this->{web}.$topic denied");
        return;
    }

    if ( $this->{topicsearch} && $text =~ /$this->{topicsearch}/ ) {
        $this->logInfo( $topic, "excluded by filter" );
        return;
    }

    # clone the current session
    my %old;
    my $query      = Foswiki::Func::getCgiQuery();
    $query->param( 'topic', "$this->{web}.$topic" );

    if ( defined &Foswiki::Func::pushTopicContext ) {
        # In 1.0.6 and earlier, have to handle some session tags ourselves
        # because pushTopicContext doesn't do it. **
        if (defined $Foswiki::Plugins::SESSION->{SESSION_TAGS}) {
            foreach my $macro qw(BASEWEB BASETOPIC
                                 INCLUDINGWEB INCLUDINGTOPIC) {
                $old{$macro} = Foswiki::Func::getPreferencesValue($macro);
            }
        }
        Foswiki::Func::pushTopicContext( $this->{web}, $topic );
        if (defined $Foswiki::Plugins::SESSION->{SESSION_TAGS}) {
            # see ** above
            my $stags = $Foswiki::Plugins::SESSION->{SESSION_TAGS};
            $stags->{BASEWEB} = $this->{web};
            $stags->{BASETOPIC} = $topic;
            $stags->{INCLUDINGWEB} = $this->{web};
            $stags->{INCLUDINGTOPIC} = $topic;
        }
    }
    else {

        # Create a new session so that the contexts are correct. This is
        # really, really inefficient, but is essential to maintain correct
        # prefs if we don't have a modern Func
        $old{SESSION} = $Foswiki::Plugins::SESSION;
        $Foswiki::Plugins::SESSION = new Foswiki( $this->{publisher}, $query );
    }

    # Because of Item5388, we have to re-read the topic to get the
    # right session in the $meta. This could be done by patching the
    # $meta object, but this should be longer-lasting.
    # $meta has to have the right session otherwise $WEB and $TOPIC
    # won't work in %IF statements.
    ( $meta, $text ) =
      Foswiki::Func::readTopic( $this->{web}, $topic, $publishedRev );

    $Foswiki::Plugins::SESSION->enterContext( 'can_render_meta', $meta );

    # Allow a local definition of VIEW_TEMPLATE to override the
    # template passed in (unless this is disabled by a global option)
    my $override = Foswiki::Func::getPreferencesValue('VIEW_TEMPLATE');
    if ($override) {
        $tmpl =
          Foswiki::Func::readTemplate( $override, $this->{publishskin},
            $this->{web} );
        $this->logInfo( $topic, "has a VIEW_TEMPLATE '$override'" );
    }

    my ( $revdate, $revuser, $maxrev );
    ( $revdate, $revuser, $maxrev ) = $meta->getRevisionInfo();
    if ( ref($revuser) ) {
        $revuser = $revuser->wikiName();
    }

    # Expand and render the topic text
    $text =
      Foswiki::Func::expandCommonVariables( $text, $topic, $this->{web},
        $meta );

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
    $tmpl =
      Foswiki::Func::expandCommonVariables( $tmpl, $topic, $this->{web},
        $meta );

    # Inject the text into the template. The extra \n is required to
    # simulate the way the view script splits up the topic and reassembles
    # it around newlines.
    $text = "\n$text" unless $text =~ /^\n/s;
    $tmpl =~ s/%TEXT%/$text/g;

    # legacy
    $tmpl =~ s/<nopublish>.*?<\/nopublish>//gs;

    $tmpl =~ s/.*?<\/nopublish>//gs;
    $tmpl =~ s/%MAXREV%/$maxrev/g;
    $tmpl =~ s/%CURRREV%/$maxrev/g;
    $tmpl =~ s/%REVTITLE%//g;
    $tmpl = Foswiki::Func::renderText( $tmpl, $this->{web} );

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
    $tmpl =~ s!(['"])($Foswiki::cfg{DefaultUrlHost}|https?://$hs)?$pub/(.*?)\1!
      $1.$this->_copyResource($3, $copied).$1!ge;

    my $ilt;

    # Modify local links relative to server base
    $ilt =
      $Foswiki::Plugins::SESSION->getScriptUrl( 0, 'view', 'NOISE', 'NOISE' );
    $ilt  =~ s!/NOISE/NOISE.*$!!;
    $tmpl =~ s!href=(["'])$ilt/(.*?)\1!"href=$1".$this->_topicURL($2).$1!ge;

    # Modify absolute topic links.
    $ilt =
      $Foswiki::Plugins::SESSION->getScriptUrl( 1, 'view', 'NOISE', 'NOISE' );
    $ilt  =~ s!/NOISE/NOISE.*$!!;
    $tmpl =~ s!href=(["'])$ilt/(.*?)\1!"href=$1".$this->_topicURL($2).$1!ge;

    # Modify topic-relative TOC links to strip out parameters (but not anchor)
    $tmpl =~ s!href=(["'])\?.*?(\1|#)!href=$1$2!g;

    # replace any external template references
    $tmpl =~ s!href=["'](.*?)\?template=(\w*)(.*?)["']!
      $this->_rewriteTemplateReferences($tmpl, $1, $2, $3)!e;

    my $extras = 0;

    # Handle image tags using absolute URLs not otherwise satisfied
    $tmpl =~ s!(<img\s+.*?\bsrc=)(["'])(.*?)\2(.*?>)!
      $1.$2.$this->_handleURL($3,\$extras).$2.$4!ge;

    $tmpl =~ s/<nop>//g;

    # Write the resulting HTML.
    $this->{archive}->addString( $tmpl, $topic . $filetype );

    if ( defined &Foswiki::Func::popTopicContext ) {
        Foswiki::Func::popTopicContext( );
        if (defined $Foswiki::Plugins::SESSION->{SESSION_TAGS}) {
            # In 1.0.6 and earlier, have to handle some session tags ourselves
            # because pushTopicContext doesn't do it. **
            foreach my $macro qw(BASEWEB BASETOPIC
                                 INCLUDINGWEB INCLUDINGTOPIC) {
                $Foswiki::Plugins::SESSION->{SESSION_TAGS}{$macro} =
                  $old{$macro};
            }
        }

    } else {
        $Foswiki::Plugins::SESSION = $old{SESSION};    # restore session
    }

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

    my $newLink =
        $Foswiki::cfg{PublishPlugin}{URL}
      . $this->_dirForTemplate($template)
      . $this->{web} . '/'
      . $topic
      . _filetypeForTemplate($template);
    $this->{templatesReferenced}->{$template} = 1;
    return "href='$newLink'";
}

# Where alternative templates (e.g. viewprint) renderings end up
# This gets appended onto puburl and pubdir
# The web is prefixed before this.
# Do not prepend with a /
sub _dirForTemplate {
    my ( $this, $template ) = @_;
    return '' if ( $template eq 'view' );
    return $template unless $this->{templateLocation};
    return "$this->{templateLocation}/$template/";
}

# SMELL this needs to be table driven
sub _filetypeForTemplate {
    my ($template) = @_;
    return '.pdf' if ( $template eq 'viewpdf' );
    return '.html';
}

#  Copy a resource (image, style sheet, etc.) from pub/%WEB% to
#   static HTML's rsrc directory.
#   * =$this->{web}= - name of web
#   * =$rsrcName= - name of resource (relative to pub/%WEB%)
#   * =\%copied= - map of copied resources to new locations
sub _copyResource {
    my ( $this, $srcName, $copied ) = @_;
    my $rsrcName = $srcName;
    # Trim the resource name, as they can sometimes pick up whitespaces
    $rsrcName =~ /^\s*(.*?)\s*$/;
    $rsrcName = $1;

    # SMELL WARNING (Martin Cleaver)
    # This is covers up a case such as where rsrcname comes through like
    # configtopic=PublishTestWeb/WebPreferences/favicon.ico
    # this should be just WebPreferences/favicon.ico
    # I've searched for hours and so here's a workaround
    if ( $rsrcName =~ m/configtopic/ ) {
        $this->logError("rsrcName '$rsrcName' contains literal 'configtopic'");
        $rsrcName =~ s!.*?/(.*)!$this->{web}/$1!;
        $this->logError("--- FIXED UP to $rsrcName");
    }

    # See if we've already copied this resource.
    unless ( exists $copied->{$rsrcName} ) {

        # Nope, it's new. Gotta copy it to new location.
        # Split resource name into path (relative to pub/%WEB%) and leaf name.
        my $file = $rsrcName;
        $file =~ s(^(.*)\/)()o;
        my $path = "";
        if ( $rsrcName =~ "/" ) {
            $path = $rsrcName;
            $path =~ s(\/[^\/]*$)()o;    # path, excluding the basename
        }

        # Copy resource to rsrc directory.
        my $pubDir = Foswiki::Func::getPubDir();
        my $src = "$pubDir/$rsrcName";
        if ( -r "$pubDir/$rsrcName" ) {
            $this->{archive}->addDirectory("rsrc");
            $this->{archive}->addDirectory("rsrc/$path");
            my $dest = "rsrc/$path/$file";
            $dest =~ s!//!/!g;
            if ( -d $src) {
                $this->{archive}->addDirectory( $src, $dest );
            } else {
                $this->{archive}->addFile( $src, $dest );
            }

            # Record copy so we don't duplicate it later.
            $copied->{$rsrcName} = $dest;
        }
        else {
            $this->logError("$src is not readable");
        }

        # check css for additional resources, ie, url()
        if ( $rsrcName =~ /\.css$/ ) {
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
                    $this->_copyResource( $resource, $copied );
                }
            }
        }
    }
    return $copied->{$rsrcName} if $copied->{$rsrcName};
    $this->logError("MISSING RESOURCE $rsrcName");
    return "MISSING RESOURCE $rsrcName";
}

sub _topicURL {
    my ( $this, $path ) = @_;
    my $extra = '';

    if ( $path && $path =~ s/([#\?].*)$// ) {
        $extra = $1;

        # no point in passing on script params; we are publishing
        # to static HTML.
        $extra =~ s/\?.*?(#|$)/$1/;
    }

    $path ||= $Foswiki::cfg{HomeTopicName};
    $path .= $Foswiki::cfg{HomeTopicName} if $path =~ /\/$/;

    # Normalise
    $this->{web} = join( '/', split( /[\/\.]+/, $this->{web} ) );
    $path = join( '/', split( /[\/\.]+/, $path ) );

    # make a path relative to the web
    $path = File::Spec->abs2rel( $path, $this->{web} );
    $path .= '.html';

    return $path . $extra;
}

sub _handleURL {
    my ( $this, $src, $extras ) = @_;

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
        if ($Foswiki::Plugins::SESSION->{net}->can('_getURLUsingLWP')) {
            $data =
              $Foswiki::Plugins::SESSION->{net}
                ->getUrl( $protocol, $host, $port, $path );
        } else {
            $data =
              $Foswiki::Plugins::SESSION->{net}
                ->getUrl( $host, $port, $path );
        }
    }

    # Note: no extension; rely on file format.
    # Images are pretty good that way.
    my $file = '___extra' . $$extras++;
    $this->{archive}->addDirectory("rsrc");
    $this->{archive}->addString( $data, "rsrc/$file" );

    return 'rsrc/' . $file;
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

1;
__END__
#
# Copyright (C) 2001 Motorola
# Copyright (C) 2001-2007 Sven Dowideit, svenud@ozemail.com.au
# Copyright (C) 2002, Eric Scouten
# Copyright (C) 2005-2008 Crawford Currie, http://c-dot.co.uk
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
# Removal of this notice in this or derivatives is forbidden.
