# p30-merge-intervals: Merge intervals (LeetCode 56)
#
# Pattern:  sort by start, then sweep, extending the last merged interval
# Why:      after the sort an interval can only overlap the one merged most
#           recently; if it starts at or before that end, take the larger end
# Time:     O(n log n) for the sort, O(n) for the sweep   Space: O(n)
# Edge:     touching intervals (<=, not <); one inside another; unsorted input
# Perl:     sort { $a->[0] <=> $b->[0] } on array refs; $out[-1] is the last
use strict;
use warnings;

chomp(my @lines = <STDIN>);
my $n = shift @lines;
my @iv = sort { $a->[0] <=> $b->[0] } map { [ split ' ' ] } @lines[0 .. $n - 1];
my @out;
for my $cur (@iv) {
    if (@out && $cur->[0] <= $out[-1][1]) {
        $out[-1][1] = $cur->[1] if $cur->[1] > $out[-1][1];
    }
    else { push @out, [@$cur] }
}
print "$_->[0] $_->[1]\n" for @out;
