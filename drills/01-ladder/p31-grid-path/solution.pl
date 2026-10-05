# p31-grid-path: Shortest path in a grid (LeetCode 1091, similar)
#
# Pattern:  breadth-first search from the start
# Why:      BFS reaches cells in order of distance, so the first time the
#           goal comes off the queue its distance is the minimum
# Time:     O(R*C)   Space: O(R*C)
# Edge:     start or goal is a wall; 1x1; no path. Mark a cell seen when it is
#           enqueued, not when it is dequeued, or cells queue twice
# Perl:     a flat index $r * $C + $c keys the distance hash; shift @queue
use strict;
use warnings;

chomp(my @lines = <STDIN>);
my ($R, $C) = split ' ', shift @lines;
my @g = map { [ split //, $lines[$_] ] } 0 .. $R - 1;
print bfs(), "\n";

sub bfs {
    return -1 if $g[0][0] eq '#' || $g[$R - 1][$C - 1] eq '#';
    my %dist = (0 => 0);
    my @queue = ([0, 0]);
    while (@queue) {
        my ($r, $c) = @{ shift @queue };
        my $d = $dist{ $r * $C + $c };
        return $d if $r == $R - 1 && $c == $C - 1;
        for my $step ([1, 0], [-1, 0], [0, 1], [0, -1]) {
            my ($nr, $nc) = ($r + $step->[0], $c + $step->[1]);
            next if $nr < 0 || $nc < 0 || $nr >= $R || $nc >= $C;
            next if $g[$nr][$nc] eq '#' || exists $dist{ $nr * $C + $nc };
            $dist{ $nr * $C + $nc } = $d + 1;
            push @queue, [$nr, $nc];
        }
    }
    return -1;
}
