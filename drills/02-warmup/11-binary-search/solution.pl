# binary-search: Binary search (LeetCode 704)
#
# Pattern:  lo/hi loop on sorted data
# Why:      each comparison discards the half that cannot hold the target
# Time:     O(log n)   Space: O(1)
# Edge:     empty list (hi = -1, loop never runs); first and last elements
# Perl:     int(($lo + $hi) / 2) -- Perl division is floating point
use strict;
use warnings;

sub binary_search {
    my ($xs, $target) = @_;
    my ($lo, $hi) = (0, $#$xs);
    while ($lo <= $hi) {
        my $mid = int(($lo + $hi) / 2);
        return $mid if $xs->[$mid] == $target;
        if ($xs->[$mid] < $target) { $lo = $mid + 1 } else { $hi = $mid - 1 }
    }
    return -1;
}

1;
