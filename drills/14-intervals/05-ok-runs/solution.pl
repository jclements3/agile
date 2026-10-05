# ok-runs: Runs of OK flags
#
# Pattern:  one scan: when a run starts, walk to its end; count it and compare
# Why:      each position is visited once; replacing the best only on a
#           strictly longer run keeps the first of equal runs
# Time:     O(n)   Space: O(1)
# Edge:     no OK at all -> [0, 0, -1]; a run that ends the list; ties
# Perl:     a while loop with an index (for can not skip ahead)
use strict;
use warnings;

sub ok_runs {
    my ($flags) = @_;
    my ($count, $best, $start, $i) = (0, 0, -1, 0);
    while ($i < @$flags) {
        if (!$flags->[$i]) { $i++; next }
        my $j = $i;
        $j++ while $j < @$flags && $flags->[$j];
        $count++;
        ($best, $start) = ($j - $i, $i) if $j - $i > $best;
        $i = $j;
    }
    return [ $count, $best, $start ];
}

1;
