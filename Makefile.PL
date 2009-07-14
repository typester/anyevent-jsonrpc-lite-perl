use inc::Module::Install;
name 'AnyEvent-JSONRPC-Lite';
all_from 'lib/AnyEvent/JSONRPC/Lite.pm';

requires 'AnyEvent' => '4.80';

test_requires 'Test::More';
test_requires 'Test::TCP';

author_tests('xt');

use_test_base;
auto_include;
WriteAll;
