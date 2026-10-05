# meeting-rooms-needed: How many rooms? (LeetCode 253)
#
# Pattern:  sweep line: walk the sorted starts; release every room whose end
#           (from the sorted ends) is at or before this start
# Why:      the rooms in use at any start = starts so far - ends so far; the
#           peak of that count is the answer
# Time:     O(n log n)   Space: O(n)
# Edge:     a meeting ending when another starts frees the room (<=)
# Perl:     two sorted copies with map; an index into the ends
use strict;
use warnings;

sub min_rooms {
    my ($meetings) = @_;
    my @starts = sort { $a <=> $b } map { $_->[0] } @$meetings;
    my @ends   = sort { $a <=> $b } map { $_->[1] } @$meetings;
    my ($rooms, $peak, $e) = (0, 0, 0);
    for my $s (@starts) {
        while ($e < @ends && $ends[$e] <= $s) { $rooms--; $e++ }
        $rooms++;
        $peak = $rooms if $rooms > $peak;
    }
    return $peak;
}

1;
