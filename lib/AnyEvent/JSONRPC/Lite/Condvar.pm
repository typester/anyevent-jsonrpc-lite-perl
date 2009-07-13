package AnyEvent::JSONRPC::Lite::CondVar;
use Any::Moose;

use AnyEvent;

has _cv => (
    is      => 'ro',
    isa     => 'ArrayRef[AnyEvent::CondVar]',
    default => sub {
        [AnyEvent->condvar, AnyEvent->condvar],
    },
);

no Any::Moose;

sub cb {
    my ($self, $callback, $errback) = @_;

    $self->_cv->[0]->cb($callback);
    $self->_cv->[1]->cb($errback);
}

sub result {
    my ($self, @result) = @_;
    $self->_cv->[0]->send(@result);
}

sub error {
    my ($self, @error) = @_;
    $self->_cv->[1]->send(@error);
}

__PACKAGE__->meta->make_immutable;
