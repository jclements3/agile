# level-order: Level-order traversal (LeetCode 102)
#
# Pattern:  breadth-first search; process the queue one level at a time
# Why:      when a level starts, the queue holds exactly that level's nodes,
#           so its size tells how many to take before the next level
# Time:     O(n)   Space: O(w), w = widest level
# Edge:     empty tree -> []; missing children are simply not queued
# Perl:     an array as a queue: push to the back, shift from the front
use strict;
use warnings;

sub level_order {
    my ($root) = @_;
    my @out;
    my @queue = $root ? ($root) : ();
    while (@queue) {
        my @level;
        for (1 .. scalar @queue) {
            my $node = shift @queue;
            push @level, $node->{val};
            push @queue, grep { defined } $node->{left}, $node->{right};
        }
        push @out, \@level;
    }
    return \@out;
}

1;
