<#
v1v2.ps1 -- move a SysML v1 model exported from an older Cameo (no SysML v2 plugin) toward SysML v2 text.
A Windows PowerShell 5.1 port of the kit's tools/sysml/v1v2.pl, safe under Constrained Language Mode: no Add-Type,
no COM, no .NET outside the core types. Same commands and options, same output and files, same exit codes.

  v1v2.ps1 inventory MODEL [--tsv]
  v1v2.ps1 check     MODEL [--typemap F]
  v1v2.ps1 convert   MODEL -o DIR [--package V1::QN] [--prefix P] [--marking LEVEL]
                     [--keep-names] [--no-provenance] [--typemap F]
  v1v2.ps1 reqs      REQS -o FILE.sysml --package NAME [--marking LEVEL]
                     [--id COL] [--name COL] [--text COL] [--parent COL]

MODEL is a UML/SysML 1.x XMI export (.xmi, .uml, .xml) or a Cameo .mdzip (read with ziplib.ps1, beside this folder or
in it). REQS is a ReqIF file (.reqif, .reqifz) or a CSV export of a requirement table.
Diagnostics are GNU format (file:line: severity: message), then a summary line.
Exit status: 0 clean, 1 findings, 2 usage or input error.
Messages Perl writes to STDERR are written with Write-Host, so they never mix into redirected output.
#>
$ErrorActionPreference = 'Stop'

# ================================================================ helpers
function Out-Text([string]$t) {
    if ($null -eq $t -or $t -eq '') { return }
    if ($t.EndsWith("`n")) { $t = $t.Substring(0, $t.Length - 1) }
    foreach ($l in ($t -split "`n")) { Write-Output $l }
}
function Out-Err([string]$t) {
    if ($null -eq $t -or $t -eq '') { return }
    if ($t.EndsWith("`n")) { $t = $t.Substring(0, $t.Length - 1) }
    foreach ($l in ($t -split "`n")) { Write-Host $l }
}
function SortOrd($a) { $c = [string[]]@($a); if ($c.Count -lt 2) { return ,$c }; [Array]::Sort($c, [StringComparer]::Ordinal); return ,$c }
function SortByKey($items, $keys) {
    $it = [object[]]@($items)
    if ($it.Count -lt 2) { return ,$it }
    $k = New-Object string[] $it.Count
    $kk = @($keys)
    for ($i = 0; $i -lt $it.Count; $i++) { $k[$i] = [string]$kk[$i] + "`0" + ('{0:D9}' -f $i) }
    [Array]::Sort($k, [StringComparer]::Ordinal)
    $out = New-Object object[] $it.Count
    for ($i = 0; $i -lt $k.Count; $i++) { $out[$i] = $it[[int]$k[$i].Substring($k[$i].Length - 9)] }
    return ,$out
}
function NumKey([long]$n) { return ('{0:D15}' -f ($n + 100000000000000)) }        # sorts numbers as text (ordinal)
function NumKeyDesc([long]$n) { return ('{0:D15}' -f (100000000000000 - $n)) }
function Dfl($v, $d) { if ($null -eq $v) { return $d }; return $v }
function PTrue($v) {
    if ($null -eq $v) { return $false }
    if ($v -is [string]) { return ($v -ne '' -and $v -ne '0') }
    if ($v -is [bool]) { return $v }
    if ($v -is [int] -or $v -is [long] -or $v -is [double]) { return ($v -ne 0) }
    return $true
}
function NLCount([string]$s) { if ($null -eq $s -or $s -eq '') { return 0 }; return $s.Length - $s.Replace("`n", '').Length }
function Fail([string]$m) { Out-Err "v1v2: $m"; throw 'V1V2EXIT2' }
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
function Base-Name([string]$p) { return ($p -creplace '^[\s\S]*[/\\]', '') }
function UcFirst([string]$s) { if ($null -eq $s -or $s -eq '') { return $s }; return $s.Substring(0, 1).ToUpperInvariant() + $s.Substring(1) }
function LcFirst([string]$s) { if ($null -eq $s -or $s -eq '') { return $s }; return $s.Substring(0, 1).ToLowerInvariant() + $s.Substring(1) }

# ================================================================ input: decode, unzip, parse
# Bytes -> text: UTF-8 when the bytes are valid UTF-8, else Windows-1252 (the system ANSI code page). Read through a
# file because CLM refuses the Encoding classes.
function Decode-Bytes([byte[]]$raw, [string]$path) {
    $tmp = $null
    if (-not $path) {
        $tmp = Join-Path $env:TEMP ('v1v2-' + [string](Get-Random) + '.bin')
        Set-Content -LiteralPath $tmp -Value $raw -Encoding Byte
        $path = $tmp
    }
    try {
        $t = Get-Content -LiteralPath $path -Raw -Encoding UTF8
        if ($null -eq $t) { $t = '' }
        if ($t.IndexOf([char]0xFFFD) -ge 0) {
            $hasRepl = $false
            for ($i = 0; $i + 2 -lt $raw.Count; $i++) { if ($raw[$i] -eq 0xEF -and $raw[$i + 1] -eq 0xBF -and $raw[$i + 2] -eq 0xBD) { $hasRepl = $true; break } }
            if (-not $hasRepl) { $t = Get-Content -LiteralPath $path -Raw -Encoding Default; if ($null -eq $t) { $t = '' } }
        }
        # Get-Content -Encoding UTF8 drops a UTF-8 BOM; Perl strips the U+FEFF it decodes to: the same
        if ($t.Length -gt 0 -and [int]$t[0] -eq 0xFEFF) { $t = $t.Substring(1) }
        return ($t -creplace "`r`n?", "`n")
    } finally { if ($tmp) { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue } }
}
function Slurp([string]$f) {
    if ($f -match '\.(?:mdzip|reqifz|zip)$') { $raw = From-Zip $f; return (Decode-Bytes $raw $null) }
    if (-not (Test-Path -LiteralPath $f -PathType Leaf)) { Fail "${f}: No such file or directory" }
    $raw = Get-Content -LiteralPath $f -Encoding Byte -ReadCount 0
    if ($null -eq $raw) { return '' }
    return (Decode-Bytes ([byte[]]$raw) $f)
}
function From-Zip([string]$f) {
    $zl = $null
    foreach ($c in @((Join-Path $PSScriptRoot 'ziplib.ps1'), (Join-Path (Split-Path -Parent $PSScriptRoot) 'ziplib.ps1'))) { if ($PSScriptRoot -and (Test-Path -LiteralPath $c -PathType Leaf)) { $zl = $c; break } }
    if (-not $zl) { Fail "${f}: ziplib.ps1 is not available; unzip the file and pass the model file inside it" }
    . $zl
    if (-not (Test-Path -LiteralPath $f -PathType Leaf)) { Fail "${f}: not a readable zip" }
    try { $ents = @(foreach ($x in (Read-ZipEntries -Path $f)) { $x }) } catch { Fail "${f}: not a readable zip" }
    $best = $null; $bestLen = -1; $name = ''
    foreach ($e in $ents) {
        $member = [string]$e.name
        if ($member.EndsWith('/')) { continue }
        try { $data = [byte[]](Read-ZipEntry -Path $f -Name $member) } catch { Fail "${f}: corrupt member $member" }
        if ($null -eq $data) { continue }
        if ($data.Length -le $bestLen) { continue }
        $all = ''; if ($data.Length -gt 0) { $all = -join [char[]]$data }
        if ($all -cmatch '<(?:xmi:XMI|uml:Model|REQ-IF)\b') { $best = $data; $bestLen = $data.Length; $name = $member }
    }
    if ($bestLen -le 0) { Fail "${f}: no XMI or ReqIF member found" }
    Out-Err "v1v2: ${f}: using member $name"
    return ,$best
}

$script:ENT = @{}
$script:ENT['lt'] = '<'; $script:ENT['gt'] = '>'; $script:ENT['amp'] = '&'; $script:ENT['quot'] = '"'; $script:ENT['apos'] = "'"
$script:ENTRE = [regex]'&(#[xX][0-9a-fA-F]+|#\d+|\w+);'
function Unent([string]$s) {
    if ($null -eq $s -or $s.IndexOf('&') -lt 0) { return $s }
    $ms = $script:ENTRE.Matches($s)
    if ($ms.Count -eq 0) { return $s }
    $out = ''; $at = 0
    foreach ($m in $ms) {
        $e = $m.Groups[1].Value
        if ($e -cmatch '^#[xX]') { $r = [char]::ConvertFromUtf32([int]('0x' + $e.Substring(2))) }
        elseif ($e -cmatch '^#') { $r = [char]::ConvertFromUtf32([int]$e.Substring(1)) }
        elseif ($script:ENT.ContainsKey($e) -and $e -cmatch '^(lt|gt|amp|quot|apos)$') { $r = $script:ENT[$e] }
        else { $r = "&$e;" }
        $out += $s.Substring($at, $m.Index - $at) + $r; $at = $m.Index + $m.Length
    }
    return $out + $s.Substring($at)
}

$script:PX_TEXT = [regex]'\G([^<]+)'
$script:PX_SPECIAL = [regex]'\G<(!--|!\[CDATA\[|\?|!)'
$script:PX_END = [regex]'\G</([^\s>]+)\s*>'
$script:PX_START = [regex]'\G<([^\s/>!?]+)((?:\s+[^\s=/>]+\s*=\s*(?:"[^"]*"|''[^'']*''))*)\s*(/?)>'
$script:PX_ATTR = [regex]'([^\s=]+)\s*=\s*(?:"([^"]*)"|''([^'']*)'')'
# Node: @{ tag; a (attrs); kids; line; up }. Text is kept as '#text' kids. Tags in $skip are skipped whole.
function Parse-Xml([string]$t, [string]$file, $skip) {
    $doc = @{ tag = '#doc'; a = [hashtable]::new(); kids = @(); line = 1 }
    $st = @($doc); $line = 1; $len = $t.Length; $skipped = 0; $pos = 0
    while ($pos -lt $len) {
        $m = $script:PX_TEXT.Match($t, $pos)
        if ($m.Success) {
            $s = $m.Groups[1].Value; $line += $s.Length - $s.Replace("`n", '').Length
            if ($s -match '\S') { $top = $st[$st.Count - 1]; $top.kids += ,@{ tag = '#text'; text = (Unent $s) } }
            $pos += $m.Length; continue
        }
        $m = $script:PX_SPECIAL.Match($t, $pos)
        if ($m.Success) {
            $open = $m.Groups[1].Value
            if ($open -ceq '!--') { $close = '-->' } elseif ($open -ceq '?') { $close = '?>' } elseif ($open -ceq '!') { $close = '>' } else { $close = ']]>' }
            $from = $m.Index + $m.Length; $end = $t.IndexOf($close, $from)
            if ($end -lt 0) { throw "${file}:${line}: error: no closing '$close'`n" }
            $s = $t.Substring($from, $end - $from)
            $pos = $end + $close.Length
            $line += $s.Length - $s.Replace("`n", '').Length
            if ($open -ceq '![CDATA[') { $top = $st[$st.Count - 1]; $top.kids += ,@{ tag = '#text'; text = $s } }
            continue
        }
        $m = $script:PX_END.Match($t, $pos)
        if ($m.Success) {
            $tg = $m.Groups[1].Value
            if ($st.Count -lt 2 -or $st[$st.Count - 1].tag -cne $tg) { throw "${file}:${line}: error: unexpected </$tg>`n" }
            $st = $st[0..($st.Count - 2)]
            $pos += $m.Length; continue
        }
        $m = $script:PX_START.Match($t, $pos)
        if ($m.Success) {
            $tag = $m.Groups[1].Value; $as = $m.Groups[2].Value; $empty = $m.Groups[3].Value -ceq '/'
            $n = @{ tag = $tag; a = [hashtable]::new(); kids = @(); line = $line; up = $st[$st.Count - 1] }
            foreach ($am in $script:PX_ATTR.Matches($as)) {
                if ($am.Groups[2].Success) { $v = $am.Groups[2].Value } else { $v = $am.Groups[3].Value }
                $n.a[$am.Groups[1].Value] = Unent $v
            }
            $line += $as.Length - $as.Replace("`n", '').Length
            $pos = $m.Index + $m.Length
            if ($null -ne $skip -and $skip.ContainsKey($tag)) {
                $skipped++
                if ($empty) { continue }
                $depth = 1; $from = $pos
                $re = [regex]('\G[\s\S]*?<(/?)' + [regex]::Escape($tag) + '(?=[\s/>])[^>]*?(/?)>')
                while ($depth) {
                    $sm = $re.Match($t, $pos)
                    if (-not $sm.Success) { break }
                    if ($sm.Groups[1].Value -ne '') { $depth-- } elseif ($sm.Groups[2].Value -eq '') { $depth++ }
                    $pos = $sm.Index + $sm.Length
                }
                if ($depth) { throw "${file}:$($n.line): error: unclosed <$tag>`n" }
                $seg = $t.Substring($from, $pos - $from); $line += $seg.Length - $seg.Replace("`n", '').Length
                continue
            }
            $top = $st[$st.Count - 1]; $top.kids += ,$n
            if (-not $empty) { $st += ,$n }
            continue
        }
        $near = $t.Substring($pos); if ($near.Length -gt 30) { $near = $near.Substring(0, 30) }
        throw "${file}:${line}: error: malformed XML near '$near'`n"
    }
    if ($st.Count -gt 1) { throw "${file}:${line}: error: unclosed <$($st[$st.Count - 1].tag)>`n" }
    return ,@($doc, $skipped)
}
function Text-Of($n) { if ($n.tag -ceq '#text') { return $n.text }; return (-join @(foreach ($k in $n.kids) { Text-Of $k })) }
function Elems($n) { return ,@(foreach ($k in $n.kids) { if ($k.tag -cne '#text') { $k } }) }
function Kid($n, [string]$tag) { foreach ($k in $n.kids) { if ($k.tag -cne '#text' -and $k.tag -ceq $tag) { return $k } }; return $null }

# ================================================================ the v1 model
$script:OPT = @{ provenance = 1 }
$script:ELEMS = [hashtable]::new(); $script:ALLREC = @(); $script:XMLNS = [hashtable]::new(); $script:MODEL = $null; $script:NSKIP = 0; $script:TYPEMAP = [hashtable]::new()
$script:SYSML_PREFIX = [hashtable]::new()
foreach ($k in (-split 'sysml SysML Blocks Requirements PortsAndFlows ConstraintBlocks Activities Allocations ModelElements DeprecatedElements StandardProfile StandardProfileL2 StandardProfileL3 l2 l3 MD_Customization_for_SysML__additional_stereotypes MD_Customization_for_Requirements__additional_stereotypes UML_Standard_Profile MagicDraw_Profile Validation_Profile DSL_Customization')) { $script:SYSML_PREFIX[$k] = 1 }

function Load-Model([string]$file) {
    $text = Slurp $file
    try { $r = Parse-Xml $text $file @{ 'xmi:Extension' = 1 } } catch { Out-Err ($_.Exception.Message -creplace '\n$', ''); throw 'V1V2EXIT2' }
    $doc = $r[0]; $script:NSKIP = $r[1]
    $els = Elems $doc
    if ($els.Count -eq 0) { Fail "${file}: empty document" }
    $root = $els[0]
    foreach ($k in $root.a.Keys) { if ($k -cmatch '^xmlns:(.+)') { $script:XMLNS[$Matches[1]] = $root.a[$k] } }
    $script:STEREO = @()
    $script:ALLREC = @(Walk-Model $root $null)
    foreach ($s in $script:STEREO) {
        $prefix = ''; $sname = $s.tag
        if ($s.tag -cmatch '^(?:([^:]+):)?(.+)$') { $sname = $Matches[2]; if ($Matches[1]) { $prefix = $Matches[1] } }
        $a = [hashtable]::new()
        foreach ($k in $s.a.Keys) { $a[$k.ToLowerInvariant()] = $s.a[$k] }
        foreach ($k in (Elems $s)) {
            if ((PTrue $k.a['xmi:idref']) -or (PTrue $k.a['href'])) { continue }
            $a[$k.tag.ToLowerInvariant()] = Text-Of $k
        }
        $uri = [string](Dfl $script:XMLNS[$prefix] '')
        $custom = (-not $script:SYSML_PREFIX.ContainsKey($prefix)) -and ($uri -notmatch 'omg\.org')
        foreach ($base in (SortOrd $s.a.Keys)) {
            if ($base -cnotmatch '^base_') { continue }
            $t = $script:ELEMS[$s.a[$base]]; if ($null -eq $t) { continue }
            $t.st += ,@{ name = $sname; prefix = $prefix; a = $a; custom = $custom; line = $s.line }
        }
    }
    foreach ($e in $script:ALLREC) { [void](Kind-Of $e) }
    foreach ($e in $script:ALLREC) { $e.inside = Inside-Of $e }
    if ($script:OPT.ContainsKey('typemap')) { Load-Typemap $script:OPT['typemap'] }
}
function Walk-Model($n, $owner) {                       # emits the element records in document order
    $id = $n.a['xmi:id']
    $rec = $owner
    if ($null -ne $id) {
        foreach ($k in $n.a.Keys) { if ($k -cmatch '^base_') { $script:STEREO += ,$n; return } }
        $type = $n.a['xmi:type']; if ($null -eq $type) { if ($n.tag -cmatch '^uml:') { $type = $n.tag } else { $type = '' } }
        $rec = @{ id = $id; type = $type; node = $n; owner = $owner; line = $n.line; name = (Name-Of $n); st = @(); kids = @() }
        $script:ELEMS[$id] = $rec
        $rec
        if ($null -ne $owner) { $owner.kids += ,$rec }
        if ($null -eq $script:MODEL -and $type -ceq 'uml:Model') { $script:MODEL = $rec }
    }
    foreach ($k in $n.kids) { if ($k.tag -cne '#text') { Walk-Model $k $rec } }
}
function Name-Of($n) {
    if ($null -ne $n.a['name']) { return $n.a['name'] }
    $k = Kid $n 'name'
    if ($null -ne $k) { return (Text-Of $k) }
    return ''
}
function Has-St($e, [string]$re) { foreach ($s in $e.st) { if ($s.name -cmatch $re) { return $true } }; return $false }
function St-Attr($e, [string]$key) { foreach ($s in $e.st) { if ($null -ne $s.a[$key]) { return $s.a[$key] } }; return $null }
function Is-ReqSt([string]$n) { return ($n -cmatch 'requirement$' -or $n -match 'requirement$' -or $n -ceq 'designConstraint') }
$script:TRACE_ST = @{}
foreach ($kv in @(@('Satisfy','satisfy'), @('Verify','verify'), @('DeriveReqt','derive'), @('Refine','refine'), @('Trace','trace'), @('Copy','copy'), @('Allocate','allocate'))) { $script:TRACE_ST[$kv[0]] = $kv[1] }
function Kind-Of($e) {
    if ($e.kind) { return $e.kind }
    $t = $e.type
    $s = [hashtable]::new(); foreach ($x in $e.st) { $s[$x.name] = 1 }
    $tr = $null; foreach ($x in $e.st) { if ($script:TRACE_ST.ContainsKey($x.name) -and $script:TRACE_ST[$x.name] -ceq $script:TRACE_ST[$x.name]) { $tr = $x.name; break } }
    $isreq = $false; foreach ($x in $s.Keys) { if (Is-ReqSt $x) { $isreq = $true } }
    if ($t -ceq 'uml:Model') { $k = 'model' }
    elseif ($t -ceq 'uml:Profile') { $k = 'profile' }
    elseif ($t -ceq 'uml:Package') { $k = 'package' }
    elseif ($t -ceq 'uml:Class' -and $isreq) { $k = 'requirement' }
    elseif ($t -ceq 'uml:Class' -and $s.ContainsKey('InterfaceBlock')) { $k = 'interfaceblock' }
    elseif ($t -ceq 'uml:Class' -and $s.ContainsKey('ConstraintBlock')) { $k = 'constraintblock' }
    elseif ($t -ceq 'uml:Class' -and $s.ContainsKey('Block')) { $k = 'block' }
    elseif ($t -ceq 'uml:Class') { $k = 'class' }
    elseif ($t -ceq 'uml:Enumeration') { $k = 'enum' }
    elseif ($t -cmatch '^uml:(?:DataType|PrimitiveType)$') { $k = 'valuetype' }
    elseif ($t -ceq 'uml:EnumerationLiteral') { $k = 'literal' }
    elseif ($t -ceq 'uml:Port') { $k = 'port' }
    elseif ($t -ceq 'uml:Property' -and $null -ne $e.owner -and $e.owner.type -ceq 'uml:Association') { $k = 'assocend' }
    elseif ($t -ceq 'uml:Property') { $k = 'property' }
    elseif ($t -ceq 'uml:Connector') { $k = 'connector' }
    elseif ($t -cmatch '^uml:(?:Abstraction|Dependency|Realization|Usage)$') { if ($tr) { $k = $script:TRACE_ST[$tr] } else { $k = 'dependency' } }
    elseif ($t -ceq 'uml:Generalization') { $k = 'generalization' }
    elseif ($t -ceq 'uml:Comment') { $k = 'comment' }
    elseif ($t -cmatch '^uml:(?:Activity|StateMachine|Interaction|OpaqueBehavior|FunctionBehavior)$') { $k = 'behavior' }
    elseif ($t -cmatch '^uml:(?:UseCase|Actor)$') { $k = 'usecase' }
    elseif ($t -ceq 'uml:Association') { $k = 'association' }
    elseif ($t -ceq 'uml:InformationFlow') { $k = 'itemflow' }
    elseif ($t -ceq 'uml:InstanceSpecification') { $k = 'instance' }
    elseif ($t -ceq 'uml:Constraint') { $k = 'constraint' }
    elseif ($t -ceq 'uml:Operation') { $k = 'operation' }
    else { $k = 'other' }
    $e.kind = $k
    return $k
}
function Inside-Of($e) {
    for ($o = $e.owner; $null -ne $o; $o = $o.owner) { if ($o.kind -cmatch '^(?:behavior|usecase|instance|constraint|other|profile|operation)$') { return 1 } }
    return 0
}
function Refs($n, [string]$attr) {
    $r = @()
    if ($null -ne $n.a[$attr]) { foreach ($x in (-split $n.a[$attr])) { if ($x -ne '') { $r += $x } } }
    foreach ($k in $n.kids) {
        if ($k.tag -ceq '#text' -or $k.tag -cne $attr) { continue }
        if ($null -ne $k.a['xmi:idref']) { $r += $k.a['xmi:idref'] }
        elseif ($null -ne $k.a['href']) { $h = $k.a['href']; if ($h -cmatch '^#([\s\S]+)') { $r += $Matches[1] } else { $r += "href:$h" } }
    }
    return ,$r
}
function QName($e) {
    if ($script:REQS_MODE) { if ($null -ne $e.rid) { return $e.rid }; return $e.name }
    $n = @()
    for ($o = $e; $null -ne $o -and $o.kind -cne 'model'; $o = $o.owner) { $n = @($o.name) + $n }
    return ($n -join '::')
}
function Owned-Comments($e) {
    if ($script:REQS_MODE) { return '' }
    $c = @()
    foreach ($k in $e.kids) {
        if ($k.kind -cne 'comment') { continue }
        $ann = Refs $k.node 'annotatedElement'
        if ($ann.Count -gt 0 -and $ann -cnotcontains $e.id) { continue }
        if ($null -ne $k.node.a['body']) { $b = $k.node.a['body'] } else { $bk = Kid $k.node 'body'; if ($null -ne $bk) { $b = Text-Of $bk } else { $b = '' } }
        if ($b -match '\S') { $c += $b }
    }
    return ($c -join "`n")
}
$script:H2T = @{ nbsp = ' '; lt = '<'; gt = '>'; amp = '&'; quot = '"'; apos = "'"; ndash = '-'; mdash = '-'; rsquo = "'"; lsquo = "'"; rdquo = '"'; ldquo = '"' }
function Html2Text($s) {
    if ($null -eq $s) { $s = '' }
    if ($s -notmatch '<\w|&\w+;') { return $s }
    $s = $s -replace '<(?:br|/p|/div|/li)\b[^>]*>', ' '
    $s = $s -creplace '<[^>]*>', ''
    $ms = ([regex]'&(\w+);').Matches($s)
    if ($ms.Count -gt 0) {
        $out = ''; $at = 0
        foreach ($m in $ms) {
            $k = $m.Groups[1].Value
            $r = "&$k;"; foreach ($hk in $script:H2T.Keys) { if ($hk -ceq $k) { $r = $script:H2T[$hk]; break } }
            $out += $s.Substring($at, $m.Index - $at) + $r; $at = $m.Index + $m.Length
        }
        $s = $out + $s.Substring($at)
    }
    return (Unent $s)
}
function Squash($s) { if ($null -eq $s) { $s = '' }; $s = $s -replace '\s+', ' '; return ($s -replace '^ | $', '') }
function Req-Id($e) { if ($script:REQS_MODE) { return [string](Dfl $e.rid '') }; return (Squash (St-Attr $e 'id')) }
function Req-Text($e) { if ($script:REQS_MODE) { return [string](Dfl $e.rtext '') }; return (Squash (Html2Text (St-Attr $e 'text'))) }
function Traces {
    return ,@(foreach ($e in $script:ALLREC) {
        if ($e.kind -cnotmatch '^(?:satisfy|verify|derive|refine|trace|copy|allocate)$') { continue }
        ,@($e.kind, (Refs $e.node 'client'), (Refs $e.node 'supplier'), $e)
    })
}

# ================================================================ types
$script:PRIM = [hashtable]::new()
foreach ($kv in @(@('Real','Real'), @('Integer','Integer'), @('Boolean','Boolean'), @('String','String'), @('UnlimitedNatural','Natural'), @('Number','Real'), @('Complex','Complex'), @('double','Real'), @('float','Real'), @('int','Integer'), @('boolean','Boolean'), @('string','String'))) { $script:PRIM[$kv[0]] = $kv[1] }
$script:ISQMAP = [hashtable]::new()
foreach ($kv in @(@('mass','MassValue'), @('length','LengthValue'), @('distance','LengthValue'), @('time','DurationValue'), @('duration','DurationValue'), @('speed','SpeedValue'),
    @('velocity','SpeedValue'), @('acceleration','AccelerationValue'), @('force','ForceValue'), @('power','PowerValue'), @('energy','EnergyValue'), @('area','AreaValue'),
    @('volume','VolumeValue'), @('frequency','FrequencyValue'), @('pressure','PressureValue'), @('electric current','ElectricCurrentValue'), @('current','ElectricCurrentValue'),
    @('thermodynamic temperature','ThermodynamicTemperatureValue'), @('temperature','ThermodynamicTemperatureValue'), @('plane angle','AngularMeasureValue'),
    @('angle','AngularMeasureValue'), @('torque','TorqueValue'))) { $script:ISQMAP[$kv[0]] = $kv[1] }
$script:UNITMAP = [hashtable]::new()
foreach ($kv in @(@('kilogram','kg','MassValue'), @('gram','g','MassValue'), @('metre','m','LengthValue'), @('meter','m','LengthValue'), @('kilometre','km','LengthValue'), @('kilometer','km','LengthValue'),
    @('second','s','DurationValue'), @('newton','N','ForceValue'), @('watt','W','PowerValue'), @('joule','J','EnergyValue'), @('hertz','Hz','FrequencyValue'), @('pascal','Pa','PressureValue'),
    @('ampere','A','ElectricCurrentValue'), @('kelvin','K','ThermodynamicTemperatureValue'), @('radian','rad','AngularMeasureValue'),
    @('metre per second','m/s','SpeedValue'), @('meter per second','m/s','SpeedValue'), @('metre per second squared','m/s^2','AccelerationValue'), @('meter per second squared','m/s^2','AccelerationValue'))) { $script:UNITMAP[$kv[0]] = @($kv[1], $kv[2]) }

function Load-Typemap([string]$f) {
    if (-not (Test-Path -LiteralPath $f -PathType Leaf)) { Fail "${f}: No such file or directory" }
    $text = Get-Content -LiteralPath $f -Raw -Encoding UTF8; if ($null -eq $text) { $text = '' }
    $lines = $text -split "`n"; if ($text.EndsWith("`n")) { $lines = $lines[0..($lines.Count - 2)] }; if ($text -eq '') { $lines = @() }
    $ln = 0
    foreach ($l in $lines) {
        $ln++
        $l = $l -creplace "`r$", ''
        if ($l -match '^\s*(?:#|$)') { continue }
        $p = $l -csplit "`t"
        $k = $p[0]; $v = $null; $unit = $null
        if ($p.Count -gt 1) { $v = $p[1] }; if ($p.Count -gt 2) { $unit = $p[2] }
        if ($null -eq $v -or $v -eq '') { Fail "${f}:${ln}: expected KEY<TAB>V2TYPE[<TAB>UNIT]" }
        $script:TYPEMAP[$k] = @($v, $unit)
    }
}
function Quantity-Of($e) {
    if ($e.name -match '^\s*([A-Za-z][\w ]*?)\s*\[\s*([^\]]+?)\s*\]\s*$') {
        $q = $Matches[1].ToLowerInvariant(); $u = $Matches[2].ToLowerInvariant()
        $sym = $null; if ($script:UNITMAP.ContainsKey($u)) { $sym = $script:UNITMAP[$u][0] }
        if ($script:ISQMAP.ContainsKey($q)) { return ,@($script:ISQMAP[$q], $sym) }
        if ($script:UNITMAP.ContainsKey($u)) { return ,@($script:UNITMAP[$u][1], $sym) }
    }
    foreach ($key in @('unit', 'quantitykind')) {
        $r = St-Attr $e $key; if ($null -eq $r) { continue }
        $t = $script:ELEMS[$r]; if ($null -eq $t) { continue }
        $n = (Squash $t.name).ToLowerInvariant()
        if ($key -ceq 'unit' -and $script:UNITMAP.ContainsKey($n)) { return ,@($script:UNITMAP[$n][1], $script:UNITMAP[$n][0]) }
        if ($key -ceq 'quantitykind' -and $script:ISQMAP.ContainsKey($n)) { return ,@($script:ISQMAP[$n], $null) }
    }
    return $null
}
# -> @{ el = record } | @{ lib = 'Real'; unit = 'kg' } | @{ unres = text } | $null
function Resolve-Type($r) {
    if ($null -eq $r) { return $null }
    if ($r -cmatch '^href:([\s\S]*)$') {
        $href = $Matches[1]
        $frag = $href; if ($href -cmatch '#([\s\S]*)$') { $frag = $Matches[1] }
        foreach ($k in @($href, $frag)) { if ($script:TYPEMAP.ContainsKey($k)) { return @{ lib = $script:TYPEMAP[$k][0]; unit = $script:TYPEMAP[$k][1] } } }
        if ($frag -cmatch '([A-Za-z]\w*)$') { $tail = $Matches[1]; if ($script:PRIM.ContainsKey($tail)) { return @{ lib = $script:PRIM[$tail] } } }
        return @{ unres = $href }
    }
    $e = $script:ELEMS[$r]
    if ($null -eq $e) { return @{ unres = "missing id $r" } }
    foreach ($k in @($e.id, $e.name)) { if ($null -ne $k -and $script:TYPEMAP.ContainsKey($k)) { return @{ lib = $script:TYPEMAP[$k][0]; unit = $script:TYPEMAP[$k][1] } } }
    if ($e.kind -ceq 'valuetype') {
        if ($script:PRIM.ContainsKey([string]$e.name)) { return @{ lib = $script:PRIM[$e.name] } }
        $q = Quantity-Of $e
        if ($null -ne $q -and $e.name -match '\[') { return @{ lib = $q[0]; unit = $q[1]; qty = 1 } }
    }
    return @{ el = $e }
}

# ================================================================ inventory
$script:CONVERTS = @{}
foreach ($kv in @(@('package','yes'), @('block','yes'), @('class','yes (as part def)'), @('interfaceblock','yes (port def)'), @('constraintblock','partly (parameters; body by hand)'),
    @('valuetype','yes'), @('enum','yes'), @('literal','yes'), @('property','yes'), @('port','yes'), @('connector','yes (binary)'), @('generalization','yes'), @('requirement','yes'),
    @('satisfy','yes'), @('verify','yes'), @('derive','yes (dependency)'), @('refine','yes (dependency)'), @('trace','yes (dependency)'), @('copy','yes (dependency)'), @('comment','yes (doc)'),
    @('allocate','no (by hand)'), @('behavior','no (out of scope)'), @('usecase','no (out of scope)'), @('itemflow','no (by hand)'), @('instance','no (by hand)'), @('constraint','no (by hand)'),
    @('operation','no (by hand)'), @('association','implied'), @('assocend','implied'), @('dependency','no'), @('profile','no'), @('model','-'), @('other','no'))) { $script:CONVERTS[$kv[0]] = $kv[1] }

function Cmd-Inventory {
    Load-Model $script:IN
    $n = [hashtable]::new(); $other = [hashtable]::new()
    foreach ($e in $script:ALLREC) {
        if ($e.inside) { continue }
        if ($e.type -cmatch '^uml:(?:Literal|OpaqueExpression|InstanceValue|ElementValue|Expression|ConnectorEnd)') { continue }
        $n[$e.kind] = 1 + [int]$n[$e.kind]
        if ($e.kind -ceq 'other') { $other[$e.type] = 1 + [int]$other[$e.type] }
    }
    $req = @(foreach ($e in $script:ALLREC) { if ($e.kind -ceq 'requirement') { $e } })
    $idc = [hashtable]::new(); foreach ($r in $req) { $i = Req-Id $r; if ($i -ne '') { $idc[$i] = 1 + [int]$idc[$i] } }
    $leaf = @(foreach ($r in $req) { $hasReqKid = $false; foreach ($k in $r.kids) { if ($k.kind -ceq 'requirement') { $hasReqKid = $true } }; if (-not $hasReqKid) { $r } })
    $sat = [hashtable]::new(); $ver = [hashtable]::new()
    foreach ($t in (Traces)) {
        if ($t[0] -ceq 'satisfy') { $set = $sat } elseif ($t[0] -ceq 'verify') { $set = $ver } else { continue }
        foreach ($x in $t[2]) { $set[$x] = 1 }
    }
    $ext = [hashtable]::new(); $cust = [hashtable]::new()
    foreach ($e in $script:ALLREC) {
        if ($e.kind -cnotmatch '^(?:property|port)$' -or $e.inside) { continue }
        foreach ($r in (Refs $e.node 'type')) { $t = Resolve-Type $r; if ($null -ne $t -and $t.ContainsKey('unres')) { $ext[$t.unres] = 1 + [int]$ext[$t.unres] } }
    }
    foreach ($e in $script:ALLREC) { foreach ($s in $e.st) { if ($s.custom) { $k = "$($s.prefix):$($s.name)"; $cust[$k] = 1 + [int]$cust[$k] } } }
    $dup = 0; foreach ($k in $idc.Keys) { if ($idc[$k] -gt 1) { $dup++ } }
    $mv = [hashtable]::new()
    $mv['requirements'] = $req.Count
    $mv['requirements.leaf'] = $leaf.Count
    $mv['requirements.with_id'] = @(foreach ($r in $req) { if ((Req-Id $r) -ne '') { 1 } }).Count
    $mv['requirements.with_text'] = @(foreach ($r in $req) { if ((Req-Text $r) -ne '') { 1 } }).Count
    $mv['requirements.duplicate_ids'] = $dup
    $mv['requirements.leaf_satisfied'] = @(foreach ($r in $leaf) { if ($sat.ContainsKey($r.id)) { 1 } }).Count
    $mv['requirements.leaf_verified'] = @(foreach ($r in $leaf) { if ($ver.ContainsKey($r.id)) { 1 } }).Count
    $mv['types.unresolved_distinct'] = $ext.Count
    $mv['stereotypes.custom_distinct'] = $cust.Count
    $mv['extensions.skipped'] = $script:NSKIP
    $out = @()
    if ($script:OPT.ContainsKey('tsv')) {
        $out += "metric`tvalue"
        foreach ($k in (SortOrd $n.Keys)) { $out += "kind.$k`t$($n[$k])" }
        foreach ($k in (SortOrd $mv.Keys)) { $out += "$k`t$($mv[$k])" }
        Out-Text (($out -join "`n") + "`n")
        return
    }
    $out += ('{0,-18} {1,6}  {2}' -f 'v1 kind', 'count', 'converts')
    $ks = @($n.Keys); $ks = SortByKey $ks @(foreach ($k in $ks) { (NumKeyDesc $n[$k]) + "`0" + $k })
    foreach ($k in $ks) { $cv = $script:CONVERTS[$k]; if ($null -eq $cv) { $cv = '?' }; $out += ('{0,-18} {1,6}  {2}' -f $k, $n[$k], $cv) }
    if ($other.Count -gt 0) {
        $out += ''; $out += 'other element types (not converted):'
        $ks = @($other.Keys); $ks = SortByKey $ks @(foreach ($k in $ks) { (NumKeyDesc $other[$k]) + "`0" + $k })
        foreach ($k in $ks) { $out += ('  {0,-34} {1,6}' -f $k, $other[$k]) }
    }
    $out += ''
    $out += "requirements: $($mv['requirements']) ($($mv['requirements.leaf']) leaf), $($mv['requirements.with_id']) with id, $($mv['requirements.with_text']) with text, $($mv['requirements.duplicate_ids']) duplicate id(s)"
    $out += "leaf coverage: $($mv['requirements.leaf_satisfied']) satisfied, $($mv['requirements.leaf_verified']) verified, of $($mv['requirements.leaf'])"
    if ($ext.Count -gt 0) {
        $out += ''; $out += 'unresolved types (add to a --typemap file; count of uses):'
        $ks = @($ext.Keys); $ks = SortByKey $ks @(foreach ($k in $ks) { (NumKeyDesc $ext[$k]) + "`0" + $k })
        foreach ($k in $ks) { $out += ('  {0,5}  {1}' -f $ext[$k], $k) }
    }
    if ($cust.Count -gt 0) {
        $out += ''; $out += 'custom stereotypes (not converted; count of applications):'
        foreach ($k in (SortOrd $cust.Keys)) { $out += ('  {0,5}  {1}' -f $cust[$k], $k) }
    }
    $out += ''; $out += "xmi:Extension blocks skipped (diagrams, tool data): $($script:NSKIP)"
    Out-Text (($out -join "`n") + "`n")
}

# ================================================================ check
$script:NERR = 0; $script:NWARN = 0; $script:DIAG = @()
function Diag($line, [string]$sev, [string]$msg) {
    $script:DIAG += ,@([int]$line, $script:DIAG.Count, "$($script:IN):${line}: ${sev}: $msg")
    if ($sev -ceq 'error') { $script:NERR++ } elseif ($sev -ceq 'warning') { $script:NWARN++ }
}
function Sorted-Diags($list) {
    $l = @($list)
    return ,(SortByKey $l @(foreach ($d in $l) { (NumKey $d[0]) + (NumKey $d[1]) }))
}
function Cmd-Check {
    Load-Model $script:IN
    $live = @(foreach ($e in $script:ALLREC) { if (-not $e.inside -and $e.kind -cne 'profile') { $e } })
    foreach ($e in $live) {
        foreach ($attr in @('type', 'general', 'client', 'supplier', 'role', 'partWithPort', 'redefinedProperty')) {
            foreach ($r in (Refs $e.node $attr)) { if ($r -cnotmatch '^href:' -and -not $script:ELEMS.ContainsKey($r)) { Diag $e.line 'error' "$attr of '$(QName $e)' refers to missing id $r" } }
        }
    }
    foreach ($e in $live) {
        $k = $e.kind
        if ($k -cmatch '^(?:model|comment|constraint|generalization|other|assocend|association|satisfy|verify|derive|refine|trace|copy|allocate|dependency|connector)$') { continue }
        if ($e.name -notmatch '\S') { Diag $e.line 'warning' "unnamed $k (xmi:id $($e.id))" }
    }
    $seen = [hashtable]::new()
    foreach ($e in $live) {
        if ($null -eq $e.owner -or $e.name -notmatch '\S') { continue }
        if ($e.kind -cnotmatch '^(?:package|block|class|interfaceblock|constraintblock|valuetype|enum|requirement|property|port|literal)$') { continue }
        $k = "$($e.owner.id)`0$($e.name)"
        if ($seen.ContainsKey($k)) { Diag $e.line 'warning' "duplicate name '$($e.name)' in '$(QName $e.owner)' (first at line $($seen[$k]))" }
        else { $seen[$k] = $e.line }
    }
    $ids = [hashtable]::new(); $sat = [hashtable]::new(); $ver = [hashtable]::new()
    foreach ($t in (Traces)) {
        $k = $t[0]; $cl = $t[1]; $su = $t[2]; $rec = $t[3]
        if ($k -cnotmatch '^(?:satisfy|verify|derive)$') { continue }
        foreach ($s in $su) {
            $se = $script:ELEMS[$s]
            if (-not ($null -ne $se -and $se.kind -ceq 'requirement')) {
                if ($null -ne $se) { $what = "$(QName $se) ($($se.kind))" } else { $what = $s }
                Diag $rec.line 'warning' "$k supplier is not a requirement: $what"
            }
            if ($k -ceq 'satisfy') { $sat[$s] = 1 } elseif ($k -ceq 'verify') { $ver[$s] = 1 }
        }
        if ($k -ceq 'satisfy') {
            foreach ($c in $cl) {
                $ce = $script:ELEMS[$c]; if ($null -eq $ce) { continue }
                if ($ce.kind -cnotmatch '^(?:block|class|property|port)$') { Diag $rec.line 'warning' "satisfy client '$(QName $ce)' is a $($ce.kind); v2 needs a part or a feature" }
            }
        }
    }
    foreach ($r in $live) {
        if ($r.kind -cne 'requirement') { continue }
        $id = Req-Id $r
        if ($id -eq '') { Diag $r.line 'warning' "requirement '$(QName $r)' has no id" }
        elseif ($ids.ContainsKey($id)) { Diag $r.line 'warning' "requirement id '$id' also used at line $($ids[$id])" }
        else { $ids[$id] = $r.line }
        if ((Req-Text $r) -eq '') { Diag $r.line 'warning' "requirement '$(QName $r)' has no text" }
        $grp = $false; foreach ($k in $r.kids) { if ($k.kind -ceq 'requirement') { $grp = $true } }
        if ($grp) { continue }
        if ($id -cmatch '^N-') { continue }
        $up = @($r); for ($o = $r.owner; $null -ne $o -and $o.kind -ceq 'requirement'; $o = $o.owner) { $up += ,$o }
        $hs = $false; $hv = $false; foreach ($u in $up) { if ($sat.ContainsKey($u.id)) { $hs = $true }; if ($ver.ContainsKey($u.id)) { $hv = $true } }
        if (-not $hs) { Diag $r.line 'warning' "leaf requirement '$(QName $r)' is not satisfied" }
        if (-not $hv) { Diag $r.line 'warning' "leaf requirement '$(QName $r)' is not verified" }
    }
    foreach ($e in $live) {
        if ($e.kind -cnotmatch '^(?:property|port)$') { continue }
        $tr = Refs $e.node 'type'
        if ($tr.Count -eq 0) { Diag $e.line 'warning' "$($e.kind) '$(QName $e)' has no type"; continue }
        $t = Resolve-Type $tr[0]
        if ($t.ContainsKey('unres')) { Diag $e.line 'warning' "$($e.kind) '$(QName $e)' has unresolved type $($t.unres)" }
        if ($e.kind -ceq 'port' -and $t.ContainsKey('el') -and $t.el.kind -cne 'interfaceblock') { Diag $e.line 'warning' "port '$(QName $e)' is typed by $($t.el.kind) '$($t.el.name)'; v2 ports need a port def (interface block)" }
    }
    foreach ($e in $live) { if ($e.kind -ceq 'class') { Diag $e.line 'warning' "class '$(QName $e)' has no Block stereotype" } }
    $cs = [hashtable]::new()
    foreach ($e in $live) {
        foreach ($s in $e.st) {
            if (-not $s.custom) { continue }
            $k = "$($s.prefix):$($s.name)"
            if (-not $cs.ContainsKey($k)) { Diag $s.line 'warning' "custom stereotype $($s.prefix):$($s.name) on '$(QName $e)' will not convert" }
            $cs[$k] = 1 + [int]$cs[$k]
        }
    }
    foreach ($e in $script:ALLREC) { if ($e.kind -cmatch '^(?:behavior|usecase)$' -and -not $e.inside) { Diag $e.line 'note' "$($e.kind) '$(QName $e)' is out of scope for conversion" } }
    $o = @(foreach ($d in (Sorted-Diags $script:DIAG)) { $d[2] })
    $o += "v1v2 check: 1 file(s), $($script:NERR) error(s), $($script:NWARN) warning(s)"
    Out-Text (($o -join "`n") + "`n")
    if ($script:NERR -or $script:NWARN) { $script:RC = 1 } else { $script:RC = 0 }
}

# ================================================================ naming
$script:KEYWORD = [hashtable]::new()
foreach ($k in (-split 'about abstract accept action actor after alias all allocate
    allocation analysis and as assert assign assume at attribute bind binding by calc case comment
    concern connect connection constant constraint crosses decide def default defined dependency
    derived do doc else end entry enum event exhibit exit expose false filter first flow for fork
    frame from hastype if implies import in include individual inout interface istype item join
    language library locale loop merge message meta metadata nonunique not null objective occurrence
    of or ordered out package parallel part perform port private protected public redefines ref
    references render rendering rep require requirement return satisfy send snapshot specializes
    stakeholder standard state subject subsets succession terminate then timeslice to transition
    true until use variant variation verification verify via view viewpoint when while xor')) { $script:KEYWORD[$k] = 1 }
$script:STOP = [hashtable]::new()
foreach ($k in (-split 'the a an shall be is are of to and or for with within in on at by from than that this which its it will should must all each any as')) { $script:STOP[$k] = 1 }
function Camel($s, $upper) {
    if ($null -eq $s) { $s = '' }
    $w = @(foreach ($x in ([string]$s -csplit '[^A-Za-z0-9]+')) { if ($x.Length) { $x } })
    if ($w.Count -eq 0) { return '' }
    $r = -join @(foreach ($x in $w) { UcFirst $x })
    if (-not $upper) {
        if ($r -cmatch '^([A-Z]+)(?=[A-Z][a-z]|\d|$)') { $r = $Matches[1].ToLowerInvariant() + $r.Substring($Matches[1].Length) }
        elseif ($r -cmatch '^([A-Z])') { $r = $Matches[1].ToLowerInvariant() + $r.Substring(1) }
    }
    if ($r -cmatch '^\d') { $r = "_$r" }
    return $r
}
function Ident-Ok([string]$n) { return ($n -cmatch '^[A-Za-z_]\w*$' -and -not $script:KEYWORD.ContainsKey($n)) }
function Qid([string]$n) { if (Ident-Ok $n) { return $n }; $n = $n -creplace "(['\\])", '\$1'; return "'$n'" }
function Sq($s) { if ($null -eq $s) { $s = '' }; $s = [string]$s -creplace '(["\\])', '\$1'; $s = $s.Replace("`n", '\n'); return '"' + $s + '"' }

$script:NOTELIST = @(); $script:NCONV = 0; $script:NMANUAL = 0; $script:RENAMED = [hashtable]::new(); $script:TAKEN = [hashtable]::new()
function Note($e, [string]$sev, [string]$msg) {
    $line = 1; if ($null -ne $e) { $line = $e.line }
    $script:NOTELIST += ,@([int]$line, $script:NOTELIST.Count, ('{0}:{1}: {2}: {3}' -f $script:IN, $line, $sev, $msg))
    if ($sev -ceq 'warning') { $script:NMANUAL++ }
}
function V2Name($e, [string]$style, $scope) {
    if ($null -ne $e.v2) { return $e.v2 }
    $raw = [string]$e.name
    if ($script:OPT.ContainsKey('keep-names') -and $e.kind -cne 'requirement') { if ($raw -match '\S') { $n = $raw } else { $n = '' } }
    else { $n = Camel $raw ($style -ceq 'def') }
    if ($n -eq '' -and $e.kind -ceq 'requirement') {
        $w = @(foreach ($x in ((Req-Text $e) -csplit '[^A-Za-z0-9]+')) { if ($x.Length -and -not $script:STOP.ContainsKey($x.ToLowerInvariant())) { $x } })
        if ($w.Count -gt 0) { $last = $w.Count - 1; if ($last -gt 4) { $last = 4 }; $n = Camel ($w[0..$last] -join ' ') $false }
        if ($n -eq '' -and (Req-Id $e) -ne '') { $n = Camel ('r ' + (Req-Id $e)) $false }
        if ($n -ne '') { Note $e 'note' "unnamed requirement '$(Req-Id $e)' named '$n' from its text" }
    }
    if ($n -eq '') {
        if ($style -ceq 'def') { $n = 'Unnamed' + (UcFirst $e.kind) } else { $n = 'unnamed' + (UcFirst $e.kind) }
        Note $e 'warning' "unnamed $($e.kind) named '$n'"
    }
    if (-not $script:OPT.ContainsKey('keep-names') -or $e.kind -ceq 'requirement') {
        if ($script:KEYWORD.ContainsKey($n)) { Note $e 'note' "'$n' is a SysML v2 keyword; named '${n}_'"; $n += '_' }
    }
    $key = [string](Dfl $scope 'global') + "`0"
    $base = $n; $i = 1
    while ($script:TAKEN.ContainsKey($key + $n)) { $i++; $n = $base + $i }
    $script:TAKEN[$key + $n] = 1
    if ($n -cne $raw) { $script:RENAMED[$e.id] = 1 }
    $e.v2 = $n
    return $n
}

# ================================================================ convert
$script:VERIFIER = [hashtable]::new(); $script:SCOPEREC = $null; $script:EMIT = [hashtable]::new(); $script:STUB = [hashtable]::new(); $script:STUBS = @(); $script:STUBPKG = $null; $script:FILEOF = [hashtable]::new()
$script:DEFRE = '^(?:block|class|interfaceblock|constraintblock|valuetype|enum)$'
function In-Scope($e) { for ($o = $e; $null -ne $o; $o = $o.owner) { if (($o -eq $script:SCOPEREC)) { return $true } }; return $false }
function Top-PkgName($e) {
    $n = Camel $e.name $true
    if ($n -eq '') { $n = 'Model' }
    if ($null -ne $script:OPT['prefix']) { $p = Camel $script:OPT['prefix'] $true; if (-not $n.StartsWith($p, 'Ordinal')) { $n = $p + $n } }
    $base = $n; $i = 1
    while ($script:TAKEN.ContainsKey("top`0" + $n.ToLowerInvariant())) { $i++; $n = $base + $i }
    $script:TAKEN["top`0" + $n.ToLowerInvariant()] = 1
    return $n
}
function Pkg-Of($e) { $o = $e.owner; while ($null -ne $o -and $o.kind -cnotmatch '^(?:package|model)$') { $o = $o.owner }; return $o }
function Qn($e) {
    if ($e.qn) { return $e.qn }
    $seg = @()
    for ($o = $e; $null -ne $o; $o = $o.owner) { $seg = @(Qid $o.v2) + $seg; if ($o.top) { break } }
    $e.qn = $seg -join '::'
    return $e.qn
}
function TRef($t, $from) {
    if ($t.lib) { return $t.lib }
    $e = $t.el
    if (-not $script:EMIT.ContainsKey($e.id)) { $e = Stub-For $e }
    if (-not $e.stub -and (Sees $from $e)) { return (Qid $e.v2) }
    return (Qn $e)
}
function Sees($from, $e) {
    $p = $e.owner
    if ($null -eq $p -or $p.kind -cnotmatch '^(?:package|model)$') { return $false }
    for ($o = $from; $null -ne $o; $o = $o.owner) { if (($o -eq $p)) { return $true }; if ($o.top) { break } }
    return $false
}
function Stub-For($e) {
    if ($script:STUB.ContainsKey($e.id)) { return $script:STUB[$e.id] }
    $s = [hashtable]::new(); foreach ($k in $e.Keys) { $s[$k] = $e[$k] }
    $s.stub = 1; $s.kids = @(); $s.v2 = $null; $s.qn = $null; $s.owner = $script:STUBPKG; $s.top = 0
    [void](V2Name $s 'def' 'stubs')
    if ($e.kind -ceq 'enum') { $s.lits = @(foreach ($k in $e.kids) { if ($k.kind -ceq 'literal') { V2Name $k 'use' "stub$($e.id)" } }) }
    $script:STUB[$e.id] = $s; $script:STUBS += ,$s
    Note $e 'note' "'$(QName $e)' is outside the slice; stubbed as $(Qn $s)"
    return $s
}
function Doc-Lines($text, [string]$ind) {
    $text = Squash $text
    if ($text -eq '') { return ,@() }
    $text = $text.Replace('*/', '* /')
    $width = 96 - $ind.Length - 8
    $l = @('')
    foreach ($w in ($text -split ' ')) {
        $cur = $l[$l.Count - 1]
        if ($cur.Length -and $cur.Length + 1 + $w.Length -gt $width) { $l += $w }
        else { if ($cur.Length) { $l[$l.Count - 1] = $cur + ' ' + $w } else { $l[$l.Count - 1] = $cur + $w } }
    }
    $out = @("${ind}doc /* $($l[0])")
    for ($i = 1; $i -lt $l.Count; $i++) { $out += "$ind     * $($l[$i])" }
    $out[$out.Count - 1] += ' */'
    return ,$out
}
function Mk($e) { if ($e.stub -or $null -eq $e.id) { return '' }; return [string][char]1 + $e.id + [char]1 }
function Prov-Line($e, [string]$ind) {
    if (-not $script:OPT['provenance']) { return ,@() }
    return ,@("$ind@V1Source { xmiId = $(Sq $e.id); v1Name = $(Sq $e.name); }")
}
function Mult($n) {
    $lo = Kid $n 'lowerValue'; $up = Kid $n 'upperValue'
    if ($null -eq $lo -and $null -eq $up) { return '' }
    $l = '1'; if ($null -ne $lo) { $l = [string](Dfl $lo.a['value'] 0) }
    $u = '1'; if ($null -ne $up) { $u = [string](Dfl $up.a['value'] 0) }
    if ($u -ceq '-1') { $u = '*' }
    if ($l -ceq '1' -and $u -ceq '1') { return '' }
    if ($l -ceq $u) { return "[$l]" }
    return "[$l..$u]"
}
function Default-Value($n, $t, $from) {                # -> @(text) or @($null, reason) or @()
    $d = Kid $n 'defaultValue'
    if ($null -eq $d) { return ,@() }
    $ty = [string](Dfl $d.a['xmi:type'] '')
    $v = $d.a['value']
    if ($ty -ceq 'uml:LiteralReal' -or $ty -ceq 'uml:LiteralInteger' -or $ty -ceq 'uml:LiteralUnlimitedNatural') {
        $lit = [string](Dfl $v 0); if ($lit -ceq '-1') { $lit = '*' }
        if ($lit -cnotmatch '^-?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?$') { return ,@($null, "default '$lit' is not a number") }
    } elseif ($ty -ceq 'uml:LiteralBoolean') { if ([string](Dfl $v 'false') -ceq 'true') { $lit = 'true' } else { $lit = 'false' } }
    elseif ($ty -ceq 'uml:LiteralString') { $lit = Sq (Dfl $v '') }
    elseif ($ty -ceq 'uml:InstanceValue') {
        $i = (Refs $d 'instance'); $le = $null; if ($i.Count -gt 0 -and (PTrue $i[0])) { $le = $script:ELEMS[$i[0]] }
        if ($null -eq $le -or $le.kind -cne 'literal') { return ,@($null, 'default instance value') }
        $en = TRef @{ el = $le.owner } $from
        return ,@($en + '::' + (Qid $le.v2))
    } else {
        $body = Squash ((@(foreach ($x in (Elems $d)) { if ($x.tag -ceq 'body') { Text-Of $x } })) -join ' ')
        $why = "default is a $ty"; if ($body -ne '') { $why += " ($body)" }
        return ,@($null, $why)
    }
    $q = $null; if ($null -ne $t -and $null -ne $t.el -and $t.el.kind -ceq 'valuetype') { $q = Quantity-Of $t.el }
    $isq = $false; $unit = $null
    if ($null -ne $t -and $t.lib) { $isq = $t.lib -cmatch 'Value$'; $unit = $t.unit } elseif ($null -ne $q) { $isq = $true; $unit = $q[1] }
    if ($isq) {
        if (PTrue $unit) { return ,@("$lit [$unit]") }
        return ,@($null, "default $lit has no unit SysML v2 can name")
    }
    return ,@($lit)
}
function Feature-Lines($p, $owner, [string]$ind, $from) {
    $n = $p.node
    $trs = Refs $n 'type'; $tr = $null; if ($trs.Count -gt 0) { $tr = $trs[0] }
    $t = Resolve-Type $tr
    $flow = (Has-St $p '^FlowProperty$') -and $owner.kind -ceq 'interfaceblock'
    $dir = ''; if ($flow) { $dir = [string](Dfl (St-Attr $p 'direction') 'inout') }
    $kw = ''; $comment = ''
    if ($null -ne $t -and $null -ne $t.el -and $t.el.kind -cnotmatch $script:DEFRE) { $t = @{ unres = "'$($t.el.name)' ($($t.el.kind))" } }
    $tk = ''; if ($null -ne $t -and $null -ne $t.el) { $tk = $t.el.kind }
    if ($p.kind -ceq 'port') {
        $kw = 'port'
        if ($null -ne $t -and $null -ne $t.el -and $tk -cne 'interfaceblock') {
            $comment = "v1 type '$($t.el.name)' is a $tk, not an interface block"
            Note $p 'warning' "port '$(QName $p)': $comment; typed by nothing"; $t = $null
        }
    } elseif ($tk -cmatch '^(?:block|class)$') {
        if ($flow) { $kw = 'item' } elseif ([string](Dfl $n.a['aggregation'] '') -ceq 'composite') { $kw = 'part' } else { $kw = 'ref part' }
    } elseif ($tk -ceq 'constraintblock') { $kw = 'constraint' }
    elseif ($tk -ceq 'interfaceblock') { $kw = 'port'; Note $p 'warning' "property '$(QName $p)' typed by an interface block; made a port" }
    else { $kw = 'attribute' }
    if ($null -ne $t -and $t.unres) {
        $comment = "v1 type: $($t.unres)"
        Note $p 'warning' "'$(QName $p)' has unresolved type $($t.unres); add it to a --typemap file"
        $t = $null
    }
    if (-not (PTrue $tr)) { Note $p 'warning' "'$(QName $p)' has no type" }
    if ($flow) { $kw = "$dir $kw" }
    $name = Qid (V2Name $p 'use' $owner.id)
    $redef = @(foreach ($x in (Refs $n 'redefinedProperty')) { if ($script:ELEMS.ContainsKey($x)) { $x } })
    if ($redef.Count -gt 0) {
        $r = $script:ELEMS[$redef[0]]
        $rn = $r.v2; if ($null -eq $rn) { $rn = V2Name $r 'use' $r.owner.id }
        if ($rn -ceq $p.v2) { $name = ':>> ' + (Qid $rn) } else { $name = "$name :>> " + (Qid $rn) }
    }
    $s = "$ind$kw $name"
    if ($null -ne $t) {
        $conj = ''; if ($p.kind -ceq 'port' -and [string](Dfl $n.a['isConjugated'] '') -ceq 'true') { $conj = '~' }
        $s += " : $conj" + (TRef $t $from)
    }
    $s += (Mult $n)
    $dv = Default-Value $n $t $from
    if ($dv.Count -gt 0 -and $null -ne $dv[0]) { $s += " default = $($dv[0])" }
    elseif ($dv.Count -gt 1 -and (PTrue $dv[1])) {
        $why = $dv[1]
        $comment = (@(foreach ($x in @($comment, "v1 $why")) { if ($x.Length) { $x } })) -join '; '
        Note $p 'warning' "'$(QName $p)': $why"
    }
    $s += ';' + (Mk $p)
    if ($comment -ne '') { $s += " // $comment" }
    return ,@($s)
}
function Connector-Line($c, $owner, [string]$ind) {
    $ends = @(foreach ($x in (Elems $c.node)) { if ([string](Dfl $x.a['xmi:type'] '') -ceq 'uml:ConnectorEnd') { $x } })
    if ($ends.Count -ne 2) { Note $c 'warning' "connector in '$(QName $owner)' has $($ends.Count) ends; not converted"; return ,@() }
    $path = @()
    foreach ($end in $ends) {
        $ro = Refs $end 'role'; $pw = Refs $end 'partWithPort'
        $re = $null; if ($ro.Count -gt 0 -and (PTrue $ro[0])) { $re = $script:ELEMS[$ro[0]] }
        if ($null -eq $re -or -not $script:EMIT.ContainsKey($re.id)) { Note $c 'warning' "connector end in '$(QName $owner)' has an unknown role; not converted"; return ,@() }
        $pe = $null; if ($pw.Count -gt 0 -and (PTrue $pw[0])) { $pe = $script:ELEMS[$pw[0]] }
        $pre = ''
        if ($null -ne $pe) { $pv = $pe.v2; if ($null -eq $pv) { $pv = V2Name $pe 'use' $pe.owner.id }; $pre = (Qid $pv) + '.' }
        $rv = $re.v2; if ($null -eq $rv) { $rv = V2Name $re 'use' $re.owner.id }
        $path += $pre + (Qid $rv)
    }
    $script:NCONV++
    $label = ''; if ($c.name -match '\S') { $label = 'connection ' + (Qid (V2Name $c 'use' $owner.id)) + ' ' }
    return ,@("$ind${label}connect $($path[0]) to $($path[1]);")
}
function General-List($e, $from) {
    $g = @()
    foreach ($k in $e.kids) {
        if ($k.kind -cne 'generalization') { continue }
        $rs = Refs $k.node 'general'; $r = $null; if ($rs.Count -gt 0) { $r = $rs[0] }
        $t = Resolve-Type $r
        if ($null -ne $t -and $null -ne $t.el -and $t.el.kind -cnotmatch $script:DEFRE) { $t = @{ unres = "'$($t.el.name)' ($($t.el.kind))" } }
        if ($null -eq $t -or $t.unres) { $u = '?'; if ($null -ne $t) { $u = $t.unres }; Note $e 'warning' "'$(QName $e)' specializes unresolved $u"; continue }
        $g += (TRef $t $from)
    }
    if ($g.Count -gt 0) { return ' :> ' + ($g -join ', ') }
    return ''
}
$script:DEFKW = @{ block = 'part def'; class = 'part def'; interfaceblock = 'port def'; constraintblock = 'constraint def'; valuetype = 'attribute def'; enum = 'enum def' }
function Emit-Def($e, $lst, [string]$ind, $from) {        # appends to the list $lst (a hashtable { l = @() })
    $kw = $script:DEFKW[$e.kind]
    $head = "$ind$kw " + (Qid $e.v2)
    if ($e.kind -ceq 'valuetype') {
        $q = Quantity-Of $e
        $g = General-List $e $from
        if ($g -eq '' -and $null -ne $q) { $g = " :> $($q[0])" }
        $head += $g
    } else { $head += (General-List $e $from) }
    $body = @()
    $body += (Doc-Lines (Owned-Comments $e) "$ind    ")
    $body += (Prov-Line $e "$ind    ")
    if ($e.stub) { $body += "$ind    // stub: defined outside the converted slice"; foreach ($x in @($e.lits)) { if ($null -ne $x) { $body += "$ind    enum " + (Qid $x) + ';' } } }
    foreach ($k in $e.kids) {
        if ($k.stub -or $e.stub) { continue }
        if ($k.kind -ceq 'literal') { $body += "${ind}    enum " + (Qid (V2Name $k 'use' $e.id)) + ';' + (Mk $k); $script:NCONV++ }
        elseif ($k.kind -cmatch '^(?:property|port)$') {
            $fl = Feature-Lines $k $e "$ind    " (Pkg-Of $e)
            if ($e.kind -ceq 'constraintblock') { $fl = @(foreach ($x in $fl) { $x -creplace '^(\s*)attribute ', '$1in ' }) }
            $body += $fl; $script:NCONV++
        }
        elseif ($k.kind -ceq 'constraint') {
            $spec = Kid $k.node 'specification'
            $b = ''; if ($null -ne $spec) { $b = Squash ((@(foreach ($x in (Elems $spec)) { if ($x.tag -ceq 'body') { Text-Of $x } })) -join ' ') }
            $nm = ''; if ($k.name -match '\S') { $nm = " $($k.name)" }
            $body += "$ind    // v1 constraint${nm}: {$b} (convert by hand)"
            Note $k 'warning' "constraint in '$(QName $e)' needs a v2 expression: $b"
        }
        elseif ($k.kind -cmatch '^(?:behavior|operation)$') {
            $body += "$ind    // v1 $($k.type) '$($k.name)' not converted"
            if ($k.kind -ceq 'operation') { $sv = 'warning' } else { $sv = 'note' }
            Note $k $sv "$($k.type) '$(QName $k)' not converted"
        }
    }
    foreach ($k in $e.kids) { if ($k.kind -ceq 'connector') { $body += (Connector-Line $k $e "$ind    ") } }
    foreach ($k in $e.kids) {
        if ($script:EMIT.ContainsKey($k.id) -and $k.kind -cmatch $script:DEFRE) { $sub = @{ l = @() }; Emit-Def $k $sub "$ind    " $from; $body += $sub.l }
    }
    if ($body.Count -gt 0) { $lst.l += @("$head {" + (Mk $e)) + $body + @("$ind}") } else { $lst.l += "$head;" + (Mk $e) }
    if (-not $e.stub) { $script:NCONV++ }
}
$script:RIDSEEN = [hashtable]::new()
function Q-Short([string]$s) { $s = $s -creplace "(['\\])", '\$1'; return "'$s'" }
function Emit-Req($r, $lst, [string]$ind) {
    $id = Req-Id $r
    if ($id -ne '' -and $script:RIDSEEN.ContainsKey($id)) { Note $r 'warning' "requirement id '$id' is also used at line $($script:RIDSEEN[$id])" }
    if (-not $script:RIDSEEN.ContainsKey($id)) { $script:RIDSEEN[$id] = $r.line }
    $head = "${ind}requirement "; if ($id -ne '') { $head += '<' + (Q-Short $id) + '> ' }; $head += (Qid $r.v2)
    $body = (Doc-Lines (Req-Text $r) "$ind    ")
    $c = Owned-Comments $r
    if ($c -ne '') { foreach ($x in (Doc-Lines $c "$ind    ")) { $body += ($x -creplace '^(\s*)doc /\*', '$1/* v1 comment:') } }
    $body += (Prov-Line $r "$ind    ")
    $sub = @{ l = @() }
    foreach ($k in $r.kids) { if ($k.kind -ceq 'requirement' -and $script:EMIT.ContainsKey($k.id)) { Emit-Req $k $sub "$ind    " } }
    if ((Req-Text $r) -eq '') { $who = $r.rid; if ($null -eq $who) { $who = QName $r }; Note $r 'warning' "requirement '$who' has no text" }
    if ($body.Count -gt 0 -or $sub.l.Count -gt 0) { $lst.l += @("$head {" + (Mk $r)) + $body + $sub.l + @("$ind}") } else { $lst.l += "$head;" + (Mk $r) }
    $script:NCONV++
}
function Std-Imports([string]$ind, $extra) {
    $l = @(foreach ($x in (@('ScalarValues', 'ISQ', 'SI') + @($extra | Where-Object { $null -ne $_ }))) { "${ind}private import ${x}::*;" })
    if ($script:OPT['marking']) { $l += "${ind}private import SecMeta::*;" }
    if ($script:OPT['provenance']) { $l += "${ind}private import V1Provenance::*;" }
    if ($script:OPT['marking']) { $l += "$ind@Marking { level = Level::$($script:OPT['marking']); }" }
    return ,$l
}
function Emit-Package($p, $lst, [string]$ind) {
    $from = $p
    $lst.l += "${ind}package " + (Qid $p.v2) + ' {' + (Mk $p)
    $doc = Owned-Comments $p
    if ($doc -eq '' -and $p.top) { $doc = "Converted from SysML v1 package '$(QName $p)' by v1v2.pl." }
    $lst.l += (Doc-Lines $doc "$ind    ")
    if ($p.top) { $lst.l += (Std-Imports "$ind    " $null) }
    if ($p.kind -ceq 'package') { $lst.l += (Prov-Line $p "$ind    ") }
    $kids = @($p.kids); if ($null -ne $p.kidsOverride) { $kids = @($p.kidsOverride) }
    $k = @(foreach ($x in $kids) { if ($script:EMIT.ContainsKey($x.id)) { $x } })
    $order = @(foreach ($x in $k) { if ($x.kind -cmatch '^(?:valuetype|enum)$') { $x } }) + @(foreach ($x in $k) { if ($x.kind -ceq 'interfaceblock') { $x } }) + @(foreach ($x in $k) { if ($x.kind -cmatch '^(?:block|class|constraintblock)$') { $x } })
    foreach ($e in $order) { $lst.l += ''; Emit-Def $e $lst "$ind    " $from }
    foreach ($r in $k) { if ($r.kind -ceq 'requirement') { $lst.l += ''; Emit-Req $r $lst "$ind    " } }
    foreach ($s in $k) { if ($s.kind -ceq 'package') { $lst.l += ''; Emit-Package $s $lst "$ind    " } }
    foreach ($x in $kids) {
        if ($x.inside -or $x.kind -cnotmatch '^(?:behavior|usecase|instance|itemflow|allocate)$') { continue }
        if ($x.kind -ceq 'instance' -and $script:UNITMAP.ContainsKey((Squash $x.name).ToLowerInvariant())) { continue }
        if ($script:VERIFIER.ContainsKey($x.id)) { $lst.l += ''; $lst.l += "$ind    // v1 $($x.type) '$($x.name)': its verify relationships became a verification def"; continue }
        $lst.l += ''; $lst.l += "$ind    // v1 $($x.type) '$($x.name)' not converted"
        if ($x.kind -cmatch '^(?:behavior|usecase)$') { $sv = 'note' } else { $sv = 'warning' }
        Note $x $sv "$($x.type) '$(QName $x)' not converted"
    }
    $lst.l += "$ind}"
}
function Req-Path($r, $chain) {
    $rs = @(); $o = $r
    for (; $null -ne $o -and $o.kind -ceq 'requirement'; $o = $o.owner) { $rs = @(Qid $o.v2) + $rs }
    if ($chain) { $sep = '.' } else { $sep = '::' }
    return (Qn $o) + '::' + ($rs -join $sep)
}
function Emit-TracePackages([string]$base, $files) {
    $sat = @(); $ver = [hashtable]::new(); $verOrder = @(); $dep = @()
    foreach ($t in (Traces)) {
        $k = $t[0]; $cl = $t[1]; $su = $t[2]; $rec = $t[3]
        foreach ($s in $su) {
            $se = $script:ELEMS[$s]
            if (-not ($null -ne $se -and $se.kind -ceq 'requirement' -and $script:EMIT.ContainsKey($se.id))) {
                $why = $false
                if ($null -ne $se -and (In-Scope $se)) { $why = $true }
                else { foreach ($c in $cl) { if ($script:ELEMS.ContainsKey($c) -and $script:EMIT.ContainsKey($c)) { $why = $true } } }
                if ($why) { if ($null -ne $se) { $nm = "'$(QName $se)'" } else { $nm = $s }; Note $rec 'note' "$k to $nm skipped: not a converted requirement" }
                continue
            }
            foreach ($c in $cl) {
                $ce = $script:ELEMS[$c]
                if ($null -eq $ce) { Note $rec 'warning' "$k client $c is not in the file"; continue }
                if ($k -ceq 'satisfy') { $sat += ,@($ce, $se, $rec) }
                elseif ($k -ceq 'verify') { if (-not $ver.ContainsKey($ce.id)) { $ver[$ce.id] = @(); $verOrder += $ce.id }; $ver[$ce.id] += ,@($ce, $se, $rec) }
                elseif ($k -cmatch '^(?:derive|refine|trace|copy)$') { $dep += ,@($k, $ce, $se, $rec) }
                else { Note $rec 'warning' "$k from '$(QName $ce)' not converted" }
            }
        }
    }
    if ($sat.Count -gt 0) {
        $pk = @{ kind = 'package'; v2 = "${base}Satisfaction"; top = 1; id = 'sat'; kids = @() }
        $lst = @{ l = @("package $($pk.v2) {") }
        $lst.l += (Doc-Lines 'Satisfy relationships converted from SysML v1 by v1v2.pl. One part usage per satisfying block, so that each satisfy has a feature to name.' '    ')
        $lst.l += (Std-Imports '    ' $null)
        $use = [hashtable]::new()
        foreach ($x in $sat) {
            $ce = $x[0]; $se = $x[1]; $rec = $x[2]
            $by = $null
            if ($ce.kind -cmatch '^(?:block|class)$') { $by = Sat-Usage $ce $use $lst }
            elseif ($ce.kind -cmatch '^(?:property|port)$' -and $script:EMIT.ContainsKey($ce.id) -and $ce.owner.kind -cmatch '^(?:block|class)$') { $by = (Sat-Usage $ce.owner $use $lst) + '.' + (Qid $ce.v2) }
            else { Note $rec 'warning' "satisfy from $($ce.kind) '$(QName $ce)' not converted; needs a part or feature"; continue }
            $lst.l += "    satisfy $(Req-Path $se 1) by $by;"; $script:NCONV++
        }
        $lst.l += '}'
        $files["configurations/$($pk.v2).sysml"] = $lst.l
    }
    if ($verOrder.Count -gt 0) {
        $pk = "${base}Verification"
        $lst = @{ l = @("package $pk {") }
        $lst.l += (Doc-Lines 'Verification cases converted from SysML v1 verify relationships by v1v2.pl. The v1 test behavior is not converted; each case holds only its objective.' '    ')
        $lst.l += (Std-Imports '    ' $null)
        $tk = [hashtable]::new()
        $ids = @($verOrder)
        $ids = SortByKey $ids @(foreach ($id in $ids) { NumKey $ver[$id][0][0].line })
        foreach ($id in $ids) {
            $ce = $ver[$id][0][0]
            $n = Camel $ce.name $true; if ($n -eq '') { $n = 'UnnamedVerification' }
            if ($n -cnotmatch '(?:Test|Inspection|Analysis|Demonstration)$') { $n += 'Test' }
            $b = $n; $i = 1; while ($tk.ContainsKey($n.ToLowerInvariant())) { $i++; $n = $b + $i }; $tk[$n.ToLowerInvariant()] = 1
            $lst.l += ''; $lst.l += "    verification def $n {"
            $lst.l += (Doc-Lines "v1 verifier: '$(QName $ce)' ($($ce.type))." '        ')
            $lst.l += (Prov-Line $ce '        ')
            $lst.l += '        objective {'
            foreach ($x in $ver[$id]) { $lst.l += "            verify $(Req-Path $x[1] 1);" }
            $lst.l += '        }'; $lst.l += '    }'
            $script:NCONV++
            Note $ce 'note' "verifier '$(QName $ce)' became verification def ${pk}::$n (objective only)"
        }
        $lst.l += '}'
        $files["evaluation/$pk.sysml"] = $lst.l
    }
    if ($dep.Count -gt 0) {
        $pk = "${base}Trace"
        $lst = @{ l = @("package $pk {") }
        $lst.l += (Doc-Lines 'SysML v1 deriveReqt, refine, trace and copy relationships, as dependencies from client to supplier. Generated by v1v2.pl.' '    ')
        $lst.l += (Std-Imports '    ' $null)
        foreach ($x in $dep) {
            $k = $x[0]; $ce = $x[1]; $se = $x[2]; $rec = $x[3]
            $cn = $null
            if ($ce.kind -ceq 'requirement' -and $script:EMIT.ContainsKey($ce.id)) { $cn = Req-Path $ce 0 }
            elseif ($script:EMIT.ContainsKey($ce.id) -and $ce.kind -cmatch $script:DEFRE) { $cn = Qn $ce }
            if (-not $cn) { Note $rec 'warning' "$k from '$(QName $ce)' not converted"; continue }
            $lst.l += "    dependency from $cn to $(Req-Path $se 0); // v1 $k"; $script:NCONV++
        }
        $lst.l += '}'
        $files["requirements/$pk.sysml"] = $lst.l
    }
}
function Sat-Usage($b, $use, $lst) {
    if (-not $script:EMIT.ContainsKey($b.id) -and -not $b.stub) { $b = Stub-For $b }
    if ($use.ContainsKey($b.id)) { return $use[$b.id] }
    $n = Camel $b.v2 $false; $base = $n; $i = 1
    while ($script:TAKEN.ContainsKey("sat`0$n")) { $i++; $n = $base + $i }
    $script:TAKEN["sat`0$n"] = 1
    $lst.l += ''; $lst.l += "    part $n : $(Qn $b);"
    $use[$b.id] = $n
    return $n
}
function Find-Scope($qn) {
    if ($null -eq $qn) { if ($null -eq $script:MODEL) { Fail "$($script:IN): no uml:Model element" }; return $script:MODEL }
    $hit = @(foreach ($e in $script:ALLREC) { if ($e.kind -cmatch '^(?:package|model)$' -and (QName $e) -ceq $qn) { $e } })
    if ($hit.Count -ne 1) {
        $msg = "$($script:IN): no package '$qn'"
        if ($hit.Count -eq 0) { $msg += '; packages: ' + ((@(foreach ($e in $script:ALLREC) { if ($e.kind -ceq 'package' -and ($e.owner -eq $script:MODEL)) { QName $e } })) -join ', ') }
        Fail $msg
    }
    return $hit[0]
}
function Notes-Sorted { return ,@(foreach ($d in (Sorted-Diags $script:NOTELIST)) { $d[2] }) }
function In-Tree($e, $t) { for ($o = $e; $null -ne $o; $o = $o.owner) { if (($o -eq $t)) { return $true }; if ($o.top -and ($o -ne $t)) { return $false } }; return $false }

function Cmd-Convert {
    if (-not $script:OPT['o']) { Fail 'convert needs -o DIR' }
    if ($null -ne $script:OPT['marking'] -and $script:OPT['marking'] -cnotmatch '^\w+$') { Fail '--marking must be an identifier' }
    Load-Model $script:IN
    $script:SCOPEREC = Find-Scope $script:OPT['package']
    foreach ($t in (Traces)) { if ($t[0] -cne 'verify') { continue }; foreach ($x in $t[1]) { $script:VERIFIER[$x] = 1 } }
    foreach ($e in $script:ALLREC) {
        if (-not (In-Scope $e) -or $e.inside) { continue }
        if ($e.kind -cmatch '^(?:package|requirement|property|port|literal)$' -or $e.kind -cmatch $script:DEFRE) { $script:EMIT[$e.id] = 1 }
    }
    foreach ($e in $script:ALLREC) {
        if (-not $script:EMIT.ContainsKey($e.id) -or $e.kind -cne 'valuetype') { continue }
        $t = Resolve-Type $e.id
        if ($t.lib) { $script:EMIT.Remove($e.id); Note $e 'note' "value type '$(QName $e)' mapped to library type $($t.lib)" }
    }
    $tops = @()
    if ($script:SCOPEREC.kind -ceq 'model') {
        $tops = @(foreach ($x in $script:SCOPEREC.kids) { if ($x.kind -ceq 'package') { $x } })
        $loose = $false; foreach ($x in $script:SCOPEREC.kids) { if ($script:EMIT.ContainsKey($x.id) -and $x.kind -cne 'package') { $loose = $true } }
        if ($loose) { $tops += ,$script:SCOPEREC }
    } else { $tops = @(,$script:SCOPEREC) }
    $pre = Camel (Dfl $script:OPT['prefix'] '') $true
    $sn = 'Model'; if ($script:SCOPEREC.name -match '\S') { $sn = $script:SCOPEREC.name }
    $base = $pre + (Camel $sn $true)
    if ($base -eq '') { $base = $pre + 'Model' }
    foreach ($t in $tops) { $t.top = 1; $t.v2 = Top-PkgName $t }
    if ($script:SCOPEREC.kind -ceq 'model') {
        foreach ($e in $script:ALLREC) { if ($e.kind -ceq 'package' -and ($e.owner -eq $script:SCOPEREC)) { $script:EMIT.Remove($e.id) } }
        foreach ($t in $tops) { $script:EMIT[$t.id] = 1 }
    }
    $script:STUBPKG = @{ kind = 'package'; v2 = "${base}SliceStubs"; top = 1; id = 'stubs'; kids = @() }
    foreach ($t in $tops) { Name-Tree $t }
    $files = [hashtable]::new()
    foreach ($t in $tops) {
        $lst = @{ l = @() }
        if ($t.kind -ceq 'model') {
            $t.kidsOverride = @(foreach ($x in $t.kids) { if ($x.kind -cne 'package') { $x } })
            Emit-Package $t $lst ''
            $t.Remove('kidsOverride')
        } else { Emit-Package $t $lst '' }
        $onlyReq = $true
        foreach ($e in $script:ALLREC) { if ($script:EMIT.ContainsKey($e.id) -and (In-Tree $e $t) -and $e.kind -cmatch $script:DEFRE) { $onlyReq = $false; break } }
        if ($onlyReq) { $f = 'requirements/' } else { $f = 'architecture/' }
        $f += "$($t.v2).sysml"
        $files[$f] = $lst.l; $script:FILEOF[$t.id] = $f
    }
    Emit-TracePackages $base $files
    if ($script:STUBS.Count -gt 0) {
        $lst = @{ l = @("package $($script:STUBPKG.v2) {") }
        $lst.l += (Doc-Lines 'Stubs for definitions outside the converted slice. Replace each with the real definition, or widen the slice.' '    ')
        $lst.l += (Std-Imports '    ' $null)
        foreach ($s in $script:STUBS) { $lst.l += ''; $saved = $s.kids; $s.kids = @(); Emit-Def $s $lst '    ' $script:STUBPKG; $s.kids = $saved }
        $lst.l += '}'
        $files["library/$($script:STUBPKG.v2).sysml"] = $lst.l
    }
    if ($script:OPT['provenance']) {
        $pl = @('library package V1Provenance {')
        $pl += (Doc-Lines 'Where a converted element came from in the SysML v1 model: its XMI id and its v1 name. Generated by v1v2.pl.' '    ')
        $pl += '    private import ScalarValues::*;'
        if ($script:OPT['marking']) { $pl += '    private import SecMeta::*;'; $pl += "    @Marking { level = Level::$($script:OPT['marking']); }" }
        $pl += @('', '    metadata def V1Source {', '        doc /* Provenance of an element converted from SysML v1. */', '        attribute xmiId : String;', '        attribute v1Name : String;', '    }', '}')
        $files['library/V1Provenance.sysml'] = $pl
    }
    $out = $script:OPT['o']
    $stamp = "// Generated by v1v2.pl 1.0 from $(Base-Name $script:IN). Edit the result, not this tool output, once it is committed."
    $atmap = [hashtable]::new()
    $mkre = [regex]([char]1 + '([^' + [char]1 + ']*)' + [char]1)
    foreach ($f in (SortOrd $files.Keys)) {
        $path = "$out/model/$f"
        $ln = 1
        $txt = @($stamp)
        foreach ($fline in $files[$f]) {
            $ln++
            if ($fline.IndexOf([char]1) -ge 0) {
                foreach ($mm in $mkre.Matches($fline)) { $id = $mm.Groups[1].Value; if (-not $atmap.ContainsKey($id)) { $atmap[$id] = "model/${f}:$ln" } }
                $fline = $mkre.Replace($fline, '')
            }
            $txt += $fline
        }
        Write-TextFile $path (($txt -join "`n") + "`n")
    }
    $rows = @(foreach ($e in $script:ALLREC) {
        if (-not $script:EMIT.ContainsKey($e.id) -or $null -eq $e.v2) { continue }
        $where = [string](Dfl $atmap[$e.id] '')
        if ($e.kind -ceq 'requirement') { $q = Req-Path $e 1 } else { $q = Qn $e }
        "$($e.id)`t$($e.kind)`t$(QName $e)`t$q`t$where"
    })
    $tsv = "xmi_id`tv1_kind`tv1_name`tv2_name`tat`n"; if ($rows.Count -gt 0) { $tsv += ($rows -join "`n") + "`n" }
    Write-TextFile "$out/ids.tsv" $tsv
    $nren = 0; foreach ($k in $script:RENAMED.Keys) { if ($script:EMIT.ContainsKey($k)) { $nren++ } }
    $summary = "convert: $($files.Count) file(s) written, $($script:NCONV) element(s) converted, $nren renamed, $($script:STUBS.Count) stub(s), $($script:NMANUAL) to finish by hand"
    $notes = Notes-Sorted
    $hdr = "# v1v2.pl 1.0 convert $($script:IN)"; if ($script:OPT['package']) { $hdr += " --package '$($script:OPT['package'])'" }
    $conv = @($hdr, "# Locations point into the v1 XMI. 'warning' = finish by hand; 'note' = information.") + $notes + @($summary)
    Write-TextFile "$out/CONVERSION.txt" (($conv -join "`n") + "`n")
    $o2 = @(foreach ($n in $notes) { if ($n -cmatch ': warning: ') { $n } })
    $o2 += $summary
    $o2 += "see $out/CONVERSION.txt and $out/ids.tsv"
    Out-Text (($o2 -join "`n") + "`n")
    if ($script:NMANUAL) { $script:RC = 1 } else { $script:RC = 0 }
}
function Name-Tree($e) {
    foreach ($k in $e.kids) {
        if (-not $script:EMIT.ContainsKey($k.id)) { continue }
        if (-not $k.top) { if ($k.kind -cmatch $script:DEFRE -or $k.kind -ceq 'package') { $st = 'def' } else { $st = 'use' }; [void](V2Name $k $st $e.id) }
        Name-Tree $k
    }
}

# ================================================================ reqs
function Cmd-Reqs {
    if (-not $script:OPT['o']) { Fail 'reqs needs -o FILE.sysml' }
    if (-not $script:OPT['package']) { Fail 'reqs needs --package NAME' }
    if (-not (Ident-Ok $script:OPT['package'])) { Fail '--package must be an identifier' }
    if ($null -ne $script:OPT['marking'] -and $script:OPT['marking'] -cnotmatch '^\w+$') { Fail '--marking must be an identifier' }
    $script:OPT['provenance'] = 0
    $script:REQS_MODE = $true
    if ($script:IN -match '\.reqifz?$') { $r = Reqif-Rows $script:IN } else { $r = Csv-Rows $script:IN }
    $byid = [hashtable]::new(); $roots = @()
    foreach ($x in $r) { $x.kind = 'requirement'; $x.kids = @(); if ($null -eq $x.line) { $x.line = 1 }; if ($x.rid -ne '' -and -not $byid.ContainsKey($x.rid)) { $byid[$x.rid] = $x } }
    foreach ($x in $r) {
        $p = $x.up
        if ($null -eq $p -and $null -ne $x.parent -and $x.parent -ne '') {
            $p = $byid[$x.parent]; if ($null -eq $p) { Note $x 'warning' "parent '$($x.parent)' of '$($x.rid)' not found" }
        }
        if ($null -eq $p -and -not $script:OPT.ContainsKey('parent') -and $script:IN -notmatch '\.reqifz?$' -and $x.rid -cmatch '^(.+)[.\-]\w+$') { $p = $byid[$Matches[1]] }
        if ($null -ne $p) { $p.kids += ,$x; $x.owner = $p } else { $roots += ,$x }
    }
    foreach ($x in $r) { $script:EMIT[$x.id] = 1 }
    Name-Reqs $roots 'root'
    $lst = @{ l = @("package $($script:OPT['package']) {") }
    $lst.l += (Doc-Lines ("Requirements imported from " + (Base-Name $script:IN) + " by v1v2.pl. Add a subject and, where quantitative, a require constraint to each.") '    ')
    $lst.l += (Std-Imports '    ' $null)
    foreach ($x in $roots) { $lst.l += ''; Emit-Req $x $lst '    ' }
    $lst.l += '}'
    $mkre = [regex]([char]1 + '[^' + [char]1 + ']*' + [char]1)
    $txt = @("// Generated by v1v2.pl 1.0 from $(Base-Name $script:IN).") + @(foreach ($rl in $lst.l) { $mkre.Replace($rl, '') })
    Write-TextFile $script:OPT['o'] (($txt -join "`n") + "`n")
    $o2 = Notes-Sorted
    $noid = 0; $notext = 0; foreach ($x in $r) { if ($x.rid -eq '') { $noid++ }; if ($x.rtext -eq '') { $notext++ } }
    $o2 += "reqs: $(@($r).Count) requirement(s), $($roots.Count) top-level, $noid without id, $notext without text -> $($script:OPT['o'])"
    Out-Text (($o2 -join "`n") + "`n")
    if ($script:NMANUAL) { $script:RC = 1 } else { $script:RC = 0 }
}
function Name-Reqs($list, $scope) { foreach ($x in $list) { [void](V2Name $x 'use' $scope); Name-Reqs $x.kids $x.id } }
function Csv-Rows([string]$f) {
    $t = Slurp $f
    $rows = @(); $row = @(); $field = ''; $line = 1; $rowline = 1; $pos = 0; $len = $t.Length
    $reQuote = [regex]'\G"((?:[^"]|"")*)"'; $reField = [regex]'\G([^",\n]+)'
    while ($pos -lt $len) {
        $m = $reQuote.Match($t, $pos)
        if ($m.Success) { $v = $m.Groups[1].Value.Replace('""', '"'); $line += NLCount $v; $field += $v; $pos += $m.Length; continue }
        $m = $reField.Match($t, $pos)
        if ($m.Success) { $field += $m.Groups[1].Value; $pos += $m.Length; continue }
        $ch = $t[$pos]
        if ($ch -ceq ',') { $row += ,$field; $field = ''; $pos++; continue }
        if ($ch -ceq "`n") { $row += ,$field; $rows += ,(@($rowline) + $row); $row = @(); $field = ''; $line++; $rowline = $line; $pos++; continue }
        Fail "${f}:${line}: bad CSV quoting"
    }
    $row += ,$field
    $any = $false; foreach ($x in $row) { if ($x.Length) { $any = $true } }
    if ($any) { $rows += ,(@($rowline) + $row) }
    if ($rows.Count -eq 0) { Fail "${f}: empty CSV" }
    $hdr = $rows[0]; $rows = @($rows | Select-Object -Skip 1)
    $h = @($hdr | Select-Object -Skip 1)
    $col = {
        param($optName, $re)
        for ($i = 0; $i -lt $h.Count; $i++) {
            if ($null -ne $script:OPT[$optName]) { if ((Squash $h[$i]).ToLowerInvariant() -ceq $script:OPT[$optName].ToLowerInvariant()) { return $i } }
            elseif ($h[$i] -match $re) { return $i }
        }
        if ($null -ne $script:OPT[$optName]) { Fail ("${f}: no column '$($script:OPT[$optName])'; columns: " + ($h -join ', ')) }
        return $null
    }
    $ci = & $col 'id' '^\s*(?:id|req(?:uirement)?[ _]?id|identifier)\s*$'
    $cn = & $col 'name' '^\s*(?:name|title)\s*$'
    $ct = & $col 'text' '^\s*(?:text|description|requirement text|shall)\s*$'
    $cp = & $col 'parent' '^\s*(?:parent|parent id|owner)\s*$'
    if ($null -eq $ci -and $null -eq $ct) { Fail ("${f}: need an id or a text column (use --id and --text); columns: " + ($h -join ', ')) }
    $out = @(); $n = 0
    foreach ($row in $rows) {
        $ln = $row[0]; $v = @($row | Select-Object -Skip 1)
        $any = $false; foreach ($x in $v) { if ($x -match '\S') { $any = $true } }
        if (-not $any) { continue }
        $n++
        $get = { param($c) if ($null -eq $c -or $c -ge $v.Count) { return '' }; return $v[$c] }
        $par = $null; if ($null -ne $cp) { $par = Squash (& $get $cp) }
        $out += ,@{ id = "csv$n"; line = $ln; rid = (Squash (& $get $ci)); name = (Squash (& $get $cn)); rtext = (Squash (Html2Text (& $get $ct))); parent = $par }
    }
    return ,$out
}
function Find-Tag($n, [string]$tag) {
    return ,@(foreach ($k in $n.kids) { if ($k.tag -ceq '#text') { continue }; if ($k.tag -ceq $tag) { $k }; Find-Tag $k $tag | ForEach-Object { $_ } })
}
function Reqif-Rows([string]$f) {
    try { $pr = Parse-Xml (Slurp $f) $f $null } catch { if ($_.Exception.Message -ceq 'V1V2EXIT2') { throw }; Out-Err ($_.Exception.Message -creplace '\n$', ''); throw 'V1V2EXIT2' }
    $doc = $pr[0]
    $adef = [hashtable]::new(); $obj = [hashtable]::new(); $all = @()
    foreach ($tg in @('STRING', 'XHTML', 'ENUMERATION', 'INTEGER', 'REAL', 'DATE', 'BOOLEAN')) {
        foreach ($d in (Find-Tag $doc "ATTRIBUTE-DEFINITION-$tg")) { $ln = $d.a['LONG-NAME']; if ($null -eq $ln) { $ln = $d.a['IDENTIFIER'] }; $adef[[string]$d.a['IDENTIFIER']] = $ln }
    }
    $pick = { param($optName, $re, $n) if ($null -ne $script:OPT[$optName]) { return ($n.ToLowerInvariant() -ceq $script:OPT[$optName].ToLowerInvariant()) }; return ($n -match $re) }
    foreach ($o in (Find-Tag $doc 'SPEC-OBJECT')) {
        $r = @{ id = $o.a['IDENTIFIER']; line = $o.line; rid = ''; name = [string](Dfl $o.a['LONG-NAME'] ''); rtext = '' }
        $vals = Kid $o 'VALUES'
        if ($null -ne $vals) {
            foreach ($v in (Elems $vals)) {
                $def = Kid $v 'DEFINITION'; if ($null -eq $def) { continue }
                $refs = Elems $def; if ($refs.Count -eq 0) { continue }
                $an = $adef[(Squash (Text-Of $refs[0]))]; if ($null -eq $an) { continue }
                if ($null -ne $v.a['THE-VALUE']) { $val = $v.a['THE-VALUE'] } else { $tv = Kid $v 'THE-VALUE'; if ($null -ne $tv) { $val = Text-Of $tv } else { $val = '' } }
                $val = Squash (Html2Text $val)
                if (& $pick 'id' '^(?:ReqIF\.ForeignID|Id|ID|Identifier|Req(?:uirement)?\s*ID)$' $an) { $r.rid = $val }
                elseif (& $pick 'text' '^(?:ReqIF\.Text|Text|Description|Object Text)$' $an) { $r.rtext = $val }
                elseif (& $pick 'name' '^(?:ReqIF\.Name|Name|Title|ReqIF\.ChapterName)$' $an) { $r.name = $val }
            }
        }
        if ($r.rid -eq '' -and $null -eq $script:OPT['id']) { $r.rid = [string](Dfl $o.a['IDENTIFIER'] '') }
        $obj[[string]$r.id] = $r; $all += ,$r
    }
    $script:RQ_ORDER = @()
    foreach ($s in (Find-Tag $doc 'SPECIFICATION')) { $ch = Kid $s 'CHILDREN'; if ($null -ne $ch) { Reqif-Walk $ch $null $obj } }
    $order = @($script:RQ_ORDER) + @(foreach ($x in $all) { if (-not $x.placed) { $x } })
    $rel = Find-Tag $doc 'SPEC-RELATION'
    if ($rel.Count -gt 0) { Note $null 'note' "$($rel.Count) SPEC-RELATION(s) not converted" }
    return ,$order
}
function Reqif-Walk($n, $parent, $obj) {
    foreach ($h in (Elems $n)) {
        if ($h.tag -cne 'SPEC-HIERARCHY') { continue }
        $ob = Kid $h 'OBJECT'; $ref = $null; if ($null -ne $ob) { $e = Elems $ob; if ($e.Count -gt 0) { $ref = $e[0] } }
        $r = $null; if ($null -ne $ref) { $r = $obj[(Squash (Text-Of $ref))] }
        if ($null -ne $r) { $was = $r.placed; $r.placed = 1 + [int]$r.placed; if (-not $was) { $r.up = $parent; $script:RQ_ORDER += ,$r } }
        $ch = Kid $h 'CHILDREN'
        if ($null -ne $ch) { $np = $parent; if ($null -ne $r) { $np = $r }; Reqif-Walk $ch $np $obj }
    }
}

# ================================================================ main
function Usage {
    Out-Err ("  perl v1v2.pl inventory MODEL [--tsv]`n  perl v1v2.pl check     MODEL [--typemap F]`n" +
             "  perl v1v2.pl convert   MODEL -o DIR [--package V1::QN] [--prefix P] [--marking LEVEL]`n" +
             "                         [--keep-names] [--no-provenance] [--typemap F]`n" +
             "  perl v1v2.pl reqs      REQS -o FILE.sysml --package NAME [--marking LEVEL]`n" +
             "                         [--id COL] [--name COL] [--text COL] [--parent COL]")
    throw 'V1V2EXIT2'
}
function Main-V1V2([string[]]$argv) {
    $cmd = ''; $rest = @()
    if ($argv.Count -gt 0) { $cmd = $argv[0]; if ($argv.Count -gt 1) { $rest = $argv[1..($argv.Count - 1)] } }
    $spec = @{ 'o' = 's'; 'package' = 's'; 'prefix' = 's'; 'marking' = 's'; 'keep-names' = ''; 'provenance' = '!'; 'typemap' = 's'; 'tsv' = ''; 'id' = 's'; 'name' = 's'; 'text' = 's'; 'parent' = 's' }
    $args2 = @(); $ok = $true
    for ($i = 0; $i -lt $rest.Count; $i++) {
        $a = $rest[$i]
        if ($a -ceq '--') { if ($i + 1 -lt $rest.Count) { $args2 += $rest[($i + 1)..($rest.Count - 1)] }; break }
        if ($a -cnotmatch '^--?([A-Za-z][A-Za-z0-9_-]*)(=([\s\S]*))?$') { $args2 += $a; continue }
        $nm = $Matches[1]; $hasv = $null -ne $Matches[2]; $val = $Matches[3]
        $neg = $false
        $hits = @(foreach ($k in $spec.Keys) { if ($k -ceq $nm) { $k } })
        if ($hits.Count -eq 0 -and $nm -cmatch '^no-?(.+)$') { $base = $Matches[1]; if ($spec.ContainsKey($base) -and $spec[$base] -ceq '!') { $hits = @($base); $neg = $true } }
        if ($hits.Count -eq 0) {
            $hits = @(foreach ($k in $spec.Keys) { if ($k.StartsWith($nm, 'Ordinal')) { $k } })
            if ($hits.Count -eq 0 -and $nm -cmatch '^no-?(.+)$') { $b2 = $Matches[1]; $hits = @(foreach ($k in $spec.Keys) { if ($spec[$k] -ceq '!' -and $k.StartsWith($b2, 'Ordinal')) { $k } }); if ($hits.Count -eq 1) { $neg = $true } }
        }
        if ($hits.Count -ne 1) {
            if ($hits.Count -gt 1) { Out-Err "Option $nm is ambiguous ($((SortOrd $hits) -join ', '))" } else { Out-Err "Unknown option: $nm" }
            $ok = $false; continue
        }
        $k = $hits[0]
        if ($spec[$k] -ceq 's') {
            if (-not $hasv) { if ($i + 1 -ge $rest.Count) { Out-Err "Option $k requires an argument"; $ok = $false; continue }; $i++; $val = $rest[$i] }
            $script:OPT[$k] = $val
        } elseif ($spec[$k] -ceq '!') { if ($neg) { $script:OPT[$k] = 0 } else { $script:OPT[$k] = 1 } }
        else { $script:OPT[$k] = 1 }
    }
    if (-not $ok) { Usage }
    if ($args2.Count -eq 0) { Usage }
    $script:IN = $args2[0]
    if ($args2.Count -gt 1) { Usage }
    switch -CaseSensitive ($cmd) {
        'inventory' { Cmd-Inventory; return }
        'check' { Cmd-Check; return }
        'convert' { Cmd-Convert; return }
        'reqs' { Cmd-Reqs; return }
        default { Usage }
    }
}

if ($args.Count -ge 1 -and $args[0] -ceq '__lib') { return }
$script:RC = 0
try { Main-V1V2 ([string[]]@($args)) }
catch {
    if ($_.Exception.Message -ceq 'V1V2EXIT2') { $script:RC = 2 }
    else { Out-Err ($_.Exception.Message -creplace '\n$', ''); if ($env:V1V2_DEBUG) { Out-Err $_.InvocationInfo.PositionMessage; Out-Err $_.ScriptStackTrace }; $script:RC = 255 }
}
if ($PSCommandPath) { exit $script:RC }
$global:LASTEXITCODE = $script:RC
