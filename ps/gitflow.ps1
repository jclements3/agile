<#
gitflow.ps1 -- gitflow for a model repository on a PowerShell-only PC (the kit's lib/GitFlow.pm, `gitlab.pl flow`).

Windows PowerShell 5.1, Constrained Language Mode safe, pure ASCII. Uses pgit.ps1 (beside this file) for every
repository step, because this PC has no git.

  gitflow.cmd init                              develop from main (a first, empty commit on main in an empty repository)
  gitflow.cmd start feature|release|hotfix NAME a branch from develop (hotfix: from main); prints "on BRANCH"
  gitflow.cmd kind                              the current branch: feature|release|hotfix|vendor|other and its name
  --repo DIR                                    the repository (default: the current folder, which must hold .git;
                                                flow never walks up to a folder above it)
  gitflow.cmd publish | finish | released IID | sync | vendor DROPDIR VERSION | allowance VERSION | take ours|theirs PATH...
                                                need git and the GitLab remote: printed, not run (exit 4)

Branch names as the kit: main, develop, feature/, release/, hotfix/, vendor/prime. What differs from the Perl kit:
the Perl kit works against origin (fetch, push, GitLab's API); here there is no remote and no GitLab, so init and
start work on the local branches (start branches from the local develop or main), and every step that pushes,
merges three ways or calls GitLab prints the exact commands to run from this clone on a PC that has git, and stops
with exit code 4 ("not run"). Nothing is pretended: a step that did not run is never reported as done.
#>

$ErrorActionPreference = 'Stop'
$script:GF_REPO = $null
$script:BR = @{ main = 'main'; develop = 'develop'; feature = 'feature/'; release = 'release/'; hotfix = 'hotfix/'; vendor = 'vendor/prime' }
$script:PGIT = Join-Path $PSScriptRoot 'pgit.ps1'

function GfOut([string]$t) { if ($t) { Write-Host -NoNewline $t } }
function GfDie([string]$m) { throw ('GFDIE:' + $m) }

function GfTop {                                   # the repository root: the folder given (--repo DIR) or the current one; never a folder above it
    $d = if ($script:GF_REPO) { $script:GF_REPO } else { (Get-Location).Path }
    if (-not (Test-Path -LiteralPath $d -PathType Container)) { GfDie "no such folder: $d`n" }
    $d = (Get-Item -LiteralPath $d).FullName.TrimEnd('\')
    if (-not (Test-Path -LiteralPath (Join-Path $d '.git\HEAD'))) { GfDie "flow runs at the top of a repository: $d has no .git (run it in the repository's own folder, or pass --repo DIR)`n" }
    return $d
}
function GfRef([string]$top, [string]$ref) {       # a ref's sha from the files (loose or packed), else $null
    $f = Join-Path $top ('.git\' + $ref.Replace('/', '\'))
    if (Test-Path -LiteralPath $f -PathType Leaf) { $l = (Get-Content -LiteralPath $f -TotalCount 1); if ($l -cmatch '^([0-9a-f]{40})') { return $Matches[1] } }
    $pr = Join-Path $top '.git\packed-refs'
    if (Test-Path -LiteralPath $pr) { foreach ($l in (Get-Content -LiteralPath $pr)) { if ($l -cmatch '^([0-9a-f]{40}) (\S+)$' -and $Matches[2] -ceq $ref) { return $Matches[1] } } }
    return $null
}
function GfBranch([string]$top) {
    $l = Get-Content -LiteralPath (Join-Path $top '.git\HEAD') -TotalCount 1
    if ($l -cmatch '^ref: refs/heads/(\S+)') { return $Matches[1] }
    return 'HEAD'
}
function GfPgit([string[]]$argv) {                 # run pgit.ps1 in this process; -> exit code (its output is shown)
    if (-not (Test-Path -LiteralPath $script:PGIT)) { GfDie 'pgit.ps1 is not beside gitflow.ps1' }
    $top = GfTop
    $saved = $env:GIT_CEILING_DIRECTORIES
    $env:GIT_CEILING_DIRECTORIES = Split-Path -Parent $top      # pgit never climbs above this repository
    $here = (Get-Location).Path
    try { Set-Location -LiteralPath $top; $out = & $script:PGIT @argv 2>&1 }
    finally { Set-Location -LiteralPath $here; if ($null -eq $saved) { Remove-Item env:GIT_CEILING_DIRECTORIES -ErrorAction SilentlyContinue } else { $env:GIT_CEILING_DIRECTORIES = $saved } }
    $rc = $LASTEXITCODE; if ($null -eq $rc) { $rc = 0 }
    $text = (@($out) | ForEach-Object { [string]$_ }) -join "`n"
    return , @($rc, $text)
}
function GfGit([string[]]$argv) {
    $r = GfPgit $argv
    if ($r[0] -ne 0) { GfDie ('pgit ' + ($argv -join ' ') + ': ' + $r[1] + "`n") }
    return $r[1]
}

function GfKind([string]$b) {
    foreach ($k in @('feature', 'release', 'hotfix')) { $p = $script:BR[$k]; if ($b.StartsWith($p)) { return , @($k, $b.Substring($p.Length)) } }
    if ($b -ceq $script:BR.vendor) { return , @('vendor', $b) }
    return , @('other', $b)
}

function GfInit([string]$top) {
    $m = $script:BR.main; $d = $script:BR.develop
    if (-not (GfRef $top "refs/heads/$m")) {
        $cur = GfBranch $top
        $hsha = if ($cur -cne 'HEAD') { GfRef $top "refs/heads/$cur" } else { $null }
        if (-not $hsha) {                         # an empty repository: the first commit, on main
            $hb = @(); foreach ($ch in ("ref: refs/heads/$m`n").ToCharArray()) { $hb += [byte][int]$ch }
            Set-Content -LiteralPath (Join-Path $top '.git\HEAD') -Value ([byte[]]$hb) -Encoding Byte
            $null = GfGit @('commit', '-q', '--allow-empty', '-m', 'Initial commit')
        } else {
            $null = GfGit @('branch', $m)
        }
    }
    if (-not (GfRef $top "refs/heads/$d")) { $null = GfGit @('branch', $d, $m) }
    $null = GfGit @('checkout', '-q', $d)
    GfOut "develop is ready (from main)`n"
    return 0
}

function GfStart([string]$top, [string]$kind, [string]$name) {
    if ($kind -cnotmatch '^(feature|release|hotfix)$') { GfDie ("start feature, release or hotfix, not '" + $kind + "'`n") }
    if (-not $name -or $name -cnotmatch '^[\w./-]+$') { GfDie ("a branch name is letters, digits and . _ - / ('" + $name + "')`n") }
    $base = if ($kind -ceq 'hotfix') { $script:BR.main } else { $script:BR.develop }
    $b = $script:BR[$kind] + $name
    if (-not (GfRef $top "refs/heads/$base")) { GfDie ("there is no '" + $base + "' branch (run init first)`n") }
    if (GfRef $top "refs/heads/$b") { GfDie ("branch '" + $b + "' already exists`n") }
    $null = GfGit @('checkout', '-q', '-b', $b, $base)
    GfOut ("on " + $b + "`n")
    return 0
}

function GfNotRun([string]$what, [string[]]$cmds) {
    $t = "not run: $what needs git and the GitLab remote, which this PC does not have.`n"
    $t += "On a PC with git, from this clone (copy it there, or push it from there), run:`n"
    foreach ($c in $cmds) { $t += "  $c`n" }
    GfOut $t
    return 4
}

$script:USAGE = @'
gitflow.cmd init                              develop from main (first commit on an empty repo)
gitflow.cmd start feature|release|hotfix NAME a branch from develop (hotfix: from main)
gitflow.cmd kind                              the current branch's kind and name
gitflow.cmd publish                           push the current branch            (needs git: printed, exit 4)
gitflow.cmd finish [--title T] ...            push and open the merge request    (needs git and GitLab: printed, exit 4)
gitflow.cmd released IID [--tag NAME]         tag main after a release MR merged (needs git and GitLab: printed, exit 4)
gitflow.cmd vendor DROPDIR VERSION            prime drop onto vendor/prime, merged (needs git's three-way merge: printed, exit 4)
gitflow.cmd allowance VERSION                 the drop's outline allowance       (needs the drop's merge: printed, exit 4)
gitflow.cmd take ours|theirs PATH...          resolve merge conflicts            (needs git: printed, exit 4)
gitflow.cmd sync                              fetch; fast-forward main/develop   (needs the remote: printed, exit 4)
  Run inside a repository (pgit init / a copied clone). Branch names: main, develop, feature/, release/, hotfix/, vendor/prime.

'@

function GfMain($argv) {
    if ($argv.Count -eq 0 -or $argv[0] -match '^(-h|--help|-Help|help|/\?)$') { GfOut $script:USAGE; if ($argv.Count) { return 0 }; return 2 }
    $all = @(); for ($i = 0; $i -lt $argv.Count; $i++) { $x = [string]$argv[$i]; if ($x -cmatch '^--repo(?:=(.*))?$') { if ($null -ne $Matches[1]) { $script:GF_REPO = $Matches[1] } else { $i++; $script:GF_REPO = [string]$argv[$i] }; continue }; $all += $x }
    $argv = $all
    if ($argv.Count -eq 0) { GfOut $script:USAGE; return 2 }
    $sub = [string]$argv[0]
    $a = @(); for ($i = 1; $i -lt $argv.Count; $i++) { $a += [string]$argv[$i] }
    $known = @('init', 'start', 'kind', 'publish', 'finish', 'released', 'vendor', 'allowance', 'take', 'sync')
    if (-not ($known -ccontains $sub)) { GfOut $script:USAGE; return 2 }
    $top = GfTop
    if (-not $top) { GfDie "flow runs inside a clone of the project (no git repository here)`n" }
    $pos = @(); foreach ($x in $a) { if (-not $x.StartsWith('--')) { $pos += $x } }
    $b = GfBranch $top
    switch -CaseSensitive ($sub) {
        'init' { return (GfInit $top) }
        'start' { if ($pos.Count -lt 2) { GfDie "flow start needs feature|release|hotfix and a NAME`n" }; return (GfStart $top $pos[0] $pos[1]) }
        'kind' { $k = GfKind $b; GfOut ($k[0] + ' ' + $k[1] + "`n"); return 0 }
        'publish' { return (GfNotRun 'publish' @("git push -u origin ${b}:refs/heads/$b")) }
        'finish' {
            $k = GfKind $b
            if ($k[0] -cnotmatch '^(feature|release|hotfix)$') { GfDie ("'" + $b + "' is not a feature, release or hotfix branch`n") }
            $target = if ($k[0] -ceq 'feature') { $script:BR.develop } else { $script:BR.main }
            return (GfNotRun 'finish' @("git push -u origin ${b}:refs/heads/$b", "gitlab.pl flow finish $($a -join ' ')    (or open the merge request $b -> $target in GitLab)"))
        }
        'released' {
            if ($pos.Count -lt 1) { GfDie "flow released needs the merged release MR IID`n" }
            return (GfNotRun 'released' @('git fetch origin', "gitlab.pl flow released $($a -join ' ')"))
        }
        'vendor' {
            if ($pos.Count -lt 2) { GfDie "flow vendor needs DROPDIR and VERSION`n" }
            return (GfNotRun 'vendor (a three-way merge of the prime drop)' @('git fetch origin', "gitlab.pl flow vendor $($a -join ' ')"))
        }
        'allowance' {
            if ($pos.Count -lt 1) { GfDie "flow allowance needs the drop VERSION`n" }
            return (GfNotRun 'allowance' @("gitlab.pl flow allowance $($a -join ' ')"))
        }
        'take' {
            if ($pos.Count -lt 2) { GfDie "flow take needs ours|theirs and PATH...`n" }
            if ($pos[0] -cnotmatch '^(ours|theirs)$') { GfDie ("take ours or theirs, not '" + $pos[0] + "'`n") }
            $cmds = @(); for ($i = 1; $i -lt $pos.Count; $i++) { $cmds += "git checkout --$($pos[0]) -- $($pos[$i]) && git add -- $($pos[$i])" }
            return (GfNotRun 'take (merge conflicts exist only in a git merge)' $cmds)
        }
        'sync' {
            $c = @('git fetch -q --prune origin')
            foreach ($x in @($script:BR.main, $script:BR.develop)) { if ($x -ceq $b) { $c += "git merge -q --ff-only origin/$x" } else { $c += "git branch -q -f $x origin/$x" } }
            return (GfNotRun 'sync' $c)
        }
    }
    return 2
}

if ($args.Count -and [string]$args[0] -ceq '__lib') { return }
$rc = 1
try { $rc = GfMain @($args) }
catch { $m = [string]$_.Exception.Message; if ($m.StartsWith('GFDIE:')) { GfOut ('gitflow: ' + $m.Substring(6)) } else { GfOut ('gitflow: ' + $m + "`n") }; $rc = 1 }
exit $rc
