<#
status-metrics.ps1 -- the 26 status metrics (A-Z) of docs/STATUS-METRICS.html in Windows PowerShell 5.1:
init / collect / report, a port of bin/status-metrics.pl + lib/StatusMetrics.pm (same files, byte for byte), plus
an Excel workbook and an HTML page of the dashboard for a PC with only PowerShell, Excel, Edge and Teams.

Runs in Constrained Language Mode: no Perl, no git, no .NET calls beyond core types. Git history is read straight
from the repository's .git directory (loose objects, through ziplib.ps1's inflate; packed objects are refused with
a message: unpack them once). lint_cmd and gen_cmd come from the config and may be PowerShell scripts
(status-metrics\lint.ps1, status-metrics\gen_docs.ps1, or sysml\model.ps1 lint) or programs.

  status-metrics.ps1 init    --config metrics.json --xmi legacy.xmi --reqif export.reqif     # once
  status-metrics.ps1 collect --config metrics.json [--as-of YYYY-MM-DD] [--history history.jsonl]   # daily
  status-metrics.ps1 report  --config metrics.json --history history.jsonl --out DIR [-Workbook] [-Html]

report writes status-weekly.md, status-daily.csv and dashboard.json (as the Perl and Python kits do); -Workbook
(or -Xlsx) also writes DIR\status-dashboard.xml (Excel workbook: Dashboard, A-Z by week, Daily) and -Html
DIR\status-dashboard.html (open in Edge, or select all and paste into a Teams post or an Outlook mail).

Dot-source with __lib to get the functions without running a command (tests).
#>
$ErrorActionPreference = 'Stop'
$script:RC = 0
$script:ERRNO = 0
. (Join-Path $PSScriptRoot 'ziplib.ps1')

# ================================================================ output
function Out-Text([string]$t) {
    if ($null -eq $t -or $t -eq '') { return }
    if ($t.EndsWith("`n")) { $t = $t.Substring(0, $t.Length - 1) }
    foreach ($ln in ($t -split "`n")) { Write-Output $ln }
}
function Out-Err([string]$t) {                         # Perl's STDERR: shown on the console, not in the output stream
    if ($null -eq $t -or $t -eq '') { return }
    if ($t.EndsWith("`n")) { $t = $t.Substring(0, $t.Length - 1) }
    foreach ($ln in ($t -split "`n")) { Write-Host $ln }
}

# ================================================================ JSON values
# object = @{ JO = 1; K = keys (case-sensitive, insertion order); V = values }   array = @{ JA = 1; V = @(...) }
# int = [long]/[int], float = [double], string, [bool], $null. Wrapped so PowerShell never unrolls them.
function JO { return @{ JO = 1; K = @(); V = @() } }
function JA($items) { $a = @{ JA = 1; V = @() }; if ($null -ne $items) { $a.V = @($items) }; return $a }
function IsJO($x) { return ($x -is [hashtable]) -and $x.ContainsKey('JO') }
function IsJA($x) { return ($x -is [hashtable]) -and $x.ContainsKey('JA') }
function JIdx($o, [string]$k) { $okeys = $o.K; for ($i = 0; $i -lt $okeys.Count; $i++) { if ($okeys[$i] -ceq $k) { return $i } }; return -1 }
function JSet($o, [string]$k, $v) {
    $i = JIdx $o $k
    if ($i -ge 0) { $o.V[$i] = $v; return }
    $o.K = @($o.K) + @($k); $o.V = @($o.V) + @(, $v)
}
function JGet($o, [string]$k) {
    if ($null -eq $o -or -not (IsJO $o)) { return $null }
    $i = JIdx $o $k
    if ($i -lt 0) { return $null }
    return $o.V[$i]
}
function JHas($o, [string]$k) { return ((IsJO $o) -and (JIdx $o $k) -ge 0) }
function JDel($o, [string]$k) {
    $i = JIdx $o $k
    if ($i -lt 0) { return }
    $nk = @(); $nv = @()
    for ($j = 0; $j -lt $o.K.Count; $j++) { if ($j -ne $i) { $nk += $o.K[$j]; $nv += , $o.V[$j] } }
    $o.K = $nk; $o.V = $nv
}
function JObj { $o = JO; for ($i = 0; $i + 1 -lt $args.Count; $i += 2) { JSet $o $args[$i] $args[$i + 1] }; return $o }   # JObj k v k v ...

function IsInt($v) { return ($v -is [int]) -or ($v -is [long]) -or ($v -is [int16]) -or ($v -is [byte]) }
function IsNum($v) { return (IsInt $v) -or ($v -is [double]) }

function PyFloat([double]$v) {                         # Python's repr(float): shortest round trip
    if ($v -ne $v) { return 'NaN' }
    if ($v -gt 1.7976931348623157E+308) { return 'Infinity' }
    if ($v -lt -1.7976931348623157E+308) { return '-Infinity' }
    $s = $null
    for ($p = 0; $p -le 16; $p++) {
        $s = $v.ToString('E' + $p).Replace(',', '.')
        if ([double]$s -eq $v) { break }
    }
    $m = [regex]::Match($s, '^(-?)(\d)(?:\.(\d+))?E([-+]\d+)$')
    if (-not $m.Success) { return $s }
    $sign = $m.Groups[1].Value; $digits = $m.Groups[2].Value + $m.Groups[3].Value
    $digits = $digits.TrimEnd('0'); if ($digits -eq '') { $digits = '0' }
    $exp = [int]$m.Groups[4].Value
    if ($exp -lt -4 -or $exp -ge 16) {
        $mm = $digits.Substring(0, 1); if ($digits.Length -gt 1) { $mm += '.' + $digits.Substring(1) }
        $ae = $exp; if ($ae -lt 0) { $ae = - $ae }
        $es = '+'; if ($exp -lt 0) { $es = '-' }
        return $sign + $mm + 'e' + $es + $ae.ToString('00')
    }
    if ($exp -lt 0) { return $sign + '0.' + ('0' * (- $exp - 1)) + $digits }
    $padded = $digits + ('0' * ($exp + 1))
    $ip = $padded.Substring(0, $exp + 1)
    $fp = '0'; if ($digits.Length -gt $exp + 1) { $fp = $digits.Substring($exp + 1) }
    return "$sign$ip.$fp"
}

function JStr([string]$s) {
    $sb = '"'
    foreach ($ch in $s.ToCharArray()) {
        $c = [int]$ch
        if ($ch -eq '"') { $sb += '\"' }
        elseif ($ch -eq '\') { $sb += '\\' }
        elseif ($c -eq 10) { $sb += '\n' } elseif ($c -eq 13) { $sb += '\r' } elseif ($c -eq 9) { $sb += '\t' }
        elseif ($c -eq 8) { $sb += '\b' } elseif ($c -eq 12) { $sb += '\f' }
        elseif ($c -lt 32 -or $c -gt 127) { $sb += '\u' + $c.ToString('x4') }
        else { $sb += $ch }
    }
    return $sb + '"'
}
function JStrFast([string]$s) {                        # the common case: printable ASCII with nothing to escape
    if ($s -cmatch '^[ !#-\[\]-~]*$') { return '"' + $s + '"' }
    return JStr $s
}

function JEnc($v, $ind = $null, [int]$lvl = 0) {       # Python's json.dumps(v[, indent=N]) with ensure_ascii
    if ($null -ne $ind) { $nl = "`n" + (' ' * ($ind * $lvl)); $nl1 = "`n" + (' ' * ($ind * ($lvl + 1))); $sep = ',' }
    else { $nl = ''; $nl1 = ''; $sep = ', ' }
    if ($null -eq $v) { return 'null' }
    if (IsJO $v) {
        if ($v.K.Count -eq 0) { return '{}' }
        $parts = @(for ($i = 0; $i -lt $v.K.Count; $i++) { $nl1 + (JStrFast $v.K[$i]) + ': ' + (JEnc $v.V[$i] $ind ($lvl + 1)) })
        return '{' + ($parts -join $sep) + "$nl}"
    }
    if (IsJA $v) {
        if ($v.V.Count -eq 0) { return '[]' }
        $parts = @(foreach ($x in $v.V) { $nl1 + (JEnc $x $ind ($lvl + 1)) })
        return '[' + ($parts -join $sep) + "$nl]"
    }
    if ($v -is [bool]) { if ($v) { return 'true' } else { return 'false' } }
    if (IsInt $v) { return ([long]$v).ToString() }
    if ($v -is [double]) { return PyFloat $v }
    return JStrFast ([string]$v)
}

function JDec([string]$t) {                            # -> value; objects keep their key order, numbers stay numbers
    $st = @{ t = $t; p = 0 }
    $v = JVal $st
    while ($st.p -lt $t.Length -and ' ', "`t", "`n", "`r" -contains [string]$t[$st.p]) { $st.p++ }
    if ($st.p -lt $t.Length) { throw "json: trailing data at offset $($st.p)" }
    return $v
}
function JWs($st) { $t = $st.t; while ($st.p -lt $t.Length) { $c = $t[$st.p]; if ($c -eq ' ' -or $c -eq "`t" -or $c -eq "`n" -or $c -eq "`r") { $st.p++ } else { break } } }
function JVal($st) {
    JWs $st
    $t = $st.t
    if ($st.p -ge $t.Length) { throw "json: unexpected input at offset $($st.p)" }
    $c = $t[$st.p]
    if ($c -eq '{') {
        $st.p++; $h = JO; JWs $st
        if ($t[$st.p] -eq '}') { $st.p++; return $h }
        while ($true) {
            JWs $st
            if ($t[$st.p] -ne '"') { throw "json: expected a key at offset $($st.p)" }
            $st.p++; $k = JStrBody $st
            JWs $st
            if ($t[$st.p] -ne ':') { throw "json: expected ':' at offset $($st.p)" }
            $st.p++
            JSet $h $k (JVal $st)
            JWs $st
            if ($t[$st.p] -eq ',') { $st.p++; continue }
            if ($t[$st.p] -eq '}') { $st.p++; return $h }
            throw "json: expected ',' or '}' at offset $($st.p)"
        }
    }
    if ($c -eq '[') {
        $st.p++; $items = @(); JWs $st
        if ($t[$st.p] -eq ']') { $st.p++; return (JA @()) }
        while ($true) {
            $items += , (JVal $st)
            JWs $st
            if ($t[$st.p] -eq ',') { $st.p++; continue }
            if ($t[$st.p] -eq ']') { $st.p++; return (JA $items) }
            throw "json: expected ',' or ']' at offset $($st.p)"
        }
    }
    if ($c -eq '"') { $st.p++; return (JStrBody $st) }
    $m = [regex]::Match($t.Substring($st.p), '^(-?(?:0|[1-9]\d*))((?:\.\d+)?(?:[eE][-+]?\d+)?)')
    if ($m.Success) {
        $st.p += $m.Length
        if ($m.Groups[2].Value -eq '') { return [long]$m.Groups[1].Value }
        return [double]($m.Groups[1].Value + $m.Groups[2].Value)
    }
    foreach ($w in @(@('true', $true), @('false', $false), @('null', $null))) {
        if ($st.p + $w[0].Length -le $t.Length -and $t.Substring($st.p, $w[0].Length) -ceq $w[0]) { $st.p += $w[0].Length; return $w[1] }
    }
    if ($t.Substring($st.p) -cmatch '^Infinity') { $st.p += 8; return [double]::PositiveInfinity }
    if ($t.Substring($st.p) -cmatch '^-Infinity') { $st.p += 9; return [double]::NegativeInfinity }
    throw "json: unexpected input at offset $($st.p)"
}
function JStrBody($st) {
    $t = $st.t; $s = ''
    while ($true) {
        if ($st.p -ge $t.Length) { throw 'json: unterminated string' }
        $q = $t.IndexOf('"', $st.p); $b = $t.IndexOf('\', $st.p)
        if ($q -lt 0) { throw 'json: unterminated string' }
        if ($b -lt 0 -or $q -lt $b) { $s += $t.Substring($st.p, $q - $st.p); $st.p = $q + 1; return $s }
        $s += $t.Substring($st.p, $b - $st.p); $st.p = $b
        $e = $t[$st.p + 1]
        if ($e -eq 'u') {
            $code = [int]('0x' + $t.Substring($st.p + 2, 4)); $st.p += 6
            $s += [string][char]$code
            continue
        }
        $map = @{ n = "`n"; r = "`r"; t = "`t"; b = [string][char]8; f = [string][char]12 }
        $es = [string]$e
        if ($map.ContainsKey($es) -and $es -cmatch '^[nrtbf]$') { $s += $map[$es] } else { $s += $es }
        $st.p += 2
    }
}

# ================================================================ helpers
function Floor([double]$x) { $i = [long]$x; if ($i -gt $x) { $i-- }; return $i }
function Rnd($x) { return (Floor ([double]$x + 0.5)) }
function Pct($n, $d) {                                 # round half up, never 100 until complete, never 0 once started
    if (-not $d) { return [long]0 }
    $r = Rnd (100.0 * $n / $d)
    if ($n -lt $d -and $r -ge 100) { $r = [long]99 }
    if ($n -gt 0 -and $r -eq 0) { $r = [long]1 }
    return $r
}
function ReadText([string]$p) {                        # UTF-8 text, as Perl's slurp + utf8::decode
    if (-not (Test-Path -LiteralPath $p -PathType Leaf)) { $script:ERRNO = 2; throw "${p}: No such file or directory" }
    $t = Get-Content -LiteralPath $p -Raw -Encoding UTF8 -ErrorAction Stop
    if ($null -eq $t) { return '' }
    return $t
}
function WriteText([string]$p, [string]$t) { Zl-WriteBytes $p (Zl-Utf8Enc $t) }
function AppendText([string]$p, [string]$t) {
    $b = Zl-Utf8Enc $t
    if (Test-Path -LiteralPath $p) { Add-Content -LiteralPath $p -Value $b -Encoding Byte } else { Zl-WriteBytes $p $b }
}
function Lines([string]$t) {                           # str.splitlines()
    if ($t -eq '') { return , @() }
    $ln = [regex]::Split($t, "\r\n|\r|\n")
    if ($ln.Count -and $ln[$ln.Count - 1] -eq '') { if ($ln.Count -eq 1) { return , @() }; $ln = $ln[0..($ln.Count - 2)] }
    return , @($ln)
}
function OrdSort($a) {                                 # Perl's sort / Python's sorted for strings: ordinal (merge sort)
    $a = @($a)
    if ($a.Count -le 1) { return , $a }
    $mid = [int](($a.Count - ($a.Count % 2)) / 2)
    $ln = OrdSort $a[0..($mid - 1)]; $r = OrdSort $a[$mid..($a.Count - 1)]
    $o = @(); $i = 0; $j = 0
    while ($i -lt $ln.Count -and $j -lt $r.Count) { if ([string]::CompareOrdinal([string]$ln[$i], [string]$r[$j]) -le 0) { $o += $ln[$i]; $i++ } else { $o += $r[$j]; $j++ } }
    while ($i -lt $ln.Count) { $o += $ln[$i]; $i++ }
    while ($j -lt $r.Count) { $o += $r[$j]; $j++ }
    return , $o
}
function NumSort($a) { return , @($a | Sort-Object { [double]$_ }) }

function NormPath([string]$p) {
    $p = $p.Replace('\', '/')
    $drive = ''
    if ($p -match '^([A-Za-z]:)(/.*)?$') { $drive = $Matches[1]; $p = $p.Substring(2); if ($p -eq '') { $p = '/' } }
    $abs = $p.StartsWith('/')
    $out = @()
    foreach ($c in ($p -split '/+')) {
        if ($c -eq '' -or $c -eq '.') { continue }
        if ($c -eq '..' -and $out.Count -and $out[$out.Count - 1] -ne '..') { if ($out.Count -eq 1) { $out = @() } else { $out = $out[0..($out.Count - 2)] } }
        elseif ($c -eq '..' -and $abs) { }
        else { $out += $c }
    }
    $r = ''; if ($abs) { $r = '/' }
    $r = $drive + $r + ($out -join '/')
    if ($r -eq '') { return '.' }
    return $r
}
function AbsPath([string]$p) {
    if ($p -match '^[A-Za-z]:[\\/]' -or $p.StartsWith('\\') -or $p.StartsWith('/')) { return NormPath $p }
    return NormPath ((Get-Location).ProviderPath + '/' + $p)
}
function AbsDir([string]$p) { $a = (AbsPath $p); $i = $a.LastIndexOf('/'); return NormPath $a.Substring(0, $i + 1) }
function IsAbs([string]$p) { return ($p -match '^[A-Za-z]:[\\/]' -or $p.StartsWith('/') -or $p.StartsWith('\\')) }

function LoadCfg([string]$path) {
    $cfg = JDec (ReadText $path)
    $base = AbsDir $path
    foreach ($k in @('repo', 'exports')) { $v = [string](JGet $cfg $k); if (IsAbs $v) { JSet $cfg $k (NormPath $v) } else { JSet $cfg $k (NormPath "$base/$v") } }
    JSet $cfg '_path' (AbsPath $path)
    return $cfg
}

function Walk([string]$root, [string]$rel = $null) {  # files under root (relative, sorted), dot entries skipped
    $dir = $root; if ($rel) { $dir = "$root/$rel" }
    if (-not (Test-Path -LiteralPath $dir -PathType Container)) { return , @() }
    $acc = @()
    $entries = OrdSort @(Get-ChildItem -LiteralPath $dir -Force | Where-Object { -not $_.Name.StartsWith('.') } | ForEach-Object { $_.Name })
    foreach ($e in $entries) {
        $r = $e; if ($rel) { $r = "$rel/$e" }
        if (Test-Path -LiteralPath "$root/$r" -PathType Container) { $acc += Walk $root $r }
        elseif (Test-Path -LiteralPath "$root/$r" -PathType Leaf) { $acc += $r }
    }
    return , $acc
}

# ---------------------------------------------------------------- SHA-256 (Get-FileHash is refused in CLM)
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
        $a = $HS[0]; $bb = $HS[1]; $c = $HS[2]; $d = $HS[3]; $e = $HS[4]; $f = $HS[5]; $g = $HS[6]; $hv = $HS[7]
        for ($t = 0; $t -lt 64; $t++) {
            $S1 = ((($e -shr 6) -bor ($e -shl 26)) -bxor (($e -shr 11) -bor ($e -shl 21)) -bxor (($e -shr 25) -bor ($e -shl 7))) -band $M32
            $ch = ($e -band $f) -bxor ((-bnot $e) -band $M32 -band $g)
            $t1 = ($hv + $S1 + $ch + $KT[$t] + $w[$t]) -band $M32
            $S0 = ((($a -shr 2) -bor ($a -shl 30)) -bxor (($a -shr 13) -bor ($a -shl 19)) -bxor (($a -shr 22) -bor ($a -shl 10))) -band $M32
            $mj = ($a -band $bb) -bxor ($a -band $c) -bxor ($bb -band $c)
            $t2 = ($S0 + $mj) -band $M32
            $hv = $g; $g = $f; $f = $e; $e = ($d + $t1) -band $M32; $d = $c; $c = $bb; $bb = $a; $a = ($t1 + $t2) -band $M32
        }
        $HS[0] = ($HS[0] + $a) -band $M32; $HS[1] = ($HS[1] + $bb) -band $M32; $HS[2] = ($HS[2] + $c) -band $M32; $HS[3] = ($HS[3] + $d) -band $M32
        $HS[4] = ($HS[4] + $e) -band $M32; $HS[5] = ($HS[5] + $f) -band $M32; $HS[6] = ($HS[6] + $g) -band $M32; $HS[7] = ($HS[7] + $hv) -band $M32
    }
    return (@(foreach ($x in $HS) { $x.ToString('x8') }) -join '')
}
function HashDir([string]$d) {                         # sha256 over (relative path, content) of every file, sorted
    $parts = @(); $n = 0
    foreach ($r in (OrdSort (Walk $d))) {
        $pb = Zl-Utf8Enc $r; $fb = Zl-ReadBytes "$d/$r"
        $parts += , $pb; $parts += , $fb; $n += $pb.Length + $fb.Length
    }
    $all = [byte[]]::new($n); $at = 0
    foreach ($p in $parts) { if ($p.Length) { [array]::Copy($p, 0, $all, $at, $p.Length); $at += $p.Length } }
    return Sha256Hex $all
}

function Attrs([string]$t) { $a = @{}; foreach ($m in [regex]::Matches($t, '(\w+)\s*=\s*"([^"]*)"')) { $a[$m.Groups[1].Value] = $m.Groups[2].Value }; return $a }

$script:RE_PAT = '^\s*(part|port|interface|connection|action|item)( def)?\b'
$script:RE_REQ = '^\s*requirement\s+(\w+)\s*\{(.*)\}'
$script:RE_SAT = '^\s*satisfy\s+(\w+)\b'
$script:RE_VER = '^\s*verify\s+(\w+)\b'
$script:RE_IFC = '^\s*interface\s+(\w+)\s*\{(.*)\}'
$script:RE_THR = '^\s*metadata\s+(\w+)\s*:\s*Threat\s*\{(.*)\}'

function ParseModel($files) {                          # $files = @( @(path, text) ... )
    $m = @{ elements = 0; reqs = @{}; sat = @{}; ver = @{}; ifcs = @{}; threats = @{} }
    $reqs = @{}; $sat = @{}; $ver = @{}; $ifcs = @{}; $thr = @{}; $el = 0
    foreach ($f in $files) {
        foreach ($line in (Lines $f[1])) {
            if ($line -cmatch $script:RE_PAT) { $el++ }
            $mm = [regex]::Match($line, $script:RE_REQ); if ($mm.Success) { $d = (Attrs $mm.Groups[2].Value)['doorsId']; if ($null -eq $d) { $d = '' }; $reqs['k' + (CaseKey $mm.Groups[1].Value)] = $d }
            $mm = [regex]::Match($line, $script:RE_SAT); if ($mm.Success) { $sat['k' + (CaseKey $mm.Groups[1].Value)] = 1 }
            $mm = [regex]::Match($line, $script:RE_VER); if ($mm.Success) { $ver['k' + (CaseKey $mm.Groups[1].Value)] = 1 }
            $mm = [regex]::Match($line, $script:RE_IFC); if ($mm.Success) { $ifcs['k' + (CaseKey $mm.Groups[1].Value)] = (Attrs $mm.Groups[2].Value) }
            $mm = [regex]::Match($line, $script:RE_THR); if ($mm.Success) { $thr['k' + (CaseKey $mm.Groups[1].Value)] = (Attrs $mm.Groups[2].Value) }
        }
    }
    $m.elements = $el; $m.reqs = $reqs; $m.sat = $sat; $m.ver = $ver; $m.ifcs = $ifcs; $m.threats = $thr
    return $m
}
# Hashtables here are case-insensitive, model names are not: keys are case-folded collisions in PowerShell, so they are
# kept as 'k' + name and compared through CaseKey, which escapes upper case letters.
function CaseKey([string]$s) { return ($s -creplace '([A-Z])', '^$1') }

function TreeFiles([string]$root) {
    $out = @()
    foreach ($r in (Walk "$root/model")) { if ($r -match '\.sysml$') { $out += , @("$root/model/$r", (ReadText "$root/model/$r")) } }
    return , $out
}

function RunCmd([string]$cwd, $cmd) {                  # -> @(stdout, exit code); stderr discarded
    $exe = [string]$cmd[0]; $rest = @(); if ($cmd.Count -gt 1) { $rest = @($cmd[1..($cmd.Count - 1)] | ForEach-Object { [string]$_ }) }
    Push-Location -LiteralPath $cwd
    try {
        $global:LASTEXITCODE = 0
        $o = @(& $exe @rest 2>$null)
        $code = $global:LASTEXITCODE; if ($null -eq $code) { $code = 0 }
    }
    catch { $o = @(); $code = 127 }
    finally { Pop-Location }
    $txt = (@($o | ForEach-Object { [string]$_ }) -join "`n"); if ($o.Count) { $txt += "`n" }
    return @($txt, $code)
}
function RunGen($cfg, [string]$src, [string]$out) {
    $cmd = @(foreach ($c in (JGet $cfg 'gen_cmd').V) { ([string]$c).Replace('{src}', $src).Replace('{out}', $out) })
    $r = RunCmd $src $cmd
    if ($r[1]) { throw "gen_cmd $($cmd -join ' '): exit $($r[1])" }
}

function CsvRows([string]$t) {                          # the csv module's default dialect
    $rows = @(); $row = @(); $f = ''; $q = $false; $started = $false; $p = 0; $n = $t.Length
    while ($p -lt $n) {
        $c = $t[$p]
        if ($q) {
            if ($c -eq '"') { if ($p + 1 -lt $n -and $t[$p + 1] -eq '"') { $f += '"'; $p += 2 } else { $q = $false; $p++ } }
            else { $e = $t.IndexOf('"', $p); if ($e -lt 0) { $e = $n }; $f += $t.Substring($p, $e - $p); $p = $e }
        }
        elseif ($c -eq '"') { $q = $true; $started = $true; $p++ }
        elseif ($c -eq ',') { $row += $f; $f = ''; $started = $true; $p++ }
        elseif ($c -eq "`r" -or $c -eq "`n") {
            if ($c -eq "`r" -and $p + 1 -lt $n -and $t[$p + 1] -eq "`n") { $p += 2 } else { $p++ }
            if ($started -or $f -ne '' -or $row.Count) { $row += $f }
            if ($row.Count) { $rows += , $row }
            $row = @(); $f = ''; $started = $false
        }
        else { $m = [regex]::Match($t.Substring($p), '^[^",\r\n]+'); $f += $m.Value; $p += $m.Length; $started = $true }
    }
    if ($started -or $f -ne '' -or $row.Count) { $row += $f }
    if ($row.Count) { $rows += , $row }
    return , $rows
}
function ReadCsv([string]$path) {                       # csv.DictReader: hashtables (case-sensitive lookups via exact keys)
    if (-not (Test-Path -LiteralPath $path)) { return , @() }
    $rows = CsvRows (ReadText $path)
    if (-not $rows.Count) { return , @() }
    $hdr = $rows[0]; $out = @()
    for ($i = 1; $i -lt $rows.Count; $i++) {
        $r = $rows[$i]; $d = @{}
        for ($k = 0; $k -lt $hdr.Count; $k++) { if ($k -lt $r.Count) { $d[$hdr[$k]] = $r[$k] } else { $d[$hdr[$k]] = $null } }
        $out += , $d
    }
    return , $out
}

# ---------------------------------------------------------------- dates
function DaysFromCivil([int]$y, [int]$m, [int]$d) {
    if ($m -le 2) { $y-- }
    $era = Floor ($y / 400.0)
    $yoe = $y - $era * 400
    $mp = ($m + 9) % 12
    $doy = (Floor ((153 * $mp + 2) / 5.0)) + $d - 1
    $doe = $yoe * 365 + (Floor ($yoe / 4.0)) - (Floor ($yoe / 100.0)) + $doy
    return [long]($era * 146097 + $doe - 719468)
}
function CivilFromDays([long]$z) {
    $z += 719468
    $era = Floor ($z / 146097.0)
    $doe = $z - $era * 146097
    $yoe = Floor (($doe - (Floor ($doe / 1460.0)) + (Floor ($doe / 36524.0)) - (Floor ($doe / 146096.0))) / 365.0)
    $y = $yoe + $era * 400
    $doy = $doe - (365 * $yoe + (Floor ($yoe / 4.0)) - (Floor ($yoe / 100.0)))
    $mp = Floor ((5 * $doy + 2) / 153.0)
    $d = $doy - (Floor ((153 * $mp + 2) / 5.0)) + 1
    $m = $mp + 3; if ($m -gt 12) { $m -= 12 }
    if ($m -le 2) { $y++ }
    return @([int]$y, [int]$m, [int]$d)
}
function DateEpoch([string]$s) {
    if ($s -notmatch '^(\d{4})-(\d\d)-(\d\d)$') { throw "bad date: $s" }
    return [long](DaysFromCivil ([int]$Matches[1]) ([int]$Matches[2]) ([int]$Matches[3])) * 86400
}
function EpochDate([double]$t) { $c = CivilFromDays (Floor ($t / 86400)); return ('{0:D4}-{1:D2}-{2:D2}' -f $c[0], $c[1], $c[2]) }
function TodayStr { return (Get-Date -Format 'yyyy-MM-dd') }
function Ts([string]$s) {                              # ISO 8601 -> @(epoch seconds, date as written); naive = UTC
    $m = [regex]::Match($s, '^(\d{4})-(\d\d)-(\d\d)(?:[T ](\d\d)(?::?(\d\d)(?::?(\d\d)(?:[.,](\d+))?)?)?)?\s*(Z|[-+]\d\d(?::?\d\d(?::?\d\d)?)?)?$')
    if (-not $m.Success) { throw "bad timestamp: $s" }
    $g = $m.Groups
    $t = [double](DaysFromCivil ([int]$g[1].Value) ([int]$g[2].Value) ([int]$g[3].Value)) * 86400
    if ($g[4].Success) { $t += 3600 * [int]$g[4].Value }
    if ($g[5].Success) { $t += 60 * [int]$g[5].Value }
    if ($g[6].Success) { $t += [int]$g[6].Value }
    if ($g[7].Success -and $g[7].Value -ne '') { $t += [double]('0.' + $g[7].Value) }
    $tz = $g[8].Value
    if ($tz -and $tz -ne 'Z') {
        $z = [regex]::Match($tz, '^([-+])(\d\d):?(\d\d)?:?(\d\d)?$')
        $off = 3600 * [int]$z.Groups[2].Value
        if ($z.Groups[3].Success) { $off += 60 * [int]$z.Groups[3].Value }
        if ($z.Groups[4].Success) { $off += [int]$z.Groups[4].Value }
        if ($z.Groups[1].Value -eq '+') { $t -= $off } else { $t += $off }
    }
    return @($t, "$($g[1].Value)-$($g[2].Value)-$($g[3].Value)")
}
function Commify($n) { $s = [string]$n; while ($s -match '^(-?\d+)(\d{3})') { $s = $s -replace '^(-?\d+)(\d{3})', '$1,$2' }; return $s }
function Median($xs) {
    $s = NumSort $xs; $n = $s.Count
    if ($n % 2) { return $s[($n - 1) / 2] }
    return ($s[$n / 2 - 1] + $s[$n / 2]) / 2
}

# ================================================================ git, read from .git (no git program)
# Every git use goes through these functions, so a library (pgit) can replace them.
$script:GOBJ = @{}; $script:GCOMMIT = @{}; $script:GTREE = @{}
function GitDir([string]$repo) { if (Test-Path -LiteralPath "$repo/.git" -PathType Container) { return "$repo/.git" }; return $repo }
function GitObj([string]$repo, [string]$sha) {
    if ($script:GOBJ.ContainsKey($sha)) { return $script:GOBJ[$sha] }
    $gd = GitDir $repo
    $p = "$gd/objects/$($sha.Substring(0, 2))/$($sha.Substring(2))"
    if (-not (Test-Path -LiteralPath $p)) {
        if (@(Get-ChildItem -LiteralPath "$gd/objects/pack" -Filter '*.pack' -ErrorAction SilentlyContinue).Count) {
            throw "git object $sha is packed: this reader takes loose objects only (unpack the repository once: see status-metrics README)"
        }
        throw "git object $sha not found in $gd"
    }
    $raw = Zl-Unzlib (Zl-ReadBytes $p)
    $z = [array]::IndexOf($raw, [byte]0)
    $hdr = Zl-Utf8Dec $raw 0 $z
    $sp = $hdr.IndexOf(' ')
    $body = [byte[]]::new($raw.Length - $z - 1)
    if ($body.Length) { [array]::Copy($raw, $z + 1, $body, 0, $body.Length) }
    $o = @{ type = $hdr.Substring(0, $sp); body = $body }
    $script:GOBJ[$sha] = $o
    return $o
}
function GitRefs([string]$repo) {                      # @{ refname = sha } from packed-refs and loose refs (loose wins)
    $gd = GitDir $repo; $r = @{}; $refnames = @()
    if (Test-Path -LiteralPath "$gd/packed-refs") {
        foreach ($ln in (Lines (ReadText "$gd/packed-refs"))) {
            if ($ln -match '^([0-9a-f]{40}) (\S+)$') { if (-not $r.ContainsKey($Matches[2])) { $refnames += $Matches[2] }; $r[$Matches[2]] = $Matches[1] }
        }
    }
    $base = (Resolve-Path -LiteralPath $gd).ProviderPath
    if (Test-Path -LiteralPath "$gd/refs") {
        foreach ($f in @(Get-ChildItem -LiteralPath "$gd/refs" -Recurse -File)) {
            $name = $f.FullName.Substring($base.Length).TrimStart('\', '/').Replace('\', '/')
            $v = (ReadText $f.FullName).Trim()
            if ($v -match '^[0-9a-f]{40}$') { if (-not $r.ContainsKey($name)) { $refnames += $name }; $r[$name] = $v }
        }
    }
    return @{ map = $r; names = $refnames }
}
function GitHead([string]$repo) {
    $gd = GitDir $repo
    $h = (ReadText "$gd/HEAD").Trim()
    if ($h -match '^[0-9a-f]{40}$') { return $h }
    if ($h -notmatch '^ref:\s*(\S+)$') { throw "HEAD: not understood: $h" }
    $refs = GitRefs $repo
    if (-not $refs.map.ContainsKey($Matches[1])) { throw "HEAD: $($Matches[1]) has no commit" }
    return $refs.map[$Matches[1]]
}
function SigTime([string]$v) { $m = [regex]::Match($v, '^(.*) <[^>]*> (\d+) ([-+]\d{4})$'); if ($m.Success) { return @($m.Groups[1].Value, [long]$m.Groups[2].Value) }; return @($v, [long]0) }
function Subject([string]$msg) {                       # git's subject: the first paragraph, lines joined with spaces
    $ls = @(); foreach ($ln in ($msg -split "`n")) { if ($ln.Trim() -eq '') { if ($ls.Count) { break } else { continue } }; $ls += $ln.Trim() }
    return ($ls -join ' ')
}
function GitCommit([string]$repo, [string]$sha) {
    if ($script:GCOMMIT.ContainsKey($sha)) { return $script:GCOMMIT[$sha] }
    $o = GitObj $repo $sha
    if ($o.type -ne 'commit') { throw "$sha is a $($o.type), not a commit" }
    $t = Zl-Utf8Dec $o.body 0 $o.body.Length
    $i = $t.IndexOf("`n`n"); $head = $t; $msg = ''
    if ($i -ge 0) { $head = $t.Substring(0, $i); $msg = $t.Substring($i + 2) }
    $c = @{ sha = $sha; tree = $null; parents = @(); an = ''; ct = [long]0; subject = (Subject $msg) }
    foreach ($ln in ($head -split "`n")) {
        if ($ln.StartsWith(' ')) { continue }
        $sp = $ln.IndexOf(' '); if ($sp -lt 0) { continue }
        $k = $ln.Substring(0, $sp); $v = $ln.Substring($sp + 1)
        if ($k -eq 'tree') { $c.tree = $v } elseif ($k -eq 'parent') { $c.parents = @($c.parents) + @($v) }
        elseif ($k -eq 'author') { $c.an = (SigTime $v)[0] } elseif ($k -eq 'committer') { $c.ct = (SigTime $v)[1] }
    }
    $script:GCOMMIT[$sha] = $c
    return $c
}
function GitTree([string]$repo, [string]$sha) {        # -> @( @{mode; name; sha} ... )
    if ($script:GTREE.ContainsKey($sha)) { return , $script:GTREE[$sha] }
    $o = GitObj $repo $sha
    $b = $o.body; $p = 0; $out = @()
    while ($p -lt $b.Length) {
        $sp = [array]::IndexOf($b, [byte]32, $p); $z = [array]::IndexOf($b, [byte]0, $sp)
        $mode = Zl-Utf8Dec $b $p ($sp - $p); $name = Zl-Utf8Dec $b ($sp + 1) ($z - $sp - 1)
        $h = (@(for ($k = $z + 1; $k -le $z + 20; $k++) { ([int]$b[$k]).ToString('x2') }) -join '')
        $out += , @{ mode = $mode; name = $name; sha = $h }
        $p = $z + 21
    }
    $script:GTREE[$sha] = $out
    return , $out
}
function GitPathSha([string]$repo, [string]$commit, [string]$path) {   # the sha of a top-level entry, or $null
    $c = GitCommit $repo $commit
    foreach ($e in (GitTree $repo $c.tree)) { if ($e.name -ceq $path) { return $e.sha } }
    return $null
}
function GitPeel([string]$repo, [string]$sha) { while ($true) { $o = GitObj $repo $sha; if ($o.type -ne 'tag') { return $sha }; $t = Zl-Utf8Dec $o.body 0 $o.body.Length; $sha = ([regex]::Match($t, '^object ([0-9a-f]{40})')).Groups[1].Value } }

function GitBaselineTags([string]$repo) {              # for-each-ref refname:short | taggerdate:unix | contents:subject
    $refs = GitRefs $repo; $out = @()
    foreach ($n in (OrdSort @($refs.names | Where-Object { $_.StartsWith('refs/tags/baseline-') }))) {
        $sha = $refs.map[$n]; $o = GitObj $repo $sha
        $date = ''; $subj = ''
        if ($o.type -eq 'tag') {
            $t = Zl-Utf8Dec $o.body 0 $o.body.Length
            $i = $t.IndexOf("`n`n"); $head = $t; $msg = ''
            if ($i -ge 0) { $head = $t.Substring(0, $i); $msg = $t.Substring($i + 2) }
            foreach ($ln in ($head -split "`n")) { if ($ln.StartsWith('tagger ')) { $date = [string](SigTime $ln.Substring(7))[1] } }
            $sig = $msg.IndexOf('-----BEGIN PGP SIGNATURE-----'); if ($sig -ge 0) { $msg = $msg.Substring(0, $sig) }
            $subj = Subject $msg
        }
        else { $subj = (GitCommit $repo $sha).subject }
        $out += , @{ name = $n.Substring(10); date = $date; subject = $subj; sha = $sha }
    }
    return , $out
}
function GitArchive([string]$repo, [string]$ref, [string]$dest, $collect) {   # write the tree of ref under dest
    $c = GitCommit $repo (GitPeel $repo $ref)
    GitWriteTree $repo $c.tree $dest '' $collect
}
function GitWriteTree([string]$repo, [string]$tree, [string]$dest, [string]$prefix, $collect) {
    foreach ($e in (GitTree $repo $tree)) {
        $p = $prefix + $e.name
        if ($e.mode -eq '40000') { New-Item -ItemType Directory -Force -Path "$dest/$p" | Out-Null; GitWriteTree $repo $e.sha $dest "$p/" $collect }
        elseif ($e.mode -eq '100644' -or $e.mode -eq '100755') {
            $o = GitObj $repo $e.sha
            Zl-WriteBytes "$dest/$p" $o.body
            if ($null -ne $collect -and $p -match '^model/.*\.sysml$') { $collect.files += , @($p, (Zl-Utf8Dec $o.body 0 $o.body.Length)) }
        }
    }
}
function GitWalkFirstParent([string]$repo) { $out = @(); $c = GitHead $repo; while ($c) { $cm = GitCommit $repo $c; $out += , $cm; if ($cm.parents.Count) { $c = $cm.parents[0] } else { $c = $null } }; return , $out }
function GitLogPath([string]$repo, [string]$path) {    # git log -- PATH: default history simplification, merges included
    $seen = @{}; $todo = @(GitHead $repo); $out = @()
    while ($todo.Count) {
        $c = $todo[$todo.Count - 1]; if ($todo.Count -gt 1) { $todo = $todo[0..($todo.Count - 2)] } else { $todo = @() }
        if ($seen.ContainsKey($c)) { continue }; $seen[$c] = 1
        $cm = GitCommit $repo $c
        $mine = GitPathSha $repo $c $path
        $follow = @($cm.parents); $same = $false
        if ($cm.parents.Count -eq 0) { $same = ($null -eq $mine) }
        else {
            foreach ($p in $cm.parents) { if ((GitPathSha $repo $p $path) -eq $mine) { $same = $true; $follow = @($p); break } }
        }
        if (-not $same) { $out += , $cm }
        $todo += $follow
    }
    return , $out
}

# ================================================================ init
$script:XMI_IN_SCOPE = 'xmi:type="uml:(?:Class|Port|Property|Connector|Activity)"'
function CmdInit($a) {
    $cfg = JDec (ReadText $a['config'])
    JSet $cfg 'v1_total' ([long]([regex]::Matches((ReadText $a['xmi']), $script:XMI_IN_SCOPE)).Count)
    JSet $cfg 'req_total' ([long]([regex]::Matches((ReadText $a['reqif']), '<SPEC-OBJECT ')).Count)
    JSet $cfg 'frozen' (TodayStr)
    WriteText $a['config'] (JEnc $cfg 2)
    Out-Text "v1_total=$(JGet $cfg 'v1_total') req_total=$(JGet $cfg 'req_total')`n"
    return 0
}

# ================================================================ collect
function Collect($cfg, [string]$asOf) {
    $repo = JGet $cfg 'repo'; $ex = JGet $cfg 'exports'
    $day = DateEpoch $asOf
    $start = DateEpoch ([string](JGet $cfg 'start'))
    $sw = JGet $cfg 'sprint_weeks'; if ($null -eq $sw) { $sw = 2 }
    $week = [long]((Floor (($day - $start) / 86400.0 / 7)) + 1)
    $sprint = [long]((Floor (($week - 1) / [double]$sw)) + 1)
    $wk0 = EpochDate ($start + ($week - 1) * 7 * 86400)
    $sp0 = EpochDate ($start + ($sprint - 1) * $sw * 7 * 86400)
    $end = $day + 86399
    $until = $day + 86399                                # --until=<day>T23:59:59+00:00
    $sinceWk = DateEpoch $wk0; $sinceSp = DateEpoch $sp0
    $MX = @{}

    # model facts (A B C E F G I Q R)
    $mdl = ParseModel (TreeFiles $repo)
    $el = [long]$mdl.elements
    $MX['A'] = JObj 'v' (Pct $el (JGet $cfg 'v1_total')) 'elements' $el
    $gated = [long]0
    if (Test-Path -LiteralPath "$repo/CODEOWNERS") { foreach ($ln in (Lines (ReadText "$repo/CODEOWNERS"))) { $x = $ln.Trim().TrimStart('/'); if ($x.StartsWith('model/')) { $gated++ } } }
    $MX['B'] = JObj 'v' $gated 'total' (JGet $cfg 'segments')
    $linked = @($mdl.reqs.Keys | Where-Object { $mdl.reqs[$_] -ne '' })
    $doors = @{}; foreach ($k in $linked) { $doors['d' + (CaseKey $mdl.reqs[$k])] = 1 }
    $MX['C'] = JObj 'v' ([long]$doors.Count) 'total' (JGet $cfg 'req_total')
    $lr = RunCmd $repo @((JGet $cfg 'lint_cmd').V)
    $err = $null; $warn = $null
    $mm = [regex]::Match($lr[0], 'errors=(\d+)\s+warnings=(\d+)'); if ($mm.Success) { $err = [long]$mm.Groups[1].Value; $warn = [long]$mm.Groups[2].Value }
    $MX['E'] = JObj 'v' $err 'w' $warn 'elements' $el
    $orph = @{}; $unv = @{}
    foreach ($k in $linked) { if (-not $mdl.sat.ContainsKey($k)) { $orph[$k] = 1 }; if (-not $mdl.ver.ContainsKey($k)) { $unv[$k] = 1 } }
    $MX['F'] = JObj 'v' ([long]$orph.Count)
    $MX['G'] = JObj 'v' ([long]$unv.Count)
    $traced = [long]@($linked | Where-Object { -not $orph.ContainsKey($_) -and -not $unv.ContainsKey($_) }).Count
    $MX['I'] = JObj 'v' (Pct $traced (JGet $cfg 'req_total'))
    $cross = @($mdl.ifcs.Values | Where-Object { $a = $_['fromZone']; $b = $_['toZone']; if ($null -eq $a) { $a = [string][char]0 }; if ($null -eq $b) { $b = [string][char]0 }; $a -cne $b })
    $MX['Q'] = JObj 'v' ([long]@($cross | Where-Object { -not ($null -ne $_['secReq'] -and $_['secReq'] -ne '') }).Count) 'total' ([long]$cross.Count)
    $thr = @($mdl.threats.Values)
    $MX['R'] = JObj 'v' ([long]@($thr | Where-Object { -not ($null -ne $_['mitigation'] -and $_['mitigation'] -ne '') }).Count) 'total' ([long]$thr.Count)

    # baselines (D S)
    $tags = @()
    foreach ($tg in (GitBaselineTags $repo)) {
        if ($tg.date -eq '' -or [long]$tg.date -gt $end) { continue }
        $num = ($tg.name -split '-')[1]
        if ($null -eq $num -or $num -notmatch '^\s*[-+]?\d+\s*$') { throw "tag $($tg.name): not baseline-<number>" }
        $tags += , @([long]$num, $tg.name, $tg.subject, $tg.sha)
    }
    $tags = @($tags | Sort-Object -Property @{ Expression = { $_[0] } }, @{ Expression = { $_[1] } }, @{ Expression = { $_[2] } })
    if ($tags.Count) {
        $ok = [long]0; $latest = @{ files = @() }
        for ($ti = 0; $ti -lt $tags.Count; $ti++) {
            $tg = $tags[$ti]
            $tmp = NewTempDir
            try {
                $col = $null; if ($ti -eq $tags.Count - 1) { $col = $latest }
                GitArchive $repo $tg[3] $tmp $col
                $out = "$tmp/_rebuild"
                RunGen $cfg $tmp $out
                if ($tg[2] -ceq ('sha256=' + (HashDir "$out/docs"))) { $ok++ }
            }
            finally { Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue }
        }
        $MX['D'] = JObj 'v' ([long](ParseModel $latest.files).elements) 'tag' ([string]$tags[$tags.Count - 1][0])
        $MX['S'] = JObj 'v' $ok 'total' ([long]$tags.Count)
    }
    else { $MX['D'] = JObj 'v' $null 'tag' $null; $MX['S'] = JObj 'v' $null 'total' ([long]0) }

    # gate log (H)
    $caught = [long]0
    if (Test-Path -LiteralPath "$ex/gate.log") {
        foreach ($ln in (Lines (ReadText "$ex/gate.log"))) { $p = @($ln.Trim() -split '\s+' | Where-Object { $_ -ne '' }); if ($p.Count -gt 1 -and $p[1] -ceq 'E-IF' -and (Ts $p[0])[0] -le $end) { $caught++ } }
    }
    $reached = [long]@((ReadCsv "$ex/defects.csv") | Where-Object { $_['phase'] -ceq 'integration' -and $_['type'] -ceq 'interface' }).Count
    $MX['H'] = JObj 'v' $caught 'reached' $reached

    # documents (J K L M O T)
    $gdocs = "$repo/generated/docs"
    $ndocs = [long]0
    if (Test-Path -LiteralPath $gdocs -PathType Container) { $ndocs = [long]@(Get-ChildItem -LiteralPath $gdocs -Force -File | Where-Object { -not $_.Name.StartsWith('.') }).Count }
    $MX['L'] = JObj 'v' $ndocs 'total' (JGet $cfg 'docs_total')
    $jv = $null; if ($ndocs) { $jv = Rnd ($ndocs * (JGet $cfg 'hours_per_doc')) }
    $MX['J'] = JObj 'v' $jv
    $jobs = @((ReadCsv "$ex/ci_jobs.csv") | Where-Object { (Ts $_['ts'])[0] -le $end })
    $dj = @($jobs | Where-Object { $_['job'] -ceq 'docs' -and $_['result'] -ceq 'pass' })
    $kv = $null; if ($dj.Count) { $kv = Rnd ([double]$dj[$dj.Count - 1]['minutes']) }
    $MX['K'] = JObj 'v' $kv 'old' (JGet $cfg 'old_regen_days')
    if ($ndocs) {
        $subs = @((GitLogPath $repo 'released') | Where-Object { $_.parents.Count -le 1 -and $_.ct -ge $sinceWk -and $_.ct -le $until })
        $MX['M'] = JObj 'v' ([long]@($subs | Where-Object { $_.subject.IndexOf('generated') -lt 0 }).Count)
    }
    else { $MX['M'] = JObj 'v' $null }
    $ph = "$repo/generated/params/params.h"
    if (Test-Path -LiteralPath $ph) { $MX['O'] = JObj 'v' ([long]@((Lines (ReadText $ph)) | Where-Object { $_ -cmatch '^#define' }).Count) 'total' (JGet $cfg 'params_total') }
    else { $MX['O'] = JObj 'v' $null 'total' (JGet $cfg 'params_total') }
    $icd = "$gdocs/icd.csv"
    if (Test-Path -LiteralPath $icd) {
        $tmp = NewTempDir
        try {
            RunGen $cfg $repo $tmp
            $a1 = Lines (ReadText $icd); $a2 = Lines (ReadText "$tmp/docs/icd.csv")
        }
        finally { Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue }
        $n = $a1.Count; if ($a2.Count -lt $n) { $n = $a2.Count }
        $drift = [long]0
        for ($i = 0; $i -lt $n; $i++) { if ($a1[$i] -cne $a2[$i]) { $drift++ } }
        $dd = [long]($a1.Count - $a2.Count); if ($dd -lt 0) { $dd = - $dd }
        $drift += $dd
        $gen = @{}; foreach ($r in (ReadCsv $icd)) { $k = $r['id']; if ($null -eq $k) { $k = '' }; $gen['k' + (CaseKey $k)] = $r }
        $leg = @{}; foreach ($r in (ReadCsv "$ex/legacy_icd.csv")) { $k = $r['id']; if ($null -eq $k) { $k = '' }; $leg['k' + (CaseKey $k)] = $r }
        $open = [long]0
        foreach ($k in $gen.Keys) {
            if (-not $leg.ContainsKey($k)) { continue }
            foreach ($f in @('from', 'to', 'fromZone', 'toZone', 'signal', 'rate', 'units')) {
                $x = $gen[$k][$f]; $y = $leg[$k][$f]; if ($null -eq $x) { $x = [string][char]0 }; if ($null -eq $y) { $y = [string][char]0 }
                if ($x -cne $y) { $open++ }
            }
        }
        $MX['T'] = JObj 'v' $drift 'legacy' $open
    }
    else { $MX['T'] = JObj 'v' $null 'legacy' $null }

    # git history (N U V Z)
    $fp = GitWalkFirstParent $repo
    $merges = @($fp | Where-Object { $_.parents.Count -ge 2 -and $_.ct -le $until } | Select-Object -First 10)
    $leads = @()
    foreach ($m in $merges) {
        if ($m.parents.Count -lt 2) { throw "git log $($m.sha)^1..$($m.sha)^2: not a two-parent merge" }
        $stop = GitReach $repo $m.parents[0] @{}
        $only = GitReach $repo $m.parents[1] $stop
        if ($only.Count) {
            $min = $null; foreach ($h in $only.Keys) { $t = (GitCommit $repo $h).ct; if ($null -eq $min -or $t -lt $min) { $min = $t } }
            $leads += ($m.ct - $min) / 86400.0
        }
    }
    $nv = $null; if ($leads.Count) { $nv = Rnd (Median $leads) }
    $MX['N'] = JObj 'v' $nv 'old' (JGet $cfg 'old_lead_days')
    $subsSp = @($fp | Where-Object { $_.parents.Count -ge 2 -and $_.ct -ge $sinceSp -and $_.ct -le $until } | ForEach-Object { $_.subject })
    $MX['U'] = JObj 'v' ([long]$subsSp.Count)
    $bad = [long]@($subsSp | Where-Object { $_ -cmatch '^(?:Revert|Merge fix-forward)' }).Count
    $vv = $null; if ($subsSp.Count) { $vv = Pct $bad $subsSp.Count }
    $MX['V'] = JObj 'v' $vv
    $exa = @{}; $ea = JGet $cfg 'exclude_authors'; if ($null -ne $ea) { foreach ($x in $ea.V) { $exa['a' + (CaseKey ([string]$x))] = 1 } }
    $auth = @{}
    foreach ($c in (GitLogPath $repo 'model')) { if ($c.parents.Count -le 1 -and $c.ct -le $until) { $auth['a' + (CaseKey $c.an)] = 1 } }
    $MX['Z'] = JObj 'v' ([long]@($auth.Keys | Where-Object { -not $exa.ContainsKey($_) }).Count) 'total' (JGet $cfg 'team')

    # sim runs (P)
    $runs = [long]0; $pinned = [long]0
    if (Test-Path -LiteralPath "$ex/runs" -PathType Container) {
        foreach ($r in (OrdSort @(Get-ChildItem -LiteralPath "$ex/runs" -Force | Where-Object { -not $_.Name.StartsWith('.') } | ForEach-Object { $_.Name }))) {
            $pv = "$ex/runs/$r/provenance.txt"
            if (-not (Test-Path -LiteralPath $pv -PathType Leaf)) { continue }
            $kv2 = @{}
            foreach ($ln in (Lines (ReadText $pv))) { if ($ln -notmatch '=') { continue }; $x = $ln.Trim(); $i = $x.IndexOf('='); $kv2[$x.Substring(0, $i)] = $x.Substring($i + 1) }
            if ($null -eq $kv2['date']) { throw "${pv}: no date" }
            if ((DateEpoch $kv2['date']) -le $day) { $runs++; if ($null -ne $kv2['model_baseline'] -and $kv2['model_baseline'] -ne '') { $pinned++ } }
        }
    }
    $pvv = $null; if ($runs) { $pvv = $pinned }
    $MX['P'] = JObj 'v' $pvv 'total' $runs

    # CI restore (W): worst time from a failure on main to the next pass, this week
    $worst = $null
    for ($i = 0; $i -lt $jobs.Count; $i++) {
        $r = $jobs[$i]
        if (-not ($r['result'] -ceq 'fail' -and $r['branch'] -ceq 'main')) { continue }
        $t0 = Ts $r['ts']
        if ([string]::CompareOrdinal($t0[1], $wk0) -lt 0) { continue }
        $nxt = $null
        for ($j = $i + 1; $j -lt $jobs.Count; $j++) { if ($jobs[$j]['job'] -ceq $r['job'] -and $jobs[$j]['result'] -ceq 'pass') { $nxt = $jobs[$j]; break } }
        if ($null -eq $nxt) { continue }
        $hrs = ((Ts $nxt['ts'])[0] - $t0[0]) / 3600.0
        if ($null -eq $worst -or $hrs -gt $worst) { $worst = $hrs }
    }
    $wv = $null; if ($null -ne $worst) { $wv = Rnd $worst }
    $MX['W'] = JObj 'v' $wv

    # tracker (X Y)
    $rows = ReadCsv "$ex/tracker/sprint-$sprint.csv"
    $done = [long]@($rows | Where-Object { $_['status'] -ceq 'done' }).Count
    $xv = $null; if ($rows.Count) { $xv = Pct $done $rows.Count }
    $MX['X'] = JObj 'v' $xv
    $blocked = @($rows | Where-Object { [long](PerlInt $_['blocked_days']) })
    $by = @{}; $order = @()
    foreach ($r in $blocked) { $k = 'b' + (CaseKey ([string]$r['blocker'])); if (-not $by.ContainsKey($k)) { $order += , @($k, $r['blocker']); $by[$k] = [long]0 }; $by[$k] += [long](PerlInt $r['blocked_days']) }
    $top = $null; $topk = $null
    foreach ($o in $order) { if ($null -eq $topk -or $by[$o[0]] -gt $by[$topk]) { $topk = $o[0]; $top = $o[1] } }
    $sumb = [long]0; foreach ($r in $blocked) { $sumb += [long](PerlInt $r['blocked_days']) }
    $yv = $null; if ($rows.Count) { $yv = $sumb }
    if ($null -eq $top) { $top = 'none' }
    $MX['Y'] = JObj 'v' $yv 'blocker' $top

    $mo = JO
    foreach ($L in $script:LETTERS) { if ($MX.ContainsKey($L)) { JSet $mo $L $MX[$L] } }
    return (JObj 'date' $asOf 'week' $week 'sprint' $sprint 'm' $mo)
}
function PerlInt($s) {                                  # Perl's int("3 days") / int(""): leading number, else 0
    if ($null -eq $s) { return 0 }
    $m = [regex]::Match([string]$s, '^\s*([-+]?\d+)')
    if ($m.Success) { return [long]$m.Groups[1].Value }
    return 0
}
function GitReach([string]$repo, [string]$from, $stop) {   # commits reachable from $from, not walking into $stop
    $seen = @{}; $todo = @($from)
    while ($todo.Count) {
        $c = $todo[$todo.Count - 1]; if ($todo.Count -gt 1) { $todo = $todo[0..($todo.Count - 2)] } else { $todo = @() }
        if ($seen.ContainsKey($c) -or $stop.ContainsKey($c)) { continue }
        $seen[$c] = 1
        $todo += @((GitCommit $repo $c).parents)
    }
    return $seen
}
function NewTempDir {
    $base = $env:TEMP; if (-not $base) { $base = '.' }
    $d = Join-Path $base ('status-metrics-' + (Get-Random) + '-' + (Get-Random))
    New-Item -ItemType Directory -Path $d -Force | Out-Null
    return ($d.Replace('\', '/'))
}

function CmdCollect($a) {
    $cfg = LoadCfg $a['config']
    $asOf = $a['as-of']; if (-not $asOf) { $asOf = TodayStr }
    $line = JEnc (Collect $cfg $asOf)
    if ($a['history']) { AppendText $a['history'] "$line`n" } else { Out-Text "$line`n" }
    return 0
}

# ================================================================ report
$script:LETTERS = @('A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M', 'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z')
$script:EMDASH = [string][char]0x2014
$script:NAMES = @{
    A = '% under configuration control'; B = 'Segments gated (of {segments})'
    C = 'Requirements linked (of {req_total:,})'; D = 'Elements in latest baseline'
    E = 'Lint errors / warnings'; F = 'Orphan requirements'; G = 'Unverified requirements'
    H = 'Interface mismatches caught (to date)'; I = 'Trace completeness %'
    J = 'Labor hours saved per baseline'; K = 'Regeneration time (min)'
    L = 'Documents generated (of {docs_total})'; M = 'Hand edits'; N = 'Lead time (days)'
    O = 'Parameters sourced (of {params_total})'; P = 'Sim runs pinned (to date)'
    Q = 'Uncovered zone crossings'; R = 'Unmitigated threats'; S = 'Reproducible baselines'
    T = 'Legacy ICD discrepancies open'; U = 'Merges per sprint'; V = 'Change failure rate %'
    W = 'Time to restore (h)'; X = 'Done % (sprint)'; Y = 'Blocked days (sprint)'
    Z = 'Active contributors (of {team})'
}
$script:SPRINT_METRICS = 'UVXY'

function PyStr($v) {                                    # str(x) for what the history holds
    if ($null -eq $v) { return 'None' }
    if ($v -is [bool] -or (IsNum $v)) { return JEnc $v }
    if ((IsJO $v) -or (IsJA $v)) { return JEnc $v }
    return [string]$v
}
function Cell([string]$L, $d, $week, $sw) {
    $v = JGet $d 'v'
    if ($script:SPRINT_METRICS.Contains($L) -and ($week % $sw)) { return $script:EMDASH }
    if ($L -eq 'T') { $v = JGet $d 'legacy' }
    if ($null -eq $v) { return $script:EMDASH }
    if ($L -eq 'E') { return (PyStr $v) + '/' + (PyStr (JGet $d 'w')) }
    if ('PQRS'.Contains($L)) { return (PyStr $v) + ' of ' + (PyStr (JGet $d 'total')) }
    if ('CD'.Contains($L)) { return Commify (PyStr $v) }
    return PyStr $v
}
function LoadHistory([string]$p) { return , @(foreach ($ln in (Lines (ReadText $p))) { if ($ln -match '\S') { JDec $ln } }) }
function Weekly($hist) {
    $w = @{}; foreach ($e in $hist) { $w['w' + (JGet $e 'week')] = $e }
    $wnums = @($hist | ForEach-Object { [long](JGet $_ 'week') } | Sort-Object -Unique)
    return , @(foreach ($k in $wnums) { $w['w' + $k] })
}
function MetricName([string]$L, $cfg) {
    $t = $script:NAMES[$L]; $o = ''; $at = 0
    foreach ($m in [regex]::Matches($t, '\{(\w+)(:,)?\}')) {
        $v = PyStr (JGet $cfg $m.Groups[1].Value); if ($m.Groups[2].Success) { $v = Commify $v }
        $o += $t.Substring($at, $m.Index - $at) + $v; $at = $m.Index + $m.Length
    }
    return $o + $t.Substring($at)
}
function CsvLine($fields) {
    return ((@(foreach ($f in $fields) { $f = [string]$f; if ($f -match '[",\r\n]') { '"' + $f.Replace('"', '""') + '"' } else { $f } }) -join ',') + "`r`n")
}
function IsNumeric($v) { return (IsNum $v) -and -not ($v -is [bool]) }

function CmdReport($a) {
    $cfg = LoadCfg $a['config']
    $sw = JGet $cfg 'sprint_weeks'; if ($null -eq $sw) { $sw = 2 }
    $hist = LoadHistory $a['history']
    $weeks = Weekly $hist
    $out = $a['out']; if (-not $out) { $out = '.' }
    New-Item -ItemType Directory -Force -Path $out | Out-Null

    $t = @(('| | Metric | ' + (@($weeks | ForEach-Object { 'W' + (PyStr (JGet $_ 'week')) }) -join ' | ') + ' |'), ('|---|---|' + ('---|' * $weeks.Count)))
    foreach ($L in $script:LETTERS) {
        $t += "| $L | " + (MetricName $L $cfg) + ' | ' + (@($weeks | ForEach-Object { Cell $L (JGet (JGet $_ 'm') $L) (JGet $_ 'week') $sw }) -join ' | ') + ' |'
    }
    WriteText "$out/status-weekly.md" (($t -join "`n") + "`n")

    $csv = CsvLine (@('date', 'week', 'sprint', 'elements') + $script:LETTERS)
    foreach ($e in $hist) {
        $m = JGet $e 'm'
        $csv += CsvLine (@((JGet $e 'date'), (PyStr (JGet $e 'week')), (PyStr (JGet $e 'sprint')), (PyStr (JGet (JGet $m 'A') 'elements'))) + @(foreach ($L in $script:LETTERS) { Cell $L (JGet $m $L) $sw $sw }))
    }
    WriteText "$out/status-daily.csv" $csv

    $dash = Dashboard $hist $weeks
    WriteText "$out/dashboard.json" (JEnc $dash 2)
    Out-Text ("wrote status-weekly.md ({0} weeks), status-daily.csv ({1} days), dashboard.json`n" -f $weeks.Count, $hist.Count)
    if ($a['workbook']) { WriteText "$out/status-dashboard.xml" (DashWorkbook $cfg $hist $weeks $dash $sw); Out-Text "wrote status-dashboard.xml`n" }
    if ($a['html']) { WriteText "$out/status-dashboard.html" (DashHtml $cfg $dash); Out-Text "wrote status-dashboard.html`n" }
    return 0
}
function Dashboard($hist, $weeks) {
    $lastw = $weeks[$weeks.Count - 1]
    $prevw = $null; if ($weeks.Count -gt 1) { $prevw = $weeks[$weeks.Count - 2] }
    $tag = JGet (JGet (JGet $lastw 'm') 'D') 'tag'
    $bl = 'none'; if ($null -ne $tag -and [string]$tag -ne '') { $bl = "baseline-$tag" }
    $dash = JObj 'sprint' ('Sprint ' + (PyStr (JGet $lastw 'sprint'))) 'date' (JGet $hist[$hist.Count - 1] 'date') 'baseline' $bl 'sel' (JA @('A', 'C', 'H')) 'm' (JO)
    $dm = JGet $dash 'm'
    foreach ($L in $script:LETTERS) {
        $src = JGet (JGet $hist[$hist.Count - 1] 'm') $L
        $d = JO
        if ($null -ne $src) { for ($i = 0; $i -lt $src.K.Count; $i++) { if ($null -ne $src.V[$i]) { JSet $d $src.K[$i] $src.V[$i] } } }
        if ($null -ne $prevw) { $pv = JGet (JGet (JGet $prevw 'm') $L) 'v'; if ($null -ne $pv) { JSet $d 'prev' $pv } }
        $key = 'v'; if ($L -eq 'T') { $key = 'legacy' }
        JSet $d 'hist' (JA @(foreach ($w in $weeks) { $x = JGet (JGet (JGet $w 'm') $L) $key; if (IsNumeric $x) { $x } }))
        if ($L -eq 'T' -and $null -eq (JGet $d 'legacy')) { JDel $d 'legacy' }
        JSet $dm $L $d
    }
    return $dash
}

# ---------------------------------------------------------------- the dashboard as Excel and HTML (new: not in Perl)
# Formats, directions, targets and phrases are docs/STATUS-DASHBOARD.html's DEF table; status() is its rule:
# no value = act; info = tracking; zero = on target when the key is 0; else on target at the target, improving when
# better than last week, else act.
$script:SECTIONS = @(@('Coverage', 'ABCD'), @('Quality', 'EFGHI'), @('Time and cost', 'JKLMN'), @('Digital thread', 'OP'), @('Risk retired', 'QRST'), @('Flow', 'UVWXYZ'))
$script:DEF = @{
    A = @{ n = '% under configuration control'; f = '{v}%'; dir = 'up'; t = 100; p = '{v}% of the IAMD architecture is now under configuration control as text, up from {prev}%.' }
    B = @{ n = 'Segments gated'; f = '{v} of {total}'; dir = 'up'; t = 'total'; p = '{v} of {total} segments are now gated on every merge.' }
    C = @{ n = 'Requirements linked'; f = '{v} of {total}'; dir = 'up'; t = 'total'; p = '{v} of {total} DOORS requirements are now linked to model elements.' }
    D = @{ n = 'Elements in baseline'; f = '{v}'; dir = 'info'; p = 'Baseline {tag} holds {v} elements, up {delta} from the last baseline.' }
    E = @{ n = 'Lint errors / warnings'; f = '{v} / {w}'; dir = 'down'; t = 0; sum = 'w'; p = 'The model lints {v} errors / {w} warnings across {elements} elements.' }
    F = @{ n = 'Orphan requirements'; f = '{v}'; dir = 'down'; t = 0; p = 'There are {v} orphan requirements. Last week there were {prev}.' }
    G = @{ n = 'Unverified requirements'; f = '{v}'; dir = 'down'; t = 0; p = 'Requirements with no verification method went from {prev} to {v}.' }
    H = @{ n = 'Interface mismatches caught at merge'; f = '{v}'; dir = 'zero'; key = 'reached'; p = 'The pipeline caught {v} interface mismatches before review, and {reached} reached integration.' }
    I = @{ n = 'Trace completeness'; f = '{v}%'; dir = 'up'; t = 100; p = '{v}% of requirements are traced satisfy-to-verify end to end.' }
    J = @{ n = 'Labor hours saved'; f = '{v} h'; dir = 'info'; p = 'Generated interface tables save about {v} labor hours per baseline.' }
    K = @{ n = 'Regeneration time'; f = '{v} min'; dir = 'down'; t = 15; p = 'ICD views now regenerate in {v} minutes. The old process took {old} days.' }
    L = @{ n = 'Documents generated'; f = '{v} of {total}'; dir = 'up'; t = 'total'; p = '{v} of {total} program documents now come straight from the model.' }
    M = @{ n = 'Hand edits'; f = '{v}'; dir = 'down'; t = 0; p = 'Generated documents needed {v} hand edits this sprint, against {prev} last sprint.' }
    N = @{ n = 'Lead time'; f = '{v} d'; dir = 'down'; t = 5; p = 'A model change now reaches a reviewed baseline in {v} days. Before, it took {old} days.' }
    O = @{ n = 'Parameters sourced from the model'; f = '{v} of {total}'; dir = 'up'; t = 'total'; p = '{v} of {total} sim parameters now come from the model, not spreadsheets.' }
    P = @{ n = 'Sim runs pinned to a baseline'; f = '{v} of {total}'; dir = 'up'; t = 'total'; p = '{v} of {total} sim runs this sprint name the exact baseline that fed them.' }
    Q = @{ n = 'Uncovered zone crossings'; f = '{v}'; dir = 'down'; t = 0; p = 'There are {v} uncovered zone crossings across {total} interfaces.' }
    R = @{ n = 'Unmitigated threats'; f = '{v} of {total}'; dir = 'down'; t = 0; p = '{v} of {total} recorded threats lack a traced mitigation.' }
    S = @{ n = 'Reproducible baselines'; f = '{v} of {total}'; dir = 'up'; t = 'total'; p = '{v} of {total} tagged baselines rebuild identically.' }
    T = @{ n = 'Drift, model vs. documents'; f = '{v}'; dir = 'down'; t = 0; p = 'Drift between the model and the ICDs is {v} lines. Legacy documents show {legacy} discrepancies.' }
    U = @{ n = 'Merges per sprint'; f = '{v}'; dir = 'info'; p = '{v} model changes merged this sprint, all gated, against {prev} last sprint.' }
    V = @{ n = 'Change failure rate'; f = '{v}%'; dir = 'down'; t = 15; p = '{v}% of merges needed a fix-forward, against a target of under {target}%.' }
    W = @{ n = 'Time to restore'; f = '{v} h'; dir = 'down'; t = 4; p = 'A broken gate was restored in {v} hours.' }
    X = @{ n = 'Done %'; f = '{v}%'; dir = 'up'; t = 80; p = 'This sprint, {v}% of committed items are done.' }
    Y = @{ n = 'Blocked days'; f = '{v}'; dir = 'down'; t = 3; p = 'There were {v} blocked days this sprint, mostly waiting on {blocker}.' }
    Z = @{ n = 'Active contributors'; f = '{v} of {total}'; dir = 'up'; t = 'total'; p = '{v} of {total} engineers merged a model change this sprint.' }
}
function DVars($dash, [string]$L) {
    $d = @{}; $src = JGet (JGet $dash 'm') $L
    if ($null -ne $src) { for ($i = 0; $i -lt $src.K.Count; $i++) { $d[$src.K[$i]] = $src.V[$i] } }
    if ($null -ne $d['v'] -and $null -ne $d['prev'] -and (IsNumeric $d['v']) -and (IsNumeric $d['prev'])) { $d['delta'] = $d['v'] - $d['prev'] }
    $df = $script:DEF[$L]
    if ($null -ne $df.t -and $df.t -isnot [string]) { $d['target'] = $df.t }
    return $d
}
function FmtN($x) { if (IsNumeric $x) { if (IsInt $x) { return Commify $x }; return Commify (PyStr $x) }; return [string]$x }
function DFill([string]$t, $d) {
    $o = ''; $at = 0
    foreach ($m in [regex]::Matches($t, '\{(\w+)\}')) {
        $x = $d[$m.Groups[1].Value]; $v = '[N]'; if ($null -ne $x -and [string]$x -ne '') { $v = FmtN $x }
        $o += $t.Substring($at, $m.Index - $at) + $v; $at = $m.Index + $m.Length
    }
    return $o + $t.Substring($at)
}
function DStatus($dash, [string]$L) {
    $df = $script:DEF[$L]; $d = DVars $dash $L
    if ($null -eq $d['v']) { return @('act', 'no data') }
    if ($df.dir -eq 'info') { return @('info', 'tracking') }
    if ($df.dir -eq 'zero') { if ($d[$df.key] -eq 0 -and $null -ne $d[$df.key]) { return @('ok', 'on target') }; return @('act', 'act') }
    $val = $d['v']; if ($df.sum) { $s = $d[$df.sum]; if ($null -eq $s) { $s = 0 }; $val = $val + $s }
    $t = $df.t; if ($t -is [string]) { $t = $d['total'] }
    if ($null -eq $t) { return @('info', 'tracking') }
    if ($df.dir -eq 'up') { $good = $val -ge $t } else { $good = $val -le $t }
    if ($good) { return @('ok', 'on target') }
    if ($null -ne $d['prev']) { if ($df.dir -eq 'up') { $imp = $val -gt $d['prev'] } else { $imp = $val -lt $d['prev'] }; if ($imp) { return @('watch', 'improving') } }
    return @('act', 'act')
}
function TargetText($dash, [string]$L) {
    $df = $script:DEF[$L]
    if ($df.dir -eq 'info') { return 'tracking' }
    if ($df.dir -eq 'zero') { return "$($df.key) = 0" }
    $t = $df.t; if ($t -is [string]) { $t = (DVars $dash $L)['total']; if ($null -eq $t) { return 'all' } }
    if ($df.dir -eq 'up') { return ">= $(FmtN $t)" }
    return "<= $(FmtN $t)"
}
function XEsc([string]$s) { return $s.Replace('&', '&amp;').Replace('<', '&lt;').Replace('>', '&gt;').Replace('"', '&quot;') }
function XCell($v, [string]$style) {
    $st = ''; if ($style) { $st = " ss:StyleID=`"$style`"" }
    if ($null -eq $v -or [string]$v -eq '') { return "<Cell$st/>" }
    if (IsNumeric $v) { return "<Cell$st><Data ss:Type=`"Number`">$(PyStr $v)</Data></Cell>" }
    return "<Cell$st><Data ss:Type=`"String`">$(XEsc ([string]$v))</Data></Cell>"
}
function XRow($cells, [string]$style) { return '<Row>' + (@(foreach ($c in $cells) { if ($c -is [hashtable] -and $c.ContainsKey('XS')) { XCell $c.v $c.XS } else { XCell $c $style } }) -join '') + "</Row>`n" }
function XSheet([string]$name, $hdr, $rows, [int]$headerRow, [string]$pre, $widths) {
    $ncol = $hdr.Count; $last = $headerRow + @($rows).Count
    $o = "<Worksheet ss:Name=`"$name`">`n"
    $o += "<Names><NamedRange ss:Name=`"_FilterDatabase`" ss:RefersTo=`"='$name'!R${headerRow}C1:R${last}C$ncol`" ss:Hidden=`"1`"/></Names>`n"
    $o += '<Table>' + (@(foreach ($w in $widths) { "<Column ss:Width=`"$w`"/>" }) -join '') + "`n"
    if ($pre) { $o += $pre }
    $o += XRow $hdr 'h'
    foreach ($r in $rows) { $o += XRow $r $null }
    $o += "</Table>`n<WorksheetOptions xmlns=`"urn:schemas-microsoft-com:office:excel`">"
    $o += "<FreezePanes/><FrozenNoSplit/><SplitHorizontal>$headerRow</SplitHorizontal><TopRowBottomPane>$headerRow</TopRowBottomPane><ActivePane>2</ActivePane></WorksheetOptions>`n"
    $o += "<AutoFilter x:Range=`"R${headerRow}C1:R${last}C$ncol`" xmlns=`"urn:schemas-microsoft-com:office:excel`"/>`n</Worksheet>`n"
    return $o
}
function CellValue($d, [string]$L) {                   # a number where the cell is one number, else the table's text
    $v = JGet $d 'v'; if ($L -eq 'T') { $v = JGet $d 'legacy' }
    if ($null -eq $v) { return $null }
    if ('EPQRS'.Contains($L)) { return Cell $L $d 2 2 }
    if (IsNumeric $v) { return $v }
    return PyStr $v
}
function DashWorkbook($cfg, $hist, $weeks, $dash, $sw) {
    $o = "<?xml version=`"1.0`" encoding=`"UTF-8`"?>`n<?mso-application progid=`"Excel.Sheet`"?>`n"
    $o += "<Workbook xmlns=`"urn:schemas-microsoft-com:office:spreadsheet`" xmlns:o=`"urn:schemas-microsoft-com:office:office`" xmlns:x=`"urn:schemas-microsoft-com:office:excel`" xmlns:ss=`"urn:schemas-microsoft-com:office:spreadsheet`">`n"
    $o += '<Styles><Style ss:ID="Default" ss:Name="Normal"><Font ss:FontName="Calibri" ss:Size="11"/></Style>' +
    '<Style ss:ID="h"><Font ss:FontName="Calibri" ss:Size="11" ss:Bold="1"/><Interior ss:Color="#D9E1F2" ss:Pattern="Solid"/><Borders><Border ss:Position="Bottom" ss:LineStyle="Continuous" ss:Weight="1"/></Borders></Style>' +
    '<Style ss:ID="t"><Font ss:FontName="Calibri" ss:Size="14" ss:Bold="1"/></Style>' +
    '<Style ss:ID="ok"><Font ss:FontName="Calibri" ss:Size="11" ss:Bold="1" ss:Color="#2E7D4F"/><Interior ss:Color="#E3F1E8" ss:Pattern="Solid"/></Style>' +
    '<Style ss:ID="watch"><Font ss:FontName="Calibri" ss:Size="11" ss:Bold="1" ss:Color="#A86A12"/><Interior ss:Color="#FBF0DC" ss:Pattern="Solid"/></Style>' +
    '<Style ss:ID="act"><Font ss:FontName="Calibri" ss:Size="11" ss:Bold="1" ss:Color="#B03A2E"/><Interior ss:Color="#F8E1DE" ss:Pattern="Solid"/></Style>' +
    "<Style ss:ID=`"info`"><Font ss:FontName=`"Calibri`" ss:Size=`"11`" ss:Bold=`"1`" ss:Color=`"#3C5A86`"/><Interior ss:Color=`"#E4EAF4`" ss:Pattern=`"Solid`"/></Style></Styles>`n"
    $pre = XRow @("Status metrics: $(JGet $dash 'sprint'), $(JGet $dash 'baseline'), as of $(JGet $dash 'date')") 't'
    $pre += "<Row/>`n"
    $rows = @()
    foreach ($sec in $script:SECTIONS) {
        foreach ($ch in $sec[1].ToCharArray()) {
            $L = [string]$ch; $df = $script:DEF[$L]; $d = DVars $dash $L; $st = DStatus $dash $L
            $h = JGet (JGet (JGet $dash 'm') $L) 'hist'; $trend = ''; if ($null -ne $h) { $trend = (@($h.V | ForEach-Object { PyStr $_ }) -join ' ') }
            $latest = $d['v']; if ($null -ne $latest -and -not ($df.f -eq '{v}' -or $df.f -eq '{v}%' -or $df.f -eq '{v} h' -or $df.f -eq '{v} min' -or $df.f -eq '{v} d')) { $latest = DFill $df.f $d }
            $rows += , @($sec[0], $L, $df.n, $latest, $d['prev'], (TargetText $dash $L), @{ XS = $st[0]; v = $st[1] }, $trend, (DFill $df.p $d))
        }
    }
    $o += XSheet 'Dashboard' @('Section', 'Metric', 'Name', 'Latest', 'Last week', 'Target', 'Status', 'Weekly trend', 'Statement') $rows 3 $pre @(90, 44, 200, 70, 66, 80, 76, 220, 520)
    $wk = @(foreach ($L in $script:LETTERS) { , (@($L, (MetricName $L $cfg)) + @(foreach ($w in $weeks) { CellValue (JGet (JGet $w 'm') $L) $L })) })
    $o += XSheet 'A-Z by week' (@('', 'Metric') + @(foreach ($w in $weeks) { 'W' + (PyStr (JGet $w 'week')) })) $wk 1 '' (@(30, 230) + @(foreach ($w in $weeks) { 56 }))
    $daily = @(foreach ($e in $hist) { $m = JGet $e 'm'; , (@((JGet $e 'date'), (JGet $e 'week'), (JGet $e 'sprint'), (JGet (JGet $m 'A') 'elements')) + @(foreach ($L in $script:LETTERS) { CellValue (JGet $m $L) $L })) })
    $o += XSheet 'Daily' (@('date', 'week', 'sprint', 'elements') + $script:LETTERS) $daily 1 '' (@(76, 44, 48, 64) + @(foreach ($L in $script:LETTERS) { 52 }))
    return $o + "</Workbook>`n"
}
function DashHtml($cfg, $dash) {
    $col = @{ ok = '#2E7D4F'; watch = '#A86A12'; act = '#B03A2E'; info = '#3C5A86' }
    $bg = @{ ok = '#E3F1E8'; watch = '#FBF0DC'; act = '#F8E1DE'; info = '#E4EAF4' }
    $h = "<!DOCTYPE html>`n<html lang=`"en`"><head><meta charset=`"utf-8`"><title>Status metrics</title></head>`n"
    $h += "<body style=`"font-family:'Segoe UI',Arial,sans-serif;color:#1B2A3A;background:#FFFFFF;margin:16px`">`n"
    $h += "<h1 style=`"font-size:20px;margin:0 0 4px`">Status metrics: $(XEsc (JGet $dash 'sprint'))</h1>`n"
    $h += "<p style=`"margin:0 0 12px;color:#4F6175`">$(XEsc (JGet $dash 'baseline')), as of $(XEsc (JGet $dash 'date'))</p>`n"
    foreach ($sec in $script:SECTIONS) {
        $h += "<h2 style=`"font-size:16px;margin:16px 0 4px;border-bottom:1px solid #A9B6C4`">$($sec[0])</h2>`n"
        $h += "<table style=`"border-collapse:collapse;font-size:14px`">`n"
        foreach ($ch in $sec[1].ToCharArray()) {
            $L = [string]$ch; $df = $script:DEF[$L]; $d = DVars $dash $L; $st = DStatus $dash $L
            $td = 'style="border:1px solid #D5DDE6;padding:3px 8px;vertical-align:top"'
            $h += "<tr><td $td><b>$L</b></td><td $td>$(XEsc $df.n)</td><td $td><b>$(XEsc (DFill $df.f $d))</b></td>"
            $h += "<td $td><span style=`"color:$($col[$st[0]]);background:$($bg[$st[0]]);font-weight:bold;padding:0 4px`">$($st[1])</span></td>"
            $h += "<td $td>target $(XEsc (TargetText $dash $L))</td><td $td>$(XEsc (DFill $df.p $d))</td></tr>`n"
        }
        $h += "</table>`n"
    }
    $sel = JGet $dash 'sel'
    if ($null -ne $sel -and $sel.V.Count) {
        $rr = @(foreach ($L in $script:LETTERS) { if ($sel.V -ccontains $L) { DFill $script:DEF[$L].p (DVars $dash $L) } }) -join ' '
        $h += "<h2 style=`"font-size:16px;margin:16px 0 4px;border-bottom:1px solid #A9B6C4`">Round-robin statement</h2>`n<p>$(XEsc $rr)</p>`n"
    }
    return $h + "</body></html>`n"
}

# ================================================================ CLI (argparse's behaviour: usage on stderr, exit 2)
$script:USAGE = @'
usage: status-metrics.cmd {init,collect,report} ...

collect the 26 status metrics (A-Z) and build the status tables.

  status-metrics.cmd init    --config metrics.json --xmi legacy.xmi --reqif export.reqif
  status-metrics.cmd collect --config metrics.json --as-of YYYY-MM-DD [--history history.jsonl]
  status-metrics.cmd report  --config metrics.json --history history.jsonl --out DIR

init     freezes the denominators (v1 element total, DOORS requirement total).
collect  takes one snapshot as of the end of a day and appends it to the history (JSON lines).
report   writes status-weekly.md (A-Z by week), status-daily.csv and dashboard.json.

Paths in the config are relative to the config file. Collection methods follow Appendix A
of docs/STATUS-METRICS.html.

status-metrics.cmd runs status-metrics.ps1 (same arguments). help, -Help or /? prints this.
PowerShell additions: report -Workbook (or -Xlsx) writes status-dashboard.xml for Excel, -Html writes
status-dashboard.html for Edge or to paste into Teams.
'@
$script:SPEC = @{
    init    = @{ opts = @('config', 'xmi', 'reqif'); req = @('config', 'xmi', 'reqif') }
    collect = @{ opts = @('config', 'as-of', 'history'); req = @('config') }
    report  = @{ opts = @('config', 'history', 'out'); req = @('config', 'history') }
}
function Usage([string]$msg) { Out-Err "usage: status-metrics.cmd {init,collect,report} ...`nstatus-metrics.cmd: error: $msg`n"; return 2 }
function Run($argv) {
    $argv = @($argv)
    if (-not $argv.Count) { return Usage 'the following arguments are required: cmd' }
    if (@('-h', '--help', '-help', 'help', '/?', '-?') -contains [string]$argv[0]) { Out-Text ($script:USAGE.Replace("`r", '') + "`n"); return 0 }
    $cmd = [string]$argv[0]
    if (-not ($cmd -ceq 'init' -or $cmd -ceq 'collect' -or $cmd -ceq 'report')) { return Usage "argument cmd: invalid choice: '$cmd' (choose from 'init', 'collect', 'report')" }
    $cs = $script:SPEC[$cmd]
    $a = @{}; $i = 1
    while ($i -lt $argv.Count) {
        $o = [string]$argv[$i]; $i++
        if (@('-h', '--help', '-help', 'help', '/?', '-?') -contains $o) { Out-Text ("usage: status-metrics.cmd $cmd " + (@($cs.opts | ForEach-Object { "--$_ $($_.ToUpper())" }) -join ' ') + "`n"); return 0 }
        if ($cmd -eq 'report' -and ($o -eq '-Workbook' -or $o -eq '-Xlsx' -or $o -eq '--workbook' -or $o -eq '--xlsx')) { $a['workbook'] = $true; continue }
        if ($cmd -eq 'report' -and ($o -eq '-Html' -or $o -eq '--html')) { $a['html'] = $true; continue }
        $m = [regex]::Match($o, '^--([\w-]+)(?:=(.*))?$')
        if (-not $m.Success) { return Usage "unrecognized arguments: $o" }
        $k = $m.Groups[1].Value
        $hits = @($cs.opts | Where-Object { $_.StartsWith($k) })
        if ($cs.opts -ccontains $k) { $hits = @($k) }
        if ($hits.Count -ne 1) { return Usage "unrecognized arguments: $o" }
        $v = $null; if ($m.Groups[2].Success) { $v = $m.Groups[2].Value } elseif ($i -lt $argv.Count) { $v = [string]$argv[$i]; $i++ }
        if ($null -eq $v) { return Usage "argument --$($hits[0]): expected one argument" }
        $a[$hits[0]] = $v
    }
    $miss = @($cs.req | Where-Object { -not $a.ContainsKey($_) })
    if ($miss.Count) { return Usage ('the following arguments are required: ' + (@($miss | ForEach-Object { "--$_" }) -join ', ')) }
    if ($cmd -eq 'init') { return CmdInit $a }
    if ($cmd -eq 'collect') { return CmdCollect $a }
    return CmdReport $a
}

# ================================================================ main
if ($args.Count -and $args[0] -ceq '__lib') { return }
try {                                                  # Run's output is the printed lines, then its exit code
    $res = @(Run $args)
    $script:RC = $res[$res.Count - 1]
    for ($i = 0; $i -lt $res.Count - 1; $i++) { Write-Output $res[$i] }
}
catch {                                                # Perl's die: exit $! (2 for a missing file), else 255
    Out-Err ($_.Exception.Message); if ($env:SM_DEBUG) { Out-Err $_.ScriptStackTrace }
    $script:RC = 255; if ($script:ERRNO) { $script:RC = $script:ERRNO }
}
if ($PSCommandPath) { exit $script:RC }
$global:LASTEXITCODE = $script:RC
