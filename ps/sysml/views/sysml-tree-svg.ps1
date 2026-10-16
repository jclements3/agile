<#
sysml-tree-svg.ps1 : draw the part decomposition of a SysML v2 model as one SVG (general view).
PowerShell port of tools/sysml/views/sysml-tree-svg.pl (Constrained Language Mode safe, pure ASCII).

  sysml-tree-svg.ps1 [-o tree.svg] [--title T] [--root NAME]... [--all] [--depth N] [--features] [--outline]
                     [--hide-meta A,B] [--compare OLD]... [--changed] DIR|FILE...

Same options, SVG bytes, messages and exit status as the Perl.
#>
. (Join-Path $PSScriptRoot 'views-lib.ps1')
VBufferStderr
$go = GetOpts $args @('o=s', 'title=s', 'root=s@', 'all', 'depth=i', 'features', 'outline', 'hide-meta=s', 'compare=s@', 'changed', 'label=s@')
if (-not $go.ok -or -not @($go.rest).Count) { PErr 'usage: perl sysml-tree-svg.pl [-o tree.svg] [--title T] [--root NAME]... [--all] [--depth N] [--features] [--outline] [--compare OLD]... [--changed] DIR|FILE...'; VExit 2 }
$OPT = $go.opts; $ARGV0 = @($go.rest)
if ($null -eq $OPT['o']) { $OPT['o'] = 'tree.svg' }
if ($null -eq $OPT['depth']) { $OPT['depth'] = 12 }
if ($null -eq $OPT['hide-meta']) { $OPT['hide-meta'] = 'Provenance,V1Source' }
$ROOTOPTS = @(); if ($null -ne $OPT['root']) { $ROOTOPTS = @($OPT['root']) }
if ($OPT['changed'] -and $null -eq $OPT['compare']) { PErr 'sysml-tree-svg: --changed needs --compare'; VExit 2 }
$HIDE = NewH; foreach ($x in (SplitKeep $OPT['hide-meta'] ',')) { $HIDE[$x] = 1 }
$LABELS = @(); foreach ($l in @(Dflt $OPT['label'] @())) { $LABELS += , (SplitN $l '=' 2) }
function Shown([string]$f) { foreach ($l in $LABELS) { if ($f.StartsWith($l[0] + '/')) { return $l[1] + $f.Substring($l[0].Length + 1) } }; $f }
$script:NWARN = 0; $script:QUIETMODE = $false
function WarnAt([string]$f, $l, [string]$m) { if ($script:QUIETMODE) { return }; PErr ("{0}:{1}: warning: {2}" -f $f, (N $l), $m); $script:NWARN++ }
$NAMEP = $script:NAMERX; $REFP = $script:REFRX

# ------------------------------------------------------------------ parse
$script:DEFS = @(); $script:BYNAME = NewH
function ScopeOf($n, $top) { Rec @{ kind = 'node'; node = $n; pkg = $top.pkg } }
function Classify([string]$s, [string]$f, [int]$line, $top) {
    $s = Squash $s
    if ($s -eq '') { return $null }
    $m = M $s "^@\s*($REFP)\s*$"; if (-not $m.Success) { $m = M $s "^metadata\s+($REFP)\s*$" }
    if ($m.Success) {
        $sg = Segs $m.Groups[1].Value; $mn = $sg[-1]
        if ($null -ne $top.node -and -not $HIDE.ContainsKey($mn)) { $top.node.meta = @($top.node.meta) + , $mn }
        return (Rec @{ kind = 'other'; pkg = $top.pkg })
    }
    $hash = @()
    $s = Sub $s '^(?:(?:public|private|protected|abstract|variation|individual|derived|readonly|end)\s+)*' ''
    while ($true) { $m = M $s "^#\s*($NAMEP)\s*"; if (-not $m.Success) { break }; $hash += , $m.Groups[1].Value; $s = $s.Substring($m.Length) }
    $s = Sub $s '^(?:(?:public|private|protected|abstract)\s+)*' ''
    $m = M $s "^(?:standard\s+)?(?:library\s+)?package\s+($NAMEP)"
    if ($m.Success) { return (Rec @{ kind = 'package'; pkg = (@($top.pkg) + , (Unq $m.Groups[1].Value)) }) }
    $m = M $s "^part\s+def\s+($NAMEP)(.*)$"
    if ($m.Success) {
        $name = Unq $m.Groups[1].Value; $rest = $m.Groups[2].Value
        $sup = @()
        $m2 = M $rest "(?::>|\bspecializes\b)\s*($REFP(?:\s*,\s*$REFP)*)"
        if ($m2.Success) { foreach ($p in (SplitKeep $m2.Groups[1].Value '\s*,\s*')) { $sup += , (Segs $p) } }
        $d = Rec @{ kind = 'def'; name = $name; pkg = $top.pkg; sup = $sup; feats = @(); meta = $hash; file = $f; line = $line }
        $d.node = $d
        $script:DEFS += , $d
        if ($null -eq $script:BYNAME[$name]) { $script:BYNAME[$name] = @() }
        $script:BYNAME[$name] = @($script:BYNAME[$name]) + , $d
        return (ScopeOf $d $top)
    }
    if ($null -eq $top.node) { return $null }
    $owner = $top.node
    $m = M $s '^(?:(in|out|inout)\s+)?(ref\s+)?(part|item|attribute|port)\b(?!\s+def\b)\s*(.*)$'
    if ($m.Success) {
        $u = Rec @{ kind = $m.Groups[3].Value; ref = $m.Groups[2].Success; dir = (Dflt (G $m 1) ''); file = $f; line = $line; feats = @(); meta = $hash; owner = $owner }
        $decl = Sub $m.Groups[4].Value '\s*(?::=|=|\bdefault\b).*$' ''
        $m2 = M $decl "^($NAMEP)"
        if ($m2.Success -and -not (T $decl '^(?:redefines|subsets|references)\b')) { $u.name = Unq $m2.Groups[1].Value }
        $m2 = M $decl "(?::>>|\bredefines\b)\s*($REFP)"
        if ($m2.Success) { $u.redef = (Segs $m2.Groups[1].Value)[-1]; if ($null -eq $u.name) { $u.name = $u.redef } }
        $m2 = M $decl "(?:^|[^:>]):\s*(~?)\s*($REFP)"
        if (-not $m2.Success) { $m2 = M $decl "\bdefined\s+by\s*(~?)\s*($REFP)" }
        if ($m2.Success) { $u.conj = $m2.Groups[1].Value; $u.type = Segs $m2.Groups[2].Value }
        $m2 = M $decl '\[\s*([^\]]+?)\s*\]'
        if ($m2.Success) { $u.mult = $m2.Groups[1].Value }
        if ($null -eq $u.name) { $u.name = '(unnamed)' }
        $owner.feats = @($owner.feats) + , $u
        return (ScopeOf $u $top)
    }
    $null
}
$TOK = Rx '\G(?:(\n)|(//[^\n]*)|(/\*)|("(?:[^"\\]|\\.)*"|''(?:[^''\\]|\\.)*'')|([{};])|([^{};"''/\n]+|/))'
function ParseFiles($list) {
    foreach ($real in $list) {
        $t = VRead $real
        $f = Shown $real
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
                    if ($null -ne $nd -and $body -ne '' -and $null -eq $nd.doc) { $nd.doc = $body }
                    $head = ''
                } elseif (T $head '^\s*comment\b') { $head = '' }
            }
            elseif ($m.Groups[4].Success) { $q = $m.Groups[4].Value; if (-not (T $head '\S')) { $hline = $line }; $head += $q; $line += NlCount $q }
            elseif ($m.Groups[5].Success) {
                $c = $m.Groups[5].Value
                if ($c -eq '}') { if ($sn -gt 1) { $sn-- }; $head = ''; continue }
                $st = Classify $head $f $hline $stack[$sn - 1]
                $head = ''
                if ($c -eq '{') { if ($null -eq $st) { $st = Rec @{ kind = 'other'; pkg = $stack[$sn - 1].pkg } }; $stack[$sn] = $st; $sn++ }
            }
            else { $x = $m.Groups[6].Value; if (-not (T $head '\S') -and (T $x '\S')) { $hline = $line }; $head += $x }
        }
    }
}

# ------------------------------------------------------------------ resolve
function FindDef($sg, $from) {
    $sg = @($sg)
    $c = $script:BYNAME[$sg[-1]]; if ($null -eq $c) { return $null }
    $c = @($c)
    if ($sg.Count -gt 1) {
        $q = @($c | Where-Object { $full = @($_.pkg) + , $_.name; $full.Count -ge $sg.Count -and ((@($full[($full.Count - $sg.Count)..($full.Count - 1)]) -join "`0") -ceq ($sg -join "`0")) })
        if ($q.Count) { $c = $q }
    }
    if ($c.Count -gt 1 -and $null -ne $from) {
        $p = @($from.pkg) -join '::'
        $near = @($c | Where-Object { (@($_.pkg) -join '::') -ceq $p })
        if ($near.Count) { $c = $near }
    }
    $c[0]
}
function ResolveTypes($u, $ctx) {
    if ($null -ne $u.type -and -not $u.ContainsKey('tdef')) {
        $u.tdef = FindDef $u.type $ctx
        if ($null -eq $u.tdef -and $u.kind -ceq 'part') { WarnAt $u.file $u.line ("part '$($u.name)' has type '" + (@($u.type) -join '::') + "' that is not a part def here") }
    }
    foreach ($x in @($u.feats)) { ResolveTypes $x $ctx }
}
function ResolveAll {
    foreach ($d in $script:DEFS) {
        $sd = @()
        foreach ($sg in @($d.sup)) { $s = FindDef $sg $d; if ($null -eq $s) { WarnAt $d.file $d.line ("'$($d.name)' specializes unknown '" + (@($sg) -join '::') + "'") } else { $sd += , $s } }
        $d.supdefs = $sd
    }
    foreach ($d in $script:DEFS) { foreach ($x in @($d.feats)) { ResolveTypes $x $d } }
}
$script:EFFMEMO = @{}
function Effective($d, $seen) {                     # -> , [array] of features
    $k = Id $d
    if ($script:EFFMEMO.ContainsKey($k)) { return , $script:EFFMEMO[$k] }
    if ($null -eq $seen) { $seen = @{} }
    if ($seen.ContainsKey($k)) { return , @() }
    $seen[$k] = 1
    $out = @(); $pos = NewH
    foreach ($s in @($d.supdefs)) {
        foreach ($f in (Effective $s $seen)) {
            if ($pos.ContainsKey($f.name)) { continue }
            $pos[$f.name] = $out.Count; $out += , (CopyRec $f @{ inherited = $true })
        }
    }
    foreach ($f in @($d.feats)) {
        $key = if ($null -ne $f.redef -and $pos.ContainsKey($f.redef)) { $f.redef } else { $f.name }
        if ($pos.ContainsKey($key)) { $out[$pos[$key]] = CopyRec $f @{ inherited = $false; merged = $out[$pos[$key]] } }
        else { $pos[$f.name] = $out.Count; $out += , $f }
    }
    $script:EFFMEMO[$k] = $out
    , $out
}
function UsageFeats($u) {
    $out = @(); $pos = NewH
    $base = Dflt $u.tdef $(if ($null -ne $u.merged) { $u.merged.tdef } else { $null })
    if ($null -ne $base) { foreach ($f in (Effective $base $null)) { $pos[$f.name] = $out.Count; $out += , $f } }
    foreach ($f in @($u.feats)) {
        $key = if ($null -ne $f.redef -and $pos.ContainsKey($f.redef)) { $f.redef } else { $f.name }
        if ($pos.ContainsKey($key)) { $out[$pos[$key]] = CopyRec $f @{ merged = $out[$pos[$key]] } }
        else { $pos[$f.name] = $out.Count; $out += , $f }
    }
    , $out
}
function Parts($feats) { , @(@($feats) | Where-Object { $_.kind -ceq 'part' }) }
function TdefOf($p) { if ($null -ne $p.tdef) { $p.tdef } elseif ($null -ne $p.merged) { $p.merged.tdef } else { $null } }

# ------------------------------------------------------------------ trees
function PickRoots {
    $roots = @()
    if ($ROOTOPTS.Count) {
        foreach ($r in $ROOTOPTS) {
            $d = FindDef (SplitKeep $r '::') $null
            if ($null -eq $d) { if ($script:QUIETMODE) { continue }; PErr "sysml-tree-svg: no part def '$r'"; VExit 2 }
            $roots += , $d
        }
    } else {
        $used = @{}
        foreach ($d in $script:DEFS) { foreach ($f in (Parts (Effective $d $null))) { $t = TdefOf $f; if ($null -ne $t -and -not $f.ref) { $used[(Id $t)] = 1 } } }
        $roots = @($script:DEFS | Where-Object { -not $used.ContainsKey((Id $_)) -and ($OPT['all'] -or (Parts (Effective $_ $null)).Count) })
    }
    , $roots
}
function Build($feats, [int]$depth, $path) {
    $kids = @()
    foreach ($p in (Parts $feats)) {
        $t = TdefOf $p
        $n = Rec @{ u = $p; depth = $depth; t = $t }
        $script:NNODES++
        if ($p.ref) { $n.note = '' }
        elseif ($null -ne $t -and $path.ContainsKey((Id $t))) { $n.note = 'cycle'; $script:NCYCLE++; WarnAt $p.file $p.line "recursive composition: '$($p.name)' : $($t.name)" }
        elseif ($depth -ge $OPT['depth']) { if ((Parts (UsageFeats $p)).Count) { $n.note = 'cut'; $script:NCUT++ } }
        else { $np = $path.Clone(); if ($null -ne $t) { $np[(Id $t)] = 1 }; $n.kids = Build (UsageFeats $p) ($depth + 1) $np }
        $kids += , $n
    }
    , $kids
}

# ------------------------------------------------------------------ box text and size
$CW = 7.2; $FS = 12; $SFS = 10.5; $LH = 15; $PADX = 10; $COLGAP = 56; $VGAP = 8; $script:TOPY = 70; $PAD = 16
function TW([string]$s) { $s.Length * $CW }
function STW([string]$s) { $s.Length * $CW * $SFS / $FS }
function MStr($m) { if ($null -ne $m) { "[$m]" } else { '' } }
function MetaLine([string]$kw, $ms) { (@("$($script:LAQUO)$kw$($script:RAQUO)") + @(@($ms) | ForEach-Object { "@$_" })) -join ' ' }
function FeatLines($feats) {
    $l = @()
    foreach ($f in @(@($feats) | Where-Object { $_.kind -cmatch '^(?:attribute|port|item)$' })) {
        $type = if ($null -ne $f.type) { ' : ' + $(if ($f.conj) { '~' } else { '' }) + (@($f.type) -join '::') } else { '' }
        $l += , ($(if ($f.inherited) { '^' } else { '' }) + $(if ($f.dir) { "$($f.dir) " } else { '' }) + $(if ($f.kind -ceq 'attribute') { '' } else { "$($f.kind) " }) + "$($f.name)$type" + (MStr $f.mult))
    }
    , $l
}
function LabelNode($n, [string]$pkey) {
    if ($null -ne $n.def) {
        $d = $n.def
        $kwl = MetaLine 'part def' $d.meta
        $sup = if (@($d.supdefs).Count) { ' :> ' + ((@($d.supdefs) | ForEach-Object { $_.name }) -join ', ') } else { '' }
        $lines = @($d.name + $sup)
        $n.sub = @($d.pkg) -join '::'
        $effl = Effective $d $null
        $fall = FeatLines $effl
        $n.nparts = (Parts $effl).Count
        $n.doc = $d.doc; $n.at = "$($d.file):$($d.line)"
        $n.key = 'def:' + ((@($d.pkg) + , $d.name) -join '::')
        $n.show = $d.name
    } else {
        $u = $n.u
        $meta = @($u.meta); if ($null -ne $n.t) { $meta += @($n.t.meta) }
        $kwl = MetaLine $(if ($u.ref) { 'ref part' } else { 'part' }) $meta
        $type = if ($null -ne $u.type) { ' : ' + (@($u.type) -join '::') } elseif ($null -ne $u.merged -and $null -ne $u.merged.type) { ' : ' + (@($u.merged.type) -join '::') } else { '' }
        $redef = if ($u.redef) { ' :>> ' + $u.redef } else { '' }
        $nm = if ($u.redef -and $u.redef -ceq $u.name) { ":>> $($u.name)" } else { "$($u.name)$redef" }
        $mult = Dflt $u.mult $(if ($null -ne $u.merged) { $u.merged.mult } else { $null })
        $l0 = $(if ($u.inherited) { '^' } else { '' }) + $nm + $type + (MStr $mult)
        if ((Dflt $n.note '') -ceq 'cycle') { $l0 += ' (recursive)' }
        if ((Dflt $n.note '') -ceq 'cut') { $l0 += ' (...)' }
        $lines = @($l0)
        $uf = UsageFeats $u
        $fall = FeatLines $uf
        $n.nparts = (Parts $uf).Count
        $n.doc = Dflt $u.doc $(if ($null -ne $n.t) { $n.t.doc } else { $null })
        $n.at = "$($u.file):$($u.line)"
        $n.key = "$pkey/$($u.name)"
        $n.show = $u.name
    }
    $n.kwl = $kwl; $n.lines = $lines; $n.fall = $fall
    if ($OPT['features']) { $n.feat = $fall } else { $n.feat = @() }
    $n.st = 'same'; $n.why = @()
    $n.bad = ($OPT['outline'] -and (($null -ne $n.def -and $n.nparts) -or ($null -ne $n.kids -and @($n.kids).Count)) -and ($n.nparts -lt 2 -or $n.nparts -gt 9))
    foreach ($k in (Arr $n.kids)) { LabelNode $k $n.key }
}
function Analyze([bool]$beQuiet, $files) {
    $script:QUIETMODE = $beQuiet
    $script:DEFS = @(); $script:BYNAME = NewH; $script:EFFMEMO = @{}; $script:NNODES = 0; $script:NCYCLE = 0; $script:NCUT = 0
    ParseFiles $files
    ResolveAll
    $tlist = @()
    foreach ($d in (PickRoots)) { $pp = @{}; $pp[(Id $d)] = 1; $tlist += , (Rec @{ def = $d; depth = 0; kids = (Build (Effective $d $null) 1 $pp) }) }
    foreach ($t in $tlist) { LabelNode $t '' }
    $r = @{ trees = $tlist; ndefs = $script:DEFS.Count; nnodes = $script:NNODES; ncycle = $script:NCYCLE; ncut = $script:NCUT; nfiles = @($files).Count }
    $script:QUIETMODE = $false
    $r
}
$NEWV = Analyze $false (CollectFiles $ARGV0 'sysml-tree-svg')
$OLDV = $null; if ($null -ne $OPT['compare']) { $OLDV = Analyze $true (CollectFiles @($OPT['compare']) 'sysml-tree-svg') }
$TREELIST = @($NEWV.trees)
if ($null -ne $OLDV) { $script:TOPY = 86 }

# ------------------------------------------------------------------ compare
function MergeSeq($new, $old) {
    $new = @($new); $old = @($old)
    $oi = NewH; for ($i = 0; $i -lt $old.Count; $i++) { if (-not $oi.ContainsKey($old[$i].key)) { $oi[$old[$i].key] = $i } }
    $nk = NewH; foreach ($n in $new) { $nk[$n.key] = 1 }
    $out = @(); $p = 0
    foreach ($n in $new) {
        if ($oi.ContainsKey($n.key)) {
            $i = $oi[$n.key]
            while ($p -lt $i) { $o = $old[$p]; $p++; if (-not $nk.ContainsKey($o.key)) { $out += , @($o, 'removed', $null) } }
            if ($i -ge $p) { $p = $i + 1 }
            $out += , @($n, 'same', $old[$i])
        } else { $out += , @($n, 'added', $null) }
    }
    while ($p -lt $old.Count) { $o = $old[$p]; $p++; if (-not $nk.ContainsKey($o.key)) { $out += , @($o, 'removed', $null) } }
    , $out
}
function MarkSt($n, $st) { $n.st = $st; foreach ($k in (Arr $n.kids)) { MarkSt $k $st } }
function MergeNodes($new, $old) {
    $out = @()
    foreach ($m in (MergeSeq $new $old)) {
        $n = $m[0]; $st = $m[1]; $o = $m[2]
        if ($st -cne 'same') { MarkSt $n $st; $out += , $n; continue }
        $why = @()
        $was = (@($(if ($o.kwl -cne $n.kwl) { $o.kwl }) ) + @($o.lines)) -join ' / '
        if ($o.kwl -cne $n.kwl -or ((@($o.lines) -join "`n") -cne (@($n.lines) -join "`n"))) { $why += , "was $was" }
        $of = NewH; foreach ($x in @($o.fall)) { $of[$x] = 1 }; $nf = NewH; foreach ($x in @($n.fall)) { $nf[$x] = 1 }
        $add = @(@($n.fall) | Where-Object { -not $of.ContainsKey($_) }); $del = @(@($o.fall) | Where-Object { -not $nf.ContainsKey($_) })
        if ($add.Count -or $del.Count) { $why += , ('features ' + ((@($add | ForEach-Object { "+$_" }) + @($del | ForEach-Object { "-$_" })) -join ', ')) }
        if ((Dflt $o.doc '') -cne (Dflt $n.doc '')) { $why += , 'doc changed' }
        $n.why = $why
        $n.st = if ($why.Count) { 'changed' } else { 'same' }
        if ($null -ne $n.kids -or $null -ne $o.kids) { $n.kids = MergeNodes (Arr $n.kids) (Arr $o.kids) }
        $out += , $n
    }
    , $out
}
$CHANGES = @(); $CNT = NewH
function CountBelow($n) { $c = 0; foreach ($k in (Arr $n.kids)) { $c += 1 + (CountBelow $k) }; $c }
function WalkChanges($n, [string]$pst) {
    if ($null -eq $n.def) { $CNT[$n.st] = 1 + (Dflt $CNT[$n.st] 0) }
    if ($n.st -cne 'same' -and ($n.st -ceq 'changed' -or $n.st -cne $pst)) {
        $below = if ($n.st -cne 'changed') { CountBelow $n } else { 0 }
        $path = Sub $n.key '^def:(?:.*::)?' ''; $path = $path.Replace('/', '.')
        $script:CHANGES += , ($n.at + ': note: ' + $(if ($null -ne $n.def) { 'part def ' } else { 'part ' }) + "$path $($n.st)" +
            $(if ($below) { " (with $below part(s) below)" } else { '' }) + $(if (@($n.why).Count) { ': ' + (@($n.why) -join '; ') } else { '' }))
    }
    foreach ($k in (Arr $n.kids)) { WalkChanges $k $n.st }
}
if ($null -ne $OLDV) {
    $TREELIST = MergeNodes $TREELIST $OLDV.trees
    foreach ($t in $TREELIST) { WalkChanges $t 'same' }
}
function Prune($n) {
    $k = (Arr $n.kids)
    if (-not $k.Count) { return ($n.st -cne 'same') }
    $keep = @(); $hidden = 0
    foreach ($c in $k) { if (Prune $c) { $keep += , $c } else { $hidden++ } }
    if ($hidden -and ($keep.Count -or $n.st -cne 'same')) {
        $keep += , (Rec @{ more = $hidden; depth = $n.depth + 1; st = 'same'; kwl = ''; lines = @("$hidden unchanged part(s)"); feat = @(); why = @(); key = "$($n.key)/..." })
    }
    $n.kids = $keep
    ($n.st -cne 'same') -or (@($keep | Where-Object { -not $_.more }).Count -gt 0)
}
if ($OPT['changed']) { $TREELIST = @($TREELIST | Where-Object { Prune $_ }) }

function SizeNode($n) {
    $w = 0
    $cands = @(STW $n.kwl) + @(@($n.lines) | ForEach-Object { TW $_ }) + @(@($n.feat) | ForEach-Object { STW $_ }) + @($(if ($n.sub) { STW $n.sub } else { 0 }))
    foreach ($x in $cands) { if ($x -gt $w) { $w = $x } }
    $n.w = $w + 2 * $PADX
    $n.h = 8 + $LH * ($(if ($n.kwl -ne '') { 1 } else { 0 }) + @($n.lines).Count + $(if ($n.sub) { 1 } else { 0 })) + $(if (@($n.feat).Count) { 6 + $LH * @($n.feat).Count } else { 0 }) + 2
    foreach ($k in (Arr $n.kids)) { SizeNode $k }
}
foreach ($t in $TREELIST) { SizeNode $t }

# ------------------------------------------------------------------ layout
$COLW = @{}; $script:NCOL = 0
function Widths($n) { $d = $n.depth; if ($null -eq $COLW[$d] -or $n.w -gt $COLW[$d]) { $COLW[$d] = $n.w }; if ($d + 1 -gt $script:NCOL) { $script:NCOL = $d + 1 }; foreach ($k in (Arr $n.kids)) { Widths $k } }
foreach ($t in $TREELIST) { Widths $t }
$COLX = @{}; $COLX[0] = $PAD
for ($i = 1; $i -lt $script:NCOL; $i++) { $COLX[$i] = $COLX[$i - 1] + $COLW[$i - 1] + $COLGAP }
$script:CURSOR = $script:TOPY
function ShiftTree($n, $dy) { $n.y += $dy; foreach ($k in (Arr $n.kids)) { ShiftTree $k $dy } }
function Place($n) {
    $start = $script:CURSOR
    $n.x = $COLX[$n.depth]
    $k = (Arr $n.kids)
    if (-not $k.Count) { $n.y = $script:CURSOR; $script:CURSOR += $n.h + $VGAP; return }
    foreach ($c in $k) { Place $c }
    $cy = ($k[0].y + $k[0].h / 2 + $k[-1].y + $k[-1].h / 2) / 2
    $n.y = $cy - $n.h / 2
    if ($n.y -lt $start) { $dy = $start - $n.y; foreach ($c in $k) { ShiftTree $c $dy }; $n.y = $start; $script:CURSOR += $dy }
    if ($n.y + $n.h + $VGAP -gt $script:CURSOR) { $script:CURSOR = $n.y + $n.h + $VGAP }
}
foreach ($t in $TREELIST) { Place $t; $script:CURSOR += 18 }
$lastw = if ($script:NCOL -gt 0) { $COLW[$script:NCOL - 1] } else { 200 }
$lastx = if ($script:NCOL -gt 0) { $COLX[$script:NCOL - 1] } else { $COLX[0] }
$SVGW = $lastx + $lastw + $PAD
if ($SVGW -lt 640) { $SVGW = 640 }
$SVGH = $script:CURSOR + 20

# ------------------------------------------------------------------ draw
$CLR = NewH
foreach ($kv in @(@('ink', '#212121'), @('dim', '#616161'), @('line', '#78909c'), @('def', '#e8eaf6'), @('defl', '#283593'), @('use', '#ffffff'),
                  @('usel', '#455a64'), @('ref', '#fafafa'), @('bad', '#e65100'), @('badbg', '#fff3e0'), @('inh', '#7b1fa2'),
                  @('added', '#2e7d32'), @('addedbg', '#e8f5e9'), @('changed', '#ef6c00'), @('changedbg', '#fff3e0'),
                  @('removed', '#c62828'), @('removedbg', '#f5f5f5'))) { $CLR[$kv[0]] = $kv[1] }
$SVGL = @{}; $script:ON = 0
function O([string]$s) { $SVGL[$script:ON] = $s; $script:ON++ }
O '<?xml version="1.0" encoding="UTF-8"?>'
O ('<svg xmlns="http://www.w3.org/2000/svg" width="' + (N $SVGW) + '" height="' + (N $SVGH) + '" viewBox="0 0 ' + (N $SVGW) + ' ' + (N $SVGH) + '" font-family="DejaVu Sans Mono, Consolas, Menlo, monospace" font-size="' + $FS + '">')
$gen = ($ARGV0 -join ' ') + $(if ($null -ne $OPT['compare']) { ', compared with ' + (@($OPT['compare']) -join ' ') } else { '' })
O ('<!-- generated by sysml-tree-svg.pl from ' + (GSub (Esc $gen) '-(?=-)' '- ') + ' -->')
O '<rect width="100%" height="100%" fill="#ffffff"/>'
$title = if ($null -ne $OPT['title']) { $OPT['title'] } elseif ($null -ne $OLDV) { 'Part decomposition changes' } else { 'Part decomposition' }
$sum = '{0} part def(s), {1} tree(s), {2} part node(s)' -f $NEWV.ndefs, @($NEWV.trees).Count, $NEWV.nnodes
if ($NEWV.ncycle) { $sum += ", $($NEWV.ncycle) recursive" }
if ($NEWV.ncut) { $sum += ", $($NEWV.ncut) cut at depth $($OPT['depth'])" }
if ($OPT['changed']) { $sum += '; changes only' }
$dsum = if ($null -ne $OLDV) { 'parts +{0} -{1} ~{2}' -f (Dflt $CNT['added'] 0), (Dflt $CNT['removed'] 0), (Dflt $CNT['changed'] 0) } else { '' }
$script:NBAD = 0
O ('<text x="' + $PAD + '" y="26" font-size="16" font-weight="bold" fill="' + $CLR.ink + '">' + (Esc $title) + '</text>')
$SUMIDX = $script:ON; O ''

$EDGES = @{}; $script:NE = 0; $BOXES = @{}; $script:NB = 0
function E([string]$s) { $EDGES[$script:NE] = $s; $script:NE++ }
function B([string]$s) { $BOXES[$script:NB] = $s; $script:NB++ }
function Draw($n) {
    $k = (Arr $n.kids)
    if ($k.Count) {
        $x1 = $n.x + $n.w; $y1 = $n.y + $n.h / 2
        $bx = $x1 + $COLGAP / 2
        $ys = @($k | ForEach-Object { $_.y + $_.h / 2 })
        $composite = @($k | Where-Object { -not ($null -ne $_.u -and $_.u.ref) }).Count
        E ('<path d="M' + (F ($x1 + $(if ($composite) { 12 } else { 0 })) 1) + ' ' + (F $y1 1) + ' H' + (F $bx 1) + '" stroke="' + $CLR.line + '" fill="none"/>')
        $all = SortNum ($ys + @($y1))
        E ('<path d="M' + (F $bx 1) + ' ' + (F $all[0] 1) + ' V' + (F $all[-1] 1) + '" stroke="' + $CLR.line + '" fill="none"/>')
        foreach ($c in $k) {
            $dash = if (($null -ne $c.u -and $c.u.ref) -or $c.more) { ' stroke-dasharray="4 3"' } else { '' }
            $col = $CLR.line; $w = 1
            if ($c.st -ceq 'added') { $col = $CLR.added; $w = 2 }
            if ($c.st -ceq 'removed') { $col = $CLR.removed; $w = 1.6; $dash = ' stroke-dasharray="3 3"' }
            E ('<path d="M' + (F $bx 1) + ' ' + (F ($c.y + $c.h / 2) 1) + ' H' + (F $c.x 1) + '" stroke="' + $col + '" stroke-width="' + (N $w) + '" fill="none"' + $dash + '/>')
        }
        if ($composite) { E ('<path d="M' + (F $x1 1) + ' ' + (F $y1 1) + ' l6 -4.5 l6 4.5 l-6 4.5 z" fill="' + $CLR.usel + '"/>') }
    }
    $x = $n.x; $y = $n.y; $w = $n.w; $h = $n.h
    $isdef = $null -ne $n.def
    $isref = (-not $isdef) -and $null -ne $n.u -and $n.u.ref
    $st = Dflt $n.st 'same'
    $gone = $st -ceq 'removed'
    $bad = $n.bad -and -not $gone; if ($bad) { $script:NBAD++ }
    $stroke = if ($bad) { $CLR.bad } elseif ($isdef) { $CLR.defl } else { $CLR.usel }
    $fill = if ($bad) { $CLR.badbg } elseif ($isdef) { $CLR.def } elseif ($isref) { $CLR.ref } else { $CLR.use }
    $sw = if ($isdef) { '1.6' } else { '1.1' }
    if ($st -cne 'same') { $stroke = $CLR[$st]; $fill = $CLR["${st}bg"]; $sw = '2.2' }
    $rx = if ($isdef) { 0 } else { 7 }
    $dash = if ($isref -or $gone) { ' stroke-dasharray="5 3"' } else { '' }
    if ($n.more) {
        B ('<g><title>' + (Esc "$($n.more) part(s) not changed") + '</title><rect x="' + (F $x 1) + '" y="' + (F $y 1) + '" width="' + (F $w 1) + '" height="' + (F $h 1) + '" rx="7" fill="#ffffff" stroke="' + $CLR.line + '" stroke-dasharray="2 3"/>' +
           '<text x="' + (F ($x + $PADX) 1) + '" y="' + (F ($y + 4 + $LH - 2) 1) + '" font-style="italic" fill="' + $CLR.dim + '">' + (Esc $n.lines[0]) + '</text></g>')
        return
    }
    $tip = @((@(@($n.kwl) + @($n.lines) | Where-Object { $_ -ne '' })) -join ' / ')
    if ($st -cne 'same') { $tip += , ($st.ToUpper() + $(if (@($n.why).Count) { ': ' + (@($n.why) -join '; ') } else { '' })) }
    if ($null -ne $n.doc) { $tip += , $n.doc }
    if ($n.nparts -or $bad) { $tip += , ("$($n.nparts) part(s)" + $(if ($bad) { ' - outside the 2 to 9 outline rule' } else { '' })) }
    if ($isref) { $tip += , 'reference: not owned, not expanded' }
    $tip += , ($(if ($gone) { 'was at ' } else { '' }) + $n.at)
    $lt = if ($gone) { ' text-decoration="line-through"' } else { '' }
    B ('<g' + $(if ($gone) { ' opacity="0.65"' } else { '' }) + '><title>' + (Esc ($tip -join "`n")) + '</title>')
    B ('<rect x="' + (F $x 1) + '" y="' + (F $y 1) + '" width="' + (F $w 1) + '" height="' + (F $h 1) + '" rx="' + $rx + '" fill="' + $fill + '" stroke="' + $stroke + '" stroke-width="' + $sw + '"' + $dash + '/>')
    $ty = $y + 4 + $LH - 3
    B ('<text x="' + (F ($x + $PADX) 1) + '" y="' + (F $ty 1) + '" font-size="' + (N $SFS) + '" fill="' + $CLR.dim + '">' + (Esc $n.kwl) + '</text>')
    foreach ($l in @($n.lines)) {
        $ty += $LH
        $col = if ($l.StartsWith('^')) { $CLR.inh } else { $CLR.ink }
        B ('<text x="' + (F ($x + $PADX) 1) + '" y="' + (F $ty 1) + '" font-weight="' + $(if ($isdef) { 'bold' } else { 'normal' }) + '" fill="' + $col + '"' + $lt + '>' + (Esc $l) + '</text>')
    }
    if ($n.sub) { $ty += $LH; B ('<text x="' + (F ($x + $PADX) 1) + '" y="' + (F $ty 1) + '" font-size="' + (N $SFS) + '" fill="' + $CLR.dim + '">' + (Esc $n.sub) + '</text>') }
    if (@($n.feat).Count) {
        $ty += 6
        B ('<path d="M' + (F $x 1) + ' ' + (F ($ty - 1) 1) + ' H' + (F ($x + $w) 1) + '" stroke="' + $stroke + '" stroke-width="0.8"/>')
        foreach ($l in @($n.feat)) {
            $ty += $LH
            B ('<text x="' + (F ($x + $PADX) 1) + '" y="' + (F ($ty - 2) 1) + '" font-size="' + (N $SFS) + '" fill="' + $(if ($l.StartsWith('^')) { $CLR.inh } else { $CLR.dim }) + '">' + (Esc $l) + '</text>')
        }
    }
    B '</g>'
    foreach ($c in $k) { Draw $c }
}
foreach ($t in $TREELIST) { Draw $t }
if ($OPT['outline']) { $sum += ", $($script:NBAD) outside the 2-9 outline rule" }
$SVGL[$SUMIDX] = '<text x="' + $PAD + '" y="46" fill="' + $CLR.dim + '">' + (Esc $sum) + '</text>' + $(if ($null -ne $OLDV) { '<text x="' + $PAD + '" y="62" fill="' + $CLR.ink + '">' + (Esc $dsum) + '</text>' } else { '' })
$lx = $PAD + (TW $sum) + 64
O ('<g transform="translate(' + (N $lx) + ',14)" font-size="11" fill="' + $CLR.dim + '">')
O ('<rect x="0" y="0" width="22" height="13" fill="' + $CLR.def + '" stroke="' + $CLR.defl + '"/><text x="28" y="11">part def</text>')
O ('<rect x="96" y="0" width="22" height="13" rx="5" fill="' + $CLR.use + '" stroke="' + $CLR.usel + '"/><text x="124" y="11">part</text>')
O ('<rect x="168" y="0" width="22" height="13" rx="5" fill="' + $CLR.ref + '" stroke="' + $CLR.usel + '" stroke-dasharray="4 2"/><text x="196" y="11">ref part</text>')
O ('<path d="M0 30 l6 -4.5 l6 4.5 l-6 4.5 z" fill="' + $CLR.usel + '"/><path d="M12 30 H34" stroke="' + $CLR.line + '"/><text x="40" y="34">owns</text>')
O ('<text x="96" y="34" fill="' + $CLR.inh + '">^inherited</text>')
if ($OPT['outline']) { O ('<rect x="196" y="23" width="22" height="13" fill="' + $CLR.badbg + '" stroke="' + $CLR.bad + '"/><text x="224" y="34">outside 2-9</text>') }
if ($null -ne $OLDV) {
    O ('<rect x="0" y="44" width="22" height="13" rx="5" fill="' + $CLR.addedbg + '" stroke="' + $CLR.added + '" stroke-width="2"/><text x="28" y="55">added</text>')
    O ('<rect x="96" y="44" width="22" height="13" rx="5" fill="' + $CLR.changedbg + '" stroke="' + $CLR.changed + '" stroke-width="2"/><text x="124" y="55">changed</text>')
    O ('<rect x="196" y="44" width="22" height="13" rx="5" fill="' + $CLR.removedbg + '" stroke="' + $CLR.removed + '" stroke-dasharray="3 2"/><text x="224" y="55" text-decoration="line-through">removed</text>')
}
O '</g>'
for ($i = 0; $i -lt $script:NE; $i++) { O $EDGES[$i] }
for ($i = 0; $i -lt $script:NB; $i++) { O $BOXES[$i] }
O '</svg>'
$svg = (@(for ($i = 0; $i -lt $script:ON; $i++) { $SVGL[$i] + "`n" })) -join ''
if (-not (VWrite $OPT['o'] $svg)) { PErr "$($OPT['o']): cannot write"; VExit 2 }
function ChangeKey([string]$l) { $m = M $l '^(.*?):(\d+):'; if ($m.Success) { @($m.Groups[1].Value, [long]$m.Groups[2].Value) } else { @('', 0) } }
foreach ($l in (SortBy $CHANGES { param($x, $y) $a1 = ChangeKey $x; $b1 = ChangeKey $y; $c = Cmp $a1[0] $b1[0]; if ($c) { return $c }; $c = NCmp $a1[1] $b1[1]; if ($c) { return $c }; Cmp $x $y })) { PL $l }
PL ('tree-svg: {0} file(s), {1}, {2} warning(s){3} -> {4}' -f $NEWV.nfiles, $sum, $script:NWARN, $(if ($null -ne $OLDV) { "; $dsum" } else { '' }), $OPT['o'])
VExit 0
