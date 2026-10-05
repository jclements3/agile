# p01-echo: Echo a line
#
# Pattern:  input reflex: read one line, print it
# Why:      the line already carries its newline, so printing it is the echo
# Time:     O(length)   Space: O(length)
# Edge:     internal runs of spaces survive because nothing is split
# Perl:     <STDIN> in scalar context reads one line; // '' guards empty input
use strict;
use warnings;

my $line = <STDIN> // '';
print $line;
