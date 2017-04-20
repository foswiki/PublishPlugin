#---+ Extensions
#---++ Publish Plugin
# **PATH**
# File path to the directory where published files will be generated.
# you will normally want this to be visible via a URL, so a subdirectory
# of the pub directory is a good choice.
$Foswiki::cfg{Plugins}{PublishPlugin}{Dir} = '$Foswiki::cfg{PubDir}/publish/';
# **URL**
# URL path of the directory you defined above.
# <p><strong>WARNING!</strong> Anything published is no longer under the
# control of Foswiki access controls, and anyone who has access to the
# published file can see the contents of the web. You may need to
# take precautions to prevent accidental leakage of confidential information
# by restricting access to this URL, for example in the Apache configuration.
$Foswiki::cfg{Plugins>{PublishPlugin}{URL} = '$Foswiki::cfg{DefaultUrlHost}$Foswiki::cfg{PubUrlPath}/publish/';
# **COMMAND**
# Command-line for the PDF generator program.
# <ul><li>%FILES|F% will expand to the list of input files</li>
# <li>%FILE|F% will expand to the output file name </li>
# <li>%EXTRAS|U% will expand to any additional generator options entered
# in the publishing form.</li></ul>
$Foswiki::cfg{Plugins}{PublishPlugin}{PDFCmd} = 'htmldoc --webpage --links --linkstyle plain --outfile %FILE|F% %EXTRAS|U% %FILES|F%';

