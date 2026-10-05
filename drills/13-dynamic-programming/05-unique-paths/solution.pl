# unique-paths: Paths across a grid (LeetCode 62)
#
# Pattern:  grid DP: paths into a cell = paths from above + paths from the left
# Why:      the last move into a cell is either down or right, never both
# Time:     O(rows*cols)   Space: O(cols), one row reused
# Edge:     one row or one column -> 1
# Perl:     (1) x $cols makes the first row; $dp[$c] += $dp[$c - 1] in place
use strict;
use warnings;

sub unique_paths {
    my ($rows, $cols) = @_;
    my @dp = (1) x $cols;
    for (2 .. $rows) {
        $dp[$_] += $dp[ $_ - 1 ] for 1 .. $cols - 1;
    }
    return $dp[-1];
}

1;
