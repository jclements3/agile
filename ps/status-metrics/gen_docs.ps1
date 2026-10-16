<#
gen_docs.ps1 -- generate documents from the model: the status-metrics simulation's generator
(sim/status-metrics/gen_docs.pl) in Windows PowerShell 5.1, Constrained Language Mode safe. Same bytes out.

  gen_docs.ps1 SRC OUT      # OUT/docs/<doc> for each name in SRC/docs/enabled.txt; OUT/params/params.h when
                            # SRC/model/T/params.sysml exists. Deterministic (no dates). Used as gen_cmd.
#>
$ErrorActionPreference = 'Stop'
if ($args.Count -lt 2) { Write-Host 'usage: gen_docs.ps1 SRC OUT'; exit 2 }
$src = ([string]$args[0]).Replace('\', '/').TrimEnd('/'); $out = ([string]$args[1]).Replace('\', '/').TrimEnd('/')
. (Join-Path $PSScriptRoot '..\ziplib.ps1')
function CK([string]$s) { return ($s -creplace '([A-Z])', '^$1') }
function OrdSort($a) {
    $a = @($a); if ($a.Count -le 1) { return , $a }
    $mid = [int](($a.Count - ($a.Count % 2)) / 2)
    $l = OrdSort $a[0..($mid - 1)]; $r = OrdSort $a[$mid..($a.Count - 1)]
    $i = 0; $j = 0                                   # the loops' output is the merged list (no += copies)
    $o = @(while ($i -lt $l.Count -and $j -lt $r.Count) { if ([string]::CompareOrdinal([string]$l[$i], [string]$r[$j]) -le 0) { $l[$i]; $i++ } else { $r[$j]; $j++ } }
        while ($i -lt $l.Count) { $l[$i]; $i++ }; while ($j -lt $r.Count) { $r[$j]; $j++ })
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
function Lines([string]$p) {
    $t = Get-Content -LiteralPath $p -Raw -Encoding UTF8; if ($null -eq $t -or $t -eq '') { return , @() }
    $l = [regex]::Split($t, "\r\n|\r|\n"); if ($l[$l.Count - 1] -eq '') { if ($l.Count -eq 1) { return , @() }; $l = $l[0..($l.Count - 2)] }
    return , @($l)
}
function Attrs([string]$t) { $a = @{}; foreach ($m in [regex]::Matches($t, '(\w+)\s*=\s*"([^"]*)"')) { $a[$m.Groups[1].Value] = $m.Groups[2].Value }; return $a }
function S($x) { if ($null -eq $x) { return '' }; return [string]$x }
$els = @{}; $reqs = @{}; $sat = @{}; $ver = @{}; $ifcs = @{}; $thr = @{}; $prm = @()
foreach ($p in (OrdSort (Walk "$src/model"))) {
    $seg = ([regex]::Match($p.Substring("$src/model/".Length), '^([^/]+)')).Groups[1].Value
    foreach ($line in (Lines $p)) {
        $m = [regex]::Match($line, '^\s*(part|port|interface|connection|action|item)( def)?\s+(\w+)'); if ($m.Success) { $els[(CK $m.Groups[3].Value)] = @($m.Groups[3].Value, $seg) }
        $m = [regex]::Match($line, '^\s*requirement\s+(\w+)\s*\{(.*)\}'); if ($m.Success) { $d = (Attrs $m.Groups[2].Value)['doorsId']; $reqs[(CK $m.Groups[1].Value)] = @($m.Groups[1].Value, (S $d)) }
        $m = [regex]::Match($line, '^\s*satisfy\s+(\w+)\b'); if ($m.Success) { $sat[(CK $m.Groups[1].Value)] = 1 }
        $m = [regex]::Match($line, '^\s*verify\s+(\w+)\b'); if ($m.Success) { $ver[(CK $m.Groups[1].Value)] = 1 }
        $m = [regex]::Match($line, '^\s*interface\s+(\w+)\s*\{(.*)\}'); if ($m.Success) { $ifcs[(CK $m.Groups[1].Value)] = @($m.Groups[1].Value, (Attrs $m.Groups[2].Value)) }
        $m = [regex]::Match($line, '^\s*metadata\s+(\w+)\s*:\s*Threat\s*\{(.*)\}'); if ($m.Success) { $thr[(CK $m.Groups[1].Value)] = @($m.Groups[1].Value, (Attrs $m.Groups[2].Value)) }
        if ($seg -ceq 'T' -and $p -match 'params\.sysml$') { $m = [regex]::Match($line, '^\s*attribute\s+(\w+)\s*:'); if ($m.Success) { $prm += $m.Groups[1].Value } }
    }
}
$script:SORTED = @{}
function Sorted([string]$which) {                    # the named table's entries by name, sorted once per run
    if (-not $script:SORTED.ContainsKey($which)) {
        $h = @{ els = $els; reqs = $reqs; ifcs = $ifcs; thr = $thr }[$which]
        $ns = OrdSort @(foreach ($v in $h.Values) { $v[0] })
        $script:SORTED[$which] = @(foreach ($n in $ns) { , $h[(CK $n)] })
    }
    return , $script:SORTED[$which]
}
if (Test-Path -LiteralPath $out) { Remove-Item -LiteralPath $out -Recurse -Force }
New-Item -ItemType Directory -Force -Path "$out/docs" | Out-Null
$enabled = @(); if (Test-Path -LiteralPath "$src/docs/enabled.txt") { $enabled = @((Lines "$src/docs/enabled.txt") | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' }) }
function W([string]$name, $lines) { Zl-WriteBytes "$out/docs/$name" (Zl-Utf8Enc ((@($lines) -join "`n") + "`n")) }
foreach ($d in $enabled) {
    if ($d -ceq 'interface_table.csv') { W $d (@('id,from,to,secReq') + @(foreach ($e in (Sorted 'ifcs')) { $v = $e[1]; "$($e[0]),$(S $v['fromSeg']),$(S $v['toSeg']),$(S $v['secReq'])" })) }
    elseif ($d -ceq 'icd.csv') { W $d (@('id,from,to,fromZone,toZone,signal,rate,units') + @(foreach ($e in (Sorted 'ifcs')) { $v = $e[1]; (@($e[0]) + @(foreach ($f in 'fromSeg', 'toSeg', 'fromZone', 'toZone', 'signal', 'rate', 'units') { S $v[$f] })) -join ',' })) }
    elseif ($d -ceq 'req_trace.csv') { W $d (@('req,doorsId,satisfied,verified') + @(foreach ($e in (Sorted 'reqs')) { $k = CK $e[0]; $s1 = 0; if ($sat.ContainsKey($k)) { $s1 = 1 }; $v1 = 0; if ($ver.ContainsKey($k)) { $v1 = 1 }; "$($e[0]),$($e[1]),$s1,$v1" })) }
    elseif ($d -ceq 'element_index.txt') { W $d @(foreach ($e in (Sorted 'els')) { "$($e[0]) $($e[1])" }) }
    elseif ($d -ceq 'threat_register.csv') { W $d (@('threat,mitigation') + @(foreach ($e in (Sorted 'thr')) { "$($e[0]),$(S $e[1]['mitigation'])" })) }
    elseif ($d -cmatch '^seg_') { $s2 = ($d.Substring(4) -split '\.')[0]; W $d @(foreach ($e in (Sorted 'els')) { if ($e[1] -ceq $s2) { $e[0] } }) }
}
if ($prm.Count) {
    New-Item -ItemType Directory -Force -Path "$out/params" | Out-Null
    Zl-WriteBytes "$out/params/params.h" (Zl-Utf8Enc (-join @(foreach ($x in $prm) { '#define ' + $x.ToUpperInvariant() + " 0`n" })))
}
exit 0
