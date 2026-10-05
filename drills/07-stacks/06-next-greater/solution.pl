# next-greater: Next greater value
#
# Pattern:  monotonic stack of indices still waiting for a larger value
# Why:      a new value answers every smaller waiting value on top of the
#           stack; each index is pushed and popped once
# Time:     O(n)   Space: O(n)
# Edge:     equal values do not count as greater; leftovers stay -1
# Perl:     my @out = (-1) x @$xs
use strict;
use warnings;

sub next_greater {
    my ($xs) = @_;
    my @out = (-1) x @$xs;
    my @stack;
    for my $i (0 .. $#$xs) {
        $out[ pop @stack ] = $xs->[$i] while @stack && $xs->[ $stack[-1] ] < $xs->[$i];
        push @stack, $i;
    }
    return \@out;
}

1;
