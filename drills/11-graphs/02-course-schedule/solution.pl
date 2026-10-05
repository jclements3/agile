# course-schedule: Can every course be finished? (LeetCode 207)
#
# Pattern:  Kahn's topological sort: repeatedly take a course with no
#           unmet prerequisite
# Why:      in a cycle no course ever reaches in-degree 0, so fewer than n
#           courses get taken exactly when there is a cycle
# Time:     O(V + E)   Space: O(V + E)
# Edge:     no prerequisites; a course that requires itself
# Perl:     @indeg = (0) x $n; a hash of arrays for the edges;
#           grep { !$indeg[$_] } 0 .. $n - 1 seeds the queue
use strict;
use warnings;

sub can_finish {
    my ($n, $prereqs) = @_;
    my @indeg = (0) x $n;
    my %next;
    for my $p (@$prereqs) {
        my ($course, $before) = @$p;
        push @{ $next{$before} }, $course;
        $indeg[$course]++;
    }
    my @queue = grep { !$indeg[$_] } 0 .. $n - 1;
    my $taken = 0;
    while (@queue) {
        my $c = shift @queue;
        $taken++;
        for my $m (@{ $next{$c} || [] }) {
            push @queue, $m unless --$indeg[$m];
        }
    }
    return $taken == $n ? 1 : 0;
}

1;
