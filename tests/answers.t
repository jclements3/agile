#!/usr/bin/perl
# perl t/answers.t
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use File::Temp qw(tempdir);
use File::Copy qw(copy);
use Cwd qw(getcwd);
use Prelude qw(show fmap sorted);
use Scrum;
use Answers;
use Ai;

my ($n, $bad) = (0, 0);
sub check { my ($name, $got, $want) = @_; $n++;
    if ($got eq $want) { print "ok $n - $name\n" }
    else { $bad++; print "not ok $n - $name\n#   got:  $got\n#   want: $want\n" } }
sub S { my ($name, $want, $got) = @_; check($name, show($got), $want) }
sub has { my ($name, $text, @res) = @_; for my $re (@res) { check("$name: $re", ($text =~ $re ? 1 : 0), 1) } }
sub ytb { [ map { [ $_->{who}, $_->{y}, $_->{t}, $_->{b}, $_->{blocked}, $_->{complete} ] } parse_answers($_[0]) ] }

my $root = "$FindBin::Bin/..";
my $s = load("$root/examples/scrum.txt", today => '2026-09-23');

# ---- parsing the conventions
S 'Y/T/B labels', '[["Ann","did AUTH-103","AUTH-104","none",0,1]]', ytb("[9:02 AM] Ann\nY: did AUTH-103\nT: AUTH-104\nB: none\n");
S 'word labels', '[["Bob","x","y","waiting on cert",1,1]]', ytb("[9:02 AM] Bob\nyesterday: x\nToday - y\nBlockers: waiting on cert\n");
S 'numbered', '[["Eve","docs","docs","-",0,1]]', ytb("[9:03 AM] Eve\n1: docs\n2: docs\n3: -\n");
S 'one-liner', '[["Cy","a","b","none",0,1]]', ytb("[9:03 AM] Cy\nY: a T: b B: none\n");
S 'bare Y T B delimiters', '[["Sam Archer","finished B-11 and B-121","start B-1221","none",0,1]]', ytb("[8:31 AM] Sam Archer\nSam Archer Y finished B-11 and B-121 T start B-1221 B none\n");
S 'bare form, no name, blocked', '[["Ann BMC2","B-13 merged","B-14","waiting on SEI ICD",1,1]]', ytb("[8:32 AM] Ann BMC2\nY B-13 merged T B-14 B waiting on SEI ICD\n");
S 'bare form across lines', '[["Cy","a b","c","none",0,1]]', ytb("[8:33 AM] Cy\nY a\nb T c B none\n");
S 'bare form, lowercase accepted when unambiguous', '[["Dee","did a","will","none",0,1]]', ytb("[8:34 AM] Dee\ny did a t will b none\n");
S 'bare form, ambiguous lowercase refused', '[]', ytb("[8:34 AM] Dee\ny did a t will b in the lab b none\n");
S 'uppercase delimiters win over a lowercase b in the text', '[["Fay","merged","will b in the lab","none",0,1]]', ytb("[8:36 AM] Fay\nY merged T will b in the lab B none\n");
S 'bare form out of order refused', '[]', ytb("[8:37 AM] Gus\nT a B none Y b\n");

# ---- lint: what the person gets told during the meeting
use Answers qw(lint_chat lint_message lint_text);
binmode STDOUT, ":utf8";
sub L { [ map { [ $_->{who}, $_->{line}, $_->{ok}, join('; ', @{ $_->{errors} }), join('; ', @{ $_->{warnings} }) ] } lint_chat($_[0], known => { 'B-11' => 1, 'B-12' => 1 }) ] }
S 'single-letter prefix ids are ids (B-11, IF-1)', '[["B-11"],["IF-1","AUTH-103"]]', [ map { $_ } @{ (parse_answers("[8:31 AM] Ann\nY: B-11 done\nT: IF-1 then AUTH-103\nB: none\n"))[0]{ids} }{qw(y t)} ];
S 'lint ok', '[["Ann",2,1,"",""]]', L("[8:31 AM] Ann\nY finished B-11 T start B-12 B none\n");
S 'lint ambiguous b', q{[["Bob",2,0,"'B' appears 2 times: capitalize the one that is the delimiter",""]]}, L("[8:31 AM] Bob\ny did B-11 t will b in the lab b none\n");
S 'lint missing T', '[["Cy",2,0,"no T found",""]]', L("[8:31 AM] Cy\nY did B-11 B none\n");
S 'lint nothing at all', '[["Dee",2,0,"no Y/T/B found",""]]', L("[8:31 AM] Dee\nhello everyone\n");
S 'lint empty B', q{[["Eve",2,0,"B is empty (write 'none')",""]]}, L("[8:31 AM] Eve\nY: B-11\nT: B-12\nB:\n");
S 'lint no id + unknown id are warnings', '[["Fay",2,1,"","no task id in Y (e.g. B-11); B-99 is not in the journal"]]', L("[8:31 AM] Fay\nY tidied the lab T B-99 B none\n");
S 'lint out of order', '[["Gus",2,0,"out of order: expected Y ... T ... B ...",""]]', L("[8:31 AM] Gus\nT a B none Y b\n");
S 'lint last message per person wins, line of the last', '[["Ann",4,1,"",""]]', L("[8:31 AM] Ann\nhello\n[8:32 AM] Ann\nY B-11 T B-12 B none\n");
S 'lint: chatter after a good status does not undo it', '[["Ann",2,1,"",""]]', L("[8:31 AM] Ann\nY B-11 T B-12 B none\n[8:40 AM] Ann\nthanks all\n[8:41 AM] Ann\n5\n");
S 'lint: a later partial message is an update, judged merged (like parse_answers)', '[["Ann",4,1,"",""]]', L("[8:31 AM] Ann\nY B-11 T B-12 B none\n[8:40 AM] Ann\nB: cert arrived, unblocked\n");
S 'lint: a later attempt that fails outright is the error', q{[["Ann",4,0,"'B' appears 2 times: capitalize the one that is the delimiter",""]]}, L("[8:31 AM] Ann\nY B-11 T B-12 B none\n[8:40 AM] Ann\ny B-11 t will b in the lab b none\n");
S 'lint: merged record still missing a field is an error', q{[["Ann",2,0,"B is empty (write 'none')",""]]}, L("[8:31 AM] Ann\nY: B-11\nT: B-12\n");
S 'lint: only chatter is still an error', '[["Ann",4,0,"no Y/T/B found",""]]', L("[8:31 AM] Ann\nhello\n[8:32 AM] Ann\nthanks\n");
S 'lint skips #est rounds', '[["Ann",2,1,"",""]]', L("[8:31 AM] Ann\nY B-11 T B-12 B none\n[8:32 AM] JC\n#est B-12\n");
my @lr = lint_chat("[8:31 AM] Bob\ny did B-11 t will b in the lab b none\n[8:32 AM] Fay\nY tidied T B-99 B none\n[8:33 AM] Ann\nY B-11 T B-12 B none\n", known => { 'B-11' => 1, 'B-12' => 1 }, example => 'B-11', example2 => 'B-12');
S 'lint replies: did-you-mean with thumbs-up, got-it with coaching, nothing when clean', q{["Hey Bob! Did you mean: Y did B-11 / T will b in the lab / B none ?  } . "\x{1F44D}" . q{ if yes, or repost as: Y did B-11 T doing B-12 B none","Hey Fay! Got it. Add the task id next time so it counts (e.g. Y did B-11 T doing B-12 B none). B-99 isn't in the backlog -- typo?",""]}, [ map { $_->{reply} } @lr ];
S 'lint reply when nothing can be guessed', q{["Hey Cy! I couldn't read your status (no T found). Repost as: Y did B-11 T doing B-12 B none"]}, [ map { $_->{reply} } lint_chat("[8:31 AM] Cy Jones\nY did B-11 B none\n", known => {}, example => 'B-11', example2 => 'B-12') ];
S 'guess fields on the record', '{"b":"none","t":"will b in the lab","y":"did B-11"}', $lr[0]{guess};
S 'confirm read-back for every parsed status (the table entry, for a thumbs-up); none for an ERROR', '["","Hey Fay! I read your status as: Y tidied / T B-99 / B none  ' . "\x{1F44D}" . ' if right, or repost.","Hey Ann! I read your status as: Y B-11 / T B-12 / B none  ' . "\x{1F44D}" . ' if right, or repost."]', [ map { $_->{confirm} } @lr ];
S 'parse_answers refuses the ambiguous line', '[]', ytb("[8:31 AM] Bob\ny did B-11 t will b in the lab b none\n");
S 'parse_answers with guess => 1 accepts it (the thumbs-up)', '[["Bob","did B-11","will b in the lab","none",0,1]]', [ map { [ $_->{who}, $_->{y}, $_->{t}, $_->{b}, $_->{blocked}, $_->{complete} ] } parse_answers("[8:31 AM] Bob\ny did B-11 t will b in the lab b none\n", guess => 1) ];
S 'lint_text', "\"chat:2: ERROR Bob: 'B' appears 2 times: capitalize the one that is the delimiter\\nchat:4: warn  Fay: no task id in Y (e.g. B-11); B-99 is not in the journal\\nchat:6: ok    Ann: Y/T/B parsed\\n# 3 answered, 1 error, 1 warning\\n\"", lint_text('chat', @lr);
S 'lowercase b inside text is not a delimiter', '[["Eve","fixed the b tree","docs","none",0,1]]', ytb("[8:35 AM] Eve\nY fixed the b tree T docs B none\n");
S 'continuation lines', '[["Ann","first and more","t","-",0,1]]', ytb("[9:02 AM] Ann\nY: first\nand more\nT: t\nB: -\n");
S 'later message overrides', '[["Bob","x","y","cert arrived, unblocked",0,1]]', ytb("[9:02 AM] Bob\nY: x\nT: y\nB: waiting\n[9:04 AM] Bob\nB: cert arrived, unblocked\n");
S 'incomplete', '[["Ann","x",undef,undef,0,0]]', ytb("[9:02 AM] Ann\nY: x\n");
S 'non-answer messages ignored', '[["Ann","x","y","-",0,1]]', ytb("[9:01 AM] JC\nMorning all\n#est A-1\n[9:02 AM] Ann\nY: x\nT: y\nB: -\n[9:05 AM] Bob\n5\n");
S 'blocked variants', '[0,0,0,0,1,1,0,0]', [ map { (parse_answers("Ann: x\nY: x\nT: y\nB: $_\n"))[0]{blocked} } 'none', 'no blockers', 'n/a', 'clear', 'waiting on ISSM', 'need access to lab', 'resolved yesterday', 'no longer blocked' ];
my ($r) = parse_answers("[9:02 AM] Bob\nY: AUTH-103 merged, RPT-202 review\nT: OPS-302 and AUTH-103\nB: cert for AUTH-104\n");
S 'ids per question', '{"b":["AUTH-104"],"t":["OPS-302","AUTH-103"],"y":["AUTH-103","RPT-202"]}', $r->{ids};
S 'empty', '[]', ytb("Meeting started\n");

# ---- answers file round trip and history
my $dir = tempdir(CLEANUP => 1);
my @ans = parse_answers("[9:02 AM] Ann\nY: a\nT: b\nB: none\n[9:03 AM] Bob\nY: AUTH-103\nT: AUTH-104\nB: cert\n");
my $txt = answers_text('2026-09-23', 'Alpha', @ans);
check 'answers_text', $txt, "2026-09-23 Alpha\nAnn (09:02)\n  Y: a\n  T: b\n  B: none\nBob (09:03)\n  Y: AUTH-103\n  T: AUTH-104\n  B: cert\n";
my $af = answers_path($dir, '2026-09-23', 'Alpha');
S 'answers_path', '"DIR/2026-09-23-Alpha-answers.txt"', $af =~ s/\Q$dir\E/DIR/r;
open my $fh, '>', $af or die; print $fh $txt; close $fh;
my $rec = read_answers($af);
S 'read_answers', '["2026-09-23","Alpha",[["Ann","09:02","a","b","none",0],["Bob","09:03","AUTH-103","AUTH-104","cert",1]]]', [ $rec->{date}, $rec->{team}, [ map { [ @{$_}{qw(who time y t b blocked)} ] } @{ $rec->{answers} } ] ];
S 'read ids', '["AUTH-104"]', $rec->{answers}[1]{ids}{t};
for my $d ('2026-09-18', '2026-09-19', '2026-09-22') { open my $f, '>', answers_path($dir, $d, 'Alpha') or die; print $f answers_text($d, 'Alpha', @ans); close $f }
open $fh, '>', answers_path($dir, '2026-09-22', 'Bravo') or die; print $fh answers_text('2026-09-22', 'Bravo', $ans[0]); close $fh;
S 'history newest first', '["2026-09-22","2026-09-19","2026-09-18"]', [ map { $_->{date} } history($dir, 'Alpha', '2026-09-23') ];
S 'history limited', '["2026-09-22"]', [ map { $_->{date} } history($dir, 'Alpha', '2026-09-23', 1) ];
S 'history other team', '["2026-09-22"]', [ map { $_->{date} } history($dir, 'Bravo', '2026-09-23') ];
S 'history none', '[]', [ history("$dir/nope", 'Alpha', '2026-09-23') ];

# ---- flags
my @hist = history($dir, 'Alpha', '2026-09-23');   # Bob blocked "cert" on 3 previous days, Ann's plan "b" repeated
my @today = parse_answers("[9:02 AM] Ann\nY: a\nT: b\nB: none\n[9:03 AM] Bob\nY: AUTH-103 merged and done\nT: AUTH-104 with Ann, then OPS-302\nB: cert\n[9:04 AM] Eve\nY: docs\nT: docs\nB: -\n");
my @f = flags($s, 'Alpha', \@today, \@hist, roster => [ 'Ann', 'Bob', 'Cy' ]);
S 'flags', '[["red","Ann","same plan 4 days running: b"],["red","Bob","blocked for 4 days: cert"],["amber","Bob","mentions AUTH-104 which is not in the journal"],["amber","Cy","no answers in chat"],["info","Ann","no task ids in yesterday/today (untracked work?)"],["info","Bob","mentions OPS-302 which is master (Master), not in Alpha\'s sprint"],["info","Bob","says AUTH-103 is done; confirm and mark"],["info","Eve","no task ids in yesterday/today (untracked work?)"]]',
  [ map { [ @{$_}{qw(level who text)} ] } @f ];
S 'done flag carries id', '["AUTH-103",1]', [ map { ($_->{id}, $_->{done}) } grep { $_->{done} } @f ];
S 'no history no repeat flag', 0, scalar grep { $_->{text} =~ /same plan/ } flags($s, 'Alpha', \@today, [], roster => []);
my @own = flags($s, 'Bravo', [ parse_answers("Dee: x\nY: x\nT: RPT-202\nB: -\n") ], [], roster => []);
S 'owner mismatch', '["Dee","working RPT-202 which is owned by Cy"]', [ @{ $own[0] }{qw(who text)} ];
S 'incomplete flag', 1, scalar grep { $_->{text} =~ /incomplete answers \(missing t\/b\)/ } flags($s, 'Alpha', [ parse_answers("Ann: x\nY: x\n") ], [], roster => []);

# ---- suggested lines
check 'suggest_lines', suggest_lines($s, 'Alpha', \@today, \@f), <<'EOF';
; done AUTH-103   ; Bob say done
risk Bob: cert
; absent Cy   ; no answers in chat (confirm)
EOF
my @lift = parse_answers("Cy: x\nY: RPT-202 review\nT: RPT-202\nB: cert arrived, unblocked\n");
$s->{items}{'RPT-202'}{blocked} = 'cert';
check 'suggest unblock', suggest_lines($s, 'Bravo', \@lift, [ flags($s, 'Bravo', \@lift, [], roster => []) ]), "; unblock RPT-202   ; Cy no longer reports a blocker\n; note Cy: cert arrived, unblocked\n";
check 'suggest risk without id', suggest_lines($s, 'Alpha', [ parse_answers("Ann: x\nY: x\nT: y\nB: lab access, still waiting\n") ], []), "risk Ann: lab access; still waiting\n";
# the four-letter words said in a status -> commented verbs for the architect to confirm
check 'suggest punt', suggest_lines($s, 'Alpha', [ parse_answers("Bob: x\nY: x\nT: punting AUTH-103, too hard as written\nB: none\n") ], []), "; punt AUTH-103 punting AUTH-103; too hard as written   ; Bob: too hard as written -- back to TODO (confirm)\n";
check 'suggest hold', suggest_lines($s, 'Alpha', [ parse_answers("Bob: x\nY: x\nT: AUTH-103 on hold, pulled onto the outage\nB: none\n") ], []), "; hold AUTH-103 AUTH-103 on hold; pulled onto the outage   ; Bob: interrupted (confirm)\n";
check 'suggest redo', suggest_lines($s, 'Alpha', [ parse_answers("Ann: x\nY: x\nT: redo AUTH-101, demo found the reset mail unsent\nB: none\n") ], []), "; redo AUTH-101 redo AUTH-101; demo found the reset mail unsent   ; Ann: found wrong after the demo (confirm)\n";
check 'suggest pass to a known team', suggest_lines($s, 'Alpha', [ parse_answers("Bob: x\nY: x\nT: passing AUTH-103 to Bravo, it is their service\nB: none\n") ], []), "; pass AUTH-103 Bravo   ; Bob: another team should do it (confirm)\n";
check 'suggest pass without a team', suggest_lines($s, 'Alpha', [ parse_answers("Bob: x\nY: x\nT: handing off AUTH-103\nB: none\n") ], []), "; note Bob: handing off AUTH-103   ; pass to which team?\n";
check 'suggest sync', suggest_lines($s, 'Alpha', [ parse_answers("Bob: x\nY: x\nT: sync AUTH-103 with AUTH-101 this sprint\nB: none\n") ], []), "; sync AUTH-103 AUTH-101   ; Bob: coordinated across teams, shared DONE (confirm)\n";
check 'no suggestion without a known id', suggest_lines($s, 'Alpha', [ parse_answers("Bob: x\nY: x\nT: punting the spike, too hard\nB: none\n") ], []), "";
has 'answers_report', answers_report('Alpha', \@today, \@f), qr/^Alpha stand-up answers: 3 people, 1 blocked$/m, qr/^  Bob            Y: AUTH-103 merged and done$/m, qr/^  RED   Bob            blocked for 4 days: cert$/m;

# ---- Ai
my $prompt = prompt_pack(date => '2026-09-23', sprint_text => "Sprint 42\nTeam ...", answers => { Alpha => "Alpha answers" }, flags => { Alpha => [ $f[1] ] }, history => { Alpha => "2026-09-22 Alpha\n..." }, notes => 'n1', marking => { banner => 'INTERNAL' });
has 'prompt_pack', $prompt, qr/^INTERNAL\n/, qr/INTERNAL\n$/, qr/EXACTLY these section headings/, qr/=== SPRINT METRICS ===\nSprint 42/, qr/=== Alpha TODAY ===\nAlpha answers/, qr/flags \(computed\):\n  red: Bob: blocked for 4 days: cert/, qr/=== Alpha PREVIOUS DAYS ===\n2026-09-22 Alpha/, qr/=== NOTES ===\nn1/;
S 'prompt no banner', 0, (prompt_pack(date => 'd', answers => {}) =~ /^INTERNAL/ ? 1 : 0);
my $resp = Ai::parse_response("Sure! Here is the assessment.\n\n## Highlights\n- AUTH-103 done (Ann, Bob)\n* Bravo unblocked\n\n**RISKS**\n1. cert for AUTH-104\n\nSTUCK:\n- none\n\nQuestions for leads\n- Ask Cy about RPT-202?\n\nPROGRESS\nAlpha on track, 13/18.\n");
S 'parse_response', '{"HIGHLIGHTS":["AUTH-103 done (Ann, Bob)","Bravo unblocked"],"PROGRESS":["Alpha on track, 13/18."],"QUESTIONS FOR LEADS":["Ask Cy about RPT-202?"],"RISKS":["cert for AUTH-104"],"STUCK":[]}', $resp;
S 'response_ok', '[1,0]', [ response_ok($resp), response_ok(Ai::parse_response("thanks")) ];
check 'response_text', response_text($resp), "AI assessment:\n  HIGHLIGHTS\n    - AUTH-103 done (Ann, Bob)\n    - Bravo unblocked\n  RISKS\n    - cert for AUTH-104\n  QUESTIONS FOR LEADS\n    - Ask Cy about RPT-202?\n  PROGRESS\n    - Alpha on track, 13/18.\n";
my $out = tempdir(CLEANUP => 1);
my $a = ask(conf => { ai_backend => 'paste' }, prompt => 'P', out_dir => $out, date => '2026-09-23');
S 'ask paste pending', '["pending",1,0]', [ $a->{status}, (-f "$out/2026-09-23-ai-prompt.txt" ? 1 : 0), (-e "$out/2026-09-23-ai-response.txt" ? 1 : 0) ];
open $fh, '>', "$out/2026-09-23-ai-response.txt" or die; print $fh "HIGHLIGHTS\n- pasted\n"; close $fh;
$a = ask(conf => { ai_backend => 'paste' }, prompt => 'P', out_dir => $out, date => '2026-09-23');
S 'ask paste ok', '["ok","HIGHLIGHTS\n- pasted\n"]', [ @{$a}{qw(status text)} ];
$a = ask(conf => { ai_backend => 'mock' }, prompt => 'P', out_dir => $out, date => '2026-09-24');
S 'ask mock', '["ok",1]', [ $a->{status}, response_ok(Ai::parse_response($a->{text})) ];
$a = ask(conf => { ai_backend => 'curl' }, prompt => 'P', out_dir => $out, date => '2026-09-25');
S 'ask curl no url', '["error",1]', [ $a->{status}, ($a->{error} =~ /ai_url not set/ ? 1 : 0) ];
# curl backend through a fake curl that echoes the request body back inside a chat-completions envelope
my $fake = "$out/fakecurl.pl";
open $fh, '>', $fake or die; print $fh q{use strict; use JSON::PP; my ($f) = grep { s/^\@// } @ARGV; open my $r, '<', $f or die; my $req = JSON::PP->new->utf8->decode(do { local $/; <$r> }); print JSON::PP->new->utf8->encode({ choices => [ { message => { content => "HIGHLIGHTS\n- model=$req->{model} user=" . substr($req->{messages}[1]{content}, 0, 5) . "\n" } } ] });}; close $fh;
$ENV{FAKE_KEY} = 'k';
$a = ask(conf => { ai_backend => 'curl', ai_url => 'https://x/v1', ai_model => 'm1', ai_key_env => 'FAKE_KEY', ai_curl => [ $^X, $fake ] }, prompt => 'Hello world', out_dir => $out, date => '2026-09-26');
S 'ask curl fake', '["ok","HIGHLIGHTS\n- model=m1 user=Hello\n"]', [ @{$a}{qw(status text)} ]; print "#   error: $a->{error}\n" if $a->{status} ne 'ok';
eval { ask(conf => { ai_backend => 'bogus' }, prompt => 'P', out_dir => $out, date => 'x') };
has 'ask bad backend', $@, qr/unknown ai_backend 'bogus'/;

# ---- daily.pl answers / ai / report
my $proj = tempdir(CLEANUP => 1);
{
    my $cwd = getcwd;
    chdir $proj or die;
    qx("$^X" "$root/bin/daily.pl" init .);
    copy("$root/examples/scrum.txt", 'scrum.txt') or die $!;
    open my $cf, '>>', 'scrum.conf' or die; print $cf "ai_backend = mock\nbanner = INTERNAL\nmarking_poc = JC\n"; close $cf;
    sub dcli { my $o = qx("$^X" "$root/bin/daily.pl" @_ 2>&1); ($? >> 8, $o) }
    my ($rc, $o);
    ($rc, $o) = dcli('--today', '2026-09-23', 'answers');
    S 'answers none', '[1,1]', [ $rc, ($o =~ /no chat files for 2026-09-23/ ? 1 : 0) ];
    open $fh, '>', 'standups/2026-09-22-Alpha-answers.txt' or die; print $fh "2026-09-22 Alpha\nEve (09:03)\n  Y: docs\n  T: docs\n  B: -\nBob (09:02)\n  Y: x\n  T: y\n  B: waiting on cert\n"; close $fh;
    copy("$root/examples/answers-2026-09-23-Alpha-chat.txt", 'standups/2026-09-23-Alpha-chat.txt') or die $!;
    ($rc, $o) = dcli('--today', '2026-09-23', 'answers');
    has 'answers', $o, qr/^Alpha stand-up answers: 3 people, 0 blocked$/m, qr/INFO  1x same plan 2 days running: docs: Eve/, qr/INFO  2x says ID is done; confirm and mark: Ann \(AUTH-103\), Bob \(AUTH-103\)/, qr/wrote standups\/2026-09-23-Alpha-answers\.txt/, qr/attendance: 3 rows \(answered\)/, qr/appended suggested lines/;
    S 'answers rc', 0, $rc;
    my $su = do { open my $r, '<', 'standups/2026-09-23.txt'; local $/; <$r> };
    has 'answers in standup file', $su, qr/; ---- answers 2026-09-23 Alpha\n== Alpha\n; done AUTH-103   ; Ann, Bob say done\n; note Bob: cert arrived, unblocked/;
    S 'attendance answered', 3, scalar(() = do { open my $r, '<', 'attendance.csv'; local $/; <$r> } =~ /,answered$/mg);
    ($rc, $o) = dcli('--today', '2026-09-23', 'answers');
    S 'answers idempotent', 1, scalar(() = do { open my $r, '<', 'standups/2026-09-23.txt'; local $/; <$r> } =~ /---- answers/g);
    ($rc, $o) = dcli('--today', '2026-09-23', 'compile');
    S 'compiles after answers', 0, $rc;
    ($rc, $o) = dcli('--today', '2026-09-23', 'ai');
    has 'ai mock', $o, qr/^AI assessment:\n  HIGHLIGHTS\n    - mock highlight/;
    S 'ai files', '[1,1]', [ (-f 'reports/2026-09-23-ai-prompt.txt' ? 1 : 0), (-f 'reports/2026-09-23-ai-response.txt' ? 1 : 0) ];
    has 'ai prompt content', do { open my $r, '<', 'reports/2026-09-23-ai-prompt.txt'; local $/; <$r> }, qr/^INTERNAL\n/, qr/=== Alpha TODAY ===/, qr/=== Alpha PREVIOUS DAYS ===\n2026-09-22 Alpha/, qr/red|amber|info/;
    ($rc, $o) = dcli('--today', '2026-09-23', 'report');
    my $st = do { open my $r, '<', 'reports/2026-09-23-status.txt'; local $/; <$r> };
    has 'report has flags and AI', $st, qr/^Alpha flags:\n  AMBER Ann/m, qr/^AI assessment:\n  HIGHLIGHTS\n    - mock highlight/m, qr/POC: JC\n\nINTERNAL\n$/;
    open $cf, '>>', 'scrum.conf' or die; print $cf "ai_backend = paste\n"; close $cf;
    unlink 'reports/2026-09-23-ai-response.txt';
    ($rc, $o) = dcli('--today', '2026-09-23', 'ai');
    has 'ai paste pending', $o, qr/prompt written: reports\/2026-09-23-ai-prompt\.txt\npaste it into your AI service/;
    ($rc, $o) = dcli('--today', '2026-09-24', 'ai');
    S 'ai no answers', '[1,1]', [ $rc, ($o =~ /no answers files for 2026-09-24/ ? 1 : 0) ];
    chdir $cwd;
}

# ---- flag semantics at scale
{
    my $s2 = load("$FindBin::Bin/../examples/scrum.txt", today => '2026-09-01');
    my @own = flags($s2, 'Bravo', [ parse_answers("[9:02 AM] Bob\nY: RPT-201\nT: OPS-302 next\nB: none\n") ], []);
    S 'mentioning your own queued task is not a flag', '[]', [ map { $_->{text} } grep { /not in/ } flags($s2, 'Alpha', [ parse_answers("[9:02 AM] Bob\nY: AUTH-103\nT: AUTH-104 next\nB: none\n") ], []) ];
    my @rep = map { +{ who => 'Bob', y => 'x', t => 'AUTH-103 sso', b => 'none', blocked => 0, complete => 1, ids => { y => [], t => ['AUTH-103'], b => [] } } } 1 .. 4;
    my $h = [ map { +{ date => "2026-08-2$_", answers => [ $rep[0] ] } } reverse 5 .. 8 ];
    my ($today) = parse_answers("[9:02 AM] Bob\nY: x\nT: AUTH-103 sso\nB: none\n");
    S 'same plan 5 days on a 13-point task is amber, not red', '["amber","same plan 5 days running: AUTH-103 sso"]', [ map { ($_->{level}, $_->{text}) } grep { $_->{text} =~ /same plan/ } flags($s2, 'Alpha', [ $today ], $h) ];
    my ($small) = parse_answers("[9:02 AM] Ann\nY: x\nT: OPS-302\nB: none\n");
    my $hs = [ map { +{ date => "2026-08-2$_", answers => [ { who => 'Ann', t => 'OPS-302', complete => 1, ids => { t => ['OPS-302'], y => [], b => [] } } ] } } reverse 6 .. 8 ];
    S 'same plan 4 days on a 3-point task is red', '["red"]', [ map { $_->{level} } grep { $_->{text} =~ /same plan/ } flags($s2, 'Bravo', [ $small ], $hs) ];
    my @fl = ( { level => 'red', who => 'Ann', text => 'blocked: cert' }, map { { level => 'info', who => "P$_", text => "mentions B-$_ which is backlog (Alpha), not in Bravo's sprint", id => "B-$_" } } 1 .. 10 );
    S 'fold_flags: serious one per line, info grouped with names', q{["RED   Ann            blocked: cert","INFO  10x mentions ID which is backlog , not in the team's sprint: P1 (B-1), P2 (B-2), P3 (B-3), P4 (B-4), P5 (B-5), P6 (B-6), P7 (B-7), P8 (B-8), ..."]}, [ Answers::fold_flags(@fl) ];
}
S '"nearly done" is not a done claim', '[]', [ grep { $_->{done} } flags(load("$FindBin::Bin/../examples/scrum.txt", today => '2026-09-01'), 'Alpha', [ parse_answers("[9:02 AM] Bob\nY: AUTH-103 nearly done\nT: AUTH-103\nB: none\n") ], []) ];
S '"done" still is', '["AUTH-103"]', [ map { $_->{id} } grep { $_->{done} } flags(load("$FindBin::Bin/../examples/scrum.txt", today => '2026-09-01'), 'Alpha', [ parse_answers("[9:02 AM] Bob\nY: AUTH-103 done\nT: AUTH-104\nB: none\n") ], []) ];

# ---- acks accept proposals (two keystrokes for the team member)
use Answers qw(is_ack read_proposals);
S 'ack tokens', '[1,1,1,1,1,1,0,0]', [ map { is_ack($_) } '+1', 'y', 'OK!', "\x{1F44D}", 'same', 'yes.', 'y B-11 t B-12 b none', 'thanks' ];
{ my $pf = "$dir/2026-09-23-proposals.txt"; open my $w, '>:encoding(UTF-8)', $pf or die; print $w "# who\tY\tT\tB\nAnn\tAUTH-103 done?\tAUTH-104\tnone\n"; close $w;
  my $pr = read_proposals($pf);
  S 'read_proposals', '{"Ann":{"b":"none","t":"AUTH-104","y":"AUTH-103 done?"}}', $pr;
  S 'a +1 accepts the proposal as the status', '[["Ann","AUTH-103 done?","AUTH-104","none",1,1]]', [ map { [ $_->{who}, $_->{y}, $_->{t}, $_->{b}, $_->{complete}, $_->{accepted} ] } parse_answers("[8:31 AM] Ann\n+1\n", proposals => $pr) ];
  S 'a +1 without a proposal is nothing', '[]', [ parse_answers("[8:31 AM] Ann\n+1\n") ];
  S 'lint sees the accepted proposal as ok', '[["Ann",2,1,"",""]]', [ map { [ $_->{who}, $_->{line}, $_->{ok}, join('; ', @{ $_->{errors} }), join('; ', @{ $_->{warnings} }) ] } lint_chat("[8:31 AM] Ann\n+1\n", proposals => $pr, known => { 'AUTH-103' => 1, 'AUTH-104' => 1 }) ];
  S 'a typed status still beats the proposal', '[["Ann","B-11","B-12","none"]]', [ map { [ $_->{who}, $_->{y}, $_->{t}, $_->{b} ] } parse_answers("[8:31 AM] Ann\n+1\n[8:35 AM] Ann\nY B-11 T B-12 B none\n", proposals => $pr) ];
}

# ---- propose: yesterday's status drafts today's; assumed records for the silent
use Answers qw(propose assumed_record);
{
    my $s = load("$FindBin::Bin/../examples/scrum.txt", today => '2026-09-01');
    my $hist = [ { date => '2026-08-31', answers => [ { who => 'Bob', y => 'x', t => 'AUTH-103 sso callback', b => 'waiting on cert', blocked => 1 } ] } ];
    my @p = propose($s, 'Alpha', $hist, roster => [ 'Bob', 'Ann' ]);
    S 'propose from yesterday T, blocker carried', q{["Bob","AUTH-103 sso callback","continue AUTH-103","waiting on cert","yesterday's T"]}, [ @{ $p[0] }{qw(who y t b basis)} ];
    S 'propose line', "\"Bob: Y AUTH-103 sso callback done? T continue AUTH-103 B waiting on cert  -- \x{1F44D} if right, or repost your own Y/T/B\"", $p[0]{line};
    S 'propose with no history and no tasks', '["Ann","nothing recorded","no committed task","none"]', [ @{ $p[1] }{qw(who y t b)} ];
    my $a = assumed_record($p[0]);
    S 'assumed record', '[1,1,1,["AUTH-103"]]', [ $a->{assumed}, $a->{complete}, $a->{blocked}, $a->{ids}{y} ];
    my $txt = answers_text('2026-09-01', 'Alpha', $a);
    S 'assumed marker in the answers file', 1, ($txt =~ /^Bob \(assumed\)$/m ? 1 : 0);
    my $f = "$dir/2026-09-01-Alpha-answers.txt"; open my $w, '>', $f or die; print $w $txt; close $w;
    my $back = read_answers($f);
    S 'assumed survives the round trip', '[["Bob",1,"AUTH-103 sso callback"]]', [ map { [ $_->{who}, $_->{assumed}, $_->{y} ] } @{ $back->{answers} } ];
    my @fl = flags($s, 'Alpha', [ $a ], [], roster => [ 'Bob' ]);
    S 'assumed flag, first day amber, not "no answers", no done suggestion', '[["amber","Bob","no answer; status ASSUMED from yesterday: Y AUTH-103 sso callback / T continue AUTH-103 / B waiting on cert -- unconfirmed",undef]]', [ map { [ $_->{level}, $_->{who}, $_->{text}, $_->{done} ] } @fl ];
    my @fl2 = flags($s, 'Alpha', [ $a ], [ $back ], roster => [ 'Bob' ]);
    S 'assumed two days running is red', '["red","2 days running"]', [ $fl2[0]{level}, ($fl2[0]{text} =~ /\((\d days running)\)/)[0] ];
    S 'suggest_lines never marks an assumed status done', 1, (suggest_lines($s, 'Alpha', [ $a ], \@fl) !~ /^\s*;?\s*done/m ? 1 : 0);
}

print "1..$n\n";
print $bad ? "# $bad of $n FAILED\n" : "# all $n passed\n";
exit($bad ? 1 : 0);
