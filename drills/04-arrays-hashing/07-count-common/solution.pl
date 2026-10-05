# count-common: Count the common values
#
# Pattern:  a hash set of one list, a filtered set of the other
# Why:      membership in a hash is O(1), so each list is walked once; the
#           second hash counts each shared value once however often it repeats
# Time:     O(n + m)   Space: O(n)
# Edge:     duplicates on either side count once; an empty list -> 0
# Perl:     my %in = map { $_ => 1 } @$a ; scalar keys %both
use strict;
use warnings;

sub count_common {
    my ($a, $b) = @_;
    my %in = map { $_ => 1 } @$a;
    my %both;
    $both{$_} = 1 for grep { $in{$_} } @$b;
    return scalar keys %both;
}

1;
