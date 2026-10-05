# kth-largest: The kth largest value (LeetCode 215)
#
# Pattern:  a min-heap holding the k largest values seen so far
# Why:      its top is the smallest of the k largest: the answer; a new value
#           bigger than the top replaces it
# Time:     O(n log k)   Space: O(k)
# Edge:     duplicates count separately; k = n gives the minimum
# Perl:     heap_push / heap_pop on a plain array (index 0 = smallest)
use strict;
use warnings;

sub kth_largest {
    my ($nums, $k) = @_;
    my @heap;
    for my $x (@$nums) {
        if (@heap < $k)       { heap_push(\@heap, $x) }
        elsif ($x > $heap[0]) { heap_pop(\@heap); heap_push(\@heap, $x) }
    }
    return $heap[0];
}

sub heap_push {
    my ($h, $x) = @_;
    push @$h, $x;
    my $i = $#$h;
    while ($i > 0) {
        my $p = int(($i - 1) / 2);
        last if $h->[$p] <= $h->[$i];
        @$h[ $p, $i ] = @$h[ $i, $p ];
        $i = $p;
    }
}

sub heap_pop {
    my ($h) = @_;
    my $top = $h->[0];
    my $last = pop @$h;
    if (@$h) {
        $h->[0] = $last;
        my $i = 0;
        while (1) {
            my ($l, $r, $m) = (2 * $i + 1, 2 * $i + 2, $i);
            $m = $l if $l < @$h && $h->[$l] < $h->[$m];
            $m = $r if $r < @$h && $h->[$r] < $h->[$m];
            last if $m == $i;
            @$h[ $m, $i ] = @$h[ $i, $m ];
            $i = $m;
        }
    }
    return $top;
}

1;
