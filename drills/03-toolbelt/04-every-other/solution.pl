# every-other: Every other element
#
# Pattern:  stepped index list
# Why:      the even indices, then a slice
# Time:     O(n)   Space: O(n)
# Edge:     empty list ($#$xs is -1, so no indices)
# Perl:     grep { $_ % 2 == 0 } 0 .. $#$xs, then the slice @$xs[...]
use strict;
use warnings;

sub every_other {
    my ($xs) = @_;
    return [ @$xs[ grep { $_ % 2 == 0 } 0 .. $#$xs ] ];
}

1;
