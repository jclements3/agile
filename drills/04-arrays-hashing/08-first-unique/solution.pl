# first-unique: First character that never repeats (patterns P1)
#
# Pattern:  two passes: count every character, then scan in order
# Why:      the count is only known after the whole string is read; the
#           second pass keeps the original order, so the first count-1 wins
# Time:     O(n)   Space: O(alphabet)
# Edge:     empty string and all-repeated strings both give '_'
# Perl:     split //, $s gives the characters; first { } from List::Util
use strict;
use warnings;
use List::Util qw(first);

sub first_unique {
    my ($s) = @_;
    my %count;
    my @c = split //, $s;
    $count{$_}++ for @c;
    my $hit = first { $count{$_} == 1 } @c;
    return defined $hit ? $hit : '_';
}

1;
