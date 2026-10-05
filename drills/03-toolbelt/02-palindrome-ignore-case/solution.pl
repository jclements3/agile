# palindrome-ignore-case: Palindrome, ignoring case
#
# Pattern:  compare with the reverse
# Why:      lower-case once, then a palindrome equals its own reverse
# Time:     O(n)   Space: O(n)
# Edge:     the empty string and one character are palindromes
# Perl:     scalar reverse $s reverses a string; plain reverse in list context would not
use strict;
use warnings;

sub is_palindrome {
    my ($s) = @_;
    my $t = lc $s;
    return $t eq scalar reverse($t) ? 1 : 0;
}

1;
