package Data::Printer::Plugin::Caller::PPI::Parser;
use feature qw(say);
use strict;
use warnings;
use List::Util qw(any first);
use PPI;
use Data::Printer::Plugin::Caller::PPI::Common;
use Data::Printer::Plugin::Caller::PPI::Extensions;

sub new {
    my ( $class, %args ) = @_;

    my $self = Data::Printer::Plugin::Caller::PPI::Common::_bless(
        \%args, [qw(parent lineno line called_as valid_callers proto)], $class
    );
    $self->_setup_ppi_extensions();
    return $self;
}


# Use PPI to parse the source line.
#
# This approach (using PPI) is admittedly somewhat heavy, but no good
# alternative has yet to be found, though many interesting approaches was found on CPAN,
# but as far as I can see, none of those seems perfect either:
#
#  - Using a source filter (Filter::Util::Call) as in Data::Dumper::Simple and
#    Debug::ShowStuff::ShowVar and let the filter parse the line using a regex
#    and then substitute it with another call to the data dumper function that
#    includes the variable names in the argument list
#
#  - Using PadWalker as in Devel::Caller and Data::Dumper::Names
#
#  - Using B::Deparse as in Data::Dumper::Lazy
#
#  - Using B::CallChecker and B::Deparse as in Debug::Show
#
# See also:
#  - perlmonks: "Displaying a variable's name and value in a sub"
#      http://www.perlmonks.org/?node_id=888088
#
sub get_ppi_document {
    my ( $self, $line ) = @_;

    _add_trailing_semicolon( \$line );
    my $doc = PPI::Document->new( \$line );
    return _check_doc_complete( $doc );
}

sub _add_trailing_semicolon {
    my ( $line ) = @_;

    if ( $$line !~ /;\s*$/ ) {
        $$line .= ';';
    }
}

sub _setup_ppi_extensions {
    my ( $self ) = @_;
    
    no strict "refs";
    for (qw( is_comma_or_semi_colon name)) {
        *{"PPI::Element::$_"} = \&{"Data::Printer::Plugin::Caller::PPI::Extensions::$_"};
    }
}

# Checks if the line we read from the source file is complete. That is, if
# it consists of one or more valid Perl statements. Examples of invalid lines:
#
#   p $a; my %h = (
#
# This line is not valid since the second statement (my %h = ... ) is not complete.
# (It is completed on the following lines (not shown)); another example:
#
#   };  p $var;
#
# In this case, the preceding source lines (not shown) defines a hash or a sub,
# which is completed on this line ( '};' ).
#
#    p { a=> 1, 
#
# In this example (assuming use_protypes = 0 ), the hash is not completed on the
# given source line..
#
# These cases can be handled by reading additional lines before or after the
# given source line until the complete() function of PPI::Document returns true.
# 
# However, currently only source lines with one (or more) complete statement are
# handled. ( Support for statements extending
# over multiple lines should be straightforward to implement though, if needed. )
#
# If the line contains a single Perl statement, it is known that that statement
# is the correct one ( the one that caused the call to Data::Printer::p() )
#
# If the line contains multiple Perl statements, we must determine which of
# the statements is the correct one. In this case, a currently crude method is
# is used to determine the correct statement: The statements in the
# PPI::Document are traversed one by one and the first one that
# matches (caller())[3] is selected.
#
#
sub _check_doc_complete {
    my ( $doc ) = @_;

    if ( $doc->complete ) {
        return $doc;
    }
    else {
        return undef;
    }
}

# Parse line, and extract variable name to be printed.
# Default behavior if we cannot determine a variable name is to return $line.
# This default should still be better than not printing anything! 
#
# Example: if $line is
#
#    "p(%some_hash, colored => 1); # print some_hash"
#
# we should be able to reduce this to "%some_hash":
#
# Note: currently the input variable "$proto" is not used.
sub parse_line {
    my ( $self, $doc ) = @_;

    # If line contains multiple statements, determine which one to use:
    my ( $line, $statement, $node ) = $self->_extract_statement_from_line( $doc );
    my $elem = $self->_find_first_word_or_statement($node);
    if ( $elem ) {
        $elem = $elem->snext_sibling;
        if ( $elem ) {
            $line = $self->_parse_var( $elem, $line );
        }
    }

    # It is not necessary to display a trailing semicolon.
    # (It will only act as "noise" in the output..)
    $line =~ s/\s*;?\s*$//;
    # $line will be quoted later. Avoid double pairs of quotes:
    $line =~ s/^["'](.*)["']$/$1/;
    # When use_prototypes = 0, references, like "\%h", should be printed as "%h":
    $line =~ s/^\\//;
    return $line;
}


sub _find_first_word_or_statement {
    my ( $self, $node) = @_;

    my $elem = $node->find_first(
        sub { return $self->_find_first_word_or_statement_helper(@_) }
    );
    return $elem;
}

sub _find_first_word_or_statement_helper {
    my ( $self, $node, $elem ) = @_;
    if (($elem->name eq 'Token::Word') and ($elem->content eq $self->{called_as})) {
        return 1;
    }
    if ($elem->name eq 'Token::Symbol') {
        if ($elem->symbol_type eq '&') {
            my $name = $elem->content;
            $name =~ s/^&//;
            return 1 if $name eq $self->{called_as};
        }
    }
    return 0;
}

# Determine the first argument (usually a variable, but could also be an
# expression) of the original caller, i.e. p() or p_without_prototypes(). 
# Currently we are able to parse the sought variable name the same way regardless
# of whether the caller was p() or p_without_prototypes(). This is due to the way
# PPI parses the line.
sub _parse_var {
    my ( $self, $elem, $orig_line ) = @_;

    if ( $elem->name eq 'Structure::List' ) {
        $elem = $self->_enter_list_structure( $elem );
        return $orig_line if !$elem; 
    }
    my $line = "";
    while ( $elem ) {
        ($elem, $line) = $self->_skip_to_next_token( $elem, $line );
    }
    return $line;
}

sub _enter_list_structure {
    my ( $self, $elem ) = @_;
    $elem = ( $elem->schildren )[0];
    return undef if !$elem;
    if ( any { $elem->name eq $_ } qw(Statement Statement::Expression) ) {
        $elem = ( $elem->schildren )[0];
    }
    return $elem;
}

sub _skip_to_next_token {
    my ( $self, $elem, $line ) = @_;
    while (1) {
        $line .= $elem->content;
        $elem = $elem->next_sibling;
        last if !$elem;
        if ( $elem->is_comma_or_semi_colon ) {
            $elem = undef;
            last;
        }
        last if $elem->significant;
    }
    return ($elem, $line);
}


#
sub _extract_statement_from_line {
    my ( $self, $doc ) = @_;
    my ($statements, $num_statements) = $self->_get_top_level_statements( $doc );

    my $statement;
    my $node;
    my $line = $self->{line};
    
    if ( $num_statements >= 1 ) {
        ($statement, $node) = $self->_select_statement( $statements );
        if ( defined $statement ) {
            $line = $statement->content;
        }
    }
    return ( $line, $statement, $node );
}

sub _select_statement {
    my ( $self, $statements ) = @_;

    my $found_statement;
    my $node;
    for my $statement (@$statements) {
        my $words = $self->_find_words_or_subroutine_symbols($statement);
        my $found_word = first {
            my $word = $_->[0];
            any { $_ eq $word } @{$self->{valid_callers}}
        } @$words;
        if ( defined $found_word ) {
            $node = $found_word->[1]->parent;
            $found_statement = $statement;
            $self->{called_as} = $found_word->[0];
            last;
        }
    }
    return ($found_statement, $node);
}

sub _find_words_or_subroutine_symbols {
    my ( $self, $statement) = @_;
    my $words = $statement->find('PPI::Token::Word');
    my @result;
    if ($words) {
        @result = map {[$_->content, $_]} @$words;
    }
    my $symbols = $statement->find('PPI::Token::Symbol');
    if ( $symbols ) {
        for my $symbol (@$symbols) {
            if ($symbol->symbol_type eq '&') {
                my $name = $symbol->content;
                $name =~ s/^&//;
                push @result, [$name, $symbol];
            }
        }
    }
    return \@result;
}
sub _find_words_or_subroutine_symbols2 {
    my ( $self, $statement) = @_;
    my $words = $statement->find(&_find_words_or_subroutine_symbols_helper);
    return $words;
}

sub _find_words_or_subroutine_symbols_helper {
    my ($node, $elem ) = @_;

    my $type = ref $elem;
    say "Type: ", $type;
    return 1 if $type eq 'PPI::Token::Word';
    if ($type eq "PPI::Token::Symbol") {
        return 1 if $elem->symbol_type eq '&';
    }
    say "No";
    return 0;
}

sub _get_top_level_statements {
    my ( $self, $ref ) = @_;

    my @items;
    for my $child ( @{ $ref->{children} } ) {
        if ( ((ref $child) eq 'PPI::Statement')
             or ((ref $child) eq 'PPI::Statement::Variable') ) {
            push @items, $child;
        }
    }
    return (\@items, scalar @items);
}

1;
