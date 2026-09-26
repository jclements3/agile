package Metrics;
# The operating model's metrics (docs/WORKFLOW.html #6), computed from the journal and checked against the thresholds
# that trigger action -- in one place, so the status mail, the dashboard, the cockpit, the sprint report and
# `daily.pl health` all say the same thing. Nothing is typed and nothing is cached: every figure is re-derived from the
# journal (plus the chat, answers and attendance files daily.pl hands in for the three metrics that live there).
#
#     signals($s, %o)            -> ( { level => red|amber|info, metric, team, text }, ... ), red first
#     table($s)                  -> [ { team, pct, load, velocity, trend, predictability, carryover, ontime, interrupt, top_share, blocked, oldest_block } ]
#     team_history($s)           -> { team => [ { sprint, committed, done, carryover, capacity, load, pct, interrupt, complete } ] }
#     intake_by_sprint($s)       -> { N => SP entered while sprint N ran }
#     sprint_report_text/html($s, $n, %o)   the Day-14 report: sprint N per team, velocity, predictability, carryover, epics
#     rollup($s, $month, %o) + rollup_text/html   the monthly roll-up: epics, intake vs done, backlog age, attendance
#     csv($s, $what, %o)         items | sprints | epics | intake | health  -> CSV text for Excel (scrum.pl csv, daily.pl csv)
#
# Thresholds (%T) are the operating model's; each check names what to do, not just what it saw.
use strict;
use warnings;
use Prelude qw(sorted nub sum);
use Scrum qw(items sprint_summary velocity blocked blocked_days backlog unassigned roadmap days_between epics);
use Quad qw(sprint_span sprint_end_date punt_rate add_days);

our @EXPORT = qw(signals table team_history intake_by_sprint sprint_report_text sprint_report_html rollup rollup_text rollup_html csv read_attendance sprint_day);
sub import {
    my ($class, @want) = @_;
    my $caller = caller;
    no strict 'refs';
    for my $n (@want ? @want : @EXPORT) {
        die "Metrics: unknown function '$n'\n" unless defined &{"Metrics::$n"};
        *{"${caller}::$n"} = \&{"Metrics::$n"};
    }
}

our %T = (day8 => 8, day8_pct => 60, predict => 80, load_hi => 110, load_lo => 70, carry => 20, block_amber => 3, block_red => 5,
          depth_lo => 2, depth_hi => 8, age => 90, intake_sprints => 3, consensus => 50, consensus_min => 4, ontime => 80, ontime_min => 5,
          punt => 20, bus => 40, bus_min => 3, discipline_days => 3, sprint_days => 14, last => 3);
my %RANK = (red => 0, amber => 1, info => 2);

sub _pct { my ($a, $b) = @_; $b ? int(100 * $a / $b + 0.5) : undef }

# ---------------------------------------------------------------- the series the checks read
sub team_history {                            # per team, every sprint it took part in, oldest first; complete = not the running sprint with work still open
    my $s = shift;
    return $s->{_memo}{team_history} if $s->{_memo}{team_history};
    my %int;                                  # interrupt SP: new! tasks (meta interrupt), by the sprint and team they were committed straight into
    for my $it (grep { $_->{meta}{interrupt} } items($s)) {
        my ($h) = grep { $_->{points} > 0 && $_->{account} =~ /:Committed$/ } @{ $it->{history} } or next;
        my ($n, $t) = $h->{account} =~ /^Sprint:(\d+):([^:]+):/ or next;
        $int{$n}{$t} += $h->{points};
    }
    my %h;
    for my $n (@{ $s->{sprints} }) {
        my $r = sprint_summary($s, $n);
        for my $t (sorted(keys %{ $r->{teams} })) {
            my $x = $r->{teams}{$t};
            push @{ $h{$t} }, { sprint => $n, (map { $_ => $x->{$_} } qw(committed done carryover capacity load pct open)), interrupt => $int{$n}{$t} // 0,
                                complete => (defined $s->{current} && $n == $s->{current} && $x->{open} > 0) ? 0 : 1 };
        }
    }
    $s->{_memo}{team_history} = \%h;
}
sub _complete { my ($s, $t) = @_; grep { $_->{complete} } @{ team_history($s)->{$t} // [] } }
sub sprint_day {                              # day of the running sprint, 1-based (Day 8 = the mid-sprint check), or undef
    my $s = shift;
    my $cur = $s->{current} // return undef;
    my $start = sprint_span($s)->{$cur}{start} // return undef;
    days_between($start, $s->{today}) + 1;
}
sub _sprint_of_date {                         # the sprint running on a date: the latest one started by then
    my ($span, $date) = @_;
    my ($n) = sort { $b <=> $a } grep { ($span->{$_}{start} // '9999') le $date } keys %$span;
    $n;
}
sub intake_by_sprint {                        # SP entered (a task's first positive posting) while each sprint ran
    my $s = shift;
    my $span = sprint_span($s);
    my %in;
    for my $it (items($s)) {
        my ($h) = grep { $_->{points} > 0 } @{ $it->{history} } or next;
        my $n = _sprint_of_date($span, $h->{date}) // next;
        $in{$n} += $h->{points};
    }
    \%in;
}
sub _ontime { my $it = shift; my @d = grep { $_->{account} =~ /:Done$/ && $_->{points} > 0 } @{ $it->{history} }; (@d <= 1 && !grep { $_->{account} =~ /:Carryover$/ && $_->{points} > 0 } @{ $it->{history} }) ? 1 : 0 }
sub _owner_shares {                           # (team, sprint) -> sorted [ [owner, SP, share%] ] of what was committed this sprint
    my ($s, $t, $n) = @_;
    my (%by, $tot);
    for my $it (items($s, team => $t)) {
        my $pts = sum(map { $_->{points} } grep { $_->{points} > 0 && $_->{account} eq "Sprint:$n:$t:Committed" } @{ $it->{history} }) or next;
        $by{ $it->{owner} // '(unassigned)' } += $pts; $tot += $pts;
    }
    [ sort { $b->[1] <=> $a->[1] || $a->[0] cmp $b->[0] } map { [ $_, $by{$_}, _pct($by{$_}, $tot) ] } keys %by ];
}

# ---------------------------------------------------------------- the table: one row per team, every metric that has a number
sub table {
    my ($s, %o) = @_;
    my $cur = $s->{current};
    my $r = defined $cur ? sprint_summary($s, $cur) : { teams => {} };
    my $v = velocity($s);
    my @rows;
    for my $t (sorted(keys %{ $r->{teams} })) {
        next if $o{team} && $t ne $o{team};
        my $x = $r->{teams}{$t};
        my @c = _complete($s, $t); my @l3 = @c > $T{last} ? @c[ -$T{last} .. -1 ] : @c;
        my @done = grep { $_->{state} eq 'done' && ($_->{sprint} // -1) == $cur } items($s, team => $t);
        my @bl = blocked($s, $t);
        my $sh = _owner_shares($s, $t, $cur);
        my ($now) = grep { $_->{sprint} == $cur } @{ team_history($s)->{$t} // [] };
        push @rows, { team => $t, pct => $x->{pct}, load => $x->{load}, velocity => sprintf('%.1f', $v->{avg}{$t} // 0),
                      trend => join(' ', map { $_->{done} } @l3), predictability => _pct(sum(map { $_->{done} } @l3), sum(map { $_->{committed} } @l3)),
                      carryover => (@c ? _pct($c[-1]{carryover}, $c[-1]{committed}) : undef), ontime => _pct(scalar(grep { _ontime($_) } @done), scalar @done),
                      interrupt => $now ? $now->{interrupt} : 0, top_share => (@$sh ? "$sh->[0][2]" : undef), blocked => scalar @bl,
                      oldest_block => (@bl ? (sort { $b <=> $a } map { blocked_days($s, $_) } @bl)[0] : undef) };
    }
    \@rows;
}

# ---------------------------------------------------------------- the checks
sub signals {                                 # signals($s, team => T, prev => $s_week_ago, prev2 => $s_two_weeks_ago, est_rounds => [tallies], attendance => [rows], answer_days => {T => [recs]}, rosters => {T => [names]})
    my ($s, %o) = @_;
    my @sig;
    my $add = sub { my ($level, $metric, $team, $text) = @_; push @sig, { level => $level, metric => $metric, team => $team, text => $text } };
    my $cur = $s->{current};
    my $today = $s->{today};
    my $mine = sub { !$o{team} || ($_[0] // '') eq $o{team} };
    my $r = defined $cur ? sprint_summary($s, $cur) : { teams => {} };
    my @teams = grep { $mine->($_) } sorted(keys %{ $r->{teams} });

    # blocked age: > 3 days escalate, > 5 it is yours (and on the weekly mail by name)
    for my $it (sort { blocked_days($s, $b) <=> blocked_days($s, $a) } grep { $mine->($_->{team}) } blocked($s)) {
        my $d = blocked_days($s, $it);
        next unless $d > $T{block_amber};
        $add->($d > $T{block_red} ? 'red' : 'amber', 'blocked', $it->{team}, "$it->{id}" . ($it->{owner} ? " ($it->{owner})" : '') . " blocked $d days: $it->{blocked} -- "
            . ($d > $T{block_red} ? 'over 5 days: your problem, on the weekly mail by name' : 'escalate across teams'));
    }
    # load at planning: > 110% cut, < 70% pull from master
    for my $t (@teams) {
        my $l = $r->{teams}{$t}{load} // next;
        $add->('red', 'load', $t, "load $l% of capacity (over $T{load_hi}%): cut the commitment") if $l > $T{load_hi};
        $add->('amber', 'load', $t, "load $l% of capacity (under $T{load_lo}%): pull work from the master backlog") if $l < $T{load_lo};
    }
    # mid-sprint: < 60% done by Day 8
    my $day = sprint_day($s);
    if (defined $day && $day >= $T{day8} && $day <= $T{sprint_days}) {
        for my $t (@teams) { my $x = $r->{teams}{$t}; next unless $x->{committed} && $x->{open} > 0;
            $add->('red', 'done by day 8', $t, "sprint day $day: $x->{pct}% done (under $T{day8_pct}% by Day $T{day8}): descope or swarm") if $x->{pct} < $T{day8_pct} }
    }
    # velocity, predictability, carryover: over completed sprints
    my $v = velocity($s);
    for my $t (@teams) {
        my @c = _complete($s, $t);
        my @l3 = @c > $T{last} ? @c[ -$T{last} .. -1 ] : @c;
        if (@l3 == 3 && $l3[0]{done} > $l3[1]{done} && $l3[1]{done} > $l3[2]{done}) {
            $add->('amber', 'velocity', $t, 'velocity down two sprints running (' . join(' -> ', map { $_->{done} } @l3) . '): look for hidden blockers');
        }
        my $p = @l3 >= 2 ? _pct(sum(map { $_->{done} } @l3), sum(map { $_->{committed} } @l3)) : undef;
        $add->('amber', 'predictability', $t, sprintf('predictability %d%% over the last %d sprints (under %d%%): over-committing; cap the next commitment at velocity (%.0f)', $p, scalar @l3, $T{predict}, $v->{avg}{$t} // 0))
            if defined $p && $p < $T{predict};
        my @l2 = @c >= 2 ? @c[-2, -1] : ();
        my @cr = map { _pct($_->{carryover}, $_->{committed}) // 0 } @l2;
        $add->('amber', 'carryover', $t, "carryover $cr[0]% and $cr[1]% in sprints $l2[0]{sprint} and $l2[1]{sprint} (over $T{carry}% two sprints running): tasks too big; split at refinement")
            if @l2 && $cr[0] > $T{carry} && $cr[1] > $T{carry};
    }
    # WIP per person: one person over 40% of the team's commitment is a bus factor
    for my $t (@teams) {
        my $sh = _owner_shares($s, $t, $cur);
        my @people = grep { $_->[0] ne '(unassigned)' } @$sh;
        $add->('amber', 'bus factor', $t, "$people[0][0] holds $people[0][2]% of the sprint commitment (over $T{bus}%): spread the knowledge") if @people >= $T{bus_min} && $people[0][2] > $T{bus};
    }
    # unassigned
    for my $t (@teams) { my @u = unassigned($s, $t); $add->('amber', 'unassigned', $t, scalar(@u) . ' committed task' . (@u == 1 ? '' : 's') . ' with no owner (' . join(' ', map { $_->{id} } @u) . '): fix at the next stand-up') if @u }
    # on-time delivery this sprint
    for my $t (@teams) {
        my @done = grep { $_->{state} eq 'done' && ($_->{sprint} // -1) == $cur } items($s, team => $t);
        next unless @done >= $T{ontime_min};
        my $p = _pct(scalar(grep { _ontime($_) } @done), scalar @done);
        $add->('amber', 'on-time', $t, "on-time delivery $p% this sprint (under $T{ontime}%): tasks too big or started too late; split at refinement") if $p < $T{ontime};
    }
    # punt rate: > 20% two sprints running
    my %pr; push @{ $pr{ $_->{team} } }, $_ for grep { $_->{team} ne 'Total' } @{ punt_rate($s) };
    for my $t (grep { $mine->($_) } sorted(keys %pr)) {
        my %done = map { $_->{sprint} => 1 } _complete($s, $t);   # finished sprints only: a running sprint's punt rate is not in yet
        my @r = grep { $done{ $_->{sprint} } } @{ $pr{$t} }; next unless @r >= 2;
        $add->('amber', 'punt rate', $t, "punt rate $r[-2]{rate}% and $r[-1]{rate}% (over $T{punt}% two sprints running): tasks arrive under-specified; refine before committing")
            if $r[-2]{rate} > $T{punt} && $r[-1]{rate} > $T{punt};
    }
    # interrupts: new! straight into the sprint -- info, so the sprint report can say what the commitment absorbed
    for my $t (@teams) {
        my ($now) = grep { $_->{sprint} == $cur } @{ team_history($s)->{$t} // [] };
        $add->('info', 'interrupts', $t, "$now->{interrupt} SP of interrupts (new!) this sprint, " . (_pct($now->{interrupt}, $r->{teams}{$t}{committed}) // 0) . '% of the commitment') if $now && $now->{interrupt};
    }
    # sprint progress degrading two weeks running (against the journal a week and two weeks ago)
    if ($o{prev} && $o{prev2} && defined $cur) {
        for my $t (@teams, ($o{team} ? () : undef)) {
            my @p = map { my $x = sprint_summary($_, $cur); defined $t ? $x->{teams}{$t}{pct} : $x->{totals}{pct} } $s, $o{prev}, $o{prev2};
            next if grep { !defined } @p;
            $add->('amber', 'sprint progress', $t, "sprint progress degrading two weeks running ($p[2]% -> $p[1]% -> $p[0]%): the commitment was wrong, not the team") if $p[0] < $p[1] && $p[1] < $p[2];
        }
    }
    unless ($o{team}) {
        # backlog depth: backlog SP (master + the teams' refined backlogs) / total velocity
        my $vel = sum(values %{ $v->{avg} });
        my $queued = sum(map { $_->{points} } grep { $_->{state} eq 'backlog' || $_->{state} eq 'master' } items($s));
        if ($vel > 0) {
            my $d = $queued / $vel;
            $add->('amber', 'backlog depth', undef, sprintf('the backlog (master + teams) is %.1f sprints of work (under %d): intake starved; ask for more', $d, $T{depth_lo})) if $d < $T{depth_lo};
            $add->('amber', 'backlog depth', undef, sprintf('the backlog (master + teams) is %.1f sprints of work (over %d): prune it', $d, $T{depth_hi})) if $d > $T{depth_hi};
        }
        # intake vs done: intake above done three completed sprints running
        my $in = intake_by_sprint($s);
        my @done_n = grep { my $n = $_; !grep { !$_->{complete} } map { grep { $_->{sprint} == $n } @$_ } values %{ team_history($s) } } @{ $s->{sprints} };
        my @l = @done_n > $T{intake_sprints} ? @done_n[ -$T{intake_sprints} .. -1 ] : @done_n;
        if (@l == $T{intake_sprints} && !grep { ($in->{$_} // 0) <= sprint_summary($s, $_)->{totals}{done} } @l) {
            my $all = sum(map { $_->{points} } grep { $_->{state} eq 'backlog' || $_->{state} eq 'master' } items($s));
            $add->('amber', 'intake vs done', undef, 'intake exceeded done three sprints running (' . join(', ', map { "$_: " . ($in->{$_} // 0) . '/' . sprint_summary($s, $_)->{totals}{done} } @l) . ')'
                . ($vel > 0 ? sprintf(': at current velocity this is %.0f sprints of work; leadership decides what to cut', $all / $vel) : ''));
        }
        # epic burn against its target (target: YYYY-MM-DD on any of its tasks)
        my %target; for my $it (items($s)) { my $e = $it->{meta}{epic} // next; my $tg = $it->{meta}{target} // next; $target{$e} = $tg if !$target{$e} || $tg lt $target{$e} }
        for my $e (grep { $target{ $_->{epic} } && $_->{remaining} > 0 } @{ roadmap($s)->{epics} }) {
            my $eta = defined $e->{end} ? sprint_end_date($s, $e->{end}) : undef;
            if (!$eta) { $add->('amber', 'epic target', undef, "$e->{epic}: $e->{remaining} SP left and no velocity to forecast it; target $target{ $e->{epic} }") if $target{ $e->{epic} } lt add_days($today, 90); next }
            $add->('amber', 'epic target', undef, "$e->{epic}: ETA $eta is past its target $target{ $e->{epic} }: re-scope, re-assign across teams, or move the date") if $eta gt $target{ $e->{epic} };
        }
    }
    # backlog age: > 90 days in a backlog -- schedule or remove
    {   my @old = sort { $b->{age} <=> $a->{age} } grep { ($_->{state} eq 'backlog' || $_->{state} eq 'master') && $_->{age} > $T{age} && $mine->($_->{team}) } items($s);
        $add->('amber', 'backlog age', $o{team}, scalar(@old) . " backlog task" . (@old == 1 ? '' : 's') . " older than $T{age} days (oldest " . join(', ', map { "$_->{id} $_->{age}d" } @old[0 .. ($#old < 2 ? $#old : 2)]) . '): schedule or remove') if @old;
    }
    # estimate consensus rate (chat #est rounds this sprint)
    {   my @est = grep { $_->{kind} eq 'est' && defined $_->{median} } @{ $o{est_rounds} // [] };
        my $c = grep { $_->{consensus} } @est;
        $add->('amber', 'consensus', $o{team}, sprintf('estimate consensus in %d of %d #est rounds (%d%%, under %d%%): tasks under-specified; refine before estimating', $c, scalar @est, _pct($c, scalar @est), $T{consensus}))
            if @est >= $T{consensus_min} && _pct($c, scalar @est) < $T{consensus};
    }
    # attendance: calendar declines rising three weeks running
    if ($o{attendance} && @{ $o{attendance} }) {
        my @w = map { my $hi = add_days($today, -7 * $_); my $lo = add_days($hi, -6); scalar grep { $_->{status} eq 'declined' && $_->{date} ge $lo && $_->{date} le $hi && $mine->($_->{team}) } @{ $o{attendance} } } 0 .. 2;
        $add->('amber', 'attendance', $o{team}, "calendar declines rising three weeks running ($w[2] -> $w[1] -> $w[0]): the meeting time may be wrong") if $w[2] < $w[1] && $w[1] < $w[0];
    }
    # answer discipline: silent or incomplete 3 days running
    for my $t (grep { $mine->($_) } sorted(keys %{ $o{answer_days} // {} })) {
        my @days = @{ $o{answer_days}{$t} }[0 .. $T{discipline_days} - 1];
        next if grep { !defined } @days;
        for my $who (@{ $o{rosters}{$t} // [] }) {
            my $bad = grep { my $d = $_; my ($a) = grep { $_->{who} eq $who } @{ $d->{answers} }; !$a || $a->{assumed} || !$a->{complete} } @days;
            $add->('amber', 'answers', $t, "$who silent or incomplete $T{discipline_days} days running: talk to the lead") if $bad == $T{discipline_days};
        }
    }
    sort { $RANK{ $a->{level} } <=> $RANK{ $b->{level} } } @sig;
}

# ---------------------------------------------------------------- the sprint report (Day 14): sprint N, velocity, predictability, carryover, epics
sub _sprint_report {
    my ($s, $n) = @_;
    my $r = sprint_summary($s, $n);
    my $v = velocity($s);
    my $th = team_history($s);
    my @teams = map { my $t = $_; my $x = $r->{teams}{$t};
        my @c = grep { $_->{complete} && $_->{sprint} <= $n } @{ $th->{$t} // [] }; my @l3 = @c > $T{last} ? @c[ -$T{last} .. -1 ] : @c;
        my ($row) = grep { $_->{sprint} == $n } @{ $th->{$t} // [] };
        { team => $t, (map { $_ => $x->{$_} } qw(committed done carryover removed open capacity load pct)), interrupt => $row ? $row->{interrupt} : 0,
          velocity => sprintf('%.1f', $v->{avg}{$t} // 0), predictability => _pct(sum(map { $_->{done} } @l3), sum(map { $_->{committed} } @l3)),
          carry_rate => _pct($x->{carryover}, $x->{committed}), punted => scalar(grep { ($_->{sprint} // -1) == $n && $_->{team} eq $t } map { @{ $_->{punts} // [] } } items($s)) } } sorted(keys %{ $r->{teams} });
    my @ep = grep { $_->{remaining} > 0 || grep { $_ == $n } $_->{first} .. ($_->{last} // $_->{first}) } @{ roadmap($s)->{epics} };
    { sprint => $n, as_of => $s->{today}, totals => $r->{totals}, teams => \@teams, epics => \@ep, unit => $s->{unit} // 'SP' };
}
sub sprint_report_text {
    my ($s, $n, %o) = @_;
    $n //= $s->{current};
    my $x = _sprint_report($s, $n);
    my $t = $x->{totals};
    my $out = sprintf "Sprint %s report -- as of %s: %d/%d %s done (%d%%), %d carried over, %d removed.\n\n", $n, $x->{as_of}, $t->{done}, $t->{committed}, $x->{unit}, $t->{pct}, $t->{carryover}, $t->{removed};
    $out .= sprintf "%-14s %6s %5s %6s %6s %6s %6s %8s %9s %7s %9s %6s\n", qw(Team Commit Done Done% Carry Carry% Load Velocity Predict% Punted Interrupt Cap);
    $out .= sprintf "%-14s %6s %5s %5s%% %6s %5s%% %6s %8s %8s%% %7s %9s %6s\n", $_->{team}, $_->{committed}, $_->{done}, $_->{pct}, $_->{carryover}, $_->{carry_rate} // '-', defined $_->{load} ? "$_->{load}%" : '-',
        $_->{velocity}, $_->{predictability} // '-', $_->{punted}, $_->{interrupt}, $_->{capacity} || '-' for @{ $x->{teams} };
    $out .= "\nEpics (remaining / team velocity = sprints to done):\n";
    $out .= sprintf "  %-40s %4d%%  %4d SP left  %s\n", "$_->{tome} > $_->{epic}", $_->{pct}, $_->{remaining}, defined $_->{end} ? "ETA sprint $_->{end}" . ($_->{blocked} ? ", $_->{blocked} blocked" : '') : 'no forecast' for @{ $x->{epics} };
    my @sig = grep { $_->{metric} =~ /^(velocity|predictability|carryover|punt rate|on-time|epic target|interrupts)$/ } signals($s);
    $out .= "\n" . Scrum::health_text(\@sig, all => 1) if @sig;
    Scrum::marked_text($o{marking}, $out);
}
sub sprint_report_html {
    my ($s, $n, %o) = @_;
    $n //= $s->{current};
    my $x = _sprint_report($s, $n);
    my $t = $x->{totals};
    my $h = \&Scrum::_h;
    my $td = 'style="border:1px solid #bbb;padding:3px 8px"'; my $tdn = 'style="border:1px solid #bbb;padding:3px 8px;text-align:right"';
    my $html = "<!DOCTYPE html>\n<html><head><meta charset=\"utf-8\"><title>Sprint $n report</title></head><body style=\"font-family:Segoe UI,Arial,sans-serif;font-size:14px\">\n" . Scrum::mark_banner_html($o{marking}, 'top') . Scrum::mark_block_html($o{marking});
    $html .= "<h1 style=\"font-size:20px\">" . Scrum::logo_svg() . "Sprint $n report <span style=\"color:#666;font-weight:normal\">as of " . $h->($x->{as_of}) . "</span></h1>\n";
    $html .= sprintf "<p><b>%d of %d %s done (%d%%)</b>, %d carried over, %d removed.</p>\n", $t->{done}, $t->{committed}, $h->($x->{unit}), $t->{pct}, $t->{carryover}, $t->{removed};
    my @c = ([ team => 'Team' ], [ committed => 'Commit' ], [ done => 'Done' ], [ pct => 'Done%' ], [ carryover => 'Carry' ], [ carry_rate => 'Carry%' ], [ load => 'Load%' ], [ velocity => 'Velocity (avg 3)' ],
             [ predictability => 'Predictability%' ], [ punted => 'Punted' ], [ interrupt => 'Interrupt SP' ], [ capacity => 'Capacity' ]);
    $html .= "<table style=\"border-collapse:collapse\"><tr>" . join('', map { $_->[0] eq 'team' ? "<th $td>$_->[1]</th>" : "<th $tdn>$_->[1]</th>" } @c) . "</tr>\n";
    for my $row (@{ $x->{teams} }) {
        $html .= '<tr>' . join('', map { my $val = $row->{ $_->[0] }; my $bad = ($_->[0] eq 'predictability' && defined $val && $val < $T{predict}) || ($_->[0] eq 'carry_rate' && defined $val && $val > $T{carry}) || ($_->[0] eq 'load' && defined $val && ($val > $T{load_hi} || $val < $T{load_lo}));
            $_->[0] eq 'team' ? "<td $td>" . $h->($val) . '</td>' : "<td $tdn>" . ($bad ? '<b style="color:#c98500">' : '') . (defined $val && $val ne '' ? $h->($val) : '&ndash;') . ($bad ? '</b>' : '') . '</td>' } @c) . "</tr>\n";
    }
    $html .= "</table>\n<h2 style=\"font-size:16px\">Epics <span style=\"color:#666;font-weight:normal\">remaining &divide; team velocity = sprints to done</span></h2>\n<table style=\"border-collapse:collapse\"><tr><th $td>Tome</th><th $td>Epic</th><th $tdn>Done%</th><th $tdn>SP left</th><th $td>ETA</th></tr>\n";
    $html .= join('', map { "<tr><td $td>" . $h->($_->{tome}) . "</td><td $td>" . $h->($_->{epic}) . "</td><td $tdn>$_->{pct}%</td><td $tdn>$_->{remaining}</td><td $td>" . (defined $_->{end} ? "sprint $_->{end}" . ($_->{blocked} ? " ($_->{blocked} blocked)" : '') : 'no forecast') . "</td></tr>\n" } @{ $x->{epics} }) . "</table>\n";
    my @sig = grep { $_->{metric} =~ /^(velocity|predictability|carryover|punt rate|on-time|epic target|interrupts)$/ } signals($s);
    $html .= Scrum::health_mail_html(\@sig) if @sig;
    $html . Scrum::mark_banner_html($o{marking}, 'bottom') . "</body></html>\n";
}

# ---------------------------------------------------------------- the monthly roll-up: epics, intake vs done, backlog age, attendance
sub read_attendance {                         # attendance.csv -> [ { date, team, name, status, minutes } ]
    my $file = shift;
    open my $fh, '<:encoding(UTF-8)', $file or return [];
    my @r;
    while (my $l = <$fh>) {
        chomp $l; $l =~ s/\r$//; next if $. == 1 && $l =~ /^date,/; next unless $l =~ /\S/;
        my @f = $l =~ /("(?:[^"]|"")*"|[^,]*)(?:,|$)/g; s/^"|"$//g for @f;
        push @r, { date => $f[0], team => $f[1], name => $f[2], status => $f[3] // '', minutes => $f[6] };
    }
    close $fh;
    \@r;
}
sub rollup {                                  # rollup($s, 'YYYY-MM', attendance => [rows]) -> { month, epics, sprints => [ {sprint, intake, done} ], age => {bucket => [n, SP]}, attendance => { team => {status => n} } }
    my ($s, $month, %o) = @_;
    $month //= substr($s->{today}, 0, 7);
    my $span = sprint_span($s);
    my $in = intake_by_sprint($s);
    my @sp = grep { my $x = $span->{$_}; substr($x->{start}, 0, 7) le $month && substr($x->{end}, 0, 7) ge $month } sort { $a <=> $b } keys %$span;
    my %age;
    for my $it (grep { $_->{state} eq 'backlog' || $_->{state} eq 'master' } items($s)) {
        my $b = $it->{age} <= 30 ? '0-30' : $it->{age} <= 60 ? '31-60' : $it->{age} <= 90 ? '61-90' : 'over 90';
        $age{$b}[0]++; $age{$b}[1] += $it->{points};
    }
    my %att;
    $att{ $_->{team} || '?' }{ $_->{status} }++ for grep { substr($_->{date}, 0, 7) eq $month } @{ $o{attendance} // [] };
    { month => $month, as_of => $s->{today}, unit => $s->{unit} // 'SP', epics => [ epics($s) ],
      sprints => [ map { { sprint => $_, start => $span->{$_}{start}, intake => $in->{$_} // 0, done => sprint_summary($s, $_)->{totals}{done} } } @sp ],
      age => \%age, attendance => \%att };
}
our @AGE = ('0-30', '31-60', '61-90', 'over 90');
our @ATT = ('answered', 'present', 'brief', 'accepted', 'tentative', 'declined', 'no response');
sub rollup_text {
    my ($s, $month, %o) = @_;
    my $x = rollup($s, $month, %o);
    my $out = "Monthly roll-up $x->{month} -- as of $x->{as_of}\n\nEPICS\n";
    $out .= sprintf "  %-40s %4d%%  %4d/%-4d %s\n", "$_->{tome} > $_->{epic}", $_->{pct}, $_->{done}, $_->{total}, $x->{unit} for @{ $x->{epics} };
    $out .= "\nINTAKE VS DONE (sprints running this month)\n";
    $out .= sprintf "  sprint %-4s from %s  intake %4d  done %4d%s\n", $_->{sprint}, $_->{start}, $_->{intake}, $_->{done}, $_->{intake} > $_->{done} ? '  (backlog grew)' : '' for @{ $x->{sprints} };
    $out .= "  no sprints this month\n" unless @{ $x->{sprints} };
    $out .= "\nBACKLOG AGE (days since intake, tasks still in a backlog)\n";
    $out .= sprintf "  %-8s %4d tasks  %5d %s\n", $_, @{ $x->{age}{$_} // [0, 0] }, $x->{unit} for @AGE;
    $out .= "\nATTENDANCE (attendance.csv rows this month)\n";
    for my $t (sorted(keys %{ $x->{attendance} })) { my $a = $x->{attendance}{$t}; $out .= "  $t: " . join(', ', map { "$_ $a->{$_}" } grep { $a->{$_} } @ATT, grep { my $k = $_; !grep { $_ eq $k } @ATT } sorted(keys %$a)) . "\n" }
    $out .= "  no attendance rows this month\n" unless %{ $x->{attendance} };
    Scrum::marked_text($o{marking}, $out);
}
sub rollup_html {
    my ($s, $month, %o) = @_;
    my $x = rollup($s, $month, %o);
    my $h = \&Scrum::_h;
    my $td = 'style="border:1px solid #bbb;padding:3px 8px"'; my $tdn = 'style="border:1px solid #bbb;padding:3px 8px;text-align:right"';
    my $tab = sub { my ($hdr, $rows, $num) = @_; "<table style=\"border-collapse:collapse;margin-bottom:12px\"><tr>" . join('', map { "<th " . ($num->{$_} ? $tdn : $td) . '>' . $h->($hdr->[$_]) . '</th>' } 0 .. $#$hdr) . "</tr>\n"
        . join('', map { my $r = $_; '<tr>' . join('', map { '<td ' . ($num->{$_} ? $tdn : $td) . '>' . $h->($r->[$_] // '') . '</td>' } 0 .. $#$r) . "</tr>\n" } @$rows) . "</table>\n" };
    my $html = "<!DOCTYPE html>\n<html><head><meta charset=\"utf-8\"><title>Roll-up $x->{month}</title></head><body style=\"font-family:Segoe UI,Arial,sans-serif;font-size:14px\">\n" . Scrum::mark_banner_html($o{marking}, 'top') . Scrum::mark_block_html($o{marking});
    $html .= '<h1 style="font-size:20px">' . Scrum::logo_svg() . "Monthly roll-up $x->{month} <span style=\"color:#666;font-weight:normal\">as of " . $h->($x->{as_of}) . "</span></h1>\n";
    $html .= "<h2 style=\"font-size:16px\">Epics</h2>\n" . $tab->([ 'Tome', 'Epic', 'Done%', 'Done', 'Total' ], [ map { [ $_->{tome}, $_->{epic}, "$_->{pct}%", $_->{done}, $_->{total} ] } @{ $x->{epics} } ], { 2 => 1, 3 => 1, 4 => 1 });
    $html .= "<h2 style=\"font-size:16px\">Intake vs done</h2>\n" . $tab->([ 'Sprint', 'Started', "Intake $x->{unit}", "Done $x->{unit}", '' ], [ map { [ $_->{sprint}, $_->{start}, $_->{intake}, $_->{done}, $_->{intake} > $_->{done} ? 'backlog grew' : '' ] } @{ $x->{sprints} } ], { 2 => 1, 3 => 1 });
    $html .= "<h2 style=\"font-size:16px\">Backlog age</h2>\n" . $tab->([ 'Days since intake', 'Tasks', $x->{unit} ], [ map { [ $_, @{ $x->{age}{$_} // [0, 0] } ] } @AGE ], { 1 => 1, 2 => 1 });
    my @st = nub(@ATT, map { keys %$_ } values %{ $x->{attendance} });
    @st = grep { my $k = $_; grep { $_->{$k} } values %{ $x->{attendance} } } @st;
    $html .= "<h2 style=\"font-size:16px\">Attendance</h2>\n" . (%{ $x->{attendance} } ? $tab->([ 'Team', @st ], [ map { my $t = $_; [ $t, map { $x->{attendance}{$t}{$_} // 0 } @st ] } sorted(keys %{ $x->{attendance} }) ], { map { $_ => 1 } 1 .. @st }) : "<p style=\"color:#666\">no attendance rows this month</p>\n");
    $html . Scrum::mark_banner_html($o{marking}, 'bottom') . "</body></html>\n";
}

# ---------------------------------------------------------------- CSV for Excel (the sprint report's xlsx, the roll-up's pivot)
sub _csvq { my $v = shift // ''; $v =~ /[",\r\n]/ ? do { (my $q = $v) =~ s/"/""/g; qq("$q") } : $v }
sub _csv { my ($hdr, @rows) = @_; join('', map { join(',', map { _csvq($_) } @$_) . "\r\n" } $hdr, @rows) }   # CRLF: what Excel writes and expects
our @CSV = qw(items sprints epics intake health);
sub csv {                                     # csv($s, 'items'|'sprints'|'epics'|'intake'|'health', %signals_opts) -> text
    my ($s, $what, %o) = @_;
    if ($what eq 'items') {
        return _csv([ qw(id title points state team sprint owner prio tome epic age blocked blocked_days created interrupt) ],
            map { [ $_->{id}, $_->{title}, $_->{points}, $_->{state}, $_->{team}, $_->{sprint}, $_->{owner}, $_->{meta}{prio}, $_->{meta}{tome}, $_->{meta}{epic}, $_->{age}, $_->{blocked}, ($_->{blocked} ? blocked_days($s, $_) : ''), $_->{created}, $_->{meta}{interrupt} ? 1 : '' ] } items($s));
    }
    if ($what eq 'sprints') {
        my $th = team_history($s); my $span = sprint_span($s); my $in = intake_by_sprint($s);
        return _csv([ qw(sprint start team capacity committed done carryover pct load carry_rate interrupt complete) ],
            map { my $t = $_; map { [ $_->{sprint}, $span->{ $_->{sprint} }{start}, $t, $_->{capacity}, $_->{committed}, $_->{done}, $_->{carryover}, $_->{pct}, $_->{load}, _pct($_->{carryover}, $_->{committed}), $_->{interrupt}, $_->{complete} ] } @{ $th->{$t} } } sorted(keys %$th));
    }
    if ($what eq 'epics') {
        return _csv([ qw(tome epic tasks total done wip backlog removed pct remaining eta_sprint blocked) ],
            map { my $e = $_; my ($rm) = grep { $_->{epic} eq $e->{epic} && $_->{tome} eq $e->{tome} } @{ roadmap($s)->{epics} }; [ $e->{tome}, $e->{epic}, scalar @{ $e->{items} }, @{$e}{qw(total done wip backlog removed pct)}, $rm ? $rm->{remaining} : '', $rm ? $rm->{end} : '', $rm ? $rm->{blocked} : '' ] } epics($s));
    }
    if ($what eq 'intake') {
        my $span = sprint_span($s); my $in = intake_by_sprint($s);
        return _csv([ qw(sprint start intake done) ], map { [ $_, $span->{$_}{start}, $in->{$_} // 0, sprint_summary($s, $_)->{totals}{done} ] } @{ $s->{sprints} });
    }
    if ($what eq 'health') { return _csv([ qw(level metric team text) ], map { [ @{$_}{qw(level metric team text)} ] } signals($s, %o)) }
    die "csv: unknown table '$what' (" . join(' ', @CSV) . ")\n";
}

1;
