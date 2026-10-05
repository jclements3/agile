# rle-encode: Run-length encode (LeetCode 443, similar)
#
# Pattern:  grouping runs
# Why:      a back-reference matches a character and every copy that follows it
# Time:     O(n)   Space: O(n)
# Edge:     the empty string; runs of 10 or more; a letter that returns later
# Perl:     s/((.)\2*)/$2 . length($1)/ge -- \2 inside the pattern, $2 in the replacement
use strict;
use warnings;

sub rle_encode {
    my ($s) = @_;
    $s =~ s/((.)\2*)/$2 . length($1)/gse;
    return $s;
}

1;
