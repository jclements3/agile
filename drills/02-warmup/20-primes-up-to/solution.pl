# primes-up-to: Sieve of Eratosthenes (LeetCode 204, similar)
#
# Pattern:  sieve
# Why:      every composite c has a prime factor p <= sqrt(c), so it is crossed
#           off by then; multiples below p * p were crossed off by smaller primes
# Time:     O(n log log n)   Space: O(n)
# Edge:     n < 2 gives no primes; a perfect square of a prime (25)
# Perl:     an array of flags; grep { !$composite[$_] } 2 .. $n
use strict;
use warnings;

sub primes_up_to {
    my ($n) = @_;
    my @composite;
    for (my $p = 2; $p * $p <= $n; $p++) {
        next if $composite[$p];
        for (my $m = $p * $p; $m <= $n; $m += $p) { $composite[$m] = 1 }
    }
    return [ grep { !$composite[$_] } 2 .. $n ];
}

1;
