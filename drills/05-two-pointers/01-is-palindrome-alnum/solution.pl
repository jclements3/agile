# is-palindrome-alnum: Palindrome, letters and digits only (LeetCode 125)
#
# Pattern:  two pointers closing in from both ends, skipping what does not count
# Why:      a palindrome matches its mirror position; skipping the non-alnum
#           characters on each side compares exactly the cleaned string
# Time:     O(n)   Space: O(1)
# Edge:     empty or all-symbol strings are palindromes; digits count
# Perl:     substr($s, $i, 1) =~ /[[:alnum:]]/ ; lc for case folding
use strict;
use warnings;

sub is_palindrome_alnum {
    my ($s) = @_;
    my ($i, $j) = (0, length($s) - 1);
    while ($i < $j) {
        $i++ while $i < $j && substr($s, $i, 1) !~ /[[:alnum:]]/;
        $j-- while $i < $j && substr($s, $j, 1) !~ /[[:alnum:]]/;
        return 0 if lc substr($s, $i, 1) ne lc substr($s, $j, 1);
        $i++;
        $j--;
    }
    return 1;
}

1;
