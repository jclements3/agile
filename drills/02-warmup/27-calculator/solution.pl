# calculator: The calculator (LeetCode 227, similar)
#
# Pattern:  recursive descent parsing
# Why:      one function per grammar rule; a lower rule binds tighter, and the
#           loops in expression and term make equal operators left-associative
# Time:     O(n)   Space: O(depth of parentheses)
# Edge:     10-2-3 is 5, not 11 (loop, do not recurse to the right); spaces
# Perl:     tokens from a global match: $expr =~ /\d+|[-+*()]/g; closures share
#           the position $i
use strict;
use warnings;

sub evaluate {
    my ($expr) = @_;
    my @tok = $expr =~ /\d+|[-+*()]/g;
    my $i = 0;
    my ($expression, $term, $factor);
    $factor = sub {
        my $t = $tok[ $i++ ];
        return $t unless $t eq '(';
        my $v = $expression->();
        $i++;
        return $v;
    };
    $term = sub {
        my $v = $factor->();
        while ($i < @tok && $tok[$i] eq '*') { $i++; $v *= $factor->() }
        return $v;
    };
    $expression = sub {
        my $v = $term->();
        while ($i < @tok && ($tok[$i] eq '+' || $tok[$i] eq '-')) {
            my $op = $tok[ $i++ ];
            my $r = $term->();
            $v = $op eq '+' ? $v + $r : $v - $r;
        }
        return $v;
    };
    return $expression->();
}

1;
