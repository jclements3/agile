# reverse-list: Reverse a linked list (LeetCode 206)
#
# Pattern:  walk the list once, turning each next link to point backwards
# Why:      prev holds the already-reversed part; each step moves one node
#           from the front of the rest onto the front of prev
# Time:     O(n)   Space: O(1)
# Edge:     empty list returns undef; one node returns itself
# Perl:     list assignment swaps three values at once, like a tuple
use strict;
use warnings;

sub reverse_list {
    my ($head) = @_;
    my $prev;
    while ($head) {
        ($head->{next}, $prev, $head) = ($prev, $head, $head->{next});
    }
    return $prev;
}

1;
