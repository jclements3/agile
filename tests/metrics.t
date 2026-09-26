#!/usr/bin/perl
# perl tests/metrics.t  — Metrics.pm: every threshold of the operating model, the table, the sprint report, the roll-up, CSV; daily.pl health/review/rollup/csv
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use File::Temp qw(tempdir);
use File::Copy qw(copy);
use Prelude qw(show sorted);
use Scrum;
use Metrics;

my ($n, $bad) = (0, 0);
sub check { my ($name, $got, $want) = @_; $n++;
    if ($got eq $want) { print "ok $n - $name\n" }
    else { $bad++; print "not ok $n - $name\n#   got:  $got\n#   want: $want\n" } }
sub S { my ($name, $want, $got) = @_; check($name, show($got), $want) }
sub has { my ($name, $text, @res) = @_; for my $re (@res) { check("$name: $re", ($text =~ $re ? 1 : 0), 1) } }

my $root = "$FindBin::Bin/..";
my $dir = tempdir(CLEANUP => 1);

# ---- a journal built to trip the thresholds: Alpha slides for three sprints, then overloads sprint 4; Bravo is underloaded
my $J = '';
sub txn { my ($date, $payee, @p) = @_; $J .= "$date $payee\n" . join('', map { my ($a, $pts, $m) = @$_; defined $pts ? sprintf("    %-30s %s SP   ; %s\n", $a, $pts, $m) : "    $a\n" } @p) . "\n" }
sub intake { my ($date, $id, $pts, $team, $meta) = @_; txn($date, "Intake $id Task $id", [ "Backlog:$team", $pts, "id: $id" . ($meta ? ", $meta" : '') ], [ 'Equity:Intake' ]) }
sub move   { my ($date, $id, $pts, $from, $to, $meta) = @_; txn($date, "Move $id", [ $from, -$pts, "id: $id" ], [ $to, $pts, "id: $id" . ($meta ? ", $meta" : '') ]) }
my %start = (1 => '2026-08-03', 2 => '2026-08-17', 3 => '2026-08-31', 4 => '2026-09-14');
$J .= "~ Sprint $_\n    Alpha    20 SP\n\n" for 1 .. 3;
$J .= "~ Sprint 4\n    Alpha    25 SP\n    Bravo    20 SP\n\n";
my %done = (1 => 18, 2 => 14, 3 => 10);                     # velocity 18 -> 14 -> 10; carryover 2, 6, 10 of 20
for my $s (1 .. 3) {
    my $d = $start{$s};
    intake($d, "A$s-1", $done{$s}, 'Alpha', 'owner: Ann, epic: Core');
    intake($d, "A$s-2", 20 - $done{$s} - 1, 'Alpha', 'owner: Bob, epic: Core');
    intake($d, "A$s-3", 1, 'Alpha', 'owner: Cy, epic: Core');
    move($d, $_->[0], $_->[1], 'Backlog:Alpha', "Sprint:$s:Alpha:Committed") for [ "A$s-1", $done{$s} ], [ "A$s-2", 20 - $done{$s} - 1 ], [ "A$s-3", 1 ];
    my $end = Quad::add_days($d, 12);
    move($end, "A$s-1", $done{$s}, "Sprint:$s:Alpha:Committed", "Sprint:$s:Alpha:Done");
    move($end, "A$s-2", 20 - $done{$s} - 1, "Sprint:$s:Alpha:Committed", "Sprint:$s:Alpha:Carryover");
    if ($s >= 2) { move(Quad::add_days($d, 5), "A$s-3", 1, "Sprint:$s:Alpha:Committed", 'Backlog:Alpha', 'punt: too big') }   # 1 of 3 punted in sprints 2 and 3: 33%
    else { move($end, "A$s-3", 1, "Sprint:$s:Alpha:Committed", "Sprint:$s:Alpha:Carryover") }
}
intake('2026-08-31', 'A3-P', 1, 'Alpha', 'owner: Cy, epic: Core');                                 # a second punt in sprint 3: 2 of 6 tasks
move('2026-08-31', 'A3-P', 1, 'Backlog:Alpha', 'Sprint:3:Alpha:Committed');
move('2026-09-04', 'A3-P', 1, 'Sprint:3:Alpha:Committed', 'Backlog:Alpha', 'punt: unclear');
# sprint 4: Alpha commits 30 of 25 (120%), Ann holds most of it, one task unassigned, two blockers, an interrupt; 5 small tasks done, 2 of them carried from sprint 3
my $d4 = $start{4};
intake($d4, 'A4-1', 20, 'Alpha', 'owner: Ann, epic: Core');
intake($d4, 'A4-2', 2, 'Alpha', 'owner: Bob, epic: Core');
intake($d4, 'A4-3', 1, 'Alpha', 'owner: Cy, epic: Core');
intake($d4, 'A4-4', 2, 'Alpha', 'epic: Core');
move($d4, $_->[0], $_->[1], 'Backlog:Alpha', 'Sprint:4:Alpha:Committed') for [ 'A4-1', 20 ], [ 'A4-2', 2 ], [ 'A4-3', 1 ], [ 'A4-4', 2 ];
intake($d4, "A4-D$_", 1, 'Alpha', 'owner: Cy, epic: Core') for 1 .. 3;
move($d4, "A4-D$_", 1, 'Backlog:Alpha', 'Sprint:4:Alpha:Committed') for 1 .. 3;
intake('2026-08-31', "A3-C$_", 1, 'Alpha', 'owner: Bob, epic: Core') for 1 .. 2;              # carried in from sprint 3: late when done
move('2026-08-31', "A3-C$_", 1, 'Backlog:Alpha', 'Sprint:3:Alpha:Committed') for 1 .. 2;
move('2026-09-12', "A3-C$_", 1, 'Sprint:3:Alpha:Committed', 'Sprint:3:Alpha:Carryover') for 1 .. 2;
move($d4, "A3-C$_", 1, 'Sprint:3:Alpha:Carryover', 'Sprint:4:Alpha:Committed') for 1 .. 2;
move('2026-09-18', $_, 1, 'Sprint:4:Alpha:Committed', 'Sprint:4:Alpha:Done') for (map { "A4-D$_" } 1 .. 3), 'A3-C1', 'A3-C2';
txn('2026-09-16', 'Stand-up', [ 'Sprint:4:Alpha:Committed', 0, 'id: A4-1, blocked: vendor licence' ], [ 'Equity:Intake' ]);
txn('2026-09-19', 'Stand-up', [ 'Sprint:4:Alpha:Committed', 0, 'id: A4-2, blocked: test rig' ], [ 'Equity:Intake' ]);
txn('2026-09-17', 'Intake HOT-1 Hotfix', [ 'Sprint:4:Alpha:Committed', 3, 'id: HOT-1, interrupt: 1, owner: Bob' ], [ 'Equity:Intake' ]);
intake($d4, 'B4-1', 10, 'Bravo', 'owner: Dee, epic: Ops');
move($d4, 'B4-1', 10, 'Backlog:Bravo', 'Sprint:4:Bravo:Committed');
intake('2026-05-01', 'OLD-1', 5, 'Alpha', 'epic: Core');                                           # 145 days in the backlog
intake($d4, 'AU-1', 120, 'Alpha', 'epic: Auth, target: 2026-09-30');                              # far more than the target allows, and a backlog over 8 sprints deep
open my $fh, '>', "$dir/scrum.txt" or die; print $fh $J; close $fh;

my $s = load("$dir/scrum.txt", today => '2026-09-23');
S 'sprint day', 10, sprint_day($s);
my $th = team_history($s);
S 'team history: done, carryover, interrupt, complete', '[[1,18,2,0,1],[2,14,5,0,1],[3,10,11,0,1],[4,5,0,3,0]]', [ map { [ @{$_}{qw(sprint done carryover interrupt complete)} ] } @{ $th->{Alpha} } ];
my $in = intake_by_sprint($s);
S 'intake by sprint', '[20,20,23]', [ map { $in->{$_} } 1 .. 3 ];

my @sig = signals($s);
my %by; push @{ $by{ $_->{metric} } }, $_ for @sig;
S 'red first', '"red"', $sig[0]{level};
S 'blocked: 7 days red, 4 days amber', '[["red","A4-1"],["amber","A4-2"]]', [ map { [ $_->{level}, $_->{text} =~ /^(\S+)/ ] } @{ $by{blocked} } ];
has 'blocked text', $by{blocked}[0]{text}, qr/blocked 7 days: vendor licence -- over 5 days: your problem, on the weekly mail by name/;
S 'load: Alpha over, Bravo under', '[["red","Alpha"],["amber","Bravo"]]', [ map { [ $_->{level}, $_->{team} ] } @{ $by{load} } ];
has 'load texts', join("\n", map { $_->{text} } @{ $by{load} }), qr/load 132% of capacity \(over 110%\): cut/, qr/load 50% of capacity \(under 70%\): pull work from the master backlog/;
S 'done by day 8', '[["red","Alpha"],["red","Bravo"]]', [ map { [ $_->{level}, $_->{team} ] } @{ $by{'done by day 8'} } ];
has 'day 8 text', $by{'done by day 8'}[0]{text}, qr/sprint day 10: 15% done \(under 60% by Day 8\): descope or swarm/;
has 'velocity', $by{velocity}[0]{text}, qr/velocity down two sprints running \(18 -> 14 -> 10\)/;
has 'predictability', $by{predictability}[0]{text}, qr/predictability 67% over the last 3 sprints \(under 80%\).*cap the next commitment at velocity \(14\)/;
has 'carryover', $by{carryover}[0]{text}, qr/carryover 25% and 48% in sprints 2 and 3/;
has 'bus factor', $by{'bus factor'}[0]{text}, qr/^Ann holds 61% of the sprint commitment \(over 40%\)/;
has 'unassigned', $by{unassigned}[0]{text}, qr/^1 committed task with no owner \(A4-4\)/;
has 'on-time', $by{'on-time'}[0]{text}, qr/on-time delivery 60% this sprint \(under 80%\)/;
has 'punt rate', $by{'punt rate'}[0]{text}, qr/punt rate 33% and 33% \(over 20% two sprints running\)/;
S 'interrupts are info', '["info","Alpha"]', [ @{ $by{interrupts}[0] }{qw(level team)} ];
has 'interrupts text', $by{interrupts}[0]{text}, qr/^3 SP of interrupts \(new!\) this sprint, 9% of the commitment/;
has 'backlog age', $by{'backlog age'}[0]{text}, qr/^1 backlog task older than 90 days \(oldest OLD-1 145d\)/;
has 'epic target', $by{'epic target'}[0]{text}, qr/^Auth: ETA \S+ is past its target 2026-09-30/;
has 'backlog depth', $by{'backlog depth'}[0]{text}, qr/the backlog \(master \+ teams\) is 9\.1 sprints of work \(over 8\): prune it/;
has 'intake vs done', $by{'intake vs done'}[0]{text}, qr/intake exceeded done three sprints running \(1: 20\/18, 2: 20\/14, 3: 23\/10\): at current velocity this is \d+ sprints of work/;
S 'team filter keeps that team only', '[]', [ grep { ($_->{team} // '') ne 'Bravo' && defined $_->{team} } signals($s, team => 'Bravo') ];

# the three that live outside the journal: #est rounds, attendance, answers -- and the fortnight trend
my @rounds = ((map { { kind => 'est', median => 3, consensus => 0 } } 1 .. 3), { kind => 'est', median => 5, consensus => 1 }, { kind => 'vote', median => undef });
my @att = map { my ($date, $k) = @$_; map { { date => $date, team => 'Alpha', name => "P$_", status => 'declined' } } 1 .. $k } [ '2026-09-08', 1 ], [ '2026-09-15', 2 ], [ '2026-09-22', 4 ];
my $rec = sub { my ($date, @who) = @_; { date => $date, answers => [ map { { who => $_->[0], complete => $_->[1], assumed => $_->[2] // 0 } } @who ] } };
my %days = (Alpha => [ $rec->('2026-09-23', [ 'Ann', 1 ], [ 'Bob', 0 ]), $rec->('2026-09-22', [ 'Ann', 1 ], [ 'Bob', 1, 1 ]), $rec->('2026-09-21', [ 'Ann', 1 ]) ]);
my $fake = sub { my $p = shift; { _memo => { sprint_summary => { 4 => { sprint => 4, teams => { Alpha => { pct => $p }, Bravo => { pct => 0 } }, totals => { pct => $p } } } } } };
my @x = signals($s, est_rounds => \@rounds, attendance => \@att, answer_days => \%days, rosters => { Alpha => [ 'Ann', 'Bob', 'Cy' ] }, prev => $fake->(40), prev2 => $fake->(60));
my %bx; push @{ $bx{ $_->{metric} } }, $_ for @x;
has 'consensus', $bx{consensus}[0]{text}, qr/^estimate consensus in 1 of 4 #est rounds \(25%, under 50%\)/;
has 'attendance', $bx{attendance}[0]{text}, qr/calendar declines rising three weeks running \(1 -> 2 -> 4\)/;
S 'answers: Bob and Cy silent/incomplete 3 days, Ann fine', '["Bob silent or incomplete 3 days running: talk to the lead","Cy silent or incomplete 3 days running: talk to the lead"]', [ map { $_->{text} } @{ $bx{answers} } ];
has 'sprint progress', join("\n", map { ($_->{team} // 'Total') . ": $_->{text}" } @{ $bx{'sprint progress'} }), qr/Alpha: sprint progress degrading two weeks running \(60% -> 40% -> 15%\)/;
S 'too few rounds: no consensus signal', 0, scalar(grep { $_->{metric} eq 'consensus' } signals($s, est_rounds => [ @rounds[0 .. 2] ]));

# ---- the table
my ($ta) = grep { $_->{team} eq 'Alpha' } @{ table($s) };
S 'table row', '{"blocked":2,"carryover":48,"interrupt":3,"load":132,"oldest_block":7,"ontime":60,"pct":15,"predictability":67,"team":"Alpha","top_share":61,"trend":"18 14 10","velocity":14.0}', $ta;

# ---- sprint report, roll-up, csv
my $sr = sprint_report_text($s, 3);
has 'sprint report', $sr, qr/^Sprint 3 report -- as of 2026-09-23: 10\/23 SP done \(43%\), 11 carried over/m, qr/^Alpha\s+23\s+10\s+43%\s+11\s+48%/m, qr/^Epics \(remaining/m, qr/Health \(thresholds/;
has 'sprint report html', sprint_report_html($s, 3), qr/<title>Sprint 3 report<\/title>/, qr/Predictability%/, qr/color:#c98500">48</;
my $ru = rollup($s, '2026-09', attendance => \@att);
S 'rollup sprints', '[[3,"2026-08-31",23,10],[4,"2026-09-14",161,5]]', [ map { [ @{$_}{qw(sprint start intake done)} ] } @{ $ru->{sprints} } ];
S 'rollup age buckets', '{"0-30":[3,122],"31-60":[1,1],"over 90":[1,5]}', { map { $_ => $ru->{age}{$_} } keys %{ $ru->{age} } };
S 'rollup attendance', '{"Alpha":{"declined":7}}', $ru->{attendance};
has 'rollup text', rollup_text($s, '2026-09', attendance => \@att), qr/^Monthly roll-up 2026-09/m, qr/sprint 4\s+from 2026-09-14\s+intake\s+161\s+done\s+5  \(backlog grew\)/, qr/over 90\s+1 tasks\s+5 SP/, qr/Alpha: declined 7/;
has 'rollup html', rollup_html($s, '2026-09', attendance => \@att), qr/<h2[^>]*>Intake vs done/, qr/<h2[^>]*>Attendance/;
my $csv = csv($s, 'sprints');
has 'csv sprints', $csv, qr/^sprint,start,team,capacity,committed,done,carryover,pct,load,carry_rate,interrupt,complete\r\n/, qr/^4,2026-09-14,Alpha,25,33,5,0,15,132,0,3,0\r$/m;
has 'csv items quoting', csv($s, 'items'), qr/^A4-1,Task A4-1,20,committed,Alpha,4,Ann,,,Core,\d+,vendor licence,7,2026-09-14,\r$/m;
has 'csv intake', csv($s, 'intake'), qr/^3,2026-08-31,23,10\r$/m;
has 'csv health', csv($s, 'health'), qr/^red,blocked,Alpha,"?A4-1/m;
S 'csv unknown', 1, (eval { csv($s, 'nope'); 1 } ? 0 : ($@ =~ /unknown table 'nope'/ ? 1 : 0));
my $ra = read_attendance("$root/examples/../data/nope.csv");
S 'read_attendance missing file', '[]', $ra;
open my $af, '>', "$dir/attendance.csv" or die; print $af "date,team,name,status\n2026-09-22,Alpha,\"Lee, Ann\",declined\n"; close $af;
S 'read_attendance quoted', '[["2026-09-22","Alpha","Lee, Ann","declined"]]', [ map { [ @{$_}{qw(date team name status)} ] } @{ read_attendance("$dir/attendance.csv") } ];

# ---- the renderers in Scrum, and the status mail
has 'health_text', Scrum::health_text(\@sig), qr/^Health \(thresholds from the operating model\):\n  RED   blocked\s+Alpha: A4-1/;
S 'health_text hides info unless all', 0, (Scrum::health_text(\@sig) =~ /interrupts/ ? 1 : 0);
has 'mail text: blocker ages + health', email_text($s, 4, health => \@sig), qr/BLOCKED: A4-1 vendor licence \(7d\); A4-2 test rig \(4d\)/, qr/Health \(thresholds/;
has 'mail html: ages + health', email_html($s, 4, health => \@sig), qr/vendor licence<\/?\w*> ?<b>7d<\/b> \(over 5 days\)|vendor licence <b>7d<\/b> \(over 5 days\)/, qr/<b>Health<\/b>/;
has 'dashboard: health + metrics table', dashboard_html($s, health => \@sig, metrics => table($s)), qr/<h2>Health/, qr/Metrics by team/, qr/Blocked 7d/;
has 'brief: blocker age', brief_text($s, 4), qr/A4-1 \(Alpha\) blocked 7d: vendor licence/;

# ---- daily.pl health / review / rollup / csv / report
my $proj = "$dir/proj"; mkdir $proj;
open my $c, '>', "$proj/scrum.conf" or die; print $c "journal = scrum.txt\nstandups = standups\nreports = reports\nunit = SP\n"; close $c;
copy("$dir/scrum.txt", "$proj/scrum.txt") or die;
sub cli { my $out = qx("$^X" "$root/bin/daily.pl" -c "$proj/scrum.conf" --today 2026-09-23 @_ 2>&1); ($? >> 8, $out) }
my ($rc, $out) = cli('health');
S 'health exits 1 on red', 1, $rc;
has 'health output', $out, qr/^sprint 4 day 10, 2026-09-23: \d+ red, \d+ amber, 1 info$/m, qr/RED   blocked/, qr/INFO  interrupts/;
($rc, $out) = cli('health', 'Bravo');
has 'health Bravo', $out, qr/AMBER load\s+Bravo/;
($rc, $out) = cli('review', 3);
has 'review', $out, qr/^Sprint 3 report/m, qr{wrote .*reports/sprint-3-report\.html};
($rc, $out) = cli('rollup', '2026-09');
has 'rollup', $out, qr/^Monthly roll-up 2026-09/m, qr{wrote .*reports/2026-09-rollup\.txt};
($rc, $out) = cli('rollup', 'Sept');
S 'rollup bad month', 2, $rc;
($rc, $out) = cli('csv', 'epics');
has 'csv to stdout', $out, qr/^tome,epic,tasks,total,done/;
($rc, $out) = cli('csv');
has 'csv writes all', $out, map { qr{wrote .*reports/$_\.csv} } @Metrics::CSV;
open my $cf, '<:raw', "$proj/reports/sprints.csv" or die; my $raw = do { local $/; <$cf> }; close $cf;
S 'csv file starts with a UTF-8 BOM', 1, ($raw =~ /^\xEF\xBB\xBFsprint,/ ? 1 : 0);
($rc, $out) = cli('report');
has 'report writes the new pages', $out, qr{sprint-4-report\.html}, qr{2026-09-rollup\.html}, qr{health\.csv};
($rc, $out) = cli('blocked');
check 'blocked lists oldest first with days', $out, "A4-1       Alpha          7d  vendor licence   (over 5 days: yours)\nA4-2       Alpha          4d  test rig   (escalate)\n";

# ---- scrum.pl csv
my $sc = qx("$^X" "$root/bin/scrum.pl" -f "$dir/scrum.txt" --today 2026-09-23 csv intake 2>&1);
has 'scrum.pl csv', $sc, qr/^sprint,start,intake,done\r?\n1,2026-08-03,20,18/;

print "1..$n\n";
print $bad ? "# $bad of $n failed\n" : "# all $n passed\n";
exit($bad ? 1 : 0);
