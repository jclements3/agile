<#
agile-more.ps1 -- the agile kit's team-management metrics and planning commands in Windows PowerShell 5.1.

The companion to agile.ps1 (same project folder, same files, Constrained Language Mode safe). It loads
agile.ps1's functions (the journal parser, the sprint arithmetic) and adds what daily.pl does with them:

  health [Team]        every metric against the operating model's threshold (exit 1 on a red)
  review [N]           the Day-14 sprint report: printed, and reports\sprint-N-report.txt/.html
  rollup [YYYY-MM]     the monthly roll-up: printed, and reports\<month>-rollup.txt/.html
  csv [TABLE]          items|sprints|epics|intake|health to the console; no TABLE writes all five to reports\
  quad [Team]          the weekly quad: Technical Priorities / Watch Items / Schedule Milestones / Accomplishments
  roster               roster.txt by team, checked against the journal (exit 1 on a warning)
  roster add "Name" email Team "Role" "Org"    add or update a person (name = the Teams display name)
  report-more          the report files agile.ps1's report does not write: <today>-quad.html/.txt,
                       sprint-N-report.html/.txt, <month>-rollup.html/.txt, health.csv

  powershell -ExecutionPolicy Bypass -File agile-more.ps1 <command> [args] [-Today YYYY-MM-DD] [-Team T]

Ports lib/Metrics.pm, lib/Quad.pm, lib/Roster.pm and the #est tally of lib/Chat.pm; the output is what
perl bin/daily.pl prints and writes, byte for byte.
#>
param(
    [Parameter(Position = 0)][string]$Command = 'help',
    [Parameter(Position = 1, ValueFromRemainingArguments = $true)][string[]]$Rest,
    [string]$Conf, [string]$Today, [string]$Team
)
$script:MORE = @{ cmd = $Command; rest = $Rest; conf = $Conf; today = $Today; team = $Team }
# agile.ps1's functions: the journal parser and the sprint arithmetic. Loaded here unless the caller already did
# (". .\agile.ps1 __lib; . .\agile-more.ps1 __lib" defines both sets of functions and runs no command).
if (-not (Get-Command LoadScrum -CommandType Function -ErrorAction SilentlyContinue)) { . "$PSScriptRoot\agile.ps1" __lib }
$Command = $script:MORE.cmd; $Rest = $script:MORE.rest; $Conf = $script:MORE.conf; $Today = $script:MORE.today
$script:MORE_USAGE = @"
agile-more.ps1 -- metrics and planning for the agile kit (Windows PowerShell 5.1, Constrained Language Mode safe)

  agile-more.ps1 COMMAND [ARGS] [-Today YYYY-MM-DD] [-Conf path\scrum.conf] [-Team T]

  health [Team]        every metric against its threshold (exit 1 on a red)
  review [N]           the sprint report; writes reports\sprint-N-report.txt and .html
  rollup [YYYY-MM]     the monthly roll-up; writes reports\<month>-rollup.txt and .html
  csv [TABLE]          items | sprints | epics | intake | health (no TABLE: all five to reports\, for Excel)
  quad [Team]          the weekly quad
  roster               roster.txt by team, checked against the journal
  roster add "Name" email Team "Role" "Org"
  report-more          the quad, sprint report, roll-up and health.csv files of daily.pl report
"@

# ================================================================ files: UTF-8 without a byte-order mark
# Windows PowerShell 5.1's Set-Content -Encoding UTF8 writes a BOM, and System.Text.Encoding is not a core type in
# Constrained Language Mode, so the text is encoded here and written as bytes: the same bytes Perl writes.
function Utf8Bytes([string]$text) {
    $n = $text.Length
    [byte[]]$r = @(for ($i = 0; $i -lt $n; $i++) {
            $cv = [int]$text[$i]
            if ($cv -ge 0xD800 -and $cv -le 0xDBFF -and $i + 1 -lt $n) { $cv = 0x10000 + (($cv - 0xD800) -shl 10) + ([int]$text[$i + 1] - 0xDC00); $i++ }
            if ($cv -lt 0x80) { $cv }
            elseif ($cv -lt 0x800) { 0xC0 -bor ($cv -shr 6); 0x80 -bor ($cv -band 0x3F) }
            elseif ($cv -lt 0x10000) { 0xE0 -bor ($cv -shr 12); 0x80 -bor (($cv -shr 6) -band 0x3F); 0x80 -bor ($cv -band 0x3F) }
            else { 0xF0 -bor ($cv -shr 18); 0x80 -bor (($cv -shr 12) -band 0x3F); 0x80 -bor (($cv -shr 6) -band 0x3F); 0x80 -bor ($cv -band 0x3F) }
        })
    , $r
}
function WriteUtf8([string]$path, [string]$text) {
    if ($text -eq '') { Set-Content -LiteralPath $path -Value '' -NoNewline -Encoding ASCII; return }
    Set-Content -LiteralPath $path -Value (Utf8Bytes $text) -Encoding Byte
}

# ================================================================ small helpers (printf widths, Scrum.pm's HTML bits)
function Fmt0($x) {                                   # sprintf '%.0f' (round half to even, as C does)
    $d = [double]$x; $neg = $d -lt 0; if ($neg) { $d = -$d }
    $f = Trunc $d; $fr = $d - $f
    if ($fr -gt 0.5 -or ($fr -eq 0.5 -and ($f % 2) -eq 1)) { $f++ }
    if ($neg -and $f -ne 0) { "-$f" } else { "$f" }
}
function PadR($v, [int]$w) { (Str $v).PadRight($w) }   # %-Ns
function PadL($v, [int]$w) { (Str $v).PadLeft($w) }    # %Ns
function DInt($v) { if ($null -eq $v -or (Str $v) -eq '') { return 0 }; Trunc $v }   # %d
function Sub30($v) { $x = Str $v; if ($x.Length -gt 30) { $x.Substring(0, 30) } else { $x } }
function Last3($rows, [int]$n) { $r = @($rows); if ($r.Count -gt $n) { , @($r[($r.Count - $n)..($r.Count - 1)]) } else { , $r } }
function Hx($v) { Esc (Str $v) }                      # Scrum::_h  (not H: that is the Get-History alias)
function LogoSvg { '' }                               # Scrum::logo_svg: the kit ships no assets/logo.svg
function MarkBannerHtml($cv, [string]$pos) {
    if (-not ($cv -and $cv.banner)) { return '' }
    if (-not $pos) { $pos = 'top' }
    '<p style="text-align:center;font-weight:bold;font-family:Arial,sans-serif" class="mark mark-' + $pos + '">' + (Hx $cv.banner) + "</p>`n"
}
function MarkBlockHtml($cv) {
    if (-not ($cv -and $cv.banner)) { return '' }
    $l = MarkingLines $cv
    if (-not @($l).Count) { return '' }
    '<p style="font-family:Arial,sans-serif;font-size:12px" class="mark-block">' + (@(foreach ($x in $l) { Hx $x }) -join '<br>') + "</p>`n"
}
function HealthText($sig, [bool]$all) {
    $s = @(foreach ($x in $sig) { if ($all -or $x.level -cne 'info') { $x } })
    if (-not $s.Count) { return '' }
    "Health (thresholds from the operating model):`n" + (@(foreach ($x in $s) { $tp = ''; if ($x.team) { $tp = "$($x.team): " }; '  ' + (PadR $x.level.ToUpper() 5) + ' ' + (PadR $x.metric 14) + " $tp$($x.text)`n" }) -join '')
}
$script:EMAIL_COLOR = @{ good = '#0ca30c'; warning = '#c98500'; critical = '#d03b3b' }
$script:HEALTH_LEVEL = @{ red = 'critical'; amber = 'warning'; info = 'info' }
function HealthMailHtml($sig) {
    $s = @(foreach ($x in $sig) { if ($x.level -cne 'info') { $x } })
    if (-not $s.Count) { return '' }
    "<p style=`"margin:10px 0 4px`"><b>Health</b> <span style=`"color:#666`">(thresholds from the operating model)</span></p>`n" + (@(foreach ($x in $s) {
                $col = $script:EMAIL_COLOR[$script:HEALTH_LEVEL[$x.level]]; $tp = ''; if ($x.team) { $tp = "$($x.team): " }
                '<div style="margin:0 0 3px"><span style="display:inline-block;width:8px;height:8px;border-radius:50%;background:' + $col + ';margin-right:5px"></span><b>' + (Hx $x.metric) + '</b> ' + (Hx "$tp$($x.text)") + "</div>`n" }) -join '')
}

# ================================================================ Metrics.pm: the operating model's thresholds
$script:TH = @{ day8 = 8; day8_pct = 60; predict = 80; load_hi = 110; load_lo = 70; carry = 20; block_amber = 3; block_red = 5
    depth_lo = 2; depth_hi = 8; age = 90; intake_sprints = 3; consensus = 50; consensus_min = 4; ontime = 80; ontime_min = 5
    punt = 20; bus = 40; bus_min = 3; discipline_days = 3; sprint_days = 14; last = 3
}
$script:RANK = @{ red = 0; amber = 1; info = 2 }
function CompleteRows($s, [string]$tname) { $hist = TeamHistory $s; if (-not $hist.ContainsKey($tname)) { return , @() }; , @(foreach ($x in $hist[$tname]) { if ($x.complete) { $x } }) }
function SprintDay($s) {
    $cur = $s.current; if ($null -eq $cur) { return $null }
    $sp = SprintSpan $s; if (-not $sp.ContainsKey("$cur") -or -not $sp["$cur"].start) { return $null }
    (DaysBetween $sp["$cur"].start $s.today) + 1
}
function Ontime($it) {
    $d = 0; $cv = 0
    foreach ($h in $it.history) { if ($h.points -gt 0) { if ($h.account -cmatch ':Done$') { $d++ }; if ($h.account -cmatch ':Carryover$') { $cv++ } } }
    [int]($d -le 1 -and $cv -eq 0)
}
function OwnerShares($s, [string]$tname, $n) {
    $by = @{}; $names = @{}; $tot = 0.0
    foreach ($it in (Items $s -team $tname)) {
        $pts = 0.0; foreach ($h in $it.history) { if ($h.points -gt 0 -and $h.account -ceq "Sprint:${n}:${tname}:Committed") { $pts += $h.points } }
        if (-not $pts) { continue }
        $o = $it.owner; if ($null -eq $o) { $o = '(unassigned)' }
        $k = CK $o; if ($by.ContainsKey($k)) { $by[$k] += $pts } else { $by[$k] = $pts; $names[$k] = $o }
        $tot += $pts
    }
    $rows = @(foreach ($k in $by.Keys) { , @($names[$k], $by[$k], (PctU $by[$k] $tot)) })
    SortWith $rows { param($a, $b) if ($b[1] -gt $a[1]) { 1 } elseif ($b[1] -lt $a[1]) { -1 } else { [string]::CompareOrdinal($a[0], $b[0]) } }
}
function PuntRate($s, [string]$tname, [int]$last = 4) {
    $sprints = @($s.sprints)
    if ($sprints.Count -gt $last) { $sprints = @($sprints[($sprints.Count - $last)..($sprints.Count - 1)]) }
    $committed = @{}; $punted = @{}
    foreach ($it in (AllItems $s)) {
        foreach ($h in $it.history) {
            if ($h.points -le 0 -or $h.account -cnotmatch '^Sprint:(\d+):([^:]+):Committed$') { continue }
            $n = $Matches[1]; $t = $Matches[2]; $k = CK $t
            if (-not $committed.ContainsKey($n)) { $committed[$n] = @{} }
            if (-not $committed[$n].ContainsKey($k)) { $committed[$n][$k] = @{ team = $t; ids = @{} } }
            $committed[$n][$k].ids[(CK $it.id)] = 1
        }
        foreach ($p in @($it.punts)) {
            if ($null -eq $p -or $null -eq $p.sprint) { continue }
            $k = "$($p.sprint)|$(CK $p.team)"; if ($punted.ContainsKey($k)) { $punted[$k]++ } else { $punted[$k] = 1 }
        }
    }
    $rows = @()
    foreach ($n in $sprints) {
        $by = @{}; if ($committed.ContainsKey("$n")) { $by = $committed["$n"] }
        $teams = Sorted @(foreach ($v in $by.Values) { if (-not $tname -or $v.team -ceq $tname) { $v.team } })
        $tc = 0; $tp = 0
        foreach ($t in $teams) {
            $cv = $by[(CK $t)].ids.Count; $p = 0; if ($punted.ContainsKey("$n|$(CK $t)")) { $p = $punted["$n|$(CK $t)"] }
            $rate = 0; if ($cv) { $rate = Trunc (100 * $p / $cv + 0.5) }
            $rows += @{ sprint = $n; team = $t; committed = $cv; punted = $p; rate = $rate }
            $tc += $cv; $tp += $p
        }
        if ($teams.Count -gt 1) { $rate = 0; if ($tc) { $rate = Trunc (100 * $tp / $tc + 0.5) }; $rows += @{ sprint = $n; team = 'Total'; committed = $tc; punted = $tp; rate = $rate } }
    }
    $prevRow = @{}
    foreach ($r in $rows) { $k = CK $r.team; $p = $null; if ($prevRow.ContainsKey($k)) { $p = $prevRow[$k] }; $r.warn = [int]($r.rate -gt 20 -and $p -and $p.rate -gt 20); $prevRow[$k] = $r }
    , $rows
}
function SprintEndDate($s, $n) {
    $cur = $s.current
    if ($null -eq $n -or $null -eq $cur) { return $null }
    $sp = SprintSpan $s; if (-not $sp.ContainsKey("$cur") -or -not $sp["$cur"].start) { return $null }
    AddDays $sp["$cur"].start (14 * ([int]$n - [int]$cur + 1) - 1)
}

# ---------------------------------------------------------------- #est rounds from the pasted chat (lib/Chat.pm rounds + tally, estimates only)
$script:EST_RE = "^(?:(?:actually|revote|re-vote|my vote|vote|make it|change(?:\s+(?:mine|my vote))?\s+to|now|ok|okay|i'?d say|i say|say|call it|i think)[,:]?\s+)?(\d+(?:\.\d+)?)\s*(?:sp|pts?|points?|story\s*points?|h|hrs?|hours?|d|days?)?\.?(?:\s*,?\s*(?:maybe|probably|i think|ish|or so|tops|at most))?[.!]?$"
function NormEst($raw) {                              # -> number | '?' | $null
    $x = (Str $raw).ToLower() -creplace '^\s+|\s+$', ''
    if ($x -cmatch '^(?:\?|idk|unknown|coffee|pass)$') { return '?' }   # Chat.pm's coffee-cup emoji never matches there (no use utf8), so not here
    if ($x -cmatch $script:EST_RE) { return [double]$Matches[1] }
    $null
}
function EstTallies($msgs) {                          # the rounds of one chat, tallied: @{ kind; median; consensus } (only #est needs numbers)
    $rounds = @(); $r = $null
    foreach ($m in $msgs) {
        $lines = @(($m.text -csplit "`n")); while ($lines.Count -and $lines[$lines.Count - 1] -eq '') { $lines = @($lines | Select-Object -First ($lines.Count - 1)) }
        $first = ''; if ($lines.Count) { $first = $lines[0] }
        $marker = $null; foreach ($l in $lines) { if ($l -match '^\s*#\s*(?:est(?:imate)?|vote|poll)\b') { $marker = $l; break } }
        if ($marker -and $marker -match '^\s*#\s*(est(?:imate)?|vote|poll)\b\s*(.*?)\s*$') {
            $kind = 'vote'; if ($Matches[1].ToLower() -cmatch '^est') { $kind = 'est' }
            $r = @{ kind = $kind; answers = @{} }; $rounds += $r; continue
        }
        if (-not $r) { continue }
        if ($r.kind -ceq 'est') { $a = NormEst $first; if ($null -ne $a) { $r.answers[(CK $m.who)] = $a } }
    }
    , @(foreach ($r in $rounds) {
            $t = @{ kind = $r.kind; median = $null; consensus = 0 }
            if ($r.kind -ceq 'est') {
                $nums = Sorted @(foreach ($v in $r.answers.Values) { if ($v -isnot [string]) { $v } })
                if ($nums.Count) {
                    $cv = $nums.Count
                    if ($cv % 2) { $t.median = $nums[($cv - 1) / 2] } else { $t.median = ($nums[$cv / 2 - 1] + $nums[$cv / 2]) / 2 }
                    $t.consensus = [int]($cv -ge 2 -and $nums[0] -eq $nums[$cv - 1])
                }
            }
            $t
        })
}

# ---------------------------------------------------------------- the checks (Metrics::signals)
function Signals($s, $o) {
    if ($null -eq $o) { $o = @{} }
    $script:SIG_ACC = @()
    $add = { param($level, $metric, $tm, $text) $script:SIG_ACC += , @{ level = $level; metric = $metric; team = $tm; text = $text } }
    $cur = $s.current; $asOf = $s.today
    $only = $o.team; if (-not $only) { $only = $null }
    $mine = { param($x) (-not $only) -or ((Str $x) -ceq $only) }
    $r = SprintSummary $s $cur
    $teams = @(foreach ($t in (SortedKeys $r.teams)) { if (& $mine $t) { $t } })
    $TT = $script:TH

    # blocked age: > 3 days escalate, > 5 it is yours
    $bl = SortWith @(foreach ($i in (Blocked $s '')) { if (& $mine $i.team) { $i } }) { param($a, $b) (BlockedDays $s $b) - (BlockedDays $s $a) }
    foreach ($it in $bl) {
        $d = BlockedDays $s $it
        if (-not ($d -gt $TT.block_amber)) { continue }
        $ow = ''; if ($it.owner) { $ow = " ($($it.owner))" }
        if ($d -gt $TT.block_red) { & $add 'red' 'blocked' $it.team "$($it.id)$ow blocked $d days: $($it.blocked) -- over 5 days: your problem, on the weekly mail by name" }
        else { & $add 'amber' 'blocked' $it.team "$($it.id)$ow blocked $d days: $($it.blocked) -- escalate across teams" }
    }
    # load at planning
    foreach ($t in $teams) {
        $l = $r.teams[$t].load; if ($null -eq $l) { continue }
        if ($l -gt $TT.load_hi) { & $add 'red' 'load' $t "load $l% of capacity (over $($TT.load_hi)%): cut the commitment" }
        if ($l -lt $TT.load_lo) { & $add 'amber' 'load' $t "load $l% of capacity (under $($TT.load_lo)%): pull work from the master backlog" }
    }
    # mid-sprint: < 60% done by Day 8
    $day = SprintDay $s
    if ($null -ne $day -and $day -ge $TT.day8 -and $day -le $TT.sprint_days) {
        foreach ($t in $teams) { $x = $r.teams[$t]; if (-not ($x.committed -and $x.open -gt 0)) { continue }
            if ($x.pct -lt $TT.day8_pct) { & $add 'red' 'done by day 8' $t "sprint day ${day}: $($x.pct)% done (under $($TT.day8_pct)% by Day $($TT.day8)): descope or swarm" } }
    }
    # velocity, predictability, carryover: over completed sprints
    $v = Velocity $s
    foreach ($t in $teams) {
        $cv = CompleteRows $s $t
        $l3 = Last3 $cv $TT.last
        if ($l3.Count -eq 3 -and $l3[0].done -gt $l3[1].done -and $l3[1].done -gt $l3[2].done) {
            & $add 'amber' 'velocity' $t ('velocity down two sprints running (' + (@(foreach ($x in $l3) { Str $x.done }) -join ' -> ') + '): look for hidden blockers')
        }
        $p = $null; if ($l3.Count -ge 2) { $p = PctU (Sum @(foreach ($x in $l3) { $x.done })) (Sum @(foreach ($x in $l3) { $x.committed })) }
        if ($null -ne $p -and $p -lt $TT.predict) {
            $av = 0; if ($v.avg.ContainsKey($t)) { $av = $v.avg[$t] }
            & $add 'amber' 'predictability' $t "predictability $p% over the last $($l3.Count) sprints (under $($TT.predict)%): over-committing; cap the next commitment at velocity ($(Fmt0 $av))"
        }
        if ($cv.Count -ge 2) {
            $l2 = @($cv[$cv.Count - 2], $cv[$cv.Count - 1])
            $cr = @(foreach ($x in $l2) { $q = PctU $x.carryover $x.committed; if ($null -eq $q) { 0 } else { $q } })
            if ($cr[0] -gt $TT.carry -and $cr[1] -gt $TT.carry) { & $add 'amber' 'carryover' $t "carryover $($cr[0])% and $($cr[1])% in sprints $($l2[0].sprint) and $($l2[1].sprint) (over $($TT.carry)% two sprints running): tasks too big; split at refinement" }
        }
    }
    # WIP per person: the bus factor
    foreach ($t in $teams) {
        $people = @(foreach ($x in (OwnerShares $s $t $cur)) { if ($x[0] -cne '(unassigned)') { , $x } })
        if ($people.Count -ge $TT.bus_min -and $people[0][2] -gt $TT.bus) { & $add 'amber' 'bus factor' $t "$($people[0][0]) holds $($people[0][2])% of the sprint commitment (over $($TT.bus)%): spread the knowledge" }
    }
    # unassigned
    foreach ($t in $teams) { $u = Unassigned $s $t; if ($u.Count) { & $add 'amber' 'unassigned' $t ("$($u.Count) committed task$(Plural $u.Count) with no owner (" + (@(foreach ($i in $u) { $i.id }) -join ' ') + '): fix at the next stand-up') } }
    # on-time delivery this sprint
    foreach ($t in $teams) {
        $done = @(foreach ($i in (Items $s -team $t)) { if ($i.state -ceq 'done' -and $null -ne $i.sprint -and $null -ne $cur -and [int]$i.sprint -eq [int]$cur) { $i } })
        if ($done.Count -lt $TT.ontime_min) { continue }
        $ok = @(foreach ($i in $done) { if (Ontime $i) { 1 } })
        $p = PctU $ok.Count $done.Count
        if ($p -lt $TT.ontime) { & $add 'amber' 'on-time' $t "on-time delivery $p% this sprint (under $($TT.ontime)%): tasks too big or started too late; split at refinement" }
    }
    # punt rate: > 20% two sprints running (finished sprints only)
    $pr = @{}; $prn = @{}
    foreach ($x in (PuntRate $s '')) { if ($x.team -ceq 'Total') { continue }; $k = CK $x.team; if (-not $pr.ContainsKey($k)) { $pr[$k] = @(); $prn[$k] = $x.team }; $pr[$k] += $x }
    foreach ($t in (Sorted @(foreach ($k in $prn.Keys) { $prn[$k] }))) {
        if (-not (& $mine $t)) { continue }
        $doneS = @{}; foreach ($x in (CompleteRows $s $t)) { $doneS["$($x.sprint)"] = 1 }
        $rr = @(foreach ($x in $pr[(CK $t)]) { if ($doneS.ContainsKey("$($x.sprint)")) { $x } })
        if ($rr.Count -lt 2) { continue }
        $a1 = $rr[$rr.Count - 2]; $a2 = $rr[$rr.Count - 1]
        if ($a1.rate -gt $TT.punt -and $a2.rate -gt $TT.punt) { & $add 'amber' 'punt rate' $t "punt rate $($a1.rate)% and $($a2.rate)% (over $($TT.punt)% two sprints running): tasks arrive under-specified; refine before committing" }
    }
    # interrupts: info
    $hist = TeamHistory $s
    foreach ($t in $teams) {
        $now = $null; if ($hist.ContainsKey($t) -and $null -ne $cur) { foreach ($x in $hist[$t]) { if ([int]$x.sprint -eq [int]$cur) { $now = $x; break } } }
        if ($now -and $now.interrupt) { $q = PctU $now.interrupt $r.teams[$t].committed; if ($null -eq $q) { $q = 0 }; & $add 'info' 'interrupts' $t "$(Str $now.interrupt) SP of interrupts (new!) this sprint, $q% of the commitment" }
    }
    # sprint progress degrading two weeks running
    if ($o.prev -and $o.prev2 -and $null -ne $cur) {
        $list = @(foreach ($t in $teams) { $t }); if (-not $only) { $list += , $null }
        foreach ($t in $list) {
            $p = @(foreach ($x in @($s, $o.prev, $o.prev2)) { $y = SprintSummary $x $cur
                    if ($null -ne $t) { if ($y.teams.ContainsKey($t)) { , $y.teams[$t].pct } else { , $null } } else { , $y.totals.pct } })
            if ($null -eq $p[0] -or $null -eq $p[1] -or $null -eq $p[2]) { continue }
            if ($p[0] -lt $p[1] -and $p[1] -lt $p[2]) { & $add 'amber' 'sprint progress' $t "sprint progress degrading two weeks running ($($p[2])% -> $($p[1])% -> $($p[0])%): the commitment was wrong, not the team" }
        }
    }
    if (-not $only) {
        # backlog depth
        $vel = Sum @($v.avg.Values)
        $queued = Sum @(foreach ($i in (AllItems $s)) { if ($i.state -ceq 'backlog' -or $i.state -ceq 'master') { $i.points } })
        if ($vel -gt 0) {
            $d = $queued / $vel
            if ($d -lt $TT.depth_lo) { & $add 'amber' 'backlog depth' $null "the backlog (master + teams) is $(Fmt1 $d) sprints of work (under $($TT.depth_lo)): intake starved; ask for more" }
            if ($d -gt $TT.depth_hi) { & $add 'amber' 'backlog depth' $null "the backlog (master + teams) is $(Fmt1 $d) sprints of work (over $($TT.depth_hi)): prune it" }
        }
        # intake vs done: intake above done three completed sprints running
        $in = IntakeBySprint $s
        $doneN = @(foreach ($n in $s.sprints) { $open = $false; foreach ($rows in $hist.Values) { foreach ($x in $rows) { if ([int]$x.sprint -eq [int]$n -and -not $x.complete) { $open = $true } } }; if (-not $open) { $n } })
        $ln = Last3 $doneN $TT.intake_sprints
        if ($ln.Count -eq $TT.intake_sprints) {
            $grew = $true
            foreach ($n in $ln) { $iv = 0; if ($in.ContainsKey("$n")) { $iv = $in["$n"] }; if ($iv -le (SprintSummary $s $n).totals.done) { $grew = $false } }
            if ($grew) {
                $all = Sum @(foreach ($i in (AllItems $s)) { if ($i.state -ceq 'backlog' -or $i.state -ceq 'master') { $i.points } })
                $txt = 'intake exceeded done three sprints running (' + (@(foreach ($n in $ln) { $iv = 0; if ($in.ContainsKey("$n")) { $iv = $in["$n"] }; "${n}: $(Str $iv)/$(Str (SprintSummary $s $n).totals.done)" }) -join ', ') + ')'
                if ($vel -gt 0) { $txt += ": at current velocity this is $(Fmt0 ($all / $vel)) sprints of work; leadership decides what to cut" }
                & $add 'amber' 'intake vs done' $null $txt
            }
        }
        # epic burn against its target (target: YYYY-MM-DD on any of its tasks)
        $target = @{}
        foreach ($i in (AllItems $s)) { $e = $i.meta['epic']; $tg = $i.meta['target']; if ($null -eq $e -or $null -eq $tg) { continue }; $k = CK $e; if (-not $target[$k] -or (SLt $tg $target[$k])) { $target[$k] = $tg } }
        foreach ($e in (Roadmap $s).epics) {
            $tg = $target[(CK $e.epic)]
            if (-not $tg -or -not ($e.remaining -gt 0)) { continue }
            $eta = $null; if ($null -ne $e.end) { $eta = SprintEndDate $s $e.end }
            if (-not $eta) { if (SLt $tg (AddDays $asOf 90)) { & $add 'amber' 'epic target' $null "$($e.epic): $(Str $e.remaining) SP left and no velocity to forecast it; target $tg" }; continue }
            if (SGt $eta $tg) { & $add 'amber' 'epic target' $null "$($e.epic): ETA $eta is past its target ${tg}: re-scope, re-assign across teams, or move the date" }
        }
    }
    # backlog age: > 90 days in a backlog
    $old = SortWith @(foreach ($i in (AllItems $s)) { if (($i.state -ceq 'backlog' -or $i.state -ceq 'master') -and $i.age -gt $TT.age -and (& $mine $i.team)) { $i } }) { param($a, $b) $b.age - $a.age }
    if ($old.Count) {
        $top = @($old | Select-Object -First 3)
        & $add 'amber' 'backlog age' $only ("$($old.Count) backlog task$(Plural $old.Count) older than $($TT.age) days (oldest " + (@(foreach ($i in $top) { "$($i.id) $($i.age)d" }) -join ', ') + '): schedule or remove')
    }
    # estimate consensus rate (chat #est rounds this sprint)
    $est = @(foreach ($x in @($o.est_rounds)) { if ($x -and $x.kind -ceq 'est' -and $null -ne $x.median) { $x } })
    $cc = @(foreach ($x in $est) { if ($x.consensus) { 1 } }).Count
    if ($est.Count -ge $TT.consensus_min -and (PctU $cc $est.Count) -lt $TT.consensus) {
        & $add 'amber' 'consensus' $only "estimate consensus in $cc of $($est.Count) #est rounds ($(PctU $cc $est.Count)%, under $($TT.consensus)%): tasks under-specified; refine before estimating"
    }
    # attendance: calendar declines rising three weeks running
    if ($o.attendance -and @($o.attendance).Count) {
        $w = @(foreach ($k in 0..2) { $hi = AddDays $asOf (-7 * $k); $lo = AddDays $hi -6
                @(foreach ($x in $o.attendance) { if ($x.status -ceq 'declined' -and -not (SLt $x.date $lo) -and -not (SGt $x.date $hi) -and (& $mine $x.team)) { 1 } }).Count })
        if ($w[2] -lt $w[1] -and $w[1] -lt $w[0]) { & $add 'amber' 'attendance' $only "calendar declines rising three weeks running ($($w[2]) -> $($w[1]) -> $($w[0])): the meeting time may be wrong" }
    }
    # answer discipline: silent or incomplete 3 days running
    if ($o.answer_days) {
        foreach ($t in (SortedKeys $o.answer_days)) {
            if (-not (& $mine $t)) { continue }
            $days = @($o.answer_days[$t])
            if ($days.Count -lt $TT.discipline_days) { continue }
            $days = @($days[0..($TT.discipline_days - 1)])
            foreach ($who in @($o.rosters[$t])) {
                $bad = 0
                foreach ($dd in $days) { $an = $null; foreach ($x in $dd.answers) { if ($x.who -ceq $who) { $an = $x; break } }; if (-not $an -or $an.assumed -or -not $an.complete) { $bad++ } }
                if ($bad -eq $TT.discipline_days) { & $add 'amber' 'answers' $t "$who silent or incomplete $($TT.discipline_days) days running: talk to the lead" }
            }
        }
    }
    SortWith $script:SIG_ACC { param($a, $b) $script:RANK[$a.level] - $script:RANK[$b.level] }
}

# ---------------------------------------------------------------- the per-team metrics table (Metrics::table)
function HealthTable($s, [string]$tname) {           # -> rows @{ team; pct; load; velocity (raw avg); velocity_text ('%.1f', what Perl shows); trend; predictability; carryover; ontime; interrupt; top_share; blocked; oldest_block }
    $cur = $s.current
    $r = SprintSummary $s $cur
    $v = Velocity $s
    $hist = TeamHistory $s
    , @(foreach ($t in (SortedKeys $r.teams)) {
            if ($tname -and $t -cne $tname) { continue }
            $x = $r.teams[$t]
            $cv = CompleteRows $s $t; $l3 = Last3 $cv $script:TH.last
            $done = @(foreach ($i in (Items $s -team $t)) { if ($i.state -ceq 'done' -and $null -ne $i.sprint -and $null -ne $cur -and [int]$i.sprint -eq [int]$cur) { $i } })
            $bl = Blocked $s $t
            $sh = OwnerShares $s $t $cur
            $now = $null; if ($hist.ContainsKey($t) -and $null -ne $cur) { foreach ($y in $hist[$t]) { if ([int]$y.sprint -eq [int]$cur) { $now = $y; break } } }
            $av = 0; if ($v.avg.ContainsKey($t)) { $av = $v.avg[$t] }
            $ir = 0; if ($now) { $ir = $now.interrupt }
            $cy = $null; if ($cv.Count) { $cy = PctU $cv[$cv.Count - 1].carryover $cv[$cv.Count - 1].committed }
            $top = $null; if (@($sh).Count) { $top = $sh[0][2] }
            $okc = @(foreach ($i in $done) { if (Ontime $i) { 1 } }).Count
            $ob = $null; if ($bl.Count) { $ob = MaxOf @(foreach ($i in $bl) { BlockedDays $s $i }) }
            @{ team = $t; pct = $x.pct; load = $x.load; velocity = $av; velocity_text = (Fmt1 $av); trend = (@(foreach ($y in $l3) { Str $y.done }) -join ' ')
                predictability = (PctU (Sum @(foreach ($y in $l3) { $y.done })) (Sum @(foreach ($y in $l3) { $y.committed })))
                carryover = $cy; ontime = (PctU $okc $done.Count); interrupt = $ir; top_share = $top; blocked = $bl.Count; oldest_block = $ob }
        })
}
function HealthSignals($s, $o) {                      # Metrics::signals: rows @{ level red|amber|info; metric; team; text }, red first
    $sig = Signals $s $o; , @($sig)
}

# ---------------------------------------------------------------- the sprint report (Day 14)
$script:REPORT_METRICS = '^(velocity|predictability|carryover|punt rate|on-time|epic target|interrupts)$'
function ReportSignals($s) { $all = Signals $s @{}; , @(foreach ($g in $all) { if ($g.metric -cmatch $script:REPORT_METRICS) { $g } }) }
function SprintReportData($s, $n) {
    $r = SprintSummary $s $n
    $v = Velocity $s
    $hist = TeamHistory $s
    $teams = @(foreach ($t in (SortedKeys $r.teams)) {
            $x = $r.teams[$t]
            $rows = @(); if ($hist.ContainsKey($t)) { $rows = @($hist[$t]) }
            $cv = @(foreach ($y in $rows) { if ($y.complete -and [int]$y.sprint -le [int]$n) { $y } })
            $l3 = Last3 $cv $script:TH.last
            $row = $null; foreach ($y in $rows) { if ([int]$y.sprint -eq [int]$n) { $row = $y; break } }
            $punted = 0; foreach ($i in (AllItems $s)) { foreach ($p in @($i.punts)) { if ($p -and $null -ne $p.sprint -and [int]$p.sprint -eq [int]$n -and $p.team -ceq $t) { $punted++ } } }
            $av = 0; if ($v.avg.ContainsKey($t)) { $av = $v.avg[$t] }
            $ir = 0; if ($row) { $ir = $row.interrupt }
            @{ team = $t; committed = $x.committed; done = $x.done; carryover = $x.carryover; removed = $x.removed; open = $x.open; capacity = $x.capacity; load = $x.load; pct = $x.pct
                interrupt = $ir; velocity = (Fmt1 $av); predictability = (PctU (Sum @(foreach ($y in $l3) { $y.done })) (Sum @(foreach ($y in $l3) { $y.committed })))
                carry_rate = (PctU $x.carryover $x.committed); punted = $punted }
        })
    $ep = @(foreach ($e in (Roadmap $s).epics) {
            $in = $false
            if ($e.remaining -gt 0) { $in = $true }
            elseif ($null -ne $e.first) {
                $lastS = [int]$e.first; foreach ($k in $e.per_sprint.Keys) { if ([int]$k -gt $lastS) { $lastS = [int]$k } }
                if ([int]$n -ge [int]$e.first -and [int]$n -le $lastS) { $in = $true }
            }
            if ($in) { $e }
        })
    $u = $s.unit; if ($null -eq $u) { $u = 'SP' }
    @{ sprint = $n; as_of = $s.today; totals = $r.totals; teams = $teams; epics = $ep; unit = $u }
}
function SprintReportText($s, $n, $marking) {
    if ($null -eq $n) { $n = $s.current }
    $x = SprintReportData $s $n; $t = $x.totals
    $out = "Sprint $n report -- as of $($x.as_of): $(DInt $t.done)/$(DInt $t.committed) $($x.unit) done ($(DInt $t.pct)%), $(DInt $t.carryover) carried over, $(DInt $t.removed) removed.`n`n"
    $out += (PadR 'Team' 14) + ' ' + (PadL 'Commit' 6) + ' ' + (PadL 'Done' 5) + ' ' + (PadL 'Done%' 6) + ' ' + (PadL 'Carry' 6) + ' ' + (PadL 'Carry%' 6) + ' ' + (PadL 'Load' 6) + ' ' + (PadL 'Velocity' 8) + ' ' + (PadL 'Predict%' 9) + ' ' + (PadL 'Punted' 7) + ' ' + (PadL 'Interrupt' 9) + ' ' + (PadL 'Cap' 6) + "`n"
    foreach ($y in $x.teams) {
        $cr = '-'; if ($null -ne $y.carry_rate) { $cr = $y.carry_rate }
        $ld = '-'; if ($null -ne $y.load) { $ld = "$($y.load)%" }
        $pd = '-'; if ($null -ne $y.predictability) { $pd = $y.predictability }
        $cap = '-'; if ($y.capacity) { $cap = $y.capacity }
        $out += (PadR $y.team 14) + ' ' + (PadL $y.committed 6) + ' ' + (PadL $y.done 5) + ' ' + (PadL $y.pct 5) + '% ' + (PadL $y.carryover 6) + ' ' + (PadL $cr 5) + '% ' + (PadL $ld 6) + ' ' + (PadL $y.velocity 8) + ' ' + (PadL $pd 8) + '% ' + (PadL $y.punted 7) + ' ' + (PadL $y.interrupt 9) + ' ' + (PadL $cap 6) + "`n"
    }
    $out += "`nEpics (remaining / team velocity = sprints to done):`n"
    foreach ($e in $x.epics) {
        $eta = 'no forecast'; if ($null -ne $e.end) { $eta = "ETA sprint $($e.end)"; if ($e.blocked) { $eta += ", $($e.blocked) blocked" } }
        $out += '  ' + (PadR "$($e.tome) > $($e.epic)" 40) + ' ' + (PadL (DInt $e.pct) 4) + '%  ' + (PadL (DInt $e.remaining) 4) + " SP left  $eta`n"
    }
    $sig = ReportSignals $s
    if ($sig.Count) { $out += "`n" + (HealthText $sig $true) }
    MarkedText $marking $out
}
function SprintReportHtml($s, $n, $marking) {
    if ($null -eq $n) { $n = $s.current }
    $x = SprintReportData $s $n; $t = $x.totals
    $td = 'style="border:1px solid #bbb;padding:3px 8px"'; $tdn = 'style="border:1px solid #bbb;padding:3px 8px;text-align:right"'
    $html = "<!DOCTYPE html>`n<html><head><meta charset=`"utf-8`"><title>Sprint $n report</title></head><body style=`"font-family:Segoe UI,Arial,sans-serif;font-size:14px`">`n" + (MarkBannerHtml $marking 'top') + (MarkBlockHtml $marking)
    $html += "<h1 style=`"font-size:20px`">" + (LogoSvg) + "Sprint $n report <span style=`"color:#666;font-weight:normal`">as of " + (Hx $x.as_of) + "</span></h1>`n"
    $html += "<p><b>$(DInt $t.done) of $(DInt $t.committed) $(Hx $x.unit) done ($(DInt $t.pct)%)</b>, $(DInt $t.carryover) carried over, $(DInt $t.removed) removed.</p>`n"
    $cols = @(@('team', 'Team'), @('committed', 'Commit'), @('done', 'Done'), @('pct', 'Done%'), @('carryover', 'Carry'), @('carry_rate', 'Carry%'), @('load', 'Load%'), @('velocity', 'Velocity (avg 3)'),
        @('predictability', 'Predictability%'), @('punted', 'Punted'), @('interrupt', 'Interrupt SP'), @('capacity', 'Capacity'))
    $html += '<table style="border-collapse:collapse"><tr>' + (@(foreach ($cv in $cols) { if ($cv[0] -ceq 'team') { "<th $td>$($cv[1])</th>" } else { "<th $tdn>$($cv[1])</th>" } }) -join '') + "</tr>`n"
    foreach ($row in $x.teams) {
        $html += '<tr>' + (@(foreach ($cv in $cols) {
                    $val = $row[$cv[0]]
                    $bad = ($cv[0] -ceq 'predictability' -and $null -ne $val -and $val -lt $script:TH.predict) -or ($cv[0] -ceq 'carry_rate' -and $null -ne $val -and $val -gt $script:TH.carry) -or ($cv[0] -ceq 'load' -and $null -ne $val -and ($val -gt $script:TH.load_hi -or $val -lt $script:TH.load_lo))
                    if ($cv[0] -ceq 'team') { "<td $td>" + (Hx $val) + '</td>' }
                    else { $b1 = ''; $b2 = ''; if ($bad) { $b1 = '<b style="color:#c98500">'; $b2 = '</b>' }; $vv = '&ndash;'; if ($null -ne $val -and (Str $val) -ne '') { $vv = Hx $val }; "<td $tdn>$b1$vv$b2</td>" }
                }) -join '') + "</tr>`n"
    }
    $html += "</table>`n<h2 style=`"font-size:16px`">Epics <span style=`"color:#666;font-weight:normal`">remaining &divide; team velocity = sprints to done</span></h2>`n<table style=`"border-collapse:collapse`"><tr><th $td>Tome</th><th $td>Epic</th><th $tdn>Done%</th><th $tdn>SP left</th><th $td>ETA</th></tr>`n"
    $html += (@(foreach ($e in $x.epics) { $eta = 'no forecast'; if ($null -ne $e.end) { $eta = "sprint $($e.end)"; if ($e.blocked) { $eta += " ($($e.blocked) blocked)" } }
                "<tr><td $td>" + (Hx $e.tome) + "</td><td $td>" + (Hx $e.epic) + "</td><td $tdn>$($e.pct)%</td><td $tdn>$(Str $e.remaining)</td><td $td>$eta</td></tr>`n" }) -join '') + "</table>`n"
    $sig = ReportSignals $s
    if ($sig.Count) { $html += HealthMailHtml $sig }
    $html + (MarkBannerHtml $marking 'bottom') + "</body></html>`n"
}

# ---------------------------------------------------------------- the monthly roll-up
function ReadAttendance([string]$file) {
    $text = ReadText $file; if ($null -eq $text) { return , @() }
    $lines = @($text -csplit "`n"); if ($lines.Count -and $lines[$lines.Count - 1] -eq '') { $lines = @($lines | Select-Object -First ($lines.Count - 1)) }
    $rows = @(); $no = 0
    foreach ($l in $lines) {
        $no++
        $l = $l -creplace "`r$", ''
        if ($no -eq 1 -and $l -cmatch '^date,') { continue }
        if ($l -cnotmatch '\S') { continue }
        $f = @(foreach ($m in [regex]::Matches($l, '("(?:[^"]|"")*"|[^,]*)(?:,|$)')) { $m.Groups[1].Value -creplace '^"|"$', '' })
        $st = ''; if ($f.Count -gt 3) { $st = $f[3] }
        $mi = $null; if ($f.Count -gt 6) { $mi = $f[6] }
        $rows += @{ date = $f[0]; team = $f[1]; name = $f[2]; status = $st; minutes = $mi }
    }
    , $rows
}
$script:AGE = @('0-30', '31-60', '61-90', 'over 90')
$script:ATT = @('answered', 'present', 'brief', 'accepted', 'tentative', 'declined', 'no response')
function Pre7($v) { $x = Str $v; if ($x.Length -gt 7) { $x.Substring(0, 7) } else { $x } }   # substr($_, 0, 7)
function RollupData($s, [string]$month, $attRows) {
    if (-not $month) { $month = $s.today.Substring(0, 7) }
    $span = SprintSpan $s; $in = IntakeBySprint $s
    $sp = SortOn @(foreach ($k in $span.Keys) { $x = $span[$k]; if (-not (SGt (Pre7 $x.start) $month) -and -not (SLt (Pre7 $x.end) $month)) { $k } }) { param($k) [int]$k }
    $ageB = @{}
    foreach ($i in (AllItems $s)) {
        if ($i.state -cne 'backlog' -and $i.state -cne 'master') { continue }
        $b = 'over 90'; if ($i.age -le 30) { $b = '0-30' } elseif ($i.age -le 60) { $b = '31-60' } elseif ($i.age -le 90) { $b = '61-90' }
        if (-not $ageB.ContainsKey($b)) { $ageB[$b] = @(0, 0.0) }
        $ageB[$b] = @(($ageB[$b][0] + 1), ($ageB[$b][1] + $i.points))
    }
    $a = @{}; $an = @{}
    foreach ($x in $attRows) {
        if ((Pre7 $x.date) -cne $month) { continue }
        $tm = $x.team; if (-not $tm) { $tm = '?' }
        $k = CK $tm; if (-not $a.ContainsKey($k)) { $a[$k] = @{}; $an[$k] = $tm }
        $sk = CK $x.status; if (-not $a[$k].ContainsKey($sk)) { $a[$k][$sk] = @{ name = $x.status; n = 0 } }; $a[$k][$sk].n++
    }
    $u = $s.unit; if ($null -eq $u) { $u = 'SP' }
    @{ month = $month; as_of = $s.today; unit = $u; epics = (Epics $s)
        sprints = @(foreach ($k in $sp) { $iv = 0; if ($in.ContainsKey("$k")) { $iv = $in["$k"] }; @{ sprint = $k; start = $span[$k].start; intake = $iv; done = (SprintSummary $s $k).totals.done } })
        age = $ageB; attendance = $a; att_names = $an }
}
function AttStatuses($m) {                            # one team's statuses: the known ones in order, then the rest sorted
    $others = Sorted @(foreach ($v in $m.Values) { if ($script:ATT -cnotcontains $v.name) { $v.name } })
    , @(foreach ($nm in (@($script:ATT) + @($others))) { $k = CK $nm; if ($m.ContainsKey($k) -and $m[$k].n) { $nm } })
}
function RollupText($s, [string]$month, $attRows, $marking) {
    $x = RollupData $s $month $attRows
    $out = "Monthly roll-up $($x.month) -- as of $($x.as_of)`n`nEPICS`n"
    foreach ($e in $x.epics) { $out += '  ' + (PadR "$($e.tome) > $($e.epic)" 40) + ' ' + (PadL (DInt $e.pct) 4) + '%  ' + (PadL (DInt $e.done) 4) + '/' + (PadR (DInt $e.total) 4) + " $($x.unit)`n" }
    $out += "`nINTAKE VS DONE (sprints running this month)`n"
    foreach ($y in $x.sprints) { $g = ''; if ($y.intake -gt $y.done) { $g = '  (backlog grew)' }; $out += '  sprint ' + (PadR $y.sprint 4) + " from $($y.start)  intake " + (PadL (DInt $y.intake) 4) + '  done ' + (PadL (DInt $y.done) 4) + "$g`n" }
    if (-not @($x.sprints).Count) { $out += "  no sprints this month`n" }
    $out += "`nBACKLOG AGE (days since intake, tasks still in a backlog)`n"
    foreach ($b in $script:AGE) { $v = @(0, 0); if ($x.age.ContainsKey($b)) { $v = $x.age[$b] }; $out += '  ' + (PadR $b 8) + ' ' + (PadL (DInt $v[0]) 4) + ' tasks  ' + (PadL (DInt $v[1]) 5) + " $($x.unit)`n" }
    $out += "`nATTENDANCE (attendance.csv rows this month)`n"
    $tk = Sorted @(foreach ($k in $x.attendance.Keys) { $x.att_names[$k] })
    foreach ($tm in $tk) { $m = $x.attendance[(CK $tm)]; $out += "  ${tm}: " + (@(foreach ($st in (AttStatuses $m)) { "$st $($m[(CK $st)].n)" }) -join ', ') + "`n" }
    if (-not $x.attendance.Count) { $out += "  no attendance rows this month`n" }
    MarkedText $marking $out
}
function RollupHtml($s, [string]$month, $attRows, $marking) {
    $x = RollupData $s $month $attRows
    $td = 'style="border:1px solid #bbb;padding:3px 8px"'; $tdn = 'style="border:1px solid #bbb;padding:3px 8px;text-align:right"'
    $tab = { param($hdr, $rows, $num)
        "<table style=`"border-collapse:collapse;margin-bottom:12px`"><tr>" + (@(for ($i = 0; $i -lt $hdr.Count; $i++) { $st = $td; if ($num -contains $i) { $st = $tdn }; "<th $st>" + (Hx $hdr[$i]) + '</th>' }) -join '') + "</tr>`n" +
        (@(foreach ($r in $rows) { '<tr>' + (@(for ($i = 0; $i -lt $r.Count; $i++) { $st = $td; if ($num -contains $i) { $st = $tdn }; "<td $st>" + (Hx $r[$i]) + '</td>' }) -join '') + "</tr>`n" }) -join '') + "</table>`n" }
    $html = "<!DOCTYPE html>`n<html><head><meta charset=`"utf-8`"><title>Roll-up $($x.month)</title></head><body style=`"font-family:Segoe UI,Arial,sans-serif;font-size:14px`">`n" + (MarkBannerHtml $marking 'top') + (MarkBlockHtml $marking)
    $html += '<h1 style="font-size:20px">' + (LogoSvg) + "Monthly roll-up $($x.month) <span style=`"color:#666;font-weight:normal`">as of " + (Hx $x.as_of) + "</span></h1>`n"
    $html += "<h2 style=`"font-size:16px`">Epics</h2>`n" + (& $tab @('Tome', 'Epic', 'Done%', 'Done', 'Total') @(foreach ($e in $x.epics) { , @($e.tome, $e.epic, "$($e.pct)%", $e.done, $e.total) }) @(2, 3, 4))
    $html += "<h2 style=`"font-size:16px`">Intake vs done</h2>`n" + (& $tab @('Sprint', 'Started', "Intake $($x.unit)", "Done $($x.unit)", '') @(foreach ($y in $x.sprints) { $g = ''; if ($y.intake -gt $y.done) { $g = 'backlog grew' }; , @($y.sprint, $y.start, $y.intake, $y.done, $g) }) @(2, 3))
    $html += "<h2 style=`"font-size:16px`">Backlog age</h2>`n" + (& $tab @('Days since intake', 'Tasks', $x.unit) @(foreach ($b in $script:AGE) { $v = @(0, 0); if ($x.age.ContainsKey($b)) { $v = $x.age[$b] }; , @($b, $v[0], $v[1]) }) @(1, 2))
    $html += "<h2 style=`"font-size:16px`">Attendance</h2>`n"
    if ($x.attendance.Count) {
        $names = @{}; foreach ($m in $x.attendance.Values) { foreach ($v in $m.Values) { $names[(CK $v.name)] = $v.name } }
        $others = Sorted @(foreach ($v in $names.Values) { if ($script:ATT -cnotcontains $v) { $v } })
        $st = @(foreach ($nm in (@($script:ATT) + @($others))) { $k = CK $nm; $any = $false; foreach ($m in $x.attendance.Values) { if ($m.ContainsKey($k) -and $m[$k].n) { $any = $true } }; if ($any) { $nm } })
        $tk = Sorted @(foreach ($k in $x.attendance.Keys) { $x.att_names[$k] })
        $html += & $tab (@('Team') + $st) @(foreach ($tm in $tk) { $m = $x.attendance[(CK $tm)]; , (@($tm) + @(foreach ($nm in $st) { $k = CK $nm; if ($m.ContainsKey($k)) { $m[$k].n } else { 0 } })) }) @(1..$st.Count)
    }
    else { $html += "<p style=`"color:#666`">no attendance rows this month</p>`n" }
    $html + (MarkBannerHtml $marking 'bottom') + "</body></html>`n"
}

# ---------------------------------------------------------------- the weekly quad (lib/Quad.pm)
function SortedItems($list) {
    SortWith @($list) { param($a, $b) $pa = 99; if ($null -ne $a.meta['prio']) { $pa = [double]$a.meta['prio'] }; $pb = 99; if ($null -ne $b.meta['prio']) { $pb = [double]$b.meta['prio'] }
        if ($pa -lt $pb) { -1 } elseif ($pa -gt $pb) { 1 } else { [string]::CompareOrdinal($a.id, $b.id) } }
}
function ItemById($s, [string]$id) { $p = $s.items[$id]; if ($p -and $p.id -ceq $id) { $p } else { $null } }   # Perl hash keys are case-exact
function QTag($it, $s) {
    $m = $it.meta
    $sync = @(foreach ($x in (SplitWs $m['sync'])) { if ($x -cne $it.id) { $x } })
    $waiting = @(foreach ($x in $sync) { $p = ItemById $s $x; if ($p -and $p.state -cne 'done') { $x } })
    $tag = 'OPEN'
    if ($it.state -ceq 'done') { if ($waiting.Count) { $tag = 'OPEN' } else { $tag = 'DONE' } }
    elseif ($it.state -ceq 'removed') { $tag = 'DROP' }
    elseif ($it.state -ceq 'backlog') { if ((Str $m['punt']) -ne '') { $tag = 'PUNT' } else { $tag = 'TODO' } }
    elseif ($it.state -ceq 'master') { $tag = 'TODO' }
    elseif ($it.blocked) { $tag = 'WAIT' }
    elseif ($it.hold) { $tag = 'HOLD' }
    $marks = @()
    if ((Str $m['redo']) -ne '' -and $it.state -cne 'done') { $marks += 'REDO' }
    if ((Str $m['pass']) -ne '' -and $it.state -cne 'done') { $marks += 'PASS ' + $m['pass'] }
    if ($sync.Count) { $w = ''; if ($waiting.Count) { $w = ' (waiting on ' + ($waiting -join ' ') + ')' }; $marks += 'SYNC ' + ($sync -join ' ') + $w }
    if ($it.state -ceq 'carryover') { $marks += 'CARRY' }
    $why = $it.blocked
    if ($null -eq $why) { $why = $it.hold }
    if ($null -eq $why -and $tag -ceq 'PUNT') { $why = $m['punt'] }
    if ($null -eq $why -and (Str $m['redo']) -ne '' -and $it.state -cne 'done') { $why = $m['redo'] }
    @{ tag = $tag; marks = $marks; why = $why }
}
function DoneOn($it) { $d = $null; foreach ($h in $it.history) { if ($h.account -cmatch ':Done$' -and $h.points -gt 0) { $d = $h.date } }; $d }
function Redone($it) { $n = 0; foreach ($h in $it.history) { if ($h.account -cmatch ':Done$' -and $h.points -gt 0) { $n++ } }; $n -gt 1 }
function Carried($it, $by) { $n = 0; foreach ($h in $it.history) { if ($h.account -cmatch ':Carryover$' -and $h.points -gt 0 -and ($null -eq $by -or -not (SGt $h.date $by))) { $n++ } }; $n }
function QuadData($s, [string]$tname, $prev, $prev2) {
    $asOf = $s.today
    $since = AddDays $asOf -7
    if ($null -eq $prev) { $prev = LoadScrum $s.file $since $since }
    $cur = $s.current
    $sum = SprintSummary $s $cur
    $inTeam = { param($i) (-not $tname) -or ((Str $i.team) -ceq $tname) }
    $row = { param($it) $g = QTag $it $s
        @{ id = $it.id; title = $it.title; owner = $it.owner; team = $it.team; pts = $it.points; prio = $it.meta['prio']; tag = $g.tag; marks = $g.marks; why = $g.why } }
    # 1. technical priorities: the sprint, then the TODO list (punted first), capped
    $pri = @()
    if ($null -ne $cur) { foreach ($i in (SortedItems @(foreach ($i in (AllItems $s)) { if ($null -ne $i.sprint -and [int]$i.sprint -eq [int]$cur -and (& $inTeam $i)) { $i } }))) { $pri += , (& $row $i) } }
    $todo = @(foreach ($i in (SortedItems @(foreach ($i in (AllItems $s)) { if ($i.state -ceq 'backlog' -and (& $inTeam $i)) { $i } }))) { , (& $row $i) })
    $todo = @(@($todo | Where-Object { $_.tag -ceq 'PUNT' }) + @($todo | Where-Object { $_.tag -cne 'PUNT' }))
    $todoMore = 0; if ($todo.Count -gt 10) { $todoMore = $todo.Count - 10 }
    if ($todo.Count) { $pri += @($todo | Select-Object -First 10) }

    # 2. watch items
    $watch = @()
    foreach ($it in (Blocked $s '')) {
        if (-not (& $inTeam $it)) { continue }
        $days = 0; if ($null -ne $it.blocked_since) { $days = DaysBetween $it.blocked_since $asOf }
        $k = 'WI'; if ($days -gt 3) { $k = 'PM' }
        $tx = "blocked $days day$(Plural $days): $($it.blocked)"; if ($days -gt 5) { $tx += " -- over 5 days: the architect's" }
        $watch += @{ kind = $k; id = $it.id; team = $it.team; owner = $it.owner; days = $days; text = $tx }
    }
    foreach ($p in $pri) { if ($p.tag -ceq 'HOLD') { $watch += @{ kind = 'WI'; id = $p.id; team = $p.team; owner = $p.owner; days = 0; text = "on hold: $($p.why)" } } }
    foreach ($p in $pri) { if ($p.tag -ceq 'PUNT') { $watch += @{ kind = 'WI'; id = $p.id; team = $p.team; owner = $p.owner; days = 0; text = "punted, needs replanning: $($p.why)" } } }
    foreach ($p in $pri) { if ($p.marks -ccontains 'REDO') { $watch += @{ kind = 'WI'; id = $p.id; team = $p.team; owner = $p.owner; days = 0; text = "rework after the demo: $($p.why)" } } }
    foreach ($p in $pri) { if (-not $p.owner -and @($p.marks | Where-Object { $_ -cmatch '^PASS' }).Count) { $watch += @{ kind = 'WI'; id = $p.id; team = $p.team; owner = $null; days = 0; text = 'passed in, no owner yet' } } }
    foreach ($p in $pri) { if ($p.marks -ccontains 'CARRY') { $watch += @{ kind = 'WI'; id = $p.id; team = $p.team; owner = $p.owner; days = 0; text = 'carried to next sprint' } } }
    foreach ($i in (Unassigned $s '')) { if ((& $inTeam $i) -and -not $i.meta['pass']) { $watch += @{ kind = 'WI'; id = $i.id; team = $i.team; owner = $null; days = 0; text = 'committed, no owner' } } }
    foreach ($t in (SortedKeys $sum.teams)) {
        if ($tname -and $t -cne $tname) { continue }
        $l = $sum.teams[$t].load
        if ($null -ne $l -and $l -gt 100) { $k = 'WI'; if ($l -gt 110) { $k = 'PM' }; $watch += @{ kind = $k; id = ''; team = $t; owner = $null; days = 0; text = "$t at $l% of capacity" } }
    }
    $watch = SortWith $watch { param($a, $b) $pa = [int]($a.kind -ceq 'PM'); $pb = [int]($b.kind -ceq 'PM')
        if ($pb -ne $pa) { return $pb - $pa }; if ($b.days -ne $a.days) { return $b.days - $a.days }; [string]::CompareOrdinal((Str $a.id), (Str $b.id)) }

    # 3. schedule milestones: epics by ETA, 30/60/90 days out, against last week's ETA
    $rm = Roadmap $s; $prm = Roadmap $prev
    $prevEnd = @{}; foreach ($e in $prm.epics) { $prevEnd[(CK "$($e.tome)`t$($e.epic)")] = $e.end }
    $ms = @{ '30' = @(); '60' = @(); '90' = @() }; $msMore = @{}
    foreach ($e in $rm.epics) {
        if (-not ($e.remaining -gt 0)) { continue }
        if ($tname -and -not (@($e.teams) -ccontains $tname)) { continue }
        $eta = SprintEndDate $s $e.end
        $days = $null; if ($null -ne $eta) { $days = DaysBetween $asOf $eta }
        $pe = $prevEnd[(CK "$($e.tome)`t$($e.epic)")]
        $shift = $null; if ($null -ne $e.end -and $null -ne $pe) { $shift = [int]$e.end - [int]$pe }
        $trend = 'new'; if ($null -ne $shift) { if ($shift -gt 0) { $trend = 'pushed' } elseif ($shift -lt 0) { $trend = 'pulled' } else { $trend = 'same' } }
        $sev = 'good'
        if ($e.blocked -ge 2 -or ($null -ne $shift -and $shift -ge 2)) { $sev = 'critical' } elseif ($e.blocked -or ($null -ne $shift -and $shift -gt 0)) { $sev = 'warning' }
        $r = @{ tome = $e.tome; epic = $e.epic; teams = $e.teams; pct = $e.pct; remaining = $e.remaining; end = $e.end; eta = $eta; days = $days; shift = $shift; trend = $trend; severity = $sev; blocked = $e.blocked }
        $h = $null; if ($null -ne $days) { foreach ($hz in @(30, 60, 90)) { if ($days -le $hz) { $h = $hz; break } } }
        if ($null -ne $h) { $ms["$h"] += $r }
    }
    foreach ($h in @('30', '60', '90')) {
        $r = SortWith $ms[$h] { param($a, $b) $cv = [string]::CompareOrdinal((Str $a.eta), (Str $b.eta)); if ($cv) { return $cv }
            if ($b.remaining -gt $a.remaining) { return 1 }; if ($b.remaining -lt $a.remaining) { return -1 }; [string]::CompareOrdinal($a.epic, $b.epic) }
        $r = @(for ($k = 0; $k -lt $r.Count; $k++) { $cv = @{}; foreach ($key in $r[$k].Keys) { $cv[$key] = $r[$k][$key] }; $cv.priority = $k + 1; $cv })
        $msMore[$h] = 0; if ($r.Count -gt 3) { $msMore[$h] = $r.Count - 3 }
        $ms[$h] = @($r | Select-Object -First 3)
    }

    # 4. accomplishments: done in the last week
    $acc = @(); $slipped = @()
    foreach ($it in (SortedItems @(foreach ($i in (AllItems $s)) { if ((& $inTeam $i) -and $i.state -ceq 'done') { $i } }))) {
        $date = DoneOn $it; if (-not $date) { continue }
        $group = @(foreach ($x in (SplitWs $it.meta['sync'])) { if ($x -cne $it.id) { $p = ItemById $s $x; if ($p) { $p } } })
        if (@($group | Where-Object { $_.state -cne 'done' }).Count) { continue }
        if ($group.Count) { $date = MaxOf (@($date) + @(foreach ($g in $group) { $d = DoneOn $g; if ($null -ne $d) { $d } })) }
        if (-not ((SGt $date $since) -and -not (SGt $date $asOf))) { continue }
        $carried = Carried $it $date; $redone = Redone $it
        $lw = ''; if ($redone) { $lw = 'rework' } elseif ($carried) { $lw = 'carried over' }
        $acc += @{ id = $it.id; title = $it.title; owner = $it.owner; team = $it.team; pts = $it.points; date = $date; ontime = [int](-not ($carried -or $redone)); late_why = $lw }
    }
    foreach ($p in $pri) {
        if ($p.tag -cnotmatch '^(WAIT|PUNT|HOLD)$') { continue }
        $w = "on hold: $($p.why)"; if ($p.tag -ceq 'WAIT') { $w = "blocked: $($p.why)" } elseif ($p.tag -ceq 'PUNT') { $w = "punted: $($p.why)" }
        $slipped += @{ id = $p.id; title = $p.title; owner = $p.owner; team = $p.team; why = $w }
    }

    # the two metrics
    if ($tname) { $tr = $null; if ($sum.teams.ContainsKey($tname)) { $tr = $sum.teams[$tname] }; $pct = 0; $done = 0; $committed = 0; if ($tr) { $pct = $tr.pct; $done = $tr.done; $committed = $tr.committed } }
    else { $pct = $sum.totals.pct; $done = $sum.totals.done; $committed = $sum.totals.committed }
    $ppct = $null
    if ($null -ne $cur) {
        $psum = SprintSummary $prev $cur
        if ($psum.sprint) { if ($tname) { if ($psum.teams.ContainsKey($tname)) { $ppct = $psum.teams[$tname].pct } } else { $ppct = $psum.totals.pct } }
    }
    $trend = 'new'; if ($null -ne $ppct) { if ($pct -gt $ppct) { $trend = 'improving' } elseif ($pct -lt $ppct) { $trend = 'degrading' } else { $trend = 'same' } }
    if ($trend -ceq 'degrading' -and $prev2) {
        $p2 = SprintSummary $prev2 $cur; $pp2 = $null
        if ($p2.sprint) { if ($tname) { if ($p2.teams.ContainsKey($tname)) { $pp2 = $p2.teams[$tname].pct } } else { $pp2 = $p2.totals.pct } }
        if ($null -ne $pp2 -and $ppct -lt $pp2) { $trend = 'degrading2' }
    }
    $allDone = @(foreach ($i in (AllItems $s)) { if ($null -ne $cur -and $i.state -ceq 'done' -and $null -ne $i.sprint -and [int]$i.sprint -eq [int]$cur -and (& $inTeam $i)) { $i } })
    $sprintOntime = @(foreach ($i in $allDone) { if (-not (Carried $i $null) -and -not (Redone $i)) { 1 } }).Count
    $u = $s.unit; if ($null -eq $u) { $u = 'SP' }
    $prate = PuntRate $s $tname
    $tv = $null; if ($tname) { $tv = $tname }
    @{ as_of = $asOf; since = $since; team = $tv; sprint = $cur; file = $s.file; unit = $u
        priorities = $pri; todo_more = $todoMore; watch = $watch; milestones = $ms; milestones_more = $msMore
        horizons = @(30, 60, 90); accomplishments = $acc; slipped = $slipped; punt_rate = $prate; punt_warn = 20
        metrics = @{ sprint = @{ pct = $pct; done = $done; committed = $committed; prev_pct = $ppct; trend = $trend; punted = @($pri | Where-Object { $_.tag -ceq 'PUNT' }).Count }
            ontime = @{ week_ontime = @($acc | Where-Object { $_.ontime }).Count; week_total = $acc.Count; sprint_ontime = $sprintOntime; sprint_total = $allDone.Count } }
    }
}
function OntimeLow($m) { $n = $m.ontime.sprint_ontime; $d = $m.ontime.sprint_total; [int]($d -and 100 * $n / $d -lt 80) }
$script:ARROW = @{ pushed = '->'; pulled = '<-'; same = '='; new = '+' }
function QuadText($q, $marking) {
    $m = $q.metrics
    $tn = ''; if ($q.team) { $tn = " $($q.team)" }
    $sp = '-'; if ($null -ne $q.sprint) { $sp = $q.sprint }
    $out = "Weekly status$tn -- as of $($q.as_of) (sprint $sp)`n"
    $tr = $m.sprint.trend; if ($tr -ceq 'degrading2') { $tr = 'DEGRADING two weeks running' }
    $was = ''; if ($null -ne $m.sprint.prev_pct) { $was = " (was $($m.sprint.prev_pct)%)" }
    $pu = ''; if ($m.sprint.punted) { $pu = ", $($m.sprint.punted) punted" }
    $late = ''; if (OntimeLow $m) { $late = '  ! under 80%' }
    $out += "Sprint progress $(DInt $m.sprint.pct)% ($(DInt $m.sprint.done)/$(DInt $m.sprint.committed) $($q.unit)) $tr$was$pu   On-time delivery: $($m.ontime.week_ontime)/$($m.ontime.week_total) this week, $($m.ontime.sprint_ontime)/$($m.ontime.sprint_total) this sprint$late`n`n"
    $out += "TECHNICAL PRIORITIES`n"
    foreach ($p in $q.priorities) {
        $mk = ''; if (@($p.marks).Count) { $mk = '  [' + ($p.marks -join ', ') + ']' }
        $ow = $p.owner; if ($null -eq $ow) { $ow = '-' }
        $out += '  ' + (PadR $p.tag 5) + ' ' + (PadR $p.id 10) + ' ' + (PadL $p.pts 3) + '  ' + (PadR (Sub30 $p.title) 30) + " $ow$mk`n"
    }
    if (-not @($q.priorities).Count) { $out += "  (nothing in the sprint or on the TODO list)`n" }
    if ($q.todo_more) { $out += "  (+$($q.todo_more) more on the TODO list)`n" }
    $out += "`nWATCH ITEMS / PM HELP NEEDED`n"
    foreach ($w in $q.watch) { $idt = $w.id; if (-not $idt) { $idt = $w.team }; $out += "  ($($w.kind)) " + (PadR $idt 10) + " $($w.text)`n" }
    if (-not @($q.watch).Count) { $out += "  none`n" }
    $out += "`nSCHEDULE MILESTONES`n"
    foreach ($h in @('30', '60', '90')) {
        $out += "  $h days out`n"
        foreach ($e in $q.milestones[$h]) { $bl = ''; if ($e.blocked) { $bl = "  BLOCKED $($e.blocked)" }; $out += "    $($e.priority). " + (PadR "$($e.tome) > $($e.epic)" 34) + " $($script:ARROW[$e.trend]) " + (PadL (DInt $e.pct) 3) + "%  ETA $($e.eta)$bl`n" }
        if (-not @($q.milestones[$h]).Count) { $out += "    -`n" }
        if ($q.milestones_more[$h]) { $out += "    (+$($q.milestones_more[$h]) more)`n" }
    }
    $out += "`nACCOMPLISHMENTS (since $($q.since))`n"
    foreach ($a in $q.accomplishments) {
        $v = 'x'; if ($a.ontime) { $v = 'v' }; $ow = $a.owner; if ($null -eq $ow) { $ow = '-' }; $lw = ''; if ($a.late_why) { $lw = "  ($($a.late_why))" }
        $out += "  $v " + (PadR $a.id 10) + ' ' + (PadL $a.pts 3) + '  ' + (PadR (Sub30 $a.title) 30) + " $ow$lw`n"
    }
    if (-not @($q.accomplishments).Count) { $out += "  none`n" }
    foreach ($x in $q.slipped) { $out += '  ! ' + (PadR $x.id 10) + " $($x.why)`n" }
    $out += "`nPUNT RATE (tasks punted back to TODO / tasks committed, last 4 sprints)`n"
    foreach ($r in $q.punt_rate) { $w = ''; if ($r.warn) { $w = '  ! two sprints running' }; $out += '  sprint ' + (PadR $r.sprint 4) + ' ' + (PadR $r.team 12) + ' ' + (PadL $r.punted 3) + ' / ' + (PadR $r.committed 3) + ' ' + (PadL $r.rate 3) + "%$w`n" }
    if (-not @($q.punt_rate).Count) { $out += "  no sprints yet`n" }
    $out += "`nLegend: v on time  x late (carried over, or rework after the demo)  ! slipped   -> pushed right  <- pulled left  = no change  + new`n"
    MarkedText $marking $out
}
$script:QCSS = @'
:root{--navy:#27235d;--gold:#e6af22;--olive:#6b7436;--red:#d6292e;--grey:#808082;--lgrey:#e4e4e7;--ink:#0b0b0b;--good:#0ca30c;--warn:#c98500}
body{font-family:"Segoe UI",Calibri,Arial,sans-serif;font-size:11.5px;color:var(--ink);background:#fff;margin:0;padding:10px 14px}
h1{font-size:16px;color:var(--navy);margin:0;border-bottom:3px solid var(--gold);padding-bottom:3px;display:flex;justify-content:space-between;align-items:baseline}
h1 .muted{font-size:11px;font-weight:400}
.metrics{display:flex;gap:18px;margin:6px 0 8px;font-size:11px}.metrics b{font-size:14px;color:var(--navy)}
.quad{display:grid;grid-template-columns:1fr 1fr;gap:8px}
.q{border:1px solid var(--lgrey);border-top:4px solid var(--navy);border-radius:4px;padding:6px 8px;min-height:180px}
.q h2{font-size:12px;margin:0 0 4px;color:var(--navy);text-transform:uppercase;letter-spacing:.03em}
.q h3{font-size:11px;margin:6px 0 2px;color:var(--olive)}
table{border-collapse:collapse;width:100%}td,th{padding:1px 4px;vertical-align:top;text-align:left;border-bottom:1px solid #f0f0f2}th{color:var(--grey);font-weight:600;font-size:10px}
td.n{text-align:right;white-space:nowrap}
.tag{display:inline-block;min-width:38px;text-align:center;border-radius:3px;padding:0 4px;font-size:10px;font-weight:700;color:#fff;background:var(--grey)}
.tag.DONE{background:var(--good)}.tag.OPEN{background:var(--navy)}.tag.WAIT{background:var(--red)}.tag.HOLD{background:var(--warn)}.tag.PUNT{background:var(--red)}.tag.DROP{background:#555}.tag.TODO{background:var(--grey)}
.mark{display:inline-block;border:1px solid var(--olive);color:var(--olive);border-radius:3px;padding:0 3px;font-size:9px;margin-left:2px}
.kind{font-weight:700}.kind.PM{color:var(--red)}.kind.WI{color:var(--warn)}
.sev.critical{color:var(--red);font-weight:700}.sev.warning{color:var(--warn);font-weight:700}.sev.good{color:var(--good)}
.ok{color:var(--good);font-weight:700}.late{color:var(--red);font-weight:700}.slip{color:var(--warn);font-weight:700}
.legend{margin-top:6px;font-size:9.5px;color:var(--grey)}.muted{color:var(--grey)}
.foot{margin-top:6px;font-size:9.5px;color:var(--grey);display:flex;justify-content:space-between}
.strip{border:1px solid var(--lgrey);border-top:4px solid var(--olive);border-radius:4px;padding:6px 8px;margin-top:8px}.strip h2{font-size:12px;margin:0 0 4px;color:var(--navy);text-transform:uppercase;letter-spacing:.03em}.strip h2 .muted{text-transform:none;letter-spacing:0;font-weight:400}.strip table{width:auto}.strip td.n{padding-left:14px}
.logo{height:16px;width:auto;vertical-align:-3px;margin-right:6px}
@page{size:landscape;margin:10mm}@media print{*{-webkit-print-color-adjust:exact;print-color-adjust:exact}body{padding:0}.q{break-inside:avoid}}
'@
$script:QCSS = ($script:QCSS -replace "`r", '') + "`n"
$script:LEGEND = 'TODO on the backlog &middot; OPEN in the sprint &middot; DONE &middot; WAIT blocked outside the team &middot; HOLD interrupted &middot; PUNT too hard as written, back to TODO &middot; DROP should not be done &middot; REDO the demo found it wrong &middot; PASS moved to the right team &middot; SYNC shared DONE across teams'
function QuadHtml($q, $marking) {
    $m = $q.metrics
    $arrowHtml = @{ pushed = '&#8594; pushed right'; pulled = '&#8592; pulled left'; same = '= no change'; new = '+ new' }
    $trend = @{ improving = '&#8599; improving'; degrading = '&#8600; degrading'; degrading2 = '<span class=late>&#8600; degrading two weeks running</span>'; same = '&#8594; no change'; new = 'first week' }
    $html = "<!DOCTYPE html>`n<html><head><meta charset=`"utf-8`"><title>Weekly status</title><style>$($script:QCSS)</style></head><body>`n"
    $html += (MarkBannerHtml $marking 'top') + (MarkBlockHtml $marking)
    $tn = ''; if ($q.team) { $tn = ' &middot; ' + (Hx $q.team) }
    $sp = ''; if ($null -ne $q.sprint) { $sp = " &middot; sprint $($q.sprint)" }
    $html += '<h1>' + (LogoSvg) + 'Weekly Status' + $tn + ' <span class=muted>as of ' + (Hx $q.as_of) + $sp + "</span></h1>`n"
    $was = ''; if ($null -ne $m.sprint.prev_pct) { $was = " (was $($m.sprint.prev_pct)%)" }
    $pu = ''; if ($m.sprint.punted) { $pu = " <span class=late>$($m.sprint.punted) punted</span>" }
    $lc = ''; $lt = ''; if (OntimeLow $m) { $lc = ' class=late'; $lt = ' (under 80%)' }
    $html += "<div class=metrics><span>Sprint progress <b>$(DInt $m.sprint.pct)%</b> $(DInt $m.sprint.done)/$(DInt $m.sprint.committed) $(Hx $q.unit) <span class=muted>$($trend[$m.sprint.trend])$was</span>$pu</span><span$lc>On-time delivery <b>$($m.ontime.week_ontime)/$($m.ontime.week_total)</b> this week <span class=muted>&middot; $($m.ontime.sprint_ontime)/$($m.ontime.sprint_total) this sprint</span>$lt</span></div>`n"
    $html += "<div class=quad>`n"
    $html += "<div class=q><h2>Technical Priorities</h2>`n"
    if (@($q.priorities).Count) {
        $rows = @($q.priorities)
        $done = @(); if ($rows.Count -gt 12) { $done = @($rows | Where-Object { $_.tag -ceq 'DONE' }) }
        if ($done.Count) { $rows = @($rows | Where-Object { $_.tag -cne 'DONE' }) }
        $html += "<table><tr><th></th><th>ID</th><th>Task</th><th>Owner</th><th class=n>$($q.unit)</th></tr>`n"
        foreach ($p in $rows) {
            $why = ''; if ($p.why) { $why = ' <span class=muted>' + (Hx $p.why) + '</span>' }
            $ow = $p.owner; if ($null -eq $ow) { $ow = '-' }
            $html += "<tr><td><span class=`"tag $($p.tag)`">$($p.tag)</span></td><td>" + (Hx $p.id) + '</td><td>' + (Hx $p.title) + (@(foreach ($x in $p.marks) { '<span class=mark>' + (Hx $x) + '</span>' }) -join '') + $why + '</td><td>' + (Hx $ow) + '</td><td class=n>' + (Hx $p.pts) + "</td></tr>`n"
        }
        if ($done.Count) { $html += '<tr><td><span class="tag DONE">DONE</span></td><td colspan=4><span class=muted>' + $done.Count + ' done: </span>' + (@(foreach ($p in $done) { Hx $p.id }) -join ', ') + "</td></tr>`n" }
        $html += "</table>`n"
        if ($q.todo_more) { $html += "<p class=muted>+$($q.todo_more) more on the TODO list</p>`n" }
    }
    else { $html += "<p class=muted>nothing in the sprint or on the TODO list</p>`n" }
    $html += "<div class=legend>$($script:LEGEND)</div></div>`n"
    $html += "<div class=q><h2>Watch Items / PM Help Needed</h2>`n"
    if (@($q.watch).Count) {
        $html += "<table><tr><th></th><th>ID</th><th>Team</th><th>Owner</th><th>Item</th></tr>`n"
        foreach ($w in $q.watch) { $ow = $w.owner; if ($null -eq $ow) { $ow = '-' }; $html += "<tr><td><span class=`"kind $($w.kind)`">($($w.kind))</span></td><td>" + (Hx $w.id) + '</td><td>' + (Hx $w.team) + '</td><td>' + (Hx $ow) + '</td><td>' + (Hx $w.text) + "</td></tr>`n" }
        $html += "</table>`n"
    }
    else { $html += "<p class=muted>nothing to watch</p>`n" }
    $html += "<div class=legend>(PM) SWAT: the program manager needs to help remove a blocker &middot; (WI) SWAT: the program manager needs to be aware</div></div>`n"
    $html += "<div class=q><h2>Schedule Milestones</h2>`n"
    foreach ($hz in @('30', '60', '90')) {
        $html += "<h3>$hz days out</h3>"
        if (@($q.milestones[$hz]).Count) {
            $html += '<table>'
            foreach ($e in $q.milestones[$hz]) { $bl = ''; if ($e.blocked) { $bl = "<span class=late>$($e.blocked) blocked</span>" }
                $html += "<tr><td class=n>$($e.priority).</td><td>" + (Hx $e.tome) + ' <span class=muted>&gt;</span> ' + (Hx $e.epic) + "</td><td class=`"sev $($e.severity)`">$($arrowHtml[$e.trend])</td><td class=n>$(DInt $e.pct)%</td><td class=n>ETA " + (Hx $e.eta) + "</td><td>$bl</td></tr>`n" }
            $html += '</table>'
        }
        else { $html += '<p class=muted>-</p>' }
        if ($q.milestones_more[$hz]) { $html += "<p class=muted>+$($q.milestones_more[$hz]) more epics in this window</p>" }
    }
    $html += "<div class=legend>ETA = remaining &divide; the owning teams' velocity, against last week's ETA. Red: pushed 2+ sprints or 2+ blockers; amber: pushed or blocked.</div></div>`n"
    $html += "<div class=q><h2>Accomplishments <span class=muted>since $($q.since)</span></h2>`n"
    if (@($q.accomplishments).Count -or @($q.slipped).Count) {
        $html += '<table>'
        foreach ($a in $q.accomplishments) {
            $cl = 'late'; $sym = '&#10007;'; if ($a.ontime) { $cl = 'ok'; $sym = '&#10003;' }
            $lw = ''; if ($a.late_why) { $lw = ' <span class=muted>' + (Hx $a.late_why) + '</span>' }
            $ow = $a.owner; if ($null -eq $ow) { $ow = '-' }
            $html += "<tr><td class=`"$cl`">$sym</td><td>" + (Hx $a.id) + '</td><td>' + (Hx $a.title) + $lw + '</td><td>' + (Hx $ow) + '</td><td class=n>' + (Hx $a.pts) + "</td></tr>`n"
        }
        foreach ($x in $q.slipped) { $html += '<tr><td class=slip>!</td><td>' + (Hx $x.id) + '</td><td colspan=3>' + (Hx $x.title) + ' <span class=muted>' + (Hx $x.why) + "</span></td></tr>`n" }
        $html += '</table>'
    }
    else { $html += "<p class=muted>nothing finished this week</p>`n" }
    $html += "<div class=legend>&#10003; delivered on time &middot; &#10007; delivered late (carried over, or rework after the demo) &middot; ! priority that slipped this week</div></div>`n"
    $html += "</div>`n"
    $html += "<div class=strip><h2>Punt rate <span class=muted>tasks punted back to TODO / tasks committed, last 4 sprints; over 20% two sprints running means tasks arrive under-specified</span></h2>`n"
    if (@($q.punt_rate).Count) {
        $sps = Nub @(foreach ($r in $q.punt_rate) { $r.sprint })
        $teams = Nub @(foreach ($r in $q.punt_rate) { $r.team })
        $cell = @{}; foreach ($r in $q.punt_rate) { $cell[(CK "$($r.sprint)`t$($r.team)")] = $r }
        $html += '<table><tr><th>Team</th>' + (@(foreach ($x in $sps) { "<th class=n>Sprint $x</th>" }) -join '') + "</tr>`n"
        foreach ($t in $teams) {
            $html += '<tr><td>' + (Hx $t) + '</td>' + (@(foreach ($x in $sps) { $cv = $cell[(CK "$x`t$t")]
                        if ($cv) { $lt2 = ''; if ($cv.warn) { $lt2 = ' late' }; "<td class=`"n$lt2`">$($cv.punted) / $($cv.committed) &middot; $($cv.rate)%</td>" } else { '<td class=n>-</td>' } }) -join '') + "</tr>`n"
        }
        $html += "</table>`n"
    }
    else { $html += "<p class=muted>no sprints yet</p>`n" }
    $html += "</div>`n<div class=foot><span>Source: " + (Hx $q.file) + "</span><span>Sprint Progress, On-Time Delivery and Punt Rate are all read off this page</span></div>`n"
    $html + (MarkBannerHtml $marking 'bottom') + "</body></html>`n"
}

# ---------------------------------------------------------------- the people file (lib/Roster.pm)
$script:RFIELDS = @('name', 'email', 'team', 'role', 'org')
function ReadRoster([string]$file) {
    $text = ReadText $file; if ($null -eq $text) { return , @() }
    $lines = @($text -csplit "`n"); if ($lines.Count -and $lines[$lines.Count - 1] -eq '') { $lines = @($lines | Select-Object -First ($lines.Count - 1)) }
    $r = @(); $no = 0
    foreach ($l in $lines) {
        $no++
        if ($l.Length -and $l[0] -eq [char]0xFEFF) { $l = $l.Substring(1) }
        if ($l -cmatch '^\s*(#|$)') { continue }
        if ($l.Contains('|')) { $f = @($l -csplit '\s*\|\s*', 5) } else { $f = @($l -csplit '\s*,\s*', 5) }
        $f = @(foreach ($x in $f) { $x -creplace '^\s+|\s+$', '' })
        if (-not $f[0]) { continue }
        $g = @(for ($i = 0; $i -lt 5; $i++) { if ($i -lt $f.Count) { $f[$i] } else { '' } })
        $r += @{ name = $g[0]; email = $g[1]; team = $g[2]; role = $g[3]; org = $g[4]; line = $no }
    }
    , $r
}
function WriteRoster([string]$file, $people) {
    $p = SortWith @($people) { param($a, $b) $cv = [string]::CompareOrdinal((Str $a.team), (Str $b.team)); if ($cv) { $cv } else { [string]::CompareOrdinal($a.name, $b.name) } }
    $w = @(foreach ($k in $script:RFIELDS) { $m = $k.Length; foreach ($x in $p) { $l = (Str $x[$k]).Length; if ($l -gt $m) { $m = $l } }; $m })
    $out = '# ' + (@(for ($i = 0; $i -lt 5; $i++) { (PadR $script:RFIELDS[$i] $w[$i]) }) -join ' | ') + "`n"
    foreach ($x in $p) { $out += '  ' + (@(for ($i = 0; $i -lt 5; $i++) { (PadR $x[$script:RFIELDS[$i]] $w[$i]) }) -join ' | ') + "`n" }
    WriteUtf8 $file $out
    $p.Count
}
function RosterByTeam($r) {
    $t = @{}; $names = @{}
    foreach ($x in $r) { $tm = $x.team; if (-not $tm) { $tm = '?' }; $k = CK $tm; if (-not $t.ContainsKey($k)) { $t[$k] = @(); $names[$k] = $tm }; $t[$k] += $x }
    @{ by = $t; names = $names }
}
function RosterCheck($s, $r) {
    $p = @()
    $ros = @{}; foreach ($x in $r) { $ros[(CK $x.name)] = $x }
    $m = Members $s ''
    $mk = @{}; foreach ($k in $m.Keys) { $mk[(CK $k)] = $m[$k] }
    foreach ($who in (SortedKeys $m)) {
        $x = $ros[(CK $who)]
        if (-not $x) { $p += @{ level = 'warn'; text = "$who owns tasks in the journal but is not in roster.txt (name must match the Teams display name)" }; continue }
        $jt = Str $m[$who].team
        if ($x.team -and $jt -and $x.team -cne $jt) { $p += @{ level = 'warn'; text = "${who}: roster team '$($x.team)' differs from the journal's '$jt'" } }
    }
    foreach ($x in $r) {
        if (-not $mk.ContainsKey((CK $x.name))) { $fine = ''; if ($x.role -match 'lead|architect|manager|owner') { $fine = " (fine for a $($x.role))" }; $p += @{ level = 'info'; text = "$($x.name) is in roster.txt but owns no task in the journal$fine" } }
        if ($x.email -cnotmatch '@') { $p += @{ level = 'warn'; text = "$($x.name): no e-mail (1:1 links and the invite will skip them)" } }
        if (-not $x.team) { $p += @{ level = 'info'; text = "$($x.name): no team" } }
    }
    $seen = @{}
    foreach ($x in $r) { $k = CK $x.name; if ($seen.ContainsKey($k)) { $p += @{ level = 'warn'; text = "$($x.name) appears twice (lines $($seen[$k]) and $($x.line))" } } else { $seen[$k] = $x.line } }
    , $p
}
function RosterText($r) {
    $bt = RosterByTeam $r
    $out = ''
    foreach ($t in (Sorted @(foreach ($k in $bt.by.Keys) { $bt.names[$k] }))) {
        $ppl = SortWith @($bt.by[(CK $t)]) { param($a, $b) [string]::CompareOrdinal($a.name, $b.name) }
        $out += "== $t ($($ppl.Count))`n"
        foreach ($x in $ppl) {
            $e = $x.email; if (-not $e) { $e = '-' }; $ro = $x.role; if (-not $ro) { $ro = '-' }; $or = $x.org; if (-not $or) { $or = '-' }
            $out += '  ' + (PadR $x.name 26) + ' ' + (PadR $e 34) + ' ' + (PadR $ro 22) + " $or`n"
        }
    }
    $out
}

# ================================================================ what daily.pl hands the checks (_health_opts)
function HealthOpts($s, $prev) {
    $asOf = $script:Today
    if ($null -eq $prev) { $prev = LoadScrum $script:C.journal (AddDays $asOf -7) (AddDays $asOf -7) }
    $prev2 = LoadScrum $script:C.journal (AddDays $asOf -14) (AddDays $asOf -14)
    $start = $asOf
    if ($null -ne $s.current) { $sp = SprintSpan $s; if ($sp.ContainsKey("$($s.current)") -and $sp["$($s.current)"].start) { $start = $sp["$($s.current)"].start } }
    $rounds = @()
    foreach ($f in (ListDir $script:C.standups)) {
        if ($f -cnotmatch '^(\d{4}-\d{2}-\d{2}).*-chat\.txt$') { continue }
        $d = $Matches[1]
        if ((SLt $d $start) -or (SGt $d $asOf)) { continue }
        $text = ReadText "$($script:C.standups)/$f"; if ($null -eq $text) { continue }
        $tl = EstTallies (ParseChat $text)
        foreach ($x in $tl) { $rounds += , $x }
    }
    $days = @{}; $rosters = @{}
    $tomorrow = AddDays $asOf 1
    foreach ($t in $s.teams) {
        $h = AnswerHistory $script:C.standups $t $tomorrow 3
        if (-not @($h).Count -or $h[0].date -cne $asOf) { continue }
        $days[$t] = $h; $rosters[$t] = RosterOf $s $t
    }
    $attRows = $script:C.attendance; if (-not $attRows) { $attRows = 'attendance.csv' }
    @{ prev = $prev; prev2 = $prev2; est_rounds = $rounds; attendance = (ReadAttendance $attRows); answer_days = $days; rosters = $rosters }
}
$script:CSV_ALL = @('items', 'sprints', 'epics', 'intake', 'health')
function HealthCsv($s, $o) { $sig = Signals $s $o; CsvText @('level', 'metric', 'team', 'text') @(foreach ($g in $sig) { , @($g.level, $g.metric, $g.team, $g.text) }) }
function MoreCsv($s, [string]$what, $o) { if ($what -ceq 'health') { HealthCsv $s $o } elseif ($script:CSV_TABLES -ccontains $what) { CsvTable $s $what } else { throw "csv: unknown table '$what' ($($script:CSV_ALL -join ' '))`n" } }
function WriteReport([string]$f, [string]$text) { WriteUtf8 $f $text; Write-Output "wrote $f" }

# ================================================================ commands
function MCmd-Health($a) {
    $tm = $null; if (@($a).Count) { $tm = $a[0] } elseif ($script:MORE.team) { $tm = $script:MORE.team }
    $s = Load-S
    $o = HealthOpts $s $null; $o.team = $tm
    $sig = Signals $s $o
    $day = SprintDay $s
    $cur = '-'; if ($null -ne $s.current) { $cur = $s.current }
    $dd = ''; if ($null -ne $day) { $dd = " day $day" }
    $n = @{ red = 0; amber = 0; info = 0 }; foreach ($g in $sig) { $n[$g.level]++ }
    Out-Text "sprint $cur$dd, $($script:Today): $($n.red) red, $($n.amber) amber, $($n.info) info`n"
    if (@($sig).Count) { Out-Text (HealthText $sig $true) } else { Out-Text "every metric is inside its threshold`n" }
    if ($n.red) { $script:RC = 1 }
}
function MCmd-Review($a) {
    $s = Load-S
    $n = $s.current; if (@($a).Count) { $n = $a[0] }
    if ($null -eq $n) { Out-Text "no sprint yet`n"; $script:RC = 1; return }
    EnsureDir $script:C.reports
    $txt = SprintReportText $s $n $script:C
    Out-Text $txt
    WriteReport "$($script:C.reports)/sprint-$n-report.txt" $txt
    WriteReport "$($script:C.reports)/sprint-$n-report.html" (SprintReportHtml $s $n $script:C)
}
function MCmd-Rollup($a) {
    $month = $script:Today.Substring(0, 7); if (@($a).Count) { $month = $a[0] }
    if ($month -cnotmatch '^\d{4}-\d{2}$') { Out-Err "usage: daily.pl rollup [YYYY-MM]`n"; $script:RC = 2; return }
    $s = Load-S
    $f = $script:C.attendance; if (-not $f) { $f = 'attendance.csv' }
    $attRows = ReadAttendance $f
    EnsureDir $script:C.reports
    $txt = RollupText $s $month $attRows $script:C
    Out-Text $txt
    WriteReport "$($script:C.reports)/$month-rollup.txt" $txt
    WriteReport "$($script:C.reports)/$month-rollup.html" (RollupHtml $s $month $attRows $script:C)
}
function MCmd-Csv($a) {
    $what = $null; if (@($a).Count) { $what = $a[0] }
    $s = Load-S
    $o = HealthOpts $s $null
    if ($what) { try { $t = MoreCsv $s $what $o } catch { Out-Err $_.Exception.Message; $script:RC = 2; return }; Out-Text ($t -replace "`r", ''); return }
    EnsureDir $script:C.reports
    foreach ($w in $script:CSV_ALL) { WriteReport "$($script:C.reports)/$w.csv" ([string][char]0xFEFF + (MoreCsv $s $w $o)) }
}
function MCmd-Quad($a) {
    $tm = $null; if (@($a).Count) { $tm = $a[0] } elseif ($script:MORE.team) { $tm = $script:MORE.team }
    $s = Load-S
    Out-Text (QuadText (QuadData $s $tm $null $null) $script:C)
}
function MCmd-Roster($a) {
    $r = ReadRoster 'roster.txt'
    if (@($a).Count -and $a[0] -ceq 'add') {
        $v = @(for ($i = 0; $i -lt 6; $i++) { if ($i -lt @($a).Count) { $a[$i] } else { $null } })
        $name = $v[1]
        if (-not $name) { Out-Err "usage: daily.pl roster add `"Name`" email Team `"Role`" `"Org`"`n"; $script:RC = 255; return }   # Perl dies: exit 255
        $x = $null; foreach ($y in $r) { if ($y.name -ceq $name) { $x = $y; break } }
        $vals = @{ email = $v[2]; team = $v[3]; role = $v[4]; org = $v[5] }
        if ($x) { foreach ($k in @('email', 'team', 'role', 'org')) { if ($null -ne $vals[$k]) { $x[$k] = $vals[$k] } }; Out-Text "updated $name`n" }
        else { $nw = @{ name = $name }; foreach ($k in @('email', 'team', 'role', 'org')) { $val = $vals[$k]; if ($null -eq $val) { $val = '' }; $nw[$k] = $val }; $r = @($r) + @($nw); Out-Text "added $name`n" }
        [void](WriteRoster 'roster.txt' $r)
        return
    }
    if (-not @($r).Count) {
        if (Test-Path -LiteralPath 'roster.txt') { Write-Output 'roster.txt has nobody in it yet.' }
        else { Out-Text "no roster.txt yet. One line per person:  Name | email | Team | Role | Org   (name = the Teams display name)`n  or: daily.pl roster add `"Ann Lee`" ann.lee@example.com Alpha Lead `"ACME`"`n" }
        $script:RC = 1; return
    }
    Out-Text (RosterText $r)
    $p = RosterCheck (Load-S) $r
    if (@($p).Count) { Out-Text ("check:`n" + (@(foreach ($x in $p) { '  ' + (PadR $x.level.ToUpper() 5) + " $($x.text)`n" }) -join '')) }
    $withMail = @(foreach ($x in $r) { if ($x.email -cmatch '@') { 1 } }).Count
    $agree = ''; if (-not @($p).Count) { $agree = ', roster and journal agree' }
    Out-Text "$(@($r).Count) people, $withMail with e-mail, $((RosterByTeam $r).by.Count) teams$agree`n"
    if (@($p | Where-Object { $_.level -ceq 'warn' }).Count) { $script:RC = 1 }
}
function MCmd-ReportMore {                            # the files daily.pl report writes from Metrics.pm and Quad.pm
    $s = Load-S
    $asOf = $script:Today
    $prev = LoadScrum $script:C.journal (AddDays $asOf -7) (AddDays $asOf -7)
    $o = HealthOpts $s $prev
    EnsureDir $script:C.reports
    $q = QuadData $s $null $prev $o.prev2
    $n = $s.current; $month = $asOf.Substring(0, 7)
    $rp = $script:C.reports
    WriteReport "$rp/$asOf-quad.html" (QuadHtml $q $script:C)
    WriteReport "$rp/$asOf-quad.txt" (QuadText $q $script:C)
    if ($null -ne $n) { WriteReport "$rp/sprint-$n-report.html" (SprintReportHtml $s $n $script:C); WriteReport "$rp/sprint-$n-report.txt" (SprintReportText $s $n $script:C) }
    WriteReport "$rp/$month-rollup.html" (RollupHtml $s $month $o.attendance $script:C)
    WriteReport "$rp/$month-rollup.txt" (RollupText $s $month $o.attendance $script:C)
    WriteReport "$rp/health.csv" ([string][char]0xFEFF + (HealthCsv $s $o))
}

# ================================================================ main
if ($Command -ceq '__lib') { return }
$script:Today = $Today
$script:PUSHED = $false
$script:RC = 0
$args1 = @($Rest | Where-Object { $null -ne $_ })
try {
    if ($script:Today -and $script:Today -cnotmatch '^\d{4}-\d{2}-\d{2}$') { throw "bad -Today '$Today' (want YYYY-MM-DD)`n" }
    if ($Command -in 'help', '-h', '--help', '/?') { Out-Text ($script:MORE_USAGE -replace "`r", '') }
    else {
        Load-Project
        switch -CaseSensitive ($Command) {
            'health' { MCmd-Health $args1; break }
            'review' { MCmd-Review $args1; break }
            'rollup' { MCmd-Rollup $args1; break }
            'csv' { MCmd-Csv $args1; break }
            'quad' { MCmd-Quad $args1; break }
            'roster' { MCmd-Roster $args1; break }
            'report-more' { MCmd-ReportMore; break }
            default { Out-Err 'commands: health review rollup csv quad roster report-more'; $script:RC = 2 }
        }
    }
}
catch { Out-Err ($_.Exception.Message); if (-not $script:RC) { $script:RC = 1 } }
finally { if ($script:PUSHED) { Pop-Location } }
if ($PSCommandPath) { exit $script:RC }
$global:LASTEXITCODE = $script:RC
