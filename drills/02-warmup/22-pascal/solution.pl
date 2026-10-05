# pascal: Pascal's triangle (LeetCode 118)
#
# Pattern:  build each row from the previous one
# Why:      the inner values of a row are the sums of adjacent pairs of the row above
# Time:     O(n^2)   Space: O(n^2)
# Edge:     n = 0 gives no rows; row 1 is just [1]
# Perl:     map over 1 .. $#prev for the pairwise sums; $rows[-1] is the last row
use strict;
use warnings;

sub pascal {
    my ($n) = @_;
    my @rows;
    for my $r (1 .. $n) {
        if (!@rows) { push @rows, [1]; next }
        my $prev = $rows[-1];
        push @rows, [ 1, (map { $prev->[ $_ - 1 ] + $prev->[$_] } 1 .. $#$prev), 1 ];
    }
    return \@rows;
}

1;
