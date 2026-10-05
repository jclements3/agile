# p12-dedup: De-duplicate, keep order
#
# Pattern:  seen-hash filter
# Why:      $seen{$_}++ is 0 (false) the first time a token is met, so grep
#           keeps exactly the first occurrences, in order
# Time:     O(n)   Space: O(n)
# Edge:     an empty line must still print a newline; all tokens equal
# Perl:     grep { !$seen{$_}++ } is the order-keeping uniq of core Perl
use strict;
use warnings;

my $line = <STDIN> // '';
my %seen;
print join(' ', grep { !$seen{$_}++ } split ' ', $line), "\n";
