# sign: Sign
#
# Pattern:  conditionals
# Why:      three cases, tested in order
# Time:     O(1)   Space: O(1)
# Edge:     zero; decimals between -1 and 1
# Perl:     the spaceship operator does it in one: $x <=> 0
use strict;
use warnings;

sub sign {
    my ($x) = @_;
    return -1 if $x < 0;
    return 1 if $x > 0;
    return 0;
}

1;
