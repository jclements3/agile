# to-roman: To Roman numerals (LeetCode 12)
#
# Pattern:  greedy over a value table
# Why:      a table that includes the subtractive pairs, largest first: take the
#           largest value that fits as often as it fits
# Time:     O(1) (bounded by 3999)   Space: O(1)
# Edge:     4, 9, 40, 90, 400, 900; 3999
# Perl:     a flat list of pairs walked two at a time; x repeats a string
use strict;
use warnings;

sub to_roman {
    my ($n) = @_;
    my @t = (1000, 'M', 900, 'CM', 500, 'D', 400, 'CD', 100, 'C', 90, 'XC',
             50, 'L', 40, 'XL', 10, 'X', 9, 'IX', 5, 'V', 4, 'IV', 1, 'I');
    my $out = '';
    for (my $i = 0; $i < @t; $i += 2) {
        my $times = int($n / $t[$i]);
        $out .= $t[ $i + 1 ] x $times;
        $n -= $times * $t[$i];
    }
    return $out;
}

1;
