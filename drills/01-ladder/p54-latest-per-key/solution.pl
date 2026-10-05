# p54-latest-per-key: Latest line per key
#
# Pattern:  keep the best record per key in a hash, replace on a better one
# Why:      one pass decides every key; ISO dates compare as strings
# Time:     O(n + k log k)   Space: O(k)
# Edge:     equal dates: the later line wins, so compare with ge, not gt
# Perl:     a hash of [date, line] pairs; sort keys for the output order
use strict;
use warnings;

my %best;
while (my $line = <STDIN>) {
    chomp $line;
    my ($date, $id) = split ' ', $line;
    next unless defined $id;
    $best{$id} = [ $date, $line ] if !exists $best{$id} || $date ge $best{$id}[0];
}
print "$best{$_}[1]\n" for sort keys %best;
