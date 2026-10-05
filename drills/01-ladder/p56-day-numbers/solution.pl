# p56-day-numbers: Day numbers
#
# Pattern:  convert each date to a day count, then subtract
# Why:      timegm gives seconds since the epoch; whole days are seconds /
#           86400, and the difference counts across months, years, leap days
# Time:     O(n)   Space: O(1)
# Edge:     month and year boundaries; leap years; dates before day 1
# Perl:     Time::Local's timegm at noon UTC stays clear of daylight saving;
#           months are 0-based in timegm
use strict;
use warnings;
use Time::Local qw(timegm);

chomp(my @lines = <STDIN>);
my $first = day(shift @lines);
for my $d (grep { /\S/ } @lines) {
    my $n = day($d) - $first + 1;
    print $n >= 1 ? "D$n\n" : "before\n";
}

sub day {
    my ($y, $m, $d) = split /-/, shift;
    return int(timegm(0, 0, 12, $d, $m - 1, $y) / 86400);
}
