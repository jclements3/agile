#!/usr/bin/perl
# perl tests/quad.t -- the weekly quad: tags, watch items, 30/60/90 milestones, accomplishments, the two metrics
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use File::Temp qw(tempdir);
use Prelude qw(show sorted);
use Scrum;
use Standup;
use Quad;

my ($n, $bad) = (0, 0);
sub check { my ($name, $got, $want) = @_; $n++;
    if ($got eq $want) { print "ok $n - $name\n" }
    else { $bad++; print "not ok $n - $name\n#   got:  $got\n#   want: $want\n" } }
sub S { my ($name, $want, $got) = @_; check($name, show($got), $want) }
sub has { my ($name, $text, @res) = @_; for my $re (@res) { check("$name: $re", ($text =~ $re ? 1 : 0), 1) } }

# ---- dates
S 'add_days', '["2026-09-30","2026-08-25","2027-01-02"]', [ add_days('2026-09-23', 7), add_days('2026-09-01', -7), add_days('2026-12-31', 2) ];

# ---- the example journal, as of 2026-09-01 (sprint 42 started 2026-08-24; RPT-201 carried from 41, done 08-28)
my $s = load("$FindBin::Bin/../examples/scrum.txt", today => '2026-09-01');
$s->{unit} = 'SP';
S 'sprint_span', '{41:{"end":"2026-08-24","start":"2026-08-10"},42:{"end":"2026-08-28","start":"2026-08-24"}}', sprint_span($s);
S 'sprint_end_date: planned from the current sprint start', '["2026-09-06","2026-09-20",undef]', [ sprint_end_date($s, 42), sprint_end_date($s, 43), sprint_end_date($s, undef) ];

my $q = quad($s);
S 'priorities: the sprint is OPEN, then DONE', '[["OPEN","AUTH-103","Bob"],["DONE","RPT-201","Cy"],["OPEN","RPT-202","Cy"]]', [ map { [ $_->{tag}, $_->{id}, $_->{owner} ] } @{ $q->{priorities} } ];
S 'no TODO list yet (backlogs empty after planning)', 0, $q->{todo_more};
S 'watch: both teams over capacity, WI not PM', '[["WI","Alpha"],["WI","Bravo"]]', [ map { [ $_->{kind}, $_->{team} ] } @{ $q->{watch} } ];
S 'milestones: 60 days out, priority order, arrows', '[[1,"Auth","same"],[2,"Ops","same"],[3,"Reporting","pulled"]]', [ map { [ $_->{priority}, $_->{epic}, $_->{trend} ] } @{ $q->{milestones}{60} } ];
S 'milestones: nothing at 30 or 90, none hidden', '[0,0,0]', [ scalar @{ $q->{milestones}{30} }, scalar @{ $q->{milestones}{90} }, $q->{milestones_more}{60} ];
S 'milestones: top N per horizon, the rest counted', '[["Auth","Ops"],1]', do { local $Quad::THRESHOLD{per_horizon} = 2; my $qq = quad($s); [ [ map { $_->{epic} } @{ $qq->{milestones}{60} } ], $qq->{milestones_more}{60} ] };
S 'accomplishment: RPT-201 done this week, late (was carried over)', '[["RPT-201","2026-08-28",0,"carried over"]]', [ map { [ $_->{id}, $_->{date}, $_->{ontime}, $_->{late_why} ] } @{ $q->{accomplishments} } ];
S 'metrics', '[31,31,"same",0,0,1,0,1]', [ @{ $q->{metrics}{sprint} }{qw(pct prev_pct trend punted)}, @{ $q->{metrics}{ontime} }{qw(week_ontime week_total sprint_ontime sprint_total)} ];
S 'team filter', '[["RPT-201","Cy"],["RPT-202","Cy"]]', [ map { [ $_->{id}, $_->{owner} ] } @{ quad($s, team => 'Bravo')->{priorities} } ];
S 'team filter narrows the watch list', '["Bravo"]', [ map { $_->{team} } @{ quad($s, team => 'Bravo')->{watch} } ];
S 'accomplishments window: only the last 7 days', '["RPT-201"]', [ map { $_->{id} } @{ quad(load("$FindBin::Bin/../examples/scrum.txt", today => '2026-08-30'))->{accomplishments} } ];

# ---- text and HTML
my $txt = quad_text($s);
has 'quad_text', $txt, qr/^Weekly status -- as of 2026-09-01 \(sprint 42\)/m, qr/^Sprint progress 31% \(8\/26 SP\) same \(was 31%\)   On-time delivery: 0\/1 this week, 0\/1 this sprint/m,
    qr/^  OPEN  AUTH-103    13  SSO/m, qr/^  \(WI\) Alpha      Alpha at 108% of capacity/m, qr/^    3\. \(none\) > Reporting\s+<-\s+62%  ETA 2026-10-18/m, qr/^  x RPT-201      8  Quarterly export\s+Cy  \(carried over\)/m;
has 'quad_text marked', quad_text($s, marking => { banner => 'INTERNAL' }), qr/^INTERNAL\n/, qr/\nINTERNAL\n$/;
my $html = quad_html($s, marking => { banner => 'INTERNAL', marking_poc => 'SA' });
has 'quad_html', $html, qr/^<!DOCTYPE html>/, qr/<p style="[^"]*" class="mark mark-top">INTERNAL<\/p>/, qr/<h2>Technical Priorities<\/h2>/, qr/<span class="tag OPEN">OPEN<\/span><\/td><td>AUTH-103</,
    qr/<h2>Watch Items \/ PM Help Needed<\/h2>/, qr/<span class="kind WI">\(WI\)<\/span>/, qr/<h3>60 days out<\/h3>/, qr/class="sev good">&#8592; pulled left</, qr/<td class="late">&#10007;<\/td><td>RPT-201</, qr/\@page\{size:landscape/;
S 'quad_html self-contained', 1, ($html !~ m{https?://|<script|<link } ? 1 : 0);

# ---- the four-letter words, end to end through Standup: WAIT HOLD PUNT REDO PASS SYNC DROP TODO, and shared DONE
my $dir = tempdir(CLEANUP => 1);
my $j = "$dir/scrum.txt";
open my $fh, '>', $j or die; print $fh <<'J'; close $fh;
2026-09-01 Intake T-1 Feed contract
    Backlog:Bravo   5 SP   ; id: T-1, prio: 1, owner: Dee
    Equity:Intake

2026-09-01 Intake T-2 Parser
    Backlog:Alpha   3 SP   ; id: T-2, prio: 2, owner: Ann
    Equity:Intake

2026-09-01 Intake T-3 Docs
    Backlog:Alpha   2 SP   ; id: T-3, prio: 3, owner: Bob
    Equity:Intake

2026-09-01 Intake T-4 Login page
    Backlog:Alpha   1 SP   ; id: T-4, owner: Bob
    Equity:Intake

2026-09-01 Intake T-5 Feed adapter
    Backlog:Alpha   2 SP   ; id: T-5, owner: Cy
    Equity:Intake

2026-09-01 Intake T-6 Hard one
    Backlog:Alpha   8 SP   ; id: T-6, prio: 1, owner: Ann
    Equity:Intake

2026-09-01 Intake T-7 Someday
    Backlog:Alpha   3 SP   ; id: T-7, prio: 9
    Equity:Intake

2026-08-20 Sprint 0 planning
    Backlog:Alpha             -1 SP   ; id: T-4
    Sprint:0:Alpha:Committed   1 SP   ; id: T-4

2026-08-28 Sprint 0 review
    Sprint:0:Alpha:Committed  -1 SP   ; id: T-4
    Sprint:0:Alpha:Done        1 SP   ; id: T-4

2026-09-02 Sprint 1 planning
    Backlog:Bravo             -5 SP   ; id: T-1
    Sprint:1:Bravo:Committed   5 SP   ; id: T-1
    Backlog:Alpha             -3 SP   ; id: T-2
    Sprint:1:Alpha:Committed   3 SP   ; id: T-2
    Backlog:Alpha             -2 SP   ; id: T-3
    Sprint:1:Alpha:Committed   2 SP   ; id: T-3
    Backlog:Alpha             -2 SP   ; id: T-5
    Sprint:1:Alpha:Committed   2 SP   ; id: T-5
    Backlog:Alpha             -8 SP   ; id: T-6
    Sprint:1:Alpha:Committed   8 SP   ; id: T-6
J
my $s2 = load($j, today => '2026-09-08');
my $su = parse_standup(join("\n", '2026-09-05', '== Alpha', 'block T-2 waiting on the feed spec', 'hold T-3 pulled onto the outage', 'punt T-6 needs splitting - too big as written',
                                  'redo T-4 demo found the reset mail unsent', 'pass T-5 Bravo', 'sync T-1 T-5', '== Bravo', ''), "$dir/2026-09-05.txt");
S 'verbs parsed', '[[["T-6","needs splitting - too big as written"]],[["T-4","demo found the reset mail unsent"]],[["T-5","Bravo"]],[["T-1","T-5"]]]', [ @{ $su->{teams}{Alpha} }{qw(punt redo pass sync)} ];
S 'verb errors', '["x:3: punt needs an id","x:4: pass needs id and the receiving team","x:5: sync needs two or more ids"]', parse_standup("2026-09-05\n== A\npunt\npass T-1\nsync T-1\n", 'x')->{errors};
my $posted = Standup::apply($s2, $su, $j);
has 'postings', $posted, qr/Sprint:1:Alpha:Committed\s+-8 SP\s+; id: T-6\n\s+Backlog:Alpha\s+8 SP\s+; id: T-6, punt: needs splitting - too big as written/,
    qr/Sprint:0:Alpha:Done\s+-1 SP\s+; id: T-4\n\s+Sprint:1:Alpha:Committed\s+1 SP\s+; id: T-4, redo: demo found the reset mail unsent/,
    qr/Sprint:1:Alpha:Committed\s+-2 SP\s+; id: T-5\n\s+Sprint:1:Bravo:Committed\s+2 SP\s+; id: T-5, pass: from Alpha, owner:/,
    qr/; id: T-1, sync: T-5/, qr/; id: T-5, sync: T-1/;
$s2 = load($j, today => '2026-09-08');
S 'states after the verbs', '["backlog","committed","committed","Bravo"]', [ $s2->{items}{'T-6'}{state}, $s2->{items}{'T-4'}{state}, $s2->{items}{'T-5'}{state}, $s2->{items}{'T-5'}{team} ];
my $q2 = quad($s2);
S 'tags and marks', '[["T-1","OPEN",["SYNC T-5 (waiting on T-5)"]],["T-2","WAIT",[]],["T-3","HOLD",[]],["T-4","OPEN",["REDO"]],["T-5","OPEN",["PASS from Alpha","SYNC T-1 (waiting on T-1)"]],["T-6","PUNT",[]],["T-7","TODO",[]]]',
    [ map { [ $_->{id}, $_->{tag}, $_->{marks} ] } @{ $q2->{priorities} } ];
S 'why on the row', '["waiting on the feed spec","pulled onto the outage","demo found the reset mail unsent","needs splitting - too big as written"]', [ map { $_->{why} } grep { $_->{id} =~ /^T-[2346]$/ } @{ $q2->{priorities} } ];
S 'watch: blocker, hold, punt, rework, passed without owner', '[["WI","T-2","blocked 3 days: waiting on the feed spec"],["WI","T-3","on hold: pulled onto the outage"],["WI","T-4","rework after the demo: demo found the reset mail unsent"],["WI","T-5","passed in, no owner yet"],["WI","T-6","punted, needs replanning: needs splitting - too big as written"]]',
    [ map { [ $_->{kind}, $_->{id}, $_->{text} ] } @{ $q2->{watch} } ];
S 'blocker older than 3 days becomes (PM)', '["PM",4]', [ map { ($_->{kind}, $_->{days}) } grep { $_->{id} eq 'T-2' } @{ quad(load($j, today => '2026-09-09'))->{watch} } ];
S 'slipped priorities', '["T-2","T-3","T-6"]', [ map { $_->{id} } @{ $q2->{slipped} } ];
S 'punted count in the metric', 1, $q2->{metrics}{sprint}{punted};
S 'TODO list capped', '[2,1]', do { local $Quad::THRESHOLD{todo_max} = 1; my $qq = quad($s2); [ scalar(grep { $_->{tag} =~ /^(PUNT|TODO)$/ } @{ $qq->{priorities} }) + 1, $qq->{todo_more} ] };
S 'epics/tomes OPEN while a task is in a sprint', '[1]', [ map { $_->{open} } epics($s2) ];

# shared DONE: T-1 finishes, T-5 has not -> T-1 stays OPEN and is not an accomplishment; when T-5 finishes both count, late-free
my $su2 = parse_standup("2026-09-06\n== Bravo\ndone T-1\n== Alpha\nresume T-3\nunblock T-2\n", "$dir/2026-09-06.txt");
Standup::apply($s2, $su2, $j);
$s2 = load($j, today => '2026-09-08');
S 'resume clears the hold', '[undef,undef]', [ $s2->{items}{'T-3'}{hold}, $s2->{items}{'T-3'}{hold_since} ];
my $q3 = quad($s2);
S 'sync: T-1 done but partner open -> OPEN, waiting', '[["T-1","OPEN","SYNC T-5 (waiting on T-5)"]]', [ map { [ $_->{id}, $_->{tag}, $_->{marks}[0] ] } grep { $_->{id} eq 'T-1' } @{ $q3->{priorities} } ];
S 'sync: not an accomplishment yet', '[]', [ map { $_->{id} } @{ $q3->{accomplishments} } ];
Standup::apply($s2, parse_standup("2026-09-07\n== Bravo\ndone T-5\n", "$dir/2026-09-07.txt"), $j);
$s2 = load($j, today => '2026-09-08');
my $q4 = quad($s2);
S 'sync: both done -> DONE, both accomplishments on the last date, on time', '[["T-1","DONE"],["T-5","DONE"]]', [ map { [ $_->{id}, $_->{tag} ] } grep { $_->{id} =~ /^T-[15]$/ } @{ $q4->{priorities} } ];
S 'sync accomplishments', '[["T-1","2026-09-07",1],["T-5","2026-09-07",1]]', [ map { [ $_->{id}, $_->{date}, $_->{ontime} ] } @{ $q4->{accomplishments} } ];
S 'pass mark gone once done', '["SYNC T-1"]', $q4->{priorities}[ (grep { $q4->{priorities}[$_]{id} eq 'T-5' } 0 .. $#{ $q4->{priorities} })[0] ]{marks};

# redo finished again: rework, late
Standup::apply($s2, parse_standup("2026-09-08\n== Alpha\ndone T-4\n", "$dir/2026-09-08.txt"), $j);
$s2 = load($j, today => '2026-09-08');
my $q5 = quad($s2);
S 'redone task finished: late, rework', '[["T-4",0,"rework"]]', [ map { [ $_->{id}, $_->{ontime}, $_->{late_why} ] } grep { $_->{id} eq 'T-4' } @{ $q5->{accomplishments} } ];
S 'sprint on-time excludes rework', '[2,3]', [ @{ $q5->{metrics}{ontime} }{qw(sprint_ontime sprint_total)} ];
S 'recommitting a punted task clears PUNT', '"OPEN"', do { Standup::apply($s2, parse_standup("2026-09-08\n== Alpha\ncommit T-6 Ann\n", "$dir/2026-09-08b.txt"), $j); my ($p) = grep { $_->{id} eq 'T-6' } @{ quad(load($j, today => '2026-09-08'))->{priorities} }; $p->{tag} };
S 'until: the journal as it stood', '["done","committed"]', [ load($j, today => '2026-08-28', until => '2026-08-28')->{items}{'T-4'}{state}, load($j, today => '2026-09-05', until => '2026-09-05')->{items}{'T-4'}{state} ];

print "1..$n\n";
print $bad ? "# $bad of $n FAILED\n" : "# all $n passed\n";
exit($bad ? 1 : 0);
