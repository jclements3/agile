#!/usr/bin/perl
# perl t/standup.t
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use File::Temp qw(tempdir);
use File::Copy qw(copy);
use Cwd qw(getcwd);
$ENV{$_} //= 'ci@example.invalid' for qw(GIT_AUTHOR_EMAIL GIT_COMMITTER_EMAIL);   # daily.pl commit is under test; a fresh runner has no git identity
$ENV{$_} //= 'ci'                 for qw(GIT_AUTHOR_NAME  GIT_COMMITTER_NAME);
use Prelude qw(show fmap sorted);
use Scrum;
use Standup;

my ($n, $bad) = (0, 0);
sub check { my ($name, $got, $want) = @_; $n++;
    if ($got eq $want) { print "ok $n - $name\n" }
    else { $bad++; print "not ok $n - $name\n#   got:  $got\n#   want: $want\n" } }
sub S { my ($name, $want, $got) = @_; check($name, show($got), $want) }
sub has { my ($name, $text, @res) = @_; for my $re (@res) { check("$name: $re", ($text =~ $re ? 1 : 0), 1) } }
sub dies_like { my ($name, $re, $code) = @_; eval { $code->(); 1 } ? check($name, 'lived', "died matching $re") : check($name, ($@ =~ $re ? 1 : "no match: $@"), 1) }

my $root = "$FindBin::Bin/..";
my $s = load("$root/examples/scrum.txt", today => '2026-09-01');
$s->{unit} = 'SP';

# ---- config
my $dir = tempdir(CLEANUP => 1);
open my $fh, '>', "$dir/scrum.conf" or die $!; print $fh "# c\njournal = j.txt\nTo = a\@x.example\nbanner=INTERNAL\nmarking_poc = JC\n"; close $fh;
my $c = read_conf("$dir/scrum.conf");
S 'read_conf', '["j.txt","a@x.example","INTERNAL","JC","standups"]', [ @{$c}{qw(journal to banner marking_poc standups)} ];
S 'read_conf missing', '"scrum.txt"', read_conf("$dir/none")->{journal};
mkdir "$dir/deep"; mkdir "$dir/deep/er";
{ my $cwd = getcwd; chdir "$dir/deep/er"; S 'find_conf upward', 1, (find_conf() =~ m{/scrum\.conf$} ? 1 : 0); chdir $cwd }
S 'find_conf none', 'undef', find_conf('/');

# ---- parsing
my $su = parse_standup(<<'EOF', 'standups/2026-09-01.txt');
2026-09-01
sprint 42
note global note   ; trailing comment
== Alpha
; open: AUTH-103   13  SSO
done AUTH-103 AUTH-999
new AUTH-104 5 MFA enrolment p:1 e:Auth o:Ann
new! HOT-1 2 Hotfix o:Bob
commit AUTH-104
commit OPS-302 Ann
est AUTH-104 8
assign AUTH-104 Bob
cap 14
note Bob out Friday
risk vendor late
absent Cy Dee
== Bravo
carry RPT-202
drop RPT-201
block RPT-202 waiting on cert, from ISSM
unblock RPT-201
sprint 43
EOF
S 'date/sprint',  '["2026-09-01",42]', [ @{$su}{qw(date sprint)} ];
S 'order',        '["Alpha","Bravo"]', $su->{order};
S 'global notes', '["global note"]', $su->{notes};
my $a = $su->{teams}{Alpha};
S 'done',         '["AUTH-103","AUTH-999"]', $a->{done};
S 'new',          '[{"id":"AUTH-104","meta":{"epic":"Auth","owner":"Ann","prio":1},"now":0,"pts":5,"title":"MFA enrolment"},{"id":"HOT-1","meta":{"owner":"Bob"},"now":1,"pts":2,"title":"Hotfix"}]', $a->{new};
S 'commit',       '[["AUTH-104",undef],["OPS-302","Ann"]]', $a->{commit};
S 'est/assign/cap', '[[["AUTH-104",8]],[["AUTH-104","Bob"]],14]', [ $a->{est}, $a->{assign}, $a->{cap} ];
S 'note/risk/absent', '[["Bob out Friday"],["vendor late"],["Cy","Dee"]]', [ @{$a}{qw(note risk absent)} ];
my $b = $su->{teams}{Bravo};
S 'carry/drop',   '[["RPT-202"],["RPT-201"]]', [ $b->{carry}, $b->{drop} ];
S 'block',        '[["RPT-202","waiting on cert, from ISSM"]]', $b->{block};
S 'unblock',      '["RPT-201"]', $b->{unblock};
S 'team sprint',  43, $b->{sprint};
S 'no errors',    '[]', $su->{errors};
S 'compiled flag', 1, parse_standup("# compiled 2026-09-01 10:00\n2026-09-01\n", 'x.txt')->{compiled};
S 'new t: tome metadata', '{"epic":"Auth","owner":"Ann","prio":1,"tome":"Platform"}',
    parse_standup("2026-09-01\n== Alpha\nnew AUTH-105 5 SSO hardening p:1 e:Auth t:Platform o:Ann\n")->{teams}{Alpha}{new}[0]{meta};
S 'new quoted values', '{"epic":"E1 Set Direction","owner":"Ann Lee","prio":2,"tome":"E Executive & Strategy"}',
    parse_standup("2026-09-01\n== Executive\nnew E-111 3 Scan market e:\"E1 Set Direction\" t:\"E Executive & Strategy\" p:2 o:\"Ann Lee\"\n")->{teams}{Executive}{new}[0]{meta};
S 'new quoted title intact', '"Scan market & race scene"',
    parse_standup("2026-09-01\n== Executive\nnew E-111 3 Scan market & race scene e:\"E1 Set Direction\"\n")->{teams}{Executive}{new}[0]{title};
S 'date from name', '"2026-09-02"', parse_standup("== A\n", 'standups/2026-09-02.txt')->{date};
my $e = parse_standup("done X-1\n== A\nfoo X-1\nest X-1 lots\nnew X-2\ncap many\n", 'x.txt');
S 'parse errors', '["x.txt:1: \'done\' needs a team section (== Team) first","x.txt:3: unknown verb \'foo\'","x.txt:4: est needs id and points","x.txt:5: new needs: id points title [p:N e:Epic t:Tome o:Owner]","x.txt:6: cap needs a number","x.txt: no date (put YYYY-MM-DD in the file name or on the first line)"]', $e->{errors};

# ---- compile
my $good = parse_standup(<<'EOF', 'standups/2026-09-01.txt');
2026-09-01
== Alpha
done AUTH-103
new AUTH-104 5 MFA enrolment p:1 e:Auth o:Ann
new! HOT-1 2 Hotfix o:Bob
commit AUTH-104 Ann
commit OPS-302
cap 14
== Bravo
carry RPT-202
est RPT-202 8
assign RPT-202 Dee
block RPT-202 waiting on cert, from ISSM
EOF
my $text = compile($s, $good);
check 'compile text', $text, <<'EOF';

; ---- standup 2026-09-01 (standups/2026-09-01.txt)
~ Sprint 42
    Alpha   14 SP

2026-09-01 Intake AUTH-104 MFA enrolment
    Backlog:Alpha                     5 SP   ; id: AUTH-104, epic: Auth, owner: Ann, prio: 1
    Equity:Intake

2026-09-01 Intake HOT-1 Hotfix
    Sprint:42:Alpha:Committed         2 SP   ; id: HOT-1, owner: Bob
    Equity:Intake

2026-09-01 Standup Alpha
    Backlog:Alpha                     -5 SP   ; id: AUTH-104
    Sprint:42:Alpha:Committed         5 SP   ; id: AUTH-104, owner: Ann
    Backlog:Master                    -3 SP   ; id: OPS-302
    Sprint:42:Alpha:Committed         3 SP   ; id: OPS-302
    Sprint:42:Alpha:Committed         -13 SP   ; id: AUTH-103
    Sprint:42:Alpha:Done              13 SP   ; id: AUTH-103

2026-09-01 Standup Bravo
    Sprint:42:Bravo:Committed         -5 SP   ; id: RPT-202
    Sprint:42:Bravo:Carryover         5 SP   ; id: RPT-202
    Sprint:42:Bravo:Carryover         3 SP   ; id: RPT-202
    Equity:Intake                     -3 SP
    Sprint:42:Bravo:Carryover         0 SP   ; id: RPT-202, owner: Dee
    Equity:Intake                     0 SP
    Sprint:42:Bravo:Carryover         0 SP   ; id: RPT-202, blocked: waiting on cert; from ISSM
    Equity:Intake                     0 SP

EOF
S 'compile leaves state untouched', 7, scalar keys %{ $s->{items} };
S 'compile twice same', 1, (compile($s, $good) eq $text ? 1 : 0);
my $badsu = parse_standup("2026-09-01\n== Alpha\ndone NOPE-1\ndone AUTH-101\ncommit AUTH-103\nnew RPT-202 1 dup\nest ZZZ 3\n== Zulu\ndone AUTH-103\n", 'standups/2026-09-01.txt');
eval { compile($s, $badsu) };
has 'compile errors', $@, qr/unknown task 'NOPE-1'/, qr/'AUTH-101' is not committed in sprint 42 for Alpha \(at: Sprint:41:Alpha:Done\)/,
    qr/'AUTH-103' is not in a backlog or carryover for Alpha \(at: Sprint:42:Alpha:Committed\)/, qr/task 'RPT-202' already exists/, qr/unknown task 'ZZZ'/,
    qr/'AUTH-103' is not committed in sprint 42 for Zulu/;
S 'compile error count', 6, scalar(() = $@ =~ /\n/g);

# ---- refine / prune
my $rp = parse_standup("2026-09-01\n== Alpha\nrefine OPS-302\nprune OPS-302 superseded, by OPS-303\n", 'standups/2026-09-01.txt');
S 'parse refine/prune', '[[["OPS-302"]],[["OPS-302","superseded, by OPS-303"]]]', [ $rp->{teams}{Alpha}{refine}, $rp->{teams}{Alpha}{prune} ];
check 'compile refine then prune', compile($s, $rp), <<'EOF';

; ---- standup 2026-09-01 (standups/2026-09-01.txt)
2026-09-01 Standup Alpha
    Backlog:Master                    -3 SP   ; id: OPS-302
    Backlog:Alpha                     3 SP   ; id: OPS-302
    Backlog:Alpha                     -3 SP   ; id: OPS-302
    Sprint:42:Alpha:Removed           3 SP   ; id: OPS-302, pruned: superseded; by OPS-303

EOF
S 'day_notes refine/prune', '[["OPS-302"],["OPS-302: superseded, by OPS-303"]]', [ @{ day_notes($rp)->{teams}{Alpha} }{qw(refine prune)} ];
my $later = eval { compile($s, parse_standup("2026-09-01\n== Alpha\nrefine M-1\n== Master\nnew M-1 5 Enabler spike p:1\n", 'standups/2026-09-01.txt')) } // "ERR $@";
has 'intake in a later Master section visible to an earlier refine', $later, qr/^2026-09-01 Intake M-1 Enabler spike\n    Backlog:Master\s+5 SP   ; id: M-1, prio: 1/m,
    qr/Standup Alpha\n    Backlog:Master\s+-5 SP   ; id: M-1\n    Backlog:Alpha\s+5 SP   ; id: M-1\n/;
eval { compile($s, parse_standup("2026-09-01\n== Alpha\nrefine AUTH-103\nprune AUTH-103\nrefine NOPE\nprune\n", 'x.txt')) };
has 'refine/prune errors', $@, qr/x\.txt:6: prune needs an id/, qr/'AUTH-103' is not in the master backlog or another team's backlog/, qr/unknown task 'NOPE'/,
    qr/'AUTH-103' is not in a backlog \(at: Sprint:42:Alpha:Committed\); use drop for committed work/;
dies_like 'no sprint',      qr/no sprint number/, sub { my $s0 = load("$root/examples/scrum.txt"); $s0->{current} = undef; $s0->{sprints} = []; compile($s0, parse_standup("2026-09-01\n== Alpha\ncap 3\n", 'x.txt')) };
dies_like 'parse errors block compile', qr/unknown verb 'bogus'/, sub { compile($s, parse_standup("2026-09-01\n== Alpha\nbogus\n", 'x.txt')) };

# ---- apply / pending / mark_compiled / re-load
copy("$root/examples/scrum.txt", "$dir/j.txt") or die $!;
mkdir "$dir/standups";
open $fh, '>', "$dir/standups/2026-09-01.txt" or die $!; print $fh "2026-09-01\n== Alpha\ndone AUTH-103\n"; close $fh;
open $fh, '>', "$dir/standups/2026-09-02.txt" or die $!; print $fh "2026-09-02\n== Bravo\ndone RPT-202\n"; close $fh;
open $fh, '>', "$dir/standups/notes.txt" or die $!; print $fh "ignored\n"; close $fh;
S 'pending', '["DIR/standups/2026-09-01.txt","DIR/standups/2026-09-02.txt"]', [ map { s/\Q$dir\E/DIR/r } pending("$dir/standups") ];
my $s1 = load("$dir/j.txt", today => '2026-09-01');
apply($s1, read_standup("$dir/standups/2026-09-01.txt"), "$dir/j.txt");
S 'pending after apply', '["DIR/standups/2026-09-02.txt"]', [ map { s/\Q$dir\E/DIR/r } pending("$dir/standups") ];
has 'marked', do { open my $r, '<', "$dir/standups/2026-09-01.txt"; local $/; <$r> }, qr/^# compiled \d{4}-\d{2}-\d{2} \d{2}:\d{2}\n2026-09-01\n/;
my $s2 = load("$dir/j.txt", today => '2026-09-01');
S 'journal updated', '["done",42]', [ @{ $s2->{items}{'AUTH-103'} }{qw(state sprint)} ];
S 'summary after', '[13,13,0]', [ @{ sprint_summary($s2)->{teams}{Alpha} }{qw(committed done open)} ];

# ---- template & day_notes
my $t = template($s, '2026-09-03');
check 'template', $t, <<'EOF';
2026-09-03
sprint 42

== Alpha
; open: AUTH-103    13  SSO                          Bob

== Bravo
; open: RPT-202      5  Chart widget                 Cy

EOF
has 'template one team', template($s, '2026-09-03', ['Bravo']), qr/^== Bravo/m;
S 'template no team match', 1, (template($s, '2026-09-03', ['Zulu']) =~ /== Zulu\n; \(nothing committed\)/ ? 1 : 0);
my $d = day_notes($su, parse_standup("2026-09-01\nrisk second file\n== Alpha\ndone Z-1\n", 'y.txt'));
S 'day_notes', '{"date":"2026-09-01","extra":"","notes":["global note"],"risks":["second file"],"teams":{"Alpha":{"absent":["Cy","Dee"],"block":[],"carry":[],"done":["AUTH-103","AUTH-999","Z-1"],"drop":[],"new":["AUTH-104 (5)","HOT-1 (2)"],"note":["Bob out Friday"],"prune":[],"refine":[],"risk":["vendor late"]},"Bravo":{"absent":[],"block":["RPT-202: waiting on cert, from ISSM"],"carry":["RPT-202"],"done":[],"drop":["RPT-201"],"new":[],"note":[],"prune":[],"refine":[],"risk":[]}}}', $d;

# ---- blocked items, INTERNAL, notes in reports (via Scrum)
my $s3 = load("$dir/j.txt", today => '2026-09-02');
open $fh, '>>', "$dir/j.txt" or die $!; print $fh "\n2026-09-02 Standup Bravo\n    Sprint:42:Bravo:Committed  0 SP ; id: RPT-202, blocked: cert\n    Equity:Intake  0 SP\n"; close $fh;
$s3 = load("$dir/j.txt", today => '2026-09-02');
S 'blocked item', '"cert"', $s3->{items}{'RPT-202'}{blocked};
S 'blocked()', '["RPT-202"]', [ fmap(sub { $_[0]{id} }, blocked($s3)) ];
open $fh, '>>', "$dir/j.txt" or die $!; print $fh "\n2026-09-03 Standup Bravo\n    Sprint:42:Bravo:Committed  0 SP ; id: RPT-202, blocked:\n    Equity:Intake  0 SP\n"; close $fh;
S 'unblocked', 'undef', load("$dir/j.txt")->{items}{'RPT-202'}{blocked};
my $cui = { banner => 'INTERNAL', marking_owner => 'Program X', marking_category => 'Engineering', marking_handling => 'do not forward outside the program', marking_poc => 'SA' };
S 'marking_lines', '["Owner: Program X","Category: Engineering","Handling: do not forward outside the program","POC: SA"]', [ marking_lines($cui) ];
S 'marked_text',  '"INTERNAL\n\nbody\nOwner: Program X\nCategory: Engineering\nHandling: do not forward outside the program\nPOC: SA\n\nINTERNAL\n"', marked_text($cui, "body");
S 'marking off',   '"body"', marked_text({ banner => '' }, 'body');
S 'marking_check clean',  '[]', [ marking_check({ %$cui, subject_prefix => 'INTERNAL', mail_domains => 'example.com, partner.example' }, recipients => [ 'a@example.com; b@mail.partner.example', undef ]) ];
S 'marking_check outside mail_domains', 1, scalar(grep { /^error: recipient me\@other\.example is outside mail_domains/ } marking_check({ %$cui, subject_prefix => 'INTERNAL', mail_domains => 'example.com' }, recipients => ['me@other.example']));
S 'marking_check no domains: any recipient', '[]', [ marking_check({ %$cui, subject_prefix => 'INTERNAL' }, recipients => ['me@other.example']) ];
S 'marking_check fields', 3, scalar(grep { /^warn: / } marking_check({ banner => 'INTERNAL' }));
S 'marking_check off',    '[]', [ marking_check({ banner => '' }, recipients => ['me@other.example']) ];
S 'marked_page_html',    1, (marked_page_html($cui, 'BODY') =~ m{^<p style="[^"]*" class="mark mark-top">INTERNAL</p>\n<p [^>]*class="mark-block">Owner: Program X<br>.*?</p>\nBODY<p style="[^"]*" class="mark mark-bottom">INTERNAL</p>\n$}s ? 1 : 0);
S 'subject',   '["INTERNAL Sprint 42","Sprint 42"]', [ subject({ subject_prefix => 'INTERNAL' }, 'Sprint 42'), subject({}, 'Sprint 42') ];
my $et = email_text($s3, 42, notes => $d, marking => $cui);
has 'email_text notes+marking', $et, qr/^INTERNAL\n/, qr/BLOCKED: RPT-202 cert/, qr/^Alpha today:\n  done today: AUTH-103 AUTH-999 Z-1\n  new: AUTH-104 \(5\), HOT-1 \(2\)\n  absent: Cy Dee\n  note: Bob out Friday\n  risk: vendor late$/m, qr/^Risks:\n  second file$/m, qr/POC: SA\n\nINTERNAL\n$/;
my $eh = email_html($s3, 42, notes => $d, marking => $cui);
has 'email_html notes+marking', $eh, qr/^<p style="text-align:center;font-weight:bold[^>]*>INTERNAL<\/p>/, qr/<b>Blocked:<\/b> RPT-202 \(Bravo\) cert/, qr/<pre[^>]*>Alpha today:/, qr/Owner: Program X<br>Category: Engineering/, qr/>INTERNAL<\/p>\n$/;
my $dh = dashboard_html($s3, marking => $cui);
S 'dashboard marking top+bottom', 2, scalar(() = $dh =~ /font-weight:bold[^>]*>INTERNAL<\/p>/g);
has 'dashboard blocked', $dh, qr/Needs attention/, qr/<td>RPT-202<\/td><td>Bravo<\/td>.*<td>cert<\/td>/;

# ---- daily.pl end to end
my $proj = tempdir(CLEANUP => 1);
my $daily = "$root/bin/daily.pl";
sub cli { my $out = qx("$^X" "$daily" @_ 2>&1); ($? >> 8, $out) }
my ($rc, $out);
{
    my $cwd = getcwd;
    chdir $proj or die;
    ($rc, $out) = cli('init', '.');
    S 'init', '[0,1,1,1,1]', [ $rc, (-f 'scrum.conf' ? 1 : 0), (-f 'scrum.txt' ? 1 : 0), (-d 'standups' ? 1 : 0), (-d '.git' ? 1 : 0) ];
    has 'init hints', $out, qr/source .*vim\/scrum\.vim/;
    ($rc, $out) = cli('init', '.');
    has 'init idempotent', $out, qr/kept    scrum\.conf/;
    copy("$root/examples/scrum.txt", 'scrum.txt') or die $!;
    open my $cf, '>>', 'scrum.conf' or die; print $cf "banner = INTERNAL\nsubject_prefix = INTERNAL\nmarking_poc = JC\nto = leads\@x.example\n"; close $cf;
    ($rc, $out) = cli('--today', '2026-09-01', 'status');
    has 'status', $out, qr/7 tasks, sprint 42, teams Alpha\/Bravo/, qr/no pending stand-up files/, qr/sprint 42: 8\/26 SP done \(31%\), 18 open, 0 blocked/;
    ($rc, $out) = cli('--today', '2026-09-01', 'new');
    S 'new', '[0,"created\nstandups/2026-09-01.txt\n"]', [ $rc, $out ];
    ($rc, $out) = cli('--today', '2026-09-01', 'new');
    S 'new exists', '"exists\nstandups/2026-09-01.txt\n"', $out;
    open my $sf, '>>', 'standups/2026-09-01.txt' or die; print $sf "== Alpha\ndone AUTH-103\nnote Bob out Friday\n== Bravo\nblock RPT-202 cert\nrisk cert slip\n"; close $sf;
    ($rc, $out) = cli('--today', '2026-09-01', '--dry', 'compile');
    has 'dry compile', $out, qr/^# would append/, qr/Sprint:42:Alpha:Done              13 SP/;
    S 'dry leaves file', 0, (qx(head -1 standups/2026-09-01.txt) =~ /compiled/ ? 1 : 0);
    ($rc, $out) = cli('--today', '2026-09-01', 'compile');
    S 'compile', '[0,"applied standups/2026-09-01.txt (2 transactions)\n"]', [ $rc, $out ];
    ($rc, $out) = cli('--today', '2026-09-01', 'compile');
    S 'compile nothing', '"nothing to compile\n"', $out;
    mkdir 'deep'; chdir 'deep';
    ($rc, $out) = cli('--today', '2026-09-01', 'report');
    S 'report from subdir', '[0,1,1,1]', [ $rc, map { -f "../reports/$_" ? 1 : 0 } qw(dashboard.html 2026-09-01-status.html 2026-09-01-status.txt) ];
    chdir '..';
    my $txt = do { open my $r, '<', 'reports/2026-09-01-status.txt'; local $/; <$r> };
    has 'report content', $txt, qr/^INTERNAL\n/, qr/21\/26 SP done \(81%\)/, qr/BLOCKED: RPT-202 cert/, qr/note: Bob out Friday/, qr/risk: cert slip/, qr/POC: JC/;
    ($rc, $out) = cli('--today', '2026-09-01', 'commit');
    S 'commit', '[0,"committed\n"]', [ $rc, $out ];
    ($rc, $out) = cli('--today', '2026-09-01', 'commit');
    S 'commit clean', '"nothing to commit\n"', $out;
    S 'reports ignored by git', 1, (qx(git status --porcelain) eq '' ? 1 : 0);
    S 'git log', 1, (qx(git log --oneline) =~ /standup 2026-09-01/ ? 1 : 0);
    open $sf, '>', 'standups/2026-09-02.txt' or die; print $sf "2026-09-02\n== Alpha\ndone NOPE-1\n"; close $sf;
    ($rc, $out) = cli('--today', '2026-09-02', 'all');
    S 'all stops on error', '[1,1,0]', [ $rc, ($out =~ /unknown task 'NOPE-1'/ ? 1 : 0), (-f 'reports/2026-09-02-status.txt' ? 1 : 0) ];
    ($rc, $out) = cli('--today', '2026-09-02', 'blocked');
    S 'blocked cmd', '"RPT-202    Bravo  cert\n"', $out;
    ($rc, $out) = cli('bogus');
    S 'bad cmd', 2, $rc;
    # calendar integration on the mock backend
    open $cf, '>>', 'scrum.conf' or die; print $cf "calendar = mock\ncalendar_fixture = $root/examples/cal-fixture.json\nteam_from_subject = ^(\\w+)\\s+stand\n"; close $cf;
    ($rc, $out) = cli('--today', '2026-09-23', 'meetings');
    has 'meetings', $out, qr/^09:00-09:15  Alpha Stand-up\s+Teams 5 invited$/m, qr/Program sync\s+0 invited/;
    ($rc, $out) = cli('--today', '2026-09-23', 'attend');
    has 'attend', $out, qr/created\nstandups\/2026-09-23\.txt/, qr/accepted:    Ann, Bob/, qr/-> attendance\.csv \(3 rows\)/, qr/appended attendance to standups\/2026-09-23\.txt/;
    my $suf = do { open my $r, '<', 'standups/2026-09-23.txt'; local $/; <$r> };
    has 'attend file', $suf, qr/^== Bravo\n; 09:20  Bravo Stand-up  \(3 invited\)\n;   tentative:   Cy\n;   declined:    Dee\n; absent Dee   ; declined in calendar$/m;
    S 'attend parses clean', '[]', read_standup('standups/2026-09-23.txt')->{errors};
    ($rc, $out) = cli('--today', '2026-09-23', 'attend');
    has 'attend idempotent', $out, qr/\(0 rows\)/;
    S 'attend no duplicate block', 1, scalar(() = do { open my $r, '<', 'standups/2026-09-23.txt'; local $/; <$r> } =~ /; ---- calendar/g);
    S 'attendance csv', 6, scalar(() = do { open my $r, '<', 'attendance.csv'; local $/; <$r> } =~ /\n/g);
    ($rc, $out) = cli('--today', '2026-09-23', 'post');
    has 'post', $out, qr/posted metrics to 'Alpha Stand-up' 09:00 \(saved\)/, qr/mock: post EV-BRAVO-0923/;
    ($rc, $out) = cli('--today', '2026-09-24', 'attend');
    has 'attend other day', $out, qr/declined:    Ann/;
    ($rc, $out) = cli('--today', '2026-09-25', 'attend');
    has 'attend none', $out, qr/no stand-up meetings on 2026-09-25/;
    chdir $cwd;
}

print "1..$n\n";
print $bad ? "# $bad of $n FAILED\n" : "# all $n passed\n";
exit($bad ? 1 : 0);
