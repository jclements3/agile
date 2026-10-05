# p40-log-report: Error report from messy logs
#
# Pattern:  parse / validate / count / report, each a small named piece
# Why:      parse() returns (level, service) or nothing, so every malformed
#           rule lives in one place; "also count WARN" changes only report()
# Time:     O(L + s log s) for L lines, s services   Space: O(s)
# Edge:     DEBUG and other levels are malformed; a service without its colon
#           is malformed; "svc:" with no message is fine; blank lines are not
#           malformed; the malformed line always prints
# Perl:     split ' ', $line, 4 stops after four fields, so the message keeps
#           its spaces
use strict;
use warnings;

my %LEVEL = map { $_ => 1 } qw(INFO WARN ERROR);
my (%errors, $malformed);
$malformed = 0;
while (my $line = <STDIN>) {
    next if $line !~ /\S/;
    my ($level, $svc) = parse($line);
    if (!defined $level) { $malformed++; next }
    $errors{$svc}++ if $level eq 'ERROR';
}
report(\%errors, $malformed);

sub parse {
    my ($line) = @_;
    my (undef, $level, $svc) = split ' ', $line, 4;
    return unless defined $svc && $LEVEL{$level} && $svc =~ /^(\S+):$/;
    return ($level, $1);
}

sub report {
    my ($e, $bad) = @_;
    print "$_ $e->{$_}\n" for sort { $e->{$b} <=> $e->{$a} or $a cmp $b } keys %$e;
    print "malformed $bad\n";
}
