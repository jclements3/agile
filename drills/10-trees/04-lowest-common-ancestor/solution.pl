# lowest-common-ancestor: Lowest common ancestor in a BST (LeetCode 235)
#
# Pattern:  walk from the root toward both values until they split
# Why:      while both values are smaller (or both larger) the answer lies on
#           that side; the first node between them (or equal to one) is it
# Time:     O(h)   Space: O(1)
# Edge:     one node is the ancestor of the other; p and q in either order
# Perl:     a loop, not recursion; return the node itself, not its value
use strict;
use warnings;

sub lowest_common_ancestor {
    my ($root, $p, $q) = @_;
    my $node = $root;
    while ($node) {
        if    ($p->{val} < $node->{val} && $q->{val} < $node->{val}) { $node = $node->{left} }
        elsif ($p->{val} > $node->{val} && $q->{val} > $node->{val}) { $node = $node->{right} }
        else                                                         { return $node }
    }
    return undef;
}

1;
