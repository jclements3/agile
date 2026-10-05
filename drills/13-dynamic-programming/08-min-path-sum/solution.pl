# min-path-sum: Cheapest path down and right (LeetCode 64)
#
# Pattern:  best(r, c) = grid[r][c] + min(best(r-1, c), best(r, c-1))
# Why:      the last step into a cell comes from above or from the left;
#           filling row by row means both are known when needed
# Time:     O(R*C)   Space: O(C), one row reused
# Edge:     one row, one column, one cell
# Perl:     the first row is a running sum; undef for "no cell to the left"
use strict;
use warnings;

sub min_path_sum {
    my ($grid) = @_;
    my @best;
    for my $r (0 .. $#$grid) {
        for my $c (0 .. $#{ $grid->[$r] }) {
            my $up   = $r > 0 ? $best[$c]     : undef;
            my $left = $c > 0 ? $best[ $c - 1 ] : undef;
            my $from = !defined $up ? $left : !defined $left ? $up : $up < $left ? $up : $left;
            $best[$c] = $grid->[$r][$c] + ($from // 0);
        }
    }
    return $best[-1];
}

1;
