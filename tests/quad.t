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
S 'priorities: tag, id, owner', '[["TODO","AUTH-103","Bob"],["DONE","RPT-201","Cy"],["TODO","RPT-202","Cy"]]', [ map { [ $_->{tag}, $_->{id}, $_->{owner} ] } @{ $q->{priorities} } ];
S 'OPEN when mentioned in a status this week', '["OPEN","TODO"]', [ map { $_->{tag} } grep { $_->{id} =~ /^(AUTH-103|RPT-202)$/ } @{ quad($s, open => { 'AUTH-103' => 1 })->{priorities} } ];
S 'watch: both teams over capacity, WI not PM', '[["WI","Alpha"],["WI","Bravo"]]', [ map { [ $_->{kind}, $_->{team} ] } @{ $q->{watch} } ];
S 'milestones: 60 days out, priority order, arrows', '[[1,"Auth","same"],[2,"Ops","same"],[3,"Reporting","pulled"]]', [ map { [ $_->{priority}, $_->{epic}, $_->{trend} ] } @{ $q->{milestones}{60} } ];
S 'milestones: nothing at 30 or 90, none hidden', '[0,0,0]', [ scalar @{ $q->{milestones}{30} }, scalar @{ $q->{milestones}{90} }, $q->{milestones_more}{60} ];
S 'milestones: top N per horizon, the rest counted', '[["Auth","Ops"],1]', do { local $Quad::THRESHOLD{per_horizon} = 2; my $qq = quad($s); [ [ map { $_->{epic} } @{ $qq->{milestones}{60} } ], $qq->{milestones_more}{60} ] };
S 'accomplishment: RPT-201 done this week, late (was carried over)', '[["RPT-201","2026-08-28",0]]', [ map { [ $_->{id}, $_->{date}, $_->{ontime} ] } @{ $q->{accomplishments} } ];
S 'metrics', '[31,31,"same",0,1,0,1]', [ @{ $q->{metrics}{sprint} }{qw(pct prev_pct trend)}, @{ $q->{metrics}{ontime} }{qw(week_ontime week_total sprint_ontime sprint_total)} ];
S 'team filter', '[["RPT-201","Cy"],["RPT-202","Cy"]]', [ map { [ $_->{id}, $_->{owner} ] } @{ quad($s, team => 'Bravo')->{priorities} } ];
S 'team filter narrows the watch list', '["Bravo"]', [ map { $_->{team} } @{ quad($s, team => 'Bravo')->{watch} } ];

# nothing done in the window when the week ends before the Done posting
S 'accomplishments window: only the last 7 days', '["RPT-201"]', [ map { $_->{id} } @{ quad(load("$FindBin::Bin/../examples/scrum.txt", today => '2026-08-30'))->{accomplishments} } ];

# ---- text and HTML
my $txt = quad_text($s);
has 'quad_text', $txt, qr/^Weekly status -- as of 2026-09-01 \(sprint 42\)/m, qr/^Sprint progress 31% \(8\/26 SP\) same \(was 31%\)   On-time delivery: 0\/1 this week, 0\/1 this sprint/m,
    qr/^  TODO  AUTH-103    13  SSO/m, qr/^  \(WI\) Alpha      Alpha at 108% of capacity/m, qr/^    3\. \(none\) > Reporting\s+<-\s+62%  ETA 2026-10-18/m, qr/^  x RPT-201      8  Quarterly export/m;
has 'quad_text marked', quad_text($s, marking => { banner => 'INTERNAL' }), qr/^INTERNAL\n/, qr/\nINTERNAL\n$/;
my $html = quad_html($s, marking => { banner => 'INTERNAL', marking_poc => 'SA' });
has 'quad_html', $html, qr/^<!DOCTYPE html>/, qr/<p style="[^"]*" class="mark mark-top">INTERNAL<\/p>/, qr/<h2>Technical Priorities<\/h2>/, qr/<span class="tag TODO">TODO<\/span><\/td><td>AUTH-103</,
    qr/<h2>Watch Items \/ PM Help Needed<\/h2>/, qr/<span class="kind WI">\(WI\)<\/span>/, qr/<h3>60 days out<\/h3>/, qr/class="sev good">&#8592; pulled left</, qr/<td class="late">&#10007;<\/td><td>RPT-201</, qr/\@page\{size:landscape/;
S 'quad_html self-contained', 1, ($html !~ m{https?://|<script|<link } ? 1 : 0);

# ---- tags from a journal with block / hold / carryover / drop / reopen / hand-off / interface, built through Standup
my $dir = tempdir(CLEANUP => 1);
my $j = "$dir/scrum.txt";
open my $fh, '>', $j or die; print $fh <<'J'; close $fh;
2026-09-01 Intake T-1 Interface: feed from Alpha to Bravo
    Backlog:Bravo   5 SP   ; id: T-1, prio: 1
    Equity:Intake

2026-09-01 Intake T-2 Parser
    Backlog:Alpha   3 SP   ; id: T-2, prio: 2, owner: Ann
    Equity:Intake

2026-09-01 Intake T-3 Docs
    Backlog:Alpha   2 SP   ; id: T-3, prio: 3, owner: Bob
    Equity:Intake

2026-09-01 Intake T-4 Old task
    Backlog:Alpha   1 SP   ; id: T-4, owner: Bob
    Equity:Intake

2026-09-01 Intake T-5 Moved task
    Backlog:Alpha   2 SP   ; id: T-5, owner: Cy
    Equity:Intake

2026-09-02 Sprint 1 planning
    Backlog:Bravo             -5 SP   ; id: T-1, owner: Dee
    Sprint:1:Bravo:Committed   5 SP   ; id: T-1
    Backlog:Alpha             -3 SP   ; id: T-2
    Sprint:1:Alpha:Committed   3 SP   ; id: T-2
    Backlog:Alpha             -2 SP   ; id: T-3
    Sprint:1:Alpha:Committed   2 SP   ; id: T-3
    Backlog:Alpha             -1 SP   ; id: T-4
    Sprint:1:Alpha:Committed   1 SP   ; id: T-4
    Backlog:Alpha             -2 SP   ; id: T-5
    Backlog:Bravo              2 SP   ; id: T-5
    Backlog:Bravo             -2 SP   ; id: T-5
    Sprint:1:Bravo:Committed   2 SP   ; id: T-5

2026-09-03 Standup Alpha
    Sprint:1:Alpha:Committed  -1 SP   ; id: T-4
    Sprint:1:Alpha:Done        1 SP   ; id: T-4

2026-09-04 Standup Alpha
    Sprint:1:Alpha:Done       -1 SP   ; id: T-4
    Sprint:1:Alpha:Committed   1 SP   ; id: T-4
J
my $s2 = load($j, today => '2026-09-08');
my $su = parse_standup("2026-09-05\n== Alpha\nblock T-2 waiting on the feed spec\nhold T-3 pulled onto the outage\n== Bravo\ncarry T-5\n", "$dir/2026-09-05.txt");
S 'hold verb parsed', '[["T-3","pulled onto the outage"]]', $su->{teams}{Alpha}{hold};
my $posted = Standup::apply($s2, $su, $j);
has 'hold compiles to a hold: posting', $posted, qr/; id: T-3, hold: pulled onto the outage/;
$s2 = load($j, today => '2026-09-08');
S 'hold and hold_since on the item', '["pulled onto the outage","2026-09-05","2026-09-05"]', [ $s2->{items}{'T-3'}{hold}, $s2->{items}{'T-3'}{hold_since}, $s2->{items}{'T-2'}{blocked_since} ];
my $q2 = quad($s2);
S 'tags: WAIT HOLD REDO PUNT PASS SYNC', '[["T-1","TODO",["SYNC"]],["T-2","WAIT",[]],["T-3","HOLD",[]],["T-4","TODO",["REDO"]],["T-5","PUNT",["PASS from Alpha"]]]', [ map { [ $_->{id}, $_->{tag}, $_->{marks} ] } @{ $q2->{priorities} } ];
S 'watch: fresh blocker is WI, hold and carryover listed', '[["WI","T-2",3],["WI","T-3",0],["WI","T-5",0]]', [ map { [ $_->{kind}, $_->{id}, $_->{days} ] } @{ $q2->{watch} } ];
S 'blocker older than 3 days becomes (PM)', '["PM",4]', [ map { ($_->{kind}, $_->{days}) } grep { $_->{id} eq 'T-2' } @{ quad(load($j, today => '2026-09-09'))->{watch} } ];
S 'slipped priorities', '["T-2","T-3","T-5"]', [ map { $_->{id} } @{ $q2->{slipped} } ];
my $su2 = parse_standup("2026-09-06\n== Alpha\nresume T-3\nunblock T-2\n", "$dir/2026-09-06.txt");
Standup::apply($s2, $su2, $j);
$s2 = load($j, today => '2026-09-08');
S 'resume clears the hold', '[undef,undef]', [ $s2->{items}{'T-3'}{hold}, $s2->{items}{'T-3'}{hold_since} ];
S 'until: the journal as it stood', '["done","committed"]', [ load($j, today => '2026-09-03', until => '2026-09-03')->{items}{'T-4'}{state}, load($j, today => '2026-09-04', until => '2026-09-04')->{items}{'T-4'}{state} ];

print "1..$n\n";
print $bad ? "# $bad of $n FAILED\n" : "# all $n passed\n";
exit($bad ? 1 : 0);
