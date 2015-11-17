#!/usr/bin/perl -w

##
#Template of SMTP PROXY
#For use with Postfix as SMTPD_PROXY_FILTER
#Can be used separately
#
#For use with Postfix:
# master.cf:
# 1. Comment existing smtpd string
# 2. Add next:
#
##SMTPD_PROXY_FILTER
## Proxying incoming mail to our filter:
#  smtp      inet  n       -       -       -       -       smtpd
#  -o smtpd_proxy_filter=localhost:9909
#
##Receive filtered mail from our filter:
#  127.0.0.1:9925      inet  n       -       -       -       -       smtpd
#  -o smtpd_authorized_xforward_hosts=127.0.0.0/8
#  -o smtpd_client_restrictions=
#  -o smtpd_helo_restrictions=
#  -o smtpd_sender_restrictions=
#  -o smtpd_recipient_restrictions=permit_mynetworks,reject
#  -o mynetworks=127.0.0.0/8
#  -o receive_override_options=no_unknown_recipient_checks
#  -o content_filter=
##END
#
# For more info see Postfix guide pgs. 166-169
##

use strict;
use Getopt::Long;
use IO::File;
use lib './smtpprox-1.2/';
use MSDW::SMTP::Server;
use MSDW::SMTP::Client;

my $syntax = "syntax: $0 [--children=16] [--minperchild=100] ".
             "[--maxperchild=200] [--debugtrace=undef] ".
             "listen.addr:port talk.addr:port\n";

my $children = 16;
my $minperchild = 100;
my $maxperchild = 200;
my $debugtrace = undef;
GetOptions("children=n" => \$children,
	   "minperchild=n" => \$minperchild,
	   "maxperchild=n" => \$maxperchild,
	   "debugtrace=s" => \$debugtrace) or die $syntax;

die $syntax unless @ARGV == 2;
my ($srcaddr, $srcport) = split /:/, $ARGV[0];
my ($dstaddr, $dstport) = split /:/, $ARGV[1];
die $syntax unless defined($srcport) and defined($dstport);

my $server = MSDW::SMTP::Server->new(interface => $srcaddr, port => $srcport);

# This should allow a kill on the parent to also blow away the
# children, I hope
my %children;
use vars qw($please_die);
$please_die = 0;
$SIG{TERM} = sub { $please_die = 1; };

# This block is the parent daemon, never does an accept, just herds
# a pool of children who accept and service connections, and
# occasionally kill themselves off
PARENT: while (1) {
    while (scalar(keys %children) >= $children) {
	my $child = wait;
	delete $children{$child} if exists $children{$child};
	if ($please_die) { kill 15, keys %children; exit 0; }
    }
    my $pid = fork;
    die "$0: fork failed: $!\n" unless defined $pid;
    last PARENT if $pid == 0;
    $children{$pid} = 1;
    select(undef, undef, undef, 0.1);
    if ($please_die) { kill 15, keys %children; exit 0; }
}

# This block is a child service daemon. It inherited the bound
# socket created by SMTP::Server->new, it will service a random
# number of connection requests in [minperchild..maxperchild] then
# exit

my $lives = $minperchild + (rand($maxperchild - $minperchild));
my %opts;
if (defined $debugtrace) {
	$opts{debug} = IO::File->new(">$debugtrace.$$");
	$opts{debug}->autoflush(1);
}

open FH, ">>", "./".$$."_debug";
my %data;
my $done = 0;

while (1) {
    $server->accept(%opts);
    my $client = MSDW::SMTP::Client->new(interface => $dstaddr, port => $dstport);
    my $banner = $client->hear;
    $banner = "220 $debugtrace.$$" if defined $debugtrace;
    $server->ok($banner);
    while (my $what = $server->chat) {
      print STDERR $what;

#START RECIPIENT VERIFY

      if($what =~ /^rcpt/i) {
	if ($server->{to} =~ /linuxtech77/) {
	  $server->fail(('550 no. RELAY TO USER DISABLED'));
	  $client = undef;
	  $done=1;
	  last;
	}
      }

#END RECIPIENT VERIFY

      elsif ($what eq '.') {

#START SUBJECT CHECKING

	my $th = $server->{data};
	print STDERR "Data:\n";
	while (<$th>){
	  if(!$done && $_ ne "\r\n"){
	    my ($key, $value) = split /:\s*/;
	    $key = lc $key;
	    $data{$key} = $value;
	  } else { $done = 1 }
	  print STDERR $_
	};

	print STDERR "\n"."-" x 10 ."end_data"."-" x 10 ."\n";
	print STDERR "SUBJ: $data{subject}\n";

#END SUBJECT CHECKING

	$client->yammer($server->{data});
	} else {
	    $client->say($what);
	}
	if (!$done) { $server->ok($client->hear) }
    }
    $done = 0;
    $client = undef;
    delete $server->{"s"};
    exit 0 if $lives-- <= 0;
}

close FH;
