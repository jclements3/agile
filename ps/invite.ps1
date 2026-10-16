<#
invite.ps1 -- the daily townhall invitation for a Teams-only PC (daily.pl invite, without Outlook automation).

Windows PowerShell 5.1, Constrained Language Mode safe: no COM, no Add-Type, pure ASCII.
Same inputs and checks as daily.pl invite: scrum.conf (townhall_subject, townhall_start, townhall_minutes,
townhall_location, banner and the marking keys, mail_domains), roster.txt (the attendees: every e-mail in it),
the marking gate on attendee domains. Instead of an Outlook item it writes:

  reports\<today>-invite.html    the Teams "new meeting" link (subject, attendees, start, end, details filled in)
  reports\<today>-townhall.ics   the same meeting as an iCalendar file, recurring every weekday (RFC 5545)

  invite.ps1 [-Dry] [-Until YYYY-MM-DD] [-Force] [-Open] [-Today YYYY-MM-DD] [-Conf path\scrum.conf]

  -Dry     print what would be created (the same text as daily.pl invite --dry); write nothing
  -Until   last day of the series
  -Force   continue despite marking errors (an attendee outside mail_domains)
  -Open    open the Teams link (Start-Process) after writing the files

The Teams link cannot carry a recurrence: in the Teams form set Repeat to "Every weekday". The .ics carries it.
Optional keys (not in daily.pl): townhall_organizer = e-mail of the organizer for the .ics (default: the
facilitator's e-mail from roster.txt).
#>
[CmdletBinding(PositionalBinding = $false)]
param(
    [switch]$Dry, [string]$Until, [switch]$Force, [switch]$Open, [string]$Today, [string]$Conf, [switch]$Help,
    [Parameter(ValueFromRemainingArguments = $true)][string[]]$Rest
)
$ErrorActionPreference = 'Stop'
$script:RC = 0

# daily.pl's own spellings work too: --dry --force --until D --today D --conf F
$i = 0; $extra = @($Rest | Where-Object { $null -ne $_ })
while ($i -lt $extra.Count) {
    $a = $extra[$i]
    switch -CaseSensitive ($a) {
        '--dry' { $Dry = $true; break }
        '--force' { $Force = $true; break }
        '--open' { $Open = $true; break }
        { $_ -in 'help', '--help', '-h', '/?' } { $Help = $true; break }
        { $_ -in '--until', '--today', '--conf', '-c' } {
            $i++; $v = $null; if ($i -lt $extra.Count) { $v = $extra[$i] }
            if ($a -eq '--until') { $Until = $v } elseif ($a -eq '--today') { $Today = $v } else { $Conf = $v }
            break
        }
        default {
            if ($a -cmatch '^--(until|today|conf)=(.*)$') { if ($Matches[1] -eq 'until') { $Until = $Matches[2] } elseif ($Matches[1] -eq 'today') { $Today = $Matches[2] } else { $Conf = $Matches[2] } }
            else { Write-Host "invite: unknown argument $a" -ForegroundColor Yellow; exit 2 }
        }
    }
    $i++
}

# ================================================================ helpers
function Out-Text([string]$t) { if ($null -eq $t -or $t -eq '') { return }; if ($t.EndsWith("`n")) { $t = $t.Substring(0, $t.Length - 1) }; foreach ($l in ($t -split "`n")) { Write-Output $l } }
function Out-Err([string]$t) { if ($null -eq $t -or $t -eq '') { return }; if ($t.EndsWith("`n")) { $t = $t.Substring(0, $t.Length - 1) }; foreach ($l in ($t -split "`n")) { Write-Host $l -ForegroundColor Yellow } }
function PerlTrue($v) { $null -ne $v -and "$v" -ne '' -and "$v" -ne '0' }
function ReadText([string]$path) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $null }
    $t = Get-Content -LiteralPath $path -Raw -Encoding UTF8
    if ($null -eq $t) { return '' }
    if ($t.Length -gt 0 -and $t[0] -eq [char]0xFEFF) { $t = $t.Substring(1) }
    $t
}
function Utf8Bytes([string]$s) {                  # UTF-8 without a BOM (Set-Content -Encoding UTF8 adds one in 5.1)
    if ($null -eq $s) { $s = '' }
    , [byte[]]@(for ($k = 0; $k -lt $s.Length; $k++) {
            $code = [int]$s[$k]
            if ($code -lt 0x80) { $code }
            elseif ($code -lt 0x800) { 0xC0 -bor ($code -shr 6); 0x80 -bor ($code -band 0x3F) }
            elseif ($code -ge 0xD800 -and $code -le 0xDBFF -and $k + 1 -lt $s.Length) {
                $cp = 0x10000 + (($code - 0xD800) -shl 10) + ([int]$s[$k + 1] - 0xDC00); $k++
                0xF0 -bor ($cp -shr 18); 0x80 -bor (($cp -shr 12) -band 0x3F); 0x80 -bor (($cp -shr 6) -band 0x3F); 0x80 -bor ($cp -band 0x3F)
            }
            else { 0xE0 -bor ($code -shr 12); 0x80 -bor (($code -shr 6) -band 0x3F); 0x80 -bor ($code -band 0x3F) }
        })
}
function WriteUtf8([string]$path, [string]$text) {
    $b = Utf8Bytes $text
    if ($b.Count -eq 0) { Set-Content -LiteralPath $path -Value '' -NoNewline -Encoding Ascii; return }
    Set-Content -LiteralPath $path -Encoding Byte -Value $b
}
function EnsureDir([string]$d) { if (-not (Test-Path -LiteralPath $d -PathType Container)) { New-Item -ItemType Directory -Path $d | Out-Null } }
function SortOrdinal($list) {                     # Perl's sort { $a cmp $b }
    $a = @($list); $n = $a.Count
    for ($x = 1; $x -lt $n; $x++) { $v = $a[$x]; $y = $x - 1; while ($y -ge 0 -and [string]::CompareOrdinal($a[$y], $v) -gt 0) { $a[$y + 1] = $a[$y]; $y-- }; $a[$y + 1] = $v }
    , $a
}
function HtmlEnc([string]$s) { if ($null -eq $s) { return '' }; $s -replace '&', '&amp;' -replace '<', '&lt;' -replace '>', '&gt;' -replace '"', '&quot;' }

# ================================================================ scrum.conf and roster.txt (as daily.pl reads them)
$script:DEFAULT_CONF = @{ journal = 'scrum.txt'; standups = 'standups'; reports = 'reports'; unit = 'SP'; to = ''; cc = ''; subject_prefix = ''
    banner = ''; marking_owner = ''; marking_category = ''; marking_handling = ''; marking_poc = ''; attendance = 'attendance.csv'; history_days = '5'; default_team = ''; facilitator = ''; readback_clean_days = '5'
}
function ReadConf([string]$path) {
    $cfg = @{}; foreach ($k in $script:DEFAULT_CONF.Keys) { $cfg[$k] = $script:DEFAULT_CONF[$k] }
    $t = ReadText $path
    if ($null -ne $t) { foreach ($l in ($t -csplit "`r?`n")) { if ($l -cmatch '^\s*(#|$)') { continue }; $l = $l -creplace '\s+#.*$', ''; if ($l -cmatch '^\s*([\w.]+)\s*=\s*(.*?)\s*$') { $cfg[$Matches[1].ToLower()] = $Matches[2] } } }
    $cfg
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
function ReadRoster([string]$file) {              # Roster::read_roster -> @{ name; email; team; role; org }
    $t = ReadText $file
    if ($null -eq $t) { return , @() }
    , @(foreach ($l in ($t -csplit "`r?`n")) {
            if ($l -cmatch '^\s*(#|$)') { continue }
            if ($l -cmatch '\|') { $f = @($l -csplit '\s*\|\s*', 5) } else { $f = @($l -csplit '\s*,\s*', 5) }
            $f = @(foreach ($x in $f) { $x.Trim() })
            if (-not $f[0]) { continue }
            $p = @{ name = $f[0]; email = ''; team = ''; role = ''; org = '' }
            if ($f.Count -gt 1) { $p.email = $f[1] }; if ($f.Count -gt 2) { $p.team = $f[2] }; if ($f.Count -gt 3) { $p.role = $f[3] }; if ($f.Count -gt 4) { $p.org = $f[4] }
            $p
        })
}
function MarkingCheck($cfg, $recipients) {         # Scrum::marking_check: "error: ..." stops, "warn: ..." advises
    $p = @()
    $b = '' + $cfg['banner']
    if ($b -ne '') {
        if (-not ($cfg['marking_owner'] -cmatch '\S')) { $p += 'warn: marking_owner is empty -- say who owns the marked material' }
        if (-not ($cfg['marking_poc'] -cmatch '\S')) { $p += 'warn: marking_poc is empty -- say who to ask about it' }
        if (-not (('' + $cfg['subject_prefix']) -cmatch '\S')) { $p += 'warn: subject_prefix is empty while a banner is set -- mail subjects will not carry the marking' }
    }
    $dom = @(('' + $cfg['mail_domains']) -csplit '[,\s]+' | Where-Object { $_ -cmatch '\S' })
    if ($dom.Count) {
        foreach ($a in @(foreach ($rcpt in $recipients) { if ($null -ne $rcpt) { $rcpt -csplit '[;,\s]+' } }) | Where-Object { $_ -cmatch '\S' }) {
            $ok = $false; foreach ($d in $dom) { if ($a -match ('[.@]' + [regex]::Escape($d) + '$')) { $ok = $true } }
            if (-not $ok) { $p += "error: recipient $a is outside mail_domains ($($dom -join ', '))" }
        }
    }
    , $p
}
function MarkingLines($cfg) {
    if (-not $cfg.banner) { return , @() }
    , @(foreach ($p in @(@('Owner', 'marking_owner'), @('Category', 'marking_category'), @('Handling', 'marking_handling'), @('POC', 'marking_poc'))) { if ($cfg[$p[1]]) { "$($p[0]): $($cfg[$p[1]])" } })
}

# ================================================================ time: the PC's zone as an iCalendar VTIMEZONE
$script:DAYS = @('SU', 'MO', 'TU', 'WE', 'TH', 'FR', 'SA')
function OffsetAt([datetime]$utc) { ($utc.ToLocalTime() - $utc).TotalMinutes }
function Utc([string]$s) { [datetime]::SpecifyKind([datetime]$s, 'Utc') }
function OffStr([double]$m) {
    $sign = '+'; if ($m -lt 0) { $sign = '-'; $m = -$m }
    $mm = [int]$m; $hh = ($mm - ($mm % 60)) / 60
    $sign + ('{0:D2}' -f [int]$hh) + ('{0:D2}' -f [int]($mm % 60))
}
function Transitions([int]$year) {                # offset changes in $year: @{ utc; from; to } (UTC instant, minutes)
    $out = @()
    $d0 = Utc "$year-01-01 12:00"
    $prev = OffsetAt $d0
    for ($d = 1; $d -le 366; $d++) {
        $u = $d0.AddDays($d)
        if ($u.Year -ne $year -and $u.Month -ne 1) { break }
        $o = OffsetAt $u
        if ($o -ne $prev) {
            $t = $u.AddDays(-1)                    # the change lies in (u-1d, u]: find it to the quarter hour
            for ($q = 1; $q -le 96; $q++) { $w = $t.AddMinutes(15 * $q); if ((OffsetAt $w) -ne $prev) { $t = $w; break } }
            $out += @{ utc = $t; from = $prev; to = $o }
            $prev = $o
        }
    }
    , $out
}
function RuleFor([datetime]$wall) {               # the yearly rule a transition on this local wall-clock date follows
    $n = [int](($wall.Day - 1 - (($wall.Day - 1) % 7)) / 7) + 1
    if ($wall.Day + 7 -gt [datetime]::DaysInMonth($wall.Year, $wall.Month)) { $n = -1 }
    @{ month = $wall.Month; nth = $n; dow = [int]$wall.DayOfWeek; time = $wall.ToString('HHmmss') }
}
function FirstIn1601($rule) {                        # the rule's date in 1601 (DTSTART of the observance, as Outlook writes it)
    $dim = [datetime]::DaysInMonth(1601, $rule.month)
    $hits = @(for ($d = 1; $d -le $dim; $d++) { $x = [datetime]"1601-$('{0:D2}' -f $rule.month)-$('{0:D2}' -f $d)"; if ([int]$x.DayOfWeek -eq $rule.dow) { $d } })
    if ($rule.nth -eq -1) { $day = $hits[$hits.Count - 1] } else { $day = $hits[$rule.nth - 1] }
    '1601' + ('{0:D2}' -f $rule.month) + ('{0:D2}' -f $day) + 'T' + $rule.time
}
function VTimezone([int]$year) {                  # -> @{ id; lines }
    $z = Get-TimeZone
    $tzLines = @('BEGIN:VTIMEZONE', "TZID:$($z.Id)")
    $tr = @(); if ($z.SupportsDaylightSavingTime) { $tr = Transitions $year }
    if ($tr.Count -lt 2) {
        $o = OffsetAt (Utc "$year-01-15 12:00")
        $tzLines += @('BEGIN:STANDARD', 'DTSTART:16010101T000000', "TZOFFSETFROM:$(OffStr $o)", "TZOFFSETTO:$(OffStr $o)", "TZNAME:$($z.StandardName)", 'END:STANDARD')
    }
    else {
        foreach ($t in $tr) {
            $wall = $t.utc.AddMinutes($t.from)    # the local clock when it changes, read in the old offset (e.g. 02:00)
            $rule = RuleFor $wall
            $kind = 'STANDARD'; $name = $z.StandardName; if ($t.to -gt $t.from) { $kind = 'DAYLIGHT'; $name = $z.DaylightName }
            $nth = "$($rule.nth)"
            $tzLines += @("BEGIN:$kind", "DTSTART:$(FirstIn1601 $rule)", "RRULE:FREQ=YEARLY;BYDAY=$nth$($script:DAYS[$rule.dow]);BYMONTH=$($rule.month)",
                "TZOFFSETFROM:$(OffStr $t.from)", "TZOFFSETTO:$(OffStr $t.to)", "TZNAME:$name", "END:$kind")
        }
    }
    $tzLines += 'END:VTIMEZONE'
    @{ id = $z.Id; lines = $tzLines }
}

# ================================================================ iCalendar text
function IcsText([string]$s) { ($s -replace '\\', '\\' -replace ';', '\;' -replace ',', '\,') -replace "`r?`n", '\n' }
function IcsFold([string]$line) {                 # fold at 75 octets (RFC 5545 3.1), never inside a UTF-8 sequence
    $out = ''; $n = 0
    for ($k = 0; $k -lt $line.Length; $k++) {
        $code = [int]$line[$k]; $ch = [string]$line[$k]
        if ($code -ge 0xD800 -and $code -le 0xDBFF -and $k + 1 -lt $line.Length) { $ch = $line.Substring($k, 2); $k++; $w = 4 }
        elseif ($code -lt 0x80) { $w = 1 } elseif ($code -lt 0x800) { $w = 2 } else { $w = 3 }
        if ($n + $w -gt 75) { $out += "`r`n "; $n = 1 }
        $out += $ch; $n += $w
    }
    $out + "`r`n"
}
function UrlEnc([string]$s) { [uri]::EscapeDataString($s) }

# ================================================================ main
if ($Help) { Get-Content -LiteralPath $PSCommandPath -TotalCount 24 | Select-Object -Skip 1 | ForEach-Object { Write-Output $_ }; exit 0 }
$pushed = $false
try {
    if ($Today -and $Today -cnotmatch '^\d{4}-\d{2}-\d{2}$') { throw "bad -Today '$Today' (want YYYY-MM-DD)" }
    $cp = $Conf; if (-not $cp) { $cp = FindConf }
    if (-not $cp) { Out-Err 'no scrum.conf found here or above (run: agile.ps1 init)'; exit 1 }
    if (-not (Test-Path -LiteralPath $cp -PathType Leaf)) { Out-Err "no such file: $cp"; exit 1 }
    $cfg = ReadConf $cp
    Push-Location; $pushed = $true
    Set-Location -LiteralPath (Split-Path -Parent (Resolve-Path -LiteralPath $cp).Path)
    $now = Get-Date
    if (-not $Today) { $Today = $now.ToString('yyyy-MM-dd') }

    $roster = ReadRoster 'roster.txt'
    $seen = @{}; $to = @()
    foreach ($p in $roster) { if ($p.email -cmatch '@' -and -not $seen.ContainsKey($p.email)) { $seen[$p.email] = $true; $to += $p.email } }
    $to = SortOrdinal $to
    if (-not $to.Count) { Out-Err 'no e-mails in roster.txt (agile.ps1 roster)'; exit 1 }
    $subject = 'Daily townhall'; if (PerlTrue $cfg['townhall_subject']) { $subject = $cfg['townhall_subject'] }
    $start = '07:30'; if (PerlTrue $cfg['townhall_start']) { $start = $cfg['townhall_start'] }
    $minutes = '60'; if (PerlTrue $cfg['townhall_minutes']) { $minutes = $cfg['townhall_minutes'] }
    $loc = 'Microsoft Teams Meeting'; if (PerlTrue $cfg['townhall_location']) { $loc = $cfg['townhall_location'] }
    # daily.pl: today, or the coming Monday when it is run on a weekend (the PC's clock, as Perl's localtime)
    $first = $Today
    $dow = [int]$now.DayOfWeek; $add = 0; if ($dow -eq 6) { $add = 2 } elseif ($dow -eq 0) { $add = 1 }
    if ($add) { $first = $now.AddDays($add).ToString('yyyy-MM-dd') }
    $mnum = [double]$minutes
    if ($mnum -le 20) { $lead = "${subject}: every weekday $start for $minutes minutes, all teams on one call. Post your status in the chat as you join; say on the line if you need another team, and take it to a follow-up -- it is not worked live." }
    else { $lead = "${subject}: an open hour, every weekday $start for $minutes minutes. Join when you can, post your status on arrival, leave when you are done -- stay if you need to clear a blocker with another team." }
    $mark = ''; if (PerlTrue $cfg['banner']) { $mark = "Marking: $($cfg['banner']). This meeting and its chat are program record." }
    $org = 'the solutions architect'; if (PerlTrue $cfg['marking_poc']) { $org = $cfg['marking_poc'] }
    $body = (@($lead, '',
            'Post ONE line in the meeting chat, capital Y T B as separators, your task ids in it:',
            '    Y did B-11   T doing B-12   B none',
            'You will get a read-back (Y / T / B as I recorded it): thumbs-up if right, or repost. Corrections come to you 1:1, not to the room.',
            'The shared screen is the cockpit: statuses grow as people post; blockers are listed with owner and team -- that is the list to work in the room.',
            '', $mark, "Attendees: $($to.Count) (roster.txt). Organiser: $org.") -join "`n")
    if ($Until -and $Until -cnotmatch '^\d{4}-\d{2}-\d{2}$') { Out-Err '--until wants YYYY-MM-DD'; exit 2 }
    $u = ''; if ($Until) { $u = " until $Until" }
    $last = $to.Count - 1; if ($last -gt 5) { $last = 5 }
    $more = ''; if ($to.Count -gt 6) { $more = ', ...' }
    Out-Text "invite: $subject  every weekday from $first $start$u, $minutes min, $loc`n  to $($to.Count) attendees: $(($to[0..$last]) -join ', ')$more`n"

    # the marking gate (daily.pl _marking_gate)
    $probs = MarkingCheck $cfg $to
    foreach ($p in $probs) { Out-Text "  marking: $p`n" }
    if (@($probs | Where-Object { $_ -cmatch '^error:' }).Count) {
        if ($Force) { Out-Text "  --force: continuing despite marking errors`n" }
        else { Out-Text "refusing: fix the marking errors above, or run again with --force`n"; exit 1 }
    }
    if ($Dry) { Out-Text "--dry: not created. Body:`n$body`n"; exit 0 }

    # ---- the meeting
    $title = $subject; if (PerlTrue $cfg['banner']) { $title = "$($cfg['banner']) $subject" }
    $t0 = [datetime]"$first $start"; $t1 = $t0.AddMinutes($mnum)
    $iso0 = $t0.ToString('yyyy-MM-ddTHH:mm:ss') + $t0.ToString('zzz'); $iso1 = $t1.ToString('yyyy-MM-ddTHH:mm:ss') + $t1.ToString('zzz')
    $link = 'https://teams.microsoft.com/l/meeting/new?subject=' + (UrlEnc $title) +
    '&attendees=' + ((@(foreach ($e in $to) { (UrlEnc $e) -replace '%40', '@' })) -join ',') +
    '&startTime=' + (UrlEnc $iso0) + '&endTime=' + (UrlEnc $iso1) + '&content=' + (UrlEnc $body)

    $repDir = $cfg.reports; EnsureDir $repDir
    # .ics: organizer from townhall_organizer, else the facilitator's e-mail in roster.txt
    $orgMail = ''; if (PerlTrue $cfg['townhall_organizer']) { $orgMail = $cfg['townhall_organizer'] }
    else { foreach ($f in @(('' + $cfg['facilitator']) -csplit '\s*;\s*' | Where-Object { $_ })) { foreach ($p in $roster) { if (-not $orgMail -and $p.name -ceq $f -and $p.email -cmatch '@') { $orgMail = $p.email } } } }
    $names = @{}; foreach ($p in $roster) { if ($p.email -cmatch '@' -and -not $names.ContainsKey($p.email)) { $names[$p.email] = $p.name } }
    $tz = VTimezone $t0.Year
    $stamp = $now.ToUniversalTime().ToString('yyyyMMddTHHmmssZ')
    $rrule = 'RRULE:FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR'
    if ($Until) { $rrule += ';UNTIL=' + ([datetime]"$Until 23:59:59").ToUniversalTime().ToString('yyyyMMddTHHmmssZ') }
    $method = 'REQUEST'; if (-not $orgMail) { $method = 'PUBLISH' }
    $uid = 'townhall-' + ($first -replace '-', '') + '-' + (($subject.ToLower() -creplace '[^a-z0-9]+', '-').Trim('-')) + '@agile-kit'
    $icsLines = @('BEGIN:VCALENDAR', 'PRODID:-//agile kit//invite.ps1//EN', 'VERSION:2.0', 'CALSCALE:GREGORIAN', "METHOD:$method") + $tz.lines +
    @('BEGIN:VEVENT', "UID:$uid", "DTSTAMP:$stamp", 'SEQUENCE:0',
        "DTSTART;TZID=$($tz.id):$($t0.ToString('yyyyMMddTHHmmss'))", "DTEND;TZID=$($tz.id):$($t1.ToString('yyyyMMddTHHmmss'))", $rrule,
        "SUMMARY:$(IcsText $title)", "LOCATION:$(IcsText $loc)", "DESCRIPTION:$(IcsText $body)")
    if ($orgMail) { $on = ''; if ($names.ContainsKey($orgMail)) { $on = ";CN=`"$($names[$orgMail] -replace '"', "'")`"" }; $icsLines += "ORGANIZER${on}:mailto:$orgMail" }
    foreach ($e in $to) { $icsLines += "ATTENDEE;CN=`"$($names[$e] -replace '"', "'")`";CUTYPE=INDIVIDUAL;ROLE=REQ-PARTICIPANT;PARTSTAT=NEEDS-ACTION;RSVP=TRUE:mailto:$e" }
    if (PerlTrue $cfg['banner']) { $icsLines += "CLASS:PRIVATE" }
    $icsLines += @('TRANSP:OPAQUE', 'STATUS:CONFIRMED', 'END:VEVENT', 'END:VCALENDAR')
    $ics = (@(foreach ($l in $icsLines) { IcsFold $l })) -join ''
    $icsName = "$Today-townhall.ics"
    WriteUtf8 "$repDir/$icsName" $ics

    # .html: the link, the instructions, the body, marked like the kit's other pages
    $ban = ''; $mb = ''
    if (PerlTrue $cfg['banner']) {
        $ban = '<p style="text-align:center;font-weight:bold;margin:0 0 8px 0;letter-spacing:.04em">' + (HtmlEnc $cfg['banner']) + "</p>`n"
        $ml = MarkingLines $cfg; if ($ml.Count) { $mb = '<p style="font-size:12px;color:#4a4a4c;margin:0 0 12px 0">' + ((@(foreach ($x in $ml) { HtmlEnc $x })) -join '<br>') + "</p>`n" }
    }
    $untilTxt = ''; if ($Until) { $untilTxt = ', ending ' + (HtmlEnc $Until) }
    $html = "<!DOCTYPE html>`n<html lang=`"en`"><head><meta charset=`"utf-8`"><title>" + (HtmlEnc $title) + "</title></head>`n" +
    "<body style=`"font-family:Segoe UI,Arial,sans-serif;font-size:14px;color:#0b0b0b;max-width:860px;margin:24px auto;padding:0 16px`">`n" + $ban + $mb +
    '<h1 style="font-size:20px;margin:0 0 6px 0">' + (HtmlEnc $title) + "</h1>`n" +
    '<p style="margin:0 0 12px 0">Every weekday from ' + (HtmlEnc $first) + ' ' + (HtmlEnc $start) + ', ' + (HtmlEnc $minutes) + ' min, ' + (HtmlEnc $loc) + $untilTxt + '. ' + $to.Count + " attendees from roster.txt.</p>`n" +
    '<p style="margin:16px 0"><a href="' + (HtmlEnc $link) + '" style="background:#27235d;color:#ffffff;padding:8px 14px;border-radius:4px;text-decoration:none;font-weight:600">Open the meeting form in Teams</a></p>' + "`n" +
    '<ol style="margin:0 0 12px 20px;padding:0"><li>Check the subject, attendees, date and time Teams filled in.</li>' +
    '<li>Set <b>Repeat</b> to <b>Every weekday</b>' + $untilTxt + ' (the link cannot carry a recurrence).</li><li>Send.</li></ol>' + "`n" +
    '<p style="margin:0 0 12px 0">Calendar file with the recurrence: <a href="' + (HtmlEnc $icsName) + '">' + (HtmlEnc $icsName) + '</a> (open it in Outlook, or import it into a calendar).</p>' + "`n" +
    '<pre style="white-space:pre-wrap;font-family:Consolas,monospace;font-size:13px;background:#f4f4f5;padding:8px 10px">' + (HtmlEnc $body) + "</pre>`n" +
    '<p style="font-size:12px;color:#4a4a4c">Attendees: ' + (HtmlEnc ($to -join ', ')) + "</p>`n" + ($ban -replace 'margin:0 0 8px 0', 'margin:16px 0 0 0') + "</body></html>`n"
    WriteUtf8 "$repDir/$Today-invite.html" $html

    Out-Text "teams: $link`n"
    Out-Text "wrote $repDir/$Today-invite.html (the Teams link, ready to click)`n"
    Out-Text "wrote $repDir/$icsName (every weekday$u, $method; open it in Outlook or import it into a calendar)`n"
    if (-not $orgMail) { Out-Text "  note: no organizer e-mail (set townhall_organizer, or facilitator with an e-mail in roster.txt): the .ics is METHOD:PUBLISH`n" }
    Out-Text "recurrence: the Teams link has no recurrence parameter -- in the Teams form set Repeat: Every weekday$u, then Send.`n"
    if ($Open) {
        try { Start-Process $link; Out-Text "opened the Teams meeting form`n" }
        catch { Out-Text "could not open the link here ($($_.Exception.Message)): open $repDir/$Today-invite.html and click the button`n" }
    }
}
catch { Out-Err ("" + $_.Exception.Message); if (-not $script:RC) { $script:RC = 1 } }
finally { if ($pushed) { Pop-Location } }
exit $script:RC
