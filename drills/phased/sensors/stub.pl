# phased-sensors: your solution, grown phase by phase (perl drills/drill.pl phased test N)
#
# ASSUME: (write your answers to the five questions here, one line each)
#
# A decomposition that survives the changes: write these as separate subs, now.
#   close_enough($x, $y, %opt)   are two detections the same object?
#   validate($feed_a, $feed_b)   can these inputs be paired at all? (a reason, or nothing)
#   pair($feed_a, $feed_b, %opt) -> (\@pairs, \@unpaired_a, \@unpaired_b)
# Put the things that will move (tolerances) in %opt with defaults.
use strict;
use warnings;

sub solve {
    my ($feed_a, $feed_b, %opt) = @_;
    # your code here
    return { pairs => [], unpaired_a => [], unpaired_b => [], ok => 0, reason => 'todo' };
}

1;
