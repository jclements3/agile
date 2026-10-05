# longest-increasing-subsequence: (LeetCode 300)
#
# Pattern:  dp[i] = length of the longest increasing subsequence ending at i
# Why:      such a subsequence is some shorter one ending at j < i with a
#           smaller value, extended by nums[i]
# Time:     O(n^2) (O(n log n) with patience sorting is the stretch)
# Space:    O(n)
# Edge:     empty -> 0; equal values never extend (strict)
# Perl:     List::Util max over the dp array; max() of nothing is undef, so
#           guard the empty list
use strict;
use warnings;
use List::Util qw(max);

sub lis {
    my ($nums) = @_;
    return 0 unless @$nums;
    my @dp = (1) x @$nums;
    for my $i (1 .. $#$nums) {
        for my $j (0 .. $i - 1) {
            $dp[$i] = $dp[$j] + 1 if $nums->[$j] < $nums->[$i] && $dp[$j] + 1 > $dp[$i];
        }
    }
    return max(@dp);
}

1;
