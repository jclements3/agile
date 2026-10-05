# permutations: All orderings (LeetCode 46)
#
# Pattern:  backtracking by swapping: position k takes each remaining value
# Why:      after fixing positions 0..k-1, every value in k..n-1 gets a turn
#           at k; swapping back restores the array for the next choice
# Time:     O(n * n!)   Space: O(n) recursion besides the output
# Edge:     empty input -> one empty ordering
# Perl:     a slice swap @a[$i, $k] = @a[$k, $i]; copy the input first so the
#           caller's array is untouched
use strict;
use warnings;

sub permutations {
    my ($nums) = @_;
    my @a = @$nums;
    my @out;
    my $go;
    $go = sub {
        my ($k) = @_;
        if ($k == @a) { push @out, [@a]; return }
        for my $i ($k .. $#a) {
            @a[ $k, $i ] = @a[ $i, $k ];
            $go->($k + 1);
            @a[ $k, $i ] = @a[ $i, $k ];
        }
    };
    $go->(0);
    undef $go;
    return \@out;
}

1;
