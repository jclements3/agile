# apply-twice: Apply twice
#
# Pattern:  functions as values
# Why:      call the code reference, then call it again on the result
# Time:     twice the cost of f   Space: O(1)
# Edge:     none beyond f itself
# Perl:     $f->($x) calls a code reference; sub { ... } makes one
use strict;
use warnings;

sub apply_twice {
    my ($f, $x) = @_;
    return $f->($f->($x));
}

1;
