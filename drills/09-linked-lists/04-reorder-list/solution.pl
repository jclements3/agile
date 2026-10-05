# reorder-list: Reorder a list, first-last-second-... (LeetCode 143)
#
# Pattern:  slow/fast to find the middle, reverse the second half, zip
# Why:      the back half reversed yields Ln, Ln-1, ... in order, so
#           alternating from the two halves gives the required order
# Time:     O(n)   Space: O(1)
# Edge:     empty, one and two nodes; odd length (the middle ends the list)
# Perl:     cut the list with $slow->{next} = undef before reversing
use strict;
use warnings;

sub reorder_list {
    my ($head) = @_;
    return $head unless $head && $head->{next};
    my ($slow, $fast) = ($head, $head->{next});
    while ($fast && $fast->{next}) {
        $slow = $slow->{next};
        $fast = $fast->{next}{next};
    }
    my $back = $slow->{next};
    $slow->{next} = undef;
    my $prev;
    ($back->{next}, $prev, $back) = ($prev, $back, $back->{next}) while $back;
    my $front = $head;
    while ($prev) {
        my ($fn, $pn) = ($front->{next}, $prev->{next});
        $front->{next} = $prev;
        $prev->{next}  = $fn;
        ($front, $prev) = ($fn, $pn);
    }
    return $head;
}

1;
