<#
sysml-diff.ps1 : review a change to a SysML v2 model as two pictures and a change list.
PowerShell port of tools/sysml/views/sysml-diff.pl (Constrained Language Mode safe, pure ASCII).

  sysml-diff.ps1 [-o PREFIX] [--changed] [--root NAME]... [--today DATE] OLD_DIR NEW_DIR

Writes PREFIX-tree.svg, PREFIX-trace.svg, PREFIX-packages.svg, PREFIX-ibd.svg and PREFIX-changes.txt (default PREFIX
model-diff), byte for byte as the Perl. The --git OLD[..NEW] form needs git, which the baseline PC does not have:
export the two versions to folders (pgit can check out a commit into a folder) and compare the folders.
Exit status: 0 no new gaps and no new error findings, 1 otherwise, 2 usage error.
#>
. (Join-Path $PSScriptRoot 'views-lib.ps1')
function Usage { PErr "usage: perl sysml-diff.pl [-o PREFIX] [--changed] [--root NAME]... OLD_DIR NEW_DIR`n       perl sysml-diff.pl [-o PREFIX] [--changed] [--root NAME]... --git OLD[..NEW] [PATH...]"; VExit 2 }
$go = GetOpts $args @('o=s', 'changed', 'root=s@', 'git=s', 'today=s')
if (-not $go.ok) { Usage }
$OPT = $go.opts; $ARGV0 = @($go.rest)
if ($null -eq $OPT['o']) { $OPT['o'] = 'model-diff' }
$ROOTOPTS = @(); if ($null -ne $OPT['root']) { $ROOTOPTS = @($OPT['root']) }
if ($null -ne $OPT['git']) {
    PErr "sysml-diff: --git needs git, which this PC does not have. Export both versions to folders (e.g. pgit.cmd checkout into a copy) and run: sysml-diff OLD_DIR NEW_DIR"
    VExit 2
}
if ($ARGV0.Count -ne 2) { Usage }
$OLDDIR = $ARGV0[0]; $NEWL = @($ARGV0[1])
$CHANGES = @(); $script:GAPS = 0
foreach ($view in @(@('tree', 'sysml-tree-svg.ps1'), @('trace', 'sysml-trace-svg.ps1'))) {
    $name = $view[0]; $tool = $view[1]
    $cmdargs = @('-o', "$($OPT['o'])-$name.svg")
    if ($OPT['changed']) { $cmdargs += , '--changed' }
    if ($name -eq 'tree') { foreach ($r in $ROOTOPTS) { $cmdargs += @('--root', $r) } }
    $cmdargs += @('--compare', $OLDDIR) + $NEWL
    VFlush
    $out = @(& (Join-Path $PSScriptRoot $tool) @cmdargs)
    $rc = $LASTEXITCODE
    foreach ($l in $out) {
        $l = [string]$l
        if (T $l '^(?:tree|trace)-svg: ') { PL $l; continue }
        if (T $l ': warning: ') { $script:GAPS++ }
        $CHANGES += , $l
    }
    if ($rc) { VFlush; PErr "sysml-diff: $($tool -replace '\.ps1$', '.pl') failed"; VExit 2 }
}
function Findings([string]$tool, $fargs) {       # its output is captured: flush stdout before calling it, not inside
    $out = @(& (Join-Path $PSScriptRoot $tool) @fargs)
    $rc = $LASTEXITCODE
    $f = @(); $sum = $null
    foreach ($l in $out) {
        $l = [string]$l
        $m = M $l '^(.*?:\d+): (error|warning): (.*)$'
        if ($m.Success) { $f += , @($m.Groups[1].Value, $m.Groups[2].Value, $m.Groups[3].Value) }
        elseif (T $l '\d+ file\(s\): ') { $sum = $l }
    }
    if ($rc -eq 2) { $script:FAILED = $tool; return $null }
    $res = @(, $f) + , $sum
    , $res
}
$script:NEWERR = 0
foreach ($chk in @(@('markings', 'sysml-pkg-svg.ps1', 'packages'), @('zones', 'sysml-ibd-svg.ps1', 'ibd'), @('threats', 'sysml-threats.ps1', $null))) {
    $name = $chk[0]; $tool = $chk[1]; $svg = $chk[2]
    $tt = @(); if ($name -eq 'threats' -and $OPT['today']) { $tt = @('--today', $OPT['today']) }
    $oa = $tt; if ($null -ne $svg) { $oa += @('-o', 'NUL') }; $oa += , $OLDDIR
    $na = $tt; if ($null -ne $svg) { $na += @('-o', "$($OPT['o'])-$svg.svg") }; $na += $NEWL
    VFlush
    $or = Findings $tool $oa
    if ($null -eq $or) { PErr "sysml-diff: $($script:FAILED -replace '\.ps1$', '.pl') failed"; VExit 2 }
    $old = $or[0]
    $cr = Findings $tool $na
    if ($null -eq $cr) { PErr "sysml-diff: $($script:FAILED -replace '\.ps1$', '.pl') failed"; VExit 2 }
    $cur = $cr[0]; $sum = $cr[1]
    $was = NewH; foreach ($x in @($old)) { $k = "$($x[1]): $($x[2])"; $was[$k] = 1 + (Dflt $was[$k] 0) }
    $now = NewH; foreach ($x in @($cur)) { $k = "$($x[1]): $($x[2])"; $now[$k] = 1 + (Dflt $now[$k] 0) }
    $nnew = 0; $nres = 0
    foreach ($x in @($cur)) { $k = "$($x[1]): $($x[2])"; if ((Dflt $was[$k] 0) -gt 0) { $was[$k]--; continue }; $CHANGES += , "$($x[0]): $($x[1]): new finding ($name): $($x[2])"; $nnew++; if ($x[1] -eq 'error') { $script:NEWERR++ } }
    foreach ($x in @($old)) { $k = "$($x[1]): $($x[2])"; if ((Dflt $now[$k] 0) -gt 0) { $now[$k]--; continue }; $CHANGES += , "$($x[0]): note: resolved ($name): $($x[2])"; $nres++ }
    if ($null -eq $sum) { $sum = '' }; $sum = Sub $sum ' -> \S+$' ''
    PL "${name}: $nnew new finding(s), $nres resolved; now $sum"
}
function ChangeKey([string]$l) { $m = M $l '^(.*?):(\d+):'; if ($m.Success) { @($m.Groups[1].Value, [long]$m.Groups[2].Value) } else { @('', 0) } }
$SORTED = SortBy $CHANGES { param($x, $y) $a1 = ChangeKey $x; $b1 = ChangeKey $y; $c = Cmp $a1[0] $b1[0]; if ($c) { return $c }; $c = NCmp $a1[1] $b1[1]; if ($c) { return $c }; Cmp $x $y }
$SEEN = NewH; $UNIQ = @(foreach ($l in $SORTED) { if (-not $SEEN.ContainsKey($l)) { $SEEN[$l] = 1; $l } })
$null = VWrite "$($OPT['o'])-changes.txt" ((@($UNIQ | ForEach-Object { "$_`n" })) -join '')
PL ('sysml-diff: {0} change line(s), {1} new gap(s), {2} new error finding(s) -> {3}-{{tree,trace,packages,ibd}}.svg {3}-changes.txt' -f $UNIQ.Count, $script:GAPS, $script:NEWERR, $OPT['o'])
VExit $(if ($script:GAPS -or $script:NEWERR) { 1 } else { 0 })
