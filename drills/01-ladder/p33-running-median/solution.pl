# p33-running-median: Running median (LeetCode 295)
#
# Pattern:  two heaps: a max-heap for the lower half, a min-heap for the upper
# Why:      keeping the halves balanced (sizes differ by at most one, lower
#           never smaller) puts the median at the top(s)
# Time:     O(log n) per arrival   Space: O(n)
# Edge:     one value; duplicates; negatives; the one-decimal format
# Perl:     no heap in core Perl: heap_push / heap_pop sift an array; the
#           max-heap stores negated values; printf "%.1f"
use strict;
use warnings;

chomp(my @lines = <STDIN>);
my $n = shift @lines;
my (@lo, @hi);                                   # @lo holds negated values
for my $x (@lines[0 .. $n - 1]) {
    if (!@lo || $x <= -$lo[0]) { heap_push(\@lo, -$x) } else { heap_push(\@hi, $x) }
    if (@lo > @hi + 1) { heap_push(\@hi, -heap_pop(\@lo)) }
    elsif (@hi > @lo)  { heap_push(\@lo, -heap_pop(\@hi)) }
    printf "%.1f\n", @lo > @hi ? -$lo[0] : (-$lo[0] + $hi[0]) / 2;
}

sub heap_push {                                  # min-heap: sift up
    my ($h, $v) = @_;
    push @$h, $v;
    my $i = $#$h;
    while ($i > 0) {
        my $p = int(($i - 1) / 2);
        last if $h->[$p] <= $h->[$i];
        @$h[$p, $i] = @$h[$i, $p];
        $i = $p;
    }
}

sub heap_pop {                                   # min-heap: take the root, sift down
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
            @$h[$m, $i] = @$h[$i, $m];
            $i = $m;
        }
    }
    return $top;
}
