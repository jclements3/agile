#!/usr/bin/perl
# sim/tidewater-split.pl [--out docs/tidewater/work-split.json] -- where the team's time goes, for the primer's BLUF.
#
# Reads the backlog in sim/tidewater-plan.pl (every task's points, every story's work type: engineering, platform or
# learning) and the cadence's ceremony hours, and writes one JSON file the primer cites with {{value: ...}}:
#   sprints.N.{points,engineering,platform,learning}   percent of the sprint's planned points
#   s1_6 / s1_39                                        the same over the first 12 weeks / the whole 18 months
#   time.*                                              percent of all paid hours in sprints 1-6, ceremonies included
# The numbers are the PLAN. When the simulation's evidence exists, sim/tidewater-evidence.pl may overwrite this file
# from the run (same keys), and the primer follows without edits.
use strict;
use warnings;
use FindBin;
use Getopt::Long;

my $out = "$FindBin::Bin/../docs/tidewater/work-split.json";
GetOptions('out=s' => \$out) or die "usage: tidewater-split.pl [--out FILE]\n";
require "$FindBin::Bin/tidewater-plan.pl";
my $plan = tw_plan();

# the cadence (docs/src/primer/08-operating-model.txt): hours per person per two-week sprint
my %CEREMONY = (standup => 10 * 0.25, kickoff => 1.5, refinement => 1, review => 1, retro => 1);
my $ceremony_h = 0; $ceremony_h += $_ for values %CEREMONY;
my $PEOPLE = 3;
my $SPRINT_H = 80;                                   # paid hours per person per sprint
my $POINT_H = 8;                                     # one point = one ideal person-day

my (%sum6, %sum39, $pts6, $pts39, %sp);
for my $s (@$plan) {
    my %w; my $t = 0;
    for my $st (@{ $s->{stories} }) { for my $tk (@{ $st->{tasks} }) { $w{ $st->{work} } += $tk->{p}; $t += $tk->{p} } }
    next unless $t;
    $sp{ $s->{n} } = { points => $t, (map { $_ => pct($w{$_} // 0, $t) } qw(engineering platform learning)), overhead => pct(($w{platform} // 0) + ($w{learning} // 0), $t) };
    for my $k (keys %w) { $sum39{$k} += $w{$k}; $sum6{$k} += $w{$k} if $s->{n} <= 6 }
    $pts39 += $t; $pts6 += $t if $s->{n} <= 6;
}
sub pct { my ($n, $d) = @_; $d ? sprintf('%.0f', 100 * $n / $d) + 0 : 0 }

my $paid6 = 6 * $PEOPLE * $SPRINT_H;                 # sprints 1-6, all paid hours
my %h6 = map { $_ => ($sum6{$_} // 0) * $POINT_H } qw(engineering platform learning);
my $cer6 = 6 * $PEOPLE * $ceremony_h;
my $board6 = 0; $board6 += $_ for values %h6;
my %time = (
    engineering => pct($h6{engineering}, $paid6), platform => pct($h6{platform}, $paid6), learning => pct($h6{learning}, $paid6),
    ceremonies => pct($cer6, $paid6),
);
$time{other} = 100 - $time{engineering} - $time{platform} - $time{learning} - $time{ceremonies};

my %doc = (
    source => 'sim/tidewater-plan.pl (the plan; replaced by the run when sim/tidewater-evidence.pl writes this file)',
    sprints => \%sp,
    s1_6 => { points => $pts6, map { $_ => pct($sum6{$_} // 0, $pts6) } qw(engineering platform learning) },
    s1_39 => { points => $pts39, map { $_ => pct($sum39{$_} // 0, $pts39) } qw(engineering platform learning) },
    ceremony_hours => { %CEREMONY, total => $ceremony_h, share_of_sprint => pct($ceremony_h, $SPRINT_H) },
    time => \%time,
);
require JSON::PP;
my $json = JSON::PP->new->canonical->pretty->encode(\%doc);
open my $fh, '>:raw', $out or die "cannot write $out: $!\n";
print $fh $json;
close $fh;
printf "wrote %s: S1-S6 engineering %d%%, platform %d%%, learning %d%%; time: engineering %d%%, ceremonies %d%%\n",
    $out, @{ $doc{s1_6} }{qw(engineering platform learning)}, $time{engineering}, $time{ceremonies};
