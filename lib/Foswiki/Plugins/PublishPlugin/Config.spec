#---+ Extensions
#---++ Publish Plugin
# **PATH**
# File path to the directory where published files will be generated.
# you will normally want this to be visible via a URL, so a subdirectory
# of the pub directory is a good choice.
$Foswiki::cfg{PublishPlugin}{Dir} = '$Foswiki::cfg{PubDir}/publish/';
# **URL**
# URL path of the directory you defined above.
# <p><strong>WARNING!</strong> Anything published is no longer under the
# control of Foswiki access controls, and anyone who has access to the
# published file can see the contents of the web. You may need to
# take precautions to prevent accidental leakage of confidential information
# by restricting access to this URL, for example in the Apache configuration.
$Foswiki::cfg{PublishPlugin}{URL} = '$Foswiki::cfg{DefaultUrlHost}$Foswiki::cfg{PubUrlPath}/publish/';
# **COMMAND**
# Command-line for the PDF generator program.
# <ul><li>%FILES|F% will expand to the list of input files</li>
# <li>%FILE|F% will expand to the output file name </li>
# <li>%EXTRAS|U% will expand to any additional generator options entered
# in the publishing form.</li></ul>
$Foswiki::cfg{PublishPlugin}{PDFCmd} = 'htmldoc --webpage --links --linkstyle plain --outfile %FILE|F% %EXTRAS|U% %FILES|F%';
# **BOOLEAN EXPERT**
# May be enabled to prevent slowdown and unnecessary memory use if templates are 
# frequently reloaded, for some 1.1.x versions of Foswiki.
# This is NOT a likely condition, and it is only known to manifest
# when there are additional problems in the data being published.
# However, if there is something wrong in the publishing configuration,
# then it is possible for many pages to have at least one inline alert,
# and Foswiki::inlineAlert reloads its template each time it is called
# (at least, it does for some versions of Foswiki).
$Foswiki::cfg{PublishPlugin}{PurgeTemplates} = 0;
