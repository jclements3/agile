# find-min-rotated: Smallest value of a rotated list (LeetCode 153)
#
# Pattern:  binary search comparing the middle with the right end
# Why:      if nums[mid] > nums[hi] the drop (the minimum) is right of mid;
#           otherwise mid..hi is sorted and the minimum is at mid or left of it
# Time:     O(log n)   Space: O(1)
# Edge:     no rotation; one element; the minimum at the last index
# Perl:     loop while ($lo < $hi), hi = mid keeps mid as a candidate
use strict;
use warnings;

sub find_min_rotated {
    my ($nums) = @_;
    my ($lo, $hi) = (0, $#$nums);
    while ($lo < $hi) {
        my $mid = int(($lo + $hi) / 2);
        if ($nums->[$mid] > $nums->[$hi]) { $lo = $mid + 1 }
        else { $hi = $mid }
    }
    return $nums->[$lo];
}

1;
