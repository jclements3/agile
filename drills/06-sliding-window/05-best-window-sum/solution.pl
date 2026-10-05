# best-window-sum: Best sum of k in a row
#
# Pattern:  fixed-size sliding window with a rolling sum
# Why:      the next window's sum is this one's plus the element entering and
#           minus the element leaving: O(1) per step
# Time:     O(n)   Space: O(1)
# Edge:     all negative: start best at the first window, not at 0
# Perl:     sum from List::Util over a slice @$xs[0 .. $k - 1]
use strict;
use warnings;
use List::Util qw(sum);

sub best_window_sum {
    my ($xs, $k) = @_;
    my $s = sum(@$xs[ 0 .. $k - 1 ]);
    my $best = $s;
    for my $i ($k .. $#$xs) {
        $s += $xs->[$i] - $xs->[ $i - $k ];
        $best = $s if $s > $best;
    }
    return $best;
}

1;
