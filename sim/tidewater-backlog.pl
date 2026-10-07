#!/usr/bin/perl
# sim/tidewater-backlog.pl -- the Tidewater plan as a backlog workbook for gitlab.pl backlog import: the three tomes,
# their sixteen epics, and the stories and tasks of sprints 1-6 (the twelve weeks) from sim/tidewater-plan.pl, in the
# columns of tools/gitlab/se-backlog/gitlab_agile_setup.py's Backlog sheet. Sprints 1-5 are DONE, sprint 6 OPEN.
#
#   perl sim/tidewater-backlog.pl [--out DIR]     writes DIR/se-backlog-tidewater.xlsx and .csv (default tools/gitlab/samples)
#
# Deterministic: the same plan gives the same bytes (tests/gitlab.t checks the committed copies are current).
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Getopt::Long;
use Backlog;
require "$FindBin::Bin/tidewater-plan.pl";
our (%TW_EPIC, %TW_TOME);

my $out = "$FindBin::Bin/../tools/gitlab/samples";
GetOptions('out=s' => \$out) or die "usage: tidewater-backlog.pl [--out DIR]\n";
my $plan = tw_plan();
my (%stories_of, @rows);
for my $sp (@$plan[0 .. 5]) {
    push @{ $stories_of{ $_->{epic} } }, [ $sp->{n}, $_ ] for @{ $sp->{stories} };
}
my $num = sub { my $e = shift; $e =~ s/^E//; $e };
for my $t (sort keys %TW_TOME) {
    my @epics = sort { $num->($a) <=> $num->($b) } grep { $TW_EPIC{$_}[0] eq $t } keys %TW_EPIC;
    my $tome_state = (grep { $stories_of{$_} } @epics) ? 'OPEN' : 'TODO';
    push @rows, { ID => $t, Level => 'Tome', Title => $TW_TOME{$t}, Status => $tome_state };
    for my $e (@epics) {
        my @st = @{ $stories_of{$e} // [] };
        push @rows, { ID => $e, Level => 'Epic', Parent => $t, Title => $TW_EPIC{$e}[1], Status => @st ? 'OPEN' : 'TODO' };
        for my $x (@st) {
            my ($n, $s) = @$x;
            my $state = $n <= 5 ? 'DONE' : 'OPEN';
            my $days = 0; $days += $_->{p} for @{ $s->{tasks} };
            push @rows, { ID => $s->{key}, Level => 'Story', Parent => $e, Title => $s->{title}, Team => 'MBSE', Epic => $e, Sprint => $n, Days => $days,
                          'Done when' => join('; ', @{ $s->{done} // [] }), 'Model link' => "area::$s->{area}", Status => $state, Assignee => $s->{owner} };
            my $k = 0;
            for my $tk (@{ $s->{tasks} }) {
                $k++;
                push @rows, { ID => "$s->{key}.K$k", Level => 'Task', Parent => $s->{key}, Title => $tk->{t}, Team => 'MBSE', Epic => $e, Days => $tk->{p},
                              Status => $state, Assignee => $tk->{who} };
            }
        }
    }
}
for my $ext (qw(xlsx csv)) {
    my $f = "$out/se-backlog-tidewater.$ext";
    Backlog::write_file($f, \@rows);
    print "wrote $f\n";
}
my %n; $n{ $_->{Level} }++ for @rows;
print join(', ', map { "$n{$_} $_" } qw(Tome Epic Story Task)) . "\n";
