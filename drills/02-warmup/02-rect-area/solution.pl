# rect-area: Rectangle area
#
# Pattern:  arithmetic
# Why:      area is the product of the sides
# Time:     O(1)   Space: O(1)
# Edge:     zero and decimal sides work unchanged
# Perl:     Perl numbers are doubles when needed: 2.5 * 4 prints 10
use strict;
use warnings;

sub rect_area {
    my ($w, $h) = @_;
    return $w * $h;
}

1;
