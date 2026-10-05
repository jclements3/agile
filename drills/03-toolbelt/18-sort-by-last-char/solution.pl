# sort-by-last-char: Sort by last character
#
# Pattern:  stable sort on a derived key
# Why:      compare only the key; a stable sort leaves equal keys in input order
# Time:     O(n log n)   Space: O(n)
# Edge:     ties must keep input order
# Perl:     use sort 'stable' guarantees it (Perl's merge sort is stable, the
#           pragma makes it a promise); substr($w, -1) is the last character
use strict;
use warnings;
use sort 'stable';

sub sort_by_last_char {
    my ($words) = @_;
    return [ sort { substr($a, -1) cmp substr($b, -1) } @$words ];
}

1;
