# max-depth: Depth of a binary tree (LeetCode 104)
#
# Pattern:  depth-first recursion: 1 + the deeper subtree
# Why:      the longest path through a node goes into its deeper child
# Time:     O(n)   Space: O(h) for the recursion, h = height
# Edge:     empty tree is 0; a chain (height n) recurses n deep
# Perl:     List::Util max; "return 0 unless $node" for the base case
use strict;
use warnings;
use List::Util qw(max);

sub max_depth {
    my ($node) = @_;
    return 0 unless $node;
    return 1 + max(max_depth($node->{left}), max_depth($node->{right}));
}

1;
