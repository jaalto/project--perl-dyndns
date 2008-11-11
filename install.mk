# make-install.mk -- Makefile portion
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
#	 Additional rules for installation

INSTALL		 = install
INSTALL_DIR	 = $(INSTALL) -m 755
INSTALL_DATA	 = $(INSTALL) -m 644
ETCDIR		 = $(DESTDIR)/etc/perl-dyndns
DOCDIR		 = $(DESTDIR)$(PREFIX)/share/doc/perl-dyndns
ETC_DIR_TEMPLATE = etc/template
OBJS_ETC	 = `(cd $(ETC_DIR_TEMPLATE); ls *.conf)`
OBJS_DOC	 = README

# Rule: manifest-make: Make list of files in this project into file MANIFEST
# Rule: manifest-make: files matching regexps in MANIFEST.SKIP are skipped.
manifest-make:
	rm -f MANIFEST
	LC_ALL=C $(PERL) -MExtUtils::Manifest=mkmanifest -e "mkmanifest()"

# Rule: manifest-check: checks if MANIFEST files really do exist.
manifest-check:
	LC_ALL=C $(PERL) -MExtUtils::Manifest=manicheck -e \
	     "exit 1 if manicheck()";

install-etc:
	$(INSTALL_DIR) -d $(ETCDIR)
	@for file in $(OBJS_ETC);					\
	do								\
	    if [ ! -f  $(ETCDIR)/$$file ]; then				\
		echo $(INSTALL_DATA) $(ETC_DIR_TEMPLATE)/$$file $(ETCDIR); \
		$(INSTALL_DATA) $(ETC_DIR_TEMPLATE)/$$file $(ETCDIR);	\
	    else							\
		echo "[WARN] Not overwriting existing $(ETCDIR)/$$file"; \
	    fi								\
	done

install-doc:
	$(INSTALL_DIR) -d 755 $(DOCDIR)
	$(INSTALL_DATA) $(OBJS_DOC) $(DOCDIR)
	pwd=$$(pwd); \
	cd doc && tar -cf - . | (cd $$pwd/$(DOCDIR) && tar -xf -)

install:: install-etc
install:: install-doc

install-test::
	mkdir -p tmp
	make DESTDIR=tmp install

clean-install-test::
	[ ! -d tmp ]] || rm -rf tmp

clean:: clean-install-test

# End of file

