# reverse-digits: Reverse the digits (LeetCode 7, similar)
#
# Pattern:  string and number conversion
# Why:      reverse the digits of |n| as text, convert back, restore the sign
# Time:     O(d)   Space: O(d)
# Edge:     negative numbers; trailing zeros vanish when the text becomes a number
# Perl:     scalar reverse reverses a string (plain reverse in list context does not);
#           0 + "021" is 21
use strict;
use warnings;

sub reverse_digits {
    my ($n) = @_;
    my $r = 0 + scalar reverse abs $n;
    return $n < 0 ? -$r : $r;
}

1;
