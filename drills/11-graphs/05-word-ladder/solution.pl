# word-ladder: Word ladder length (LeetCode 127)
#
# Pattern:  breadth-first search where neighbours differ in one letter
# Why:      BFS reaches each word first by a shortest chain; trying all 26
#           letters at each position costs L*26 per word instead of
#           comparing against every word in the list
# Time:     O(N * L * 26)   Space: O(N)
# Edge:     $end missing from the list -> 0; no path -> 0
# Perl:     a hash as a set; substr as an lvalue on a copy builds a candidate
use strict;
use warnings;

sub ladder_length {
    my ($begin, $end, $words) = @_;
    my %dict = map { $_ => 1 } @$words;
    return 0 unless $dict{$end};
    my %seen = ($begin => 1);
    my @queue = ([ $begin, 1 ]);
    while (my $item = shift @queue) {
        my ($word, $steps) = @$item;
        return $steps if $word eq $end;
        for my $i (0 .. length($word) - 1) {
            for my $ch ('a' .. 'z') {
                my $cand = $word;
                substr($cand, $i, 1) = $ch;
                next unless $dict{$cand} && !$seen{$cand}++;
                push @queue, [ $cand, $steps + 1 ];
            }
        }
    }
    return 0;
}

1;
