# find-median-stream: Running median (LeetCode 295)
#
# Pattern:  two heaps: a max-heap of the lower half, a min-heap of the upper
# Why:      each new value goes into the low heap, its largest moves up to
#           the high heap, and the high heap gives one back when it is the
#           bigger; the tops are then the middle values
# Time:     O(log n) per value   Space: O(n)
# Edge:     even counts average two tops; duplicates; negatives
# Perl:     one min-heap pair of helpers; the low half stores negated values
use strict;
use warnings;

sub running_median {
    my ($stream) = @_;
    my (@lo, @hi, @out);
    for my $x (@$stream) {
        heap_push(\@lo, -$x);
        heap_push(\@hi, -heap_pop(\@lo));
        heap_push(\@lo, -heap_pop(\@hi)) if @hi > @lo;
        push @out, @lo > @hi ? -$lo[0] : (-$lo[0] + $hi[0]) / 2;
    }
    return \@out;
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
