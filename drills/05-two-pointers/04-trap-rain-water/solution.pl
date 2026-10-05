# trap-rain-water: Trapped rain water (LeetCode 42)
#
# Pattern:  two pointers, each side keeping its running maximum
# Why:      move the lower side: its water level is fixed by its own running
#           max, because the other side already has something at least as tall
# Time:     O(n)   Space: O(1)
# Edge:     fewer than three columns hold nothing; an empty list -> 0
# Perl:     plain index arithmetic; $#$h is -1 for an empty list
use strict;
use warnings;

sub trapped_water {
    my ($h) = @_;
    my ($lo, $hi) = (0, $#$h);
    my ($left_max, $right_max, $water) = (0, 0, 0);
    while ($lo < $hi) {
        if ($h->[$lo] < $h->[$hi]) {
            $left_max = $h->[$lo] if $h->[$lo] > $left_max;
            $water += $left_max - $h->[$lo];
            $lo++;
        }
        else {
            $right_max = $h->[$hi] if $h->[$hi] > $right_max;
            $water += $right_max - $h->[$hi];
            $hi--;
        }
    }
    return $water;
}

1;
