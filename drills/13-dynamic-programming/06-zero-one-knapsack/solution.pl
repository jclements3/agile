# zero-one-knapsack: 0/1 knapsack
#
# Pattern:  dp[c] = best value with capacity c, over the items seen so far
# Why:      for each item, dp[c] = max(dp[c], dp[c - w] + v); walking c from
#           the top down means dp[c - w] still excludes this item, so it is
#           used at most once (bottom-up would allow reuse)
# Time:     O(n * capacity)   Space: O(capacity)
# Edge:     no items; capacity 0; items heavier than the capacity
# Perl:     reverse $w .. $cap counts down; (0) x ($cap + 1) initialises
use strict;
use warnings;

sub knapsack {
    my ($weights, $values, $cap) = @_;
    my @dp = (0) x ($cap + 1);
    for my $i (0 .. $#$weights) {
        my ($w, $v) = ($weights->[$i], $values->[$i]);
        for my $c (reverse $w .. $cap) {
            $dp[$c] = $dp[ $c - $w ] + $v if $dp[ $c - $w ] + $v > $dp[$c];
        }
    }
    return $dp[$cap];
}

1;
