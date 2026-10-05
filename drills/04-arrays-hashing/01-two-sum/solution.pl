# two-sum: Two sum (LeetCode 1)
#
# Pattern:  hash map, one pass: value -> index of its first sighting
# Why:      the partner x needs is target - x; if it was seen earlier the pair
#           is complete the moment its second half arrives, so the first hit
#           has the smallest j
# Time:     O(n)   Space: O(n)
# Edge:     equal halves (5 + 5): look up before storing; no pair -> []
# Perl:     exists $seen{$k} (index 0 is false); //= keeps the first index
use strict;
use warnings;

sub two_sum {
    my ($nums, $target) = @_;
    my %seen;
    for my $j (0 .. $#$nums) {
        my $want = $target - $nums->[$j];
        return [ $seen{$want}, $j ] if exists $seen{$want};
        $seen{ $nums->[$j] } //= $j;
    }
    return [];
}

1;
