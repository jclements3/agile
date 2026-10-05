# flatten: Flatten one level
#
# Pattern:  nested loop, one level
# Why:      dereference each inner list in turn and collect
# Time:     O(total)   Space: O(total)
# Edge:     empty inner lists; deeper lists are kept as they are
# Perl:     map { @$_ } dereferences each array ref into the outer list
use strict;
use warnings;

sub flatten {
    my ($lists) = @_;
    return [ map { @$_ } @$lists ];
}

1;
