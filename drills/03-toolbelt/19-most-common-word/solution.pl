# most-common-word: Most common word
#
# Pattern:  counting with a tie-break
# Why:      count in a hash; the first key sorted by count descending then word
#           ascending is the answer
# Time:     O(n + k log k)   Space: O(k)
# Edge:     ties; case is significant ("A" and "a" are different words; "B" < "a")
# Perl:     sort { $c{$b} <=> $c{$a} or $a cmp $b } keys %c
use strict;
use warnings;

sub most_common_word {
    my ($text) = @_;
    my %c;
    $c{$_}++ for split ' ', $text;
    my ($best) = sort { $c{$b} <=> $c{$a} or $a cmp $b } keys %c;
    return $best;
}

1;
