# initials: Initials
#
# Pattern:  split, map, join
# Why:      take each word's first character, upper-case it, add a dot
# Time:     O(n)   Space: O(n)
# Edge:     leading, trailing and repeated spaces
# Perl:     split ' ' (not split / /) trims and collapses; uc substr($_, 0, 1)
use strict;
use warnings;

sub initials {
    my ($name) = @_;
    return join '', map { uc(substr $_, 0, 1) . '.' } split ' ', $name;
}

1;
