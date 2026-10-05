# shortest-steps: Fewest edges between two nodes (lessons)
#
# Pattern:  breadth-first search, recording each node's distance when queued
# Why:      BFS dequeues nodes in order of distance, so the first time the
#           goal comes off the queue its distance is the minimum
# Time:     O(V + E)   Space: O(V)
# Edge:     start equals goal -> 0; unreachable -> -1
# Perl:     exists $dist{$n} doubles as the seen set
use strict;
use warnings;

sub shortest_steps {
    my ($adj, $start, $goal) = @_;
    my %dist = ($start => 0);
    my @queue = ($start);
    while (@queue) {
        my $node = shift @queue;
        return $dist{$node} if $node eq $goal;
        for my $next (@{ $adj->{$node} || [] }) {
            next if exists $dist{$next};
            $dist{$next} = $dist{$node} + 1;
            push @queue, $next;
        }
    }
    return -1;
}

1;
