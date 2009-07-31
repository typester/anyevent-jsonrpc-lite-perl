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
        $cv->cb(
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

