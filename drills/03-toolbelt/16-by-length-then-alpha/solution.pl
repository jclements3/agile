# by-length-then-alpha: Sort by length, then alphabetically
#
# Pattern:  two-level sort key
# Why:      compare lengths; only when they tie, compare the words
# Time:     O(n log n)   Space: O(n)
# Edge:     ties on length
# Perl:     sort { length($a) <=> length($b) or $a cmp $b } -- `or` chains the keys
use strict;
use warnings;

sub by_len_then_alpha {
    my ($words) = @_;
    return [ sort { length($a) <=> length($b) or $a cmp $b } @$words ];
}

1;
