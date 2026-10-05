# two-sum-sorted: Two sum on sorted input (LeetCode 167)
#
# Pattern:  two pointers from both ends of sorted data
# Why:      a sum too small can only grow by moving lo right, too big only
#           shrink by moving hi left; nothing skipped can be part of a pair
# Time:     O(n)   Space: O(1)
# Edge:     empty or one-element input -> undef; negatives are fine
# Perl:     return undef explicitly (a bare return in list context is empty)
use strict;
use warnings;

sub two_sum_sorted {
    my ($xs, $target) = @_;
    my ($lo, $hi) = (0, $#$xs);
    while ($lo < $hi) {
        my $sum = $xs->[$lo] + $xs->[$hi];
        return [ $lo, $hi ] if $sum == $target;
        if ($sum < $target) { $lo++ } else { $hi-- }
    }
    return undef;
}

1;
