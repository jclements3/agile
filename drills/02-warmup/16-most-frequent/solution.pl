# most-frequent: Most frequent, with a tie-break
#
# Pattern:  counting with a two-level sort key
# Why:      count in a hash, then sort by count descending and value ascending;
#           the first key is the answer
# Time:     O(n + k log k)   Space: O(k)
# Edge:     ties; 9 before 10 (compare numbers as numbers, not strings)
# Perl:     sort { $c{$b} <=> $c{$a} or ... }; Scalar::Util looks_like_number picks <=> or cmp
use strict;
use warnings;
use Scalar::Util qw(looks_like_number);

sub most_frequent {
    my ($xs) = @_;
    my %c;
    $c{$_}++ for @$xs;
    my ($best) = sort { $c{$b} <=> $c{$a} or _cmp($a, $b) } keys %c;
    return $best;
}

sub _cmp {
    my ($x, $y) = @_;
    return looks_like_number($x) && looks_like_number($y) ? $x <=> $y : $x cmp $y;
}

1;
