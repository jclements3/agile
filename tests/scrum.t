#!/usr/bin/perl
# perl t/scrum.t
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use File::Temp qw(tempdir);
use Prelude qw(show fmap sorted);
use Scrum;

my ($n, $bad) = (0, 0);
sub check { my ($name, $got, $want) = @_; $n++;
    if ($got eq $want) { print "ok $n - $name\n" }
    else { $bad++; print "not ok $n - $name\n#   got:  $got\n#   want: $want\n" } }
sub S { my ($name, $want, $got) = @_; check($name, show($got), $want) }
sub has { my ($name, $text, @res) = @_; for my $re (@res) { check("$name: $re", ($text =~ $re ? 1 : 0), 1) } }

my $file = "$FindBin::Bin/../examples/scrum.txt";
my $s = load($file, today => '2026-09-01');

# ---- meta & loading
S 'parse_meta',   '{"epic":"Auth","id":"A-1","prio":2}', parse_meta('id: A-1, prio: 2, epic: Auth');
S 'parse_meta empty', '{}', parse_meta(undef);
S 'teams',        '["Alpha","Bravo"]', $s->{teams};
S 'sprints',      '[41,42]', $s->{sprints};
S 'current',      42, $s->{current};
S 'capacity',     '{41:{"Alpha":10,"Bravo":12},42:{"Alpha":12,"Bravo":12}}', $s->{capacity};
S 'item count',   7, scalar keys %{ $s->{items} };
my $it = $s->{items}{'AUTH-101'};
S 'item title',   '"Login page"', $it->{title};
S 'item state',   '["done",41,"Alpha","Bob",5]', [ @{$it}{qw(state sprint team owner points)} ];
S 'item created', '"2026-08-03"', $it->{created};
S 'item age',     29, $it->{age};
S 'item location', '["Sprint:41:Alpha:Done"]', $it->{location};
S 'item history', 7, scalar @{ $it->{history} };
S 'item meta',    '{"epic":"Auth","owner":"Bob","prio":1}', $it->{meta};
S 'carry then done', '["done",42,"Bravo"]', [ @{ $s->{items}{'RPT-201'} }{qw(state sprint team)} ];
S 'master item',  '["master","Master"]', [ @{ $s->{items}{'OPS-302'} }{qw(state team)} ];
S 'committed item', '["committed",42,"Alpha","Bob"]', [ @{ $s->{items}{'AUTH-103'} }{qw(state sprint team owner)} ];
S 'days_between', 29, days_between('2026-08-03', '2026-09-01');

# ---- items filters
S 'items by state', '["AUTH-103","RPT-202"]', [ fmap(sub { $_[0]{id} }, items($s, state => 'committed')) ];
S 'items by team',  '["RPT-202"]', [ fmap(sub { $_[0]{id} }, items($s, state => 'committed', team => 'Bravo')) ];
S 'items by owner', '["AUTH-101","AUTH-103"]', [ sorted(fmap(sub { $_[0]{id} }, items($s, owner => 'Bob'))) ];
S 'items by epic',  '["AUTH-101","AUTH-103","AUTH-102"]', [ fmap(sub { $_[0]{id} }, items($s, epic => 'Auth')) ];
S 'items sprint',   '["AUTH-101","AUTH-102","OPS-301"]', [ fmap(sub { $_[0]{id} }, items($s, sprint => 41)) ];
S 'items prio order', '["AUTH-101","RPT-201","AUTH-103","AUTH-102","OPS-301","RPT-202","OPS-302"]', [ fmap(sub { $_[0]{id} }, items($s)) ];

# ---- sprint summary
my $r = sprint_summary($s, 42);
S 'summary alpha', '[12,13,0,13,0,0,0,108]', [ @{ $r->{teams}{Alpha} }{qw(capacity committed done open carryover removed pct load)} ];
S 'summary bravo', '[12,13,8,5,0,0,62,108]', [ @{ $r->{teams}{Bravo} }{qw(capacity committed done open carryover removed pct load)} ];
S 'summary totals', '[24,26,8,18,31,108]', [ @{ $r->{totals} }{qw(capacity committed done open pct load)} ];
S 'summary open items', '["RPT-202"]', [ fmap(sub { $_[0]{id} }, @{ $r->{teams}{Bravo}{open_items} }) ];
my $r41 = sprint_summary($s, 41);
S 'sprint 41 bravo', '[10,2,0,8,20,83]', [ @{ $r41->{teams}{Bravo} }{qw(committed done open carryover pct load)} ];
S 'sprint 41 carry', '[]', [ fmap(sub { $_[0]{id} }, @{ $r41->{teams}{Bravo}{carry_items} }) ];   # RPT-201 moved on to sprint 42
S 'default sprint', 42, sprint_summary($s)->{sprint};

# ---- velocity
my $v = velocity($s);
S 'velocity rows',  '[{"capacity":10,"committed":8,"done":8,"sprint":41},{"capacity":12,"committed":13,"done":0,"sprint":42}]', $v->{team}{Alpha};
S 'velocity avg excludes in-progress', '{"Alpha":8,"Bravo":2}', $v->{avg};
S 'velocity last 1', 2, velocity($s, last => 1)->{avg}{Bravo};

# ---- backlogs & members
S 'master backlog', '["OPS-302"]', [ fmap(sub { $_[0]{id} }, backlog($s)) ];
S 'team backlog empty', '[]', [ backlog($s, 'Alpha') ];
my $m = members($s);
S 'members',       '["Ann","Bob","Cy","Dee"]', [ sorted(keys %$m) ];
S 'member wip',    '[13,["AUTH-103"]]', [ $m->{Bob}{wip_points}, [ fmap(sub { $_[0]{id} }, @{ $m->{Bob}{wip} }) ] ];
S 'member done',   '["RPT-201"]', [ fmap(sub { $_[0]{id} }, @{ $m->{Cy}{done} }) ];
S 'member team',   '"Bravo"', $m->{Dee}{team};
S 'members by team', '["Cy","Dee"]', [ sorted(keys %{ members($s, 'Bravo') }) ];
S 'unassigned',    '[]', [ unassigned($s) ];

# ---- epics
my @ep = epics($s);
S 'epics', '[["(none)","Auth",3,21,8,13,0,38],["(none)","Ops",2,5,2,0,3,40],["(none)","Reporting",2,13,8,5,0,62]]', [ map { [ @{$_}{qw(tome epic)}, scalar @{ $_->{items} }, @{$_}{qw(total done wip backlog pct)} ] } @ep ];
has 'epics_text', epics_text($s), qr/^Tome    Epic       Tasks  Total  Done  In sprint  Backlog  Done%$/m, qr/^\(none\)  Auth           3     21     8         13        0    38%$/m;
has 'dashboard epics', dashboard_html($s), qr/<h2>Epics<\/h2>/;

# ---- roadmap
my $rm = roadmap($s);
S 'roadmap sprints', '[41,42,43,44,45]', $rm->{sprints};
S 'roadmap auth', '["(none)","Auth",["Alpha"],41,42,44,8,21,13,38,2,8,0]', [ @{ $rm->{epics}[0] }{qw(tome epic teams first last end done total remaining pct forecast_sprints velocity blocked)} ];
S 'roadmap auth per sprint', '{41:{"committed":8,"done":8},42:{"committed":13}}', $rm->{epics}[0]{per_sprint};
has 'roadmap_text', roadmap_text($s), qr/^Roadmap: epics by tome, sprints 41-45 \(current 42/m,
    qr/^\(none\) > Auth       #=\.\.    38%  8\/21 SP  ETA sprint 44$/m, qr/^\(none\) > Reporting  =#\.\.\.   62%  8\/13 SP  ETA sprint 45$/m;
my $rh = roadmap_html($s);
has 'roadmap_html', $rh, qr/<caption>Epics by tome: roadmap<\/caption>/, qr/<tr class=tome><td colspan="10">\(none\)/, qr/<th class="n cur">42<\/th>/, qr/<td class="a">8<\/td>/, qr/<td class="f">/, qr/sprint 44/;
S 'roadmap html balanced, no script/external', 1, (((() = $rh =~ /<table/g) == (() = $rh =~ /<\/table>/g)) && $rh !~ /<script|src=|href=/ ? 1 : 0);

# ---- unassigned + reassignment + title override in a tiny journal
my $dir = tempdir(CLEANUP => 1);
open my $fh, '>', "$dir/t.txt" or die $!;
print $fh <<'EOF';
2026-09-01 Intake X-1 First
    Backlog:Master   5 SP   ; id: X-1, title: Better title
    Equity:Intake
2026-09-02 Sprint 1 planning   ; owner: Ann
    Backlog:Master            -5 SP   ; id: X-1
    Sprint:1:Zulu:Committed    5 SP   ; id: X-1
2026-09-03 Reassign
    Sprint:1:Zulu:Committed    0 SP   ; id: X-1, owner: Bob
    Equity:Intake              0 SP
2026-09-03 Intake X-2 Orphan
    Sprint:1:Zulu:Committed    3 SP   ; id: X-2
    Equity:Intake
EOF
close $fh;
my $s2 = load("$dir/t.txt", today => '2026-09-10');
S 'title override', '"Better title"', $s2->{items}{'X-1'}{title};
S 'txn-level meta then reassign', '"Bob"', $s2->{items}{'X-1'}{owner};
S 'unassigned found', '["X-2"]', [ fmap(sub { $_[0]{id} }, unassigned($s2)) ];
has 'members warns', members_text($s2), qr/UNASSIGNED committed tasks: X-2/;

# ---- text reports
check 'sprint_text', sprint_text($s, 42), <<'EOF';
Teams: sprint 42
Team   Cap  Commit  Done  Open  Carry  Removed  Done%  Load%
-----  ---  ------  ----  ----  -----  -------  -----  -----
Alpha   12      13     0    13      0        0     0%   108%
Bravo   12      13     8     5      0        0    62%   108%
Total   24      26     8    18      0        0    31%   108%

Alpha open tasks (1):
ID        SP  Prio  Tome  Epic  Owner  Age  Title  Blocked
--------  --  ----  ----  ----  -----  ---  -----  -------
AUTH-103  13     1        Auth  Bob     12  SSO

Bravo open tasks (1):
ID       SP  Prio  Tome  Epic       Owner  Age  Title         Blocked
-------  --  ----  ----  ---------  -----  ---  ------------  -------
RPT-202   5     3        Reporting  Cy      28  Chart widget
EOF
has 'velocity_text', velocity_text($s), qr/^Alpha  \(avg velocity 8\.0 over last 3 completed\)$/m, qr/^    41   10       8     8   100%$/m;
check 'backlog_text', backlog_text($s), <<'EOF';
Master backlog: 1 tasks, 3 SP
ID       SP  Prio  Tome  Epic  Owner  Age  Title         Blocked
-------  --  ----  ----  ----  -----  ---  ------------  -------
OPS-302   3     4        Ops           28  Alert tuning
EOF
has 'members_text', members_text($s), qr/^Bob \(Alpha\)  WIP 13 SP in 1 tasks, done this sprint 0, queued 0$/m, qr/^    RPT-201      8  Quarterly export$/m;
check 'email_text', email_text($s, 42), <<'EOF';
Sprint 42 status as of 2026-09-01: 8/26 SP done (31%), 18 open, 0 carried over.

Alpha: 0/13 done (0%), 13 open, load 108% of capacity
  open: AUTH-103 (13)
Bravo: 8/13 done (62%), 5 open, load 108% of capacity
  open: RPT-202 (5)
EOF

# ---- HTML
my $d = dashboard_html($s);
has 'dashboard', $d, qr/^<!DOCTYPE html>/, qr/<h2>Sprint 42<\/h2>/, qr/<h2>Velocity<\/h2>/, qr/Master backlog <span class=muted>1 tasks, 3 SP/,
    qr/<summary>Alpha <span class=muted>0 tasks, 0 SP<\/span><\/summary>\s*<p class=muted>empty/, qr/<td>Bob<\/td><td>Alpha<\/td><td class=n>13<\/td>/,
    qr/class="chip warning">.*108% LOAD/, qr/Needs attention/, qr/Chart widget/;
S 'dashboard tables balanced', 1, ((() = $d =~ /<table/g) == (() = $d =~ /<\/table>/g) ? 1 : 0);
S 'dashboard no script/external', 1, ($d !~ /<script|src=|href=/ ? 1 : 0);
my $e = email_html($s, 42);
has 'email_html', $e, qr/<b>Sprint 42 status as of 2026-09-01:<\/b> 8 of 26 SP done \(31%\)/, qr/<td style="[^"]+">Total<\/td><td [^>]+>26<\/td>/,
    qr/<b>Bravo still open:<\/b> RPT-202 Chart widget \(5 SP, Cy\)/;
S 'email html inline only', 1, ($e !~ /<style|class=/ ? 1 : 0);

# ---- brief (BLUF leadership mail)
my ($level, $headline) = brief_status($s, 42);
S 'brief_status amber', '"amber"', $level;
has 'brief_status headline', $headline, qr/approaching capacity/;
S 'brief_subject deterministic', 1, (brief_subject($s, 42) eq brief_subject($s, 42) ? 1 : 0);
has 'brief_subject', brief_subject($s, 42), qr/^\[AMBER\] Sprint 42, 2026-09-01: 31% done, \w+ approaching capacity$/;
my $bt = brief_text($s, 42);
has 'brief_text', $bt, qr/^AMBER -- Sprint 42, 2026-09-01: 31% done\./m, qr/^- \w+ approaching capacity \(108%\)$/m;
S 'brief_text at most 2 bullets here', 1, ((() = $bt =~ /^- /mg) <= 2 ? 1 : 0);
my $bh = brief_html($s, 42);
has 'brief_html', $bh, qr/>AMBER</, qr/<li[^>]*>\w+ approaching capacity \(108%\)<\/li>/;
S 'brief_html inline only', 1, ($bh !~ /<style|class=/ ? 1 : 0);
S 'html escaping', '"&lt;a&gt; &amp; &quot;b&quot;"', Scrum::_h('<a> & "b"');

# ---- Outlook script (not executed)
my $ps = outlook_script('C:\\Temp\\m.html', to => "a\@x.example; b\@x.example", cc => '', subject => "Sprint 42 O'Brien");
has 'outlook script', $ps, qr/New-Object -ComObject Outlook\.Application/, qr/\$m\.To = 'a\@x\.example; b\@x\.example'/, qr/Subject = 'Sprint 42 O''Brien'/,
    qr/ReadAllText\('C:\\Temp\\m\.html', \[Text\.Encoding\]::UTF8\)/, qr/\$m\.Display\(\)$/;

# ---- CLI
my $bin = "$FindBin::Bin/../bin/scrum.pl";
sub cli { my $out = qx("$^X" "$bin" @_ 2>&1); ($? >> 8, $out) }
my ($rc, $out);
($rc, $out) = cli('-f', $file, '--today', '2026-09-01', 'check');
S 'cli check',    '[0,"ok: 7 items, teams Alpha/Bravo, sprints 41/42\n"]', [ $rc, $out ];
($rc, $out) = cli('-f', $file, '--today', '2026-09-01', 'sprint', '41');
has 'cli sprint 41', $out, qr/^Teams: sprint 41$/m, qr/^Bravo   12      10     2     0      8        0    20%    83%$/m;
($rc, $out) = cli('-f', $file, '--today', '2026-09-01', 'items', 'done', 'Alpha');
has 'cli items', $out, qr/^AUTH-101/m, qr/^AUTH-102/m;
S 'cli items count', 4, scalar(() = $out =~ /^\S/mg);
($rc, $out) = cli('-f', $file, '--today', '2026-09-01', 'dashboard', '-o', "$dir/dash.html");
S 'cli dashboard', '[0,"wrote DIR/dash.html\n",1]', [ $rc, $out =~ s/\Q$dir\E/DIR/r, (-s "$dir/dash.html" > 3000 ? 1 : 0) ];
($rc, $out) = cli('-f', $file, '--today', '2026-09-01', 'email', '--text');
has 'cli email text', $out, qr/^Sprint 42 status as of 2026-09-01/;
($rc, $out) = cli('-f', $file, 'email', '41');
has 'cli email html', $out, qr/<b>Sprint 41 status/;
{ local $ENV{SCRUM_FILE} = $file; ($rc, $out) = cli('backlog', 'Bravo') }
has 'cli env file', $out, qr/^Bravo backlog: 0 tasks, 0 SP$/m;
($rc, $out) = cli('-f', "$dir/missing.txt", 'sprint');
S 'cli missing', '[1,1]', [ $rc, ($out =~ /cannot open/ ? 1 : 0) ];
($rc, $out) = cli('-f', $file, 'nope');
S 'cli bad cmd', 2, $rc;

print "1..$n\n";
print $bad ? "# $bad of $n FAILED\n" : "# all $n passed\n";
exit($bad ? 1 : 0);
