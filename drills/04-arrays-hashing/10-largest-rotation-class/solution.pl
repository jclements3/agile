# largest-rotation-class: Largest rotation class
#
# Pattern:  map each string to a canonical form, count in a hash
# Why:      every rotation of a string has the same smallest rotation, so
#           that rotation names the class
# Time:     O(n k^2) for n strings of length k   Space: O(n k)
# Edge:     no words -> 0; the empty string is its own class
# Perl:     substr($s, $i) . substr($s, 0, $i) is rotation i; max from List::Util
use strict;
use warnings;
use List::Util qw(max);

sub largest_rotation_class {
    my ($words) = @_;
    return 0 unless @$words;
    my %size;
    $size{ canon($_) }++ for @$words;
    return max values %size;
}

sub canon {
    my ($s) = @_;
    my $best = $s;
    for my $i (1 .. length($s) - 1) {
        my $r = substr($s, $i) . substr($s, 0, $i);
        $best = $r if $r lt $best;
    }
    return $best;
}

1;
