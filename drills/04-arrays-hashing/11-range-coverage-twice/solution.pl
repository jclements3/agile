# range-coverage-twice: Covered at least twice
#
# Pattern:  difference array: +1 at a range's start, -1 just after its end
# Why:      the running sum of the difference array at item i is the number of
#           ranges covering i, so one pass counts every item
# Time:     O(n + q)   Space: O(n)
# Edge:     a range ending at n writes to index n + 1 (allocate n + 2)
# Perl:     my @d = (0) x ($n + 2) ; $twice++ if ($run += $d[$i]) >= 2
use strict;
use warnings;

sub covered_twice {
    my ($n, $ranges) = @_;
    my @d = (0) x ($n + 2);
    for my $r (@$ranges) {
        $d[ $r->[0] ]++;
        $d[ $r->[1] + 1 ]--;
    }
    my ($run, $twice) = (0, 0);
    for my $i (1 .. $n) {
        $run += $d[$i];
        $twice++ if $run >= 2;
    }
    return $twice;
}

1;
