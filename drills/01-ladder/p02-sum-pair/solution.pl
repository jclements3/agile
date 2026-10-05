# p02-sum-pair: Sum a pair
#
# Pattern:  parse and compute
# Why:      split ' ' gives the two fields; numeric context does the rest
# Time:     O(1)   Space: O(1)
# Edge:     negatives; a sum beyond 32 bits (fine in a 64-bit Perl)
# Perl:     split ' ' trims and splits on runs of blanks; avoid $a and $b,
#           they belong to sort
use strict;
use warnings;

my ($x, $y) = split ' ', <STDIN> // '';
print $x + $y, "\n";
