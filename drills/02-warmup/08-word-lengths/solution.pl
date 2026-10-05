# word-lengths: Word lengths
#
# Pattern:  hash from a list
# Why:      map each word to a key/value pair; a repeated key just overwrites
# Time:     O(n)   Space: O(w)
# Edge:     the empty string; runs of spaces
# Perl:     split ' ' trims and collapses whitespace; map { $_ => length } builds the pairs
use strict;
use warnings;

sub word_lengths {
    my ($sentence) = @_;
    return { map { $_ => length $_ } split ' ', $sentence };
}

1;
