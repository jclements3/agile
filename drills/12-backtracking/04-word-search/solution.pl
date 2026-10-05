# word-search: Find a word in a letter grid (LeetCode 79)
#
# Pattern:  depth-first search from every cell; mark a cell used while it is
#           on the current path and unmark it when the path backs out
# Why:      the mark stops reuse within one path but not across paths
# Time:     O(R*C * 4^L)   Space: O(L) recursion
# Edge:     a word longer than the board; a path that must turn back
# Perl:     copy the rows into arrays of characters (split //); a named
#           helper recurses more clearly than a closure here
use strict;
use warnings;

sub exist {
    my ($rows, $word) = @_;
    my @g = map { [ split //, $_ ] } @$rows;
    my @w = split //, $word;
    for my $r (0 .. $#g) {
        for my $c (0 .. $#{ $g[$r] }) {
            return 1 if _from(\@g, \@w, $r, $c, 0);
        }
    }
    return 0;
}

sub _from {
    my ($g, $w, $r, $c, $i) = @_;
    return 1 if $i == @$w;
    return 0 if $r < 0 || $c < 0 || $r > $#$g || $c > $#{ $g->[$r] } || $g->[$r][$c] ne $w->[$i];
    $g->[$r][$c] = '';
    my $found = _from($g, $w, $r + 1, $c, $i + 1) || _from($g, $w, $r - 1, $c, $i + 1)
             || _from($g, $w, $r, $c + 1, $i + 1) || _from($g, $w, $r, $c - 1, $i + 1);
    $g->[$r][$c] = $w->[$i];
    return $found;
}

1;
