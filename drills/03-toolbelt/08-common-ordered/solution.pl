# common-ordered: Common elements, in order
#
# Pattern:  hash for membership, hash for seen
# Why:      a lookup hash makes "is it in b" O(1); a second hash drops repeats
# Time:     O(a + b)   Space: O(a + b)
# Edge:     duplicates in a; an empty b
# Perl:     my %in = map { $_ => 1 } @$b; grep { $in{$_} && !$seen{$_}++ }
use strict;
use warnings;

sub common_ordered {
    my ($x, $y) = @_;
    my %in = map { $_ => 1 } @$y;
    my %seen;
    return [ grep { $in{$_} && !$seen{$_}++ } @$x ];
}

1;
