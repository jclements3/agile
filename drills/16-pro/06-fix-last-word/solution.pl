# fix-last-word: Find the bug: the last word
#
# Pattern:  find the bug: an anchor that ignores trailing blanks and a
#           character class too narrow for real words
# Why:      /(\w+)$/ needs the word to touch the end and to be all word
#           characters; split ' ' drops leading blanks and splits on any run
# Time:     O(n)   Space: O(n)
# Edge:     trailing spaces and tabs; hyphens and punctuation inside a word
# Perl:     (split ' ', $s)[-1]: a list slice; split ' ' is the awk-style
#           special case
use strict;
use warnings;

sub fix_last_word {
    my ($s) = @_;
    return (split ' ', $s)[-1];
}

1;
