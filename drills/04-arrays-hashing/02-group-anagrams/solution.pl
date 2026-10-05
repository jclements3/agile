# group-anagrams: Group anagrams (LeetCode 49)
#
# Pattern:  group by a canonical key in a hash of arrays
# Why:      anagrams share one signature, their letters sorted; every word
#           lands in the bucket of its signature
# Time:     O(n k log k) for n words of length k   Space: O(n k)
# Edge:     the empty string has the empty signature; no words -> []
# Perl:     join '', sort split //, $w ; push @{ $g{$key} }, $w autovivifies
use strict;
use warnings;

sub group_anagrams {
    my ($words) = @_;
    my (%group, @order);
    for my $w (@$words) {
        my $key = join '', sort split //, $w;
        push @order, $key unless exists $group{$key};
        push @{ $group{$key} }, $w;
    }
    return [ map { $group{$_} } @order ];
}

1;
