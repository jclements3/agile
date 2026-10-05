# merge-sum: Merge two hashes, summing values
#
# Pattern:  hash merge without mutation
# Why:      copy the first hash, then add each value of the second into the copy
# Time:     O(a + b)   Space: O(a + b)
# Edge:     empty inputs; a sum of zero still keeps the key
# Perl:     my %out = %$a copies (one level); += on a missing key starts from 0
#           (and warns nothing, because += treats undef as 0 silently)
use strict;
use warnings;

sub merge_sum {
    my ($x, $y) = @_;
    my %out = %$x;
    $out{$_} += $y->{$_} for keys %$y;
    return \%out;
}

1;
