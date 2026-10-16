<#
reqiflib.ps1 -- the shared code behind reqif2sysml.ps1 and req-recipe.ps1: a port of the kit's lib/XmlLite.pm,
lib/SysmlText.pm and lib/Reqif.pm to Windows PowerShell 5.1, Constrained Language Mode safe.

Dot-source it:  . "$PSScriptRoot\reqiflib.ps1"

Text is handled the way the Perl handles it: as BYTES. A file is read into a string with one char per byte
(0-255), processed, and written back one byte per char, so what goes out is byte-for-byte what the Perl writes,
whatever the input encoding. Regular expressions run in .NET's ECMAScript mode, whose \w \s \d \b are ASCII-only,
as Perl's are on byte strings. Hashtables that must be case-sensitive (Perl hashes are) are made with New-Object.
#>

# ================================================================ basics
$script:RX = [System.Text.RegularExpressions.RegexOptions]::ECMAScript
$script:RXI = [System.Text.RegularExpressions.RegexOptions]::ECMAScript -bor [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
$script:ORD = [System.StringComparison]::Ordinal

function NewH { New-Object hashtable }                 # a case-sensitive hashtable (a Perl hash)
function Rx([string]$s, [string]$re) { [regex]::Match($s, $re, $script:RX) }            # Perl =~ (bytes)
function RxI([string]$s, [string]$re) { [regex]::Match($s, $re, $script:RXI) }          # =~ //i
function RT([string]$s, [string]$re) { [regex]::Match($s, $re, $script:RX).Success }    # boolean match
function RTI([string]$s, [string]$re) { [regex]::Match($s, $re, $script:RXI).Success }
function RA([string]$s, [string]$re) { [regex]::Matches($s, $re, $script:RX) }           # //g list
function RR([string]$s, [string]$re, [string]$to) { [regex]::Replace($s, $re, $to, $script:RX) }   # s///g
function RRI([string]$s, [string]$re, [string]$to) { [regex]::Replace($s, $re, $to, $script:RXI) }
function Expand($m, [string]$to) {                    # a replacement string with $1..$9 and $& (Match.Result is refused in CLM)
    if ($to.IndexOf('$') -lt 0) { return $to }
    $o = ''; $i = 0
    while ($i -lt $to.Length) {
        $c = $to[$i]
        if ($c -eq '$' -and $i + 1 -lt $to.Length) {
            $d = $to[$i + 1]
            if ($d -ge '0' -and $d -le '9') { $o += $m.Groups[[int][string]$d].Value; $i += 2; continue }
            if ($d -eq '&') { $o += $m.Value; $i += 2; continue }
            if ($d -eq '$') { $o += '$'; $i += 2; continue }
        }
        $o += $c; $i++
    }
    $o
}
function R1([string]$s, [string]$re, [string]$to) {    # s/// (first only)
    $m = [regex]::Match($s, $re, $script:RX)
    if (-not $m.Success) { return $s }
    $s.Substring(0, $m.Index) + (Expand $m $to) + $s.Substring($m.Index + $m.Length)
}
function Min2($a, $b) { if ($a -lt $b) { $a } else { $b } }
function Floor($x) { $f = [long]$x; if ($f -gt $x) { $f-- }; $f }
function Trim([string]$s) { RR $s '^[\t\n\x0B\f\r ]+|[\t\n\x0B\f\r ]+$' '' }   # s/^\s+|\s+$//g
function HasNS($s) { ($null -ne $s) -and (RT ([string]$s) '[^\t\n\x0B\f\r ]') }  # defined && /\S/
function LcA([string]$s) {                             # Perl lc on bytes: ASCII letters only
    if ($s -cnotmatch '[A-Z]') { return $s }
    $c = $s.ToCharArray()
    for ($i = 0; $i -lt $c.Length; $i++) { $n = [int]$c[$i]; if ($n -ge 65 -and $n -le 90) { $c[$i] = [char]($n + 32) } }
    -join $c
}
function UcA([string]$s) {
    if ($s -cnotmatch '[a-z]') { return $s }
    $c = $s.ToCharArray()
    for ($i = 0; $i -lt $c.Length; $i++) { $n = [int]$c[$i]; if ($n -ge 97 -and $n -le 122) { $c[$i] = [char]($n - 32) } }
    -join $c
}
function CountCh([string]$s, [string]$ch) { ($s.Length - $s.Replace($ch, '').Length) / $ch.Length }   # tr/x//

# lists: plain arrays grow by copying, so a growing list is @{ n = count; i = hashtable index -> item }
function NewL { @{ n = 0; i = (New-Object hashtable) } }
function LAdd($l, $x) { $l.i[$l.n] = $x; $l.n++ }
function LArr($l) { if ($l.n -eq 0) { return ,@() }; $a = New-Object object[] $l.n; for ($j = 0; $j -lt $l.n; $j++) { $a[$j] = $l.i[$j] }; return ,$a }

# ordinal sorting, stable (Perl's mergesort): Sorted for strings, SortWith with a comparison scriptblock
function SortWith($list, [scriptblock]$cmp) {
    $a = @($list)
    if ($a.Count -lt 2) { return ,$a }
    $w = 1; $n = $a.Count
    while ($w -lt $n) {
        $b = New-Object object[] $n
        for ($lo = 0; $lo -lt $n; $lo += 2 * $w) {
            $mid = Min2 ($lo + $w) $n; $hi = Min2 ($lo + 2 * $w) $n
            $i = $lo; $j = $mid; $k = $lo
            while ($i -lt $mid -and $j -lt $hi) {
                if ((& $cmp $a[$j] $a[$i]) -lt 0) { $b[$k] = $a[$j]; $j++ } else { $b[$k] = $a[$i]; $i++ }
                $k++
            }
            while ($i -lt $mid) { $b[$k] = $a[$i]; $i++; $k++ }
            while ($j -lt $hi) { $b[$k] = $a[$j]; $j++; $k++ }
        }
        $a = $b; $w *= 2
    }
    return ,$a
}
function Sorted($list) { SortWith $list { param($x, $y) [string]::CompareOrdinal([string]$x, [string]$y) } }
function SortedKeys($h) { if ($null -eq $h -or $h.Count -eq 0) { return ,@() }; Sorted @($h.Keys) }

# ================================================================ bytes in, bytes out
function ReadBytes([string]$path) {                    # file -> byte string (one char per byte)
    $b = Get-Content -Encoding Byte -ReadCount 0 -LiteralPath $path -ErrorAction Stop
    if ($null -eq $b) { return '' }
    if ($b -is [byte]) { return [string][char]$b }
    -join [char[]]$b
}
function WriteBytes([string]$path, [string]$s) {       # byte string -> file, exactly those bytes
    if ($s.Length -eq 0) { Set-Content -LiteralPath $path -Value $null -Encoding Byte -NoNewline; if (-not (Test-Path -LiteralPath $path)) { New-Item -ItemType File -Path $path | Out-Null }; return }
    [byte[]]$b = [char[]]$s
    Set-Content -LiteralPath $path -Value $b -Encoding Byte
}
function Utf8Show([string]$s) {                        # byte string holding UTF-8 -> a .NET string, for the console
    if ($s -cnotmatch '[\x80-\xFF]') { return $s }
    $o = New-Object 'char[]' ($s.Length + 1); $n = 0; $i = 0; $blen = $s.Length
    while ($i -lt $blen) {
        $c = [int]$s[$i]; $need = 0; $cp = 0
        if ($c -lt 0x80) { $o[$n++] = [char]$c; $i++; continue }
        if ($c -ge 0xC2 -and $c -le 0xDF) { $need = 1; $cp = $c -band 0x1F } elseif ($c -ge 0xE0 -and $c -le 0xEF) { $need = 2; $cp = $c -band 0x0F } elseif ($c -ge 0xF0 -and $c -le 0xF4) { $need = 3; $cp = $c -band 0x07 }
        $ok = $need -gt 0 -and ($i + $need) -lt $blen
        if ($ok) { for ($k = 1; $k -le $need; $k++) { $d = [int]$s[$i + $k]; if ($d -lt 0x80 -or $d -gt 0xBF) { $ok = $false; break }; $cp = ($cp -shl 6) -bor ($d -band 0x3F) } }
        if (-not $ok) { $o[$n++] = [char]$c; $i++; continue }
        if ($cp -ge 0x10000) { $cp -= 0x10000; $o[$n++] = [char](0xD800 + ($cp -shr 10)); $o[$n++] = [char](0xDC00 + ($cp -band 0x3FF)) } else { $o[$n++] = [char]$cp }
        $i += $need + 1
    }
    -join $o[0..($n - 1)]
}
function OutLines([string]$t) {                        # print text (bytes) to stdout, line for line
    if ($null -eq $t -or $t -eq '') { return }
    if ($t.EndsWith("`n")) { $t = $t.Substring(0, $t.Length - 1) }
    foreach ($l in ($t -split "`n")) { if ($l.EndsWith("`r")) { $l = $l.Substring(0, $l.Length - 1) }; Write-Output (Utf8Show $l) }   # the console ends each line with CRLF
}
function ErrLines([string]$t) {                        # Perl's STDERR (Write-Host: shown, kept out of redirected output)
    if ($null -eq $t -or $t -eq '') { return }
    if ($t.EndsWith("`n")) { $t = $t.Substring(0, $t.Length - 1) }
    foreach ($l in ($t -split "`n")) { Write-Host (Utf8Show $l) }
}
function MkPath([string]$d) { if (-not (Test-Path -LiteralPath $d)) { New-Item -ItemType Directory -Force -Path $d | Out-Null } }
function BaseName([string]$p) { RR $p '.*[/\\]' '' }

function Utf8Enc([int]$c) {                            # code point -> UTF-8 bytes as a byte string (XmlLite::_utf8)
    if ($c -lt 0x80) { return [string][char]$c }
    if ($c -lt 0x800) { return [string][char](0xC0 -bor ($c -shr 6)) + [char](0x80 -bor ($c -band 0x3F)) }
    if ($c -lt 0x10000) { return [string][char](0xE0 -bor ($c -shr 12)) + [char](0x80 -bor (($c -shr 6) -band 0x3F)) + [char](0x80 -bor ($c -band 0x3F)) }
    return [string][char](0xF0 -bor (($c -shr 18) -band 0xFF)) + [char](0x80 -bor (($c -shr 12) -band 0x3F)) + [char](0x80 -bor (($c -shr 6) -band 0x3F)) + [char](0x80 -bor ($c -band 0x3F))
}
function StrToUtf8([string]$s) {                       # a .NET string -> UTF-8 byte string
    $o = New-Object 'string[]' $s.Length; $n = 0
    for ($i = 0; $i -lt $s.Length; $i++) {
        $c = [int]$s[$i]
        if ($c -ge 0xD800 -and $c -le 0xDBFF -and $i + 1 -lt $s.Length) { $d = [int]$s[$i + 1]; if ($d -ge 0xDC00 -and $d -le 0xDFFF) { $c = 0x10000 + (($c - 0xD800) -shl 10) + ($d - 0xDC00); $i++ } }
        $o[$n++] = Utf8Enc $c
    }
    -join $o
}
$script:CP1252 = @{ 0x80 = 0x20AC; 0x82 = 0x201A; 0x83 = 0x0192; 0x84 = 0x201E; 0x85 = 0x2026; 0x86 = 0x2020; 0x87 = 0x2021; 0x88 = 0x02C6; 0x89 = 0x2030; 0x8A = 0x0160; 0x8B = 0x2039; 0x8C = 0x0152; 0x8E = 0x017D
    0x91 = 0x2018; 0x92 = 0x2019; 0x93 = 0x201C; 0x94 = 0x201D; 0x95 = 0x2022; 0x96 = 0x2013; 0x97 = 0x2014; 0x98 = 0x02DC; 0x99 = 0x2122; 0x9A = 0x0161; 0x9B = 0x203A; 0x9C = 0x0153; 0x9E = 0x017E; 0x9F = 0x0178 }
function RecodeSingle([string]$bytes, [string]$enc) {  # single-byte encoding -> UTF-8 bytes (Encode::decode, then encode)
    $o = New-Object 'string[]' $bytes.Length
    $w = $enc -match '^(windows-?1252|cp-?1252)$'
    $l1 = $enc -match '^(iso-?8859-1|latin-?1|l1|iso_8859-1|us-ascii|ascii)$'
    if (-not $w -and -not $l1) { throw "unsupported encoding '$enc' (this port knows UTF-8, UTF-16, ISO-8859-1 and windows-1252)`n" }
    for ($i = 0; $i -lt $bytes.Length; $i++) {
        $c = [int]$bytes[$i]
        if ($w -and $c -ge 0x80 -and $c -le 0x9F) { if ($script:CP1252.ContainsKey($c)) { $c = $script:CP1252[$c] } else { $c = 0xFFFD } }
        $o[$i] = Utf8Enc $c
    }
    -join $o
}
function RecodeUtf16([string]$bytes, [bool]$le) {      # UTF-16 bytes -> UTF-8 bytes
    $n = Floor ($bytes.Length / 2)
    $u = New-Object 'char[]' $n
    for ($i = 0; $i -lt $n; $i++) {
        $a = [int]$bytes[2 * $i]; $b = [int]$bytes[2 * $i + 1]
        $u[$i] = if ($le) { [char]($a -bor ($b -shl 8)) } else { [char](($a -shl 8) -bor $b) }
    }
    if ($n -eq 0) { return '' }
    StrToUtf8 (-join $u)
}

# Perl sprintf '%.1f': round half to even on the binary value (what C's printf does)
function Fmt1($x) {
    $d = [double]$x; $neg = $d -lt 0; if ($neg) { $d = -$d }
    $t = $d * 10; $f = Floor $t; $r = $t - $f
    if ($r -gt 0.5) { $f++ } elseif ($r -eq 0.5) { if (($f % 2) -ne 0) { $f++ } }
    $s = ('{0}' -f [long]$f); if ($s.Length -lt 2) { $s = '0' + $s }
    $s = $s.Substring(0, $s.Length - 1) + '.' + $s.Substring($s.Length - 1)
    if ($neg -and $f -ne 0) { $s = '-' + $s }
    $s
}
function PadL([string]$s, [int]$w) { if ($s.Length -ge $w) { $s } else { (' ' * ($w - $s.Length)) + $s } }   # %Ns
function PadR([string]$s, [int]$w) { if ($s.Length -ge $w) { $s } else { $s + (' ' * ($w - $s.Length)) } }   # %-Ns

# ================================================================ Getopt::Long (default configuration)
# spec: array of 'name|alias=s' 'x=s@' 'y=s%' 'flag' 'neg!'. Returns @{ ok; opts (case-sensitive hash); args; err }
function GetOpt($argv, $spec) {
    $defs = NewH; $names = @()
    foreach ($s in $spec) {
        $m = Rx $s '^([\w-]+(?:\|[\w-?]+)*)(?:([=:])([si])([@%]?)|(!))?$'
        $al = $m.Groups[1].Value -split '\|'
        $d = @{ key = $al[0]; type = $m.Groups[3].Value; kind = $m.Groups[4].Value; neg = $m.Groups[5].Success }
        foreach ($a in $al) { $defs[$a] = $d; $names += $a; if ($d.neg) { $defs["no$a"] = @{ key = $al[0]; type = ''; kind = ''; negated = $true }; $defs["no-$a"] = $defs["no$a"]; $names += "no$a"; $names += "no-$a" } }
    }
    $o = NewH; $rest = @(); $err = ''
    $argv = @($argv); $i = 0
    while ($i -lt $argv.Count) {
        $a = [string]$argv[$i]; $i++
        if ($a -eq '--') { while ($i -lt $argv.Count) { $rest += $argv[$i]; $i++ }; break }
        if ($a -eq '-' -or -not $a.StartsWith('-')) { $rest += $a; continue }
        $body = if ($a.StartsWith('--')) { $a.Substring(2) } else { $a.Substring(1) }
        $val = $null
        $eq = $body.IndexOf('=')
        if ($eq -ge 0) { $val = $body.Substring($eq + 1); $body = $body.Substring(0, $eq) }
        $d = $null
        foreach ($n in $names) { if ($n -ceq $body) { $d = $defs[$n] } }
        if (-not $d) { foreach ($n in $names) { if ((LcA $n) -ceq (LcA $body)) { $d = $defs[$n] } } }
        if (-not $d) {
            $hits = @($names | Where-Object { (LcA $_).StartsWith((LcA $body), $script:ORD) })
            $keys = @($hits | ForEach-Object { $defs[$_].key } | Select-Object -Unique)
            if ($keys.Count -eq 1) { $d = $defs[$hits[0]] }
            elseif ($keys.Count -gt 1) { $err += "Option $body is ambiguous (" + ((Sorted $hits) -join ', ') + ")`n"; continue }
        }
        if (-not $d) { $err += "Unknown option: $(LcA $body)`n"; continue }
        if ($d.negated) { $o[$d.key] = 0; continue }
        if ($d.type -eq '') {
            if ($null -ne $val) { $err += "Option $body does not take an argument`n"; continue }
            $o[$d.key] = 1; continue
        }
        if ($null -eq $val) {
            if ($i -ge $argv.Count) { $err += "Option $body requires an argument`n"; continue }
            $val = [string]$argv[$i]; $i++
        }
        if ($d.kind -eq '@') { if (-not $o.ContainsKey($d.key)) { $o[$d.key] = @() }; $o[$d.key] += $val }
        elseif ($d.kind -eq '%') {
            if (-not $o.ContainsKey($d.key)) { $o[$d.key] = NewH }
            $k = $val; $v = 1; $e2 = $val.IndexOf('='); if ($e2 -ge 0) { $k = $val.Substring(0, $e2); $v = $val.Substring($e2 + 1) }
            $o[$d.key][$k] = $v
        } else { $o[$d.key] = $val }
    }
    @{ ok = ($err -eq ''); opts = $o; args = $rest; err = $err }
}

# ================================================================ XmlLite (lib/XmlLite.pm)
$script:PREDEF = NewH; $script:PREDEF['lt'] = '<'; $script:PREDEF['gt'] = '>'; $script:PREDEF['amp'] = '&'; $script:PREDEF['quot'] = '"'; $script:PREDEF['apos'] = "'"

function DecodeEntities([string]$s, $ent) {
    if ($null -eq $s -or $s.IndexOf('&') -lt 0) { return $s }
    $ms = RA $s '&(#[xX][0-9a-fA-F]+|#[0-9]+|[A-Za-z_][A-Za-z0-9_.\-]*);'
    if ($ms.Count -eq 0) { return $s }
    $o = @(); $at = 0
    foreach ($m in $ms) {
        $o += $s.Substring($at, $m.Index - $at)
        $r = $m.Groups[1].Value
        if ($r -cmatch '^#[xX](.+)$') { $o += Utf8Enc ([long]('0x' + $Matches[1])) }
        elseif ($r -cmatch '^#(\d+)') { $o += Utf8Enc ([int]$Matches[1]) }
        elseif ($script:PREDEF.ContainsKey($r)) { $o += $script:PREDEF[$r] }
        elseif ($ent -and $ent.ContainsKey($r)) { $o += $ent[$r] }
        else { $o += "&$r;" }
        $at = $m.Index + $m.Length
    }
    $o += $s.Substring($at)
    -join $o
}

# XmlParse(byteString, label, keepWs scriptblock) -> root node @{ n; l; p; u; a (hash); ak (attr order); k (list); line; mixed }
function XmlParse([string]$buf, [string]$label, $keep) {
    $pos = 0; $line = 1; $ent = NewH; $open = NewL
    if ($buf.StartsWith([string][char]0xEF + [char]0xBB + [char]0xBF, $script:ORD)) { $pos = 3 }
    elseif ($buf.Length -ge 2 -and (([int]$buf[0] -eq 0xFF -and [int]$buf[1] -eq 0xFE) -or ([int]$buf[0] -eq 0xFE -and [int]$buf[1] -eq 0xFF))) {
        $le = [int]$buf[0] -eq 0xFF; $buf = RecodeUtf16 $buf.Substring(2) $le; $pos = 0
    }
    $buf = $buf.Replace("`r`n", "`n").Replace("`r", "`n")     # Perl folds CRLF/CR in text, attributes and in line counts
    $root = $null; $stack = NewL; $ns = NewL
    $text = ''
    $addText = {
        param($t)
        if ($stack.n -eq 0) { return }
        $top = $stack.i[$stack.n - 1]
        if (-not (RT $t '[^\t\n\x0B\f\r ]') -and -not $top.mixed) { return }
        $k = $top.k
        if ($k.n -gt 0 -and $k.i[$k.n - 1] -is [string]) { $k.i[$k.n - 1] = $k.i[$k.n - 1] + $t } else { LAdd $k $t }
    }
    $blen = $buf.Length
    $err = { param($msg) throw "${label}:${line}: $msg`n" }
    while ($true) {
        $lt = $buf.IndexOf('<', $pos)
        if ($lt -lt 0) { $text += $buf.Substring($pos); $line += CountCh $buf.Substring($pos) "`n"; $pos = $blen; break }
        if ($lt -gt $pos) { $seg = $buf.Substring($pos, $lt - $pos); $text += $seg; $line += CountCh $seg "`n"; $pos = $lt }
        if ($buf.IndexOf('<!--', $pos, $script:ORD) -eq $pos) {
            $e = $buf.IndexOf('-->', $pos + 4, $script:ORD); if ($e -lt 0) { & $err 'unterminated comment' }
            $line += CountCh $buf.Substring($pos, $e + 3 - $pos) "`n"; $pos = $e + 3; continue
        }
        if ($buf.IndexOf('<![CDATA[', $pos, $script:ORD) -eq $pos) {
            $e = $buf.IndexOf(']]>', $pos + 9, $script:ORD); if ($e -lt 0) { & $err 'unterminated CDATA section' }
            $c = $buf.Substring($pos + 9, $e - $pos - 9)
            $line += CountCh $buf.Substring($pos, $e + 3 - $pos) "`n"; $pos = $e + 3
            if ($text -ne '') { $t = DecodeEntities $text $ent; $text = ''; & $addText $t }
            if ($c -ne '') { & $addText $c }
            continue
        }
        if ($buf.IndexOf('<?', $pos, $script:ORD) -eq $pos) {
            $e = $buf.IndexOf('?>', $pos + 2, $script:ORD); if ($e -lt 0) { & $err 'unterminated processing instruction' }
            $pi = $buf.Substring($pos, $e + 2 - $pos)
            $line += CountCh $pi "`n"; $pos = $e + 2
            $m = Rx $pi '^<\?xml[\t\n\x0B\f\r ](?:.|\n)*?encoding[\t\n\x0B\f\r ]*=[\t\n\x0B\f\r ]*["'']([^"'']+)["'']'
            if ($m.Success) {
                $e2 = LcA $m.Groups[1].Value
                if ($e2 -cnotmatch '^utf-?8$' -and $e2 -cnotmatch '^utf-?16') {
                    $buf = $buf.Substring(0, $pos) + (RecodeSingle $buf.Substring($pos) $e2); $blen = $buf.Length
                }
            }
            continue
        }
        if ($pos + 9 -le $blen -and (LcA $buf.Substring($pos, 9)) -ceq '<!doctype') {
            $lb = $buf.IndexOf('[', $pos); $gt = $buf.IndexOf('>', $pos)
            if ($lb -ge 0 -and $lb -lt $gt) {
                $rb = $buf.IndexOf(']', $lb); if ($rb -lt 0) { & $err 'unterminated DOCTYPE' }
                $end = $buf.IndexOf('>', $rb)
                $subset = $buf.Substring($lb + 1, $rb - $lb - 1)
                foreach ($em in (RA $subset '<!ENTITY[\t\n\x0B\f\r ]+([A-Za-z_][A-Za-z0-9_.\-]*)[\t\n\x0B\f\r ]+(?:"([^"]*)"|''([^'']*)'')[\t\n\x0B\f\r ]*>')) {
                    $v = if ($em.Groups[2].Success) { $em.Groups[2].Value } else { $em.Groups[3].Value }
                    $ent[$em.Groups[1].Value] = DecodeEntities $v $null
                }
            } else { $end = $gt }
            if ($end -lt 0) { & $err 'unterminated DOCTYPE' }
            $line += CountCh $buf.Substring($pos, $end + 1 - $pos) "`n"; $pos = $end + 1; continue
        }
        if ($buf.IndexOf('</', $pos, $script:ORD) -eq $pos) {
            $e = $buf.IndexOf('>', $pos); if ($e -lt 0) { & $err 'unterminated end tag' }
            $name = RR $buf.Substring($pos + 2, $e - $pos - 2) '[\t\n\x0B\f\r ]+$' ''
            if ($text -ne '') { $t = DecodeEntities $text $ent; $text = ''; & $addText $t }
            $top = $null; if ($open.n -gt 0) { $open.n--; $top = $open.i[$open.n] }
            if ($null -eq $top) { & $err "end tag </$name> with nothing open" }
            if ($top -cne $name) { & $err "end tag </$name> does not match <$top>" }
            $line += CountCh $buf.Substring($pos, $e + 1 - $pos) "`n"; $pos = $e + 1
            if ($stack.n -gt 0) { $stack.n-- }; if ($ns.n -gt 0) { $ns.n-- }
            continue
        }
        # a start tag: the first '>' outside a quoted attribute value
        $end = -1; $from = $pos + 1
        while ($true) {
            $e = $buf.IndexOf('>', $from)
            if ($e -lt 0) { break }
            $tag = $buf.Substring($pos + 1, $e - $pos - 1)
            if ($tag.IndexOf('<') -ge 0 -and -not (RT $tag '^(?>(?:[^"''<]+|"[^"]*"|''[^'']*'')*)\z')) { break }
            if (-not (RT $tag '["'']') -or (RT $tag '^(?>(?:[^"'']+|"[^"]*"|''[^'']*'')*)\z')) { $end = $e; break }
            $from = $e + 1
        }
        if ($end -lt 0) { & $err 'unterminated start tag' }
        $tag = $buf.Substring($pos + 1, $end - $pos - 1)
        $startline = $line
        $line += CountCh $buf.Substring($pos, $end + 1 - $pos) "`n"; $pos = $end + 1
        $em = Rx $tag '/[\t\n\x0B\f\r ]*$'
        $empty = $em.Success; if ($empty) { $tag = $tag.Substring(0, $em.Index) }
        $tm = Rx $tag '^([^\t\n\x0B\f\r ]+)[\t\n\x0B\f\r ]*((?:.|\n)*)$'
        if (-not $tm.Success) { & $err 'empty tag' }
        $name = $tm.Groups[1].Value; $rest = $tm.Groups[2].Value
        $a = NewH; $order = @(); $ap = 0
        while ($true) {
            $am = [regex]::Match($rest.Substring($ap), '^[\t\n\x0B\f\r ]*([^\t\n\x0B\f\r =]+)[\t\n\x0B\f\r ]*=[\t\n\x0B\f\r ]*(?:"([^"]*)"|''([^'']*)'')', $script:RX)
            if (-not $am.Success) { break }
            $an = $am.Groups[1].Value; $v = if ($am.Groups[2].Success) { $am.Groups[2].Value } else { $am.Groups[3].Value }
            $v = $v.Replace("`n", ' ').Replace("`t", ' ')
            $a[$an] = DecodeEntities $v $ent; $order += $an
            $ap += $am.Length
        }
        if (-not (RT $rest.Substring($ap) '^[\t\n\x0B\f\r ]*$')) { & $err "malformed attributes in <$name>" }
        if ($text -ne '') { $t = DecodeEntities $text $ent; $text = ''; & $addText $t }
        # tree builder (XmlLite::_tree)
        $scope = NewH; if ($ns.n -gt 0) { $prev = $ns.i[$ns.n - 1]; foreach ($k in $prev.Keys) { $scope[$k] = $prev[$k] } }
        foreach ($k in $a.Keys) { if ($k -ceq 'xmlns') { $scope[''] = $a[$k] } elseif ($k -cmatch '^xmlns:(.+)') { $scope[$Matches[1]] = $a[$k] } }
        $p = ''; $l = $name; if ($name -cmatch '^([^:]+):(.+)$') { $p = $Matches[1]; $l = $Matches[2] }
        $node = @{ n = $name; l = $l; p = $p; u = $(if ($scope.ContainsKey($p)) { $scope[$p] } else { '' }); a = $a; ak = $order; k = (NewL); line = $startline; mixed = $false }
        if (($stack.n -gt 0 -and $stack.i[$stack.n - 1].mixed) -or ($keep -and (& $keep $node))) { $node.mixed = $true }
        if ($stack.n -gt 0) { LAdd $stack.i[$stack.n - 1].k $node } else { $root = $node }
        if (-not $empty) { LAdd $open $name; $stack.i[$stack.n] = $node; $stack.n++; $ns.i[$ns.n] = $scope; $ns.n++ }
    }
    if ($text -ne '') { $t = DecodeEntities $text $ent; $text = ''; & $addText $t }
    if ($open.n -gt 0) { & $err ('missing end tag for <' + $open.i[$open.n - 1] + '>') }
    if ($null -eq $root) { throw "no root element`n" }
    $root
}
function XKids($n, [string]$local) {                   # element children (optionally of one local name)
    $o = @()
    for ($j = 0; $j -lt $n.k.n; $j++) { $x = $n.k.i[$j]; if ($x -isnot [string] -and ($local -eq '' -or $x.l -ceq $local)) { $o += , $x } }
    return ,$o
}
function XKid($n, [string]$local) { for ($j = 0; $j -lt $n.k.n; $j++) { $x = $n.k.i[$j]; if ($x -isnot [string] -and $x.l -ceq $local) { return $x } }; $null }
function XText($n) {
    $o = @()
    for ($j = 0; $j -lt $n.k.n; $j++) { $x = $n.k.i[$j]; if ($x -is [string]) { $o += $x } else { $o += XText $x } }
    -join $o
}

# ================================================================ SysmlText (lib/SysmlText.pm)
$script:KEYWORD = NewH
foreach ($w in ('about abstract accept action actor after alias all allocate allocation analysis and as assert assign assume assumption at ' +
    'attribute bind binding by calc case comment concern connect connection constant constraint crosses decide def ' +
    'default defined dependency derived do doc effect else end entry enum event exhibit exit expose false filter first flow ' +
    'for fork frame from guard hastype if implies import in include individual inout interface istype item join language ' +
    'library locale loop merge message meta metadata new nonunique not null objective occurrence of or ordered out ' +
    'package parallel part perform port private protected public redefines ref references render rendering rep ' +
    'require requirement return satisfy send snapshot specializes stakeholder standard state subject subsets ' +
    'succession terminate then timeslice to transition trigger true typed until use variant variation verification verify via ' +
    'view viewpoint when while xor').Split(' ')) { $script:KEYWORD[$w] = 1 }

function SName($s) {                                   # SysmlText::name
    if ($null -eq $s) { $s = '' }
    $s = [string]$s
    if ((RT $s '^[A-Za-z_][A-Za-z0-9_]*$') -and -not $script:KEYWORD.ContainsKey($s)) { return $s }
    $q = RR $s '([\\''])' '\$1'
    $q = $q.Replace("`n", '\n').Replace("`t", '\t').Replace("`r", '')
    "'$q'"
}
function Ident($s) {                                   # SysmlText::ident
    if ($null -eq $s) { $s = '' }
    $s = RR ([string]$s) '[^A-Za-z0-9_]+' '_'
    $s = RR $s '^_+|_+$' ''
    if ($s -eq '' -or (RT $s '^[0-9]')) { $s = "R_$s" }
    if ($script:KEYWORD.ContainsKey($s)) { $s += '_' }
    $s
}
function SStr($s) {                                    # SysmlText::str
    if ($null -eq $s) { $s = '' }
    $s = RR ([string]$s) '[\t\n\x0B\f\r ]*\n[\t\n\x0B\f\r ]*' ' '
    $s = $s.Replace("`r", '')
    $s = RR $s '([\\"])' '\$1'
    '"' + $s + '"'
}
function DocBody([string]$t) {
    $t = $t.Replace("`r", '')
    $t = $t.Replace('*/', '* /').Replace('/*', '/ *')
    $t = RR $t '(?m)[ \t]+$' ''
    $t = R1 $t '^[\t\n\x0B\f\r ]*\n' ''
    $t = RR $t '[\t\n\x0B\f\r ]+$' ''
    $t
}
function SDoc($text, [string]$ind) {                   # -> lines
    $t = DocBody $(if ($null -ne $text) { [string]$text } else { '' })
    if ($t.IndexOf("`n") -lt 0 -and $t.Length -le 100) { return ,@("${ind}doc /* $t */") }
    $l = @("${ind}doc", "${ind}    /*")
    foreach ($x in ($t -split "`n")) { if ($x -eq '') { $l += "${ind}     *" } else { $l += "${ind}     * $x" } }
    $l += "${ind}     */"
    return ,$l
}
function OneLine($t) { $t = DocBody $(if ($null -ne $t) { [string]$t } else { '' }); RR $t '[\t\n\x0B\f\r ]*\n[\t\n\x0B\f\r ]*' ' ' }
function SRequirement($r, [string]$style, [string]$ind) {   # SysmlText::requirement; $r: hashtable name doorsId text title vm attrs body
    if (-not $style) { $style = 'def' }
    $attrs = @()
    if ($null -ne $r.doorsId -and $r.doorsId -ne '') { $attrs += , @('doorsId', $r.doorsId) }
    if ($null -ne $r.title -and $r.title -ne '') { $attrs += , @('title', $r.title) }
    if ($null -ne $r.vm -and $r.vm -ne '') { $attrs += , @('verificationMethod', $r.vm) }
    foreach ($x in @($r.attrs)) { if ($null -ne $x) { $attrs += , $x } }
    $extra = @($r.body | Where-Object { $null -ne $_ })
    if ($style -eq 'usage') {
        $b = @()
        if (HasNS $r.text) { $b += 'doc /* ' + (OneLine $r.text) + ' */' }
        foreach ($x in $attrs) { $b += 'attribute ' + (Ident $x[0]) + ' = ' + (SStr $x[1]) + ';' }
        $l = "${ind}requirement $($r.name) { " + ($b -join ' ') + ' }'
        $l = R1 $l '\{  \}' '{ }'
        $o = @($l); foreach ($x in $extra) { $o += "$ind$x" }
        return ,$o
    }
    $l = @("${ind}requirement def $($r.name) {")
    if (HasNS $r.text) { $l += SDoc $r.text "$ind    " }
    foreach ($x in $attrs) { $l += "$ind    attribute " + (Ident $x[0]) + ' = ' + (SStr $x[1]) + ';' }
    foreach ($x in $extra) { $l += "$ind    $x" }
    $l += "$ind}"
    return ,$l
}

$script:LIBPKG = NewH
foreach ($w in ('ScalarValues ISQ SI USCustomaryUnits Quantities MeasurementReferences RequirementDerivation Base Links Occurrences Items Parts Ports ' +
    'Actions Requirements VerificationCases Connections Interfaces Constraints Calculations Cases UseCases Metaobjects Collections SequenceFunctions ' +
    'ControlFunctions BaseFunctions NumericalFunctions Time KerML SysML ISQBase ISQSpaceTime ISQMechanics ISQThermodynamics ISQElectromagnetism ' +
    'ShapeItems SpatialItems VerdictKind VerificationMethodKind RiskMetadata ModelingMetadata ParametersOfInterestMetadata ImageMetadata TradeStudies AnalysisTooling').Split(' ')) { $script:LIBPKG[$w] = 1 }
$script:LIBNAME = NewH
foreach ($w in 'Real Integer Natural Positive Boolean String Complex Rational Number NumericalValue ScalarValue Anything start done self that'.Split(' ')) { $script:LIBNAME[$w] = 1 }
$script:DECL = NewH
foreach ($w in ('package part port attribute item action requirement enum connection interface verification constraint calc case use occurrence ' +
    'state allocation analysis metadata view viewpoint concern flow ref in out inout objective subject').Split(' ')) { $script:DECL[$w] = 1 }
$script:TOKRX = @{
    ws = New-Object regex ('\G([\t\n\x0B\f\r ]+)', $script:RX); lc = New-Object regex ('\G//[^\n]*', $script:RX)
    bc = New-Object regex ('\G/\*', $script:RX); bce = New-Object regex ('(?s)\G(.*?)\*/', $script:RX)
    str = New-Object regex ('\G"((?:[^"\\\n]|\\.)*)"', $script:RX); q1 = New-Object regex ('\G"', $script:RX)
    nm = New-Object regex ('\G''((?:[^''\\\n]|\\.)*)''', $script:RX); q2 = New-Object regex ('\G''', $script:RX)
    id = New-Object regex ('\G([A-Za-z_][A-Za-z0-9_]*)', $script:RX); num = New-Object regex ('\G([0-9][0-9.eE+\-]*)', $script:RX)
    p = New-Object regex ('\G(::>|:>>|:>|::|\.\.|[{}()\[\];:~,.=#*<>\-+/])', $script:RX); any = New-Object regex ('(?s)\G(.)', $script:RX)
}
function SysTokens([string]$t, [string]$path) {       # -> @{ tok = list of @(kind, value, line); bad = list }
    $tok = NewL; $bad = NewL; $line = 1; $pos = 0; $TKR = $script:TOKRX
    while ($pos -lt $t.Length) {
        $m = $TKR.ws.Match($t, $pos); if ($m.Success) { $line += CountCh $m.Groups[1].Value "`n"; $pos += $m.Length; continue }
        $m = $TKR.lc.Match($t, $pos); if ($m.Success) { $pos += $m.Length; continue }
        $m = $TKR.bc.Match($t, $pos)
        if ($m.Success) {
            $pos += $m.Length
            $m2 = $TKR.bce.Match($t, $pos)
            if ($m2.Success) { $line += CountCh $m2.Groups[1].Value "`n"; $pos += $m2.Length } else { LAdd $bad "${path}:${line}: unterminated comment"; break }
            continue
        }
        $m = $TKR.str.Match($t, $pos); if ($m.Success) { LAdd $tok @('str', $m.Groups[1].Value, $line); $pos += $m.Length; continue }
        $m = $TKR.q1.Match($t, $pos); if ($m.Success) { LAdd $bad "${path}:${line}: unterminated string"; break }
        $m = $TKR.nm.Match($t, $pos); if ($m.Success) { $v = RR $m.Groups[1].Value '\\(.)' '$1'; LAdd $tok @('name', $v, $line); $pos += $m.Length; continue }
        $m = $TKR.q2.Match($t, $pos); if ($m.Success) { LAdd $bad "${path}:${line}: unterminated name"; break }
        $m = $TKR.id.Match($t, $pos); if ($m.Success) { $v = $m.Groups[1].Value; LAdd $tok @($(if ($script:KEYWORD.ContainsKey($v)) { 'kw' } else { 'name' }), $v, $line); $pos += $m.Length; continue }
        $m = $TKR.num.Match($t, $pos); if ($m.Success) { LAdd $tok @('num', $m.Groups[1].Value, $line); $pos += $m.Length; continue }
        $m = $TKR.p.Match($t, $pos); if ($m.Success) { LAdd $tok @('p', $m.Groups[1].Value, $line); $pos += $m.Length; continue }
        $m = $TKR.any.Match($t, $pos); LAdd $bad "${path}:${line}: unexpected character '$($m.Groups[1].Value)'"; $pos += $m.Length
    }
    @{ tok = (LArr $tok); bad = (LArr $bad) }
}
function SysCheck($files) {                            # SysmlText::check: hashtable path -> text  ->  array of problems
    $declared = NewH; $refs = NewL; $bad = NewL
    $close = NewH; $close[')'] = '('; $close[']'] = '['; $close['}'] = '{'
    foreach ($path in (SortedKeys $files)) {
        $r = SysTokens $files[$path] $path
        foreach ($b in $r.bad) { LAdd $bad $b }
        $tok = $r.tok; $ntok = $tok.Count
        $stack = NewL
        foreach ($k in $tok) {
            if ($k[0] -cne 'p') { continue }
            if ($k[1] -ceq '(' -or $k[1] -ceq '[' -or $k[1] -ceq '{') { LAdd $stack $k }
            elseif ($close.ContainsKey($k[1])) {
                $o = $null; if ($stack.n -gt 0) { $stack.n--; $o = $stack.i[$stack.n] }
                if ($null -eq $o) { LAdd $bad "${path}:$($k[2]): unbalanced '$($k[1])'" }
                elseif ($o[1] -cne $close[$k[1]]) { LAdd $bad "${path}:$($k[2]): '$($k[1])' closes '$($o[1])' from line $($o[2])" }
            }
        }
        foreach ($o in (LArr $stack)) { LAdd $bad "${path}:$($o[2]): '$($o[1])' never closed" }
        $qn = {
            param($i)
            if (-not ($i -lt $ntok -and $tok[$i][0] -ceq 'name')) { return @($null, $i) }
            $seg = @($tok[$i][1]); $i++
            while ($i + 1 -lt $ntok -and $tok[$i][1] -ceq '::' -and $tok[$i + 1][0] -ceq 'name') { $seg += $tok[$i + 1][1]; $i += 2 }
            return @(, $seg) + @($i)
        }
        for ($i = 0; $i -lt $ntok; $i++) {
            $kind = $tok[$i][0]; $v = $tok[$i][1]; $ln = $tok[$i][2]
            if ($i -gt 0 -and $tok[$i - 1][1] -ceq '#') { continue }
            if ($kind -ceq 'kw' -and $script:DECL.ContainsKey($v)) {
                $j = $i + 1
                while ($j -lt $ntok -and $tok[$j][0] -ceq 'kw' -and $tok[$j][1] -cmatch '^(def|part|item|attribute|action|port|requirement|case|connection|ref)$') { $j++ }
                if ($j -lt $ntok -and $tok[$j][1] -ceq '<') { $j += 3 }
                if ($j -lt $ntok -and $tok[$j][0] -ceq 'name') { $declared[$tok[$j][1]] = 1 }
            }
            $refAt = $null
            if ($kind -ceq 'p' -and ($v -ceq ':' -or $v -ceq '::>')) { $refAt = $i + 1; if ($refAt -lt $ntok -and $tok[$refAt][1] -ceq '~') { $refAt++ } }
            elseif ($kind -ceq 'kw' -and $v -cmatch '^(satisfy|verify|by|connect|to|from|bind|allocate|specializes)$') { $refAt = $i + 1 }
            if ($kind -ceq 'p' -and $v -ceq ':>') {
                $j = $i + 1
                while ($true) {
                    $q = & $qn $j; $seg = $q[0]; $n2 = $q[1]
                    if ($null -eq $seg) { break }
                    LAdd $refs @{ seg = $seg; where = "${path}:$($tok[$j][2])" }
                    if (-not ($n2 -lt $ntok -and $tok[$n2][1] -ceq ',')) { break }
                    $j = $n2 + 1
                }
                continue
            }
            if ($kind -ceq 'kw' -and $v -ceq 'import') {
                $q = & $qn ($i + 1)
                if ($null -ne $q[0]) { LAdd $refs @{ seg = $q[0]; where = "${path}:$ln"; imp = 1 } }
                continue
            }
            if ($null -ne $refAt) {
                $q = & $qn $refAt
                if ($null -ne $q[0]) { LAdd $refs @{ seg = $q[0]; where = "${path}:$ln" } }
            }
            if ($kind -ceq 'kw' -and $v -ceq 'bind') {
                $j = $i + 1; while ($j -lt $ntok -and $tok[$j][1] -cne '=' -and $tok[$j][1] -cne ';') { $j++ }
                if ($j -lt $ntok -and $tok[$j][1] -ceq '=') { $q = & $qn ($j + 1); if ($null -ne $q[0]) { LAdd $refs @{ seg = $q[0]; where = "${path}:$ln" } } }
            }
        }
    }
    foreach ($r in (LArr $refs)) {
        $seg = @($r.seg); $head = $seg[0]
        if ($script:LIBPKG.ContainsKey($head)) { continue }
        if ($seg.Count -eq 1 -and $script:LIBNAME.ContainsKey($head)) { continue }
        $miss = @($seg | Where-Object { -not $declared.ContainsKey($_) })
        if ($miss.Count) { LAdd $bad "$($r.where): '$($seg -join '::')' is not declared in these files or the standard library" }
    }
    $seen = NewH; $out = @()
    foreach ($b in (LArr $bad)) { if (-not $seen.ContainsKey($b)) { $seen[$b] = 1; $out += $b } }
    return ,$out
}

function ReadLayoutMap([string]$path) {               # SysmlText::read_layout_map; throws "FILE:LINE: ..."
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "${path}: No such file or directory`n" }
    $txt = ReadBytes $path
    $map = NewH; $order = @(); $default = $null; $n = 0
    $lines = $txt -split "`n"; if ($txt.EndsWith("`n")) { $lines = $lines[0..($lines.Count - 2)] }
    if ($txt -eq '') { $lines = @() }
    foreach ($l in $lines) {
        $n++
        $l = RR $l '\r$' ''
        $l = R1 $l '(?:^|[\t\n\x0B\f\r ])#.*' ''
        if (-not (RT $l '[^\t\n\x0B\f\r ]')) { continue }
        $m = Rx $l '^[\t\n\x0B\f\r ]*(.*?)[\t\n\x0B\f\r ]*=[\t\n\x0B\f\r ]*(.*?)[\t\n\x0B\f\r ]*$'
        if (-not $m.Success) { throw "${path}:${n}: expected PACKAGE = folder/ or PACKAGE = folder/File.sysml`n" }
        $k = $m.Groups[1].Value; $v = $m.Groups[2].Value
        $k = R1 $k "^'(.*)'$" '$1'; $k = R1 $k '^"(.*)"$' '$1'
        if ($k -eq '') { throw "${path}:${n}: no package name before '='`n" }
        if ($v -eq '') { throw "${path}:${n}: no path after '=' for $k`n" }
        if (RT $v '^/|^[A-Za-z]:|(?:^|/)\.\.(?:/|$)|\\') { throw "${path}:${n}: ${v}: give a path relative to the output folder, without '..'`n" }
        if (-not $v.EndsWith('/') -and -not (RT $v '\.sysml$')) { throw "${path}:${n}: ${v}: a file must end in .sysml (or end the folder with /)`n" }
        if ($k -ceq '*') { if (-not $v.EndsWith('/')) { throw "${path}:${n}: '*' must be a folder (end it with /)`n" }; $default = $v; continue }
        if ($map.ContainsKey($k)) { throw "${path}:${n}: $k is mapped twice`n" }
        $map[$k] = $v; $order += $k
    }
    @{ path = $path; map = $map; default = $default; order = $order }
}
function LayoutPath($lm, [string]$pkg, [string]$pf, [string]$fallback) {   # -> @(path, note or $null)
    if (-not $lm) { return @($fallback, $null) }
    if ($lm.map.ContainsKey($pkg)) { $v = $lm.map[$pkg]; if ($v.EndsWith('/')) { return @("$v$pf.sysml", $null) } else { return @($v, $null) } }
    if ($null -ne $lm.default) { return @("$($lm.default)$pf.sysml", "layout map: $pkg is not listed; written to $($lm.default)$pf.sysml (the * default)") }
    @($fallback, "layout map: $pkg is not listed; written to $fallback (the converter's own layout)")
}

# ================================================================ Reqif (lib/Reqif.pm)
$script:ID_ATTRS = @('Object Identifier', 'ReqIF.ForeignID', 'Absolute Number', 'ID', 'Identifier')
$script:TEXT_ATTRS = @('ReqIF.Text', 'Object Text', 'Text', 'Description')
$script:HEAD_ATTRS = @('ReqIF.ChapterName', 'Object Heading', 'Heading')
$script:NAME_ATTRS = @('ReqIF.Name', 'Name', 'Title')
function RFirst($h, $keys) { foreach ($k in $keys) { if ($h.ContainsKey($k) -and (HasNS $h[$k])) { return $h[$k] } }; $null }

$script:BLOCK = NewH
foreach ($w in 'p div br li tr h1 h2 h3 h4 h5 h6 ul ol table pre blockquote dt dd'.Split(' ')) { $script:BLOCK[$w] = 1 }
function XhtmlText($node) {
    $script:xo = NewL
    XhtmlWalk $node
    $out = -join (LArr $script:xo)
    $out = $out.Replace([string][char]0xC2 + [char]0xA0, ' ')
    $out = RR $out '[ \t]+\n' "`n"
    $out = RR $out '\n[ \t]+' "`n"
    $out = RR $out '\n{2,}' "`n"
    $out = RR $out '^[\t\n\x0B\f\r ]+|[\t\n\x0B\f\r ]+$' ''
    $out = RR $out ' {2,}' ' '
    $out
}
function XoEndsNl { if ($script:xo.n -eq 0) { return $false }; for ($j = $script:xo.n - 1; $j -ge 0; $j--) { $x = $script:xo.i[$j]; if ($x -ne '') { return $x.EndsWith("`n") } }; $false }
function XhtmlWalk($n) {
    for ($j = 0; $j -lt $n.k.n; $j++) {
        $k = $n.k.i[$j]
        if ($k -is [string]) { LAdd $script:xo (RR $k '[\t\n\x0B\f\r ]+' ' '); continue }
        $l = LcA $k.l
        if ($l -ceq 'br') { LAdd $script:xo "`n"; continue }
        if ($l -ceq 'img' -or $l -ceq 'object') {
            $alt = $null; if ($k.a.ContainsKey('alt') -and $k.a['alt']) { $alt = $k.a['alt'] } elseif ($k.a.ContainsKey('name') -and $k.a['name']) { $alt = $k.a['name'] } else { $alt = 'image' }
            if ($alt -eq '0') { $alt = 'image' }
            LAdd $script:xo "[$alt]"; continue
        }
        if ($script:BLOCK.ContainsKey($l)) { LAdd $script:xo "`n" }
        if ($l -ceq 'li') { LAdd $script:xo '- ' }
        if (($l -ceq 'td' -or $l -ceq 'th') -and -not (XoEndsNl)) { LAdd $script:xo ' | ' }
        XhtmlWalk $k
        if ($script:BLOCK.ContainsKey($l)) { LAdd $script:xo "`n" }
    }
}

function ReqifXml([string]$path) {                     # the XML bytes of a .reqif, or of the first .reqif in a .reqifz
    if (-not (RTI $path '\.reqifz$')) { return $null }
    $zl = Join-Path $PSScriptRoot '..\ziplib.ps1'
    if (-not (Test-Path -LiteralPath $zl)) { throw "${path}: ziplib.ps1 is not beside this tool; unzip the .reqifz and give the .reqif inside`n" }
    . $zl
    $ents = $null
    try { $ents = @(Read-ZipEntries -Path $path | ForEach-Object { $_ }) } catch { throw "${path}: not a zip ($($_.Exception.Message))`n" }
    foreach ($e in $ents) {
        if (RTI $e.name '\.reqif$') { $b = Read-ZipEntry -Path $path -Name $e.name; if ($null -eq $b -or $b.Count -eq 0) { return '' }; return (-join [char[]]$b) }
    }
    throw "${path}: no .reqif file inside the archive`n"
}

function RObject([string]$oid, $v, $type, $o) {        # Reqif::_object
    $id = if ($null -ne $o.id_attr) { $v[$o.id_attr] } else { RFirst $v $script:ID_ATTRS }
    if ($null -eq $id -or $id -eq '') { $id = $oid }
    if ($null -ne $o.id_prefix -and -not $id.StartsWith($o.id_prefix, $script:ORD)) { $id = $o.id_prefix + $id }
    $vm = $null
    if ($null -ne $o.vm_attr) { $vm = $v[$o.vm_attr] }
    else { foreach ($k in (SortedKeys $v)) { if ((RTI $k 'verif') -and (HasNS $v[$k])) { $vm = $v[$k]; break } } }
    @{ oid = $oid; id = $id; type = $type; attrs = $v; bare = ($v.Count -eq 0)
       text = $(if ($null -ne $o.text_attr) { $v[$o.text_attr] } else { RFirst $v $script:TEXT_ATTRS })
       heading = $(if ($null -ne $o.heading_attr) { $v[$o.heading_attr] } else { RFirst $v $script:HEAD_ATTRS })
       name = (RFirst $v $script:NAME_ATTRS); vm = $vm }
}
function XFind($n, [string]$l, $acc) { for ($j = 0; $j -lt $n.k.n; $j++) { $x = $n.k.i[$j]; if ($x -is [string]) { continue }; if ($x.l -ceq $l) { LAdd $acc $x } else { XFind $x $l $acc } } }
function XRef($n, [string]$wrap) { $w = XKid $n $wrap; if ($null -eq $w) { return $null }; $r = @(XKids $w ''); if ($r.Count) { return (XText $r[0]) }; $null }

function LoadReqif([string]$path, $o) {
    $xml = ReqifXml $path
    if ($null -eq $xml) {
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "${path}: No such file or directory`n" }
        $xml = ReadBytes $path
    }
    $keep = { param($nd) $nd.l -ceq 'THE-VALUE' -or $nd.l -ceq 'THE-ORIGINAL-VALUE' }
    $root = XmlParse $xml $(if ($null -eq (ReqifXml2Label $path)) { $path } else { 'input' }) $keep
    $script:ad = NewH; $script:ev = NewH; $script:types = NewH
    RIndex $root
    $objs = NewH; $order = NewL; $rels = NewL; $specs = NewL
    $acc = NewL; XFind $root 'SPEC-OBJECT' $acc
    foreach ($so in (LArr $acc)) {
        if (-not $so.a.ContainsKey('IDENTIFIER')) { continue }
        $oid = $so.a['IDENTIFIER']
        $v = RValues $so
        $t = XRef $so 'TYPE'
        $ty = if ($null -ne $t -and $script:types.ContainsKey($t)) { $script:types[$t] } else { $t }
        $objs[$oid] = RObject $oid $v $ty $o
        LAdd $order $oid
    }
    $acc = NewL; XFind $root 'SPEC-RELATION' $acc
    foreach ($sr in (LArr $acc)) {
        $t = XRef $sr 'TYPE'
        $ty = if ($null -ne $t -and $script:types.ContainsKey($t) -and $null -ne $script:types[$t]) { $script:types[$t] } elseif ($null -ne $t) { $t } else { '' }
        LAdd $rels @{ id = $sr.a['IDENTIFIER']; type = $ty; src = (XRef $sr 'SOURCE'); tgt = (XRef $sr 'TARGET') }
    }
    $acc = NewL; XFind $root 'SPECIFICATION' $acc
    foreach ($sp in (LArr $acc)) {
        $nm = $sp.a['LONG-NAME']; if ($null -eq $nm -or $nm -eq '') { $nm = $sp.a['IDENTIFIER'] }
        LAdd $specs @{ name = $nm; kids = (RTree $sp) }
    }
    $title = $null
    $acc = NewL; XFind $root 'TITLE' $acc
    if ($acc.n) { $title = XText $acc.i[0] }
    @{ source = (BaseName $path); title = $title; objects = $objs; order = (LArr $order); specs = (LArr $specs); relations = (LArr $rels); spec_objects = $order.n }
}
function ReqifXml2Label([string]$path) { if (RTI $path '\.reqifz$') { 'zip' } else { $null } }
function RIndex($n) {
    $l = $n.l
    $idk = if ($n.a.ContainsKey('IDENTIFIER')) { $n.a['IDENTIFIER'] } else { '' }      # Perl: an undefined key is ''
    if ($l.StartsWith('ATTRIBUTE-DEFINITION-', $script:ORD)) { if ($n.a.ContainsKey('IDENTIFIER')) { $script:ad[$idk] = $n.a['LONG-NAME'] } }
    elseif ($l -ceq 'ENUM-VALUE') { $script:ev[$idk] = $(if ($n.a.ContainsKey('LONG-NAME')) { $n.a['LONG-NAME'] } else { $n.a['IDENTIFIER'] }) }
    elseif ($l -cmatch '^(SPEC-OBJECT-TYPE|SPEC-RELATION-TYPE|SPECIFICATION-TYPE|RELATION-GROUP-TYPE)$') { $script:types[$idk] = $n.a['LONG-NAME'] }
    for ($j = 0; $j -lt $n.k.n; $j++) { $x = $n.k.i[$j]; if ($x -isnot [string]) { RIndex $x } }
}
function RValues($n) {
    $v = NewH
    $vs = XKid $n 'VALUES'; if ($null -eq $vs) { return $v }
    foreach ($av in (XKids $vs '')) {
        $def = XRef $av 'DEFINITION'
        $an = if ($null -ne $def -and $script:ad.ContainsKey($def) -and $null -ne $script:ad[$def]) { $script:ad[$def] } else { $def }
        if ($null -eq $an) { continue }
        if ($av.l -ceq 'ATTRIBUTE-VALUE-XHTML') {
            $tv = XKid $av 'THE-VALUE'
            $val = if ($tv) { XhtmlText $tv } else { '' }
        } elseif ($av.l -ceq 'ATTRIBUTE-VALUE-ENUMERATION') {
            $w = XKid $av 'VALUES'
            $parts = @(); if ($w) { foreach ($x in (XKids $w '')) { $t = XText $x; if ($script:ev.ContainsKey($t)) { $parts += $script:ev[$t] } else { $parts += $t } } }
            $val = $parts -join ', '
        } else {
            if ($av.a.ContainsKey('THE-VALUE')) { $val = $av.a['THE-VALUE'] } else { $tv = XKid $av 'THE-VALUE'; $val = if ($tv) { XText $tv } else { '' } }
        }
        $v[$an] = $val
    }
    $v
}
function RTree($n) {
    $c = XKid $n 'CHILDREN'; if ($null -eq $c) { return ,@() }
    $o = @(); foreach ($h in (XKids $c 'SPEC-HIERARCHY')) { $o += , @{ oid = (XRef $h 'OBJECT'); kids = (RTree $h) } }
    return ,$o
}

# ---- CSV
function ParseCsv([string]$text, $sep) {
    if ($text.StartsWith([string][char]0xEF + [char]0xBB + [char]0xBF, $script:ORD)) { $text = $text.Substring(3) }
    if ($null -eq $sep) {
        $nl = $text.IndexOf("`n"); $first = if ($nl -ge 0) { $text.Substring(0, $nl) } else { $text }
        $sep = "`t"; $bestN = CountCh $first "`t"                 # most frequent; ties go tab, comma, semicolon (Perl's cmp order)
        foreach ($c in @(',', ';')) { $n = CountCh $first $c; if ($n -gt $bestN) { $sep = $c; $bestN = $n } }
    }
    $q = [regex]::Escape($sep)
    $rxQuote = New-Object regex ('\G"((?:[^"]|"")*)"', $script:RX)
    $rxSep = New-Object regex (('\G' + $q), $script:RX)
    $rxNl = New-Object regex ('\G\r?\n', $script:RX)
    $rxField = New-Object regex (('\G([^"\r\n' + $q + ']+|["\r])'), $script:RX)
    $rows = NewL; $row = NewL; $f = ''; $pos = 0; $tlen = $text.Length
    while ($pos -lt $tlen) {
        $m = $rxQuote.Match($text, $pos); if ($m.Success) { $f += $m.Groups[1].Value.Replace('""', '"'); $pos += $m.Length; continue }
        $m = $rxSep.Match($text, $pos); if ($m.Success) { LAdd $row $f; $f = ''; $pos += $m.Length; continue }
        $m = $rxNl.Match($text, $pos); if ($m.Success) { LAdd $row $f; LAdd $rows (LArr $row); $row = NewL; $f = ''; $pos += $m.Length; continue }
        $m = $rxField.Match($text, $pos); if ($m.Success) { $f += $m.Groups[1].Value; $pos += $m.Length; continue }
        $pos++
    }
    if ($f -ne '' -or $row.n) { LAdd $row $f }
    if ($row.n) { LAdd $rows (LArr $row) }
    $out = @()
    foreach ($r in (LArr $rows)) {
        $r2 = @(foreach ($x in $r) { $x.Replace("`r`n", "`n").Replace("`r", "`n") })
        $keep = $false; foreach ($x in $r2) { if (RT $x '[^\t\n\x0B\f\r ]') { $keep = $true; break } }
        if ($keep) { $out += , $r2 }
    }
    return ,$out
}
$script:CSV_GUESS = [ordered]@{
    id = '^(object identifier|id|identifier|absolute number|req(uirement)? ?id|doors ?id)$'
    text = '^(object text|text|requirement|requirement text|description)$'
    heading = '^(object heading|heading|section)$'
    level = '^(object level|level|depth)$'
    vm = 'verif'
    name = '^(name|title|short name)$'
}
function LoadCsv([string]$path, $o) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "${path}: No such file or directory`n" }
    $text = ReadBytes $path
    $rows = ParseCsv $text $o.sep
    if ($rows.Count -eq 0) { throw "${path}: no rows`n" }
    $head = @(foreach ($x in @($rows[0])) { Trim $x })
    $all = $rows; $rows = @(); for ($x = 1; $x -lt $all.Count; $x++) { $rows += , $all[$x] }
    $col = NewH
    foreach ($k in @($script:CSV_GUESS.Keys)) {
        if ($o.cols -and $o.cols.ContainsKey($k)) {
            $want = LcA $o.cols[$k]; $i = $null
            for ($x = 0; $x -lt $head.Count; $x++) { if ((LcA $head[$x]) -ceq $want) { $i = $x; break } }
            if ($null -eq $i) { throw "${path}: no column '$($o.cols[$k])' (have: $($head -join ', '))`n" }
            $col[$k] = $i
        } else {
            for ($x = 0; $x -lt $head.Count; $x++) { if (RTI $head[$x] $script:CSV_GUESS[$k]) { $col[$k] = $x; break } }
        }
    }
    if (-not $col.ContainsKey('id')) { throw "${path}: no id column (have: $($head -join ', ')); name it with --col id=NAME`n" }
    if (-not $col.ContainsKey('text') -and -not $col.ContainsKey('heading')) { throw "${path}: no text column (have: $($head -join ', ')); name it with --col text=NAME`n" }
    $objs = NewH; $order = NewL
    $base = BaseName $path; $src = RR $base '\.[^.]+$' ''
    $root = @{ kids = (NewL) }
    $stack = NewL; LAdd $stack @(0, $root)
    $n = 0
    foreach ($r in $rows) {
        $r = @($r)
        $get = { param($k) if (-not $col.ContainsKey($k)) { return $null }; $i = $col[$k]; if ($i -ge $r.Count) { return $null }; Trim $r[$i] }
        $v = NewH; for ($x = 0; $x -lt $head.Count; $x++) { $v[$head[$x]] = $(if ($x -lt $r.Count) { $r[$x] } else { '' }) }
        $id = & $get 'id'
        $n++; $oid = "row$n"
        $heading = & $get 'heading'
        $level = & $get 'level'
        if (($null -eq $level -or -not (RT $level '^[0-9]+$')) -and $null -ne $heading) {
            $hm = Rx $heading '^([0-9]+(?:\.[0-9]+)*)\.?[\t\n\x0B\f\r ]+'
            if ($hm.Success) { $heading = $heading.Substring($hm.Length); $level = [string]((CountCh $hm.Groups[1].Value '.') + 1) }
        }
        if ($null -ne $id -and $id -ne '' -and $null -ne $o.id_prefix -and -not $id.StartsWith($o.id_prefix, $script:ORD)) { $id = $o.id_prefix + $id }
        $objs[$oid] = @{ oid = $oid; id = $(if ($null -ne $id -and $id -ne '') { $id } else { $oid }); text = (& $get 'text'); heading = $heading
                         name = (& $get 'name'); vm = (& $get 'vm'); attrs = $v; type = 'csv row'; bare = $false }
        LAdd $order $oid
        $node = @{ oid = $oid; kids = (NewL) }
        if ($null -ne $level -and (RT $level '^[0-9]+$')) {
            $lv = [long]$level
            while ($stack.n -gt 1 -and $stack.i[$stack.n - 1][0] -ge $lv) { $stack.n-- }
            LAdd $stack.i[$stack.n - 1][1].kids $node
            $stack.i[$stack.n] = @($lv, $node); $stack.n++
        } else { LAdd $root.kids $node }
    }
    @{ source = $base; title = $null; objects = $objs; order = (LArr $order); specs = @(@{ name = $(if ($null -ne $o.name) { $o.name } else { $src }); kids = (CsvKids $root.kids) }); relations = @(); spec_objects = $order.n }
}
function CsvKids($l) { $o = @(); foreach ($x in (LArr $l)) { $o += , @{ oid = $x.oid; kids = (CsvKids $x.kids) } }; return ,$o }

# ---- conversion
function RKind($ob) {
    if ($null -eq $ob) { return 'missing' }
    if ((HasNS $ob.text) -or $ob.bare) { return 'req' }
    if (HasNS $ob.heading) { return 'heading' }
    'empty'
}
function RConvert($d, $o) {
    $style = if ($o.req_style) { $o.req_style } else { 'def' }
    $layout = if ($o.layout) { $o.layout } else { '{seg}/{pkg}.sysml' }
    $script:cv = @{ obj = $d.objects; reqname = (NewH); reqpkg = (NewH); reqtop = (NewH); count = (NewH); placed = (NewH); vm = (NewH); style = $style; extra = $o.extra_attrs; cur_top = 0 }
    $cv = $script:cv
    $used = NewH
    foreach ($oid in $d.order) {
        if ((RKind $cv.obj[$oid]) -cne 'req') { continue }
        $b = Ident $cv.obj[$oid].id; $nm = $b; $i = 1
        while ($used.ContainsKey($nm)) { $i++; $nm = $b + '_' + $i }
        $used[$nm] = 1; $cv.reqname[$oid] = $nm
    }
    $topUsed = NewH; $tops = NewL
    foreach ($sp in $d.specs) {
        $b = if ($null -ne $o.name -and @($d.specs).Count -eq 1) { $o.name } else { $sp.name }
        $nm = $b; $i = 1; while ($topUsed.ContainsKey($nm)) { $i++; $nm = "$b $i" }; $topUsed[$nm] = 1
        $cv.cur_top = $tops.n
        $below = @{ v = 0 }
        $body = RWalk $sp.kids '    ' @(SName $nm) (NewH) $below
        LAdd $tops @{ name = $nm; body = $body; links = $null }
    }
    $unplaced = @($d.order | Where-Object { -not $cv.placed.ContainsKey($_) })
    if ($unplaced.Count) {
        $nm = $(if ($tops.n) { $tops.i[0].name } else { 'Requirements' }) + ' unplaced'
        $cv.cur_top = $tops.n
        $below = @{ v = 0 }
        $nodes = @(foreach ($u in $unplaced) { @{ oid = $u; kids = @() } })
        $body = RWalk $nodes '    ' @(SName $nm) (NewH) $below
        LAdd $tops @{ name = $nm; body = $body; links = $null }
        $cv.count['unplaced'] = $unplaced.Count
    }
    $lc = NewH; $imports = NewH
    $obj = $cv.obj
    foreach ($r in $d.relations) {
        $s = $r.src; $t = $r.tgt
        $sk = if ($null -ne $s) { RKind $obj[$s] } else { 'missing' }
        $tk = if ($null -ne $t) { RKind $obj[$t] } else { 'missing' }
        $ty = if ($r.type) { $r.type } else { '' }
        $cls = if (RTI $ty 'deriv|refine') { 'derive' } elseif (RTI $ty 'satisf') { 'satisfy' } elseif (RTI $ty 'verif|test') { 'verify' } else { 'trace' }
        $ti = if ($sk -ceq 'req') { $cv.reqtop[$s] } elseif ($tk -ceq 'req') { $cv.reqtop[$t] } else { 0 }
        $tb = $tops.i[$ti]
        if ($sk -cne 'req' -or $tk -cne 'req') {
            $lc['unresolved'] = 1 + $(if ($lc.ContainsKey('unresolved')) { $lc['unresolved'] } else { 0 })
            $sd = if ($null -ne $s) { if ($obj.ContainsKey($s)) { $obj[$s].id } else { $s } } else { '?' }
            $td = if ($null -ne $t) { if ($obj.ContainsKey($t)) { $obj[$t].id } else { $t } } else { '?' }
            if ($null -eq $tb.links) { $tb.links = NewL }
            LAdd $tb.links "    // TODO link $($r.id) (${ty}): $sd -> $td is not between two requirements"
            continue
        }
        if (-not $imports.ContainsKey($ti)) { $imports[$ti] = NewH }
        foreach ($x in @($s, $t)) { if ($cv.reqtop[$x] -ne $ti -or @($cv.reqpkg[$x]).Count -gt 1) { $imports[$ti][(@($cv.reqpkg[$x]) -join '::')] = 1 } }
        $SNm = $cv.reqname[$s]; $TNm = $cv.reqname[$t]
        $lc[$cls] = 1 + $(if ($lc.ContainsKey($cls)) { $lc[$cls] } else { 0 })
        if ($null -eq $tb.links) { $tb.links = NewL }
        if ($cls -ceq 'derive') {
            $imports[$ti]['RequirementDerivation'] = 1
            foreach ($x in @("    #derivation connection {", "        end #original ::> $TNm;", "        end #derive ::> $SNm;", "    }")) { LAdd $tb.links $x }
        } else {
            LAdd $tb.links ("    dependency from $SNm to $TNm; // $cls" + $(if ($ty -ne '' -and (LcA $ty) -cne $cls) { " ($ty)" } else { '' }))
        }
    }
    $src = $d.source
    $notes = @(); $files = NewH
    for ($i = 0; $i -lt $tops.n; $i++) {
        $tb = $tops.i[$i]
        $self = SName $tb.name
        $imp = @(); if ($imports.ContainsKey($i)) { foreach ($k in (SortedKeys $imports[$i])) { if ($k -cne $self) { $imp += "    private import ${k}::*;" } } }
        $l = @("// generated by reqif2sysml.pl from $src -- review before committing", ('package ' + (SName $tb.name) + ' {')) + $imp + @($tb.body)
        if ($null -ne $tb.links) { $l += '    // links (DOORS link modules)'; $l += LArr $tb.links }
        $l += '}'
        $seg = RR (LcA $tb.name) '[^a-z0-9]+' '-'; $seg = RR $seg '^-+|-+$' ''; if ($seg -eq '') { $seg = 'requirements' }
        $pf = RR $tb.name '[^A-Za-z0-9_.\-]+' '_'
        $fn = $layout.Replace('{seg}', $seg).Replace('{pkg}', $pf)
        $lp = LayoutPath $o.layout_map $tb.name $pf $fn; $fn = $lp[0]
        if ($null -ne $lp[1]) { $notes += $lp[1] }
        if ($files.ContainsKey($fn)) { $alt = R1 $fn '\.sysml$' ('_' + $pf.Replace('$', '$$') + '.sysml'); $notes += "layout map: $($tb.name) and another module both go to $fn; $($tb.name) written to $alt"; $fn = $alt }
        $files[$fn] = ($l -join "`n") + "`n"
    }
    foreach ($k in 'requirements', 'no_text', 'with_vm', 'without_vm', 'headings', 'orphan_headings', 'empty', 'missing', 'unplaced') { if (-not $cv.count.ContainsKey($k)) { $cv.count[$k] = 0 } }
    foreach ($k in 'derive', 'satisfy', 'verify', 'trace', 'unresolved') { if (-not $lc.ContainsKey($k)) { $lc[$k] = 0 } }
    @{ files = $files; problems = (SysCheck $files); reqs = $cv.reqname
       report = @{ source = $src; objects = $d.spec_objects; counts = $cv.count; links = $lc; vm = $cv.vm; relations = @($d.relations).Count; layout = $notes } }
}
function CInc([string]$k) { $c = $script:cv.count; $c[$k] = 1 + $(if ($c.ContainsKey($k)) { $c[$k] } else { 0 }) }
function RWalk($nodes, [string]$ind, $path, $used, $below) {
    $cv = $script:cv; $obj = $cv.obj
    $l = @()
    foreach ($nd in @($nodes)) {
        if ($null -eq $nd) { continue }
        $oid = $nd.oid
        $ob = if ($null -ne $oid -and $obj.ContainsKey($oid)) { $obj[$oid] } else { $null }
        $k = RKind $ob
        if ($null -ne $oid) { $cv.placed[$oid] = 1 }
        if ($k -ceq 'heading') {
            CInc 'headings'
            $b = RR $ob.heading '[\t\n\x0B\f\r ]+' ' '; $b = RR $b '^ | $' ''
            $nm = $b; $i = 1; while ($used.ContainsKey($nm)) { $i++; $nm = "$b $i" }; $used[$nm] = 1
            $sub = @{ v = 0 }
            $in = RWalk $nd.kids "$ind    " (@($path) + @(SName $nm)) (NewH) $sub
            if (-not $sub.v) { CInc 'orphan_headings' }
            $l += "${ind}package " + (SName $nm) + ' {'; $l += "$ind    // DOORS heading " + $ob.id; $l += $in; $l += "$ind}"
            $below.v += $sub.v
            continue
        }
        if ($k -ceq 'req') {
            CInc 'requirements'
            if (-not (HasNS $ob.text)) { CInc 'no_text' }
            if (HasNS $ob.vm) { CInc 'with_vm'; $cv.vm[$ob.vm] = 1 + $(if ($cv.vm.ContainsKey($ob.vm)) { $cv.vm[$ob.vm] } else { 0 }) } else { CInc 'without_vm' }
            $attrs = @(); foreach ($a in @($cv.extra)) { if ($null -ne $a -and $ob.attrs.ContainsKey($a) -and $null -ne $ob.attrs[$a] -and $ob.attrs[$a] -ne '') { $attrs += , @($a, $ob.attrs[$a]) } }
            $l += SRequirement @{ name = $cv.reqname[$oid]; doorsId = $ob.id; text = $ob.text; title = $ob.name; vm = $ob.vm; attrs = $attrs } $cv.style $ind
            $cv.reqpkg[$oid] = @($path); $cv.reqtop[$oid] = $cv.cur_top
            $below.v++
        } elseif ($k -ceq 'empty') {
            CInc 'empty'
            $l += "$ind// TODO DOORS object $($ob.id) has neither text nor heading"
        } else {
            CInc 'missing'
            $l += "$ind// TODO hierarchy points at object " + $(if ($null -ne $oid) { $oid } else { '?' }) + ', which is not in the export'
        }
        if (@($nd.kids).Count) { $l += RWalk $nd.kids $ind $path $used $below }
    }
    return ,$l
}

function ReportText($out) {
    $r = $out.report; $c = $r.counts; $k = $r.links
    $f = { param($label, $n) (PadR $label 44) + ' ' + (PadL ([string]$n) 6) }
    $l = @("reqif2sysml report: $($r.source)", '',
        (& $f 'DOORS objects (C total: <SPEC-OBJECT> count)' $r.objects),
        (& $f 'requirements (objects with text)' $c.requirements),
        (& $f '  bare objects (an identifier, no attributes)' $c.no_text),
        (& $f '  with a verification method' $c.with_vm),
        (& $f '  without a verification method' $c.without_vm),
        (& $f 'headings (section packages)' $c.headings),
        (& $f '  orphan headings (no requirement below)' $c.orphan_headings),
        (& $f 'empty objects (no text, no heading)' $c.empty),
        (& $f 'objects in no specification' $c.unplaced),
        (& $f 'hierarchy entries naming a missing object' $c.missing),
        (& $f 'links' $r.relations),
        "  derive $($k.derive), satisfy $($k.satisfy), verify $($k.verify), trace $($k.trace), not between requirements $($k.unresolved)")
    if ($r.vm.Count) { $l += 'verification methods: ' + (@(foreach ($x in (SortedKeys $r.vm)) { "$x $($r.vm[$x])" }) -join ', ') }
    $l += ''; $l += 'files: ' + ((SortedKeys $out.files) -join ' ')
    $l += @($r.layout)
    $pr = @($out.problems)
    $l += 'self-check: ' + $(if ($pr.Count) { "$($pr.Count) problem(s)" } else { 'ok' })
    foreach ($p in $pr) { $l += "  $p" }
    ($l -join "`n") + "`n"
}

# ---- trace against a SysML v2 model directory
function ScanModel([string]$dir) {
    $req = NewH; $byDoors = NewH; $sat = NewH; $ver = NewH; $doc = NewH
    $files = NewL
    SysmlFiles $dir $files
    foreach ($f in (LArr $files)) {
        $txt = ''; try { $txt = ReadBytes $f } catch { continue }
        $lines = [regex]::Split($txt, '(?<=\n)')
        $cur = $null; $since = $null; $open = $null; $pending = $false
        foreach ($l in $lines) {
            if ($l -eq '') { continue }
            if ($null -ne $open) {
                $m = Rx $l '^(.*?)\*/'
                if ($m.Success) { if (-not $doc.ContainsKey($cur)) { $doc[$cur] = "$open " + (DocStrip $m.Groups[1].Value) }; $open = $null } else { $open += ' ' + (DocStrip $l) }
                continue
            }
            if ($pending) {
                $pending = $false
                $m = Rx $l '^[\t\n\x0B\f\r ]*/\*(.*?)\*/'; if ($m.Success) { if (-not $doc.ContainsKey($cur)) { $doc[$cur] = $m.Groups[1].Value }; continue }
                $m = Rx $l '^[\t\n\x0B\f\r ]*/\*(.*)$'; if ($m.Success) { $open = $m.Groups[1].Value; continue }
            }
            if ($l.IndexOf('/*') -lt 0) { $l = R1 $l '//.*' '' }
            $m = Rx $l '^[\t\n\x0B\f\r ]*requirement[\t\n\x0B\f\r ]+(?:def[\t\n\x0B\f\r ]+)?([A-Za-z0-9_]+)'
            if ($m.Success -and $m.Groups[1].Value -cne 'def') { $cur = $m.Groups[1].Value; $req[$cur] = 1; $since = 0 }
            elseif ($null -ne $since) { $since++ }
            if ($null -ne $cur -and $since -le 3 -and -not $doc.ContainsKey($cur)) {
                $m = Rx $l '\bdoc[\t\n\x0B\f\r ]*/\*(.*?)\*/'
                if ($m.Success) { $doc[$cur] = $m.Groups[1].Value }
                else {
                    $m = Rx $l '\bdoc[\t\n\x0B\f\r ]*/\*(.*)$'
                    if ($m.Success) { $open = $m.Groups[1].Value }
                    elseif (RT $l '^[\t\n\x0B\f\r ]*doc[\t\n\x0B\f\r ]*$') { $pending = $true }
                }
            }
            $m = Rx $l 'doorsId[\t\n\x0B\f\r ]*(?::[\t\n\x0B\f\r ]*[A-Za-z0-9_]+[\t\n\x0B\f\r ]*)?=[\t\n\x0B\f\r ]*"([^"]*)"'
            if ($m.Success -and $null -ne $cur) { $k = $m.Groups[1].Value; if (-not $byDoors.ContainsKey($k)) { $byDoors[$k] = NewH }; $byDoors[$k][$cur] = 1 }
            $m = Rx $l '^[\t\n\x0B\f\r ]*satisfy[\t\n\x0B\f\r ]+(?:requirement[\t\n\x0B\f\r ]+)?([A-Za-z0-9_:]+)'
            if ($m.Success) { $sat[(LastSeg $m.Groups[1].Value)] = 1 }
            $m = Rx $l '^[\t\n\x0B\f\r ]*verify[\t\n\x0B\f\r ]+(?:requirement[\t\n\x0B\f\r ]+)?([A-Za-z0-9_:]+)'
            if ($m.Success) { $ver[(LastSeg $m.Groups[1].Value)] = 1 }
        }
    }
    @{ files = $files.n; req = $req; by_doors = $byDoors; sat = $sat; ver = $ver; doc = $doc }
}
function LastSeg([string]$x) { $p = @($x -split '::'); $i = $p.Count - 1; while ($i -gt 0 -and $p[$i] -eq '') { $i-- }; $p[$i] }   # (split /::/)[-1]
function DocStrip([string]$x) { R1 $x '^[\t\n\x0B\f\r ]*\*(?!/)[\t\n\x0B\f\r ]?' '' }
function SysmlFiles([string]$d, $acc) {
    if (-not (Test-Path -LiteralPath $d -PathType Container)) { return }
    $es = @(Get-ChildItem -LiteralPath $d -Force -ErrorAction SilentlyContinue | Where-Object { -not $_.Name.StartsWith('.') } | ForEach-Object { $_.Name })
    foreach ($e in (Sorted $es)) {
        $p = "$d/$e"
        if (Test-Path -LiteralPath $p -PathType Container) { SysmlFiles $p $acc } elseif (RT $e '\.sysml$') { LAdd $acc $p }
    }
}
function NormText($t) {
    if ($null -eq $t) { $t = '' }
    $t = RR ([string]$t) '<[^>]+>' ''; $t = $t.Replace('* /', '*/'); $t = RR $t '[\t\n\x0B\f\r ]+' ' '; RR $t '^ | $' ''
}
function RTrace($d, $out, [string]$dir) {
    $m = ScanModel $dir
    $linked = @(); $orphan = @(); $unver = @(); $both = @(); $missing = @(); $drift = @()
    $doors = NewH
    foreach ($oid in $d.order) {
        $ob = $d.objects[$oid]
        if ((RKind $ob) -cne 'req') { continue }
        $doors[$ob.id] = 1
        $names = NewH; if ($m.by_doors.ContainsKey($ob.id)) { foreach ($k in $m.by_doors[$ob.id].Keys) { $names[$k] = 1 } }
        $nm = $out.reqs[$oid]
        if ($null -ne $nm -and $m.req.ContainsKey($nm)) { $names[$nm] = 1 }
        if ($names.Count -eq 0) { $missing += $ob.id; $orphan += $ob.id; $unver += $ob.id; continue }
        $linked += $ob.id
        $s = @($names.Keys | Where-Object { $m.sat.ContainsKey($_) }).Count
        $v = @($names.Keys | Where-Object { $m.ver.ContainsKey($_) }).Count
        if (-not $s) { $orphan += $ob.id }
        if (-not $v) { $unver += $ob.id }
        if ($s -and $v) { $both += $ob.id }
        $want = NormText $ob.text
        $differ = @(foreach ($k in (SortedKeys $names)) { if ($m.doc.ContainsKey($k) -and (NormText $m.doc[$k]) -cne $want) { $k } })
        if ($differ.Count -and $want -ne '') { $drift += , @{ id = $ob.id; doors = $ob.text; model = $m.doc[$differ[0]]; names = $differ } }
    }
    $extra = @($m.by_doors.Keys | Where-Object { -not $doors.ContainsKey($_) }).Count
    @{ dir = $dir; files = $m.files; total = ($linked.Count + $missing.Count); linked = $linked; missing = $missing; orphan = $orphan; unverified = $unver; complete = $both; extra = $extra; drift = $drift }
}
function TraceText($t) {
    $pct = if ($t.total) { Fmt1 (100 * $t.complete.Count / $t.total) } else { '0.0' }
    $f = { param($a, $b) (PadR $a 44) + ' ' + (PadL ([string]$b) 12) }
    $l = @('', "trace against $($t.dir) ($($t.files) .sysml files)",
        (& $f 'C requirements linked (doorsId in the model)' "$($t.linked.Count) of $($t.total)"),
        (& $f 'F orphan requirements (nothing satisfies)' $t.orphan.Count),
        (& $f 'G unverified requirements (no verify)' $t.unverified.Count),
        (& $f 'I trace completeness (satisfied and verified)' "$pct%"),
        (& $f 'doorsIds in the model but not in this export' $t.extra),
        (& $f 'text differs from DOORS' $t.drift.Count))
    if ($t.missing.Count) { $l += 'not in the model: ' + ($t.missing -join ' ') }
    if ($t.orphan.Count) { $l += 'orphans: ' + ($t.orphan -join ' ') }
    if ($t.unverified.Count) { $l += 'unverified: ' + ($t.unverified -join ' ') }
    if ($t.drift.Count) { $l += 'drift: ' + (($t.drift | ForEach-Object { $_.id }) -join ' ') }
    foreach ($x in $t.drift) { $l += "  $($x.id) DOORS: " + (NormText $x.doors); $l += "  $($x.id) model: " + (NormText $x.model) }
    ($l -join "`n") + "`n"
}
