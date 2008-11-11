#!/usr/bin/perl
#
# Makefile.PL -- Generate Makefile
# list files in 'MANIFEST'

use ExtUtils::MakeMaker;

WriteMakefile (	NAME => 'perl-dyndns',
		AUTHOR => 'Jari Aalto <jari.aalto@cante.net>',
		LICENSE => 'GPL v2 or (at your option) later',
		ABSTRACT => 'A Perl Dynamic DNS (DDNS) update client',
		PREREQ_PM => {'Getopt::Long' => 2.00},
		# VERSION => '2008.1111',
		VERSION_FROM => 'bin/dyndns.pl',
		EXE_FILES => [qw(bin/dyndns.pl)]
		);

package MY;
sub postamble
{
    return <<'EOF'


EOF
}

# End of file
