# k-closest-points: The k points nearest the origin (LeetCode 973)
#
# Pattern:  a max-heap of the k closest so far, keyed by squared distance
# Why:      the top is the farthest of the current k; a nearer point evicts it
# Time:     O(n log k)   Space: O(k)
# Edge:     k = n returns everything; the origin itself has distance 0
# Perl:     store [-dist, x, y] so the min-heap helpers act as a max-heap
use strict;
use warnings;

sub k_closest {
    my ($points, $k) = @_;
    my @heap;
    for my $p (@$points) {
        my $key = -($p->[0] ** 2 + $p->[1] ** 2);
        if (@heap < $k)            { heap_push(\@heap, [ $key, @$p ]) }
        elsif ($key > $heap[0][0]) { heap_pop(\@heap); heap_push(\@heap, [ $key, @$p ]) }
    }
    return [ map { [ $_->[1], $_->[2] ] } @heap ];
}

sub heap_push {
    my ($h, $x) = @_;
    push @$h, $x;
    my $i = $#$h;
    while ($i > 0) {
        my $p = int(($i - 1) / 2);
        last if $h->[$p][0] <= $h->[$i][0];
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
            $m = $l if $l < @$h && $h->[$l][0] < $h->[$m][0];
            $m = $r if $r < @$h && $h->[$r][0] < $h->[$m][0];
            last if $m == $i;
            @$h[ $m, $i ] = @$h[ $i, $m ];
            $i = $m;
        }
    }
    return $top;
}

1;
