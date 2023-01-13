use feature qw(say);
use strict;
use warnings;

BEGIN {
    # Load this before "Data::Printer" to avoid user's .dataprinter
    use Data::Printer::Config;
    no warnings 'redefine';
    *Data::Printer::Config::load_rc_file = sub { {} };
}
use Data::Printer colored        => 0,
                  use_prototypes => 0,
                  caller_info    => 1,
                  caller_plugin  => 'PPI';
use Data::Printer::Plugin::Caller::PPI;
use Test::More;
use version;

diag "modpath = $INC{'Data/Printer/Plugin/Caller/PPI.pm'}";
# This module should only be used with the new version of DDP
ok( (version->parse($Data::Printer::VERSION) >= version->parse("0.91")),
  "Data::Printer version is high enough");

eval {
    my $cppi = Data::Printer::Plugin::Caller::PPI->new(
        parent => []
    );
};
like( $@, qr/Missing arguments/, 'missing args to constructor');
eval {
    my $cppi = Data::Printer::Plugin::Caller::PPI->new(
        parent => [], template => 1, caller => 0, foo => 3
    );
};
like( $@, qr/Unexpected argument to constructor/, 'missing args to constructor');

done_testing();
