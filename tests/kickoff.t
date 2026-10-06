#!/usr/bin/perl
# perl tests/kickoff.t -- tools/gitlab/kickoff.pl (doctor, scaffold, start) and bin/release.pl --profile mbse.
# Under Git for Windows' Perl (every process start is slow) the end-to-end runs are skipped unless KICKOFF_FULL=1.
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use File::Temp qw(tempdir);
use File::Path qw(make_path);
use File::Copy qw(copy);
use Cwd qw(abs_path getcwd);

my ($n, $bad) = (0, 0);
sub check_ { my ($name, $got, $want) = @_; $n++;
    if (defined $got && $got eq $want) { print "ok $n - $name\n" }
    else { $bad++; print "not ok $n - $name\n#   got:  " . ($got // 'undef') . "\n#   want: $want\n" } }
sub has { my ($name, $text, @res) = @_; for my $re (@res) { check_("$name: $re", ($text =~ $re ? 1 : 0), 1) } }
sub hasnt { my ($name, $text, @res) = @_; for my $re (@res) { check_("$name: not $re", ($text =~ $re ? 0 : 1), 1) } }
sub skip_ { my ($name, $why) = @_; $n++; print "ok $n - $name # skip $why\n" }
sub slurp { my $f = shift; open my $fh, '<:raw', $f or return undef; local $/; my $t = <$fh>; close $fh; $t }
sub spew { my ($f, $t) = @_; open my $fh, '>:raw', $f or die "$f: $!"; print $fh $t; close $fh }
sub run {                                       # run(cmd...) -> (output, exit) with stdout+stderr, in the current dir
    my @cmd = @_;
    my $tmp = File::Temp->new; my $tf = $tmp->filename;
    open my $o, '>&', \*STDOUT or die; open my $e, '>&', \*STDERR or die;
    open STDOUT, '>', $tf or die; open STDERR, '>&', \*STDOUT or die;
    my $rc = system { $cmd[0] } @cmd;
    open STDOUT, '>&', $o or die; open STDERR, '>&', $e or die;
    return (slurp($tf) // '', $rc >> 8);
}

my $ROOT = abs_path("$FindBin::Bin/..");
my $K = "$ROOT/tools/gitlab/kickoff.pl";
my $WIN = $^O =~ /^(MSWin32|cygwin|msys)$/;
my $FULL = !$WIN || $ENV{KICKOFF_FULL};
my $T = tempdir(CLEANUP => 1);
my $home = "$T/home"; make_path($home);
local $ENV{HOME} = $home;
local $ENV{GIT_CONFIG_GLOBAL} = "$home/gitconfig";       # the tests never touch the real ~/.gitconfig
local $ENV{GIT_CONFIG_NOSYSTEM} = 1;
delete local $ENV{GITLAB_URL};
spew("$home/gitconfig", '');

# ---------------------------------------------------------------- help and usage
my ($out, $rc) = run($^X, $K, 'help');
check_('help exits 0', $rc, 0);
has('help', $out, qr/kickoff\.pl doctor/, qr/kickoff\.pl scaffold DIR/, qr/kickoff\.pl start/);
($out, $rc) = run($^X, $K, 'bogus');
check_('an unknown command is a usage error (exit 2)', $rc, 2);

# ---------------------------------------------------------------- doctor
($out, $rc) = run($^X, $K, 'doctor', '--quick', '--local', "$T/gl");
check_('doctor fails without a git identity (exit 1)', $rc, 1);
my @lines = grep { !/^      fix: / } split /\n/, $out;
check_('every doctor line is STATUS + text, then the summary', scalar(grep { !/^(PASS|WARN|FAIL|SKIP) +\S/ && !/^doctor: \d+ pass, \d+ warn, \d+ fail, \d+ skipped$/ } @lines), 0);
has('doctor', $out, qr/^FAIL  git user\.email is not set.*\n      fix: git config --global user\.email /m,
    qr/^WARN  git pull\.ff is not set, recommended only/m, qr/^SKIP  the kit's self-test \(--quick\)$/m,
    qr/^FAIL  the kit's Vim setup is not sourced/m, qr/^PASS  perl core modules the kit uses/m, qr/^PASS  GitLab: the local emulator/m);
check_('doctor --quick changes nothing', slurp("$home/gitconfig"), '');
spew("$home/gitconfig", "[user]\n\tname = Bob\n\temail = bob\@example.invalid\n");
spew("$home/.vimrc", "syntax on\nsource $ROOT/vim/scrum.vim\n");
($out, $rc) = run($^X, $K, 'doctor', '--quick', '--fix', '--local', "$T/gl");
has('doctor --fix', $out, qr/^running: git config --global pull\.ff only$/m, qr/^PASS  git merge\.conflictstyle = diff3 \(set by --fix\)$/m);
my ($v) = run('git', 'config', '--global', '--get', 'core.autocrlf');
check_('--fix set core.autocrlf in the (test) global config', $v =~ /^false/ ? 1 : 0, 1);
($out, $rc) = run($^X, $K, 'doctor', '--quick', '--local', "$T/gl");
hasnt('doctor after --fix', $out, qr/^WARN  git (init\.defaultBranch|core\.autocrlf|pull\.ff|merge\.conflictstyle)/m);
($v) = run('git', 'config', '--global', '--get', 'user.name');
check_('--fix never touches the name', $v, "Bob\n");
if ($FULL) {
    ($out, $rc) = run($^X, $K, 'doctor', '--local', "$T/gl");
    has('doctor with the self-test', $out, qr/^PASS  kit self-test tests\/prelude\.t: # all \d+ passed$/m,
        qr/^PASS  converter and grammar check: xmi2sysml: .*self-check ok$/m);
} else { skip_('doctor self-test', 'Git for Windows Perl (KICKOFF_FULL=1 to run)') }

# ---------------------------------------------------------------- scaffold
my $cwd = getcwd();
chdir $T or die;
($out, $rc) = run($^X, $K, 'scaffold', 'radar', '--project', 'acme/radar-model', '--title', 'Radar', '--noun-root', 'RadarSystem', '--levels', 'L1Radar, L2Segment,L3Unit');
check_('scaffold exits 0', $rc, 0);
for my $f ('.gitlab-ci.yml', 'ci/job.pl', 'CODEOWNERS', '.gitignore', 'README.md', 'CHANGELOG.md', '.gitlab/project.conf',
           '.gitlab/issue_templates/Story.md', '.gitlab/merge_request_templates/Default.md', 'sysml.conf', 'docs/adr/0001-record-decisions.md',
           'verification/results.csv', 'model/library/conventions/Conventions.sysml', '.ci/outline-max', 'docs/README.md', 'docs/onboarding.md',
           'docs/conventions/naming.md', 'docs/conventions/markings.md', 'docs/conventions/review-checklist.md',
           'docs/model-exchange-agreement.md', 'docs/adr/0002-prime-boundary.md', 'docs/adr/0003-results-schema.md',
           'docs/memos/templates/progress-memo.md', 'docs/memos/templates/README.md') {
    check_("scaffold made $f", -f "radar/$f" ? 1 : 0, 1);
}
check_('no wiki, prime or project.conf at the top', (grep { -e "radar/$_" } qw(wiki prime project.conf release-notes.md memos)) ? 0 : 1, 1);
has('scaffold substitutes the project', slurp('radar/.gitlab/project.conf'), qr/^path = acme\/radar-model\b/m);
hasnt('scaffold substitutes the project', slurp('radar/.gitlab/project.conf'), qr/tidewater\/model/);
has('README heading', slurp('radar/README.md'), qr/^# Radar\b/m);
has('sysml.conf', slurp('radar/sysml.conf'), qr/^title\s+= Radar$/m, qr/^noun_root\s+= RadarSystem$/m, qr/^# verb_root /m);
has('levels', slurp('radar/sysml.conf'), qr/^level_tags\s+= L1Radar, L2Segment, L3Unit$/m, qr/^layers\s+= Conventions$/m);
has('Conventions', slurp('radar/model/library/conventions/Conventions.sysml') // '', qr{^// Government-owned}, qr/metadata def L1Radar \{/, qr/metadata def L3Unit \{/);
check_('no model/gov', -e 'radar/model/gov' ? 1 : 0, 0);
has('scaffold names where to rename the levels', $out, qr{level tags: L1Radar, L2Segment, L3Unit -- to rename them, edit model/library/conventions/Conventions\.sysml});
{   # every relative link in the scaffolded docs points at a file the scaffold made
    my @bad;
    for my $f (map { s{^radar/}{}r } grep { /\.md$/ } split /\n/, `find radar/docs -type f`) {
        (my $dir = $f) =~ s{/[^/]+$}{};
        for my $l ((slurp("radar/$f") // q()) =~ /\]\(([^)#:]+)(?:#[^)]*)?\)/g) {
            my $p = "radar/$dir/$l"; 1 while $p =~ s{/[^/.][^/]*/\.\./}{/}; $p =~ s{/\./}{/}g; $p =~ s{/$}{};
            push @bad, "$f -> $l" unless -e $p;
        }
    }
    check_(q(the docs links all resolve), join(q(, ), @bad), q());
}
check_('results.csv header', slurp('radar/verification/results.csv'), "requirement,case,verdict,commit,environment,timestamp,signed_by\n");
{   my $cl = slurp('radar/CHANGELOG.md') // '';
    check_('CHANGELOG: only the [Unreleased] section', join(',', $cl =~ /^## \[([^\]]+)\]/mg), 'Unreleased');
    has('CHANGELOG', $cl, qr/^# Changelog$/m, qr/the Radar model/, qr/^    ## \[baseline-1\] -- /m);
    hasnt('CHANGELOG', $cl, qr/^\[baseline-1\]:/m);
    has('CHANGELOG: the instructions sit above [Unreleased], outside every section', $cl, qr/-->\n\n## \[Unreleased\]\n\n### Added\n\n### Changed\n\n### Fixed\n\n### Prime drops merged\n\n\[Unreleased\]:/);
    has('CHANGELOG: says to delete the empty headings', $cl, qr/delete the headings left empty under it/);
    # cut baseline-1 by renaming [Unreleased] (empty headings left in by mistake), then publish its notes as the release job does
    (my $cut = $cl) =~ s/^## \[Unreleased\]\n/## [Unreleased]\n\n### Added\n\n## [baseline-1] -- 2027-03-19\n/m;
    $cut =~ s/^(## \[baseline-1\][^\n]*\n\n### Added\n)/$1- The structure from drop v1.0 (!3)\n/m;
    open my $w, '>:raw', 'radar/CHANGELOG.md' or die; print $w $cut; close $w;
    my $kv = (slurp('radar/.kit-version') // '') =~ s/\s+//gr;
    local $ENV{KIT} = $ROOT; local $ENV{KIT_VERSION} = $kv; local $ENV{CI_COMMIT_TAG} = 'baseline-1';
    my $o = `cd radar && "$^X" ci/job.pl publish-release 2>&1`;
    check_('release notes from the scaffold\'s CHANGELOG: the baseline section only', ((slurp('radar/release-notes.md') // $o) =~ /^(.*?)(?:\n\n## (?:Verification|Toolchain)|\n\z)/s)[0] // '',
           "### Added\n- The structure from drop v1.0 (!3)");
    open $w, '>:raw', 'radar/CHANGELOG.md' or die; print $w $cl; close $w;
    unlink 'radar/release-notes.md';
}
($v) = run('git', '-C', 'radar', 'log', '--oneline');
check_('one commit', scalar(split /\n/, $v), 1);
($v) = run('git', '-C', 'radar', 'rev-parse', '--abbrev-ref', 'HEAD');
check_('on main', $v, "main\n");
($v) = run('git', '-C', 'radar', 'status', '--porcelain');
check_('nothing left uncommitted', $v, '');
($out, $rc) = run($^X, $K, 'scaffold', 'radar');
check_('scaffold refuses a non-empty folder', ($rc != 0 && $out =~ /is not empty/) ? 1 : 0, 1);
($out, $rc) = run($^X, $K, 'scaffold', 'bad2', '--levels', 'L1 bad');
check_('--levels checks its names (exit 2)', ($rc == 2 && $out =~ /comma list of names/) ? 1 : 0, 1);
check_('without --layout-map: an example, not a map', (-f 'radar/.ci/layout.map.example' && !-e 'radar/.ci/layout.map') ? 1 : 0, 1);
has('the example', slurp('radar/.ci/layout.map.example') // '', qr/^# Stations\s+= physical\/stations\/$/m, qr/BEFORE the first\s*\n# prime drop/);
($out, $rc) = run($^X, $K, 'scaffold', 'mapped', '--layout-map', "$ROOT/examples/tidewater-v1/layout.map");
check_('scaffold --layout-map exits 0', $rc, 0);
has('.ci/layout.map', slurp('mapped/.ci/layout.map') // '', qr/^# \.ci\/layout\.map -- where each top-level package/, qr/^Stations\s+= physical\/stations\/$/m);
check_('with --layout-map: no example', -e 'mapped/.ci/layout.map.example' ? 1 : 0, 0);
($out, $rc) = run($^X, $K, 'scaffold', 'nomap', '--layout-map', "$T/missing.map");
check_('--layout-map checks the file (exit 2)', ($rc == 2 && $out =~ /no layout map/) ? 1 : 0, 1);
($out, $rc) = run($^X, $K, 'scaffold', 'bad', '--project', 'noslash');
check_('scaffold checks --project', ($rc != 0 && $out =~ /GROUP\/NAME/) ? 1 : 0, 1);
{   # the scaffold passes its own first jobs
    local $ENV{KIT} = $ROOT;
    chdir "$T/radar" or die;
    my ($g, $grc) = run($^X, 'ci/job.pl', 'grammar');
    check_('ci/job.pl grammar passes on the scaffold', $grc, 0);
    my ($l, $lrc) = run($^X, 'ci/job.pl', 'lint');
    check_('ci/job.pl lint passes on the scaffold', $lrc, 0);
    my ($ol, $orc) = run($^X, 'ci/job.pl', 'outline');
    check_('ci/job.pl outline passes on the scaffold (the ratchet starts at the skeleton)', $orc, 0);
    chdir $T or die;
}

# ---------------------------------------------------------------- start: the plan, then the run
($out, $rc) = run($^X, $K, 'start', '--local', 'gl0', '--dir', 'plan-model');
check_('start without --yes exits 0', $rc, 0);
check_('start without --yes shows 12 steps', scalar(() = $out =~ /^== step \d+:/mg), 12);
check_('start without --yes makes nothing', (grep { -e "$T/$_" } qw(gl0 plan-model journal)) ? 0 : 1, 1);
has('the plan', $out, qr/setup model\/\.gitlab\/project\.conf|setup \S*project\.conf/, qr/\(a copy: without \[schedules\], KIT = this kit\)/, qr/flow init/, qr/daily\.pl init journal/);
($out, $rc) = run($^X, $K, 'start', '--yes');
check_('start needs a GitLab', ($rc != 0 && $out =~ /which GitLab/) ? 1 : 0, 1);

if ($FULL) {
    my $drop = "$T/drop";
    my ($d, $drc) = run($^X, "$ROOT/sim/tidewater-v1.pl", '--drop', '1', $drop);
    check_('drop 1 generated', $drc, 0);
    ($out, $rc) = run($^X, $K, 'start', '--yes', '--local', 'gl', '--drop', $drop, '--version', 'v1.0', '--layout-map', "$ROOT/examples/tidewater-v1/layout.map");
    check_('start --yes exits 0', $rc, 0);
    print map { "#   $_\n" } split /\n/, $out if $rc;
    has('start --yes', $out, qr/^kickoff: week zero is set up\.$/m, qr/develop is ready \(from main\)/, qr/schedule Nightly full check/,
        qr/vendor\/prime: imported v1\.0/, qr/^   \| added Tom$/m, qr/^   \| #5 Working agreements/m);
    my ($heads) = run('git', 'ls-remote', '--heads', "$T/gl/repos/tidewater/model.git");
    has('branches on the server', $heads, qr{refs/heads/main$}m, qr{refs/heads/develop$}m, qr{refs/heads/vendor/prime$}m);
    my $state = slurp("$T/gl/gitlab.json") // '';
    has('the emulator holds', $state, qr/"Working agreements: Definition of Ready and Done"/, qr/"Nightly full check"/, qr/"Definition of Done"/,
        qr/"value"\s*:\s*"\Q$ROOT\E"/);
    my $roster = slurp("$T/journal/roster.txt") // '';
    check_('roster: the three members', scalar(() = $roster =~ /^\s*(Jim|Bob|Tom)\s+\| /mg), 3);
    my ($pl) = run($^X, "$ROOT/bin/gitlab.pl", '--local', "$T/gl", '--project', 'tidewater/model', 'pipeline', 'list');
    has('the first pipelines', $pl, qr/^#\d+\s+success\s+push\s+main\b/m, qr/^#\d+\s+success\s+push\s+develop\b/m, qr/^#\d+\s+success\s+push\s+vendor\/prime\b/m);
    hasnt('the first pipelines', $pl, qr/^#\d+\s+failed\s+push\s+(main|develop)\b/m);
    my ($lg) = run('git', '-C', "$T/model", 'log', '--format=%s', 'origin/feature/drop-v1.0');
    has('the drop branch', $lg, qr/^Regenerate docs for prime drop v1\.0$/m);
    check_('the scaffold committed its generated docs', -f "$T/model/docs/Nouns.md" ? 1 : 0, 1);
    my ($ls) = run('git', '-C', "$T/model", 'ls-tree', '-r', '--name-only', 'origin/feature/drop-v1.0');
    has('the first drop followed --layout-map', $ls, qr{^model/physical/stations/Stations\.sysml$}m,
        qr{^model/requirements/system/System_Requirements\.sysml$}m, qr{^\.ci/layout\.map$}m);
    check_('journal: scrum.conf', -f "$T/journal/scrum.conf" ? 1 : 0, 1);
    ($out, $rc) = run($^X, $K, 'start', '--yes', '--local', 'gl', '--from', '5', '--no-wiki', '--no-issues');
    check_('start --yes --from 5 resumes cleanly', $rc, 0);
    has('the resume', $out, qr/skipped: before --from 5/, qr/skipped: model already exists/, qr/skipped: journal already holds a journal/);
} else { skip_('start --yes end to end', 'Git for Windows Perl (KICKOFF_FULL=1 to run)') }

# ---------------------------------------------------------------- release.pl --profile mbse
chdir $ROOT or die;
($out, $rc) = run($^X, 'bin/release.pl', '--profile', 'mbse', '--list', '--worktree');
check_('release --profile mbse --list exits 0', $rc, 0);
my %in = map { $_ => 1 } split /\n/, $out;
check_("the mbse profile has $_", $in{$_} ? 1 : 0, 1) for qw(agile.pl bin/gitlab.pl bin/daily.pl lib/GitLab.pm tools/gitlab/kickoff.pl
    tools/sysml/model.pl tools/idef0/idef0.pl tools/gitlab/templates/ci/job.pl vim/scrum.vim vim/doc/agile.txt examples/tidewater-v1/tidewater.xmi
    sim/tidewater-v1.pl tests/prelude.t tests/ledger.t docs/GITLAB.html docs/img/cover-art.jpg);
check_('the mbse profile leaves out the rest', (grep { m{^(data|drills|sim/halberd|tests/scrum|docs/HALBERD)} } keys %in) ? 0 : 1, 1);
($out, $rc) = run($^X, 'bin/release.pl', '--profile', 'nope', '--list');
check_('an unknown profile is a usage error', ($rc == 2 && $out =~ /no profile 'nope'/) ? 1 : 0, 1);
($out, $rc) = run($^X, 'bin/release.pl', '--list');
check_('--list needs --profile', $rc, 2);
if ($FULL) {                                    # the slim tree on its own: doctor's self-test and scaffold work from it
    my $slim = "$T/slim/agile";
    for my $f (sort keys %in) { (my $d = "$slim/$f") =~ s{/[^/]+$}{}; make_path($d); copy("$ROOT/$f", "$slim/$f") or die "copy $f: $!" }
    spew("$home/.vimrc", "source $slim/vim/scrum.vim\n");
    chdir "$T/slim" or die;
    ($out, $rc) = run($^X, "$slim/tools/gitlab/kickoff.pl", 'doctor', '--local', "$T/gl2");
    check_('doctor from the slim tree passes', $rc, 0);
    print map { "#   $_\n" } split /\n/, $out if $rc;
    has('doctor from the slim tree', $out, qr/^PASS  kit self-test tests\/ledger\.t/m, qr/^PASS  converter and grammar check/m);
    ($out, $rc) = run($^X, "$slim/tools/gitlab/kickoff.pl", 'scaffold', 'm');
    check_('scaffold from the slim tree', $rc, 0);
} else { skip_('the slim tree on its own', 'Git for Windows Perl (KICKOFF_FULL=1 to run)') }
chdir $cwd;

print "1..$n\n";
print $bad ? "# $bad of $n FAILED\n" : "# all $n passed\n";
exit($bad ? 1 : 0);
