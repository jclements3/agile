# product-except-self: Product of the others (LeetCode 238)
#
# Pattern:  prefix products left to right, then suffix products right to left
# Why:      out[i] = (product of everything left of i) * (everything right of
#           i); the first pass stores the left part, the second multiplies in
#           the right part with a running product
# Time:     O(n)   Space: O(1) besides the output
# Edge:     zeros need no special case because nothing is divided
# Perl:     a C-style downward loop: for (my $i = $#a; $i >= 0; $i--)
use strict;
use warnings;

sub product_except_self {
    my ($nums) = @_;
    my @out;
    my $left = 1;
    for my $i (0 .. $#$nums) {
        $out[$i] = $left;
        $left *= $nums->[$i];
    }
    my $right = 1;
    for (my $i = $#$nums; $i >= 0; $i--) {
        $out[$i] *= $right;
        $right *= $nums->[$i];
    }
    return \@out;
}

1;
