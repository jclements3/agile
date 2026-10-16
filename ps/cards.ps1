<#
cards.ps1 -- per-member stand-up cards (daily.pl cards) for Windows PowerShell 5.1, Constrained Language Mode safe.

  cards.cmd [-Team T] [-Today YYYY-MM-DD] [-Conf path\scrum.conf]      (or: cards.ps1 ...)

Writes reports\<today>-cards.txt (marked when scrum.conf sets a banner) and reports\<today>-cards.html: one card
per member (in progress, done this sprint, queued, yesterday's blocker) with a "send in Teams" link that opens a
1:1 chat with the card filled in. E-mails come from roster.txt, then from today's stand-up invitees when
scrum.conf has calendar = mock with a calendar_fixture (Outlook is not read here: no COM on this PC).
-Send / -Draft (Outlook mail in the Perl kit) are not available: post each card with its Teams link instead.
#>
param(
    [Parameter(Position = 0)][string]$Team,
    [string]$Conf, [Alias('Today')][string]$OnDate, [switch]$Send, [switch]$Draft, [switch]$Help
)
if ($Help -or $Team -in @('help', '-h', '--help', '/?')) {     # usage works anywhere, before any scrum.conf search
    Write-Output (Get-Content -LiteralPath $PSCommandPath -TotalCount 12 | Select-Object -Skip 1 | Out-String).TrimEnd()
    exit 0
}
$CD = @{ Team = $Team; Conf = $Conf; Today = $OnDate; Send = [bool]$Send; Draft = [bool]$Draft }
$CD_AGILE = Join-Path $PSScriptRoot 'agile.ps1'
if (-not (Test-Path -LiteralPath $CD_AGILE -PathType Leaf)) { Write-Host "cards: agile.ps1 not found beside cards.ps1 ($CD_AGILE)" -ForegroundColor Yellow; exit 2 }
. $CD_AGILE __lib
$Conf = $CD.Conf
$ErrorActionPreference = 'Stop'

function CD-Write([string]$path, [string]$text) {    # Perl's open '>:encoding(UTF-8)': no BOM, the bytes as they are
    $b = Utf8Bytes $text                              # agile.ps1's: one cast for ASCII, no per-byte array growth
    if ($b.Count -eq 0) { Set-Content -LiteralPath $path -Value '' -NoNewline -Encoding Ascii; return }
    Set-Content -LiteralPath $path -Value $b -Encoding Byte
}
$script:MARK_PRINT_CSS = '@page{margin:16mm 12mm}@media print{*{-webkit-print-color-adjust:exact;print-color-adjust:exact}body{background:#fff;padding-top:26px;padding-bottom:26px}' +
'p.mark{position:fixed;left:0;right:0;margin:0;padding:2px 0;background:#fff;text-align:center}p.mark-top{top:0}p.mark-bottom{bottom:0}' +
'details:not([open])>*:not(summary){display:block !important}details{break-inside:avoid}}'

function CD-MemberCard($s, $all, [string]$name, $lastb) {   # Scrum::member_card
    $m = $null; foreach ($k in $all.Keys) { if ($k -ceq $name) { $m = $all[$k] } }
    if ($null -eq $m) { return $null }
    $u = $s.unit; if ($null -eq $u -or $u -eq '') { $u = 'SP' }
    $cur = $s.current; if ($null -eq $cur -or "$cur" -eq '') { $cur = '-' }
    $out = "$name - sprint $cur"; if ($m.team) { $out += " ($($m.team))" }; $out += "`n"
    $out += "In progress ($(@($m.wip).Count), $(Num $m.wip_points) $u):`n"
    foreach ($i in @($m.wip)) {
        $b = ''; if ($i.blocked) { $b = "   [BLOCKED: $($i.blocked)]" }
        $out += '  ' + ('' + $i.id).PadRight(10) + ' ' + (Num $i.points).PadLeft(3) + '  ' + $i.title + $b + "`n"
    }
    if (-not @($m.wip).Count) { $out += "  (nothing committed)`n" }
    if (@($m.done).Count) { $out += 'Done this sprint: ' + (@(foreach ($i in $m.done) { $i.id }) -join ', ') + "`n" }
    if (@($m.backlog).Count) { $out += 'Queued: ' + (@(foreach ($i in $m.backlog) { "$($i.id) ($(Num $i.points))" }) -join ', ') + "`n" }
    if ($lastb) { $out += "Yesterday's blocker: $lastb`n" }
    $out += "Reply in the meeting chat:  Y: <yesterday>  T: <today>  B: <blocker or none>`n"
    $out
}
function CD-Invitees {                               # today's stand-up invitees from the mock calendar fixture: name -> e-mail
    $e = @{}
    $cfg = $script:C
    if (('' + $cfg['calendar']) -cne 'mock' -or -not $cfg['calendar_fixture']) { return $e }
    $fx = $cfg['calendar_fixture']
    if (-not (Test-Path -LiteralPath $fx -PathType Leaf)) { return $e }
    $ev = @(Get-Content -LiteralPath $fx -Raw -Encoding UTF8 | ConvertFrom-Json)
    $match = '' + $cfg['standup_match']
    $resp = @{ '0' = 'none'; '1' = 'organizer'; '2' = 'tentative'; '3' = 'accepted'; '4' = 'declined'; '5' = 'no response' }
    $evs = @(foreach ($x in $ev) { foreach ($y in @($x)) { $y } })
    $evs = @($evs | Where-Object { $st = ('' + $_.start); $st.Length -ge 10 -and $st.Substring(0, 10) -ceq $script:TODAY -and ('' + $_.subject) -match $match })
    $evs = SortOn $evs { param($x) ('' + $x.start) -creplace '^(\d{4}-\d{2}-\d{2})[ T](\d{2}:\d{2}).*$', '$1T$2' }
    foreach ($x in $evs) {
        $at = @{}; $order = @()
        foreach ($a in @($x.attendees)) {
            if ($null -eq $a) { continue }
            $r = $a.response; if ($null -eq $r) { $r = 'none' }; $r = '' + $r; if ($r -cmatch '^\d$' -and $resp.ContainsKey($r)) { $r = $resp[$r] }
            $key = $a.email; if ($null -eq $key) { $key = $a.name }; if ($null -eq $key) { $key = '' }; $key = ('' + $key).ToLower()
            $k = "~$key"
            if (-not $at.ContainsKey($k)) { $at[$k] = @{ name = $a.name; email = $a.email; response = $r }; $order += $k; continue }
            if (($at[$k].response -ceq 'none' -or $at[$k].response -ceq 'no response') -and $r -cne 'none') { $at[$k] = @{ name = $a.name; email = $a.email; response = $r } }
        }
        foreach ($k in $order) {
            $a = $at[$k]
            if ($a.email -and ('' + $a.email) -cmatch '@') { $ck = CK ('' + $a.name); if (-not $e[$ck]) { $e[$ck] = '' + $a.email } }
        }
    }
    $e
}

$script:RC = 0
try {
    if ($CD.Today -and $CD.Today -cnotmatch '^\d{4}-\d{2}-\d{2}$') { throw "bad -Today '$($CD.Today)' (want YYYY-MM-DD)`n" }
    $script:TODAY = $CD.Today
    Load-Project
    $s = Load-S
    $cfg = $script:C
    $lastb = @{}
    foreach ($tm in @($s.teams)) {
        $h = AnswerHistory $cfg.standups $tm $script:TODAY 1
        if ($h.Count) { foreach ($a in @($h[0].answers)) { if ($a.blocked) { $lastb[(CK $a.who)] = $a.b } } }
    }
    $emails = RosterEmails 'roster.txt'
    $inv = CD-Invitees
    foreach ($k in @($inv.Keys)) { if (-not $emails[$k]) { $emails[$k] = $inv[$k] } }
    EnsureDir $cfg.reports
    $all = Members $s ''
    $names = SortedKeys (Members $s $CD.Team)
    $cards = @(foreach ($n in $names) { CD-MemberCard $s $all $n $lastb[(CK $n)] })
    $txt = MarkedText $cfg ($cards -join "`n")
    $css = ($script:PAGE_CSS -replace "`r", '')
    $html = "<!DOCTYPE html>`n<html><head><meta charset=""utf-8""><title>Stand-up cards $($script:TODAY)</title><style>$css pre{white-space:pre-wrap;background:#f7f7f7;padding:8px;border:1px solid #ddd}$($script:MARK_PRINT_CSS)</style></head><body>`n"
    $html += (MarkBannerHtml $cfg 'top') + (MarkBlockHtml $cfg) + "<h1>Stand-up cards <span class=muted>$($script:TODAY)</span></h1>`n"
    for ($i = 0; $i -lt $names.Count; $i++) {
        $name = $names[$i]; $card = $cards[$i]; $mail = $emails[(CK $name)]
        if ($mail) { $a = ' <a href="' + (Esc (TeamsChatLink $mail $card)) + '">send in Teams</a>' } else { $a = ' <span class=muted>(no e-mail known)</span>' }
        $html += '<h3>' + (Esc $name) + $a + "</h3>`n<pre>" + (Esc $card) + "</pre>`n"
    }
    $html += (MarkBannerHtml $cfg 'bottom') + "</body></html>`n"
    foreach ($f in @(@("$($cfg.reports)/$($script:TODAY)-cards.txt", $txt), @("$($cfg.reports)/$($script:TODAY)-cards.html", $html))) { CD-Write $f[0] $f[1]; Write-Output "wrote $($f[0])" }
    $known = @($names | Where-Object { $emails[(CK $_)] }).Count
    $src = "from today's meeting invitees"; if (Test-Path -LiteralPath 'roster.txt' -PathType Leaf) { $src += ' and roster.txt' }
    Write-Output "  e-mail known for $known/$($names.Count) members ($src)"
    if ($CD.Send -or $CD.Draft) {
        Write-Output "cards: -Send/-Draft mail through Outlook, which this PC cannot drive: open $($cfg.reports)/$($script:TODAY)-cards.html in Edge and use each person's 'send in Teams' link (a 1:1 chat with the card filled in; press Send)."
        $script:RC = 1
    }
}
catch {
    $msg = $_.Exception.Message.TrimEnd(); Write-Host $msg -ForegroundColor Yellow
    if (-not $script:RC) { if ($msg -cmatch 'No such file or directory') { $script:RC = 2 } elseif ($msg -cmatch '^(no scrum.conf|no such file:|bad -Today)') { $script:RC = 1 } else { $script:RC = 255 } }
}
finally { if ($script:PUSHED) { Pop-Location } }
exit $script:RC
