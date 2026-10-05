# p03-min-max-sum: Min, max, sum
#
# Pattern:  parse a count then a row; reduce three ways
# Why:      List::Util's min, max and sum each make one pass
# Time:     O(n)   Space: O(n)
# Edge:     n = 1; all negative (a hand-written max must not start at 0)
# Perl:     List::Util qw(min max sum); sum0 is newer than 5.10's List::Util
use strict;
use warnings;
use List::Util qw(min max sum);

chomp(my @lines = <STDIN>);
my @x = split ' ', $lines[1];
print join(' ', min(@x), max(@x), sum(@x)), "\n";
