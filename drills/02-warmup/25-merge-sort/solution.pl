# merge-sort: Merge sort by hand (LeetCode 912)
#
# Pattern:  divide and conquer, then a two-pointer merge
# Why:      two sorted halves merge in one pass by always taking the smaller head
# Time:     O(n log n)   Space: O(n)
# Edge:     empty and one-element lists are already sorted; equal values (<= keeps it stable)
# Perl:     slices @$xs[0 .. $mid - 1]; shift from the front of each half
use strict;
use warnings;

sub merge_sort {
    my ($xs) = @_;
    return [@$xs] if @$xs <= 1;
    my $mid = int(@$xs / 2);
    my $l = merge_sort([ @$xs[ 0 .. $mid - 1 ] ]);
    my $r = merge_sort([ @$xs[ $mid .. $#$xs ] ]);
    my @out;
    while (@$l && @$r) { push @out, $l->[0] <= $r->[0] ? shift @$l : shift @$r }
    return [ @out, @$l, @$r ];
}

1;
