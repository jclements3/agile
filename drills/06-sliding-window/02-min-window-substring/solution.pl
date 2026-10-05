# min-window-substring: Smallest window covering a pattern (LeetCode 76)
#
# Pattern:  grow the window right until it covers t, then shrink from the left
#           while it still covers; record every covering window
# Why:      each index enters and leaves the window once; a "missing" counter
#           says in O(1) whether the window covers t
# Time:     O(|s| + |t|)   Space: O(alphabet)
# Edge:     repeated characters in t; no cover -> ''; ties keep the leftmost
#           (only a strictly shorter window replaces the best)
# Perl:     $need{$c}-- may go negative: surplus copies inside the window
use strict;
use warnings;

sub min_window {
    my ($s, $t) = @_;
    my %need;
    $need{$_}++ for split //, $t;
    my $missing = length $t;
    my ($lo, $best_lo, $best_len) = (0, 0, -1);
    for my $hi (0 .. length($s) - 1) {
        my $c = substr($s, $hi, 1);
        $missing-- if ($need{$c} // 0) > 0;
        $need{$c}--;
        while ($missing == 0) {
            my $len = $hi - $lo + 1;
            ($best_lo, $best_len) = ($lo, $len) if $best_len < 0 || $len < $best_len;
            my $d = substr($s, $lo, 1);
            $need{$d}++;
            $missing++ if $need{$d} > 0;
            $lo++;
        }
    }
    return $best_len < 0 ? '' : substr($s, $best_lo, $best_len);
}

1;
