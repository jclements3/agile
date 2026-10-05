# build-from-preorder-inorder: Rebuild a tree (LeetCode 105)
#
# Pattern:  the first preorder value is the root; its inorder position splits
#           the rest into the left and right subtrees
# Why:      the left subtree's size (mid - in_lo) tells how many preorder
#           values belong to it; recurse on index ranges, never on copies
# Time:     O(n) with the value -> inorder index hash   Space: O(n)
# Edge:     empty input; one-sided chains
# Perl:     %idx built with a hash slice: @idx{@$in} = 0 .. $#$in;
#           half-open ranges [lo, hi) keep the arithmetic simple
use strict;
use warnings;

sub build_tree {
    my ($pre, $in) = @_;
    my %idx;
    @idx{@$in} = 0 .. $#$in;
    return _build($pre, \%idx, 0, scalar @$pre, 0);
}

sub _build {
    my ($pre, $idx, $plo, $phi, $ilo) = @_;
    return undef if $plo >= $phi;
    my $val  = $pre->[$plo];
    my $left = $idx->{$val} - $ilo;
    return {
        val   => $val,
        left  => _build($pre, $idx, $plo + 1, $plo + 1 + $left, $ilo),
        right => _build($pre, $idx, $plo + 1 + $left, $phi, $idx->{$val} + 1),
    };
}

1;
