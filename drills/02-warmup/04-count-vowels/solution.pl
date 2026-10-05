# count-vowels: Count vowels
#
# Pattern:  character counting
# Why:      the transliteration operator counts the characters it matches
# Time:     O(n)   Space: O(1)
# Edge:     the empty string; upper case
# Perl:     tr/aeiouAEIOU// returns the count without changing the string
use strict;
use warnings;

sub count_vowels {
    my ($s) = @_;
    return ($s =~ tr/aeiouAEIOU//);
}

1;
