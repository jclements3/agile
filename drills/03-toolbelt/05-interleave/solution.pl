# interleave: Interleave two lists
#
# Pattern:  zip by index
# Why:      one index walks both lists; each step emits a pair
# Time:     O(n)   Space: O(n)
# Edge:     empty lists; ask what to do if the lengths differ
# Perl:     map returning two values per index flattens into one list
use strict;
use warnings;

sub interleave {
    my ($x, $y) = @_;
    return [ map { ($x->[$_], $y->[$_]) } 0 .. $#$x ];
}

1;
