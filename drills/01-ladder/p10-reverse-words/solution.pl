# p10-reverse-words: Reverse the words
#
# Pattern:  split, reverse, join
# Why:      split ' ' already drops leading blanks and collapses runs, so the
#           word list is clean before it is reversed
# Time:     O(length)   Space: O(length)
# Edge:     leading and trailing blanks; a single word
# Perl:     split ' ' (a one-space string) is the awk-style split; split / /
#           would keep empty fields
use strict;
use warnings;

my $line = <STDIN> // '';
print join(' ', reverse split ' ', $line), "\n";
