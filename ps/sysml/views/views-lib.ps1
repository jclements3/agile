<#
views-lib.ps1 -- shared helpers for the PowerShell ports of tools/sysml/views (dot-sourced by each tool).
Windows PowerShell 5.1, Constrained Language Mode safe, pure ASCII.

What it emulates from Perl, exactly where the output depends on it:
  sprintf %.Nf     exact binary-to-decimal rounding (round half to even on the exact value, "-0.0" kept), as glibc
  "$number"        Perl's %.15g stringification
  sort             stable merge sort; default string order is ordinal (codepoint), as Perl's
  File::Find       DIR/rel/path names (forward slashes), *.sysml (case-sensitive), then sorted
  Getopt::Long     permute, --opt / -opt, --opt=value, unique abbreviations, ignore case, '--'
  STDOUT/STDERR    stdout buffered until VFlush (as a piped Perl's), stderr immediate
#>

# ================================================================ output
$script:VOB = @{}; $script:VON = 0
function P([string]$s) { $script:VOB[$script:VON] = $s; $script:VON++ }                 # print (text with its own "\n")
function PL([string]$s) { P ($s + "`n") }                                                # print a line
$script:EBUF = $null                                            # set to @{} by VBufferStderr: stderr held until VFlush
function VBufferStderr { $script:EBUF = @{}; $script:EBN = 0 }   # Perl with binmode STDERR ':encoding(UTF-8)': stderr is buffered too
function PErr([string]$s) {
    if ($s.EndsWith("`n")) { $s = $s.Substring(0, $s.Length - 1) }
    foreach ($l in ($s -split "`n")) { if ($null -ne $script:EBUF) { $script:EBUF[$script:EBN] = $l; $script:EBN++ } else { Write-Host $l } }
}
function VExit([int]$code) { VFlush; exit $code }
function VFlushErr { if ($null -ne $script:EBUF) { for ($i = 0; $i -lt $script:EBN; $i++) { Write-Host $script:EBUF[$i] }; $script:EBUF = @{}; $script:EBN = 0 } }   # Perl flushes before it starts a child               # stdout, then any buffered stderr, as Perl flushes them at exit
function VFlush {
    $text = (@(for ($i = 0; $i -lt $script:VON; $i++) { $script:VOB[$i] })) -join ''
    $script:VOB = @{}; $script:VON = 0
    if ($text -ne '') {
        if ($text.EndsWith("`n")) { $text = $text.Substring(0, $text.Length - 1) }
        foreach ($l in ($text -split "`n")) { Write-Output $l }
    }
    if ($null -ne $script:EBUF) { for ($i = 0; $i -lt $script:EBN; $i++) { Write-Host $script:EBUF[$i] }; $script:EBUF = @{}; $script:EBN = 0 }
}

# ================================================================ text files
function VUtf8([string]$s) {                                    # string -> UTF-8 bytes
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
function IsNullDev([string]$path) { $path -ceq '/dev/null' -or $path -eq 'nul' -or $path -eq 'NUL' }
function VWrite([string]$path, [string]$text) {                 # UTF-8 without BOM, line ends as given (Perl's '>:encoding(UTF-8)')
    if (IsNullDev $path) { return $true }
    try {
        if ($text -cmatch '^[\x00-\x7F]*$') { Set-Content -LiteralPath $path -Value $text -Encoding ASCII -NoNewline -ErrorAction Stop }
        else { Set-Content -LiteralPath $path -Value (VUtf8 $text) -Encoding Byte -ErrorAction Stop }
        return $true
    } catch { return $false }
}
function VRead([string]$path) {                                 # Perl '<:encoding(UTF-8)' then slurp: CRs and a BOM are kept
    $t = Get-Content -LiteralPath $path -Raw -Encoding UTF8
    if ($null -eq $t) { $t = '' }
    $b = @(Get-Content -LiteralPath $path -Encoding Byte -TotalCount 3)
    if ($b.Count -ge 3 -and $b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF) { $t = [string][char]0xFEFF + $t }
    $t
}
function IsDir([string]$p) { $p -ne '' -and (Test-Path -LiteralPath $p -PathType Container) }
function IsFile([string]$p) { $p -ne '' -and (Test-Path -LiteralPath $p -PathType Leaf) }
function FindSysml([string]$dir) {                             # File::Find names: DIR/rel/x.sysml
    $base = (Resolve-Path -LiteralPath $dir).ProviderPath
    $pre = if ($dir.EndsWith('/') -or $dir.EndsWith('\')) { $dir } else { $dir + '/' }
    @(Get-ChildItem -LiteralPath $base -Recurse -File -Force -ErrorAction SilentlyContinue | Where-Object { $_.Name -cmatch '\.sysml$' } | ForEach-Object {
        $rel = $_.FullName.Substring($base.TrimEnd('\').Length + 1).Replace('\', '/')
        $pre + $rel
    })
}
function CollectFiles($items, [string]$tool) {                 # dirs (recursive) and files, sorted; a missing one: message + exit 2
    $f = @()
    foreach ($a in @($items)) {
        if (IsDir $a) { $f += @(FindSysml $a) }
        elseif (IsFile $a) { $f += , $a }
        else { PErr "${tool}: ${a}: no such file or directory"; VExit 2 }
    }
    SortStr $f
}

# ================================================================ numbers (Perl's formatting)
$script:POW10 = @([decimal]1, [decimal]10, [decimal]100, [decimal]1000, [decimal]10000, [decimal]100000, [decimal]1000000, [decimal]10000000)
function Abs($x) { if ($x -lt 0) { -$x } else { $x } }
function Trunc($x) {                                            # Perl int(): toward zero
    $d = [double]$x
    $t = [long]$d
    if ($d -ge 0) { if ($t -gt $d) { $t-- } } else { if ($t -lt $d) { $t++ } }
    if ($t -ge -2147483648 -and $t -le 2147483647) { return [int]$t }    # an [int]: hashtable keys 0 and [long]0 differ
    $t
}
function F($x, [int]$p) {                                       # sprintf "%.{p}f", exact
    $d = [double]$x
    $neg = $d -lt 0
    if ($d -eq 0) { $neg = (1.0 / $d) -lt 0 }
    $a = if ($neg) { -$d } else { $d }
    if ($a -ge 4e18) { $q = [decimal]$a * $script:POW10[$p] }    # whole numbers this large: no fraction left
    else {
        $k = 0; $y = $a
        while ($k -le 90 -and $y -ne [double][long]$y) { $y = $y * 2; $k++ }
        if ($k -gt 90) { $q = [decimal]0 }
        else {
            $num = [decimal][long]$y * $script:POW10[$p]
            $den = [decimal]1; for ($i = 0; $i -lt $k; $i++) { $den = $den * 2 }
            $q = [decimal]::Floor($num / $den)
            $r = $num - $q * $den
            if ($r -lt 0) { $q = $q - 1; $r = $r + $den }
            elseif ($r -ge $den) { $q = $q + 1; $r = $r - $den }
            $twice = $r * 2
            if ($twice -gt $den -or ($twice -eq $den -and ($q % 2) -eq 1)) { $q = $q + 1 }
        }
    }
    $s = ([decimal]::Floor($q)).ToString()
    if ($p -gt 0) {
        while ($s.Length -le $p) { $s = '0' + $s }
        $s = $s.Substring(0, $s.Length - $p) + '.' + $s.Substring($s.Length - $p)
    }
    if ($neg) { '-' + $s } else { $s }
}
function N($x) {                                                # Perl stringification of a number (%.15g)
    if ($x -is [string]) { return $x }
    if ($x -is [int] -or $x -is [long]) { return [string]$x }
    $d = [double]$x
    if ($d -eq [double][long]$d -and (Abs $d) -lt 1e15) { return [string][long]$d }
    ("$d" -creplace 'E', 'e')
}
function D($x) { [string](Trunc $x) }                          # %d

# ================================================================ strings, sorting
function PadR([string]$s, [int]$w) { if ($s.Length -lt $w) { $s + (' ' * ($w - $s.Length)) } else { $s } }
function PadL([string]$s, [int]$w) { if ($s.Length -lt $w) { (' ' * ($w - $s.Length)) + $s } else { $s } }
function Cmp([string]$a, [string]$b) { $c = [string]::CompareOrdinal($a, $b); if ($c -lt 0) { -1 } elseif ($c -gt 0) { 1 } else { 0 } }
function NCmp($a, $b) { if ($a -lt $b) { -1 } elseif ($a -gt $b) { 1 } else { 0 } }
function SortBy($items, [scriptblock]$cmp) {                    # stable merge sort; $cmp ($x, $y) -> -1/0/1
    $a = @($items); $n = $a.Count
    if ($n -lt 2) { return , $a }
    $w = 1
    while ($w -lt $n) {
        $out = New-Object object[] $n; $k = 0
        for ($lo = 0; $lo -lt $n; $lo += 2 * $w) {
            $mid = $lo + $w; if ($mid -gt $n) { $mid = $n }
            $hi = $lo + 2 * $w; if ($hi -gt $n) { $hi = $n }
            $i = $lo; $j = $mid
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
function SortNum($items) { SortBy $items { param($x, $y) NCmp $x $y } }
function MaxNum($items) { $m = $null; foreach ($x in @($items)) { if ($null -eq $m -or $x -gt $m) { $m = $x } }; $m }
function MinNum($items) { $m = $null; foreach ($x in @($items)) { if ($null -eq $m -or $x -lt $m) { $m = $x } }; $m }
function UniqStr($items) { $seen = NewH; @(foreach ($x in @($items)) { if (-not $seen.ContainsKey($x)) { $seen[$x] = 1; $x } }) }
function SplitKeep([string]$s, [string]$re) {                   # Perl split: trailing empty fields dropped
    $p = [regex]::Split($s, $re); $n = $p.Count
    while ($n -gt 0 -and $p[$n - 1] -eq '') { $n-- }
    , @(for ($i = 0; $i -lt $n; $i++) { $p[$i] })
}
function SplitN([string]$s, [string]$sep, [int]$n) { $i = $s.IndexOf($sep); if ($n -le 1 -or $i -lt 0) { , @($s) } else { , @($s.Substring(0, $i), $s.Substring($i + $sep.Length)) } }
function NlCount([string]$t) { $t.Length - $t.Replace("`n", '').Length }
function Ch([int]$c) { [string][char]$c }
$script:LAQUO = Ch 0xAB; $script:RAQUO = Ch 0xBB; $script:ELLIP = Ch 0x2026
function Esc([string]$s) { $s.Replace('&', '&amp;').Replace('<', '&lt;').Replace('>', '&gt;').Replace('"', '&quot;') }
function UcFirst([string]$s) { if ($s.Length) { $s.Substring(0, 1).ToUpper() + $s.Substring(1) } else { $s } }
function JoinS($sep, $items) { (@($items) | ForEach-Object { [string]$_ }) -join $sep }

# ================================================================ hashes, records
function NewH { , [hashtable]::new([System.StringComparer]::Ordinal) }
$script:VID = 0
function Rec([hashtable]$h) {                                   # a record with an identity (Perl's hash refs as keys)
    $r = NewH
    foreach ($k in $h.Keys) { $r[$k] = $h[$k] }
    $script:VID++; $r['_id'] = $script:VID
    , $r
}
function CopyRec($h, [hashtable]$over) {                        # { %$h, k => v }: a new identity
    $r = NewH
    foreach ($k in $h.Keys) { $r[$k] = $h[$k] }
    foreach ($k in $over.Keys) { $r[$k] = $over[$k] }
    $script:VID++; $r['_id'] = $script:VID
    , $r
}
function Id($o) { if ($null -eq $o) { '' } else { [string]$o['_id'] } }
function Dflt($a, $b) { if ($null -ne $a) { $a } else { $b } }   # $a // $b
function Arr($a) { if ($null -eq $a) { , @() } else { , @($a) } }
function Truthy($v) {                                           # Perl truth
    if ($null -eq $v) { return $false }
    if ($v -is [string]) { return ($v -ne '' -and $v -ne '0') }
    if ($v -is [bool]) { return $v }
    if ($v -is [array]) { return $v.Count -gt 0 }
    if ($v -is [hashtable]) { return $true }
    return ($v -ne 0)
}

# ================================================================ regexes
$script:RXC = NewH
function Rx([string]$p, [string]$o = '') {                      # cached regex; o: m, s, i
    $k = "$o|$p"
    $r = $script:RXC[$k]
    if ($null -eq $r) {
        $opts = [System.Text.RegularExpressions.RegexOptions]::None
        if ($o.Contains('m')) { $opts = $opts -bor [System.Text.RegularExpressions.RegexOptions]::Multiline }
        if ($o.Contains('s')) { $opts = $opts -bor [System.Text.RegularExpressions.RegexOptions]::Singleline }
        if ($o.Contains('i')) { $opts = $opts -bor [System.Text.RegularExpressions.RegexOptions]::IgnoreCase }
        $r = [regex]::new($p, $opts); $script:RXC[$k] = $r
    }
    $r
}
function M([string]$t, [string]$p, [string]$o = '') { (Rx $p $o).Match($t) }
function MAt([string]$t, [string]$p, [int]$at, [string]$o = '') { (Rx $p $o).Match($t, $at) }
function MS([string]$t, [string]$p, [string]$o = '') { (Rx $p $o).Matches($t) }
function T([string]$t, [string]$p, [string]$o = '') { (Rx $p $o).IsMatch($t) }
function Sub([string]$t, [string]$p, [string]$rep, [string]$o = '') { (Rx $p $o).Replace($t, $rep, 1) }   # s/// (rep in .NET syntax)
function GSub([string]$t, [string]$p, [string]$rep, [string]$o = '') { (Rx $p $o).Replace($t, $rep) }     # s///g
function G($m, [int]$i) { if ($m.Groups[$i].Success) { $m.Groups[$i].Value } else { $null } }

$script:NAMERX = "(?:[A-Za-z_]\w*|'(?:[^'\\]|\\.)*')"
$script:REFRX = "$($script:NAMERX)(?:\s*(?:::|\.)\s*$($script:NAMERX))*"
function Unq([string]$n) {
    $m = M $n "^'(.*)'$" 's'
    if (-not $m.Success) { return $n }
    GSub $m.Groups[1].Value '\\(.)' '$1' 's'
}
function Segs([string]$r) {                                     # names of a qualified reference (:: or .)
    $out = @(); $pos = 0
    $rx = Rx ("\G\s*(" + $script:NAMERX + ")\s*(?:::|\.)?")
    while ($pos -le $r.Length) {
        $m = $rx.Match($r, $pos)
        if (-not $m.Success -or $m.Length -eq 0) { break }
        $out += , (Unq $m.Groups[1].Value); $pos = $m.Index + $m.Length
    }
    , $out
}
function Sval([string]$v) { $m = M $v '^"((?:[^"\\]|\\.)*)"$'; if ($m.Success) { GSub $m.Groups[1].Value '\\(.)' '$1' } else { $v } }
function Squash([string]$s) { $s = GSub $s '\s+' ' '; GSub $s '^ | $' '' }   # s/\s+/ /g; s/^ | $//g
function DocBody([string]$b) { $b = GSub $b '^\s*\*\s?' '' 'm'; Squash $b }

# ================================================================ Getopt::Long (the subset the tools use)
# spec: 'o=s' 'root=s@' 'all' 'depth=i' 'min-text=f'. Returns @{ ok; opts (ordinal hashtable); rest }
function GetOpts($argv, $specs) {
    $def = NewH
    foreach ($s in $specs) {
        $m = M $s '^([\w-]+)(?:=([sif])(@?))?$'
        $def[$m.Groups[1].Value] = @{ type = (G $m 2); list = ($m.Groups[3].Value -eq '@') }
    }
    $opts = NewH; $rest = @(); $ok = $true
    $a = @($argv); $i = 0
    while ($i -lt $a.Count) {
        $x = [string]$a[$i]; $i++
        if ($x -ceq '--') { while ($i -lt $a.Count) { $rest += , [string]$a[$i]; $i++ }; break }
        $m = M $x '^--?([^=]+)(?:=(.*))?$' 's'
        if ($x -eq '-' -or -not $m.Success -or -not $x.StartsWith('-')) { $rest += , $x; continue }
        $nm = $m.Groups[1].Value; $val = G $m 2
        $hit = @($def.Keys | Where-Object { $_ -eq $nm })
        if (-not $hit.Count) { $hit = @($def.Keys | Where-Object { $_.ToLower().StartsWith($nm.ToLower()) }) }
        if ($hit.Count -ne 1) {
            if ($hit.Count -gt 1) { PErr ("Option $nm is ambiguous (" + ((SortStr $hit) -join ', ') + ")") } else { PErr "Unknown option: $($nm.ToLower())" }
            $ok = $false; continue
        }
        $key = $hit[0]; $d = $def[$key]
        if ($null -eq $d.type) {
            if ($null -ne $val) { PErr "Option $key does not take an argument"; $ok = $false; continue }
            $opts[$key] = 1; continue
        }
        if ($null -eq $val) {
            if ($i -ge $a.Count) { PErr "Option $key requires an argument"; $ok = $false; continue }
            $val = [string]$a[$i]; $i++
        }
        if ($d.type -eq 'i' -and $val -cnotmatch '^[-+]?\d+$') { PErr "Value `"$val`" invalid for option $key (number expected)"; $ok = $false; continue }
        if ($d.type -eq 'f' -and $val -cnotmatch '^[-+]?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?$') { PErr "Value `"$val`" invalid for option $key (real number expected)"; $ok = $false; continue }
        $v = if ($d.type -eq 'i') { [int]$val } elseif ($d.type -eq 'f') { [double]$val } else { $val }
        if ($d.list) { if ($null -eq $opts[$key]) { $opts[$key] = @() }; $opts[$key] = @($opts[$key]) + , $v } else { $opts[$key] = $v }
    }
    @{ ok = $ok; opts = $opts; rest = $rest }
}

# ================================================================ dates
function TodayStr { Get-Date -Format 'yyyy-MM-dd' }
