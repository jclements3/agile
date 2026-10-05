# wrap-diff: Bearing difference on a circle
#
# Pattern:  d = |a - b| reduced modulo 360, then the smaller of d and 360 - d
# Why:      two bearings split the circle into two arcs that add up to 360;
#           the answer is the shorter arc
# Time:     O(1)   Space: O(1)
# Edge:     decimals; bearings beyond 360; equal bearings -> 0
# Perl:     % truncates to integers, so use POSIX fmod for decimals
use strict;
use warnings;
use POSIX qw(fmod);

sub wrap_diff {
    my ($x, $y) = @_;
    my $d = fmod(abs($x - $y), 360);
    return $d < 360 - $d ? $d : 360 - $d;
}

1;
