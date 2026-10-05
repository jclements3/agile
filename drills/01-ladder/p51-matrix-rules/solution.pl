# p51-matrix-rules: Matrix rules check
#
# Pattern:  a list of (test, message) rules applied to each row in order
# Why:      a new rule is one more entry in @RULES; nothing else changes
# Time:     O(rows * rules)   Space: O(problems)
# Edge:     an empty kind compared as a number (treat it as 0); one row
#           breaking two rules prints two lines; trailing empty fields
# Perl:     split /\t/, $line, -1 keeps trailing empty fields; code refs in
#           an array of pairs
use strict;
use warnings;

my %SCORE = map { $_ => 1 } ('in place', 'partial', 'missing', 'unknown');
my @RULES = (
    [ sub { !$SCORE{ $_[0]{score} } }, 'bad score' ],
    [ sub { $_[0]{score} eq 'in place' && !(($_[0]{kind} || 0) >= 1 && ($_[0]{kind} || 0) <= 4) }, 'in place needs kind 1-4' ],
    [ sub { $_[0]{score} eq 'in place' && $_[0]{ref} eq '' }, 'in place needs a ref' ],
);
<STDIN>;
my @problems;
while (my $line = <STDIN>) {
    $line =~ s/\r?\n\z//;
    next if $line !~ /\S/;
    my %row;
    @row{qw(id element domain score kind ref)} = map { $_ // '' } (split /\t/, $line, -1)[0 .. 5];
    push @problems, map { "$row{id}: $_->[1]" } grep { $_->[0]->(\%row) } @RULES;
}
print "$_\n" for @problems;
print @problems ? scalar(@problems) . " problem(s)\n" : "OK\n";
