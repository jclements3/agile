# fix-merge: Find the bug: merging touching intervals
#
# Pattern:  find the bug: < where <= was meant (a boundary-value bug, the most
#           common off-by-one family)
# Why:      inclusive intervals that share an end point overlap at that point
# Time:     O(n)   Space: O(n)
# Edge:     touching pairs and chains; a single interval
# Perl:     @$iv[1 .. $#$iv] is an array slice of the rest; copy each pair
use strict;
use warnings;

sub fix_merge {
    my ($iv) = @_;
    my @out = ([ @{ $iv->[0] } ]);
    for my $x (@$iv[ 1 .. $#$iv ]) {
        if ($x->[0] <= $out[-1][1]) { $out[-1][1] = $x->[1] if $x->[1] > $out[-1][1] }
        else                        { push @out, [@$x] }
    }
    return \@out;
}

1;
