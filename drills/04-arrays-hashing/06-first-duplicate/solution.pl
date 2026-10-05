# first-duplicate: First value seen twice
#
# Pattern:  hash set of the values seen so far
# Why:      the first value found already in the set is, by construction,
#           the one whose second appearance comes first
# Time:     O(n)   Space: O(n)
# Edge:     a repeated 0 is a real answer (return it, not "false"); none -> undef
# Perl:     return $x if $seen{$x}++ ; a bare return gives undef
use strict;
use warnings;

sub first_duplicate {
    my ($xs) = @_;
    my %seen;
    for my $x (@$xs) {
        return $x if $seen{$x}++;
    }
    return undef;
}

1;
