package Data::Printer::Plugin::Caller::PPI;
use feature qw(say);
use strict;
use warnings;

use Carp;
our $VERSION = '0.001';

sub new {
    my ( $class, %args ) = @_;

    my $self = _bless( \%args, [qw(parent template caller)], $class);
    return $self;
}

sub get_message {
    my ( $self ) = @_;

    my $message = "";
    return $message;
}

sub _bless {
    my ( $args, $expected, $class ) = @_;

    my %exp = map { $_ => 1 } @$expected;
    for my $key (keys %$args) {
        if (!exists $exp{$key} ) {
            carp "Unexpected argument to constructor for class '$class': " . $key;
        }
        delete $exp{$key};
    }
    my @k = keys %exp;
    if (@k) {
        carp 'Missing argument'
          . ((@k > 1) ? 's' : '')
          . ": '"
          . (join ', ', keys %exp), "'";
    }
    return bless $args, $class;
}



1;

=head1 NAME

Data::Printer::Plugin::Caller::PPI - Module abstract placeholder text

=head1 SYNOPSIS

=for comment Brief examples of using the module.

=head1 DESCRIPTION

=for comment The module's description.

=head1 AUTHOR

Håkon Hægland <hakon.hagland@gmail.com>

=head1 COPYRIGHT AND LICENSE

This software is copyright (c) 2020 by Håkon Hægland.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

