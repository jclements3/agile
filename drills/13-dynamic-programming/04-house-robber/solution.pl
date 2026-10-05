# house-robber: No two neighbours (LeetCode 198)
#
# Pattern:  DP with two running values: best ending with a take, or a skip
# Why:      taking x is only allowed after a skip; skipping keeps the better
#           of the two previous states
# Time:     O(n)   Space: O(1)
# Edge:     empty -> 0; one value
# Perl:     list assignment updates both from the old values at once
use strict;
use warnings;

sub rob {
    my ($values) = @_;
    my ($take, $skip) = (0, 0);
    for my $x (@$values) {
        ($take, $skip) = ($skip + $x, $take > $skip ? $take : $skip);
    }
    return $take > $skip ? $take : $skip;
}

1;
