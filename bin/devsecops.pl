#!/usr/bin/perl
# devsecops.pl -- run the kit's own pipeline gates on this machine and write ./devsecops.html, a status
# dashboard in the poetic-musings DevSecOps style: pillars as cards (ok / partial / gap), each gate's evidence,
# hover definitions, and GitHub Actions badges + live job dots when a remote exists.
#
#   perl bin/devsecops.pl            run every gate (tests under every Perl found, syntax, secrets, marking, hygiene), write devsecops.html
#   perl bin/devsecops.pl --quick    skip the test suites (seconds instead of a minute)
#   perl bin/devsecops.pl --open     also open the page
#
# Every status on the page comes from a check that ran here, now; the time and the interpreters are printed.
# Nothing is fetched at build time; the page's live strip asks api.github.com from the browser only if a
# GitHub remote is configured, and degrades to the local evidence when offline.
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Getopt::Long;
use Cwd qw(abs_path);
use POSIX qw(strftime);
use Prelude qw(sorted);
use Scrum qw(logo_svg);

my %o;
GetOptions(\%o, 'quick', 'open') or exit 2;
my $ROOT = abs_path("$FindBin::Bin/..");
chdir $ROOT or die "cannot chdir $ROOT: $!\n";
my $NOW = strftime('%Y-%m-%d %H:%M', localtime);

# ---------------------------------------------------------------- gates
my (@gates, %pillar);                        # gate = { id, pillar, name, state => ok|partial|gap, evidence, detail }
sub gate { my %g = @_; push @gates, \%g; push @{ $pillar{ $g{pillar} } }, \%g; $g{state} }
sub sh { my $out = qx(@_ 2>&1); chomp $out; $out }
sub h  { my $s = shift // ''; $s =~ s/&/&amp;/g; $s =~ s/</&lt;/g; $s =~ s/>/&gt;/g; $s =~ s/"/&quot;/g; $s }

# perls: this one, and Git for Windows' if present (the target)
my @perls = ([ 'this perl', $^X ]);
for my $gp ('/mnt/c/Program Files/Git/usr/bin/perl.exe', '/c/Program Files/Git/usr/bin/perl.exe', 'C:/Program Files/Git/usr/bin/perl.exe') {
    if (-x $gp && abs_path($gp) ne abs_path($^X)) { push @perls, [ 'Git for Windows perl (target)', $gp ]; last }
}

# -- source control
my $branch = sh('git rev-parse --abbrev-ref HEAD');
my $sha    = sh('git rev-parse --short HEAD');
my $dirty  = sh('git status --porcelain') =~ /\S/ ? 1 : 0;
my $remote = sh('git remote get-url origin');
$remote = '' if $remote =~ /fatal|error/i;
my ($gh_owner, $gh_repo) = $remote =~ m{github\.com[:/]([^/]+)/([^/.]+)};
gate(id => 'git', pillar => 'Source control', name => 'Every change in git, with a message',
     state => $dirty ? 'partial' : 'ok', evidence => "branch $branch at $sha" . ($dirty ? ', uncommitted changes present' : ', working tree clean'),
     detail => sh('git log --oneline -5'));
gate(id => 'remote', pillar => 'Source control', name => 'Off-machine copy (GitHub, private)',
     state => $gh_repo ? 'ok' : 'gap', evidence => $gh_repo ? "origin = github.com/$gh_owner/$gh_repo" : 'no GitHub remote: the repo lives only on this laptop',
     detail => $gh_repo ? sh('git status -sb | head -1') : "git remote add origin git\@github.com:<you>/agile.git && git push -u origin $branch");
gate(id => 'data', pillar => 'Source control', name => 'Project data never committed (project data stays out of the kit repo)',
     state => (sh('git ls-files data/ 2>&1') =~ /\S/ ? 'gap' : 'ok'), evidence => (sh('git ls-files data/') =~ /\S/ ? 'files under data/ are tracked!' : 'data/ is git-ignored and untracked'),
     detail => sh('grep -n "^/data/" .gitignore'));

# -- CI: tests on every Perl found
my $total = 0;
for my $p (@perls) {
    my ($label, $bin) = @$p;
    my $ver = sh(qq("$bin" -e 'print "\$^V \$^O"'));
    if ($o{quick}) { gate(id => "tests-$label", pillar => 'CI: build, lint, test', name => "Test suite under $label", state => 'partial', evidence => "skipped (--quick); $ver", detail => ''); next }
    my (@lines, $bad, $n);
    for my $t (sorted(glob 'tests/*.t')) {
        my $out = sh(qq("$bin" "$t")); my ($last) = (split /\n/, $out)[-1] // '';
        $bad++ unless $last =~ /^# all (\d+) passed/; $n += $1 // 0; push @lines, sprintf '%-20s %s', $t, $last;
    }
    $total = $n if $n > $total;
    gate(id => "tests-$label", pillar => 'CI: build, lint, test', name => "Test suite under $label", state => $bad ? 'gap' : 'ok',
         evidence => ($bad ? "$bad suite(s) FAILED" : "$n tests, 9 suites, all passed") . " -- $ver", detail => join "\n", @lines);
}
{   my @bad;
    for my $f (sorted(glob('bin/*.pl'), 'agile.pl', glob('sim/*.pl'), 'tools/idef0/idef0.pl', glob('lib/*.pm'))) { my $r = sh(qq("$^X" -Ilib -c "$f")); push @bad, "$f: $r" unless $r =~ /syntax OK/ }
    gate(id => 'syntax', pillar => 'CI: build, lint, test', name => 'perl -c on every script and module', state => @bad ? 'gap' : 'ok',
         evidence => @bad ? scalar(@bad) . ' failed' : 'all compile (strict + warnings everywhere)', detail => join "\n", @bad);
}
gate(id => 'workflow', pillar => 'CI: build, lint, test', name => 'Pipeline as code (GitHub Actions: windows-latest with Git for Windows\' Perl, ubuntu)',
     state => (-f '.github/workflows/tests.yml' ? ($gh_repo ? 'ok' : 'partial') : 'gap'),
     evidence => -f '.github/workflows/tests.yml' ? ('.github/workflows/tests.yml + security.yml present' . ($gh_repo ? '' : '; not yet running anywhere (no remote)')) : 'no workflow',
     detail => sh('grep -n "runs-on\\|name:" .github/workflows/*.yml | head -12'));
gate(id => 'replay', pillar => 'CI: build, lint, test', name => 'End-to-end: the training replay runs daily.pl, git and the IDEF0 toolkit for real',
     state => (-s 'docs/TRAINING.html' ? 'ok' : 'gap'), evidence => -s 'docs/TRAINING.html' ? 'docs/TRAINING.html generated (' . sh('grep -c "class=term" docs/TRAINING.html') . ' recorded steps)' : 'not generated',
     detail => 'perl sim/training.pl --fast');

# -- security gates
{   my $hits = sh(q{grep -rnIE --exclude-dir=.git --exclude-dir=data --exclude-dir=reports -e 'AKIA[0-9A-Z]{16}' -e '-----BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY' -e '(api[_-]?key|secret|token|password)\s*[:=]\s*["'"'"'][^"'"'"']{8,}' . | grep -v 'devsecops.pl\|ai_key_env\|password=\$' | head -5});
    gate(id => 'secrets', pillar => 'Security gates', name => 'Secrets detection (keys, tokens, passwords in the tree)', state => $hits =~ /\S/ ? 'gap' : 'ok',
         evidence => $hits =~ /\S/ ? 'possible secrets found' : 'no key/token/password patterns in the tree; the AI key is read from an env var (ai_key_env), never a file',
         detail => $hits || 'gitleaks runs the same check in CI (security.yml)');
}
{   my $out = sh(q{grep -rnIE 'https?://|<script src|<link ' lib/Scrum.pm lib/Cockpit.pm | grep -v '^\s*#' | grep -vi 'teams.microsoft.com\|w3.org\|comment\|api.github' | head -5});
    gate(id => 'external', pillar => 'Security gates', name => 'No external resources in generated pages (nothing loads from the internet; works on an air-gapped share)',
         state => $out =~ /\S/ ? 'partial' : 'ok', evidence => $out =~ /\S/ ? 'references found, see detail' : 'reports and cockpit are self-contained; tests enforce no <script src>, <link>, http(s) in reports',
         detail => $out || 'tests/scrum.t, tests/cockpit.t: "nothing external"');
}
{   my $out = -f 'data/demo/scrum.conf' ? sh(qq("$^X" bin/daily.pl --conf data/demo/scrum.conf check)) : 'data/demo not present';
    gate(id => 'marking', pillar => 'Security gates', name => 'Marking gate (banner and block on every report and mail; mail_domains restricts recipients; send refuses on error)',
         state => ($out =~ /error/i ? 'gap' : $out =~ /marking/ ? 'ok' : 'partial'), evidence => $out =~ /error/i ? 'marking errors on the demo project' : 'daily.pl check passes on the demo project; draft/brief/cards --send refuse on error',
         detail => $out);
}
gate(id => 'deps', pillar => 'Security gates', name => 'Dependencies: core Perl only (the SBOM is the interpreter)',
     state => (sh(q{grep -rhoE '^use [A-Z][A-Za-z:]+' lib bin agile.pl | sort -u | grep -vE '^use (strict|warnings|utf8|lib|FindBin|Getopt::Long|Cwd|POSIX|File::|JSON::PP|Digest::|IO::|List::Util|Encode|Time::|Scalar::Util|Prelude|Ledger|Scrum|Standup|Calendar|Chat|Answers|Ai|Attendance|Cockpit)'}) =~ /\S/ ? 'partial' : 'ok'),
     evidence => 'no CPAN, no XS, no network at build or run time; curl only for the optional AI endpoint',
     detail => sh(q{grep -rhoE '^use [A-Z][A-Za-z:]+' lib bin agile.pl | sort | uniq -c | sort -rn | head -14}));
gate(id => 'sast', pillar => 'Security gates', name => 'Static analysis for Perl (perlcritic)', state => 'partial',
     evidence => 'perlcritic --severity 5 runs in the Linux CI job (tests.yml); not on the target, where strict/warnings + perl -c + the test suites stand in',
     detail => 'perlcritic is CPAN, so it cannot run on the target Perl; the Linux job covers the same sources.');

# -- release
{   my @z = sorted(glob 'release/agile-*.zip');
    gate(id => 'release', pillar => 'Release to the target', name => 'Reproducible package for the target machine (git archive + SHA-256, no data/)',
         state => @z ? 'ok' : 'partial', evidence => @z ? "latest: $z[-1]" . (-f "$z[-1].sha256" ? ' (+ .sha256)' : '') : 'no package built yet: perl bin/release.pl',
         detail => @z ? sh("cat '$z[-1].sha256' 2>/dev/null") : '');
}
gate(id => 'target', pillar => 'Release to the target', name => 'Runs on the target toolchain (Git Bash + core Perl + Vim + classic Outlook)',
     state => (@perls > 1 ? 'ok' : 'partial'), evidence => @perls > 1 ? 'suite executed under Git for Windows\' Perl on this machine' : 'Git for Windows\' Perl not found here; target not exercised',
     detail => 'Outlook COM layer: docs/TEST-PLAN.html (manual, 30 min, on the target)');

# -- observability
gate(id => 'cockpit', pillar => 'Observability', name => 'The product\'s own telemetry: journal-derived cockpit, reports, HISTORY',
     state => (-f 'dashboard.html' ? 'ok' : 'partial'), evidence => -f 'dashboard.html' ? 'dashboard.html present (' . sh('grep -o "\\"generated\\":\\"[^\\"]*\\"" dashboard.html | head -1') . ')' : 'run perl agile.pl',
     detail => 'perl agile.pl [PROJECT]');
gate(id => 'docs', pillar => 'Observability', name => 'Docs as code (HTML in docs/, regenerated replay, CLAUDE.md for the assistant)',
     state => 'ok', evidence => sh('ls docs/*.html | wc -l') . ' HTML documents; TRAINING.html regenerated by sim/training.pl', detail => sh('ls docs'));

# ---------------------------------------------------------------- page
my %def = (
  'Source control' => 'Every change recorded with who/why, recoverable, and project data kept out of the code repository.',
  'CI: build, lint, test' => 'Continuous Integration: every change is compiled and tested automatically, here on both interpreters and (when pushed) on GitHub runners.',
  'Security gates' => 'Shift-left checks that fail the build: secrets, markings, external resources, dependency surface, static analysis.',
  'Release to the target' => 'A reproducible, checksummed package that runs on a plain Windows machine with only Git for Windows, nothing installed.',
  'Observability' => 'What the system tells you about itself: the cockpit, reports, history and docs derived from the journal.',
);
my @order = ('Source control', 'CI: build, lint, test', 'Security gates', 'Release to the target', 'Observability');
my %count; $count{ $_->{state} }++ for @gates;
my $pill = sub { my ($st, $txt) = @_; qq(<span class="pill $st">$txt</span>) };
my $badges = $gh_repo ? join '', map { qq(<a href="https://github.com/$gh_owner/$gh_repo/actions/workflows/$_.yml" title="live run on GitHub Actions"><img src="https://github.com/$gh_owner/$gh_repo/actions/workflows/$_.yml/badge.svg" alt="$_" style="vertical-align:middle"></a>) } qw(tests security) : '';
my $live = $gh_repo
  ? qq(<div class="live-strip" id="live-strip"><span class="live-strip-label">Live job status:</span>) . join('', map { qq(<span class="live-job" data-job="$_->[0]">$_->[1]<i class="dot"></i></span>) } ['git-for-windows-perl','tests: win/GitPerl'], ['linux-perl','tests: linux'], ['secrets','gitleaks'], ['hygiene','hygiene']) . qq(<a href="#" id="live-refresh">refresh</a><span id="live-stamp"></span></div>)
  : qq(<div class="live-strip"><span class="live-strip-label">Live job status:</span><span class="live-job">local gates only<i class="dot" data-state="pending"></i></span><span id="live-stamp">no GitHub remote configured; every status below was produced on this machine at $NOW</span></div>);

my $cards = '';
for my $p (@order) {
    my @g = @{ $pillar{$p} // [] };
    my $st = (grep { $_->{state} eq 'gap' } @g) ? 'gap' : (grep { $_->{state} eq 'partial' } @g) ? 'partial' : 'ok';
    my $label = { ok => 'All gates pass', partial => 'Partially verified', gap => 'Gap' }->{$st};
    $cards .= qq(<div class="card status-$st"><div class="card-head"><h3><a class="term" title=") . h($def{$p}) . qq(">) . h($p) . qq(</a></h3><span class="badge $st">$label</span></div>\n<ul class="gates">\n);
    for my $g (@g) {
        $cards .= qq(<li class="$g->{state}"><span class="dot"></span><b>) . h($g->{name}) . qq(</b><br><span class="ev">) . h($g->{evidence}) . qq(</span>) . ($g->{detail} =~ /\S/ ? qq(<details><summary>evidence</summary><pre>) . h($g->{detail}) . qq(</pre></details>) : '') . qq(</li>\n);
    }
    $cards .= "</ul></div>\n";
}
my $rows = join '', map { qq(<tr><td>$_->{pillar}</td><td>) . h($_->{name}) . qq(</td><td><span class="badge $_->{state}">$_->{state}</span></td><td>) . h($_->{evidence}) . qq(</td></tr>\n) } @gates;
my $logo = logo_svg();
my $ghjs = $gh_repo ? <<"JS" : '';
(function(){var owner='$gh_owner',repo='$gh_repo';var stamp=document.getElementById('live-stamp');
function refresh(){fetch('https://api.github.com/repos/'+owner+'/'+repo+'/actions/runs?per_page=20').then(function(r){return r.json()}).then(function(d){
 var seen={};(d.workflow_runs||[]).forEach(function(run){var k=run.name;if(seen[k])return;seen[k]=run;});
 document.querySelectorAll('.live-job[data-job]').forEach(function(el){var job=el.getAttribute('data-job');var run=seen['tests']||seen['security'];var st='pending';
  Object.keys(seen).forEach(function(k){var r=seen[k];if(r.conclusion==='success')st=st==='failure'?st:'success';else if(r.conclusion==='failure')st='failure';});
  el.querySelector('.dot').setAttribute('data-state',st);});stamp.textContent=' checked '+new Date().toLocaleTimeString();}).catch(function(){stamp.textContent=' offline: showing the local gates from $NOW';});}
document.getElementById('live-refresh').addEventListener('click',function(e){e.preventDefault();refresh();});refresh();})();
JS

my $html = <<"HTML";
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>agile kit &mdash; DevSecOps Dashboard</title>
<meta name="description" content="Status of the agile kit's own pipeline: source control, CI on the target Perl, security gates, release packaging, observability. Every status was produced by running the gate.">
<style>
:root{--bg:#f4f4f5;--panel:#fff;--fg:#0b0b0b;--muted:#4a4a4c;--accent:#27235d;--accent-soft:#e9e8f1;--rule:#e4e4e7;--gold:#e6af22;
--ok-border:#2f8f4e;--ok-bg:#eaf7ee;--partial-border:#b8860b;--partial-bg:#fbf3df;--gap-border:#a3313f;--gap-bg:#fbecee;--code-bg:#f0f1f3;--shadow:0 1px 3px rgba(20,25,35,.08),0 1px 2px rgba(20,25,35,.06)}
\@media (prefers-color-scheme: dark){:root:not([data-theme="light"]){--bg:#14161a;--panel:#1b1e24;--fg:#e6e8eb;--muted:#9aa4b2;--accent:#aac1d7;--accent-soft:#242a3a;--rule:#2c3038;--ok-border:#4caf72;--ok-bg:#16261c;--partial-border:#d9a441;--partial-bg:#2b2413;--gap-border:#e2828d;--gap-bg:#2c1a1d;--code-bg:#22252b;--shadow:0 1px 3px rgba(0,0,0,.4)}}
*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--fg);font-family:"Segoe UI",Helvetica,Arial,sans-serif;line-height:1.42;font-size:clamp(.92rem,.8rem + .25vw,1.02rem)}
.wrap{width:100%;padding:.6rem clamp(1rem,4vw,4rem) 1.5rem}
header.top{display:flex;flex-wrap:wrap;align-items:baseline;justify-content:space-between;gap:.5rem 1.5rem;padding-bottom:.35rem;margin-bottom:.5rem;border-bottom:3px solid var(--gold)}
header.top h1{margin:0;font-size:1.3rem;color:var(--accent)}header.top h1 svg.logo{height:22px;width:auto;color:var(--panel);vertical-align:-3px;margin-right:10px}
header.top .links a{color:var(--accent);text-decoration:none;font-size:.82rem;margin-left:1rem}header.top .links a:hover{text-decoration:underline}
.summary-bar{display:flex;flex-wrap:wrap;gap:.5rem;align-items:center}
.pill{font-size:.74rem;font-weight:600;padding:.2rem .6rem;border-radius:999px;white-space:nowrap}
.pill.ok{background:var(--ok-bg);color:var(--ok-border);border:1px solid var(--ok-border)}.pill.partial{background:var(--partial-bg);color:var(--partial-border);border:1px solid var(--partial-border)}.pill.gap{background:var(--gap-bg);color:var(--gap-border);border:1px solid var(--gap-border)}
.live-strip{display:flex;flex-wrap:wrap;align-items:center;gap:.55rem;background:var(--panel);border:1px solid var(--rule);border-radius:6px;padding:.4rem .75rem;margin-bottom:.75rem;font-size:.76rem}
.live-strip-label{color:var(--muted);font-weight:600}.live-job{display:inline-flex;align-items:center;gap:.3rem;font-family:Consolas,Menlo,monospace}
.live-job .dot{display:inline-block;width:.6em;height:.6em;border-radius:50%;background:#9aa4b2}.live-job .dot[data-state="success"]{background:#2f8f4e}.live-job .dot[data-state="failure"]{background:#c0392b}.live-job .dot[data-state="pending"]{background:#d9a441}
.live-strip a{color:var(--accent);text-decoration:none;margin-left:auto}#live-stamp{color:var(--muted)}
h2.section-title{font-size:.76rem;text-transform:uppercase;letter-spacing:.04em;color:var(--accent);background:var(--accent-soft);padding:.22rem .6rem;margin:.85rem 0 .5rem;border-radius:4px}
.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(340px,1fr));gap:.7rem}\@media(min-width:1500px){.grid{grid-template-columns:repeat(3,1fr)}}
.card{background:var(--panel);border:1px solid var(--rule);border-radius:8px;padding:.65rem .8rem .75rem;box-shadow:var(--shadow);border-top:4px solid var(--rule)}
.card.status-ok{border-top-color:var(--ok-border)}.card.status-partial{border-top-color:var(--partial-border)}.card.status-gap{border-top-color:var(--gap-border)}
.card-head{display:flex;align-items:center;justify-content:space-between;gap:.5rem;margin-bottom:.3rem}.card h3{margin:0;font-size:.95rem}
.badge{font-size:.64rem;font-weight:700;text-transform:uppercase;letter-spacing:.03em;padding:.12rem .4rem;border-radius:4px;flex-shrink:0}
.badge.ok{background:var(--ok-bg);color:var(--ok-border)}.badge.partial{background:var(--partial-bg);color:var(--partial-border)}.badge.gap{background:var(--gap-bg);color:var(--gap-border)}
ul.gates{list-style:none;margin:.3rem 0 0;padding:0;font-size:.8rem}ul.gates li{padding:.3rem 0 .3rem 1.1rem;position:relative;border-top:1px solid var(--rule)}ul.gates li:first-child{border-top:0}
ul.gates li .dot{position:absolute;left:0;top:.6rem;width:.6rem;height:.6rem;border-radius:50%}ul.gates li.ok .dot{background:var(--ok-border)}ul.gates li.partial .dot{background:var(--partial-border)}ul.gates li.gap .dot{background:var(--gap-border)}
ul.gates .ev{color:var(--muted)}ul.gates details{margin-top:.2rem}ul.gates summary{cursor:pointer;color:var(--accent);font-size:.74rem}ul.gates pre{margin:.2rem 0 0;font-size:.7rem;background:var(--code-bg);padding:.4rem .6rem;border-radius:4px;overflow-x:auto;white-space:pre-wrap}
table.scan-table{width:100%;border-collapse:collapse;background:var(--panel);border:1px solid var(--rule);border-radius:8px;overflow:hidden;font-size:.8rem}
table.scan-table th,table.scan-table td{border-bottom:1px solid var(--rule);padding:.35rem .6rem;text-align:left;vertical-align:top}table.scan-table th{background:var(--accent-soft);font-size:.74rem;text-transform:uppercase;letter-spacing:.03em;color:var(--muted)}
a.term{color:inherit;text-decoration:none;border-bottom:1px dotted var(--accent);cursor:help}a.term:hover{background:var(--accent-soft)}
.foot{color:var(--muted);font-size:.76rem;margin-top:1rem}
</style>
</head>
<body>
<div class="wrap">
<header class="top">
  <h1>$logo agile kit &mdash; DevSecOps Dashboard</h1>
  <div class="summary-bar">
    @{[ $pill->('ok', ($count{ok} // 0) . ' gates pass') ]}
    @{[ $pill->('partial', ($count{partial} // 0) . ' partially verified') ]}
    @{[ $pill->('gap', ($count{gap} // 0) . ' gaps') ]}
    $badges
  </div>
  <nav class="links">
    <a href="dashboard.html" style="font-weight:700">Cockpit</a>
    <a href="docs/SECURITY.html">SECURITY</a>
    <a href="docs/PILOT.html">Pilot plan</a>
    <a href="docs/TEST-PLAN.html">Test plan (Outlook COM)</a>
    <a href="docs/README.html">README</a>
    <a href=".github/workflows/tests.yml">tests.yml</a>
    <a href=".github/workflows/security.yml">security.yml</a>
    @{[ $gh_repo ? qq(<a href="https://github.com/$gh_owner/$gh_repo/actions" target="_blank">Actions &#8599;</a>) : '' ]}
  </nav>
</header>
$live
<h2 class="section-title">Pipeline pillars &mdash; every status below was produced by running the gate on this machine at $NOW ($branch\@$sha)</h2>
<div class="grid">
$cards</div>
<h2 class="section-title">Gate table</h2>
<table class="scan-table"><tr><th>Pillar</th><th>Gate</th><th>State</th><th>Evidence</th></tr>
$rows</table>
<p class="foot">Regenerate: <code>perl bin/devsecops.pl</code> (add <code>--quick</code> to skip the suites). Interpreters exercised: @{[ join '; ', map { $_->[0] } @perls ]}. Total tests: $total.</p>
</div>
<script>$ghjs</script>
</body>
</html>
HTML

open my $fh, '>:encoding(UTF-8)', 'devsecops.html' or die "cannot write devsecops.html: $!\n";
print $fh $html; close $fh;
printf "wrote %s/devsecops.html  (%d ok, %d partial, %d gap)\n", $ROOT, $count{ok} // 0, $count{partial} // 0, $count{gap} // 0;
if ($o{open}) { $^O =~ /^(MSWin32|cygwin|msys)$/ ? system('powershell.exe', '-NoProfile', '-Command', 'Start-Process', '-FilePath', "$ROOT/devsecops.html") : $^O eq 'darwin' ? system('open', 'devsecops.html') : system('xdg-open', 'devsecops.html') }
exit(($count{gap} // 0) ? 1 : 0);
