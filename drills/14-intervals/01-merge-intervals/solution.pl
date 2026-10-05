# merge-intervals: Merge overlapping intervals (LeetCode 56)
#
# Pattern:  sort by start, then sweep: extend the last merged interval while
#           the next one starts at or before its end
# Why:      after sorting, anything that overlaps the current run is next in
#           line; the first gap ends the run for good
# Time:     O(n log n)   Space: O(n)
# Edge:     touching (<=, not <); one interval inside another (keep the max
#           end); empty input; unsorted input
# Perl:     sort { $a->[0] <=> $b->[0] }; copy each pair so the caller's
#           arrays are not changed
use strict;
use warnings;

sub merge_intervals {
    my ($intervals) = @_;
    my @out;
    for my $iv (sort { $a->[0] <=> $b->[0] } @$intervals) {
        if (@out && $iv->[0] <= $out[-1][1]) {
            $out[-1][1] = $iv->[1] if $iv->[1] > $out[-1][1];
        }
        else {
            push @out, [@$iv];
        }
    }
    return \@out;
}

1;
