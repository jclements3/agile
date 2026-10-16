<#
agile.ps1 -- the agile kit's daily loop in Windows PowerShell 5.1.

Runs on a locked-down laptop: no install, no compiler, no admin, no network, no COM, and it
works under Constrained Language Mode (AppLocker/WDAC). Same files as the Perl kit:
scrum.conf, the scrum.txt journal, standups/<date>.txt notes, standups/<date>[-Team]-chat.txt
pastes of the Teams chat. Either kit can work on the same project folder.

  powershell -ExecutionPolicy Bypass -File agile.ps1 <command> [args] [-Today YYYY-MM-DD]

  init [DIR]          new project folder: scrum.conf, scrum.txt, standups\, reports\
  new [Team...]       today's stand-up file (standups\<today>.txt) listing each team's open tasks
  paste [Team]        Teams chat on the clipboard -> standups\<today>[-Team]-chat.txt, then lint
  lint [FILE]         check every Y/T/B status in the chat; -Reply: the lines to post back (-Clip copies them);
                      -Private: reports\<today>-lint.html, a Teams 1:1 link per person (e-mails from roster.txt)
  propose [Team]      today's statuses drafted from yesterday's (-Clip copies them; -Private: 1:1 links)
  answers             chat -> answers file, flags, suggested lines appended to today's stand-up file
  chat [FILE]         #est / #vote rounds in the meeting chat -> tallies, est/note lines into today's stand-up file
  tally [FILE|-]      the same tallies without a project (-Est ID / -Vote Q markerless, -Since, -Options, -Lines, -Messages)
  compile             apply pending stand-up files to the journal (-Dry: show, do not write)
  draft | brief       the status mail / the BLUF brief: reports\<today>-status|brief.html + .txt to paste into Teams or Outlook
  commit              commit the project with pgit.ps1 ("standup <today>")
  all [-Draft]        compile, report, (draft,) commit
  joined [FILE...]    Teams attendance report downloads -> attendance.csv (join, leave, minutes; via townhall.ps1)
  health [Team] | review [N] | rollup [YYYY-MM] | quad [Team] | roster [add ...] | csv health
                      the metrics and planning commands: run by agile-more.ps1 (beside this file)
  status | sprint [N] | velocity | backlog [Team] | members [Team] | epics | roadmap | blocked
  csv [TABLE]         reports\items.csv sprints.csv epics.csv intake.csv for Excel (TABLE: print one)
  report              reports\<today>-status.txt/.html, -brief.txt and the CSVs
  check               parse the journal, list every problem
#>
param(
    [Parameter(Position = 0)][string]$Command = 'status',
    [Parameter(Position = 1, ValueFromRemainingArguments = $true)][string[]]$Rest,
    [string]$Conf, [string]$Today, [switch]$Dry, [switch]$Reply, [switch]$Table,
    [switch]$Assume, [switch]$Guess, [switch]$Confirm, [switch]$Clip, [switch]$Private,
    [string]$To, [string]$Cc, [string]$Subject, [switch]$Force, [switch]$Draft,
    [string]$Est, [string]$Vote, [string]$Since, [string]$Options, [switch]$Lines, [switch]$Messages,
    [Parameter(ValueFromPipeline = $true)][string]$Pipe   # tally: chat lines piped in (read as $input below)
)
# daily.pl's metrics and planning commands (health review rollup quad roster, csv health) are agile-more.ps1's. Forwarded
# here, before any function is defined: agile-more.ps1 loads this file's functions itself only when it does not see them.
if ($Command -cin @('health', 'review', 'rollup', 'quad', 'roster') -or ($Command -ceq 'csv' -and @($Rest).Count -and $Rest[0] -ceq 'health')) {
    $more = $null; if ($PSCommandPath) { $more = Join-Path (Split-Path -Parent $PSCommandPath) 'agile-more.ps1' }
    $fwdRc = 2
    if (-not $more -or -not (Test-Path -LiteralPath $more -PathType Leaf)) { Write-Host "$Command needs agile-more.ps1 beside agile.ps1" -ForegroundColor Yellow }
    else {
        $mArgs = @{}; if ($Conf) { $mArgs['Conf'] = $Conf }; if ($Today) { $mArgs['Today'] = $Today }
        $fwd = @($Rest | Where-Object { $null -ne $_ })
        & $more $Command @fwd @mArgs; $fwdRc = $LASTEXITCODE
    }
    if ($PSCommandPath) { exit $fwdRc }
    $global:LASTEXITCODE = $fwdRc; return
}
$script:USAGE = @"
agile.ps1 -- the agile kit's daily loop for Windows PowerShell 5.1 (Constrained Language Mode safe)

  agile.ps1 COMMAND [ARGS] [-Today YYYY-MM-DD] [-Conf path\scrum.conf]

Set up
  init [DIR]          new project folder: scrum.conf, scrum.txt, standups\, reports\

Every morning (Teams)
  new [Team...]       today's stand-up file, standups\<today>.txt, listing each team's open tasks
  propose [Team]      today's statuses drafted from yesterday's, one line per person to post (-Clip: on the clipboard;
                      -Private: reports\<today>-propose.html with a Teams 1:1 link per person, e-mails from roster.txt)
  paste [Team]        Teams chat on the clipboard (Ctrl+A, Ctrl+C in the chat) -> standups\<today>[-Team]-chat.txt, then lint
  lint [FILE]         check every Y/T/B status; -Reply: the lines to post back, -Clip: copy them for Ctrl+V in Teams,
                      -Confirm: also read back clean statuses (until someone has readback_clean_days clean days), -Table: what was read,
                      -Private: reports\<today>-lint.html, the replies as Teams 1:1 links instead of posts in the meeting chat
  answers             statuses -> standups\<today>-<Team>-answers.txt, flags, attendance.csv, suggested lines in today's file
                      (-Assume: record yesterday's plan for the silent, marked assumed; -Guess: accept the lint's best reading)
  chat [FILE]         #est / #vote rounds in the meeting chat (standups\<today>-chat.txt) -> tallies, lines into today's file
  compile             apply the pending stand-up files to the journal (-Dry: show what would be appended)
  commit              save the project with pgit.ps1 (git for PowerShell): "standup <today>"
  all [-Draft]        compile, report, (draft,) commit
  joined [FILE...]    Teams attendance report downloads -> attendance.csv (join, leave, minutes; via townhall.ps1)
  health [Team] | review [N] | rollup [YYYY-MM] | quad [Team] | roster [add ...] | csv health
                      the metrics and planning commands: run by agile-more.ps1 (beside this file)

Reports and the spreadsheet
  report              reports\<today>-status.txt/.html, <today>-brief.txt/.html, items/sprints/epics/intake.csv, backlog.xml
  draft | brief       the status mail / the BLUF brief as reports\<today>-status|brief.html + .txt, subject line printed:
                      paste into a Teams post (or Outlook). -Subject S, -To/-Cc (marking domain check), -Force, -Clip
  tally [FILE|-]      #est/#vote tallies of any chat, no project needed: -Est ID / -Vote Q (markerless), -Since HH:MM,
                      -Options a/b/c, -Lines (stand-up lines), -Messages (what the parser read); - or a pipe: stdin
  csv [TABLE]         the CSVs and backlog.xml (TABLE = items|sprints|epics|intake prints one)
  status | sprint [N] | velocity | backlog [Team] | members [Team] | epics | roadmap | blocked | check

Stand-up file verbs (under '== Team'):
  done carry drop commit refine prune new new! est assign block unblock hold resume punt redo pass sync cap note risk absent
"@
$ErrorActionPreference = 'Stop'
$script:RC = 0
$script:NL = "`n"

# ================================================================ Constrained Language Mode
# CLM allows methods on core types only. Hashtable is core; [ordered] (OrderedDictionary) is not, so its
# .Contains() is refused. ODHas reads the keys instead (a property), with [ordered]'s case-insensitive match.
function ODHas($d, $k) { foreach ($x in $d.Keys) { if ($x -eq $k) { return $true } }; return $false }

# ================================================================ output and numbers
function Out-Text([string]$t) {                       # print text that ends in newlines, line for line (no extra blank line)
    if ($null -eq $t -or $t -eq '') { return }
    if ($t.EndsWith("`n")) { $t = $t.Substring(0, $t.Length - 1) }
    foreach ($l in ($t -split "`n")) { Write-Output $l }
}
function Out-Err([string]$t) {                        # Perl's STDERR: shown, never mixed into redirected output
    if ($null -eq $t -or $t -eq '') { return }
    if ($t.EndsWith("`n")) { $t = $t.Substring(0, $t.Length - 1) }
    foreach ($l in ($t -split "`n")) { Write-Host $l -ForegroundColor Yellow }
}
function Trunc($x) { $d = [double]$x; $r = [long]$d; if ($d -ge 0) { if ($r -gt $d) { $r-- } } else { if ($r -lt $d) { $r++ } }; $r }   # Perl int()
function Num($x) {                                    # a number as Perl prints it: 5, 2.5, -3, 0.333333333333333
    if ($null -eq $x) { return '' }
    if ($x -is [string]) { return $x }
    $d = [double]$x
    if ($d -lt 1e15 -and $d -gt -1e15 -and $d -eq [double][long]$d) { return [string][long]$d }
    (('{0:G15}' -f $d) -replace ',', '.')
}
function Str($v) {
    if ($null -eq $v) { return '' }
    if ($v -is [string]) { return $v }
    if ($v -is [double] -or $v -is [int] -or $v -is [long] -or $v -is [decimal]) { return (Num $v) }
    [string]$v
}
function Fmt1($x) {                                   # sprintf '%.1f' (round half to even on the binary value, as C does)
    $d = [double]$x; $neg = $d -lt 0; if ($neg) { $d = -$d }
    $y = $d * 10; $f = Trunc $y; $fr = $y - $f
    if ($fr -gt 0.5 -or ($fr -eq 0.5 -and ($f % 2) -eq 1)) { $f++ }
    $ip = Trunc ($f / 10); $dp = $f - $ip * 10
    $r = "$ip.$dp"; if ($neg) { $r = "-$r" }; $r
}
function Pct($a, $b) { if ($b) { Trunc (100 * $a / $b + 0.5) } else { 0 } }
function PctU($a, $b) { if ($b) { Trunc (100 * $a / $b + 0.5) } else { $null } }
function Sum($list) { $t = 0.0; foreach ($x in $list) { $t += [double]$x }; $t }
function Plural($n) { if ($n -eq 1) { '' } else { 's' } }

# ================================================================ ordering (Prelude::compare, a stable merge sort)
$script:NUMRE = '^\s*[-+]?(?:(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?)\s*$'
function IsNum($x) {
    if ($null -eq $x) { return $false }
    if ($x -is [double] -or $x -is [int] -or $x -is [long] -or $x -is [decimal]) { return $true }
    if ($x -is [string]) { return ($x -cmatch $script:NUMRE) }
    $false
}
function Cmp($x, $y) {                                # -1/0/1: undef first, arrays lexicographically, numbers numerically, else by code unit
    $dx = $null -ne $x; $dy = $null -ne $y
    if (-not ($dx -and $dy)) { return ([int]$dx - [int]$dy) }
    if ($x -is [array] -and $y -is [array]) {
        $m = $x.Count; if ($y.Count -lt $m) { $m = $y.Count }
        for ($i = 0; $i -lt $m; $i++) { $c = Cmp $x[$i] $y[$i]; if ($c -ne 0) { return $c } }
        return ([int]($x.Count -gt $y.Count) - [int]($x.Count -lt $y.Count))
    }
    if ((IsNum $x) -and (IsNum $y)) { $a = [double]$x; $b = [double]$y; if ($a -lt $b) { return -1 }; if ($a -gt $b) { return 1 }; return 0 }
    $c = [string]::CompareOrdinal((Str $x), (Str $y))
    if ($c -lt 0) { -1 } elseif ($c -gt 0) { 1 } else { 0 }
}
function SortWith($list, [scriptblock]$cmp) {         # stable: equal elements keep their order (Perl's mergesort)
    $src = @($list); $n = $src.Count
    if ($n -lt 2) { return , $src }
    $w = 1
    while ($w -lt $n) {
        $src = @(for ($lo = 0; $lo -lt $n; $lo += 2 * $w) {
                $mid = $lo + $w; if ($mid -gt $n) { $mid = $n }
                $hi = $lo + 2 * $w; if ($hi -gt $n) { $hi = $n }
                $i = $lo; $j = $mid
                while ($i -lt $mid -and $j -lt $hi) {
                    if ((& $cmp $src[$j] $src[$i]) -lt 0) { , $src[$j]; $j++ } else { , $src[$i]; $i++ }
                }
                while ($i -lt $mid) { , $src[$i]; $i++ }
                while ($j -lt $hi) { , $src[$j]; $j++ }
            })
        $w *= 2
    }
    , $src
}
# FastSortIdx: the indexes of $keys in stable Cmp order, as SortWith + Cmp would give them, but with each key normalised
# once (null / number / string, its double and its Str) and compared inline: no scriptblock or function call per
# comparison. Keys must be all scalars or all flat arrays; anything else returns $null and the caller falls back.
function FastSortIdx($keys) {
    $n = $keys.Count
    if ($n -lt 2) { return , @(for ($i = 0; $i -lt $n; $i++) { $i }) }
    $isArr = $keys[0] -is [array]
    $kt = @{}; $kd = @{}; $ks = @{}; $kl = @{}
    for ($i = 0; $i -lt $n; $i++) {
        $k = $keys[$i]
        if (($k -is [array]) -ne $isArr) { return $null }
        $comps = $k; if (-not $isArr) { $comps = , $k }
        $kl[$i] = $comps.Count
        for ($c = 0; $c -lt $comps.Count; $c++) {
            $v = $comps[$c]; $id = "$i,$c"
            if ($null -eq $v) { $kt[$id] = 0; continue }
            if ($v -is [array]) { return $null }
            if (IsNum $v) { $kt[$id] = 1; $kd[$id] = [double]$v } else { $kt[$id] = 2 }
            $ks[$id] = Str $v
        }
    }
    $src = @(for ($i = 0; $i -lt $n; $i++) { $i })
    $w = 1
    while ($w -lt $n) {
        $src = @(for ($lo = 0; $lo -lt $n; $lo += 2 * $w) {
                $mid = $lo + $w; if ($mid -gt $n) { $mid = $n }
                $hi = $lo + 2 * $w; if ($hi -gt $n) { $hi = $n }
                $i = $lo; $j = $mid
                while ($i -lt $mid -and $j -lt $hi) {
                    $a = $src[$j]; $b = $src[$i]              # Cmp(key[a], key[b]) < 0 takes a (the right run) first
                    $la = $kl[$a]; $lb = $kl[$b]; $m = $la; if ($lb -lt $m) { $m = $lb }
                    $r = 0
                    for ($c = 0; $c -lt $m -and $r -eq 0; $c++) {
                        $ta = $kt["$a,$c"]; $tb = $kt["$b,$c"]
                        if ($ta -eq 0 -or $tb -eq 0) { $r = [int]($ta -ne 0) - [int]($tb -ne 0) }
                        elseif ($ta -eq 1 -and $tb -eq 1) { $da = $kd["$a,$c"]; $db = $kd["$b,$c"]; if ($da -lt $db) { $r = -1 } elseif ($da -gt $db) { $r = 1 } }
                        else { $r = [string]::CompareOrdinal($ks["$a,$c"], $ks["$b,$c"]) }
                    }
                    if ($r -eq 0 -and $isArr) { $r = [int]($la -gt $lb) - [int]($la -lt $lb) }
                    if ($r -lt 0) { $a; $j++ } else { $b; $i++ }
                }
                while ($i -lt $mid) { $src[$i]; $i++ }
                while ($j -lt $hi) { $src[$j]; $j++ }
            })
        $w *= 2
    }
    , $src
}
function Sorted($list) {
    $src = @($list)
    $idx = FastSortIdx $src
    if ($null -eq $idx) { return SortWith $src { param($a, $b) Cmp $a $b } }
    , @(foreach ($i in $idx) { , $src[$i] })
}
function SortOn($list, [scriptblock]$key) {
    $src = @($list)
    $keys = @(foreach ($x in $src) { , (& $key $x) })
    $idx = FastSortIdx $keys
    if ($null -eq $idx) {
        $pairs = @(for ($i = 0; $i -lt $src.Count; $i++) { @{ k = $keys[$i]; v = $src[$i] } })
        $s = SortWith $pairs { param($a, $b) Cmp $a.k $b.k }
        return , @(foreach ($p in $s) { , $p.v })
    }
    , @(foreach ($i in $idx) { , $src[$i] })
}
function Nub($list) { $seen = @{}; , @(foreach ($x in @($list)) { $k = "~$x"; if (-not $seen.ContainsKey($k)) { $seen[$k] = 1; $x } }) }
function MaxOf($list) { $m = $null; foreach ($x in @($list)) { if ($null -eq $m -or (Cmp $x $m) -ge 0) { $m = $x } }; $m }
function MinOf($list) { $m = $null; foreach ($x in @($list)) { if ($null -eq $m -or (Cmp $x $m) -lt 0) { $m = $x } }; $m }
function Keys($h) { , @(foreach ($k in $h.Keys) { $k }) }
function SortedKeys($h) { Sorted (Keys $h) }

# ================================================================ dates
function DaysBetween([string]$a, [string]$b) { ([datetime]$b - [datetime]$a).Days }
function AddDays([string]$d, [int]$n) { ([datetime]$d).AddDays($n).ToString('yyyy-MM-dd') }
function SLt([string]$a, [string]$b) { [string]::CompareOrdinal($a, $b) -lt 0 }
function SGt([string]$a, [string]$b) { [string]::CompareOrdinal($a, $b) -gt 0 }
function NormDate([string]$d) {
    if ($null -eq $d -or $d -cnotmatch '^(\d{4})[-/.](\d{1,2})[-/.](\d{1,2})$') { return $null }
    $y = [int]$Matches[1]; $m = [int]$Matches[2]; $dd = [int]$Matches[3]
    if ($m -lt 1 -or $m -gt 12 -or $dd -lt 1 -or $dd -gt 31) { return $null }
    '{0:D4}-{1:D2}-{2:D2}' -f $y, $m, $dd
}

# ================================================================ files
function ReadText([string]$path) {                    # the file as text, or $null; a UTF-8 BOM is dropped
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $null }
    $t = Get-Content -LiteralPath $path -Raw -Encoding UTF8
    if ($null -eq $t) { return '' }
    if ($t.Length -gt 0 -and $t[0] -eq [char]0xFEFF) { $t = $t.Substring(1) }
    $t
}
# Files are written as Perl writes them: UTF-8 with no byte-order mark, the text's own line endings. Windows
# PowerShell 5.1's -Encoding UTF8 always adds a BOM and CLM refuses [Text.Encoding], so the bytes are made here.
function Utf8Bytes([string]$t) {
    if ($null -eq $t -or $t.Length -eq 0) { return , @() }
    if ($t -cmatch '^[\x00-\x7F]*$') { return , ([byte[]][char[]]$t) }
    $n = $t.Length; $i = 0
    $out = @(while ($i -lt $n) {                        # the loop's output is the byte list (no ArrayList in CLM)
            $c = [int]$t[$i]; $i++
            if ($c -ge 0xD800 -and $c -le 0xDBFF -and $i -lt $n -and [int]$t[$i] -ge 0xDC00 -and [int]$t[$i] -le 0xDFFF) { $c = 0x10000 + (($c - 0xD800) * 0x400) + ([int]$t[$i] - 0xDC00); $i++ }
            if ($c -lt 0x80) { $c }
            elseif ($c -lt 0x800) { 0xC0 -bor ($c -shr 6); 0x80 -bor ($c -band 0x3F) }
            elseif ($c -lt 0x10000) { 0xE0 -bor ($c -shr 12); 0x80 -bor (($c -shr 6) -band 0x3F); 0x80 -bor ($c -band 0x3F) }
            else { 0xF0 -bor ($c -shr 18); 0x80 -bor (($c -shr 12) -band 0x3F); 0x80 -bor (($c -shr 6) -band 0x3F); 0x80 -bor ($c -band 0x3F) }
        })
    , ([byte[]]$out)
}
function WriteBytes([string]$path, $bytes) {
    if (@($bytes).Count -eq 0) { $null = New-Item -ItemType File -Path $path -Force; return }   # Set-Content writes nothing for no bytes
    Set-Content -LiteralPath $path -Value ([byte[]]$bytes) -Encoding Byte
}
function WriteText([string]$path, [string]$text) { WriteBytes $path (Utf8Bytes $text) }
function WriteBom([string]$path, [string]$text) {     # Excel wants the BOM to read UTF-8 (Perl's CSVs carry one too)
    $x = Utf8Bytes $text
    WriteBytes $path ([byte[]](@([byte]0xEF, [byte]0xBB, [byte]0xBF) + $x))
}
function AppendText([string]$path, [string]$text) {
    if (-not (Test-Path -LiteralPath $path)) { WriteText $path $text; return }
    $b = Utf8Bytes $text
    if (@($b).Count) { Add-Content -LiteralPath $path -Value ([byte[]]$b) -Encoding Byte }
}
function ListDir([string]$dir) {
    if (-not (Test-Path -LiteralPath $dir -PathType Container)) { return , @() }
    Sorted @(Get-ChildItem -LiteralPath $dir -File | ForEach-Object { $_.Name })
}
function EnsureDir([string]$d) { if (-not (Test-Path -LiteralPath $d -PathType Container)) { New-Item -ItemType Directory -Path $d | Out-Null } }

# ================================================================ ledger: the plain-text double-entry journal
$script:PREC = @{}
function ParseAmount([string]$s) {
    if ($null -eq $s -or $s -cnotmatch '\S') { return $null }
    $s = $s.Trim()
    if ($s -cnotmatch '^(-)?\s*([^\s\d\-+.,"]+)?\s*(-)?\s*(\d[\d,]*(?:\.\d+)?|\.\d+)\s*([A-Za-z]\w*|"[^"]*")?$') { return $null }
    $neg = $Matches[1]; $sym = $Matches[2]; $neg2 = $Matches[3]; $num = $Matches[4]; $code = $Matches[5]
    $c = ''; if ($null -ne $sym) { $c = $sym } elseif ($null -ne $code) { $c = $code }
    $c = $c -creplace '^"|"$', ''
    $n = $num -replace ',', ''
    $dec = 0; if ($n -cmatch '\.(\d+)') { $dec = $Matches[1].Length }
    if (-not $script:PREC.ContainsKey($c) -or $dec -gt $script:PREC[$c]) { $script:PREC[$c] = $dec }
    $v = [double]$n; if ($neg -or $neg2) { $v = -$v }
    @{ $c = $v }
}
function AmtAdd($x, $y) { $r = @{}; foreach ($k in $x.Keys) { $r[$k] = $x[$k] }; foreach ($k in $y.Keys) { if ($r.ContainsKey($k)) { $r[$k] += $y[$k] } else { $r[$k] = $y[$k] } }; $r }
function AmtNeg($x) { $r = @{}; foreach ($k in $x.Keys) { $r[$k] = - $x[$k] }; $r }
function Tol { $p = 2; foreach ($v in $script:PREC.Values) { if ($v -gt $p) { $p = $v } }; 0.5 * [double]("1e-$p") }
function AmtZero($x) { $t = Tol; foreach ($v in $x.Values) { if ([double]$v -gt $t -or [double]$v -lt - $t) { return $false } }; $true }
function FmtFixed($v, [int]$p) {                      # sprintf "%.{p}f" for the error messages
    $neg = $v -lt 0; if ($neg) { $v = - $v }
    $scale = [double]("1e$p"); $f = Trunc ($v * $scale + 0.5)
    $s = [string]$f
    if ($p -gt 0) { $s = $s.PadLeft($p + 1, '0'); $s = $s.Substring(0, $s.Length - $p) + '.' + $s.Substring($s.Length - $p) }
    if ($neg) { "-$s" } else { $s }
}
function FormatAmount($a) {
    $parts = @(foreach ($c in (SortedKeys $a)) {
            $v = $a[$c]; if ([double]$v -lt (Tol) -and [double]$v -gt - (Tol)) { continue }
            $p = 2; if ($script:PREC.ContainsKey($c)) { $p = $script:PREC[$c] }
            $n = FmtFixed $v $p
            while ($n -cmatch '^(-?\d+)(\d{3})') { $n = $n -creplace '^(-?\d+)(\d{3})', '$1,$2' }
            if ($c -eq '') { $n } elseif ($c -cmatch '^[A-Za-z]') { "$n $c" } elseif ($c -cmatch '\s') { "$n `"$c`"" } else { "$c$n" }
        })
    if ($parts.Count) { $parts -join ', ' } else { '0' }
}
function ReadJournal([string]$file) {
    $text = ReadText $file
    if ($null -eq $text) { throw "cannot open ${file}: No such file or directory`n" }
    $j = @{ txns = @(); periodic = @(); errors = @(); txbuf = @{}; txn = 0 }
    ParseInto $j $text $file
    $j.txns = @(for ($k = 0; $k -lt $j.txn; $k++) { $j.txbuf[$k] })   # collected by index: += per transaction is quadratic
    $j.Remove('txbuf'); $j.Remove('txn')
    BalanceAll $j
    if ($j.errors.Count) { throw (($j.errors | ForEach-Object { "$_`n" }) -join '') }
    $j
}
function ParseInto($j, [string]$text, [string]$file) {
    $lineList = $text -csplit "`r?`n"
    $n = $lineList.Count; $i = 0
    while ($i -lt $n) {
        $ln = $i + 1; $line = $lineList[$i]; $i++
        if ($line -cmatch '^\s*$' -or $line -cmatch '^[;#%|*]') { continue }
        if ($line -cmatch '^\s') { $j.errors += "${file}:${ln}: unexpected indented line"; continue }
        $block = @()
        while ($i -lt $n -and $lineList[$i] -cmatch '^\s+\S') { $block += , @(($i + 1), $lineList[$i]); $i++ }
        if ($line -cmatch '^(\d[\d\/.-]*)(?:=(\d[\d\/.-]*))?\s+(?:([*!])\s+)?(.*?)\s*(?:;(.*))?$') {
            $d = $Matches[1]; $status = $Matches[3]; $payee = $Matches[4]; $cmt = $Matches[5]
            $date = NormDate $d
            if (-not $date) { $j.errors += "${file}:${ln}: bad date '$d'"; continue }
            if ($null -eq $status) { $status = '' }
            $cm = ''; if ($null -ne $cmt) { $cm = $cmt.Trim() }
            $t = @{ date = $date; status = $status; payee = $payee; comment = $cm; line = $ln; file = $file; period = $null }
            $t.postings = ParsePostings $j $block $file
            $j.txbuf[$j.txn] = $t; $j.txn++
        }
        elseif ($line -cmatch '^~\s*(.*?)\s*$') {
            $t = @{ period = $Matches[1]; line = $ln; file = $file }
            $t.postings = ParsePostings $j $block $file
            $j.periodic += $t
        }
        elseif ($line -cmatch '^P\s+') { }
        elseif ($line -cmatch '^!?include\s+(.+?)\s*$') {
            $inc = $Matches[1]
            $dir = $file -creplace '[^/\\]*$', ''
            if ($dir -ne '' -and $inc -cnotmatch '^(/|[A-Za-z]:)') { $inc = "$dir$inc" }
            $t2 = ReadText $inc
            if ($null -ne $t2) { ParseInto $j $t2 $inc } else { $j.errors += "${file}:${ln}: cannot include '$inc': No such file or directory" }
        }
        elseif ($line -cmatch '^comment\b') {
            while ($i -lt $n -and $lineList[$i] -cnotmatch '^end comment\b') { $i++ }
            $i++
        }
        elseif ($line -cmatch '^=' -or $line -cmatch '^(?:account|commodity|payee|tag|year|Y|apply|end|bucket|A|N|D|C|alias|define|assert|check)\b') { }
        else { $j.errors += "${file}:${ln}: unrecognised line: $line" }
    }
}
function ParsePostings($j, $block, [string]$file) {
    , @(foreach ($b in $block) {
            $ln = $b[0]; $body = $b[1] -creplace '^\s+', ''
            $cmt = ''
            if ($body.Contains(';') -and $body -cmatch '\s*;(.*)$') { $cmt = $Matches[1].Trim(); $body = $body -creplace '\s*;.*$', '' }
            if ($body -eq '') { continue }
            $sp = $body -csplit '(?:\s{2,}|\t)\s*', 2
            $acct = $sp[0]; $restText = $null; if ($sp.Count -gt 1) { $restText = $sp[1] }
            $virtual = 0
            if ($acct.StartsWith('(') -and $acct -cmatch '^\((.*)\)$') { $acct = $Matches[1]; $virtual = 'unbalanced' }
            elseif ($acct.StartsWith('[') -and $acct -cmatch '^\[(.*)\]$') { $acct = $Matches[1]; $virtual = 'balanced' }
            $acct = $acct.Trim()
            $amount = $null; $cost = $null
            if ($null -ne $restText -and $restText -cmatch '\S') {
                if ($restText.Contains('=')) { $restText = $restText -creplace '\s*=.*$', '' }
                if ($restText.Contains('@')) { $null = $restText -cmatch '^(.*?)\s*(?:(@@?)\s*(.*))?$'; $amt_s = $Matches[1]; $at = $Matches[2]; $price_s = $Matches[3] }
                else { $amt_s = $restText -creplace '\s+$', ''; $at = $null; $price_s = $null }   # the regex's result when there is no @
                if ($amt_s -cmatch '^\s*(-?)\s*(\d+)(?:\.(\d+))?\s*$') {    # fast path: what ParseAmount returns for a plain number
                    $dec = 0; if ($null -ne $Matches[3]) { $dec = $Matches[3].Length }
                    if (-not $script:PREC.ContainsKey('') -or $dec -gt $script:PREC['']) { $script:PREC[''] = $dec }
                    $num = $Matches[2]; if ($null -ne $Matches[3]) { $num = "$num.$($Matches[3])" }
                    $v = [double]$num; if ($Matches[1]) { $v = -$v }
                    $amount = @{ '' = $v }
                }
                else { $amount = ParseAmount $amt_s }
                if ($null -eq $amount) { $j.errors += "${file}:${ln}: bad amount '$amt_s'"; continue }
                if ($at) {
                    $p = ParseAmount $price_s
                    if ($null -eq $p) { $j.errors += "${file}:${ln}: bad price '$price_s'"; continue }
                    $qc = @($amount.Keys)[0]; $pc = @($p.Keys)[0]
                    if ($at -eq '@') { $cost = @{ $pc = $amount[$qc] * $p[$pc] } }
                    else { $sg = 1; if ($amount[$qc] -lt 0) { $sg = -1 }; $cost = @{ $pc = $sg * $p[$pc] } }
                }
            }
            @{ account = $acct; amount = $amount; cost = $cost; virtual = $virtual; comment = $cmt; line = $ln }
        })
}
function BalanceAll($j) {
    $tol = Tol                                        # PREC is final once the journal is parsed: AmtZero's tolerance, once
    foreach ($t in @($j.txns) + @($j.periodic)) {
        $sum = @{}; $elided = @()
        foreach ($p in $t.postings) {
            if ('unbalanced' -eq $p.virtual) { continue }    # string first: int -eq 'text' fails a conversion (slow)
            if ($null -ne $p.amount) {
                $add = $p.amount; if ($null -ne $p.cost) { $add = $p.cost }
                foreach ($k in $add.Keys) { if ($sum.ContainsKey($k)) { $sum[$k] += $add[$k] } else { $sum[$k] = $add[$k] } }
            }
            else { $elided += $p }
        }
        $where = "$($t.file):$($t.line)"
        if ($elided.Count -gt 1) { $j.errors += "${where}: more than one posting without an amount"; continue }
        if ($elided.Count -eq 1) { $elided[0].amount = AmtNeg $sum; continue }
        if ($null -ne $t.period) { continue }
        $zero = $true; foreach ($v in $sum.Values) { if ([double]$v -gt $tol -or [double]$v -lt - $tol) { $zero = $false; break } }   # AmtZero
        if (-not $zero) { $j.errors += "${where}: transaction does not balance (off by $(FormatAmount $sum))" }
    }
}
function JournalPostings($j) {                        # every posting, transactions sorted by date (stable: file order within a day)
    $txns = SortOn $j.txns { param($t) $t.date }
    , @(foreach ($t in $txns) { foreach ($p in $t.postings) {
                @{ date = $t.date; payee = $t.payee; status = $t.status; account = $p.account; amount = $p.amount; comment = $p.comment; txn = $t } } })
}
function AmtNum($a) { if ($null -eq $a) { return 0.0 }; Sum @($a.Values) }

# ================================================================ scrum: the journal read as backlog and sprints
function ParseMeta([string]$c) {                      # "id: A-1, prio: 2, owner: Lee, Ann" -> @{id; prio; owner}
    $m = @{}
    if ($null -eq $c) { return $m }
    foreach ($f in ($c -csplit '\s*,\s*(?=\w+\s*:)')) {
        if ($f -cnotmatch '^\s*(\w+)\s*:\s*(.*?)\s*$') { continue }
        $k = $Matches[1].ToLower(); $v = $Matches[2]
        if ($v -cmatch '^"(.*)"$') { $v = $Matches[1] }
        $m[$k] = $v
    }
    $m
}
function LoadScrum([string]$file, [string]$asOf, [string]$until) {
    $j = ReadJournal $file
    $s = @{ j = $j; file = $file; today = $asOf; until = $until; memo = @{}; unit = 'SP' }
    $all = JournalPostings $j
    $ps = @(foreach ($p in $all) { if ($until -and (SGt $p.date $until)) { continue }; $p })
    $s.postings = $ps
    $items = @{}; $teams = @{}; $sprints = @{}; $orderBuf = @{}; $orderN = 0
    $metaCache = @{}                                  # comment text -> its ParseMeta (copied before use: $meta is changed below)
    foreach ($p in $ps) {
        $acct = $p.account
        if ($acct -cmatch '^Backlog:(?!Master)([^:]+)') { $teams[$Matches[1]] = 1 }
        if ($acct -cmatch '^Sprint:(\d+):([^:]+)') { $sprints[$Matches[1]] = 1; $teams[$Matches[2]] = 1 }
        $tc = $p.txn.comment; if ($null -eq $tc) { $tc = '' }
        $pc = $p.comment; if ($null -eq $pc) { $pc = '' }
        if (-not $metaCache.ContainsKey("t$tc")) { $metaCache["t$tc"] = ParseMeta $tc }
        if (-not $metaCache.ContainsKey("t$pc")) { $metaCache["t$pc"] = ParseMeta $pc }
        $meta = @{}; $m0 = $metaCache["t$tc"]; foreach ($k in $m0.Keys) { $meta[$k] = $m0[$k] }
        $pm = $metaCache["t$pc"]
        foreach ($k in $pm.Keys) { $meta[$k] = $pm[$k] }
        $id = $meta['id']
        if (-not $id) { continue }
        $it = $items[$id]
        if ($null -eq $it) {
            $title = $p.payee
            if ($p.payee -cmatch ('(?i)^\s*(?:intake|new|add)\s+' + [regex]::Escape($id) + '\s*(.*)$')) { $title = $Matches[1] }
            $it = @{ id = $id; created = $p.date; meta = @{}; bal = [ordered]@{}; history = @(); title = $title; punts = @(); blocked_since = $null; hold_since = $null }
            $items[$id] = $it; $orderBuf[$orderN] = $id; $orderN++
        }
        foreach ($k in $meta.Keys) { if ($k -ceq 'id') { continue }; $it.meta[$k] = $meta[$k] }
        if ($it.meta['title']) { $it.title = $it.meta['title'] }
        foreach ($k in @('blocked', 'hold')) {
            if (-not $meta.ContainsKey($k)) { continue }
            $on = ($null -ne $meta[$k]) -and ($meta[$k] -cne '')
            if (-not $on) { $it["${k}_since"] = $null } elseif ($null -eq $it["${k}_since"]) { $it["${k}_since"] = $p.date }
        }
        $pts = 0.0; if ($null -ne $p.amount) { foreach ($av in $p.amount.Values) { $pts += [double]$av } }   # AmtNum
        if ($pts -gt 0) {
            if ($acct -cmatch ':Committed$' -and -not $meta.ContainsKey('punt')) { $it.meta.Remove('punt') }
            if ($acct -cmatch ':Done$') { $it.meta.Remove('redo'); $it.meta.Remove('pass') }
        }
        $cur = $it.bal[$acct]                         # the indexer is allowed in CLM; a balance is never $null
        if ($null -ne $cur) { $it.bal[$acct] = $cur + $pts } else { $it.bal[$acct] = $pts }
        $it.history += @{ date = $p.date; payee = $p.payee; account = $acct; points = $pts }
        if ($meta['punt'] -and $meta['punt'] -cne '' -and $pts -gt 0 -and $acct -cmatch '^Backlog:([^:]+)$') {
            $team = $Matches[1]; $from = $null
            for ($x = $it.history.Count - 1; $x -ge 0; $x--) { $h = $it.history[$x]; if ($h.points -lt 0 -and $h.account -cmatch '^Sprint:(\d+):') { $from = $h; break } }
            $sp = $null; if ($from -and $from.account -cmatch '^Sprint:(\d+):') { $sp = $Matches[1] }
            $it.punts += @{ date = $p.date; sprint = $sp; team = $team; why = $meta['punt']; points = $pts }
        }
    }
    $order = @(for ($k = 0; $k -lt $orderN; $k++) { $orderBuf[$k] })
    foreach ($id in $order) {
        $it = $items[$id]
        $loc = Sorted @(foreach ($a in $it.bal.Keys) { if ($it.bal[$a] -gt 1e-9) { $a } })
        $it.location = $loc
        $it.points = Sum @(foreach ($a in $loc) { $it.bal[$a] })
        $l = ''; if ($loc.Count) { $l = $loc[0] }
        $it.sprint = $null; $it.team = $null
        if ($l -ceq 'Backlog:Master') { $it.state = 'master'; $it.team = 'Master' }
        elseif ($l -cmatch '^Backlog:([^:]+)$') { $it.state = 'backlog'; $it.team = $Matches[1] }
        elseif ($l -cmatch '^Sprint:(\d+):([^:]+):(Committed|Done|Carryover|Removed)$') {
            $it.state = @{ Committed = 'committed'; Done = 'done'; Carryover = 'carryover'; Removed = 'removed' }[$Matches[3]]
            $it.sprint = $Matches[1]; $it.team = $Matches[2]
        }
        elseif ($l -eq '') { $it.state = 'closed' }
        else { $it.state = $l }
        if ($null -eq $it.team) { $it.team = $it.meta['team'] }
        $it.owner = $it.meta['owner']
        $it.blocked = $null; if ($it.meta['blocked']) { $it.blocked = $it.meta['blocked'] }
        $it.hold = $null; if ($it.meta['hold']) { $it.hold = $it.meta['hold'] }
        $it.age = DaysBetween $it.created $asOf
    }
    $s.items = $items
    $s.teams = SortedKeys $teams
    $s.sprints = SortOn (Keys $sprints) { param($k) [int]$k }
    $s.current = $null; if ($s.sprints.Count) { $s.current = $s.sprints[$s.sprints.Count - 1] }
    $s.capacity = @{}
    foreach ($t in $j.periodic) {
        if ($t.period -notmatch '^sprint\s+(\d+)') { continue }
        $n = $Matches[1]
        if (-not $s.capacity.ContainsKey($n)) { $s.capacity[$n] = @{} }
        foreach ($p in $t.postings) { if ($null -ne $p.amount) { $s.capacity[$n][$p.account] = AmtNum $p.amount } }
    }
    $s
}
function AllItems($s) {                               # by priority, then created, then id
    if (-not $s.memo.ContainsKey('items')) {
        $s.memo.items = SortOn @($s.items.Values) { param($i) $pr = $i.meta['prio']; if ($null -eq $pr) { $pr = 9999 }; , @($pr, $i.created, $i.id) }
    }
    , $s.memo.items
}
function Items($s, [string]$state, [string]$team, [string]$owner, $sprint, [string]$epic) {
    , @(foreach ($i in (AllItems $s)) {
            if ($state -and $i.state -cne $state) { continue }
            if ($team -and ($null -eq $i.team -or $i.team -cne $team)) { continue }
            if ($owner -and ($null -eq $i.owner -or $i.owner -cne $owner)) { continue }
            if ($sprint -and ($null -eq $i.sprint -or [int]$i.sprint -ne [int]$sprint)) { continue }
            if ($epic) { $e = $i.meta['epic']; if ($null -eq $e) { $e = '' }; if ($e -cne $epic) { continue } }
            $i
        })
}
function SprintSummary($s, $n) {
    if ($null -eq $n) { $n = $s.current }
    $key = "~$n"
    if ($s.memo.ContainsKey($key)) { return $s.memo[$key] }
    $tot = @{ team = 'Total'; committed = 0.0; done = 0.0; carryover = 0.0; removed = 0.0; open = 0.0; capacity = 0.0; pct = 0; load = $null }
    if ($null -eq $n) { $r = @{ sprint = $null; teams = @{}; totals = $tot }; $s.memo[$key] = $r; return $r }
    $t = @{}
    if (-not $s.memo.ContainsKey('bysprint')) {         # every Sprint:N:Team:Bucket posting, grouped by N, in posting order
        $bs = @{}
        foreach ($p in $s.postings) {
            if ($p.account -cnotmatch '^Sprint:(\d+):([^:]+):(\w+)') { continue }
            $sn = $Matches[1]; if (-not $bs.ContainsKey($sn)) { $bs[$sn] = @{ n = 0 } }
            $g = $bs[$sn]; $g[$g.n] = @($Matches[2], $Matches[3], (AmtNum $p.amount)); $g.n++
        }
        $s.memo.bysprint = $bs
    }
    $grp = $s.memo.bysprint["$n"]; $gn = 0; if ($null -ne $grp) { $gn = $grp.n }
    for ($gi = 0; $gi -lt $gn; $gi++) {
        $row = $grp[$gi]
        $team = $row[0]; $bucket = $row[1]
        $pts = $row[2]
        if (-not $t.ContainsKey($team)) { $t[$team] = @{ team = $team; committed = 0.0; done = 0.0; carryover = 0.0; removed = 0.0; open = 0.0 } }
        $r = $t[$team]
        if ($bucket -ceq 'Committed' -and $pts -gt 0) { $r.committed += $pts }
        if ($bucket -ceq 'Committed') { $r.open += $pts }
        if ($bucket -ceq 'Done') { $r.done += $pts }
        if ($bucket -ceq 'Carryover' -and $pts -gt 0) { $r.carryover += $pts }
        if ($bucket -ceq 'Removed') { $r.removed += $pts }
    }
    foreach ($team in (SortedKeys $t)) {
        $r = $t[$team]
        $cap = 0.0; if ($s.capacity.ContainsKey("$n") -and $s.capacity["$n"].ContainsKey($team)) { $cap = $s.capacity["$n"][$team] }
        $r.capacity = $cap
        $r.pct = Pct $r.done $r.committed
        $r.load = PctU $r.committed $r.capacity
        $r.open_items = SprintItems $s 'committed' $n $team
        $r.carry_items = SprintItems $s 'carryover' $n $team
        foreach ($k in @('committed', 'done', 'carryover', 'removed', 'open', 'capacity')) { $tot[$k] += $r[$k] }
    }
    $tot.pct = Pct $tot.done $tot.committed
    $tot.load = PctU $tot.committed $tot.capacity
    $r = @{ sprint = "$n"; teams = $t; totals = $tot }
    $s.memo[$key] = $r
    $r
}
function SprintItems($s, [string]$state, $n, [string]$team) {   # = Items $s -state X -sprint N -team T, from one index per load
    if (-not $n -or -not $team) { return Items $s -state $state -sprint $n -team $team }
    if (-not $s.memo.ContainsKey('sprintitems')) {
        $ix = @{}
        foreach ($i in (AllItems $s)) {
            if (($i.state -cne 'committed' -and $i.state -cne 'carryover') -or $null -eq $i.sprint -or $null -eq $i.team) { continue }
            $k = "$($i.state)|$([int]$i.sprint)|$($i.team)"
            if (-not $ix.ContainsKey($k)) { $ix[$k] = @{ n = 0 } }
            $g = $ix[$k]; $g[$g.n] = $i; $g.n++
        }
        $s.memo.sprintitems = $ix
    }
    $g = $s.memo.sprintitems["$state|$([int]$n)|$team"]
    if ($null -eq $g) { return , @() }
    , @(for ($k = 0; $k -lt $g.n; $k++) { $g[$k] })
}
function InProgress($s, $team) { $r = SprintSummary $s $s.current; if (-not $r.teams.ContainsKey($team)) { return $false }; $r.teams[$team].open -gt 0 }
function Velocity($s, [int]$last = 3) {
    $key = "velocity$last"
    if ($s.memo.ContainsKey($key)) { return $s.memo[$key] }
    $v = @{}
    foreach ($n in $s.sprints) {
        $sum = SprintSummary $s $n
        foreach ($team in (SortedKeys $sum.teams)) {
            $r = $sum.teams[$team]
            if (-not $v.ContainsKey($team)) { $v[$team] = @() }
            $v[$team] += @{ sprint = $n; committed = $r.committed; done = $r.done; capacity = $r.capacity }
        }
    }
    $avg = @{}; $cnt = @{}
    foreach ($team in $v.Keys) {
        $rows = $v[$team]
        $done = @(foreach ($x in $rows) { $x.done })
        $running = ($null -ne $s.current) -and ([int]$rows[$rows.Count - 1].sprint -eq [int]$s.current) -and (InProgress $s $team)
        if ($done.Count -gt 1 -and $running) { $done = @($done[0..($done.Count - 2)]) }
        if ($done.Count -gt $last) { $done = @($done[($done.Count - $last)..($done.Count - 1)]) }
        if ($done.Count) { $avg[$team] = (Sum $done) / $done.Count } else { $avg[$team] = 0 }
        if ($rows.Count -eq 1 -and $running) { $cnt[$team] = 0 } else { $cnt[$team] = $done.Count }
    }
    $r = @{ team = $v; avg = $avg; completed = $cnt }
    $s.memo[$key] = $r
    $r
}
function Epics($s) {
    if ($s.memo.ContainsKey('epics')) { return , $s.memo.epics }
    $by = @{}; $keys = @()
    foreach ($i in (AllItems $s)) { $e = $i.meta['epic']; if ($null -eq $e) { $e = '(none)' }; if (-not $by.ContainsKey($e)) { $by[$e] = @(); $keys += $e }; $by[$e] += $i }
    $out = @(foreach ($e in (Sorted $keys)) {
            $its = @($by[$e])
            $tome = '(none)'; foreach ($i in $its) { if ($null -ne $i.meta['tome']) { $tome = $i.meta['tome']; break } }
            $r = @{ epic = $e; tome = $tome; items = $its; total = 0.0; done = 0.0; wip = 0.0; backlog = 0.0; removed = 0.0 }
            foreach ($i in $its) {
                foreach ($a in $i.bal.Keys) { if ($a -cmatch ':Done$') { $r.done += $i.bal[$a] }; if ($a -cmatch ':Removed$') { $r.removed += $i.bal[$a] } }
                if ($i.state -ceq 'committed' -or $i.state -ceq 'carryover') { $r.wip += $i.points }
                if ($i.state -ceq 'backlog' -or $i.state -ceq 'master') { $r.backlog += $i.points }
            }
            $r.total = $r.done + $r.wip + $r.backlog
            $r.pct = Pct $r.done $r.total
            $r.open = [int]($r.wip -gt 0)
            $r
        })
    $s.memo.epics = SortOn $out { param($x) , @($x.tome, $x.epic) }
    , $s.memo.epics
}
function Backlog($s, [string]$scope) {
    if (-not $scope -or $scope.ToLower() -eq 'master') { Items $s -state master } else { Items $s -state backlog -team $scope }
}
function Members($s, [string]$team) {
    $m = @{}
    foreach ($i in (AllItems $s)) {
        if (-not $i.owner) { continue }
        $it_team = $i.team; if ($null -eq $it_team) { $it_team = '' }
        if ($team -and $it_team -cne $team) { continue }
        if (-not $m.ContainsKey($i.owner)) { $m[$i.owner] = @{ name = $i.owner; team = $i.team; wip = @(); done = @(); backlog = @() } }
        $r = $m[$i.owner]
        if ($null -eq $r.team) { $r.team = $i.team }
        if ($i.state -ceq 'committed') { $r.wip += $i }
        if ($i.state -ceq 'done' -and $s.current -and $null -ne $i.sprint -and [int]$i.sprint -eq [int]$s.current) { $r.done += $i }
        if ($i.state -ceq 'backlog' -or $i.state -ceq 'master') { $r.backlog += $i }
    }
    foreach ($r in $m.Values) {
        foreach ($k in @('wip', 'done', 'backlog')) { $r[$k] = SortOn $r[$k] { param($i) $pr = $i.meta['prio']; if ($null -eq $pr) { $pr = 9999 }; , @($pr, $i.created) } }
        $r.wip_points = Sum @(foreach ($i in $r.wip) { $i.points })
    }
    $m
}
function Unassigned($s, [string]$team) {
    , @(foreach ($i in (AllItems $s)) { if (-not $i.owner -and $i.state -ceq 'committed' -and (-not $team -or $i.team -ceq $team)) { $i } })
}
function Blocked($s, [string]$team) {
    , @(foreach ($i in (AllItems $s)) {
            if (-not $i.blocked) { continue }
            if ($i.state -cne 'committed' -and $i.state -cne 'carryover') { continue }
            $t = $i.team; if ($null -eq $t) { $t = '' }
            if ($team -and $t -cne $team) { continue }
            $i
        })
}
function BlockedDays($s, $i) { if ($null -ne $i.blocked_since) { DaysBetween $i.blocked_since $s.today } else { 0 } }

# ---------------------------------------------------------------- text tables
function TextTable($hdr, $rows, $right, $title) {
    $all = @(, $hdr) + @($rows)
    $nc = $hdr.Count
    $w = @(for ($c = 0; $c -lt $nc; $c++) { $m = 0; foreach ($r in $all) { $l = (Str $r[$c]).Length; if ($l -gt $m) { $m = $l } }; $m })
    $isR = @{}; foreach ($c in @($right)) { $isR["$c"] = 1 }
    $dash = @(foreach ($x in $w) { '-' * $x })
    $out = ''; if ($null -ne $title) { $out = "$title`n" }
    $out += (@(foreach ($row in (@(, $hdr) + @(, $dash) + @($rows))) {
                $parts = @(for ($c = 0; $c -lt $nc; $c++) { $v = Str $row[$c]; if ($isR.ContainsKey("$c")) { $v.PadLeft($w[$c]) } else { $v.PadRight($w[$c]) } })
                (($parts -join '  ') -creplace '\s+$', '') + "`n"
            }) -join '')
    $out
}
$script:ITEM_HDR = @('ID', 'SP', 'Prio', 'Tome', 'Epic', 'Owner', 'Age', 'Title', 'Blocked')
$script:ITEM_R = @(1, 2, 6)
function ItemRow($i) { , @($i.id, $i.points, $i.meta['prio'], $i.meta['tome'], $i.meta['epic'], $i.owner, $i.age, $i.title, $i.blocked) }

function SprintText($s, $n) {
    $r = SprintSummary $s $n
    if ($null -eq $r.sprint) { return "no sprint yet -- put 'sprint 1' in a stand-up file and commit tasks to it (commit ID owner)`n" }
    $row = { param($name, $t) $cap = ''; if ($t.capacity) { $cap = $t.capacity }; $ld = ''; if ($null -ne $t.load) { $ld = "$($t.load)%" }
        , @($name, $cap, $t.committed, $t.done, $t.open, $t.carryover, $t.removed, "$($t.pct)%", $ld) }
    $rows = @(foreach ($team in (SortedKeys $r.teams)) { , (& $row $team $r.teams[$team]) }) + @(, (& $row 'Total' $r.totals))
    $out = TextTable @('Team', 'Cap', 'Commit', 'Done', 'Open', 'Carry', 'Removed', 'Done%', 'Load%') $rows @(1..8) "Teams: sprint $($r.sprint)"
    foreach ($team in (SortedKeys $r.teams)) {
        $open = @($r.teams[$team].open_items)
        if ($open.Count) { $out += "`n$team open tasks ($($open.Count)):`n" + (TextTable $script:ITEM_HDR @(foreach ($i in $open) { , (ItemRow $i) }) $script:ITEM_R $null) }
    }
    $out
}
function VelocityText($s, [int]$last = 3) {
    $v = Velocity $s $last
    $out = ''
    foreach ($team in (SortedKeys $v.team)) {
        $rows = @(foreach ($x in $v.team[$team]) { $cap = ''; if ($x.capacity) { $cap = $x.capacity }; $pc = ''; if ($x.committed) { $pc = "$(Pct $x.done $x.committed)%" }; , @($x.sprint, $cap, $x.committed, $x.done, $pc) })
        $n = $v.completed[$team]
        if ($n) { $out += "$team  (avg velocity $(Fmt1 $v.avg[$team]) over the last $n completed sprint$(Plural $n))`n" }
        else { $out += "$team  (first sprint still running: $(Fmt1 $v.avg[$team]) done so far, no completed sprint yet)`n" }
        $out += (TextTable @('Sprint', 'Cap', 'Commit', 'Done', 'Done%') $rows @(0..4) $null) + "`n"
    }
    $out
}
function BacklogText($s, [string]$scope) {
    $its = Backlog $s $scope
    $name = $scope; if (-not $scope -or $scope.ToLower() -eq 'master') { $name = 'Master' }
    "$name backlog: $($its.Count) tasks, $(Trunc (Sum @(foreach ($i in $its) { $i.points }))) SP`n" + (TextTable $script:ITEM_HDR @(foreach ($i in $its) { , (ItemRow $i) }) $script:ITEM_R $null)
}
function MembersText($s, [string]$team) {
    $m = Members $s $team
    $out = ''
    foreach ($name in (SortedKeys $m)) {
        $r = $m[$name]
        $tm = $r.team; if ($null -eq $tm) { $tm = '-' }
        $out += "$name ($tm)  WIP $(Trunc $r.wip_points) SP in $($r.wip.Count) tasks, done this sprint $($r.done.Count), queued $($r.backlog.Count)`n"
        foreach ($k in @('wip', 'done', 'backlog')) {
            if ($r[$k].Count) { $out += "  ${k}:`n"; foreach ($i in $r[$k]) { $out += '    ' + $i.id.PadRight(10) + ' ' + ([string](Trunc $i.points)).PadLeft(3) + "  $($i.title)`n" } }
        }
    }
    $un = Unassigned $s $team
    if ($un.Count) { $out += 'UNASSIGNED committed tasks: ' + (@(foreach ($i in $un) { $i.id }) -join ', ') + "`n" }
    $out
}
function EpicsText($s) {
    $rows = @(foreach ($e in (Epics $s)) { , @($e.tome, $e.epic, $e.items.Count, $e.total, $e.done, $e.wip, $e.backlog, "$($e.pct)%") })
    TextTable @('Tome', 'Epic', 'Tasks', 'Total', 'Done', 'In sprint', 'Backlog', 'Done%') $rows @(2..7) 'Epics by tome'
}
function Ceil($x) { $i = Trunc $x; if ($x -gt $i) { $i + 1 } else { $i } }
function Roadmap($s) {
    if ($s.memo.ContainsKey('roadmap')) { return $s.memo.roadmap }
    $v = Velocity $s
    $cur = $s.current
    $rows = @(foreach ($e in (Epics $s)) {
            $ps = @{}; $teams = @{}; $blocked = 0
            foreach ($i in $e.items) {
                if ($i.team -and $i.team -cne 'Master') { $teams[$i.team] = 1 }
                if ($i.blocked -and ($i.state -ceq 'committed' -or $i.state -ceq 'carryover')) { $blocked++ }
                foreach ($h in $i.history) {
                    if ($h.points -le 0 -or $h.account -cnotmatch '^Sprint:(\d+):[^:]+:(Committed|Done)$') { continue }
                    $sn = $Matches[1]; $b = $Matches[2].ToLower()
                    if (-not $ps.ContainsKey($sn)) { $ps[$sn] = @{ committed = 0.0; done = 0.0 } }
                    $ps[$sn][$b] += $h.points
                }
            }
            $sn = SortOn (Keys $ps) { param($k) [int]$k }
            $remaining = $e.wip + $e.backlog
            $vel = Sum @(foreach ($t in $teams.Keys) { if ($v.avg.ContainsKey($t)) { $v.avg[$t] } else { 0 } })
            $fc = $null; if ($remaining -le 0) { $fc = 0 } elseif ($vel -gt 0) { $fc = Ceil ($remaining / $vel) }
            $end = $null
            if ($remaining -le 0) { if ($sn.Count) { $end = [int]$sn[$sn.Count - 1] } } elseif ($null -ne $fc -and $null -ne $cur) { $end = [int]$cur + $fc }
            $first = $null; if ($sn.Count) { $first = [int]$sn[0] }
            @{ tome = $e.tome; epic = $e.epic; teams = (SortedKeys $teams); first = $first; end = $end; done = $e.done; total = $e.total
                remaining = $remaining; pct = $e.pct; forecast_sprints = $fc; velocity = $vel; blocked = $blocked; per_sprint = $ps }
        })
    $bounds = @(foreach ($r in $rows) { if ($null -ne $r.first) { $r.first }; if ($null -ne $r.end) { $r.end } }) + @(if ($null -ne $cur) { [int]$cur })
    $sp = @(); if ($bounds.Count) { $lo = MinOf $bounds; $hi = MaxOf $bounds; $sp = @($lo..$hi) }
    $r = @{ sprints = $sp; current = $cur; epics = $rows }
    $s.memo.roadmap = $r
    $r
}
function RoadmapText($s) {
    $r = Roadmap $s
    $sp = @($r.sprints)
    if (-not $sp.Count -or -not @($r.epics).Count) { return "no sprints yet`n" }
    $cur = $r.current
    $tail = ''; if ($null -ne $cur) { $tail = " (current $cur; past it is a forecast at the teams' velocity)" }
    $out = "Roadmap: epics by tome, sprints $($sp[0])-$($sp[$sp.Count - 1])$tail`n"
    $out += "  # done  = in progress  . forecast  ^ current sprint`n"
    $w = 0; foreach ($e in $r.epics) { $l = "$($e.tome) > $($e.epic)".Length; if ($l -gt $w) { $w = $l } }
    $out += ''.PadRight($w) + '  ' + (@(foreach ($x in $sp) { if ($null -ne $cur -and $x -eq [int]$cur) { '^' } else { ' ' } }) -join '') + "`n"
    foreach ($e in $r.epics) {
        $bar = @(foreach ($x in $sp) {
                $p = $null; if ($e.per_sprint.ContainsKey("$x")) { $p = $e.per_sprint["$x"] }
                if ($p -and $p.done) { '#' } elseif ($p -and $p.committed) { '=' }
                elseif ($null -ne $e.end -and $null -ne $cur -and $x -gt [int]$cur -and $x -le $e.end) { '.' } else { ' ' }
            }) -join ''
        $eta = 'no velocity yet'; if ($e.remaining -le 0) { $eta = 'done' } elseif ($null -ne $e.end) { $eta = "ETA sprint $($e.end)" }
        $bl = ''; if ($e.blocked) { $bl = "  BLOCKED $($e.blocked)" }
        $out += "$($e.tome) > $($e.epic)".PadRight($w) + "  $bar  " + ([string]$e.pct).PadLeft(3) + "%  $(Trunc $e.done)/$(Trunc $e.total) SP  $eta$bl`n"
    }
    $out
}
function BlockedText($s) {
    $bl = SortWith (Blocked $s) { param($a, $b) (BlockedDays $s $b) - (BlockedDays $s $a) }
    $out = ''
    foreach ($i in $bl) {
        $d = BlockedDays $s $i
        $t = $i.team; if ($null -eq $t) { $t = '' }
        $note = ''; if ($d -gt 5) { $note = '   (over 5 days: yours)' } elseif ($d -gt 3) { $note = '   (escalate)' }
        $out += $i.id.PadRight(10) + ' ' + $t.PadRight(12) + ' ' + ([string]$d).PadLeft(3) + "d  $($i.blocked)$note`n"
    }
    $out
}

# ================================================================ stand-up files -> journal transactions
function NewTeamSection([string]$team) {
    @{ team = $team; done = @(); carry = @(); drop = @(); commit = @(); new = @(); est = @(); assign = @(); block = @(); unblock = @(); note = @(); risk = @(); absent = @()
        cap = $null; sprint = $null; refine = @(); prune = @(); hold = @(); resume = @(); punt = @(); redo = @(); pass = @(); sync = @() }
}
function SplitWs([string]$s) { if ($null -eq $s) { return , @() }; $t = $s.Trim(); if ($t -eq '') { return , @() }; , @($t -csplit '\s+') }
function Split2([string]$s) {                         # Perl split ' ', $s, 2
    if ($null -eq $s) { return , @() }
    $t = $s -creplace '^\s+', ''
    if ($t -eq '') { return , @() }
    $p = $t -csplit '\s+', 2
    if ($p.Count -gt 1 -and $p[1] -eq '') { return , @($p[0]) }
    , @($p)
}
function Unquote([string]$v) { if ($null -eq $v -or $v -eq '') { return $null }; $v = $v.Trim(); $v = $v -creplace '^"(.*)"$', '$1'; if ($v -eq '') { $null } else { $v } }
function ParseStandup([string]$text, [string]$file) {
    if (-not $file) { $file = '(string)' }
    $su = @{ file = $file; date = $null; sprint = $null; teams = @{}; order = @(); notes = @(); risks = @(); errors = @(); compiled = $false }
    if ($file -cmatch '(\d{4}-\d{2}-\d{2})') { $su.date = $Matches[1] }
    $team = $null; $ln = 0
    foreach ($raw in ($text -csplit "`r?`n")) {
        $ln++
        if ($ln -eq 1 -and $raw -cmatch '^#\s*compiled\b') { $su.compiled = $true; continue }
        $line = ($raw -creplace '\s*[;#].*$', '').Trim()
        if ($line -eq '') { continue }
        if ($line -cmatch '^(\d{4}-\d{2}-\d{2})$') { $su.date = $Matches[1]; continue }
        if ($line -match '^sprint\s+(\d+)$') { if ($team) { $su.teams[$team].sprint = $Matches[1] } else { $su.sprint = $Matches[1] }; continue }
        if ($line -cmatch '^==+\s*$') { $team = $null; continue }
        if ($line -cmatch '^==+\s*(\S+)') {
            $team = $Matches[1]
            if (-not $su.teams.ContainsKey($team)) { $su.order += $team; $su.teams[$team] = NewTeamSection $team }
            continue
        }
        $null = $line -cmatch '^(\S+)\s*(.*)$'
        $verb = $Matches[1].ToLower(); $restText = $Matches[2]
        $err = "${file}:${ln}: "
        if ($verb -ceq 'note' -or $verb -ceq 'risk') { if ($team) { $su.teams[$team][$verb] += $restText } else { $su["${verb}s"] += $restText }; continue }
        if (-not $team) { $su.errors += "$err'$verb' needs a team section (== Team) first"; continue }
        $t = $su.teams[$team]
        $two = Split2 $restText; $id = $null; $tail = $null
        if ($two.Count) { $id = $two[0] }; if ($two.Count -gt 1) { $tail = $two[1] }
        switch -CaseSensitive ($verb) {
            { $_ -in 'done', 'carry', 'drop', 'unblock', 'resume' } { $t[$verb] += (SplitWs $restText); break }
            { $_ -in 'hold', 'punt', 'redo', 'block', 'prune' } {
                if ($id) { $why = $tail; if ($null -eq $why) { $why = '' }; $t[$verb] += , @($id, $why) } else { $su.errors += "$err$verb needs an id" }; break }
            'pass' { $w = SplitWs $restText; if ($w.Count -ge 2) { $t.pass += , @($w[0], $w[1]) } else { $su.errors += "${err}pass needs id and the receiving team" }; break }
            'sync' { $w = SplitWs $restText; if ($w.Count -ge 2) { $t.sync += , $w } else { $su.errors += "${err}sync needs two or more ids" }; break }
            'commit' { if ($id) { $t.commit += , @($id, (Unquote $tail)) } else { $su.errors += "${err}commit needs an id" }; break }
            'assign' { $o = Unquote $tail; if ($id -and $o) { $t.assign += , @($id, $o) } else { $su.errors += "${err}assign needs id and owner" }; break }
            'est' { $w = SplitWs $restText; if ($w.Count -ge 2 -and $w[1] -cmatch '^\d+(\.\d+)?$') { $t.est += , @($w[0], $w[1]) } else { $su.errors += "${err}est needs id and points" }; break }
            'refine' { $w = SplitWs $restText; if ($w.Count) { $t.refine += , @($w[0]) } else { $su.errors += "${err}refine needs an id" }; break }
            'cap' { if ($restText -cmatch '^\d+(\.\d+)?$') { $t.cap = $restText } else { $su.errors += "${err}cap needs a number" }; break }
            'absent' { $t.absent += (SplitWs $restText); break }
            { $_ -in 'new', 'new!' } {
                $meta = @{}; $metaKey = @{ p = 'prio'; e = 'epic'; o = 'owner'; t = 'tome' }
                while ($true) {
                    $m = [regex]::Match($restText, '(?:^|\s)([peot]):"([^"]*)"(?=\s|$)')
                    if (-not $m.Success) { break }
                    $meta[$metaKey[$m.Groups[1].Value]] = $m.Groups[2].Value
                    $restText = $restText.Substring(0, $m.Index) + ' ' + $restText.Substring($m.Index + $m.Length)
                }
                $w = SplitWs $restText
                if ($w.Count -lt 2 -or $w[1] -cnotmatch '^\d+(\.\d+)?$') { $su.errors += "${err}new needs: id points title [p:N e:Epic t:Tome o:Owner]"; break }
                $title = @()
                foreach ($x in @($w | Select-Object -Skip 2)) { if ($x -cmatch '^([peot]):(.+)$') { $meta[$metaKey[$Matches[1]]] = $Matches[2] } else { $title += $x } }
                $t.new += @{ id = $w[0]; pts = $w[1]; title = ($title -join ' '); meta = $meta; now = ($verb -ceq 'new!') }
                break
            }
            default { $su.errors += "${err}unknown verb '$verb'" }
        }
    }
    if (-not $su.date) { $su.errors += "${file}: no date (put YYYY-MM-DD in the file name or on the first line)" }
    $su
}
function ReadStandup([string]$f) { $t = ReadText $f; if ($null -eq $t) { throw "cannot open ${f}: No such file or directory`n" }; ParseStandup $t $f }

function CompileStandup($s, $su) {                    # -> journal text; throws listing every problem
    $err = @($su.errors)
    $unit = $s.unit
    $out = "`n; ---- standup $($su.date)"; if ($su.file -cne '(string)') { $out += " ($($su.file))" }; $out += "`n"
    $seen = @{}
    $bal = { param($id, $acct)
        $v = 0.0
        if ($s.items.ContainsKey($id) -and (ODHas $s.items[$id].bal $acct)) { $v += $s.items[$id].bal[$acct] }
        if ($seen.ContainsKey($id) -and (ODHas $seen[$id] $acct)) { $v += $seen[$id][$acct] }
        $v }
    $bump = { param($id, $acct, $d) if (-not $seen.ContainsKey($id)) { $seen[$id] = [ordered]@{} }; if (ODHas $seen[$id] $acct) { $seen[$id][$acct] = $seen[$id][$acct] + $d } else { $seen[$id][$acct] = $d } }
    $move = { param($id, $from, $toAcct, $pts)
        & $bump $id $from (- $pts); & $bump $id $toAcct $pts
        '    ' + $from.PadRight(32) + '  ' + (Num (- $pts)) + " $unit   ; id: $id`n" + '    ' + $toAcct.PadRight(32) + '  ' + (Num $pts) + " $unit   ; id: $id`n" }
    $known = { param($id) if ($s.items.ContainsKey($id) -or $seen.ContainsKey($id)) { return $true }; $script:cerr += "$($su.file): unknown task '$id'"; $false }
    $where = { param($id)
        $ks = @(); if ($s.items.ContainsKey($id)) { $ks += @($s.items[$id].bal.Keys) }; if ($seen.ContainsKey($id)) { $ks += @($seen[$id].Keys) }
        (@(foreach ($a in (Nub $ks)) { if ((& $bal $id $a) -gt 1e-9) { $a } }) -join ' ') }
    $zero = { param($id, $acct, $m) $a = (SplitWs $acct)[0]; '    ' + $a.PadRight(32) + "  0 $unit   ; id: $id, $m`n" + '    ' + 'Equity:Intake'.PadRight(32) + "  0 $unit`n" }
    $script:cerr = @()
    $sprint_of = @{}
    foreach ($team in $su.order) {                   # pass 1: capacities and intakes, so a commit in one section sees a new in another
        $t = $su.teams[$team]
        $n = $t.sprint; if ($null -eq $n) { $n = $su.sprint }; if ($null -eq $n) { $n = $s.current }
        if ($null -eq $n) { $script:cerr += "$($su.file): no sprint number (add 'sprint N')"; $n = 0 }
        $sprint_of[$team] = $n
        if ($null -ne $t.cap) { $out += "~ Sprint $n`n    $team   $($t.cap) $unit`n`n" }
        foreach ($it in $t.new) {
            $acct = "Backlog:$team"; if ($it.now) { $acct = "Sprint:${n}:${team}:Committed" }
            if ($s.items.ContainsKey($it.id) -or $seen.ContainsKey($it.id)) { $script:cerr += "$($su.file): task '$($it.id)' already exists" }
            & $bump $it.id $acct ([double]$it.pts)
            $m = @{}; foreach ($k in $it.meta.Keys) { $m[$k] = $it.meta[$k] }; if ($it.now) { $m['interrupt'] = 1 }
            $ms = (@(foreach ($k in (SortedKeys $m)) { if ($null -ne $m[$k] -and "$($m[$k])" -cne '') { ", ${k}: $($m[$k])" } }) -join '')
            $out += "$($su.date) Intake $($it.id) $($it.title)`n    " + $acct.PadRight(32) + "  $($it.pts) $unit   ; id: $($it.id)$ms`n    Equity:Intake`n`n"
        }
    }
    $rev = @($s.sprints); [array]::Reverse($rev)
    foreach ($team in $su.order) {                   # pass 2: the moves
        $t = $su.teams[$team]; $n = $sprint_of[$team]
        $committed = "Sprint:${n}:${team}:Committed"
        $post = @()
        $wh = { param($id) $x = & $where $id; if ($x) { $x } else { 'nowhere' } }
        foreach ($rf in $t.refine) {
            $id = $rf[0]; if (-not (& $known $id)) { continue }
            $from = $null; foreach ($a in (@('Backlog:Master') + @(foreach ($x in $s.teams) { if ($x -cne $team) { "Backlog:$x" } }))) { if ((& $bal $id $a) -gt 1e-9) { $from = $a; break } }
            if (-not $from) { $script:cerr += "$($su.file): '$id' is not in the master backlog or another team's backlog (at: $(& $wh $id))"; continue }
            $post += (& $move $id $from "Backlog:$team" (& $bal $id $from))
        }
        foreach ($c in $t.commit) {
            $id = $c[0]; $owner = $c[1]; if (-not (& $known $id)) { continue }
            $from = $null; foreach ($a in (@("Backlog:$team", 'Backlog:Master') + @(foreach ($x in $rev) { "Sprint:${x}:${team}:Carryover" }))) { if ((& $bal $id $a) -gt 1e-9) { $from = $a; break } }
            if (-not $from) { $script:cerr += "$($su.file): '$id' is not in a backlog or carryover for $team (at: $(& $wh $id))"; continue }
            $txt = & $move $id $from $committed (& $bal $id $from)
            if ($owner) { $txt = $txt.Substring(0, $txt.Length - 1) + ", owner: $owner`n" }
            $post += $txt
        }
        foreach ($pr in $t.prune) {
            $id = $pr[0]; $why = $pr[1]; if (-not (& $known $id)) { continue }
            $from = $null; foreach ($a in (@("Backlog:$team", 'Backlog:Master') + @(foreach ($x in $s.teams) { "Backlog:$x" }))) { if ((& $bal $id $a) -gt 1e-9) { $from = $a; break } }
            if (-not $from) { $script:cerr += "$($su.file): '$id' is not in a backlog (at: $(& $wh $id)); use drop for committed work"; continue }
            $txt = & $move $id $from "Sprint:${n}:${team}:Removed" (& $bal $id $from)
            $why = $why -creplace ',', ';'
            if ($why -cne '') { $txt = $txt.Substring(0, $txt.Length - 1) + ", pruned: $why`n" }
            $post += $txt
        }
        foreach ($verb in @('done', 'carry', 'drop')) {
            $toAcct = "Sprint:${n}:${team}:" + @{ done = 'Done'; carry = 'Carryover'; drop = 'Removed' }[$verb]
            foreach ($id in $t[$verb]) {
                if (-not (& $known $id)) { continue }
                $pts = & $bal $id $committed
                if ($pts -le 1e-9) { $script:cerr += "$($su.file): '$id' is not committed in sprint $n for $team (at: $(& $wh $id))"; continue }
                $post += (& $move $id $committed $toAcct $pts)
            }
        }
        foreach ($e in $t.est) {
            $id = $e[0]; $pts = [double]$e[1]; if (-not (& $known $id)) { continue }
            $loc = (SplitWs (& $where $id)); if (-not $loc.Count) { $script:cerr += "$($su.file): '$id' has no points to re-estimate"; continue }
            $loc = $loc[0]
            $diff = $pts - (& $bal $id $loc)
            if ($diff -lt 1e-9 -and $diff -gt -1e-9) { continue }
            & $bump $id $loc $diff
            $post += '    ' + $loc.PadRight(32) + '  ' + (Num $diff) + " $unit   ; id: $id`n" + '    ' + 'Equity:Intake'.PadRight(32) + '  ' + (Num (- $diff)) + " $unit`n"
        }
        $at = { param($id) $x = & $where $id; if ($x) { $x } else { $committed } }
        foreach ($a in $t.assign) { if (-not (& $known $a[0])) { continue }; $post += (& $zero $a[0] (& $at $a[0]) "owner: $($a[1])") }
        foreach ($b in $t.block) { if (-not (& $known $b[0])) { continue }; $why = $b[1] -creplace ',', ';'; if (-not $why) { $why = 'yes' }; $post += (& $zero $b[0] (& $at $b[0]) "blocked: $why") }
        foreach ($id in $t.unblock) { if (-not (& $known $id)) { continue }; $post += (& $zero $id (& $at $id) 'blocked:') }
        foreach ($b in $t.hold) { if (-not (& $known $b[0])) { continue }; $why = $b[1] -creplace ',', ';'; if (-not $why) { $why = 'yes' }; $post += (& $zero $b[0] (& $at $b[0]) "hold: $why") }
        foreach ($id in $t.resume) { if (-not (& $known $id)) { continue }; $post += (& $zero $id (& $at $id) 'hold:') }
        foreach ($p in $t.punt) {
            $id = $p[0]; if (-not (& $known $id)) { continue }
            $pts = & $bal $id $committed
            if ($pts -le 1e-9) { $script:cerr += "$($su.file): '$id' is not committed in sprint $n for $team (at: $(& $wh $id)); punt is for committed work"; continue }
            $txt = & $move $id $committed "Backlog:$team" $pts
            $why = $p[1] -creplace ',', ';'; if (-not $why) { $why = 'yes' }
            $post += $txt.Substring(0, $txt.Length - 1) + ", punt: $why`n"
        }
        foreach ($r in $t.redo) {
            $id = $r[0]; if (-not (& $known $id)) { continue }
            $from = $null; foreach ($x in $rev) { $a = "Sprint:${x}:${team}:Done"; if ((& $bal $id $a) -gt 1e-9) { $from = $a; break } }
            if (-not $from) { $script:cerr += "$($su.file): '$id' is not Done for $team in any sprint (at: $(& $wh $id)); redo is for finished work"; continue }
            $txt = & $move $id $from $committed (& $bal $id $from)
            $why = $r[1] -creplace ',', ';'; if (-not $why) { $why = 'yes' }
            $post += $txt.Substring(0, $txt.Length - 1) + ", redo: $why`n"
        }
        foreach ($p in $t.pass) {
            $id = $p[0]; if (-not (& $known $id)) { continue }
            $pts = & $bal $id $committed
            if ($pts -le 1e-9) { $script:cerr += "$($su.file): '$id' is not committed in sprint $n for $team (at: $(& $wh $id)); pass is for committed work"; continue }
            $txt = & $move $id $committed "Sprint:${n}:$($p[1]):Committed" $pts
            $post += $txt.Substring(0, $txt.Length - 1) + ", pass: from $team, owner:`n"
        }
        foreach ($g in $t.sync) {
            $ids = @(foreach ($x in $g) { if (& $known $x) { $x } })
            if ($ids.Count -lt 2) { continue }
            foreach ($id in $ids) { $post += (& $zero $id (& $at $id) ('sync: ' + (@(foreach ($x in $ids) { if ($x -cne $id) { $x } }) -join ' '))) }
        }
        if ($post.Count) { $out += "$($su.date) Standup $team`n" + ($post -join '') + "`n" }
    }
    $err += $script:cerr
    if ($err.Count) { throw (($err | ForEach-Object { "$_`n" }) -join '') }
    $out
}
function MarkCompiled([string]$file) {                # through a temp file: a failure never truncates the notes
    $t = ReadText $file
    $tmp = "$file.tmp$PID"
    WriteText $tmp ("# compiled " + (Get-Date).ToString('yyyy-MM-dd HH:mm') + "`n" + $t)
    Move-Item -LiteralPath $tmp -Destination $file -Force
}
function ApplyStandup($s, $su, [string]$journal) {
    if ($su.file -cne '(string)' -and $su.date -and (Test-Path -LiteralPath $journal)) {
        $header = "; ---- standup $($su.date) ($($su.file))"
        $jt = ReadText $journal
        foreach ($l in ($jt -csplit "`r?`n")) {
            if ($l -ceq $header) { MarkCompiled $su.file; Out-Err "$($su.file) is already in ${journal}: marked it compiled, applied nothing"; return '' }
        }
    }
    $text = CompileStandup $s $su
    AppendText $journal $text
    MarkCompiled $su.file
    $text
}
function Pending([string]$dir) {
    , @(foreach ($f in (ListDir $dir)) {
            if ($f -cnotmatch '^\d{4}-\d{2}-\d{2}.*\.txt$' -or $f -cmatch '-(?:chat|answers|proposals)\.txt$') { continue }
            $p = "$dir/$f"
            if (-not (ReadStandup $p).compiled) { $p }
        })
}
function Template($s, [string]$date, $teams) {
    $n = $s.current
    $out = "$date`n"
    if ($null -ne $n) { $out += "sprint $n`n" } else { $out += "sprint 1        ; no sprint yet: planning the first one (change the number if you continue an existing count)`n" }
    $out += "`n"
    if (-not $teams -or -not @($teams).Count) { $teams = $s.teams }
    foreach ($team in $teams) {
        $out += "== $team`n"
        $open = @(); if ($null -ne $n) { $open = Items $s -state committed -sprint $n -team $team }
        foreach ($i in $open) {
            $title = $i.title; if ($title.Length -gt 28) { $title = $title.Substring(0, 28) }
            $ow = $i.owner; if ($null -eq $ow) { $ow = '-' }
            $bl = ''; if ($i.blocked) { $bl = "  BLOCKED: $($i.blocked)" }
            $out += '; open: ' + $i.id.PadRight(10) + ' ' + (Num $i.points).PadLeft(3) + '  ' + $title.PadRight(28) + " $ow$bl`n"
        }
        if (-not $open.Count) { $out += "; (nothing committed)`n" }
        $out += "`n"
    }
    $out
}
function DayNotes($sus) {
    $first = @($sus)[0]
    $d = @{ date = $first.date; teams = @{}; notes = @(); risks = @(); extra = '' }
    foreach ($su in $sus) {
        $d.notes += $su.notes; $d.risks += $su.risks
        foreach ($team in $su.order) {
            $t = $su.teams[$team]
            if (-not $d.teams.ContainsKey($team)) { $d.teams[$team] = @{ done = @(); carry = @(); drop = @(); new = @(); note = @(); risk = @(); absent = @(); block = @(); refine = @(); prune = @() } }
            $r = $d.teams[$team]
            foreach ($k in @('done', 'carry', 'drop', 'note', 'risk', 'absent')) { $r[$k] += $t[$k] }
            $r.refine += @(foreach ($x in $t.refine) { $x[0] })
            $r.prune += @(foreach ($x in $t.prune) { if ($x[1]) { "$($x[0]): $($x[1])" } else { $x[0] } })
            $r.new += @(foreach ($x in $t.new) { "$($x.id) ($($x.pts))" })
            $r.block += @(foreach ($x in $t.block) { if ($x[1]) { "$($x[0]): $($x[1])" } else { $x[0] } })
        }
    }
    $d
}

# ================================================================ the Teams chat: paste, Y/T/B answers, lint, flags
$script:TIME = '(?:\d{1,2}/\d{1,2}(?:/\d{2,4})?,?\s+)?(\d{1,2}):(\d{2})(?::\d{2})?\s*([AaPp]\.?[Mm]\.?)?'
$script:NAME_RE = '[^\[\]\t:#]{1,60}?'
$script:PLAIN = "[A-Za-z][A-Za-z.'-]*(?:\s[A-Za-z][A-Za-z.'-]*){0,2}"
$script:ID_RE = '\b([A-Z][A-Z0-9_]{0,9}-\d{1,6})\b'
$script:LABEL_RE = '(?i)^\s*(?:(y|yesterday|yday|1|did|done)|(t|today|2|plan|planned|doing|will)|(b|blockers?|blocked|3|impediments?|issues?))\s*[:\-' + [char]0x2013 + [char]0x2014 + '.)]\s*(.*)$'
$script:THUMB = "$([char]0xD83D)$([char]0xDC4D)"
$script:CHECK = [string][char]0x2705
$script:NONE = '(?i)^\s*(?:none|no|nope|nothing|n/?a|nil|-|--|clear|no blockers?|all good|' + $script:CHECK + '|' + $script:THUMB + ')?\s*[.!]?\s*$'
$script:LIFTED = '(?i)\b(?:unblocked|resolved|cleared|fixed|no longer|not any ?more|lifted|sorted)\b'
$script:NOTHING = '(?i)^\s*(?:none|nothing|no|n/a|na|-|nil|clear|same|ditto|no blockers?)\s*[.!]?\s*$'
$script:ACK = '(?i)^\s*(?:\+1|y|yes|yep|ok|okay|same|ditto|confirmed?|' + $script:THUMB + '|' + $script:CHECK + ')\s*[.!]?\s*$'

function HM($h, $m, $ap) {
    $h = [int]$h
    if ($ap -and $ap -match '^p' -and $h -lt 12) { $h += 12 }
    if ($ap -and $ap -match '^a' -and $h -eq 12) { $h = 0 }
    '{0:D2}:{1:D2}' -f $h, [int]$m
}
function CleanName([string]$s) { ($s.Trim()) -replace '\s*\((?:Guest|External|Unverified)\)$', '' }
function ParseChat([string]$text) {
    $msgs = @(); $cur = $null; $ln = 0
    $timeRe = $script:TIME; $nameRe = $script:NAME_RE
    foreach ($raw in ($text -csplit "`r?`n")) {
        $ln++
        $line = $raw -creplace '\s+$', ''
        if ($line -cmatch '^\s*$' -and $null -eq $cur) { continue }
        $hdr = $null
        if ($line -cmatch "^\s*\[$timeRe\]\s*($nameRe)\s*$") { $hdr = @($Matches[4], (HM $Matches[1] $Matches[2] $Matches[3])) }
        elseif ($line -cmatch "^\s*($nameRe)(?:\s{2,}|\t|\s+)$timeRe\s*$") { $hdr = @($Matches[1], (HM $Matches[2] $Matches[3] $Matches[4])) }
        elseif ($line -cmatch "^\s*$timeRe\s+($nameRe)\s*$") { $hdr = @($Matches[4], (HM $Matches[1] $Matches[2] $Matches[3])) }
        elseif ($line -cmatch "^\s*($($script:PLAIN)):\s+(.*)$" -and $Matches[1] -notmatch '^(?:https?|note|risk|vote|est|re|fyi|y|t|b|yesterday|yday|today|blockers?|blocked|did|done|plan|planned|doing|will|issues?|impediments?)$') {
            $who = $Matches[1]; $body = $Matches[2]
            if ($cur -and $cur.text -cmatch '\S') { $msgs += $cur }
            $cur = @{ who = (CleanName $who); time = $null; text = $body; line = $ln }; continue
        }
        if ($hdr) {
            if ($cur -and $cur.text -cmatch '\S') { $msgs += $cur }
            $cur = @{ who = (CleanName $hdr[0]); time = $hdr[1]; text = ''; line = $ln + 1 }; continue
        }
        if ($line -match '^\s*(?:Meeting (?:started|ended)|.* (?:joined|left) the meeting\.?|Recording (?:has )?started.*|Transcription (?:has )?started.*)\s*$') { continue }
        if ($line -cmatch '^\s*(?:[^\w\s]+\s+\d+\s*)+$') { continue }
        if ($cur) { if ($cur.text -eq '') { $cur.text = $line } else { $cur.text += "`n$line" } }
    }
    if ($cur -and $cur.text -cmatch '\S') { $msgs += $cur }
    , $msgs
}
function CK([string]$s) { $s -creplace '(\p{Lu})', '^$1' }     # case-exact hashtable key: 'Ann' and 'ann' stay two people, as in Perl
function IdsIn([string]$t) { if ($null -eq $t) { return , @() }; Nub @(foreach ($m in [regex]::Matches($t, $script:ID_RE)) { $m.Groups[1].Value }) }
function IsBlocked($b) { [int](($null -ne $b) -and ($b -notmatch $script:NONE) -and ($b -notmatch $script:LIFTED)) }
function IsAck($t) { if ($null -eq $t) { return $false }; $t -match $script:ACK }
function FirstName([string]$w) {
    if ($null -eq $w) { return '' }
    $w = $w -replace '\s*\((?:Guest|External|Unverified)\)$', ''
    if ($w -cmatch '^[^,]+,\s*(\S+)') { return $Matches[1] }
    if ($w -cmatch '^(\S+)') { return $Matches[1] }
    $w
}
function Tokens([string]$s) { , @(foreach ($m in [regex]::Matches($s, '(?<!\S)([YyTtBb])(?!\S)')) { @{ k = $m.Groups[1].Value.ToUpper(); up = ($m.Groups[1].Value -cmatch '[YTB]'); at = $m.Groups[1].Index } }) }
function Fields([string]$text) {                      # one message -> (@{y;t;b}, @(errors))
    $kw = '\b(?:[ytb]|yesterday|today|blockers?)\s*:'
    $lineList = @(foreach ($l in ($text -csplit "`n")) {
            if ([regex]::Matches($l, "(?i)$kw").Count -ge 2) { $l -split '\s+(?=\b(?:[ytb]|yesterday|today|blockers?)\s*:)' } else { $l }
        })
    $got = [ordered]@{}; $err = @()
    if ($lineList.Count -and $lineList[0] -match '^\s*#\s*(?:est|estimate|vote|poll)\b') { return @{ got = $got; err = $err } }
    $cur = $null
    foreach ($l in $lineList) {
        if ($l -cmatch $script:LABEL_RE) { if ($null -ne $Matches[1]) { $cur = 'y' } elseif ($null -ne $Matches[2]) { $cur = 't' } else { $cur = 'b' }; $got[$cur] = $Matches[4] }
        elseif ($null -ne $cur -and $l -cmatch '\S') { $got[$cur] = $got[$cur] + " $l" }
    }
    if (-not $got.Count -and $lineList.Count -and $lineList[0] -match '\b(?:y|yesterday)\s*:.*\b(?:t|today)\s*:') {
        $s = $lineList -join ' '
        if ($s -match '\b(?:y|yesterday)\s*:\s*(.*?)\s*(?=\b(?:t|today)\s*:)') { $got['y'] = $Matches[1] }
        if ($s -match '\b(?:t|today)\s*:\s*(.*?)\s*(?=\b(?:b|blockers?)\s*:|$)') { $got['t'] = $Matches[1] }
        if ($s -match '\b(?:b|blockers?)\s*:\s*(.*)$') { $got['b'] = $Matches[1] }
    }
    if (-not $got.Count) {
        $s = ($lineList -join ' ') -creplace '\s+', ' '
        $tok = Tokens $s
        $up = @{}; $all = @{}
        foreach ($x in $tok) { if (-not $all.ContainsKey($x.k)) { $all[$x.k] = @() }; $all[$x.k] += $x; if ($x.up) { if (-not $up.ContainsKey($x.k)) { $up[$x.k] = @() }; $up[$x.k] += $x } }
        $pick = $null
        $u1 = @(foreach ($k in @('Y', 'T', 'B')) { if ($up.ContainsKey($k) -and @($up[$k]).Count -eq 1) { $k } })
        if ($u1.Count -eq 3) { $pick = @{ Y = @($up['Y'])[0]; T = @($up['T'])[0]; B = @($up['B'])[0] } }
        elseif ($tok.Count) {
            foreach ($k in @('Y', 'T', 'B')) { $n = 0; if ($all.ContainsKey($k)) { $n = @($all[$k]).Count }
                if ($n -ne 1) { if ($n -eq 0) { $err += "no $k found" } else { $err += "'$k' appears $n times: capitalize the one that is the delimiter" } } }
            if (-not $err.Count) { $pick = @{ Y = @($all['Y'])[0]; T = @($all['T'])[0]; B = @($all['B'])[0] } }
        }
        else { $err += 'no Y/T/B found' }
        if ($pick) {
            if ($pick.Y.at -lt $pick.T.at -and $pick.T.at -lt $pick.B.at) {
                $got['y'] = $s.Substring($pick.Y.at + 1, $pick.T.at - $pick.Y.at - 1)
                $got['t'] = $s.Substring($pick.T.at + 1, $pick.B.at - $pick.T.at - 1)
                $got['b'] = $s.Substring($pick.B.at + 1)
            }
            else { $err += 'out of order: expected Y ... T ... B ...' }
        }
    }
    foreach ($k in @($got.Keys)) { if ($null -ne $got[$k]) { $got[$k] = $got[$k].Trim() } }
    @{ got = $got; err = $err }
}
function GuessFields([string]$text) {                 # first Y, first T after it, LAST B after that
    $s = $text -creplace '\s+', ' '
    $tok = Tokens $s
    $y = $null; foreach ($x in $tok) { if ($x.k -ceq 'Y') { $y = $x; break } }; if (-not $y) { return $null }
    $t = $null; foreach ($x in $tok) { if ($x.k -ceq 'T' -and $x.at -gt $y.at) { $t = $x; break } }; if (-not $t) { return $null }
    $b = $null; foreach ($x in $tok) { if ($x.k -ceq 'B' -and $x.at -gt $t.at) { $b = $x } }; if (-not $b) { return $null }
    $g = [ordered]@{ y = $s.Substring($y.at + 1, $t.at - $y.at - 1).Trim(); t = $s.Substring($t.at + 1, $b.at - $t.at - 1).Trim(); b = $s.Substring($b.at + 1).Trim() }
    foreach ($v in $g.Values) { if ($v.Length -eq 0) { return $null } }
    $g
}
function ReadProposals([string]$file) {
    $p = @{}; $t = ReadText $file; if ($null -eq $t) { return $p }
    foreach ($l in ($t -csplit "`r?`n")) { if ($l -cmatch '^\s*(#|$)') { continue }; $f = $l -csplit "`t", 4; if ($f[0]) { $p[$f[0]] = @{ y = $f[1]; t = $f[2]; b = $f[3] } } }
    $p
}
function FinishAnswer($r) {
    $r.ids = @{ y = (IdsIn $r.y); t = (IdsIn $r.t); b = (IdsIn $r.b) }
    $r.blocked = IsBlocked $r.b
    $r.complete = [int](($null -ne $r.y) -and ($null -ne $r.t) -and ($null -ne $r.b))
    $r
}
function ParseAnswers([string]$text, [bool]$tryGuess, $proposals) {
    $a = @{}; $order = @()
    foreach ($m in (ParseChat $text)) {
        $f = Fields $m.text; $got = $f.got
        if (-not $got.Count -and $proposals -and $proposals.ContainsKey($m.who) -and (IsAck $m.text)) { $got = [ordered]@{}; $pp = $proposals[$m.who]; foreach ($k in @('y', 't', 'b')) { $got[$k] = $pp[$k] } }
        if (-not $got.Count -and $tryGuess) { $g = GuessFields $m.text; if ($g) { $got = $g } }
        if (-not $got.Count) { continue }
        $kw = CK $m.who
        if (-not $a.ContainsKey($kw)) { $order += $kw; $a[$kw] = @{ who = $m.who; time = $m.time; y = $null; t = $null; b = $null; raw = ''; assumed = 0 } }
        $r = $a[$kw]
        if ($null -ne $m.time) { $r.time = $m.time }
        if ($r.raw) { $r.raw += "`n" + $m.text } else { $r.raw = $m.text }
        foreach ($k in $got.Keys) { $v = $got[$k]; if ($null -ne $v) { $v = $v.Trim() }; $r[$k] = $v }
    }
    , @(foreach ($w in $order) { FinishAnswer $a[$w] })
}
function LintMessage([string]$text, $o) {
    $f = Fields $text; $g = $f.got
    $e = @($f.err); $w = @()
    if (-not $e.Count -and -not $g.Count) { $e = @('no Y/T/B found') }
    $guessed = $null; if ($e.Count) { $guessed = GuessFields $text }
    if (-not $e.Count) {
        foreach ($k in @('y', 't', 'b')) { if ($null -eq $g[$k] -or $g[$k] -cnotmatch '\S') { $msg = $k.ToUpper() + ' is empty'; if ($k -ceq 'b') { $msg += " (write 'none')" }; $e += $msg } }
    }
    if (-not $e.Count) {
        foreach ($k in @('y', 't')) { if ($g[$k] -cnotmatch $script:ID_RE -and $g[$k] -notmatch $script:NOTHING) { $w += 'no task id in ' + $k.ToUpper() + " (e.g. $($o.example))" } }
        if ($o.known) { foreach ($id in (IdsIn (@($g['y'], $g['t'], $g['b']) -join "`n"))) { if (-not $o.known.ContainsKey($id)) { $w += "$id is not in the journal" } } }
    }
    @{ ok = [int](-not $e.Count); errors = $e; warnings = $w; guess = $guessed; y = $g['y']; t = $g['t']; b = $g['b'] }
}
function LintChat([string]$text, $o) {
    $by = @{}; $order = @()
    foreach ($m in (ParseChat $text)) {
        if ($m.text -match '^\s*#\s*(?:est|estimate|vote|poll)\b') { continue }
        $f = Fields $m.text; $g = $f.got; $err = $f.err
        if (-not $g.Count -and $o.proposals -and $o.proposals.ContainsKey($m.who) -and (IsAck $m.text)) { $g = [ordered]@{}; $pp = $o.proposals[$m.who]; foreach ($k in @('y', 't', 'b')) { $g[$k] = $pp[$k] }; $err = @() }
        $kw = CK $m.who
        if (-not $by.ContainsKey($kw)) { $order += $kw; $by[$kw] = @{ who = $m.who; line = $m.line; time = $m.time; fields = [ordered]@{}; last_err = $null; last_text = $m.text } }
        $p = $by[$kw]
        if ($g.Count) { foreach ($k in $g.Keys) { $p.fields[$k] = $g[$k] }; $p.last_err = $null; $p.line = $m.line; if ($null -ne $m.time) { $p.time = $m.time }; $p.last_text = $m.text }
        elseif (@($err).Count -and -not (@($err).Count -eq 1 -and $err[0] -ceq 'no Y/T/B found')) { $p.last_err = $err; $p.line = $m.line; $p.last_text = $m.text }
        elseif (-not $p.fields.Count -and -not $p.last_err) { $p.line = $m.line; $p.last_text = $m.text }
    }
    $out = @(foreach ($who in $order) {
            $p = $by[$who]
            $merged = (@(foreach ($k in @('y', 't', 'b')) { if ((ODHas $p.fields $k) -and $null -ne $p.fields[$k]) { $k.ToUpper() + ": $($p.fields[$k])" } }) -join "`n")
            if ($p.last_err) { $r = LintMessage $p.last_text $o } elseif ($p.fields.Count) { $r = LintMessage $merged $o } else { $r = LintMessage $p.last_text $o }
            $r.who = $p.who; $r.line = $p.line; $r.time = $p.time
            $e1 = $null; $e2 = $null
            if ($o.examples -and $o.examples.ContainsKey($r.who)) { $ex = @($o.examples[$r.who]); $e1 = $ex[0]; if ($ex.Count -gt 1) { $e2 = $ex[1] } }
            $x1 = $e1; if ($null -eq $x1) { $x1 = $o.example }
            $x2 = $e2; if ($null -eq $x2) { $x2 = $e1 }; if ($null -eq $x2) { $x2 = $o.example2 }
            $fmt = "Y did $x1 T doing $x2 B none"
            $hey = 'Hey ' + (FirstName $r.who) + '! '
            $r.confirm = ''; if ($r.ok) { $r.confirm = $hey + "I read your status as: Y $($r.y) / T $($r.t) / B $($r.b)  $($script:THUMB) if right, or repost." }
            if (-not $r.ok -and $r.guess) { $r.reply = $hey + "Did you mean: Y $($r.guess.y) / T $($r.guess.t) / B $($r.guess.b) ?  $($script:THUMB) if yes, or repost as: $fmt" }
            elseif (-not $r.ok) { $r.reply = $hey + "I couldn't read your status (" + ($r.errors -join '; ') + "). Repost as: $fmt" }
            elseif ($r.warnings.Count) {
                $parts = Nub @(foreach ($w in $r.warnings) {
                        if ($w -cmatch '^no task id') { "Add the task id next time so it counts (e.g. $fmt)." }
                        elseif ($w -cmatch '^(\S+) is not in the journal') { "$($Matches[1]) isn't in the backlog -- typo?" } else { "$w." } })
                $r.reply = $hey + 'Got it. ' + ($parts -join ' ')
            }
            else { $r.reply = '' }
            $r
        })
    , $out
}
function LintText([string]$file, $rs) {
    $out = ''
    foreach ($r in $rs) {
        $st = 'ok   '; $msg = 'Y/T/B parsed'
        if (-not $r.ok) { $st = 'ERROR'; $msg = $r.errors -join '; ' } elseif ($r.warnings.Count) { $st = 'warn '; $msg = $r.warnings -join '; ' }
        $ln = $r.line; if ($null -eq $ln) { $ln = 0 }
        $out += "${file}:${ln}: $st $($r.who): $msg`n"
    }
    $bad = @($rs | Where-Object { -not $_.ok }).Count; $warn = @($rs | Where-Object { $_.ok -and $_.warnings.Count }).Count
    $out += "# $(@($rs).Count) answered, $bad error$(Plural $bad), $warn warning$(Plural $warn)`n"
    $out
}
function AnswersText([string]$date, [string]$team, $ans) {
    $out = $date; if ($team) { $out += " $team" }; $out += "`n"
    foreach ($r in $ans) {
        $out += $r.who; if ($r.time) { $out += " ($($r.time))" }; if ($r.assumed) { $out += ' (assumed)' }; $out += "`n"
        $out += "  Y: $($r.y)`n  T: $($r.t)`n  B: $($r.b)`n"
    }
    $out
}
function ReadAnswers([string]$file) {
    $t = ReadText $file; if ($null -eq $t) { throw "cannot open ${file}: No such file or directory`n" }
    $l = @($t -csplit "`r?`n"); if ($l.Count -and $l[$l.Count - 1] -eq '') { $l = @($l | Select-Object -First ($l.Count - 1)) }
    $date = $null; $team = $null
    if ($l.Count -and $l[0] -cmatch '^(\d{4}-\d{2}-\d{2})\s*(\S*)') { $date = $Matches[1]; $team = $Matches[2] }
    $ans = @(); $r = $null
    foreach ($x in @($l | Select-Object -Skip 1)) {
        if ($x -cmatch '^(\S.*?)(?:\s+\((\d{2}:\d{2})\))?(\s+\(assumed\))?$' -and $x -cnotmatch '^\s') {
            $r = @{ who = $Matches[1]; time = $Matches[2]; assumed = [int]($null -ne $Matches[3]); y = $null; t = $null; b = $null; raw = '' }; $ans += $r
        }
        elseif ($r -and $x -cmatch '^\s+([YTB]):\s?(.*)$') { $r[$Matches[1].ToLower()] = $Matches[2] }
    }
    $ans = @(foreach ($r in $ans) { FinishAnswer $r })
    if (-not $team) { $team = $null }
    @{ date = $date; team = $team; answers = $ans }
}
function AnswerHistory([string]$dir, [string]$team, [string]$before, [int]$days = 5) {
    $fs = @(foreach ($f in (ListDir $dir)) {
            if ($f -cnotmatch '^(\d{4}-\d{2}-\d{2})(?:-(.+?))?-answers\.txt$') { continue }
            $d = $Matches[1]; $ft = $Matches[2]
            if (-not (SLt $d $before)) { continue }
            if ($team -and $null -ne $ft -and $ft -cne $team) { continue }
            $f })
    $fs = SortWith $fs { param($a, $b) - (Cmp $a $b) }
    $h = @()
    foreach ($f in $fs) { $r = ReadAnswers "$dir/$f"; if ($team -and $r.team -and $r.team -cne $team) { continue }; $h += $r; if ($h.Count -ge $days) { break } }
    , $h
}
function AssumedDays($who, $hist) { $d = 0; foreach ($h in $hist) { $p = $null; foreach ($a in $h.answers) { if ($a.who -ceq $who) { $p = $a; break } }; if (-not ($p -and $p.assumed)) { break }; $d++ }; $d }
function Propose($s, [string]$team, $hist, $roster) {
    $prev = @{}; if (@($hist).Count) { foreach ($a in $hist[0].answers) { $prev[$a.who] = $a } }
    $n = $s.current
    , @(foreach ($who in $roster) {
            $p = $prev[$who]
            $wip = @(); if ($null -ne $n) { $wip = @(foreach ($i in (Items $s -state committed -sprint $n -team $team)) { if ($i.owner -ceq $who) { $i } }) }
            $wip = SortOn $wip { param($i) $pr = $i.meta['prio']; if ($null -eq $pr) { $pr = 9 }; , @($pr, $i.id) }
            if ($p -and $p.t -and $p.t -cmatch '\S') { $y = $p.t; $basis = "yesterday's T" }
            elseif ($wip.Count) { $y = "$($wip[0].id) in progress"; $basis = 'first committed task' }
            else { $y = 'nothing recorded'; $basis = 'no history, no committed tasks' }
            $iny = @{}; foreach ($x in (IdsIn $y)) { $iny[$x] = 1 }
            $next = $null; foreach ($i in $wip) { if (-not $iny.ContainsKey($i.id)) { $next = $i; break } }
            if ($next) { $t = "$($next.id) $($next.title)" } elseif ($wip.Count) { $t = "continue $($wip[0].id)" } else { $t = 'no committed task' }
            $b = 'none'; if ($p -and $p.blocked) { $b = $p.b }
            @{ who = $who; y = $y; t = $t; b = $b; basis = $basis }
        })
}
function AssumedRecord($p) { FinishAnswer @{ who = $p.who; time = $null; y = $p.y; t = $p.t; b = $p.b; raw = ''; assumed = 1 } }
function NormPlan($t) { if ($null -eq $t) { $t = '' }; $t = $t.ToLower() -creplace '[^a-z0-9 ]', ''; $t = $t -creplace '\s+', ' '; $t -creplace '^ | $', '' }
function Flags($s, [string]$team, $ans, $hist, $roster) {
    $f = @()
    $seen = @{}; foreach ($a in $ans) { $seen[$a.who] = $a }
    $n = $s.current
    $committed = @{}; if ($team -and $null -ne $n) { foreach ($i in (Items $s -state committed -sprint $n -team $team)) { $committed[$i.id] = $i } }
    $prev = $null; if (@($hist).Count) { $prev = $hist[0] }
    $pv = @{}; if ($prev) { foreach ($a in $prev.answers) { $pv[$a.who] = $a } }
    foreach ($who in $roster) { if (-not $seen.ContainsKey($who)) { $f += @{ level = 'amber'; who = $who; text = 'no answers in chat' } } }
    foreach ($r in $ans) {
        if (-not $r.assumed) { continue }
        $days = 1 + (AssumedDays $r.who $hist)
        $lv = 'amber'; if ($days -ge 2) { $lv = 'red' }
        $run = ''; if ($days -gt 1) { $run = " ($days days running)" }
        $f += @{ level = $lv; who = $r.who; text = "no answer; status ASSUMED from yesterday${run}: Y $($r.y) / T $($r.t) / B $($r.b) -- unconfirmed" }
    }
    foreach ($r in $ans) {
        if ($r.assumed) { continue }
        if (-not $r.complete) { $f += @{ level = 'info'; who = $r.who; text = 'incomplete answers (missing ' + (@(foreach ($k in @('y', 't', 'b')) { if ($null -eq $r[$k]) { $k } }) -join '/') + ')' } }
        if ($r.blocked) {
            $days = 1
            foreach ($h in $hist) { $p = $null; foreach ($a in $h.answers) { if ($a.who -ceq $r.who) { $p = $a; break } }; if (-not ($p -and $p.blocked)) { break }; $days++ }
            $lv = 'amber'; if ($days -ge 3) { $lv = 'red' }
            $run = ''; if ($days -gt 1) { $run = ", reported $days days running" }
            $bid = $null; if ($r.ids.b.Count) { $bid = $r.ids.b[0] }
            $f += @{ level = $lv; who = $r.who; text = "blocked${run}: $($r.b)"; id = $bid }
        }
        if ($prev -and $pv.ContainsKey($r.who) -and $null -ne $r.t -and (NormPlan $r.t) -cne '' -and (NormPlan $r.t) -ceq (NormPlan $pv[$r.who].t)) {
            $days = 2
            $hh = @($hist); for ($x = 1; $x -lt $hh.Count; $x++) { $p = $null; foreach ($a in $hh[$x].answers) { if ($a.who -ceq $r.who) { $p = $a; break } }; if (-not ($p -and (NormPlan $p.t) -ceq (NormPlan $r.t))) { break }; $days++ }
            $big = 0; foreach ($id in $r.ids.t) { $v = 0; if ($s.items.ContainsKey($id)) { $v = $s.items[$id].points }; if ($v -gt $big) { $big = $v } }
            $limit = 3; if ($big -gt 3) { $limit = $big }
            $lv = 'info'; if ($days -ge $limit) { $lv = 'red' } elseif ($days -ge 3) { $lv = 'amber' }
            $f += @{ level = $lv; who = $r.who; text = "same plan $days days running: $($r.t)" }
        }
        if (-not $r.ids.y.Count -and -not $r.ids.t.Count -and $r.complete) { $f += @{ level = 'info'; who = $r.who; text = 'no task ids in yesterday/today (untracked work?)' } }
        foreach ($id in (Nub (@($r.ids.y) + @($r.ids.t) + @($r.ids.b)))) {
            if (-not $s.items.ContainsKey($id)) { $f += @{ level = 'amber'; who = $r.who; text = "mentions $id which is not in the journal"; id = $id }; continue }
            $it = $s.items[$id]
            $ow = $it.owner; if ($null -eq $ow) { $ow = '' }
            if ($team -and -not $committed.ContainsKey($id) -and $it.state -cne 'done' -and $ow -cne $r.who) {
                $tt = ''; if ($it.team) { $tt = " ($($it.team))" }
                $f += @{ level = 'info'; who = $r.who; text = "mentions $id which is $($it.state)$tt, not in $team's sprint"; id = $id }
            }
            if ($it.owner -and $it.owner -cne $r.who -and ($r.ids.t -ccontains $id)) { $f += @{ level = 'info'; who = $r.who; text = "working $id which is owned by $($it.owner)"; id = $id } }
        }
        foreach ($id in $r.ids.y) {
            if (-not $s.items.ContainsKey($id)) { continue }
            if ($r.y -match '\b(?:done|finished|complete[d]?|closed|merged|shipped|delivered)\b' -and $r.y -notmatch "\b(?:nearly|almost|not|isn'?t|half|mostly|partly|still)\s+(?:\w+\s+)?(?:done|finished|complete[d]?|closed|merged|shipped|delivered)\b" -and $s.items[$id].state -ceq 'committed') {
                $f += @{ level = 'info'; who = $r.who; text = "says $id is done; confirm and mark"; id = $id; done = 1 }
            }
        }
    }
    SortOn $f { param($x) , @(@{ red = 0; amber = 1; info = 2 }[$x.level], $x.who) }
}
function FoldFlags($fl) {
    $out = @(); $info = @{}; $kinds = @()
    foreach ($x in $fl) {
        if ($x.level -cne 'info') { $out += ($x.level.ToUpper().PadRight(5) + ' ' + $x.who.PadRight(14) + ' ' + $x.text); continue }
        $kind = $x.text -creplace '\b[A-Z][A-Z0-9_]{0,9}-\d{1,6}\b', 'ID'
        $kind = $kind -creplace '\([^)]*\)', ''; $kind = $kind -creplace 'owned by .*', 'owned by someone else'; $kind = $kind -creplace "in \S+'s sprint", "in the team's sprint"
        $kind = ($kind -creplace '\s+', ' ') -creplace '^\s|\s$', ''
        if (-not $info.ContainsKey($kind)) { $kinds += $kind; $info[$kind] = @() }
        $nm = $x.who; if ($x.id) { $nm += " ($($x.id))" }
        $info[$kind] += $nm
    }
    foreach ($k in $kinds) {
        $w = @($info[$k]); $last = $w.Count - 1; if ($last -gt 7) { $last = 7 }
        $more = ''; if ($w.Count -gt 8) { $more = ', ...' }
        $out += 'INFO'.PadRight(5) + " $($w.Count)x ${k}: " + ($w[0..$last] -join ', ') + $more
    }
    , $out
}
function SuggestLines($s, [string]$team, $ans, $fl) {
    $out = ''
    $doneflag = @{}; foreach ($x in $fl) { if ($x.done) { $doneflag[$x.id] = 1 } }
    $said = @{}
    foreach ($r in $ans) { foreach ($id in $r.ids.y) { if ($doneflag.ContainsKey($id)) { if (-not $said.ContainsKey($id)) { $said[$id] = @() }; $said[$id] += $r.who } } }
    foreach ($id in (SortedKeys $said)) { $out += "; done $id   ; " + ($said[$id] -join ', ') + " say done`n" }
    foreach ($r in $ans) {
        if ($r.blocked) {
            $id = $null; if ($r.ids.b.Count) { $id = $r.ids.b[0] }
            $why = $r.b -creplace ',', ';'
            if ($id) { $why = $why -replace ('^\s*' + [regex]::Escape($id) + '\b[\s:;-]*'), '' }
            if ($id -and $s.items.ContainsKey($id) -and $s.items[$id].blocked) { continue }
            if ($id -and $s.items.ContainsKey($id)) { $out += "block $id $why`n" } else { $out += "risk $($r.who): $why`n" }
        }
        else {
            foreach ($id in (Nub (@($r.ids.t) + @($r.ids.y) + @($r.ids.b)))) { if ($s.items.ContainsKey($id) -and $s.items[$id].blocked) { $out += "; unblock $id   ; $($r.who) no longer reports a blocker`n" } }
            if ($null -ne $r.b -and $r.b -match $script:LIFTED) { $out += "; note $($r.who): $($r.b)`n" }
        }
    }
    $teams = @{}; foreach ($t in $s.teams) { $teams[$t.ToLower()] = $t }
    foreach ($r in $ans) {
        foreach ($text in @($r.t, $r.b)) {
            if ($null -eq $text -or $text -cnotmatch '\S') { continue }
            $ids = Nub @(foreach ($x in [regex]::Matches($text, $script:ID_RE)) { if ($s.items.ContainsKey($x.Groups[1].Value)) { $x.Groups[1].Value } })
            if (-not $ids.Count) { continue }
            $why = $text -creplace ',', ';'
            if ($text -match "\b(?:punt|punting|punted|too (?:hard|big)|can'?t (?:do|finish))\b") { $out += "; punt $($ids[0]) $why   ; $($r.who): too hard as written -- back to TODO (confirm)`n" }
            elseif ($text -match '\b(?:on hold|hold(?:ing)?|parked|paused|pulled (?:on|off)to)\b') { $out += "; hold $($ids[0]) $why   ; $($r.who): interrupted (confirm)`n" }
            elseif ($text -match '\b(?:redo|rework|reopen(?:ed)?|demo found)\b') { $out += "; redo $($ids[0]) $why   ; $($r.who): found wrong after the demo (confirm)`n" }
            elseif ($text -match '\b(?:pass(?:ing)?|hand(?:ing)?[ -]?off|hand(?:ing)? (?:over|to))\b') {
                $toTeam = $null; foreach ($w in [regex]::Matches($text, '\b([A-Za-z][\w&-]*)\b')) { $lw = $w.Groups[1].Value.ToLower(); if ($teams.ContainsKey($lw)) { $toTeam = $teams[$lw]; break } }
                if ($toTeam) { $out += "; pass $($ids[0]) $toTeam   ; $($r.who): another team should do it (confirm)`n" } else { $out += "; note $($r.who): $why   ; pass to which team?`n" }
            }
            elseif ($text -match '\b(?:sync|coordinat\w+|together with|jointly)\b' -and $ids.Count -ge 2) { $out += "; sync $($ids[0]) $($ids[1])   ; $($r.who): coordinated across teams, shared DONE (confirm)`n" }
        }
    }
    $silent = @(foreach ($x in $fl) { if ($x.text -ceq 'no answers in chat') { $x.who } })
    if ($silent.Count) { $out += '; absent ' + ($silent -join ' ') + "   ; no answers in chat (confirm)`n" }
    $out
}
function AnswersReport([string]$team, $ans, $fl) {
    $nb = @($ans | Where-Object { $_.blocked }).Count
    $out = ''; if ($team) { $out = "$team " }
    $out += "stand-up answers: $(@($ans).Count) people, $nb blocked`n"
    foreach ($r in $ans) {
        $y = $r.y; if ($null -eq $y) { $y = '-' }; $t = $r.t; if ($null -eq $t) { $t = '-' }; $b = $r.b; if ($null -eq $b) { $b = '-' }
        $out += '  ' + $r.who.PadRight(14) + " Y: $y`n  " + ''.PadRight(14) + " T: $t`n  " + ''.PadRight(14) + " B: $b`n"
    }
    if (@($fl).Count) { $out += "flags:`n"; foreach ($l in (FoldFlags $fl)) { $out += "  $l`n" } }
    $out
}
function TeamOf($s, [string]$name) {
    $m = Members $s ''
    if ($m.ContainsKey($name)) { return $m[$name].team }
    $first = (SplitWs $name)[0]
    $hit = @(foreach ($k in $m.Keys) { if ($k -ceq $first -or $k.StartsWith($first)) { $k } })
    if ($hit.Count -eq 1) { $m[$hit[0]].team } else { $null }
}

# ================================================================ the spreadsheet: CSV tables for Excel
function CsvQ($v) { $v = Str $v; if ($v -cmatch "[`",`r`n]") { '"' + ($v -creplace '"', '""') + '"' } else { $v } }
function CsvText($hdr, $rows) { (@(foreach ($r in (@(, $hdr) + @($rows))) { (@(foreach ($c in $r) { CsvQ $c }) -join ',') + "`r`n" }) -join '') }
function SprintSpan($s) {
    if ($s.memo.ContainsKey('span')) { return $s.memo.span }
    $span = @{}
    foreach ($it in $s.items.Values) { foreach ($h in $it.history) {
            if ($h.account -cnotmatch '^Sprint:(\d+):') { continue }
            $n = $Matches[1]; if (-not $span.ContainsKey($n)) { $span[$n] = @{ start = $null; end = $null } }
            $sx = $span[$n]
            if (-not $sx.start -or [string]::CompareOrdinal($h.date, $sx.start) -lt 0) { $sx.start = $h.date }
            if (-not $sx.end -or [string]::CompareOrdinal($h.date, $sx.end) -gt 0) { $sx.end = $h.date } } }
    $s.memo.span = $span
    $span
}
function TeamHistory($s) {
    if ($s.memo.ContainsKey('th')) { return $s.memo.th }
    $int = @{}
    foreach ($it in (AllItems $s)) {
        if (-not $it.meta['interrupt']) { continue }
        $h = $null; foreach ($x in $it.history) { if ($x.points -gt 0 -and $x.account -cmatch ':Committed$') { $h = $x; break } }
        if (-not $h -or $h.account -cnotmatch '^Sprint:(\d+):([^:]+):') { continue }
        $k = "$($Matches[1])|$($Matches[2])"; if ($int.ContainsKey($k)) { $int[$k] += $h.points } else { $int[$k] = $h.points }
    }
    $th = @{}
    foreach ($n in $s.sprints) {
        $r = SprintSummary $s $n
        foreach ($t in (SortedKeys $r.teams)) {
            $x = $r.teams[$t]
            if (-not $th.ContainsKey($t)) { $th[$t] = @() }
            $iv = 0; if ($int.ContainsKey("$n|$t")) { $iv = $int["$n|$t"] }
            $th[$t] += @{ sprint = $n; committed = $x.committed; done = $x.done; carryover = $x.carryover; capacity = $x.capacity; load = $x.load; pct = $x.pct; open = $x.open
                interrupt = $iv; complete = [int](-not ($null -ne $s.current -and [int]$n -eq [int]$s.current -and $x.open -gt 0)) }
        }
    }
    $s.memo.th = $th
    $th
}
function IntakeBySprint($s) {
    $span = SprintSpan $s; $in = @{}
    $sk = @(foreach ($k in $span.Keys) { if ($span[$k].start) { , @($k, [int]$k, $span[$k].start) } })
    foreach ($it in (AllItems $s)) {
        $h = $null; foreach ($x in $it.history) { if ($x.points -gt 0) { $h = $x; break } }
        if (-not $h) { continue }
        $hd = $h.date
        $best = $null; $bestN = 0
        foreach ($e in $sk) { if ([string]::CompareOrdinal($e[2], $hd) -le 0 -and ($null -eq $best -or $e[1] -gt $bestN)) { $best = $e[0]; $bestN = $e[1] } }
        if ($null -eq $best) { continue }
        if ($in.ContainsKey($best)) { $in[$best] += $h.points } else { $in[$best] = $h.points }
    }
    $in
}
$script:CSV_TABLES = @('items', 'sprints', 'epics', 'intake')
function TableData($s, [string]$what) {     # -> @{ hdr; rows } for the CSVs and the workbook
    switch -CaseSensitive ($what) {
        'items' {
            return @{ hdr = @('id', 'title', 'points', 'state', 'team', 'sprint', 'owner', 'prio', 'tome', 'epic', 'age', 'blocked', 'blocked_days', 'created', 'interrupt'); rows = @(foreach ($i in (AllItems $s)) {
                        $bd = ''; if ($i.blocked) { $bd = BlockedDays $s $i }; $ir = ''; if ($i.meta['interrupt']) { $ir = 1 }
                        , @($i.id, $i.title, $i.points, $i.state, $i.team, $i.sprint, $i.owner, $i.meta['prio'], $i.meta['tome'], $i.meta['epic'], $i.age, $i.blocked, $bd, $i.created, $ir) }) }
        }
        'sprints' {
            $th = TeamHistory $s; $span = SprintSpan $s
            return @{ hdr = @('sprint', 'start', 'team', 'capacity', 'committed', 'done', 'carryover', 'pct', 'load', 'carry_rate', 'interrupt', 'complete'); rows = @(foreach ($t in (SortedKeys $th)) { foreach ($x in $th[$t]) {
                            $st = $null; if ($span.ContainsKey("$($x.sprint)")) { $st = $span["$($x.sprint)"].start }
                            , @($x.sprint, $st, $t, $x.capacity, $x.committed, $x.done, $x.carryover, $x.pct, $x.load, (PctU $x.carryover $x.committed), $x.interrupt, $x.complete) } }) }
        }
        'epics' {
            $rm = Roadmap $s
            return @{ hdr = @('tome', 'epic', 'tasks', 'total', 'done', 'wip', 'backlog', 'removed', 'pct', 'remaining', 'eta_sprint', 'blocked'); rows = @(foreach ($e in (Epics $s)) {
                        $r = $null; foreach ($x in $rm.epics) { if ($x.epic -ceq $e.epic -and $x.tome -ceq $e.tome) { $r = $x; break } }
                        $a = ''; $b = ''; $c = ''; if ($r) { $a = $r.remaining; $b = $r.end; $c = $r.blocked }
                        , @($e.tome, $e.epic, $e.items.Count, $e.total, $e.done, $e.wip, $e.backlog, $e.removed, $e.pct, $a, $b, $c) }) }
        }
        'intake' {
            $span = SprintSpan $s; $in = IntakeBySprint $s
            return @{ hdr = @('sprint', 'start', 'intake', 'done'); rows = @(foreach ($n in $s.sprints) {
                        $st = $null; if ($span.ContainsKey("$n")) { $st = $span["$n"].start }
                        $iv = 0; if ($in.ContainsKey("$n")) { $iv = $in["$n"] }
                        , @($n, $st, $iv, (SprintSummary $s $n).totals.done) }) }
        }
    }
    throw "csv: unknown table '$what' ($($script:CSV_TABLES -join ' '))`n"
}
function CsvTable($s, [string]$what) { $t = TableData $s $what; CsvText $t.hdr $t.rows }

# ---------------------------------------------------------------- the workbook: Excel's XML Spreadsheet format (one file, no zip, opens in Excel)
function XEsc($v) { ((Str $v) -creplace '[\x00-\x08\x0B\x0C\x0E-\x1F]', '').Replace('&', '&amp;').Replace('<', '&lt;').Replace('>', '&gt;').Replace('"', '&quot;') }
function XCell($v, [string]$style) {
    $st = ''; if ($style) { $st = " ss:StyleID=`"$style`"" }
    if ($null -eq $v -or (Str $v) -eq '') { return "<Cell$st/>" }
    if ($v -is [string] -and $v -cmatch '^\d{4}-\d{2}-\d{2}$') { $ds = 'd'; if ($style) { $ds = $style }; return "<Cell ss:StyleID=`"$ds`"><Data ss:Type=`"DateTime`">${v}T00:00:00.000</Data></Cell>" }
    if (-not ($v -is [string] -and $v -cmatch '^0\d') -and (IsNum $v)) { return "<Cell$st><Data ss:Type=`"Number`">$(Num ([double]$v))</Data></Cell>" }
    "<Cell$st><Data ss:Type=`"String`">$(XEsc $v)</Data></Cell>"
}
function XRow($cells, [string]$style) {             # XCell for each cell, inlined: the workbook has tens of thousands
    $st = ''; if ($style) { $st = " ss:StyleID=`"$style`"" }
    '<Row>' + (@(foreach ($v in $cells) {
                if ($null -eq $v) { "<Cell$st/>"; continue }
                $isStr = $v -is [string]
                $isN = $v -is [double] -or $v -is [int] -or $v -is [long] -or $v -is [decimal]
                if ($isStr) { $sv = $v } elseif ($isN) { $sv = Num $v } else { $sv = [string]$v }
                if ($sv -eq '') { "<Cell$st/>"; continue }
                if ($isStr -and $v -cmatch '^\d{4}-\d{2}-\d{2}$') { $ds = 'd'; if ($style) { $ds = $style }; "<Cell ss:StyleID=`"$ds`"><Data ss:Type=`"DateTime`">${v}T00:00:00.000</Data></Cell>"; continue }
                $num = $isN -or ($isStr -and $v -cmatch $script:NUMRE)
                if (-not ($isStr -and $v -cmatch '^0\d') -and $num) { "<Cell$st><Data ss:Type=`"Number`">$(Num ([double]$v))</Data></Cell>"; continue }
                "<Cell$st><Data ss:Type=`"String`">" + (($sv -creplace '[\x00-\x08\x0B\x0C\x0E-\x1F]', '').Replace('&', '&amp;').Replace('<', '&lt;').Replace('>', '&gt;').Replace('"', '&quot;')) + '</Data></Cell>'
            }) -join '') + "</Row>`n"
}
function XSheet([string]$name, $hdr, $rows, $c, [int]$headerRow = 1, $pre = $null, $widths = $null) {
    $ncol = $hdr.Count
    if (-not $widths) {
        $widths = @(for ($k = 0; $k -lt $ncol; $k++) { $m = (Str $hdr[$k]).Length; foreach ($r in $rows) { $l = (Str $r[$k]).Length; if ($l -gt $m) { $m = $l } }; $w = $m * 6 + 14; if ($w -gt 320) { $w = 320 }; $w })
    }
    $o = "<Worksheet ss:Name=`"$name`">`n"
    $last = $headerRow + @($rows).Count
    $o += "<Names><NamedRange ss:Name=`"_FilterDatabase`" ss:RefersTo=`"='$name'!R${headerRow}C1:R${last}C$ncol`" ss:Hidden=`"1`"/></Names>`n"
    $o += '<Table>' + (@(foreach ($w in $widths) { "<Column ss:Width=`"$w`"/>" }) -join '') + "`n"
    if ($pre) { $o += $pre }
    $o += XRow $hdr 'h'
    $o += (@(foreach ($r in $rows) { XRow $r $null }) -join '')
    $o += "</Table>`n<WorksheetOptions xmlns=`"urn:schemas-microsoft-com:office:excel`">"
    if ($c.banner) { $b = XEsc $c.banner; $o += "<PageSetup><Header x:Margin=`"0.3`" x:Data=`"&amp;C$b`"/><Footer x:Margin=`"0.3`" x:Data=`"&amp;C$b`"/></PageSetup>" }
    $o += "<FreezePanes/><FrozenNoSplit/><SplitHorizontal>$headerRow</SplitHorizontal><TopRowBottomPane>$headerRow</TopRowBottomPane><ActivePane>2</ActivePane></WorksheetOptions>`n"
    $o += "<AutoFilter x:Range=`"R${headerRow}C1:R${last}C$ncol`" xmlns=`"urn:schemas-microsoft-com:office:excel`"/>`n</Worksheet>`n"
    $o
}
# ---------------------------------------------------------------- dashboard sheets: Health, Funding, Quad, Gantt (the cockpit's views, in Excel)
# Health and Quad need agile-more.ps1's metrics, Funding needs ledger.ps1 and the scrum.conf funding/complete keys; each sheet
# is written only when its source is there. Gantt is the roadmap on a sprint grid: # actual, . forecast, the ETA marked.
function XRaw([string]$cells) { "<Row>$cells</Row>`n" }
function XBlock([string]$title, $hdr, $rows) {
    $o = "<Row/>`n" + (XRow @($title) 't2') + (XRow $hdr 'h')
    foreach ($r in $rows) { $o += XRow $r $null }
    $o
}
function HealthSheetXml($s, $c) {
    if (-not (Get-Command HealthTable -CommandType Function -ErrorAction SilentlyContinue)) { return '' }
    $rows = @(foreach ($r in (HealthTable $s '')) {
            , @($r.team, $r.pct, $r.load, [double](Fmt1 $r.velocity), $r.trend, $r.predictability, $r.carryover, $r.ontime, $r.interrupt, $r.top_share, $r.blocked, $r.oldest_block) })
    $sig = @(HealthSignals $s (HealthOpts $s $null))
    $pre = ''; $hr = 1
    if ($c.banner) { $pre += XRow @($c.banner) 'b'; $hr++ }
    $pre += XRow @("Team health as of $($s.today), sprint $($s.current)") 't'; $hr++
    $nr = @($sig | Where-Object { $_.level -ceq 'red' }).Count; $na = @($sig | Where-Object { $_.level -ceq 'amber' }).Count
    $lvl = 'green'; if ($nr) { $lvl = 'red' } elseif ($na) { $lvl = 'amber' }
    $pre += XRow @("$nr red, $na amber signal(s)") $lvl; $hr++
    $pre += "<Row/>`n"; $hr++
    $post = ''
    if ($sig.Count) {
        $post = "<Row/>`n" + (XRow @('Signals: what to do') 't2') + (XRow @('Level', 'Metric', 'Team', 'What it saw and what to do') 'h')
        foreach ($g in $sig) { $st = $null; if ($g.level -ceq 'red' -or $g.level -ceq 'amber') { $st = $g.level }
            $post += '<Row>' + (XCell $g.level $st) + (XCell $g.metric $null) + (XCell $g.team $null) + (XCell $g.text $null) + "</Row>`n" }
    }
    $x = XSheet 'Health' @('Team', 'Done %', 'Load %', 'Velocity', 'Trend (last 3)', 'Predictability %', 'Carryover %', 'On-time %', 'Interrupt', 'Top owner share %', 'Blocked', 'Oldest block (days)') $rows $c $hr $pre @(100, 54, 54, 60, 90, 90, 74, 66, 60, 96, 56, 104)
    $x.Replace('</Table>', $post + '</Table>')
}
function FundingSheetXml($s, $c) {
    if (-not $c.funding -or -not (Get-Command FundingSnapshot -CommandType Function -ErrorAction SilentlyContinue)) { return '' }
    $f = FundingSnapshot $c.funding $c.complete $s.today
    if ($null -eq $f) { return '' }
    $pre = ''; $hr = 1
    if ($c.banner) { $pre += XRow @($c.banner) 'b'; $hr++ }
    $pre += XRow @("Funding as of $($s.today) ($($c.funding))") 't'; $hr++
    if ($f.error) { $pre += XRow @("could not read $($c.funding): $($f.error)") 'red'; $hr++; return XSheet 'Funding' @('Account') @() $c $hr $pre }
    $last = $f.points[$f.points.Count - 1]
    $pre += '<Row>' + (XCell 'Funds remaining' 'h') + (XCell $last.funds 'usd') + "</Row>`n"; $hr++
    $pre += '<Row>' + (XCell 'Spent to date' 'h') + (XCell $last.spent 'usd') + "</Row>`n"; $hr++
    if ($f.forecast) {
        $pre += '<Row>' + (XCell 'Burn per month' 'h') + (XCell $f.forecast.burn 'usd') + "</Row>`n"; $hr++
        $ro = $f.forecast.runout; if (-not $ro) { $ro = 'no burn yet' }
        $pre += '<Row>' + (XCell 'Funds run out' 'h') + (XCell $ro $null) + "</Row>`n"; $hr++
    }
    $ev = $f.evm
    $cf = ''; if ($ev -and $ev.complete_file) { $cf = $ev.complete_file }
    $pre += '<Row>' + (XCell 'Percent complete from' 'h') + (XCell $(if ($cf) { $cf } else { 'no complete-*.csv on or before today: no earned value yet' }) $null) + "</Row>`n"; $hr++
    $pre += "<Row/>`n"; $hr++
    $rows = @()
    if ($ev -and -not $ev.error) {
        foreach ($r in (@($ev.rows) + @($ev.total))) { if ($null -eq $r) { continue }
            $rows += , @($r.account, $r.pct, $r.bac, $r.bcws, $r.bcwp, $r.acwp, $r.cv, $r.sv, $r.cpi, $r.spi, $r.eac, $r.vac) }
    }
    $hdr = @('Account', '% done', 'BAC', 'BCWS (planned)', 'BCWP (earned)', 'ACWP (actual)', 'CV', 'SV', 'CPI', 'SPI', 'EAC', 'VAC')
    $styles = @($null, 'pct', 'usd', 'usd', 'usd', 'usd', 'usd', 'usd', 'r2', 'r2', 'usd', 'usd')
    $x = XSheet 'Funding' $hdr @() $c $hr $pre @(230, 56, 96, 96, 96, 96, 90, 90, 50, 50, 96, 90)
    $body = ''
    foreach ($r in $rows) { $body += '<Row>' + (@(for ($k = 0; $k -lt $r.Count; $k++) { XCell $r[$k] $styles[$k] }) -join '') + "</Row>`n" }
    if ($ev -and $ev.error) { $body += XRow @("earned value: $($ev.error)") 'red' }
    $body += XBlock 'Funds and spending by week (chart these two columns)' @('Week of', 'Funds', 'Spent') @()
    foreach ($pt in $f.points) { $body += '<Row>' + (XCell $pt.date $null) + (XCell $pt.funds 'usd') + (XCell $pt.spent 'usd') + "</Row>`n" }
    $x = $x.Replace('</Table>', $body + '</Table>')
    $n = $hr + $rows.Count
    $x -creplace 'R(\d+)C1:R\d+C12', "R`${1}C1:R${n}C12"
}
function QuadSheetXml($s, $c) {
    if (-not (Get-Command QuadData -CommandType Function -ErrorAction SilentlyContinue)) { return '' }
    $q = QuadData $s $null $null $null
    $m = $q.metrics
    $pre = ''; $hr = 1
    if ($c.banner) { $pre += XRow @($c.banner) 'b'; $hr++ }
    $pre += XRow @("Weekly quad as of $($q.as_of), sprint $($q.sprint)") 't'; $hr++
    $pre += XRow @("Sprint progress: $($m.sprint.pct)% ($($m.sprint.done) of $($m.sprint.committed) $($q.unit) done), trend $($m.sprint.trend)") $null; $hr++
    $pre += XRow @("On-time delivery: $($m.ontime.sprint_ontime) of $($m.ontime.sprint_total) this sprint, $($m.ontime.week_ontime) of $($m.ontime.week_total) this week") $null; $hr++
    $pre += "<Row/>`n" + (XRow @('Technical priorities') 't2'); $hr += 2
    $pri = @(foreach ($p in $q.priorities) { , @($p.tag, (@($p.marks) -join ' '), $p.id, $p.title, $p.owner, $p.team, $p.pts, $p.prio) })
    $x = XSheet 'Quad' @('Tag', 'Marks', 'ID', 'Title', 'Owner', 'Team', 'Points', 'Prio') $pri $c $hr $pre @(60, 74, 70, 330, 130, 100, 60, 52)
    # every block keeps the top table's columns: A tag/kind, B mark/when, C ID, D the long text (wide), E owner, F team, G-H numbers
    $post = XBlock 'Watch items / PM help' @('Kind', 'Days', 'ID', 'What', 'Owner', 'Team', '', '') @(foreach ($w in $q.watch) { , @("($($w.kind))", $w.days, $w.id, $w.text, $w.owner, $w.team, '', '') })
    $ms = @(); foreach ($h in @('30', '60', '90')) { foreach ($e in @($q.milestones[$h])) { if ($e) { $ms += , @("$h days", $e.trend, $e.eta, $e.epic, $e.tome, $e.blocked, $e.remaining, $e.pct) } } }
    $post += XBlock 'Schedule milestones (30 / 60 / 90 days)' @('Horizon', 'Moved', 'ETA', 'Epic', 'Tome', 'Blocked', 'Remaining', 'Done %') $ms
    $post += XBlock 'Accomplishments this week' @('On time', 'Done', 'ID', 'Title', 'Owner', 'Team', 'Points', '') @(foreach ($a in $q.accomplishments) { , @($(if ($a.ontime) { 'yes' } else { 'LATE' }), $a.date, $a.id, $(if ($a.ontime) { $a.title } else { "$($a.title) (late: $($a.late_why))" }), $a.owner, $a.team, $a.pts, '') })
    if (@($q.slipped).Count) { $post += XBlock 'Priorities that slipped' @('', '', 'ID', 'Title and why', 'Owner', 'Team', '', '') @(foreach ($p in $q.slipped) { , @('', '', $p.id, "$($p.title): $($p.why)", $p.owner, $p.team, '', '') }) }
    $x.Replace('</Table>', $post + '</Table>')
}
function GanttSheetXml($s, $c) {
    $rm = Roadmap $s; $span = SprintSpan $s
    $sps = @($rm.sprints); $cur = $rm.current
    $known = @(foreach ($n in $sps) { if ($span.ContainsKey("$n") -and $span["$n"].start) { [int]$n } })
    $base = $null; if ($known.Count) { $base = MaxOf $known }
    $sdate = { param($n) if ($span.ContainsKey("$n") -and $span["$n"].start) { return $span["$n"].start }; if ($null -eq $base) { return '' }; AddDays $span["$base"].start (14 * ([int]$n - $base)) }
    $hdr = @('Tome', 'Epic', 'Teams', 'Done', 'Total', 'Done %', 'ETA sprint', 'Blocked') + @(foreach ($n in $sps) { "S$n " + ((& $sdate $n) -replace '^\d{4}-', '') })
    $pre = ''; $hr = 1
    if ($c.banner) { $pre += XRow @($c.banner) 'b'; $hr++ }
    $pre += XRow @("Roadmap as of $($s.today): epics by tome across sprints (dark = actual to date, gold = forecast to the ETA at the owning teams' velocity, <> = ETA, red = blocked)") 't'; $hr++
    if (-not $sps.Count) { $pre += XRow @('No sprint has started yet: the bars appear once tasks are committed to a sprint.') $null; $hr++ }
    $pre += "<Row/>`n"; $hr++
    $x = XSheet 'Gantt' $hdr @() $c $hr $pre (@(170, 230, 120, 44, 44, 50, 60, 52) + @(foreach ($n in $sps) { 46 }))
    $body = ''; $rowsXml = ''
    foreach ($e in $rm.epics) {
        $cells = (XCell $e.tome $null) + (XCell $e.epic $null) + (XCell ($e.teams -join ' ') $null) + (XCell $e.done $null) + (XCell $e.total $null) + (XCell $e.pct $null) + (XCell $e.end $null) + (XCell $(if ($e.blocked) { $e.blocked } else { '' }) $(if ($e.blocked) { 'red' } else { $null }))
        foreach ($n in $sps) {
            $st = $null; $tx = ''
            if ($null -ne $e.first -and $n -ge $e.first) {
                if ($e.remaining -le 0) { if ($null -ne $e.end -and $n -le $e.end) { $st = 'na' } }
                elseif ($null -ne $cur -and $n -le [int]$cur) { $st = 'na' }
                elseif ($null -ne $e.end -and $n -le $e.end) { $st = 'go' }
            } elseif ($null -eq $e.first -and $null -ne $e.end -and $null -ne $cur -and $n -gt [int]$cur -and $n -le $e.end) { $st = 'go' }
            if ($null -ne $e.end -and $n -eq $e.end) { $tx = '<>' }
            if ($st -and $e.blocked -and $null -ne $cur -and $n -eq [int]$cur) { $st = 'nb' }
            $body += XCell $tx $st
        }
        $rowsXml += "<Row>$cells$body</Row>`n"
        $body = ''
    }
    $x = $x.Replace('</Table>', $rowsXml + '</Table>')
    $n = $hr + @($rm.epics).Count; $nc = $hdr.Count
    $x -creplace "R(\d+)C1:R\d+C$nc", "R`${1}C1:R${n}C$nc"
}
function WorkbookXml($s, $c) {
    $r = SprintSummary $s $s.current; $t = $r.totals; $v = Velocity $s
    $st = BriefStatus $s $s.current
    $head = $st[1]; if (-not $head) { $head = 'On track, no blockers.' }
    $sp = $r.sprint; if ($null -eq $sp) { $sp = '-' }
    $pre = ''; $hr = 1
    if ($c.banner) { $pre += XRow @($c.banner) 'b'; $hr++ }
    $pre += XRow @("Sprint $sp status as of $($s.today)") 't'; $hr++
    $pre += XRow @("$($st[0].ToUpper()): $($t.pct)% done. $head") $st[0]; $hr++
    foreach ($l in (MarkingLines $c)) { $pre += XRow @($l) $null; $hr++ }
    $pre += "<Row/>`n"; $hr++
    $teams = @(foreach ($team in (SortedKeys $r.teams)) { $x = $r.teams[$team]; $avg = $null; if ($v.avg.ContainsKey($team)) { $avg = Fmt1 $v.avg[$team] }
            $cap = $null; if ($x.capacity) { $cap = $x.capacity }
            , @($team, $cap, $x.committed, $x.done, $x.open, $x.carryover, $x.removed, $x.pct, $x.load, $avg, (Blocked $s $team).Count) })
    $teams += , @('Total', $t.capacity, $t.committed, $t.done, $t.open, $t.carryover, $t.removed, $t.pct, $t.load, $null, (Blocked $s '').Count)
    $bl = SortWith (Blocked $s '') { param($x, $y) (BlockedDays $s $y) - (BlockedDays $s $x) }
    $post = ''
    if ($bl.Count) {
        $post = "<Row/>`n" + (XRow @('Blocked', 'Team', 'Owner', 'Days', 'Blocker') 'h')
        foreach ($i in $bl) { $post += XRow @($i.id, $i.team, $i.owner, (BlockedDays $s $i), $i.blocked) $null }
    }
    $o = "<?xml version=`"1.0`" encoding=`"UTF-8`"?>`n<?mso-application progid=`"Excel.Sheet`"?>`n"
    $o += "<Workbook xmlns=`"urn:schemas-microsoft-com:office:spreadsheet`" xmlns:o=`"urn:schemas-microsoft-com:office:office`" xmlns:x=`"urn:schemas-microsoft-com:office:excel`" xmlns:ss=`"urn:schemas-microsoft-com:office:spreadsheet`">`n"
    $o += '<Styles><Style ss:ID="Default" ss:Name="Normal"><Font ss:FontName="Calibri" ss:Size="11"/></Style>' +
    '<Style ss:ID="h"><Font ss:FontName="Calibri" ss:Size="11" ss:Bold="1"/><Interior ss:Color="#D9E1F2" ss:Pattern="Solid"/><Borders><Border ss:Position="Bottom" ss:LineStyle="Continuous" ss:Weight="1"/></Borders></Style>' +
    '<Style ss:ID="d"><NumberFormat ss:Format="yyyy\-mm\-dd"/></Style><Style ss:ID="t"><Font ss:FontName="Calibri" ss:Size="14" ss:Bold="1"/></Style><Style ss:ID="b"><Font ss:FontName="Calibri" ss:Size="11" ss:Bold="1"/><Interior ss:Color="#EEEEEE" ss:Pattern="Solid"/></Style>' +
    '<Style ss:ID="red"><Font ss:FontName="Calibri" ss:Size="11" ss:Bold="1" ss:Color="#D03B3B"/></Style><Style ss:ID="amber"><Font ss:FontName="Calibri" ss:Size="11" ss:Bold="1" ss:Color="#C98500"/></Style>' +
    "<Style ss:ID=`"green`"><Font ss:FontName=`"Calibri`" ss:Size=`"11`" ss:Bold=`"1`" ss:Color=`"#0CA30C`"/></Style>" +
    '<Style ss:ID="t2"><Font ss:FontName="Calibri" ss:Size="12" ss:Bold="1"/></Style><Style ss:ID="usd"><NumberFormat ss:Format="&quot;$&quot;#,##0"/></Style>' +
    '<Style ss:ID="pct"><NumberFormat ss:Format="0%"/></Style><Style ss:ID="r2"><NumberFormat ss:Format="0.00"/></Style>' +
    '<Style ss:ID="na"><Font ss:FontName="Calibri" ss:Size="11" ss:Color="#FFFFFF"/><Interior ss:Color="#27235D" ss:Pattern="Solid"/></Style>' +
    '<Style ss:ID="go"><Interior ss:Color="#E6AF22" ss:Pattern="Solid"/></Style><Style ss:ID="nb"><Font ss:FontName="Calibri" ss:Size="11" ss:Color="#FFFFFF"/><Interior ss:Color="#D6292E" ss:Pattern="Solid"/></Style></Styles>' + "`n"
    $sum = XSheet 'Summary' @('Team', 'Capacity', 'Committed', 'Done', 'Open', 'Carryover', 'Removed', 'Done %', 'Load %', 'Avg velocity', 'Blocked') $teams $c $hr $pre @(110, 62, 66, 50, 50, 64, 60, 54, 54, 76, 56)
    $sum = $sum.Replace('</Table>', $post + '</Table>')
    $o += $sum
    foreach ($w in @(@('Backlog', 'items'), @('Sprints', 'sprints'), @('Epics', 'epics'), @('Intake', 'intake'))) { $td = TableData $s $w[1]; $o += XSheet $w[0] $td.hdr $td.rows $c }
    $o += HealthSheetXml $s $c
    $o += FundingSheetXml $s $c
    $o += QuadSheetXml $s $c
    $o += GanttSheetXml $s $c
    $o + "</Workbook>`n"
}
function WriteWorkbook($s) {
    $f = "$($script:C.reports)/backlog.xml"
    try { WriteText $f (WorkbookXml $s $script:C); Out-Text "wrote $f`n" }
    catch { Out-Err "could not write $f (open in Excel? close it and run again): $($_.Exception.Message)" }
}

# ================================================================ reports: the status mail text, the BLUF brief, an HTML page
function MarkingLines($c) {
    if (-not $c.banner) { return , @() }
    , @(foreach ($p in @(@('Owner', 'marking_owner'), @('Category', 'marking_category'), @('Handling', 'marking_handling'), @('POC', 'marking_poc'))) { if ($c[$p[1]]) { "$($p[0]): $($c[$p[1]])" } })
}
function MarkedText($c, [string]$body) {
    if (-not $c.banner) { return $body }
    $b = "$($c.banner)`n"
    "$b`n$body`n" + (@(foreach ($l in (MarkingLines $c)) { "$l`n" }) -join '') + "`n$b"
}
function NotesText($d) {
    if (-not $d) { return '' }
    $out = ''
    foreach ($team in (SortedKeys $d.teams)) {
        $t = $d.teams[$team]; $l = @()
        if ($t.done.Count) { $l += "done today: $($t.done -join ' ')" }
        if ($t.carry.Count) { $l += "carried: $($t.carry -join ' ')" }
        if ($t.drop.Count) { $l += "removed: $($t.drop -join ' ')" }
        if ($t.new.Count) { $l += 'new: ' + ($t.new -join ', ') }
        if ($t.refine.Count) { $l += "refined into the backlog: $($t.refine -join ' ')" }
        if ($t.prune.Count) { $l += 'pruned: ' + ($t.prune -join '; ') }
        if ($t.absent.Count) { $l += "absent: $($t.absent -join ' ')" }
        foreach ($x in $t.note) { $l += "note: $x" }
        foreach ($x in $t.risk) { $l += "risk: $x" }
        if ($l.Count) { $out += "$team today:`n" + (@(foreach ($x in $l) { "  $x`n" }) -join '') }
    }
    if ($d.notes.Count) { $out += "Notes:`n" + (@(foreach ($x in $d.notes) { "  $x`n" }) -join '') }
    if ($d.risks.Count) { $out += "Risks:`n" + (@(foreach ($x in $d.risks) { "  $x`n" }) -join '') }
    if ($d.extra) { $out += "`n$($d.extra)" }
    $out
}
function EmailText($s, $n, $notes, $marking, $health) {
    $r = SprintSummary $s $n; $t = $r.totals; $u = $s.unit
    $sp = $r.sprint; if ($null -eq $sp) { $sp = '-' }
    $out = "Sprint $sp status as of $($s.today): $(Trunc $t.done)/$(Trunc $t.committed) $u done ($($t.pct)%), $(Trunc $t.open) open, $(Trunc $t.carryover) carried over.`n`n"
    foreach ($team in (SortedKeys $r.teams)) {
        $x = $r.teams[$team]
        $ld = ''; if ($null -ne $x.load) { $ld = ", load $($x.load)% of capacity" }
        $out += "${team}: $(Trunc $x.done)/$(Trunc $x.committed) done ($($x.pct)%), $(Trunc $x.open) open$ld`n"
        if (@($x.open_items).Count) { $out += '  open: ' + (@(foreach ($i in $x.open_items) { "$($i.id) ($(Num $i.points))" }) -join ', ') + "`n" }
        $bl = Blocked $s $team
        if ($bl.Count) { $out += '  BLOCKED: ' + (@(foreach ($i in $bl) { "$($i.id) $($i.blocked) ($(BlockedDays $s $i)d)" }) -join '; ') + "`n" }
    }
    if ($health -and @($health | Where-Object { $_.level -cne 'info' }).Count) { $out += "`n" + (HealthText $health $false) }   # agile-more.ps1's signals
    $nt = NotesText $notes
    if ($nt) { $out += "`n$nt" }
    MarkedText $marking $out
}
function LoadStatus($load) { if ($null -eq $load) { 'good' } elseif ($load -gt 110) { 'critical' } elseif ($load -gt 100) { 'warning' } else { 'good' } }
function BriefStatus($s, $n) {
    $r = SprintSummary $s $n
    $bl = Blocked $s ''
    $crit = @(foreach ($t in (SortedKeys $r.teams)) { if ((LoadStatus $r.teams[$t].load) -ceq 'critical') { $t } })
    $risk = @(foreach ($t in (SortedKeys $r.teams)) { if ((LoadStatus $r.teams[$t].load) -cne 'good') { $t } })
    $un = Unassigned $s ''
    if ($bl.Count -ge 2 -or $crit.Count) { return @('red', "$($bl.Count) blocker$(Plural $bl.Count), $($crit.Count) team$(Plural $crit.Count) over capacity") }
    if ($bl.Count -or $risk.Count -or $un.Count) {
        if ($bl.Count) { return @('amber', "1 blocker: $($bl[0].id) ($($bl[0].team)) $($bl[0].blocked)") }
        if ($risk.Count) { return @('amber', "$($risk[0]) approaching capacity") }
        return @('amber', "$($un.Count) committed task(s) unassigned")
    }
    @('green', '')
}
function BriefText($s, $n, $marking) {
    $r = SprintSummary $s $n
    $st = BriefStatus $s $n
    $sp = $r.sprint; if ($null -eq $sp) { $sp = '-' }
    $head = $st[1]; if (-not $head) { $head = 'On track, no blockers.' }
    $out = "$($st[0].ToUpper()) -- Sprint $sp, $($s.today): $($r.totals.pct)% done. $head`n"
    $b = @()
    $crit = SortWith @(foreach ($t in (SortedKeys $r.teams)) { if ((LoadStatus $r.teams[$t].load) -ceq 'critical') { $t } }) { param($x, $y) $c = $r.teams[$y].load - $r.teams[$x].load; if ($c) { $c } else { Cmp $x $y } }
    foreach ($t in $crit) { $b += "$t at $($r.teams[$t].load)% load" }
    foreach ($i in (SortWith (Blocked $s '') { param($x, $y) (BlockedDays $s $y) - (BlockedDays $s $x) })) { $b += "$($i.id) ($($i.team)) blocked $(BlockedDays $s $i)d: $($i.blocked)" }
    $warn = SortWith @(foreach ($t in (SortedKeys $r.teams)) { if ((LoadStatus $r.teams[$t].load) -ceq 'warning') { $t } }) { param($x, $y) $c = $r.teams[$y].load - $r.teams[$x].load; if ($c) { $c } else { Cmp $x $y } }
    foreach ($t in $warn) { $b += "$t approaching capacity ($($r.teams[$t].load)%)" }
    $un = Unassigned $s ''; if ($un.Count) { $b += "$($un.Count) committed task(s) unassigned" }
    $extra = 0; if ($b.Count -gt 5) { $extra = $b.Count - 5; $b = @($b[0..4]) }
    if ($b.Count) { $out += "`n" + (@(foreach ($x in $b) { "- $x`n" }) -join '') }
    if ($extra) { $out += "  (+$extra more -- see the full status report)`n" }
    MarkedText $marking $out
}
function Esc([string]$s) { if ($null -eq $s) { return '' }; $s.Replace('&', '&amp;').Replace('<', '&lt;').Replace('>', '&gt;').Replace('"', '&quot;') }
function HtmlTable($hdr, $rows, $right) {
    $isR = @{}; foreach ($c in @($right)) { $isR["$c"] = 1 }
    $o = '<table><tr>' + (@(for ($c = 0; $c -lt $hdr.Count; $c++) { $cl = ''; if ($isR.ContainsKey("$c")) { $cl = ' class=n' }; "<th$cl>$(Esc $hdr[$c])</th>" }) -join '') + "</tr>`n"
    foreach ($r in $rows) { $o += '<tr>' + (@(for ($c = 0; $c -lt $hdr.Count; $c++) { $cl = ''; if ($isR.ContainsKey("$c")) { $cl = ' class=n' }; "<td$cl>$(Esc (Str $r[$c]))</td>" }) -join '') + "</tr>`n" }
    $o + "</table>`n"
}
function StatusHtml($s, $n, $notes, $flagsText, $c) {
    $r = SprintSummary $s $n; $t = $r.totals
    $st = BriefStatus $s $n
    $color = @{ red = '#d03b3b'; amber = '#c98500'; green = '#0ca30c' }[$st[0]]
    $head = $st[1]; if (-not $head) { $head = 'On track, no blockers.' }
    $banner = ''; if ($c.banner) { $banner = "<div class=banner>$(Esc $c.banner)</div>`n" }
    $mk = MarkingLines $c; $block = ''; if ($mk.Count) { $block = '<p class=mark>' + (@(foreach ($l in $mk) { Esc $l }) -join '<br>') + "</p>`n" }
    $o = "<!doctype html><html><head><meta charset=utf-8><title>Sprint $($r.sprint) status $($s.today)</title><style>" +
    'body{font-family:Segoe UI,Arial,sans-serif;margin:24px;color:#222;max-width:1000px}h1{font-size:20px}h2{font-size:16px;margin-top:22px}' +
    'table{border-collapse:collapse;margin:6px 0;font-size:13px}th,td{border:1px solid #ccc;padding:3px 8px;text-align:left}th{background:#f2f2f2}.n{text-align:right}' +
    '.st{font-weight:700}.banner{text-align:center;font-weight:700;background:#eee;padding:4px}.mark{font-size:12px}pre{font-size:13px;background:#f8f8f8;padding:8px;white-space:pre-wrap}' +
    "@media print{body{margin:0}}</style></head><body>`n$banner$block"
    $o += "<h1>Sprint $(Esc $r.sprint) status, $(Esc $s.today)</h1>`n<p><span class=st style=`"color:$color`">$($st[0].ToUpper())</span> &middot; $($t.pct)% done &middot; $(Esc $head)</p>`n"
    $rows = @(foreach ($team in (SortedKeys $r.teams)) { $x = $r.teams[$team]; $ld = ''; if ($null -ne $x.load) { $ld = "$($x.load)%" }; $cap = ''; if ($x.capacity) { $cap = $x.capacity }
            , @($team, $cap, $x.committed, $x.done, $x.open, $x.carryover, $x.removed, "$($x.pct)%", $ld) })
    $ld = ''; if ($null -ne $t.load) { $ld = "$($t.load)%" }; $cap = ''; if ($t.capacity) { $cap = $t.capacity }
    $rows += , @('Total', $cap, $t.committed, $t.done, $t.open, $t.carryover, $t.removed, "$($t.pct)%", $ld)
    $o += "<h2>Teams</h2>`n" + (HtmlTable @('Team', 'Cap', 'Commit', 'Done', 'Open', 'Carry', 'Removed', 'Done%', 'Load%') $rows @(1..8))
    $bl = SortWith (Blocked $s '') { param($x, $y) (BlockedDays $s $y) - (BlockedDays $s $x) }
    if ($bl.Count) { $o += "<h2>Blocked</h2>`n" + (HtmlTable @('ID', 'Team', 'Owner', 'Days', 'Blocker') @(foreach ($i in $bl) { , @($i.id, $i.team, $i.owner, (BlockedDays $s $i), $i.blocked) }) @(3)) }
    foreach ($team in (SortedKeys $r.teams)) {
        $open = @($r.teams[$team].open_items)
        if ($open.Count) { $o += "<h2>$(Esc $team) open tasks ($($open.Count))</h2>`n" + (HtmlTable $script:ITEM_HDR @(foreach ($i in $open) { , (ItemRow $i) }) $script:ITEM_R) }
    }
    $nt = NotesText $notes
    if ($nt) { $o += "<h2>Today</h2>`n<pre>$(Esc $nt)</pre>`n" }
    if ($flagsText) { $o += "<h2>Flags from the stand-up chat</h2>`n<pre>$(Esc $flagsText)</pre>`n" }
    $o += "<h2>Velocity</h2>`n<pre>$(Esc (VelocityText $s))</pre>`n<h2>Roadmap</h2>`n<pre>$(Esc (RoadmapText $s))</pre>`n"
    $o + "$block$banner</body></html>`n"
}

# ================================================================ #est / #vote tallies (Chat.pm), daily.pl chat
# A round opens with a marker message (#est ID, #vote Question? y/n, #vote Name: A B C) and runs to the next marker.
# Only the first line of a reply counts; one answer per person, the latest wins; a comment never replaces a vote.
# Fixed rather than copied: Chat.pm has no "use utf8", so Perl never reads a thumbs-up/down or check/cross as a
# vote, and prints the em dash in "re-discuss with" as mojibake. Here the emoji are votes, and the dash is " -- " (ASCII, safe in any console code page).
$script:EST_UNIT = '(?:sp|pts?|points?|story\s*points?|h|hrs?|hours?|d|days?)'
$script:EST_PRE = "(?:actually|revote|re-vote|my vote|vote|make it|change(?:\s+(?:mine|my vote))?\s+to|now|ok|okay|i'?d say|i say|say|call it|i think)"
$script:EST_HEDGE = '(?:maybe|probably|i think|ish|or so|tops|at most)'
$script:YESW = @('y', 'yes', '+1', 'aye', 'ok', 'go', 'ship', $script:THUMB, $script:CHECK, [string][char]0x2714, 'yep', 'yup', 'agree', 'approve')
$script:NOW = @('n', 'no', '-1', 'nay', "$([char]0xD83D)$([char]0xDC4E)", [string][char]0x274C, [string][char]0x2716, 'nope', 'disagree', 'reject', 'hold')
function InList($x, $list) { foreach ($y in $list) { if ($x -ceq $y) { return $true } }; $false }
function NormEstimate([string]$raw) {                       # -> number | '?' | $null
    $t = ('' + $raw).ToLower().Trim()
    if ($t -cmatch ('^(?:\?|idk|unknown|' + [char]0x2615 + '|coffee|pass)$')) { return '?' }
    if ($t -cmatch "^(?:$($script:EST_PRE)[,:]?\s+)?(\d+(?:\.\d+)?)\s*$($script:EST_UNIT)?\.?(?:\s*,?\s*$($script:EST_HEDGE))?[.!]?$") { return [double]$Matches[1] }
    $null
}
function NormVote([string]$raw, $opts) {
    $t = ('' + $raw).ToLower().Trim() -creplace '[.!]+$', ''
    $opts = @($opts | Where-Object { $null -ne $_ })
    if ($opts.Count -and (InList $t $opts)) { return $t }
    $y = $null; foreach ($o in $opts) { if ($o -ceq 'yes' -or $o -ceq 'y') { $y = $o; break } }
    $n = $null; foreach ($o in $opts) { if ($o -ceq 'no' -or $o -ceq 'n') { $n = $o; break } }
    $word = $t -creplace '^(\S+?)[,.!:;]*(?:\s.*)?$', '$1'
    if ((InList $t $script:YESW) -or (InList $word $script:YESW)) { if ($null -ne $y) { return $y }; return 'yes' }
    if ((InList $t $script:NOW) -or (InList $word $script:NOW)) { if ($null -ne $n) { return $n }; return 'no' }
    if ($opts.Count) {
        $hit = @(foreach ($o in $opts) { if ($o -ceq $word) { $o } })
        if (-not $hit.Count) { $hit = @(foreach ($o in $opts) { if ($o.Length -ge 3 -and $t.IndexOf($o) -ge 0) { $o } }) }
        if ($hit.Count -eq 1) { return $hit[0] }
    }
    if ($t -cmatch '^(?:abstain|pass|skip|-)$') { return 'abstain' }
    $null
}
function FirstLine($t) { if ($null -eq $t) { return '' }; (('' + $t) -split "`n")[0] }
function ChatRounds($msgs) {
    $rounds = @(); $r = $null
    foreach ($m in $msgs) {
        $lineList = @($m.text -split "`n"); $first = FirstLine $m.text
        $marker = $null; foreach ($l in $lineList) { if ($l -match '^\s*#\s*(?:est(?:imate)?|vote|poll)\b') { $marker = $l; break } }
        if ($marker -and $marker -match '^\s*#\s*(est(?:imate)?|vote|poll)\b\s*(.*?)\s*$') {
            $k = $Matches[1]; $subj = $Matches[2]
            $kind = 'vote'; if ($k.ToLower() -cmatch '^est') { $kind = 'est' }
            $opts = @()
            if ($kind -eq 'vote' -and $subj -cmatch '^(.*[?:])\s*(\S.*)$') {
                $stem = $Matches[1]; $tail = $Matches[2]
                $o = @(foreach ($x in ($tail -csplit '\s*/\s*|\s+')) { if ($x.Length) { $x.ToLower() } })
                $long = @($o | Where-Object { $_.Length -gt 12 }).Count
                if ($o.Count -ge 2 -and $o.Count -le 8 -and -not $long) { $opts = $o; $subj = $stem -creplace ':$', '' }
            }
            $r = @{ kind = $kind; subject = $subj; options = $opts; by = $m.who; time = $m.time; answers = @{}; msgs = @(); discussion = @() }
            $rounds += $r
            continue
        }
        if (-not $r) { continue }
        $r.msgs += $m
        if ($r.kind -eq 'est') { $ans = NormEstimate $first } else { $ans = NormVote $first $r.options }
        if ($null -ne $ans) { $r.answers[(CK $m.who)] = @{ who = $m.who; raw = $first } } else { $r.discussion += $m }
    }
    , $rounds
}
function Tally($r) {
    $by = @{}; $names = @(); $unparsed = @()
    foreach ($w in (SortOn @($r.answers.Values) { param($x) $x.who })) {
        if ($r.kind -eq 'est') { $v = NormEstimate $w.raw } else { $v = NormVote $w.raw $r.options }
        if ($null -ne $v) { $by[(CK $w.who)] = @{ who = $w.who; v = $v }; $names += $w.who } else { $unparsed += , @($w.who, $w.raw) }
    }
    $said = @{}
    foreach ($m in $r.discussion) { if ($by.ContainsKey((CK $m.who)) -or $m.who -ceq ('' + $r.by)) { continue }; $said[(CK $m.who)] = @{ who = $m.who; t = (FirstLine $m.text) } }
    foreach ($x in (SortOn @($said.Values) { param($z) $z.who })) { $unparsed += , @($x.who, $x.t) }
    $t = @{ kind = $r.kind; subject = $r.subject; by = $r.by; time = $r.time; n = $by.Count; by_who = $by; names = (Sorted $names); unparsed = $unparsed }
    if ($r.kind -eq 'est') {
        $nums = Sorted @(foreach ($x in $by.Values) { if ($x.v -isnot [string]) { $x.v } })
        $t.unknown = Sorted @(foreach ($x in $by.Values) { if ($x.v -is [string]) { $x.who } })
        if ($nums.Count) {
            $c = $nums.Count
            $t.min = $nums[0]; $t.max = $nums[$c - 1]
            if ($c % 2) { $t.median = $nums[[int](($c - 1) / 2)] } else { $t.median = ($nums[$c / 2 - 1] + $nums[$c / 2]) / 2 }
            $cnt = @{}; foreach ($x in $nums) { $k = Num $x; if ($cnt.ContainsKey($k)) { $cnt[$k]++ } else { $cnt[$k] = 1 } }
            $modes = SortOn (Keys $cnt) { param($k) , @(- $cnt[$k], $k) }
            $t.mode = [double]$modes[0]
            $t.consensus = [int]($c -ge 2 -and $nums[0] -eq $nums[$c - 1])
            $t.spread = $nums[$c - 1] - $nums[0]
            if ($t.consensus) { $t.result = $nums[0] } else { $t.result = $t.median }
            $lim = $t.median; if (-not $lim) { $lim = 1 }
            $t.outliers = Sorted @(foreach ($x in $by.Values) { if ($x.v -is [string]) { continue }; $d = $x.v - $t.median; if ($d -lt 0) { $d = -$d }; if ($d -gt $lim) { $x.who } })   # no [math] in CLM
        }
    }
    else {
        $voters = @{}; foreach ($x in $by.Values) { if (-not $voters.ContainsKey($x.v)) { $voters[$x.v] = @() }; $voters[$x.v] += $x.who }
        $t.voters = @{}; $t.counts = @{}
        foreach ($k in (Keys $voters)) { $t.voters[$k] = Sorted $voters[$k]; $t.counts[$k] = $voters[$k].Count }
        $t.order = SortOn (Keys $t.counts) { param($k) , @(- $t.counts[$k], $k) }
        $cast = 0; foreach ($k in $t.order) { if ($k -cne 'abstain') { $cast += $t.counts[$k] } }
        $t.result = $null; if ($t.order.Count) { $t.result = $t.order[0] }
        $t.tie = [int]($t.order.Count -ge 2 -and $t.counts[$t.order[0]] -eq $t.counts[$t.order[1]])
        $t.majority = [int]($t.result -and $cast -and $t.counts[$t.result] * 2 -gt $cast)
        $t.unanimous = [int]($t.result -and $cast -and $t.counts[$t.result] -eq $cast)
    }
    $t
}
function TallyText($t) {
    $out = ''; $at = ''; if ($t.time) { $at = " at $($t.time)" }
    if ($t.kind -eq 'est') {
        $out += "ESTIMATE $($t.subject)  ($($t.n) answers$at)`n"
        foreach ($w in $t.names) { $out += ('  {0,-14} {1}' -f $w, (Str $t.by_who[(CK $w)].v)) + "`n" }
        if ($null -ne $t.median) {
            if ($t.consensus) { $out += "  consensus: $(Num $t.result)`n" }
            else {
                $ol = ''; if ($t.outliers.Count) { $ol = " -- re-discuss with " + ($t.outliers -join ', ') }
                $out += "  no consensus: median $(Num $t.median), mode $(Num $t.mode), range $(Num $t.min)-$(Num $t.max)$ol`n"
            }
        }
        if ($t.unknown -and $t.unknown.Count) { $out += '  unknown: ' + ($t.unknown -join ', ') + "`n" }
    }
    else {
        $out += "VOTE $($t.subject)  ($($t.n) votes$at)`n"
        foreach ($o in $t.order) { $out += ('  {0,-10} {1,2}  {2}' -f $o, $t.counts[$o], ($t.voters[$o] -join ', ')) + "`n" }
        if ($t.n -eq 0) { $out += "  no votes`n" } elseif ($t.tie) { $out += "  TIE`n" }
        else { $how = ' (plurality)'; if ($t.unanimous) { $how = ' (unanimous)' } elseif ($t.majority) { $how = ' (majority)' }; $out += "  result: $($t.result)$how`n" }
    }
    if ($t.unparsed.Count) { $out += '  could not read: ' + (@(foreach ($u in $t.unparsed) { "$($u[0]) '$($u[1])'" }) -join '; ') + "`n" }
    $out
}
function StandupLinesOf($tallies) {                    # est lines ready to uncomment (consensus) or commented; votes as notes
    $out = ''
    foreach ($t in $tallies) {
        if ($t.kind -eq 'est') {
            $id = $null; if ($t.subject -cmatch '([A-Za-z][A-Za-z0-9_]*-\d+)') { $id = $Matches[1] }
            $votes = (@(foreach ($w in $t.names) { "$w $(Str $t.by_who[(CK $w)].v)" }) -join ', ')
            if ($null -ne $t.result -and $id) {
                if ($t.consensus) { $out += "est $id $(Num $t.result)   ; consensus: $votes`n" } else { $out += "; est $id $(Num $t.result)   ; median, no consensus: $votes`n" }
            }
            else { $v = $votes; if (-not $v) { $v = 'no answers' }; $out += "; est $($t.subject): $v`n" }
        }
        else {
            $res = 'no votes'; if ($t.n) { if ($t.tie) { $res = 'tie' } else { $res = $t.result } }
            $cs = (@(foreach ($o in $t.order) { "$o $($t.counts[$o])" }) -join ', '); if (-not $cs) { $cs = '-' }
            $out += "note vote $($t.subject) -> $res ($cs)`n"
        }
    }
    $out
}
function ChatReport([string]$text) {
    $ts = @(foreach ($r in (ChatRounds (ParseChat $text))) { Tally $r })
    @{ text = (@(foreach ($t in $ts) { TallyText $t }) -join "`n"); lines = (StandupLinesOf $ts); n = $ts.Count }
}
function QuickTally([string]$kind, $msgs, [string]$after, $opts, [string]$subj) {   # Chat::quick_est / quick_vote: no markers, every answer after -Since
    $ans = @{}
    foreach ($m in $msgs) {
        if ($after -and $m.time -and (SLt $m.time $after)) { continue }
        $first = FirstLine $m.text
        if ($kind -eq 'est') { $v = NormEstimate $first } else { $v = NormVote $first $opts }
        if ($null -ne $v) { $ans[(CK $m.who)] = @{ who = $m.who; raw = (Str $v) } }
    }
    Tally @{ kind = $kind; subject = $subj; options = @($opts); by = $null; time = $null; answers = $ans; discussion = @() }
}
function Cmd-Tally($a) {                               # bin/chat.pl: tally a pasted chat file (or stdin: FILE - or none)
    $file = '-'; if (@($a).Count -and $a[0]) { $file = $a[0] }
    if ($file -eq '-') { $text = ((@($script:STDIN) | ForEach-Object { "$_" }) -join "`n") + "`n" }
    else { $text = ReadText $file; if ($null -eq $text) { throw "cannot open ${file}: No such file or directory`n" } }
    if ($Messages) {
        foreach ($m in (ParseChat $text)) { $tm = $m.time; if (-not $tm) { $tm = '--:--' }; Write-Output ('{0} {1,-20} {2}' -f $tm, $m.who, (FirstLine $m.text)) }
        return
    }
    if ($Est -or $Vote) {
        $ms = ParseChat $text
        if ($Est) { $t = QuickTally 'est' $ms $Since @() $Est }
        else { $o = 'y/n'; if ($Options) { $o = $Options }; $t = QuickTally 'vote' $ms $Since @(foreach ($x in ($o -csplit '[/,\s]+')) { if ($x) { $x.ToLower() } }) $Vote }
        if ($Lines) { Out-Text (StandupLinesOf @($t)) } else { Out-Text (TallyText $t) }
        return
    }
    $rep = ChatReport $text
    if ($Lines) { Out-Text $rep.lines }
    elseif ($rep.n) { Out-Text $rep.text }
    else { Out-Text "no #est / #vote markers found (use -Est ID or -Vote Q for markerless tallies)`n" }
}
function Cmd-Chat($a) {
    $s = Load-S
    $chat = "$($script:C.standups)/$($script:TODAY)-chat.txt"; if (@($a).Count -and $a[0]) { $chat = $a[0] }
    if (-not (Test-Path -LiteralPath $chat)) { Out-Text "no chat file: $chat  (paste the Teams meeting chat there)`n"; $script:RC = 1; return }
    $text = ReadText $chat
    $rep = ChatReport $text
    if (-not $rep.n) { Out-Text "no #est / #vote markers in $chat`n"; $script:RC = 1; return }
    Out-Text $rep.text
    $path = "$($script:C.standups)/$($script:TODAY).txt"
    if (-not (Test-Path -LiteralPath $path)) { Cmd-New @() }
    $body = ReadText $path
    $perTeam = @{}; $global = @()
    foreach ($l in ($rep.lines -split "`n")) {
        if ($l -eq '') { continue }
        if ($l -cmatch '^est (\S+) ' -and -not $s.items.ContainsKey($Matches[1])) { $l = "; $l   ; task not in journal yet" }
        if ($l -cmatch '^;?\s*est (\S+)' -and $s.items.ContainsKey($Matches[1]) -and $s.items[$Matches[1]].team -and $s.items[$Matches[1]].team -cne 'Master') {
            $tm = $s.items[$Matches[1]].team; $k = CK $tm
            if (-not $perTeam.ContainsKey($k)) { $perTeam[$k] = @{ team = $tm; lines = @() } }
            $perTeam[$k].lines += $l
        }
        elseif ($l -cmatch '^est (\S+)') { $global += "; $l   ; in the master backlog: move under a team section to apply" }
        else { $global += $l }
    }
    $homeTeam = $null
    if ($chat -cmatch '(?:^|[/\\])\d{4}-\d{2}-\d{2}-(.+?)-chat\.txt$') { $homeTeam = $Matches[1] } elseif ($script:C.default_team) { $homeTeam = $script:C.default_team }
    if ($null -eq $homeTeam -and @($global | Where-Object { $_ -cmatch '^;?\s*est ' }).Count) {
        Out-Err 'chat: no team for est lines of tasks not in the journal yet: set default_team in scrum.conf or name the chat file DATE-Team-chat.txt'
    }
    $gh = "==`n"; if ($null -ne $homeTeam) { $gh = "== $homeTeam`n" }
    $chatLines = ''
    foreach ($e in (SortOn @($perTeam.Values) { param($x) $x.team })) { $chatLines += "== $($e.team)`n" + (@(foreach ($l in $e.lines) { "$l`n" }) -join '') }
    if ($global.Count) { $chatLines += $gh + (@(foreach ($l in $global) { "$l`n" }) -join '') }
    if ($null -ne $body -and $body.IndexOf($chatLines) -ge 0) { return }
    AppendText $path "`n; ---- chat $($script:TODAY)`n$chatLines"
    Out-Text "appended to $path (uncomment the est lines you accept; note lines apply as-is)`n"
}

# ================================================================ Teams 1:1 messages (-Private), the roster's e-mails
function RosterEmails([string]$file) {                # roster.txt (Name | email | Team | Role | Org, or the old "Name, email") -> name -> email
    $e = @{}
    $t = ReadText $file; if ($null -eq $t) { return $e }
    foreach ($l in ($t -csplit "`r?`n")) {
        if ($l -cmatch '^\s*(#|$)') { continue }
        if ($l.Contains('|')) { $f = @($l -csplit '\s*\|\s*', 5) } else { $f = @($l -csplit '\s*,\s*', 5) }
        $f = @(foreach ($x in $f) { $x.Trim() })
        if (-not $f[0]) { continue }
        if ($f.Count -gt 1 -and $f[1] -cmatch '@') { $e[(CK $f[0])] = $f[1] }
    }
    $e
}
function TeamsChatLink([string]$email, [string]$text) {   # opens a 1:1 Teams chat with the message filled in; the person presses Send
    # UTF-8 percent-encoding. Fixed rather than copied: Perl encodes a character above 0xFF as %<code point> (a
    # thumbs-up becomes %1F44D), which Teams cannot read; RFC 3986 encodes its UTF-8 bytes.
    $enc = [uri]::EscapeDataString($text)           # .NET 4 leaves !*'() as they are; Perl escapes all but A-Za-z0-9-_.~
    $enc = $enc.Replace('!', '%21').Replace('*', '%2A').Replace("'", '%27').Replace('(', '%28').Replace(')', '%29')
    "https://teams.microsoft.com/l/chat/0/0?users=$email&message=$enc"
}
$script:PAGE_CSS = @'
:root{--surface:#ffffff;--page:#f4f4f5;--ink:#0b0b0b;--ink2:#4a4a4c;--muted:#808082;
--grid:#e4e4e7;--baseline:#c9c9cc;--border:rgba(11,11,11,.10);
--navy:#27235d;--gold:#e6af22;--lblue:#aac1d7;--lgrey:#e4e4e7;--blue:var(--navy);--good:#0ca30c;--warning:#fab219;--serious:#ec835a;--critical:#d03b3b}
*{box-sizing:border-box}
body{font-family:"Segoe UI",Arial,sans-serif;font-size:13px;color:var(--ink);background:var(--page);margin:0;padding:14px 18px;max-width:1900px}
h1{font-size:19px;margin:0 0 2px}
h2{font-size:15px;border-bottom:2px solid var(--ink);margin:18px 0 6px;padding-bottom:3px}
h3{font-size:13px;margin:10px 0 4px;color:var(--ink2)}
.muted{color:var(--muted)}
table{border-collapse:collapse;margin:4px 0 10px;width:100%;background:var(--surface);font-size:12px}
caption{caption-side:top;text-align:left;font-weight:600;color:var(--ink2);padding:2px 0 3px;font-size:11.5px}
.rm td.a{background:var(--blue);color:#fff;text-align:center;font-size:10.5px;font-variant-numeric:tabular-nums}
.rm td.c{background:#b7d3f6;text-align:center;font-size:10.5px;font-variant-numeric:tabular-nums}
.rm td.f{background:repeating-linear-gradient(135deg,#dcd9cf 0 3px,#f7f6f2 3px 7px)}
.rm td.cur,.rm th.cur{box-shadow:inset 0 0 0 2px var(--ink)}
.rm tr.tome td{background:var(--olive);color:#fff;font-weight:600}
th,td{border:1px solid var(--grid);padding:3px 7px;text-align:left;vertical-align:top}
th{background:var(--lgrey);font-weight:600}td.n,th.n{text-align:right;font-variant-numeric:tabular-nums}
tr:nth-child(even) td{background:#f5f4f0}
.cols{display:flex;gap:20px;flex-wrap:wrap}.cols>div{flex:1 1 280px}
.tiles{display:flex;gap:8px;flex-wrap:wrap;margin:8px 0 4px}
.tile{flex:1 1 105px;background:var(--surface);border:1px solid var(--border);border-radius:6px;padding:6px 10px}
.tile .n{font-size:20px;font-weight:700;font-variant-numeric:tabular-nums;line-height:1.15}
.tile .l{font-size:10px;color:var(--ink2);text-transform:uppercase;letter-spacing:.03em}
.tile.critical .n{color:var(--critical)}.tile.warning .n{color:#9a6300}
.bar{display:inline-block;height:10px;background:var(--grid);vertical-align:middle;border-radius:5px;overflow:hidden}
.bar span{display:block;height:100%;background:var(--blue)}
.warn{color:var(--critical);font-weight:bold}
.chip{display:inline-block;padding:1px 7px;border-radius:9px;font-weight:600;font-size:10.5px;white-space:nowrap}
.chip.good{background:var(--good);color:#fff}.chip.info{background:var(--rule,#ddd);color:var(--ink)}.chip.warning{background:var(--warning);color:var(--ink)}
.chip.serious{background:var(--serious);color:var(--ink)}.chip.critical{background:var(--critical);color:#fff}
.attn{border:1px solid var(--border);border-radius:6px;background:var(--surface);padding:2px 12px;margin:6px 0 6px}
.attn .loadrow{display:flex;flex-wrap:wrap;gap:8px;align-items:center;padding:6px 0;font-size:11.5px}
.attn .loadrow .chip{margin-right:2px}
.attn h2{margin:8px 0 2px}
.attn table{margin:4px 0}.attn p.ok{color:var(--ink2);padding:4px 0;font-size:12px}
details{border:1px solid var(--grid);border-radius:6px;margin:4px 0;background:var(--surface)}
details>summary{cursor:pointer;padding:5px 10px;font-weight:600}
details>summary::-webkit-details-marker{display:none}
details>table{margin:0 10px 10px;width:calc(100% - 20px)}
.topbar{display:flex;justify-content:space-between;align-items:baseline;flex-wrap:wrap;gap:10px;border-bottom:1px solid var(--grid);padding-bottom:6px;margin-bottom:0}
.topbar h1 svg.logo{height:22px;width:auto;color:#fff;vertical-align:-3px;margin-right:12px}
.topbar h1{margin:0}
.topbar .badges{display:flex;gap:8px;flex-wrap:wrap}
.ticker{color:var(--ink2);font-size:11.5px;margin:5px 0 2px;font-variant-numeric:tabular-nums}
.grid-wrap{display:flex;gap:8px;align-items:flex-start;margin:4px 0}
.section-label{writing-mode:vertical-rl;transform:rotate(180deg);font-size:10px;letter-spacing:.08em;color:var(--muted);font-weight:700;text-transform:uppercase;padding:4px 0}
.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(155px,1fr));gap:8px;flex:1}
.card{border:1px solid var(--border);border-left:4px solid var(--baseline);border-radius:7px;background:var(--surface);padding:8px 10px}
.card.status-good{border-left-color:var(--good)}
.card.status-warning{border-left-color:var(--warning)}
.card.status-critical{border-left-color:var(--critical)}
.card-head{display:flex;justify-content:space-between;align-items:center;gap:6px;margin-bottom:1px}
.card-head h3{margin:0;font-size:13px}
.card-desc{margin:1px 0 5px;font-size:11px;color:var(--ink2)}
.facts{list-style:none;margin:5px 0;padding:0;font-size:11px;color:var(--ink2)}
.facts li{padding:0}
.tags{display:flex;flex-wrap:wrap;gap:3px;margin:6px 0 1px}
.tag{background:#eceae2;color:var(--ink2);border-radius:4px;padding:1px 6px;font-size:10px;font-weight:600}
.card details{border:0;background:transparent;margin:5px 0 0;border-radius:0}
.card details>summary{padding:2px 0;font-size:11px;font-weight:600;color:var(--blue)}
.card details>table{margin:4px 0 0;width:100%;font-size:10.5px}
.card details>table td,.card details>table th{padding:2px 5px}

'@
function MarkBannerHtml($c, [string]$pos) { if (-not $c.banner) { return '' }; "<p style=""text-align:center;font-weight:bold;font-family:Arial,sans-serif"" class=""mark mark-$pos"">$(Esc $c.banner)</p>`n" }
function MarkBlockHtml($c) { $l = MarkingLines $c; if (-not $c.banner -or -not $l.Count) { return '' }; '<p style="font-family:Arial,sans-serif;font-size:12px" class="mark-block">' + (@(foreach ($x in $l) { Esc $x }) -join '<br>') + "</p>`n" }
function MessagesHtml([string]$day, [string]$title, $msgs, $c) {   # Scrum::messages_html: one page, a "send in Teams 1:1" link per person
    $css = ($script:PAGE_CSS -replace "`r", '')       # ends in a newline, as Perl's heredoc does
    $h = "<!DOCTYPE html>`n<html><head><meta charset=""utf-8""><title>$(Esc $title) $day</title><style>$css pre{white-space:pre-wrap;background:#f7f7f7;padding:8px;border:1px solid #ddd;margin:2px 0 10px}`nh3{margin:14px 0 2px}a.send{font-size:12px;font-weight:600;margin-left:10px}</style></head><body>`n"
    $h += (MarkBannerHtml $c 'top') + (MarkBlockHtml $c) + "<h1>$(Esc $title) <span class=muted>$day</span></h1>`n"
    $h += "<p class=muted>Each link opens a private 1:1 Teams chat with the message filled in; press Send there. The meeting chat stays clean; only the two of you see it.</p>`n"
    $known = 0
    foreach ($m in $msgs) {
        if ($m.email) { $known++; $a = " <a class=send href=""$(Esc (TeamsChatLink $m.email $m.text))"">send in Teams (1:1)</a>" } else { $a = ' <span class=muted>(no e-mail known: add to roster.txt)</span>' }
        $h += "<h3>$(Esc $m.who)$a</h3>`n<pre>$(Esc $m.text)</pre>`n"
    }
    $h += "<p class=muted>e-mail known for $known/$(@($msgs).Count)</p>`n"
    $h + (MarkBannerHtml $c 'bottom') + "</body></html>`n"
}
function PrivatePage($kind, $title, $msgs) {           # reports/<date>-<kind>.html; e-mails from roster.txt (no Outlook here)
    $em = RosterEmails 'roster.txt'
    foreach ($m in $msgs) { $m.email = $em[(CK $m.who)] }
    EnsureDir $script:C.reports
    $f = "$($script:C.reports)/$($script:TODAY)-$kind.html"
    WriteText $f (MessagesHtml $script:TODAY $title $msgs $script:C)
    $k = @($msgs | Where-Object { $_.email }).Count
    Out-Text "wrote $f  ($(@($msgs).Count) people, e-mail known for $k)`n"
}
function Cmd-Propose($teams) {                         # today's status drafted from yesterday's, one paste-ready line per person
    $s = Load-S
    $teams = @($teams | Where-Object { $_ }); if (-not $teams.Count) { $teams = @($s.teams) }
    $priv = @(); $all = @()
    foreach ($team in $teams) {
        $h = AnswerHistory $script:C.standups $team $script:TODAY ([int]$script:C.history_days)
        $ps = @(foreach ($x in (Propose $s $team $h (RosterOf $s $team))) { $x })
        if (-not $ps.Count) { continue }
        foreach ($p in $ps) { $done = ''; if ($p.y -cmatch $script:ID_RE) { $done = ' done?' }; $p["line"] = "$($p.who): Y $($p.y)$done T $($p.t) B $($p.b)  -- $($script:THUMB) if right, or repost your own Y/T/B" }
        $all += $ps
        if ($Private) {
            foreach ($p in $ps) { $d = ''; if ($p.line -cmatch ' done\? ') { $d = ' done?' }
                $priv += @{ who = $p.who; text = "Hey $(FirstName $p.who)! Your status for today, from yesterday's: Y $($p.y)$d T $($p.t) B $($p.b)  -- $($script:THUMB) if right, or post your own Y/T/B in the meeting chat" } }
            continue
        }
        $from = '  (no history yet)'; if (@($h).Count) { $from = "  (from $($h[0].date))" }
        Out-Text ("== $team$from`n" + (@(foreach ($p in $ps) { "$($p.line)`n" }) -join '') + "`n")
    }
    if ($Private) { PrivatePage 'propose' 'Proposed statuses' $priv }
    elseif ($Clip) {                                  # the lines on the clipboard, Unicode intact, for Ctrl+V in the Teams chat
        if ($all.Count) { Set-Clipboard -Value (@(foreach ($p in $all) { $p.line }) -join "`r`n"); Out-Err "$($all.Count) line$(Plural $all.Count) copied: paste into the Teams chat (Ctrl+V)" }
    }
    if ($all.Count) {                                 # an ack in the chat (+1, y, ok, thumbs-up) then accepts the line (lint, answers)
        EnsureDir $script:C.standups
        $pf = "$($script:C.standups)/$($script:TODAY)-proposals.txt"
        WriteText $pf ("# who`tY`tT`tB   (daily.pl propose $($script:TODAY); an ack in the chat -- +1, y, ok, thumbs-up -- accepts the line)`n" + (@(foreach ($p in $all) { "$($p.who)`t$($p.y)`t$($p.t)`t$($p.b)`n" }) -join ''))
        Out-Text "wrote $pf`n"
    }
}

# ================================================================ the status mail and the brief as HTML (Scrum::email_html, brief_html)
# Byte for byte what daily.pl draft / brief put in the Outlook draft and report writes. Inline styles and tables only:
# it pastes into a Teams post or an Outlook mail and renders the same.
$script:EMAIL_COLOR = @{ good = '#0ca30c'; warning = '#c98500'; critical = '#d03b3b' }
function MarkedMailHtml($c, [string]$body) { (MarkBannerHtml $c 'top') + $body + (MarkBlockHtml $c) + (MarkBannerHtml $c 'bottom') }
function SubjectOf($c, [string]$text) { if ($c.subject_prefix) { return "$($c.subject_prefix) $text" }; $text }
function EmailDot([string]$level) { "<span style=""display:inline-block;width:8px;height:8px;border-radius:50%;background:$($script:EMAIL_COLOR[$level]);margin-right:5px""></span>" }
function EmailStat($n, [string]$label, $level) {
    $color = '#888'; $nc = '#222'; if ($level) { $color = $script:EMAIL_COLOR[$level]; $nc = $color }
    "<td style=""border-top:3px solid $color;padding:8px 14px;text-align:center""><div style=""font-size:22px;font-weight:bold;color:$nc"">$(Esc (Str $n))</div><div style=""font-size:10px;color:#666;text-transform:uppercase;letter-spacing:.03em"">$(Esc $label)</div></td>"
}
function EmailHtml($s, $n, $notes, $c, $health) {
    $r = SprintSummary $s $n; $t = $r.totals; $u = $s.unit; if ($null -eq $u) { $u = 'SP' }
    $td = 'style="border:1px solid #bbb;padding:3px 8px"'; $tdn = 'style="border:1px solid #bbb;padding:3px 8px;text-align:right"'
    $sp = $r.sprint; if ($null -eq $sp) { $sp = '-' }
    $h = "<div style=""font-family:Segoe UI,Arial,sans-serif;font-size:14px"">`n"
    $h += "<p><b>Sprint $sp status as of $($s.today):</b> $(Trunc $t.done) of $(Trunc $t.committed) $u done ($(Trunc $t.pct)%), $(Trunc $t.open) open, $(Trunc $t.carryover) carried over.</p>`n"
    $bl = Blocked $s ''
    $risk = @(foreach ($tm in (Keys $r.teams)) { if ((LoadStatus $r.teams[$tm].load) -cne 'good') { $tm } })
    $lb = 'good'; if ($bl.Count) { $lb = 'critical' }; $lr = 'good'; if ($risk.Count) { $lr = 'warning' }
    $h += '<table style="border-collapse:collapse;margin-bottom:10px"><tr>' + (EmailStat "$($t.pct)%" 'Done' $null) + (EmailStat $t.open "Open $u" $null) + (EmailStat $bl.Count 'Blocked' $lb) + (EmailStat $risk.Count 'At-risk teams' $lr) + "</tr></table>`n"
    $h += "<table style=""border-collapse:collapse"">`n<tr><th $td>Team</th><th $tdn>Committed</th><th $tdn>Done</th><th $tdn>Open</th><th $tdn>Done %</th><th $tdn>Load</th></tr>`n"
    foreach ($team in @((SortedKeys $r.teams) + @('Total'))) {
        if ($team -ceq 'Total') { $x = $t; $level = $null } else { $x = $r.teams[$team]; $level = LoadStatus $x.load }
        if ($null -eq $x.load) { $lc = '' }
        elseif ($level -and $level -cne 'good') { $lc = "<span style=""background:$($script:EMAIL_COLOR[$level]);color:#fff;padding:1px 6px;border-radius:3px;font-weight:bold"">$($x.load)%</span>" }
        else { $lc = "$($x.load)%" }
        if ($team -ceq 'Total') { $nm = Esc $team } else { $nm = (EmailDot $level) + (Esc $team) }
        $h += "<tr><td $td>$nm</td><td $tdn>$(Trunc $x.committed)</td><td $tdn>$(Trunc $x.done)</td><td $tdn>$(Trunc $x.open)</td><td $tdn>$(Trunc $x.pct)%</td><td $tdn>$lc</td></tr>`n"
    }
    $h += "</table>`n"
    foreach ($team in (SortedKeys $r.teams)) {
        $open = @($r.teams[$team].open_items | Where-Object { $null -ne $_ }); if (-not $open.Count) { continue }
        $h += "<p><b>$(Esc $team) still open:</b> " + (@(foreach ($i in $open) { $ow = ')'; if ($i.owner) { $ow = ", $($i.owner))" }; Esc "$($i.id) $($i.title) ($(Num $i.points) $u$ow" }) -join '; ') + "</p>`n"
    }
    if ($bl.Count) {
        $h += "<p style=""background:#fdeeee;border-left:3px solid $($script:EMAIL_COLOR['critical']);padding:6px 10px;color:#b00""><b>Blocked:</b> " + (@(foreach ($i in $bl) {
                    $d = BlockedDays $s $i; $w = ''; if ($d -gt 5) { $w = ' (over 5 days)' } elseif ($d -gt 3) { $w = ' (escalate)' }
                    (Esc "$($i.id) ($($i.team)) $($i.blocked)") + " <b>$($d)d</b>$w" }) -join '; ') + "</p>`n"
    }
    if ($health -and @($health | Where-Object { $_.level -cne 'info' }).Count) { $h += HealthMailHtml $health }
    $nt = NotesText $notes
    if ($nt) { $h += '<pre style="font-family:Segoe UI,Arial,sans-serif;white-space:pre-wrap">' + (Esc $nt) + "</pre>`n" }
    MarkedMailHtml $c ($h + "</div>`n")
}
function BriefBullets($s, $r) {                        # -> @(bullets (at most 5), extra)
    $b = @()
    $crit = SortWith @(foreach ($t in (SortedKeys $r.teams)) { if ((LoadStatus $r.teams[$t].load) -ceq 'critical') { $t } }) { param($x, $y) $c = $r.teams[$y].load - $r.teams[$x].load; if ($c) { $c } else { Cmp $x $y } }
    foreach ($t in $crit) { $b += "$t at $($r.teams[$t].load)% load" }
    foreach ($i in (SortWith (Blocked $s '') { param($x, $y) (BlockedDays $s $y) - (BlockedDays $s $x) })) { $b += "$($i.id) ($($i.team)) blocked $(BlockedDays $s $i)d: $($i.blocked)" }
    $warn = SortWith @(foreach ($t in (SortedKeys $r.teams)) { if ((LoadStatus $r.teams[$t].load) -ceq 'warning') { $t } }) { param($x, $y) $c = $r.teams[$y].load - $r.teams[$x].load; if ($c) { $c } else { Cmp $x $y } }
    foreach ($t in $warn) { $b += "$t approaching capacity ($($r.teams[$t].load)%)" }
    $un = Unassigned $s ''; if ($un.Count) { $b += "$($un.Count) committed task(s) unassigned" }
    $extra = 0; if ($b.Count -gt 5) { $extra = $b.Count - 5; $b = @($b[0..4]) }
    @{ bullets = $b; extra = $extra }
}
function BriefSubject($s, $n) {
    $r = SprintSummary $s $n; $st = BriefStatus $s $n
    $sp = $r.sprint; if ($null -eq $sp) { $sp = '-' }
    $hl = ''; if ($st[1]) { $hl = ", $($st[1])" }
    "[$($st[0].ToUpper())] Sprint $sp, $($s.today): $(Trunc $r.totals.pct)% done$hl"
}
function BriefHtml($s, $n, $c) {
    $r = SprintSummary $s $n; $st = BriefStatus $s $n
    $lv = 'good'; if ($st[0] -ceq 'red') { $lv = 'critical' } elseif ($st[0] -ceq 'amber') { $lv = 'warning' }
    $sp = $r.sprint; if ($null -eq $sp) { $sp = '-' }
    $head = $st[1]; if (-not $head) { $head = 'On track, no blockers.' }
    $h = "<div style=""font-family:Segoe UI,Arial,sans-serif;font-size:16px;line-height:1.5;max-width:480px"">`n"
    $h += "<p style=""margin:0 0 10px""><span style=""display:inline-block;background:$($script:EMAIL_COLOR[$lv]);color:#fff;font-weight:bold;padding:3px 10px;border-radius:4px;font-size:15px"">$($st[0].ToUpper())</span></p>`n"
    $h += "<p style=""margin:0 0 12px""><b>Sprint $sp, $($s.today): $(Trunc $r.totals.pct)% done.</b><br>$(Esc $head)</p>`n"
    $bb = BriefBullets $s $r
    if ($bb.bullets.Count) {
        $h += "<ul style=""margin:0 0 8px;padding-left:22px"">`n" + (@(foreach ($x in $bb.bullets) { "<li style=""margin-bottom:6px"">$(Esc $x)</li>`n" }) -join '') + "</ul>`n"
        if ($bb.extra) { $h += "<p style=""color:#888;font-size:13px;margin:0"">+$($bb.extra) more &mdash; see the full status report</p>`n" }
    }
    MarkedMailHtml $c ($h + "</div>`n")
}

# ================================================================ draft, brief, commit, all: Teams-only versions of daily.pl's Outlook/git commands
function MarkingGate {                                 # daily.pl _marking_gate: print the problems; $false (refuse) on an error unless -Force
    $rcp = @(); if ($To) { $rcp = @($To, $Cc) }        # no Outlook here: recipients only when -To names them
    $p = MarkingCheck $script:C $rcp
    $out = (@(foreach ($x in $p) { "  marking: $x`n" }) -join '')
    $ok = $true
    if (@($p | Where-Object { $_ -cmatch '^error:' }).Count) {
        if ($Force) { $out += "  --force: continuing despite marking errors`n" }
        else { $out += "refusing: fix the marking errors above, or run again with --force`n"; $ok = $false }
    }
    @{ ok = $ok; text = $out }                         # the caller prints: output inside an if () would be swallowed
}
function MailNotes($s) {
    $notes = TodayNotes
    if (-not $notes) { $notes = @{ date = $script:TODAY; teams = @{}; notes = @(); risks = @(); extra = '' } }
    $notes.extra = FlagsText $s
    $notes
}
function WriteMail([string]$kind, [string]$subj, [string]$html, [string]$text) {   # reports/<today>-<kind>.html/.txt; -Clip: the text for a Teams post
    EnsureDir $script:C.reports
    $f = "$($script:C.reports)/$($script:TODAY)-$kind"
    WriteText "$f.html" $html; WriteText "$f.txt" $text
    Out-Text "subject: $subj`nwrote $f.html  (paste into Teams (or Outlook): open it in Edge, Ctrl+A, Ctrl+C)`nwrote $f.txt`n"
    if ($Clip) { Set-Clipboard -Value ($text -replace "`n", "`r`n"); Out-Err "copied the text of $f.txt: paste into the Teams post (Ctrl+V)" }
}
function Cmd-Draft {
    $s = Load-S
    $notes = MailNotes $s
    $g = MarkingGate; Out-Text $g.text; if (-not $g.ok) { $script:RC = 1; return }
    $subj = $Subject; if (-not $subj) { $subj = "Sprint $(Str $s.current) status $($script:TODAY)" }
    WriteMail 'status' (SubjectOf $script:C $subj) (EmailHtml $s $s.current $notes $script:C) (EmailText $s $s.current $notes $script:C)
}
function Cmd-Brief {
    $s = Load-S
    $g = MarkingGate; Out-Text $g.text; if (-not $g.ok) { $script:RC = 1; return }
    $subj = $Subject; if (-not $subj) { $subj = BriefSubject $s $s.current }
    WriteMail 'brief' (SubjectOf $script:C $subj) (BriefHtml $s $s.current $script:C) (BriefText $s $s.current $script:C)
}
function FindPgit {                                    # pgit.ps1 (git for PowerShell) beside agile.ps1, else in Documents\agile
    $c = @(); if ($PSCommandPath) { $c += (Join-Path (Split-Path -Parent $PSCommandPath) 'pgit.ps1') }
    $c += (Join-Path $HOME 'Documents\agile\pgit.ps1')
    foreach ($x in $c) { if (Test-Path -LiteralPath $x -PathType Leaf) { return $x } }
    $null
}
function Cmd-Commit {                                  # the project folder (where scrum.conf is) must hold its own .git
    $proj = (Get-Location).Path
    $pg = FindPgit
    if (-not $pg -or -not (Test-Path -LiteralPath (Join-Path $proj '.git') -PathType Container)) { Out-Err 'not a git repository (git init first)'; $script:RC = 1; return }
    $ceil = $env:GIT_CEILING_DIRECTORIES                # and pgit never climbs out of it into an enclosing repository
    $env:GIT_CEILING_DIRECTORIES = Split-Path -Parent $proj
    try {
        $o = & $pg add -A 2>&1
        if ($LASTEXITCODE) { Out-Text (($o | ForEach-Object { "$_" }) -join "`n"); $script:RC = 1; return }
        $null = & $pg commit -q -m "standup $($script:TODAY)" 2>&1
        if ($LASTEXITCODE) { Out-Text "nothing to commit`n" } else { Out-Text "committed`n" }
        $global:LASTEXITCODE = 0
    }
    finally { $env:GIT_CEILING_DIRECTORIES = $ceil }
}
function Cmd-All {
    Cmd-Compile
    if ($script:RC) { return }
    Cmd-Report
    if ($Draft) { Cmd-Draft }
    Cmd-Commit
}

# ================================================================ project: scrum.conf
$script:DEFAULT_CONF = [ordered]@{ journal = 'scrum.txt'; standups = 'standups'; reports = 'reports'; unit = 'SP'; to = ''; cc = ''; subject_prefix = ''
    banner = ''; marking_owner = ''; marking_category = ''; marking_handling = ''; marking_poc = ''; attendance = 'attendance.csv'; history_days = '5'; default_team = ''; facilitator = ''; readback_clean_days = '5'
}
function ReadConf([string]$path) {
    $c = @{}; foreach ($k in $script:DEFAULT_CONF.Keys) { $c[$k] = $script:DEFAULT_CONF[$k] }
    $t = ReadText $path
    if ($null -ne $t) { foreach ($l in ($t -csplit "`r?`n")) { if ($l -cmatch '^\s*(#|$)') { continue }; $l = $l -creplace '\s+#.*$', ''; if ($l -cmatch '^\s*([\w.]+)\s*=\s*(.*?)\s*$') { $c[$Matches[1].ToLower()] = $Matches[2] } } }
    $c
}
function FindConf {
    $dir = (Get-Location).Path
    while ($true) {
        if (Test-Path -LiteralPath (Join-Path $dir 'scrum.conf') -PathType Leaf) { return (Join-Path $dir 'scrum.conf') }
        $up = Split-Path -Parent $dir
        if (-not $up -or $up -eq $dir) { return $null }
        $dir = $up
    }
}
# daily.pl init's files, byte for byte (the em dash in scrum.conf's first line is put in at write time: this file stays ASCII)
$script:CONF_TEXT = @'
# scrum.conf @EMDASH@ all paths relative to this file
journal   = scrum.txt
standups  = standups
reports   = reports
unit      = SP

# e-mail defaults for daily.pl draft
to        =
cc        =
subject_prefix =                  # e.g. INTERNAL -- prepended to mail subjects when set

# stand-up answers and the AI service
history_days  = 5                 # previous days of answers used for "stuck" and "blocked N days" checks
default_team  =                   # team for standups/<date>-chat.txt without a team in the name
ai_backend    = paste             # paste | curl | mock
ai_url        =
ai_model      =
ai_key_env    =                   # name of the env var holding the API key

# the townhall (daily.pl invite creates it: every weekday, roster.txt as attendees)
townhall_subject  = Daily townhall
townhall_start    = 07:30
townhall_minutes  = 60
townhall_location = Microsoft Teams Meeting
facilitator       =                 # your Teams display name (; between several): your own chat lines are not linted as statuses

# calendar (Outlook/Teams via PowerShell COM). calendar = mock + calendar_fixture = file.json for offline use
standup_match     = stand-?up
team_from_subject = ^(\w+)\s+stand
attendance        = attendance.csv

# marking (optional): a banner on every report, mail and PDF page, and a block under it. Leave banner empty to disable.
banner            =                 # e.g. INTERNAL, COMPANY CONFIDENTIAL
marking_owner     =                 # who owns the marked material
marking_category  =
marking_handling  =                 # e.g. do not forward outside the program
marking_poc       =
mail_domains      =                 # optional, comma-separated: mail may only go to these domains (daily.pl check enforces it)
'@
$script:JOURNAL_TEXT = @'
; Scrum journal. Conventions: perldoc lib/Scrum.pm
; Points move Backlog:Master -> Backlog:<Team> -> Sprint:<N>:<Team>:Committed -> Done | Carryover | Removed
; Every posting that moves a task carries "; id: KEY". Stand-up files write most of this for you.

; ~ Sprint 1
;     Alpha    20 SP

; 2026-01-05 Intake ABC-1 First task
;     Backlog:Alpha    5 SP   ; id: ABC-1, prio: 1, epic: Setup, owner: Someone
;     Equity:Intake

; 2026-01-06 Sprint 1 planning
;     Backlog:Alpha             -5 SP   ; id: ABC-1
;     Sprint:1:Alpha:Committed   5 SP   ; id: ABC-1
'@

# ================================================================ commands
function Cmd-Init([string]$dir) {
    if (-not $dir) { $dir = '.' }
    EnsureDir $dir
    $confText = (($script:CONF_TEXT -replace "`r", '') -creplace '@EMDASH@', [string][char]0x2014) + "`n"
    $files = [ordered]@{ '.gitattributes' = "* text eol=lf`n"; '.gitignore' = "reports/`n"; 'scrum.conf' = $confText; 'scrum.txt' = ($script:JOURNAL_TEXT -replace "`r", '') + "`n" }
    foreach ($f in $files.Keys) {
        $p = Join-Path $dir $f
        if (Test-Path -LiteralPath $p) { Write-Output "kept    $f"; continue }
        WriteText $p $files[$f]; Write-Output "created $f"
    }
    foreach ($d in @('standups', 'reports')) { EnsureDir (Join-Path $dir $d) }
    $pg = FindPgit                                     # daily.pl runs git init; here pgit.ps1, when it is beside this file
    if ($pg -and -not (Test-Path -LiteralPath (Join-Path $dir '.git'))) {
        $null = & $pg init -q $dir 2>&1
        if (-not $LASTEXITCODE) { Write-Output 'git init' }
        $global:LASTEXITCODE = 0
    }
    Out-Text @"

Next:
  1. edit scrum.conf (facilitator = your Teams display name; banner and marking if the material is marked)
  2. the backlog: agile.ps1 new, then lines like  new ABC-2 5 Login page e:Auth o:"Ann Lee"  under '== Team', then agile.ps1 compile
  3. each morning: copy the stand-up chat in Teams (Ctrl+A, Ctrl+C), then  agile.ps1 paste  and  agile.ps1 lint -Reply -Clip
"@
}
function Load-Project {
    $script:CONFPATH = $Conf; if (-not $script:CONFPATH) { $script:CONFPATH = FindConf }
    if (-not $script:CONFPATH) { throw "no scrum.conf found here or above (run: agile.ps1 init)`n" }
    if (-not (Test-Path -LiteralPath $script:CONFPATH -PathType Leaf)) { throw "no such file: $($script:CONFPATH)`n" }
    $script:C = ReadConf $script:CONFPATH
    Push-Location; $script:PUSHED = $true
    Set-Location -LiteralPath (Split-Path -Parent (Resolve-Path -LiteralPath $script:CONFPATH).Path)
    if (-not $script:TODAY) { $script:TODAY = (Get-Date).ToString('yyyy-MM-dd') }
}
function Load-S([string]$until) { $s = LoadScrum $script:C.journal $script:TODAY $until; $s.unit = $script:C.unit; $s }
function MarkingCheck($c, $recipients) {     # -> problems: "error: ..." must stop a send, "warn: ..." is advisory (Scrum::marking_check)
    $p = @()
    $b = '' + $c['banner']
    if ($b -ne '') {
        if (-not ($c['marking_owner'] -cmatch '\S')) { $p += 'warn: marking_owner is empty -- say who owns the marked material' }
        if (-not ($c['marking_poc'] -cmatch '\S')) { $p += 'warn: marking_poc is empty -- say who to ask about it' }
        if (-not (('' + $c['subject_prefix']) -cmatch '\S')) { $p += 'warn: subject_prefix is empty while a banner is set -- mail subjects will not carry the marking' }
    }
    $dom = @(('' + $c['mail_domains']) -csplit '[,\s]+' | Where-Object { $_ -cmatch '\S' })
    if ($dom.Count) {
        foreach ($a in @(foreach ($r in $recipients) { if ($null -ne $r) { $r -csplit '[;,\s]+' } }) | Where-Object { $_ -cmatch '\S' }) {
            $ok = $false; foreach ($d in $dom) { if ($a -match ('[.@]' + [regex]::Escape($d) + '$')) { $ok = $true } }
            if (-not $ok) { $p += "error: recipient $a is outside mail_domains ($($dom -join ', '))" }
        }
    }
    , $p
}
function Cmd-Check {
    $s = Load-S
    Out-Text "ok: $($s.items.Count) tasks, teams $($s.teams -join '/'), sprints $($s.sprints -join '/')`n"
    $p = MarkingCheck $script:C @($script:C['to'], $script:C['cc'])
    if ($p.Count) { Out-Text (($p | ForEach-Object { "marking: $_`n" }) -join '') }
    elseif ($script:C['banner']) { $md = ''; if ($script:C['mail_domains']) { $md = "; mail only to $($script:C['mail_domains'])" }; Out-Text "marking: ok ($($script:C['banner'])$md)`n" }
    else { Out-Text "marking: off (no banner in scrum.conf)`n" }
    if (@($p | Where-Object { $_ -cmatch '^error:' }).Count) { $script:RC = 1 }
}
function Cmd-New($teams) {
    EnsureDir $script:C.standups
    $path = "$($script:C.standups)/$($script:TODAY).txt"
    if (Test-Path -LiteralPath $path) { Out-Text "exists`n$path`n"; return }
    $s = Load-S
    WriteText $path (Template $s $script:TODAY $teams)
    Out-Text "created`n$path`n"
}
function Cmd-Status {
    $s = Load-S
    $p = Pending $script:C.standups
    $cur = $s.current; if ($null -eq $cur) { $cur = '?' }
    $out = "journal: $($script:C.journal)  ($($s.items.Count) tasks, sprint $cur, teams $($s.teams -join '/'))`n"
    if ($p.Count) { $out += "pending stand-up files:`n" + (@(foreach ($x in $p) { "  $x`n" }) -join '') } else { $out += "no pending stand-up files`n" }
    $r = SprintSummary $s $null
    if ($null -ne $r.sprint) { $t = $r.totals; $out += "sprint $($r.sprint): $(Trunc $t.done)/$(Trunc $t.committed) $($script:C.unit) done ($($t.pct)%), $(Trunc $t.open) open, $((Blocked $s '').Count) blocked`n" }
    Out-Text $out
}
function Cmd-Compile {
    $p = Pending $script:C.standups
    if (-not $p.Count) { Out-Text "nothing to compile`n"; return }
    foreach ($f in $p) {
        $s = Load-S
        $su = ReadStandup $f
        try { if ($Dry) { $text = CompileStandup $s $su } else { $text = ApplyStandup $s $su $script:C.journal } }
        catch { Out-Err "${f}: NOT applied`n$($_.Exception.Message)"; $script:RC = 1; return }
        if ($Dry) { Out-Text "# would append for ${f}:`n$text"; continue }
        $n = [regex]::Matches($text, '(?m)^\d{4}-\d{2}-\d{2} ').Count
        Out-Text "applied $f ($n transactions)`n"
    }
}
function IsFacilitator([string]$who) {
    $f = @{}; foreach ($x in ($script:C.facilitator -csplit '\s*;\s*')) { if ($x) { $f[$x.ToLower()] = 1 } }
    $f.ContainsKey($who.ToLower())
}
function ChatFiles {
    , @(foreach ($f in (ListDir $script:C.standups)) {
            if ($f -cnotmatch ('^' + [regex]::Escape($script:TODAY) + '(?:-(.+?))?-chat\.txt$')) { continue }
            $team = $Matches[1]; if (-not $team -and $script:C.default_team) { $team = $script:C.default_team }
            , @("$($script:C.standups)/$f", $team) })
}
function AnswerFiles { , @(foreach ($f in (ListDir $script:C.standups)) { if ($f -cmatch ('^' + [regex]::Escape($script:TODAY) + '(?:-.+?)?-answers\.txt$')) { "$($script:C.standups)/$f" } }) }
function RosterOf($s, [string]$team) { SortedKeys (Members $s $team) }
function OwnExamples($s) {
    $m = Members $s ''; $ex = @{}
    foreach ($k in $m.Keys) { $ids = @(foreach ($i in (@($m[$k].wip) + @($m[$k].backlog))) { $i.id }); if ($ids.Count) { $ex[$k] = @($ids | Select-Object -First 2) } }
    $ex
}
function Cmd-Paste($a) {
    $team = $null; if ($a -and @($a).Count) { $team = @($a)[0] }
    $text = (Get-Clipboard -Raw)
    if ($null -eq $text -or $text -cnotmatch '\S') { Out-Err 'the clipboard is empty: in Teams click in the chat, Ctrl+A, Ctrl+C, then run this again'; $script:RC = 1; return }
    EnsureDir $script:C.standups
    $name = $script:TODAY; if ($team) { $name += "-$team" }
    $path = "$($script:C.standups)/$name-chat.txt"
    WriteText $path (($text -replace "`r`n", "`n") -replace "`r", "`n")
    $nm = (ParseChat $text).Count
    Out-Text "saved the chat to $path ($nm messages)`n"
    if (-not $nm) { Out-Err "no messages recognised: the copy has no '[9:05 AM] Name', 'Name 9:05 AM' or 'Name: text' lines. Open $path and check what Teams copied." }
    Cmd-Lint @($path)
}
function Cmd-Lint($files) {
    $files = @($files | Where-Object { $_ })
    if (-not $files.Count) { $files = @(foreach ($x in (ChatFiles)) { $x[0] }) }
    if (-not $files.Count) { Out-Text "no chat file for $($script:TODAY) (standups/$($script:TODAY)-chat.txt); or: agile.ps1 paste`n"; $script:RC = 1; return }
    $s = Load-S
    $known = @{}; foreach ($i in (AllItems $s)) { $known[$i.id] = 1 }
    $ids = Sorted (Keys $known)
    $ex1 = 'B-11'; $ex2 = 'B-12'; if ($ids.Count -gt 0) { $ex1 = $ids[0] }; if ($ids.Count -gt 1) { $ex2 = $ids[1] }
    $o = @{ known = $known; example = $ex1; example2 = $ex2; examples = (OwnExamples $s); proposals = (ReadProposals "$($script:C.standups)/$($script:TODAY)-proposals.txt") }
    $replies = @()
    foreach ($f in $files) {
        $text = ReadText $f
        if ($null -eq $text) { Out-Err "cannot open ${f}: No such file or directory"; $script:RC = 1; return }
        $rs = @(foreach ($r in (LintChat $text $o)) { if (-not (IsFacilitator $r.who)) { $r } })
        $mature = [int]$script:C.readback_clean_days
        $streak = @{}
        if ($Confirm -and $mature -gt 0) {
            foreach ($team in $s.teams) { foreach ($h in (AnswerHistory $script:C.standups $team $script:TODAY $mature)) { foreach ($a in $h.answers) {
                        if ($streak.ContainsKey($a.who) -and $streak[$a.who] -lt 0) { continue }
                        $clean = $a.complete -and -not $a.assumed -and ($a.ids.y.Count -or $a.ids.t.Count)
                        if ($clean) { $v = 0; if ($streak.ContainsKey($a.who)) { $v = $streak[$a.who] }; $streak[$a.who] = $v + 1 } else { $streak[$a.who] = -1 } } } }
        }
        $msg = { param($x) if ($x.reply) { return $x.reply }; $st = 0; if ($streak.ContainsKey($x.who)) { $st = $streak[$x.who] }; if ($Confirm -and $st -lt $mature) { return $x.confirm }; '' }
        if ($Private) {
            $title = 'Status corrections'; if ($Confirm) { $title = 'Status read-backs' }
            PrivatePage 'lint' $title @(foreach ($x in $rs) { $m = & $msg $x; if ($m) { @{ who = $x.who; text = $m } } })
        }
        elseif ($Reply) { foreach ($x in $rs) { $m = & $msg $x; if ($m) { Write-Output $m; $replies += $m } } }
        elseif ($Table) {
            Write-Output (@('state', 'who', 'Y', 'T', 'B', 'note') -join "`t")
            foreach ($x in $rs) {
                $st = 'ok'; if (-not $x.ok) { $st = 'ERROR' } elseif ($x.warnings.Count) { $st = 'warn' }
                if (-not $x.ok -and $x.guess) { $fs = @("$($x.guess.y) ?", "$($x.guess.t) ?", "$($x.guess.b) ?") } else { $fs = @((Str $x.y), (Str $x.t), (Str $x.b)) }
                $nt = $x.warnings -join '; '; if (-not $x.ok) { $nt = $x.errors -join '; ' }
                Write-Output ((@($st, $x.who) + $fs + @($nt)) -join "`t")
            }
        }
        else { $fn = $f; if ($f -eq '-') { $fn = 'chat' }; Out-Text (LintText $fn $rs) }
        if (@($rs | Where-Object { -not $_.ok }).Count) { $script:RC = 1 }
    }
    if ($Reply -and $Clip) {
        if ($replies.Count) { Set-Clipboard -Value ($replies -join "`r`n"); Out-Err "$($replies.Count) repl$(if ($replies.Count -eq 1) { 'y' } else { 'ies' }) copied: paste into the Teams chat (Ctrl+V)" }
        else { Out-Err 'nothing to reply: every status read cleanly' }
    }
}
function Cmd-Answers {
    $s = Load-S
    $cf = ChatFiles
    if (-not $cf.Count) { Out-Text "no chat files for $($script:TODAY) (standups/$($script:TODAY)-<Team>-chat.txt)`n"; $script:RC = 1; return }
    $path = "$($script:C.standups)/$($script:TODAY).txt"
    $props = ReadProposals "$($script:C.standups)/$($script:TODAY)-proposals.txt"
    foreach ($x in $cf) {
        $file = $x[0]; $team0 = $x[1]
        if (-not $team0 -and $s.teams.Count -eq 1) { $team0 = $s.teams[0] }
        $text = ReadText $file
        $all = @(foreach ($a in (ParseAnswers $text ([bool]$Guess) $props)) { if (-not (IsFacilitator $a.who)) { $a } })
        if (-not $all.Count) { Out-Text "${file}: no Y/T/B answers found`n"; $script:RC = 1; continue }
        $by = @{}
        if ($team0) { $by[$team0] = $all } else { foreach ($a in $all) { $t = TeamOf $s $a.who; if (-not $t) { $t = '?' }; if (-not $by.ContainsKey($t)) { $by[$t] = @() }; $by[$t] += $a } }
        if ($by.ContainsKey('?')) { Out-Text ('  unknown team for: ' + (@(foreach ($a in $by['?']) { $a.who }) -join ', ') + "  (not an owner in the journal; assign them a task or name the team in the file name)`n") }
        foreach ($team in (SortedKeys $by)) {
            if ($team -ceq '?') { continue }
            $ans = @($by[$team])
            $af = "$($script:C.standups)/$($script:TODAY)-$team-answers.txt"
            WriteText $af (AnswersText $script:TODAY $team $ans)
            $h = AnswerHistory $script:C.standups $team $script:TODAY ([int]$script:C.history_days)
            if ($Assume) {
                $seen = @{}; foreach ($a in $ans) { $seen[$a.who] = 1 }
                $silent = @(foreach ($w in (RosterOf $s $team)) { if (-not $seen.ContainsKey($w)) { $w } })
                $ps = @(foreach ($p in (Propose $s $team $h $silent)) { if (-not $seen.ContainsKey($p.who)) { $p } })
                $ans += @(foreach ($p in $ps) { AssumedRecord $p })
                WriteText $af (AnswersText $script:TODAY $team $ans)
                if ($ps.Count) { Out-Text ('  assumed for the silent: ' + (@(foreach ($p in $ps) { $p.who }) -join ', ') + "`n") }
            }
            $fl = Flags $s $team $ans $h (RosterOf $s $team)
            Out-Text ((AnswersReport $team $ans $fl) + "wrote $af`n")
            $nrows = LogAttendance $script:C.attendance $script:TODAY $team $ans
            $as = @($ans | Where-Object { $_.assumed }).Count
            if ($nrows) { $tail = ''; if ($as) { $tail = ", $as assumed" }; Out-Text "  attendance: $nrows rows ($($ans.Count - $as) answered$tail) -> $($script:C.attendance)`n" }
            $suggested = SuggestLines $s $team $ans $fl
            if (-not $suggested) { continue }
            if (-not (Test-Path -LiteralPath $path)) { Cmd-New @() }
            $body = ReadText $path
            if ($body.Contains($suggested)) { continue }
            AppendText $path "`n; ---- answers $($script:TODAY) $team`n== $team`n$suggested"
            Out-Text "  appended suggested lines to $path`n"
        }
    }
}
function LogAttendance([string]$path, [string]$date, [string]$team, $ans) {
    $have = @{}
    $t = ReadText $path
    if ($null -ne $t) { foreach ($l in ($t -csplit "`r?`n")) { $c = $l -csplit ','; if ($c.Count -ge 3) { $have["$($c[0]),$($c[1]),$($c[2])"] = 1 } } }
    $add = ''; if ($null -eq $t) { $add = "date,team,name,status`n" }
    $n = 0
    foreach ($a in $ans) {
        $nm = $a.who; if ($nm -cmatch "[`",`n]") { $nm = '"' + ($nm -creplace '"', '""') + '"' }
        $k = "$date,$team,$nm"; if ($have.ContainsKey($k)) { continue }; $have[$k] = 1
        $st = 'answered'; if ($a.assumed) { $st = 'assumed' }
        $add += "$k,$st`n"; $n++
    }
    if ($add) { AppendText $path $add }
    $n
}
function TodayNotes {
    $fs = @(foreach ($f in (ListDir $script:C.standups)) { if ($f -cmatch ('^' + [regex]::Escape($script:TODAY) + '.*\.txt$') -and $f -cnotmatch '-(?:chat|answers|proposals)\.txt$') { "$($script:C.standups)/$f" } })
    if (-not $fs.Count) { return $null }
    DayNotes @(foreach ($f in $fs) { ReadStandup $f })
}
function FlagsText($s) {
    $out = ''
    foreach ($f in (AnswerFiles)) {
        $rec = ReadAnswers $f
        $h = AnswerHistory $script:C.standups $rec.team $script:TODAY ([int]$script:C.history_days)
        $fl = Flags $s $rec.team $rec.answers $h (RosterOf $s $rec.team)
        if (@($fl).Count) { $p = ''; if ($rec.team) { $p = "$($rec.team) " }; $out += "${p}flags:`n" + (@(foreach ($l in (FoldFlags $fl)) { "  $l`n" }) -join '') }
    }
    $out
}
function Cmd-Csv($a) {
    $s = Load-S
    $what = $null; if ($a -and @($a).Count) { $what = @($a)[0] }
    if ($what) { try { Out-Text ((CsvTable $s $what) -replace "`r", '') } catch { Out-Err $_.Exception.Message; $script:RC = 2 }; return }
    EnsureDir $script:C.reports
    foreach ($w in $script:CSV_TABLES) { $f = "$($script:C.reports)/$w.csv"; WriteBom $f (CsvTable $s $w); Out-Text "wrote $f`n" }
    WriteWorkbook $s
}
function Cmd-Report {
    $s = Load-S
    EnsureDir $script:C.reports
    $notes = TodayNotes
    if (-not $notes) { $notes = @{ date = $script:TODAY; teams = @{}; notes = @(); risks = @(); extra = '' } }
    $ft = FlagsText $s
    $notes.extra = $ft
    $repDir = $script:C.reports; $repDay = $script:TODAY
    $out = [ordered]@{}
    $health = $null                                   # the Health block, as daily.pl report writes it, when agile-more.ps1 is beside this file
    if (Get-Command HealthSignals -CommandType Function -ErrorAction SilentlyContinue) { $health = HealthSignals $s (HealthOpts $s $null) }
    $out["$repDir/$repDay-status.txt"] = EmailText $s $s.current $notes $script:C $health
    $out["$repDir/$repDay-brief.txt"] = BriefText $s $s.current $script:C
    $out["$repDir/$repDay-status.html"] = EmailHtml $s $s.current $notes $script:C $health   # Perl's status mail body
    $out["$repDir/$repDay-brief.html"] = BriefHtml $s $s.current $script:C
    foreach ($f in $out.Keys) { WriteText $f $out[$f]; Out-Text "wrote $f`n" }
    foreach ($w in $script:CSV_TABLES) { $f = "$repDir/$w.csv"; WriteBom $f (CsvTable $s $w); Out-Text "wrote $f`n" }
    WriteWorkbook $s
}

# ================================================================ main
if ($Command -ceq "__lib") { return }      # dot-source with __lib: the functions without running a command (tests)
# report / all: the Health block needs agile-more.ps1's metrics (Metrics.pm). Dot-sourced here, at script scope (inside a
# function its functions would vanish on return); its param block rebinds $Command, $Rest, $Conf and $Today, so put them back.
if (($Command -ceq 'report' -or $Command -ceq 'all' -or $Command -ceq 'csv') -and -not (Get-Command HealthSignals -CommandType Function -ErrorAction SilentlyContinue)) {
    $morePath = $null
    foreach ($x in @($(if ($PSCommandPath) { Join-Path (Split-Path -Parent $PSCommandPath) 'agile-more.ps1' }), (Join-Path $HOME 'Documents\agile\agile-more.ps1'))) { if ($x -and (Test-Path -LiteralPath $x -PathType Leaf)) { $morePath = $x; break } }
    if ($morePath) {
        $keep = @{ c = $Command; r = $Rest; f = $Conf; t = $Today }
        . $morePath __lib
        $Command = $keep.c; $Rest = $keep.r; $Conf = $keep.f; $Today = $keep.t
    }
}
# The workbook's Funding sheet (report, all, csv) needs ledger.ps1's FundingSnapshot: dot-sourced here, at script scope, as
# above. Its functions are all Lg-prefixed and it has no param block, so nothing of this file is rebound.
if (($Command -ceq 'report' -or $Command -ceq 'all' -or $Command -ceq 'csv') -and -not (Get-Command FundingSnapshot -CommandType Function -ErrorAction SilentlyContinue)) {
    $ledgerPath = $null
    foreach ($x in @($(if ($PSCommandPath) { Join-Path (Split-Path -Parent $PSCommandPath) 'ledger.ps1' }), (Join-Path $HOME 'Documents\agile\ledger.ps1'))) { if ($x -and (Test-Path -LiteralPath $x -PathType Leaf)) { $ledgerPath = $x; break } }
    if ($ledgerPath) { . $ledgerPath __lib }
}
$script:TODAY = $Today
$script:PUSHED = $false
$script:STDIN = @($input)                              # tally - / tally: the chat piped in (Get-Content chat.txt | agile tally)
$args1 = @($Rest | Where-Object { $null -ne $_ })
try {
    if ($script:TODAY -and $script:TODAY -cnotmatch '^\d{4}-\d{2}-\d{2}$') { throw "bad -Today '$Today' (want YYYY-MM-DD)`n" }
    switch -CaseSensitive ($Command) {
        'init' { $initDir = $null; if ($args1.Count) { $initDir = $args1[0] }; Cmd-Init $initDir; break }
        'joined' {                                     # Teams attendance report downloads -> attendance.csv: townhall.ps1 does it
            $th = $null; if ($PSCommandPath) { $th = Join-Path (Split-Path -Parent $PSCommandPath) 'townhall.ps1' }
            if (-not $th -or -not (Test-Path -LiteralPath $th -PathType Leaf)) { Out-Err 'joined needs townhall.ps1 beside agile.ps1'; $script:RC = 2; break }
            $thArgs = @{}; if ($Conf) { $thArgs['Conf'] = $Conf }; if ($script:TODAY) { $thArgs['Today'] = $script:TODAY }
            & $th joined @args1 @thArgs; $script:RC = $LASTEXITCODE; break
        }
        { $_ -in 'help', '-h', '--help', '/?' } { Out-Text ($script:USAGE -replace "`r", ''); break }
        'tally' { Cmd-Tally $args1; break }
        default {
            Load-Project
            $a0 = $null; if ($args1.Count) { $a0 = $args1[0] }
            switch -CaseSensitive ($Command) {
                'new' { Cmd-New $args1; break }
                'status' { Cmd-Status; break }
                'compile' { Cmd-Compile; break }
                'paste' { Cmd-Paste $args1; break }
                'lint' { Cmd-Lint $args1; break }
                'answers' { Cmd-Answers; break }
                'propose' { Cmd-Propose $args1; break }
                'chat' { Cmd-Chat $args1; break }
                'draft' { Cmd-Draft; break }
                'brief' { Cmd-Brief; break }
                'commit' { Cmd-Commit; break }
                'all' { Cmd-All; break }
                'csv' { Cmd-Csv $args1; break }
                'report' { Cmd-Report; break }
                'sprint' { $s = Load-S; $n = $s.current; if ($a0 -cmatch '^\d+$') { $n = $a0 }; Out-Text (SprintText $s $n); break }
                'velocity' { Out-Text (VelocityText (Load-S)); break }
                'backlog' { Out-Text (BacklogText (Load-S) $a0); break }
                'members' { Out-Text (MembersText (Load-S) $a0); break }
                'epics' { Out-Text (EpicsText (Load-S)); break }
                'roadmap' { Out-Text (RoadmapText (Load-S)); break }
                'blocked' { Out-Text (BlockedText (Load-S)); break }
                'check' { Cmd-Check; break }
                default { Out-Err 'commands: init joined health review rollup quad roster new paste lint propose answers chat compile report draft brief commit all status sprint velocity backlog members epics roadmap blocked csv check'; $script:RC = 2 }
            }
        }
    }
}
catch { Out-Err ($_.Exception.Message); if (-not $script:RC) { $script:RC = 1 } }
finally { if ($script:PUSHED) { Pop-Location } }
if ($PSCommandPath) { exit $script:RC }                  # run as a file: the exit code; loaded as text (Invoke-Expression): never close the window
$global:LASTEXITCODE = $script:RC
