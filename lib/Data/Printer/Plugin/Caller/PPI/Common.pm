package Data::Printer::Plugin::Caller::PPI::Common;
use feature qw(say);
use strict;
use warnings;

use Carp;

sub _bless {
    my ( $args, $expected, $class ) = @_;

    my %exp = map { $_ => 1 } @$expected;
    for my $key (keys %$args) {
        if (!exists $exp{$key} ) {
            croak "Unexpected argument to constructor for class '$class': " . $key;
        }
        delete $exp{$key};
    }
    my @k = keys %exp;
    if (@k) {
        croak 'Missing argument'
          . ((@k > 1) ? 's' : '')
          . ": '"
          . (join ', ', keys %exp), "'";
    }
    return bless $args, $class;
}

1;
