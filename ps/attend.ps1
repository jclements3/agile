<#
attend.ps1 -- meeting attendance and metrics posting for the agile kit, in Windows PowerShell 5.1.

The port of `daily.pl attend` and `daily.pl post` (lib/Calendar.pm, the Roster lookup), Constrained Language Mode
safe: no Outlook automation (COM is refused in CLM). Same project folder and files as agile.ps1 (scrum.conf,
roster.txt, standups\<today>.txt, attendance.csv).

  attend.ps1 [attend] [-Today YYYY-MM-DD] [-Conf path\scrum.conf]
        scrum.conf calendar = mock, calendar_fixture = FILE: today's stand-up meetings from the fixture (JSON, the
        shape `cal.pl dump` writes), exactly as daily.pl attend does with the mock calendar.
  attend.ps1 [attend] -Paste [-Team T] [-Subject S] [-At HH:MM]
  attend.ps1 [attend] -File FILE [-Team T] [-Subject S] [-At HH:MM]
        Outlook's meeting Tracking list instead of a calendar: open the stand-up meeting in Outlook (or the
        Scheduling Assistant), Tracking tab, "Copy Status to Clipboard", then -Paste (or save it and use -File).
  attend.ps1 post [-Team T] [-Clip]
        Today's metrics text for each stand-up meeting. With the mock calendar: posted into the fixture's meetings,
        output as daily.pl post. Without one: reports\<today>-post[-Team].txt per team, printed; -Clip puts it on
        the clipboard to paste into the meeting chat or the team's channel. --send (an Outlook update to the
        attendees) is not ported.

Both sources end in the same code path: one line per response ("accepted:", "tentative:", "declined:",
"no response:"), commented into today's stand-up file with a suggested "; absent NAME" line for each decline
(uncomment it to confirm), and date,team,name,status rows in attendance.csv (one per person per day).

The Tracking text (tab-separated, the first line a header):
    Name<TAB>Attendance<TAB>Response[<TAB>Response Time ...]
    JC<TAB>Meeting Organizer<TAB>None
    Lee, Ann<TAB>Required Attendee<TAB>Accepted<TAB>9/22/2026 3:04 PM
    Bob Ray <bob.ray@example.mil><TAB>Optional Attendee<TAB>Tentative
    Room 204<TAB>Resource<TAB>Accepted
  Columns are found by their header words (Name; Attendance or Role; Response or Status), so extra columns and
  their order do not matter; without a recognisable header the order Name, Attendance, Response is assumed.
  Attendance: Meeting Organizer -> the organizer; Required/Optional Attendee; Resource (rooms: not counted).
  Response: the first word is enough (Accepted 9/22/2026 ... reads as accepted): Accepted, Tentative, Declined,
  None or Not Responded or No Response -> "no response" (an invitee who has not answered), Organizer.
  A name may carry its address ("Name <a@b>") or be one; it is matched to roster.txt by e-mail, then by name,
  then by the name turned around ("Lee, Ann" <-> "Ann Lee"), case ignored. -Team names the team (else the
  meeting's subject decides, as with the calendar: team_from_subject or a team name in it; -Subject sets it,
  default "Stand-up"); people from several teams in one meeting are split by their roster team.
#>
param(
    [Parameter(Position = 0)][string]$Command = 'attend',
    [Parameter(Position = 1, ValueFromRemainingArguments = $true)][string[]]$Rest,
    [string]$Conf, [string]$Today, [string]$Team, [string]$Subject, [string]$At, [string]$File,
    [switch]$Paste, [switch]$Clip, [switch]$Send
)
$script:ATT = @{ cmd = $Command; rest = $Rest; conf = $Conf; today = $Today; team = $Team; subject = $Subject; at = $At; file = $File
    paste = [bool]$Paste; clip = [bool]$Clip; send = [bool]$Send }
# agile.ps1's functions (the journal, the stand-up template, the status text); its param block rebinds ours, so they were saved
if (-not (Get-Command LoadScrum -CommandType Function -ErrorAction SilentlyContinue)) { . "$PSScriptRoot\agile.ps1" __lib }
$Conf = $script:ATT.conf; $Today = $script:ATT.today   # -Today and $script:TODAY are one variable (names are case-insensitive): the run date

$script:ATT_USAGE = @"
attend.ps1 -- meeting attendance and metrics posting (Windows PowerShell 5.1, Constrained Language Mode safe)

  attend.ps1 [attend] [-Today YYYY-MM-DD] [-Conf path\scrum.conf]       mock calendar (calendar = mock, calendar_fixture)
  attend.ps1 [attend] -Paste | -File FILE [-Team T] [-Subject S] [-At HH:MM]
                       Outlook's Tracking tab, "Copy Status to Clipboard" (Name, Attendance, Response; tab-separated)
  attend.ps1 post [-Team T] [-Clip]       today's metrics per stand-up meeting (or per team, to paste into Teams)

Writes the attendance comments and suggested '; absent' lines into standups\<today>.txt and rows into attendance.csv.
Not ported: reading Outlook itself (COM is refused in Constrained Language Mode) and post --send.
"@

# ================================================================ bytes: UTF-8 without a byte-order mark (System.Text.Encoding is not core in CLM)
function AttUtf8([string]$text) {
    $n = $text.Length
    [byte[]]$r = @(for ($i = 0; $i -lt $n; $i++) {
            $cp = [int]$text[$i]
            if ($cp -ge 0xD800 -and $cp -le 0xDBFF -and $i + 1 -lt $n) { $cp = 0x10000 + (($cp - 0xD800) -shl 10) + ([int]$text[$i + 1] - 0xDC00); $i++ }
            if ($cp -lt 0x80) { $cp }
            elseif ($cp -lt 0x800) { 0xC0 -bor ($cp -shr 6); 0x80 -bor ($cp -band 0x3F) }
            elseif ($cp -lt 0x10000) { 0xE0 -bor ($cp -shr 12); 0x80 -bor (($cp -shr 6) -band 0x3F); 0x80 -bor ($cp -band 0x3F) }
            else { 0xF0 -bor ($cp -shr 18); 0x80 -bor (($cp -shr 12) -band 0x3F); 0x80 -bor (($cp -shr 6) -band 0x3F); 0x80 -bor ($cp -band 0x3F) }
        })
    , $r
}
function AttWrite([string]$path, [string]$text) {      # create/replace
    if ($text -eq '') { Set-Content -LiteralPath $path -Value '' -NoNewline -Encoding ASCII; return }
    Set-Content -LiteralPath $path -Value (AttUtf8 $text) -Encoding Byte
}
function AttAppend([string]$path, [string]$text) {     # Perl's open '>>'
    if ($text -eq '') { if (-not (Test-Path -LiteralPath $path)) { AttWrite $path '' }; return }
    if (Test-Path -LiteralPath $path) { Add-Content -LiteralPath $path -Value (AttUtf8 $text) -Encoding Byte } else { AttWrite $path $text }
}
function AttLc([string]$s) { if ($null -eq $s) { return '' }; $s.ToLowerInvariant() }
function AttDef($x, $d) { if ($null -eq $x) { $d } else { $x } }

# ================================================================ roster.txt (Roster::read_roster)
function AttRoster([string]$rosterPath) {
    $t = ReadText $rosterPath
    if ($null -eq $t) { return , @() }
    $out = @()
    foreach ($l in ($t -split "`n")) {
        if ($l.EndsWith("`r")) { $l = $l.Substring(0, $l.Length - 1) }
        if ($l -cmatch '^\s*(#|$)') { continue }
        if ($l.Contains('|')) { $f = @($l -split '\s*\|\s*', 5) } else { $f = @($l -split '\s*,\s*', 5) }
        $f = @(foreach ($x in $f) { $x.Trim() })
        if (-not $f[0]) { continue }
        $g = @($f + @('', '', '', '', ''))
        $out += , @{ name = $g[0]; email = $g[1]; team = $g[2]; role = $g[3]; org = $g[4] }
    }
    , $out
}

# ================================================================ events (Calendar.pm: _norm_event, attendance, text, lines, csv)
$script:RESPONSE = @{ '0' = 'none'; '1' = 'organizer'; '2' = 'tentative'; '3' = 'accepted'; '4' = 'declined'; '5' = 'no response' }
$script:RESPONSE_NAMES = @('none', 'organizer', 'tentative', 'accepted', 'declined', 'no response')
function IsoDt([string]$d) {
    if ($d -cmatch '^(\d{4}-\d{2}-\d{2})[ T](\d{2}:\d{2})(?::(\d{2}))?') { $sec = '00'; if ($Matches[3]) { $sec = $Matches[3] }; return "$($Matches[1])T$($Matches[2]):$sec" }
    $d
}
function JStr($v) {                                    # a JSON scalar as Perl sees it: numbers as their digits, true/false as 1/''
    if ($null -eq $v) { return $null }
    if ($v -is [bool]) { if ($v) { return '1' } else { return '' } }
    if ($v -is [string]) { return $v }
    Str $v
}
function NormEvent($e) {                               # -> hashtable event with normalized attendees (one row per person)
    $n = @{}
    foreach ($k in @('id', 'subject', 'start', 'end', 'location', 'organizer', 'body')) { $n[$k] = JStr $e.$k }
    $n.start = IsoDt (AttDef $n.start ''); $n.end = IsoDt (AttDef $n.end '')
    $n.body = AttDef $n.body ''
    $tm = $e.teams; $isT = $false
    if ($null -ne $tm -and ((JStr $tm) -ne '' -and (JStr $tm) -ne '0')) { $isT = $true }
    if ($n.body -cmatch 'teams\.microsoft\.com') { $isT = $true }
    if ((AttDef $n.location '') -match 'teams') { $isT = $true }
    $n.teams = [int]$isT
    $rcv = JStr $e.recurring; $n.recurring = [int]($null -ne $rcv -and $rcv -ne '' -and $rcv -ne '0')
    $list = @()
    foreach ($a in @($e.attendees)) {
        if ($null -eq $a) { continue }
        $x = @{ name = (JStr $a.name); email = (JStr $a.email); response = (JStr $a.response); type = (JStr $a.type) }
        $r = $x.response; if ($null -eq $r) { $r = 'none' }
        if ($r -cmatch '^\d$' -and $script:RESPONSE.ContainsKey($r)) { $r = $script:RESPONSE[$r] }
        $t = $x.type; if ($null -eq $t) { $t = 'required' }
        if ($t -cmatch '^\d$') { $tm2 = @{ '1' = 'required'; '2' = 'optional'; '3' = 'resource' }; if ($tm2.ContainsKey($t)) { $t = $tm2[$t] } }
        $x.response = $r; $x.type = $t
        $list += , $x
    }
    $byKey = @{}; $order = @()                            # one row per person: a real response wins over 'none'
    foreach ($x in $list) {
        $k = $x.email; if ($null -eq $k) { $k = $x.name }; $k = AttLc $k
        if (-not $byKey.ContainsKey($k)) { $byKey[$k] = $x; $order += , $k; continue }
        if (($byKey[$k].response -ceq 'none' -or $byKey[$k].response -ceq 'no response') -and $x.response -cne 'none') { $byKey[$k] = $x }
    }
    $n.attendees = @(foreach ($k in $order) { , $byKey[$k] })
    $n
}
function Attendance($ev) {                             # Calendar::attendance
    $a = @{}; foreach ($k in $script:RESPONSE_NAMES) { $a[$k] = @() }
    $all = 0
    foreach ($x in @($ev.attendees)) {
        if ((AttDef $x.type '') -ceq 'resource') { continue }
        $all++
        $r = '' + $x.response
        if ($a.ContainsKey($r) -and ($script:RESPONSE_NAMES -ccontains $r)) { $a[$r] += , $x.name }
    }
    foreach ($k in $script:RESPONSE_NAMES) { $srt = Sorted $a[$k]; $a[$k] = @($srt) }
    $a['all'] = $all
    $a
}
function SubStr5([string]$st) { if ($st.Length -le 11) { return '' }; $m = $st.Length - 11; if ($m -gt 5) { $m = 5 }; $st.Substring(11, $m) }
function AttendanceText($ev) {
    $a = Attendance $ev
    $hm = SubStr5 ('' + $ev.start)
    $out = "$hm  $($ev.subject)  ($($a['all']) invited)`n"
    foreach ($k in @('accepted', 'tentative', 'declined', 'no response')) {
        if (@($a[$k]).Count) { $out += '  ' + ("$($k):").PadRight(12) + ' ' + (@($a[$k]) -join ', ') + "`n" }
    }
    $out
}
function StandupLines($ev) {
    $a = Attendance $ev
    $txt = AttendanceText $ev
    $t = (@(foreach ($l in ($txt -csplit '(?<=\n)')) { if ($l -ne '') { "; $l" } }) -join '')
    $t + (@(foreach ($n in @($a['declined'])) { "; absent $n   ; declined in calendar`n" }) -join '')
}
function CsvF([string]$s) { if ($s -cmatch '[",\n]') { return '"' + ($s -replace '"', '""') + '"' }; $s }
function LogRows([string]$path, [string]$date, [string]$teamName, $rows) {     # Calendar::log_rows: date,team,name,status; idempotent
    $have = @{}
    $t = $null; if (Test-Path -LiteralPath $path -PathType Leaf) { $t = ReadText $path }
    if ($null -ne $t) {
        $ls = @($t -split "`n"); if ($ls.Count -and $ls[$ls.Count - 1] -eq '') { $ls = @($ls[0..($ls.Count - 2)]) }
        foreach ($l in $ls) { $cells = @($l -split ',') + @('', '', ''); $have["$($cells[0]),$($cells[1]),$($cells[2])"] = 1 }
    }
    $out = ''; if (-not (Test-Path -LiteralPath $path)) { $out = "date,team,name,status`n" }
    $n = 0
    foreach ($r in @($rows)) {
        $key = "$date,$teamName," + (CsvF $r[0])
        if ($have.ContainsKey($key)) { continue }
        $have[$key] = 1
        $out += "$date,$teamName,$(CsvF $r[0]),$($r[1])`n"; $n++
    }
    AttAppend $path $out
    $n
}
function LogAttendance([string]$path, [string]$date, [string]$teamName, $ev) {
    $a = Attendance $ev
    $rows = @(foreach ($k in @('accepted', 'tentative', 'declined', 'no response', 'none')) { foreach ($nm in @($a[$k])) { , @($nm, $k) } })
    LogRows $path $date $teamName $rows
}
function TeamFor($ev, $cf, $teams) {                   # Calendar::team_for
    if ($cf['team_from_subject']) { if (('' + $ev.subject) -match $cf['team_from_subject']) { if ($null -ne $Matches[1]) { return $Matches[1] } } }
    foreach ($t in @($teams)) { if (('' + $ev.subject) -match ('\b' + [regex]::Escape($t) + '\b')) { return $t } }
    $null
}

# ================================================================ sources
function FixtureEvents([string]$fixturePath) {
    # a project made under WSL names the fixture /mnt/c/...: on Windows that is C:\...
    if (-not (Test-Path -LiteralPath $fixturePath -PathType Leaf) -and $fixturePath -cmatch '^/mnt/([a-zA-Z])/(.*)$') { $w = $Matches[1].ToUpper() + ':\' + ($Matches[2] -replace '/', '\'); if (Test-Path -LiteralPath $w -PathType Leaf) { $fixturePath = $w } }
    if (-not (Test-Path -LiteralPath $fixturePath -PathType Leaf)) { throw "cannot open ${file}: No such file or directory`n" }
    $j = (ReadText $fixturePath) | ConvertFrom-Json
    , @(foreach ($e in @($j)) { if ($null -ne $e) { NormEvent $e } })
}
function CalEvents {                                   # today's stand-up events from the configured calendar, sorted by start
    $cf = $script:C; $cal = '' + (AttDef $cf['calendar'] 'outlook'); if ($cal -eq '') { $cal = 'outlook' }
    if ($cal -cne 'mock') {
        throw ("the calendar is '$cal': reading Outlook needs COM, which Constrained Language Mode refuses. Use the meeting's Tracking`n" +
            "list instead: in Outlook open today's stand-up, Tracking tab, Copy Status to Clipboard, then attend.ps1 -Paste [-Team T]`n")
    }
    $ev = @(); if ($cf['calendar_fixture']) { $ev = FixtureEvents $cf['calendar_fixture'] }
    $match = '' + (AttDef $cf['standup_match'] 'stand-?up')
    $d = $script:TODAY
    $sel = @(foreach ($e in $ev) { $day = ''; if (('' + $e.start).Length -ge 10) { $day = ('' + $e.start).Substring(0, 10) }; if ($day -ceq $d -and ('' + $e.subject) -match $match) { , $e } })
    $r = SortWith $sel { param($a, $b) [string]::CompareOrdinal(('' + $a.start), ('' + $b.start)) }
    , @($r)
}
function SwapName([string]$n) {                        # "Lee, Ann" <-> "Ann Lee"
    if ($n -cmatch '^\s*([^,]+?)\s*,\s*(.+?)\s*$') { return "$($Matches[2]) $($Matches[1])" }
    if ($n -cmatch '^\s*(\S+)\s+(.+?)\s*$') { return "$($Matches[2]), $($Matches[1])" }
    $n
}
function TrackingEvent([string]$text, $ros) {        # Outlook Tracking "Copy Status to Clipboard" -> the event shape
    $lines = @(foreach ($l in ($text -split "`n")) { $l = $l.TrimEnd("`r"); if ($l -cmatch '\S') { $l } })
    if (-not $lines.Count) { throw "no attendees in the Tracking text (Outlook: open the meeting, Tracking tab, Copy Status to Clipboard)`n" }
    $iN = 0; $iA = 1; $iR = 2; $start = 0
    $h = @($lines[0] -split "`t")
    $hn = -1; $ha = -1; $hr = -1
    for ($i = 0; $i -lt $h.Count; $i++) {
        $w = $h[$i].Trim().ToLowerInvariant()
        if ($hn -lt 0 -and $w -match '^(name|attendee|attendees)\b') { $hn = $i }
        elseif ($ha -lt 0 -and $w -match '^(attendance|role|type)\b') { $ha = $i }
        elseif ($hr -lt 0 -and $w -match '^(response|status)$') { $hr = $i }
    }
    if ($hn -ge 0 -and $hr -ge 0) { $iN = $hn; $iR = $hr; $iA = $ha; $start = 1 }
    elseif ($h.Count -lt 2) { throw "not a Tracking list: want tab-separated Name, Attendance, Response (Outlook: Tracking tab, Copy Status to Clipboard)`n" }
    $people = @()
    for ($k = $start; $k -lt $lines.Count; $k++) {
        $cells = @($lines[$k] -split "`t")
        $name = ''; if ($iN -lt $cells.Count) { $name = $cells[$iN].Trim() }
        if ($name -eq '') { continue }
        $role = ''; if ($iA -ge 0 -and $iA -lt $cells.Count) { $role = $cells[$iA].Trim().ToLowerInvariant() }
        $resp = ''; if ($iR -lt $cells.Count) { $resp = $cells[$iR].Trim().ToLowerInvariant() }
        $email = ''
        if ($name -cmatch '^(.*?)\s*<([^<>@\s]+@[^<>\s]+)>\s*$') { $email = $Matches[2]; $name = $Matches[1].Trim().Trim('"'); if ($name -eq '') { $name = $email } }
        elseif ($name -cmatch '^[^@\s]+@[^@\s]+$') { $email = $name }
        $type = 'required'
        if ($role -match 'optional') { $type = 'optional' } elseif ($role -match 'resource|room|equipment') { $type = 'resource' }
        $r = 'no response'
        if ($role -match 'organizer' -or $resp -match '^organi[sz]er') { $r = 'organizer' }
        elseif ($resp -match '^accept') { $r = 'accepted' }
        elseif ($resp -match '^tentative') { $r = 'tentative' }
        elseif ($resp -match '^decline') { $r = 'declined' }
        $x = @{ name = $name; response = $r; type = $type }
        if ($email -ne '') { $x.email = $email }
        $people += , $x
    }
    # match the roster by e-mail, then by name, then by the name turned around: the roster's display name wins
    foreach ($x in $people) {
        if ($x.ContainsKey('email')) { continue }
        foreach ($p in @($ros)) {
            if ((AttLc $p.name) -ceq (AttLc $x.name) -or (AttLc $p.name) -ceq (AttLc (SwapName $x.name))) { $x.name = $p.name; if ($p.email -cmatch '@') { $x.email = $p.email }; break }
        }
    }
    $hm = $script:ATT.at; if (-not $hm) { $hm = '00:00' }
    if ($hm -cnotmatch '^\d{1,2}:\d{2}$') { throw "bad -At '$hm' (want HH:MM)`n" }
    if ($hm.Length -eq 4) { $hm = "0$hm" }
    $subj = $script:ATT.subject
    if (-not $subj) { if ($script:ATT.team) { $subj = "$($script:ATT.team) Stand-up" } else { $subj = 'Stand-up' } }
    $e = @{ id = 'tracking'; subject = $subj; start = "$($script:TODAY)T$($hm):00"; end = ''; location = ''; organizer = ''; body = ''; attendees = $people }
    NormEvent $e
}

# ================================================================ attend (daily.pl cmd_attend)
function Cmd-Attend {
    $cf = $script:C
    $s = Load-S
    if ($script:ATT.paste -or $script:ATT.file) {
        if ($script:ATT.file) { $txt = ReadText $script:ATT.file; if ($null -eq $txt) { throw "cannot read $($script:ATT.file)`n" } }
        else { $txt = (Get-Clipboard -Raw); if ($null -eq $txt) { $txt = '' } }
        $ev = @(TrackingEvent $txt (AttRoster 'roster.txt'))
    } else {
        $ev = CalEvents; $ev = @($ev)
    }
    if (-not $ev.Count) { Out-Text "no stand-up meetings on $($script:TODAY) (standup_match = $($cf['standup_match']))`n"; return }
    EnsureDir $cf.standups
    $path = "$($cf.standups)/$($script:TODAY).txt"
    if (-not (Test-Path -LiteralPath $path)) { AttWrite $path (Template $s $script:TODAY $null); Out-Text "created`n$path`n" }
    $body = ReadText $path; if ($null -eq $body) { throw "cannot read ${path}`n" }
    $added = ''
    $ros = AttRoster 'roster.txt'
    $byMail = @{}; $byName = @{}
    foreach ($p in $ros) { if ($p.email -cmatch '@') { $byMail[(AttLc $p.email)] = $p } }
    foreach ($p in $ros) { $byName[(AttLc $p.name)] = $p }
    $attf = '' + $cf['attendance']
    foreach ($ev0 in $ev) {
        $atts = @(foreach ($x in @($ev0.attendees)) {
                $r = $null
                $km = AttLc (AttDef $x.email ''); if ($byMail.ContainsKey($km)) { $r = $byMail[$km] }
                if ($null -eq $r) { $kn = AttLc (AttDef $x.name ''); if ($byName.ContainsKey($kn)) { $r = $byName[$kn] } }
                $y = @{}; foreach ($k in $x.Keys) { $y[$k] = $x[$k] }
                if ($null -ne $r) { $y.name = $r.name; $y.team = $r.team }
                , $y
            })
        $e = @{}; foreach ($k in $ev0.Keys) { $e[$k] = $ev0[$k] }; $e.attendees = $atts
        $evTeam = $null
        if ($script:ATT.team -and ($script:ATT.paste -or $script:ATT.file)) { $evTeam = $script:ATT.team } else { $evTeam = TeamFor $e $cf $s.teams }
        Out-Text (AttendanceText $e)
        $parts = @()
        if ($null -ne $evTeam) { $parts += , @($evTeam, $e) }
        else {
            $per = @{}
            foreach ($x in $atts) { $tk = '' + $x.team; if ($tk -eq '') { $tk = '?' }; if (-not $per.ContainsKey($tk)) { $per[$tk] = @() }; $per[$tk] += , $x }
            foreach ($tk in (SortedKeys $per)) { $pe = @{}; foreach ($k in $e.Keys) { $pe[$k] = $e[$k] }; $pe.attendees = $per[$tk]; $parts += , @($tk, $pe) }
        }
        $rows = 0
        foreach ($p in $parts) {
            $t = $p[0]; $pe = $p[1]
            $rows += LogAttendance $attf $script:TODAY $t $pe
            $lines = StandupLines $pe
            if ($body.Contains($lines)) { continue }
            if ($t -cne '?') { $added += "== $t`n" }
            $added += $lines
        }
        $unknown = @(foreach ($x in $atts) { if (-not $x.team -and (AttDef $x.type '') -cne 'resource' -and (AttDef $x.response '') -cne 'organizer') { if ($x.email) { $x.email } else { $x.name } } })
        $tail = ''; if ($unknown.Count -and $null -eq $evTeam) { $tail = '  [not in roster.txt: ' + ($unknown -join ', ') + ']' }
        Out-Text "  -> $attf ($rows rows)$tail`n"
    }
    if ($added) { AttAppend $path "`n; ---- calendar $($script:TODAY)`n$added"; Out-Text "appended attendance to $path`n" }
}

# ================================================================ post (daily.pl cmd_post)
function Cmd-Post {
    $cf = $script:C
    if ($script:ATT.send) { Out-Err "post -Send (an Outlook meeting update to the attendees) is not ported: Constrained Language Mode refuses Outlook automation. Paste the text into the meeting chat instead (post -Clip)."; $script:RC = 2; return }
    $s = Load-S
    $cal = '' + (AttDef $cf['calendar'] 'outlook'); if ($cal -eq '') { $cal = 'outlook' }
    $notes = TodayNotes
    if ($cal -ceq 'mock') {
        $ev = CalEvents; $ev = @($ev)
        if (-not $ev.Count) { Out-Text "no stand-up meetings on $($script:TODAY)`n"; return }
        $log = @(); $clipTexts = @()
        foreach ($e in $ev) {
            $evTeam = TeamFor $e $cf $s.teams
            $text = EmailText $s $s.current $notes $cf
            if ($evTeam) { $text = "[$evTeam]`n$text" }
            $e.body = ('' + $e.body) + "`n" + $text      # the mock records it in the meeting body (Calendar::post_text)
            $log += , @('post', $e.id); $clipTexts += , $text
            Out-Text "posted metrics to '$($e.subject)' $(SubStr5 ('' + $e.start)) (saved)`n"
            $script:POSTED += , "=== $($e.id)`n$text"
        }
        if ($env:ATTEND_POSTED_FILE) { AttWrite $env:ATTEND_POSTED_FILE ($script:POSTED -join '') }   # tests: what the mock recorded
        foreach ($l in $log) { Out-Text "mock: $($l[0]) $($l[1])`n" }
        if ($script:ATT.clip) { Set-Clipboard -Value ((($clipTexts -join "`n") -replace "`n", "`r`n")); Out-Err "copied the posted text: paste into the meeting chat (Ctrl+V)" }
        return
    }
    # no calendar here: one text per team, to paste into the meeting chat or the team's channel
    $teams = @(); if ($script:ATT.team) { $teams = @($script:ATT.team) } else { $teams = @($s.teams) }
    if (-not $teams.Count) { $teams = @('') }
    EnsureDir $cf.reports
    $all = @()
    foreach ($t in $teams) {
        $text = EmailText $s $s.current $notes $cf
        $f = "$($cf.reports)/$($script:TODAY)-post.txt"
        if ($t) { $text = "[$t]`n$text"; $f = "$($cf.reports)/$($script:TODAY)-post-$t.txt" }
        AttWrite $f $text
        Out-Text "wrote $f`n"
        Out-Text $text
        $all += , $text
    }
    if ($script:ATT.clip) { Set-Clipboard -Value ((($all -join "`n") -replace "`n", "`r`n")); Out-Err "copied: paste into the meeting chat or the team's channel (Ctrl+V)" }
}

function AttDefaults {                                # Standup::read_conf's defaults that agile.ps1's conf reader does not set
    foreach ($kv in @(@('standup_match', 'stand-?up'), @('team_from_subject', ''), @('attendance', 'attendance.csv'), @('calendar', 'outlook'), @('calendar_fixture', ''))) {
        if (-not $script:C.ContainsKey($kv[0])) { $script:C[$kv[0]] = $kv[1] }
    }
}

# ================================================================ main
if ($script:ATT.cmd -ceq '__lib') { return }
$script:TODAY = $script:ATT.today
$script:PUSHED = $false
$script:RC = 0
$script:POSTED = @()
try {
    if ($script:TODAY -and $script:TODAY -cnotmatch '^\d{4}-\d{2}-\d{2}$') { throw "bad -Today '$($script:TODAY)' (want YYYY-MM-DD)`n" }
    switch -CaseSensitive ($script:ATT.cmd) {
        { $_ -in 'help', '-h', '--help', '/?' } { Out-Text ($script:ATT_USAGE -replace "`r", ''); break }
        'attend' { Load-Project; AttDefaults; Cmd-Attend; break }
        'post' { Load-Project; AttDefaults; Cmd-Post; break }
        default { Out-Err 'commands: attend post help'; $script:RC = 2 }
    }
}
catch { Out-Err ($_.Exception.Message); if (-not $script:RC) { $script:RC = 1 } }
finally { if ($script:PUSHED) { Pop-Location } }
if ($PSCommandPath) { exit $script:RC }
$global:LASTEXITCODE = $script:RC
