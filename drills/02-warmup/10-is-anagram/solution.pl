# is-anagram: Anagram check (LeetCode 242, similar)
#
# Pattern:  canonical form
# Why:      two anagrams sort to the same letters; compare the sorted forms
# Time:     O(n log n)   Space: O(n)
# Edge:     case and spaces removed first; different counts of a letter
# Perl:     join '', sort split //, lc $s; tr/ //d deletes spaces
use strict;
use warnings;

sub is_anagram {
    my ($x, $y) = @_;
    return _canon($x) eq _canon($y) ? 1 : 0;
}

sub _canon {
    my ($s) = @_;
    ($s = lc $s) =~ tr/ //d;
    return join '', sort split //, $s;
}

1;
