<#
xmi2sysml.ps1 -- SysML v1 XMI (Cameo / MagicDraw export) -> SysML v2 text, one file per top-level package.
A Windows PowerShell 5.1 port of the kit's bin/xmi2sysml.pl (+ lib/Xmi.pm, lib/XmlLite.pm, lib/SysmlText.pm), safe under
Constrained Language Mode (AppLocker/WDAC): no Add-Type, no COM, no .NET methods outside the core types. Same options,
same output files byte for byte, same exit codes.

  xmi2sysml.ps1 --report legacy.xmi                       mapping summary only: in by xmi:type, out, TODO list
  xmi2sysml.ps1 --out model legacy.xmi                    writes model\<segment>\<Package>.sysml (+ the report)
  xmi2sysml.ps1 --out model --layout '{pkg}.sysml' legacy.xmi
  xmi2sysml.ps1 --out model --layout-map layout.map legacy.xmi
  xmi2sysml.ps1 --stdout legacy.xmi                       all files to stdout, each after a "// file: path" line
  xmi2sysml.ps1 --delta old.xmi new.xmi                   two drops of the same model: what changed, carried or manual
  xmi2sysml.ps1 --out model --map map.csv legacy.xmi      also the v1 -> v2 map
  xmi2sysml.ps1 --delta old.xmi new.xmi --impact model [--map map.csv] [--impact-csv impact.csv]

Options: --req-style usage|def, --name PKG, --check (needs tools/sysml/sysml.pl and Perl: reported as not available here).
Exit status: 0 ok, 1 when the self-check finds a problem, 2 on bad usage or unreadable input.
Messages that Perl writes to STDERR are written with Write-Host (the console), so they never mix into redirected output.
#>
$ErrorActionPreference = 'Stop'
$script:NL = "`n"

# ================================================================ output, strings, collections
function Out-Text([string]$t) {                         # Perl's print to STDOUT of text ending in newlines
    if ($null -eq $t -or $t -eq '') { return }
    if ($t.EndsWith("`n")) { $t = $t.Substring(0, $t.Length - 1) }
    foreach ($l in ($t -split "`n")) { Write-Output $l }
}
function Out-Err([string]$t) {                          # Perl's print to STDERR
    if ($null -eq $t -or $t -eq '') { return }
    if ($t.EndsWith("`n")) { $t = $t.Substring(0, $t.Length - 1) }
    foreach ($l in ($t -split "`n")) { Write-Host $l }
}
function NewH { return [hashtable]::new() }              # a case-sensitive hashtable, like a Perl hash
function SortOrd($a) {                                  # Perl's sort: by code unit (byte order for UTF-8 text)
    $c = [string[]]@($a)
    if ($c.Count -lt 2) { return ,$c }
    [Array]::Sort($c, [StringComparer]::Ordinal)
    return ,$c
}
function SortByKey($items, $keys) {                     # items sorted by string keys (ordinal), stable by index
    $it = [object[]]@($items)
    if ($it.Count -lt 2) { return ,$it }
    $k = New-Object string[] $it.Count
    $kk = @($keys)
    for ($i = 0; $i -lt $it.Count; $i++) { $k[$i] = [string]$kk[$i] + "`0" + ('{0:D9}' -f $i) }
    [Array]::Sort($k, [StringComparer]::Ordinal)      # (the keys+items overload does not reorder the items under PowerShell)
    $out = New-Object object[] $it.Count
    for ($i = 0; $i -lt $k.Count; $i++) { $out[$i] = $it[[int]$k[$i].Substring($k[$i].Length - 9)] }
    return ,$out
}
function U8Len([string]$s) {                            # length in UTF-8 bytes (Perl counts bytes)
    if ($null -eq $s) { return 0 }
    if ($s -cmatch '^[\x00-\x7F]*$') { return $s.Length }
    $n = 0
    foreach ($ch in $s.ToCharArray()) {
        $c = [int]$ch
        if ($c -lt 0x80) { $n += 1 } elseif ($c -lt 0x800) { $n += 2 } elseif ($c -ge 0xD800 -and $c -le 0xDFFF) { $n += 2 } else { $n += 3 }
    }
    return $n
}
function PadR([string]$s, [int]$w) { if ($null -eq $s) { $s = '' }; $n = U8Len $s; if ($n -ge $w) { return $s }; return $s + (' ' * ($w - $n)) }
function PadL([string]$s, [int]$w) { if ($null -eq $s) { $s = '' }; $n = U8Len $s; if ($n -ge $w) { return $s }; return (' ' * ($w - $n)) + $s }
function Lc([string]$s) {                               # Perl lc on bytes: ASCII only
    if ($null -eq $s) { return '' }
    if ($s -cmatch '^[\x00-\x7F]*$') { return $s.ToLowerInvariant() }
    return -join @(foreach ($ch in $s.ToCharArray()) { if ($ch -ge 'A' -and $ch -le 'Z' -and [int]$ch -lt 128) { [char]([int]$ch + 32) } else { $ch } })
}
function LcFirst([string]$s) { if ($null -eq $s -or $s -eq '') { return $s }; return (Lc $s.Substring(0, 1)) + $s.Substring(1) }
function NLCount([string]$s) { if ($null -eq $s -or $s -eq '') { return 0 }; return $s.Length - $s.Replace("`n", '').Length }
function Dfl($v, $d) { if ($null -eq $v) { return $d }; return $v }

# Files: read as text (UTF-8, BOM honoured) and write UTF-8 without a BOM, LF line ends, exactly the bytes given.
function Read-TextFile([string]$path) {
    $t = Get-Content -LiteralPath $path -Raw -Encoding UTF8
    if ($null -eq $t) { return '' }
    return $t
}
function Write-TextFile([string]$path, [string]$text) {
    if ($null -eq $text) { $text = '' }
    $dir = Split-Path -Parent $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    if ($text -cmatch '^[\x00-\x7F]*$') { Set-Content -LiteralPath $path -Value $text -Encoding Ascii -NoNewline; return }
    Set-Content -LiteralPath $path -Value $text -Encoding UTF8 -NoNewline
    $b = Get-Content -LiteralPath $path -Encoding Byte -ReadCount 0
    if ($b.Count -gt 3) { Set-Content -LiteralPath $path -Value ([byte[]]$b[3..($b.Count - 1)]) -Encoding Byte }
    else { Set-Content -LiteralPath $path -Value ([byte[]]@()) -Encoding Byte }
}
function Make-Dir([string]$d) { if ($d -and -not (Test-Path -LiteralPath $d)) { New-Item -ItemType Directory -Force -Path $d | Out-Null } }

# Regex replace-all with a scriptblock (CLM refuses MatchEvaluator conversion): $f receives the Match, returns the text
function ReplaceEach([string]$s, $re, [scriptblock]$f) {
    if ($null -eq $s) { return $s }
    $ms = $re.Matches($s)
    if ($ms.Count -eq 0) { return $s }
    $out = ''; $at = 0
    foreach ($m in $ms) { $out += $s.Substring($at, $m.Index - $at) + (& $f $m); $at = $m.Index + $m.Length }
    return $out + $s.Substring($at)
}

# ================================================================ XmlLite: the reader (lib/XmlLite.pm)
$script:XL_PREDEF = [hashtable]::new(); $script:XL_PREDEF['lt'] = '<'; $script:XL_PREDEF['gt'] = '>'; $script:XL_PREDEF['amp'] = '&'; $script:XL_PREDEF['quot'] = '"'; $script:XL_PREDEF['apos'] = "'"
$script:XL_ENTRE = [regex]'&(#[xX][0-9a-fA-F]+|#[0-9]+|[A-Za-z_][A-Za-z0-9_.\-]*);'
function XL-Decode([string]$s, $ent) {
    if ($null -eq $s -or $s.IndexOf('&') -lt 0) { return $s }
    return ReplaceEach $s $script:XL_ENTRE {
        param($m)
        $r = $m.Groups[1].Value
        if ($r -cmatch '^#[xX](.+)') { return [char]::ConvertFromUtf32([int]('0x' + $Matches[1])) }
        if ($r -cmatch '^#([0-9]+)') { return [char]::ConvertFromUtf32([int]$Matches[1]) }
        if ($script:XL_PREDEF.ContainsKey($r)) { return $script:XL_PREDEF[$r] }
        if ($ent -and $ent.ContainsKey($r)) { return $ent[$r] }
        return "&$r;"
    }
}
function XL-Nl([string]$s) { return ($s -creplace "`r`n?", "`n") }

# The file as text: BOM (UTF-8 stripped, UTF-16 decoded), or the declared single-byte encoding (ISO-8859-1 exactly,
# windows-1252 through the system ANSI code page), else UTF-8.
function XL-ReadText([string]$path) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "${path}: No such file or directory`n" }
    $b = Get-Content -LiteralPath $path -Encoding Byte -ReadCount 0
    if ($null -eq $b -or $b.Count -eq 0) { return '' }
    if ($b.Count -ge 2 -and $b[0] -eq 0xFF -and $b[1] -eq 0xFE) { return (Get-Content -LiteralPath $path -Raw -Encoding Unicode) }
    if ($b.Count -ge 2 -and $b[0] -eq 0xFE -and $b[1] -eq 0xFF) { return (Get-Content -LiteralPath $path -Raw -Encoding BigEndianUnicode) }
    if ($b.Count -ge 3 -and $b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF) { return (Read-TextFile $path) }
    $n = [int]$b.Count; if ($n -gt 400) { $n = 400 }
    $head = -join [char[]][byte[]]$b[0..($n - 1)]
    if ($head -cmatch '^<\?xml[ \t\r\n][^>]*?encoding[ \t\r\n]*=[ \t\r\n]*["'']([^"'']+)["'']') {
        $e = Lc $Matches[1]
        if ($e -cnotmatch '^utf-?8$' -and $e -cnotmatch '^utf-?16') {
            if ($e -cmatch '^(iso-?8859-1|latin-?1|iso_8859-1|l1)$') { return (-join [char[]][byte[]]$b) }
            return (Get-Content -LiteralPath $path -Raw -Encoding Default)
        }
    }
    return (Read-TextFile $path)
}

$script:XL_START = [regex]'\G<((?:[^"''<>]|"[^"]*"|''[^'']*'')*)>'
$script:XL_ATTR = [regex]'\G[ \t\r\n]*([^ \t\r\n=]+)[ \t\r\n]*=[ \t\r\n]*(?:"([^"]*)"|''([^'']*)'')'
$script:XL_TRAIL = [regex]'\G[ \t\r\n]*$'
$script:XL_ENTDECL = [regex]'<!ENTITY[ \t\r\n]+([A-Za-z_][A-Za-z0-9_.\-]*)[ \t\r\n]+(?:"([^"]*)"|''([^'']*)'')[ \t\r\n]*>'

# XL-Parse($path, $label) -> root node { n, l, p, u, a (attrs), ao (attr order), k (kids: nodes and strings), line }
function XL-Parse([string]$path, [string]$label) {
    if (-not $label) { $label = $path }
    $t = XL-ReadText $path
    if ($t.Length -gt 0 -and [int]$t[0] -eq 0xFEFF) { $t = $t.Substring(1) }
    return (XL-ParseText $t $label)
}
function XL-ParseText([string]$t, [string]$label) {
    $pos = 0; $line = 1; $len = $t.Length
    $ent = [hashtable]::new()
    $open = @(); $stack = @(); $nsstack = @(); $root = $null
    $text = ''
    $flush = {
        if ($text -eq '') { return }
        $tx = XL-Decode (XL-Nl $text) $ent
        if ($stack.Count -gt 0) {
            if ($tx -cmatch '[^ \t\n\r\f\v]') {
                $top = $stack[$stack.Count - 1]
                $kc = $top.k.Count
                if ($kc -gt 0 -and $top.k[$kc - 1] -is [string]) { $top.k[$kc - 1] = $top.k[$kc - 1] + $tx } else { $top.k += ,$tx }
            }
        }
    }
    while ($true) {
        $lt = $t.IndexOf('<', $pos)
        if ($lt -lt 0) { $text += $t.Substring($pos); $line += NLCount $t.Substring($pos); $pos = $len; break }
        if ($lt -gt $pos) { $seg = $t.Substring($pos, $lt - $pos); $text += $seg; $line += $seg.Length - $seg.Replace("`n", '').Length; $pos = $lt }
        if ($t.Length - $pos -ge 4 -and $t.Substring($pos, 4) -ceq '<!--') {
            $e = $t.IndexOf('-->', $pos + 4); if ($e -lt 0) { throw "${label}:${line}: unterminated comment`n" }
            $line += NLCount $t.Substring($pos, $e + 3 - $pos); $pos = $e + 3; continue
        }
        if ($t.Length - $pos -ge 9 -and $t.Substring($pos, 9) -ceq '<![CDATA[') {
            $e = $t.IndexOf(']]>', $pos + 9); if ($e -lt 0) { throw "${label}:${line}: unterminated CDATA section`n" }
            $c = $t.Substring($pos + 9, $e - $pos - 9)
            $line += NLCount $t.Substring($pos, $e + 3 - $pos); $pos = $e + 3
            if ($text -ne '') { . $flush; $text = '' }
            if ($c -ne '' -and $stack.Count -gt 0) {
                $cx = XL-Nl $c
                if ($cx -cmatch '[^ \t\n\r\f\v]') {
                    $top = $stack[$stack.Count - 1]; $kc = $top.k.Count
                    if ($kc -gt 0 -and $top.k[$kc - 1] -is [string]) { $top.k[$kc - 1] = $top.k[$kc - 1] + $cx } else { $top.k += ,$cx }
                }
            }
            continue
        }
        if ($t.Length - $pos -ge 2 -and $t.Substring($pos, 2) -ceq '<?') {
            $e = $t.IndexOf('?>', $pos + 2); if ($e -lt 0) { throw "${label}:${line}: unterminated processing instruction`n" }
            $line += NLCount $t.Substring($pos, $e + 2 - $pos); $pos = $e + 2; continue
        }
        if ($t.Length - $pos -ge 9 -and $t.Substring($pos, 9) -match '^<!DOCTYPE') {
            $lb = $t.IndexOf('[', $pos); $gt = $t.IndexOf('>', $pos)
            if ($lb -ge 0 -and ($gt -lt 0 -or $lb -lt $gt)) {
                $rb = $t.IndexOf(']', $lb); if ($rb -lt 0) { throw "${label}:${line}: unterminated DOCTYPE`n" }
                $end = $t.IndexOf('>', $rb)
                $subset = $t.Substring($lb + 1, $rb - $lb - 1)
                foreach ($m in $script:XL_ENTDECL.Matches($subset)) {
                    $v = $m.Groups[3].Value; if ($m.Groups[2].Success) { $v = $m.Groups[2].Value }
                    $ent[$m.Groups[1].Value] = XL-Decode $v $null
                }
            } else { $end = $gt }
            if ($end -lt 0) { throw "${label}:${line}: unterminated DOCTYPE`n" }
            $line += NLCount $t.Substring($pos, $end + 1 - $pos); $pos = $end + 1; continue
        }
        if ($t.Length - $pos -ge 2 -and $t.Substring($pos, 2) -ceq '</') {
            $e = $t.IndexOf('>', $pos); if ($e -lt 0) { throw "${label}:${line}: unterminated end tag`n" }
            $name = $t.Substring($pos + 2, $e - $pos - 2) -creplace '[ \t\n\r\f\v]+$', ''
            if ($text -ne '') { . $flush; $text = '' }
            if ($open.Count -eq 0) { throw "${label}:${line}: end tag </$name> with nothing open`n" }
            $topn = $open[$open.Count - 1]
            if ($topn -cne $name) { throw "${label}:${line}: end tag </$name> does not match <$topn>`n" }
            if ($open.Count -eq 1) { $open = @() } else { $open = $open[0..($open.Count - 2)] }
            $line += NLCount $t.Substring($pos, $e + 1 - $pos); $pos = $e + 1
            if ($stack.Count -eq 1) { $stack = @(); $nsstack = @() } else { $stack = $stack[0..($stack.Count - 2)]; $nsstack = $nsstack[0..($nsstack.Count - 2)] }
            continue
        }
        $m = $script:XL_START.Match($t, $pos)
        if (-not $m.Success) { throw "${label}:${line}: unterminated start tag`n" }
        $tag = $m.Groups[1].Value
        $startline = $line
        $mv = $m.Value; $line += $mv.Length - $mv.Replace("`n", '').Length; $pos = $m.Index + $m.Length
        $empty = $false
        if ($tag -cmatch '/[ \t\n\r\f\v]*$') { $empty = $true; $tag = $tag -creplace '/[ \t\n\r\f\v]*$', '' }
        if ($tag -cnotmatch '^([^ \t\n\r\f\v]+)[ \t\n\r\f\v]*([\s\S]*)$') { throw "${label}:${line}: empty tag`n" }
        $name = $Matches[1]; $rest = $Matches[2]
        $a = [hashtable]::new(); $ao = @()
        $ap = 0
        while ($true) {
            $am = $script:XL_ATTR.Match($rest, $ap)
            if (-not $am.Success) { break }
            $an = $am.Groups[1].Value
            $v = $am.Groups[3].Value; if ($am.Groups[2].Success) { $v = $am.Groups[2].Value }
            $v = ($v -creplace "`r`n?", "`n") -creplace "[`n`t]", ' '
            if (-not $a.ContainsKey($an)) { $ao += ,$an }
            if ($v.IndexOf('&') -ge 0) { $v = XL-Decode $v $ent }
            $a[$an] = $v
            $ap = $am.Index + $am.Length
        }
        if (-not $script:XL_TRAIL.Match($rest, $ap).Success) { throw "${label}:${line}: malformed attributes in <$name>`n" }
        if ($text -ne '') { . $flush; $text = '' }
        # namespaces
        $prev = $null; if ($nsstack.Count -gt 0) { $prev = $nsstack[$nsstack.Count - 1] }
        $decl = $false; foreach ($k in $ao) { if ($k -ceq 'xmlns' -or $k.StartsWith('xmlns:')) { $decl = $true; break } }
        if ($decl -or $null -eq $prev) {
            $scope = [hashtable]::new()
            if ($null -ne $prev) { foreach ($k in $prev.Keys) { $scope[$k] = $prev[$k] } }
            foreach ($k in $ao) { if ($k -ceq 'xmlns') { $scope[''] = $a[$k] } elseif ($k -cmatch '^xmlns:(.+)') { $scope[$Matches[1]] = $a[$k] } }
        } else { $scope = $prev }
        $p = ''; $l = $name
        if ($name -cmatch '^([^:]+):(.+)$') { $p = $Matches[1]; $l = $Matches[2] }
        $u = ''; if ($scope.ContainsKey($p) -and $null -ne $scope[$p]) { $u = $scope[$p] }
        $node = @{ n = $name; l = $l; p = $p; u = $u; a = $a; ao = $ao; k = @(); line = $startline }
        if ($stack.Count -gt 0) { $par = $stack[$stack.Count - 1]; $par.k += ,$node } elseif ($null -eq $root) { $root = $node }
        if (-not $empty) { $stack += ,$node; $nsstack += ,$scope; $open += ,$name }
    }
    if ($text -ne '') { . $flush; $text = '' }
    if ($open.Count -gt 0) { throw "${label}:${line}: missing end tag for <$($open[$open.Count - 1])>`n" }
    if ($null -eq $root) { throw "no root element`n" }
    return $root
}
function XL-Kids($n, $local) {
    $out = @(foreach ($c in $n.k) { if ($c -is [hashtable] -and ($null -eq $local -or $c.l -ceq $local)) { $c } })
    return ,$out
}
function XL-Kid($n, [string]$local) { foreach ($c in $n.k) { if ($c -is [hashtable] -and $c.l -ceq $local) { return $c } }; return $null }
function XL-Text($n) { return (-join @(foreach ($c in $n.k) { if ($c -is [hashtable]) { XL-Text $c } else { $c } })) }

# ================================================================ SysmlText (lib/SysmlText.pm)
$script:KEYWORD = [hashtable]::new()
foreach ($k in (-split 'about abstract accept action actor after alias all allocate allocation analysis and as assert assign assume assumption at
    attribute bind binding by calc case comment concern connect connection constant constraint crosses decide def
    default defined dependency derived do doc effect else end entry enum event exhibit exit expose false filter first flow
    for fork frame from guard hastype if implies import in include individual inout interface istype item join language
    library locale loop merge message meta metadata new nonunique not null objective occurrence of or ordered out
    package parallel part perform port private protected public redefines ref references render rendering rep
    require requirement return satisfy send snapshot specializes stakeholder standard state subject subsets
    succession terminate then timeslice to transition trigger true typed until use variant variation verification verify via
    view viewpoint when while xor')) { $script:KEYWORD[$k] = 1 }
function Is-Keyword([string]$s) { if ($script:KEYWORD.ContainsKey($s)) { return 1 }; return 0 }
function SName($s) {
    if ($null -eq $s) { $s = '' }
    $s = [string]$s
    if ($s -cmatch '^[A-Za-z_][A-Za-z0-9_]*$' -and -not $script:KEYWORD.ContainsKey($s)) { return $s }
    $q = $s -creplace '([\\''])', '\$1'
    $q = $q.Replace("`n", '\n').Replace("`t", '\t').Replace("`r", '')
    return "'$q'"
}
function Ident($s) {
    if ($null -eq $s) { $s = '' }
    $s = [string]$s -creplace '[^A-Za-z0-9_]+', '_'
    $s = $s -creplace '^_+|_+$', ''
    if ($s -eq '' -or $s -cmatch '^[0-9]') { $s = "R_$s" }
    if ($script:KEYWORD.ContainsKey($s)) { $s += '_' }
    return $s
}
function SStr($s) {
    if ($null -eq $s) { $s = '' }
    $s = [string]$s -creplace '[ \t\n\r\f\v]*\n[ \t\n\r\f\v]*', ' '
    $s = $s.Replace("`r", '')
    $s = $s -creplace '([\\"])', '\$1'
    return '"' + $s + '"'
}
function DocBody([string]$t) {
    if ($null -eq $t) { $t = '' }
    $t = $t.Replace("`r", '')
    $t = $t.Replace('*/', '* /').Replace('/*', '/ *')
    $t = $t -creplace '(?m)[ \t]+$', ''
    $t = $t -creplace '^[ \t\n\r\f\v]*\n', ''
    $t = $t -creplace '[ \t\n\r\f\v]+$', ''
    return $t
}
function SDoc($text, [string]$ind) {
    if ($null -eq $ind) { $ind = '' }
    $t = DocBody $(if ($null -eq $text) { '' } else { [string]$text })
    if ($t -cnotmatch "`n" -and (U8Len $t) -le 100) { return ,@("${ind}doc /* $t */") }
    $out = @("${ind}doc", "${ind}    /*")
    foreach ($l in ($t -split "`n")) { if ($l -eq '') { $out += "${ind}     *" } else { $out += "${ind}     * $l" } }
    $out += "${ind}     */"
    return ,$out
}
function OneLine($t) { $x = DocBody $(if ($null -eq $t) { '' } else { [string]$t }); return ($x -creplace '[ \t\n\r\f\v]*\n[ \t\n\r\f\v]*', ' ') }
function SRequirement($r, [string]$style, [string]$ind) {
    if (-not $style) { $style = 'def' }; if ($null -eq $ind) { $ind = '' }
    $attrs = @()
    if ($null -ne $r.doorsId -and $r.doorsId -ne '') { $attrs += ,@('doorsId', $r.doorsId) }
    if ($null -ne $r.title -and $r.title -ne '') { $attrs += ,@('title', $r.title) }
    if ($null -ne $r.vm -and $r.vm -ne '') { $attrs += ,@('verificationMethod', $r.vm) }
    foreach ($x in @($r.attrs)) { if ($null -ne $x) { $attrs += ,$x } }
    $extra = @($r.body | Where-Object { $null -ne $_ })
    if ($style -ceq 'usage') {
        $b = @()
        if ($null -ne $r.text -and $r.text -cmatch '[^ \t\n\r\f\v]') { $b += 'doc /* ' + (OneLine $r.text) + ' */' }
        foreach ($x in $attrs) { $b += 'attribute ' + (Ident $x[0]) + ' = ' + (SStr $x[1]) + ';' }
        $l = "${ind}requirement $($r.name) { " + ($b -join ' ') + ' }'
        $l = ([regex]'\{  \}').Replace($l, '{ }', 1)
        $out = @($l); foreach ($e in $extra) { $out += "$ind$e" }
        return ,$out
    }
    $out = @("${ind}requirement def $($r.name) {")
    if ($null -ne $r.text -and $r.text -cmatch '[^ \t\n\r\f\v]') { $out += (SDoc $r.text "$ind    ") }
    foreach ($x in $attrs) { $out += "$ind    attribute " + (Ident $x[0]) + ' = ' + (SStr $x[1]) + ';' }
    foreach ($e in $extra) { $out += "$ind    $e" }
    $out += "$ind}"
    return ,$out
}

$script:LIBPKG = [hashtable]::new()
foreach ($k in (-split 'ScalarValues ISQ SI USCustomaryUnits Quantities MeasurementReferences
    RequirementDerivation Base Links Occurrences Items Parts Ports Actions Requirements VerificationCases
    Connections Interfaces Constraints Calculations Cases UseCases Metaobjects Collections SequenceFunctions
    ControlFunctions BaseFunctions NumericalFunctions Time KerML SysML ISQBase ISQSpaceTime ISQMechanics
    ISQThermodynamics ISQElectromagnetism ShapeItems SpatialItems VerdictKind VerificationMethodKind
    RiskMetadata ModelingMetadata ParametersOfInterestMetadata ImageMetadata TradeStudies AnalysisTooling')) { $script:LIBPKG[$k] = 1 }
$script:LIBNAME = [hashtable]::new()
foreach ($k in (-split 'Real Integer Natural Positive Boolean String Complex Rational Number NumericalValue ScalarValue Anything start done self that')) { $script:LIBNAME[$k] = 1 }
$script:DECLKW = [hashtable]::new()
foreach ($k in (-split 'package part port attribute item action requirement enum connection interface verification constraint calc case use occurrence state allocation analysis metadata view viewpoint concern flow ref in out inout objective subject')) { $script:DECLKW[$k] = 1 }

$script:TK_WS = [regex]'\G[ \t\n\r\f\v]+'
$script:TK_LC = [regex]'\G//[^\n]*'
$script:TK_BC = [regex]'\G/\*'
$script:TK_BCE = [regex]'\G([\s\S]*?)\*/'
$script:TK_STR = [regex]'\G"((?:[^"\\\n]|\\[\s\S])*)"'
$script:TK_NAME = [regex]'\G''((?:[^''\\\n]|\\[\s\S])*)'''
$script:TK_ID = [regex]'\G([A-Za-z_][A-Za-z0-9_]*)'
$script:TK_NUM = [regex]'\G([0-9][0-9.eE+\-]*)'
$script:TK_P = [regex]'\G(::>|:>>|:>|::|\.\.|[{}()\[\];:~,.=#*<>\-+/])'
function STokens([string]$t, [string]$path) {          # -> @(tokens, problems); a token is @(kind, value, line)
    $bad = @(); $line = 1; $pos = 0; $len = $t.Length
    $tok = @(while ($pos -lt $len) {
        $m = $script:TK_WS.Match($t, $pos); if ($m.Success) { $line += NLCount $m.Value; $pos += $m.Length; continue }
        $m = $script:TK_LC.Match($t, $pos); if ($m.Success) { $pos += $m.Length; continue }
        $m = $script:TK_BC.Match($t, $pos)
        if ($m.Success) {
            $pos += $m.Length
            $m2 = $script:TK_BCE.Match($t, $pos)
            if ($m2.Success) { $line += NLCount $m2.Groups[1].Value; $pos += $m2.Length } else { $bad += "${path}:${line}: unterminated comment"; break }
            continue
        }
        $m = $script:TK_STR.Match($t, $pos); if ($m.Success) { ,@('str', $m.Groups[1].Value, $line); $pos += $m.Length; continue }
        if ($t[$pos] -ceq '"') { $bad += "${path}:${line}: unterminated string"; break }
        $m = $script:TK_NAME.Match($t, $pos)
        if ($m.Success) { $v = $m.Groups[1].Value -creplace '\\([\s\S])', '$1'; ,@('name', $v, $line); $pos += $m.Length; continue }
        if ($t[$pos] -ceq "'") { $bad += "${path}:${line}: unterminated name"; break }
        $m = $script:TK_ID.Match($t, $pos)
        if ($m.Success) { $v = $m.Groups[1].Value; if ($script:KEYWORD.ContainsKey($v)) { ,@('kw', $v, $line) } else { ,@('name', $v, $line) }; $pos += $m.Length; continue }
        $m = $script:TK_NUM.Match($t, $pos); if ($m.Success) { ,@('num', $m.Groups[1].Value, $line); $pos += $m.Length; continue }
        $m = $script:TK_P.Match($t, $pos); if ($m.Success) { ,@('p', $m.Groups[1].Value, $line); $pos += $m.Length; continue }
        $ch = [string]$t[$pos]
        if ([int]$t[$pos] -ge 0xD800 -and [int]$t[$pos] -le 0xDBFF -and $pos + 1 -lt $len) { $ch = $t.Substring($pos, 2); $pos++ }
        $bad += "${path}:${line}: unexpected character '$ch'"; $pos++
    })
    return ,@($tok, $bad)
}
function SCheck($files) {                               # { path => text } -> problems "path:line: message"
    $declared = [hashtable]::new(); $refs = @(); $bad = @()
    foreach ($path in (SortOrd $files.Keys)) {
        $r = STokens $files[$path] $path
        $tok = $r[0]; $bad += @($r[1])
        $n = $tok.Count
        $stack = @()
        $close = @{ ')' = '('; ']' = '['; '}' = '{' }
        foreach ($k in $tok) {
            if ($k[0] -cne 'p') { continue }
            if ($k[1] -cmatch '^[(\[{]$') { $stack += ,$k }
            elseif ($k[1] -ceq ')' -or $k[1] -ceq ']' -or $k[1] -ceq '}') {
                if ($stack.Count -eq 0) { $bad += "${path}:$($k[2]): unbalanced '$($k[1])'"; continue }
                $o = $stack[$stack.Count - 1]
                if ($stack.Count -eq 1) { $stack = @() } else { $stack = $stack[0..($stack.Count - 2)] }
                if ($o[1] -cne $close[$k[1]]) { $bad += "${path}:$($k[2]): '$($k[1])' closes '$($o[1])' from line $($o[2])" }
            }
        }
        foreach ($o in $stack) { $bad += "${path}:$($o[2]): '$($o[1])' never closed" }
        for ($i = 0; $i -lt $n; $i++) {
            $kind = $tok[$i][0]; $v = $tok[$i][1]; $ln = $tok[$i][2]
            if ($i -gt 0 -and $tok[$i - 1][1] -ceq '#') { continue }
            if ($kind -ceq 'kw' -and $script:DECLKW.ContainsKey($v)) {
                $j = $i + 1
                while ($j -lt $n -and $tok[$j][0] -ceq 'kw' -and $tok[$j][1] -cmatch '^(def|part|item|attribute|action|port|requirement|case|connection|ref)$') { $j++ }
                if ($j -lt $n -and $tok[$j][1] -ceq '<') { $j += 3 }
                if ($j -lt $n -and $tok[$j][0] -ceq 'name') { $declared[$tok[$j][1]] = 1 }
            }
            $refAt = -1
            if ($kind -ceq 'p' -and ($v -ceq ':' -or $v -ceq '::>')) { $refAt = $i + 1; if ($refAt -lt $n -and $tok[$refAt][1] -ceq '~') { $refAt++ } }
            elseif ($kind -ceq 'kw' -and $v -cmatch '^(satisfy|verify|by|connect|to|from|bind|allocate|specializes)$') { $refAt = $i + 1 }
            if ($kind -ceq 'p' -and $v -ceq ':>') {
                $j = $i + 1
                while ($true) {
                    $q = SQn $tok $j
                    if ($null -eq $q[0]) { break }
                    $refs += ,@($q[0], "${path}:$($tok[$j][2])", $null)
                    $nx = $q[1]
                    if (-not ($nx -lt $n -and $tok[$nx][1] -ceq ',')) { break }
                    $j = $nx + 1
                }
                continue
            }
            if ($kind -ceq 'kw' -and $v -ceq 'import') {
                $q = SQn $tok ($i + 1)
                if ($null -ne $q[0]) { $refs += ,@($q[0], "${path}:$ln", 'import') }
                continue
            }
            if ($refAt -ge 0) { $q = SQn $tok $refAt; if ($null -ne $q[0]) { $refs += ,@($q[0], "${path}:$ln", $null) } }
            if ($kind -ceq 'kw' -and $v -ceq 'bind') {
                $j = $i + 1
                while ($j -lt $n -and $tok[$j][1] -cne '=' -and $tok[$j][1] -cne ';') { $j++ }
                if ($j -lt $n -and $tok[$j][1] -ceq '=') { $q = SQn $tok ($j + 1); if ($null -ne $q[0]) { $refs += ,@($q[0], "${path}:$ln", $null) } }
            }
        }
    }
    foreach ($r in $refs) {
        $seg = $r[0]; $where = $r[1]
        $head = $seg[0]
        if ($script:LIBPKG.ContainsKey($head)) { continue }
        if ($seg.Count -eq 1 -and $script:LIBNAME.ContainsKey($head)) { continue }
        $miss = $false; foreach ($x in $seg) { if (-not $declared.ContainsKey($x)) { $miss = $true } }
        if ($miss) { $bad += "${where}: '" + ($seg -join '::') + "' is not declared in these files or the standard library" }
    }
    $seen = [hashtable]::new()
    $out = @(foreach ($b in $bad) { if (-not $seen.ContainsKey($b)) { $seen[$b] = 1; $b } })
    return ,$out
}
function SQn($tok, [int]$i) {                           # a qualified name at $i -> @(segments or $null, next index)
    $n = $tok.Count
    if (-not ($i -lt $n -and $tok[$i][0] -ceq 'name')) { return ,@($null, $i) }
    $seg = @($tok[$i][1]); $i++
    while ($i + 1 -lt $n -and $tok[$i][1] -ceq '::' -and $tok[$i + 1][0] -ceq 'name') { $seg += $tok[$i + 1][1]; $i += 2 }
    return ,@($seg, $i)
}

# ---- layout maps
function Read-LayoutMap([string]$path) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "${path}: No such file or directory`n" }
    $text = Read-TextFile $path
    $map = [hashtable]::new(); $order = @(); $default = $null; $n = 0
    $lines = $text -split "`n"
    if ($text.EndsWith("`n")) { $lines = $lines[0..($lines.Count - 2)] }
    if ($text -eq '') { $lines = @() }
    foreach ($l in $lines) {
        $n++
        $l = $l -creplace "`r$", ''
        $l = $l -creplace '(?:^|[ \t\n\r\f\v])#[\s\S]*', ''
        if ($l -cnotmatch '[^ \t\n\r\f\v]') { continue }
        if ($l -cnotmatch '^[ \t\n\r\f\v]*([\s\S]*?)[ \t\n\r\f\v]*=[ \t\n\r\f\v]*([\s\S]*?)[ \t\n\r\f\v]*$') { throw "${path}:${n}: expected PACKAGE = folder/ or PACKAGE = folder/File.sysml`n" }
        $k = $Matches[1]; $v = $Matches[2]
        $k = $k -creplace "^'([\s\S]*)'$", '$1'; $k = $k -creplace '^"([\s\S]*)"$', '$1'
        if ($k -eq '') { throw "${path}:${n}: no package name before '='`n" }
        if ($v -eq '') { throw "${path}:${n}: no path after '=' for $k`n" }
        if ($v -cmatch '^/|^[A-Za-z]:|(?:^|/)\.\.(?:/|$)|\\') { throw "${path}:${n}: ${v}: give a path relative to the output folder, without '..'`n" }
        if ($v -cnotmatch '/$' -and $v -cnotmatch '\.sysml$') { throw "${path}:${n}: ${v}: a file must end in .sysml (or end the folder with /)`n" }
        if ($k -ceq '*') { if ($v -cnotmatch '/$') { throw "${path}:${n}: '*' must be a folder (end it with /)`n" }; $default = $v; continue }
        if ($map.ContainsKey($k)) { throw "${path}:${n}: $k is mapped twice`n" }
        $map[$k] = $v; $order += $k
    }
    return @{ path = $path; map = $map; default = $default; order = $order }
}
function Layout-Path($lm, [string]$pkg, [string]$pf, [string]$fallback) {   # -> @(path, note or $null)
    if ($null -eq $lm) { return ,@($fallback, $null) }
    if ($lm.map.ContainsKey($pkg)) { $v = $lm.map[$pkg]; if ($v -cmatch '/$') { return ,@("$v$pf.sysml", $null) }; return ,@($v, $null) }
    if ($null -ne $lm.default) { return ,@("$($lm.default)$pf.sysml", "layout map: $pkg is not listed; written to $($lm.default)$pf.sysml (the * default)") }
    return ,@($fallback, "layout map: $pkg is not listed; written to $fallback (the converter's own layout)")
}

# ================================================================ Xmi (lib/Xmi.pm)
$script:IN_SCOPE = @('Class', 'Port', 'Property', 'Connector', 'Activity')
$script:PRIM = [hashtable]::new()
foreach ($kv in @(@('real','ScalarValues::Real'), @('integer','ScalarValues::Integer'), @('boolean','ScalarValues::Boolean'),
    @('string','ScalarValues::String'), @('unlimitednatural','ScalarValues::Natural'), @('natural','ScalarValues::Natural'),
    @('number','ScalarValues::NumericalValue'), @('complex','ScalarValues::Complex'), @('double','ScalarValues::Real'),
    @('float','ScalarValues::Real'), @('int','ScalarValues::Integer'), @('long','ScalarValues::Integer'),
    @('short','ScalarValues::Integer'), @('char','ScalarValues::String'), @('bool','ScalarValues::Boolean'))) { $script:PRIM[$kv[0]] = $kv[1] }
$script:REQ_STEREO = [hashtable]::new()
foreach ($k in (-split 'Requirement extendedRequirement functionalRequirement interfaceRequirement performanceRequirement physicalRequirement designConstraint businessRequirement usabilityRequirement')) { $script:REQ_STEREO[(Lc $k)] = 1 }
$script:KNOWN_STEREO = [hashtable]::new()
foreach ($k in $script:REQ_STEREO.Keys) { $script:KNOWN_STEREO[$k] = 1 }
foreach ($k in (-split 'Block InterfaceBlock ConstraintBlock ValueType FlowPort ProxyPort FullPort FlowProperty Satisfy Verify DeriveReqt Trace Refine Copy Allocate TestCase BindingConnector NestedConnectorEnd Unit QuantityKind ParticipantProperty ConstraintProperty ElementPropertyPath')) { $script:KNOWN_STEREO[(Lc $k)] = 1 }

function PTrue($v) {                                    # Perl truth: undef, '', '0' and 0 are false
    if ($null -eq $v) { return $false }
    if ($v -is [string]) { return ($v -ne '' -and $v -ne '0') }
    if ($v -is [bool]) { return $v }
    if ($v -is [int] -or $v -is [long] -or $v -is [double]) { return ($v -ne 0) }
    return $true
}
function XType($n) {
    $t = $n.a['xmi:type']
    if ($null -eq $t) { foreach ($k in $n.ao) { if ($k -cmatch '^[^:]+:type$') { $t = $n.a[$k]; break } } }
    if ($null -eq $t -and ($n.p -ceq 'uml' -or $n.u -match '/UML\b') -and $n.l -cmatch '^(Model|Package|Profile)$') { $t = $n.n }
    if ($null -eq $t) { return $null }
    return ($t -creplace '^[\s\S]*:', '')
}
function XId($n) {
    if ($null -ne $n.a['xmi:id']) { return $n.a['xmi:id'] }
    foreach ($k in $n.ao) { if ($k -cmatch '^[^:]+:id$') { return $n.a[$k] } }
    return $null
}
function SplitWs($s) { if ($null -eq $s) { return ,@() }; return ,@(foreach ($x in (-split $s)) { if ($x -ne '') { $x } }) }    # Perl split ' '
function IdRefs($n, [string]$what) {
    $ids = @()
    if ($null -ne $n.a[$what]) { $ids += (SplitWs $n.a[$what]) }
    foreach ($c in $n.k) {
        if ($c -isnot [hashtable] -or $c.l -cne $what) { continue }
        $r = $c.a['xmi:idref']; if ($null -eq $r) { $r = $c.a['idref'] }
        if ($null -ne $r) { $ids += $r }
        if ($null -eq $r -and $null -ne $c.a['href']) { $ids += 'href:' + $c.a['href'] }
    }
    return ,$ids
}
function First($a) { $x = @($a); if ($x.Count -gt 0) { return $x[0] }; return $null }

function Xmi-Load([string]$path) {
    $root = XL-Parse $path $path
    $base = $path -creplace '^[\s\S]*[/\\]', ''; $base = $base -creplace '\.[^.]+$', ''
    $m = @{ path = $path; base = $base; root = $root; el = ([hashtable]::new()); order = @(); st = ([hashtable]::new()); apps = @(); ext = 0; parent = ([hashtable]::new()); anon = 0 }
    $content = @()
    if ($root.l -ceq 'XMI') {
        foreach ($c in (XL-Kids $root $null)) {
            if ($c.l -ceq 'Extension' -or $c.l -ceq 'Documentation') { $m.ext++; continue }
            $hasBase = $false; foreach ($k in $c.ao) { if ($k -cmatch '^base_') { $hasBase = $true } }
            if ($hasBase -and $null -eq (XType $c)) { $m.apps += ,$c; continue }
            $content += ,$c
        }
    } else { $content = @(,$root) }
    $m.content = $content
    $orderOut = @(foreach ($c in $content) { Xmi-Walk $m $c $null })
    $m.order = $orderOut
    foreach ($a in $m.apps) {
        foreach ($k in $a.ao) {
            if ($k -cnotmatch '^base_') { continue }
            foreach ($tid in (SplitWs $a.a[$k])) {
                if (-not $m.st.ContainsKey($tid)) { $m.st[$tid] = [hashtable]::new() }
                $m.st[$tid][(Lc $a.l)] = $a
            }
        }
    }
    return $m
}
function Xmi-Walk($m, $n, $parent) {                    # emits the ids in document order
    if ($n.l -ceq 'Extension') { $m.ext++; return }
    $t = XType $n
    $id = $null
    if ($null -ne $t) {
        $id = XId $n
        if ($null -eq $id) { $m.anon++; $id = 'anon_' + $m.anon }
        $n.id = $id; $n.t = $t
        $m.el[$id] = $n
        if ($null -ne $parent) { $m.parent[$id] = $parent }
        $id
    }
    $p2 = $parent; if ($null -ne $id) { $p2 = $id }
    foreach ($c in $n.k) { if ($c -is [hashtable]) { Xmi-Walk $m $c $p2 } }
}
function SAttr($app, [string[]]$names) {
    if ($null -eq $app) { return $null }
    foreach ($nm in $names) {
        $ln = Lc $nm
        foreach ($k in $app.ao) { if ((Lc $k) -ceq $ln) { return $app.a[$k] } }
        foreach ($c in $app.k) { if ($c -is [hashtable] -and (Lc $c.l) -ceq $ln) { return (XL-Text $c) } }
    }
    return $null
}

# ---- convert: the state of one conversion lives in the script:C... variables (Perl's closures over convert()'s lexicals)
$script:LOOSEID = '__loose__'
function C-Has($id, [string]$s) { if ($null -eq $id) { return $null }; $x = $script:Cst[[string]$id]; if ($null -eq $x) { return $null }; return $x[$s.ToLowerInvariant()] }
function C-IsReq($id) { $x = $script:Cst[[string]$id]; if ($null -eq $x) { return $false }; foreach ($k in $x.Keys) { if ($script:REQ_STEREO.ContainsKey($k)) { return $true } }; return $false }
function C-ReqApp($id) { $x = $script:Cst[[string]$id]; if ($null -eq $x) { return $null }; foreach ($k in (SortOrd $x.Keys)) { if ($script:REQ_STEREO.ContainsKey($k)) { return $x[$k] } }; return $null }
function C-LibOf($nmv) {
    if ($null -eq $nmv) { return $null }
    $k = (Lc $nmv) -creplace '^[\s\S]*[#./:]', ''
    return $script:PRIM[$k]
}
function C-NsOwner($id) {
    $p = $script:Cmodel.parent[$id]
    while ($null -ne $p) {
        $pk = $script:Ckind[$p]
        if ($pk -ceq 'package' -and $script:Cel[$p].t -ceq 'Model' -and $null -eq $script:Cmodel.parent[$p]) { return $script:LOOSEID }
        if ($script:NSK.ContainsKey([string]$pk) -and -not ($pk -ceq 'req' -and $script:Ckind[$id] -ceq 'req')) { return $p }
        $p = $script:Cmodel.parent[$p]
    }
    return $script:LOOSEID
}
function C-Assign($id, [string]$want) {
    $o = [string]$script:Cowner[$id]
    if (-not $script:Cused.ContainsKey($o)) { $script:Cused[$o] = [hashtable]::new() }
    $b = $want; $i = 1
    while ($script:Cused[$o].ContainsKey($want)) { $i++; $want = $b + '_' + $i }
    $script:Cused[$o][$want] = 1
    $script:Cnm[$id] = $want
    $script:Ccount[$want] = 1 + [int]$script:Ccount[$want]
}
function C-N($id) { $k = [string]$id; $v = $script:CmemoN[$k]; if ($null -eq $v) { $v = SName $script:Cnm[$id]; $script:CmemoN[$k] = $v }; return $v }
function C-Chain($id) {
    $key = [string]$id
    $memo = $script:CmemoC[$key]
    if ($null -ne $memo) { return ,$memo }
    $c = @($id)
    while ($true) {
        $o = $script:Cowner[$c[0]]
        if ($null -eq $o -or $c[0] -ceq $script:LOOSEID) { break }
        if ($o -ceq $script:LOOSEID -and $script:Ckind[$c[0]] -ceq 'package') { break }
        $c = @($o) + $c
        if ($o -ceq $script:LOOSEID) { break }
    }
    $script:CmemoC[$key] = $c
    return ,$c
}
function C-Qual($id) { $k = [string]$id; $v = $script:CmemoQ[$k]; if ($null -eq $v) { $v = (@(foreach ($x in (C-Chain $id)) { C-N $x })) -join '::'; $script:CmemoQ[$k] = $v }; return $v }
function C-Top($id) { return (C-Chain $id)[0] }
function C-Tag($id, $kind, $q, $lines) {                # mark the first line with the element's id; returns the lines
    $l = @($lines)
    if ($null -eq $id -or $l.Count -eq 0) { return ,$l }
    if (-not $script:Ctagmap.ContainsKey($id)) { $script:Ctagmap[$id] = @{ kind = $kind; q = $q } }
    $l[0] = [char]1 + $id + [char]1 + $l[0]
    return ,$l
}
function C-Ref($ctx, $tid) {
    if ($null -eq $tid -or $null -eq $script:Cnm[$tid] -or $script:Ckind[$tid] -ceq 'libtype') { return $null }
    $o = $script:Cowner[$tid]
    $anc = [hashtable]::new(); foreach ($x in (C-Chain $ctx)) { $anc[$x] = 1 }
    if ($null -ne $o -and $anc.ContainsKey($o)) { return (C-N $tid) }
    if ($script:Ckind[$o] -cne 'package') {
        $d = C-Ref $ctx $o
        if ($null -ne $d) { return $d + '::' + (C-N $tid) }
        return (C-Qual $tid)
    }
    if ($script:Ckind[$o] -ceq 'package' -and $script:Ccount[$script:Cnm[$tid]] -eq 1) {
        $top = C-Top $ctx
        if ($o -cne $script:LOOSEID -or $top -cne $script:LOOSEID) {
            if (-not $script:Cimports.ContainsKey($top)) { $script:Cimports[$top] = [hashtable]::new() }
            $script:Cimports[$top][(C-Qual $o)] = 1
        }
        return (C-N $tid)
    }
    return (C-Qual $tid)
}
function C-TypeRef($ctx, $n) {                          # -> @(type string or $null, target id or $null, comment)
    $tid = First (IdRefs $n 'type')
    if ($null -eq $tid) { return ,@($null, $null, '') }
    if ($tid -cmatch '^href:([\s\S]*)') {
        $h = $Matches[1]; $lib = C-LibOf $h
        if ($lib) { return ,@($lib, $null, '') }
        $script:Cunres[$h] = 1 + [int]$script:Cunres[$h]
        return ,@($null, $null, " // TODO type $h not resolved")
    }
    $t = $script:Cel[$tid]
    if ($null -eq $t) { return ,@($null, $null, " // TODO type $tid not in this file") }
    if ($script:Ckind[$tid] -ceq 'libtype') { return ,@((C-LibOf $t.a['name']), $tid, '') }
    return ,@((C-Ref $ctx $tid), $tid, '')
}
function C-Mult($n) {
    $lo = XL-Kid $n 'lowerValue'; $hi = XL-Kid $n 'upperValue'
    if ($null -eq $lo -and $null -eq $hi) { return '' }
    $l = '1'; if ($null -ne $lo) { $l = [string](Dfl $lo.a['value'] 0) }
    $h = '1'; if ($null -ne $hi) { $h = [string](Dfl $hi.a['value'] 0) }
    if ($h -ceq '-1') { $h = '*' }
    if ($h -ceq '0' -or ($l -ceq '1' -and $h -ceq '1')) { return '' }
    if ($l -ceq $h) { return "[$l]" }
    return "[$l..$h]"
}
function C-Fold($n) { if ($null -ne $n.id -and -not $script:Cstatus[$n.id]) { $script:Cstatus[$n.id] = 'folded' }; foreach ($c in $n.k) { if ($c -is [hashtable]) { C-Fold $c } } }
function C-TodoChild($n) { if ($null -ne $n.id -and -not $script:Cstatus[$n.id]) { $script:Cstatus[$n.id] = 'todo-child' }; foreach ($c in $n.k) { if ($c -is [hashtable]) { C-TodoChild $c } } }
function C-Value($ctx, $n) {
    $d = XL-Kid $n 'defaultValue'
    if ($null -eq $d) { return $null }
    C-Fold $d
    $t = [string]$d.t; $v = $d.a['value']
    if ($t -ceq 'LiteralString') { return (SStr (Dfl $v '')) }
    if ($t -cmatch '^Literal(Integer|Real|UnlimitedNatural)$') { return [string](Dfl $v 0) }
    if ($t -ceq 'LiteralBoolean') { if ($null -ne $v -and $v -ceq 'true') { return 'true' }; return 'false' }
    if ($t -ceq 'InstanceValue') { $i = First (IdRefs $d 'instance'); if ((PTrue $i) -and (PTrue $script:Cnm[$i])) { return (C-Ref $ctx $i) }; return $null }
    return $null
}
function C-Todo($id, [string]$why, [string]$ind) {
    $n = $script:Cel[$id]
    $script:Cstatus[$id] = 'todo'
    $nmv = ''; if ($null -ne $n.a['name']) { $nmv = " '" + $n.a['name'] + "'" }
    $script:Cunmapped += ,@{ id = $id; type = $n.t; name = [string](Dfl $n.a['name'] ''); why = $why }
    foreach ($c in $n.k) { if ($c -is [hashtable]) { C-TodoChild $c } }
    return (C-Tag $id 'todo' $null @("$ind// TODO uml:$($n.t)$nmv (xmi:id $id): $why"))[0]
}
function C-StereoNotes($id, [string]$ind) {
    $x = $script:Cst[[string]$id]; if ($null -eq $x) { return ,@() }
    $l = @()
    foreach ($s in (SortOrd $x.Keys)) {
        if ($script:KNOWN_STEREO.ContainsKey($s)) { continue }
        $app = $x[$s]
        $script:Cstereo_todo[$app.l] = 1 + [int]$script:Cstereo_todo[$app.l]
        $xi = XId $app; if (-not (PTrue $xi)) { $xi = '?' }
        $l += "$ind// TODO stereotype $($app.n) on this element (xmi:id $xi) not converted"
    }
    return ,$l
}
function C-Docs($n, [string]$ind) {
    $l = @()
    foreach ($c in (XL-Kids $n 'ownedComment')) {
        if ($null -ne $c.a['body']) { $b = $c.a['body'] } else { $k = XL-Kid $c 'body'; if ($null -ne $k) { $b = XL-Text $k } else { $b = '' } }
        $q = $null; if ((PTrue $n.id) -and (PTrue $script:Cnm[$n.id])) { $q = C-Qual $n.id }
        $l += (C-Tag $c.id 'doc' $q (SDoc $b $ind))
        if (PTrue $c.id) { $script:Cstatus[$c.id] = 'mapped' }
        $script:Cout['doc'] = 1 + [int]$script:Cout['doc']
    }
    return ,$l
}
function C-Gens($ctx, $n) {
    $g = @()
    foreach ($x in (XL-Kids $n 'generalization')) {
        C-Fold $x
        $gid = First (IdRefs $x 'general')
        if ($null -ne $gid -and $gid -cmatch '^href:([\s\S]*)') { $r = C-LibOf $Matches[1] }
        elseif ($null -ne $gid -and (PTrue $script:Ckind[$gid]) -and $script:Ckind[$gid] -ceq 'libtype') { $r = C-LibOf $script:Cel[$gid].a['name'] }
        else { $r = C-Ref $ctx $gid }
        if ($null -ne $r) { $g += $r }
    }
    if ($g.Count -gt 0) { return ' :> ' + ($g -join ', ') }
    return ''
}
function C-Inc([string]$k) { $script:Cout[$k] = 1 + [int]$script:Cout[$k] }

function C-PropLine($ctx, $id, [string]$ind) {
    $n = $script:Cel[$id]
    foreach ($c in $n.k) { if ($c -is [hashtable]) { C-Fold $c } }
    $tr = C-TypeRef $ctx $n; $ty = $tr[0]; $tid = $tr[1]; $cmt = $tr[2]
    $tk = ''; if ($null -ne $tid) { $tk = [string]$script:Ckind[$tid] }
    $dir = ''
    $fp = C-Has $id 'FlowProperty'
    if ($fp) { $d = SAttr $fp @('direction'); $dir = [string](Dfl $d 'inout') + ' ' }
    if ($tk -cmatch '^(partdef|portdef|constraintdef|usecasedef|verif)$') {
        if ($dir) { $kw = 'item' } elseif ([string]$n.a['aggregation'] -ceq 'composite') { $kw = 'part' } else { $kw = 'ref part' }
    }
    elseif ($tk -ceq 'itemdef') { $kw = 'item' }
    elseif ($tk -ceq 'req') { $kw = 'requirement' }
    elseif ($tk -ceq 'actiondef') { $kw = 'action' }
    else { $kw = 'attribute' }
    if ([string]$n.a['isDerived'] -ceq 'true') { $kw = "derived $kw" }
    $v = C-Value $ctx $n
    if ($kw -cmatch '([A-Za-z0-9_]+(?: part)?)$') { C-Inc $Matches[1] } else { C-Inc $kw }
    $script:Cstatus[$id] = 'mapped'
    $bk = $kw -creplace '^derived ', ''
    $line = "$ind$dir$kw " + (C-N $id)
    if ($null -ne $ty) { $line += " : $ty" }
    $line += (C-Mult $n)
    if ($null -ne $v) { $line += " = $v" }
    $line += ";$cmt"
    return (C-Tag $id $bk ((C-Qual $ctx) + '::' + (C-N $id)) @($line))[0]
}
function C-PortLine($ctx, $id, [string]$ind) {
    $n = $script:Cel[$id]
    foreach ($c in $n.k) { if ($c -is [hashtable]) { C-Fold $c } }
    $tr = C-TypeRef $ctx $n; $ty = $tr[0]; $tid = $tr[1]; $cmt = $tr[2]
    $fp = C-Has $id 'FlowPort'
    $conj = ([string]$n.a['isConjugated'] -ceq 'true') -or ($fp -and ([string](SAttr $fp @('isConjugated')) -ceq 'true'))
    $script:Cstatus[$id] = 'mapped'; C-Inc 'port'
    if ($null -ne $tid) { $tk = [string]$script:Ckind[$tid] } elseif ($null -ne $ty) { $tk = 'lib' } else { $tk = '' }
    $q = (C-Qual $ctx) + '::' + (C-N $id)
    if ($tk -cmatch '^(attrdef|enumdef|lib|itemdef)$') {
        $d = 'inout'; if ($fp) { $dd = SAttr $fp @('direction'); if (PTrue $dd) { $d = $dd } }
        $what = 'attribute'; if ($tk -ceq 'itemdef') { $what = 'item' }
        return (C-Tag $id 'port' $q @("${ind}port " + (C-N $id) + (C-Mult $n) + " { $d $what flowValue : $ty; }$cmt"))[0]
    }
    $note = ''
    if ($tk -ceq 'partdef') { $note = ' // TODO the type is a part def (also used as a part); give the port a port def' }
    $tys = ''; if ($null -ne $ty) { $tys = ' : '; if ($conj) { $tys += '~' }; $tys += $ty }
    return (C-Tag $id 'port' $q @("${ind}port " + (C-N $id) + $tys + (C-Mult $n) + ";$cmt$note"))[0]
}
function C-EndPath($ctx, $e) {
    $role = First (IdRefs $e 'role')
    if ($null -eq $role -or -not (PTrue $script:Cnm[$role])) { return $null }
    $p = @()
    $ne = $null; if (PTrue $e.id) { $sx = $script:Cst[[string]$e.id]; if ($null -ne $sx) { $ne = $sx['nestedconnectorend'] } }
    if ($ne) { foreach ($x in (IdRefs $ne 'propertyPath')) { if (PTrue $script:Cnm[$x]) { $p += (C-N $x) } } }
    else {
        $pw = (IdRefs $e 'partWithPort')
        if ($pw.Count -gt 0) { if (PTrue $script:Cnm[$pw[0]]) { $p += (C-N $pw[0]) } }
    }
    $p += (C-N $role)
    return ($p -join '.')
}
function C-ConnLine($ctx, $id, [string]$ind) {
    $n = $script:Cel[$id]
    $es = (XL-Kids $n 'end')
    $p = @(); $ok = $true
    foreach ($e in $es) { $x = C-EndPath $ctx $e; if ($null -eq $x) { $ok = $false }; $p += ,$x }
    if ($p.Count -ne 2 -or -not $ok) { return (C-Todo $id 'connector without two resolvable ends' $ind) }
    foreach ($c in $n.k) { if ($c -is [hashtable]) { C-Fold $c } }
    $script:Cstatus[$id] = 'mapped'
    if (C-Has $id 'BindingConnector') { C-Inc 'bind'; return (C-Tag $id 'bind' (C-Qual $ctx) @("${ind}bind $($p[0]) = $($p[1]);"))[0] }
    C-Inc 'connection'
    $named = $null -ne $n.a['name'] -and $n.a['name'] -ne ''
    $q = C-Qual $ctx; $lab = ''
    if ($named) { $q += '::' + (C-N $id); $lab = (C-N $id) + ' ' }
    return (C-Tag $id 'connection' $q @("${ind}connection ${lab}connect $($p[0]) to $($p[1]);"))[0]
}
function C-RelLines($ctx, $id, [string]$ind) {
    $n = $script:Cel[$id]
    if ($script:Cverif_rel.ContainsKey($id)) { foreach ($x in $script:Cverif_rel[$id][0]) { if ((PTrue $script:Ckind[$x]) -and $script:Ckind[$x] -ceq 'verif') { return ,@() } } }
    $cs = (IdRefs $n 'client'); $ss = (IdRefs $n 'supplier')
    $bad = @(foreach ($x in ($cs + $ss)) { if ($null -eq $script:Cnm[$x]) { $x } })
    if ($bad.Count -gt 0 -or $cs.Count -eq 0 -or $ss.Count -eq 0) { return ,@(C-Todo $id ('client or supplier not converted (' + ($bad -join ' ') + ')') $ind) }
    foreach ($c in $n.k) { if ($c -is [hashtable]) { C-Fold $c } }
    $script:Cstatus[$id] = 'mapped'
    $l = @()
    foreach ($c in $cs) {
        foreach ($s in $ss) {
            $cref = C-Ref $ctx $c; $sref = C-Ref $ctx $s
            if (C-Has $id 'Satisfy') { $l += "${ind}satisfy $sref by $cref;"; C-Inc 'satisfy' }
            elseif (C-Has $id 'Verify') {
                $vn = Ident ($script:Cnm[$c] + '_verification')
                $cx = [string]$ctx
                if (-not $script:Cused.ContainsKey($cx)) { $script:Cused[$cx] = [hashtable]::new() }
                while ($script:Cused[$cx].ContainsKey($vn)) { $kk = "$vn#"; $script:Cused[$cx][$kk] = 1 + [int]$script:Cused[$cx][$kk]; $vn = $vn + '_' + $script:Cused[$cx][$kk] }
                $script:Cused[$cx][$vn] = 1
                $l += @("${ind}verification def $vn {", "$ind    // verified by $cref", "$ind    objective {", "$ind        verify $sref;", "$ind    }", "$ind}")
                C-Inc 'verify'; C-Inc 'verification def'
            }
            elseif (C-Has $id 'DeriveReqt') {
                $top = C-Top $ctx
                if (-not $script:Cimports.ContainsKey($top)) { $script:Cimports[$top] = [hashtable]::new() }
                $script:Cimports[$top]['RequirementDerivation'] = 1
                $l += @("${ind}#derivation connection {", "$ind    end #original ::> $sref;", "$ind    end #derive ::> $cref;", "$ind}")
                C-Inc 'derivation'
            }
            elseif (C-Has $id 'Allocate') { $l += "${ind}allocate $cref to $sref;"; C-Inc 'allocate' }
            else {
                $why = $null; foreach ($w in @('Trace', 'Refine', 'Copy')) { if (C-Has $id $w) { $why = $w; break } }
                if (-not $why) { $why = $n.t }
                $why = Lc $why
                $named = $null -ne $n.a['name'] -and $n.a['name'] -ne ''
                $lab = ''; if ($named) { $lab = (C-N $id) + ' ' }
                $l += "${ind}dependency ${lab}from $cref to $sref; // $why"
                C-Inc 'dependency'
            }
        }
    }
    $rk = $null; foreach ($w in @('Satisfy', 'Verify', 'DeriveReqt', 'Allocate')) { if (C-Has $id $w) { $rk = $w; break } }
    $rkind = @{ Satisfy = 'satisfy'; Verify = 'verification def'; DeriveReqt = 'derivation'; Allocate = 'allocate' }
    $kd = 'dependency'; if ($rk) { $kd = $rkind[$rk] }
    return ,(C-Tag $id $kd (C-Qual $ctx) $l)
}
function C-ActivityLines($ctx, $id, [string]$ind) {
    $n = $script:Cel[$id]
    $l = @()
    $nodename = [hashtable]::new()
    foreach ($p in (XL-Kids $n 'ownedParameter')) {
        foreach ($c in $p.k) { if ($c -is [hashtable]) { C-Fold $c } }
        $d = [string]$p.a['direction']; if (-not (PTrue $d)) { $d = 'in' }; if ($d -ceq 'return') { $d = 'out' }
        $tr = C-TypeRef $ctx $p; $ty = $tr[0]; $cmt = $tr[2]
        $line = "$ind$d " + (C-N $p.id); if ($null -ne $ty) { $line += " : $ty" }; $line += (C-Mult $p) + ";$cmt"
        $l += (C-Tag $p.id 'parameter' ((C-Qual $ctx) + '::' + (C-N $p.id)) @($line))[0]
        $script:Cstatus[$p.id] = 'mapped'; C-Inc 'parameter'
    }
    foreach ($c in (XL-Kids $n 'node')) {
        $t = [string]$c.t
        if ($t -ceq 'InitialNode') { $nodename[$c.id] = 'start'; $script:Cstatus[$c.id] = 'folded'; continue }
        if ($t -cmatch '^(ActivityFinalNode|FlowFinalNode)$') { $nodename[$c.id] = 'done'; $script:Cstatus[$c.id] = 'folded'; continue }
        if ($t -ceq 'ActivityParameterNode') { $script:Cstatus[$c.id] = 'folded'; continue }
        if ($t -cmatch '^(CallBehaviorAction|OpaqueAction|CallOperationAction)$') {
            $b = First (IdRefs $c 'behavior')
            $bt = ''; if ($null -ne $b -and (PTrue $script:Cnm[$b])) { $bt = ' : ' + (C-Ref $ctx $b) }
            $l += (C-Tag $c.id 'action' ((C-Qual $ctx) + '::' + (C-N $c.id)) @("${ind}action " + (C-N $c.id) + "$bt;"))[0]
            $nodename[$c.id] = C-N $c.id
            $script:Cstatus[$c.id] = 'mapped'; C-Inc 'action'
            foreach ($k in (XL-Kids $c $null)) { if (PTrue $k.id) { $l += (C-Todo $k.id 'pin (object flow) not converted' $ind) } }
            continue
        }
        if (PTrue $c.id) { $l += (C-Todo $c.id 'activity node not converted' $ind) }
    }
    foreach ($c in (XL-Kids $n 'edge')) {
        $s = First (IdRefs $c 'source'); $t = First (IdRefs $c 'target')
        if ([string]$c.t -ceq 'ControlFlow' -and $null -ne $s -and $null -ne $t -and (PTrue $nodename[$s]) -and (PTrue $nodename[$t])) {
            foreach ($k in $c.k) { if ($k -is [hashtable]) { C-Fold $k } }
            $l += (C-Tag $c.id 'succession' (C-Qual $ctx) @("${ind}first $($nodename[$s]) then $($nodename[$t]);"))[0]
            $script:Cstatus[$c.id] = 'mapped'; C-Inc 'succession'
            continue
        }
        if (PTrue $c.id) { $l += (C-Todo $c.id 'activity edge not converted (object flow, or an end that is a decision/fork/pin)' $ind) }
    }
    return ,$l
}
$script:NSK = [hashtable]::new()
foreach ($k in (-split 'package partdef portdef constraintdef verif actiondef itemdef attrdef enumdef req usecasedef')) { $script:NSK[$k] = 1 }
$script:DEFNAME = @{ package = 'package'; partdef = 'part def'; portdef = 'port def'; constraintdef = 'constraint def'; verif = 'verification def';
                actiondef = 'action def'; itemdef = 'item def'; attrdef = 'attribute def'; enumdef = 'enum def'; usecasedef = 'use case def' }
function C-EmitBody($id, [string]$ind) {
    $n = $script:Cel[$id]
    $l = @()
    foreach ($c in $n.k) {
        if ($c -isnot [hashtable] -or -not (PTrue $c.id)) { continue }
        $cid = $c.id
        if (PTrue $script:Cstatus[$cid]) { continue }
        $k = [string]$script:Ckind[$cid]
        if ($k -ceq 'comment' -and $c.l -ceq 'ownedComment') { continue }
        if ($c.l -cmatch '^(generalization|ownedParameter|node|edge|lowerValue|upperValue|defaultValue)$' -and $script:NSK.ContainsKey([string]$script:Ckind[$id])) { continue }
        if ($k -ceq 'req' -and $script:Cowner[$cid] -cne $id) { continue }
        if ($k -ceq 'prop') { $l += (C-PropLine $id $cid $ind) }
        elseif ($k -ceq 'port') { $l += (C-PortLine $id $cid $ind) }
        elseif ($k -ceq 'conn') { $l += (C-ConnLine $id $cid $ind) }
        elseif ($k -ceq 'rel') { $l += (C-RelLines $id $cid $ind) }
        elseif ($k -ceq 'literal') {
            if ($script:Ckind[$id] -ceq 'enumdef') {
                $l += (C-Tag $cid 'enum' ((C-Qual $id) + '::' + (C-N $cid)) @("${ind}enum " + (C-N $cid) + ';'))[0]
                $script:Cstatus[$cid] = 'mapped'; C-Inc 'enum'
                foreach ($x in $c.k) { if ($x -is [hashtable]) { C-Fold $x } }
            } else { $l += (C-Todo $cid 'literal outside an enumeration' $ind) }
        }
        elseif ($k -ceq 'assoc') { C-Fold $c }
        elseif ($k -ceq 'libtype') { C-Fold $c }
        elseif ($k -ceq 'comment') {
            $first = (C-Tag $cid 'comment' (C-Qual $id) @("${ind}comment "))[0]
            $b = ''; if ($null -ne $c.a['body']) { $b = $c.a['body'] }
            $d = (SDoc $b ''); $d[0] = $d[0] -creplace '^doc ', ''
            $l += $first + ($d -join ' ')
            $script:Cstatus[$cid] = 'mapped'; C-Inc 'comment'
        }
        elseif ($script:NSK.ContainsKey($k)) { $l += (C-Emit $cid $ind) }
        elseif ($c.t -cmatch '^(PackageImport|ElementImport|ProfileApplication)$') { C-Fold $c }
        else {
            $why = 'no SysML v2 mapping in this converter'
            if ($c.t -ceq 'Constraint') { $why = 'constraint: ' + (X-Constraint $c) }
            $l += (C-Todo $cid $why $ind)
        }
    }
    return ,$l
}
function C-Emit($id, [string]$ind) {
    $n = $script:Cel[$id]
    $k = $script:Ckind[$id]
    $script:Cstatus[$id] = 'mapped'
    $in = "$ind    "
    $b = (C-StereoNotes $id $in)
    if ($k -ceq 'req') {
        foreach ($c in $n.k) {
            if ($c -isnot [hashtable]) { continue }
            $ck = $null; if (PTrue $c.id) { $ck = $script:Ckind[$c.id] }
            if (-not (PTrue $ck) -or $ck -cne 'req') { C-Fold $c }
        }
        $app = C-ReqApp $id
        $text = SAttr $app @('text')
        $ds = @(foreach ($c in (XL-Kids $n 'ownedComment')) { [string](Dfl $c.a['body'] '') })
        $script:Cout['doc'] = [int]$script:Cout['doc'] + $ds.Count
        $parts = @(foreach ($x in (@(,$text) + $ds)) { if ($null -ne $x -and $x -cmatch '[^ \t\n\r\f\v]') { $x } })
        $text = $parts -join "`n`n"
        $attrs = @()
        if ($null -ne $app) {
            foreach ($ak in (SortOrd $app.a.Keys)) {
                if ($ak -cmatch '^(xmi:|base_)') { continue }
                $lk = Lc $ak
                if ($lk -ceq 'id' -or $lk -ceq 'text' -or $lk -ceq 'verifymethod') { continue }
                $attrs += ,@($ak, $app.a[$ak])
            }
        }
        $title = $n.raw
        if ($null -ne $title -and $title -ceq $script:Cnm[$id]) { $title = $null }
        $style = $script:Cstyle
        if ($style -ceq 'usage') { C-Inc 'requirement'; $kd = 'requirement' } else { C-Inc 'requirement def'; $kd = 'requirement def' }
        $body = @(foreach ($x in $b) { if ($x.StartsWith($in)) { $x.Substring($in.Length) } else { $x } })
        $req = @{ name = (C-N $id); doorsId = $n.doorsId; text = $text; title = $title; vm = (SAttr $app @('verifyMethod')); attrs = $attrs; body = $body }
        $l = (C-Tag $id $kd (C-Qual $id) (SRequirement $req $style $ind))
        foreach ($c in $n.k) {
            if ($c -isnot [hashtable] -or -not (PTrue $c.id)) { continue }
            if ($script:Ckind[$c.id] -ceq 'req' -and -not (PTrue $script:Cstatus[$c.id])) { $l += (C-Emit $c.id $ind) }
        }
        return ,$l
    }
    $kw = $script:DEFNAME[$k]
    $head = $kw + ' ' + (C-N $id)
    if ($k -cne 'package') { $head += (C-Gens $id $n) }
    C-Inc $kw
    $b += (C-Docs $n $in)
    if ($k -ceq 'attrdef') {
        $vt = C-Has $id 'ValueType'
        if ($vt) {
            $u = First (IdRefs $vt 'unit')
            if ($null -ne $u) {
                $un = $u; if ($null -ne $script:Cel[$u] -and $null -ne $script:Cel[$u].a['name']) { $un = $script:Cel[$u].a['name'] }
                $b += "$in// SysML 1.x unit: $un -- specialize an ISQ quantity value by hand"
            }
        }
    }
    if ($k -ceq 'verif' -and $script:Cverifies.ContainsKey($id)) {
        $relof = [hashtable]::new()
        foreach ($r in (SortOrd $script:Cverif_rel.Keys)) {
            if (@($script:Cverif_rel[$r][0]) -cnotcontains $id) { continue }
            foreach ($x in $script:Cverif_rel[$r][1]) { if (-not $relof.ContainsKey($x)) { $relof[$x] = $r } }
        }
        $b += "${in}objective {"
        $cnt = 0
        foreach ($x in $script:Cverifies[$id]) {
            if (-not (PTrue $script:Cnm[$x])) { continue }
            $cnt++
            $rr = C-Ref $id $x; if (-not (PTrue $rr)) { $rr = "TODO_$x" }
            $b += (C-Tag $relof[$x] 'verify' (C-Qual $id) @("$in    verify $rr;"))[0]
        }
        $b += "$in}"
        $script:Cout['verify'] = [int]$script:Cout['verify'] + $cnt
        foreach ($r in @($script:Cverif_rel.Keys)) {
            if (@($script:Cverif_rel[$r][0]) -ccontains $id) { $script:Cstatus[$r] = 'mapped'; foreach ($x in $script:Cel[$r].k) { if ($x -is [hashtable]) { C-Fold $x } } }
        }
    }
    if ($k -ceq 'constraintdef') { $b += "$in// TODO constraint expression (parametrics) not converted" }
    if ($n.t -ceq 'Activity') { $b += (C-ActivityLines $id $id $in) }
    $b += (C-EmitBody $id $in)
    if ($k -ceq 'package') { $b = @("$in" + [char]0 + "IMPORTS $id") + $b }
    if ($b.Count -eq 0) { return ,(C-Tag $id $kw (C-Qual $id) @("$ind$head;")) }
    return ,((C-Tag $id $kw (C-Qual $id) @("$ind$head {")) + $b + @("$ind}"))
}

function Xmi-Convert($m, $o) {
    $script:Cmodel = $m; $script:Cel = $m.el; $script:Cst = $m.st
    $script:Cstyle = 'def'; if ($o.req_style) { $script:Cstyle = $o.req_style }
    $layout = '{seg}/{pkg}.sysml'; if ($o.layout) { $layout = $o.layout }
    $script:Cstatus = [hashtable]::new(); $script:Ckind = [hashtable]::new(); $script:Cnm = [hashtable]::new(); $script:Cowner = [hashtable]::new(); $script:Cout = [hashtable]::new()
    $script:Cunmapped = @(); $script:Cunres = [hashtable]::new(); $script:Cimports = [hashtable]::new(); $script:Cstereo_todo = [hashtable]::new()
    $script:Cused = [hashtable]::new(); $script:Ccount = [hashtable]::new(); $script:Ctagmap = [hashtable]::new(); $script:CmemoN = [hashtable]::new(); $script:CmemoQ = [hashtable]::new(); $script:CmemoC = [hashtable]::new()
    $el = $m.el
    $port_typed = [hashtable]::new(); $part_typed = [hashtable]::new()
    foreach ($id in $m.order) {
        $n = $el[$id]
        if ($n.t -cne 'Port' -and $n.t -cne 'Property') { continue }
        $tid = First (IdRefs $n 'type')
        if ($null -eq $tid -or $null -eq $el[$tid]) { continue }
        if ($n.t -ceq 'Port') { $port_typed[$tid] = 1 } else { $part_typed[$tid] = 1 }
    }
    foreach ($id in $m.order) {
        $n = $el[$id]; $t = $n.t
        if ($t -cmatch '^(Model|Package)$') { $k = 'package' }
        elseif ($t -ceq 'Class' -or $t -ceq 'Component' -or $t -ceq 'Actor') {
            if (C-IsReq $id) { $k = 'req' }
            elseif (C-Has $id 'TestCase') { $k = 'verif' }
            elseif (C-Has $id 'InterfaceBlock') { $k = 'portdef' }
            elseif (C-Has $id 'ConstraintBlock') { $k = 'constraintdef' }
            elseif ($port_typed.ContainsKey($id) -and -not $part_typed.ContainsKey($id)) { $k = 'portdef' }
            else { $k = 'partdef' }
        }
        elseif ($t -ceq 'Activity') { if (C-Has $id 'TestCase') { $k = 'verif' } else { $k = 'actiondef' } }
        elseif ($t -ceq 'Signal') { $k = 'itemdef' }
        elseif ($t -ceq 'PrimitiveType' -and (PTrue (C-LibOf $n.a['name']))) { $k = 'libtype' }
        elseif ($t -cmatch '^(DataType|PrimitiveType)$') { $k = 'attrdef' }
        elseif ($t -ceq 'Enumeration') { $k = 'enumdef' }
        elseif ($t -ceq 'UseCase') { $k = 'usecasedef' }
        elseif ($t -cmatch '^(Abstraction|Dependency|Usage|Realization)$') { $k = 'rel' }
        elseif ($t -ceq 'Association') { $k = 'assoc' }
        elseif ($t -ceq 'Property') { $k = 'prop' }
        elseif ($t -ceq 'Port') { $k = 'port' }
        elseif ($t -ceq 'Connector') { $k = 'conn' }
        elseif ($t -ceq 'Comment') { $k = 'comment' }
        elseif ($t -ceq 'EnumerationLiteral') { $k = 'literal' }
        elseif ($t -ceq 'Parameter') { $k = 'param' }
        else { $k = 'other' }
        $script:Ckind[$id] = $k
    }
    $model_name = $null
    foreach ($id in $m.order) {
        $n = $el[$id]
        if ($script:Ckind[$id] -ceq 'package' -and $n.t -ceq 'Model' -and $null -eq $m.parent[$id]) {
            $model_name = $n.a['name']; $script:Ckind[$id] = 'model'; $script:Cstatus[$id] = 'folded'; continue
        }
        $script:Cowner[$id] = C-NsOwner $id
    }
    foreach ($id in $m.order) {
        if ($script:Ckind[$id] -ceq 'model') { continue }
        $n = $el[$id]
        $raw = $n.a['name']
        if ($null -eq $raw -or $raw -eq '') { $c = XL-Kid $n 'name'; if ($null -ne $c) { $raw = XL-Text $c } }
        if ($script:Ckind[$id] -ceq 'req') {
            $app = C-ReqApp $id
            $rid = SAttr $app @('id')
            $n.doorsId = $rid
            if ($null -ne $rid -and $rid -ne '') { $w = $rid } elseif ($null -ne $raw -and $raw -ne '') { $w = $raw } else { $w = $id }
            C-Assign $id (Ident $w)
            $n.raw = $raw
            continue
        }
        if (($null -eq $raw -or $raw -eq '') -and $script:Ckind[$id] -cmatch '^(prop|port)$') {
            $tid = First (IdRefs $n 'type')
            if ($null -ne $tid -and $null -ne $el[$tid] -and $null -ne $el[$tid].a['name']) { $raw = LcFirst $el[$tid].a['name'] }
        }
        if ($null -eq $raw -or $raw -eq '') { $raw = Ident $id }
        $raw = $raw -creplace '^[ \t\n\r\f\v]+|[ \t\n\r\f\v]+$', ''
        C-Assign $id $raw
    }
    $tl = @(foreach ($id in $m.order) { if ($script:Cowner[$id] -ceq $script:LOOSEID -and $script:Ckind[$id] -ceq 'package') { $id } })
    $script:Cloose = @(foreach ($id in $m.order) { if ($script:Cowner[$id] -ceq $script:LOOSEID -and $script:Ckind[$id] -cne 'package') { $id } })
    if ($null -ne $o.name) { $loose_name = $o.name } elseif ($null -ne $model_name -and $model_name -ne '') { $loose_name = $model_name } else { $loose_name = $m.base }
    foreach ($id in $tl) { if ($script:Cnm[$id] -ceq $loose_name) { $loose_name += '_loose'; break } }
    $top = @($tl); if ($script:Cloose.Count -gt 0) { $top += $script:LOOSEID }
    $script:Cnm[$script:LOOSEID] = $loose_name; $script:Ckind[$script:LOOSEID] = 'package'

    $script:Cverifies = [hashtable]::new(); $script:Cverif_rel = [hashtable]::new()
    foreach ($id in $m.order) {
        if ($script:Ckind[$id] -cne 'rel' -or -not (C-Has $id 'Verify')) { continue }
        $n = $el[$id]
        $cs = (IdRefs $n 'client'); $ss = (IdRefs $n 'supplier')
        foreach ($c in $cs) { if (-not $script:Cverifies.ContainsKey($c)) { $script:Cverifies[$c] = @() }; $script:Cverifies[$c] += $ss }
        $script:Cverif_rel[$id] = @(,$cs + ,$ss)
    }

    $files = [hashtable]::new(); $layout_notes = @()
    $lsId = $script:LOOSEID
    foreach ($tp in $top) {
        if ($tp -ceq $lsId) {
            $script:Cstatus[$lsId] = 'mapped'
            $b = @("    " + [char]0 + "IMPORTS $lsId")
            foreach ($id in $script:Cloose) {
                if (PTrue $script:Cstatus[$id]) { continue }
                $k = $script:Ckind[$id]
                if ($k -ceq 'prop') { $b += (C-PropLine $lsId $id '    ') }
                elseif ($k -ceq 'port') { $b += (C-PortLine $lsId $id '    ') }
                elseif ($k -ceq 'conn') {
                    $es = (XL-Kids $el[$id] 'end')
                    if ($es.Count -gt 0) { $b += (C-ConnLine $lsId $id '    ') }
                    else { $script:Cstatus[$id] = 'mapped'; C-Inc 'connection'; $b += '    connection ' + (C-N $id) + ';' }
                }
                elseif ($k -ceq 'rel') { $b += (C-RelLines $lsId $id '    ') }
                elseif ($k -ceq 'assoc' -or $k -ceq 'libtype' -or $el[$id].t -cmatch '^(PackageImport|ElementImport|ProfileApplication)$') { C-Fold $el[$id] }
                elseif ($k -ceq 'comment') {
                    $c = $el[$id]
                    if ($null -ne $c.a['body']) { $bt = $c.a['body'] } else { $x = XL-Kid $c 'body'; if ($null -ne $x) { $bt = XL-Text $x } else { $bt = '' } }
                    $d = (SDoc $bt ''); $d[0] = $d[0] -creplace '^doc ', ''
                    $lab = ''; if (PTrue $c.a['name']) { $lab = (C-N $id) + ' ' }
                    $b += '    comment ' + $lab + ($d -join "`n    ")
                    $script:Cstatus[$id] = 'mapped'; C-Inc 'comment'
                }
                elseif ($script:NSK.ContainsKey([string]$k)) { $b += (C-Emit $id '    ') }
                else { $b += (C-Todo $id 'no SysML v2 mapping in this converter' '    ') }
            }
            C-Inc 'package'
            $body = @('package ' + (SName $loose_name) + ' {') + $b + @('}')
        } else {
            $body = (C-Emit $tp '')
        }
        $txt = ($body -join "`n") + "`n"
        $fn = $layout
        $pn = $script:Cnm[$tp]
        $seg = (Lc $pn) -creplace '[^a-z0-9]+', '-'; $seg = $seg -creplace '^-+|-+$', ''; if ($seg -eq '') { $seg = 'model' }
        $pf = $pn -creplace '[^A-Za-z0-9_.\-]+', '_'
        $fn = $fn.Replace('{seg}', $seg).Replace('{pkg}', $pf)
        $lp = Layout-Path $o.layout_map $pn $pf $fn
        $fn = $lp[0]; if ($null -ne $lp[1]) { $layout_notes += $lp[1] }
        if ($files.ContainsKey($fn)) {
            $fn2 = $fn -creplace '\.sysml$', "_$pf.sysml"
            $layout_notes += "layout map: $pn and another package both go to $fn; $pn written to $fn2"
            $fn = $fn2
        }
        $files[$fn] = @{ tp = $tp; text = $txt }
    }
    $missed = @(foreach ($id in $m.order) { if (-not (PTrue $script:Cstatus[$id])) { $id } })
    if ($missed.Count -gt 0 -and $top.Count -gt 0) {
        $f0 = (SortOrd $files.Keys)[0]
        $t = $files[$f0].text -creplace '\}\n\z', ''
        $t += "    // elements not reached by the converter (owner not converted):`n"
        foreach ($id in $missed) { $t += (C-Todo $id 'owner not converted' '    ') + "`n" }
        $files[$f0].text = "$t}`n"
    }
    $impRe = [regex]('(?m)^([ ]*)' + [char]0 + 'IMPORTS ([^ \t\n\r\f\v]+)\n')
    foreach ($fk in @($files.Keys)) {
        $f = $files[$fk]
        $f.text = ReplaceEach $f.text $impRe {
            param($mm)
            $i = $mm.Groups[1].Value; $p = $mm.Groups[2].Value
            $tpp = C-Top $p
            if ($p -cne $tpp) { return '' }
            $qp = C-Qual $p
            $imp = $script:Cimports[$p]; if ($null -eq $imp) { return '' }
            return (-join @(foreach ($x in (SortOrd $imp.Keys)) { if ($x -cne $qp) { "${i}private import ${x}::*;`n" } }))
        }
        $f.text = $f.text -creplace '\{\n(?:[ \t\n\r\f\v]*\n)*', "{`n"
    }
    $src = $m.path -creplace '^[\s\S]*[/\\]', ''
    $text = [hashtable]::new()
    foreach ($fk in $files.Keys) { $text[$fk] = "// generated by xmi2sysml.pl from $src -- review before committing; TODO lines need a person`n" + $files[$fk].text }
    $at = [hashtable]::new()
    $c1 = [string][char]1
    $tagRe = [regex]([char]1 + '([^' + [char]1 + ']*)' + [char]1)
    foreach ($fk in (SortOrd $text.Keys)) {
        if ($text[$fk].IndexOf($c1) -lt 0) { continue }
        $flines = $text[$fk] -split "`n"
        for ($i = 0; $i -lt $flines.Count; $i++) {
            if ($flines[$i].IndexOf($c1) -lt 0) { continue }
            foreach ($mm in $tagRe.Matches($flines[$i])) { $tg = $mm.Groups[1].Value; if (-not $at.ContainsKey($tg)) { $at[$tg] = @($fk, ($i + 1)) } }
            $flines[$i] = $tagRe.Replace($flines[$i], '')
        }
        $text[$fk] = $flines -join "`n"
    }
    $DEFK = [hashtable]::new()
    foreach ($x in @('package', 'part def', 'port def', 'constraint def', 'verification def', 'action def', 'item def', 'attribute def', 'enum def', 'use case def', 'requirement', 'requirement def')) { $DEFK[$x] = 1 }
    $cmap = $script:Ctagmap
    $maprows = @(foreach ($id in $m.order) {
        $src_id = $id
        while ($null -ne $src_id -and -not $at.ContainsKey($src_id)) { $src_id = $m.parent[$src_id] }
        if ($null -eq $src_id) { continue }
        $e = $cmap[$src_id]
        if ($src_id -ceq $id) { $kind = $e.kind } elseif ($e.kind -ceq 'todo') { $kind = 'todo' } else { $kind = 'folded' }
        $def = $null
        for ($x = $src_id; $null -ne $x; $x = $m.parent[$x]) { if ($cmap.ContainsKey($x) -and $DEFK.ContainsKey([string]$cmap[$x].kind) -and $at.ContainsKey($x)) { $def = $x; break } }
        $q = $e.q
        $dq = ''; if ($null -ne $def) { $dq = $cmap[$def].q }
        if ($null -eq $q) { $q = $dq + '::(TODO ' + $el[$src_id].t + ')' }
        if ($null -eq $q -or $q -eq '') { $q = $dq }
        $tdid = $null; $tdnm = $null; if ($kind -ceq 'todo') { $tdid = $src_id; $tdnm = $el[$src_id].a['name'] }
        $dk = ''; if ($null -ne $def) { $dk = $cmap[$def].kind }
        @{ id = $id; type = $el[$id].t; q = $q; kind = $kind; file = $at[$src_id][0]; line = $at[$src_id][1]; def = $dq; defkind = $dk; todo_id = $tdid; todo_name = $tdnm }
    })
    $maprows = SortByKey $maprows @(foreach ($r in $maprows) { $r.file + "`0" + ('{0:D9}' -f [int]$r.line) + "`0" + $r.id })

    $in = [hashtable]::new()
    foreach ($id in $m.order) {
        $t = $el[$id].t
        $s = $script:Cstatus[$id]; if (-not (PTrue $s)) { $s = 'todo' }; if ($s -cmatch '^todo') { $s = 'todo' }
        if (-not $in.ContainsKey($t)) { $in[$t] = [hashtable]::new() }
        $in[$t]['in'] = 1 + [int]$in[$t]['in']; $in[$t][$s] = 1 + [int]$in[$t][$s]
    }
    $stc = [hashtable]::new()
    foreach ($a in $m.apps) { $stc[$a.l] = 1 + [int]$stc[$a.l] }
    $scope = 0; $scope_done = 0
    foreach ($t in $script:IN_SCOPE) { if ($in.ContainsKey($t)) { $scope += [int]$in[$t]['in']; $scope_done += [int]$in[$t]['mapped'] + [int]$in[$t]['folded'] } }
    $problems = SCheck $text
    $file_of = [hashtable]::new(); foreach ($fk in $files.Keys) { $file_of[$files[$fk].tp] = $fk }
    return @{ files = $text; problems = $problems; status = $script:Cstatus; file_of = $file_of; map = $maprows
              report = @{ source = $src; in = $in; out = $script:Cout; unmapped = $script:Cunmapped; stereotypes = $stc; stereo_todo = $script:Cstereo_todo
                          extensions = $m.ext; unresolved = $script:Cunres; layout = $layout_notes; scope = $scope; scope_done = $scope_done; total = $m.order.Count } }
}
function X-Constraint($c) {
    $s = XL-Kid $c 'specification'
    if ($null -eq $s) { return (X-Flat (XL-Text $c)) }
    if ($null -ne $s.a['body']) { $b = $s.a['body'] } else { $k = XL-Kid $s 'body'; if ($null -ne $k) { $b = XL-Text $k } elseif ($null -ne $s.a['value']) { $b = $s.a['value'] } else { $b = '' } }
    if ($null -ne $s.a['language']) { $l = $s.a['language'] } else { $k = XL-Kid $s 'language'; if ($null -ne $k) { $l = XL-Text $k } else { $l = '' } }
    $pre = ''; if ($l -ne '') { $pre = "${l}: " }
    return (X-Flat ($pre + $b))
}
function X-Flat($t) {
    if ($null -eq $t) { $t = '' }
    $t = [string]$t -creplace '[ \t\n\r\f\v]+', ' '
    $t = $t -creplace '^ | $', ''
    if ((U8Len $t) -gt 120) { return (U8Cut $t 117) + '...' }
    return $t
}
function U8Cut([string]$s, [int]$bytes) {               # the longest prefix of at most $bytes UTF-8 bytes
    if ($s -cmatch '^[\x00-\x7F]*$') { if ($s.Length -le $bytes) { return $s }; return $s.Substring(0, $bytes) }
    $n = 0; $i = 0
    while ($i -lt $s.Length) {
        $c = [int]$s[$i]; $w = 3; $step = 1
        if ($c -lt 0x80) { $w = 1 } elseif ($c -lt 0x800) { $w = 2 } elseif ($c -ge 0xD800 -and $c -le 0xDBFF) { $w = 4; $step = 2 }
        if ($n + $w -gt $bytes) { break }
        $n += $w; $i += $step
    }
    return $s.Substring(0, $i)
}

function Xmi-ReportText($out) {
    $r = $out.report
    $l = @("xmi2sysml report: $($r.source)", '', ((PadR 'in (xmi:type)' 28) + ' ' + (PadL 'in' 6) + ' ' + (PadL 'mapped' 7) + ' ' + (PadL 'folded' 7) + ' ' + (PadL 'todo' 6)))
    $tot = @{ in = 0; mapped = 0; folded = 0; todo = 0 }
    foreach ($t in (SortOrd $r.in.Keys)) {
        $x = $r.in[$t]
        $l += (PadR "uml:$t" 28) + ' ' + (PadL ([int]$x['in']) 6) + ' ' + (PadL ([int]$x['mapped']) 7) + ' ' + (PadL ([int]$x['folded']) 7) + ' ' + (PadL ([int]$x['todo']) 6)
        foreach ($k in @('in', 'mapped', 'folded', 'todo')) { $tot[$k] += [int]$x[$k] }
    }
    $l += (PadR 'total' 28) + ' ' + (PadL $tot.in 6) + ' ' + (PadL $tot.mapped 7) + ' ' + (PadL $tot.folded 7) + ' ' + (PadL $tot.todo 6)
    $l += ''
    $l += 'ported vs remaining (metric A filter uml:' + ($script:IN_SCOPE -join '|') + "): $($r.scope_done) of $($r.scope) ported, $($r.scope - $r.scope_done) remaining"
    $l += ''
    $st = (@(foreach ($k in (SortOrd $r.stereotypes.Keys)) { "$k $($r.stereotypes[$k])" }) -join ', ')
    if ($st -eq '') { $st = 'none' }
    $l += "stereotype applications: $st"
    if ($r.stereo_todo.Count -gt 0) { $l += 'stereotypes not converted: ' + (@(foreach ($k in (SortOrd $r.stereo_todo.Keys)) { "$k $($r.stereo_todo[$k])" }) -join ', ') }
    $l += "xmi:Extension and xmi:Documentation blocks skipped (diagrams, layout, exporter): $($r.extensions)"
    if ($r.unresolved.Count -gt 0) { $l += 'type references not resolved: ' + (@(foreach ($k in (SortOrd $r.unresolved.Keys)) { "$k ($($r.unresolved[$k]))" }) -join ', ') }
    $l += ''; $l += 'out (SysML v2)'
    foreach ($k in (SortOrd $r.out.Keys)) { $l += '  ' + (PadR $k 22) + ' ' + (PadL $r.out[$k] 6) }
    $u = @($r.unmapped)
    $l += ''; $l += "unmapped (TODO in the output): $($u.Count)"
    foreach ($x in $u) { $nm = ''; if ($x.name -ne '') { $nm = "'$($x.name)' " }; $l += '  uml:' + (PadR $x.type 22) + ' ' + (PadR $x.id 24) + ' ' + $nm + $x.why }
    $l += ''; $l += 'files: ' + ((SortOrd $out.files.Keys) -join ' ')
    $l += @($r.layout)
    $pr = @($out.problems)
    if ($pr.Count -gt 0) { $l += "self-check: $($pr.Count) problem(s)" } else { $l += 'self-check: ok' }
    foreach ($p in $pr) { $l += "  $p" }
    return ($l -join "`n") + "`n"
}

# ---- the v1 -> v2 map
function Csvf($v) { if ($null -eq $v) { $v = '' }; $v = [string]$v; if ($v -cmatch '[",\r\n]') { return '"' + $v.Replace('"', '""') + '"' }; return $v }
function Xmi-MapCsv($m, $out) {
    $t = "xmi_id,v1_type,v1_qualified_name,v2_qualified_name,v2_kind,file,line`n"
    $rows = @(foreach ($r in $out.map) { (@(foreach ($v in @($r.id, "uml:$($r.type)", (X-QName $m $r.id), $r.q, $r.kind, $r.file, $r.line)) { Csvf $v })) -join ',' })
    if ($rows.Count -gt 0) { $t += ($rows -join "`n") + "`n" }
    return $t
}
$script:CSV_RE = [regex]'\G(?:"((?:[^"]|"")*)"|([^,\n]*))(,|\n|\z)'
function Parse-Csv([string]$text) {                     # Perl's \G CSV loop: rows of fields
    $rows = @(); $row = @(); $pos = 0
    while ($true) {
        $mm = $script:CSV_RE.Match($text, $pos)
        if (-not $mm.Success) { break }
        if ($mm.Groups[1].Success) { $v = $mm.Groups[1].Value.Replace('""', '"') } else { $v = $mm.Groups[2].Value }
        $row += ,$v
        $sep = $mm.Groups[3].Value
        $np = $mm.Index + $mm.Length
        if ($sep -cne ',') { $rows += ,@($row); $row = @(); if ($sep -eq '') { break } }
        if ($np -eq $pos -and $mm.Length -eq 0) { break }
        $pos = $np
    }
    return ,$rows
}
function Xmi-ReadMapCsv([string]$path) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "${path}: No such file or directory`n" }
    $text = (Read-TextFile $path).Replace("`r", '')
    $rows = Parse-Csv $text
    $head = $null; if ($rows.Count -gt 0) { $head = $rows[0] }
    if ($null -eq $head -or ($head -join ',') -cne 'xmi_id,v1_type,v1_qualified_name,v2_qualified_name,v2_kind,file,line') {
        throw "${path}: not an xmi2sysml map (expected the header xmi_id,v1_type,v1_qualified_name,v2_qualified_name,v2_kind,file,line)`n"
    }
    $mm = [hashtable]::new()
    for ($i = 1; $i -lt $rows.Count; $i++) { $r = $rows[$i]; if ($r.Count -ge 7 -and $r[0] -ne '') { $mm[$r[0]] = @{ q = $r[3]; kind = $r[4]; file = $r[5]; line = $r[6] } } }
    return $mm
}

# ---- delta
function X-QName($m, $id) {
    $p = @()
    for ($x = $id; $null -ne $x; $x = $m.parent[$x]) {
        $n = $m.el[$x]
        if ($n.t -ceq 'Model' -and $null -eq $m.parent[$x]) { break }
        $nm = $n.a['name']
        if ($null -eq $nm -or $nm -eq '') {
            if ($x -cne $id) { continue }
            if ($n.t -ceq 'Comment') { $nm = 'comment' } else { $nm = X-AnonLabel $m $x }
        }
        $p = @($nm) + $p
    }
    return ($p -join '::')
}
function X-AnonLabel($m, $id) {
    $n = $m.el[$id]
    $nmf = { param($i) if ($null -eq $i) { $i = '' }; $e = $m.el[$i]; if ($null -ne $e -and $null -ne $e.a['name']) { return $e.a['name'] }; return '?' }
    if ($n.t -cmatch '^(Abstraction|Dependency|Usage|Realization)$') {
        $sx = $m.st[$id]; $stn = $null
        if ($null -ne $sx) { $ls = @(foreach ($v in $sx.Values) { $v.l }); if ($ls.Count -gt 0) { $stn = (SortOrd $ls)[0] } }
        $c = First (IdRefs $n 'client'); $s = First (IdRefs $n 'supplier')
        return '(' + (Dfl $stn $n.t) + ' ' + (& $nmf $c) + ' -> ' + (& $nmf $s) + ')'
    }
    if ($n.t -ceq 'Transition') { return '(Transition ' + (& $nmf $n.a['source']) + ' -> ' + (& $nmf $n.a['target']) + ')' }
    return "($($n.t))"
}
function X-OwnSig($n) { return (X-OwnWalk $n $true) }
function X-OwnWalk($x, [bool]$top) {
    if (-not $top -and $null -ne (XType $x) -and $null -ne (XId $x)) { return '' }
    $s = -join @(foreach ($k in (SortOrd $x.a.Keys)) { if ($k -cne 'xmi:id' -and (-not $top -or $k -cne 'name')) { " $k=$($x.a[$k])" } })
    $kk = ''
    foreach ($c in $x.k) {
        if ($c -is [hashtable]) {
            if ($null -ne (XType $c) -and $null -ne (XId $c)) { continue }
            $kk += '<' + $c.l + (X-OwnWalk $c $false) + '>'
        } else { $t = $c -creplace '[ \t\n\r\f\v]+', ' '; $kk += ($t -creplace '^ | $', '') }
    }
    return "$s$kk"
}
function X-StSig($m, $id) {
    $sx = $m.st[$id]; $out = [hashtable]::new()
    if ($null -eq $sx) { return $out }
    foreach ($k in (SortOrd $sx.Keys)) {
        $a = $sx[$k]; $h = [hashtable]::new()
        foreach ($ak in $a.a.Keys) { if ($ak -cne 'xmi:id' -and $ak -cnotmatch '^base_') { $h[$ak] = $a.a[$ak] } }
        $out[$a.l] = $h
    }
    return $out
}
function X-Where($m, $conv, $id) {                      # -> @(carried 1|0, where)
    $s = [string]$conv.status[$id]
    $top = $id
    while ($null -ne $m.parent[$top] -and $null -ne $m.parent[$m.parent[$top]]) { $top = $m.parent[$top] }
    $file = $conv.file_of[$top]
    if ($null -eq $file) { $fs = SortOrd $conv.files.Keys; if ($fs.Count -gt 0) { $file = $fs[0] } else { $file = '?' } }
    if ($s -ceq 'mapped' -or $s -ceq 'folded') { return ,@(1, $file) }
    if ($s -ceq 'todo') { return ,@(0, "manual: a TODO line in $file (the converter does not carry uml:$($m.el[$id].t))") }
    $p = $m.parent[$id]
    while ($null -ne $p -and [string]$conv.status[$p] -ceq 'todo-child') { $p = $m.parent[$p] }
    $on = 'an element'
    if ($null -ne $p) { $o = $m.el[$p]; $on = "uml:$($o.t)"; if ($null -ne $o.a['name']) { $on += " '" + $o.a['name'] + "'" } }
    return ,@(0, "manual: inside $on, which the converter leaves as a TODO in $file; rework the v2 text by hand")
}
function X-Item($m, $conv, $id, $what) {
    $w = X-Where $m $conv $id
    return @{ id = $id; type = $m.el[$id].t; qname = (X-QName $m $id); what = @($what); carried = $w[0]; where = $w[1] }
}
function Xmi-Delta($old, $new, $o) {
    $co = Xmi-Convert $old $o
    $cn = Xmi-Convert $new $o
    $added = @(); $removed = @(); $changed = @()
    $in_old = [hashtable]::new(); foreach ($id in $old.order) { $in_old[$id] = 1 }
    $in_new = [hashtable]::new(); foreach ($id in $new.order) { $in_new[$id] = 1 }
    foreach ($id in $new.order) {
        if ($id -cmatch '^anon_') { continue }
        if (-not $in_old.ContainsKey($id)) { $added += ,(X-Item $new $cn $id @()); continue }
        $a = $old.el[$id]; $b = $new.el[$id]
        $what = @()
        $na = [string](Dfl $a.a['name'] ''); $nb = [string](Dfl $b.a['name'] '')
        if ($na -cne $nb) { $what += "renamed '$na' -> '$nb'" }
        $pa = [string](Dfl $old.parent[$id] ''); $pb = [string](Dfl $new.parent[$id] '')
        if ($pa -cne $pb) {
            $fa = '(top)'; if ($pa -ne '') { $fa = X-QName $old $pa }
            $fb = '(top)'; if ($pb -ne '') { $fb = X-QName $new $pb }
            $what += "moved from $fa to $fb"
        }
        if ($a.t -cne $b.t) { $what += "type changed uml:$($a.t) -> uml:$($b.t)" }
        if ($what.Count -eq 0 -and (X-OwnSig $a) -cne (X-OwnSig $b)) { if ($a.t -ceq 'Comment') { $what += 'text changed' } else { $what += 'properties changed' } }
        if ($a.t -cmatch '^(Package|Model)$') { $what = @($what | Where-Object { $_ -cne 'properties changed' }) }
        $sa = X-StSig $old $id; $sb = X-StSig $new $id
        $ks = [hashtable]::new(); foreach ($k in $sa.Keys) { $ks[$k] = 1 }; foreach ($k in $sb.Keys) { $ks[$k] = 1 }
        $kl = @($ks.Keys)
        $kl = SortByKey $kl @(foreach ($k in $kl) { (Lc $k) + "`0" + $k })
        foreach ($k in $kl) {
            if (-not $sa.ContainsKey($k)) { $what += "stereotype $k applied" }
            elseif (-not $sb.ContainsKey($k)) { $what += "stereotype $k removed" }
            else {
                $ta = $sa[$k]; $tb = $sb[$k]
                $tk = [hashtable]::new(); foreach ($x in $ta.Keys) { $tk[$x] = 1 }; foreach ($x in $tb.Keys) { $tk[$x] = 1 }
                $tags = @(foreach ($x in (SortOrd $tk.Keys)) { if ([string](Dfl $ta[$x] '') -cne [string](Dfl $tb[$x] '')) { $x } })
                if ($tags.Count -gt 0) { $what += "stereotype ${k}: " + (@($tags | ForEach-Object { "$_ changed" }) -join ', ') }
            }
        }
        if ($what.Count -gt 0) { $changed += ,(X-Item $new $cn $id $what) }
    }
    foreach ($id in $old.order) {
        if ($id -cmatch '^anon_' -or $in_new.ContainsKey($id)) { continue }
        $removed += ,(X-Item $old $co $id @())
    }
    $all = @($added) + @($removed) + @($changed)
    $man = 0; foreach ($x in $all) { if (-not $x.carried) { $man++ } }
    return @{ old = $old; new = $new; added = $added; removed = $removed; changed = $changed; conv_old = $co; conv_new = $cn
              counts = @{ old = $old.order.Count; new = $new.order.Count; added = $added.Count; removed = $removed.Count; changed = $changed.Count; manual = $man; carried = ($all.Count - $man) } }
}
function X-DropLabel($m) {
    if (-not (Test-Path -LiteralPath $m.path -PathType Leaf)) { return '' }
    $b = Get-Content -LiteralPath $m.path -Encoding Byte -TotalCount 512
    if ($null -eq $b) { return '' }
    $head = -join [char[]][byte[]]@($b)
    if ($head -cmatch 'prime drop (v[0-9.]+)') { return $Matches[1] }
    return ''
}
function Xmi-DeltaText($d) {
    $c = $d.counts
    $src = { param($mm) $p = $mm.path -creplace '^[\s\S]*[/\\]', ''; $v = X-DropLabel $mm; if ($v) { return "$p ($v)" }; return $p }
    $l = @(('xmi delta: ' + (& $src $d.old) + ' -> ' + (& $src $d.new)),
           "elements $($c.old) -> $($c.new): $($c.added) added, $($c.removed) removed, $($c.changed) changed",
           "carried by the converter (re-convert the drop and merge it): $($c.carried)",
           "manual (the converter does not carry these; rework the v2 text by hand): $($c.manual)")
    foreach ($sec in @(@('added', '+'), @('removed', '-'), @('changed', '~'))) {
        $k = $sec[0]; $mk = $sec[1]
        $xs = @($d[$k])
        if ($xs.Count -eq 0) { continue }
        $l += ''; $l += "${k}:"
        foreach ($i in $xs) {
            $w = ''; if (@($i.what).Count -gt 0) { $w = ' -- ' + (@($i.what) -join '; ') }
            $l += "  $mk " + (PadR "uml:$($i.type)" 22) + ' ' + $i.qname + $w
            if ($i.carried) { $l += "      carried: $($i.where)" } else { $l += '      ' + $i.where }
        }
    }
    $man = @()
    foreach ($k in @('added', 'removed', 'changed')) { foreach ($x in @($d[$k])) { if (-not $x.carried) { $man += ,@($k, $x) } } }
    if ($man.Count -gt 0) {
        $l += ''; $l += 'manual rework list:'
        foreach ($p in $man) {
            $x = $p[1]; $w = ''; if (@($x.what).Count -gt 0) { $w = ' -- ' + (@($x.what) -join '; ') }
            $l += "  [ ] $($p[0]) uml:$($x.type) $($x.qname)$w (xmi:id $($x.id))"
        }
    }
    return ($l -join "`n") + "`n"
}

# ---- impact
$script:S_ = '[ \t\n\r\f\v]'
$script:V2HEAD = [regex]('^S*(?:(?:private|public|protected)S+)?(?:abstractS+|variationS+|#WS+)*(libraryS+package|package|(?:part|port|action|item|attribute|enum|constraint|verification|useS+case|requirement|interface|connection|state|calc|analysis|occurrence|allocation|metadata|view|viewpoint|rendering|concern|case|flow)S+def|requirement|part|action|state|item|verification|constraint|interface|connection|exhibitS+state|performS+action)S+(''[^'']*''|W+)'.Replace('S', $script:S_).Replace('W', '[A-Za-z0-9_]'))
function X-Trim($t) { if ($null -eq $t) { $t = '' }; $t = [string]$t -creplace '^[ \t\n\r\f\v]+|[ \t\n\r\f\v]+$', ''; return ($t -creplace '[ \t\n\r\f\v]+', ' ') }
function X-Last($p) { $s = (X-Segs $p); if ($s.Count -eq 0) { return '' }; return [string]$s[$s.Count - 1] }
function X-Segs($p) {
    if ($null -eq $p) { $p = '' }
    $p = [string]$p
    if ($p -eq '') { return ,@() }
    $s = @($p -csplit '::|\.')
    while ($s.Count -gt 0 -and $s[$s.Count - 1] -eq '') { if ($s.Count -eq 1) { $s = @() } else { $s = $s[0..($s.Count - 2)] } }   # Perl split drops trailing empty fields
    return ,@(foreach ($x in $s) { $x -creplace "^'|'$", '' })
}
function X-V2Scan($files) {
    $wc = '[A-Za-z0-9_]'; $WS = $script:S_
    $defs = [hashtable]::new(); $sat = @(); $ver = @(); $conn = @(); $alloc = @(); $use = @(); $doors = [hashtable]::new(); $lines = [hashtable]::new()
    $reDoors = [regex]('doorsId' + $WS + '*=' + $WS + '*"([^"]*)"')
    $reAlt1 = [regex]('^' + $WS + '*:' + $WS + '*~?([A-Za-z0-9_:''.]+)')
    $reUse = [regex]('^' + $WS + '*(?:in|out|inout|subject|ref|derived|abstract)\b[^:;]*?\b(' + $wc + '+|''[^'']*'')' + $WS + '*:' + $WS + '*~?([A-Za-z0-9_:''.]+)')
    $reSat = [regex]('^' + $WS + '*satisfy' + $WS + '+(?:requirement' + $WS + '+)?([A-Za-z0-9_:''.]+)' + $WS + '+by' + $WS + '+([A-Za-z0-9_:''.]+)')
    $reVer = [regex]('^' + $WS + '*verify' + $WS + '+(?:requirement' + $WS + '+)?([A-Za-z0-9_:''.]+)' + $WS + '*;')
    $reAlloc = [regex]('^' + $WS + '*allocate' + $WS + '+([A-Za-z0-9_:''.]+)' + $WS + '+to' + $WS + '+([A-Za-z0-9_:''.]+)')
    $reConn = [regex]('\bconnect' + $WS + '+(?:' + $wc + '+' + $WS + '*::>' + $WS + '*)?([A-Za-z0-9_:''.]+)' + $WS + '+to' + $WS + '+(?:' + $wc + '+' + $WS + '*::>' + $WS + '*)?([A-Za-z0-9_:''.]+)')
    $reBind = [regex]('^' + $WS + '*bind' + $WS + '+([A-Za-z0-9_:''.]+)' + $WS + '*=' + $WS + '*([A-Za-z0-9_:''.]+)')
    $reCn = [regex]('^' + $WS + '*(?:connection|interface)' + $WS + '+(' + $wc + '+)' + $WS + '*(?::' + $WS + '*' + $wc + '+' + $WS + '*)?connect')
    foreach ($f in (SortOrd $files.Keys)) {
        $flines = $files[$f] -split "`n"
        $lines[$f] = $flines
        $stack = @(); $depth = 0; $inc = $false
        for ($i = 0; $i -lt $flines.Count; $i++) {
            $s = $flines[$i]; $ln = $i + 1
            if ($inc) { if ($s -cmatch '^.*?\*/') { $s = $s -creplace '^.*?\*/', ''; $inc = $false } else { continue } }
            $raw = $s
            $s = $s -creplace '/\*.*?\*/', ''
            if ($s -cmatch '/\*.*$') { $s = $s -creplace '/\*.*$', ''; $inc = $true }
            $s = $s -creplace '//.*$', ''
            $s = $s -creplace '"(?:[^"\\]|\\.)*"', '""'
            $ctx = ''; if ($stack.Count -gt 0) { $ctx = $stack[$stack.Count - 1][2] }
            $vctx = $null
            for ($j = $stack.Count - 1; $j -ge 0; $j--) { if ($stack[$j][3] -cmatch '^verification') { $vctx = $stack[$j][2]; break } }
            $opens = $s.Length - $s.Replace('{', '').Length; $closes = $s.Length - $s.Replace('}', '').Length
            $hm = $script:V2HEAD.Match($s)
            if ($hm.Success) {
                $k = $hm.Groups[1].Value -creplace "$WS+", ' '; $nm = $hm.Groups[2].Value
                if ($ctx -ne '') { $q = $ctx + '::' + $nm } else { $q = $nm }
                if (-not $defs.ContainsKey($q)) { $defs[$q] = @{ file = $f; start = $ln; end = $ln; kind = $k; name = $nm; ctx = $ctx } }
                if ($k -cmatch '^requirement') { $dm = $reDoors.Match($raw); if ($dm.Success) { $doors[$nm] = $dm.Groups[1].Value } }
                $um = $reAlt1.Match($s)
                if (-not $um.Success) { $um = ([regex]('^' + $WS + '*[^:]*?\b' + [regex]::Escape($nm) + $WS + '*:' + $WS + '*~?([A-Za-z0-9_:''.]+)')).Match($s) }
                if ($um.Success -and $k -cnotmatch ' def$|package') { $use += ,@{ name = $nm; type = $um.Groups[1].Value; ctx = $ctx; file = $f; line = $ln; kind = $k } }
                if ($opens -gt $closes) { $stack += ,@($nm, $depth, $q, $k) }
            } else {
                $um = $reUse.Match($s)
                if ($um.Success) { $use += ,@{ name = $um.Groups[1].Value; type = $um.Groups[2].Value; ctx = $ctx; file = $f; line = $ln; kind = 'usage' } }
            }
            if ($stack.Count -gt 0) { $dm = $reDoors.Match($raw); if ($dm.Success) { $top = $stack[$stack.Count - 1][0]; if (-not $doors.ContainsKey($top)) { $doors[$top] = $dm.Groups[1].Value } } }
            $mm = $reSat.Match($s); if ($mm.Success) { $sat += ,@{ req = $mm.Groups[1].Value; by = $mm.Groups[2].Value; ctx = $ctx; file = $f; line = $ln } }
            $mm = $reVer.Match($s); if ($mm.Success) { $vc = $vctx; if ($null -eq $vc) { $vc = $ctx }; $ver += ,@{ req = $mm.Groups[1].Value; ctx = $vc; file = $f; line = $ln } }
            $mm = $reAlloc.Match($s); if ($mm.Success) { $alloc += ,@{ from = $mm.Groups[1].Value; to = $mm.Groups[2].Value; ctx = $ctx; file = $f; line = $ln } }
            $mm = $reConn.Match($s); if (-not $mm.Success) { $mm = $reBind.Match($s) }
            if ($mm.Success) {
                $cm = $reCn.Match($s); $cn = $null; if ($cm.Success) { $cn = $cm.Groups[1].Value }
                $conn += ,@{ ends = @($mm.Groups[1].Value, $mm.Groups[2].Value); name = $cn; ctx = $ctx; file = $f; line = $ln; text = (X-Trim $raw) }
            }
            $depth += $opens - $closes
            while ($stack.Count -gt 0 -and $depth -le $stack[$stack.Count - 1][1]) {
                $e = $stack[$stack.Count - 1]
                if ($stack.Count -eq 1) { $stack = @() } else { $stack = $stack[0..($stack.Count - 2)] }
                $defs[$e[2]].end = $ln
            }
        }
    }
    return @{ defs = $defs; sat = $sat; ver = $ver; conn = $conn; alloc = $alloc; use = $use; doors = $doors; lines = $lines }
}
function X-Block($scan, $q) {
    if ($null -eq $q) { return $null }
    $d = $scan.defs[$q]; if ($null -eq $d) { return $null }
    $flines = $scan.lines[$d.file]
    return ((@(for ($i = $d.start - 1; $i -le $d.end - 1; $i++) { $tx = X-Trim $flines[$i]; if ($tx -ne '') { $tx } })) -join "`n")
}
function X-ReadTree([string]$dir) {
    $t = [hashtable]::new()
    X-ReadTreeInto $t $dir ''
    return $t
}
function X-ReadTreeInto($t, [string]$d, [string]$rel) {
    $items = @(Get-ChildItem -LiteralPath $d -Force -ErrorAction SilentlyContinue)
    $names = SortOrd @(foreach ($x in $items) { $x.Name })
    foreach ($e in $names) {
        if ($e.StartsWith('.')) { continue }
        $p = Join-Path $d $e
        if ($rel -eq '') { $r = $e } else { $r = "$rel/$e" }
        if (Test-Path -LiteralPath $p -PathType Container) { X-ReadTreeInto $t $p $r }
        elseif ($e -cmatch '\.sysml$') { $t[$r] = (Read-TextFile $p).Replace("`r", '') }
    }
}
$script:IMPACT_DEFK = [hashtable]::new()
foreach ($x in @('part def', 'port def', 'constraint def', 'verification def', 'action def', 'item def', 'attribute def', 'enum def', 'use case def', 'requirement', 'requirement def')) { $script:IMPACT_DEFK[$x] = 1 }
function H-Copy($h) { $c = [hashtable]::new(); foreach ($k in $h.Keys) { $c[$k] = $h[$k] }; return $c }
function Xmi-Impact($d, [string]$dir, $o) {
    if (-not (Test-Path -LiteralPath $dir -PathType Container)) { throw "${dir}: not a directory`n" }
    $mtext = X-ReadTree $dir
    $model = X-V2Scan $mtext
    $co = $d.conv_old; $cn = $d.conv_new
    $oscan = X-V2Scan $co.files
    $nscan = X-V2Scan $cn.files
    $omap = [hashtable]::new(); foreach ($r in $co.map) { $omap[$r.id] = $r }
    $nmap = [hashtable]::new(); foreach ($r in $cn.map) { $nmap[$r.id] = $r }
    $notes = @()
    if ($null -ne $o.map) {
        $moved = 0
        foreach ($id in (SortOrd $o.map.Keys)) {
            $r = $o.map[$id]
            $cur = $omap[$id]; if ($null -eq $cur) { $cur = @{ def = ''; defkind = '' } }
            if ($null -ne $o.layout_map -and (PTrue $cur.file) -and $r.file -cne $cur.file) {
                $moved++
                $x = H-Copy $cur; $x.q = $r.q; $x.kind = $r.kind; $x.id = $id
                $omap[$id] = $x
                continue
            }
            $x = H-Copy $cur; foreach ($k in $r.Keys) { $x[$k] = $r[$k] }; $x.id = $id
            $omap[$id] = $x
        }
        if ($moved) { $notes += "--map: $moved row(s) name a path the layout map puts elsewhere; the layout map's paths are used" }
    }
    $doors = [hashtable]::new()
    foreach ($src in @($nscan.doors, $oscan.doors, $model.doors)) { foreach ($k in $src.Keys) { $doors[$k] = $src[$k] } }
    $rname = { param($x) $n = X-Last $x; if ($doors.ContainsKey($n) -and $null -ne $doors[$n]) { return $doors[$n] }; return $n }
    $req_all = [hashtable]::new(); $ver_all = [hashtable]::new(); $conn_all = [hashtable]::new(); $alloc_all = [hashtable]::new(); $edit_all = [hashtable]::new(); $items = @()
    foreach ($kind in @('added', 'removed', 'changed')) {
        foreach ($it in @($d[$kind])) {
            if ($kind -ceq 'added') { $srcs = @(,@($d.new, $nmap)) } elseif ($kind -ceq 'removed') { $srcs = @(,@($d.old, $omap)) } else { $srcs = @(@($d.old, $omap), @($d.new, $nmap)) }
            $v2 = @(); $seen = [hashtable]::new()
            foreach ($sp in $srcs) {
                $m = $sp[0]; $map = $sp[1]
                $ids = @(,@($it.id, 0))
                if ($it.type -cmatch '^(Abstraction|Dependency|Usage|Realization)$' -and $null -ne $m.el[$it.id]) {
                    foreach ($x in (IdRefs $m.el[$it.id] 'client')) { $ids += ,@($x, 1) }
                    foreach ($x in (IdRefs $m.el[$it.id] 'supplier')) { $ids += ,@($x, 1) }
                }
                foreach ($x in $ids) {
                    $r = $map[$x[0]]; if ($null -eq $r) { continue }
                    $sk = [string]$r.q + "`0" + [string]$r.kind
                    if ($seen.ContainsKey($sk)) { $seen[$sk]++; continue }
                    $seen[$sk] = 1
                    $c = H-Copy $r; $c.end = $x[1]; $v2 += ,$c
                }
            }
            $reqs = [hashtable]::new(); $vers = [hashtable]::new(); $conns = [hashtable]::new(); $allocs = [hashtable]::new(); $refs = @(); $edits = @()
            $names = [hashtable]::new(); $defs = [hashtable]::new()
            foreach ($r in $v2) {
                if ($r.kind -cmatch '^requirement') { $reqs[(& $rname $r.q)] = "$($r.file):$($r.line)" }
                if ($r.end) { continue }
                if ($script:IMPACT_DEFK.ContainsKey([string]$r.kind) -and $r.kind -cnotmatch '^requirement') { $names[(X-Last $r.q)] = 1; $defs[[string]$r.q] = 1 }
                if ($r.kind -cmatch '^(part|port|attribute|item|ref part|action|parameter|enum)$') { $names[(X-Last $r.q)] = 1 }
                if ((PTrue $r.def) -and (PTrue $r.defkind) -and $script:IMPACT_DEFK.ContainsKey([string]$r.defkind) -and $r.defkind -cnotmatch '^requirement') { $defs[$r.def] = 1 }
                if ((PTrue $r.def) -and (PTrue $r.defkind) -and $r.defkind -cnotmatch '^requirement|package' -and $r.kind -cne 'todo') { $names[(X-Last $r.def)] = 1 }
                if ($r.kind -ceq 'verify') { $vers[(X-Last $r.q)] = "$($r.file):$($r.line)" }
                if ([string]$r.defkind -ceq 'verification def' -and $r.kind -cne 'verify') { $vers[(X-Last $r.def)] = "$($r.file):$($r.line)" }
                if ($r.kind -ceq 'verification def' -and $r.q -cnotmatch '_verification(?:_[0-9]+)?$') { $vers[(X-Last $r.q)] = "$($r.file):$($r.line)" }
            }
            $own = [hashtable]::new(); foreach ($k in $defs.Keys) { $own[$k] = 1 }
            foreach ($s in $model.sat) {
                $hit = $false; foreach ($x in (X-Segs $s.by)) { if ($names.ContainsKey($x)) { $hit = $true } }
                if ($hit) { $rn = & $rname $s.req; if (-not $reqs.ContainsKey($rn)) { $reqs[$rn] = "$($s.file):$($s.line)" } }
            }
            $rq = [hashtable]::new(); foreach ($k in $reqs.Keys) { $rq[$k] = 1 }
            foreach ($v in $model.ver) { if ($rq.ContainsKey((& $rname $v.req))) { $vl = X-Last $v.ctx; if (-not $vers.ContainsKey($vl)) { $vers[$vl] = "$($v.file):$($v.line)" } } }
            $in_model = [hashtable]::new(); foreach ($dd in $model.defs.Values) { if ($dd.kind -cmatch '^requirement') { $in_model[(& $rname $dd.name)] = 1 } }
            foreach ($v in $nscan.ver) {
                $rn = & $rname $v.req
                if ($rq.ContainsKey($rn) -and -not $in_model.ContainsKey($rn)) { $vl = X-Last $v.ctx; if (-not $vers.ContainsKey($vl)) { $vers[$vl] = "$($v.file):$($v.line) (new drop)" } }
            }
            $usage = [hashtable]::new()
            foreach ($u in $model.use) { if ($names.ContainsKey((X-Last $u.type))) { $usage["$($u.ctx)`0$($u.name)"] = $u } }
            foreach ($c in $model.conn) {
                $hit = $false
                foreach ($e in $c.ends) {
                    $sg = (X-Segs $e)
                    $s0 = ''; if ($sg.Count -gt 0) { $s0 = $sg[0] }
                    if ($usage.ContainsKey("$($c.ctx)`0$s0")) { $hit = $true }
                    if ($defs.ContainsKey([string]$c.ctx) -and $names.ContainsKey($s0)) { $hit = $true }
                }
                if ($hit) { if (PTrue $c.name) { $ck = "$($c.ctx)::$($c.name)" } else { $ck = "$($c.ctx): $($c.text)" }; $conns[$ck] = "$($c.file):$($c.line)" }
            }
            foreach ($a in $model.alloc) {
                $hit = $false; foreach ($x in ((X-Segs $a.from) + (X-Segs $a.to))) { if ($names.ContainsKey($x)) { $hit = $true } }
                if ($hit) { $allocs["allocate $($a.from) to $($a.to)"] = "$($a.file):$($a.line)" }
            }
            $breaks = $kind -ceq 'removed'
            foreach ($w in @($it.what)) { if ($w -cmatch '^renamed|^moved') { $breaks = $true } }
            $refctx = [hashtable]::new()
            if ($breaks) {
                foreach ($u in $model.use) {
                    if (-not $names.ContainsKey((X-Last $u.type)) -or $u.ctx -eq '') { continue }
                    $refs += ,@{ what = "$($u.ctx)::$($u.name) : $($u.type)"; at = "$($u.file):$($u.line)" }
                    $refctx[$u.ctx] = 1
                }
            }
            $todo_seen = [hashtable]::new()
            foreach ($r in $v2) {
                if ($r.kind -cne 'todo' -or -not (PTrue $r.todo_id)) { continue }
                if ($todo_seen.ContainsKey($r.todo_id)) { continue }
                $todo_seen[$r.todo_id] = 1
                $needle = "(xmi:id $($r.todo_id))"
                $found = $false; foreach ($tv in $mtext.Values) { if ($tv.Contains($needle)) { $found = $true; break } }
                if ($found) { continue }
                $inq = $r.def; if (-not (PTrue $inq)) { $inq = $r.q }
                $edits += ,@{ what = 'TODO for ' + (X-TodoLabel $r) + ' closed by hand in ' + (X-Last $inq); where = $inq; at = (X-WhereIn $model $inq $r) }
            }
            $edited = [hashtable]::new(); foreach ($e in $edits) { $edited[[string]$e.where] = 1 }
            foreach ($q in ((SortOrd $defs.Keys) + (SortOrd $refctx.Keys))) {
                if ($edited.ContainsKey($q)) { $edited[$q]++; continue }
                $edited[$q] = 1
                $was = X-Block $oscan $q; $now = X-Block $model $q
                if ($null -eq $was) { continue }
                if ($null -eq $now) { $edits += ,@{ what = (X-Last $q) + ' was removed or moved by the government'; where = $q; at = '' }; continue }
                if ($was -ceq $now) { continue }
                $mid = ''; if ($refctx.ContainsKey($q) -and -not $own.ContainsKey($q)) { $mid = ' refers to it and' }
                $edits += ,@{ what = (X-Last $q) + $mid + ' was edited by the government since ' + (X-DropLabel $d.old); where = $q; at = "$($model.defs[$q].file):$($model.defs[$q].start)" }
            }
            foreach ($k in $reqs.Keys) { if (-not $req_all.ContainsKey($k)) { $req_all[$k] = $reqs[$k] } }
            foreach ($k in $vers.Keys) { if (-not $ver_all.ContainsKey($k)) { $ver_all[$k] = $vers[$k] } }
            foreach ($k in $conns.Keys) { if (-not $conn_all.ContainsKey($k)) { $conn_all[$k] = $conns[$k] } }
            foreach ($k in $allocs.Keys) { if (-not $alloc_all.ContainsKey($k)) { $alloc_all[$k] = $allocs[$k] } }
            foreach ($e in $edits) { if (-not $edit_all.ContainsKey($e.what)) { $edit_all[$e.what] = $e } }
            $items += ,@{ change = $kind; item = $it; v2 = $v2; reqs = $reqs; vers = $vers; conns = $conns; allocs = $allocs; refs = $refs; edits = $edits }
        }
    }
    $like_new = 0; $like_old = 0
    $dq = [hashtable]::new(); foreach ($x in $items) { foreach ($r in $x.v2) { foreach ($q in @($r.q, $r.def)) { if (PTrue $q) { $dq[$q] = 1 } } } }
    foreach ($q in (SortOrd $dq.Keys)) {
        $ob = X-Block $oscan $q; $nb = X-Block $nscan $q; $mb = X-Block $model $q
        if ($null -ne $ob -and $null -ne $nb -and $ob -ceq $nb) { continue }
        if ($null -eq $mb) { continue }
        if ($null -ne $nb -and $mb -ceq $nb) { $like_new++ }
        elseif ($null -ne $ob -and $mb -ceq $ob) { $like_old++ }
    }
    if ($like_new -and $like_new -gt $like_old) {
        $lbl = X-DropLabel $d.new; if (-not $lbl) { $lbl = 'NEW' }
        $notes += "warning: the model already contains ${lbl}: run --impact against develop before the drop is merged ($like_new changed definition(s) match the new drop, $like_old the old one); hand edits are not reported"
        foreach ($x in $items) { $x.edits = @() }
        $edit_all = [hashtable]::new()
    }
    $crs = $o.changes
    if ($null -ne $crs) {
        $of = [hashtable]::new(); foreach ($c in $crs) { foreach ($i in $c.ids) { if (-not $of.ContainsKey($i)) { $of[$i] = $c } } }
        foreach ($x in $items) {
            if ($x.change -ceq 'removed') { $m = $d.old } else { $m = $d.new }
            $cr = $null
            for ($p = $x.item.id; $null -ne $p -and $null -eq $cr; $p = $m.parent[$p]) { $cr = $of[$p] }
            $x.cr = $cr
        }
    }
    $ed = @(foreach ($k in (SortOrd $edit_all.Keys)) { $edit_all[$k] })
    return @{ dir = $dir; files = $mtext.Count; delta = $d; items = $items; reqs = $req_all; vers = $ver_all; changes = $crs; notes = $notes; conns = $conn_all; allocs = $alloc_all; edits = $ed }
}
function Xmi-ReadChangesCsv([string]$path) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "${path}: No such file or directory`n" }
    $text = (Read-TextFile $path).Replace("`r", '')
    $rows = Parse-Csv $text
    $head = $null; if ($rows.Count -gt 0) { $head = $rows[0] }
    if ($null -eq $head -or ($head -join ',') -cne 'cr_id,title,rationale,kind,xmi_ids,requirements') {
        throw "${path}: not a CHANGES.csv (expected the header cr_id,title,rationale,kind,xmi_ids,requirements)`n"
    }
    $out = @()
    for ($i = 1; $i -lt $rows.Count; $i++) {
        $r = $rows[$i]
        if ($r.Count -lt 4 -or $r[0] -eq '') { continue }
        $f = { param($j) if ($j -lt $r.Count -and $null -ne $r[$j]) { return $r[$j] }; return '' }
        $out += ,@{ cr = $r[0]; title = (& $f 1); rationale = (& $f 2); kind = (& $f 3); ids = (SplitWs (& $f 4)); reqs = (SplitWs (& $f 5)) }
    }
    return ,$out
}
function X-TodoLabel($r) {
    $q = [string](Dfl $r.q '')
    if ($q -cmatch '\(TODO ([A-Za-z0-9_]+)\)$') { $s = "uml:$($Matches[1])" } else { $s = X-Last $q }
    if ($null -ne $r.todo_name) { $s += " '$($r.todo_name)'" }
    return $s
}
function X-WhereIn($scan, $q, $r) { $d = $scan.defs[[string]$q]; if ($null -ne $d) { return "$($d.file):$($d.start)" }; return "$($r.file):$($r.line)" }
function Xmi-ImpactText($i) {
    $sym = @{ added = '+'; removed = '-'; changed = '~' }
    $l = @('', "impact on $($i.dir) ($($i.files) .sysml files)") + @($i.notes)
    $groups = @(,@($null, $i.items))
    if ($null -ne $i.changes) {
        $by = [hashtable]::new()
        foreach ($x in $i.items) { if ($x.cr) { $kk = $x.cr.cr } else { $kk = '' }; if (-not $by.ContainsKey($kk)) { $by[$kk] = @() }; $by[$kk] += ,$x }
        $groups = @(foreach ($c in $i.changes) { $xs = @(); if ($by.ContainsKey($c.cr)) { $xs = $by[$c.cr] }; ,@($c, $xs) })
        if ($by.ContainsKey('')) { $groups += ,@(@{ cr = '' }, $by['']) }
    }
    foreach ($g in $groups) {
        $cr = $g[0]; $xs = @($g[1])
        if ($cr) {
            if ($cr.cr -eq '') { $l += ''; $l += '== changes no change request names (ask the prime)' }
            else {
                $none = ''; if ($xs.Count -eq 0) { $none = ' (no change in this delta)' }
                $l += ''; $l += "== $($cr.cr) $($cr.kind): $($cr.title)$none"
                if ($cr.rationale -cmatch '[^ \t\n\r\f\v]') { $l += "   rationale: $($cr.rationale)" } else { $l += '   rationale: (none given -- ask the prime for clarification)' }
                if (@($cr.reqs).Count -gt 0) { $l += '   requirements: ' + (@($cr.reqs) -join ' ') }
            }
        }
        foreach ($x in $xs) {
            $it = $x.item
            $w = ''; if (@($it.what).Count -gt 0) { $w = ' -- ' + (@($it.what) -join '; ') }
            $l += ''; $l += "$($sym[$x.change]) uml:$($it.type) $($it.qname)$w"
            foreach ($r in $x.v2) { $l += "    v2: $($r.q) ($($r.kind), $($r.file):$([int]$r.line))" }
            if ($x.reqs.Count -gt 0) { $l += '    requirements: ' + ((SortOrd $x.reqs.Keys) -join ', ') }
            if ($x.vers.Count -gt 0) { $l += '    verification cases: ' + ((SortOrd $x.vers.Keys) -join ', ') }
            foreach ($k in (SortOrd $x.conns.Keys)) { $l += "    interface: $k ($($x.conns[$k]))" }
            foreach ($k in (SortOrd $x.allocs.Keys)) { $l += "    allocation: $k ($($x.allocs[$k]))" }
            foreach ($r in $x.refs) { $l += "    referenced by: $($r.what) ($($r.at))" }
            foreach ($e in $x.edits) { $at = ''; if ($e.at) { $at = " ($($e.at))" }; $l += "    hand edit: $($e.what)$at" }
        }
    }
    $l += ''; $l += 'impact summary:'
    $l += (PadR 'requirements touched' 28) + ' ' + (PadL $i.reqs.Count 3) + '  ' + ((SortOrd $i.reqs.Keys) -join ', ')
    $l += (PadR 'verification cases touched' 28) + ' ' + (PadL $i.vers.Count 3) + '  ' + ((SortOrd $i.vers.Keys) -join ', ')
    $l += (PadR 'interfaces touched' 28) + ' ' + (PadL $i.conns.Count 3) + '  ' + ((SortOrd $i.conns.Keys) -join '; ')
    $l += (PadR 'allocations touched' 28) + ' ' + (PadL $i.allocs.Count 3) + '  ' + ((SortOrd $i.allocs.Keys) -join '; ')
    $last = (PadR 'hand edits to redo' 28) + ' ' + (PadL @($i.edits).Count 3)
    if ($null -ne $i.changes) {
        $norat = @(foreach ($c in $i.changes) { if ($c.rationale -cnotmatch '[^ \t\n\r\f\v]') { $c } })
        $loose = 0; foreach ($x in $i.items) { if (-not $x.cr) { $loose++ } }
        $l += (PadR 'change requests' 28) + ' ' + (PadL @($i.changes).Count 3) + '  ' + (@($i.changes | ForEach-Object { $_.cr }) -join ' ')
        $l += (PadR 'without a rationale' 28) + ' ' + (PadL $norat.Count 3) + '  ' + (@($norat | ForEach-Object { $_.cr }) -join ' ')
        $l += (PadR 'changes no CR names' 28) + ' ' + (PadL $loose 3)
    }
    $l += $last
    foreach ($e in $i.edits) { $at = ''; if ($e.at) { $at = " ($($e.at))" }; $l += "  [ ] $($e.what)$at" }
    return ($l -join "`n") + "`n"
}
function Xmi-ImpactCsv($i) {
    $t = "change,xmi_id,v1_type,v1_qualified_name,category,v2_name,file,line,detail,cr_id`n"
    $rows = @()
    $row = {
        param($x, $cat, $name, $at, $detail)
        $f = ''; $ln = ''
        if ([string](Dfl $at '') -cmatch '^([\s\S]*):([0-9]+)$') { $f = $Matches[1]; $ln = $Matches[2] }
        $cr = ''; if ($x.cr) { $cr = $x.cr.cr }
        return ((@(foreach ($v in @($x.change, $x.item.id, "uml:$($x.item.type)", $x.item.qname, $cat, $name, $f, $ln, (Dfl $detail ''), $cr)) { Csvf $v })) -join ',')
    }
    foreach ($x in $i.items) {
        foreach ($r in $x.v2) { $rows += (& $row $x 'v2' $r.q "$($r.file):$($r.line)" $r.kind) }
        foreach ($k in (SortOrd $x.reqs.Keys)) { $rows += (& $row $x 'requirement' $k $x.reqs[$k] $null) }
        foreach ($k in (SortOrd $x.vers.Keys)) { $rows += (& $row $x 'verification' $k $x.vers[$k] $null) }
        foreach ($k in (SortOrd $x.conns.Keys)) { $rows += (& $row $x 'interface' $k $x.conns[$k] $null) }
        foreach ($k in (SortOrd $x.allocs.Keys)) { $rows += (& $row $x 'allocation' $k $x.allocs[$k] $null) }
        foreach ($r in $x.refs) { $rows += (& $row $x 'reference' $r.what $r.at $null) }
        foreach ($e in $x.edits) { $rows += (& $row $x 'hand-edit' $e.where $e.at $e.what) }
    }
    if ($rows.Count -gt 0) { $t += ($rows -join "`n") + "`n" }
    return $t
}

# ================================================================ the command line (bin/xmi2sysml.pl)
# Getopt::Long's rules: --opt VALUE, --opt=VALUE, one or two dashes, unique abbreviations, options anywhere, -- ends them.
function Get-Opts([string[]]$argv, $spec, [string]$prog) {     # spec: name => 's' (string) | '' (flag); -> @(opts, rest, ok)
    $o = [hashtable]::new(); $rest = @(); $ok = $true
    for ($i = 0; $i -lt $argv.Count; $i++) {
        $a = $argv[$i]
        if ($a -ceq '--') { $rest += @($argv[($i + 1)..($argv.Count - 1)] | Where-Object { $null -ne $_ }); break }
        if ($a -cnotmatch '^--?([A-Za-z][A-Za-z0-9_-]*|h)(=([\s\S]*))?$' -or $a -ceq '-') { $rest += $a; continue }
        $nm = $Matches[1]; $hasv = $null -ne $Matches[2]; $val = $Matches[3]
        $hits = @(foreach ($k in $spec.Keys) { if ($k -ceq $nm) { $k } })
        if ($hits.Count -eq 0) { $hits = @(foreach ($k in $spec.Keys) { if ($k.StartsWith($nm)) { $k } }) }
        if ($hits.Count -ne 1) {
            if ($hits.Count -gt 1) { Out-Err "Option $nm is ambiguous ($((SortOrd $hits) -join ', '))" } else { Out-Err "Unknown option: $nm" }
            $ok = $false; continue
        }
        $k = $hits[0]
        if ($spec[$k] -ceq 's') {
            if (-not $hasv) {
                if ($i + 1 -ge $argv.Count) { Out-Err "Option $k requires an argument"; $ok = $false; continue }
                $i++; $val = $argv[$i]
            }
            $o[$k] = $val
        } else {
            if ($hasv) { Out-Err "Option $k does not take an argument"; $ok = $false; continue }
            $o[$k] = 1
        }
    }
    return ,@($o, $rest, $ok)
}

function Main-Xmi2Sysml([string[]]$argv) {
    $spec = @{ 'out' = 's'; 'layout' = 's'; 'layout-map' = 's'; 'report' = ''; 'stdout' = ''; 'req-style' = 's'; 'name' = 's'; 'check' = ''; 'delta' = ''; 'map' = 's'; 'impact' = 's'; 'impact-csv' = 's'; 'help' = ''; 'h' = '' }
    $g = Get-Opts $argv $spec 'xmi2sysml'
    $o = $g[0]; $ARGVr = @($g[1])
    if (-not $g[2]) { $script:RC = 2; return }
    if (-not $o.ContainsKey('layout')) { $o['layout'] = '{seg}/{pkg}.sysml' }
    if (-not $o.ContainsKey('req-style')) { $o['req-style'] = 'usage' }
    $help = $o.ContainsKey('help') -or $o.ContainsKey('h')
    $want = 1; if ($o.ContainsKey('delta')) { $want = 2 }
    if ($help -or $ARGVr.Count -ne $want) {
        Out-Err ("usage: xmi2sysml.pl [--report] [--out DIR [--layout '{seg}/{pkg}.sysml' | --layout-map FILE] | --stdout]`n" +
                 "                     [--req-style usage|def] [--name PKG] [--check] FILE.xmi`n" +
                 "                     [--map MAP.csv] FILE.xmi`n" +
                 "       xmi2sysml.pl --delta OLD.xmi NEW.xmi [--impact MODEL_DIR [--map OLD-MAP.csv] [--impact-csv FILE]]")
        if ($help) { $script:RC = 0; return }; $script:RC = 2; return
    }
    if ($o['req-style'] -cnotmatch '^(def|usage)$') { Out-Err 'xmi2sysml: --req-style is def or usage'; $script:RC = 255; return }
    if ($o.ContainsKey('impact') -and -not $o.ContainsKey('delta')) { Out-Err 'xmi2sysml: --impact needs --delta OLD.xmi NEW.xmi'; $script:RC = 2; return }
    if ($o.ContainsKey('impact-csv') -and -not $o.ContainsKey('impact')) { Out-Err 'xmi2sysml: --impact-csv needs --impact MODEL_DIR'; $script:RC = 2; return }
    if ($o.ContainsKey('impact') -and -not (Test-Path -LiteralPath $o['impact'] -PathType Container)) { Out-Err "xmi2sysml: --impact $($o['impact']): not a directory"; $script:RC = 2; return }
    $lm = $null
    if ($o.ContainsKey('layout-map')) {
        try { $lm = Read-LayoutMap $o['layout-map'] } catch { Out-Err ("xmi2sysml: --layout-map " + ($_.Exception.Message -creplace '\n$', '')); $script:RC = 2; return }
    }
    $copts = @{ req_style = $o['req-style']; layout = $o['layout']; name = $o['name']; layout_map = $lm }
    if ($o.ContainsKey('delta')) {
        $ms = @()
        foreach ($f in $ARGVr) { try { $ms += ,(Xmi-Load $f) } catch { Out-Err ("xmi2sysml: " + $_.Exception.Message); $script:RC = 2; return } }
        $d = Xmi-Delta $ms[0] $ms[1] $copts
        Out-Text (Xmi-DeltaText $d)
        if ($o.ContainsKey('impact')) {
            $map = $null
            if ($o.ContainsKey('map')) { try { $map = Xmi-ReadMapCsv $o['map'] } catch { Out-Err ("xmi2sysml: --map " + $_.Exception.Message); $script:RC = 2; return } }
            $cdir = $ARGVr[1] -creplace '[^/\\]*$', ''
            if ($cdir -eq '') { $cf = 'CHANGES.csv' } else { $cf = $cdir + '/CHANGES.csv' }
            $changes = $null
            if (Test-Path -LiteralPath $cf -PathType Leaf) { try { $changes = Xmi-ReadChangesCsv $cf } catch { Out-Err ("xmi2sysml: " + $_.Exception.Message); $script:RC = 2; return } }
            $iopts = @{ map = $map; changes = $changes; layout_map = $lm }
            $im = Xmi-Impact $d $o['impact'] $iopts
            Out-Text (Xmi-ImpactText $im)
            if ($o.ContainsKey('impact-csv')) { Write-TextFile $o['impact-csv'] (Xmi-ImpactCsv $im) }
        }
        $script:RC = 0; return
    }
    try { $m = Xmi-Load $ARGVr[0] } catch { Out-Err ("xmi2sysml: " + $_.Exception.Message); $script:RC = 2; return }
    $out = Xmi-Convert $m $copts
    $files = $out.files
    $bad = 0; if (@($out.problems).Count -gt 0) { $bad = 1 }
    if ($o.ContainsKey('out')) {
        foreach ($f in (SortOrd $files.Keys)) { Write-TextFile ($o['out'] + '/' + $f) $files[$f] }
        if ($o.ContainsKey('check')) {
            $chk = Join-Path $PSScriptRoot 'sysml.ps1'
            if ($PSScriptRoot -and (Test-Path -LiteralPath $chk -PathType Leaf)) {
                $fl = @(foreach ($f in (SortOrd $files.Keys)) { $o['out'] + '/' + $f })
                & $chk check @fl
                if ($LASTEXITCODE) { $bad = 1 }
            } else { Out-Err 'xmi2sysml: tools/sysml/sysml.pl not found; structural self-check only' }
        }
    }
    if ($o.ContainsKey('stdout')) { Out-Text (-join @(foreach ($f in (SortOrd $files.Keys)) { "// file: $f`n" + $files[$f] })) }
    if ($o.ContainsKey('map')) { Write-TextFile $o['map'] (Xmi-MapCsv $m $out) }
    $rep = Xmi-ReportText $out
    if ($o.ContainsKey('report')) { Out-Text $rep }
    elseif ($o.ContainsKey('out') -or $o.ContainsKey('stdout') -or $o.ContainsKey('map')) {
        $r = $out.report
        $pc = @($out.problems).Count
        $sc = 'ok'; if ($pc -gt 0) { $sc = "$pc problem(s)" }
        Out-Err ("xmi2sysml: $($r.total) elements in, $($r.scope_done) of $($r.scope) in scope ported, $(@($r.unmapped).Count) TODO, $($files.Count) file(s), self-check $sc")
        foreach ($p in @($out.problems)) { Out-Err "  $p" }
        foreach ($p in @($r.layout)) { Out-Err "  $p" }
    }
    else { Out-Err 'xmi2sysml: nothing to do: give --out DIR, --stdout or --report'; $script:RC = 2; return }
    $script:RC = $bad; return
}

if ($args.Count -ge 1 -and $args[0] -ceq '__lib') { return }   # dot-source with __lib: the functions only (tests)
$script:RC = 0
try { Main-Xmi2Sysml ([string[]]@($args)) }
catch { Out-Err ("xmi2sysml: " + ($_.Exception.Message -creplace '\n$', '')); if ($env:XMI2SYSML_DEBUG) { Out-Err $_.InvocationInfo.PositionMessage; Out-Err $_.ScriptStackTrace }; $script:RC = 255 }
if ($PSCommandPath) { exit $script:RC }
$global:LASTEXITCODE = $script:RC
