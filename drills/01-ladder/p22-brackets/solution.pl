# p22-brackets: Balanced brackets (LeetCode 20)
#
# Pattern:  stack of open brackets
# Why:      a closer must match the most recent unmatched opener, which is
#           exactly the top of the stack; leftovers at the end are unclosed
# Time:     O(length) per string   Space: O(length)
# Edge:     a closer on an empty stack; openers left over; the empty string
# Perl:     pop on an empty array returns undef, so compare with // ''
use strict;
use warnings;

my %match = (')' => '(', ']' => '[', '}' => '{');

sub balanced {
    my ($s) = @_;
    my @stack;
    for my $ch (split //, $s) {
        if ($match{$ch}) { return 0 if (pop(@stack) // '') ne $match{$ch} }
        else { push @stack, $ch }
    }
    return !@stack;
}

chomp(my @lines = <STDIN>);
my $n = shift @lines;
print balanced($lines[$_] // '') ? "YES\n" : "NO\n" for 0 .. $n - 1;
