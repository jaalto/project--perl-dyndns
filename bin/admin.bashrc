#!/bin/bash
#
#   File id
#
#       Copyright (C) 2000-2007 Jari Aalto
#
#       This program is free software; you can redistribute it and/or
#       modify it under the terms of the GNU General Public License as
#       published by the Free Software Foundation; either version 2 of
#       the License, or (at your option) any later version.
#
#       This program is distributed in the hope that it will be useful, but
#       WITHOUT ANY WARRANTY; without even the implied warranty of
#       MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
#       General Public License for more details.
#
#       You should have received a copy of the GNU General Public License
#       along with program; see the file COPYING. If not, write to the
#       Free Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
#       Boston, MA 02110-1301, USA.
#
#       Visit <http://www.gnu.org/copyleft/gpl.html>
#
#   Documentation
#
#       This file is of interest only for the Admin or Co-Developer of
#       project. These bash functions will help maintaining the project.
#       You need:
#
#       Bash        any version
#       Perl        5.004 or any later version
#       t2html.pl   Perl program to convert text -> HTML
#                   http://freshmeat.net/projects/perl-text2html
#
#       Variables to set
#
#       SF_PERL_DYNDNS_USER=<sourceforge-login-name>
#       SF_PERL_DYNDNS_USER_NAME="FirstName LastName"
#       SF_PERL_DYNDNS_EMAIL=<email address>
#       SF_PERL_DYNDNS_ROOT=~/cvs-projects/perl-dyndns
#       SF_PERL_DYNDNS_HTML_TARGET=http://freshmeat.net/projects/perl-dyndns

function sfperldyn_init ()
{
    local id="sfperldyninit"

    local url=http://perl-dyndns.sourceforge.net/

    SF_PERL_DYNDNS_HTML_TARGET=${SF_PERL_DYNDNS_HTML_TARGET:-$url}

    SF_PERL_DYNDNS_KWD=${SF_PERL_DYNDNS_KWD:-"\
Perl, HTML, CSS2, conversion, text2html"}

    SF_PERL_DYNDNS_DESC=${SF_PERL_DYNDNS_DESC:-"Perl text2html converter"}
    SF_PERL_DYNDNS_TITLE=${SF_PERL_DYNDNS_TITLE:-"$SF_PERL_DYNDNS_DESC"}
    SF_PERL_DYNDNS_ROOT=${SF_PERL_DYNDNS_ROOT:-""}


    if [ "$SF_PERL_DYNDNS_USER" = "" ]; then
       echo "$id: Identity SF_PERL_DYNDNS_USER unknown."
    fi


    if [ "$SF_PERL_DYNDNS_USER_NAME" = "" ]; then
       echo "$id: Identity SF_PERL_DYNDNS_USER_NAME unknown."
    fi

    if [ "$SF_PERL_DYNDNS_EMAIL" = "" ]; then
       echo "$id: Address SF_PERL_DYNDNS_EMAIL unknown."
    fi
}

function sfperldyn_date ()
{
    date "+%Y.%m%d"
}

function sfperldyn_ask ()
{
    #   Ask question from user.

    local msg="$1"
    local answer
    local junk

    echo "$msg" >&2
    read -e answer junk

    case $answer in
        Y|y|yes)    return 0 ;;
        *)          return 1 ;;
    esac
}

function sfperldyn_FileSize ()
{
    #   put line into array ( .. )

    local line
    line=($(ls -l "$1"))

    #   Read 4th element from array
    #   -rw-r--r--    1 root     None         4989 Aug  5 23:37 file

    echo ${line[4]}
}

function sfperldyn_CheckRoot ()
{
    local id="sfperldyn_CheckRoot"

    if [ ! -d "$SF_PERL_DYNDNS_ROOT" ]; then
        echo "$id: invalid SF_PERL_DYNDNS_ROOT [$SF_PERL_DYNDNS_ROOT]"
        return 0
    fi

    return 1
}

function sfperldyn_VersionUpdate ()
{
    #   Update Version: field.

    local id="sfperldyn_VersionUpdate"
    local version="$1"
    local source="$2"


    if [ -z "$version" ]; then
        echo "$id: ABorted. No VERSION information, arg 1"
        return
    fi

    if [ ! -r $source ]; then
        echo "$id: Aborted. Problem reading [$source], arg 2"
        return
    fi

    #  Update the Version field.

    local out=$source.new

    if [ -f $out ]; then
        rm $out || return
    fi

    awk '                                   \
    {                                       \
        if ( match( $0, "Version:") > 0 )   \
        {                                   \
            print "Version: " ver;          \
        }                                   \
        else                                \
        {                                   \
            print;                          \
        }                                   \
    }' ver=$version $source                 \
    >  $out

    if [ -s $out ]; then
        mv $out $source
    else
        echo "$id: [ERROR], output file looks odd: $out"
        ls -l $out
    fi

}

function sfperldynscp ()
{
    #   To upload file to project, call from shell prompt
    #
    #       bash$ sfperldynscp <FILE>

    local sfuser=$SF_PERL_DYNDNS_USER
    local sfproject=p/pe/perl-dyndns

    if [ "$SF_PERL_DYNDNS_USER" = "" ]; then
        echo "sfperldynscp: identity SF_PERL_DYNDNS_USER unknown, can't scp files."
        return
    fi

    scp $* $sfuser@shell.sourceforge.net:/home/groups/$sfproject/htdocs/
}

function sfperldyn_doc ()
{
    #   Generate documentation.

    local id="sfperldyn_doc"
    local dir=$SF_PERL_DYNDNS_ROOT

    if sfperldyn_CheckRoot; then
       echo "$id: aborted."
       return
    fi

    cd $dir/bin

    perl dyndns.pl --Help-man  > ../doc/man/dyndns.1
    perl dyndns.pl --Help-html > ../doc/html/dyndns.html
    perl dyndns.pl --help      > ../doc/txt/dyndns.txt


    #   The Perl POD maker leaves behind .x~~ files. Delete them

    for file in *~
    do
        rm $file
    done

    echo "$id: Documentation updated."
}

function sfperldyn_IsDebian ()
{
    local id="sfperldyn_IsDebian"
    test -f /usr/bin/dpkg-deb
}

function sfperldyn_MakeFilename ()
{
    #   $1 is desired file to request

    local id="sfperldyn_MakeFilename"

    if sfperldyn_CheckRoot; then
       echo "$id: aborted [$1]."
       return
    fi

    local root=$SF_PERL_DYNDNS_ROOT
    local ret=$root/$1

    if [ "$1" = "" ]; then
        echo $root
    elif [ ! -f  $ret  -o  -d $ret ]; then
        echo "No such file or directory: $ret";
        echo "#InvalidRequest#"
    else
        echo $root/$1
    fi

}

function sfperldyn_version ()
{
    # Read current version infromation.

    local id="sfperldyn_version"
    local source=$(sfperldyn_MakeFilename bin/dyndns.pl)

    perl $source --Version | cut -d" " -f 1
}

function sfperldyn_DebianControlGetVersion ()
{
    # Read current control file's version infromation.

    local id="sfperldyn_DebianControlGetVersion"
    local source=$(sfperldyn_MakeFilename debian/control)

    awk -F" " '/Version:/ { print $2; exit}'  $source
}

function sfperldyn_DebianControlGetVersionNew ()
{
    local prgVersion=$(sfperldyn_version)
    local debVersion=$(sfperldyn_DebianControlGetVersion)

    #  Debian version numbers contain x.x-patch

    local ver=${debVersion%%-*}
    local patch=${debVersion##*-}

    #  If version numbers are the same, this is NEW patch release

    if [ "$prgVersion" = "$ver" ]; then
        (( patch++ ))
    else
        ver=$prgVersion
        patch=1
    fi

    echo $ver-$patch
}

function sfperldyn_DebianControl ()
{
    #  Update control file's version information

    local id="sfperldyn_ReleaseDebianControl"
    local version=$(sfperldyn_DebianControlGetVersionNew)
    local source=$(sfperldyn_MakeFilename debian/control)

    sfperldyn_VersionUpdate "$version" "$source"

    echo "$id: updated $source $version"
}

function sfperldyn_ReleaseDebian ()
{
    local id="sfperldyn_ReleaseDebian"

    # Create debian .deb package

    if sfperldyn_CheckRoot; then
       echo "$id: aborted."
       return
    fi

    if ! sfperldyn_IsDebian; then
        echo "$id: ignored, this is not a debian system."
        return;
    fi

    # ........................................................ Clean ...

    echo "$id: Cleaning previous build structure"

    local root=$SF_PERL_DYNDNS_ROOT
    local build=~/tmp/package/debian
    local to=perl-dyndns

    local dir=$build/$to

    if [ -d $dir ]; then
        echo "$id: cleaning old build directory"
        rm -rf --verbose $dir || return
    fi

    # .............................................. Build Structure ...

    echo "$id: making fresh build structure"

    local control=$dir/DEBIAN

    mkdir -p --verbose $control

    if [ ! -d $control ]; then
        echo "$id: Cannot create $control, aborted."
        return;
    fi

    local install=$dir/usr/bin
    mkdir -p --verbose $install

    local man=$dir/usr/share/man/man1
    mkdir -p --verbose $man

    local doc=$dir/usr/share/doc/perl-dyndns
    mkdir -p --verbose $doc/html

    # Set permissions

    echo "$id: Setting directory permissions 755"
    find $dir -type d | xargs chmod 755

    # ......................................................... Copy ...

    echo "$id: Copying files to build directory and making .deb"

    local file=dyndns.pl
    local bin="$root/bin/$file"
    cp  --verbose $bin $install/$file || return

    perl $bin --Help-man > $man/dyndns.1

    cp  $root/doc/txt/*.txt   $doc/
    cp  $root/doc/html/*.html $doc/html/

    file="control"
    cp $root/debian/$file $control/$file  || return

    cp $root/debian/{prerm,postrm} $control

    #  Now update version information in 'control' file
    sfperldyn_DebianControl

    (
        cd $build
        echo "$id: Building in " $(pwd)
        dpkg-deb --build -z9 $to $to  || return
        cd $to

        #  Now check build status

        package=$(pwd)/$(ls *.deb)

        if [ ! -f $package ]; then
            echo "$id: [ERROR] No .deb package found at " $(pwd)
        else
            echo "$id: Checking build status, lintian $package"
            lintian $package
        fi

    )
}

function sfperldyn_release_check ()
{
    #   Remind that that everything has been prepared
    #   Before doing release

    if sfperldyn_ask '[sfperldyn_doc] Generate docs (y/[n])?'
    then
        echo "Running..."
        sfperldyn_doc
    fi


    if sfperldyn_ask '[sfperldyn_doc] Make debian .deb (y/[n])?'
    then
        sfperldyn_ReleaseDebian
    fi
}

function sfperldyn_release ()
{
    local id="sfperldyn_release"

    local dir=/tmp

    if [ ! -d $dir ]; then
        echo "$id: Can't make release. No directory [$dir]"
        return
    fi

    if sfperldyn_CheckRoot; then
       echo "$id: aborted."
       return
    fi

    sfperldyn_release_check

    local opt=-9
    local cmd=gzip
    local ext1=.tar
    local ext2=.gz

    local base=perl-dyndns
    local ver=$(sfperldyn_date)
    local tar="$base-$ver$ext1"
    local file="$base-$ver$ext1$ext2"

    if [ -f $dir/$file ]; then
        echo "$id: Removing old archive $dir/$file"
        rm $dir/$file
    fi

    (

        local todir=$base-$ver
        local tmp=$dir/$todir

        if [ -d $tmp ]; then
            echo "$id: Removing old archive directory $tmp"
            rm -rf $tmp
        fi

        cp -r $SF_PERL_DYNDNS_ROOT $dir/$todir

        cd $dir

        find $todir -type f                     \
            \( -name "*[#~]*"                   \
               -o -name ".*[#~]"                \
               -o -name ".#*"                   \
               -o -name "*elc"                  \
               -o -name "*tar"                  \
               -o -name "*gz"                   \
               -o -name "*bz2"                  \
               -o -name .cvsignore              \
            \) -prune                           \
            -o -type d \( -name CVS \) -prune   \
            -o -type f -print                   \
            | xargs tar cvf $dir/$tar

        echo "$id: Running $cmd $opt $dir/$tar"

        $cmd $opt $dir/$tar

        echo "$id: Made release $dir/$file"
        ls -l $dir/$file
    )

    echo "$id: Call ncftpput upload.sourceforge.net /incoming $dir/$file"
}

sfperldyn_init                  # Run initializer

export SF_PERL_DYNDNS_HTML_TARGET
export SF_PERL_DYNDNS_KWD
export SF_PERL_DYNDNS_DESC
export SF_PERL_DYNDNS_TITLE
export SF_PERL_DYNDNS_ROOT

# End of file
