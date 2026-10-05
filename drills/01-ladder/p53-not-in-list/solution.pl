# p53-not-in-list: In one list, not the other
#
# Pattern:  set difference with a hash
# Why:      the second list becomes a hash; filtering the first list keeps its
#           order; a second hash prints each id once
# Time:     O(a + b)   Space: O(a + b)
# Edge:     duplicates in the first list; blank lines; nothing left ("-")
# Perl:     the shell twin when order does not matter: comm -23 <(sort a) <(sort b)
use strict;
use warnings;

my (@first, %second, $in_second);
while (my $line = <STDIN>) {
    $line =~ s/\s+\z//;
    next if $line eq '';
    if ($line eq '---') { $in_second = 1; next }
    if ($in_second) { $second{$line} = 1 } else { push @first, $line }
}
my %seen;
my @left = grep { !$second{$_} && !$seen{$_}++ } @first;
print @left ? map { "$_\n" } @left : "-\n";
