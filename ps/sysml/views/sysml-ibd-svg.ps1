<#
sysml-ibd-svg.ps1 : interconnection view (parts, ports, connections) of SysML v2 part defs, as one SVG, colored by
SecMeta trust zone, with the boundary-coverage check (SEC-1).
PowerShell port of tools/sysml/views/sysml-ibd-svg.pl (Constrained Language Mode safe, pure ASCII).

  sysml-ibd-svg.ps1 [-o ibd.svg] [--title T] [--root NAME]... DIR|FILE...

Same options, SVG bytes, diagnostics and exit status as the Perl (0 no errors, 1 errors, 2 usage error).
#>
. (Join-Path $PSScriptRoot 'views-lib.ps1')
VBufferStderr
$go = GetOpts $args @('o=s', 'title=s', 'root=s@')
if (-not $go.ok -or -not @($go.rest).Count) { PErr 'usage: perl sysml-ibd-svg.pl [-o ibd.svg] [--title T] [--root NAME]... DIR|FILE...'; VExit 2 }
$OPT = $go.opts; $ARGV0 = @($go.rest)
if ($null -eq $OPT['o']) { $OPT['o'] = 'ibd.svg' }
$ROOTOPTS = @(); if ($null -ne $OPT['root']) { $ROOTOPTS = @($OPT['root']) }
$FILES = @()
foreach ($a in $ARGV0) {
    if (IsDir $a) { $FILES += @(FindSysml $a) }
    elseif (IsFile $a) { $FILES += , $a }
    else { PErr "sysml-ibd-svg: ${a}: no such file or directory"; VExit 2 }
}
$FILES = SortStr $FILES
$NAMEP = $script:NAMERX; $REFP = $script:REFRX
$CHAIN = "$NAMEP(?:\s*\.\s*$NAMEP)*"
$script:NERR = 0; $script:NWARN = 0; $script:NNOTE = 0; $script:DIAG = @()
function Diag([string]$f, $l, [string]$sev, [string]$msg) {
    $script:DIAG += , @($f, [long]$l, $script:DIAG.Count, "${f}:$(N $l): ${sev}: $msg")
    if ($sev -eq 'error') { $script:NERR++ } elseif ($sev -eq 'warning') { $script:NWARN++ } else { $script:NNOTE++ }
}

# ------------------------------------------------------------------ parse
$DEFLIST = @(); $DEFBYNAME = NewH; $REQLIST = @(); $REQDEFS = NewH; $SATLIST = @()
function Classify([string]$s, [string]$f, [int]$line, $stack, [int]$sn) {
    $top = $stack[$sn - 1]
    $s = Squash $s
    if ($s -eq '') { return $null }
    $pkg = $top.pkg
    $node = $top.node
    if ($top.kind -ceq 'conn') {
        $cn = $top.conn
        $m = M $s "^end\b\s*(?:$NAMEP\s*)?(?::\s*~?\s*$REFP\s*)?(?:::>|\breferences\b)\s*($CHAIN)"
        if (-not $top.done -and $m.Success) {
            $top.ends = @($top.ends) + , (@($top.pre) + (Segs $m.Groups[1].Value))
            if (@($top.ends).Count -eq 2) { $cn.ends = $top.ends; $cn.owner.conns = @($cn.owner.conns) + , $cn; $top.done = $true }
        } else {
            $m = M $s '^attribute\s+(secReq|fromZone|toZone)\b[^=]*=\s*"((?:[^"\\]|\\.)*)"'
            if ($m.Success) { $cn.attr[$m.Groups[1].Value] = $m.Groups[2].Value }
        }
        return $null
    }
    $m = M $s '^@\s*(?:SecMeta::)?TrustZone\b(.*)$'
    if ($m.Success) {
        $m2 = M $m.Groups[1].Value 'zone\s*=\s*(?:\w+::)*(\w+)'
        if ($null -ne $node -and $m2.Success) { $node.zone = $m2.Groups[1].Value }
        return (Rec @{ kind = 'zone'; target = $node; pkg = $pkg })
    }
    $m = M $s '^(?::>>\s*)?zone\s*=\s*(?:\w+::)*(\w+)'
    if ($top.kind -ceq 'zone' -and $m.Success) { if ($null -ne $top.target) { $top.target.zone = $m.Groups[1].Value }; return $null }
    if (T $s '^@\s*(?:SecMeta::)?SecurityRequirement\b') { if ($null -ne $node -and $node.isreq) { $node.secreq = $true }; return (Rec @{ kind = 'other'; pkg = $pkg }) }
    if ((T $s '^@') -or (T $s '^metadata\s')) { return (Rec @{ kind = 'other'; pkg = $pkg }) }
    $hash = @()
    $s = Sub $s '^(?:(?:public|private|protected|abstract|variation|individual|derived|readonly)\s+)*' ''
    while ($true) { $m = M $s "^#\s*($NAMEP)\s*"; if (-not $m.Success) { break }; $hash += , (Unq $m.Groups[1].Value); $s = $s.Substring($m.Length) }
    $hasSec = @($hash | Where-Object { $_ -ceq 'SecurityRequirement' }).Count -gt 0
    if ($null -ne $node -and $node.isreq -and $hasSec) { $node.secreq = $true }
    $m = M $s "^(?:standard\s+)?(?:library\s+)?package\s+($NAMEP)"
    if ($m.Success) { return (Rec @{ kind = 'package'; pkg = (@($pkg) + , (Unq $m.Groups[1].Value)) }) }
    $m = M $s "^satisfy\s+(?:requirement\s+)?($REFP)\s+by\s+($REFP)"
    if ($m.Success) { $script:SATLIST += , @{ ref = (Segs $m.Groups[1].Value); file = $f; line = $line }; return $null }
    $m = M $s "^requirement\s+def\s+($NAMEP)"
    if ($m.Success) {
        $r = Rec @{ isreq = $true; name = (Unq $m.Groups[1].Value); pkg = $pkg; file = $f; line = $line }
        if ($hasSec) { $r.secreq = $true }
        $REQDEFS[$r.name] = $r
        return (Rec @{ kind = 'node'; node = $r; pkg = $pkg })
    }
    $m = M $s "^requirement\s+(?:<'[^']*'>\s*)?($NAMEP)(.*)$"
    if ($m.Success) {
        $n = Unq $m.Groups[1].Value; $rest = $m.Groups[2].Value
        $path = @(for ($i = 0; $i -lt $sn; $i++) { $x = $stack[$i].node; if ($null -ne $x -and $x.isreq -and -not $x.isdef) { $x.name } }) + , $n
        $up = $null; if ($null -ne $node -and $node.isreq) { $up = $node }
        $r = Rec @{ isreq = $true; name = $n; path = $path; pkg = $pkg; file = $f; line = $line; up = $up }
        $m2 = M $rest "^\s*:\s*($REFP)"
        if ($m2.Success) { $r.type = (Segs $m2.Groups[1].Value)[-1] }
        if ($hasSec) { $r.secreq = $true }
        $script:REQLIST += , $r
        return (Rec @{ kind = 'node'; node = $r; pkg = $pkg })
    }
    if ($null -ne $node -and $node.isreq) {
        $m = M $s "^subject\s+(?:$NAMEP\s*)?(?::|defined\s+by)\s*($REFP)"
        if ($m.Success) { $node.subject = Segs $m.Groups[1].Value; return $null }
    }
    $m = M $s "^part\s+def\s+($NAMEP)(.*)$"
    if ($m.Success) {
        $name = Unq $m.Groups[1].Value; $rest = $m.Groups[2].Value
        $sup = @()
        $m2 = M $rest "(?::>|\bspecializes\b)\s*($REFP(?:\s*,\s*$REFP)*)"
        if ($m2.Success) { foreach ($p in (SplitKeep $m2.Groups[1].Value '\s*,\s*')) { $sup += , (Segs $p) } }
        $d = Rec @{ isdef = $true; name = $name; pkg = $pkg; sup = $sup; feats = @(); conns = @(); file = $f; line = $line }
        $script:DEFLIST += , $d
        if ($null -eq $DEFBYNAME[$name]) { $DEFBYNAME[$name] = @() }
        $DEFBYNAME[$name] = @($DEFBYNAME[$name]) + , $d
        return (Rec @{ kind = 'node'; node = $d; pkg = $pkg })
    }
    if ($null -eq $node -or $node.isreq) { return $null }
    $owner = $node; while ($null -ne $owner -and -not $owner.isdef) { $owner = $owner.owner }
    $m = M $s '^(connection|interface|flow|connect)\b(?!\s+def\b)(.*)$'
    if ($null -ne $owner -and $m.Success) {
        $kw = $m.Groups[1].Value; $rest = $m.Groups[2].Value
        $cn = Rec @{ kind = $(if ($kw -ceq 'connect') { 'connection' } else { $kw }); file = $f; line = $line; owner = $owner; attr = (NewH) }
        if ($kw -cne 'connect') {
            $m2 = M $rest "^\s*($NAMEP)"
            if ($m2.Success -and $m2.Groups[1].Value -cnotmatch '^(?:connect|of|from)$') { $cn.name = Unq $m2.Groups[1].Value }
            $m2 = M $rest "^\s*(?:$NAMEP\s*)?:\s*($REFP)"
            if ($m2.Success) { $cn.type = (Segs $m2.Groups[1].Value) -join '::' }
        }
        $body = if ($kw -ceq 'connect') { "connect$rest" } else { $rest }
        $m2 = M $body "\bconnect\s+(?:$NAMEP\s*::>\s*)?($CHAIN)\s+to\s+(?:$NAMEP\s*::>\s*)?($CHAIN)"
        if ($m2.Success) { $cn.ends = @(, (Segs $m2.Groups[1].Value)) + , (Segs $m2.Groups[2].Value) }
        elseif ($kw -ceq 'flow') {
            $m3 = M $body "(?:\bof\s+(?:$NAMEP\s*:\s*)?($REFP)\s+)?\bfrom\s+($CHAIN)\s+to\s+($CHAIN)"
            if ($m3.Success) {
                $cn.item = if ($m3.Groups[1].Success -and $m3.Groups[1].Value) { (Segs $m3.Groups[1].Value) -join '::' } else { $null }
                $cn.ends = @(, (Segs $m3.Groups[2].Value)) + , (Segs $m3.Groups[3].Value); $cn.directed = $true
            }
        }
        $pre = @(); for ($o = $node; $null -ne $o -and -not $o.isdef; $o = $o.owner) { $pre = @($o.name) + $pre }
        if ($null -ne $cn.ends) {
            $cn.ends = @(foreach ($e in @($cn.ends)) { , (@($pre) + @($e)) })
            $owner.conns = @($owner.conns) + , $cn
        }
        return (Rec @{ kind = 'conn'; conn = $cn; pre = $pre; ends = @(); done = ($null -ne $cn.ends); pkg = $pkg })
    }
    $m = M $s '^(?:(in|out|inout)\s+)?(ref\s+)?(part|item|attribute|port)\b(?!\s+def\b)\s*(.*)$'
    if ($m.Success) {
        $u = Rec @{ kind = $m.Groups[3].Value; ref = $m.Groups[2].Success; dir = (Dflt (G $m 1) ''); file = $f; line = $line; feats = @(); owner = $node }
        $decl = Sub $m.Groups[4].Value '\s*(?::=|=|\bdefault\b).*$' ''
        $m2 = M $decl "^($NAMEP)"
        if ($m2.Success -and -not (T $decl '^(?:redefines|subsets|references)\b')) { $u.name = Unq $m2.Groups[1].Value }
        $m2 = M $decl "(?::>>|\bredefines\b)\s*($REFP)"
        if ($m2.Success) { $u.redef = (Segs $m2.Groups[1].Value)[-1]; if ($null -eq $u.name) { $u.name = $u.redef } }
        $m2 = M $decl "(?:^|[^:>]):\s*(~?)\s*($REFP)"
        if ($m2.Success) { $u.conj = $m2.Groups[1].Value; $u.type = Segs $m2.Groups[2].Value }
        $m2 = M $decl '\[\s*([^\]]+?)\s*\]'
        if ($m2.Success) { $u.mult = $m2.Groups[1].Value }
        if ($null -eq $u.name) { $u.name = '(unnamed)' }
        $node.feats = @($node.feats) + , $u
        return (Rec @{ kind = 'node'; node = $u; pkg = $pkg })
    }
    $null
}
$TOK = Rx '\G(?:(\n)|(//[^\n]*)|(/\*)|("(?:[^"\\]|\\.)*"|''(?:[^''\\]|\\.)*'')|([{};])|([^{};"''/\n]+|/))'
foreach ($f in $FILES) {
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
                $nd = $stack[$sn - 1].node
                if ($null -ne $nd -and $null -eq $nd.doc) { $nd.doc = $body }
                $head = ''
            } elseif (T $head '^\s*comment\b') { $head = '' }
        }
        elseif ($m.Groups[4].Success) { $q = $m.Groups[4].Value; if (-not (T $head '\S')) { $hline = $line }; $head += $q; $line += NlCount $q }
        elseif ($m.Groups[5].Success) {
            $c = $m.Groups[5].Value
            if ($c -eq '}') { if ($sn -gt 1) { $sn-- }; $head = ''; continue }
            $st = Classify $head $f $hline $stack $sn
            $head = ''
            if ($c -eq '{') { if ($null -eq $st) { $st = Rec @{ kind = 'other'; pkg = $stack[$sn - 1].pkg } }; $stack[$sn] = $st; $sn++ }
        }
        else { $x = $m.Groups[6].Value; if (-not (T $head '\S') -and (T $x '\S')) { $hline = $line }; $head += $x }
    }
}

# ------------------------------------------------------------------ resolve
function FindDef($sg, $from) {
    $sg = @($sg)
    $c = $DEFBYNAME[$sg[-1]]; if ($null -eq $c) { return $null }
    $c = @($c)
    if ($sg.Count -gt 1) {
        $q = @($c | Where-Object { $full = @($_.pkg) + , $_.name; $full.Count -ge $sg.Count -and ((@($full[($full.Count - $sg.Count)..($full.Count - 1)]) -join "`0") -ceq ($sg -join "`0")) })
        if ($q.Count) { $c = $q }
    }
    if ($c.Count -gt 1 -and $null -ne $from) { $p = @($from.pkg) -join '::'; $near = @($c | Where-Object { (@($_.pkg) -join '::') -ceq $p }); if ($near.Count) { $c = $near } }
    $c[0]
}
foreach ($d in $DEFLIST) {
    $sd = @(); foreach ($sg in @($d.sup)) { $x = FindDef $sg $d; if ($null -ne $x) { $sd += , $x } }
    $d.supdefs = $sd
    $queue = @($d.feats); $qi = 0
    while ($qi -lt $queue.Count) { $u = $queue[$qi]; $qi++; if ($null -ne $u.type -and $u.kind -ceq 'part') { $u.tdef = FindDef $u.type $d }; $queue += @($u.feats) }
}
$EFFMEMO = @{}
function Effective($d, $seen) {                     # -> , @(features, connections)
    $k = Id $d
    if ($EFFMEMO.ContainsKey($k)) { return , $EFFMEMO[$k] }
    if ($null -eq $seen) { $seen = @{} }
    if ($seen.ContainsKey($k)) { $emp = @(, @()) + , @(); return , $emp }
    $seen[$k] = 1
    $fl = @(); $pos = NewH; $cl = @()
    foreach ($s in @($d.supdefs)) {
        $e2 = Effective $s $seen
        foreach ($x in @($e2[0])) { if ($pos.ContainsKey($x.name)) { continue }; $pos[$x.name] = $fl.Count; $fl += , (CopyRec $x @{ inherited = $true }) }
        foreach ($x in @($e2[1])) { $cl += , (CopyRec $x @{ inherited = $true }) }
    }
    foreach ($x in @($d.feats)) {
        $k2 = if ($null -ne $x.redef -and $pos.ContainsKey($x.redef)) { $x.redef } else { $x.name }
        if ($pos.ContainsKey($k2)) { $fl[$pos[$k2]] = CopyRec $x @{ base = $fl[$pos[$k2]] } } else { $pos[$x.name] = $fl.Count; $fl += , $x }
    }
    $cl += @($d.conns)
    $r = @(, $fl) + , $cl
    $EFFMEMO[$k] = $r
    , $r
}
function EffFeats($d) { (Effective $d $null)[0] }
function EffConns($d) { (Effective $d $null)[1] }
function TdefOf($u) { if ($null -ne $u.tdef) { return $u.tdef }; if ($null -ne $u.base) { return (TdefOf $u.base) }; $null }
function ZoneOfUsage($u) {
    if ($null -ne $u.zone) { return $u.zone }
    if ($null -ne $u.base) { $z = ZoneOfUsage $u.base; if ($null -ne $z) { return $z } }
    $t = TdefOf $u; if ($null -ne $t) { return $t.zone }
    $null
}
function PortsOf($u) {
    $pl = @(); $pos = NewH
    $t = TdefOf $u
    if ($null -ne $t) { foreach ($x in @(EffFeats $t)) { if ($x.kind -ceq 'port') { $pos[$x.name] = $pl.Count; $pl += , $x } } }
    foreach ($x in @($u.feats)) { if ($x.kind -cne 'port') { continue }; if ($pos.ContainsKey($x.name)) { $pl[$pos[$x.name]] = $x } else { $pl += , $x } }
    , $pl
}
function Child($u, [string]$n) {
    $t = TdefOf $u; if ($null -eq $t) { return $null }
    foreach ($x in @($u.feats) + @(EffFeats $t)) { if ($x.name -ceq $n) { return $x } }
    $null
}
$CONTAINS = @{}
function Contains($sd, $dd) {
    $k = (Id $sd) + "`0" + (Id $dd)
    if ($CONTAINS.ContainsKey($k)) { return $CONTAINS[$k] }
    $CONTAINS[$k] = $false
    if ($sd -eq $dd) { $CONTAINS[$k] = $true; return $true }
    foreach ($u in @(EffFeats $sd)) {
        if ($u.kind -cne 'part' -or $u.ref) { continue }
        $t = TdefOf $u; if ($null -eq $t) { continue }
        if (Contains $t $dd) { $CONTAINS[$k] = $true; return $true }
    }
    $false
}
$SATISFIED = @{}
foreach ($s in $SATLIST) {
    $sg = @($s.ref)
    foreach ($r in $REQLIST) {
        $full = @($r.pkg) + @($r.path)
        if ($full.Count -ge $sg.Count -and ((@($full[($full.Count - $sg.Count)..($full.Count - 1)]) -join "`0") -ceq ($sg -join "`0"))) { $SATISFIED[(Id $r)] = $true }
    }
}
$SECREQS = @()
foreach ($r in $REQLIST) {
    $rd = if ($null -ne $r.type) { $REQDEFS[$r.type] } else { $null }
    $sec = $r.secreq -or ($null -ne $rd -and $rd.secreq)
    $subj = Dflt $r.subject $(if ($null -ne $rd) { $rd.subject } else { $null })
    for ($o = $r.up; $null -eq $subj -and $null -ne $o; $o = $o.up) {
        $subj = $o.subject
        if ($null -eq $subj -and $null -ne $o.type -and $null -ne $REQDEFS[$o.type]) { $subj = $REQDEFS[$o.type].subject }
    }
    $sat = $false; for ($o = $r; $null -ne $o; $o = $o.up) { if (-not $sat) { $sat = [bool]$SATISFIED[(Id $o)] } }
    if (-not $sec) { continue }
    $SECREQS += , @{ r = $r; subject = $(if ($null -ne $subj) { FindDef $subj $r } else { $null }); sat = $sat }
}
$ROOTDEFS = @()
if ($ROOTOPTS.Count) {
    foreach ($n in $ROOTOPTS) { $d = FindDef (SplitKeep $n '::') $null; if ($null -eq $d) { PErr "sysml-ibd-svg: no part def '$n'"; VExit 2 }; $ROOTDEFS += , $d }
} else { $ROOTDEFS = @($DEFLIST | Where-Object { @(EffConns $_).Count }) }

# ------------------------------------------------------------------ one diagram per root
$ZCOL = @(@('trusted', '#e8f5e9', '#2e7d32'), @('dmz', '#fff8e1', '#f9a825'), @('untrusted', '#ffebee', '#c62828'))
$ZFILL = NewH; $ZLINE = NewH; foreach ($z in $ZCOL) { $ZFILL[$z[0]] = $z[1]; $ZLINE[$z[0]] = $z[2] }
$ZEXTRA = @(@('#e3f2fd', '#1565c0'), @('#f3e5f5', '#6a1b9a'), @('#e0f2f1', '#00695c'))
$ZSEEN = NewH
function ZIdx([string]$z) { if (-not $ZSEEN.ContainsKey($z)) { $ZSEEN[$z] = $ZSEEN.Count + 1 }; ($ZSEEN[$z] - 1) % $ZEXTRA.Count }
function ZFill($z) { if ($null -eq $z) { return '#ffffff' }; if ($null -ne $ZFILL[$z]) { return $ZFILL[$z] }; $ZEXTRA[(ZIdx $z)][0] }
function ZLine($z) { if ($null -eq $z) { return '#455a64' }; if ($null -ne $ZLINE[$z]) { return $ZLINE[$z] }; $ZEXTRA[(ZIdx $z)][1] }
$script:NCROSS = 0; $script:NCONN = 0; $DG = @()
foreach ($d in $ROOTDEFS) {
    $feats = EffFeats $d; $conns = EffConns $d
    $parts = @(@($feats) | Where-Object { $_.kind -ceq 'part' })
    $fports = @(@($feats) | Where-Object { $_.kind -ceq 'port' })
    $fpbyname = NewH; foreach ($x in $fports) { $fpbyname[$x.name] = $x }
    $dzone = $d.zone
    $gparts = @(foreach ($u in $parts) { Rec @{ u = $u; ports = (NewH); zone = (Dflt (ZoneOfUsage $u) $dzone) } })
    $g = Rec @{ def = $d; parts = $gparts; fports = (NewH); conns = @() }
    $PBY = NewH; foreach ($x in $gparts) { $PBY[$x.u.name] = $x }
    foreach ($c in @($conns)) {
        $ends = @(); $okEnds = $true
        foreach ($e in @($c.ends)) {
            $s = @($e)
            if ($null -ne $PBY[$s[0]]) {
                $p = $PBY[$s[0]]
                $zone = $p.zone; $u = $p.u
                for ($i = 1; $i -lt $s.Count; $i++) { $x = Child $u $s[$i]; if ($null -eq $x) { break }; if ($x.kind -cne 'part') { break }; $z = ZoneOfUsage $x; if ($null -ne $z) { $zone = $z }; $u = $x }
                $label = if ($s.Count -gt 1) { ($s[1..($s.Count - 1)]) -join '.' } else { '' }
                if ($label -ne '' -and $null -eq $p.ports[$label]) { $p.ports[$label] = Rec @{ name = $label; part = $p } }
                $ends += , (Rec @{ part = $p; port = $(if ($label -ne '') { $p.ports[$label] } else { $null }); zone = $zone; text = ($s -join '.') })
            } elseif ($null -ne $fpbyname[$s[0]] -or $s.Count -eq 1) {
                $label = $s -join '.'
                if ($null -eq $g.fports[$label]) { $g.fports[$label] = Rec @{ name = $label; frame = $true } }
                $ends += , (Rec @{ frame = $true; port = $g.fports[$label]; zone = $dzone; text = $label })
            } else {
                Diag $c.file $c.line 'warning' "connection end '$($s -join '.')' is not a part or port of '$($d.name)'"
                $okEnds = $false; break
            }
        }
        if (-not $okEnds -or $ends.Count -ne 2) { continue }
        $cc = CopyRec $c @{ e = $ends }
        $script:NCONN++
        $z1 = $ends[0].zone; $z2 = $ends[1].zone
        $label = if ($null -ne $c.name) { $c.name } else { (@($ends | ForEach-Object { $_.text })) -join ' -> ' }
        $what = $(if ($c.kind -ceq 'interface') { 'interface' } elseif ($c.kind -ceq 'flow') { 'flow' } else { 'connection' }) + " '$label'"
        if ($null -ne $c.attr['fromZone'] -or $null -ne $c.attr['toZone']) {
            $d1 = Dflt $c.attr['fromZone'] ''; $d2 = Dflt $c.attr['toZone'] ''
            $g1 = Dflt $z1 '(none)'; $g2 = Dflt $z2 '(none)'
            if ("$d1->$d2" -cne "$g1->$g2" -and -not $c.inherited) { Diag $c.file $c.line 'warning' "$what declares fromZone/toZone $d1->$d2 but its ends sit in $g1->$g2" }
        }
        if ($null -ne $z1 -and $null -ne $z2 -and $z1 -cne $z2) {
            $cc.cross = "$z1->$z2"; $script:NCROSS++
            $cov = @($SECREQS | Where-Object { $_.sat -and $null -ne $_.subject -and (Contains $_.subject $c.owner) })
            $named = Dflt $c.attr['secReq'] ''
            $nm = @()
            if ($named -ne '') { $lastn = (SplitKeep $named '::|\.')[-1]; $nm = @($SECREQS | Where-Object { $_.r.name -ceq $lastn }) }
            foreach ($x in $nm) { if ($x.sat -and @($cov | Where-Object { $_ -eq $x }).Count -eq 0) { $cov += , $x } }
            if ($cov.Count) { $cc.covered = (@($cov | ForEach-Object { $_.r.name })) -join ', ' }
            else {
                $why = if ($named -ne '' -and -not $nm.Count) { " (its secReq '$named' is not a @SecurityRequirement)" }
                       elseif ($named -ne '') { " (its secReq '$named' is not satisfied)" }
                       elseif (@($SECREQS | Where-Object { $null -ne $_.subject -and (Contains $_.subject $c.owner) }).Count) { ' (a security requirement covers it but is not satisfied)' } else { '' }
                $pat = [regex]::Escape($what) + " in '" + [regex]::Escape($c.owner.name) + "'"
                if (-not ($cc.inherited -and @($script:DIAG | Where-Object { T $_[3] $pat }).Count)) {
                    Diag $c.file $c.line 'error' "$what in '$($c.owner.name)' crosses $z1->$z2 with no satisfied security requirement$why"
                }
            }
        }
        if (@($ends | Where-Object { (Dflt $_.zone '') -ceq 'untrusted' }).Count) {
            $pat = 'attack surface: ' + [regex]::Escape($what) + " in '" + [regex]::Escape($d.name) + "'"
            if (-not @($script:DIAG | Where-Object { T $_[3] $pat }).Count) { Diag $c.file $c.line 'note' "attack surface: $what in '$($d.name)' touches the untrusted zone" }
        }
        $g.conns = @($g.conns) + , $cc
    }
    foreach ($p in $gparts) { foreach ($x in (PortsOf $p.u)) { if ($null -eq $p.ports[$x.name]) { $p.ports[$x.name] = Rec @{ name = $x.name; part = $p; decl = $x } }; if ($null -eq $p.ports[$x.name].decl) { $p.ports[$x.name].decl = $x } } }
    foreach ($x in $fports) { if ($null -eq $g.fports[$x.name]) { $g.fports[$x.name] = Rec @{ name = $x.name; frame = $true } }; $g.fports[$x.name].decl = $x }
    $DG += , $g
}

# ------------------------------------------------------------------ layout
$CW = 7.2; $FS = 12; $SFS = 10.5; $PAD = 16; $TOPY = 96
$PSZ = 10; $PSTEP = 22; $GAPX = 120; $GAPY = 70; $FPAD = 60
function TW([string]$s) { $s.Length * $CW }
function STW([string]$s) { $s.Length * $CW * $SFS / $FS }
$script:YPOS = $TOPY
$script:SVGW = 720
function SumTo($p, $placed, $wts) { $s = 0; $row = $wts[(Id $p)]; if ($null -eq $row) { return 0 }; foreach ($x in @($placed)) { $s += Dflt $row[(Id $x)] 0 }; $s }
function Cost($cell, [int]$cols, $links) {
    $at = @{}; for ($i = 0; $i -lt $cell.Count; $i++) { if ($null -ne $cell[$i]) { $at[(Id $cell[$i])] = $i } }
    $s = 0
    foreach ($l in $links) {
        $pa = $l[0]; $pb = $l[1]
        if ($null -eq $pa -and $null -eq $pb) { continue }
        if ($null -eq $pa -or $null -eq $pb) { $one = if ($null -ne $pa) { $pa } else { $pb }; $i = $at[(Id $one)]; $c = $i % $cols; $s += $(if ($c -lt $cols - 1 - $c) { $c } else { $cols - 1 - $c }) + 1; continue }
        $i = $at[(Id $pa)]; $j = $at[(Id $pb)]
        $r1 = Trunc ($i / $cols); $c1 = $i % $cols; $r2 = Trunc ($j / $cols); $c2 = $j % $cols
        $s += (Abs ($c1 - $c2)) + 1.2 * (Abs ($r1 - $r2))
        if ($r1 -eq $r2) { for ($c = $(if ($c1 -lt $c2) { $c1 } else { $c2 }) + 1; $c -le $(if ($c1 -lt $c2) { $c2 } else { $c1 }) - 1; $c++) { if ($null -ne $cell[$r1 * $cols + $c]) { $s += 3 } } }
        if ($c1 -eq $c2) { for ($r = $(if ($r1 -lt $r2) { $r1 } else { $r2 }) + 1; $r -le $(if ($r1 -lt $r2) { $r2 } else { $r1 }) - 1; $r++) { if ($null -ne $cell[$r * $cols + $c1]) { $s += 3 } } }
    }
    $s
}
foreach ($g in $DG) {
    $PLIST = @($g.parts)
    $wts = @{}; $fw = @{}
    foreach ($c in @($g.conns)) {
        $pp = @(@($c.e) | Where-Object { $null -ne $_.part } | ForEach-Object { $_.part })
        if ($pp.Count -ne 2 -or $pp[0] -eq $pp[1]) { continue }
        foreach ($pair in @(@($pp[0], $pp[1]), @($pp[1], $pp[0]))) {
            $ka = Id $pair[0]; $kb = Id $pair[1]
            if ($null -eq $wts[$ka]) { $wts[$ka] = @{} }
            $wts[$ka][$kb] = 1 + (Dflt $wts[$ka][$kb] 0)
        }
    }
    foreach ($c in @($g.conns)) { $e = @($c.e); for ($i = 0; $i -lt 2; $i++) { if ($null -ne $e[$i].part -and $e[1 - $i].frame) { $k = Id $e[$i].part; $fw[$k] = 1 + (Dflt $fw[$k] 0) } } }
    $deg = { param($p) $k = Id $p; $s = Dflt $fw[$k] 0; if ($null -ne $wts[$k]) { foreach ($v in @($wts[$k].Values)) { $s += $v } }; $s }
    $order = @(); $in = @{}
    while ($order.Count -lt $PLIST.Count) {
        $cand = @($PLIST | Where-Object { -not $in.ContainsKey((Id $_)) })
        $sorted = SortBy $cand { param($x, $y)
            $c = NCmp (SumTo $y $order $wts) (SumTo $x $order $wts); if ($c) { return $c }
            $c = NCmp (Dflt $fw[(Id $y)] 0) (Dflt $fw[(Id $x)] 0); if ($c) { return $c }
            NCmp (& $deg $y) (& $deg $x) }
        $best = $sorted[0]; $order += , $best; $in[(Id $best)] = 1
    }
    $n = $order.Count
    $cols = if ($n -le 2) { $n } elseif ($n -le 4) { 2 } elseif ($n -le 9) { 3 } else { 4 }
    if (-not $cols) { $cols = 1 }
    $rows = Trunc (($n + $cols - 1) / $cols); if (-not $rows) { $rows = 1 }
    $cell = New-Object object[] ($rows * $cols)
    for ($i = 0; $i -lt $order.Count; $i++) { $r = Trunc ($i / $cols); $c = $i % $cols; if ($r % 2) { $c = $cols - 1 - $c }; $cell[$r * $cols + $c] = $order[$i] }
    $links = @(foreach ($c in @($g.conns)) { , @(@($c.e) | ForEach-Object { if ($_.frame) { $null } else { $_.part } }) })
    $best = Cost $cell $cols $links
    for ($round = 1; $round -le 20; $round++) {
        $improved = $false
        for ($i = 0; $i -lt $cell.Count; $i++) {
            for ($j = $i + 1; $j -lt $cell.Count; $j++) {
                if ($null -eq $cell[$i] -and $null -eq $cell[$j]) { continue }
                $tmp = $cell[$i]; $cell[$i] = $cell[$j]; $cell[$j] = $tmp
                $cst = Cost $cell $cols $links
                if ($cst -lt $best - 1e-9) { $best = $cst; $improved = $true } else { $tmp = $cell[$i]; $cell[$i] = $cell[$j]; $cell[$j] = $tmp }
            }
        }
        if (-not $improved) { break }
    }
    for ($i = 0; $i -lt $cell.Count; $i++) { if ($null -eq $cell[$i]) { continue }; $cell[$i].r = Trunc ($i / $cols); $cell[$i].c = $i % $cols }
    $acc = @{}
    foreach ($c in @($g.conns)) {
        $e = @($c.e)
        for ($i = 0; $i -lt 2; $i++) { $ea = $e[$i]; $eb = $e[1 - $i]; if (-not ($ea.frame -and -not $eb.frame)) { continue }; $k = Id $ea.port; $acc[$k] = (Dflt $acc[$k] 0) + ($eb.part.c - ($cols - 1) / 2) }
    }
    foreach ($fp in @($g.fports.Values)) { $fp.side = if ((Dflt $acc[(Id $fp)] (-1)) -gt 0) { 'R' } else { 'L' } }
    $vx = @{}; $vy = @{}
    foreach ($c in @($g.conns)) {
        $e = @($c.e)
        for ($i = 0; $i -lt 2; $i++) {
            $ea = $e[$i]; $eb = $e[1 - $i]
            if ($ea.frame) { continue }
            $k = if ($null -ne $ea.port) { 'p' + (Id $ea.port) } else { 'c' + (Id $c) + '#' + $i }
            if ($eb.frame) { $dc = $(if ($eb.port.side -ceq 'R') { $cols } else { -1 }) - $ea.part.c; $dr = 0 }
            else { $dc = $eb.part.c - $ea.part.c; $dr = $eb.part.r - $ea.part.r }
            if (-not $eb.frame -and $eb.part -eq $ea.part) { $dc = 0.1 }
            $vx[$k] = (Dflt $vx[$k] 0) + $dc; $vy[$k] = (Dflt $vy[$k] 0) + $dr
        }
    }
    foreach ($c in @($g.conns)) {
        $e = @($c.e)
        for ($i = 0; $i -lt 2; $i++) {
            $ea = $e[$i]; if ($ea.frame) { continue }
            $k = if ($null -ne $ea.port) { 'p' + (Id $ea.port) } else { 'c' + (Id $c) + '#' + $i }
            $dc = Dflt $vx[$k] 0; $dr = Dflt $vy[$k] 0
            $side = if ((Abs $dc) -ge (Abs $dr) -and $dc -ne 0) { $(if ($dc -gt 0) { 'R' } else { 'L' }) } elseif ($dr -gt 0) { 'B' } elseif ($dr -lt 0) { 'T' } else { 'R' }
            if ($null -ne $ea.port) { $ea.port.side = $side } else { $ea.side = $side }
        }
    }
    foreach ($p in $PLIST) {
        $pp = SortBy @($p.ports.Values) { param($x, $y) Cmp $x.name $y.name }
        foreach ($q in $pp) { if ($null -eq $q.side) { $q.side = 'L' } }
        $by = NewH; foreach ($q in $pp) { if ($null -eq $by[$q.side]) { $by[$q.side] = @() }; $by[$q.side] = @($by[$q.side]) + , $q }
        $p.byside = $by
        $u = $p.u
        $p.l1 = $(if ($u.inherited) { '^' } else { '' }) + $u.name + $(if ($null -ne $u.type) { ' : ' + (@($u.type) -join '::') } else { '' }) + $(if ($u.mult) { "[$($u.mult)]" } else { '' })
        $p.l0 = $(if ($u.ref) { "$($script:LAQUO)ref part$($script:RAQUO)" } else { "$($script:LAQUO)part$($script:RAQUO)" }) + $(if ($null -ne $p.zone) { " zone $($p.zone)" } else { '' })
        $lw = 0; foreach ($sd in @('L', 'R')) { foreach ($q in (Arr $by[$sd])) { $w = STW $q.name; if ($w -gt $lw) { $lw = $w } } }
        $tw = MaxNum (@((TW $p.l1), (STW $p.l0)) + @(@((Arr $by['T'])) + @((Arr $by['B'])) | ForEach-Object { (STW $_.name) * 1 }))
        $p.w = $tw + 24 + 2 * $(if ($lw) { $lw + 8 } else { 0 })
        $nT = (Arr $by['T']).Count; $nB = (Arr $by['B']).Count
        $wT = $(if ($nT -gt $nB) { $nT } else { $nB }) * 90 + 30; if ($p.w -lt $wT) { $p.w = $wT }
        $nside = (Arr $by['L']).Count; if ((Arr $by['R']).Count -gt $nside) { $nside = (Arr $by['R']).Count }
        $p.toff = if ($nT) { 14 } else { 0 }
        $p.h = 34 + $(if ($nside) { $nside * $PSTEP } else { 14 }) + $(if ($nT) { 14 } else { 0 }) + $(if ($nB) { 14 } else { 0 })
        if ($p.h -lt 52) { $p.h = 52 }
    }
    $colw = @{}; for ($i = 0; $i -lt $cols; $i++) { $colw[$i] = 0 }
    $rh = @{}; for ($i = 0; $i -lt $rows; $i++) { $rh[$i] = 0 }
    foreach ($p in $PLIST) { if ($p.w -gt $colw[$p.c]) { $colw[$p.c] = $p.w }; if ($p.h -gt $rh[$p.r]) { $rh[$p.r] = $p.h } }
    $fl = 0; foreach ($q in @($g.fports.Values)) { $w = STW $q.name; if ($w -gt $fl) { $fl = $w } }
    $fx = $PAD; $fy = $script:YPOS
    $ix = $fx + $FPAD + $fl; $iy = $fy + 54
    $colx = @{}; $colx[0] = $ix; for ($i = 1; $i -lt $cols; $i++) { $colx[$i] = $colx[$i - 1] + $colw[$i - 1] + $GAPX }
    $rowy = @{}; $rowy[0] = $iy; for ($i = 1; $i -lt $rows; $i++) { $rowy[$i] = $rowy[$i - 1] + $rh[$i - 1] + $GAPY }
    foreach ($p in $PLIST) { $p.x = $colx[$p.c] + ($colw[$p.c] - $p.w) / 2; $p.y = $rowy[$p.r] + ($rh[$p.r] - $p.h) / 2 }
    $innerw = $colx[$cols - 1] + $colw[$cols - 1] - $ix; $innerh = $rowy[$rows - 1] + $rh[$rows - 1] - $iy
    $fb = NewH
    foreach ($q in (SortBy @($g.fports.Values) { param($x, $y) Cmp $x.name $y.name })) { $sd = Dflt $q.side 'L'; if ($null -eq $fb[$sd]) { $fb[$sd] = @() }; $fb[$sd] = @($fb[$sd]) + , $q }
    $nf = (Arr $fb['L']).Count; if ((Arr $fb['R']).Count -gt $nf) { $nf = (Arr $fb['R']).Count }
    if ($innerh -lt $nf * 34) { $innerh = $nf * 34 }
    $g.frame = @{ x = $fx; y = $fy; w = ($ix - $fx) + $innerw + $FPAD + $fl; h = ($iy - $fy) + $innerh + 40 }
    $g.gx = @(for ($i = 0; $i -lt $cols; $i++) { $colx[$i] + $colw[$i] })
    $g.gy = @(for ($i = 0; $i -lt $rows; $i++) { $rowy[$i] + $rh[$i] })
    $g.colx = @(for ($i = 0; $i -lt $cols; $i++) { $colx[$i] }); $g.rowy = @(for ($i = 0; $i -lt $rows; $i++) { $rowy[$i] })
    foreach ($p in $PLIST) {
        $by = $p.byside
        foreach ($sd in @('L', 'R')) {
            $l = Arr $by[$sd]; $y0 = $p.y + 34 + $p.toff
            for ($i = 0; $i -lt $l.Count; $i++) { $l[$i].px = $(if ($sd -ceq 'L') { $p.x } else { $p.x + $p.w }); $l[$i].py = $y0 + $i * $PSTEP + $PSZ / 2 }
        }
        foreach ($sd in @('T', 'B')) {
            $l = Arr $by[$sd]; $step = $p.w / ($l.Count + 1)
            for ($i = 0; $i -lt $l.Count; $i++) { $l[$i].px = $p.x + $step * ($i + 1); $l[$i].py = $(if ($sd -ceq 'T') { $p.y } else { $p.y + $p.h }) }
        }
    }
    foreach ($sd in @('L', 'R')) {
        $l = Arr $fb[$sd]; $fr = $g.frame
        $step = ($fr.h - 60) / ($l.Count + 1)
        for ($i = 0; $i -lt $l.Count; $i++) { $l[$i].px = $(if ($sd -ceq 'L') { $fr.x } else { $fr.x + $fr.w }); $l[$i].py = $fr.y + 50 + $step * ($i + 1) }
    }
    $g.fb = $fb
    $script:YPOS = $fy + $g.frame.h + 48
    if ($g.frame.x + $g.frame.w + $PAD -gt $script:SVGW) { $script:SVGW = $g.frame.x + $g.frame.w + $PAD }
}
$SVGH = $script:YPOS + 10
$SVGW = $script:SVGW

# ------------------------------------------------------------------ routing
function Endpoint($e) {
    if ($null -ne $e.port) { return , @($e.port.px, $e.port.py, (Dflt $e.port.side 'L'), [bool]$e.frame) }
    $p = $e.part; $s = Dflt $e.side 'R'
    $x = if ($s -ceq 'L') { $p.x } elseif ($s -ceq 'R') { $p.x + $p.w } else { $p.x + $p.w / 2 }
    $y = if ($s -ceq 'T') { $p.y } elseif ($s -ceq 'B') { $p.y + $p.h } else { $p.y + $p.h / 2 }
    , @($x, $y, $s, $false)
}
function OutPt($pt, $len) {
    $x = $pt[0]; $y = $pt[1]; $s = $pt[2]; if ($pt[3]) { $len = -$len }
    if ($s -ceq 'L') { , @(($x - $len), $y) } elseif ($s -ceq 'R') { , @(($x + $len), $y) } elseif ($s -ceq 'T') { , @($x, ($y - $len)) } else { , @($x, ($y + $len)) }
}
function Hits($g, $pts) {
    for ($i = 0; $i -lt $pts.Count - 1; $i++) {
        $x1 = $pts[$i][0]; $y1 = $pts[$i][1]; $x2 = $pts[$i + 1][0]; $y2 = $pts[$i + 1][1]
        if ($x1 -gt $x2) { $t = $x1; $x1 = $x2; $x2 = $t }; if ($y1 -gt $y2) { $t = $y1; $y1 = $y2; $y2 = $t }
        foreach ($p in @($g.parts)) {
            $l = $p.x + 2; $tp = $p.y + 2; $r = $p.x + $p.w - 2; $b = $p.y + $p.h - 2
            if ($x2 -gt $l -and $x1 -lt $r -and $y2 -gt $tp -and $y1 -lt $b) { return $true }
        }
    }
    $false
}
function AllChannelsY($g) { $gy = @($g.gy); , (@($g.rowy[0] - 22) + @(for ($i = 0; $i -lt $gy.Count - 1; $i++) { $gy[$i] + $GAPY / 2 }) + @($gy[-1] + 22)) }
function Nearest($cands, $v) { (SortBy $cands { param($x, $y) NCmp (Abs ($x - $v)) (Abs ($y - $v)) })[0] }
function ChannelX($g, $x) { $gx = @($g.gx); Nearest (@($g.colx[0] - $GAPX / 2.5) + @(for ($i = 0; $i -lt $gx.Count - 1; $i++) { $gx[$i] + $GAPX / 2 }) + @($gx[-1] + $GAPX / 2.5)) $x }
function ChannelY($g, $y) { $gy = @($g.gy); Nearest (@($g.rowy[0] - 20) + @(for ($i = 0; $i -lt $gy.Count - 1; $i++) { $gy[$i] + $GAPY / 2 }) + @($gy[-1] + 20)) $y }
function IsHz([string]$s) { $s -ceq 'L' -or $s -ceq 'R' }
function Route($g, $pa, $pb) {
    $a1 = OutPt $pa 16; $b1 = OutPt $pb 16
    if ((IsHz $pa[2]) -and (IsHz $pb[2])) { $mx = ChannelX $g (($a1[0] + $b1[0]) / 2); $mid = @(, @($mx, $a1[1])) + , @($mx, $b1[1]) }
    elseif (-not (IsHz $pa[2]) -and -not (IsHz $pb[2])) { $my = ChannelY $g (($a1[1] + $b1[1]) / 2); $mid = @(, @($a1[0], $my)) + , @($b1[0], $my) }
    elseif (IsHz $pa[2]) { $mid = @(, @($b1[0], $a1[1])) }
    else { $mid = @(, @($a1[0], $b1[1])) }
    $pts = @(, @($pa[0], $pa[1])) + @(, $a1) + $mid + @(, $b1) + @(, @($pb[0], $pb[1]))
    if (Hits $g (@(, $a1) + $mid + @(, $b1))) {
        $best = @()
        $xs = @((ChannelX $g $a1[0]), (ChannelX $g $b1[0]))
        $cy = ($a1[1] + $b1[1]) / 2
        foreach ($hy in (SortBy (AllChannelsY $g) { param($x, $y) NCmp (Abs ($x - $cy)) (Abs ($y - $cy)) })) {
            $mm = @(, @($xs[0], $a1[1])) + , @($xs[0], $hy) + , @($xs[1], $hy) + , @($xs[1], $b1[1])
            if (-not (IsHz $pa[2]) -and -not (IsHz $pb[2])) { $mm = @(, @($a1[0], $hy)) + , @($b1[0], $hy) }
            if (-not (Hits $g (@(, $a1) + $mm + @(, $b1)))) { $best = $mm; break }
        }
        if ($best.Count) { $pts = @(, @($pa[0], $pa[1])) + @(, $a1) + $best + @(, $b1) + @(, @($pb[0], $pb[1])) }
    }
    $d = 'M' + (F $pts[0][0] 1) + ' ' + (F $pts[0][1] 1)
    for ($i = 1; $i -lt $pts.Count; $i++) { $d += ' L' + (F $pts[$i][0] 1) + ' ' + (F $pts[$i][1] 1) }
    $li = 1; $ll = -1
    for ($i = 1; $i -le $pts.Count - 3; $i++) { $l = (Abs ($pts[$i][0] - $pts[$i + 1][0])) + (Abs ($pts[$i][1] - $pts[$i + 1][1])); if ($l -gt $ll) { $li = $i; $ll = $l } }
    , @($d, (($pts[$li][0] + $pts[$li + 1][0]) / 2), (($pts[$li][1] + $pts[$li + 1][1]) / 2), ($pts[$li][1] -eq $pts[$li + 1][1]), $ll)
}

# ------------------------------------------------------------------ draw
$CLR = NewH; foreach ($kv in @(@('ink', '#212121'), @('dim', '#616161'), @('wire', '#546e7a'), @('frame', '#283593'), @('cov', '#ef6c00'), @('bad', '#c62828'))) { $CLR[$kv[0]] = $kv[1] }
$SVGL = @{}; $script:ON = 0
function O([string]$s) { $SVGL[$script:ON] = $s; $script:ON++ }
O '<?xml version="1.0" encoding="UTF-8"?>'
O ('<svg xmlns="http://www.w3.org/2000/svg" width="' + (N $SVGW) + '" height="' + (N $SVGH) + '" viewBox="0 0 ' + (N $SVGW) + ' ' + (N $SVGH) + '" font-family="DejaVu Sans Mono, Consolas, Menlo, monospace" font-size="' + $FS + '">')
O ('<!-- generated by sysml-ibd-svg.pl from ' + (GSub (Esc ($ARGV0 -join ' ')) '-(?=-)' '- ') + ' -->')
O ('<defs><marker id="fa" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="8" markerHeight="8" orient="auto"><path d="M0 0 L10 5 L0 10 z" fill="' + $CLR.wire + '"/></marker></defs>')
O '<rect width="100%" height="100%" fill="#ffffff"/>'
$SUMLINE = '{0} file(s): {1} error(s), {2} warning(s), {3} diagram(s), {4} connection(s), {5} boundary crossing(s), {6} on the attack surface' -f $FILES.Count, $script:NERR, $script:NWARN, $DG.Count, $script:NCONN, $script:NCROSS, $script:NNOTE
O ('<text x="' + $PAD + '" y="26" font-size="16" font-weight="bold" fill="' + $CLR.ink + '">' + (Esc (Dflt $OPT['title'] 'Interconnection')) + '</text>')
O ('<text x="' + $PAD + '" y="46" fill="' + $CLR.dim + '">' + (Esc $SUMLINE) + '</text>')
$lx = $PAD; $ly = 60
O ('<g font-size="11" fill="' + $CLR.dim + '">')
$zall = NewH; foreach ($g in $DG) { foreach ($p in @($g.parts)) { if ($null -ne $p.zone) { $zall[$p.zone] = 1 } } }
$zones = @($ZCOL | ForEach-Object { $_[0] }) + (SortStr @(@($zall.Keys) | Where-Object { $null -eq $ZFILL[$_] }))
foreach ($z in $zones) {
    O ('<rect x="' + (N $lx) + '" y="' + $ly + '" width="22" height="13" rx="3" fill="' + (ZFill $z) + '" stroke="' + (ZLine $z) + '"/><text x="' + (N ($lx + 28)) + '" y="' + ($ly + 11) + '">' + (Esc $z) + '</text>')
    $lx += 44 + (STW $z)
}
O ('<rect x="' + (N $lx) + '" y="' + $ly + '" width="22" height="13" rx="3" fill="#ffffff" stroke="#455a64"/><text x="' + (N ($lx + 28)) + '" y="' + ($ly + 11) + '">no zone</text>'); $lx += 100
O ('<path d="M' + (N $lx) + ' ' + ($ly + 7) + ' h28" stroke="' + $CLR.wire + '" stroke-width="1.6"/><text x="' + (N ($lx + 34)) + '" y="' + ($ly + 11) + '">connection</text>'); $lx += 116
O ('<path d="M' + (N $lx) + ' ' + ($ly + 7) + ' h28" stroke="' + $CLR.cov + '" stroke-width="3"/><text x="' + (N ($lx + 34)) + '" y="' + ($ly + 11) + '">crossing, covered</text>'); $lx += 172
O ('<path d="M' + (N $lx) + ' ' + ($ly + 7) + ' h28" stroke="' + $CLR.bad + '" stroke-width="3" stroke-dasharray="6 3"/><text x="' + (N ($lx + 34)) + '" y="' + ($ly + 11) + '">crossing, NOT covered</text>'); $lx += 200
O ('<path d="M' + (N $lx) + ' ' + ($ly + 7) + ' h28" stroke="' + $CLR.wire + '" stroke-width="1.6" marker-end="url(#fa)"/><text x="' + (N ($lx + 34)) + '" y="' + ($ly + 11) + '">flow</text>')
O '</g>'
foreach ($g in $DG) {
    $d = $g.def; $fr = $g.frame
    $tip = @("part def $($d.name)"); if ($null -ne $d.doc) { $tip += , $d.doc }; if ($null -ne $d.zone) { $tip += , "zone $($d.zone)" }; $tip += , "$($d.file):$($d.line)"
    O ('<g><title>' + (Esc ($tip -join "`n")) + '</title>')
    O ('<rect x="' + (F $fr.x 1) + '" y="' + (F $fr.y 1) + '" width="' + (F $fr.w 1) + '" height="' + (F $fr.h 1) + '" fill="' + (ZFill $d.zone) + '" fill-opacity="0.35" stroke="' + $CLR.frame + '" stroke-width="1.8"/>')
    O ('<text x="' + (F ($fr.x + 10) 1) + '" y="' + (F ($fr.y + 16) 1) + '" font-size="' + (N $SFS) + '" fill="' + $CLR.dim + '">' + (Esc ("$($script:LAQUO)part def$($script:RAQUO)" + $(if ($null -ne $d.zone) { " zone $($d.zone)" } else { '' }))) + '</text>')
    O ('<text x="' + (F ($fr.x + 10) 1) + '" y="' + (F ($fr.y + 33) 1) + '" font-weight="bold" fill="' + $CLR.ink + '">' + (Esc ((@($d.pkg) + , $d.name) -join '::')) + '</text>')
    O '</g>'
    foreach ($p in @($g.parts)) {
        $u = $p.u
        $dash = if ($u.ref) { ' stroke-dasharray="5 3"' } else { '' }
        $t = @($p.l0, $p.l1); $td = TdefOf $u; if ($null -ne $td -and $td.doc) { $t += , $td.doc }; $t += , "$($u.file):$($u.line)"
        O ('<g><title>' + (Esc ($t -join "`n")) + '</title>')
        O ('<rect x="' + (F $p.x 1) + '" y="' + (F $p.y 1) + '" width="' + (F $p.w 1) + '" height="' + (F $p.h 1) + '" rx="8" fill="' + (ZFill $p.zone) + '" stroke="' + (ZLine $p.zone) + '" stroke-width="1.4"' + $dash + '/>')
        O ('<text x="' + (F ($p.x + $p.w / 2) 1) + '" y="' + (F ($p.y + 14 + $p.toff) 1) + '" font-size="' + (N $SFS) + '" fill="' + $CLR.dim + '" text-anchor="middle">' + (Esc $p.l0) + '</text>')
        O ('<text x="' + (F ($p.x + $p.w / 2) 1) + '" y="' + (F ($p.y + 28 + $p.toff) 1) + '" fill="' + $(if ($u.inherited) { '#7b1fa2' } else { $CLR.ink }) + '" text-anchor="middle">' + (Esc $p.l1) + '</text>')
        O '</g>'
    }
}
foreach ($g in $DG) {
    foreach ($c in @($g.conns)) {
        $e = @($c.e)
        $col = $CLR.wire; $w = 1.6; $dash = ''
        if ($c.cross -and $c.covered) { $col = $CLR.cov; $w = 3 }
        if ($c.cross -and -not $c.covered) { $col = $CLR.bad; $w = 3; $dash = ' stroke-dasharray="6 3"' }
        $path = Route $g (Endpoint $e[0]) (Endpoint $e[1])
        $label = if ($null -ne $c.name) { $c.name } elseif ($c.kind -ceq 'flow' -and $c["item"]) { $c["item"] } else { '' }
        if ($path[3] -and $path[4] -lt (STW $label) + 12) { $label = '' }
        $t = @($(if ($c.inherited) { '^' } else { '' }) + "$($c.kind) " + (Dflt $c.name '') + $(if ($c.type) { " : $($c.type)" } else { '' }))
        $t += , ((@($e | ForEach-Object { $_.text })) -join ' -> ')
        if ($c["item"]) { $t += , "item $($c["item"])" }
        if ($c.cross) { $t += , ("zone crossing $($c.cross): " + $(if ($c.covered) { "covered by $($c.covered)" } else { 'NOT covered by a satisfied security requirement' })) }
        $t += , "$($c.file):$($c.line)"
        $mk = if ($c.directed) { ' marker-end="url(#fa)"' } else { '' }
        $lab = ''
        if ($label -ne '') {
            if ($path[3]) { $tx = $path[1]; $ty = $path[2] - 5 } else { $tx = $path[1] + 6; $ty = $path[2] + 4 }
            $lab = '<text x="' + (F $tx 1) + '" y="' + (F $ty 1) + '" font-size="' + (N $SFS) + '" fill="' + $(if ($c.cross) { $col } else { $CLR.dim }) + '" text-anchor="' + $(if ($path[3]) { 'middle' } else { 'start' }) + '" font-style="italic">' + (Esc $label) + '</text>'
        }
        O ('<g><title>' + (Esc ($t -join "`n")) + '</title><path d="' + $path[0] + '" fill="none" stroke="' + $col + '" stroke-width="' + (N $w) + '"' + $dash + $mk + '/>' +
           '<path d="' + $path[0] + '" fill="none" stroke="transparent" stroke-width="10"/>' + $lab + '</g>')
    }
}
function PortSvg($q, [string]$sd, [string]$line) {
    $x = $q.px - $PSZ / 2; $y = $q.py - $PSZ / 2
    $decl = $q.decl
    $conj = ($null -ne $decl -and $decl.conj)
    $label = $(if ($conj) { '~' } else { '' }) + $q.name
    $dir = if ($null -ne $decl -and $null -ne $decl.type) { ' : ' + $(if ($conj) { '~' } else { '' }) + (@($decl.type) -join '::') } else { '' }
    if ($q.frame) { if ($sd -ceq 'L') { $tx = $q.px + 9; $ty = $q.py - 7; $anchor = 'start' } else { $tx = $q.px - 9; $ty = $q.py - 7; $anchor = 'end' } }
    elseif ($sd -ceq 'L') { $tx = $q.px + 9; $ty = $q.py + 4; $anchor = 'start' }
    elseif ($sd -ceq 'R') { $tx = $q.px - 9; $ty = $q.py + 4; $anchor = 'end' }
    elseif ($sd -ceq 'T') { $tx = $q.px; $ty = $q.py + 18; $anchor = 'middle' }
    else { $tx = $q.px; $ty = $q.py - 9; $anchor = 'middle' }
    '<g><title>' + (Esc ("port $($q.name)$dir" + $(if ($null -ne $decl) { "`n$($decl.file):$($decl.line)" } else { "`n(path to a nested feature)" }))) + '</title>' +
      '<rect x="' + (F $x 1) + '" y="' + (F $y 1) + '" width="' + $PSZ + '" height="' + $PSZ + '" fill="' + $(if ($conj) { $line } else { '#ffffff' }) + '" stroke="' + $line + '" stroke-width="1.4"/>' +
      '<text x="' + (F $tx 1) + '" y="' + (F $ty 1) + '" font-size="' + (N $SFS) + '" fill="' + $CLR.dim + '" text-anchor="' + $anchor + '">' + (Esc $label) + '</text></g>'
}
foreach ($g in $DG) {
    foreach ($p in @($g.parts)) { foreach ($sd in (SortStr @($p.byside.Keys))) { foreach ($q in (Arr $p.byside[$sd])) { O (PortSvg $q $sd (ZLine $p.zone)) } } }
    foreach ($sd in (SortStr @($g.fb.Keys))) { foreach ($q in (Arr $g.fb[$sd])) { O (PortSvg $q $sd $CLR.frame) } }
}
O '</svg>'
$svg = (@(for ($i = 0; $i -lt $script:ON; $i++) { $SVGL[$i] + "`n" })) -join ''
if (-not (VWrite $OPT['o'] $svg)) { PErr "$($OPT['o']): cannot write"; VExit 2 }
foreach ($d in (SortBy $script:DIAG { param($x, $y) $c = Cmp $x[0] $y[0]; if ($c) { return $c }; $c = NCmp $x[1] $y[1]; if ($c) { return $c }; NCmp $x[2] $y[2] })) { PL $d[3] }
PL "$SUMLINE -> $($OPT['o'])"
VExit $(if ($script:NERR) { 1 } else { 0 })
