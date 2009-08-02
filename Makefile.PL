use inc::Module::Install;
name 'AnyEvent-JSONRPC-Lite';
all_from 'lib/AnyEvent/JSONRPC/Lite.pm';

requires 'Any::Moose';
requires 'AnyEvent' => '4.80';
requires 'JSON';

test_requires 'Test::More';
test_requires 'Test::TCP';

author_tests('xt');

use_test_base;
auto_include;
WriteAll;
