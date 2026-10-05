# p23-longest-unique: Longest run without repeats (LeetCode 3)
#
# Pattern:  sliding window with the last index of each character
# Why:      when the current character was last seen inside the window, the
#           window must start just after that sighting; every window end is
#           visited once
# Time:     O(n)   Space: O(alphabet)
# Edge:     "abba": a stale last index before the start must not move the
#           start backwards (hence the >= $start test); the empty line
# Perl:     substr walks the string; exists guards the first sighting
use strict;
use warnings;

my $s = <STDIN> // '';
chomp $s;
my %last;
my ($start, $best) = (0, 0);
for my $i (0 .. length($s) - 1) {
    my $ch = substr $s, $i, 1;
    $start = $last{$ch} + 1 if exists $last{$ch} && $last{$ch} >= $start;
    $last{$ch} = $i;
    $best = $i - $start + 1 if $i - $start + 1 > $best;
}
print "$best\n";
