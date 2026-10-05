# running-totals: Running totals (LeetCode 1480)
#
# Pattern:  prefix sums
# Why:      carry the sum so far; each output is the previous plus one element
# Time:     O(n)   Space: O(n)
# Edge:     empty input
# Perl:     map { $sum += $_ } -- the assignment's value is the new sum
use strict;
use warnings;

sub running_totals {
    my ($xs) = @_;
    my $sum = 0;
    return [ map { $sum += $_ } @$xs ];
}

1;
