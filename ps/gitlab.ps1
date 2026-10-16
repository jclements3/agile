<#
gitlab.ps1 -- GitLab from the command line, for a PC with only Windows PowerShell 5.1 (bin/gitlab.pl of the agile kit):
project setup from one file, sprints as milestones, issues and merge requests with templates and quick actions,
pipelines, tags and releases, wiki pages, CSV exports for the status metrics, schedules, analytics, boards, statuses,
iterations, the backlog workbook, the Windchill bridge, Terraform and the Insights file.

Talks to a real GitLab (REST API v4 through Invoke-WebRequest; --url, token in $GITLAB_TOKEN) or to the offline
emulator (--local DIR; state in DIR\gitlab.json), which is how a team trains without a server. The emulator here has
no git: repository work (branches, tags, merges, pipelines) needs a server. Constrained Language Mode safe.

  gitlab.cmd --local data\gl --as tom setup .gitlab\project.conf
  gitlab.cmd --url https://gitlab.example.gov --project tidewater/model issue list --label type::story
  gitlab.cmd help [COMMAND]
#>
$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot; if (-not $here) { $here = (Get-Location).Path }
. "$here\ziplib.ps1"
. "$here\gitlab\glcore.ps1"
. "$here\gitlab\glapi.ps1"
. "$here\gitlab\glemu.ps1"
. "$here\gitlab\glsetup.ps1"
. "$here\gitlab\windchill.ps1"
. "$here\gitlab\gltf.ps1"
. "$here\gitlab\backlog.ps1"
. "$here\gitlab\glhelp.ps1"

$script:ARGS0 = @($args)
$script:RCX = 0

function GUsage($cmd) { $t = $script:GLHELP[[string](Dor $cmd '')]; if ($null -eq $t) { $t = $script:GLHELP[''] }; GErr $t; throw 'USAGE' }
function Opts($a, [string[]]$spec) {                   # opts(\@args, spec): name=s, name=s@, flag -> the options; the rest in $script:REST
    $t = NewH
    foreach ($s in $spec) { if ($s -cmatch '^([\w-]+)(=s@?)?$') { $t[$matches[1]] = $(if ($matches[2]) { $matches[2] } else { '' }) } }
    $o = NewH; $restv = @()
    $a = (L $a)
    $i = 0
    while ($i -lt $a.Count) {
        $x = [string]$a[$i]; $i++
        if ($x -cmatch '^--([\w-]+)(?:=(.*))?$' -and $t.ContainsKey($matches[1])) {
            $k = $matches[1]; $v = $(if ($matches[0].Contains('=')) { $matches[2] } else { $null })
            if ($t[$k] -ceq '') { $o[$k] = 1; continue }
            if ($null -eq $v) { if ($i -lt $a.Count) { $v = [string]$a[$i]; $i++ } else { throw "gitlab.pl: --$k needs a value`n" } }
            if ($t[$k] -ceq '=s@') { Push $o $k $v } else { $o[$k] = $v }
        } elseif ($x -cmatch '^--.') { throw "gitlab.pl: unknown option $x`n" }
        else { $restv += $x }
    }
    $script:REST = $restv
    return $o
}
function Slurp([string]$f) { if (-not (Test-Path -LiteralPath $f -PathType Leaf)) { throw "gitlab.pl: cannot read ${f}: No such file or directory`n" }; return (ReadText $f) }
function Template($name, $kind) {
    if ($null -eq $name) { return $null }
    if (Test-Path -LiteralPath $name -PathType Leaf) { return (Slurp $name) }
    $f = ".gitlab/${kind}_templates/$name.md"
    if (-not (Test-Path -LiteralPath $f -PathType Leaf)) { throw "gitlab.pl: no template '$name' ($f not found)`n" }
    return (Slurp $f)
}
function FindConf {
    $d = (Get-Location).ProviderPath -creplace '\\', '/'
    while ($true) {
        if (Test-Path -LiteralPath "$d/.gitlab/project.conf" -PathType Leaf) { return "$d/.gitlab/project.conf" }
        $up = $d -creplace '/[^/]*$', ''
        if ($up -ceq $d -or $up.Length -eq 0 -or $up -cmatch '^[A-Za-z]:$') { break }
        $d = $up
    }
    return $null
}
function IterationConf($f) {
    if ($null -eq $f) { $f = FindConf }
    if ($null -eq $f -or -not (Test-Path -LiteralPath $f -PathType Leaf)) { return (O 'use' 'milestones' 'group' $null) }
    $c = ParseProjectFile (Slurp $f) $f
    $pp = Dor $script:GOPT.project (First $c.project { param($x) $x[0] -ceq 'path' })
    if ($pp -is [array]) { $pp = $pp[1] }
    return (ParseIterations $c.iterations $f $pp)
}
function ProjectConf($conf) {
    if ($null -eq $conf) { $conf = FindConf }
    if ($null -eq $conf) { return , @((NewH), $null) }
    $c = ParseProjectFile (Slurp $conf) $conf
    if ($null -eq $script:GOPT.project) { $x = First $c.project { param($y) $y[0] -ceq 'path' }; if ($x) { $script:GOPT.project = $x[1] } }
    return , @($c, $conf)
}
function PP { if ($null -eq $script:GOPT.project) { throw "gitlab.pl: give --project GROUP/NAME (or GITLAB_PROJECT)`n" }; return $script:GOPT.project }
function Need([int]$n, [string]$what, $a) { if ((L $a).Count -lt $n) { throw "gitlab.pl: $what`n" } }
function ShowIssue($i) {
    GOut ('#{0}  {1}  {2}' -f (PStr $i.iid), $i.state, $i.title) ; GOut "`n"
    $lb = (@(foreach ($l in (L $i.labels)) { "~$l" })) -join ' '; if (-not $lb) { $lb = '-' }
    $as = (@(foreach ($x in (L $i.assignees)) { "@$($x.username)" })) -join ' '; if (-not $as) { $as = '-' }
    GOut ("  type: " + (Dor $i.issue_type 'issue') + "   labels: $lb   milestone: " + $(if ($i.milestone -is [hashtable]) { $i.milestone.title } else { '-' }) + "   assignees: $as`n")
    if ($i.web_url) { GOut "  $($i.web_url)`n" }
    if (([string](Dor $i.description '')).Length) { GOut "`n$($i.description)`n" }
    foreach ($n in (L $i.notes)) { GOut ("`n  $($n.created_at) " + $(if (Tru $n.system) { '* ' } else { '' }) + "@$($n.author.username): " + (([string]$n.body) -replace "`n", "`n    ") + "`n") }
}
function ScheduleNext($a, $o, [long]$now) {
    if ((L $a).Count -eq 0) { throw "gitlab.pl: schedule next needs a CRON line`n" }
    $from = $(if ($null -ne $o.from) { Epoch $o.from } else { $now })
    $tz = Dor $o.tz 'UTC'
    foreach ($t in (CronRuns $a[0] $tz $from ([int](Dor $o.n 5)))) {
        $off = TzOffset $tz $t
        $ab = $(if ($off -lt 0) { - $off } else { $off })
        GOut ('{0}  ({1} {2}{3}:{4})' -f (IsoT $t), (StrfTime '%a %Y-%m-%d %H:%M' (GmTime ($t + $off))), $(if ($off -lt 0) { '-' } else { '+' }), (P2 (Trunc ($ab / 3600))), (P2 (Trunc (($ab % 3600) / 60))))
        GOut "`n"
    }
}
function PrintWidgets($w) {
    if ($w.junit) { $j = $w.junit; GOut ('  tests: {0} total, {1} failed, {2} skipped' -f (PStr $j.total), (PStr $j.failed), (PStr $j.skipped)); GOut "`n"; foreach ($f in (L $j.failures)) { GOut "    failed: $f`n" } }
    if ($w.codequality) {
        $c = $w.codequality
        GOut ('  code quality: {0} finding{1}, {2} new, {3} resolved' -f (PStr $c.total), $(if ((PNum $c.total) -eq 1) { '' } else { 's' }), (L $c.new).Count, (L $c.resolved).Count); GOut "`n"
        foreach ($x in (L $c.new)) { GOut "    new $($x.severity): $($x.description) ($($x.path):$($x.line))`n" }
    }
    if ($w.metrics) {
        GOut "  metrics:`n"
        foreach ($x in (L $w.metrics)) { GOut (('    {0,-28} {1}' -f $x.name, (PStr $x.value)) + $(if ($null -ne $x.previous -and (PStr $x.previous) -cne (PStr $x.value)) { " (was $(PStr $x.previous))" } elseif ($null -eq $x.previous) { ' (new)' } else { '' }) + "`n") }
    }
}

function MainCmd([string]$cmd, $a) {
    $gl = $script:GLC
    if ($cmd -ceq 'setup') {
        $o = Opts $a @('diff', 'repo=s', 'commit'); $a = $script:REST
        Need 1 'setup needs a project file (tools/gitlab/templates/project.conf)' $a
        if (Tru $o.diff) {
            $d = GL-diff_project_file $gl $a[0] (O 'project' $script:GOPT.project)
            if ((L $d).Count) { foreach ($x in $d) { GOut "$x`n" } } else { GOut "no differences: the project matches $($a[0])`n" }
            if ((L $d).Count) { return 1 }; return 0
        }
        $log = GL-apply_project_file $gl $a[0] (O 'project' $script:GOPT.project 'repo' $o.repo 'commit' $o.commit)
        foreach ($x in $log) { GOut "$x`n" }
        return 0
    }
    if ($cmd -ceq 'user') {
        $o = Opts $a @('name=s', 'email=s'); $a = $script:REST
        Need 1 'user needs a USERNAME' $a
        $null = GL-create_user $gl $a[0] (O 'name' $o.name 'email' $o.email)
        GOut "user $($a[0])`n"
        return 0
    }
    if ($cmd -ceq 'sprints') {
        $o = Opts $a @('weeks=s', 'prefix=s'); $a = $script:REST
        Need 2 'sprints needs START (YYYY-MM-DD) and COUNT' $a
        if ($a[1] -cnotmatch '^\d+$') { throw "gitlab.pl: sprint COUNT must be a number`n" }
        foreach ($m in (GL-sprints $gl (PP) $a[0] $a[1] (O 'weeks' (Dor $o.weeks 2) 'prefix' $o.prefix))) { GOut ('{0}  {1} .. {2}' -f $m.title, (Dor $m.start_date ''), (Dor $m.due_date '')); GOut "`n" }
        return 0
    }
    if ($cmd -ceq 'issue') {
        if ((L $a).Count -eq 0) { GUsage 'issue' }
        $sub = $a[0]; $a = @($a | Select-Object -Skip 1)
        $o = Opts $a @('template=s', 'description=s', 'label=s@', 'milestone=s', 'assign=s@', 'type=s', 'weight=s', 'due=s', 'state=s', 'file=s', 'add=s@', 'remove=s@'); $a = $script:REST
        if ($sub -ceq 'new') {
            Need 1 'issue new needs a TITLE' $a
            $d = Dor $o.description (Dor (Template $o.template 'issue') '')
            $i = GL-create_issue $gl (PP) (O 'title' $a[0] 'description' $d 'labels' $o.label 'milestone' $o.milestone 'assignees' $o.assign 'issue_type' $o.type 'weight' $o.weight 'due_date' $o.due)
            GOut ("#$(PStr $i.iid) $($a[0])`n" + $(if ($i.web_url) { "$($i.web_url)`n" } else { '' }))
        } elseif ($sub -ceq 'list') {
            foreach ($i in (GL-issues $gl (PP) (O 'state' (Dor $o.state 'opened') 'labels' $o.label 'milestone' $o.milestone 'issue_type' $o.type))) {
                GOut (('#{0,-4} {1,-7} {2,-40} {3}' -f (PStr $i.iid), $i.state, ((@(foreach ($l in (L $i.labels)) { "~$l" })) -join ' '), $i.title) + "`n")
            }
        } elseif ($sub -ceq 'show') { Need 1 'issue show needs an IID' $a; ShowIssue (GL-issue $gl (PP) $a[0]) }
        elseif ($sub -ceq 'close' -or $sub -ceq 'reopen') { Need 1 "issue $sub needs an IID" $a; $i = GL-update_issue $gl (PP) $a[0] (O 'state_event' $sub); GOut "#$($a[0]) $($i.state)`n" }
        elseif ($sub -ceq 'note') {
            Need 1 'issue note needs an IID and TEXT (or --file F)' $a
            $body = $(if ($null -ne $o.file) { Slurp $o.file } elseif ((L $a).Count -gt 1) { $a[1] } else { throw "gitlab.pl: issue note needs TEXT or --file FILE`n" })
            $null = GL-add_note $gl (PP) 'issue' $a[0] $body (NewH)
            GOut "noted on #$($a[0])`n"
        } elseif ($sub -ceq 'link') {
            Need 2 'issue link needs IID and TARGET' $a
            $null = GL-link_issues $gl (PP) $a[0] $a[1] (Dor $o.type 'relates_to')
            GOut ("#$($a[0]) " + (Dor $o.type 'relates_to') + " #$($a[1])`n")
        } elseif ($sub -ceq 'label') {
            Need 1 'issue label needs an IID' $a
            $i = GL-update_issue $gl (PP) $a[0] (O 'add_labels' $o.add 'remove_labels' $o.remove)
            GOut ("#$($a[0]) " + ((@(foreach ($l in (L $i.labels)) { "~$l" })) -join ' ') + "`n")
        } else { GUsage 'issue' }
        return 0
    }
    if ($cmd -ceq 'mr') {
        if ((L $a).Count -eq 0) { GUsage 'mr' }
        $sub = $a[0]; $a = @($a | Select-Object -Skip 1)
        $o = Opts $a @('source=s', 'target=s', 'title=s', 'template=s', 'description=s', 'label=s@', 'milestone=s', 'reviewer=s@', 'keep-branch', 'state=s', 'resolvable'); $a = $script:REST
        if ($sub -ceq 'new') {
            if ($null -eq $o.source -or $null -eq $o.title) { throw "gitlab.pl: mr new needs --source BRANCH and --title TITLE`n" }
            $t = Dor $o.target (GL-project $gl (PP)).default_branch
            $m = GL-create_mr $gl (PP) (O 'source_branch' $o.source 'target_branch' $t 'title' $o.title 'description' (Dor $o.description (Dor (Template $o.template 'merge_request') '')) `
                'labels' $o.label 'milestone' $o.milestone 'reviewers' $o.reviewer 'remove_source_branch' $(if (Tru $o['keep-branch']) { 0 } else { 1 }))
            GOut ("!$(PStr $m.iid) $($o.source) -> ${t}: $($o.title)`n" + $(if ($m.web_url) { "$($m.web_url)`n" } else { '' }))
            if ($m.head_pipeline) { GOut "pipeline #$($m.head_pipeline.id) $($m.head_pipeline.status)`n" }
        } elseif ($sub -ceq 'list') {
            foreach ($m in (GL-mrs $gl (PP) (O 'state' (Dor $o.state 'opened')))) {
                GOut (('!{0,-4} {1,-7} {2} -> {3}  {4}' -f (PStr $m.iid), $m.state, $m.source_branch, $m.target_branch, $m.title) + $(if ($m.head_pipeline) { "  (pipeline $($m.head_pipeline.status))" } else { '' }) + "`n")
            }
        } elseif ($sub -ceq 'show') {
            Need 1 'mr show needs an IID' $a
            $m = GL-mr $gl (PP) $a[0]
            GOut (('!{0}  {1}  {2} -> {3}  {4}' -f (PStr $m.iid), $m.state, $m.source_branch, $m.target_branch, $m.title) + "`n")
            $lb = (@(foreach ($l in (L $m.labels)) { "~$l" })) -join ' '; if (-not $lb) { $lb = '-' }
            $ap = (@(foreach ($x in (L $m.approved_by)) { "@$($x.user.username)" })) -join ' '; if (-not $ap) { $ap = '-' }
            GOut ("  author: @" + (Dor (HGet $m.author 'username') '?') + "   labels: $lb   approved by: $ap   pipeline: " + $(if ($m.head_pipeline) { "#$($m.head_pipeline.id) $($m.head_pipeline.status)" } else { '-' }) + "`n")
            if ($m.merged_at) { $sha = [string](Dor $m.merge_commit_sha ''); GOut ("  merged $($m.merged_at) as " + $sha.Substring(0, [int]$(if ($sha.Length -lt 8) { $sha.Length } else { 8 })) + "`n") }
            if ($m.reports) { PrintWidgets $m.reports }
            if (([string](Dor $m.description '')).Length) { GOut "`n$($m.description)`n" }
            foreach ($n in (L $m.notes)) { GOut ("`n  $($n.created_at) " + $(if (Tru $n.system) { '* ' } else { '' }) + "@$($n.author.username): $($n.body)`n") }
        } elseif ($sub -ceq 'approve') { Need 1 'mr approve needs an IID' $a; $null = GL-approve_mr $gl (PP) $a[0]; GOut ("!$($a[0]) approved by " + (Dor (GL-as $gl $null) '?') + "`n") }
        elseif ($sub -ceq 'merge') {
            Need 1 'mr merge needs an IID' $a
            $m = GL-merge_mr $gl (PP) $a[0] (NewH)
            GOut ("!$($a[0]) merged" + $(if ($m.merge_commit_sha) { ' as ' + ([string]$m.merge_commit_sha).Substring(0, 8) } else { '' }) + "`n")
        } elseif ($sub -ceq 'note') {
            Need 2 'mr note needs IID and TEXT' $a
            $null = GL-add_note $gl (PP) 'mr' $a[0] $a[1] (O 'resolvable' $o.resolvable)
            GOut "noted on !$($a[0])`n"
        } elseif ($sub -ceq 'resolve') { Need 1 'mr resolve needs an IID' $a; $null = GL-resolve_discussions $gl (PP) $a[0]; GOut "!$($a[0]) discussions resolved`n" }
        else { GUsage 'mr' }
        return 0
    }
    if ($cmd -ceq 'pipeline') {
        if ((L $a).Count -eq 0) { GUsage 'pipeline' }
        $sub = $a[0]; $a = @($a | Select-Object -Skip 1)
        $o = Opts $a @('source=s', 'var=s@', 'ref=s', 'status=s'); $a = $script:REST
        if ($sub -ceq 'run') {
            Need 1 'pipeline run needs a REF' $a
            $v = NewH; foreach ($x in (L $o.var)) { if ($x -cnotmatch '^([^=]+)=(.*)$') { throw "gitlab.pl: --var is KEY=VALUE`n" }; $v[$matches[1]] = $matches[2] }
            $pl = GL-run_pipeline $gl (PP) $a[0] (O 'source' $o.source 'variables' $v)
            if ($pl) { GOut "pipeline #$($pl.id) $($pl.status)`n" } else { GOut "no pipeline: no job matched (rules)`n" }
            if ($pl -and [string](Dor $pl.status '') -ceq 'failed') { return 1 }; return 0
        } elseif ($sub -ceq 'list') {
            foreach ($pl in (GL-pipelines $gl (PP) (O 'ref' $o.ref 'status' $o.status))) {
                $sha = [string](Dor $pl.sha ''); if ($sha.Length -gt 8) { $sha = $sha.Substring(0, 8) }
                GOut (('#{0,-5} {1,-8} {2,-20} {3,-30} {4} {5}' -f (PStr $pl.id), $pl.status, (Dor $pl.source ''), $pl.ref, $sha, (Dor $pl.created_at '')) + "`n")
            }
        } elseif ($sub -ceq 'show') {
            Need 1 'pipeline show needs an ID' $a
            $pl = GL-pipeline $gl (PP) $a[0]
            GOut (('#{0} {1}  {2}  {3}  {4}' -f (PStr $pl.id), $pl.status, (Dor $pl.source ''), $pl.ref, (Dor $pl.sha '')) + "`n")
            if ($pl.yaml_errors) { GOut "  yaml error: $($pl.yaml_errors)`n" }
            foreach ($j in (GL-jobs $gl (PP) $a[0])) {
                GOut (('  {0,-10} {1,-14} {2,-16} {3,6} s{4}' -f $j.stage, $j.name, ($j.status + $(if ((Tru $j.allow_failure) -and $j.status -ceq 'failed') { ' (allowed)' } else { '' })), $(if ($null -ne $j.duration) { FmtF $j.duration 1 } else { '-' }), $(if ($j.log) { "  $($j.log)" } else { '' })) + "`n")
            }
        } else { GUsage 'pipeline' }
        return 0
    }
    if ($cmd -ceq 'tag') {
        $o = Opts $a @('message=s'); $a = $script:REST
        Need 2 'tag needs NAME and REF' $a
        $t = GL-create_tag $gl (PP) $a[0] $a[1] $o.message
        $sha = [string](Dor $t.target (Dor (HGet $t.commit 'id') '')); if ($sha.Length -gt 8) { $sha = $sha.Substring(0, 8) }
        GOut "tag $($a[0]) at $sha`n"
        return 0
    }
    if ($cmd -ceq 'release') {
        $o = Opts $a @('notes=s', 'name=s', 'milestone=s@'); $a = $script:REST
        Need 1 'release needs a TAG' $a
        $null = GL-create_release $gl (PP) (O 'tag_name' $a[0] 'name' $o.name 'description' $(if ($null -ne $o.notes) { Slurp $o.notes } else { '' }) 'milestones' $o.milestone)
        GOut "release $($a[0])`n"
        return 0
    }
    if ($cmd -ceq 'wiki') {
        if ((L $a).Count -eq 0) { GUsage 'wiki' }
        $sub = $a[0]; $a = @($a | Select-Object -Skip 1)
        if ($sub -ceq 'put') { Need 2 'wiki put needs TITLE and FILE' $a; $null = GL-wiki_put $gl (PP) $a[0] (Slurp $a[1]); GOut "wiki $($a[0])`n" }
        elseif ($sub -ceq 'list') { foreach ($w in (GL-wiki $gl (PP))) { GOut "$($w.slug)`t$($w.title)`n" } }
        elseif ($sub -ceq 'show') { Need 1 'wiki show needs a TITLE' $a; $s = $a[0] -creplace '\s+', '-'; $w = First (GL-wiki $gl (PP)) { param($x) $x.slug -ceq $s }; if ($null -eq $w) { throw "gitlab.pl: no wiki page '$($a[0])'`n" }; GOut $w.content }
        else { GUsage 'wiki' }
        return 0
    }
    if ($cmd -ceq 'export') {
        $o = Opts $a @('since=s', 'until=s'); $a = $script:REST
        Need 1 'export needs a DIR' $a
        $n = GL-export $gl (PP) $a[0] (O 'since' $o.since 'until' $o.until)
        GOut (((@(foreach ($k in (SortStr @($n.Keys))) { "$k $(PStr $n[$k])" })) -join ', ') + " -> $($a[0])`n")
        return 0
    }
    if ($cmd -ceq 'package') {
        if ((L $a).Count -eq 0) { GUsage 'package' }
        $sub = $a[0]; $a = @($a | Select-Object -Skip 1)
        if ($sub -ceq 'put') { Need 3 'package put needs NAME VERSION FILE' $a; $r = GL-package_put $gl (PP) $a[0] $a[1] $a[2] (NewH); GOut "$($r.name)/$($r.version)/$($r.file_name)  $(PStr $r.size) bytes  sha256 $($r.file_sha256)`n" }
        elseif ($sub -ceq 'get') { Need 3 'package get needs NAME VERSION FILE [DEST]' $a; GOut ((GL-package_get $gl (PP) $a[0] $a[1] $a[2] $(if ($a.Count -gt 3) { $a[3] } else { $null })) + "`n") }
        elseif ($sub -ceq 'list') { foreach ($k in (GL-packages $gl (PP))) { GOut ('{0}/{1}  {2}' -f $k.name, $k.version, ((@(foreach ($f in (L $k.files)) { $f.file_name })) -join ' ')); GOut "`n" } }
        else { GUsage 'package' }
        return 0
    }
    if ($cmd -ceq 'trigger') {
        if ((L $a).Count -eq 0) { GUsage 'trigger' }
        $sub = $a[0]; $a = @($a | Select-Object -Skip 1)
        if ($sub -ceq 'new') { Need 1 'trigger new needs a DESCRIPTION' $a; $tr = GL-create_trigger $gl (PP) ($a -join ' '); GOut "trigger $(PStr $tr.id): $($tr.token)  ($($tr.description))`n" }
        elseif ($sub -ceq 'list') { foreach ($x in (GL-triggers $gl (PP))) { GOut ('{0}  {1}  owner {2}' -f (PStr $x.id), $x.description, (Dor (HGet $x.owner 'username') '')); GOut "`n" } }
        elseif ($sub -ceq 'run') {
            $o = Opts $a @('var=s@'); $a = $script:REST
            Need 2 'trigger run needs TOKEN REF' $a
            $v = NewH; foreach ($x in (L $o.var)) { if ($x -cnotmatch '(?s)^([^=]+)=(.*)$') { throw "gitlab.pl: --var is KEY=VALUE`n" }; $v[$matches[1]] = $matches[2] }
            $pl = GL-trigger_pipeline $gl (PP) $a[0] $a[1] (O 'variables' $v)
            if ($pl) { GOut "pipeline $($pl.id) ($($pl.source)) $($pl.status)`n" } else { GOut "no pipeline: no job matched`n" }
        }
        else { GUsage 'trigger' }
        return 0
    }
    if ($cmd -ceq 'token') {
        $kind = $(if ((L $a).Count -gt 0) { $a[0] } else { $null }); $sub = $(if ((L $a).Count -gt 1) { $a[1] } else { $null }); $a = @($a | Select-Object -Skip 2)
        if (-not ($kind -ceq 'deploy' -and $null -ne $sub)) { GUsage 'token' }
        if ($sub -ceq 'new') {
            $o = Opts $a @('scope=s@', 'expires=s'); $a = $script:REST
            Need 1 'token deploy new needs a NAME' $a
            $dt = GL-create_deploy_token $gl (PP) $a[0] (Dor $o.scope @('read_repository')) (O 'expires_at' $o.expires)
            GOut ("deploy token $(PStr $dt.id) $($dt.username): $($dt.token)  scopes " + ((L $dt.scopes) -join ',') + $(if ($dt.expires_at) { "  expires $($dt.expires_at)" } else { '' }) + "`n")
        }
        elseif ($sub -ceq 'list') { foreach ($x in (GL-deploy_tokens $gl (PP))) { GOut ('{0}  {1}  {2}  {3}' -f (PStr $x.id), $x.name, ((L $x.scopes) -join ','), (Dor $x.expires_at 'never')); GOut "`n" } }
        else { GUsage 'token' }
        return 0
    }
    if ($cmd -ceq 'pages') {
        $pg = GL-pages $gl (PP)
        if (-not $pg -or -not (Dor $pg.url $pg.path)) { GOut "no Pages site yet (a ``pages`` job on the default branch publishes public/)`n"; return 1 }
        GOut ("$($pg.url)`n" + $(if ($pg.path) { "  $($pg.path)`n" } else { '' }))
        return 0
    }
    if ($cmd -ceq 'schedule') {
        if ((L $a).Count -eq 0) { GUsage 'schedule' }
        $sub = $a[0]; $a = @($a | Select-Object -Skip 1 | ForEach-Object { if ($_ -ceq '-n') { '--n' } else { $_ } })
        $o = Opts $a @('cron=s', 'ref=s', 'tz=s', 'var=s@', 'inactive', 'until=s', 'from=s', 'n=s'); $a = $script:REST
        $v = NewH; foreach ($x in (L $o.var)) { if ($x -cnotmatch '^([A-Za-z_]\w*)=(.*)$') { throw "gitlab.pl: --var is KEY=VALUE`n" }; $v[$matches[1]] = $matches[2] }
        if ($sub -ceq 'new') {
            Need 1 'schedule new needs a DESCRIPTION' $a
            if ($null -eq $o.cron -or $null -eq $o.ref) { throw "gitlab.pl: schedule new needs --cron `"MIN HOUR DOM MON DOW`" and --ref BRANCH`n" }
            $sc = GL-create_schedule $gl (PP) (O 'description' $a[0] 'ref' $o.ref 'cron' $o.cron 'cron_timezone' (Dor $o.tz 'UTC') 'active' $(if (Tru $o.inactive) { 0 } else { 1 }) 'variables' $v)
            GOut ("schedule " + (Dor (PStr $sc.id) '?') + " $($a[0])" + $(if ($sc.next_run_at) { "  next run $($sc.next_run_at)" } else { '' }) + "`n")
        } elseif ($sub -ceq 'list') {
            foreach ($sc in (GL-schedules $gl (PP))) {
                $act = (Tru $sc.active) -and ([string]$sc.active -cnotmatch '^false$')
                GOut (('{0,-5} {1,-26} {2,-16} {3,-18} {4,-10} next {5,-20} @{6}{7}' -f (PStr $sc.id), $sc.description, $sc.cron, $sc.cron_timezone, $sc.ref,
                    $(if ($act) { Dor $sc.next_run_at '-' } else { '(inactive)' }), (Dor (HGet $sc.owner 'username') '?'), $(if ($sc.last_pipeline) { "  last #$($sc.last_pipeline.id) $($sc.last_pipeline.status)" } else { '' })) + "`n")
                if ((L $sc.variables).Count) { GOut ("      vars: " + ((@(foreach ($x in (L $sc.variables)) { "$($x.key)=$($x.value)" })) -join ' ') + "`n") }
            }
        } elseif ($sub -ceq 'run') {
            Need 1 'schedule run needs an ID' $a
            $pl = GL-play_schedule $gl (PP) $a[0]
            if ($pl -is [hashtable] -and $pl.id) { GOut "pipeline #$($pl.id) $($pl.status)`n" } else { GOut "schedule $($a[0]) queued`n" }
        } elseif ($sub -ceq 'delete') { Need 1 'schedule delete needs an ID' $a; $null = GL-delete_schedule $gl (PP) $a[0]; GOut "schedule $($a[0]) deleted`n" }
        elseif ($sub -ceq 'due') {
            $pls = GL-run_due_schedules $gl (PP) (O 'until' (Dor $o.until (GL-now $gl)))
            foreach ($x in $pls) { GOut ('{0}  #{1} {2,-8} {3} ({4})' -f $x.created_at, (PStr $x.id), $x.status, $x.ref, $x.schedule.description); GOut "`n" }
            GOut ("$($pls.Count) scheduled pipeline" + $(if ($pls.Count -eq 1) { '' } else { 's' }) + "`n")
            if (First $pls { param($x) $x.status -ceq 'failed' }) { return 1 }; return 0
        } elseif ($sub -ceq 'next') { ScheduleNext $a $o (GL-epoch $gl) }
        else { GUsage 'schedule' }
        return 0
    }
    if ($cmd -ceq 'iteration') {
        $sub = $(if ((L $a).Count) { $a[0] } else { 'list' }); $a = @($a | Select-Object -Skip 1)
        if ($sub -cne 'list') { GUsage 'iteration' }
        $o = Opts $a @('group=s', 'conf=s'); $a = $script:REST
        $it = IterationConf $o.conf
        $g = Dor $o.group (Dor $it.group $(if ((PP) -cmatch '^(.*)/') { $matches[1] } else { $null }))
        if ($null -eq $g) { throw "gitlab.pl: iteration list needs --group PATH`n" }
        $cs = GL-cadences $gl $g
        if ((L $cs).Count -eq 0) { GOut "no iteration cadence on group $g (add one to [iterations] and run setup)`n" }
        foreach ($c in $cs) { GOut ("$($c.title): every $(PStr $c.duration_in_weeks) week" + $(if ((PNum $c.duration_in_weeks) -eq 1) { '' } else { 's' }) + " from " + (Dor $c.start_date '?') + ", $(PStr (Dor $c.iterations_in_advance 0)) in advance, " + $(if (Tru $c.automatic) { 'automatic' } else { 'manual' }) + $(if (Tru $c.roll_over) { ', roll-over' } else { '' }) + "`n") }
        foreach ($i in (GL-iterations $gl $g)) { GOut (('  Sprint {0,-3} {1} .. {2}  {3}' -f (PStr (Dor $i.sequence '?')), $i.start_date, $i.due_date, $i.state) + "`n") }
        GOut "sprints come from: $($it.use) ([iterations] use)`n"
        return 0
    }
    if ($cmd -ceq 'analytics') {
        $o = Opts $a @('since=s', 'until=s', 'by=s', 'csv=s', 'sprints-from=s', 'group=s'); $a = $script:REST
        $it = IterationConf $null
        $from = Dor $o['sprints-from'] $it.use
        if ($from -cnotmatch '^(milestones|iterations)$') { throw "gitlab.pl: --sprints-from is milestones or iterations, not '$from'`n" }
        $AN = GL-analytics $gl (PP) (O 'since' $o.since 'until' $o.until 'by' (Dor $o.by 'sprint') 'sprints_from' $from 'group' (Dor $o.group $it.group))
        GOut (AnalyticsText $AN)
        if ($null -ne $o.csv) { $n = AnalyticsCsv $AN $o.csv; GOut ("`nCSV: " + ((@(foreach ($k in (SortStr @($n.Keys))) { "$k ($(PStr $n[$k]))" })) -join ', ') + " -> $($o.csv)`n") }
        return 0
    }
    if ($cmd -ceq 'board') {
        $sub = $(if ((L $a).Count) { $a[0] } else { 'list' })
        if ($sub -cne 'list') { GUsage 'board' }
        $bs = GL-boards $gl (PP)
        if ((L $bs).Count -eq 0) { GOut "no issue boards (add a [boards] section to the project file and run setup)`n" }
        $sl = $(if (GL-is_local $gl) { NewH } else { $x = $null; try { $x = GL-board_status_lists $gl (PP) } catch { $x = $null }; Dor $x (NewH) })
        foreach ($bo in $bs) {
            $all = (L $bo.lists) + (L $sl[$bo.name])
            $l = Map-L (SortWith (Where-L $all { param($y) (ListKey $y).Length }) { param($p1, $p2) NumCmp (Dor $p1.position 0) (Dor $p2.position 0) }) { param($y) ListKey $y }
            GOut ("$($bo.name)  (milestone " + (BoardScope $bo.milestone) + ")`n  " + $(if ($l.Count) { $l -join ' | ' } else { '(no lists)' }) + "`n")
        }
        return 0
    }
    if ($cmd -ceq 'status') {
        $sub = $(if ((L $a).Count) { $a[0] } else { 'list' }); $a = @($a | Select-Object -Skip 1)
        $o = Opts $a @('conf=s'); $a = $script:REST
        $pc = ProjectConf $o.conf; $c = $pc[0]; $conf = $pc[1]
        $st = ParseStatuses $c.statuses (Dor $conf 'project file') (PP)
        if ($sub -ceq 'list') {
            if ($st.mode -ceq 'labels') { foreach ($l in (GL-labels $gl (PP))) { if ([string]$l.name -cmatch '^state::') { GOut (('{0,-14} {1}  {2}' -f $l.name, $l.color, (Dor $l.description '')) + "`n") } }; return 0 }
            $lc = GL-lifecycle $gl $st.group
            GOut "lifecycle $($lc.name) on $($st.group)`n"
            foreach ($s in (L $lc.statuses)) {
                $d = @(foreach ($k in @('open', 'closed', 'duplicate')) { if ([string](Dor $lc["default_$k"] '') -ceq $s.name) { $k } })
                GOut (('  {0,-12} {1,-12} {2}{3}' -f $s.name, $s.category, (Dor $s.color ''), $(if ($d.Count) { '  default ' + ($d -join '/') } else { '' })) + "`n")
            }
            return 0
        }
        if ($sub -ceq 'set') {
            Need 2 'status set needs IID NAME' $a
            $null = GL-set_item_status $gl (PP) $a[0] $a[1] (O 'mode' $st.mode)
            $now = $(if (Tru $script:GOPT['dry-run']) { $null } else { GL-issue $gl (PP) $a[0] })
            GOut ("#$($a[0]) " + $(if ($now) { (Dor (ItemStatus $now) $a[1]) + " ($($now.state))" } else { $a[1] }) + "`n")
            return 0
        }
        GUsage 'status'
    }
    if ($cmd -ceq 'backlog') {
        if ((L $a).Count -eq 0) { GUsage 'backlog' }
        $sub = $a[0]; $a = @($a | Select-Object -Skip 1)
        $o = Opts $a @('conf=s', 'levels=s', 'group=s'); $a = $script:REST
        $c = (ProjectConf $o.conf)[0]
        $cfg = BL-config $c (O 'project' (PP) 'levels' $o.levels 'group' $o.group)
        Need 1 "backlog $sub needs the workbook FILE (.xlsx or .csv)" $a
        if ($sub -ceq 'import') {
            $b = BL-read_file $a[0] (NewH)
            $r = BL-import_rows $gl (PP) $b.rows $cfg
            foreach ($x in (L $r.log)) { GOut "$x`n" }
            foreach ($w in (L $r.warnings)) { GErr "backlog: $w`n" }
            GOut ('backlog: {0} rows, {1} epics, {2} issues, {3} tasks {4}, {5} already there, {6} warning{7}' -f (L $b.rows).Count, $r.made.epic, $r.made.issue, $r.made.task,
                $(if (Tru $script:GOPT['dry-run']) { 'would be created' } else { 'created' }), $r.skipped, (L $r.warnings).Count, $(if ((L $r.warnings).Count -eq 1) { '' } else { 's' }))
            GOut "`n"
            return 0
        }
        if ($sub -ceq 'export') {
            $rows = BL-export_rows $gl (PP) $cfg
            BL-write_file $a[0] $rows (O 'levels' $cfg.levels)
            $n = NewH; foreach ($r in (L $rows)) { $n[$r.Level] = [long](Dor $n[$r.Level] 0) + 1 }
            GOut ("backlog: " + ((@(foreach ($l in (L $cfg.levels)) { if ($n[$l]) { "$($n[$l]) $l" } })) -join ', ') + " -> $($a[0])`n")
            return 0
        }
        GUsage 'backlog'
    }
    if ($cmd -ceq 'windchill') {
        if ((L $a).Count -eq 0) { GUsage 'windchill' }
        $sub = $a[0]; $a = @($a | Select-Object -Skip 1)
        $o = Opts $a @('conf=s', 'note', 'csv=s', 'since=s'); $a = $script:REST
        $conf = Dor $o.conf (FindConf)
        if ($null -eq $conf) { throw "gitlab.pl: no project file: give --conf FILE (one with a [windchill] section) or run inside a repository with .gitlab/project.conf`n" }
        $cp = WC-config_file $conf; $cfg = $cp[0]
        if ($null -eq $script:GOPT.project) { $script:GOPT.project = $cp[1] }
        if ($sub -ceq 'intake') {
            Need 1 'windchill intake needs the exported CSV FILE' $a
            $s = WC-intake $gl (PP) $a[0] $cfg (O 'note' $o.note)
            foreach ($x in (L $s.lines)) { GOut "$x`n" }
            return 0
        }
        if ($sub -ceq 'status') {
            $rows = WC-status $gl (PP) $cfg (O 'since' $o.since)
            if ($null -ne $o.csv) {
                $csv = WC-status_csv $rows
                if ($o.csv -ceq '-') { GOut $csv }
                else {
                    $b = Utf8B $csv; $all = [byte[]]::new($b.Length + 3); $all[0] = 0xEF; $all[1] = 0xBB; $all[2] = 0xBF; for ($i = 0; $i -lt $b.Length; $i++) { $all[$i + 3] = $b[$i] }
                    Zl-WriteBytes $o.csv $all
                    GOut ("$((L $rows).Count) Windchill request" + $(if ((L $rows).Count -eq 1) { '' } else { 's' }) + " -> $($o.csv)`n")
                }
            } else { GOut (WC-status_text $rows) }
            return 0
        }
        GUsage 'windchill'
    }
    if ($cmd -ceq 'env') {
        $sub = $(if ((L $a).Count) { $a[0] } else { 'list' }); $a = @($a | Select-Object -Skip 1)
        if ($sub -ceq 'list') { foreach ($e in (GL-environments $gl (PP))) { $ld = $e.last_deployment; GOut (('{0,-14} {1,-10} {2}{3}' -f $e.name, (Dor $e.state ''), (Dor $e.external_url ''), $(if ($ld) { $sha = [string](Dor $ld.sha ''); if ($sha.Length -gt 8) { $sha = $sha.Substring(0, 8) }; "  (last: $($ld.ref) $sha)" } else { '' })) + "`n") } }
        elseif ($sub -ceq 'deployments') { foreach ($d in (GL-deployments $gl (PP) (O 'environment' $(if ($a.Count) { $a[0] } else { $null })))) { $sha = [string](Dor $d.sha ''); if ($sha.Length -gt 8) { $sha = $sha.Substring(0, 8) }; GOut (('#{0,-4} {1,-12} {2,-20} {3} {4}' -f (PStr $d.iid), $d.environment.name, $d.ref, $sha, (Dor $d.created_at '')) + "`n") } }
        else { GUsage 'env' }
        return 0
    }
    GUsage $null
}

# ---------------------------------------------------------------- global options and dispatch
$script:GOPT = O 'url' $env:GITLAB_URL 'local' $env:GITLAB_LOCAL 'project' $env:GITLAB_PROJECT 'as' $env:GITLAB_USER 'token-env' 'GITLAB_TOKEN'
$argv = @($script:ARGS0)
$exit = 0
try {
    while ($argv.Count -and [string]$argv[0] -cmatch '^--?(.+)$') {
        $k = $matches[1]
        if ($k -cnotmatch '^(url|token-env|local|project|as|now|dry-run|no-cache|sudo|help|h)$') { break }
        $argv = @($argv | Select-Object -Skip 1)
        if ($k -cmatch '^(dry-run|no-cache|sudo)$') { $script:GOPT[$k] = 1; continue }
        if ($k -ceq 'help' -or $k -ceq 'h') { GOut $script:GLHELP['']; throw 'EXIT0' }
        if ($argv.Count -eq 0) { GErr "gitlab.pl: --$k needs a value`n"; throw 'EXIT2' }
        $script:GOPT[$k] = [string]$argv[0]; $argv = @($argv | Select-Object -Skip 1)
    }
    if ($argv.Count -eq 0) { GUsage $null }
    $cmd = [string]$argv[0]; $argv = @($argv | Select-Object -Skip 1)
    if ($cmd -ceq 'help') { $c = $(if ($argv.Count) { [string]$argv[0] } else { '' }); $t = $script:GLHELP[$c]; if ($null -eq $t) { $t = $script:GLHELP[''] }; GOut $t; throw 'EXIT0' }
    if ($cmd -ceq 'ci' -or $cmd -ceq 'flow') {
        $f = $(if ($cmd -ceq 'ci') { "$here\gitlab-ci.ps1" } else { "$here\gitflow.ps1" })
        if (-not (Test-Path -LiteralPath $f -PathType Leaf)) { GErr "gitlab.pl: $cmd needs $f (not on this PC)`n"; throw 'EXIT2' }
        GFlush
        $fwd = @(); foreach ($k in @('url', 'local', 'project', 'as', 'now', 'token-env')) { if ($null -ne $script:GOPT[$k] -and $k -cne 'token-env') { $fwd += "--$k"; $fwd += $script:GOPT[$k] } }
        & $f @($fwd + $argv)
        $exit = $LASTEXITCODE; if ($null -eq $exit) { $exit = 0 }
        throw "EXITN"
    }
    if (-not $script:GLHELP.ContainsKey($cmd)) { GErr "gitlab.pl: unknown command '$cmd' (gitlab.pl help)`n"; throw 'EXIT2' }
    if ($cmd -ceq 'terraform') {
        $a = $argv
        try {
            $o = Opts $a @('out=s', 'url=s', 'state=s'); $a = $script:REST
            $f = $(if ($a.Count) { $a[0] } else { FindConf })
            if ($null -eq $f) { throw "gitlab.pl: terraform needs a project file (or run it inside a repository with .gitlab/project.conf)`n" }
            $files = Tf-generate (Slurp $f) (O 'file' $f 'url' (Dor $o.url (Dor $script:GOPT.url $env:GITLAB_URL)) 'state' $o.state)
            if ($null -ne $o.out) {
                $null = New-Item -ItemType Directory -Path $o.out -Force
                foreach ($n in (SortStr @($files.Keys))) { WriteText "$($o.out)/$n" $files[$n] }
                $nres = (Tf-resources $files['project.tf']).Count
                GOut (((SortStr @($files.Keys)) -join ', ') + " -> $($o.out) ($nres resources)`n")
            } else { foreach ($n in (SortStr @($files.Keys))) { GOut "# ==== $n`n$($files[$n])`n" } }
        } catch { $e = [string]$_.Exception.Message; if ($e -ceq 'USAGE') { throw }; GErr ('gitlab.pl: ' + ($e -creplace '^(?:gitlab\.pl|GitLab|GitLabTf): ', '')); throw 'EXIT1' }
        throw 'EXIT0'
    }
    if ($cmd -ceq 'insights') {
        try {
            $f = $(if ($argv.Count) { $argv[0] } else { FindConf })
            if ($null -eq $f) { throw "gitlab.pl: insights needs a project file (or run it inside a repository with .gitlab/project.conf)`n" }
            $c = ParseProjectFile (Slurp $f) $f
            GOut (InsightsYml $c $f)[0]
        } catch { $e = [string]$_.Exception.Message; GErr ('gitlab.pl: ' + ($e -creplace '^(?:gitlab\.pl|GitLab): ', '')); throw 'EXIT1' }
        throw 'EXIT0'
    }
    if ($cmd -ceq 'schedule' -and $argv.Count -and [string]$argv[0] -ceq 'next' -and -not ($script:GOPT.local) -and -not $script:GOPT.url) {
        try {
            $a = @($argv | Select-Object -Skip 1 | ForEach-Object { if ($_ -ceq '-n') { '--n' } else { $_ } })
            $o = Opts $a @('tz=s', 'from=s', 'n=s'); $a = $script:REST
            ScheduleNext $a $o $(if ($null -ne $script:GOPT.now) { Epoch $script:GOPT.now } else { NowEpoch })
        } catch { $e = [string]$_.Exception.Message; GErr ('gitlab.pl: ' + ($e -creplace '^(?:gitlab\.pl|GitLab): ', '')); throw 'EXIT1' }
        throw 'EXIT0'
    }
    $script:GLC = $null
    try {
        if ($script:GOPT.local -and -not $script:GOPT.url) {
            $script:GLC = New-GL (O 'local' $script:GOPT.local 'dry_run' $script:GOPT['dry-run'] 'now' $script:GOPT.now)
        } else {
            if (-not $script:GOPT.url) { throw "gitlab.pl: give --url URL (or GITLAB_URL) or --local DIR (the emulator)`n" }
            $script:GLC = New-GL (O 'url' $script:GOPT.url 'token_env' $script:GOPT['token-env'] 'dry_run' $script:GOPT['dry-run'] 'sudo' $script:GOPT.sudo 'now' $script:GOPT.now)
        }
        if ($script:GOPT.as) { $null = GL-as $script:GLC $script:GOPT.as }
        $r = MainCmd $cmd $argv
        GL-save $script:GLC
        $exit = [int]$r
    } catch {
        $e = [string]$_.Exception.Message
        if ($e -ceq 'USAGE') { throw 'EXIT2' }
        if ($e -cmatch '^EXIT') { throw }
        try { if ($script:GLC) { GL-save $script:GLC } } catch { }
        if ($e -ceq '') { $e = "failed`n" }
        $e = $e -creplace '^(?:gitlab\.pl|GitLab|GitFlow|Windchill|Backlog): ', ''
        if ($_.InvocationInfo -and $e -notmatch "`n$") { $e += "`n" }
        GErr "gitlab.pl: $e"
        $exit = 1
    }
} catch {
    $e = [string]$_.Exception.Message
    if ($e -ceq 'EXIT0') { $exit = 0 } elseif ($e -ceq 'EXIT1') { $exit = 1 } elseif ($e -ceq 'EXIT2' -or $e -ceq 'USAGE') { $exit = 2 } elseif ($e -ceq 'EXITN') { }
    else { GErr "gitlab.pl: $e"; $exit = 1 }
}
GFlush
exit $exit
