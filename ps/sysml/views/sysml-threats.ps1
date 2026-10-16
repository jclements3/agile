<#
sysml-threats.ps1 : threat-model checks on a SysML v2 model (SecMeta), with a threat table.
PowerShell port of tools/sysml/views/sysml-threats.pl (Constrained Language Mode safe, pure ASCII).

  sysml-threats.ps1 [--today YYYY-MM-DD] DIR|FILE...

Same checks, table, diagnostics and exit status as the Perl (0 no errors, 1 errors, 2 usage error).
#>
. (Join-Path $PSScriptRoot 'views-lib.ps1')
$go = GetOpts $args @('today=s')
if (-not $go.ok -or -not @($go.rest).Count) { VFlush; PErr 'usage: perl sysml-threats.pl [--today YYYY-MM-DD] DIR|FILE...'; exit 2 }
$O = $go.opts
$TODAY = if ($null -ne $O['today']) { $O['today'] } else { TodayStr }
if ($TODAY -cnotmatch '^\d{4}-\d\d-\d\d$') { PErr 'sysml-threats: --today must be YYYY-MM-DD'; exit 2 }
$files = @()
foreach ($a in @($go.rest)) {
    if (IsDir $a) { $files += @(FindSysml $a) }
    elseif (IsFile $a) { $files += , $a }
    else { PErr "sysml-threats: ${a}: no such file or directory"; exit 2 }
}
$files = SortStr $files
$NAME = $script:NAMERX; $REF = $script:REFRX

# ------------------------------------------------------------------ parse
$script:NODES = @(); $script:SATS = @(); $script:VERS = @()
function Finish($s) {
    if ($s.kind -ne 'meta' -or $null -eq $s.target) { return }
    $e = CopyRec $s.attrs @{ file = $s.file; line = $s.line }
    $mm = $s.target.meta
    if ($null -eq $mm[$s.name]) { $mm[$s.name] = @() }
    $mm[$s.name] = @($mm[$s.name]) + , $e
}
function Statement([string]$s, [string]$f, [int]$line, $stack, [int]$sn, [string]$c) {
    $top = $stack[$sn - 1]
    $s = Squash $s
    if ($s -eq '') { return $null }
    $pkg = $top.pkg
    $owner = $null; for ($i = $sn - 1; $i -ge 0; $i--) { if ($null -ne $stack[$i].node) { $owner = $stack[$i].node; break } }
    if ($top.kind -eq 'meta') {
        $m = M $s '^(?::>>\s*)?(\w+)\s*=\s*("(?:[^"\\]|\\.)*"|\S+)'
        if ($m.Success) { $top.attrs[$m.Groups[1].Value] = Sval $m.Groups[2].Value }
        return $null
    }
    $m = M $s "^metadata\s+($NAME)\s*(?::|\bdefined\s+by\b)\s*(?:\w+::)*Threat$"
    if ($m.Success) {
        $n = Unq $m.Groups[1].Value
        $node = Rec @{ kind = 'metadata'; name = $n; id = ''; isreq = $false; pkg = $pkg; path = @($n); file = $f; line = $line; meta = (NewH) }
        $script:NODES += , $node
        return (Rec @{ kind = 'meta'; name = 'Threat'; target = $node; attrs = (NewH); pkg = $pkg; file = $f; line = $line })
    }
    $m = M $s '^@\s*(?:\w+::)*(\w+)\s*$'; if (-not $m.Success) { $m = M $s '^metadata\s+(?:\w+::)*(\w+)\s*$' }
    if ($m.Success) { return (Rec @{ kind = 'meta'; name = $m.Groups[1].Value; target = $owner; attrs = (NewH); pkg = $pkg; file = $f; line = $line }) }
    $hash = @()
    $s = Sub $s '^(?:(?:public|private|protected|abstract|variation|individual|derived|readonly)\s+)*' ''
    while ($true) { $m = M $s '^#\s*(?:\w+::)*(\w+)\s*'; if (-not $m.Success) { break }; $hash += , $m.Groups[1].Value; $s = $s.Substring($m.Length) }
    $m = M $s "^(?:standard\s+)?(?:library\s+)?package\s+($NAME)"
    if ($m.Success) { return (Rec @{ kind = 'package'; pkg = (@($pkg) + , (Unq $m.Groups[1].Value)) }) }
    $m = M $s "^satisfy\s+(?:requirement\s+)?($REF)\s+by\s+($REF)"
    if ($m.Success) { $script:SATS += , @{ ref = (Segs $m.Groups[1].Value); file = $f; line = $line }; return $null }
    $m = M $s "^verify\s+(?:requirement\s+)?($REF)"
    if ($m.Success) { $script:VERS += , @{ ref = (Segs $m.Groups[1].Value); file = $f; line = $line }; return $null }
    $m = M $s "^(\w+(?:\s+def)?)\s+(?:<'((?:[^'\\]|\\.)*)'>\s*)?($NAME)"
    if ($m.Success -and $m.Groups[1].Value -cnotmatch '^(?:import|alias|dependency|doc|comment|subject|objective|return|in|out|inout)$') {
        $kw = $m.Groups[1].Value; $id = Dflt (G $m 2) ''; $n = Unq $m.Groups[3].Value
        $isreq = $kw -ceq 'requirement'
        $path = @(for ($i = 0; $i -lt $sn; $i++) { $x = $stack[$i].node; if ($null -ne $x -and $x.isreq) { $x.name } }) + , $n
        $up = $null; if ($null -ne $owner -and $owner.isreq -and $isreq) { $up = $owner }
        $pth = if ($isreq) { , $path } else { , @($n) }
        $node = Rec @{ kind = $kw; name = $n; id = $id; isreq = $isreq; pkg = $pkg; path = $pth; up = $up; file = $f; line = $line; meta = (NewH) }
        foreach ($h in $hash) { if ($null -eq $node.meta[$h]) { $node.meta[$h] = @() }; $node.meta[$h] = @($node.meta[$h]) + , (Rec @{ file = $f; line = $line }) }
        $script:NODES += , $node
        if ($c -eq '{') { return (Rec @{ kind = 'node'; node = $node; pkg = $pkg }) }
        return $null
    }
    $null
}
$TOK = Rx '\G(?:(\n)|(//[^\n]*)|(/\*)|("(?:[^"\\]|\\.)*"|''(?:[^''\\]|\\.)*'')|([{};])|([^{};"''/\n]+|/))'
foreach ($f in $files) {
    $t = VRead $f
    $stack = @{}; $stack[0] = Rec @{ kind = 'file'; pkg = @() }; $sn = 1
    $head = ''; $hline = 1; $line = 1; $pos = 0; $len = $t.Length
    while ($pos -lt $len) {
        $m = $TOK.Match($t, $pos)
        if (-not $m.Success) { $pos++; continue }
        $pos = $m.Index + $m.Length
        if ($m.Groups[1].Success) { $line++; $head += ' ' }
        elseif ($m.Groups[2].Success) { }
        elseif ($m.Groups[3].Success) {
            $from = $pos; $end = $t.IndexOf('*/', $from); if ($end -lt 0) { $end = $len }
            $body = $t.Substring($from, $end - $from); $pos = $end + 2
            $line += NlCount $body
            if (T $head '^\s*doc\b') {
                $body = DocBody $body
                $n = $null; for ($i = $sn - 1; $i -ge 0; $i--) { if ($null -ne $stack[$i].node) { $n = $stack[$i]; break } }
                if ($null -ne $n -and $null -eq $n.node.doc) { $n.node.doc = $body }
                $head = ''
            } elseif (T $head '^\s*comment\b') { $head = '' }
        }
        elseif ($m.Groups[4].Success) { $q = $m.Groups[4].Value; if (-not (T $head '\S')) { $hline = $line }; $head += $q; $line += NlCount $q }
        elseif ($m.Groups[5].Success) {
            $c = $m.Groups[5].Value
            if ($c -eq '}') { if ($sn -gt 1) { $sn--; Finish $stack[$sn] }; $head = ''; continue }
            $st = Statement $head $f $hline $stack $sn $c
            $head = ''
            if ($c -eq '{') { if ($null -eq $st) { $st = Rec @{ kind = 'other'; pkg = $stack[$sn - 1].pkg } }; $stack[$sn] = $st; $sn++ }
            elseif ($null -ne $st -and $st.kind -eq 'meta') { Finish $st }
        }
        else { $x = $m.Groups[6].Value; if (-not (T $head '\S') -and (T $x '\S')) { $hline = $line }; $head += $x }
    }
}

# ------------------------------------------------------------------ checks
$script:NERR = 0; $script:NWARN = 0; $script:DIAG = @()
function Diag([string]$f, [int]$l, [string]$sev, [string]$msg) {
    $script:DIAG += , @($f, $l, $script:DIAG.Count, "${f}:${l}: ${sev}: $msg")
    if ($sev -eq 'error') { $script:NERR++ } else { $script:NWARN++ }
}
$STRIDEMAP = NewH
foreach ($x in @('Spoofing', 'Tampering', 'Repudiation', 'Information disclosure', 'Denial of service', 'Elevation of privilege')) { $STRIDEMAP[$x.ToLower()] = $x }
$reqs = @($script:NODES | Where-Object { $_.isreq -and $_.kind -ceq 'requirement' })
function Hit($r, $sg) {
    $full = @($r.pkg) + @($r.path); $sg = @($sg)
    if ($full.Count -lt $sg.Count) { return $false }
    $tail = @($full[($full.Count - $sg.Count)..($full.Count - 1)])
    ($tail -join "`0") -ceq ($sg -join "`0")
}
foreach ($s in $script:SATS) { foreach ($r in $reqs) { if (Hit $r $s.ref) { $r.sat_direct = $true } } }
foreach ($v in $script:VERS) { foreach ($r in $reqs) { if (Hit $r $v.ref) { $r.ver_direct = $true } } }
foreach ($r in $reqs) { for ($ow = $r; $null -ne $ow; $ow = $ow.up) { if (-not $r.sat) { $r.sat = [bool]$ow.sat_direct }; if (-not $r.ver) { $r.ver = [bool]$ow.ver_direct } } }

$threats = @($script:NODES | Where-Object { $null -ne $_.meta['Threat'] })
$tbyname = NewH; foreach ($t in $threats) { if ($null -eq $tbyname[$t.name]) { $tbyname[$t.name] = @() }; $tbyname[$t.name] = @($tbyname[$t.name]) + , $t }
$mit = @{}; $nmit = 0
foreach ($r in $reqs) {
    foreach ($m in (Arr $r.meta['Mitigates'])) {
        $nmit++
        $tn = $m['threat']
        $rn = if ($r.id -ne '') { $r.id } else { $r.name }
        if ($null -eq $tn -or $tn -eq '') { Diag $m.file $m.line 'error' "@Mitigates on requirement '$rn' names no threat"; continue }
        $last = @(SplitKeep $tn '::|\.'); $last = if ($last.Count) { $last[-1] } else { '' }
        $tl = (Arr $tbyname[$last])
        if (-not $tl.Count) { Diag $m.file $m.line 'error' "@Mitigates on requirement '$rn' names unknown threat '$tn'"; continue }
        foreach ($t in $tl) { $k = Id $t; if ($null -eq $mit[$k]) { $mit[$k] = @() }; $mit[$k] = @($mit[$k]) + , $r }
    }
}
function RName($r) { if ($r.id -ne '') { $r.id } else { $r.name } }
$rows = @(); $nacc = 0
foreach ($t in $threats) {
    $m = $t.meta['Threat'][0]
    $stride = Dflt $m['stride'] ''; $capec = Dflt $m['capec'] ''
    $bad = @()
    if ($stride -eq '') { $bad += , 'no STRIDE category' }
    elseif ($null -eq $STRIDEMAP[$stride.ToLower()]) { $bad += , "STRIDE category '$stride' is not one of the six" }
    if ($capec -eq '') { $bad += , 'no CAPEC id' }
    elseif ($capec -cnotmatch '^CAPEC-\d+$') { $bad += , "CAPEC id '$capec' is not CAPEC-n" }
    foreach ($b in $bad) { Diag $m.file $m.line 'error' "threat '$($t.name)': $b" }
    $rq = (Arr $mit[(Id $t)])
    $good = @($rq | Where-Object { $_.sat -and $_.ver })
    if ($good.Count) { $status = 'mitigated' }
    else {
        if (-not $rq.Count) { $why = 'is not mitigated by any requirement' }
        else {
            $parts = @(); if (@($rq | Where-Object { -not $_.sat }).Count) { $parts += , 'satisfied' }; if (@($rq | Where-Object { -not $_.ver }).Count) { $parts += , 'verified' }
            $why = 'is mitigated only by requirements that are not ' + ($parts -join ' and ') + ' (' + ((@($rq | ForEach-Object { (RName $_) + ':' + $(if ($_.sat) { '' } else { ' not satisfied' }) + $(if ($_.ver) { '' } else { ' not verified' }) })) -join ', ') + ')'
        }
        $acc = (Arr $t.meta['RiskAcceptance'])
        $cur = $null
        foreach ($a in $acc) { if ((Dflt $a['approver'] '') -ne '' -and (Dflt $a['expires'] '') -cmatch '^\d{4}-\d\d-\d\d$' -and [string]::CompareOrdinal($a['expires'], $TODAY) -ge 0) { $cur = $a; break } }
        if ($null -ne $cur) {
            $nacc++
            $status = "accepted until $($cur['expires']) ($($cur['approver']))"
            Diag $t.file $t.line 'warning' "threat '$($t.name)' $why; accepted by risk acceptance (approver: $($cur['approver']), expires $($cur['expires']))"
        } else {
            $status = if (-not $rq.Count) { 'UNMITIGATED' } else { 'NOT CLOSED' }
            foreach ($a in $acc) {
                $p = if ((Dflt $a['approver'] '') -eq '') { 'has no approver' } elseif ((Dflt $a['expires'] '') -cnotmatch '^\d{4}-\d\d-\d\d$') { 'has no expiry date (YYYY-MM-DD)' } else { "expired on $($a['expires'])" }
                Diag $a.file $a.line 'error' "risk acceptance on threat '$($t.name)' $p"
            }
            Diag $t.file $t.line 'error' "threat '$($t.name)' $why"
        }
    }
    if ($null -ne $m['mitigation']) {
        $attr = $m['mitigation']
        $by = NewH; foreach ($x in $rq) { $by[$x.name] = 1; if ($x.id -ne '') { $by[$x.id] = 1 } }
        $lastA = @(SplitKeep $attr '::|\.'); $lastA = if ($lastA.Count) { $lastA[-1] } else { '' }
        if ($attr -ne '' -and -not $by.ContainsKey($lastA)) { Diag $m.file $m.line 'warning' "threat '$($t.name)': mitigation = `"$attr`" but no @Mitigates on '$attr' names it" }
        if ($attr -eq '' -and $rq.Count) { Diag $m.file $m.line 'warning' ("threat '$($t.name)': @Mitigates on " + ((@($rq | ForEach-Object { RName $_ })) -join ', ') + ' but mitigation = ""') }
    }
    if ($bad.Count) { $status = "INCOMPLETE; $status" }
    $sc = if ($null -ne $STRIDEMAP[$stride.ToLower()]) { $STRIDEMAP[$stride.ToLower()] } elseif ($stride -eq '') { '-' } else { "?$stride" }
    $mc = if ($rq.Count) { (@($rq | ForEach-Object { (RName $_) + ' (' + $(if ($_.sat) { 'S' } else { '-' }) + $(if ($_.ver) { 'V' } else { '-' }) + ')' })) -join ', ' } else { '-' }
    $rows += , @($t.name, $sc, $(if ($capec -eq '') { '-' } else { $capec }), $mc, $status)
}

# ------------------------------------------------------------------ report
$hdr = @('threat', 'STRIDE', 'CAPEC', 'mitigated by (S satisfied, V verified)', 'status')
$w = @($hdr | ForEach-Object { $_.Length })
foreach ($r in $rows) { for ($i = 0; $i -lt $r.Count - 1; $i++) { if ($r[$i].Length -gt $w[$i]) { $w[$i] = $r[$i].Length } } }
function Row($cells) { $s = ''; for ($i = 0; $i -lt 4; $i++) { $s += (PadR $cells[$i] $w[$i]) + '  ' }; PL ($s + $cells[4]) }
if ($rows.Count) {
    Row $hdr
    Row @(('-' * $w[0]), ('-' * $w[1]), ('-' * $w[2]), ('-' * $w[3]), ('-' * $hdr[4].Length))
    foreach ($r in $rows) { Row $r }
    PL ''
}
foreach ($d in (SortBy $script:DIAG { param($x, $y) $c = Cmp $x[0] $y[0]; if ($c) { return $c }; $c = NCmp $x[1] $y[1]; if ($c) { return $c }; NCmp $x[2] $y[2] })) { PL $d[3] }
PL ("{0} file(s): {1} error(s), {2} warning(s), {3} threat(s), {4} mitigation(s), {5} risk acceptance(s) in force" -f $files.Count, $script:NERR, $script:NWARN, $threats.Count, $nmit, $nacc)
VFlush
if ($script:NERR) { exit 1 } else { exit 0 }
