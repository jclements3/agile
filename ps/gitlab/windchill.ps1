# windchill.ps1 -- lib/Windchill.pm: Windchill requests (a report exported as CSV) -> GitLab issues, and GitLab progress
# -> a sheet for Windchill. A file each way, no API between them. Constrained Language Mode safe.

$script:WC_DEFAULT = O 'number' 'Number' 'title' 'Name' 'state' 'State' 'type' 'Type' 'requester' 'Created By' 'priority' 'Priority' `
    'need-date' 'Need Date' 'description' 'Description' 'url' '' 'labels' 'source::windchill, type::story' 'accept' '*' 'priority-map' ''
$script:WC_FIELDS = @('number', 'title', 'state', 'type', 'requester', 'priority', 'need-date', 'description')
function WcList($v) { return , @(foreach ($x in ([string](Dor $v '') -split ',')) { $y = $x.Trim(); if ($y.Length) { $y } }) }
function WC-config($c, [string]$file) {
    $v = Copy-H $script:WC_DEFAULT
    foreach ($x in (L $c.windchill)) {
        $k = $x[0].ToLowerInvariant()
        if (-not $script:WC_DEFAULT.ContainsKey($k)) { throw "${file}:$($x[2]): unknown [windchill] key '$($x[0])' (" + ((SortStr @($script:WC_DEFAULT.Keys)) -join ', ') + ")`n" }
        $v[$k] = $x[1]
    }
    $pmap = NewH
    foreach ($e in (WcList $v['priority-map'])) { if ($e -cnotmatch '^(.+?)\s*=\s*(\S+)$') { throw "${file}: [windchill] priority-map entries are WINDCHILL=LABEL, not '$e'`n" }; $pmap[$matches[1].ToLowerInvariant()] = $matches[2] }
    $labels = WcList $v.labels
    $source = $null; foreach ($l in $labels) { if ($l -cmatch '^source::') { $source = $l; break } }
    $acc = WcList $v.accept
    $col = NewH; foreach ($f in $script:WC_FIELDS) { $col[$f] = $v[$f] }
    $accept = $null
    if (-not ($acc.Count -eq 0 -or $acc -ccontains '*')) { $accept = NewH; foreach ($a in $acc) { $accept[$a.ToLowerInvariant()] = 1 } }
    return (O 'col' $col 'url' $v.url 'labels' $labels 'pmap' $pmap 'source' (Dor $source 'source::windchill') 'accept' $accept)
}
function WC-config_file([string]$path) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Windchill: cannot read ${path}: No such file or directory`n" }
    $c = ParseProjectFile (ReadText $path) $path
    $p = $null; foreach ($x in (L $c.project)) { if ($x[0] -ceq 'path') { $p = $x[1]; break } }
    return , @((WC-config $c $path), $p)
}
function Cp1252Dec([byte[]]$b) {                       # Windows-1252 bytes -> text
    $map = @{ 128 = 0x20AC; 130 = 0x201A; 131 = 0x0192; 132 = 0x201E; 133 = 0x2026; 134 = 0x2020; 135 = 0x2021; 136 = 0x02C6; 137 = 0x2030; 138 = 0x0160; 139 = 0x2039; 140 = 0x0152; 142 = 0x017D
              145 = 0x2018; 146 = 0x2019; 147 = 0x201C; 148 = 0x201D; 149 = 0x2022; 150 = 0x2013; 151 = 0x2014; 152 = 0x02DC; 153 = 0x2122; 154 = 0x0161; 155 = 0x203A; 156 = 0x0153; 158 = 0x017E; 159 = 0x0178 }
    $o = ''
    foreach ($x in $b) { $c = [int]$x; if ($map.ContainsKey($c)) { $o += [char]$map[$c] } else { $o += [char]$c } }
    return $o
}
function Utf16Dec([byte[]]$b, [int]$off, [bool]$le) {
    $o = ''
    for ($i = $off; $i + 1 -lt $b.Length; $i += 2) { if ($le) { $c = [int]$b[$i] -bor ([int]$b[$i + 1] -shl 8) } else { $c = ([int]$b[$i] -shl 8) -bor [int]$b[$i + 1] }; $o += [char]$c }
    return $o
}
function ValidUtf8([byte[]]$b) {
    $i = 0; $n = $b.Length
    while ($i -lt $n) {
        $c = [int]$b[$i]
        if ($c -lt 0x80) { $i++; continue }
        $k = 0; if (($c -band 0xE0) -eq 0xC0 -and $c -ge 0xC2) { $k = 1 } elseif (($c -band 0xF0) -eq 0xE0) { $k = 2 } elseif (($c -band 0xF8) -eq 0xF0 -and $c -le 0xF4) { $k = 3 } else { return $false }
        if ($i + $k -ge $n) { return $false }
        for ($j = 1; $j -le $k; $j++) { if (([int]$b[$i + $j] -band 0xC0) -ne 0x80) { return $false } }
        $i += $k + 1
    }
    return $true
}
function WC-decode_bytes([byte[]]$raw) {
    $t = $null
    if ($raw.Length -ge 2 -and $raw[0] -eq 0xFF -and $raw[1] -eq 0xFE) { $t = Utf16Dec $raw 2 $true }
    elseif ($raw.Length -ge 2 -and $raw[0] -eq 0xFE -and $raw[1] -eq 0xFF) { $t = Utf16Dec $raw 2 $false }
    elseif ($raw.Length -ge 8 -and $raw[0] -ne 0 -and $raw[1] -eq 0 -and $raw[2] -ne 0 -and $raw[3] -eq 0 -and $raw[4] -ne 0 -and $raw[5] -eq 0 -and $raw[6] -ne 0 -and $raw[7] -eq 0) { $t = Utf16Dec $raw 0 $true }
    elseif ($raw.Length -ge 8 -and $raw[0] -eq 0 -and $raw[1] -ne 0 -and $raw[2] -eq 0 -and $raw[3] -ne 0 -and $raw[4] -eq 0 -and $raw[5] -ne 0 -and $raw[6] -eq 0 -and $raw[7] -ne 0) { $t = Utf16Dec $raw 0 $false }
    elseif (ValidUtf8 $raw) { if ($raw.Length) { $t = Zl-Utf8Dec $raw 0 $raw.Length } else { $t = '' } }
    else { $t = Cp1252Dec $raw }
    if ($t.Length -and [int]$t[0] -eq 0xFEFF) { $t = $t.Substring(1) }
    $t = $t -replace "`r`n?", "`n"
    return $t
}
function WC-parse_csv([string]$t) {
    $head = ($t -split "`n", 2)[0]
    $bare = $head -creplace '"[^"]*"', ''
    $cnt = O ',' ([regex]::Matches($bare, ',').Count) "`t" ([regex]::Matches($bare, "`t").Count) ';' ([regex]::Matches($bare, ';').Count)
    $sep = ','; $best = $cnt[',']
    foreach ($s in @("`t", ';')) { if ($cnt[$s] -gt $best) { $sep = $s; $best = $cnt[$s] } }
    $rows = @(); $row = @(); $i = 0; $len = $t.Length
    $q = [regex]::Escape($sep)
    while ($i -le $len) {
        if ($i -lt $len -and $t[$i] -ceq '"') {
            $j = $i + 1; $cell = ''
            while ($true) {
                $k = $t.IndexOf('"', $j)
                if ($k -lt 0) { $cell += $t.Substring($j); $i = $len; break }
                $cell += $t.Substring($j, $k - $j)
                if ($k + 1 -lt $len -and $t[$k + 1] -ceq '"') { $cell += '"'; $j = $k + 2; continue }
                $i = $k + 1; break
            }
            if ($i -lt $len) { $m = [regex]::Match($t.Substring($i), "^[^`n$q]*"); $cell += $m.Value; $i += $m.Value.Length }
        } else {
            $m = [regex]::Match($t.Substring($i), "^[^`n$q]*"); $cell = $m.Value; $i += $m.Value.Length
        }
        $row += $cell
        if ($i -ge $len) { if (@($row | Where-Object { $_.Length }).Count) { $rows += , $row }; break }
        $ch = $t[$i]; $i++
        if ($ch -eq "`n") { if (@($row | Where-Object { $_.Length }).Count) { $rows += , $row }; $row = @() }
    }
    return , $rows
}
$script:WC_MON = O 'jan' 1 'feb' 2 'mar' 3 'apr' 4 'may' 5 'jun' 6 'jul' 7 'aug' 8 'sep' 9 'oct' 10 'nov' 11 'dec' 12
function WC-iso_date($s) {
    $s = [string](Dor $s '')
    if ($s -cmatch '^\s*(\d{4})-(\d{1,2})-(\d{1,2})\b') { return ('{0}-{1}-{2}' -f (P4 $matches[1]), (P2 $matches[2]), (P2 $matches[3])) }
    if ($s -cmatch '^\s*(\d{1,2})/(\d{1,2})/(\d{4})\b') { return ('{0}-{1}-{2}' -f (P4 $matches[3]), (P2 $matches[1]), (P2 $matches[2])) }
    if ($s -cmatch '^\s*(\d{1,2})[-\s]([A-Za-z]{3})[A-Za-z]*[-\s,]+(\d{4})\b' -and $script:WC_MON.ContainsKey($matches[2].ToLowerInvariant())) { return ('{0}-{1}-{2}' -f (P4 $matches[3]), (P2 $script:WC_MON[$matches[2].ToLowerInvariant()]), (P2 $matches[1])) }
    return $null
}
function WC-read_export([string]$file, $cfg) {
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { throw "Windchill: cannot read ${file}: No such file or directory`n" }
    $rows = WC-parse_csv (WC-decode_bytes (Zl-ReadBytes $file))
    if ($rows.Count -eq 0) { throw "Windchill: $file is empty (export a Windchill report or search result as CSV)`n" }
    $head = @(foreach ($h in $rows[0]) { $h.Trim() })
    $at = NewH; for ($k = 0; $k -lt $head.Count; $k++) { $lk = $head[$k].ToLowerInvariant(); if (-not $at.ContainsKey($lk)) { $at[$lk] = $k } }
    $col = NewH
    foreach ($f in $script:WC_FIELDS) { $h = $cfg.col[$f]; if ($null -ne $h -and $h.Length -and $at.ContainsKey($h.ToLowerInvariant())) { $col[$f] = $at[$h.ToLowerInvariant()] } }
    foreach ($f in @('number', 'title')) {
        if (-not $col.ContainsKey($f)) { throw "Windchill: $file has no '$($cfg.col[$f])' column for the $f (its columns: " + ($head -join ', ') + "); set $f = COLUMN in [windchill]`n" }
    }
    $rec = @(); $warn = @(); $seen = NewH; $line = 1
    for ($ri = 1; $ri -lt $rows.Count; $ri++) {
        $r = $rows[$ri]; $line++
        $x = O 'line' $line
        foreach ($f in $script:WC_FIELDS) { if ($col.ContainsKey($f)) { $v = $(if ($col[$f] -lt $r.Count) { $r[$col[$f]] } else { '' }); $x[$f] = ([string](Dor $v '')).Trim() } else { $x[$f] = '' } }
        if ($x.number.Length -eq 0) { $warn += "row ${line}: no Windchill number; skipped"; continue }
        if ($seen.ContainsKey($x.number)) { $warn += "row ${line}: $($x.number) appears again; the first row is used"; continue }
        $seen[$x.number] = 1
        $rec += , $x
    }
    return (O 'records' $rec 'warnings' $warn 'columns' $head)
}
function WcAttr($s) { $s = [string](Dor $s ''); $s = $s.Replace('&', '&amp;').Replace('"', '&quot;').Replace('--', '-&#45;').Replace("`n", ' '); return $s }
function WcUnattr($s) { return ([string]$s).Replace('&#45;', '-').Replace('&quot;', '"').Replace('&amp;', '&') }
function WC-marker($r) { return '<!-- windchill ' + ((@(foreach ($k in @('number', 'state', 'priority', 'title')) { $k + '="' + (WcAttr $r[$k]) + '"' })) -join ' ') + ' -->' }
function WC-read_marker($t) {
    $ms = [regex]::Matches([string](Dor $t ''), '<!-- windchill (.*?) -->')
    if ($ms.Count -eq 0) { return $null }
    $h = NewH
    foreach ($m in [regex]::Matches($ms[$ms.Count - 1].Groups[1].Value, '(\w+)="([^"]*)"')) { $h[$m.Groups[1].Value] = WcUnattr $m.Groups[2].Value }
    return $h
}
function WC-issue_link($cfg, $num) { $u = [string](Dor $cfg.url ''); if ($u.Length) { return $u.Replace('{number}', $num) }; return $null }
function WcCell($s) { $s = [string](Dor $s ''); $s = $s.Replace('|', '\|').Replace("`n", ' '); if ($s.Length) { return $s }; return '-' }
function WC-body($r, $cfg) {
    $u = WC-issue_link $cfg $r.number
    $num = $(if ($u) { "[$($r.number)]($u)" } else { $r.number })
    $d = [string](Dor $r.description '')
    $o = "Windchill request $num, submitted by " + $(if ($r.requester.Length) { $r.requester } else { 'an unnamed requester' }) + ".`n`n"
    $o += "| Windchill | |`n|---|---|`n"
    foreach ($x in @(@('Number', $num), @('Type', $r.type), @('State', $r.state), @('Priority', $r.priority), @('Requested by', $r.requester), @('Need date', $r['need-date']))) { $o += "| $($x[0]) | " + (WcCell $x[1]) + " |`n" }
    $o += "`n### The request`n`n" + $(if ($d.Length) { $d } else { '(no description in the export)' }) + "`n`n"
    $o += "<!-- Keep the Windchill number at the start of the title: intake and status find the issue by it. -->`n" + (WC-marker $r) + "`n"
    return $o
}
function WcLabels($r, $cfg) { $pl = $cfg.pmap[([string](Dor $r.priority '')).ToLowerInvariant()]; $o = (L $cfg.labels); if ($pl) { $o += $pl }; return , $o }
function WC-number_of($i) {
    $m = WC-read_marker $i.description
    if ($m -and [string](Dor $m.number '') -cne '') { return $m.number }
    if ([string]$i.title -cmatch '^\s*([^\s:]+)\s*:') { return $matches[1] }
    return $null
}
function WC-intake($gl, $p, [string]$file, $cfg, $o) {
    $x = WC-read_export $file $cfg
    $bynum = NewH; $bytitle = NewH
    foreach ($i in (GL-issues $gl $p (O 'state' 'all'))) {
        $m = WC-read_marker $i.description
        if ($m -and [string](Dor $m.number '') -cne '' -and -not $bynum.ContainsKey($m.number)) { $bynum[$m.number] = $i }
        if ([string]$i.title -cmatch '^\s*([^\s:]+)\s*:' -and -not $bytitle.ContainsKey($matches[1])) { $bytitle[$matches[1]] = $i }
    }
    $s = O 'rows' ((L $x.records).Count + (L $x.warnings).Count) 'created' 0 'skipped' 0 'drift' 0 'lines' @(foreach ($w in (L $x.warnings)) { "warning: $w" })
    $s.skipped += (L $x.warnings).Count
    foreach ($r in (L $x.records)) {
        $i = Dor $bynum[$r.number] $bytitle[$r.number]
        if ($i) {
            $was = Dor (WC-read_marker $i.description) (NewH)
            if (-not $gl.dry_run -or (GL-is_local $gl)) {
                $ns = $null; try { $ns = GL-issue_notes $gl $p $i.iid } catch { $ns = $null }
                foreach ($n in (L $ns)) { $m = WC-read_marker $n.body; if ($m) { $was = $m } }
            }
            $ch = @(foreach ($f in @('title', 'state', 'priority')) { $old = [string](Dor $was[$f] ''); if ($old -cne [string](Dor $r[$f] '')) { "$f '" + $old + "' -> '" + (Dor $r[$f] '') + "'" } })
            if ($ch.Count -and $was.Count) {
                $s.drift++
                $s.lines += "drift   #$($i.iid) $($r.number): " + ($ch -join '; ')
                if (Tru $o.note) {
                    $null = GL-add_note $gl $p 'issue' $i.iid ("Windchill update (from " + ($file -creplace '.*[/\\]', '') + "): " + ($ch -join '; ') + ".`n`n" + (WC-marker $r) + "`n") (NewH)
                    $s.lines += "noted   #$($i.iid) $($r.number)"
                }
            } else { $s.skipped++; $s.lines += "exists  #$($i.iid) $($r.number)" }
            continue
        }
        if ($cfg.accept -and -not $cfg.accept.ContainsKey(([string]$r.state).ToLowerInvariant())) {
            $s.skipped++; $s.lines += "skipped $($r.number): state '$($r.state)' is not accepted (accept = " + ((SortStr @($cfg.accept.Keys)) -join ', ') + ')'
            continue
        }
        $due = WC-iso_date $r['need-date']
        $title = $(if ($r.title.Length) { "$($r.number): $($r.title)" } else { "$($r.number): (no title in Windchill)" })
        $io = O 'title' $title 'description' (WC-body $r $cfg) 'labels' (WcLabels $r $cfg)
        if ($due) { $io.due_date = $due }
        $new = GL-create_issue $gl $p $io
        $s.created++
        $s.lines += "created #" + (Dor $new.iid '?') + " $title"
        $bynum[$r.number] = $new
    }
    $s.lines += "windchill: $($s.rows) rows, $($s.created) created, $($s.skipped) skipped, $($s.drift) drift"
    return $s
}
$script:WC_CLOSES = '(?i)\b(?:close[sd]?|closing|fix(?:e[sd]|ing)?|resolve[sd]?|resolving|implement(?:s|ed|ing)?|refs?|related\s+to)\b\s*:?\s+((?:#\d+(?:\s*(?:,|and)\s*)?)+)'
function WcMrIssues($m) {
    $n = NewH
    foreach ($t in @([string](Dor $m.description ''), [string](Dor $m.title ''))) { foreach ($x in [regex]::Matches($t, $script:WC_CLOSES)) { foreach ($y in [regex]::Matches($x.Groups[1].Value, '#(\d+)')) { $n[$y.Groups[1].Value] = 1 } } }
    if ([string](Dor $m.source_branch '') -cmatch '^(?:[\w.-]+/)?(\d+)-') { $n[$matches[1]] = 1 }
    return , @($n.Keys)
}
function WC-status($gl, $p, $cfg, $o) {
    $iss = Where-L (GL-issues $gl $p (O 'state' 'all')) { param($i) ((L $i.labels) -ccontains $cfg.source) -or (WC-read_marker $i.description) }
    if ($o.since) { $iss = Where-L $iss { param($i) $u = [string](Dor $i.updated_at (Dor $i.created_at '')); if ($u.Length -gt 10) { $u = $u.Substring(0, 10) }; (OrdCmp $u $o.since) -ge 0 } }
    $mrs = NewH
    foreach ($m in (GL-mrs $gl $p (O 'state' 'all'))) { foreach ($k in (WcMrIssues $m)) { Push $mrs $k $m } }
    $rel = NewH; $rl = $null; try { $rl = GL-releases $gl $p } catch { $rl = $null }; foreach ($r in (L $rl)) { $rel[$r.tag_name] = $r }
    $tags = NewH; $rows = @()
    foreach ($i in (SortWith $iss { param($a, $b) NumCmp $a.iid $b.iid })) {
        $m = SortWith $mrs[[string]$i.iid] { param($a, $b) NumCmp $a.iid $b.iid }
        $wf = $null; foreach ($l in (L $i.labels)) { if ([string]$l -cmatch '^workflow::') { $wf = ([string]$l) -creplace '^workflow::', ''; break } }
        $release = ''
        foreach ($mr in (Where-L $m { param($x) $x.state -ceq 'merged' })) {
            $sha = Dor $mr.merge_commit_sha (Dor $mr.squash_commit_sha $mr.sha)
            if ($null -eq $sha) { continue }
            if (-not $tags.ContainsKey($sha)) { $tg = $null; try { $tg = GL-tags_containing $gl $p $sha } catch { $tg = $null }; $tags[$sha] = L $tg }
            $t = L $tags[$sha]
            $rs = SortWith (Map-L (Where-L $t { param($x) $rel.ContainsKey($x) }) { param($x) $rel[$x] }) { param($a, $b) $c = OrdCmp ([string](Dor $a.released_at (Dor $a.created_at ''))) ([string](Dor $b.released_at (Dor $b.created_at ''))); if ($c -ne 0) { $c } else { OrdCmp $a.tag_name $b.tag_name } }
            $name = $(if ($rs.Count) { $rs[0].tag_name } elseif ($t.Count) { (SortStr $t)[0] } else { $null })
            if ($null -ne $name -and (-not $release.Length -or (OrdCmp $name $release) -lt 0)) { $release = $name }
        }
        $rows += , (O 'number' (Dor (WC-number_of $i) '') 'iid' $i.iid 'state' $(if ($i.state -ceq 'opened') { 'open' } else { $i.state }) 'workflow' (Dor $wf '') `
            'milestone' $(if ($i.milestone -is [hashtable]) { Dor $i.milestone.title '' } else { '' }) 'closed' $(if ($i.closed_at) { ([string]$i.closed_at).Substring(0, 10) } else { '' }) `
            'mrs' ((@(foreach ($x in $m) { "!$($x.iid) $($x.state)" })) -join '; ') 'release' $release 'url' (Dor $i.web_url ''))
    }
    return , $rows
}
$script:WC_COLS = @(@('number', 'windchill'), @('iid', 'issue'), @('state', 'state'), @('workflow', 'workflow'), @('milestone', 'milestone'), @('closed', 'closed'), @('mrs', 'merge_requests'), @('release', 'release'), @('url', 'url'))
function WC-status_csv($rows) {
    $o = ((@(foreach ($c in $script:WC_COLS) { $c[1] })) -join ',') + "`r`n"
    foreach ($r in (L $rows)) { $o += ((@(foreach ($c in $script:WC_COLS) { CsvCell $r[$c[0]] })) -join ',') + "`r`n" }
    return $o
}
function WC-status_text($rows) {
    $rows = L $rows
    if ($rows.Count -eq 0) { return "no Windchill requests in GitLab yet (gitlab.pl windchill intake EXPORT.csv)`n" }
    $cs = $script:WC_COLS[0..7]
    $w = @(foreach ($c in $cs) { $mx = $c[1].Length; foreach ($r in $rows) { $l = $(if ($c[0] -ceq 'iid') { ("#$($r.iid)").Length } else { ([string](PStr $r[$c[0]])).Length }); if ($l -gt $mx) { $mx = $l } }; $mx })
    $line = { param($vals) $parts = @(); for ($k = 0; $k -lt $vals.Count; $k++) { $parts += ([string]$vals[$k]).PadRight($w[$k]) }; ($parts -join '  ') + "`n" }
    $out = & $line @(foreach ($c in $cs) { $c[1] })
    foreach ($r in $rows) { $out += & $line @(foreach ($c in $cs) { $v = $(if ($c[0] -ceq 'iid') { "#$($r.iid)" } else { PStr $r[$c[0]] }); if ($v.Length) { $v } else { '-' } }) }
    $out = $out -creplace '(?m) +$', ''
    return $out
}
