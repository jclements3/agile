# max-sliding-window: Maximum of every window (LeetCode 239)
#
# Pattern:  monotonic deque: indices whose values decrease from front to back
# Why:      a value with a larger one to its right can never be a maximum
#           again, so it is popped; the front is always the window's maximum
# Time:     O(n) (each index is pushed and removed once)   Space: O(k)
# Edge:     k = 1 and k = n; drop the front once it falls out of the window
# Perl:     an array as a deque: push / pop at the back, shift at the front
use strict;
use warnings;

sub max_sliding_window {
    my ($nums, $k) = @_;
    my (@dq, @out);
    for my $i (0 .. $#$nums) {
        pop @dq while @dq && $nums->[ $dq[-1] ] <= $nums->[$i];
        push @dq, $i;
        shift @dq if $dq[0] <= $i - $k;
        push @out, $nums->[ $dq[0] ] if $i >= $k - 1;
    }
    return \@out;
}

1;
