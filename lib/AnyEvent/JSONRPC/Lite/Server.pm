package AnyEvent::JSONRPC::Lite::Server;
use Any::Moose;

use AnyEvent;
use AnyEvent::Handle;
use AnyEvent::Socket;

use AnyEvent::JSONRPC::Lite::CondVar;

has address => (
    is      => 'ro',
    isa     => 'Maybe[Str]',
    default => undef,
);

has port => (
    is      => 'ro',
    isa     => 'Int|Str',
    default => 4423,
);

has handler_options => (
    is      => 'ro',
    isa     => 'HashRef',
    default => sub { {} },
);

has _handlers => (
    is      => 'ro',
    isa     => 'ArrayRef',
    default => sub { [] },
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

    tcp_server $self->address, $self->port, sub {
        my ($fh, $host, $port) = @_;
        my $indicator = "$host:$port";

        my $handle = AnyEvent::Handle->new(
            on_error => sub {
                my ($h, $fatal, $msg) = @_;
                $h->destroy;
                warn 'Server got error ', $msg;
            },
            %{ $self->handler_options },
            fh => $fh,
        );
        $handle->on_read(sub {
            shift->unshift_read( json => sub {
                $self->_dispatch($indicator, @_);
            }),
        });

        $self->_handlers->[ fileno($fh) ] = $handle;
    }, sub {
        my ($fh) = @_;
        unless ($fh) {
            warn "Failed to start JSONRPC Server: $!";
            return;
        }
    };

    $self;
}

sub reg_cb {
    my ($self, %callbacks) = @_;

    while (my ($method, $callback) = each %callbacks) {
        $self->_callbacks->{ $method } = $callback;
    }
}

sub _dispatch {
    my ($self, $indicator, $handle, $request) = @_;
    return unless $request and ref $request eq 'HASH';

    my $target = $self->_callbacks->{ $request->{method} };

    # must response if id is exists
    if (my $id = $request->{id}) {
        $indicator = "$indicator:$id";

        my $res_cb = sub {
            my $type   = shift;
            my $result = @_ > 1 ? \@_ : $_[0];

            $handle->push_write( json => {
                id     => $id,
                result => $type eq 'result' ? $result : undef,
                error  => $type eq 'error'  ? $result : undef,
            });
        };

        my $cv = AnyEvent::JSONRPC::Lite::CondVar->new;
        $cv->_cb(
            sub { $res_cb->( result => $_[0]->recv ) },
            sub { $res_cb->( error  => $_[0]->recv ) },
        );

        $target ||= sub { shift->error(qq/No such method "$request->{method}" found/) };
        $target->( $cv, @{ $request->{params} || [] } );
    }
    else {
        # without id parameter, this is notification.
        # dispatch to method without cv object.
        $target ||= sub { warn qq/No such method "$request->{method}" found/ };
        $target->(undef, @{ $request->{params} || [] });
    }
}

__PACKAGE__->meta->make_immutable;

__END__

=head1 NAME

AnyEvent::JSONRPC::Lite::Server - Simple TCP-based JSONRPC server

=head1 SYNOPSIS

    use AnyEvent::JSONRPC::Lite::Server;
    
    my $server = AnyEvent::JSONRPC::Lite::Server->new( port => 4423 );
    $server->reg_cb(
        echo => sub {
            my ($res_cv, @params) = @_;
            $res_cv->result(@params);
        },
        sum => sub {
            my ($res_cv, @params) = @_;
            $res_cv->result( $params[0] + $params[1] );
        },
    );

=head1 DESCRIPTION

This module is server part of L<AnyEvent::JSONRPC::Lite>.

=head1 METHOD

=head1 new (%options)

Create server object, start listening socket, and return object.

    my $server = AnyEvent::JSONRPC::Lite::Server->new(
        port => 4423,
    );

Available C<%options> are:

=over 4

=item port (Required)

Listening port.

=item address (Optional)

Bind address. Default to undef: This means server binds all interfaces by default.

=item handler_options (Optional)

Hashref options of L<AnyEvent::Handle> that is used to handle client connections.

=back

=head2 reg_cb (%callbacks)

Register JSONRPC methods.

    $server->reg_cb(
        echo => sub {
            my ($res_cv, @params) = @_;
            $res_cv->result(@params);
        },
        sum => sub {
            my ($res_cv, @params) = @_;
            $res_cv->result( $params[0] + $params[1] );
        },
    );

=head3 callback arguments

JSONRPC callback arguments consists of C<$result_cv>, and request C<@params>.

    my ($result_cv, @params) = @_;

C<$result_cv> is L<AnyEvent::JSONRPC::Lite::CondVar> object.
Callback must be call C<$result_cv->result> to return result or L<$result_cv->error> to return error.

If L<$result_cv> is not defined, it is notify request, so you don't have to return response. See L<AnyEvent::JSONRPC::Lite::Client> notify method.

C<@params> is same as request parameter.

=head1 AUTHOR

Daisuke Murase <typester@cpan.org>

=head1 COPYRIGHT AND LICENSE

Copyright (c) 2009 by KAYAC Inc.

This program is free software; you can redistribute
it and/or modify it under the same terms as Perl itself.

The full text of the license can be found in the
LICENSE file included with this module.

=cut
