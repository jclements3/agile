# glsetup.ps1 -- GitLab.pm's project file (setup, setup --diff), sprints, the Insights file, pipeline schedules with
# cron in a time zone, analytics and the CSV export. Constrained Language Mode safe.

# ---------------------------------------------------------------- the project file
function ParseProjectFile([string]$text, [string]$file) {
    if ($null -eq $file -or $file -ceq '') { $file = 'project file' }
    $c = NewH; $sec = $null; $n = 0
    foreach ($l in ($text -split "`r?`n")) {
        $n++
        $l = $l -creplace '^\s*[;#].*$', ''; $l = $l -creplace '\s+;.*$', ''; $l = $l -creplace '\s+#\s.*$', ''
        if ($l -cnotmatch '\S') { continue }
        if ($l -cmatch '^\s*\[\s*([\w ]+?)\s*\]\s*$') { $sec = $matches[1].ToLowerInvariant(); continue }
        if ($null -eq $sec) { throw "${file}:${n}: a key before any [section]`n" }
        if ($l -cnotmatch '^\s*(.+?)\s*=\s*(.*?)\s*$') { throw "${file}:${n}: expected KEY = VALUE`n" }
        Push $c $sec @($matches[1], $matches[2], $n)
    }
    return $c
}
function KV($lines) { $h = NewH; foreach ($x in (L $lines)) { $h[$x[0]] = $x[1] }; return $h }
function GL-apply_project_file($gl, [string]$path, $o) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "GitLab: cannot read ${path}: No such file or directory`n" }
    $c = ParseProjectFile (ReadText $path) $path
    $log = @()
    $pr = KV $c.project
    $p = Dor $o.project $pr.path
    if ($null -eq $p) { throw "${path}: [project] needs path = group/name`n" }
    $exists = $false
    if (IsLocal $gl) { $exists = [bool]$gl.st.projects[$p] }
    else { $ok = $true; try { $null = GL-_api $gl 'GET' ('/projects/' + (Enc $p)) } catch { $ok = $false }; $exists = $ok -and -not $gl.dry_run }
    if (-not $exists) {
        if ($p -cmatch '^(.*)/') { $ns = $matches[1] } else { $ns = $null }
        if (IsLocal $gl) { $null = GL-create_group $gl $ns (NewH) }
        $po = NewH; if (Tru $pr.visibility) { $po.visibility = $pr.visibility }
        $null = GL-create_project $gl $p $po; $log += "created project $p"
    }
    $set = NewH; foreach ($k in @($pr.Keys)) { if ($k -cne 'path' -and $k -cne 'visibility') { $set[$k] = $pr[$k] } }
    if ($set.Count) { $null = GL-update_project $gl $p $set; $log += 'settings: ' + ((@(foreach ($k in (SortStr @($set.Keys))) { "$k=$($set[$k])" })) -join ', ') }
    foreach ($x in (L $c.members)) { $null = GL-add_member $gl $p $x[0] $x[1] (NewH); $log += "member $($x[0]) $($x[1])" }
    foreach ($x in (L $c.variables)) {
        $parts = @($x[1] -csplit '\s+\|\s+'); $v = $parts[0]; $fo = NewH; for ($i = 1; $i -lt $parts.Count; $i++) { $fo[$parts[$i]] = 1 }
        $null = GL-set_variable $gl $p $x[0] $v $fo; $log += "variable $($x[0])"
    }
    foreach ($x in (L $c.labels)) {
        if ($x[1] -cnotmatch '^\s*(#[0-9A-Fa-f]{6})\s*(?:\|\s*(.*))?$') { throw "${path}:$($x[2]): label value is '#RRGGBB | description'`n" }
        $color = $matches[1]; $desc = $(if ($matches[2]) { $matches[2] } else { '' })
        $null = GL-create_label $gl $p $x[0] $color $desc; $log += "label $($x[0])"
    }
    foreach ($x in (L $c.milestones)) {
        if ($x[0] -ceq 'sprints') {
            $w = SplitWs $x[1] 4
            $ms = GL-sprints $gl $p $w[0] $w[1] (O 'weeks' (Dor $(if ($w.Count -gt 2) { $w[2] }) 2) 'prefix' $(if ($w.Count -gt 3) { $w[3] } else { $null }))
            foreach ($m in $ms) { $log += "milestone $($m.title)" }
        } else {
            $sp = @($x[1] -csplit '\s*\|\s*', 2); $dates = $sp[0]; $desc = $(if ($sp.Count -gt 1) { $sp[1] } else { $null })
            $dd = SplitWs (Dor $dates '') 0
            $null = GL-_upsert_milestone $gl $p $x[0] (O 'start_date' $(if ($dd.Count) { $dd[0] }) 'due_date' $(if ($dd.Count -gt 1) { $dd[1] }) 'description' (Dor $desc ''))
            $log += "milestone $($x[0])"
        }
    }
    if ($c.statuses) { $log += (GL-_setup_statuses $gl $p (ParseStatuses $c.statuses $path $p)) }
    $it = ParseIterations $c.iterations $path $p
    $res = GL-_setup_iterations $gl $it
    $log += (L $res[0]); $cads = $res[1]
    $cad = $null; foreach ($k in @($cads.Keys)) { if ($null -ne $cads[$k].id) { $cad = $cads[$k].id; break } }
    $bit = $null
    if ($c.boards -and -not (IsLocal $gl) -and (First $c.boards { param($b) $b[1] -cmatch ' iteration=| sprint=' })) { try { $bit = GL-board_iterations $gl $p } catch { $bit = $null } }
    foreach ($x in (L $c.boards)) { $log += (GL-_setup_board $gl $p $x[0] (ParseBoardLine $x[1] "${path}:$($x[2])" $it.use) (O 'iterations' $bit 'cadence' $cad)) }
    foreach ($x in (L $c.branches)) {
        $a = NewH
        foreach ($w in (SplitWs $x[1] 0)) { if ($w -cnotmatch '^(\w+):(\S+)$') { throw "${path}:$($x[2]): branch rule words are push:LEVEL merge:LEVEL force:yes|no codeowners:yes|no`n" }; $a[$matches[1].ToLowerInvariant()] = $matches[2].ToLowerInvariant() }
        $null = GL-protect_branch $gl $p $x[0] (O 'push_access_level' (Dor $a.push 'maintainer') 'merge_access_level' (Dor $a.merge 'maintainer') `
            'allow_force_push' ((Dor $a.force 'no') -ceq 'yes') 'code_owner_approval_required' ((Dor $a.codeowners 'no') -ceq 'yes'))
        $log += "protected branch $($x[0]) ($($x[1]))"
    }
    foreach ($x in (L $c.tags)) {
        if ($x[1] -cnotmatch '^create:(\S+)$') { throw "${path}:$($x[2]): tag rule is create:LEVEL`n" }
        $null = GL-protect_tag $gl $p $x[0] (O 'create_access_level' $matches[1]); $log += "protected tag $($x[0])"
    }
    foreach ($x in (L $c.approvals)) {
        $w = SplitWs $x[1] 0; $n = $w[0]
        if ([string]$n -cnotmatch '^\d+$') { throw "${path}:$($x[2]): approval rule is N user user ...`n" }
        $users = @(); if ($w.Count -gt 1) { $users = $w[1..($w.Count - 1)] }
        $null = GL-create_approval_rule $gl $p $x[0] $n (O 'users' $users); $log += "approval rule $($x[0]) ($n)"
    }
    foreach ($x in (L $c.schedules)) {
        $f = @(@($x[1] -split '\|', 4) | ForEach-Object { $_.Trim() })
        $cron = $(if ($f.Count -gt 0) { $f[0] }); $ref = $(if ($f.Count -gt 1) { $f[1] }); $tz = $(if ($f.Count -gt 2) { $f[2] }); $vars = $(if ($f.Count -gt 3) { $f[3] })
        if (-not ($ref -and $cron)) { throw "${path}:$($x[2]): a schedule is CRON | REF [| TZ [| K=V ...]]`n" }
        $v = NewH; foreach ($kv in (SplitWs (Dor $vars '') 0)) { if ($kv -cnotmatch '^([A-Za-z_]\w*)=(.*)$') { throw "${path}:$($x[2]): schedule variables are KEY=VALUE, not '$kv'`n" }; $v[$matches[1]] = $matches[2] }
        $so = O 'description' $x[0] 'ref' $ref 'cron' $cron 'cron_timezone' $(if ($tz) { $tz } else { 'UTC' }) 'variables' $v
        $name = $x[0]; $old = $null
        if (-not ($gl.dry_run -and -not (IsLocal $gl))) { $old = First (GL-schedules $gl $p) { param($s) $s.description -ceq $name } }
        if ($old) {
            $all = NewH; foreach ($ov in (L $old.variables)) { $all[$ov.key] = $null }; foreach ($k in @($v.Keys)) { $all[$k] = $v[$k] }
            $so2 = Copy-H $so; $so2.variables = $all
            $null = GL-update_schedule $gl $p $old.id $so2
        } elseif ((IsLocal $gl) -and -not (GL-_sha $gl (GL-_p $gl $p) "refs/heads/$ref") -and -not (GL-_sha $gl (GL-_p $gl $p) "refs/tags/$ref")) {
            GErr "GitLab: schedule $name skipped: $ref does not exist yet; re-run setup after flow init`n"
            $log += "schedule $name skipped ($ref does not exist yet)"
            continue
        } else { $null = GL-create_schedule $gl $p $so }
        $log += "schedule $name ($cron, $($so.cron_timezone), $ref)"
    }
    if ($c.insights) { $log += (GL-_setup_insights $gl $p $path $c (O 'repo' $o.repo 'commit' $o.commit)) }
    return , $log
}
function SplitWs([string]$s, [int]$max) {             # Perl split ' ', S, MAX
    $s = $s -creplace '^\s+', ''
    if ($s -ceq '') { return , @() }
    if ($max -le 0) { return , @($s -split '\s+' | Where-Object { $_ -cne '' }) }
    $o = @(); $rest = $s
    while ($o.Count -lt $max - 1 -and $rest -cmatch '^(\S+)\s+(.*)$') { $o += $matches[1]; $rest = $matches[2] }
    if ($rest -cne '') { if ($o.Count -eq $max - 1) { $o += $rest } else { $o += @($rest -split '\s+' | Where-Object { $_ -cne '' }) } }
    return , $o
}
function GL-_upsert_milestone($gl, $p, $title, $o) {
    $m = $null
    if (-not $gl.dry_run) { $m = First (GL-milestones $gl $p) { param($x) $x.title -ceq $title } }
    if (-not $m) { return (GL-create_milestone $gl $p $title $o) }
    $ch = NewH; foreach ($k in @($o.Keys)) { if ($null -ne $o[$k] -and (PStr (Dor $m[$k] '')) -cne (PStr $o[$k])) { $ch[$k] = $o[$k] } }
    if ($ch.Count) { return (GL-update_milestone $gl $p $title $ch) }
    return $m
}
function GL-sprints($gl, $p, $start, $count, $o) {
    if ($null -eq $o) { $o = NewH }
    $w = PNum (Dor $o.weeks 2)
    $prefix = Dor $o.prefix 'Sprint '
    $t0 = Epoch $start
    $m = @()
    for ($k = 1; $k -le (PNum $count); $k++) {
        $s = $t0 + ($k - 1) * $w * 7 * 86400
        $e = $s + ($w * 7 - 3) * 86400
        $m += , (GL-_upsert_milestone $gl $p "$prefix$k" (O 'start_date' (DateT $s) 'due_date' (DateT $e) 'description' ("Two-week sprint ${k}: planning on " + (DateT $s) + ', review and retrospective on ' + (DateT $e) + '.')))
    }
    return , $m
}

# ---------------------------------------------------------------- the Insights dashboard
function Yq($s) { $s = [string](Dor $s ''); $s = $s.Replace('\', '\\').Replace('"', '\"'); return "`"$s`"" }
function InsightsYml($c, [string]$file) {
    $ins = KV $c.insights
    $weeks = Dor $ins.weeks 12
    if (-not ([string]$weeks -cmatch '^\d+$' -and [int]$weeks -ge 1)) { throw "${file}: [insights] weeks is a number of weeks, not '$weeks'`n" }
    $labels = @(foreach ($x in (L $c.labels)) { $x[0] })
    $fam = { param($pre) , @(foreach ($l in $labels) { if ($l.StartsWith($pre, [StringComparison]::Ordinal)) { $l } }) }
    $wf = & $fam 'workflow::'; $sev = & $fam 'severity::'; $work = & $fam 'work::'
    $defect = $null; foreach ($l in $labels) { if ($l -ceq 'type::defect') { $defect = $l; break } }
    $wc = KV $c.windchill
    $source = $null
    foreach ($x in ([string](Dor $wc.labels '') -split ',')) { $y = $x.Trim(); if ($y -cmatch '^source::') { $source = $y; break } }
    if ($null -eq $source -and $c.windchill) { foreach ($l in $labels) { if ($l -cmatch '^source::windchill$') { $source = $l; break } } }
    $script:INSN = 0
    $chart = { param($a)
        $script:INSN++
        $y = "    - title: " + (Yq $a.title) + "`n      description: " + (Yq $a.description) + "`n      type: $($a.type)`n      query:`n        data_source: issuables`n        params:`n"
        $y += "          issuable_type: $($a.kind)`n          issuable_state: $($a.state)`n"
        foreach ($k in @('filter_labels', 'collection_labels')) { if ($a[$k] -and (L $a[$k]).Count) { $y += "          ${k}:`n" + ((@(foreach ($x in (L $a[$k])) { "            - " + (Yq $x) + "`n" })) -join '') } }
        $y += "          group_by: week`n          period_limit: $weeks`n" + $(if ($a.field) { "          period_field: $($a.field)`n" } else { '' })
        $y
    }
    $y = "# .gitlab/insights.yml -- generated by gitlab.pl setup from .gitlab/project.conf ([labels], [windchill], [insights]).`n" +
         "# Edit project.conf and re-run setup, not this file. GitLab reads it from the default branch (Analyze > Insights,`n" +
         "# Ultimate). Insights groups by day, week or month, not by sprint: the charts are weekly, the last $weeks weeks.`n"
    $y += "flow:`n  title: `"Flow of work`"`n  charts:`n"
    if ($wf.Count) { $y += & $chart (O 'title' 'Open issues by board column' 'description' 'Open issues created each week, split by their workflow:: label (the board columns)' 'type' 'stacked-bar' 'kind' 'issue' 'state' 'opened' 'collection_labels' $wf) }
    $y += & $chart (O 'title' 'Issues created per week' 'description' 'Every issue created each week, open or closed' 'type' 'bar' 'kind' 'issue' 'state' 'all' 'field' 'created_at')
    $y += & $chart (O 'title' 'Issues closed per week' 'description' 'Issues closed each week (compare with created: is the backlog growing?)' 'type' 'bar' 'kind' 'issue' 'state' 'closed' 'field' 'closed_at')
    $y += & $chart (O 'title' 'Merge requests merged per week' 'description' 'Changes that reached the target branch each week' 'type' 'bar' 'kind' 'merge_request' 'state' 'merged' 'field' 'merged_at')
    if ($defect -or $sev.Count) {
        $y += "quality:`n  title: `"Defects`"`n  charts:`n"
        $a = O 'title' 'Open defects by severity' 'description' 'Open defects created each week, split by severity::' 'type' 'stacked-bar' 'kind' 'issue' 'state' 'opened' 'collection_labels' $sev
        if ($defect) { $a.filter_labels = @($defect) }
        $y += & $chart $a
        if ($defect) { $y += & $chart (O 'title' 'Defects closed per week' 'description' 'Defects closed each week' 'type' 'bar' 'kind' 'issue' 'state' 'closed' 'field' 'closed_at' 'filter_labels' @($defect)) }
    }
    if ($source) {
        $y += "requests:`n  title: `"Requests from Windchill`"`n  charts:`n"
        $y += & $chart (O 'title' 'Requests received per week' 'description' "Issues made from Windchill requests ($source), by the week they arrived" 'type' 'bar' 'kind' 'issue' 'state' 'all' 'field' 'created_at' 'filter_labels' @($source))
        $y += & $chart (O 'title' 'Requests closed per week' 'description' 'Windchill requests the team finished each week (gitlab.pl windchill status sends them back)' 'type' 'bar' 'kind' 'issue' 'state' 'closed' 'field' 'closed_at' 'filter_labels' @($source))
        $y += & $chart (O 'title' 'Open requests' 'description' 'Windchill requests still open, by the week they arrived' 'type' 'bar' 'kind' 'issue' 'state' 'opened' 'filter_labels' @($source))
    }
    if ($work.Count) {
        $y += "work:`n  title: `"Where the time goes`"`n  charts:`n"
        $y += & $chart (O 'title' 'Issues closed by kind of work' 'description' 'Closed issues each week, split by work:: (engineering, platform, learning)' 'type' 'stacked-bar' 'kind' 'issue' 'state' 'closed' 'field' 'closed_at' 'collection_labels' $work)
    }
    return , @($y, $script:INSN)
}
function InsightsTarget([string]$path, $c, $o) {
    $ins = KV $c.insights
    $rel = Dor $ins.file '.gitlab/insights.yml'
    if ($null -ne $o.repo) { return "$($o.repo)/$rel" }
    $abs = $path; if (Test-Path -LiteralPath $path) { $abs = (Resolve-Path -LiteralPath $path).ProviderPath }
    $dir = $abs -creplace '[/\\][^/\\]*$', ''
    if ($dir -cmatch '[/\\]\.gitlab$') { return ($dir -creplace '[/\\]\.gitlab$', '') + "/$rel" }
    return $null
}
function GL-_setup_insights($gl, $p, [string]$path, $c, $o) {
    $r = InsightsYml $c $path; $yml = $r[0]; $n = $r[1]
    $ins = KV $c.insights
    $rel = Dor $ins.file '.gitlab/insights.yml'
    $target = InsightsTarget $path $c $o
    $log = @()
    if (Tru $o.commit) {
        $def = Dor (GL-project $gl $p).default_branch 'main'
        $live = GL-file_raw $gl $p $rel $def
        if ($null -ne $live -and $live -ceq $yml) { $log += "insights: $rel on $def is current ($n charts)"; return , $log }
        $br = 'feature/insights-' + ((DateT (GL-epoch $gl)) -creplace '-', '')
        $null = GL-commit_files $gl $p (O 'branch' $br 'start_branch' $def 'message' "Insights dashboard from project.conf ($n charts)" 'actions' @((O 'action' $(if ($null -ne $live) { 'update' } else { 'create' }) 'file_path' $rel 'content' $yml)))
        $mr = GL-create_mr $gl $p (O 'source_branch' $br 'target_branch' $def 'title' 'Insights dashboard from project.conf' 'description' ("Generated by ``gitlab.pl setup --commit`` from .gitlab/project.conf: $n charts. Review the charts, then merge;`nGitLab reads ``$rel`` from the default branch (Analyze > Insights).`n"))
        $log += "insights: $rel ($n charts) on $br, merge request !" + (Dor $mr.iid '?')
    }
    if ($null -eq $target) {
        if (-not (Tru $o.commit)) { $log += "insights: $rel not written ($n charts generated): run setup on the repository's .gitlab/project.conf, or setup --repo DIR" }
        return , $log
    }
    $old = $null; if (Test-Path -LiteralPath $target -PathType Leaf) { $old = ReadText $target }
    if ($null -ne $old -and $old -ceq $yml) { if (-not (Tru $o.commit)) { $log += "insights: $rel is current ($n charts)" }; return , $log }
    if ($gl.dry_run) { $log += "insights: would write $rel ($n charts)"; return , $log }
    $d = $target -creplace '[/\\][^/\\]*$', ''; $null = New-Item -ItemType Directory -Path $d -Force
    WriteText $target $yml
    $log += "insights: wrote $rel ($n charts)" + $(if (Tru $o.commit) { '' } else { ' -- commit it through a merge request (or run setup --commit)' })
    return , $log
}

# ---------------------------------------------------------------- pipeline schedules: cron in a time zone
$script:MONTHS = O 'jan' 1 'feb' 2 'mar' 3 'apr' 4 'may' 5 'jun' 6 'jul' 7 'aug' 8 'sep' 9 'oct' 10 'nov' 11 'dec' 12
$script:CRONDAYS = O 'sun' 0 'mon' 1 'tue' 2 'wed' 3 'thu' 4 'fri' 5 'sat' 6
$script:MACRO = O '@yearly' '0 0 1 1 *' '@annually' '0 0 1 1 *' '@monthly' '0 0 1 * *' '@weekly' '0 0 * * 0' '@daily' '0 0 * * *' '@midnight' '0 0 * * *' '@hourly' '0 * * * *'
$script:US_TZ = O 'America/New_York' @(-5, 1) 'US/Eastern' @(-5, 1) 'America/Chicago' @(-6, 1) 'US/Central' @(-6, 1) 'America/Denver' @(-7, 1) 'US/Mountain' @(-7, 1) `
    'America/Phoenix' @(-7, 0) 'America/Los_Angeles' @(-8, 1) 'US/Pacific' @(-8, 1) 'America/Anchorage' @(-9, 1) 'Pacific/Honolulu' @(-10, 0)
function ParseCron($expr) {
    $e = ([string](Dor $expr '')).ToLowerInvariant().Trim()
    if ($script:MACRO.ContainsKey($e)) { $e = $script:MACRO[$e] }
    $f = SplitWs $e 0
    if ($f.Count -ne 5) { throw "GitLab: bad cron '$(Dor $expr '')': want 5 fields (minute hour day-of-month month day-of-week)`n" }
    $spec = @(@('minute', 0, 59, $null), @('hour', 0, 23, $null), @('day-of-month', 1, 31, $null), @('month', 1, 12, $script:MONTHS), @('day-of-week', 0, 7, $script:CRONDAYS))
    $c = NewH; $keys = @('min', 'hour', 'dom', 'mon', 'dow')
    for ($i = 0; $i -lt 5; $i++) {
        $name = $spec[$i][0]; $lo = $spec[$i][1]; $hi = $spec[$i][2]; $names = $spec[$i][3]
        $set = NewH
        foreach ($part in ($f[$i] -split ',')) {
            $rs = @($part -split '/', 2); $range = $rs[0]; $step = $(if ($rs.Count -gt 1) { $rs[1] } else { $null })
            if ($null -ne $step -and $step -cnotmatch '^[1-9]\d*$') { throw "GitLab: bad cron '$expr': step '$step' in the $name field`n" }
            $num = { param($v) if ($names -and $names.ContainsKey($v)) { return $names[$v] }; if ($v -cmatch '^\d+$' -and [int]$v -ge $lo -and [int]$v -le $hi) { return [int]$v }
                     throw ("GitLab: bad cron '$expr': '$v' is not a $name ($lo-$hi" + $(if ($names) { ' or a name' } else { '' }) + ")`n") }
            if ($range -ceq '*') { $a = $lo; $b = $hi }
            elseif ($range -cmatch '^([^-]+)-([^-]+)$') { $a = & $num $matches[1]; $b = & $num $matches[2]; if ($a -gt $b) { throw "GitLab: bad cron '$expr': range '$range' runs backwards`n" } }
            else { $a = & $num $range; if ($null -ne $step) { $b = $hi } else { $b = $a } }
            $st = $(if ($null -ne $step) { [int]$step } else { 1 })
            for ($v = $a; $v -le $b; $v += $st) { $set[[string]$(if ($i -eq 4 -and $v -eq 7) { 0 } else { $v })] = 1 }
        }
        $c[$keys[$i]] = $set
    }
    $c.dom_any = $(if ($f[2] -cmatch '^\*(/1)?$') { 1 } else { 0 })
    $c.dow_any = $(if ($f[4] -cmatch '^\*(/1)?$') { 1 } else { 0 })
    return $c
}
function NthSunday([long]$y, [long]$m, [long]$n) { $t = TimeGm 0 0 0 1 ($m - 1) $y; $w = (GmTime $t)[6]; return (1 + (7 - $w) % 7 + 7 * ($n - 1)) }
function TzOffset($tz, [long]$t) {
    if ($null -eq $tz -or $tz -ceq '') { $tz = 'UTC' }
    if ($tz -cmatch '^(?i)(UTC|GMT|Z|Etc/UTC|Etc/GMT|Universal|Zulu)$') { return 0 }
    if ($tz -cmatch '^(?i)(?:UTC|GMT)?\s*([+-])(\d{1,2})(?::?(\d\d))?$') { $o = [long]$matches[2] * 3600 + [long](Dor $matches[3] 0) * 60; if ($matches[1] -ceq '-') { return - $o }; return $o }
    $z = $script:US_TZ[[string]$tz]
    if (-not $z) { throw "GitLab: unknown time zone '$tz' (UTC, +HH:MM, America/New_York, America/Chicago, America/Denver, America/Los_Angeles, ...)`n" }
    $std = $z[0] * 3600
    if (-not $z[1]) { return $std }
    $y = (GmTime ($t + $std))[5] + 1900
    $on = (TimeGm 0 0 2 (NthSunday $y 3 2) 2 $y) - $std
    $off = (TimeGm 0 0 2 (NthSunday $y 11 1) 10 $y) - ($std + 3600)
    if ($t -ge $on -and $t -lt $off) { return $std + 3600 }
    return $std
}
function LocalToUtc($tz, [long]$l) {
    $u = NewH; $u[[string](TzOffset $tz ($l - 86400))] = 1; $u[[string](TzOffset $tz ($l + 86400))] = 1
    $c = @(); foreach ($k in @($u.Keys)) { $x = $l - [long]$k; if ((TzOffset $tz $x) -eq $l - $x) { $c += $x } }
    if ($c.Count) { return (SortNum $c)[0] }
    return ($l - (TzOffset $tz ($l - 86400)))
}
function CronNext($cron, $tz, [long]$after) {
    $c = $(if ($cron -is [hashtable]) { $cron } else { ParseCron $cron })
    $null = TzOffset $tz $after
    $l = $after + (TzOffset $tz $after)
    $l = $l - ($l % 60) + 60
    for ($guard = 0; $guard -lt 2000000; $guard++) {
        $g = GmTime $l
        $mi = $g[1]; $h = $g[2]; $d = $g[3]; $mo = $g[4] + 1; $y = $g[5] + 1900; $w = $g[6]
        if (-not $c.mon.ContainsKey([string]$mo)) { if ($mo -eq 12) { $l = TimeGm 0 0 0 1 0 ($y + 1) } else { $l = TimeGm 0 0 0 1 $mo $y }; continue }
        $day = $(if ($c.dom_any -and $c.dow_any) { $true } elseif ($c.dom_any) { $c.dow.ContainsKey([string]$w) } elseif ($c.dow_any) { $c.dom.ContainsKey([string]$d) } else { $c.dom.ContainsKey([string]$d) -or $c.dow.ContainsKey([string]$w) })
        if (-not $day) { $l = (TimeGm 0 0 0 $d ($mo - 1) $y) + 86400; continue }
        if (-not $c.hour.ContainsKey([string]$h)) { $l = $l - ($l % 3600) + 3600; continue }
        if (-not $c.min.ContainsKey([string]$mi)) { $l += 60; continue }
        $u = LocalToUtc $tz $l
        if ($u -gt $after) { return $u }
        $l += 60
    }
    throw "GitLab: cron '$cron' never runs`n"
}
function CronRuns($cron, $tz, [long]$after, [int]$n) { $r = @(); $t = $after; for ($i = 1; $i -le $n; $i++) { $t = CronNext $cron $tz $t; $r += $t }; return , $r }
function ActiveOf($v) { if ($null -eq $v) { return 1 }; if ([string]$v -cmatch '^(?i)(0|false|no|off)$') { return 0 }; return 1 }
function GL-create_schedule($gl, $p, $o) {
    return (DryWrap $gl {
        foreach ($k in @('description', 'ref', 'cron')) { if ([string](Dor $o[$k] '') -ceq '') { throw "GitLab: a pipeline schedule needs $k`n" } }
        $tz = Dor $o.cron_timezone 'UTC'
        $active = ActiveOf $o.active
        if (IsLocal $gl) {
            $PJ = GL-_p $gl $p
            $null = ParseCron $o.cron; $null = TzOffset $tz 0
            $ref = ([string]$o.ref) -creplace '^refs/heads/', ''
            if (-not ((GL-_sha $gl $PJ "refs/heads/$ref") -or (GL-_sha $gl $PJ "refs/tags/$ref"))) { throw "GitLab: no branch or tag '$ref' in $p (400 Ref is invalid)`n" }
            $vars = NewH; if ($o.variables) { $vars = $o.variables }
            $s = O 'id' (GL-_id $gl) 'description' $o.description 'ref' $ref 'cron' $o.cron 'cron_timezone' $tz 'active' $active `
                'owner' (O 'username' $gl.as) 'created_at' (GL-now $gl) 'updated_at' (GL-now $gl) 'last_pipeline' $null `
                'variables' (Map-L (SortStr @($vars.Keys)) { param($k) O 'key' $k 'value' $vars[$k] 'variable_type' 'env_var' })
            if ($active) { $s.next_run_at = IsoT (CronNext $s.cron $tz (GL-epoch $gl)) } else { $s.next_run_at = $null }
            Push $PJ 'schedules' $s
            return $s
        }
        $base = '/projects/' + (Enc $p) + '/pipeline_schedules'
        $s = GL-_api $gl 'POST' $base (O 'description' $o.description 'ref' $o.ref 'cron' $o.cron 'cron_timezone' $tz 'active' (Jbool $(if ($active) { 'true' } else { 'false' })))
        $sid = $(if ($gl.dry_run) { '{id}' } else { $s.id })
        $vars = NewH; if ($o.variables) { $vars = $o.variables }
        foreach ($k in (SortStr @($vars.Keys))) { $null = GL-_api $gl 'POST' "$base/$sid/variables" (O 'key' $k 'value' $vars[$k]) }
        return $s
    })
}
function GL-schedules($gl, $p) {
    if (IsLocal $gl) { return , (L (GL-_p $gl $p).schedules) }
    return , (L (GL-_api $gl 'GET' ('/projects/' + (Enc $p) + '/pipeline_schedules') $null (O 'all' 1)))
}
function GL-_schedule($gl, $PJ, $id) { $s = First $PJ.schedules { param($x) [long]$x.id -eq [long](PNum $id) }; if (-not $s) { throw "GitLab: no pipeline schedule $id in $($PJ.path_with_namespace) (404 Not found)`n" }; return $s }
function GL-update_schedule($gl, $p, $id, $o) {
    return (DryWrap $gl {
        if (IsLocal $gl) {
            $PJ = GL-_p $gl $p
            $s = GL-_schedule $gl $PJ $id
            if ($null -ne $o.cron) { $null = ParseCron $o.cron }
            if ($null -ne $o.cron_timezone) { $null = TzOffset $o.cron_timezone 0 }
            foreach ($k in @('description', 'ref', 'cron', 'cron_timezone')) { if ($null -ne $o[$k]) { $s[$k] = $o[$k] } }
            if ($null -ne $o.active) { $s.active = ActiveOf $o.active }
            if ($o.variables) {
                $have = NewH; foreach ($x in (L $s.variables)) { $have[$x.key] = $x }
                foreach ($k in @($o.variables.Keys)) { if ($null -ne $o.variables[$k]) { $have[$k] = O 'key' $k 'value' $o.variables[$k] 'variable_type' 'env_var' } else { $have.Remove($k) } }
                $s.variables = Map-L (SortStr @($have.Keys)) { param($k) $have[$k] }
            }
            $s.updated_at = GL-now $gl
            if (Tru $s.active) { $s.next_run_at = IsoT (CronNext $s.cron $s.cron_timezone (GL-epoch $gl)) } else { $s.next_run_at = $null }
            return $s
        }
        $base = '/projects/' + (Enc $p) + "/pipeline_schedules/$id"
        $b = NewH; foreach ($k in @('description', 'ref', 'cron', 'cron_timezone')) { if ($null -ne $o[$k]) { $b[$k] = $o[$k] } }
        if ($null -ne $o.active) { $b.active = Jbool $(if ((ActiveOf $o.active) -eq 0) { 'false' } else { 'true' }) }
        $s = $null; if ($b.Count) { $s = GL-_api $gl 'PUT' $base $b }
        if ($o.variables) {
            $have = NewH
            if (-not $gl.dry_run) { foreach ($x in (L (Dor (GL-_api $gl 'GET' $base) (NewH)).variables)) { $have[$x.key] = 1 } }
            foreach ($k in (SortStr @($o.variables.Keys))) {
                if ($null -eq $o.variables[$k]) { if ($have.ContainsKey($k)) { $null = GL-_api $gl 'DELETE' "$base/variables/$(Enc $k)" } }
                elseif ($have.ContainsKey($k)) { $null = GL-_api $gl 'PUT' "$base/variables/$(Enc $k)" (O 'value' $o.variables[$k]) }
                else { $null = GL-_api $gl 'POST' "$base/variables" (O 'key' $k 'value' $o.variables[$k]) }
            }
        }
        if ($null -ne $s) { return $s }
        if ($gl.dry_run) { return (NewH) }
        return (GL-_api $gl 'GET' $base)
    })
}
function GL-delete_schedule($gl, $p, $id) {
    return (DryWrap $gl {
        if (IsLocal $gl) { $PJ = GL-_p $gl $p; $null = GL-_schedule $gl $PJ $id; $PJ.schedules = Where-L $PJ.schedules { param($x) [long]$x.id -ne [long](PNum $id) }; return (O 'id' $id) }
        return (GL-_api $gl 'DELETE' ('/projects/' + (Enc $p) + "/pipeline_schedules/$id"))
    })
}
function GL-play_schedule($gl, $p, $id) {
    return (DryWrap $gl {
        if (IsLocal $gl) { $null = GL-_schedule $gl (GL-_p $gl $p) $id; throw $script:NOGIT }
        return (GL-_api $gl 'POST' ('/projects/' + (Enc $p) + "/pipeline_schedules/$id/play") (NewH))
    })
}
function GL-run_due_schedules($gl, $p, $o) {
    if (-not $gl.local) { throw "GitLab: run_due_schedules is for the local emulator; a GitLab server runs its schedules itself`n" }
    $PJ = GL-_p $gl $p
    $until = $(if ($null -ne $o.until) { Epoch $o.until } else { GL-epoch $gl })
    if ($gl.dry_run) {
        $next = NewH; $by = NewH
        foreach ($s in (L $PJ.schedules)) { $by[[string]$s.id] = $s; if ((Tru $s.active) -and $null -ne $s.next_run_at) { $next[[string]$s.id] = Epoch $s.next_run_at } }
        while ($true) {
            $due = Where-L @($next.Keys) { param($k) $next[$k] -le $until }
            if ($due.Count -eq 0) { break }
            $id = (SortWith $due { param($a, $b) $c = NumCmp $next[$a] $next[$b]; if ($c -ne 0) { $c } else { NumCmp $a $b } })[0]
            GOut ("POST /api/v4/projects/" + (Enc $p) + "/pipeline_schedules/$id/play {}   # " + (IsoT $next[$id]) + " $($by[$id].description)`n")
            $next[$id] = CronNext $by[$id].cron $by[$id].cron_timezone $next[$id]
        }
        return , @()
    }
    $due = Where-L $PJ.schedules { param($s) (Tru $s.active) -and $null -ne $s.next_run_at -and (Epoch $s.next_run_at) -le $until }
    if ($due.Count) { throw $script:NOGIT }
    $was = GL-epoch $gl
    $null = GL-clock $gl $(if ($until -gt $was) { $until } else { $was })
    return , @()
}

# ---------------------------------------------------------------- analytics
function Median($v) { $x = SortNum (Where-L $v { param($y) $null -ne $y }); if ($x.Count -eq 0) { return $null }; if ($x.Count % 2) { return $x[($x.Count - 1) / 2] }; return ($x[$x.Count / 2 - 1] + $x[$x.Count / 2]) / 2 }
function Pct($p, $v) { $x = SortNum (Where-L $v { param($y) $null -ne $y }); if ($x.Count -eq 0) { return $null }; $k = (Trunc ($p * $x.Count + 0.999999)) - 1; if ($k -lt 0) { $k = 0 }; return $x[$k] }
function Period([long]$t, $by, $sprints) {
    if ($by -ceq 'month') { $g = GmTime $t; return (StrfTime '%Y-%m' $g) }
    if ($by -ceq 'week') { $wd = (((GmTime $t)[6]) + 6) % 7; return 'week of ' + (DateT ($t - $wd * 86400 - ($t % 86400))) }
    foreach ($s in (L $sprints)) { if ($t -ge $s[1] -and $t -lt $s[2]) { return $s[0] } }
    return 'no sprint'
}
$script:CLOSES_RE = '\b(?:[Cc]los(?:e|es|ed|ing)|[Ff]ix(?:|es|ed|ing)|[Rr]esolv(?:e|es|ed|ing)|[Ii]mplement(?:s|ed|ing)?)\s*:?\s+((?:#\d+(?:\s*,\s*|\s+and\s+|\s+)?)+)'
function GL-analytics($gl, $p, $o) {
    $by = Dor $o.by 'sprint'
    if ($by -cnotmatch '^(sprint|week|month)$') { throw "GitLab: analytics --by is sprint, week or month, not '$by'`n" }
    $since = 0; if ($null -ne $o.since) { $since = TParse $o.since; if ($null -eq $since) { throw "GitLab: bad date '$($o.since)'`n" } }
    if ($null -ne $o.until) { $u = TParse $o.until; if ($null -eq $u) { throw "GitLab: bad date '$($o.until)'`n" }; $until = $u + $(if ([string]$o.until -cmatch 'T') { 0 } else { 86399 }) } else { $until = GL-epoch $gl }
    $in = { param($t) $null -ne $t -and $t -ge $since -and $t -le $until }
    $proj = GL-project $gl $p
    $dev = Dor $proj.default_branch 'main'
    $sprints = @()
    if ([string](Dor $o.sprints_from 'milestones') -ceq 'iterations') {
        $g = Dor $o.group $(if ($p -cmatch '^(.*)/') { $matches[1] })
        foreach ($i in (GL-iterations $gl $g)) { if ($i.start_date -and $i.due_date) { $sprints += , @(('Sprint ' + (Dor $i.sequence '?')), (TParse $i.start_date), ((TParse $i.due_date) + 86400)) } }
    } else {
        foreach ($m in (GL-milestones $gl $p)) { if (([string](Dor $m.title '')) -match '(?i)sprint' -and $m.start_date -and $m.due_date) { $sprints += , @($m.title, (TParse $m.start_date), ((TParse $m.due_date) + 3 * 86400)) } }
    }
    $sprints = SortWith $sprints { param($a, $b) NumCmp $a[1] $b[1] }
    $per = { param($t) Period $t $by $sprints }
    $periods = NewH
    $RP = O 'project' $p 'by' $by 'since' $(if ($since) { IsoT $since } else { $null }) 'until' (IsoT $until) 'default_branch' $dev
    $mrs = GL-mrs $gl $p (O 'state' 'all')
    $issue = NewH; foreach ($i in (GL-issues $gl $p (O 'state' 'all'))) { $issue[[string]$i.iid] = $i }
    $mr = @(); $author = NewH
    foreach ($m in (SortWith $mrs { param($a, $b) NumCmp $a.iid $b.iid })) {
        $open = TParse $m.created_at; $merged = TParse $m.merged_at
        if (-not ((& $in $open) -or (& $in $merged))) { continue }
        $commits = GL-mr_commits $gl $p $m.iid
        $fs = SortNum (Map-L $commits { param($c) TParse (Dor $c.authored_date $c.created_at) }); $first = $(if ($fs.Count) { $fs[0] } else { $null })
        $au = [string](Dor (HGet $m.author 'username') '')
        $rv = SortNum (Map-L (Where-L (GL-mr_notes $gl $p $m.iid) { param($n) [string](Dor (HGet $n.author 'username') '') -cne $au -and (-not (Tru $n.system) -or ([string](Dor $n.body '')) -cmatch '^approved this merge request') }) { param($n) TParse $n.created_at })
        $review = $(if ($rv.Count) { $rv[0] } else { $null })
        $closes = @(); foreach ($mm in [regex]::Matches([string](Dor $m.description ''), $script:CLOSES_RE)) { foreach ($x in [regex]::Matches($mm.Groups[1].Value, '#(\d+)')) { $closes += $x.Groups[1].Value } }
        $fix = $(if (((L $m.labels) -ccontains 'fix-forward') -or ([string](Dor $m.title '')) -cmatch '^Revert\b') { 1 } else { 0 })
        $r = O 'iid' $m.iid 'title' $m.title 'author' $au 'source' $m.source_branch 'target' $m.target_branch 'state' $m.state 'opened' $open 'merged' $merged 'first_commit' $first 'first_review' $review 'closes' $closes 'fix' $fix
        $mr += , $r
        if ($null -eq $author[$au]) { $author[$au] = NewH }
        if (& $in $open) { $author[$au].opened = [long](Dor $author[$au].opened 0) + 1 }
        if (& $in $merged) { $author[$au].merged = [long](Dor $author[$au].merged 0) + 1 }
    }
    $h = { param($a, $b) if ($null -ne $a -and $null -ne $b) { ($b - $a) / 3600 } else { $null } }
    $vs = @()
    foreach ($r in $mr) {
        if (-not ($r.merged -and $r.closes.Count)) { continue }
        foreach ($n in $r.closes) {
            $i = $issue[[string]$n]; if (-not $i) { continue }
            $c = TParse $i.created_at; $x = TParse $i.closed_at
            $vs += , (O 'issue' $n 'mr' $r.iid 'created' $c 'closed' $x 'plan' (& $h $c $r.first_commit) 'code' (& $h $r.first_commit $r.opened) 'review' (& $h $r.opened $r.first_review) `
                'approve' (& $h $r.first_review $r.merged) 'close' (& $h $r.merged $x) 'total' (& $h $c $x))
        }
    }
    $stages = @(@('plan', 'issue created -> first commit'), @('code', 'first commit -> MR opened'), @('review', 'MR opened -> first review'),
                @('approve', 'first review -> merged'), @('close', 'merged -> issue closed'), @('total', 'issue created -> issue closed'))
    $RP.value_stream = O 'items' $vs 'stages' (Map-L $stages { param($s) $v = Map-L $vs { param($x) $x[$s[0]] }
        O 'stage' $s[0] 'label' $s[1] 'n' (Where-L $v { param($y) $null -ne $y }).Count 'median' (R1 (Median $v)) 'p85' (R1 (Pct 0.85 $v)) })
    $pl = @()
    foreach ($x in (SortWith (GL-pipelines $gl $p (NewH)) { param($a, $b) NumCmp $a.id $b.id })) {
        $t = TParse $x.created_at
        if (-not (& $in $t)) { continue }
        $jobs = $(if (IsLocal $gl) { L $x.jobs } else { GL-jobs $gl $p $x.id })
        $st = Where-L (Map-L $jobs { param($j) TParse $j.started_at }) { param($y) $null -ne $y }
        $fi = Where-L (Map-L $jobs { param($j) TParse $j.finished_at }) { param($y) $null -ne $y }
        $dur = $(if ($null -ne $x.duration) { $x.duration } elseif ($st.Count -and $fi.Count) { $mx = SortNum $fi; $mn = SortNum $st; $mx[$mx.Count - 1] - $mn[0] } else { $null })
        $pl += , (O 'id' $x.id 'ref' $x.ref 'source' $x.source 'status' $x.status 't' $t 'end' ($t + (Dor $dur 0)) 'minutes' $(if ($null -ne $dur) { $dur / 60 } else { $null }) `
            'failed_jobs' (Map-L (Where-L $jobs { param($j) $j.status -ceq 'failed' -and -not (Tru $j.allow_failure) }) { param($j) $j.name }) `
            'jobs' (Map-L $jobs { param($j) , @($j.name, $j.status, $(if (Tru $j.allow_failure) { 1 } else { 0 })) }))
    }
    $dep = @()
    foreach ($d in (GL-deployments $gl $p (NewH))) {
        if ([string](Dor (HGet $d.environment 'name') '') -ceq 'pages' -and [string](Dor $d.status 'success') -ceq 'success') { $t = TParse $d.created_at; if (& $in $t) { $dep += , (O 't' $t 'what' 'pages deployment') } }
    }
    foreach ($r in (GL-releases $gl $p)) { $t = TParse (Dor $r.released_at $r.created_at); if (& $in $t) { $dep += , (O 't' $t 'what' "release $($r.tag_name)") } }
    $dmr = Where-L $mr { param($r) $r.target -ceq $dev -and (& $in $r.merged) }
    $lead = Map-L (Where-L $dmr { param($r) $null -ne $r.first_commit }) { param($r) ($r.merged - $r.first_commit) / 3600 }
    $fails = (Where-L $dmr { param($r) $r.fix }).Count
    $base = (Where-L $dmr { param($r) -not $r.fix }).Count
    $restore = @(); $red = $null
    foreach ($x in (Where-L $pl { param($q) $q.ref -ceq $dev -and $q.source -cne 'merge_request_event' -and $q.status -cmatch '^(success|failed)$' })) {
        if ($x.status -ceq 'failed') { if ($null -eq $red) { $red = $x.t } }
        elseif ($null -ne $red) { $restore += ($x.end - $red) / 3600; $red = $null }
    }
    $firstOpen = $null; $ops = SortNum (Map-L $mr { param($r) $r.opened }); if ($ops.Count) { $firstOpen = $ops[0] }
    $from = $(if ($since) { $since } elseif ($null -ne $firstOpen) { $firstOpen } else { $until })
    $weeks = ($until - $from) / (7 * 86400)
    $RP.dora = O 'deployments' $dep.Count 'per_week' $(if ($weeks -gt 0) { PNum (FmtF ($dep.Count / $weeks) 2) } else { $null }) 'deploy_list' (SortWith $dep { param($a, $b) NumCmp $a.t $b.t }) `
        'lead_median' (R1 (Median $lead)) 'lead_p85' (R1 (Pct 0.85 $lead)) 'merges' $base 'failures' $fails 'change_failure_rate' $(if ($base) { PNum (FmtF (100 * $fails / $base) 1) } else { $null }) `
        'restore_median' (R1 (Median $restore)) 'restore_p85' (R1 (Pct 0.85 $restore)) 'restores' $restore.Count 'still_red' $(if ($null -ne $red) { 1 } else { 0 })
    $jf = NewH; $jr = NewH
    foreach ($x in $pl) { foreach ($j in (L $x.jobs)) { if ($j[1] -cnotmatch '^(success|failed)$') { continue }; $jr[$j[0]] = [long](Dor $jr[$j[0]] 0) + 1; if ($j[1] -ceq 'failed' -and -not $j[2]) { $jf[$j[0]] = [long](Dor $jf[$j[0]] 0) + 1 } } }
    $ok = (Where-L $pl { param($x) $x.status -ceq 'success' }).Count
    $bad = (Where-L $pl { param($x) $x.status -ceq 'failed' }).Count
    $cip = NewH
    foreach ($x in $pl) { $k = & $per $x.t; if (-not $periods.ContainsKey($k)) { $periods[$k] = $x.t }; Push $cip $k $x }
    $jobsort = SortWith @($jr.Keys) { param($a, $b) $c = NumCmp (Dor $jf[$b] 0) (Dor $jf[$a] 0); if ($c -ne 0) { $c } else { OrdCmp $a $b } }
    $RP.ci = O 'pipelines' $pl.Count 'success' $ok 'failed' $bad 'success_rate' $(if ($ok + $bad) { PNum (FmtF (100 * $ok / ($ok + $bad)) 1) } else { $null }) `
        'median_minutes' (R1 (Median (Map-L $pl { param($x) $x.minutes }))) 'p85_minutes' (R1 (Pct 0.85 (Map-L $pl { param($x) $x.minutes }))) `
        'jobs' (Map-L $jobsort { param($k) O 'job' $k 'runs' $jr[$k] 'failed' (Dor $jf[$k] 0) }) `
        'trend' (Map-L @($cip.Keys) { param($k) $xs = L $cip[$k]; $s = (Where-L $xs { param($y) $y.status -ceq 'success' }).Count; $f = (Where-L $xs { param($y) $y.status -ceq 'failed' }).Count
            O 'period' $k 'pipelines' $xs.Count 'success' $s 'failed' $f 'rate' $(if ($s + $f) { PNum (FmtF (100 * $s / ($s + $f)) 1) } else { $null }) 'median_minutes' (R1 (Median (Map-L $xs { param($y) $y.minutes }))) })
    $mp = NewH
    foreach ($r in (Where-L $mr { param($r) & $in $r.merged })) { $k = & $per $r.merged; if (-not $periods.ContainsKey($k)) { $periods[$k] = $r.merged }; Push $mp $k $r }
    $ttm = Map-L (Where-L $mr { param($r) & $in $r.merged }) { param($r) ($r.merged - $r.opened) / 3600 }
    $rev = Map-L (Where-L $mr { param($r) $null -ne $r.first_review -and (& $in $r.opened) }) { param($r) ($r.first_review - $r.opened) / 3600 }
    $RP.mrs = O 'opened' (Where-L $mr { param($r) & $in $r.opened }).Count 'merged' $ttm.Count 'ttm_median' (R1 (Median $ttm)) 'ttm_p85' (R1 (Pct 0.85 $ttm)) `
        'review_median' (R1 (Median $rev)) 'review_p85' (R1 (Pct 0.85 $rev)) `
        'authors' (Map-L (SortStr @($author.Keys)) { param($a) O 'author' $a 'opened' (Dor $author[$a].opened 0) 'merged' (Dor $author[$a].merged 0) }) `
        'throughput' (Map-L @($mp.Keys) { param($k) $xs = L $mp[$k]; O 'period' $k 'merged' $xs.Count 'ttm_median' (R1 (Median (Map-L $xs { param($y) ($y.merged - $y.opened) / 3600 }))) `
            'review_median' (R1 (Median (Map-L $xs { param($y) if ($null -ne $y.first_review) { ($y.first_review - $y.opened) / 3600 } else { $null } }))) }) 'list' $mr
    $flow = NewH; $age = @()
    foreach ($i in @($issue.Values)) {
        $type = $null; foreach ($l in (L $i.labels)) { if ([string]$l -cmatch '^type::(.+)') { $type = $matches[1]; break } }
        if ($null -eq $type) { $type = Dor $i.issue_type 'issue' }
        $c = TParse $i.created_at; $x = TParse $i.closed_at
        if (& $in $c) { $k = & $per $c; if (-not $periods.ContainsKey($k)) { $periods[$k] = $c }; if (-not $flow[$k]) { $flow[$k] = NewH }; if (-not $flow[$k][$type]) { $flow[$k][$type] = NewH }; $flow[$k][$type].opened = [long](Dor $flow[$k][$type].opened 0) + 1 }
        if (& $in $x) { $k = & $per $x; if (-not $periods.ContainsKey($k)) { $periods[$k] = $x }; if (-not $flow[$k]) { $flow[$k] = NewH }; if (-not $flow[$k][$type]) { $flow[$k][$type] = NewH }; $flow[$k][$type].closed = [long](Dor $flow[$k][$type].closed 0) + 1 }
        if ($c -le $until -and ($null -eq $x -or $x -gt $until)) { $age += , (O 'iid' $i.iid 'type' $type 'title' $i.title 'days' (($until - $c) / 86400)) }
    }
    $fl = @(); foreach ($k in @($flow.Keys)) { foreach ($t in (SortStr @($flow[$k].Keys))) { $fl += , (O 'period' $k 'type' $t 'opened' (Dor $flow[$k][$t].opened 0) 'closed' (Dor $flow[$k][$t].closed 0)) } }
    $ol = Map-L (SortWith $age { param($a, $b) $c = NumCmp $b.days $a.days; if ($c -ne 0) { $c } else { NumCmp $a.iid $b.iid } }) { param($x) $y = Copy-H $x; $y.days = R1 $x.days; $y }
    $RP.issues = O 'flow' $fl 'open' $age.Count 'age_median_days' (R1 (Median (Map-L $age { param($x) $x.days }))) 'age_p85_days' (R1 (Pct 0.85 (Map-L $age { param($x) $x.days }))) 'open_list' $ol
    $RP.issues.oldest = @(); for ($i = 0; $i -lt $ol.Count -and $i -le 9; $i++) { $RP.issues.oldest += , $ol[$i] }
    $byord = { param($a, $b) NumCmp $periods[$a.period] $periods[$b.period] }
    $RP.ci.trend = SortWith $RP.ci.trend $byord
    $RP.mrs.throughput = SortWith $RP.mrs.throughput $byord
    $RP.issues.flow = SortWith $RP.issues.flow { param($a, $b) $c = NumCmp $periods[$a.period] $periods[$b.period]; if ($c -ne 0) { $c } else { OrdCmp $a.type $b.type } }
    return $RP
}
function Dash($v) { if ($null -eq $v) { return '-' }; return (PStr $v) }
function AnalyticsText($AN) {
    $o = "GitLab analytics: $($AN.project), " + (Dor $AN.since 'start') + " .. $($AN.until), by $($AN.by)`n"
    $o += "`n1. Value stream (hours; $((L $AN.value_stream.items).Count) issues closed by merge requests)`n"
    $o += ('   {0,-34} {1,5} {2,8} {3,8}' -f 'stage', 'n', 'median', 'p85') + "`n"
    foreach ($s in (L $AN.value_stream.stages)) { $o += ('   {0,-34} {1,5} {2,8} {3,8}' -f $s.label, (PStr $s.n), (Dash $s.median), (Dash $s.p85)) + "`n" }
    $d = $AN.dora
    $o += "`n2. DORA, for a model repository`n"
    $o += ('   {0,-34} {1} ({2} a week)' -f 'deployment frequency', (PStr $d.deployments), (Dash $d.per_week)) + "`n"
    $o += ('   {0,-34} median {1} h, p85 {2} h' -f "lead time (first commit -> merged on $($AN.default_branch))", (Dash $d.lead_median), (Dash $d.lead_p85)) + "`n"
    $o += ('   {0,-34} {1}% ({2} fix-forward or revert MRs / {3} merges)' -f 'change failure rate', (Dash $d.change_failure_rate), (PStr $d.failures), (PStr $d.merges)) + "`n"
    $o += ('   {0,-34} median {1} h, p85 {2} h ({3} restores{4})' -f "time to restore ($($AN.default_branch) red -> green)", (Dash $d.restore_median), (Dash $d.restore_p85), (PStr $d.restores), $(if ($d.still_red) { ', red now' } else { '' })) + "`n"
    $c = $AN.ci
    $o += "`n3. CI/CD: $($c.pipelines) pipelines, success rate " + (Dash $c.success_rate) + "%, duration median " + (Dash $c.median_minutes) + " min, p85 " + (Dash $c.p85_minutes) + " min`n"
    $o += ('   {0,-28} {1,6} {2,8} {3,8} {4,12}' -f 'period', 'runs', 'failed', 'success%', 'median min') + "`n"
    foreach ($t in (L $c.trend)) { $o += ('   {0,-28} {1,6} {2,8} {3,8} {4,12}' -f $t.period, (PStr $t.pipelines), (PStr $t.failed), (Dash $t.rate), (Dash $t.median_minutes)) + "`n" }
    $jf = (@(foreach ($j in (L $c.jobs)) { if ($j.failed) { "$($j.job) $($j.failed)/$($j.runs)" } })) -join ', '
    $o += "   job failures: " + $(if ($jf) { $jf } else { 'none' }) + "`n"
    $m = $AN.mrs
    $o += "`n4. Merge requests: $($m.opened) opened, $($m.merged) merged; time to merge median " + (Dash $m.ttm_median) + " h (p85 " + (Dash $m.ttm_p85) + " h); review turnaround median " + (Dash $m.review_median) + " h (p85 " + (Dash $m.review_p85) + " h)`n"
    $o += ('   {0,-28} {1,7} {2,12} {3,14}' -f 'period', 'merged', 'ttm median h', 'review median h') + "`n"
    foreach ($t in (L $m.throughput)) { $o += ('   {0,-28} {1,7} {2,12} {3,14}' -f $t.period, (PStr $t.merged), (Dash $t.ttm_median), (Dash $t.review_median)) + "`n" }
    $o += "   per author: " + ((@(foreach ($a in (L $m.authors)) { "$($a.author) $($a.merged)/$($a.opened)" })) -join ', ') + " (merged/opened)`n"
    $i = $AN.issues
    $o += "`n5. Issues: $($i.open) open, age median " + (Dash $i.age_median_days) + " days, p85 " + (Dash $i.age_p85_days) + " days`n"
    $o += ('   {0,-28} {1,-14} {2,7} {3,7}' -f 'period', 'type', 'opened', 'closed') + "`n"
    foreach ($f in (L $i.flow)) { $o += ('   {0,-28} {1,-14} {2,7} {3,7}' -f $f.period, $f.type, (PStr $f.opened), (PStr $f.closed)) + "`n" }
    $old = L $i.oldest
    if ($old.Count) { $lim = $(if ($old.Count -lt 5) { $old.Count } else { 5 }); $o += "   oldest open: " + ((@(for ($k = 0; $k -lt $lim; $k++) { "#$($old[$k].iid) ($($old[$k].type), $(PStr $old[$k].days) d)" })) -join ', ') + "`n" }
    return $o
}
function CsvCell($v) { $v = PStr $v; if ($v -cmatch '[",\r\n]') { return '"' + $v.Replace('"', '""') + '"' }; return $v }
function WriteCsv([string]$path, $head, $rows) {
    $t = ((L $head) -join ',') + "`n"
    foreach ($r in (L $rows)) { $t += ((@(foreach ($c in (L $r)) { CsvCell $c })) -join ',') + "`n" }
    WriteText $path $t
    return (L $rows).Count
}
function AnalyticsCsv($AN, [string]$dir) {
    $null = New-Item -ItemType Directory -Path $dir -Force
    if (-not (Test-Path -LiteralPath $dir -PathType Container)) { throw "GitLab: cannot create $dir`n" }
    $n = NewH
    $iso = { param($t) if ($null -ne $t) { IsoT $t } else { '' } }
    $n['value_stream.csv'] = WriteCsv "$dir/value_stream.csv" @('issue', 'mr', 'issue_created', 'issue_closed', 'plan_h', 'code_h', 'review_h', 'approve_h', 'close_h', 'total_h') `
        (Map-L $AN.value_stream.items { param($x) , @($x.issue, $x.mr, (& $iso $x.created), (& $iso $x.closed), (Dor (R1 $x.plan) ''), (Dor (R1 $x.code) ''), (Dor (R1 $x.review) ''), (Dor (R1 $x.approve) ''), (Dor (R1 $x.close) ''), (Dor (R1 $x.total) '')) })
    $d = $AN.dora
    $n['dora.csv'] = WriteCsv "$dir/dora.csv" @('metric', 'value') @(@('deployments', $d.deployments), @('deployments_per_week', $d.per_week), @('lead_time_median_h', $d.lead_median),
        @('lead_time_p85_h', $d.lead_p85), @('merges', $d.merges), @('failures', $d.failures), @('change_failure_rate_pct', $d.change_failure_rate),
        @('time_to_restore_median_h', $d.restore_median), @('time_to_restore_p85_h', $d.restore_p85))
    $n['deployments.csv'] = WriteCsv "$dir/deployments.csv" @('time', 'what') (Map-L $d.deploy_list { param($x) , @((IsoT $x.t), $x.what) })
    $n['pipelines.csv'] = WriteCsv "$dir/pipelines.csv" @('period', 'pipelines', 'success', 'failed', 'success_pct', 'median_minutes') (Map-L $AN.ci.trend { param($x) , @($x.period, $x.pipelines, $x.success, $x.failed, $x.rate, $x.median_minutes) })
    $n['job_failures.csv'] = WriteCsv "$dir/job_failures.csv" @('job', 'runs', 'failed') (Map-L $AN.ci.jobs { param($x) , @($x.job, $x.runs, $x.failed) })
    $n['mr_throughput.csv'] = WriteCsv "$dir/mr_throughput.csv" @('period', 'merged', 'ttm_median_h', 'review_median_h') (Map-L $AN.mrs.throughput { param($x) , @($x.period, $x.merged, $x.ttm_median, $x.review_median) })
    $n['mr_authors.csv'] = WriteCsv "$dir/mr_authors.csv" @('author', 'opened', 'merged') (Map-L $AN.mrs.authors { param($x) , @($x.author, $x.opened, $x.merged) })
    $n['mr_list.csv'] = WriteCsv "$dir/mr_list.csv" @('iid', 'title', 'author', 'source', 'target', 'state', 'opened', 'first_commit', 'first_review', 'merged', 'fix') `
        (Map-L $AN.mrs.list { param($x) , @($x.iid, $x.title, $x.author, $x.source, $x.target, $x.state, (& $iso $x.opened), (& $iso $x.first_commit), (& $iso $x.first_review), (& $iso $x.merged), $x.fix) })
    $n['issue_flow.csv'] = WriteCsv "$dir/issue_flow.csv" @('period', 'type', 'opened', 'closed') (Map-L $AN.issues.flow { param($x) , @($x.period, $x.type, $x.opened, $x.closed) })
    $n['open_issues.csv'] = WriteCsv "$dir/open_issues.csv" @('iid', 'type', 'age_days', 'title') (Map-L $AN.issues.open_list { param($x) , @($x.iid, $x.type, $x.days, $x.title) })
    return $n
}

# ---------------------------------------------------------------- export: CSVs for status-metrics and the sprint tracker
function GL-export($gl, $p, [string]$dir, $o) {
    $null = New-Item -ItemType Directory -Path "$dir/tracker" -Force
    if (-not (Test-Path -LiteralPath $dir -PathType Container)) { throw "GitLab: cannot create $dir`n" }
    $since = Dor $o.since '0000'; $until = Dor $o.until '9999'
    $s10 = $(if ($since.Length -gt 10) { $since.Substring(0, 10) } else { $since }); $u10 = $(if ($until.Length -gt 10) { $until.Substring(0, 10) } else { $until })
    $in = { param($t) $d = [string](Dor $t ''); if ($d.Length -gt 10) { $d = $d.Substring(0, 10) }; (OrdCmp $d $s10) -ge 0 -and (OrdCmp $d $u10) -le 0 }
    $n = NewH
    $jobs = @()
    foreach ($pl in (SortWith (GL-pipelines $gl $p (NewH)) { param($a, $b) NumCmp $a.id $b.id })) {
        $js = $(if (IsLocal $gl) { L $pl.jobs } else { GL-jobs $gl $p $pl.id })
        foreach ($j in (SortWith $js { param($a, $b) $c = OrdCmp ([string](Dor $a.started_at '')) ([string](Dor $b.started_at '')); if ($c -ne 0) { $c } else { NumCmp $a.id $b.id } })) {
            if (-not ($j.started_at -and (& $in $j.started_at))) { continue }
            if ($j.status -ceq 'success') { $r = 'pass' } elseif ($j.status -ceq 'failed') { $r = $(if (Tru $j.allow_failure) { 'warn' } else { 'fail' }) } else { continue }
            $jobs += , @($j.started_at, $j.name, $pl.ref, $r, (FmtF ((PNum (Dor $j.duration 0)) / 60) 2))
        }
    }
    $n.ci_jobs = WriteCsv "$dir/ci_jobs.csv" @('ts', 'job', 'branch', 'result', 'minutes') $jobs
    $mr = @()
    foreach ($m in (SortWith (GL-mrs $gl $p (NewH)) { param($a, $b) NumCmp $a.iid $b.iid })) {
        if (-not (& $in $m.created_at)) { continue }
        $lead = $(if ($m.merged_at) { FmtF (((Epoch $m.merged_at) - (Epoch $m.created_at)) / 3600) 1 } else { '' })
        $mr += , @($m.iid, $m.title, (Dor (HGet $m.author 'username') ''), $m.source_branch, $m.target_branch, $m.created_at, (Dor $m.merged_at ''), $lead, ((L $m.labels) -join ';'), $m.state)
    }
    $n.mrs = WriteCsv "$dir/mrs.csv" @('iid', 'title', 'author', 'source', 'target', 'created_at', 'merged_at', 'lead_hours', 'labels', 'state') $mr
    $issues = GL-issues $gl $p (O 'state' 'all')
    $type = { param($i) foreach ($l in (L $i.labels)) { if ([string]$l -cmatch '^type::(.+)') { return $matches[1] } }; Dor $i.issue_type 'issue' }
    $mil = { param($i) if ($i.milestone -is [hashtable]) { $i.milestone.title } else { '' } }
    $rows = Map-L (Where-L (SortWith $issues { param($a, $b) NumCmp $a.iid $b.iid }) { param($i) & $in $i.created_at }) { param($i)
        , @($i.iid, (& $type $i), $i.title, ((L $i.labels) -join ';'), (& $mil $i), ((@(foreach ($a in (L $i.assignees)) { $a.username })) -join ';'), $i.state, $i.created_at, (Dor $i.closed_at '')) }
    $n.issues = WriteCsv "$dir/issues.csv" @('iid', 'type', 'title', 'labels', 'milestone', 'assignee', 'state', 'created_at', 'closed_at') $rows
    $def = @()
    foreach ($i in (SortWith $issues { param($a, $b) NumCmp $a.iid $b.iid })) {
        if (-not ((L $i.labels) | Where-Object { $_ -ceq 'type::defect' -or $_ -ceq 'type::discrepancy' })) { continue }
        $area = $null; $phase = $null
        foreach ($l in (L $i.labels)) { if ($null -eq $area -and [string]$l -cmatch '^area::(.+)') { $area = $matches[1] }; if ($null -eq $phase -and [string]$l -cmatch '^phase::(.+)') { $phase = $matches[1] } }
        $def += , @("#$($i.iid)", (Dor $area ''), (Dor $phase ''), ([string]$i.created_at).Substring(0, 10), $(if ($i.closed_at) { ([string]$i.closed_at).Substring(0, 10) } else { '' }))
    }
    $n.defects = WriteCsv "$dir/defects.csv" @('id', 'type', 'phase', 'found', 'closed') $def
    $sp = NewH
    foreach ($i in (L $issues)) { $t = & $mil $i; if ([string]$t -cmatch '(\d+)\s*$' -and ((L $i.labels) | Where-Object { $_ -ceq 'type::story' -or $_ -ceq 'type::task' })) { Push $sp $matches[1] $i } }
    foreach ($s in (SortNum @($sp.Keys))) {
        $rows = Map-L (SortWith $sp[[string]$s] { param($a, $b) NumCmp $a.iid $b.iid }) { param($i) $bd = GL-_blocked $gl $i; , @("#$($i.iid)", $(if ($i.state -ceq 'closed') { 'done' } else { 'open' }), $bd[0], $bd[1]) }
        $null = WriteCsv "$dir/tracker/sprint-$s.csv" @('id', 'status', 'blocked_days', 'blocker') $rows
        $n.tracker = [long](Dor $n.tracker 0) + 1
    }
    return $n
}
function GL-_blocked($gl, $i) {
    $from = $null; $days = 0; $why = ''
    foreach ($n in (L $i.notes)) {
        if ((Tru $n.system) -and [string]$n.body -cmatch 'added ~"?workflow::blocked') { $from = Epoch $n.created_at }
        elseif ((Tru $n.system) -and [string]$n.body -cmatch 'removed ~"?workflow::blocked' -and $null -ne $from) { $days += WDays $from (Epoch $n.created_at); $from = $null }
        elseif (-not (Tru $n.system) -and [string]$n.body -cmatch '(?im)^\s*(?:Blocked(?: by)?|Blocker)\s*:\s*(.+)$') { $why = $matches[1] }
    }
    if ($null -ne $from) { $days += WDays $from $(if ($i.closed_at) { Epoch $i.closed_at } else { GL-epoch $gl }) }
    return , @($days, $why)
}
function WDays([long]$a, [long]$b) { $n = 0; for ($t = $a; $t -lt $b; $t += 86400) { $w = (GmTime $t)[6]; if ($w -gt 0 -and $w -lt 6) { $n++ } }; return $n }

# ---------------------------------------------------------------- setup --diff: the drift against a project file
function GL-diff_project_file($gl, [string]$path, $o) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "GitLab: cannot read ${path}: No such file or directory`n" }
    $c = ParseProjectFile (ReadText $path) $path
    $pr = KV $c.project
    $p = Dor $o.project $pr.path
    if ($null -eq $p) { throw "${path}: [project] needs path = group/name`n" }
    $proj = $null; try { $proj = GL-project $gl $p } catch { $proj = $null }
    if (-not $proj) { return , @("[project] ${p}: missing (setup creates it)") }
    $d = @()
    $name = NewH; foreach ($k in @($script:LEVEL.Keys)) { $name[[string]$script:LEVEL[$k]] = $k }; $name['0'] = 'none'; $name['60'] = 'admin'
    $ln = { param($l) $l = Dor $l 0; if ($name.ContainsKey([string]$l)) { $name[[string]$l] } else { PStr $l } }
    $bool = { param($v) if ($v -is [bool]) { if ($v) { 1 } else { 0 } } elseif ($null -ne $v -and [string]$v -cmatch '^(?i)(1|true|yes|on)$') { 1 } else { 0 } }
    $live = $(if (IsLocal $gl) { $x = Copy-H $proj.settings; $x.default_branch = $proj.default_branch; $x } else { $proj })
    foreach ($k in (SortStr @($pr.Keys))) {
        if ($k -ceq 'path') { continue }
        $f = $pr[$k]; $l = $live[$k]
        $same = $(if ($f -cmatch '^(?i)(true|false|yes|no|on|off)$' -or $l -is [bool] -or ($null -ne $l -and (PStr $l) -cmatch '^[01]$')) { (& $bool $f) -eq (& $bool $l) } else { (PStr (Dor $l '')) -ceq $f })
        if (-not $same) { $d += "[project] ${k}: file $f, live " + $(if ($l -is [bool]) { $(if ($l) { 'true' } else { 'false' }) } elseif ($null -eq $l) { '(unset)' } else { PStr $l }) }
    }
    $mem = GL-members $gl $p
    $fm = NewH
    foreach ($x in (L $c.members)) {
        $want = LevelOf $x[1]; $fm[$x[0]] = 1
        $have = $mem[$x[0]]
        if ($null -eq $have) { $d += "[members] $($x[0]): missing (file $($x[1]))" }
        elseif ([long]$have -ne [long]$want) { $d += "[members] $($x[0]): file $($x[1]), live " + (& $ln $have) }
    }
    if ($c.members) { foreach ($k in (SortStr @($mem.Keys))) { if (-not $fm.ContainsKey($k) -and $k -cne 'root') { $d += "[members] ${k}: live only (" + (& $ln $mem[$k]) + ')' } } }
    $ll = NewH; foreach ($l in (GL-labels $gl $p)) { $ll[$l.name] = $l }
    $sts = $(if ($c.statuses) { ParseStatuses $c.statuses $path $p } else { $null })
    if ($sts) {
        $want = (L $sts.marks); if ($sts.mode -ceq 'labels') { $want += @(foreach ($s in (L $sts.statuses)) { "state::$($s.name)" }) }
        foreach ($l in $want) {
            $x = $ll[$l]; if ($ll.ContainsKey($l)) { $ll.Remove($l) }
            if (-not $x) { $d += "[statuses] label ${l}: missing"; continue }
            $wc = $(if ($l -cmatch '^state::(.+)$') { $nm = $matches[1]; (First $sts.statuses { param($s) $s.name -ceq $nm }).color } else { $sts.mark_color })
            if (([string](Dor $x.color '')).ToLowerInvariant() -cne ([string]$wc).ToLowerInvariant()) { $d += "[statuses] label ${l}: color differs" }
        }
        if ($sts.mode -ceq 'statuses' -and (L $sts.statuses).Count) {
            $lc = $null; try { $lc = GL-lifecycle $gl $sts.group } catch { $lc = $null }
            if (-not $lc) { $d += "[statuses] $($sts.group): no lifecycle (statuses need GitLab 18.2+, Premium or Ultimate)" }
            else {
                $ls = NewH; foreach ($s in (L $lc.statuses)) { $ls[$s.name] = $s }
                foreach ($w in (L $sts.statuses)) {
                    $l = $ls[$w.name]
                    if (-not $l) { $d += "[statuses] $($w.name): missing on $($sts.group)"; continue }
                    $lcol = ([string](Dor $l.color '')).ToLowerInvariant()
                    if ($lcol -cne $w.color) { $d += "[statuses] $($w.name): color file $($w.color), live $lcol" }
                    if ([string](Dor $l.category '') -cne $w.category) { $d += "[statuses] $($w.name): category file $($w.category), live " + (Dor $l.category '') }
                }
                foreach ($k in @('open', 'closed', 'duplicate')) {
                    $f = StatusDefault $sts.statuses $k
                    if ([string](Dor $lc["default_$k"] '') -cne [string]$f) { $d += "[statuses] default ${k}: file $f, live " + (Dor $lc["default_$k"] '(unset)') }
                }
            }
        }
    }
    foreach ($x in (L $c.labels)) {
        if ($x[1] -cnotmatch '^\s*(#[0-9A-Fa-f]{6})\s*(?:\|\s*(.*))?$') { throw "${path}:$($x[2]): label value is '#RRGGBB | description'`n" }
        $color = $matches[1]; $desc = $(if ($matches[2]) { $matches[2] } else { '' })
        $l = $ll[$x[0]]; if ($ll.ContainsKey($x[0])) { $ll.Remove($x[0]) }
        if (-not $l) { $d += "[labels] $($x[0]): missing"; continue }
        if ($color.ToLowerInvariant() -cne ([string](Dor $l.color '')).ToLowerInvariant()) { $d += "[labels] $($x[0]): color file $color, live $($l.color)" }
        if ($desc -cne [string](Dor $l.description '')) { $d += "[labels] $($x[0]): description differs" }
    }
    if ($c.labels) { foreach ($k in (SortStr @($ll.Keys))) { $d += "[labels] ${k}: live only" } }
    $lm = NewH; foreach ($m in (GL-milestones $gl $p)) { $lm[$m.title] = $m }
    foreach ($x in (L $c.milestones)) {
        $want = @()
        if ($x[0] -ceq 'sprints') {
            $w = SplitWs $x[1] 4
            $t0 = Epoch $w[0]; $weeks = PNum (Dor $(if ($w.Count -gt 2) { $w[2] }) 2); $prefix = Dor $(if ($w.Count -gt 3) { $w[3] }) 'Sprint '
            for ($k = 1; $k -le (PNum $w[1]); $k++) { $s0 = $t0 + ($k - 1) * $weeks * 7 * 86400; $want += , @("$prefix$k", (DateT $s0), (DateT ($s0 + ($weeks * 7 - 3) * 86400))) }
        } else { $dates = @($x[1] -csplit '\s*\|\s*', 2)[0]; $dd = SplitWs (Dor $dates '') 0; $want += , @($x[0], $(if ($dd.Count) { $dd[0] }), $(if ($dd.Count -gt 1) { $dd[1] })) }
        foreach ($w in $want) {
            $m = $lm[$w[0]]
            if (-not $m) { $d += "[milestones] $($w[0]): missing"; continue }
            if ([string](Dor $w[1] '') -cne [string](Dor $m.start_date '') -or [string](Dor $w[2] '') -cne [string](Dor $m.due_date '')) {
                $d += "[milestones] $($w[0]): dates file " + (Dor $w[1] '') + '..' + (Dor $w[2] '') + ", live " + (Dor $m.start_date '') + '..' + (Dor $m.due_date '')
            }
        }
    }
    $it = ParseIterations $c.iterations $path $p
    if ((L $it.cadences).Count) {
        $lc = NewH; $cs = $null; try { $cs = GL-cadences $gl $it.group } catch { $cs = $null }; foreach ($x in (L $cs)) { $lc[$x.title] = $x }
        foreach ($w in (L $it.cadences)) {
            $l = $lc[$w.title]
            if (-not $l) { $d += "[iterations] $($w.title): missing on group $($it.group)"; continue }
            foreach ($k in @('start_date', 'duration_in_weeks', 'iterations_in_advance', 'automatic', 'roll_over')) {
                $f = $w[$k]; $v = $l[$k]
                if ($k -cmatch '^(automatic|roll_over)$') { $f = $(if (Tru $f) { 'yes' } else { 'no' }); $v = $(if (Tru $v) { 'yes' } else { 'no' }) }
                if ((PStr (Dor $v '')) -cne (PStr $f)) { $d += "[iterations] $($w.title): $k file $(PStr $f), live " + $(if ($null -eq $v) { '(unset)' } else { PStr $v }) }
            }
        }
    }
    if ($c.boards) {
        $bd = NewH; foreach ($b in (GL-boards $gl $p)) { $bd[$b.name] = $b }
        $bit = NewH
        if (First $c.boards { param($b) $b[1] -cmatch ' iteration=| sprint=' }) { try { $bit = Dor (GL-board_iterations $gl $p) (NewH) } catch { $bit = NewH } }
        foreach ($x in (L $c.boards)) {
            $w = ParseBoardLine $x[1] "${path}:$($x[2])" $it.use
            $bo = $bd[$x[0]]
            if (-not $bo) { $d += "[boards] $($x[0]): missing"; continue }
            $bl = (L $bo.lists)
            if (-not (IsLocal $gl) -and (First $w.labels { param($y) $y -cmatch '^status:' })) { $sl = $null; try { $sl = GL-board_status_lists $gl $p } catch { $sl = $null }; if ($sl) { $bl += (L $sl[$x[0]]) } }
            $livel = Map-L (SortWith (Where-L $bl { param($y) (ListKey $y).Length }) { param($a, $b) NumCmp (Dor $a.position 0) (Dor $b.position 0) }) { param($y) ListKey $y }
            if (($livel -join ' ') -cne ((L $w.labels) -join ' ')) { $d += "[boards] $($x[0]): lists file $((L $w.labels) -join ' '), live " + $(if ($livel.Count) { $livel -join ' ' } else { '(none)' }) }
            $ms = BoardScope $bo.milestone
            if ($ms -cne $w.milestone) { $d += "[boards] $($x[0]): milestone file $($w.milestone), live $ms" }
            $li = $(if (IsLocal $gl) { IterationScope $bo.iteration } else { Dor $bit[$x[0]] 'any' })
            if ($li -cne $w.iteration) { $d += "[boards] $($x[0]): iteration file $($w.iteration), live $li" }
        }
    }
    if ($c.insights) {
        $yml = (InsightsYml $c $path)[0]
        $ins = KV $c.insights
        $rel = Dor $ins.file '.gitlab/insights.yml'
        $def = $(if (IsLocal $gl) { $proj.default_branch } else { Dor $proj.default_branch 'main' })
        $livef = GL-file_raw $gl $p $rel (Dor $def 'main')
        if ($null -eq $livef) { $d += "[insights] ${rel}: missing on " + (Dor $def 'main') + " (setup writes it; commit it through a merge request)" }
        elseif ($livef -cne $yml) { $d += "[insights] ${rel}: on " + (Dor $def 'main') + " differs from what the project file generates (re-run setup, commit through a merge request)" }
    }
    $pb = NewH; foreach ($b in (GL-protected_branches $gl $p)) { $pb[$b.name] = $b }
    foreach ($x in (L $c.branches)) {
        $a = NewH; foreach ($w in (SplitWs $x[1] 0)) { if ($w -cmatch '^(\w+):(\S+)$') { $a[$matches[1].ToLowerInvariant()] = $matches[2].ToLowerInvariant() } }
        $b = $pb[$x[0]]; if ($pb.ContainsKey($x[0])) { $pb.Remove($x[0]) }
        if (-not $b) { $d += "[branches] $($x[0]): not protected"; continue }
        foreach ($pp in @(@('push', 'push_access_level'), @('merge', 'merge_access_level'))) {
            $want = LevelOf (Dor $a[$pp[0]] 'maintainer')
            if ([long]$want -ne [long](Dor $b[$pp[1]] 0)) { $d += "[branches] $($b.name): $($pp[0]) file " + (& $ln $want) + ", live " + (& $ln $b[$pp[1]]) }
        }
        if ($(if ((Dor $a.force 'no') -ceq 'yes') { 1 } else { 0 }) -ne $(if (Tru $b.allow_force_push) { 1 } else { 0 })) { $d += "[branches] $($b.name): force file " + (Dor $a.force 'no') + ', live ' + $(if (Tru $b.allow_force_push) { 'yes' } else { 'no' }) }
        if ($(if ((Dor $a.codeowners 'no') -ceq 'yes') { 1 } else { 0 }) -ne $(if (Tru $b.code_owner_approval_required) { 1 } else { 0 })) { $d += "[branches] $($b.name): codeowners file " + (Dor $a.codeowners 'no') + ', live ' + $(if (Tru $b.code_owner_approval_required) { 'yes' } else { 'no' }) }
    }
    if ($c.branches) { foreach ($k in (SortStr @($pb.Keys))) { $d += "[branches] ${k}: protected live only" } }
    $pt = NewH; foreach ($t in (GL-protected_tags $gl $p)) { $pt[$t.name] = $t }
    foreach ($x in (L $c.tags)) {
        $lvl = $null; if ($x[1] -cmatch '^create:(\S+)$') { $lvl = $matches[1] }
        $t = $pt[$x[0]]; if ($pt.ContainsKey($x[0])) { $pt.Remove($x[0]) }
        if (-not $t) { $d += "[tags] $($x[0]): not protected"; continue }
        if ([long](LevelOf (Dor $lvl 'maintainer')) -ne [long](Dor $t.create_access_level 0)) { $d += "[tags] $($x[0]): create file $lvl, live " + (& $ln $t.create_access_level) }
    }
    if ($c.tags) { foreach ($k in (SortStr @($pt.Keys))) { $d += "[tags] ${k}: protected live only" } }
    $ar = NewH; foreach ($r in (GL-approval_rules $gl $p)) { $ar[$r.name] = $r }
    foreach ($x in (L $c.approvals)) {
        $w = SplitWs $x[1] 0; $n = $w[0]; $users = @(); if ($w.Count -gt 1) { $users = $w[1..($w.Count - 1)] }
        $r = $ar[$x[0]]; if ($ar.ContainsKey($x[0])) { $ar.Remove($x[0]) }
        if (-not $r) { $d += "[approvals] $($x[0]): missing"; continue }
        if ((PNum $n) -ne (PNum $r.approvals_required)) { $d += "[approvals] $($x[0]): file $n required, live $(PStr $r.approvals_required)" }
        $fu = (SortStr $users) -join ' '; $lu = (SortStr (L $r.users)) -join ' '
        if ($fu -cne $lu) { $d += "[approvals] $($x[0]): users file $fu, live $lu" }
    }
    if ($c.approvals) { foreach ($k in (SortStr @($ar.Keys))) { $d += "[approvals] ${k}: live only" } }
    $vr = NewH; foreach ($v in (GL-variables $gl $p)) { $vr[$v.key] = $v }
    foreach ($x in (L $c.variables)) {
        $v = @($x[1] -csplit '\s+\|\s+')[0]
        $y = $vr[$x[0]]; if ($vr.ContainsKey($x[0])) { $vr.Remove($x[0]) }
        if (-not $y) { $d += "[variables] $($x[0]): missing" } elseif ([string](Dor $y.value '') -cne $v) { $d += "[variables] $($x[0]): value differs" }
    }
    if ($c.variables) { foreach ($k in (SortStr @($vr.Keys))) { $d += "[variables] ${k}: live only" } }
    $sc = NewH; foreach ($s in (GL-schedules $gl $p)) { $sc[$s.description] = $s }
    foreach ($x in (L $c.schedules)) {
        $f = @(@($x[1] -split '\|', 4) | ForEach-Object { $_.Trim() })
        $cron = $f[0]; $ref = $(if ($f.Count -gt 1) { $f[1] }); $tz = $(if ($f.Count -gt 2) { $f[2] }); $vars = $(if ($f.Count -gt 3) { $f[3] })
        if (-not $tz) { $tz = 'UTC' }
        $s = $sc[$x[0]]; if ($sc.ContainsKey($x[0])) { $sc.Remove($x[0]) }
        if (-not $s) { $d += "[schedules] $($x[0]): missing"; continue }
        if (-not (IsLocal $gl) -and -not $gl.dry_run) { $s = GL-_api $gl 'GET' ('/projects/' + (Enc $p) + "/pipeline_schedules/$($s.id)") }
        if ($cron -cne $s.cron) { $d += "[schedules] $($x[0]): cron file $cron, live $($s.cron)" }
        if ($ref -cne (([string]$s.ref) -creplace '^refs/heads/', '')) { $d += "[schedules] $($x[0]): ref file $ref, live $($s.ref)" }
        if ($tz -cne $s.cron_timezone) { $d += "[schedules] $($x[0]): time zone file $tz, live $($s.cron_timezone)" }
        $fv = (SortStr (SplitWs (Dor $vars '') 0)) -join ' '
        $lv = (SortStr (Map-L $s.variables { param($y) "$($y.key)=$($y.value)" })) -join ' '
        if ($fv -cne $lv) { $d += "[schedules] $($x[0]): variables file '$fv', live '$lv'" }
    }
    if ($c.schedules) { foreach ($k in (SortStr @($sc.Keys))) { $d += "[schedules] ${k}: live only" } }
    return , $d
}
