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
# Latest information at http://romana.now.ie/
#
# $Id: QMTP.pm,v 1.4 2003/01/27 17:20:18 james Exp $
#
# This module is an object interface to the Quick Mail Transfer
# Protocol (QMTP). See the Net::QMTP man page that was installed with
# this module for more information.
#

use vars qw($VERSION);
$VERSION = "0.01";

sub new {
	my $proto = shift;
	my $class = ref($proto) || $proto;
	my $host = shift || or croak "No host specified in constructor";
	my $self = {
		SENDER		=> undef,
		RECIPIENTS	=> [],
		MESSAGE		=> undef,
		MSGFILE		=> undef,
		ENCODING	=> undef,
		SOCKET		=> undef,
		HOST		=> undef,
	};
	bless($self, $class);
	$self->encoding("__GUESS__") or croak "Constructor encoding() failed";
	$self->host($host) or croak "Constructor host() failed";
	return $self;
}

sub encoding {
	my $self = shift;
	ref($self) || die;
	my $e = shift || return $self->{ENCODING};

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
	ref($self) || die;
	$self->{HOST} = shift if @_;
	return $self->{HOST};
}

sub sender {
	my $self = shift;
	ref($self) || die;
	$self->{SENDER} = shift if @_;
	return $self->{SENDER};
}

sub recipient {
	my $self = shift;
	ref($self) || die;
	push(@{$self->{RECIPIENTS}}, shift) if @_;
	return $self->{RECIPIENTS};
}

sub message {
	my $self = shift;
	ref($self) || die;
	if ($self->{MSGFILE}) {
		carp "Message already created by message_from_file()";
		return undef;
	}
	$self->{MESSAGE} .= shift if @_;
	return $self->{MESSAGE};
}

sub message_from_file {
	my $self = shift;
	ref($self) || die;
	if ($self->{MESSAGE}) {
		carp "Message already created by message()";
		return undef;
	}
	my $f = shift || return $self->{MSGFILE};
	-s $f || return undef;
	$self->{MSGFILE} = $f;
	return $self->{MSGFILE};
}

sub _send_file {
	my $self = shift;
	ref($self) || die;
	my $f = $self->{MSGFILE};
	my $sock = $self->{SOCKET};

	my $size = -s $f || die;
	open(F,$f) || die;
	print $sock ($size+1) . ":" . $self->{ENCODING};
	while (<F>) { print $sock };
	print $sock ",";
	close F || die;
}

sub send {
	my $self = shift;
	ref($self) || die;

	my $sock = IO::Socket::INET->new(
			PeerAddr	=> $self->{HOST},
			PeerPort	=> 'qmtp(209)',
			Proto		=> 'tcp') or die;
	$self->{SOCKET} = $sock;
	$sock->autoflush();

	if ($self->{MSGFILE}) {
		$self->_send_file();
	} else {
		print $sock &_as_netstring($self->{ENCODING}.$self->{MESSAGE});
	}

	print $sock &_as_netstring($self->{SENDER});
	print $sock &_list_as_netstring($self->{RECIPIENTS});

	my($s, %r);

	foreach (@{$self->{RECIPIENTS}}) {
		read($sock, $s, $self->_getlen());
		$self->_getcomma();
		CASE: {
			$s =~ s/^K/success: / and last CASE;
			$s =~ s/^Z/deferral: / and last CASE;
			$s =~ s/^D/failure: / and last CASE;
		}
		$r{$_} = $s;
	}

	$self->{SOCKET} = undef;
	return \%r;
}

sub _as_netstring {
	my $s = shift || "";
	return length($s) . ":" . $s . ",";
}

sub _list_as_netstring {
	my $listref = shift;
	my $netstring;

	foreach (@{$listref}) {
		$netstring .= _as_netstring($_);
	}
	return _as_netstring($netstring);
}

sub _getlen {
	my $self = shift;
	ref($self) || die;
	my $sock = $self->{SOCKET};
	my $len = 0;
	my $s = "";
	for (;;) {
		defined(read($sock, $s, 1)) or die;
		return $len if $s eq ":";
		##if (len > 200000000) resources();
		$len = 10 * $len + $s;
	}
}

sub _getcomma {
	my $self = shift;
	ref($self) || die;
	my $sock = $self->{SOCKET};
	my $s = "";
	defined(read($sock, $s, 1)) or die;
	badproto() if ($s ne ",");
}

sub _badproto {
	die "Protocol violation\n";
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

 $qmtp->send();

=head1 DESCRIPTION

This module implements an object orientated interface to a Quick Mail
Transfer Protocol (QMTP) client which enables a perl program to send
email by QMTP.

=head2 CONSTRUCTOR

=over 4

=item Net::QMTP->new(HOST)

The new() constructor creates an new Net::QMTP object and returns a
reference to it if successful, undef otherwise. C<HOST> is an FQDN or
IP address of the QMTP server to connect to and it is mandatory.

=back

=head2 METHODS

=over 4

=item sender(ADDRESS) sender()

Return the envelope sender for this object or set it to the
supplied C<ADDRESS>. Returns undef if the sender is not yet defined.

=item recipient(ADDRESS) recipient()

If supplied, add C<ADDRESS> to the list of envelope recipients. If not,
return a reference to the current list of recipients. Returns a reference
to an empty list if recipients have not yet been defined.

=item host(SERVER) host()

If supplied, set C<SERVER> as the QMTP server this object will connect
to. If not, return the current server.

=item message(TEXT) message()

If supplied, append C<TEXT> to the message body. If not, return the
current message body. It is the programmer's responsibility to create
a valid message including appropriate RFC2822/RFC822 header lines.

This method cannot be used on a object which has had a message body
created by the C<message_from_file> method.

=item message_from_file(FILE)

Use the contents of C<FILE> as the message body. It is the programmer's
responsibility to create a valid message in C<FILE> including
appropriate RFC2822/RFC822 header lines.

This method cannot be used on a object which has had a message body
created by the C<message> method.

=item encoding(TYPE) encoding()

Set the line-ending encoding for this object to one of:

B<unix> - Unix-like line ending; lines are delimited by a line-feed
character.

B<dos> - DOS/Windows line ending; lines are delimited by a carraige-return
line-feed character pair.

The C<new> method will make a guess at which encoding to use based on the
value of C<$/>. Call C<encoding> method without an argument to get the
current line-encoding. It will return a line-feed for C<unix>, a
carraige-return for C<dos> or undef if the encoding couldn't be set.

Be sure the messages you create with C<message> and C<message_from_file>
have approproiate line-endings.

=item send()

Send the message. It returns a reference to a hash. The hash is
keyed by recipient address. The value for each key is the response
from the QMTP server, prepended with one of:

B<success:> - the message was accepted for delivery

B<deferral:> - temporary failure. The client should try again later

B<failure:> - permanent failure. The message was not accepted and should
not be tried again

=back

=head1 NOTES

The QMTP protocol is described in http://cr.yp.to/proto/qmtp.txt

QMTP is a replacement for SMTP and, as such, requires a QMTP server in
addition to this client. The qmail MTA includes a QMTP server;
qmail-qmtpd. Setting up the server is outside the scope of the module's
documentation.

=head1 CAVEATS

Be aware of your line endings! C<\n> means different things on different
platforms.

If, on a Unix system, you say:

 $qmtp->encoding("dos");
 
with the intention of later supplying a DOS formatted file, don't
make the mistake of substituting C<message_from_file> with something
like:

 $qmtp->message($lineone . "\n" . $linetwo);

On Unix systems C<\n> is (only) a line-feed. You should either explicitly
change the encoding back to C<unix> or supply your text with the proper
encoding:

 $qmtp->message($lineone . "\r\n" . $linetwo);

=head1 AUTHOR

James Raftery <james@now.ie>.

=head1 SEE ALSO

L<qmail-qmtpd(8)>, L<maildirqmtp(1)>.

=cut
