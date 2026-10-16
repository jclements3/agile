<#
idef0-backlog.ps1 -- the agile kit's sim/idef0-backlog.pl in Windows PowerShell 5.1 (Constrained Language Mode safe):
an IDEF0 model -> product backlog, as a planning stand-up file the kit compiles.

  model  (tA Name)          -> tome  "A Name"          and one team per model
  level-1 activity (A1)     -> epic  "A1 Name"
  leaf activity (A111 ...)  -> task  A-111  in the model's team backlog
  cross-model link (A1.o1 > B2.c1 Flow)
                            -> interface task IF-n in the DESTINATION team's backlog, under the SOURCE epic

  idef0-backlog.ps1 MODEL.md [--date YYYY-MM-DD] [--sprint N] [--people N] [--cap N --commit] [--out FILE]
  idef0-backlog.ps1 MODEL.md --roster

Reads the model with idef0.ps1 (dump and links, as the Perl reads idef0.pl's output). --out FILE writes UTF-8.
#>
$ErrorActionPreference = 'Stop'
$script:BLARGS = @($args)
. (Join-Path $PSScriptRoot 'idef0.ps1') __lib

$o = @{ date = '2026-09-23'; sprint = 1; people = 6; roster = $false; cap = 0; commit = $false }
$model = $null; $outFile = $null
for ($i = 0; $i -lt $script:BLARGS.Count; $i++) {
    $a = $script:BLARGS[$i]
    $m = [regex]::Match($a, '^--?(date|sprint|people|cap|out)(?:=(.*))?$')
    if ($m.Success) {
        $v = if ($m.Groups[2].Success) { $m.Groups[2].Value } else { $i++; $script:BLARGS[$i] }
        $k = $m.Groups[1].Value
        if ($k -ceq 'out') { $outFile = $v; continue }
        if ($k -cne 'date') {
            if ($v -cnotmatch '^-?\d+$') { PErr "Value `"$v`" invalid for option $k (number expected)"; Flush $null; exit 2 }
            $v = [int]$v
        }
        $o[$k] = $v; continue
    }
    if ($a -cmatch '^--?roster$') { $o.roster = $true; continue }
    if ($a -cmatch '^--?commit$') { $o.commit = $true; continue }
    if ($a -cmatch '^-') { PErr ("Unknown option: " + ($a -creplace '^--?', '')); Flush $null; exit 2 }
    if ($null -eq $model) { $model = $a }
}
if ($null -eq $model) { PErr 'usage: idef0-backlog.pl MODEL.md [--date D] [--sprint N] [--roster]'; Flush $null; exit 2 }

function Capture([scriptblock]$sb) {                    # run an idef0 command, return its stdout text (a fresh process in Perl)
    $script:OB = @{}; $script:ON = 0; $script:DIAGS = @(); $script:DSEQ = 0; $script:UID = 0
    $null = & $sb
    $t = (@(for ($i = 0; $i -lt $script:ON; $i++) { $script:OB[$i] })) -join ''
    $script:OB = @{}; $script:ON = 0
    $t
}
function Lines([string]$t) { if ($t -eq '') { return , @() }; $l = $t -split "`n"; if ($l[$l.Count - 1] -eq '') { $l = @($l | Select-Object -First ($l.Count - 1)) }; , @($l) }

$TEAM = NewH
$ALIAS = NewH
$ALIAS['Customer Support & Feedback'] = 'Support'; $ALIAS['Human Resources'] = 'HR'; $ALIAS['Research & Development'] = 'Research'; $ALIAS['Executive & Strategy'] = 'Executive'
$FIRST = @('Ann', 'Bob', 'Cy', 'Dee', 'Eve', 'Fay', 'Gus', 'Hal', 'Ida', 'Jon', 'Kim', 'Lou', 'Max', 'Nia', 'Ola', 'Pat', 'Quinn', 'Ray', 'Sam', 'Tia', 'Uma', 'Val', 'Wes', 'Xia', 'Yul', 'Zed')

# ---- parse the dump: models, activities (id, name, depth), children
$modelName = NewH; $act = NewH; $order = @()
foreach ($ln in (Lines (Capture { CmdDump @($model) }))) {
    $mm = [regex]::Match($ln, '^([A-Z])\s{2,}(.+?)\s{2,}\[')
    if ($mm.Success) { $modelName[$mm.Groups[1].Value] = $mm.Groups[2].Value; continue }
    $mm = [regex]::Match($ln, '^(\s*)([A-Z]\d+)\s{2,}(\S.*)$')
    if ($mm.Success) {
        $id = $mm.Groups[2].Value; $name = $mm.Groups[3].Value
        $act[$id] = @{ id = $id; name = $name; model = $id.Substring(0, 1); depth = $id.Length - 1; kids = 0 }
        $order += , $id
        $parent = $id.Substring(0, $id.Length - 1)
        if ($parent.Length -gt 1 -and $act.ContainsKey($parent)) { $act[$parent].kids++ }
    }
}
if (-not $order.Count) { PErr "no activities found in $model (is tools/idef0/idef0.pl runnable?)"; Flush $null; exit 255 }
foreach ($mk in @($modelName.Keys)) {
    $n = $modelName[$mk]
    if ($ALIAS.ContainsKey($n)) { $TEAM[$mk] = $ALIAS[$n] }
    else { $w = [regex]::Match($n, '([A-Za-z0-9]+)'); $TEAM[$mk] = if ($w.Success) { $w.Groups[1].Value } else { $mk } }
}

# ---- links from the INTERFACES table: SOURCE DEST FLOW
$links = @()
foreach ($ln in (Lines (Capture { CmdLinks @($model) }))) {
    if ($ln -cmatch '^SOURCE' -or $ln -cnotmatch '\S') { continue }
    $parts = [regex]::Split($ln, '\s{2,}', 3)
    if ($parts.Count -ge 2 -and $parts[0] -ne '' -and $parts[0] -cne '0' -and $parts[1] -ne '' -and $parts[1] -cne '0') {
        $links += , @($parts[0], $parts[1], $(if ($parts.Count -ge 3) { $parts[2] } else { $null }))
    }
}

# ---- rosters: N people per team, deterministic
$letters = SortStr @($modelName.Keys)
$roster = NewH; $pi = 0
foreach ($mk in $letters) { $roster[$mk] = @(for ($q = 1; $q -le $o.people; $q++) { $FIRST[$pi % $FIRST.Count] + " $($TEAM[$mk])"; $pi++ }) }
if ($o.roster) {
    foreach ($mk in $letters) { P ("$($TEAM[$mk]) ($mk $($modelName[$mk])): " + ($roster[$mk] -join ', ') + "`n") }
    Flush $outFile; exit 0
}

# ---- emit the planning stand-up file
function Q_([string]$s) { '"' + $s.Replace(',', ';').Replace('"', "'") + '"' }
function EpicOf([string]$id) { $e = $id.Substring(0, 2); if ($act.ContainsKey($e)) { "$e $($act[$e].name)" } else { "$id $($act[$id].name)" } }
function TomeOf([string]$m) { "$m $($modelName[$m])" }
$pick = NewH
function Owner([string]$m) { $r = $roster[$m]; $c = $pick[$m]; if ($null -eq $c) { $c = 0 }; $pick[$m] = $c + 1; $r[$c % $r.Count] }
function Pts($d) { if ($d -eq 1) { 8 } elseif ($d -eq 2) { 5 } else { 3 } }
function Prio($d) { if ($d -le 2) { 1 } elseif ($d -eq 3) { 2 } else { 3 } }
P "$($o.date)`nsprint $($o.sprint)`n"
foreach ($mk in $letters) {
    $teamName = if ($TEAM.ContainsKey($mk)) { $TEAM[$mk] } else { $mk }
    P "`n== $teamName`n"
    if ($o.cap) { P "cap $($o.cap)`n" }
    foreach ($id in $order) {
        $ac = $act[$id]
        if ($ac.model -cne $mk -or $ac.kids -ne 0) { continue }
        $tid = $id -creplace '^([A-Z])', '$1-'
        P ("new $tid $(Pts $ac.depth) " + $ac.name.Replace(',', ';') + " p:$(Prio $ac.depth) e:" + (Q_ (EpicOf $id)) + ' t:' + (Q_ (TomeOf $mk)) + ' o:' + (Q_ (Owner $mk)) + "`n")
    }
}
$i = 0
$byTeam = NewH; $tasks = NewH
foreach ($id in $order) {
    $ac = $act[$id]; if ($ac.kids) { continue }
    $tid = $id -creplace '^([A-Z])', '$1-'
    if (-not $tasks.ContainsKey($ac.model)) { $tasks[$ac.model] = @() }
    $tasks[$ac.model] += , @{ id = $tid; pts = (Pts $ac.depth); prio = (Prio $ac.depth) }
}
foreach ($lk in $links) {
    $src = $lk[0]; $dst = $lk[1]; $flow = $lk[2]
    $sm0 = [regex]::Match($src, '^([A-Z]\d+)'); $dm0 = [regex]::Match($dst, '^([A-Z]\d+)')
    if (-not $sm0.Success -or -not $dm0.Success) { continue }
    $sa = $sm0.Groups[1].Value; $da = $dm0.Groups[1].Value
    if (-not $act.ContainsKey($sa) -or -not $act.ContainsKey($da)) { continue }
    $dm = $da.Substring(0, 1); $sm = $sa.Substring(0, 1)
    $i++
    if (-not $byTeam.ContainsKey($dm)) { $byTeam[$dm] = @() }
    $fl = if ($null -eq $flow) { '' } else { $flow.Replace(',', ';') }
    $byTeam[$dm] += , ("new IF-$i 5 Interface: $fl from $($TEAM[$sm]) to $($TEAM[$dm]) p:1 e:" + (Q_ (EpicOf $sa)) + ' t:' + (Q_ (TomeOf $sm)) + ' o:' + (Q_ (Owner $dm)))
    if (-not $tasks.ContainsKey($dm)) { $tasks[$dm] = @() }
    $tasks[$dm] += , @{ id = "IF-$i"; pts = 5; prio = 1 }
}
foreach ($mk in (SortStr @($byTeam.Keys))) { P "`n== $($TEAM[$mk])`n"; foreach ($l in $byTeam[$mk]) { P "$l`n" } }
if ($o.commit -and $o.cap) {
    foreach ($mk in (SortStr @($tasks.Keys))) {
        $sum = 0; $c = @()
        $sorted = SortBy $tasks[$mk] {
            param($x, $y)
            $r = NumCmp $x.prio $y.prio; if ($r) { return $r }
            $xi = if ($x.id -cmatch '^IF') { 1 } else { 0 }; $yi = if ($y.id -cmatch '^IF') { 1 } else { 0 }
            $r = NumCmp $yi $xi; if ($r) { return $r }
            Cmp $x.id $y.id
        }
        foreach ($t in $sorted) { if ($sum + $t.pts -gt $o.cap) { continue }; $c += , $t.id; $sum += $t.pts }
        if ($c.Count) { P "`n== $($TEAM[$mk])`n"; foreach ($x in $c) { P "commit $x`n" } }
    }
}
Flush $outFile
exit 0
