# last-k: The last k events
#
# Pattern:  bounded queue
# Why:      push each event; when the queue is longer than k, drop the oldest --
#           works on a stream too, holding only k items
# Time:     O(n)   Space: O(k)
# Edge:     fewer than k events; empty input
# Perl:     push and shift make an array a queue
use strict;
use warnings;

sub last_k {
    my ($events, $k) = @_;
    my @q;
    for my $e (@$events) {
        push @q, $e;
        shift @q if @q > $k;
    }
    return \@q;
}

1;
