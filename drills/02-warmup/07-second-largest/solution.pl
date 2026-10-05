# second-largest: Second largest
#
# Pattern:  one pass tracking the top two distinct values
# Why:      a new maximum pushes the old one down; a value strictly between
#           them replaces the second
# Time:     O(n)   Space: O(1)
# Edge:     repeated maximum (skip equals); all negative (start from undef, not 0)
# Perl:     undef as "nothing yet"; !defined $second || $x > $second
use strict;
use warnings;

sub second_largest {
    my ($xs) = @_;
    my ($first, $second);
    for my $x (@$xs) {
        if (!defined $first || $x > $first) { ($first, $second) = ($x, $first) }
        elsif ($x < $first && (!defined $second || $x > $second)) { $second = $x }
    }
    return $second;
}

1;
