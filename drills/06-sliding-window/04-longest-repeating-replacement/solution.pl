# longest-repeating-replacement: Longest run after k replacements (LeetCode 424)
#
# Pattern:  sliding window valid while (window length - top letter count) <= k
# Why:      a window can be made one letter by changing everything but its
#           most common letter; shrink from the left whenever that exceeds k
# Time:     O(n)   Space: O(26)
# Edge:     the stored top count may be stale after shrinking; that is safe,
#           because only a larger top count can produce a longer answer
# Perl:     substr for characters; a %count hash
use strict;
use warnings;

sub longest_after_replacements {
    my ($s, $k) = @_;
    my %count;
    my ($start, $best, $top) = (0, 0, 0);
    for my $end (0 .. length($s) - 1) {
        my $c = substr($s, $end, 1);
        $count{$c}++;
        $top = $count{$c} if $count{$c} > $top;
        while ($end - $start + 1 - $top > $k) {
            $count{ substr($s, $start, 1) }--;
            $start++;
        }
        $best = $end - $start + 1 if $end - $start + 1 > $best;
    }
    return $best;
}

1;
