# p50-score-counts: Score counts from a tab-separated table
#
# Pattern:  count in a hash, print in a fixed list order
# Why:      the order and the zero rows come from the list of scores, not from
#           the data, so absent scores still print 0
# Time:     O(rows)   Space: O(1)
# Edge:     the space inside "in place" (split on tab, not whitespace); a
#           header-only file; \r from files saved on Windows
# Perl:     <STDIN> in void context skips the header; s/\r?\n\z// strips both
#           line ends; $c{$s} // 0
use strict;
use warnings;

my @SCORES = ('in place', 'partial', 'missing', 'unknown');
<STDIN>;
my %c;
while (my $line = <STDIN>) {
    $line =~ s/\r?\n\z//;
    next if $line !~ /\S/;
    my @f = split /\t/, $line;
    $c{ $f[3] }++ if defined $f[3];
}
my $total = 0;
for my $s (@SCORES) { printf "%s: %d\n", $s, $c{$s} // 0; $total += $c{$s} // 0 }
print "total: $total\n";
