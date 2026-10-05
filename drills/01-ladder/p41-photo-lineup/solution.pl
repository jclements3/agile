# p41-photo-lineup: Two-row lineup
#
# Pattern:  sort both rows, then compare column by column
# Why:      exchange argument: if any arrangement works, swapping two columns
#           that are out of order in both rows keeps every column valid, so
#           the sorted-against-sorted pairing works whenever anything does
# Time:     O(n log n)   Space: O(n)
# Edge:     equal heights fail (strictly taller); n = 1; ask what to do when
#           the rows differ in size
# Perl:     sort { $a <=> $b }; grep over the indices finds a failing column
use strict;
use warnings;

chomp(my @lines = <STDIN>);
my @back  = sort { $a <=> $b } split ' ', $lines[0];
my @front = sort { $a <=> $b } split ' ', $lines[1];
if (@back == @front && !grep { $back[$_] <= $front[$_] } 0 .. $#back) {
    print "YES\n@back\n@front\n";
}
else { print "NO\n" }
