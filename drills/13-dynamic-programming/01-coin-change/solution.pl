# coin-change: Fewest coins (LeetCode 322)
#
# Pattern:  bottom-up DP: best[a] = 1 + min over coins c <= a of best[a - c]
# Why:      the last coin of an optimal answer for a leaves an optimal answer
#           for a - c, so trying every last coin finds the optimum
# Time:     O(amount * coins)   Space: O(amount)
# Edge:     amount 0 -> 0; unreachable sub-amounts stay undef; -1 at the end
# Perl:     undef as "impossible" instead of an infinity; @best = (0)
use strict;
use warnings;

sub coin_change {
    my ($coins, $amount) = @_;
    my @best = (0);
    for my $a (1 .. $amount) {
        for my $c (@$coins) {
            next if $c > $a || !defined $best[ $a - $c ];
            my $n = $best[ $a - $c ] + 1;
            $best[$a] = $n if !defined $best[$a] || $n < $best[$a];
        }
    }
    return $best[$amount] // -1;
}

1;
