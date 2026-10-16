# gltf.ps1 -- lib/GitLabTf.pm: the project file as Terraform/OpenTofu for the gitlabhq/gitlab provider (~> 19.4).
# No GitLab and no terraform binary needed. Constrained Language Mode safe.

$script:TF_LEVEL = O 'none' 'no one' 'no one' 'no one' 'noone' 'no one' 'guest' 'guest' 'reporter' 'reporter' 'developer' 'developer' 'maintainer' 'maintainer' 'owner' 'owner' 'admin' 'admin'
function TfQ($s) {
    $s = [string](Dor $s '')
    $s = $s.Replace('\', '\\').Replace('"', '\"').Replace('${', '$${').Replace('%{', '%%{').Replace("`n", '\n')
    return "`"$s`""
}
function TfId($s) { $s = ([string]$s).ToLowerInvariant() -creplace '[^a-z0-9_]+', '_'; $s = $s -creplace '^_+|_+$', ''; if ($s -cmatch '^\d') { $s = "_$s" }; if ($s.Length) { return $s }; return 'x' }
function TfBool($v) { if ($v -is [bool]) { if ($v) { return 'true' } else { return 'false' } }; if ([string](Dor $v '') -cmatch '^(?i)(1|true|yes|on)$') { return 'true' }; return 'false' }
function TfLevel($v, $where) { $k = ([string]$v).ToLowerInvariant(); if ($script:TF_LEVEL.ContainsKey($k)) { return $script:TF_LEVEL[$k] }; throw "${where}: '$v' is not an access level Terraform knows (none, developer, maintainer, admin)`n" }
function Tf-generate([string]$text, $o) {
    $file = Dor $o.file 'project.conf'
    $c = ParseProjectFile $text $file
    $pr = KV $c.project
    $p = $pr.path; if ($null -eq $p) { throw "${file}: [project] needs path = group/name`n" }
    if ($p -cnotmatch '^(.+)/([^/]+)$') { throw "${file}: [project] path must be GROUP/NAME, not '$p'`n" }
    $ns = $matches[1]; $name = $matches[2]
    $url = ([string](Dor $o.url 'https://gitlab.example.com')) -creplace '/+$', ''
    $state = Dor $o.state 'gitlab-project'
    $tf = @(); $users = NewH; $vars = @(); $skipped = @()
    $user = { param($u) $users[$u] = 1; 'data.gitlab_user.' + (TfId $u) + '.id' }
    $set = NewH; foreach ($k in @($pr.Keys)) { if ($k -cnotmatch '^(path|visibility)$') { $set[$k] = $pr[$k] } }
    $bool = @('only_allow_merge_if_pipeline_succeeds', 'only_allow_merge_if_all_discussions_are_resolved', 'remove_source_branch_after_merge')
    $t = "# The project. It already exists (gitlab.pl setup or the UI made it): the import block adopts it on the first apply.`n" +
         "import {`n  to = gitlab_project.this`n  id = " + (TfQ $p) + "`n}`n`n" +
         "data `"gitlab_group`" `"ns`" {`n  full_path = " + (TfQ $ns) + "`n}`n`n" +
         "resource `"gitlab_project`" `"this`" {`n  name         = " + (TfQ $name) + "`n  path         = " + (TfQ $name) + "`n  namespace_id = data.gitlab_group.ns.group_id`n"
    if ($pr.visibility) { $t += "  visibility_level = " + (TfQ $pr.visibility) + "`n" }
    foreach ($k in (SortStr @($set.Keys))) { $v = $set[$k]; $t += "  $k = " + $(if ($bool -ccontains $k -or $v -cmatch '^(?i)(true|false)$') { TfBool $v } else { TfQ $v }) + "`n" }
    $t += "}`n`nlocals {`n  project = gitlab_project.this.id`n}`n"
    $tf += $t
    foreach ($x in (L $c.members)) {
        $tf += "resource `"gitlab_project_membership`" `"" + (TfId $x[0]) + "`" {`n  project      = local.project`n  user_id      = " + (& $user $x[0]) + "`n  access_level = " + (TfQ (TfLevel $x[1] "${file}:$($x[2])")) + "`n}`n"
    }
    if ((L $c.labels).Count) {
        $l = @()
        foreach ($x in (L $c.labels)) {
            if ($x[1] -cnotmatch '^\s*(#[0-9A-Fa-f]{6})\s*(?:\|\s*(.*))?$') { throw "${file}:$($x[2]): label value is '#RRGGBB | description'`n" }
            $color = $matches[1]; $desc = $(if ($matches[2]) { $matches[2] } else { '' })
            $l += "    " + (TfQ $x[0]) + " = { color = " + (TfQ $color) + ", description = " + (TfQ $desc) + " }`n"
        }
        $tf += "locals {`n  labels = {`n" + ($l -join '') + "  }`n}`n`nresource `"gitlab_project_label`" `"this`" {`n  for_each    = local.labels`n  project     = local.project`n" +
               "  name        = each.key`n  color       = each.value.color`n  description = each.value.description`n}`n"
    }
    $ms = @()
    foreach ($x in (L $c.milestones)) {
        if ($x[0] -ceq 'sprints') {
            $w = SplitWs $x[1] 4
            $weeks = PNum (Dor $(if ($w.Count -gt 2) { $w[2] }) 2); $prefix = Dor $(if ($w.Count -gt 3) { $w[3] }) 'Sprint '
            $t0 = Epoch $w[0]
            for ($k = 1; $k -le (PNum $w[1]); $k++) {
                $s = $t0 + ($k - 1) * $weeks * 7 * 86400; $d = $s + ($weeks * 7 - 3) * 86400
                $ms += , @("$prefix$k", (DateT $s), (DateT $d), ("Two-week sprint ${k}: planning on " + (DateT $s) + ', review and retrospective on ' + (DateT $d) + '.'))
            }
        } else {
            $sp = @($x[1] -csplit '\s*\|\s*', 2); $dd = SplitWs (Dor $sp[0] '') 0
            $ms += , @($x[0], $(if ($dd.Count) { $dd[0] }), $(if ($dd.Count -gt 1) { $dd[1] }), $(if ($sp.Count -gt 1) { $sp[1] } else { '' }))
        }
    }
    if ($ms.Count) {
        $tf += "locals {`n  milestones = {`n" + ((@(foreach ($m in $ms) { "    " + (TfQ $m[0]) + " = { start = " + (TfQ (Dor $m[1] '')) + ", due = " + (TfQ (Dor $m[2] '')) + ", description = " + (TfQ $m[3]) + " }`n" })) -join '') +
               "  }`n}`n`nresource `"gitlab_project_milestone`" `"this`" {`n  for_each    = local.milestones`n  project     = local.project`n  title       = each.key`n" +
               "  start_date  = each.value.start != `"`" ? each.value.start : null`n  due_date    = each.value.due != `"`" ? each.value.due : null`n  description = each.value.description`n}`n"
    }
    foreach ($x in (L $c.branches)) {
        $a = NewH
        foreach ($w in (SplitWs $x[1] 0)) { if ($w -cnotmatch '^(\w+):(\S+)$') { throw "${file}:$($x[2]): branch rule words are push:LEVEL merge:LEVEL force:yes|no codeowners:yes|no`n" }; $a[$matches[1].ToLowerInvariant()] = $matches[2].ToLowerInvariant() }
        $tf += "resource `"gitlab_branch_protection`" `"" + (TfId $x[0]) + "`" {`n  project                      = local.project`n  branch                       = " + (TfQ $x[0]) +
               "`n  push_access_level            = " + (TfQ (TfLevel (Dor $a.push 'maintainer') "${file}:$($x[2])")) + "`n  merge_access_level           = " + (TfQ (TfLevel (Dor $a.merge 'maintainer') "${file}:$($x[2])")) +
               "`n  allow_force_push             = " + (TfBool ((Dor $a.force 'no') -ceq 'yes')) + "`n  code_owner_approval_required = " + (TfBool ((Dor $a.codeowners 'no') -ceq 'yes')) + "`n}`n"
    }
    foreach ($x in (L $c.tags)) {
        if ($x[1] -cnotmatch '^create:(\S+)$') { throw "${file}:$($x[2]): tag rule is create:LEVEL`n" }
        $lvl = $matches[1]
        $tf += "resource `"gitlab_tag_protection`" `"" + (TfId $x[0]) + "`" {`n  project             = local.project`n  tag                 = " + (TfQ $x[0]) +
               "`n  create_access_level = " + (TfQ (TfLevel $lvl "${file}:$($x[2])")) + "`n}`n"
    }
    foreach ($x in (L $c.approvals)) {
        $w = SplitWs $x[1] 0; $n = $w[0]; $us = @(); if ($w.Count -gt 1) { $us = $w[1..($w.Count - 1)] }
        if ([string]$n -cnotmatch '^\d+$') { throw "${file}:$($x[2]): approval rule is N user user ...`n" }
        $tf += "resource `"gitlab_project_approval_rule`" `"" + (TfId $x[0]) + "`" {`n  project            = local.project`n  name               = " + (TfQ $x[0]) +
               "`n  approvals_required = $n`n  user_ids           = [" + ((@(foreach ($u in $us) { & $user $u })) -join ', ') + "]`n}`n"
    }
    foreach ($x in (L $c.variables)) {
        $parts = @($x[1] -csplit '\s+\|\s+'); $f = NewH; for ($i = 1; $i -lt $parts.Count; $i++) { $f[$parts[$i].ToLowerInvariant()] = 1 }
        $tv = 'ci_' + (TfId $x[0])
        $vars += , @($tv, $x[0], $f['masked'])
        $tf += "resource `"gitlab_project_variable`" `"" + (TfId $x[0]) + "`" {`n  project   = local.project`n  key       = " + (TfQ $x[0]) +
               "`n  value     = var.$tv`n  protected = " + (TfBool $f['protected']) + "`n  masked    = " + (TfBool $f['masked']) + "`n}`n"
    }
    foreach ($x in (L $c.schedules)) {
        $f = @(@($x[1] -split '\|', 4) | ForEach-Object { $_.Trim() })
        $cron = $f[0]; $ref = $(if ($f.Count -gt 1) { $f[1] }); $tz = $(if ($f.Count -gt 2) { $f[2] }); $vv = $(if ($f.Count -gt 3) { $f[3] })
        if (-not ($ref -and $cron)) { throw "${file}:$($x[2]): a schedule is CRON | REF [| TZ [| K=V ...]]`n" }
        $id = TfId $x[0]
        $tf += "resource `"gitlab_pipeline_schedule`" `"$id`" {`n  project       = local.project`n  description   = " + (TfQ $x[0]) + "`n  ref           = " + (TfQ $(if ($ref -cmatch '^refs/') { $ref } else { "refs/heads/$ref" })) +
               "`n  cron          = " + (TfQ $cron) + "`n  cron_timezone = " + (TfQ $(if ($tz) { $tz } else { 'UTC' })) + "`n  active        = true`n}`n"
        foreach ($kv in (SplitWs (Dor $vv '') 0)) {
            if ($kv -cnotmatch '^([A-Za-z_]\w*)=(.*)$') { throw "${file}:$($x[2]): schedule variables are KEY=VALUE, not '$kv'`n" }
            $k = $matches[1]; $v = $matches[2]
            $tf += "resource `"gitlab_pipeline_schedule_variable`" `"${id}_" + (TfId $k) + "`" {`n  project              = local.project`n  pipeline_schedule_id = gitlab_pipeline_schedule.$id.pipeline_schedule_id" +
                   "`n  key                  = " + (TfQ $k) + "`n  value                = " + (TfQ $v) + "`n}`n"
        }
    }
    $it = ParseIterations $c.iterations $file $p
    foreach ($x in (L $c.boards)) {
        $w = ParseBoardLine $x[1] "${file}:$($x[2])" $it.use
        $known = NewH; foreach ($y in (L $c.labels)) { $known[$y[0]] = 1 }
        foreach ($l in (L $w.labels)) { if (-not $known.ContainsKey($l)) { throw "${file}:$($x[2]): board $($x[0]) lists label '$l', which [labels] does not define`n" } }
        $msv = $w.milestone
        $mline = $(if ($script:BOARD_MS.ContainsKey($msv)) { $(if ($msv -ceq 'any') { '' } else { "  milestone_id = $($script:BOARD_MS[$msv]) # GitLab's predefined timebox id for `"$msv`" (Premium/Ultimate)`n" }) }
                   else { "  milestone_id = gitlab_project_milestone.this[" + (TfQ $msv) + "].milestone_id`n" })
        $t = "resource `"gitlab_project_issue_board`" `"" + (TfId $x[0]) + "`" {`n  project = local.project`n  name    = " + (TfQ $x[0]) + "`n" + $mline
        if ($w.iteration -cne 'any') { $t += "  # iteration=$($w.iteration): the provider sets a board's iteration scope only per list; gitlab.pl setup sets it (GraphQL)`n" }
        foreach ($l in (L $w.labels)) { if ($l -cmatch '^status:(.+)$') { $t += "  # list status:$($matches[1]): a status list is not in the gitlab provider; gitlab.pl setup adds it (GraphQL)`n" } else { $t += "  lists {`n    label_id = gitlab_project_label.this[" + (TfQ $l) + "].label_id`n  }`n" } }
        $tf += $t + "}`n"
    }
    if ((L $it.cadences).Count) { $skipped += '[iterations] (the iteration cadence: not in the gitlab provider; gitlab.pl setup makes it through GraphQL)' }
    if ($c.insights) { $skipped += '[insights] (.gitlab/insights.yml is a repository file: commit it through a merge request; gitlab.pl insights prints it)' }
    if ($c.windchill) { $skipped += '[windchill] (the Windchill intake mapping is not a GitLab setting)' }
    if ($c.statuses) { $skipped += '[statuses] (work-item statuses and their mark labels: not in the gitlab provider; gitlab.pl setup sets the lifecycle through GraphQL)' }
    if ($c.backlog) { $skipped += '[backlog] (the backlog workbook mapping is not a GitLab setting: gitlab.pl backlog import loads the work items)' }
    $ud = (@(foreach ($u in (SortStr @($users.Keys))) { "data `"gitlab_user`" `"" + (TfId $u) + "`" {`n  username = " + (TfQ $u) + "`n}`n`n" })) -join ''
    $head = "# Generated by gitlab.pl terraform from $file -- edit the project file and regenerate, not these files.`n"
    $out = NewH
    $out['versions.tf'] = $head + "terraform {`n  required_version = `">= 1.5`" # Terraform 1.5+ or OpenTofu 1.6+ (import blocks)`n  required_providers {`n    gitlab = {`n" +
        "      source  = `"gitlabhq/gitlab`"`n      version = `"~> 19.4`" # written against 19.4.1 (2026-10-03); the major version follows GitLab's`n    }`n  }`n" +
        "  # GitLab-managed state. In CI the OpenTofu component configures it; on a workstation:`n  #   tofu init -backend-config=backend.hcl     (TF_HTTP_PASSWORD = a token with scope api)`n" +
        "  backend `"http`" {}`n}`n`nprovider `"gitlab`" {`n  # token from GITLAB_TOKEN; the server from GITLAB_BASE_URL (for example $url/api/v4/)`n}`n"
    $out['project.tf'] = $head + "# Project " + $p + ".`n`n" + $ud + ($tf -join "`n") + $(if ($skipped.Count) { "`n# Not managed here:`n" + ((@(foreach ($s in $skipped) { "#   $s`n" })) -join '') } else { '' })
    $out['variables.tf'] = $head + $(if ($vars.Count) { (@(foreach ($v in $vars) { "variable `"$($v[0])`" {`n  description = " + (TfQ "CI/CD variable $($v[1]): set TF_VAR_$($v[0]) or a .tfvars file kept out of git") + "`n  type        = string`n" + $(if ($v[2]) { "  sensitive   = true`n" } else { '' }) + "}`n" })) -join "`n" } else { "# no CI/CD variables in the project file`n" })
    $addr = "$url/api/v4/projects/" + (Enc $p) + "/terraform/state/$state"
    $out['backend.hcl'] = "# tofu init -backend-config=backend.hcl   (state `"$state`" of $p; the numeric project id works in place of the path)`n" +
        "address        = " + (TfQ $addr) + "`nlock_address   = " + (TfQ "$addr/lock") + "`nunlock_address = " + (TfQ "$addr/lock") + "`n" +
        "lock_method    = `"POST`"`nunlock_method  = `"DELETE`"`nretry_wait_min = 5`n# username = your GitLab user; the password comes from TF_HTTP_PASSWORD (never in this file)`n"
    foreach ($k in @($out.Keys)) { if ($k -cmatch '\.(tf|hcl)$') { $out[$k] = TfAlign $out[$k] } }
    return $out
}
function TfAlign([string]$t) {                       # what `terraform fmt` does to our output: align the = of consecutive attributes
    $l = @($t -split "`n")
    $i = 0
    while ($i -lt $l.Count) {
        if ($l[$i] -cnotmatch '^(\s*)(?:"[^"]*"|[\w.-]+)\s*= ') { $i++; continue }
        $ind = $matches[1]
        $j = $i; $g = @()
        while ($j -lt $l.Count -and $l[$j] -cmatch '^(\s*)("[^"]*"|[\w.-]+)\s*= (.*)$' -and $matches[1] -ceq $ind) { $g += , @($matches[2], $matches[3]); $j++; if ($matches[3] -cmatch '[{\[]\s*$') { break } }
        $w = 0; foreach ($x in $g) { if ($x[0].Length -gt $w) { $w = $x[0].Length } }
        for ($k = 0; $k -lt $g.Count; $k++) { $l[$i + $k] = $ind + $g[$k][0] + (' ' * ($w - $g[$k][0].Length)) + ' = ' + $g[$k][1] }
        if ($j -gt $i) { $i = $j } else { $i = $i + 1 }
    }
    return ($l -join "`n")
}
function Tf-resources([string]$t) { return , @(foreach ($m in [regex]::Matches($t, '(?m)^resource "(\w+)" "(\w+)" \{')) { "$($m.Groups[1].Value).$($m.Groups[2].Value)" }) }
