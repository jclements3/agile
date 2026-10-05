# top3-names: Top three names
#
# Pattern:  sort descending with an ascending tie-break
# Why:      score descending ($b before $a), then name ascending; take three
# Time:     O(n log n)   Space: O(n)
# Edge:     fewer than three entries (do not return undef padding)
# Perl:     swap $a/$b for descending; slice up to min(2, $#sorted)
use strict;
use warnings;

sub top3_names {
    my ($pairs) = @_;
    my @s = sort { $b->[1] <=> $a->[1] or $a->[0] cmp $b->[0] } @$pairs;
    my $last = $#s < 2 ? $#s : 2;
    return [ map { $_->[0] } @s[ 0 .. $last ] ];
}

1;
