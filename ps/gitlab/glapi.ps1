# glapi.ps1 -- lib/GitLab.pm in PowerShell: one interface, two backends (REST API v4 through Invoke-WebRequest; the
# offline emulator with its state in DIR\gitlab.json). Methods are functions taking the client ($gl) first, then the
# project path, as GitLab.pm's do. Constrained Language Mode safe.
#
# The emulator here has no git: projects get their bare repository folder, hook and protection file written directly,
# and everything that keeps state only (users, groups, members, variables, labels, milestones, boards, iterations,
# statuses, work items, issues and quick actions, notes, links, approvals, protections, wiki, packages, schedules,
# trigger and deploy tokens) works as in GitLab.pm. What needs git or the CI runner (creating branches and tags,
# merging, pipelines, reading files from the repository) stops with $script:NOGIT.

$script:NOGIT = "GitLab: this needs git and the CI runner (branches, tags, merges, pipelines, repository files), which this PC does not have; the PowerShell emulator keeps issues, labels, milestones, boards and the rest: use a GitLab server (--url) for repository work`n"
$script:LEVEL = NewH
foreach ($kv in @(@('none', 0), @('no one', 0), @('noone', 0), @('guest', 10), @('reporter', 20), @('developer', 30), @('maintainer', 40), @('owner', 50), @('admin', 60))) { $script:LEVEL[$kv[0]] = $kv[1] }
$script:ZERO = '0' * 40

function O { $h = NewH; for ($i = 0; $i + 1 -lt $args.Count; $i += 2) { $h[[string]$args[$i]] = $args[$i + 1] }; return $h }   # a hash from pairs
function Push($__h, [string]$__k, $__item) { $__c = $__h[$__k]; if ($null -eq $__c) { $__c = @() }; $__h[$__k] = @($__c) + , $__item }
function First($__l, [scriptblock]$__f) { foreach ($__x in (L $__l)) { if (& $__f $__x) { return $__x } }; return $null }
function Where-L($__l, [scriptblock]$__f) { $__o = @(); foreach ($__x in (L $__l)) { if (& $__f $__x) { $__o += , $__x } }; return , $__o }
function Map-L($__l, [scriptblock]$__f) { $__o = @(); foreach ($__x in (L $__l)) { $__o += , (& $__f $__x) }; return , $__o }
function JTrue { return $true }
function JFalse { return $false }
function Jbool($v) { if ($null -eq $v -or $v -is [bool]) { return $v }; if ([string]$v -cmatch '^(?i)(true|yes|on)$') { return $true }; if ([string]$v -cmatch '^(?i)(false|no|off)$') { return $false }; return $v }
function LevelOf($n) {
    $s = ([string](Dor $n '')).ToLowerInvariant()
    if ($s -cmatch '^\d+$') { return $s }
    if ($script:LEVEL.ContainsKey($s)) { return $script:LEVEL[$s] }
    throw "GitLab: unknown access level '$s' (none, developer, maintainer, owner)`n"
}

# ---------------------------------------------------------------- construction, identity, time
function New-GL($o) {
    $gl = NewH
    $gl.as = Dor $o.user 'root'; $gl.base = Dor $o.url_base 'https://gitlab.local'
    $gl.dry_run = [bool](Tru $o.dry_run); $gl.sudo = [bool](Tru $o.sudo); $gl.force_rest = 0
    $gl.uids = NewH; $gl.wit = NewH
    if ($null -ne $o.local) {
        $dir = [string]$o.local
        if (-not (Test-Path -LiteralPath $dir)) { $null = New-Item -ItemType Directory -Path $dir -Force }
        if (-not (Test-Path -LiteralPath $dir -PathType Container)) { throw "GitLab: cannot create $dir`n" }
        $gl.local = (Resolve-Path -LiteralPath $dir).ProviderPath -creplace '\\', '/'
        $f = "$($gl.local)/gitlab.json"
        if (Test-Path -LiteralPath $f) { $gl.st = JsDec (ReadText $f) }
        else { $gl.st = O 'next_id' 0 'users' (NewH) 'groups' (NewH) 'projects' (NewH) 'ci_cache' (NewH) }
        if ($null -eq $gl.st.users['root']) { $gl.st.users['root'] = O 'id' 1 'username' 'root' 'name' 'Administrator' 'email' 'admin@example.invalid' 'admin' 1 }
        if ($null -ne $o.now) { GL-clock $gl $o.now | Out-Null }
        if ($null -eq $gl.t) { if ($null -ne $gl.st.clock) { $gl.t = Epoch $gl.st.clock } else { $gl.t = NowEpoch } }
        $gl.wall0 = NowEpoch
    } else {
        if ($null -eq $o.url) { throw "GitLab: give url => URL (a GitLab server) or local => DIR (the emulator)`n" }
        $gl.url = ([string]$o.url) -creplace '/+$', ''
        $gl.token_env = Dor $o.token_env 'GITLAB_TOKEN'
        $gl.t = NowEpoch
        if ($null -ne $o.now) { GL-clock $gl $o.now | Out-Null }
    }
    return $gl
}
function IsLocal($gl) { return , ([bool]$gl.local -and $gl.force_rest -eq 0) }      # the emulator, unless a dry run took the REST path
function GL-is_local($gl) { return [bool]$gl.local }
function GL-as($gl, $u) { if ($null -ne $u) { $gl.as = $u; if ($gl.local) { $null = GL-_user $gl $u (NewH) }; return $gl }; return $gl.as }
function GL-clock($gl, $t) {
    if ([string]$t -cmatch '^\d+$') { $gl.t = [long]$t } else { $gl.t = Epoch ([string]$t) }
    $gl.wall0 = NowEpoch
    if ($gl.local) { $gl.st.clock = IsoT $gl.t }
    return $gl
}
function GL-epoch($gl) { return [long]($gl.t + ((NowEpoch) - (Dor $gl.wall0 (NowEpoch)))) }
function GL-now($gl) { return , (IsoT (GL-epoch $gl)) }
function GL-save($gl) {
    if (-not $gl.local -or $gl.dry_run) { return }
    $gl.st.clock = GL-now $gl
    $f = "$($gl.local)/gitlab.json"
    WriteText "$f.tmp" ((JsEnc $gl.st $true) + "`n")
    Move-Item -LiteralPath "$f.tmp" -Destination $f -Force
}
function GL-_id($gl) { $gl.st.next_id = [long]$gl.st.next_id + 1; return $gl.st.next_id }

# A dry run on the emulator takes the REST path (it prints the request), reads included, as GitLab.pm's wrapper does.
function DryWrap($gl, [scriptblock]$__b) {
    $__r = $null
    if ($gl.local -and $gl.dry_run -and $gl.force_rest -eq 0) { $gl.force_rest++; try { $__r = & $__b } finally { $gl.force_rest-- }; return , $__r }
    $__r = & $__b
    return , $__r
}

# ================================================================ REST backend
function GL-_api($gl, [string]$method, [string]$path, $body, $o) {
    if ($null -eq $o) { $o = NewH }
    $q = Copy-H $o.query
    if (Tru $o.all) {
        $all = @(); if ($null -eq $q.per_page) { $q.per_page = 100 }
        $page = 1
        while ($null -ne $page -and [string]$page -cne '') {
            $q.page = $page
            $r = GL-_api1 $gl $method $path $null $q
            if ($r[0] -is [array]) { $all += $r[0] }
            $page = $r[1]['x-next-page']
        }
        return , $all
    }
    $r = GL-_api1 $gl $method $path $body $q
    return , $r[0]
}
function GL-_api1($gl, [string]$method, [string]$path, $body, $q) {
    $rel = $(if ($path -cmatch '^/api/graphql') { $path } else { "/api/v4$path" }) + (QStr $q)
    if ($gl.dry_run) {
        $line = "$method $rel"; if ($null -ne $body) { $line += ' ' + (JsEnc $body) }
        GOut "$line`n"
        if ($method -ceq 'GET') { if ($q.page) { return , @(@(), (NewH)) } else { return , @((NewH), (NewH)) } }
        $r = Copy-H $body; $r.id = 0; $r.iid = 0
        return , @($r, (NewH))
    }
    $tok = (Get-Item -LiteralPath ("env:" + $gl.token_env) -ErrorAction SilentlyContinue).Value
    if (-not $tok) { throw "GitLab: set $($gl.token_env) to a personal or project access token (scope api)`n" }
    $hd = @{ 'PRIVATE-TOKEN' = $tok; 'Accept' = 'application/json' }
    if ($gl.sudo -and $gl.as -and $gl.as -cne 'root') { $hd['Sudo'] = $gl.as }
    $url = "$($gl.url)$rel"
    $status = 0; $text = ''; $hdr = NewH
    try {
        if ($null -ne $body) {
            $resp = Invoke-WebRequest -Uri $url -Method $method -Headers $hd -UseBasicParsing -ContentType 'application/json; charset=utf-8' -Body ([byte[]](Utf8B (JsEnc $body))) -ErrorAction Stop
        } else {
            $resp = Invoke-WebRequest -Uri $url -Method $method -Headers $hd -UseBasicParsing -ErrorAction Stop
        }
        $status = [int]$resp.StatusCode
        $text = [string]$resp.Content
        foreach ($k in @($resp.Headers.Keys)) { $hdr[([string]$k).ToLowerInvariant()] = [string]$resp.Headers[$k] }
    } catch {
        $ex = $_.Exception
        if ($null -ne $ex.Response) {
            $status = [int]$ex.Response.StatusCode
            $text = [string]$_.ErrorDetails.Message
        } else { throw "GitLab: curl exit 7: $($ex.Message)`n" }
    }
    $data = $text
    if ($text.Length -and $text -cmatch '^\s*[\[{]') { try { $data = JsDec $text } catch { $data = $text } }
    if ($status -ge 400) {
        $msg = $text
        if ($data -is [hashtable]) { $msg = Dor $data.message (Dor $data.error '') }
        if ($msg -is [hashtable] -or $msg -is [array]) { $msg = JsEnc $msg }
        throw "GitLab: $method ${path}: $status $msg`n"
    }
    return , @($data, $hdr)
}
function GL-_pid($gl, $p) { return , (Enc $p) }
function GL-_uid($gl, $u) {
    if ($gl.dry_run) { return "{id of $u}" }
    if ($null -eq $gl.uids[$u]) {
        $r = GL-_api $gl 'GET' '/users' $null (O 'query' (O 'username' $u))
        if ($r -is [array] -and $r.Count) { $gl.uids[$u] = $r[0].id } else { throw "GitLab: no user '$u'`n" }
    }
    return $gl.uids[$u]
}
function GL-_mid($gl, $p, $title) {
    if ($gl.dry_run) { return "{id of milestone $title}" }
    $r = GL-_api $gl 'GET' ('/projects/' + (Enc $p) + '/milestones') $null (O 'query' (O 'title' $title))
    if ($r -is [array] -and $r.Count) { return $r[0].id }
    throw "GitLab: no milestone '$title' in $p`n"
}

# ================================================================ public API
function GL-create_user($gl, $u, $o) {
    if ($null -eq $o) { $o = NewH }
    return , (DryWrap $gl {
        if (IsLocal $gl) { return , (GL-_user $gl $u $o) }
        $b = O 'username' $u 'name' (Dor $o.name $u) 'email' (Dor $o.email "$u@example.invalid") 'skip_confirmation' $true
        if (Tru $o.password) { $b.password = $o.password } else { $b.reset_password = $true }
        return , (GL-_api $gl 'POST' '/users' $b)
    })
}
function GL-create_group($gl, $path, $o) {
    if ($null -eq $o) { $o = NewH }
    return , (DryWrap $gl {
        if (IsLocal $gl) {
            if ($null -eq $gl.st.groups[$path]) { $gl.st.groups[$path] = O 'id' (GL-_id $gl) 'full_path' $path 'name' (Dor $o.name $path) 'members' (NewH) 'created_at' (GL-now $gl) }
            return $gl.st.groups[$path]
        }
        $parent = $null; $name = $path
        if ($path -cmatch '^(?:(.*)/)?([^/]+)$') { $parent = $matches[1]; $name = $matches[2] }
        $b = O 'name' (Dor $o.name $name) 'path' $name 'visibility' (Dor $o.visibility 'private')
        if ($parent) { $b.parent_id = (GL-_api $gl 'GET' ('/groups/' + (Enc $parent))).id }
        return , (GL-_api $gl 'POST' '/groups' $b)
    })
}
function GL-project($gl, $p) {
    if (IsLocal $gl) { return , (GL-_summary $gl (GL-_p $gl $p)) }
    return , (GL-_api $gl 'GET' ('/projects/' + (Enc $p)))
}
function GL-create_project($gl, $path, $o) {
    if ($null -eq $o) { $o = NewH }
    return , (DryWrap $gl {
        if (IsLocal $gl) { return , (GL-_create_project $gl $path $o) }
        if ($path -cnotmatch '^(.*)/([^/]+)$') { throw "GitLab: project path '$path' needs a group: group/name`n" }
        $ns = $matches[1]; $name = $matches[2]
        $nsid = $(if ($gl.dry_run) { "{id of $ns}" } else { (GL-_api $gl 'GET' ('/namespaces/' + (Enc $ns))).id })
        $b = O 'name' (Dor $o.name $name) 'path' $name 'namespace_id' $nsid 'visibility' (Dor $o.visibility 'private') 'initialize_with_readme' $false
        foreach ($k in @($o.Keys)) { if ($k -cne 'name' -and $k -cne 'visibility') { $b[$k] = $o[$k] } }
        return , (GL-_api $gl 'POST' '/projects' $b)
    })
}
function GL-update_project($gl, $p, $s) {
    return , (DryWrap $gl {
        if (IsLocal $gl) { return , (GL-_update_project $gl $p $s) }
        $b = NewH; foreach ($k in @($s.Keys)) { $b[$k] = Jbool $s[$k] }
        return , (GL-_api $gl 'PUT' ('/projects/' + (Enc $p)) $b)
    })
}
function GL-add_member($gl, $p, $u, $lvl, $o) {
    if ($null -eq $o) { $o = NewH }
    return , (DryWrap $gl {
        $l = LevelOf $lvl
        if (IsLocal $gl) {
            $null = GL-_user $gl $u (NewH)
            $g = $gl.st.groups[$p]
            $h = $(if ($g) { $g.members } else { (GL-_p $gl $p).members })
            $h[$u] = $l
            if ($g) { foreach ($PJ in @($gl.st.projects.Values)) { if ($PJ.namespace -ceq $p) { GL-_write_protect $gl $PJ } } }
            else { GL-_write_protect $gl (GL-_p $gl $p) }
            return , (O 'username' $u 'access_level' $l)
        }
        $kind = $(if (Tru $o.group) { 'groups' } else { 'projects' })
        return , (GL-_api $gl 'POST' "/$kind/$(Enc $p)/members" (O 'user_id' (GL-_uid $gl $u) 'access_level' $l))
    })
}
function GL-set_variable($gl, $p, $k, $v, $o) {
    if ($null -eq $o) { $o = NewH }
    return , (DryWrap $gl {
        if (IsLocal $gl) {
            $PJ = GL-_p $gl $p
            $PJ.variables[$k] = O 'key' $k 'value' $v 'protected' $(if (Tru $o.protected) { 1 } else { 0 }) 'masked' $(if (Tru $o.masked) { 1 } else { 0 })
            return $PJ.variables[$k]
        }
        return , (GL-_api $gl 'POST' ('/projects/' + (Enc $p) + '/variables') (O 'key' $k 'value' $v 'protected' (Jbool $(if (Tru $o.protected) { 'true' } else { 'false' })) 'masked' (Jbool $(if (Tru $o.masked) { 'true' } else { 'false' }))))
    })
}
function GL-create_label($gl, $p, $name, $color, $desc) {
    return , (DryWrap $gl {
        if (IsLocal $gl) {
            $PJ = GL-_p $gl $p
            $l = First $PJ.labels { param($x) $x.name -ceq $name }
            if ($l) { $l.color = Dor $color $l.color; $l.description = Dor $desc $l.description; return $l }
            $l = O 'id' (GL-_id $gl) 'name' $name 'color' (Dor $color '#6699cc') 'description' (Dor $desc '')
            Push $PJ 'labels' $l
            return $l
        }
        return , (GL-_api $gl 'POST' ('/projects/' + (Enc $p) + '/labels') (O 'name' $name 'color' (Dor $color '#6699cc') 'description' (Dor $desc '')))
    })
}
function GL-labels($gl, $p) {
    if (IsLocal $gl) { return , @((GL-_p $gl $p).labels) }
    return , (GL-_api $gl 'GET' ('/projects/' + (Enc $p) + '/labels') $null (O 'all' 1))
}
function GL-create_milestone($gl, $p, $title, $o) {
    if ($null -eq $o) { $o = NewH }
    return , (DryWrap $gl {
        if (IsLocal $gl) {
            $PJ = GL-_p $gl $p
            if (First $PJ.milestones { param($x) $x.title -ceq $title }) { throw "GitLab: milestone '$title' already exists in $p`n" }
            if ($null -eq $PJ.iids) { $PJ.iids = NewH }
            $PJ.iids.milestone = [long](Dor $PJ.iids.milestone 0) + 1
            $m = O 'id' (GL-_id $gl) 'iid' $PJ.iids.milestone 'title' $title 'description' (Dor $o.description '') 'start_date' $o.start_date 'due_date' $o.due_date 'state' 'active' 'created_at' (GL-now $gl)
            Push $PJ 'milestones' $m
            return $m
        }
        $b = O 'title' $title
        foreach ($k in @('description', 'start_date', 'due_date')) { if ($null -ne $o[$k]) { $b[$k] = $o[$k] } }
        return , (GL-_api $gl 'POST' ('/projects/' + (Enc $p) + '/milestones') $b)
    })
}
function GL-milestones($gl, $p) {
    if (IsLocal $gl) { return , @((GL-_p $gl $p).milestones) }
    return , (GL-_api $gl 'GET' ('/projects/' + (Enc $p) + '/milestones') $null (O 'all' 1))
}
function GL-update_milestone($gl, $p, $title, $o) {
    return , (DryWrap $gl {
        if (IsLocal $gl) {
            $m = First (GL-_p $gl $p).milestones { param($x) $x.title -ceq $title }
            if (-not $m) { throw "GitLab: no milestone '$title' in $p`n" }
            $o2 = Copy-H $o
            if ($o2.state_event) { if ($o2.state_event -ceq 'close') { $m.state = 'closed' } else { $m.state = 'active' }; $o2.Remove('state_event') }
            foreach ($k in @($o2.Keys)) { $m[$k] = $o2[$k] }
            return $m
        }
        return , (GL-_api $gl 'PUT' ('/projects/' + (Enc $p) + '/milestones/' + (GL-_mid $gl $p $title)) $o)
    })
}

# ---------------------------------------------------------------- issue boards
$script:BOARD_MS = NewH; $script:BOARD_MS['none'] = 0; $script:BOARD_MS['any'] = -1; $script:BOARD_MS['upcoming'] = -2; $script:BOARD_MS['started'] = -3
$script:BOARD_MS_NAME = NewH; foreach ($k in @($script:BOARD_MS.Keys)) { $script:BOARD_MS_NAME[[string]$script:BOARD_MS[$k]] = $k }
function BoardScope($m) {
    if (-not ($m -is [hashtable]) -or ($null -eq $m.id -and $null -eq $m.title)) { return 'any' }
    if ($null -ne $m.id -and $script:BOARD_MS_NAME.ContainsKey([string]$m.id)) { return $script:BOARD_MS_NAME[[string]$m.id] }
    $t = [string](Dor $m.title '')
    if ($t -cmatch '^(?i)(upcoming|started)$') { return $t.ToLowerInvariant() }
    if ($t -cmatch '^(?i)any milestone$') { return 'any' }
    if ($t -cmatch '^(?i)no milestone$') { return 'none' }
    return $t
}
function GL-boards($gl, $p) {
    if (IsLocal $gl) {
        $o = @(); foreach ($b in (L (GL-_p $gl $p).boards)) { $c = Copy-H $b; $c.lists = Map-L $b.lists { param($x) Copy-H $x }; $o += , $c }
        return , $o
    }
    return , (GL-_api $gl 'GET' ('/projects/' + (Enc $p) + '/boards') $null (O 'all' 1))
}
function GL-create_board($gl, $p, $name) {
    return , (DryWrap $gl {
        if (IsLocal $gl) { $PJ = GL-_p $gl $p; $b = O 'id' (GL-_id $gl) 'name' $name 'milestone' $null 'lists' @(); Push $PJ 'boards' $b; return $b }
        return , (GL-_api $gl 'POST' ('/projects/' + (Enc $p) + '/boards') (O 'name' $name))
    })
}
function GL-_board($gl, $PJ, $id) {
    $b = First $PJ.boards { param($x) [long]$x.id -eq [long]$id }
    if (-not $b) { throw "GitLab: no board $id in $($PJ.path_with_namespace) (404 Not found)`n" }
    return $b
}
function GL-update_board($gl, $p, $id, $o) {
    return , (DryWrap $gl {
        $want = Dor $o.milestone 'any'
        $lw = ([string]$want).ToLowerInvariant()
        if (IsLocal $gl) {
            $PJ = GL-_p $gl $p
            $b = GL-_board $gl $PJ $id
            if ($script:BOARD_MS.ContainsKey($lw)) {
                if ($lw -ceq 'any') { $b.milestone = $null }
                else { $t = $(if ($lw -ceq 'none') { 'No Milestone' } else { $lw.Substring(0, 1).ToUpperInvariant() + $lw.Substring(1) }); $b.milestone = O 'id' $script:BOARD_MS[$lw] 'title' $t }
            } else { $m = GL-_milestone $gl $PJ $want; $b.milestone = O 'id' $m.id 'iid' $m.iid 'title' $m.title }
            return $b
        }
        $mid = $(if ($script:BOARD_MS.ContainsKey($lw)) { $script:BOARD_MS[$lw] } else { GL-_mid $gl $p $want })
        return , (GL-_api $gl 'PUT' ('/projects/' + (Enc $p) + "/boards/$id") (O 'milestone_id' $mid))
    })
}
function ListKey($l) { if ($l.label) { return [string]$l.label.name }; if ($l.status) { return "status:$($l.status.name)" }; return '' }
function GL-create_board_list($gl, $p, $id, $label) {
    return , (DryWrap $gl {
        if ($label -cmatch '^status:(.+)$') {
            $s = GL-_status_of $gl $p $matches[1]
            if (IsLocal $gl) {
                $b = GL-_board $gl (GL-_p $gl $p) $id
                if (First $b.lists { param($x) (ListKey $x) -ceq "status:$($s.name)" }) { throw "GitLab: board $($b.name) already has a list for status '$($s.name)' (400 Bad request)`n" }
                $x = O 'id' (GL-_id $gl) 'status' (O 'name' $s.name 'color' $s.color) 'position' (L $b.lists).Count
                Push $b 'lists' $x
                return $x
            }
            $d = GL-_gql $gl 'mutation($in: BoardListCreateInput!) { boardListCreate(input: $in) { list { id position } errors } }' (O 'in' (O 'boardId' "gid://gitlab/Board/$id" 'statusId' $s.id))
            $r = Dor $d.boardListCreate (NewH)
            if ((L $r.errors).Count) { throw "GitLab: boardListCreate: $((L $r.errors) -join ' ')`n" }
            $l = Dor $r.list (NewH)
            $lid = ([string](Dor $l.id 0)) -creplace '.*/', ''
            return , (O 'id' $lid 'status' (O 'name' $s.name) 'position' $l.position)
        }
        if (IsLocal $gl) {
            $PJ = GL-_p $gl $p
            $b = GL-_board $gl $PJ $id
            $l = First $PJ.labels { param($x) $x.name -ceq $label }
            if (-not $l) { throw "GitLab: no label '$label' in $($PJ.path_with_namespace) (add it to [labels])`n" }
            if (First $b.lists { param($x) (ListKey $x) -ceq $label }) { throw "GitLab: board $($b.name) already has a list for '$label' (400 Bad request)`n" }
            $x = O 'id' (GL-_id $gl) 'label' (O 'id' $l.id 'name' $l.name 'color' $l.color) 'position' (L $b.lists).Count
            Push $b 'lists' $x
            return $x
        }
        $lid = $(if ($gl.dry_run) { "{id of label $label}" } else {
            $l = First (GL-labels $gl $p) { param($x) $x.name -ceq $label }
            if (-not $l) { throw "GitLab: no label '$label' in $p (add it to [labels])`n" }; $l.id })
        return , (GL-_api $gl 'POST' ('/projects/' + (Enc $p) + "/boards/$id/lists") (O 'label_id' $lid))
    })
}
function GL-move_board_list($gl, $p, $id, $list, $pos) {
    return , (DryWrap $gl {
        if (IsLocal $gl) {
            $b = GL-_board $gl (GL-_p $gl $p) $id
            $ls = L $b.lists
            $i = -1; for ($k = 0; $k -lt $ls.Count; $k++) { if ([long]$ls[$k].id -eq [long]$list) { $i = $k; break } }
            if ($i -lt 0) { throw "GitLab: no list $list on board $($b.name) (404 Not found)`n" }
            $x = $ls[$i]
            $rest = @(); for ($k = 0; $k -lt $ls.Count; $k++) { if ($k -ne $i) { $rest += , $ls[$k] } }
            $pp = [int]$pos; if ($pp -gt $rest.Count) { $pp = $rest.Count }
            $new = @(); for ($k = 0; $k -lt $pp; $k++) { $new += , $rest[$k] }; $new += , $x; for ($k = $pp; $k -lt $rest.Count; $k++) { $new += , $rest[$k] }
            for ($k = 0; $k -lt $new.Count; $k++) { $new[$k].position = $k }
            $b.lists = $new
            return $x
        }
        return , (GL-_api $gl 'PUT' ('/projects/' + (Enc $p) + "/boards/$id/lists/$list") (O 'position' (PNum $pos)))
    })
}
function GL-board_status_lists($gl, $p) {
    if ((IsLocal $gl) -or $gl.dry_run) { return , (NewH) }
    $d = GL-_gql $gl 'query($p: ID!) { project(fullPath: $p) { boards { nodes { name lists { nodes { id position listType status { name } } } } } } }' (O 'p' $p)
    $r = NewH
    $nodes = HGet (HGet (HGet $d 'project') 'boards') 'nodes'
    foreach ($b in (L $nodes)) {
        foreach ($l in (L (HGet (HGet $b 'lists') 'nodes'))) {
            if ([string](Dor $l.listType '') -cne 'status' -or -not $l.status) { continue }
            $id = ([string](Dor $l.id 0)) -creplace '.*/', ''
            if ($null -eq $r[$b.name]) { $r[$b.name] = @() }
            $r[$b.name] = @($r[$b.name]) + , (O 'id' $id 'status' (O 'name' $l.status.name) 'position' $l.position)
        }
    }
    return $r
}
function ParseBoardLine([string]$v, [string]$where, $use) {
    $parts = @($v -split '\s*\|\s*')
    $ls = $parts[0]; $opt = @(); if ($parts.Count -gt 1) { $opt = $parts[1..($parts.Count - 1)] }
    if ($null -eq $ls) { $ls = '' }
    if ($ls -cmatch ',') { $labels = @(foreach ($x in ($ls -split ',')) { $y = $x.Trim(); if ($y.Length) { $y } }) }
    else { $labels = @(foreach ($x in ($ls.Trim() -split '\s+')) { if ($x.Length) { $x } }) }
    if ($labels.Count -eq 0) { throw "${where}: a board needs its lists: LABEL LABEL ... [| milestone=started]`n" }
    $o = NewH
    foreach ($x in $opt) {
        if ($x -cnotmatch '^\s*(\w[\w-]*)\s*=\s*(.*?)\s*$') { throw "${where}: board options are milestone=any|none|upcoming|started|TITLE, iteration=current|any|none or sprint=current, not '$x'`n" }
        $k = $matches[1]; $xv = $matches[2]
        if ($k -ceq 'milestone') { $o.milestone = $xv }
        elseif ($k -ceq 'iteration' -and $xv -cmatch '^(?i)(current|any|none)$') { $o.iteration = $xv.ToLowerInvariant() }
        elseif ($k -ceq 'sprint' -and $xv.ToLowerInvariant() -ceq 'current') { if ([string](Dor $use 'milestones') -ceq 'iterations') { $o.iteration = 'current' } else { $o.milestone = 'started' } }
        else { throw "${where}: board options are milestone=any|none|upcoming|started|TITLE, iteration=current|any|none or sprint=current, not '$x'`n" }
    }
    $ms = Dor $o.milestone 'any'
    if ($script:BOARD_MS.ContainsKey(([string]$ms).ToLowerInvariant())) { $ms = ([string]$ms).ToLowerInvariant() }
    return , (O 'labels' $labels 'milestone' $ms 'iteration' (Dor $o.iteration 'any'))
}
$script:BOARD_IT = NewH; $script:BOARD_IT['none'] = 0; $script:BOARD_IT['any'] = -1; $script:BOARD_IT['current'] = -4
$script:BOARD_IT_NAME = NewH; foreach ($k in @($script:BOARD_IT.Keys)) { $script:BOARD_IT_NAME[[string]$script:BOARD_IT[$k]] = $k }
function IterationScope($i) {
    if (-not ($i -is [hashtable]) -or ($null -eq $i.id -and $null -eq $i.title)) { return 'any' }
    if ([string](Dor $i.id '') -cmatch '(-?\d+)$') { $id = $matches[1]; if ($script:BOARD_IT_NAME.ContainsKey($id)) { return $script:BOARD_IT_NAME[$id] } }
    $t = ([string](Dor $i.title '')).ToLowerInvariant()
    if ($t -cmatch '^(current|any|none)$') { return $t }
    return , (Dor $i.title 'any')
}
function GL-board_iterations($gl, $p) {
    if (IsLocal $gl) { $r = NewH; foreach ($b in (L (GL-_p $gl $p).boards)) { $r[$b.name] = IterationScope $b.iteration }; return $r }
    if ($gl.dry_run) { return , (NewH) }
    $d = GL-_gql $gl 'query($p: ID!) { project(fullPath: $p) { boards { nodes { name iteration { id title } } } } }' (O 'p' $p)
    $r = NewH; foreach ($b in (L (HGet (HGet (HGet $d 'project') 'boards') 'nodes'))) { $r[$b.name] = IterationScope $b.iteration }
    return $r
}
function GL-update_board_iteration($gl, $p, $id, $want, $o) {
    if ($null -eq $o) { $o = NewH }
    return , (DryWrap $gl {
        if (-not $script:BOARD_IT.ContainsKey([string]$want)) { throw "GitLab: a board's iteration scope is current, any or none, not '$want'`n" }
        if (IsLocal $gl) {
            $b = GL-_board $gl (GL-_p $gl $p) $id
            if ($want -ceq 'any') { $b.iteration = $null } else { $b.iteration = O 'id' $script:BOARD_IT[$want] 'title' ($want.Substring(0, 1).ToUpperInvariant() + $want.Substring(1)) }
            return , (O 'iteration' $b.iteration)
        }
        $in = O 'id' "gid://gitlab/Board/$id" 'iterationId' "gid://gitlab/Iteration/$($script:BOARD_IT[$want])"
        if ($o.cadence) { $in.iterationCadenceId = $o.cadence }
        $d = GL-_gql $gl 'mutation($in: UpdateBoardInput!) { updateBoard(input: $in) { board { id iteration { id title } } errors } }' (O 'in' $in)
        $r = Dor $d.updateBoard (NewH)
        if ((L $r.errors).Count) { throw "GitLab: updateBoard: $((L $r.errors) -join ' ')`n" }
        return , (Dor $r.board (NewH))
    })
}
function GL-_setup_board($gl, $p, $name, $want, $o) {
    $log = @()
    $bo = $null
    if (-not ($gl.dry_run -and -not (IsLocal $gl))) { $bo = First (GL-boards $gl $p) { param($x) $x.name -ceq $name } }
    if (-not $bo) { $bo = GL-create_board $gl $p $name; $log += "board $name created" }
    $bid = Dor $bo.id 0
    if (-not (IsLocal $gl) -and -not $gl.dry_run -and $bo.id -and (First $want.labels { param($x) $x -cmatch '^status:' })) {
        $sl = $null; try { $sl = GL-board_status_lists $gl $p } catch { $sl = $null }; if ($null -eq $sl) { $sl = NewH }
        $bo.lists = (L $bo.lists) + (L $sl[$name])
    }
    $have = NewH; foreach ($l in (L $bo.lists)) { $have[(ListKey $l)] = $l }
    $srt = SortWith (Where-L $bo.lists { param($x) (ListKey $x).Length -gt 0 }) { param($x, $y) NumCmp (Dor $x.position 0) (Dor $y.position 0) }
    $order = @(foreach ($l in $srt) { ListKey $l })
    foreach ($l in (L $want.labels)) { if ($have.ContainsKey($l)) { continue }; $have[$l] = GL-create_board_list $gl $p $bid $l; $order += $l; $log += "board ${name}: list $l added" }
    $wl = L $want.labels
    for ($k = 0; $k -lt $wl.Count; $k++) {
        $l = $wl[$k]
        if ($k -lt $order.Count -and $order[$k] -ceq $l) { continue }
        $i = -1; for ($j = 0; $j -lt $order.Count; $j++) { if ($order[$j] -ceq $l) { $i = $j; break } }
        $item = $order[$i]
        $rest = @(); for ($j = 0; $j -lt $order.Count; $j++) { if ($j -ne $i) { $rest += $order[$j] } }
        $new = @(); for ($j = 0; $j -lt $k -and $j -lt $rest.Count; $j++) { $new += $rest[$j] }; $new += $item; for ($j = $k; $j -lt $rest.Count; $j++) { $new += $rest[$j] }
        $order = $new
        $null = GL-move_board_list $gl $p $bid (Dor $have[$l].id 0) $k; $log += "board ${name}: list $l moved to position $k"
    }
    $live = BoardScope $bo.milestone
    if ($live -cne $want.milestone) {
        $r = $null; $err = $null
        try { $r = GL-update_board $gl $p $bid (O 'milestone' $want.milestone) } catch { $err = [string]$_.Exception.Message }
        $got = $(if ($r -and -not $gl.dry_run) { BoardScope $r.milestone } else { $want.milestone })
        if ($got -cne $want.milestone) {
            $why = $(if ($err) { ($err -creplace '^GitLab: ', '') -replace "`n$", '' } else { 'the scope did not take' })
            GErr "GitLab: board ${name}: milestone scope '$($want.milestone)' not set ($why); scoped boards need Premium or Ultimate, the board shows every milestone`n"
            $log += "board ${name}: milestone scope not set (needs Premium or Ultimate)"
        } else { $log += "board ${name}: milestone $($want.milestone)" }
    }
    $wi = Dor $want.iteration 'any'
    $li = $(if ($bo.iteration -or -not $o.iterations) { IterationScope $bo.iteration } else { Dor $o.iterations[$name] 'any' })
    if ($wi -cne $li) {
        $r = $null; $err = $null
        try { $r = GL-update_board_iteration $gl $p $bid $wi (O 'cadence' $o.cadence) } catch { $err = [string]$_.Exception.Message }
        $got = $(if ($r -and -not $gl.dry_run) { IterationScope $r.iteration } else { $wi })
        if ($got -cne $wi) {
            $why = $(if ($err) { ($err -creplace '^GitLab: ', '') -replace "`n$", '' } else { 'the scope did not take' })
            GErr "GitLab: board ${name}: iteration scope '$wi' not set ($why); iterations need Premium or Ultimate and a cadence on the group`n"
            $log += "board ${name}: iteration scope not set (needs Premium or Ultimate and a cadence)"
        } else { $log += "board ${name}: iteration $wi" }
    }
    $log += "board $name ($((L $want.labels).Count) lists, milestone $($want.milestone)" + $(if ($wi -cne 'any') { ", iteration $wi" } else { '' }) + ')'
    return , $log
}

# ---------------------------------------------------------------- iterations (a cadence on the group)
function GL-_gql($gl, [string]$q, $v) {
    $one = $q -creplace '\s+', ' '
    if ($null -eq $v) { $v = NewH }
    $r = (GL-_api1 $gl 'POST' '/api/graphql' (O 'query' $one 'variables' $v) (NewH))[0]
    if ($gl.dry_run) { return , (NewH) }
    if ($r -is [hashtable] -and (L $r.errors).Count) { throw ("GitLab: GraphQL: " + ((@(foreach ($e in (L $r.errors)) { Dor $e.message (JsEnc $e) })) -join '; ') + "`n") }
    if ($r -is [hashtable]) { return , (Dor $r.data (NewH)) }
    return , (NewH)
}
$script:CAD_GQL = NewH
foreach ($kv in @(@('title', 'title'), @('start_date', 'startDate'), @('duration_in_weeks', 'durationInWeeks'), @('iterations_in_advance', 'iterationsInAdvance'),
                  @('automatic', 'automatic'), @('active', 'active'), @('roll_over', 'rollOver'), @('description', 'description'))) { $script:CAD_GQL[$kv[0]] = $kv[1] }
function CadFromGql($n) { $c = O 'id' $n.id; foreach ($k in @($script:CAD_GQL.Keys)) { $c[$k] = $n[$script:CAD_GQL[$k]] }; return $c }
function GL-cadences($gl, $g) {
    if (IsLocal $gl) {
        $GR = $gl.st.groups[$g]; if (-not $GR) { throw "GitLab: no group '$g' (404 Group Not Found)`n" }
        return , (Map-L $GR.cadences { param($x) Copy-H $x })
    }
    if ($gl.dry_run) { return , @() }
    $vals = SortStr @($script:CAD_GQL.Values)
    $d = GL-_gql $gl ('query($g: ID!) { group(fullPath: $g) { iterationCadences { nodes { id ' + ($vals -join ' ') + ' } } } }') (O 'g' $g)
    if (-not $d.group) { throw "GitLab: no group '$g' (or no access to it)`n" }
    $o = @(); foreach ($n in (L (HGet (HGet $d.group 'iterationCadences') 'nodes'))) { $c = CadFromGql $n; $sd = [string](Dor $c.start_date ''); if ($sd.Length -gt 10) { $sd = $sd.Substring(0, 10) }; $c.start_date = $sd; $o += , $c }
    return , $o
}
function CadIn($o) {
    $r = NewH
    foreach ($k in @($script:CAD_GQL.Keys)) {
        if ($null -eq $o[$k]) { continue }
        if ($k -cmatch '^(automatic|active|roll_over)$') { $r[$script:CAD_GQL[$k]] = [bool](Tru $o[$k]) }
        elseif ($k -cmatch 'weeks|advance') { $r[$script:CAD_GQL[$k]] = PNum $o[$k] }
        else { $r[$script:CAD_GQL[$k]] = $o[$k] }
    }
    return $r
}
function GL-create_cadence($gl, $g, $o) {
    return , (DryWrap $gl {
        $o = Copy-H $o
        if ($null -eq $o.active) { $o.active = 1 }; if ($null -eq $o.automatic) { $o.automatic = 1 }
        if (IsLocal $gl) {
            $GR = $gl.st.groups[$g]; if (-not $GR) { throw "GitLab: no group '$g' (404 Group Not Found)`n" }
            if ((GL-_glevel $gl $g) -lt 40) { throw "GitLab: you need Maintainer on group $g to manage its iteration cadences (403 Forbidden)`n" }
            $c = O 'id' ('gid://gitlab/Iterations::Cadence/' + (GL-_id $gl))
            foreach ($k in @($script:CAD_GQL.Keys)) { if ($o.ContainsKey($k)) { $c[$k] = $o[$k] } }
            foreach ($k in @('automatic', 'active', 'roll_over')) { $c[$k] = $(if (Tru $c[$k]) { 1 } else { 0 }) }
            Push $GR 'cadences' $c
            return , (Copy-H $c)
        }
        $in = CadIn $o; $in.groupPath = $g
        $d = GL-_gql $gl 'mutation($in: IterationCadenceCreateInput!) { iterationCadenceCreate(input: $in) { iterationCadence { id } errors } }' (O 'in' $in)
        $r = Dor $d.iterationCadenceCreate (NewH)
        if ((L $r.errors).Count) { throw "GitLab: iterationCadenceCreate: $((L $r.errors) -join ' ')`n" }
        $x = Copy-H $o; foreach ($k in @((Dor $r.iterationCadence (NewH)).Keys)) { $x[$k] = $r.iterationCadence[$k] }
        return $x
    })
}
function GL-update_cadence($gl, $g, $id, $o) {
    return , (DryWrap $gl {
        if (IsLocal $gl) {
            if ((GL-_glevel $gl $g) -lt 40) { throw "GitLab: you need Maintainer on group $g to manage its iteration cadences (403 Forbidden)`n" }
            $c = First (HGet $gl.st.groups[$g] 'cadences') { param($x) [string]$x.id -ceq [string]$id }
            if (-not $c) { throw "GitLab: no iteration cadence $id in $g`n" }
            foreach ($k in @($script:CAD_GQL.Keys)) { if ($o.ContainsKey($k)) { if ($k -cmatch '^(automatic|active|roll_over)$') { $c[$k] = $(if (Tru $o[$k]) { 1 } else { 0 }) } else { $c[$k] = $o[$k] } } }
            return , (Copy-H $c)
        }
        $in = CadIn $o; $in.id = $id
        $d = GL-_gql $gl 'mutation($in: IterationCadenceUpdateInput!) { iterationCadenceUpdate(input: $in) { iterationCadence { id } errors } }' (O 'in' $in)
        $r = Dor $d.iterationCadenceUpdate (NewH)
        if ((L $r.errors).Count) { throw "GitLab: iterationCadenceUpdate: $((L $r.errors) -join ' ')`n" }
        $x = Copy-H $o; $x.id = $id
        return $x
    })
}
function GL-_glevel($gl, $g) {
    if ((HGet $gl.st.users[$gl.as] 'admin')) { return 60 }
    $l = 0; $ns = [string]$g
    while ($ns.Length) {
        $x = Dor (HGet (HGet $gl.st.groups[$ns] 'members') $gl.as) 0
        if ($x -gt $l) { $l = $x }
        $ns = $ns -creplace '/?[^/]*$', ''
    }
    return $l
}
$script:IT_STATE = NewH; $script:IT_STATE['1'] = 'upcoming'; $script:IT_STATE['2'] = 'current'; $script:IT_STATE['3'] = 'closed'; $script:IT_STATE['4'] = 'closed'
function GL-iterations($gl, $g) {
    if (IsLocal $gl) {
        $GR = $gl.st.groups[$g]; if (-not $GR) { throw "GitLab: no group '$g' (404 Group Not Found)`n" }
        $today = DateT (GL-epoch $gl)
        $it = @()
        foreach ($c in (L $GR.cadences)) {
            if (-not ((Tru $c.automatic) -and (Tru $c.active))) { continue }
            $t0 = Epoch $c.start_date; $w = PNum $c.duration_in_weeks; if (-not $w) { $w = 2 }; $ahead = 0
            for ($k = 1; $k -le 500; $k++) {
                $s = $t0 + ($k - 1) * $w * 7 * 86400; $e = $s + ($w * 7 - 1) * 86400
                $st = $(if ((OrdCmp (DateT $e) $today) -lt 0) { 'closed' } elseif ((OrdCmp (DateT $s) $today) -gt 0) { 'upcoming' } else { 'current' })
                if ($st -ceq 'upcoming') { $ahead++; if ($ahead -gt (PNum (Dor $c.iterations_in_advance 1))) { break } }
                $cid = ([string]$c.id) -creplace '.*/', ''
                $it += , (O 'id' "gid://gitlab/Iteration/$cid$k" 'sequence' $k 'title' $null 'state' $st 'start_date' (DateT $s) 'due_date' (DateT $e) 'cadence' $c.title)
            }
        }
        return , $it
    }
    if ($gl.dry_run) { return , @() }
    $r = GL-_api $gl 'GET' ('/groups/' + (Enc $g) + '/iterations') $null (O 'query' (O 'state' 'all' 'include_ancestors' 'true') 'all' 1)
    return , (Map-L $r { param($x) $c = Copy-H $x; $s = [string]$x.state; if ($script:IT_STATE.ContainsKey($s)) { $c.state = $script:IT_STATE[$s] }; $c })
}
function ParseIterations($lines, [string]$where, $project) {
    $r = O 'group' $null 'use' 'milestones' 'cadences' @()
    foreach ($x in (L $lines)) {
        $k = $x[0]; $v = $x[1]; $n = $x[2]
        if ($k -ceq 'group') { $r.group = $v; continue }
        if ($k -ceq 'use') { if ($v -cnotmatch '^(milestones|iterations)$') { throw "${where}:${n}: [iterations] use is milestones or iterations, not '$v'`n" }; $r.use = $v; continue }
        $sp = @($v -split '\s*\|\s*', 2); $when = $sp[0]; $flags = $(if ($sp.Count -gt 1) { $sp[1] } else { $null })
        $w = @(([string]$when).Trim() -split '\s+' | Where-Object { $_ -cne '' })
        $start = $w[0]; $weeks = $(if ($w.Count -gt 1) { $w[1] } else { $null }); $ahead = $(if ($w.Count -gt 2) { $w[2] } else { $null })
        if (-not ($null -ne $weeks -and $start -cmatch '^\d{4}-\d\d-\d\d$' -and $weeks -cmatch '^\d+$' -and [int]$weeks -ge 1 -and [int]$weeks -le 4 -and ($null -eq $ahead -or $ahead -cmatch '^\d+$'))) {
            throw "${where}:${n}: a cadence is TITLE = START WEEKS [IN_ADVANCE] [| automatic roll-over manual] (START a date, WEEKS 1 to 4)`n"
        }
        $f = NewH; foreach ($y in (@(([string](Dor $flags '')).Trim() -split '\s+') | Where-Object { $_ -cne '' })) { $f[$y.ToLowerInvariant()] = 1 }
        foreach ($y in @($f.Keys)) { if ($y -cnotmatch '^(automatic|manual|roll-over)$') { throw "${where}:${n}: cadence flags are automatic, manual and roll-over, not '$y'`n" } }
        Push $r 'cadences' (O 'title' $k 'start_date' $start 'duration_in_weeks' (PNum $weeks) 'iterations_in_advance' (PNum (Dor $ahead 4)) 'automatic' $(if ($f['manual']) { 0 } else { 1 }) 'roll_over' $(if ($f['roll-over']) { 1 } else { 0 }) 'line' $n)
    }
    if ($null -eq $r.group) { if ([string](Dor $project '') -cmatch '^(.*)/') { $r.group = $matches[1] } }
    return $r
}
function GL-_setup_iterations($gl, $it) {
    $log = @(); $by = NewH
    if ((L $it.cadences).Count -eq 0) { return , @($log, $by) }
    $g = $it.group; if ($null -eq $g) { throw "GitLab: [iterations] needs group = PATH (the group the cadence lives on)`n" }
    $live = NewH; foreach ($c in (GL-cadences $gl $g)) { $live[[string]$c.title] = $c }
    foreach ($c in (L $it.cadences)) {
        $want = NewH; foreach ($k in @('title', 'start_date', 'duration_in_weeks', 'iterations_in_advance', 'automatic', 'roll_over')) { $want[$k] = $c[$k] }
        $l = $live[[string]$c.title]
        if (-not $l) { $w2 = Copy-H $want; $w2.active = 1; $by[$c.title] = GL-create_cadence $gl $g $w2; $log += "iteration cadence $($c.title) on $g ($($c.duration_in_weeks) weeks from $($c.start_date))"; continue }
        $ch = NewH
        foreach ($k in @($want.Keys)) {
            $differs = (PStr (Dor $l[$k] '')) -cne (PStr (Dor $want[$k] ''))
            $boolsame = ($k -cmatch '^(automatic|roll_over)$') -and ($(if (Tru $l[$k]) { 1 } else { 0 }) -eq $want[$k])
            if ($differs -and -not $boolsame) { $ch[$k] = $want[$k] }
        }
        if ($ch.Count) { $by[$c.title] = GL-update_cadence $gl $g $l.id $ch } else { $by[$c.title] = $l }
        if ($ch.Count) { $log += "iteration cadence $($c.title) on $g updated (" + ((SortStr @($ch.Keys)) -join ', ') + ')' } else { $log += "iteration cadence $($c.title) on $g" }
    }
    return , @($log, $by)
}

# ---------------------------------------------------------------- work-item statuses
$script:STATUS_CATEGORIES = @('triage', 'to_do', 'in_progress', 'done', 'canceled')
$script:DEFAULT_LIFECYCLE = @(@('To do', '#737278', 'to_do'), @('In progress', '#1f75cb', 'in_progress'), @('Done', '#108548', 'done'),
    @("Won't do", '#dd2b0e', 'canceled'), @('Duplicate', '#dd2b0e', 'canceled'))
function TopGroup($p) { if ([string](Dor $p '') -cmatch '^([^/]+)') { return $matches[1] }; return $null }
function ParseStatuses($lines, [string]$where, $project) {
    $r = O 'group' $null 'mode' 'statuses' 'statuses' @() 'marks' @() 'mark_color' '#6b7436'
    foreach ($x in (L $lines)) {
        $k = $x[0]; $v = $x[1]; $n = $x[2]
        if ($k -ceq 'group') { $r.group = $v; continue }
        if ($k -ceq 'mode') { if ($v -cnotmatch '^(statuses|labels)$') { throw "${where}:${n}: [statuses] mode is statuses or labels, not '$v'`n" }; $r.mode = $v; continue }
        if ($k -ceq 'marks') {
            $w = @(([string]$v).Trim() -split '\s+' | Where-Object { $_ -cne '' })
            $c = $(if ($w.Count) { $w[0] } else { $null }); $m = @(); if ($w.Count -gt 1) { $m = $w[1..($w.Count - 1)] }
            if ([string](Dor $c '') -cnotmatch '^#[0-9A-Fa-f]{6}$') { if ($null -ne $c) { $m = @($c) + $m }; $c = $r.mark_color }
            $r.mark_color = $c; $r.marks = @(foreach ($y in $m) { $y.ToUpperInvariant() }); continue
        }
        $f = @(([string]$v) -split '\|', 4 | ForEach-Object { $_.Trim() })
        $color = $(if ($f.Count -gt 0) { $f[0] }); $cat = $(if ($f.Count -gt 1) { $f[1] }); $desc = $(if ($f.Count -gt 2) { $f[2] }); $def = $(if ($f.Count -gt 3) { $f[3] })
        if (-not ([string](Dor $color '') -cmatch '^#[0-9A-Fa-f]{6}$' -and $script:STATUS_CATEGORIES -contains ([string](Dor $cat '')).ToLowerInvariant())) {
            throw "${where}:${n}: a status is NAME = #RRGGBB | CATEGORY | description [| default-open|default-closed|default-duplicate] (CATEGORY: $($script:STATUS_CATEGORIES -join ' '))`n"
        }
        $d = NewH; foreach ($y in (@(([string](Dor $def '')) -split '[\s,]+') | Where-Object { $_ -cne '' })) { $d[$y.ToLowerInvariant()] = 1 }
        foreach ($y in @($d.Keys)) { if ($y -cnotmatch '^default-(open|closed|duplicate)$') { throw "${where}:${n}: a status's last field is default-open, default-closed or default-duplicate, not '$y'`n" } }
        Push $r 'statuses' (O 'name' $k 'color' $color.ToLowerInvariant() 'category' $cat.ToLowerInvariant() 'description' (Dor $desc '') 'default' (Map-L (SortStr @($d.Keys)) { param($y) $y -creplace '^default-', '' }) 'line' $n)
    }
    if ((L $r.statuses).Count) {
        foreach ($kind in @('open', 'closed', 'duplicate')) {
            $dd = Where-L $r.statuses { param($s) (L $s.default) -contains $kind }
            if ($dd.Count -gt 1) { throw "${where}: [statuses] names more than one default-$kind status`n" }
        }
        $pref = O 'open' @('to_do', 'triage') 'closed' @('done') 'duplicate' @('canceled', 'done')
        foreach ($kind in @('open', 'closed', 'duplicate')) {
            if (First $r.statuses { param($s) (L $s.default) -contains $kind }) { continue }
            $s = $null
            foreach ($c in $pref[$kind]) { $s = First $r.statuses { param($x) $x.category -ceq $c }; if ($s) { break } }
            if (-not $s) { throw "${where}: [statuses] needs a status for default-$kind (a $($pref[$kind][0]) status)`n" }
            $s.default = (L $s.default) + $kind
        }
    }
    if ($null -eq $r.group) { $r.group = TopGroup $project }
    return $r
}
function StatusDefault($ss, $kind) { $s = First $ss { param($x) (L $x.default) -contains $kind }; if ($s) { return $s.name }; return $null }
function GL-lifecycle($gl, $g) {
    $g = TopGroup $g
    if (IsLocal $gl) {
        $GR = $gl.st.groups[$g]; if (-not $GR) { throw "GitLab: no group '$g' (404 Group Not Found)`n" }
        if ($null -eq $GR.lifecycle) {
            $sts = @(); for ($i = 0; $i -lt $script:DEFAULT_LIFECYCLE.Count; $i++) { $d = $script:DEFAULT_LIFECYCLE[$i]; $sts += , (O 'id' ('gid://gitlab/WorkItems::Statuses::SystemDefined::Status/' + ($i + 1)) 'name' $d[0] 'color' $d[1] 'category' $d[2] 'description' '') }
            $GR.lifecycle = O 'id' 'gid://gitlab/WorkItems::Statuses::SystemDefined::Lifecycle/1' 'name' 'Default' 'statuses' $sts 'default_open' 'To do' 'default_closed' 'Done' 'default_duplicate' 'Duplicate'
        }
        return $GR.lifecycle
    }
    if ($gl.dry_run) { return , (O 'id' '{lifecycle id}' 'name' 'Default' 'statuses' @()) }
    $d = GL-_gql $gl ('query($p: ID!) { namespace(fullPath: $p) { lifecycles { nodes { id name workItemTypes { name } ' + 'defaultOpenStatus { name } defaultClosedStatus { name } defaultDuplicateStatus { name } statuses { id name color category description } } } } }') (O 'p' $g)
    $n = L (HGet (HGet (HGet $d 'namespace') 'lifecycles') 'nodes')
    $l = First $n { param($x) First $x.workItemTypes { param($t) [string](Dor $t.name '') -ceq 'Issue' } }
    if (-not $l -and $n.Count) { $l = $n[0] }
    if (-not $l) { throw "GitLab: no work-item lifecycle on ${g}: statuses need GitLab 18.2 or later, Premium or Ultimate, on the top-level group (else [statuses] mode = labels)`n" }
    return , (O 'id' $l.id 'name' $l.name 'statuses' (Map-L $l.statuses { param($s) $c = Copy-H $s; $c.category = ([string](Dor $s.category '')).ToLowerInvariant(); $c }) `
            'default_open' (HGet $l.defaultOpenStatus 'name') 'default_closed' (HGet $l.defaultClosedStatus 'name') 'default_duplicate' (HGet $l.defaultDuplicateStatus 'name'))
}
function GL-set_lifecycle($gl, $g, $want, $o) {
    return , (DryWrap $gl {
        $g = TopGroup $g
        $have = GL-lifecycle $gl $g
        $old = NewH; foreach ($s in (L $have.statuses)) { $old[$s.name] = $s }
        $named = NewH; foreach ($s in (L $want)) { $named[$s.name] = 1 }
        $all = @()
        foreach ($s in (L $want)) { $x = Copy-H (Dor $old[$s.name] (NewH)); $x.name = $s.name; $x.color = $s.color; $x.category = $s.category; $x.description = Dor $s.description ''; $all += , $x }
        foreach ($s in (L $have.statuses)) { if (-not $named.ContainsKey($s.name)) { $all += , $s } }
        if ($all.Count -gt 30) { throw "GitLab: a lifecycle holds at most 30 statuses (this one would have $($all.Count))`n" }
        $ix = NewH; for ($i = 0; $i -lt $all.Count; $i++) { $ix[$all[$i].name] = $i }
        foreach ($k in @('open', 'closed', 'duplicate')) { if ($null -eq $o[$k] -or -not $ix.ContainsKey([string]$o[$k])) { throw "GitLab: set_lifecycle needs $k => a status name`n" } }
        if (IsLocal $gl) {
            $GR = $gl.st.groups[$g]
            foreach ($s in $all) { if ($null -eq $s.id) { $s.id = 'gid://gitlab/WorkItems::Statuses::Custom::Status/' + (GL-_id $gl) } }
            $lid = $(if ([string]$have.id -cmatch 'Custom') { $have.id } else { 'gid://gitlab/WorkItems::Statuses::Custom::Lifecycle/' + (GL-_id $gl) })
            $GR.lifecycle = O 'id' $lid 'name' $have.name 'statuses' (Map-L $all { param($s) Copy-H $s }) 'default_open' $o.open 'default_closed' $o.closed 'default_duplicate' $o.duplicate
            return $GR.lifecycle
        }
        $sts = Map-L $all { param($s) $x = NewH; if ($null -ne $s.id) { $x.id = $s.id }; $x.name = $s.name; $x.color = $s.color; $x.category = ([string]$s.category).ToUpperInvariant(); $x.description = Dor $s.description ''; $x }
        $d = GL-_gql $gl 'mutation($in: LifecycleUpdateInput!) { lifecycleUpdate(input: $in) { lifecycle { id name statuses { id name color category description } } errors } }' `
            (O 'in' (O 'namespacePath' $g 'id' $have.id 'statuses' $sts 'defaultOpenStatusIndex' $ix[[string]$o.open] 'defaultClosedStatusIndex' $ix[[string]$o.closed] 'defaultDuplicateStatusIndex' $ix[[string]$o.duplicate]))
        $r = Dor $d.lifecycleUpdate (NewH)
        if ((L $r.errors).Count) { throw "GitLab: lifecycleUpdate: $((L $r.errors) -join ' ')`n" }
        return , (Dor $r.lifecycle (NewH))
    })
}
function GL-_status_of($gl, $g, $name) {
    $l = GL-lifecycle $gl $g
    $s = First $l.statuses { param($x) ([string]$x.name).ToLowerInvariant() -ceq ([string]$name).ToLowerInvariant() }
    if ($s) { return $s }
    if ($gl.dry_run -and -not (IsLocal $gl)) { return , (O 'id' "{id of status $name}" 'name' $name) }
    throw ("GitLab: no status '$name' on " + (TopGroup $g) + " (statuses: " + ((@(foreach ($x in (L $l.statuses)) { $x.name })) -join ', ') + ")`n")
}
function GL-set_item_status($gl, $p, $iid, $name, $o) {
    if ($null -eq $o) { $o = NewH }
    return , (DryWrap $gl {
        if ([string](Dor $o.mode 'statuses') -ceq 'labels') {
            $i = GL-update_issue $gl $p $iid (O 'add_labels' "state::$name")
            $closing = $(if ($null -ne $o.closing) { Tru $o.closing } else { $name -cmatch '^(?i)(DONE|DROP)$' })
            $st = $(if ($gl.dry_run) { '' } else { [string](Dor (GL-issue $gl $p $iid).state '') })
            if ($closing -and $st -cne 'closed') { return , (GL-update_issue $gl $p $iid (O 'state_event' 'close')) }
            if (-not $closing -and $st -ceq 'closed') { return , (GL-update_issue $gl $p $iid (O 'state_event' 'reopen')) }
            return $i
        }
        $s = GL-_status_of $gl $p $name
        if (IsLocal $gl) {
            $i = GL-_issue $gl (GL-_p $gl $p) $iid
            $was = HGet $i.status 'name'
            $i.status = O 'name' $s.name 'category' $s.category 'color' $s.color
            if ([string](Dor $was '') -cne $s.name) { GL-_sysnote $gl $i "set status to **$($s.name)**" }
            if ($s.category -cmatch '^(done|canceled)$') { if ($i.state -cne 'closed') { GL-_close $gl $i $null } }
            elseif ($i.state -ceq 'closed') { $i.state = 'opened'; $i.closed_at = $null; GL-_sysnote $gl $i 'reopened' }
            $i.updated_at = GL-now $gl
            return $i
        }
        $gid = Dor $o.gid $(if ($gl.dry_run) { "gid://gitlab/WorkItem/{id of #$iid}" } else { 'gid://gitlab/WorkItem/' + (GL-issue $gl $p $iid).id })
        $d = GL-_gql $gl 'mutation($in: WorkItemUpdateInput!) { workItemUpdate(input: $in) { workItem { id state } errors } }' (O 'in' (O 'id' $gid 'statusWidget' (O 'status' $s.id)))
        $r = Dor $d.workItemUpdate (NewH)
        if ((L $r.errors).Count) { throw "GitLab: workItemUpdate: $((L $r.errors) -join ' ')`n" }
        return , (Dor $r.workItem (NewH))
    })
}
function ItemStatus($i) {
    if ($i.status -is [hashtable] -and $null -ne $i.status.name) { return $i.status.name }
    foreach ($l in (L $i.labels)) { $n = $(if ($l -is [hashtable]) { Dor $l.name $l.title } else { $l }); if ([string]$n -cmatch '^state::') { return , ([string]$n).Substring(7) } }
    return $null
}
function GL-_setup_statuses($gl, $p, $st) {
    $log = @()
    if ($st.mode -ceq 'labels') {
        foreach ($s in (L $st.statuses)) { $null = GL-create_label $gl $p "state::$($s.name)" $s.color $s.description; $log += "label state::$($s.name)" }
    } elseif ((L $st.statuses).Count) {
        $g = $st.group
        if ((IsLocal $gl) -and -not $gl.st.groups[$g]) { $null = GL-create_group $gl $g (NewH) }
        $r = $null; $err = $null
        try { $r = GL-set_lifecycle $gl $g $st.statuses (O 'open' (StatusDefault $st.statuses 'open') 'closed' (StatusDefault $st.statuses 'closed') 'duplicate' (StatusDefault $st.statuses 'duplicate')) } catch { $err = [string]$_.Exception.Message }
        if (-not $r) {
            $why = ($err -creplace '^GitLab: ', '') -replace "`n$", ''
            GErr "GitLab: statuses not set on $g ($why); they need GitLab 18.2+, Premium or Ultimate, the top-level group and Maintainer on it ([statuses] mode = labels is the fallback)`n"
            $log += "statuses not set on $g (needs GitLab 18.2+, Premium or Ultimate)"
        } else {
            foreach ($s in (L $st.statuses)) { $log += "status $($s.name) ($($s.category)" + $(if ((L $s.default).Count) { ', default ' + ((L $s.default) -join '/') } else { '' }) + ") on $g" }
        }
    }
    $MD = O 'REDO' 'Mark: the demo showed it was wrong, back in this sprint' 'PASS' 'Mark: handed to another team' 'SYNC' 'Mark: coordinated across teams, with a shared DONE'
    foreach ($m in (L $st.marks)) { $null = GL-create_label $gl $p $m $st.mark_color (Dor $MD[$m] "Mark: $m (shown beside the state)"); $log += "label $m (mark)" }
    return , $log
}

# ---------------------------------------------------------------- work items: epics on the group, tasks under issues
function WiGid($id) { if ([string]$id -cmatch '^gid:') { return [string]$id }; return "gid://gitlab/WorkItem/$id" }
function GL-_wi_type_id($gl, $ns, $type, $kind) {
    if ($gl.dry_run) { return "{id of type $type}" }
    $key = "$ns`0$type"
    if ($null -eq $gl.wit[$key]) {
        $f = $(if ($kind -ceq 'group') { 'group' } else { 'project' })
        $d = GL-_gql $gl "query(`$p: ID!) { $f(fullPath: `$p) { workItemTypes { nodes { id name } } } }" (O 'p' $ns)
        $t = First (HGet (HGet (HGet $d $f) 'workItemTypes') 'nodes') { param($x) ([string]$x.name).ToLowerInvariant() -ceq ([string]$type).ToLowerInvariant() }
        if (-not $t) { throw ("GitLab: no work item type '$type' in $ns" + $(if ($type -ceq 'Epic') { ' (epics need Premium or Ultimate, on a group)' } else { '' }) + "`n") }
        $gl.wit[$key] = $t.id
    }
    return $gl.wit[$key]
}
$script:WI_FIELDS = 'id iid title state webUrl createdAt closedAt workItemType { name } widgets { __typename ' +
    '... on WorkItemWidgetDescription { description } ... on WorkItemWidgetHierarchy { parent { id } } ' +
    '... on WorkItemWidgetStartAndDueDate { startDate dueDate } ... on WorkItemWidgetWeight { weight } ' +
    '... on WorkItemWidgetTimeTracking { timeEstimate totalTimeSpent } ... on WorkItemWidgetLabels { labels { nodes { title } } } ' +
    '... on WorkItemWidgetMilestone { milestone { title } } ... on WorkItemWidgetIteration { iteration { title startDate } } ' +
    '... on WorkItemWidgetAssignees { assignees { nodes { username } } } STATUS }'
function UcFirst([string]$s) { if ($s.Length -eq 0) { return $s }; return $s.Substring(0, 1).ToUpperInvariant() + $s.Substring(1) }
function GL-work_items($gl, $ns, $o) {
    if ($null -eq $o) { $o = NewH }
    $kind = Dor $o.kind 'project'
    $want = NewH
    $types = $(if ($null -ne $o.types) { L $o.types } elseif ($kind -ceq 'group') { @('Epic') } else { @('Issue', 'Task') })
    foreach ($t in $types) { $want[([string]$t).ToLowerInvariant()] = 1 }
    if (IsLocal $gl) {
        $it = @()
        if ($kind -ceq 'group') { $GR = $gl.st.groups[$ns]; if (-not $GR) { throw "GitLab: no group '$ns' (404 Group Not Found)`n" }; $it = Map-L $GR.work_items { param($x) Copy-H $x } }
        else {
            foreach ($i in (L (GL-_p $gl $ns).issues)) {
                $it += , (O 'id' (WiGid $i.id) 'iid' $i.iid 'type' (UcFirst ([string](Dor $i.issue_type 'issue'))) 'title' $i.title 'state' $i.state `
                    'description' $i.description 'parent' (HGet $i.parent 'id') 'status' (ItemStatus $i) 'weight' $i.weight `
                    'estimate' (Dor (HGet $i.time_stats 'time_estimate') 0) 'spent' (Dor (HGet $i.time_stats 'total_time_spent') 0) `
                    'start_date' $null 'due_date' $i.due_date 'labels' (Map-L $i.labels { param($l) if ($l -is [hashtable]) { $l.name } else { $l } }) `
                    'milestone' (HGet $i.milestone 'title') 'iteration' $null 'assignees' (Map-L $i.assignees { param($a) $a.username }) 'web_url' $i.web_url)
            }
        }
        return , (Where-L $it { param($x) $want.ContainsKey(([string]$x.type).ToLowerInvariant()) })
    }
    if ($gl.dry_run) { return , @() }
    $f = $(if ($kind -ceq 'group') { 'group' } else { 'project' })
    $tl = (SortStr @(foreach ($k in @($want.Keys)) { $k.ToUpperInvariant() })) -join ', '
    foreach ($status in @('... on WorkItemWidgetStatus { status { name } }', '')) {
        $fields = $script:WI_FIELDS.Replace('STATUS', $status)
        $out = @(); $after = $null
        $ok = $true; $err = $null
        try {
            while ($true) {
                $d = GL-_gql $gl "query(`$p: ID!, `$after: String) { $f(fullPath: `$p) { workItems(first: 100, after: `$after, types: [$tl]) { pageInfo { hasNextPage endCursor } nodes { $fields } } } }" (O 'p' $ns 'after' $after)
                $w = Dor (HGet (HGet $d $f) 'workItems') (NewH)
                $out += (L $w.nodes)
                if (-not (Tru (HGet $w.pageInfo 'hasNextPage'))) { break }
                $after = $w.pageInfo.endCursor
            }
        } catch { $ok = $false; $err = [string]$_.Exception.Message }
        if (-not $ok) { if (-not ($status -and $err -cmatch 'WorkItemWidgetStatus')) { throw $err }; continue }
        $res = @()
        foreach ($n in $out) {
            $w = NewH; foreach ($x in (L $n.widgets)) { $w[[string](Dor $x.__typename '')] = $x }
            $res += , (O 'id' $n.id 'iid' $n.iid 'type' (HGet $n.workItemType 'name') 'title' $n.title 'state' $(if (([string](Dor $n.state '')).ToLowerInvariant() -ceq 'closed') { 'closed' } else { 'opened' }) `
                'description' (HGet $w['WorkItemWidgetDescription'] 'description') 'parent' (HGet (HGet $w['WorkItemWidgetHierarchy'] 'parent') 'id') `
                'status' (HGet (HGet $w['WorkItemWidgetStatus'] 'status') 'name') 'weight' (HGet $w['WorkItemWidgetWeight'] 'weight') `
                'estimate' (Dor (HGet $w['WorkItemWidgetTimeTracking'] 'timeEstimate') 0) 'spent' (Dor (HGet $w['WorkItemWidgetTimeTracking'] 'totalTimeSpent') 0) `
                'start_date' (HGet $w['WorkItemWidgetStartAndDueDate'] 'startDate') 'due_date' (HGet $w['WorkItemWidgetStartAndDueDate'] 'dueDate') `
                'labels' (Map-L (HGet (HGet $w['WorkItemWidgetLabels'] 'labels') 'nodes') { param($x) $x.title }) `
                'milestone' (HGet (HGet $w['WorkItemWidgetMilestone'] 'milestone') 'title') 'iteration' (HGet (HGet $w['WorkItemWidgetIteration'] 'iteration') 'startDate') `
                'assignees' (Map-L (HGet (HGet $w['WorkItemWidgetAssignees'] 'assignees') 'nodes') { param($x) $x.username }) 'web_url' $n.webUrl)
        }
        return , $res
    }
    return , @()
}
function GL-create_work_item($gl, $ns, $o) {
    return , (DryWrap $gl {
        $kind = Dor $o.kind 'project'
        $type = $o.type; if ($null -eq $type) { throw "GitLab: create_work_item needs type => Epic or Task`n" }
        if ([string](Dor $o.title '') -ceq '') { throw "GitLab: a work item needs a title`n" }
        if (IsLocal $gl) {
            if ($kind -ceq 'group') {
                $GR = $gl.st.groups[$ns]; if (-not $GR) { throw "GitLab: no group '$ns' (404 Group Not Found)`n" }
                if ($null -eq $GR.iids) { $GR.iids = NewH }
                $GR.iids.epic = [long](Dor $GR.iids.epic 0) + 1; $iid = $GR.iids.epic
                $id = GL-_id $gl
                $w = O 'id' (WiGid $id) 'iid' $iid 'type' $type 'title' $o.title 'state' 'opened' 'description' (Dor $o.description '') `
                    'parent' $o.parent 'status' $null 'start_date' $o.start_date 'due_date' $o.due_date 'labels' @() 'web_url' "$($gl.base)/groups/$ns/-/epics/$iid" 'created_at' (GL-now $gl)
                Push $GR 'work_items' $w
                return $w
            }
            $i = GL-_create_issue $gl $ns (O 'title' $o.title 'description' $o.description 'issue_type' ([string]$type).ToLowerInvariant() 'due_date' $o.due_date)
            $i.time_stats.time_estimate = PNum (Dor $o.estimate 0)
            if ($o.parent) { $null = GL-set_work_item_parent $gl $ns (WiGid $i.id) $o.parent }
            return , (O 'id' (WiGid $i.id) 'iid' $i.iid 'web_url' $i.web_url)
        }
        $in = O 'namespacePath' $ns 'title' $o.title 'workItemTypeId' (GL-_wi_type_id $gl $ns $type $kind)
        if ($null -ne $o.description) { $in.descriptionWidget = O 'description' $o.description }
        if ($o.parent) { $in.hierarchyWidget = O 'parentId' $o.parent }
        if ($o.start_date -or $o.due_date) { $in.startAndDueDateWidget = O 'isFixed' $true 'startDate' $o.start_date 'dueDate' $o.due_date }
        if (Tru $o.estimate) { $in.timeTrackingWidget = O 'timeEstimate' (GlTime $o.estimate) }
        $d = GL-_gql $gl 'mutation($in: WorkItemCreateInput!) { workItemCreate(input: $in) { workItem { id iid webUrl } errors } }' (O 'in' $in)
        $r = Dor $d.workItemCreate (NewH)
        if ((L $r.errors).Count) { throw "GitLab: workItemCreate: $((L $r.errors) -join ' ')`n" }
        $w = Dor $r.workItem (O 'id' 'gid://gitlab/WorkItem/0' 'iid' 0)
        return , (O 'id' $w.id 'iid' $w.iid 'web_url' $w.webUrl)
    })
}
function GlTime($s) { $s = PNum (Dor $s 0); $d = $s / 28800; if ($d -eq (Trunc $d)) { return "$(Trunc $d)d" }; return , ('{0}h' -f (Trunc ($s / 3600 + 0.5))) }
function GL-set_work_item_parent($gl, $ns, $child, $parent) {
    return , (DryWrap $gl {
        if (IsLocal $gl) {
            $cid = $null; if ([string]$child -cmatch '(\d+)$') { $cid = [long]$matches[1] }
            $PJ = $gl.st.projects[$ns]
            $i = $(if ($PJ) { First $PJ.issues { param($x) [long]$x.id -eq $cid } } else { $null })
            $par = GL-_local_work_item $gl $parent
            if (-not $par) { throw "GitLab: no work item $parent (404 Not found)`n" }
            if ($i) { $i.parent = O 'id' $par.id 'title' $par.title 'type' $par.type; return $i }
            $w = GL-_local_work_item $gl $child
            if (-not $w) { throw "GitLab: no work item $child (404 Not found)`n" }
            $w.parent = $par.id
            return $w
        }
        $d = GL-_gql $gl 'mutation($in: WorkItemUpdateInput!) { workItemUpdate(input: $in) { workItem { id } errors } }' (O 'in' (O 'id' (WiGid $child) 'hierarchyWidget' (O 'parentId' (WiGid $parent))))
        $r = Dor $d.workItemUpdate (NewH)
        if ((L $r.errors).Count) { throw "GitLab: workItemUpdate: $((L $r.errors) -join ' ')`n" }
        return , (Dor $r.workItem (NewH))
    })
}
function GL-_local_work_item($gl, $gid) {
    if ($null -eq $gid) { return $null }
    foreach ($GR in @($gl.st.groups.Values)) { foreach ($w in (L $GR.work_items)) { if ([string]$w.id -ceq [string]$gid) { return $w } } }
    $n = $null; if ([string]$gid -cmatch '(\d+)$') { $n = [long]$matches[1] }
    foreach ($PJ in @($gl.st.projects.Values)) { foreach ($i in (L $PJ.issues)) { if ([long]$i.id -eq $n) { return , (O 'id' (WiGid $i.id) 'title' $i.title 'type' (UcFirst ([string](Dor $i.issue_type 'issue')))) } } }
    return $null
}
function GL-set_epic_status($gl, $g, $gid, $name, $o) {
    if ($null -eq $o) { $o = NewH }
    return , (DryWrap $gl {
        if ([string](Dor $o.mode '') -ceq 'close') {
            if ($name -cnotmatch '^(?i)(DONE|DROP)$') { return , (NewH) }
            if (IsLocal $gl) { $w = GL-_local_work_item $gl $gid; if (-not $w) { throw "GitLab: no work item $gid (404 Not found)`n" }; $w.state = 'closed'; return $w }
            $d = GL-_gql $gl 'mutation($in: WorkItemUpdateInput!) { workItemUpdate(input: $in) { workItem { id state } errors } }' (O 'in' (O 'id' (WiGid $gid) 'stateEvent' 'CLOSE'))
            $r = Dor $d.workItemUpdate (NewH)
            if ((L $r.errors).Count) { throw "GitLab: workItemUpdate: $((L $r.errors) -join ' ')`n" }
            return , (Dor $r.workItem (NewH))
        }
        if (IsLocal $gl) {
            $w = GL-_local_work_item $gl $gid; if (-not $w) { throw "GitLab: no work item $gid (404 Not found)`n" }
            if ([string](Dor $o.mode 'statuses') -ceq 'labels') {
                $w.labels = @((Where-L $w.labels { param($x) [string]$x -cnotmatch '^state::' })) + "state::$name"
                $w.state = $(if ($name -cmatch '^(?i)(DONE|DROP)$') { 'closed' } else { 'opened' })
                return $w
            }
            $s = GL-_status_of $gl $g $name
            $w.status = $s.name
            $w.state = $(if ($s.category -cmatch '^(done|canceled)$') { 'closed' } else { 'opened' })
            return $w
        }
        $in = O 'id' (WiGid $gid)
        if ([string](Dor $o.mode 'statuses') -ceq 'labels') { if ($name -cmatch '^(?i)(DONE|DROP)$') { $in.stateEvent = 'CLOSE' }; if (-not $in.stateEvent) { return , (NewH) } }
        else { $in.statusWidget = O 'status' (GL-_status_of $gl $g $name).id }
        $d = GL-_gql $gl 'mutation($in: WorkItemUpdateInput!) { workItemUpdate(input: $in) { workItem { id state } errors } }' (O 'in' $in)
        $r = Dor $d.workItemUpdate (NewH)
        if ((L $r.errors).Count) { throw "GitLab: workItemUpdate: $((L $r.errors) -join ' ')`n" }
        return , (Dor $r.workItem (NewH))
    })
}

# ---------------------------------------------------------------- files in the repository
function GL-file_raw($gl, $p, $path, $ref) {
    if (IsLocal $gl) { $null = GL-_p $gl $p; return $null }   # no git here: the emulator's repositories cannot be read (Perl reads them with git)
    if ($gl.dry_run) { return $null }
    $r = $null
    try { $r = (GL-_api1 $gl 'GET' ('/projects/' + (Enc $p) + '/repository/files/' + (Enc $path) + '/raw') $null (O 'ref' $ref))[0] } catch { $r = $null }
    if ($null -eq $r) { return $null }
    if ($r -is [hashtable] -or $r -is [array]) { return , (JsEnc $r) }
    return $r
}
function GL-commit_files($gl, $p, $o) {
    return , (DryWrap $gl {
        if (IsLocal $gl) { $null = GL-_p $gl $p; throw $script:NOGIT }
        $acts = Map-L $o.actions { param($a) O 'action' (Dor $a.action 'update') 'file_path' $a.file_path 'content' $a.content }
        $b = O 'branch' $o.branch 'commit_message' (Dor $o.message 'Update files') 'actions' $acts
        if ($o.start_branch) { $b.start_branch = $o.start_branch }
        return , (GL-_api $gl 'POST' ('/projects/' + (Enc $p) + '/repository/commits') $b)
    })
}

# ---------------------------------------------------------------- protection and approvals
function GL-protect_branch($gl, $p, $name, $o) {
    return , (DryWrap $gl {
        $r = O 'name' $name 'push_access_level' (LevelOf (Dor $o.push_access_level 'maintainer')) 'merge_access_level' (LevelOf (Dor $o.merge_access_level 'maintainer')) `
            'allow_force_push' $(if (Tru $o.allow_force_push) { 1 } else { 0 }) 'code_owner_approval_required' $(if (Tru $o.code_owner_approval_required) { 1 } else { 0 })
        if (IsLocal $gl) {
            $PJ = GL-_p $gl $p
            $PJ.protected_branches = (Where-L $PJ.protected_branches { param($x) $x.name -cne $name }) + , $r
            GL-_write_protect $gl $PJ
            return $r
        }
        $b = Copy-H $r
        $b.allow_force_push = Jbool $(if ($r.allow_force_push) { 'true' } else { 'false' })
        $b.code_owner_approval_required = Jbool $(if ($r.code_owner_approval_required) { 'true' } else { 'false' })
        return , (GL-_api $gl 'POST' ('/projects/' + (Enc $p) + '/protected_branches') $b)
    })
}
function GL-protect_tag($gl, $p, $name, $o) {
    return , (DryWrap $gl {
        $r = O 'name' $name 'create_access_level' (LevelOf (Dor $o.create_access_level 'maintainer'))
        if (IsLocal $gl) {
            $PJ = GL-_p $gl $p
            $PJ.protected_tags = (Where-L $PJ.protected_tags { param($x) $x.name -cne $name }) + , $r
            GL-_write_protect $gl $PJ
            return $r
        }
        return , (GL-_api $gl 'POST' ('/projects/' + (Enc $p) + '/protected_tags') $r)
    })
}
function GL-create_approval_rule($gl, $p, $name, $n, $o) {
    return , (DryWrap $gl {
        $users = Arr $o.users
        if (IsLocal $gl) {
            $PJ = GL-_p $gl $p
            $r = O 'name' $name 'approvals_required' (PNum $n) 'users' $users
            $PJ.approval_rules = (Where-L $PJ.approval_rules { param($x) $x.name -cne $name }) + , $r
            return $r
        }
        return , (GL-_api $gl 'POST' ('/projects/' + (Enc $p) + '/approval_rules') (O 'name' $name 'approvals_required' (PNum $n) 'user_ids' (Map-L $users { param($u) GL-_uid $gl $u })))
    })
}

# ---------------------------------------------------------------- issues
function GL-create_issue($gl, $p, $o) {
    return , (DryWrap $gl {
        if ([string](Dor $o.title '') -ceq '') { throw "GitLab: an issue needs a title`n" }
        if (IsLocal $gl) { return , (GL-_create_issue $gl $p $o) }
        $b = O 'title' $o.title
        if ($null -ne $o.description) { $b.description = $o.description }
        if (Tru $o.labels) { $b.labels = (Arr $o.labels) -join ',' }
        if (Tru $o.milestone) { $b.milestone_id = GL-_mid $gl $p $o.milestone }
        if (Tru $o.assignees) { $b.assignee_ids = Map-L (Arr $o.assignees) { param($u) GL-_uid $gl $u } }
        foreach ($k in @('issue_type', 'weight', 'due_date', 'confidential')) { if ($null -ne $o[$k]) { $b[$k] = $o[$k] } }
        return , (GL-_api $gl 'POST' ('/projects/' + (Enc $p) + '/issues') $b)
    })
}
function GL-update_issue($gl, $p, $iid, $o) {
    return , (DryWrap $gl {
        if (IsLocal $gl) { return , (GL-_update_issue $gl $p $iid $o) }
        $b = NewH
        foreach ($k in @('state_event', 'description', 'title', 'weight', 'due_date')) { if ($null -ne $o[$k]) { $b[$k] = $o[$k] } }
        foreach ($k in @('add_labels', 'remove_labels', 'labels')) { if ($null -ne $o[$k]) { $b[$k] = (Arr $o[$k]) -join ',' } }
        if ($null -ne $o.milestone) { if ([string]$o.milestone -ceq '') { $b.milestone_id = 0 } else { $b.milestone_id = GL-_mid $gl $p $o.milestone } }
        if (Tru $o.assignees) { $b.assignee_ids = Map-L (Arr $o.assignees) { param($u) GL-_uid $gl $u } }
        return , (GL-_api $gl 'PUT' ('/projects/' + (Enc $p) + "/issues/$iid") $b)
    })
}
function GL-issue($gl, $p, $iid) {
    if (IsLocal $gl) { return , (GL-_issue $gl (GL-_p $gl $p) $iid) }
    return , (GL-_api $gl 'GET' ('/projects/' + (Enc $p) + "/issues/$iid"))
}
function GL-issues($gl, $p, $f) {
    if ($null -eq $f) { $f = NewH }
    if (IsLocal $gl) {
        $PJ = GL-_p $gl $p
        $st = Dor $f.state 'all'
        $labels = Arr $f.labels
        return , (Where-L $PJ.issues { param($i)
            ($st -ceq 'all' -or $i.state -ceq $st) -and
            ($labels.Count -eq 0 -or (HasAll $i.labels $labels)) -and
            ($null -eq $f.milestone -or ($i.milestone -and [string]$i.milestone.title -ceq [string]$f.milestone)) -and
            ($null -eq $f.issue_type -or [string]$i.issue_type -ceq [string]$f.issue_type) -and
            ($null -eq $f.assignee_username -or (First $i.assignees { param($a) $a.username -ceq $f.assignee_username })) -and
            ($null -eq $f.search -or ([string]$i.title).ToLowerInvariant().IndexOf(([string]$f.search).ToLowerInvariant()) -ge 0) })
    }
    $q = O 'state' (Dor $f.state 'all')
    if (Tru $f.labels) { $q.labels = (Arr $f.labels) -join ',' }
    foreach ($k in @('milestone', 'issue_type', 'assignee_username', 'search')) { if ($null -ne $f[$k]) { $q[$k] = $f[$k] } }
    return , (GL-_api $gl 'GET' ('/projects/' + (Enc $p) + '/issues') $null (O 'query' $q 'all' 1))
}
function HasAll($have, $want) { $h = NewH; foreach ($x in (L $have)) { $h[[string]$x] = 1 }; foreach ($w in (L $want)) { if (-not $h.ContainsKey([string]$w)) { return $false } }; return $true }
function GL-add_note($gl, $p, $kind, $iid, $body, $o) {
    if ($null -eq $o) { $o = NewH }
    return , (DryWrap $gl {
        if ($kind -cnotmatch '^(issue|mr)$') { throw "GitLab: add_note kind is issue or mr, not '$kind'`n" }
        if (IsLocal $gl) { return , (GL-_add_note $gl $p $kind $iid $body $o) }
        $what = $(if ($kind -ceq 'mr') { 'merge_requests' } else { 'issues' })
        $path = '/projects/' + (Enc $p) + "/$what/$iid/" + $(if (Tru $o.resolvable) { 'discussions' } else { 'notes' })
        return , (GL-_api $gl 'POST' $path (O 'body' $body))
    })
}
function GL-resolve_discussions($gl, $p, $iid) {
    return , (DryWrap $gl {
        if (IsLocal $gl) { $m = GL-_mr $gl (GL-_p $gl $p) $iid; foreach ($n in (L $m.notes)) { if (Tru $n.resolvable) { $n.resolved = 1 } }; return $m }
        $base = '/projects/' + (Enc $p) + "/merge_requests/$iid/discussions"
        $ds = GL-_api $gl 'GET' $base $null (O 'all' 1)
        foreach ($d in (L $ds)) {
            if (-not (First $d.notes { param($n) (Tru $n.resolvable) -and -not (Tru $n.resolved) })) { continue }
            $null = GL-_api $gl 'PUT' "$base/$($d.id)" $null (O 'query' (O 'resolved' 'true'))
        }
        return $ds
    })
}
function GL-link_issues($gl, $p, $iid, $target, $type) {
    return , (DryWrap $gl {
        if ($null -eq $type) { $type = 'relates_to' }
        if (IsLocal $gl) {
            $PJ = GL-_p $gl $p
            $a = GL-_issue $gl $PJ $iid; $b = GL-_issue $gl $PJ $target
            $inv = O 'relates_to' 'relates_to' 'blocks' 'is_blocked_by' 'is_blocked_by' 'blocks'
            if (-not $inv.ContainsKey([string]$type)) { throw "GitLab: link type is relates_to, blocks or is_blocked_by, not '$type'`n" }
            if (-not (First $a.links { param($x) [long]$x.iid -eq [long](PNum $target) })) { Push $a 'links' (O 'iid' (PNum $target) 'link_type' $type) }
            if (-not (First $b.links { param($x) [long]$x.iid -eq [long](PNum $iid) })) { Push $b 'links' (O 'iid' (PNum $iid) 'link_type' $inv[[string]$type]) }
            return , (O 'source_issue' (O 'iid' $iid) 'target_issue' (O 'iid' $target) 'link_type' $type)
        }
        $proj = $(if ($gl.dry_run) { "{id of $p}" } else { (GL-_api $gl 'GET' ('/projects/' + (Enc $p))).id })
        return , (GL-_api $gl 'POST' ('/projects/' + (Enc $p) + "/issues/$iid/links") (O 'target_project_id' $proj 'target_issue_iid' $target 'link_type' $type))
    })
}

# ---------------------------------------------------------------- merge requests
function GL-create_mr($gl, $p, $o) {
    return , (DryWrap $gl {
        foreach ($k in @('source_branch', 'target_branch', 'title')) { if ($null -eq $o[$k]) { throw "GitLab: a merge request needs $k`n" } }
        if (IsLocal $gl) { return , (GL-_create_mr $gl $p $o) }
        $b = NewH; foreach ($k in @('source_branch', 'target_branch', 'title', 'description', 'squash')) { if ($null -ne $o[$k]) { $b[$k] = $o[$k] } }
        if ($null -ne $o.remove_source_branch) { $b.remove_source_branch = Jbool $(if (Tru $o.remove_source_branch) { 'true' } else { 'false' }) }
        if (Tru $o.labels) { $b.labels = (Arr $o.labels) -join ',' }
        if (Tru $o.milestone) { $b.milestone_id = GL-_mid $gl $p $o.milestone }
        if (Tru $o.assignee) { $b.assignee_id = GL-_uid $gl $o.assignee }
        if (Tru $o.reviewers) { $b.reviewer_ids = Map-L (Arr $o.reviewers) { param($u) GL-_uid $gl $u } }
        return , (GL-_api $gl 'POST' ('/projects/' + (Enc $p) + '/merge_requests') $b)
    })
}
function GL-mr($gl, $p, $iid) {
    if (IsLocal $gl) { return , (GL-_mr $gl (GL-_p $gl $p) $iid) }
    return , (GL-_api $gl 'GET' ('/projects/' + (Enc $p) + "/merge_requests/$iid"))
}
function GL-mrs($gl, $p, $f) {
    if ($null -eq $f) { $f = NewH }
    if (IsLocal $gl) {
        $st = Dor $f.state 'all'; $labels = Arr $f.labels
        return , (Where-L (GL-_p $gl $p).mrs { param($m) ($st -ceq 'all' -or $m.state -ceq $st) -and ($null -eq $f.source_branch -or $m.source_branch -ceq $f.source_branch) -and
            ($null -eq $f.target_branch -or $m.target_branch -ceq $f.target_branch) -and ($labels.Count -eq 0 -or (HasAll $m.labels $labels)) })
    }
    $q = O 'state' (Dor $f.state 'all')
    foreach ($k in @('source_branch', 'target_branch')) { if ($null -ne $f[$k]) { $q[$k] = $f[$k] } }
    if (Tru $f.labels) { $q.labels = (Arr $f.labels) -join ',' }
    return , (GL-_api $gl 'GET' ('/projects/' + (Enc $p) + '/merge_requests') $null (O 'query' $q 'all' 1))
}
function GL-approve_mr($gl, $p, $iid) {
    return , (DryWrap $gl {
        if (IsLocal $gl) { return , (GL-_approve $gl $p $iid) }
        return , (GL-_api $gl 'POST' ('/projects/' + (Enc $p) + "/merge_requests/$iid/approve") (NewH))
    })
}
function GL-merge_mr($gl, $p, $iid, $o) {
    if ($null -eq $o) { $o = NewH }
    return , (DryWrap $gl {
        if (IsLocal $gl) { return , (GL-_merge $gl $p $iid $o) }
        $b = NewH
        if ($null -ne $o.merge_when_pipeline_succeeds) { $b.merge_when_pipeline_succeeds = Jbool $(if (Tru $o.merge_when_pipeline_succeeds) { 'true' } else { 'false' }) }
        if ($null -ne $o.remove_source_branch) { $b.should_remove_source_branch = Jbool $(if (Tru $o.remove_source_branch) { 'true' } else { 'false' }) }
        if ($null -ne $o.squash) { $b.squash = Jbool $(if (Tru $o.squash) { 'true' } else { 'false' }) }
        if ($null -ne $o.merge_commit_message) { $b.merge_commit_message = $o.merge_commit_message }
        return , (GL-_api $gl 'PUT' ('/projects/' + (Enc $p) + "/merge_requests/$iid/merge") $b)
    })
}

# ---------------------------------------------------------------- pipelines, branches, tags, releases, wiki
function GL-run_pipeline($gl, $p, $ref, $o) {
    if ($null -eq $o) { $o = NewH }
    return , (DryWrap $gl {
        if (IsLocal $gl) { $null = GL-_p $gl $p; throw $script:NOGIT }
        $b = O 'ref' $ref
        if ($o.variables -and $o.variables.Count) { $b.variables = Map-L (SortStr @($o.variables.Keys)) { param($k) O 'key' $k 'value' $o.variables[$k] } }
        return , (GL-_api $gl 'POST' ('/projects/' + (Enc $p) + '/pipeline') $b)
    })
}
function GL-pipelines($gl, $p, $f) {
    if ($null -eq $f) { $f = NewH }
    if (IsLocal $gl) {
        return , (Where-L (GL-_p $gl $p).pipelines { param($x) ($null -eq $f.ref -or $x.ref -ceq $f.ref) -and ($null -eq $f.status -or $x.status -ceq $f.status) -and
            ($null -eq $f.source -or $x.source -ceq $f.source) -and ($null -eq $f.mr_iid -or (PNum (Dor $x.mr_iid 0)) -eq (PNum $f.mr_iid)) })
    }
    $q = NewH; foreach ($k in @('ref', 'status', 'source', 'updated_after', 'updated_before')) { if ($null -ne $f[$k]) { $q[$k] = $f[$k] } }
    return , (GL-_api $gl 'GET' ('/projects/' + (Enc $p) + '/pipelines') $null (O 'query' $q 'all' 1))
}
function GL-pipeline($gl, $p, $id) {
    if (IsLocal $gl) { $pl = First (GL-_p $gl $p).pipelines { param($x) [long]$x.id -eq [long](PNum $id) }; if (-not $pl) { throw "GitLab: no pipeline $id in $p`n" }; return $pl }
    return , (GL-_api $gl 'GET' ('/projects/' + (Enc $p) + "/pipelines/$id"))
}
function GL-jobs($gl, $p, $id) {
    if (IsLocal $gl) { return , @((GL-pipeline $gl $p $id).jobs) }
    return , (GL-_api $gl 'GET' ('/projects/' + (Enc $p) + "/pipelines/$id/jobs") $null (O 'query' (O 'include_retried' 'false') 'all' 1))
}
function GL-create_branch($gl, $p, $name, $ref) {
    return , (DryWrap $gl {
        if (IsLocal $gl) {
            $PJ = GL-_p $gl $p
            if (GL-_sha $gl $PJ "refs/heads/$name") { throw "GitLab: branch '$name' already exists in $p (400 Branch already exists)`n" }
            $sha = Dor (GL-_sha $gl $PJ "refs/heads/$ref") (GL-_sha $gl $PJ $ref)
            if (-not $sha) { throw "GitLab: no branch or commit '$ref' in $p (400 Invalid reference name)`n" }
            throw $script:NOGIT
        }
        return , (GL-_api $gl 'POST' ('/projects/' + (Enc $p) + '/repository/branches') $null (O 'query' (O 'branch' $name 'ref' $ref)))
    })
}
function GL-create_tag($gl, $p, $name, $ref, $msg) {
    return , (DryWrap $gl {
        if (IsLocal $gl) { $null = GL-_p $gl $p; throw $script:NOGIT }
        $b = O 'tag_name' $name 'ref' $ref; if ($null -ne $msg) { $b.message = $msg }
        return , (GL-_api $gl 'POST' ('/projects/' + (Enc $p) + '/repository/tags') $b)
    })
}
function GL-create_release($gl, $p, $o) {
    return , (DryWrap $gl {
        if ($null -eq $o.tag_name) { throw "GitLab: a release needs tag_name`n" }
        if (IsLocal $gl) {
            $PJ = GL-_p $gl $p
            if (-not (GL-_sha $gl $PJ "refs/tags/$($o.tag_name)")) { throw "GitLab: tag '$($o.tag_name)' does not exist in $p`n" }
            throw $script:NOGIT
        }
        $b = O 'tag_name' $o.tag_name 'name' (Dor $o.name $o.tag_name) 'description' (Dor $o.description '')
        if (Tru $o.milestones) { $b.milestones = Arr $o.milestones }
        return , (GL-_api $gl 'POST' ('/projects/' + (Enc $p) + '/releases') $b)
    })
}
function GL-tags_containing($gl, $p, $sha) {
    if (IsLocal $gl) { $null = GL-_p $gl $p; return , @() }    # Perl: git tag --contains (no git here: no tags)
    $r = GL-_api $gl 'GET' ('/projects/' + (Enc $p) + "/repository/commits/$sha/refs") $null (O 'query' (O 'type' 'tag') 'all' 1)
    return , (Map-L (Where-L $r { param($x) [string](Dor $x.type 'tag') -ceq 'tag' }) { param($x) $x.name })
}
function GL-releases($gl, $p) {
    if (IsLocal $gl) { $r = L (GL-_p $gl $p).releases; $o = @(); for ($i = $r.Count - 1; $i -ge 0; $i--) { $o += , $r[$i] }; return , $o }
    return , (GL-_api $gl 'GET' ('/projects/' + (Enc $p) + '/releases') $null (O 'all' 1))
}
function GL-wiki_put($gl, $p, $title, $content) {
    return , (DryWrap $gl {
        $slug = $title -creplace '\s+', '-'
        if (IsLocal $gl) {
            $PJ = GL-_p $gl $p
            $w = First $PJ.wiki { param($x) $x.slug -ceq $slug }
            if ($w) { $w.content = $content; $w.updated_at = GL-now $gl; return $w }
            $w = O 'slug' $slug 'title' $title 'format' 'markdown' 'content' $content 'created_at' (GL-now $gl) 'updated_at' (GL-now $gl)
            Push $PJ 'wiki' $w
            return $w
        }
        $base = '/projects/' + (Enc $p) + '/wikis'
        $have = $(if ($gl.dry_run) { @() } else { GL-_api $gl 'GET' $base $null (O 'all' 1) })
        if (First $have { param($x) $x.slug -ceq $slug }) { return , (GL-_api $gl 'PUT' "$base/$(Enc $slug)" (O 'title' $title 'content' $content 'format' 'markdown')) }
        return , (GL-_api $gl 'POST' $base (O 'title' $title 'content' $content 'format' 'markdown'))
    })
}
function GL-wiki($gl, $p) {
    if (IsLocal $gl) { return , @((GL-_p $gl $p).wiki) }
    return , (GL-_api $gl 'GET' ('/projects/' + (Enc $p) + '/wikis') $null (O 'query' (O 'with_content' 1) 'all' 1))
}
function GL-environments($gl, $p) {
    if (IsLocal $gl) { return , (L (GL-_p $gl $p).environments) }
    return , (GL-_api $gl 'GET' ('/projects/' + (Enc $p) + '/environments') $null (O 'all' 1))
}
function GL-deployments($gl, $p, $f) {
    if ($null -eq $f) { $f = NewH }
    if (IsLocal $gl) { return , (Where-L (GL-_p $gl $p).deployments { param($d) $null -eq $f.environment -or $d.environment.name -ceq $f.environment }) }
    $q = O 'order_by' 'id'; if ($null -ne $f.environment) { $q.environment = $f.environment }
    return , (GL-_api $gl 'GET' ('/projects/' + (Enc $p) + '/deployments') $null (O 'query' $q 'all' 1))
}
function GL-pages($gl, $p) {
    if (IsLocal $gl) { return , (GL-_p $gl $p).pages }
    return , (GL-_api $gl 'GET' ('/projects/' + (Enc $p) + '/pages'))
}

# ---------------------------------------------------------------- Generic Package Registry
function PkgCheck($n, $v, $f) {
    if ([string]$n -cnotmatch '^[\w.-]+$') { throw "GitLab: a package name is letters, digits and . _ - ('$n')`n" }
    if ([string]$v -cnotmatch '^[\w.+-]+$') { throw "GitLab: a package version is letters, digits and . _ + - ('$v')`n" }
    if ($null -ne $f -and [string]$f -cnotmatch '^[\w.+-]+$') { throw "GitLab: a package file name is letters, digits and . _ + - ('$f')`n" }
}
function GL-package_put($gl, $p, $name, $ver, $file, $o) {
    if ($null -eq $o) { $o = NewH }
    return , (DryWrap $gl {
        if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { throw "GitLab: no file $file to upload`n" }
        $base = $file -creplace '.*[/\\]', ''
        PkgCheck $name $ver $base
        $bytes = Zl-ReadBytes $file
        $sha = Sha256Hex $bytes
        $size = $bytes.Length
        if (IsLocal $gl) {
            $PJ = GL-_p $gl $p
            $dt = $(if ($o.deploy_token) { GL-_deploy_token_ok $gl $PJ $o.deploy_token 'write_package_registry' } else { $null })
            if ($o.deploy_token -and -not $dt) { throw "GitLab: the deploy token cannot publish packages to $p (403 Forbidden)`n" }
            if (-not $dt -and (GL-_level $gl $PJ $gl.as) -lt 30) { throw "GitLab: $($gl.as) cannot publish packages to $p (403 Forbidden)`n" }
            $dir = "$($gl.local)/packages/$($PJ.path_with_namespace)/$name/$ver"
            $null = New-Item -ItemType Directory -Path $dir -Force
            Zl-WriteBytes "$dir/$base" $bytes
            if ($null -eq $PJ.packages) { $PJ.packages = @() }
            $pk = First $PJ.packages { param($x) $x.name -ceq $name -and $x.version -ceq $ver }
            if (-not $pk) { $pk = O 'id' (GL-_id $gl) 'name' $name 'version' $ver 'package_type' 'generic' 'created_at' (GL-now $gl) 'files' @(); Push $PJ 'packages' $pk }
            $f = O 'file_name' $base 'size' $size 'file_sha256' $sha 'created_at' (GL-now $gl) 'uploaded_by' $(if ($dt) { $dt.username } else { $gl.as })
            $pk.files = (Where-L $pk.files { param($x) $x.file_name -cne $base }) + , $f
            $r = Copy-H $f; $r.name = $name; $r.version = $ver
            return $r
        }
        $path = '/projects/' + (Enc $p) + "/packages/generic/$name/$ver/$base"
        if ($gl.dry_run) { GOut "PUT /api/v4$path <$file ($size bytes, sha256 $sha)>`n"; return , (O 'name' $name 'version' $ver 'file_name' $base 'size' $size 'file_sha256' $sha) }
        $hd = @{}
        if ($o.deploy_token) { $hd['Deploy-Token'] = $o.deploy_token } else {
            $tok = (Get-Item -LiteralPath ("env:" + $gl.token_env) -ErrorAction SilentlyContinue).Value
            if ($null -eq $tok) { throw "GitLab: set $($gl.token_env) to a personal or project access token (scope api)`n" }
            $hd['PRIVATE-TOKEN'] = $tok
        }
        try { $null = Invoke-WebRequest -Uri "$($gl.url)/api/v4$path" -Method PUT -Headers $hd -InFile $file -UseBasicParsing -ErrorAction Stop }
        catch { throw "GitLab: package upload failed: $($_.Exception.Message)`n" }
        return , (O 'name' $name 'version' $ver 'file_name' $base 'size' $size 'file_sha256' $sha)
    })
}
function GL-package_get($gl, $p, $name, $ver, $fname, $dest) {
    PkgCheck $name $ver $fname
    if ($null -eq $dest) { $dest = $fname }
    if (Test-Path -LiteralPath $dest -PathType Container) { $dest = "$dest/$fname" }
    if (IsLocal $gl) {
        $PJ = GL-_p $gl $p
        $pk = First $PJ.packages { param($x) $x.name -ceq $name -and $x.version -ceq $ver }
        $f = $(if ($pk) { First $pk.files { param($x) $x.file_name -ceq $fname } } else { $null })
        if (-not $f) { throw "GitLab: no package file $name/$ver/$fname in $p (404 Not found)`n" }
        $src = "$($gl.local)/packages/$($PJ.path_with_namespace)/$name/$ver/$fname"
        $bytes = Zl-ReadBytes $src
        Zl-WriteBytes $dest $bytes
        if ((Sha256Hex (Zl-ReadBytes $dest)) -cne $f.file_sha256) { throw "GitLab: $dest does not match the registry's sha256`n" }
        return $dest
    }
    $path = '/projects/' + (Enc $p) + "/packages/generic/$name/$ver/$fname"
    if ($gl.dry_run) { GOut "GET /api/v4$path > $dest`n"; return $dest }
    $tok = (Get-Item -LiteralPath ("env:" + $gl.token_env) -ErrorAction SilentlyContinue).Value
    if ($null -eq $tok) { throw "GitLab: set $($gl.token_env) to a personal or project access token (scope api)`n" }
    try { $null = Invoke-WebRequest -Uri "$($gl.url)/api/v4$path" -Headers @{ 'PRIVATE-TOKEN' = $tok } -OutFile $dest -UseBasicParsing -ErrorAction Stop }
    catch { throw "GitLab: package download failed: $($_.Exception.Message)`n" }
    return $dest
}
function GL-packages($gl, $p) {
    if (IsLocal $gl) { return , (L (GL-_p $gl $p).packages) }
    return , (GL-_api $gl 'GET' ('/projects/' + (Enc $p) + '/packages') $null (O 'query' (O 'package_type' 'generic') 'all' 1))
}

# ---------------------------------------------------------------- trigger tokens and deploy tokens
function GL-create_trigger($gl, $p, $desc) {
    return , (DryWrap $gl {
        if (IsLocal $gl) {
            $PJ = GL-_p $gl $p
            if ((GL-_level $gl $PJ $gl.as) -lt 40) { throw "GitLab: $($gl.as) cannot create trigger tokens in $p (403 Forbidden)`n" }
            $id = GL-_id $gl
            $tr = O 'id' $id 'description' (Dor $desc '') 'token' ('glptt-' + (Md5Hex "trigger $p $id $desc").Substring(0, 20)) 'owner' (O 'username' $gl.as) 'created_at' (GL-now $gl)
            Push $PJ 'triggers' $tr
            return , (Copy-H $tr)
        }
        return , (GL-_api $gl 'POST' ('/projects/' + (Enc $p) + '/triggers') (O 'description' (Dor $desc '')))
    })
}
function GL-triggers($gl, $p) {
    if (IsLocal $gl) { return , (Map-L (GL-_p $gl $p).triggers { param($x) Copy-H $x }) }
    return , (GL-_api $gl 'GET' ('/projects/' + (Enc $p) + '/triggers') $null (O 'all' 1))
}
function GL-trigger_pipeline($gl, $p, $token, $ref, $o) {
    if ($null -eq $o) { $o = NewH }
    if (IsLocal $gl) {
        $PJ = GL-_p $gl $p
        $tr = First $PJ.triggers { param($x) $x.token -ceq [string](Dor $token '') }
        if (-not $tr) { throw "GitLab: invalid trigger token for $p (404 Not Found)`n" }
        if (-not (GL-_sha $gl $PJ "refs/heads/$ref")) { throw "GitLab: no branch or tag '$ref' in $p (400 Reference not found)`n" }
        throw $script:NOGIT
    }
    $b = O 'token' $token 'ref' $ref; if ($o.variables -and $o.variables.Count) { $b.variables = $o.variables }
    return , (GL-_api $gl 'POST' ('/projects/' + (Enc $p) + '/trigger/pipeline') $b)
}
function GL-create_deploy_token($gl, $p, $name, $scopes, $o) {
    if ($null -eq $o) { $o = NewH }
    return , (DryWrap $gl {
        $s = Arr $scopes
        $ok = @('read_repository', 'read_registry', 'write_registry', 'read_package_registry', 'write_package_registry')
        foreach ($x in $s) { if ($ok -cnotcontains $x) { throw "GitLab: deploy token scope is read_repository, read_registry, write_registry, read_package_registry or write_package_registry, not '$x'`n" } }
        if (IsLocal $gl) {
            $PJ = GL-_p $gl $p
            if ((GL-_level $gl $PJ $gl.as) -lt 40) { throw "GitLab: $($gl.as) cannot create deploy tokens in $p (403 Forbidden)`n" }
            $id = GL-_id $gl
            $dt = O 'id' $id 'name' $name 'username' "gitlab+deploy-token-$id" 'scopes' $s 'expires_at' $o.expires_at 'token' ('gldt-' + (Md5Hex "deploy $p $id $name").Substring(0, 20)) 'created_at' (GL-now $gl) 'revoked' 0
            Push $PJ 'deploy_tokens' $dt
            return , (Copy-H $dt)
        }
        $b = O 'name' $name 'scopes' $s; if ($o.expires_at) { $b.expires_at = $o.expires_at }
        return , (GL-_api $gl 'POST' ('/projects/' + (Enc $p) + '/deploy_tokens') $b)
    })
}
function GL-deploy_tokens($gl, $p) {
    if (IsLocal $gl) { return , (Map-L (GL-_p $gl $p).deploy_tokens { param($x) $c = Copy-H $x; $c.token = $null; $c }) }
    return , (GL-_api $gl 'GET' ('/projects/' + (Enc $p) + '/deploy_tokens') $null (O 'all' 1))
}
function GL-_deploy_token_ok($gl, $PJ, $token, $scope) {
    $dt = First $PJ.deploy_tokens { param($x) $x.token -ceq [string](Dor $token '') }
    if (-not $dt) { return $null }
    if ((Tru $dt.revoked) -or ($dt.expires_at -and (OrdCmp (GL-now $gl).Substring(0, 10) $dt.expires_at) -gt 0)) { return $null }
    if ((L $dt.scopes) -ccontains $scope) { return $dt }
    return $null
}

# ---------------------------------------------------------------- job artifacts and notes
function GL-job_artifact($gl, $p, $o) {
    foreach ($k in @('ref', 'job', 'path')) { if ([string](Dor $o[$k] '') -ceq '') { throw "GitLab: job_artifact needs $k`n" } }
    $path = ([string]$o.path) -creplace '^/+', ''
    if (@($path -split '/') -contains '..') { throw "GitLab: an artifact path may not contain '..' ('$($o.path)')`n" }
    if (IsLocal $gl) {
        $PJ = GL-_p $gl $p
        $pls = L $PJ.pipelines
        for ($i = $pls.Count - 1; $i -ge 0; $i--) {
            $pl = $pls[$i]
            $match = ($pl.ref -ceq $o.ref) -or ($(if ([string]$pl.ref -cmatch '^refs/merge-requests/') { $false } else { "refs/heads/$($pl.ref)" -ceq $o.ref }))
            if (-not $match) { continue }
            $j = First $pl.jobs { param($x) $x.name -ceq $o.job -and $x.status -ceq 'success' }
            if (-not $j) { continue }
            $safe = ([string]$o.job) -creplace '[^\w.-]+', '_'
            $f = "$($pl.log_dir)/artifacts/$safe/$path"
            if (-not (Test-Path -LiteralPath $f -PathType Leaf)) { throw "GitLab: no artifact $path in job $($o.job) of pipeline #$($pl.id) on $($o.ref) (404 Not found)`n" }
            return , (ReadText $f)
        }
        throw "GitLab: no successful job $($o.job) on $($o.ref) in $p (404 Not found)`n"
    }
    $rel = '/projects/' + (Enc $p) + '/jobs/artifacts/' + (Enc $o.ref) + '/raw/' + ((@(foreach ($x in ($path -split '/')) { Enc $x })) -join '/') + '?job=' + (Enc $o.job)
    if ($gl.dry_run) { GOut "GET /api/v4$rel`n"; return '' }
    $tok = (Get-Item -LiteralPath ("env:" + $gl.token_env) -ErrorAction SilentlyContinue).Value
    if ($null -eq $tok) { throw "GitLab: set $($gl.token_env) to a personal or project access token (scope api)`n" }
    try { return [string](Invoke-WebRequest -Uri "$($gl.url)/api/v4$rel" -Headers @{ 'PRIVATE-TOKEN' = $tok } -UseBasicParsing -ErrorAction Stop).Content }
    catch { throw "GitLab: no artifact $path from job $($o.job) on $($o.ref) in $p (curl exit 22: $($_.Exception.Message))`n" }
}
function GL-issue_notes($gl, $p, $iid) {
    if (IsLocal $gl) { return , (L (GL-_issue $gl (GL-_p $gl $p) $iid).notes) }
    return , (GL-_api $gl 'GET' ('/projects/' + (Enc $p) + "/issues/$iid/notes") $null (O 'query' (O 'sort' 'asc' 'order_by' 'created_at') 'all' 1))
}
function GL-mr_commits($gl, $p, $iid) {
    if (-not (IsLocal $gl)) { return , (GL-_api $gl 'GET' ('/projects/' + (Enc $p) + "/merge_requests/$iid/commits") $null (O 'all' 1)) }
    $null = GL-_mr $gl (GL-_p $gl $p) $iid
    return , @()                                         # Perl reads them with git log; no git here
}
function GL-mr_notes($gl, $p, $iid) {
    if (IsLocal $gl) { return , (L (GL-_mr $gl (GL-_p $gl $p) $iid).notes) }
    return , (GL-_api $gl 'GET' ('/projects/' + (Enc $p) + "/merge_requests/$iid/notes") $null (O 'query' (O 'sort' 'asc' 'order_by' 'created_at') 'all' 1))
}

# ---------------------------------------------------------------- the live settings (for setup --diff)
function GL-protected_branches($gl, $p) {
    if (IsLocal $gl) { return , (Map-L (GL-_p $gl $p).protected_branches { param($x) Copy-H $x }) }
    $lv = { param($l) $v = SortNum (Map-L $l { param($a) Dor $a.access_level 0 }); if ($v.Count) { $v[0] } else { 0 } }
    return , (Map-L (GL-_api $gl 'GET' ('/projects/' + (Enc $p) + '/protected_branches') $null (O 'all' 1)) { param($x)
        O 'name' $x.name 'push_access_level' (& $lv $x.push_access_levels) 'merge_access_level' (& $lv $x.merge_access_levels) `
          'allow_force_push' $(if (Tru $x.allow_force_push) { 1 } else { 0 }) 'code_owner_approval_required' $(if (Tru $x.code_owner_approval_required) { 1 } else { 0 }) })
}
function GL-protected_tags($gl, $p) {
    if (IsLocal $gl) { return , (Map-L (GL-_p $gl $p).protected_tags { param($x) Copy-H $x }) }
    return , (Map-L (GL-_api $gl 'GET' ('/projects/' + (Enc $p) + '/protected_tags') $null (O 'all' 1)) { param($x)
        $v = SortNum (Map-L $x.create_access_levels { param($a) Dor $a.access_level 0 }); O 'name' $x.name 'create_access_level' $(if ($v.Count) { $v[0] } else { 0 }) })
}
function GL-approval_rules($gl, $p) {
    if (IsLocal $gl) { return , (Map-L (GL-_p $gl $p).approval_rules { param($x) $c = Copy-H $x; $c.users = (L $x.users); $c }) }
    return , (Map-L (GL-_api $gl 'GET' ('/projects/' + (Enc $p) + '/approval_rules') $null (O 'all' 1)) { param($x) O 'name' $x.name 'approvals_required' $x.approvals_required 'users' (Map-L $x.users { param($u) $u.username }) })
}
function GL-variables($gl, $p) {
    if (IsLocal $gl) { $v = (GL-_p $gl $p).variables; $ks = SortStr @($v.Keys); return , (Map-L $ks { param($k) Copy-H $v[$k] }) }
    return , (GL-_api $gl 'GET' ('/projects/' + (Enc $p) + '/variables') $null (O 'all' 1))
}
function GL-members($gl, $p) {
    if (IsLocal $gl) {
        $PJ = GL-_p $gl $p
        $u = Copy-H $PJ.members
        $ns = [string]$PJ.namespace
        while ($ns.Length) {
            $g = $gl.st.groups[$ns]
            if ($g) { foreach ($k in @($g.members.Keys)) { if ([long](Dor $g.members[$k] 0) -gt [long](Dor $u[$k] 0)) { $u[$k] = $g.members[$k] } } }
            $ns = $ns -creplace '/?[^/]*$', ''
        }
        return $u
    }
    $r = NewH; foreach ($m in (L (GL-_api $gl 'GET' ('/projects/' + (Enc $p) + '/members/all') $null (O 'all' 1)))) { $r[$m.username] = $m.access_level }
    return $r
}
