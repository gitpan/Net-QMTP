package Net::QMTP;

require 5.001;
use strict;

use IO::Socket;
use Carp;

#
# Copyright (c) 2003 James Raftery <james@now.ie>. All rights reserved.
# This program is free software; you can redistribute it and/or
# modify it under the same terms as Perl itself.
# Please submit bug reports, patches and comments to the author.
# Latest information at http://romana.now.ie/#net-qmtp
#
# $Id: QMTP.pm,v 1.8 2003/01/28 19:11:44 james Exp $
#
# This module is an object interface to the Quick Mail Transfer Protocol
# (QMTP). QMTP is a replacement for the Simple Mail Transfer Protocol
# (SMTP). It offers increased speed, especially over high latency
# links, pipelining, 8-bit data transmission and predeclaration of
# line-ending encoding.
#
# See the Net::QMTP man page that was installed with this module for
# information on how to use the module.
#

use vars qw($VERSION);
$VERSION = "0.02";

sub new {
	my $proto = shift or croak;
	my $class = ref($proto) || $proto;
	my $host = shift or croak "No host specified in constructor";
	my %args;

	%args = @_ if @_;
	my $self = {
		SENDER		=> undef,
		RECIPIENTS	=> [],
		MESSAGE		=> undef,
		MSGFILE		=> undef,
		ENCODING	=> undef,
		SOCKET		=> undef,
		HOST		=> undef,
		DEBUG		=> undef,
	};
	$self->{DEBUG} = 1 if $args{'Debug'};
	$self->{HOST} = $host or croak "Constructor host() failed";
	bless($self, $class);
	unless ($self->encoding("__GUESS__")) {
		carp "Constructor encoding() failed";
		return undef;
	}
	if ($args{'ManualConnect'}) {
		$self->reconnect() or return undef;
	}
	return $self;
}

sub reconnect {
	my $self = shift;
	ref($self) or croak;

	# can't reconnect if connected
	return undef if $self->{SOCKET};
	my $sock = IO::Socket::INET->new(
			PeerAddr	=> $self->{HOST},
			PeerPort	=> 'qmtp(209)',
			Proto		=> 'tcp') or return undef;
	$sock->autoflush();
	$self->{SOCKET} = $sock;
	return $self->{SOCKET};
}

sub disconnect {
	my $self = shift;
	ref($self) or croak;

	# can't disconnect if not connected
	my $sock = $self->{SOCKET} or return undef;
	unless (close $sock) {
		carp "Cannot close socket: $!";
		return undef;
	}
	$self->{SOCKET} = undef;
	return 1;
}

sub encoding {
	my $self = shift;
	ref($self) or croak;
	my $e = shift or return $self->{ENCODING};

	# guess from input record seperator
	if ($e eq "__GUESS__") {

		if ($/ eq "\015\012") {		# CRLF: Dos/Win
			$self->{ENCODING} = "\015";
		} else {			# LF: Unix-like
			$self->{ENCODING} = "\012";
		}

	# specific encoding requested
	} elsif ($e eq "dos") {
		$self->{ENCODING} = "\015";
	} elsif ($e eq "unix") {
		$self->{ENCODING} = "\012";
	} else {
		croak "Unknown encoding: '$e'";
	}

	return $self->{ENCODING};
}

sub host {
	my $self = shift;
	ref($self) or croak;
	$self->{HOST} = shift if @_;
	return $self->{HOST};
}

sub sender {
	my $self = shift;
	ref($self) or croak;
	$self->{SENDER} = shift if @_;
	return $self->{SENDER};
}

sub recipient {
	my $self = shift;
	ref($self) or croak;
	push(@{$self->{RECIPIENTS}}, shift) if @_;
	return $self->{RECIPIENTS};
}

sub message {
	my $self = shift;
	ref($self) or croak;
	if ($self->{MSGFILE}) {
		carp "Message already created by message_from_file()";
		return undef;
	}
	$self->{MESSAGE} .= shift if @_;
	return $self->{MESSAGE};
}

sub message_from_file {
	my $self = shift;
	ref($self) or croak;
	if ($self->{MESSAGE}) {
		carp "Message already created by message()";
		return undef;
	}
	my $f = shift or return $self->{MSGFILE};
	-s $f or return undef;
	$self->{MSGFILE} = $f;
	return $self->{MSGFILE};
}

sub new_message {
	my $self = shift;
	ref($self) or croak;

	$self->{MESSAGE} = undef;
	$self->{MSGFILE} = undef;
	return 1;
}

sub new_envelope {
	my $self = shift;
	ref($self) or croak;

	$self->{SENDER} = undef;
	$self->{RECIPIENTS} = [];
	return 1;
}

sub _send_file {
	my $self = shift;
	ref($self) or die;
	my $f = $self->{MSGFILE};
	my $sock = $self->{SOCKET};

	unless (open(FILE, $f)) {
		carp "Cannot open file '$f': $!";
		return undef;
	}
	my $size = -s $f;
	carp "File '$f' is empty" if $size == 0;
	return undef if $size < 0;

	print $sock ($size+1) . ":" . $self->{ENCODING} or return undef;
	# count len as we read?
	while (<FILE>) { print $sock or return undef };
	print $sock "," or return undef;
	unless (close FILE) {
		carp "Cannot close file '$f': $!";
		return undef;
	}
	return 1;
}

sub send {
	my $self = shift;
	ref($self) or croak;

	$self->_ready_to_send() or return undef;
	my $sock = $self->{SOCKET};

	if ($self->{MSGFILE}) {
		$self->_send_file() or return undef;
	} else {
		print $sock &_as_netstring($self->{ENCODING} .
			$self->{MESSAGE}) or return undef;
	}

	print $sock &_as_netstring($self->{SENDER}) or return undef;
	print $sock &_list_as_netstring($self->{RECIPIENTS}) or return undef;

	my($s, %r);
	foreach (@{$self->{RECIPIENTS}}) {
		$s = $self->_read_netstring();
		CASE: {
			$s =~ s/^K/success: / and last CASE;
			$s =~ s/^Z/deferral: / and last CASE;
			$s =~ s/^D/failure: / and last CASE;
		}
		$r{$_} = $s;
	}

	return \%r;
}

sub _ready_to_send {
	my $self = shift;
	ref($self) or die;

	# need defined sender (don't need true; empty string is valid),
	# recipient(s), message and socket
	return (defined($self->{SENDER}) and scalar(@{$self->{RECIPIENTS}}) and
		($self->{MESSAGE} or $self->{MSGFILE}) and
		$self->{SOCKET});
}

sub _read_netstring {
	my $self = shift;
	ref($self) or die;
	my $sock = $self->{SOCKET};
	my $s;
	read($sock, $s, $self->_getlen()) or die;
	$self->_getcomma() or die;
	return $s;
}

sub _as_netstring {
	my $s = shift || "";
	return length($s) . ":" . $s . ",";
}

sub _list_as_netstring {
	my $listref = shift || [];
	my $netstring;

	foreach (@{$listref}) {
		$netstring .= _as_netstring($_);
	}
	return _as_netstring($netstring);
}

sub _getlen {
	my $self = shift;
	ref($self) or die;
	my $sock = $self->{SOCKET};
	my $len = 0;
	my $s = "";
	for (;;) {
		defined(read($sock, $s, 1)) or die;
		return $len if $s eq ":";
		_badproto() if $s !~ /[0-9]/;
		_badresources() if $len > 200000000;
		$len = 10 * $len + $s;
	}
	return 0;
}

sub _getcomma {
	my $self = shift;
	ref($self) or die;
	my $sock = $self->{SOCKET};
	my $s = "";
	defined(read($sock, $s, 1)) or die;
	_badproto() if $s ne ",";
	return 1;
}

sub _badproto {
	confess "Protocol violation";
}

sub _badresources {
	confess "Excessive resources requested";
}

sub DESTROY {
	my $self = shift;
	ref($self) or die;
	$self->disconnect();	# don't care about failure
}

1;

__END__

=head1 NAME

Net::QMTP - Quick Mail Transfer Protocol (QMTP) client

=head1 SYNOPSIS

 use Net::QMTP;

 $qmtp = Net::QMTP->new('mail.example.org');

 $qmtp->sender('sender@example.org');
 $qmtp->recipient('foo@example.org');
 $qmtp->recipient('bar@example.org');

 $qmtp->message($bodytext);

 $qmtp->encoding('unix');
 $qmtp->message_from_file($filename);

 $qmtp->host('server.example.org');
 $qmtp->new_envelope();
 $qmtp->new_message();

 $qmtp->reconnect()
 $qmtp->send();
 $qmtp->disconnect()

=head1 DESCRIPTION

This module implements an object orientated interface to a Quick Mail
Transfer Protocol (QMTP) client which enables a perl program to send
email by QMTP.

=head2 CONSTRUCTOR

=over 4

=item new(HOST)

The C<new()> constructor creates an new Net::QMTP object and returns a
reference to it if successful, undef otherwise. C<HOST> is an FQDN or IP
address of the QMTP server to connect to and it is mandatory. The TCP
session is established when the object is created but may be brought up
and down at will by C<disconnect()> and C<reconnect()> methods.

=back

=head2 METHODS

=over 4

=item sender(ADDRESS) sender()

Return the envelope sender for this object or set it to the supplied
C<ADDRESS>. Returns undef if the sender is not yet defined. An empty
envelope sender is quite valid. If you want this, be sure to call
C<sender()> with an argument of an empty string.

=item recipient(ADDRESS) recipient()

If supplied, add C<ADDRESS> to the list of envelope recipients. If not,
return a reference to the current list of recipients. Returns a
reference to an empty list if recipients have not yet been defined.

=item host(SERVER) host()

If supplied, set C<SERVER> as the QMTP server this object will connect
to. If not, return the current server.

=item message(TEXT) message()

If supplied, append C<TEXT> to the message body. If not, return the
current message body. It is the programmer's responsibility to create a
valid message including appropriate RFC 2822/822 header lines.

This method cannot be used on a object which has had a message body
created by the C<message_from_file()> method. Use C<new_message()> to
erase the current message contents.

=item message_from_file(FILE)

Use the contents of C<FILE> as the message body. It is the programmer's
responsibility to create a valid message in C<FILE> including
appropriate RFC 2822/822 header lines.

This method cannot be used on a object which has had a message body
created by C<message()>. Use C<new_message()> to erase the current
message contents.

=item encoding(TYPE) encoding()

Set the line-ending encoding for this object to one of:

B<unix> - Unix-like line ending; lines are delimited by a line-feed
character.

B<dos> - DOS/Windows line ending; lines are delimited by a
carraige-return line-feed character pair.

The constructor will make a guess at which encoding to use based on
the value of C<$/>. Call C<encoding()> without an argument to get the
current line-encoding. It will return a line-feed for C<unix>, a
carraige-return for C<dos> or undef if the encoding couldn't be set.

Be sure the messages you create with C<message()> and
C<message_from_file()> have approproiate line-endings.

=item send()

Send the message. It returns a reference to a hash. The hash is keyed by
recipient address. The value for each key is the response from the QMTP
server, prepended with one of:

B<success:> - the message was accepted for delivery

B<deferral:> - temporary failure. The client should try again later

B<failure:> - permanent failure. The message was not accepted and should
not be tried again

See L<"EXAMPLES">.

=item new_envelope()

Reset the object's envelope information; sender and recipients. Does
not affect the message body.

=item new_message()

Reset the object's message information; message text or message file.
Does not affect the envelope.

=item disconnect()

Close the network connection to the object's server. Returns undef if
this fails. The object's destructor will call C<disconnect()> to be sure
any open socket is closed cleanly when the object is destroyed.

=item reconnect()

Reestablish a network connection to the object's server. Returns undef
if the connection could not be established.

=back

=head1 EXAMPLES

 use Net::QMTP;
 my $qmtp = Net::QMTP->new('server.example.org') or die;

 $qmtp->sender('sender@example.org');
 $qmtp->recipient('joe@example.org');
 $qmtp->message('From: sender@example.org' . "\n" .
 		'To: joe@example.org' . "\n" .
		"Subject: QMTP test\n\n" .
		"Hi Joe!\nThis message was sent over QMTP");

 my $response = $qmtp->send() or die;
 foreach (keys %{ $response }) {
	 print $_ . ": " . ${$response}{$_} . "\n";
 }
 $qmtp->disconnect();

=head1 SEE ALSO

L<qmail-qmtpd(8)>, L<maildirqmtp(1)>.

=head1 NOTES

The QMTP protocol is described in http://cr.yp.to/proto/qmtp.txt

QMTP is a replacement for SMTP and, as such, requires a QMTP server in
addition to this client. The qmail MTA includes a QMTP server;
qmail-qmtpd. Setting up the server is outside the scope of the module's
documentation. See http://www.qmail.org/ for more QMTP information.

=head1 CAVEATS

Be aware of your line endings! C<\n> means different things on different
platforms.

If, on a Unix system, you say:

 $qmtp->encoding("dos");

with the intention of later supplying a DOS formatted file, don't make
the mistake of substituting C<message_from_file> with something like:

 $qmtp->message($lineone . "\n" . $linetwo);

On Unix systems C<\n> is (only) a line-feed. You should either
explicitly change the encoding back to C<unix> or supply your text with
the proper encoding:

 $qmtp->message($lineone . "\r\n" . $linetwo);

=head1 BUGS

Also known as the TODO list:

=over 4

=item *

we have no timeouts

=item *

we have no debugging output

=item *

we need an option to constructor to set socket timeout

=item *

how do we reset client/server state if failure occurs during transmission?

=item *

we should write more tests

=back

=head1 AUTHOR

James Raftery <james@now.ie>.

=cut
