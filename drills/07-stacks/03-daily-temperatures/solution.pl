# daily-temperatures: Days until warmer (LeetCode 739)
#
# Pattern:  monotonic decreasing stack of day indices still waiting
# Why:      a warmer day answers every colder day on top of the stack at once;
#           each index is pushed and popped once
# Time:     O(n)   Space: O(n)
# Edge:     equal temperatures are not warmer (strict <); unanswered days stay 0
# Perl:     my @out = (0) x @$t ; $t->[ $stack[-1] ] peeks at the top
use strict;
use warnings;

sub days_until_warmer {
    my ($t) = @_;
    my @out = (0) x @$t;
    my @stack;
    for my $i (0 .. $#$t) {
        while (@stack && $t->[ $stack[-1] ] < $t->[$i]) {
            my $j = pop @stack;
            $out[$j] = $i - $j;
        }
        push @stack, $i;
    }
    return \@out;
}

1;
