<#
doors2v2.ps1 : port IBM DOORS (9.x classic) and DOORS Next requirement modules into SysML v2 text: one package per
module, headings as requirement groups, objects as requirements with their DOORS ID as short name, information objects
as comments, DOORS links as satisfy / verify / dependency. A port of the kit's tools/sysml/doors2v2.pl to Windows
PowerShell 5.1 (Constrained Language Mode safe): same options, same files, same exit codes.

  doors2v2.cmd -o DIR [--prefix P] [--marking LEVEL] [--tests MODULE]... [--design MODULE]... [--keep ATTR]...
               [--map FIELD=COLUMN]... [--id-prefix PFX] [--no-provenance] EXPORT...

EXPORT: a module exported as CSV or TSV (DOORS 9 "Export to spreadsheet", DOORS Next CSV; UTF-8, UTF-16 or
Windows-1252), or ReqIF (.reqif, .reqifz) from DOORS 9 or DOORS Next (a .reqifz needs ziplib.ps1 one folder up).
Writes DIR\model\requirements\*.sysml, DIR\model\library\DoorsSource.sysml, links and verification packages,
DIR\ids.tsv and DIR\CONVERSION.txt. Exit status: 0 clean, 1 findings to finish by hand, 2 usage or input error.

Text here is Unicode (the Perl decodes its input too), so the regular expressions run in .NET's default mode.
#>
. "$PSScriptRoot\reqiflib.ps1"
$script:UI = [System.Text.RegularExpressions.RegexOptions]::IgnoreCase -bor [System.Text.RegularExpressions.RegexOptions]::CultureInvariant
function UM([string]$s, [string]$re) { [regex]::Match($s, $re) }
function UT([string]$s, [string]$re) { [regex]::Match($s, $re).Success }
function UTI([string]$s, [string]$re) { [regex]::Match($s, $re, $script:UI).Success }
function UR([string]$s, [string]$re, [string]$to) { [regex]::Replace($s, $re, $to) }
function ULc([string]$s) { $s.ToLowerInvariant() }
function Fail([string]$m) { ErrLines (StrToUtf8 "doors2v2: $m"); $script:RC = 2; throw 'doors2v2-exit' }

# ---------------------------------------------------------------- decoding (Encode::decode)
function CpStr([int]$cp) { if ($cp -ge 0x10000) { $cp -= 0x10000; return [string][char](0xD800 + ($cp -shr 10)) + [char](0xDC00 + ($cp -band 0x3FF)) }; [string][char]$cp }
function DecodeUtf8Strict([string]$b) {                # byte string -> string, or $null if not strict UTF-8 (FB_CROAK)
    if ($b -cnotmatch '[\x80-\xFF]') { return $b }
    $o = New-Object 'string[]' $b.Length; $n = 0; $i = 0; $blen = $b.Length
    while ($i -lt $blen) {
        $c = [int]$b[$i]
        if ($c -lt 0x80) { $o[$n++] = [string][char]$c; $i++; continue }
        $need = 0; $cp = 0; $min = 0
        if ($c -ge 0xC2 -and $c -le 0xDF) { $need = 1; $cp = $c -band 0x1F; $min = 0x80 }
        elseif ($c -ge 0xE0 -and $c -le 0xEF) { $need = 2; $cp = $c -band 0x0F; $min = 0x800 }
        elseif ($c -ge 0xF0 -and $c -le 0xF4) { $need = 3; $cp = $c -band 0x07; $min = 0x10000 }
        else { return $null }
        if ($i + $need -ge $blen) { return $null }
        for ($k = 1; $k -le $need; $k++) { $d = [int]$b[$i + $k]; if ($d -lt 0x80 -or $d -gt 0xBF) { return $null }; $cp = ($cp -shl 6) -bor ($d -band 0x3F) }
        if ($cp -lt $min -or $cp -gt 0x10FFFF -or ($cp -ge 0xD800 -and $cp -le 0xDFFF)) { return $null }
        if (($cp -ge 0xFDD0 -and $cp -le 0xFDEF) -or (($cp -band 0xFFFE) -eq 0xFFFE)) { return $null }     # non-characters
        $o[$n++] = CpStr $cp; $i += $need + 1
    }
    -join $o[0..($n - 1)]
}
function DecodeCp1252([string]$b) {
    $o = New-Object 'char[]' $b.Length
    for ($i = 0; $i -lt $b.Length; $i++) {
        $c = [int]$b[$i]
        if ($c -ge 0x80 -and $c -le 0x9F) { if ($script:CP1252.ContainsKey($c)) { $c = $script:CP1252[$c] } else { $c = 0xFFFD } }
        $o[$i] = [char]$c
    }
    if ($b.Length -eq 0) { return '' }
    -join $o
}
function DecodeUtf16([string]$b, [bool]$le) {
    $n = Floor ($b.Length / 2); if ($n -eq 0) { return '' }
    $u = New-Object 'char[]' $n
    for ($i = 0; $i -lt $n; $i++) { $a = [int]$b[2 * $i]; $c = [int]$b[2 * $i + 1]; $u[$i] = if ($le) { [char]($a -bor ($c -shl 8)) } else { [char](($a -shl 8) -bor $c) } }
    -join $u
}
function Slurp([string]$f) {
    if (UTI $f '\.reqifz$') { $raw = FromZip $f } else { $raw = ReadBytes $f }
    if ($raw.StartsWith([string][char]0xFF + [char]0xFE, $script:ORD)) { $t = DecodeUtf16 $raw.Substring(2) $true }
    elseif ($raw.StartsWith([string][char]0xFE + [char]0xFF, $script:ORD)) { $t = DecodeUtf16 $raw.Substring(2) $false }
    elseif ($raw -cmatch '^(?:[^\x00]\x00){8}') { $t = DecodeUtf16 $raw $true }
    else { $t = DecodeUtf8Strict $raw; if ($null -eq $t) { $t = DecodeCp1252 $raw } }
    if ($t.Length -gt 0 -and [int]$t[0] -eq 0xFEFF) { $t = $t.Substring(1) }
    $t.Replace("`r`n", "`n").Replace("`r", "`n")
}
function FromZip([string]$f) {
    $zl = Join-Path $PSScriptRoot '..\ziplib.ps1'
    if (-not (Test-Path -LiteralPath $zl)) { Fail "${f}: ziplib.ps1 is not available; unzip the file and pass the .reqif inside" }
    . $zl
    $ents = $null; try { $ents = @(Read-ZipEntries -Path $f | ForEach-Object { $_ }) } catch { Fail "${f}: not a readable zip" }
    $best = ''
    foreach ($e in $ents) {
        $b = Read-ZipEntry -Path $f -Name $e.name
        $data = if ($null -eq $b -or @($b).Count -eq 0) { '' } else { -join [char[]]$b }
        if ($data -cmatch '<REQ-IF\b' -and $data.Length -gt $best.Length) { $best = $data }
    }
    if ($best.Length -eq 0) { Fail "${f}: no ReqIF member found" }
    $best
}

# ---------------------------------------------------------------- options and fields
$script:FIELDRE = [ordered]@{
    id = '^(?:object identifier|id|identifier|reqif\.foreignid|doors id|req(?:uirement)? ?id)$'
    heading = '^(?:object heading|heading|reqif\.chaptername|title)$'
    text = '^(?:object text|primary text|reqif\.text|text|description|requirement text)$'
    number = '^(?:object number|paragraph number|section number|number|reqif\.chapternumber)$'
    level = '^(?:object level|level|depth|outline level)$'
    type = '^(?:object type|requirement type|artifact type|type|category|object class)$'
    absno = '^(?:absolute number|absno)$'
}
function FieldOf([string]$name) {
    foreach ($f in $script:MAP.Keys) { if ((ULc $script:MAP[$f]) -ceq (ULc $name)) { return $f } }
    foreach ($f in @('id', 'heading', 'text', 'number', 'level', 'type', 'absno')) { if ($script:MAP.ContainsKey($f)) { continue }; if (UTI $name $script:FIELDRE[$f]) { return $f } }
    if (UTI $name 'link|satisf|verif|validat|deriv|refin|trace') { return 'link' }
    $null
}
function LinkKind([string]$c) {
    if (UTI $c 'verif|validat|test') { return 'verify' }; if (UTI $c 'satisf') { return 'satisfy' }
    if (UTI $c 'deriv') { return 'derive' }; if (UTI $c 'refin') { return 'refine' }; 'trace'
}

# ---------------------------------------------------------------- XML (doors2v2's own small reader)
$script:ENT = NewH; foreach ($kv in @(@('lt', '<'), @('gt', '>'), @('amp', '&'), @('quot', '"'), @('apos', "'"), @('nbsp', ' '))) { $script:ENT[$kv[0]] = $kv[1] }
function Unent([string]$s) {
    $ms = [regex]::Matches($s, '&(#[xX][0-9a-fA-F]+|#\d+|\w+);')
    if ($ms.Count -eq 0) { return $s }
    $o = @(); $at = 0
    foreach ($m in $ms) {
        $o += $s.Substring($at, $m.Index - $at); $e = $m.Groups[1].Value
        if ($e -cmatch '^#[xX]') { $o += CpStr ([long]('0x' + $e.Substring(2))) }
        elseif ($e.StartsWith('#')) { $o += CpStr ([long]$e.Substring(1)) }
        elseif ($script:ENT.ContainsKey($e)) { $o += $script:ENT[$e] } else { $o += "&$e;" }
        $at = $m.Index + $m.Length
    }
    $o += $s.Substring($at)
    -join $o
}
function ParseXml([string]$t, [string]$file) {
    $doc = @{ tag = '#doc'; a = (NewH); kids = (NewL); line = 1 }
    $st = NewL; LAdd $st $doc; $line = 1; $pos = 0
    $reT = New-Object regex '\G([^<]+)'
    $reO = New-Object regex '\G<(!--|!\[CDATA\[|\?|!)'
    $reE = New-Object regex '\G<\/([^\s>]+)\s*>'
    $rxSep = New-Object regex ('\G<([^\s\/>!?]+)((?:\s+[^\s=\/>]+\s*=\s*(?:"[^"]*"|''[^'']*''))*)\s*(\/?)>')
    $reA = New-Object regex ('([^\s=]+)\s*=\s*(?:"([^"]*)"|''([^'']*)'')')
    while ($pos -lt $t.Length) {
        $m = $reT.Match($t, $pos)
        if ($m.Success) { $s = $m.Groups[1].Value; $line += CountCh $s "`n"; if (UT $s '\S') { LAdd $st.i[$st.n - 1].kids @{ tag = '#text'; text = (Unent $s) } }; $pos += $m.Length; continue }
        $m = $reO.Match($t, $pos)
        if ($m.Success) {
            $op = $m.Groups[1].Value; $c = if ($op -ceq '!--') { '-->' } elseif ($op -ceq '?') { '?>' } elseif ($op -ceq '!') { '>' } else { ']]>' }
            $from = $pos + $m.Length; $end = $t.IndexOf($c, $from, $script:ORD)
            if ($end -lt 0) { throw "${file}:${line}: error: no closing '$c'`n" }
            $s = $t.Substring($from, $end - $from); $pos = $end + $c.Length; $line += CountCh $s "`n"
            if ($op -ceq '![CDATA[') { LAdd $st.i[$st.n - 1].kids @{ tag = '#text'; text = $s } }
            continue
        }
        $m = $reE.Match($t, $pos)
        if ($m.Success) {
            $tg = $m.Groups[1].Value
            if ($st.n -lt 2 -or $st.i[$st.n - 1].tag -cne $tg) { throw "${file}:${line}: error: unexpected </$tg>`n" }
            $st.n--; $pos += $m.Length; continue
        }
        $m = $rxSep.Match($t, $pos)
        if ($m.Success) {
            $tag = $m.Groups[1].Value; $as = $m.Groups[2].Value; $empty = $m.Groups[3].Value
            $n = @{ tag = $tag; a = (NewH); kids = (NewL); line = $line }
            foreach ($am in $reA.Matches($as)) { $n.a[$am.Groups[1].Value] = Unent $(if ($am.Groups[2].Success) { $am.Groups[2].Value } else { $am.Groups[3].Value }) }
            $line += CountCh $as "`n"
            LAdd $st.i[$st.n - 1].kids $n; if ($empty -eq '') { LAdd $st $n }
            $pos += $m.Length; continue
        }
        throw "${file}:${line}: error: malformed XML`n"
    }
    if ($st.n -gt 1) { throw "${file}:${line}: error: unclosed <$($st.i[$st.n - 1].tag)>`n" }
    $doc
}
function Elems($n) { $o = @(); for ($j = 0; $j -lt $n.kids.n; $j++) { $x = $n.kids.i[$j]; if ($x.tag -cne '#text') { $o += , $x } }; return ,$o }
function LTag([string]$t) { UR $t '^.*:' '' }
function DKid($n, [string]$t) { foreach ($x in (Elems $n)) { if ((LTag $x.tag) -ceq $t) { return $x } }; $null }
function TextOf($n) {
    if ($n.tag -ceq '#text') { return $n.text }
    $o = @(); for ($j = 0; $j -lt $n.kids.n; $j++) { $o += TextOf $n.kids.i[$j] }
    $s = -join $o
    if (UTI (LTag $n.tag) '^(?:p|div|li|br|tr|td|th|h\d)$') { $s = " $s " }
    $s
}
function FindAll($n, [string]$t, $out) { foreach ($k in (Elems $n)) { if ((LTag $k.tag) -ceq $t) { LAdd $out $k }; FindAll $k $t $out } }
function NoWs([string]$s) { UR $s '\s' '' }
function Clean($s) {
    if ($null -eq $s) { $s = '' }
    $s = [string]$s
    $m = [regex]::Match($s, '(?s)\{\\rtf.*\}')
    if ($m.Success) { $s = '' }
    if (UTI $s '<\/?(?:p|div|span|br|b|i)\b') { $s = UR $s '<[^>]+>' ' ' }
    if (UT $s '&\w+;') { $s = Unent $s }
    $s = UR $s '\s+' ' '; UR $s '^ | $' ''
}

# ---------------------------------------------------------------- modules and objects
function Note([string]$f, $l, [string]$sev, [string]$m) { LAdd $script:NOTES @{ f = $f; l = [long]$l; i = $script:NOTES.n; t = "${f}:${l}: ${sev}: $m" }; if ($sev -ceq 'warning') { $script:NWARN++ } }
function NewObj($h) { $script:SER++; $h['ser'] = $script:SER; $h }

function ReadCsv([string]$f) {
    $t = Slurp $f
    $nl = $t.IndexOf("`n"); $first = if ($nl -ge 0) { $t.Substring(0, $nl) } else { $t }
    $tc = CountCh $first "`t"; $cc = CountCh $first ','; $sc = CountCh $first ';'
    $sep = if ($tc -gt $cc) { "`t" } elseif ($sc -gt $cc) { ';' } else { ',' }
    $q = [regex]::Escape($sep)
    $rxQuote = New-Object regex '\G"((?:[^"]|"")*)"'
    $rxField = New-Object regex (('\G([^"' + $q + '\n]+)'))
    $rxSep = New-Object regex (('\G' + $q))
    $rows = NewL; $row = NewL; $field = ''; $line = 1; $rowline = 1; $pos = 0
    while ($pos -lt $t.Length) {
        $m = $rxQuote.Match($t, $pos); if ($m.Success) { $v = $m.Groups[1].Value.Replace('""', '"'); $line += CountCh $v "`n"; $field += $v; $pos += $m.Length; continue }
        $m = $rxField.Match($t, $pos); if ($m.Success) { $field += $m.Groups[1].Value; $pos += $m.Length; continue }
        $m = $rxSep.Match($t, $pos); if ($m.Success) { LAdd $row $field; $field = ''; $pos += $m.Length; continue }
        if ($t[$pos] -eq "`n") { LAdd $row $field; LAdd $rows @{ line = $rowline; v = (LArr $row) }; $row = NewL; $field = ''; $line++; $rowline = $line; $pos++; continue }
        if ($t[$pos] -eq '"') { $field += '"'; $pos++; continue }
        Fail "${f}:${line}: cannot read CSV"
    }
    LAdd $row $field
    $last = LArr $row; $any = $false; foreach ($x in $last) { if ($x.Length) { $any = $true } }
    if ($any) { LAdd $rows @{ line = $rowline; v = $last } }
    $rowsA = LArr $rows
    if ($rowsA.Count -eq 0) { Fail "${f}: empty file" }
    $h = @(foreach ($x in $rowsA[0].v) { UR $x '^\s+|\s+$' '' })
    $col = NewH; $links = @(); $keep = @()
    for ($i = 0; $i -lt $h.Count; $i++) {
        $fd = FieldOf $h[$i]; if ($null -eq $fd) { continue }
        if ($fd -ceq 'link') { $links += , @($i, $h[$i]) } elseif (-not $col.ContainsKey($fd)) { $col[$fd] = $i }
    }
    for ($i = 0; $i -lt $h.Count; $i++) { $k = ULc $h[$i]; if ($script:KEEPATTR.ContainsKey($k) -and $script:KEEPATTR[$k]) { $keep += , @($i, $script:KEEPATTR[$k]) } }
    if (-not $col.ContainsKey('id') -and -not $col.ContainsKey('absno') -and -not $col.ContainsKey('text')) {
        Fail ("${f}: no id or text column found (columns: " + ($h -join ', ') + "); use --map id=COLUMN --map text=COLUMN")
    }
    $mname = UR (BaseName $f) '\.[^.]+$' ''
    $mod = NewObj @{ name = $mname; file = $f; objs = (NewL); tests = [bool]$script:TESTMODS.ContainsKey((ULc $mname)) }
    for ($r = 1; $r -lt $rowsA.Count; $r++) {
        $ln = $rowsA[$r].line; $v = @($rowsA[$r].v)
        $nonblank = $false; foreach ($x in $v) { if (UT $x '\S') { $nonblank = $true; break } }
        if (-not $nonblank) { continue }
        $o = NewObj @{ file = $f; line = $ln; module = $mod }
        foreach ($k in $col.Keys) { $ci = $col[$k]; $o[$k] = $(if ($ci -lt $v.Count) { $v[$ci] } else { '' }) }
        if (($null -eq $o.id -or $o.id -eq '') -and $null -ne $o.absno -and $o.absno -ne '') { $o.id = $(if ($null -ne $script:OPT['id-prefix']) { $script:OPT['id-prefix'] } else { '' }) + $o.absno }
        if ($null -eq $o.id) { $o.id = '' }
        $o.raw_text = $(if ($null -ne $o.text) { $o.text } else { '' })
        if (UT $o.raw_text '\{\\rtf|\bOLE\b') { Note $f $ln 'warning' "object '$($o.id)': rich text or an OLE object was dropped" }
        foreach ($k in @('id', 'heading', 'text', 'number', 'level', 'type', 'absno')) { if ($o.ContainsKey($k) -and $null -ne $o[$k]) { $o[$k] = Clean $o[$k] } }
        $o.links = @(foreach ($l in $links) { , @($l[1], $(if ($l[0] -lt $v.Count) { $v[$l[0]] } else { '' })) })
        $o.keep = @(foreach ($kp in $keep) { if ($kp[0] -lt $v.Count -and (UT $v[$kp[0]] '\S')) { , @($kp[1], (Clean $v[$kp[0]])) } })
        LAdd $mod.objs $o
    }
    $os = LArr $mod.objs
    $hasLevel = $false; if ($col.ContainsKey('level')) { foreach ($x in $os) { if (UT $x.level '^\d+$') { $hasLevel = $true; break } } }
    $hasNum = $false; if ($col.ContainsKey('number')) { foreach ($x in $os) { if (UT $x.number '\d') { $hasNum = $true; break } } }
    if ($hasLevel) {
        $stack = NewL
        foreach ($x in $os) {
            $mm = UM $x.level '^(\d+)$'
            $l = if ($mm.Success) { [long]$mm.Groups[1].Value } elseif ($stack.n) { $stack.i[$stack.n - 1].lv + 1 } else { 1 }
            while ($stack.n -and $stack.i[$stack.n - 1].lv -ge $l) { $stack.n-- }
            $x.up = $(if ($stack.n) { $stack.i[$stack.n - 1].o } else { $null })
            $stack.i[$stack.n] = @{ lv = $l; o = $x }; $stack.n++
        }
    } elseif ($hasNum) {
        $bynum = NewH; foreach ($x in $os) { if ($x.number -ne '') { $bynum[$x.number] = $x } }
        foreach ($x in $os) {
            $n = $x.number
            while ($true) {
                $mm = UM $n '[.\-]\d+$'; if (-not $mm.Success) { break }
                $n = $n.Substring(0, $mm.Index)
                if ($bynum.ContainsKey($n) -and $bynum[$n].ser -ne $x.ser) { $x.up = $bynum[$n]; break }
            }
        }
    }
    LAdd $script:MODULES $mod
}

function ReadReqif([string]$f) {
    try { $doc = ParseXml (Slurp $f) $f } catch { if ($_.Exception.Message -eq 'doors2v2-exit') { throw }; ErrLines (StrToUtf8 $_.Exception.Message); $script:RC = 2; throw 'doors2v2-exit' }
    $adef = NewH; $otype = NewH; $rtype = NewH; $so = NewH
    foreach ($k in @('STRING', 'XHTML', 'ENUMERATION', 'INTEGER', 'REAL', 'DATE', 'BOOLEAN')) {
        $d = NewL; FindAll $doc "ATTRIBUTE-DEFINITION-$k" $d
        foreach ($x in (LArr $d)) { $id = KeyOf $x.a['IDENTIFIER']; $adef[$id] = $(if ($x.a.ContainsKey('LONG-NAME')) { $x.a['LONG-NAME'] } else { $x.a['IDENTIFIER'] }) }
    }
    $ev = NewL; FindAll $doc 'ENUM-VALUE' $ev; $enum = NewH
    foreach ($x in (LArr $ev)) { $enum[(KeyOf $x.a['IDENTIFIER'])] = $(if ($x.a.ContainsKey('LONG-NAME')) { $x.a['LONG-NAME'] } else { '' }) }
    $tl = NewL; FindAll $doc 'SPEC-OBJECT-TYPE' $tl; foreach ($x in (LArr $tl)) { $otype[(KeyOf $x.a['IDENTIFIER'])] = $(if ($x.a.ContainsKey('LONG-NAME')) { $x.a['LONG-NAME'] } else { '' }) }
    $rl = NewL; FindAll $doc 'SPEC-RELATION-TYPE' $rl; foreach ($x in (LArr $rl)) { $rtype[(KeyOf $x.a['IDENTIFIER'])] = $(if ($x.a.ContainsKey('LONG-NAME')) { $x.a['LONG-NAME'] } else { 'Link' }) }
    $ol = NewL; FindAll $doc 'SPEC-OBJECT' $ol
    foreach ($x in (LArr $ol)) {
        $o = NewObj @{ file = $f; line = $x.line; rid = $x.a['IDENTIFIER']; keep = @(); links = @() }
        $ty = DKid $x 'TYPE'; $tr = $null; if ($ty) { $e = Elems $ty; if ($e.Count) { $tr = $e[0] } }
        if ($tr) { $k = NoWs (TextOf $tr); $o.type = $(if ($otype.ContainsKey($k)) { $otype[$k] } else { '' }) }
        $vals = DKid $x 'VALUES'
        foreach ($v in $(if ($vals) { Elems $vals } else { @() })) {
            $def = DKid $v 'DEFINITION'; if (-not $def) { continue }
            $de = Elems $def; if (-not $de.Count) { continue }
            $k = NoWs (TextOf $de[0]); if (-not $adef.ContainsKey($k) -or $null -eq $adef[$k]) { continue }
            $an = $adef[$k]
            $val = $null
            if ($v.a.ContainsKey('THE-VALUE')) { $val = $v.a['THE-VALUE'] }
            else {
                $tv = DKid $v 'THE-VALUE'
                if ($tv) { $val = TextOf $tv }
                else {
                    $vs = DKid $v 'VALUES'
                    if ($vs) { $parts = @(); foreach ($e1 in (Elems $vs)) { foreach ($e2 in (Elems $e1)) { $kk = NoWs (TextOf $e2); $parts += $(if ($enum.ContainsKey($kk)) { $enum[$kk] } else { '' }) } }; $val = $parts -join ', ' }
                }
            }
            $val = Clean $val
            $fd = FieldOf $an
            $lk = ULc $an
            if ($script:KEEPATTR.ContainsKey($lk) -and $script:KEEPATTR[$lk]) { if ($val -ne '') { $o.keep += , @($script:KEEPATTR[$lk], $val) } }
            if (-not $fd -or $fd -ceq 'link') { continue }
            if ($null -eq $o[$fd] -or $o[$fd] -eq '') { $o[$fd] = $val }
        }
        if (($null -eq $o.id -or $o.id -eq '') -and $null -ne $o.absno) { $o.id = $(if ($null -ne $script:OPT['id-prefix']) { $script:OPT['id-prefix'] } else { '' }) + $o.absno }
        if ($null -eq $o.id) { $o.id = '' }
        $so[(KeyOf $o.rid)] = $o
    }
    $rels = NewL; FindAll $doc 'SPEC-RELATION' $rels
    foreach ($r in (LArr $rels)) {
        $ends = @(foreach ($w in @('SOURCE', 'TARGET')) { $k = DKid $r $w; $ref = $null; if ($k) { $e = Elems $k; if ($e.Count) { $ref = $e[0] } }; if ($ref) { NoWs (TextOf $ref) } else { '' } })
        $s = $ends[0]; $t = $ends[1]
        $ty = DKid $r 'TYPE'; $tr = $null; if ($ty) { $e = Elems $ty; if ($e.Count) { $tr = $e[0] } }
        $name = 'Link'; if ($tr) { $k = NoWs (TextOf $tr); if ($rtype.ContainsKey($k)) { $name = $rtype[$k] } }
        if ($so.ContainsKey($s)) { $so[$s].links += , @($name, "rid:$t") } else { Note $f $r.line 'warning' "link '$name' from an object not in this file" }
    }
    $specs = NewL; FindAll $doc 'SPECIFICATION' $specs
    $script:placed = NewH
    foreach ($sp in (LArr $specs)) {
        $mod = NewObj @{ name = $(if ($sp.a.ContainsKey('LONG-NAME')) { $sp.a['LONG-NAME'] } else { BaseName $f }); file = $f; objs = (NewL) }
        $mod.tests = [bool]$script:TESTMODS.ContainsKey((ULc $mod.name))
        $ch = DKid $sp 'CHILDREN'; if ($ch) { WalkSpec $ch $null $mod $so }
        LAdd $script:MODULES $mod
    }
    $loose = @(foreach ($k in (SortedKeys $so)) { if (-not $script:placed.ContainsKey($so[$k].ser)) { $so[$k] } })
    if ($loose.Count) {
        $mn = UR (BaseName $f) '\.[^.]+$' ''
        $mod = NewObj @{ name = $mn; file = $f; objs = (NewL); tests = [bool]$script:TESTMODS.ContainsKey((ULc $mn)) }
        foreach ($x in $loose) { $x.module = $mod; LAdd $mod.objs $x }
        LAdd $script:MODULES $mod
    }
}
function KeyOf($k) { if ($null -eq $k) { '' } else { $k } }
function WalkSpec($n, $up, $mod, $so) {
    foreach ($h in (Elems $n)) {
        if ((LTag $h.tag) -cne 'SPEC-HIERARCHY') { continue }
        $ob = DKid $h 'OBJECT'; $ref = $null; if ($ob) { $e = Elems $ob; if ($e.Count) { $ref = $e[0] } }
        $o = $null; if ($ref) { $k = NoWs (TextOf $ref); if ($so.ContainsKey($k)) { $o = $so[$k] } }
        if ($o) {
            $first = -not $script:placed.ContainsKey($o.ser); $script:placed[$o.ser] = 1 + $(if ($script:placed.ContainsKey($o.ser)) { $script:placed[$o.ser] } else { 0 })
            if ($first) { $o.module = $mod; $o.up = $up; LAdd $mod.objs $o }
        }
        $ch = DKid $h 'CHILDREN'; if ($ch) { WalkSpec $ch $(if ($o) { $o } else { $up }) $mod $so }
    }
}

# ---------------------------------------------------------------- classify, name, resolve links
$script:KEYWORD2 = NewH
foreach ($w in ('about abstract accept action actor after alias all allocate allocation analysis and as assert assign assume at attribute bind binding by calc case comment concern connect connection constant constraint ' +
    'crosses decide def default defined dependency derived do doc else end entry enum event exhibit exit expose false filter first flow for fork frame from hastype if implies import in include individual inout interface istype item ' +
    'join language library locale loop merge message meta metadata nonunique not null objective occurrence of or ordered out package parallel part perform port private protected public redefines ref references render rendering rep ' +
    'require requirement return satisfy send snapshot specializes stakeholder standard state subject subsets succession terminate then timeslice to transition true until use variant variation verification verify via view viewpoint when ' +
    'while xor').Split(' ')) { $script:KEYWORD2[$w] = 1 }
$script:STOP = NewH
foreach ($w in 'the a an shall be is are of to and or for with within in on at by from than that this which its it will should must all each any as'.Split(' ')) { $script:STOP[$w] = 1 }
function Words([string]$s) { @([regex]::Split($s, '[^A-Za-z0-9]+') | Where-Object { $_.Length }) }
function UcFirst([string]$w) { if ($w.Length -eq 0) { return $w }; $w.Substring(0, 1).ToUpperInvariant() + $w.Substring(1) }
function Camel($s, [bool]$upper) {
    if ($null -eq $s) { $s = '' }
    $w = Words ([string]$s); if ($w.Count -eq 0) { return '' }
    $r = -join @(foreach ($x in $w) { UcFirst $x })
    if (-not $upper) {
        $m = [regex]::Match($r, '^([A-Z]+)(?=[A-Z][a-z]|\d|$)')
        if ($m.Success) { $r = $m.Groups[1].Value.ToLowerInvariant() + $r.Substring($m.Length) }
        else { $m = [regex]::Match($r, '^([A-Z])'); if ($m.Success) { $r = $m.Groups[1].Value.ToLowerInvariant() + $r.Substring(1) } }
    }
    if (UT $r '^\d') { $r = "_$r" }
    $r
}
function QShort([string]$s) { "'" + (UR $s '([''\\])' '\$1') + "'" }
function Sq($s) { if ($null -eq $s) { $s = '' }; '"' + (UR ([string]$s) '(["\\])' '\$1') + '"' }
function NE($s) { $null -ne $s -and [string]$s -ne '' }            # ($x // '') ne ''
function PTrue($s) { $null -ne $s -and [string]$s -ne '' -and [string]$s -ne '0' }   # Perl truth of a string

function HasReq($o) { if ($o.kind -ceq 'req') { return $true }; foreach ($k in (LArr $o.kids)) { if (HasReq $k) { return $true } }; $false }
function NameFor($o, [string]$scope) {
    $n = ''
    if (NE $o.heading) { $n = Camel $o.heading $false }
    if ($n -eq '') {
        $w = @(Words $(if ($null -ne $o.text) { $o.text } else { '' }) | Where-Object { -not $script:STOP.ContainsKey((ULc $_)) })
        if ($w.Count) { $last = if ($w.Count - 1 -lt 4) { $w.Count - 1 } else { 4 }; $n = Camel ($w[0..$last] -join ' ') $false }
    }
    if ($n -eq '') { $n = Camel ('r ' + $o.id) $false }
    if ($n -eq '') { $n = 'unnamed' }
    if ($script:KEYWORD2.ContainsKey($n)) { $n += '_' }
    $b = $n; $i = 1; while ($script:TAKEN.ContainsKey("$scope`0$n")) { $i++; $n = "$b$i" }; $script:TAKEN["$scope`0$n"] = 1
    $n
}

# ---------------------------------------------------------------- emit
function DocLines($text, [string]$ind, [string]$kw) {
    if (-not $kw) { $kw = 'doc' }
    $text = ([string]$text).Replace('*/', '* /')
    if ($text -eq '') { return ,@() }
    $w = @([regex]::Split($text, ' ')); $n = $w.Count; while ($n -gt 0 -and $w[$n - 1] -eq '') { $n-- }   # Perl split drops trailing empty fields
    $l = NewL; LAdd $l ''
    for ($j = 0; $j -lt $n; $j++) {
        $x = $w[$j]; $cur = $l.i[$l.n - 1]
        if ($cur.Length -and ($cur.Length + 1 + $x.Length) -gt (96 - $ind.Length - 8)) { LAdd $l $x }
        else { $l.i[$l.n - 1] = $cur + $(if ($cur.Length) { ' ' } else { '' }) + $x }
    }
    $la = LArr $l
    $out = @("$ind$kw /* $($la[0])")
    for ($j = 1; $j -lt $la.Count; $j++) { $out += "$ind     * $($la[$j])" }
    $out[$out.Count - 1] += ' */'
    return ,$out
}
function Prov($o, [string]$ind) {
    $l = @()
    if ($script:OPT['provenance']) {
        $parts = ''; foreach ($p in @(@('objectNumber', $o.number), @('objectType', $o.type))) { if (NE $p[1]) { $parts += " $($p[0]) = " + (Sq $p[1]) + ';' } }
        $l += "$ind@DoorsObject { module = " + (Sq $o.module.name) + ';' + $parts + ' }'
    }
    foreach ($k in @($o.keep)) { if ($null -ne $k) { $l += "$ind@DoorsAttribute { name = " + (Sq $k[0]) + '; value = ' + (Sq $k[1]) + '; }' } }
    return ,$l
}
function PathOf($o) { $p = @(); $x = $o; while ($x) { if ($x.v2) { $p = @($x.v2) + $p }; $x = $x.up }; $p -join '.' }
function RefOf($o) { "$($o.module.pkg)::" + (PathOf $o) }
function EmitObj($o, $lst, [string]$ind) {
    $k = $o.kind
    if ($k -ceq 'empty') { return }
    if (($o.istest -or $o.isdesign) -and $k -ceq 'req') { foreach ($x in (LArr $o.kids)) { EmitObj $x $lst $ind }; return }
    if ($k -ceq 'info' -or $k -ceq 'hcomment') {
        $t = @(@($o.number, $o.heading, $o.text) | ForEach-Object { if ($null -eq $_) { '' } else { $_ } } | Where-Object { $_ -ne '' }) -join ' - '
        if ($t -ne '') { foreach ($x in (DocLines ($(if ($o.id -ne '') { "[$($o.id)] " } else { '' }) + $t) $ind 'comment')) { LAdd $lst $x } }
        foreach ($x in (LArr $o.kids)) { EmitObj $x $lst $ind }
        return
    }
    $scope = if ($o.up) { "o$($o.up.ser)" } else { "m$($o.module.ser)" }
    $o.v2 = NameFor $o $scope
    $head = "${ind}requirement " + $(if ($o.id -ne '') { '<' + (QShort $o.id) + '> ' } else { '' }) + $o.v2
    $body = @()
    if ($k -ceq 'heading') { $docs = @(@($(if ($null -ne $o.number) { $o.number } else { '' }), $o.heading) | Where-Object { $_ -ne '' }) -join ' ' }
    else { $docs = if ($null -ne $o.text) { $o.text } else { '' } }
    if ($docs -eq '' -and (NE $o.heading)) { $docs = $o.heading }
    $body += DocLines $docs "$ind    "
    $body += Prov $o "$ind    "
    $sub = NewL; foreach ($x in (LArr $o.kids)) { EmitObj $x $sub "$ind    " }
    if ($body.Count -or $sub.n) { LAdd $lst "$head {"; foreach ($x in $body) { LAdd $lst $x }; foreach ($x in (LArr $sub)) { LAdd $lst $x }; LAdd $lst "$ind}" }
    else { LAdd $lst "$head;" }
    if ($k -ceq 'req' -and -not (NE $o.text)) { Note $o.file $o.line 'warning' "requirement '$($o.id)' has no text" }
}

# ---------------------------------------------------------------- main
function Main($argv) {
    $g = GetOpt $argv @('o=s', 'prefix=s', 'marking=s', 'tests=s@', 'design=s@', 'keep=s@', 'map=s@', 'id-prefix=s', 'provenance!')
    $script:OPT = $g.opts
    if (-not $script:OPT.ContainsKey('prefix')) { $script:OPT['prefix'] = '' }
    if (-not $script:OPT.ContainsKey('provenance')) { $script:OPT['provenance'] = 1 }
    if ($g.err) { ErrLines $g.err }
    $files = @($g.args)
    if (-not $g.ok -or $files.Count -eq 0 -or -not $script:OPT['o']) {
        ErrLines "usage: perl doors2v2.pl -o DIR [--prefix P] [--marking LEVEL] [--tests MODULE]... [--keep ATTR]... [--map FIELD=COLUMN]... [--id-prefix PFX] [--no-provenance] EXPORT..."
        $script:RC = 2; return
    }
    if ($null -ne $script:OPT['marking'] -and -not (UT $script:OPT['marking'] '^\w+$')) { Fail '--marking must be an identifier' }
    $script:MAP = NewH
    foreach ($x in @($script:OPT['map'])) { if ($null -eq $x) { continue }; $p = $x.Split([char[]]'=', 2); if ($p.Count -lt 2 -or -not (UT $p[0] '^(?:id|heading|text|number|level|type)$')) { Fail '--map needs FIELD=COLUMN with FIELD one of id heading text number level type' }; $script:MAP[$p[0]] = $p[1] }
    $script:TESTMODS = NewH; foreach ($x in @($script:OPT['tests'])) { if ($null -ne $x) { $script:TESTMODS[(ULc $x)] = 1 } }
    $script:DESIGN = NewH; foreach ($x in @($script:OPT['design'])) { if ($null -ne $x) { $script:DESIGN[(ULc $x)] = 1 } }
    $script:KEEPATTR = NewH; foreach ($x in @($script:OPT['keep'])) { if ($null -ne $x) { $script:KEEPATTR[(ULc $x)] = $x } }
    $script:MODULES = NewL; $script:NOTES = NewL; $script:NWARN = 0; $script:SER = 0; $script:TAKEN = NewH

    foreach ($f in $files) {
        if (-not (Test-Path -LiteralPath $f -PathType Leaf)) { Fail "${f}: no such file" }
        if (UTI $f '\.reqifz?$') { ReadReqif $f } else { ReadCsv $f }
    }
    $mods = LArr $script:MODULES
    $BYID = NewH; $OBJ = NewH
    foreach ($m in $mods) {
        $pk = (Camel $script:OPT['prefix'] $true) + (Camel $m.name $true); if ($pk -eq '') { $pk = (Camel $script:OPT['prefix'] $true) + 'Module' }
        $m.pkg = $pk
        foreach ($o in (LArr $m.objs)) {
            $ty = if ($null -ne $o.type) { $o.type } else { '' }
            $o.kids = NewL
            $o.istest = [bool]$m.tests -or (UTI $ty 'test')
            $o.isdesign = $script:DESIGN.ContainsKey((ULc $m.name)) -or (UTI $ty 'design|component|element')
            $h = if ($null -ne $o.heading) { $o.heading } else { '' }; $tx = if ($null -ne $o.text) { $o.text } else { '' }
            $o.kind = if (UTI $ty 'head|title|section|chapter') { 'heading' } elseif (UTI $ty 'info|note|comment|rationale|description|figure|table') { 'info' } elseif ($h -ne '' -and $tx -eq '') { 'heading' } elseif ($tx -ne '' -or $h -ne '') { 'req' } else { 'empty' }
            if ($o.id -eq '' -and $o.kind -ceq 'req') { Note $o.file $o.line 'warning' "object '$($o.id)' has no ID" }
            if ($o.id -ne '') {
                if ($BYID.ContainsKey($o.id)) { Note $o.file $o.line 'warning' "ID '$($o.id)' also used at $($BYID[$o.id].file):$($BYID[$o.id].line)" } else { $BYID[$o.id] = $o }
            }
            if ($null -ne $o.rid) { $OBJ["rid:$($o.rid)"] = $o }
        }
        foreach ($o in (LArr $m.objs)) { if ($o.up) { LAdd $o.up.kids $o } }
    }
    foreach ($m in $mods) { foreach ($o in (LArr $m.objs)) { if ($o.kind -ceq 'heading' -and -not (HasReq $o)) { $o.kind = 'hcomment' } } }

    # links
    $idKeys = SortWith @($BYID.Keys) { param($a, $b) $b.Length - $a.Length }
    $ids = (@(foreach ($k in $idKeys) { [regex]::Escape($k) }) -join '|')
    $IDRE = if ($ids -ne '') { New-Object regex (('(?<![\w-])(' + $ids + ')(?![\w-])')) } else { $null }
    $SAT = NewL; $VER = NewH; $VERORD = @(); $DEP = NewL; $unres = NewH; $unresFirst = NewH
    foreach ($m in $mods) { foreach ($o in (LArr $m.objs)) {
        foreach ($lk in @($o.links)) {
            if ($null -eq $lk) { continue }
            $col = $lk[0]; $cell = $lk[1]
            $kind = LinkKind $col
            $targets = @()
            $rm = UM $cell '^rid:(.*)$'
            if ($rm.Success) {
                $key = "rid:$($rm.Groups[1].Value)"
                if ($OBJ.ContainsKey($key)) { $targets += , $OBJ[$key] }
                else { $u = "(ReqIF object $($rm.Groups[1].Value))"; if (-not $unres.ContainsKey($u)) { $unres[$u] = 0; $unresFirst[$u] = @($o.file, $o.line) }; $unres[$u]++ }
            } else {
                foreach ($item in ([regex]::Split($cell, '[\n;|]+|,\s+(?=\S)'))) {
                    if (-not (UT $item '\S')) { continue }
                    $im = if ($IDRE) { $IDRE.Match($item) } else { $null }
                    if ($im -and $im.Success) { $targets += , $BYID[$im.Groups[1].Value] }
                    else {
                        $km = UM $item '([A-Za-z][\w]*-\d+|\b\d+\b)'
                        $k = if ($km.Success) { $km.Groups[1].Value } else { Clean $item }
                        if (-not $unres.ContainsKey($k)) { $unres[$k] = 0; $unresFirst[$k] = @($o.file, $o.line) }; $unres[$k]++
                    }
                }
            }
            foreach ($t in $targets) {
                if ($t.ser -eq $o.ser) { continue }
                $a = $o; $b = $t
                if ($kind -ceq 'verify') {
                    $test = $null; $req = $null
                    if ($a.istest) { $test = $a; $req = $b } elseif ($b.istest) { $test = $b; $req = $a }
                    if (-not $test) { Note $o.file $o.line 'warning' "'$col' link $($a.id) -> $($b.id): neither end is a test object (use --tests MODULE); kept as a dependency"; LAdd $DEP @($a, $b, $col); continue }
                    if (-not $VER.ContainsKey($test.ser)) { $VER[$test.ser] = NewL; $VERORD += $test.ser }
                    LAdd $VER[$test.ser] $req
                } elseif ($kind -ceq 'satisfy') {
                    if (UTI $col 'by$|ed by') { $req = $a; $by = $b } else { $req = $b; $by = $a }
                    if ($by.isdesign) { LAdd $SAT @($req, $by, $col) }
                    else { LAdd $DEP @($by, $req, $col); $o.satdep = 1 + $(if ($o.satdep) { $o.satdep } else { 0 }) }
                } else { LAdd $DEP @($a, $b, $col) }
            }
        }
    } }
    foreach ($k in (SortedKeys $unres)) { Note $unresFirst[$k][0] $unresFirst[$k][1] 'note' "link target '$k' is not in the imported modules ($($unres[$k]) link(s); first here)" }

    # emit
    $files2 = NewH
    $libimp = @(if ($script:OPT['provenance']) { '    private import DoorsSource::*;' })
    $mark = @(if ($script:OPT['marking']) { '    private import SecMeta::*;'; "    @Marking { level = Level::$($script:OPT['marking']); }" })
    foreach ($m in $mods) {
        $any = $false; foreach ($o in (LArr $m.objs)) { if ($o.kind -ceq 'req' -and -not $o.istest -and -not $o.isdesign) { $any = $true; break } }
        if (-not $any) { continue }
        $lst = NewL
        LAdd $lst "package $($m.pkg) {"
        foreach ($x in (DocLines ("DOORS module '$($m.name)' imported from " + (BaseName $m.file) + ' by doors2v2.pl. Add a subject and, where quantitative, a require constraint to each requirement.') '    ')) { LAdd $lst $x }
        foreach ($x in ($libimp + $mark + @(''))) { LAdd $lst $x }
        foreach ($o in (LArr $m.objs)) { if (-not $o.up) { EmitObj $o $lst '    ' } }
        LAdd $lst '}'
        $files2["requirements/$($m.pkg).sysml"] = LArr $lst
        $m.file_out = "requirements/$($m.pkg).sysml"
    }
    $base = (Camel $script:OPT['prefix'] $true) + 'Doors'
    if ($SAT.n) {
        $lst = NewL; LAdd $lst "package ${base}Satisfaction {"
        foreach ($x in (DocLines 'DOORS satisfaction links. The satisfying DOORS objects are not design elements: replace each part below with the design element that satisfies the requirement.' '    ')) { LAdd $lst $x }
        foreach ($x in ($libimp + $mark + @(''))) { LAdd $lst $x }
        $byn = NewH
        foreach ($s in (LArr $SAT)) {
            $req = $s[0]; $by = $s[1]; $col = $s[2]
            if (-not $req.v2) { continue }
            if (-not $byn.ContainsKey($by.ser)) {
                $src = if (PTrue $by.heading) { $by.heading } elseif ($null -ne $by.text) { $by.text } else { '' }
                $x = Camel $src $false; if ($x.Length -gt 40) { $x = $x.Substring(0, 40) }
                if ($x -eq '') { $x = Camel ('by ' + $(if (PTrue $by.id) { $by.id } else { 'object' })) $false }
                if ($script:KEYWORD2.ContainsKey($x)) { $x += '_' }
                $b = $x; $i = 1; while ($script:TAKEN.ContainsKey("sat`0$x")) { $i++; $x = "$b$i" }; $script:TAKEN["sat`0$x"] = 1
                LAdd $lst ''; LAdd $lst "    part $x; // placeholder for DOORS design object $($by.id) ($($by.module.name))"; $by.part = "${base}Satisfaction::$x"
                $byn[$by.ser] = $x
            }
            LAdd $lst ("    satisfy " + (RefOf $req) + " by $($byn[$by.ser]); // DOORS '$col'")
        }
        LAdd $lst '}'
        $files2["configurations/${base}Satisfaction.sysml"] = LArr $lst
        $s0 = $SAT.i[0]; Note $s0[1].file $s0[1].line 'warning' "$($SAT.n) satisfy link(s) from DOORS design objects: replace the placeholder parts in ${base}Satisfaction with the design elements"
    }
    if ($VER.Count) {
        $lst = NewL; LAdd $lst "package ${base}Verification {"
        foreach ($x in (DocLines 'Verification cases from DOORS test objects. Each holds only its objective: the procedure stays in the test document.' '    ')) { LAdd $lst $x }
        foreach ($x in ($libimp + $mark)) { LAdd $lst $x }
        $all = @(foreach ($m in $mods) { foreach ($o in (LArr $m.objs)) { if ($VER.ContainsKey($o.ser)) { $o } } })
        $tests = SortWith $all { param($a, $b) $c = [string]::CompareOrdinal([string]$a.file, [string]$b.file); if ($c) { $c } else { [long]$a.line - [long]$b.line } }
        $tk = NewH
        foreach ($t in $tests) {
            $src = if (PTrue $t.heading) { $t.heading } elseif ($null -ne $t.text) { $t.text } else { '' }
            $n = Camel $src $true; if ($n.Length -gt 40) { $n = $n.Substring(0, 40) }
            if ($n -eq '') { $n = 'Test' + (Camel $t.id $true) }
            if (-not (UT $n '(?:Test|Inspection|Analysis|Demonstration)$')) { $n += 'Test' }
            $b = $n; $i = 1; while ($tk.ContainsKey($n)) { $i++; $n = "$b$i" }; $tk[$n] = 1
            LAdd $lst ''
            LAdd $lst ("    verification def " + $(if ($t.id -ne '') { '<' + (QShort $t.id) + '> ' } else { '' }) + "$n {")
            $dt = if (PTrue $t.text) { $t.text } elseif (PTrue $t.heading) { $t.heading } else { '' }
            foreach ($x in (DocLines $dt '        ')) { LAdd $lst $x }
            foreach ($x in (Prov $t '        ')) { LAdd $lst $x }
            LAdd $lst '        objective {'
            $seen = NewH
            foreach ($r in (LArr $VER[$t.ser])) { if ($r.v2 -and -not $seen.ContainsKey($r.ser)) { $seen[$r.ser] = 1; LAdd $lst ("            verify " + (RefOf $r) + ';') } }
            LAdd $lst '        }'; LAdd $lst '    }'
            $t.vdef = "${base}Verification::$n"
        }
        LAdd $lst '}'
        $files2["evaluation/${base}Verification.sysml"] = LArr $lst
    }
    if ($DEP.n) {
        $lst = NewL; LAdd $lst "package ${base}Links {"
        foreach ($x in (DocLines 'DOORS derivation, refinement and trace links between requirements, as dependencies from source to target.' '    ')) { LAdd $lst $x }
        foreach ($x in ($libimp + $mark + @(''))) { LAdd $lst $x }
        foreach ($d in (LArr $DEP)) {
            $a = $d[0]; $b = $d[1]; $col = $d[2]
            if (-not ($a.v2 -and $b.v2)) { continue }
            $ra = (RefOf $a).Replace('.', '::'); $rb = (RefOf $b).Replace('.', '::')
            LAdd $lst ("    dependency from $ra to $rb; // DOORS '$col'" + $(if (UTI $col 'satisf') { ' (a requirement satisfying a requirement: derivation)' } else { '' }))
        }
        LAdd $lst '}'
        $files2["requirements/${base}Links.sysml"] = LArr $lst
    }
    if ($script:OPT['provenance']) {
        $files2['library/DoorsSource.sysml'] = @('library package DoorsSource {') +
            (DocLines 'Where an element came from in DOORS: module, object number and type, and any carried attributes. Generated by doors2v2.pl.' '    ') +
            @('    private import ScalarValues::*;') + $mark + @('',
            '    metadata def DoorsObject {', '        doc /* The DOORS object this element was imported from. */',
            '        attribute module : String;', '        attribute objectNumber : String;', '        attribute objectType : String;', '    }',
            '    metadata def DoorsAttribute {', '        doc /* A DOORS attribute value carried over as is. */',
            '        attribute name : String;', '        attribute value : String;', '    }', '}')
    }

    # write (UTF-8)
    $out = $script:OPT['o']
    $hdr = "// Generated by doors2v2.pl from " + (@(foreach ($f in $files) { BaseName $f }) -join ', ') + ". Re-run after each DOORS export and review the diff.`n"
    foreach ($f in (SortedKeys $files2)) {
        $p = "$out/model/$f"; MkPath (UR $p '/[^/]+$' '')
        WriteBytes $p (StrToUtf8 ($hdr + ((@($files2[$f]) | ForEach-Object { "$_`n" }) -join '')))
    }
    MkPath $out
    $tsv = @("doors_id`tmodule`tkind`tv2_name`tsource")
    foreach ($m in $mods) { foreach ($o in (LArr $m.objs)) {
        if ($o.id -eq '') { continue }
        $v2 = if ($o.v2) { RefOf $o } elseif ($null -ne $o.vdef) { $o.vdef } elseif ($null -ne $o.part) { $o.part } elseif (UT $o.kind 'info|hcomment') { '(comment)' } else { '' }
        $kd = if ($o.istest) { 'test' } elseif ($o.isdesign) { 'design' } else { $o.kind }
        $tsv += (@($o.id, $m.name, $kd, $v2, "$($o.file):$($o.line)") -join "`t")
    } }
    WriteBytes "$out/ids.tsv" (StrToUtf8 (($tsv -join "`n") + "`n"))
    $cnt = NewH
    foreach ($m in $mods) { foreach ($o in (LArr $m.objs)) { $k = if ($o.kind -ceq 'req' -and $o.istest) { 'test' } elseif ($o.kind -ceq 'req' -and $o.isdesign) { 'design' } else { $o.kind }; $cnt[$k] = 1 + $(if ($cnt.ContainsKey($k)) { $cnt[$k] } else { 0 }) } }
    $g0 = { param($k) if ($cnt.ContainsKey($k)) { $cnt[$k] } else { 0 } }
    $nver = 0; foreach ($k in $VER.Keys) { $nver += $VER[$k].n }
    $sum = "doors2v2: $($mods.Count) module(s), $(& $g0 'req') requirement(s), $(& $g0 'heading') heading group(s), $((& $g0 'info') + (& $g0 'hcomment')) comment(s), $(& $g0 'test') test(s), $(& $g0 'design') design object(s); links: $($SAT.n) satisfy, $nver verify, $($DEP.n) dependency, $($unres.Count) unresolved; $($script:NWARN) to finish by hand"
    $sorted = SortWith (LArr $script:NOTES) { param($a, $b) $c = [string]::CompareOrdinal($a.f, $b.f); if ($c) { return $c }; if ($a.l -ne $b.l) { return [long]$a.l - [long]$b.l }; $a.i - $b.i }
    $conv = "# doors2v2.pl " + ($files -join ' ') + "`n" + ((@($sorted | ForEach-Object { $_.t + "`n" })) -join '') + "$sum`n"
    WriteBytes "$out/CONVERSION.txt" (StrToUtf8 $conv)
    foreach ($s in $sorted) { if ($s.t -cmatch ': warning: ') { Write-Output $s.t } }
    Write-Output $sum
    $script:RC = $(if ($script:NWARN) { 1 } else { 0 })
}

$script:RC = 0
try { Main $args } catch { if ($_.Exception.Message -ne 'doors2v2-exit') { ErrLines ("doors2v2: " + $_.Exception.Message + "`n" + $_.ScriptStackTrace); $script:RC = 255 } }
if ($PSCommandPath) { exit $script:RC }
$global:LASTEXITCODE = $script:RC
