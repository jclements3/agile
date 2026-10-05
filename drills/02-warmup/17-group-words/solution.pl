# group-words: Group by first letter
#
# Pattern:  hash of arrays
# Why:      push each word onto the list under its first letter; pushing keeps order
# Time:     O(n)   Space: O(n)
# Edge:     an empty list gives an empty hash
# Perl:     push @{ $g{$k} }, $w autovivifies the array the first time
use strict;
use warnings;

sub group_words {
    my ($words) = @_;
    my %g;
    push @{ $g{ substr($_, 0, 1) } }, $_ for @$words;
    return \%g;
}

1;
