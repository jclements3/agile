# rotate-right: Rotate right (LeetCode 189, similar)
#
# Pattern:  modulo, then two slices
# Why:      rotating by n changes nothing, so only k % n matters; the answer is
#           the last k elements followed by the first n - k
# Time:     O(n)   Space: O(n)
# Edge:     empty list (no modulo by zero); k = 0; k a multiple of n
# Perl:     negative indices: @$xs[-$k .. -1]; guard k = 0 (-0 .. -1 would be wrong)
use strict;
use warnings;

sub rotate_right {
    my ($xs, $k) = @_;
    my $n = @$xs;
    return [] unless $n;
    $k %= $n;
    return [@$xs] unless $k;
    return [ @$xs[ $n - $k .. $n - 1 ], @$xs[ 0 .. $n - $k - 1 ] ];
}

1;
