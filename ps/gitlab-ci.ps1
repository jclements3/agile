<#
gitlab-ci.ps1 -- .gitlab-ci.yml, offline, for a PowerShell-only PC (the kit's lib/GitLabCI.pm, `gitlab.pl ci`).

Windows PowerShell 5.1, Constrained Language Mode safe, pure ASCII. A YAML-subset reader, GitLab's job selection
(workflow:rules, rules, only/except, extends, default, hidden jobs, stages, local includes with include:rules) and a
local runner. The job plan (--list) is the same as the Perl kit's, line for line.

  gitlab-ci.cmd [--file .gitlab-ci.yml] [--event push|merge_request_event|tag|schedule|web|trigger]
                [--branch B] [--target B] [--tag T] [--var K=V]... [--job NAME]... [--manual] [--logs DIR] [--list]

Git: there is no git on this PC. The repository facts GitLab would give a pipeline (the commit, the branch, the
default branch, the commit title, the files a push or merge request changed) are read from the .git folder with
pgit.ps1 (beside this file), which reads loose objects. A repository with pack files must be unpacked once.

Running jobs: the Perl kit runs each job's script in `sh -e`. This PC has no sh, so a job runs only when it says it
is a PowerShell job: `tags: [powershell]` (or pwsh), or the job variable KIT_SHELL: powershell. Its before_script and
script lines then run in a child powershell.exe, stopping at the first failing line (like sh -e); after_script runs
after, with CI_JOB_STATUS. Every other job is reported "not run (needs bash)": it is never counted as passed, and the
pipeline is then "incomplete" (exit 3) unless something failed (exit 1).

Library: . .\gitlab-ci.ps1 __lib   defines GciParseYaml, GciEvalIf, GciLoad, GciPlan, GciRun without running.
#>

$ErrorActionPreference = 'Stop'

# ================================================================ data: YAML maps keep their key order
# A YAML map is a case-sensitive hashtable whose key "`0" holds the key order; a list is an object[]; a scalar is a
# string or $null; a !reference is a hashtable with key "`1".
function GciNewMap { $m = [hashtable]::new([StringComparer]::Ordinal); $m["`0"] = @(); return $m }
function GciOMap { return [hashtable]::new([StringComparer]::Ordinal) }
function GciIsMap($v) { return (($v -is [hashtable]) -and $v.ContainsKey("`0")) }
function GciIsRef($v) { return (($v -is [hashtable]) -and $v.ContainsKey("`1")) }
function GciIsList($v) { return ($v -is [array]) }
function GciKeys($m) { return , ([object[]]$m["`0"]) }
function GciSet($m, [string]$k, $v) { if (-not $m.ContainsKey($k)) { $m["`0"] = [object[]]$m["`0"] + @($k) }; $m[$k] = $v }
function GciDel($m, [string]$k) {
    if (-not $m.ContainsKey($k)) { return }
    $m.Remove($k)
    $o = @(); foreach ($x in $m["`0"]) { if ($x -cne $k) { $o += $x } }; $m["`0"] = $o
}
function GciSortOrd($a) {
    $c = [string[]]@($a)
    if ($c.Count -lt 2) { return , $c }
    [Array]::Sort($c, [StringComparer]::Ordinal)
    return , $c
}
function GciClone($v) {
    if (GciIsMap $v) { $n = GciNewMap; foreach ($k in (GciKeys $v)) { GciSet $n $k (GciClone $v[$k]) }; return $n }
    if (GciIsRef $v) { return $v }
    if (GciIsList $v) { $a = @(); foreach ($x in $v) { $a += , (GciClone $x) }; return , $a }
    return $v
}
function GciDie([string]$msg) { throw ('GCIDIE:' + $msg) }

# ================================================================ YAML subset
$script:KEY_RE = '^(?:"(?:[^"\\]|\\.)*"|''(?:[^'']|'''')*''|[^\s\-\[\]{},#&*!|>''"%@`?](?:[^:]|:(?!\s|$))*?|-[^\s:](?:[^:]|:(?!\s|$))*?)\s*:(?=\s|$)'

function GciParseYaml($text, [string]$file = 'yaml') {
    if ($null -eq $text) { $text = '' }
    if ($text.Length -gt 0 -and [int]$text[0] -eq 0xFEFF) { $text = $text.Substring(1) }
    $text = $text.Replace("`r`n", "`n").Replace("`r", "`n")
    $raw = $text.Split("`n")
    $LA = @()
    for ($i = 0; $i -lt $raw.Count; $i++) {
        $r = $raw[$i]; $n = 0; while ($n -lt $r.Length -and $r[$n] -eq ' ') { $n++ }
        $LA += , @{ n = $i + 1; indent = $n; raw = $r; text = $r.Substring($n) }
    }
    $script:YP = @{ L = $LA; i = 0; file = $file; anchors = (GciOMap) }
    $script:ROOTORDER = $null
    GciSkipBlank
    if ($script:YP.i -lt $LA.Count -and $LA[$script:YP.i].indent -eq 0 -and $LA[$script:YP.i].text -cmatch '^---\s*(?:#.*)?$') { $script:YP.i++; GciSkipBlank }
    if ($script:YP.i -ge $LA.Count) { return $null }
    $v = GciNode $LA[$script:YP.i].indent
    GciSkipBlank
    if ($script:YP.i -lt $LA.Count) {
        $l = $LA[$script:YP.i]
        if ($l.text -cnotmatch '^(?:\.\.\.|---)\s*$') { GciErr $l 'unexpected content (bad indentation?)' }
    }
    if (GciIsMap $v) { $script:ROOTORDER = (GciKeys $v) }
    return , $v
}

function GciErr($l, [string]$msg) {
    $n = if ($l) { $l.n } else { $script:YP.L.Count }
    GciDie ($script:YP.file + ':' + $n + ': ' + $msg)
}

function GciSkipBlank {
    $LA = $script:YP.L
    while ($script:YP.i -lt $LA.Count) {
        $l = $LA[$script:YP.i]
        if ($l.text -cmatch '^\t' -and $l.text -cmatch '\S' -and $l.text -cnotmatch '^\s*#') { GciErr $l 'tabs are not allowed in indentation' }
        if ((GciStrip $l.text) -cne '') { break }
        $script:YP.i++
    }
}

function GciStrip([string]$s) {               # drop a trailing comment (a # at the start or after whitespace, outside quotes)
    $q = ''
    for ($k = 0; $k -lt $s.Length; $k++) {
        $c = [string]$s[$k]
        if ($q -ne '') {
            if ($q -ceq '"' -and $c -ceq '\') { $k++; continue }
            if ($c -ceq $q) {
                if ($q -ceq "'" -and $k + 1 -lt $s.Length -and [string]$s[$k + 1] -ceq "'") { $k++; continue }
                $q = ''
            }
            continue
        }
        if (($c -ceq '"' -or $c -ceq "'") -and $s.Substring(0, $k) -cmatch '(?:^|[\[\{,]|[:\-?]\s)\s*$') { $q = $c; continue }
        if ($c -ceq '#' -and ($k -eq 0 -or [string]$s[$k - 1] -cmatch '\s')) { $s = $s.Substring(0, $k); break }
    }
    return ($s -creplace '\s+$', '')
}

function GciIsKey([string]$t) { return ($t -cmatch $script:KEY_RE) }
function GciSplitKey([string]$t) {
    if ($t -cnotmatch '^("(?:[^"\\]|\\.)*"|''(?:[^'']|'''')*''|.*?)\s*:(?=\s|$)\s*(.*)$') { return $null }
    $k = $Matches[1]; $rest = $Matches[2]
    if ($k -cmatch '^"(.*)"$') { $k = GciUnescape $Matches[1] }
    elseif ($k -cmatch "^'(.*)'$") { $k = $Matches[1].Replace("''", "'") }
    return , @($k, $rest)
}

function GciNode([int]$ind) {
    $l = $script:YP.L[$script:YP.i]
    $t = GciStrip $l.text
    if ($t -cmatch '^-(?:\s|$)') { return , (GciList $ind) }
    if (GciIsKey $t) { return , (GciMapNode $ind) }
    $script:YP.i++
    return , (GciValue $t $l ($ind - 1))
}

function GciMapNode([int]$ind) {
    $LA = $script:YP.L
    $h = GciNewMap
    $merges = @()
    while ($true) {
        GciSkipBlank
        if ($script:YP.i -ge $LA.Count) { break }
        $l = $LA[$script:YP.i]
        if ($l.indent -lt $ind) { break }
        if ($l.indent -gt $ind) { GciErr $l 'bad indentation' }
        $t = GciStrip $l.text
        if ($ind -eq 0 -and $t -cmatch '^(?:---|\.\.\.)$') { break }
        if (-not (GciIsKey $t)) { GciErr $l ("expected 'key: value', found '" + $t + "'") }
        $kr = GciSplitKey $t
        $k = $kr[0]; $rest = $kr[1]
        $script:YP.i++
        $v = GciAfterKey $rest $l $ind
        if ($k -ceq '<<') {
            $ms = if (GciIsList $v) { $v } else { @(, $v) }
            foreach ($m in $ms) { if (-not (GciIsMap $m)) { GciErr $l 'the merge key << needs a map (or a list of maps)' }; $merges += , $m }
            continue
        }
        if ($h.ContainsKey($k)) { GciErr $l ("duplicate key '" + $k + "'") }
        GciSet $h $k $v
    }
    foreach ($m in $merges) {
        foreach ($k in (GciSortOrd (GciKeys $m))) { if ($h.ContainsKey($k)) { continue }; GciSet $h $k $m[$k] }
    }
    return , $h
}

function GciList([int]$ind) {
    $LA = $script:YP.L
    $a = @()
    while ($true) {
        GciSkipBlank
        if ($script:YP.i -ge $LA.Count) { break }
        $l = $LA[$script:YP.i]
        if ($l.indent -lt $ind) { break }
        if ($l.indent -gt $ind) { GciErr $l 'bad indentation' }
        if ($l.text -cnotmatch '^-(\s+|$)') { break }
        $gap = $Matches[1].Length
        if ((GciStrip $l.text.Substring(1)) -ceq '') {
            $script:YP.i++
            GciSkipBlank
            if ($script:YP.i -lt $LA.Count -and $LA[$script:YP.i].indent -gt $ind) { $a += , (GciNode $LA[$script:YP.i].indent) }
            else { $a += , $null }
            continue
        }
        $l.indent += 1 + $gap
        $l.text = $l.text.Substring(1 + $gap)
        $a += , (GciNode $l.indent)
    }
    return , $a
}

function GciAfterKey([string]$rest, $l, [int]$ind) {
    if ($rest -cne '') { return , (GciValue $rest $l $ind) }
    $LA = $script:YP.L
    GciSkipBlank
    if ($script:YP.i -ge $LA.Count) { return $null }
    $n = $LA[$script:YP.i]
    if ($n.indent -gt $ind) { return , (GciNode $n.indent) }
    if ($n.indent -eq $ind -and $n.text -cmatch '^-(?:\s|$)') { return , (GciList $ind) }
    return $null
}

function GciValue([string]$s, $l, [int]$ind) {
    if ($s -cmatch '^&([^\s\[\]{},]+)\s*(.*)$') {
        $name = $Matches[1]; $rest = $Matches[2]
        $v = if ($rest -ceq '') { GciAfterKey '' $l $ind } else { GciValue $rest $l $ind }
        $script:YP.anchors[$name] = $v
        return , $v
    }
    if ($s -cmatch '^\*([^\s\[\]{},]+)$') {
        $nm = $Matches[1]
        if (-not $script:YP.anchors.ContainsKey($nm)) { GciErr $l ('unknown alias *' + $nm) }
        return , (GciClone $script:YP.anchors[$nm])
    }
    if ($s -cmatch '^!reference\s*(.*)$') {
        $ref = GciFlowValue $Matches[1] $l
        if (-not (GciIsList $ref) -or $ref.Count -eq 0) { GciErr $l '!reference needs a list: !reference [job, key]' }
        return , @{ "`1" = $true; path = $ref; line = $l.n; file = $script:YP.file }
    }
    if ($s -cmatch '^!') { $s = $s -creplace '^!!?\w+\s+', '' }
    if ($s -cmatch '^([|>])([+-]?)([1-9]?)([+-]?)$') {
        $ch = $Matches[2]; if ($ch -ceq '') { $ch = $Matches[4] }
        $dg = 0; if ($Matches[3] -cne '') { $dg = [int]$Matches[3] }
        return (GciBlock $ind $Matches[1] $ch $dg)
    }
    if ($s -cmatch '^[\[\{]') { return , (GciFlowValue $s $l) }
    if ($s -cmatch '^"') {
        if ($s -cnotmatch '^"((?:[^"\\]|\\.)*)"(.*)$') { GciErr $l 'unterminated "string"' }
        $body = $Matches[1]; $after = $Matches[2]
        if ($after -cne '') { GciErr $l ("unexpected text after a quoted string: '" + $after + "'") }
        return (GciUnescape $body)
    }
    if ($s -cmatch "^'") {
        if ($s -cnotmatch "^'((?:[^']|'')*)'(.*)$") { GciErr $l "unterminated 'string'" }
        $body = $Matches[1]; $after = $Matches[2]
        if ($after -cne '') { GciErr $l ("unexpected text after a quoted string: '" + $after + "'") }
        return $body.Replace("''", "'")
    }
    $LA = $script:YP.L
    while ($script:YP.i -lt $LA.Count) {
        $n = $LA[$script:YP.i]
        $t = GciStrip $n.text
        if ($t -ceq '') {
            $j = $script:YP.i; while ($j -lt $LA.Count -and (GciStrip $LA[$j].text) -ceq '') { $j++ }
            if (-not ($j -lt $LA.Count -and $LA[$j].indent -gt $ind -and -not (GciIsKey (GciStrip $LA[$j].text)))) { break }
            $script:YP.i = $j; continue
        }
        if ($n.indent -le $ind) { break }
        if ((GciIsKey $t) -or $t -cmatch '^-(?:\s|$)') { break }
        $s += ' ' + $t
        $script:YP.i++
    }
    return (GciPlain $s)
}

function GciPlain([string]$s) {
    $s = $s -creplace '^\s+|\s+$', ''
    if ($s -ceq '' -or $s -ceq '~' -or $s -ceq 'null' -or $s -ceq 'Null' -or $s -ceq 'NULL') { return $null }
    return $s
}

function GciUnescape([string]$s) {
    $o = ''
    for ($k = 0; $k -lt $s.Length; $k++) {
        $c = [string]$s[$k]
        if ($c -cne '\' -or $k + 1 -ge $s.Length) { $o += $c; continue }
        $e = [string]$s[$k + 1]
        if ($e -ceq 'x' -and $k + 3 -lt $s.Length -and $s.Substring($k + 2, 2) -cmatch '^[0-9a-fA-F]{2}$') { $o += [string][char]([int]('0x' + $s.Substring($k + 2, 2))); $k += 3; continue }
        if ($e -ceq 'u' -and $k + 5 -lt $s.Length -and $s.Substring($k + 2, 4) -cmatch '^[0-9a-fA-F]{4}$') { $o += [string][char]([int]('0x' + $s.Substring($k + 2, 4))); $k += 5; continue }
        $k++
        switch -CaseSensitive ($e) {
            'n' { $o += "`n" } 't' { $o += "`t" } 'r' { $o += "`r" } '0' { $o += [string][char]0 } 'e' { $o += [string][char]27 }
            'a' { $o += [string][char]7 } 'b' { $o += [string][char]8 } '"' { $o += '"' } '\' { $o += '\' } '/' { $o += '/' } ' ' { $o += ' ' }
            default { $o += '\' + $e }
        }
    }
    return $o
}

function GciBlock([int]$ind, [string]$style, [string]$chomp, [int]$digit) {
    $LA = $script:YP.L
    $lines = @()
    $cind = -1
    if ($digit) { $cind = $ind + $digit }
    while ($script:YP.i -lt $LA.Count) {
        $raw = $LA[$script:YP.i].raw
        if ($raw -cmatch '^\s*$') { $lines += ''; $script:YP.i++; continue }
        $n = 0; while ($n -lt $raw.Length -and $raw[$n] -eq ' ') { $n++ }
        if ($n -le $ind) { break }
        if ($cind -lt 0) { $cind = $n }
        if ($n -lt $cind) { break }
        $lines += $raw.Substring($cind)
        $script:YP.i++
    }
    $trail = 0
    while ($lines.Count -gt 0 -and $lines[$lines.Count - 1] -ceq '') {
        if ($lines.Count -eq 1) { $lines = @() } else { $lines = $lines[0..($lines.Count - 2)] }
        $trail++
    }
    $lines = @($lines)
    if ($style -ceq '|') { $body = $lines -join "`n" }
    else {
        $body = ''; $prev = 0
        foreach ($x in $lines) {
            if ($x -ceq '') { $body += "`n"; $prev = 0; continue }
            if ($x -cmatch '^\s') { if ($prev) { $body += "`n" }; $body += $x; $prev = 2; continue }
            if ($prev -eq 1) { $body += ' ' } elseif ($prev -eq 2) { $body += "`n" }
            $body += $x
            $prev = 1
        }
    }
    if ($lines.Count -eq 0 -and $chomp -cne '+') { return '' }
    if ($chomp -ceq '-') { return $body }
    if ($chomp -ceq '+') { return $body + ("`n" * (1 + $trail)) }
    if ($lines.Count -gt 0) { return $body + "`n" }
    return ''
}

function GciFlowDepth([string]$s) {
    $d = 0; $q = ''
    for ($k = 0; $k -lt $s.Length; $k++) {
        $c = [string]$s[$k]
        if ($q -ne '') { if ($q -ceq '"' -and $c -ceq '\') { $k++; continue }; if ($c -ceq $q) { $q = '' }; continue }
        if ($c -ceq '"' -or $c -ceq "'") { $q = $c; continue }
        if ($c -ceq '[' -or $c -ceq '{') { $d++ }
        if ($c -ceq ']' -or $c -ceq '}') { $d-- }
    }
    return $d
}

function GciFlowValue([string]$s, $l) {
    $LA = $script:YP.L
    while ((GciFlowDepth $s) -gt 0) {
        if ($script:YP.i -ge $LA.Count) { GciErr $l 'unterminated flow collection ([ or { never closed)' }
        $t = GciStrip $LA[$script:YP.i].text
        $script:YP.i++
        $s += ' ' + $t
    }
    $script:FS = $s; $script:FP = 0; $script:FL = $l
    $v = GciFNode ''
    $rest = $script:FS.Substring($script:FP) -creplace '^\s+', ''
    if ($rest -cne '') { GciErr $l ("unexpected text after a flow collection: '" + $rest + "'") }
    return , $v
}

function GciFWs { while ($script:FP -lt $script:FS.Length -and [string]$script:FS[$script:FP] -cmatch '\s') { $script:FP++ } }
function GciFCh { if ($script:FP -lt $script:FS.Length) { return [string]$script:FS[$script:FP] }; return '' }
function GciFAt([int]$n) { $r = $script:FS.Substring($script:FP); if ($r.Length -gt $n) { return $r.Substring(0, $n) }; return $r }

function GciFNode([string]$stop) {
    $l = $script:FL
    GciFWs
    $c = GciFCh
    if ($c -ceq '[') {
        $script:FP++
        $a = @()
        while ($true) {
            GciFWs
            if ($script:FP -ge $script:FS.Length) { GciErr $l 'unterminated [ list' }
            if ((GciFCh) -ceq ']') { $script:FP++; break }
            $a += , (GciFNode '')
            GciFWs
            $d = GciFCh
            if ($d -ceq ',') { $script:FP++ }
            elseif ($d -ceq ']') { $script:FP++; break }
            else { GciErr $l ("expected ',' or ']' in a flow list, found '" + (GciFAt 10) + "'") }
        }
        return , $a
    }
    if ($c -ceq '{') {
        $script:FP++
        $h = GciNewMap
        while ($true) {
            GciFWs
            if ($script:FP -ge $script:FS.Length) { GciErr $l 'unterminated { map' }
            if ((GciFCh) -ceq '}') { $script:FP++; break }
            $k = GciFNode ':'
            GciFWs
            $v = $null
            if ((GciFCh) -ceq ':') {
                $script:FP++; GciFWs; $d = GciFCh
                if (-not ($d -ceq ',' -or $d -ceq '}')) { $v = GciFNode '' }
            }
            if ($null -eq $k) { $k = '' }
            if ($k -ceq '<<' -and (GciIsMap $v)) { foreach ($x in (GciSortOrd (GciKeys $v))) { if ($h.ContainsKey($x)) { continue }; GciSet $h $x $v[$x] } }
            else { GciSet $h ([string]$k) $v }
            GciFWs
            $d = GciFCh
            if ($d -ceq ',') { $script:FP++ }
            elseif ($d -ceq '}') { $script:FP++; break }
            else { GciErr $l ("expected ',' or '}' in a flow map, found '" + (GciFAt 10) + "'") }
        }
        return , $h
    }
    $rest = $script:FS.Substring($script:FP)
    if ($c -ceq '"') {
        if ($rest -cnotmatch '^"((?:[^"\\]|\\.)*)"') { GciErr $l 'unterminated "string"' }
        $script:FP += $Matches[1].Length + 2
        return (GciUnescape $Matches[1])
    }
    if ($c -ceq "'") {
        if ($rest -cnotmatch "^'((?:[^']|'')*)'") { GciErr $l "unterminated 'string'" }
        $script:FP += $Matches[1].Length + 2
        return $Matches[1].Replace("''", "'")
    }
    if ($c -ceq '*') {
        $null = $rest -cmatch '^\*([^\s\[\]{},]+)'
        $nm = $Matches[1]
        $script:FP += 1 + $nm.Length
        if (-not $script:YP.anchors.ContainsKey($nm)) { GciErr $l ('unknown alias *' + $nm) }
        return , (GciClone $script:YP.anchors[$nm])
    }
    $t = ''
    if ($rest -cmatch '^((?:[^,\[\]{}:]|:(?!\s|[,\]}]|$))*)') { $t = $Matches[1] }
    $script:FP += $t.Length
    return (GciPlain $t)
}

# ================================================================ rules:if expressions
function GciEvalIf($expr, $vars) {
    if ($null -eq $vars) { $vars = GciOMap }
    $script:ES = if ($null -ne $expr) { [string]$expr } else { '' }
    $script:EP = 0
    $script:EV = $vars
    $v = GciEOr
    GciEWs
    if ($script:EP -lt $script:ES.Length) { GciEFail }
    return $v
}
function GciEFail {
    $at = $script:ES.Substring($script:EP)
    if ($at -ceq '') { $at = 'the end' }
    GciDie ("rules:if: cannot read '" + $script:ES + "' at '" + $at + "'")
}
function GciEWs { while ($script:EP -lt $script:ES.Length -and [string]$script:ES[$script:EP] -cmatch '\s') { $script:EP++ } }
function GciETake([string]$re) {
    GciEWs
    $r = $script:ES.Substring($script:EP)
    if ($r -cmatch ('^(' + $re + ')')) { $script:EP += $Matches[1].Length; return $Matches[1] }
    return $null
}
function GciEVar([string]$n) { if ($script:EV.ContainsKey($n)) { return $script:EV[$n] }; return $null }
function GciRegex([string]$pat, [string]$flv, [string]$expr) {
    $f = ''
    foreach ($ch in $flv.ToCharArray()) { if ('imsx'.Contains([string]$ch)) { $f += [string]$ch } }
    $p = if ($f -ne '') { '(?' + $f + ')' + $pat } else { $pat }
    try { $null = [regex]::Match('', $p) } catch { GciDie ('rules:if: bad regular expression /' + $pat + '/ in ''' + $expr + '''') }
    return $p
}
function GciERegex {
    GciEWs
    $r = $script:ES.Substring($script:EP)
    if ($r -cnotmatch '^/((?:[^/\\]|\\.)*)/([a-z]*)') { return $null }
    $pat = $Matches[1]; $flv = $Matches[2]
    $script:EP += $pat.Length + 2 + $flv.Length
    return (GciRegex $pat $flv $script:ES)
}
function GciEOperand {
    $t = GciETake '\$\{?[A-Za-z_][A-Za-z0-9_]*\}?'
    if ($null -ne $t) { $n = $t -creplace '^\$\{?|\}$', ''; return , @('var', (GciEVar $n)) }
    $t = GciETake '"(?:[^"\\]|\\.)*"'
    if ($null -ne $t) { return , @('str', (GciUnescape $t.Substring(1, $t.Length - 2))) }
    $t = GciETake "'(?:[^'\\]|\\.)*'"
    if ($null -ne $t) { return , @('str', $t.Substring(1, $t.Length - 2).Replace("\'", "'")) }
    $t = GciETake 'null\b'
    if ($null -ne $t) { return , @('null', $null) }
    $re = GciERegex
    if ($null -ne $re) { return , @('re', $re) }
    GciEFail
}
function GciEPrimary {
    if ($null -ne (GciETake '\(')) {
        $v = GciEOr
        if ($null -eq (GciETake '\)')) { GciEFail }
        return $v
    }
    $lv = GciEOperand
    $op = GciETake '==|!=|=~|!~'
    if ($null -ne $op) {
        if ($op -ceq '=~' -or $op -ceq '!~') {
            $re = GciERegex
            if ($null -eq $re) {
                $o = GciEOperand
                $v = $o[1]
                if ($null -eq $v) { $re = $null }
                elseif ($v -cmatch '(?s)^/(.*)/([a-z]*)$') { $re = GciRegex $Matches[1] $Matches[2] $script:ES }
                else { $re = GciRegex ([regex]::Escape([string]$v)) '' $script:ES }
            }
            $m = 0
            if ($null -ne $lv[1] -and $null -ne $re -and ([string]$lv[1] -cmatch $re)) { $m = 1 }
            if ($op -ceq '=~') { return $m }
            if ($m) { return 0 } else { return 1 }
        }
        $rv = GciEOperand
        $a = $lv[1]; $b = $rv[1]
        $eq = 0
        if ($null -eq $a -and $null -eq $b) { $eq = 1 } elseif ($null -ne $a -and $null -ne $b -and [string]$a -ceq [string]$b) { $eq = 1 }
        if ($op -ceq '==') { return $eq }
        if ($eq) { return 0 } else { return 1 }
    }
    if ($lv[0] -ceq 'var' -or $lv[0] -ceq 'str') { if ($null -ne $lv[1] -and [string]$lv[1] -cne '') { return 1 }; return 0 }
    return 0
}
function GciEUnary { if ($null -eq (GciETake '!(?![=~])')) { return (GciEPrimary) }; if (GciEUnary) { return 0 }; return 1 }
function GciEAnd {
    $v = GciEUnary
    while ($null -ne (GciETake '&&')) { $r = GciEUnary; if ($v -and $r) { $v = 1 } else { $v = 0 } }
    return $v
}
function GciEOr {
    $v = GciEAnd
    while ($null -ne (GciETake '\|\|')) { $r = GciEAnd; if ($v -or $r) { $v = 1 } else { $v = 0 } }
    return $v
}

# ================================================================ globs
function GciGlobRe([string]$g) {
    $g = $g -creplace '^\./', ''
    if ($g -cmatch '/$') { $g += '**' }
    $re = ''
    $k = 0
    while ($k -lt $g.Length) {
        $r = $g.Substring($k)
        if ($r -cmatch '^\*\*/?') { $t = $Matches[0]; if ($t -cmatch '/$') { $re += '(?:.*/)?' } else { $re += '.*' }; $k += $t.Length; continue }
        $c = [string]$g[$k]
        if ($c -ceq '*') { $re += '[^/]*'; $k++; continue }
        if ($c -ceq '?') { $re += '[^/]'; $k++; continue }
        if ($r -cmatch '^\{([^}]*)\}') {
            $alts = @(); foreach ($x in $Matches[1].Split(',')) { $alts += [regex]::Escape($x) }
            $re += '(?:' + ($alts -join '|') + ')'; $k += $Matches[0].Length; continue
        }
        if ($r -cmatch '^\[[^\]]*\]') { $re += $Matches[0]; $k += $Matches[0].Length; continue }
        $re += [regex]::Escape($c); $k++
    }
    return ('^' + $re + '$')
}
function GciExpand($s, $vars) {
    if ($null -eq $s) { return $null }
    $s = [string]$s
    $ms = [regex]::Matches($s, '\$\{([A-Za-z_][A-Za-z0-9_]*)\}|\$([A-Za-z_][A-Za-z0-9_]*)')
    if ($ms.Count -eq 0) { return $s }
    $o = ''; $at = 0
    foreach ($m in $ms) {
        $o += $s.Substring($at, $m.Index - $at)
        $n = if ($m.Groups[1].Success) { $m.Groups[1].Value } else { $m.Groups[2].Value }
        if ($vars.ContainsKey($n) -and $null -ne $vars[$n]) { $o += [string]$vars[$n] }
        $at = $m.Index + $m.Length
    }
    return $o + $s.Substring($at)
}
function GciFiles([string]$dir) {           # every file under $dir, relative, / separated (no .git), sorted
    if (-not $dir -or -not (Test-Path -LiteralPath $dir -PathType Container)) { return , @() }
    $base = (Get-Item -LiteralPath $dir).FullName.TrimEnd('\')
    $out = @()
    foreach ($f in (Get-ChildItem -LiteralPath $base -Recurse -Force -File -ErrorAction SilentlyContinue)) {
        $r = $f.FullName.Substring($base.Length + 1).Replace('\', '/')
        if ($r -cmatch '(?:^|/)\.git(?:/|$)') { continue }
        $out += $r
    }
    return , (GciSortOrd $out)
}
function GciGlobsHit($globs, $paths, $vars) {
    $res = @()
    foreach ($g in $globs) { if ($null -ne $g) { $res += (GciGlobRe (GciExpand $g $vars)) } }
    foreach ($f in $paths) {
        $cand = @($f); $d = $f
        while ($d -cmatch '/[^/]*$') { $d = $d -creplace '/[^/]*$', ''; $cand += $d }
        foreach ($c in $cand) { foreach ($re in $res) { if ($c -cmatch $re) { return $true } } }
    }
    return $false
}

# ================================================================ the pipeline definition
$script:GLOBALKEYS = @('image', 'services', 'stages', 'types', 'variables', 'default', 'workflow', 'include', 'before_script', 'after_script', 'cache', 'spec')
$script:WHENS = @('on_success', 'on_failure', 'always', 'manual', 'delayed', 'never')

function GciSlurp([string]$f) {
    if (-not (Test-Path -LiteralPath $f -PathType Leaf)) { return '' }
    $b = Get-Content -LiteralPath $f -Encoding Byte -ReadCount 0
    if ($null -eq $b) { return '' }
    return (GciUtf8Dec ([byte[]]$b))
}
function GciUtf8Dec([byte[]]$b) {
    $sb = ''
    $chunk = @()
    $i = 0; $n = $b.Length
    $o = [char[]]::new($n)
    $k = 0
    while ($i -lt $n) {
        $c = [int]$b[$i]
        if ($c -lt 0x80) { $o[$k++] = [char]$c; $i++; continue }
        $cp = -1; $len = 0
        if ($c -ge 0xC2 -and $c -le 0xDF) { $len = 2; $cp = $c -band 0x1F }
        elseif ($c -ge 0xE0 -and $c -le 0xEF) { $len = 3; $cp = $c -band 0x0F }
        elseif ($c -ge 0xF0 -and $c -le 0xF4) { $len = 4; $cp = $c -band 0x07 }
        $ok = $len -gt 0 -and $i + $len -le $n
        if ($ok) { for ($j = 1; $j -lt $len; $j++) { $x = [int]$b[$i + $j]; if (($x -band 0xC0) -ne 0x80) { $ok = $false; break }; $cp = ($cp -shl 6) -bor ($x -band 0x3F) } }
        if (-not $ok) { $o[$k++] = [char]$c; $i++; continue }
        if ($cp -ge 0x10000) { $cp -= 0x10000; $o[$k++] = [char](0xD800 + ($cp -shr 10)); $o[$k++] = [char](0xDC00 + ($cp -band 0x3FF)) }
        else { $o[$k++] = [char]$cp }
        $i += $len
    }
    return (-join $o[0..($k - 1)])
}

function GciLoad([string]$path, [string]$file, [string]$root, $vars, $changed) {
    $text = GciSlurp $path
    if (-not $file) { $file = $path }
    if (-not $root) { $root = Split-Path -Parent (Get-Item -LiteralPath $path).FullName }
    if ($null -eq $vars) { $vars = GciOMap }
    return (GciBuild @{ text = $text; file = $file; root = $root } $vars $changed)
}

function GciKeyLines([string]$text) {
    $line = GciOMap; $n = 0
    foreach ($l in ($text -split "\r?\n")) {
        $n++
        if ($l -cmatch '^([^\s#''"\-][^:]*?)\s*:(?:\s|$)') { if (-not $line.ContainsKey($Matches[1])) { $line[$Matches[1]] = $n } }
        if ($l -cmatch '^["'']([^"'']+)["'']\s*:(?:\s|$)') { if (-not $line.ContainsKey($Matches[1])) { $line[$Matches[1]] = $n } }
    }
    return $line
}

function GciListOf($v) { if ($null -eq $v) { return , @() }; if (GciIsList $v) { return , $v }; return , @(, $v) }
function GciTrue($v) { return ($null -ne $v -and -not ($v -is [hashtable]) -and -not (GciIsList $v) -and [string]$v -match '^(?:true|yes|on|1)$') }
function GciHasMap($v) {
    if (GciIsMap $v) { $ks = GciSortOrd (GciKeys $v); if ($ks.Count) { return ($ks[0] + ': ...') }; return '{}' }
    if (GciIsList $v) { foreach ($x in $v) { $r = GciHasMap $x; if ($r) { return $r } } }
    return $null
}
function GciFlat($v) {
    $o = @()
    if ($null -eq $v) { return , $o }
    if (GciIsList $v) { foreach ($x in $v) { foreach ($y in (GciFlat $x)) { $o += $y } }; return , $o }
    if ($v -is [hashtable]) { return , @('HASH') }
    return , @([string]$v)
}

function GciIncludeDesc($inc) {
    if (-not ($inc -is [hashtable])) { if ([string]$inc -cmatch '^https?://') { return 'remote: ' + $inc }; return 'local: ' + $inc }
    if (-not (GciIsMap $inc)) { return [string]$inc }
    $parts = @()
    foreach ($k in (GciSortOrd (GciKeys $inc))) {
        if ($k -ceq 'rules') { $parts += '(conditional: rules)'; continue }
        $v = $inc[$k]
        if ($v -is [hashtable] -or (GciIsList $v)) { $xs = @(); foreach ($x in (GciListOf $v)) { if (-not ($x -is [hashtable]) -and -not (GciIsList $x)) { $xs += [string]$x } }; $parts += ($k + ': ' + ($xs -join ' ')) }
        else { $parts += ($k + ': ' + [string]$v) }
    }
    return ($parts -join ', ')
}

function GciCompose($st, [string]$file, [string]$text, $stack) {
    $data = GciParseYaml $text $file
    $order = $script:ROOTORDER; if ($null -eq $order) { $order = @() }
    if ($null -eq $data) { $data = GciNewMap }
    if (-not (GciIsMap $data)) { GciDie ($file + ':1: the top level must be a map of keys') }
    $lines = GciKeyLines $text
    $from = $file + ':' + $(if ($lines.ContainsKey('include')) { $lines['include'] } else { 1 })
    $acc = GciNewMap; $accOrder = @(); $seen = GciOMap
    foreach ($inc in (GciListOf $data['include'])) {
        $local = $null
        if (-not ($inc -is [hashtable]) -and -not (GciIsList $inc)) { if ([string]$inc -cnotmatch '^https?://') { $local = [string]$inc } }
        elseif ((GciIsMap $inc) -and $inc.ContainsKey('local') -and -not $inc.ContainsKey('project')) { $local = $inc['local'] }
        elseif (-not (GciIsMap $inc)) { GciDie ($from + ': include: an item must be a path or a map (local:, template:, project:, remote:, component:)') }
        if ($null -eq $local) { $st.remote += , (GciIncludeDesc $inc); continue }
        if ($local -is [hashtable] -or (GciIsList $local) -or [string]$local -ceq '') { GciDie ($from + ': include: local: needs a path') }
        if ((GciIsMap $inc) -and $null -ne $inc['rules']) {
            $rr = $inc['rules']
            $bad = -not (GciIsList $rr); if (-not $bad) { foreach ($r in $rr) { if (-not (GciIsMap $r)) { $bad = $true } } }
            if ($bad) { GciDie ($from + ': include: rules must be a list of maps') }
            $st.conditional = 1
            $m = $null
            foreach ($r in $rr) { if (GciRuleMatch $r $st.vars @{ dir = $st.root; changed = $st.changed }) { $m = $r; break } }
            $when = if ($m) { if ($null -ne $m['when']) { [string]$m['when'] } else { 'always' } } else { 'never' }
            if (-not ($when -ceq 'always' -or $when -ceq 'never')) { GciDie ($from + ": include: rules: when must be always or never, got '" + $when + "'") }
            if ($when -ceq 'never') { continue }
        }
        $path = [string]$local
        if ($path.Contains('$')) { $path = GciExpand $path $st.vars }
        $path = $path -creplace '^/+', ''
        $path = $path -creplace '^\./', ''
        $files = @()
        if ($path -cmatch '[*?\[{]') {
            if ($null -eq $st.all_files) { $st.all_files = GciFiles $st.root }
            $re = GciGlobRe $path
            foreach ($f in $st.all_files) { if ($f -cmatch $re -and $f -cmatch '\.ya?ml$') { $files += $f } }
        } else {
            if ($path -cnotmatch '\.ya?ml$') { GciDie ($from + ": include: local file '" + $path + "' must end in .yml or .yaml") }
            if (-not (Test-Path -LiteralPath (Join-Path $st.root ($path.Replace('/', '\'))) -PathType Leaf)) { GciDie ($from + ": include: local file '" + $path + "' does not exist (paths start at the repository root)") }
            $files = @($path)
        }
        foreach ($f in $files) {
            $cyc = $false; foreach ($s in (@($stack) + @($file))) { if ($s -ceq $f) { $cyc = $true } }
            if ($cyc) { GciDie ($from + ': include: cycle ' + ((@($stack) + @($file) + @($f)) -join ' -> ')) }
            if ($seen.ContainsKey($f)) { continue }; $seen[$f] = 1
            $st.nfiles++
            if ($st.nfiles -gt 100) { GciDie ($from + ': include: more than 100 included files') }
            $st.included += , $f
            $res = GciCompose $st $f (GciSlurp (Join-Path $st.root ($f.Replace('/', '\')))) (@($stack) + @($file))
            $acc = GciDeepMerge $acc $res[0]
            foreach ($k in $res[1]) { if (-not ($accOrder -ccontains $k)) { $accOrder += $k } }
        }
    }
    $own = GciClone $data
    GciDel $own 'include'
    foreach ($k in $order) {
        if ($k -ceq 'include') { continue }
        if (-not $st.origin.ContainsKey($k)) { $st.origin[$k] = @() }
        $ln = if ($lines.ContainsKey($k)) { $lines[$k] } else { 1 }
        $st.origin[$k] = [object[]]$st.origin[$k] + , @($file, $ln)
    }
    $acc = GciDeepMerge $acc $own
    foreach ($k in $order) { if ($k -cne 'include' -and -not ($accOrder -ccontains $k)) { $accOrder += $k } }
    return , @($acc, $accOrder)
}

function GciAt($ci, [string]$name) {
    if ($ci.origin.ContainsKey($name) -and $ci.origin[$name].Count) { $o = $ci.origin[$name][0]; return ($o[0] + ':' + $o[1]) }
    return ($ci.file + ':1')
}
function GciFrom($ci, [string]$name) {
    if (-not $ci.origin.ContainsKey($name)) { return '' }
    $s = @(); foreach ($o in $ci.origin[$name]) { if (-not ($s -ccontains $o[0])) { $s += $o[0] } }
    return ($s -join ' + ')
}

function GciBuild($top, $vars, $changed) {
    $st = @{ root = $top.root; vars = $vars; changed = $changed; remote = @(); included = @(); origin = (GciOMap); nfiles = 0; conditional = 0; all_files = $null }
    $res = GciCompose $st $top.file $top.text @()
    $data = $res[0]; $order = $res[1]
    $file = $top.file
    $ci = @{ file = $file; text = $top.text; data = $data; origin = $st.origin; jobs = (GciOMap); order = @(); includes = $st.remote; included = $st.included; conditional = $st.conditional; src = $top }
    GciResolveRefs $ci $data 0
    $stv = $data['stages']; if ($null -eq $stv) { $stv = $data['types'] }
    if ($null -ne $stv -and -not (GciIsList $stv)) { GciDie ((GciAt $ci 'stages') + ': stages must be a list') }
    if ($null -eq $stv) { $stv = @('build', 'test', 'deploy') }
    $stages = @('.pre'); foreach ($s in $stv) { if ($null -ne $s -and [string]$s -cne '.pre' -and [string]$s -cne '.post') { $stages += [string]$s } }; $stages += '.post'
    $ci.stages = $stages
    $ci.variables = GciVars $data['variables'] $ci 'variables'
    $wf = $null
    if (GciIsMap $data['workflow']) { $wf = $data['workflow']['rules'] }
    if ($null -ne $wf) {
        $bad = -not (GciIsList $wf); if (-not $bad) { foreach ($r in $wf) { if (-not (GciIsMap $r)) { $bad = $true } } }
        if ($bad) { GciDie ((GciAt $ci 'workflow') + ': workflow:rules must be a list of maps') }
    }
    $ci.workflow = $wf
    $ci.default = if (GciIsMap $data['default']) { $data['default'] } else { GciNewMap }
    foreach ($name in $order) {
        if ($script:GLOBALKEYS -ccontains $name -or $name.StartsWith('.')) { continue }
        $j = $data[$name]
        if (-not (GciIsMap $j)) { GciDie ((GciAt $ci $name) + ": job '" + $name + "' must be a map of keys") }
        $full = GciExtends $ci $name (GciOMap) 0
        $ci.jobs[$name] = GciJob $ci $name $full
        $ci.jobs[$name].file = GciFrom $ci $name
        $ci.order += $name
    }
    return $ci
}

function GciResolveRefs($ci, $node, [int]$depth) {
    if ($depth -gt 20) { GciDie ($ci.file + ': !reference nested too deeply (a cycle?)') }
    if (GciIsMap $node) {
        foreach ($k in (GciKeys $node)) {
            $node[$k] = GciFixRef $ci $node[$k] $depth
            if ($node[$k] -is [hashtable] -or (GciIsList $node[$k])) { GciResolveRefs $ci $node[$k] $depth }
        }
    } elseif (GciIsList $node) {
        for ($i = 0; $i -lt $node.Count; $i++) {
            $node[$i] = GciFixRef $ci $node[$i] $depth
            if ($node[$i] -is [hashtable] -or (GciIsList $node[$i])) { GciResolveRefs $ci $node[$i] $depth }
        }
    }
}
function GciFixRef($ci, $v, [int]$depth) {
    if (-not (GciIsRef $v)) { return , $v }
    $cur = $ci.data
    foreach ($k in $v.path) {
        if (-not ((GciIsMap $cur) -and $cur.ContainsKey([string]$k))) {
            $f = if ($v.file) { $v.file } else { $ci.file }
            GciDie ($f + ':' + $v.line + ': !reference [' + (@($v.path) -join ', ') + '] not found')
        }
        $cur = $cur[[string]$k]
    }
    $c = GciClone $cur
    if ($c -is [hashtable] -or (GciIsList $c)) { GciResolveRefs $ci $c ($depth + 1) }
    return , $c
}

function GciVars($v, $ci, [string]$where) {
    $o = GciOMap
    if ($null -eq $v) { return $o }
    if (-not (GciIsMap $v)) { GciDie ((GciAt $ci $where) + ': ' + $where + ' must be a map') }
    foreach ($k in (GciKeys $v)) {
        $x = $v[$k]
        if (GciIsMap $x) { $x = $x['value'] }
        $o[$k] = if ($null -ne $x -and -not ($x -is [hashtable]) -and -not (GciIsList $x)) { [string]$x } else { '' }
    }
    return $o
}

function GciDeepMerge($a, $b) {
    $r = GciClone $a
    foreach ($k in (GciKeys $b)) {
        if ((GciIsMap $r[$k]) -and (GciIsMap $b[$k])) { GciSet $r $k (GciDeepMerge $r[$k] $b[$k]) }
        else { GciSet $r $k (GciClone $b[$k]) }
    }
    return $r
}

function GciExtends($ci, [string]$name, $seen, [int]$depth) {
    $j = $ci.data[$name]
    if (-not (GciIsMap $j)) { GciDie ((GciAt $ci $name) + ": extends: '" + $name + "' is not defined") }
    if ($seen.ContainsKey($name)) { GciDie ((GciAt $ci $name) + ": extends: circular chain through '" + $name + "'") }
    if ($depth -gt 11) { GciDie ((GciAt $ci $name) + ": extends: more than 11 levels at '" + $name + "'") }
    $parents = GciListOf $j['extends']
    if ($parents.Count -eq 0) { return (GciClone $j) }
    $acc = GciNewMap
    foreach ($par in $parents) {
        $par = [string]$par
        if (-not (GciIsMap $ci.data[$par])) { GciDie ((GciAt $ci $name) + ": job '" + $name + "' extends '" + $par + "', which is not defined") }
        $s2 = GciOMap; foreach ($k in $seen.Keys) { $s2[$k] = 1 }; $s2[$name] = 1
        $acc = GciDeepMerge $acc (GciExtends $ci $par $s2 ($depth + 1))
    }
    $own = GciClone $j
    GciDel $own 'extends'
    $r = GciDeepMerge $acc $own
    GciDel $r 'extends'
    return $r
}

function GciInherits($j, [string]$key) {
    $inh = $null
    if (GciIsMap $j['inherit']) { $inh = $j['inherit']['default'] }
    if ($null -eq $inh) { return $true }
    if (GciIsList $inh) { foreach ($x in $inh) { if ([string]$x -ceq $key) { return $true } }; return $false }
    return (GciTrue $inh)
}

function GciJob($ci, [string]$name, $j) {
    $at = GciAt $ci $name
    $n = @{ name = $name }
    $stage = if ($null -ne $j['stage']) { [string]$j['stage'] } else { 'test' }
    if (-not ($ci.stages -ccontains $stage)) { GciDie ($at + ": job '" + $name + "': stage '" + $stage + "' is not in stages (" + ($ci.stages -join ', ') + ')') }
    $n.stage = $stage
    $n.trigger = $j.ContainsKey('trigger')
    foreach ($k in @('script', 'before_script', 'after_script')) {
        $bad = GciHasMap $j[$k]
        if ($bad) { GciDie ($at + ": job '" + $name + "': a " + $k + " line is a map (" + $bad + ") -- quote a command that contains ': '") }
    }
    $n.script = GciFlat $j['script']
    if ($n.script.Count -eq 0 -and -not $n.trigger) { GciDie ($at + ": job '" + $name + "' has no script (or trigger)") }
    foreach ($k in @('before_script', 'after_script')) {
        $v = $null
        if ($j.ContainsKey($k)) { $v = $j[$k] }
        elseif (GciInherits $j $k) { $v = $ci.default[$k]; if ($null -eq $v) { $v = $ci.data[$k] } }
        $n[$(if ($k -ceq 'before_script') { 'before' } else { 'after' })] = GciFlat $v
    }
    $n.variables = GciVars $j['variables'] $ci $name
    $iv = $null; if (GciIsMap $j['inherit']) { $iv = $j['inherit']['variables'] }
    $n.global_vars = if ($null -eq $iv) { $true } elseif (GciIsList $iv) { , $iv } else { GciTrue $iv }
    if ($null -ne $j['rules']) {
        $rr = $j['rules']
        $bad = -not (GciIsList $rr); if (-not $bad) { foreach ($r in $rr) { if (-not (GciIsMap $r)) { $bad = $true } } }
        if ($bad) { GciDie ($at + ": job '" + $name + "': rules must be a list of maps") }
        if ($null -ne $j['only'] -or $null -ne $j['except']) { GciDie ($at + ": job '" + $name + "': rules cannot be used with only/except") }
        $n.rules = $rr
        foreach ($r in $rr) { if ($null -ne $r['when'] -and -not ($script:WHENS -ccontains [string]$r['when'])) { GciDie ($at + ": job '" + $name + "': unknown when '" + $r['when'] + "' in rules") } }
    }
    $n.only = $j['only']
    $n.except = $j['except']
    $when = if ($null -ne $j['when']) { [string]$j['when'] } else { 'on_success' }
    if (-not ($script:WHENS -ccontains $when)) { GciDie ($at + ": job '" + $name + "': unknown when '" + $when + "'") }
    $n.when = $when
    $n.allow_failure = $j['allow_failure']
    $art = $j['artifacts']
    $n.artifacts = if (GciIsMap $art) { GciFlat $art['paths'] } else { @() }
    $n.artifacts_when = if ((GciIsMap $art) -and $null -ne $art['when']) { [string]$art['when'] } else { 'on_success' }
    $needs = @(); foreach ($x in (GciListOf $j['needs'])) { if (GciIsMap $x) { $needs += $x['job'] } else { $needs += $x } }
    $n.needs = $needs
    $n.tags = GciFlat $j['tags']                 # this port only: a PowerShell job says so with tags: [powershell]
    return $n
}

# ================================================================ which jobs a pipeline gets
$script:REFWORD = @{ merge_requests = 'merge_request_event'; schedules = 'schedule'; pushes = 'push'; web = 'web'; api = 'api'
    triggers = 'trigger'; pipelines = 'pipeline'; chat = 'chat'; external = 'external'; external_pull_requests = 'external_pull_request_event' }

function GciRuleMatch($r, $vars, $o) {
    if ($r.ContainsKey('if') -and -not (GciEvalIf $r['if'] $vars)) { return $false }
    if ($r.ContainsKey('changes') -and $null -ne $o.changed) {
        $c = $r['changes']
        $g = if (GciIsMap $c) { GciListOf $c['paths'] } else { GciListOf $c }
        if (-not (GciGlobsHit $g $o.changed $vars)) { return $false }
    }
    if ($r.ContainsKey('exists')) {
        $e = $r['exists']
        $g = if (GciIsMap $e) { GciListOf $e['paths'] } else { GciListOf $e }
        if ($null -eq $o._files) { $o._files = GciFiles $o.dir }
        if (-not (GciGlobsHit $g $o._files $vars)) { return $false }
    }
    return $true
}

function GciVarOr($vars, [string]$k) { if ($vars.ContainsKey($k)) { return $vars[$k] }; return $null }

function GciOnlyMatch($spec, $vars, $o) {
    if (-not (GciIsMap $spec)) { $s2 = GciNewMap; GciSet $s2 'refs' $spec; $spec = $s2 }
    $src = GciVarOr $vars 'CI_PIPELINE_SOURCE'; if ($null -eq $src) { $src = 'push' }
    $mr = $src -ceq 'merge_request_event'
    $ref = GciVarOr $vars 'CI_COMMIT_REF_NAME'; if ($null -eq $ref) { $ref = GciVarOr $vars 'CI_COMMIT_TAG' }; if ($null -eq $ref) { $ref = GciVarOr $vars 'CI_COMMIT_BRANCH' }
    if ($null -ne $spec['refs']) {
        $hit = $false
        foreach ($w in (GciListOf $spec['refs'])) {
            if ($null -eq $w) { continue }
            $w = [string]$w
            if ($w -ceq 'branches') { if (-not $mr -and $null -ne (GciVarOr $vars 'CI_COMMIT_BRANCH') -and $null -eq (GciVarOr $vars 'CI_COMMIT_TAG')) { $hit = $true } }
            elseif ($w -ceq 'tags') { $t = GciVarOr $vars 'CI_COMMIT_TAG'; if ($null -ne $t -and [string]$t -cne '') { $hit = $true } }
            elseif ($script:REFWORD.ContainsKey($w) -and ($script:REFWORD.Keys -ccontains $w)) { if ($src -ceq $script:REFWORD[$w]) { $hit = $true } }
            elseif ($w -cmatch '(?s)^/(.*)/([a-z]*)$') { $re = GciRegex $Matches[1] $Matches[2] $w; if (-not $mr -and $null -ne $ref -and [string]$ref -cmatch $re) { $hit = $true } }
            else { if (-not $mr -and $null -ne $ref -and [string]$ref -ceq $w) { $hit = $true } }
            if ($hit) { break }
        }
        if (-not $hit) { return $false }
    }
    if ($null -ne $spec['variables']) {
        $any = $false; foreach ($e in (GciListOf $spec['variables'])) { if (GciEvalIf $e $vars) { $any = $true; break } }
        if (-not $any) { return $false }
    }
    if ($null -ne $spec['changes'] -and $null -ne $o.changed) {
        $c = $spec['changes']
        $g = if (GciIsMap $c) { GciListOf $c['paths'] } else { GciListOf $c }
        if (-not (GciGlobsHit $g $o.changed $vars)) { return $false }
    }
    return $true
}

function GciMergeInto($dst, $src) { if ($null -ne $src) { foreach ($k in $src.Keys) { $dst[$k] = $src[$k] } } }

function GciPlan($ci, $o) {
    $ovars = if ($null -ne $o.vars) { $o.vars } else { GciOMap }
    if ($ci.conditional -and $ci.src) { $cv = GciOMap; GciMergeInto $cv $ovars; $ci = GciBuild $ci.src $cv $o.changed }
    $v = GciOMap; GciMergeInto $v $ci.variables; GciMergeInto $v $ovars
    $jobs = @(); $skipped = @()
    foreach ($d in $ci.includes) { $skipped += , @{ name = 'include: ' + $d; reason = 'include: runs on GitLab only'; file = $null } }
    $res = @{ jobs = $null; skipped = $null; stages = $ci.stages; workflow = $null }
    if ($ci.workflow) {
        $m = $null
        foreach ($r in $ci.workflow) { if (GciRuleMatch $r $v $o) { $m = $r; break } }
        $why = $null
        if (-not $m) { $why = 'workflow:rules: no rule matched' } elseif ([string]$m['when'] -ceq 'never') { $why = 'workflow:rules: when never' }
        if ($why) {
            foreach ($nm in $ci.order) { $skipped += , @{ name = $nm; reason = $why; file = $null } }
            $res.jobs = @(); $res.skipped = $skipped; $res.workflow = 'blocked'; return $res
        }
        GciMergeInto $v (GciVars $m['variables'] $ci 'workflow')
        GciMergeInto $v $ovars
    }
    $sel = @(); if ($o.only_jobs) { $sel = @($o.only_jobs) }
    $k = 0
    foreach ($name in $ci.order) {
        $j = $ci.jobs[$name]
        $k++
        $skip = $null
        if ($sel.Count -and -not ($sel -ccontains $name)) { $skipped += , @{ name = $name; reason = 'not selected (--job)'; file = $j.file }; continue }
        if ($j.trigger) { $skipped += , @{ name = $name; reason = 'trigger: runs on GitLab only'; file = $j.file }; continue }
        $jv = GciOMap; GciMergeInto $jv $v; GciMergeInto $jv $j.variables; GciMergeInto $jv $ovars
        $when = $null; $af = $null; $rv = GciOMap; $reason = $null; $afset = $false
        if ($j.rules) {
            # the Perl kit evaluates every rule (grep) and reports the rule COUNT as "rule N": kept for parity
            $m = $null
            foreach ($r in $j.rules) { if ((GciRuleMatch $r $jv $o) -and $null -eq $m) { $m = $r } }
            $i = @($j.rules).Count
            if (-not $m) { $skipped += , @{ name = $name; reason = 'rules: no rule matched'; file = $j.file }; continue }
            $when = if ($null -ne $m['when']) { [string]$m['when'] } else { 'on_success' }
            if ($when -ceq 'never') { $skipped += , @{ name = $name; reason = "rules: rule $i says when: never"; file = $j.file }; continue }
            if ($m.ContainsKey('allow_failure')) { $af = $m['allow_failure'] } else { $af = $j.allow_failure }
            $afset = $true
            $rv = GciVars $m['variables'] $ci $name
            $reason = "rules: rule $i matched"
        } elseif ($null -ne $j.only -or $null -ne $j.except) {
            if ($null -ne $j.only -and -not (GciOnlyMatch $j.only $jv $o)) { $skipped += , @{ name = $name; reason = 'only: not this pipeline'; file = $j.file }; continue }
            if ($null -ne $j.except -and (GciOnlyMatch $j.except $jv $o)) { $skipped += , @{ name = $name; reason = 'except: this pipeline is excluded'; file = $j.file }; continue }
            $when = $j.when
            $reason = 'only/except'
        } else {
            $ps = GciVarOr $jv 'CI_PIPELINE_SOURCE'; if ($null -eq $ps) { $ps = '' }
            if ($ps -cmatch '^(?:merge_request_event|external_pull_request_event)$') { $skipped += , @{ name = $name; reason = 'no rules or only/except: not added to merge request pipelines'; file = $j.file }; continue }
            $when = $j.when
            $reason = 'no rules: branch and tag pipelines'
        }
        if ($when -ceq 'never') { $skipped += , @{ name = $name; reason = 'when: never'; file = $j.file }; continue }
        if (-not $afset -or $null -eq $af) { if ($null -ne $j.allow_failure) { $af = $j.allow_failure } elseif ($when -ceq 'manual' -and -not $j.rules) { $af = 'true' } }
        $jvars = GciOMap; GciMergeInto $jvars $j.variables; GciMergeInto $jvars $rv
        $wh = if ($when -ceq 'delayed') { 'on_success' } else { $when }
        $jobs += , @{ name = $name; stage = $j.stage; when = $wh; allow_failure = $af; script = $j.script; before = $j.before; after = $j.after
            variables = $jvars; global_vars = $j.global_vars; artifacts = $j.artifacts; artifacts_when = $j.artifacts_when; needs = $j.needs
            reason = $reason; file = $j.file; tags = $j.tags; k = $k; si = [array]::IndexOf([object[]]$ci.stages, $j.stage) }
    }
    # stable sort by stage index, then file order
    $sorted = @()
    for ($s = 0; $s -lt $ci.stages.Count; $s++) { foreach ($x in $jobs) { if ($x.si -eq $s) { $sorted += , $x } } }
    $res.jobs = $sorted; $res.skipped = $skipped
    return $res
}

# ================================================================ running a pipeline (PowerShell jobs only)
function GciSafe([string]$n) { return ($n -creplace '[^A-Za-z0-9._-]+', '_') }
function GciAllowed($af, [int]$exit) {
    if (GciIsMap $af) { foreach ($c in (GciListOf $af['exit_codes'])) { if ([int]$c -eq $exit) { return $true } }; return $false }
    return (GciTrue $af)
}
function GciIsPsJob($j) {
    foreach ($t in $j.tags) { if ($t -match '^(?:powershell|pwsh)$') { return $true } }
    if ($j.variables.ContainsKey('KIT_SHELL') -and $j.variables['KIT_SHELL'] -match '^(?:powershell|pwsh)$') { return $true }
    return $false
}
function GciWriteUtf8([string]$path, [string]$text) {
    $b = @()
    $bytes = [byte[]]::new(0)
    $list = [byte[]]::new($text.Length * 3 + 1); $n = 0
    for ($i = 0; $i -lt $text.Length; $i++) {
        $c = [int]$text[$i]
        if ($c -ge 0xD800 -and $c -le 0xDBFF -and $i + 1 -lt $text.Length) { $c = 0x10000 + (($c - 0xD800) -shl 10) + ([int]$text[$i + 1] - 0xDC00); $i++ }
        if ($c -lt 0x80) { $list[$n++] = $c }
        elseif ($c -lt 0x800) { $list[$n++] = 0xC0 -bor ($c -shr 6); $list[$n++] = 0x80 -bor ($c -band 0x3F) }
        elseif ($c -lt 0x10000) { $list[$n++] = 0xE0 -bor ($c -shr 12); $list[$n++] = 0x80 -bor (($c -shr 6) -band 0x3F); $list[$n++] = 0x80 -bor ($c -band 0x3F) }
        else { if ($n + 4 -gt $list.Length) { }; $list[$n++] = 0xF0 -bor ($c -shr 18); $list[$n++] = 0x80 -bor (($c -shr 12) -band 0x3F); $list[$n++] = 0x80 -bor (($c -shr 6) -band 0x3F); $list[$n++] = 0x80 -bor ($c -band 0x3F) }
    }
    $out = [byte[]]::new($n); if ($n) { [Array]::Copy($list, $out, $n) }
    Set-Content -LiteralPath $path -Encoding Byte -Value $out -ErrorAction Stop
}
function GciPsScript($cmds, [bool]$after) {
    $t = "`$ErrorActionPreference = 'Stop'`n"
    foreach ($c in $cmds) {
        $first = ($c -split "`n")[0]
        $note = if ($c -cmatch "`n.") { ' # collapsed multi-line command' } else { '' }
        $t += "Write-Output '" + ('$ ' + $first + $note).Replace("'", "''") + "'`n"
        $t += "`$global:LASTEXITCODE = 0`n" + $c + "`n"
        if (-not $after) { $t += "if (`$LASTEXITCODE) { exit `$LASTEXITCODE }`n" }
    }
    return $t
}
function GciRunPs([string]$file, [string]$dir, $env, [string]$log, [bool]$append) {
    $saved = @{}
    foreach ($k in $env.Keys) { $e = Get-Item -LiteralPath ('env:' + $k) -ErrorAction SilentlyContinue; $saved[$k] = if ($e) { $e.Value } else { $null } }
    foreach ($k in $env.Keys) { Set-Item -LiteralPath ('env:' + $k) -Value ([string]$env[$k]) }
    $here = (Get-Location).Path
    $rc = 0
    try {
        Set-Location -LiteralPath $dir
        $out = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $file 2>&1 | ForEach-Object { [string]$_ }
        $rc = $LASTEXITCODE
        if ($null -eq $rc) { $rc = 0 }
    } catch { $out = @([string]$_); $rc = 1 }
    finally {
        Set-Location -LiteralPath $here
        foreach ($k in $env.Keys) { if ($null -eq $saved[$k]) { Remove-Item -LiteralPath ('env:' + $k) -ErrorAction SilentlyContinue } else { Set-Item -LiteralPath ('env:' + $k) -Value $saved[$k] } }
    }
    $text = ''; foreach ($l in @($out)) { $text += $l + "`n" }
    if ($append -and (Test-Path -LiteralPath $log)) { $text = (GciSlurp $log) + $text }
    GciWriteUtf8 $log $text
    return $rc
}

function GciCopyArtifacts([string]$dir, $paths, [string]$dest, $vars) {
    $n = 0
    foreach ($f in (GciFiles $dir)) {
        if (-not (GciGlobsHit $paths @($f) $vars)) { continue }
        $to = Join-Path $dest $f.Replace('/', '\')
        $pd = Split-Path -Parent $to
        if (-not (Test-Path -LiteralPath $pd)) { New-Item -ItemType Directory -Force -Path $pd | Out-Null }
        Copy-Item -LiteralPath (Join-Path $dir $f.Replace('/', '\')) -Destination $to -Force
        $n++
    }
    return $n
}

function GciRunJob($ci, $j, $o) {
    $dir = $o.dir
    $gv = $j.global_vars
    $g = GciOMap
    if (GciIsList $gv) { foreach ($x in $gv) { if ($ci.variables.ContainsKey([string]$x)) { $g[[string]$x] = $ci.variables[[string]$x] } } }
    elseif ($gv) { GciMergeInto $g $ci.variables }
    $yaml = GciOMap; GciMergeInto $yaml $g; GciMergeInto $yaml $j.variables
    $vars = GciOMap; GciMergeInto $vars $yaml; GciMergeInto $vars $o.vars
    foreach ($k in @($yaml.Keys)) { if (-not $o.vars.ContainsKey($k)) { $vars[$k] = GciExpand $vars[$k] $vars } }
    $env = GciOMap; GciMergeInto $env $vars
    $env['CI'] = 'true'; $env['GITLAB_CI'] = 'true'; $env['CI_JOB_NAME'] = $j.name; $env['CI_JOB_STAGE'] = $j.stage
    $env['CI_PROJECT_DIR'] = $dir; $env['CI_BUILDS_DIR'] = (Split-Path -Parent $dir)
    $log = Join-Path $o.log_dir ((GciSafe $j.name) + '.log')
    if (-not (GciIsPsJob $j)) {
        GciWriteUtf8 $log ("not run: this job's script is for sh (bash); this PC has none. Run it on a GitLab runner, or tag the job powershell.`n")
        return @{ name = $j.name; stage = $j.stage; status = 'not run'; duration = 0.0; log = $log; exit = $null; cached = $false; why = 'needs bash' }
    }
    $sf = Join-Path $o.log_dir ((GciSafe $j.name) + '.ps1')
    GciWriteUtf8 $sf (GciPsScript (@($j.before) + @($j.script)) $false)
    $t0 = Get-Date
    $exit = GciRunPs $sf $dir $env $log $false
    $status = if ($exit -eq 0) { 'success' } elseif (GciAllowed $j.allow_failure $exit) { 'allowed_failure' } else { 'failed' }
    if (@($j.after).Count) {
        $af = Join-Path $o.log_dir ((GciSafe $j.name) + '.after.ps1')
        GciWriteUtf8 $af (GciPsScript $j.after $true)
        $env2 = GciOMap; GciMergeInto $env2 $env; $env2['CI_JOB_STATUS'] = $(if ($status -ceq 'success') { 'success' } else { 'failed' })
        $null = GciRunPs $af $dir $env2 $log $true
    }
    $dur = ((Get-Date) - $t0).TotalSeconds
    if (@($j.artifacts).Count) {
        $w = $j.artifacts_when
        if ($w -ceq 'always' -or ($w -ceq 'on_success' -and $status -cne 'failed') -or ($w -ceq 'on_failure' -and $status -ceq 'failed')) {
            $null = GciCopyArtifacts $dir $j.artifacts (Join-Path (Join-Path $o.log_dir 'artifacts') (GciSafe $j.name)) $vars
        }
    }
    return @{ name = $j.name; stage = $j.stage; status = $status; duration = $dur; log = $log; exit = $exit; cached = $false }
}

function GciRun($ci, $o) {
    if (-not $o.dir) { $o.dir = (Get-Location).Path }
    if (-not $o.log_dir) {
        $base = $env:TEMP; if (-not $base) { $base = '.' }
        $o.log_dir = Join-Path $base ('gitlab-ci-' + (Get-Date -Format 'yyyyMMddHHmmss') + '-' + (Get-Random -Maximum 99999))
    }
    if (-not (Test-Path -LiteralPath $o.log_dir)) { New-Item -ItemType Directory -Force -Path $o.log_dir | Out-Null }
    $plan = GciPlan $ci $o
    $res = @{ status = 'skipped'; duration = 0.0; jobs = @(); skipped = $plan.skipped; log_dir = $o.log_dir }
    if (@($plan.jobs).Count -eq 0) { return $res }
    $failed = $false; $notrun = $false
    foreach ($stage in $plan.stages) {
        $stageFailed = $false
        foreach ($j in $plan.jobs) {
            if ($j.stage -cne $stage) { continue }
            $go = if ($j.when -ceq 'always') { $true } elseif ($j.when -ceq 'on_failure') { $failed } elseif ($j.when -ceq 'manual') { $o.manual -and -not $failed } else { -not $failed }
            if (-not $go) {
                $stv = if ($j.when -ceq 'manual' -and -not $o.manual) { 'manual' } else { 'skipped' }
                $res.jobs += , @{ name = $j.name; stage = $stage; status = $stv; duration = 0.0; log = $null; exit = $null; cached = $false }
                continue
            }
            $r = GciRunJob $ci $j $o
            $res.jobs += , $r
            $res.duration += $r.duration
            if ($r.status -ceq 'failed') { $stageFailed = $true }
            if ($r.status -ceq 'not run') { $notrun = $true }
        }
        if ($stageFailed) { $failed = $true }
    }
    $ok = $false; foreach ($x in $res.jobs) { if ($x.status -cmatch '^(?:success|allowed_failure)$') { $ok = $true } }
    $res.status = if ($failed) { 'failed' } elseif ($notrun) { 'incomplete' } elseif ($ok) { 'success' } else { 'skipped' }
    return $res
}

# ================================================================ the repository, read with pgit (no git here)
function GciFindTop([string]$start) {
    $d = (Get-Item -LiteralPath $start).FullName
    while ($d) {
        if (Test-Path -LiteralPath (Join-Path $d '.git')) { return $d }
        $p = Split-Path -Parent $d
        if (-not $p -or $p -eq $d) { break }
        $d = $p
    }
    return $null
}
function GciPgit { return [bool]$script:PGIT_LOADED }      # pgit.ps1 is dot-sourced at script scope below
function GciRev([string]$spec) { try { return (Resolve-PgitRef $script:REPOTOP $spec) } catch { return $null } }
function GciCommitMsg([string]$sha) { try { return (Get-PgitCommit $script:REPOTOP $sha).message } catch { return '' } }
function GciTreeMap([string]$sha) {
    $m = GciOMap
    if (-not $sha) { return $m }
    foreach ($e in (Get-PgitTreeFiles $script:REPOTOP $sha)) { $m[$e.path] = [string]$e.mode + ' ' + $e.sha }
    return $m
}
function GciDiffNames([string]$a, [string]$b) {
    $x = GciTreeMap $a; $y = GciTreeMap $b
    $names = @()
    foreach ($k in $x.Keys) { if (-not $y.ContainsKey($k) -or $y[$k] -cne $x[$k]) { $names += $k } }
    foreach ($k in $y.Keys) { if (-not $x.ContainsKey($k)) { $names += $k } }
    return , (GciSortOrd $names)
}
function GciAncestors([string]$sha) {
    $seen = GciOMap; $q = @($sha)
    while ($q.Count) {
        $c = $q[0]; if ($q.Count -gt 1) { $q = $q[1..($q.Count - 1)] } else { $q = @() }
        if (-not $c -or $seen.ContainsKey($c)) { continue }
        $seen[$c] = 1
        try { foreach ($p in (Get-PgitCommit $script:REPOTOP $c).parents) { $q += $p } } catch { }
    }
    return $seen
}
function GciMergeBase([string]$a, [string]$b) {
    $anc = GciAncestors $a
    $seen = GciOMap; $q = @($b)
    while ($q.Count) {
        $c = $q[0]; if ($q.Count -gt 1) { $q = $q[1..($q.Count - 1)] } else { $q = @() }
        if (-not $c -or $seen.ContainsKey($c)) { continue }
        $seen[$c] = 1
        if ($anc.ContainsKey($c)) { return $c }
        try { foreach ($p in (Get-PgitCommit $script:REPOTOP $c).parents) { $q += $p } } catch { }
    }
    return $null
}
function GciSubject([string]$msg) {
    $s = @()
    foreach ($l in ($msg -split "`n")) { if ($l -cmatch '^\s*$') { if ($s.Count) { break }; continue }; $s += $l.TrimEnd() }
    return ($s -join ' ')
}

# ================================================================ the CLI
$script:GCI_USAGE = @'
usage: gitlab-ci.cmd [--file .gitlab-ci.yml] [--event push|merge_request_event|tag|schedule|web|trigger]
                     [--branch B] [--target B] [--tag T] [--var K=V]... [--job NAME]... [--manual]
                     [--logs DIR] [--list]
Runs the pipeline of the current git repository locally, the way GitLab would select its jobs for that event.
  --event    pipeline source (default push); tag sets CI_COMMIT_TAG (from --tag or the tag on HEAD)
  --branch   the branch (default: the current one); --target the merge request target (default: CI_DEFAULT_BRANCH)
  --var      a CI/CD variable (repeat); --job run only these jobs; --manual also run manual jobs
  --list     show which jobs the pipeline would get, and why the others are left out, without running anything
On this PC (no git, no sh): the repository is read with pgit.ps1; only jobs tagged powershell (or with the job
variable KIT_SHELL: powershell) run; every other job is "not run (needs bash)", never passed. Exit: 0 success,
1 a job failed, 2 usage or configuration error, 3 incomplete (jobs not run).
'@

function GciOut([string]$t) { if ($t) { Write-Host -NoNewline $t } }
function GciErrOut([string]$t) { if ($t) { Write-Host -NoNewline $t } }

function GciCli($argv) {
    $o = @{ file = '.gitlab-ci.yml'; event = 'push' }
    $vars = @(); $jobsel = @()
    $names = @('file', 'event', 'branch', 'target', 'tag', 'var', 'job', 'manual', 'list', 'logs', 'help', 'h')
    $takes = @('file', 'event', 'branch', 'target', 'tag', 'var', 'job', 'logs')
    $rest = @()
    $bad = $false
    for ($i = 0; $i -lt $argv.Count; $i++) {
        $a = [string]$argv[$i]
        if ($a -ceq '--') { for ($k = $i + 1; $k -lt $argv.Count; $k++) { $rest += $argv[$k] }; break }
        if ($a -notmatch '^--?([A-Za-z][\w-]*)(?:=(.*))?$') { $rest += $a; continue }
        $nm = $Matches[1].ToLowerInvariant(); $val = $Matches[2]; $hasVal = $null -ne $Matches[2]
        $cands = @(); foreach ($x in $names) { if ($x -ceq $nm) { $cands = @($x); break }; if ($x.StartsWith($nm)) { $cands += $x } }
        if ($cands.Count -ne 1) {
            if ($cands.Count -eq 0) { GciErrOut ("gitlab-ci: Unknown option: " + $nm + "`n") } else { GciErrOut ("gitlab-ci: Option " + $nm + " is ambiguous (" + ($cands -join ', ') + ")`n") }
            $bad = $true; continue
        }
        $nm = $cands[0]
        if ($takes -ccontains $nm) {
            if (-not $hasVal) {
                if ($i + 1 -ge $argv.Count) { GciErrOut ("gitlab-ci: Option " + $nm + " requires an argument`n"); $bad = $true; continue }
                $i++; $val = [string]$argv[$i]
            }
            if ($nm -ceq 'var') { $vars += $val } elseif ($nm -ceq 'job') { $jobsel += $val } else { $o[$nm] = $val }
        } else { if ($nm -ceq 'h') { $nm = 'help' }; $o[$nm] = $true }
    }
    if ($o.help) { GciOut $script:GCI_USAGE; return 0 }
    if ($bad) { GciErrOut $script:GCI_USAGE; return 2 }
    if ($rest.Count) { GciErrOut ("gitlab-ci: unexpected argument '" + $rest[0] + "'`n" + $script:GCI_USAGE); return 2 }
    $events = @('push', 'merge_request_event', 'tag', 'schedule', 'web', 'api', 'trigger')
    if (-not ($events -ccontains $o.event)) { GciErrOut ("gitlab-ci: unknown --event '" + $o.event + "' (push, merge_request_event, tag, schedule, web, trigger)`n"); return 2 }
    $cv = GciOMap
    foreach ($kv in $vars) {
        if ($kv -cnotmatch '(?s)^([A-Za-z_][A-Za-z0-9_]*)=(.*)$') { GciErrOut ("gitlab-ci: --var needs KEY=VALUE, got '" + $kv + "'`n"); return 2 }
        $cv[$Matches[1]] = $Matches[2]
    }
    $top = GciFindTop (Get-Location).Path
    if (-not $top) { GciErrOut "gitlab-ci: not inside a git work tree`n"; return 2 }
    $script:REPOTOP = $top
    $file = if (Test-Path -LiteralPath $o.file -PathType Leaf) { (Get-Item -LiteralPath $o.file).FullName } else { Join-Path $top $o.file.Replace('/', '\') }
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { GciErrOut ("gitlab-ci: no " + $o.file + " here or at the top of the work tree (pass --file)`n"); return 2 }
    if (-not (GciPgit)) { GciErrOut "gitlab-ci: pgit.ps1 is not beside gitlab-ci.ps1 (it reads the repository)`n"; return 2 }
    try { $ci = GciLoad $file $o.file $top (GciOMap) $null }
    catch { $m = [string]$_.Exception.Message; if ($m.StartsWith('GCIDIE:')) { GciErrOut ($m.Substring(7) + "`n"); return 2 }; throw }

    $sha = GciRev 'HEAD'; if (-not $sha) { $sha = '' }
    $def = ''
    $oh = Join-Path $top '.git\refs\remotes\origin\HEAD'
    if (Test-Path -LiteralPath $oh) { $t = (GciSlurp $oh).Trim(); if ($t -cmatch '^ref: refs/remotes/(.*)$') { $def = $Matches[1] } }
    $def = $def -creplace '^origin/', ''
    if ($def -ceq '') { $def = 'main' }
    $branch = $o.branch
    if ($null -eq $branch) {
        $hd = (GciSlurp (Join-Path $top '.git\HEAD')).Trim()
        if ($hd -cmatch '^ref: refs/heads/(.+)$' -and $sha) { $branch = $Matches[1] }
    }
    $msg = if ($sha) { GciCommitMsg $sha } else { '' }
    $title = GciSubject $msg
    $msg = $msg -creplace '\s+$', ''
    $path = Split-Path -Leaf $top
    $v = GciOMap
    $v['CI_COMMIT_SHA'] = $sha; $v['CI_COMMIT_SHORT_SHA'] = $(if ($sha.Length -ge 8) { $sha.Substring(0, 8) } else { $sha }); $v['CI_DEFAULT_BRANCH'] = $def
    $v['CI_PROJECT_DIR'] = $top; $v['CI_PROJECT_NAME'] = $path; $v['CI_PROJECT_PATH'] = 'local/' + $path; $v['CI_PIPELINE_ID'] = '1'; $v['CI_PIPELINE_IID'] = '1'
    $v['CI_COMMIT_TITLE'] = $title; $v['CI_COMMIT_MESSAGE'] = $msg; $v['CI_SERVER'] = 'yes'; $v['CI_SERVER_HOST'] = 'localhost'
    $changed = $null
    if ($o.event -ceq 'merge_request_event') {
        if ($null -eq $branch) { GciErrOut "gitlab-ci: a merge request pipeline needs a branch (check one out or pass --branch)`n"; return 2 }
        $target = if ($null -ne $o.target) { $o.target } else { $def }
        $v['CI_PIPELINE_SOURCE'] = 'merge_request_event'; $v['CI_COMMIT_REF_NAME'] = $branch; $v['CI_MERGE_REQUEST_IID'] = '1'
        $v['CI_MERGE_REQUEST_SOURCE_BRANCH_NAME'] = $branch; $v['CI_MERGE_REQUEST_TARGET_BRANCH_NAME'] = $target; $v['CI_MERGE_REQUEST_EVENT_TYPE'] = 'detached'
        foreach ($ref in @($target, ('origin/' + $target))) {
            $t = GciRev $ref
            if ($t -and $sha) { $mb = GciMergeBase $t $sha; if ($mb) { $changed = GciDiffNames $mb $sha; break } }
        }
    } elseif ($o.event -ceq 'tag') {
        $tag = $o.tag
        if ($null -eq $tag -and $sha) {
            $refs = Get-PgitRefs $top 'refs/tags/'
            foreach ($rn in (GciSortOrd @($refs.Keys))) { $id = GciRev $rn; $c = $null; try { $c = (Get-PgitCommit $top $rn).sha } catch { }; if ($c -ceq $sha) { $tag = $rn.Substring(10); break } }
        }
        if ($null -eq $tag -or $tag -ceq '') { GciErrOut "gitlab-ci: --event tag needs --tag T (HEAD has no tag)`n"; return 2 }
        $v['CI_PIPELINE_SOURCE'] = 'push'; $v['CI_COMMIT_TAG'] = $tag; $v['CI_COMMIT_REF_NAME'] = $tag
    } else {
        if ($null -eq $branch) { GciErrOut "gitlab-ci: HEAD is detached: pass --branch B`n"; return 2 }
        $v['CI_PIPELINE_SOURCE'] = $o.event; $v['CI_COMMIT_BRANCH'] = $branch; $v['CI_COMMIT_REF_NAME'] = $branch
        if ($o.event -ceq 'push') {
            $parents = @(); if ($sha) { try { $parents = @((Get-PgitCommit $top $sha).parents) } catch { } }
            if ($parents.Count) { $changed = GciDiffNames $parents[0] $sha }
            else { $changed = GciSortOrd @((GciTreeMap $sha).Keys) }
        }
    }
    GciMergeInto $v $cv
    $ro = @{ vars = $v; changed = $changed; dir = $top; only_jobs = $(if ($jobsel.Count) { , $jobsel } else { $null }); manual = [bool]$o.manual; log_dir = $o.logs; _files = $null }
    try {
        if ($o.list) {
            $plan = GciPlan $ci $ro
            $w = 4
            foreach ($x in (@($plan.jobs) + @($plan.skipped))) { $flv = if ($null -ne $x.file) { $x.file } else { '-' }; if ($flv.Length -gt $w) { $w = $flv.Length } }
            $fmt = '{0,-24} {1,-10} {2,-10} {3,-' + $w + '}  {4}'
            $out = ''
            foreach ($x in $plan.jobs) { $flv = if ($null -ne $x.file) { $x.file } else { '-' }; $out += ($fmt -f $x.name, $x.stage, $x.when, $flv, $x.reason) + "`n" }
            foreach ($x in $plan.skipped) { $flv = if ($null -ne $x.file) { $x.file } else { '-' }; $out += ($fmt -f $x.name, '-', 'skipped', $flv, $x.reason) + "`n" }
            if (@($ci.included).Count) { $out += 'included: ' + (@($ci.included) -join ', ') + "`n" }
            $nj = @($plan.jobs).Count
            $out += 'pipeline: ' + $nj + ' job' + $(if ($nj -eq 1) { '' } else { 's' }) + "`n"
            GciOut $out
            return 0
        }
        $res = GciRun $ci $ro
    } catch { $m = [string]$_.Exception.Message; if ($m.StartsWith('GCIDIE:')) { GciErrOut ($m.Substring(7) + "`n"); return 2 }; throw }
    $out = ''
    foreach ($j in $res.jobs) {
        $st = if ($j.status -ceq 'not run') { 'not run' } else { $j.status }
        $out += ('{0,-24} {1,-10} {2,-16} {3,6:F1}s{4}' -f $j.name, $j.stage, $st, $j.duration, $(if ($j.status -ceq 'not run') { ' (needs bash)' } else { '' })) + "`n"
        if ($j.status -ceq 'failed' -and $j.log) {
            $ll = @((GciSlurp $j.log) -split "`n"); if ($ll.Count -and $ll[$ll.Count - 1] -ceq '') { $ll = @($ll[0..($ll.Count - 2)]) }
            $from = if ($ll.Count -gt 15) { $ll.Count - 15 } else { 0 }
            for ($k = $from; $k -lt $ll.Count; $k++) { $out += '    | ' + $ll[$k] + "`n" }
        }
    }
    foreach ($x in $res.skipped) { if ($x.reason -cmatch 'GitLab only') { $out += ('{0,-24} {1,-10} {2,-16} {3}' -f $x.name, '-', 'not run', $x.reason) + "`n" } }
    $nj = @($res.jobs).Count
    $out += 'pipeline: ' + $res.status + ' (' + $nj + ' job' + $(if ($nj -eq 1) { '' } else { 's' }) + ")`nlogs: " + $res.log_dir + "`n"
    GciOut $out
    if ($res.status -ceq 'failed') { return 1 }
    if ($res.status -ceq 'incomplete') { return 3 }
    return 0
}

# ---------------------------------------------------------------- test hooks: the parsed YAML and rules:if, as canonical text
function GciDump($v) {
    if ($null -eq $v) { return 'undef' }
    if (GciIsMap $v) { $p = @(); foreach ($k in (GciSortOrd (GciKeys $v))) { $p += ((GciQ $k) + ' => ' + (GciDump $v[$k])) }; return '{' + ($p -join ',') + '}' }
    if (GciIsRef $v) { return 'REF[' + ((@($v.path) | ForEach-Object { GciQ $_ }) -join ',') + ']' }
    if (GciIsList $v) { $p = @(); foreach ($x in $v) { $p += (GciDump $x) }; return '[' + ($p -join ',') + ']' }
    return (GciQ ([string]$v))
}
function GciQ([string]$s) {
    $o = '"'
    foreach ($ch in $s.ToCharArray()) {
        $c = [int]$ch
        if ($ch -ceq '"' -or $ch -ceq '\' -or $ch -ceq '$' -or $ch -ceq '@') { $o += '\' + [string]$ch }
        elseif ($c -eq 10) { $o += '\n' } elseif ($c -eq 9) { $o += '\t' } elseif ($c -eq 13) { $o += '\r' }
        elseif ($c -lt 32 -or $c -gt 126) { $o += '\x{' + ('{0:x}' -f $c) + '}' }
        else { $o += [string]$ch }
    }
    return $o + '"'
}

if ($args.Count -and [string]$args[0] -ceq '__lib') { return }
if ($args.Count -and [string]$args[0] -ceq '__yaml') {
    try { GciOut ((GciDump (GciParseYaml (GciSlurp $args[1]) $args[2])) + "`n"); exit 0 }
    catch { $m = [string]$_.Exception.Message; if ($m.StartsWith('GCIDIE:')) { GciOut ('ERR ' + $m.Substring(7) + "`n"); exit 0 }; throw }
}
if ($args.Count -and [string]$args[0] -ceq '__if') {
    $vv = GciOMap
    for ($k = 2; $k -lt $args.Count; $k++) { $kv = [string]$args[$k]; $ix = $kv.IndexOf('='); $vv[$kv.Substring(0, $ix)] = $kv.Substring($ix + 1) }
    try { GciOut ([string](GciEvalIf ([string]$args[1]) $vv) + "`n") }
    catch { $m = [string]$_.Exception.Message; if ($m.StartsWith('GCIDIE:')) { GciOut ('ERR ' + $m.Substring(7) + "`n") } else { throw } }
    exit 0
}
$script:PGIT_LOADED = $false
$pgitFile = Join-Path $PSScriptRoot 'pgit.ps1'
if (Test-Path -LiteralPath $pgitFile) { . $pgitFile __lib; $script:PGIT_LOADED = $true }
$ErrorActionPreference = 'Stop'
$rc = 2
try { $rc = GciCli @($args) }
catch { $m = [string]$_.Exception.Message; if ($m.StartsWith('GCIDIE:')) { $m = $m.Substring(7) }; GciErrOut ('gitlab-ci: ' + $m + "`n"); $rc = 2 }
exit $rc
