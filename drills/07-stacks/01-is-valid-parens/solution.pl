# is-valid-parens: Balanced brackets (LeetCode 20)
#
# Pattern:  stack: push openers, a closer must match the top
# Why:      the most recently opened bracket is the one that must close next,
#           which is exactly what a stack's top holds
# Time:     O(n)   Space: O(n)
# Edge:     a closer on an empty stack; openers left at the end; ''
# Perl:     %pair maps closer -> opener; pop on an empty array returns undef
use strict;
use warnings;

sub is_valid_parens {
    my ($s) = @_;
    my %pair = (')' => '(', ']' => '[', '}' => '{');
    my @stack;
    for my $c (split //, $s) {
        if (exists $pair{$c}) {
            my $top = pop @stack;
            return 0 unless defined $top && $top eq $pair{$c};
        }
        else {
            push @stack, $c;
        }
    }
    return @stack ? 0 : 1;
}

1;
