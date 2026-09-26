#!/usr/bin/perl
# perl tests/drill.t  — Drill.pm: initials, cards at every level, grading, Leitner progress, the sheet, the terminal loop, daily.pl drill
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use File::Temp qw(tempdir);
use File::Copy qw(copy);
use Prelude qw(show sorted);
use Scrum;
use Drill;

my ($n, $bad) = (0, 0);
sub check { my ($name, $got, $want) = @_; $n++;
    if ($got eq $want) { print "ok $n - $name\n" }
    else { $bad++; print "not ok $n - $name\n#   got:  $got\n#   want: $want\n" } }
sub S { my ($name, $want, $got) = @_; check($name, show($got), $want) }
sub has { my ($name, $text, @res) = @_; for my $re (@res) { check("$name: $re", ($text =~ $re ? 1 : 0), 1) } }

my $root = "$FindBin::Bin/..";
my $dir = tempdir(CLEANUP => 1);

# ---- initials: two words, one word, "Last, First", collisions, identical names
my $i = initials('Ann Lee', 'Bob', 'Archer, Sam', 'Jo Chen', 'Jo Cole', 'Ann Lee');
S 'initials', '{"Ann Lee":"AL","Archer, Sam":"SA","Bob":"Bo","Jo Chen":"JCh","Jo Cole":"JCo"}', $i;
S 'identical base, same extension', '{"Al Lee":"ALee","Al Leeds":"ALeed"}', initials('Al Lee', 'Al Leeds');

# ---- a small journal: two teams, a tome, two epics, owners, a blocker
my $j = "$dir/scrum.txt";
open my $fh, '>', $j or die;
print $fh <<'J';
2026-09-01 Intake C-1 Negotiate & Close
    Backlog:Alpha    5 SP   ; id: C-1, epic: C2 Win Contracts, tome: C Contracting, owner: Ann Lee
    Equity:Intake
2026-09-01 Intake C-2 Draft Proposal
    Backlog:Alpha    3 SP   ; id: C-2, epic: C2 Win Contracts, tome: C Contracting, owner: Bob Jones
    Equity:Intake
2026-09-01 Intake C-3 Screen Parties
    Backlog:Alpha    3 SP   ; id: C-3, epic: C1 Markets, tome: C Contracting, owner: Ann Lee
    Equity:Intake
2026-09-01 Intake L-1 Ship It
    Backlog:Bravo    2 SP   ; id: L-1, epic: Ops, owner: Cy Park
    Equity:Intake
2026-09-02 Sprint 1 planning
    Backlog:Alpha             -5 SP   ; id: C-1
    Sprint:1:Alpha:Committed   5 SP   ; id: C-1
2026-09-03 Stand-up
    Sprint:1:Alpha:Committed   0 SP   ; id: C-1, blocked: legal review of the terms
    Equity:Intake
J
close $fh;
my $s = load($j, today => '2026-09-26');
my $roster = [ { name => 'Dee Fox', team => 'Bravo' } ];
my $cards = cards($s, roster => $roster);
my %by = map { $_->{key} => $_ } @$cards;
S 'every level', '["team","who","home","tome","up","epic","now","next","task","what","blk"]', [ do { my %k; grep { !$k{$_}++ } map { $_->{kind} } @$cards } ];
S 'team card: owners and roster, as initials', '[["AL","BJ"],["CP","DF"]]', [ map { $by{$_}{want} } 'team:Alpha', 'team:Bravo' ];
S 'tome card: epic codes', '["C1","C2"]', $by{'tome:C Contracting'}{want};
S 'epic without a code keeps its name, no tome card', '[["L-1"],0]', [ $by{'epic:Ops'}{want}, exists $by{'up:Ops'} ? 1 : 0 ];
S 'up card: the tome code', '["C"]', $by{'up:C2 Win Contracts'}{want};
S 'now / next per person', '[["C-1"],["C-3"],["C-2"]]', [ map { $by{$_}{want} } 'now:Ann Lee', 'next:Ann Lee', 'next:Bob Jones' ];
S 'task card: owner initials, shown with the name', '[["AL"],"AL (Ann Lee)"]', [ @{ $by{'task:C-1'} }{qw(want show)} ];
S 'blocker card', '["legal review of the terms"]', $by{'blk:C-1'}{want};
S 'roster-only person has who and home', '[1,1,0]', [ map { exists $by{$_} ? 1 : 0 } 'who:Dee Fox', 'home:Dee Fox', 'now:Dee Fox' ];
my %ta = map { $_->{key} => 1 } @{ cards($s, team => 'Alpha', roster => $roster) };
S 'team filter: tome/epic keys carry the team, others do not', '[1,1,0,1]', [ map { $ta{$_} ? 1 : 0 } 'tome:C Contracting@Alpha', 'task:C-1', 'task:L-1', 'who:Ann Lee' ];

# ---- grading
my $g = sub { my ($k, $a) = @_; my $r = grade($by{$k}, $a); [ $r->{ok}, $r->{missed}, $r->{extra} ] };
S 'set: any order, case, commas', '[1,[],[]]', $g->('team:Alpha', 'bj, al');
S 'case never matters, every mode', '[1,1,1,1,1]', [ map { grade($by{$_->[0]}, $_->[1])->{ok} } ['task:C-1', 'al'], ['epic:C2 Win Contracts', 'c-1 C-2'], ['who:Ann Lee', 'aNN lEE'], ['what:C-1', 'NEGOTIATE close'], ['tome:C Contracting', 'c1 c2'] ];
S 'disambiguated initials in lower case', 1, grade({ mode => 'set', want => ['JCh'], vocab => { JCH => 1, JCO => 1 } }, 'jch')->{ok};
S 'set: a gap', '[0,["BJ"],[]]', $g->('team:Alpha', 'AL');
S 'set: wrong recall counts', '[0,[],["CP"]]', $g->('team:Alpha', 'AL BJ CP');
S 'set: ids', '[1,[],[]]', $g->('epic:C2 Win Contracts', 'C-2 C-1');
S 'set: an id that is not in it', '[0,[],["C-3"]]', $g->('epic:C2 Win Contracts', 'C-1 C-2 C-3');
S 'set: filler words ignored', '[1,[],[]]', $g->('home:Ann Lee', 'on the Alpha team');
S 'name: order free, Last, First', '[1,[],[]]', $g->('who:Ann Lee', 'lee ann');
S 'name: first name only is a miss', '[0,["LEE"],[]]', $g->('who:Ann Lee', 'ann');
S 'gist: half the words, prefixes', '[1,["CLOSE"],[]]', $g->('what:C-1', 'negot');
S 'gist: nothing', '[0,["NEGOTIATE","CLOSE"],[]]', $g->('what:C-1', 'proposal');
S 'gist: blocker', 1, grade($by{'blk:C-1'}, 'legal terms')->{ok};

# ---- progress: Leitner boxes, changed answers, pick order
my $p = {};
record($p, $by{'team:Alpha'}, 1, '2026-09-26');
S 'right: box 1, due tomorrow', '[1,"2026-09-27",1,0]', [ @{ $p->{'team:Alpha'} }{qw(box due right wrong)} ];
record($p, $by{'team:Alpha'}, 1, '2026-09-27'); record($p, $by{'team:Alpha'}, 1, '2026-09-28');
S 'up the boxes: 1, 1, 3 days', '[3,"2026-10-05"]', [ @{ $p->{'team:Alpha'} }{qw(box due)} ];
record($p, $by{'team:Alpha'}, 0, '2026-09-28');
S 'wrong: box 0, due tomorrow', '[0,"2026-09-29",3,1]', [ @{ $p->{'team:Alpha'} }{qw(box due right wrong)} ];
$p->{'team:Alpha'}{hook} = 'Al and BJ, the |A| team';
write_progress("$dir/drill.txt", $p);
my $back = read_progress("$dir/drill.txt");
S 'progress round trip, pipes flattened', '{"ans":"AL (Ann Lee) BJ (Bob Jones)","box":0,"due":"2026-09-29","hook":"Al and BJ, the /A/ team","right":3,"wrong":1}', $back->{'team:Alpha'};
S 'missing progress file', '{}', read_progress("$dir/nope.txt");

my $all = {}; record($all, $_, 1, '2026-09-20') for @$cards;           # everything known, due 2026-09-21
$all->{'task:C-2'}{ans} = 'CP (Cy Park)';                              # the journal reassigned it since
$all->{'who:Ann Lee'}{due} = '2026-10-30';
my @pk = pick($cards, $all, today => '2026-09-26', n => 3);
S 'pick: changed first, then due, in tree order', '[["team:Alpha","due"],["team:Bravo","due"],["task:C-2","changed"]]', [ map { [ $_->{key}, $_->{status} ] } @pk ];
S 'changed card remembers what it was', '"CP (Cy Park)"', (grep { $_->{status} eq 'changed' } @pk)[0]{was};
S 'pick: not due is skipped', 0, scalar(grep { $_->{key} eq 'who:Ann Lee' } pick($cards, $all, today => '2026-09-26', n => 99));
S 'pick: new cards round-robin across kinds', '["team","who","home","tome","up"]', [ map { $_->{kind} } pick($cards, {}, today => '2026-09-26', n => 5) ];

# ---- the sheet: write, answer, grade, hook, regrade is idempotent
my @sp = grep { $_->{key} =~ /^(team:Alpha|who:Ann Lee|what:C-1)$/ } pick($cards, {}, today => '2026-09-26', n => 99);
my $sheet = sheet_text(\@sp, today => '2026-09-26', team => 'Alpha');
has 'sheet', $sheet, qr/^; memory drill 2026-09-26 -- Alpha: 3 cards \(3 new\)$/m, qr/^; team: Alpha$/m, qr/^#1 team:Alpha  \(new\)\nTeam Alpha: who\? \(initials\)\n> $/m, qr/^#2 who:Ann Lee  \(new\)\nAL = \?/m;
(my $ans = $sheet) =~ s/^(Team Alpha.*\n)> $/$1> al bj/m;
$ans =~ s/^(AL = .*\n)> $/$1> ann/m;
my $pg = {};
my ($t1, $st1) = grade_sheet($ans, \%by, $pg, '2026-09-26');
S 'graded two, one to go', '[2,1,1,1,3]', [ @{$st1}{qw(graded ok miss)}, $st1->{total} - $st1->{done}, $st1->{total} ];
has 'graded sheet', $t1, qr/^> al bj\n= ok  AL \(Ann Lee\) BJ \(Bob Jones\)\n\n/m, qr/^> ann\n= miss  Ann Lee\nhook: \n/m, qr/^; score: 1\/3 ok, 1 missed, 1 to go$/m;
S 'progress recorded', '[1,0]', [ $pg->{'team:Alpha'}{box}, $pg->{'who:Ann Lee'}{box} ];
(my $t2 = $t1) =~ s/^hook: $/hook: Ann Lee -- Anne of the Lee shore/m;
my ($t3, $st2) = grade_sheet($t2, \%by, $pg, '2026-09-26');
S 'hook saved, nothing regraded', '[0,1,"Ann Lee -- Anne of the Lee shore",1]', [ $st2->{graded}, $st2->{hooks}, $pg->{'who:Ann Lee'}{hook}, $pg->{'who:Ann Lee'}{wrong} ];
S 'regrade is a no-op', '["same",0]', [ $t3 eq $t2 ? 'same' : 'differs', (grade_sheet($t3, \%by, $pg, '2026-09-26'))[1]{hooks} ];
(my $t4 = $t3) =~ s/^(C-1: what.*\n)> $/$1> ?/m;
my ($t5) = grade_sheet($t4, \%by, $pg, '2026-09-26');
has "'?' is a miss without a detail line", $t5, qr/^> \?\n= miss  Negotiate & Close\nhook: \n?\z/m;
my ($t6) = grade_sheet($t4, { %by, 'what:C-1' => undef }, {}, '2026-09-26');
has 'a card gone from the journal', $t6, qr/^> \?\n= gone/m;
# a later miss shows the person's hook
my ($t7) = grade_sheet("#1 task:C-1\nC-1: who?\n> BJ\n", \%by, $pg, '2026-09-27');
has 'miss shows the hooks of the people in the answer', $t7, qr/^= miss  AL \(Ann Lee\)\n  missed AL; not in it BJ\n  Ann Lee: Ann Lee -- Anne of the Lee shore$/m;
(my $t8 = $t3) =~ s/^hook: Ann Lee.*$/hook: -/m;
grade_sheet($t8, \%by, $pg, '2026-09-26');
S "'hook: -' forgets", '""', $pg->{'who:Ann Lee'}{hook};

# ---- the terminal loop
my $in = "AL BJ\nann\nAnn = Anne of the Lee shore\nq\n";
open my $ifh, '<', \$in; my $out = ''; open my $ofh, '>', \$out;
my $saves = 0; my $pt = {};
my $lst = drill_loop(\@sp, $pt, in => $ifh, out => $ofh, today => '2026-09-26', save => sub { $saves++ });
S 'loop: q stops, counts, saves per card', '[1,1,2]', [ $lst->{ok}, $lst->{miss}, $saves ];
S 'loop: hook typed after a miss', '"Ann = Anne of the Lee shore"', $pt->{'who:Ann Lee'}{hook};
has 'loop output', $out, qr/\[1\/3\] Team Alpha: who\? \(initials\)  \(new\)\n> = ok/, qr/= miss  Ann Lee\nhook \(enter to keep, - to forget\)> /, qr/1\/2 ok, 1 missed/;

# ---- daily.pl drill: --sheet, --grade, nothing due
my $proj = "$dir/proj"; mkdir $proj; mkdir "$proj/reports";
open my $c, '>', "$proj/scrum.conf" or die; print $c "journal = scrum.txt\nstandups = standups\nreports = reports\n"; close $c;
copy($j, "$proj/scrum.txt") or die "copy: $!";
open my $r, '>', "$proj/roster.txt" or die; print $r "Dee Fox | dee\@example.com | Bravo | Dev | ACME\n"; close $r;
sub cli { my $in = @_ && ref $_[0] ? ${ shift() } : undef; my $redir = '';   # quoted: on the CI runner $^X is /c/Program Files/Git/usr/bin/perl.exe
    if (defined $in) { open my $i, '>', "$dir/stdin.txt" or die; print $i $in; close $i; $redir = qq( < "$dir/stdin.txt") }
    scalar qx("$^X" "$root/bin/daily.pl" -c "$proj/scrum.conf" --today 2026-09-26 @_$redir 2>&1) }
my $f = cli('drill', '--sheet', '-n', 2, 'Alpha'); chomp $f;
has 'daily.pl drill --sheet', $f, qr{/reports/2026-09-26-drill\.txt$};
open my $sf, '<', $f or die "no sheet $f"; my $st = do { local $/; <$sf> }; close $sf;
has 'sheet has the team', $st, qr/^; team: Alpha$/m, qr/^#1 team:Alpha  \(new\)$/m;
$st =~ s/^> $/> AL BJ/m;
open my $wf, '>', $f or die; print $wf $st; close $wf;
my $go = cli('drill', '--grade', qq("$f"));
has 'daily.pl drill --grade', $go, qr/^graded 1, hooks saved 0 -- 1\/2 ok, 0 missed, 1 to go$/m;
has 'drill.txt written', do { open my $d, '<', "$proj/drill.txt" or die; local $/; <$d> }, qr/^team:Alpha \| 1 \| 2026-09-27 \| 1 \| 0 \| /m;
my $tl = cli(\"AL BJ\nq\n", 'drill', '-n', 1, 'Alpha');
has 'daily.pl drill in the terminal', $tl, qr/memory drill: 1 cards/, qr/\[1\/1\] /;
my $none = cli('drill', '-n', 0, 'Alpha');
has 'nothing due', $none, qr/^nothing due today \(\d+ cards/;

print "1..$n\n";
print $bad ? "# $bad of $n failed\n" : "# all $n passed\n";
exit($bad ? 1 : 0);
