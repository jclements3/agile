# busiest-users: Busiest users
#
# Pattern:  count by key in a hash, take the maximum, keep the keys that reach it
# Why:      ties are part of the answer, so filter by the top count rather than
#           taking the first of a sort
# Time:     O(n + u log u) for u users   Space: O(u)
# Edge:     no lines -> []; everyone tied -> everyone, sorted
# Perl:     (split ' ', $line)[0] ; max from List::Util ; sort grep { }
use strict;
use warnings;
use List::Util qw(max);

sub busiest_users {
    my ($lines) = @_;
    my %count;
    $count{ (split ' ', $_)[0] }++ for @$lines;
    return [] unless %count;
    my $top = max values %count;
    return [ sort grep { $count{$_} == $top } keys %count ];
}

1;
