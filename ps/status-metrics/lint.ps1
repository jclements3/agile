<#
lint.ps1 -- the minimal model lint of the status-metrics simulation (sim/status-metrics/lint.pl), in Windows
PowerShell 5.1 (Constrained Language Mode safe). Prints: elements=N errors=E warnings=W. Exit 1 on any finding.

  lint.ps1 [MODEL_DIR]          # default .\model; used as lint_cmd in metrics.json
#>
$ErrorActionPreference = 'Stop'
$root = 'model'; if ($args.Count) { $root = [string]$args[0] }
function CK([string]$s) { return ($s -creplace '([A-Z])', '^$1') }      # a case-sensitive hashtable key
function OrdSort($a) {
    $a = @($a); if ($a.Count -le 1) { return , $a }
    $mid = [int](($a.Count - ($a.Count % 2)) / 2)
    $l = OrdSort $a[0..($mid - 1)]; $r = OrdSort $a[$mid..($a.Count - 1)]
    $o = @(); $i = 0; $j = 0
    while ($i -lt $l.Count -and $j -lt $r.Count) { if ([string]::CompareOrdinal([string]$l[$i], [string]$r[$j]) -le 0) { $o += $l[$i]; $i++ } else { $o += $r[$j]; $j++ } }
    while ($i -lt $l.Count) { $o += $l[$i]; $i++ }; while ($j -lt $r.Count) { $o += $r[$j]; $j++ }
    return , $o
}
function Walk([string]$dir) {
    if (-not (Test-Path -LiteralPath $dir -PathType Container)) { return , @() }
    $acc = @()
    foreach ($e in (OrdSort @(Get-ChildItem -LiteralPath $dir -Force | Where-Object { -not $_.Name.StartsWith('.') } | ForEach-Object { $_.Name }))) {
        $p = "$dir/$e"
        if (Test-Path -LiteralPath $p -PathType Container) { $acc += Walk $p } elseif ($e -match '\.sysml$') { $acc += $p }
    }
    return , $acc
}
$names = @{}; $reqs = @{}; $refs = @(); $errors = 0; $warnings = 0
foreach ($p in (OrdSort (Walk $root))) {
    $t = Get-Content -LiteralPath $p -Raw -Encoding UTF8; if ($null -eq $t) { $t = '' }
    $ls = [regex]::Split($t, "\n"); if ($ls.Count -and $ls[$ls.Count - 1] -eq '') { if ($ls.Count -eq 1) { $ls = @() } else { $ls = $ls[0..($ls.Count - 2)] } }
    $n = 0
    foreach ($line in $ls) {
        $n++
        if ($line.EndsWith("`r")) { $line = $line.Substring(0, $line.Length - 1) }
        $m = [regex]::Match($line, '^\s*(part|port|interface|connection|action|item)( def)?\s+(\w+)')
        if ($m.Success) { $k = CK $m.Groups[3].Value; if ($names.ContainsKey($k)) { $errors++; Write-Output "${p}:${n}: E-DUP duplicate element $($m.Groups[3].Value)" }; $names[$k] = 1 }
        $m = [regex]::Match($line, '^\s*requirement\s+(\w+)\s*\{(.*)\}')
        if ($m.Success) { $reqs[(CK $m.Groups[1].Value)] = 1; if ($m.Groups[2].Value.IndexOf('doorsId') -lt 0) { $warnings++; Write-Output "${p}:${n}: W-REQ requirement $($m.Groups[1].Value) has no doorsId" } }
        $m = [regex]::Match($line, '^\s*(satisfy|verify)\s+(\w+)\b')
        if ($m.Success) { $refs += , @($p, $n, $m.Groups[2].Value) }
    }
}
foreach ($r in $refs) { if ($reqs.ContainsKey((CK $r[2]))) { continue }; $errors++; Write-Output "$($r[0]):$($r[1]): E-REF unknown requirement $($r[2])" }
Write-Output ('elements={0} errors={1} warnings={2}' -f $names.Count, $errors, $warnings)
if ($errors -or $warnings) { exit 1 }
exit 0
