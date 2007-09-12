#!/usr/bin/makefile -f
# -*- makefile -*-
#
#	Copyright (C) 2003-2007 Jari Aalto
#
#	This program is free software; you can redistribute it and/or
#	modify it under the terms of the GNU General Public License as
#	published by the Free Software Foundation; either version 2 of the
#	License, or (at your option) any later version
#
#	This program is distributed in the hope that it will be useful, but
#	WITHOUT ANY WARRANTY; without even the implied warranty of
#	MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
#	General Public License for more details.
#
#	You should have received a copy of the GNU General Public License
#	along with program; see the file COPYING. If not, write to the
#	Free Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
#	Boston, MA 02110-1301, USA.
#
#	Visit <http://www.gnu.org/copyleft/gpl.html>

# ######################################################### &targets ###

install-log:
	$(INSTALL) $(INSTALL_DATA) -d $(LOGDIR)

install-make-etc-dir:
	$(INSTALL) $(INSTALL_DATA) -d $(ETCDIR)

install-etc: install-make-etc-dir
	@for file in $(OBJS_ETC);					\
	do								\
	    if [ ! -f  $(ETCDIR)/$$file ]; then				\
		echo "installing from $(ETC_DIR_TEMPLATE)/$$file";	\
		$(INSTALL) $(INSTALL_DATA)				\
		    $(ETC_DIR_TEMPLATE)/$$file $(ETCDIR);		\
	    else							\
		echo "Not overwriting existing $(ETCDIR)/$$file";	\
	    fi								\
	done

install-man: doc
	$(INSTALL) $(INSTALL_DATA) -d $(MANDIR)
	@for file in `ls $(DOCDIR)/*.1 $(DOCDIR)/man/*.1 2> /dev/null`; \
	do								\
	    echo "Installing $$file => $(MANDIR)";			\
	    $(INSTALL) $(INSTALL_DATA) $$file $(MANDIR);		\
	done;

install-bin:
	$(INSTALL) -d $(BINDIR)
	@for file in  $(SRCS);						\
	do								\
	    name=$$(echo $$file|					\
		 sed 's/.*\///; s/.pl$$// ; s/.sh$$//');		\
	    $(INSTALL) $(INSTALL_BIN) $$file $(BINDIR)/$$name;		\
	done;

install-bin-symlink:
	$(INSTALL) -d $(BINDIR)
	@for file in  $(SRCS);						\
	do								\
	    dir=`$(DIRNAME) $$file`;					\
	    file=`$(BASENAME) $$file`;					\
	    to=$(BINDIR)/$$file;					\
	    if [ "$$dir" = "." ]; then					\
		file=`pwd`/$$file;					\
	    else							\
		file=$$dir/$$file;					\
	    fi;								\
	    echo "Installing symlink $$file => $$to";			\
	    ln -sf $$file $$to;						\
	done;

# Rule: install - Install files. Run rule 'doc' first
install-unix: install-man install-bin

# Rule: install-clean - Purge executables from the system
install-clean:
	@for file in  $(SRCS);						\
	do								\
	    file=$(BINDIR)/$$file;					\
	    test -f $$file  && rm $$file;				\
	    true;							\
	done;

clean-temp-files:
	@-find . -name "*[~#]" -exec rm -f {} \;

# Rule: clean - Remove directories that can be generated
clean-temp-dirs:
	@-rm -rf .inst/ .sinst/ .build/

# Rule: clean - Remove files and directories that can be generated
clean-temp-realclean: clean-temp-files clean-temp-dirs

# Rule: help - Display make target summary
help-makefile:
	@egrep -e '# +Rule:' $(MAKEFILE) | sed -e 's/.*Rule://' | sort

help: help-makefile
	@cd $(MAKE_INCLUDEDIR) &&				    \
	for file in *.mk;					    \
	do							    \
	    egrep -e '# +Rule:' $$file | sed -e 's/.*Rule://';	    \
	done;

# Rule: release-world - [maintenance] Make a world release
release-world:
	@$(INSTALL) $(INSTALL_DATA) -d $(RELEASEDIR)
	@rm -rf $(RELEASEDIR)/*
	@$(TAR) $(TAR_OPT_NO) -zcf - . | ( cd $(RELEASEDIR); tar -zxf - )
	@cd $(BUILDDIR) &&						    \
	$(TAR) $(TAR_OPT_WORLD) -zcf $(RELEASE_FILE) $(PACKAGEVER)
	@echo Releasing from directory $(RELEASE_FILE_PATH)
	@tar -ztvf $(RELEASE_FILE_PATH)

# Rule: list-world - [maintenance] List content of world release.
list-world:
	$(TAR) -ztvf $(TAR_FILE_WORLD_LS)

# Rule: manifest-make: Make list of files in this project into file MANIFEST
# Rule: manifest-make: files matching regexps in MANIFEST.SKIP are skipped.
manifest-make:
	rm -f MANIFEST
	LC_ALL=C $(PERL) -MExtUtils::Manifest=mkmanifest -e 'mkmanifest()'

# Rule: manifest-check: checks if MANIFEST files really do exist.
manifest-check:
	LC_ALL=C $(PERL) -MExtUtils::Manifest=manicheck -e \
	     'exit 1 if manicheck()';

# End of file
