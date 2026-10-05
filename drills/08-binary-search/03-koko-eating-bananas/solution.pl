# koko-eating-bananas: Slowest speed that finishes in time (LeetCode 875)
#
# Pattern:  binary search on the answer: the smallest k with hours(k) <= h
# Why:      hours(k) only falls as k grows, so "fast enough" is false then true
#           over 1..max(pile); find the first true
# Time:     O(n log max)   Space: O(1)
# Edge:     hours equal to the number of piles forces k = the largest pile
# Perl:     ceiling of p / k as int(($p + $k - 1) / $k); max from List::Util
use strict;
use warnings;
use List::Util qw(max);

sub min_speed {
    my ($piles, $h) = @_;
    my ($lo, $hi) = (1, max(@$piles));
    while ($lo < $hi) {
        my $k = int(($lo + $hi) / 2);
        my $hours = 0;
        $hours += int(($_ + $k - 1) / $k) for @$piles;
        if ($hours <= $h) { $hi = $k } else { $lo = $k + 1 }
    }
    return $lo;
}

1;
