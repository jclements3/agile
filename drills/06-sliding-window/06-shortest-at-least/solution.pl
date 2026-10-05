# shortest-at-least: Shortest run reaching a target sum
#
# Pattern:  variable window: grow the right edge, shrink the left while the
#           sum still reaches the target
# Why:      with positive values, shrinking only lowers the sum, so every
#           shortest run is seen at the moment it is shrunk to its limit
# Time:     O(n)   Space: O(1)
# Edge:     no run -> 0 (best starts at n + 1 as "none yet")
# Perl:     two indices and a running $sum; no slices inside the loop
use strict;
use warnings;

sub shortest_at_least {
    my ($xs, $target) = @_;
    my $best = @$xs + 1;
    my ($sum, $lo) = (0, 0);
    for my $hi (0 .. $#$xs) {
        $sum += $xs->[$hi];
        while ($sum >= $target) {
            $best = $hi - $lo + 1 if $hi - $lo + 1 < $best;
            $sum -= $xs->[ $lo++ ];
        }
    }
    return $best <= @$xs ? $best : 0;
}

1;
