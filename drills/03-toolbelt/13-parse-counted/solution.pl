# parse-counted: Parse a counted list
#
# Pattern:  input shape: a count, then values
# Why:      split the text into lines, read n from line 1, take n values of line 2
# Time:     O(n)   Space: O(n)
# Edge:     more values than n; a trailing newline
# Perl:     split /\n/; split ' ' on the values; a slice @v[0 .. $n - 1]
use strict;
use warnings;

sub parse_counted {
    my ($text) = @_;
    my ($n, $line) = split /\n/, $text;
    my @v = split ' ', $line;
    return [ map { 0 + $_ } @v[ 0 .. $n - 1 ] ];
}

1;
