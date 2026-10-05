# longest-substring-no-repeat: Longest substring without a repeat (LeetCode 3)
#
# Pattern:  sliding window; remember where each character was last seen
# Why:      when the current character was seen inside the window, the window
#           must start just after that sighting; it never needs to move back
# Time:     O(n)   Space: O(alphabet)
# Edge:     'abba': a last sighting before the window start must not move the
#           start backwards (check last >= start)
# Perl:     substr($s, $i, 1) ; exists $last{$c}
use strict;
use warnings;

sub longest_no_repeat {
    my ($s) = @_;
    my %last;
    my ($start, $best) = (0, 0);
    for my $i (0 .. length($s) - 1) {
        my $c = substr($s, $i, 1);
        $start = $last{$c} + 1 if exists $last{$c} && $last{$c} >= $start;
        $last{$c} = $i;
        $best = $i - $start + 1 if $i - $start + 1 > $best;
    }
    return $best;
}

1;
