# task-scheduler: Tasks with a cooldown (LeetCode 621)
#
# Pattern:  greedy in cycles of n + 1 slots: each cycle runs the most
#           frequent remaining letters, one each (a max-heap of counts)
# Why:      running the most frequent letters first never forces extra idle
#           time later; a cycle that ends the work needs no idle tail
# Time:     O(T log 26)   Space: O(26)
# Edge:     n = 0 (no idle); one letter only; no tasks
# Perl:     with at most 26 counts, re-sorting the counts each cycle is the
#           plain stand-in for a heap: sort { $b <=> $a } values %count
use strict;
use warnings;

sub least_interval {
    my ($tasks, $n) = @_;
    my %count;
    $count{$_}++ for @$tasks;
    my @left = sort { $b <=> $a } values %count;
    my $time = 0;
    while (@left) {
        my @took = splice @left, 0, $n + 1;
        my @back = grep { $_ > 0 } map { $_ - 1 } @took;
        @left = sort { $b <=> $a } @left, @back;
        $time += @left ? $n + 1 : scalar @took;
    }
    return $time;
}

1;
