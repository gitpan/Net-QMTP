use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
# $Id: Makefile.PL,v 1.2 2003/01/27 15:33:48 james Exp $
WriteMakefile(
    'NAME'	=> 'Net::QMTP',
    'VERSION_FROM' => 'QMTP.pm', # finds $VERSION
);
