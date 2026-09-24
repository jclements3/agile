#!/usr/bin/perl
# Discrete time-accounting simulation of the architect's day, over one full two-week
# sprint, at your actual scale (10 teams / 100 people). Not part of the tested kit
# (see lib/, bin/, tests/) -- a standalone planning tool. Pure core Perl, no CPAN.
#
# What it models: the daily townhall + pipeline + triage + the sprint's fixed events
# (planning/refinement/health-check/review), all costed in minutes of the architect's
# own time -- NOT the Perl runtime (that's sub-second regardless of scale; the real
# cost at 100 people is human triage time, not compute). Output: a per-day ledger and
# a sprint summary, so you can see where an 8-hour day actually goes.
#
# Usage:  perl sim/daily-job-sim.pl [--teams N] [--people-per-team N] [--seed N]
use strict;
use warnings;
use Getopt::Long;

my %o = (teams => 10, people_per_team => 10, seed => 42, workday_min => 480);
GetOptions(\%o, 'teams=i', 'people_per_team=i', 'seed=i', 'workday_min=i') or exit 2;
srand($o{seed});

# ---- the sprint's fixed calendar (per docs/WORKFLOW.html #3: sprints start Wed, end Tue;
# day numbers skip weekends, so 4/5/11/12 don't appear)
my @DAYS = (
    { day => 1,  wd => 'Wed', label => 'Planning' },
    { day => 2,  wd => 'Thu', label => 'Townhall begins' },
    { day => 3,  wd => 'Fri', label => 'Townhall + weekly status mail' },
    { day => 6,  wd => 'Mon', label => 'Townhall + refinement prep' },
    { day => 7,  wd => 'Tue', label => 'Townhall' },
    { day => 8,  wd => 'Wed', label => 'Townhall + mid-sprint health check' },
    { day => 9,  wd => 'Thu', label => 'Townhall + Master backlog refinement' },
    { day => 10, wd => 'Fri', label => 'Townhall + weekly status mail' },
    { day => 13, wd => 'Mon', label => 'Townhall + pre-review sweep' },
    { day => 14, wd => 'Tue', label => 'Review/demo + retro + sprint close' },
);

# ---- per-team-per-day random flag generation (mirrors what Answers.pm actually raises:
# blocked / silent / stuck). Rates are illustrative -- tune to your real teams once you
# have a sprint or two of real data; that's the whole point of running this again later
# with --seed unset against actual numbers instead of these priors.
sub team_flags {                              # -> (blocked, silent, stuck) counts for one team, one day
    my $blocked = (rand() < 0.12) ? 1 + int(rand(2)) : 0;   # ~12% of teams have 1-2 blockers on a given day
    my $silent  = (rand() < 0.06) ? 1 : 0;                   # ~6% of teams have someone go silent
    my $stuck   = (rand() < 0.08) ? 1 : 0;                   # ~8% of teams show a "same plan N days" flag
    ($blocked, $silent, $stuck);
}
sub cross_team_asks {                          # -> number of "say so on the line" integration asks this townhall
    my $n = 0;
    $n++ while rand() < 0.35 && $n < 4;         # geometric-ish: usually 0-1, occasionally more
    $n;
}

my $MIN_TOWNHALL       = 15;    # fixed 08:30-08:45
my $MIN_PIPELINE       = 3;     # paste chat, run chat/answers/compile/report/tree -- your keyboard time, not perl's
my $MIN_PER_FLAG       = 1.5;   # read + decide (escalate / note / ignore) per flag
my $MIN_PER_ASK_LOGGED = 0.5;   # quick "noted, follow up" during the townhall
my $PROB_ASK_ESCALATES = 0.3;   # this fraction of cross-team asks become a real follow-up meeting
my $MIN_ESCALATION     = 30;    # a scheduled follow-up meeting, costed on the day it's raised
my $MIN_STATUS_MAIL    = 8;     # review + send the daily status draft
my %SPECIAL = (1 => 45, 8 => 20, 9 => 45, 14 => 130);   # planning / health-check / refinement / review+retro-skim+report
my %WEEKLY_MAIL_EXTRA  = (3 => 15, 10 => 15);

my (@rows, $sprint_total, $sprint_escalations);
for my $d (@DAYS) {
    my ($blocked_t, $silent_t, $stuck_t, $asks_logged, $escalations) = (0, 0, 0, 0, 0);
    for (1 .. $o{teams}) {
        my ($b, $s, $st) = team_flags();
        $blocked_t += $b; $silent_t += $s; $stuck_t += $st;
    }
    my $asks = cross_team_asks();
    for (1 .. $asks) { rand() < $PROB_ASK_ESCALATES ? $escalations++ : $asks_logged++ }

    my $flags     = $blocked_t + $silent_t + $stuck_t;
    my $triage    = $flags * $MIN_PER_FLAG;
    my $coord     = $asks_logged * $MIN_PER_ASK_LOGGED + $escalations * $MIN_ESCALATION;
    my $special   = $SPECIAL{ $d->{day} } // 0;
    my $mail_extra = $WEEKLY_MAIL_EXTRA{ $d->{day} } // 0;
    my $total     = $MIN_TOWNHALL + $MIN_PIPELINE + $triage + $coord + $MIN_STATUS_MAIL + $special + $mail_extra;
    my $deep_work = $o{workday_min} - $total;

    push @rows, { %$d, blocked => $blocked_t, silent => $silent_t, stuck => $stuck_t, flags => $flags,
                  triage => $triage, asks => $asks, escalations => $escalations, coord => $coord,
                  special => $special, mail_extra => $mail_extra, total => $total, deep_work => $deep_work };
    $sprint_total += $total;
    $sprint_escalations += $escalations;
}

printf "Simulated sprint: %d teams x %d people = %d people, seed=%d\n\n", $o{teams}, $o{people_per_team}, $o{teams} * $o{people_per_team}, $o{seed};
printf "%-4s %-4s %-36s %6s %6s %6s %6s %6s %8s %8s\n", 'Day', 'Wd', 'Event', 'Flags', 'Triage', 'Coord', 'Spec', 'Mail', 'Process', 'DeepWork';
for my $r (@rows) {
    printf "%-4d %-4s %-36s %6d %6.1f %6.1f %6d %6d %8.1f %8.1f\n",
        $r->{day}, $r->{wd}, $r->{label}, $r->{flags}, $r->{triage}, $r->{coord}, $r->{special}, $r->{mail_extra}, $r->{total}, $r->{deep_work};
}

my $avg_total = $sprint_total / @rows;
my $avg_deep  = $o{workday_min} - $avg_total;
printf "\nSprint totals over %d workdays:\n", scalar @rows;
printf "  process time:     %.0f min (%.1f hrs)  --  avg %.0f min/day (%.1f hrs/day)\n", $sprint_total, $sprint_total / 60, $avg_total, $avg_total / 60;
printf "  deep-work time:   %.0f min (%.1f hrs)  --  avg %.0f min/day (%.1f hrs/day), out of an %.0f-min day\n",
    $o{workday_min} * @rows - $sprint_total, ($o{workday_min} * @rows - $sprint_total) / 60, $avg_deep, $avg_deep / 60, $o{workday_min};
printf "  follow-up meetings spawned this sprint: %d (30 min each, schedule separately -- not counted in the day they land on above)\n", $sprint_escalations;
printf "\nNote: the townhall (15) + pipeline run (%d) + status mail (%d) = %d min/day is FIXED regardless of team count --\n", $MIN_PIPELINE, $MIN_STATUS_MAIL, $MIN_TOWNHALL + $MIN_PIPELINE + $MIN_STATUS_MAIL;
print "the only cost that scales with your 10 teams is triage + coordination, and that's driven by flag/ask RATES, not raw people count.\n";
print "Re-run with --seed unset (or a real seed) and, once you have real sprint data, replace the priors in team_flags()/cross_team_asks()\n";
print "with your actual observed rates for a forecast instead of a guess.\n";
