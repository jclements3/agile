# from-roman: From Roman numerals (LeetCode 13)
#
# Pattern:  one pass with a look-ahead
# Why:      a symbol smaller than its right neighbour is the subtractive half
#           of a pair, so it counts negative
# Time:     O(n)   Space: O(1)
# Edge:     the last symbol has no neighbour (compare with 0)
# Perl:     split // into characters; a hash of symbol values; // 0 past the end
use strict;
use warnings;

sub from_roman {
    my ($s) = @_;
    my %v = (I => 1, V => 5, X => 10, L => 50, C => 100, D => 500, M => 1000);
    my @c = map { $v{$_} } split //, $s;
    my $total = 0;
    for my $i (0 .. $#c) {
        my $next = $i < $#c ? $c[ $i + 1 ] : 0;
        $total += $c[$i] < $next ? -$c[$i] : $c[$i];
    }
    return $total;
}

1;
