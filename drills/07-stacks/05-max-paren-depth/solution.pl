# max-paren-depth: Deepest nesting (LeetCode 1614)
#
# Pattern:  a counter standing in for the stack's height
# Why:      only the number of open brackets matters, not which ones, so the
#           stack collapses to an integer
# Time:     O(n)   Space: O(1)
# Edge:     empty string -> 0
# Perl:     for my $c (split //, $s) ; postfix if
use strict;
use warnings;

sub max_paren_depth {
    my ($s) = @_;
    my ($depth, $best) = (0, 0);
    for my $c (split //, $s) {
        if ($c eq '(') {
            $depth++;
            $best = $depth if $depth > $best;
        }
        elsif ($c eq ')') {
            $depth--;
        }
    }
    return $best;
}

1;
