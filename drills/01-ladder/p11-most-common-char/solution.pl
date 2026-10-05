# p11-most-common-char: Most common character
#
# Pattern:  hash counting, then a sort with a two-level key
# Why:      count descending puts the winners first; letter ascending breaks
#           the tie the statement defines
# Time:     O(n) to count, O(k log k) to sort k <= 26 keys   Space: O(k)
# Edge:     every letter ties; a single distinct letter
# Perl:     split //, $s gives the characters; sort { $c{$b} <=> $c{$a} or
#           $a cmp $b } is the descending-then-ascending idiom
use strict;
use warnings;

chomp(my $s = <STDIN> // '');
my %c;
$c{$_}++ for split //, $s;
my ($best) = sort { $c{$b} <=> $c{$a} or $a cmp $b } keys %c;
print "$best $c{$best}\n";
