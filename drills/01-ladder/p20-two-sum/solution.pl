# p20-two-sum: Two sum, stdin to stdout (LeetCode 1)
#
# Pattern:  one pass with a hash from value to its earliest index
# Why:      at index j the partner needed is t - x[j]; the first j that finds
#           its partner is the smallest j, and the stored index is the
#           earliest i for it
# Time:     O(n)   Space: O(n)
# Edge:     equal halves (look up before storing); duplicates keep the
#           earliest index (//= stores only once); no pair -> none
# Perl:     exists, not truth: index 0 is false
use strict;
use warnings;

chomp(my @lines = <STDIN>);
my $t = $lines[0];
my @x = split ' ', $lines[1];
my %first;
for my $j (0 .. $#x) {
    my $want = $t - $x[$j];
    if (exists $first{$want}) { print "$first{$want} $j\n"; exit 0 }
    $first{ $x[$j] } //= $j;
}
print "none\n";
