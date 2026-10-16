<#
idef0.ps1 -- the agile kit's idef0.pl (tools/idef0) in Windows PowerShell 5.1, Constrained Language Mode safe:
validator, formatter and plate renderer for the pipe-path IDEF0 DSL. Same commands, same output, same exit codes.

  powershell -ExecutionPolicy Bypass -File idef0.ps1 COMMAND [ARGS] [--out FILE]

--out FILE (this port only) writes stdout to FILE as UTF-8 without a BOM, LF line ends, byte for byte what
idef0.pl prints. Use it for html/svg/text/fmt: Windows PowerShell's '>' writes UTF-16, which browsers and the
kit's other tools do not expect.
#>
$ErrorActionPreference = 'Stop'
$script:CLIARGS = @($args)
$script:USAGE = @'
idef0 -- validator, formatter, and plate renderer for the pipe-path IDEF0 DSL.

Usage:
  idef0 lint  FILE...              validate; GNU-format diagnostics; exit 1 on errors
  idef0 text  FILE...              render plates as character art, form-feed paginated
  idef0 html  FILE...              render HTML drawing set (plates as SVG)
  idef0 svg   NODE FILE...         render one plate (e.g. E22) as standalone SVG
  idef0 dump  FILE...              print numbered model tree(s)
  idef0 links FILE...              print project interface table
  idef0 fmt [--number|--auto] [--write] FILE...
                                   rewrite tag suffixes; --write edits in place
                                   (fmt validates structure only, not links)

Grammar summary (v1):
  line := tag name [< path | > path]     tag := [taicom]( # | digit | LETTER | NUM. )
  path := segment (| segment)*           ; comment lines start with ;
Segment resolution order: child activity by name -> port by flow name
(2+ matches = ambiguous error) -> port ref [icom]N -> node number.
A '<' path ending at an activity with exactly one output takes that output.

Diagnostics use GNU format  file:line: severity: message.
Exit status: 0 clean, 1 errors found, 2 usage failure.
'@ -replace "`r", ''
$script:USAGE += "`n"

# ================================================================ output (stdout buffer, stderr, bytes)
$script:OB = @{}; $script:ON = 0
function P([string]$s) { $script:OB[$script:ON] = $s; $script:ON++ }        # print to stdout (buffered)
function PErr([string]$s) {                                                  # print to stderr (Write-Host: never redirected)
    if ($s.EndsWith("`n")) { $s = $s.Substring(0, $s.Length - 1) }
    foreach ($l in ($s -split "`n")) { Write-Host $l }
}
function Utf8([string]$s) {                                                  # UTF-8 bytes without .NET encoders (CLM)
    $cs = $s.ToCharArray(); $n = $cs.Length
    $out = for ($i = 0; $i -lt $n; $i++) {
        $o = [int]$cs[$i]
        if ($o -lt 0x80) { $o; continue }
        if ($o -ge 0xD800 -and $o -le 0xDBFF -and $i + 1 -lt $n) {
            $lo = [int]$cs[$i + 1]
            if ($lo -ge 0xDC00 -and $lo -le 0xDFFF) {
                $i++; $cp = 0x10000 + (($o - 0xD800) -shl 10) + ($lo - 0xDC00)
                0xF0 -bor ($cp -shr 18); 0x80 -bor (($cp -shr 12) -band 0x3F); 0x80 -bor (($cp -shr 6) -band 0x3F); 0x80 -bor ($cp -band 0x3F)
                continue
            }
        }
        if ($o -lt 0x800) { 0xC0 -bor ($o -shr 6); 0x80 -bor ($o -band 0x3F); continue }
        0xE0 -bor ($o -shr 12); 0x80 -bor (($o -shr 6) -band 0x3F); 0x80 -bor ($o -band 0x3F)
    }
    , [byte[]]@($out)
}
function WriteText([string]$path, [string]$text) {                          # exact bytes: UTF-8, no BOM, LF as given
    if ($text -cmatch '^[\x00-\x7F]*$') { Set-Content -LiteralPath $path -Value $text -Encoding ASCII -NoNewline }
    else { Set-Content -LiteralPath $path -Value (Utf8 $text) -Encoding Byte }
}
function ReadText([string]$path) {
    $t = Get-Content -LiteralPath $path -Raw -Encoding UTF8
    if ($null -eq $t) { return '' }
    $t
}
function Flush([string]$outFile) {
    $parts = @(for ($i = 0; $i -lt $script:ON; $i++) { $script:OB[$i] })
    $text = $parts -join ''
    $script:OB = @{}; $script:ON = 0
    if ($outFile) { WriteText $outFile $text; return }
    if ($text -eq '') { return }
    if ($text.EndsWith("`n")) { $text = $text.Substring(0, $text.Length - 1) }
    foreach ($l in ($text -split "`n")) { Write-Output $l }
}

# ================================================================ helpers
function NewH { , [hashtable]::new([System.StringComparer]::Ordinal) }       # case-sensitive, like a Perl hash
function Strip([string]$s) { ($s -creplace '^\s+', '') -creplace '\s+\z', '' }
function RStrip([string]$s) { $s -creplace '\s+\z', '' }
function Esc([string]$s) { $s.Replace('&', '&amp;').Replace('<', '&lt;').Replace('>', '&gt;').Replace('"', '&quot;').Replace("'", '&#x27;') }
function IsDigits([string]$s) { $s -ne '' -and $s -cmatch '^\d+\z' }
function Lj([string]$s, [int]$w) { $n = $w - $s.Length; if ($n -gt 0) { $s + (' ' * $n) } else { $s } }
function Max2($a, $b) { if ($a -ge $b) { $a } else { $b } }
function Min2($a, $b) { if ($a -le $b) { $a } else { $b } }
function MaxL($xs) { $m = $null; foreach ($x in $xs) { if ($null -eq $m -or $x -gt $m) { $m = $x } }; $m }
function MinL($xs) { $m = $null; foreach ($x in $xs) { if ($null -eq $m -or $x -lt $m) { $m = $x } }; $m }
function AbsN($x) { if ($x -lt 0) { -$x } else { $x } }
function Trunc($x) { $d = [double]$x; $r = [long]$d; if ($d -ge 0) { if ($r -gt $d) { $r-- } } else { if ($r -lt $d) { $r++ } }; $r }   # Perl int()
function Cmp([string]$a, [string]$b) { $c = [string]::CompareOrdinal($a, $b); if ($c -lt 0) { -1 } elseif ($c -gt 0) { 1 } else { 0 } }
function NumCmp($a, $b) { if ($a -lt $b) { -1 } elseif ($a -gt $b) { 1 } else { 0 } }
function SortBy($items, [scriptblock]$cmp) {                                 # stable merge sort; $cmp gets ($x, $y) -> -1/0/1
    $a = @($items); $n = $a.Count
    if ($n -lt 2) { return , $a }
    $w = 1
    while ($w -lt $n) {
        $out = New-Object object[] $n; $k = 0
        for ($lo = 0; $lo -lt $n; $lo += 2 * $w) {
            $mid = Min2 ($lo + $w) $n; $hi = Min2 ($lo + 2 * $w) $n; $i = $lo; $j = $mid
            while ($i -lt $mid -and $j -lt $hi) {
                if ((& $cmp $a[$j] $a[$i]) -lt 0) { $out[$k] = $a[$j]; $j++ } else { $out[$k] = $a[$i]; $i++ }
                $k++
            }
            while ($i -lt $mid) { $out[$k] = $a[$i]; $i++; $k++ }
            while ($j -lt $hi) { $out[$k] = $a[$j]; $j++; $k++ }
        }
        $a = $out; $w *= 2
    }
    , $a
}
function SortStr($items) { SortBy $items { param($x, $y) Cmp $x $y } }
function Hex([int]$n, [int]$w) { $h = '{0:x}' -f $n; while ($h.Length -lt $w) { $h = '0' + $h }; $h }

function PyRepr([string]$s) {                                                # Python repr() of a str
    $q = "'"; if ($s.Contains("'") -and -not $s.Contains('"')) { $q = '"' }
    $o = ''
    foreach ($c in $s.ToCharArray()) {
        $n = [int]$c; $cs = [string]$c
        if ($cs -ceq '\') { $o += '\\' }
        elseif ($cs -ceq $q) { $o += '\' + $q }
        elseif ($n -eq 9) { $o += '\t' }
        elseif ($n -eq 10) { $o += '\n' }
        elseif ($n -eq 13) { $o += '\r' }
        elseif ($n -lt 0x20 -or ($n -ge 0x7f -and $n -le 0xa0) -or $n -eq 0xad) { $o += '\x' + (Hex $n 2) }
        else { $o += $cs }
    }
    "$q$o$q"
}
function PyJsonStr([string]$s) {                                             # json.dumps(str), ensure_ascii
    $sb = @{}; $k = 0; $sb[$k++] = '"'
    $cs = $s.ToCharArray()
    foreach ($c in $cs) {
        $n = [int]$c
        if ($n -eq 34) { $sb[$k++] = '\"' }
        elseif ($n -eq 92) { $sb[$k++] = '\\' }
        elseif ($n -eq 10) { $sb[$k++] = '\n' }
        elseif ($n -eq 13) { $sb[$k++] = '\r' }
        elseif ($n -eq 9) { $sb[$k++] = '\t' }
        elseif ($n -eq 8) { $sb[$k++] = '\b' }
        elseif ($n -eq 12) { $sb[$k++] = '\f' }
        elseif ($n -ge 0x20 -and $n -le 0x7e) { $sb[$k++] = [string]$c }
        else { $sb[$k++] = '\u' + (Hex $n 4) }                                 # UTF-16 units: surrogates come out as pairs, as Python's
    }
    $sb[$k++] = '"'
    (@(for ($i = 0; $i -lt $k; $i++) { $sb[$i] })) -join ''
}
function SplitLines([string]$t) {
    if ($t -eq '') { return , @() }
    $l = [regex]::Split($t, ("\r\n|[\n\r\x0b\x0c\x1c\x1d\x1e\x85" + [string][char]0x2028 + [string][char]0x2029 + "]"))
    if ($l.Count -and $l[$l.Count - 1] -ceq '') { $l = @($l | Select-Object -First ($l.Count - 1)) }
    , @($l)
}

# ================================================================ difflib (exact port)
function Ratio([string]$a, [string]$b) {                                     # a = candidate, b = word
    $CA = $a.ToCharArray(); $CB = $b.ToCharArray()
    $b2j = NewH
    for ($j = 0; $j -lt $CB.Count; $j++) { $chs = [string]$CB[$j]; if (-not $b2j.ContainsKey($chs)) { $b2j[$chs] = @() }; $b2j[$chs] += $j }
    if ($CB.Count -ge 200) {
        $ntest = (Trunc ($CB.Count / 100)) + 1
        foreach ($key in @($b2j.Keys)) { if ($b2j[$key].Count -gt $ntest) { $b2j.Remove($key) } }
    }
    $m = 0
    $q = @(, @(0, $CA.Count, 0, $CB.Count))
    while ($q.Count) {
        $top = $q[$q.Count - 1]
        $q = @(for ($z = 0; $z -lt $q.Count - 1; $z++) { , $q[$z] })
        $alo = $top[0]; $ahi = $top[1]; $blo = $top[2]; $bhi = $top[3]
        $bi = $alo; $bj = $blo; $bs = 0
        $j2len = @{}
        for ($i = $alo; $i -lt $ahi; $i++) {
            $new = @{}
            $js = $b2j[[string]$CA[$i]]
            if ($null -ne $js) {
                foreach ($jj in $js) {
                    if ($jj -lt $blo) { continue }
                    if ($jj -ge $bhi) { break }
                    $prev = $j2len[$jj - 1]; if ($null -eq $prev) { $prev = 0 }
                    $kk = $prev + 1; $new[$jj] = $kk
                    if ($kk -gt $bs) { $bi = $i - $kk + 1; $bj = $jj - $kk + 1; $bs = $kk }
                }
            }
            $j2len = $new
        }
        while ($bi -gt $alo -and $bj -gt $blo -and $CA[$bi - 1] -ceq $CB[$bj - 1]) { $bi--; $bj--; $bs++ }
        while ($bi + $bs -lt $ahi -and $bj + $bs -lt $bhi -and $CA[$bi + $bs] -ceq $CB[$bj + $bs]) { $bs++ }
        if ($bs) {
            $m += $bs
            if ($alo -lt $bi -and $blo -lt $bj) { $q += , @($alo, $bi, $blo, $bj) }
            if ($bi + $bs -lt $ahi -and $bj + $bs -lt $bhi) { $q += , @(($bi + $bs), $ahi, ($bj + $bs), $bhi) }
        }
    }
    $t = $CA.Count + $CB.Count
    if ($t) { 2.0 * $m / $t } else { 1.0 }
}
function CloseMatch([string]$word, $poss, [double]$cutoff) {
    $bs = $null; $bx = $null
    foreach ($x in $poss) {
        $r = Ratio $x $word
        if ($r -lt $cutoff) { continue }
        if ($null -eq $bs -or $r -gt $bs -or ($r -eq $bs -and (Cmp $x $bx) -gt 0)) { $bs = $r; $bx = $x }
    }
    $bx
}

# ================================================================ nodes
$script:UID = 0
function NewNode($h) {
    $n = @{}
    foreach ($k in $h.Keys) { $n[$k] = $h[$k] }
    $n.doc = @(); $n.trail = $null; $n.parent = $null; $n.children = @(); $n.ports = @(); $n.number = $null
    $n.letter = $null; $n.node_id = $null; $n.asserted = $null; $n.link_target = $null; $n.model = $null
    $script:UID++; $n.uid = $script:UID
    $n
}
function IsAct($n) { $n.tag -ceq 't' -or $n.tag -ceq 'a' }
function Desc($n) { foreach ($k in $n.children) { $k; Desc $k } }
function AllPorts($n) { foreach ($p in $n.ports) { $p }; foreach ($k in $n.children) { AllPorts $k } }
function HasLink($p) { $null -ne $p.link_dir -and $p.link_dir -ne '' }
function Same($a, $b) { $null -ne $a -and $null -ne $b -and $a.uid -eq $b.uid }

$script:DIAGS = @(); $script:DSEQ = 0
function Err($w, [string]$msg, [string]$sev = 'error') {
    if ($w -is [hashtable]) { $f = $w.fname; $l = $w.line } else { $f = $w[0]; $l = $w[1] }
    $script:DIAGS += , @($f, $l, $sev, $msg, $script:DSEQ); $script:DSEQ++
}

# ================================================================ parsing
$script:FENCE_OPEN = '^(`{3,})\s*idef0\s*$'
$script:FENCE_CLOSE = '^`{3,}\s*$'
$script:TAG_RE = '^([ \t]*)([taicom])(#|[A-Za-z]?\d+\.|[A-Za-z]?\d*)(?:\s+(.*))?$'
$script:INDENT = 2

function ParseFile([string]$fname, [string]$text, $doc) {
    $roots = @(); $stack = @(); $last = $null
    $isMd = $fname.ToLower() -cmatch '\.(?:md|markdown)\z'
    $inFence = -not $isMd
    $fenceLen = 0; $fenceLine = 0
    $rec = @()
    $lines = SplitLines $text
    for ($ix = 0; $ix -lt $lines.Count; $ix++) {
        $lineno = $ix + 1
        $raw = $lines[$ix]
        if ($isMd) {
            if (-not $inFence) {
                $m = [regex]::Match($raw, $script:FENCE_OPEN)
                if ($m.Success) { $inFence = $true; $fenceLen = $m.Groups[1].Value.Length; $fenceLine = $lineno }
                $rec += , @('raw', $raw, $null); continue
            }
            if ($raw -cmatch $script:FENCE_CLOSE -and (Strip $raw).Length -ge $fenceLen) {
                $inFence = $false; $rec += , @('raw', $raw, $null); continue
            }
        }
        $st = Strip $raw
        $two = if ($st.Length -ge 2) { $st.Substring(0, 2) } else { $st }
        if ($two -ceq ';;' -or $two -ceq '##') {
            $txt = Strip $st.Substring(2)
            if ($null -eq $last) {
                Err @($fname, $lineno) ("'" + $two + "' doc comment has no element line to attach to") 'warning'
            } else {
                $last.doc += $(if ($txt -ne '') { $txt } else { '\n' })
            }
            $rec += , @('raw', $raw, $null); continue
        }
        if ($st -eq '' -or $st -cmatch '^[;#]') { $rec += , @('raw', $raw, $null); continue }
        $trail = $null; $code = $raw
        $tm = [regex]::Match($raw, '\s(#.*)$')
        if ($tm.Success) { $trail = $tm.Groups[1].Value; $code = $raw.Substring(0, $tm.Index) }
        $m = [regex]::Match($code, $script:TAG_RE)
        if (-not $m.Success) {
            Err @($fname, $lineno) ('cannot parse line: ' + (PyRepr $st))
            $rec += , @('raw', $raw, $null); continue
        }
        $ind = $m.Groups[1].Value; $tag = $m.Groups[2].Value; $suffix = $m.Groups[3].Value
        $rest = if ($m.Groups[4].Success) { $m.Groups[4].Value } else { '' }
        if ($ind.Contains("`t")) {
            Err @($fname, $lineno) 'tabs in indentation; use 2 spaces per level'
            $ind = $ind.Replace("`t", '  ')
        }
        if ($ind.Length % $script:INDENT) {
            Err @($fname, $lineno) ("indentation of " + $ind.Length + " is not a multiple of $($script:INDENT)")
        }
        $level = Trunc ($ind.Length / $script:INDENT)
        if ($suffix -eq '') { $suffix = '#' }
        $rest = Strip $rest
        $ldir = $null; $lpath = $null; $name = $rest
        $lm = [regex]::Match($rest, '([<>])')
        if ($lm.Success) {
            $ldir = $lm.Groups[1].Value
            $name = Strip $rest.Substring(0, $lm.Index)
            $pt = Strip $rest.Substring($lm.Index + 1)
            $lpath = @(foreach ($s in [regex]::Split($pt, '\|')) { Strip $s })
            foreach ($s in $lpath) { if ($s -eq '') { Err @($fname, $lineno) 'empty segment in link path'; break } }
        }
        if ($name.Contains('|')) {
            Err @($fname, $lineno) "'|' not allowed in a name (link paths follow < or >)"
            $name = $name.Replace('|', ' ')
        }
        if ($name -eq '') { Err @($fname, $lineno) "'$tag' line has no name" }
        $node = NewNode @{ tag = $tag; suffix = $suffix; name = $name; link_dir = $ldir; link_path = $lpath; fname = $fname; line = $lineno; indent = $ind.Length }
        $node.trail = $trail
        if ($null -ne $trail -and $trail.Length -ge 2 -and $trail.Substring(0, 2) -ceq '##') {
            $dt = Strip $trail.Substring(2)
            $node.doc += $(if ($dt -ne '') { $dt } else { '\n' })
        }
        $rec += , @('node', $raw, $node)
        $last = $node
        if ($tag -ceq 't') {
            if ($level -ne 0) { Err $node "model root 't' must be at indentation 0" }
            $roots += , $node
            $stack = @(, @(0, $node))
            continue
        }
        while ($stack.Count -and $stack[$stack.Count - 1][0] -ge $level) {
            $stack = @(for ($z = 0; $z -lt $stack.Count - 1; $z++) { , $stack[$z] })
        }
        if (-not $stack.Count) { Err $node "'$tag' line has no parent model/activity"; continue }
        $plevel = $stack[$stack.Count - 1][0]; $parent = $stack[$stack.Count - 1][1]
        if ($plevel -ne $level - 1) { Err $node "indentation jumps from level $plevel to $level" }
        $node.parent = $parent
        if ($tag -ceq 'a') {
            if (-not (IsAct $parent)) { Err $node 'activity nested under a port' }
            else { $parent.children += , $node; $stack += , @($level, $node) }
        } else {
            if (-not (IsAct $parent)) { Err $node 'port nested under a port' }
            else { $parent.ports += , $node }
        }
    }
    if ($isMd -and $inFence) { Err @($fname, $fenceLine) 'unclosed ```idef0 fence at end of file' 'warning' }
    $doc[$fname] = $rec
    , $roots
}

# ================================================================ numbering
function AssignNumbers($models) {
    $letters = NewH
    foreach ($t in $models) {
        $s = $t.suffix
        if ($s -ceq '#' -or $s -eq '') {
            $lm = [regex]::Match($t.name, '(\p{L})')
            $letter = if ($lm.Success) { $lm.Groups[1].Value.ToUpper() } else { 'X' }
        } elseif ($s.Length -eq 1 -and $s -cmatch '^\p{L}\z') {
            $letter = $s.ToUpper()
        } else {
            Err $t ('bad model suffix ' + (PyRepr $s) + ': use a single letter or #')
            $letter = 'X'
        }
        if ($letters.ContainsKey($letter)) {
            Err $t ("duplicate model letter '$letter' (also " + (PyRepr $letters[$letter].name) + ')')
        }
        $letters[$letter] = $t
        $t.letter = $letter; $t.node_id = $letter; $t.model = $t
        NumberChildren $t
        NumberPorts $t
        foreach ($p in $t.ports) { $p.model = $t }
        foreach ($a in @(Desc $t)) {
            $a.model = $t
            NumberPorts $a
            foreach ($p in $a.ports) { $p.model = $t }
        }
    }
    , $letters
}
function NumberChildren($act) {
    $kids = @($act.children)
    if ($kids.Count -gt 9) { Err $act 'more than 9 activities on one plate' }
    $pinned = @{}
    foreach ($k in $kids) {
        $s = $k.suffix
        $k.asserted = $null
        if ($s.EndsWith('.')) { $k.asserted = $s.Substring(0, $s.Length - 1); continue }
        if ($s -ne '' -and $s -cne '#' -and (IsDigits $s)) {
            if ($s.Length -ne 1 -or $s -ceq '0') { Err $k ('pinned number ' + (PyRepr $s) + ' must be a single digit 1-9'); continue }
            $d = [int]$s
            if ($pinned.ContainsKey($d)) {
                Err $k ("duplicate pinned digit $d on plate $($act.node_id) (also line $($pinned[$d].line))")
            } else { $pinned[$d] = $k; $k.number = $d }
        } elseif ($s -cne '#' -and $s -ne '' -and -not $s.EndsWith('.')) {
            Err $k ('bad activity suffix ' + (PyRepr $s))
        }
    }
    $nxt = 1
    foreach ($k in $kids) {
        if ($null -ne $k.number) { continue }
        while ($pinned.ContainsKey($nxt)) { $nxt++ }
        $k.number = $nxt; $pinned[$nxt] = $k; $nxt++
    }
    $base = if ($act.tag -ceq 'a') { $act.node_id } else { $act.letter }
    foreach ($k in $kids) {
        $k.node_id = "$base$($k.number)"
        if ($null -ne $k.asserted -and $k.asserted -ne '' -and $k.asserted -cne $k.node_id) {
            Err $k ("asserted number $($k.asserted) but position derives " + $k.node_id)
        }
        NumberChildren $k
    }
}
function NumberPorts($act) {
    $counts = NewH
    foreach ($p in $act.ports) {
        $s = $p.suffix; $n = $null
        if ($s.EndsWith('.')) { Err $p 'asserted numbers are for activities; ports take # or a digit' }
        elseif (IsDigits $s) {
            if ($s.Length -ne 1 -or $s -ceq '0') { Err $p ('pinned port number ' + (PyRepr $s) + ' must be a single digit 1-9') }
            else { $n = [int]$s }
        } elseif ($s -cne '#' -and $s -ne '') { Err $p ('bad port suffix ' + (PyRepr $s)) }
        $c = $counts[$p.tag]; if ($null -eq $c) { $c = 0 }
        if ($null -eq $n) { $n = $c + 1 }
        $counts[$p.tag] = Max2 $c $n
        $p.number = $n
        $p.node_id = "$($act.node_id).$($p.tag)$n"
        $ld = if ($null -eq $p.link_dir) { '' } else { $p.link_dir }
        if ($ld -ceq '<' -and $p.tag -ceq 'o') { Err $p "outputs declare goes-to with '>', not '<'" }
        if ($ld -ceq '>' -and $p.tag -cmatch '^[icm]\z') { Err $p "'$($p.tag)' ports declare comes-from with '<', not '>'" }
    }
}

# ================================================================ wiring
function WireModel($t) {
    $prod = NewH; $pk = @(); $cons = NewH; $ck = @()
    foreach ($p in @(AllPorts $t)) {
        if ($p.tag -ceq 'o') { if (-not $prod.ContainsKey($p.name)) { $pk += , $p.name; $prod[$p.name] = @() }; $prod[$p.name] += , $p }
        else { if (-not $cons.ContainsKey($p.name)) { $ck += , $p.name; $cons[$p.name] = @() }; $cons[$p.name] += , $p }
    }
    $t.producers = $prod; $t.consumers = $cons
    foreach ($name in $ck) {
        if ($prod.ContainsKey($name)) { continue }
        $c = CloseMatch $name $pk 0.86
        foreach ($p in $cons[$name]) {
            if (HasLink $p) { continue }
            if ($null -ne $c) { Err $p "'$name' has no producer; did you mean '$c'?" 'warning' }
        }
    }
    foreach ($name in $pk) {
        if ($cons.ContainsKey($name)) { continue }
        $c = CloseMatch $name $ck 0.86
        foreach ($p in $prod[$name]) {
            if (HasLink $p) { continue }
            if ($null -ne $c) { Err $p "'$name' has no consumer; did you mean '$c'?" 'warning' }
        }
    }
}

# ================================================================ links
function Walk($scope, $segs, [string]$want) {                                 # node, $null, or @{ ambig } (Perl's die)
    $cur = $scope
    for ($i = 0; $i -lt $segs.Count; $i++) {
        $seg = $segs[$i]; $last = $i -eq $segs.Count - 1
        $kids = @($cur.children | Where-Object { $_.name -ceq $seg })
        if ($kids.Count -eq 1) { $cur = $kids[0]; continue }
        $pm = @($cur.ports | Where-Object { $_.name -ceq $seg })
        if ($pm.Count -ge 2) { return @{ ambig = $true; act = $cur; flow = $seg } }
        if ($pm.Count -eq 1) { if ($last) { return $pm[0] } else { return $null } }
        if ($seg -cmatch '^[icom][1-9]\z') {
            $tg = $seg.Substring(0, 1); $nm = [int]$seg.Substring(1)
            $pr = @($cur.ports | Where-Object { $_.tag -ceq $tg -and $_.number -eq $nm })
            if ($pr.Count) { if ($last) { return $pr[0] } else { return $null } }
        }
        $nn = @($cur.children | Where-Object { $null -ne $_.node_id -and $_.node_id -ceq $seg })
        if ($nn.Count -eq 1) { $cur = $nn[0]; continue }
        return $null
    }
    if ($want -ceq '<') {
        $outs = @($cur.ports | Where-Object { $_.tag -ceq 'o' })
        if ($outs.Count -eq 1) { return $outs[0] }
    }
    $null
}
function Suggest($segs, $scopeModel, $letters) {
    $names = NewH
    foreach ($k in $letters.Keys) { $names[$k] = 1 }
    foreach ($v in $letters.Values) { $names[$v.name] = 1 }
    if ($null -ne $scopeModel) { foreach ($a in @(Desc $scopeModel)) { $names[$a.name] = 1; $names[$a.node_id] = 1 } }
    $n = @($names.Keys)
    foreach ($seg in $segs) {
        if ($names.ContainsKey($seg)) { continue }
        $c = CloseMatch $seg $n 0.75
        if ($null -ne $c) { return " (closest: '$c')" }
    }
    ''
}
function ResolveLinks($models, $letters) {
    $byName = NewH
    foreach ($m in $models) { $byName[$m.name] = $m }
    $cross = @()
    foreach ($t in $models) {
        foreach ($p in @(AllPorts $t)) {
            if (-not (HasLink $p)) { continue }
            $segs = @($p.link_path)
            $target = $null; $addressed = $t; $amb = $null
            $scope = $p.parent
            while ($null -ne $scope -and $null -eq $target) {
                $r = Walk $scope $segs $p.link_dir
                if ($null -ne $r -and $r.ambig) { $amb = $r; break }
                $target = $r
                $scope = $scope.parent
            }
            if ($null -eq $amb -and $null -eq $target -and $segs.Count) {
                $mt = $letters[$segs[0]]; if ($null -eq $mt) { $mt = $byName[$segs[0]] }
                if ($null -ne $mt -and $segs.Count -gt 1) {
                    $addressed = $mt
                    $r = Walk $mt @($segs[1..($segs.Count - 1)]) $p.link_dir
                    if ($null -ne $r -and $r.ambig) { $amb = $r } else { $target = $r }
                }
            }
            if ($null -ne $amb) {
                Err $p ("'$($amb.act.name)' has no unique port for flow '$($amb.flow)'; add the port or use o1/i1 form")
                continue
            }
            if ($null -eq $target) {
                $hint = Suggest $segs $addressed $letters
                Err $p ("broken link: cannot resolve '" + ($segs -join '|') + "'$hint")
                continue
            }
            $p.link_target = $target
            if ($p.link_dir -ceq '<') { $src = $target; $dst = $p } else { $src = $p; $dst = $target }
            if ($src.tag -cne 'o' -and -not ($src.tag -ceq 'm' -and $dst.tag -ceq 'm')) {
                Err $p ("link source '$($src.node_id)' is '$($src.tag)' -- flows must originate at an output") 'warning'
            }
            if ($dst.tag -ceq 'o') { Err $p "link destination '$($dst.node_id)' is an output" 'warning' }
            if (-not (Same $src.model $dst.model)) { $cross += , @($src, $dst, $p) }
        }
    }
    foreach ($c in $cross) {
        $src = $c[0]; $dst = $c[1]; $via = $c[2]
        $other = if (Same $via $src) { $dst } else { $src }
        if (-not (HasLink $other)) {
            $dirc = if ($other.tag -ceq 'o') { '>' } else { '<' }
            Err $via ("one-sided cross-model link: $($other.node_id) " + (PyRepr $other.name) + ' does not declare the reciprocal ' + $dirc + ' link') 'warning'
        }
    }
    $rows = @(); $seen = NewH
    foreach ($c in $cross) {
        $src = $c[0]; $dst = $c[1]
        $nm = if ($src.name -ceq $dst.name) { @($src.name) } else { @($src.name, $dst.name) }
        foreach ($name in $nm) {
            $key = $src.node_id + [char]0 + $dst.node_id + [char]0 + $name
            if ($seen.ContainsKey($key)) { continue }
            $seen[$key] = 1
            $rows += , @($src, $dst, $name, $rows.Count)
        }
    }
    $rows = SortBy $rows {
        param($x, $y)
        $r = Cmp $x[0].model.letter $y[0].model.letter; if ($r) { return $r }
        $r = Cmp $x[0].node_id $y[0].node_id; if ($r) { return $r }
        $r = Cmp $x[1].node_id $y[1].node_id; if ($r) { return $r }
        $r = Cmp $x[2] $y[2]; if ($r) { return $r }
        NumCmp $x[3] $y[3]
    }
    , $rows
}

# ================================================================ project
function LoadProject($files, [bool]$linksToo = $true) {
    $doc = NewH; $models = @()
    foreach ($f in $files) {
        if (-not (Test-Path -LiteralPath $f -PathType Leaf)) {
            PErr ("idef0: cannot read ${f}: [Errno 2] No such file or directory: " + (PyRepr $f))
            Flush $null; exit 2
        }
        $text = ReadText $f
        $models += (ParseFile $f $text $doc)
    }
    $letters = AssignNumbers $models
    $rows = @()
    if ($linksToo) {
        foreach ($m in $models) { WireModel $m }
        $rows = ResolveLinks $models $letters
    }
    @{ models = $models; letters = $letters; rows = $rows; doc = $doc }
}
function EmitDiags([bool]$toErr = $false) {
    $e = @($script:DIAGS | Where-Object { $_[2] -ceq 'error' }).Count
    $w = @($script:DIAGS | Where-Object { $_[2] -ceq 'warning' }).Count
    $sorted = SortBy $script:DIAGS { param($x, $y) $r = Cmp $x[0] $y[0]; if ($r) { return $r }; $r = NumCmp $x[1] $y[1]; if ($r) { return $r }; NumCmp $x[4] $y[4] }
    foreach ($d in $sorted) {
        $line = "$($d[0]):$($d[1]): $($d[2]): $($d[3])"
        if ($toErr) { PErr $line } else { P "$line`n" }
    }
    @($e, $w)
}
function Summary($files, $models, $rows) {
    $e = @($script:DIAGS | Where-Object { $_[2] -ceq 'error' }).Count
    $w = @($script:DIAGS | Where-Object { $_[2] -ceq 'warning' }).Count
    $acts = 0
    foreach ($m in $models) { $acts += @(Desc $m).Count }
    P ("$(@($files).Count) file(s): $e error(s), $w warning(s), $(@($models).Count) model(s), $acts activities, $(@($rows).Count) link(s)`n")
    $e
}

# ================================================================ commands
function CmdLint($files) {
    $pr = LoadProject $files
    $null = EmitDiags
    if (Summary $files $pr.models $pr.rows) { 1 } else { 0 }
}
function DumpRec($a, [int]$depth) {
    foreach ($p in $a.ports) {
        $lk = if (HasLink $p) { "  $($p.link_dir) " + ($p.link_path -join '|') } else { '' }
        P (('  ' * $depth) + (Lj $p.node_id 12) + ' ' + $p.tag.ToUpper() + " $($p.name)$lk`n")
    }
    foreach ($k in $a.children) {
        P (('  ' * $depth) + (Lj $k.node_id 12) + " $($k.name)`n")
        DumpRec $k ($depth + 1)
    }
}
function CmdDump($files) {
    $pr = LoadProject $files
    $ew = EmitDiags
    foreach ($t in $pr.models) {
        P "$($t.node_id)  $($t.name)    [$($t.fname)]`n"
        DumpRec $t 1
        P "`n"
    }
    if ($ew[0]) { 1 } else { 0 }
}
function CmdLinks($files) {
    $pr = LoadProject $files
    $ew = EmitDiags
    P ((Lj 'SOURCE' 14) + ' ' + (Lj 'DEST' 14) + " FLOW`n")
    foreach ($r in $pr.rows) { P ((Lj $r[0].node_id 14) + ' ' + (Lj $r[1].node_id 14) + " $($r[2])`n") }
    if ($ew[0]) { 1 } else { 0 }
}

# ================================================================ plate layout
$script:BOX_H = 5
$script:CONTEXT = @{}                                                         # uid -> 1: models whose A-0 context plate is drawn
function ModelPlateId($t) { if (-not @($t.children).Count -or $script:CONTEXT.ContainsKey($t.uid)) { "$($t.letter)-0" } else { "$($t.letter)0" } }
function PlateId($t, $node) { if ($node.tag -ceq 'a') { $node.node_id } else { ModelPlateId $t } }
function DKey($t, $el) {
    if ($el.tag -ceq 't') { return ModelPlateId $el }
    if ($el.tag -ceq 'a') { return $el.node_id }
    $par = $el.parent
    $plid = if ($par.tag -ceq 'a') { $par.node_id } else { ModelPlateId $par }
    "$plid.$($el.tag)$($el.number)"
}
function DocPlain($el) { ($el.doc -join ' ').Replace('\n', "`n") }
function MdInline([string]$s) {
    $s = Esc $s
    $s = $s -creplace '`([^`]+)`', '<code>$1</code>'
    $s = $s -creplace '\*\*(.+?)\*\*', '<strong>$1</strong>'
    $s = $s -creplace '(?<!\*)\*([^*]+)\*(?!\*)', '<em>$1</em>'
    $s = $s -creplace '\[([^\]]+)\]\(([^)\s]+)\)', '<a href="$2" target="_blank">$1</a>'
    $s
}
function DocHtml($el) {
    $paras = @(foreach ($x in [regex]::Split(($el.doc -join ' '), '\\n')) { Strip $x })
    (@(foreach ($x in $paras) { if ($x -ne '') { '<p>' + (MdInline $x) + '</p>' } })) -join ''
}
function PlatesOf($t) {                                                       # a model with no activities draws its own box
    $kids = @($t.children); if (-not $kids.Count) { $kids = @(, $t) }
    , @($t, $kids)
    foreach ($a in @(Desc $t)) { if (@($a.children).Count) { , @($a, @($a.children)) } }
}
function AllPlates($models) { foreach ($t in $models) { foreach ($pl in @(PlatesOf $t)) { , @($t, $pl[0], $pl[1]) } } }
function PortRoute($p, $t) {
    if (HasLink $p) {
        $o = $p.link_target
        if ($null -eq $o -or $null -eq $o.model) { return "$($p.link_dir) " + ($p.link_path -join '|') }
        return "$($p.link_dir) $($o.model.letter):$($o.node_id)"
    }
    $tbl = if ($p.tag -cne 'o') { $t.producers } else { $t.consumers }
    $lst = $tbl[$p.name]; if ($null -eq $lst) { $lst = @() }
    $peers = @($lst | Where-Object { -not (Same $_.parent $p.parent) -and -not ($null -eq $_.parent -and $null -eq $p.parent) })
    if ($peers.Count) {
        $u = NewH; foreach ($x in $peers) { $u[$x.parent.node_id] = 1 }
        $pre = if ($p.tag -cne 'o') { 'from ' } else { 'to ' }
        return $pre + ((SortStr @($u.Keys)) -join ',')
    }
    ''
}
function LayoutPlate($t, $node, $boxes) {
    $bw = Min2 26 (Max2 20 ((MaxL @(foreach ($b in $boxes) { $b.name.Length })) + 4))
    $inLabels = @(); $ext = @()
    $boxIds = @{}; foreach ($b in $boxes) { $boxIds[$b.uid] = 1 }
    foreach ($b in $boxes) {
        foreach ($p in $b.ports) {
            if ($p.tag -ceq 'i') {
                $r = PortRoute $p $t
                $inLabels += , ($p.name + $(if ($r -ne '') { " ($r)" } else { '' }))
            }
            if ($p.tag -ceq 'c') {
                $lst = $t.producers[$p.name]; if ($null -eq $lst) { $lst = @() }
                $prod = @($lst | Where-Object { $null -ne $_.parent -and $boxIds.ContainsKey($_.parent.uid) })
                if (-not $prod.Count -and -not ($ext -ccontains $p.name)) { $ext += , $p.name }
            }
        }
    }
    $left = Max2 8 $(if ($inLabels.Count) { (MaxL @(foreach ($l in $inLabels) { $l.Length })) + 4 } else { 8 })
    $top = 2 * $ext.Count + 2
    $hgap = 12; $vgap = 4
    $pos = @{}
    for ($i = 0; $i -lt $boxes.Count; $i++) { $pos[$boxes[$i].uid] = @(($left + $i * ($bw + $hgap)), ($top + $i * ($script:BOX_H + $vgap))) }
    $lp = $pos[$boxes[$boxes.Count - 1].uid]; $lastx = $lp[0]; $lasty = $lp[1]
    $hasMech = $false; foreach ($b in $boxes) { foreach ($p in $b.ports) { if ($p.tag -ceq 'm') { $hasMech = $true } } }
    $Wd = Max2 ($lastx + $bw + 28) 64
    $Ht = $lasty + $script:BOX_H + $(if ($hasMech) { 5 } else { 2 }) + 6
    @{ pos = $pos; bw = $bw; left = $left; top = $top; W = $Wd; H = $Ht; ext = $ext }
}
function RenderTextPlate($t, $node, $boxes, [int]$pageno) {
    $lay = LayoutPlate $t $node $boxes
    $pos = $lay.pos; $bw = $lay.bw; $Wd = $lay.W; $Ht = $lay.H; $ext = $lay.ext
    $script:G = @{}; $script:MAXR = $null; $script:MAXC = $null
    $put = {
        param($r, $c, $s)
        $chs = $s.ToCharArray()
        for ($k = 0; $k -lt $chs.Count; $k++) {
            if ($c + $k -lt 0) { continue }
            $script:G["$r,$($c + $k)"] = [string]$chs[$k]
            if ($null -eq $script:MAXR -or $r -gt $script:MAXR) { $script:MAXR = $r }
            if ($null -eq $script:MAXC -or $c + $k -gt $script:MAXC) { $script:MAXC = $c + $k }
        }
    }
    for ($ci = 0; $ci -lt $ext.Count; $ci++) {
        $cname = $ext[$ci]; $row = 2 * $ci
        $cons = @($boxes | Where-Object { $bb = $_; @($bb.ports | Where-Object { $_.tag -ceq 'c' -and $_.name -ceq $cname }).Count })
        if (-not $cons.Count) { continue }
        $x0 = $pos[$cons[0].uid][0]
        & $put $row ($x0 + 2) $cname
        foreach ($b in $cons) {
            $x = $pos[$b.uid][0]; $y = $pos[$b.uid][1]
            $cx = $x + (Trunc ($bw / 2))
            for ($r = $row + 1; $r -le $y - 1; $r++) { if (-not $script:G.ContainsKey("$r,$cx")) { & $put $r $cx '|' } }
            & $put ($y - 1) $cx 'v'
        }
    }
    foreach ($b in $boxes) {
        $x = $pos[$b.uid][0]; $y = $pos[$b.uid][1]
        & $put $y $x ('+' + ('-' * ($bw - 2)) + '+')
        for ($q = 1; $q -le $script:BOX_H - 2; $q++) { & $put ($y + $q) $x ('|' + (' ' * ($bw - 2)) + '|') }
        & $put ($y + $script:BOX_H - 1) $x ('+' + ('-' * ($bw - 2)) + '+')
        $nm = if ($b.name.Length -le $bw - 4) { $b.name } else { $b.name.Substring(0, $bw - 7) + '...' }
        & $put ($y + 1) ($x + 2) $nm
        $tagn = $b.node_id + $(if (@($b.children).Count) { '*' } else { '' })
        & $put ($y + $script:BOX_H - 2) ($x + $bw - 2 - $tagn.Length) $tagn
        $ins = @($b.ports | Where-Object { $_.tag -ceq 'i' })
        for ($k = 0; $k -lt $ins.Count; $k++) {
            $p = $ins[$k]; $r = $y + 1 + (Min2 $k ($script:BOX_H - 3))
            $rt = PortRoute $p $t
            $lab = $p.name + $(if ($rt -ne '') { " ($rt)" } else { '' })
            & $put $r ($x - $lab.Length - 4) "$lab ->"
        }
        $outs = @($b.ports | Where-Object { $_.tag -ceq 'o' })
        for ($k = 0; $k -lt $outs.Count; $k++) {
            $p = $outs[$k]; $r = $y + 1 + (Min2 $k ($script:BOX_H - 3))
            $rt = PortRoute $p $t
            $lab = $p.name + $(if ($rt -ne '') { " ($rt)" } else { '' })
            & $put $r ($x + $bw + 1) "-> $lab"
        }
        $mechs = @($b.ports | Where-Object { $_.tag -ceq 'm' })
        if ($mechs.Count) {
            & $put ($y + $script:BOX_H) ($x + (Trunc ($bw / 2))) '^'
            & $put ($y + $script:BOX_H + 1) ($x + 2) ((@($mechs | ForEach-Object { $_.name })) -join ', ')
        }
    }
    $mr = $script:MAXR; if ($null -eq $mr) { $mr = 0 }
    $mc = $script:MAXC; if ($null -eq $mc) { $mc = 0 }
    $Wd = Max2 $Wd ($mc + 2)
    $lines = @()
    $nrows = Max2 $Ht ($mr + 1)
    for ($r = 0; $r -lt $nrows; $r++) {
        $cells = for ($c = 0; $c -lt $Wd; $c++) { $v = $script:G["$r,$c"]; if ($null -eq $v) { ' ' } else { $v } }
        $lines += , (RStrip ($cells -join ''))
    }
    $total = Max2 (Max2 0 (MaxL @(foreach ($l in $lines) { $l.Length }))) 64
    $mid = $total - 26
    $nid = PlateId $t $node
    $title = $node.name
    if ($title.Length -gt $mid - 2) { $title = $title.Substring(0, $mid - 5) + '...' }
    $num = "p.$pageno"
    $bar = '+' + ('-' * 11) + '+' + ('-' * $mid) + '+' + ('-' * 11) + '+'
    $tb = @($bar,
        ('|' + (Lj ' NODE' 11) + '|' + (Lj ' TITLE' $mid) + '|' + (Lj ' NUMBER' 11) + '|'),
        ('|' + (Lj " $nid" 11) + '|' + (Lj " $title" $mid) + '|' + (Lj " $num" 11) + '|'),
        $bar)
    (@($lines) + $tb) -join "`n"
}
function CmdText($files) {
    $pr = LoadProject $files
    $ew = EmitDiags $true
    if ($ew[0]) { return 1 }
    $plates = @(AllPlates $pr.models)
    P ('NODE INDEX' + (' ' * 44) + "p.1`n" + ('-' * 64) + "`n")
    for ($i = 0; $i -lt $plates.Count; $i++) {
        $t = $plates[$i][0]; $node = $plates[$i][1]
        P ('  ' + (Lj (PlateId $t $node) 10) + ' ' + (Lj $node.name 40) + ' p.' + ($i + 2) + "`n")
    }
    for ($i = 0; $i -lt $plates.Count; $i++) {
        P "`f`n"
        P ((RenderTextPlate $plates[$i][0] $plates[$i][1] $plates[$i][2] ($i + 2)) + "`n")
    }
    0
}

# ================================================================ svg
$script:CW = 9; $script:CH = 18; $script:PAD = 20
function GFmt($x) {                                                           # sprintf '%g' (6 significant digits)
    $d = [double]$x
    if ($d -eq 0) { return '0' }
    $a = AbsN $d
    $e = 0; $t = $a
    while ($t -ge 10) { $t /= 10; $e++ }
    while ($t -lt 1) { $t *= 10; $e-- }
    if ($e -lt -4 -or $e -ge 6) { return "$d" }                              # not reached by plate coordinates
    $dec = 5 - $e
    $s = $d.ToString('F' + $dec, [System.Globalization.CultureInfo]::InvariantCulture)
    if ($s.Contains('.')) { $s = ($s -creplace '0+$', '') -creplace '\.$', '' }
    $s
}
function PNum($x) { "$x" }                                                    # Perl's number stringification (15 significant digits)
function Elbow($sx, $sy, $midx, $dyy, $dxx, $r = 7) {
    if ($sy -eq $dyy) { return "M$(PNum $sx),$(PNum $sy) H$(PNum $dxx)" }
    $vy = if ($dyy -gt $sy) { 1 } else { -1 }
    $hx2 = if ($dxx -ge $midx) { 1 } else { -1 }
    $last = if ($dxx -ne $midx) { (AbsN ($dxx - $midx)) / 2 } else { $r }
    $rr = MinL @($r, ((AbsN ($midx - $sx)) / 2), ((AbsN ($dyy - $sy)) / 2), $last)
    if ($rr -lt 1) { return "M$(PNum $sx),$(PNum $sy) H$(PNum $midx) V$(PNum $dyy) H$(PNum $dxx)" }
    "M$(PNum $sx),$(PNum $sy) H" + (GFmt ($midx - $rr)) + ' ' +
        "Q$(PNum $midx),$(PNum $sy) $(PNum $midx)," + (GFmt ($sy + $vy * $rr)) + ' ' +
        'V' + (GFmt ($dyy - $vy * $rr)) + ' ' +
        "Q$(PNum $midx),$(PNum $dyy) " + (GFmt ($midx + $hx2 * $rr)) + ",$(PNum $dyy) " +
        "H$(PNum $dxx)"
}
function SvgPlate($t, $node, $boxes, [int]$pageno, [bool]$rich = $false) {
    $lay = LayoutPlate $t $node $boxes
    $pos = $lay.pos; $bw = $lay.bw; $Wd = $lay.W; $Ht = $lay.H; $ext = $lay.ext
    $CW = $script:CW; $chPx = $script:CH; $PAD = $script:PAD; $BH = $script:BOX_H
    $dattr = { param($el) if ($null -eq $el -or -not @($el.doc).Count -or -not $rich) { '' } else { ' class="hasdoc" data-doc="' + (DKey $t $el) + '"' } }
    $dtitle = { param($el) if ($null -eq $el -or -not @($el.doc).Count -or $rich) { '' } else { '<title>' + (Esc (DocPlain $el)) + '</title>' } }
    $boxIds = @{}; foreach ($b in $boxes) { $boxIds[$b.uid] = 1 }
    $width = ((Max2 $Wd 64) * $CW + $PAD) + $PAD
    $height = (($Ht + 4) * $chPx + $PAD) + $PAD
    $o = @{}; $k = 0
    $o[$k++] = "<svg xmlns=`"http://www.w3.org/2000/svg`" width=`"$width`" height=`"$height`" viewBox=`"0 0 $width $height`" font-family=`"IBM Plex Mono,monospace`">"
    $o[$k++] = "<rect width=`"$width`" height=`"$height`" fill=`"#fdfcf8`"/>"
    $o[$k++] = '<defs><marker id="arr" markerWidth="8" markerHeight="8" refX="7" refY="3" orient="auto"><path d="M0,0 L7,3 L0,6 z" fill="#222"/></marker></defs>'
    for ($ci = 0; $ci -lt $ext.Count; $ci++) {
        $cname = $ext[$ci]; $row = 2 * $ci
        $cons = @($boxes | Where-Object { $bb = $_; @($bb.ports | Where-Object { $_.tag -ceq 'c' -and $_.name -ceq $cname }).Count })
        if (-not $cons.Count) { continue }
        $x0 = $pos[$cons[0].uid][0]
        $dp = $null
        foreach ($b in $cons) { foreach ($p in $b.ports) { if ($null -eq $dp -and $p.tag -ceq 'c' -and $p.name -ceq $cname -and @($p.doc).Count) { $dp = $p } } }
        $o[$k++] = '<text x="' + (($x0 + 2) * $CW + $PAD) + '" y="' + (($row * $chPx + $PAD) + 12) + '" font-size="11"' + (& $dattr $dp) + '>' + (Esc $cname) + (& $dtitle $dp) + '</text>'
        foreach ($b in $cons) {
            $x = $pos[$b.uid][0]; $y = $pos[$b.uid][1]
            $cx = ($x + (Trunc ($bw / 2))) * $CW + $PAD
            $o[$k++] = "<path d=`"M$cx," + (($row * $chPx + $PAD) + 16) + ' V' + ($y * $chPx + $PAD) + '" fill="none" stroke="#222" stroke-width="1.1" marker-end="url(#arr)"/>'
        }
    }
    foreach ($b in $boxes) {
        foreach ($p in $b.ports) {
            if ($p.tag -cne 'o') { continue }
            $lst = $t.consumers[$p.name]; if ($null -eq $lst) { $lst = @() }
            foreach ($q in $lst) {
                if ($null -eq $q.parent -or -not $boxIds.ContainsKey($q.parent.uid) -or (Same $q.parent $b)) { continue }
                if ($q.tag -ceq 'c') { continue }
                $sp = $pos[$b.uid]; $dp0 = $pos[$q.parent.uid]
                $sx = ($sp[0] + $bw) * $CW + $PAD
                $sy = (($sp[1] + 2) * $chPx + $PAD) + (Trunc ($chPx / 2))
                $dxx = $dp0[0] * $CW + $PAD
                $dyy = (($dp0[1] + 2) * $chPx + $PAD) + (Trunc ($chPx / 2))
                $midx = $sx + 5 * $CW
                $o[$k++] = '<path d="' + (Elbow $sx $sy $midx $dyy $dxx) + '" fill="none" stroke="#222" stroke-width="1.1" marker-end="url(#arr)"/>'
                $fl = if (@($p.doc).Count) { $p } else { $q }
                $o[$k++] = '<text x="' + ($midx + 4) + '" y="' + (Trunc (($sy + $dyy) / 2)) + '" font-size="9"' + (& $dattr $fl) + '>' + (Esc $p.name) + (& $dtitle $fl) + '</text>'
            }
        }
    }
    foreach ($b in $boxes) {
        $x = $pos[$b.uid][0] * $CW + $PAD; $y = $pos[$b.uid][1] * $chPx + $PAD
        $w = $bw * $CW; $h = $BH * $chPx
        $kids = @($b.children).Count
        if ($rich -and $kids) { $o[$k++] = "<a href=`"#plate-$($b.node_id)`">" }
        $o[$k++] = "<rect x=`"$x`" y=`"$y`" width=`"$w`" height=`"$h`" fill=`"#fff`" stroke=`"#222`" stroke-width=`"1.6`"/>"
        $nm = if ($b.name.Length -le $bw - 4) { $b.name } else { $b.name.Substring(0, $bw - 7) + '...' }
        $cxf = if ($w % 2) { ($x + $w / 2).ToString('F1', [System.Globalization.CultureInfo]::InvariantCulture) } else { "$($x + $w / 2).0" }
        $o[$k++] = "<text x=`"$cxf`" y=`"" + ($y + 24) + '" font-size="12" text-anchor="middle"' + (& $dattr $b) + '>' + (Esc $nm) + (& $dtitle $b) + '</text>'
        $o[$k++] = '<text x="' + ($x + $w - 6) + '" y="' + ($y + $h - 8) + '" font-size="10" text-anchor="end" fill="#555">' + $b.node_id + $(if ($kids) { '*' } else { '' }) + '</text>'
        if ($rich -and $kids) { $o[$k++] = '</a>' }
        $ins = @($b.ports | Where-Object { $_.tag -ceq 'i' })
        for ($j = 0; $j -lt $ins.Count; $j++) {
            $p = $ins[$j]
            $py = $y + $chPx * (1 + (Min2 $j ($BH - 3))) + (Trunc ($chPx / 2))
            $rt = PortRoute $p $t
            if ($rt -cmatch '^from ') { continue }
            $lab = $p.name + $(if ($rt -ne '') { "  [$rt]" } else { '' })
            $o[$k++] = '<path d="M' + ($x - 40) + ",$py H$x`" fill=`"none`" stroke=`"#222`" stroke-width=`"1.1`" marker-end=`"url(#arr)`"/>"
            $o[$k++] = '<text x="' + ($x - 44) + '" y="' + ($py - 3) + '" font-size="9" text-anchor="end"' + (& $dattr $p) + '>' + (Esc $lab) + (& $dtitle $p) + '</text>'
        }
        $outs = @($b.ports | Where-Object { $_.tag -ceq 'o' })
        for ($j = 0; $j -lt $outs.Count; $j++) {
            $p = $outs[$j]
            $py = $y + $chPx * (1 + (Min2 $j ($BH - 3))) + (Trunc ($chPx / 2))
            $rt = PortRoute $p $t
            if ($rt -cmatch '^to ') { continue }
            $lab = $p.name + $(if ($rt -ne '') { "  [$rt]" } else { '' })
            $o[$k++] = '<path d="M' + ($x + $w) + ",$py H" + ($x + $w + 40) + '" fill="none" stroke="#222" stroke-width="1.1" marker-end="url(#arr)"/>'
            $o[$k++] = '<text x="' + ($x + $w + 44) + '" y="' + ($py - 3) + '" font-size="9"' + (& $dattr $p) + '>' + (Esc $lab) + (& $dtitle $p) + '</text>'
        }
        $mechs = @($b.ports | Where-Object { $_.tag -ceq 'm' })
        if ($mechs.Count) {
            $cx = $x + (Trunc ($w / 2))
            $o[$k++] = "<path d=`"M$cx," + ($y + $h + 30) + " V" + ($y + $h) + '" fill="none" stroke="#222" stroke-width="1.1" marker-end="url(#arr)"/>'
            $parts = for ($j = 0; $j -lt $mechs.Count; $j++) {
                $p = $mechs[$j]
                $(if ($j) { ', ' } else { '' }) + '<tspan' + (& $dattr $p) + '>' + (Esc $p.name) + (& $dtitle $p) + '</tspan>'
            }
            $o[$k++] = '<text x="' + ($cx + 4) + '" y="' + ($y + $h + 28) + '" font-size="9">' + (@($parts) -join '') + '</text>'
        }
    }
    $ty = $height - 3 * $chPx
    $nid = PlateId $t $node
    $o[$k++] = "<rect x=`"0`" y=`"$ty`" width=`"$width`" height=`"" + (3 * $chPx) + '" fill="#fff" stroke="#222"/>'
    $o[$k++] = "<line x1=`"99`" y1=`"$ty`" x2=`"99`" y2=`"$height`" stroke=`"#222`"/>"
    $o[$k++] = '<line x1="' + ($width - 99) + "`" y1=`"$ty`" x2=`"" + ($width - 99) + "`" y2=`"$height`" stroke=`"#222`"/>"
    $o[$k++] = '<text x="10" y="' + ($ty + 16) + '" font-size="10">NODE</text>'
    $o[$k++] = '<text x="10" y="' + ($ty + 36) + "`" font-size=`"12`">$nid</text>"
    $o[$k++] = '<text x="110" y="' + ($ty + 16) + '" font-size="10">TITLE</text>'
    $o[$k++] = '<text x="110" y="' + ($ty + 36) + '" font-size="12"' + (& $dattr $node) + '>' + (Esc $node.name) + (& $dtitle $node) + '</text>'
    $o[$k++] = '<text x="' + ($width - 89) + '" y="' + ($ty + 16) + '" font-size="10">NUMBER</text>'
    $o[$k++] = '<text x="' + ($width - 89) + '" y="' + ($ty + 36) + "`" font-size=`"12`">p.$pageno</text>"
    $o[$k++] = '</svg>'
    (@(for ($i = 0; $i -lt $k; $i++) { $o[$i] })) -join "`n"
}
function CmdSvg([string]$nodeid, $files) {
    $pr = LoadProject $files
    $ew = EmitDiags $true
    if ($ew[0]) { return 1 }
    $m = [regex]::Match($nodeid, '^(\S+)-0\z')
    if ($m.Success) {
        $t = $null; foreach ($x in $pr.models) { if ($x.letter -ceq $m.Groups[1].Value) { $t = $x; break } }
        if ($null -ne $t -and @($t.children).Count) {
            $script:CONTEXT[$t.uid] = 1
            P ((SvgPlate $t $t @(, $t) 1) + "`n")
            $script:CONTEXT.Remove($t.uid)
            return 0
        }
    }
    $plates = @(AllPlates $pr.models)
    for ($i = 0; $i -lt $plates.Count; $i++) {
        if ((PlateId $plates[$i][0] $plates[$i][1]) -ceq $nodeid) {
            P ((SvgPlate $plates[$i][0] $plates[$i][1] $plates[$i][2] ($i + 2)) + "`n")
            return 0
        }
    }
    PErr ('idef0: no plate ' + (PyRepr $nodeid))
    2
}
function PlateOfPort($p, $pageof) {
    $a = $p.parent
    if ($null -eq $a -or $a.tag -ceq 't') { return $null }
    $par = $a.parent
    $plid = if ($par.tag -ceq 'a') { $par.node_id } else { ModelPlateId $par }
    if ($pageof.ContainsKey($plid)) { $plid } else { $null }
}

$script:HTML_CSS = @'
body{font-family:IBM Plex Mono,monospace;background:#eee;margin:0}
.plate{background:#fff;margin:10px auto;padding:6px;box-shadow:0 1px 4px #0003;
width:max-content;max-width:calc(100vw - 20px);overflow-x:auto;scroll-margin-top:4px;
page-break-after:always}
.plate svg{display:block;width:auto;height:auto;max-width:calc(100vw - 34px);max-height:calc(100vh - 60px)}
body.one2one .plate svg{max-width:none;max-height:none}
.zoom{float:right}.zoom a{margin:0 0 0 4px}.zoom a.on{font-weight:700;color:#000;text-decoration:none;cursor:default}
@media print{.plate svg{max-width:100%;max-height:none}}
h1{font-size:16px;margin:18px}
h1 svg.logo{height:22px;width:auto;color:#eee;vertical-align:-4px;margin-right:14px}
table{border-collapse:collapse;margin:18px;background:#fff}
td,th{border:1px solid #999;padding:3px 9px;font-size:12px}
.p1{display:flex;flex-wrap:wrap;align-items:flex-start;gap:0 18px}.p1 table{margin-top:0}.p1 caption{text-align:left;font-weight:700;font-size:12px;padding:0 0 6px}
a{color:#27235d}
.nav{font-size:12px;padding:4px 8px;background:#e4e4e7;border-bottom:1px solid #ddd;
position:sticky;left:0}
.nav a{text-decoration:none;margin-right:4px}
.dim{color:#999}
details.notes{font-size:12px;max-width:640px;padding:4px 8px;background:#fdfcf2;
border-bottom:1px solid #eee}
details.notes p{margin:4px 0}
.hasdoc{text-decoration:underline dotted 1.5px #6a994e;cursor:help}
svg a text{cursor:pointer}
svg a:hover rect{fill:#f5f9ee}
#tip{position:fixed;display:none;z-index:9;max-width:340px;background:#fffbea;
border:1px solid #b7a;box-shadow:2px 3px 8px #0004;padding:2px 12px;
font-size:12.5px;line-height:1.45}
#tip p{margin:8px 0}
#tip code{background:#eee8d5;padding:0 3px}
'@ -replace "`r", ''
$script:HTML_JS = @'
function zoom(one){document.body.classList.toggle('one2one',!!one);
 document.querySelectorAll('.zoom a').forEach(a=>a.classList.toggle('on',a.classList.contains(one?'one':'fit')));
 try{localStorage.setItem('idef0-zoom',one?'1':'0');}catch(e){}return false;}
try{if(localStorage.getItem('idef0-zoom')==='1')zoom(1);}catch(e){}
const tip=document.getElementById('tip');
let pin=null;
function show(k,x,y){tip.innerHTML=DOCS[k]||'';tip.style.display='block';
 const r=tip.getBoundingClientRect();
 x=Math.min(x+14,innerWidth-r.width-8);y=Math.min(y+16,innerHeight-r.height-8);
 tip.style.left=Math.max(4,x)+'px';tip.style.top=Math.max(4,y)+'px';}
function hide(){tip.style.display='none';pin=null;}
const canHover=matchMedia('(hover:hover)').matches;
document.addEventListener('mousemove',e=>{if(!canHover||pin)return;
 const t=e.target.closest?e.target.closest('.hasdoc'):null;
 if(t)show(t.dataset.doc,e.clientX,e.clientY);else hide();});
document.addEventListener('click',e=>{
 const t=e.target.closest?e.target.closest('.hasdoc'):null;
 if(t&&!t.closest('a')){
  if(pin===t.dataset.doc){hide();}
  else{pin=t.dataset.doc;show(pin,e.clientX,e.clientY);}
  e.stopPropagation();}
 else if(!e.target.closest('#tip'))hide();});
'@ -replace "`r", ''
$script:HTML_CSS += "`n"; $script:HTML_JS += "`n"

function LogoSvg($file) {
    if ($null -eq $file) {
        $file = Join-Path $PSScriptRoot '..\..\assets\logo.svg'
        if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { return '' }
    }
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { throw "cannot read logo ${file}: No such file or directory`n" }
    $x = ReadText $file
    $m = [regex]::Match($x, '(?s)<svg[^>]*viewBox="([^"]+)"[^>]*>(.*)</svg>')
    if (-not $m.Success) { return '' }
    $vb = $m.Groups[1].Value; $body = $m.Groups[2].Value
    $body = $body -creplace '\s+', ' '
    $body = $body -creplace ' opacity="1\.000000"', ''
    $body = $body -creplace '(\d+\.\d{2})\d+', '$1'
    "<svg class=`"logo`" viewBox=`"$vb`" role=`"img`" aria-label=`"logo`">$body</svg>"
}
function CmdHtml($files) {
    $files = @($files); $logo = $null
    for ($i = 0; $i -lt $files.Count; $i++) {
        if ($files[$i] -ceq '--logo') {
            $logo = $files[$i + 1]
            $files = @(for ($j = 0; $j -lt $files.Count; $j++) { if ($j -ne $i -and $j -ne $i + 1) { $files[$j] } })
            break
        }
    }
    $pr = LoadProject $files
    $ew = EmitDiags $true
    if ($ew[0]) { return 1 }
    $plates = @(AllPlates $pr.models)
    $pageof = NewH
    for ($i = 0; $i -lt $plates.Count; $i++) { $pageof[(PlateId $plates[$i][0] $plates[$i][1])] = $i + 2 }
    $docs = NewH; $dk = @()
    foreach ($t in $pr.models) {
        foreach ($el in @(@(, $t) + @(Desc $t))) {
            if (@($el.doc).Count) { $key = DKey $t $el; if (-not $docs.ContainsKey($key)) { $dk += , $key }; $docs[$key] = DocHtml $el }
            foreach ($p in $el.ports) {
                if (@($p.doc).Count) { $key = DKey $t $p; if (-not $docs.ContainsKey($key)) { $dk += , $key }; $docs[$key] = DocHtml $p }
            }
        }
    }
    $out = @{}; $k = 0
    $out[$k++] = "<!doctype html><meta charset='utf-8'><meta name='viewport' content='width=device-width,initial-scale=1'><title>IDEF0 drawing set</title><style>$($script:HTML_CSS)</style>"
    $out[$k++] = "<h1 id='top'>" + (LogoSvg $logo) + 'IDEF0 drawing set &mdash; p.1: node index and interface table</h1>'
    $out[$k++] = "<div class='p1'>"
    $out[$k++] = '<table><caption>Node index</caption><tr><th>NODE</th><th>TITLE</th><th>NUMBER</th></tr>'
    for ($i = 0; $i -lt $plates.Count; $i++) {
        $t = $plates[$i][0]; $node = $plates[$i][1]
        $plid = PlateId $t $node
        $key = DKey $t $node
        $cls = if ($docs.ContainsKey($key)) { " class='hasdoc' data-doc='$key'" } else { '' }
        $out[$k++] = "<tr><td><a href='#plate-$plid'>$plid</a></td><td$cls>" + (Esc $node.name) + "</td><td><a href='#plate-$plid'>p." + ($i + 2) + '</a></td></tr>'
    }
    $out[$k++] = '</table>'
    $out[$k++] = '<table><caption>Interface table</caption><tr><th>SOURCE</th><th>DEST</th><th>FLOW</th></tr>'
    foreach ($r in $pr.rows) {
        $s = $r[0]; $d = $r[1]; $name = $r[2]
        $sp = PlateOfPort $s $pageof; $dp = PlateOfPort $d $pageof
        $sc = if ($null -ne $sp) { "<a href='#plate-$sp'>$($s.node_id)</a>" } else { $s.node_id }
        $dc = if ($null -ne $dp) { "<a href='#plate-$dp'>$($d.node_id)</a>" } else { $d.node_id }
        $out[$k++] = "<tr><td>$sc</td><td>$dc</td><td>" + (Esc $name) + '</td></tr>'
    }
    $out[$k++] = '</table>'
    $out[$k++] = '</div>'
    for ($i = 0; $i -lt $plates.Count; $i++) {
        $t = $plates[$i][0]; $node = $plates[$i][1]; $boxes = $plates[$i][2]
        $plid = PlateId $t $node
        $out[$k++] = "<div class='plate' id='plate-$plid'>"
        $nav = @("<a href='#top'>&#8962; index</a>")
        if ($node.tag -ceq 'a') {
            $par = $node.parent
            $up = if ($par.tag -ceq 'a') { $par.node_id } else { ModelPlateId $par }
            $nav += "<a href='#plate-$up'>&#8593; $up</a>"
        } else { $nav += "<span class='dim'>top plate</span>" }
        $nav += "<a href='javascript:history.back()'>&#8592; back</a>"
        $nav += "<a href='javascript:history.forward()'>fwd &#8594;</a>"
        $nav += "<span class='dim'>$plid &middot; p." + ($i + 2) + '</span>'
        $zoom = "<span class='zoom'><a href='#' class='fit on' onclick='return zoom(0)'>fit</a> &middot; <a href='#' class='one' onclick='return zoom(1)'>1:1</a></span>"
        $out[$k++] = "<div class='nav'>$zoom" + ($nav -join ' &middot; ') + '</div>'
        if (@($node.doc).Count) { $out[$k++] = "<details class='notes'><summary>notes: " + (Esc $node.name) + '</summary>' + (DocHtml $node) + '</details>' }
        $out[$k++] = SvgPlate $t $node $boxes ($i + 2) $true
        $out[$k++] = '</div>'
    }
    $payload = '{' + ((@(foreach ($key in $dk) { (PyJsonStr $key) + ': ' + (PyJsonStr $docs[$key]) })) -join ', ') + '}'
    $payload = $payload.Replace('</', '<\/')
    $out[$k++] = "<div id='tip'></div><script>const DOCS=$payload;`n" + $script:HTML_JS + '</script>'
    P (((@(for ($i = 0; $i -lt $k; $i++) { $out[$i] })) -join "`n") + "`n")
    0
}

# ================================================================ fmt
function CmdFmt($mode, [bool]$write, $files) {
    $pr = LoadProject $files $false
    $ew = EmitDiags $true
    if ($ew[0]) { PErr 'fmt: refusing to rewrite files with errors'; return 1 }
    foreach ($f in $files) {
        $lines = @()
        foreach ($r in $pr.doc[$f]) {
            $kind = $r[0]; $raw = $r[1]; $node = $r[2]
            if ($kind -ceq 'raw' -or $null -eq $node) { $lines += , $raw; continue }
            if ($mode -ceq 'number') { $sfx = if ($node.tag -ceq 't') { $node.letter } else { $node.number } }
            elseif ($mode -ceq 'auto') { $sfx = if ($node.tag -ceq 't') { $node.letter } else { '#' } }
            else { $sfx = if ($node.suffix -ne '') { $node.suffix } else { '#' } }
            $line = (' ' * $node.indent) + $node.tag + $sfx + ' ' + $node.name
            if (HasLink $node) { $line += " $($node.link_dir) " + ($node.link_path -join '|') }
            if ($null -ne $node.trail) { $line += '  ' + $node.trail }
            $lines += , $line
        }
        $text = ($lines -join "`n") + "`n"
        if ($write) { WriteText $f $text }
        else {
            if (@($files).Count -gt 1) { P "==> $f <==`n" }
            P $text
        }
    }
    if ($write) { $md = if ($null -ne $mode) { $mode } else { 'normalize' }; P ("fmt: rewrote $(@($files).Count) file(s) [$md]`n") }
    0
}

# ================================================================ main
function Main($argv) {
    $argv = @($argv)
    if (-not $argv.Count) { P ($script:USAGE + "`n"); return 2 }
    $cmd = $argv[0]; $rest = @($argv | Select-Object -Skip 1)
    switch -CaseSensitive ($cmd) {
        'lint' { return CmdLint $rest }
        'dump' { return CmdDump $rest }
        'links' { return CmdLinks $rest }
        'text' { return CmdText $rest }
        'html' { return CmdHtml $rest }
        'svg' {
            if (-not $rest.Count) { PErr 'usage: idef0 svg NODE FILE...'; return 2 }
            return CmdSvg $rest[0] @($rest | Select-Object -Skip 1)
        }
        'fmt' {
            $mode = $null; $write = $false; $files = @()
            foreach ($a in $rest) {
                if ($a -ceq '--number') { $mode = 'number' } elseif ($a -ceq '--auto') { $mode = 'auto' } elseif ($a -ceq '--write') { $write = $true } else { $files += $a }
            }
            return CmdFmt $mode $write $files
        }
    }
    PErr ('idef0: unknown command ' + (PyRepr $cmd))
    P ($script:USAGE + "`n")
    2
}

# --out FILE: stdout to a UTF-8 file (this port's addition)
$argv = @(); $outFile = $null
for ($i = 0; $i -lt $script:CLIARGS.Count; $i++) {
    if ($script:CLIARGS[$i] -ceq '--out' -and $i + 1 -lt $script:CLIARGS.Count) { $outFile = $script:CLIARGS[$i + 1]; $i++ } else { $argv += , $script:CLIARGS[$i] }
}
if ($argv.Count -and $argv[0] -ceq '__lib') { return }
$rc = 2
try { $rc = Main $argv }
catch { PErr ("idef0: " + $_.Exception.Message); $rc = 2 }
Flush $outFile
exit $rc
