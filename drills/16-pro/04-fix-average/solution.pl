# fix-average: Find the bug: an average
#
# Pattern:  find the bug: an unguarded division (and sum() of nothing is undef)
# Why:      @$xs in numeric context is 0 for an empty list: "Illegal division
#           by zero"; the fix is a stated contract for the empty case
# Time:     O(n)   Space: O(1)
# Edge:     empty -> 0 by contract; one value; negatives
# Perl:     sum(0, @xs) never returns undef; a ternary on the count
use strict;
use warnings;
use List::Util qw(sum);

sub fix_average {
    my ($xs) = @_;
    return @$xs ? sum(0, @$xs) / @$xs : 0;
}

1;
