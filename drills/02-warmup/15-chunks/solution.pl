# chunks: Chunk a list
#
# Pattern:  stepped slices
# Why:      start indices 0, k, 2k, ...; each slice ends at the smaller of
#           start + k - 1 and the last index
# Time:     O(n)   Space: O(n)
# Edge:     a short last piece; an empty list; k larger than the list
# Perl:     an array slice @$xs[$i .. $j]; the min written inline
use strict;
use warnings;

sub chunks {
    my ($xs, $k) = @_;
    my @out;
    for (my $i = 0; $i < @$xs; $i += $k) {
        my $end = $i + $k - 1 < $#$xs ? $i + $k - 1 : $#$xs;
        push @out, [ @$xs[ $i .. $end ] ];
    }
    return \@out;
}

1;
