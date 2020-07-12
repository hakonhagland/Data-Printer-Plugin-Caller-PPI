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
use Carp;
use Data::Printer;
use Cwd ();
use File::Basename ();
use File::Spec;
use File::Temp ();
use Test::More;
use Test::Output;
use version;

# This module should only be used with the new version of DDP
ok( (version->parse($Data::Printer::VERSION) >= version->parse("0.91")),
  "Data::Printer version is high enough");

done_testing();
