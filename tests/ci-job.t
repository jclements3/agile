#!/usr/bin/perl
# perl tests/ci-job.t -- tools/gitlab/templates/ci/job.pl, the one script every model pipeline job runs: each job on a
# real model repo (Tidewater drop 1 and drop 2), the outline and trace ratchets, the baseline hash and toolchain, and the
# template's YAML (every job's script is `perl ci/job.pl NAME`).
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use File::Temp qw(tempdir);
use File::Path qw(make_path);
use File::Copy qw(copy);
use Digest::SHA ();
use GitLabCI ();

my ($n, $bad) = (0, 0);
sub check { my ($name, $got, $want) = @_; $n++;
    if ($got eq $want) { print "ok $n - $name\n" }
    else { $bad++; print "not ok $n - $name\n#   got:  $got\n#   want: $want\n" } }
sub like { my ($name, $got, $re) = @_; $n++;
    if ($got =~ $re) { print "ok $n - $name\n" } else { $bad++; my $g = substr($got, 0, 600); $g =~ s/\n/\n#   /g; print "not ok $n - $name\n#   got:  $g\n#   want: $re\n" } }
sub slurp { my $f = shift; open my $fh, '<:raw', $f or return ''; local $/; my $t = <$fh>; close $fh; $t }
sub spew { my ($f, $t) = @_; (my $d = $f) =~ s{/[^/]*$}{}; make_path($d) if $d ne $f; open my $fh, '>:raw', $f or die "$f: $!"; print $fh $t; close $fh }

my $ROOT = "$FindBin::Bin/..";
my $JOB = "$ROOT/tools/gitlab/templates/ci/job.pl";
my $tmp = tempdir(CLEANUP => 1);
my $repo = "$tmp/repo";
sub sh { my ($cmd) = @_; my $o = `$cmd 2>&1`; ($o, $? >> 8) }
sub q_ { my $s = shift; $s =~ s/'/'\\''/g; "'$s'" }
sub git { my $a = join ' ', map { q_($_) } @_; my $o = `git -C ${\ q_($repo)} -c core.autocrlf=false -c user.name=t -c user.email=t\@example.invalid -c commit.gpgsign=false -c tag.gpgsign=false $a 2>&1`; die "git @_: $o" if $?; $o }
sub job {                                     # job(NAME, %env) -> (output, exit)
    my ($name, %env) = @_;
    local $ENV{KIT} = exists $env{KIT} ? $env{KIT} : $ROOT;
    delete local $ENV{CI_PIPELINE_SOURCE}; delete local $ENV{CI_MERGE_REQUEST_DIFF_BASE_SHA}; delete local $ENV{CI_COMMIT_TAG};
    delete local $ENV{TRACE_MODE}; delete local $ENV{CI_API_V4_URL}; delete local $ENV{STATUS_TOKEN};
    local @ENV{ grep { $_ ne 'KIT' } keys %env } = map { $env{$_} } grep { $_ ne 'KIT' } keys %env;
    delete $ENV{KIT} unless defined $ENV{KIT};
    sh('cd ' . q_($repo) . ' && ' . q_($^X) . ' ci/job.pl ' . $name);
}

# ---- a model repo from drops 1 and 2
for my $d (1, 2) { my ($o, $rc) = sh(q_($^X) . " " . q_("$ROOT/sim/tidewater-v1.pl") . " --drop $d " . q_("$tmp/d$d")); die "drop $d: $o" if $rc }
make_path("$repo/ci", "$repo/.ci", "$repo/imports/v1.0", "$repo/model");
copy($JOB, "$repo/ci/job.pl") or die $!;
copy("$ROOT/tools/gitlab/templates/.gitignore", "$repo/.gitignore") or die $!;
copy("$tmp/d1/$_", "$repo/imports/v1.0/$_") for qw(tidewater.xmi tidewater.reqif MANIFEST.txt);
sh(q_($^X) . ' ' . q_("$ROOT/bin/xmi2sysml.pl") . ' --out ' . q_("$repo/model") . ' ' . q_("$tmp/d1/tidewater.xmi"));
sh(q_($^X) . ' ' . q_("$ROOT/bin/reqif2sysml.pl") . ' --layout {pkg}.sysml --out ' . q_("$repo/model/doors") . ' ' . q_("$tmp/d1/tidewater.reqif"));   # DOORS's own conversion, as the intake writes it
spew("$repo/sysml.conf", "title = Tidewater\nnoun_root = ObservationNetwork\nverb_root = ObserveCoast\nidef0_name = ObserveCoast\n");
git('init', '-q', '-b', 'develop');
sh('cd ' . q_($repo) . ' && ' . q_($^X) . ' ' . q_("$ROOT/tools/sysml/model.pl") . ' docs');
my ($out, $rc);

# ---- usage and KIT
($out, $rc) = job('nonsense');
check('unknown job: exit 2', $rc, 2);
like('unknown job: usage lists the jobs', $out, qr/usage: perl ci\/job\.pl .*grammar.*trace/);
($out, $rc) = job('lint', KIT => undef);
check('KIT unset: exit 2', $rc, 2);
like('KIT unset: says where to set it', $out, qr/KIT is not set: add it under Settings > CI\/CD > Variables/);
($out, $rc) = job('lint', KIT => "$tmp/nokit");
like('KIT wrong: names the path', $out, qr/does not hold the agile kit/);

# ---- the kit pin
spew("$repo/.kit-version", "2026.12.0\n");
($out, $rc) = job('todo', KIT_VERSION => '2026.10.0');
check('.kit-version: a different kit stops the job', $rc, 2);
like('.kit-version: says how to fix it', $out, qr/the kit on this runner is 2026\.10\.0, but \.kit-version pins 2026\.12\.0:\n  bump \.kit-version in a merge request/);
($out, $rc) = job('todo', KIT_VERSION => '2026.12.0');
check('.kit-version: the pinned kit runs', $rc, 0);
unlink "$repo/.kit-version";

# ---- the check jobs on drop 1
($out, $rc) = job('outline');
my ($v) = slurp("$repo/outline.txt") =~ /^violations\s+(\d+)/m;
check('outline: no .ci/outline-max means 0 allowed, so it fails', $rc, 1);
like('outline: says not to raise the number', $out, qr/this change adds outline violations \(\d+ > 0\): fix them, do not raise \.ci\/outline-max/);
spew("$repo/.ci/outline-max", "$v\n");
git('add', '-A'); git('commit', '-q', '-m', 'drop 1');
($out, $rc) = job('outline');
check('outline: at the allowed count it passes', $rc, 0);
my $ox = slurp("$repo/outline.xml");
check('outline JUnit: inherited findings are skipped, not failed (a green MR shows no red tests)', ($ox !~ /<failure/ && $ox =~ /<skipped message="inherited/ && $ox =~ /failures="0"/) ? 1 : 0, 1);
spew("$repo/.ci/outline-max", "0\n");
($out, $rc) = job('outline', CI_COMMIT_BRANCH => 'feature/drop-v1.1', CI_PIPELINE_SOURCE => 'push');
check('outline: a push to a drop branch is reported, not ratcheted', $rc, 0);
like('outline: says why', $out, qr/a prime drop: reported, not ratcheted/);
($out, $rc) = job('outline', CI_PIPELINE_SOURCE => 'merge_request_event', CI_MERGE_REQUEST_SOURCE_BRANCH_NAME => 'release/baseline-1');
check('outline: a release MR is reported, not ratcheted (develop checked it), like complexity', "$rc " . ($out =~ /a release: its changes were checked on develop; reported only/ ? 'says why' : $out), '0 says why');
($out, $rc) = job('outline', CI_COMMIT_BRANCH => 'release/baseline-1', CI_PIPELINE_SOURCE => 'push');
check('outline: and so is a push to the release branch', $rc, 0);
($out, $rc) = job('outline', CI_COMMIT_BRANCH => 'feature/9-x', CI_PIPELINE_SOURCE => 'push');
check('outline: a feature branch is still ratcheted', $rc, 1);
spew("$repo/.ci/outline-max", ($v + 3) . "\n");
($out, $rc) = job('outline');
like('outline: below the allowed count it asks to lower the number', $out, qr/lower \.ci\/outline-max to $v/);
spew("$repo/.ci/outline-max", ($v + 3) . "\n# room for new one-file folders: tighten it at the first baseline\n");
($out, $rc) = job('outline');
check('outline: a scaffold\'s commented allowance: the first line is the number, the room is not nagged',
      "$rc " . ($out =~ /allowed: @{[$v + 3]}\)/ ? 'read' : 'unread') . ($out =~ /room left for new folders \(see the comment in \.ci\/outline-max for when to tighten it to $v\)/ ? ' room' : ' nag'), '0 read room');
spew("$repo/.ci/outline-max", "$v\n");
($out, $rc) = job('grammar');
check('grammar: drop 1 parses', $rc, 0);
like('grammar: JUnit report written', slurp("$repo/grammar.xml"), qr/<testsuite/);
($out, $rc) = job('lint');
check('lint: drop 1 is 0/0', $rc, 0);
like('lint: Code Quality report written', slurp("$repo/lint-cq.json"), qr/^\[/);
($out, $rc) = job('todo');
like('todo: counts the TODO lines', $out, qr/TODO lines remaining: \d+/);
check('todo: never fails', $rc, 0);
like('todo: one line per TODO in todo.txt', slurp("$repo/todo.txt"), qr{^model/\S+\.sysml:\d+:\s*// TODO}m);
($out, $rc) = job('secrets');
check('secrets: a clean tree passes', $rc, 0);
spew("$repo/model/leak.txt", "token = glpat-" . ('a' x 20) . "\n");
git('add', '-A');
($out, $rc) = job('secrets');
check('secrets: a token fails the job', $rc, 1);
like('secrets: names the file and line', $out, qr{model/leak\.txt:1: matches});
git('rm', '-q', '--cached', 'model/leak.txt'); unlink "$repo/model/leak.txt";
($out, $rc) = job('docs');
check('docs: committed docs are current', $rc, 0);
spew("$repo/docs/Nouns.md", "stale\n");
git('add', '-A'); git('commit', '-q', '-m', 'stale docs');
($out, $rc) = job('docs');
check('docs: stale docs fail', $rc, 1);
like('docs: says how to fix', $out, qr/docs\/ is stale: run model\.pl docs and commit/);
git('checkout', '-q', 'HEAD~1', '--', 'docs'); git('commit', '-q', '-m', 'docs back');

# ---- trace: reports on develop, a ratchet on merge requests
($out, $rc) = job('trace');
check('trace on a push: reports, passes', $rc, 0);
like('trace: counts the gaps', $out, qr/trace gaps: 2 orphan\(s\), 9 unverified, 1 drifted/);
like('trace: DOORS is compared with the model, not with its own conversion (29 of 30 linked)', slurp("$repo/trace.txt"), qr/linked \(doorsId in the model\)\s+29 of 30/);
like('trace on a push: inherited gaps are skipped tests, none failed (a green job shows no red in the MR widget)', slurp("$repo/trace.xml"), qr/<testsuites name="sysml-trace" tests="\d+" failures="0"/);
like('trace on a push: each gap is still listed, as skipped', slurp("$repo/trace.xml"), qr/<skipped message="reported, not gated \(not a merge request\): TW-SYS-012/);
my ($base) = git('rev-parse', 'HEAD') =~ /([0-9a-f]{40})/;
($out, $rc) = job('trace', CI_PIPELINE_SOURCE => 'merge_request_event', CI_MERGE_REQUEST_DIFF_BASE_SHA => $base);
check('trace ratchet: no change, no new gap', $rc, 0);
like('trace ratchet: reports the target counts', $out, qr/no new trace gaps \(target branch: orphans 2, unverified 9, drift 1\)/);
like('trace ratchet: the target branch in one labelled line', $out, qr/^target branch: 29 of 30 linked; 2 orphan\(s\), 9 unverified, 1 drifted \(full report: trace-base\.txt\)$/m);
check('trace ratchet: the target branch\'s full report is not in the job log (only the change\'s)', scalar(() = $out =~ /^C requirements linked/mg), 1);
like('trace ratchet: the full target report is in trace-base.txt', slurp("$repo/trace-base.txt"), qr/^C requirements linked/m);
my ($req) = grep { slurp($_) =~ /satisfy TW_SYS_001 by/ } glob("$repo/model/*/*.sysml");
my $t = slurp($req); $t =~ s/^.*satisfy TW_SYS_001 by.*\n//mg; spew($req, $t);
git('add', '-A'); git('commit', '-q', '-m', 'lose a satisfy');
($out, $rc) = job('trace', CI_PIPELINE_SOURCE => 'merge_request_event', CI_MERGE_REQUEST_DIFF_BASE_SHA => $base);
check('trace ratchet: a removed satisfy fails the MR', $rc, 1);
like('trace ratchet: says which count grew', $out, qr/this change adds trace gaps: orphans 2 -> 3/);
like('trace ratchet: only the new gap is a failed test', slurp("$repo/trace.xml"), qr/<testsuites name="sysml-trace" tests="\d+" failures="1"/);
($out, $rc) = job('trace', CI_PIPELINE_SOURCE => 'merge_request_event', CI_MERGE_REQUEST_DIFF_BASE_SHA => $base, TRACE_MODE => 'report');
check('trace ratchet: TRACE_MODE=report never fails', $rc, 0);
git('revert', '--no-edit', 'HEAD');
# like with like: the same count but a different requirement is still a new gap (sets of ids, not counts)
$t = slurp($req); $t =~ s/^(.*)satisfy TW_SYS_001 by(.*)\n/$1satisfy TW_SYS_012 by$2\n/m; spew($req, $t);
git('add', '-A'); git('commit', '-q', '-m', 'fix one orphan, make another');
($out, $rc) = job('trace', CI_PIPELINE_SOURCE => 'merge_request_event', CI_MERGE_REQUEST_DIFF_BASE_SHA => $base);
check('trace ratchet: a swapped orphan (same count) still fails', $rc, 1);
like('trace ratchet: names the new gap', $out, qr/orphans 2 -> 2 \(new: TW-SYS-001\)/);
git('revert', '--no-edit', 'HEAD');
# a target branch with no model yet (a release MR into main before the first baseline): nothing to compare
git('checkout', '-q', '-b', 'empty-main');
git('rm', '-q', '-r', '--cached', 'model'); git('commit', '-q', '-m', 'main before any model');
my ($empty) = git('rev-parse', 'HEAD') =~ /([0-9a-f]{40})/;
git('checkout', '-q', '-f', 'develop'); git('branch', '-q', '-D', 'empty-main');
($out, $rc) = job('trace', CI_PIPELINE_SOURCE => 'merge_request_event', CI_MERGE_REQUEST_DIFF_BASE_SHA => $empty);
check('trace ratchet: a target with no model is not a baseline', $rc, 0);
like('trace ratchet: says so', $out, qr/the target branch has no model to compare with: reported only/);

# ---- delta, drop-package
($out, $rc) = job('delta');
like('delta: one drop, nothing to compare', $out, qr/first drop: nothing to compare/);
make_path("$repo/imports/v1.1");
copy("$tmp/d2/$_", "$repo/imports/v1.1/$_") for qw(tidewater.xmi tidewater.reqif MANIFEST.txt);
($out, $rc) = job('delta');
check('delta: two drops compared', $rc, 0);
like('delta: names the two drops', slurp("$repo/delta.txt"), qr/Hygrometer|added/i);
($out, $rc) = job('drop-package');
like('drop-package: skipped outside GitLab', $out, qr/no package registry here \(a local run\): skipped/);
($out, $rc) = job('status');
like('status: skipped without STATUS_TOKEN', $out, qr/STATUS_TOKEN is not set: nothing to export/);
unlink glob("$repo/imports/v1.1/*"); rmdir "$repo/imports/v1.1";

# ---- baseline: hash over `git ls-tree -r HEAD -- docs`, toolchain, release notes
my $hash = Digest::SHA::sha256_hex(git('ls-tree', '-r', 'HEAD', '--', 'docs'));
spew("$repo/CHANGELOG.md", "# Changelog\n\n## [baseline-0]\n\n- Drop 1 on develop.\n\n## [older]\n\n- before\n");
git('add', '-A'); git('commit', '-q', '-m', 'changelog');
git('tag', '-a', '-m', "baseline-0\n\nsha256=$hash (docs/ at x)", 'baseline-0');
($out, $rc) = job('baseline', CI_COMMIT_TAG => 'baseline-0', KIT_VERSION => 'agile-kit test', CI_RUNNER_DESCRIPTION => 'mbse-win-01');
check('baseline: the tag rebuilds and its hash matches', $rc, 0);
like('baseline: says so', $out, qr/baseline-0 rebuilds identically \(sha256=$hash\)/);
my $tc = slurp("$repo/toolchain.txt");
like('baseline: toolchain.txt names the kit, Perl, Git, runner', $tc, qr/^kit: agile-kit test\nperl v?5\.\d+\.\d+\ngit version \S+\nos: \w+\nrunner: mbse-win-01\nimage: none \(shell runner\)\ndocs sha256: $hash$/m);
git('tag', '-a', '-m', "baseline-9\n\nsha256=" . ('0' x 64), 'baseline-9');
($out, $rc) = job('baseline', CI_COMMIT_TAG => 'baseline-9');
check('baseline: a wrong hash fails', $rc, 1);
like('baseline: names the hash it found', $out, qr/docs hash $hash is not the one recorded in baseline-9/);
($out, $rc) = job('baseline', CI_COMMIT_TAG => 'baseline-0', KIT_VERSION => 'agile-kit test', SPRINT_START => '2026-10-05', SPRINT_WEEKS => '2');
like('baseline: release.env names the sprint the baseline closes', slurp("$repo/release.env"), qr/^RELEASE_MILESTONE=Sprint \d+\n$/);
($out, $rc) = job('publish-package', CI_COMMIT_TAG => 'baseline-0');
check('publish-package: the files, locally', join(' ', map { -f "$repo/package-upload/tidewater-model/baseline-0/$_" ? 1 : 0 } 'tidewater-model-baseline-0.tar.gz', 'vcrm.csv', 'toolchain.txt', 'SHA256SUMS'), '1 1 1 1');
like('publish-package: SHA256SUMS lists the archive', slurp("$repo/package-upload/tidewater-model/baseline-0/SHA256SUMS"), qr/^[0-9a-f]{64}  tidewater-model-baseline-0\.tar\.gz\n/);
like('publish-package: the archive holds model/ and docs/ at the tag', scalar(`tar tzf ${\ q_("$repo/package-upload/tidewater-model/baseline-0/tidewater-model-baseline-0.tar.gz")} 2>&1`), qr{^tidewater-model-baseline-0/docs/.*\n(?:.*\n)*tidewater-model-baseline-0/model/}m);
system('rm', '-rf', "$repo/package-upload");
($out, $rc) = job('publish-release', CI_COMMIT_TAG => 'baseline-0');
my $notes = slurp("$repo/release-notes.md");
like('publish-release: the tag\'s CHANGELOG section', $notes, qr/^- Drop 1 on develop\.\n/);
like('publish-release: then the toolchain', $notes, qr/## Toolchain\n\n```text\nbaseline: baseline-0\n/);
check('publish-release: not the other sections', ($notes =~ /before/ ? 1 : 0), 0);
{   # the scaffold's CHANGELOG, a baseline cut the way its comment says, and one written in the old way (under [Unreleased])
    my $cl0 = slurp("$repo/CHANGELOG.md");
    spew("$repo/CHANGELOG.md", "# Changelog\n\n<!-- When you cut a baseline ...\n    ## [baseline-1] -- 2027-03-19\n    - example\n-->\n\n## [Unreleased]\n\n### Added\n\n### Changed\n\n### Fixed\n\n### Prime drops merged\n\n"
        . "## [baseline-0] -- 2027-01-15\n\n### Added\n- Level tags (!2)\n\n### Changed\n\n### Fixed\n<!-- nothing yet -->\n\n### Prime drops merged\n- v1.0, 2026-10-02\n\n[Unreleased]: ../-/compare/baseline-0...develop\n[baseline-0]: ../-/tags/baseline-0\n");
    ($out, $rc) = job('publish-release', CI_COMMIT_TAG => 'baseline-0');
    my $n2 = slurp("$repo/release-notes.md");
    check('publish-release: exactly the tag\'s section; empty headings, HTML comments and link lines left out',
          ($n2 =~ /^(.*?)\n\n## (?:Verification|Toolchain)/s)[0], "### Added\n- Level tags (!2)\n\n### Prime drops merged\n- v1.0, 2026-10-02");
    spew("$repo/CHANGELOG.md", $cl0);
}

# ---- vcrm: the matrix from the model's verify relationships and verification/*.csv
($out, $rc) = job('vcrm');
check('vcrm: reports, never fails', $rc, 0);
like('vcrm: counts from drop 1 (no results yet)', $out, qr/VCRM: 30 requirements, 0 verified, 0 failed, \d+ not run, \d+ without a case/);
like('vcrm: the CSV has a row per requirement', slurp("$repo/vcrm.csv"), qr/^requirement,method,cases,status,verdicts,evidence\nTW-SEG-001,Inspection,TestStationObservations,not run,/);
spew("$repo/verification/results-prime.csv", "requirement,case,verdict,commit,environment,timestamp,signed_by\n"
     . "TW-SEG-001,TestStationObservations,passed,abc123,prime test lab,2027-07-01T10:00:00Z,\n"
     . "TW-SYS-013,TestStoreAndForward,failed,abc123,prime test lab,2027-09-28T10:00:00Z,\n");
($out, $rc) = job('vcrm');
like('vcrm: a passed and a failed verdict', $out, qr/VCRM: 30 requirements, 1 verified, 1 failed/);
like('vcrm: JUnit failure for the failed requirement', slurp("$repo/vcrm.xml"), qr/name="TW-SYS-013">\n    <failure message="TestStoreAndForward failed \(prime test lab/);
like('vcrm: metrics', slurp("$repo/vcrm.metrics"), qr/^vcrm_requirements 30\nvcrm_verified 1\n/);
like('vcrm: the HTML page', slurp("$repo/vcrm.html"), qr/<tr class="failed"><td>TW-SYS-013/);
unlink "$repo/verification/results-prime.csv"; rmdir "$repo/verification";
($out, $rc) = job('sil-regression');
like('sil-regression: without SIL_CMD it says what to set', $out, qr/sil: no harness configured \(set SIL_CMD/);

# ---- intake: a delivery checked against its MANIFEST
{ my ($o4, $r4) = sh(q_($^X) . " " . q_("$ROOT/sim/tidewater-v1.pl") . " --drop 4 " . q_("$tmp/d4")); die $o4 if $r4; }
($out, $rc) = job('intake', DROP_VERSION => 'v1.3', INTAKE_DROP_DIR => "$tmp/d4");
check('intake: a complete drop is accepted', $rc, 0);
like('intake: every file checked, Jenkins provenance kept', slurp("$repo/intake.txt"), qr/^Built by: Jenkins \S+ \(build \d+\)\n(?:.*\n)*ok       tidewater\.xmi  sha256 [0-9a-f]{64}\n(?:.*\n)*ok       results\.xml  sha256 [0-9a-f]{64}\nACCEPTED for import/m);
like('intake: without INTAKE_TOKEN it says to open the issue by hand', $out, qr/INTAKE_TOKEN is not set: open the Prime Drop issue by hand/);
spew("$tmp/d4/tidewater.xmi", slurp("$tmp/d4/tidewater.xmi") . "<!-- edited in transit -->\n");
($out, $rc) = job('intake', DROP_VERSION => 'v1.3', INTAKE_DROP_DIR => "$tmp/d4");
check('intake: an altered file rejects the drop', $rc, 1);
like('intake: names the file and both hashes', $out, qr/MISMATCH tidewater\.xmi  manifest [0-9a-f]{64}, received [0-9a-f]{64}\n(?:.*\n)*REJECTED: 1 file\(s\) missing or altered/);
($out, $rc) = job('intake', DROP_VERSION => '');
like('intake: needs DROP_VERSION', $out, qr/intake needs DROP_VERSION/);
{ my ($o5, $r5) = sh(q_($^X) . " " . q_("$ROOT/sim/tidewater-v1.pl") . " --drop 4 " . q_("$tmp/reg/prime-drop/v1.3")); die $o5 if $r5; }
system('rm', '-rf', "$repo/intake");
($out, $rc) = job('intake', DROP_VERSION => 'v1.3', GITLAB_LOCAL_REGISTRY => "$tmp/reg");
check('intake: from the emulator\'s package registry (GITLAB_LOCAL_REGISTRY, no HTTP)', $rc, 0);
like('intake: the registry copy is checked like a download', slurp("$repo/intake.txt"), qr/ok       tidewater\.xmi  sha256 [0-9a-f]{64}\n(?:.*\n)*ACCEPTED for import/m);
($out, $rc) = job('intake', DROP_VERSION => 'v9.9', GITLAB_LOCAL_REGISTRY => "$tmp/reg");
like('intake: a version not in the registry', "$rc $out", qr/^1 .*prime-drop v9\.9: no MANIFEST\.txt/s);
system('rm', '-rf', "$repo/intake");

# ---- pages
($out, $rc) = job('pages');
check('pages: builds the site', $rc, 0);
check('pages: index, docs, burn-down', join(' ', map { -e "$repo/public/$_" ? 1 : 0 } 'index.html', 'docs/Nouns.md', 'todo-burndown.csv', 'trace.txt'), '1 1 1 1');
like('pages: one burn-down point per day', slurp("$repo/public/todo-burndown.csv"), qr/^date,todo_lines\n\d{4}-\d\d-\d\d,\d+\n/);

# ---- complexity: the graph computations, on small models
{ local $ENV{KIT} = $ROOT; require $JOB; }
my $g = CIJob::model_graph({ 'model/a.sysml' => "package A {\n  private import B::*;\n  part def P { part q : Q; }\n  satisfy R1 by P;\n}\n",
                      'model/b.sysml' => "package B {\n  part def Q { attribute x : T; }\n  requirement R1 { }\n}\n",
                      'model/gov/c.sysml' => "// Government-owned\npackage C {\n  private import A::*;\n  attribute def T;\n  dependency from T to P;\n}\n" });
check('graph: edges from imports and resolved names', join(' ', map { my $a = $_; map { "$a>$_" } sort keys %{ $g->{edges}{$a} } } sort keys %{ $g->{edges} }), 'A>B B>C C>A');
check('graph: a cycle of three is one strongly connected group', join(' ', map { join('', @$_) } @{ CIJob::sccs($g->{edges}, qw(A B C)) }), 'ABC');
check('graph: relationship ends per part def', join(' ', map { "$_=$g->{rel}{$_}" } sort keys %{ $g->{rel} }), 'P=2 Q=1');
my $cx = CIJob::complexity_of({ 'model/a.sysml' => "package A {\n  private import B::*;\n}\n", 'model/b.sysml' => "package B {\n  part def Q;\n}\n",
                         'model/gov/c.sysml' => "// Government-owned\npackage C {\n  private import B::*;\n}\n" }, { layers => 'A; B, C' });
check('complexity: fan-in, fan-out, an upward dependency (A is below B)', join(' ', $cx->{fan_in}{B}, $cx->{fan_out}{A}, $cx->{metrics}{upward_imports}, $cx->{metrics}{cycles}), '2 1 1 0');
check('complexity: a wildcard import in model/gov is a violation', scalar(grep { $_->[2] =~ /^wildcard import B::\* in government file/ } @{ $cx->{violations} }), 1);
my %m0 = (max_fan_out => 0, max_relationships_per_part => 0, cycles => 0, upward_imports => 0, duplicates => 0);
check('ratchet: a new project\'s first part with a sub-part (relationships 0 -> 1) passes',
      join(' ', CIJob::complexity_worse(\%m0, { %m0, max_relationships_per_part => 1, max_fan_out => 3 }, {})), '');
check('ratchet: sizes ratchet only above their limits (fan-out 7 -> 8, relationships 10 -> 11)',
      join(' ', CIJob::complexity_worse({ %m0, max_fan_out => 7, max_relationships_per_part => 10 }, { %m0, max_fan_out => 8, max_relationships_per_part => 11 }, {})), 'max_fan_out max_relationships_per_part');
check('ratchet: the limits come from sysml.conf',
      join(' ', CIJob::complexity_worse({ %m0, max_fan_out => 2 }, { %m0, max_fan_out => 3 }, { max_package_fan_out => 2 })), 'max_fan_out');
check('ratchet: a new cycle or upward import always fails',
      join(' ', CIJob::complexity_worse(\%m0, { %m0, cycles => 1, upward_imports => 1 }, {})), 'cycles upward_imports');

# ---- the template: every job's script is `perl ci/job.pl NAME`, and the YAML loads
my $ci = GitLabCI::load("$ROOT/tools/gitlab/templates/gitlab-ci.yml");
my @jobs = grep { !/^\./ } sort keys %{ $ci->{jobs} };
my @odd = grep { my $s = $ci->{jobs}{$_}{script} // []; !(@$s == 1 && $s->[0] eq "perl ci/job.pl $_") } @jobs;
check('template: every job runs perl ci/job.pl NAME', "@odd", '');
check('template: 20 jobs', scalar(@jobs), 20);
my $plan = GitLabCI::plan($ci, vars => { CI_PIPELINE_SOURCE => 'schedule', CI_COMMIT_BRANCH => 'develop', CI_DEFAULT_BRANCH => 'develop' });
check('weekly schedule: only status', join(' ', map { $_->{name} } @{ $plan->{jobs} }), 'status');
$plan = GitLabCI::plan($ci, vars => { CI_PIPELINE_SOURCE => 'schedule', CI_COMMIT_BRANCH => 'develop', CI_DEFAULT_BRANCH => 'develop', FULL => '1' });
check('nightly schedule (FULL=1): the checks and pages', join(' ', map { $_->{name} } @{ $plan->{jobs} }), 'grammar lint outline todo secrets complexity trace vcrm recipe docs pages');
$plan = GitLabCI::plan($ci, vars => { CI_PIPELINE_SOURCE => 'push', CI_COMMIT_BRANCH => 'develop', CI_DEFAULT_BRANCH => 'develop' });
check('SIL and HIL are disabled by default', (grep { $_->{name} =~ /^(sil|hil)/ } @{ $plan->{jobs} }) ? 1 : 0, 0);
$plan = GitLabCI::plan($ci, vars => { CI_PIPELINE_SOURCE => 'push', CI_COMMIT_BRANCH => 'develop', CI_DEFAULT_BRANCH => 'develop', HIL_ENABLED => 'true' });
check('HIL_ENABLED=true: hil-test is a manual job', join(' ', map { "$_->{name}:$_->{when}" } grep { $_->{name} eq 'hil-test' } @{ $plan->{jobs} }), 'hil-test:manual');
$plan = GitLabCI::plan($ci, vars => { CI_PIPELINE_SOURCE => 'trigger', CI_COMMIT_BRANCH => 'develop', CI_DEFAULT_BRANCH => 'develop', DROP_VERSION => 'v1.3' });
check('a delivery trigger runs only intake', join(' ', map { $_->{name} } @{ $plan->{jobs} }), 'intake');
check('the Secret-Detection include is conditional', (grep { /conditional/ && /Secret-Detection/ } @{ $ci->{includes} }) ? 1 : 0, 1);

print "1..$n\n";
print $bad ? "# $bad of $n FAILED\n" : "# all $n passed\n";
exit($bad ? 1 : 0);
