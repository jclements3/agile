# merge-sorted: Merge two sorted lists (LeetCode 88, similar)
#
# Pattern:  two pointers
# Why:      the smaller of the two heads is the next value overall
# Time:     O(n + m)   Space: O(n + m)
# Edge:     an empty side; equal values; one list entirely before the other
# Perl:     after the loop, append whatever is left of both slices
use strict;
use warnings;

sub merge_sorted {
    my ($x, $y) = @_;
    my ($i, $j, @out) = (0, 0);
    while ($i < @$x && $j < @$y) {
        push @out, $x->[$i] <= $y->[$j] ? $x->[ $i++ ] : $y->[ $j++ ];
    }
    push @out, @$x[ $i .. $#$x ], @$y[ $j .. $#$y ];
    return \@out;
}

1;
