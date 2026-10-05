# p57-blocked-days: Blocked days per task
#
# Pattern:  open/close events per key: remember the open date, add the
#           stretch on close, close what is left at the end
# Why:      each stretch is measured once, so the total is the sum of
#           stretches and the "!" rule can look at each one alone
# Time:     O(n + k log k)   Space: O(k)
# Edge:     repeated blocks on one task (sum them); a block never unblocked
#           (count to today); the ! is per stretch, not per total
# Perl:     day() from p56 (Time::Local::timegm); a sub that closes a stretch
#           is used by both the unblock event and the end of input
use strict;
use warnings;
use Time::Local qw(timegm);

my (%open, %total, %flag, $today);
while (my $line = <STDIN>) {
    my ($date, $id, $kind) = split ' ', $line;
    next unless defined $id;
    if ($date eq 'today') { $today = $id; next }
    if ($kind eq 'block') { $open{$id} = $date; $total{$id} //= 0 }
    elsif ($kind eq 'unblock' && exists $open{$id}) { close_stretch($id, $date) }
}
if (defined $today) { close_stretch($_, $today) for sort keys %open }
print "$_ $total{$_}", ($flag{$_} ? ' !' : ''), "\n" for sort keys %total;

sub close_stretch {
    my ($id, $end) = @_;
    my $len = day($end) - day(delete $open{$id});
    $total{$id} += $len;
    $flag{$id} = 1 if $len > 5;
}

sub day {
    my ($y, $m, $d) = split /-/, shift;
    return int(timegm(0, 0, 12, $d, $m - 1, $y) / 86400);
}
