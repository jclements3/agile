# to-base: Convert to any base (LeetCode 504, similar)
#
# Pattern:  repeated division
# Why:      n % b is the last digit; dividing by b drops it; the digits come
#           out last-first, so prepend each one
# Time:     O(log_b n)   Space: O(log_b n)
# Edge:     n = 0 must print "0" (the loop would print nothing)
# Perl:     a digit table string and substr; int($n / $b) for integer division
use strict;
use warnings;

sub to_base {
    my ($n, $b) = @_;
    return '0' if $n == 0;
    my $digits = '0123456789ABCDEF';
    my $out = '';
    while ($n > 0) {
        $out = substr($digits, $n % $b, 1) . $out;
        $n = int($n / $b);
    }
    return $out;
}

1;
