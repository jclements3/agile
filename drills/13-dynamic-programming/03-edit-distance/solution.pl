# edit-distance: Edit distance (LeetCode 72)
#
# Pattern:  dp[i][j] = edits to turn the first i chars of a into the first j of b
# Why:      matching last characters cost nothing (dp[i-1][j-1]); otherwise
#           the last edit is a delete, an insert or a replace: 1 + the min
# Time:     O(m*n)   Space: O(m*n) (two rows suffice)
# Edge:     either string empty: the other's length
# Perl:     substr($a, $i - 1, 1) reads a character; List::Util min
use strict;
use warnings;
use List::Util qw(min);

sub edit_distance {
    my ($x, $y) = @_;
    my ($m, $n) = (length $x, length $y);
    my @dp = map { [ ($_) x 1 ] } 0 .. $m;
    $dp[0][$_] = $_ for 0 .. $n;
    for my $i (1 .. $m) {
        for my $j (1 .. $n) {
            $dp[$i][$j] = substr($x, $i - 1, 1) eq substr($y, $j - 1, 1)
                ? $dp[ $i - 1 ][ $j - 1 ]
                : 1 + min($dp[ $i - 1 ][$j], $dp[$i][ $j - 1 ], $dp[ $i - 1 ][ $j - 1 ]);
        }
    }
    return $dp[$m][$n];
}

1;
