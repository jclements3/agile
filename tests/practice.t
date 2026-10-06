#!/usr/bin/perl
# perl tests/practice.t -- practice lessons 11-13 (lib/Practice.pm): the offline-GitLab lessons set up, then are solved
# the way their text in vim/doc/agile.txt says -- gl (bin/gitlab.pl, with the settings the sandbox's env.sh exports),
# git, and the Vim edits done here with substitutions -- and check as done; before the work, each check says what is
# missing. Lesson 10 is in tests/help.t with lesson 1.
#
# Lessons 12 and 13 replay the earlier lessons in their set-up, a few dozen git and perl starts each; under Git for
# Windows' Perl every start costs ~0.15 s, so there only lesson 11 runs unless PRACTICE_FULL=1.
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use File::Temp qw(tempdir);
use Cwd qw(abs_path);

my ($n, $bad) = (0, 0);
sub ok { my ($c, $name, $diag) = @_; $n++;
    if ($c) { print "ok $n - $name\n" } else { $bad++; print "not ok $n - $name\n"; print map { "#   $_\n" } split /\n/, $diag // '' } }
sub skip_ { my ($name, $why) = @_; $n++; print "ok $n - $name # skip $why\n" }
my $ROOT = abs_path("$FindBin::Bin/..");
my $TMP = tempdir(CLEANUP => 1);
my %ENV0 = %ENV;
sub run {                                        # (cwd, @cmd) -> (exit status, stdout+stderr)
    my ($cwd, @cmd) = @_;
    require Cwd; my $back = Cwd::getcwd();
    chdir $cwd or return (255, "cannot chdir $cwd: $!");
    my $out = '';
    if (open my $ph, '-|') { local $/; $out = <$ph> // ''; close $ph }
    else { open STDERR, '>&', \*STDOUT; exec @cmd or do { print "cannot run $cmd[0]: $!\n"; require POSIX; POSIX::_exit(127) } }
    my $rc = $? >> 8; chdir $back; ($rc, $out);
}
sub slurp { my $f = shift; open my $fh, '<:raw', $f or return undef; local $/; my $t = <$fh>; close $fh; $t }
sub spew { my ($f, $t) = @_; open my $fh, '>:raw', $f or die "cannot write $f: $!\n"; print $fh $t; close $fh }
sub vimedit { my ($f, $sub) = @_; my $t = slurp($f) // ''; local $_ = $t; $sub->(); spew($f, $_); $_ ne $t }

my $base = "$TMP/practice";
my ($rc, $out);
sub practice { run($TMP, $^X, "$ROOT/agile.pl", q(practice), @_, q(--dir), q(practice)) }   # a relative --dir, from $TMP: the same sandboxes as $base
sub lesson_env {                                 # what `source ../env.sh` does: the exports, read from the file itself
    my ($sb) = @_;
    %ENV = %ENV0;
    my $sh = slurp("$sb/env.sh") // '';
    $ENV{$1} = $2 while $sh =~ /^export (\w+)='([^']*)'$/mg;
    delete @ENV{qw(GIT_AUTHOR_DATE GIT_COMMITTER_DATE)};
    $sh;
}
sub gl { my ($w, @a) = @_; run($w, $^X, "$ROOT/bin/gitlab.pl", @a) }
sub git { my ($w, @a) = @_; run($w, 'git', @a) }

my @need = grep { !-f "$ROOT/$_" } qw(sim/tidewater-v1.pl bin/gitlab.pl lib/GitLab.pm lib/GitFlow.pm tools/gitlab/kickoff.pl examples/tidewater-v1/layout.map tools/gitlab/templates/ci/job.pl);
my $full = !($^O eq 'cygwin' || $^O eq 'msys' || $^O eq 'MSWin32') || $ENV{PRACTICE_FULL};
my $ST = 'model/physical/stations/Stations.sysml';    # where the layout map puts the Stations package

if (@need) { skip_("practice lessons 11-13", "not in this checkout: @need") }
else {
    # ------------------------------------------------------------ lesson 11: your first merge request (Bob)
    ($rc, $out) = practice('11');
    my $sb = "$base/lesson11"; my $w = "$sb/work";
    ok($rc == 0 && -d "$w/.git" && -f "$sb/env.sh" && -f "$sb/gitlab/gitlab.json" && $out =~ /you are Bob/, 'practice 11 sets up the offline GitLab, the project and Bob\'s clone', $out);
    ok(-f "$w/$ST" && -f "$w/model/library/conventions/Conventions.sysml" && -f "$w/.ci/layout.map" && -f "$w/.ci/outline-max" && -f "$w/sysml.conf",
       'the clone is the kickoff.pl scaffold with drop v1.0 at the layout map\'s paths');
    my $sh = lesson_env($sb);
    ok($ENV{GITLAB_LOCAL} =~ m{^(?:/|[A-Za-z]:)} && $ENV{GITLAB_LOCAL} =~ m{/practice/lesson11/gitlab$}, q(a relative --dir: env.sh still names absolute paths), $sh);
    ok($ENV{GITLAB_USER} eq 'bob' && $ENV{GITLAB_PROJECT} eq 'tidewater/model' && $sh =~ /^gl\(\) \{ perl "\$KIT\/bin\/gitlab\.pl" "\$@"; \}$/m, 'env.sh exports the GitLab settings and defines gl');
    ($rc, $out) = run($sb, 'sh', '-n', 'env.sh');
    ok($rc == 0, 'env.sh is valid sh', $out);
    ($rc, $out) = gl($w, 'mr', 'list', '--state', 'all');
    ok($out =~ /!1\s+merged\s+feature\/drop-v1\.0 -> develop/, 'drop v1.0 came in through vendor/prime by merge request (!1)', $out);
    ($rc, $out) = practice('check', '11');
    ok($rc == 1 && $out =~ /no merge request from a feature branch yet/, 'check 11 before the work: not yet, with the next step', $out);
    ($rc, $out) = gl($w, 'issue', 'show', '1');
    ok($rc == 0 && $out =~ /Tag StationSegment/ && $out =~ /\@bob/, 'step 1: issue #1 is Bob\'s task', $out);
    ($rc, $out) = gl($w, 'flow', 'start', 'feature', '1-tag-stationsegment');
    ok($rc == 0 && $out =~ m{feature/1-tag-stationsegment}, 'step 2: gl flow start feature', $out);
    my $st = "$w/$ST";
    vimedit($st, sub { s{(    part def StationSegment \{\n)        // TODO stereotype Tidewater_Profile:L2Segment[^\n]*\n}{$1        \@L2Segment\n}; s{(package Stations \{\n)}{$1    private import Conventions::*;\n} });
    git($w, 'add', 'model');
    ($rc, $out) = git($w, 'commit', '-q', '-m', 'Tag StationSegment with its level (L2Segment)');
    ok($rc == 0, 'step 3: the change, committed (the semicolon left out on purpose)', $out);
    ($rc, $out) = gl($w, 'flow', 'finish', '--title', 'Tag StationSegment with its level', '--description', 'Closes #1');
    ok($rc == 0 && $out =~ /!2 / && $out =~ /pipeline #(\d+) failed/, 'step 4: gl flow finish opens !2 and its pipeline fails', $out);
    my ($pl) = $out =~ /pipeline #(\d+)/;
    ($rc, $out) = gl($w, 'pipeline', 'show', $pl // 0);
    my ($log) = $out =~ /grammar\s+failed.*?(\S+grammar\.log)/;
    ok($rc == 0 && $log && (slurp($log) // '') =~ /Stations\.sysml:14:9: error: unexpected 'doc'/, 'step 5: the grammar job\'s log names the line', $out);
    ($rc, $out) = gl($w, 'mr', 'merge', '2');
    ok($rc != 0 && $out =~ /pipeline must succeed/, 'step 5: a red pipeline blocks the merge', $out);
    vimedit($st, sub { s/^(        \@L2Segment)$/$1;/m });
    git($w, 'commit', '-q', '-am', 'Add the missing semicolon');
    ($rc, $out) = gl($w, 'flow', 'publish');
    ($rc, $out) = gl($w, 'mr', 'show', '2');
    ok($rc == 0 && $out =~ /pipeline: #\d+ success/, 'step 6: the fix, published: the same MR goes green (the full scaffold pipeline)', $out);
    ($rc, $out) = gl($w, 'mr', 'merge', '2');
    ok($rc != 0 && $out =~ /approvals required/, 'step 7: no merge without an approval', $out);
    ($rc, $out) = gl($w, '--as', 'jim', 'mr', 'approve', '2');
    ($rc, $out) = gl($w, 'mr', 'merge', '2');
    ok($rc == 0 && $out =~ /merged/, 'step 7: Jim approves, Bob merges', $out);
    ($rc, $out) = gl($w, 'issue', 'show', '1');
    ok($out =~ /#1\s+closed/, 'step 7: "Closes #1" closed the issue', $out);
    git($w, 'checkout', '-q', 'develop');
    ($rc, $out) = gl($w, 'flow', 'sync');
    ok($rc == 0 && (slurp($st) // '') =~ /^\s+\@L2Segment;$/m, 'step 8: develop, synced, holds the change', $out);
    ($rc, $out) = practice('check', '11');
    ok($rc == 0 && $out =~ /lesson 11: done/, 'check 11 after the work: done', $out);

    if (!$full) { skip_('practice lessons 12 and 13', 'slow under this Perl (PRACTICE_FULL=1 runs them)') }
    else {
        # -------------------------------------------------------- lesson 12: a prime drop (Tom)
        ($rc, $out) = practice('12');
        $sb = "$base/lesson12"; $w = "$sb/work";
        ok($rc == 0 && -f "$sb/drops/v1.1/tidewater.xmi" && $out =~ /you are Tom/, 'practice 12 sets up the project after lesson 11, drop v1.1 delivered', $out);
        lesson_env($sb);
        ($rc, $out) = practice('check', '12');
        ok($rc == 1 && $out =~ /not on vendor\/prime yet/, 'check 12 before the work: not yet', $out);
        ($rc, $out) = run($w, $^X, "$ROOT/bin/xmi2sysml.pl", '--delta', '../drops/v1.0/tidewater.xmi', '../drops/v1.1/tidewater.xmi');
        ok($rc == 0 && $out =~ /7 added, 0 removed, 1 changed/ && $out =~ /SensorSuite::hygrometer/, 'step 2: the delta report', $out);
        ($rc, $out) = gl($w, 'flow', 'vendor', '../drops/v1.1', 'v1.1');
        ok($out =~ m{conflicts:\s+\Q$ST\E}, 'step 3: gl flow vendor (with .ci/layout.map) stops on the conflict', $out);
        ($rc, $out) = git($w, 'ls-tree', '-r', '--name-only', 'origin/vendor/prime', '--', 'model/physical/stations', 'model/library/conventions');
        ok($out =~ m{^\Q$ST\E$}m && $out =~ m{^model/library/conventions/Conventions\.sysml$}m, 'vendor/prime: the drop at the map\'s paths, the government\'s Conventions kept', $out);
        $st = "$w/$ST";
        my $t = slurp($st) // '';
        ok(2 == (() = $t =~ /^<<<<<<< HEAD$/mg) && $t =~ /^\|\|\|\|\|\|\| /m && $t =~ /humiditySensor/ && $t =~ /hygrometer/, 'step 4: two conflicts, three parts each (diff3)');
        vimedit($st, sub { s{<<<<<<< HEAD\n.*?\n=======\n(.*?)>>>>>>> vendor/prime\n}{$1}sg; s{(    part def Hygrometer \{\n)        // TODO stereotype Tidewater_Profile:L5Assembly[^\n]*\n}{$1        \@L5Assembly;\n} });
        ($rc, $out) = run($w, $^X, "$ROOT/tools/sysml/model.pl", 'lint');
        ok($out =~ /errors=0 warnings=0/, 'step 5: lint after the resolution', $out);
        git($w, 'add', 'model');
        ($rc, $out) = git($w, 'commit', '-q', '--no-edit');
        ok($rc == 0, 'step 6: the merge committed', $out);
        ($rc, $out) = gl($w, 'flow', 'finish', '--title', 'Prime drop v1.1', '--description', 'Closes #3 and #2');
        ok($rc == 0 && $out =~ /!4 / && $out =~ /pipeline #(\d+) failed/, 'step 6: !4, and the docs gate fails (docs/ is generated from the model)', $out);
        ($pl) = $out =~ /pipeline #(\d+)/;
        ($rc, $out) = gl($w, 'pipeline', 'show', $pl // 0);
        ($log) = $out =~ /docs\s+failed.*?(\S+docs\.log)/;
        ok($log && (slurp($log) // '') =~ /docs\/ is stale: run model\.pl docs and commit/ && $out !~ /(?:grammar|lint|outline|complexity|trace)\s+failed/, 'step 7: only docs failed, and its log says what to do', $out);
        run($w, $^X, "$ROOT/tools/sysml/model.pl", 'docs');
        git($w, 'add', 'docs');
        ($rc, $out) = git($w, 'commit', '-q', '-m', 'Regenerate docs for drop v1.1');
        ($rc, $out) = gl($w, 'flow', 'publish');
        ($rc, $out) = gl($w, 'mr', 'show', '4');
        ok($out =~ /pipeline: #\d+ success/, 'step 7: docs regenerated: green', $out);
        gl($w, '--as', 'jim', 'mr', 'approve', '4');
        ($rc, $out) = gl($w, 'mr', 'merge', '4');
        if ($rc && $out =~ /code owner approval required/) { gl($w, '--as', 'bob', 'mr', 'approve', '4'); ($rc, $out) = gl($w, 'mr', 'merge', '4') }
        ok($rc == 0 && $out =~ /merged/, 'step 8: approved and merged', $out);
        ($rc, $out) = practice('check', '12');
        ok($rc == 0 && $out =~ /lesson 12: done/, 'check 12 after the work: done', $out);

        # -------------------------------------------------------- lesson 13: your first baseline (Tom prepares, Jim signs)
        ($rc, $out) = practice('13');
        $sb = "$base/lesson13"; $w = "$sb/work";
        ok($rc == 0 && $out =~ /you are Tom/, 'practice 13 sets up the project after lesson 12', $out);
        ok((slurp("$w/CHANGELOG.md") // '') =~ /^## \[Unreleased\]/m && (slurp("$w/CHANGELOG.md") // '') !~ /^## \[baseline-/m, 'the CHANGELOG has no baseline yet (the scaffold\'s example is gone)');
        lesson_env($sb);
        ($rc, $out) = practice('check', '13');
        ok($rc == 1 && $out =~ /no merge request from a release branch/, 'check 13 before the work: not yet', $out);
        ($rc, $out) = gl($w, 'flow', 'start', 'release', 'baseline-1');
        ok($rc == 0 && $out =~ m{release/baseline-1}, 'step 2: the release branch', $out);
        vimedit("$w/CHANGELOG.md", sub { s{(\n\[Unreleased\]:)}{\n## [baseline-1] -- 2027-01-15\n\n### Added\n- Level tags on StationSegment and Hygrometer (!2, !4)\n\n### Prime drops merged\n- v1.0, 2026-10-02\n- v1.1, 2027-01-08 (#3); closes DR-5 (#2)\n$1} });
        git($w, 'commit', '-q', '-am', 'CHANGELOG: baseline-1');
        ($rc, $out) = gl($w, 'flow', 'finish', '--title', 'Baseline 1');
        ok($rc == 0 && $out =~ /!5 release\/baseline-1 -> main/ && $out =~ /pipeline #\d+ success/, 'step 3: !5 to main, green', $out);
        ($rc, $out) = gl($w, 'mr', 'merge', '5');
        ok($rc != 0 && $out =~ /approvals required/, 'step 4: GitLab names the missing approval', $out);
        gl($w, '--as', 'jim', 'mr', 'approve', '5');
        ($rc, $out) = gl($w, 'mr', 'merge', '5');
        ok($rc != 0 && $out =~ /code owner approval required for /, 'step 4: then the missing code owner', $out);
        gl($w, '--as', 'bob', 'mr', 'approve', '5');
        ($rc, $out) = gl($w, 'mr', 'merge', '5');
        ok($rc == 0 && $out =~ /merged/, 'step 4: merged into main', $out);
        ($rc, $out) = gl($w, 'flow', 'released', '5', '--notes', 'CHANGELOG.md');
        ok($rc == 0 && $out =~ /tag baseline-1 \(sha256=[0-9a-f]{64}\)/ && $out =~ /back-merge !6/, 'step 5: tag, release, back-merge', $out);
        ($rc, $out) = gl($w, 'pipeline', 'list');
        ok($out =~ /#\d+\s+success\s+push\s+baseline-1\b/, 'step 5: the tag\'s own pipeline re-checks the baseline: green', $out);
        gl($w, '--as', 'jim', 'mr', 'approve', '6');
        gl($w, '--as', 'bob', 'mr', 'approve', '6');
        ($rc, $out) = gl($w, 'mr', 'merge', '6');
        ok($rc == 0 && $out =~ /merged/, 'step 6: the back-merge merged', $out);
        ($rc, $out) = gl($w, 'pages');
        ok($rc == 0 && $out =~ /pages\.gitlab\.local/, 'step 6: gl pages', $out);
        ($rc, $out) = practice('check', '13');
        ok($rc == 0 && $out =~ /lesson 13: done/, 'check 13 after the work: done', $out);
    }
    %ENV = %ENV0;
    ($rc, $out) = practice('reset', '11');
    ok($rc == 0 && !-e "$base/lesson11", 'practice reset 11 removes the sandbox');
}

print "1..$n\n";
print $bad ? "# $bad of $n FAILED\n" : "# all $n passed\n";
exit($bad ? 1 : 0);
