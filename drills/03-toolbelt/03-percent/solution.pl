# percent: Percent with one decimal
#
# Pattern:  sprintf formatting
# Why:      scale to 100 and let the format do the rounding and the decimal
# Time:     O(1)   Space: O(1)
# Edge:     100.0% and 0.0% keep their one decimal
# Perl:     %% prints a literal percent sign in sprintf
use strict;
use warnings;

sub percent {
    my ($part, $whole) = @_;
    return sprintf '%.1f%%', 100 * $part / $whole;
}

1;
