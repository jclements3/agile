# string-permutations: Permutations of a string (LeetCode 47, similar)
#
# Pattern:  recursion with de-duplication
# Why:      each character in turn goes first, followed by every ordering of
#           the rest; a hash drops repeats caused by equal characters
# Time:     O(n * n!)   Space: O(n * n!)
# Edge:     the empty string is one permutation; repeated letters
# Perl:     substr($s, 0, $i) . substr($s, $i + 1) removes one character;
#           keys of a hash = distinct strings
use strict;
use warnings;

sub string_permutations {
    my ($s) = @_;
    return [''] if $s eq '';
    my %seen;
    for my $i (0 .. length($s) - 1) {
        my $rest = substr($s, 0, $i) . substr($s, $i + 1);
        $seen{ substr($s, $i, 1) . $_ } = 1 for @{ string_permutations($rest) };
    }
    return [ sort keys %seen ];
}

1;
