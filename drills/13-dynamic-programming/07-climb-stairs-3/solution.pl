# climb-stairs-3: Stairs, 1 to 3 steps at a time (LeetCode 70, similar)
#
# Pattern:  state ways(n); recurrence ways(n-1) + ways(n-2) + ways(n-3);
#           base ways(0) = 1, negatives 0
# Why:      the first move is 1, 2 or 3 stairs, and the rest is a smaller
#           instance of the same problem
# Time:     O(n)   Space: O(n)
# Edge:     n = 0 is one way; n = 30 shows why plain recursion is too slow
# Perl:     a hash memo inside a closure (core Memoize also works:
#           use Memoize; memoize('ways'))
use strict;
use warnings;

sub climb3 {
    my ($n) = @_;
    my %memo;
    my $ways;
    $ways = sub {
        my ($k) = @_;
        return 0 if $k < 0;
        return 1 if $k == 0;
        return $memo{$k} //= $ways->($k - 1) + $ways->($k - 2) + $ways->($k - 3);
    };
    my $r = $ways->($n);
    undef $ways;
    return $r;
}

1;
