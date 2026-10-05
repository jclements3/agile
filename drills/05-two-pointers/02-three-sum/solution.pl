# three-sum: Three values summing to zero (LeetCode 15)
#
# Pattern:  sort; fix the smallest value; two pointers find the other two
# Why:      in sorted data a sum too small moves lo up and a sum too big moves
#           hi down, so each fixed value costs one O(n) sweep
# Time:     O(n^2)   Space: O(1) besides the output and the sort
# Edge:     skip equal fixed values and equal lo values to avoid repeats
# Perl:     sort { $a <=> $b } (numeric!); a C-style while with two indices
use strict;
use warnings;

sub three_sum {
    my ($nums) = @_;
    my @x = sort { $a <=> $b } @$nums;
    my @out;
    for my $i (0 .. $#x - 2) {
        next if $i > 0 && $x[$i] == $x[ $i - 1 ];
        my ($lo, $hi) = ($i + 1, $#x);
        while ($lo < $hi) {
            my $sum = $x[$i] + $x[$lo] + $x[$hi];
            if    ($sum < 0) { $lo++ }
            elsif ($sum > 0) { $hi-- }
            else {
                push @out, [ $x[$i], $x[$lo], $x[$hi] ];
                $lo++;
                $lo++ while $lo < $hi && $x[$lo] == $x[ $lo - 1 ];
            }
        }
    }
    return \@out;
}

1;
