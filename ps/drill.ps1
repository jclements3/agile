<#
drill.ps1 -- the memory drill (daily.pl drill, lib/Drill.pm) in Windows PowerShell 5.1, Constrained Language Mode safe.

The backlog tree and the people, recalled rather than read, so the meeting can be run from memory. Cards are made
from the journal on every run (team: who?, AL = ?, AL: team?, Tome: epics?, epic: tome?, epic: open tasks?, AL: in
the sprint?, AL: next up?, task: who?, task: what is it?, task: blocked on?). Answers are terse: ids, codes and
initials in any order, case and commas ignored. Progress is the Leitner system in drill.txt next to scrum.conf
(key | box | due | right | wrong | answer | hook), the same file the Perl kit reads and writes.

  drill.ps1 [Team] [-N 12] [-Today YYYY-MM-DD] [-Conf path\scrum.conf]   the drill in the console (? = don't know, q = stop)
  drill.ps1 -Sheet [Team] [-N 12]      reports\<today>-drill.txt: answer after each '>' in pvi or Notepad, then grade it
  drill.ps1 -Grade FILE                grade the sheet; write hooks after 'hook:' and grade again to keep them

Exit: 0, or 1 when the console drill had a miss. Needs agile.ps1 beside it (the journal parser).
#>
param(
    [string]$TeamArg, [int]$N = -1, [switch]$Sheet, [string]$Grade, [string]$Team, [string]$Today, [string]$Conf
)
$DR = @{ team = $TeamArg; n = $N; sheet = [bool]$Sheet; grade = $Grade; today = $Today; conf = $Conf }
if (-not $DR.team -and $Team) { $DR.team = $Team }
if ($TeamArg -in @('help', '-h', '--help', '/?')) {
    Write-Output 'drill.ps1 [Team] [-N 12] | -Sheet [Team] | -Grade FILE   [-Today YYYY-MM-DD] [-Conf scrum.conf]'
    exit 0
}
. "$PSScriptRoot\agile.ps1" __lib                     # the journal parser; its param block resets $Conf and $Today here
$Conf = $DR.conf
$script:TODAY = $DR.today
$script:PUSHED = $false
$script:RC = 0

$script:KINDS = @('team', 'who', 'home', 'tome', 'up', 'epic', 'now', 'next', 'task', 'what', 'blk')   # presentation order
$script:INTERVAL = @(1, 1, 3, 7, 14, 30)               # days until due again, by box
$script:MAX_EPIC = 8                                   # more open tasks than this: ask only the in-sprint ones
$script:NEXTN = 5
$script:KIND_RANK = @{}; for ($i = 0; $i -lt $script:KINDS.Count; $i++) { $script:KIND_RANK[$script:KINDS[$i]] = $i }
$script:STOP = @{}; foreach ($w in @('AND', 'THE', 'OF', 'TO', 'ON', 'IN', 'FOR', 'BY', 'WITH', 'FROM', 'A', 'AN')) { $script:STOP[$w] = 1 }

# ================================================================ case-exact maps
# PowerShell hashtables ignore case; Perl's do not. Keys that come from names and ids go through CK (agile.ps1).
function MGet($h, [string]$k) { $h[(CK $k)] }
function MHas($h, [string]$k) { $h.ContainsKey((CK $k)) }
function MSet($h, [string]$k, $v) { $h[(CK $k)] = $v }
function NubCS($list) { $seen = @{}; , @(foreach ($x in @($list)) { $k = CK ('' + $x); if (-not $seen.ContainsKey($k)) { $seen[$k] = 1; $x } }) }
function Classify($list, [scriptblock]$f) {            # -> @{ keys = [first-seen order]; by = @{ CK key -> [items] } }
    $by = @{}; $keys = @()
    foreach ($x in @($list)) {
        $k = '' + (& $f $x); $ck = CK $k
        if (-not $by.ContainsKey($ck)) { $by[$ck] = @(); $keys += $k }
        $by[$ck] += , $x
    }
    @{ keys = $keys; by = $by }
}
function CGet($cl, [string]$k) { $v = $cl.by[(CK $k)]; if ($null -eq $v) { , @() } else { , @($v) } }

# ================================================================ UTF-8 bytes (CLM: no Encoding methods)
function Utf8Bytes([string]$s) {
    if ($null -eq $s -or $s.Length -eq 0) { return , @() }
    $a = $s.ToCharArray(); $howMany = $a.Count
    , @(for ($i = 0; $i -lt $howMany; $i++) {
            $cd = [int]$a[$i]
            if ($cd -ge 0xD800 -and $cd -le 0xDBFF -and $i + 1 -lt $howMany -and [int]$a[$i + 1] -ge 0xDC00 -and [int]$a[$i + 1] -le 0xDFFF) {
                $cd = 0x10000 + (($cd - 0xD800) -shl 10) + ([int]$a[$i + 1] - 0xDC00); $i++
            }
            if ($cd -lt 0x80) { $cd }
            elseif ($cd -lt 0x800) { 0xC0 -bor ($cd -shr 6); 0x80 -bor ($cd -band 0x3F) }
            elseif ($cd -lt 0x10000) { 0xE0 -bor ($cd -shr 12); 0x80 -bor (($cd -shr 6) -band 0x3F); 0x80 -bor ($cd -band 0x3F) }
            else { 0xF0 -bor ($cd -shr 18); 0x80 -bor (($cd -shr 12) -band 0x3F); 0x80 -bor (($cd -shr 6) -band 0x3F); 0x80 -bor ($cd -band 0x3F) }
        })
}
function WriteUtf8([string]$path, [string]$text) {     # UTF-8 without a BOM, the bytes as given (LF stays LF), as Perl writes
    $b = Utf8Bytes $text
    if ($b.Count) { Set-Content -LiteralPath $path -Encoding Byte -Value ([byte[]]$b) }
    else { Set-Content -LiteralPath $path -Value '' -NoNewline }
}
function ReadUtf8Raw([string]$path) {                  # the whole file as text, a leading BOM kept as U+FEFF (Perl's <:encoding(UTF-8)>)
    $t = Get-Content -LiteralPath $path -Raw -Encoding UTF8
    if ($null -eq $t) { $t = '' }
    $h = @(Get-Content -LiteralPath $path -Encoding Byte -TotalCount 3)
    if ($h.Count -eq 3 -and $h[0] -eq 0xEF -and $h[1] -eq 0xBB -and $h[2] -eq 0xBF -and -not ($t.Length -and $t[0] -eq [char]0xFEFF)) { $t = [string][char]0xFEFF + $t }
    $t
}
function Say([string]$t) { Write-Host -NoNewline $t }   # the console loop: prompts without a newline, in order with the answers

# ================================================================ roster (Roster::read_roster)
function ReadRoster([string]$file) {
    $t = ReadText $file
    if ($null -eq $t) { return , @() }
    $t = $t -creplace "`n$", ''
    , @(foreach ($l in ($t -csplit "`n")) {
            $l = $l -creplace '^\uFEFF', ''
            if ($l -cmatch '^\s*(#|$)') { continue }
            if ($l.Contains('|')) { $f = @($l -csplit '\s*\|\s*', 5) } else { $f = @($l -csplit '\s*,\s*', 5) }
            $f = @(foreach ($x in $f) { $x.Trim() })
            if (-not $f[0]) { continue }
            $g = @('', '', '', '', ''); for ($i = 0; $i -lt $f.Count -and $i -lt 5; $i++) { $g[$i] = $f[$i] }
            @{ name = $g[0]; email = $g[1]; team = $g[2]; role = $g[3]; org = $g[4] }
        })
}

# ================================================================ initials
function Words([string]$howMany) {                           # "Archer, Sam" reads as "Sam Archer"; Smith-Jones is two words
    if ($null -eq $howMany) { $howMany = '' }
    if ($howMany -cmatch '^([^,]+),\s*(.+)$') { $howMany = "$($Matches[2]) $($Matches[1])" }
    , @(foreach ($w in ($howMany -csplit '[\s-]+')) { $w = $w -creplace '[^\p{L}\d]', ''; if ($w.Length) { $w } })
}
function PSub([string]$s, [int]$off, [int]$len) {      # Perl substr: '' past the end
    if ($null -eq $s -or $off -ge $s.Length) { return '' }
    if ($off + $len -gt $s.Length) { $len = $s.Length - $off }
    $s.Substring($off, $len)
}
function UcFirst([string]$s) { if (-not $s) { return '' }; $s.Substring(0, 1).ToUpperInvariant() + $s.Substring(1) }
function Initials($names) {                            # -> case-exact map name -> 'AL'; collisions extend: ACh ACo, SA SA2
    $names = NubCS $names
    $base = @{}
    foreach ($nm in $names) {
        $w = Words $nm
        if ($w.Count -gt 1) { $b = (@(foreach ($x in $w) { $x.Substring(0, 1).ToUpperInvariant() }) -join '') }
        else { $w0 = '?'; if ($w.Count) { $w0 = $w[0] }; $b = UcFirst ((PSub $w0 0 2).ToLowerInvariant()) }
        MSet $base $nm $b
    }
    $out = @{}
    $groups = Classify $names { param($x) (MGet $base $x).ToUpperInvariant() }
    foreach ($gk in $groups.keys) {
        $g = CGet $groups $gk
        if ($g.Count -eq 1) { MSet $out $g[0] (MGet $base $g[0]); continue }
        $canon = @{}; foreach ($x in $g) { MSet $canon $x ((@(foreach ($w in (Words $x)) { $w.ToUpperInvariant() })) -join ' ') }
        $sg = Sorted $g
        $reps = NubCS @(foreach ($x in $sg) { MGet $canon $x })
        $repBase = @{}; foreach ($x in $g) { MSet $repBase (MGet $canon $x) (MGet $base $x) }
        $ext = @{}
        if ($reps.Count -eq 1) { MSet $ext $reps[0] (MGet $repBase $reps[0]) }
        for ($k = 1; $k -le 12; $k++) {
            if ($reps.Count -eq 1) { break }
            $try = @{}
            foreach ($r in $reps) { $ws = @($r -csplit ' ' | Where-Object { $_ -ne '' }); $last = ''; if ($ws.Count) { $last = $ws[$ws.Count - 1] }; MSet $try $r ((MGet $repBase $r) + (PSub $last 1 $k).ToLowerInvariant()) }
            $cnt = @{}; foreach ($r in $reps) { $u = CK ((MGet $try $r).ToUpperInvariant()); $cnt[$u] = 1 + [int]$cnt[$u] }
            $ones = 0; foreach ($v in $cnt.Values) { if ($v -eq 1) { $ones++ } }
            if ($ones -eq $reps.Count -or $k -eq 12) { $ext = $try; break }
        }
        $seen = @{}
        foreach ($x in $sg) {
            $i0 = MGet $ext (MGet $canon $x); $u = CK $i0.ToUpperInvariant(); $seen[$u] = 1 + [int]$seen[$u]; $cd = $seen[$u]
            if ($cd -gt 1) { MSet $out $x "$i0$cd" } else { MSet $out $x $i0 }
        }
    }
    $out
}

# ================================================================ cards
function Code([string]$name) {                         # the epic's code: its first word when it looks like one (C2, B-1, E.3)
    if ($null -eq $name) { $name = '' }
    if ($name -cmatch '^(\S+)\s+\S') { $w = $Matches[1]; if ($w -cmatch '^[A-Z0-9][A-Z0-9.\-]{0,5}$' -and $w -cmatch '[A-Z]') { return $w } }
    $name
}
function NewCard($h) {
    if ($null -eq $h.show) { $h.show = ($h.want -join ' ') }
    if ($null -eq $h.names) { $h.names = @() }
    $h
}
function Cards($s, [string]$teamSel, $roster) {
    $open = @(foreach ($it in (AllItems $s)) {
            if ($it.state -cnotin @('committed', 'carryover', 'backlog', 'master')) { continue }
            if ($teamSel -and ('' + $it.team) -cne $teamSel) { continue }
            $it
        })
    $ros = @(foreach ($r in $roster) { if (-not $teamSel -or ('' + $r.team) -ceq $teamSel) { $r } })
    $homeOf = @{}
    foreach ($r in $ros) { if ($r.team) { MSet $homeOf $r.name $r.team } }
    foreach ($it in $open) { if (-not $it.owner -or -not $it.team -or $it.team -ceq 'Master') { continue }; if ($null -eq (MGet $homeOf $it.owner)) { MSet $homeOf $it.owner $it.team } }
    $people = Sorted (NubCS (@(foreach ($it in $open) { if ($it.owner) { $it.owner } }) + @(foreach ($r in $ros) { $r.name })))
    $ini = Initials (@($people) + @(foreach ($r in $roster) { $r.name }))
    $at = ''; if ($teamSel) { $at = "@$teamSel" }
    $cd = @()
    $whoShow = { param($ps) (@(foreach ($p in $ps) { "$(MGet $ini $p) ($p)" }) -join ' ') }

    $byTeam = Classify $people { param($p) $h = MGet $homeOf $p; if ($null -eq $h) { '' } else { $h } }
    foreach ($t in (Sorted @($byTeam.keys | Where-Object { $_.Length }))) {
        $p = CGet $byTeam $t
        $cd += , (NewCard @{ key = "team:$t"; kind = 'team'; q = "Team ${t}: who? (initials)"; want = @(foreach ($x in $p) { MGet $ini $x }); mode = 'set'; show = (& $whoShow $p); names = $p })
    }
    foreach ($p in $people) {
        $cd += , (NewCard @{ key = "who:$p"; kind = 'who'; q = "$(MGet $ini $p) = ?  (full name)"; want = @($p); mode = 'name'; names = @($p) })
        $h = MGet $homeOf $p
        if ($h) { $cd += , (NewCard @{ key = "home:$p"; kind = 'home'; q = "$(MGet $ini $p): team?"; want = @($h); mode = 'set'; names = @($p) }) }
    }
    $byEpic = Classify $open { param($it) $e = $it.meta['epic']; if ($null -eq $e) { '' } else { $e } }
    $tomeOf = @{}
    foreach ($e in $byEpic.keys) { $tm = ''; foreach ($it in (CGet $byEpic $e)) { if ($null -ne $it.meta['tome']) { $tm = $it.meta['tome']; break } }; MSet $tomeOf $e $tm }
    $byTome = Classify @($byEpic.keys | Where-Object { $_.Length }) { param($e) MGet $tomeOf $e }
    foreach ($t in (Sorted @($byTome.keys | Where-Object { $_.Length }))) {
        $es = Sorted (CGet $byTome $t)
        $codes = @(foreach ($e in $es) { if ((Code $e) -cne $e) { 1 } }).Count
        $qq = "Tome ${t}: epics?"; if ($codes) { $qq += ' (codes)' }
        $cd += , (NewCard @{ key = "tome:$t$at"; kind = 'tome'; q = $qq; want = @(foreach ($e in $es) { Code $e }); mode = 'set'; show = ($es -join ', ') })
    }
    foreach ($e in (Sorted @($byEpic.keys | Where-Object { $_.Length }))) {
        $its = CGet $byEpic $e
        $tm = MGet $tomeOf $e
        if ($tm) { $cd += , (NewCard @{ key = "up:$e"; kind = 'up'; q = "${e}: tome?"; want = @(Code $tm); mode = 'set'; show = $tm }) }
        $qq = 'open tasks?'; $ask = $its
        if ($its.Count -gt $script:MAX_EPIC) { $qq = 'in the sprint?'; $ask = @(foreach ($it in $its) { if ($it.state -ceq 'committed' -or $it.state -ceq 'carryover') { $it } }) }
        if (-not $ask.Count -or $ask.Count -gt $script:MAX_EPIC) { continue }
        $cd += , (NewCard @{ key = "epic:$e$at"; kind = 'epic'; q = "${e}: $qq (ids)"; want = @(foreach ($it in $ask) { $it.id }); mode = 'set'; show = (@(foreach ($it in $ask) { "$($it.id) $($it.title)" }) -join ', ') })
    }
    $byOwner = Classify $open { param($it) if ($null -eq $it.owner) { '' } else { $it.owner } }
    foreach ($p in $people) {
        $mine = CGet $byOwner $p
        $now = @(foreach ($it in $mine) { if ($it.state -ceq 'committed' -or $it.state -ceq 'carryover') { $it } })
        $next = @(foreach ($it in $mine) { if ($it.state -ceq 'backlog' -or $it.state -ceq 'master') { $it } })
        if ($now.Count) { $cd += , (NewCard @{ key = "now:$p"; kind = 'now'; q = "$(MGet $ini $p): in the sprint? (ids)"; want = @(foreach ($it in $now) { $it.id }); mode = 'set'; show = (@(foreach ($it in $now) { "$($it.id) $($it.title)" }) -join ', '); names = @($p) }) }
        if ($next.Count -gt $script:NEXTN) { $next = @($next[0..($script:NEXTN - 1)]) }
        if ($next.Count) {
            $top = ''; if ($mine.Count - $now.Count -gt $script:NEXTN) { $top = ", top $($script:NEXTN)" }
            $cd += , (NewCard @{ key = "next:$p"; kind = 'next'; q = "$(MGet $ini $p): next up? (ids$top)"; want = @(foreach ($it in $next) { $it.id }); mode = 'set'; show = (@(foreach ($it in $next) { "$($it.id) $($it.title)" }) -join ', '); names = @($p) })
        }
    }
    foreach ($it in $open) {
        if ($it.owner) { $cd += , (NewCard @{ key = "task:$($it.id)"; kind = 'task'; q = "$($it.id) $($it.title): who?"; want = @(MGet $ini $it.owner); mode = 'set'; show = (& $whoShow @(, $it.owner)); names = @($it.owner) }) }
        if (('' + $it.title).Length) { $cd += , (NewCard @{ key = "what:$($it.id)"; kind = 'what'; q = "$($it.id): what is it? (a few words)"; want = @($it.title); mode = 'gist' }) }
        if ($it.blocked) { $cd += , (NewCard @{ key = "blk:$($it.id)"; kind = 'blk'; q = "$($it.id) $($it.title): blocked on?"; want = @($it.blocked); mode = 'gist' }) }
    }
    $vocab = @{}
    foreach ($x in $cd) { if ($x.mode -ceq 'set') { foreach ($w in $x.want) { $k = CK (NormT $w); $vocab[$k] = 1 + [int]$vocab[$k] } } }
    foreach ($x in $cd) { $x.vocab = $vocab }
    , $cd
}

# ================================================================ grading
function NormT([string]$t) { if ($null -eq $t) { $t = '' }; $t = $t.ToUpperInvariant() -creplace '[^\p{L}\d\-]+', ' '; $t.Trim() }
function SplitSp([string]$s) { , @($s -csplit '\s+' | Where-Object { $_ -ne '' }) }
function Sig([string]$t) { , @(foreach ($w in (SplitSp (NormT $t))) { if ($w.Length -gt 2 -and -not $script:STOP.ContainsKey($w)) { $w } }) }
function Like([string]$a, [string]$b) {
    if ($a -ceq $b) { return $true }
    if ($a.Length -lt $b.Length) { $sh = $a; $lo = $b } else { $sh = $b; $lo = $a }
    $sh.Length -ge 4 -and $lo.StartsWith($sh, 'Ordinal')
}
function GradeCard($cd, [string]$ans) {                  # -> @{ ok; missed; extra }
    $missed = @(); $extra = @()
    if ($cd.mode -ceq 'set') {
        $a = ' ' + (NormT $ans) + ' '
        foreach ($w in $cd.want) {
            $nn = NormT $w
            $m = [regex]::Match($a, '(?i) ' + [regex]::Escape($nn) + ' ')
            if ($m.Success) { $a = $a.Substring(0, $m.Index) + ' ' + $a.Substring($m.Index + $m.Length) } else { $missed += , $w }
        }
        $extra = @(foreach ($w in (SplitSp $a)) { if ($cd.vocab[(CK $w)]) { $w } })
    }
    elseif ($cd.mode -ceq 'name') {
        $got = @{}; foreach ($w in (Words $ans)) { $got[(CK $w.ToUpperInvariant())] = 1 }
        $missed = @(foreach ($x in $cd.want) { foreach ($w in (Words $x)) { $u = $w.ToUpperInvariant(); if (-not $got.ContainsKey((CK $u))) { $u } } })
    }
    else {
        $got = Sig $ans
        $want = NubCS (Sig $cd.want[0])
        if (-not $want.Count) { $want = NubCS (SplitSp (NormT $cd.want[0])); $got = SplitSp (NormT $ans) }
        $missed = @(foreach ($w in $want) { $hit = $false; foreach ($g in $got) { if (Like $w $g) { $hit = $true; break } }; if (-not $hit) { $w } })
        $ok = [bool]($want.Count -and 2 * ($want.Count - $missed.Count) -ge $want.Count)
        return @{ ok = $ok; missed = $missed; extra = @() }
    }
    @{ ok = (-not $missed.Count -and -not $extra.Count); missed = $missed; extra = $extra }
}

# ================================================================ progress (drill.txt)
function Flat($t) { if ($null -eq $t) { return '' }; ('' + $t).Replace('|', '/').Replace("`n", ' ') }
function PTrue($v) { $null -ne $v -and $v -ne '' -and $v -ne '0' }   # Perl truth for a field read as text
function ReadProgress([string]$file) {                 # -> @{ CK key -> @{ key; box; due; right; wrong; ans; hook } }
    $p = @{}
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { return $p }
    $t = Get-Content -LiteralPath $file -Raw -Encoding UTF8
    if ($null -eq $t) { return $p }
    $t = $t -creplace "`n$", ''
    foreach ($l in ($t -csplit "`n")) {
        $l = $l -creplace "`r$", ''; $l = $l -creplace '^\uFEFF', ''
        if ($l -cmatch '^\s*(#|$)') { continue }
        $f = @(foreach ($x in @($l -csplit '\|', 7)) { $x.Trim() })
        if (-not (PTrue $f[0])) { continue }
        $g = @($null, $null, $null, $null, $null, $null, $null); for ($i = 0; $i -lt $f.Count -and $i -lt 7; $i++) { $g[$i] = $f[$i] }
        $r = @{ key = $g[0]; box = 0; due = ''; right = 0; wrong = 0; ans = ''; hook = '' }
        if (PTrue $g[1]) { $r.box = $g[1] }; if ($null -ne $g[2]) { $r.due = $g[2] }
        if (PTrue $g[3]) { $r.right = $g[3] }; if (PTrue $g[4]) { $r.wrong = $g[4] }
        if ($null -ne $g[5]) { $r.ans = $g[5] }; if ($null -ne $g[6]) { $r.hook = $g[6] }
        MSet $p $g[0] $r
    }
    $p
}
function WriteProgress([string]$file, $p) {
    $rows = SortOn @($p.Values) { param($r) $r.key }
    $out = "# memory drill progress (daily.pl drill): key | box | due | right | wrong | answer | hook`n"
    foreach ($r in $rows) { $out += ((@($r.key, (Str $r.box), (Str $r.due), (Str $r.right), (Str $r.wrong), (Flat $r.ans), (Flat $r.hook)) -join ' | ') + "`n") }
    WriteUtf8 $file $out
}
function Record($p, $cd, [bool]$ok, [string]$day) {   # move the card between boxes, remember the answer
    $r = MGet $p $cd.key
    if ($null -eq $r) { $r = @{ key = $cd.key; box = 0; right = 0; wrong = 0; hook = ''; due = $null; ans = $null }; MSet $p $cd.key $r }
    $top = $script:INTERVAL.Count - 1
    if ($ok) { $b = [double]$r.box; if ($b -lt $top) { $r.box = $b + 1 } else { $r.box = $top } } else { $r.box = 0 }
    if ($ok) { $r.right = [double]$r.right + 1 } else { $r.wrong = [double]$r.wrong + 1 }
    $r.due = AddDays $day $script:INTERVAL[[int]$r.box]
    $r.ans = Flat $cd.show
    $r
}
function Pick($cards, $p, [string]$day, [int]$howMany) {   # cards due now: changed, then due (room permitting), then new (a third)
    $changed = @(); $due = @(); $new = @{}
    foreach ($cd in $cards) {
        $r = MGet $p $cd.key
        if ($null -eq $r) { $x = $cd.Clone(); $x.status = 'new'; if (-not $new.ContainsKey($cd.kind)) { $new[$cd.kind] = @() }; $new[$cd.kind] += , $x; continue }
        if (('' + $r.ans).Length -and $r.ans -cne (Flat $cd.show)) { $x = $cd.Clone(); $x.status = 'changed'; $x.was = $r.ans; $changed += , $x }
        elseif (-not (SGt ('' + $r.due) $day)) { $x = $cd.Clone(); $x.status = 'due'; $x.box = $r.box; $x.due = $r.due; $due += , $x }
    }
    $due = SortWith $due { param($a, $b) $x = [double]$a.box; $y = [double]$b.box; if ($x -lt $y) { -1 } elseif ($x -gt $y) { 1 } else { $o = [string]::CompareOrdinal(('' + $a.due), ('' + $b.due)); if ($o -lt 0) { -1 } elseif ($o -gt 0) { 1 } else { 0 } } }
    $newl = @()
    $pos = @{}; foreach ($k in $script:KINDS) { $pos[$k] = 0 }
    $left = $true
    while ($left) {
        $left = $false
        foreach ($k in $script:KINDS) { $l = $new[$k]; if ($l -and $pos[$k] -lt $l.Count) { $newl += , $l[$pos[$k]]; $pos[$k]++ } }
        foreach ($k in $script:KINDS) { $l = $new[$k]; if ($l -and $pos[$k] -lt $l.Count) { $left = $true } }
    }
    $quota = 0; if ($newl.Count) { if ($howMany -ge 3) { $quota = Trunc ($howMany / 3) } else { $quota = 1 } }
    if ($quota -gt $newl.Count) { $quota = $newl.Count }
    $room = $howMany - $changed.Count - $quota; if ($room -lt 0) { $room = 0 }
    $take = $due; if ($due.Count -gt $room) { if ($room -gt 0) { $take = @($due[0..($room - 1)]) } else { $take = @() } }
    $out = @($changed) + @($take) + @($newl)
    if ($out.Count -gt $howMany) { if ($howMany -gt 0) { $out = @($out[0..($howMany - 1)]) } else { $out = @() } }
    $ord = @{}; for ($i = 0; $i -lt $cards.Count; $i++) { $ord[(CK $cards[$i].key)] = $i }
    SortWith $out { param($a, $b) $x = $script:KIND_RANK[$a.kind]; $y = $script:KIND_RANK[$b.kind]; if ($x -ne $y) { if ($x -lt $y) { -1 } else { 1 } } else { $i = $ord[(CK $a.key)]; $j = $ord[(CK $b.key)]; if ($i -lt $j) { -1 } elseif ($i -gt $j) { 1 } else { 0 } } }
}
function Hooks($cd, $p) {                                # the card's own hook, then the people in the answer
    $h = @()
    $r = MGet $p $cd.key
    if ($r -and ('' + $r.hook).Length) { $h += "hook: $($r.hook)" }
    foreach ($who in @($cd.names)) { $w = MGet $p "who:$who"; if ($w -and ('' + $w.hook).Length -and $cd.key -cne "who:$who") { $h += "${who}: $($w.hook)" } }
    , $h
}
function Verdict($cd, $g) {
    if ($g.ok) { $t = '= ok'; if (-not ($cd.mode -ceq 'set' -and $cd.show -ceq ($cd.want -join ' '))) { $t += "  $($cd.show)" }; return , @($t) }
    $d = @()
    if ($g.missed.Count -and $cd.mode -ceq 'set') { $d += 'missed ' + ($g.missed -join ' ') }
    if ($g.extra.Count) { $d += 'not in it ' + ($g.extra -join ' ') }
    $o = @("= miss  $($cd.show)"); if ($d.Count) { $o += '  ' + ($d -join '; ') }
    , $o
}
function MissG { @{ ok = $false; missed = @(); extra = @() } }

# ================================================================ the sheet (answered in pvi or Notepad, graded with -Grade)
function StatusText($cd) { if ($cd.status -ceq 'changed') { "  (changed, was: $($cd.was))" } elseif ($cd.status -ceq 'new') { '  (new)' } else { '' } }
function SheetText($pick, [string]$day, [string]$teamSel) {
    $howMany = @{ changed = 0; due = 0; new = 0 }; foreach ($cd in $pick) { $howMany[$cd.status]++ }
    $parts = @(foreach ($k in @('changed', 'due', 'new')) { if ($howMany[$k]) { "$($howMany[$k]) $k" } })
    $tt = ''; if ($teamSel) { $tt = " -- $teamSel" }
    $out = "; memory drill $day${tt}: $($pick.Count) cards ($($parts -join ', '))`n" +
    "; answer after each '>', then :w to grade. Terse: ids, codes, initials, any order, any case. '?' = don't know.`n" +
    "; after grading, write a mnemonic after 'hook:' and :w again to keep it ('hook: -' forgets it).`n"
    if ($teamSel) { $out += "; team: $teamSel`n" }
    $out += "; score: -`n"
    $i = 0
    foreach ($cd in $pick) { $i++; $out += "`n#$i $($cd.key)$(StatusText $cd)`n$($cd.q)`n> `n" }
    $out
}
function GradeSheet([string]$text, $by, $p, [string]$day) {   # -> @{ text; st }
    $lines = @($text -csplit "`n")
    if ($lines.Count -and $lines[$lines.Count - 1] -ceq '') { if ($lines.Count -gt 1) { $lines = @($lines[0..($lines.Count - 2)]) } else { $lines = @() } }
    $head = @(); $blocks = @()
    foreach ($l in $lines) {
        if ($l -cmatch '^#\d+\s+(.+?)(?:\s{2}\(.*\))?\s*$') { $blocks += , @{ key = $Matches[1]; lines = @($l) } }
        elseif ($blocks.Count) { $blocks[$blocks.Count - 1].lines += , $l }
        else { $head += , $l }
    }
    $st = @{ graded = 0; ok = 0; miss = 0; hooks = 0; done = 0; total = $blocks.Count }
    foreach ($b in $blocks) {
        $BL = @($b.lines)
        $ai = -1; for ($i = 0; $i -lt $BL.Count; $i++) { if ($BL[$i] -cmatch '^>') { $ai = $i; break } }
        $graded = @($BL | Where-Object { $_ -cmatch '^= ' }).Count
        $ans = ''
        if ($ai -ge 0) { if ($BL[$ai] -cmatch '^>\s?') { $ans = $BL[$ai].Substring($Matches[0].Length) } else { $ans = $BL[$ai] } }
        $cd = MGet $by $b.key
        if ($ai -ge 0 -and $ans -cmatch '\S' -and -not $graded) {
            $ins = @()
            if ($null -eq $cd) { $ins = @('= gone  (no longer in the journal)') }
            else {
                if ($ans -cmatch '^\s*\?\s*$') { $g = MissG } else { $g = GradeCard $cd $ans }
                $ins = Verdict $cd $g
                if (-not $g.ok) {
                    foreach ($h in (Hooks $cd $p)) { if ($h -cnotmatch '^hook: ') { $ins += "  $h" } }
                    if (-not @($BL | Where-Object { $_ -cmatch '^hook:' }).Count) { $r = MGet $p $b.key; $hk = ''; if ($r) { $hk = $r.hook }; $ins += "hook: $hk" }
                }
                $null = Record $p $cd $g.ok $day
                $st.graded++
            }
            $BL = @($BL[0..$ai]) + $ins + $(if ($ai + 1 -lt $BL.Count) { @($BL[($ai + 1)..($BL.Count - 1)]) } else { @() })
        }
        foreach ($hl in $BL) {                           # hooks: kept when written, forgotten with '-'
            if ($hl -cnotmatch '^hook:\s*(.*?)\s*$' -or -not $Matches[1].Length) { continue }
            $h = $Matches[1]; if ($h -ceq '-') { $h = '' }
            $r = MGet $p $b.key; if (-not $r) { continue }
            if (('' + $r.hook) -ceq (Flat $h)) { continue }
            $r.hook = Flat $h; $st.hooks++
        }
        if (@($BL | Where-Object { $_ -cmatch '^= ok' }).Count) { $st.ok++ }
        if (@($BL | Where-Object { $_ -cmatch '^= miss' }).Count) { $st.miss++ }
        if (@($BL | Where-Object { $_ -cmatch '^= ' }).Count) { $st.done++ }
        $b.lines = $BL
    }
    $score = "; score: $($st.ok)/$($st.total) ok, $($st.miss) missed"
    if ($st.done -lt $st.total) { $score += ", $($st.total - $st.done) to go" }
    $head = @(foreach ($l in $head) { if ($l -cmatch '^; score:') { $l -creplace '^; score:.*$', $score } else { $l } })
    $all = @($head) + @(foreach ($b in $blocks) { $b.lines })
    @{ text = (($all -join "`n") + "`n"); st = $st }
}

# ================================================================ the console loop
function DrillLoop($pick, $p, [string]$day, [bool]$askHook, $feed, [string]$file) {
    $st = @{ ok = 0; miss = 0; total = $pick.Count }
    $i = 0; $fi = 0
    foreach ($cd in $pick) {
        $i++
        Say ("`n[$i/$($pick.Count)] $($cd.q)$(StatusText $cd)`n> ")
        if ($null -ne $feed) { if ($fi -ge $feed.Count) { break }; $ans = '' + $feed[$fi]; $fi++ } else { $ans = Read-Host; if ($null -eq $ans) { break } }
        $ans = $ans -creplace "`r$", ''
        if ($ans -match '^\s*(q|quit)\s*$') { break }
        if ($ans -cmatch '^\s*\??\s*$') { $g = MissG } else { $g = GradeCard $cd $ans }
        foreach ($v in (Verdict $cd $g)) { Say "$v`n" }
        if (-not $g.ok) {
            foreach ($h in (Hooks $cd $p)) { Say "  $h`n" }
            $null = Record $p $cd $false $day
            $h = $null
            if ($askHook) {
                Say 'hook (enter to keep, - to forget)> '
                if ($null -ne $feed) { if ($fi -lt $feed.Count) { $h = '' + $feed[$fi]; $fi++ } } else { $h = Read-Host }
            }
            if ($null -ne $h) { $h = ($h -creplace "`r$", '').Trim(); if ($h.Length) { $r = MGet $p $cd.key; if ($h -ceq '-') { $r.hook = '' } else { $r.hook = Flat $h } } }
        }
        else { $null = Record $p $cd $true $day }
        if ($g.ok) { $st.ok++ } else { $st.miss++ }
        WriteProgress $file $p
    }
    Say ("`n$($st.ok)/$($st.ok + $st.miss) ok, $($st.miss) missed`n")
    $st
}

# ================================================================ main (daily.pl cmd_drill)
function Cmd-Drill {
    Load-Project
    $file = $script:C['drill']; if (-not $file) { $file = 'drill.txt' }
    $prog = ReadProgress $file
    $roster = ReadRoster 'roster.txt'
    $s = Load-S
    $day = $script:TODAY
    if ($DR.grade) {
        if (-not (Test-Path -LiteralPath $DR.grade -PathType Leaf)) { Out-Err "cannot read $($DR.grade): No such file or directory"; $script:RC = 2; return }
        $text = ReadUtf8Raw $DR.grade
        $t = $null; if ($text -cmatch '(?m)^; team: (.+?)\s*$') { $t = $Matches[1] }
        $by = @{}; foreach ($cd in (Cards $s $t $roster)) { MSet $by $cd.key $cd }
        $res = GradeSheet $text $by $prog $day
        if ($res.text -cne $text) { WriteUtf8 $DR.grade $res.text }
        $st = $res.st
        if ($st.graded -or $st.hooks) { WriteProgress $file $prog }
        $go = ''; if ($st.done -lt $st.total) { $go = ", $($st.total - $st.done) to go" }
        Out-Text "graded $($st.graded), hooks saved $($st.hooks) -- $($st.ok)/$($st.total) ok, $($st.miss) missed$go`n"
        return
    }
    $teamSel = $DR.team
    $cards = Cards $s $teamSel $roster
    $howMany = 12; if ($DR.n -ge 0) { $howMany = $DR.n }
    $pick = Pick $cards $prog $day $howMany
    if (-not $pick.Count) {
        $next = Sorted @(foreach ($cd in $cards) { $r = MGet $prog $cd.key; $d = ''; if ($r -and $null -ne $r.due) { $d = '' + $r.due }; if (SGt $d $day) { $d } })
        $nx = ''; if ($next.Count) { $nx = ", next due $($next[0])" }
        Out-Text "nothing due today ($($cards.Count) cards$nx)`n"
        return
    }
    if ($DR.sheet) {
        EnsureDir $script:C.reports
        $f = Join-Path (Join-Path (Get-Location).Path $script:C.reports) "$day-drill.txt"
        WriteUtf8 $f (SheetText $pick $day $teamSel)
        Out-Text "$f`n"
        return
    }
    $redirected = $false; try { $redirected = [bool][Console]::IsInputRedirected } catch { $redirected = $false }
    $feed = $null
    if ($redirected) { $feed = @(cmd.exe /c 'findstr "^"'); $global:LASTEXITCODE = 0 }   # piped answers, read at once (Read-Host would echo them)
    Say "memory drill: $($pick.Count) cards. Terse answers (ids, codes, initials, any order, any case); ? = don't know, q = stop.`n"
    $st = DrillLoop $pick $prog $day (-not $redirected) $feed $file
    if ($st.miss) { $script:RC = 1 }
}

try { Cmd-Drill }
catch { Out-Err ($_.Exception.Message); if (-not $script:RC) { $script:RC = 1 } }
finally { if ($script:PUSHED) { Pop-Location } }
if ($PSCommandPath) { exit $script:RC }
$global:LASTEXITCODE = $script:RC
