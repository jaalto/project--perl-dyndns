# $Id: net.mk,v 1.3 2003/08/01 14:32:30 jaalto Exp $
#
#	Copyright (C)  2003 Jari Aalto
#	Keywords:      Makefile, sourceforge
#
#	This program is free software; you can redistribute it and/or
#	modify it under the terms of the GNU General Public License as
#	published by the Free Software Foundation; either version 2 of the
#	License, or (at your option) any later version
#
#	Make targets to update files to a remote location.


SOURCEFORGE_UPLOAD_HOST = upload.sourceforge.net
SOURCEFORGE_UPLOAD_DIR	= /incoming

SOURCEFORGE_DIR	    = /home/groups/p/pe/perl-dyndns
SOURCEFORGE_SHELL   = shell.sourceforge.net
SOURCEFORGE_USER    = $(USER)
SOURCEFORGE_SSH_DIR = \
  $(SOURCEFORGE_USER)@$(SOURCEFORGE_SHELL):$(SOURCEFORGE_DIR)


SF_DOC_DIR	    = doc/html
SF_DOC_OBJS	    = `ls $(SF_DOC_DIR)/*.html`

CYGETC_DIR	    = etc/cygwin
CYGETC_UPLOAD_DIR   = $(SOURCEFORGE_SSH_DIR)

# ######################################################### &targets ###


sf-uload-no-root:
	@if [ $(SOURCEFORGE_USER) = "root" ]; then		    \
	    echo "'root' cannot upload files. ";		    \
	    echo "Please call with 'make USER=<sfuser> <target>";   \
	    return 1;						    \
	fi

# Rule: sf-upload-doc - [Maintenence] Sourceforge; Upload documentation
sf-upload-doc: doc sf-uload-no-root
	scp $(SF_DOC_OBJS) $(SOURCEFORGE_SSH_DIR)/htdocs/

sf-upload-release-check:
	@[ -f $(RELEASE_FILE_PATH) ]


# Rule: sf-upload-doc - [Maintenence] Sourceforge; Upload documentation
sf-upload-release: sf-upload-release-check
	@echo "-- run command --"
	@echo $(FTP)			    \
		$(SOURCEFORGE_UPLOAD_HOST)  \
		$(SOURCEFORGE_UPLOAD_DIR)   \
		$(RELEASE_FILE_PATH)


# Rule: sf-upload-doc - [Maintenence] Sourceforge; Upload setup.ini
sf-upload-cyg-setup-ini: sf-uload-no-root
	scp $(CYGETC_DIR)/setup.ini $(CYGETC_UPLOAD_DIR)

# End of file
