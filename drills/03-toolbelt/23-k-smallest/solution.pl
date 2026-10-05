# k-smallest: The k smallest
#
# Pattern:  sort and slice (or a heap)
# Why:      sorting puts the k smallest first; say that a size-k max-heap is
#           O(n log k) when n is huge and k small
# Time:     O(n log n)   Space: O(n)
# Edge:     fewer than k values; k = 0; numeric (not string) order
# Perl:     sort { $a <=> $b }; a slice capped at the last index
use strict;
use warnings;

sub k_smallest {
    my ($xs, $k) = @_;
    my @s = sort { $a <=> $b } @$xs;
    my $last = $k - 1 < $#s ? $k - 1 : $#s;
    return [ @s[ 0 .. $last ] ];
}

1;
