<#
townhall.ps1 -- the 15-minute meeting console (the kit's bin/townhall.tcl) for Windows PowerShell 5.1.

Every decision is made by agile.ps1 (paste, lint, answers, compile, report, propose); this file only shows the
results and runs the steps. Nothing here posts to Teams: replies go to the clipboard and you paste them.

  townhall.cmd [PROJECT-DIR]            the console: a status screen and one-letter commands (Constrained Language Mode safe)
  townhall.cmd [PROJECT-DIR] -Gui       the window (paste box left, results right, buttons bottom); needs FullLanguage
  townhall.cmd joined [FILE...]         Teams attendance report(s) -> attendance.csv (daily.pl joined)
  options: -Today YYYY-MM-DD  -Conf path\scrum.conf  -Project DIR
  tests:   -Script FILE (console commands from a file instead of the keyboard; nothing is opened)
           -ClipFile FILE (the clipboard is this file: paste reads it, R writes FILE.out)

Console keys (type the letter, Enter):
  P [Team]  paste the Teams chat from the clipboard -> standups\<today>[-Team]-chat.txt, lint it (agile paste)
  L         lint again                          R  copy the replies (corrections + read-backs) to the clipboard
  S [Name]  1:1 Teams link with Name's reply; no name: the private 1:1 page for everyone (lint -Private)
  J [FILE]  joined: the meeting's attendance report -> attendance.csv
  V propose  A answers (-Guess -Assume)  N answers (-Guess)  D dry compile  C compile  E report
  K cockpit  M cards  T today's stand-up file  G commit (pgit)  W redraw  ? help  Q quit
#>
param(
    [Parameter(Position = 0)][string]$Command = '',
    [Parameter(Position = 1, ValueFromRemainingArguments = $true)][string[]]$Rest,
    [string]$Conf, [Alias('Today')][string]$OnDate, [string]$Project, [switch]$Gui, [string]$Script, [string]$ClipFile
)
# dot-sourcing agile.ps1 rebinds its parameter names in this scope: keep ours first
$TH = @{ Command = $Command; Rest = @($Rest | Where-Object { $null -ne $_ }); Conf = $Conf; Today = $OnDate; Project = $Project
    Gui = [bool]$Gui; Script = $Script; ClipFile = $ClipFile }
$TH_AGILE = Join-Path $PSScriptRoot 'agile.ps1'
if (-not (Test-Path -LiteralPath $TH_AGILE -PathType Leaf)) { Write-Host "townhall: agile.ps1 not found beside townhall.ps1 ($TH_AGILE)" -ForegroundColor Yellow; exit 2 }
. $TH_AGILE __lib
$Conf = $TH.Conf; $Command = $TH.Command; $Rest = $TH.Rest
$ErrorActionPreference = 'Stop'

# ================================================================ bytes and text (Perl's :encoding(UTF-8), no BOM, LF)
function TH-Utf8Bytes([string]$s) {                  # UTF-8 encode by hand: [Text.Encoding] is not a core type in CLM
    $i = 0; $n = $s.Length
    $buf = @()
    while ($i -lt $n) {
        $cp = [int]$s[$i]
        if ($cp -ge 0xD800 -and $cp -le 0xDBFF -and $i + 1 -lt $n) {
            $d = [int]$s[$i + 1]
            if ($d -ge 0xDC00 -and $d -le 0xDFFF) { $cp = 0x10000 + (($cp - 0xD800) -shl 10) + ($d - 0xDC00); $i++ }
        }
        if ($cp -lt 0x80) { $buf += $cp }
        elseif ($cp -lt 0x800) { $buf += (0xC0 -bor ($cp -shr 6)); $buf += (0x80 -bor ($cp -band 0x3F)) }
        elseif ($cp -lt 0x10000) { $buf += (0xE0 -bor ($cp -shr 12)); $buf += (0x80 -bor (($cp -shr 6) -band 0x3F)); $buf += (0x80 -bor ($cp -band 0x3F)) }
        else { $buf += (0xF0 -bor ($cp -shr 18)); $buf += (0x80 -bor (($cp -shr 12) -band 0x3F)); $buf += (0x80 -bor (($cp -shr 6) -band 0x3F)); $buf += (0x80 -bor ($cp -band 0x3F)) }
        $i++
    }
    [byte[]]$buf
}
function TH-ReadBytes([string]$path) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $null }
    if ((Get-Item -LiteralPath $path).Length -eq 0) { return [byte[]]@() }
    [byte[]](Get-Content -LiteralPath $path -Encoding Byte -ReadCount 0)
}
function TH-WriteUtf8([string]$path, [string]$text) {    # exactly the bytes: no BOM, no newline added
    $b = TH-Utf8Bytes $text
    if ($b.Count -eq 0) { Set-Content -LiteralPath $path -Value '' -NoNewline -Encoding Ascii; return }
    Set-Content -LiteralPath $path -Value $b -Encoding Byte
}
function TH-AppendUtf8([string]$path, [string]$text) {   # Perl's open '>>:encoding(UTF-8)'
    $old = TH-ReadBytes $path
    $new = TH-Utf8Bytes $text
    if ($null -eq $old -or $old.Count -eq 0) { TH-WriteUtf8 $path $text; return }
    if ($new.Count -eq 0) { return }
    [byte[]]$all = @($old) + @($new)
    Set-Content -LiteralPath $path -Value $all -Encoding Byte
}
function TH-DecodeFile([string]$path) {               # Attendance::decode_bytes: UTF-16 (BOM or not) or UTF-8
    $head = @(Get-Content -LiteralPath $path -Encoding Byte -TotalCount 4)
    $enc = 'UTF8'
    if ($head.Count -ge 2 -and $head[0] -eq 0xFF -and $head[1] -eq 0xFE) { $enc = 'Unicode' }
    elseif ($head.Count -ge 2 -and $head[0] -eq 0xFE -and $head[1] -eq 0xFF) { $enc = 'BigEndianUnicode' }
    elseif ($head.Count -ge 4 -and $head[1] -eq 0 -and $head[3] -eq 0) { $enc = 'Unicode' }
    $t = Get-Content -LiteralPath $path -Raw -Encoding $enc
    if ($null -eq $t) { return '' }
    if ($t.Length -gt 0 -and $t[0] -eq [char]0xFEFF) { $t = $t.Substring(1) }
    $t
}

# ================================================================ Attendance.pm: the Teams attendance report
function TH-SplitQ([string]$line, [string]$sep) {     # split on $sep honouring double quotes
    $out = @(); $cur = ''; $q = $false
    foreach ($ch in $line.ToCharArray()) {
        $ch1 = [string]$ch
        if ($ch1 -ceq '"') { $q = -not $q }
        elseif ($ch1 -ceq $sep -and -not $q) { $out += $cur; $cur = '' }
        else { $cur += $ch1 }
    }
    $out += $cur
    , $out
}
function TH-Hm($t) {                                  # "9/23/26, 9:00:15 AM" | "2026-09-23T13:05:15" | "09:00" -> "09:00"
    if ($null -eq $t) { $t = '' }
    if ($t -cnotmatch '(?<![\d:])(\d{1,2}):(\d{2})(?::\d{2})?(?:\s*([AaPp])\.?[Mm]\.?)?') { return $null }
    $h = [int]$Matches[1]; $m = $Matches[2]; $ap = $Matches[3]
    if ($ap -and $ap.ToLower() -ceq 'p' -and $h -lt 12) { $h += 12 }
    if ($ap -and $ap.ToLower() -ceq 'a' -and $h -eq 12) { $h = 0 }
    ('{0:D2}' -f $h) + ':' + $m
}
function TH-Tenths([long]$secs) {                     # Perl: sprintf('%.1f', $secs / 60) + 0, then printed as a number
    # The exact binary value of secs/60 is x / 2^e (doubling is exact); round it to tenths half-even like C's printf.
    $d = [double]$secs / 60
    $x = $d; $e = 0
    while ($x -ne [double][long]$x) { $x = $x * 2; $e++ }
    $num = [decimal][long]$x * 10
    $den = [decimal]1; for ($k = 0; $k -lt $e; $k++) { $den = $den * 2 }
    $rem = $num % $den
    $q = ($num - $rem) / $den
    if ($rem * 2 -gt $den) { $q = $q + 1 }
    elseif ($rem * 2 -eq $den -and ($q % 2) -eq 1) { $q = $q + 1 }
    $q = [long]$q
    $whole = ($q - ($q % 10)) / 10; $frac = $q % 10
    if ($frac -eq 0) { return [string][long]$whole }
    "$([long]$whole).$frac"
}
function TH-Minutes($d) {                             # "1h 2m 3s" | "14m 55s" | "45s" | "0:14:55" -> minutes, 1 decimal
    if ($null -eq $d) { $d = '' }
    [long]$s = 0
    if ($d -cmatch '^\s*(\d+):(\d+):(\d+)\s*$') { $s = [long]$Matches[1] * 3600 + [long]$Matches[2] * 60 + [long]$Matches[3] }
    else {
        foreach ($m in [regex]::Matches($d, '(\d+)\s*h')) { $s += [long]$m.Groups[1].Value * 3600 }
        foreach ($m in [regex]::Matches($d, '(\d+)\s*m(?!s)')) { $s += [long]$m.Groups[1].Value * 60 }
        foreach ($m in [regex]::Matches($d, '(\d+)\s*s')) { $s += [long]$m.Groups[1].Value }
    }
    TH-Tenths $s
}
function TH-ParseReport([string]$text) {
    $text = $text -creplace "`r", ''
    $r = @{ title = $null; start = $null; end = $null; participants = @() }
    $tabs = ([regex]::Matches($text, "`t")).Count; $commas = ([regex]::Matches($text, ',')).Count
    $sep = ','; if ($tabs -gt $commas) { $sep = "`t" }
    $section = ''; $hdr = @()
    foreach ($line in ($text -csplit "`n")) {
        if ($line -cmatch '^\s*$') { continue }
        if ($line -match '^\s*\d+\.\s*(Summary|Participants|In-Meeting Activities|Activities)\b') { $section = $Matches[1].ToLower(); $hdr = @(); continue }
        $cells = @(foreach ($x in (TH-SplitQ $line $sep)) { $x = $x -creplace '^\s+|\s+$', ''; if ($x -cmatch '^"(.*)"$') { $x = $Matches[1] }; $x })
        if ($section -ceq 'summary' -or $section -ceq '') {
            if ($cells[0] -match '^meeting title$') { $r.title = $cells[1] }
            if ($cells[0] -match '^start time$') { $r.start = $cells[1] }
            if ($cells[0] -match '^end time$') { $r.end = $cells[1] }
            continue
        }
        if ($section -cne 'participants') { continue }
        if (-not $hdr.Count) {
            $isHdr = $false; foreach ($x in $cells) { if ($x -match '^name$') { $isHdr = $true } }
            if (-not $isHdr) { continue }
            $hdr = @(foreach ($x in $cells) { $x.ToLower() }); continue
        }
        $row = @{}; for ($k = 0; $k -lt $hdr.Count; $k++) { if ($k -lt $cells.Count) { $row[$hdr[$k]] = $cells[$k] } else { if (-not $row.ContainsKey($hdr[$k])) { $row[$hdr[$k]] = $null } } }
        $name = $row['name']; if ($null -eq $name -or $name -ceq '') { continue }
        $join = $null; $leave = $null; $dur = $null; $mail = $null
        foreach ($h in $hdr) { if ($null -eq $join -and $h -cmatch 'join' -and $null -ne $row[$h]) { $join = $row[$h] } }
        foreach ($h in $hdr) { if ($null -eq $leave -and $h -cmatch 'leave' -and $null -ne $row[$h]) { $leave = $row[$h] } }
        foreach ($h in $hdr) { if ($null -eq $dur -and $h -cmatch 'duration' -and $null -ne $row[$h]) { $dur = $row[$h] } }
        foreach ($h in $hdr) { if ($null -eq $mail -and $h -cmatch 'email|upn' -and $null -ne $row[$h] -and $row[$h] -cmatch '@') { $mail = $row[$h] } }
        $r.participants += @{ name = $name; email = $mail; join = (TH-Hm $join); leave = (TH-Hm $leave); minutes = (TH-Minutes $dur); role = $row['role'] }
    }
    $r
}
function TH-ReadReport([string]$file) {
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { throw "cannot open ${file}: No such file or directory`n" }
    TH-ParseReport (TH-DecodeFile $file)
}
function TH-ReportText($rep) {
    $out = ''
    if ($rep.title) { $out += "$($rep.title)  " }
    if ($rep.start) { $out += "$($rep.start) - $($rep.end)`n" } else { $out += "`n" }
    # stable sort by join time (Perl's sort is a stable merge sort)
    $ps = @($rep.participants); $sorted = @()
    foreach ($p in $ps) {
        $k = '' + $p.join; $i = $sorted.Count
        while ($i -gt 0 -and [string]::CompareOrdinal(('' + $sorted[$i - 1].join), $k) -gt 0) { $i-- }
        $before = @(); if ($i -gt 0) { $before = @($sorted[0..($i - 1)]) }
        $after = @(); if ($i -lt $sorted.Count) { $after = @($sorted[$i..($sorted.Count - 1)]) }
        $sorted = @($before + @(, $p) + $after)
    }
    foreach ($p in $sorted) {
        $out += '  ' + ('' + $p.name).PadRight(22) + ' ' + ('' + $p.join).PadLeft(5) + '  ' + ('' + $p.leave).PadLeft(5) + '  ' + ('' + $p.minutes).PadLeft(5) + " min`n"
    }
    $out
}
function TH-CsvField([string]$s) { if ($s -cmatch "[`",`n]") { '"' + ($s -creplace '"', '""') + '"' } else { $s } }
function TH-TeamOf($members, [string]$name) {         # name -> team via the journal's owners; $null if unknown
    foreach ($k in $members.Keys) { if ($k -ceq $name) { return $members[$k].team } }
    $first = @($name -csplit '\s+' | Where-Object { $_ -ne '' })[0]
    if ($null -eq $first) { return $null }
    $hit = @(foreach ($k in $members.Keys) { if ($k -ceq $first -or ($k.Length -ge $first.Length -and $k.Substring(0, $first.Length) -ceq $first)) { $k } })
    if ($hit.Count -eq 1) { return $members[$hit[0]].team }
    $null
}
function TH-LogReport([string]$path, [string]$date, $rep, [string]$team, $members, $minMinutes) {
    $have = @{}
    $old = $null
    if (Test-Path -LiteralPath $path -PathType Leaf) { $old = Get-Content -LiteralPath $path -Raw -Encoding UTF8 }
    if ($null -ne $old) { foreach ($l in ($old -csplit "`n")) { $cells = @($l -csplit ','); if ($cells.Count -ge 1) { $k = (@($cells[0], $cells[1], $cells[2]) | ForEach-Object { '' + $_ }) -join ','; $have["~$k"] = 1 } } }
    $add = ''
    if (-not (Test-Path -LiteralPath $path)) { $add += "date,team,name,status,join,leave,minutes`n" }
    $n = 0
    $min = 3.0; if ($null -ne $minMinutes -and "$minMinutes" -ne '') { $min = [double]$minMinutes }
    foreach ($p in $rep.participants) {
        $status = 'brief'; if ([double]$p.minutes -ge $min) { $status = 'present' }
        $t = $team
        if (-not $t) { $t = TH-TeamOf $members $p.name }
        if (-not $t) { $t = '?' }
        $k = "~$date,$t," + (TH-CsvField $p.name)
        if ($have.ContainsKey($k)) { continue }
        $have[$k] = 1
        $add += (@($date, $t, (TH-CsvField $p.name), $status, ('' + $p.join), ('' + $p.leave), $p.minutes) -join ',') + "`n"; $n++
    }
    TH-AppendUtf8 $path $add
    $n
}
function TH-Joined($files) {                          # daily.pl joined: attendance report downloads -> attendance.csv; rc in $script:TH_JRC
    $script:TH_JRC = 1
    $s = Load-S
    $members = Members $s ''
    $cfg = $script:C
    $files = @($files | Where-Object { $_ })
    if (-not $files.Count) {
        $files = @(foreach ($f in (ListDir $cfg.standups)) { if ($f -cmatch ('^' + [regex]::Escape($script:TODAY) + '(?:-.+?)?-attendance\.(?:csv|txt|tsv)$')) { "$($cfg.standups)/$f" } })
    }
    if (-not $files.Count) { Write-Output "no attendance reports for $($script:TODAY) (download from the meeting's Attendance tab to standups/$($script:TODAY)-<Team>-attendance.csv)"; $script:TH_JRC = 1; return }
    $att = $cfg.attendance; if (-not $att) { $att = 'attendance.csv' }
    foreach ($f in $files) {
        $team = $null
        if ($f -cmatch ([regex]::Escape($script:TODAY) + '-(.+?)-attendance\.')) { $team = $Matches[1] }
        $rep = TH-ReadReport $f
        Out-Text (TH-ReportText $rep)
        $n = TH-LogReport $att $script:TODAY $rep $team $members $cfg['min_minutes']
        $unk = @(foreach ($p in $rep.participants) { if ($null -eq (TH-TeamOf $members $p.name)) { $p.name } })
        $tail = ''; if (-not $team -and $unk.Count) { $tail = '   (team unknown for: ' + ($unk -join ', ') + ')' }
        Write-Output "  $n rows -> $att$tail"
    }
    $script:TH_JRC = 0
}

# ================================================================ the engine: agile.ps1 and friends as child scripts
$script:TH_PROJ = $null
$script:TH_CONFPATH = $null
function TH-Run([string]$file, [string[]]$pos, $named) {     # run a kit script, capture everything it prints -> @{ out; rc }
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { return @{ out = "not found: $file (copy it beside townhall.ps1)"; rc = 2 } }
    if ($null -eq $named) { $named = @{} }
    $have = @(foreach ($pm in (Get-Command -Name $file).Parameters.Values) { $pm.Name; foreach ($al in $pm.Aliases) { $al } })   # pass -Conf / -Today only where taken (name or alias)
    if ($have -contains 'Conf') { $named.Conf = $script:TH_CONFPATH }
    if ($have -contains 'Today') { $named.Today = $script:TODAY }
    $global:LASTEXITCODE = 0
    try { $o = @(& $file @pos @named *>&1 | ForEach-Object { "$_" }) }
    catch { return @{ out = "$(Split-Path -Leaf $file): $($_.Exception.Message.TrimEnd())"; rc = 1 } }
    @{ out = ($o -join "`n"); rc = $global:LASTEXITCODE }
}
function TH-Agile([string[]]$pos, $named) { TH-Run $TH_AGILE $pos $named }
function TH-RunProc([string]$file, [string[]]$argv) {   # a kit script in its own powershell.exe (cockpit.ps1 skips loading
    # agile.ps1 when its functions are already visible, so in this process it would miss agile.ps1's script variables)
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { return @{ out = "not found: $file (copy it beside townhall.ps1)"; rc = 2 } }
    $global:LASTEXITCODE = 0
    $o = @(& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $file @argv 2>&1 | ForEach-Object { "$_" })
    @{ out = ($o -join "`n"); rc = $global:LASTEXITCODE }
}
function TH-ClipGet {
    if ($TH.ClipFile) { $t = ReadText $TH.ClipFile; if ($null -eq $t) { return '' }; return $t }
    Get-Clipboard -Raw
}
function TH-ClipSet([string]$text) {
    if ($TH.ClipFile) { TH-WriteUtf8 "$($TH.ClipFile).out" $text; return }
    Set-Clipboard -Value $text
}
function TH-Open([string]$path) {                    # never by file association in tests (TOWNHALL_NOOPEN or -Script)
    if ($TH.Script -or $env:TOWNHALL_NOOPEN) { return "(would open $path)" }
    try { Start-Process -FilePath $path | Out-Null; "opened $path" } catch { "open it yourself: $path" }
}

# ---------------------------------------------------------------- state shown on the screen
$script:ST = @{ lint = @(); nlint = 0; nbad = 0; replies = ''; roster = @(); last = ''; lastrc = 0; status = '' }
function TH-Lint {                                    # lint -Table -> rows; lint -Reply -Confirm -> the replies; then the roster
    $chat = ChatFiles
    if (-not $chat.Count) { $script:ST.lint = @(); $script:ST.replies = ''; TH-Roster @(); $script:ST.status = "no chat file for $($script:TODAY) yet: P pastes it"; return }
    $r = TH-Agile @('lint') @{ Table = $true }
    $rows = @()
    foreach ($line in ($r.out -csplit "`n")) {
        $f = @($line -csplit "`t")
        if ($f.Count -lt 5 -or $f[0] -ceq 'state') { continue }
        while ($f.Count -lt 6) { $f += '' }
        $rows += , @($f[0], $f[1], $f[2], $f[3], $f[4], $f[5])
    }
    $script:ST.lint = $rows
    $script:ST.nlint = $rows.Count
    $script:ST.nbad = @($rows | Where-Object { $_[0] -ceq 'ERROR' }).Count
    $rep = TH-Agile @('lint') @{ Reply = $true; Confirm = $true }
    $script:ST.replies = $rep.out
    TH-Roster @(foreach ($x in $rows) { $x[1] })
}
function TH-People {                                  # roster.txt first (name | email | team | role | org); else the journal's owners
    $people = @()
    $rf = 'roster.txt'
    if (Test-Path -LiteralPath $rf -PathType Leaf) {
        foreach ($line in ((ReadText $rf) -csplit "`r?`n")) {
            if ($line -cmatch '^\s*(#|$)') { continue }
            $f = @(foreach ($x in ($line -csplit '\|')) { $x.Trim() })
            if ($f.Count -lt 3) { $f = @(foreach ($x in ($line -csplit ',')) { $x.Trim() }) }
            while ($f.Count -lt 5) { $f += '' }
            if ($f[0] -cne '') { $people += , @($f[0], $f[2], $f[3], $f[1]) }
        }
    }
    else {
        $m = Members (Load-S) ''
        foreach ($k in (SortedKeys $m)) { $t = $m[$k].team; if ($null -eq $t) { $t = '' }; $people += , @($k, $t, '', '') }
    }
    , $people
}
function TH-Roster($answered) {
    $people = TH-People
    # Tcl: lsort -index 1 [lsort -index 0 $people] -- by team, then name (both stable, ASCII order)
    $sorted = SortWith $people { param($a, $b) $cmp = [string]::CompareOrdinal($a[1], $b[1]); if ($cmp -ne 0) { $cmp } else { [string]::CompareOrdinal($a[0], $b[0]) } }
    $ans = @{}; foreach ($w in $answered) { $ans["~$w"] = 1 }
    $script:ST.roster = @(foreach ($p in $sorted) { , @($p[0], $p[1], $p[2], [bool]$ans.ContainsKey("~$($p[0])"), $p[3]) })
    $yes = @($script:ST.roster | Where-Object { $_[3] }).Count
    $script:ST.status = "$yes of $($script:ST.roster.Count) answered"
    $chat = ChatFiles; if ($chat.Count) { $script:ST.status += ' -- chat saved to ' + (Split-Path -Leaf $chat[0][0]) }
}
function TH-Cut([string]$s, [int]$n) { if ($null -eq $s) { return '' }; if ($s.Length -gt $n) { $s.Substring(0, $n) } else { $s } }
function TH-Screen {                                  # what townhall.tcl's right side shows
    if (-not $TH.Script) { try { Clear-Host } catch { } }
    $rule = '-' * 110
    Write-Host ("Townhall $($script:TODAY)  --  " + (Split-Path -Leaf $script:TH_PROJ)) -ForegroundColor Cyan
    Write-Host $rule -ForegroundColor DarkYellow
    Write-Host 'Lint' -ForegroundColor Cyan
    Write-Host ('{0,-5} {1,-18} {2,-26} {3,-26} {4,-16} {5}' -f 'STATE', 'WHO', 'YESTERDAY', 'TODAY', 'BLOCKERS', 'NOTE') -ForegroundColor DarkGray
    foreach ($r in $script:ST.lint) {
        $col = 'Gray'; if ($r[0] -ceq 'ERROR') { $col = 'Red' } elseif ($r[0] -ceq 'warn') { $col = 'Yellow' } elseif ($r[0] -ceq 'ok') { $col = 'Green' }
        Write-Host ('{0,-5} {1,-18} {2,-26} {3,-26} {4,-16} {5}' -f $r[0], (TH-Cut $r[1] 18), (TH-Cut $r[2] 26), (TH-Cut $r[3] 26), (TH-Cut $r[4] 16), $r[5]) -ForegroundColor $col
    }
    Write-Host "# $($script:ST.nlint) answered, $($script:ST.nbad) with errors" -ForegroundColor DarkGray
    Write-Host ''
    Write-Host 'Replies (R copies them; paste into the chat, or S Name for a 1:1)' -ForegroundColor Cyan
    if ($script:ST.replies) { foreach ($l in ($script:ST.replies -csplit "`n")) { Write-Host "  $l" } } else { Write-Host '  (none yet)' -ForegroundColor DarkGray }
    Write-Host ''
    Write-Host 'Roster' -ForegroundColor Cyan
    $last = $null
    foreach ($p in $script:ST.roster) {
        if ($p[1] -cne $last) { if ($null -ne $last) { Write-Host '' }; Write-Host ("  $($p[1]):  ") -NoNewline -ForegroundColor DarkGray; $last = $p[1] }
        $role = ''; if ($p[2]) { $role = " ($($p[2]))" }
        if ($p[3]) { Write-Host ("[x] $($p[0])$role   ") -NoNewline -ForegroundColor Green } else { Write-Host ("[ ] $($p[0])$role   ") -NoNewline -ForegroundColor Red }
    }
    Write-Host ''
    Write-Host ''
    Write-Host $script:ST.status -ForegroundColor DarkGray
    if ($script:ST.last) {
        Write-Host $rule -ForegroundColor DarkYellow
        foreach ($l in ($script:ST.last -csplit "`n")) { Write-Host $l }
        Write-Host "rc=$($script:ST.lastrc)" -ForegroundColor DarkGray
    }
    Write-Host $rule -ForegroundColor DarkYellow
    Write-Host 'P paste  L lint  R replies  S [Name] 1:1  J joined  V propose  A answers+assume  N answers  D dry  C compile  E report  K cockpit  M cards  T stand-up file  G commit  ? help  Q quit' -ForegroundColor DarkGray
}
function TH-Show($r) { $script:ST.last = $r.out; $script:ST.lastrc = $r.rc }
function TH-OneToOne([string]$name) {
    if (-not $name) {
        $r = TH-Agile @('lint') @{ Private = $true; Confirm = $true }
        $f = "$($script:C.reports)/$($script:TODAY)-lint.html"
        $r.out += "`n" + (TH-Open (Join-Path $script:TH_PROJ $f))
        return $r
    }
    $em = RosterEmails 'roster.txt'
    $mail = $em[(CK $name)]
    $first = @($name -csplit '\s+')[0]               # replies greet by first name ("Hey Bob! ...") or name the person
    $mine = @(foreach ($l in ($script:ST.replies -csplit "`n")) { if ($l -cmatch ('^\s*(Hey|Hi)\s+' + [regex]::Escape($first) + '\b') -or $l.Contains($name)) { $l.Trim() } }) -join "`n"
    if (-not $mine) { return @{ out = "no reply for $name in the current lint (L lints again)"; rc = 1 } }
    if (-not $mail) { return @{ out = "no e-mail for $name in roster.txt: add it (Name | email | Team | Role | Org), or paste this yourself:`n$mine"; rc = 1 } }
    $link = TeamsChatLink $mail $mine
    @{ out = "1:1 with ${name}:`n$link`n" + (TH-Open $link); rc = 0 }
}
function TH-Commit {                                   # daily.pl commit, through pgit when it is here
    $pg = Join-Path $PSScriptRoot 'pgit.ps1'
    if (-not (Test-Path -LiteralPath $pg -PathType Leaf)) { return @{ out = 'commit: pgit.ps1 is not beside townhall.ps1 (no git on this PC); the files are saved, just not versioned'; rc = 1 } }
    $global:LASTEXITCODE = 0
    $o1 = @(& $pg add . *>&1 | ForEach-Object { "$_" })
    $o2 = @(& $pg commit -m "standup $($script:TODAY)" *>&1 | ForEach-Object { "$_" })
    @{ out = (@($o1) + @($o2)) -join "`n"; rc = $global:LASTEXITCODE }
}
function TH-StandupFile {
    $f = "$($script:C.standups)/$($script:TODAY).txt"
    $pvi = Join-Path $PSScriptRoot 'pvi.ps1'
    if ($TH.Script) { return @{ out = "(would edit $f)"; rc = 0 } }
    if (Test-Path -LiteralPath $pvi -PathType Leaf) { & $pvi $f; return @{ out = "edited $f"; rc = 0 } }
    Start-Process notepad.exe -ArgumentList $f -Wait
    @{ out = "edited $f"; rc = 0 }
}
function TH-Do([string]$line) {                       # one console command -> $false to quit
    $line = ('' + $line).Trim()
    if ($line -ceq '') { return $true }
    $k = $line.Substring(0, 1).ToUpper(); $arg = $line.Substring(1).Trim()
    switch -CaseSensitive ($k) {
        'Q' { return $false }
        'P' {
            $pos = @('paste'); if ($arg) { $pos += $arg }
            if ($TH.ClipFile) { $r = TH-WithClip { TH-Agile $pos @{} } } else { $r = TH-Agile $pos @{} }
            TH-Show $r; TH-Lint; break
        }
        'L' { TH-Lint; $script:ST.last = ''; break }
        'R' { TH-ClipSet $script:ST.replies; $script:ST.last = "replies copied ($(@($script:ST.replies -csplit "`n").Count) lines): Ctrl+V in the meeting chat"; $script:ST.lastrc = 0; break }
        'S' { TH-Show (TH-OneToOne $arg); break }
        'J' {
            $o = @(); try { $o = @(TH-Joined @($arg) *>&1 | ForEach-Object { "$_" }) } catch { $o += $_.Exception.Message.TrimEnd(); $script:TH_JRC = 1 }
            TH-Show @{ out = ($o -join "`n"); rc = $script:TH_JRC }; break
        }
        'V' { TH-Show (TH-Agile @('propose') @{}); break }
        'A' { TH-Show (TH-Agile @('answers') @{ Guess = $true; Assume = $true }); break }
        'N' { TH-Show (TH-Agile @('answers') @{ Guess = $true }); break }
        'D' { TH-Show (TH-Agile @('compile') @{ Dry = $true }); break }
        'C' { TH-Show (TH-Agile @('compile') @{}); break }
        'E' { TH-Show (TH-Agile @('report') @{}); break }
        'K' {
            $r = TH-RunProc (Join-Path $PSScriptRoot 'cockpit.ps1') @($script:TH_PROJ, '-Today', $script:TODAY)
            if ($r.rc -eq 0) {
                $html = @(foreach ($l in ($r.out -csplit "`n")) { if ($l -cmatch '^wrote (.+\.html)') { $Matches[1].Trim() } })[0]
                if (-not $html) { $html = Join-Path $script:TH_PROJ "$($script:C.reports)/cockpit.html" }
                $r.out += "`n" + (TH-Open $html)
            }
            TH-Show $r; break
        }
        'M' {
            $r = TH-Run (Join-Path $PSScriptRoot 'cards.ps1') @() @{}
            if ($r.rc -eq 0) { $r.out += "`n" + (TH-Open (Join-Path $script:TH_PROJ "$($script:C.reports)/$($script:TODAY)-cards.html")) }
            TH-Show $r; break
        }
        'T' { TH-Show (TH-StandupFile); break }
        'G' { TH-Show (TH-Commit); break }
        'W' { break }
        '?' { $script:ST.last = (($script:TH_HELP -replace "`r", '').TrimEnd()); $script:ST.lastrc = 0; break }
        default { $script:ST.last = "unknown command '$line' (? for help)"; $script:ST.lastrc = 2 }
    }
    $true
}
function TH-WithClip([scriptblock]$b) {               # tests: the clipboard is a file; agile.ps1 paste then reads it
    $global:TH_CLIPTEXT = TH-ClipGet
    function Get-Clipboard { param([switch]$Raw) $global:TH_CLIPTEXT }
    & $b
}
$script:TH_HELP = @'
P [Team]  paste the meeting chat (Ctrl+A, Ctrl+C in Teams first) -> standups\<today>[-Team]-chat.txt, then lint
L         lint again (after people correct their statuses: copy the chat again and P)
R         copy the replies to the clipboard; Ctrl+V them into the meeting chat
S [Name]  1:1 Teams chat link with Name's reply filled in; S alone: the private page for everyone
J [FILE]  after the call: the meeting's attendance report (Teams > Attendance > Download) -> attendance.csv
V         propose: today's statuses drafted from yesterday's (before the meeting)
A / N     answers with / without -Assume (record yesterday's plan for the silent)
D / C     compile -Dry / compile: apply today's stand-up file to the journal
E         report (status page, brief, CSVs, the Excel workbook)
K / M     cockpit page / the members' cards (both open in Edge)
T         edit today's stand-up file    G  commit (pgit)    W  redraw    Q  quit
'@

function TH-Console {
    TH-Lint
    $lines = $null; $at = 0
    if ($TH.Script) { $t = ReadText $TH.Script; if ($null -eq $t) { throw "cannot open $($TH.Script): No such file or directory`n" }; $lines = @($t -csplit "`r?`n") }
    while ($true) {
        TH-Screen
        if ($null -ne $lines) {
            if ($at -ge $lines.Count) { break }
            $cmd = $lines[$at]; $at++
            Write-Host "townhall> $cmd" -ForegroundColor Cyan
        }
        else { $cmd = Read-Host 'townhall' }
        if (-not (TH-Do $cmd)) { break }
    }
}

# ================================================================ the window (FullLanguage only)
function TH-Gui {
    if ($ExecutionContext.SessionState.LanguageMode -ne 'FullLanguage') {
        Write-Host "townhall: the window needs FullLanguage; this PowerShell runs in $($ExecutionContext.SessionState.LanguageMode) mode (AppLocker/WDAC). Use the console: townhall.ps1 without -Gui." -ForegroundColor Yellow
        return 2
    }
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    $mono = New-Object System.Drawing.Font('Consolas', 10)
    $ui = New-Object System.Drawing.Font('Segoe UI', 10)
    $head = New-Object System.Drawing.Font('Segoe UI', 11, [System.Drawing.FontStyle]::Bold)
    $navy = [System.Drawing.Color]::FromArgb(0x27, 0x23, 0x5d)
    $f = New-Object System.Windows.Forms.Form
    $f.Text = "Townhall $($script:TODAY) -- " + (Split-Path -Leaf $script:TH_PROJ)
    $f.Size = New-Object System.Drawing.Size(1500, 860); $f.Font = $ui
    $top = New-Object System.Windows.Forms.Label
    $top.Text = "Townhall $($script:TODAY)  --  $(Split-Path -Leaf $script:TH_PROJ)      Ctrl-A, Ctrl-C in the meeting chat, then Paste. Lint runs on every paste."
    $top.Dock = 'Top'; $top.Height = 30; $top.Font = $head; $top.ForeColor = $navy
    $rule = New-Object System.Windows.Forms.Panel; $rule.Dock = 'Top'; $rule.Height = 3; $rule.BackColor = [System.Drawing.Color]::FromArgb(0xe6, 0xaf, 0x22)
    $split = New-Object System.Windows.Forms.SplitContainer; $split.Dock = 'Fill'; $split.SplitterDistance = 700
    # left: the paste box
    $paste = New-Object System.Windows.Forms.TextBox; $paste.Multiline = $true; $paste.ScrollBars = 'Both'; $paste.Font = $mono; $paste.Dock = 'Fill'; $paste.WordWrap = $true
    $lb = New-Object System.Windows.Forms.FlowLayoutPanel; $lb.Dock = 'Bottom'; $lb.Height = 38
    $lh = New-Object System.Windows.Forms.Label; $lh.Text = 'Meeting chat (pasted)'; $lh.Dock = 'Top'; $lh.Font = $head; $lh.ForeColor = $navy; $lh.Height = 26
    $split.Panel1.Controls.Add($paste); $split.Panel1.Controls.Add($lb); $split.Panel1.Controls.Add($lh)
    # right: lint, replies, roster
    $rt = New-Object System.Windows.Forms.TableLayoutPanel; $rt.Dock = 'Fill'; $rt.ColumnCount = 1; $rt.RowCount = 7
    foreach ($h in @(@('Absolute', 28), @('Percent', 50), @('Absolute', 28), @('Percent', 25), @('Absolute', 36), @('Absolute', 28), @('Percent', 25))) {
        [void]$rt.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]$h[0], $h[1])))
    }
    $mk = { param($text) $l = New-Object System.Windows.Forms.Label; $l.Text = $text; $l.Font = $head; $l.ForeColor = $navy; $l.Dock = 'Fill'; $l }
    $lint = New-Object System.Windows.Forms.RichTextBox; $lint.Font = $mono; $lint.ReadOnly = $true; $lint.WordWrap = $false; $lint.Dock = 'Fill'
    $rep = New-Object System.Windows.Forms.TextBox; $rep.Multiline = $true; $rep.ReadOnly = $true; $rep.ScrollBars = 'Vertical'; $rep.Dock = 'Fill'
    $ros = New-Object System.Windows.Forms.RichTextBox; $ros.ReadOnly = $true; $ros.Dock = 'Fill'
    $rb = New-Object System.Windows.Forms.FlowLayoutPanel; $rb.Dock = 'Fill'
    $rt.Controls.Add((& $mk 'Lint'), 0, 0); $rt.Controls.Add($lint, 0, 1)
    $rt.Controls.Add((& $mk 'Replies: corrections, and a read-back of each clean status for a thumbs-up'), 0, 2); $rt.Controls.Add($rep, 0, 3); $rt.Controls.Add($rb, 0, 4)
    $rt.Controls.Add((& $mk 'Roster'), 0, 5); $rt.Controls.Add($ros, 0, 6)
    $split.Panel2.Controls.Add($rt)
    $bot = New-Object System.Windows.Forms.FlowLayoutPanel; $bot.Dock = 'Bottom'; $bot.Height = 40
    $stat = New-Object System.Windows.Forms.Label; $stat.AutoSize = $true; $stat.ForeColor = [System.Drawing.Color]::Gray; $stat.Padding = New-Object System.Windows.Forms.Padding(12, 8, 0, 0)
    $outForm = $null
    $show = {
        param($r)
        $script:ST.last = $r.out; $script:ST.lastrc = $r.rc
        $of = New-Object System.Windows.Forms.Form; $of.Text = 'agile.ps1 output'; $of.Size = New-Object System.Drawing.Size(900, 600)
        $ot = New-Object System.Windows.Forms.TextBox; $ot.Multiline = $true; $ot.ScrollBars = 'Both'; $ot.WordWrap = $false; $ot.Font = $mono; $ot.Dock = 'Fill'; $ot.ReadOnly = $true
        $ot.Text = ($r.out -replace "`r?`n", "`r`n"); $of.Controls.Add($ot); $of.Show()
        $stat.Text = "rc=$($r.rc)"
    }
    $refresh = {
        $lint.Clear()
        $lint.SelectionColor = [System.Drawing.Color]::Gray
        $lint.AppendText(('{0,-5} {1,-18} {2,-26} {3,-26} {4,-16} {5}' -f 'STATE', 'WHO', 'YESTERDAY', 'TODAY', 'BLOCKERS', 'NOTE') + "`n")
        foreach ($r in $script:ST.lint) {
            $col = [System.Drawing.Color]::Black
            if ($r[0] -ceq 'ERROR') { $col = [System.Drawing.Color]::FromArgb(0xd0, 0x3b, 0x3b) } elseif ($r[0] -ceq 'warn') { $col = [System.Drawing.Color]::FromArgb(0xb8, 0x86, 0x0b) } elseif ($r[0] -ceq 'ok') { $col = [System.Drawing.Color]::FromArgb(0x0c, 0xa3, 0x0c) }
            $lint.SelectionColor = $col
            $lint.AppendText(('{0,-5} {1,-18} {2,-26} {3,-26} {4,-16} {5}' -f $r[0], (TH-Cut $r[1] 18), (TH-Cut $r[2] 26), (TH-Cut $r[3] 26), (TH-Cut $r[4] 16), $r[5]) + "`n")
        }
        $lint.SelectionColor = [System.Drawing.Color]::Gray
        $lint.AppendText("`n# $($script:ST.nlint) answered, $($script:ST.nbad) with errors`n")
        $rep.Text = ($script:ST.replies -replace "`r?`n", "`r`n")
        $ros.Clear(); $last = $null
        foreach ($p in $script:ST.roster) {
            if ($p[1] -cne $last) { $ros.SelectionColor = [System.Drawing.Color]::Gray; $ros.AppendText("`n$($p[1]):  "); $last = $p[1] }
            $role = ''; if ($p[2]) { $role = " ($($p[2]))" }
            if ($p[3]) { $ros.SelectionColor = [System.Drawing.Color]::FromArgb(0x0c, 0xa3, 0x0c); $ros.AppendText("[x] $($p[0])$role   ") }
            else { $ros.SelectionColor = [System.Drawing.Color]::FromArgb(0xd0, 0x3b, 0x3b); $ros.AppendText("[ ] $($p[0])$role   ") }
        }
        $stat.Text = $script:ST.status
    }
    $lintNow = {
        $chat = "$($script:C.standups)/$($script:TODAY)-chat.txt"
        EnsureDir $script:C.standups
        TH-WriteUtf8 $chat (($paste.Text -replace "`r`n", "`n") + "`n")
        TH-Lint; & $refresh
    }
    $btn = { param($panel, $text, $action) $b = New-Object System.Windows.Forms.Button; $b.Text = $text; $b.AutoSize = $true; $b.Add_Click($action); $panel.Controls.Add($b) }
    & $btn $lb 'Paste from clipboard' { $clip = Get-Clipboard -Raw; if ($clip) { $paste.AppendText(($clip -replace "`r?`n", "`r`n") + "`r`n"); & $lintNow } }
    & $btn $lb 'Lint now' { & $lintNow }
    & $btn $lb 'Clear' { $paste.Clear() }
    & $btn $rb 'Copy replies to clipboard' { if ($script:ST.replies) { Set-Clipboard -Value $script:ST.replies }; $stat.Text = 'replies copied' }
    & $btn $rb 'Private 1:1 page' { & $show (TH-OneToOne '') }
    & $btn $bot 'Propose (before)' { & $show (TH-Agile @('propose') @{}) }
    & $btn $bot 'Answers' { & $show (TH-Agile @('answers') @{ Guess = $true }) }
    & $btn $bot 'Answers -Assume' { & $show (TH-Agile @('answers') @{ Guess = $true; Assume = $true }) }
    & $btn $bot 'Joined' { $o = @(TH-Joined @() *>&1 | ForEach-Object { "$_" }); & $show @{ out = ($o -join "`n"); rc = $script:TH_JRC } }
    & $btn $bot 'Dry compile' { & $show (TH-Agile @('compile') @{ Dry = $true }) }
    & $btn $bot 'Compile' { & $show (TH-Agile @('compile') @{}) }
    & $btn $bot 'Report' { & $show (TH-Agile @('report') @{}) }
    & $btn $bot 'Cockpit' { [void](TH-Do 'K'); & $show @{ out = $script:ST.last; rc = $script:ST.lastrc } }
    & $btn $bot 'Cards' { [void](TH-Do 'M'); & $show @{ out = $script:ST.last; rc = $script:ST.lastrc } }
    & $btn $bot 'Commit' { & $show (TH-Commit) }
    $bot.Controls.Add($stat)
    $f.Controls.Add($split); $f.Controls.Add($bot); $f.Controls.Add($rule); $f.Controls.Add($top)
    $chat = "$($script:C.standups)/$($script:TODAY)-chat.txt"
    if (Test-Path -LiteralPath $chat) { $paste.Text = ((ReadText $chat) -replace "`r?`n", "`r`n") }
    TH-Lint; & $refresh
    $f.Add_Shown({ $split.SplitterDistance = [int]($split.Width * 0.45); $paste.SelectionStart = $paste.TextLength; $paste.SelectionLength = 0 })
    if ($env:TOWNHALL_SCREENSHOT) {                    # tests: show, capture the screen under the window (rich text boxes do not draw to bitmaps), close
        $f.TopMost = $true
        $f.Add_Shown({
                $f.Activate(); $f.Refresh(); [System.Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 1200; [System.Windows.Forms.Application]::DoEvents()
                $b = $f.Bounds
                $bmp = New-Object System.Drawing.Bitmap($b.Width, $b.Height)
                $g = [System.Drawing.Graphics]::FromImage($bmp); $g.CopyFromScreen($b.Location, [System.Drawing.Point]::Empty, $b.Size); $g.Dispose()
                $bmp.Save($env:TOWNHALL_SCREENSHOT, [System.Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose(); $f.Close()
            })
    }
    [void]$f.ShowDialog()
    0
}

# ================================================================ main
$script:RC = 0
try {
    if ($Command -in @('help', '-h', '--help', '/?')) { Write-Output (Get-Content -LiteralPath $PSCommandPath -TotalCount 26 | Select-Object -Skip 1 | Out-String).TrimEnd(); exit 0 }
    $proj = $TH.Project
    if (-not $proj -and $Command -and $Command -cne 'joined' -and $Command -cne 'console' -and (Test-Path -LiteralPath $Command -PathType Container)) { $proj = $Command; $Command = 'console' }
    if (-not $Command) { $Command = 'console' }
    if ($proj) {
        if (-not (Test-Path -LiteralPath (Join-Path $proj 'scrum.conf') -PathType Leaf)) { throw "No scrum.conf in $proj.`nStart with:  townhall.ps1 PROJECT-DIR`n" }
        $Conf = (Resolve-Path -LiteralPath (Join-Path $proj 'scrum.conf')).Path
    }
    if ($TH.Today -and $TH.Today -cnotmatch '^\d{4}-\d{2}-\d{2}$') { throw "bad -Today '$($TH.Today)' (want YYYY-MM-DD)`n" }
    $script:TODAY = $TH.Today
    Load-Project
    $script:TH_CONFPATH = (Resolve-Path -LiteralPath $script:CONFPATH).Path
    $script:TH_PROJ = (Get-Location).Path
    switch -CaseSensitive ($Command) {
        'joined' { TH-Joined $Rest; $script:RC = $script:TH_JRC; break }
        'console' {
            if ($TH.Gui) { $script:RC = TH-Gui } else { EnsureDir $script:C.standups; TH-Console }
            break
        }
        default { Write-Host "townhall: commands: console (default) | joined [FILE...] | help" -ForegroundColor Yellow; $script:RC = 2 }
    }
}
catch {                                                 # Perl's die: exit with errno (2 = no such file), else 255
    $msg = $_.Exception.Message.TrimEnd(); Write-Host $msg -ForegroundColor Yellow
    if ($env:TOWNHALL_DEBUG) { Write-Host $_.ScriptStackTrace }
    if (-not $script:RC) { if ($msg -cmatch 'No such file or directory') { $script:RC = 2 } elseif ($msg -cmatch '^(No scrum.conf|no scrum.conf|no such file:|bad -Today)') { $script:RC = 1 } else { $script:RC = 255 } }
}
finally { if ($script:PUSHED) { Pop-Location } }
exit $script:RC
