# reachable: Every node reachable from a start (lessons)
#
# Pattern:  depth-first search with an explicit stack and a seen set
# Why:      a node is marked when first pushed, so each is expanded once and
#           cycles cannot loop
# Time:     O(V + E)   Space: O(V)
# Edge:     a start with no edges; cycles; a neighbour with no entry in %adj
# Perl:     $seen{$n}++ is false the first time: test and mark in one step;
#           @{ $adj->{$n} || [] } guards a missing key
use strict;
use warnings;

sub reachable {
    my ($adj, $start) = @_;
    my %seen = ($start => 1);
    my @stack = ($start);
    while (@stack) {
        my $node = pop @stack;
        for my $next (@{ $adj->{$node} || [] }) {
            push @stack, $next unless $seen{$next}++;
        }
    }
    return [ keys %seen ];
}

1;
