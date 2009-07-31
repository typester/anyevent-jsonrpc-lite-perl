package AnyEvent::JSONRPC::Lite::Client;
use Any::Moose;

use AnyEvent;
use AnyEvent::Socket;
use AnyEvent::Handle;

our $VERSION = '0.01';

has host => (
    is       => 'ro',
    isa      => 'Str',
    required => 1,
);

has port => (
    is       => 'ro',
    isa      => 'Int|Str',
    required => 1,
);

has handler => (
    is  => 'rw',
    isa => 'AnyEvent::Handle',
);

has handler_options => (
    is      => 'ro',
    isa     => 'HashRef',
    default => sub { {} },
);

has _request_pool => (
    is      => 'ro',
    isa     => 'ArrayRef',
    lazy    => 1,
    default => sub { [] },
);

has _next_id => (
    is      => 'ro',
    isa     => 'CodeRef',
    lazy    => 1,
    default => sub {
        my $id = 0;
        sub { ++$id };
    },
);

has _callbacks => (
    is      => 'ro',
    isa     => 'HashRef',
    lazy    => 1,
    default => sub { {} },
);

no Any::Moose;

sub BUILD {
    my $self = shift;

    tcp_connect $self->host, $self->port, sub {
        my ($fh) = @_
            or die "Failed to connect $self->{host}:$self->{port}: $!";

        my $handle = AnyEvent::Handle->new(
            on_error => sub {
                my ($h, $fatal, $msg) = @_;
                $h->destroy;
                warn "Client got error: $msg";
            },
            %{ $self->handler_options },
            fh => $fh,
        );
        $handle->on_read(sub {
            shift->unshift_read(json => sub {
                $self->_handle_response( $_[1] );
            });
        });

        while (my $pooled = shift @{ $self->_request_pool }) {
            $handle->push_write( json => $pooled );
        }

        $self->handler( $handle );
    };
}

sub call {
    my ($self, $method, @params) = @_;

    my $request = {
        id     => $self->_next_id->(),
        method => $method,
        params => \@params,
    };

    if ($self->handler) {
        $self->handler->push_write( json => $request );
    }
    else {
        push @{ $self->_request_pool }, $request;
    }

    $self->_callbacks->{ $request->{id} } = AnyEvent->condvar;
}

sub _handle_response {
    my ($self, $res) = @_;

    my $d = delete $self->_callbacks->{ $res->{id} };
    unless ($d) {
        warn q/Invalid response from server/;
        return;
    }

    $d->send($res);
}

sub notify {
    my ($self, $method, @params) = @_;

    my $request = {
        method => $method,
        params => \@params,
    };

    if ($self->handler) {
        $self->handler->push_write( json => $request );
    }
    else {
        push @{ $self->_request_pool }, $request;
    }
}

__PACKAGE__->meta->make_immutable;

__END__

=head1 NAME

AnyEvent::JSONRPC::Lite::Client - Module abstract (<= 44 characters) goes here

=head1 SYNOPSIS

  use AnyEvent::JSONRPC::Lite;
  blah blah blah

=head1 DESCRIPTION

Stub documentation for this module was created by ExtUtils::ModuleMaker.
It looks like the author of the extension was negligent enough
to leave the stub unedited.

Blah blah blah.

=head1 AUTHOR

Daisuke Murase <typester@cpan.org>

=head1 COPYRIGHT AND LICENSE

Copyright (c) 2009 by KAYAC Inc.

This program is free software; you can redistribute
it and/or modify it under the same terms as Perl itself.

The full text of the license can be found in the
LICENSE file included with this module.

=cut


