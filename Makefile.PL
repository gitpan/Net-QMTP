use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
# $Id: Makefile.PL,v 1.3 2003/01/29 18:04:36 james Exp $
WriteMakefile(
    'NAME'	=> 'Net::QMTP',
    'VERSION_FROM' => 'QMTP.pm', # finds $VERSION
    'dist'	=> { POSTOP=>'$(CHMOD) 444 $(DISTVNAME).tar$(SUFFIX)' },
);
