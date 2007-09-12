# $Id: cygwin.mk,v 1.4 2004/04/05 00:31:46 jaalto Exp $
#
#	Copyright (C)  2003 Jari Aalto
#	Keywords:      Makefile, cygbuild, Cygwin
#
#	This program is free software; you can redistribute it and/or
#	modify it under the terms of the GNU General Public License as
#	published by the Free Software Foundation; either version 2 of the
#	License, or (at your option) any later version
#
#    To make a Cygwin Net release
#
#	First, make world release. It is a preliminary step for Cygwin release
#
#	    make release-world
#
#	Now Cygwin binary and source packages can be done with:
#
#	    make RELEASE=1 release-cygwin-bin release-cygwin-source
#	    make publish
#
#   Cygwin build: How it all works?
#
#	Everything is done under .build/ directory where the released
#	tar files will appear. The first phase is to make world release.
#	You must do it first, because it copies everything under RELEASEDIR
#	which will be exact snapshot of the current package directory (or CVS
#	checkout)
#
#	    .build/package-YYYY.MMDD/		<< RELEASEDIR
#
#	Now, the cygbuild.sh tool will chdir _inside_ this RELEASEDIR directory
#	and will give all packaging commands from there. The results appear
#	one directory above (..), which efectively puts the created files in:
#
#	    .build/
#
#	The 'publish' command works similarly. It enters the RELEASEDIR and looks
#	Cygwin files one directory above (..) and copies them to the default
#	destination directory. This directory is usually configured to Web server
#	and it is seen to the outside world.


CYGBUILD	= cygbuild.sh
CYGBUILDBIN	= $(CYGBUILD)

TAR_FILE_CYGWIN_LS = `ls -t1 $(BUILDDIR)/*[0-9].tar.bz2 | sort -r | head -1`
TAR_FILE_CYGWIN	   = $(BUILDDIR)/$(PACKAGEVER)-$(RELEASE)


# ######################################################### &targets ###

# Rule: release-cygwin - [maintenance] Make a Cygwin Net releases. Call: make RELEASE=1 ...
release-cygwin: release-cygwin-bin release-cygwin-source

# Rule: release-cygwin-source - [maintenance] Make only 'install' 'readmefix'
release-cygwin-bin-fix:
	@cd $(RELEASEDIR) &&					    \
	$(CYGBUILDBIN) -r $(RELEASE) -x install package &&	    \
	$(CYGBUILDBIN) -r $(RELEASE) -x readmefix &&

# Rule: release-cygwin-source - [maintenance] Make only 'install' and 'package'
release-cygwin-bin-only:
	@cd $(RELEASEDIR) &&					    \
	$(CYGBUILDBIN) -r $(RELEASE) -x install package

# Rule: release-cygwin-source - [maintenance] Make everything for binary package
release-cygwin-bin: release-cygwin-bin-fix release-cygwin-bin-only
	@ls $(TAR_FILE_CYGWIN).tar.bz2
	@tar -jtvf $(TAR_FILE_CYGWIN).tar.bz2

# Rule: release-cygwin-source - [maintenance] Make everything for source package
release-cygwin-source:
	cd $(RELEASEDIR) &&					    \
	$(CYGBUILDBIN) -r $(RELEASE) mkdirs source-package
	@ls -l $(TAR_FILE_CYGWIN)*.tar.bz2
	@echo Run 'make publish' if all looks good

# Rule: release-cygwin-source-verify - [maintenance] Verify source package
release-cygwin-source-verify:
	cd $(RELEASEDIR) &&					    \
	$(CYGBUILDBIN) -r $(RELEASE) mkdirs source-package-verify


# This simply copies the cygwin binary and source packages made after target 'kit'
# to the Web server publishing are from where they are available.
# Rule: publish-cygwin - [maintenance] Publish Cygwin net release
publish-cygwin:
	cd $(RELEASEDIR) && \
	$(CYGBUILD) publish


# Rule: release-cygwin - [maintenance] List content of Cygwin Net release.
list-cygwin:
	$(TAR) -jtvf $(TAR_FILE_CYGWIN_LS)


# End of file
