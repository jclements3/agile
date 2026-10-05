# longest-consecutive: Longest consecutive run (LeetCode 128)
#
# Pattern:  hash set; start counting only at a run's first value
# Why:      x starts a run when x - 1 is absent; walking forward from starts
#           only visits each value once overall, so the total work is O(n)
# Time:     O(n)   Space: O(n)
# Edge:     empty list -> 0; duplicates collapse in the set
# Perl:     my %in = map { $_ => 1 } @$nums ; exists $in{$x - 1}
use strict;
use warnings;

sub longest_consecutive {
    my ($nums) = @_;
    my %in = map { $_ => 1 } @$nums;
    my $best = 0;
    for my $x (keys %in) {
        next if exists $in{ $x - 1 };
        my $len = 1;
        $len++ while exists $in{ $x + $len };
        $best = $len if $len > $best;
    }
    return $best;
}

1;
