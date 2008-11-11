# make-admin.mk -- Makefile portion
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
#	 Rules for maintenance

.SUFFIXES:
.SUFFIXES: .pl .1 .html .txt

#   Pod generates .x~~ extra files
#
#   $<	  = name of the input (full)
#   $@	  = name, but only basename part, without suffix
#   $(*D) = macro; Give only directory part
#   $(*F) = macro; Give only file part

.pl.1:
	perl $< --Help-man > $@

.pl.html:
	perl $< --Help-html > doc/manual/index.html

.pl.txt:
	pod2man $< > doc/manual/index.txt

doc/index.txt: doc/index.html
	lynx -dump $? > $@

# Rule: man: generate manual page
man: bin/dyndns.1

# Rule: doc: generate documentation
doc: bin/dyndns.html bin/dyndns.txt doc/index.txt

# Rule: manifest-make: Make list of files in this project into file MANIFEST
# Rule: manifest-make: files matching regexps in MANIFEST.SKIP are skipped.
manifest-make:
	rm -f MANIFEST
	LC_ALL=C $(PERL) -MExtUtils::Manifest=mkmanifest -e "mkmanifest()"

# Rule: manifest-check: checks if MANIFEST files really do exist.
manifest-check:
	LC_ALL=C $(PERL) -MExtUtils::Manifest=manicheck -e \
	     "exit 1 if manicheck()";

# Rule: www: copy web pages to ../../<project>-www
www:
	echo $$(pwd); asdasdasd
	name=$$(basename $$(cd .. && pwd)); \
	to=../../$$name-www; \
	echo "Copying to $$to"; \
	find . -type f -name "*.html" | \
	rsync $${test:+"--dry-run"} \
	  --files-from=- \
	  --update \
	  --progress \
	  --verbose \
	  -r \
	  . \
	  $$to/

# End of file
