# glcore.ps1 -- the plumbing gitlab.ps1 is built on: Perl-compatible JSON, time, sorting, encoding, hashing, output.
# Windows PowerShell 5.1, Constrained Language Mode safe (no .NET method calls on non-core types, no ArrayList).
# Dot-sourced by gitlab.ps1 (and its other libraries); ps\ziplib.ps1 supplies bytes, UTF-8 and zip.

# ---------------------------------------------------------------- output: stdout buffered, "stderr" at once
# Perl's STDOUT is block-buffered when redirected and STDERR is not: here the stderr lines appear first, then stdout.
$script:GLOUT = ''
function GOut([string]$s) { $script:GLOUT += $s }
function GErr([string]$s) {                           # Perl's warn / print STDERR (Write-Host: CLM has no clean stderr)
    if ($null -eq $s -or $s -ceq '') { return }
    if ($s.EndsWith("`n")) { $s = $s.Substring(0, $s.Length - 1) }
    foreach ($l in ($s -split "`n")) { Write-Host $l }
}
function GFlush {
    $t = $script:GLOUT; $script:GLOUT = ''
    if ($t -ceq '') { return }
    if ($t.EndsWith("`n")) { $t = $t.Substring(0, $t.Length - 1) }
    foreach ($l in ($t -split "`n")) { Write-Output $l }
}

# ---------------------------------------------------------------- hashtables and lists
function NewH { return (New-Object System.Collections.Hashtable ([StringComparer]::Ordinal)) }   # case-sensitive, as Perl hashes
function HasK($h, [string]$k) { if ($null -eq $h) { return $false }; return $h.ContainsKey($k) }
function HGet($h, [string]$k) { if ($null -eq $h) { return $null }; if ($h -is [hashtable]) { return , $h[$k] }; return $null }
function IsH($v) { return ($v -is [hashtable]) }
function IsA($v) { return ($v -is [array]) }
function Def($v) { return ($null -ne $v) }
function Dor($a, $b) { if ($null -ne $a) { return , $a }; return , $b }        # Perl //
function L($v) { if ($null -eq $v) { return ,@() }; if ($v -is [array]) { return ,$v }; return ,@($v) }   # a list, never unrolled
function Copy-H($h) { $n = NewH; if ($null -ne $h) { foreach ($k in @($h.Keys)) { $n[$k] = $h[$k] } }; return $n }
function HKeys($h) { if ($null -eq $h) { return ,@() }; return ,@($h.Keys) }

# Perl truthiness: undef, '', '0' and 0 are false
function Tru($v) {
    if ($null -eq $v) { return $false }
    if ($v -is [bool]) { return $v }
    if ($v -is [string]) { return ($v -cne '' -and $v -cne '0') }
    if ($v -is [array]) { return ($v.Count -gt 0) }
    if ($v -is [hashtable]) { return $true }
    if (IsNum $v) { return ($v -ne 0) }
    return $true
}
function IsNum($v) { return ($v -is [int] -or $v -is [long] -or $v -is [double] -or $v -is [decimal] -or $v -is [single] -or $v -is [byte] -or $v -is [int16] -or $v -is [uint32] -or $v -is [uint64]) }
function IsInt($v) { return ($v -is [int] -or $v -is [long] -or $v -is [byte] -or $v -is [int16] -or $v -is [uint32]) }
function PStr($v) { if ($null -eq $v) { return '' }; if ($v -is [bool]) { if ($v) { return '1' } else { return '' } }; if (IsNum $v) { return (NumStr $v) }; return [string]$v }   # Perl stringification
function PNum($v) {                                  # Perl numification: leading number of a string, else 0
    if ($null -eq $v) { return 0 }
    if ($v -is [bool]) { if ($v) { return 1 } else { return 0 } }
    if (IsNum $v) { return $v }
    $s = [string]$v
    if ($s -cmatch '^\s*([+-]?\d+)\s*$') { $x = $matches[1]; if ($x.Length -lt 18) { return [long]$x } }
    if ($s -cmatch '^\s*([+-]?(?:\d+\.?\d*|\.\d+)(?:[eE][+-]?\d+)?)') { $d = [double]$matches[1]; if ($d -eq [long]$d -and $s -cnotmatch '[.eE]') { return [long]$d }; return $d }
    return 0
}
function Trunc($x) { $d = [double]$x; $r = [long]$d; if ($d -ge 0) { if ($r -gt $d) { $r-- } } else { if ($r -lt $d) { $r++ } }; return $r }   # Perl int()

# ---------------------------------------------------------------- ordinal sorting (Perl's sort is by bytes)
function OrdCmp([string]$a, [string]$b) { $c = [string]::CompareOrdinal($a, $b); if ($c -lt 0) { return -1 }; if ($c -gt 0) { return 1 }; return 0 }
function SortWith($__list, [scriptblock]$__cmp) {        # stable merge sort; $__cmp gets ($x, $y) and returns -1/0/1
    $__a = L $__list
    $__n = $__a.Count
    if ($__n -lt 2) { return ,$__a }
    $__src = $__a; $__dst = [object[]]::new($__n)
    $__w = 1
    while ($__w -lt $__n) {
        for ($__lo = 0; $__lo -lt $__n; $__lo += 2 * $__w) {
            $__mid = $__lo + $__w; if ($__mid -gt $__n) { $__mid = $__n }
            $__hi = $__lo + 2 * $__w; if ($__hi -gt $__n) { $__hi = $__n }
            $__i = $__lo; $__j = $__mid; $__k = $__lo
            while ($__i -lt $__mid -and $__j -lt $__hi) {
                if ((& $__cmp $__src[$__j] $__src[$__i]) -lt 0) { $__dst[$__k] = $__src[$__j]; $__j++ } else { $__dst[$__k] = $__src[$__i]; $__i++ }
                $__k++
            }
            while ($__i -lt $__mid) { $__dst[$__k] = $__src[$__i]; $__i++; $__k++ }
            while ($__j -lt $__hi) { $__dst[$__k] = $__src[$__j]; $__j++; $__k++ }
        }
        $__t = $__src; $__src = $__dst; $__dst = $__t
        $__w *= 2
    }
    return ,$__src
}
function SortStr($list) { return (SortWith $list { param($x, $y) OrdCmp ([string]$x) ([string]$y) }) }
function SortNum($list) { return (SortWith $list { param($x, $y) $p = [double]$x; $q = [double]$y; if ($p -lt $q) { -1 } elseif ($p -gt $q) { 1 } else { 0 } }) }
function NumCmp($x, $y) { $p = [double](PNum $x); $q = [double](PNum $y); if ($p -lt $q) { return -1 }; if ($p -gt $q) { return 1 }; return 0 }
function Uniq($__l) { $__s = NewH; $__o = @(); foreach ($__x in (L $__l)) { $__k = [string]$__x; if (-not $__s.ContainsKey($__k)) { $__s[$__k] = 1; $__o += $__x } }; return ,$__o }

# ---------------------------------------------------------------- numbers as Perl prints them
function NumStr($v) {
    if ($null -eq $v) { return '' }
    if (IsInt $v) { return [string]$v }
    $d = [double]$v
    if ($d -lt 1e15 -and $d -gt -1e15 -and $d -eq [long]$d) { return [string][long]$d }
    $s = '{0:G15}' -f $d
    $s = $s -creplace 'E', 'e'
    if ($s -cmatch 'e([+-])(\d)$') { $s = $s -creplace 'e([+-])(\d)$', 'e${1}0$2' }
    return $s
}
# sprintf('%.Nf', x) exactly as C does it: the double's exact binary value, ties to even.
function FmtF($x, [int]$n) {
    $d = [double]$x
    $neg = $false
    if ($d -lt 0) { $neg = $true; $d = -$d }
    # integer part, by subtracting powers of two (exact for doubles)
    $ip = [long]0; $r = $d
    if ($r -ge 1) {
        $p = 1.0; while ($p * 2 -le $r) { $p = $p * 2 }
        while ($p -ge 1) { if ($r -ge $p) { $r = $r - $p; $ip += [long]$p }; $p = $p / 2 }
    }
    # fraction bits, by doubling (exact)
    $bits = @(); $guard = 0
    while ($r -gt 0 -and $guard -lt 1100) { $r = $r * 2; if ($r -ge 1) { $bits += 1; $r = $r - 1 } else { $bits += 0 }; $guard++ }
    $digits = ''
    $f = [int[]]$bits
    for ($k = 0; $k -lt $n; $k++) {                   # fraction * 10 = fraction * 8 + fraction * 2, on the bits
        $len = $f.Count
        $r = [int[]]::new($len)
        $c = 0
        for ($i = $len - 1; $i -ge 0; $i--) {
            $b8 = 0; if ($i + 3 -lt $len) { $b8 = $f[$i + 3] }
            $b2 = 0; if ($i + 1 -lt $len) { $b2 = $f[$i + 1] }
            $s = $b8 + $b2 + $c
            $r[$i] = $s % 2; $c = ($s - ($s % 2)) / 2
        }
        $f0 = 0; $f1 = 0; $f2 = 0
        if ($len -gt 0) { $f0 = $f[0] }; if ($len -gt 1) { $f1 = $f[1] }; if ($len -gt 2) { $f2 = $f[2] }
        $intd = $c + 4 * $f0 + 2 * $f1 + $f2 + $f0
        $f = $r
        $digits += [string][int]$intd
    }
    # rounding: compare the rest with one half
    $half = 0
    if ($f.Count -gt 0 -and $f[0] -eq 1) {
        $rest = $false; for ($i = 1; $i -lt $f.Count; $i++) { if ($f[$i] -ne 0) { $rest = $true; break } }
        if ($rest) { $half = 1 } else { $half = 2 }    # 2 = exactly one half
    }
    $up = $false
    if ($half -eq 1) { $up = $true }
    elseif ($half -eq 2) {
        $last = 0; if ($n -gt 0) { $last = [int][string]$digits[$n - 1] } else { $last = [int]($ip % 2) }
        if ($last % 2 -eq 1) { $up = $true }
    }
    $num = "$ip"; if ($n -gt 0) { $num = "$ip.$digits" }
    if ($up) {                                         # add one unit in the last place, decimal string arithmetic
        $ch = $num.ToCharArray()
        $i = $ch.Length - 1; $carry = 1
        while ($i -ge 0 -and $carry) {
            if ($ch[$i] -ceq '.') { $i--; continue }
            $dg = [int][string]$ch[$i] + 1
            if ($dg -eq 10) { $ch[$i] = '0'; $carry = 1 } else { $ch[$i] = [char](48 + $dg); $carry = 0 }
            $i--
        }
        $num = -join $ch
        if ($carry) { $num = '1' + $num }
    }
    if ($neg -and $num -cmatch '[1-9]') { $num = '-' + $num } elseif ($neg) { $num = '-' + $num }
    return $num
}
function R1($v) { if ($null -eq $v) { return $null }; return (PNum (FmtF $v 1)) }   # Perl 0 + sprintf('%.1f', v)

# ---------------------------------------------------------------- time (UTC, without .NET date methods)
function TimeGm([long]$sec, [long]$min, [long]$hour, [long]$mday, [long]$mon0, [long]$year) {   # Time::Local::timegm (mon 0-based, year full)
    $y = $year; $m = $mon0 + 1
    if ($m -le 2) { $y = $y - 1 }
    $era = $y; if ($era -lt 0) { $era = $era - 399 }
    $era = ($era - (($era % 400 + 400) % 400)) / 400
    $yoe = $y - $era * 400
    $mp = $m + 9; if ($m -gt 2) { $mp = $m - 3 }
    $doy = ((153 * $mp + 2) - ((153 * $mp + 2) % 5)) / 5 + $mday - 1
    $doe = $yoe * 365 + ($yoe - ($yoe % 4)) / 4 - ($yoe - ($yoe % 100)) / 100 + $doy
    $days = $era * 146097 + $doe - 719468
    return [long]($days * 86400 + $hour * 3600 + $min * 60 + $sec)
}
function GmTime([long]$t) {                          # -> @(sec, min, hour, mday, mon0, year-1900, wday)
    $s = $t % 86400; $days = ($t - $s) / 86400
    if ($s -lt 0) { $s += 86400; $days -= 1 }
    $days = [long]$days
    $z = $days + 719468
    $era = $z; if ($era -lt 0) { $era = $era - 146096 }
    $era = ($era - (($era % 146097 + 146097) % 146097)) / 146097
    $doe = $z - $era * 146097
    $yoe = ($doe - ($doe - ($doe % 1460)) / 1460 + ($doe - ($doe % 36524)) / 36524 - ($doe - ($doe % 146096)) / 146096)
    $yoe = ($yoe - ($yoe % 365)) / 365
    $y = $yoe + $era * 400
    $doy = $doe - (365 * $yoe + ($yoe - ($yoe % 4)) / 4 - ($yoe - ($yoe % 100)) / 100)
    $mp = ((5 * $doy + 2) - ((5 * $doy + 2) % 153)) / 153
    $d = $doy - ((153 * $mp + 2) - ((153 * $mp + 2) % 5)) / 5 + 1
    $m = $mp + 3; if ($mp -ge 10) { $m = $mp - 9 }
    if ($m -le 2) { $y = $y + 1 }
    $wday = (($days % 7) + 7 + 4) % 7                  # 1970-01-01 was a Thursday
    $hh = ($s - ($s % 3600)) / 3600; $mm = (($s % 3600) - ($s % 60)) / 60; $ss = $s % 60
    return ,@([long]$ss, [long]$mm, [long]$hh, [long]$d, [long]($m - 1), [long]($y - 1900), [long]$wday)
}
function P2([long]$v) { if ($v -lt 10 -and $v -ge 0) { return "0$v" }; return "$v" }
function P4([long]$v) { $s = "$v"; while ($s.Length -lt 4) { $s = '0' + $s }; return $s }
function IsoT($t) { $g = GmTime (Trunc $t); return ('{0}-{1}-{2}T{3}:{4}:{5}Z' -f (P4 ($g[5] + 1900)), (P2 ($g[4] + 1)), (P2 $g[3]), (P2 $g[2]), (P2 $g[1]), (P2 $g[0])) }
function DateT($t) { return (IsoT $t).Substring(0, 10) }
function NowEpoch {
    $u = [datetime]::UtcNow
    $e = [datetime]'1970-01-01T00:00:00'
    return [long](Trunc (($u - $e).TotalSeconds))
}
function Epoch([string]$s) {                         # GitLab::_epoch: YYYY-MM-DD[THH:MM[:SS]] (UTC), dies on anything else
    if ($s -cnotmatch '^(\d{4})-(\d\d)-(\d\d)(?:[T ](\d\d):(\d\d)(?::(\d\d))?)?') { throw "GitLab: bad time '$s' (want YYYY-MM-DD[THH:MM[:SS]])`n" }
    $se = 0; if ($matches[6]) { $se = [long]$matches[6] }
    $mi = 0; if ($matches[5]) { $mi = [long]$matches[5] }
    $h = 0; if ($matches[4]) { $h = [long]$matches[4] }
    return (TimeGm $se $mi $h ([long]$matches[3]) ([long]$matches[2] - 1) ([long]$matches[1]))
}
function TParse($s) {                                # GitLab::_t: ISO 8601 with optional fraction and offset -> epoch, or undef
    if ($null -eq $s) { return $null }
    if ([string]$s -cnotmatch '^(\d{4})-(\d\d)-(\d\d)(?:[T ](\d\d):(\d\d)(?::(\d\d)(?:\.\d+)?)?)?\s*(Z|[+-]\d\d:?\d\d)?') { return $null }
    $m = $matches
    $se = 0; if ($m[6]) { $se = [long]$m[6] }; $mi = 0; if ($m[5]) { $mi = [long]$m[5] }; $h = 0; if ($m[4]) { $h = [long]$m[4] }
    $t = TimeGm $se $mi $h ([long]$m[3]) ([long]$m[2] - 1) ([long]$m[1])
    $tz = $m[7]
    if ($tz -and $tz -cne 'Z') {
        if ($tz -cmatch '([+-])(\d\d):?(\d\d)') { $o = [long]$matches[2] * 3600 + [long]$matches[3] * 60; if ($matches[1] -ceq '-') { $t += $o } else { $t -= $o } }
    }
    return $t
}
function StrfTime([string]$fmt, $g) {                # the few strftime formats GitLab.pm uses, on GmTime output
    $wd = @('Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat')
    $s = $fmt
    $s = $s.Replace('%a', $wd[$g[6]]).Replace('%Y', (P4 ($g[5] + 1900))).Replace('%m', (P2 ($g[4] + 1))).Replace('%d', (P2 $g[3]))
    $s = $s.Replace('%H', (P2 $g[2])).Replace('%M', (P2 $g[1])).Replace('%S', (P2 $g[0]))
    return $s
}

# ---------------------------------------------------------------- encoding
function Utf8B([string]$s) { if ($null -eq $s -or $s -ceq '') { return ,([byte[]]@()) }; return ,(Zl-Utf8Enc $s) }
function Enc([string]$s) {                           # GitLab::_enc: every byte outside A-Za-z0-9_.~- as %XX
    if ($null -eq $s) { return '' }
    $b = Utf8B $s
    $o = ''
    foreach ($x in $b) {
        $c = [char]$x
        if (($x -ge 65 -and $x -le 90) -or ($x -ge 97 -and $x -le 122) -or ($x -ge 48 -and $x -le 57) -or $x -eq 95 -or $x -eq 46 -or $x -eq 126 -or $x -eq 45) { $o += $c }
        else { $o += '%' + ([int]$x).ToString('X2') }
    }
    return $o
}
function QStr($q) {                                  # GitLab::_q: ?k=v&... sorted, undefined values left out
    $ks = @(); foreach ($k in $q.Keys) { if ($null -ne $q[$k]) { $ks += $k } }
    $ks = SortStr $ks
    if ($ks.Count -eq 0) { return '' }
    return '?' + ((@(foreach ($k in $ks) { (Enc $k) + '=' + (Enc (PStr $q[$k])) })) -join '&')
}
function Slug([string]$s) { $s = $s.ToLowerInvariant() -creplace '[^a-z0-9]+', '-'; $s = $s -creplace '^-+|-+$', ''; if ($s.Length -gt 63) { $s = $s.Substring(0, 63) }; return $s }
function Arr($v) {                                    # GitLab::_arr: a list, or a comma string split and trimmed
    if ($null -eq $v) { return ,@() }
    if ($v -is [array]) { return ,$v }
    $o = @(); foreach ($x in ([string]$v -split ',')) { $y = $x.Trim(); if ($y.Length) { $o += $y } }
    return ,$o
}
function ReadText([string]$path) {                   # a file's text, raw (no newline translation), UTF-8
    $b = Zl-ReadBytes $path
    if ($b.Length -eq 0) { return '' }
    return (Zl-Utf8Dec $b 0 $b.Length)
}
function WriteText([string]$path, [string]$text) { Zl-WriteBytes $path (Utf8B $text) }

# ---------------------------------------------------------------- JSON (JSON::PP: canonical, utf8; pretty = 3 spaces, " : ")
function JsStr([string]$s) {
    $o = '"'
    foreach ($ch in $s.ToCharArray()) {
        $c = [int]$ch
        if ($c -eq 34) { $o += '\"' } elseif ($c -eq 92) { $o += '\\' }
        elseif ($c -eq 10) { $o += '\n' } elseif ($c -eq 13) { $o += '\r' } elseif ($c -eq 9) { $o += '\t' }
        elseif ($c -eq 8) { $o += '\b' } elseif ($c -eq 12) { $o += '\f' }
        elseif ($c -lt 32) { $o += '\u' + $c.ToString('x4') }
        else { $o += $ch }
    }
    return $o + '"'
}
function JsEnc($v, [bool]$pretty = $false, [int]$lvl = 0) {
    if ($null -eq $v) { return 'null' }
    if ($v -is [bool]) { if ($v) { return 'true' } else { return 'false' } }
    if ($v -is [string]) { return (JsStr $v) }
    if (IsNum $v) { return (NumStr $v) }
    if ($v -is [hashtable]) {
        $ks = SortStr @($v.Keys)
        if ($ks.Count -eq 0) { return '{}' }
        if ($pretty) {
            $pad = ' ' * (3 * ($lvl + 1)); $end = ' ' * (3 * $lvl)
            $parts = @(foreach ($k in $ks) { $pad + (JsStr $k) + ' : ' + (JsEnc $v[$k] $true ($lvl + 1)) })
            return "{`n" + ($parts -join ",`n") + "`n$end}"
        }
        return '{' + ((@(foreach ($k in $ks) { (JsStr $k) + ':' + (JsEnc $v[$k]) })) -join ',') + '}'
    }
    if ($v -is [array]) {
        if ($v.Count -eq 0) { return '[]' }
        if ($pretty) {
            $pad = ' ' * (3 * ($lvl + 1)); $end = ' ' * (3 * $lvl)
            $parts = @(foreach ($x in $v) { $pad + (JsEnc $x $true ($lvl + 1)) })
            return "[`n" + ($parts -join ",`n") + "`n$end]"
        }
        return '[' + ((@(foreach ($x in $v) { JsEnc $x })) -join ',') + ']'
    }
    return (JsStr ([string]$v))
}
function FromJsObj($o) {                             # ConvertFrom-Json output -> ordinal hashtables and arrays
    if ($null -eq $o) { return $null }
    if ($o -is [string] -or $o -is [bool]) { return $o }
    if (IsNum $o) { if ($o -is [decimal]) { $d = [double]$o; return $d }; return $o }
    if ($o -is [array]) { $r = @(foreach ($x in $o) { , (FromJsObj $x) }); return ,$r }
    if ($o -is [System.Management.Automation.PSCustomObject]) {
        $h = NewH
        foreach ($p in $o.PSObject.Properties) { $h[$p.Name] = FromJsObj $p.Value }
        return $h
    }
    return $o
}
function JsDec([string]$text) {
    $t = $text.Trim()
    if ($t -ceq '') { return $null }
    if ($t.StartsWith('[')) {                        # ConvertFrom-Json unrolls a top-level array: wrap it
        $w = ('{"a":' + $t + '}') | ConvertFrom-Json
        $r = FromJsObj $w
        return ,(L $r['a'])
    }
    if ($t.StartsWith('{')) { return (FromJsObj ($t | ConvertFrom-Json)) }
    return (FromJsObj ($t | ConvertFrom-Json))
}

# ---------------------------------------------------------------- hashing: MD5 (Digest::MD5) and SHA-256
$script:MD5S = [int[]]@(7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22, 5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20,
    4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23, 6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21)
$script:MD5K = [long[]]@(0xd76aa478L, 0xe8c7b756L, 0x242070dbL, 0xc1bdceeeL, 0xf57c0fafL, 0x4787c62aL, 0xa8304613L, 0xfd469501L,
    0x698098d8L, 0x8b44f7afL, 0xffff5bb1L, 0x895cd7beL, 0x6b901122L, 0xfd987193L, 0xa679438eL, 0x49b40821L,
    0xf61e2562L, 0xc040b340L, 0x265e5a51L, 0xe9b6c7aaL, 0xd62f105dL, 0x02441453L, 0xd8a1e681L, 0xe7d3fbc8L,
    0x21e1cde6L, 0xc33707d6L, 0xf4d50d87L, 0x455a14edL, 0xa9e3e905L, 0xfcefa3f8L, 0x676f02d9L, 0x8d2a4c8aL,
    0xfffa3942L, 0x8771f681L, 0x6d9d6122L, 0xfde5380cL, 0xa4beea44L, 0x4bdecfa9L, 0xf6bb4b60L, 0xbebfbc70L,
    0x289b7ec6L, 0xeaa127faL, 0xd4ef3085L, 0x04881d05L, 0xd9d4d039L, 0xe6db99e5L, 0x1fa27cf8L, 0xc4ac5665L,
    0xf4292244L, 0x432aff97L, 0xab9423a7L, 0xfc93a039L, 0x655b59c3L, 0x8f0ccc92L, 0xffeff47dL, 0x85845dd1L,
    0x6fa87e4fL, 0xfe2ce6e0L, 0xa3014314L, 0x4e0811a1L, 0xf7537e82L, 0xbd3af235L, 0x2ad7d2bbL, 0xeb86d391L)
function Md5Hex([string]$s) {
    $m = Utf8B $s
    $len = $m.Length
    $tot = $len + 9; $tot = $tot + ((64 - ($tot % 64)) % 64)
    $b = [byte[]]::new($tot)
    for ($i = 0; $i -lt $len; $i++) { $b[$i] = $m[$i] }
    $b[$len] = 0x80
    $bits = [long]$len * 8
    for ($i = 0; $i -lt 8; $i++) { $b[$tot - 8 + $i] = [byte](($bits -shr (8 * $i)) -band 0xff) }
    $M32 = 0xFFFFFFFFL
    $a0 = 0x67452301L; $b0 = 0xefcdab89L; $c0 = 0x98badcfeL; $d0 = 0x10325476L
    $w = [long[]]::new(16)
    for ($o = 0; $o -lt $tot; $o += 64) {
        for ($t = 0; $t -lt 16; $t++) { $j = $o + 4 * $t; $w[$t] = [long]$b[$j] -bor ([long]$b[$j + 1] -shl 8) -bor ([long]$b[$j + 2] -shl 16) -bor ([long]$b[$j + 3] -shl 24) }
        $ma = $a0; $mb = $b0; $mc = $c0; $md = $d0
        for ($i = 0; $i -lt 64; $i++) {
            if ($i -lt 16) { $mf = ($mb -band $mc) -bor (((-bnot $mb) -band $M32) -band $md); $g = $i }
            elseif ($i -lt 32) { $mf = ($md -band $mb) -bor (((-bnot $md) -band $M32) -band $mc); $g = (5 * $i + 1) % 16 }
            elseif ($i -lt 48) { $mf = $mb -bxor $mc -bxor $md; $g = (3 * $i + 5) % 16 }
            else { $mf = $mc -bxor ($mb -bor ((-bnot $md) -band $M32)); $g = (7 * $i) % 16 }
            $mf = ($mf + $ma + $script:MD5K[$i] + $w[$g]) -band $M32
            $ma = $md; $md = $mc; $mc = $mb
            $sh = $script:MD5S[$i]
            $mb = ($mb + ((($mf -shl $sh) -bor ($mf -shr (32 - $sh))) -band $M32)) -band $M32
        }
        $a0 = ($a0 + $ma) -band $M32; $b0 = ($b0 + $mb) -band $M32; $c0 = ($c0 + $mc) -band $M32; $d0 = ($d0 + $md) -band $M32
    }
    $o = ''
    foreach ($x in @($a0, $b0, $c0, $d0)) { for ($i = 0; $i -lt 4; $i++) { $o += ([int](($x -shr (8 * $i)) -band 0xff)).ToString('x2') } }
    return $o
}
$script:SHAK = [long[]]@(0x428a2f98L, 0x71374491L, 0xb5c0fbcfL, 0xe9b5dba5L, 0x3956c25bL, 0x59f111f1L, 0x923f82a4L, 0xab1c5ed5L,
    0xd807aa98L, 0x12835b01L, 0x243185beL, 0x550c7dc3L, 0x72be5d74L, 0x80deb1feL, 0x9bdc06a7L, 0xc19bf174L,
    0xe49b69c1L, 0xefbe4786L, 0x0fc19dc6L, 0x240ca1ccL, 0x2de92c6fL, 0x4a7484aaL, 0x5cb0a9dcL, 0x76f988daL,
    0x983e5152L, 0xa831c66dL, 0xb00327c8L, 0xbf597fc7L, 0xc6e00bf3L, 0xd5a79147L, 0x06ca6351L, 0x14292967L,
    0x27b70a85L, 0x2e1b2138L, 0x4d2c6dfcL, 0x53380d13L, 0x650a7354L, 0x766a0abbL, 0x81c2c92eL, 0x92722c85L,
    0xa2bfe8a1L, 0xa81a664bL, 0xc24b8b70L, 0xc76c51a3L, 0xd192e819L, 0xd6990624L, 0xf40e3585L, 0x106aa070L,
    0x19a4c116L, 0x1e376c08L, 0x2748774cL, 0x34b0bcb5L, 0x391c0cb3L, 0x4ed8aa4aL, 0x5b9cca4fL, 0x682e6ff3L,
    0x748f82eeL, 0x78a5636fL, 0x84c87814L, 0x8cc70208L, 0x90befffaL, 0xa4506cebL, 0xbef9a3f7L, 0xc67178f2L)
function Sha256Hex([byte[]]$m) {
    $len = $m.Length
    $tot = $len + 9; $tot = $tot + ((64 - ($tot % 64)) % 64)
    $b = [byte[]]::new($tot)
    if ($len) { [array]::Copy($m, $b, $len) }
    $b[$len] = 0x80
    $bits = [long]$len * 8
    for ($i = 0; $i -lt 8; $i++) { $b[$tot - 1 - $i] = [byte](($bits -shr (8 * $i)) -band 0xff) }
    $HS = [long[]]@(0x6a09e667L, 0xbb67ae85L, 0x3c6ef372L, 0xa54ff53aL, 0x510e527fL, 0x9b05688cL, 0x1f83d9abL, 0x5be0cd19L)
    $w = [long[]]::new(64); $KT = $script:SHAK; $M32 = 0xFFFFFFFFL
    for ($o = 0; $o -lt $tot; $o += 64) {
        for ($t = 0; $t -lt 16; $t++) { $j = $o + 4 * $t; $w[$t] = ([long]$b[$j] -shl 24) -bor ([long]$b[$j + 1] -shl 16) -bor ([long]$b[$j + 2] -shl 8) -bor [long]$b[$j + 3] }
        for ($t = 16; $t -lt 64; $t++) {
            $x = $w[$t - 15]; $sg0 = ((($x -shr 7) -bor ($x -shl 25)) -bxor (($x -shr 18) -bor ($x -shl 14)) -bxor ($x -shr 3)) -band $M32
            $x = $w[$t - 2]; $sg1 = ((($x -shr 17) -bor ($x -shl 15)) -bxor (($x -shr 19) -bor ($x -shl 13)) -bxor ($x -shr 10)) -band $M32
            $w[$t] = ($w[$t - 16] + $sg0 + $w[$t - 7] + $sg1) -band $M32
        }
        $va = $HS[0]; $vb = $HS[1]; $vc = $HS[2]; $vd = $HS[3]; $ve = $HS[4]; $vf = $HS[5]; $vg = $HS[6]; $vh = $HS[7]
        for ($t = 0; $t -lt 64; $t++) {
            $S1 = ((($ve -shr 6) -bor ($ve -shl 26)) -bxor (($ve -shr 11) -bor ($ve -shl 21)) -bxor (($ve -shr 25) -bor ($ve -shl 7))) -band $M32
            $ch = ($ve -band $vf) -bxor ((-bnot $ve) -band $M32 -band $vg)
            $t1 = ($vh + $S1 + $ch + $KT[$t] + $w[$t]) -band $M32
            $S0 = ((($va -shr 2) -bor ($va -shl 30)) -bxor (($va -shr 13) -bor ($va -shl 19)) -bxor (($va -shr 22) -bor ($va -shl 10))) -band $M32
            $mj = ($va -band $vb) -bxor ($va -band $vc) -bxor ($vb -band $vc)
            $t2 = ($S0 + $mj) -band $M32
            $vh = $vg; $vg = $vf; $vf = $ve; $ve = ($vd + $t1) -band $M32; $vd = $vc; $vc = $vb; $vb = $va; $va = ($t1 + $t2) -band $M32
        }
        $HS[0] = ($HS[0] + $va) -band $M32; $HS[1] = ($HS[1] + $vb) -band $M32; $HS[2] = ($HS[2] + $vc) -band $M32; $HS[3] = ($HS[3] + $vd) -band $M32
        $HS[4] = ($HS[4] + $ve) -band $M32; $HS[5] = ($HS[5] + $vf) -band $M32; $HS[6] = ($HS[6] + $vg) -band $M32; $HS[7] = ($HS[7] + $vh) -band $M32
    }
    return (@(foreach ($x in $HS) { $x.ToString('x8') }) -join '')
}
