#!/usr/bin/perl
# perl tests/drills.t -- the coding drills (drills/, lib/Drills.pm, drills/drill.pl, vim/plugin+autoload/drills.vim):
# every problem is complete and well-formed, every reference solution passes its own tests, every stub fails them
# cleanly, drill.pl works end to end in a temporary workspace, the statements are short and the kit's own, and the
# Vim trainer's comparison, fading and game behave (when a vim is on PATH).
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use File::Temp qw(tempdir);
use File::Copy qw(copy);
use Cwd qw(abs_path getcwd);
use Drills ();

my ($n, $bad) = (0, 0);
sub ok { my ($c, $name, $diag) = @_; $n++;
    if ($c) { print "ok $n - $name\n" } else { $bad++; print "not ok $n - $name\n"; print map { "#   $_\n" } split /\n/, $diag if defined $diag } }

my $ROOT = abs_path("$FindBin::Bin/..");
my $TMP = tempdir(CLEANUP => 1);
my $WS = "$TMP/ws";
sub run { my ($cwd, @cmd) = @_;                 # -> (exit status, stdout+stderr)
    my $back = getcwd(); chdir $cwd or die "cannot chdir $cwd: $!\n";
    my $out = '';
    my $pid = open(my $ph, '-|');
    die "cannot fork: $!\n" unless defined $pid;
    if (!$pid) { open STDERR, '>&', \*STDOUT; exec @cmd or exit 127 }
    { local $/; $out = <$ph> // '' } close $ph;
    my $rc = $? >> 8; chdir $back; ($rc, $out) }
sub slurp { my $f = shift; open my $fh, '<:raw', $f or return undef; local $/; my $t = <$fh>; close $fh; $t }
sub drill { run($ROOT, $^X, "$ROOT/drills/drill.pl", '--dir', $WS, @_) }

# ---------------------------------------------------------------- the problem set
my @S = Drills::sections($ROOT);
my @P = Drills::problems($ROOT);
ok(@S >= 16, 'at least 16 sections (' . scalar(@S) . ')');
ok(@P >= 150, 'at least 150 problems (' . scalar(@P) . ')');
my %id; $id{ $_->{id} }++ for @P;
my @dup = grep { $id{$_} > 1 } sort keys %id;
ok(!@dup, 'problem ids are unique', "duplicates: @dup");
ok($S[0]{name} eq 'ladder', 'the ladder is the first section (level 1)');
my @ladder = map { $_->{id} } grep { $_->{section} eq 'ladder' } @P;
my @want = qw(p00 p01 p02 p03 p10 p11 p12 p13 p20 p21 p22 p23 p24 p30 p31 p32 p33 p40 p41 p42 p43 p50 p51 p52 p53 p54 p55 p56 p57);
ok(join(' ', map { /^(p\d\d)/ ? $1 : $_ } @ladder) eq "@want", 'the ladder holds the binder\'s 29 rungs p00..p57, in order', "@ladder");
my (@incomplete, @badhead, @long, @lc, @copied);
my @LC_PHRASES = ('You may assume that each input would have exactly one solution', 'Given an array of integers nums',
    'Given a string s, find the length of the longest', 'You must write an algorithm that runs in', 'Given the head of a singly linked list',
    'Given the root of a binary tree', 'Return the answer in any order', 'An input string is valid if');
for my $p (@P) {
    my @miss = grep { !-f "$p->{path}/$_" } qw(statement.txt tests.pl solution.pl stub.pl);
    push @incomplete, "$p->{id}: @miss" if @miss;
    push @badhead, $p->{id} unless $p->{title} && $p->{origin} && $p->{pattern} && $p->{timebox} =~ /^\d+$/ && $p->{kind} =~ /^(?:function|class|stdio)$/;
    push @lc, $p->{id} unless defined $p->{leetcode} && $p->{leetcode} =~ /^(?:\d+\. \S.*|none\b.*)$/;
    my $words = () = $p->{body} =~ /\S+/g;
    push @long, "$p->{id} ($words words)" if $words > 250;
    my $st = slurp("$p->{path}/statement.txt") // '';
    for my $ph (@LC_PHRASES) { push @copied, "$p->{id}: $ph" if index(lc $st, lc $ph) >= 0 }
}
ok(!@incomplete, 'every problem has statement.txt, tests.pl, solution.pl and stub.pl', join "\n", @incomplete);
ok(!@badhead, 'every statement has Title, Origin, Pattern, Timebox and a valid Kind', "@badhead");
ok(!@lc, 'every statement has its LeetCode line (a number and title as a pointer, or none)', "@lc");
ok(!@long, 'every statement body is short (250 words at most): the kit\'s own words, not a copied text', join "\n", @long);
ok(!@copied, 'no statement carries a stock LeetCode sentence', join "\n", @copied);
my %origin; $origin{ $_->{origin} }++ for @P;
ok(($origin{technique} // 0) >= 54 && ($origin{ladder} // 0) == 29, "origins: technique $origin{technique}, ladder " . ($origin{ladder} // 0) . ", " . join(', ', map { "$_ $origin{$_}" } grep { !/^(?:technique|ladder)$/ } sort keys %origin));

# ---------------------------------------------------------------- every reference passes, every stub fails cleanly
my (@reffail, @stubpass, @stubcrash, @kind);
for my $p (@P) {
    my $spec = eval { Drills::load_tests("$p->{path}/tests.pl") };
    if (!$spec || !@{ $spec->{cases} // [] }) { push @reffail, "$p->{id}: tests.pl does not load: $@"; next }
    my $k = $spec->{stdio} ? 'stdio' : $spec->{class} ? 'class' : 'function';
    push @kind, "$p->{id}: statement says $p->{kind}, tests.pl is $k" if $k ne $p->{kind};
    push @reffail, "$p->{id}: only " . scalar(@{ $spec->{cases} }) . ' case(s)' if @{ $spec->{cases} } < 2;
    my $r = Drills::run_tests($p, "$p->{path}/solution.pl", timeout => 30);   # a generous limit: a loaded machine must not fail a reference
    push @reffail, "$p->{id}: " . ($r->{error} // join(', ', map { "$_->{name}: " . ($_->{error} // "got $_->{got}, want $_->{want}") } grep { !$_->{ok} } @{ $r->{cases} })) if $r->{error} || $r->{passed} != $r->{total};
    my $s = Drills::run_tests($p, "$p->{path}/stub.pl");
    push @stubcrash, "$p->{id}: $s->{error}" if $s->{error};
    push @stubcrash, map { "$p->{id}: $_->{name}: $_->{error}" } grep { $_->{error} && $_->{error} =~ /timeout|not run/ } @{ $s->{cases} };
    push @stubpass, $p->{id} if !$s->{error} && $s->{passed} == $s->{total};
}
ok(!@kind, 'every statement\'s Kind matches its tests.pl', join "\n", @kind);
ok(!@reffail, 'every reference solution passes its own tests (' . scalar(@P) . ' problems)', join "\n", @reffail);
ok(!@stubcrash, 'every stub loads and runs (no syntax error, no hang)', join "\n", @stubcrash);
ok(!@stubpass, 'every stub fails its tests', "@stubpass");
my (@nohead, @noperl);
for my $p (@P) {
    my $sol = slurp("$p->{path}/solution.pl") // '';
    push @nohead, $p->{id} unless $sol =~ /\A#[^\n]*\n(?:#[^\n]*\n)*/ && $sol =~ /^#\s*Pattern:/m && $sol =~ /^#\s*Time:.*O\(/m && $sol =~ /^#\s*Edge:/m && $sol =~ /^#\s*Perl:/m;
    push @noperl, $p->{id} unless $sol =~ /^use strict;$/m && $sol =~ /^use warnings;$/m;
}
ok(!@nohead, 'every solution opens with its notes: Pattern, Time (O(...)), Edge, Perl', "@nohead");
ok(!@noperl, 'every solution uses strict and warnings', "@noperl");
my ($rc, $out) = run($ROOT, $^X, "$ROOT/drills/toolbelt.pl");
ok($rc == 0 && $out =~ /toolbelt: all \d+ idioms verified/, 'drills/toolbelt.pl: every idiom verified', $out);

# ---------------------------------------------------------------- comparing results
ok(Drills::same([1, 2], [1, 2]) && !Drills::same([1, 2], [2, 1]), 'same: exact order matters');
ok(Drills::same([2, 1], [1, 2], 'unordered') && Drills::same([[2, 1], [3]], [[3], [1, 2]], 'nested'), 'same: unordered and nested');
ok(Drills::same(10.0, '10') && Drills::same(4.5, '4.50') && !Drills::same('', 0), 'same: numbers by value, the empty string is not 0');
ok(Drills::same('', 0, 'bool') && Drills::same(1, 'yes', 'bool') && Drills::same(0.1 + 0.2, 0.3, 'float'), 'same: bool and float');
ok(Drills::canon({ b => [1, undef], a => 'x' }) eq '{a => "x", b => [1, undef]}', 'canon: hashes sorted by key');
ok(join(',', @{ Drills::list_to(Drills::list_from([1, 2, 3])) }) eq '1,2,3', 'list_from / list_to round trip');
ok(Drills::canon(Drills::tree_to(Drills::tree_from([3, 9, 20, undef, undef, 15, 7]))) eq '[3, 9, 20, undef, undef, 15, 7]', 'tree_from / tree_to round trip');

# ---------------------------------------------------------------- drill.pl in a temporary workspace
($rc, $out) = drill('list');
ok($rc == 0 && $out =~ /^1\. The ladder/m && $out =~ /p12-dedup/ && $out =~ /two-sum/, 'list: every section and problem');
($rc, $out) = drill('list', 'ladder');
ok($rc == 0 && $out =~ /p57/ && $out !~ /^\s+two-sum\s/m, 'list SECTION: one section');
($rc, $out) = drill('show', 'p12');
ok($rc == 0 && $out =~ /^LeetCode:/m, 'show p12: a shortened id prints the statement');
($rc, $out) = drill('show', 'p2');
ok($rc == 1 && $out =~ /matches several problems/, 'an ambiguous id is refused with the candidates');
($rc, $out) = drill('show', 'nosuchproblem');
ok($rc == 1 && $out =~ /drill: no problem matches/, 'an unknown id is refused');
($rc, $out) = drill('solution', 'p12');
ok($rc == 1 && $out =~ /no attempt recorded/, 'solution is gated until an attempt is recorded');
($rc, $out) = drill('test', 'p12');
ok($rc == 1 && $out =~ /no file/, 'test before start: no file');
($rc, $out) = drill('start', 'p12');
ok($rc == 0 && -f "$WS/p12-dedup.pl" && $out =~ /clock started/ && (slurp("$WS/attempts.txt") // '') =~ /\tstart\tp12-dedup/, 'start: the stub in the workspace, the start recorded');
($rc, $out) = drill('test', 'p12');
ok($rc == 1 && $out =~ /FAIL/ && $out =~ /p12-dedup: \d+\/\d+ passed/ && $out =~ /min since start/, 'test on the stub: FAIL per case, the elapsed time');
my ($p12) = grep { $_->{id} eq 'p12-dedup' } @P;
copy("$p12->{path}/solution.pl", "$WS/p12-dedup.pl");
($rc, $out) = drill('test', 'p12');
ok($rc == 0 && $out !~ /FAIL/ && $out =~ /(\d+)\/\1 passed/, 'test on a right answer: every case passes, exit 0');
($rc, $out) = drill('solution', 'p12');
ok($rc == 0 && $out =~ /Pattern:/, 'solution after an attempt: the reference with its notes');
($rc, $out) = drill('solution', 'p13', '--force');
ok($rc == 0 && $out =~ /Pattern:/, 'solution --force: without an attempt');
($rc, $out) = drill('start', 'p12');
ok($rc == 0 && $out =~ /keeping your file/ && (slurp("$WS/p12-dedup.pl") // '') eq (slurp("$p12->{path}/solution.pl") // ''), 'start again keeps the file');
($rc, $out) = drill('log', 'p12', '7', 'pass', 'hash of seen tokens');
ok($rc == 0 && (slurp("$WS/log.txt") // '') =~ /^\d{4}-\d\d-\d\d \| p12-dedup \| 7 \| pass \| hash of seen tokens$/m, 'log ID MIN pass NOTES: one line appended');
($rc, $out) = drill('log', 'p12', 'second', 'try');
ok($rc == 0 && (slurp("$WS/log.txt") // '') =~ /\| p12-dedup \| \d+ \| pass \| second try$/m, 'log ID NOTES: minutes and result filled in');
my $before = slurp("$WS/log.txt");
($rc, $out) = drill('log', '--session', '1');
ok($rc == 0 && index(slurp("$WS/log.txt") // '', $before) == 0 && (slurp("$WS/log.txt") // '') =~ /SESSION 1 .*ONE THING TO REDO/s, 'log --session N: the session form appended, nothing rewritten');
($rc, $out) = drill('log');
ok($rc == 0 && $out =~ /p12-dedup/ && $out =~ /2 entries/, 'log: the log printed');
($rc, $out) = drill('stats');
ok($rc == 0 && $out =~ /^ladder\s+29\s+1\s+1\s/m, 'stats: per section, started and passed');
($rc, $out) = drill('next');
ok($rc == 0 && $out =~ /^next: p00-pong/ && $out =~ /why:/, 'next: the first unsolved ladder rung');
($rc, $out) = drill('check', 't1');
ok($rc == 0 && $out =~ /pass\s+p12-dedup/ && $out =~ /1 passed, 0 failed, 3 not started/, 'check t1: the tier, the files you have');
($rc, $out) = drill('check', 'pro', '--ref');
ok($rc == 0 && $out !~ /product-except-self/ && $out =~ /6 passed, 0 failed/, 'check SECTION: the section, not ids that start with its name');
($rc, $out) = drill('check', 'ladder', '--ref');
ok($rc == 0 && $out =~ /29 passed, 0 failed, 0 not started/, 'check ladder --ref: the whole ladder\'s references');
($rc, $out) = drill('phased');
ok($rc == 0 && $out =~ /Phase 1/ && $out =~ /sensors/, 'phased: the clock plan');
($rc, $out) = drill('phased', '1');
ok($rc == 0 && -f "$WS/phased-sensors.pl" && $out =~ /five clarifying questions/i, 'phased 1: the card, the file, the clock');
($rc, $out) = drill('phased', 'test', '1');
ok($rc == 1 && $out =~ /not yet/, 'phased test 1 on the stub: not yet');
for my $sc (qw(sensors payments)) {
    my @ok = map { my ($r) = drill('phased', 'test', $_, '--ref', '--scenario', $sc); $r == 0 ? 1 : 0 } 1 .. 4;
    ok(!grep({ !$_ } @ok), "phased test 1..4 --ref --scenario $sc: the reference passes every phase");
}
($rc, $out) = drill('phased', '9');
ok($rc == 1 && $out =~ /drill: usage/, 'phased with a bad argument: the usage line');
($rc, $out) = drill('frobnicate');
ok($rc == 2 && $out =~ /unknown command 'frobnicate'/, 'an unknown command exits 2');
($rc, $out) = drill('help', 'test');
ok($rc == 0 && $out =~ /^drill\.pl test/, 'help test: the command\'s help section');
($rc, $out) = drill('help');
ok($rc == 0 && $out =~ /CODING DRILLS/, 'help: the chapter');
ok(!-e "$ROOT/drills/attempts.txt" && !-e "$ROOT/drills/log.txt" && !-e "$ROOT/drills/p12-dedup.pl", 'nothing was written inside the kit');

# ---------------------------------------------------------------- practice lesson 9, performed
my $base = "$TMP/practice";
($rc, $out) = run($ROOT, $^X, 'agile.pl', 'practice', '9', '--dir', $base);
my $sb = "$base/lesson9";
ok($rc == 0 && -f "$sb/.practice" && $out =~ /Lesson 9/, 'practice 9: the sandbox and the task', $out);
($rc, $out) = run($ROOT, $^X, 'agile.pl', 'practice', 'check', '9', '--dir', $base);
ok($rc == 1 && $out =~ /not yet/, 'practice check 9 before the work: not yet');
run($ROOT, $^X, "$ROOT/drills/drill.pl", '--dir', $sb, 'start', 'p12-dedup');
copy("$p12->{path}/solution.pl", "$sb/p12-dedup.pl");
run($ROOT, $^X, "$ROOT/drills/drill.pl", '--dir', $sb, 'test', 'p12-dedup');
run($ROOT, $^X, "$ROOT/drills/drill.pl", '--dir', $sb, 'log', 'p12-dedup', 'seen hash');
($rc, $out) = run($ROOT, $^X, 'agile.pl', 'practice', 'check', '9', '--dir', $base);
ok($rc == 0 && $out =~ /lesson 9: done/, 'practice check 9 after the work: done', $out);

# ---------------------------------------------------------------- the public-repo sweep
my @files = (grep { -f } map { glob("$ROOT/drills/$_") } ('*', '*/*', '*/*/*', 'phased/*/*'));
push @files, map { "$ROOT/$_" } grep { -f "$ROOT/$_" } qw(lib/Drills.pm vim/plugin/drills.vim vim/autoload/drills.vim docs/DRILLS.html tests/drills.t);
my (@py, @personal);
for my $f (@files) {
    my $t = slurp($f) // '';
    (my $rel = $f) =~ s{^\Q$ROOT\E/}{};
    push @py, $rel if $f =~ /\.py$/ || $t =~ /\A#!.*python/ || $t =~ /^\s*(?:def \w+\(.*\):|import (?:sys|os|collections)\b)/m;
    my $home = join '', '/ho', 'me/';
    my $mnt = join '', '/mn', 't/c';
    push @personal, $rel if index($t, $home) >= 0 || index($t, $mnt) >= 0 || $t =~ /clem\x{65}ntsj/;
}
ok(@files > 600, 'the sweep covers drills/ and the new files (' . scalar(@files) . ')');
ok(!@py, 'no Python under drills/ or in the drill tools', "@py");
ok(!@personal, 'no personal paths in drills/ or the drill tools', "@personal");

# ---------------------------------------------------------------- the Vim trainer (when a vim is on PATH)
my $vim = grep { -x "$_/vim" || -x "$_/vim.exe" } split /:/, $ENV{PATH} // '';
if ($vim) {
    my $o = "$TMP/vim.out";
    my $script = "$TMP/t.vim";
    my $nsec = @S;
    my $nladder = @ladder;
    open my $fh, '>', $script or die "cannot write $script: $!\n";
    print $fh <<"VIM";
let g:drills_headless = 1
let g:drills_shuffle = 0
let g:drills_fade_steps = 3
let g:drills_work = '$TMP/vimws'
let s:o = []
function! T(c, name) abort
  call add(s:o, (a:c ? 'ok ' : 'not ok ') . a:name)
endfunction
try
call T(drills#Normalize(['my \$x = 1;  # set', '', '  return \$#a; # last']) ==# "my\\\$x=1;\\nreturn\\\$#a;", 'Normalize drops comments, blank lines and spaces; keeps \$#')
call T(drills#Same("sub f {\\n  my \\\$s = '#'; # note\\n}", ['sub f {', "my \\\$s='#';", '}']), 'Same ignores comments and indentation, not a # in quotes')
call T(!drills#Same('sub f { 1 }', 'sub f { 2 }'), 'Same tells different code apart')
let s:L = ['sub f {', '    my (\$a, \$b) = \@_;', '    return \$a + \$b;', '}']
call T(drills#Fade(s:L, 1, 5) == s:L, 'Fade rep 1: the full text')
call T(drills#Fade(s:L, 5, 5) == [], 'Fade last rep: blind')
let s:f2 = drills#Fade(s:L, 2, 5, 7)
let s:f4 = drills#Fade(s:L, 4, 5, 7)
let s:n2 = len(substitute(join(s:f2, ''), '[^_]', '', 'g'))
let s:n4 = len(substitute(join(s:f4, ''), '[^_]', '', 'g'))
call T(s:n2 > 0 && s:n4 > s:n2, 'Fade blanks more tokens rep by rep')
call T(len(s:f2) == len(s:L) && s:f2[1] =~# '^    ', 'Fade keeps the lines and the indentation')
let s:c = drills#Cards()
call T(len(s:c) == $nsec && len(s:c[0].cards) == $nladder, 'Cards: one level per section, one card per solution')
call T(s:c[3].cards[0].prompt =~# '^sub ' && s:c[3].cards[0].code[-1] !=# '1;' && join(s:c[3].cards[0].code, '') !~# 'use strict', 'a card starts at the sub line, without the notes, use lines or 1;')
DrillTrain
let s:g = drills#State()
call T(s:g.state ==# 'typing' && s:g.level == 1 && s:g.round == 1, ':DrillTrain deals the first card of level 1')
call T(index(getline(1, '\$'), '  | ' . s:g.item.code[-1]) >= 0, 'rep 1 shows the solution')
let s:mark = '>>> type the answer below this line; everything above it is ignored'
call setline(index(getline(1, '\$'), s:mark) + 2, 'wrong answer')
DrillAnswer
call T(s:g.state ==# 'shown' && empty(s:g.misses), 'a wrong hinted rep shows the solution, no miss counted')
DrillNext
call T(s:g.state ==# 'typing' && s:g.round == 1, 'Next after a wrong hinted rep: the same rep again')
let s:cards = 0
while s:g.state ==# 'typing'
  if s:g.round == 3 | let s:cards += 1 | endif
  call setline(index(getline(1, '\$'), s:mark) + 2, s:g.item.code)
  DrillAnswer
endwhile
call T(s:cards == $nladder && s:g.state ==# 'level-end' && s:g.hits == $nladder && s:g.unlocked == 2, 'every blind rep right first try clears level 1 and unlocks level 2')
call T(readfile(drills#ProgressFile())[-1] ==# 'unlocked 2', 'the progress is saved in the workspace')
DrillNext
call T(s:g.level == 2 && s:g.state ==# 'typing', 'Next after a cleared level: the next level')
let s:g.round = 3
DrillGiveUp
call T(s:g.state ==# 'shown' && len(s:g.misses) == 1, 'giving up on the blind rep is a miss')
while s:g.state !=# 'level-end'
  if s:g.state ==# 'shown' | DrillNext | continue | endif
  call setline(index(getline(1, '\$'), s:mark) + 2, s:g.item.code)
  DrillAnswer
endwhile
call T(s:g.unlocked == 2 && join(getline(1, '\$'), ' ') =~# 'Missed: ' && s:g.state ==# 'level-end', 'a level with a miss is not cleared')
call drills#Reset(1)
call T(drills#Unlocked() == 1, ':DrillReset locks every level but the first')
call T(exists(':DrillOpen') == 2 && exists(':DrillTest') == 2 && exists(':DrillTestAll') == 2 && maparg('<Leader>dt', 'n') =~# 'DrillTest', 'the ladder glue: :DrillOpen, :DrillTest, :DrillTestAll and \\\\dt')
call T(drills#IdOf('$ROOT/drills/01-ladder/p12-dedup/statement.txt') ==# 'p12-dedup' && drills#IdOf('/w/p12-dedup.pl') ==# 'p12-dedup', 'IdOf: a statement or a workspace file names its problem')
catch
call add(s:o, 'not ok ERR ' . v:exception . ' ' . v:throwpoint)
endtry
call writefile(s:o, '$o')
qa!
VIM
    close $fh;
    ($rc, $out) = run($ROOT, 'vim', '-Nu', 'NONE', '-es', '-c', 'syntax on', '-c', "source $ROOT/vim/scrum.vim", '-c', "source $script", '-c', 'qa!');
    my @v = split /\n/, slurp($o) // "not ok the Vim script did not run\n";
    for my $line (@v) { my ($good, $name) = $line =~ /^(ok|not ok) (.*)$/; ok($good && $good eq 'ok', "vim: " . ($name // $line)) }
    ok(@v >= 20, 'the Vim trainer checks ran (' . scalar(@v) . ')');
} else { print "# no vim on PATH: the trainer checks are skipped\n" }

print "1..$n\n";
print $bad ? "# $bad of $n FAILED\n" : "# all $n passed\n";
exit($bad ? 1 : 0);
