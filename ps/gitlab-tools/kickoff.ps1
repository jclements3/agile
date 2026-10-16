<#
kickoff.ps1 -- week zero for a model team on a PowerShell-only PC (tools/gitlab/kickoff.pl): check this PC, make the
model repository, and set up the GitLab project, the journal and the first issues -- one command at a time, each
printed before it runs.

Windows PowerShell 5.1, Constrained Language Mode safe, pure ASCII. The kit's tools here are PowerShell: pgit.ps1
(no git), gitlab.ps1, gitflow.ps1, agile.ps1, sysml\model.ps1; the templates are in gitlab-tools\templates.

  kickoff.cmd doctor [--quick] [--fix] [--local DIR | --url URL [--token-env VAR]]
  kickoff.cmd scaffold DIR [--project GROUP/NAME] [--title T] [--noun-root N] [--verb-root V] [--levels L1A,...] [--layout-map FILE] [--force]
  kickoff.cmd start [--yes] [--local DIR | --url URL [--token-env VAR]] [--project GROUP/NAME] [--title T] [--conf FILE]
                    [--dir REPO] [--journal DIR] [--team NAME] [--as USER] [--sprints START COUNT] [--no-wiki] [--no-issues] [--from N]
  kickoff.cmd help [COMMAND]

doctor   PASS / WARN / FAIL / SKIP per check, with the command that fixes each failure. On this PC it checks: Windows
         PowerShell 5.1 and its language mode; the kit's PowerShell tools beside this folder (pgit, gitlab, gitlab-ci,
         gitflow, agile, pvi, model, the templates); pgit's identity and recommended settings (pgit config --global);
         a quick self-test (the template pipeline parses with gitlab-ci, a pgit repository round trip); GitLab
         (the emulator folder, or the server's /api/v4/version through Invoke-WebRequest with the token). There is no
         Perl, git, Vim, curl or SSH here, and none is needed. --fix sets the recommended pgit settings (never your
         name or e-mail), printing each command first. Exit 1 when anything FAILs.
scaffold the model repository from the templates (the same files as the Perl kit), the outline allowance and the
         generated docs from sysml\model.ps1, then `pgit init -b main` and the first commit. Only DIR is touched.
start    the week-zero sequence. Without --yes it prints the steps and their commands (a dry run). With --yes it runs
         them; a step that needs git or a GitLab server this PC cannot reach (pushing main, gitflow's develop on the
         server, the prime drop) is printed as "not run" with what to run on a PC with git, never skipped silently.
#>

$ErrorActionPreference = 'Stop'
$script:KO_HERE = $PSScriptRoot; if (-not $script:KO_HERE) { $script:KO_HERE = (Get-Location).Path }
$script:KO_PS = Split-Path -Parent $script:KO_HERE
$script:KO_TPL = Join-Path $script:KO_HERE 'templates'
$script:KO_OUTLINE_ROOM = 6
$script:KO_OUT = ''
function KoOut([string]$s) { Write-Host -NoNewline $s }
function KoDie([string]$m) { throw ('KODIE:' + $m) }

$script:KO_HELP = @{
    doctor = "kickoff.cmd doctor [--quick] [--fix] [--local DIR | --url URL [--token-env VAR]]`n" +
        "  Checks Windows PowerShell 5.1 and its language mode, the kit's PowerShell tools and templates, pgit's identity and`n" +
        "  recommended settings, a quick self-test, and GitLab (the emulator, or the server with the token). --quick skips`n" +
        "  the self-test. --fix sets the recommended pgit settings, printing each command first; it never sets your name or`n" +
        "  e-mail. Exit 1 if anything FAILs.`n"
    scaffold = "kickoff.cmd scaffold DIR [--project GROUP/NAME] [--title T] [--noun-root N] [--verb-root V] [--levels L1A,L2B,...] [--layout-map FILE] [--force]`n" +
        "  Makes the model repository in DIR from the templates, runs pgit init -b main and commits it.`n" +
        "  --layout-map FILE: where each prime package lands (.ci/layout.map; flow vendor uses it from the first drop).`n" +
        "  Without it, .ci/layout.map.example explains the format.`n" +
        "  --levels names the part-tree levels, top first (default L1System,L2Segment,L3Subsystem,L4Assembly,L5Component,L6Part).`n" +
        "  DIR must be empty or missing (--force: fill it anyway). Defaults: --project tidewater/model, --title Tidewater.`n"
    start = "kickoff.cmd start [--yes] [--local DIR | --url URL [--token-env VAR]] [--project GROUP/NAME] [--title T]`n" +
        "                  [--conf FILE] [--dir REPO] [--journal DIR] [--team NAME] [--as USER]`n" +
        "                  [--sprints START COUNT] [--no-wiki] [--no-issues] [--from N]`n" +
        "  Week zero, in order: doctor; scaffold; gitlab setup (without schedules: they need develop); push main and gitflow`n" +
        "  init (need git: printed); setup again (schedules); sprints; the journal + roster; wiki pages; the first issues from`n" +
        "  the Story template. Without --yes: print the plan only.`n"
}

# ---------------------------------------------------------------- bytes and text
function KoUtf8Enc([string]$s) {
    $buf = [byte[]]::new($s.Length * 3 + 4); $n = 0
    for ($i = 0; $i -lt $s.Length; $i++) {
        $c = [int]$s[$i]
        if ($c -ge 0xD800 -and $c -le 0xDBFF -and $i + 1 -lt $s.Length) { $c = 0x10000 + (($c - 0xD800) -shl 10) + ([int]$s[$i + 1] - 0xDC00); $i++ }
        if ($c -lt 0x80) { $buf[$n++] = $c }
        elseif ($c -lt 0x800) { $buf[$n++] = 0xC0 -bor ($c -shr 6); $buf[$n++] = 0x80 -bor ($c -band 0x3F) }
        elseif ($c -lt 0x10000) { $buf[$n++] = 0xE0 -bor ($c -shr 12); $buf[$n++] = 0x80 -bor (($c -shr 6) -band 0x3F); $buf[$n++] = 0x80 -bor ($c -band 0x3F) }
        else { $buf[$n++] = 0xF0 -bor ($c -shr 18); $buf[$n++] = 0x80 -bor (($c -shr 12) -band 0x3F); $buf[$n++] = 0x80 -bor (($c -shr 6) -band 0x3F); $buf[$n++] = 0x80 -bor ($c -band 0x3F) }
    }
    $o = [byte[]]::new($n); if ($n) { [Array]::Copy($buf, $o, $n) }
    return , $o
}
function KoUtf8Dec([byte[]]$b) {
    $n = $b.Length; if ($n -eq 0) { return '' }
    $o = [char[]]::new($n * 2); $k = 0; $i = 0
    while ($i -lt $n) {
        $c = [int]$b[$i]
        if ($c -lt 0x80) { $o[$k++] = [char]$c; $i++; continue }
        $len = 0; $cp = 0
        if ($c -ge 0xC2 -and $c -le 0xDF) { $len = 2; $cp = $c -band 0x1F } elseif ($c -ge 0xE0 -and $c -le 0xEF) { $len = 3; $cp = $c -band 0x0F } elseif ($c -ge 0xF0 -and $c -le 0xF4) { $len = 4; $cp = $c -band 0x07 }
        $ok = $len -gt 0 -and $i + $len -le $n
        if ($ok) { for ($j = 1; $j -lt $len; $j++) { $x = [int]$b[$i + $j]; if (($x -band 0xC0) -ne 0x80) { $ok = $false; break }; $cp = ($cp -shl 6) -bor ($x -band 0x3F) } }
        if (-not $ok) { $o[$k++] = [char]$c; $i++; continue }
        if ($cp -ge 0x10000) { $cp -= 0x10000; $o[$k++] = [char](0xD800 + ($cp -shr 10)); $o[$k++] = [char](0xDC00 + ($cp -band 0x3FF)) } else { $o[$k++] = [char]$cp }
        $i += $len
    }
    return (-join $o[0..($k - 1)])
}
function KoSlurp([string]$f) {
    if (-not (Test-Path -LiteralPath $f -PathType Leaf)) { return $null }
    $b = Get-Content -LiteralPath $f -Encoding Byte -ReadCount 0
    if ($null -eq $b) { return '' }
    return (KoUtf8Dec ([byte[]]$b))
}
function KoSpew([string]$f, [string]$t) {
    $d = Split-Path -Parent $f
    if ($d -and -not (Test-Path -LiteralPath $d)) { New-Item -ItemType Directory -Force -Path $d | Out-Null }
    $bytes = KoUtf8Enc $t
    if ($bytes.Length -eq 0) { Set-Content -LiteralPath $f -Value '' -NoNewline -Encoding Ascii } else { Set-Content -LiteralPath $f -Encoding Byte -Value $bytes }
}
function KoTool([string]$rel) { return (Join-Path $script:KO_PS $rel) }
function KoRun([string]$script, [string[]]$argv, [string]$dir) {   # a kit tool in this process -> @(exit code, output text)
    $here = (Get-Location).Path
    try {
        if ($dir) { Set-Location -LiteralPath $dir }
        $out = & $script @argv 2>&1 | ForEach-Object { [string]$_ }
        $rc = $LASTEXITCODE; if ($null -eq $rc) { $rc = 0 }
    } catch { $out = @([string]$_.Exception.Message); $rc = 1 }
    finally { Set-Location -LiteralPath $here }
    $text = (@($out) -join "`n")
    return , @($rc, $text)
}
function KoPgit([string]$repo, [string[]]$argv) {                # pgit fenced to $repo: GIT_CEILING_DIRECTORIES = its parent
    $saved = $env:GIT_CEILING_DIRECTORIES
    $env:GIT_CEILING_DIRECTORIES = Split-Path -Parent $repo
    try { return (KoRun (KoTool 'pgit.ps1') $argv $repo) }
    finally { if ($null -eq $saved) { Remove-Item env:GIT_CEILING_DIRECTORIES -ErrorAction SilentlyContinue } else { $env:GIT_CEILING_DIRECTORIES = $saved } }
}
function KoQ([string]$a) { if ($a -cmatch '^[\w./:=@%+,\\-]+$') { return $a }; return "'" + $a.Replace("'", "''") + "'" }
function KoShow($c) { $p = @(); foreach ($x in $c) { $p += (KoQ ([string]$x)) }; return ($p -join ' ') }

# ---------------------------------------------------------------- doctor
function KoRecommended { return , @(@('init.defaultBranch', 'main', 'new repositories start on main'), @('core.autocrlf', 'false', 'model files keep their line endings; the baselines hash them'), @('pull.ff', 'only', 'a pull never makes a surprise merge commit')) }
function KoGlobalCfg([string]$key) { $r = KoRun (KoTool 'pgit.ps1') @('config', '--global', $key) $null; if ($r[0] -ne 0) { return $null }; $v = ($r[1] -split "`n")[0]; if ($v -ceq '') { return $null }; return $v }
function KoDoctor($o) {
    $rows = @()
    $v = $PSVersionTable.PSVersion
    $ok = $v.Major -gt 5 -or ($v.Major -eq 5 -and $v.Minor -ge 1)
    $rows += , @($(if ($ok) { 'PASS' } else { 'FAIL' }), "Windows PowerShell $v", $(if ($ok) { $null } else { 'Windows PowerShell 5.1 is part of Windows 10 and 11: use it, not an older one' }))
    $mode = [string]$ExecutionContext.SessionState.LanguageMode
    $rows += , @('PASS', "language mode $mode" + $(if ($mode -cne 'FullLanguage') { ' (the tools are written for it)' } else { '' }), $null)
    $tools = @('pgit.ps1', 'gitlab.ps1', 'gitlab-ci.ps1', 'gitflow.ps1', 'agile.ps1', 'pvi.ps1', 'ziplib.ps1', 'sysml\model.ps1', 'gitlab-tools\ci-reports.ps1')
    $missing = @(); foreach ($t in $tools) { if (-not (Test-Path -LiteralPath (KoTool $t))) { $missing += $t } }
    $rows += , @($(if ($missing.Count) { 'FAIL' } else { 'PASS' }), $(if ($missing.Count) { 'kit tools missing: ' + ($missing -join ' ') } else { "the kit's PowerShell tools ($($tools.Count)) in $($script:KO_PS)" }), $(if ($missing.Count) { 'unzip the whole tools folder again: every tool sits beside pgit.ps1' } else { $null }))
    $rows += , @($(if (Test-Path -LiteralPath (Join-Path $script:KO_TPL 'gitlab-ci.yml')) { 'PASS' } else { 'FAIL' }), "the repository templates ($($script:KO_TPL))", $(if (Test-Path -LiteralPath (Join-Path $script:KO_TPL 'gitlab-ci.yml')) { $null } else { 'the templates folder is beside kickoff.ps1 in the kit: unzip it again' }))
    if (Test-Path -LiteralPath (KoTool 'pgit.ps1')) {
        foreach ($k in @(@('user.name', 'pgit config --global user.name "Your Name"'), @('user.email', 'pgit config --global user.email you@agency.gov'))) {
            $val = KoGlobalCfg $k[0]
            $rows += , @($(if ($null -ne $val) { 'PASS' } else { 'FAIL' }), $(if ($null -ne $val) { "pgit $($k[0]) = $val" } else { "pgit $($k[0]) is not set (commits need it)" }), $(if ($null -ne $val) { $null } else { $k[1] }))
        }
        foreach ($s in (KoRecommended)) {
            $val = KoGlobalCfg $s[0]
            if ($null -ne $val -and $val -ceq $s[1]) { $rows += , @('PASS', "pgit $($s[0]) = $($s[1])", $null) }
            elseif ($o.fix) {
                KoOut "running: pgit config --global $($s[0]) $($s[1])`n"
                $r = KoRun (KoTool 'pgit.ps1') @('config', '--global', $s[0], $s[1]) $null
                $rows += , @($(if ($r[0]) { 'FAIL' } else { 'PASS' }), $(if ($r[0]) { "pgit $($s[0]) could not be set: $($r[1])" } else { "pgit $($s[0]) = $($s[1]) (set by --fix)" }), $(if ($r[0]) { "pgit config --global $($s[0]) $($s[1])" } else { $null }))
            }
            else { $isv = if ($null -ne $val) { "'$val'" } else { 'not set' }; $rows += , @('WARN', "pgit $($s[0]) is $isv, recommended $($s[1]) ($($s[2]))", "pgit config --global $($s[0]) $($s[1])   (or: kickoff.cmd doctor --fix)") }
        }
    }
    if ($o.quick) { $rows += , @('SKIP', "the kit's self-test (--quick)", $null) }
    else {
        $okp = $false
        try { $okp = & { param($lib, $y) . $lib __lib; $null = GciParseYaml (GciSlurp $y) 'gitlab-ci.yml'; $true } (KoTool 'gitlab-ci.ps1') (Join-Path $script:KO_TPL 'gitlab-ci.yml') } catch { $okp = $false }
        $rows += , @($(if ($okp) { 'PASS' } else { 'FAIL' }), 'self-test: the template pipeline parses (gitlab-ci)', $(if ($okp) { $null } else { 'gitlab-ci.cmd __yaml ' + (Join-Path $script:KO_TPL 'gitlab-ci.yml') }))
        $tmp = Join-Path $(if ($env:TEMP) { $env:TEMP } else { '.' }) ('kickoff-selftest-' + (Get-Random -Maximum 999999))
        New-Item -ItemType Directory -Force -Path $tmp | Out-Null
        try {
            $null = KoPgit $tmp @('init', '-q', '-b', 'main')
            KoSpew (Join-Path $tmp 'a.txt') "self-test`n"
            $null = KoPgit $tmp @('add', 'a.txt')
            $null = KoPgit $tmp @('config', 'user.name', 'kickoff'); $null = KoPgit $tmp @('config', 'user.email', 'kickoff@example.invalid')
            $c = KoPgit $tmp @('commit', '-q', '-m', 'self-test')
            $f = KoPgit $tmp @('fsck')
            $okg = $c[0] -eq 0 -and $f[0] -eq 0
            $rows += , @($(if ($okg) { 'PASS' } else { 'FAIL' }), 'self-test: a pgit repository round trip (init, add, commit, fsck)', $(if ($okg) { $null } else { 'pgit.cmd help   (the tool may be incomplete: ' + $c[1] + ' ' + $f[1] + ')' }))
        } finally { Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue }
    }
    if ($o.local) {
        $rows += , @('PASS', $(if (Test-Path -LiteralPath (Join-Path $o.local 'gitlab.json')) { "GitLab: the local emulator in $($o.local)" } else { "GitLab: the local emulator ($($o.local) is created on first use)" }), $null)
    } elseif ($o.url -or $env:GITLAB_URL) {
        $url = if ($o.url) { $o.url } else { $env:GITLAB_URL }
        $var = if ($o.token_env) { $o.token_env } else { 'GITLAB_TOKEN' }
        $tok = (Get-Item -LiteralPath "env:$var" -ErrorAction SilentlyContinue)
        if (-not $tok -or -not $tok.Value) { $rows += , @('FAIL', "GitLab ${url}: no token in `$env:$var", "create a personal access token (scope api) under Preferences > Access tokens, then: `$env:$var = 'glpat-...'") }
        else {
            $base = $url -creplace '/+$', ''
            $code = '000'
            try { $resp = Invoke-WebRequest -UseBasicParsing -Uri "$base/api/v4/version" -Headers @{ 'PRIVATE-TOKEN' = $tok.Value } -TimeoutSec 15; $code = [string]$resp.StatusCode }
            catch { if ($_.Exception.Response) { $code = [string][int]$_.Exception.Response.StatusCode } }
            $rows += , @($(if ($code -ceq '200') { 'PASS' } else { 'FAIL' }), "GitLab ${base}: " + $(if ($code -ceq '200') { 'reachable, token accepted' } else { "HTTP $code" }), $(if ($code -ceq '200') { $null } elseif ($code -ceq '401') { "the token in `$env:$var is wrong or expired: make a new one (scope api)" } else { 'check the URL, the VPN and the proxy (Invoke-WebRequest ' + "$base/api/v4/version)" }))
        }
    } else { $rows += , @('SKIP', 'GitLab: none named', "`$env:GITLAB_URL = 'https://gitlab.your.agency'  (or --local DIR for the offline emulator)") }
    $rows += , @('SKIP', 'SSH: not used on this PC (pgit has no remote; GitLab is reached over HTTPS with a token)', $null)
    $n = @{ PASS = 0; WARN = 0; FAIL = 0; SKIP = 0 }
    foreach ($r in $rows) {
        $n[$r[0]]++
        KoOut ('{0,-5} {1}' -f $r[0], $r[1]) ; KoOut "`n"
        if ($r[2] -and $r[0] -cne 'PASS') { KoOut "      fix: $($r[2])`n" }
    }
    KoOut ('doctor: {0} pass, {1} warn, {2} fail, {3} skipped' -f $n.PASS, $n.WARN, $n.FAIL, $n.SKIP); KoOut "`n"
    if ($n.FAIL) { return 1 }
    return 0
}

# ---------------------------------------------------------------- scaffold
$script:KO_LAYOUT_EXAMPLE = @'
# .ci/layout.map.example -- an example, not in use. Rename it to .ci/layout.map (by merge request, BEFORE the first
# prime drop) to choose where each top-level package of a drop lands in this repository:
#
#   PACKAGE = folder/                -> model/folder/<Package>.sysml
#   PACKAGE = folder/File.sysml      -> exactly that file
#
# gitlab.pl flow vendor reads .ci/layout.map for every drop (both converters use it), so a package always lands at
# the same path and the next drop merges 3-way on vendor/prime. Without it the converters write one folder per
# package (model/<package>/) and the DOORS modules under model/doors/. A package the prime adds later that the map
# does not list lands in unsorted/, and the converter's report names it.
#
# The folders are the repository's layers, lowest first: library -> requirements -> logical -> physical ->
# analysis -> verification (a package may depend only on its own layer or a lower one). Tidewater's map, for
# example (examples/tidewater-v1/layout.map in the kit):
#
# Types                = library/
# Interfaces           = library/
# Tidewater            = library/
# Stakeholder Needs    = requirements/stakeholder/
# System Requirements  = requirements/system/
# Segment Requirements = requirements/segment/
# Requirements         = requirements/model/
# Behavior             = logical/
# Network              = physical/network/
# Stations             = physical/stations/
# DataCenter           = physical/datacenter/
# Operations           = physical/operations/
# Allocations          = physical/allocation/
# Analysis             = analysis/
# Verification         = verification/
# Legacy Import        = legacy/

'@
$script:KO_CHANGELOG = @'
# Changelog

All notable changes to the @TITLE@ model, one section per baseline, newest first. Entries come from the merge
requests' `Changelog:` commit trailers (the wiki page *Definition of Done*). The release job publishes a baseline's
section as its release notes.

<!-- When you cut a baseline, on the release branch: rename `## [Unreleased]` to `## [baseline-N] -- DATE` and
     delete the headings left empty under it; put a fresh `## [Unreleased]` with the four empty headings above it;
     add the link lines at the bottom. The release job publishes exactly the `## [baseline-N]` section (empty
     headings and this comment are never part of it). A baseline entry looks like this (indented here so it is
     not taken for a real section):

    ## [baseline-1] -- 2027-03-19

    ### Added
    - The structure ported from prime drop v1.0: 12 packages, 40 part definitions (!3 to !21).
    - Requirements from DOORS with their doorsId, and the satisfy/verify trace (!22 to !30).

    ### Prime drops merged
    - v1.0, 2026-10-02 (#5)

    [Unreleased]: ../-/compare/baseline-1...develop
    [baseline-1]: ../-/tags/baseline-1
-->

## [Unreleased]

### Added

### Changed

### Fixed

### Prime drops merged

[Unreleased]: ../-/commits/develop

'@
$script:KO_ADR1 = @'
# 1. Record decisions in the repository

Date: (the day you merge this)

## Status

Accepted

## Context

The team makes structural decisions about the model and the process: branching, merge method, where the prime's drops
land, what counts as progress. Decisions kept in e-mail or slides get lost, and new people repeat old debates.

## Decision

Each decision is a short Markdown file in `docs/adr/`, numbered in order, with Context, Decision and Consequences.
A decision is proposed in a merge request and accepted when the MR merges. A changed decision gets a new file that
supersedes the old one; the old file stays.

## Consequences

The reasons behind the model's structure are reviewed like the model and travel with it. Writing a decision down
takes ten minutes.

'@
function KoNl([string]$s) { return $s.Replace("`r`n", "`n") }      # here-strings in a CRLF checkout: LF, as the Perl kit writes

function KoScaffold([string]$dir, $o) {
    $project = if ($o.project) { $o.project } else { 'tidewater/model' }
    $title = if ($o.title) { $o.title } else { 'Tidewater' }
    if ($project -cnotmatch '^[\w.-]+(?:/[\w.-]+)+$') { KoDie "kickoff: --project is GROUP/NAME, not '$project'`n" }
    if (Test-Path -LiteralPath $dir) {
        $e = @(Get-ChildItem -LiteralPath $dir -Force)
        if ($e.Count -and -not $o.force) { KoDie "kickoff: $dir is not empty (use an empty or new folder, or --force)`n" }
    }
    if (-not (Test-Path -LiteralPath $script:KO_TPL -PathType Container)) { KoDie "kickoff: no templates in $($script:KO_TPL) (is this the agile kit?)`n" }
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    $dir = (Get-Item -LiteralPath $dir).FullName.TrimEnd('\')
    $made = @()
    $tplRoot = (Get-Item -LiteralPath $script:KO_TPL).FullName.TrimEnd('\')
    foreach ($f in (Get-ChildItem -LiteralPath $tplRoot -Recurse -Force -File)) {
        $rel = $f.FullName.Substring($tplRoot.Length + 1).Replace('\', '/')
        if ($rel -cmatch '^(wiki|prime)/' -or @('project.conf', 'release-notes.md', 'CHANGELOG.md') -ccontains $rel) { continue }
        $to = if ($rel -ceq 'gitlab-ci.yml') { '.gitlab-ci.yml' } elseif ($rel -cmatch '^memos/(.+)') { 'docs/memos/templates/' + $Matches[1] } else { $rel }
        KoSpew (Join-Path $dir $to) ((KoSlurp $f.FullName) -creplace '\btidewater/model\b', $project); $made += $to
    }
    KoSpew (Join-Path $dir '.gitlab/project.conf') ((KoSlurp (Join-Path $tplRoot 'project.conf')) -creplace '\btidewater/model\b', $project); $made += '.gitlab/project.conf'
    if ($title -cne 'Tidewater' -and (Test-Path -LiteralPath (Join-Path $dir 'README.md'))) {
        $t = KoSlurp (Join-Path $dir 'README.md')
        $t = ([regex]::new('(?m)^# Tidewater\b')).Replace($t, ('# ' + $title.Replace('$', '$$')), 1)
        KoSpew (Join-Path $dir 'README.md') $t
    }
    $levels = if ($o.levels) { $o.levels } else { @('L1System', 'L2Segment', 'L3Subsystem', 'L4Assembly', 'L5Component', 'L6Part') }
    $noun = [string]$o.noun_root; $verb = [string]$o.verb_root
    $sc = "# sysml.conf -- read by the kit's tools/sysml/model.pl (key = value; # comments). Written by kickoff.pl scaffold.`n" +
        "title         = $title`n" +
        $(if ($noun.Length) { "noun_root     = $noun`n" } else { "# noun_root  = TopPartDef      the part def at the top of the part tree (set it once the model has one)`n" }) +
        $(if ($verb.Length) { "verb_root     = $verb`n" } else { "# verb_root  = TopActionDef    the action def at the top of the function tree; set it once the model has one`n# (until then model.pl docs skips the IDEF0 plates). Tidewater: noun_root = ObservationNetwork, verb_root = ObserveCoast`n" }) +
        'level_tags    = ' + ($levels -join ', ') + "`n" +
        "# The level tags are metadata defs in model/library/conventions/Conventions.sysml: rename them in both places`n" +
        "# (or scaffold with --levels L1Network,L2Segment,...).`n" +
        "# layers: the dependency order of the root packages, lowest first; ``;`` between layers, ``,`` within one. A package may`n" +
        "# depend only on its own layer or a lower one (the complexity job). The folders under model/ are the same layers:`n" +
        "#   library (types, interfaces, conventions); requirements; logical (behavior); physical (structure, allocation);`n" +
        "#   analysis; verification. Add each package here as it arrives, e.g.`n" +
        "#   layers = Types, Conventions; Interfaces; System Requirements; Behavior; Network, Stations; Analysis; Verification`n" +
        "layers        = Conventions`n" +
        "# The other keys (idef0_name, steps, control_types, alloc_prefix, acronyms, need_prefix): :help agile-mbse, or`n" +
        "# the header of tools/sysml/model.pl.`n"
    KoSpew (Join-Path $dir 'sysml.conf') $sc; $made += 'sysml.conf'
    $cv = "// Government-owned (model/library/conventions): the metadata the team tags the model with, in one place,`n" +
        "// reviewed by merge request. The level tags below name the levels of the part tree, top first (sysml.conf`n" +
        "// level_tags lists the same names). The port adds here whatever else the v1 profile had.`n" +
        "package Conventions {`n    doc /* Metadata definitions used across the model. */`n"
    for ($k = 0; $k -lt $levels.Count; $k++) { $cv += "    metadata def $($levels[$k]) { doc /* Level $($k + 1) of the part tree. */ }`n" }
    $cv += "}`n"
    KoSpew (Join-Path $dir 'model/library/conventions/Conventions.sysml') $cv; $made += 'model/library/conventions/Conventions.sysml'
    KoSpew (Join-Path $dir 'verification/results.csv') "requirement,case,verdict,commit,environment,timestamp,signed_by`n"; $made += 'verification/results.csv'
    KoSpew (Join-Path $dir 'CHANGELOG.md') ((KoNl $script:KO_CHANGELOG).Replace('@TITLE@', $title)); $made += 'CHANGELOG.md'
    KoSpew (Join-Path $dir 'docs/adr/0001-record-decisions.md') (KoNl $script:KO_ADR1); $made += 'docs/adr/0001-record-decisions.md'
    if ($o.layout_map) {
        $map = KoSlurp $o.layout_map; if ($null -eq $map) { KoDie "kickoff: cannot read $($o.layout_map): No such file or directory`n" }
        KoSpew (Join-Path $dir '.ci/layout.map') ("# .ci/layout.map -- where each top-level package of a prime drop goes in this repository.`n" +
            "# gitlab.pl flow vendor (and the drop intake) read it for every drop, so a package always lands at the same`n" +
            "# path and the next drop merges 3-way on vendor/prime. Change it only by merge request, and before a drop:`n" +
            "# moving a package later means re-importing on the vendor branch. Copied by kickoff.pl scaffold.`n#`n" + $map); $made += '.ci/layout.map'
    } else { KoSpew (Join-Path $dir '.ci/layout.map.example') (KoNl $script:KO_LAYOUT_EXAMPLE); $made += '.ci/layout.map.example' }
    $model = KoTool 'sysml\model.ps1'
    $have = 0
    if (Test-Path -LiteralPath $model) {
        $chk = KoRun $model @('--root', $dir, 'check') $null
        $vv = 0; $mm = 0
        if ($chk[1] -cmatch '(?m)^violations\s+(\d+)') { $vv = [int]$Matches[1] }
        if ($chk[1] -cmatch '(?m)^@L tag mismatches\s+(\d+)') { $mm = [int]$Matches[1] }
        $have = $vv + $mm
    }
    $room = $script:KO_OUTLINE_ROOM
    KoSpew (Join-Path $dir '.ci/outline-max') ([string]($have + $room) + "`n" +
        "# .ci/outline-max -- the outline job's allowance: the number on the first line is the most outline violations`n" +
        "# (2..9 rule and level tags) a merge request may leave. The scaffold has $have (its one-file folders) and adds`n" +
        "# $room of room: requirements/, logical/, physical/, analysis/, verification/ and one more each start with one file.`n" +
        "# Tighten it -- write the count the outline job prints and delete these comment lines -- once every layer folder`n" +
        "# holds two or more files, and at the latest in the merge request of the first baseline. Never raise it by hand`n" +
        "# (a prime drop's merge raises it, in its own commit). Written by kickoff.pl scaffold.`n"); $made += '.ci/outline-max'
    if (Test-Path -LiteralPath $model) {
        $dr = KoRun $model @('--root', $dir, 'docs') $null
        if ($dr[0]) { KoDie ("kickoff: model.ps1 docs failed on the new repository: " + $dr[1] + "`n") }
        foreach ($g in @('Nouns.md', 'Verbs.md', 'Traceability.md')) { if (Test-Path -LiteralPath (Join-Path $dir "docs/$g")) { $made += "docs/$g (generated)" } }
    } else { KoOut "kickoff: sysml\model.ps1 is not in the kit here: .ci/outline-max counts 0 and docs/ is not generated (run model.cmd docs later)`n" }
    $r = KoPgit $dir @('init', '-q', '-b', 'main'); if ($r[0]) { KoDie "kickoff: pgit init failed: $($r[1])`n" }
    $null = KoPgit $dir @('config', 'core.autocrlf', 'false')
    $r = KoPgit $dir @('add', '-A'); if ($r[0]) { KoDie "kickoff: pgit add failed: $($r[1])`n" }
    $tempWho = @()                                # no global identity: a one-commit local one (pgit has no -c), removed after
    if ($null -eq (KoGlobalCfg 'user.name')) { $null = KoPgit $dir @('config', 'user.name', 'kickoff'); $tempWho += 'user.name' }
    if ($null -eq (KoGlobalCfg 'user.email')) { $null = KoPgit $dir @('config', 'user.email', 'kickoff@example.invalid'); $tempWho += 'user.email' }
    $r = KoPgit $dir @('commit', '-q', '-m', "Scaffold the $title model repository (kickoff.pl)")
    foreach ($k in $tempWho) { $null = KoPgit $dir @('config', '--unset', $k) }
    if ($r[0]) { KoDie "kickoff: pgit commit failed: $($r[1])`n" }
    $sorted = [string[]]$made; [Array]::Sort($sorted, [StringComparer]::Ordinal)
    $t = "made $dir (pgit, branch main, 1 commit):`n"
    foreach ($m in $sorted) { $t += "  $m`n" }
    $t += 'level tags: ' + ($levels -join ', ') + " -- to rename them, edit model/library/conventions/Conventions.sysml and`n  level_tags in sysml.conf together (they must match)`n"
    $t += "next:`n  edit .gitlab/project.conf (members, labels, sprints), README.md and sysml.conf for your project`n"
    $t += "  kickoff.cmd start --dir $dir ...   (or the steps by hand: kickoff.cmd help start)`n"
    KoOut $t
    return 0
}

# ---------------------------------------------------------------- start
function KoConfMembers([string]$f) {
    $t = KoSlurp $f; if ($null -eq $t) { return , @() }
    $sec = ''; $m = @()
    foreach ($l in ($t -split "`n")) {
        $l = $l -creplace '\s+[;#].*$', ''; $l = $l -creplace '^\s+|\s+$', ''
        if ($l -ceq '' -or $l -cmatch '^[;#]') { continue }
        if ($l -cmatch '^\[(.+)\]$') { $sec = $Matches[1]; continue }
        if ($sec -ceq 'members' -and $l -cmatch '^(\S+)\s*=\s*(\S+)') { $m += , @($Matches[1], $Matches[2]) }
    }
    return , $m
}
function KoConfValue([string]$f, [string]$sec, [string]$key) {
    $t = KoSlurp $f; if ($null -eq $t) { return $null }
    $in = ''
    foreach ($l in ($t -split "`n")) { $l = $l -creplace '\s+;.*$', ''; if ($l -cmatch '^\s*\[(.+)\]\s*$') { $in = $Matches[1]; continue }; if ($in -ceq $sec -and $l -cmatch ('^\s*' + [regex]::Escape($key) + '\s*=\s*(\S+)')) { return $Matches[1] } }
    return $null
}
function KoWithout([string]$f, [string]$drop) {
    $in = ''; $out = ''
    foreach ($l in ([regex]::Split((KoSlurp $f), '(?<=\n)'))) { if ($l -cmatch '^\s*\[(.+)\]\s*$') { $in = $Matches[1] }; if ($in -cne $drop) { $out += $l } }
    return $out
}
function KoStart($o) {
    $yes = [bool]$o.yes
    if (-not $o.local -and -not $o.url) { KoDie "kickoff: no --local DIR or --url URL (or GITLAB_URL): which GitLab?`n" }
    $repo = if ($o.dir) { $o.dir } else { 'model' }
    $title = if ($o.title) { $o.title } else { 'Tidewater' }
    $journal = if ($o.journal) { $o.journal } else { 'journal' }
    $team = if ($o.team) { $o.team } else { 'Model' }
    if ($o.local -and $o.local -cnotmatch '^(?:[A-Za-z]:[\\/]|[\\/])') { $o.local = Join-Path (Get-Location).Path $o.local }   # steps run in other folders
    $glArgs = @(); if ($o.local) { $glArgs += @('--local', $o.local) }; if ($o.url) { $glArgs += @('--url', $o.url) }; if ($o.token_env) { $glArgs += @('--token-env', $o.token_env) }
    $script:KO_CONF = $null; $script:KO_PROJECT = $o.project; $script:KO_AS = $null
    $resolve = {
        $c = if ($o.conf) { $o.conf } elseif (Test-Path -LiteralPath (Join-Path $repo '.gitlab/project.conf')) { Join-Path $repo '.gitlab/project.conf' } else { Join-Path $script:KO_TPL 'project.conf' }
        $script:KO_CONF = $c
        $script:KO_PROJECT = if ($o.project) { $o.project } else { $v = KoConfValue $c 'project' 'path'; if ($v) { $v } else { 'tidewater/model' } }
        $as = $o.as
        if (-not $as) { foreach ($m in (KoConfMembers $c)) { if ($m[1] -cmatch '^(maintainer|owner)$') { $as = $m[0]; break } } }
        if (-not $as) { $as = $env:GITLAB_USER }; if (-not $as) { $as = 'root' }
        $script:KO_AS = $as
    }
    $gl = { param([string[]]$rest) return , (@(KoTool 'gitlab.ps1') + @($glArgs) + @('--project', $script:KO_PROJECT, '--as', $script:KO_AS) + @($rest)) }
    $steps = @()
    $steps += , @{ title = 'Check this PC'; why = 'a missing tool or setting is cheaper to fix now than in the middle of a sprint'; allow_fail = $true
        cmds = { , @(, (@((Join-Path $script:KO_HERE 'kickoff.ps1'), 'doctor', '--quick') + @($glArgs))) } }
    $steps += , @{ title = 'Make the model repository'; why = 'the templates give the pipeline, the review rules and the issue templates from day one'
        skip = { if (Test-Path -LiteralPath (Join-Path $repo '.git')) { "$repo already exists" } else { $null } }
        cmds = { , @(, @((Join-Path $script:KO_HERE 'kickoff.ps1'), 'scaffold', $repo, '--project', $script:KO_PROJECT, '--title', $title)) } }
    $steps += , @{ title = 'Create the GitLab project from the project file (schedules come later: they need develop)'; why = 'settings, members, labels, sprints and branch protection as a reviewed file, not clicks'
        conf_without = 'schedules'; cmds = { , @(, (& $gl @('setup', $script:KO_TMPCONF))) } }
    $steps += , @{ title = 'Push the scaffold to main'; why = "the first commit is the project's starting point; everything after it arrives by merge request"
        needs_git = "pushing needs git. On a PC with git, from $repo`: git remote add origin <the project's clone URL>; git push -u origin main" }
    $steps += , @{ title = 'Start gitflow: develop from main'; why = 'develop is where work lands; main only takes baselines'
        needs_git = "develop on the server comes with the push: gitflow.cmd init makes it here (in $repo), and git push -u origin develop sends it" }
    $steps += , @{ title = 'Apply the whole project file again (now with the schedules)'; why = 'setup is safe to re-run: it updates what differs'
        cmds = { , @(, (& $gl @('setup', $script:KO_CONF))) } }
    $steps += , @{ title = 'Sprints as milestones'; why = 'each two-week sprint is a GitLab milestone that issues and MRs belong to'
        skip = { if ($o.sprints) { $null } else { "the project file's [milestones] made them (or pass --sprints START COUNT)" } }
        cmds = { , @(, (& $gl (@('sprints') + @($o.sprints)))) } }
    $steps += , @{ title = 'Make the journal and the roster'; why = "stand-ups, sprints and stories are recorded in the kit's journal; tasks stay in GitLab"
        skip = { if (Test-Path -LiteralPath (Join-Path $journal 'scrum.conf')) { "$journal already holds a journal" } else { $null } }
        cmds = { $c = @(, @((KoTool 'agile.ps1'), 'init', $journal))
            foreach ($m in (KoConfMembers $script:KO_CONF)) { $u = $m[0]; $c += , @("@dir=$journal", (KoTool 'agile-more.ps1'), 'roster', 'add', ($u.Substring(0, 1).ToUpperInvariant() + $u.Substring(1)), "$u@example.invalid", $team, ($m[1].Substring(0, 1).ToUpperInvariant() + $m[1].Substring(1)), 'Government') }
            , $c } }
    $steps += , @{ title = 'Wiki pages: Home, Definition of Ready and Done, Gitflow, Onboarding, ...'; why = 'the working agreements live where everyone looks'
        skip = { if ($o.no_wiki) { '--no-wiki' } else { $null } }
        cmds = { $c = @(); $names = @(); foreach ($f in (Get-ChildItem -LiteralPath (Join-Path $script:KO_TPL 'wiki') -Filter '*.md')) { $names += $f.Name }
            $names = [string[]]$names; [Array]::Sort($names, [StringComparer]::Ordinal)
            foreach ($f in $names) { $c += , (& $gl @('wiki', 'put', ($f -creplace '\.md$', ''), (Join-Path (Join-Path $script:KO_TPL 'wiki') $f))) }
            , $c } }
    $steps += , @{ title = 'The first stories, from the Story template'; why = 'sprint 1 starts with work already written down, each with its acceptance criteria'
        skip = { if ($o.no_issues) { '--no-issues' } else { $null } }; dir = $repo
        cmds = { $c = @(); foreach ($t in @('Create the GitLab project and protect its branches', 'First pipeline gates every merge request', 'Receive the first prime drop and record it', 'Convert the first drop and assess it', 'Working agreements: Definition of Ready and Done')) { $c += , (& $gl @('issue', 'new', $t, '--template', 'Story', '--milestone', 'Sprint 1', '--assign', $script:KO_AS)) }; , $c } }

    KoOut $(if ($yes) { "kickoff: week zero, running each step`n" } else { "kickoff: week zero, the plan (nothing runs without --yes)`n" })
    $n = 0; $notrun = 0
    foreach ($s in $steps) {
        $n++
        KoOut "`n== step ${n}: $($s.title)`n   why: $($s.why)`n"
        $skip = $null; if ($s.skip) { $skip = & $s.skip }
        if ($skip) { KoOut "   skipped: $skip`n"; continue }
        if ($o.from -and $n -lt [int]$o.from) { KoOut "   skipped: before --from $($o.from)`n"; continue }
        & $resolve
        if ($s.needs_git) { KoOut "   not run: $($s.needs_git)`n"; $notrun++; continue }
        if ($s.conf_without) {
            $tmp = Join-Path $(if ($env:TEMP) { $env:TEMP } else { '.' }) ('kickoff-' + (Get-Random -Maximum 999999) + '.conf')
            KoSpew $tmp (KoWithout $script:KO_CONF $s.conf_without)
            $script:KO_TMPCONF = $tmp
        }
        $cmds = & $s.cmds
        foreach ($c0 in $cmds) {
            $cdir = $s.dir; $c = $c0                  # an entry may start with @dir=PATH: that command runs in PATH (tools with a param block read their folder)
            if ([string]$c0[0] -cmatch '^@dir=(.*)$') { $cdir = $Matches[1]; $c = @(); for ($k = 1; $k -lt $c0.Count; $k++) { $c += $c0[$k] } }
            $shown = KoShow $c
            if ($s.conf_without) { $shown = $shown.Replace($script:KO_TMPCONF, $script:KO_CONF) + "   (a copy without [$($s.conf_without)])" }
            KoOut ('   $ ' + $(if ($cdir) { "(in $cdir) " } else { '' }) + $shown + "`n")
            if (-not $yes) { continue }
            $argv = @(); for ($k = 1; $k -lt $c.Count; $k++) { $argv += [string]$c[$k] }
            $r = KoRun $c[0] $argv $(if ($cdir) { $cdir } else { $null })
            if ($r[1]) { foreach ($l in ($r[1] -split "`n")) { KoOut "   | $l`n" } }
            if ($r[0] -and -not $s.allow_fail) {
                KoOut "kickoff: step $n failed (exit $($r[0])). Fix what it says, then carry on from this step:`n         kickoff.cmd start --yes --from $n (the same options as before)`n"
                return 1
            }
            if ($r[0] -and $s.allow_fail) { KoOut "   (doctor found problems: fix them soon; continuing)`n" }
        }
    }
    KoOut ("`nkickoff: " + $(if ($yes) { 'week zero is set up' + $(if ($notrun) { " here; $notrun step(s) need git on another PC (printed above as not run)." } else { '.' }) } else { 'that is the plan; run again with --yes to do it.' }) + "`n")
    if ($yes) { KoOut "next: the sprint 1 kickoff -- agile.cmd -Conf $journal\scrum.conf new; the board at the project's Issues > Boards`n" }
    return 0
}

# ---------------------------------------------------------------- main
function KoOpts($argv, [string[]]$valued, [string[]]$flags) {
    $o = @{}; $rest = @()
    for ($i = 0; $i -lt $argv.Count; $i++) {
        $a = [string]$argv[$i]
        if ($a -cmatch '^--([\w-]+)(?:=(.*))?$') {
            $k = $Matches[1]; $v = $Matches[2]; $key = $k.Replace('-', '_')
            if ($k -ceq 'sprints') { $o.sprints = @([string]$argv[$i + 1], [string]$argv[$i + 2]); $i += 2; continue }
            if ($valued -ccontains $k) { if ($null -eq $v) { $i++; if ($i -ge $argv.Count) { KoDie "Option $k requires an argument`n" }; $v = [string]$argv[$i] }; $o[$key] = $v; continue }
            if ($flags -ccontains $k) { $o[$key] = $true; continue }
            KoDie "Unknown option: $k`nusage: kickoff.cmd doctor|scaffold|start|help [COMMAND]  (kickoff.cmd help COMMAND)`n"
        }
        $rest += $a
    }
    $o.rest = $rest
    return $o
}
function KoMain($argv) {
    $cmd = if ($argv.Count) { [string]$argv[0] } else { '' }
    $a = @(); for ($i = 1; $i -lt $argv.Count; $i++) { $a += $argv[$i] }
    if ($cmd -cmatch '^(help|--help|-h|-Help)$') {
        if ($a.Count -and $script:KO_HELP.ContainsKey([string]$a[0])) { KoOut $script:KO_HELP[[string]$a[0]]; return 0 }
        KoOut ("kickoff.ps1 -- week zero for a model team (tools/gitlab/kickoff.pl, for a PowerShell-only PC)`n`n" + $script:KO_HELP.doctor + "`n" + $script:KO_HELP.scaffold + "`n" + $script:KO_HELP.start + "`n")
        return 0
    }
    if ($cmd -ceq 'doctor') { return (KoDoctor (KoOpts $a @('local', 'url', 'token-env') @('quick', 'fix'))) }
    if ($cmd -ceq 'scaffold') {
        $o = KoOpts $a @('project', 'title', 'noun-root', 'verb-root', 'levels', 'layout-map') @('force')
        if ($o.layout_map -and -not (Test-Path -LiteralPath $o.layout_map -PathType Leaf)) { KoDie "kickoff: no layout map $($o.layout_map) (write it first, or leave --layout-map out: the new repository's .ci/layout.map.example explains the format)`n" }
        if ($null -ne $o.levels) {
            $l = @(); foreach ($x in ($o.levels -split ',')) { $x = $x.Trim(); if ($x.Length) { $l += $x } }
            $bad = $l.Count -eq 0; foreach ($x in $l) { if ($x -cnotmatch '^[A-Za-z_]\w*$') { $bad = $true } }
            if ($bad) { KoDie "kickoff: --levels is a comma list of names, top level first (e.g. L1Network,L2Segment,L3Station)`n" }
            $o.levels = $l
        }
        if (-not $o.rest.Count) { KoDie "kickoff: scaffold needs a DIR`n" }
        return (KoScaffold $o.rest[0] $o)
    }
    if ($cmd -ceq 'start') {
        $o = KoOpts $a @('local', 'url', 'token-env', 'project', 'title', 'conf', 'dir', 'journal', 'team', 'as', 'from', 'layout-map') @('yes', 'no-wiki', 'no-issues')
        if (-not $o.local -and -not $o.url -and $env:GITLAB_URL) { $o.url = $env:GITLAB_URL }
        return (KoStart $o)
    }
    KoOut "usage: kickoff.cmd doctor|scaffold|start|help [COMMAND]  (kickoff.cmd help COMMAND)`n"
    return 2
}

if ($args.Count -and [string]$args[0] -ceq '__lib') { return }
$rc = 2
try { $rc = KoMain @($args) }
catch { $m = [string]$_.Exception.Message; if ($m.StartsWith('KODIE:')) { KoOut $m.Substring(6) } else { KoOut ("kickoff: " + $m + "`n") }; $rc = 2 }
exit $rc
