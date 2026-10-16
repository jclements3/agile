<#
scrum.ps1 -- the kit's low-level journal CLI (bin/scrum.pl, Scrum::run) in Windows PowerShell 5.1.

Constrained Language Mode safe, no install. It reads the scrum.txt journal directly (no scrum.conf), the
same as scrum.pl, and reuses agile.ps1's journal parser and text reports (dot-sourced with __lib).

  scrum.cmd [-f JOURNAL] [--today D] COMMAND [N] [ARGS]

Options as scrum.pl takes them (Getopt::Long rules: one or two dashes, any case, unique abbreviations,
--name=value): -f/--file FILE (or $env:SCRUM_FILE; default scrum.txt), --today YYYY-MM-DD, --last N,
-o/--out FILE, --to --cc --subject (draft), --text (email).

Commands: sprint [N], velocity, backlog [TEAM], members [TEAM], epics, roadmap [-o FILE],
items [STATE] [TEAM], dashboard [-o FILE], tree [-o FILE], email [N] [--text], draft [N], csv [TABLE] [-o FILE],
check, help [COMMAND].

Differences from scrum.pl:
  draft     there is no Outlook automation on this PC: the mail body is written where scrum.pl writes it
            (%TEMP%\scrum-mail-PID.html) and the subject is printed; paste it into Teams or Outlook.
  members   scrum.pl lists people in Perl hash order (it changes from run to run); this lists them in a fixed
            order. tree.html and dashboard.html have the same kind of run-to-run order in scrum.pl; here the
            order is fixed (priority, then created date, then id).
  help      names scrum.cmd where scrum.pl's help names perl bin/scrum.pl.
#>
$script:SC_ARGV = @($args)
. "$PSScriptRoot\agile.ps1" __lib
$ErrorActionPreference = 'Stop'

# ================================================================ bytes out (UTF-8 without a BOM, as Perl's :encoding(UTF-8))
function ScUtf8Bytes([string]$text) {
    $n = $text.Length
    [byte[]]$r = @(for ($i = 0; $i -lt $n; $i++) {
            $c = [int]$text[$i]
            if ($c -ge 0xD800 -and $c -le 0xDBFF -and $i + 1 -lt $n) { $c = 0x10000 + (($c - 0xD800) -shl 10) + ([int]$text[$i + 1] - 0xDC00); $i++ }
            if ($c -lt 0x80) { $c }
            elseif ($c -lt 0x800) { 0xC0 -bor ($c -shr 6); 0x80 -bor ($c -band 0x3F) }
            elseif ($c -lt 0x10000) { 0xE0 -bor ($c -shr 12); 0x80 -bor (($c -shr 6) -band 0x3F); 0x80 -bor ($c -band 0x3F) }
            else { 0xF0 -bor ($c -shr 18); 0x80 -bor (($c -shr 12) -band 0x3F); 0x80 -bor (($c -shr 6) -band 0x3F); 0x80 -bor ($c -band 0x3F) }
        })
    , $r
}
function ScWrite([string]$path, [string]$text, [bool]$bom) {
    [byte[]]$b = ScUtf8Bytes $text
    if ($bom) { [byte[]]$b = @(0xEF, 0xBB, 0xBF) + $b }
    if ($b.Count -eq 0) { Set-Content -LiteralPath $path -Value '' -NoNewline -Encoding ASCII; return }
    Set-Content -LiteralPath $path -Value $b -Encoding Byte
}

# ================================================================ Scrum.pm's HTML pieces
$script:MARK_PRINT_CSS = '@page{margin:16mm 12mm}@media print{*{-webkit-print-color-adjust:exact;print-color-adjust:exact}body{background:#fff;padding-top:26px;padding-bottom:26px}' +
'p.mark{position:fixed;left:0;right:0;margin:0;padding:2px 0;background:#fff;text-align:center}p.mark-top{top:0}p.mark-bottom{bottom:0}' +
'details:not([open])>*:not(summary){display:block !important}details{break-inside:avoid}}'
function ScCss { ($script:PAGE_CSS -replace "`r", '') }
function HtmlV($v) { Esc (Str $v) }
function Dn($v) { if ($null -eq $v -or $v -eq '') { return '0' }; [string](Trunc $v) }        # sprintf '%d'
function OrDash($v) { if ($v) { Str $v } else { '&ndash;' } }                                 # $x || '&ndash;'
$script:CHIP_ICON = @{ good = '&#10003;'; warning = '&#9679;'; serious = '&#9650;'; critical = '&#10007;'; info = '&#8505;' }
function Chip([string]$level, $text) { "<span class=""chip $level"">$($script:CHIP_ICON[$level]) " + (HtmlV $text) + '</span>' }
function Bar($pct) { $p = $pct; if ($p -gt 100) { $p = 100 }; "<span class=""bar"" style=""width:140px""><span style=""width:$(Str $p)%""></span></span> <b>$(Str $p)%</b>" }
function Tile($n, [string]$label, [string]$class) { "<div class=""tile$class""><div class=""n"">" + (HtmlV $n) + '</div><div class="l">' + (HtmlV $label) + '</div></div>' }
function HTab($hdr, $rows, $right, $caption) {                                                # Scrum::_htable
    $r = @{}; foreach ($x in @($right)) { $r["$x"] = 1 }
    $nc = @($hdr).Count
    $cell = { param($tag, $i, $v) $cl = ''; if ($r.ContainsKey("$i")) { $cl = ' class="n"' }; "<$tag$cl>" + (HtmlV $v) + "</$tag>" }
    $o = "<table>`n"
    if ($null -ne $caption) { $o += '<caption>' + (HtmlV $caption) + "</caption>`n" }
    $o += '<tr>' + (@(for ($i = 0; $i -lt $nc; $i++) { & $cell 'th' $i $hdr[$i] }) -join '') + "</tr>`n"
    foreach ($row in @($rows)) { $o += '<tr>' + (@(for ($i = 0; $i -lt $nc; $i++) { & $cell 'td' $i $row[$i] }) -join '') + "</tr>`n" }
    $o + "</table>`n"
}
$script:SC_LOGO = $null
function LogoSvg {                                                                            # assets/logo.svg beside the kit, inlined; '' when absent
    if ($null -ne $script:SC_LOGO) { return $script:SC_LOGO }
    $script:SC_LOGO = ''
    foreach ($f in @("$PSScriptRoot\..\assets\logo.svg", "$PSScriptRoot\assets\logo.svg")) {
        $x = ReadText $f
        if ($null -eq $x) { continue }
        if ($x -cmatch '(?s)<svg[^>]*viewBox="([^"]+)"[^>]*>(.*)</svg>') {
            $vb = $Matches[1]; $body = $Matches[2]
            $body = $body -creplace '\s+', ' '; $body = $body -creplace ' opacity="1\.000000"', ''; $body = $body -creplace '(\d+\.\d{2})\d+', '$1'
            $script:SC_LOGO = "<svg class=""logo"" viewBox=""$vb"" role=""img"" aria-label=""logo"">$body</svg>"
        }
        break
    }
    $script:SC_LOGO
}
function PageHead([string]$title) { "<!DOCTYPE html>`n<html><head><meta charset=""utf-8""><title>$title</title><style>$(ScCss)$($script:MARK_PRINT_CSS)</style></head><body>`n" }
function PtsSum($items) { Sum @(foreach ($i in @($items)) { $i.points }) }

# ---------------------------------------------------------------- tree.html
$script:TREE_ITEM_HDR = @('ID', 'SP', 'Prio', 'Owner', 'Age', 'Title', 'Blocked')
function TreeItemRow($i) { , @($i.id, $i.points, $i.meta['prio'], $i.owner, $i.age, $i.title, $i.blocked) }
function EpicGroupHtml([string]$epic, $items, [string]$unit, [string]$team, [string]$scope) {
    $items = @($items)
    $hot = @(foreach ($i in $items) { if ($i.blocked) { $i } }).Count
    $tome = $null; foreach ($i in $items) { $t = $i.meta['tome']; if ($null -ne $t -and $t -ne '') { $tome = $t; break } }
    $label = $epic; if ($null -ne $tome) { $label = "$tome > $epic" }
    $open = ''; $chip = ''; if ($hot) { $open = ' open'; $chip = ' ' + (Chip 'serious' "$hot blocked") }
    $pl = 's'; if ($items.Count -eq 1) { $pl = '' }
    $cap = 'Tasks'; if ($team) { $cap += ": $team" }; if ($scope) { $cap += ", $scope" }
    "<details$open><summary>$(HtmlV $label) <span class=muted>$($items.Count) task$pl, $(Dn (PtsSum $items)) $unit</span>$chip</summary>`n" +
    (HTab $script:TREE_ITEM_HDR @(foreach ($i in $items) { , (TreeItemRow $i) }) @(1, 2, 4) $cap) + "</details>`n"
}
function IntegrationTreeHtml($s) {
    $by = @{}; $tomes = @()
    foreach ($e in (Epics $s)) { if (-not $by.ContainsKey($e.tome)) { $by[$e.tome] = @(); $tomes += $e.tome }; $by[$e.tome] += $e }
    $html = ''
    foreach ($tome in (Sorted $tomes)) {
        $html += "<details open><summary><b>$(HtmlV $tome)</b> <span class=muted>$(@($by[$tome]).Count) epics</span></summary>`n"
        foreach ($e in @($by[$tome])) {
            $bt = @{}
            foreach ($i in @($e.items)) { $t = $i.team; if ($null -eq $t) { $t = '(unassigned)' }; if (-not $bt.ContainsKey($t)) { $bt[$t] = @() }; $bt[$t] += $i }
            $nt = $bt.Count
            $chips = ''; if ($e.open) { $chips += ' ' + (Chip 'good' 'OPEN') }; if ($nt -gt 1) { $chips += ' ' + (Chip 'warning' "$nt teams &mdash; integration point") }
            $html += "<details style=""margin-left:16px""><summary>$(HtmlV $e.epic) <span class=muted>$(Dn $e.pct)% done &middot; $(Dn $e.done)/$(Dn $e.wip)/$(Dn $e.backlog) done/wip/backlog</span>$chips</summary>`n"
            $html += "<table><caption>Teams: $(HtmlV ""$tome > $($e.epic)"")</caption><tr><th>Team</th><th class=n>Tasks</th><th class=n>SP</th><th class=n>Done SP</th></tr>`n"
            foreach ($team in (SortedKeys $bt)) {
                $it = @($bt[$team])
                $done = Sum @(foreach ($x in $it) { Sum @(foreach ($a in $x.bal.Keys) { if ($a -cmatch ':Done$') { $x.bal[$a] } }) })
                $html += "<tr><td>$(HtmlV $team)</td><td class=n>$($it.Count)</td><td class=n>$(Dn (PtsSum $it))</td><td class=n>$(Dn $done)</td></tr>`n"
            }
            $html += "</table></details>`n"
        }
        $html += "</details>`n"
    }
    if ($html) { $html } else { '<p class=muted>no epics yet</p>' }
}
function TeamTreeHtml($s) {
    $plan = @{}
    foreach ($i in (AllItems $s)) {
        if (-not $i.team) { continue }
        $epic = $i.meta['epic']; if ($null -eq $epic) { $epic = '(none)' }
        $k = $null
        if ($i.state -ceq 'committed' -or $i.state -ceq 'carryover') { $k = 'sprint' } elseif ($i.state -ceq 'backlog') { $k = 'backlog' } else { continue }
        if (-not $plan.ContainsKey($i.team)) { $plan[$i.team] = @{ sprint = @{}; backlog = @{} } }
        $g = $plan[$i.team][$k]; if (-not $g.ContainsKey($epic)) { $g[$epic] = @() }; $g[$epic] += $i
    }
    $u = $s.unit; if ($null -eq $u) { $u = 'SP' }
    $html = ''
    foreach ($team in @($s.teams)) {
        $p = $plan[$team]; if ($null -eq $p) { $p = @{ sprint = @{}; backlog = @{} } }
        $sp = $p.sprint; $bl = $p.backlog
        $spn = 0; foreach ($k in $sp.Keys) { $spn += @($sp[$k]).Count }
        $bln = 0; foreach ($k in $bl.Keys) { $bln += @($bl[$k]).Count }
        $html += "<details open><summary><b>$(HtmlV $team)</b> <span class=muted>$spn in sprint &middot; $bln in backlog</span></summary>`n"
        $html += "<h3>This sprint, by epic</h3>`n"
        if ($sp.Count) { $html += (@(foreach ($ep in (SortedKeys $sp)) { EpicGroupHtml $ep $sp[$ep] $u $team 'this sprint' }) -join '') } else { $html += '<p class=muted>nothing committed</p>' }
        $html += "<h3>Backlog, by epic</h3>`n"
        if ($bl.Count) { $html += (@(foreach ($ep in (SortedKeys $bl)) { EpicGroupHtml $ep $bl[$ep] $u $team 'backlog' }) -join '') } else { $html += '<p class=muted>empty</p>' }
        $html += "</details>`n"
    }
    $html
}
function TreeHtml($s) {
    $html = PageHead 'Planning tree'
    $html += "<div class=topbar>`n<h1>$(LogoSvg)Planning tree <span class=muted>&middot; $($s.today) &middot; $(HtmlV $s.file)</span></h1>`n" +
    '<div class=badges>' + (Chip 'good' "$(@($s.teams).Count) teams") + (Chip 'good' "$((Epics $s).Count) epics") + "</div>`n</div>`n"
    $html += "<h2>Integration view <span class=muted>tome &rarr; epic &rarr; team</span></h2>`n<p class=muted>An epic touching more than one team is a coordination point &mdash; flagged below.</p>`n" + (IntegrationTreeHtml $s)
    $html += "<h2>Team view <span class=muted>team &rarr; sprint / backlog &rarr; epic</span></h2>`n<p class=muted>What each team is committed to now and what's queued, grouped for planning and assignment.</p>`n" + (TeamTreeHtml $s)
    $html + "</body></html>`n"
}

# ---------------------------------------------------------------- roadmap.html
function RoadmapHtml($s) {
    $r = Roadmap $s
    $sp = @($r.sprints); $cur = $r.current
    $u = $s.unit; if ($null -eq $u) { $u = 'SP' }
    $html = PageHead 'Roadmap'
    $cs = ''; if ($null -ne $cur) { $cs = Chip 'good' "sprint $cur" }
    $html += "<div class=topbar>`n<h1>$(LogoSvg)Roadmap <span class=muted>&middot; $($s.today) &middot; $(HtmlV $s.file)</span></h1>`n<div class=badges>" +
    (Chip 'good' "$(@($r.epics).Count) epics") + $cs + "</div>`n</div>`n"
    if (-not $sp.Count -or -not @($r.epics).Count) { return $html + "<p class=muted>no sprints yet</p>`n" + "</body></html>`n" }
    $html += "<p class=muted>Sprints $($sp[0])&ndash;$($sp[$sp.Count - 1]). Solid = $u done in that sprint, light = in progress, striped = forecast (remaining $u &divide; the owning teams' 3-sprint velocity; optimistic, since it assumes their whole velocity). Nothing here is typed: it is derived from the journal's postings.</p>`n"
    $html += "<table class=rm><caption>Epics by tome: roadmap</caption>`n<tr><th>Tome &gt; Epic</th><th>Teams</th>" +
    (@(foreach ($x in $sp) { $c = ''; if ($null -ne $cur -and $x -eq [int]$cur) { $c = ' cur' }; "<th class=""n$c"">$x</th>" }) -join '') +
    "<th class=n>Done</th><th class=n>Left</th><th>ETA</th></tr>`n"
    $last = ''
    foreach ($e in @($r.epics)) {
        if ($e.tome -cne $last) {
            $in = @(foreach ($x in @($r.epics)) { if ($x.tome -ceq $e.tome) { $x } })
            $pl = 's'; if ($in.Count -eq 1) { $pl = '' }
            $html += "<tr class=tome><td colspan=""$($sp.Count + 5)"">$(HtmlV $e.tome) <span class=muted>&middot; $($in.Count) epic$pl &middot; $(Dn (Sum @(foreach ($x in $in) { $x.done })))/$(Dn (Sum @(foreach ($x in $in) { $x.total }))) $u done</span></td></tr>`n"
            $last = $e.tome
        }
        $bc = ''; if ($e.blocked) { $bc = ' ' + (Chip 'serious' "$($e.blocked) blocked") }
        $html += '<tr><td>' + (HtmlV $e.epic) + $bc + '</td><td class=muted>' + (HtmlV (@($e.teams) -join ', ')) + '</td>'
        foreach ($n in $sp) {
            $p = $null; if ($e.per_sprint.ContainsKey("$n")) { $p = $e.per_sprint["$n"] }
            $cls = ''
            if ($p -and $p.done) { $cls = 'a' } elseif ($p -and $p.committed) { $cls = 'c' } elseif ($null -ne $e.end -and $null -ne $cur -and $n -gt [int]$cur -and $n -le $e.end) { $cls = 'f' }
            if ($null -ne $cur -and $n -eq [int]$cur) { $cls += ' cur' }
            $txt = ''; if ($p -and $p.done) { $txt = Str $p.done } elseif ($p -and $p.committed) { $txt = Str $p.committed }
            if ($cls) { $html += "<td class=""$cls"">$txt</td>" } else { $html += '<td></td>' }
        }
        $eta = 'no velocity yet'; if ($e.remaining -le 0) { $eta = 'done' } elseif ($null -ne $e.end) { $eta = "sprint $($e.end)" }
        $html += "<td class=n>$(Dn $e.pct)%</td><td class=n>$(Dn $e.remaining)</td><td>$(HtmlV $eta)</td></tr>`n"
    }
    $html += "</table>`n"
    $html + "</body></html>`n"
}

# ---------------------------------------------------------------- dashboard.html
function TagsHtml($items) {
    $seen = @{}
    (@(foreach ($i in @($items)) { $e = $i.meta['epic']; if ($null -eq $e -or $e -eq '' -or $seen.ContainsKey($e)) { continue }; $seen[$e] = 1; '<span class="tag">' + (HtmlV $e) + '</span>' }) -join '')
}
function TeamCard([string]$team, $x, [string]$u) {
    $open = @($x.open_items)
    $hot = @(foreach ($i in $open) { if ($i.blocked) { $i } }).Count
    $status = LoadStatus $x.load; if ($hot) { $status = 'critical' }
    $badge = 'ON TRACK'; if ($hot) { $badge = "$hot BLOCKED" } elseif ($null -ne $x.load) { $badge = "$($x.load)% LOAD" }
    $det = ''; if ($status -ceq 'critical') { $det = ' open' }
    $tab = '<p class=muted>none</p>'
    if ($open.Count) { $tab = HTab @('ID', 'SP', 'Title', 'Blocked') @(foreach ($i in $open) { , @($i.id, $i.points, $i.title, $i.blocked) }) @(1) "Tasks: $team, this sprint" }
    "<div class=""card status-$status"">`n  <div class=""card-head""><h3>$(HtmlV $team)</h3>$(Chip $status $badge)</div>`n" +
    "  <p class=""card-desc"">$(Dn $x.done)/$(Dn $x.committed) $u done ($(Dn $x.pct)%) &middot; $($open.Count) open</p>`n" +
    "  $(Bar $x.pct)`n" +
    "  <ul class=""facts""><li>Cap <b>$(OrDash $x.capacity)</b> &middot; Commit <b>$(Dn $x.committed)</b> &middot; Carry <b>$(Dn $x.carryover)</b> $u</li></ul>`n" +
    "  <div class=""tags"">$(TagsHtml $open)</div>`n" +
    "  <details$det><summary>$($open.Count) open tasks</summary>$tab</details>`n</div>`n"
}
function SprintHtml($s, $n) {
    $r = SprintSummary $s $n
    $u = $s.unit; if ($null -eq $u) { $u = 'SP' }
    $html = "<h2>Sprint $($r.sprint)</h2>`n<div class=""grid-wrap""><div class=""section-label"">SPRINT TEAMS</div>`n<div class=""grid"">`n"
    foreach ($team in (SortedKeys $r.teams)) { $html += TeamCard $team $r.teams[$team] $u }
    $html += "</div></div>`n"
    $t = $r.totals
    $ld = '&ndash;'; if ($null -ne $t.load) { $ld = "$($t.load)%" }
    $html + "<p class=muted>Total &middot; $(Dn $t.done)/$(Dn $t.committed) $u done ($(Dn $t.pct)%) &middot; $(Dn $t.open) open &middot; capacity $(OrDash $t.capacity) &middot; load $ld</p>`n"
}
function AttentionHtml($s, $r) {
    $rows = @()
    $bl = Blocked $s ''
    foreach ($b in $bl) { $d = BlockedDays $s $b; $lv = 'serious'; if ($d -gt 5) { $lv = 'critical' }; $rows += , @((Chip $lv "Blocked ${d}d"), (HtmlV $b.id), (HtmlV $b.team), (HtmlV $b.owner), (HtmlV $b.blocked)) }
    foreach ($x in (Unassigned $s '')) { $rows += , @((Chip 'warning' 'Unassigned'), (HtmlV $x.id), (HtmlV $x.team), '', 'committed with no owner') }
    $lt = @()
    if ($r) { foreach ($team in (SortedKeys $r.teams)) { $st = LoadStatus $r.teams[$team].load; if ($st -cne 'good') { $lt += , @($team, $r.teams[$team].load, $st) } } }
    $n = $rows.Count + $lt.Count
    if (-not $n) { return "<div class=""attn""><h2 style=""border:0;margin-top:14px"">Needs attention</h2><p class=ok>Nothing flagged &mdash; no blockers, no unassigned commitments, no team over 100% load.</p></div>`n" }
    $html = "<div class=""attn""><h2 style=""border:0;margin-top:14px"">Needs attention <span class=muted>($n)</span></h2>`n"
    if ($rows.Count) { $html += "<table><caption>Tasks needing a decision</caption><tr><th></th><th>ID</th><th>Team</th><th>Owner</th><th>Detail</th></tr>`n" + (@(foreach ($x in $rows) { '<tr><td>' + ($x -join '</td><td>') + "</td></tr>`n" }) -join '') + "</table>`n" }
    if ($lt.Count) { $html += '<div class="loadrow">' + (@(foreach ($x in $lt) { Chip $x[2] "$($x[0]) $($x[1])%" }) -join '') + "</div>`n" }
    $html + "</div>`n"
}
function DashboardHtml($s) {
    $n = $s.current
    $html = PageHead 'Scrum dashboard'
    $r = $null; if ($null -ne $n) { $r = SprintSummary $s $n }
    $bl = Blocked $s ''; $un = Unassigned $s ''
    $risk = @(); if ($r) { $risk = @(foreach ($t in (SortedKeys $r.teams)) { if ((LoadStatus $r.teams[$t].load) -cne 'good') { $t } }) }
    $worst = 'warning'; foreach ($t in $risk) { if ((LoadStatus $r.teams[$t].load) -ceq 'critical') { $worst = 'critical' } }
    $att = $bl.Count -or $un.Count -or $risk.Count
    $lvl = 'good'; $txt = 'On track'; if ($att) { $lvl = 'warning'; $txt = 'Needs attention' }
    $html += "<div class=topbar>`n<h1>$(LogoSvg)Scrum dashboard <span class=muted>&middot; $($s.today) &middot; $(HtmlV $s.file)</span></h1>`n<div class=badges>`n" +
    (Chip $lvl $txt) + (Chip 'good' "$(@($s.teams).Count) teams") + "</div>`n</div>`n"
    if ($r) {
        $html += '<p class=ticker>Load: ' + (@(foreach ($t in (SortedKeys $r.teams)) { $x = $r.teams[$t]; $l = '&ndash;'; if ($null -ne $x.load) { $l = "$($x.load)%" }; (HtmlV $t) + ': ' + $l }) -join ' &middot; ') + "</p>`n"
    }
    $u = $s.unit; if ($null -eq $u) { $u = 'SP' }
    $tiles = Tile @($s.teams).Count 'Teams' ''
    if ($r) { $tiles += Tile "$($r.totals.pct)%" 'Done' ''; $tiles += Tile $r.totals.open "Open $u" '' }
    $c = ''; if ($bl.Count) { $c = ' warning' }; $tiles += Tile $bl.Count 'Blocked' $c
    $c = ''; if ($un.Count) { $c = ' warning' }; $tiles += Tile $un.Count 'Unassigned' $c
    $c = ''; if ($risk.Count) { $c = " $worst" }; $tiles += Tile $risk.Count 'At-risk teams' $c
    $html += "<div class=tiles>`n$tiles</div>`n"
    $html += AttentionHtml $s $r
    if ($null -ne $n) { $html += SprintHtml $s $n }

    $v = Velocity $s 3
    $html += "<h2>Velocity</h2>`n<table><caption>Teams: velocity</caption><tr><th>Team</th><th class=n>Avg</th><th class=n>Latest sprint</th><th class=n>Cap</th><th class=n>Commit</th><th class=n>Done</th><th class=n>Done%</th><th>Earlier sprints</th></tr>`n"
    foreach ($team in (SortedKeys $v.team)) {
        $hist = @($v.team[$team]); $lt = $hist[$hist.Count - 1]
        $older = @(for ($k = 0; $k -lt $hist.Count - 1; $k++) { "$($hist[$k].sprint):$(Pct $hist[$k].done $hist[$k].committed)%" }) -join ', '
        $html += "<tr><td>$(HtmlV $team)</td><td class=n>$(Fmt1 $v.avg[$team])</td><td class=n>$($lt.sprint)</td><td class=n>$(OrDash $lt.capacity)</td><td class=n>$(Dn $lt.committed)</td><td class=n>$(Dn $lt.done)</td><td class=n>$(Pct $lt.done $lt.committed)%</td><td class=muted>$(HtmlV $older)</td></tr>`n"
    }
    $html += "</table>`n"

    $ep = Epics $s
    if ($ep.Count) {
        $html += "<h2>Epics</h2>`n" + (HTab @('Tome', 'Epic', 'Tasks', 'Total', 'Done', 'In sprint', 'Backlog', 'Progress') @(foreach ($e in $ep) { , @($e.tome, $e.epic, @($e.items).Count, $e.total, $e.done, $e.wip, $e.backlog, "$($e.pct)%") }) @(2..7) 'Epics by tome')
    }
    $m = Backlog $s ''; if ($null -eq $m) { $m = @() }
    $html += "<h2>Master backlog <span class=muted>$($m.Count) tasks, $(Dn (PtsSum $m)) SP</span></h2>`n<details><summary>show $($m.Count) tasks</summary>`n" +
    (HTab $script:ITEM_HDR @(foreach ($i in $m) { , (ItemRow $i) }) $script:ITEM_R 'Tasks: master backlog') + "</details>`n"
    $html += "<h2>Team backlogs</h2>`n<div class=cols>`n"
    foreach ($team in @($s.teams)) {
        $it = Backlog $s $team; if ($null -eq $it) { $it = @() }
        $body = '<p class=muted>empty</p>'; if ($it.Count) { $body = HTab $script:ITEM_HDR @(foreach ($i in $it) { , (ItemRow $i) }) $script:ITEM_R "Tasks: $team backlog" }
        $html += "<div><details><summary>$(HtmlV $team) <span class=muted>$($it.Count) tasks, $(Dn (PtsSum $it)) SP</span></summary>`n$body</details></div>`n"
    }
    $html += "</div>`n"

    $mm = Members $s ''
    $ns = '?'; if ($null -ne $n) { $ns = "$n" }
    $html += "<h2>Members</h2>`n<table>`n<caption>Members: sprint $ns</caption>`n<tr><th>Member</th><th>Team</th><th class=n>WIP SP</th><th>In progress</th><th>Done this sprint</th><th>Queued</th></tr>`n"
    $ids = { param($list) $x = @(foreach ($i in @($list)) { HtmlV "$($i.id) ($(Str $i.points))" }) -join ', '; if ($x) { $x } else { '<span class=muted>-</span>' } }
    foreach ($name in (SortedKeys $mm)) {
        $x = $mm[$name]
        $html += "<tr><td>$(HtmlV $name)</td><td>$(HtmlV $x.team)</td><td class=n>$(Dn $x.wip_points)</td><td>$(& $ids $x.wip)</td><td>$(& $ids $x.done)</td><td>$(& $ids $x.backlog)</td></tr>`n"
    }
    $html += "</table>`n"
    $html + "</body></html>`n"
}

# ================================================================ help (scrum.pl's sections of vim/doc/agile.txt)
$script:SC_HELP = @{
    '' = @'
scrum.ps1 (scrum.cmd)

    scrum.cmd [-f JOURNAL] [--today D] COMMAND [N] [ARGS]

-f FILE (or $SCRUM_FILE; default scrum.txt), --today, --last N (velocity),
-o FILE (dashboard, roadmap, tree, csv), --to --cc --subject (draft),
--text (email). N is a sprint number (default: current).
help: scrum.cmd help [COMMAND].

sprint [N]
The sprint table and open tasks.
velocity [--last N]
Committed and done per sprint; average over the last N finished sprints.
backlog [TEAM]
The master backlog or a team's.
members [TEAM]
Per owner: in progress, done, queued.
epics
Roll-up by tome and epic.
roadmap [-o FILE]
Epics by tome across sprints as text, or an HTML page with -o.
items [STATE] [TEAM]
Raw task query; STATE is master, backlog, committed, done, carryover,
removed or closed: scrum.cmd items committed Bravo.
dashboard [-o FILE]
A self-contained HTML dashboard (default dashboard.html).
tree [-o FILE]
The backlog tree as HTML (default tree.html).
email [N] [--text]
The status mail, HTML (or text) on the screen.
draft [N] [--to A] [--cc B] [--subject S]
That mail's HTML body in a file and its subject, to paste into Teams or
Outlook (no Outlook automation on this PC).
csv [TABLE] [-o FILE]
items, sprints, epics, intake or health as CSV.
check
Load the journal: "ok: N items, teams ..., sprints ...".

One command: scrum.cmd help COMMAND. Everything: agile.cmd help
'@
}
foreach ($pair in @(
        @('sprint', "sprint [N]`nThe sprint table and open tasks."),
        @('velocity', "velocity [--last N]`nCommitted and done per sprint; average over the last N finished sprints."),
        @('backlog', "backlog [TEAM]`nThe master backlog or a team's."),
        @('members', "members [TEAM]`nPer owner: in progress, done, queued."),
        @('epics', "epics`nRoll-up by tome and epic."),
        @('roadmap', "roadmap [-o FILE]`nEpics by tome across sprints as text, or an HTML page with -o."),
        @('items', "items [STATE] [TEAM]`nRaw task query; STATE is master, backlog, committed, done, carryover,`nremoved or closed: scrum.cmd items committed Bravo."),
        @('dashboard', "dashboard [-o FILE]`nA self-contained HTML dashboard (default dashboard.html)."),
        @('tree', "tree [-o FILE]`nThe backlog tree as HTML (default tree.html)."),
        @('email', "email [N] [--text]`nThe status mail, HTML (or text) on the screen."),
        @('draft', "draft [N] [--to A] [--cc B] [--subject S]`nThat mail's HTML body in a file and its subject, to paste into Teams or`nOutlook (no Outlook automation on this PC)."),
        @('csv', "csv [TABLE] [-o FILE]`nitems, sprints, epics, intake or health as CSV."),
        @('check', "check`nLoad the journal: `"ok: N items, teams ..., sprints ...`"."))) { $script:SC_HELP[$pair[0]] = $pair[1] + "`n" }
function ScHelp($a) {
    $a = @($a)
    if ($a.Count -and $a[0] -cmatch '^(?:help|--help|-h)$') { $a = @($a | Select-Object -Skip 1) }
    if (-not $a.Count) { Out-Text ($script:SC_HELP[''] -replace "`r", ''); return }
    $k = $a[0]
    if ($script:SC_HELP.ContainsKey($k) -and $k -ne '') { Out-Text $script:SC_HELP[$k]; return }
    Out-Text "no help for '$($a -join ' ')'. agile.cmd help`n"; $script:SC_RC = 1
}

# ================================================================ options (Getopt::Long, as scrum.pl configures it)
$script:SC_OPTS = @(
    @{ name = 'f'; key = 'file'; type = 's' }, @{ name = 'file'; key = 'file'; type = 's' },
    @{ name = 'to'; key = 'to'; type = 's' }, @{ name = 'cc'; key = 'cc'; type = 's' }, @{ name = 'subject'; key = 'subject'; type = 's' },
    @{ name = 'last'; key = 'last'; type = 'i' }, @{ name = 'text'; key = 'text'; type = '' }, @{ name = 'today'; key = 'today'; type = 's' },
    @{ name = 'o'; key = 'out'; type = 's' }, @{ name = 'out'; key = 'out'; type = 's' })
function ScGetOpts($argv, $o) {                    # -> remaining args, or $null after printing Getopt::Long's warning
    $rest = @(); $i = 0; $n = $argv.Count
    while ($i -lt $n) {
        $a = [string]$argv[$i]; $i++
        if ($a -ceq '--') { while ($i -lt $n) { $rest += [string]$argv[$i]; $i++ }; break }
        if ($a -notmatch '^--?(.+)$' -or $a -eq '-') { $rest += $a; continue }
        $body = $Matches[1]; $val = $null; $hasVal = $false
        $eq = $body.IndexOf('='); if ($eq -ge 0) { $val = $body.Substring($eq + 1); $body = $body.Substring(0, $eq); $hasVal = $true }
        $nm = $body.ToLower()
        $opt = $null; foreach ($x in $script:SC_OPTS) { if ($x.name -ceq $nm) { $opt = $x } }
        if ($null -eq $opt) {
            $cand = @(foreach ($x in $script:SC_OPTS) { if ($x.name.StartsWith($nm)) { $x } })
            $keys = @{}; foreach ($x in $cand) { $keys[$x.key] = 1 }
            if ($keys.Count -eq 1) { $opt = $cand[0] }
            elseif ($keys.Count -gt 1) { Out-Err ("Option $nm is ambiguous (" + ((Sorted @(foreach ($x in $cand) { $x.name })) -join ', ') + ")`n"); return $null }
            else { Out-Err "Unknown option: $nm`n"; return $null }
        }
        $show = $nm; if ($nm.Length -lt $opt.name.Length) { $show = $opt.name }
        if ($opt.type -eq '') {
            if ($hasVal) { Out-Err "Option $show does not take an argument`n"; return $null }
            $o[$opt.key] = $true; continue
        }
        if (-not $hasVal) { if ($i -ge $n) { Out-Err "Option $show requires an argument`n"; return $null }; $val = [string]$argv[$i]; $i++ }
        elseif ($val -eq '') { Out-Err "Option $show requires an argument`n"; return $null }
        if ($opt.type -eq 'i') {
            if ($val -notmatch '^[-+]?\d+$') { Out-Err "Value ""$val"" invalid for option $show (number expected)`n"; return $null }
            $o[$opt.key] = [int]$val
        } else { $o[$opt.key] = $val }
    }
    , $rest
}

# ================================================================ the CLI (Scrum::run)
function ScRun($argv) {
    $argv = @($argv)
    if ($argv.Count -and $argv[0] -cmatch '^(?:help|--help|-h)$') { ScHelp $argv; return }
    $file = $env:SCRUM_FILE; if (-not $file) { $file = 'scrum.txt' }
    $o = @{ file = $file; last = 3 }
    $rest = ScGetOpts $argv $o
    if ($null -eq $rest) { $script:SC_RC = 2; return }
    $rest = @($rest)
    $cmd = 'sprint'; if ($rest.Count) { $cmd = $rest[0]; $rest = @($rest | Select-Object -Skip 1) }
    $today = $o.today; if (-not $today) { $today = Get-Date -Format 'yyyy-MM-dd' }
    try { $s = LoadScrum $o.file $today '' } catch { Out-Err $_.Exception.Message; $script:SC_RC = 1; return }
    $n = $s.current
    if ($rest.Count -and $rest[0] -cmatch '^\d+$') { $n = $rest[0]; $rest = @($rest | Select-Object -Skip 1) }
    $a0 = $null; if ($rest.Count) { $a0 = $rest[0] }
    $a1 = $null; if ($rest.Count -gt 1) { $a1 = $rest[1] }
    switch -CaseSensitive ($cmd) {
        'sprint' { Out-Text (SprintText $s $n); break }
        'velocity' { Out-Text (VelocityText $s $o.last); break }
        'backlog' { Out-Text (BacklogText $s $a0); break }
        'members' { Out-Text (MembersText $s $a0); break }
        'epics' { Out-Text (EpicsText $s); break }
        'items' {
            $its = Items $s -state $a0 -team $a1
            Out-Text (TextTable ($script:ITEM_HDR + @('State', 'Team')) @(foreach ($i in $its) { , ((ItemRow $i) + @($i.state, $i.team)) }) $script:ITEM_R $null)
            break
        }
        'dashboard' { $out = $o.out; if (-not $out) { $out = $a0 }; if (-not $out) { $out = 'dashboard.html' }; ScWrite $out (DashboardHtml $s) $false; Out-Text "wrote $out`n"; break }
        'roadmap' { if ($o.out) { ScWrite $o.out (RoadmapHtml $s) $false; Out-Text "wrote $($o.out)`n" } else { Out-Text (RoadmapText $s) }; break }
        'tree' { $out = $o.out; if (-not $out) { $out = $a0 }; if (-not $out) { $out = 'tree.html' }; ScWrite $out (TreeHtml $s) $false; Out-Text "wrote $out`n"; break }
        'email' { if ($o.text) { Out-Text (EmailText $s $n $null $null) } else { Out-Text (EmailHtml $s $n $null $null) }; break }
        'draft' {
            $dir = $env:TEMP; if (-not $dir) { $dir = $env:TMP }; if (-not $dir) { $dir = '.' }
            $path = "$dir\scrum-mail-$PID.html"
            ScWrite $path (EmailHtml $s $n $null $null) $false
            $subj = $o.subject; if ($null -eq $subj) { $subj = "Sprint $n status $($s.today)" }
            $t = "mail body: $path`nsubject: $subj`n"
            if ($o.to) { $t += "to: $($o.to)`n" }; if ($o.cc) { $t += "cc: $($o.cc)`n" }
            $t += "no Outlook automation on this PC: open the body in Edge, select all, copy, and paste it into Teams or an Outlook mail`n"
            Out-Text $t
            break
        }
        'csv' {
            $what = $a0; if (-not $what) { $what = 'items' }
            $tables = @('items', 'sprints', 'epics', 'intake', 'health')
            if ($tables -cnotcontains $what) { Out-Err "csv: unknown table '$what' ($($tables -join ' '))`n"; $script:SC_RC = 2; return }
            if ($what -ceq 'health') {
                if (-not (Get-Command HealthCsv -CommandType Function -ErrorAction SilentlyContinue)) {
                    if (-not (Test-Path -LiteralPath "$PSScriptRoot\agile-more.ps1")) { Out-Err "csv health: needs agile-more.ps1 beside scrum.ps1 (the health signals); not available`n"; $script:SC_RC = 2; return }
                    . "$PSScriptRoot\agile-more.ps1" __lib
                }
                $t = HealthCsv $s @{}
            } else { $t = CsvTable $s $what }
            if ($o.out) { ScWrite $o.out $t $true; Out-Text "wrote $($o.out)`n" } else { Out-Text $t }
            break
        }
        'check' { Out-Text "ok: $($s.items.Count) items, teams $(@($s.teams) -join '/'), sprints $(@($s.sprints) -join '/')`n"; break }
        default { Out-Err "unknown command '$cmd' (sprint velocity backlog members epics roadmap items dashboard tree email draft csv check)`n"; $script:SC_RC = 2; return }
    }
}

$script:SC_RC = 0
try { ScRun $script:SC_ARGV }
catch { Out-Err ($_.Exception.Message); if ($env:SCRUM_TRACE) { Out-Err ($_.ScriptStackTrace) }; $script:SC_RC = 255 }
if ($PSCommandPath) { exit $script:SC_RC }
$global:LASTEXITCODE = $script:SC_RC
