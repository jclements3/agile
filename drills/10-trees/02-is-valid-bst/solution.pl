# is-valid-bst: Is it a binary search tree? (LeetCode 98)
#
# Pattern:  recursion carrying the open interval (lo, hi) each node must fit
# Why:      going left tightens hi to the parent, going right tightens lo;
#           an ancestor's bound is therefore checked at every descendant
# Time:     O(n)   Space: O(h)
# Edge:     duplicates are invalid (strict); empty tree is valid
# Perl:     undef as "no bound" instead of infinities; a nested closure
#           needs a predeclared lexical to recurse, so use a named helper
use strict;
use warnings;

sub is_valid_bst {
    my ($root) = @_;
    return _fits($root, undef, undef);
}

sub _fits {
    my ($node, $lo, $hi) = @_;
    return 1 unless $node;
    my $v = $node->{val};
    return 0 if defined $lo && $v <= $lo;
    return 0 if defined $hi && $v >= $hi;
    return _fits($node->{left}, $lo, $v) && _fits($node->{right}, $v, $hi);
}

1;
