# adjacent-diffs: Adjacent differences
#
# Pattern:  pairwise over neighbours
# Why:      indices 1 .. last each pair with the index before
# Time:     O(n)   Space: O(n)
# Edge:     zero or one element gives an empty list (1 .. 0 is empty)
# Perl:     map { $xs->[$_] - $xs->[$_ - 1] } 1 .. $#$xs
use strict;
use warnings;

sub adjacent_diffs {
    my ($xs) = @_;
    return [ map { $xs->[$_] - $xs->[ $_ - 1 ] } 1 .. $#$xs ];
}

1;
