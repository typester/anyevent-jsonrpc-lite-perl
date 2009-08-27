package AnyEvent::JSONRPC::Lite::Client;
use Any::Moose;
use Scalar::Util 'weaken';

use AnyEvent;
use AnyEvent::Socket;
use AnyEvent::Handle;

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

has _connection_guard => (
    is  => 'rw',
    isa => 'Object',
);

no Any::Moose;

sub BUILD {
    my $self = shift;

    my $guard = tcp_connect $self->host, $self->port, sub {
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
    weaken $self;

    $self->_connection_guard($guard);
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

AnyEvent::JSONRPC::Lite::Client - Simple TCP-based JSONRPC client

=head1 SYNOPSIS

    use AnyEvent::JSONRPC::Lite::Client;
    
    my $client = AnyEvent::JSONRPC::Lite::Client->new(
        host => '127.0.0.1',
        port => 4423,
    );
    
    my $cv = $client->call('echo', 'foo', 'bar');
    
    my $res    = $cv->recv;
    my $result = $res->{result}; # => ['foo', 'bar']

=head1 DESCRIPTION

This module is client part of L<AnyEvent::JSONRPC::Lite>.

=head1 METHODS

=head2 new (%options)

Create new client object and return it.

    my $client = AnyEvent::JSONRPC::Lite::Client->new(
        host => '127.0.0.1',
        port => 4423,
    );

Available options are:

=over 4

=item host (Required)

Hostname to connect.

=item port (Required)

Port number to connect.

=item handler_options (Optional)

Hashref. This is passed to constructor of L<AnyEvent::Handle> that is used manage connection.

=back

=head2 call ($method, @params)

Call remote method named C<$method> with parameters C<@params>. And return condvar object for response.

    my $cv = $client->call( echo => 'Hello!' );
    my $res = $cv->recv;

=head2 notify ($method, @params)

Same as call method, but not handle response. This method just notify to server.

    $client->call( echo => 'Hello' );

=head1 AUTHOR

Daisuke Murase <typester@cpan.org>

=head1 COPYRIGHT AND LICENSE

Copyright (c) 2009 by KAYAC Inc.

This program is free software; you can redistribute
it and/or modify it under the same terms as Perl itself.

The full text of the license can be found in the
LICENSE file included with this module.

=cut


