# adder-closure: A closure that adds
#
# Pattern:  closure
# Why:      an anonymous sub keeps the lexical $n it was created with
# Time:     O(1)   Space: O(1)
# Edge:     none
# Perl:     my $add = sub { $_[0] + $n }; a named inner sub would NOT capture
#           a fresh $n per call ("Variable will not stay shared")
use strict;
use warnings;

sub adder_result {
    my ($n, $x) = @_;
    my $add = sub { my ($v) = @_; return $v + $n };
    return $add->($x);
}

1;
