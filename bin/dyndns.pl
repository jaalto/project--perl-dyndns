#!/usr/bin/perl
#
# dyndns.pl - Update Dynamic DNS address to DDNS provider
#
#   File id
#
#       Copyright (C) 1999-2008 Jari Aalto
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
#   Details how to update dyndns.org account
#
#       To create an account [2000-11-04]
#       http://members.dyndns.org/newacct
#
#       According to the developer page at
#       For more about approved clients for dyndns.org, refer to:
#       http://clients.dyndns.org/
#
#       majordomo@dyndns.org with "subscribe devel" in the body of the message
#       The signup e-mail will have information about the test account
#       to be used in client testing to avoid blocks on your own account.
#
#       2001-06, the specification has changed. The new specification
#       is listed in http://support.dyndns.org/dyndns/clients/devel/query.shtml
#       and look like this:
#
#       http://username:password@members.dyndns.org/nic/update?system=dyndns&hostname=yourhost.ourdomain.ext,yourhost2.dyndns.org& myip=ipaddress&wildcard=OFF&mx=mail.exchanger.ext&backmx=NO&offline=NO
#
#       GET /nic/update?system=statdns&hostname=yourhost.ourdomain.ext,yourhost2.dyndns.org &myip=ipaddress&wildcard=OFF&mx=mail.exchanger.ext&backmx=NO&offline=NO HTTP/1.1
#       Host: members.dyndns.org
#       Authorization: Basic username:pass (note: username:pass must be encoded in base64)
#       User-Agent: myclient/1.0 me@null.net
#
#       ...A test account is available for client testing to avoid having your
#       own hostnames blocked. Hosts test.* (all available domains) can be
#       updated under this account, and we unblock them on a fairly regular
#       basis. The username and password for this account are both "test".
#
#   Test commands (developer only information)
#
#       dyndns.pl --system custom --Test-account --urlping-linksys4 -d 4 2>&1 | tee ~/dyndns-custom.log

# {{{ Import

use 5.004;

use strict;
use English;
use File::Basename;
use Getopt::Long;

use autouse 'Pod::Text'     => qw( pod2text );
use autouse 'Pod::Html'     => qw( pod2html );

#   use autouse 'Sys::Syslog' =>  qw( syslog closelog );
#   See also CPAN module: Tie::Syslog

my @REQUIRE_FATAL =   # Without these the program won't work
(
    'HTTP::Request::Common'
    , 'HTTP::Headers'
    , 'LWP::UserAgent'
    , 'LWP::Simple'
);

my @REQUIRE_OPTIONAL =
(
     'Sys::Syslog'
);

#  Will be set at runtime
my @FEATURE_LIST_MODULES;

IMPORT:                     # This is just syntactic sugar: actually no-op
{
    #   Import following environment variables

    use Env;
    use vars qw
    (
        $PATH
        $TMPDIR
        $SYSTEMROOT
        $WINDIR
    );

    use vars qw ( $VERSION );

    #   This is for use of Makefile.PL and ExtUtils::MakeMaker
    #   So that it puts the tardist number in format YYYY.MMDD
    #
    #   The following variable is updated by Emacs setup whenever
    #   this file is saved.

    $VERSION = '2008.1111.1231';
}

# }}}
# {{{ Initialize

# ****************************************************************************
#
#   DESCRIPTION
#
#       Set global variables for the program
#
#   INPUT PARAMETERS
#
#       none
#
#   RETURN VALUES
#
#       none
#
# ****************************************************************************

sub Initialize ()
{
    use vars qw
    (
        $PROGNAME
        $LIB
        $WIN32
        $CYGWIN

        %STATUS_CODE_DYNDNS_HASH
        @STATUS_CODE_DYNDNS_TRY_AGAIN

        %STATUS_CODE_NOIP_HASH
        @STATUS_CODE_NOIP_TRY_AGAIN

        %STATUS_CODE_HN_HASH
        @STATUS_CODE_HN_TRY_AGAIN

        $WIN32_SYSLOG_DIR
        $WIN32_SYSLOG_FILE
        $WIN32_SYSLOG_PATH
    );

    $PROGNAME   = basename $PROGRAM_NAME;
    $LIB        = $PROGNAME;

    my $id = "$LIB.Initialize";

    $WIN32    = 1   if  $OSNAME =~ /win32|cygwin/i;
    $CYGWIN   = 1   if  $OSNAME =~ /cygwin/i;

    if ( not $WIN32  or  $CYGWIN )
    {
        #   Sometimes due to malconfigured system, the PATH is not set
        #   correctly. Make sure it includes these, always.

        $PATH .= ":/bin:/usr/bin:/sbin:/usr/sbin";
    }

    #   For Activestate Perl without Cygwin.

    $WIN32_SYSLOG_FILE  = "syslog.txt";
    $WIN32_SYSLOG_DIR   = "C:/";
    $WIN32_SYSLOG_PATH  = $WIN32_SYSLOG_DIR  . $WIN32_SYSLOG_FILE;

    $OUTPUT_AUTOFLUSH = 1;

    %STATUS_CODE_HN_HASH =
    (
        101     => "Ok, update succeeded."
        , 201   => "Failure, previous update was already 300 seconds ago"
        , 202   => "Failure, server error"
        , 203   => "Failure, account locked by admin"
        , 204   => "Failure, account locked by user"
    );

    @STATUS_CODE_HN_TRY_AGAIN = qw
    (
        101
    );

    %STATUS_CODE_NOIP_HASH =
    (
         0 => "No changes; already set. IP update considered abusive"
         , 1 => "Ok, update succeeded"
         , 2 => "Incorrect hostname"
         , 3 => "Bad authorization (password)"
         , 4 => "Bad authorization (user)"
         , 6 => "Acocunt has been banned for violating terms of service"
         , 7 => "Ip is a private network address"
         , 8 => "Host or acocunt has been disabled by the provider"
         , 9 => "Cannot update, because it is a web redirect"
        , 10 => "Group does not exist"
        , 11 => "Group update succeeded"
        , 12 => "No changes; already set. Group update considered abusive"
        , 99 => "This client software has been disabled/expired. "
                . "Please upgrade to newest version."
    );

    #  Codes that signify "You can try again, you made a mistake"

    @STATUS_CODE_NOIP_TRY_AGAIN = qw
    (
        2 3 4 7 9 10
    );

    # 2002-01-01 See http://clients.dyndns.org/devel/codes.php

    %STATUS_CODE_DYNDNS_HASH =
    (
        # Pre-Update Errors
        #
        #   The codes above are only only given once, regardless of how many
        #   hosts are in the update.

        "badauth"       => "Bad authorization (username or password)"
        , "badsys"      => "The system parameter given was not valid."
        , "badagent"    => "The useragent your client sent has been blocked"
          . " at the access level. Support of this return code is optional."

        # Update Complete
        #
        #   The codes below indicate that the update was completed, in some
        #   fashion or another. This includes abusive updates, see the
        #   abuse code for more information.
        #
        #   Note that "update complete" messages will be followed by the IP
        #   address updated for confirmation purposes. This value will be
        #   space-separated from the update code.

        , "good"        => "Ok, update succeeded."
        , "nochg"       => "No changes, update considered abusive"

        # Input Error Conditions
        #
        #   The codes below indicate fatal errors, after which updating should
        #   be stopped pending user confirmation of settings or other
        #   appropriate data.
        #
        #   notfqdn will be returned once if no hosts are given.

        , "notfqdn"     => "A Fully-Qualified Domain Name was not provided."
        , "nohost"      => "The hostname specified does not exist"

        , "!donator"    => "The offline setting was set, when the user"
                        .  " is not a donator, this is only returned once"

        , "!yours"      => "The hostname specified exists, but not under"

        , "!active"     => "The hostname specified is in a Custom DNS domain"
                        .  " which has not yet been activated. "
                        .  "The hostname specified exists, but not under"

        , "abuse"       => "The hostname specified is blocked for abuse;"
                        .  " contact support to be unblocked"

        # Server Error Conditions
        #
        #   The conditions represented by the codes below should cause the
        #   client to stop and request that the user inform support what
        #   code was received. These are hard server errors that will have
        #   to be investigated.
        #
        #   Note: dnserr will be followed by a numeric packet ID which
        #   should be reported to the support department along with the
        #   error.

        , "numhost"     => "Too many or too few hosts found"
        , "dnserr"      => "DNS error encountered"

        # Wait Conditions
        #
        #   When one of the below codes is received, wait for the specified
        #   conditions to be met before attempting another update. Note:
        #   "xx" can be any integer. Note: An optional explanation of the
        #   delay may be present after the wait code, separated from the
        #   code by a space. Due to difficulties in implementation, the
        #   wuxxxx return has been removed from the spec.

        , "wxxh"        => "Wait xx hours."
        , "wxxm"        => "Wait xx minutes."
        , "wxxs"        => "Wait xx seconds."

        # Emergency Conditions

        #   To be used when things have all gone horribly wrong, mostly if
        #   the database or DNS server have died for whatever reason. Also
        #   will be sent if the NIC is closed for any reason, unless a
        #   timeframe is known.

        , "911"         => "Shutdown until notified otherwise via status.shtml"

        #   Same as 911, for British users :)
        , "999"         => "Shutdown until notified otherwise via status.shtml"
    );

    @STATUS_CODE_DYNDNS_TRY_AGAIN =
    (
        "badauth"
        , "badsys"
        , "notfqdn"
        , "nohost"
        , "!yours"
        , "!active"
        , "numhost"
        , "dnserr"
    );
}

# ****************************************************************************
#
#   DESCRIPTION
#
#       Load CPAN modules or notify user
#
#   INPUT PARAMETERS
#
#       None
#
#   RETURN VALUES
#
#       None. Dies if cannot load module.
#
# ****************************************************************************

sub InitializeModules ()
{
    my $id = "$LIB.InitializeModules";

    for my $module (@REQUIRE_OPTIONAL )
    {
        eval "use $module";

        if ($EVAL_ERROR)
        {
            warn "$id: [WARN] can't load CPAN module $module: $EVAL_ERROR\n"
              . "Please install with command:\n"
              . "  perl -MCPAN -e shell\n"
              . "  cpan>install $module\n" ;
        }

	push @FEATURE_LIST_MODULES, $module;
    }

    for my $module (@REQUIRE_FATAL )
    {
        eval "use $module";

        if ($EVAL_ERROR)
        {
            warn "$id: [FATAL] can't load CPAN module $module: $EVAL_ERROR\n"
              . "Please install with command:\n"
              . "  perl -MCPAN -e shell\n"
              . "  cpan>install $module\n" ;

            exit 1;
        }
    }
}

# }}}
# {{{ Help page

# ***************************************************************** &help ****
#
#   DESCRIPTION
#
#       Print help and exit.
#
#   INPUT PARAMETERS
#
#       $msg    [optional] Reason why function was called.-
#
#   RETURN VALUES
#
#       none
#
# ****************************************************************************

=pod

=head1 NAME

dyndns.pl - Update IP address to dynamic DNS (DDNS) provider

=head1 SYNOPSIS

    dyndns.pl --login LOGIN --password PASSWORD \
              --Host yourhost.dyndns.org

Note: By Default this program expects www.dyndns.org provider. If you use
other provider, see option B<--Provider>

=head1 OPTIONS

=head2 Gneneral options

=over 4

=item B<--Config=FILE [--Config=FILE ...]>

List of configuration files to read. No command line options other
than B<--verbose>, B<--debug> or B<--test> should be appended or
results are undefined. Each file must contain complete DDNS account
configuration.

The FILE part wll go through Perl's C<glob()> function, meaning that
the filenames are expanded if standard shell wild card is supplied.
Series of configuration files can be run at once e.g. within directory
C</etc/dyndns/> by using a single option. The order of the files processed
is alphabetical:

    --Config=/etc/dyndns/*

See section CONFIGURATION FILE for more information how to write the files.

=item B<--Host=host1 [--Host=host2 ...]>

Use registered HOST(s).

=item B<--group GROUP>

B<This option is only for --Provider noip>

Assign IP to GROUP. Do you have many hosts that all update to the same
IP address? Update a group instead of a many hosts.

=item B<--login LOGIN>

DDNS account's LOGIN name.

=item B<--mxhost MX-HOST-NAME>

B<This option is only for --Provider dyndns>

Update account information with MX hostname. Specifies a Mail eXchanger for
use with the host being modified. Must resolve to an B<static> IP address,
or it will be ignored. If you don't know DNS, don't touch this option.

The servers you list need to be correctly configured to accept mail for
your hostname, or this will do no good. Setting up a server as an MX
without permission of the administrator may get them angry at you. If
someone is contacted about such an infraction, your MX record will be
removed and possibly further action taken to prevent it from happening
again. Any mail sent to a misconfigured server listed as an MX may bounce,
and may be lost.

=item B<--Mx-option>

B<This option is only for --Provider dyndns>

Turn on MX option. Request that the MX in the previous parameter be set up
as a backup. This means that mail will first attempt to deliver to your
host directly, and will be delivered to the MX listed as a backup.

Note regarding provider C<noip>:

Update clients cannot change this value. Clients can only submit requests
to the php script to update the A record. Changes such as MX records
must be done through website.

=item B<--Offline>

If given, set the host to offline mode.

C<Note:> [dyndns] This feature is only available to donators. The
"!donator" return message will appear if this is set on a non-donator
host.

This is useful if you will be going offline for an extended period of
time. If someone else gets your old IP your users will not go to your
old IP address.

=item B<--password PASSWORD>

DDNS account's PASSWORD.

=item B<--system {dyndns|statdns|custom}>

B<This option is only for --Provider dyndns>

The system you wish to use for this update. C<dyndns> will update a dynamic
host, C<custom> will update a MyDynDNS Custom DNS host and C<statdns> will
update a static host. The default value is C<dyndns> and you cannot use
other options (statdns|custom) unless you donate and gain access to the
more advanced features.

=item B<--Wildcard>

Turn on wildcard option. The wildcard aliases C<*.yourhost.ourdomain.ext>
to the same address as C<yourhost.ourdomain.ext>

=back

=head2 Additional options

=over 4

=item B<--Daemon [WAIT-MINUTES]>

Enter daemon mode. The term "daemon" refers to a standalone processes
which keep serving until killed. In daemon mode program enters
into infinite loop where IP address changes are checked periodically.
For each new ip address check, program waits for WAIT-MINUTES.
Messages in this mode are reported using syslog(3).

This option is designed to be used in systems that do not provide Unix-like
cron capabilities (e.g under Windows OS). It is better to use cron(8) and
define an entry using crontab(5) notation to run the update in periodic
intervals. This will use less memory when Perl is not permanently kept in
memory like it would with option B<--Daemon>.

The update to DDNS provider happens only if

    1) IP address changes
    2) or it has taken 30 days since last update.
       (See DDNS providers' account expiration time documentation)

The minumum sleep time is 5 minutes. Program will not allow faster
wake up times(*). The value can be expressed in formats:

    15      Plain number, minutes
    15m     (m)inutes. Same sa above
    1h      (h)ours
    1d      (d)days

This options is primarily for cable and DSL users. If you have a
dial-up connection, it is better to arrange the IP update at the same
time as when the connection is started. In Linux this would happen
during C<ifup(1)>.

(*) Perl language is CPU intensive so any faster check would put
considerable strain on system resources. Normally a value of 30 or 60
minutes will work fine in most of the ADSL lines. Monitor the ISP's IP
rotation time to adjust the time in to use sufficiently long wake up
times.

=item B<--ethernet [CARD]>

In Linux system, the automatic IP detection uses program
C<ifconfig(1)>. If you have multiple network cards, select the correct
card with this option. The default device queried is C<eth0>.

=item B<--file PREFIX>

Prefix where to save IP information. This can be a) a absolute path name to
a file b) directory where to save or c) directory + prefix where to save.
Make sure that files in this location do not get deleted. If they are
deleted and you happen to update SAME ip twice within a short period -
according to www.dyndns.org FAQ - your address may be blocked.

On Windows platform all filenames must use forward slashs like
C:/somedir/to/, not C:\somedir\to.

The PREFIX is only used as a basename for supported DDNS accounts (see
B<--Provider>). The saved filename is constructed like this:

   PREFIX<ethernet-card>-<update-system>-<host>-<provider>.log
                          |
                          See option --system

A sample filename in Linux could be something like this if PREFIX were set
to C</var/log/dyndns/>:

    /var/log/dyndns/eth0-statdns-my.dyndns.org-dyndns.log

=item B<--file-default|-f>

Use reasonable default for saved IP file PREFIX (see B<--file>). Under
Windows, %WINDIR% is used. Under Linux the PREFIXes searched are

    /var/log/dyndns/     (if directory exists)
    /var/log/            (system's standard)
    $HOME/tmp or $HOME   if process is not running under root

=item B<--proxy HOST>

Use HOST as outgoing HTTP proxy.

=item B<--Provider TYPE>

By default, program connects to C<dyndns.org> to update the dynamic IP
address. There are many free dynamic DNS providers are reported.
Supported list of TYPES in alphabetical order:

    hnorg       No domain name limists
                Basic DDNS service is free (as of 2003-10-02)
                http://hn.org/

    dyndns      No domain name limits.
                Basic DDNS service is free (as of 2003-10-02)
                http://www.dyndns.org/
                See also http://members.dyndns.org/

    noip        No domain name limits.
                Basic DDNS service is free (as of 2003-10-02)
                http://www.no-ip.com/

=item B<--Query>

Query current IP address and quit. B<Note:> if you use router, you may
need --urlping* option, otherwise the IP address returned is your subnet's
DHCP IP and not the ISP's Internet IP.

Output of the command is at least two string. The second string is
C<last-ip-info-not-available> if the saved ip file name is not specified.
In order to program to know where to look for saved IP files you need to
give some B<--file*> or B<--Config> option. The second string can also be
C<nochange> if current IP address is same as what was found from saved
file. Examples:

    100.197.1.6 last-ip-info-not-available
    100.197.1.6 100.197.1.7
    100.197.1.6 nochange 18
                         |
                         How many days since last saved IP

B<Note for tool developers:> additional information may be provided in
future. Don't rely on the count of the output words, but instead parse
output from left to right.

=item B<--Query-ipchanged ['exitcode']>

Print message if IP has changed or not. This option can take
an optional string argument C<exitcode> which causes program to
indicate changed ip address with standard shell status code
(in bash shell that would available at variable C<$?>):

    $ dyndns.pl --Query-ipchange exitcode --file-default \
      --Provider dyndns --Host xxx.dyndns.org
    $ echo $?

    ... the status code of shell ($?) would be:

    0   true value, changed
    1   false value, error code, i.e. not changed

Without the C<exitcode> argument, the returned strings are:

                Current IP address
                |
    changed  35 111.222.333.444
    nochange 18
             |
             Days since last IP update. Based on saved IP file's
             time stamp.

If the last saved IP file's time stamp is too old, then even if the IP were
not really changed, the situation is reported with word C<changed>. This is
due to time limits the DDNS providers have. The account would expire unless
it is updated in NN days.

B<Note for tool developers:> additional information may be provided in
future. Don't rely on the count of the output words, but instead parse
output from left to right.

=item B<--Query-ipfile>

Print the name of the IP file and quit.

B<Note:> In order for this option to work, you must supply all other
options would be normally pass to update the DDNS account, because the Ip
filename depends on these options. Alternatively provide option B<--Config
FILE> from where all relevant information if read.

    --ethernet      [optional, defaults to eth0]
    --Provider      [optional, defaults to dyndns]
    --system        [optional, defaults to dyndns]
    --Host          required.

Here is an example which supposed that directory C</var/log/dyndns/>
already exists:

    $ dyndns.pl --file-default --Query-ipfile \
      --Provider dyndns --Host xxx.dyndns.org
    /var/log/dyndns/eth0-dyndns-dyndns-xxx-dyndns.org.log

=item B<--regexp REGEXP>

In host, which has multiple netword cards, the response can include
multiple IP addresses. The default is to pick always the first choice, but
that may not be what is wanted. The regexp MUST not contain capturing
parentheses: if you need one, use non-capturing choice (?:). Refer to Perl
manual page C<perlre> for more information about non-cpaturing regular
expression parentheses.

Here is an example from Windows:

    Ethernet adapter {3C317757-AEE8-4DA7-9B68-C67B4D344103}:

        Connection-specific DNS Suffix  . :
        Autoconfiguration IP Address. . . : 169.254.241.150
        Subnet Mask . . . . . . . . . . . : 255.255.0.0
        Default Gateway . . . . . . . . . :

    Ethernet adapter Local Area Connection 3:

        Connection-specific DNS Suffix  . : somewhere.net
        IP Address. . . . . . . . . . . . : 193.10.221.45
        Subnet Mask . . . . . . . . . . . : 255.255.0.0
        Default Gateway . . . . . . . . . : 10.10.0.101

The 193.10.221.45 is the intended dynamic IP address, not the first one.
To instruct searching from somewhere else in the listing, supply a
regular expressions that can match a portion in the listing after
which the IP address appears. In the above case, the regexp could be:

    --regexp "Connection 3:"

In Windows, the words that follow "IP Address" are automatically expected,
so you should not add them to the regexp.

In FreeBSD 4.5, you may get following response:

    tun0: flags <UP,POINTOPOINT,RUNNING,MULTICAST> mtu 1492
        inet6 fe80::250:4ff:feef:7998%tun0 prefixlen 64 scopeid 0x7
        inet 62.214.33.49 --> 255.255.255.255 netmask 0xffffffff
        inet 62.214.32.12 --> 255.255.255.255 netmask 0xffffffff
        inet 62.214.35.49 --> 255.255.255.255 netmask 0xffffffff
        inet 62.214.33.163 --> 62.214.32.1 netmask 0xff000000
        Opened by PID 64

The correct IP address to pick from the listing is the one, which does
not contain netmask 0xffffffff. The picked address for above is
therefore 62.214.33.163. The regexp that finds that line is:

    --regexp ".*0xffffffff.*?inet"
               |            |
               |            Search minimum match until word "inet"
               search maximum match

This will match all the way until the the last line with netmask
0xffffffff, after which shortest match C<.*?> to C<inet> is reached to read
the number following it. The regexp must make sure that the next word
after its match point is the wanted address.

=back

=head2 Cable, DSL and router options

=over 4

If you do not have direct access to world known C<real> IP address, but to
a subnet IP address, then you cannot determine your outside world IP
address from your machine directly. See picture below:

                        router/subnet                    Internet
                       +-------------+                +-----------+
   Your PC:            |             | maps address   |           |
   connect to ISP -->  | ROUTER      | -------------> |           |
                       | 192.168.... |                | 80.1.1.1  |
   local ip says:      +-------------+                +-----------+
   192.168.xxx.xxx                                    THE REAL IP

ASDL and cable modem and other connections may not be directly connected to
Internet, but to a router to allow subnnetting internal hosts. This makes
several computers to access the Internet while the ISP has offered only one
visible IP address to you. The router makes the mapping of the local subnet
IP to the world known IP address, provided by the ISP when the connection
was established.

You need some way to find out what is the real IP is. The simplest way is
to connect to a some web page, which runs a reverse lookup service which
can show the connecting IP address.

Note: the following web web page does not exists. To find a service
that is able to display your IP address, do a google search. Let's
say, that you found a fictional service
C<http://www.example.com/showip> and somewhere in the web page it
reads:

        Your IP address is: 212.111.11.10

This is what you need. To automate the lookup from web page, you need
to instruct the program to connect to URL page and tell how to read
the ip from page by using a regular expression. Consult Perl's manual
page C<perlre> if you are unfamiliar with the regular expressions. For
the above fictional service, the options needed would be:

    --urlping         "http://showip.org/?showit.pl"
    --urlping-regexp  "address is:\s+([\d.]+)"
                                  |  ||
                                  |  |+- Read all digits and periods
                                  |  |
                                  |  +- capturing parentheses
                                  |
                                  +- expect any number of whitespaces

NOTE: The text to match from web page is not text/plain, but text/html,
so you must look at the HTML page's sources to match the IP
address correctly without the bold <b> tags etc.

=item B<--urlping URL>

Web page where world known IP address can be read. If you find a Web server
that is running some program, which can show your IP addres, use it. The
example below connects to site and calls CGI program to make show the
connector's IP address. Be polite. Making calls like this too often
may cause putting blocks to your site.

    http://www.dyndns.org/cgi-bin/check_ip.cgi

Be sure to use period of 60 minutes or more with B<--Daemon> option to
not increase the load in the "ping" site and cause admin's to shut
down the service.

=item B<--urlping-dyndns>

Contact to www.dyndns.org service to obtain IP address information. This
is shorthand to more general optiopn B<--urlping>.

=item B<--urlping-linksys [TYPE]>

B<Specialized router option for Linksys products>.

This option connects to Linksys Wireless LAN 4-point router, whose page is
by default at local network address -<http://192.168.1.1/Status.htm>. The
world known IP address (which is provided by ISP) is parsed from that
page. The product is typically connected to the cable or DSL modem. Refer
to routing picture presented previously.

If the default login and password has been changed, options
B<--urlping-login> and B<--urlping-password> must be supplied

For TYPE information, See <http://www.linksys.com/>. Products codes currently
supported include:

 - BEFW11S4, Wireless Access Point Router with 4-Port Switch.
   Page: http://192.168.1.1/Status.htm
 - WRT54GL, Wireless WRT54GL Wireless-G Broadband Router.
   Page: http://192.168.1.1/Status_Router.asp

=item B<--urlping-login LOGIN>

If C<--urlping> web page requires authentication, supply user name for
a secured web page.

=item B<--urlping-password LOGIN>

If C<--urlping> web page requires authentication, supply password for
a secured web page.

=item B<--urlping-regexp REGEXP>

After connecting to page with B<--urlping URL>, the web page is examined for
REGEXP. The regexp must catch the IP to perl match $1. Use non-capturing
parenthesis to control the match as needed. For example this is incorrect:

    --urlping-regexp "(Address|addr:)\s+([0-9.]+)"
                      |                 |
                      $1                $2

The match MUST be in "$1", so you must use non-capturing perl paentheses
for the first one:

    --urlping-regexp "(?:Address|addr:) +([0-9.]+)"
                       |                 |
                       non-capturing     $1

If this option is not given, the default value is to find first word
that matches:

    ([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)

=back

=head2 Miscellaneous options

=over 4

=item B<--debug [LEVEL]>

Turn on debug with optional positive LEVEL. Use this if you want to know
details how the program initiates connection or if you experience trouble
contacting DDNS provider.

=item B<--help>

Print help

=item B<--Help-html>

Print help in HTML format.

=item B<--Help-man>

Print help page in Unix manual page format. You want to feed this output to
B<nroff -man> in order to read it.

=item B<--test [LEVEL]>

Run in test mode, do not actually update anything. LEVEL 1 allows
sending HTTP ping options and getting answers.

=item B<--Test-driver>

This is for developer only. Run internal integrity tests.

=item B<--test-account>

This is for developer only. Uses DYNDNS test account options. All command
line values that set host information or provider are ignored. Refer to
client page at http://clients.dyndns.org/devel/

=item B<--verbose>

Print informational messages.

=item B<--Version>

Print version and contact information.

=back

=head1 README

Perl client for updating a dynamic DNS IP information at supported
providers (see C<--Provider>). Visit the page of the provider and create an
account. Write down the login name, password and host name you registered.

Program has been designed to work under any version of Windows or
Linux, possibly Mac OS included. It may not work under other Unix
variants due to different commands and outputs to get network IP
assignment information. Please see BUGS section how to provide details
to add support to other operating systems.

The dynamic DNS service allows mapping a dynamic IP address to a static
hostname. This way the computer can be refereed by name instead of ever
changing IP address from ISP's pool. The DDNS providers have may have basic
services, like single account and single host name, which may still be free
of charge. Please check the current status form the pages of the providers.

Separate files are used for remembering the last IP address to prevent
updating the same IP address again. This is necessary in order to comply
guidelines of the providers where multiple updates of the same IP address
could cause your domain to be blocked. You should not normally need to
touch the files where the ip addresses are stored.

If you know what you are doing and desperately need a forced update,
delete the IP files and start program with apropriate arguments.
Without the information about previous IP address, program sends a new
update request to the provider.

For windows operating systems, you need to install Perl. There are two
Perl incarnatons: Native Windows version (Activestate Perl) and Cygwin
version. It is recommended that you install Cygwin suite, which
includes Perl from C<http://www.cygwin.com/>. The Cygwin is a Unix
layer running on top of windws and makes it possible to use cron jobs
etc. just like in Linux systems. If you have no prior experience on
Unix/Linux, then the Activestate Perl might be better for Windows.
Activestate includes a Windows installer, but the Perl programs must
be run through Perl interpreter. For Activestate, put programs along
PATH and use command line call with option B<-S> to instruct to search
PATH:

    perl -S dyndns.pl [options]

=head1 EXAMPLES

To check current IP address:

  dyndns.pl --Query [--urlping...]
                    |
                    Select correct option to do the "ping" for IP

Show where the ip file is/would be stored with given connect options.
The option B<--file-default> uses OS's default directory structure.

  dyndns.pl --file-default --Query-ipfile --Provider dyndns \
            --Host xxx.dyndns.org

To upate account information to DDNS provider:

  dyndns.pl --login <login> --password <pass> --Host your.dyndns.org

If you have a cable or DSL and your router can display a web page
containing the world known IP address, you can instruct to "ping"
it. Suppose that router occupies address 192.168.1.1 and page that
displays the world known IP is C<status.html>, and you have to log in
the router using username C<foo> and password C<bar>:

  dyndns.pl --urlping http://192.168.1.1/Status.html \
            --urlping-login foo                      \
            --urlping-pass  bar                      \

If the default regexp does not find IP address from the page, supply
your own match with option B<--urlping-regexp>. In case of doubt, add
option B<--debug 1> and examine the responses. In serious doubt, contact
the maintainer (see option B<--Version>) and send the full debug
output.

Tip: if you run a local web server, provider C<www.dyndns.org> can direct
calls to it. See option C<--Wildcard> to enable `*.your.dyndns.org' domain
delegation, like if it we accessed using `www.your.dyndns.org'.

=head1 CONFIGURATION FILE

Instead of supplying options at command line, the options can be stored to
configuration files. For each DDNS account and different domains, a
separate configuration file must be created. The configuration files are
read with option B<--Config>.

The syntax of the configuration file includes comments that start with (#).
Anything after hash-sign is interpreted as comment. Values are set in KEY =
VALUE fashion, where spaces are non-significant. Keys are not case
sensitive, but values are.

Below, lines marked with [default] need only be set if the default value
needs to be changed. Lines marked with [noip] or [dyndns] apply to only
those providers' DDNS accounts. Notice that some keys, like C<host>, can
take multple values seprated by colons. On/Off options take values [1/0]
respectively. All host name values below are fictional.

    # /etc/dyndns/dyndns.conf

    #  Set to "yes" to make this configuration file excluded
    #  from updates.

    disable  = no       # [default]

    ethernet = eth0     # [default]
    group    = mygourp  # [noip]
    host     = host1.dyndns.org, host1.dyndns.org

    #   If you route mail. See dyndns.org documentation for details
    #   how to set up MX records. If you know nothing about DNS/BIND
    #   Don't even consider using this option. Misuse or broken
    #   DNS at your end will probably terminate your 'free' dyndns contract.

    mxhost   = mxhost.dyndns.org

    #   Details how to get the world known IP address, in case the standard
    #   Linux 'ifconfig' or Windows 'ipconfig' programs cannot be used. This
    #   interests mainly Cable, DSL and router owners. NOTE: You may
    #   not use all these options. E.g. [urlping-linksys4] is alternate
    #   to [urlping] etc. See documentation.

    urlping-linksys  = BEFW11S4
    urlping-login    = joe
    urlping-password = mypass

    urlping          = fictional.showip.org
    urlping-regexp   = (Address|addr:)\s+([0-9.]+)

    #   Where IPs are stored. Directory name or Directory name with
    #   additional file prefix. The directory part must exist. You could
    #   say 'file = /var/log/dyndns/' but that's the default.

    file     = default              # Use OS's default location

    #   The DDNS account details

    login    = mylogin
    password = mypass
    provider = dyndns               # [default]
    proxy    = myproxy.myisp.net    # set only if needed for HTTP calls

    #   Hou need this option only if you have multiple ethernet cards.
    #   After which regexp the IP number appers in ifconfig(1) listing?

    regexp   = .*0xffffffff.*?inet

    #   What account are you using? Select 'dyndns|statdns|custom'

    system   = dyndns               # Provider [dyndns] only

    #   Yes, delegate all *.mydomain.dyndns.org calls

    wildcard = 1

    # End of cnfiguration file

See the details of all of these options from the corresponding command line
option descriptions. E.g. option 'ethernet' in configuration file
corresponds to B<--ethernet> command line option. The normal configuration
file for average user would only include few lines:

    #   /etc/dyndns/myhost.dyndns.org.conf

    host             = myhost.dyndns.org
    file             = default      # Use OS's default location
    login            = mylogin
    password         = mypassword
    provider         = dyndns
    system           = dyndns       # or 'statdns'
    wildcard         = 1            # Delegate *.mydomain.dyndns.org

    # End of cnfiguration file

TODO (write Debian daemon scripts) FIXME:

    update-rc.d dyndns start 3 4 5 6    # Debian

=head1 SUPPORT REQUESTS

For new Operating System, provide all relevant commands, their options,
examples and their output which answer to following questions. The items in
parentheses are examples from Linux:

    - How is the OS detected? Send result of 'id -a', or if file/dir
      structure can be used to detect the system. In Lunux the
      existence of /boot/vmlinuz could indicate that "this is a Linux
      OS".
    - What is the command to get network information (commandlike 'ifconfig')
    - Where are the system configuration files stored (in directory /etc?)
    - Where are the log files stored (under /var/log?)

To add support for routers that can be connected through HTTP protocol
or with some other commands, please provide connection details and
full HTTP response:

  lynx -dump http://192.168.1.0/your-network/router/page.html

=head1 TROUBLESHOOTING

1. Turn on B<--debug> to see exact details how the program runs and
what HTTP requests are sent and received.

2. Most of the <--Query> options can't be used standalone. Please see
documentation what additional options you need to supply with them.

=head1 ENVIRONMENT

=over 4

=item B<TMPDIR>

Directory of temporary files. Defaults to system temporary dir.

=back

=head1 FILES

Daemon startup file

    /etc/default/dyndns

In Linux the syslog message files are:

    /etc/syslog.conf         daemon.err daemon.warning
    /var/log/daemon.log

There is no default location where program would search for configuration
files. At installation, configuration examples are put in directory
C</etc/dyndns/examples>. It is recommended that the examples are modified
and copied one directorory up in order to use option B<--Config
/etc/dyndns/*>.

If program is run with Windows Activestate Perl, the log file is stored to
file C<C:/syslog.txt>.

=head1 SEE ALSO

syslog(3), Debian package ddclient(1)

See other dyndns.org clients at http://clients.dyndns.org/

=head1 BUGS

=head2 Cygwin syslog

There is no syslog daemon in Cygwin. The Cygwin POSIX emulation layer takes
care about syslog requests. On NT and above systems it logs to the
Windows's event manager, on Win9x and ME a file is created in the root of
drive C<C:>. See message <http://cygwin.com/ml/cygwin/2002-10/msg00219.html>
for more details.

You can see the entries in W2K Start => Settings => Administrative Tools
=> Computer Management: [ System Tools / Event Viewer / Application ]

=head2 Debugging errors

Please use option B<--debug 2> and save the result. Contact maintainer if
you find bugs or need new features.

=head1 AVAILABILITY

http://freshmeat.net/projects/perl-dyndns

=head1 STANDARDS

The client specification is at
https://www.dyndns.com/developers/specs/

=head1 SCRIPT CATEGORIES

C<CPAN/Administrative>
C<CPAN/Networking>

=head1 PREREQUISITES

HTTP::Headers
HTTP::Request::Common
LWP::UserAgent
LWP::Simple
Sys::Syslog

=head1 COREQUISITES

None.

=head1 OSNAMES

C<any>

=head1 AUTHOR

Copyright (C) 1999-2008 Jari Aalto. All rights reserved. This program
is free software; you can redistribute and/or modify program under the
terms of GNU General Public license v2 or later.

This documentation may be distributed subject to the terms and
conditions set forth in GNU General Public License v2 or later (GNU
GPL); or, at your option, distributed under the terms of GNU Free
Documentation License version 1.2 or later (GNU FDL).

=cut

sub Help ( ; $ $ )
{
    my $id   = "$LIB.Help";
    my $msg  = shift;  # optional arg, why are we here...
    my $type = shift;  # optional arg, type

    if ( $type eq -html )
    {
        pod2html $PROGRAM_NAME;
    }
    elsif ( $type eq -man )
    {
        eval "use Pod::Man";
        $EVAL_ERROR  and  die "$id: Cannot generate Man $EVAL_ERROR";

        my %options;
        $options{center} = 'Perl Dynamic DNS Update Client';

        my $parser = Pod::Man->new(%options);
        $parser->parse_from_file ($PROGRAM_NAME);
    }
    else
    {
        pod2text $PROGRAM_NAME;
    }

    if ( defined $msg )
    {
        print $msg;
        exit 1;
    }

    exit 0;
}

# }}}
# {{{ Command line arguments

# ****************************************************************************
#
#   DESCRIPTION
#
#       Return version string
#
#   INPUT PARAMETERS
#
#       none
#
#   RETURN VALUES
#
#       string
#
# ****************************************************************************

sub Version ()
{
    "$VERSION";
}

sub VersionInfo ()
{
    Version();
}

# ************************************************************** &args *******
#
#   DESCRIPTION
#
#       Read and interpret command line arguments ARGV. Sets global variables
#
#   INPUT PARAMETERS
#
#       none
#
#   RETURN VALUES
#
#       none
#
# ****************************************************************************

sub HandleCommandLineArgsMain ()
{
    my    $id = "$LIB.HandleCommandLineArgsMain";

    local $ARG;

    use vars qw
    (
        $OPT_QUERY_IP_CHANGED

        $OPT_DAEMON
        $OPT_IGNORE_CONFIG
        $OPT_ETHERNET
        $OPT_FORCE
        $OPT_GROUP
        @OPT_HOST
        $OPT_HOSTMX
        $OPT_HTTP_PING
        $OPT_HTTP_PING_DYNDNS
        $OPT_HTTP_PING_LINKSYS
        $OPT_HTTP_PING_LOGIN
        $OPT_HTTP_PING_PASSWORD
        $OPT_HTTP_PING_REGEXP
        $OPT_IP_FILE
        $OPT_LOGIN
        $OPT_MX
        $OPT_OFFLINE
        $OPT_PASS
        $OPT_PROVIDER
        $OPT_PROXY
        $OPT_QUERY
        $OPT_QUERY_IP_FILE
        $OPT_QUERY_IP_SAVED
        $OPT_REGEXP
        $OPT_SYSTEM
        $OPT_WILDCARD

        $debug
        $verb
        $test
        $DAEMON_MIN

        @OPT_CONFIG_FILE
        %CONFIG_FILE_MAP_TABLE
        @CONFIG_COMMAND_LINE_TABLE

        @REQUIRED_UPDATE_OPTION_LIST
    );

    $DAEMON_MIN = 5;

    #   What comand line options to preserve, if configuration file
    #   does not define the value.

    @CONFIG_COMMAND_LINE_TABLE = qw
    (
         OPT_DAEMON
         OPT_ETHERNET
         OPT_HTTP_PING
         OPT_HTTP_PING_DYNDNS
         OPT_HTTP_PING_LINKSYS4
         OPT_HTTP_PING_LOGIN
         OPT_HTTP_PING_PASSWORD
         OPT_HTTP_PING_REGEXP
         OPT_PROXY
    );

    #   Allowed values in configuration file

    %CONFIG_FILE_MAP_TABLE =
    (
        daemon          => '$OPT_DAEMON'
        , ethernet      => '$OPT_ETHERNET'
        , group         => '$OPT_GROUP'
        , host          => '@OPT_HOST'
        , mxhost        => '$OPT_HOSTMX'

        , urlping               => '$OPT_HTTP_PING'
        , 'urlping-dyndns'      => '$OPT_HTTP_PING_DYNDNS'
        , 'urlping-linksys'     => '$OPT_HTTP_PING_LINKSYS'
        , 'urlping-login'       => '$OPT_HTTP_PING_LOGIN'
        , 'urlping-password'    => '$OPT_HTTP_PING_PASSWORD'
        , 'urlping-regexp'      => '$OPT_HTTP_PING_REGEXP'

        , file          => '$OPT_IP_FILE'
        , login         => '$OPT_LOGIN'
        , mxoption      => '$OPT_MX'
        # , offline     => '$OPT_OFFLINE'
        , password      => '$OPT_PASS'
        , provider      => '$OPT_PROVIDER'
        , proxy         => '$OPT_PROXY'
        , regexp        => '$OPT_REGEXP'
        , system        => '$OPT_SYSTEM'

        # Provide synonyms
        , wildcard      => '$OPT_WILDCARD'
        , disable       => '$OPT_IGNORE_CONFIG'
    );

    #   Minumum required options, which must be set, before anything
    #   ic connected to provider.

    @REQUIRED_UPDATE_OPTION_LIST =
    (
        '@OPT_HOST'
        , '$OPT_PASS'
        , '$OPT_LOGIN'
        , '$OPT_SYSTEM'
        , '$OPT_PROVIDER'
        , '$OPT_IP_FILE'
    );

    $debug = -1;
    $test  = -1;

    # .................................................... read args ...

    my ( $help, $helpHTML,$helpMan, $version, $testAccount, $testDriver );
    my ( $ipfileDefault, $wildcard, $mx, $offline );


    if  ( grep /--debug|^-d\b/, @ARGV )
    {
        print "$id: ARGV: @ARGV\n";
    }

    Getopt::Long::config( qw
    (
        no_ignore_case
        require_order
    ));

    GetOptions      # Getopt::Long
    (
          "h|help"              => \$help
        , "Help-html"           => \$helpHTML
        , "Help-man"            => \$helpMan

        , "debug:i"             => \$debug
        , "Config=s@"           => \@OPT_CONFIG_FILE
        , "Daemon:i"            => \$OPT_DAEMON
        , "ethernet=s"          => \$OPT_ETHERNET
        , "Host=s@"             => \@OPT_HOST

        , "file=s"              => \$OPT_IP_FILE
        , "f|file-default"      => \$ipfileDefault
        , "Force"               => \$OPT_FORCE

        , "group=s"             => \$OPT_GROUP

        , "login=s"             => \$OPT_LOGIN

        , "mxhost=s"            => \$OPT_HOSTMX
        , "Mx-option"           => \$mx

        , "proxy=s"             => \$OPT_PROXY
        , "Provider=s"          => \$OPT_PROVIDER

        , "regexp=s"            => \$OPT_REGEXP
        , "system=s"            => \$OPT_SYSTEM

        , "Offline"             => \$offline

        , "password=s"          => \$OPT_PASS

        , "Q|Query"             => \$OPT_QUERY
        , "Query-ipfile"        => \$OPT_QUERY_IP_FILE
        , "Query-ipsaved"       => \$OPT_QUERY_IP_SAVED
        , "Query-ipchanged:s"   => \$OPT_QUERY_IP_CHANGED


        , "test:i"              => \$test
        , "Test-driver"         => \$testDriver
        , "Test-account"        => \$testAccount

        , "urlping=s"           => \$OPT_HTTP_PING
        , "urlping-regexp=s"    => \$OPT_HTTP_PING_REGEXP
        , "urlping-login=s"     => \$OPT_HTTP_PING_LOGIN
        , "urlping-password=s"  => \$OPT_HTTP_PING_PASSWORD

        , "urlping-dyndns"      => \$OPT_HTTP_PING_DYNDNS
        , "urlping-linksys:s"   => \$OPT_HTTP_PING_LINKSYS

        , "verbose"             => \$verb
        , "Version"             => \$version

        , "Wildcard"            => \$wildcard

    );

    $version                and print( VersionInfo() . "\n"), exit;

    $help                   and Help();
    $helpHTML               and Help undef, -html;
    $helpMan                and Help undef, -man;
    $testDriver             and TestDriver();

    $debug = 1              if $debug == 0;
    $debug = 0              if $debug < 0;

    $test = 1               if $test == 0;
    $test = 0               if $test < 0;

    $verb = 1               if $debug;
    $verb = 1               if $test;

    $OPT_QUERY = 1          if defined $OPT_QUERY;
    $OPT_FORCE = 1          if defined $OPT_FORCE;
    $OPT_WILDCARD = 'ON'    if defined $wildcard;
    $OPT_MX       = 'YES'   if defined $mx;
    $OPT_OFFLINE  = 'YES'   if defined $offline;

    if ( $ipfileDefault )
    {
        $OPT_IP_FILE = SystemLogDir();
	$debug  and   print "$id: OPT_IP_FILE = $OPT_IP_FILE\n";
    }

    #   Because this is defined as ':s', this string will be "" if
    #   User supplies option without arguments. We must give
    #   '-undef' to signify that this option has not been used at all
    #   on command line.

    unless ( defined $OPT_QUERY_IP_CHANGED )
    {
        $OPT_QUERY_IP_CHANGED = '-undef'
    }
    else
    {
        $OPT_QUERY_IP_CHANGED = 'query'  unless $OPT_QUERY_IP_CHANGED;

        unless ( @OPT_CONFIG_FILE  or  $OPT_IP_FILE )
        {
            die "$id: Need more details, add option --file* or --Config. "
                , "If you use router, then you also need some "
                , "--urlping* option"
                ;
        }
    }

    $OPT_QUERY_IP_FILE    = 1 if defined $OPT_QUERY_IP_FILE;
    $OPT_QUERY_IP_SAVED   = 1 if defined $OPT_QUERY_IP_SAVED;
    $OPT_QUERY            = 1 if defined $OPT_QUERY;

   if ( ($OPT_QUERY_IP_FILE || $OPT_QUERY_IP_SAVED)
         and
	 not defined @OPT_HOST
       )
    {
        warn "$id: Option --Host should be included with queries.";
    }

    if ( defined $OPT_DAEMON )
    {
        $debug  and  print "$id: OPT_DAEMON was set to $OPT_DAEMON\n";

        my $min = $DAEMON_MIN;
        $OPT_DAEMON = TimeValue($min)  if  $OPT_DAEMON < $min;

        $debug  and  print "$id: DAEMON is using $OPT_DAEMON minutes\n";
    }

    if ( defined $testAccount )
    {
        $OPT_IP_FILE = SystemLogDir();

        # See https://www.dyndns.org/developers/testaccount.html

        if ( ! defined $OPT_SYSTEM )
        {
            die "--system option is missing";
        }

        $OPT_LOGIN = "test";
        $OPT_PASS  = "test";
        @OPT_HOST  = ("test.dyndns.org");

        if ( $OPT_SYSTEM eq "statdns" )
        {
            $OPT_LOGIN = "test";
            $OPT_PASS  = "test";
            @OPT_HOST  = ("test-static.dyndns.org");
        }
        elsif ( $OPT_SYSTEM eq "custom" )
        {
            $OPT_LOGIN = "test";
            $OPT_PASS  = "test";
            @OPT_HOST  = ("test1.customtest.dyndns.org");
        }
    }
}

# }}}
# {{{ Logging

# ****************************************************************************
#
#   DESCRIPTION
#
#       Write to syslog.
#
#   INPUT PARAMETERS
#
#       $cmd        Command with options (with initial arguments, like 'ls -l')
#       @args       Additional arguments
#
#   RETURN VALUES
#
#       true        if succeeded.
#
# ****************************************************************************

sub RunCommand ($ @)
{
    my $id              = "$LIB.RunCommand";
    my ($cmd, @args)    = @ARG;

    #   We cannot 'syslog' these messages, because if this fails,
    #   syslog isn't callable either.

    unless ( $cmd )
    {
        warn "$id: COMMAND is empty" unless $OPT_DAEMON;
        return;
    }

    local *PIPE;

    unless ( open PIPE, "| $cmd" )
    {
        warn "$id: cannot start $cmd" unless $OPT_DAEMON;
        return;
    }

    my $status = 1;

    if ( @args )
    {
        unless( print PIPE @args )
        {
            warn "$id: cannot write [@args] to PIPE [$cmd]" unless $OPT_DAEMON;
            $status = 0;
        }
    }

    unless ( close PIPE )
    {
        warn "$id: cannot close PIPE [$cmd]" unless $OPT_DAEMON;
    }

    $status;
}


# ****************************************************************************
#
#   DESCRIPTION
#
#       Write tog to syslog.
#
#   INPUT PARAMETERS
#
#       $msg
#
#   RETURN VALUES
#
#       None.
#
# ****************************************************************************

sub LogSyslog ($)
{
    my $id    = "$LIB.LogSyslog";
    my ($msg) = @ARG;

    $debug  and  print "$id: INPUT '$msg'\n";

    #  syslog() calls dies unless there is message.
    return   unless $msg;

    my $date     = DateISO();
    my $prefix   = "$LIB\[$PID]";
    my $facility = 'daemon';
    my $priority = 'warning';
    my $pString  = "$facility.$priority";

    $priority = 'err'  if  $msg =~ /ERROR|PANIC/;

    #   Maybe remove these, they are for consele printing, syslog uses
    #   priority levels.

    # $msg =~ s,\[(WARN|ERROR|PANIC)\]\s*,,;

    my $syslog = grep /syslog/i, @FEATURE_LIST_MODULES;

    if ( $CYGWIN )
    {
        #   Syslog Perl module does not work under Cygwin

        my $cmd = "syslog -p$pString -t$prefix";

        $debug  and  print "$id: Cygwin command: $cmd '$msg'\n";

        RunCommand $cmd, $msg;
    }
    elsif ( $WIN32 )
    {
        #   Native Windows perl (Activestate)

        my $dir  = $WIN32_SYSLOG_DIR;
        my $path = $WIN32_SYSLOG_PATH;
        $dir     =~ s,/$,,;
        $dir     =~ s,\\,/,g;
        my $err  = "Directory does not exist: $dir" unless -d $dir;

        if ( -d $dir )
        {
            chomp $msg;
            FileWrite( $path, -append, "$date $prefix $pString $msg\n");
        }
    }
    elsif ( $syslog )
    {
        my $err;

        LOOP:
        {
            my $s = "Sys::Syslog::";

            unless( openlog( "dyndns", "pid", $facility) )
            {
                $err = "${s}openlog error [$ERRNO]"; last LOOP;
            }

            unless ( syslog( "$priority", $msg ) )
            {
                $err = "${s}syslog error [$ERRNO]"; last LOOP;
            }

            unless ( closelog() )
            {
                # Manual page does not say that error is possible
                # $err = "${s}closelog error [$ERRNO]"; last LOOP;
            }
        }

        $debug  and  print "$id: used Perl module. Status [$err]\n";
    }
    else  # no syslog
    {
	$msg .= "\n" unless m,\n\Z,;
	print STDERR "$date $prefix $pString $msg";
    }
}

# ****************************************************************************
#
#   DESCRIPTION
#
#       Write tog to syslog if running in DAEMON mode. Otherwise print
#       standard warn().
#
#   INPUT PARAMETERS
#
#       $msg
#       $line       [optional] Location of the error in this program.
#
#   RETURN VALUES
#
#       None.
#
# ****************************************************************************

sub Log ($;$)
{
    my ($msg, $line) = @ARG;

    $msg =~ /\n$/  or  $msg .= "\n";

    if ( $line )
    {
        $msg .= " $PROGRAM_NAME at line $line\n";
    }

    if ( $OPT_DAEMON )
    {
        LogSyslog $msg;
    }
    else
    {
        print STDERR $msg;
    }
}

# }}}
# {{{ Variables

# ****************************************************************************
#
#   DESCRIPTION
#
#       Convert tokens 7m, 2h, 3d into minutes. Die if value is not numeric.
#
#   INPUT PARAMETERS
#
#       none
#
#   RETURN VALUES
#
#       none
#
# ****************************************************************************

sub TimeValue ($)
{
    my $id = "$LIB.TimeValue";

    local ($ARG) = (@ARG);

    if ( /^(\d+)([mhd]?)$/ )
    {
        $ARG = $1;
        my $spec = $2  if defined $2;

        $debug  and  print "$id: val [$ARG] spec [$spec]\n";

        my $factor = 1;
        $factor = 60        if $spec =~ /h/i;
        $factor = 60 *24    if $spec =~ /d/i;

        $ARG *= $factor;

        $debug  and  print "$id: val [$ARG] factor [$factor]\n";
    }
    else
    {
        die "$id: Not a recognized time value [$ARG]. Try 2m, 2d, 2h";
    }

    $ARG;
}

# ***************************************************************************
#
#   DESCRIPTION
#
#       Check that set variables make sense. Programs dies if there are
#       errors.
#
#   INPUT PARAMETERS
#
#       $file       [optional] File name being checked (conf file)
#
#   RETURN VALUES
#
#       None
#
# ****************************************************************************

sub VariableCheckValidity (; $)
{
    my $id      = "$LIB.VariableCheckValidity";
    my ($file)  = @ARG;

    my $msg = "[at $file]"  if $file;

    $debug  and  print "$id:\n";

    sub OnOff($$$);
    local *OnOff = sub ($$$)
    {
        my ($var, $val, $arrRef) = @ARG;

        $debug  and  print "$id.OnOff: $var [$val]\n";

        if ( $val =~ /on/i  or  $val > 0 )
        {
            $val = (@$arrRef)[0];
        }
        else
        {
            $val = (@$arrRef)[1];
        }

        VariableEval( $var, $val );
    };

    #  default values

    $OPT_ETHERNET = "eth0"      unless defined $OPT_ETHERNET;
    $OPT_SYSTEM   = "dyndns"    unless defined $OPT_SYSTEM;
    $OPT_PROVIDER = "dyndns"    unless defined $OPT_PROVIDER;

    OnOff '$OPT_WILDCARD', $OPT_WILDCARD, [qw(ON OFF)];
    OnOff '$OPT_MX'      , $OPT_MX      , [qw(YES NO)];
    OnOff '$OPT_OFFLINE' , $OPT_OFFLINE , [qw(YES NO)];

    if ( not $test
         and  not $OPT_QUERY
         and  not $OPT_QUERY_IP_FILE
         and  not $OPT_QUERY_IP_SAVED
         and  not $OPT_QUERY_IP_CHANGED
       )
    {
        unless ( $OPT_LOGIN  and  $OPT_PASS  and  @OPT_HOST)
        {
            die "$id: ${msg}Need minimum options: "
                . "--login $OPT_LOGIN --pass $OPT_PASS --Host @OPT_HOST";
        }
    }

    if ( defined          $OPT_HTTP_PING_PASSWORD
         and not defined  $OPT_HTTP_PING_LOGIN
       )
    {
        #  E.g. www.linksys.com router doesn't care about login name,
        #  just the password.

        $verb  and print "$id: ${msg}--urlping-login not set. Login is [login]";
        $OPT_HTTP_PING_LOGIN = "login";
    }

    if ( defined          $OPT_HTTP_PING_LOGIN
         and not defined  $OPT_HTTP_PING_PASSWORD
       )
    {
        die "--urlping-passwrd not set.";
    }

    unless ( $OPT_SYSTEM =~ /dyndns|statdns|custom/ )
    {
        die "$id: ${msg}Invalid --system value: [$OPT_SYSTEM]. See --help.";
    }

    if ( $OPT_HTTP_PING and
         (
            $OPT_HTTP_PING_LINKSYS or
            $OPT_HTTP_PING_DYNDNS
         )
       )
    {
        die "$id: ${msg}Choose only one --urlping* option.";
    }

    if ( $OPT_HTTP_PING  and  not $OPT_HTTP_PING_REGEXP )
    {
        # Cable and DSL router say that it is a WAN IP, not the LAN ip.
        # this is like reading from page:
        #
        # LAN:
        #      MAC Address: zzzzz
        #    Å† IP Address: 192.168.1.1
        # WAN:x
        #      MAC Address: zzzzz
        #    Å† IP Address: xxx.xxx.xxx.xxx    << READ THIS

        my $ip    = '([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)';
        my $maybe = '(?i)(?:WAN.+?IP\s+Address.+?)';

        $OPT_HTTP_PING_REGEXP = $maybe . $ip;

        $verb  and  Log "$id: [WARN] ${msg}--urlping-regexp is missing, "
                          . "using default regexp $OPT_HTTP_PING_REGEXP";
    }
}

# ***************************************************************************
#
#   DESCRIPTION
#
#       Check that enough variables hold values in order to start doing
#       IP update request.
#
#   INPUT PARAMETERS
#
#       $file       [optional] File name being checked (conf file)
#
#   RETURN VALUES
#
#       false       If there is not enough variables.
#
# ****************************************************************************

sub VariableCheckMinimum (; $)
{
    my $id      = "$LIB.VariableCheckMinimum";
    my ($file)  = @ARG;

    my $msg     = " at $file "  if $file;
    my $stat    = 1;

    $debug  and  print "$id: $file\n";

    {
        no strict;              # Due to "eval" in here.

        for my $var ( @REQUIRED_UPDATE_OPTION_LIST )
        {
            my $result = '';
            my $eval   = '$result = ' . $var;

            eval $eval;

            $debug  and  print  "$id: EVAL $eval => $result\n";

            unless ( $result )
            {
                $verb  and  Log "$id: [ERROR]${msg}$var is not set\n";
                $stat = 0;
            }
        }
    }

    $debug  and  print "$id: return [$stat]\n";

    $stat;
}

# }}}
# {{{ Misc functions

# ****************************************************************************
#
#   DESCRIPTION
#
#       Set perl variables
#
#   INPUT PARAMETERS
#
#       $variable       This is string like '$var' or '@list'.
#       $value          This is string. Value to set to.
#
#   RETURN VALUES
#
#       None.
#
# ****************************************************************************

sub VariableEval ($;$)
{
    my $id = "$LIB.VariableEval";
    my($variable, $value) = @ARG;

    no strict;
    my ($type, $name) = $variable =~ /^(.)(.*)/;

    if ( $type eq '@' )
    {
        $debug  > 1 and  print "$id: \@$name = $value\n";
        @{$name} = $value;
    }
    else
    {
        $debug  > 1 and  print "$id: \$$name = $value\n";
        ${$name} = $value;
    }
}

# ****************************************************************************
#
#   DESCRIPTION
#
#       Parse sublevel 1 regexp form input string.
#
#   INPUT PARAMETERS
#
#       $string
#       $regexp
#
#   RETURN VALUES
#
#       MATCH      At grouping expression 1
#
# ****************************************************************************

sub StringRegexpMatch ($$)
{
    my $id            = "StringRegexpMatch";
    my($str, $regexp) = @ARG;
    my $ret = '';

    if ( $str =~ /$regexp/ )
    {
        $ret = $1;
    }

    $debug   and  print "$id: return [$ret] regexp [$regexp] \n";

    $ret;
}

# ****************************************************************************
#
#   DESCRIPTION
#
#       Find OS's temporary directory
#
#   INPUT PARAMETERS
#
#       none
#
#   RETURN VALUES
#
#       $dir        If one found
#
# ****************************************************************************

sub TempDir ()
{
    my $id  = "$LIB.TempDir";

    my $ret;

    for my $try ( $TMPDIR, qw(/tmp c:/temp c:/) )
    {
        if ( $try  and  -d $try )
        {
            $ret = $try;
            last;
        }
    }

    if ( not $ret  or  not -d $ret )
    {
        die "$id: [FATAL] Cannot set temporary directory. Set TMPDIR.";
    }

    $debug  and  print "$id: $ret";

    $ret;
}

# ****************************************************************************
#
#   DESCRIPTION
#
#       Try to guess system's log directory. In windows, use %WINDIR%
#       or %SYSTEMROOT% and in Linux and Unix this usually if /var/log
#
#   INPUT PARAMETERS
#
#       none
#
#   RETURN VALUES
#
#       $dir        If one found
#
# ****************************************************************************

sub SystemLogDir ()
{
    my $id  = "$LIB.SystemLogDir";
    my $ret = '';

    my $root;

    if ( not $WIN32  and  $EUID == 0 )
    {
	$root = "yes";
    }

    if ( -d '/var/log'   and ($WIN32 or $root) )
    {
	#  Under Win32/Cygwin this directory may exist, but user
	#  does not have permission to it under *nix.

        $ret = '/var/log';

        #   See if thee is subdirectory, created by this package's
        #   install phase (in case user did run it)

        my $try = "$ret/dyndns";
        $ret = $try    if -d $try;
    }
    elsif ( $WIN32 )
    {
        #  Don't try to use these variables in any other system,
        #  even if they were set. That's why if-case for Win32.

        if ( defined  $SYSTEMROOT  and  -d $SYSTEMROOT )
        {
            $ret = $SYSTEMROOT;
        }
        elsif ( defined  $WINDIR  and  -d $WINDIR )
        {
            $ret = $WINDIR;
        }
        elsif ( -d "C:/" )
        {
            $ret = "C:/"
        }
        else
        {
            die "$id: [FATAL] This system does not have WINDIR ?";
        }
    }
    elsif (not $root)
    {
	$ret = "$HOME"      if  -d "$HOME";
	$ret = "$HOME/tmp"  if  -d "$HOME/tmp";
    }
    else
    {
        Log "$id: [WARN] $OSNAME not recognized see --help and section BUGS"
    }

    $ret =~ s,[/\\]$,,;      # Delete trailing slash
    $ret =~ s,\\,/,g;        # convert to forward slashes.

    if ( $ret  and  not -d $ret )
    {
        my $try = TempDir();

        Log "$id: [WARN] No such directory [$ret]. Do you have permissions? "
            . "Using backup directory [$try]"
            ;

        $ret = $try;
    }

    $debug  and  print "$id: return [$ret]\n";

    unless ( $ret )
    {
        die "$id: [FATAL] Nothing to return.";
    }

    $ret;
}

# ****************************************************************************
#
#   DESCRIPTION
#
#       Process each config file option and map them to global
#       variables. Global hash %CONFIG_FILE_MAP_TABLE provides mappings
#       from configuration variable to internal global variables.
#
#   INPUT PARAMETERS
#
#       \%hash      Reference to hash, key => value
#       \%global    Global values given on command line. Used of configuration
#                   file does not define these.
#       $file       [optional] Used for error message if HASH is empty.
#
#   RETURN VALUES
#
#       none        Globals variables are set (See HandleCommandLineArgs)
#
# ****************************************************************************

sub ConfigFileProcess (%)
{
    my $id      = "$LIB.ConfigFileProcess";
    my %arg     = @ARG;
    my %hash    = %{ $arg{-hash}   };
    my %global  = %{ $arg{-global} };
    my $file    = $arg{-file};

    my %map  = %CONFIG_FILE_MAP_TABLE;

    unless ( %hash )
    {
        Log "$id: [WARN] No configuration settings to process from [$file]";
        return;
    }

    $debug  and  print "$id: Clearing variables.\n";

    while ( my($dummy, $var) = each %map )
    {
        VariableEval $var;
    }

    $debug  and  print "$id: Setting global values.\n";

    if ( %global )
    {
        no strict;
        while ( my($var, $val) = each %global )
        {
            $debug > 1  and  printf "$id: GLOBAL $var = %s\n", $val;
            ${$var} = $val;
        }
    }

    $debug  and  print "$id: Evaluating configuration values.\n";

    my $ret = 1;

    while ( my($key, $val) = each %hash )
    {
        $key =~ s/(.*)/\L$1/;       # case insensitive keys.

        unless ( exists $map{$key} )
        {
            Log "$id: [WARN] unrecognized option in file $file\n";
            next;
        }

        my $variable = $map{$key};

        $debug  and  print "$id: config $key [$variable] = $val\n";

        #  handle option --file-default

        if ( $key eq 'file'  and  $val eq 'default' )
        {
            $val = SystemLogDir();
        }

        VariableEval $variable, $val;
    }

    $debug  and  print "$id: return [$ret]\n";

    return $ret;
}

# ****************************************************************************
#
#   DESCRIPTION
#
#       Parse configuration file content. Comments start with '#'. The syntax
#       is simple. Variable names are not case sensitive.
#
#           variable = value
#
#   INPUT PARAMETERS
#
#       $content
#
#   RETURN VALUES
#
#       %hash       variable => value
#
# ****************************************************************************

sub ConfigFileParse ($)
{
    my $id       = "$LIB.ConfigFileRead";
    local ($ARG) = @ARG;

    $debug  and  print "$id: INPUT START\n${ARG}INPUT STOP\n";

    my %hash;

    while ( m,^\s*([^#\r\n\t\f]+)\s*=\s*([^#\r\n\t\f]+),gmxi )
    {
        my $key = $1;
        my $val = $2;

        #   Delete trailing spaces
        $key =~ s/\s+$//;
        $val =~ s/\s+$//;

        $debug  and  print "$id: [$key] => [$val]\n";

        $hash{ $key } = $val;
    }

    %hash;
}

# ****************************************************************************
#
#   DESCRIPTION
#
#       Read configuration file and set global variables according to it.
#
#   INPUT PARAMETERS
#
#       $file
#
#   RETURN VALUES
#
#       boolean         Return false, if file should not be processed.
#
# ****************************************************************************

sub ConfigFileRead ($)
{
    my $id     = "$LIB.ConfigFileRead";
    my ($file) = @ARG;

    #    Perl does not know $HOME or tilde(~) filenames without a glob.

    my %globalHash;

    #   Preserve global values if they are not overriden in configuration
    #   files

    {
	no strict;
	for my $name ( @CONFIG_COMMAND_LINE_TABLE )
	{
	    if ( defined ${$name} )
	    {
		$globalHash{ $name } = ${$name};
		$debug > 1  and  printf "$id: GLOBAL $name = %s\n", ${$name};
	    }
	}
    }

    my $expanded;

    unless ( -f $file )
    {
        $expanded = glob $file;
        $file     = $expanded;
    }

    $debug  and  print "$id: Reading [$file] which expands to [$expanded]\n";

    my $content = join '', FileRead( $file);
    my %hash    = ConfigFileParse $content;

    my $ret = 1;

    if ( $hash{disable} =~ /yes|1/i )
    {
        $debug  and  print "$id: skipped. "
                         , "OPT_IGNORE_CONFIG was found from $file\n";

        #   Configuration file option 'disable' was set
        $ret = 0;
        last;
    }
    else
    {
        ConfigFileProcess -hash     => \%hash
                        , -global   => \%globalHash
                        , -file     => $file
                        ;
    }

    return $ret;
}

# ****************************************************************************
#
#   DESCRIPTION
#
#       Return file where to save the IP address based on values like
#       ethernet card, provider and update system type.
#
#   INPUT PARAMETERS
#
#       $prefix     This is prepended to the beginning of the filename
#                   It can be a directory or directory + prefix.
#       $absolute   if set, then the PREFIX is considered absolute
#                   if it's not a directory, do not try to add
#                   ethernet strings etc.
#       $hostRef    List of hosts whose IP addresses are in question.
#
#   RETURN VALUES
#
#       $file
#
# ****************************************************************************

sub IPfileNamePath (; $$$)
{
    my $id       = "IPfileNamePath";
    local $ARG   = shift;
    my $abs      = shift;
    my $hostRef  = shift;

    $debug  and  print "$id: INPUT arg [$ARG] abs [$abs]\n";

    $ARG    = ''        unless defined $ARG;
    my $ret = '';

    if ( $ARG )
    {
        #   Add trailing slash if needed. Because the value
        #   is glued to other variables

        if ( -d  )
        {
            $ARG .= '/'  unless  m,/$,;

            #   This was a directory, not a absolute path name. Clear flag.

            $abs = '';
        }
    }

    if ( $ARG  and  not $abs )
    {
        #   The name will contain the *-HOSTA-HOSTB-HOSTC.log if multiple
        #   hosts are updated in batch. If separately, then there will
        #   be different files: *{-HOSTA,-HOSTB,-HOSTC}.log

        $debug  and  print "$id ---> making filename\n";

        my $HOST = '';

        if ( $hostRef )
        {
            my @host = @$hostRef;

            $debug  and  print "$id: \@host = @host\n";

            @host  and  $HOST = join '-', @host;
        }

        #   Last saved IP address is in this file
        #   For multiple network cards, store each one for separate card.
        #   Updates for 'statdns', are different than for 'dyndns'

        Log "$id: [ERROR] OPT_ETHERNET is empty" unless $OPT_ETHERNET;
        Log "$id: [ERROR] OPT_PROVIDER is empty" unless $OPT_PROVIDER;

        my $ethernet = $OPT_ETHERNET . '-'  if $OPT_ETHERNET;

        my $provider = 'noprovider-';
           $provider = $OPT_PROVIDER . '-'  if $OPT_PROVIDER;

        my $system = $OPT_SYSTEM . '-'      if $OPT_SYSTEM;

        my $body = $ethernet
                 . $provider
                 . $system
                 . $HOST
                 ;

        $body =~ s/-$//;            # Delete trailing slash

        $ARG .= $body . ".log";
    }

    $debug  and  print "$id: $ARG\n";

    $ARG;
}

# ****************************************************************************
#
#   DESCRIPTION
#
#       Return correctly globbed $OPT_IP_FILE.
#       That variable can be both a directory and a filename, possibly
#       Shell metacharacters like tilde(~) need to be expanded.
#
#   GLOBAL VARIABLES
#
#       $OPT_IP_FILE  must be set before calling this function
#
#   INPUT PARAMETERS
#
#       None
#
#   RETURN VALUES
#
#       $path
#
# ****************************************************************************

sub IPfileNameGlobbed ()
{
    my $id   = "$LIB.IPfileNameGlobbed";
    my $file = $OPT_IP_FILE;

    $debug      and  print "$id: OPT_IP_FILE [$file]\n";

    $debug and print "$id: OPT_QUERY_IP_FILE [$OPT_QUERY_IP_FILE] "
	           . "OPT_QUERY_IP_SAVED [$OPT_QUERY_IP_SAVED] "
		   . "OPT_QUERY_IP_CHANGED [$OPT_QUERY_IP_CHANGED]\n";

    if ( not $file
	 and not ($OPT_QUERY_IP_FILE
		  or $OPT_QUERY_IP_SAVED
		  or ($OPT_QUERY_IP_CHANGED eq -undef) )
       )
    {
	#  Nothing to check. We donÅ‰t need to look at previously saved file
	#  User is probably calling with --Query or --query-linksys

	$debug and print "$id: Nothing to do\n";
	return;
    }

    unless ( $file )
    {
        warn "$id: variable OPT_IP_FILE has no value. "
            , "Did you forgot to use option --file-default?"
            ;
    }

    if ( $file )
    {
        unless ( -f $file  or  -d $file )
        {
            my $try = glob $file;

            $debug  and  print "$id: flob [$try]\n";

            $file = $try    if $try;
        }
    }

    $debug  and  print "$id: return [$file]\n";

    $file;
}

# ****************************************************************************
#
#   DESCRIPTION
#
#       Check valid IP address.
#
#   INPUT PARAMETERS
#
#       $ip
#       $intenet    [optional] If set, consider Internal 192.*  and 10.*
#                   addresses valid too. Normally these are not Internet
#                   addresses, but used only for local subnets.
#       $subnet     If set, consider subnet IPs valid (192.x.x.x etc).
#
#   RETURN VALUES
#
#       true,  if ok.
#
# ****************************************************************************

sub IPvalidate ($)
{
    my $id = "IPvalidate";
    local $ARG = shift;
    my $subnet = shift;

    my $ret = 0;

    $debug  and  print "$id: [$ARG] subnet [$subnet]\n";

    if ( /^\s*\d+\.\d+\.\d+\.\d+\s*$/ )
    {
        $ret = 1;

        if ( /^\s*(0|192|10)\./ )
        {
           $ret = 0;
           $ret = 1 if $subnet;
           $verb  and  print "$id: ranges 192.* and 10.* are not valid\n";
        }
    }

    if ( $debug  )
    {
        my $action = "[ERROR] IP is not valid.";
        $ret  and  $action = "Success.";

        print "$id: return [$ret] $action\n";
    }

    $ret;
}

# ****************************************************************************
#
#   DESCRIPTION
#
#       Return strings (B) that are not found in original list (A)
#
#   INPUT PARAMETERS
#
#       \@      original list (A)
#       \@      list of search elements  (B)
#
#   RETURN VALUES
#
#       @       list of elements that were not found from string
#
# ****************************************************************************

sub StringMatch ( $ $ )
{
    my $id = "StringMatch";
    my ($itemRef, $searchRef  ) =  @ARG;

    unless ( @$itemRef )
    {
        $debug  and  print "$id: [ERROR] input list is empty."
                        , "items = [@$itemRef]\n";
        return;
    }

    my @ret;

    for my $search ( @$searchRef )
    {

        unless ( grep /^\Q$search$/, @$itemRef )
        {
            $debug  and print "$id: not found [$search]\n";
            push @ret, $search;
        }
    }

    $debug  and
        print "$id: ret = [@ret] input items = [@$itemRef]\n";

    @ret;
}

# ****************************************************************************
#
#   DESCRIPTION
#
#       Construct correct URL
#
#   INPUT PARAMETERS
#
#       $url     URL page
#       $login   [optional] how to log in to a secured page
#       $pass    [optional] how to log in to a secured page
#
#   RETURN VALUES
#
#       $url     with possible LOGIN and PASS information
#
# ****************************************************************************

sub HttpUrlMake (%)
{
    my $id      = "$LIB.HttpUrlMake";
    my %arg     = @ARG;

    local $ARG  = $arg{-url};
    my $login   = $arg{-login};
    my $pass    = $arg{-pass};

    if ( $pass  and  m,(http://)(.+), )
    {
        my ($method, $rest) = ($1, $2);

        $ARG = $method . "$login:$pass@" . $rest;
    }

    $debug  and  print "$id: return [$ARG]\n";
    $ARG;
}

# ****************************************************************************
#
#   DESCRIPTION
#
#       Return (YYYY, MM, DD, HH, mm)
#
#   INPUT PARAMETERS
#
#       $time       [optional]. If not given, return current date
#
#   RETURN VALUES
#
#       @list
#
# ****************************************************************************

sub Date (; $)
{
    my $id = "$LIB.Date";
    my ($time) = @ARG;

    $time = time   unless defined $time;
    my ($yyyy, $MM, $dd, $hh, $mm) = (localtime $time)[5, 4, 3, 2, 1];

    $yyyy += 1900;
    $MM++;

    $yyyy, $MM, $dd, $hh, $mm;
}

# ****************************************************************************
#
#   DESCRIPTION
#
#       Return ISO 8601 Date in format 'YYYY-MM-DD HH:mm'
#
#   INPUT PARAMETERS
#
#       $time       [optional]. If not given, return current date
#
#   RETURN VALUES
#
#       @list
#
# ****************************************************************************

sub DateISO (; $)
{
    my $id = "$LIB.Date";
    my ($time) = @ARG;

    my($yyyy, $MM, $dd, $hh, $mm) = Date $time;

    sprintf "$yyyy-%02d-%02d %02d:%02d", $MM, $dd, $hh, $mm;
}

# ****************************************************************************
#
#   DESCRIPTION
#
#       Calculate diff between TWO dates in days. This is rought estimation,
#       Not a correct value.
#
#   INPUT PARAMETERS
#
#       \@date1         See return value of Date()
#       \@date2         See return value of Date()
#
#   RETURN VALUES
#
#       $days           Floating point number
#
# ****************************************************************************

sub DateDiffDays ($$)
{
    my $id      = "$LIB.DateDiffDays";
    my ($date1ref, $date2ref)  = @ARG;

    my ($yyyy, $MM, $dd, $hh, $mm)      = @$date1ref;
    my ($yyyy2, $MM2, $dd2, $hh2, $mm2) = @$date2ref;

    my $total = ($yyyy2 - $yyyy) * 365;

    $total += ($MM2 - $MM) * 30;

    $total += (
                  ($dd2*24*60 + $hh2*60 + $mm2)
                - ($dd*24*60  + $hh*60  + $mm)
              )
              / (24*60);

    $debug and
      print "$id: $yyyy, $MM, $dd, $hh, $mm | $yyyy2, $MM2, $dd2, $hh2, $mm2\n";

    $debug and  print "$id: return $total\n";

    $total;
}

# ****************************************************************************
#
#   DESCRIPTION
#
#       File date in format (YYYY, MM, DD)
#
#   INPUT PARAMETERS
#
#       $file
#
#   RETURN VALUES
#
#       @list
#
# ****************************************************************************

sub FileDate ($)
{
    my $id      = "$LIB.FileDate";
    my ($file)  = @ARG;

    unless ( -f $file )
    {
        $verb > 2   and  Log "$id: [WARN] No such file [$file]";
        return;
    }

    my $mtime = (stat $file)[9];
    my @ret = Date $mtime;

    $debug and  print "$id: return @ret\n";

    @ret;
}

# ****************************************************************************
#
#   DESCRIPTION
#
#       Check if the file has been accessed within N days
#
#   INPUT PARAMETERS
#
#       $file       File to check
#       $days       Floating point number
#
#   RETURN VALUES
#
#       ( $status, $diff )
#
#       $status     0 = File has changed.
#                   N = Not touched in N days
#       $diff       float, how many days old
#
# ****************************************************************************

sub IsFileOlderThanDays ($$)
{
    my $id      = "$LIB.IsFileOlderThanDays";
    my ($file, $days)  = @ARG;

    $debug  and  print "$id: file [$file] required days [$days]\n";

    unless ( -f $file )
    {
        $verb > 2   and  Log "$id: [WARN] No such file [$file]";
        return 100;
    }

    my @fileDate = FileDate $file;
    my @date     = Date();

    my $diffDays = DateDiffDays \@fileDate, \@date;

    my $ret = 0;
    $ret    = $diffDays    if $diffDays > $days;

    $debug and  print "$id: file [$file] days $[days], return [$ret]\n";

    ( $ret, $diffDays );
}

# ****************************************************************************
#
#   DESCRIPTION
#
#       Check if the file has been accessed within N days
#
#   GLOBAL VALUES
#
#       $OPT_PRROVIDER must be set prior calling. (not yet used)
#
#   INPUT PARAMETERS
#
#       $file       File to check
#
#   RETURN VALUES
#
#       See function IsFileOlderThanDays()
#
# ****************************************************************************

sub IsFileOld ($)
{
    my $id      = "$LIB.IsFileOld";
    my ($file)  = @ARG;

    $debug  and  print "$id: file [$file]\n";

    warn "$id: [ERROR] OPT_PROVIDER is not set." unless  $OPT_PROVIDER;

    my ($status, $days);

    if ( $file )
    {
        ($status, $days) = IsFileOlderThanDays $file, 30;
    }
    else
    {
        warn "$id: input parameter 'file' is not set.";
    }

    $debug  and  print "$id: RETURN [$status]\n";

    ($status, $days);
}

# ****************************************************************************
#
#   DESCRIPTION
#
#       Connect to a HTTP page from where IP address can be read
#
#   INPUT PARAMETERS
#
#       $url     Call string
#       $regexp  How to read the IP address
#       $login   [optional] how to log in to a secured page
#       $pass    [optional] how to log in to a secured page
#
#   RETURN VALUES
#
#       $ip     IP number
#
# ****************************************************************************

sub HttpPing (%)
{
    my $id      = "$LIB.HttpPing";
    my %arg     = @ARG;
    my $url     = $arg{-url};
    my $regexp  = $arg{-regexp};
    my $login   = $arg{-login};
    my $pass    = $arg{-pass};

    if ( $debug )
    {
        print "$id: input URL [$url] regexp [$regexp} "
            , "login [$login] pass [$pass]\n"
            ;
    }

    $url = HttpUrlMake -url   => $url
                     , -login => $login
                     , -pass  => $pass
                     ;

    unless ( $url and  $regexp )
    {
        die "$id: parameters are empty, URL [$url]. ",
            " Run in debug mode.\n";
    }

    if ( not $url  or  $url !~ m,http://,i )
    {
        die "$id: invalid URL [$url]. Please check syntax";
    }

    unless ( $regexp =~ /\(/ )
    {
        die "$id: Invalid regexp [$regexp]. Must include parentheses."
    }

    my $req  = new HTTP::Request( 'GET', $url );

    $req->user_agent( "Perl client $PROGNAME/$VERSION");

    # $req->header( "Host", $connect );

    if ( $test or  $debug )
    {
        print $req->as_string;
    }

    my $ret = '';

    my $ua = new LWP::UserAgent
        or die "$id: LWP::UserAgent failed $ERRNO";


    if ( $test < 2 )
    {
        my $resp    = $ua->request( $req );
        my $str     = $resp->as_string;

        $debug  and  print "$str";
        $ret = StringRegexpMatch $str, $regexp;
    }
    else
    {
        $verb  and  print  "$id: No request sent; running in test mode.\n";
        $ret = "0.0.0.0";
    }

    $debug  and  print "$id: return ip [$ret]\n";

    $ret;
}

# ****************************************************************************
#
#   DESCRIPTION
#
#       Connect to a www.dyndns.org and get outbound IP address.
#
#   INPUT PARAMETERS
#
#       none
#
#   RETURN VALUES
#
#       $ip     IP address
#
# ****************************************************************************

sub HttpPingDyndns ()
{
    my $id     = "$LIB.HttpPingDyndns";

    $debug  and  print "$id:\n";

    my $regexp = 'IP\s+Address:\s+([\d.]+)';

    HttpPing   -url    => "http://www.dyndns.org/cgi-bin/check_ip.cgi"
             , -regexp => $regexp
             ;
}

# ****************************************************************************
#
#   DESCRIPTION
#
#       Connect to a Linksys WLAN router, and get outbound IP address.
#       See http://www.linksys.com/
#
#       This function is for "Wireless AP Router w/4 port Switch"
#       Model BEFW11S4
#
#   INPUT PARAMETERS
#
#       $login  Login to connect the router
#       $pass   Password to connect the router
#
#   RETURN VALUES
#
#       $ip     IP address
#
# ****************************************************************************

sub HttpPingWlanLinksysBEFW11S4 (; $$)
{
    my $id             = "$LIB.HttpPingWlanLinksysBEFW11S4";
    my ($login, $pass) = @ARG;

    $login = "admin" unless $login;

    $debug  and  print "$id: INPUT login [$login] pass [$pass]\n";

    #   It is not a password, if there is are no alphanumeric characters
    #   in it.

    unless ( $pass =~ /[a-z]/i )
    {
        $pass = "admin";   # Use default
    }

    #  There are two models of BEFW11S4; v2 and v4. The later version
    #  (Cisco version) changed the page from Status.html to
    #  RouterStatus.htm. The page content is also different.
    #
    #   [v2]
    #   The Response string looks like:
    #   IP Address:</td><td><font face=verdana size=2>81.197.0.2</td>
    #
    #   [v4]
    #   Internet IP Address:</FONT></TD><TD><FONT style='FONT-SIZE: 8pt'><B>69.110.12.53</B></FONT></TD><


    #  The LOGIN name is ignored by Linksys. But it has to be provided
    #  in the HTTP call. LOGIN:PASS@SITE.

    $debug  and  print "$id: regexp [regexp] login [$login] pass [$pass]\n";

    my ($ip, $regexp);

    #   v4
    $regexp = 'IP +Address:.+?<B>\s*([\d.]+)';

    $ip = HttpPing  -url   =>"http://192.168.1.1/RouterStatus.htm"
                    , -regexp => $regexp
                    , -login  => $login
                    , -pass   => $pass
                    ;

    unless ($ip)
    {
        #   v2
        #   There is actually TWO similar lines, the first one is LAN
        #   and the other is WAN ip address. The ".*" at front forces
        #   to pick the last.

        $regexp = '.*IP +Address:.+?font[^>]+>+([\d.]+)';

        $ip = HttpPing  -url   =>"http://192.168.1.1/Status.htm"
                        , -regexp => $regexp
                        , -login  => $login
                        , -pass   => $pass
                        ;
    }

    $ip;
}

# ****************************************************************************
#
#   DESCRIPTION
#
#       Connect to a Linksys Model WRT54GL router, and get outbound IP address.
#
#   INPUT PARAMETERS
#
#       $login  Login to connect the router
#       $pass   Password to connect the router
#
#   RETURN VALUES
#
#       $ip     IP address
#
# ****************************************************************************

sub HttpPingWlanLinksysWRT54GL (; $$)
{
    my $id             = "$LIB.HttpPingWlanLinksysWRT54GL";
    my ($login, $pass) = @ARG;

    # This router has empty login by default.

    $debug  and  print "$id: INPUT login [$login] pass [$pass]\n";

    #   It is not a password, if there is are no alphanumeric characters
    #   in it.

    unless ( $pass =~ /[a-z]/i )
    {
        $pass = "admin";   # Use default
    }

    #   The Response string looks like:
    #   <script>Capture(share.ipaddr)</script>:&nbsp;</FONT></TD>
    #      <TD><FONT style="FONT-SIZE: 8pt"><B>81.197.175.198</B></FONT></TD>

    my $regexp = '(?mi)Capture.*ipaddr.*[\r\n]+.+?font.+?<B>([\d.]+)';

    #  The LOGIN name is ignored by Linksys. But it has to be provided
    #  in the HTTP call. LOGIN:PASS@SITE.

    $debug  and  print "$id: regexp [regexp] login [$login] pass [$pass]\n";

    HttpPing   -url    =>"http://192.168.1.1/Status_Router.asp"
             , -regexp => $regexp
             , -login  => $login
             , -pass   => $pass
             ;
}

# ****************************************************************************
#
#   DESCRIPTION
#
#       ping network HOST
#
#   INPUT PARAMETERS
#
#       $       HOST
#
#   RETURN VALUES
#
#       1       If connection is okay.
#
# ****************************************************************************

sub Ping ($)
{
    my $id      = "$LIB.Ping";
    my ($host)  = @ARG;

    my $ret = 0;
    eval "use Net::Ping";

    if ( $EVAL_ERROR )
    {
        Log "$id: [ERROR] Cannot load Net::Ping.pm, please check \@INC\n";
    }
    else
    {
        my $ping = Net::Ping->new();

        $ret = 1  if $ping->ping($host);

        $ping->close();
    }

    $debug  and  print "$id: return [$ret]n";

    $ret;
}

# }}}
# {{{ IP addresses

# ****************************************************************************
#
#   DESCRIPTION
#
#       Return last used ip address.
#
#       http://support.dyndns.org/dyndns/faq.shtml
#
#       A Dynamic DNS hostname only needs to
#       be updated when your IP address has changed. Any updates more
#       frequently than this - from the same IP address - will be
#       considered abusive by the update system and may result in your
#       hostname becoming blocked. Any script which runs periodically
#       should check to make sure that the IP has actually changed before
#       making an update, or the host will become blocked. An exception to
#       this is for users with mostly static IP addresses; you may update
#       24-30 days after your previous update with the same IP address to
#       "touch" the record and prevent it from expiring. Users will receive
#       an e-mail notification if a host has been unchanged for 28 days.
#
#   INPUT PARAMETERS
#
#       $file       File to read
#
#   RETURN VALUES
#
#       string
#
# ****************************************************************************

sub GetIpAddressLast ($)
{
    my $id      = "$LIB.GetIpAddressLast";
    my ($file)  = @ARG;

    $debug  and  print "$id: INPUT file to check [$file]\n";

    local ( *FILE, $ARG );

    if ( $file =~ /^\s*$/ )
    {
        $verb  and
            Log "$id: [WARN] FILE argument is missing, see --file-default\n";
        return;
    }

    unless ( -f $file )
    {
        $verb  and  print "$id: No file [$file]\n";
        return;
    }

    $debug  and  print "$id: opening [$file]\n";

    open FILE, "< $file"
        or die "$id: Cannot open [$file] $ERRNO";

    my $ip;

    while ( defined( $ARG = <FILE>) )
    {
        if ( /^\s*([\d.]+)\s*$/ )
        {
            $ip = $1;
            last;
        }
    }

    close FILE;

    $debug  and  print "$id: return [$ip]\n";

    $ip;
}

# ****************************************************************************
#
#   DESCRIPTION
#
#       Read file
#
#   INPUT PARAMETERS
#
#       $file       File
#
#   RETURN VALUES
#
#       @lines
#
# ****************************************************************************

sub FileRead ( $ )
{
    my $id      = "$LIB.FileRead";
    my ($file)  = @ARG;

    local *FILE;

    my @content;

    unless( open FILE, "< $file" )
    {
        my $msg = "$id: [ERROR] Cannot open [$file] $ERRNO";

        if ( $OPT_DAEMON )
        {
            Log $msg;
        }
        else
        {
            die $msg;
        }
    }
    else
    {
        @content = <FILE>;
        close FILE;
    }

    @content;
}

# ****************************************************************************
#
#   DESCRIPTION
#
#       Write message to file. Call syntax:
#
#           FileWrite $file, undef, "String\n";       Replace file
#           FileWrite $file, -append, "String\n";     Append mode
#
#   INPUT PARAMETERS
#
#       $file       File
#       $append     [optional] Append write mode.
#       @list       Strings to write to file
#
#   RETURN VALUES
#
#       true    If wrote.
#
# ****************************************************************************

sub FileWrite ( $ $ @ )
{
    my $id   = "$LIB.FileWrite";
    my ($file, $append, @list ) = @ARG;

    $debug  and  print "$id: INPUT file [$file] append [$append] list [@list]\n";

    local ( *FILE, $ARG );

    my $status = -wrote;
    my $mode   = ">";
    $mode      = ">>" if $append;

    unless ( open FILE, "$mode $file" )
    {
        Log "$id: [ERROR] Cannot write [$file] $ERRNO";
        return 0;
    }

    unless ( $test )
    {
        unless ( print FILE @list )
        {
            Log "$id: [ERROR] Cannot write '@list' to file $file\n";
            $status = '';
        }

        close FILE;

        $debug  and  print "$id: Wrote to [$file] content [@list]\n";
    }
    else
    {
        $debug  and  print "$id: test would write [$file] content [@list]\n";
    }

    $status;
}

# ****************************************************************************
#
#   DESCRIPTION
#
#       Glob (that is, expand) all files in passed LIST. Errors
#       are displayed for files which do not exist. Directories
#       in result of glob are discarded
#
#   INPUT PARAMETERS
#
#       @list       List of filenames to glob.
#                   For example '~/tmp/*'
#
#   RETURN VALUES
#
#       @list       absolute paths to files
#
# ****************************************************************************

sub FileGlob (@)
{
    my $id     = "$LIB.FileGlob";
    my (@list) = @ARG;

    $debug  and  print  "$id: INPUT [@list]\n";

    my @ret;

    for my $file ( @list )
    {
        my @glob = glob $file;

        $debug  and  print  "$id: glob $file => [@glob]\n";

        for my $glob ( @glob )
        {
            if ( -d $glob )
            {
                $debug  and  print "$id: directory [$glob]\n";
            }
            elsif ( not -r $glob )
            {
                $debug  and  print "$id: not readable [$glob]\n";
            }
            else
            {
                push @ret, $glob if $glob;
            }
        }
    }

    $debug  and  print  "$id: return [@ret]\n";

    #   I think sort() is not strictly necessary, because glob()
    #   already return the files in alphabetical order.
    #   Be safe: we use this in case Perl some day changes glob().

    sort @ret;
}

# ****************************************************************************
#
#   DESCRIPTION
#
#       See if it is possible to Write to the DIRECTORY or to the FILE. The
#       FILE is not used, but a FILE.tmp file is tested and then deleted.
#
#   INPUT PARAMETERS
#
#       $file   This can be either DIRECTORY of FILE. If DIRECTORY,
#               then try to write using temporary name.
#
#   RETURN VALUES
#
#       true    If writable.
#
# ****************************************************************************

sub FileWriteCheck ( $ )
{
    my $id     = "$LIB.FileWriteCheck";
    my ($file) = @ARG;

    local *FILE;
    my $status = '';

    $debug  and  print "$id: file [$file]\n";

    return  unless $file;

    local *Write = sub ($)
    {
        my ($path) = @ARG;

        my $stamp   = join '', Date();
        my $postfix = "dyndns-writetest" . $stamp . ".tmp";
        $path      .= $postfix;

        my $status = FileWrite $path, undef, "write check";

        if ( $status )
        {
            $debug  and  print "$id: Removing $path\n";

            unless ( unlink $path  )
            {
                Log "$id: [WARN] Cannot remove $path $ERRNO";
            }
        }

        $status;
    };

    if ( -d $file )
    {
        $file =~ s,/$,,;
        $file .= '/';
    }

    $status = Write($file);

    if ( $debug )
    {
        my $action = "Check failed.";
        $status  and  $action = "Good, check passed.";

        print "$id: return [$status] $action\n";
    }

    $status;
}

# ****************************************************************************
#
#   DESCRIPTION
#
#       Check if directory or file can be written to. Consequent calls
#       return cached status and do not actually test the disk any more.
#       It is expected that permissions on disk do not change.
#
#   INPUT PARAMETERS
#
#       $file       Directory or file.
#
#   RETURN VALUES
#
#       true        If writable
#
# ****************************************************************************

{
    my %cacheStatic;

sub FileWriteCheckIP ($)
{
    my $id     = "$LIB.FileWriteCheckIP";
    my ($file) = @ARG;

    $debug  and  print "$id: file [$file]\n";

    unless ( $file )
    {
        die "$id: Don't know where to save IP. "
            , "Use --debug to pinpoint the problem if you supplied "
            , "option --Config or --file or --file-default"
            ;
    }

    $debug  and  print "$id: \@OPT_HOST = @OPT_HOST\n";

    $file = IPfileNamePath $file, -absolute, \@OPT_HOST;

    my $stat;

    if ( exists $cacheStatic{file} )
    {
        $stat = $cacheStatic{file};
    }
    else
    {
        $stat = FileWriteCheck $file;
    }

    die "$id: Cannot use [$file].\n"  unless $stat;

    $stat;
}}

# ****************************************************************************
#
#   DESCRIPTION
#
#       Parse Ip address from INPUT by searching REGEXP line.
#       IP address must be the first numeric expression.
#
#   INPUT PARAMETERS
#
#       $           regexp. Submatch 1 must contain the IP address portion.
#       @           List of lines to search. Typically command's output.
#
#   RETURN VALUES
#
#       $           ip address
#
# ****************************************************************************

sub IpAddressGenericParser ( $ @ )
{
    my $id                = "$LIB.IpAddressGenericParser";
    my ($regexp, @lines ) = @ARG;

    local $ARG;
    my    $ip = '';

    $debug  and  print "$id: Response => \n@lines\n";

    for ( @lines )
    {
        if ( /$regexp/ )
        {
            if ( not defined $1 )           # User gave non-fucntional regexp
            {
                if ( /(\d[\d.]+)/ )         # try generic IP matcher
                {
                    $ip = $1;
                }
            }
            else
            {
                $ip = $1;
            }

            $debug  and  print "$id: Matched [$ARG]\n";
            last;
        }
    }

    unless ( $ip )
    {
        $debug  and
            print "$id: Hm, single line did not match. Try multiline match.\n";

        # Try full line regexp
        $ARG = join '', @lines;

        if ( /$regexp/ )
        {
            $ip = $1;
            $debug  and  print "$id: MULTILINE MATCH FOUND => [$ip] $MATCH\n";

        }
    }

    unless( $ip )
    {
        $verb  and
            Log "$id: [WARN] Can't read IP '$regexp' lines => [@lines]";
    }

    $debug  and  print "$id: return IP [$ip]\n";

    $ip;
}

# ****************************************************************************
#
#   DESCRIPTION
#
#       Print error message and PATH content if command response is empty.
#
#   INPUT PARAMETERS
#
#       $           Original function name which generated error
#       $           command
#       @           command response
#
#   RETURN VALUES
#
#       1           if LIST is empty
#
# ****************************************************************************

sub CmdError ( $ $ @ )
{
    my $id = "$LIB.CmdError";
    my ($func, $cmd, @list ) = @ARG;

    my $ret = 0;

    unless ( @list )
    {
        my @try     = qw( /usr/sbin /usr/local/sbin );

        my @paths = split $WIN32 ? ";" : ":" , $PATH;

        my @missing = StringMatch \@paths, \@try ;

        my $out;

        $out = "$id: $func [PANIC] command [$cmd] did not return response.\n"
                . "\tYou may need to add some directory to your PATH."
                . "Your PATH is now:\n"
                ;

        my $i = 0;
        for my $path ( @paths )
        {
            $i++;
            $out .= "\t$i $path\n";
        }

        if ( @missing )
        {
            $out .= "\t=> Try adding path";

            if ( @missing == 1 )
            {
                $out .= " @missing";
            }
            else
            {
                $out .= "s [@missing]\n";
            }
        }

        Log $out;
        $ret = 1;
    }

    $debug  and  print "$id: return [$ret]\n";

    $ret;
}

# ****************************************************************************
#
#   DESCRIPTION
#
#       Get current IP by running COMMAND and searching for line
#       matching REGEXP. The IP address must be the first numeric
#       expression in the found REGEXP line.
#
#   INPUT PARAMETERS
#
#       $           Command  which return IP address
#       @           Regular expressions to find line containing IP address.
#
#   RETURN VALUES
#
#       $           ip address
#
# ****************************************************************************

sub GetIpAddressGenericParser ( $ @ )
{
    my $id              = "$LIB.GetIpAddressGenericParser";
    my ($cmd, @regexp ) = @ARG;

    my $list = join '', qx($cmd);

    $debug  and  print "$id: [$cmd] [$list]\n";

    my $stat = CmdError $id, $cmd, $list;

    $stat and die "$id: $cmd ERROR" ;

    my $ip;

    for my $regexp ( @regexp )
    {
        $debug  and  print "$id: Trying with regexp '$regexp'\n";
        $ip = IpAddressGenericParser $regexp, $list;
        last if  $ip;
    }

    $ip;
}

# ****************************************************************************
#
#   DESCRIPTION
#
#       Get current IP by running Win32 IPconfig.exe
#
#   INPUT PARAMETERS
#
#       $           [optional] command to run
#
#   RETURN VALUES
#
#       $           ip address
#
# ****************************************************************************

sub GetIpAddressWin32 (; $)
{
    my $id    = "$LIB.GetIpAddressWin32";
    my ($cmd) = @ARG;

    $cmd = "ipconfig"   unless $cmd;

    # The output could look like this:
    #
    # PPP adapter tpo128:
    #
    #       Connection-specific DNS Suffix  . :
    #       IP Address. . . . . . . . . . . . : 212.246.177.6
    #       Subnet Mask . . . . . . . . . . . : 255.255.255.255
    #
    # Notice: The German Win32 reads:
    #
    #       PPP-Adapter "T-DSL":
    #       Verbindungsspezifisches DNS-Suffix:
    #       IP-Adresse. . . . . . . . . . . . : 80.136.27.233
    #       Subnetzmaske. . . . . . . . . . . : 255.255.255.255


    my $modifier  = '(?sm)';
    my $base      = 'IP\s+Add?resse?[^\r\n:]+:[ \t]*(\d[\d.]+)';

    my @regexpList;
    push @regexpList, $modifier . 'PPP.*' . $base;
    push @regexpList, $modifier . $base;

    my $ip;

    if ( $OPT_REGEXP )
    {
        # If user supplied search criteria, this must be tried first
        my $try = $modifier . $OPT_REGEXP . ".*" . $base;

        $ip = GetIpAddressGenericParser $cmd, $try;

        if ( not $ip   and   $verb )
        {
            print "$id: [ERROR] User supplied regexp [$OPT_REGEXP] failed. "
              , "Use --debug to see what went wrong.";
        }
    }

    unless ( $ip )
    {
        $ip = GetIpAddressGenericParser $cmd, @regexpList;
    }

    $verb  and  print "$id: $cmd => $ip\n";
    $ip;
}

# ****************************************************************************
#
#   DESCRIPTION
#
#       Get current IP address information from ethernet CARD.
#       Global variable OPT_ETHERNET can be set via command line option.
#
#   INPUT PARAMETERS
#
#       none
#
#   RETURN VALUES
#
#       string
#
# ****************************************************************************

sub GetIpAddressIfconfig ()
{
    my $id = "$LIB.GetIpAddressIfconfig";
    my $cmd  = "ifconfig $OPT_ETHERNET";

    # $ /sbin/ifconfig eth0
    # eth0      Link encap:Ethernet  HWaddr 00:10:5A:64:8D:32
    #       inet addr:12.246.164.15  Bcast:255.255.255.255  Mask:255.255.255.0
    #       UP BROADCAST RUNNING  MTU:1500  Metric:1
    #       RX packets:38180 errors:0 dropped:0 overruns:0 frame:0
    #       TX packets:12211 errors:0 dropped:0 overruns:0 carrier:1
    #       collisions:46 txqueuelen:100
    #       Interrupt:11 Base address:0xec00

    # my $re = 'inet[ \t]+addr:[ \t]*(\d[\d.]+)';

    my $modifier  = '(?sm)';
    my $inet      = 'inet[ \t]+';
    my $base      = '[ \t]*(\d[\d.]+)';

    my @regexpList;
    push @regexpList, $modifier . $inet . "addr:" . $base;
    push @regexpList, $modifier . $inet . $base;


    my $ip;

    if ( $OPT_REGEXP )
    {
        # If user supplied search criteria, this must be tried first
        my $try = $modifier . $OPT_REGEXP . $base;

        $ip = GetIpAddressGenericParser $cmd, $try;

        if ( not $ip   and   $verb )
        {
            print "$id: [ERROR] User supplied regexp [$OPT_REGEXP] failed. "
              , "Use --debug to see what went wrong.";
        }
    }

    unless ( $ip )
    {
        $ip = GetIpAddressGenericParser $cmd, @regexpList;
    }

    $verb  and  print "$id: $cmd => $ip\n";

    $ip;
}

# ****************************************************************************
#
#   DESCRIPTION
#
#       Get current IP address information. Dies if cannot detect ip address.
#
#   INPUT PARAMETERS
#
#       none
#
#   RETURN VALUES
#
#       string
#
# ****************************************************************************

sub GetIpAddress ()
{
    my $id = "$LIB.GetIpAddress";

    my $ret;

    if ( $OPT_HTTP_PING )
    {
        $ret = HttpPing -url    => $OPT_HTTP_PING
                      , -regexp => $OPT_HTTP_PING_REGEXP
                      , -login  => $OPT_HTTP_PING_LOGIN
                      , -pass   => $OPT_HTTP_PING_PASSWORD
                      ;
    }
    elsif ( $OPT_HTTP_PING_DYNDNS )
    {
        $ret = HttpPingDyndns();
    }
    elsif ( $OPT_HTTP_PING_LINKSYS )
    {

	local $ARG = $OPT_HTTP_PING_LINKSYS;

	if ( /BEFW11S4/i )
	{
	    $ret = HttpPingWlanLinksysBEFW11S4
		     $OPT_HTTP_PING_LOGIN, $OPT_HTTP_PING_PASSWORD;
	}
	if ( /WRT54GL/i )
	{
	    $ret = HttpPingWlanLinksysWRT54GL
		     $OPT_HTTP_PING_LOGIN, $OPT_HTTP_PING_PASSWORD;
	}
	else
	{
	    warn "$id: Unknown product code: $ARG. Please contact maintainer.";
	}
    }
    elsif ( $WIN32 )
    {
        $ret = GetIpAddressWin32();
    }
    elsif ( -x "/sbin/ifconfig"  or  -x "/usr/sbin/ifconfig")
    {
        $ret = GetIpAddressIfconfig();
    }
    else
    {
        die "$id: Don't know how to get your IP address in this OS [$OSNAME]."
            , "Please contain maintainer and let him "
            , "know your system name + command + result where to get ip "
            , "information."
            ;
    }

    unless ( $ret )
    {
        my $msg = "$id: [EXIT] Can't read IP address. Please turn on --debug.";

        Log $msg;
        die $msg;
    }

    $ret;
}

# ****************************************************************************
#
#   DESCRIPTION
#
#       Return NEW ip address if it has been changed.
#
#   INPUT PARAMETERS
#
#       $file           File to read IP address info
#       $query          if true, do not complain about previous IP
#
#   RETURN VALUES
#
#       (IP, "nochange") "nochange" added if the IP adderess has not changed.
#       (IP, IP)         First argument is the new IP address.
#                        The second argument may be missing if there is no
#                        record of old address.
#
# ****************************************************************************

sub GetIpAddressInfo (%)
{
    my $id      = "$LIB.GetIpAddressInfo";
    my %arg     = @ARG;
    my $file    = $arg{-file};
    my $query   = $arg{-query};

    $debug  and  print "$id: INPUT file [$file] query [$query]\n";

    my $ip      = GetIpAddress();
    my $lastIP  = GetIpAddressLast( $file ) || "last-ip-info-not-available";
    my @ret     = ("nochange");

    $debug  and  print "$id: IP now [$ip] IP last [$lastIP]\n";

    if ( defined $ip )
    {
        if ( defined $lastIP )
        {
            if ( $ip  eq  $lastIP )
            {
                @ret = ($ip, "nochange");
            }
            else
            {
                @ret = ($ip, $lastIP);
            }
        }
        else
        {
            @ret = ($ip);
        }
    }
    else
    {
        $verb  and  print "$id: Could not get IP address. ",
                          , "Please run --debug\n";
    }

    $debug  and  print "$id: return [@ret]\n";

    @ret;
}

# ****************************************************************************
#
#   DESCRIPTION
#
#       See if there is anything to inform about status code
#
#   INPUT PARAMETERS
#
#       $code           Error code
#       $description    Error descriptions string
#       $type           -dyndns, -noip, -hnorg
#
#   RETURN VALUES
#
#       true           If IP update can be tried again.
#
# ****************************************************************************

sub StatusCodeHandle ($ $ $)
{
    my $id = "$LIB.StatusCodeHandle";
    my ($code, $desc, $type)   = @ARG;

    my $status = 0;

    $debug  and  print "$id: INPUT [$code] [$desc] type [$type]\n";

    if ( $type  =~ /noip/ )
    {
        my @list = @STATUS_CODE_NOIP_TRY_AGAIN;

        $debug  and  print "$id: BOUNCE LIST noip [@list]\n";

        #   If number is found in "ok" list, then return the status code
        $status = $code   if  grep /^$code$/, @list;
    }
    elsif ( $type  =~ /dyndns/ )
    {
        #  This is list of regexps, not numbers
        my @list = @STATUS_CODE_DYNDNS_TRY_AGAIN;

        $debug  and  print "$id: BOUNCE LIST dyndns [@list]\n";

        $status = $code   if  grep /$code/, @list;
    }
    elsif ( $type  =~ /hnorg/ )
    {
        #  This is list of regexps, not numbers
        my @list = @STATUS_CODE_HN_TRY_AGAIN;

        $debug  and  print "$id: BOUNCE LIST hnorg [@list]\n";

        $status = $code   if  grep /$code/, @list;
    }
    else
    {
        Log "$id: [ERROR] Can't handle unknown provider [$type].";
    }

    if ( $debug )
    {
        my $action = "Success.";
        $status  and  $action = "User is allowed to retry based on [$code].";

        print "$id: RETURN [$status] $action\n";
    }

    $status;
}

# ****************************************************************************
#
#   DESCRIPTION
#
#       Parse status code
#
#   INPUT PARAMETERS
#
#       $response   HTTP response string
#
#   RETURN VALUES
#
#       $code, $string      status code and description string
#
# ****************************************************************************

sub StatusCodeParseDynDns ( $ )
{
    my $id       = "$LIB.StatusCodeParseDynDns";
    local ($ARG) = @ARG;

    #   The response look like:
    #
    #    dyndns.pl.main: Updating IP 212.246.177.25
    #    HTTP/1.1 200 OK
    #    Connection: close
    #    Date: Sun, 10 Jun 2001 22:11:25 GMT
    #    Pragma: no-cache
    #    Server: Apache/1.3.20 (Unix) mod_perl/1.25
    #    Content-Type: text/plain
    #    Client-Date: Sun, 10 Jun 2001 22:16:54 GMT
    #    Client-Peer: 66.37.218.209:80
    #
    #    nohost 212.246.177.25


    # Get last string from the @lines

    my $code = (reverse split /\n/)[0];

    if ( $code =~ /([a-zA-Z]+)/ )                   # find first word
    {
        $code = $1;
    }

    my $desc =  "[WARN] there is no return code description "
                . "defined for [$code]"
                ;

    my %hash = %STATUS_CODE_DYNDNS_HASH;

    if ( exists $hash{$code} )
    {
        $desc = $hash{$code};
    }
    elsif ( $code =~ /w(\d\d)([hms])/i )
    {
        my  $min  = $1;
        my  $type = $2;

        if ( exists $hash{"wxx$type"} )
        {
            $desc = $hash{"wxx$type"};
            $desc =~ s/ xx /$min/;
        }
    }
    elsif ( $code =~ /good/i )
    {
        $desc = "Update successful.";
    }

    $code, $desc;
}

# ****************************************************************************
#
#   DESCRIPTION
#
#       Parse status code
#
#   INPUT PARAMETERS
#
#       $response   HTTP response string
#
#   RETURN VALUES
#
#       $code, $string      status code and description string
#
# ****************************************************************************

sub StatusCodeParseNoip ( $ )
{
    my $id       = "$LIB.StatusCodeParseNoip";
    local ($ARG) = @ARG;

    #   The response look like:
    #
    # HTTP/1.1 200 OK
    # Connection: close
    # Date: Sun, 29 Sep 2002 17:39:32 GMT
    # Server: Apache/1.3.26 (Unix) PHP/4.2.2 mod_ssl/2.8.10 OpenSSL/0.9.6g
    # Content-Type: text/html
    # Client-Date: Sun, 29 Sep 2002 17:41:40 GMT
    # Client-Response-Num: 1
    # Client-Transfer-Encoding: chunked
    # X-Powered-By: PHP/4.2.2
    #
    # status=2

    # Get last string from the @lines

    my $code = (reverse split /\n/)[0];

    if ( $code =~ /status=(\d+)/ )                   # find first word
    {
        $code = $1;
    }

    my $desc = "[WARN] there is no ret code description defined for [$code]";

    my %hash = %STATUS_CODE_NOIP_HASH;

    if ( exists $hash{$code} )
    {
        $desc = $hash{$code};
    }

    $code, $desc;
}

# ****************************************************************************
#
#   DESCRIPTION
#
#       Parse status code
#
#   INPUT PARAMETERS
#
#       $response   HTTP response string
#
#   RETURN VALUES
#
#       $code, $string      status code and description string
#
# ****************************************************************************

sub StatusCodeParseHNorg( $ )
{
    my $id       = "$LIB.StatusCodeParseNoip";
    local ($ARG) = @ARG;

    my %hash = %STATUS_CODE_HN_HASH;
    my $code = '';

    if ( /status \s+ code:.*?(\d+)/mix )
    {
        $code = $1;
    }

    #   Default value
    my $desc = "[WARN] there is no ret code description defined for [$code]";

    if ( exists $hash{$code} )
    {
        $desc = $hash{$code};
    }

    $debug  and  print "$id: code [$code] desc [$desc]\n";

    $code, $desc;
}

# }}}
# {{{ Test drivers

# ****************************************************************************
#
#   DESCRIPTION
#
#       Test drivers for the program. Exist when done. These programs are
#       never run in production release. If you want to run them, uncommand
#       the Main() call at the end of this file and replace it with call to
#       any of these functions
#
#   INPUT PARAMETERS
#
#       none
#
#   RETURN VALUES
#
#       none
#
# ****************************************************************************

sub TestDriverConfigFile ()
{
    my $id = "TestDriverConfigFile";

    $debug = 1;

    my $content = <<EOF;

# This is comment
# more

key1 = something
key2 = /path/to/file  # comment
   key3   =   1

   key4=123
multi key = multi string value

# End of configuration
EOF

    my %hash = ConfigFileParse $content;

    ConfigFileProcess \%hash;
}

sub TestDriverHttpPing ()
{
    #   Connect to a site, which can display the IP you're using.

    $debug = 5;
    Initialize();

    HttpPing   -url    => "http://ankka.com/?ip"
             , -regexp => '([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)'
             ;
}

sub TestDriverHNorg ()
{
    $debug = 1;
    Initialize();  # Need status codes

    my $str =<<'EOF';
HTTP/1.1 200 OK
Connection: close
Date: Sat, 29 May 2004 12:03:35 GMT
Server: Apache/1.3.28 (Unix) PHP/4.3.4 mod_perl/1.28
Content-Type: text/html
Client-Date: Sat, 29 May 2004 12:05:59 GMT
Client-Peer: 216.151.80.10:80
Client-Response-Num: 1
Client-Transfer-Encoding: chunked
Title: HN.ORG

<HTML><HEAD><TITLE>HN.ORG</TITLE></HEAD><BODY>
<!-- DDNS_Response_Code=101 -->
Status Code: <B>101</B><BR>
Notice: This is not a <I>real</I> response - it's only to stop the automated programs from DoS-ing HN.ORG.  The <I>real</I> update mechanism is no longer on the hostname www.hn.org - it's now on the hostname dup.hn.org.
</BODY></HTML>

EOF

    StatusCodeParseHNorg $str;


    $str =<<'EOF';
HTTP/1.1 401 (Unauthorized) Authorization Required
Connection: close
Date: Fri, 13 Aug 2004 06:06:40 GMT
Server: Apache/1.3.28 (Unix) PHP/4.3.4 mod_perl/1.28
WWW-Authenticate: Basic realm="Vanity Host Users"
Content-Type: text/html; charset=iso-8859-1
Client-Date: Fri, 13 Aug 2004 06:09:01 GMT
Client-Peer: 216.151.80.11:80
Client-Response-Num: 1
Client-Transfer-Encoding: chunked
Title: 401 Authorization Required

<!DOCTYPE HTML PUBLIC "-//IETF//DTD HTML 2.0//EN">
<HTML><HEAD>
<TITLE>401 Authorization Required</TITLE>
</HEAD><BODY>
<H1>Authorization Required</H1>
This server could not verify that you
are authorized to access the document
requested.  Either you supplied the wrong
credentials (e.g., bad password), or your
browser doesn't understand how to supply
the credentials required.<P>
</BODY></HTML>

EOF

    StatusCodeParseHNorg $str;

    $str =<<'EOF';
HTTP/1.1 200 OK
Connection: close
Date: Fri, 13 Aug 2004 06:06:25 GMT
Server: Apache/1.3.27 (Unix) PHP/4.3.2
Content-Type: text/html
Client-Date: Fri, 13 Aug 2004 06:09:02 GMT
Client-Peer: 63.215.241.204:80
Client-Response-Num: 1
Client-Transfer-Encoding: chunked
X-Powered-By: PHP/4.3.2

status=4

Bad authorization (user)
EOF

    StatusCodeParseHNorg $str;
}

sub TestDriverLinksysBEFW11S4 ()
{
    my $id = "TestDriverLinksysBEFW11S4";

    # The page from Linksys router looks like this.

    my $str =<<'EOF';
HTTP/1.1 200 OK
Connection: close
Pragma: no-cache
Content-Type: text/html
Expires: Thu, 13 Dec 1969 10:29:00 GMT
Client-Date: Sat, 22 Feb 2003 19:23:34 GMT
Client-Response-Num: 1

<html><head><style>A:active;A:link;{text-decoration:none;}A:visited{text-decoration:none;}</style></head><script src=Gozila.js></script><script language=JavaScript>function pppoeAction(F,I){  F.pppoeAct.value = I;   F.submit();}function showAlert(){alert('');}function DHCPAct(F,I){      F.dhcpAction.value = I; F.submit();}</script><body bgcolor=black><center><table border=0 cellspacing=0 cellpadding=0 width=700><tr><td colspan=2 background='tmp.gif' width=100% height=54><table border=0 cellspacing=3 width=100% height=54><tr><td colspan=11 height=22></td></tr><tr><td width=175 align=center height=23>&nbsp;</td><td align=center width=50 height=23 bgcolor=a5a4a1 background=''><a href='index.htm'><font face=verdana color=black size=1><b>Setup</a></td><td align=center width=50 height=23 bgcolor=a5a4a1 background=''><a href='Passwd.htm'><font face=verdana color=black size=1><b>Password</a></td><td align=center width=50 height=23 bgcolor=white background=''><a href='Status.htm'><font face=verdana color=f79400 size=1><b>Status</a></td><td align=center width=50 height=23 bgcolor=a5a4a1 background=''><a href='DHCP.htm'><font face=verdana color=black size=1><b>DHCP</a></td><td align=center width=50 height=23 bgcolor=a5a4a1 background=''><a href='Log.htm'><font face=verdana color=black size=1><b>Log</a></td><td align=center width=50 height=23 bgcolor=a5a4a1 background=''><a href='Security.htm'><font face=verdana color=black size=1><b>Security</a></td><td align=center width=50 height=23 bgcolor=a5a4a1 background=''><a href='Help.htm'><font face=verdana color=black size=1><b>Help</a></td><td align=center height=23 background=''>&nbsp;</td><td align=center width=50 height=23 bgcolor=f79400 background=''><a href='Filters.htm'><font face=verdana color=black size=1><b>Advanced</a></td><td width=30 align=center height=23 background=''>&nbsp;</td></tr></table><tr><th bgcolor=black width=26% height=100><font size=5 face=verdana color=white>STATUS</th><th bgcolor=white valign=top>      <table cellpadding=3 width=94%><tr><td><font size=2 face=verdana color=black>This screen displays the router's current status and settings. This information is read-only.       </td></tr></table></th></tr><tr><th colspan=2><table border=1 bgcolor=black cellspacing=3 width=100%><tr><th><table border=0 bgcolor=white cellspacing=0 width=100%><tr><th bgcolor=6666cc width=26% align=right><font color=white face=Arial size=2>Host Name:&nbsp;&nbsp;</th><td>&nbsp;&nbsp;&nbsp;<font face=verdana size=2><b></td></tr><tr><th bgcolor=6666cc align=right><font color=white face=Arial size=2>Firmware Version:&nbsp;&nbsp;</th><td>&nbsp;&nbsp;&nbsp;<font face=verdana size=2><b>1.44.2, Dec 20 2002</td></tr><tr><th bgcolor=6666cc align=right><font color=white face=Arial size=2><br>Login:&nbsp;&nbsp;</th><td><font face=verdana size=2><b><br>&nbsp;&nbsp;&nbsp;Disable</td></tr><!--LAN head--><tr><th bgcolor=6666cc align=right><font color=white face=Arial size=2><br>LAN:&nbsp;&nbsp;</th><td><br>&nbsp;&nbsp;&nbsp;<font face=verdana size=1>(MAC Address: 00-06-25-A4-EE-D0)</td></tr><tr><th bgcolor=6666cc>&nbsp;</th><td><table width=90%><tr><td  bgcolor=6666cc width=47%>&nbsp; &nbsp;<font color=white face=verdana size=2>IP Address:</td><td><font face=verdana size=2>192.168.1.1</td></tr><tr><td bgcolor=6666cc>&nbsp; &nbsp;<font color=white face=verdana size=2>Subnet Mask:</td><td><font face=verdana size=2>255.255.255.0</td></tr><tr><td bgcolor=6666cc>&nbsp; &nbsp;<font color=white face=verdana size=2>DHCP server:</td><td><font face=verdana size=2>Enabled</td></tr></table></td></tr><!--LAN tail--><!--WAN head--><tr><th bgcolor=6666cc align=right><font color=white face=Arial size=2><br>WAN: &nbsp;</th><td><br>&nbsp; &nbsp;<font face=verdana size=1>(MAC Address: 00-06-25-A4-EE-D1)</td></tr><tr><th bgcolor=6666cc>&nbsp;</th><td><table width=90%><tr><td bgcolor=6666cc width=47%>&nbsp; &nbsp;<font color=white face=verdana size=2>IP Address:</td><td><font face=verdana size=2>81.197.0.2</td></tr><tr><td bgcolor=6666cc>&nbsp; &nbsp;<font color=white face=verdana size=2>Subnet Mask:</td><td><font face=verdana size=2>255.255.248.0</td></tr><tr><td bgcolor=6666cc>&nbsp; &nbsp;<font color=white face=verdana size=2>Default Gateway:</td><td><font face=verdana size=2>81.197.0.1</td></tr><tr><td bgcolor=6666cc>&nbsp; &nbsp;<font color=white face=verdana size=2>DNS:</td><td><font face=verdana size=2>212.63.10.250<br>193.229.0.40<br>193.229.0.49</td></tr><tr><td bgcolor=6666cc>&nbsp; &nbsp;<font color=white face=verdana size=2>DHCP Remaining Time:</td><td><font face=verdana size=2> 0:38:41</td></tr></table></td></tr><!--WAN tail--><tr><th bgcolor=6666cc>&nbsp;</th><td>&nbsp;<form method=get action=Gozila.cgi> &nbsp; <input type=hidden name=dhcpAction><input type=button value=' DHCP Release ' onClick=DHCPAct(this.form,0)> <input type=button value=' DHCP Renew ' onClick=DHCPAct(this.form,1)> </form><form> &nbsp; <input type=button value=' DHCP Clients Table ' onClick=ViewDHCP()>  </form><p> </td></tr></table></th></tr></table></th></tr></table></center></body></html>
EOF

    $debug = 1;

    my $re = '.*IP +Address:.+?font[^>]+>+([\d.]+)';  # default test

    print "$id: REGEXP 1 [$re]\n";
    StringRegexpMatch $str, $re;

    my $ip = '([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)';
    $re = "(?i)(?:WAN.+?IP +Address.+?)$ip";

    print "$id: REGEXP 2 [$re]\n";
    StringRegexpMatch $str, $re;
}

sub TestDriverLinksysBEFW11S4v4 ()
{
    # The newer "Cisco model";

    my $id = "TestDriverLinksysBEFW11S4b4";

    # The page from Linksys router looks like this.

    my $str =<<'EOF';
HTTP/1.1 200 OK
Connection: close
Pragma: no-cache
Content-Type: text/html
Expires: Thu, 13 Dec 1969 10:29:00 GMT
Client-Date: Sat, 22 Feb 2003 19:23:34 GMT
Client-Response-Num: 1

<HTML><HEAD><TITLE>Setup</TITLE><META http-equiv=Content-Language content=en-us><META http-equiv=Content-Type content='text/html; charset=iso-8859-1'><style fprolloverstyle>BODY{FONT: 10pt Arial,Helvetica,sans-serif; COLOR: black}TH {FONT: bold 10pt Arial,Helvetica,sans-serif; COLOR: white;}TABLE {FONT: 10pt Arial,Helvetica,sans-serif; COLOR: black; BORDER: Medium White None; border-collapse: collapse}TD{font-size: 8pt; font-family: Arial, Helvetica, sans-serif}.num{FONT: 8pt Courier,serif;}.bar{background-color:white;}A{text-decoration: none;} A:link{color: #FFFFFF;}       A:visited{color: #FFFFFF;}.small A:link {	COLOR: #b5b5e6}.small A:visited {COLOR: #b5b5e6}A:hover {color: #00FFFF}.small A:hover {color: #00FFFF}</style><meta http-equiv=refresh content=60;url=RouterStatus.htm></HEAD><SCRIPT language=JavaScript>function pppoeAction(F,I){F.hid_dialAction.value = I;F.submit();}function DHCPAct(F,I){F.hid_dhcpAction.value = I;F.submit();}function showAlert(){alert('');}</SCRIPT><BODY ><DIV align=center><TABLE cellSpacing=0 cellPadding=0 width=809 border=0><TBODY><TR><TD width=95><IMG height=57 src='UI_Linksys.gif' width=165 border=0></TD><TD vAlign=bottom align=right width=714 bgColor=#6666cc><FONT style='FONT-SIZE: 7pt' color=#ffffff face=Arial>Firmware Version: 1.50.10&nbsp;&nbsp;</FONT></TD></TR><TR><TD width=808 colSpan=2 bgColor=#6666cc><IMG height=11 src='UI_10.gif' width=809 border=0></TD></TR></TBODY></TABLE><TABLE height=77 cellSpacing=0 cellPadding=0 width=809 bgColor=black border=0><TBODY><TR><TD style='FONT-WEIGHT: normal; FONT-SIZE: 10pt; COLOR: black; FONT-STYLE: normal; FONT-FAMILY: Arial, Helvetica, sans-serif; FONT-VARIANT: normal' borderColor=#000000 align=middle height=49 width=163><H3 style='MARGIN-TOP: 1px; MARGIN-BOTTOM: 1px'><FONT style='FONT-SIZE: 15pt' face=Arial color=#ffffff>Status</FONT></H3></TD><TD style='FONT-WEIGHT: normal; FONT-SIZE: 10pt; COLOR: black; FONT-STYLE: normal; FONT-FAMILY: Arial, Helvetica, sans-serif; FONT-VARIANT: normal' vAlign=center borderColor=#000000 width=646 bgColor=#000000 height=49><TABLE style='FONT-WEIGHT: normal; FONT-SIZE: 10pt; COLOR: black; FONT-STYLE: normal; FONT-FAMILY: Arial, Helvetica, sans-serif; BORDER-COLLAPSE: collapse; FONT-VARIANT: normal' height=33 cellSpacing=0 cellPadding=0 bgColor=#6666cc border=0><TBODY><TR><TD style='font-size:10pt; font-weight:bolder' bgColor=#6666cc height=33 align=right><FONT color='#ffffff'>Wireless-B Broadband Router&nbsp;<TD align=middle borderColor=#000000 borderColorLight=#000000 width=109 bgColor=#000000 borderColorDark=#000000 height=12 rowSpan=2><FONT color=#ffffff><SPAN style='FONT-SIZE: 8pt'><B>BEFW11S4</B></SPAN></FONT></TD></TR><TR><TD style='FONT-WEIGHT: normal; FONT-SIZE: 1pt; COLOR: black; FONT-STYLE: normal; FONT-FAMILY: Arial, Helvetica, sans-serif; FONT-VARIANT: normal' width=537 bgColor=#000000 height=1>&nbsp;</TD></TR><TR><TD width=646 bgColor=#000000 colSpan=2 height=32><TABLE id=AutoNumber1 style='FONT-WEIGHT: normal; FONT-SIZE: 10pt; COLOR: black; FONT-STYLE: normal; FONT-FAMILY: Arial, Helvetica, sans-serif; BORDER-COLLAPSE: collapse; FONT-VARIANT: normal' height=6 cellSpacing=0 cellPadding=0 width=637 border=0><TBODY><TR style='BORDER-RIGHT: medium none; BORDER-TOP: medium none; FONT-WEIGHT: normal; FONT-SIZE: 1pt; BORDER-LEFT: medium none; COLOR: black; BORDER-BOTTOM: medium none; FONT-STYLE: normal; FONT-FAMILY: Arial, Helvetica, sans-serif; FONT-VARIANT: normal' bgColor=#6666cc align=middle><TD width=73  height=1><IMG height=10 src=UI_06.gif width=73  border=0></TD><TD width=73  height=1><IMG height=10 src=UI_06.gif width=73  border=0></TD><TD width=73  height=1><IMG height=10 src=UI_06.gif width=73  border=0></TD><TD width=113 height=1><IMG height=10 src=UI_06.gif width=113 border=0></TD><TD width=95  height=1><IMG height=10 src=UI_06.gif width=95  border=0></TD><TD width=73  height=1><IMG height=10 src=UI_07.gif width=73  border=0></TD><TD width=146 height=1><IMG height=10 src=UI_06.gif width=146 border=0></TD></TR><TR><TD bgColor=000000 height=20 align=middle><FONT style='FONT-WEIGHT: 700' color=#ffffff><A style='TEXT-DECORATION: none' href='index.htm'>Setup</a></FONT></TD><TD align=middle bgColor=000000 height=20><FONT style='FONT-WEIGHT: 700' color=#ffffff><A style='TEXT-DECORATION: none' href='WLbasic.htm'>Wireless</A></FONT></TD><TD align=middle bgColor=000000 height=20><FONT style='FONT-WEIGHT: 700' color=#ffffff><A style='TEXT-DECORATION: none' href='Filter.htm'>Security</A></FONT></TD><TD align=middle bgColor=000000 height=20><FONT style='FONT-WEIGHT: 700' color=#ffffff><A style='TEXT-DECORATION: none' href='Forwarding.htm'>Applications &amp; Gaming</A></FONT></TD><TD align=middle bgColor=000000 height=20><FONT style='FONT-WEIGHT: 700' color=#ffffff><A style='TEXT-DECORATION: none' href='Management.htm'>Administration</A></FONT></TD><TD align=middle bgColor=6666cc height=20><FONT style='FONT-WEIGHT: 700' color=#ffffff><A style='TEXT-DECORATION: none'  href='RouterStatus.htm'>Status</A></FONT></TD></TR><TR><TD width=643 bgColor=#6666cc colSpan=7 height=21><TABLE height=21 cellSpacing=0 cellPadding=0 bordercolor=black><TR align=center><TD width=220><FONT style='COLOR: white'>Router</font></TD><TD><P class=bar>&nbsp;</P></TD><TD width=220 class=small><A href='LanStatus.htm'>Local Network</A></TD><td width=220>&nbsp;</td><td width=220>&nbsp;</td></TR></TABLE></TD></TR></TABLE></TD></TR></TABLE></TD></TR></TABLE><TABLE height=5 cellSpacing=0 cellPadding=0 width=806 bgColor=black border=0><TR bgColor=black><TD style='FONT-WEIGHT: normal; FONT-SIZE: 10pt; COLOR: black; FONT-STYLE: normal; FONT-FAMILY: Arial, Helvetica, sans-serif; FONT-VARIANT: normal' borderColor=#e7e7e7 width=163 bgColor=#e7e7e7 height=1><IMG height=15 src='UI_03.gif' width=164 border=0></TD><TD style='FONT-WEIGHT: normal; FONT-SIZE: 10pt; COLOR: black; FONT-STYLE: normal; FONT-FAMILY: Arial, Helvetica, sans-serif; FONT-VARIANT: normal' width=646 height=1><IMG height=15 src='UI_02.gif' width=645 border=0></TD></TR></TABLE><TABLE id=AutoNumber9 style='BORDER-COLLAPSE: collapse' borderColor=#111111 height=23 cellSpacing=0 cellPadding=0 width=809 border=0><TR><TD width=633><TABLE cellSpacing=0 cellPadding=0 border=0><TR><TD width=156 bgColor=#000000 colSpan=3 height=25><P align=right><B><FONT style='FONT-SIZE: 9pt' face=Arial color=#ffffff>Router Information</FONT></B></P></TD><TD width=8 bgColor=#000000 height=25>&nbsp;</TD><TD width=14 height=25>&nbsp;</TD><TD width=17 height=25>&nbsp;</TD><TD width=13 height=25>&nbsp;</TD><TD width=101 height=25>&nbsp;</TD><TD width=296 height=25>&nbsp;</TD><TD width=13 height=25>&nbsp;</TD><TD width=15 height=25 background='UI_05.gif'>&nbsp;</TD></TR><TR><TD width=156 bgColor=#e7e7e7 colSpan=3 height=25>&nbsp;</TD><TD width=8 height=25 background='UI_04.gif'>&nbsp;</TD><TD colspan=3 height=25>&nbsp;</TD><TD width=101 height=25><FONT style='FONT-SIZE: 8pt'>Firmware Version:</FONT></TD><TD><FONT style='FONT-SIZE: 8pt'><B>1.50.10, Jan 16 2004</B></FONT></TD><TD width=13 height=25>&nbsp;</TD><TD width=15 height=25 background='UI_05.gif'>&nbsp;</TD></TR><TR><TD width=156 bgColor=#e7e7e7 colSpan=3 height=25>&nbsp;</TD><TD width=8 height=25 background='UI_04.gif'>&nbsp;</TD><TD colspan=3 height=25>&nbsp;</TD><TD><FONT style='FONT-SIZE: 8pt'>MAC Address:</FONT></TD><TD><FONT style='FONT-SIZE: 8pt'><B>00-0F-66-23-C2-56</B></FONT></TD><TD width=13 height=25>&nbsp;</TD><TD width=15 height=25 background='UI_05.gif'>&nbsp;</TD></TR><TR><TD width=156 bgColor=#000000 colSpan=3 height=25><P align=right><B><FONT style='FONT-SIZE: 9pt' color=#ffffff>Internet</FONT></B></P></TD><TD width=8 bgColor=#000000 height=25>&nbsp;</TD><TD colSpan=6>&nbsp;</TD><TD width=15 height=25 background='UI_05.gif'>&nbsp;</TD></TR><TR><TD width=156 bgColor=#e7e7e7 colSpan=3 height=25><P align=right><b>Configuration Type</b></TD><TD width=8 height=25 background='UI_04.gif'>&nbsp;</TD><TD colspan=3 height=25>&nbsp;</TD><TD><FONT style='FONT-SIZE: 8pt'>Login Type:</FONT></TD><TD><FONT style='FONT-SIZE: 8pt'><B>PPPOE</B></FONT></TD><TD width=13 height=25>&nbsp;</TD><TD width=15 height=25 background='UI_05.gif'>&nbsp;</TD></TR><form name=F1 method=get action=Gozila.cgi><input type=hidden name='RouterStatus.htm' value=255><input type=hidden name=hid_returnPoint value=''><TR><TD width=156 bgColor=#e7e7e7 colSpan=3 height=25>&nbsp;</TD><TD width=8 height=25><IMG height=35 src='UI_04.gif' width=8 border=0></TD><TD colspan=3 bgColor=#ffffff height=25>&nbsp;</TD><TD width=101 bgColor=#ffffff height=25><FONT style='FONT-SIZE: 8pt'>Login Status:</FONT></TD><TD width=296 bgColor=#ffffff height=25><FONT style='FONT-SIZE: 8pt'><B><input type=hidden name=hid_dialAction value=0>Connected <input type=button value='Disconnect' onClick='pppoeAction(this.form,2)'></B></FONT></TD><TD width=13 bgColor=#ffffff height=25>&nbsp;</TD><TD width=15 bgColor=#ffffff height=25><IMG height=35 src='UI_05.gif' width=15 border=0></TD></TR></form><TR><TD width=156 bgColor=#e7e7e7 colSpan=3 height=25>&nbsp;</TD><TD width=8 height=25 background='UI_04.gif'>&nbsp;</TD><TD colspan=3 height=25>&nbsp;</TD><TD><FONT style='FONT-SIZE: 8pt'>Internet IP Address:</FONT></TD><TD><FONT style='FONT-SIZE: 8pt'><B>69.110.12.53</B></FONT></TD><TD width=13 height=25>&nbsp;</TD><TD width=15 height=25 background='UI_05.gif'>&nbsp;</TD></TR><TR><TD width=156 bgColor=#e7e7e7 colSpan=3 height=25>&nbsp;</TD><TD width=8 height=25 background='UI_04.gif'>&nbsp;</TD><TD colspan=3 height=25>&nbsp;</TD><TD><FONT style='FONT-SIZE: 8pt'>DNS 1:</FONT></TD><TD><FONT style='FONT-SIZE: 8pt'><B>63.203.35.55</B></FONT></TD><TD width=13 height=25>&nbsp;</TD><TD width=15 height=25 background='UI_05.gif'>&nbsp;</TD></TR><TR><TD width=156 bgColor=#e7e7e7 colSpan=3 height=25>&nbsp;</TD><TD width=8 height=25 background='UI_04.gif'>&nbsp;</TD><TD colspan=3 height=25>&nbsp;</TD><TD height=25><FONT style='FONT-SIZE: 8pt'>DNS 2:</FONT></TD><TD height=25><FONT style='FONT-SIZE: 8pt'><B>206.13.28.12</B></FONT></TD><TD width=13 height=25>&nbsp;</TD><TD width=15 height=25 background='UI_05.gif'>&nbsp;</TD></TR><TR><TD width=156 bgColor=#e7e7e7 colSpan=3 height=25>&nbsp;</TD><TD width=8 height=25 background='UI_04.gif'>&nbsp;</TD><TD colspan=3 height=25>&nbsp;</TD><TD height=25><FONT style='FONT-SIZE: 8pt'>DNS 3:</FONT></TD><TD height=25><FONT style='FONT-SIZE: 8pt'><B>0.0.0.0</B></FONT></TD><TD width=13 height=25>&nbsp;</TD><TD width=15 height=25 background='UI_05.gif'>&nbsp;</TD></TR><TR><TD width=156 bgColor=#e7e7e7 colSpan=3 height=1>&nbsp;</TD><TD width=8 background='UI_04.gif'>&nbsp;</TD><TD colspan=6 height=1>&nbsp;</TD><TD width=15 height=1 background='UI_05.gif'>&nbsp;</TD></TR><TR><TD width=156 bgColor=#e7e7e7 colSpan=3 height=1>&nbsp;</TD><TD width=8 background='UI_04.gif'>&nbsp;</TD><TD colSpan=6><HR color=#b5b5e6 SIZE=1></TD><TD width=15 background='UI_05.gif'>&nbsp;</TD></TR><TR><TD width=156 bgColor=#e7e7e7 colSpan=3 height=1>&nbsp;</TD><TD width=8 background='UI_04.gif'>&nbsp;</TD><TD colspan=6 height=1>&nbsp;</TD><TD width=15 height=1 background='UI_05.gif'>&nbsp;</TD></TR><TR><TD width=156 bgColor=#e7e7e7 colSpan=3 height=25>&nbsp;</TD><TD width=8 height=25 background='UI_04.gif'>&nbsp;</TD><TD colspan=3 height=25>&nbsp;</TD><TD colSpan=2 height=25> </TD><TD width=13 height=25>&nbsp;</TD><TD width=15 height=25 background='UI_05.gif'>&nbsp;</TD></TR></form><TR><TD width=156 bgColor=#e7e7e7 colSpan=3 height=1>&nbsp;</TD><TD width=8 background='UI_04.gif'>&nbsp;</TD><TD colspan=6 height=1>&nbsp;</TD><TD width=15 height=1 background='UI_05.gif'>&nbsp;</TD></TR><TR><TD width=156 bgColor=#e7e7e7 colSpan=3 height=1>&nbsp;</TD><TD width=8 background='UI_04.gif'>&nbsp;</TD><TD colspan=6 height=1>&nbsp;</TD><TD width=15 height=1 background='UI_05.gif'>&nbsp;</TD></TR><TR><TD width=156 colspan=3 bgColor=#e7e7e7 height=5>&nbsp;</TD><TD width=8 height=5 background='UI_04.gif'>&nbsp;</TD><TD colspan=6>&nbsp;</TD><TD width=15 height=5 background='UI_05.gif'>&nbsp;</TD></TR></TABLE></TD><TD vAlign=top width=176 bgColor=#6666cc><TABLE cellSpacing=0 cellPadding=0 width=176 border=0><TR><TD width=11 bgColor=#6666cc height=25>&nbsp;</TD><TD width=156 bgColor=#6666cc height=25><FONT color=white size=3><b>Router Status</b></font><p><FONT color=white>This screen provides the Router's current status information in a read-only format.<p><b>Login Type</b><br>This field shows the Internet login status. When you choose PPPoE, RAS, PPTP, or HBS as the login method, you can click the <b>Connect</b> button to log in. If you click the <b>Disconnect</b> button, the Router will not dial up again until you click the <b>Connect</b> button.<p>If your connection is DHCP or Static IP, the Status screen will show you the Internet IP Address, Subnet mask,<p><a target="_blank" href="HRouterStatus.htm"><b><u>More...</u></b></TD><TD width=9 bgColor=#6666cc height=25>&nbsp;</TD></TR></TABLE></TD></TR><TR><TD width=809 colSpan=2><TABLE cellSpacing=0 cellPadding=0 border=0><TR><TD width=156 bgColor=#e7e7e7 height=30>&nbsp;</TD><TD width=8 background='UI_04.gif'>&nbsp;</TD><TD width=131>&nbsp;</TD><TD width=323>&nbsp;</TD><TD width=15 background='UI_05.gif'>&nbsp;</TD><TD width=176 bgColor=#6666cc rowSpan=2><IMG height=64 src='UI_Cisco.gif' width=176 border=0></TD></TR><TR><TD width=156 bgColor=#000000>&nbsp;</TD><TD width=8 bgColor=#000000>&nbsp;</TD><TD width=131 bgColor=#6666cc>&nbsp;</TD><TD width=323 bgColor=#6666cc><DIV align=center><TABLE height=19 cellSpacing=0 cellPadding=0 width=117 align=right border=0><TR><TD align=middle width=101 bgColor=#434a8f><!--<INPUT onclick=window.location.replace('RouterStatus.htm') type=button value=Refresh>--><FONT style='FONT-WEIGHT: 700; FONT-SIZE: 8pt' face=Arial color=#ffffff><A href='RouterStatus.htm'>Refresh</A></TD><TD width=8 bgColor=#6666cc>&nbsp;</TD></TR></TABLE></DIV></TD><TD width=15 bgColor=#000000 height=33>&nbsp;</TD></TR></TABLE></TD></TR></TABLE></DIV></BODY></HTML>
EOF

    $debug = 1;

    my $re = 'IP +Address:.+?<B>\s*([\d.]+)';  # default test

    print "$id: REGEXP 1 [$re]\n";
    StringRegexpMatch $str, $re;
}

sub TestDriverLinksysWRT54GL ()
{
    my $id = "TestDriverLinksysWRT54GL";

    # The page from Linksys router looks like this.

    my $str =<<'EOF';
HTTP/1.0 200 Ok
Cache-Control: no-cache
Cache-Control: no-cache
Connection: close
Date: Wed, 30 Aug 2006 13:11:30 GMT
Pragma: no-cache
Pragma: no-cache
Server: httpd
Content-Type: text/html
Expires: 0
Expires: 0
Client-Date: Wed, 30 Aug 2006 10:10:50 GMT
Client-Peer: 192.168.1.1:80
Client-Response-Num: 1
Link: <style.css>; rel="stylesheet"; type="text/css"
Title: Router Status


<!--
*********************************************************
*   Copyright 2003, CyberTAN  Inc.  All Rights Reserved *
*********************************************************

This is UNPUBLISHED PROPRIETARY SOURCE CODE of CyberTAN Inc.
the contents of this file may not be disclosed to third parties,
copied or duplicated in any form without the prior written
permission of CyberTAN Inc.

This software should be used as a reference only, and it not
intended for production use!


THIS SOFTWARE IS OFFERED "AS IS", AND CYBERTAN GRANTS NO WARRANTIES OF ANY
KIND, EXPRESS OR IMPLIED, BY STATUTE, COMMUNICATION OR OTHERWISE.  CYBERTAN
SPECIFICALLY DISCLAIMS ANY IMPLIED WARRANTIES OF MERCHANTABILITY, FITNESS
FOR A SPECIFIC PURPOSE OR NONINFRINGEMENT CONCERNING THIS SOFTWARE
-->


<HTML><HEAD><TITLE>Router Status</TITLE>
<meta http-equiv="expires" content="0">
<meta http-equiv="cache-control" content="no-cache">
<meta http-equiv="pragma" content="no-cache">


<link rel="stylesheet" type="text/css" href="style.css">
<style fprolloverstyle>
A:hover {color: #00FFFF}
.small A:hover {color: #00FFFF}
</style>

<SCRIPT src="common.js"></SCRIPT>
<SCRIPT language="Javascript" type="text/javascript" src="lang_pack/capsec.js"></SCRIPT>
<SCRIPT language="javascript" type="text/javascript" src="lang_pack/share.js"></SCRIPT>
<SCRIPT language="javascript" type="text/javascript" src="lang_pack/help.js"></SCRIPT>
<SCRIPT language="javascript" type="text/javascript" src="lang_pack/capwrt54g.js"></SCRIPT>
<SCRIPT language="Javascript" type="text/javascript" src="lang_pack/capstatus.js"></SCRIPT>
<SCRIPT language="Javascript" type="text/javascript" src="lang_pack/capsetup.js"></SCRIPT>
<SCRIPT language="Javascript" type="text/javascript" src="lang_pack/layout.js"></SCRIPT>

<SCRIPT language=JavaScript>
document.title = share.router;
function DHCPAction(F,I)
{
	F.submit_type.value = I;
	F.submit_button.value = "Status_Router";
	F.change_action.value = "gozila_cgi";
	F.submit();
}
function Connect(F,I)
{
	F.submit_type.value = I;
	F.submit_button.value = "Status_Router";
	F.change_action.value = "gozila_cgi";
	F.submit();
}
function init()
{

}
function ShowAlert(M)
{
	var str = "";
	var mode = "";
	var wan_ip = "81.197.175.198";
	var wan_proto = "dhcp";
	var ac_name = "";
	var srv_name = "";

	if(document.status.wan_proto.value == "pppoe")
		mode = "PPPoE";
	else if(document.status.wan_proto.value == "l2tp")
		mode = "L2TP";
	else if(document.status.wan_proto.value == "heartbeat")
		mode = "HBS";
	else
		mode = "PPTP";

	if(M == "AUTH_FAIL" || M == "PAP_AUTH_FAIL" || M == "CHAP_AUTH_FAIL")
                str = mode + hstatrouter2.authfail;
//              str = mode + " authentication fail";
	else if(M == "IP_FAIL" || (M == "TIMEOUT" && wan_ip == "0.0.0.0")) {
		if(mode == "PPPoE") {
			if(hstatrouter2.pppoenoip)	// For DE
				str = hstatrouter2.pppoenoip;
			else
				str = hstatrouter2.noip + mode + hstatrouter2.server;
		}
		else
                	str = hstatrouter2.noip + mode + hstatrouter2.server;
	}
//              str = "Can not get a IP address from " + mode + " server";
        else if(M == "NEG_FAIL")
                str = mode + hstatrouter2.negfail;
//              str = mode + " negotication fail";
        else if(M == "LCP_FAIL")
                str = mode + hstatrouter2.lcpfail;
//              str = mode + " LCP negotication fail";
        else if(M == "TCP_FAIL" || (M == "TIMEOUT" && wan_ip != "0.0.0.0" && wan_proto == "heartbeat"))
                str = hstatrouter2.tcpfail + mode + hstatrouter2.server;
//              str = "Can not build a TCP connection to " + mode + " server";
	else
                str = hstatrouter2.noconn + mode + hstatrouter2.server;
//              str = "Can not connect to " + mode + " server";

	alert(str);

	Refresh();
}
var value=0;
function Refresh()
{
	var refresh_time = "";
	if(refresh_time == "")	refresh_time = 60000;
	if (value>=1)
	{
		window.location.replace("Status_Router.asp");
	}
	value++;
	timerID=setTimeout("Refresh()",refresh_time);
}
function ViewDHCP()
{
	dhcp_win = self.open('DHCPTable.asp','inLogTable','alwaysRaised,resizable,scrollbars,width=720,height=600');
	dhcp_win.focus();
}
function localtime()
{
        tmp = "Wed, 30 Aug 2006 13:11:30";
        if( tmp == "Not Available")
                document.write(satusroute.localtime);
        else
                document.write(tmp);
}
</SCRIPT>

<BODY onload=init()>
<DIV align=center>
<FORM name=status method=post action=apply.cgi>
<input type=hidden name=submit_button>
<input type=hidden name=submit_type>
<input type=hidden name=change_action>
<input type=hidden name=wan_proto value='dhcp'>

<TABLE cellSpacing=0 cellPadding=0 width=809 border=0>
  <TBODY>
  <TR>
    <TD width=95><IMG src="image/UI_Linksys.gif" border=0 width="165" height="57"></TD>
    <TD vAlign=bottom align=right width=714 bgColor=#6666cc><FONT
      style="FONT-SIZE: 7pt" color=#ffffff><FONT face=Arial><script>Capture(share.firmwarever)</script>:&nbsp;v4.30.7&nbsp;&nbsp;&nbsp;</FONT></FONT></TD></TR>
  <TR>
    <TD width=808 bgColor=#6666cc colSpan=2><IMG height=11
      src="image/UI_10.gif" width=809
border=0></TD></TR></TBODY></TABLE>
<TABLE height=77 cellSpacing=0 cellPadding=0 width=809 bgColor=black border=0>
  <TBODY>
  <TR>
    <TD
    style="FONT-WEIGHT: normal; FONT-SIZE: 10pt; COLOR: black; FONT-STYLE: normal; FONT-FAMILY: Arial, Helvetica, sans-serif; FONT-VARIANT: normal"
    borderColor=#000000 align=middle width=163 height=49>
      <H3 style="MARGIN-TOP: 1px; MARGIN-BOTTOM: 1px"><FONT
      style="FONT-SIZE: 15pt" face=Arial color=#ffffff><script>Capture(bmenu.statu)</script></FONT></H3></TD>
    <TD
    style="FONT-WEIGHT: normal; FONT-SIZE: 10pt; COLOR: black; FONT-STYLE: normal; FONT-FAMILY: Arial, Helvetica, sans-serif; FONT-VARIANT: normal"
    vAlign=center borderColor=#000000 width=646 bgColor=#000000 height=49>
      <TABLE
      style="FONT-WEIGHT: normal; FONT-SIZE: 10pt; COLOR: black; FONT-STYLE: normal; FONT-FAMILY: Arial, Helvetica, sans-serif; BORDER-COLLAPSE: collapse; FONT-VARIANT: normal"
      height=33 cellSpacing=0 cellPadding=0 bgColor=#6666cc border=0>
        <TBODY>
        <TR>
          <TD style="FONT-WEIGHT: bolder; FONT-SIZE: 10pt" align=right
          bgColor=#6666cc height=33><FONT color=#ffffff><script>productname()</script>&nbsp;&nbsp;</FONT></TD>
          <TD borderColor=#000000 borderColorLight=#000000 align=middle
          width=109 bgColor=#000000 borderColorDark=#000000 height=12
            rowSpan=2><FONT color=#ffffff><SPAN
            style="FONT-SIZE: 8pt"><B>WRT54GL</B></SPAN></FONT></TD></TR>
        <TR>
          <TD
          style="FONT-WEIGHT: normal; FONT-SIZE: 1pt; COLOR: black; FONT-STYLE: normal; FONT-FAMILY: Arial, Helvetica, sans-serif; FONT-VARIANT: normal"
          width=537 bgColor=#000000 height=1>&nbsp;</TD></TR>
        <TR>
          <TD width=646 bgColor=#000000 colSpan=2 height=32>
            <TABLE id=AutoNumber1
            style="FONT-WEIGHT: normal; FONT-SIZE: 10pt; COLOR: black; FONT-STYLE: normal; FONT-FAMILY: Arial, Helvetica, sans-serif; BORDER-COLLAPSE: collapse; FONT-VARIANT: normal"
            height=6 cellSpacing=0 cellPadding=0 width=646 border=0>
              <TBODY>
              <TR
              style="BORDER-RIGHT: medium none; BORDER-TOP: medium none; FONT-WEIGHT: normal; FONT-SIZE: 1pt; BORDER-LEFT: medium none; COLOR: black; BORDER-BOTTOM: medium none; FONT-STYLE: normal; FONT-FAMILY: Arial, Helvetica, sans-serif; FONT-VARIANT: normal" align=middle bgColor=#6666cc>

<!--
                <TD width=83 height=1><IMG height=10 src="image/UI_06.gif" width=83 border=0></TD>
                <TD width=73 height=1><IMG height=10 src="image/UI_06.gif" width=83 border=0></TD>
                <TD width=113 height=1><IMG height=10 src="image/UI_06.gif" width=83 border=0></TD>
                <TD width=103 height=1><IMG height=10 src="image/UI_06.gif" width=103 border=0></TD>
                <TD width=85 height=1><IMG height=10 src="image/UI_06.gif" width=100 border=0></TD>
                <TD width=115 height=1><IMG height=10 src="image/UI_06.gif" width=115 border=0></TD>
                <TD width=74 height=1><IMG height=10 src="image/UI_07.gif" width=79 border=0></TD>
-->
                <script>document.write("<TD width=" + ui_06.w1 + " height=8 background=image/UI_06.gif></TD>")</script>
                <script>document.write("<TD width=" + ui_06.w2 + " height=8 background=image/UI_06.gif></TD>")</script>
                <script>document.write("<TD width=" + ui_06.w3 + " height=8 background=image/UI_06.gif></TD>")</script>
                <script>document.write("<TD width=" + ui_06.w4 + " height=8 background=image/UI_06.gif></TD>")</script>
                <script>document.write("<TD width=" + ui_06.w5 + " height=8 background=image/UI_06.gif></TD>")</script>
                <script>document.write("<TD width=" + ui_06.w6 + " height=8 background=image/UI_06.gif></TD>")</script>
                <script>document.write("<TD width=" + ui_06.w7 + " height=8 background=image/UI_07.gif></TD>")</script>

              </TR>
              <TR>
                <TD align=middle bgColor=#000000 height=20><FONT
                  style="FONT-WEIGHT: 700" color=#ffffff><A
                  style="TEXT-DECORATION: none"
                  href="index.asp"><script>Capture(bmenu.setup)</script></A></FONT></TD>
                <TD align=middle bgColor=#000000 height=20><FONT
                  style="FONT-WEIGHT: 700" color=#ffffff>
                <a style="TEXT-DECORATION: none" href="Wireless_Basic.asp"><script>Capture(bmenu.wireless)</script></a></FONT></TD>
                <TD align=middle bgColor=#000000 height=20><FONT
                  style="FONT-WEIGHT: 700" color=#ffffff>
                <a style="TEXT-DECORATION: none" href="Firewall.asp"><script>Capture(bmenu.security)</script></a></FONT></TD>
                <TD align=middle bgColor=#000000 height=20><FONT
                  style="FONT-WEIGHT: 700" color=#ffffff>
                <a style="TEXT-DECORATION: none" href="Filters.asp"><script>Capture(bmenu.accrestriction)</script></a></FONT></TD>
                <TD align=middle bgColor=#000000 height=20>
                  <P style="MARGIN-BOTTOM: 4px"><FONT style="FONT-WEIGHT: 700"
                  color=#ffffff>
                  <a style="TEXT-DECORATION: none" href="Forward.asp"><script>Capture(bmenu.applications)</script> <BR>&amp; <script>Capture(bmenu.gaming)</script></a>&nbsp;&nbsp;&nbsp;&nbsp;</FONT></P></TD>
                <TD align=middle bgColor=#000000 height=20>
                  <P style="MARGIN-BOTTOM: 4px"><FONT style="FONT-WEIGHT: 700"
                  color=#ffffff>
                  <a style="TEXT-DECORATION: none" href="Management.asp"><script>Capture(bmenu.admin)</script></a>&nbsp;&nbsp;&nbsp;&nbsp;</FONT></P></TD>
                <TD align=middle bgColor=#6666cc height=20>
                  <P style="MARGIN-BOTTOM: 4px"><FONT style="FONT-WEIGHT: 700"
                  color=#ffffff><script>Capture(bmenu.statu)</script>&nbsp;&nbsp;&nbsp;&nbsp;</FONT></P></TD>
              </TR>
              <TR>
                <TD width=643 bgColor=#6666cc colSpan=7 height=21>
                  <TABLE borderColor=black height=21 cellSpacing=0 cellPadding=0 width=643>
                    <TBODY>
                    <TR align=left>

                      <!-- TD width=25></TD -->
                      <script>document.write("<TD width=" + sta_width.w1 + "></TD>")</script>

                      <!-- TD width=65 -->
                      <script>document.write("<TD width=" + sta_width.w2 + ">")</script>
                      <FONT style="COLOR: white"><script>Capture(share.router)</script></FONT></TD>

                      <TD width=1 align=center><P class=bar><font color='white'><b>|</b></font></P></TD>

                      <!-- TD width=25></TD -->
                      <script>document.write("<TD width=" + sta_width.w3 + "></TD>")</script>

                      <!-- TD class=small width=100 -->
                      <script>document.write("<TD class=small width=" + sta_width.w4 + ">")</script>
                      <A href="Status_Lan.asp"><script>Capture(statopmenu.localnet)</script></A></TD>

                      <TD width=1 align=center><P class=bar><font color='white'><b>|</b></font></P></TD>

                      <!-- TD width=25></TD -->
                      <script>document.write("<TD width=" + sta_width.w5 + "></TD>")</script>

                      <!-- TD class=small width=100 -->
                      <script>document.write("<TD class=small width=" + sta_width.w6 + ">")</script>
                      <span >&nbsp;</span><A href="Status_Wireless.asp"><script>Capture(bmenu.wireless)</script></A></TD>
<!--
                      <TD width=1 align=center><P class=bar><font color='white'><b>|</b></font></P></TD>

                      <script>document.write("<TD width=" + sta_width.w7 + "></TD>")</script>

                      <script>document.write("<TD class=small width=" + sta_width.w8 + ">")</script>
                      <A href="Status_Performance.asp">System Performance</A></TD>
-->
                      <TD>&nbsp;</TD>
		    </TR>
                    </TBODY>
                  </TABLE>
                </TD>
              </TR></TBODY></TABLE></TD></TR></TBODY></TABLE></TD></TR></TBODY></TABLE>
<TABLE height=5 cellSpacing=0 cellPadding=0 width=806 bgColor=black border=0>
  <TBODY>
  <TR bgColor=black>
    <TD
    style="FONT-WEIGHT: normal; FONT-SIZE: 10pt; COLOR: black; FONT-STYLE: normal; FONT-FAMILY: Arial, Helvetica, sans-serif; FONT-VARIANT: normal"
    borderColor=#e7e7e7 width=163 bgColor=#e7e7e7 height=1><IMG height=15
      src="image/UI_03.gif" width=164 border=0></TD>
    <TD
    style="FONT-WEIGHT: normal; FONT-SIZE: 10pt; COLOR: black; FONT-STYLE: normal; FONT-FAMILY: Arial, Helvetica, sans-serif; FONT-VARIANT: normal"
    width=646 height=1><IMG height=15 src="image/UI_02.gif"
      width=645 border=0></TD></TR></TBODY></TABLE>
<TABLE id=AutoNumber9 style="BORDER-COLLAPSE: collapse" borderColor=#111111
height=23 cellSpacing=0 cellPadding=0 width=809 border=0>
  <TBODY>
  <TR>
    <TD width=633>
      <TABLE height=100% cellSpacing=0 cellPadding=0 border=0>
        <TBODY>
        <TR>
          <TD width=156 bgColor=#000000 height=25>
            <P align=right><B><FONT style="FONT-SIZE: 9pt" face=Arial
            color=#ffffff><script>Capture(staleftmenu.routerinfo)</script></B></P></TD>
          <TD width=8 bgColor=#000000 height=25>&nbsp;</TD>
          <TD width=14 height=25>&nbsp;</TD>
          <TD width=17 height=25>&nbsp;</TD>
          <TD width=13 height=25>&nbsp;</TD>
          <TD width=101 height=25>&nbsp;</TD>
          <TD width=296 height=25>&nbsp;</TD>
          <TD width=13 height=25>&nbsp;</TD>
          <TD width=15 background=image/UI_05.gif height=25>&nbsp;</TD></TR>
        <TR>
          <TD width=156 bgColor=#e7e7e7 height=25>&nbsp;</TD>
          <TD width=8 background=image/UI_04.gif height=25>&nbsp;</TD>
          <TD colSpan=3 height=25>&nbsp;</TD>
          <TD width=101 height=25><script>Capture(share.firmwarever)</script>:&nbsp;</TD>
          <TD><B>v4.30.7, Jun. 20, 2006</B></TD>
          <TD width=13 height=25>&nbsp;</TD>
          <TD width=15 background=image/UI_05.gif height=25>&nbsp;</TD></TR>
        <TR>
          <TD width=156 bgColor=#e7e7e7 height=25>&nbsp;</TD>
          <TD width=8 background=image/UI_04.gif height=25>&nbsp;</TD>
          <TD colSpan=3 height=25>&nbsp;</TD>
          <TD width=101 height=25><script>Capture(stacontent.curtime)</script>:&nbsp;</TD>
          <!-- TD><b>Wed, 30 Aug 2006 13:11:30</b></TD -->
          <TD><b><script>localtime();</script></b></TD>
          <TD width=13 height=25>&nbsp;</TD>
          <TD width=15 background=image/UI_05.gif height=25>&nbsp;</TD></TR>
        <TR>
          <TD width=156 bgColor=#e7e7e7 height=25>&nbsp;</TD>
          <TD width=8 background=image/UI_04.gif height=25>&nbsp;</TD>
          <TD colSpan=3 height=25>&nbsp;</TD>
          <TD width=101 height=25><script>Capture(share.macaddr)</script>:&nbsp;</TD>
          <TD><b>00:18:39:C0:4F:1A</b></TD>
          <TD width=13 height=25>&nbsp;</TD>
          <TD width=15 background=image/UI_05.gif height=25>&nbsp;</TD></TR>
        <TR>
          <TD width=156 bgColor=#e7e7e7 height=25>&nbsp;</TD>
          <TD width=8 background=image/UI_04.gif height=25>&nbsp;</TD>
          <TD colSpan=3 height=25>&nbsp;</TD>
          <TD width=101 height=25><script>Capture(share.routename)</script>:&nbsp;</TD>
          <TD><b>WRT54GL&nbsp;</b></TD>
          <TD width=13 height=25>&nbsp;</TD>
          <TD width=15 background=image/UI_05.gif height=25>&nbsp;</TD></TR>
        <TR>
          <TD width=156 bgColor=#e7e7e7 height=25>&nbsp;</TD>
          <TD width=8 background=image/UI_04.gif height=25>&nbsp;</TD>
          <TD colSpan=3 height=25>&nbsp;</TD>
          <TD width=101 height=25><script>Capture(share.hostname)</script>:&nbsp;</TD>
          <TD><b>&nbsp;</b></TD>
          <TD width=13 height=25>&nbsp;</TD>
          <TD width=15 background=image/UI_05.gif height=25>&nbsp;</TD></TR>

        <TR>
          <TD width=156 bgColor=#e7e7e7 height=25>&nbsp;</TD>
          <TD width=8 background=image/UI_04.gif height=25>&nbsp;</TD>
          <TD colSpan=3 height=25>&nbsp;</TD>
          <TD width=101 height=25><script>Capture(share.domainname)</script>:&nbsp;</TD>
          <TD><b>
<script language=javascript>
if("" != "") {
	document.write("");
}
else {
	document.write("elisa-laajakaista.fi");
}
</script>
</b></TD>
          <TD width=13 height=25>&nbsp;</TD>
          <TD width=15 background=image/UI_05.gif height=25>&nbsp;</TD></TR>
        <TR>
          <TD width=156 bgColor=#000000 height=25>
            <P align=right><B><FONT style="FONT-SIZE: 9pt"
            color=#ffffff><span ><script>Capture(share.internet)</script></span></FONT></B></P></TD>
          <TD width=8 bgColor=#000000 height=25>&nbsp;</TD>
          <TD colSpan=6>&nbsp;</TD>
          <TD width=15 background=image/UI_05.gif
          height=25>&nbsp;</TD></TR>
        <TR>
          <TD width=156 bgColor=#e7e7e7 height=25>
          <p align="right"><FONT
style='FONT-WEIGHT: 700'><span ><script>Capture(share.cfgtype)</script></span></FONT></TD>
          <TD width=8 background=image/UI_04.gif
          height=25>&nbsp;</TD>
          <TD colSpan=3 height=25>&nbsp;</TD>
          <TD width=101 height=25><span><script>Capture(stacontent.logtype)</script></span>:&nbsp;</TD>
          <TD><b><script>Capture(setupcontent.dhcp)</script></b></TD>
          <TD width=13 height=25>&nbsp;</TD>
          <TD width=15 background=image/UI_05.gif height=25>&nbsp;</TD></TR>

<!--
*********************************************************
*   Copyright 2003, CyberTAN  Inc.  All Rights Reserved *
*********************************************************

This is UNPUBLISHED PROPRIETARY SOURCE CODE of CyberTAN Inc.
the contents of this file may not be disclosed to third parties,
copied or duplicated in any form without the prior written
permission of CyberTAN Inc.

This software should be used as a reference only, and it not
intended for production use!


THIS SOFTWARE IS OFFERED "AS IS", AND CYBERTAN GRANTS NO WARRANTIES OF ANY
KIND, EXPRESS OR IMPLIED, BY STATUTE, COMMUNICATION OR OTHERWISE.  CYBERTAN
SPECIFICALLY DISCLAIMS ANY IMPLIED WARRANTIES OF MERCHANTABILITY, FITNESS
FOR A SPECIFIC PURPOSE OR NONINFRINGEMENT CONCERNING THIS SOFTWARE
-->

<!--
        <TR>
          <TD width=156 bgColor=#e7e7e7 height=25>&nbsp;</TD>
          <TD width=8 background=image/UI_04.gif height=25>&nbsp;</TD>
          <TD colSpan=3 height=25>&nbsp;</TD>
          <TD><FONT style="FONT-SIZE: 8pt"><script>Capture(stacontent.logsta)</script>:&nbsp;</FONT></TD>
          <TD><FONT style="FONT-SIZE: 8pt"><B>
<script language=javascript>
        var status1 = "Disable";
        var status2 = "&nbsp;";
	if(status1 == "Status")         status1 = bmenu.statu;
        if(status2 == "Connecting")     status2 = hstatrouter2.connecting;
        else    if(status2 == "Disconnected")   status2 = hstatrouter2.disconnected;
        else    if(status2 == "Connected")      status2 = stacontent.conn;
	document.write(status2);
	document.write("&nbsp;&nbsp;");

	var but_arg = "";
        var wan_proto = "dhcp";
        var but_type = "";
	if(but_arg == "Connect")        but_value = stacontent.connect;
        else if(but_arg == "Disconnect")        but_value = hstatrouter2.disconnect;
        but_type = but_arg +"_" + wan_proto;
	document.write("<INPUT type=button value='"+but_value+"' onClick=Connect(this.form,'"+but_type+"')>");
</script>
</B></FONT></TD>
          <TD width=13 height=25>&nbsp;</TD>
          <TD width=15 background=image/UI_05.gif height=25>&nbsp;</TD></TR>
-->
        <TR>
          <TD width=156 bgColor=#e7e7e7 height=25>&nbsp;</TD>
          <TD width=8 background=image/UI_04.gif height=25>&nbsp;</TD>
          <TD colSpan=3 height=25>&nbsp;</TD>
          <TD><FONT style="FONT-SIZE: 8pt"><script>Capture(share.ipaddr)</script>:&nbsp;</FONT></TD>
          <TD><FONT style="FONT-SIZE: 8pt"><B>81.197.175.198</B></FONT></TD>
          <TD width=13 height=25>&nbsp;</TD>
          <TD width=15 background=image/UI_05.gif height=25>&nbsp;</TD></TR>
        <TR>
          <TD width=156 bgColor=#e7e7e7 height=25>&nbsp;</TD>
          <TD width=8 height=25><IMG height=30
            src="image/UI_04.gif" width=8 border=0></TD>
          <TD bgColor=#ffffff colSpan=3 height=25>&nbsp;</TD>
          <TD width=101 bgColor=#ffffff height=25><FONT
            style="FONT-SIZE: 8pt"><script>Capture(share.submask)</script>:&nbsp;</FONT></TD>
          <TD width=296 bgColor=#ffffff height=25><FONT
            style="FONT-SIZE: 8pt"><B>255.255.192.0</B></FONT></TD>
          <TD width=13 bgColor=#ffffff height=25>&nbsp;</TD>
          <TD width=15 bgColor=#ffffff height=25><IMG height=30
            src="image/UI_05.gif" width=15 border=0></TD></TR>
        <TR>
          <TD width=156 bgColor=#e7e7e7 height=25>&nbsp;</TD>
          <TD width=8 height=25><IMG height=30
            src="image/UI_04.gif" width=8 border=0></TD>
          <TD bgColor=#ffffff colSpan=3 height=25>&nbsp;</TD>
          <TD width=101 bgColor=#ffffff height=25><FONT
            style="FONT-SIZE: 8pt"><script>Capture(share.defgateway)</script>:&nbsp;</FONT></TD>
          <TD width=296 bgColor=#ffffff height=25><FONT
            style="FONT-SIZE: 8pt"><B>81.197.128.1</B></FONT></TD>
          <TD width=13 bgColor=#ffffff height=25>&nbsp;</TD>
          <TD width=15 bgColor=#ffffff height=25><IMG height=30
            src="image/UI_05.gif" width=15 border=0></TD></TR>
        <TR>
          <TD width=156 bgColor=#e7e7e7 height=25>&nbsp;</TD>
          <TD width=8 background=image/UI_04.gif
          height=25>&nbsp;</TD>
          <TD colSpan=3 height=25>&nbsp;</TD>
          <TD><FONT style="FONT-SIZE: 8pt"><script>Capture(share.dns)</script> 1:&nbsp;</FONT></TD>
          <TD><FONT style="FONT-SIZE: 8pt"><B>193.229.0.40</B></FONT></TD>
          <TD width=13 height=25>&nbsp;</TD>
          <TD width=15 background=image/UI_05.gif
          height=25>&nbsp;</TD></TR>
        <TR>
          <TD width=156 bgColor=#e7e7e7 height=25>&nbsp;</TD>
          <TD width=8 background=image/UI_04.gif
          height=25>&nbsp;</TD>
          <TD colSpan=3 height=25>&nbsp;</TD>
          <TD height=25><FONT style="FONT-SIZE: 8pt"><script>Capture(share.dns)</script> 2:&nbsp;</FONT></TD>
          <TD height=25><FONT style="FONT-SIZE: 8pt"><B>193.229.0.42</B></FONT></TD>
          <TD width=13 height=25>&nbsp;</TD>
          <TD width=15 background=image/UI_05.gif
          height=25>&nbsp;</TD></TR>
        <TR>
          <TD width=156 bgColor=#e7e7e7 height=25>&nbsp;</TD>
          <TD width=8 background=image/UI_04.gif
          height=25>&nbsp;</TD>
          <TD colSpan=3 height=25>&nbsp;</TD>
          <TD height=25><FONT style="FONT-SIZE: 8pt"><script>Capture(share.dns)</script> 3:&nbsp;</FONT></TD>
          <TD height=25><FONT style="FONT-SIZE: 8pt"><B></B></FONT></TD>
          <TD width=13 height=25>&nbsp;</TD>
          <TD width=15 background=image/UI_05.gif height=25>&nbsp;</TD></TR>
        <TR>
          <TD width=156 bgColor=#e7e7e7 height=25>&nbsp;</TD>
          <TD width=8 background=image/UI_04.gif
          height=25>&nbsp;</TD>
          <TD colSpan=3 height=25>&nbsp;</TD>
          <TD height=25><FONT style="FONT-SIZE: 8pt"><script>Capture(share.mtu)</script>:&nbsp;</FONT></TD>
          <TD height=25><FONT style="FONT-SIZE: 8pt"><B>1492</B></FONT></TD>
          <TD width=13 height=25>&nbsp;</TD>
          <TD width=15 background=image/UI_05.gif height=25>&nbsp;</TD></TR>


        <TR>
          <TD width=156 bgColor=#e7e7e7 height=25>&nbsp;</TD>
          <TD width=8 background=image/UI_04.gif height=25>&nbsp;</TD>
	  <TD width=14 height=25></TD>
          <TD colSpan=4 height=25><HR color=#b5b5e6 SIZE=1></TD>
          <TD width=13 height=25>&nbsp;</TD>
          <TD width=15 background=image/UI_05.gif height=25>&nbsp;</TD></TR>

        <TR>
          <TD width=156 bgColor=#e7e7e7 height=25>&nbsp;</TD>
          <TD width=8 background=image/UI_04.gif height=25>&nbsp;</TD>
          <TD colSpan=3 height=25>&nbsp;</TD>
          <TD colSpan=2 height=25>

<!-- % nvram_match("wan_proto", "dhcp", "<INPUT onclick=DHCPAction(this.form,'release') type=button value='DHCP Release'>&nbsp;&nbsp;&nbsp;&nbsp;<INPUT onclick=DHCPAction(this.form,'renew') type=button value='DHCP Renew'>"); % -->



<script>document.write("<INPUT onclick=DHCPAction(this.form,\'release\') type=button name=dhcp_release value=\"" + stabutton.dhcprelease + "\">");</script>

<script>document.write("<INPUT onclick=DHCPAction(this.form,\'renew\') type=button name=dhcp_renew value=\"" + stabutton.dhcprenew + "\">");</script>



    &nbsp;</TD>
          <TD width=13 height=25>&nbsp;</TD>
          <TD width=15 background=image/UI_05.gif height=25>&nbsp;</TD></TR>
        <TR>
          <TD width=156 bgColor=#e7e7e7>&nbsp;</TD>
          <TD width=8 background=image/UI_04.gif>&nbsp;</TD>
          <TD colSpan=6>&nbsp;</TD>
          <TD width=15 background=image/UI_05.gif>&nbsp;</TD></TR></TBODY></TABLE></TD>

    <TD vAlign=top width=176 bgColor=#6666cc>
      <TABLE cellSpacing=0 cellPadding=0 width=176 border=0>
        <TBODY>
        <TR>
          <TD width=11 bgColor=#6666cc height=25>&nbsp;</TD>
          <TD width=156 bgColor=#6666cc height=25><font color="#FFFFFF"><span ><br>
<script>Capture(hstatrouter2.right1)</script><br><br>
<script>Capture(hstatrouter2.right2)</script><br><br>
<script>Capture(hstatrouter2.right3)</script><br><br>
<script>Capture(hstatrouter2.right4)</script><br>
<b><a target="_blank" href="help/HStatus.asp"><script>Capture(share.more)</script></a></b></span><br><br>
<script>Capture(hstatrouter2.right5)</script><br>
<b><a target="_blank" href="help/HStatus.asp"><script>Capture(share.more)</script></a></b></span></font></TD>
          <TD width=9 bgColor=#6666cc
  height=25>&nbsp;</TD></TR></TBODY></TABLE></TD></TR>
  <TR>
    <TD width=809 colSpan=2>
      <TABLE cellSpacing=0 cellPadding=0 border=0>
        <TBODY>
        <TR>
          <TD width=156 bgColor=#e7e7e7 height=30>&nbsp;</TD>
          <TD width=8 background=image/UI_04.gif>&nbsp;</TD>
          <TD width=454>&nbsp;</TD>
          <TD width=15 background=image/UI_05.gif>&nbsp;</TD>
          <TD width=176 bgColor=#6666cc rowSpan=2>
          <IMG src="image/UI_Cisco.gif" border=0 width="176" height="64"></TD></TR>
        <TR>
          <TD width=156 bgColor=#000000>&nbsp;</TD>
          <TD width=8 bgColor=#000000>&nbsp;</TD>
          <TD width=454 bgColor=#6666cc align="right">

<!-- INPUT onclick="window.location.replace('Status_Router.asp')" type=button name="refresh_button" -->
<script>document.write("<INPUT onclick=window.location.replace('Status_Router.asp') type=button name=refresh_button value=\"" + sbutton.refresh + "\">");</script>&nbsp;&nbsp;

          </TD>
          <TD width=15 bgColor=#000000 height=33>&nbsp;</TD>
</TR></TBODY></TABLE></TD></TR></TBODY></TABLE></FORM></DIV></BODY></HTML>
EOF

    $debug = 1;

    my $re = '(?mi)Capture.*ipaddr.*[\r\n]+.+?font.+?<B>([\d.]+)'; # default test

    print "$id: REGEXP 1 [$re]\n";
    StringRegexpMatch $str, $re;

}

sub TestDriver ()
{
    my $id = "$LIB.TestDriver";
    print "$id: BEGIN\n\tAny messages you will now see are not important.\n";

    $debug = 10;
    $verb  = $debug;

    LOCAL_TEST:
    {
        local $PATH = "/usr/local/bin:/bin";
        local $WIN32 = 0;

        my @paths = split $WIN32 ? ";" : ":" , $PATH;
        my @missing = StringMatch \@paths, [ "/usr/bin" ];
        CmdError $id, $id ;
    }

    my (@response, $ip);
    my $linuxDefaultRegexp = '(?sm)inet[ \t]+addr:[ \t]*(\d[\d.]+)';
    my $regexp;

    @response = split /\r?\n/, '
eth0      Link encap:Ethernet  HWaddr 00:10:5A:64:8D:32
            inet addr:12.246.164.15  Bcast:255.255.255.255  Mask:255.255.255.0
            UP BROADCAST RUNNING  MTU:1500  Metric:1
            RX packets:38180 errors:0 dropped:0 overruns:0 frame:0
            TX packets:12211 errors:0 dropped:0 overruns:0 carrier:1
            collisions:46 txqueuelen:100
            Interrupt:11 Base address:0xec00';


    $ip = IpAddressGenericParser  $linuxDefaultRegexp, @response;

    @response = split /\r?\n/, '
tun0: flagsÄ51<UP,POINTOPOINT,RUNNING,MULTICAST> mtu 1492
        inet6 fe80::250:4ff:feef:7998%tun0 prefixlen 64 scopeid 0x7
        inet 62.214.32.46 --> 62.214.32.1 netmask 0xff000000
        Opened by PID 65';

    {
        my $modifier  = '(?sm)';
        my $inet      = 'inet[ \t]+';
        my $base      = '[ \t]*(\d[\d.]+)';

        my @regexpList;
        push @regexpList, $modifier . $inet . "addr:" . $base;
        push @regexpList, $modifier . $inet . $base;

        for my $regexp ( @regexpList )
        {
            $ip = IpAddressGenericParser $regexp, join '', @response;
            last if  $ip;
        }
    }

    @response =  split /\r?\n/, '
tun0: flagsÄ51<UP,POINTOPOINT,RUNNING,MULTICAST> mtu 1492
        inet6 fe80::250:4ff:feef:7998%tun0 prefixlen 64 scopeid 0x7
        inet 62.214.33.49 --> 255.255.255.255 netmask 0xffffffff
        inet 62.214.32.12 --> 255.255.255.255 netmask 0xffffffff
        inet 62.214.35.49 --> 255.255.255.255 netmask 0xffffffff
        inet 62.214.33.163 --> 62.214.32.1 netmask 0xff000000
        Opened by PID 64';


    {
        my $OPT_REGEXP = ".*0xffffffff.*?inet";

        my $modifier  = '(?sm)';
        my $inet      = 'inet[ \t]+';
        my $base      = '[ \t]*(\d[\d.]+)';

        my $try = $modifier . $OPT_REGEXP . $base;

        $ip = IpAddressGenericParser $try, @response;
    }

    @response =  split /\r?\n/, '
Connection-specific DNS Suffix  . :
IP Address. . . . . . . . . . . . : 212.246.177.28
Subnet Mask . . . . . . . . . . . : 255.255.255.255
Default Gateway . . . . . . . . . : 212.246.177.28';

    $ip = IpAddressGenericParser 'IP\s+Address.*[ \t](\d[\d.]+)', @response;

    #   German Windows response

    @response =  split /\r?\n/, '
Windows 2000-IP-Konfiguration Ethernetadapter "Realtek":
Verbindungsspezifisches DNS-Suffix:
IP-Adresse. . . . . . . . . . . . : 192.168.0.1
Subnetzmaske. . . . . . . . . . . : 255.255.255.0
Standardgateway . . . . . . . . . :
PPP-Adapter "T-DSL":
Verbindungsspezifisches DNS-Suffix:
IP-Adresse. . . . . . . . . . . . : 80.136.27.233
Subnetzmaske. . . . . . . . . . . : 255.255.255.255
Standardgateway . . . . . . . . . : 80.136.27.233';

    $ip = IpAddressGenericParser '(?sm)PPP.*IP-Adresse[^\r\n:]+:[ \t]*(\d[\d.]+)'
        , @response;


    @response =  split /\r?\n/, '

Windows 2000 IP Configuration

Ethernet adapter {3C317757-AEE8-4DA7-9B68-C67B4D344103}:

        Connection-specific DNS Suffix  . :
        Autoconfiguration IP Address. . . : 169.254.241.150
        Subnet Mask . . . . . . . . . . . : 255.255.0.0
        Default Gateway . . . . . . . . . :

Ethernet adapter Local Area Connection 3:

        Connection-specific DNS Suffix  . : internalgroove.net
        IP Address. . . . . . . . . . . . : 10.10.221.45
        Subnet Mask . . . . . . . . . . . : 255.255.0.0
        Default Gateway . . . . . . . . . : 10.10.0.101';

    $ip = IpAddressGenericParser 'IP\s+Address.*[ \t](\d[\d.]+)', @response;

    {
        my $OPT_REGEXP = 'Connection 3:';

        print "\n\n$id: Second IP address [$OPT_REGEXP]\n";

        my $modifier  = '(?sm)';
        my $base      = 'IP\s+Address[^\r\n:]+:[ \t]*(\d[\d.]+)';
        my $re        = $modifier . $OPT_REGEXP . ".*" . $base;

        $ip = IpAddressGenericParser $re, @response;
    }

    print "$id: END\n";
    die;
}

sub TestDriverSyslogWin32cygwin()
{
    Initialize();
    my $id = "$LIB.TestDriverSyslogWin32cygwin";

    $debug = 1;

    print "$id:\n";
    $WIN32  = 0;
    $CYGWIN = 1;
    LogSyslog "[ERROR] $id error-priority test";
    LogSyslog "[WARN] $id warn-priority test";

}

sub TestDriverSyslogWin32native()
{
    Initialize();
    my $id = "$LIB.TestDriverSyslogWin32native";

    $debug = 1;

    print "$id:\n";
    $WIN32  = 1;
    $CYGWIN = 0;
    LogSyslog "[ERROR] $id error-priority test";

    my $path = $WIN32_SYSLOG_PATH;

    print  "$path:\n", FileRead($path), "\n";
}

sub TestDriverSyslogWin32()
{
    Initialize();
    my $id = "$LIB.TestDriverSyslogWin32";

    TestDriverSyslogWin32cygwin();
    TestDriverSyslogWin32native();
}

sub TestDriverSyslogUnix()
{
    Initialize();
    my $id = "$LIB.TestDriverSyslogUnix";

    $debug = 1;

    print "$id:\n";
    $WIN32  = 0;
    $CYGWIN = 0;
    LogSyslog "[ERROR] $id error-priority test";
}

sub TestDriverSyslog()
{
    Initialize();
    my $id = "$LIB.TestDriverSyslog";

    if ( $WIN32 )
    {
        TestDriverSyslogWin32();
    }
    else
    {
        TestDriverSyslogUnix();
    }
}

# }}}
# {{{ Main

# ****************************************************************************
#
#   DESCRIPTION
#
#       Set common http headers
#
#   INPUT PARAMETERS
#
#       $req        reference to LWP object
#       $host
#
#   RETURN VALUES
#
#        none
#
# ****************************************************************************

sub HTTPheaderSet ( $ $ )
{
    my $id      = "$LIB.HTTPheaderSet";
    my ($req, $host)  = @ARG;

    $req->header( "Host", $host );
    $req->header( "Pragma", "no-cache");
    $req->header( "Connection", "close");
}

# ****************************************************************************
#
#   DESCRIPTION
#
#       Update new IP address.
#
#   INPUT PARAMETERS
#
#       %hash       Hash containing the needed parameters
#
#   RETURN VALUES
#
#        ( $code, $message )
#
# ****************************************************************************

sub UpdateDynDns ( % )
{
    my $id      = "$LIB.UpdateDynDns";
    my %arg     = @ARG;

    my $LOGIN    = $arg{login};
    my $PASS     = $arg{pass};
    my $CONNECT  = $arg{connect};
    my $HOST     = $arg{host}; # This is reference to a \@LIST of host names
    my $IP       = $arg{ip};
    my $WILDCARD = $arg{wildcard};
    my $MX       = $arg{mx};
    my $HOSTMX   = $arg{hostmx};
    my $SYSTEM   = $arg{system};
    my $OFFLINE  = $arg{offline};
    my $provider = $arg{provider};
    my $port     = $arg{port};
    my $proxy    = $arg{proxy};

    if ( $debug )
    {
        print "$id: INPUT ";
        print <<EOF;
$id: INPUT values are:
    LOGIN    = $arg{login}
    PASS     = $arg{pass}
    CONNECT  = $arg{connect}
    HOST     = @{ $arg{host} }
    IP       = $arg{ip}
    WILDCARD = $arg{wildcard}
    MX       = $arg{mx}
    HOSTMX   = $arg{hostmx}
    SYSTEM   = $arg{system}
    OFFLINE  = $arg{offline}
    provider = $arg{provider}
    port     = $arg{port}
    proxy    = $arg{proxy}
EOF

    }

    my $ua = new LWP::UserAgent
        or die "$id: LWP::UserAgent failed $ERRNO";

    if ( $verb )
    {
        my $msg = "[running in TEST mode; no real thing]" if $test;
        print "$id: $msg Updating IP $IP\n";
    }

    my $host = join ",", @$HOST;


    if ( $proxy )
    {
        $debug  and  print "$id: Using PROXY [$proxy]\n";
        $ua->proxy( http => $proxy );
    }

    #   This is old, do not use. Just a reminder.
    #
    # my $url2 =
    #     ""
    #     . "http://${LOGIN}:${PASS}\@${CONNECT}"
    #     . "/nic/dyndns"
    #     . "?action=edit&started=1&hostname=YES"
    #     . "&host_id=$host"
    #     . "&myip=$IP"
    #     . "&wildcard=$WILDCARD"
    #     . "&backmx=$MX"
    #     ;

    # 2001-06 Specification

    my $url =
        ""
        . "http://${LOGIN}:${PASS}\@${CONNECT}"
        . "/nic/update"
        . "?system=$SYSTEM"
        . "&hostname=$host"        # hostname=host,host,host..
        . "&myip=$IP"
        . "&wildcard=$WILDCARD"
        . "&backmx=$MX"
        . "&offline=$OFFLINE"
        ;

    $url .= "&mx=$HOSTMX" if $HOSTMX;


    if ( $provider =~ /ovh/ )
    {
        #   mx,wildcard and backmx are not supported
        #   https://www.ovh.com/manager/fr/manager.pl
        #
        #   Also uses HTTPS

        $url =
        ""
        . "https://${LOGIN}:${PASS}\@${CONNECT}"
        . "/nic/update"
        . "?system=dyndns"
        . "&hostname=$host"        # hostname=host,host,host..
        . "&myip=$IP"
        ;

    }

    my $req  = new HTTP::Request( 'GET', $url );

    $req->user_agent( "Perl client $PROGNAME/$VERSION");

    HTTPheaderSet $req, $CONNECT;

    $req->authorization_basic( $LOGIN, $PASS );

    if ( $test  or  $debug )
    {
        print $req->as_string;
    }

    my ($status, $code, $str);

    if ( not $test   and  IPvalidate $IP)
    {
        my $resp   = $ua->request( $req );
        my $return = $resp->as_string;

        ( $code, $str ) = StatusCodeParseDynDns( $return );

        if ( $return =~ /^\d\d\d / )
        {

            #  Web server errors # 500 (Internal Server Error) Can't
            #  connect to members.dyndns.org:80 (Timeout)

            $verb and
                  print "$id: Net or web server error."
                  . " Testing with ping $CONNECT.\n";

            unless ( Ping $CONNECT )
            {
                Log "$id: [ERROR] Ping failed."
                    . " Check your network connections.\n";
            }
            else
            {
                Log "$id: [PANIC] Hm, ping was good."
                    . " Maybe HTTP upate protocol "
                    . "string has changed.\n"
            }
        }

        if ( $verb )
        {
            print "$return\n$str\n";
        }

        $status = StatusCodeHandle $code, $str, -dyndns;
    }

    $debug  and  print "$id: RETURN [$status]\n";

    $status, $str;
}

# ****************************************************************************
#
#   DESCRIPTION
#
#       Update new IP address.
#
#   INPUT PARAMETERS
#
#       %hash       Hash containing the needed parameters
#
#   RETURN VALUES
#
#        $stat      If false, IP should not be recorded as successful
#                   update.
#
# ****************************************************************************

sub UpdateNoip ( % )
{
    my $id      = "$LIB.UpdateNoip";
    my %arg     = @ARG;

    my $LOGIN    = $arg{login};
    my $PASS     = $arg{pass};
    my $CONNECT  = $arg{connect};
    my $HOST     = $arg{host}; # This is reference to a \@LIST of host names
    my $IP       = $arg{ip};
    my $WILDCARD = $arg{wildcard};
    my $MX       = $arg{mx};
    my $HOSTMX   = $arg{hostmx};
    my $SYSTEM   = $arg{system};
    my $OFFLINE  = $arg{offline};
    my $GROUP    = $arg{group};
    my $proxy    = $arg{proxy};

    if ( $debug )
    {
        print "$id: INPUT ";
        print <<EOF;
$id: INPUT values are:
    LOGIN    = $arg{login}
    PASS     = $arg{pass}
    CONNECT  = $arg{connect}
    HOST     = @{ $arg{host} }
    IP       = $arg{ip}
    WILDCARD = $arg{wildcard}
    MX       = $arg{mx}
    HOSTMX   = $arg{hostmx}
    SYSTEM   = $arg{system}
    OFFLINE  = $arg{offline}
    provider = $arg{provider}
    port     = $arg{port}
    proxy    = $arg{proxy}
EOF

    }

    my $ua = new LWP::UserAgent
        or die "$id: LWP::UserAgent failed $ERRNO";

    $verb  and  print "$id: Updating IP $IP\n";

    my $host = join ",", @$HOST;

    if ( $proxy )
    {
        $debug  and  print "$id: Using PROXY [$proxy]\n";
        $ua->proxy( http => $proxy );
    }

    #   Use the IP 0.0.0.0 to make your host inaccessible to
    #   other users on the internet. This is useful if you will be
    #   going offline for an extended period of time. If someone else
    #   gets your old IP your users will not go to your old IP
    #   address.

    if ( $OFFLINE eq "YES" )
    {
        $verb  and  print "$id: offline request, setting IP to 0.0.0.0";
        $IP = "0.0.0.0";
    }

    # todo: 2005-02-15. There seems to be another update script
    # at http://dynupdate.no-ip.com/ducupdate.php but that is used by the
    # official no-ip.com scipt. See Downoads => Linux

    my $url =
        ""
        . "http://${CONNECT}/"
        . "update.php"
        . "?username=${LOGIN}&pass=${PASS}&host=${host}"
        . "&ip=$IP"
        ;

    $url .= "&groupname=$GROUP"     if $GROUP;
    $url .= "&mx=$HOSTMX"           if $HOSTMX;

    my $req  = new HTTP::Request( 'GET', $url );

    $req->user_agent( "Perl client $PROGNAME/$VERSION");

    HTTPheaderSet $req, $CONNECT;

    #   no-ip does not use authorization.
    #
    #    $req->authorization_basic( $LOGIN, $PASS );

    if ( $test  or  $debug )
    {
        print $req->as_string;
    }

    my ($status, $code, $str);

    if ( not $test   and  IPvalidate $IP)
    {
        my $resp   = $ua->request( $req );
        my $return = $resp->as_string;

        ( $code, $str ) = StatusCodeParseNoip( $return );

        if ( $verb )
        {
            print $return;
            print "\n$str\n";
        }

        $status = StatusCodeHandle $code, $str, -noip;
    }

    $debug  and  print "$id: done.\n";

    $status, $str;
}

# ****************************************************************************
#
#   DESCRIPTION
#
#       Update new IP address.
#
#   INPUT PARAMETERS
#
#       %hash       Hash containing the needed parameters
#
#   RETURN VALUES
#
#        $stat      If false, IP should not be recorded as successful
#                   update.
#
# ****************************************************************************

sub UpdateHNorg ( % )
{
    my $id      = "$LIB.UpdateHNorg";
    my %arg     = @ARG;

    my $LOGIN    = $arg{login};
    my $PASS     = $arg{pass};
    my $CONNECT  = $arg{connect};
    my $HOST     = $arg{host}; # This is reference to a \@LIST of host names
    my $IP       = $arg{ip};
    my $WILDCARD = $arg{wildcard};
    my $MX       = $arg{mx};
    my $HOSTMX   = $arg{hostmx};
    my $SYSTEM   = $arg{system};
    my $OFFLINE  = $arg{offline};
    my $GROUP    = $arg{group};
    my $proxy    = $arg{proxy};

    if ( $debug )
    {
        print "$id: INPUT ";
        print <<"EOF";
$id: INPUT values are:
    LOGIN    = $arg{login}
    PASS     = $arg{pass}
    CONNECT  = $arg{connect}
    HOST     = @{ $arg{host} }
    IP       = $arg{ip}
    WILDCARD = $arg{wildcard}
    MX       = $arg{mx}
    HOSTMX   = $arg{hostmx}
    SYSTEM   = $arg{system}
    OFFLINE  = $arg{offline}
    provider = $arg{provider}
    port     = $arg{port}
    proxy    = $arg{proxy}
EOF

    }

    my $ua = new LWP::UserAgent
        or die "$id: LWP::UserAgent failed $ERRNO";

    $verb  and  print "$id: Updating IP $IP\n";

    my $host = join ",", @$HOST;

    if ( $proxy )
    {
        $debug  and  print "$id: Using PROXY [$proxy]\n";
        $ua->proxy( http => $proxy );
    }

    #   Use the IP 0.0.0.0 to make your host inaccessible to
    #   other users on the internet. This is useful if you will be
    #   going offline for an extended period of time. If someone else
    #   gets your old IP your users will not go to your old IP
    #   address.

    if ( $OFFLINE eq "YES" )
    {
        $verb  and  print "$id: offline request, setting IP to 0.0.0.0";
        $IP = "0.0.0.0";
    }

    my $url =
        ""
        . "http://${CONNECT}/"
        . "vanity/update/?VER=1"
        . "&IP=$IP"
        ;

    $url .= "&mx=$HOSTMX"           if $HOSTMX;

    my $req  = new HTTP::Request( 'GET', $url );

    $req->user_agent( "Perl client $PROGNAME/$VERSION");

    HTTPheaderSet $req, $CONNECT;

    $req->authorization_basic( $LOGIN, $PASS );

    if ( $test  or  $debug )
    {
        print $req->as_string;
    }

    my ($status, $code, $str);

    if ( not $test   and  IPvalidate $IP)
    {
        my $resp   = $ua->request( $req );
        my $return = $resp->as_string;

        ( $code, $str ) = StatusCodeParseHNorg( $return );

        if ( $verb )
        {
            print $return;
            print "\n$str\n";
        }

        $status = StatusCodeHandle $code, $str, -hnorg;
    }

    $debug  and  print "$id: done.\n";

    $status, $str;
}

# ****************************************************************************
#
#   DESCRIPTION
#
#       Write IP address to a file. does nothing if program is running
#       in test or query mode.
#
#   INPUT PARAMETERS
#
#       $file
#       $ip
#
#   RETURN VALUES
#
#       true        If  Written.
#
# ****************************************************************************

sub RunUpdateIPWrite ( $$ )
{
    my $id          = "$LIB.RunUpdateIPWrite";
    my ($file, $ip) = @ARG;

    $debug  and  print "$id: INPUT file [$file] ip [$ip]\n";

    #   If Running in DEBUG mode, do it.
    #   If running in test mode OR Query, don't do it

    my $stat;

    if ( (not $test and not $OPT_QUERY) or $debug )
    {
        if ( IPvalidate $ip )
        {
            $stat = FileWrite $file, undef, $ip;
            $debug  and  print "$id: saved last used IP Address\n";
        }
        else
        {
            Log "Invalid IP address $ip";
        }
    }

    $stat;
}

# ****************************************************************************
#
#   DESCRIPTION
#
#       Set up parameters and call Update
#
#   INPUT PARAMETERS
#
#       $       IP address
#
#   RETURN VALUES
#
#       $stat   If false, the IP couldn't be updated and the IP should
#               not be recorded to a saved file. E.g if user tried to
#               update a wrong domain name, or wrong password,
#               then he can try again.
#       $msg    Message string for the STAT.
#
# ****************************************************************************

sub RunUpdate ( $ )
{
    my $id      = "$LIB.RunUpdate";
    my ($ip)    = @ARG;

    $debug  and  print "$id: INPUT ip [$ip]\n";

    local $ARG  = $OPT_PROVIDER;

    my $status = 0;
    my $msg    = '';

    if ( /dyndns|ovh/ )
    {
        my $port    = 80;
        $port       = 443 if /ovh/;  # https

        my $connect = "members.dyndns.org";
        $connect    = "www.ovh.com"  if /ovh/;

        ($status, $msg) = UpdateDynDns
              connect   => $connect
            , ip        => $ip
            , system    => $OPT_SYSTEM
            , login     => $OPT_LOGIN
            , pass      => $OPT_PASS
            , host      => \@OPT_HOST
            , wildcard  => $OPT_WILDCARD
            , mx        => $OPT_MX
            , hostmx    => $OPT_HOSTMX
            , offline   => $OPT_OFFLINE
            , provider  => $OPT_PROVIDER
            , port      => $port
            , proxy     => $OPT_PROXY
            ;
    }
    elsif ( /noip/ )
    {
        #   no-ip does not support updating all of the features
        #   from a client. E.g. You have to go to the Web page to
        #   manage the wild card option.
        #
        #   So, some of the sent parameters are not yet used.

        ($status, $msg) = UpdateNoip
              connect   => "dynupdate.no-ip.com"
            , ip        => $ip
            , system    => $OPT_SYSTEM
            , login     => $OPT_LOGIN
            , pass      => $OPT_PASS
            , host      => \@OPT_HOST
            , wildcard  => $OPT_WILDCARD    # Not supported, but send anyway
            , mx        => $OPT_MX          # Not supported, but send anyway
            , hostmx    => $OPT_HOSTMX      # Not supported, but send anyway
            , offline   => $OPT_OFFLINE
            , group     => $OPT_GROUP
            , proxy     => $OPT_PROXY
            ;
    }
    elsif ( /hnorg/ )
    {
        #   no-ip does not support updating all of the features
        #   from a client. E.g. You have to go to the Web page to
        #   manage the wild card option.
        #
        #   So, some of the sent parameters are not yet used.

        ($status, $msg) = UpdateHNorg
              connect   => "dup.hn.org"
            , ip        => $ip
            , system    => $OPT_SYSTEM
            , login     => $OPT_LOGIN
            , pass      => $OPT_PASS
            , host      => \@OPT_HOST
            , wildcard  => $OPT_WILDCARD    # Not supported, but send anyway
            , mx        => $OPT_MX          # Not supported, but send anyway
            , hostmx    => $OPT_HOSTMX      # Not supported, but send anyway
            , offline   => $OPT_OFFLINE
            , group     => $OPT_GROUP
            , proxy     => $OPT_PROXY
            ;
    }
    else
    {
        die "$id: Unknown OPT_PROVIDER [$OPT_PROVIDER]";
    }

    $status, $msg;
}

# ****************************************************************************
#
#   DESCRIPTION
#
#       Run checks before making update.
#       - It is safe to update ip, even if same, at least every 30 days
#       - If IP has changed, update immediately.
#
#   INPUT PARAMETERS
#
#       %hash       Parameters
#
#   RETURN VALUES
#
#       true        if updated
#       $code       Status code from the remote site
#                   only if update failed and it can be tried again.
#       $msg        Status string (if update run)
#
# ****************************************************************************

sub ProcessUpdateOne ( % )
{
    my $id      = "$LIB.ProcessUpdateOne";
    my %arg     = @ARG;

    my $file    = $arg{-file};
    my $ip      = $arg{-ip};
    my $lastIP  = $arg{-lastip};

    $debug  and  print "$id: INPUT file [$file] ip [$ip] last [$lastIP]\n";

    my $valid   = IPvalidate $ip;
    $valid = 1  if $test and $debug;       # Treat it as "okay"

    #  For dyndns.org, the Ip must be updated every 30 days
    #  in order to keep the account active

    my ($oldFile, $days) = IsFileOld $file;
    my $new              = "$ip $lastIP" !~ /nochange/;

    if ( $OPT_FORCE )
    {
        $debug  and  print "$id: --Force is active\n";

        unless ( $oldFile  or   $new )
        {
            print "$id: [WARN] Using --Force while IP has not changed.\n";
        }

        $new = -forced;
    }

    $new = -test  if $test;         # "test" should run all phases

    $debug  and  print "$id: IP [$ip] valid [$valid] last IP [$lastIP]\n";

    my ($stat, $msg, $update);

    if ( $valid )
    {
        if ( $oldFile  or   $new )
        {
            ($stat, $msg) = RunUpdate $ip;

            if ( $stat )
            {
                my $msg = "$id: [EXIT] Hm, update failed but according to "
                    . "error [$stat] it should be okay to try again. "
                    . "Error epxplanation is [$msg]. "
                    . "To be on the safe side, check parameters and "
                    . "wait 30 minutes before trying again. "
                    . "If in doubt, run next call with --debug 1 "
                    ;
                Log $msg;
                die $msg;
            }
            else
            {
                if ( $OPT_DAEMON )
                {
                    Log "[OK] updated IP $ip and saved it to $file\n";
                }

                #   Succeeded ok, so record this ip
                $update = RunUpdateIPWrite $file, $ip;
            }
        }
    }

    if ( not $new   and  not $oldFile )
    {
        #   - If same ip is updated too fast, warn user.
        #   - In 2002 the expiration of an account took 35 days at
        #     www.dyndns.org.

        if ($days < 1)
        {
            my $msg = "$id: [WARN] It is not allowed to update same IP "
                . "address twice [$ip]. "
                . "Trying to do so in a short period of time (< 15 min) "
                . "might possibly cause the provider to block the domain "
                . "for further attemps. "
                . "In case you know what your're doing and want to force update, "
                . "delete file $file and run program again\n"
                ;
            if ( $OPT_DAEMON )
            {
                #todo: Hm.
            }
            else
            {
                Log $msg;
            }
        }
    }

    $update, $stat, $msg
}

# ****************************************************************************
#
#   DESCRIPTION
#
#       Process passed query options and print output to screen.
#
#   INPUT PARAMETERS
#
#       None.
#
#   RETURN VALUES
#
#       true        If program should quit
#
# ****************************************************************************

sub ProcessQueryRequests (%)
{
    my $id      = "$LIB.ProcessQueryRequests";

    $debug  and  print  "$id: START\n";

    # .............................................. local functions ...

    my $file;

    sub InfoFile();
    local *InfoFile = sub
    {
        my $id = "$id.InfoFile";

        my $msg = "$id: [ERROR] option --ethernet missing";

        die $msg unless $OPT_ETHERNET;

        die "$id: [ERROR] option --Provider missing"
            unless $OPT_PROVIDER;

        unless ( $file )
        {
            $debug  and  print "$id:\n";

            $file = IPfileNameGlobbed();
            $file = IPfileNamePath  $file, -absolute, \@OPT_HOST;

            $debug  and  print "$id: $file\n";
        }
    };

    my ($ip, $lastIP);

    sub Info();
    local *InfoIP = sub
    {
        my $id = "$id.InfoIP";

        unless ( $ip and $lastIP )
        {
            $debug  and  print "$id:\n";

            InfoFile()  unless $file;

            ($ip, $lastIP)  = GetIpAddressInfo
                                 -file  => $file
                                 , -query => $OPT_QUERY
                                 ;

            $debug  and  print "$id: $ip, $lastIP\n";
        }
    };

    # ...................................................... queries ...

    my $stat;

    if ( defined $OPT_QUERY_IP_FILE )
    {
        $debug  and  print "$id: Processing OPT_QUERY_IP_FILE\n";

        InfoFile();

        $debug  and  print "$id: Processing OPT_QUERY_IP_FILE\n";

        print "$file\n";
        $stat = -queryfile;
    }

    if ( defined $OPT_QUERY_IP_SAVED )
    {
        $debug  and  print "$id: Processing OPT_QUERY_IP_SAVED\n";

        InfoFile();

        $lastIP = GetIpAddressLast( $file );

        $debug  and  print "$id: Processing OPT_QUERY_IP_SAVED\n";

        print "$lastIP\n";
        $stat = -querysaved;
    }

    if ( $OPT_QUERY )
    {
        # $ip = GetIpAddress() unless $ip;

        $debug  and  print "$id: Processing OPT_QUERY\n";

        InfoIP();

        $debug  and  print "$id: Processing OPT_QUERY\n";

        print "$ip $lastIP\n";
        $stat = -queryip;
    }

    if ( $OPT_QUERY_IP_CHANGED !~ /^-/ )    # '-undef' would mean "not used"
    {
        $debug  and  print "$id: Processing OPT_QUERY_IP_CHANGED\n";

        InfoIP();

        warn  "$id: [WARN] --file* or --Config option is missing" unless $file;

        unless ( IPvalidate $ip )
        {
            die "$id: Cannot determine query. Current IP [$ip] "
                , "is not valid for Internet. "
                , "Do you need to add --urlping* option for router?"
                ;
        }

        my %code =
        (
            changed => [ 0, "changed"  ]
            , same  => [ 1, "nochange" ]
        );

        my @ret = @{ $code{changed} };  # set default value to "changed"

        InfoFile();         # We need to know if file is OLD
        my ($oldFile, $days) = IsFileOld $file;

        if ( ( $ip eq $lastIP  or  $lastIP =~ /^[a-z]/ )     # 'nochange'
              and  not $oldFile
           )
        {
            @ret = @{ $code{same} };
        }

        #   It depends how user wants our notifications of the change.
        #   If he requested that shell exit status shuld be set, then
        #   do explicit exit(). Other than that, print a message.

        my $exit = 1        if $OPT_QUERY_IP_CHANGED =~ /exit/i;

        my $ret  = $ret[1];
        $ret     = $ret[0]  if $exit;

        $debug  and  print "$id: Processing OPT_QUERY_IP_CHANGED\n"
                        ,  "$id: ipchange check; return [$ret] => [@ret]\n"
                        ,  "$id: days old [$days]\n"
                        ;

        exit $ret  if  $exit;

        my $ipmaybe = ($ret =~ /^change/i) ? " $ip" : "";

        printf "$ret %d%s\n", int $days, $ipmaybe;

        $stat = -querysameip
    }

    $debug  and  print "$id: return [$stat]\n";

    $stat;
}

# ****************************************************************************
#
#   DESCRIPTION
#
#       Start update process.
#
#   INPUT PARAMETERS
#
#       $file           [optional] Configuraton file being processed.
#
#   RETURN VALUES
#
#       None
#
# ****************************************************************************

sub ProcessUpdateStart (; $)
{
    my $id      = "$LIB.ProcessUpdateStart";
    my ($conf)  = @ARG;

    $debug  and  print "$id: CONF [$conf]\n";

    my $file = IPfileNameGlobbed();
    $file    = IPfileNamePath  $file, -absolute, \@OPT_HOST;

    $debug  and  print "$id: Continuing update with file [$file] ...\n";

    #   The result of this call is two words: 81.197.0.2 nochange
    #   The "nochange" is included if ip has not changed.

    my ($ip, $lastIP)  = GetIpAddressInfo
                         -file    => $file
                         , -query => $OPT_QUERY
                         ;

    $debug  and  print "$id: OPT_PROVIDER $OPT_PROVIDER, file [$file]\n";

    my $ok = VariableCheckMinimum $conf;

    if ( $ok )
    {
        FileWriteCheckIP $file;

        ProcessUpdateOne
                -file       => $file
                , -ip       => $ip
                , -lastip   => $lastIP
                ;
    }
    else
    {
        Log "FATAL: Too few options set. "
          . "Use --debug to see what is missing\n";
    }
};

# ****************************************************************************
#
#   DESCRIPTION
#
#       Read settings from each configuration file (if supplied)
#       and Process an update request.
#
#   INPUT PARAMETERS
#
#       %hash       Parameters
#
#   RETURN VALUES
#
#       $quit       If true, program should quit.
#
# ****************************************************************************

sub ProcessUpdateMain ( % )
{
    my $id      = "$LIB.ProcessUpdateMain";
    my %arg     = @ARG;

    my $configArrRef = $arg{-config};

    $debug  and  print "$id: START\n";

    my $stat;

    sub ProcessIt(; $);
    local *ProcessIt = sub
    {
        my $id     = "$id.ProcessIt";
        my ($conf) = @ARG;

        $debug  and  print "$id: Reading conf [$conf]\n";

        $stat = ProcessQueryRequests();

        unless ( $stat )
        {
            ProcessUpdateStart $conf;
        }
    };

    if ( defined $configArrRef  and  @$configArrRef  )
    {
        for my $file ( @$configArrRef )
        {
            $debug  and  print "$id: processing config [$file]\n";
            ConfigFileRead $file  or  next ;

            $debug  and  print "$id: processing config [$file]\n";
            VariableCheckValidity $file;

            ProcessIt($file);
        }
    }
    else
    {
        $debug  and  print "$id: No config file. Using Cmd line options\n";
        ProcessIt();
   }

    $stat;
}

# ****************************************************************************
#
#   DESCRIPTION
#
#       Main entry point. If option --daemon is set, this function
#       never ends.
#
#   INPUT PARAMETERS
#
#       none
#
#   RETURN VALUES
#
#       none
#
# ****************************************************************************

sub Main ()
{
    Initialize();
    InitializeModules();
    HandleCommandLineArgsMain();
    VariableCheckValidity();

    my $id = "$LIB.main";

    $debug  and  print "$id: " . Version() . "\n";

    if ( exists $ENV{DYNDNS_PL_CFG} )
    {
        #   Older versions of this program used a single file to
        #   store the IP address. The variable is no longer read.

        warn "$PROGRAM_NAME: [UPGRADE NOTE] Non-supported environment "
            , "variable DYNDNS_PL_CFG found. Please migrate to the "
            , "new system. See --Config and section 'CONFIGURATION FILE' "
            , "from the manual page";
    }

    my @configFiles = @OPT_CONFIG_FILE;
    @configFiles    = FileGlob @configFiles  if @configFiles;

    $debug  and  print "$id: Config files [@configFiles]\n";

    while ( 1 )
    {
        my $stat = ProcessUpdateMain -config => \@configFiles;

        $debug  and  print "$id: loop daemon [$OPT_DAEMON] stat [$stat]\n";

        exit 0 if $stat;

        if ( $OPT_DAEMON )
        {
            $debug and
                print "$id: [daemon mode] sleeping $OPT_DAEMON minutes.\n";

            if ( $OPT_DAEMON < $DAEMON_MIN )
            {
                #   Prevent from errors. The update must not be less.
                $OPT_DAEMON = $DAEMON_MIN;
            }

            sleep 60 * $OPT_DAEMON;
            next;
        }

        $debug  and  print "$id: loop normal EXIT\n";

        exit 0;
    }
}

# }}}

# TestDriverLinksysBEFW11S4; die;
# TestDriverLinksysBEFW11S4v4; die;
# TestDriverLinksysWRT54GL; die;
# TestDriverSyslog; die;
# TestDriverHNorg(); die;

Main();

0;                  # Perl scripts (.pl) must return 0, Libraries (.pm) 1

__END__
