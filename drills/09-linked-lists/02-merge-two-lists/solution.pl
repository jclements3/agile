# merge-two-lists: Merge two sorted lists (LeetCode 21)
#
# Pattern:  a dummy head node and a tail pointer; splice the smaller front
# Why:      the smallest remaining value is always at one of the two fronts;
#           when one list runs out the other is already sorted, so link it whole
# Time:     O(n + m)   Space: O(1)
# Edge:     either or both empty; equal values (take from a first: stable)
# Perl:     the dummy is a plain hash; $a/$b are sort's globals, so use $x/$y
use strict;
use warnings;

sub merge_two_lists {
    my ($x, $y) = @_;
    my $dummy = { next => undef };
    my $tail  = $dummy;
    while ($x && $y) {
        if ($x->{val} <= $y->{val}) { $tail->{next} = $x; $x = $x->{next} }
        else                        { $tail->{next} = $y; $y = $y->{next} }
        $tail = $tail->{next};
    }
    $tail->{next} = $x || $y;
    return $dummy->{next};
}

1;
