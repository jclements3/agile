# non-overlapping-intervals: Fewest removals (LeetCode 435)
#
# Pattern:  greedy interval scheduling: sort by end, keep each interval that
#           starts at or after the last kept end, remove the others
# Why:      the interval that ends first leaves the most room for the rest,
#           so keeping it is never worse (an exchange argument)
# Time:     O(n log n)   Space: O(n) for the sorted copy
# Edge:     touching intervals are compatible (>=); empty input
# Perl:     undef as "nothing kept yet" instead of minus infinity
use strict;
use warnings;

sub erase_overlaps {
    my ($intervals) = @_;
    my ($removed, $end) = (0, undef);
    for my $iv (sort { $a->[1] <=> $b->[1] } @$intervals) {
        if (!defined $end || $iv->[0] >= $end) { $end = $iv->[1] }
        else                                   { $removed++ }
    }
    return $removed;
}

1;
