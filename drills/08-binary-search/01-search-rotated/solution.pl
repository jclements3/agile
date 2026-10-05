# search-rotated: Search a rotated sorted list (LeetCode 33)
#
# Pattern:  binary search; at every step one half of [lo, hi] is sorted
# Why:      compare the ends to see which half is sorted; if the target lies
#           within that sorted half's range go there, otherwise the other half
# Time:     O(log n)   Space: O(1)
# Edge:     not rotated at all; one element; empty -> -1
# Perl:     int(($lo + $hi) / 2) for the midpoint (no integer division operator)
use strict;
use warnings;

sub search_rotated {
    my ($nums, $target) = @_;
    my ($lo, $hi) = (0, $#$nums);
    while ($lo <= $hi) {
        my $mid = int(($lo + $hi) / 2);
        return $mid if $nums->[$mid] == $target;
        if ($nums->[$lo] <= $nums->[$mid]) {
            if ($nums->[$lo] <= $target && $target < $nums->[$mid]) { $hi = $mid - 1 }
            else { $lo = $mid + 1 }
        }
        else {
            if ($nums->[$mid] < $target && $target <= $nums->[$hi]) { $lo = $mid + 1 }
            else { $hi = $mid - 1 }
        }
    }
    return -1;
}

1;
