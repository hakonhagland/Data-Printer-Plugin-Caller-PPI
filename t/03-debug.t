use feature qw(say);
use strict;
use warnings;

BEGIN {
    # Load this before "Data::Printer" to avoid user's .dataprinter
    use Data::Printer::Config;
    no warnings 'redefine';
    *Data::Printer::Config::load_rc_file = sub { {} };
}
use Data::Printer::Plugin::Caller::PPI; # make sure %INC is updated with this
use Test::More;
use Test::Output;
use Data::Printer 
{
    use_prototypes => 1,
    return_value   => 'pass',
    colored        => 0,
    caller_info    => 1,
    caller_plugin  => 'PPI',
    caller_message => 'Printing __VAR__ in line __LINE__ of __FILENAME__:'
};

my @a = [0,1,2];

my $res = p @a;

diag "res = $res";

ok $res == 1;

done_testing();
