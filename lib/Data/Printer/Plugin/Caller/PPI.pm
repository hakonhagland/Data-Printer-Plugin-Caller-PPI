package Data::Printer::Plugin::Caller::PPI;
use feature qw(say);
use strict;
use warnings;

use Carp;
use Cwd;
use File::Spec;
use Data::Printer::Plugin::Caller::PPI::Common;
use Data::Printer::Plugin::Caller::PPI::Parser;
our $VERSION = '0.001';

#
# For background regarding the below $initial_cwd variable, see
# http://www.perlmonks.org/?node_id=1156424
# https://github.com/Perl/perl5/issues/15212
my $initial_cwd;
BEGIN {
    # This code is copied from FindBin::cwd2();
    $initial_cwd = Cwd::getcwd();
    # getcwd might fail if it hasn't access to the current directory.
    # try harder.
    defined $initial_cwd or $initial_cwd = Cwd::cwd();
}

sub new {
    my ( $class, %args ) = @_;

    my $self = Data::Printer::Plugin::Caller::PPI::Common::_bless(
        \%args, [qw(parent template caller)], $class
    );
    return $self;
}

sub get_message {
    my ( $self ) = @_;

    $self->{package} = $self->{caller}[0];
    $self->{filename} = $self->{caller}[1];
    $self->{lineno} = $self->{caller}[2];
    warn "get_message() called..";
    # Handle the package, filename, and line part (but not the variable name part)
    my $message = $self->handle_package_filename_line( );
    if ( $message ) {
        warn "handle_var_name..";
        $message = $self->handle_var_name( $message );
        warn "message = $message";
    }
    return $message;
}

sub handle_var_name {
    my ( $self, $message ) = @_;

    my $regex = qr/\b(__VAR__)\b/;
    if ( $message =~ $regex ) {
        # try to guess the variable name that is printed by reading
        # $line in $filename
        my $replace = $self->get_caller_print_var();
        # use grep to remove empty items
        my @parts = grep $_, split $regex, $message;
        for ( @parts ) {
            if (/^$regex$/) {
                s/$regex/$replace/;
                $_ = $self->{parent}->maybe_colorize($_, 'caller_info_var', 'green');
            }
            else {
                $_ = $self->{parent}->maybe_colorize($_, 'caller_info', 'blue');
            }
        }
        $message = join "", @parts;
    }
    else {
        $message = $self->{parent}->maybe_colorize(
            $message, 'caller_info', 'bright_cyan'
        );
    }
    return $message;
}

# This function reads line number $lineno from file $filename (if $line is undef).
#   If this function is called more than once for a given $filename, it still
#   rereads the file each time. So a possible improvement could be to store each
#   line of a file in private array the first time the file is read. Then
#   subsequent calls for the same $filename could simply lookup the line in the
#   array.
#
sub get_caller_print_var {
    my ( $self ) = @_;

    my $line = $self->{line};
    if ( !defined $line ) {
        if ( !defined $self->{filename} ) {
            return _quote('??');
        }
        $line = $self->_get_caller_source_line( );
        if ( !defined $line ) {
            return _quote("<Could not read file '$self->{filename}'>");
        }
    }
    my $called_as  = $self->{caller}[3];
    my ( $valid_callers, $proto ) = $self->_get_valid_callers( $called_as );
    my $parser = Data::Printer::Plugin::Caller::PPI::Parser->new(
        parent        => $self,
        lineno        => $self->{lineno},
        line          => $line,
        called_as     => $called_as,
        valid_callers => $valid_callers,
        proto         => $proto,
    );
    my $doc = $parser->get_ppi_document( $line );
    if ( defined $doc ) {
        $line = $parser->parse_line( $doc );
    }
    return _quote( $line );
}

# The value of the variable $called_as (derived from the value of caller()) can
# take one of two values (as far as I have been able to determine):
#
# - Data::Printer::p
# - Data::Printer::_p_without_prototypes
#
# The corresponding value on the source line is usually not the same. Some
#   examples:
#
# - p
# - Data::Printer::p
# - pp # i.e. an alias
#
# Here we try to use some heuristics to determine what would be a valid call
# function name on the source line. We do this to later be able to determine the
# correct statement if there should be more than one Perl statement on the
# source line.
#
sub _get_valid_callers {
    my ( $self, $called_as ) = @_;

    my $subref = $self->_get_call_subref( $called_as );
    my $aliases = $self->_get_caller_aliases( $subref );
    my $name = $called_as;
    $name =~ s/^.*:://;  # strip the Data::Printer prefix

    # We assume $name is either equal to "p" or "_p_without_prototypes"
    my $proto = ($name eq "p") ? 1 : 0;
    my @valid_callers = (@$aliases, $called_as);
    return (\@valid_callers, $proto );
}

sub _get_call_subref {
    my ( $self,  $called_as ) = @_;

    my ($pack, $fun) = $called_as =~ /^(.*)::((?:(?!::).)*)$/;
    no strict 'refs';
    my $subref = *{"$pack\::$fun"}{CODE};
    warn "Could not determine called sub ref" if !defined $subref;
    return $subref;
}

sub _get_caller_aliases {
    my ( $self,  $subref ) = @_;

    my $package = $self->{package};
    no strict 'refs';
    my @aliases;
    for my $key (keys %{"$package\::"}) {
        if ( my $temp = *{"$package\::$key"}{CODE} ) {
            if ($temp == $subref) {
                push @aliases, $key;
            }
        }
    }
    return \@aliases;
}

sub _quote {
    my ( $str ) = @_;

    return '"' . $str . '"';
}

sub _get_caller_source_line {
    my ( $self ) = @_;

    my $filename = $self->_get_abs_filename( );
    my $open_success = open ( my $fh, '<', $filename );
    if ( !$open_success ) {
        ## croak "Could not open file '$filename': $!";
        # We do not want to terminate the program simply
        # because the file cannot be read. Instead return 'undef'
        # to signal that we failed to read the file.
        return undef;
    }
    my $line;
    do { $line = <$fh> } until $. == $self->{lineno} || eof;
    close $fh;
    chomp $line;
    $line =~ s/^\s+//;
    $line =~ s/\s+$//;
    return $line;
}

sub _get_abs_filename {
    my ( $self ) = @_;

    my $filename = $self->{filename};
    # Note: $filename can be absolute or relative.
    # A difficulty of determining the absolute path of $filename arises
    # if $filename is relative:
    #
    # - If $filename is equal to $0, then $filename is relative
    #   to the initial current directory at the time the main Perl script was run. 
    #   This directory may not be equal to the current directory at this point.
    #   The absolute path of $0 can be recovered using $FindBin::Bin,
    #   but we choose to not use $FindBin::Bin, since $FindBin::Bin does not expose
    #   the initial current directory (it rather exposes the directory of the main
    #   script $0, for example if we run from command line: "perl ./test/prog.pl", then
    #   the initial current directory is what '.' would expand to at the time the script
    #   prog.pl was run, whereas the directory of the main script ($0, here: 'prog.pl')
    #   would be '/test/'),  which we will need if $filename is different
    #   from $0 (that is: a module or a another Perl file loded with "do $filename;").
    #
    # - If $filename is not equal to $0, which would be the case for
    #    * a "require $filename" (implicitly called for any "use ModuleName"
    #      statement) or a "do $filename", and
    #    * ( for a required file) the corresponding entry in @INC
    #      is a relative pathname,
    #   then $filename is relative to the current directory at the time the module
    #   was loaded (which again, might not be equal to the current directory at
    #   this point. Also, for a required file at run time ( not at compile time )
    #   the current directory at the time the module was loaded need not be equal
    #   to the initial current directory ( as used to recover $0, see above )
    #
    #  Note: The values in %INC may also be relative (a value will be relative
    #    if the file was loaded based on a relative path from @INC).
    #
    #  Note: This plugin module is "require"d at run time by Data::Printer, so
    #    the value we record for $initial_cwd in this module might not be equal
    #    to the value of the current directory when Data::Printer was loaded at
    #    compile time (assuming Data::Printer is usually loaded at compile
    #    time). TODO: We could try to improve on the sitation by having
    #    'Data::Printer' also record an intial cwd variable and pass it along to
    #    the constructor of this module. Then we could check both the
    #    $intial_cwd in this class, and if it fails to find a file, we could try
    #    again with the intital cwd from the time when Data::Printer was loaded.
    #
    if ( !File::Spec->file_name_is_absolute( $filename ) ) {
        # NOTE: variable $initial_cwd below is a lexical variable defined
        #    outside the scope of this subroutine
        #
        # The following recovery of the absolute $filename should work for most
        #  cases. It may still not work however, in the following cases:
        #
        #  1. This module (let's denote it Y) is loaded at compile time, but later,
        #     at run time, a module M is loaded that also uses Y. If M is
        #     loaded based on a relative path in @INC, and if the current
        #     directory has changed since Y was loaded at compile time,
        #     it could be unclear what the absolute path of M would be. If the path
        #     cannot be recoverd with $initial_cwd, we also try the current
        #     directory (see below). However, if the current directory has changed
        #     since module M was loaded, at the time when a Data::Printer::p()
        #     command is executed, that will also fail.
        #
        #  2. This module is loaded at compile time with a "use Data::Printer::..."
        #     statement, and either
        #    -  the initial current directory is changed *earlier* at compile
        #       time. That is, in a BEGIN {} block which is executed before
        #       $initial_cwd in Y has been defined. Then $initial_cwd
        #       may be wrong for some of the  modules loaded before Y, or
        #    -  the initial current directory is changed *after* at compile
        #       time (or run time). That is, the current directory is changed after
        #       $initial_cwd in Y has been defined. Then $initial_cwd
        #       may be wrong for some of the modules loaded after Y (and
        #       that also "use" Data::Printer).
        #
        #       Note: the above point assumes (at least) that the current directory
        #       is changed nonlocally (chdir() is called, and and not reset immediately
        #       after) at compile time. This is considered very unlikely to happen.
        #
        #
        # NOTE: Maybe all these problems could have been avoided if __FILE__
        #   and caller() had avoided using relative path names. A ticket has been
        #   submitted, see: https://github.com/Perl/perl5/issues/15212
        #
        my $fn_abs = File::Spec->rel2abs( $filename, $initial_cwd );
        if ( ! -e $fn_abs ) {
            # Assume $filename is relative to current directory if it is not relative
            # to $initial_cwd. Note: Cwd::abs_path( $filename ) would fail if a
            # directory component of $filename does not exist. See:
            #   http://stackoverflow.com/q/35876488/2173773
            # we therefore use: File::Spec->rel2abs()
            $fn_abs = File::Spec->rel2abs( $filename, '.' );
        }
        $filename = $fn_abs;
    }
    return $filename;
}

sub handle_package_filename_line {
    my ( $self ) = @_;

    my $line = undef;
    my $lineno = $self->{lineno};
    my $filename = $self->{filename};
    my $filename_str = $filename;
    my $package = $self->{package};
    # Note : $filename will not be valid if we were called from "eval $str"..
    #   In that case $filename will be on the form "(eval xx)"..
    #   For example, for "eval 'p $var'", $filename will be "(eval xx)",
    #   in "caller 3", for "xx" equal to an integer representing the
    #   number of the eval statement in the source (as encountered on runtime).
    #
    #   For example, if this were the third "eval" encountered at runtime, xx
    #   would be 3. In this case, element 7 of "caller 3" will contain the
    #   eval-text, i.e. "p $var", and $filename and $line can also be recovered
    #   from "caller 3".  But not all cases allows the source line to be
    #   recovered. For example, for "eval 'sub my_func { p $var }'", and then a
    #   call to "my_func()", will set $filename to "(eval xx)", but now element
    #   7 of "caller 3" will no longer be defined. So in order to determine the
    #   source statement in "caller 2", one would need to parse the whole source
    #   using PPI and search for the xx-th eval statement, and then try to parse
    #   that statement to arrive at 'p $var'.. However, since the xx number
    #   refers to runtime code, it may not be the same number as in the source
    #   code... (Alternatively one could try use "B::Deparse" on "my_func")
    #
    return if check_running_under_perldb();
    my $eval_regex = qr/^\Q(eval\E/;
    if ( $filename =~ $eval_regex ) {
        my @caller = caller 4;
        #   Still try to determine $filename, by going one stack frame up:
        if ( $caller[1] =~ $eval_regex ) {
            # TODO: we do not currently handle recursive evals
            #   currently: simply bail out on determining the $filename
            $filename = undef;
            $package = '??';
            $filename_str = '??';
            $lineno = 0;
        }
        else {
            $package = $caller[0];
            $filename = $caller[1];
            $filename_str = $caller[1];
            $lineno = $caller[2];
        }
        $line = $caller[6];  # this is the $str in "eval $str" (or may be undef)
        if ( defined $line ) {
            # seems like earlier versions of perl (< 5.20) adds a new line and a
            # semicolon to this string.. remove those
            $line =~ s/;$//;
            $line =~ s/\s+$//;
        }
    }
    $self->{line} = $line;
    $self->{lineno} = $lineno;
    $self->{filename} = $filename;
    $self->{package} = $package;
    my $message = $self->{template};
    $message =~ s/\b__PACKAGE__\b/$package/g;
    $message =~ s/\b__FILENAME__\b/$filename_str/g;
    $message =~ s/\b__LINE__\b/$lineno/g;
    return  $message;
}

sub check_running_under_perldb {
    return 0 if $ENV{DDP_PPI_DEBUG};
    return exists $INC{"perl5db.pl"};
}


1;

=head1 NAME

=encoding UTF-8

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




