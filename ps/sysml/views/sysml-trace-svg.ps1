<#
sysml-trace-svg.ps1 : draw the requirement trace of a SysML v2 model as one SVG.
PowerShell port of tools/sysml/views/sysml-trace-svg.pl (Constrained Language Mode safe, pure ASCII).

  sysml-trace-svg.ps1 [-o trace.svg] [--title T] [--gaps] [--match REGEX] [--compare OLD]... [--changed]
                      [--package P]... [--mono] DIR|FILE...

Same options, SVG bytes, messages and exit status as the Perl. --match takes a .NET regular expression (the same
syntax as Perl's for the patterns a requirement filter needs).
#>
. (Join-Path $PSScriptRoot 'views-lib.ps1')
$go = GetOpts $args @('o=s', 'title=s', 'gaps', 'match=s', 'compare=s@', 'changed', 'label=s@', 'package=s@', 'mono')
if (-not $go.ok -or -not @($go.rest).Count) { PErr 'usage: perl sysml-trace-svg.pl [-o trace.svg] [--title T] [--gaps] [--match REGEX] [--compare OLD]... [--changed] DIR|FILE...'; VExit 2 }
$OPT = $go.opts; $ARGV0 = @($go.rest)
if ($null -eq $OPT['o']) { $OPT['o'] = 'trace.svg' }
if ($OPT['changed'] -and $null -eq $OPT['compare']) { PErr 'sysml-trace-svg: --changed needs --compare'; VExit 2 }
$NAMEP = $script:NAMERX; $REFP = $script:REFRX
$script:NWARN = 0
$LABELS = @(); foreach ($l in @(Dflt $OPT['label'] @())) { $LABELS += , (SplitN $l '=' 2) }
function Shown([string]$f) { foreach ($l in $LABELS) { if ($f.StartsWith($l[0] + '/')) { return $l[1] + $f.Substring($l[0].Length + 1) } }; $f }

# ------------------------------------------------------------------ analyze one version
$TOKX = Rx ("\G(?:(\n)|//[^\n]*|doc\s*(?:<'[^']*'>\s*)?/\*(.*?)\*/|(/\*.*?\*/)|`"(?:[^`"\\]|\\.)*`"|(\{)|(\})|(;)" +
            "|(?:library\s+|standard\s+library\s+)?package\s+($NAMEP)|requirement\s+def\b" +
            "|requirement\s+(?:<'((?:[^'\\]|\\.)*)'>\s*)?($NAMEP)|verification\s+def\s+($NAMEP)" +
            "|satisfy\s+(?:requirement\s+)?($REFP)\s+by\s+($REFP)|verify\s+(?:requirement\s+)?($REFP)" +
            "|part\s+($NAMEP)\s*(?::|typed\s+by)\s*($REFP)|\w+|[^\S\n]+|.)") 's'
function PkgPath($stk, [int]$sn) { , @(for ($i = 0; $i -lt $sn; $i++) { if ($stk[$i].kind -ceq 'package') { $stk[$i].name } }) }
function Analyze([bool]$beQuiet, $files) {
    $reqs = @(); $sats = @(); $vers = @(); $usage = NewH
    foreach ($real in $files) {
        $t = VRead $real
        $f = Shown $real
        $stk = @{}; $sn = 0; $pending = $null; $line = 1
        foreach ($m in $TOKX.Matches($t)) {
            $here = $line
            if ($m.Groups[1].Success) { $line++ }
            elseif ($m.Groups[2].Success) {
                $doc = $m.Groups[2].Value; $line += NlCount $doc
                if ($sn -gt 0) {
                    $top = $stk[$sn - 1]
                    if ($top.kind -ceq 'req' -and $null -eq $top.rec.doc) { $top.rec.doc = DocBody $doc }
                }
            }
            elseif ($m.Groups[3].Success) { $line += NlCount $m.Groups[3].Value }
            elseif ($m.Groups[4].Success) { $stk[$sn] = $(if ($null -ne $pending) { $pending } else { @{ kind = 'other' } }); $sn++; $pending = $null }
            elseif ($m.Groups[5].Success) { if ($sn -gt 0) { $sn-- }; $pending = $null }
            elseif ($m.Groups[6].Success) { $pending = $null }
            elseif ($m.Groups[7].Success) { $pending = @{ kind = 'package'; name = (Unq $m.Groups[7].Value) } }
            elseif ($m.Groups[9].Success) {
                $pkgpath = PkgPath $stk $sn
                $nm = Unq $m.Groups[9].Value
                $reqpath = @(for ($i = 0; $i -lt $sn; $i++) { if ($stk[$i].kind -ceq 'req') { $stk[$i].name } })
                $r = Rec @{ id = (Dflt (G $m 8) ''); name = $nm; file = $f; line = $here; pkg = $pkgpath; path = ($reqpath + , $nm); kids = @() }
                $parent = $null; for ($i = $sn - 1; $i -ge 0; $i--) { if ($stk[$i].kind -ceq 'req') { $parent = $stk[$i]; break } }
                if ($null -ne $parent) { $r.up = $parent.rec; $parent.rec.kids = @($parent.rec.kids) + , $r }
                $reqs += , $r
                $pending = @{ kind = 'req'; name = $nm; rec = $r }
            }
            elseif ($m.Groups[10].Success) { $pkgpath = PkgPath $stk $sn; $pending = @{ kind = 'vdef'; name = (Unq $m.Groups[10].Value); pkg = $pkgpath } }
            elseif ($m.Groups[11].Success) { $pkgpath = PkgPath $stk $sn; $sats += , @{ ref = $m.Groups[11].Value; by = $m.Groups[12].Value; file = $f; line = $here; pkg = $pkgpath } }
            elseif ($m.Groups[13].Success) {
                $pkgpath = PkgPath $stk $sn
                $v = $null; for ($i = $sn - 1; $i -ge 0; $i--) { if ($stk[$i].kind -ceq 'vdef') { $v = $stk[$i]; break } }
                $vers += , @{ ref = $m.Groups[13].Value; vdef = $(if ($null -ne $v) { $v.name } else { '(anonymous)' }); file = $f; line = $here; pkg = $(if ($null -ne $v) { $v.pkg } else { $pkgpath }) }
            }
            elseif ($m.Groups[14].Success) {
                $pkgpath = PkgPath $stk $sn
                if ($sn -gt 0 -and $stk[$sn - 1].kind -ceq 'package') { $usage[($pkgpath -join '::') + "`0" + (Unq $m.Groups[14].Value)] = $m.Groups[15].Value }
            }
        }
    }
    $seen = NewH
    foreach ($r in $reqs) {
        $k = if ($r.id -ne '') { "id:$($r.id)" } else { 'path:' + (@($r.pkg) -join '::') + '::' + (@($r.path) -join '.') }
        $cnt = Dflt $seen[$k] 0; $seen[$k] = $cnt + 1
        if ($cnt) { $k += '#' + $cnt }
        $r.key = $k
        $r.show = if ($r.id -ne '') { $r.id } else { @($r.path) -join '.' }
    }
    $boxes = NewH; $edges = @()
    foreach ($x in @(@($sats | ForEach-Object { , @($_, 'satisfy') }) + @($vers | ForEach-Object { , @($_, 'verify') }))) {
        $it = $x[0]; $kind = $x[1]
        $s = Segs $it.ref
        $hit = @($reqs | Where-Object { $full = @($_.pkg) + @($_.path); $full.Count -ge $s.Count -and ((@($full[($full.Count - $s.Count)..($full.Count - 1)]) -join "`0") -ceq ($s -join "`0")) })
        if ($hit.Count -gt 1) {
            $p = @($it.pkg) -join '::'
            $near = @($hit | Where-Object { (@($_.pkg) -join '::') -ceq $p })
            if ($near.Count) { $hit = $near }
        }
        if (-not $hit.Count) { if (-not $beQuiet) { PErr "$($it.file):$($it.line): warning: $kind target '$($it.ref)' not found"; $script:NWARN++ }; continue }
        if ($hit.Count -gt 1 -and -not $beQuiet) { PErr "$($it.file):$($it.line): warning: $kind target '$($it.ref)' is ambiguous; using the first"; $script:NWARN++ }
        $r = $hit[0]
        $pk = @($it.pkg) -join '::'
        if ($kind -eq 'satisfy') {
            $b = Segs $it.by
            $type = $usage[$pk + "`0" + $b[0]]
            $label = ($b -join '.') + $(if ($null -ne $type -and $b.Count -eq 1) { " : $type" } else { '' })
            $key = "S|$pk|" + ($b -join '.')
            if ($null -eq $boxes[$key]) { $boxes[$key] = Rec @{ key = $key; side = 'S'; label = $label; pkg = $pk; file = $it.file; line = $it.line } }
            $r.sat_direct = $true
        } else {
            $key = "V|$pk|" + $it.vdef
            if ($null -eq $boxes[$key]) { $boxes[$key] = Rec @{ key = $key; side = 'V'; label = $it.vdef; pkg = $pk; file = $it.file; line = $it.line } }
            $r.ver_direct = $true
        }
        $edges += , @($key, $r)
    }
    foreach ($r in $reqs) {
        $s = $false; $v = $false
        for ($o = $r; $null -ne $o; $o = $o.up) { if (-not $s) { $s = [bool]$o.sat_direct }; if (-not $v) { $v = [bool]$o.ver_direct } }
        $r.leaf = -not @($r.kids).Count
        $r.need = $r.id -cmatch '^N-'
        $r.sat = $s; $r.ver = $v
        $r.gap = $r.leaf -and -not $r.need -and (-not $s -or -not $v)
        $r.links = NewH
    }
    foreach ($e in $edges) { $e[1].links[$e[0]] = 1 }
    @{ req = $reqs; box = $boxes; edge = @($edges | ForEach-Object { , @($_[0], $_[1].key, $_[1]) }); nfiles = @($files).Count }
}
$NEWV = Analyze $false (CollectFiles $ARGV0 'sysml-trace-svg')
$OLDV = $null; if ($null -ne $OPT['compare']) { $OLDV = Analyze $true (CollectFiles @($OPT['compare']) 'sysml-trace-svg') }

# ------------------------------------------------------------------ merge versions
function MergeSeq($new, $old) {
    $new = @($new); $old = @($old)
    $oi = NewH; for ($i = 0; $i -lt $old.Count; $i++) { if (-not $oi.ContainsKey($old[$i].key)) { $oi[$old[$i].key] = $i } }
    $nk = NewH; foreach ($n in $new) { $nk[$n.key] = 1 }
    $out = @(); $p = 0
    foreach ($n in $new) {
        if ($oi.ContainsKey($n.key)) {
            $i = $oi[$n.key]
            while ($p -lt $i) { $o = $old[$p]; $p++; if (-not $nk.ContainsKey($o.key)) { $out += , @($o, 'removed') } }
            if ($i -ge $p) { $p = $i + 1 }
            $out += , @($n, 'same')
        } else { $out += , @($n, 'added') }
    }
    while ($p -lt $old.Count) { $o = $old[$p]; $p++; if (-not $nk.ContainsKey($o.key)) { $out += , @($o, 'removed') } }
    , $out
}
function Lbl([string]$k) { (SplitN (SplitN $k '|' 2)[1] '|' 2)[1] }
$ELIST = @(); $EMAP = NewH; $CHANGES = @(); $script:NEWGAPS = 0; $script:CLOSED = 0
$OLDREQ = NewH; if ($null -ne $OLDV) { foreach ($r in @($OLDV.req)) { $OLDREQ[$r.key] = $r } }
$SEQ = if ($null -ne $OLDV) { MergeSeq $NEWV.req $OLDV.req } else { , @(@($NEWV.req) | ForEach-Object { , @($_, 'same') }) }
foreach ($mm in $SEQ) {
    $r = $mm[0]; $st = $mm[1]
    $e = Rec @{ r = $r; st = $st; why = @(); key = $r.key }
    if ($null -ne $OLDV -and $st -ceq 'same') {
        $o = $OLDREQ[$r.key]
        $e.old = $o
        $why = @()
        if ($o.name -cne $r.name) { $why += , "renamed from $($o.name)" }
        if ((Dflt $o.doc '') -cne (Dflt $r.doc '')) { $why += , 'text changed' }
        $oup = if ($null -ne $o.up) { $o.up.key } else { '' }; $rup = if ($null -ne $r.up) { $r.up.key } else { '' }
        if ($oup -cne $rup -or (@($o.pkg) -join '::') -cne (@($r.pkg) -join '::')) { $why += , ('moved from ' + $(if ($null -ne $o.up) { $o.up.show } else { 'top level' })) }
        foreach ($side in @(@('S', 'satisfied by'), @('V', 'verified by'))) {
            $add = SortStr @(@($r.links.Keys) | Where-Object { $_.StartsWith($side[0] + '|') -and -not $o.links.ContainsKey($_) } | ForEach-Object { Lbl $_ })
            $del = SortStr @(@($o.links.Keys) | Where-Object { $_.StartsWith($side[0] + '|') -and -not $r.links.ContainsKey($_) } | ForEach-Object { Lbl $_ })
            if ($add.Count -or $del.Count) { $why += , ($side[1] + ' ' + ((@($add | ForEach-Object { "+$_" }) + @($del | ForEach-Object { "-$_" })) -join ' ')) }
        }
        if ($o.gap -ne $r.gap) {
            $why += , $(if ($r.gap) { 'now a gap' } else { 'gap closed' })
            if ($r.gap) { $script:NEWGAPS++ } else { $script:CLOSED++ }
            $e.gapnew = $r.gap
        }
        $e.why = $why
        if ($why.Count) { $e.st = 'changed' }
    }
    if ($null -ne $OLDV -and $st -ceq 'added' -and $r.gap) { $script:NEWGAPS++; $e.gapnew = $true; $e.why = @($e.why) + , 'added as a gap' }
    $ELIST += , $e; $EMAP[$e.key] = $e
    if ($null -eq $OLDV -or $e.st -ceq 'same') { continue }
    $sev = if ($e.gapnew) { 'warning' } else { 'note' }
    $CHANGES += , ("$($r.file):$($r.line): ${sev}: requirement $($r.show) $($e.st)" + $(if (@($e.why).Count) { ': ' + (@($e.why) -join '; ') } else { '' }))
}
$PARENTOF = NewH; foreach ($e in $ELIST) { $PARENTOF[$e.key] = $(if ($null -ne $e.r.up) { $e.r.up.key } else { $null }) }
$BOXMAP = NewH; $EDGELIST = @()
foreach ($b in @($NEWV.box.Values)) { $BOXMAP[$b.key] = CopyRec $b @{ st = $(if ($null -ne $OLDV -and $null -eq $OLDV.box[$b.key]) { 'added' } else { 'same' }) } }
if ($null -ne $OLDV) { foreach ($b in @($OLDV.box.Values)) { if ($null -eq $BOXMAP[$b.key]) { $BOXMAP[$b.key] = CopyRec $b @{ st = 'removed' } } } }
$OLDEDGE = NewH; if ($null -ne $OLDV) { foreach ($x in @($OLDV.edge)) { $OLDEDGE[$x[0] + "`0" + $x[1]] = 1 } }
$NEWEDGE = NewH; foreach ($x in @($NEWV.edge)) { $NEWEDGE[$x[0] + "`0" + $x[1]] = 1 }
foreach ($x in @($NEWV.edge)) { $EDGELIST += , @{ b = $x[0]; r = $x[1]; st = $(if ($null -ne $OLDV -and -not $OLDEDGE.ContainsKey($x[0] + "`0" + $x[1])) { 'added' } else { 'same' }); leaf = $x[2].leaf } }
if ($null -ne $OLDV) { foreach ($x in @($OLDV.edge)) { if (-not $NEWEDGE.ContainsKey($x[0] + "`0" + $x[1])) { $EDGELIST += , @{ b = $x[0]; r = $x[1]; st = 'removed'; leaf = $x[2].leaf } } } }
foreach ($b in (SortBy @(@($BOXMAP.Values) | Where-Object { $_.st -cne 'same' }) { param($x, $y) Cmp $x.key $y.key })) {
    $CHANGES += , ("$($b.file):$($b.line): note: " + $(if ($b.side -ceq 'S') { 'satisfier' } else { 'verification case' }) + " $($b.label) $($b.st)")
}
function ChangeKey([string]$l) { $m = M $l '^(.*?):(\d+):'; if ($m.Success) { @($m.Groups[1].Value, [long]$m.Groups[2].Value) } else { @('', 0) } }
$LINES = SortBy $CHANGES { param($x, $y) $a1 = ChangeKey $x; $b1 = ChangeKey $y; $c = Cmp $a1[0] $b1[0]; if ($c) { return $c }; NCmp $a1[1] $b1[1] }

# ------------------------------------------------------------------ filter
$KEEP = NewH
foreach ($e in $ELIST) {
    $r = $e.r
    $want = $true
    if ($OPT['gaps']) { $want = $want -and $r.gap -and $e.st -cne 'removed' }
    if ($null -ne $OPT['match']) { $want = $want -and ((Rx $OPT['match']).IsMatch("$($r.id) $($r.name)")) }
    if ($null -ne $OPT['package']) { $p = @($r.pkg) -join '::'; $want = $want -and (@(@($OPT['package']) | Where-Object { $p -ceq $_ -or $p.StartsWith("$_::") }).Count -gt 0) }
    if ($OPT['changed']) { $want = $want -and ($e.st -cne 'same' -or (@($EDGELIST | Where-Object { $null -ne $BOXMAP[$_.b] -and $_.st -cne 'same' -and $_.r -ceq $e.key }).Count -gt 0)) }
    if (-not $want) { continue }
    for ($k = $e.key; $null -ne $k -and $null -ne $EMAP[$k]; $k = $PARENTOF[$k]) { $was = $KEEP.ContainsKey($k); $KEEP[$k] = 1; if ($was) { break } }
}
$SHOWN = @($ELIST | Where-Object { $KEEP.ContainsKey($_.key) })
$LEAF = @(@($NEWV.req) | Where-Object { $_.leaf })
$NGAP = @(@($NEWV.req) | Where-Object { $_.gap }).Count

# ------------------------------------------------------------------ layout
$CW = 7.2; $FS = 12; $ROWH = 22; $BOXH = 20; $GAPB = 6; $COLGAP = 150; $TOPY = 92; $PAD = 16; $DOCMAX = 70
function TW([string]$s) { $s.Length * $CW }
function Short([string]$d) { if ($d -eq '') { return '' }; if ($d.Length -gt $DOCMAX) { $d.Substring(0, $DOCMAX - 1) + $script:ELLIP } else { $d } }
$ROWS = @(); $ROWY = NewH
$y = $TOPY; $lastpkg = ''
foreach ($e in $SHOWN) {
    $r = $e.r
    $pkg = @($r.pkg) -join '::'
    if ($pkg -cne $lastpkg) { $ROWS += , @{ band = $pkg; y = $y }; $y += $ROWH + 4; $lastpkg = $pkg }
    $ROWS += , @{ e = $e; y = $y; depth = @($r.path).Count - 1 }
    $ROWY[$e.key] = $y + $ROWH / 2
    $y += $ROWH
}
$MIDH = $y
$MIDW = 360
foreach ($row in $ROWS) {
    if ($null -ne $row.band) { $w = (TW $row.band) + 24 }
    else { $r = $row.e.r; $w = 56 + $row.depth * 16 + (TW $r.id) + $(if ($r.id -ne '') { 12 } else { 0 }) + (TW $r.name) + 12 + (TW (Short (Dflt $r.doc ''))) }
    if ($w -gt $MIDW) { $MIDW = $w }
}
function PlaceBoxes($bs) {
    foreach ($b in @($bs)) {
        $ys = @($EDGELIST | Where-Object { $_.b -ceq $b.key -and $ROWY.ContainsKey($_.r) } | ForEach-Object { $ROWY[$_.r] })
        $sum = 0; foreach ($v in $ys) { $sum += $v }
        $b.want = if ($ys.Count) { $sum / $ys.Count } else { $null }
    }
    $sorted = SortBy @(@($bs) | Where-Object { $null -ne $_.want }) { param($x, $y) $c = NCmp $x.want $y.want; if ($c) { return $c }; Cmp $x.label $y.label }
    $next = $TOPY
    foreach ($b in $sorted) {
        $top = $b.want - $BOXH / 2
        if ($top -lt $next) { $top = $next }
        $b.y = $top; $next = $top + $BOXH + $GAPB
    }
    , $sorted
}
$SBOX = PlaceBoxes (SortBy @(@($BOXMAP.Values) | Where-Object { $_.side -ceq 'S' }) { param($x, $y) Cmp $x.label $y.label })
$VBOX = PlaceBoxes (SortBy @(@($BOXMAP.Values) | Where-Object { $_.side -ceq 'V' }) { param($x, $y) Cmp $x.label $y.label })
$bn = 0; foreach ($b in @($SBOX) + @($VBOX)) { $bn++; $b.n = $bn }
$en = 0; foreach ($e in $ELIST) { $en++; $e.n = $en }
$SW = MaxNum (@(180) + @($SBOX | ForEach-Object { (TW $_.label) + 20 }))
$VW = MaxNum (@(180) + @($VBOX | ForEach-Object { (TW $_.label) + 20 }))
$XS = $PAD; $XM = $PAD + $SW + $COLGAP
$XV = $XM + $MIDW + $COLGAP
$SVGW = $XV + $VW + $PAD
$SVGH = MaxNum (@($MIDH) + @(@($SBOX) + @($VBOX) | ForEach-Object { $_.y + $BOXH }))
$SVGH += 40

# ------------------------------------------------------------------ draw
$CLR = NewH
foreach ($kv in @(@('ok', '#2e7d32'), @('bad', '#c62828'), @('na', '#d6d6d6'), @('grp', '#78909c'), @('edge', '#90a4ae'), @('band', '#eceff1'),
                  @('gapbg', '#ffebee'), @('ink', '#212121'), @('dim', '#616161'), @('sbox', '#e3f2fd'), @('sline', '#1565c0'), @('vbox', '#f3e5f5'),
                  @('vline', '#6a1b9a'), @('added', '#2e7d32'), @('changed', '#ef6c00'), @('removed', '#c62828'), @('addedbg', '#e8f5e9'),
                  @('changedbg', '#fff3e0'), @('removedbg', '#f5f5f5'))) { $CLR[$kv[0]] = $kv[1] }
$SVGL = @{}; $script:ON = 0
function O([string]$s) { $SVGL[$script:ON] = $s; $script:ON++ }
O '<?xml version="1.0" encoding="UTF-8"?>'
O ('<svg xmlns="http://www.w3.org/2000/svg" width="' + (N $SVGW) + '" height="' + (N $SVGH) + '" viewBox="0 0 ' + (N $SVGW) + ' ' + (N $SVGH) + '" font-family="DejaVu Sans Mono, Consolas, Menlo, monospace" font-size="' + $FS + '">')
$gen = ($ARGV0 -join ' ') + $(if ($null -ne $OPT['compare']) { ', compared with ' + (@($OPT['compare']) -join ' ') } else { '' })
O ('<!-- generated by sysml-trace-svg.pl from ' + (GSub (Esc $gen) '-(?=-)' '- ') + ' -->')
O '<style>.e{transition:stroke .1s} .hl{stroke:#e65100 !important;stroke-width:2.6px !important} .dim{opacity:.15} [data-k]{cursor:pointer} .gone{opacity:.6} .gone text{text-decoration:line-through}</style>'
O ("<script><![CDATA[`nwindow.addEventListener('load', function () {`n  var edges = document.querySelectorAll('.e');`n  function on(k, yes) {`n    edges.forEach(function (e) {`n" +
   "      var hit = (' ' + e.getAttribute('data-ends') + ' ').indexOf(' ' + k + ' ') >= 0;`n      e.classList.toggle('hl', yes && hit); e.classList.toggle('dim', yes && !hit);`n    });`n  }`n" +
   "  document.querySelectorAll('[data-k]').forEach(function (g) {`n    g.addEventListener('mouseenter', function () { on(g.getAttribute('data-k'), true) });`n" +
   "    g.addEventListener('mouseleave', function () { on(g.getAttribute('data-k'), false) });`n  });`n});`n]]></script>")
O '<rect width="100%" height="100%" fill="#ffffff"/>'
$title = if ($null -ne $OPT['title']) { $OPT['title'] } elseif ($null -ne $OLDV) { 'Requirement trace changes' } else { 'Requirement trace' }
$sum = '{0} leaf requirement(s), {1} with gaps; {2} satisfy, {3} verify' -f $LEAF.Count, $NGAP, @($EDGELIST | Where-Object { $_.b.StartsWith('S') -and $_.st -cne 'removed' }).Count, @($EDGELIST | Where-Object { $_.b.StartsWith('V') -and $_.st -cne 'removed' }).Count
$dsum = ''
if ($null -ne $OLDV) {
    $nn = NewH; foreach ($e in $ELIST) { $nn[$e.st] = 1 + (Dflt $nn[$e.st] 0) }
    $ll = NewH; foreach ($x in $EDGELIST) { $ll[$x.st] = 1 + (Dflt $ll[$x.st] 0) }
    $dsum = 'requirements +{0} -{1} ~{2}; links +{3} -{4}; {5} new gap(s), {6} closed' -f (Dflt $nn['added'] 0), (Dflt $nn['removed'] 0), (Dflt $nn['changed'] 0), (Dflt $ll['added'] 0), (Dflt $ll['removed'] 0), $script:NEWGAPS, $script:CLOSED
}
$filt = $(if ($OPT['gaps']) { '; gaps only' } else { '' }) + $(if ($null -ne $OPT['match']) { "; filter /$($OPT['match'])/" } else { '' }) + $(if ($OPT['changed']) { '; changes only' } else { '' })
O ('<text x="' + $PAD + '" y="26" font-size="16" font-weight="bold" fill="' + $CLR.ink + '">' + (Esc $title) + '</text>')
O ('<text x="' + $PAD + '" y="46" fill="' + $CLR.dim + '">' + (Esc ($sum + $filt)) + '</text>')
if ($null -ne $OLDV) { O ('<text x="' + $PAD + '" y="64" fill="' + $CLR.ink + '">' + (Esc $dsum) + '</text>') }
foreach ($hd in @(@($XS, 'satisfied by'), @(($XM + 9), 'S'), @(($XM + 25), 'V'), @(($XM + 48), 'requirements'), @($XV, 'verified by'))) {
    O ('<text x="' + (N $hd[0]) + '" y="84" font-weight="bold" fill="' + $CLR.dim + '">' + $hd[1] + '</text>')
}
$lx = $XM + 48
foreach ($s in @(($sum + $filt), $dsum)) { if ($lx -lt $PAD + (TW $s) + 64) { $lx = $PAD + (TW $s) + 64 } }
function Badge($x, $y, [string]$k) {
    if (-not $OPT['mono']) { return '<rect x="' + (N $x) + '" y="' + (N $y) + '" width="12" height="12" rx="2" fill="' + $CLR[$k] + '"/>' }
    $r = '<rect x="' + (N $x) + '" y="' + (N $y) + '" width="12" height="12" rx="2" fill="' + $(if ($k -ceq 'ok') { '#000000' } else { '#ffffff' }) + '" stroke="#000000" stroke-width="1"/>'
    if ($k -ceq 'bad') { $r += '<path d="M' + (D $x) + ' ' + (D $y) + ' l12 12 M' + (D ($x + 12)) + ' ' + (D $y) + ' l-12 12" stroke="#000000" stroke-width="1.6"/>' }
    if ($k -ceq 'grp') { $r += '<path d="M' + (D $x) + ' ' + (D ($y + 12)) + ' l12 -12 v12 z" fill="#000000"/>' }
    $r
}
function Curve($x1, $y1, $x2, $y2, [string]$dash, [string]$ends, [string]$col, $w) {
    $mx = ($x1 + $x2) / 2
    $d = if ($dash) { " stroke-dasharray=`"$dash`"" } else { '' }
    '<path class="e" data-ends="' + $ends + '" d="M' + (F $x1 1) + ' ' + (F $y1 1) + ' C' + (F $mx 1) + ' ' + (F $y1 1) + ' ' + (F $mx 1) + ' ' + (F $y2 1) + ' ' + (F $x2 1) + ' ' + (F $y2 1) + '" fill="none" stroke="' + $col + '" stroke-width="' + (N $w) + '"' + $d + '/>'
}
O ('<g transform="translate(' + (N $lx) + ',16)" font-size="11" fill="' + $CLR.dim + '">')
O ((Badge 0 0 'ok') + '<text x="16" y="10">covered</text>')
O ((Badge 84 0 'bad') + '<text x="100" y="10">gap</text>')
O ((Badge 140 0 'grp') + '<text x="156" y="10">via a group</text>')
O ((Badge 252 0 'na') + '<text x="268" y="10">not judged (group, need)</text>')
O ('<line x1="0" y1="27" x2="24" y2="27" stroke="' + $CLR.edge + '" stroke-width="1.5"/><text x="30" y="31">to a leaf</text>')
O ('<line x1="110" y1="27" x2="134" y2="27" stroke="' + $CLR.edge + '" stroke-width="1.5" stroke-dasharray="4 3"/><text x="140" y="31">to a group</text>')
if ($null -ne $OLDV) {
    O ('<rect x="252" y="21" width="5" height="12" fill="' + $CLR.added + '"/><text x="262" y="31">added</text>')
    O ('<rect x="314" y="21" width="5" height="12" fill="' + $CLR.changed + '"/><text x="324" y="31">changed</text>')
    O ('<rect x="390" y="21" width="5" height="12" fill="' + $CLR.removed + '"/><text x="400" y="31" text-decoration="line-through">removed</text>')
}
O '</g>'
# edges first, under everything
foreach ($x in (SortBy $EDGELIST { param($p, $q) NCmp ([int]($p.st -cne 'same')) ([int]($q.st -cne 'same')) })) {
    $b = $BOXMAP[$x.b]; $e = $EMAP[$x.r]
    if ($null -eq $b -or $null -eq $b.y -or $null -eq $e -or -not $ROWY.ContainsKey($x.r)) { continue }
    $col = $CLR.edge; $w = 1.3; $dash = if ($x.leaf) { '' } else { '4 3' }
    if ($x.st -ceq 'added') { $col = $CLR.added; $w = 2 }
    if ($x.st -ceq 'removed') { $col = $CLR.removed; $w = 1.6; $dash = '3 3' }
    $ends = "r$($e.n) b$($b.n)"
    if ($b.side -ceq 'S') { O (Curve ($XS + $SW) ($b.y + $BOXH / 2) ($XM - 4) $ROWY[$x.r] $dash $ends $col $w) }
    else { O (Curve ($XM + $MIDW + 4) $ROWY[$x.r] $XV ($b.y + $BOXH / 2) $dash $ends $col $w) }
}
foreach ($row in $ROWS) {
    if ($null -ne $row.band) {
        O ('<rect x="' + (N $XM) + '" y="' + (N $row.y) + '" width="' + (N $MIDW) + '" height="' + $ROWH + '" fill="' + $CLR.band + '"/>')
        O ('<text x="' + (N ($XM + 8)) + '" y="' + (N ($row.y + 15)) + '" font-weight="bold" fill="' + $CLR.ink + '">' + (Esc $row.band) + '</text>')
        continue
    }
    $e = $row.e; $r = $e.r; $ry = $row.y
    $gone = $e.st -ceq 'removed'
    $tip = @("$($r.id) $($r.name)", (Dflt $r.doc ''))
    if ($r.need) { $tip += , 'need: traced by derivation, not judged' }
    elseif ($r.leaf) { $tip += , ('satisfied: ' + $(if ($r.sat) { 'yes' } else { 'NO' })); $tip += , ('verified: ' + $(if ($r.ver) { 'yes' } else { 'NO' })) }
    else { $tip += , 'group: judged by its leaves' }
    if ($e.st -cne 'same') { $tip += , ($e.st.ToUpper() + $(if (@($e.why).Count) { ': ' + (@($e.why) -join '; ') } else { '' })) }
    $tip += , ($(if ($gone) { 'was at ' } else { '' }) + "$($r.file):$($r.line)")
    O ('<g data-k="r' + $e.n + '"' + $(if ($gone) { ' class="gone"' } else { '' }) + '><title>' + (Esc ((@($tip | Where-Object { $_ -ne '' })) -join "`n")) + '</title>')
    if ($r.gap -and -not $gone) { O ('<rect x="' + (N $XM) + '" y="' + (N $ry) + '" width="' + (N $MIDW) + '" height="' + $ROWH + '" fill="' + $CLR.gapbg + '"/>') }
    if ($e.st -cne 'same' -and (-not $r.gap -or $gone)) { O ('<rect x="' + (N $XM) + '" y="' + (N $ry) + '" width="' + (N $MIDW) + '" height="' + $ROWH + '" fill="' + $CLR[($e.st + 'bg')] + '"/>') }
    if ($e.st -cne 'same') { O ('<rect x="' + (N $XM) + '" y="' + (N $ry) + '" width="4" height="' + $ROWH + '" fill="' + $CLR[$e.st] + '"/>') }
    $bx = $XM + 8
    foreach ($k in @('sat', 'ver')) {
        $direct = $r[$k + '_direct']
        $state = if ($r.need -or -not $r.leaf) { $(if ($direct) { 'ok' } else { 'na' }) } elseif (-not $r[$k]) { 'bad' } elseif ($direct) { 'ok' } else { 'grp' }
        if ($r.need) { $state = 'na' }
        O (Badge $bx ($ry + 5) $state)
        $bx += 16
    }
    $tx = $XM + 48 + $row.depth * 16
    $ty = $ry + 15
    if ($r.id -ne '') { O ('<text x="' + (N $tx) + '" y="' + (N $ty) + '" fill="' + $CLR.dim + '">' + (Esc $r.id) + '</text>'); $tx += (TW $r.id) + 12 }
    $col = if ($gone) { $CLR.dim } elseif ($r.gap) { $CLR.bad } else { $CLR.ink }
    O ('<text x="' + (N $tx) + '" y="' + (N $ty) + '" font-weight="' + $(if ($r.leaf) { 'normal' } else { 'bold' }) + '" fill="' + $col + '">' + (Esc $r.name) + '</text>')
    $tx += (TW $r.name) + 12
    if ($null -ne $r.doc) { O ('<text x="' + (N $tx) + '" y="' + (N $ty) + '" fill="' + $CLR.dim + '" font-style="italic">' + (Esc (Short $r.doc)) + '</text>') }
    O '</g>'
}
foreach ($colspec in @(@($SBOX, $XS, $SW, 'sbox', 'sline'), @($VBOX, $XV, $VW, 'vbox', 'vline'))) {
    $boxes = $colspec[0]; $x = $colspec[1]; $w = $colspec[2]; $fillk = $colspec[3]; $linek = $colspec[4]
    foreach ($b in @($boxes)) {
        $links = @(foreach ($ed in $EDGELIST) {
            if ($ed.b -cne $b.key) { continue }
            $rr = if ($null -ne $EMAP[$ed.r]) { $EMAP[$ed.r].r } else { $null }
            if ($null -ne $rr) { $(if ($rr.id -ne '') { "$($rr.id) " } else { '' }) + (@($rr.path) -join '.') + $(if ($ed.st -cne 'same') { " ($($ed.st))" } else { '' }) }
        })
        $tip = @($b.label, "package $($b.pkg)") + $links
        if ($b.st -cne 'same') { $tip += , $b.st.ToUpper() }
        $tip += , ($(if ($b.st -ceq 'removed') { 'was at ' } else { '' }) + "$($b.file):$($b.line)")
        $fl = $CLR[$fillk]; $sk = $CLR[$linek]; $sw2 = 1; $dash = ''
        if ($b.st -ceq 'added') { $sk = $CLR.added; $sw2 = 2.2 }
        if ($b.st -ceq 'removed') { $fl = $CLR.removedbg; $sk = $CLR.removed; $dash = ' stroke-dasharray="4 3"' }
        O ('<g data-k="b' + $b.n + '"' + $(if ($b.st -ceq 'removed') { ' class="gone"' } else { '' }) + '><title>' + (Esc ($tip -join "`n")) + '</title>')
        O ('<rect x="' + (N $x) + '" y="' + (N $b.y) + '" width="' + (N $w) + '" height="' + $BOXH + '" rx="4" fill="' + $fl + '" stroke="' + $sk + '" stroke-width="' + (N $sw2) + '"' + $dash + '/>')
        O ('<text x="' + (N ($x + 10)) + '" y="' + (N ($b.y + 14)) + '" fill="' + $CLR.ink + '">' + (Esc $b.label) + '</text></g>')
    }
}
O '</svg>'
$svg = (@(for ($i = 0; $i -lt $script:ON; $i++) { $SVGL[$i] + "`n" })) -join ''
if (-not (VWrite $OPT['o'] $svg)) { PErr "$($OPT['o']): cannot write"; VExit 2 }
foreach ($l in $LINES) { PL $l }
PL ('trace-svg: {0} file(s), {1} leaf requirement(s), {2} with gaps, {3} warning(s){4} -> {5}' -f $NEWV.nfiles, $LEAF.Count, $NGAP, $script:NWARN, $(if ($null -ne $OLDV) { "; $dsum" } else { '' }), $OPT['o'])
VExit 0
