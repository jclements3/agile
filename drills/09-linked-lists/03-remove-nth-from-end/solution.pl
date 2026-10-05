# remove-nth-from-end: Remove the nth node from the end (LeetCode 19)
#
# Pattern:  fast pointer n steps ahead of slow; a dummy before the head
# Why:      when fast reaches the last node, slow sits just before the node
#           to drop; the dummy makes removing the head the same case
# Time:     O(n), one pass   Space: O(1)
# Edge:     removing the head; a one-node list becomes empty
# Perl:     $slow->{next} = $slow->{next}{next} unlinks; arrows between
#           subscripts are optional
use strict;
use warnings;

sub remove_nth_from_end {
    my ($head, $n) = @_;
    my $dummy = { next => $head };
    my ($fast, $slow) = ($dummy, $dummy);
    $fast = $fast->{next} for 1 .. $n;
    while ($fast->{next}) {
        $fast = $fast->{next};
        $slow = $slow->{next};
    }
    $slow->{next} = $slow->{next}{next};
    return $dummy->{next};
}

1;
