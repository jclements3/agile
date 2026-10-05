# count-by-length: Count words by length
#
# Pattern:  counting hash
# Why:      the length is the key; increment it per word
# Time:     O(n)   Space: O(k)
# Edge:     an empty list gives an empty hash
# Perl:     $c{ length $_ }++ for @$words -- ++ on a missing key starts from 0
use strict;
use warnings;

sub count_by_length {
    my ($words) = @_;
    my %c;
    $c{ length $_ }++ for @$words;
    return \%c;
}

1;
