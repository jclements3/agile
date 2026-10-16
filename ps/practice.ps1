<#
practice.ps1 -- the agile kit's hands-on practice lessons for Windows PowerShell 5.1 (Constrained Language Mode safe).

A fresh sandbox per lesson, the task printed, and a check of your result against the journal and the files, as
the Perl kit's lib/Practice.pm does. The sandboxes are built from ps\practice\templates (the kit generators' raw
output, made once by practice\build-templates.sh) with today's dates, so no Perl is needed here.

  practice.cmd                       list the lessons
  practice.cmd N                     set up .\practice\lessonN (wiping an old one) and print the task
  practice.cmd check N               what is done, what is missing; exit 0 when the lesson is done
  practice.cmd reset N               remove the sandbox
  options: -Dir DIR (sandboxes there instead of .\practice), -Today YYYY-MM-DD (the sandbox's "today")

Lessons 9, 11, 12 and 13 are not here: 9 is a Perl coding drill, and 11-13 run against the Perl kit's offline
GitLab (lib/GitLab.pm), which has no PowerShell port.
#>
param(
    [Parameter(Position = 0)][string]$Verb,
    [Parameter(Position = 1)][string]$Num,
    [string]$Dir, [string]$Today, [switch]$Help
)
$PR = @{ verb = $Verb; num = $Num; dir = $Dir; today = $Today; help = [bool]$Help }   # saved: agile.ps1's param block resets these
$ErrorActionPreference = 'Stop'
$script:TOOLS = $PSScriptRoot
if (-not $script:TOOLS) { $script:TOOLS = (Get-Location).Path }
. "$($script:TOOLS)\agile.ps1" __lib                   # the journal parser (LoadScrum, SprintSummary, Pending ...)
$script:TPL = Join-Path $script:TOOLS 'practice\templates'
$script:PGIT = Join-Path $script:TOOLS 'pgit.ps1'
$script:PRC = 0

# ================================================================ the lessons
$script:LESSONS = @(
    @{ n = 1; kind = 'empty'; title = 'Lesson 1: the first stand-up file and compile' },
    @{ n = 2; kind = 'halberd'; title = 'Lesson 2: carry, block and unblock' },
    @{ n = 3; kind = 'halberd'; title = 'Lesson 3: close the sprint and report' },
    @{ n = 4; kind = 'dronecorp'; title = 'Lesson 4: the townhall chat lint'; chat = $true },
    @{ n = 5; kind = 'dronecorp'; title = 'Lesson 5: the memory drill' },
    @{ n = 6; kind = 'idef0'; title = 'Lesson 6: IDEF0 lint, fix, plates' },
    @{ n = 7; kind = 'halberd'; title = 'Lesson 7: a status memo'; memo = $true },
    @{ n = 8; kind = 'sysml'; title = 'Lesson 8: port a segment to SysML v2' },
    @{ n = 10; kind = 'tw-model'; title = 'Lesson 10: your first model change' }
)
$script:NOT_HERE = @{
    9  = 'a Perl coding drill (drills/drill.pl): there is no Perl on this PC'
    11 = "it runs against the Perl kit's offline GitLab (lib/GitLab.pm), which has no PowerShell port"
    12 = "it runs against the Perl kit's offline GitLab (lib/GitLab.pm), which has no PowerShell port"
    13 = "it runs against the Perl kit's offline GitLab (lib/GitLab.pm), which has no PowerShell port"
}
function Lesson([int]$n) { foreach ($l in $script:LESSONS) { if ($l.n -eq $n) { return $l } }; $null }

$script:TEXT = @{}
$script:TEXT[1] = @'
Sandbox: a new, empty project (agile.cmd init).
Task:
1. Make today's file: agile.cmd new (then open it: pvi.cmd standups\DATE.txt, or Notepad).
2. Under its "sprint 1" line add a team and three tasks, and commit two of
   them with a capacity:
    == Alpha
    cap 10
    new AL-1 3 Set up the build p:1 e:"A1 Tooling" o:"Ann Lee"
    new AL-2 5 Write the ICD p:2 e:"A1 Tooling" o:"Bob Ray"
    new AL-3 2 Draft the test plan p:3 e:"A1 Tooling" o:"Ann Lee"
    commit AL-1 Ann Lee
    commit AL-2 Bob Ray
3. agile.cmd compile -Dry until it is clean, then agile.cmd compile.
4. agile.cmd status, agile.cmd sprint, then agile.cmd commit.
Check: three or more tasks in the journal, two or more committed in sprint
1, a capacity for sprint 1, no pending stand-up file, and a pgit commit.
'@
$script:TEXT[2] = @'
Sandbox: a copy of the Halberd project, mid-sprint, compiled up to
yesterday.
Task:
1. agile.cmd sprint: note the open tasks of the current sprint.
2. In today's file (agile.cmd new), block the oldest open task with a
   reason: block HAL-N waiting on the shared runner. Compile.
3. Make a second file for today, standups\DATE-b.txt, with the same first
   two lines (the date, sprint N) and "== Halberd". In it: unblock that
   task, and carry another open task. Compile.
4. agile.cmd blocked (now empty), agile.cmd commit.
Check: today a task was blocked with a reason and unblocked again, a task
went to Carryover today, nothing pending, and a commit after the set-up.
'@
$script:TEXT[3] = @'
Sandbox: a copy of the Halberd project, mid-sprint.
Task: close the current sprint as on Day 14.
1. agile.cmd sprint: every open task.
2. In today's file (agile.cmd new) mark each one done or carry, compile.
3. agile-more.cmd review, agile.cmd report, agile.cmd commit.
Check: no open points left in the current sprint,
reports\sprint-N-report.txt and reports\DATE-status.html exist, nothing
pending, a commit after the set-up.
'@
$script:TEXT[4] = @'
Sandbox: the DroneCorp backlog planned yesterday, with today's chat pasted
in standups\DATE-chat.txt (a rehearsal chat, mistakes seeded). The answer
key is in .answer-key.txt; read it after you try.
Task:
1. agile.cmd lint: who has an ERROR and why?
2. agile.cmd lint -Reply: the replies you would post.
3. For each ERROR, add a corrected repost at the end of the chat file, as
   the person would post it: a line "[9:01 AM] Name" then their status
   "Y ... T ... B none" with their task ids. Their last message wins.
4. agile.cmd lint again until there is no ERROR, then agile.cmd answers.
Check: lint finds no ERROR in today's chat, and today's answers file exists.
In the townhall console (townhall.cmd) the same is P (paste) and L (lint).
'@
$script:TEXT[5] = @'
Sandbox: the DroneCorp project.
Task:
1. drill.cmd -Sheet Contracting (or :SDrill Contracting in pvi).
2. Open the sheet it names; answer at least six cards after the ">" marks:
   ids, codes, initials. Look things up with agile.cmd backlog Contracting
   and agile.cmd members Contracting first if you like: that is reading,
   the drill is recall.
3. Grade it: drill.cmd -Grade reports\DATE-drill.txt (or :w in pvi).
Check: drill.txt holds at least six graded cards and at least one right.
'@
$script:TEXT[6] = @'
Sandbox: model\, a five-model IDEF0 project with errors seeded in
model\design.txt.
Task:
1. idef0.cmd lint (Resolve-Path model\*.txt -Relative)
2. Fix every error (a tab where two spaces belong, a port arrow pointing
   the wrong way, and the others idef0.cmd lint names) until lint says
   0 error(s). Edit with pvi.cmd model\design.txt or Notepad.
3. The plates:
    idef0.cmd html (Resolve-Path model\*.txt -Relative) | Out-File -Encoding utf8 plates.html
    idef0.cmd text (Resolve-Path model\*.txt -Relative) | Out-File -Encoding utf8 plates.txt
Check: lint reports no errors, and plates.html holds SVG plates newer than
every model file.
'@
$script:TEXT[7] = @'
Sandbox: the Halberd project and memo.md, a memo with TODO marks.
Task:
1. agile.cmd status and agile-more.cmd quad for the facts.
2. Replace every TODO in memo.md; say which sprint this is ("sprint N").
3. md2docx.cmd memo.md -Out memo.docx
   md2docx.cmd memo.md -Text -Out memo.txt
Check: no TODO left, the current sprint number named, memo.docx is a Word
file newer than memo.md, and memo.txt exists.
'@
$script:TEXT[8] = @'
Sandbox: legacy.xmi (a small Cameo export) and an empty model repository
(pgit init) with a sysml.conf.
Task:
1. xmi2sysml.cmd --report legacy.xmi: how many elements are left as TODO?
2. xmi2sysml.cmd --out model --check legacy.xmi
3. sysml.cmd check (Resolve-Path model\*\*.sysml -Relative)
4. Work the TODO lines:
    Get-ChildItem model -Recurse -Filter *.sysml | Select-String '// TODO'
   For each one either model the element by hand or keep the line and mark
   it reviewed by changing "// TODO" to "// TODO(reviewed)". Write in
   NOTES.txt one line, "TODO: N", N being the number of TODO lines left
   (count the lines, not the report's figure).
5. pgit.cmd add model NOTES.txt, pgit.cmd commit -m "port: legacy.xmi".
Check: .sysml files under model\, sysml check passes, every TODO line is
fixed or marked TODO(reviewed), NOTES.txt says how many are left (and the
number is right), and the work is committed.
'@
$script:TEXT[10] = @'
Lessons 10-13 follow Tidewater, a fictional coastal weather network: the
prime contractor keeps its SysML v1 model in Cameo and delivers it as
drops; the government team (Jim, Bob, Tom) keeps a SysML v2 text copy.
Sandbox: the model repository a team gets in week zero, with drop v1.0
converted into it by the layout map .ci\layout.map (each package at a fixed
path, in every drop). model\library\conventions\Conventions.sysml holds the
government's level tags; .ci\outline-max records the outline findings drop
v1.0 brought with it. You are Bob, the MBSE engineer. About 30 minutes.
Task:
1. Look around (a configuration item's folders and its history):
    ls model, model\physical
    pgit.cmd log --oneline
2. Count the TODO lines the converter left: the port's open action items.
    Get-ChildItem model -Recurse -Filter *.sysml | Select-String '// TODO' | Measure-Object
3. pvi.cmd model\physical\stations\Stations.sysml, then /StationSegment
   and n until you are on "part def StationSegment {". The next line is a
   TODO: in v1 a profile stereotype said StationSegment is level 2.
4. Replace that whole line with (in pvi's ex mode: .+1c, the line, then a
   line holding only a dot):
        @L2Segment;
   The tag is the v2 form of the stereotype: metadata defined once in
   model\library\conventions\Conventions.sysml, one line in place of a
   profile.
5. Under the line "package Stations {" add the import that makes the tags
   visible here, then :w
        private import Conventions::*;
6. Check it as a reviewer would:
    sysml.cmd check model\physical\stations\Stations.sysml   (the grammar)
    model.cmd lint      (the whole model: 0 errors, 0 warnings)
    model.cmd check     (outline and level tags: "@L tag mismatches 0";
                         the 20 outline findings are the ones drop v1.0
                         brought)
   Lint does not catch a misspelled tag (@L2Segmnt;); practice check 10
   does.
7. Record the change with its reason (a configuration change, signed):
    pgit.cmd add model
    pgit.cmd commit -m "Tag StationSegment with its level (L2Segment)"
Check: StationSegment carries @L2Segment; and no TODO, package Stations
imports Conventions, the grammar check and lint pass, every level tag sits
at its level, and the change is committed.
'@

# ================================================================ small helpers
function POut([string]$t) { Write-Output ($t -replace "`n$", '') }
function PErr([string]$t) { Write-Host $t }                                   # the console, like Perl's STDERR
function Norm([string]$p) { $p -replace '/', '\' }
function Abs([string]$p) {
    if ([string]::IsNullOrEmpty($p)) { return (Get-Location).Path }
    if ($p -match '^[A-Za-z]:\\' -or $p -match '^\\\\') { return $p }
    Join-Path (Get-Location).Path $p
}
function PRead([string]$path) {                     # file bytes as a string, one char per byte (dates are ASCII)
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $null }
    $b = Get-Content -LiteralPath $path -Encoding Byte -ReadCount 0
    if ($null -eq $b) { return '' }
    -join @(foreach ($x in $b) { [char]$x })
}
function PWrite([string]$path, [string]$s) {        # the reverse of PRead: the same bytes back
    $d = Split-Path -Parent $path
    if ($d -and -not (Test-Path -LiteralPath $d -PathType Container)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
    if ($s.Length -eq 0) { Set-Content -LiteralPath $path -Value ([byte[]]@()) -Encoding Byte; return }
    $bytes = [byte[]]@(foreach ($c in $s.ToCharArray()) { [int]$c })
    Set-Content -LiteralPath $path -Value $bytes -Encoding Byte
}
function PCopy([string]$from, [string]$to) {
    $d = Split-Path -Parent $to
    if ($d -and -not (Test-Path -LiteralPath $d -PathType Container)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
    Copy-Item -LiteralPath $from -Destination $to -Force
}
function DayNum([string]$d) { [int](([datetime]$d) - ([datetime]'2000-01-03')).Days }     # 2000-01-03 is a Monday
function NumDay([int]$n) { ([datetime]'2000-01-03').AddDays($n).ToString('yyyy-MM-dd') }
function PrevWeekday([string]$d) {
    $n = (DayNum $d) - 1
    while ((($n % 7) + 7) % 7 -ge 5) { $n-- }
    NumDay $n
}
function FloorDiv([int]$a, [int]$b) { [int](($a - ((($a % $b) + $b) % $b)) / $b) }    # floor, also for negative a
function RealToday { (Get-Date).ToString('yyyy-MM-dd') }

function Run([string]$cwd, [string]$script, [string[]]$a, [hashtable]$named = @{}) {     # (rc, output text) of a sibling tool, run in $cwd
    Push-Location -LiteralPath $cwd
    try {
        $global:LASTEXITCODE = 0
        $o = & $script @a @named 2>&1
        $rc = $LASTEXITCODE; if ($null -eq $rc) { $rc = 0 }
    } catch { $o = @("$($_.Exception.Message)"); $rc = 1 }
    finally { Pop-Location }
    $txt = (@($o | ForEach-Object { "$_" }) -join "`n")
    @{ rc = [int]$rc; out = $txt }
}
function Tool([string]$name) { Join-Path $script:TOOLS $name }
function Agile([string]$sbx, [string[]]$a, [string]$day) { $nmd = @{ Conf = (Join-Path $sbx 'scrum.conf') }; if ($day) { $nmd['Today'] = $day }; Run $sbx (Tool 'agile.ps1') $a $nmd }
function Pgit([string]$sbx, [string[]]$a) {          # pgit in the sandbox only: never climbs into a repository above it
    if ($a[0] -cne 'init' -and -not (Test-Path -LiteralPath (Join-Path $sbx '.git') -PathType Container)) { return @{ rc = 128; out = "practice: $sbx has no .git" } }
    $keep = Get-Item -LiteralPath 'env:GIT_CEILING_DIRECTORIES' -ErrorAction SilentlyContinue
    $env:GIT_CEILING_DIRECTORIES = (Split-Path -Parent ((Resolve-Path -LiteralPath $sbx).Path))
    try { Run $sbx $script:PGIT $a }
    finally { if ($keep) { $env:GIT_CEILING_DIRECTORIES = $keep.Value } else { Remove-Item -LiteralPath 'env:GIT_CEILING_DIRECTORIES' -ErrorAction SilentlyContinue } }
}
function PgitAs([string]$sbx, [string]$name, [string]$email, [string[]]$a) {
    $keep = @{}
    foreach ($k in @('GIT_AUTHOR_NAME', 'GIT_AUTHOR_EMAIL', 'GIT_COMMITTER_NAME', 'GIT_COMMITTER_EMAIL')) { $v = Get-Item -LiteralPath "env:$k" -ErrorAction SilentlyContinue; $keep[$k] = $null; if ($v) { $keep[$k] = $v.Value } }
    $env:GIT_AUTHOR_NAME = $name; $env:GIT_COMMITTER_NAME = $name; $env:GIT_AUTHOR_EMAIL = $email; $env:GIT_COMMITTER_EMAIL = $email
    try { Pgit $sbx $a } finally {
        foreach ($k in $keep.Keys) { if ($null -eq $keep[$k]) { Remove-Item -LiteralPath "env:$k" -ErrorAction SilentlyContinue } else { Set-Item -LiteralPath "env:$k" -Value $keep[$k] } }
    }
}
function GitCommit([string]$sbx, [string]$msg, [string]$name = 'practice', [string]$email = 'practice@localhost') {   # add -A, commit, the new HEAD
    $null = Pgit $sbx @('add', '-A')
    $null = PgitAs $sbx $name $email @('commit', '-q', '-m', $msg)
    $r = Pgit $sbx @('rev-parse', 'HEAD')
    if ($r.rc) { return '' }
    $r.out.Trim()
}
function HasIdentity([string]$sbx) { $r = Pgit $sbx @('config', 'user.name'); ($r.rc -eq 0 -and $r.out -match '\S') }

# ================================================================ set-up
function InitProject([string]$sbx) {
    $r = Run (Split-Path -Parent $sbx) (Tool 'agile.ps1') @('init', $sbx)
    if ($r.rc) { throw "practice: agile.ps1 init failed: $($r.out)`n" }
    PWrite (Join-Path $sbx '.gitignore') "reports/`n.practice`n"
    $r = Pgit $sbx @('init', '-q')
    if ($r.rc) { throw "practice: pgit init failed: $($r.out)`n" }
}
function SetupHalberd([string]$sbx, [string]$day, $info) {      # the Halberd journal, shifted by whole weeks so today is day 4 of sprint 2
    $src = Join-Path $script:TPL 'halberd'
    $files = (Sorted @(Get-ChildItem -LiteralPath (Join-Path $src 'standups') -File | ForEach-Object { $_.Name } | Where-Object { $_ -cmatch '^\d{4}-\d{2}-\d{2}(?:\.txt|-\w+-answers\.txt)$' }))
    $sprint = @{}
    foreach ($f in $files) {
        if ($f -cnotmatch '^\d{4}-\d{2}-\d{2}\.txt$') { continue }
        $t = PRead (Join-Path $src "standups\$f")
        if ($t -cmatch '(?m)^sprint (\d+)$') { $sprint[$f.Substring(0, 10)] = [int]$Matches[1] }
    }
    $s2 = (Sorted @($sprint.Keys | Where-Object { $sprint[$_] -eq 2 }))
    if ($s2.Count -lt 4) { throw "practice: the Halberd journal has no sprint 2`n" }
    $diff = (DayNum $day) - (DayNum $s2[3])
    $shift = 7 * (FloorDiv $diff 7)
    InitProject $sbx
    foreach ($f in @('scrum.conf', 'roster.txt')) { if (Test-Path -LiteralPath (Join-Path $src $f)) { PCopy (Join-Path $src $f) (Join-Path $sbx $f) } }
    PWrite (Join-Path $sbx 'scrum.txt') "; practice copy of the Halberd journal (sim/halberd-gen.pl), dates moved so today is mid-sprint`n"
    $last = $null
    foreach ($f in $files) {
        $d = NumDay ((DayNum $f.Substring(0, 10)) + $shift)
        if (-not (SLt $d $day)) { continue }
        $t = PRead (Join-Path $src "standups\$f")
        $t = $t -creplace '^# compiled [^\n]*\n', ''
        $t = $t -creplace '^\d{4}-\d{2}-\d{2}', $d
        $nf = $d + $f.Substring(10)
        PWrite (Join-Path $sbx "standups\$nf") $t
        if ($f -cmatch '^\d{4}-\d{2}-\d{2}\.txt$') { $last = $d }
    }
    if ($null -eq $last) { throw "practice: no Halberd stand-up falls before $day`n" }
    $r = Agile $sbx @('compile') $last
    if ($r.rc) { throw "practice: compiling the Halberd copy failed: $($r.out)`n" }
    $s = LoadScrum (Join-Path $sbx 'scrum.txt') $day $null
    $info.sprint = "$($s.current)"
    $info.notes += "The journal runs to $last; today ($day) is in sprint $($s.current)."
}
function SetupDronecorp([string]$sbx, [string]$day, $info, [bool]$chat) {   # DroneCorp planned on the previous weekday; a seeded chat for today
    $src = Join-Path $script:TPL 'dronecorp'
    InitProject $sbx
    $d0 = PrevWeekday $day
    $plan = (PRead (Join-Path $src 'plan.txt')) -creplace '^DATE', $d0
    PWrite (Join-Path $sbx "standups\$d0.txt") $plan
    PCopy (Join-Path $src 'roster.txt') (Join-Path $sbx 'roster.txt')
    $conf = PRead (Join-Path $sbx 'scrum.conf')
    $conf = $conf -creplace '(?m)^facilitator\s*=.*$', 'facilitator       = Sam Archer       # the facilitator in the rehearsal chat'
    $conf = $conf -creplace '(?m)^(standup_match.*)$', ("calendar          = mock`n" + '$1')
    PWrite (Join-Path $sbx 'scrum.conf') $conf
    $r = Agile $sbx @('compile') $d0
    if ($r.rc) { throw "practice: compiling the DroneCorp plan failed: $($r.out)`n" }
    if ($chat) {
        $null = GitCommit $sbx 'practice: the plan'
        PCopy (Join-Path $src 'chat.txt') (Join-Path $sbx "standups\$day-chat.txt")
        PCopy (Join-Path $src 'answer-key.txt') (Join-Path $sbx '.answer-key.txt')
        $info.notes += "Today's chat: standups\$day-chat.txt (the answer key: .answer-key.txt -- read it after you try)."
    }
    $info.notes += "Sprint 1 was planned on $d0 for ten teams."
}
function SetupIdef0([string]$sbx, $info) {
    foreach ($f in @(Get-ChildItem -LiteralPath (Join-Path $script:TPL 'idef0\model') -File)) { PCopy $f.FullName (Join-Path $sbx "model\$($f.Name)") }
    $info.notes += 'Lint: idef0.cmd lint (Resolve-Path model\*.txt -Relative)   (edit: pvi.cmd model\design.txt, or Notepad)'
}
function SetupSysml([string]$sbx, $info) {
    $src = Join-Path $script:TPL 'sysml'
    PCopy (Join-Path $src 'legacy.xmi') (Join-Path $sbx 'legacy.xmi')
    $r = Pgit $sbx @('init', '-q')
    if ($r.rc) { throw "practice: pgit init failed: $($r.out)`n" }
    PWrite (Join-Path $sbx '.gitignore') ".practice`n"
    PCopy (Join-Path $src 'sysml.conf') (Join-Path $sbx 'sysml.conf')
    $info.notes += 'sysml.cmd check FILE checks the grammar of one .sysml file.'
}
function SetupTwModel([string]$sbx, $info) {                       # lesson 10: the scaffold, then drop v1.0 imported, as two commits by Tom
    $src = Join-Path $script:TPL 'tw-model'
    $r = Pgit $sbx @('init', '-q')
    if ($r.rc) { throw "practice: pgit init failed: $($r.out)`n" }
    $commits = @(Get-Content -LiteralPath (Join-Path $src 'commits.txt') | Where-Object { $_ -match '\S' })
    for ($k = 1; $k -le $commits.Count; $k++) {
        $parts = $commits[$k - 1] -split '\|', 3
        $cdir = Join-Path $src "c$k"
        if (Test-Path -LiteralPath $cdir -PathType Container) {
            $root = (Resolve-Path -LiteralPath $cdir).Path
            foreach ($f in @(Get-ChildItem -LiteralPath $cdir -Recurse -File -Force)) { PCopy $f.FullName (Join-Path $sbx $f.FullName.Substring($root.Length + 1)) }
        }
        $del = Join-Path $src "c$k.deleted"
        if (Test-Path -LiteralPath $del) { foreach ($p in @(Get-Content -LiteralPath $del | Where-Object { $_ -match '\S' })) { Remove-Item -LiteralPath (Join-Path $sbx $p) -Force -ErrorAction SilentlyContinue } }
        $null = GitCommit $sbx $parts[2] $parts[0] $parts[1]
    }
    $ig = PRead (Join-Path $sbx '.gitignore'); if ($null -eq $ig) { $ig = '' }
    $sep = ''; if ($ig -ne '' -and -not $ig.EndsWith("`n")) { $sep = "`n" }
    PWrite (Join-Path $sbx '.gitignore') ($ig + $sep + ".practice`ndrops/`n")
    $info.notes += 'The file: pvi.cmd model\physical\stations\Stations.sysml   (sysml.cmd check FILE, model.cmd lint, model.cmd check)'
    if (-not (HasIdentity $sbx)) {
        $null = Pgit $sbx @('config', 'user.name', 'Bob')
        $null = Pgit $sbx @('config', 'user.email', 'bob@example.invalid')
        $info.notes += 'Commits here are signed Bob <bob@example.invalid> (pgit has no user.name yet: pgit.cmd config --global user.name "First Last")'
    }
}
function SetupMemo([string]$sbx, $info) {
    PWrite (Join-Path $sbx 'memo.md') @"
# MEMORANDUM FOR THE PROGRAM MANAGER

SUBJECT: Halberd SysML v2 port, status TODO (the date)

The port is in sprint TODO (the number) of six. TODO: one sentence on where it stands.

Progress this sprint:

- TODO: items committed and done so far (agile.cmd status)
- TODO: what is blocked or carried, if anything (agile.cmd blocked, agile-more.cmd quad)

Next: TODO: what the team does next.

Point of contact: TODO.

"@.Replace("`r", '')
    $info.notes += 'Edit memo.md (pvi.cmd memo.md, or Notepad): replace every TODO.'
}
function Setup([int]$n, [string]$sbx, [string]$day) {
    $l = Lesson $n
    if (Test-Path -LiteralPath $sbx) { Remove-Item -LiteralPath $sbx -Recurse -Force }
    New-Item -ItemType Directory -Path $sbx -Force | Out-Null
    $info = @{ lesson = "$n"; today = $day; notes = @() }
    switch ($l.kind) {
        'empty' { InitProject $sbx; break }
        'halberd' { SetupHalberd $sbx $day $info; break }
        'dronecorp' { SetupDronecorp $sbx $day $info ([bool]$l.chat); break }
        'idef0' { SetupIdef0 $sbx $info; break }
        'sysml' { SetupSysml $sbx $info; break }
        'tw-model' { SetupTwModel $sbx $info; break }
    }
    if ($l.memo) { SetupMemo $sbx $info }
    if (Test-Path -LiteralPath (Join-Path $sbx '.git') -PathType Container) { $info.head = GitCommit $sbx "practice lesson ${n}: set-up" }
    $txt = ''
    foreach ($k in (Sorted @($info.Keys))) { if ($k -ceq 'notes') { continue }; $txt += "$k = $($info[$k])`n" }
    PWrite (Join-Path $sbx '.practice') $txt
    $info
}
function Info([string]$sbx) {
    $i = @{}
    $t = PRead (Join-Path $sbx '.practice'); if ($null -eq $t) { $t = '' }
    foreach ($line in ($t -split "`n")) { if ($line -cmatch '^(\w+) = (.*)$') { $i[$Matches[1]] = $Matches[2] } }
    $i
}

# ================================================================ checks
function Res([bool]$ok, [string]$msg) { , @($ok, $msg) }   # not R: that is PowerShell's alias for Invoke-History
function LoadJ([string]$sbx) { try { LoadScrum (Join-Path $sbx 'scrum.txt') (RealToday) $null } catch { $null } }
function CommitsSince([string]$sbx, [string]$head) {             # git rev-list --count HEAD..head on a linear history
    $r = Pgit $sbx @('log', '--format=%H')
    if ($r.rc) { return 0 }
    $n = 0
    foreach ($h in ($r.out -split "`n")) { $h = $h.Trim(); if (-not $h) { continue }; if ($head -and $h -ceq $head) { break }; $n++ }
    $n
}
function StatusLines([string]$sbx) {
    $r = Pgit $sbx @('status', '--porcelain')
    @(($r.out -split "`n") | Where-Object { $_ -match '\S' -and $_ -notmatch '\.practice$' })
}
function Common([string]$sbx, $info) {                         # nothing pending, committed after the set-up, nothing uncommitted
    $p = Pending (Join-Path $sbx 'standups')
    $cnt = CommitsSince $sbx $info.head
    $st = StatusLines $sbx
    $a = Res ($p.Count -eq 0) $(if ($p.Count) { "stand-up files not compiled yet: $($p -join ' ') (agile.cmd compile)" } else { 'no pending stand-up files' })
    $b = Res ($cnt -ge 1 -and $st.Count -eq 0) $(if ($cnt -lt 1) { 'no commit of your work yet (agile.cmd commit)' } elseif ($st.Count) { "uncommitted changes (agile.cmd commit):`n" + (@($st | ForEach-Object { "          $_" }) -join "`n") } else { 'your work is committed' })
    @($a, $b)
}
function TodayBlocks([string]$sbx, [string]$since) {
    $t = PRead (Join-Path $sbx 'scrum.txt'); if ($null -eq $t) { $t = '' }
    $out = ''
    foreach ($b in ($t -split '(?m)(?=^; ---- standup )')) { if ($b -cmatch '^; ---- standup (\d{4}-\d{2}-\d{2})' -and -not (SLt $Matches[1] $since)) { $out += $b } }
    $out
}
function Check1([string]$sbx, $info) {
    $s = LoadJ $sbx
    if (-not $s) { return @((Res $false 'the journal does not load: agile.cmd status shows the error')) }
    $items = @($s.items.Values)
    $in1 = @($items | Where-Object { "$($_.sprint)" -ceq '1' -and "$($_.state)" -cmatch '^(?:committed|done|carryover)$' })
    $sum = $null; try { $sum = SprintSummary $s 1 } catch { $sum = $null }
    $cap = $false
    if ($sum) { foreach ($t in $sum.teams.Values) { if ($t.capacity -gt 0) { $cap = $true } } }
    @((Res ($items.Count -ge 3) "$($items.Count) task(s) in the journal (want 3 or more: new lines)"),
      (Res ($in1.Count -ge 2) "$($in1.Count) task(s) committed in sprint 1 (want 2 or more: commit lines)"),
      (Res $cap $(if ($cap) { 'sprint 1 has a capacity' } else { 'no capacity for sprint 1 (a cap N line under the team)' }))) + (Common $sbx $info)
}
function Check2([string]$sbx, $info) {
    $since = $info.today; if (-not $since) { $since = RealToday }
    $t = TodayBlocks $sbx $since
    $blocked = @{}; $unblocked = @{}; $carried = @{}
    foreach ($line in ($t -split "`n")) {
        if ($line -cmatch '; id: ([^,\s]+), blocked: ?(.*?)\s*$') { if ($Matches[2] -ne '') { $blocked[$Matches[1]] = 1 } else { $unblocked[$Matches[1]] = 1 } }
        if ($line -cmatch '^\s+Sprint:\d+:[^:\s]+:Carryover\s+\d[\d.]*\s.*; id: (\S+)') { $carried[$Matches[1]] = 1 }
    }
    $both = (Sorted @($blocked.Keys | Where-Object { $unblocked.ContainsKey($_) }))
    @((Res ($blocked.Count -ge 1) $(if ($blocked.Count) { 'blocked today: ' + ((Sorted @($blocked.Keys)) -join ' ') } else { 'no task blocked today (block ID REASON)' })),
      (Res ($both.Count -ge 1) $(if ($both.Count) { "blocked and unblocked again: $($both -join ' ')" } else { 'no blocked task unblocked again today (unblock ID in a second file)' })),
      (Res ($carried.Count -ge 1) $(if ($carried.Count) { 'carried today: ' + ((Sorted @($carried.Keys)) -join ' ') } else { 'nothing carried today (carry ID)' }))) + (Common $sbx $info)
}
function Check3([string]$sbx, $info) {
    $s = LoadJ $sbx
    if (-not $s) { return @((Res $false 'the journal does not load: agile.cmd status shows the error')) }
    $n = $info.sprint; if (-not $n) { $n = $s.current }
    $open = $null; try { $open = (SprintSummary $s $n).totals.open } catch { $open = $null }
    $since = $info.today; if (-not $since) { $since = RealToday }
    $status = @(Get-ChildItem -LiteralPath (Join-Path $sbx 'reports') -Filter '*-status.html' -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -cmatch '^(\d{4}-\d{2}-\d{2})-status\.html$' -and -not (SLt $Matches[1] $since) })
    $rep = Test-Path -LiteralPath (Join-Path $sbx "reports\sprint-$n-report.txt") -PathType Leaf
    $openShown = '?'; if ($null -ne $open) { $openShown = Num $open }
    @((Res ($null -ne $open -and $open -eq 0) $(if ($null -ne $open -and $open -eq 0) { "nothing open in sprint $n" } else { "$openShown points still open in sprint $n (done or carry each one)" })),
      (Res $rep $(if ($rep) { "reports/sprint-$n-report.txt written" } else { "no reports/sprint-$n-report.txt (agile-more.cmd review)" })),
      (Res ($status.Count -gt 0) $(if ($status.Count) { 'the status report is written' } else { 'no status report from today (agile.cmd report)' }))) + (Common $sbx $info)
}
function Check4([string]$sbx, $info) {
    $d = $info.today; if (-not $d) { $d = RealToday }
    $r = Agile $sbx @('lint') $d
    $err = @(($r.out -split "`n") | Where-Object { $_ -cmatch ' ERROR ' })
    $ans = @(Get-ChildItem -LiteralPath (Join-Path $sbx 'standups') -Filter "$d-*-answers.txt" -File -ErrorAction SilentlyContinue)
    $msg = 'lint finds no ERROR in today''s chat'
    if ($err.Count) { $msg = "$($err.Count) status(es) with an ERROR still:`n" + (@($err | ForEach-Object { '          ' + ($_ -creplace '^.*?: (ERROR)', '$1') }) -join "`n") }
    elseif ($r.rc) { $msg = "lint failed: $($r.out)" }
    @((Res ($r.rc -eq 0 -and $err.Count -eq 0) $msg),
      (Res ($ans.Count -gt 0) $(if ($ans.Count) { "$($ans.Count) answers file(s) for $d" } else { "no answers file for $d (agile.cmd answers)" })))
}
function Check5([string]$sbx, $info) {
    $n = 0; $right = 0
    $t = PRead (Join-Path $sbx 'drill.txt'); if ($null -eq $t) { $t = '' }
    foreach ($line in ($t -split "`n")) {
        if ($line -match '^\s*#') { continue }
        $f = @(($line -split '\|', 7) | ForEach-Object { $_.Trim() })
        if ($f.Count -lt 5) { continue }
        $rt = 0; if ($f[3] -match '^\d+$') { $rt = [int]$f[3] }
        $wr = 0; if ($f[4] -match '^\d+$') { $wr = [int]$f[4] }
        if ($rt + $wr -gt 0) { $n++ }
        $right += $rt
    }
    @((Res ($n -ge 6) "$n card(s) graded in drill.txt (want 6 or more: drill.cmd -Sheet, answer, drill.cmd -Grade)"),
      (Res ($right -ge 1) "$right right answer(s)"))
}
function Check6([string]$sbx, $info) {
    $m = @(Get-ChildItem -LiteralPath (Join-Path $sbx 'model') -Filter '*.txt' -File -ErrorAction SilentlyContinue | Sort-Object Name)
    $rel = @($m | ForEach-Object { "model\$($_.Name)" })
    $r = Run $sbx (Tool 'idef0\idef0.ps1') (@('lint') + $rel)
    $sum = $null; if ($r.out -cmatch '(?m)^(\d+ file\(s\): .*)$') { $sum = $Matches[1] }
    $pf = Join-Path $sbx 'plates.html'
    $html = ''; if (Test-Path -LiteralPath $pf) { $html = Get-Content -LiteralPath $pf -Raw }
    $newest = [datetime]'1900-01-01'; foreach ($f in $m) { if ($f.LastWriteTime -gt $newest) { $newest = $f.LastWriteTime } }
    $fresh = (Test-Path -LiteralPath $pf) -and ((Get-Item -LiteralPath $pf).LastWriteTime -ge $newest)
    $lintMsg = 'the model lints clean'; if ($r.rc) { $lintMsg = 'lint still reports errors: ' + $(if ($sum) { $sum } else { $r.out }) }
    $pmsg = if (-not (Test-Path -LiteralPath $pf)) { 'no plates.html (idef0.cmd html ... | Out-File -Encoding utf8 plates.html)' } elseif ($html -notmatch '<svg') { 'plates.html has no SVG plates' } elseif ($fresh) { 'plates.html is up to date' } else { 'plates.html is older than the model: render it again' }
    @((Res ($r.rc -eq 0) $lintMsg), (Res (($html -match '<svg') -and $fresh) $pmsg))
}
function Check7([string]$sbx, $info) {
    $md = PRead (Join-Path $sbx 'memo.md'); if ($null -eq $md) { $md = '' }
    $n = $info.sprint; if (-not $n) { $n = '?' }
    $docx = Join-Path $sbx 'memo.docx'
    $isDocx = $false; $fresh = $false
    if (Test-Path -LiteralPath $docx) {
        $b = Get-Content -LiteralPath $docx -Encoding Byte -TotalCount 2
        $isDocx = ($b.Count -eq 2 -and $b[0] -eq 0x50 -and $b[1] -eq 0x4B)
        $fresh = (Get-Item -LiteralPath $docx).LastWriteTime -ge (Get-Item -LiteralPath (Join-Path $sbx 'memo.md')).LastWriteTime
    }
    $txtOk = (Test-Path -LiteralPath (Join-Path $sbx 'memo.txt')) -and ((Get-Item -LiteralPath (Join-Path $sbx 'memo.txt')).Length -gt 0)
    $dmsg = if (-not (Test-Path -LiteralPath $docx)) { 'no memo.docx (md2docx.cmd memo.md -Out memo.docx)' } elseif (-not $isDocx) { 'memo.docx is not a Word file' } elseif ($fresh) { 'memo.docx is rendered from the latest memo.md' } else { 'memo.docx is older than memo.md: render it again' }
    @((Res ($md -ne '' -and $md -notmatch 'TODO') $(if ($md -match 'TODO') { 'memo.md still has TODO marks' } else { 'every TODO is replaced' })),
      (Res ($md -match "\bsprint\s+$([regex]::Escape($n))\b") "memo.md names the current sprint (sprint $n)"),
      (Res ($isDocx -and $fresh) $dmsg),
      (Res $txtOk $(if ($txtOk) { 'memo.txt written' } else { 'no memo.txt (md2docx.cmd memo.md -Text -Out memo.txt)' })))
}
function Check8([string]$sbx, $info) {
    $f = @()
    if (Test-Path -LiteralPath (Join-Path $sbx 'model') -PathType Container) { $f = @(Get-ChildItem -LiteralPath (Join-Path $sbx 'model') -Recurse -Filter '*.sysml' -File | Sort-Object FullName) }
    $root = (Resolve-Path -LiteralPath $sbx).Path
    $rel = @($f | ForEach-Object { $_.FullName.Substring($root.Length + 1) })
    $r = @{ rc = 1; out = '' }; if ($f.Count) { $r = Run $sbx (Tool 'sysml\sysml.ps1') (@('check') + $rel) }
    $open = 0; $reviewed = 0
    foreach ($x in $f) {
        $t = PRead $x.FullName
        foreach ($line in ($t -split "`n")) { if ($line -notmatch '//\s*TODO\b') { continue }; if ($line -match '//\s*TODO\(reviewed\)') { $reviewed++ } else { $open++ } }
    }
    $notes = PRead (Join-Path $sbx 'NOTES.txt'); if ($null -eq $notes) { $notes = '' }
    $said = $null; if ($notes -match '(?m)^\s*TODO:\s*(\d+)') { $said = [int]$Matches[1] }
    $left = $open + $reviewed
    $st = StatusLines $sbx
    $cnt = CommitsSince $sbx $info.head
    $errLine = @(($r.out -split "`n") | Where-Object { $_ -match 'error' })[0]; if (-not $errLine) { $errLine = $r.out }
    @((Res ($f.Count -gt 0) $(if ($f.Count) { "$($f.Count) .sysml file(s) under model/" } else { 'no .sysml files under model/ (xmi2sysml.cmd --out model --check legacy.xmi)' })),
      (Res ($f.Count -gt 0 -and $r.rc -eq 0) $(if (-not $f.Count) { 'sysml check: nothing to check yet' } elseif ($r.rc -eq 0) { 'sysml check passes' } else { "sysml check finds errors: $errLine" })),
      (Res ($f.Count -gt 0 -and $open -eq 0) $(if ($open) { "$open TODO line(s) neither fixed nor marked TODO(reviewed)" } else { "no open TODO lines ($reviewed marked reviewed)" })),
      (Res ($null -ne $said -and $said -eq $left) $(if ($null -eq $said) { 'NOTES.txt has no "TODO: N" line' } elseif ($said -eq $left) { "NOTES.txt counts $left TODO line(s) left, right" } else { "NOTES.txt says TODO: $said, but $left TODO line(s) are left" })),
      (Res ($cnt -ge 1 -and $st.Count -eq 0) $(if ($cnt -lt 1) { 'nothing committed yet (pgit.cmd add model NOTES.txt; pgit.cmd commit)' } elseif ($st.Count) { 'uncommitted changes (pgit.cmd status)' } else { 'the port is committed' })))
}
$script:TW_ST = 'model/physical/stations/Stations.sysml'
function TwBlock([string]$t, [string]$name) { if ($t -cmatch "(?ms)^    part def $([regex]::Escape($name))\b[^\n]*\{\n(.*?)^    \}") { return $Matches[1] }; '' }
function TwStationsChecks([string]$t) {
    $seg = TwBlock $t 'StationSegment'
    $hasTag = $seg -cmatch '(?m)^\s*@L2Segment\s*;'
    $todo = $seg -cmatch 'TODO stereotype Tidewater_Profile:L2Segment'
    $m1 = if ($seg -eq '') { '$TW_ST has no part def StationSegment' } elseif ($todo) { 'StationSegment still has its level TODO line: replace it with @L2Segment;' } elseif ($hasTag) { 'StationSegment carries @L2Segment;' } else { 'StationSegment has no "@L2Segment;" line (spelled exactly so, with the semicolon)' }
    $imp = $t -cmatch '(?m)^\s*(?:private\s+)?import\s+Conventions::\*\s*;'
    @((Res ($hasTag -and -not $todo) $m1),
      (Res $imp $(if ($t -cmatch 'import\s+Conventions::\*') { 'package Stations imports Conventions' } else { 'package Stations does not import Conventions: add "private import Conventions::*;" under "package Stations {"' })))
}
function Check10([string]$sbx, $info) {
    $f = Join-Path $sbx (Norm $script:TW_ST)
    $t = PRead $f
    if ($null -eq $t) { return @((Res $false "no $($script:TW_ST): practice.cmd 10 sets the lesson up again")) }
    $g = Run $sbx (Tool 'sysml\sysml.ps1') @('check', (Norm $script:TW_ST))
    $lint = Run $sbx (Tool 'sysml\model.ps1') @('lint')
    $chk = Run $sbx (Tool 'sysml\model.ps1') @('check')
    $lastl = $null; foreach ($line in ($lint.out -split "`n")) { if ($line -cmatch '^elements=') { $lastl = $line.TrimEnd() } }
    $mis = $null; if ($chk.out -cmatch '(?m)^@L tag mismatches\s+(\d+)') { $mis = [int]$Matches[1] }
    $st = StatusLines $sbx
    $cnt = CommitsSince $sbx $info.head
    $gerr = @(($g.out -split "`n") | Where-Object { $_ -match 'error' })[0]; if (-not $gerr) { $gerr = $g.out }
    $lintOk = ($null -ne $lastl) -and ($lastl -cmatch 'errors=0 warnings=0$')
    $lmsg = if ($null -ne $lastl) { "model lint: $lastl" + $(if ($lintOk) { '' } else { ' (model.cmd lint lists them)' }) } else { 'model lint did not finish: ' + @($lint.out -split "`n")[-1] }
    $mmsg = if ($null -eq $mis) { 'model check did not run' } elseif ($mis) { "model check: $mis level tag(s) at the wrong level" } else { 'every level tag sits at its level (model check)' }
    $cmsg = if ($cnt -lt 1) { 'nothing committed yet (pgit.cmd add model; pgit.cmd commit -m "Tag StationSegment with its level")' } elseif ($st.Count) { "uncommitted changes (pgit.cmd status):`n" + (@($st | ForEach-Object { "          $_" }) -join "`n") } else { 'your change is committed' }
    (TwStationsChecks $t) + @(
        (Res ($g.rc -eq 0) $(if ($g.rc -eq 0) { 'the grammar check passes' } else { "the grammar check finds an error: $gerr" })),
        (Res $lintOk $lmsg),
        (Res ($null -ne $mis -and $mis -eq 0) $mmsg),
        (Res ($cnt -ge 1 -and $st.Count -eq 0) $cmsg))
}
function Check([int]$n, [string]$sbx) {
    $info = Info $sbx
    $rs = switch ($n) { 1 { Check1 $sbx $info } 2 { Check2 $sbx $info } 3 { Check3 $sbx $info } 4 { Check4 $sbx $info } 5 { Check5 $sbx $info }
                        6 { Check6 $sbx $info } 7 { Check7 $sbx $info } 8 { Check8 $sbx $info } 10 { Check10 $sbx $info } }
    $rs = @($rs)
    $ok = 0
    foreach ($r in $rs) { $tag = 'TODO'; if ($r[0]) { $tag = 'ok'; $ok++ }; POut ('  {0,-5} {1}' -f $tag, $r[1]) }
    if ($ok -eq $rs.Count) { POut "lesson ${n}: done"; $script:PRC = 0; return }
    POut ("lesson {0}: not yet ({1} of {2} checks pass). The task: practice.cmd help {0}" -f $n, $ok, $rs.Count)
    $script:PRC = 1
}

# ================================================================ the command line
function Usage {
    @'
practice.cmd -- the agile kit's hands-on practice lessons (Windows PowerShell 5.1)

  practice.cmd                     list the lessons
  practice.cmd N                   set up .\practice\lessonN (wiping an old one) and print the task
  practice.cmd check N             what is done, what is missing; exit 0 when the lesson is done
  practice.cmd reset N             remove the sandbox
  practice.cmd help [N]            this text, or lesson N's task
  options: -Dir DIR (sandboxes there instead of .\practice), -Today YYYY-MM-DD (the sandbox's "today")

Lessons 9 (a Perl coding drill) and 11-13 (they need the Perl kit's offline GitLab) are not in this version.
'@
}
function Main {
    $vb = $PR.verb; $nm = $PR.num
    if ($PR.help -or $vb -in @('help', '-h', '--help', '/?', '-Help')) {
        if ($nm -match '^\d+$' -and (Lesson ([int]$nm))) { POut (Lesson ([int]$nm)).title; POut ''; POut ($script:TEXT[[int]$nm] -replace "`r", ''); $script:PRC = 0; return }
        POut ((Usage) -replace "`r", ''); $script:PRC = 0; return
    }
    $base = Abs $(if ($PR.dir) { $PR.dir } else { 'practice' })
    $day = $PR.today; if (-not $day) { $day = RealToday }
    if ($day -cnotmatch '^\d{4}-\d{2}-\d{2}$') { PErr "practice: bad -Today '$day' (want YYYY-MM-DD)"; $script:PRC = 2; return }
    if (-not $vb) {
        POut 'Practice lessons (practice.cmd N to start one; practice.cmd help N prints its task):'
        foreach ($l in $script:LESSONS) {
            $state = ''; if (Test-Path -LiteralPath (Join-Path $base "lesson$($l.n)\.practice")) { $state = '  [set up]' }
            POut ('  {0}  {1}{2}' -f $l.n, $l.title, $state)
        }
        foreach ($k in @(9, 11, 12, 13)) { POut ("  {0}  [not in this version: {1}]" -f $k, $script:NOT_HERE[$k]) }
        POut "Sandboxes go in $base. practice.cmd check N checks your work; practice.cmd reset N removes it."
        $script:PRC = 0; return
    }
    if ($vb -cnotin @('check', 'reset')) { $nm = $vb; $vb = 'setup' }
    if (-not $nm -or $nm -notmatch '^\d+$') { PErr 'usage: practice.cmd [N | check N | reset N] [-Dir DIR] [-Today YYYY-MM-DD]'; $script:PRC = 2; return }
    $n = [int]$nm
    if ($script:NOT_HERE.ContainsKey($n)) { PErr "practice: lesson $n is not in this version: $($script:NOT_HERE[$n])"; $script:PRC = 2; return }
    $l = Lesson $n
    if (-not $l) { PErr "practice: no lesson $n (practice.cmd lists them)"; $script:PRC = 2; return }
    $sbx = Join-Path $base "lesson$n"
    if ($vb -ceq 'reset') { if (Test-Path -LiteralPath $sbx) { Remove-Item -LiteralPath $sbx -Recurse -Force }; POut "removed $sbx"; $script:PRC = 0; return }
    if ($vb -ceq 'check') {
        if (-not (Test-Path -LiteralPath (Join-Path $sbx '.practice'))) { PErr "practice: lesson $n is not set up (practice.cmd $n)"; $script:PRC = 1; return }
        Check $n $sbx; return
    }
    if (-not (Test-Path -LiteralPath $script:TPL -PathType Container)) { PErr "practice: no templates at $($script:TPL)"; $script:PRC = 1; return }
    try { $info = Setup $n $sbx $day } catch { PErr ("$($_.Exception.Message)" -replace "`n$", ''); $script:PRC = 1; return }
    POut $l.title; POut ''
    POut ($script:TEXT[$n] -replace "`r", '')
    POut ''
    POut "Tools     = $($script:TOOLS)"
    POut "Sandbox   = $sbx"
    POut "In it:      cd $sbx"
    POut "On PATH:    `$env:PATH += `";$($script:TOOLS)`"   (then agile.cmd, pgit.cmd ... work from any folder)"
    if (-not (Test-Path -LiteralPath (Tool 'agile-more.cmd'))) { POut "agile-more.cmd = powershell -NoProfile -ExecutionPolicy Bypass -File `"$(Tool 'agile-more.ps1')`"" }
    foreach ($x in $info.notes) { POut $x }
    POut "When done: practice.cmd check $n"
    $script:PRC = 0
}
Main
if ($PSCommandPath) { exit $script:PRC }
$global:LASTEXITCODE = $script:PRC
