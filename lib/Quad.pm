package Quad;
# The weekly "quad": one page, four quadrants, derived from the journal.
#
#   +----------------------------+----------------------------+
#   | Technical Priorities       | Watch Items / PM Help      |
#   |  the sprint's tasks (OPEN, |  (PM) SWAT: a blocker the  |
#   |  DONE, WAIT, HOLD, DROP    |  program manager must help |
#   |  with REDO/PASS/SYNC marks)|  remove; (WI) SWAT: an     |
#   |  then the TODO list        |  item the PM should know   |
#   +----------------------------+----------------------------+
#   | Schedule Milestones        | Accomplishments            |
#   |  epics by ETA: 30/60/90    |  done this week, on time   |
#   |  days out, priority 1-3,   |  (check) or late (cross);  |
#   |  pushed right / pulled     |  priorities that slipped   |
#   |  left vs last week         |                            |
#   +----------------------------+----------------------------+
#
# Two metrics fall out of it and are shown in the header: Sprint Progress (done / committed, with the trend against
# a week ago) and On-Time Delivery (tasks finished without ever being carried over or reworked / tasks finished).
# Everything is computed from scrum.txt as it stands and as it stood a week ago (Scrum::load with until => date);
# nothing is typed.
#
# The tags -- the owner's four-letter words for work -- and where each comes from:
#   TODO  on the team backlog: planned, not yet in a sprint          OPEN  in a sprint (an epic or tome is OPEN while any task is)
#   DONE  Done this sprint                                            WAIT  blocked by something outside the team (block ID why)
#   HOLD  interrupted by higher-priority work, will resume (hold)     DROP  planned, then found it should not be done (drop)
#   PUNT  in the sprint, found too hard as written, any reason: back on TODO for replanning (punt ID why)
#   REDO  finished, then the demo found it wrong: rework in this sprint (redo ID why)
#   PASS  started by one team, found another should do it: whole task moved to that team (pass ID Team)
#   SYNC  coordinated across teams this sprint; the group shares DONE, none counts until all are (sync ID ID...)
use strict;
use warnings;
use Time::Local qw(timegm);
use Prelude qw(sorted sum nub maximum);
use Scrum;

our @EXPORT;
sub import {
    my ($class, @want) = @_;
    my $caller = caller;
    no strict 'refs';
    for my $n (@want ? @want : @EXPORT) {
        die "Quad: unknown function '$n'\n" unless defined &{"Quad::$n"};
        *{"${caller}::$n"} = \&{"Quad::$n"};
    }
}

our %THRESHOLD = (pm_days => 3, week => 7, sprint_days => 14, horizons => [30, 60, 90], per_horizon => 3, todo_max => 10, punt_sprints => 4, punt_warn => 20);   # blocked > pm_days: PM SWAT (WORKFLOW #6: > 3 days escalate)

sub _ymd { my $t = shift; my @g = gmtime $t; sprintf '%04d-%02d-%02d', $g[5] + 1900, $g[4] + 1, $g[3] }
sub _epoch { my ($y, $m, $d) = split /-/, $_[0]; timegm(0, 0, 0, $d, $m - 1, $y) }
sub add_days { my ($date, $n) = @_; _ymd(_epoch($date) + $n * 86400) }

sub sprint_span {                             # sprint_span($s) -> { N => { start, end } } from the postings; end is the last posting seen for that sprint
    my $s = shift;
    my %span;
    for my $it (values %{ $s->{items} }) {
        for my $h (@{ $it->{history} }) {
            next unless $h->{account} =~ /^Sprint:(\d+):/;
            my $n = $1;
            $span{$n}{start} = $h->{date} if !$span{$n}{start} || $h->{date} lt $span{$n}{start};
            $span{$n}{end}   = $h->{date} if !$span{$n}{end}   || $h->{date} gt $span{$n}{end};
        }
    }
    \%span;
}
sub sprint_end_date {                         # sprint_end_date($s, N) -> the calendar day sprint N ends (planned: start of the current sprint + whole sprints), or undef
    my ($s, $n) = @_;
    my $cur = $s->{current};
    return undef unless defined $n && defined $cur;
    my $span = sprint_span($s);
    my $start = $span->{$cur}{start} or return undef;
    add_days($start, $THRESHOLD{sprint_days} * ($n - $cur + 1) - 1);
}

sub _tag {                                    # ($item, $s) -> (tag, [marks], why)
    my ($it, $s) = @_;
    my $m = $it->{meta};
    my @sync = grep { $_ ne $it->{id} } split ' ', ($m->{sync} // '');
    my @waiting = grep { my $p = $s->{items}{$_}; $p && $p->{state} ne 'done' } @sync;   # partners not Done yet: the group is not DONE
    my $tag = $it->{state} eq 'done'      ? (@waiting ? 'OPEN' : 'DONE')
            : $it->{state} eq 'removed'   ? 'DROP'
            : $it->{state} eq 'backlog'   ? (($m->{punt} // '') ne '' ? 'PUNT' : 'TODO')
            : $it->{state} eq 'master'    ? 'TODO'
            : $it->{blocked}              ? 'WAIT'
            : $it->{hold}                 ? 'HOLD'
            :                               'OPEN';
    my @marks;
    push @marks, 'REDO' if ($m->{redo} // '') ne '' && $it->{state} ne 'done';
    push @marks, 'PASS ' . $m->{pass} if ($m->{pass} // '') ne '' && $it->{state} ne 'done';
    push @marks, 'SYNC ' . join(' ', @sync) . (@waiting ? ' (waiting on ' . join(' ', @waiting) . ')' : '') if @sync;
    push @marks, 'CARRY' if $it->{state} eq 'carryover';
    my $why = $it->{blocked} // $it->{hold} // ($tag eq 'PUNT' ? $m->{punt} : undef) // (($m->{redo} // '') ne '' && $it->{state} ne 'done' ? $m->{redo} : undef);
    ($tag, \@marks, $why);
}
sub _done_on { my $it = shift; my ($d) = grep { $_->{account} =~ /:Done$/ && $_->{points} > 0 } reverse @{ $it->{history} }; $d ? $d->{date} : undef }
sub _redone  { my $it = shift; (grep { $_->{account} =~ /:Done$/ && $_->{points} > 0 } @{ $it->{history} }) > 1 }   # Done more than once: the demo sent it back
sub _carried { my ($it, $by) = @_; grep { $_->{account} =~ /:Carryover$/ && $_->{points} > 0 && (!defined $by || $_->{date} le $by) } @{ $it->{history} } }

sub quad {                                    # quad($s, team => T, prev => $s_week_ago) -> the four quadrants + the two metrics (JSON-ready hashref)
    my ($s, %o) = @_;
    my $team  = $o{team};
    my $today = $s->{today};
    my $since = add_days($today, -$THRESHOLD{week});
    my $prev  = $o{prev} // load($s->{file}, today => $since, until => $since);
    my $cur   = $s->{current};
    my $sum   = sprint_summary($s, $cur);
    my $in_team = sub { !$team || (($_[0]->{team} // '') eq $team) };
    my $row = sub { my $it = shift; my ($tag, $marks, $why) = _tag($it, $s);
                    { id => $it->{id}, title => $it->{title}, owner => $it->{owner}, team => $it->{team}, pts => $it->{points}, prio => $it->{meta}{prio}, tag => $tag, marks => $marks, why => $why } };

    # 1. technical priorities: everything in this sprint (OPEN and its variants), then the team's TODO list (backlog, punted first), capped
    my @pri;
    push @pri, map { $row->($_) } sorted_items(grep { defined $_->{sprint} && $_->{sprint} == $cur && $in_team->($_) } items($s)) if defined $cur;
    my @todo = map { $row->($_) } sorted_items(grep { $_->{state} eq 'backlog' && $in_team->($_) } items($s));
    @todo = ((grep { $_->{tag} eq 'PUNT' } @todo), (grep { $_->{tag} ne 'PUNT' } @todo));
    my $todo_more = @todo > $THRESHOLD{todo_max} ? @todo - $THRESHOLD{todo_max} : 0;
    push @pri, @todo[0 .. (@todo <= $THRESHOLD{todo_max} ? $#todo : $THRESHOLD{todo_max} - 1)] if @todo;

    # 2. watch items: PM = blocker older than the escalation threshold or a team well over capacity; WI = the rest the PM should know
    my @watch;
    for my $it (grep { $in_team->($_) } blocked($s)) {
        my $days = defined $it->{blocked_since} ? days_between($it->{blocked_since}, $today) : 0;
        push @watch, { kind => $days > $THRESHOLD{pm_days} ? 'PM' : 'WI', id => $it->{id}, team => $it->{team}, owner => $it->{owner}, days => $days,
                       text => "blocked $days day" . ($days == 1 ? '' : 's') . ": $it->{blocked}" };
    }
    push @watch, { kind => 'WI', id => $_->{id}, team => $_->{team}, owner => $_->{owner}, days => 0, text => "on hold: $_->{why}" }              for grep { $_->{tag} eq 'HOLD' } @pri;
    push @watch, { kind => 'WI', id => $_->{id}, team => $_->{team}, owner => $_->{owner}, days => 0, text => "punted, needs replanning: $_->{why}" } for grep { $_->{tag} eq 'PUNT' } @pri;
    push @watch, { kind => 'WI', id => $_->{id}, team => $_->{team}, owner => $_->{owner}, days => 0, text => "rework after the demo: $_->{why}" }   for grep { grep { $_ eq 'REDO' } @{ $_->{marks} } } @pri;
    push @watch, { kind => 'WI', id => $_->{id}, team => $_->{team}, owner => undef, days => 0, text => 'passed in, no owner yet' }                  for grep { !$_->{owner} && grep { /^PASS/ } @{ $_->{marks} } } @pri;
    push @watch, { kind => 'WI', id => $_->{id}, team => $_->{team}, owner => $_->{owner}, days => 0, text => 'carried to next sprint' }            for grep { grep { $_ eq 'CARRY' } @{ $_->{marks} } } @pri;
    push @watch, { kind => 'WI', id => $_->{id}, team => $_->{team}, owner => undef, days => 0, text => 'committed, no owner' } for grep { $in_team->($_) && !($_->{meta}{pass} // '') } unassigned($s);
    for my $t (sorted(keys %{ $sum->{teams} })) {
        next if $team && $t ne $team;
        my $l = $sum->{teams}{$t}{load};
        push @watch, { kind => $l > 110 ? 'PM' : 'WI', id => '', team => $t, owner => undef, days => 0, text => "$t at $l% of capacity" } if defined $l && $l > 100;
    }
    @watch = sort { ($b->{kind} eq 'PM') <=> ($a->{kind} eq 'PM') || $b->{days} <=> $a->{days} || ($a->{id} cmp $b->{id}) } @watch;

    # 3. schedule milestones: epics by ETA, 30/60/90 days out, against last week's ETA; the top few per horizon, the rest counted
    my $rm   = roadmap($s);
    my $prm  = roadmap($prev);
    my %prev_end = map { ("$_->{tome}\0$_->{epic}" => $_->{end}) } @{ $prm->{epics} };
    my %ms = map { $_ => [] } @{ $THRESHOLD{horizons} };
    my %more;
    for my $e (@{ $rm->{epics} }) {
        next if $e->{remaining} <= 0;
        next if $team && !grep { $_ eq $team } @{ $e->{teams} };
        my $eta = sprint_end_date($s, $e->{end});
        my $days = defined $eta ? days_between($today, $eta) : undef;
        my $pe = $prev_end{"$e->{tome}\0$e->{epic}"};
        my $shift = (defined $e->{end} && defined $pe) ? $e->{end} - $pe : undef;    # sprints: > 0 pushed right, < 0 pulled left
        my $trend = !defined $shift ? 'new' : $shift > 0 ? 'pushed' : $shift < 0 ? 'pulled' : 'same';
        my $sev = ($e->{blocked} >= 2 || (defined $shift && $shift >= 2)) ? 'critical' : ($e->{blocked} || (defined $shift && $shift > 0)) ? 'warning' : 'good';
        my $r = { tome => $e->{tome}, epic => $e->{epic}, teams => $e->{teams}, pct => $e->{pct}, remaining => $e->{remaining}, end => $e->{end}, eta => $eta, days => $days,
                  shift => $shift, trend => $trend, severity => $sev, blocked => $e->{blocked} };
        my ($h) = grep { defined $days && $days <= $_ } @{ $THRESHOLD{horizons} };
        push @{ $ms{$h} }, $r if defined $h;
    }
    for my $h (keys %ms) {
        my @r = sort { ($a->{eta} // '') cmp ($b->{eta} // '') || $b->{remaining} <=> $a->{remaining} || $a->{epic} cmp $b->{epic} } @{ $ms{$h} };
        @r = map { { %{ $r[$_] }, priority => $_ + 1 } } 0 .. $#r;
        $more{$h} = @r > $THRESHOLD{per_horizon} ? @r - $THRESHOLD{per_horizon} : 0;
        $ms{$h} = [ @r[0 .. (@r <= $THRESHOLD{per_horizon} ? $#r : $THRESHOLD{per_horizon} - 1)] ];
    }

    # 4. accomplishments: done in the last week; on time = never carried over and not rework; a SYNC group finishes when its last member does
    my (@acc, @slipped);
    for my $it (sorted_items(grep { $in_team->($_) && $_->{state} eq 'done' } items($s))) {
        my $date = _done_on($it) or next;
        my @group = grep { $_ } map { $s->{items}{$_} } grep { $_ ne $it->{id} } split ' ', ($it->{meta}{sync} // '');
        next if grep { $_->{state} ne 'done' } @group;                                       # shared DONE: not until every partner is
        $date = maximum($date, grep { defined } map { _done_on($_) } @group) if @group;
        next unless $date gt $since && $date le $today;
        my ($carried, $redone) = (scalar(_carried($it, $date)), _redone($it));
        push @acc, { id => $it->{id}, title => $it->{title}, owner => $it->{owner}, team => $it->{team}, pts => $it->{points}, date => $date,
                     ontime => ($carried || $redone) ? 0 : 1, late_why => $redone ? 'rework' : $carried ? 'carried over' : '' };
    }
    push @slipped, { id => $_->{id}, title => $_->{title}, owner => $_->{owner}, team => $_->{team},
                     why => $_->{tag} eq 'WAIT' ? "blocked: $_->{why}" : $_->{tag} eq 'PUNT' ? "punted: $_->{why}" : "on hold: $_->{why}" }
        for grep { $_->{tag} =~ /^(WAIT|PUNT|HOLD)$/ } @pri;

    # the two metrics
    my ($pct, $done, $committed) = $team ? map { $sum->{teams}{$team}{$_} // 0 } qw(pct done committed) : map { $sum->{totals}{$_} // 0 } qw(pct done committed);
    my $psum = sprint_summary($prev, $cur);
    my $ppct = defined $cur && $psum->{sprint} ? ($team ? $psum->{teams}{$team}{pct} : $psum->{totals}{pct}) : undef;
    my $sprint_trend = !defined $ppct ? 'new' : $pct > $ppct ? 'improving' : $pct < $ppct ? 'degrading' : 'same';
    my @all_done = grep { defined $cur && $_->{state} eq 'done' && $_->{sprint} == $cur && $in_team->($_) } items($s);
    my $sprint_ontime = grep { !_carried($_) && !_redone($_) } @all_done;
    {
        as_of => $today, since => $since, team => $team, sprint => $cur, file => $s->{file}, unit => $s->{unit} // 'SP',
        priorities => \@pri, todo_more => $todo_more, watch => \@watch, milestones => \%ms, milestones_more => \%more, horizons => $THRESHOLD{horizons},
        accomplishments => \@acc, slipped => \@slipped, punt_rate => punt_rate($s, team => $team), punt_warn => $THRESHOLD{punt_warn},
        metrics => {
            sprint => { pct => $pct, done => $done, committed => $committed, prev_pct => $ppct, trend => $sprint_trend, punted => scalar(grep { $_->{tag} eq 'PUNT' } @pri) },
            ontime => { week_ontime => scalar(grep { $_->{ontime} } @acc), week_total => scalar(@acc), sprint_ontime => $sprint_ontime, sprint_total => scalar(@all_done) },
        },
    };
}
sub sorted_items { sort { ($a->{meta}{prio} // 99) <=> ($b->{meta}{prio} // 99) || $a->{id} cmp $b->{id} } @_ }

sub punt_rate {                               # punt_rate($s, team => T, last => 4) -> [ { sprint, team, committed, punted, rate } ] tasks, per team per sprint (newest last), plus a Total row per sprint
    my ($s, %o) = @_;
    my @sprints = @{ $s->{sprints} };
    @sprints = @sprints[ -($o{last} // $THRESHOLD{punt_sprints}) .. -1 ] if @sprints > ($o{last} // $THRESHOLD{punt_sprints});
    my (%committed, %punted);
    for my $it (items($s)) {
        my %seen;
        for my $h (@{ $it->{history} }) {
            next unless $h->{points} > 0 && $h->{account} =~ /^Sprint:(\d+):([^:]+):Committed$/;
            $committed{$1}{$2}{ $it->{id} } = 1;      # a task counts once per sprint and team it was committed to, however it got there
        }
        $punted{ $_->{sprint} }{ $_->{team} }++ for grep { defined $_->{sprint} } @{ $it->{punts} // [] };
    }
    my @rows;
    for my $n (@sprints) {
        my @teams = grep { !$o{team} || $_ eq $o{team} } sorted(keys %{ $committed{$n} // {} });
        my ($tc, $tp) = (0, 0);
        for my $t (@teams) {
            my ($c, $p) = (scalar(keys %{ $committed{$n}{$t} }), $punted{$n}{$t} // 0);
            push @rows, { sprint => $n, team => $t, committed => $c, punted => $p, rate => $c ? int(100 * $p / $c + 0.5) : 0 };
            $tc += $c; $tp += $p;
        }
        push @rows, { sprint => $n, team => 'Total', committed => $tc, punted => $tp, rate => $tc ? int(100 * $tp / $tc + 0.5) : 0 } if @teams > 1;
    }
    \@rows;
}

# ---------------------------------------------------------------- text (the Friday mail) and HTML (one printed page)
my %ARROW = (pushed => '->', pulled => '<-', same => '=', new => '+');
my $LEGEND = 'TODO on the backlog &middot; OPEN in the sprint &middot; DONE &middot; WAIT blocked outside the team &middot; HOLD interrupted &middot; PUNT too hard as written, back to TODO &middot; DROP should not be done &middot; REDO the demo found it wrong &middot; PASS moved to the right team &middot; SYNC shared DONE across teams';
sub quad_text {
    my ($s, %o) = @_;
    my $q = $o{quad} // quad($s, %o);
    my $m = $q->{metrics};
    my $out = sprintf "Weekly status%s -- as of %s (sprint %s)\n", $q->{team} ? " $q->{team}" : '', $q->{as_of}, $q->{sprint} // '-';
    $out .= sprintf "Sprint progress %d%% (%d/%d %s) %s%s%s   On-time delivery: %d/%d this week, %d/%d this sprint\n\n",
        $m->{sprint}{pct}, $m->{sprint}{done}, $m->{sprint}{committed}, $q->{unit}, $m->{sprint}{trend}, defined $m->{sprint}{prev_pct} ? " (was $m->{sprint}{prev_pct}%)" : '',
        $m->{sprint}{punted} ? ", $m->{sprint}{punted} punted" : '', $m->{ontime}{week_ontime}, $m->{ontime}{week_total}, $m->{ontime}{sprint_ontime}, $m->{ontime}{sprint_total};
    $out .= "TECHNICAL PRIORITIES\n";
    $out .= sprintf("  %-5s %-10s %3s  %-30s %s%s\n", $_->{tag}, $_->{id}, $_->{pts}, substr($_->{title} // '', 0, 30), $_->{owner} // '-', @{ $_->{marks} } ? '  [' . join(', ', @{ $_->{marks} }) . ']' : '') for @{ $q->{priorities} };
    $out .= "  (nothing in the sprint or on the TODO list)\n" unless @{ $q->{priorities} };
    $out .= "  (+$q->{todo_more} more on the TODO list)\n" if $q->{todo_more};
    $out .= "\nWATCH ITEMS / PM HELP NEEDED\n";
    $out .= sprintf("  (%s) %-10s %s\n", $_->{kind}, $_->{id} || $_->{team}, $_->{text}) for @{ $q->{watch} };
    $out .= "  none\n" unless @{ $q->{watch} };
    $out .= "\nSCHEDULE MILESTONES\n";
    for my $h (@{ $q->{horizons} }) {
        $out .= "  $h days out\n";
        $out .= sprintf("    %d. %-34s %s %3d%%  ETA %s%s\n", $_->{priority}, "$_->{tome} > $_->{epic}", $ARROW{ $_->{trend} }, $_->{pct}, $_->{eta}, $_->{blocked} ? "  BLOCKED $_->{blocked}" : '') for @{ $q->{milestones}{$h} };
        $out .= "    -\n" unless @{ $q->{milestones}{$h} };
        $out .= "    (+$q->{milestones_more}{$h} more)\n" if $q->{milestones_more}{$h};
    }
    $out .= "\nACCOMPLISHMENTS (since $q->{since})\n";
    $out .= sprintf("  %s %-10s %3s  %-30s %s%s\n", $_->{ontime} ? 'v' : 'x', $_->{id}, $_->{pts}, substr($_->{title} // '', 0, 30), $_->{owner} // '-', $_->{late_why} ? "  ($_->{late_why})" : '') for @{ $q->{accomplishments} };
    $out .= "  none\n" unless @{ $q->{accomplishments} };
    $out .= sprintf("  ! %-10s %s\n", $_->{id}, $_->{why}) for @{ $q->{slipped} };
    $out .= "\nPUNT RATE (tasks punted back to TODO / tasks committed, last $THRESHOLD{punt_sprints} sprints)\n";
    $out .= sprintf("  sprint %-4s %-12s %3d / %-3d %3d%%%s\n", $_->{sprint}, $_->{team}, $_->{punted}, $_->{committed}, $_->{rate}, $_->{rate} > $THRESHOLD{punt_warn} ? '  !' : '') for @{ $q->{punt_rate} };
    $out .= "  no sprints yet\n" unless @{ $q->{punt_rate} };
    $out .= "\nLegend: v on time  x late (carried over, or rework after the demo)  ! slipped   -> pushed right  <- pulled left  = no change  + new\n";
    marked_text($o{marking}, $out);
}

my $QCSS = <<'CSS';
:root{--navy:#27235d;--gold:#e6af22;--olive:#6b7436;--red:#d6292e;--grey:#808082;--lgrey:#e4e4e7;--ink:#0b0b0b;--good:#0ca30c;--warn:#c98500}
body{font-family:"Segoe UI",Calibri,Arial,sans-serif;font-size:11.5px;color:var(--ink);background:#fff;margin:0;padding:10px 14px}
h1{font-size:16px;color:var(--navy);margin:0;border-bottom:3px solid var(--gold);padding-bottom:3px;display:flex;justify-content:space-between;align-items:baseline}
h1 .muted{font-size:11px;font-weight:400}
.metrics{display:flex;gap:18px;margin:6px 0 8px;font-size:11px}.metrics b{font-size:14px;color:var(--navy)}
.quad{display:grid;grid-template-columns:1fr 1fr;gap:8px}
.q{border:1px solid var(--lgrey);border-top:4px solid var(--navy);border-radius:4px;padding:6px 8px;min-height:180px}
.q h2{font-size:12px;margin:0 0 4px;color:var(--navy);text-transform:uppercase;letter-spacing:.03em}
.q h3{font-size:11px;margin:6px 0 2px;color:var(--olive)}
table{border-collapse:collapse;width:100%}td,th{padding:1px 4px;vertical-align:top;text-align:left;border-bottom:1px solid #f0f0f2}th{color:var(--grey);font-weight:600;font-size:10px}
td.n{text-align:right;white-space:nowrap}
.tag{display:inline-block;min-width:38px;text-align:center;border-radius:3px;padding:0 4px;font-size:10px;font-weight:700;color:#fff;background:var(--grey)}
.tag.DONE{background:var(--good)}.tag.OPEN{background:var(--navy)}.tag.WAIT{background:var(--red)}.tag.HOLD{background:var(--warn)}.tag.PUNT{background:var(--red)}.tag.DROP{background:#555}.tag.TODO{background:var(--grey)}
.mark{display:inline-block;border:1px solid var(--olive);color:var(--olive);border-radius:3px;padding:0 3px;font-size:9px;margin-left:2px}
.kind{font-weight:700}.kind.PM{color:var(--red)}.kind.WI{color:var(--warn)}
.sev.critical{color:var(--red);font-weight:700}.sev.warning{color:var(--warn);font-weight:700}.sev.good{color:var(--good)}
.ok{color:var(--good);font-weight:700}.late{color:var(--red);font-weight:700}.slip{color:var(--warn);font-weight:700}
.legend{margin-top:6px;font-size:9.5px;color:var(--grey)}.muted{color:var(--grey)}
.foot{margin-top:6px;font-size:9.5px;color:var(--grey);display:flex;justify-content:space-between}
.strip{border:1px solid var(--lgrey);border-top:4px solid var(--olive);border-radius:4px;padding:6px 8px;margin-top:8px}.strip h2{font-size:12px;margin:0 0 4px;color:var(--navy);text-transform:uppercase;letter-spacing:.03em}.strip h2 .muted{text-transform:none;letter-spacing:0;font-weight:400}.strip table{width:auto}.strip td.n{padding-left:14px}
.logo{height:16px;width:auto;vertical-align:-3px;margin-right:6px}
@page{size:landscape;margin:10mm}@media print{*{-webkit-print-color-adjust:exact;print-color-adjust:exact}body{padding:0}.q{break-inside:avoid}}
CSS
sub quad_html {
    my ($s, %o) = @_;
    my $q = $o{quad} // quad($s, %o);
    my $m = $q->{metrics};
    my $h = \&Scrum::_h;
    my %arrow = (pushed => '&#8594; pushed right', pulled => '&#8592; pulled left', same => '= no change', new => '+ new');
    my %trend = (improving => '&#8599; improving', degrading => '&#8600; degrading', same => '&#8594; no change', new => 'first week');
    my $html = "<!DOCTYPE html>\n<html><head><meta charset=\"utf-8\"><title>Weekly status</title><style>$QCSS</style></head><body>\n";
    $html .= Scrum::mark_banner_html($o{marking}, 'top') . Scrum::mark_block_html($o{marking});
    $html .= '<h1>' . Scrum::logo_svg() . 'Weekly Status' . ($q->{team} ? ' &middot; ' . $h->($q->{team}) : '') . ' <span class=muted>as of ' . $h->($q->{as_of}) . (defined $q->{sprint} ? " &middot; sprint $q->{sprint}" : '') . "</span></h1>\n";
    $html .= sprintf('<div class=metrics><span>Sprint progress <b>%d%%</b> %d/%d %s <span class=muted>%s%s</span>%s</span><span>On-time delivery <b>%d/%d</b> this week <span class=muted>&middot; %d/%d this sprint</span></span></div>' . "\n",
        $m->{sprint}{pct}, $m->{sprint}{done}, $m->{sprint}{committed}, $h->($q->{unit}), $trend{ $m->{sprint}{trend} }, defined $m->{sprint}{prev_pct} ? " (was $m->{sprint}{prev_pct}%)" : '',
        $m->{sprint}{punted} ? " <span class=late>$m->{sprint}{punted} punted</span>" : '',
        $m->{ontime}{week_ontime}, $m->{ontime}{week_total}, $m->{ontime}{sprint_ontime}, $m->{ontime}{sprint_total});
    $html .= "<div class=quad>\n";
    # technical priorities
    $html .= "<div class=q><h2>Technical Priorities</h2>\n";
    if (@{ $q->{priorities} }) {
        my @rows = @{ $q->{priorities} };
        my @done = @rows > 12 ? grep { $_->{tag} eq 'DONE' } @rows : ();       # a long list (all teams): finished tasks fold into one line so the page stays one page
        @rows = grep { $_->{tag} ne 'DONE' } @rows if @done;
        $html .= "<table><tr><th></th><th>ID</th><th>Task</th><th>Owner</th><th class=n>$q->{unit}</th></tr>\n";
        for my $p (@rows) {
            $html .= sprintf "<tr><td><span class=\"tag %s\">%s</span></td><td>%s</td><td>%s%s%s</td><td>%s</td><td class=n>%s</td></tr>\n", $p->{tag}, $p->{tag}, $h->($p->{id}), $h->($p->{title}),
                join('', map { '<span class=mark>' . $h->($_) . '</span>' } @{ $p->{marks} }), $p->{why} ? ' <span class=muted>' . $h->($p->{why}) . '</span>' : '', $h->($p->{owner} // '-'), $h->($p->{pts});
        }
        $html .= '<tr><td><span class="tag DONE">DONE</span></td><td colspan=4><span class=muted>' . scalar(@done) . ' done: </span>' . join(', ', map { $h->($_->{id}) } @done) . "</td></tr>\n" if @done;
        $html .= "</table>\n";
        $html .= "<p class=muted>+$q->{todo_more} more on the TODO list</p>\n" if $q->{todo_more};
    } else { $html .= "<p class=muted>nothing in the sprint or on the TODO list</p>\n" }
    $html .= "<div class=legend>$LEGEND</div></div>\n";
    # watch items
    $html .= "<div class=q><h2>Watch Items / PM Help Needed</h2>\n";
    if (@{ $q->{watch} }) {
        $html .= "<table><tr><th></th><th>ID</th><th>Team</th><th>Owner</th><th>Item</th></tr>\n";
        $html .= sprintf("<tr><td><span class=\"kind %s\">(%s)</span></td><td>%s</td><td>%s</td><td>%s</td><td>%s</td></tr>\n", $_->{kind}, $_->{kind}, $h->($_->{id}), $h->($_->{team} // ''), $h->($_->{owner} // '-'), $h->($_->{text})) for @{ $q->{watch} };
        $html .= "</table>\n";
    } else { $html .= "<p class=muted>nothing to watch</p>\n" }
    $html .= "<div class=legend>(PM) SWAT: the program manager needs to help remove a blocker &middot; (WI) SWAT: the program manager needs to be aware</div></div>\n";
    # schedule milestones
    $html .= "<div class=q><h2>Schedule Milestones</h2>\n";
    for my $hz (@{ $q->{horizons} }) {
        $html .= "<h3>$hz days out</h3>";
        if (@{ $q->{milestones}{$hz} }) {
            $html .= "<table>";
            $html .= sprintf("<tr><td class=n>%d.</td><td>%s <span class=muted>&gt;</span> %s</td><td class=\"sev %s\">%s</td><td class=n>%d%%</td><td class=n>ETA %s</td><td>%s</td></tr>\n",
                $_->{priority}, $h->($_->{tome}), $h->($_->{epic}), $_->{severity}, $arrow{ $_->{trend} }, $_->{pct}, $h->($_->{eta}), $_->{blocked} ? "<span class=late>$_->{blocked} blocked</span>" : '') for @{ $q->{milestones}{$hz} };
            $html .= "</table>";
        } else { $html .= "<p class=muted>-</p>" }
        $html .= "<p class=muted>+$q->{milestones_more}{$hz} more epics in this window</p>" if $q->{milestones_more}{$hz};
    }
    $html .= "<div class=legend>ETA = remaining &divide; the owning teams' velocity, against last week's ETA. Red: pushed 2+ sprints or 2+ blockers; amber: pushed or blocked.</div></div>\n";
    # accomplishments
    $html .= "<div class=q><h2>Accomplishments <span class=muted>since $q->{since}</span></h2>\n";
    if (@{ $q->{accomplishments} } || @{ $q->{slipped} }) {
        $html .= "<table>";
        $html .= sprintf("<tr><td class=\"%s\">%s</td><td>%s</td><td>%s%s</td><td>%s</td><td class=n>%s</td></tr>\n", $_->{ontime} ? 'ok' : 'late', $_->{ontime} ? '&#10003;' : '&#10007;', $h->($_->{id}), $h->($_->{title}),
            $_->{late_why} ? ' <span class=muted>' . $h->($_->{late_why}) . '</span>' : '', $h->($_->{owner} // '-'), $h->($_->{pts})) for @{ $q->{accomplishments} };
        $html .= sprintf("<tr><td class=slip>!</td><td>%s</td><td colspan=3>%s <span class=muted>%s</span></td></tr>\n", $h->($_->{id}), $h->($_->{title}), $h->($_->{why})) for @{ $q->{slipped} };
        $html .= "</table>";
    } else { $html .= "<p class=muted>nothing finished this week</p>\n" }
    $html .= "<div class=legend>&#10003; delivered on time &middot; &#10007; delivered late (carried over, or rework after the demo) &middot; ! priority that slipped this week</div></div>\n";
    $html .= "</div>\n";
    # punt rate: the estimation-quality strip under the quadrants
    $html .= "<div class=strip><h2>Punt rate <span class=muted>tasks punted back to TODO / tasks committed, last $THRESHOLD{punt_sprints} sprints; over $THRESHOLD{punt_warn}% two sprints running means tasks arrive under-specified</span></h2>\n";
    if (@{ $q->{punt_rate} }) {
        my @sp = nub(map { $_->{sprint} } @{ $q->{punt_rate} });
        my @teams = nub(map { $_->{team} } @{ $q->{punt_rate} });
        my %cell = map { ("$_->{sprint}\0$_->{team}" => $_) } @{ $q->{punt_rate} };
        $html .= "<table><tr><th>Team</th>" . join('', map { "<th class=n>Sprint $_</th>" } @sp) . "</tr>\n";
        for my $t (@teams) {
            $html .= '<tr><td>' . $h->($t) . '</td>' . join('', map { my $c = $cell{"$_\0$t"}; $c ? sprintf('<td class="n%s">%d / %d &middot; %d%%</td>', $c->{rate} > $THRESHOLD{punt_warn} ? ' late' : '', $c->{punted}, $c->{committed}, $c->{rate}) : '<td class=n>-</td>' } @sp) . "</tr>\n";
        }
        $html .= "</table>\n";
    } else { $html .= "<p class=muted>no sprints yet</p>\n" }
    $html .= "</div>\n<div class=foot><span>Source: " . $h->($q->{file}) . "</span><span>Sprint Progress, On-Time Delivery and Punt Rate are all read off this page</span></div>\n";
    $html . Scrum::mark_banner_html($o{marking}, 'bottom') . "</body></html>\n";
}

@EXPORT = qw(quad quad_text quad_html punt_rate sprint_span sprint_end_date add_days);
1;
