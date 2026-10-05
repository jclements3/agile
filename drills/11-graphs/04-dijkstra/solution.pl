# dijkstra: Shortest distances with weights (LeetCode 743, similar)
#
# Pattern:  Dijkstra: always settle the closest unsettled node, from a min-heap
# Why:      with non-negative weights no later path can beat the smallest
#           tentative distance, so a popped node's distance is final; stale
#           heap entries (larger than the known distance) are skipped
# Time:     O(E log V)   Space: O(V + E)
# Edge:     unreachable nodes never enter %dist; zero weights; cycles
# Perl:     no heap in core Perl: heap_push / heap_pop sift an array of
#           [dist, node] pairs; exists $dist{$n} for "seen"
use strict;
use warnings;

sub dijkstra {
    my ($graph, $source) = @_;
    my %dist = ($source => 0);
    my @heap = ([ 0, $source ]);
    while (@heap) {
        my ($d, $node) = @{ heap_pop(\@heap) };
        next if $d > $dist{$node};
        for my $edge (@{ $graph->{$node} || [] }) {
            my ($nbr, $w) = @$edge;
            my $nd = $d + $w;
            if (!exists $dist{$nbr} || $nd < $dist{$nbr}) {
                $dist{$nbr} = $nd;
                heap_push(\@heap, [ $nd, $nbr ]);
            }
        }
    }
    return \%dist;
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
