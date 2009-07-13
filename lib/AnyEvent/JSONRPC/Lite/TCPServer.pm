package AnyEvent::JSONRPC::Lite::TCPServer;
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
    isa     => 'Int',
    default => 4423,
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

has _callbacks => (
    is      => 'ro',
    isa     => 'HashRef',
    lazy    => 1,
    default => sub { {} },
);

has _callback_guards => (
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
        unless ($fh) {
            warn "Failed to start JSONRPC Server: $!";
            return;
        }

        my $indicator = "$host:$port";

        my $handle = AnyEvent::Handle->new(
            %{ $self->handler_options },
            fh => $fh,
        );
        $handle->on_read(sub {
            shift->unshift_read( json => sub {
                $self->_dispatch($indicator, @_);
            }),
        });
        $self->handler( $handle );
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

            $self->handler->push_write( json => {
                id     => $id,
                result => $type eq 'result' ? $result : undef,
                error  => $type eq 'error'  ? $result : undef,
            });
            $self->_remove_guard( $indicator );
        };

        my $cv = AnyEvent::JSONRPC::Lite::CondVar->new;
        $cv->cb(
            sub { $res_cb->( result => $_[0]->recv ) },
            sub { $res_cb->( error  => $_[0]->recv ) },
        );

        $target ||= sub { shift->error(qq/No such method "$request->{method}" found/) };
        $target->( $cv, $request->{params} );

        $self->_set_guard( $indicator => $cv );
    }
    else {
        # without id parameter, this is notification.
        # dispatch to method without cv object.
        $target ||= sub { warn qq/No such method "$request->{method}" found/ };
        $target->(undef, $request->{params});
    }
}

sub _set_guard {
    my ($self, $indicator, $cv) = @_;
    $self->_callback_guards->{ $indicator } = $cv;
}

sub _remove_guard {
    my ($self, $indicator) = @_;
    delete $self->_callback_guards->{ $indicator };
}

__PACKAGE__->meta->make_immutable;

