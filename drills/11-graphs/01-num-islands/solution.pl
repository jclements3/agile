# num-islands: Count the islands (LeetCode 200)
#
# Pattern:  scan every cell; each unseen land cell starts a new island, and a
#           flood fill marks all the land joined to it
# Why:      the fill visits a whole island once, so each island is counted
#           exactly when its first cell is met
# Time:     O(R*C)   Space: O(R*C) for the seen marks and the stack
# Edge:     empty grid; diagonal neighbours; one island filling the grid
# Perl:     an explicit stack instead of recursion (deep recursion warns);
#           substr($row, $c, 1) reads a cell; "$r,$c" keys a seen hash
use strict;
use warnings;

sub num_islands {
    my ($grid) = @_;
    my $rows = @$grid;
    return 0 unless $rows;
    my $cols = length $grid->[0];
    my ($count, %seen) = (0);
    for my $r0 (0 .. $rows - 1) {
        for my $c0 (0 .. $cols - 1) {
            next if substr($grid->[$r0], $c0, 1) ne '1' || $seen{"$r0,$c0"}++;
            $count++;
            my @stack = ([ $r0, $c0 ]);
            while (my $cell = pop @stack) {
                my ($r, $c) = @$cell;
                for my $d ([ 1, 0 ], [ -1, 0 ], [ 0, 1 ], [ 0, -1 ]) {
                    my ($nr, $nc) = ($r + $d->[0], $c + $d->[1]);
                    next if $nr < 0 || $nc < 0 || $nr >= $rows || $nc >= $cols;
                    next if substr($grid->[$nr], $nc, 1) ne '1' || $seen{"$nr,$nc"}++;
                    push @stack, [ $nr, $nc ];
                }
            }
        }
    }
    return $count;
}

1;
