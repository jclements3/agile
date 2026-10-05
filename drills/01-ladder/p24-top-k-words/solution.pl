# p24-top-k-words: Top k words (LeetCode 692)
#
# Pattern:  hash counting across all lines, then a two-level sort
# Why:      count descending ranks the words; word ascending is the tie-break;
#           the first k of that order are the answer
# Time:     O(N + d log d) for N words, d distinct   Space: O(d)
# Edge:     words split across lines; ties at the k-th place; reversing a
#           whole sort would break the alphabetical tie-break
# Perl:     sort { $c{$b} <=> $c{$a} or $a cmp $b }; a slice takes the first k
use strict;
use warnings;

chomp(my $k = <STDIN> // 0);
my %c;
while (my $line = <STDIN>) { $c{$_}++ for split ' ', $line }
my @top = sort { $c{$b} <=> $c{$a} or $a cmp $b } keys %c;
print "$_ $c{$_}\n" for @top[0 .. $k - 1];
