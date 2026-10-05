# parse-matrix: Parse a matrix
#
# Pattern:  input shape: R C, then R rows
# Why:      the header says how many rows to read; each row splits into numbers
# Time:     O(R * C)   Space: O(R * C)
# Edge:     a single row or column; stray spaces
# Perl:     my ($r) = split ' ', shift @lines; [ split ' ', $line ] per row
use strict;
use warnings;

sub parse_matrix {
    my ($text) = @_;
    my @lines = split /\n/, $text;
    my ($r) = split ' ', shift @lines;
    return [ map { [ map { 0 + $_ } split ' ', $lines[$_] ] } 0 .. $r - 1 ];
}

1;
