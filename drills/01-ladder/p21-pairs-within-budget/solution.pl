# p21-pairs-within-budget: Pairs within budget
#
# Pattern:  sort, then two pointers closing in from both ends
# Why:      sorted ascending, if xs[lo] + xs[hi] fits then xs[lo] fits with
#           every index between lo and hi: count hi - lo at once, advance lo;
#           otherwise xs[hi] fits with nothing left, so retreat hi
# Time:     O(n log n)   Space: O(n)
# Edge:     negatives; every pair fits; none fits; n < 2
# Perl:     sort { $a <=> $b } is numeric (plain sort is string order)
use strict;
use warnings;

chomp(my @lines = <STDIN>);
my $t = $lines[0];
my @xs = sort { $a <=> $b } split ' ', $lines[1] // '';
my ($lo, $hi, $count) = (0, $#xs, 0);
while ($lo < $hi) {
    if ($xs[$lo] + $xs[$hi] <= $t) { $count += $hi - $lo; $lo++ }
    else { $hi-- }
}
print "$count\n";
