# glemu.ps1 -- the local emulator's internals (GitLab.pm's "the local emulator" section), without git.
# A project's bare repository folder is written directly: HEAD, config, refs/, objects/, hooks/pre-receive and the
# protection file the hook reads (the same text GitLab.pm writes), so a later real git can push to it.

function GL-_user($gl, $u, $o) {
    if ($null -eq $o) { $o = NewH }
    if ([string](Dor $u '') -ceq '') { throw "GitLab: no user given`n" }
    $us = $gl.st.users[$u]
    if ($null -eq $us) {
        $us = O 'id' (GL-_id $gl) 'username' $u 'name' (Dor $o.name (UcFirst ([string]$u))) 'email' (Dor $o.email "$u@example.invalid") 'created_at' (GL-now $gl)
        $gl.st.users[$u] = $us
    }
    if (Tru $o.name) { $us.name = $o.name }
    if (Tru $o.email) { $us.email = $o.email }
    return $us
}
function GL-_p($gl, $p) { $PJ = $gl.st.projects[[string]$p]; if ($null -eq $PJ) { throw "GitLab: no project '$p' (404 Project Not Found)`n" }; return $PJ }
function GL-_bare($gl, $PJ) { return "$($gl.local)/repos/$($PJ.path_with_namespace).git" }
function GL-_summary($gl, $PJ) { $r = NewH; foreach ($k in @('id', 'name', 'path', 'path_with_namespace', 'namespace', 'default_branch', 'http_url_to_repo', 'web_url', 'settings', 'created_at')) { $r[$k] = $PJ[$k] }; return $r }
function GL-_create_project($gl, $path, $o) {
    if ($path -cnotmatch '^(.*)/([^/]+)$') { throw "GitLab: project path '$path' needs a group: group/name`n" }
    $ns = $matches[1]; $name = $matches[2]
    if ($gl.st.projects[$path]) { throw "GitLab: project '$path' already exists (400 has already been taken)`n" }
    $null = GL-create_group $gl $ns (NewH)
    $members = NewH; $members[$gl.as] = 50
    $PJ = O 'id' (GL-_id $gl) 'name' (Dor $o.name $name) 'path' $name 'path_with_namespace' $path 'namespace' $ns `
        'default_branch' 'main' 'created_at' (GL-now $gl) 'creator' $gl.as 'web_url' "$($gl.base)/$path" `
        'settings' (O 'merge_method' 'merge' 'squash_option' 'default_off' 'only_allow_merge_if_pipeline_succeeds' 0 `
                      'only_allow_merge_if_all_discussions_are_resolved' 0 'remove_source_branch_after_merge' 1 'visibility' (Dor $o.visibility 'private')) `
        'members' $members 'labels' @() 'milestones' @() 'protected_branches' @() 'protected_tags' @() 'approval_rules' @() 'variables' (NewH) `
        'issues' @() 'mrs' @() 'pipelines' @() 'releases' @() 'wiki' @() 'iids' (NewH) 'seen' (NewH)
    $gl.st.projects[$path] = $PJ
    $bare = GL-_bare $gl $PJ
    foreach ($d in @('', '/refs/heads', '/refs/tags', '/objects/info', '/objects/pack', '/hooks', '/info')) { $null = New-Item -ItemType Directory -Path "$bare$d" -Force }
    WriteText "$bare/HEAD" "ref: refs/heads/main`n"
    WriteText "$bare/config" "[core]`n`trepositoryformatversion = 0`n`tfilemode = true`n`tbare = true`n"
    WriteText "$bare/description" "Unnamed repository; edit this file 'description' to name the repository.`n"
    $PJ.http_url_to_repo = $bare
    GL-_install_hook $gl $PJ
    GL-_write_protect $gl $PJ
    return (GL-_summary $gl $PJ)
}
function GL-_update_project($gl, $p, $s) {
    $PJ = GL-_p $gl $p
    foreach ($k in @($s.Keys)) {
        $v = $s[$k]
        if ($null -ne $v) { if ([string]$v -cmatch '^(?i)(true|yes|on|1)$') { $v = 1 } elseif ([string]$v -cmatch '^(?i)(false|no|off|0)$') { $v = 0 } }
        if ($k -ceq 'default_branch') { $PJ.default_branch = $v; WriteText "$(GL-_bare $gl $PJ)/HEAD" "ref: refs/heads/$v`n" }
        elseif ($k -ceq 'name') { $PJ.name = $v }
        else { $PJ.settings[$k] = $v }
    }
    GL-_write_protect $gl $PJ
    return (GL-_summary $gl $PJ)
}
function GL-_level($gl, $PJ, $u) {
    if ((HGet $gl.st.users[[string]$u] 'admin')) { return 60 }
    $l = [long](Dor $PJ.members[[string]$u] 0)
    $ns = [string]$PJ.namespace
    while ($ns.Length) {
        $g = $gl.st.groups[$ns]
        if ($g -and [long](Dor $g.members[[string]$u] 0) -gt $l) { $l = [long]$g.members[[string]$u] }
        $ns = $ns -creplace '/?[^/]*$', ''
    }
    return $l
}
$script:HOOK = @'
#!/usr/bin/env perl
# pre-receive hook written by lib/GitLab.pm (the local GitLab emulator): protected branches and tags, as GitLab
# enforces them. Reads protect.txt beside it (rewritten whenever protection or membership changes). The pusher is
# $GITLAB_USER_LOGIN; the emulator's own merges set GITLAB_EMULATOR_BYPASS=1.
use strict;
use warnings;
exit 0 if $ENV{GITLAB_EMULATOR_BYPASS};
my $dir = $ENV{GIT_DIR} // '.';
my (%member, @branch, @tag);
open my $fh, '<', "$dir/protect.txt" or exit 0;
while (<$fh>) {
    chomp;
    my @f = split /\t/;
    if    ($f[0] eq 'member') { $member{ $f[1] } = $f[2] }
    elsif ($f[0] eq 'branch') { push @branch, { name => $f[1], push => $f[2], force => $f[3] } }
    elsif ($f[0] eq 'tag')    { push @tag, { name => $f[1], create => $f[2] } }
}
close $fh;
sub match { my ($pat, $s) = @_; my $re = join '.*', map { quotemeta } split /\*/, $pat, -1; $s =~ /^$re$/ }
my $user = $ENV{GITLAB_USER_LOGIN} // '';
my $level = $member{$user} // 0;
my $z = '0' x 40;
my $empty = !`git for-each-ref --count=1 refs/heads`;     # "fully protected after initial push": the first push is allowed
my @err;
while (my $l = <STDIN>) {
    my ($old, $new, $ref) = split ' ', $l;
    if ($level < 30) { push @err, "You are not allowed to push code to this project."; next }
    if ($ref =~ m{^refs/heads/(.+)$}) {
        my $b = $1;
        my ($r) = grep { match($_->{name}, $b) } @branch;
        next unless $r;
        next if $empty && $old eq $z;
        if ($new eq $z) { push @err, "You are not allowed to delete protected branches from this project."; next }
        if ($r->{push} == 0 || $level < $r->{push}) { push @err, "You are not allowed to push code to protected branches on this project."; next }
        if ($old ne $z && !$r->{force}) {
            system('git', 'merge-base', '--is-ancestor', $old, $new);
            push @err, "You are not allowed to force push code to a protected branch on this project." if $?;
        }
    } elsif ($ref =~ m{^refs/tags/(.+)$}) {
        my $t = $1;
        my ($r) = grep { match($_->{name}, $t) } @tag;
        next unless $r;
        if ($old ne $z) { push @err, "You are not allowed to change existing tags on this project."; next }
        push @err, "You are not allowed to create this tag as it is protected." if $r->{create} == 0 || $level < $r->{create};
    }
}
if (@err) { print STDERR "GitLab: $_\n" for @err; exit 1 }
exit 0;
'@
function GL-_install_hook($gl, $PJ) { WriteText ((GL-_bare $gl $PJ) + '/hooks/pre-receive') (($script:HOOK -replace "`r", '') + "`n") }
function GL-_write_protect($gl, $PJ) {
    $f = (GL-_bare $gl $PJ) + '/protect.txt'
    $t = ''
    foreach ($u in (SortStr @($gl.st.users.Keys))) { $t += "member`t$u`t$(GL-_level $gl $PJ $u)`n" }
    foreach ($b in (L $PJ.protected_branches)) { $t += "branch`t$($b.name)`t$($b.push_access_level)`t$($b.allow_force_push)`n" }
    foreach ($b in (L $PJ.protected_tags)) { $t += "tag`t$($b.name)`t$($b.create_access_level)`n" }
    if (Test-Path -LiteralPath (Split-Path -Parent $f)) { WriteText $f $t }
}
function MatchGlob([string]$pat, [string]$s) { $re = (@(foreach ($x in ($pat -split '\*', -1)) { [regex]::Escape($x) }) -join '.*'); return ($s -cmatch "^$re$") }
function GL-_protected_branch($gl, $PJ, $b) { return (First $PJ.protected_branches { param($x) MatchGlob $x.name $b }) }
function GL-_sha($gl, $PJ, $ref) {                    # a ref's sha from the bare repository's files (no git: other forms are not resolved)
    if ([string]$ref -cmatch '^refs/(?:heads|tags)/[^\^~:\s]+$') {
        $b = GL-_bare $gl $PJ
        if (Test-Path -LiteralPath "$b/$ref" -PathType Leaf) { $l = ReadText "$b/$ref"; if ($l -cmatch '^([0-9a-f]{40})') { return $matches[1] } }
        if (Test-Path -LiteralPath "$b/packed-refs" -PathType Leaf) { foreach ($l in ((ReadText "$b/packed-refs") -split "`n")) { if ($l -cmatch '^([0-9a-f]{40}) (\S+)$' -and $matches[2] -ceq $ref) { return $matches[1] } } }
        return $null
    }
    return $null
}

# ---------------------------------------------------------------- issues and quick actions
function GL-_issue($gl, $PJ, $iid) { $i = First $PJ.issues { param($x) [long]$x.iid -eq [long](PNum $iid) }; if (-not $i) { throw "GitLab: no issue #$iid in $($PJ.path_with_namespace) (404 Not found)`n" }; return $i }
function GL-_mr($gl, $PJ, $iid) { $m = First $PJ.mrs { param($x) [long]$x.iid -eq [long](PNum $iid) }; if (-not $m) { throw "GitLab: no merge request !$iid in $($PJ.path_with_namespace) (404 Not found)`n" }; return $m }
function GL-_milestone($gl, $PJ, $t) { $m = First $PJ.milestones { param($x) $x.title -ceq [string]$t }; if (-not $m) { throw "GitLab: no milestone '$t' in $($PJ.path_with_namespace)`n" }; return $m }
function GL-_sysnote($gl, $obj, $body) { Push $obj 'notes' (O 'id' (GL-_id $gl) 'body' $body 'author' (O 'username' $gl.as) 'created_at' (GL-now $gl) 'system' 1) }
function GL-_labels_add($gl, $PJ, $obj, $ls) {
    foreach ($l in (L $ls)) {
        if ((L $obj.labels) -ccontains $l) { continue }
        if (-not (First $PJ.labels { param($x) $x.name -ceq $l })) { $null = GL-create_label $gl $PJ.path_with_namespace $l $null $null }
        if ($l -cmatch '^(.+)::[^:]+$') {
            $scope = [regex]::Escape($matches[1])
            $old = Where-L $obj.labels { param($x) [string]$x -cmatch "^$scope::[^:]+$" }
            if ($old.Count) {
                $obj.labels = Where-L $obj.labels { param($x) [string]$x -cnotmatch "^$scope::[^:]+$" }
                GL-_sysnote $gl $obj ('removed ' + ((@(foreach ($x in $old) { "~`"$x`"" })) -join ' ') + ' label' + $(if ($old.Count -gt 1) { 's' } else { '' }))
            }
        }
        $obj.labels = (L $obj.labels) + $l
        GL-_sysnote $gl $obj "added ~`"$l`" label"
    }
}
function GL-_labels_remove($gl, $obj, $ls) {
    $r = NewH; foreach ($x in (L $ls)) { $r[[string]$x] = 1 }
    $gone = Where-L $obj.labels { param($x) $r.ContainsKey([string]$x) }
    $obj.labels = Where-L $obj.labels { param($x) -not $r.ContainsKey([string]$x) }
    if ($gone.Count) { GL-_sysnote $gl $obj ('removed ' + ((@(foreach ($x in $gone) { "~`"$x`"" })) -join ' ') + ' label' + $(if ($gone.Count -gt 1) { 's' } else { '' })) }
}
function Duration([string]$s) {                       # GitLab time notation (1w 2d 3h 30m) -> seconds; 1w = 5d, 1d = 8h, 1mo = 4w
    $u = O 'mo' (4 * 5 * 8 * 3600) 'w' (5 * 8 * 3600) 'd' (8 * 3600) 'h' 3600 'm' 60
    $t = 0
    $neg = $false; if ($s -cmatch '^\s*-') { $neg = $true; $s = $s -creplace '^\s*-', '' }
    foreach ($m in [regex]::Matches($s, '(\d+(?:\.\d+)?)\s*(mo|w|d|h|m)\b')) { $t += [double]$m.Groups[1].Value * $u[$m.Groups[2].Value] }
    if ($t -eq (Trunc $t)) { $t = [long]$t }
    if ($neg) { return - $t }; return $t
}
function GL-_quick($gl, $PJ, $kind, $obj, $body) {
    $keep = @()
    $tokens = { param($s) $t = @(); foreach ($m in [regex]::Matches($s, '([~%@#!])(?:"([^"]+)"|(\S+))')) { $v = $(if ($m.Groups[2].Success) { $m.Groups[2].Value } else { $m.Groups[3].Value }); $t += , @($m.Groups[1].Value, $v) }; , $t }
    foreach ($line in (([string](Dor $body '')) -split "`n")) {
        if ($line -cnotmatch '^/([a-z_]+)\b\s*(.*?)\s*$') { $keep += $line; continue }
        $cmd = $matches[1]; $arg = $matches[2]
        $t = & $tokens $arg
        if ($cmd -ceq 'milestone' -and -not (First $t { param($x) $x[0] -ceq '%' -and (First $PJ.milestones { param($m) $m.title -ceq $x[1] }) })) { continue }
        if ($cmd -cmatch '^(assign|label|relabel|relate|blocks|blocked_by)$' -and $t.Count -eq 0) { continue }
        if ($cmd -ceq 'assign' -and -not (First $t { param($x) $x[0] -ceq '@' -and $x[1].Length })) { continue }
        if ($cmd -cmatch '^(estimate|spend)$' -and $arg -cnotmatch '\d') { continue }
        if ($cmd -ceq 'weight' -and $arg -cnotmatch '^\d+$') { continue }
        if ($cmd -cmatch '^(due|title)$' -and $arg -cnotmatch '\S') { continue }
        if ($cmd -ceq 'label') { GL-_labels_add $gl $PJ $obj (Map-L (Where-L $t { param($x) $x[0] -ceq '~' }) { param($x) $x[1] }) }
        elseif ($cmd -ceq 'unlabel') { if ($t.Count) { GL-_labels_remove $gl $obj (Map-L (Where-L $t { param($x) $x[0] -ceq '~' }) { param($x) $x[1] }) } else { GL-_labels_remove $gl $obj (L $obj.labels) } }
        elseif ($cmd -ceq 'relabel') { GL-_labels_remove $gl $obj (L $obj.labels); GL-_labels_add $gl $PJ $obj (Map-L (Where-L $t { param($x) $x[0] -ceq '~' }) { param($x) $x[1] }) }
        elseif ($cmd -ceq 'milestone') {
            $mt = (First $t { param($x) $x[0] -ceq '%' })[1]; $ms = GL-_milestone $gl $PJ $mt
            $obj.milestone = O 'id' $ms.id 'iid' $ms.iid 'title' $ms.title; GL-_sysnote $gl $obj "changed milestone to %`"$mt`""
        }
        elseif ($cmd -ceq 'remove_milestone') { $obj.milestone = $null; GL-_sysnote $gl $obj 'removed milestone' }
        elseif ($cmd -ceq 'assign') {
            foreach ($x in $t) {
                if ($x[0] -cne '@') { continue }
                $u = $(if ($x[1] -ceq 'me') { $gl.as } else { $x[1] })
                $null = GL-_user $gl $u (NewH)
                if (-not (First $obj.assignees { param($a) $a.username -ceq $u })) { Push $obj 'assignees' (O 'username' $u 'name' $gl.st.users[$u].name) }
                GL-_sysnote $gl $obj "assigned to @$u"
            }
        }
        elseif ($cmd -ceq 'unassign') { $obj.assignees = @(); GL-_sysnote $gl $obj 'unassigned' }
        elseif ($cmd -ceq 'close') { GL-_close $gl $obj $null }
        elseif ($cmd -ceq 'reopen') { if ($obj.state -ceq 'closed') { $obj.state = 'opened'; $obj.closed_at = $null; GL-_sysnote $gl $obj 'reopened' } }
        elseif ($cmd -ceq 'estimate') { $obj.time_stats.time_estimate = Duration $arg; GL-_sysnote $gl $obj "changed time estimate to $arg" }
        elseif ($cmd -ceq 'spend') { $d = @($arg.Trim() -split '\s+')[0]; $obj.time_stats.total_time_spent = (PNum $obj.time_stats.total_time_spent) + (Duration $d); GL-_sysnote $gl $obj "added $d of time spent" }
        elseif ($cmd -ceq 'relate') { foreach ($x in $t) { if ($x[0] -ceq '#') { $null = GL-link_issues $gl $PJ.path_with_namespace $obj.iid $x[1] 'relates_to' } }; GL-_sysnote $gl $obj "marked this issue as related to $arg" }
        elseif ($cmd -ceq 'blocks') { foreach ($x in $t) { if ($x[0] -ceq '#') { $null = GL-link_issues $gl $PJ.path_with_namespace $obj.iid $x[1] 'blocks' } } }
        elseif ($cmd -ceq 'blocked_by') { foreach ($x in $t) { if ($x[0] -ceq '#') { $null = GL-link_issues $gl $PJ.path_with_namespace $obj.iid $x[1] 'is_blocked_by' } } }
        elseif ($cmd -ceq 'title') { $obj.title = $arg; GL-_sysnote $gl $obj "changed title to **$arg**" }
        elseif ($cmd -ceq 'due') { $obj.due_date = $arg; GL-_sysnote $gl $obj "changed due date to $arg" }
        elseif ($cmd -ceq 'weight') { $obj.weight = PNum $arg; GL-_sysnote $gl $obj "set weight to $arg" }
        elseif ($cmd -ceq 'approve' -and $kind -ceq 'mr') { $null = GL-_approve $gl $PJ.path_with_namespace $obj.iid }
        elseif ($cmd -ceq 'draft' -and $kind -ceq 'mr') { $obj.draft = 1; if ($obj.title -cnotmatch '^Draft:') { $obj.title = "Draft: $($obj.title)" }; GL-_sysnote $gl $obj 'marked this merge request as **draft**' }
        elseif ($cmd -ceq 'ready' -and $kind -ceq 'mr') { $obj.draft = 0; $obj.title = $obj.title -creplace '^Draft:\s*', ''; GL-_sysnote $gl $obj 'marked this merge request as **ready**' }
        elseif ($cmd -ceq 'done' -or $cmd -ceq 'todo') { }
        else { $keep += $line }
    }
    $t = $keep -join "`n"
    $t = $t -creplace '^\s*\n+', ''
    $t = $t -creplace '\s+$', ''
    return $t
}
function GL-_close($gl, $obj, $note) {
    if ($obj.state -cne 'opened') { return }
    $obj.state = 'closed'; $obj.closed_at = GL-now $gl; $obj.closed_by = O 'username' $gl.as
    GL-_sysnote $gl $obj (Dor $note 'closed')
}
function GL-_create_issue($gl, $p, $o) {
    $PJ = GL-_p $gl $p
    if ($null -eq $PJ.iids) { $PJ.iids = NewH }
    $PJ.iids.issue = [long](Dor $PJ.iids.issue 0) + 1; $iid = $PJ.iids.issue
    $type = Dor $o.issue_type 'issue'
    if ([string]$type -cnotmatch '^(issue|task|incident)$') { throw "GitLab: issue_type is issue, task or incident, not '$type'`n" }
    $i = O 'id' (GL-_id $gl) 'iid' $iid 'project_id' $PJ.id 'title' $o.title 'description' '' 'state' 'opened' 'labels' @() 'milestone' $null `
        'assignees' @() 'author' (O 'username' $gl.as) 'issue_type' $type 'type' ([string]$type).ToUpperInvariant() 'weight' $o.weight 'due_date' $o.due_date `
        'created_at' (GL-now $gl) 'updated_at' (GL-now $gl) 'closed_at' $null 'web_url' ("$($gl.base)/$p/-/" + $(if ($type -ceq 'task') { 'work_items' } else { 'issues' }) + "/$iid") `
        'references' (O 'short' "#$iid" 'full' "$p#$iid") 'time_stats' (O 'time_estimate' 0 'total_time_spent' 0) 'links' @() 'notes' @()
    Push $PJ 'issues' $i
    if (Tru $o.labels) { GL-_labels_add $gl $PJ $i (Arr $o.labels) }
    if (Tru $o.milestone) { $m = GL-_milestone $gl $PJ $o.milestone; $i.milestone = O 'id' $m.id 'iid' $m.iid 'title' $m.title }
    foreach ($u in (Arr $o.assignees)) { $null = GL-_user $gl $u (NewH); Push $i 'assignees' (O 'username' $u 'name' $gl.st.users[$u].name) }
    $i.description = GL-_quick $gl $PJ 'issue' $i (Dor $o.description '')
    $i.notes = @()
    return $i
}
function GL-_update_issue($gl, $p, $iid, $o) {
    $PJ = GL-_p $gl $p
    $i = GL-_issue $gl $PJ $iid
    if (Tru $o.add_labels) { GL-_labels_add $gl $PJ $i (Arr $o.add_labels) }
    if (Tru $o.remove_labels) { GL-_labels_remove $gl $i (Arr $o.remove_labels) }
    if ($null -ne $o.labels) { GL-_labels_remove $gl $i (L $i.labels); GL-_labels_add $gl $PJ $i (Arr $o.labels) }
    if ($null -ne $o.milestone) { if ([string]$o.milestone -ceq '') { $i.milestone = $null } else { $m = GL-_milestone $gl $PJ $o.milestone; $i.milestone = O 'id' $m.id 'iid' $m.iid 'title' $m.title } }
    if (Tru $o.assignees) { $i.assignees = Map-L (Arr $o.assignees) { param($u) $null = GL-_user $gl $u (NewH); O 'username' $u 'name' $gl.st.users[$u].name } }
    foreach ($k in @('title', 'description', 'weight', 'due_date')) { if ($null -ne $o[$k]) { $i[$k] = $o[$k] } }
    $e = $o.state_event
    if (Tru $e) {
        if ($e -ceq 'close') { GL-_close $gl $i $null }
        elseif ($e -ceq 'reopen') { if ($i.state -ceq 'closed') { $i.state = 'opened'; $i.closed_at = $null; GL-_sysnote $gl $i 'reopened' } }
        else { throw "GitLab: state_event is close or reopen, not '$e'`n" }
    }
    $i.updated_at = GL-now $gl
    return $i
}
function GL-_add_note($gl, $p, $kind, $iid, $body, $o) {
    $PJ = GL-_p $gl $p
    $obj = $(if ($kind -ceq 'mr') { GL-_mr $gl $PJ $iid } else { GL-_issue $gl $PJ $iid })
    $text = GL-_quick $gl $PJ $kind $obj $body
    $obj.updated_at = GL-now $gl
    if ($text.Length -eq 0) { return (O 'commands_only' 1) }
    $n = O 'id' (GL-_id $gl) 'body' $text 'author' (O 'username' $gl.as) 'created_at' (GL-now $gl) 'system' 0 'resolvable' $(if (Tru $o.resolvable) { 1 } else { 0 }) 'resolved' 0
    Push $obj 'notes' $n
    return $n
}

# ---------------------------------------------------------------- merge requests (state only: merging needs git)
function GL-_create_mr($gl, $p, $o) {
    $PJ = GL-_p $gl $p
    $s = $o.source_branch; $t = $o.target_branch
    if (-not (GL-_sha $gl $PJ "refs/heads/$s")) { throw "GitLab: source branch '$s' does not exist in $p`n" }
    if (-not (GL-_sha $gl $PJ "refs/heads/$t")) { throw "GitLab: target branch '$t' does not exist in $p`n" }
    $dup = Where-L $PJ.mrs { param($m) $m.state -ceq 'opened' -and $m.source_branch -ceq $s -and $m.target_branch -ceq $t }
    if ($dup.Count) { throw ("GitLab: another open merge request already exists for this source branch: !" + ((@(foreach ($m in $dup) { $m.iid })) -join ', !') + "`n") }
    if (-not (Tru $o.no_pipeline)) { throw $script:NOGIT }       # GitLab.pm runs the MR pipeline here (lib/GitLabCI.pm, git)
    if ($null -eq $PJ.iids) { $PJ.iids = NewH }
    $PJ.iids.mr = [long](Dor $PJ.iids.mr 0) + 1; $iid = $PJ.iids.mr
    $rsb = $(if ($null -ne $o.remove_source_branch) { $(if (Tru $o.remove_source_branch) { 1 } else { 0 }) } elseif (Tru $PJ.settings.remove_source_branch_after_merge) { 1 } else { 0 })
    $m = O 'id' (GL-_id $gl) 'iid' $iid 'project_id' $PJ.id 'title' $o.title 'description' '' 'state' 'opened' 'source_branch' $s 'target_branch' $t `
        'labels' @() 'milestone' $null 'author' (O 'username' $gl.as) 'assignees' @() 'reviewers' @() 'created_at' (GL-now $gl) 'updated_at' (GL-now $gl) `
        'merged_at' $null 'merged_by' $null 'merge_commit_sha' $null 'sha' (GL-_sha $gl $PJ "refs/heads/$s") 'draft' $(if ($o.title -cmatch '^(?i)(Draft|WIP):') { 1 } else { 0 }) `
        'remove_source_branch' $rsb 'web_url' "$($gl.base)/$p/-/merge_requests/$iid" 'references' (O 'short' "!$iid" 'full' "$p!$iid") 'approved_by' @() 'notes' @() `
        'pipelines' @() 'head_pipeline' $null 'has_conflicts' 0
    Push $PJ 'mrs' $m
    if (Tru $o.labels) { GL-_labels_add $gl $PJ $m (Arr $o.labels) }
    if (Tru $o.milestone) { $ms = GL-_milestone $gl $PJ $o.milestone; $m.milestone = O 'id' $ms.id 'iid' $ms.iid 'title' $ms.title }
    if (Tru $o.assignee) { $m.assignees = Map-L (Arr $o.assignee) { param($u) $null = GL-_user $gl $u (NewH); O 'username' $u } }
    if (Tru $o.reviewers) { $m.reviewers = Map-L (Arr $o.reviewers) { param($u) $null = GL-_user $gl $u (NewH); O 'username' $u } }
    $m.description = GL-_quick $gl $PJ 'mr' $m (Dor $o.description '')
    $m.notes = @()
    return $m
}
function GL-_approve($gl, $p, $iid) {
    $PJ = GL-_p $gl $p
    $m = GL-_mr $gl $PJ $iid
    $u = $gl.as
    if ($m.state -cne 'opened') { throw "GitLab: merge request !$iid is not open`n" }
    if ($m.author.username -ceq $u) { throw "GitLab: $u wrote merge request !$iid and cannot approve it (401 Unauthorized)`n" }
    if ((GL-_level $gl $PJ $u) -lt 20) { throw "GitLab: $u has no access to approve in $p (401 Unauthorized)`n" }
    if (First $m.approved_by { param($a) $a.user.username -ceq $u }) { throw "GitLab: $u already approved merge request !$iid (401 Unauthorized)`n" }
    Push $m 'approved_by' (O 'user' (O 'username' $u) 'approved_at' (GL-now $gl))
    GL-_sysnote $gl $m 'approved this merge request'
    return $m
}
function GL-_merge($gl, $p, $iid, $o) {
    $PJ = GL-_p $gl $p
    $m = GL-_mr $gl $PJ $iid
    if ($m.state -cne 'opened') { throw "GitLab: MR is not open (!$iid is $($m.state)) (405 Method Not Allowed)`n" }
    if (Tru $m.draft) { throw "GitLab: MR !$iid is a draft; mark it ready first (405 Method Not Allowed)`n" }
    if (Tru $o.squash) { throw "GitLab: squash is not supported by the local emulator (the project merges with merge commits)`n" }
    if (-not (GL-_sha $gl $PJ "refs/heads/$($m.source_branch)")) { throw "GitLab: source branch '$($m.source_branch)' no longer exists`n" }
    throw $script:NOGIT
}
