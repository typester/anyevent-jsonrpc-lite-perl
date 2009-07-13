use inc::Module::Install;
name 'AnyEvent-JSONRPC-Lite';
all_from 'lib/AnyEvent/JSONRPC/Lite.pm';

test_requires 'Test::More';
use_test_base;
auto_include;
WriteAll;
