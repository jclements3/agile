# p32-coin-change: Fewest coins (LeetCode 322)
#
# Pattern:  bottom-up dynamic programming over the amount
# Why:      the best for amount a is one coin c plus the best for a - c; every
#           smaller amount is already final when a is computed
# Time:     O(amount * coins)   Space: O(amount)
# Edge:     amount 0; unreachable amounts (stay undef); one coin value.
#           Greedy fails (1 5 6 for 10), which is why this is a table
# Perl:     undef as "impossible" instead of an infinity constant
use strict;
use warnings;

chomp(my @lines = <STDIN>);
my @coins = split ' ', $lines[0];
my $amount = $lines[1];
my @best = (0);
for my $amt (1 .. $amount) {
    for my $c (@coins) {
        next if $c > $amt || !defined $best[$amt - $c];
        $best[$amt] = $best[$amt - $c] + 1 if !defined $best[$amt] || $best[$amt - $c] + 1 < $best[$amt];
    }
}
print $best[$amount] // -1, "\n";
