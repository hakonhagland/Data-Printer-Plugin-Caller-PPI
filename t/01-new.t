use feature qw(say);
use strict;
use warnings;

BEGIN {
    # Load this before "Data::Printer" to avoid user's .dataprinter
    use File::HomeDir::Test;
    delete $ENV{DATAPRINTERRC};
    if (my $dir = $ENV{DEVEL_DDP_DIR}) {
        unshift @INC, $dir;
    }
}
use Data::Printer colored        => 0,
                  use_prototypes => 0,
                  caller_info    => 1,
                  caller_plugin  => 'PPI';
use Data::Printer::Plugin::Caller::PPI;
use Test::More;
use version;

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
