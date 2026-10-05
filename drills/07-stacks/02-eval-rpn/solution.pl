# eval-rpn: Evaluate postfix notation (LeetCode 150)
#
# Pattern:  stack machine: numbers push, operators pop two and push one
# Why:      postfix puts an operator after its operands, so they are always the
#           top two values of the stack
# Time:     O(n)   Space: O(n)
# Edge:     operand order: the SECOND pop is the left operand; division
#           truncates toward zero (int, not floor)
# Perl:     a dispatch hash of code refs; int($x / $y) truncates toward zero
use strict;
use warnings;

sub eval_rpn {
    my ($tokens) = @_;
    my %op = (
        '+' => sub { $_[0] + $_[1] },
        '-' => sub { $_[0] - $_[1] },
        '*' => sub { $_[0] * $_[1] },
        '/' => sub { int($_[0] / $_[1]) },
    );
    my @stack;
    for my $t (@$tokens) {
        if (exists $op{$t}) {
            my $right = pop @stack;
            my $left  = pop @stack;
            push @stack, $op{$t}->($left, $right);
        }
        else {
            push @stack, $t;
        }
    }
    return $stack[0];
}

1;
