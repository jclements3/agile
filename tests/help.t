#!/usr/bin/perl
# perl tests/help.t -- the offline help (vim/doc/agile.txt, agile-errors.txt; lib/Help.pm, lib/Practice.pm):
# everything the code offers has a tag, every message the code prints is in the catalog, every link resolves,
# the command-line help works, docs/HELP.html and docs/help/quickref.md are up to date, practice lesson 1 passes.
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use File::Temp qw(tempdir);
use Cwd qw(abs_path getcwd);
use Help ();

my ($n, $bad) = (0, 0);
sub ok { my ($c, $name, $diag) = @_; $n++;
    if ($c) { print "ok $n - $name\n" } else { $bad++; print "not ok $n - $name\n"; print map { "#   $_\n" } split /\n/, $diag if defined $diag } }

my $ROOT = abs_path("$FindBin::Bin/..");
my $TMP = tempdir(CLEANUP => 1);
$ENV{$_} = 'help.t' for qw(GIT_AUTHOR_NAME GIT_COMMITTER_NAME);
$ENV{$_} = 'help.t@localhost' for qw(GIT_AUTHOR_EMAIL GIT_COMMITTER_EMAIL);
sub run { my ($cwd, @cmd) = @_;                 # -> (exit status, stdout+stderr)
    my $back = getcwd(); chdir $cwd or die "cannot chdir $cwd: $!\n";
    my $out = '';
    my $pid = open(my $ph, '-|');
    die "cannot fork: $!\n" unless defined $pid;
    if (!$pid) { open STDERR, '>&', \*STDOUT; exec @cmd or exit 127 }
    { local $/; $out = <$ph> // '' } close $ph;
    my $rc = $? >> 8; chdir $back; ($rc, $out) }
sub slurp { my $f = shift; open my $fh, '<:raw', $f or return undef; local $/; my $t = <$fh>; close $fh; $t }

# Internal invariants: messages that mean a bug in the kit, not a user mistake. They need no catalog entry,
# but each must be listed in the source's "Internal:" lines (agile-err-internal) so the user sees them named.
my @INTERNAL = (": unknown function '*'", ': empty list', 'range: zero step', 'chunksOf: n must be > 0', 'unwrap: *');

# ---------------------------------------------------------------- the source
my @files = Help::doc_files($ROOT);
ok(@files == 2, 'vim/doc/agile.txt and vim/doc/agile-errors.txt exist');
for my $f (@files) {
    my $t = slurp($f);
    (my $b = $f) =~ s{.*/}{};
    ok($t =~ /\A\*\Q$b\E\*\t\S/, "$b: first line is the Vim help header *$b*<Tab>title");
    ok($t =~ /\n vim:tw=78:ts=8:ft=help:norl:\n\z/, "$b: ends with the help modeline");
    ok($t !~ /[^\x09\x0a\x20-\x7e]/, "$b: plain ASCII (any console, any code page)");
    ok($t !~ /\r/, "$b: LF line ends");
}
my $h = Help::load(root => $ROOT);
my %count; $count{$_}++ for map { @{ $_->{tags} } } @{ $h->{sections} };
my @dup = grep { $count{$_} > 1 } sort keys %count;
ok(!@dup, 'no tag is defined twice', "duplicates: @dup");
my @odd = grep { !/^(?:agile(?:-[\w!.:-]+)?|:S\w+|:Idef\w+|:Drill\w+|\\[simd]\w)$/ } sort keys %count;
ok(!@odd, 'every tag is agile-..., :S..., :Idef..., :Drill... or a \\s/\\i/\\m/\\d key (no stray *word* in the text)', "odd tags: @odd");
ok(scalar(keys %count) >= 300, 'at least 300 tags (' . scalar(keys %count) . ')');

# ---------------------------------------------------------------- everything the code offers has a tag
my @req = Help::required_tags($ROOT);
my %kind;
for my $r (@req) { my ($k) = $r->[1] =~ /^(daily\.pl|scrum\.pl|ledger\.pl|stand-up|scrum\.conf|:|\\|\S+)/; $kind{$k}++ }
ok($kind{'daily.pl'} >= 35, "daily.pl subcommands found in the dispatch table ($kind{'daily.pl'})");
ok(($kind{'stand-up'} // 0) >= 20, 'stand-up verbs found in Standup.pm (' . ($kind{'stand-up'} // 0) . ')');
ok(($kind{'scrum.conf'} // 0) >= 30, 'scrum.conf keys found (' . ($kind{'scrum.conf'} // 0) . ')');
ok(scalar(grep { $_->[0] =~ /^\\s/ } @req) >= 13 && scalar(grep { $_->[0] =~ /^\\i/ } @req) >= 9, '\\s and \\i keys found in the Vim files');
ok(scalar(grep { $_->[0] =~ /^:S/ } @req) >= 30 && scalar(grep { $_->[0] =~ /^:Idef/ } @req) >= 8, ':S and :Idef commands found in the Vim files');
ok(!-f "$ROOT/vim/ftplugin/sysml.vim" || (scalar(grep { $_->[0] =~ /^:Sys/ } @req) >= 9 && scalar(grep { $_->[0] =~ /^\\m/ } @req) >= 9), ':Sys commands and \\m keys found in vim/ftplugin/sysml.vim');
ok(!-f "$ROOT/drills/drill.pl" || (scalar(grep { $_->[0] =~ /^agile-drills-/ } @req) >= 10 && scalar(grep { $_->[0] =~ /^:Drill/ } @req) >= 8 && scalar(grep { $_->[0] =~ /^\\d/ } @req) >= 8), 'drill.pl commands, :Drill commands and \\d keys found (drills/, vim/plugin/drills.vim)');
for my $r (@req) { ok($h->{tags}{ $r->[0] }, "help tag *$r->[0]* for $r->[1]") }

# ---------------------------------------------------------------- every message the code prints is in the catalog
my @cat = Help::catalog($h);
ok(@cat >= 40, 'the error catalog has at least 40 entries (' . scalar(@cat) . ')');
for my $e (@cat) {
    my $body = Help::section_text($e->{section}, own => 1);
    ok($body =~ /^\s*Means:/m && $body =~ /^\s*Fix:/m, "$e->{tag}: says what it means and the fix");
}
my %src_internal = map { $_ => 1 } Help::internal_patterns($h);
ok(!grep({ !$src_internal{$_} } @INTERNAL), 'every internal invariant is listed in agile-err-internal');
my ($msgs, @unc) = (0);
for my $f (Help::message_files($ROOT)) {
    for my $m (Help::extract_messages($ROOT, $f)) {
        $msgs++;
        (my $probe = $m->{sample}) =~ s/\*/X/g;
        next if grep { $probe =~ Help::glob_re($_) } @INTERNAL;
        my ($e, $how) = Help::error_match($h, $probe);
        push @unc, "$m->{file}:$m->{line}: $m->{sample}" unless $e && $how eq 'pattern';
    }
}
ok($msgs >= 200, "messages extracted from bin/, lib/, agile.pl, idef0.pl, md2memo.pl ($msgs)");
ok(!@unc, 'every user-facing message matches a catalog pattern', join "\n", @unc);
my @files_scanned = Help::message_files($ROOT);
ok((grep { $_ eq 'tools/idef0/idef0.pl' } @files_scanned) && (grep { $_ eq 'lib/Standup.pm' } @files_scanned) && (grep { $_ eq 'bin/daily.pl' } @files_scanned), 'the scan covers bin/, lib/ and tools');
ok(!%Help::PENDING_FILES, 'no file is exempt from the message scan');
ok((grep { $_ eq 'tools/sysml/model.pl' } @files_scanned) && (grep { $_ eq 'lib/StatusMetrics.pm' } @files_scanned), 'the scan covers the SysML tools and the port/metrics libraries');

# ---------------------------------------------------------------- links
my $audit = Help::audit($h, root => $ROOT, internal => \@INTERNAL);
ok(!@{ $audit->{badlinks} }, 'every |link| resolves to a tag', join "\n", @{ $audit->{badlinks} });
ok(!$audit->{problems}, 'perl agile.pl help --check finds nothing', $audit->{text});
my @ph = sort { $a cmp $b } keys %{ { map { $_ => 1 } (join("\n", map { slurp($_) } @files) =~ /PLACEHOLDER\(([\w-]+)\)/g) } };
ok(!@ph, 'no PLACEHOLDER(...) is left in the help source', "placeholders: @ph");

# ---------------------------------------------------------------- the command line
my ($rc, $out) = run($ROOT, $^X, 'agile.pl', 'help');
ok($rc == 0 && $out =~ /HOW DO I/ && $out =~ /howto-townhall/, 'agile.pl help: the index, runbooks first');
($rc, $out) = run($ROOT, $^X, 'agile.pl', 'help', 'compile');
ok($rc == 0 && $out =~ /^daily\.pl compile/ && $out !~ /\*agile-/, 'agile.pl help compile: the section, tags rendered plainly');
($rc, $out) = run($ROOT, $^X, 'agile.pl', 'help', 'STown');
ok($rc == 0 && $out =~ /townhall in one tab/, 'agile.pl help STown: a Vim command by name');
($rc, $out) = run($ROOT, $^X, 'agile.pl', 'help', '\\sp');
ok($rc == 0 && $out =~ /Paste the clipboard/, 'agile.pl help \\sp: a key');
($rc, $out) = run($ROOT, $^X, 'agile.pl', 'help', 'banner');
ok($rc == 0 && $out =~ /marking banner/, 'agile.pl help banner: a scrum.conf key');
($rc, $out) = run($ROOT, $^X, 'agile.pl', 'help', 'carry');
ok($rc == 0 && $out =~ /Carryover/, 'agile.pl help carry: a verb');
($rc, $out) = run($ROOT, $^X, 'agile.pl', 'help', 'agile-howto-review');
ok($rc == 0 && $out =~ /You are done when/, 'agile.pl help agile-howto-review: a runbook with its done check');
($rc, $out) = run($ROOT, $^X, 'agile.pl', 'help', 'search', 'carryover', 'velocity');
ok($rc == 0 && $out =~ /agile-/ && $out =~ /best first/, 'agile.pl help search WORDS: ranked sections');
($rc, $out) = run($ROOT, $^X, 'agile.pl', 'help', 'search', 'zzqqxx');
ok($rc == 1, 'help search with no hit exits 1');
($rc, $out) = run($ROOT, $^X, 'agile.pl', 'help', 'error', "standups/2026-10-05.txt:7: unknown verb 'don'");
ok($rc == 0 && $out =~ /^FILE:LINE: unknown verb/ && $out =~ /Fix:/ && $out =~ /agile-err-unknown-verb/, 'agile.pl help error: the matching catalog entry');
($rc, $out) = run($ROOT, $^X, 'agile.pl', 'help', 'error', "standups/2026-10-06.txt: NOT applied\nstandups/2026-10-06.txt: 'A-9' is not committed in sprint 3 for Alpha (at: Backlog:Alpha)");
ok($rc == 0 && $out =~ /NOT applied/, 'help error: a pasted block is matched by its first line');
($rc, $out) = run($ROOT, $^X, 'agile.pl', 'help', 'error', 'cannot write reports/x.html: Permission denied at bin/daily.pl line 99.');
ok($rc == 0 && $out =~ /cannot write FILE/, 'help error: "at FILE line N." is ignored');
($rc, $out) = run($ROOT, $^X, 'agile.pl', 'help', 'error', 'roster marking domains refusing everything');
ok($rc == 0 && $out =~ /closest/, 'help error: no exact match gives the closest entry');
($rc, $out) = run($ROOT, $^X, 'agile.pl', 'help', 'model-pl');
ok($rc == 0 && $out =~ /elements=N errors=E/, 'agile.pl help model-pl');
($rc, $out) = run($ROOT, $^X, 'agile.pl', 'help', 'error', "xmi2sysml: legacy.xmi:12: end tag </packagedElement> does not match <ownedAttribute>");
ok($rc == 0 && $out =~ /agile-err-(?:xml|port-usage)/, 'help error: an XML error from the port tools');
($rc, $out) = run($ROOT, $^X, 'agile.pl', 'help', 'errors');
ok($rc == 0 && $out =~ /agile-err-not-applied/ && $out =~ /IDEF0 MODELS/, 'agile.pl help errors: the catalog as a list');
($rc, $out) = run($ROOT, $^X, 'agile.pl', 'help', 'nosuchtopicatall');
ok($rc == 1 && $out =~ /no topic/, 'an unknown topic exits 1 and says so');
($rc, $out) = run($TMP, $^X, "$ROOT/bin/daily.pl", 'help', 'lint');
ok($rc == 0 && $out =~ /^daily\.pl lint/, 'daily.pl help lint works outside a project');
($rc, $out) = run($TMP, $^X, "$ROOT/bin/daily.pl", '--help');
ok($rc == 0 && $out =~ /DAILY\.PL/, 'daily.pl --help');
($rc, $out) = run($TMP, $^X, "$ROOT/bin/daily.pl", '-h');
ok($rc == 0 && $out =~ /DAILY\.PL/, 'daily.pl -h');
($rc, $out) = run($TMP, $^X, "$ROOT/bin/daily.pl", 'status');
ok($rc == 1 && $out =~ /no scrum\.conf found/, 'daily.pl outside a project still says so (behaviour kept)');
($rc, $out) = run($TMP, $^X, "$ROOT/bin/scrum.pl", 'help');
ok($rc == 0 && $out =~ /scrum\.pl/ && $out =~ /velocity/, 'scrum.pl help');
($rc, $out) = run($TMP, $^X, "$ROOT/bin/scrum.pl", '--help', 'items');
ok($rc == 0 && $out =~ /Raw task query/, 'scrum.pl --help items');
($rc, $out) = run($TMP, $^X, "$ROOT/bin/ledger.pl", '-h');
ok($rc == 0 && $out =~ /ledger\.pl/ && $out =~ /forecast/, 'ledger.pl -h');
($rc, $out) = run($TMP, $^X, "$ROOT/bin/ledger.pl", 'help', 'evm');
ok($rc == 0 && $out =~ /Earned value/, 'ledger.pl help evm');

# ---------------------------------------------------------------- generated files are up to date
for my $g (['--html', 'docs/HELP.html'], ['--md', 'docs/help/quickref.md']) {
    my $fresh = "$TMP/" . (split m{/}, $g->[1])[-1];
    ($rc, $out) = run($ROOT, $^X, 'agile.pl', 'help', $g->[0], $fresh);
    my $want = slurp($fresh) // '';
    my $have = slurp("$ROOT/$g->[1]") // '';
    ok($rc == 0 && length $want && $want eq $have, "$g->[1] is up to date with vim/doc (perl agile.pl help $g->[0])");
}
my $html = slurp("$ROOT/docs/HELP.html") // '';
my %id = map { $_ => 1 } $html =~ /\bid="([^"]+)"/g;
my @dead = grep { !$id{$_} } $html =~ /href="#([^"]+)"/g;
ok(!@dead, 'every in-page link in docs/HELP.html has its target', "dead: @dead[0 .. ($#dead < 9 ? $#dead : 9)]");
ok($html =~ /How do I\.\.\.\?.*Reference.*Troubleshooting/s, 'docs/HELP.html: runbooks first, then reference, then troubleshooting');
ok($html !~ /<script/i, 'docs/HELP.html has no script');
my $md = slurp("$ROOT/docs/help/quickref.md") // '';
ok($md =~ /^# Quick reference/ && $md =~ /^## How do I/m && $md =~ /^## When something goes wrong/m && $md !~ /<\w+[ >]/, 'quickref.md: runbooks, commands, top errors, no HTML');
my $lines = () = $md =~ /\n/g;
ok($lines > 300 && $lines < 1200, "quickref.md is binder-chapter sized ($lines lines)");

# ---------------------------------------------------------------- practice lesson 1, performed
my $base = "$TMP/practice";
($rc, $out) = run($ROOT, $^X, 'agile.pl', 'practice', '--dir', $base);
ok($rc == 0 && $out =~ /^\s+1\s+Lesson 1/m && $out =~ /^\s+7\s+Lesson 7/m, 'agile.pl practice lists the lessons');
($rc, $out) = run($ROOT, $^X, 'agile.pl', 'practice', '1', '--dir', $base);
my $sb = "$base/lesson1";
ok($rc == 0 && -f "$sb/scrum.conf" && -f "$sb/.practice" && $out =~ /Lesson 1/ && $out =~ /Check:/, 'practice 1 sets up a sandbox project and prints the task', $out);
($rc, $out) = run($ROOT, $^X, 'agile.pl', 'practice', 'check', '1', '--dir', $base);
ok($rc == 1 && $out =~ /not yet/ && $out =~ /TODO/, 'practice check 1 before the work: not yet, with what is missing');
($rc, $out) = run($sb, $^X, "$ROOT/bin/daily.pl", 'new');
my ($sf) = $out =~ /^(standups\/\S+\.txt)$/m;
ok($rc == 0 && $sf && -f "$sb/$sf", 'the learner: daily.pl new');
if ($sf && open my $fh, '>>', "$sb/$sf") {
    print $fh "== Alpha\ncap 10\n", map({ "$_\n" } 'new AL-1 3 Set up the build p:1 e:"A1 Tooling" o:"Ann Lee"', 'new AL-2 5 Write the ICD p:2 e:"A1 Tooling" o:"Bob Ray"',
              'new AL-3 2 Draft the test plan p:3 e:"A1 Tooling" o:"Ann Lee"'), "commit AL-1 Ann Lee\ncommit AL-2 Bob Ray\n";
    close $fh;
}
($rc, $out) = run($sb, $^X, "$ROOT/bin/daily.pl", 'compile');
ok($rc == 0 && $out =~ /applied/, 'the learner: daily.pl compile', $out);
($rc, $out) = run($sb, $^X, "$ROOT/bin/daily.pl", 'commit');
ok($rc == 0 && $out =~ /committed/, 'the learner: daily.pl commit', $out);
($rc, $out) = run($ROOT, $^X, 'agile.pl', 'practice', 'check', '1', '--dir', $base);
ok($rc == 0 && $out =~ /lesson 1: done/, 'practice check 1 after the work: done', $out);
($rc, $out) = run($ROOT, $^X, 'agile.pl', 'practice', 'reset', '1', '--dir', $base);
ok($rc == 0 && !-e $sb, 'practice reset 1 removes the sandbox');
($rc, $out) = run($ROOT, $^X, 'agile.pl', 'practice', '99', '--dir', $base);
ok($rc == 2 && $out =~ /practice: no lesson 99/, 'an unknown lesson is refused');

# ---------------------------------------------------------------- Vim: :help agile through vim/scrum.vim (when a vim is on PATH)
my $vim = grep { -x "$_/vim" || -x "$_/vim.exe" } split /:/, $ENV{PATH} // '';
if ($vim) {
    my $o = "$TMP/vimhelp.txt";
    ($rc, $out) = run($ROOT, 'vim', '-Nu', 'NONE', '-es', '-c', 'syntax on', '-c', "source $ROOT/vim/scrum.vim",
        '-c', "try | help agile | call writefile([getline('.')], '$o') | help :STown | call writefile([getline('.')], '$o', 'a') | help \\sw | call writefile([getline('.')], '$o', 'a') | catch | call writefile(['ERR ' . v:exception], '$o', 'a') | endtry", '-c', 'qa!');
    my $v = slurp($o) // '';
    ok($v =~ /\*agile\*/ && $v =~ /\*:STown\*/ && $v =~ /\*\\sw\*/ && $v !~ /ERR/, ':help agile, :help :STown and :help \\sw open the kit help in Vim', $v);
} else { print "# no vim on PATH: the :help check is skipped\n" }

print "1..$n\n";
print $bad ? "# $bad of $n FAILED\n" : "# all $n passed\n";
exit($bad ? 1 : 0);
