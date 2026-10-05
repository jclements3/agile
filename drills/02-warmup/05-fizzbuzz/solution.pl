# fizzbuzz: FizzBuzz as data (LeetCode 412)
#
# Pattern:  loop building a list
# Why:      test the combined case first, or build the word from both parts
# Time:     O(n)   Space: O(n)
# Edge:     n = 0 gives an empty list
# Perl:     map over 1 .. $n; ($w || $i) falls back to the number
use strict;
use warnings;

sub fizzbuzz {
    my ($n) = @_;
    return [ map {
        my $w = ($_ % 3 ? '' : 'Fizz') . ($_ % 5 ? '' : 'Buzz');
        $w || "$_";
    } 1 .. $n ];
}

1;
