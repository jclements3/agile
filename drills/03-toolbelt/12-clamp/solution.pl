# clamp: Clamp with defaults
#
# Pattern:  default arguments, min/max
# Why:      max with lo, then min with hi
# Time:     O(1)   Space: O(1)
# Edge:     an explicit 0 (hi = 0) must not be replaced by the default
# Perl:     $lo //= 0 (defined-or), not $lo ||= 0, which would also replace a real 0
use strict;
use warnings;

sub clamp {
    my ($x, $lo, $hi) = @_;
    $lo //= 0;
    $hi //= 10;
    return $x < $lo ? $lo : $x > $hi ? $hi : $x;
}

1;
