# insert-interval: Insert an interval (LeetCode 57)
#
# Pattern:  one pass in three phases: copy intervals ending before the new
#           one, absorb every interval that overlaps it, copy the rest
# Why:      the input is sorted and disjoint, so the overlapping ones form one
#           contiguous run
# Time:     O(n)   Space: O(n)
# Edge:     empty list; new interval first, last, or swallowing several
# Perl:     a while loop with an index; @$x[$i .. $#$x] copies the tail
use strict;
use warnings;

sub insert_interval {
    my ($intervals, $new) = @_;
    my ($s, $e) = @$new;
    my ($i, @out) = (0);
    push @out, [ @{ $intervals->[ $i++ ] } ] while $i < @$intervals && $intervals->[$i][1] < $s;
    while ($i < @$intervals && $intervals->[$i][0] <= $e) {
        $s = $intervals->[$i][0] if $intervals->[$i][0] < $s;
        $e = $intervals->[$i][1] if $intervals->[$i][1] > $e;
        $i++;
    }
    push @out, [ $s, $e ], map { [@$_] } @$intervals[ $i .. $#$intervals ];
    return \@out;
}

1;
