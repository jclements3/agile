# find-peak-element: Find a peak (LeetCode 162)
#
# Pattern:  binary search, always stepping toward the higher neighbour
# Why:      if nums[mid] < nums[mid + 1] the values rise to the right and must
#           come down before the edge (minus infinity), so a peak lies right;
#           otherwise one lies at mid or to its left
# Time:     O(log n)   Space: O(1)
# Edge:     one element; strictly rising (last index) or falling (index 0)
# Perl:     loop while ($lo < $hi) so mid + 1 is always in range
use strict;
use warnings;

sub find_peak {
    my ($nums) = @_;
    my ($lo, $hi) = (0, $#$nums);
    while ($lo < $hi) {
        my $mid = int(($lo + $hi) / 2);
        if ($nums->[$mid] > $nums->[ $mid + 1 ]) { $hi = $mid }
        else { $lo = $mid + 1 }
    }
    return $lo;
}

1;
