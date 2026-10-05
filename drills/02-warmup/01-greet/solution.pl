# greet: Greet
#
# Pattern:  string interpolation
# Why:      a double-quoted string interpolates the scalar in place
# Time:     O(n)   Space: O(n)
# Edge:     the empty name gives "Hello, !"
# Perl:     "Hello, $name!" -- the ! is not part of the variable name
use strict;
use warnings;

sub greet {
    my ($name) = @_;
    return "Hello, $name!";
}

1;
