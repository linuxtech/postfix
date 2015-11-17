#!/usr/bin/perl
#
#Test for Postfix SMTP Access Policy Delegation
#Add to
# /etc/postfix/main.cf:
#     smtpd_recipient_restrictions =
#         ...
#         reject_unauth_destination
#         check_policy_service inet:127.0.0.1:9998
#
# and restart the postfix when this script is running...
#
# Docs: http://www.postfix.org/SMTPD_POLICY_README.html
#

package simplefilter1;

use strict;
use utf8;

binmode STDOUT, ":utf8";
use open ':std', ':encoding(UTF-8)';

use base qw(Net::Server);



my $server = bless {
		    server => {
			       #port => '/etc/postfix/transports/simple1.sock',
			       port => 9998,
			       proto => 'tcp',
			       #socketmode => '0666',
			       host => '127.0.0.1',
			       
			      }
		   };

sub process_request {
  my $self = shift;
#  open FH, ">>", "/etc/postfix/transports/simplefilter1.dat";
  while (<STDIN>){
#    print "Reply: $_";
    print STDERR "$_";
  }
  print "OK\n";
#  print FH "\n-----end transmission-------\n\n";
#  close FH;

}


  $server->run();
