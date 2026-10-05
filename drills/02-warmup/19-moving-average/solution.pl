# moving-average: Moving average (LeetCode 346, similar)
#
# Pattern:  sliding window sum
# Why:      add the value entering the window and subtract the one leaving,
#           instead of summing k values for every window
# Time:     O(n)   Space: O(n) for the output
# Edge:     k = n gives one average; k = 1 gives the list itself
# Perl:     Perl division is floating point already: 3 / 2 is 1.5
use strict;
use warnings;

sub moving_average {
    my ($xs, $k) = @_;
    my ($sum, @out) = (0);
    for my $i (0 .. $#$xs) {
        $sum += $xs->[$i];
        $sum -= $xs->[ $i - $k ] if $i >= $k;
        push @out, $sum / $k if $i >= $k - 1;
    }
    return \@out;
}

1;
