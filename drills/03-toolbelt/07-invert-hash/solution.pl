# invert-hash: Invert a hash
#
# Pattern:  hash swap
# Why:      the hash in list context is key, value, key, value; reversed it is
#           value, key, ... -- exactly the inverted pairs
# Time:     O(n)   Space: O(n)
# Edge:     duplicate values would collide: ask (here they are unique)
# Perl:     { reverse %$h }
use strict;
use warnings;

sub invert {
    my ($h) = @_;
    return { reverse %$h };
}

1;
