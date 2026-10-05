# p52-commits-per-day: Commits per day
#
# Pattern:  count by the first field, print the keys sorted
# Why:      ISO dates (YYYY-MM-DD) sort correctly as plain strings
# Time:     O(n + d log d)   Space: O(d)
# Edge:     messages with spaces (only the first field matters); empty input
# Perl:     (split ' ', $line)[0] takes one field; the one-liner is
#           perl -lane '$c{$F[0]}++; END { print "$_ $c{$_}" for sort keys %c }'
use strict;
use warnings;

my %c;
while (my $line = <STDIN>) {
    my ($date) = split ' ', $line;
    $c{$date}++ if defined $date;
}
print "$_ $c{$_}\n" for sort keys %c;
