# container-with-most-water: Most water between two walls (LeetCode 11)
#
# Pattern:  two pointers at the ends; always move the shorter wall inward
# Why:      the shorter wall limits every container that keeps it while the
#           width shrinks, so it can never do better: drop it
# Time:     O(n)   Space: O(1)
# Edge:     equal heights: moving either side is safe
# Perl:     ($h[$lo] < $h[$hi] ? $h[$lo] : $h[$hi]) as a min of two
use strict;
use warnings;

sub max_water {
    my ($h) = @_;
    my ($lo, $hi, $best) = (0, $#$h, 0);
    while ($lo < $hi) {
        my $short = $h->[$lo] < $h->[$hi] ? $h->[$lo] : $h->[$hi];
        my $area  = ($hi - $lo) * $short;
        $best = $area if $area > $best;
        if ($h->[$lo] < $h->[$hi]) { $lo++ } else { $hi-- }
    }
    return $best;
}

1;
