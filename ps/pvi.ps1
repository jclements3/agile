<#
pvi.ps1 -- a vi for the agile kit's text files (scrum.conf, scrum.txt, standups\*.txt, roster.txt, *.md) in
Windows PowerShell 5.1. Runs under Constrained Language Mode (AppLocker/WDAC): no install, no admin, no COM,
no Add-Type, no network.

  pvi FILE...                  edit: full-screen vi when keys can be read, else ex (line commands)
  pvi -Ex FILE...              ex mode. Under Constrained Language Mode it is the only mode: PowerShell refuses
                               to read single keys there (ReadKey is a .NET method), so pvi reads whole lines
  pvi -Script EXFILE FILE...   run the ex commands in EXFILE (one per line), then quit: batch edits and tests
  pvi -Keys "dwjx:wq<CR>" FILE feed full-screen keys (tests): <Esc> <CR> <BS> <Tab> <Del> <C-x> <lt> <Up> ...
                               -Rows/-Cols set the screen size, -Dump prints the final screen, -NormAbort stops
                               at the first error like vim's :normal

Files are written back byte for byte as they were read: LF or CRLF, a UTF-8 byte-order mark or none, a final
newline or none (:set ff=unix|dos, :set bomb|nobomb, :set eol|noeol change them). A file that is not UTF-8 is
edited byte for byte as Latin-1.

Agile commands (the kit's vim/scrum.vim, run through agile.ps1 beside this file, in the project folder that
holds scrum.conf): :SNew [Team...] :SStatus :SCompile :SDry :SReport :SLint [FILE] :SLintReply :SAnswers
:SJournal :SSprint [N] :SBacklog [Team] :SMembers [Team] :SBlocked :SRoadmap :SVelocity :SEpics :SPropose
[Team] :SQuad :SHealth :S ARGS (any agile command); :check runs compile -Dry and loads the errors as a list
(:cn :cp :cc [N] :cl); :verbs lists the stand-up file verbs; :help lists everything.
#>
param(
    [Parameter(Position = 0, ValueFromRemainingArguments = $true)][string[]]$Files,
    [string]$Script, [string]$Keys, [switch]$Ex, [string]$Agile, [int]$Rows = 0, [int]$Cols = 0, [switch]$Dump, [switch]$NormAbort, [string]$Today
)
$ErrorActionPreference = 'Stop'
$script:HOME_DIR = $PSScriptRoot
if (-not $script:HOME_DIR) { if ($env:AGILE_HOME) { $script:HOME_DIR = $env:AGILE_HOME } else { $script:HOME_DIR = Join-Path $HOME 'Documents\agile' } }
$script:STATE = 0                                    # every buffer change gets a new number: undo and the modified flag use it
$script:RX_IC = [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
$script:RX_NONE = [System.Text.RegularExpressions.RegexOptions]::None
$script:SPLIT = [string][char]0xE000                  # a line break made by \r in a :s replacement
$script:KW = '[A-Za-z0-9_\u00C0-\u00FF\p{L}\p{Nd}]'   # vim's 'iskeyword' (@,48-57,_,192-255), letters beyond Latin-1 too

# ================================================================ small helpers
function Slice($a, [int]$from, [int]$to) { if ($to -le $from) { return ,@() }; return ,@($a[$from..($to - 1)]) }
function Min2($a, $b) { if ($a -lt $b) { return $a }; return $b }
function Max2($a, $b) { if ($a -gt $b) { return $a }; return $b }
function FirstNonBlank([string]$s) { return ([regex]::Match($s, '^[ \t]*')).Length }
function IsDigit([string]$c) { return ($c.Length -eq 1 -and $c -cmatch '^[0-9]$') }
function FullPath([string]$p) {
    if (-not $p) { return '' }
    if ($p -match '^(?:[A-Za-z]:[\\/]|[\\/][\\/])') { return $p }
    return (Join-Path (Get-Location).Path $p)
}
function FileTime([string]$p) { if ($p -and (Test-Path -LiteralPath $p -PathType Leaf)) { return (Get-Item -LiteralPath $p).LastWriteTimeUtc.Ticks }; return 0 }
function Say($st, [string]$t) { foreach ($tl in ($t -split "`n")) { $st.msgs += $tl; $st.log += $tl } }

# ================================================================ files: byte for byte
function Utf8Bytes([string]$s) {
    if ($s.Length -eq 0) { return ,([byte[]]@()) }
    if ($s -cmatch '^[\x00-\x7F]*$') { return ,([byte[]][int[]][char[]]$s) }
    $parts = foreach ($m in [regex]::Matches($s, '[\x00-\x7F]+|[^\x00-\x7F]+')) {
        $t = $m.Value
        if ([int]$t[0] -lt 0x80) { [int[]][char[]]$t }
        else {
            $n = $t.Length; $i = 0
            while ($i -lt $n) {
                $c = [int]$t[$i]
                if ($c -lt 0x800) { 0xC0 -bor ($c -shr 6); 0x80 -bor ($c -band 0x3F) }
                elseif ($c -ge 0xD800 -and $c -le 0xDBFF -and ($i + 1) -lt $n) {
                    $lo = [int]$t[$i + 1]; $cp = 0x10000 + (($c - 0xD800) -shl 10) + ($lo - 0xDC00); $i++
                    0xF0 -bor ($cp -shr 18); 0x80 -bor (($cp -shr 12) -band 0x3F); 0x80 -bor (($cp -shr 6) -band 0x3F); 0x80 -bor ($cp -band 0x3F)
                }
                else { 0xE0 -bor ($c -shr 12); 0x80 -bor (($c -shr 6) -band 0x3F); 0x80 -bor ($c -band 0x3F) }
                $i++
            }
        }
    }
    return ,([byte[]]$parts)
}
function EmptyFile([string]$path) { return @{ path = $path; exists = $false; eol = "`n"; bom = $false; trailing = $true; latin1 = $false; lines = @(''); empty = $true; bytes = 0; note = '' } }
function ReadTextFile([string]$path) {
    $f = EmptyFile $path
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $f }
    $f.exists = $true
    $bytes = Get-Content -LiteralPath $path -Encoding Byte -ReadCount 0
    if ($null -eq $bytes) { $bytes = [byte[]]@() } elseif ($bytes -isnot [array]) { $bytes = [byte[]]@($bytes) }
    $n = $bytes.Count; $f.bytes = $n
    if ($n -ge 2 -and (($bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE) -or ($bytes[0] -eq 0xFE -and $bytes[1] -eq 0xFF))) {
        $f.latin1 = $true; $f.note = '[UTF-16: edited byte for byte]'
    } elseif ($n -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { $f.bom = $true }
    $text = ''
    if (-not $f.latin1 -and $n -gt 0) {
        $text = Get-Content -LiteralPath $path -Encoding UTF8 -Raw
        if ($null -eq $text) { $text = '' }
        if ($text.IndexOf([char]0xFFFD) -ge 0) {
            $chk = (Utf8Bytes $text).Count; if ($f.bom) { $chk += 3 }
            if ($chk -ne $n) { $f.latin1 = $true; $f.note = '[not UTF-8: edited byte for byte as Latin-1]' }
        }
        if (-not $f.latin1 -and $f.bom -and $text.Length -and [int]$text[0] -eq 0xFEFF) { $text = $text.Substring(1) }
    }
    if ($f.latin1) { $f.bom = $false; if ($n) { $text = -join [char[]][byte[]]$bytes } else { $text = '' } }
    if ($text.Length -eq 0) { return $f }
    $parts = $text -split "`n", 0, 'SimpleMatch'
    if ($parts[$parts.Count - 1] -eq '') { $f.trailing = $true; $parts = Slice $parts 0 ($parts.Count - 1) } else { $f.trailing = $false }
    $term = $parts.Count; if (-not $f.trailing) { $term-- }
    $allcr = $term -gt 0
    for ($i = 0; $i -lt $term; $i++) { if (-not $parts[$i].EndsWith("`r")) { $allcr = $false; break } }
    if ($allcr) {                                    # every line ends in CRLF: a dos file (vim's fileformat=dos)
        $f.eol = "`r`n"; $last = $parts[$parts.Count - 1]
        $parts = @($parts -replace "`r$", '')
        if (-not $f.trailing) { $parts[$parts.Count - 1] = $last }
    }
    $f.lines = $parts; $f.empty = $false
    return $f
}
function WriteTextFile($f, $lines, [string]$path, [bool]$append) {
    $text = ''
    if ($lines.Count) { $text = ($lines -join $f.eol); if ($f.trailing) { $text += $f.eol } }
    if ($f.latin1) {
        if ($text -match '[^\x00-\xFF]') { throw 'E513: write error, a character cannot be written as Latin-1 (the file was not UTF-8)' }
        if ($text.Length) { $bytes = [byte[]][int[]][char[]]$text } else { $bytes = [byte[]]@() }
    } else {
        $bytes = Utf8Bytes $text
        if ($f.bom -and -not $append) { $bytes = [byte[]](@(0xEF, 0xBB, 0xBF) + $bytes) }
    }
    if ($append) { Add-Content -LiteralPath $path -Encoding Byte -Value $bytes } else { Set-Content -LiteralPath $path -Encoding Byte -Value $bytes }
    return $bytes.Count
}

# ================================================================ buffers (arrays are never changed in place: undo keeps references)
function NewBuffer([string]$name) {
    if ($name) { $f = ReadTextFile (FullPath $name) } else { $f = EmptyFile '' }
    $L = $f.lines
    $ids = @(for ($k = 1; $k -le $L.Count; $k++) { $k })
    $script:STATE++
    return @{ name = $name; f = $f; L = $L; I = $ids; nid = $L.Count + 1; empty = [bool]$f.empty; state = $script:STATE; saved = $script:STATE
        undo = @(); redo = @(); marks = @{}; mtime = (FileTime $f.path) }
}
function IsMod($b) { return ($b.state -ne $b.saved) }
function Bump($b) { $script:STATE++; $b.state = $script:STATE }
function BufReplace($st, [int]$s, [int]$c, $new) {   # 0-based: lines s .. s+c-1 become $new
    if ($null -eq $st.ccur) { $st.ccur = $st.cur }
    $b = $st.buf; $new = @($new); $n = $b.L.Count
    $ids = @(foreach ($x in $new) { $b.nid; $b.nid = $b.nid + 1 })
    $b.L = (Slice $b.L 0 $s) + $new + (Slice $b.L ($s + $c) $n)
    $b.I = (Slice $b.I 0 $s) + $ids + (Slice $b.I ($s + $c) $n)
    if ($b.L.Count -eq 0) { $b.L = @(''); $b.I = @($b.nid); $b.nid = $b.nid + 1; $b.empty = $true } else { $b.empty = $false }   # vim: an empty buffer is one empty line, written as 0 bytes
    Bump $b
}
function BufSet($st, [int]$i, [string]$text) { if ($null -eq $st.ccur) { $st.ccur = $st.cur }; $b = $st.buf; $L = $b.L + @(); $L[$i] = $text; $b.L = $L; $b.empty = $false; Bump $b }
function BufAll($st, $L, $idv) { if ($null -eq $st.ccur) { $st.ccur = $st.cur }; $b = $st.buf; $b.L = $L; $b.I = $idv; if (-not ($b.empty -and $L.Count -eq 1 -and $L[0] -eq '')) { $b.empty = $false }; Bump $b }
function Snap($st) { $b = $st.buf; return @{ L = $b.L; I = $b.I; empty = $b.empty; state = $b.state; cur = $st.cur; r = $st.r; c = $st.c } }
function PushUndo($st, $snap) {
    $b = $st.buf; $b.undo += $snap
    if ($b.undo.Count -gt 1000) { $b.undo = Slice $b.undo 1 $b.undo.Count }
    $b.redo = @()
}
function UndoOnce($st, [bool]$redo) {
    $b = $st.buf
    if ($redo) { $from = $b.redo } else { $from = $b.undo }
    if ($from.Count -eq 0) { if ($redo) { throw 'Already at newest change' }; throw 'Already at oldest change' }
    $snap = $from[$from.Count - 1]; $rest = Slice $from 0 ($from.Count - 1)
    $now = Snap $st; $now.ccur = $snap.ccur; $now.ucur = $snap.ucur   # one undo header: the same change cursor both ways
    if ($redo) { $b.redo = $rest; $b.undo += $now } else { $b.undo = $rest; $b.redo += $now }
    $b.L = $snap.L; $b.I = $snap.I; $b.empty = $snap.empty; $b.state = $snap.state; $st.cur = $snap.cur; $st.r = $snap.r; $st.c = $snap.c
    if ($null -ne $snap.ucur -and -not $redo) { return @{ fixed = $snap.ucur } }
    return $snap.ccur
}
function ExUndoCursor($st, $oldL, $oldI, $ccur) {      # ex u/red: vim's u_undoredo cursor rule
    $b = $st.buf; $newL = $b.L; $newI = $b.I; $no = $oldL.Count; $nn = $newL.Count; $k = 0
    if ($ccur -is [hashtable]) { $st.cur = Min2 $ccur.fixed $nn; return }
    while ($k -lt $no -and $k -lt $nn -and $oldI[$k] -eq $newI[$k] -and $oldL[$k] -ceq $newL[$k]) { $k++ }
    if ($k -ge $no -and $k -ge $nn) { if ($st.cur -gt $nn) { $st.cur = $nn }; return }
    $e = 0; while ($e -lt ($no - $k) -and $e -lt ($nn - $k) -and $oldI[$no - 1 - $e] -eq $newI[$nn - 1 - $e] -and $oldL[$no - 1 - $e] -ceq $newL[$nn - 1 - $e]) { $e++ }
    $newsize = $nn - $k - $e                              # vim: top = $k (the line above the block), newsize lines in it now
    if ($null -ne $ccur -and $ccur -ge $k -and $ccur -le ($k + $newsize + 1)) { $st.cur = $ccur }   # the cursor when the change began
    else { $st.cur = $k + 1 }
    if ($st.cur -gt $nn) { $st.cur = $nn }; if ($st.cur -lt 1) { $st.cur = 1 }
}
function FindId($st, $id, [int]$hint) {
    $idv = $st.buf.I; $n = $idv.Count
    for ($k = (Max2 0 $hint); $k -lt $n; $k++) { if ($idv[$k] -eq $id) { return $k } }
    for ($k = 0; $k -lt (Min2 $hint $n); $k++) { if ($idv[$k] -eq $id) { return $k } }
    return -1
}
function FileInfo($st) {
    $b = $st.buf; $n = $b.L.Count; $name = $b.name; if (-not $name) { $name = '[No Name]' }
    $t = '"' + $name + '"'
    if (-not $b.f.exists -and $b.name) { $t += ' [New]' }
    if (IsMod $b) { $t += ' [Modified]' }
    if ($b.f.eol -eq "`r`n") { $t += ' [dos]' }
    if ($b.f.bom) { $t += ' [BOM]' }
    if (-not $b.f.trailing -and -not $b.empty) { $t += ' [noeol]' }
    if ($b.f.note) { $t += ' ' + $b.f.note }
    if ($b.empty) { return "$t --No lines in buffer--" }
    return "$t $n line$(if ($n -ne 1) { 's' }) --$([int](100 * (Max2 1 $st.cur) / $n))%--"
}
function EditFile($st, [string]$name, [bool]$force) {
    if (-not $force -and $null -ne $st.buf -and (IsMod $st.buf)) { throw 'E37: No write since last change (add ! to override)' }
    $st.buf = NewBuffer $name
    $st.cur = $st.buf.L.Count; $st.r = 0; $st.c = 0; $st.top = 0; $st.want = -2
    $b = $st.buf
    if (-not $name) { return }
    $t = '"' + $name + '"'
    if (-not $b.f.exists) { $t += ' [New]' } else {
        if ($b.f.eol -eq "`r`n") { $t += ' [dos]' }
        if ($b.f.bom) { $t += ' [BOM]' }
        if (-not $b.f.trailing -and -not $b.empty) { $t += ' [noeol]' }
        if ($b.f.note) { $t += ' ' + $b.f.note }
        $nl = $b.L.Count; if ($b.empty) { $nl = 0 }; $t += " ${nl}L, $($b.f.bytes)B"
    }
    Say $st $t
}

# ================================================================ vim regular expressions -> .NET
function ReadDelim([string]$s, [int]$i, [string]$d) {   # text up to an unescaped delimiter; \<delim> means the delimiter
    $o = ''
    while ($i -lt $s.Length) {
        $c = [string]$s[$i]
        if ($c -eq '\' -and ($i + 1) -lt $s.Length) {
            $nx = [string]$s[$i + 1]
            if ($nx -ceq $d) { $o += $d } else { $o += $c + $nx }
            $i += 2; continue
        }
        if ($c -ceq $d) { return @{ text = $o; next = $i + 1; closed = $true } }
        $o += $c; $i++
    }
    return @{ text = $o; next = $i; closed = $false }
}
function VimClassName([string]$n) {
    switch -CaseSensitive ($n) {
        'alpha' { return 'a-zA-Z' } 'digit' { return '0-9' } 'alnum' { return 'a-zA-Z0-9' } 'lower' { return 'a-z' } 'upper' { return 'A-Z' }
        'space' { return '\s' } 'blank' { return ' \t' } 'xdigit' { return '0-9A-Fa-f' } 'punct' { return '!-/:-@\[-`{-~' } 'cntrl' { return '\x00-\x1F\x7F' }
        'print' { return '\x20-\x7E' } 'graph' { return '\x21-\x7E' } 'return' { return '\r' } 'tab' { return '\t' } 'escape' { return '\x1B' } 'backspace' { return '\x08' }
    }
    throw "E: unknown character class [:${n}:]"
}
function ClassRe([string]$c) {                    # vim's \d \s \w ... (ASCII, as vim's defaults)
    switch -CaseSensitive ($c) {
        'd' { return '[0-9]' } 'D' { return '[^0-9]' } 's' { return '[ \t]' } 'S' { return '[^ \t]' } 'w' { return '[0-9A-Za-z_]' } 'W' { return '[^0-9A-Za-z_]' }
        'a' { return '[A-Za-z]' } 'A' { return '[^A-Za-z]' } 'l' { return '[a-z]' } 'L' { return '[^a-z]' } 'u' { return '[A-Z]' } 'U' { return '[^A-Z]' }
        'x' { return '[0-9A-Fa-f]' } 'X' { return '[^0-9A-Fa-f]' } 'o' { return '[0-7]' } 'O' { return '[^0-7]' } 'h' { return '[A-Za-z_]' } 'H' { return '[^A-Za-z_]' }
        'i' { return '[A-Za-z0-9_]' } 'I' { return '[A-Za-z_]' } 'k' { return '[A-Za-z0-9_]' } 'K' { return '[A-Za-z_]' } 'f' { return '[^ \t]' } 'F' { return '[^ \t0-9]' }
        'p' { return '[\x20-\x7E]' } 'P' { return '[\x20-\x7E]' }
    }
}
function VimRe($st, [string]$p) {
    $ic = [bool]$st.opt.ic; $mode = 'm'; $o = ''; $i = 0; $n = $p.Length; $start = $true
    while ($i -lt $n) {
        $c = [string]$p[$i]; $bs = $false
        if ($c -eq '\') {
            if (($i + 1) -ge $n) { $o += '\\'; $i++; continue }
            $c = [string]$p[$i + 1]; $bs = $true; $i += 2
            if ($c -ceq '_' -and $i -lt $n) {         # \_x: x or a line break; within one line, just x
                $c = [string]$p[$i]; $i++
                if ($c -eq '.') { $o += '.'; $start = $false; continue }
                if ($c -eq '^') { $o += '^'; continue }
                if ($c -eq '$') { $o += '$'; continue }
            }
        } else { $i++ }
        $role = 'lit'
        if ($bs) {
            if ('vmMV'.Contains($c) -and $c.Length -eq 1 -and $c -cmatch '^[vmMV]$') { $mode = $c; continue }
            if ($c -ceq 'c') { $ic = $true; continue }
            if ($c -ceq 'C') { $ic = $false; continue }
            if ($c -cmatch '^[dDsSwWaAlLuUxXoOhHiIkKfFpP]$') { $o += ClassRe $c; $start = $false; continue }
            if ($c -ceq 'n') { $o += '\n'; $start = $false; continue }
            if ($c -ceq 't') { $o += '\t'; $start = $false; continue }
            if ($c -ceq 'e') { $o += '\x1B'; $start = $false; continue }
            if ($c -ceq 'r') { $o += '\r'; $start = $false; continue }
            if ($c -ceq 'b') { $o += '\x08'; $start = $false; continue }
            if ($c -cmatch '^[1-9]$') { $o += '\' + $c; $start = $false; continue }
            if (($c -ceq 'z') -or ($c -ceq '@' -and $mode -cne 'v')) { throw "E: \$c is not supported in pvi patterns" }
            if ($mode -ceq 'v') { $role = 'lit' }
            elseif ($c -cmatch '^[()|+=?{<>%]$') { $role = 'sp' }
            elseif ($c -cmatch '^[.*\[~]$') { if ($mode -ceq 'M' -or $mode -ceq 'V') { $role = 'sp' } }
            elseif ($c -cmatch '^[\^$]$') { if ($mode -ceq 'V') { $role = 'sp' } }
        } else {
            if ($mode -ceq 'v') { if ($c -cmatch '^[()|+=?{<>%@.*\[~\^$]$') { $role = 'sp' } }
            elseif ($mode -ceq 'm') { if ($c -cmatch '^[.*\[~\^$]$') { $role = 'sp' } }
            else { if ($c -cmatch '^[\^$]$') { $role = 'sp' } }
        }
        if ($role -eq 'lit') { $o += [regex]::Escape($c); $start = $false; continue }
        switch -CaseSensitive ($c) {
            '(' { $o += '('; $start = $true; continue }
            ')' { $o += ')'; $start = $false; continue }
            '|' { $o += '|'; $start = $true; continue }
            '+' { $o += '+'; $start = $false; continue }
            '=' { $o += '?'; $start = $false; continue }
            '?' { $o += '?'; $start = $false; continue }
            '<' { $o += '(?<!' + $script:KW + ')(?=' + $script:KW + ')'; continue }
            '>' { $o += '(?<=' + $script:KW + ')(?!' + $script:KW + ')'; continue }
            '@' { throw 'E: \@ (look-around) is not supported in pvi patterns' }
            '%' {
                if ($i -lt $n -and [string]$p[$i] -eq '(') { $o += '(?:'; $i++; $start = $true; continue }
                if ($i -lt $n -and $mode -cne 'v' -and [string]$p[$i] -eq '\' -and ($i + 1) -lt $n -and [string]$p[$i + 1] -eq '(') { $o += '(?:'; $i += 2; $start = $true; continue }
                throw 'E: this \% item is not supported in pvi patterns'
            }
            '{' {
                $q = ''
                while ($i -lt $n -and [string]$p[$i] -ne '}') { if ([string]$p[$i] -eq '\' -and ($i + 1) -lt $n -and [string]$p[$i + 1] -eq '}') { break }; $q += [string]$p[$i]; $i++ }
                if ($i -lt $n -and [string]$p[$i] -eq '\') { $i++ }
                if ($i -lt $n) { $i++ }
                $lazy = $q.StartsWith('-'); if ($lazy) { $q = $q.Substring(1) }
                if ($q -eq '') { $t = '*' } elseif ($q -cmatch '^\d*(,\d*)?$') { if ($q.StartsWith(',')) { $t = '{0' + $q + '}' } else { $t = '{' + $q + '}' } } else { throw "E: bad \{ count: $q" }
                if ($lazy) { $t += '?' }
                $o += $t; $start = $false; continue
            }
            '.' { $o += '.'; $start = $false; continue }
            '*' { if ($start) { $o += '\*' } else { $o += '*' }; $start = $false; continue }
            '~' { $o += [regex]::Escape([string]$st.lastRep); $start = $false; continue }
            '^' { if ($start) { $o += '^' } else { $o += '\^' }; continue }
            '$' {
                $atEnd = ($i -ge $n)
                if (-not $atEnd) {
                    if ($mode -ceq 'v') { $atEnd = ([string]$p[$i] -eq '|' -or [string]$p[$i] -eq ')') }
                    else { $atEnd = ($i + 1 -lt $n -and [string]$p[$i] -eq '\' -and ([string]$p[$i + 1] -eq '|' -or [string]$p[$i + 1] -eq ')')) }
                }
                if ($atEnd) { $o += '$' } else { $o += '\$' }
                $start = $false; continue
            }
            '[' {
                $j = $i; if ($j -lt $n -and [string]$p[$j] -eq '^') { $j++ }
                if ($j -lt $n -and [string]$p[$j] -eq ']') { $j++ }
                $close = -1
                while ($j -lt $n) {
                    $cj = [string]$p[$j]
                    if ($cj -eq '\' -and ($j + 1) -lt $n) { $j += 2; continue }
                    if ($cj -eq '[' -and ($j + 1) -lt $n -and [string]$p[$j + 1] -eq ':') { $e = $p.IndexOf(':]', $j + 2); if ($e -gt 0) { $j = $e + 2; continue } }
                    if ($cj -eq ']') { $close = $j; break }
                    $j++
                }
                if ($close -lt 0) { $o += '\['; $start = $false; continue }
                $body = $p.Substring($i, $close - $i); $i = $close + 1
                $t = '['; $k = 0
                if ($body.StartsWith('^')) { $t += '^'; $k = 1 }
                while ($k -lt $body.Length) {
                    $ck = [string]$body[$k]
                    if ($ck -eq '\' -and ($k + 1) -lt $body.Length) {
                        $nx = [string]$body[$k + 1]; $k += 2
                        switch -CaseSensitive ($nx) { 'e' { $t += '\x1B' } 't' { $t += '\t' } 'r' { $t += '\r' } 'n' { $t += '\n' } 'b' { $t += '\x08' }
                            '\' { $t += '\\' } ']' { $t += '\]' } '^' { $t += '\^' } '-' { $t += '\-' } default { $t += '\\' + [regex]::Escape($nx) } }
                        continue
                    }
                    if ($ck -eq '[' -and ($k + 1) -lt $body.Length -and [string]$body[$k + 1] -eq ':') {
                        $e = $body.IndexOf(':]', $k + 2)
                        if ($e -gt 0) { $t += VimClassName $body.Substring($k + 2, $e - $k - 2); $k = $e + 2; continue }
                    }
                    if ($ck -eq '[') { $t += '\['; $k++; continue }
                    if ($ck -eq ']' -and $k -eq ($t.Length - 1)) { $t += '\]'; $k++; continue }
                    $t += $ck; $k++
                }
                $o += $t + ']'; $start = $false; continue
            }
        }
    }
    return @{ re = $o; ic = $ic }
}
function MkRx($st, [string]$pat) {
    if ($pat -eq '') { if ($null -eq $st.lastPat) { throw 'E35: No previous regular expression' }; $pat = $st.lastPat }
    $st.lastPat = $pat
    $t = VimRe $st $pat
    $opt = $script:RX_NONE; if ($t.ic) { $opt = $script:RX_IC }
    try { return [regex]::new($t.re, $opt) } catch { throw "E383: Invalid search string: $pat" }
}
function ExpandRep([string]$rep, $m) {
    $out = ''; $one = ''; $all = ''; $i = 0; $n = $rep.Length
    while ($i -lt $n) {
        $c = [string]$rep[$i]; $piece = ''
        if ($c -eq '\' -and ($i + 1) -lt $n) {
            $d = [string]$rep[$i + 1]; $i += 2
            if ($d -cmatch '^[0-9]$') { $g = [int]$d; if ($g -lt $m.Groups.Count) { $piece = $m.Groups[$g].Value } }
            elseif ($d -ceq 'n') { $piece = [string][char]0 }
            elseif ($d -ceq 'r') { $piece = $script:SPLIT }
            elseif ($d -ceq 't') { $piece = "`t" }
            elseif ($d -ceq 'u' -or $d -ceq 'l') { $one = $d; continue }
            elseif ($d -ceq 'U' -or $d -ceq 'L') { $all = $d; continue }
            elseif ($d -ceq 'e' -or $d -ceq 'E') { $all = ''; continue }
            else { $piece = $d }
        }
        elseif ($c -eq '&') { $piece = $m.Value; $i++ }
        elseif ($c -eq "`r") { $piece = $script:SPLIT; $i++ }
        else { $piece = $c; $i++ }
        if ($piece.Length) {
            if ($all -ceq 'U') { $piece = $piece.ToUpperInvariant() } elseif ($all -ceq 'L') { $piece = $piece.ToLowerInvariant() }
            if ($one) {
                $f = $piece.Substring(0, 1); if ($one -ceq 'u') { $f = $f.ToUpperInvariant() } else { $f = $f.ToLowerInvariant() }
                $piece = $f + $piece.Substring(1); $one = ''
            }
        }
        $out += $piece
    }
    return $out
}
function SubLine([string]$line, $rx, [string]$rep, [bool]$global) {
    $out = ''; $pos = 0; $cnt = 0; $lastEnd = -1
    foreach ($m in $rx.Matches($line)) {
        if ($m.Length -eq 0 -and $m.Index -eq $lastEnd) { continue }   # no empty match right after a match (vim)
        if ($m.Length -eq 0 -and $m.Index -eq $line.Length -and $cnt -gt 0) { break }   # nor at the end of a line that matched
        $out += $line.Substring($pos, $m.Index - $pos) + (ExpandRep $rep $m)
        $pos = $m.Index + $m.Length; $lastEnd = $pos; $cnt++
        if (-not $global) { break }
    }
    return @{ text = $out + $line.Substring($pos); count = $cnt }
}
function TildeRep($st, [string]$rep) {          # ~ in a replacement: the previous replacement string
    $o = ''; $i = 0
    while ($i -lt $rep.Length) {
        $c = [string]$rep[$i]
        if ($c -eq '\' -and ($i + 1) -lt $rep.Length) { $o += $c + [string]$rep[$i + 1]; $i += 2; continue }
        if ($c -eq '~') { $o += [string]$st.lastRep; $i++; continue }
        $o += $c; $i++
    }
    return $o
}

# ================================================================ ex: addresses and ranges
function SearchLine($st, [string]$pat, [bool]$fwd, [int]$from) {
    $rx = MkRx $st $pat; $st.lastDir = $(if ($fwd) { 1 } else { -1 })
    $L = $st.buf.L; $n = $L.Count
    if ($n -eq 0) { throw "E486: Pattern not found: $pat" }
    for ($k = 1; $k -le $n; $k++) {
        if ($fwd) { $ln = $from + $k } else { $ln = $from - $k }
        if ($ln -gt $n -or $ln -lt 1) {
            if (-not $st.opt.ws) { if ($fwd) { throw "E385: Search hit BOTTOM without match for: $pat" }; throw "E384: Search hit TOP without match for: $pat" }
            if ($fwd) { $ln -= $n } else { $ln += $n }
        }
        if ($rx.IsMatch($L[$ln - 1])) { return $ln }
    }
    throw "E486: Pattern not found: $pat"
}
function MarkLine($st, [string]$mk) {
    if (-not $st.buf.marks.ContainsKey($mk)) { throw 'E20: Mark not set' }
    $k = FindId $st $st.buf.marks[$mk] 0
    if ($k -lt 0) { throw 'E20: Mark not set' }
    return $k + 1
}
function ParseAddr($st, [string]$s, $p) {
    $i = $p.i; $n = $st.buf.L.Count
    while ($i -lt $s.Length -and ([string]$s[$i] -eq ' ' -or [string]$s[$i] -eq "`t")) { $i++ }
    $base = $null; $srch = $false; $c = ''; if ($i -lt $s.Length) { $c = [string]$s[$i] }
    if (IsDigit $c) { $j = $i; while ($j -lt $s.Length -and (IsDigit ([string]$s[$j]))) { $j++ }; $base = [int]$s.Substring($i, $j - $i); $i = $j }
    elseif ($c -eq '.') { $base = $st.cur; $i++ }
    elseif ($c -eq '$') { $base = $n; $i++ }
    elseif ($c -eq "'" -and ($i + 1) -lt $s.Length) { $base = MarkLine $st ([string]$s[$i + 1]); $i += 2 }
    elseif ($c -eq '/' -or $c -eq '?') { $r = ReadDelim $s ($i + 1) $c; $i = $r.next; $base = SearchLine $st $r.text ($c -eq '/') $st.cur; $srch = $true }
    while ($i -lt $s.Length) {
        $c = [string]$s[$i]
        if ($c -eq '+' -or $c -eq '-') {
            $j = $i + 1; while ($j -lt $s.Length -and (IsDigit ([string]$s[$j]))) { $j++ }
            $k = 1; if ($j -gt ($i + 1)) { $k = [int]$s.Substring($i + 1, $j - $i - 1) }
            if ($null -eq $base) { $base = $st.cur }
            if ($c -eq '+') { $base += $k } else { $base -= $k }
            $i = $j
        } elseif ((IsDigit $c) -and $null -ne $base) {   # ".5" is ".+5"
            $j = $i; while ($j -lt $s.Length -and (IsDigit ([string]$s[$j]))) { $j++ }
            $base += [int]$s.Substring($i, $j - $i); $i = $j
        } else { break }
    }
    if ($srch) { if ($base -gt $n) { $base = $n }; if ($base -lt 1) { $base = 1 } }   # vim clamps a pattern address with an offset
    $p.i = $i
    return $base
}
function ParseRange($st, [string]$s, $p) {
    $addrs = @()
    while ($p.i -lt $s.Length -and [string]$s[$p.i] -eq ' ') { $p.i++ }
    if ($p.i -lt $s.Length -and [string]$s[$p.i] -eq '%') { $p.i++; return ,@(1, $st.buf.L.Count) }
    while ($true) {
        $a = ParseAddr $st $s $p
        $c = ''; if ($p.i -lt $s.Length) { $c = [string]$s[$p.i] }
        if ($c -eq ',' -or $c -eq ';') {
            if ($null -eq $a) { $a = $st.cur }
            $addrs += $a
            if ($c -eq ';') { if ($a -lt 0 -or $a -gt $st.buf.L.Count) { throw 'E16: Invalid range' }; $st.cur = $a }
            $p.i++; continue
        }
        if ($null -ne $a) { $addrs += $a } elseif ($addrs.Count) { $addrs += $st.cur }
        break
    }
    return ,$addrs
}
function Rng($st, $addrs, [string]$dflt) {
    $n = $st.buf.L.Count
    if ($addrs.Count -eq 0) { if ($dflt -eq '%') { $a = 1; $b = $n } else { $a = $st.cur; $b = $st.cur } }
    elseif ($addrs.Count -eq 1) { $a = $addrs[0]; $b = $addrs[0] }
    else { $a = $addrs[$addrs.Count - 2]; $b = $addrs[$addrs.Count - 1] }
    if ($a -lt 0 -or $b -gt $n -or $a -gt $n) { throw 'E16: Invalid range' }
    if ($a -gt $b) { throw 'E493: Backwards range given' }
    return ,@($a, $b)
}
function NoZero($r, [int]$n) { $a = $r[0]; $b = $r[1]; if ($n -gt 0) { if ($a -lt 1) { $a = 1 }; if ($b -lt 1) { $b = 1 } }; return ,@($a, $b) }
function CountArg($st, $r, [string]$arg) {        # "d 3": count lines from the last address
    $t = $arg.Trim()
    if ($t -cmatch '^\d+$') {
        $k = [int]$t; if ($k -lt 1) { throw 'E939: Positive count required' }
        $a = $r[1]; $b = Min2 ($a + $k - 1) $st.buf.L.Count; return ,@($a, $b)
    }
    if ($t) { throw "E488: Trailing characters: $t" }
    return ,$r
}
function RegArg($st, [string]$arg) {               # "d a 3", "y A", "pu b": a register name, then the rest
    $t = $arg.TrimStart()
    if ($t.Length -and $t -cmatch '^[a-zA-Z"]' -and ($t.Length -eq 1 -or [string]$t[1] -eq ' ')) { return @{ reg = [string]$t[0]; rest = $t.Substring(1) } }
    return @{ reg = ''; rest = $t }
}
function SetReg($st, [string]$name, $lines, [bool]$lw) {
    $new = @{ lw = $lw; lines = @($lines) }
    if ($name -cmatch '^[A-Z]$') {
        $k = $name.ToLowerInvariant()
        if ($st.regs.ContainsKey($k)) { $old = $st.regs[$k]; $new = @{ lw = ($old.lw -or $lw); lines = @($old.lines) + @($lines) } }
        $st.regs[$k] = $new
    } elseif ($name -cmatch '^[a-z]$') { $st.regs[$name] = $new }
    $st.reg = $new
}
function GetReg($st, [string]$name) {
    if ($name -cmatch '^[a-zA-Z]$') { $k = $name.ToLowerInvariant(); if ($st.regs.ContainsKey($k)) { return $st.regs[$k] }; throw "E353: Nothing in register $name" }
    return $st.reg
}

# ================================================================ join (vim's do_join)
function JoinLines($parts, [bool]$spaces) {
    $acc = [string]$parts[0]; $col = 0
    $e1 = ''; $e2 = ''
    if ($acc.Length) { $e1 = [string]$acc[$acc.Length - 1]; if ($acc.Length -ge 2) { $e2 = [string]$acc[$acc.Length - 2] } }
    for ($t = 1; $t -lt $parts.Count; $t++) {
        $curr = [string]$parts[$t]; $sp = 0
        if ($spaces) {
            $curr = $curr -replace '^[ \t]+', ''
            if ($curr.Length -gt 0 -and [string]$curr[0] -ne ')' -and $acc.Length -gt 0 -and $e1 -ne "`t") {
                if ($e1 -eq ' ') { $e1 = $e2 } else { $sp++ }
                if ($e1 -eq '.' -or $e1 -eq '?' -or $e1 -eq '!') { $sp++ }       # 'joinspaces' (on in vim)
            }
        }
        $col = $acc.Length
        $acc = $acc + (' ' * $sp) + $curr
        $e1 = ''; $e2 = ''
        if ($curr.Length) { $e1 = [string]$curr[$curr.Length - 1]; if ($curr.Length -ge 2) { $e2 = [string]$curr[$curr.Length - 2] } }
    }
    return @{ text = $acc; col = $col }
}
function ShiftLine([string]$line, [int]$dir) {     # > and <: one 'shiftwidth' (8), indent rebuilt with tabs (vim's defaults)
    if ($line.Length -eq 0) { return $line }
    $m = [regex]::Match($line, '^[ \t]*'); $w = 0
    foreach ($ch in [char[]]$m.Value) { if ($ch -eq "`t") { $w = $w + 8 - ($w % 8) } else { $w++ } }
    $w = Max2 0 ($w + 8 * $dir)
    $tabs = ($w - ($w % 8)) / 8
    return ("`t" * $tabs) + (' ' * ($w % 8)) + $line.Substring($m.Length)
}
function OrdCmp([string]$a, [string]$b) { return [string]::CompareOrdinal($a, $b) }
function MergeSort($idx, $sortKeys, [bool]$num) {      # stable sort of indexes by keys (ordinal strings, or numbers)
    if ($idx.Count -le 1) { return ,$idx }
    $mid = ($idx.Count - ($idx.Count % 2)) / 2
    $left = MergeSort (Slice $idx 0 $mid) $sortKeys $num; $right = MergeSort (Slice $idx $mid $idx.Count) $sortKeys $num
    $i = 0; $j = 0
    $out = @(while ($i -lt $left.Count -or $j -lt $right.Count) {
        if ($j -ge $right.Count) { $left[$i]; $i++; continue }
        if ($i -ge $left.Count) { $right[$j]; $j++; continue }
        $ka = $sortKeys[$left[$i]]; $kb = $sortKeys[$right[$j]]
        if ($num) { $le = ($ka -le $kb) } else { $le = ((OrdCmp $ka $kb) -le 0) }
        if ($le) { $left[$i]; $i++ } else { $right[$j]; $j++ }
    })
    return ,$out
}

# ================================================================ ex commands
$script:EXCMDS = @(
    @('append', 1), @('args', 2), @('change', 1), @('cc', 2), @('check', 5), @('clist', 2), @('cnext', 2), @('copen', 4), @('copy', 2), @('cprevious', 2),
    @('delete', 1), @('edit', 1), @('exit', 3), @('file', 1), @('global', 1), @('help', 1), @('insert', 1), @('join', 1), @('k', 1), @('list', 1),
    @('mark', 2), @('move', 1), @('next', 1), @('nohlsearch', 3), @('number', 2), @('print', 1), @('previous', 4), @('put', 2), @('quit', 1),
    @('read', 1), @('redo', 3), @('substitute', 1), @('set', 2), @('sort', 3), @('t', 1), @('undo', 1), @('update', 2), @('vglobal', 1),
    @('verbs', 5), @('version', 2), @('visual', 2), @('write', 1), @('wq', 2), @('wall', 2), @('xit', 1), @('yank', 1), @('z', 1), @('Next', 1)
)
$script:AGILECMDS = @('S', 'SNew', 'SStatus', 'SCompile', 'SDry', 'SReport', 'SLint', 'SLintReply', 'SAnswers', 'SJournal', 'SSprint', 'SBacklog',
    'SMembers', 'SBlocked', 'SRoadmap', 'SVelocity', 'SEpics', 'SPropose', 'SQuad', 'SHealth', 'SCheck', 'SDrill')
function LookupCmd([string]$w) {
    foreach ($e in $script:EXCMDS) { $full = $e[0]; if ($w.Length -ge $e[1] -and $w.Length -le $full.Length -and $full.Substring(0, $w.Length) -ceq $w) { return $full } }
    if ($script:AGILECMDS -ccontains $w) { return $w }
    return $null
}
function ReadInputLines($st) {
    if ($st.visual) { throw 'E: a, i and c read lines in ex mode; in the full-screen editor use o, O, i or A' }
    $out = @()
    while ($true) {
        $tl = NextLine $st
        if ($null -eq $tl -or $tl -eq '.') { break }
        $out += $tl
    }
    return ,$out
}
function NextLine($st) {
    if ($null -ne $st.feed) { if ($st.feedi -lt $st.feed.Count) { $tl = $st.feed[$st.feedi]; $st.feedi++; return [string]$tl }; return $null }
    try { $tl = Read-Host } catch { return $null }
    return $tl
}
function ExTop($st, [string]$line) {               # one command line: one undo step
    $b = $st.buf; $snap = Snap $st; $state0 = $b.state; $st.ccur = $null; $st.ucur = $null
    try { ExLine $st $line }
    catch { Say $st ([string]$_.Exception.Message); $st.errors++ }
    finally { if ($st.buf -eq $b -and $b.state -ne $state0 -and -not $st.undoing) { $snap.ccur = $st.ccur; $snap.ucur = $st.ucur; PushUndo $st $snap }; $st.undoing = $false }
}
function ExLine($st, [string]$s) {
    $p = @{ i = 0 }
    while ($p.i -lt $s.Length -and ([string]$s[$p.i] -eq ':' -or [string]$s[$p.i] -eq ' ' -or [string]$s[$p.i] -eq "`t")) { $p.i++ }
    if ($p.i -lt $s.Length -and [string]$s[$p.i] -eq '"') { return }
    $addrs = ParseRange $st $s $p
    while ($p.i -lt $s.Length -and ([string]$s[$p.i] -eq ' ' -or [string]$s[$p.i] -eq "`t")) { $p.i++ }
    $n = $st.buf.L.Count
    if ($p.i -ge $s.Length -or [string]$s[$p.i] -eq '|') {             # a bare address: go there
        if ($addrs.Count) {
            $ln = $addrs[$addrs.Count - 1]
            if ($ln -lt 0) { throw 'E16: Invalid range' }
            if ($ln -gt $n) { $ln = $n }; if ($ln -lt 1 -and $n -gt 0) { $ln = 1 }
            $st.cur = $ln
            if (-not $st.visual -and $n -gt 0 -and -not $st.inGlobal) { Say $st $st.buf.L[$ln - 1] }
        } elseif (-not $st.visual -and -not $st.inGlobal) {
            if ($st.cur -ge $n) { throw 'E501: At end-of-file' }
            $st.cur++; Say $st $st.buf.L[$st.cur - 1]
        }
        if ($p.i -lt $s.Length) { ExLine $st $s.Substring($p.i + 1) }
        return
    }
    $c = [string]$s[$p.i]
    if ($c -cmatch '^[A-Za-z]$') {
        $j = $p.i; while ($j -lt $s.Length -and [string]$s[$j] -cmatch '^[A-Za-z]$') { $j++ }
        $w = $s.Substring($p.i, $j - $p.i)
        $name = LookupCmd $w
        if ($null -eq $name -and $w.Length -eq 2 -and [string]$w[0] -ceq 'k') { $name = 'k'; $j = $p.i + 1 }
        if ($null -eq $name -and $w.Length -gt 1 -and [string]$w[0] -ceq 's' -and $w.Substring(1) -cmatch '^[cegiInp#lr]+$') { $name = 'substitute'; $j = $p.i + 1 }
        if ($null -eq $name) { throw "E492: Not an editor command: $($s.Substring($p.i).Trim())" }
        $p.i = $j
    } elseif ('!=&<>#~'.Contains($c)) { $name = $c; $p.i++ }
    else { throw "E492: Not an editor command: $($s.Substring($p.i).Trim())" }
    $bang = $false
    if ($name -ne '!' -and $p.i -lt $s.Length -and [string]$s[$p.i] -eq '!') { $bang = $true; $p.i++ }
    $rest = $s.Substring($p.i); $next = $null
    $whole = ($name -eq 'global' -or $name -eq 'vglobal' -or $name -eq '!' -or ($script:AGILECMDS -ccontains $name) -or
        (($name -eq 'read' -or $name -eq 'write') -and $rest.TrimStart().StartsWith('!')))
    if (-not $whole) {
        $k0 = 0                                       # :s and :& own their pattern and replacement: a | in them is not a separator
        if (($name -eq 'substitute') -and $rest.Length -and [string]$rest[0] -cnotmatch '^[A-Za-z0-9 "|\\&]$') {
            $d = [string]$rest[0]; $r1 = ReadDelim $rest 1 $d; $k0 = $r1.next
            if ($r1.closed) { $k0 = (ReadDelim $rest $r1.next $d).next }
        }
        for ($k = $k0; $k -lt $rest.Length; $k++) {
            $ck = [string]$rest[$k]
            if ($ck -eq '\' -and ($k + 1) -lt $rest.Length) { $k++; continue }
            if ($ck -eq '|') { $next = $rest.Substring($k + 1); $rest = $rest.Substring(0, $k); break }
        }
    }
    ExCmd $st $name $bang $addrs $rest
    if ($null -ne $next -and -not $st.quit) { ExLine $st $next }
}
function PrintLines($st, [int]$a, [int]$b, [string]$how) {
    $L = $st.buf.L
    for ($k = $a; $k -le $b; $k++) {
        $t = [string]$L[$k - 1]
        if ($how -eq 'l') { $t = ($t -replace "`t", '^I') + '$' }
        if ($how -eq 'nu' -or $st.opt.nu -or $how -eq 'p') { $t = ('{0,3} ' -f $k) + $t }
        Say $st $t
    }
    $st.cur = $b
}
function ExCmd($st, [string]$name, [bool]$bang, $addrs, [string]$arg) {
    $bf = $st.buf; $n = $bf.L.Count
    switch -CaseSensitive ($name) {
        { $_ -eq 'print' -or $_ -eq 'number' -or $_ -eq '#' -or $_ -eq 'list' } {
            if ($bf.empty) { Say $st '--No lines in buffer--'; return }
            $r = NoZero (Rng $st $addrs '.') $n; $r = CountArg $st $r ($arg -replace '^[ ]*[#lp]*', '')
            $how = 'p'; if ($name -eq 'list') { $how = 'l' } elseif ($name -ne 'print') { $how = 'nu' }
            PrintLines $st $r[0] $r[1] $how; return
        }
        '=' { if ($addrs.Count) { $r = Rng $st $addrs '.'; Say $st ([string]$r[1]) } else { Say $st ([string]$n) }; return }
        'z' {
            if ($bf.empty) { Say $st '--No lines in buffer--'; return }
            $r = NoZero (Rng $st $addrs '.') $n; $at = $r[1]
            $kind = '+'; $t = $arg.Trim()
            if ($t.Length -and '+-.^='.Contains([string]$t[0])) { $kind = [string]$t[0]; $t = $t.Substring(1).Trim() }
            $w = [int]$st.opt.window; if ($t -cmatch '^\d+$') { $w = [int]$t }
            switch ($kind) {
                '+' { $a = $at; $b = Min2 $n ($at + $w - 1) }
                '-' { $b = $at; $a = Max2 1 ($at - $w + 1) }
                '^' { $b = Max2 1 ($at - $w); $a = Max2 1 ($b - $w + 1) }
                default { $h = ($w - ($w % 2)) / 2; $a = Max2 1 ($at - $h); $b = Min2 $n ($at + $h) }
            }
            for ($k = $a; $k -le $b; $k++) {
                if ($kind -eq '=' -and $k -eq $at) { Say $st '----------' }
                Say $st (('{0,3} ' -f $k) + $bf.L[$k - 1])
                if ($kind -eq '=' -and $k -eq $at) { Say $st '----------' }
            }
            if ($kind -eq '=' -or $kind -eq '.') { $st.cur = $at } else { $st.cur = $b }
            return
        }
        { $_ -eq 'append' -or $_ -eq 'insert' } {
            $r = Rng $st $addrs '.'; $at = $r[1]
            if ($name -eq 'insert') { $at = Max2 0 ($at - 1) }
            $new = ReadInputLines $st
            if ($new.Count -and $bf.empty) { BufReplace $st 0 1 $new; $st.cur = $new.Count; return }   # into an empty buffer: replaces its empty line
            if ($new.Count) { BufReplace $st $at 0 $new; $st.cur = $at + $new.Count } else { $st.cur = Max2 1 $at }
            return
        }
        'change' {
            $r = NoZero (Rng $st $addrs '.') $n; $r = CountArg $st $r $arg
            SetReg $st '' (Slice $bf.L ($r[0] - 1) $r[1]) $true
            $new = ReadInputLines $st
            BufReplace $st ($r[0] - 1) ($r[1] - $r[0] + 1) $new
            if ($new.Count) { $st.cur = $r[0] - 1 + $new.Count } else { $st.cur = Min2 (Max2 1 ($r[0] - 1)) $st.buf.L.Count }
            return
        }
        { $_ -eq 'delete' -or $_ -eq 'yank' } {
            $ra = RegArg $st $arg
            $r = NoZero (Rng $st $addrs '.') $n; $r = CountArg $st $r $ra.rest
            SetReg $st $ra.reg (Slice $bf.L ($r[0] - 1) $r[1]) $true
            if ($name -eq 'yank') { return }
            if ($null -eq $st.ccur) { $st.ccur = $r[0] }   # vim's ex_operators puts the cursor on line1 first (undo returns there)
            BufReplace $st ($r[0] - 1) ($r[1] - $r[0] + 1) @()
            $m = $st.buf.L.Count; $st.cur = Min2 $r[0] $m
            if (($r[1] - $r[0] + 1) -ge 3) { Say $st "$($r[1] - $r[0] + 1) fewer lines" }
            return
        }
        'put' {
            $ra = RegArg $st $arg; $reg = GetReg $st $ra.reg
            if ($reg.lines.Count -eq 0) { throw 'E353: Nothing in register "' }
            $r = Rng $st $addrs '.'; $at = $r[1]; if ($bang) { $at = Max2 0 ($at - 1) }
            BufReplace $st $at 0 $reg.lines
            $st.cur = $at + $reg.lines.Count; return
        }
        { $_ -eq 'move' -or $_ -eq 'copy' -or $_ -eq 't' } {
            $r = NoZero (Rng $st $addrs '.') $n
            $q = @{ i = 0 }; $dest = ParseAddr $st $arg $q
            if ($null -eq $dest) { throw 'E14: Invalid address' }
            if ($dest -lt 0 -or $dest -gt $n) { throw 'E16: Invalid range' }
            $cnt = $r[1] - $r[0] + 1
            if ($name -eq 'move') {
                if ($dest -ge $r[0] -and $dest -lt $r[1]) { throw 'E134: Cannot move a range of lines into itself' }
                if ($dest -eq $r[1] -or $dest -eq ($r[0] - 1)) { $st.cur = $dest; if ($dest -eq ($r[0] - 1)) { $st.cur = $r[1] }; Bump $bf; return }
                $mvL = Slice $bf.L ($r[0] - 1) $r[1]; $mvI = Slice $bf.I ($r[0] - 1) $r[1]
                $L = (Slice $bf.L 0 ($r[0] - 1)) + (Slice $bf.L $r[1] $n); $idv = (Slice $bf.I 0 ($r[0] - 1)) + (Slice $bf.I $r[1] $n)
                $d = $dest; if ($dest -ge $r[1]) { $d = $dest - $cnt }
                $c = $st.cur                                  # vim undoes a move as two entries (insert, delete): its cursor rule
                if ($dest -lt $r[0]) { $t1 = $r[0] - 1 + $cnt; $u = $r[0] + $cnt; if ($c -ge $t1 -and $c -le ($t1 + $cnt + 1)) { $u = $c }; if ($c -ge $dest -and $c -le ($dest + 1)) { $u = $c } }
                else { $t1 = $r[0] - 1; $u = $r[0]; if ($c -ge $t1 -and $c -le ($t1 + $cnt + 1)) { $u = $c } }
                if ($u -gt $n) { if ($c -ge $r[0] -and $c -le $r[1]) { $u = $c } else { $u = $n } }   # fitted to vim: 257 of 260 probes
                $st.ucur = $u
                BufAll $st ((Slice $L 0 $d) + $mvL + (Slice $L $d $L.Count)) ((Slice $idv 0 $d) + $mvI + (Slice $idv $d $idv.Count))
                $st.cur = $d + $cnt
                if ($cnt -ge 3) { Say $st "$cnt lines moved" }
            } else {
                BufReplace $st $dest 0 (Slice $bf.L ($r[0] - 1) $r[1])
                $st.cur = $dest + $cnt
            }
            return
        }
        'join' {
            $r = NoZero (Rng $st $addrs '.') $n
            $t = $arg.Trim()
            if ($t -cmatch '^\d+$') { $a = $r[1]; $b = $a + [int]$t - 1 } else { $a = $r[0]; $b = $r[1]; if ($a -eq $b) { $b = $a + 1 } }
            if ($b -gt $n) { $b = $n }
            if ($b -le $a) { return }
            $j = JoinLines (Slice $bf.L ($a - 1) $b) (-not $bang)
            BufReplace $st ($a - 1) ($b - $a + 1) @($j.text)
            $st.cur = $a; return
        }
        { $_ -eq 'substitute' -or $_ -eq '&' -or $_ -eq '~' } { ExSub $st $name $addrs $arg; return }
        { $_ -eq 'global' -or $_ -eq 'vglobal' } {
            if ($st.inGlobal) { throw 'E147: Cannot do :global recursive' }
            $inv = ($name -eq 'vglobal') -or $bang
            $a2 = $arg.TrimStart()
            if ($a2.Length -eq 0) { throw 'E35: No previous regular expression' }
            $d = [string]$a2[0]
            if ($d -cmatch '^[A-Za-z0-9"|\\ ]$') { throw 'E146: Regular expressions can not be delimited by letters' }
            $rd = ReadDelim $a2 1 $d; $pat = $rd.text; $cmd2 = ''
            if ($rd.closed) { $cmd2 = $a2.Substring($rd.next) }
            if ($cmd2.Trim() -eq '') { $cmd2 = 'p' }
            $rx = MkRx $st $pat
            $r = Rng $st $addrs '%'
            $L = $bf.L; $idv = $bf.I
            $marked = @(for ($k = (Max2 1 $r[0]); $k -le $r[1]; $k++) { if ($rx.IsMatch([string]$L[$k - 1]) -ne $inv) { $idv[$k - 1] } })
            if ($marked.Count -eq 0) { if ($inv) { Say $st "Pattern found in every line: $pat" } else { Say $st "Pattern not found: $pat" }; return }
            $st.inGlobal = $true; $hint = 0
            try {
                foreach ($id in $marked) {
                    $idx = FindId $st $id $hint; if ($idx -lt 0) { continue }; $hint = $idx
                    $st.cur = $idx + 1
                    ExLine $st $cmd2
                    if ($st.quit) { break }
                }
            } finally { $st.inGlobal = $false }
            return
        }
        'undo' { $oL = $st.buf.L; $oI = $st.buf.I; $cc = UndoOnce $st $false; $st.undoing = $true; ExUndoCursor $st $oL $oI $cc; return }
        'redo' { $oL = $st.buf.L; $oI = $st.buf.I; $cc = UndoOnce $st $true; $st.undoing = $true; ExUndoCursor $st $oL $oI $cc; return }
        { $_ -eq 'write' -or $_ -eq 'wq' -or $_ -eq 'xit' -or $_ -eq 'exit' -or $_ -eq 'update' -or $_ -eq 'wall' } {
            $t = $arg.Trim(); $append = $false
            if ($name -eq 'write' -and $t.StartsWith('!')) {        # :w !cmd -- the lines to a PowerShell command
                $r = Rng $st $addrs '%'; $script:PVI_IN = Slice $bf.L ((Max2 1 $r[0]) - 1) $r[1]
                $out = @(Invoke-Expression ('$script:PVI_IN | ' + $t.Substring(1)) | ForEach-Object { "$_" })
                foreach ($o in $out) { Say $st $o }; return
            }
            if ($t.StartsWith('>>')) { $append = $true; $t = $t.Substring(2).Trim() }
            $doWrite = $true
            if (($name -eq 'xit' -or $name -eq 'exit' -or $name -eq 'update') -and -not (IsMod $bf) -and -not $t) { $doWrite = $false }
            if ($doWrite) {
                $whole = ($addrs.Count -eq 0)
                if ($whole) { $a = 1; $b = $n } else { $r = NoZero (Rng $st $addrs '.') $n; $a = $r[0]; $b = $r[1] }
                WriteBuf $st $a $b $t $bang $append $whole
            }
            if ($name -ne 'write' -and $name -ne 'update' -and $name -ne 'wall') { $st.quit = $true }
            return
        }
        'quit' {
            if (-not $bang -and (IsMod $bf)) { throw 'E37: No write since last change (add ! to override)' }
            if (-not $bang -and $st.args.Count -gt ($st.argi + 1) -and -not $st.warnedArgs) { $st.warnedArgs = $true; throw "E173: $($st.args.Count - $st.argi - 1) more file(s) to edit" }
            $st.quit = $true; return
        }
        'edit' {
            $t = $arg.Trim()
            if (-not $t) { if (-not $bf.name) { throw 'E32: No file name' }; $t = $bf.name }
            EditFile $st $t $bang
            if ($st.visual) { $st.cur = 1 }
            return
        }
        { $_ -eq 'next' -or $_ -eq 'Next' -or $_ -eq 'previous' } {
            $t = $arg.Trim()
            if ($t) { if (-not $bang -and (IsMod $bf)) { throw 'E37: No write since last change (add ! to override)' }; $st.args = @($t -split '\s+'); $st.argi = 0; EditFile $st $st.args[0] $true; return }
            $k = $st.argi + 1; if ($name -ne 'next') { $k = $st.argi - 1 }
            if ($k -ge $st.args.Count) { throw 'E165: Cannot go beyond last file' }
            if ($k -lt 0) { throw 'E164: Cannot go before first file' }
            EditFile $st $st.args[$k] $bang; $st.argi = $k; return
        }
        'args' { $i = 0; Say $st (@(foreach ($f in $st.args) { if ($i -eq $st.argi) { "[$f]" } else { $f }; $i++ }) -join ' '); return }
        'read' {
            $r = Rng $st $addrs '.'; $at = $r[1]; $t = $arg.Trim()
            if ($t.StartsWith('!')) { $new = @(Invoke-Expression $t.Substring(1) | ForEach-Object { "$_" }) }
            else {
                if (-not $t) { $t = $bf.name }
                if (-not $t) { throw 'E32: No file name' }
                $full = FullPath $t
                if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { throw "E484: Can't open file $t" }
                $rf = ReadTextFile $full; $new = @(); if (-not $rf.empty) { $new = $rf.lines }
            }
            if ($new.Count -and $bf.empty) { BufReplace $st 0 1 $new; $st.cur = 1; return }
            if ($new.Count) { BufReplace $st $at 0 $new; $st.cur = $at + 1 }
            return
        }
        '!' {
            $t = $arg
            if ($addrs.Count) {                           # :{range}!cmd -- filter the lines through a PowerShell command
                $r = NoZero (Rng $st $addrs '.') $n
                $script:PVI_IN = Slice $bf.L ($r[0] - 1) $r[1]
                $out = @(Invoke-Expression ('$script:PVI_IN | ' + $t) | ForEach-Object { "$_" })
                BufReplace $st ($r[0] - 1) ($r[1] - $r[0] + 1) $out
                $st.cur = Min2 ($r[0] - 1 + (Max2 1 $out.Count)) $st.buf.L.Count
                Say $st "$($r[1] - $r[0] + 1) lines filtered"; return
            }
            $out = @(Invoke-Expression $t *>&1 | ForEach-Object { "$_" })
            foreach ($o in $out) { Say $st $o }; return
        }
        { $_ -eq 'k' -or $_ -eq 'mark' } {
            $t = $arg.Trim(); if ($t.Length -ne 1 -or $t -cnotmatch '^[a-zA-Z]$') { throw 'E191: Argument must be a letter' }
            $r = NoZero (Rng $st $addrs '.') $n; $bf.marks[$t] = $bf.I[$r[1] - 1]; return
        }
        { $_ -eq '>' -or $_ -eq '<' } {
            if ($bf.empty) { return }
            $times = 1; $t = $arg
            while ($t.StartsWith($name)) { $times++; $t = $t.Substring(1) }
            $r = NoZero (Rng $st $addrs '.') $n; $r = CountArg $st $r $t
            $dir = 1; if ($name -eq '<') { $dir = -1 }
            $L = $bf.L + @()
            for ($k = $r[0]; $k -le $r[1]; $k++) { $x = [string]$L[$k - 1]; for ($q = 0; $q -lt $times; $q++) { $x = ShiftLine $x $dir }; $L[$k - 1] = $x }
            BufAll $st $L $bf.I; $st.cur = $r[1]; return
        }
        'sort' {
            if ($bf.empty) { return }
            $r = Rng $st $addrs '%'; $a = Max2 1 $r[0]; $b = $r[1]
            $o = $arg.Trim(); $ic = $o.Contains('i'); $num = $o.Contains('n'); $uniq = $o.Contains('u')
            $L = Slice $bf.L ($a - 1) $b; $idv = Slice $bf.I ($a - 1) $b
            $idx = @(for ($k = 0; $k -lt $L.Count; $k++) { $k })
            if ($num) {
                $with = @(); $without = @()
                foreach ($k in $idx) { if ([string]$L[$k] -match '-?\d+') { $with += $k } else { $without += $k } }
                $sortKeys = @{}; foreach ($k in $with) { $sortKeys[$k] = [double]([regex]::Match([string]$L[$k], '-?\d+').Value) }
                $sorted = MergeSort $with $sortKeys $true
                $order = $without + $sorted
            } else {
                $sortKeys = @{}; foreach ($k in $idx) { $v = [string]$L[$k]; if ($ic) { $v = $v.ToLowerInvariant() }; $sortKeys[$k] = $v }
                $order = MergeSort $idx $sortKeys $false
            }
            if ($bang) { [array]::Reverse($order) }
            if ($uniq) {
                $prev = $null; $keep = @()
                foreach ($k in $order) { $v = [string]$L[$k]; if ($ic) { $v = $v.ToLowerInvariant() }; if ($null -ne $prev -and $v -ceq $prev) { continue }; $keep += $k; $prev = $v }
                $order = $keep
            }
            $nl = @(foreach ($k in $order) { $L[$k] }); $ni = @(foreach ($k in $order) { $idv[$k] })
            BufAll $st ((Slice $bf.L 0 ($a - 1)) + $nl + (Slice $bf.L $b $n)) ((Slice $bf.I 0 ($a - 1)) + $ni + (Slice $bf.I $b $n))
            $st.cur = $a; return
        }
        'set' { ExSet $st $arg; return }
        'file' { Say $st (FileInfo $st); return }
        'nohlsearch' { return }
        'version' { Say $st 'pvi 1.0 -- a vi for the agile kit in Windows PowerShell 5.1 (Constrained Language Mode safe)'; return }
        'visual' {
            if ($st.visual) { return }
            if ($st.canVisual) { $st.goVisual = $true; return }
            throw 'E: the full-screen editor needs single keystrokes, which PowerShell refuses under Constrained Language Mode; stay in ex mode'
        }
        'help' { foreach ($tl in ($script:HELP -split "`n")) { Say $st $tl.TrimEnd() }; return }
        'verbs' { foreach ($tl in ($script:VERBS -split "`n")) { Say $st $tl.TrimEnd() }; return }
        { $_ -eq 'cnext' -or $_ -eq 'cprevious' -or $_ -eq 'cc' -or $_ -eq 'clist' -or $_ -eq 'copen' } { ExQf $st $name $arg $bang; return }
        default { Agile $st $name $arg; return }
    }
}
function ExSet($st, [string]$arg) {
    $t = $arg.Trim()
    if (-not $t -or $t -eq 'all') {
        $f = $st.buf.f; $ff = 'unix'; if ($f.eol -eq "`r`n") { $ff = 'dos' }
        Say $st ("  {0}number {1}ignorecase {2}wrapscan window={3} fileformat={4} {5}bomb {6}endofline" -f $(if ($st.opt.nu) { '' } else { 'no' }), $(if ($st.opt.ic) { '' } else { 'no' }), $(if ($st.opt.ws) { '' } else { 'no' }), $st.opt.window, $ff, $(if ($f.bom) { '' } else { 'no' }), $(if ($f.trailing) { '' } else { 'no' }))
        return
    }
    foreach ($o in ($t -split '\s+')) {
        $f = $st.buf.f
        switch -Regex -CaseSensitive ($o) {
            '^(nu|number)$' { $st.opt.nu = $true; continue }
            '^(nonu|nonumber)$' { $st.opt.nu = $false; continue }
            '^(ic|ignorecase)$' { $st.opt.ic = $true; continue }
            '^(noic|noignorecase)$' { $st.opt.ic = $false; continue }
            '^(ws|wrapscan)$' { $st.opt.ws = $true; continue }
            '^(nows|nowrapscan)$' { $st.opt.ws = $false; continue }
            '^(wi|window)=(\d+)$' { $st.opt.window = [int]$Matches[2]; continue }
            '^(ff|fileformat)=(unix|dos)$' { if ($Matches[2] -eq 'dos') { $f.eol = "`r`n" } else { $f.eol = "`n" }; Bump $st.buf; continue }
            '^bomb$' { if ($f.latin1) { throw 'E: a Latin-1 file has no byte-order mark' }; $f.bom = $true; Bump $st.buf; continue }
            '^nobomb$' { $f.bom = $false; Bump $st.buf; continue }
            '^(eol|endofline|fixeol|fixendofline)$' { $f.trailing = $true; Bump $st.buf; continue }
            '^(noeol|noendofline|nofixeol|nofixendofline)$' { $f.trailing = $false; Bump $st.buf; continue }
            '^(ff|fileformat)\??$' { if ($f.eol -eq "`r`n") { Say $st '  fileformat=dos' } else { Say $st '  fileformat=unix' }; continue }
            default { throw "E518: Unknown option: $o" }
        }
    }
}
function WriteBuf($st, [int]$a, [int]$b, [string]$fname, [bool]$bang, [bool]$append, [bool]$whole) {
    $buf = $st.buf
    $target = $fname; if (-not $target) { $target = $buf.name }
    if (-not $target) { throw 'E32: No file name' }
    $full = FullPath $target
    $same = $false; if ($buf.name) { $same = ($full -eq (FullPath $buf.name)) }
    if (-not $buf.name) { $buf.name = $target; $buf.f.path = $full; $same = $true }
    if ($same -and -not $whole -and -not $bang) { throw 'E140: Use ! to write partial buffer' }
    if (-not $same -and -not $bang -and -not $append -and (Test-Path -LiteralPath $full)) { throw 'E13: File exists (add ! to override)' }
    if ($same -and -not $bang -and $buf.mtime -and (FileTime $full) -ne $buf.mtime) { throw 'E: the file changed on disk since it was read (:w! to write anyway, :e! to reload)' }
    $lines = @(); if (-not $buf.empty -and $b -ge $a) { $lines = Slice $buf.L ($a - 1) $b }
    $bytes = WriteTextFile $buf.f $lines $full $append
    if ($same -and $whole) { $buf.saved = $buf.state; $buf.mtime = FileTime $full; $buf.f.exists = $true; $buf.f.path = $full }
    Say $st ('"{0}" {1}L, {2}B {3}' -f $target, $lines.Count, $bytes, $(if ($append) { 'appended' } else { 'written' }))
    if ($same -and $whole -and $buf.name -match '-drill\.txt$' -and (Test-Path -LiteralPath (Join-Path $script:HOME_DIR 'drill.ps1'))) { DrillGrade $st $full }
}
function DrillGo($st, [string]$re) {               # the first line matching re (the next blank answer or hook)
    $k = 0; foreach ($x in $st.buf.L) { $k++; if ([string]$x -match $re) { $st.cur = $k; $st.r = $k - 1; $st.c = ([string]$x).Length; return $true } }
    return $false
}
function DrillGrade($st, [string]$full) {          # vim/scrum.vim's BufWritePost *-drill.txt: grade, reload, go to the first blank hook
    $res = RunKit $st 'drill.ps1' @() @{ Grade = $full }
    ShowRun $st $res
    $cur = $st.cur; EditFile $st $full $true; $st.msgs = @($st.msgs | Where-Object { $_ -notmatch '^"' })
    if (-not (DrillGo $st '^hook:\s*$')) { if (-not (DrillGo $st '^>\s*$')) { $st.cur = Min2 $cur $st.buf.L.Count; $st.r = $st.cur - 1 } }
}
function ExSub($st, [string]$name, $addrs, [string]$arg) {
    $bf = $st.buf; $n = $bf.L.Count
    $rest = $arg; $flags = ''
    if ($name -eq 'substitute' -and $arg.Length -gt 0 -and [string]$arg[0] -cnotmatch '^[A-Za-z0-9 "|\\&]$') {
        $d = [string]$arg[0]
        $r1 = ReadDelim $arg 1 $d; $pat = $r1.text; $rep = ''; $rest = ''
        if ($r1.closed) { $r2 = ReadDelim $arg $r1.next $d; $rep = $r2.text; $rest = $arg.Substring($r2.next) }
        $rep = TildeRep $st $rep; $st.lastRep = $rep
    } else {
        if ($null -eq $st.lastSub) { throw 'E35: No previous regular expression' }
        $pat = $st.lastSub.pat; $rep = $st.lastSub.rep
        if ($name -eq '~') { if ($null -eq $st.lastPat) { throw 'E35: No previous regular expression' }; $pat = $st.lastPat }
        if ($rest.StartsWith('&')) { $flags = $st.lastSub.flags; $rest = $rest.Substring(1) }
    }
    $m = [regex]::Match($rest, '^\s*([&cegiInp#lr]*)\s*(\d*)\s*$')
    if (-not $m.Success) { throw "E488: Trailing characters: $rest" }
    $fl = $m.Groups[1].Value
    if ($fl.StartsWith('&')) { if ($st.lastSub) { $flags += $st.lastSub.flags }; $fl = $fl.Substring(1) }
    $flags += $fl
    if ($pat -eq '') { if ($null -eq $st.lastPat) { throw 'E35: No previous regular expression' }; $pat = $st.lastPat }
    $st.lastSub = @{ pat = $pat; rep = $rep; flags = $flags }
    if ($flags.Contains('c')) { throw 'E: the c (confirm) flag is not supported: use n to count, then :s without c' }
    $oldIc = $st.opt.ic
    if ($flags.Contains('i')) { $st.opt.ic = $true } elseif ($flags.Contains('I')) { $st.opt.ic = $false }
    try { $rx = MkRx $st $pat } finally { $st.opt.ic = $oldIc }
    $r = NoZero (Rng $st $addrs '.') $n
    if ($m.Groups[2].Value) { $r = CountArg $st $r $m.Groups[2].Value }
    $g = $flags.Contains('g'); $count = $flags.Contains('n')
    $k = $r[0] - 1; $end = $r[1] - 1; $subs = 0; $lines = 0; $last = -1
    while ($k -le $end) {
        $line = [string]$st.buf.L[$k]
        $res = SubLine $line $rx $rep $g
        if ($res.count -gt 0) {
            $subs += $res.count; $lines++
            if (-not $count) {
                $parts = $res.text -split $script:SPLIT, 0, 'SimpleMatch'
                if ($null -eq $st.ccur) { $st.ccur = $k + 1 }   # vim's do_sub: the cursor is on the line at its first change
                if ($parts.Count -eq 1) { BufSet $st $k $parts[0] }
                else { BufReplace $st $k 1 $parts; $end += $parts.Count - 1; $k += $parts.Count - 1 }
            }
            $last = $k
        }
        $k++
    }
    if ($subs -eq 0) { if (-not $flags.Contains('e') -and -not $st.inGlobal) { throw "E486: Pattern not found: $pat" }; return }
    if ($count) { Say $st "$subs match$(if ($subs -ne 1) { 'es' }) on $lines line$(if ($lines -ne 1) { 's' })"; return }
    $st.cur = $last + 1
    if ($subs -gt 2 -and -not $st.inGlobal) { Say $st "$subs substitutions on $lines line$(if ($lines -ne 1) { 's' })" }
    if ($flags.Contains('p') -or $flags.Contains('#') -or $flags.Contains('l')) { $how = 'p'; if ($flags.Contains('#')) { $how = 'nu' } elseif ($flags.Contains('l')) { $how = 'l' }; PrintLines $st $st.cur $st.cur $how }
}

# ================================================================ quickfix and the agile kit
function ProjectRoot($st) {
    $d = (Get-Location).Path
    if ($st.buf.name) { $pp = Split-Path -Parent (FullPath $st.buf.name); if ($pp) { $d = $pp } }
    $x = $d
    while ($x) {
        if (Test-Path -LiteralPath (Join-Path $x 'scrum.conf')) { return $x }
        $parent = Split-Path -Parent $x
        if (-not $parent -or $parent -eq $x) { break }
        $x = $parent
    }
    return $d
}
function RunKit($st, [string]$tool, $pos, $named) {
    if ($tool -eq 'agile.ps1' -and $st.agile) { $ps1 = $st.agile } else { $ps1 = Join-Path $script:HOME_DIR $tool }
    if (-not (Test-Path -LiteralPath $ps1 -PathType Leaf)) { return @{ rc = 2; out = @("$tool not found at $ps1 (keep it beside pvi.ps1, or start pvi with -Agile PATH)"); root = '' } }
    $root = ProjectRoot $st
    $pos = @($pos); if ($null -eq $named) { $named = @{} } else { $named = $named.Clone() }
    if ($Today) { $named['Today'] = $Today }          # pvi -Today D: the kit's -Today (as daily.pl --today)
    $global:LASTEXITCODE = 0
    Push-Location -LiteralPath $root
    try { $out = @(& $ps1 @pos @named *>&1 | ForEach-Object { "$_" }) } finally { Pop-Location }
    $rc = $global:LASTEXITCODE; if ($null -eq $rc) { $rc = 0 }
    return @{ rc = $rc; out = $out; root = $root }
}
function QfLoad($st, $res) {                        # file:line: text lines (and file: text naming a task id) -> the list
    $q = @()
    foreach ($tl in $res.out) {
        $m = [regex]::Match($tl, '^(.+?):(\d+): (.*)$')
        if ($m.Success) { $q += @{ file = (Join-Path $res.root $m.Groups[1].Value); line = [int]$m.Groups[2].Value; text = $m.Groups[3].Value }; continue }
        $m = [regex]::Match($tl, '^([^:]+\.txt): (.*)$')
        if ($m.Success -and $m.Groups[2].Value -notmatch '^NOT applied') {
            $file = Join-Path $res.root $m.Groups[1].Value; $ln = 1
            $id = [regex]::Match($m.Groups[2].Value, "'([^']+)'")
            if ($id.Success -and (Test-Path -LiteralPath $file -PathType Leaf)) {
                $k = 0; foreach ($x in (ReadTextFile $file).lines) { $k++; if ($x -match ('(^|\s)' + [regex]::Escape($id.Groups[1].Value) + '(\s|$)')) { $ln = $k; break } }
            }
            $q += @{ file = $file; line = $ln; text = $m.Groups[2].Value }
        }
    }
    $st.qf = $q; $st.qfi = -1
    return $q.Count
}
function QfJump($st, [int]$i) {
    if ($st.qf.Count -eq 0) { throw 'E42: No Errors' }
    if ($i -ge $st.qf.Count) { throw 'E553: No more items' }
    if ($i -lt 0) { throw 'E553: No more items' }
    $e = $st.qf[$i]; $st.qfi = $i
    $cur = ''; if ($st.buf.name) { $cur = FullPath $st.buf.name }
    if ($cur -ne $e.file) {
        if (IsMod $st.buf) { throw 'E37: No write since last change (add ! to override)' }
        EditFile $st $e.file $false
    }
    $ln = Min2 (Max2 1 $e.line) (Max2 1 $st.buf.L.Count)
    $st.cur = $ln; $st.r = $ln - 1; $st.c = 0
    Say $st "($($i + 1) of $($st.qf.Count)): $($e.text)"
}
function ExQf($st, [string]$name, [string]$arg, [bool]$bang) {
    switch ($name) {
        'cnext' { QfJump $st ($st.qfi + 1) }
        'cprevious' { QfJump $st ($st.qfi - 1) }
        'cc' { $k = $st.qfi; if ($arg.Trim() -cmatch '^\d+$') { $k = [int]$arg.Trim() - 1 } elseif ($k -lt 0) { $k = 0 }; QfJump $st $k }
        default {
            if ($st.qf.Count -eq 0) { Say $st 'E42: No Errors'; return }
            $i = 0; foreach ($e in $st.qf) { $i++; Say $st ("{0,2} {1}:{2}: {3}" -f $i, $e.file, $e.line, $e.text) }
        }
    }
}
function SaveIfModified($st) { if ((IsMod $st.buf) -and $st.buf.name) { WriteBuf $st 1 $st.buf.L.Count '' $false $false $true } }
function ShowRun($st, $res) { foreach ($tl in $res.out) { Say $st $tl }; if ($res.rc -ne 0) { $st.errors++ } }
function ReloadIfChanged($st) {                     # the kit rewrote the file pvi has open (compile writes scrum.txt)
    $b = $st.buf
    if ($b.name -and -not (IsMod $b) -and $b.mtime -and (FileTime (FullPath $b.name)) -ne $b.mtime) {
        $cur = $st.cur; $r = $st.r; EditFile $st $b.name $true
        $st.cur = Min2 $cur $st.buf.L.Count; $st.r = Min2 $r (Max2 0 ($st.buf.L.Count - 1))
        Say $st '(reloaded: the kit changed the file)'
    }
}
function Agile($st, [string]$name, [string]$arg) {
    $words = @(); if ($arg.Trim()) { $words = @($arg.Trim() -split '\s+') }
    $simple = @{ SStatus = 'status'; SCompile = 'compile'; SReport = 'report'; SAnswers = 'answers'; SSprint = 'sprint'; SBacklog = 'backlog'
        SMembers = 'members'; SBlocked = 'blocked'; SRoadmap = 'roadmap'; SVelocity = 'velocity'; SEpics = 'epics'; SPropose = 'propose' }
    if ($name -ne 'S' -and $simple.ContainsKey($name)) {
        if ((IsMod $st.buf) -and $st.buf.name) { Say $st '(this buffer has unsaved changes: :w first if the kit should see them)' }
        $res = RunKit $st 'agile.ps1' (@($simple[$name]) + $words) $null; ShowRun $st $res; ReloadIfChanged $st; return
    }
    switch -CaseSensitive ($name) {
        'S' {
            if (-not $words.Count) { throw 'E471: Argument required (:S status, :S sprint 3, ...)' }
            $pos = @(); $named = @{}
            foreach ($w in $words) { if ($w -cmatch '^-([A-Za-z]+)$') { $named[$Matches[1]] = $true } else { $pos += $w } }
            $res = RunKit $st 'agile.ps1' $pos $named; ShowRun $st $res; ReloadIfChanged $st; return
        }
        'SDry' { $res = RunKit $st 'agile.ps1' @('compile') @{ Dry = $true }; ShowRun $st $res; [void](QfLoad $st $res); return }
        { $_ -eq 'check' -or $_ -eq 'SCheck' } {
            SaveIfModified $st
            $res = RunKit $st 'agile.ps1' @('compile') @{ Dry = $true }
            $k = QfLoad $st $res
            if ($k -gt 0) { Say $st "check: $k problem$(if ($k -ne 1) { 's' }) (:cn next, :cp previous, :cl list)"; QfJump $st 0 }
            else { ShowRun $st $res; Say $st 'check: no problems found (compile -Dry)' }
            return
        }
        'SNew' {
            $res = RunKit $st 'agile.ps1' (@('new') + $words) $null
            if ($res.rc -ne 0 -or $res.out.Count -lt 1) { ShowRun $st $res; return }
            $path = $res.out[$res.out.Count - 1]
            EditFile $st (Join-Path $res.root $path) $false
            $st.cur = $st.buf.L.Count; $st.r = Max2 0 ($st.buf.L.Count - 1)
            Say $st $res.out[0]; return
        }
        'SJournal' {
            $root = ProjectRoot $st; $j = 'scrum.txt'; $conf = Join-Path $root 'scrum.conf'
            if (Test-Path -LiteralPath $conf) { foreach ($tl in (ReadTextFile $conf).lines) { $m = [regex]::Match($tl, '^\s*journal\s*=\s*([^#\s]+)'); if ($m.Success) { $j = $m.Groups[1].Value } } }
            EditFile $st (Join-Path $root $j) $false
            $st.cur = $st.buf.L.Count; $st.r = Max2 0 ($st.buf.L.Count - 1); return
        }
        { $_ -eq 'SLint' -or $_ -eq 'SLintReply' } {
            SaveIfModified $st
            $file = @(); if ($words.Count) { $file = @($words[0]) } elseif ($st.buf.name -match '-chat\.txt$') { $file = @(FullPath $st.buf.name) }
            $named = $null; if ($name -eq 'SLintReply') { $named = @{ Reply = $true } }
            $res = RunKit $st 'agile.ps1' (@('lint') + $file) $named
            ShowRun $st $res
            if ($name -eq 'SLint') { $k = QfLoad $st $res; if ($k) { Say $st "$k status line$(if ($k -ne 1) { 's' }) to fix (:cn jumps to the first)" } }
            return
        }
        'SQuad' { $res = RunKit $st 'agile-more.ps1' (@('quad') + $words) $null; ShowRun $st $res; return }
        'SDrill' {                                      # the memory drill: a sheet of due cards; :w grades it (drill.ps1 -Grade)
            $res = RunKit $st 'drill.ps1' $words @{ Sheet = $true }
            $last = ''; if ($res.out.Count) { $last = [string]$res.out[$res.out.Count - 1] }
            if ($res.rc -ne 0 -or $last -notmatch '-drill\.txt$') { ShowRun $st $res; return }
            EditFile $st $last $false
            if (-not (DrillGo $st '^>\s*$')) { $st.cur = 1; $st.r = 0 }
            Say $st 'drill: type after each ">", then :w grades the sheet (:wq to grade and leave)'
            return
        }
        'SHealth' { $res = RunKit $st 'agile-more.ps1' (@('health') + $words) $null; ShowRun $st $res; return }
    }
    throw "E492: Not an editor command: $name"
}

$script:VERBS = @'
Stand-up file verbs (under '== Team'; :check tests the file, :SCompile applies it)
  done ID...            Committed -> Done in this sprint
  carry ID...           Committed -> Carryover: not finished
  drop ID...            Committed -> Removed: out of the sprint and out of scope
  commit ID [OWNER]     into this sprint's commitment (from a backlog or last sprint's carryover)
  new ID PTS TITLE [p:N] [e:EPIC] [t:TOME] [o:OWNER]   intake into the team's backlog
  new! ID PTS TITLE ... straight into this sprint, tagged interrupt
  refine ID             from the master (or another team's) backlog into this team's
  prune ID REASON       retire a backlog task
  est ID PTS            re-estimate
  assign ID OWNER       change the owner
  block ID REASON / unblock ID       blocked, with the reason (escalate after 3 days)
  hold ID REASON / resume ID         interrupted by higher-priority work
  punt ID REASON        too hard as written: back to the team's backlog
  redo ID REASON        found wrong after the demo: last sprint's Done -> Committed
  pass ID TEAM          another team should do it
  sync ID ID...         done together: none counts until all are done
  cap N                 the team's capacity this sprint
  note TEXT / risk TEXT / absent NAME...   report-only lines
  sprint N              the sprint this file (or section) belongs to
'@
$script:HELP = @'
pvi -- ex commands ([range] is N, ., $, +N, -N, /re/, ?re?, 'm, %, a,b; most default to the current line)
  [range]p  nu  #  l  [count]   print (with numbers)         z[+-.^=][count]  a window of lines
  [line]a  [line]i  [range]c    input lines, end with a line holding only "."
  [range]d [x] [count]          delete (into register x)     [range]y [x]   yank       [line]pu[!] [x]  put
  [range]m ADDR  [range]t ADDR  move / copy after ADDR (0 = top)
  [range]j[!] [count]           join (! without spaces)      [range]> / <   shift right / left
  [range]s/re/rep/[gciIen] [count]   substitute: & \0 \1..\9 \r (new line) \t \u \l \U \L \E in rep; & repeats
  [range]g/re/cmd  v/re/cmd     run cmd on the lines that match (v: that do not)
  [range]sort[!] [i] [n] [u]    sort lines (! reverse, i ignore case, n numeric, u unique)
  u  red                        undo, redo
  w [file]  w! file  w >> file  [range]w !cmd   write;  wq  x  q  q!  e[!] file  r file  r !cmd
  n  N  args                    next / previous file of the argument list
  [range]!cmd  !cmd             filter lines through a PowerShell command / run one
  k x  'x                       mark a line / address it      =  the line number
  set nu|nonu ic|noic ws|nows window=N ff=unix|dos bomb|nobomb eol|noeol
  vi                            the full-screen editor (needs FullLanguage: not available under CLM)
Agile kit (agile.ps1 beside pvi.ps1, run in the folder holding scrum.conf)
  SNew [Team...]  today's stand-up file, opened at the end   SJournal  the journal, at the end
  check  compile -Dry; problems into a list: cn cp cc [N] cl SCompile  apply the stand-up files
  SDry SStatus SReport SAnswers SSprint [N] SBacklog [Team] SMembers [Team] SBlocked SRoadmap SVelocity SEpics
  SPropose [Team]  SLint [file]  SLintReply  SQuad  SHealth  S ARGS (any agile command)   verbs  the stand-up verbs
  SDrill [Team]   the memory drill sheet (drill.ps1): answer after each '>', :w grades it
'@

# ================================================================ full-screen vi: a pure function of (state, key)
function NL($st) { return $st.buf.L.Count }
function VLine($st, [int]$r) { if ($r -ge 0 -and $r -lt $st.buf.L.Count) { return [string]$st.buf.L[$r] }; return '' }
function VSetLine($st, [int]$r, [string]$t) { BufSet $st $r $t }
function EnsureLine($st) { }
function VClamp($st) {
    $n = NL $st
    if ($st.r -ge $n) { $st.r = $n - 1 }; if ($st.r -lt 0) { $st.r = 0 }
    $len = (VLine $st $st.r).Length
    if ($st.mode -eq 'i') { if ($st.c -gt $len) { $st.c = $len } } elseif ($st.c -ge $len) { $st.c = Max2 0 ($len - 1) }
    if ($st.c -lt 0) { $st.c = 0 }
}
function VScroll($st) {
    if ($st.r -lt $st.top) { $st.top = $st.r }
    if ($st.r -ge $st.top + $st.H) { $st.top = $st.r - $st.H + 1 }
    if ($st.top -lt 0) { $st.top = 0 }
}
function WCls($st, $pos, [bool]$big) {
    $line = VLine $st $pos.r
    if ($pos.c -ge $line.Length) { return 0 }
    $ch = [string]$line[$pos.c]
    if ($ch -eq ' ' -or $ch -eq "`t" -or [int][char]$ch -eq 0xA0) { return 0 }
    if ($big) { return 1 }
    if ($ch -cmatch '^[A-Za-z0-9_]$' -or ([int][char]$ch -ge 0xC0 -and [int][char]$ch -le 0xFF) -or ([int][char]$ch -gt 0xFF -and $ch -cmatch '^[\p{L}\p{Nd}]$')) { return 2 }
    return 1
}
function PInc($st, $pos) {                          # vim's inc(): 0 within the line, 2 onto the end of the line, 1 next line, -1 end
    $line = VLine $st $pos.r
    if ($pos.c -lt $line.Length) { $pos.c++; if ($pos.c -lt $line.Length) { return 0 }; return 2 }
    if ($pos.r -lt (NL $st) - 1) { $pos.r++; $pos.c = 0; return 1 }
    return -1
}
function PDec($st, $pos) {                          # vim's dec(): the end of the previous line is its NUL position
    if ($pos.c -gt 0) { $line = VLine $st $pos.r; if ($pos.c -gt $line.Length) { $pos.c = $line.Length }; $pos.c--; return 0 }
    if ($pos.r -gt 0) { $pos.r--; $pos.c = (VLine $st $pos.r).Length; return 1 }
    return -1
}
function SkipChars($st, $pos, [int]$cls, [bool]$fwd, [bool]$big) {
    while ((WCls $st $pos $big) -eq $cls) { if ($fwd) { $x = PInc $st $pos } else { $x = PDec $st $pos }; if ($x -eq -1) { return $true } }
    return $false
}
function FwdWord($st, $pos, [int]$count, [bool]$big, [bool]$eol) {
    while ($count -gt 0) {
        $count--
        $sclass = WCls $st $pos $big
        $lastLine = ($pos.r -eq (NL $st) - 1)
        $i = PInc $st $pos
        if ($i -eq -1 -or ($i -ge 1 -and $lastLine)) { return $false }
        if ($i -ge 1 -and $eol -and $count -eq 0) { return $true }
        if ($sclass -ne 0) {
            while ((WCls $st $pos $big) -eq $sclass) { $i = PInc $st $pos; if ($i -eq -1 -or ($i -ge 1 -and $eol -and $count -eq 0)) { return $true } }
        }
        while ((WCls $st $pos $big) -eq 0) {
            if ($pos.c -eq 0 -and (VLine $st $pos.r).Length -eq 0) { break }
            $i = PInc $st $pos; if ($i -eq -1 -or ($i -ge 1 -and $eol -and $count -eq 0)) { return $true }
        }
    }
    return $true
}
function EndWord($st, $pos, [int]$count, [bool]$big, [bool]$stop, [bool]$empty) {
    while ($count -gt 0) {
        $count--
        $sclass = WCls $st $pos $big
        if ((PInc $st $pos) -eq -1) { return $false }
        $fin = $false
        if ((WCls $st $pos $big) -eq $sclass -and $sclass -ne 0) { if (SkipChars $st $pos $sclass $true $big) { return $false } }
        elseif (-not $stop -or $sclass -eq 0) {
            while ((WCls $st $pos $big) -eq 0) {
                if ($pos.c -eq 0 -and (VLine $st $pos.r).Length -eq 0 -and $empty) { $fin = $true; break }
                if ((PInc $st $pos) -eq -1) { return $false }
            }
            if (-not $fin) { if (SkipChars $st $pos (WCls $st $pos $big) $true $big) { return $false } }
        }
        if (-not $fin) { [void](PDec $st $pos) }
        $stop = $false
    }
    return $true
}
function BckWord($st, $pos, [int]$count, [bool]$big, [bool]$stop) {
    while ($count -gt 0) {
        $count--
        $sclass = WCls $st $pos $big
        if ((PDec $st $pos) -eq -1) { return $false }
        $fin = $false
        if (-not $stop -or $sclass -eq (WCls $st $pos $big) -or $sclass -eq 0) {
            while ((WCls $st $pos $big) -eq 0) {
                if ($pos.c -eq 0 -and (VLine $st $pos.r).Length -eq 0) { $fin = $true; break }
                if ((PDec $st $pos) -eq -1) { return $true }
            }
            if (-not $fin) { if (SkipChars $st $pos (WCls $st $pos $big) $false $big) { return $true } }
        }
        if (-not $fin) { [void](PInc $st $pos) }
        $stop = $false
    }
    return $true
}
function FindChar($st, [string]$cmd, [string]$ch, [int]$count, [bool]$repeat) {
    $line = VLine $st $st.r; $c = $st.c; $fwd = ($cmd -ceq 'f' -or $cmd -ceq 't')
    $k = $c
    for ($n = 0; $n -lt $count; $n++) {
        while ($true) {
            if ($fwd) { $k++ } else { $k-- }
            if ($k -lt 0 -or $k -ge $line.Length) { return -1 }
            if ([string]$line[$k] -ceq $ch) {
                if ($repeat -and $n -eq 0 -and (($cmd -ceq 't' -and $k -eq $c + 1) -or ($cmd -ceq 'T' -and $k -eq $c - 1))) { continue }
                break
            }
        }
    }
    if ($cmd -ceq 't') { return $k - 1 }
    if ($cmd -ceq 'T') { return $k + 1 }
    return $k
}
function FindMatch($st, $rx, [bool]$fwd, [int]$r, [int]$c) {
    $n = NL $st
    for ($step = 0; $step -le $n; $step++) {
        if ($fwd) { $ln = $r + $step } else { $ln = $r - $step }
        $wrapped = $false
        if ($ln -ge $n) { $ln -= $n; $wrapped = $true } elseif ($ln -lt 0) { $ln += $n; $wrapped = $true }
        if ($wrapped -and -not $st.opt.ws) { return $null }
        $ms = @($rx.Matches((VLine $st $ln)))
        if ($fwd) {
            foreach ($m in $ms) {
                if ($step -eq 0 -and $m.Index -le $c) { continue }
                if ($step -eq $n -and $m.Index -gt $c) { continue }
                return @{ r = $ln; c = $m.Index; wrapped = $wrapped }
            }
        } else {
            for ($q = $ms.Count - 1; $q -ge 0; $q--) {
                $m = $ms[$q]
                if ($step -eq 0 -and $m.Index -ge $c) { continue }
                if ($step -eq $n -and $m.Index -lt $c) { continue }
                return @{ r = $ln; c = $m.Index; wrapped = $wrapped }
            }
        }
    }
    return $null
}
function VSearch($st, [string]$pat, [int]$dir, [bool]$move) {
    $rx = MkRx $st $pat
    $hit = FindMatch $st $rx ($dir -gt 0) $st.r $st.c
    if ($null -eq $hit) { throw "E486: Pattern not found: $($st.lastPat)" }
    if ($hit.wrapped) { if ($dir -gt 0) { $st.msg = 'search hit BOTTOM, continuing at TOP' } else { $st.msg = 'search hit TOP, continuing at BOTTOM' } }
    if ($move) { $st.r = $hit.r; $st.c = $hit.c; SetWant $st }
    return $hit
}
$script:MOTIONS = @('h', 'l', 'j', 'k', '0', '^', '$', '|', 'w', 'W', 'b', 'B', 'e', 'E', 'f', 'F', 't', 'T', ';', ',', 'G', 'gg', 'H', 'M', 'L',
    'n', 'N', '_', '+', '-', '<CR>', '<Left>', '<Right>', '<Up>', '<Down>', '<Home>', '<End>', '<BS>', ' ', '<C-n>', '<C-p>', '<C-h>', '<C-j>', '<C-m>')
$script:VCHANGE = @('x', 'X', 'D', 'C', 's', 'S', 'p', 'P', 'J', 'gJ', 'r', '~', 'i', 'a', 'I', 'A', 'o', 'O', '&', '<Del>')
function VMotion($st, [string]$m, [string]$ch, [int]$cnt, [string]$op) {
    $c1 = $cnt; if ($c1 -lt 1) { $c1 = 1 }
    $r = $st.r; $c = $st.c; $len = (VLine $st $r).Length; $nl = NL $st
    $res = @{ ok = $true; r = $r; c = $c; lw = $false; inc = $false; vert = $false; fnb = $false; want = $null; bell = $false }
    if ($m -ceq 'h' -or $m -eq '<Left>' -or $m -eq '<BS>' -or $m -eq '<C-h>') { if ($c -le 0) { $res.ok = $false } else { $res.c = Max2 0 ($c - $c1) } }
    elseif ($m -ceq 'l' -or $m -eq '<Right>' -or $m -eq ' ') {
        $lim = $len - 1; if ($op) { $lim = $len }
        if ($c -ge $lim) { $res.ok = $false } else { $res.c = Min2 $lim ($c + $c1) }
    }
    elseif ($m -eq '0' -or $m -eq '<Home>') { $res.c = 0 }
    elseif ($m -eq '^') { $res.c = FirstNonBlank (VLine $st $r) }
    elseif ($m -eq '$' -or $m -eq '<End>') {
        $r2 = $r + $c1 - 1; if ($r2 -ge $nl) { $res.ok = $false } else { $res.r = $r2; $res.c = Max2 0 ((VLine $st $r2).Length - 1); $res.inc = $true; $res.want = -1 }
    }
    elseif ($m -eq '|') { $res.c = Min2 ($c1 - 1) (Max2 0 ($len - 1)) }
    elseif ($m -ceq 'w' -or $m -ceq 'W' -or $m -ceq 'e' -or $m -ceq 'E') {
        $big = ($m -ceq 'W' -or $m -ceq 'E'); $wordEnd = ($m -ceq 'e' -or $m -ceq 'E'); $res.inc = $wordEnd; $flag = $false
        if (-not $wordEnd -and $op -eq 'c') {
            $line = VLine $st $r
            if ($c -lt $line.Length) { $chr = [string]$line[$c]; if ($chr -ne ' ' -and $chr -ne "`t") { $res.inc = $true; $wordEnd = $true; $flag = $true } }
        }
        $pos = @{ r = $r; c = $c }
        if ($wordEnd) { $ok = EndWord $st $pos $c1 $big $flag $false } else { $ok = FwdWord $st $pos $c1 $big ([bool]$op) }
        if ($pos.r -gt $r -or ($pos.r -eq $r -and $pos.c -gt $c)) {
            if ($pos.c -gt 0 -and $pos.c -ge (VLine $st $pos.r).Length) { $pos.c--; $res.inc = $true }   # vim's adjust_cursor
        }
        $res.r = $pos.r; $res.c = $pos.c
        if (-not $ok -and -not $op) { $res.bell = $true }
    }
    elseif ($m -ceq 'b' -or $m -ceq 'B') { $pos = @{ r = $r; c = $c }; if (BckWord $st $pos $c1 ($m -ceq 'B') $false) { $res.r = $pos.r; $res.c = $pos.c } else { $res.ok = $false } }
    elseif ($m -ceq 'f' -or $m -ceq 'F' -or $m -ceq 't' -or $m -ceq 'T' -or $m -eq ';' -or $m -eq ',') {
        $cmd = $m; $x = $ch; $rep = $false
        if ($m -eq ';' -or $m -eq ',') {
            if ($null -eq $st.lastFt) { $res.ok = $false; return $res }
            $cmd = $st.lastFt.cmd; $x = $st.lastFt.ch; $rep = $true
            if ($m -eq ',') { if ($cmd -ceq 'f') { $cmd = 'F' } elseif ($cmd -ceq 'F') { $cmd = 'f' } elseif ($cmd -ceq 't') { $cmd = 'T' } else { $cmd = 't' } }
        } else { $st.lastFt = @{ cmd = $m; ch = $ch } }
        if ($x -eq '<Tab>') { $x = "`t" }
        $k = FindChar $st $cmd $x $c1 $rep
        if ($k -lt 0) { $res.ok = $false } else { $res.c = $k; $res.inc = ($cmd -ceq 'f' -or $cmd -ceq 't') }
    }
    elseif ($m -ceq 'j' -or $m -eq '<Down>' -or $m -eq '<C-n>' -or $m -eq '<C-j>') {
        if ($r -ge $nl - 1) { $res.ok = $false } else { $res.r = Min2 ($nl - 1) ($r + $c1); $res.lw = $true; $res.vert = $true }
    }
    elseif ($m -eq '+' -or $m -eq '<CR>' -or $m -eq '<C-m>') {
        if ($r -ge $nl - 1) { $res.ok = $false } else { $res.r = Min2 ($nl - 1) ($r + $c1); $res.lw = $true; $res.fnb = $true }
    }
    elseif ($m -ceq 'k' -or $m -eq '<Up>' -or $m -eq '<C-p>') {
        if ($r -le 0) { $res.ok = $false } else { $res.r = Max2 0 ($r - $c1); $res.lw = $true; $res.vert = $true }
    }
    elseif ($m -eq '-') { if ($r -le 0) { $res.ok = $false } else { $res.r = Max2 0 ($r - $c1); $res.lw = $true; $res.fnb = $true } }
    elseif ($m -eq '_') { $r2 = $r + $c1 - 1; if ($r2 -ge $nl) { $res.ok = $false } else { $res.r = $r2; $res.lw = $true; $res.fnb = $true } }
    elseif ($m -ceq 'G') { if ($cnt -gt 0) { $res.r = (Min2 $cnt $nl) - 1 } else { $res.r = $nl - 1 }; $res.lw = $true; $res.fnb = $true }
    elseif ($m -ceq 'gg') { if ($cnt -gt 0) { $res.r = (Min2 $cnt $nl) - 1 } else { $res.r = 0 }; $res.lw = $true; $res.fnb = $true }
    elseif ($m -ceq 'H' -or $m -ceq 'M' -or $m -ceq 'L') {
        $bot = Min2 ($st.top + $st.H - 1) ($nl - 1)
        if ($m -ceq 'H') { $res.r = Min2 ($st.top + $c1 - 1) $bot } elseif ($m -ceq 'L') { $res.r = Max2 $st.top ($bot - $c1 + 1) }
        else { $res.r = $st.top + (($bot - $st.top) - (($bot - $st.top) % 2)) / 2 }
        $res.lw = $true; $res.fnb = $true
    }
    elseif ($m -ceq 'n' -or $m -ceq 'N') {
        if ($null -eq $st.lastPat) { throw 'E35: No previous regular expression' }
        $dir = $st.lastDir; if ($m -ceq 'N') { $dir = -$dir }
        $save = @{ r = $st.r; c = $st.c }
        $hit = $null
        for ($q = 0; $q -lt $c1; $q++) { $hit = VSearch $st '' $dir $true }
        $st.r = $save.r; $st.c = $save.c
        $res.r = $hit.r; $res.c = $hit.c
    }
    else { $res.ok = $false }
    if ($res.ok) {
        if ($res.vert) {
            $l2 = VLine $st $res.r; $w = $st.want; if ($w -eq -2) { $w = DispCol (VLine $st $st.r) $st.c; $st.want = $w }
            if ($w -eq -1) { $res.c = Max2 0 ($l2.Length - 1) } else { $res.c = ColFor $l2 $w }
        }
        elseif ($res.fnb) { $res.c = FirstNonBlank (VLine $st $res.r) }
    }
    return $res
}
function VExtract($st, [int]$r1, [int]$c1, [int]$r2, [int]$e) {
    if ($r1 -eq $r2) { $tl = VLine $st $r1; $e = Min2 $e $tl.Length; if ($e -le $c1) { return ,@('') }; return ,@($tl.Substring($c1, $e - $c1)) }
    $a = VLine $st $r1; $z = VLine $st $r2; $e = Min2 $e $z.Length
    $mid = @(); for ($k = $r1 + 1; $k -lt $r2; $k++) { $mid += VLine $st $k }
    return ,(@($a.Substring((Min2 $c1 $a.Length))) + $mid + @($z.Substring(0, $e)))
}
function VApplyOp($st, [string]$op, $mres, [int]$cnt, [bool]$doubled) {
    $c1 = $cnt; if ($c1 -lt 1) { $c1 = 1 }
    if ($st.buf.empty -and $op -ne 'y') {            # vim: nothing to delete in an empty buffer (no register either)
        if ($op -eq 'c') { $st.r = 0; $st.c = 0; VStartInsert $st 'c' 1 }
        return
    }
    $nl = NL $st
    if ($doubled) {
        if ($c1 -gt 1 -and $st.r -ge $nl - 1) { $st.bell = $true; return }
        $r1 = $st.r; $r2 = Min2 ($st.r + $c1 - 1) ($nl - 1); $lw = $true; $cc1 = 0; $cc2 = 0; $inc = $false
    } else {
        $lw = $mres.lw; $inc = $mres.inc
        if ($mres.r -lt $st.r -or ($mres.r -eq $st.r -and $mres.c -lt $st.c)) { $r1 = $mres.r; $cc1 = $mres.c; $r2 = $st.r; $cc2 = $st.c } else { $r1 = $st.r; $cc1 = $st.c; $r2 = $mres.r; $cc2 = $mres.c }
        if (-not $lw -and -not $inc -and $cc2 -eq 0 -and $r2 -gt $r1) {     # exclusive motion ending in column 0: vim's o_end_adjust
            $r2--; $cc2 = (VLine $st $r2).Length; $inc = $false
            if ($cc1 -le (FirstNonBlank (VLine $st $r1))) { $lw = $true }
        }
    }
    if ($lw) {
        $lines = Slice $st.buf.L $r1 ($r2 + 1)
        switch ($op) {
            'y' { SetReg $st $st.regName $lines $true; $st.r = $r1; if ($r2 - $r1 + 1 -ge 3) { $st.msg = "$($r2 - $r1 + 1) lines yanked" } }
            'd' {
                SetReg $st $st.regName $lines $true
                BufReplace $st $r1 ($r2 - $r1 + 1) @()
                $st.r = Min2 $r1 ((NL $st) - 1); $st.c = FirstNonBlank (VLine $st $st.r)
                if ($r2 - $r1 + 1 -ge 3) { $st.msg = "$($r2 - $r1 + 1) fewer lines" }
            }
            'c' {
                SetReg $st $st.regName $lines $true
                BufReplace $st $r1 ($r2 - $r1 + 1) @('')
                $st.r = $r1; $st.c = 0; VStartInsert $st 'c' 1
            }
            { $_ -eq '>' -or $_ -eq '<' } {
                $dir = 1; if ($op -eq '<') { $dir = -1 }
                if (-not $st.buf.empty) { $L = $st.buf.L + @(); for ($k = $r1; $k -le $r2; $k++) { $L[$k] = ShiftLine ([string]$L[$k]) $dir }; BufAll $st $L $st.buf.I }
                $st.r = $r1; $st.c = FirstNonBlank (VLine $st $r1)
            }
        }
        return
    }
    $e = $cc2; if ($inc) { $e = $cc2 + 1 }
    if ($op -eq 'd' -and $r2 -gt $r1 -and $e -ge (VLine $st $r2).Length -and $cc1 -le (FirstNonBlank (VLine $st $r1))) {   # whole lines after all
        $mres2 = @{ r = $r2; c = 0; lw = $true; inc = $false }; $save = $st.r; $st.r = $r1
        VApplyOp $st 'd' $mres2 1 $false; return
    }
    $text = VExtract $st $r1 $cc1 $r2 $e
    switch ($op) {
        'y' { SetReg $st $st.regName $text $false; $st.r = $r1; $st.c = $cc1 }
        { $_ -eq 'd' -or $_ -eq 'c' } {
            SetReg $st $st.regName $text $false
            $a = VLine $st $r1; $z = VLine $st $r2
            $new = $a.Substring(0, (Min2 $cc1 $a.Length)) + $z.Substring((Min2 $e $z.Length))
            if ($r1 -eq $r2) { if ($new -cne $a) { VSetLine $st $r1 $new } } else { BufReplace $st $r1 ($r2 - $r1 + 1) @($new) }
            $st.r = $r1; $st.c = $cc1
            if ($op -eq 'c') { VStartInsert $st 'c' 1 }
        }
        { $_ -eq '>' -or $_ -eq '<' } { $m2 = @{ r = $r2; c = 0; lw = $true; inc = $false }; $st.r = $r1; VApplyOp $st $op $m2 1 $false }
    }
}
function VStartInsert($st, [string]$how, [int]$count) {
    $line = VLine $st $st.r
    switch -CaseSensitive ($how) {
        'a' { if ($line.Length) { $st.c = $st.c + 1 } }
        'A' { $st.c = $line.Length }
        'I' { $st.c = FirstNonBlank $line }
        'o' { EnsureLine $st; BufReplace $st ($st.r + 1) 0 @(''); $st.r++; $st.c = 0 }
        'O' { EnsureLine $st; BufReplace $st $st.r 0 @(''); $st.c = 0 }
    }
    $st.mode = 'i'; $st.ins = @{ how = $how; count = $count; text = ''; dirty = $false }
}
function InsertText($st, [string]$text) {
    $parts = $text -split "`n", 0, 'SimpleMatch'
    $line = VLine $st $st.r; $c = Min2 $st.c $line.Length
    $head = $line.Substring(0, $c); $tail = $line.Substring($c)
    if ($parts.Count -eq 1) { VSetLine $st $st.r ($head + $parts[0] + $tail); $st.c = $c + $parts[0].Length; return }
    $new = @($head + $parts[0]) + (Slice $parts 1 ($parts.Count - 1)) + @($parts[$parts.Count - 1] + $tail)
    BufReplace $st $st.r 1 $new
    $st.r = $st.r + $parts.Count - 1; $st.c = $parts[$parts.Count - 1].Length
}
function VFinishChange($st) { if ($null -ne $st.vsnap) { if ($st.buf.state -ne $st.vsnap.state) { PushUndo $st $st.vsnap }; $st.vsnap = $null } }
function VInsertKey($st, [string]$k) {
    if ($st.recIns -and -not $st.replaying) { $st.last.keys += $k }
    $in = $st.ins
    if ($k -eq '<Esc>' -or $k -eq '<C-c>') {
        if ($in.count -gt 1 -and -not $in.dirty -and $in.text.Length) {
            for ($t = 1; $t -lt $in.count; $t++) {
                if ($in.how -ceq 'o' -or $in.how -ceq 'O') { BufReplace $st ($st.r + 1) 0 @(''); $st.r++; $st.c = 0 }
                InsertText $st $in.text
            }
        }
        if ($st.c -gt 0) { $st.c-- }
        $st.mode = 'n'; SetWant $st; $st.recIns = $false
        VFinishChange $st; return
    }
    switch -CaseSensitive ($k) {
        '<CR>' { InsertText $st "`n"; $in.text += "`n"; return }
        '<Tab>' { InsertText $st "`t"; $in.text += "`t"; return }
        { $_ -eq '<BS>' -or $_ -eq '<C-h>' } {
            $in.dirty = $true
            if ($st.c -gt 0) { $tl = VLine $st $st.r; VSetLine $st $st.r ($tl.Substring(0, $st.c - 1) + $tl.Substring($st.c)); $st.c-- }
            elseif ($st.r -gt 0) { $p = VLine $st ($st.r - 1); $tl = VLine $st $st.r; BufReplace $st ($st.r - 1) 2 @($p + $tl); $st.r--; $st.c = $p.Length }
            return
        }
        '<Del>' {
            $in.dirty = $true; $tl = VLine $st $st.r
            if ($st.c -lt $tl.Length) { VSetLine $st $st.r ($tl.Substring(0, $st.c) + $tl.Substring($st.c + 1)) }
            elseif ($st.r -lt $st.buf.L.Count - 1) { BufReplace $st $st.r 2 @($tl + (VLine $st ($st.r + 1))) }
            return
        }
        '<C-w>' {
            $in.dirty = $true; $tl = VLine $st $st.r; $h = $tl.Substring(0, $st.c)
            $m = [regex]::Match($h, '([A-Za-z0-9_]+|[^A-Za-z0-9_\s]+)?\s*$'); $nc = $st.c - $m.Length
            VSetLine $st $st.r ($tl.Substring(0, $nc) + $tl.Substring($st.c)); $st.c = $nc; return
        }
        '<C-u>' { $in.dirty = $true; $tl = VLine $st $st.r; VSetLine $st $st.r $tl.Substring($st.c); $st.c = 0; return }
        '<Left>' { $in.dirty = $true; if ($st.c -gt 0) { $st.c-- }; return }
        '<Right>' { $in.dirty = $true; if ($st.c -lt (VLine $st $st.r).Length) { $st.c++ }; return }
        '<Up>' { $in.dirty = $true; if ($st.r -gt 0) { $st.r--; $st.c = Min2 $st.c (VLine $st $st.r).Length }; return }
        '<Down>' { $in.dirty = $true; if ($st.r -lt (NL $st) - 1) { $st.r++; $st.c = Min2 $st.c (VLine $st $st.r).Length }; return }
        '<Home>' { $in.dirty = $true; $st.c = 0; return }
        '<End>' { $in.dirty = $true; $st.c = (VLine $st $st.r).Length; return }
    }
    if ($k.Length -eq 1) { InsertText $st $k; $in.text += $k }
}
function VParse($t) {
    $i = 0; $n = $t.Count; $cnt = ''
    while ($i -lt $n -and (IsDigit $t[$i]) -and -not ($t[$i] -eq '0' -and $cnt -eq '')) { $cnt += $t[$i]; $i++ }
    $res = @{ state = 'done'; count = 0; at = $i; cmd = ''; op = ''; motion = ''; ch = ''; count2 = 0; doubled = $false }
    if ($cnt) { $res.count = [int]$cnt }
    if ($i -ge $n) { $res.state = 'more'; return $res }
    $k = $t[$i]; $i++
    if ($k -eq '<Esc>') { $res.state = 'bad'; return $res }
    if ($k -ceq 'g' -or $k -ceq 'Z') { if ($i -ge $n) { $res.state = 'more'; return $res }; $k = $k + $t[$i]; $i++ }
    $res.cmd = $k
    if ($k -ceq 'r' -or $k -ceq 'f' -or $k -ceq 'F' -or $k -ceq 't' -or $k -ceq 'T' -or $k -ceq 'm') {
        if ($i -ge $n) { $res.state = 'more'; return $res }
        $res.ch = $t[$i]; if ($res.ch -eq '<Esc>') { $res.state = 'bad' }; return $res
    }
    if ($k -ceq 'd' -or $k -ceq 'c' -or $k -ceq 'y' -or $k -eq '>' -or $k -eq '<') {
        $res.op = $k; $c2 = ''
        while ($i -lt $n -and (IsDigit $t[$i]) -and -not ($t[$i] -eq '0' -and $c2 -eq '')) { $c2 += $t[$i]; $i++ }
        if ($c2) { $res.count2 = [int]$c2 }
        if ($i -ge $n) { $res.state = 'more'; return $res }
        $mk = $t[$i]; $i++
        if ($mk -eq '<Esc>') { $res.state = 'bad'; return $res }
        if ($mk -ceq $k) { $res.doubled = $true; return $res }
        if ($mk -ceq 'g') { if ($i -ge $n) { $res.state = 'more'; return $res }; $mk = 'g' + $t[$i]; $i++ }
        if ($mk -ceq 'f' -or $mk -ceq 'F' -or $mk -ceq 't' -or $mk -ceq 'T') {
            if ($i -ge $n) { $res.state = 'more'; return $res }
            $res.ch = $t[$i]; if ($res.ch -eq '<Esc>') { $res.state = 'bad' }
        }
        if ($script:MOTIONS -ccontains $mk) { $res.motion = $mk } else { $res.state = 'bad' }
        return $res
    }
    return $res
}
function VNormalKey($st, [string]$k) {
    $st.pend += $k
    $res = VParse $st.pend
    if ($res.state -eq 'more') { return }
    $toks = $st.pend; $st.pend = @()
    if ($res.state -eq 'bad') { $st.bell = $true; return }
    VExec $st $res $toks
}
function VExec($st, $res, $toks) {
    $cmd = $res.cmd; $cnt = $res.count; $c1 = $cnt; if ($c1 -lt 1) { $c1 = 1 }
    $isChange = ($script:VCHANGE -ccontains $cmd) -or ($res.op -and $res.op -ne 'y')
    if ($isChange -and -not $st.replaying) { $st.last = @{ keys = (Slice $toks $res.at $toks.Count); count = $cnt } }
    if ($isChange) { $st.vsnap = Snap $st }
    $st.regName = ''
    try { VDo $st $res $cmd $cnt $c1; if ($res.op -or -not ($script:MOTIONS -ccontains $cmd)) { $st.want = -2 } } finally {
        if ($st.mode -eq 'i') { if ($isChange -and -not $st.replaying) { $st.recIns = $true } } else { VFinishChange $st }
    }
}
function VDo($st, $res, [string]$cmd, [int]$cnt, [int]$c1) {
    if ($res.op) {
        $total = $c1; if ($res.count2 -gt 0) { $total = $c1 * $res.count2 } elseif ($cnt -lt 1) { $total = 0 }
        if ($res.doubled) { VApplyOp $st $res.op $null (Max2 1 $total) $true; return }
        $m = VMotion $st $res.motion $res.ch $total $res.op
        if (-not $m.ok) { $st.bell = $true; return }
        VApplyOp $st $res.op $m $total $false; return
    }
    if ($script:MOTIONS -ccontains $cmd) {
        $m = VMotion $st $cmd $res.ch $cnt ''
        if (-not $m.ok) { $st.bell = $true; return }
        $st.r = $m.r; $st.c = $m.c; if ($m.bell) { $st.bell = $true }
        if (-not $m.vert) { if ($null -ne $m.want) { $st.want = $m.want } else { SetWant $st } }
        return
    }
    $line = VLine $st $st.r; $len = $line.Length
    switch -CaseSensitive ($cmd) {
        { $_ -eq 'x' -or $_ -eq '<Del>' } { if ($len -eq 0) { $st.bell = $true; return }; $k = Min2 $c1 ($len - $st.c); VApplyOp $st 'd' @{ r = $st.r; c = $st.c + $k; lw = $false; inc = $false } 1 $false; return }
        'X' { if ($st.c -eq 0) { $st.bell = $true; return }; $k = Min2 $c1 $st.c; VApplyOp $st 'd' @{ r = $st.r; c = $st.c - $k; lw = $false; inc = $false } 1 $false; return }
        'D' { $m = VMotion $st '$' '' $c1 'd'; if ($m.ok -and $len) { VApplyOp $st 'd' $m $c1 $false }; return }
        'C' { $m = VMotion $st '$' '' $c1 'c'; if ($len -eq 0 -and $c1 -eq 1) { VStartInsert $st 'c' 1; return }; if ($m.ok) { VApplyOp $st 'c' $m $c1 $false }; return }
        's' { if ($len -eq 0) { VStartInsert $st 'c' 1; return }; $k = Min2 $c1 ($len - $st.c); VApplyOp $st 'c' @{ r = $st.r; c = $st.c + $k; lw = $false; inc = $false } 1 $false; return }
        'S' { VApplyOp $st 'c' $null $c1 $true; return }
        'Y' { VApplyOp $st 'y' $null $c1 $true; return }
        { $_ -eq 'p' -or $_ -eq 'P' } { VPut $st ($cmd -ceq 'P') $c1; return }
        { $_ -eq 'J' -or $_ -eq 'gJ' } {
            $nl = NL $st; $k = Max2 2 $c1
            if ($st.r + $k - 1 -gt $nl - 1) { if ($cnt -le 2) { $st.bell = $true; return }; $k = $nl - $st.r }   # vim joins what is there
            $last = $st.r + $k - 1
            $j = JoinLines (Slice $st.buf.L $st.r ($last + 1)) ($cmd -ceq 'J')
            BufReplace $st $st.r ($last - $st.r + 1) @($j.text); $st.c = $j.col; return
        }
        'r' {
            $ch = $res.ch
            if ($st.c + $c1 -gt $len) { $st.bell = $true; return }
            if ($ch -eq '<CR>') { BufReplace $st $st.r 1 @($line.Substring(0, $st.c), $line.Substring($st.c + $c1)); $st.r++; $st.c = 0; return }
            if ($ch -eq '<Tab>') { $ch = "`t" }
            if ($ch.Length -ne 1) { $st.bell = $true; return }
            VSetLine $st $st.r ($line.Substring(0, $st.c) + ($ch * $c1) + $line.Substring($st.c + $c1)); $st.c = $st.c + $c1 - 1; return
        }
        '~' {
            if ($len -eq 0) { return }
            $k = Min2 $c1 ($len - $st.c); $seg = $line.Substring($st.c, $k)
            $t = -join @(foreach ($ch in [char[]]$seg) { $s1 = [string]$ch; if ($s1 -cmatch '^\p{Lu}$') { $s1.ToLowerInvariant() } else { $s1.ToUpperInvariant() } })
            VSetLine $st $st.r ($line.Substring(0, $st.c) + $t + $line.Substring($st.c + $k)); $st.c = Min2 ($st.c + $k) ($len - 1); return
        }
        { $_ -eq 'i' -or $_ -eq 'a' -or $_ -eq 'I' -or $_ -eq 'A' -or $_ -eq 'o' -or $_ -eq 'O' } { VStartInsert $st $cmd $c1; return }
        'u' { for ($q = 0; $q -lt $c1; $q++) { try { $null = UndoOnce $st $false } catch { $st.msg = [string]$_.Exception.Message; break } }; return }
        '<C-r>' { for ($q = 0; $q -lt $c1; $q++) { try { $null = UndoOnce $st $true } catch { $st.msg = [string]$_.Exception.Message; break } }; return }
        '.' {
            if ($null -eq $st.last) { $st.bell = $true; return }
            $n = $st.last.count; if ($cnt -gt 0) { $n = $cnt }
            $tok = @(); if ($n -gt 0) { foreach ($ch in [char[]]([string]$n)) { $tok += [string]$ch } }
            $tok += $st.last.keys
            $st.replaying = $true
            try { foreach ($k in $tok) { VKey $st $k } } finally { $st.replaying = $false }
            return
        }
        { $_ -eq ':' -or $_ -eq '/' -or $_ -eq '?' } { $st.mode = 'c'; $st.cmdtype = $cmd; $st.cmdline = ''; if ($cnt -gt 0 -and $cmd -eq ':') { $st.cmdline = ".,.+$($cnt - 1)" }; return }
        '&' { VRunEx $st 's'; return }
        'ZZ' { VRunEx $st 'x'; return }
        'ZQ' { VRunEx $st 'q!'; return }
        '<C-g>' { $st.cur = $st.r + 1; $st.msg = FileInfo $st; return }
        '<C-l>' { return }
        { $_ -eq '<C-f>' -or $_ -eq '<PageDown>' } { $nl = NL $st; $st.top = Min2 ($nl - 1) ($st.top + (Max2 1 ($st.H - 2)) * $c1); $st.r = Max2 $st.r $st.top; $st.c = FirstNonBlank (VLine $st $st.r); return }
        { $_ -eq '<C-b>' -or $_ -eq '<PageUp>' } { $st.top = Max2 0 ($st.top - (Max2 1 ($st.H - 2)) * $c1); $st.r = Min2 $st.r ($st.top + $st.H - 1); $st.c = FirstNonBlank (VLine $st $st.r); return }
        { $_ -eq '<C-d>' -or $_ -eq '<C-u>' } {
            $h = Max2 1 (($st.H - ($st.H % 2)) / 2); if ($cnt -gt 0) { $h = $cnt }; $nl = NL $st
            if ($cmd -eq '<C-d>') { if ($st.r -ge $nl - 1) { $st.bell = $true; return }; $st.r = Min2 ($nl - 1) ($st.r + $h); $st.top = Min2 (Max2 0 ($nl - $st.H)) ($st.top + $h) }
            else { if ($st.r -le 0) { $st.bell = $true; return }; $st.r = Max2 0 ($st.r - $h); $st.top = Max2 0 ($st.top - $h) }
            $st.c = FirstNonBlank (VLine $st $st.r); return
        }
        '<C-e>' { if ($st.top -lt (NL $st) - 1) { $st.top++; if ($st.r -lt $st.top) { $st.r = $st.top } }; return }
        '<C-y>' { if ($st.top -gt 0) { $st.top--; if ($st.r -ge $st.top + $st.H) { $st.r = $st.top + $st.H - 1 } }; return }
    }
    $st.bell = $true
}
function VPut($st, [bool]$before, [int]$c1) {
    $reg = $st.reg
    if ($reg.lines.Count -eq 0) { $st.bell = $true; return }
    if ($reg.lw) {
        EnsureLine $st
        $ins = @(); for ($q = 0; $q -lt $c1; $q++) { $ins += $reg.lines }
        $at = $st.r + 1; if ($before) { $at = $st.r }
        BufReplace $st $at 0 $ins; $st.r = $at; $st.c = FirstNonBlank (VLine $st $at); return
    }
    $line = VLine $st $st.r
    $pos = $st.c + 1; if ($line.Length -eq 0) { $pos = 0 } elseif ($before) { $pos = $st.c }
    $tx = $reg.lines
    if ($tx.Count -eq 1) {
        $t = [string]$tx[0] * $c1
        if ($t.Length -eq 0) { return }                 # nothing to put: the line is not touched
        VSetLine $st $st.r ($line.Substring(0, $pos) + $t + $line.Substring($pos)); $st.c = Max2 0 ($pos + $t.Length - 1); return
    }
    $acc = @($tx)
    for ($q = 1; $q -lt $c1; $q++) { $acc = (Slice $acc 0 ($acc.Count - 1)) + @([string]$acc[$acc.Count - 1] + [string]$tx[0]) + (Slice $tx 1 $tx.Count) }
    $new = @($line.Substring(0, $pos) + $acc[0]) + (Slice $acc 1 ($acc.Count - 1)) + @([string]$acc[$acc.Count - 1] + $line.Substring($pos))
    BufReplace $st $st.r 1 $new
    $st.c = $pos
}
function VRunEx($st, [string]$line) {
    $b = $st.buf; $state0 = $b.state; $st.cur = $st.r + 1; $cur0 = $st.cur; $st.msgs = @()
    ExTop $st $line
    if ($st.buf -ne $b) { $st.r = Max2 0 ($st.cur - 1); if ($st.cur -lt 1) { $st.r = 0 }; $st.c = 0; $st.top = 0 }
    elseif ($st.buf.state -ne $state0 -or $st.cur -ne $cur0) { $st.r = Max2 0 ($st.cur - 1); $st.c = FirstNonBlank (VLine $st $st.r) }
    SetWant $st
    if ($st.msgs.Count -eq 1) { $st.msg = $st.msgs[0] }
    elseif ($st.msgs.Count -gt 1) { $st.pager = $st.msgs; $st.ptop = 0; $st.mode = 'p' }
    $st.msgs = @()
    if ($st.goVisual) { $st.goVisual = $false }
}
function VCmdKey($st, [string]$k) {
    switch ($k) {
        { $_ -eq '<Esc>' -or $_ -eq '<C-c>' } { $st.mode = 'n'; $st.cmdline = ''; return }
        '<CR>' {
            $line = $st.cmdline; $type = $st.cmdtype; $st.mode = 'n'; $st.cmdline = ''
            if ($type -eq ':') { if ($line) { $st.hist += $line }; VRunEx $st $line; return }
            $dir = 1; if ($type -eq '?') { $dir = -1 }
            $st.lastDir = $dir
            try { [void](VSearch $st $line $dir $true) } catch { $st.msg = [string]$_.Exception.Message; $st.bell = $true }
            return
        }
        { $_ -eq '<BS>' -or $_ -eq '<C-h>' } { if ($st.cmdline.Length -eq 0) { $st.mode = 'n'; return }; $st.cmdline = $st.cmdline.Substring(0, $st.cmdline.Length - 1); return }
        '<C-u>' { $st.cmdline = ''; return }
        '<Up>' { if ($st.hist.Count) { $st.cmdline = $st.hist[$st.hist.Count - 1] }; return }
        '<Tab>' { $st.cmdline += "`t"; return }
    }
    if ($k.Length -eq 1) { $st.cmdline += $k }
}
function VPagerKey($st, [string]$k) {
    if ($k -eq 'q' -or $k -eq '<Esc>') { $st.mode = 'n'; $st.pager = @(); return }
    $step = 1; if ($k -eq ' ' -or $k -eq '<C-f>' -or $k -eq '<PageDown>') { $step = Max2 1 ($st.H) }
    $st.ptop += $step
    if ($st.ptop + $st.H + 1 -gt $st.pager.Count -and ($k -ne 'j' -and $k -ne ' ' -and $k -ne '<CR>')) { $st.mode = 'n'; $st.pager = @(); return }
    if ($st.ptop -ge $st.pager.Count - $st.H) { if ($st.ptop -gt $st.pager.Count - $st.H) { $st.mode = 'n'; $st.pager = @() } }
}
function VKey($st, [string]$k) {
    $st.bell = $false
    if ($st.mode -ne 'c' -and $st.mode -ne 'p') { $st.msg = '' }
    try {
        switch ($st.mode) {
            'i' { VInsertKey $st $k }
            'c' { VCmdKey $st $k }
            'p' { VPagerKey $st $k }
            default { VNormalKey $st $k }
        }
    } catch { $st.msg = [string]$_.Exception.Message; $st.pend = @(); $st.bell = $true }
    if ($st.mode -ne 'i') { VClamp $st } else { VClamp $st }
    VScroll $st
}
function ParseKeys([string]$s) {
    $out = @()
    foreach ($m in [regex]::Matches($s, '<[A-Za-z][-A-Za-z0-9]*>|[\s\S]')) {
        $t = $m.Value
        if ($t.Length -gt 1) {
            $tl = $t.ToLowerInvariant()
            switch -Regex ($tl) {
                '^<esc>$' { $t = '<Esc>'; break } '^<(cr|enter|return)>$' { $t = '<CR>'; break } '^<bs>$' { $t = '<BS>'; break }
                '^<tab>$' { $t = '<Tab>'; break } '^<del>$' { $t = '<Del>'; break } '^<lt>$' { $t = '<'; break } '^<space>$' { $t = ' '; break }
                '^<up>$' { $t = '<Up>'; break } '^<down>$' { $t = '<Down>'; break } '^<left>$' { $t = '<Left>'; break } '^<right>$' { $t = '<Right>'; break }
                '^<home>$' { $t = '<Home>'; break } '^<end>$' { $t = '<End>'; break } '^<pageup>$' { $t = '<PageUp>'; break } '^<pagedown>$' { $t = '<PageDown>'; break }
                '^<c-([a-z])>$' { $t = '<C-' + $Matches[1] + '>'; break }
            }
        }
        $out += $t
    }
    return ,$out
}
function DispCol([string]$s, [int]$c) {           # vim's cursor column on screen: a tab shows the cursor on its last cell
    $w = 0; for ($q = 0; $q -lt $c -and $q -lt $s.Length; $q++) { if ([string]$s[$q] -eq "`t") { $w = $w + 8 - ($w % 8) } else { $w++ } }
    if ($c -lt $s.Length -and [string]$s[$c] -eq "`t") { $w = $w + 7 - ($w % 8) }
    return $w
}
function ColFor([string]$s, [int]$want) {           # the character whose screen cells hold column want (vim's coladvance)
    if ($s.Length -eq 0) { return 0 }
    $w = 0
    for ($q = 0; $q -lt $s.Length; $q++) {
        $e = $w; if ([string]$s[$q] -eq "`t") { $e = $w + 7 - ($w % 8) }
        if ($want -le $e) { return $q }
        $w = $e + 1
    }
    return $s.Length - 1
}
function SetWant($st) { $st.want = DispCol (VLine $st $st.r) $st.c }
function DispWidth([string]$s, [int]$upto) { $w = 0; for ($q = 0; $q -lt $upto -and $q -lt $s.Length; $q++) { if ([string]$s[$q] -eq "`t") { $w = $w + 8 - ($w % 8) } else { $w++ } }; return $w }
function Expand([string]$s) { if ($s.IndexOf("`t") -lt 0) { return $s }; $o = ''; foreach ($ch in [char[]]$s) { if ($ch -eq "`t") { $o += ' ' * (8 - ($o.Length % 8)) } else { $o += [string]$ch } }; return $o }
function Screen($st) {                              # the screen as text rows (pure): H text rows, a status row, a message row
    VClamp $st; VScroll $st
    $width = $st.W; $height = $st.H; $scr = @()
    if ($st.mode -eq 'p') {
        for ($y = 0; $y -le $height; $y++) { $k = $st.ptop + $y; $t = ''; if ($k -lt $st.pager.Count) { $t = Expand ([string]$st.pager[$k]) }; if ($t.Length -gt $width - 1) { $t = $t.Substring(0, $width - 1) }; $scr += $t.PadRight($width - 1) }
        $more = 'Press ENTER or type command to continue'; if ($st.ptop + $height + 1 -lt $st.pager.Count) { $more = '-- More -- (Space: page, Enter: line, q: quit)' }
        $scr += $more.PadRight($width - 1); $st.scrX = Min2 ($width - 2) $more.Length; $st.scrY = $height + 1
        return ,$scr
    }
    $nw = 0; if ($st.opt.nu) { $nw = (Max2 3 ([string](NL $st)).Length) + 1 }
    $tw = Max2 10 ($width - 1 - $nw)
    $dc = DispWidth (VLine $st $st.r) $st.c
    if ($dc -lt $st.left) { $st.left = $dc }; if ($dc -ge $st.left + $tw) { $st.left = $dc - $tw + 1 }
    for ($y = 0; $y -lt $height; $y++) {
        $k = $st.top + $y
        if ($k -lt $st.buf.L.Count) {
            $t = Expand (VLine $st $k)
            if ($st.left -gt 0) { if ($t.Length -gt $st.left) { $t = $t.Substring($st.left) } else { $t = '' } }
            if ($t.Length -gt $tw) { $t = $t.Substring(0, $tw) }
            if ($nw) { $t = ([string]($k + 1)).PadLeft($nw - 1) + ' ' + $t }
        } else { $t = '~' }
        $scr += $t.PadRight($width - 1)
    }
    $name = $st.buf.name; if (-not $name) { $name = '[No Name]' }
    $mod = ''; if (IsMod $st.buf) { $mod = ' [+]' }
    $pos = "$($st.r + 1),$($st.c + 1)"; $left = " $name$mod"
    $status = $left + ' ' * (Max2 1 ($width - 1 - $left.Length - $pos.Length - 1)) + $pos + ' '
    if ($status.Length -gt $width - 1) { $status = $status.Substring(0, $width - 1) }
    $scr += $status
    $msg = $st.msg
    if ($st.mode -eq 'c') { $msg = $st.cmdtype + $st.cmdline } elseif ($st.mode -eq 'i') { $msg = '-- INSERT --' } elseif (-not $msg -and $st.pend.Count) { $msg = ' ' * ($width - 12) + (-join $st.pend) }
    $msg = [string]$msg; if ($msg.Length -gt $width - 1) { $msg = $msg.Substring(0, $width - 1) }
    $scr += $msg.PadRight($width - 1)
    if ($st.mode -eq 'c') { $st.scrX = Min2 ($width - 2) $msg.Length; $st.scrY = $height + 1 }
    else { $st.scrX = Min2 ($width - 2) ($nw + $dc - $st.left); $st.scrY = $st.r - $st.top }
    return ,$scr
}
function Render($st) {
    $scr = Screen $st
    [Console]::CursorVisible = $false
    for ($y = 0; $y -lt $scr.Count; $y++) {
        [Console]::SetCursorPosition(0, $y)
        if ($y -eq $st.H -and $st.mode -ne 'p') { Write-Host -NoNewline -ForegroundColor Black -BackgroundColor Gray $scr[$y] } else { [Console]::Write($scr[$y]) }
    }
    [Console]::SetCursorPosition($st.scrX, $st.scrY)
    [Console]::CursorVisible = $true
}
function ReadKeyTok {
    $k = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown,AllowCtrlC')
    $vk = [int]$k.VirtualKeyCode; $code = [int]$k.Character
    switch ($vk) { 27 { return '<Esc>' } 13 { return '<CR>' } 8 { return '<BS>' } 9 { return '<Tab>' } 46 { return '<Del>' } 37 { return '<Left>' }
        38 { return '<Up>' } 39 { return '<Right>' } 40 { return '<Down>' } 36 { return '<Home>' } 35 { return '<End>' } 33 { return '<PageUp>' } 34 { return '<PageDown>' } }
    if ($code -eq 0) { return $null }
    if ($code -eq 27 -or $code -eq 3) { return '<Esc>' }
    if ($code -lt 32) { return '<C-' + [string][char]($code + 96) + '>' }
    return [string][char]$code
}
function VisualLoop($st) {
    $st.visual = $true; $st.r = Max2 0 ($st.cur - 1); if ($st.buf.L.Count -gt 0 -and $st.cur -ge $st.buf.L.Count) { $st.r = 0 }
    $ui = $Host.UI.RawUI
    Clear-Host
    try {
        while (-not $st.quit) {
            $sz = $ui.WindowSize; $st.H = Max2 3 ($sz.Height - 2); $st.W = Max2 20 $sz.Width
            Render $st
            $k = ReadKeyTok
            if ($null -ne $k) { VKey $st $k }
        }
    } finally { Clear-Host }
}

# ================================================================ main
function NewState {
    return @{ buf = $null; cur = 0; r = 0; c = 0; want = -2; top = 0; left = 0; H = 20; W = 80; mode = 'n'; pend = @(); msgs = @(); log = @(); msg = ''
        errors = 0; quit = $false; reg = @{ lw = $true; lines = @() }; regs = @{}; regName = ''; lastPat = $null; lastDir = 1; lastSub = $null; lastRep = ''
        lastFt = $null; opt = @{ nu = $false; ic = $false; ws = $true; window = 20 }; qf = @(); qfi = -1; args = @(); argi = 0; inGlobal = $false
        feed = $null; feedi = 0; visual = $false; canVisual = $false; goVisual = $false; agile = $Agile; undoing = $false; warnedArgs = $false
        last = $null; replaying = $false; recIns = $false; vsnap = $null; ins = $null; cmdtype = ':'; cmdline = ''; hist = @(); pager = @(); ptop = 0
        bell = $false; scrX = 0; scrY = 0 }
}
function Flush($st) { foreach ($m in $st.msgs) { Write-Output $m }; $st.msgs = @() }
function ShowContext($st) {
    $n = $st.buf.L.Count; if ($st.buf.empty) { Write-Output '--No lines in buffer--'; return }
    $c = Max2 1 (Min2 $st.cur $n); $a = Max2 1 ($c - 2); $b = Min2 $n ($c + 2)
    for ($k = $a; $k -le $b; $k++) { $mark = ' '; if ($k -eq $c) { $mark = '>' }; Write-Output ($mark + ('{0,4} ' -f $k) + $st.buf.L[$k - 1]) }
}
function ExLoop($st, [bool]$interactive) {
    while (-not $st.quit) {
        if ($interactive) { Write-Host -NoNewline ':' }
        $line = NextLine $st
        if ($null -eq $line) { break }
        $b = $st.buf; $state0 = $b.state
        ExTop $st $line
        Flush $st
        if ($st.goVisual) { $st.goVisual = $false; VisualLoop $st; continue }
        if ($interactive -and -not $st.quit -and ($st.buf -ne $b -or $st.buf.state -ne $state0)) { ShowContext $st }
    }
}

$st = NewState
if ($ExecutionContext.SessionState.LanguageMode -eq 'FullLanguage' -and $Host.Name -eq 'ConsoleHost') {
    try { if (-not [Console]::IsInputRedirected -and -not [Console]::IsOutputRedirected) { $st.canVisual = $true } } catch { }
}
if ($Files) { $st.args = @($Files) }
try { if ($st.args.Count) { EditFile $st $st.args[0] $true } else { $st.buf = NewBuffer '' } }
catch { $st.buf = NewBuffer ''; Say $st ([string]$_.Exception.Message); $st.errors++ }
$st.cur = $st.buf.L.Count
if ($Script) {
    $st.feed = @(Get-Content -LiteralPath $Script -Encoding UTF8)
    Flush $st
    ExLoop $st $false
    Flush $st
    if ($st.errors) { exit 1 }; exit 0
}
if ($Keys) {
    $st.visual = $true; $st.cur = 1; $st.r = 0
    if ($Rows -gt 2) { $st.H = $Rows - 2 }; if ($Cols -gt 10) { $st.W = $Cols }
    $st.log = @()
    $ks = ParseKeys $Keys; $ki = 0
    while ($ki -lt $ks.Count -and -not $st.quit) {
        VKey $st $ks[$ki]; $ki++
        if ($NormAbort -and $st.bell) {               # like vim's :normal, an error drops the keys after it (up to a final ':' command line)
            $j = $ki; $tail = -1
            for ($q = $ks.Count - 1; $q -ge $ki; $q--) { if ($ks[$q] -eq ':') { $tail = $q; break } }
            if ($tail -lt 0) { break }
            $st.mode = 'n'; $st.pend = @(); $ki = $tail
        }
    }
    foreach ($tl in $st.log) { Write-Output $tl }
    if ($st.msg) { Write-Output $st.msg }
    if ($Dump) { foreach ($row in (Screen $st)) { Write-Output ('|' + $row.TrimEnd()) }; Write-Output "cursor $($st.r + 1),$($st.c + 1) mode $($st.mode)" }
    exit 0
}
if ($Ex -or -not $st.canVisual) {
    if (-not $Ex -and $ExecutionContext.SessionState.LanguageMode -ne 'FullLanguage') {
        Say $st 'pvi: ex mode (Constrained Language Mode refuses single-key input). :help lists the commands, :q quits.'
    }
    Flush $st
    ExLoop $st $true
    exit 0
}
$st.msgs = @()
VisualLoop $st
exit 0
