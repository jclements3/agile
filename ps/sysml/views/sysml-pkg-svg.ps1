<#
sysml-pkg-svg.ps1 : package dependencies and SecMeta markings of a SysML v2 model, as one SVG, with the marking
checks (SEC-4) printed in GNU format.
PowerShell port of tools/sysml/views/sysml-pkg-svg.pl (Constrained Language Mode safe, pure ASCII).

  sysml-pkg-svg.ps1 [-o packages.svg] [--title T] [--nested] [--hide P,Q] [--levels U,CUI,ITAR] [--no-markings] DIR|FILE...

Same options, SVG bytes, diagnostics and exit status as the Perl (0 no errors, 1 errors, 2 usage error).
#>
. (Join-Path $PSScriptRoot 'views-lib.ps1')
VBufferStderr
$go = GetOpts $args @('o=s', 'title=s', 'nested', 'levels=s', 'hide=s', 'no-markings')
if (-not $go.ok -or -not @($go.rest).Count) { PErr 'usage: perl sysml-pkg-svg.pl [-o packages.svg] [--title T] [--nested] [--hide P,Q] [--levels U,CUI,ITAR] [--no-markings] DIR|FILE...'; VExit 2 }
$OPT = $go.opts; $ARGV0 = @($go.rest)
if ($null -eq $OPT['o']) { $OPT['o'] = 'packages.svg' }
$HIDE = NewH; foreach ($x in (SplitKeep (Dflt $OPT['hide'] '') ',')) { $HIDE[$x] = 1 }
$FILES = @()
foreach ($a in $ARGV0) {
    if (IsDir $a) { $FILES += @(FindSysml $a) }
    elseif (IsFile $a) { $FILES += , $a }
    else { PErr "sysml-pkg-svg: ${a}: no such file or directory"; VExit 2 }
}
$FILES = SortStr $FILES
$NAMEP = $script:NAMERX
$REFQ = "$NAMEP(?:\s*::\s*$NAMEP)*"
$KWSET = NewH
foreach ($k in (SplitKeep ('about abstract accept action actor after alias all allocate allocation analysis and as assert assign assume at attribute bind binding by calc case comment concern connect connection constant ' +
    'constraint crosses decide def default defined dependency derived do doc else end entry enum event exhibit exit expose false filter first flow for fork frame from hastype if implies import in include individual ' +
    'inout interface istype item join language library locale loop merge message meta metadata nonunique not null objective occurrence of or ordered out package parallel part perform port private protected public ' +
    'redefines ref references render rendering rep require requirement return satisfy send snapshot specializes stakeholder standard state subject subsets succession terminate then timeslice to transition true until ' +
    'use variant variation verification verify via view viewpoint when while xor') ' ')) { $KWSET[$k] = 1 }
$DECLP = '(?:part|item|port|attribute|requirement|action|calc|constraint|enum|interface|connection|verification|analysis|metadata|view|viewpoint|concern|state|occurrence|flow|allocation|rendering|case|use\s+case|individual|connector|binding|succession)'

# ------------------------------------------------------------------ parse
$PKGS = NewH; $PORDER = @(); $ELEMS = NewH; $LEVELSFOUND = @()
$TOK = Rx '\G(?:(\n)|//([^\n]*)|(/\*)|("(?:[^"\\]|\\.)*")|(''(?:[^''\\]|\\.)*'')|([{};])|([^{};"''/\n]+|/))'
function CurPkg($stack, [int]$sn) { for ($i = $sn - 1; $i -ge 0; $i--) { if ($null -ne $stack[$i].p) { return $stack[$i].p } }; $null }
function CurElem($stack, [int]$sn) { for ($i = $sn - 1; $i -ge 0; $i--) { if ($null -ne $stack[$i].e) { return $stack[$i].e }; if ($null -ne $stack[$i].p) { return $null } }; $null }
function AddText($stack, [int]$sn, [string]$s, [int]$ln) {
    $p = CurPkg $stack $sn; if ($null -eq $p) { return }
    foreach ($m in (MS $s '\b([A-Za-z_]\w{3,})\b')) { $p.words = @($p.words) + , @($m.Groups[1].Value, $ln) }
}
foreach ($f in $FILES) {
    $t = VRead $f
    $stack = @{}; $stack[0] = @{ kind = 'file' }; $sn = 1
    $head = ''; $hline = 1; $line = 1; $pos = 0; $len = $t.Length
    while ($pos -lt $len) {
        $m = $TOK.Match($t, $pos)
        if (-not $m.Success) { $pos++; continue }
        $pos = $m.Index + $m.Length
        if ($m.Groups[1].Success) { $line++; $head += ' ' }
        elseif ($m.Groups[2].Success) { AddText $stack $sn $m.Groups[2].Value $line }
        elseif ($m.Groups[3].Success) {
            $from = $pos; $end = $t.IndexOf('*/', $from); if ($end -lt 0) { $end = $len }
            $body = $t.Substring($from, $end - $from); $pos = $end + 2
            AddText $stack $sn $body $line
            $line += NlCount $body
            if (T $head '^\s*(?:doc|comment)\b') { $head = '' }
        }
        elseif ($m.Groups[4].Success) { $q = $m.Groups[4].Value; AddText $stack $sn $q $line; if (-not (T $head '\S')) { $hline = $line }; $head += '""'; $line += NlCount $q }
        elseif ($m.Groups[5].Success) { $q = $m.Groups[5].Value; if (-not (T $head '\S')) { $hline = $line }; $head += $q }
        elseif ($m.Groups[6].Success) {
            $c = $m.Groups[6].Value
            if ($c -eq '}') { if ($sn -gt 1) { $sn-- }; $head = ''; continue }
            $s = Squash $head; $head = ''
            $scope = @{ kind = 'other' }
            $p = CurPkg $stack $sn
            $mm = M $s "^(?:(?:standard\s+)?(library)\s+)?package\s+($NAMEP)"
            if ($mm.Success) {
                $lib = $mm.Groups[1].Success; $n = Unq $mm.Groups[2].Value
                $q = if ($null -ne $p) { "$($p.qname)::$n" } else { $n }
                if ($null -eq $PKGS[$q]) { $PKGS[$q] = Rec @{ name = $n; qname = $q; parent = $p; file = $f; line = $hline; lib = $lib; members = (NewH); imports = @(); refs = @(); words = @(); ndef = 0; nreq = 0 } }
                $np = $PKGS[$q]
                if (-not $np.seen) { $script:PORDER += , $np }
                $np.seen = 1 + (Dflt $np.seen 0)
                if ($null -ne $p -and $null -eq $p.members[$n]) { $p.members[$n] = Rec @{ name = $n; qname = $q; pkg = $p; ispkg = $true } }
                $scope = @{ kind = 'package'; p = $np }
            }
            elseif ((T $s '^@\s*(?:SecMeta::)?Marking\b') -or (T $s '^metadata\s+(?:SecMeta::)?Marking\b')) {
                $target = CurElem $stack $sn; if ($null -eq $target) { $target = $p }
                $scope = @{ kind = 'marking'; target = $target; file = $f; line = $hline }
                $m2 = M $s 'level\s*=\s*(?:\w+::)*(\w+)'
                if ($m2.Success -and $null -ne $target) { $target.marking = $m2.Groups[1].Value; $target.mline = $hline }
            }
            elseif ($stack[$sn - 1].kind -ceq 'marking' -and (T $s '^(?::>>\s*)?level\s*=\s*(?:\w+::)*(\w+)')) {
                $m2 = M $s '^(?::>>\s*)?level\s*=\s*(?:\w+::)*(\w+)'
                $tg = $stack[$sn - 1].target
                if ($null -ne $tg) { $tg.marking = $m2.Groups[1].Value; $tg.mline = $stack[$sn - 1].line }
            }
            elseif (T $s '^enum\s+def\s+Level\b') { $scope = @{ kind = 'levels' } }
            elseif ($stack[$sn - 1].kind -ceq 'levels' -and (T $s "^(?:enum\s+)?($NAMEP)$")) {
                $lv = Unq (M $s "^(?:enum\s+)?($NAMEP)$").Groups[1].Value
                if (@($script:LEVELSFOUND | Where-Object { $_ -ceq $lv }).Count -eq 0) { $script:LEVELSFOUND += , $lv }
            }
            elseif ($null -ne $p -and (T $s "^(?:(public|private|protected)\s+)?import\s+(?:all\s+)?($REFQ)\s*(::\s*\*\*|::\s*\*)?")) {
                $m2 = M $s "^(?:(public|private|protected)\s+)?import\s+(?:all\s+)?($REFQ)\s*(::\s*\*\*|::\s*\*)?"
                $star = Dflt (G $m2 3) ''
                $p.imports = @($p.imports) + , @{ segs = (Segs $m2.Groups[2].Value); star = $(if ($star.Contains('**')) { '**' } elseif ($star) { '*' } else { '' }); vis = (Dflt (G $m2 1) 'private'); file = $f; line = $hline; text = $s }
            }
            elseif ($null -ne $p -and $s -ne '') {
                $s2 = Sub $s '^(?:(?:public|private|protected|abstract|variation|individual|derived|readonly|in|out|inout|ref|end)\s+)*' ''
                $s2 = Sub $s2 "^(?:#\s*$NAMEP\s*)+" ''
                $m2 = M $s2 "^($DECLP)\s+(def\s+)?(?:<'[^']*'>\s*)?($NAMEP)"
                if ($m2.Success) {
                    $kw = $m2.Groups[1].Value; $isdef = $m2.Groups[2].Success; $n = Unq $m2.Groups[3].Value
                    $owner = CurElem $stack $sn
                    $q = $(if ($null -ne $owner) { $owner.qname } else { $p.qname }) + "::$n"
                    if ($null -eq $ELEMS[$q]) { $ELEMS[$q] = Rec @{ name = $n; qname = $q; pkg = $p; owner = $owner; file = $f; line = $hline } }
                    $e = $ELEMS[$q]
                    if ($null -eq $owner -and $null -eq $p.members[$n]) { $p.members[$n] = $e }
                    if ($isdef) { $p.ndef++ }
                    if ($kw -ceq 'requirement' -and -not $isdef) { $p.nreq++ }
                    if ($c -eq '{') { $scope = @{ kind = 'elem'; e = $e } }
                }
                foreach ($rm in (MS $s "($REFQ)")) {
                    $sg = Segs $rm.Groups[1].Value
                    if ($sg.Count -gt 1) { $p.refs = @($p.refs) + , @{ segs = $sg; file = $f; line = $hline; qual = $true } }
                    elseif (-not $KWSET.ContainsKey($sg[0])) { $p.refs = @($p.refs) + , @{ segs = $sg; file = $f; line = $hline; qual = $false } }
                }
                AddText $stack $sn $s $hline
            }
            if ($c -eq '{') { $stack[$sn] = $scope; $sn++ }
        }
        else { $x = $m.Groups[7].Value; if (-not (T $head '\S') -and (T $x '\S')) { $hline = $line }; $head += $x }
    }
}

# ------------------------------------------------------------------ levels, markings, resolution
$LEVELS = if ($null -ne $OPT['levels'] -and $OPT['levels'] -ne '') { SplitKeep $OPT['levels'] ',' } elseif ($LEVELSFOUND.Count) { , $LEVELSFOUND } else { , @('U', 'CUI', 'ITAR') }
$RANK = NewH; for ($i = 0; $i -lt $LEVELS.Count; $i++) { $RANK[$LEVELS[$i]] = $i }
$script:NERR = 0; $script:NWARN = 0; $script:DIAG = @()
function Diag([string]$f, $l, [string]$sev, [string]$msg) {
    $script:DIAG += , @($f, [long]$l, $script:DIAG.Count, "${f}:$(N $l): ${sev}: $msg")
    if ($sev -eq 'error') { $script:NERR++ } else { $script:NWARN++ }
}
$ESORTED = @(foreach ($k in (SortStr @($ELEMS.Keys))) { $ELEMS[$k] })
foreach ($x in @($PORDER) + $ESORTED) {
    if ($null -ne $x.marking -and -not $RANK.ContainsKey($x.marking)) {
        Diag $x.file (Dflt $x.mline $x.line) 'error' "unknown marking level '$($x.marking)' on '$($x.qname)' (levels: $($LEVELS -join ' '))"
        $x.Remove('marking')
    }
}
function RankOf($x) {
    $r = -1
    for ($o = $x; $null -ne $o; ) {
        if ($null -ne $o.marking -and $RANK.ContainsKey($o.marking) -and $RANK[$o.marking] -gt $r) { $r = $RANK[$o.marking] }
        if ($null -ne $o.owner) { $o = $o.owner } elseif ($null -ne $o.parent) { $o = $o.parent } elseif ($null -ne $o.pkg -and -not ($o.pkg -eq $o)) { $o = $o.pkg } else { $o = $null }
    }
    $r
}
function Lvl($r) { if ($r -lt 0) { 'unmarked' } else { $LEVELS[$r] } }
function RootOf($p) { while ($null -ne $p.parent) { $p = $p.parent }; $p }
function NodeOf($p) { if ($OPT['nested']) { $p } else { RootOf $p } }
function ResolveQ($sg) {
    $sg = @($sg)
    for ($i = $sg.Count - 1; $i -ge 0; $i--) {
        $q = ($sg[0..$i]) -join '::'
        if ($null -eq $PKGS[$q]) { continue }
        if ($i -eq $sg.Count - 1) { return $PKGS[$q] }
        $e = $ELEMS[($sg -join '::')]; if ($null -eq $e) { $e = $PKGS[$q].members[$sg[$i + 1]] }
        if ($null -ne $e) { return $e }
        return $PKGS[$q]
    }
    $null
}
$NOMARK = [bool]$OPT['no-markings']
foreach ($p in $PORDER) { $p.rank = RankOf $p }
if (-not $NOMARK) { foreach ($p in @($PORDER | Where-Object { $null -eq $_.parent })) { if ($null -eq $p.marking) { Diag $p.file $p.line 'error' "root package '$($p.qname)' has no @Marking" } } }

$DEP = NewH
function Dep($from, $to, [string]$kind, $x) {
    $na = NodeOf $from; $nb = NodeOf $to
    if ($na -eq $nb) { return $null }
    $k = $na.qname + "`0" + $nb.qname
    if ($null -eq $DEP[$k]) { $DEP[$k] = Rec @{ from = $na; to = $nb; imports = @(); refs = 0; bad = @(); at = @($x.file, $x.line) } }
    $d = $DEP[$k]
    if ($kind -eq 'import') { $d.imports = @($d.imports) + , "$($x.file):$($x.line): $($x.text)" } else { $d.refs++ }
    $d
}
$REPORTED = NewH
function CheckWriteDown($p, $target, $x, [string]$how) {
    $pr = $p.rank; $tr = RankOf $target
    if ($pr -lt 0) { return $false }
    if (-not ($tr -gt $pr)) { return $false }
    $what = if ($target.ispkg -or $null -ne $PKGS[$target.qname]) { 'package' } else { 'element' }
    $msg = "$(Lvl $pr) package '$($p.qname)' $how $(Lvl $tr) $what '$($target.qname)'"
    $rk = "$($x.file):$($x.line):$msg"
    if ($REPORTED.ContainsKey($rk)) { return $false }
    $REPORTED[$rk] = 1
    Diag $x.file $x.line 'error' $msg
    $true
}
$VISIBLE = NewH
foreach ($p in $PORDER) {
    $vis = NewH
    foreach ($i in @($p.imports)) {
        $t = ResolveQ $i.segs
        if ($null -eq $t) { continue }
        $tp = if ($null -ne $PKGS[$t.qname]) { $PKGS[$t.qname] } else { $t.pkg }
        $d = Dep $p $tp 'import' $i
        $bad = CheckWriteDown $p $t $i 'imports'
        if ($bad -and $null -ne $d) { $d.bad = @($d.bad) + , "imports $($t.qname)" }
        if ($i.star -and $null -ne $PKGS[$t.qname]) {
            $queue = @($PKGS[$t.qname]); $qi = 0
            while ($qi -lt $queue.Count) {
                $q = $queue[$qi]; $qi++
                foreach ($k in @($q.members.Keys)) { if ($null -eq $vis[$k]) { $vis[$k] = $q.members[$k] } }
                if ($i.star -ceq '**') { foreach ($c in $PORDER) { if ($null -ne $c.parent -and $c.parent -eq $q) { $queue += , $c } } }
            }
        } elseif (-not $i.star) { if ($null -eq $vis[$t.name]) { $vis[$t.name] = $t } }
    }
    $VISIBLE[$p.qname] = $vis
}
foreach ($p in $PORDER) {
    $vis = $VISIBLE[$p.qname]
    for ($o = $p.parent; $null -ne $o; $o = $o.parent) { $v = $VISIBLE[$o.qname]; foreach ($k in @($v.Keys)) { if ($null -eq $vis[$k]) { $vis[$k] = $v[$k] } } }
    foreach ($r in @($p.refs)) {
        $t = $null
        if ($r.qual) { $t = ResolveQ $r.segs }
        else {
            $n = $r.segs[0]
            if ($null -ne $p.members[$n]) { continue }
            $own = $false; for ($o = $p.parent; $null -ne $o; $o = $o.parent) { if ($null -ne $o.members[$n]) { $own = $true; break } }
            if ($own) { continue }
            $t = $vis[$n]
        }
        if ($null -eq $t -or $t -eq $p) { continue }
        $tp = if ($null -ne $PKGS[$t.qname]) { $PKGS[$t.qname] } else { $t.pkg }
        if ($null -eq $tp -or ((RootOf $tp) -eq (RootOf $p) -and -not $OPT['nested'] -and (RankOf $t) -le $p.rank)) { continue }
        $d = Dep $p $tp 'ref' $r
        $bad = CheckWriteDown $p $t $r 'references'
        if ($bad -and $null -ne $d) { $d.bad = @($d.bad) + , "references $($t.qname)" }
    }
}
# text leakage
$HINAME = NewH
foreach ($e in $ESORTED) { $r = RankOf $e; if ($r -gt 0 -and $e.name.Length -ge 4 -and ($null -eq $HINAME[$e.name] -or $HINAME[$e.name][0] -lt $r)) { $HINAME[$e.name] = @($r, $e.qname) } }
foreach ($p in $PORDER) {
    $seen = NewH
    foreach ($w in @($p.words)) {
        $h = $HINAME[$w[0]]; if ($null -eq $h) { continue }
        if (-not ($h[0] -gt $p.rank)) { continue }
        if ($null -ne $p.members[$w[0]]) { continue }
        if ($seen.ContainsKey($w[0])) { continue }; $seen[$w[0]] = 1
        $pat = '^' + [regex]::Escape($p.file) + ':\d+: error: .* ''' + [regex]::Escape($h[1]) + '''$'
        if (@($script:DIAG | Where-Object { T $_[3] $pat }).Count) { continue }
        Diag $p.file $w[1] 'warning' "text in $(Lvl $p.rank) package '$($p.qname)' names $(Lvl $h[0]) element '$($h[1])'"
    }
}

# ------------------------------------------------------------------ graph layout
$NDEP = $DEP.Count
$WD = @(foreach ($k in @($DEP.Keys)) { if (@($DEP[$k].bad).Count) { 1 } }).Count
foreach ($k in @($DEP.Keys)) { if ($HIDE.ContainsKey($DEP[$k].from.qname) -or $HIDE.ContainsKey($DEP[$k].to.qname)) { $DEP.Remove($k) } }
$NODES = @($PORDER | Where-Object { ($OPT['nested'] -or $null -eq $_.parent) -and -not $HIDE.ContainsKey($_.qname) })
$DSORTED = @(foreach ($k in (SortStr @($DEP.Keys))) { $DEP[$k] })
$OUTE = NewH; foreach ($d in $DSORTED) { $k = $d.from.qname; if ($null -eq $OUTE[$k]) { $OUTE[$k] = @() }; $OUTE[$k] = @($OUTE[$k]) + , $d }
$STATE = NewH; $BACK = @()
function Dfs($n) {
    $STATE[$n.qname] = 1
    foreach ($d in (SortBy (Arr $OUTE[$n.qname]) { param($x, $y) Cmp $x.to.qname $y.to.qname })) {
        $s = Dflt $STATE[$d.to.qname] 0
        if ($s -eq 1) { $d.back = $true; $script:BACK += , $d }
        elseif ($s -eq 0) { Dfs $d.to }
    }
    $STATE[$n.qname] = 2
}
foreach ($n in $NODES) { if (-not $STATE[$n.qname]) { Dfs $n } }
foreach ($d in $BACK) { Diag $d.at[0] $d.at[1] 'warning' "package dependency cycle: '$($d.from.qname)' depends on '$($d.to.qname)', which depends back on it (directly or through other packages)" }
$LAYER = NewH
function Lay($n) {
    if ($LAYER.ContainsKey($n.qname)) { return $LAYER[$n.qname] }
    $LAYER[$n.qname] = 0
    $l = 0
    foreach ($d in (Arr $OUTE[$n.qname])) { if ($d.back) { continue }; $x = (Lay $d.to) + 1; if ($x -gt $l) { $l = $x } }
    $LAYER[$n.qname] = $l
    $l
}
foreach ($n in $NODES) { [void](Lay $n) }
$MAXL = MaxNum (@(0) + @($LAYER.Values))
$COLS = @{}; $script:NCOLS = 0
function ColAdd([int]$c, $v) { if ($null -eq $COLS[$c]) { $COLS[$c] = @() }; $COLS[$c] = @($COLS[$c]) + , $v; if ($c + 1 -gt $script:NCOLS) { $script:NCOLS = $c + 1 } }
foreach ($n in $NODES) { ColAdd ($MAXL - $LAYER[$n.qname]) $n }
foreach ($d in $DSORTED) {
    if ($d.back) { continue }
    $ca = $MAXL - $LAYER[$d.from.qname]; $cb = $MAXL - $LAYER[$d.to.qname]
    $d.via = @()
    for ($c = $ca + 1; $c -le $cb - 1; $c++) { $v = Rec @{ dummy = $true; qname = "~$($d.from.qname)>$($d.to.qname)#$c" }; ColAdd $c $v; $d.via = @($d.via) + , $v }
}
for ($c = 0; $c -lt $script:NCOLS; $c++) { $COLS[$c] = SortBy (Arr $COLS[$c]) { param($x, $y) $r = NCmp ([int][bool]$x.dummy) ([int][bool]$y.dummy); if ($r) { return $r }; Cmp $x.qname $y.qname } }
$NBR = NewH
function NbrAdd([string]$q, [string]$side, $v) { if ($null -eq $NBR[$q]) { $NBR[$q] = @{ l = @(); r = @() } }; $NBR[$q][$side] = @($NBR[$q][$side]) + , $v }
foreach ($d in $DSORTED) {
    if ($d.back) { continue }
    $chain = @($d.from) + @($d.via) + @($d.to)
    for ($i = 0; $i -lt $chain.Count - 1; $i++) { NbrAdd $chain[$i].qname 'r' $chain[$i + 1]; NbrAdd $chain[$i + 1].qname 'l' $chain[$i] }
}
$POSN = NewH
function Reindex { for ($c = 0; $c -lt $script:NCOLS; $c++) { $col = Arr $COLS[$c]; for ($i = 0; $i -lt $col.Count; $i++) { $POSN[$col[$i].qname] = $i } } }
Reindex
for ($sweep = 1; $sweep -le 8; $sweep++) {
    if ($sweep % 2) { $order = @(for ($c = 1; $c -lt $script:NCOLS; $c++) { $c }) } else { $order = @(for ($c = $script:NCOLS - 2; $c -ge 0; $c--) { $c }) }
    $side = if ($sweep % 2) { 'l' } else { 'r' }
    foreach ($c in $order) {
        $bc = NewH
        foreach ($n in (Arr $COLS[$c])) {
            $nb = @(); if ($null -ne $NBR[$n.qname]) { $nb = @($NBR[$n.qname][$side]) }
            $sum = 0; foreach ($x in $nb) { $sum += $POSN[$x.qname] }
            $bc[$n.qname] = if ($nb.Count) { $sum / $nb.Count } else { $POSN[$n.qname] }
        }
        $COLS[$c] = SortBy (Arr $COLS[$c]) { param($x, $y) $r = NCmp $bc[$x.qname] $bc[$y.qname]; if ($r) { return $r }; NCmp $POSN[$x.qname] $POSN[$y.qname] }
        Reindex
    }
}

# ------------------------------------------------------------------ geometry
$CW = 7.2; $FS = 12; $SFS = 10.5; $LH = 15; $PADX = 10; $COLGAP = 110; $VGAP = 22; $TOPY = 92; $PAD = 16
function TW([string]$s) { $s.Length * $CW }
function STW([string]$s) { $s.Length * $CW * $SFS / $FS }
$MAXIN = NewH
foreach ($x in $ESORTED + @($PORDER)) {
    $node = NodeOf $(if ($null -ne $PKGS[$x.qname]) { $x } else { $x.pkg })
    $r = RankOf $x
    if ($r -gt (Dflt $MAXIN[$node.qname] (-1))) { $MAXIN[$node.qname] = $r }
}
foreach ($n in $NODES) {
    $mx = Dflt $MAXIN[$n.qname] (-1)
    $n.inside = if ($mx -gt $n.rank) { $mx } else { $null }
    $n.l1 = $n.qname
    $n.l2 = if ($n.lib) { "$($script:LAQUO)library$($script:RAQUO) " } else { '' }
    $n.l2 += $(if ($NOMARK) { '' } elseif ($null -ne $n.marking) { "@Marking $($n.marking)" } elseif ($null -ne $n.parent) { 'inherits ' + (Lvl $n.rank) } else { 'NO MARKING' })
    $n.l3 = $(if ($n.inside) { 'contains ' + (Lvl $n.inside) + '; ' } else { '' }) + "$($n.ndef) def(s)" + $(if ($n.nreq) { ", $($n.nreq) req(s)" } else { '' })
    if (-not $OPT['nested']) {
        $rdef = 0; $rreq = 0; $nsub = 0
        foreach ($q in $PORDER) { if (-not ($q -eq $n) -and (RootOf $q) -eq $n) { $rdef += $q.ndef; $rreq += $q.nreq; $nsub++ } }
        $n.l3 = $(if ($n.inside) { 'contains ' + (Lvl $n.inside) + '; ' } else { '' }) + ($n.ndef + $rdef) + ' def(s)' +
            $(if ($n.nreq + $rreq) { ', ' + ($n.nreq + $rreq) + ' req(s)' } else { '' }) + $(if ($nsub) { ", $nsub nested pkg(s)" } else { '' })
    }
    $n.w = (MaxNum @((TW $n.l1), (STW $n.l2), (STW $n.l3))) + 2 * $PADX; $n.h = 8 + 3 * $LH + 4
}
$COLX = @{}; $COLW = @{}
for ($c = 0; $c -lt $script:NCOLS; $c++) { $COLW[$c] = MaxNum (@(0) + @((Arr $COLS[$c]) | ForEach-Object { Dflt $_.w 0 })) }
$COLX[0] = $PAD; for ($c = 1; $c -lt $script:NCOLS; $c++) { $COLX[$c] = $COLX[$c - 1] + $COLW[$c - 1] + $COLGAP }
$SVGH = $TOPY
for ($c = 0; $c -lt $script:NCOLS; $c++) {
    $y = $TOPY
    foreach ($n in (Arr $COLS[$c])) {
        if ($n.dummy) { $n.x = $COLX[$c]; $n.w = $COLW[$c]; $n.y = $y; $n.h = 10; $y += 10 + $VGAP / 2; continue }
        $n.x = $COLX[$c] + ($COLW[$c] - $n.w) / 2; $n.y = $y; $y += $n.h + $VGAP
    }
    if ($y -gt $SVGH) { $SVGH = $y }
}
for ($c = 0; $c -lt $script:NCOLS; $c++) {
    $col = Arr $COLS[$c]; if (-not $col.Count) { continue }
    $span = $col[-1].y + $col[-1].h - $TOPY; $dy = ($SVGH - $VGAP - $TOPY - $span) / 2
    foreach ($n in $col) { $n.y += $dy }
}
$lastc = $script:NCOLS - 1
$SVGW = $(if ($lastc -ge 0) { $COLX[$lastc] + $COLW[$lastc] } else { $COLX[0] }) + $PAD; if ($SVGW -lt 720) { $SVGW = 720 }
$SVGH += 40 + $(if ($BACK.Count) { 30 } else { 0 })

# ------------------------------------------------------------------ draw
$PAL = @('#e8f5e9', '#fff8e1', '#ffe0b2', '#ffccbc', '#f8bbd0', '#e1bee7', '#d1c4e9')
$PALL = @('#2e7d32', '#f9a825', '#ef6c00', '#d84315', '#ad1457', '#6a1b9a', '#4527a0')
$CLR = NewH; foreach ($kv in @(@('ink', '#212121'), @('dim', '#616161'), @('edge', '#90a4ae'), @('bad', '#c62828'), @('back', '#ef6c00'), @('none', '#ffffff'))) { $CLR[$kv[0]] = $kv[1] }
$SVGL = @{}; $script:ON = 0
function O([string]$s) { $SVGL[$script:ON] = $s; $script:ON++ }
O '<?xml version="1.0" encoding="UTF-8"?>'
O ('<svg xmlns="http://www.w3.org/2000/svg" width="' + (N $SVGW) + '" height="' + (N $SVGH) + '" viewBox="0 0 ' + (N $SVGW) + ' ' + (N $SVGH) + '" font-family="DejaVu Sans Mono, Consolas, Menlo, monospace" font-size="' + $FS + '">')
O ('<!-- generated by sysml-pkg-svg.pl from ' + (GSub (Esc ($ARGV0 -join ' ')) '-(?=-)' '- ') + ' -->')
O ('<defs><marker id="ar" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse"><path d="M0 0 L10 5 L0 10 z" fill="' + $CLR.edge + '"/></marker>')
O ('<marker id="arb" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse"><path d="M0 0 L10 5 L0 10 z" fill="' + $CLR.bad + '"/></marker>')
O ('<marker id="arc" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse"><path d="M0 0 L10 5 L0 10 z" fill="' + $CLR.back + '"/></marker></defs>')
O '<rect width="100%" height="100%" fill="#ffffff"/>'
$SUMLINE = '{0} file(s): {1} error(s), {2} warning(s), {3} package(s), {4} dependenc{5}, {6} write-down edge(s), {7} cycle(s)' -f $FILES.Count, $script:NERR, $script:NWARN, $PKGS.Count, $NDEP, $(if ($NDEP -eq 1) { 'y' } else { 'ies' }), $WD, $BACK.Count
if ($NOMARK) { $SUMLINE += '; markings not checked (--no-markings)' }
$title = $OPT['title']
if ($NOMARK -and $null -ne $title) { $title = Sub $title 'packages and markings\z' 'packages and dependencies' }
if ($null -eq $title) { $title = if ($NOMARK) { 'Packages and dependencies' } else { 'Packages and markings' } }
O ('<text x="' + $PAD + '" y="26" font-size="16" font-weight="bold" fill="' + $CLR.ink + '">' + (Esc $title) + '</text>')
O ('<text x="' + $PAD + '" y="46" fill="' + $CLR.dim + '">' + (Esc ($SUMLINE + $(if ($OPT['hide']) { "; not drawn: $($OPT['hide'])" } else { '' }))) + '</text>')
$lx = $PAD; $ly = 60
O ('<g font-size="11" fill="' + $CLR.dim + '">')
if (-not $NOMARK) {
    for ($i = 0; $i -lt $LEVELS.Count; $i++) {
        O ('<rect x="' + (N $lx) + '" y="' + $ly + '" width="22" height="13" fill="' + $PAL[$i % $PAL.Count] + '" stroke="' + $PALL[$i % $PALL.Count] + '"/><text x="' + (N ($lx + 28)) + '" y="' + ($ly + 11) + '">' + (Esc $LEVELS[$i]) + '</text>')
        $lx += 40 + (STW $LEVELS[$i])
    }
    O ('<rect x="' + (N $lx) + '" y="' + $ly + '" width="22" height="13" fill="#ffffff" stroke="' + $CLR.bad + '" stroke-dasharray="3 2"/><text x="' + (N ($lx + 28)) + '" y="' + ($ly + 11) + '">no marking</text>')
    $lx += 120
}
O ('<path d="M' + (N $lx) + ' ' + ($ly + 7) + ' h28" stroke="' + $CLR.edge + '" marker-end="url(#ar)"/><text x="' + (N ($lx + 34)) + '" y="' + ($ly + 11) + '">imports</text>'); $lx += 100
O ('<path d="M' + (N $lx) + ' ' + ($ly + 7) + ' h28" stroke="' + $CLR.edge + '" stroke-dasharray="2 3" marker-end="url(#ar)"/><text x="' + (N ($lx + 34)) + '" y="' + ($ly + 11) + '">references only</text>'); $lx += 150
O ('<path d="M' + (N $lx) + ' ' + ($ly + 7) + ' h28" stroke="' + $CLR.bad + '" stroke-width="2.4" marker-end="url(#arb)"/><text x="' + (N ($lx + 34)) + '" y="' + ($ly + 11) + '">write-down</text>'); $lx += 110
O ('<path d="M' + (N $lx) + ' ' + ($ly + 7) + ' h28" stroke="' + $CLR.back + '" stroke-dasharray="6 3" marker-end="url(#arc)"/><text x="' + (N ($lx + 34)) + '" y="' + ($ly + 11) + '">cycle</text>')
O '</g>'
foreach ($d in (SortBy $DSORTED { param($x, $y) NCmp ([int](@($x.bad).Count -gt 0)) ([int](@($y.bad).Count -gt 0)) })) {
    $na = $d.from; $nb = $d.to
    $bad = @($d.bad).Count
    if ($bad) { $col = $CLR.bad; $w = 2.4; $mk = 'arb' } elseif ($d.back) { $col = $CLR.back; $w = 1.4; $mk = 'arc' } else { $col = $CLR.edge; $w = 1.3; $mk = 'ar' }
    $dash = if ($d.back) { ' stroke-dasharray="6 3"' } elseif (-not @($d.imports).Count) { ' stroke-dasharray="2 3"' } else { '' }
    if ($d.back) {
        $x1 = $na.x + $na.w / 2; $y1 = $na.y + $na.h
        $x2 = $nb.x + $nb.w / 2; $y2 = $nb.y + $nb.h
        $yb = $(if ($y1 -gt $y2) { $y1 } else { $y2 }) + 34
        $path = 'M' + (F $x1 1) + ' ' + (F $y1 1) + ' C' + (F $x1 1) + ' ' + (F $yb 1) + ' ' + (F $x2 1) + ' ' + (F $yb 1) + ' ' + (F $x2 1) + ' ' + (F ($y2 + 2) 1)
    } else {
        $pt = @(, @(($na.x + $na.w), ($na.y + $na.h / 2)))
        foreach ($v in @($d.via)) { $pt += , @(($v.x + $v.w / 2), ($v.y + 5)) }
        $pt += , @(($nb.x - 2), ($nb.y + $nb.h / 2))
        $path = 'M' + (F $pt[0][0] 1) + ' ' + (F $pt[0][1] 1)
        for ($i = 1; $i -lt $pt.Count; $i++) {
            $pp = $pt[$i - 1]; $qq = $pt[$i]; $mx = ($pp[0] + $qq[0]) / 2
            $path += ' C' + (F $mx 1) + ' ' + (F $pp[1] 1) + ' ' + (F $mx 1) + ' ' + (F $qq[1] 1) + ' ' + (F $qq[0] 1) + ' ' + (F $qq[1] 1)
        }
    }
    $tip = @("$($na.qname) -> $($nb.qname)") + @($d.imports)
    if ($d.refs) { $tip += , "$($d.refs) reference(s)" }
    foreach ($b in @($d.bad)) { $tip += , "WRITE-DOWN: $b" }
    if ($d.back) { $tip += , 'part of a dependency cycle' }
    O ('<g><title>' + (Esc ($tip -join "`n")) + '</title><path d="' + $path + '" fill="none" stroke="' + $col + '" stroke-width="' + (N $w) + '"' + $dash + ' marker-end="url(#' + $mk + ')"/>' +
       '<path d="' + $path + '" fill="none" stroke="transparent" stroke-width="10"/></g>')
}
foreach ($n in $NODES) {
    $r = $n.rank
    if ($r -ge 0) { $fill = $PAL[$r % $PAL.Count]; $stroke = $PALL[$r % $PALL.Count]; $dash = '' }
    elseif ($NOMARK) { $fill = $CLR.none; $stroke = $CLR.edge; $dash = '' }
    else { $fill = $CLR.none; $stroke = $CLR.bad; $dash = ' stroke-dasharray="4 3"' }
    $unmarkedRoot = (-not $NOMARK -and $null -eq $n.marking -and $null -eq $n.parent)
    if ($unmarkedRoot) { $stroke = $CLR.bad }
    $tip = @($n.qname, $n.l2, $n.l3, "$($n.file):$($n.line)")
    if (@($n.imports).Count) { $tip += , ('imports: ' + ((@($n.imports) | ForEach-Object { (@($_.segs) -join '::') + $(if ($_.star) { "::$($_.star)" } else { '' }) }) -join ', ')) }
    $x = $n.x; $y = $n.y
    O ('<g><title>' + (Esc ($tip -join "`n")) + '</title>')
    O ('<rect x="' + (F $x 1) + '" y="' + (F $y 1) + '" width="' + (F $n.w 1) + '" height="' + (F $n.h 1) + '" rx="3" fill="' + $fill + '" stroke="' + $stroke + '" stroke-width="1.6"' + $dash + '/>')
    if ($null -ne $n.inside -and $n.inside) { O ('<rect x="' + (F ($x + $n.w - 6) 1) + '" y="' + (F $y 1) + '" width="6" height="' + (F $n.h 1) + '" fill="' + $PALL[$n.inside % $PALL.Count] + '"/>') }
    O ('<text x="' + (F ($x + $PADX) 1) + '" y="' + (F ($y + 4 + $LH - 2) 1) + '" font-weight="bold" fill="' + $CLR.ink + '">' + (Esc $n.l1) + '</text>')
    O ('<text x="' + (F ($x + $PADX) 1) + '" y="' + (F ($y + 4 + 2 * $LH - 2) 1) + '" font-size="' + (N $SFS) + '" fill="' + $(if ($unmarkedRoot) { $CLR.bad } else { $CLR.dim }) + '">' + (Esc $n.l2) + '</text>')
    O ('<text x="' + (F ($x + $PADX) 1) + '" y="' + (F ($y + 4 + 3 * $LH - 2) 1) + '" font-size="' + (N $SFS) + '" fill="' + $CLR.dim + '">' + (Esc $n.l3) + '</text>')
    O '</g>'
}
O '</svg>'
$svg = (@(for ($i = 0; $i -lt $script:ON; $i++) { $SVGL[$i] + "`n" })) -join ''
if (-not (VWrite $OPT['o'] $svg)) { PErr "$($OPT['o']): cannot write"; VExit 2 }
foreach ($d in (SortBy $script:DIAG { param($x, $y) $c = Cmp $x[0] $y[0]; if ($c) { return $c }; $c = NCmp $x[1] $y[1]; if ($c) { return $c }; NCmp $x[2] $y[2] })) { PL $d[3] }
PL "$SUMLINE -> $($OPT['o'])"
VExit $(if ($script:NERR) { 1 } else { 0 })
