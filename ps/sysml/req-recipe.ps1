<#
req-recipe.ps1 -- grade requirement statements against the requirement recipe: one sentence per requirement, built
from up to 18 parts, six of them required. A port of the kit's tools/sysml/req-recipe.pl to Windows PowerShell 5.1
(Constrained Language Mode safe): same options, same output bytes, same exit codes.

  req-recipe.cmd [--format text|csv|junit|codequality] [--require classification]
                 [--links [--baseline] [--top REGEX]...] [--strict] [--tag NAME]... [--only ID]... [-o FILE] INPUT...

INPUT: .sysml files or folders of them, DOORS exports (.reqif, .reqifz, .csv), or a plain .txt file (one requirement
per paragraph, its ID in parentheses at the end). Exit 0, or 1 with --strict when any requirement has a finding or a
missing required part, or 2 on bad usage or an unreadable input. The last line is always
  requirements=N findings=F missing=M
The recipe, the heuristics and the scoring are those of req-recipe.pl (read its header). --top REGEX uses .NET
regular expressions (ECMAScript mode), which accept the usual Perl patterns.
#>
. "$PSScriptRoot\reqiflib.ps1"

$script:RECIPE_PARTS = @('Classification', 'State', 'Trigger', 'Preconditions', 'Specification Target', 'Allocated Function',
    'Operative Verb', 'Target Verb', 'Precise Object(s)', 'Modifier(s)', 'Modification(s)', 'Specification',
    'Document Number', 'Section Number', 'Exception(s)', 'Informational Statement(s)', 'Requirement ID', 'Requirement Tags')
$script:REQUIRED = @('Specification Target', 'Operative Verb', 'Target Verb', 'Precise Object(s)', 'Requirement ID')
$script:LINK_PARTS = @('Parent Trace', 'Rationale', 'Verification Method', 'Verification Case', 'Satisfied By')
$script:METHOD = NewH; foreach ($m in 'Test', 'Analysis', 'Demonstration', 'Inspection') { $script:METHOD[(LcA $m)] = $m }
$script:LINKS = $false
$script:WEAK = NewH
foreach ($w in 'provide', 'have', 'be', 'establish') { $script:WEAK[$w] = 'the recipe' }
foreach ($w in 'support', 'allow', 'enable', 'handle', 'ensure', 'facilitate', 'accommodate', 'permit') { $script:WEAK[$w] = "the kit's list" }
$script:KNOWN_TAG = NewH; foreach ($t in 'SC', 'SR', 'MC', 'RMF') { $script:KNOWN_TAG[$t] = 1 }
$script:VAGUE = @('as appropriate', 'as required', 'as needed', 'etc', 'and/or', 'user-friendly', 'user friendly', 'fast',
    'quickly', 'easy', 'easily', 'adequate', 'sufficient', 'robust', 'flexible', 'timely', 'approximately',
    'optimize', 'minimize', 'maximize', 'state-of-the-art', 'if possible', 'in time')
$script:PERF_VERB = NewH
foreach ($v in 'send transmit report respond update publish sample measure maintain detect retry deliver recover acquire charge receive'.Split(' ')) { $script:PERF_VERB[$v] = 1 }
$script:MODLIST = @('such that', 'in less than', 'less than', 'no more than', 'at least', 'at a rate of', 'within', 'with',
    'to', 'every', 'per', 'at', 'by', 'from', 'for', 'on', 'in', 'under', 'over', 'into', 'onto', 'via',
    'through', 'after', 'before', 'between', 'once')
$script:MODRE = (@(foreach ($m in $script:MODLIST) { $m.Replace(' ', '\s+') }) -join '|')
$script:SEV_COST = @{ missing = 20; major = 15; minor = 8; info = 3 }
$script:USAGE = 'usage: req-recipe.pl [--format text|csv|junit|codequality] [--require classification] [--links [--baseline] [--top REGEX]...] [--strict] [--tag NAME]... [--only ID]... [-o FILE] INPUT...'
$script:WS = '[\t\n\x0B\f\r ]'

# ---------------------------------------------------------------- MD5 (Digest::MD5 md5_hex), pure integer arithmetic
$script:MD5S = @(7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22, 5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20,
    4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23, 6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21)
$script:MD5K = @(0xd76aa478L, 0xe8c7b756L, 0x242070dbL, 0xc1bdceeeL, 0xf57c0fafL, 0x4787c62aL, 0xa8304613L, 0xfd469501L,
    0x698098d8L, 0x8b44f7afL, 0xffff5bb1L, 0x895cd7beL, 0x6b901122L, 0xfd987193L, 0xa679438eL, 0x49b40821L,
    0xf61e2562L, 0xc040b340L, 0x265e5a51L, 0xe9b6c7aaL, 0xd62f105dL, 0x02441453L, 0xd8a1e681L, 0xe7d3fbc8L,
    0x21e1cde6L, 0xc33707d6L, 0xf4d50d87L, 0x455a14edL, 0xa9e3e905L, 0xfcefa3f8L, 0x676f02d9L, 0x8d2a4c8aL,
    0xfffa3942L, 0x8771f681L, 0x6d9d6122L, 0xfde5380cL, 0xa4beea44L, 0x4bdecfa9L, 0xf6bb4b60L, 0xbebfbc70L,
    0x289b7ec6L, 0xeaa127faL, 0xd4ef3085L, 0x04881d05L, 0xd9d4d039L, 0xe6db99e5L, 0x1fa27cf8L, 0xc4ac5665L,
    0xf4292244L, 0x432aff97L, 0xab9423a7L, 0xfc93a039L, 0x655b59c3L, 0x8f0ccc92L, 0xffeff47dL, 0x85845dd1L,
    0x6fa87e4fL, 0xfe2ce6e0L, 0xa3014314L, 0x4e0811a1L, 0xf7537e82L, 0xbd3af235L, 0x2ad7d2bbL, 0xeb86d391L)
function Md5Hex([string]$s) {                          # byte string -> 32 hex digits
    $mask = 0xFFFFFFFFL
    $len = $s.Length; $n = ((($len + 8) -shr 6) + 1) * 64
    $buf = New-Object 'int[]' $n
    for ($i = 0; $i -lt $len; $i++) { $buf[$i] = [int]$s[$i] }
    $buf[$len] = 0x80
    $bits = [long]$len * 8
    for ($i = 0; $i -lt 8; $i++) { $buf[$n - 8 + $i] = [int](($bits -shr (8 * $i)) -band 0xFF) }
    $a0 = 0x67452301L; $b0 = 0xefcdab89L; $c0 = 0x98badcfeL; $d0 = 0x10325476L
    $words = New-Object 'long[]' 16
    for ($off = 0; $off -lt $n; $off += 64) {
        for ($j = 0; $j -lt 16; $j++) { $p = $off + 4 * $j; $words[$j] = [long]$buf[$p] -bor ([long]$buf[$p + 1] -shl 8) -bor ([long]$buf[$p + 2] -shl 16) -bor ([long]$buf[$p + 3] -shl 24) }
        $hA = $a0; $hB = $b0; $hC = $c0; $hD = $d0
        for ($i = 0; $i -lt 64; $i++) {
            if ($i -lt 16) { $hF = ($hB -band $hC) -bor ((-bnot $hB) -band $mask -band $hD); $g = $i }
            elseif ($i -lt 32) { $hF = ($hD -band $hB) -bor ((-bnot $hD) -band $mask -band $hC); $g = (5 * $i + 1) % 16 }
            elseif ($i -lt 48) { $hF = $hB -bxor $hC -bxor $hD; $g = (3 * $i + 5) % 16 }
            else { $hF = $hC -bxor ($hB -bor ((-bnot $hD) -band $mask)); $g = (7 * $i) % 16 }
            $hF = ($hF + $hA + $script:MD5K[$i] + $words[$g]) -band $mask
            $hA = $hD; $hD = $hC; $hC = $hB
            $sh = $script:MD5S[$i]
            $hB = ($hB + ((($hF -shl $sh) -bor ($hF -shr (32 - $sh))) -band $mask)) -band $mask
        }
        $a0 = ($a0 + $hA) -band $mask; $b0 = ($b0 + $hB) -band $mask; $c0 = ($c0 + $hC) -band $mask; $d0 = ($d0 + $hD) -band $mask
    }
    $hex = ''
    foreach ($v in $a0, $b0, $c0, $d0) { for ($i = 0; $i -lt 4; $i++) { $hex += '{0:x2}' -f [int](($v -shr (8 * $i)) -band 0xFF) } }
    $hex
}

# ---------------------------------------------------------------- inputs
function RSlurp([string]$f) {
    if (-not (Test-Path -LiteralPath $f -PathType Leaf)) { throw "cannot read ${f}: No such file or directory`n" }
    (ReadBytes $f).Replace("`r`n", "`n").Replace("`r", "`n")
}
function ReadInput([string]$in) {
    if (-not (Test-Path -LiteralPath $in)) { throw "cannot read ${in}: no such file or folder`n" }
    if (Test-Path -LiteralPath $in -PathType Container) { return ,(ReadSysmlDir $in) }
    if (RTI $in '\.sysml$') { return ,(ReadSysml $in) }
    if ((RTI $in '\.reqifz?$') -or (RTI $in '\.csv$')) {
        $d = if (RTI $in '\.csv$') { LoadCsv $in @{} } else { LoadReqif $in @{} }
        $r = @()
        foreach ($oid in $d.order) {
            $x = $d.objects[$oid]
            if (-not (HasNS $x.text)) { continue }
            $r += , @{ id = $x.id; title = $x.name; text = $x.text; file = $in; line = 1; source = 'doors' }
        }
        return ,$r
    }
    return ,(ReadText $in)
}
function DirFiles([string]$x, $acc) {
    if (-not (Test-Path -LiteralPath $x -PathType Container)) { return }
    $es = @(Get-ChildItem -LiteralPath $x -Force -ErrorAction SilentlyContinue | Where-Object { -not $_.Name.StartsWith('.') } | ForEach-Object { $_.Name })
    foreach ($e in (Sorted $es)) { $p = "$x/$e"; if (Test-Path -LiteralPath $p -PathType Container) { DirFiles $p $acc } elseif (RT $e '\.sysml$') { LAdd $acc $p } }
}
function ReadSysmlDir([string]$d) { $acc = NewL; DirFiles $d $acc; $r = @(); foreach ($f in (LArr $acc)) { $r += ReadSysml $f }; return ,$r }
function R1I([string]$s, [string]$re, [string]$to) { $m = [regex]::Match($s, $re, $script:RXI); if (-not $m.Success) { return $s }; $s.Substring(0, $m.Index) + (Expand $m $to) + $s.Substring($m.Index + $m.Length) }
function StripCode([string]$l) { $c = RR $l '/\*.*?\*/' ''; R1 $c '//.*' '' }
function PackagePaths($lines) {
    $stack = NewL; $path = @(); $depth = 0
    foreach ($l in $lines) {
        $path += (@(for ($j = 0; $j -lt $stack.n; $j++) { $stack.i[$j][0] }) -join '::')
        $code = StripCode $l
        $pm = Rx $code '\bpackage[\t\n\x0B\f\r ]+(''[^'']*''|[A-Za-z0-9_]+)[\t\n\x0B\f\r ]*\{'
        $pk = if ($pm.Success) { $pm.Groups[1].Value } else { $null }
        foreach ($ch in (RA $code '[{}]')) {
            if ($ch.Value -eq '{') { $depth++; if ($null -ne $pk) { $nm = RR $pk "^'|'$" ''; $stack.i[$stack.n] = @($nm, $depth); $stack.n++; $pk = $null } }
            else { if ($stack.n -and $stack.i[$stack.n - 1][1] -eq $depth) { $stack.n-- }; $depth-- }
        }
    }
    return ,$path
}
function SplitList([string]$s, [string]$re) {           # Perl split /re/: leading empty field kept, trailing ones dropped
    $p = @([regex]::Split($s, $re, $script:RX)); $n = $p.Count
    while ($n -gt 0 -and $p[$n - 1] -eq '') { $n-- }
    if ($n -eq 0) { return ,@() }
    return ,@($p[0..($n - 1)])
}
function ReadSysml([string]$f) {
    $lines = @((RSlurp $f) -split "`n")
    $paths = PackagePaths $lines
    $r = @()
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $m = Rx $lines[$i] ('^' + $script:WS + '*requirement' + $script:WS + '+(?:def' + $script:WS + '+)?(''[^'']*''|[A-Za-z0-9_]+)')
        if (-not $m.Success -or $m.Groups[1].Value -ceq 'def') { continue }
        $name = $m.Groups[1].Value; $start = $i
        $block = ''; $depth = 0; $seen = $false
        for ($j = $i; $j -lt $lines.Count; $j++) {
            $l = $lines[$j]; $block += "$l`n"
            $code = StripCode $l
            $depth += (RA $code '\{').Count; if ($depth -gt 0) { $seen = $true }
            $depth -= (RA $code '\}').Count
            if (($seen -and $depth -le 0) -or (-not $seen -and (RT $code (';' + $script:WS + '*$')))) { $i = $j; break }
        }
        $dm = Rx $block ('(?s)\bdoc' + $script:WS + '*/\*' + $script:WS + '*(.*?)' + $script:WS + '*\*/')
        if (-not $dm.Success) { continue }
        $doc = $dm.Groups[1].Value
        $doc = RR $doc ('(?m)^' + $script:WS + '*\*[\t\n\x0B\f\r ]?') ''
        $doc = RR $doc ($script:WS + '+') ' '; $doc = $doc.Replace('* /', '*/')
        $attr = { param($nm) $am = Rx $block ('\b' + $nm + $script:WS + '*(?::' + $script:WS + '*[A-Za-z0-9_]+' + $script:WS + '*)?=' + $script:WS + '*"([^"]*)"'); if ($am.Success) { $am.Groups[1].Value } else { $null } }
        $id = & $attr 'doorsId'; $title = & $attr 'title'; $cls = & $attr 'classification'
        if ($null -eq $cls) { $mm = Rx $block ('@Marking' + $script:WS + '*\{' + $script:WS + '*level' + $script:WS + '*=' + $script:WS + '*(?:[A-Za-z0-9_]+::)*([A-Za-z0-9_]+)'); if ($mm.Success) { $cls = $mm.Groups[1].Value } }
        $tags = @()
        foreach ($tm in (RA $block ('\btags' + $script:WS + '*(?::' + $script:WS + '*[A-Za-z0-9_]+' + $script:WS + '*)?=' + $script:WS + '*"([^"]*)"'))) { $tags += SplitList $tm.Groups[1].Value '[\t\n\x0B\f\r ,;]+' }
        foreach ($tm in (RA $block '@(SC|SR|MC|RMF)\b')) { $tags += $tm.Groups[1].Value }
        $n = RR $name "^'|'$" ''
        $lk = NewH
        $lk['method'] = & $attr 'verificationMethod'
        $lk['rationale'] = & $attr 'rationale'
        if ($null -eq $lk['rationale']) { $rm = Rx $block ('@Rationale' + $script:WS + '*\{[^}]*?(?:text|explanation)' + $script:WS + '*=' + $script:WS + '*"([^"]*)"'); if ($rm.Success) { $lk['rationale'] = $rm.Groups[1].Value } }
        if ($null -eq $lk['rationale']) { $rm = Rx $block ('(?s)\bcomment\b[^/]*/\*' + $script:WS + '*Rationale:' + $script:WS + '*(.*?)' + $script:WS + '*\*/'); if ($rm.Success) { $lk['rationale'] = $rm.Groups[1].Value } }
        $lk['derived_from'] = & $attr 'derivedFrom'
        $lk['level'] = & $attr 'level'
        $hz = @(); foreach ($hm in (RA $block ('\bhazards?' + $script:WS + '*(?::' + $script:WS + '*[A-Za-z0-9_]+' + $script:WS + '*)?=' + $script:WS + '*"([^"]*)"'))) { $hz += SplitList $hm.Groups[1].Value '[\t\n\x0B\f\r ,;]+' }
        $lk['hazards'] = $hz
        if ($null -ne $lk['rationale']) { $lk['rationale'] = RR $lk['rationale'] ($script:WS + '+') ' ' }
        $r += , @{ id = $(if ($null -ne $id) { $id } else { $n }); title = $title; text = $doc; file = $f; line = $start + 1; source = 'sysml'
                   class = $cls; tags = $tags; id_from_attr = ($null -ne $id); name = $n; pkg = $paths[$start]; link = $lk }
    }
    return ,$r
}
function ReadText([string]$f) {
    $t = RSlurp $f
    $r = NewL; $n = 1
    foreach ($para in (SplitList $t '\n[ \t]*\n')) {
        $lines = CountCh $para "`n"
        $p = RR $para ($script:WS + '+') ' '; $p = RR $p '^ | $' ''
        $lk = NewH
        $fm = RxI $p ($script:WS + '*\b((?:Parent|Rationale|Verification|Satisfied by):.*)$')
        if ($fm.Success) {
            $fl = $fm.Groups[1].Value; $p = $p.Substring(0, $fm.Index)
            $parts = @([regex]::Split(" $fl", ($script:WS + '*\b(Parent|Rationale|Verification|Satisfied by):' + $script:WS + '*'), $script:RXI))
            $np = $parts.Count; while ($np -gt 0 -and $parts[$np - 1] -eq '') { $np-- }
            for ($k = 1; $k -lt $np; $k += 2) {
                $key = LcA $parts[$k]; $v = if ($k + 1 -lt $np) { $parts[$k + 1] } else { '' }
                $v = RR $v '[\t\n\x0B\f\r .]+$' ''
                if ($key -ceq 'parent') { $lk['parents'] = @(foreach ($q in (SplitList $v '[\t\n\x0B\f\r ,;]+')) { if ($q.Length) { $q } }) }
                elseif ($key -ceq 'rationale') { $lk['rationale'] = $v }
                elseif ($key -ceq 'verification') {
                    $vm = RxI $v '^([A-Za-z0-9_]+)(?:[\t\n\x0B\f\r ]+by[\t\n\x0B\f\r ]+(.+))?$'
                    $lk['method'] = if ($vm.Success) { $vm.Groups[1].Value } else { $null }
                    $case = if ($vm.Success -and $vm.Groups[2].Success) { $vm.Groups[2].Value } else { '' }
                    $lk['cases'] = @(foreach ($q in (SplitList $case '[\t\n\x0B\f\r ,;]+')) { if ($q.Length) { $q } })
                }
                elseif ($key -ceq 'satisfied by') { $sb = R1 $v ($script:WS + '*\(.*$') ''; $lk['satisfiers'] = @(foreach ($q in (SplitList $sb '[\t\n\x0B\f\r ,;]+')) { if ($q.Length) { $q } }) }
            }
        }
        if ($p -eq '' -and $lk.Count -and $r.n -and $r.i[$r.n - 1].source -ceq 'text') {
            $prev = $r.i[$r.n - 1]; if ($null -eq $prev.link) { $prev.link = NewH }
            foreach ($k in $lk.Keys) { $prev.link[$k] = $lk[$k] }
        } elseif ($p -ne '' -and -not $p.StartsWith('#')) {
            $lead = (Rx $para '^(\n*)').Groups[1].Value.Length
            $rec = @{ text = $p; file = $f; line = $n + $lead; source = 'text' }
            if ($lk.Count) { $rec.link = $lk }
            LAdd $r $rec
        }
        $n += $lines + 2
    }
    return ,(LArr $r)
}

# ---------------------------------------------------------------- links (recipe elements 19-23)
function RefName([string]$r) {
    $r = Trim $r
    $seg = SplitList $r '::|\.'
    $n = if ($seg.Count) { $seg[$seg.Count - 1] } else { $r }
    RR $n "^'|'$" ''
}
function LinkIndex($inputs, $reqs) {
    $ix = NewH
    $at = { param($k) if (-not $ix.ContainsKey($k)) { $ix[$k] = @{ parents = @(); children = 0; satisfiers = @(); cases = @() } }; $ix[$k] }
    $files = NewL
    foreach ($in in $inputs) {
        if (Test-Path -LiteralPath $in -PathType Container) { DirFiles $in $files }
        elseif ((RTI $in '\.sysml$') -and (Test-Path -LiteralPath $in -PathType Leaf)) { LAdd $files $in }
    }
    foreach ($f in (LArr $files)) {
        $t = RSlurp $f
        $t = RR $t '(?s)/\*.*?\*/' ' '; $t = RR $t '//[^\n]*' ''
        foreach ($dm in (RA $t ('(?s)#derivation' + $script:WS + '+connection\b[^{;]*\{(.*?)\}'))) {
            $body = $dm.Groups[1].Value
            $orig = @(foreach ($m in (RA $body ('\bend' + $script:WS + '+#original' + $script:WS + '*::>' + $script:WS + '*([^;]+);'))) { RefName $m.Groups[1].Value })
            $der = @(foreach ($m in (RA $body ('\bend' + $script:WS + '+#derive' + $script:WS + '*::>' + $script:WS + '*([^;]+);'))) { RefName $m.Groups[1].Value })
            foreach ($d in $der) { $e = & $at $d; $e.parents += $orig }
            foreach ($o in $orig) { $e = & $at $o; $e.children += $der.Count }
        }
        foreach ($sm in (RA $t ('\bsatisfy' + $script:WS + '+(?:requirement' + $script:WS + '+)?([A-Za-z0-9_'':.]+?)(?:' + $script:WS + '+by' + $script:WS + '+([A-Za-z0-9_'':.]+))?' + $script:WS + '*;'))) {
            $e = & $at (RefName $sm.Groups[1].Value)
            $e.satisfiers += $(if ($sm.Groups[2].Success) { RefName $sm.Groups[2].Value } else { '(its owner)' })
        }
        $case = '(a verification)'
        foreach ($vm in (RA $t ('\bverification' + $script:WS + '+(?:def' + $script:WS + '+)?(''[^'']*''|[A-Za-z0-9_]+)|\bverify' + $script:WS + '+(?:requirement' + $script:WS + '+)?([A-Za-z0-9_'':.]+)' + $script:WS + '*;'))) {
            if ($vm.Groups[1].Success) { $case = RR $vm.Groups[1].Value "^'|'$" ''; continue }
            $e = & $at (RefName $vm.Groups[2].Value); $e.cases += $case
        }
    }
    foreach ($r in $reqs) {
        $lk = $r.link; if ($null -eq $lk) { continue }
        $id = $r.id; if ($null -eq $id) { $id = (Parse $r.text)['Requirement ID'] }; if ($null -eq $id) { continue }
        $par = @($lk['parents'] | Where-Object { $null -ne $_ })
        $e = & $at $id; $e.parents += $par
        foreach ($p in $par) { $e2 = & $at $p; $e2.children++ }
        $e = & $at $id; $e.cases += @($lk['cases'] | Where-Object { $null -ne $_ }); $e.satisfiers += @($lk['satisfiers'] | Where-Object { $null -ne $_ })
    }
    foreach ($k in @($ix.Keys)) { $v = $ix[$k]; $s = NewH; foreach ($f in 'parents', 'satisfiers', 'cases') { $v[$f] = @(foreach ($x in $v[$f]) { if (-not $s.ContainsKey("$x`0")) { $s["$x`0"] = 1; $x } }) } }
    $ix
}
function LinkCounts($g) {
    $c = [ordered]@{ orphan = 0; childless = 0; unjustified = 0; unverified = 0; unsatisfied = 0; unmitigated = 0 }
    foreach ($r in $g) { foreach ($k in @($r.link_fail.Keys)) { $c[$k] = $c[$k] + 1 } }
    'links: ' + (@(foreach ($k in 'orphan', 'childless', 'unjustified', 'unverified', 'unsatisfied', 'unmitigated') { "$k=$($c[$k])" }) -join ' ') + "`n"
}

# ---------------------------------------------------------------- parse one statement
function SplitCommas([string]$t) {
    $out = @(); $cur = ''; $d = 0
    foreach ($ch in $t.ToCharArray()) {
        if ($ch -eq '(') { $d++ } elseif ($ch -eq ')') { if ($d) { $d-- } }
        if ($ch -eq ',' -and -not $d) { $out += $cur; $cur = ''; continue }
        $cur += $ch
    }
    $out += $cur
    $r = @(foreach ($x in $out) { $y = Trim $x; if ($y -ne '') { $y } })
    return ,$r
}
function Parse($text) {
    $p = NewH; $wsp = $script:WS
    $s = if ($null -ne $text) { [string]$text } else { '' }
    $s = RR $s "$wsp+" ' '; $s = RR $s '^ | $' ''
    $m = Rx $s "^\($wsp*([A-Z]{1,4}(?:\/\/?[A-Z][A-Z\-]*)*)$wsp*\)$wsp*"
    if ($m.Success) { $p['Classification'] = $m.Groups[1].Value; $s = $s.Substring($m.Length) }
    $m = Rx $s "$wsp*\[([A-Za-z]{1,6}(?:$wsp*[,;\/ ]$wsp*[A-Za-z]{1,6})*)\]$wsp*\.?$wsp*$"
    if ($m.Success) { $p['Requirement Tags'] = @(foreach ($x in (SplitList $m.Groups[1].Value '[\t\n\x0B\f\r ,;\/]+')) { UcA $x }); $s = $s.Substring(0, $m.Index) }
    $m = Rx $s "$wsp*\(([A-Za-z][A-Za-z0-9]*(?:[-_.][A-Za-z0-9]+)+)\)$wsp*\.?$wsp*$"
    if ($m.Success) { $p['Requirement ID'] = $m.Groups[1].Value; $s = $s.Substring(0, $m.Index) }
    $m = RxI $s "$wsp*\bNote:$wsp*(.*)$"
    if ($m.Success) { $n = R1 $m.Groups[1].Value "$wsp*\.?$wsp*$" ''; if ($n -ne '') { $p['Informational Statement(s)'] = $n }; $s = $s.Substring(0, $m.Index) }
    $s = R1 $s "$wsp*\.$wsp*$" ''
    $p['_sentences'] = 1 + (RA $s "(?<!\be\.g)(?<!\bi\.e)(?<!\bSec)(?<!\bNo)(?<!\bpara)(?<!\bFig)(?<!\bvs)(?<!\bapprox)\.$wsp+(?=[A-Z])").Count
    $p['_ops'] = @(foreach ($om in [regex]::Matches($s, '\b(shall|will|should|may|must)\b', $script:RXI)) { LcA $om.Groups[1].Value })
    $m = RxI $s "^(.*?)\b(shall|will|should|may|must)\b$wsp*(.*)$"
    if (-not $m.Success) { return $p }
    $pre = $m.Groups[1].Value; $op = LcA $m.Groups[2].Value; $post = $m.Groups[3].Value
    $p['Operative Verb'] = $op
    $pre = RR $pre '[\t\n\x0B\f\r ,]+$' ''
    $cl = SplitCommas $pre
    if ($cl.Count -eq 1) {
        $cm = RxI $cl[0] "^(while|when|during|upon|on|every|after|before|if|once|at)\b$wsp*(.*?)$wsp+((?:the|each|every|all|any|a|an)$wsp+\S.*)$"
        if ($cm.Success) { $cl = @("$($cm.Groups[1].Value) $($cm.Groups[2].Value)", $cm.Groups[3].Value) }
    }
    $state = @(); $trigger = @(); $exc = @(); $subject = $null
    $last = $null
    for ($k = $cl.Count - 1; $k -ge 0; $k--) { if (-not (RTI $cl[$k] "^for$wsp+(?:the$wsp+)?.+?$wsp+function$")) { $last = $cl[$k]; break } }
    if ($null -eq $last) { $last = '' }
    foreach ($c in $cl) {
        if ($c -ceq $last -and $cl.Count) { $subject = if ($null -ne $subject) { "$subject, $c" } else { $c }; continue }
        if (RTI $c "^(while|when|during)\b$wsp*(.*)$") { $state += $c }
        elseif (RTI $c "^(upon|on|every|after|before|if|once|at)\b$wsp*(.*)$") { $trigger += $c }
        elseif (($em = RxI $c "^except\b$wsp*(.*)$").Success) { $exc += $em.Groups[1].Value }
        elseif (($fm = RxI $c "^for$wsp+(?:the$wsp+)?(.+?)$wsp+function$").Success) { $p['Allocated Function'] = $fm.Groups[1].Value }
        else { $subject = if ($null -ne $subject) { "$subject, $c" } else { $c } }
    }
    if ($state.Count) { $p['State'] = $state -join '; ' }
    if ($trigger.Count) { $p['Trigger'] = $trigger -join '; ' }
    if ($state.Count -or $trigger.Count) {
        $p['Preconditions'] = (@(foreach ($x in ($state + $trigger)) { (R1I $x "^(while|when|during|upon|on|every|after|before|if|once|at)$wsp+" '') }) -join '; ')
    }
    if ($null -ne $subject -and (RT $subject '\S')) { $p['Specification Target'] = R1 $subject '^(?i:the|each|every|all|any|a|an)[\t\n\x0B\f\r ]+' ''; $p['_subject'] = $subject }
    $neg = ''; $nm = RxI $post "^not$wsp+"; if ($nm.Success) { $neg = 'not '; $post = $post.Substring($nm.Length) }
    $tv = $null
    $vm = RxI $post "^(be$wsp+capable$wsp+of|be$wsp+able$wsp+to|have$wsp+the$wsp+(?:capability|ability)$wsp+to)$wsp+"
    if ($vm.Success) { $tv = RR (LcA $vm.Groups[1].Value) "$wsp+" ' '; $post = $post.Substring($vm.Length) }
    else { $vm = Rx $post "^([A-Za-z0-9_]+)$wsp*"; if ($vm.Success) { $tv = LcA $vm.Groups[1].Value; $post = $post.Substring($vm.Length) } }
    if ($null -ne $tv) {
        $p['Target Verb'] = $neg + $tv
        $p['_verb'] = $tv
        if ($tv -ceq 'be') { $pm = RxI $post '^([A-Za-z0-9_]+(?:ed|en)|kept|made|held|sent|built|set|put|found|shown|done|led|run|met|paid|brought|caught|left|lost|split|cut|shut|spread)\b'; if ($pm.Success) { $p['_passive'] = $pm.Groups[1].Value } }
        if ($tv -cmatch '^(?:be capable of|be able to|have the \w+ to)$') { $im = Rx $post '^([A-Za-z0-9_]+)'; if ($im.Success) { $p['_inner_verb'] = LcA $im.Groups[1].Value } }
    }
    $am = RxI $post ",?$wsp*\bin$wsp+accordance$wsp+with$wsp+(.*?)(?=,?$wsp*\bexcept\b|$)"
    if ($am.Success) {
        $spec = $am.Groups[1].Value; $post = $post.Substring(0, $am.Index) + $post.Substring($am.Index + $am.Length)
        $sm = RxI $spec ("$wsp*\b(?:Section|Sec\.?|para(?:graph)?\.?|" + [char]0xC2 + [char]0xA7 + ")$wsp*(\d+(?:\.\d+)*)\b")
        if ($sm.Success) { $p['Section Number'] = $sm.Groups[1].Value; $spec = $spec.Substring(0, $sm.Index) + $spec.Substring($sm.Index + $sm.Length) }
        $dm = Rx $spec "$wsp*\(([A-Za-z0-9][\w\-.\/]*\d[\w\-.\/]*)\)"
        if ($dm.Success) { $p['Document Number'] = $dm.Groups[1].Value; $spec = $spec.Substring(0, $dm.Index) + $spec.Substring($dm.Index + $dm.Length) }
        $spec = RRI $spec "^$wsp*(the$wsp+)?|$wsp*[,.]?$wsp*$" ''
        if ($spec -ne '') { $p['Specification'] = $spec }
    }
    $xm = RxI $post ",?$wsp*\bexcept\b$wsp*(.*)$"
    if ($xm.Success) { $exc += $xm.Groups[1].Value; $post = $post.Substring(0, $xm.Index) }
    if ($exc.Count) { $p['Exception(s)'] = (@(foreach ($x in $exc) { RR $x '[,.\t\n\x0B\f\r ]+$' '' }) -join '; ') }
    $post = RR $post '[,\t\n\x0B\f\r ]+$' ''
    $obj = $post; $mods = @()
    $mm = RxI $post "^(.+?)$wsp+\b($($script:MODRE))\b$wsp+(.*)$"
    if ($mm.Success) {
        $obj = $mm.Groups[1].Value; $kw = LcA $mm.Groups[2].Value; $rest = $mm.Groups[3].Value
        while ($null -ne $kw) {
            $m2 = RxI $rest "^(.+?)$wsp+\b($($script:MODRE))\b$wsp+(.*)$"
            if ($m2.Success) { $mods += , @($kw, $m2.Groups[1].Value); $kw = LcA $m2.Groups[2].Value; $rest = $m2.Groups[3].Value }
            else { $mods += , @($kw, $rest); $kw = $null }
        }
    }
    $obj = RR $obj '[,\t\n\x0B\f\r ]+$' ''
    if (RT $obj '\S') { $p['Precise Object(s)'] = $obj }
    if ($mods.Count) { $p['Modifier(s)'] = (@(foreach ($x in $mods) { $x[0] }) -join '; '); $p['Modification(s)'] = (@(foreach ($x in $mods) { $x[1] }) -join '; ') }
    $p['_main'] = $s
    $p
}

# ---------------------------------------------------------------- grade
function HasPart($v) { if ($null -eq $v) { return $false }; if ($v -is [array]) { return $v.Count -gt 0 }; RT ([string]$v) '\S' }
function Grade($r, $o) {
    $p = Parse $r.text
    if ($null -eq $p['Requirement ID'] -and $null -ne $r.id -and $r.id -ne '') { $p['Requirement ID'] = $r.id }
    if ($null -eq $p['Classification'] -and $null -ne $r.class) { $p['Classification'] = $r.class }
    if ($r.tags -and @($r.tags).Count) { $p['Requirement Tags'] = @($p['Requirement Tags'] | Where-Object { $null -ne $_ }) + @(foreach ($x in $r.tags) { UcA $x }) }
    $missing = @(); $f = NewL
    $req = $script:REQUIRED; if ($o.require_class) { $req = @('Classification') + $req }
    foreach ($k in $req) { if (-not (HasPart $p[$k])) { $missing += $k } }
    $add = { param($sev, $msg) LAdd $f @{ sev = $sev; msg = $msg } }
    $tv = if ($null -ne $p['_verb']) { $p['_verb'] } else { '' }
    if ($tv -cmatch '^(be capable of|be able to|have the \w+ to)$') {
        & $add 'major' ("weak target verb '$tv'" + $(if ($null -ne $p['_inner_verb']) { " $($p['_inner_verb'])" } else { '' }) + ": state the action itself ('shall " + $(if ($null -ne $p['_inner_verb']) { $p['_inner_verb'] } else { 'VERB' }) + "'), with its threshold")
    } elseif ($script:WEAK.ContainsKey($tv)) {
        if (-not ($tv -ceq 'be' -and $p['_passive'])) { & $add 'major' "weak target verb '$tv' ($($script:WEAK[$tv])): rarely verifiable -- name the concrete action (send, store, measure, report ...)" }
    }
    if ($p['_passive']) { & $add 'minor' "passive voice 'shall be $($p['_passive'])': make the specification target the one that acts" }
    $ops = @($p['_ops'])
    if ($ops.Count -gt 1) { & $add 'major' "$($ops.Count) operative verbs ($($ops -join ', ')): one requirement per statement -- split it" }
    $sent = if ($null -ne $p['_sentences']) { $p['_sentences'] } else { 1 }
    if ($sent -gt 1) { & $add 'major' "$($p['_sentences']) sentences: a requirement is a single sentence (move the rest to a Note: or a new requirement)" }
    $op = if ($null -ne $p['Operative Verb']) { $p['Operative Verb'] } else { '' }
    if ($op -ceq 'must') { & $add 'info' "'must' as the operative verb: the recipe uses shall (requisite), will, should or may" }
    if ($op -ceq 'will') { & $add 'info' "'will' states a fact about an external actor, not a requirement on the specification target" }
    if ($op -ceq 'should') { & $add 'info' "'should' is a design guideline, not a requirement" }
    if ($op -ceq 'may') { & $add 'info' "'may' grants permission (design space), not a requirement" }
    $main = if ($null -ne $p['_main']) { $p['_main'] } else { '' }
    $am = RxI $main '\b(?:shall|will|should|may|must)\b(.*)$'; $after = if ($am.Success) { $am.Groups[1].Value } else { '' }
    $iv = if ($null -ne $p['_inner_verb']) { $p['_inner_verb'] } else { '' }
    if ($script:PERF_VERB.ContainsKey($tv) -or $script:PERF_VERB.ContainsKey($iv)) {
        if (-not ((RT $after '\d') -or (RTI $after '\b(within|every|per|at least|no more than|less than|twice|once|hourly|daily)\b'))) {
            & $add 'minor' "'$tv' with no measurable threshold (a number with a unit, within, every, at least, no more than ...)"
        }
    }
    if ($null -ne $p['Specification'] -and ($null -eq $p['Document Number'] -or $null -eq $p['Section Number'])) {
        $what = @(); if ($null -eq $p['Document Number']) { $what += 'a document number' }; if ($null -eq $p['Section Number']) { $what += 'a section' }
        & $add 'minor' ("a reference without " + ($what -join ' or ') + ": cite both")
    }
    foreach ($v in $script:VAGUE) {
        $re = (@(foreach ($w in $v.Split(' ')) { [regex]::Escape($w) }) -join '[\t\n\x0B\f\r ]+')
        if (RTI $main ('(?<![\w-])' + $re + '(?![\w-])')) { & $add 'minor' "vague wording '$v': replace it with a measurable criterion" }
    }
    foreach ($t in @($p['Requirement Tags'])) { if ($null -eq $t) { continue }; if (-not $script:KNOWN_TAG.ContainsKey($t)) { & $add 'minor' ("unknown tag '$t' (known: " + ((SortedKeys $script:KNOWN_TAG) -join ', ') + ")") } }
    $fail = NewH
    if ($o.links) {
        $ix = $o.links
        $lk = if ($null -ne $r.link) { $r.link } else { NewH }
        $id = if ($null -ne $p['Requirement ID']) { $p['Requirement ID'] } elseif ($null -ne $r.id) { $r.id } else { '' }
        $e = @{ parents = @(); children = 0; satisfiers = @(); cases = @() }
        foreach ($k in @($r.name, $id, $r.id)) {
            if ($null -eq $k -or $k -eq '' -or -not $ix.ContainsKey($k)) { continue }
            $x = $ix[$k]
            $e.parents += $x.parents; $e.satisfiers += $x.satisfiers; $e.cases += $x.cases; $e.children += $x.children
        }
        $s = NewH; foreach ($fn in 'parents', 'satisfiers', 'cases') { $e[$fn] = @(foreach ($x in $e[$fn]) { if (-not $s.ContainsKey("$x`0")) { $s["$x`0"] = 1; $x } }) }
        $nameS = if ($null -ne $r.name) { $r.name } else { '' }; $pkgS = if ($null -ne $r.pkg) { $r.pkg } else { '' }
        $top = $false
        if (@($o.top).Count) { foreach ($t in $o.top) { if ((RT $id $t) -or (RT $nameS $t) -or (RT $pkgS $t)) { $top = $true; break } } }
        else { $lv = if ($null -ne $lk['level']) { $lk['level'] } else { '' }; $top = (RTI $lv '^top') -or (RTI $pkgS 'stakeholder|\bneeds\b') }
        if ($e.parents.Count) { $p['Parent Trace'] = $e.parents -join ', ' }
        elseif ($null -ne $lk['derived_from'] -and (RT $lk['derived_from'] '\S')) {
            $p['Parent Trace'] = "derived from $($lk['derived_from'])"
            & $add 'info' "derived requirement (from $($lk['derived_from'])): it needs its own review, not a parent's"
        }
        elseif ($top) { $p['Parent Trace'] = '(top level)' }
        else { $missing += 'Parent Trace'; $fail['orphan'] = 1 }
        if ($top -and -not $e.children -and -not $e.satisfiers.Count) {
            & $add 'minor' 'childless: a top-level requirement with no derived requirement and nothing that satisfies it'; $fail['childless'] = 1
        }
        $rat = $lk['rationale']
        if ($null -ne $rat -and (RT $rat '\S')) {
            $p['Rationale'] = $rat
            if ((RT $main '\d') -and -not (RTI $rat '\b(budget|allocat\w*|analys[ie]s|trade|study|standard|direction|directed|specif\w*|measured|survey|test(?:ed)?)\b') -and -not (RT $rat '\b[A-Z][A-Z0-9]*[-_][A-Z0-9][\w-]*\b')) {
                & $add 'minor' 'unjustified threshold: the statement has a number and the rationale names no source (a budget, an analysis, a trade study, a standard, a direction, or an id)'
                $fail['unjustified'] = 1
            }
        } else {
            $missing += 'Rationale'
            if (RT $main '\d') { $fail['unjustified'] = 1 }
        }
        $m = $lk['method']
        if ($null -ne $m -and (RT $m '\S')) {
            if ($script:METHOD.ContainsKey((LcA $m))) { $p['Verification Method'] = $script:METHOD[(LcA $m)] }
            else { $p['Verification Method'] = $m; & $add 'major' "verification method '$m': use Test, Analysis, Demonstration or Inspection"; $fail['unverified'] = 1 }
        } elseif ($op -ceq 'shall') { $missing += 'Verification Method'; $fail['unverified'] = 1 }
        if ($e.cases.Count) { $p['Verification Case'] = $e.cases -join ', ' }
        elseif ($op -ceq 'shall') {
            $fail['unverified'] = 1
            if ($o.baseline) { $missing += 'Verification Case' } else { & $add 'info' 'no verification case yet (required by the baseline; --baseline makes it missing)' }
        }
        if ($e.satisfiers.Count) { $p['Satisfied By'] = $e.satisfiers -join ', ' }
        elseif (-not $top) {
            $fail['unsatisfied'] = 1
            if ($o.baseline) { $missing += 'Satisfied By' } else { & $add 'info' 'nothing satisfies it yet (required by the design baseline; --baseline makes it missing)' }
        }
        $safety = @(foreach ($t in @($p['Requirement Tags'])) { if ($t -cmatch '^(SC|SR)$') { $t } })
        if ($safety.Count -and -not @($lk['hazards'] | Where-Object { $null -ne $_ }).Count) {
            & $add 'major' "unmitigated safety tag ($($safety[0])): link the hazard it mitigates (attribute hazard = `"HAZ-...`")"; $fail['unmitigated'] = 1
        }
        $note = if ($null -ne $p['Informational Statement(s)']) { $p['Informational Statement(s)'] } else { '' }
        if (RTI $note '\b(because|rationale|so that we|verified by|verification|will be tested|to be tested)\b') {
            & $add 'minor' 'the Note: carries a rationale or the verification approach: move it to the Rationale or Verification field'
        }
    }
    $fs = LArr $f
    $score = 100 - $script:SEV_COST.missing * $missing.Count
    foreach ($x in $fs) { $score -= $script:SEV_COST[$x.sev] }
    if ($score -lt 0) { $score = 0 }
    $g = @{}; foreach ($k in $r.Keys) { $g[$k] = $r[$k] }
    $g.id = if ($null -ne $p['Requirement ID']) { $p['Requirement ID'] } elseif ($null -ne $r.id) { $r.id } else { '?' }
    $g.parts = $p; $g.missing = $missing; $g.findings = $fs; $g.score = $score; $g.link_fail = $fail
    $g
}

# ---------------------------------------------------------------- output
function PartText($v) { if ($v -is [array]) { $v -join ', ' } else { [string]$v } }
function ToText($g) {
    $o = @()
    foreach ($r in $g) {
        $o += "$($r.id)  score $($r.score)  $($r.file):$($r.line)" + $(if ($null -ne $r.title) { "  ($($r.title))" } else { '' }) + "`n"
        $o += "  $($r.text)`n"
        $keys = $script:RECIPE_PARTS; if ($script:LINKS) { $keys = $keys + $script:LINK_PARTS }
        foreach ($k in $keys) {
            $v = $r.parts[$k]
            if ($null -eq $v -or ($v -is [array] -and $v.Count -eq 0)) { continue }
            $o += '    ' + (PadR $k 27) + ' ' + (PartText $v) + "`n"
        }
        if ($r.missing.Count) { $o += '    missing: ' + ($r.missing -join ', ') + "`n" }
        foreach ($x in $r.findings) { $o += '    ' + (PadR $x.sev 6) + ' ' + $x.msg + "`n" }
        $o += "`n"
    }
    -join $o
}
function Csvq($v) { if ($null -eq $v) { $v = '' }; '"' + ([string]$v).Replace('"', '""') + '"' }
function ToCsv($g) {
    $cols = $script:RECIPE_PARTS; if ($script:LINKS) { $cols = $cols + $script:LINK_PARTS }
    $o = @((@('id', 'score', 'missing', 'findings', 'file', 'line', 'text') + $cols) -join ',')
    foreach ($r in $g) {
        $vals = @($r.id, $r.score, ($r.missing -join '; '), (@(foreach ($x in $r.findings) { "$($x.sev): $($x.msg)" }) -join '; '), $r.file, $r.line, $r.text)
        foreach ($c in $cols) { $v = $r.parts[$c]; $vals += $(if ($null -ne $v) { PartText $v } else { '' }) }
        $o += (@(foreach ($v in $vals) { Csvq $v }) -join ',')
    }
    ($o -join "`r`n") + "`r`n"
}
function Xmlq($t) { if ($null -eq $t) { $t = '' }; ([string]$t).Replace('&', '&amp;').Replace('<', '&lt;').Replace('>', '&gt;').Replace('"', '&quot;') }
function ToJunit($g) {
    $bad = @($g | Where-Object { $_.missing.Count -or $_.findings.Count }).Count
    $o = "<?xml version=`"1.0`" encoding=`"UTF-8`"?>`n<testsuites>`n<testsuite name=`"requirement recipe`" tests=`"$(@($g).Count)`" failures=`"$bad`">`n"
    foreach ($r in $g) {
        $o += "  <testcase classname=`"recipe`" name=`"" + (Xmlq "$($r.id)") + "`" file=`"" + (Xmlq $r.file) + "`">"
        if ($r.missing.Count -or $r.findings.Count) {
            $m = @(foreach ($x in $r.missing) { "missing: $x" }) + @(foreach ($x in $r.findings) { "$($x.sev): $($x.msg)" })
            $o += "`n    <failure message=`"" + (Xmlq "score $($r.score): $($m[0])") + "`">" + (Xmlq ((@($r.text) + $m) -join "`n")) + "</failure>`n  "
        }
        $o += "</testcase>`n"
    }
    $o + "</testsuite>`n</testsuites>`n"
}
function Jstr($t) {
    if ($null -eq $t) { $t = '' }
    $t = ([string]$t).Replace('\', '\\').Replace('"', '\"').Replace("`n", '\n').Replace("`t", '\t')
    if ($t -cmatch '[\x00-\x1f]') { $t = -join @(foreach ($ch in $t.ToCharArray()) { if ([int]$ch -lt 0x20) { '\u{0:x4}' -f [int]$ch } else { [string]$ch } }) }
    '"' + $t + '"'
}
function ToCodequality($g) {
    $items = @(); $CQ = @{ missing = 'major'; major = 'major'; minor = 'minor'; info = 'info' }
    foreach ($r in $g) {
        $m = @(foreach ($x in $r.missing) { , @('missing', "missing required part: $x") }) + @(foreach ($x in $r.findings) { , @($x.sev, $x.msg) })
        foreach ($x in $m) {
            $desc = "$($r.id): $($x[1])"
            $items += '  {"description": ' + (Jstr $desc) + ', "check_name": "requirement-recipe", "fingerprint": ' + (Jstr (Md5Hex "$($r.file)`0$($r.id)`0$($x[1])")) +
                ', "severity": ' + (Jstr $CQ[$x[0]]) + ', "location": {"path": ' + (Jstr $r.file) + ', "lines": {"begin": ' + [long]$r.line + '}}}'
        }
    }
    "[`n" + ($items -join ",`n") + $(if ($items.Count) { "`n" } else { '' }) + "]`n"
}
function Totals($g) { $f = 0; $m = 0; foreach ($r in $g) { $f += $r.findings.Count; $m += $r.missing.Count }; @(@($g).Count, $f, $m) }

# ---------------------------------------------------------------- main
function Main($argv) {
    $g = GetOpt $argv @('format=s', 'require=s@', 'strict', 'tag=s@', 'only=s@', 'o=s', 'links', 'baseline', 'top=s@', 'help|h')
    if (-not $g.ok) { ErrLines $g.err; ErrLines $script:USAGE; $script:RC = 2; return }
    $o = $g.opts; $args1 = @($g.args)
    if (-not $o.ContainsKey('format')) { $o['format'] = 'text' }
    if ($o['help']) { OutLines $script:USAGE; $script:RC = 0; return }
    if ($args1.Count -eq 0) { ErrLines $script:USAGE; $script:RC = 2; return }
    if ($o['format'] -cnotmatch '^(text|csv|junit|codequality)$') { ErrLines "req-recipe: --format is text, csv, junit or codequality, not '$($o['format'])'"; $script:RC = 2; return }
    foreach ($r in @($o['require'])) { if ($null -ne $r -and $r -cne 'classification') { ErrLines "req-recipe: --require takes 'classification', not '$r'"; $script:RC = 2; return } }
    foreach ($t in @($o['tag'])) { if ($null -ne $t) { $script:KNOWN_TAG[(UcA $t)] = 1 } }
    $tops = @($o['top'] | Where-Object { $null -ne $_ })
    if (($o['baseline'] -or $tops.Count) -and -not $o['links']) { ErrLines 'req-recipe: --baseline and --top go with --links'; $script:RC = 2; return }
    foreach ($t in $tops) { try { $null = New-Object regex ($t, $script:RX) } catch { ErrLines "req-recipe: --top '$t' is not a valid regular expression"; $script:RC = 2; return } }
    $script:LINKS = [bool]$o['links']
    $reqs = @()
    foreach ($in in $args1) {
        try { $got = ReadInput $in } catch { $e = RR $_.Exception.Message '[\t\n\x0B\f\r ]+$' ''; ErrLines "req-recipe: $e"; $script:RC = 2; return }
        $reqs += @($got)
    }
    $only = @($o['only'] | Where-Object { $null -ne $_ })
    if ($only.Count) { $w = NewH; foreach ($x in $only) { $w[$x] = 1 }; $reqs = @($reqs | Where-Object { $w.ContainsKey($(if ($null -ne $_.id) { $_.id } else { '' })) }) }
    $idx = if ($o['links']) { LinkIndex $args1 $reqs } else { $null }
    $reqCls = 0; foreach ($x in @($o['require'])) { if ($x -ceq 'classification') { $reqCls++ } }
    $graded = @(foreach ($r in $reqs) { Grade $r @{ require_class = $reqCls; links = $idx; baseline = $o['baseline']; top = $tops } })
    $out = switch ($o['format']) { 'csv' { ToCsv $graded } 'junit' { ToJunit $graded } 'codequality' { ToCodequality $graded } default { ToText $graded } }
    $t = Totals $graded
    $summary = "requirements=$($t[0]) findings=$($t[1]) missing=$($t[2])`n"
    if ($o['links']) { $summary = (LinkCounts $graded) + $summary }
    if ($null -ne $o['o']) {
        try { WriteBytes $o['o'] $out } catch { ErrLines "req-recipe: cannot write $($o['o']): $($_.Exception.Message)"; $script:RC = 2; return }
        OutLines $summary
    } else {
        OutLines $out
        if ($o['format'] -ceq 'text') { OutLines $summary } else { ErrLines $summary }
    }
    $script:RC = $(if ($o['strict'] -and ($t[1] -or $t[2])) { 1 } else { 0 })
}

$script:RC = 0
Main $args
if ($PSCommandPath) { exit $script:RC }
$global:LASTEXITCODE = $script:RC
