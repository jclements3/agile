<#
talk.ps1 -- drafts the words for a stand-up, a sprint review demo, or a weekly note to management, from what GitLab
(and, optionally, the kit's journal) already knows (tools/gitlab/talk.pl). It DRAFTS ONLY: it prints text for a person
to read, edit and say; it never posts, comments, labels or changes anything (every GitLab call it makes is a read).

Windows PowerShell 5.1, Constrained Language Mode safe, pure ASCII. GitLab is read through ..\gitlab.ps1's library
(..\gitlab\*.ps1: the offline emulator with --local DIR, or a server with --url URL); the stand-up lint and the journal
through ..\agile.ps1.

  talk.cmd [--local DIR | --url URL [--token-env VAR]] [--project GROUP/NAME] COMMAND ...
    standup --as USER [--date D] [--journal DIR] [--prefix TW-] [--why] [--chat [--name "First Last"]]
    review  --sprint N [--baseline FILE] [--metrics FILE] [--journal DIR] [--md]
    weekly  [--date D] [--baseline FILE] [--metrics FILE] [--md]
    translate FILE|- [--glossary FILE] [--md]
    help
  Environment: GITLAB_LOCAL, GITLAB_URL, GITLAB_PROJECT, TALK_PREFIX. Exit 0, 2 on a usage error.
  --chat: the stand-up line as a Teams chat paste ("[9:05 AM] Name" header); the notes then go to the console host
  (Write-Host), so `talk.cmd standup --as bob --chat | agile.cmd lint -` reads only the message.
#>

$ErrorActionPreference = 'Stop'
$script:TK_HERE = $PSScriptRoot; if (-not $script:TK_HERE) { $script:TK_HERE = (Get-Location).Path }
$script:TK_PS = Split-Path -Parent $script:TK_HERE
. "$($script:TK_PS)\ziplib.ps1"
. "$($script:TK_PS)\gitlab\glcore.ps1"
. "$($script:TK_PS)\gitlab\glapi.ps1"
. "$($script:TK_PS)\gitlab\glemu.ps1"
. "$($script:TK_PS)\gitlab\glsetup.ps1"

$script:TK_DOW = @('Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat')
$script:TK_MON = @('Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec')
$script:TK_OUT = ''
$script:TK_NOTE = ''
function TkOut([string]$s) { $script:TK_OUT += $s }
function TkMin($a, $b) { if ($a -lt $b) { return $a }; return $b }
function TkAbs($a) { if ($a -lt 0) { return -$a }; return $a }
function TkDie([string]$m) { throw ('TKDIE:' + $m) }

# ---------------------------------------------------------------- small helpers
function TkEp($s) {                               # ISO -> epoch (UTC)
    if ($null -eq $s -or [string]$s -cnotmatch '^(\d{4})-(\d\d)-(\d\d)(?:[T ](\d\d):(\d\d)(?::(\d\d))?)?') { return $null }
    $m = $Matches
    $t = TimeGm ([long](Dor $m[6] 0)) ([long](Dor $m[5] 0)) ([long](Dor $m[4] 0)) ([long]$m[3]) ([long]$m[2] - 1) ([long]$m[1])
    if ([string]$s -cmatch '([+-])(\d\d):?(\d\d)$') { $sg = if ($Matches[1] -ceq '-') { -1 } else { 1 }; $t -= $sg * ([long]$Matches[2] * 3600 + [long]$Matches[3] * 60) }
    return $t
}
function TkDay($t) { $g = GmTime ([long]$t); return ('{0}-{1}-{2}' -f (P4 ($g[5] + 1900)), (P2 ($g[4] + 1)), (P2 $g[3])) }
function TkDow($s) { return $script:TK_DOW[(GmTime (TkEp $s))[6]] }
function TkNiceDate($s) { $g = GmTime (TkEp $s); return ($script:TK_DOW[$g[6]] + ' ' + $script:TK_MON[$g[4]] + ' ' + $g[3]) }
function TkPrevWorkday($s) { $t = TkEp $s; do { $t -= 86400; $w = (GmTime $t)[6] } while ($w -eq 0 -or $w -eq 6); return (TkDay $t) }
function TkShort($t, [int]$n = 40) {
    if ($null -eq $t) { $t = '' }
    $t = ([string]$t) -creplace '\s+', ' '
    $t = $t -creplace '^\s+|\s+$', ''
    if ($t.Length -le $n) { return $t }
    $c = $t.Substring(0, $n) -creplace '\s+\S*$', ''
    return $c + '...'
}
function TkLcFirst([string]$t) { if ($t -cmatch '^([A-Z])(?=[a-z])') { return $t.Substring(0, 1).ToLowerInvariant() + $t.Substring(1) }; return $t }
function TkPlural($n, [string]$w) { if ([long]$n -eq 1) { return "$n $w" }; $w = $w -creplace '([^aeiou])y$', '$1ie'; return "$n ${w}s" }
function TkLabels($x) { $o = @(); foreach ($l in (L $x.labels)) { if ($l -is [hashtable]) { $o += [string]$l.name } else { $o += [string]$l } }; return , $o }
function TkHas($x, [string]$l) { return ((TkLabels $x) -ccontains $l) }
function TkAssigned($x, [string]$u) { foreach ($a in (L $x.assignees)) { if (([string](Dor $a.username '')).ToLowerInvariant() -ceq $u.ToLowerInvariant()) { return $true } }; return $false }
function TkIn($ts, $from, $to) { $t = TkEp $ts; return ($null -ne $t -and $t -ge $from -and $t -lt $to) }
function TkR1($v) { if ($null -eq $v) { return $null }; return (NumStr (PNum (FmtF $v 1))) }
function TkHours($h) {
    if ($null -eq $h) { return '-' }
    $h = [double]$h
    if ($h -ge 48) { return ((FmtF ($h / 24) 1) + ' days') }
    if ($h -ge 1) { return ((FmtF $h 1) + ' h') }
    return ([string](Trunc ($h * 60 + 0.5)) + ' min')
}
function TkUser($x) { if ($x -is [hashtable]) { return [string](Dor $x.username '') }; return '' }
function TkIid($x) { return [long](PNum $x.iid) }

# ---------------------------------------------------------------- connection and project data
function TkConnect($o) {
    $local = $o['local']; if ($null -eq $local -and -not $o['url']) { $local = $env:GITLAB_LOCAL }
    $url = $o['url']; if ($null -eq $url -and -not $local) { $url = $env:GITLAB_URL }
    if ($local) { $gl = New-GL (O 'local' $local) }
    elseif ($url) { $gl = New-GL (O 'url' $url 'token_env' (Dor $o['token-env'] 'GITLAB_TOKEN')) }
    else { TkDie "talk: give --local DIR (the emulator) or --url URL (or GITLAB_LOCAL / GITLAB_URL)`n" }
    $gl.wall0 = NowEpoch                          # freeze: the emulator's clock does not run while talk reads
    $p = $o['project']; if (-not $p) { $p = $env:GITLAB_PROJECT }
    if (-not $p) { TkDie "talk: give --project GROUP/NAME (or GITLAB_PROJECT)`n" }
    return , @($gl, $p)
}
function TkLoad($gl, $p) {
    $d = NewH
    $d.issues = L (GL-issues $gl $p (O 'state' 'all')); $d.mrs = L (GL-mrs $gl $p (O 'state' 'all'))
    $d.pipelines = L (GL-pipelines $gl $p (NewH)); $d.milestones = L (GL-milestones $gl $p)
    try { $d.project = GL-project $gl $p } catch { $d.project = NewH }
    if ($null -eq $d.project) { $d.project = NewH }
    $d.default = [string](Dor $d.project.default_branch 'develop')
    $d.issue_by = NewH; foreach ($i in $d.issues) { $d.issue_by[[string](TkIid $i)] = $i }
    try { $d.pages = GL-pages $gl $p } catch { $d.pages = $null }
    $d.gl = $gl; $d.p = $p; $d.notes = NewH
    if (-not (GL-is_local $gl)) {
        $cand = @(); foreach ($x in $d.pipelines) { if ([string]$x.ref -ceq $d.default -and [string]$x.status -ceq 'success') { $cand += , $x } }
        $last = $null; $lk = ''
        foreach ($x in $cand) { $k = [string](Dor $x.updated_at (Dor $x.created_at '')); if ($null -eq $last -or (OrdCmp $k $lk) -gt 0) { $last = $x; $lk = $k } }
        $m = NewH
        foreach ($job in @('todo', 'trace', 'vcrm', 'recipe')) {
            $txt = $null; try { $txt = GL-job_artifact $gl $p (O 'ref' $d.default 'job' $job 'path' "$job.metrics") } catch { $txt = $null }
            if ($null -eq $txt) { continue }
            foreach ($mm in [regex]::Matches([string]$txt, '(?m)^([A-Za-z_][\w:]*)\s+(-?[\d.]+)')) { $m[$mm.Groups[1].Value] = $mm.Groups[2].Value }
        }
        if ($last -and $m.Count) { if ($null -eq $last.reports) { $last.reports = NewH }; $last.reports.metrics = $m }
    }
    return $d
}
function TkStoryOf($d, $i) {
    if (-not $i -or (TkHas $i 'type::story')) { return $i }
    if ([string](Dor $i.description '') -match 'Part of #(\d+)') { $n = $Matches[1]; if ($d.issue_by.ContainsKey($n)) { return $d.issue_by[$n] } }
    return $i
}
function TkCloses($m) {
    $n = NewH
    foreach ($mm in [regex]::Matches([string](Dor $m.description ''), '(?i)\b(?:close[sd]?|fix(?:e[sd])?|resolve[sd]?|part of)\s+#(\d+)')) { $n[[string][long]$mm.Groups[1].Value] = 1 }
    if ([string](Dor $m.source_branch '') -cmatch '^(?:feature|hotfix)/(\d+)-') { $n[[string][long]$Matches[1]] = 1 }
    return , (SortNum @($n.Keys))
}
function TkSid($o, $i) { if ($i) { return ([string]$o.prefix + [string](TkIid $i)) }; return $null }
function TkTasksOf($d, $story) { $o = @(); foreach ($x in $d.issues) { $s = TkStoryOf $d $x; if ($s -and (TkIid $s) -eq (TkIid $story) -and (TkIid $x) -ne (TkIid $story)) { $o += , $x } }; return , $o }

function TkSeries($d, $o) {
    if ($null -ne $d.series) { return , $d.series }
    $s = @()
    foreach ($x in $d.pipelines) {
        if (-not ($x.reports -is [hashtable]) -or -not ($x.reports.metrics -is [hashtable]) -or [string](Dor $x.ref '') -cne $d.default) { continue }
        $s += , (O 't' (TkEp (Dor $x.finished_at (Dor $x.updated_at $x.created_at))) 'metrics' $x.reports.metrics)
    }
    $s = (SortWith $s { param($a, $b) NumCmp $a.t $b.t })
    if ($o.metrics) {
        if (-not (Test-Path -LiteralPath $o.metrics -PathType Leaf)) { TkDie "talk: cannot read $($o.metrics): No such file or directory`n" }
        $m = NewH; foreach ($l in ((ReadText $o.metrics) -split "`n")) { if ($l -cmatch '^([A-Za-z_][\w:]*)\s+(-?[\d.]+)') { $m[$Matches[1]] = $Matches[2] } }
        $t0 = 0; if ($s.Count) { $t0 = $s[$s.Count - 1].t }
        $s += , (O 't' $t0 'metrics' $m)
    }
    $d.series = $s
    return , $s
}
function TkMetricAt($series, [string]$name, $t) {
    $v = $null
    foreach ($x in $series) { if ($x.t -gt $t) { break }; if ($null -ne $x.metrics[$name]) { $v = $x.metrics[$name] } }
    return $v
}
function TkCasesAt($s, $t) {
    $tot = TkMetricAt $s 'trace_total' $t; $unv = TkMetricAt $s 'trace_unverified' $t
    if ($tot -and (PNum $tot) -ne 0 -and $null -ne $unv) { return , @(((PNum $tot) - (PNum $unv)), (PNum $tot)) }
    return , @($null, $null)
}
function TkResultsAt($s, $t) {
    $n = TkMetricAt $s 'vcrm_verified' $t; $tot = TkMetricAt $s 'vcrm_requirements' $t
    if ($tot -and (PNum $tot) -ne 0 -and $null -ne $n) { return , @((PNum $n), (PNum $tot)) }
    return , @($null, $null)
}
function TkOfPct($n, $tot) { if ($null -eq $n) { return $null }; return ('{0} of {1} ({2}%)' -f (Trunc $n), (Trunc $tot), (TkR1 (100 * [double]$n / [double]$tot))) }
function TkBaseline($f) {
    $b = NewH
    if (-not $f) { return $b }
    if (-not (Test-Path -LiteralPath $f -PathType Leaf)) { TkDie "talk: cannot read ${f}: No such file or directory`n" }
    foreach ($l in ((ReadText $f) -split "`n")) {
        if ($l -cmatch '^\s*(#|$)') { continue }
        if ($l -cmatch '^\s*(\w+)\s*=\s*([\d.]+)\s*(?:\|\s*(.*?))?\s*$') { $b[$Matches[1]] = O 'value' $Matches[2] 'label' (Dor $Matches[3] $Matches[1]) }
    }
    return $b
}

# ---------------------------------------------------------------- the journal and the lint (agile.ps1, in a child scope)
function TkAgileScope([scriptblock]$b, $arg) {
    $agile = Join-Path $script:TK_PS 'agile.ps1'
    if (-not (Test-Path -LiteralPath $agile)) { return $null }
    return (& { param($f, $blk, $a) . $f __lib; & $blk $a } $agile $b $arg)
}
function TkJournalItems($dir) {
    if (-not $dir) { return , @() }
    $file = "$dir/scrum.txt"
    $conf = "$dir/scrum.conf"
    if (Test-Path -LiteralPath $conf) { foreach ($l in ((ReadText $conf) -split "`n")) { if ($l -cmatch '^\s*journal\s*=\s*(\S+)') { $file = "$dir/" + $Matches[1] } } }
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { TkDie "talk: no journal at $file`n" }
    $items = TkAgileScope { param($f) $s = LoadScrum $f (Get-Date -Format 'yyyy-MM-dd') $null; $o = @(); foreach ($k in @($s.items.Keys)) { $it = $s.items[$k]; $o += , @{ id = $it.id; state = $it.state; owner = $it.owner; title = $it.title } }; , $o } $file
    return , @($items)
}
function TkPrefix($o, $items) {
    if ($null -ne $o.prefix) { return $o.prefix }
    if ($env:TALK_PREFIX) { return $env:TALK_PREFIX }
    $c = NewH
    foreach ($it in $items) { if ([string]$it.id -cmatch '^([A-Z][A-Z0-9_]*-)\d+$') { $k = $Matches[1]; if ($c.ContainsKey($k)) { $c[$k]++ } else { $c[$k] = 1 } } }
    if ($c.Count) { $best = SortWith @($c.Keys) { param($a, $b) $x = NumCmp $c[$b] $c[$a]; if ($x) { $x } else { OrdCmp $a $b } }; return $best[0] }
    $proj = $o.project; if (-not $proj) { $proj = $env:GITLAB_PROJECT }; if (-not $proj) { $proj = 'X' }
    $g = ($proj -split '/')[0]
    return ($g.Substring(0, (TkMin (2) ($g.Length))).ToUpperInvariant() + '-')
}

# ---------------------------------------------------------------- standup
function TkStandup($gl, $p, $o) {
    $u = $o.as; if (-not $u) { TkDie "talk: standup needs --as USER`n" }
    $items = TkJournalItems $o.journal
    $o.prefix = TkPrefix $o $items
    $d = TkLoad $gl $p
    $date = Dor $o.date (TkDay (GL-epoch $gl))
    if ($date -cnotmatch '^\d{4}-\d\d-\d\d$') { TkDie "talk: --date is YYYY-MM-DD, not '$date'`n" }
    $since = TkPrevWorkday $date
    $from = TkEp $since; $to = TkEp $date
    $why = @()
    $closed = @(); foreach ($x in $d.issues) { if ([string]$x.state -ceq 'closed' -and (TkAssigned $x $u) -and (TkIn $x.closed_at $from $to)) { $closed += , $x } }
    $merged = @(); $opened = @(); $reviewed = @()
    foreach ($m in $d.mrs) {
        $au = TkUser $m.author
        if ($au -ceq $u -and [string]$m.state -ceq 'merged' -and (TkIn $m.merged_at $from $to)) { $merged += , $m }
        if ($au -ceq $u -and (TkIn $m.created_at $from $to) -and [string]$m.state -cne 'merged') { $opened += , $m }
        if ($au -cne $u) {
            $hit = $false
            foreach ($nt in (L $m.notes)) { if ((TkUser $nt.author) -ceq $u -and (TkIn $nt.created_at $from $to)) { $hit = $true } }
            if (-not $hit) { foreach ($ap in (L $m.approved_by)) { if ((TkUser $ap.user) -ceq $u -and (TkIn $ap.approved_at $from $to)) { $hit = $true } } }
            if ($hit) { $reviewed += , $m }
        }
    }
    $score = NewH
    foreach ($x in $closed) { $k = [string](TkIid (TkStoryOf $d $x)); $score[$k] = (PNum $score[$k]) + 2 }
    foreach ($m in (@($merged) + @($opened))) { foreach ($n in (TkCloses $m)) { $n = [string]$n; if ($d.issue_by.ContainsKey($n)) { $k = [string](TkIid (TkStoryOf $d $d.issue_by[$n])); $score[$k] = (PNum $score[$k]) + 1 } } }
    $story = $null
    if ($score.Count) {
        $top = (SortWith @($score.Keys) { param($a, $b) $x = NumCmp $score[$b] $score[$a]; if ($x) { $x } else { NumCmp $a $b } })[0]
        $story = $d.issue_by[[string]$top]
    }
    $y = $null
    if ($story) {
        $tasks = TkTasksOf $d $story
        $done = 0; foreach ($x in $tasks) { if ([string]$x.state -ceq 'closed') { $done++ } }
        $title = TkShort $story.title 38
        $series = TkSeries $d $o
        $t0 = TkMetricAt $series 'todo_lines' ($from - 1); $t1 = TkMetricAt $series 'todo_lines' ($to - 1)
        $mineOpen = @(); foreach ($m in $opened) { foreach ($n in (TkCloses $m)) { $n = [string]$n; if ($d.issue_by.ContainsKey($n) -and (TkIid (TkStoryOf $d $d.issue_by[$n])) -eq (TkIid $story)) { $mineOpen += , $m; break } } }
        if ($merged.Count -and $null -ne $t0 -and $null -ne $t1 -and (PNum $t1) -lt (PNum $t0)) {
            $num = '{0} TODOs closed, {1} left' -f (Trunc ((PNum $t0) - (PNum $t1))), (Trunc (PNum $t1))
            $why += "todo_lines on $($d.default): $(PStr $t0) -> $(PStr $t1)"
        } elseif ([string]$story.state -ceq 'closed' -and (TkIn $story.closed_at $from $to)) {
            $num = 'done' + $(if ($tasks.Count) { ' (' + (TkPlural $tasks.Count 'task') + ')' } else { '' })
        } elseif ($tasks.Count -and $done) { $num = '{0} of {1} tasks done' -f $done, $tasks.Count }
        elseif ($merged.Count) { $num = (TkPlural $merged.Count 'change') + ' merged, checks green' }
        elseif ($mineOpen.Count) { $ids = @(); foreach ($m in $mineOpen) { $ids += ('!' + (TkIid $m)) }; $num = ($ids -join ', ') + ' up for review' }
        elseif ($tasks.Count) { $num = '{0} of {1} tasks done' -f $done, $tasks.Count }
        else { $num = (TkPlural $closed.Count 'item') + ' closed' }
        $y = (TkSid $o $story) + " ${title}: $num."
        foreach ($x in $closed) { $why += ('#' + (TkIid $x) + ' closed') }
        foreach ($x in $merged) { $why += ('!' + (TkIid $x) + ' merged') }
        foreach ($x in $opened) { $why += ('!' + (TkIid $x) + ' opened') }
    }
    if ($reviewed.Count) {
        $ids = @(); $lim = (TkMin (2) ($reviewed.Count - 1)); for ($k = 0; $k -le $lim; $k++) { $ids += ('!' + (TkIid $reviewed[$k])) }
        $r = 'Reviewed ' + ($ids -join ', ') + '.'
        $y = if ($null -ne $y) { "$y $r" } else { $r }
        foreach ($x in $reviewed) { $why += ('reviewed !' + (TkIid $x)) }
    }
    if ($null -ne $y -and $y -cnotmatch ([regex]::Escape([string]$o.prefix) + '\d')) {
        $m = $reviewed[0]; $cl = TkCloses $m; $s = $null
        if ($cl.Count -and $d.issue_by.ContainsKey([string]$cl[0])) { $s = TkStoryOf $d $d.issue_by[[string]$cl[0]] }
        if ($s) { $y = (TkSid $o $s) + " $y" }
    }
    if ($null -eq $y) { $y = 'none' }

    $mine = @(); foreach ($x in $d.issues) { if ([string]$x.state -ceq 'opened' -and (TkAssigned $x $u) -and -not (TkHas $x 'workflow::blocked') -and -not (TkHas $x 'type::story')) { $mine += , $x } }
    $cur = $null; foreach ($m in $d.milestones) { if ((OrdCmp ([string](Dor $m.start_date '')) $date) -le 0 -and (OrdCmp ([string](Dor $m.due_date '9999')) $date) -ge 0) { $cur = $m; break } }
    $inCur = { param($x) if ($cur -and $x.milestone -and [string]$x.milestone.title -ceq [string]$cur.title) { 1 } else { 0 } }
    $ip = { param($x) if (TkHas $x 'workflow::in-progress') { 1 } else { 0 } }
    $pick = (SortWith $mine { param($a, $b)
        $c = NumCmp (& $ip $b) (& $ip $a); if ($c) { return $c }
        $c = NumCmp (& $inCur $b) (& $inCur $a); if ($c) { return $c }
        $c = OrdCmp ([string](Dor $a.due_date '9999')) ([string](Dor $b.due_date '9999')); if ($c) { return $c }
        return (NumCmp (TkIid $a) (TkIid $b)) })
    $t = 'none'
    if ($pick.Count) {
        $task = $pick[0]
        $s = TkStoryOf $d $task
        $by = $task.due_date
        if ($null -eq $by -and $task.milestone) { foreach ($m in $d.milestones) { if ([string]$m.title -ceq [string]$task.milestone.title) { $by = $m.due_date; break } } }
        $when = ''
        if ($by) { if ((TkEp $by) - (TkEp $date) -le 6 * 86400 -and (TkEp $by) -ge (TkEp $date)) { $when = ', by ' + (TkDow $by) } else { $when = ', by ' + (TkNiceDate $by).Substring(4) } }
        $t = (TkSid $o $s) + ' ' + (TkLcFirst (TkShort $task.title 50)) + $when
        $why += ('today: #' + (TkIid $task) + $(if ((TkIid $s) -ne (TkIid $task)) { ' (story #' + (TkIid $s) + ')' } else { '' }))
    } elseif ($items.Count) {
        $name = $null
        if ((GL-is_local $gl) -and $gl.st.users[$u]) { $name = $gl.st.users[$u].name }
        if (-not $name) { $name = $u.Substring(0, 1).ToUpperInvariant() + $u.Substring(1) }
        $cands = @(); foreach ($it in $items) { $ow = ([string](Dor $it.owner '')).ToLowerInvariant(); if ([string]$it.state -ceq 'committed' -and ($ow.StartsWith($name.ToLowerInvariant()) -or $ow.StartsWith($u))) { $cands += , $it } }
        if ($cands.Count) { $it = (SortWith $cands { param($a, $b) OrdCmp ([string]$a.id) ([string]$b.id) })[0]; $t = [string]$it.id + ' ' + (TkLcFirst (TkShort $it.title 50)) }
    }

    $blk = @(); foreach ($x in $d.issues) { if ([string]$x.state -ceq 'opened' -and (TkAssigned $x $u) -and (TkHas $x 'workflow::blocked')) { $blk += , $x } }
    $b = 'none'
    if ($blk.Count) {
        $x = $blk[0]; $rw = TkBlocker $x $d
        $b = (TkSid $o (TkStoryOf $d $x)) + ' ' + (TkLcFirst (TkShort $x.title 40)) + ' blocked: ' + $rw[0] + ' -- need: ' + $rw[1]
        $why += ('blocked: #' + (TkIid $x))
    }
    if ($t -cne 'none' -and $t -cnotmatch '\.$') { $t += '.' }
    $line = "Y $y T $t B $b"
    $lint = TkAgileScope { param($a) LintMessage $a[0] @{ example = $a[1] } } @($line, ($o.prefix + '12'))
    $note = ''
    if ($o.chat) {
        $now = Get-Date
        $hh = $now.Hour % 12; if ($hh -eq 0) { $hh = 12 }
        TkOut ('[{0}:{1:00} {2}] {3}' -f $hh, $now.Minute, $(if ($now.Hour -lt 12) { 'AM' } else { 'PM' }), (Dor $o.name (TkDisplayName $gl $d $u))) + "`n"
    }
    TkOut "$line`n"
    $note += "# draft for $u on " + (TkNiceDate $date) + ' (since ' + (TkNiceDate $since) + "): edit it, then post it yourself`n"
    if ($o.why -and $why.Count) { $note += '# from: ' + ($why -join ', ') + "`n" }
    if ($lint) { $note += '# lint: ' + $(if ($lint.ok -and @($lint.warnings).Count -eq 0) { 'ok' } else { (@(@($lint.errors) + @($lint.warnings)) -join '; ') }) + "`n" }
    $ynum = $y -creplace ([regex]::Escape([string]$o.prefix) + '\d+'), ''
    if ($y -cne 'none' -and $y -cnotmatch '\d.*\d|\d\D*$' -and $ynum -cnotmatch '\d') { $note += "# no number in Y: add one (how many, how much, by when)`n" }
    if ($o.chat) { $script:TK_NOTE = $note } else { TkOut $note }
    return 0
}
function TkDisplayName($gl, $d, $u) {
    foreach ($x in (@($d.issues) + @($d.mrs))) {
        foreach ($pp in (@(L $x.assignees) + @($(if ($x.author) { , $x.author } else { @() })))) {
            if (([string](Dor $pp.username '')).ToLowerInvariant() -ceq $u.ToLowerInvariant() -and [string](Dor $pp.name '') -cmatch '\S') { return $pp.name }
        }
    }
    if ((GL-is_local $gl) -and $gl.st.users[$u] -and $gl.st.users[$u].name) { return $gl.st.users[$u].name }
    return ($u.Substring(0, 1).ToUpperInvariant() + $u.Substring(1))
}
function TkBlocker($x, $d) {
    $notes = $x.notes
    if ($null -eq $notes) {
        $k = [string](TkIid $x)
        if ($d -and $d.gl) { if (-not $d.notes.ContainsKey($k)) { try { $d.notes[$k] = L (GL-issue_notes $d.gl $d.p (TkIid $x)) } catch { $d.notes[$k] = @() } }; $notes = $d.notes[$k] } else { $notes = @() }
    }
    $texts = @()
    $nl = @(L $notes); for ($k = $nl.Count - 1; $k -ge 0; $k--) { if (-not (Tru $nl[$k].system)) { $texts += [string](Dor $nl[$k].body '') } }
    $texts += [string](Dor $x.description '')
    $w = $null; $n = $null
    foreach ($tx in $texts) {
        if ($null -eq $n -and $tx -match '\bneed(?:ed|s)?\s*:\s*([^\n.]+)') { $n = $Matches[1] }
        if ($null -eq $w -and $tx -match '\b(?:blocked by|waiting (?:on|for))\s*:?\s*([^\n.]+?)(?:\s*--|\s+need:|[\n.]|$)') { $w = $Matches[1] }
    }
    return , @((Dor $w 'see the issue'), (Dor $n 'help to unblock it'))
}

# ---------------------------------------------------------------- review
function TkSprintNum([string]$title, [string]$n) { return ($title -match ('\bSprint\s*' + [regex]::Escape($n) + '$')) }
function TkSprintBounds($d, [string]$n) {
    $ms = @(); foreach ($m in $d.milestones) { if ([string](Dor $m.title '') -match '\bSprint\s*\d+$') { $ms += , $m } }
    $ms = (SortWith $ms { param($a, $b) OrdCmp ([string](Dor $a.start_date '')) ([string](Dor $b.start_date '')) })
    $m = $null; foreach ($x in $ms) { if (TkSprintNum $x.title $n) { $m = $x; break } }
    if (-not $m) { TkDie "talk: no milestone 'Sprint $n'`n" }
    $prev = $null; foreach ($x in $ms) { if (TkSprintNum $x.title ([string]([long]$n - 1))) { $prev = $x; break } }
    $next = $null; foreach ($x in $ms) { if ((OrdCmp ([string](Dor $x.start_date '')) ([string](Dor $m.due_date ''))) -gt 0) { $next = $x; break } }
    if (-not $m.start_date) { TkDie "talk: milestone '$($m.title)' has no start date`n" }
    if (-not $m.due_date) { TkDie "talk: milestone '$($m.title)' has no due date`n" }
    return , @($m, $prev, $next, (TkEp $m.start_date), ((TkEp $m.due_date) + 3 * 86400))
}
function TkHeadline($d, $series, $t) {
    $c = TkCasesAt $series $t; $r = TkResultsAt $series $t
    $drs = 0; $blk = 0
    foreach ($i in $d.issues) {
        $cr = TkEp $i.created_at
        $open = $null -ne $cr -and $cr -le $t -and (-not $i.closed_at -or (TkEp $i.closed_at) -gt $t)
        if ($open -and ((TkHas $i 'type::discrepancy') -or (TkHas $i 'prime-change'))) { $drs++ }
        if ([string]$i.state -ceq 'opened' -and (TkHas $i 'workflow::blocked')) { $blk++ }
    }
    return (O 'todo' (TkMetricAt $series 'todo_lines' $t) 'cases' $c[0] 'cases_tot' $c[1] 'res' $r[0] 'res_tot' $r[1] 'drs' $drs 'blocked' $blk)
}
function TkChange($now, $was) {
    if ($null -eq $now -or $null -eq $was) { return '' }
    $c = (PNum $now) - (PNum $was)
    if ($c -eq 0) { return ' (no change)' }
    return (' ({0}{1} from {2})' -f $(if ($c -gt 0) { 'up ' } else { 'down ' }), (NumStr (PNum (FmtF ((TkAbs $c)) 1))), (PStr $was))
}
function TkPace($now, $was) {
    if ($null -eq $was -or (PNum $was) -le (PNum $now)) { return 'unknown pace' }
    $s = (PNum $now) / ((PNum $was) - (PNum $now))
    if ($s -le 1) { return 'about one more sprint' }
    return ('about {0} more sprints' -f (Trunc ($s + 0.999)))
}
function TkReview($gl, $p, $o) {
    $n = $o.sprint; if ($null -eq $n) { TkDie "talk: review needs --sprint N`n" }
    if ($n -cnotmatch '^\d+$') { TkDie "talk: --sprint is a number, not '$n'`n" }
    $d = TkLoad $gl $p
    $sb = TkSprintBounds $d $n
    $m = $sb[0]; $next = $sb[2]; $start = $sb[3]; $end = $sb[4]
    $series = TkSeries $d $o
    $base = TkBaseline $o.baseline
    $h = TkHeadline $d $series $end; $hp = TkHeadline $d $series ($start - 1)
    $desc = @([string](Dor $m.description '') -split "`n")
    $goal = $null
    foreach ($l in $desc) { $s = $l -ireplace '^\s*(?:[-*]\s*)?\*{0,2}(?:goal|question)\s*:?\s*\*{0,2}\s*:?\s*', ''; if ($s -match '\?\s*$') { $goal = $s; break } }
    $gline = $null
    foreach ($l in $desc) { if ($l -imatch '^\s*(?:\*\*)?goal') { $gline = $l -ireplace '^\s*(?:\*\*)?goal(?:\*\*)?\s*:\s*', ''; break } }
    $question = if ($null -ne $goal) { $goal } elseif ($gline) { "Did we do what we set out to do: ${gline}?" } else { "What did Sprint $n change for the model, and how do we know?" }
    $merged = @(); foreach ($x in $d.mrs) { if ([string]$x.state -ceq 'merged' -and (TkIn $x.merged_at $start $end)) { $merged += , $x } }
    $green = @(); foreach ($x in $merged) { $pl = $x.head_pipeline; if (-not $pl -or [string](Dor $pl.status 'success') -ceq 'success') { $green += , $x } }
    $stories = @(); foreach ($x in $d.issues) { if ((TkHas $x 'type::story') -and $x.milestone -and [string]$x.milestone.title -ceq [string]$m.title) { $stories += , $x } }
    $sdone = 0; foreach ($x in $stories) { if ([string]$x.state -ceq 'closed') { $sdone++ } }
    $an = $null; try { $an = GL-analytics $gl $p (O 'since' (TkDay $start) 'until' (TkDay ($end - 86400)) 'by' 'sprint') } catch { $an = $null }
    if ($null -eq $an) { $an = NewH }
    $rev = $null; $lead = $null; $plmin = $null
    if ($an.mrs) { $rev = $an.mrs.review_median }; if ($an.dora) { $lead = $an.dora.lead_median }; if ($an.ci) { $plmin = $an.ci.median_minutes }
    $pages = $null; if ($d.pages -is [hashtable]) { $pages = $d.pages.url }
    $jobs = NewH
    foreach ($pl in $d.pipelines) { if ([string](Dor $pl.ref '') -ceq $d.default) { foreach ($j in (L $pl.jobs)) { if ([string](Dor $j.status '') -ceq 'success') { $jobs[[string]$j.name] = 1 } } } }
    $md = [bool]$o.md
    $hdr = { param($t) if ($md) { "## $t" } else { $t.ToUpperInvariant() } }
    $out = @()
    $out += ($(if ($md) { '# ' } else { '' }) + "Sprint $n review -- demo script (draft: edit before the meeting)"); $out += ''
    $out += (& $hdr '1. The question this sprint answered'); $out += "`"$question`""
    $out += ('Answer in one line: {0} of {1} stories done{2}.' -f $sdone, $stories.Count, $(if ($null -ne $h.cases) { ', {0} of {1} requirements with a verification case' -f (Trunc $h.cases), (Trunc $h.cases_tot) } else { '' })); $out += ''
    $out += (& $hdr '2. The same four numbers as every review')
    $out += ('- TODO lines left: {0}{1}' -f $(if ($null -ne $h.todo) { PStr $h.todo } else { 'n/a (no todo metrics yet)' }), (TkChange $h.todo $hp.todo))
    $op = TkOfPct $h.cases $h.cases_tot
    $out += ('- Requirements with a verification case: {0}{1}' -f $(if ($null -ne $op) { $op } else { 'n/a (no trace metrics yet)' }), (TkChange $h.cases $hp.cases))
    if ($null -ne $h.res) { $out += ('    (a different measure: requirements with a passing recorded result, from the VCRM: {0} of {1}{2})' -f (Trunc $h.res), (Trunc $h.res_tot), (TkChange $h.res $hp.res)) }
    $out += ('- Open discrepancy reports and prime changes: {0}{1}' -f $h.drs, (TkChange $h.drs $hp.drs))
    $out += ('- Blocked items: {0}' -f $h.blocked); $out += ''
    $out += (& $hdr '3. Show the output, not the tool')
    $out += ('- The model site: ' + $(if ($pages) { $pages } else { '(not published yet: the pages job on the default branch publishes it)' }))
    if ($jobs.ContainsKey('vcrm')) { $out += '- The verification matrix (vcrm.html on the site, from the vcrm job)' }
    if ($jobs.ContainsKey('docs') -or $jobs.ContainsKey('pages')) { $out += '- The generated documents (docs/ on the site: part tree, trace, data exchange tables)' }
    $out += ('- {0} merged this sprint, {1} with green checks; show one going red to green:' -f (TkPlural $merged.Count 'change'), $green.Count)
    $lim = (TkMin (3) ($green.Count - 1)); for ($k = 0; $k -le $lim; $k++) { $out += ('    !' + (TkIid $green[$k]) + ' ' + (TkShort $green[$k].title 60)) }
    $out += ''
    $out += (& $hdr '4. One before-and-after')
    $ba = @()
    foreach ($e in @(@('review_hours', 'from proposing a change to the first review', $rev), @('lead_hours', 'from first edit to accepted change', $lead))) {
        $k = $e[0]; $what = $e[1]; $now = $e[2]
        if ($null -eq $now) { continue }
        if ($base[$k]) { $ba += ('- Before: {0} took {1} ({2}). Now: {3}, median this sprint.' -f $what, (TkHours $base[$k].value), $base[$k].label, (TkHours $now)) }
        else { $ba += ('- Now: {0} takes {1} (median). Before: [the document-era number -- put it in a --baseline file].' -f $what, (TkHours $now)) }
    }
    $pm = if ($null -ne $plmin) { PNum $plmin } else { 4 }
    if ($jobs.ContainsKey('trace') -or $jobs.ContainsKey('vcrm')) {
        $bt = if ($base['trace_hours']) { $base['trace_hours'].label + ', ' + $base['trace_hours'].value + ' h' } else { '[how long "which requirements are unverified?" used to take]' }
        $ba += ('- Before: {0}. Now: the trace check answers it on every change, in about {1}.' -f $bt, (TkHours ($pm / 60)))
    }
    if ($ba.Count) { $out += $ba } else { $out += '- [Before: ... Now: ... -- one number each, from a --baseline file and analytics]' }
    $out += ''
    $out += (& $hdr '5. One safe live change (on a scratch branch, never on develop)')
    if ($jobs.ContainsKey('trace') -or $jobs.ContainsKey('vcrm')) { $out += ('- Delete one satisfy line on a scratch branch and open a draft merge request: in about {0} the trace check names the requirement that lost its design. Close the merge request afterwards.' -f (TkHours ($pm / 60))) }
    else { $out += ('- Misspell one part type on a scratch branch and open a draft merge request: in about {0} the lint check points at the line. Close the merge request afterwards.' -f (TkHours ($pm / 60))) }
    $out += ''
    $out += (& $hdr '6. What it means for the next milestone')
    if ($next) {
        $tail = if ($null -ne $h.todo) { (PStr $h.todo) + " TODO lines to go; at this sprint's pace that is " + (TkPace $h.todo $hp.todo) + '.' } else { '[what this sprint makes possible next]' }
        $out += ('- {0} starts {1}: {2}' -f $next.title, (TkNiceDate $next.start_date), $tail)
    } else { $out += '- [the next milestone and what this sprint makes possible]' }
    $out += ''
    $out += (& $hdr '7. The ask')
    $blk = @(); foreach ($x in $d.issues) { if ([string]$x.state -ceq 'opened' -and (TkHas $x 'workflow::blocked')) { $blk += , $x } }
    if ($blk.Count) { foreach ($x in $blk) { $rw = TkBlocker $x $d; $out += ('- Need: ' + $rw[1] + ' (#' + (TkIid $x) + ' ' + (TkShort $x.title 40) + ' is blocked: ' + $rw[0] + ')') } }
    else { $out += '- [A decision on ___ by ___, or help with ___. Name it, with a date.]' }
    $out += ''
    $tb = ''
    if ($null -ne $h.todo) { $tb = ', ' + (PStr $h.todo) + ' TODO lines left'; if ($null -ne $hp.todo -and (PNum $hp.todo) -gt (PNum $h.todo)) { $tb += (' (down {0})' -f (Trunc ((PNum $hp.todo) - (PNum $h.todo)))) } }
    $cb = if ($null -ne $h.cases) { ', ' + (NumStr $h.cases) + ' of ' + (NumStr $h.cases_tot) + ' requirements with a verification case' } else { '' }
    $s30 = 'Sprint {0}: {1} of {2} stories done{3}{4}. {5}' -f $n, $sdone, $stories.Count, $tb, $cb, $(if ($blk.Count) { 'We need help with ' + (TkPlural $blk.Count 'blocked item') + '.' } else { 'Nothing blocks us.' })
    $out += (& $hdr '30-second version'); $out += $s30; $out += ''
    $tail = ''; if ($null -ne $h.todo -and $null -ne $hp.todo -and (PNum $hp.todo) -gt (PNum $h.todo)) { $tail = ' and {0} TODO lines' -f (Trunc ((PNum $hp.todo) - (PNum $h.todo))) }
    $out += (& $hdr '1-sentence version'); $out += ('Sprint {0} moved the model forward by {1}{2}.' -f $n, (TkPlural $sdone 'story'), $tail)
    TkOut (($out -join "`n") + "`n")
    return 0
}

# ---------------------------------------------------------------- weekly
function TkWeekly($gl, $p, $o) {
    $d = TkLoad $gl $p
    $date = Dor $o.date (TkDay (GL-epoch $gl))
    if ($date -cnotmatch '^\d{4}-\d\d-\d\d$') { TkDie "talk: --date is YYYY-MM-DD, not '$date'`n" }
    $t = (TkEp $date) + 86399
    $wd = ((GmTime (TkEp $date))[6] + 6) % 7
    $mon = (TkEp $date) - $wd * 86400
    $series = TkSeries $d $o
    $h = TkHeadline $d $series $t; $hp = TkHeadline $d $series ($mon - 1)
    $done = @(); foreach ($x in $d.issues) { if ((TkHas $x 'type::story') -and [string]$x.state -ceq 'closed' -and (TkIn $x.closed_at $mon ($t + 1))) { $done += , $x } }
    $merged = @(); foreach ($x in $d.mrs) { if ([string]$x.state -ceq 'merged' -and (TkIn $x.merged_at $mon ($t + 1))) { $merged += , $x } }
    $cur = $null; foreach ($m in $d.milestones) { if ((OrdCmp ([string](Dor $m.start_date '')) $date) -le 0 -and (OrdCmp ([string](Dor $m.due_date '9999')) $date) -ge 0) { $cur = $m; break } }
    $on = 'On track'; $why = ''
    if ($cur -and $cur.start_date -and $cur.due_date) {
        $pts = 0; $dn = 0
        foreach ($x in $d.issues) { if ((TkHas $x 'type::story') -and $x.milestone -and [string]$x.milestone.title -ceq [string]$cur.title) { $w = PNum $x.weight; if (-not $w) { $w = 1 }; $pts += $w; if ([string]$x.state -ceq 'closed') { $dn += $w } } }
        $frac = ((TkEp $date) - (TkEp $cur.start_date) + 86400) / ((TkEp $cur.due_date) - (TkEp $cur.start_date) + 86400)
        if ($pts -and $frac -gt 0.5 -and $dn / $pts -lt 0.8 * $frac) { $on = 'At risk'; $why = (' -- {0}% of the sprint is done with {1}% of the time gone' -f (Trunc (100 * $dn / $pts)), (Trunc (100 * $frac))) }
    }
    if ($h.blocked -and $on -ceq 'At risk') { $on = 'Needs help' }
    $devp = @(); foreach ($x in $d.pipelines) { if ([string](Dor $x.ref '') -ceq $d.default) { $devp += , $x } }
    $devp = (SortWith $devp { param($a, $b) NumCmp (TkEp $a.created_at) (TkEp $b.created_at) })
    $last = if ($devp.Count) { $devp[$devp.Count - 1] } else { $null }
    $risk = @()
    if ($last -and [string](Dor $last.status '') -ceq 'failed') { $risk += ('The automated checks on the shared model are failing since ' + (TkNiceDate $last.created_at) + '.') }
    $asks = @()
    foreach ($x in $d.issues) { if ([string]$x.state -ceq 'opened' -and (TkHas $x 'workflow::blocked')) { $rw = TkBlocker $x $d; $risk += ('#' + (TkIid $x) + ' ' + (TkShort $x.title 50) + ' is blocked: ' + $rw[0] + '.') } }
    foreach ($x in $d.issues) { if ([string]$x.state -ceq 'opened' -and (TkHas $x 'type::discrepancy') -and $t - (TkEp $x.created_at) -gt 14 * 86400) { $risk += ('Discrepancy report #' + (TkIid $x) + ' to the prime is ' + (Trunc (($t - (TkEp $x.created_at)) / 86400)) + ' days old.') } }
    foreach ($x in $d.issues) { if ([string]$x.state -ceq 'opened' -and (TkHas $x 'workflow::blocked')) { $rw = TkBlocker $x $d; $asks += ($rw[1] + ' (#' + (TkIid $x) + ')') } }
    $md = [bool]$o.md
    $hdr = { param($s) if ($md) { "## $s" } else { "${s}:" } }
    $nums = @(('{0} finished this week ({1} accepted into the model)' -f (TkPlural $done.Count 'story'), (TkPlural $merged.Count 'change')))
    if ($null -ne $h.todo) { $nums += ('{0} TODO lines left to port by hand{1}' -f (Trunc (PNum $h.todo)), (TkChange $h.todo $hp.todo)) }
    if ($null -ne $h.cases) { $nums += ('Requirements with a verification case: {0}{1}' -f (TkOfPct $h.cases $h.cases_tot), (TkChange $h.cases $hp.cases)) }
    $nums += ('{0} open discrepancy reports and prime changes' -f $h.drs)
    $out = @(($(if ($md) { '# ' } else { '' }) + ('Weekly note, week of {0} -- {1}{2}' -f (TkNiceDate (TkDay $mon)).Substring(4), $on, $why)), '')
    $tb = ''; if ($null -ne $h.todo -and $null -ne $hp.todo -and (PNum $hp.todo) -gt (PNum $h.todo)) { $tb = ', and the hand-port list fell from {0} to {1}' -f (Trunc (PNum $hp.todo)), (Trunc (PNum $h.todo)) }
    $out += ('{0}: {1} finished this week{2}.' -f $on, (TkPlural $done.Count 'story'), $tb); $out += ''
    $out += (& $hdr 'The numbers'); $lim = (TkMin (2) ($nums.Count - 1)); for ($k = 0; $k -le $lim; $k++) { $out += ('- ' + $nums[$k]) }
    if ($null -ne $h.res) { $out += ('- Separately: {0} of {1} requirements have a passing recorded result (VCRM)' -f (Trunc $h.res), (Trunc $h.res_tot)) }
    $out += ''
    $out += (& $hdr 'Risks'); if ($risk.Count) { foreach ($r in $risk) { $out += "- $r" } } else { $out += '- None this week.' }; $out += ''
    $out += (& $hdr 'Asks'); if ($asks.Count) { foreach ($r in $asks) { $out += "- $r" } } else { $out += '- None this week.' }; $out += ''
    $out += '(The weekly quad -- daily.pl quad -- has the detail; this note is the headline.)'
    TkOut (($out -join "`n") + "`n")
    return 0
}

# ---------------------------------------------------------------- translate
$script:TK_GLOSSARY = @(
    , @('merge requests?|MRs?', 'proposed change', 'say what the change does for the model', @('proposed change', 'proposed changes'))
    , @('pull requests?', 'proposed change', 'say what the change does for the model', @('proposed change', 'proposed changes'))
    , @('VCRMs?', 'verification matrix', 'say how many requirements are verified', @('verification matrix', 'verification matrices'))
    , @('DRs?', 'discrepancy report', 'say what the prime must fix and by when', @('discrepancy report', 'discrepancy reports'))
    , @('prime drops?', 'prime model update', 'say what the update changes for us', @('prime model update', 'prime model updates'))
    , @('TODO lines?|TODOs?', 'hand-port item', 'say how many are closed and how many are left', @('hand-port item', 'hand-port items'))
    , @('artifacts?', 'generated report', 'name the report (trace report, data exchange table ...)', @('generated report', 'generated reports'))
    , @('runners?', 'check machine', 'say what it lets the team do (run the checks on every change)', @('check machine', 'check machines'))
    , @('code ?owners', 'approvers for that part of the model', 'name the person who approves', $null)
    , @('green pipelines?|(?:the )?pipeline (?:is|was) green', 'all automated checks passed', 'say what that proves (e.g. "no grammar or lint errors")', $null)
    , @('red pipelines?|(?:the )?pipeline (?:is|was) red', 'an automated check failed', 'say what the check caught and when it will be fixed', $null)
    , @('CI/CD pipelines?|CI pipelines?|pipelines?|CI', 'automated checks', 'say which check and what it caught or confirmed', $null)
    , @('trace coverage', 'requirements linked to a design and a test', 'give it as "X of Y requirements"', $null)
    , @('SIL', 'testing with simulated hardware', 'say what was tested and the result', $null)
    , @('HIL', 'testing with real hardware', 'say what was tested and the result', $null)
    , @('baselines?|tags?', 'frozen, approved version', 'name the version and what it is for', $null)
    , @('lint (?:errors?|warnings?|failures?)|grammar errors?|validation failures?', 'errors the automated checks found', 'say how many, and that they were caught before review', $null)
    , @('technical debt|refactor(?:ing|ed)?', 'cleanup that keeps future changes cheap', 'say what gets cheaper (e.g. "one edit instead of ten")', $null)
    , @('rebas(?:e|ed|ing)', 'brought my change up to date', 'say what it achieved, or leave it out: nobody needs to hear it', $null)
    , @('feature branch(?:es)?|branch(?:es)?', 'private working copy of the model', 'usually leave it out: say what the change does', $null)
    , @('commit(?:s|ted)?', 'saved change', 'usually leave it out: say what the change does', $null)
    , @('merg(?:e|ed|ing)', 'accepted into the shared model', 'say what is now in the model', $null)
    , @('vendor branch', "the prime's model as delivered", 'say "the prime''s delivery"', $null)
    , @('orphans?', 'requirements nothing in the design satisfies', 'give it as "N requirements have no design"', $null)
    , @('drift', 'wording that differs between DOORS and the model', 'say which requirement and who fixes it', $null)
    , @('\.gitlab-ci\.yml|YAML', 'the list of automated checks', 'usually leave it out', $null)
)
$script:TK_OUTCOME = '(?i)\b(done|fail(?:ed|s)?|close[sd]?|closing|caught|ready|passed|merged|accepted|saved|reduced|increased|cut|up|down|complete|completed|decided|fixed|finished|delivered|approved|published|found|verified|green|blocked|need|needs|by (?:mon|tue|wed|thu|fri|\w+ \d))\b'
$script:TK_REF = '(?:\b[A-Z][A-Z0-9_]{0,9}-\d+\b|[!#]\d+\b)'
function TkReplaceAll([string]$text, [string]$re, [scriptblock]$f) {          # s/re/f(match)/g without a MatchEvaluator
    $ms = [regex]::Matches($text, $re)
    if ($ms.Count -eq 0) { return $text }
    $o = ''; $at = 0
    foreach ($m in $ms) { $o += $text.Substring($at, $m.Index - $at); $o += (& $f $m); $at = $m.Index + $m.Length }
    return $o + $text.Substring($at)
}
function TkPlainSwap([string]$text, $g) {
    $script:TK_KEPT = @()
    $text = TkReplaceAll $text ('(`[^`]*`|' + $script:TK_REF + ')') { param($m) $script:TK_KEPT += $m.Groups[1].Value; [string][char]0 + [string]($script:TK_KEPT.Count - 1) + [string][char]0 }
    foreach ($e in $g) {
        if ($null -eq $e[3]) { continue }
        $sw = $e[3]
        $text = TkReplaceAll $text ('(?i)\b(' + $e[0] + ')\b') { param($m) $w = $m.Groups[1].Value
            $pl = if ($w -cmatch 's$' -and $w -notmatch '^(?:VCRM|DR|MR)$') { 1 } else { 0 }
            $r = $sw[$pl]
            if ($w -cmatch '^[A-Z][a-z]') { $r.Substring(0, 1).ToUpperInvariant() + $r.Substring(1) } else { $r } }
    }
    return (TkReplaceAll $text ([string][char]0 + '(\d+)' + [string][char]0) { param($m) $script:TK_KEPT[[int]$m.Groups[1].Value] })
}
function TkSuggestion([string]$s, $terms) {
    $refs = @(); foreach ($m in [regex]::Matches($s, $script:TK_REF)) { $refs += $m.Value }
    $num = $null
    if ($s -cmatch '\b(\d[\d.,]*%?(?:\s+(?:of\s+\d+\s+)?[A-Za-z][\w-]*(?:\s+(?:lines?|items?))?)?)') { $num = TkPlainSwap $Matches[1] $script:TK_GLOSSARY }
    $nouns = @(); foreach ($t in $terms) { if ($null -ne $t[3]) { $nouns += $t[1] } }
    $topic = ''; if ($nouns.Count) { $topic = ($nouns[0..((TkMin (1) ($nouns.Count - 1)))] -join ', ') }
    $done = 'Done: ' + $(if ($refs.Count) { $refs[0] + ' ' } else { '' }) + '[what is now true' + $(if ($topic) { " -- topic: $topic" } else { '' }) + ']' + ' (' + $(if ($null -ne $num) { $num } else { '[one number: how many, how much]' }) + ').'
    return "SUGGESTION: $done Next: [outcome, by a day]. Need: [an ask, or none]."
}
function TkTranslate($o, $src) {
    if ($null -eq $src) { TkDie "talk: translate needs FILE or - (standard input)`n" }
    if ($src -ceq '-') { $text = (@($script:TK_STDIN) -join "`n") + "`n" }
    else { if (-not (Test-Path -LiteralPath $src -PathType Leaf)) { TkDie "talk: cannot read ${src}: No such file or directory`n" }; $text = ReadText $src }
    $g = $script:TK_GLOSSARY
    if ($o.glossary) {
        if (-not (Test-Path -LiteralPath $o.glossary -PathType Leaf)) { TkDie "talk: cannot read $($o.glossary): No such file or directory`n" }
        $mine = @()
        foreach ($l in ((ReadText $o.glossary) -split "`n")) {
            if ($l -cmatch '^\s*(#|$)') { continue }
            if ($l -cmatch '^\s*(.+?)\s*=\s*([^|]+?)\s*(?:\|\s*(.+?))?\s*$') { $mine += , @((TkQuoteMeta $Matches[1]), $Matches[2], (Dor $Matches[3] 'say what it achieved'), $null) }
        }
        $g = @($mine) + @($g)
    }
    $sents = @(); $seen = NewH; $terms = @()
    foreach ($sent in ($text -split '(?<=[.!?])\s+|\n+')) {
        if ($sent -cnotmatch '\w') { continue }
        $s = $sent -creplace '^\s+|\s+$', ''
        $scan = $s -creplace ('`[^`]*`|' + $script:TK_REF), ' '
        $here = @(); $rest = $scan
        foreach ($e in $g) {
            while ($rest -match ('\b(' + $e[0] + ')\b')) {
                $w = $Matches[1]
                $here += , @($w, $e[1], $e[2], $e[3])
                $lw = $w.ToLowerInvariant(); if (-not $seen.ContainsKey($lw)) { $seen[$lw] = 1; $terms += , @($w, $e[1], $e[2]) }
                $rest = ([regex]::new('(?i)\b' + [regex]::Escape($w) + '\b')).Replace($rest, ' ', 1)
            }
        }
        $why = @()
        if ($s -cnotmatch '\d') { $why += 'no number' }
        if ($s -notmatch $script:TK_OUTCOME) { $why += 'no outcome (done, caught, ready, decided ... or an ask)' }
        $wc = [regex]::Matches($s, '\S+').Count
        if ($wc -gt 30) { $why += "long ($wc words): split it" }
        if ($s -match '\b(?:is|was|are|were|being|been)\s+(?:being\s+)?\w+ed\b' -and $s -notmatch '\bblocked\b') { $why += 'passive: say who did what' }
        $sents += , @{ s = $s; why = $why; terms = $here }
    }
    $plain = TkPlainSwap $text $g
    $md = [bool]$o.md
    $h1 = if ($md) { '## ' } else { '' }; $li = if ($md) { '- ' } else { '  ' }
    $out = @()
    $out += ("${h1}Jargon to replace" + $(if ($md) { '' } else { ':' }))
    if ($terms.Count) { foreach ($t in $terms) { $out += ('{0}"{1}" -> {2}. Hint: {3}.' -f $li, $t[0], $t[1], $t[2]) } } else { $out += "${li}none found" }
    $out += ''; $out += ("${h1}So what? -- sentences to rework" + $(if ($md) { '' } else { ':' }))
    $k = 0; $bad = 0
    foreach ($x in $sents) {
        $k++
        if (@($x.why).Count -eq 0) { continue }
        $bad++
        $out += ('{0}{1}. "{2}" -- {3}' -f $li, $k, $x.s, (@($x.why) -join '; ')); $out += ($li + '   ' + (TkSuggestion $x.s $x.terms))
    }
    if (-not $bad) { $out += "${li}none: every sentence has a number and an outcome" }
    $out += ''; $out += ("${h1}Plain version (nouns swapped only; your sentences otherwise unchanged)" + $(if ($md) { '' } else { ':' })); $out += ($plain -creplace '\s+$', '')
    $out += ''; $out += $(if ($bad) { 'Rework the flagged sentences, then say it.' } else { 'Ready to say.' })
    TkOut (($out -join "`n") + "`n")
    return 0
}
function TkQuoteMeta([string]$s) { $o = ''; foreach ($ch in $s.ToCharArray()) { if ([string]$ch -cmatch '\w') { $o += [string]$ch } else { $o += '\' + [string]$ch } }; return $o }

# ---------------------------------------------------------------- main
$script:TK_USAGE = "usage: talk.cmd [--local DIR | --url URL] [--project GROUP/NAME] standup|review|weekly|translate|help ...`n"
function TkHelp {
    $f = $PSCommandPath; if (-not $f) { $f = Join-Path $script:TK_HERE 'talk.ps1' }
    $t = ReadText $f; $s = $t.IndexOf('<#'); $e = $t.IndexOf('#>')
    TkOut (($t.Substring($s + 2, $e - $s - 2).Trim("`r", "`n")) + "`n")
}
function TkMain($argv) {
    $o = NewH; $rest = @()
    $global1 = @('local', 'url', 'token-env', 'project', 'curl')
    $valued = @('as', 'name', 'date', 'journal', 'prefix', 'sprint', 'baseline', 'metrics', 'glossary')
    $flags = @('chat', 'why', 'md')
    $i = 0; $cmd = $null
    while ($i -lt $argv.Count) {                  # the global options before the command (require_order)
        $a = [string]$argv[$i]
        if ($a -cmatch '^--([\w-]+)(?:=(.*))?$' -and $global1 -ccontains $Matches[1]) {
            $k = $Matches[1]; $v = $Matches[2]; if ($null -eq $v) { $i++; if ($i -ge $argv.Count) { TkDie $script:TK_USAGE }; $v = [string]$argv[$i] }
            $o[$k] = $v; $i++; continue
        }
        $cmd = $a; $i++; break
    }
    if ($null -eq $cmd) { TkDie $script:TK_USAGE }
    if ($cmd -cmatch '^(help|-h|--help|-Help)$') { TkHelp; return 0 }
    while ($i -lt $argv.Count) {
        $a = [string]$argv[$i]; $i++
        if ($a -cmatch '^--([\w-]+)(?:=(.*))?$') {
            $k = $Matches[1]; $v = $Matches[2]
            if ($valued -ccontains $k) { if ($null -eq $v) { if ($i -ge $argv.Count) { TkDie $script:TK_USAGE }; $v = [string]$argv[$i]; $i++ }; $o[$k] = $v; continue }
            if ($flags -ccontains $k) { $o[$k] = $true; continue }
            if ($global1 -ccontains $k) { if ($null -eq $v) { $v = [string]$argv[$i]; $i++ }; $o[$k] = $v; continue }
            TkDie ("Unknown option: $k`n" + $script:TK_USAGE)
        }
        $rest += $a
    }
    if ($cmd -ceq 'translate') { return (TkTranslate $o $(if ($rest.Count) { $rest[0] } else { $null })) }
    if (-not (@('standup', 'review', 'weekly') -ccontains $cmd)) { TkDie "talk: unknown command '$cmd' (standup, review, weekly, translate, help)`n" }
    if ($rest.Count) { TkDie "talk: unexpected argument '$($rest[0])'`n" }
    $c = TkConnect $o
    switch -CaseSensitive ($cmd) {
        'standup' { return (TkStandup $c[0] $c[1] $o) }
        'review' { return (TkReview $c[0] $c[1] $o) }
        'weekly' { return (TkWeekly $c[0] $c[1] $o) }
    }
}

if ($args.Count -and [string]$args[0] -ceq '__lib') { return }
$script:TK_STDIN = @(); if ($args -ccontains '-') { $script:TK_STDIN = @($input | ForEach-Object { [string]$_ }) }
$rc = 2
try { $rc = TkMain @($args) }
catch {
    $m = [string]$_.Exception.Message
    if ($m.StartsWith('TKDIE:')) { $m = $m.Substring(6) } elseif ($m -cnotmatch "`n$") { $m += "`n" }
    if ($script:TK_OUT) { Write-Output ($script:TK_OUT -creplace "`n$", '') }
    Write-Host -NoNewline $m
    exit 2
}
if ($script:TK_OUT) { foreach ($l in (($script:TK_OUT -creplace "`n$", '') -split "`n")) { Write-Output $l } }
if ($script:TK_NOTE) { Write-Host -NoNewline $script:TK_NOTE }
exit $rc
