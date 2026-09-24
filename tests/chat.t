#!/usr/bin/perl
# perl t/chat.t
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use File::Temp qw(tempdir);
use File::Copy qw(copy);
use Cwd qw(getcwd);
use Prelude qw(show fmap);
use Chat;

my ($n, $bad) = (0, 0);
sub check { my ($name, $got, $want) = @_; $n++;
    if ($got eq $want) { print "ok $n - $name\n" }
    else { $bad++; print "not ok $n - $name\n#   got:  $got\n#   want: $want\n" } }
sub S { my ($name, $want, $got) = @_; check($name, show($got), $want) }
sub has { my ($name, $text, @res) = @_; for my $re (@res) { check("$name: $re", ($text =~ $re ? 1 : 0), 1) } }
sub msgs { [ map { [ $_->{who}, $_->{time}, $_->{text} ] } parse_chat($_[0]) ] }
S 'message line numbers (body start)', '[["Ann",2],["Bob",5],["Cy",6]]', [ map { [ $_->{who}, $_->{line} ] } parse_chat("[9:02 AM] Ann\nY: a\nT: b\n[9:03 AM] Bob\nY: x T: y B: z\nCy: 5\n") ];

# ---- paste formats
S 'bracket format', '[["JC","09:02","hi\n#est A-1"],["Ann Smith","09:03",5]]', msgs("[9:02 AM] JC\nhi\n#est A-1\n[9:03 AM] Ann Smith\n5\n");
S 'name-then-time', '[["Ann Smith","09:03",5],["Bob Jones","13:10",8]]', msgs("Ann Smith 9:03 AM\n5\nBob Jones  1:10 PM\n8\n");
S 'time-then-name', '[["Ann Smith","09:03",5]]', msgs("9:03 AM Ann Smith\n5\n");
S '24h with date', '[["Ann Smith","14:03",5],["Bob","00:05","x"]]', msgs("[9/23 14:03] Ann Smith\n5\n[9/23/2026, 12:05 AM] Bob\nx\n");
S 'seconds/a.m.', '[["Ann","09:03",5]]', msgs("[9:03:17 a.m.] Ann\n5\n");
S 'colon fallback', '[["Ann",undef,5],["Bob Jones",undef,"8 pts"]]', msgs("Ann: 5\nBob Jones: 8 pts\n");
S 'fallback not for urls/notes', '[["Ann",undef,"see https://x.example/a\nnote: later"]]', msgs("Ann: see https://x.example/a\nnote: later\n");
S 'multiline message', '[["Ann","09:03","first\nsecond line"]]', msgs("[9:03 AM] Ann\nfirst\nsecond line\n");
S 'system lines dropped', '[["Ann","09:03",5]]', msgs("Meeting started\nBob Jones joined the meeting.\n[9:03 AM] Ann\n5\n\x{1F44D} 2\nRecording has started.\nMeeting ended\n");
S 'blank inside message kept out', '[["Ann","09:03",5]]', msgs("\n\n[9:03 AM] Ann\n5\n\n");
S 'guest suffix', '[["Ann Smith","09:03",5]]', msgs("[9:03 AM] Ann Smith (Guest)\n5\n");
S 'empty', '[]', msgs("");

# ---- normalisation
S 'norm_est', '[5,8,3,13,2.5,"?","?",undef,8,8,undef]', [ map { norm_est($_) } '5', '8 pts', '3sp', '13 points', '2.5', '?', 'idk', 'no idea', 'actually 8', "I'd say 8, maybe", '5 or 8' ];
S 'norm_vote yes/no', '["yes","yes","no","no","yes","no","abstain",undef]', [ map { norm_vote($_) } 'y', '+1', 'n', 'nope', 'Yes!', 'no, cert', 'pass', 'maybe' ];
S 'norm_vote options', '["y","n","hawk","kestrel","hawk",undef,"b"]', [ norm_vote('yes', [ 'y', 'n' ]), norm_vote('-1', [ 'y', 'n' ]), norm_vote('hawk', [ 'falcon', 'hawk' ]), norm_vote('Kestrel!', [ 'hawk', 'kestrel' ]), norm_vote('the hawk one', [ 'falcon', 'hawk' ]), norm_vote('a', [ 'falcon', 'hawk' ]), norm_vote('b', [ 'a', 'b', 'c' ]) ];
S 'no single-letter substring', 'undef', norm_vote('nothing here', [ 'a', 'b' ]);

# ---- rounds & tallies on the example
my $chat = do { open my $f, '<', "$FindBin::Bin/../examples/chat-2026-09-23.txt" or die $!; local $/; <$f> };
my @r = rounds(parse_chat($chat));
S 'rounds', '[["est","AUTH-104",[]],["est","RPT-203 export perf",[]],["vote","Ship Friday?",["y","n"]],["vote","Sprint name",["falcon","hawk","kestrel"]]]', [ map { [ @{$_}{qw(kind subject)}, $_->{options} ] } @r ];
S 'marker inside message', '"JC"', $r[0]{by};
S 'last answer wins', '"actually 8"', $r[0]{answers}{'Ann Smith'};
my @t = map { tally($_) } @r;
S 'est tally', '{"answers":{"Ann Smith":8,"Bob Jones":8,"Cy Park":5,"Dee Lee":"?"},"consensus":0,"max":8,"median":8,"min":5,"mode":8,"n":4,"outliers":[],"result":8,"spread":3,"unknown":["Dee Lee"]}',
  { map { $_ => $t[0]{$_} } qw(answers consensus max median min mode n outliers result spread unknown) };
S 'est consensus', '[1,3,0]', [ @{ $t[1] }{qw(consensus result spread)} ];
S 'vote tie', '[{"n":2,"y":2},1,0,undef]', [ $t[2]{counts}, $t[2]{tie}, $t[2]{majority}, $t[2]{unanimous} ? 1 : undef ];
S 'vote plurality', '["hawk",{"falcon":1,"hawk":2,"kestrel":1},0,0,["Ann Smith","Eve Wu"]]', [ $t[3]{result}, $t[3]{counts}, $t[3]{majority}, $t[3]{tie}, $t[3]{voters}{hawk} ];
S 'unparsed empty', '[]', $t[3]{unparsed};

# ---- edge tallies
my $one = tally({ kind => 'est', subject => 'X', answers => { A => '5' }, options => [] });
S 'single estimate', '[5,0]', [ $one->{result}, $one->{consensus} ];
my $none = tally({ kind => 'vote', subject => 'X', answers => {}, options => [] });
S 'no votes', '[0,undef]', [ $none->{n}, $none->{result} ];
my $out = tally({ kind => 'est', subject => 'X', answers => { A => '3', B => '3', C => '13', D => '?' }, options => [] });
S 'outlier flagged', '[["C"],3,0]', [ $out->{outliers}, $out->{result}, $out->{consensus} ];
my $maj = tally({ kind => 'vote', subject => 'X', answers => { A => 'y', B => 'yes', C => 'n', D => 'pass' }, options => [ 'y', 'n' ] });
S 'majority ignores abstain', '["y",1,0,{"abstain":1,"n":1,"y":2}]', [ @{$maj}{qw(result majority unanimous counts)} ];
my $unp = tally({ kind => 'est', subject => 'X', answers => { A => 'dunno really', B => '5' }, options => [] });
S 'unparsed kept', '[["A","dunno really"]]', $unp->{unparsed};

# ---- text & lines
check 'tally_text est', tally_text($t[0]), <<'EOF';
ESTIMATE AUTH-104  (4 answers at 09:02)
  Ann Smith      8
  Bob Jones      8
  Cy Park        5
  Dee Lee        ?
  no consensus: median 8, mode 8, range 5-8
  unknown: Dee Lee
EOF
check 'tally_text vote', tally_text($t[3]), <<'EOF';
VOTE Sprint name  (4 votes at 09:07)
  hawk        2  Ann Smith, Eve Wu
  falcon      1  Cy Park
  kestrel     1  Bob Jones
  result: hawk (plurality)
EOF
has 'tally_text outliers', tally_text($out), qr/re-discuss with C/;
check 'standup_lines', standup_lines(@t), <<'EOF';
; est AUTH-104 8   ; median, no consensus: Ann Smith 8, Bob Jones 8, Cy Park 5, Dee Lee ?
est RPT-203 3   ; consensus: Ann Smith 3, Bob Jones 3, Cy Park 3
note vote Ship Friday? -> tie (n 2, y 2)
note vote Sprint name -> hawk (hawk 2, falcon 1, kestrel 1)
EOF
my ($rep, $lines, $cnt) = report($chat);
S 'report', '[4,4]', [ $cnt, scalar(() = $rep =~ /^(?:ESTIMATE|VOTE) /mg) ];
S 'report none', '[0,"",""]', [ (report("Ann: 5\n"))[2], (report("Ann: 5\n"))[1], (report("Ann: 5\n"))[0] ];

# ---- quick (markerless)
my @m = parse_chat("[9:00 AM] JC\nwhat about RPT-9?\n[9:01 AM] Ann\n5\n[9:01 AM] Bob\n8\n[9:07 AM] Cy\n8\n");
S 'quick_est', '[3,8]', [ quick_est(\@m, undef, 'RPT-9')->{n}, quick_est(\@m, undef, 'RPT-9')->{result} ];
S 'quick_est since', '[1,8]', [ quick_est(\@m, '09:05')->{n}, quick_est(\@m, '09:05')->{result} ];
S 'quick_vote', '{"n":1,"y":2}', quick_vote([ parse_chat("Ann: y\nBob: +1\nCy: nope\n") ], undef, [ 'y', 'n' ])->{counts};

# ---- chat.pl
my $bin = "$FindBin::Bin/../bin/chat.pl";
sub cli { my $out = qx("$^X" "$bin" @_ 2>&1); ($? >> 8, $out) }
my ($rc, $o);
($rc, $o) = cli("$FindBin::Bin/../examples/chat-2026-09-23.txt");
has 'cli report', $o, qr/^ESTIMATE AUTH-104/m, qr/result: hawk \(plurality\)/;
($rc, $o) = cli('--lines', "$FindBin::Bin/../examples/chat-2026-09-23.txt");
has 'cli lines', $o, qr/^est RPT-203 3/m;
($rc, $o) = cli('--messages', "$FindBin::Bin/../examples/chat-2026-09-23.txt");
has 'cli messages', $o, qr/^09:03 Bob Jones            8 pts$/m;
my $dir = tempdir(CLEANUP => 1);
open my $fh, '>', "$dir/plain.txt" or die; print $fh "Ann: 5\nBob: 8\nCy: 8\n"; close $fh;
($rc, $o) = cli('--est', 'Z-1', "$dir/plain.txt");
has 'cli quick est', $o, qr/^ESTIMATE Z-1  \(3 answers\)/, qr/median 8, mode 8, range 5-8/;
($rc, $o) = cli("$dir/plain.txt");
has 'cli no markers', $o, qr/no #est \/ #vote markers found/;
($rc, $o) = cli('--vote', 'Ship?', '--options', 'y/n', '--lines', "$dir/plain.txt");
has 'cli quick vote lines', $o, qr/^note vote Ship\? -> no votes/;

# ---- daily.pl chat
my $root = "$FindBin::Bin/..";
my $proj = tempdir(CLEANUP => 1);
{
    my $cwd = getcwd;
    chdir $proj or die;
    qx("$^X" "$root/bin/daily.pl" init .);
    copy("$root/examples/scrum.txt", 'scrum.txt') or die $!;
    sub dcli { my $out = qx("$^X" "$root/bin/daily.pl" @_ 2>&1); ($? >> 8, $out) }
    ($rc, $o) = dcli('--today', '2026-09-23', 'chat');
    S 'daily chat missing', '[1,1]', [ $rc, ($o =~ /no chat file: standups\/2026-09-23-chat\.txt/ ? 1 : 0) ];
    copy("$root/examples/chat-2026-09-23.txt", 'standups/2026-09-23-chat.txt') or die $!;
    ($rc, $o) = dcli('--today', '2026-09-23', 'chat');
    has 'daily chat', $o, qr/^ESTIMATE AUTH-104/m, qr/appended to standups\/2026-09-23\.txt/;
    my $su = do { open my $r, '<', 'standups/2026-09-23.txt'; local $/; <$r> };
    has 'daily chat file', $su, qr/\n; ---- chat 2026-09-23\n==\n; est AUTH-104 8   ; median/, qr/^; est RPT-203 3   ; consensus: .*   ; task not in journal yet$/m, qr/^note vote Sprint name -> hawk/m;
    ($rc, $o) = dcli('--today', '2026-09-23', 'chat');
    S 'daily chat idempotent', 1, scalar(() = do { open my $r, '<', 'standups/2026-09-23.txt'; local $/; <$r> } =~ /---- chat/g);
    require Standup;
    my $parsed = Standup::read_standup('standups/2026-09-23.txt');
    S 'daily chat parses clean', '[[],2]', [ $parsed->{errors}, scalar @{ $parsed->{notes} } ];
    ($rc, $o) = dcli('--today', '2026-09-23', 'compile');
    S 'daily chat compiles', 0, $rc;
    chdir $cwd;
}

print "1..$n\n";
print $bad ? "# $bad of $n FAILED\n" : "# all $n passed\n";
exit($bad ? 1 : 0);
