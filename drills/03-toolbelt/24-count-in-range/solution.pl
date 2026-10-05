# count-in-range: Count values in a range
#
# Pattern:  two binary searches (lower and upper bound)
# Why:      lower_bound(lo) is the first index with value >= lo; lower_bound
#           of "> hi" is the first index past the range; their difference counts it
# Time:     O(log n)   Space: O(1)
# Edge:     empty list; a range outside the values; all values equal
# Perl:     a half-open [lo, hi) search returns n when every value is smaller;
#           int(($l + $h) / 2)
use strict;
use warnings;

sub count_in_range {
    my ($xs, $lo, $hi) = @_;
    return _first($xs, sub { $_[0] > $hi }) - _first($xs, sub { $_[0] >= $lo });
}

sub _first {                        # the first index whose value passes $ok (values pass from some point on)
    my ($xs, $ok) = @_;
    my ($l, $h) = (0, scalar @$xs);
    while ($l < $h) {
        my $m = int(($l + $h) / 2);
        if ($ok->($xs->[$m])) { $h = $m } else { $l = $m + 1 }
    }
    return $l;
}

1;
