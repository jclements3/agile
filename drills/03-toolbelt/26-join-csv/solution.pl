# join-csv: Join as CSV
#
# Pattern:  build once with join
# Why:      join walks the list once; repeated string appends are the habit
#           that costs O(n^2) in languages with immutable strings
# Time:     O(n)   Space: O(n)
# Edge:     an empty list gives the empty string; no trailing comma
# Perl:     join ',', @$nums
use strict;
use warnings;

sub join_csv {
    my ($nums) = @_;
    return join ',', @$nums;
}

1;
