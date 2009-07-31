package AnyEvent::JSONRPC::Lite;
use strict;
use warnings;
use base 'Exporter';

our @EXPORT = qw/jsonrpc_client jsonrpc_server/;

use AnyEvent::JSONRPC::Lite::Client;
use AnyEvent::JSONRPC::Lite::Server;

sub jsonrpc_client($$) {
    my ($host, $port) = @_;

    AnyEvent::JSONRPC::Lite::Client->new(
        host => $host,
        port => $port,
    );
}

sub jsonrpc_server($$) {
    my ($address, $port) = @_;

    AnyEvent::JSONRPC::Lite::Server->new(
        address => $address,
        port    => $port,
    );
}

1;

