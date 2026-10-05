# p13-transpose: Transpose a matrix
#
# Pattern:  parse a matrix into an array of arrays, then read it by column
# Why:      output row c is column c of the input: the c-th value of each row
# Time:     O(R*C)   Space: O(R*C)
# Edge:     1x1; a single column becomes a single row
# Perl:     [ split ' ' ] builds a row; map { $_->[$c] } @rows reads a column
use strict;
use warnings;

chomp(my @lines = <STDIN>);
my ($r, $c) = split ' ', shift @lines;
my @rows = map { [ split ' ' ] } @lines[0 .. $r - 1];
for my $col (0 .. $c - 1) {
    print join(' ', map { $_->[$col] } @rows), "\n";
}
