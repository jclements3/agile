<#
sysml-plates.ps1 : drawing plates (sheets) from the views declared in a SysML v2 model: ISO 5457 sheet, frame,
centring marks and grid reference, ISO 7200 title block.
PowerShell port of tools/sysml/views/sysml-plates.pl (Constrained Language Mode safe, pure ASCII).

  sysml-plates.ps1 [-o DIR] [--size auto|A4|A3|A2|A1|A0] [--auto] [--color] [--owner TEXT] [--creator TEXT]
                   [--approver TEXT] [--status TEXT] [--rev R] [--date YYYY-MM-DD] [--prefix DWG] [--min-text MM]
                   [--source TEXT] DIR|FILE...

Same options, sheets, plates.html and exit status as the Perl. The Source field shows `git describe` only where a
git command exists (the baseline PC has none: it shows the file count, or --source TEXT).
#>
. (Join-Path $PSScriptRoot 'views-lib.ps1')
VBufferStderr
$go = GetOpts $args @('o=s', 'size=s', 'auto', 'color', 'owner=s', 'creator=s', 'approver=s', 'status=s', 'rev=s', 'date=s', 'prefix=s', 'min-text=f', 'source=s')
if (-not $go.ok -or -not @($go.rest).Count) { PErr 'usage: perl sysml-plates.pl [-o DIR] [--size auto|A4|A3|A2|A1|A0] [--auto] [--color] [--owner T] [--creator T] [--approver T] [--status T] [--rev R] [--date YYYY-MM-DD] [--prefix DWG] [--min-text MM] DIR|FILE...'; VExit 2 }
$OPT = $go.opts; $ARGV0 = @($go.rest)
foreach ($kv in @(@('o', 'plates'), @('size', 'auto'), @('min-text', 2.0), @('prefix', 'DWG'), @('status', 'In preparation'), @('rev', '-'))) { if ($null -eq $OPT[$kv[0]]) { $OPT[$kv[0]] = $kv[1] } }
$SHEET = NewH
foreach ($kv in @(@('A4', 297, 210, 6, 4), @('A3', 420, 297, 8, 6), @('A2', 594, 420, 12, 8), @('A1', 841, 594, 16, 12), @('A0', 1189, 841, 24, 16))) { $SHEET[$kv[0]] = @($kv[1], $kv[2], $kv[3], $kv[4]) }
if ($OPT['size'] -cne 'auto' -and $null -eq $SHEET[$OPT['size'].ToUpper()]) { PErr 'sysml-plates: --size must be auto, A4, A3, A2, A1 or A0'; VExit 2 }
$DATE = if ($null -ne $OPT['date']) { $OPT['date'] } else { TodayStr }
$FILES = @()
foreach ($a in $ARGV0) {
    if (IsDir $a) { $FILES += @(FindSysml $a) }
    elseif (IsFile $a) { $FILES += , $a }
    else { PErr "sysml-plates: ${a}: no such file or directory"; VExit 2 }
}
$FILES = SortStr $FILES
$script:NWARN = 0
function WarnMsg($f, $l, [string]$m) { PErr ("{0}:{1}: warning: {2}" -f $f, (N $l), $m); $script:NWARN++ }
$NAMEP = $script:NAMERX; $REFP = $script:REFRX

# ------------------------------------------------------------------ parse
$ELIST = @(); $PKGMAP = NewH; $LEVELLIST = @(); $SRCLINES = NewH
function Finish($s) {
    if ($s.kind -cne 'meta') { return }
    $tg = $s.target; if ($null -eq $tg) { return }
    $tg.meta = @($tg.meta) + , $s.name
    $cp = NewH; foreach ($k in $s.attrs.Keys) { $cp[$k] = $s.attrs[$k] }
    $tg.attrs[$s.name] = $cp
    if ($s.name -ceq 'Marking' -and $null -ne $s.attrs['level']) { $tg.marking = $s.attrs['level'] }
}
function Statement([string]$s, [string]$f, [int]$line, $stack, [int]$sn, [string]$c) {
    $top = $stack[$sn - 1]
    $s = Squash $s
    if ($s -eq '') { return $null }
    $pkg = $top.pkg
    $owner = $null; for ($i = $sn - 1; $i -ge 0; $i--) { if ($null -ne $stack[$i].node) { $owner = $stack[$i].node; break } }
    $pk = $null; for ($i = $sn - 1; $i -ge 0; $i--) { if ($null -ne $stack[$i].pk) { $pk = $stack[$i].pk; break } }
    if ($top.kind -ceq 'meta') {
        $m = M $s '^(?::>>\s*)?(\w+)\s*=\s*("(?:[^"\\]|\\.)*"|\S+)'
        if ($m.Success) {
            $k = $m.Groups[1].Value; $v = $m.Groups[2].Value
            $m2 = M $v '^"(.*)"$' 's'; if ($m2.Success) { $v = $m2.Groups[1].Value }
            $v = Sub $v '^(?:\w+::)+' ''
            $top.attrs[$k] = $v
        }
        return $null
    }
    if ($top.kind -ceq 'levels') {
        $m = M $s "^(?:enum\s+)?($NAMEP)$"
        if ($m.Success) { $lv = Unq $m.Groups[1].Value; if (@($script:LEVELLIST | Where-Object { $_ -ceq $lv }).Count -eq 0) { $script:LEVELLIST += , $lv } }
        return $null
    }
    $m = M $s '^@\s*(?:\w+::)*(\w+)\s*$'; if (-not $m.Success) { $m = M $s '^metadata\s+(?:\w+::)*(\w+)\s*$' }
    if ($m.Success) { return (Rec @{ kind = 'meta'; name = $m.Groups[1].Value; target = $(if ($null -ne $owner) { $owner } else { $pk }); attrs = (NewH); pkg = $pkg }) }
    $s = Sub $s '^(?:(?:public|private|protected|abstract|variation|individual|derived|readonly)\s+)*' ''
    $hash = @()
    while ($true) { $m = M $s '^#\s*(?:\w+::)*(\w+)\s*'; if (-not $m.Success) { break }; $hash += , $m.Groups[1].Value; $s = $s.Substring($m.Length) }
    $m = M $s "^(?:standard\s+)?(?:library\s+)?package\s+($NAMEP)"
    if ($m.Success) {
        $pp = @($pkg) + , (Unq $m.Groups[1].Value); $q = $pp -join '::'
        if ($null -eq $PKGMAP[$q]) { $PKGMAP[$q] = Rec @{ name = (Unq $m.Groups[1].Value); qname = $q; path = $pp; parent = $pk; file = $f; line = $line; meta = @(); attrs = (NewH) } }
        return (Rec @{ kind = 'package'; pkg = $pp; pk = $PKGMAP[$q] })
    }
    if (T $s '^enum\s+def\s+Level\b') { return (Rec @{ kind = 'levels'; pkg = $pkg }) }
    if ($null -ne $owner -and (T $s '^(connect|connection|interface|flow)\b(?!\s+def\b)')) { $d = $owner; while ($null -ne $d -and -not $d.isdef) { $d = $d.owner }; if ($null -ne $d) { $d.hasconn = $true }; return $null }
    if ($null -ne $owner -and $owner.kind -ceq 'view') {
        $m = M $s "^expose\s+($REFP)\s*(::\s*\*\*|::\s*\*)?"
        if ($m.Success) { $st = Dflt (G $m 2) ''; $owner.expose = @($owner.expose) + , @{ segs = (Segs $m.Groups[1].Value); star = $(if ($st.Contains('**')) { '**' } elseif ($st) { '*' } else { '' }) }; return $null }
        $m = M $s '^render\s+(?:\w+::)*(\w+)'
        if ($m.Success) { $owner.render = $m.Groups[1].Value; return $null }
        $m = M $s '^filter\s+(.*)$'
        if ($m.Success) { $owner.filter = @($owner.filter) + , $m.Groups[1].Value; return $null }
    }
    $m = M $s "^(\w+(?:\s+def)?)\s+(?:<'((?:[^'\\]|\\.)*)'>\s*)?($NAMEP)(.*)$"
    if ($m.Success -and $m.Groups[1].Value -cnotmatch '^(?:import|alias|dependency|doc|comment|subject|objective|return|in|out|inout|expose|render|filter|satisfy|verify|ref|end|bind|succession|first|then|send|accept|assign|assert|require|assume|frame)$') {
        $kw = $m.Groups[1].Value; $id = Dflt (G $m 2) ''; $n = Unq $m.Groups[3].Value; $rest = $m.Groups[4].Value
        $isdef = T $kw '\sdef$'
        $k = Sub $kw '\s+def$' ''
        $depth = 0; for ($i = 0; $i -lt $sn; $i++) { if ($null -ne $stack[$i].node) { $depth++ } }
        $e = Rec @{ kind = $k; isdef = $isdef; name = $n; id = $id; pkg = $pkg; pk = $pk; owner = $owner; file = $f; line = $line; meta = $hash; attrs = (NewH); depth = $depth }
        $m2 = M $rest "^\s*(?::|defined\s+by)\s*($REFP)"
        if ($m2.Success) { $e.type = (Segs $m2.Groups[1].Value)[-1]; $e.typesegs = Segs $m2.Groups[1].Value }
        $script:ELIST += , $e
        if ($c -eq '{') { return (Rec @{ kind = 'node'; node = $e; pkg = $pkg }) }
        return $null
    }
    $null
}
$TOK = Rx '\G(?:(\n)|(//[^\n]*)|(/\*)|("(?:[^"\\]|\\.)*"|''(?:[^''\\]|\\.)*'')|([{};])|([^{};"''/\n]+|/))'
foreach ($f in $FILES) {
    $t = VRead $f
    $SRCLINES[$f] = [regex]::Split($t, "`n")
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
                $nd = if ($null -ne $stack[$sn - 1].node) { $stack[$sn - 1].node } else { $stack[$sn - 1].pk }
                if ($null -ne $nd -and $null -eq $nd.doc) { $nd.doc = $body }
                $head = ''
            } elseif (T $head '^\s*comment\b') { $head = '' }
        }
        elseif ($m.Groups[4].Success) { $q = $m.Groups[4].Value; if (-not (T $head '\S')) { $hline = $line }; $head += $q; $line += NlCount $q }
        elseif ($m.Groups[5].Success) {
            $c = $m.Groups[5].Value
            if ($c -eq '}') {
                if ($sn -gt 1) { $sn--; $s0 = $stack[$sn]; if ($null -ne $s0.node) { $s0.node.endline = $line }; Finish $s0 }
                $head = ''; continue
            }
            $st = Statement $head $f $hline $stack $sn $c
            $head = ''
            if ($c -eq '{') { if ($null -eq $st) { $st = Rec @{ kind = 'other'; pkg = $stack[$sn - 1].pkg } }; $stack[$sn] = $st; $sn++ }
            elseif ($null -ne $st -and $st.kind -ceq 'meta') { Finish $st }
        }
        else { $x = $m.Groups[6].Value; if (-not (T $head '\S') -and (T $x '\S')) { $hline = $line }; $head += $x }
    }
}
if (-not $LEVELLIST.Count) { $LEVELLIST = @('U', 'CUI', 'ITAR') }
$RANK = NewH; for ($i = 0; $i -lt $LEVELLIST.Count; $i++) { $RANK[$LEVELLIST[$i]] = $i }
function PkgRank($p) { $r = -1; for ($o = $p; $null -ne $o; $o = $o.parent) { $mk = $o.marking; if ($null -ne $mk -and $RANK.ContainsKey($mk) -and $RANK[$mk] -gt $r) { $r = $RANK[$mk] } }; $r }
function ElemRank($e) {
    $r = if ($null -ne $e.pk) { PkgRank $e.pk } else { -1 }
    for ($o = $e; $null -ne $o; $o = $o.owner) { $mk = $o.marking; if ($null -ne $mk -and $RANK.ContainsKey($mk) -and $RANK[$mk] -gt $r) { $r = $RANK[$mk] } }
    $r
}
function Qn($e) { $n = @($e.name); for ($o = $e.owner; $null -ne $o; $o = $o.owner) { $n = @($o.name) + $n }; (@($e.pkg) + $n) -join '::' }

# ------------------------------------------------------------------ plates: from views, or automatic
$VIEWS = @($ELIST | Where-Object { $_.kind -ceq 'view' -and -not $_.isdef })
$VDEFS = NewH; foreach ($v in @($ELIST | Where-Object { $_.kind -ceq 'view' -and $_.isdef })) { $VDEFS[$v.name] = $v }
function ResolveExpose($x) {
    $q = @($x.segs) -join '::'
    $hit = @(); if ($null -ne $PKGMAP[$q]) { $hit = @($PKGMAP[$q]) }
    if (-not $hit.Count) {
        $cands = @(@($PKGMAP.Values) + $ELIST | Where-Object { $nm = if ($null -ne $_.qname) { $_.qname } else { Qn $_ }; $nm -ceq $q -or $nm.EndsWith("::$q") })
        $hit = SortBy $cands { param($a1, $b1) Cmp $(if ($null -ne $a1.qname) { $a1.qname } else { Qn $a1 }) $(if ($null -ne $b1.qname) { $b1.qname } else { Qn $b1 }) }
        if ($hit.Count) { $hit = @($hit[0]) }
    }
    if (-not $hit.Count) { return , @() }
    $t = $hit[0]
    if (-not $x.star) { return , @($t) }
    if ($null -ne $t.qname -and $null -ne $PKGMAP[$t.qname]) {
        $p = $t.qname
        return , @($ELIST | Where-Object { $ep = @($_.pkg) -join '::'; ($ep -ceq $p -or ($x.star -ceq '**' -and $ep.StartsWith("$p::"))) -and ($x.star -ceq '**' -or $null -eq $_.owner) })
    }
    , @($ELIST | Where-Object { $o = $_.owner; $in = $false; while ($null -ne $o) { if ($o -eq $t) { $in = $true; break }; $o = $o.owner }; $in -and ($x.star -ceq '**' -or $_.owner -eq $t) })
}
$SYSKIND = NewH
foreach ($kv in @(@('PartUsage', 'part', $false), @('PartDefinition', 'part', $true), @('RequirementUsage', 'requirement', $false), @('RequirementDefinition', 'requirement', $true),
                  @('ActionUsage', 'action', $false), @('ActionDefinition', 'action', $true), @('PortUsage', 'port', $false), @('PortDefinition', 'port', $true),
                  @('InterfaceUsage', 'interface', $false), @('AttributeUsage', 'attribute', $false), @('ItemUsage', 'item', $false), @('ConstraintUsage', 'constraint', $false),
                  @('VerificationCaseDefinition', 'verification', $true), @('StateUsage', 'state', $false), @('OccurrenceDefinition', 'occurrence', $true))) { $SYSKIND[$kv[0]] = @($kv[1], $kv[2]) }
function PassFilter($e, $filters) {
    foreach ($fl in @($filters)) {
        $ok = $false
        foreach ($m in (MS $fl '@\s*((?:\w+::)*)(\w+)')) {
            $ns = $m.Groups[1].Value; $n = $m.Groups[2].Value
            if ($ns -cmatch 'SysML::' -and $null -ne $SYSKIND[$n]) { if ($e.kind -ceq $SYSKIND[$n][0] -and [bool]$e.isdef -eq $SYSKIND[$n][1]) { $ok = $true } }
            elseif (@(@($e.meta) | Where-Object { $_ -ceq $n }).Count) { $ok = $true }
        }
        if (-not $ok) { return $false }
    }
    $true
}
$PLATES = @()
if ($VIEWS.Count -and -not $OPT['auto']) {
    foreach ($v in $VIEWS) {
        $vd = if ($null -ne $v.type) { $VDEFS[$v.type] } else { $null }
        $filters = @($v.filter) + $(if ($null -ne $vd) { @($vd.filter) } else { @() }) | Where-Object { $null -ne $_ }
        $filters = @($filters)
        $render = Dflt $v.render $(if ($null -ne $vd) { $vd.render } else { $null }); if ($null -eq $render) { $render = '' }
        $vdn = Dflt $v.type ''
        $ex = @(); foreach ($x in @($v.expose)) { if ($null -eq $x) { continue }; $ex += (ResolveExpose $x) }
        foreach ($x in @($v.expose)) { if ($null -eq $x) { continue }; if (-not (ResolveExpose $x).Count) { WarnMsg $v.file $v.line ("view '$($v.name)': expose '" + (@($x.segs) -join '::') + "' matches nothing") } }
        $pkd = @($ex | Where-Object { $null -ne $_.qname })
        $el = @($ex | Where-Object { $null -eq $_.qname })
        $sel = if ($filters.Count) { @($el | Where-Object { PassFilter $_ $filters }) } else { $el }
        $sel = @($sel)
        $isreq = @($filters | Where-Object { $_ -cmatch 'RequirementUsage|RequirementDefinition' }).Count -gt 0
        $base = @{ view = $v; filters = $filters; render = $render; vdef = $vdn }
        $pk = NewH; foreach ($e in $el) { $pk[(@($e.pkg) -join '::')] = 1 }; foreach ($p in $pkd) { $pk[(@($p.path) -join '::')] = 1 }
        $pkgs = SortStr @($pk.Keys)
        if ($vdn -match 'Package') { $PLATES += , (CopyRec $base @{ kind = 'pkg' }) }
        elseif ($render -ceq 'asTextualNotation') {
            $inn = @{}; foreach ($e in $sel) { $inn[(Id $e)] = 1 }
            $top = @($sel | Where-Object { $o = $_.owner; $nested = $false; while ($null -ne $o) { if ($inn.ContainsKey((Id $o))) { $nested = $true; break }; $o = $o.owner }; -not $nested })
            $PLATES += , (CopyRec $base @{ kind = 'text'; elements = $top })
        }
        elseif ($render -ceq 'asElementTable') { $PLATES += , (CopyRec $base @{ kind = $(if ($isreq) { 'trace' } else { 'table' }); elements = $sel; packages = $pkgs }) }
        elseif ($render -ceq 'asInterconnectionDiagram' -or $vdn -cmatch 'Interconnection') {
            $r = @($el | Where-Object { $_.kind -ceq 'part' -and $_.isdef -and $_.hasconn })
            if (-not $r.Count) { $r = @($el | Where-Object { $_.kind -ceq 'part' -and $_.isdef }) }
            if ($r.Count) { $PLATES += , (CopyRec $base @{ kind = 'ibd'; roots = $r }) }
            else { WarnMsg $v.file $v.line "view '$($v.name)': nothing to draw as an interconnection diagram" }
        }
        elseif ($isreq) { $PLATES += , (CopyRec $base @{ kind = 'trace'; packages = $pkgs }) }
        elseif ($render -ceq 'asTreeDiagram' -or $render -ceq '' -or $vdn -cmatch 'General|Decomposition|Browser') {
            $defs = @($el | Where-Object { $_.kind -ceq 'part' -and $_.isdef })
            $used = NewH
            foreach ($u in @($ELIST | Where-Object { $_.kind -ceq 'part' -and -not $_.isdef -and $null -ne $_.type })) {
                $ow = $u.owner
                if ($null -ne $ow -and @($defs | Where-Object { $_ -eq $ow }).Count) { $used[$u.type] = 1 + (Dflt $used[$u.type] 0) }
            }
            $r = @($defs | Where-Object { -not $used.ContainsKey($_.name) }); if (-not $r.Count) { $r = $defs }
            if ($r.Count) { $PLATES += , (CopyRec $base @{ kind = 'tree'; roots = $r }) }
            elseif ($sel.Count) { $PLATES += , (CopyRec $base @{ kind = 'table'; elements = $sel }) }
            else { WarnMsg $v.file $v.line "view '$($v.name)': nothing to draw" }
        }
        else { WarnMsg $v.file $v.line "view '$($v.name)': render $render is not supported; skipped" }
    }
} else {
    $defs = @($ELIST | Where-Object { $_.kind -ceq 'part' -and $_.isdef })
    $used = NewH; foreach ($u in @($ELIST | Where-Object { $_.kind -ceq 'part' -and -not $_.isdef -and $null -ne $_.type -and $null -ne $_.owner })) { $used[$u.type] = 1 }
    $hasparts = NewH; foreach ($u in @($ELIST | Where-Object { $_.kind -ceq 'part' -and -not $_.isdef -and $null -ne $_.owner -and $_.owner.isdef })) { $hasparts[$u.owner.name] = 1 }
    foreach ($d in $defs) { if (-not $used.ContainsKey($d.name) -and $hasparts.ContainsKey($d.name)) { $PLATES += , (Rec @{ kind = 'tree'; roots = @($d); auto = $true }) } }
    foreach ($d in $defs) { if ($d.hasconn) { $PLATES += , (Rec @{ kind = 'ibd'; roots = @($d); auto = $true }) } }
    if (@($ELIST | Where-Object { $_.kind -ceq 'requirement' -and -not $_.isdef }).Count) { $PLATES += , (Rec @{ kind = 'trace'; auto = $true }) }
    if ($PKGMAP.Count -gt 1) { $PLATES += , (Rec @{ kind = 'pkg'; auto = $true }) }
}

# ------------------------------------------------------------------ draw each plate's content
$TMPDIR = Join-Path (Dflt $env:TEMP '.') ('sysml-plates-' + (Get-Random -Maximum 999999999))
$null = New-Item -ItemType Directory -Path $TMPDIR -Force
$KINDNAME = NewH
foreach ($kv in @(@('tree', 'Part decomposition'), @('ibd', 'Interconnection diagram'), @('trace', 'Requirement trace'), @('pkg', 'Packages and markings'), @('table', 'Element table'), @('text', 'Textual notation'))) { $KINDNAME[$kv[0]] = $kv[1] }
$script:RN = 0
function RunRenderer([string]$script, $rargs) {
    VFlushErr
    $script:RN++
    $out = Join-Path $TMPDIR ("r$($script:RN).svg")
    $null = & (Join-Path $PSScriptRoot $script) -o $out @rargs
    if (IsFile $out) { $out } else { $null }
}
$script:NUM = 0
foreach ($p in $PLATES) {
    $v = $p.view
    if ($p.kind -ceq 'tree') { $p.svg = RunRenderer 'sysml-tree-svg.ps1' (@(foreach ($r in @($p.roots)) { '--root'; ((@($r.pkg) + , $r.name) -join '::') }) + $FILES) }
    elseif ($p.kind -ceq 'ibd') { $p.svg = RunRenderer 'sysml-ibd-svg.ps1' (@(foreach ($r in @($p.roots)) { '--root'; ((@($r.pkg) + , $r.name) -join '::') }) + $FILES) }
    elseif ($p.kind -ceq 'trace') { $p.svg = RunRenderer 'sysml-trace-svg.ps1' (@($(if ($OPT['color']) { } else { '--mono' })) + @(foreach ($q in @($p.packages)) { if ($null -ne $q) { '--package'; $q } }) + $FILES) }
    elseif ($p.kind -ceq 'pkg') { $p.svg = RunRenderer 'sysml-pkg-svg.ps1' (@('--hide', 'SecMeta') + $FILES) }
    if (@('tree', 'ibd', 'trace', 'pkg') -ccontains $p.kind) {
        if ($null -eq $p.svg) {
            if ($null -ne $v) { WarnMsg $v.file $v.line "plate '$($v.name)' could not be drawn" } else { WarnMsg '-' 0 "plate '$($p.kind)' could not be drawn" }
            $p.skip = $true; continue
        }
    }
    $att = if ($null -ne $v -and $null -ne $v.attrs['Drawing']) { $v.attrs['Drawing'] } else { NewH }
    if ($null -ne $att['number']) { $p.number = $att['number'] }
    elseif ($null -ne $v -and $v.id -ne '') { $p.number = $v.id }
    else { $script:NUM++; $p.number = '{0}-{1}' -f $OPT['prefix'], $script:NUM.ToString('000') }
    $title = if ($null -ne $v) { Dflt $v.doc '' } else { '' }
    $title = Sub $title '^(.*?[.!?])(?:\s.*)?$' '$1'; $title = Sub $title '[.]$' ''
    if ($title -eq '') {
        if ($null -ne $v) { $title = (@(MS $v.name '([A-Z]?[a-z0-9]+|[A-Z]+(?![a-z]))' | ForEach-Object { $_.Value.ToLower() })) -join ' ' } else { $title = $KINDNAME[$p.kind] }
        $title = UcFirst $title
    }
    $p.title = $title
    if ($null -ne $p.roots) { $p.sub = (@($p.roots) | ForEach-Object { $_.name }) -join ', ' }
    elseif ($null -ne $p.packages -and @($p.packages).Count) { $p.sub = @($p.packages) -join ', ' }
    elseif ($null -ne $v) { $p.sub = (@(@($v.expose) | Where-Object { $null -ne $_ } | ForEach-Object { (@($_.segs) -join '::') + $(if ($_.star) { "::$($_.star)" } else { '' }) })) -join ', ' }
    else { $p.sub = 'whole model' }
    $p.doctype = $KINDNAME[$p.kind]
    $p.ref = if ($null -ne $v) { Qn $v } else { "generated ($($p.kind))" }
    $p.rev = Dflt $att['revision'] $OPT['rev']
    $p.status = Dflt $att['status'] $OPT['status']
    $p.creator = Dflt $att['drawnBy'] (Dflt $OPT['creator'] '')
    $p.approver = Dflt $att['approvedBy'] (Dflt $OPT['approver'] '')
    $p.owner = Dflt $att['owner'] (Dflt $OPT['owner'] '')
    $r = if ($null -ne $v) { ElemRank $v } else { -1 }
    foreach ($e in @($p.roots) + @($p.elements)) { if ($null -eq $e) { continue }; $x = ElemRank $e; if ($x -gt $r) { $r = $x } }
    foreach ($q in @($p.packages)) { if ($null -eq $q) { continue }; $x = if ($null -ne $PKGMAP[$q]) { PkgRank $PKGMAP[$q] } else { -1 }; if ($x -gt $r) { $r = $x } }
    if ($null -eq $v -or $p.kind -ceq 'pkg' -or ($p.kind -ceq 'trace' -and -not @(@($p.packages) | Where-Object { $null -ne $_ }).Count)) { foreach ($q in @($PKGMAP.Values)) { $x = PkgRank $q; if ($x -gt $r) { $r = $x } } }
    $p.marking = if ($r -ge 0) { $LEVELLIST[$r] } else { 'UNMARKED' }
    $p.size = (Dflt $att['size'] $(if ($OPT['size'] -ceq 'auto') { 'AUTO' } else { $OPT['size'] })).ToUpper()
}
$PLATES = @($PLATES | Where-Object { -not $_.skip })

# ------------------------------------------------------------------ sheet layout
$TBW = 180; $TBH = 45
function FrameOf([string]$sz) { $wh = $SHEET[$sz]; @{ x = 20; y = 10; w = $wh[0] - 30; h = $wh[1] - 20 } }
function Areas([string]$sz) {
    $fr = FrameOf $sz
    , @(@(($fr.x + 5), ($fr.y + 5), ($fr.w - 10), ($fr.h - 10 - $TBH - 4)), @(($fr.x + 5), ($fr.y + 5), ($fr.w - 10 - $TBW - 4), ($fr.h - 10)))
}
function SvgSize([string]$path) {
    $t = VRead $path
    $m = M $t '<svg[^>]*\bwidth="([\d.]+)"[^>]*\bheight="([\d.]+)"'
    if ($m.Success) { , @($m.Groups[1].Value, $m.Groups[2].Value, $t) } else { , @('0', '0', $t) }
}
function Fit([string]$sz, $w, $h) {
    $best = $null; $sc = 0
    foreach ($ar in (Areas $sz)) {
        if ($ar[2] -le 0 -or $ar[3] -le 0) { continue }
        $k = if ($ar[2] / $w -lt $ar[3] / $h) { $ar[2] / $w } else { $ar[3] / $h }
        if ($k -gt $sc) { $best = $ar; $sc = $k }
    }
    if ($sc -gt 0.35) { $sc = 0.35 }
    , @($best, $sc)
}
function Gray([string]$hx) {
    $r = [int]('0x' + $hx.Substring(0, 2)); $g = [int]('0x' + $hx.Substring(2, 2)); $b = [int]('0x' + $hx.Substring(4, 2))
    $l = 0.299 * $r + 0.587 * $g + 0.114 * $b
    if ($l -lt 185) { return '#000000' }
    $v = Trunc (255 - (255 - $l) * 0.8 + 0.5)
    '#' + ('{0:x2}' -f $v) + ('{0:x2}' -f $v) + ('{0:x2}' -f $v)
}
function Mono([string]$t) {
    $out = ''; $pos = 0
    foreach ($m in (MS $t '#([0-9a-fA-F]{6})\b')) { $out += $t.Substring($pos, $m.Index - $pos) + (Gray $m.Groups[1].Value); $pos = $m.Index + $m.Length }
    $out + $t.Substring($pos)
}
function Cut([string]$s, [int]$mx) { if ($s.Length -gt $mx) { $s.Substring(0, [int]($mx - 1)) + $script:ELLIP } else { $s } }
function LayoutRows($p) {
    $lh = if ($p.kind -ceq 'text') { 3.6 } else { 5.0 }; $th = 2.5
    $size = $p.size
    if ($size -ceq 'AUTO') {
        if ($p.kind -ceq 'text') { $nrows = 0; foreach ($e in @($p.elements)) { $nrows += (Dflt $e.endline $e.line) - $e.line + 3 } } else { $nrows = @($p.elements).Count }
        $a4 = (Areas 'A4')[0]
        $size = if ($nrows -le (Trunc (($a4[3] - 10) / $lh))) { 'A4' } else { 'A3' }
    }
    $ar = (Areas $size)[0]
    $cw = $th * 0.6
    $rows = @()
    if ($p.kind -ceq 'text') {
        foreach ($e in (SortBy @($p.elements) { param($x, $y) $c = Cmp $x.file $y.file; if ($c) { return $c }; NCmp $x.line $y.line })) {
            $end = Dflt $e.endline $e.line
            $rows += , @("// " + (Qn $e) + "  ($($e.file):$($e.line))")
            $src = $SRCLINES[$e.file]
            for ($i = $e.line; $i -le $end; $i++) { $rows += , @($(if ($i - 1 -lt $src.Count) { $src[$i - 1] } else { '' })) }
            $rows += , @('')
        }
    } else {
        foreach ($e in (SortBy @($p.elements) { param($x, $y) Cmp (Qn $x) (Qn $y) })) {
            $rows += , @((Qn $e), ($e.kind + $(if ($e.isdef) { ' def' } else { '' })), ((@(@($e.meta) | Where-Object { $_ -cne 'Drawing' } | ForEach-Object { "@$_" })) -join ' '), (Dflt $e.doc ''), "$($e.file):$($e.line)")
        }
    }
    $per = Trunc (($ar[3] - $(if ($p.kind -ceq 'text') { 4 } else { 10 })) / $lh); if ($per -lt 1) { $per = 1 }
    $pages = @(); for ($i = 0; $i -lt $rows.Count; $i += $per) { $pg = @(); for ($j = $i; $j -lt $i + $per -and $j -lt $rows.Count; $j++) { $pg += , $rows[$j] }; $pages += , $pg }
    if (-not $pages.Count) { $pages = @(, @()) }
    $outl = @()
    $maxc = Trunc ($ar[2] / $cw)
    for ($i = 0; $i -lt $pages.Count; $i++) {
        $bl = @(); $y = $ar[1] + 4
        if ($p.kind -ceq 'text') {
            foreach ($r in $pages[$i]) {
                $l = $r[0].Replace("`t", '    '); $l = Cut $l $maxc
                $bl += , ('<text x="' + (F $ar[0] 2) + '" y="' + (F $y 2) + '" font-family="DejaVu Sans Mono, Consolas, monospace" font-size="' + (N $th) + '" fill="#000000" xml:space="preserve">' + (Esc $l) + '</text>'); $y += $lh
            }
        } else {
            $wf = @(0.30, 0.10, 0.14, 0.31, 0.15); $xs = @($ar[0]); for ($k = 1; $k -lt $wf.Count; $k++) { $xs += , ($xs[-1] + $wf[$k - 1] * $ar[2]) }
            $hd = @('Element', 'Kind', 'Metadata', 'Doc', 'Source')
            $bl += , ('<rect x="' + (F $ar[0] 2) + '" y="' + (F ($y - 4) 2) + '" width="' + (F $ar[2] 2) + '" height="' + (F ($lh * (@($pages[$i]).Count + 1) + 1) 2) + '" fill="none" stroke="#000000" stroke-width="0.5"/>')
            $bl += , ('<line x1="' + (F $ar[0] 2) + '" y1="' + (F ($y + 1.5) 2) + '" x2="' + (F ($ar[0] + $ar[2]) 2) + '" y2="' + (F ($y + 1.5) 2) + '" stroke="#000000" stroke-width="0.5"/>')
            for ($k = 0; $k -lt $hd.Count; $k++) { $bl += , ('<text x="' + (F ($xs[$k] + 1) 2) + '" y="' + (F $y 2) + '" font-size="' + (N $th) + '" font-weight="bold" fill="#000000">' + $hd[$k] + '</text>') }
            $y += $lh
            foreach ($r in $pages[$i]) {
                for ($c = 0; $c -lt $r.Count; $c++) {
                    $mx = (Trunc ($wf[$c] * $ar[2] / ($th * 0.55))) - 1; $s = Cut $r[$c] $mx
                    $bl += , ('<text x="' + (F ($xs[$c] + 1) 2) + '" y="' + (F $y 2) + '" font-size="' + (N $th) + '" fill="#000000">' + (Esc $s) + '</text>')
                }
                $bl += , ('<line x1="' + (F $ar[0] 2) + '" y1="' + (F ($y + 1.5) 2) + '" x2="' + (F ($ar[0] + $ar[2]) 2) + '" y2="' + (F ($y + 1.5) 2) + '" stroke="#000000" stroke-width="0.18"/>')
                $y += $lh
            }
            for ($k = 1; $k -lt $xs.Count; $k++) { $bl += , ('<line x1="' + (F $xs[$k] 2) + '" y1="' + (F $ar[1] 2) + '" x2="' + (F $xs[$k] 2) + '" y2="' + (F ($y - $lh + 1.5) 2) + '" stroke="#000000" stroke-width="0.25"/>') }
        }
        $outl += , (CopyRec $p @{ size = $size; body = ($bl -join "`n"); scale = '-'; cont = $(if ($pages.Count -gt 1) { "$($i + 1) of $($pages.Count)" } else { '' }) })
    }
    , $outl
}
$OUTP = @()
foreach ($p in $PLATES) {
    if ($null -ne $p.svg) {
        $ss = SvgSize $p.svg; $svgw0 = $ss[0]; $svgh0 = $ss[1]; $t = $ss[2]
        $wv = [double]$svgw0; $hv = [double]$svgh0
        $size = $p.size
        if ($size -ceq 'AUTO') {
            $size = 'A0'
            foreach ($s in @('A4', 'A3', 'A2', 'A1', 'A0')) { $fk = (Fit $s $wv $hv)[1]; if (12 * $fk -ge $OPT['min-text']) { $size = $s; break } }
        }
        $fitr = Fit $size $wv $hv; $ar = $fitr[0]; $k = $fitr[1]
        if (12 * $k -lt $OPT['min-text'] - 1e-9) {
            $msg = 'plate ' + $p.number + ': diagram text is ' + (F (12 * $k) 1) + ' mm on ' + $size + ', below ' + (F $OPT['min-text'] 1) + ' mm'
            if ($null -ne $p.view) { WarnMsg $p.view.file $p.view.line $msg } else { WarnMsg '-' 0 $msg }
        }
        $dw = $wv * $k; $dh = $hv * $k
        $x = $ar[0] + ($ar[2] - $dw) / 2; $y = $ar[1] + ($ar[3] - $dh) / 2
        $t = Sub $t '<\?xml[^>]*\?>' ''; $t = GSub $t '<script>.*?</script>' '' 's'; $t = GSub $t '<!--.*?-->' '' 's'
        $root = (M $t '^\s*(<svg\b[^>]*>)' 's').Groups[1].Value
        $inherit = (@(foreach ($an in @('font-family', 'font-size')) { $m = M $root ('\b(' + $an + '="[^"]*")'); if ($m.Success) { $m.Groups[1].Value } })) -join ' '
        $t = Sub $t '^\s*<svg\b[^>]*>' '' 's'; $t = Sub $t '</svg>\s*$' '' 's'
        $t = "<g $inherit>$t</g>"
        if (-not $OPT['color']) { $t = Mono $t }
        $OUTP += , (CopyRec $p @{ size = $size; body = ('<svg x="' + (F $x 2) + '" y="' + (F $y 2) + '" width="' + (F $dw 2) + '" height="' + (F $dh 2) + '" viewBox="0 0 ' + $svgw0 + ' ' + $svgh0 + '" preserveAspectRatio="xMidYMid meet">' + $t + '</svg>'); scale = ('NTS (' + (F $k 2) + ' mm/px)') })
    } else { $OUTP += (LayoutRows $p) }
}

# ------------------------------------------------------------------ sheets
$FONT = 'font-family="osifont, ISOCPEUR, ''DejaVu Sans'', Arial, sans-serif"'
$PROV = Dflt $OPT['source'] ''
if ($PROV -eq '' -and ((Test-Path -LiteralPath '.git' -PathType Container) -or (Test-Path -LiteralPath '.git' -PathType Leaf)) -and $null -ne (Get-Command git -ErrorAction SilentlyContinue)) {
    $dsc = ((& git describe --always --dirty 2>$null) | Select-Object -First 1); if ($dsc) { $PROV = "git $dsc" }
}
if ($PROV -eq '') { $PROV = "$($FILES.Count) file(s)" }
$LETTERS = @('A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'J', 'K', 'L', 'M', 'N', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z')
function Ln($x1, $y1, $x2, $y2, [string]$sw) { '<line x1="' + (F $x1 2) + '" y1="' + (F $y1 2) + '" x2="' + (F $x2 2) + '" y2="' + (F $y2 2) + '" stroke="#000000" stroke-width="' + $sw + '"/>' }
function SheetSvg($p, [int]$no, [int]$tot) {
    $wh = $SHEET[$p.size]; $shw = $wh[0]; $shh = $wh[1]; $nx = $wh[2]; $ny = $wh[3]
    $fr = FrameOf $p.size
    $o = @()
    $o += , ('<svg xmlns="http://www.w3.org/2000/svg" width="' + $shw + 'mm" height="' + $shh + 'mm" viewBox="0 0 ' + $shw + ' ' + $shh + '" ' + $FONT + '>')
    $o += , ('<rect width="' + $shw + '" height="' + $shh + '" fill="#ffffff"/>')
    $o += , ('<rect x="' + $fr.x + '" y="' + $fr.y + '" width="' + $fr.w + '" height="' + $fr.h + '" fill="none" stroke="#000000" stroke-width="0.7"/>')
    $fx = $fr.w / $nx; $fy = $fr.h / $ny
    for ($i = 0; $i -le $nx; $i++) {
        $x = $fr.x + $i * $fx
        if ($i -gt 0 -and $i -lt $nx) { $o += , (Ln $x ($fr.y - 5) $x $fr.y '0.35'); $o += , (Ln $x ($fr.y + $fr.h) $x ($fr.y + $fr.h + 5) '0.35') }
        if ($i -eq $nx) { continue }
        $cx = $x + $fx / 2
        $o += , ('<text x="' + (F $cx 2) + '" y="' + (F ($fr.y - 1.3) 2) + '" font-size="3.5" text-anchor="middle">' + ($i + 1) + '</text>')
        $o += , ('<text x="' + (F $cx 2) + '" y="' + (F ($fr.y + $fr.h + 4) 2) + '" font-size="3.5" text-anchor="middle">' + ($i + 1) + '</text>')
    }
    for ($j = 0; $j -le $ny; $j++) {
        $y = $fr.y + $j * $fy
        if ($j -gt 0 -and $j -lt $ny) { $o += , (Ln ($fr.x - 5) $y $fr.x $y '0.35'); $o += , (Ln ($fr.x + $fr.w) $y ($fr.x + $fr.w + 5) $y '0.35') }
        if ($j -eq $ny) { continue }
        $cy = $y + $fy / 2 + 1.2
        $o += , ('<text x="' + (F ($fr.x - 2.5) 2) + '" y="' + (F $cy 2) + '" font-size="3.5" text-anchor="middle">' + $LETTERS[$j] + '</text>')
        $o += , ('<text x="' + (F ($fr.x + $fr.w + 2.5) 2) + '" y="' + (F $cy 2) + '" font-size="3.5" text-anchor="middle">' + $LETTERS[$j] + '</text>')
    }
    $mx = $fr.x + $fr.w / 2; $my = $fr.y + $fr.h / 2
    $o += , (Ln $mx 0 $mx ($fr.y + 5) '0.7'); $o += , (Ln $mx $shh $mx ($fr.y + $fr.h - 5) '0.7'); $o += , (Ln 0 $my ($fr.x + 5) $my '0.7'); $o += , (Ln $shw $my ($fr.x + $fr.w - 5) $my '0.7')
    $mw = $p.marking.Length * 4 * 0.62 + 4
    foreach ($yy in @(@(0.3, 4.2), @(($shh - 4.7), ($shh - 0.8)))) {
        $o += , ('<rect x="' + (F ($mx - $mw / 2) 2) + '" y="' + (F $yy[0] 2) + '" width="' + (F $mw 2) + '" height="4.4" fill="#ffffff"/>')
        $o += , ('<text x="' + (F $mx 2) + '" y="' + (F $yy[1] 2) + '" font-size="4" font-weight="bold" text-anchor="middle">' + (Esc $p.marking) + '</text>')
    }
    $o += , $p.body
    $tx = $fr.x + $fr.w - $TBW; $ty = $fr.y + $fr.h - $TBH
    $o += , ('<rect x="' + (F $tx 2) + '" y="' + (F $ty 2) + '" width="' + $TBW + '" height="' + $TBH + '" fill="#ffffff" stroke="#000000" stroke-width="0.7"/>')
    $fields = @(
        @(0, 0, 90, 9, 'Security class', $p.marking, 3.5, $null), @(90, 0, 45, 9, 'Scale', $p.scale, 2.5, $null), @(135, 0, 45, 9, 'Source', $PROV, 2.5, $null),
        @(0, 9, 60, 9, 'Legal owner', $p.owner, 3.5, $null), @(60, 9, 60, 9, 'Document type', $p.doctype, 3.5, $null), @(120, 9, 60, 9, 'Document status', $p.status, 3.5, $null),
        @(0, 18, 60, 9, 'Technical reference', $p.ref, 2.5, $null), @(60, 18, 120, 18, 'Title', $p.title, 5, ($p.sub + $(if ($p.cont) { " ($($p.cont))" } else { '' }))),
        @(0, 27, 60, 9, 'Created by', $p.creator, 3.5, $null),
        @(0, 36, 60, 9, 'Approved by', $p.approver, 3.5, $null), @(60, 36, 55, 9, 'Identification number', $p.number, 3.5, $null),
        @(115, 36, 12, 9, 'Rev.', $p.rev, 3.5, $null), @(127, 36, 27, 9, 'Date of issue', $DATE, 3.5, $null), @(154, 36, 10, 9, 'Lang.', 'en', 3.5, $null),
        @(164, 36, 16, 9, 'Sheet', "$no/$tot", 3.5, $null))
    foreach ($cf in $fields) {
        $x = $cf[0]; $y = $cf[1]; $w = $cf[2]; $h = $cf[3]; $lab = $cf[4]; $val = $cf[5]; $vs = $cf[6]; $sub = $cf[7]
        $X0 = $tx + $x; $Y0 = $ty + $y
        $o += , ('<rect x="' + (F $X0 2) + '" y="' + (F $Y0 2) + '" width="' + (F $w 2) + '" height="' + (F $h 2) + '" fill="none" stroke="#000000" stroke-width="0.35"/>')
        $o += , ('<text x="' + (F ($X0 + 1) 2) + '" y="' + (F ($Y0 + 2.4) 2) + '" font-size="1.8">' + (Esc $lab) + '</text>')
        $v = Dflt $val ''
        $vsText = N $vs
        if ($lab -ceq 'Title') {
            $ln = if ($v.Length) { $v.Length } else { 1 }
            $fit = ($w - 3) / ($ln * 0.62)
            $vs = if ($fit -lt 3.5) { 3.5 } elseif ($fit -lt $vs) { $fit } else { $vs }
            $vsText = F $vs 2; $vs = [double]$vsText
        }
        $maxc = Trunc (($w - 2) / ($vs * $(if ($lab -ceq 'Title') { 0.62 } else { 0.55 })))
        $v = Cut $v $maxc
        $o += , ('<text x="' + (F ($X0 + 1.5) 2) + '" y="' + (F ($Y0 + $(if ($sub) { 9 } else { $h - 2 })) 2) + '" font-size="' + $vsText + '"' + $(if ($lab -ceq 'Title') { ' font-weight="bold"' } else { '' }) + '>' + (Esc $v) + '</text>')
        if ($sub) {
            $m2 = Trunc (($w - 2) / (2.5 * 0.55)); $s2 = Cut $sub $m2
            $o += , ('<text x="' + (F ($X0 + 1.5) 2) + '" y="' + (F ($Y0 + 15) 2) + '" font-size="2.5">' + (Esc $s2) + '</text>')
        }
    }
    $o += , ('<rect x="' + (F $tx 2) + '" y="' + (F $ty 2) + '" width="' + $TBW + '" height="' + $TBH + '" fill="none" stroke="#000000" stroke-width="0.7"/>')
    $o += , '</svg>'
    $o -join "`n"
}
if (-not (IsDir $OPT['o'])) { $null = New-Item -ItemType Directory -Path $OPT['o'] -Force }
$TOTAL = $OUTP.Count
$HTML = @(); $SIZES = NewH
for ($i = 0; $i -lt $OUTP.Count; $i++) {
    $p = $OUTP[$i]
    $svg = SheetSvg $p ($i + 1) $TOTAL
    $fn = $p.number + $(if ($p.cont) { '-' + (M $p.cont '^(\d+)').Groups[1].Value } else { '' })
    $fn = GSub $fn '[^\w.-]+' '_'
    $null = VWrite "$($OPT['o'])/$fn.svg" ("<?xml version=`"1.0`" encoding=`"UTF-8`"?>`n<!-- generated by sysml-plates.pl -->`n$svg`n")
    $SIZES[$p.size] = 1
    $HTML += , "<div class=`"sheet $($p.size)`">$svg</div>"
    PL ((PadR $p.number 14) + ' ' + (PadR $p.size 3) + ' ' + (PadL ([string]($i + 1)) 3) + '/' + (PadR ([string]$TOTAL) 3) + ' ' + (PadR $p.kind 24) + ' ' + $(if ($null -ne $p.view) { Qn $p.view } else { 'auto' }) + " -> $($OPT['o'])/$fn.svg")
}
$h = "<!DOCTYPE html>`n<html><head><meta charset=`"utf-8`"><title>Plates</title><style>`n" +
     "body { margin: 0; background: #888; } .sheet { margin: 12px auto; width: max-content; background: #fff; }`n" +
     ((@(foreach ($sz in (SortStr @($SIZES.Keys))) { $wh = $SHEET[$sz]; "@page $sz { size: $($wh[0])mm $($wh[1])mm; margin: 0 } .sheet.$sz { page: $sz }`n" })) -join '') +
     "@media print { body { background: #fff } .sheet { margin: 0; break-after: page } }`n</style></head><body>`n" + ($HTML -join "`n") + "`n</body></html>`n"
$null = VWrite "$($OPT['o'])/plates.html" $h
Remove-Item -LiteralPath $TMPDIR -Recurse -Force -ErrorAction SilentlyContinue
PL ('plates: {0} view(s), {1} plate(s) on {2} sheet(s), {3} warning(s) -> {4}/plates.html' -f $VIEWS.Count, $PLATES.Count, $TOTAL, $script:NWARN, $OPT['o'])
VExit $(if ($script:NWARN) { 1 } else { 0 })
