#!/usr/bin/perl
#
#   Copyright information
#
#	Copyright (C) 2003-2008 Jari Aalto
#
#   License
#
#	This program is free software; you can redistribute it and/or
#	modify it under the terms of the GNU General Public License as
#	published by the Free Software Foundation; either version 2 of the
#	License, or (at your option) any later version
#
#	This program is distributed in the hope that it will be useful, but
#	WITHOUT ANY WARRANTY; without even the implied warranty of
#	MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
#	General Public License for more details at
#	Visit <http://www.gnu.org/copyleft/gpl.html>.
#
#   Description
#
#	run 'perl *.PL' to generate Makefile

use ExtUtils::MakeMaker;

WriteMakefile (	NAME => 'perl-dyndns',
		AUTHOR => 'Jari Aalto <jari.aalto@cante.net>',
		LICENSE => 'GPL v2 or (at your option) later',
		ABSTRACT => 'A Perl Dynamic DNS (DDNS) update client',
		# PREREQ_PM => {'Getopt::Long' => 2.00},
		# VERSION => '2008.1111',
		MAN1EXT => 1,
		VERSION_FROM => 'bin/dyndns.pl',
		EXE_FILES => [qw(bin/dyndns.pl)]
		);

package MY;

# Install without the "*.pl" extension
# See: perldoc ExtUtils::MakeMaker; perldoc ExtUtils::MM_Unix

sub manifypods
{
    local $_ = shift->SUPER::manifypods(@_);
    s,(MAN1DIR./.+?).pl,$1,gm;
    $_;
}

sub installbin
{
    local $_ = shift->SUPER::installbin(@_);
    s,(SCRIPT./.+?).pl,$1,gm;
    $_;
}

sub postamble
{
    return "
-include etc/makefile/install.mk
-include etc/makefile/admin.mk
";
}

# End of file
