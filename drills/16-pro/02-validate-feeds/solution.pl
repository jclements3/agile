# validate-feeds: Validate the feeds first
#
# Pattern:  a validate() step that returns a reason or nothing
# Why:      when "some inputs are now invalid" arrives, one function changes
#           and the solver is untouched
# Time:     O(1)   Space: O(1)
# Edge:     either or both empty
# Perl:     an array ref in numeric context is not its length: use @$a
use strict;
use warnings;

sub validate_feeds {
    my ($x, $y) = @_;
    return 'empty feed' unless @$x && @$y;
    return undef;
}

1;
