# backlog.ps1 -- lib/Backlog.pm: the planning workbook (.xlsx or .csv) <-> GitLab epics, issues and tasks.
# The .xlsx is read and written through ps\ziplib.ps1 (written uncompressed: Excel opens it the same).

$script:BL_COLS = @('ID', 'Level', 'Parent', 'Title', 'Team', 'EPIC', 'Sprint', 'Days', 'Done when', 'Model link', 'Status', 'Marks', 'Iteration', 'Assignee', 'Spent (d)', 'GitLab')
$script:BL_LEVELS = @('Tome', 'Epic', 'Story', 'Task')
$script:BL_KINDS = @('tome', 'epic', 'story', 'task')
$script:BL_STATE_COLOR = O 'TODO' '808082' 'OPEN' '27235D' 'WAIT' 'D6292E' 'HOLD' 'C98500' 'PUNT' 'D6292E' 'DONE' '0CA30C' 'DROP' '555555'
$script:BL_MARKS = @('REDO', 'PASS', 'SYNC')
$script:BL_MARK_COLOR = '6B7436'
function BL-columns($lv) { if ($null -eq $lv) { $lv = $script:BL_LEVELS }; return , @(foreach ($c in $script:BL_COLS) { if ($c -ceq 'EPIC') { $lv[1] } else { $c } }) }
function BL-kind_of($l, $lv) {
    if ($null -eq $lv) { $lv = $script:BL_LEVELS }
    $l = ([string](Dor $l '')).ToLowerInvariant().Trim()
    for ($k = 0; $k -lt 4; $k++) {
        $n = ([string]$lv[$k]).ToLowerInvariant()
        if ($l -ceq $n -or ($k -eq 1 -and ($l -ceq 'epic' -or $l -ceq 'epoch') -and ($n -ceq 'epic' -or $n -ceq 'epoch'))) { return $script:BL_KINDS[$k] }
    }
    return $null
}
function BL-config($c, $o) {
    $b = NewH; foreach ($x in (L $c.backlog)) { $b[$x[0].ToLowerInvariant()] = $x[1] }
    $pr = KV $c.project
    $levels = Dor $o.levels $b.levels
    $lv = $(if ($null -ne $levels) { @(foreach ($x in ([string]$levels -split ',')) { $y = $x.Trim(); if ($y.Length) { $y } }) } else { $script:BL_LEVELS })
    if ($lv.Count -ne 4) { throw "Backlog: levels are four names, top down (Tome, Epic, Story, Task), not '" + (Dor $levels '') + "'`n" }
    $num = Dor $b.sprint 'project'
    if ($num -cnotmatch '^(project|epic)$') { throw "Backlog: [backlog] sprint is project or epic, not '$num'`n" }
    $sp = First $c.milestones { param($x) $x[0] -ceq 'sprints' }
    $start = $null; $weeks = $null; $prefix = $null
    if ($sp) { $w = SplitWs $sp[1] 4; $start = $w[0]; if ($w.Count -gt 2) { $weeks = $w[2] }; if ($w.Count -gt 3) { $prefix = $w[3] } }
    $p = Dor $o.project $pr.path
    $st = $(if ($c.statuses) { ParseStatuses $c.statuses 'project file' $p } else { $null })
    $grp = Dor $o.group (Dor $b.group $(if ($null -ne $p -and $p -cmatch '^(.*)/') { $matches[1] } else { $null }))
    return (O 'levels' $lv 'group' $grp 'numbering' $num 'per_epic' (PNum (Dor $b['sprints-per-epic'] 13)) 'team' (Dor $b['team-label'] 'team::') `
        'start' (Dor $o.start (Dor $b.start $start)) 'weeks' (PNum (Dor $weeks 2)) 'prefix' (Dor $prefix 'Sprint ') `
        'status_mode' $(if (-not $st -or (L $st.statuses).Count -eq 0) { 'none' } else { $st.mode }) 'status_names' (Map-L $(if ($st) { $st.statuses } else { @() }) { param($s) $s.name }))
}
function HexVal([string]$h) { $n = 0; foreach ($ch in $h.ToUpperInvariant().ToCharArray()) { $c = [int]$ch; if ($c -ge 65) { $c = $c - 55 } else { $c = $c - 48 }; $n = $n * 16 + $c }; return $n }
function XmlUnesc($s) {
    $s = [string](Dor $s '')
    if ($s.IndexOf('&') -lt 0) { return $s }
    $o = ''; $pos = 0
    foreach ($m in [regex]::Matches($s, '&#x([0-9A-Fa-f]+);|&#(\d+);|&(lt|gt|quot|apos|amp);')) {
        $o += $s.Substring($pos, $m.Index - $pos)
        if ($m.Groups[1].Success) { $o += [string][char](HexVal $m.Groups[1].Value) }
        elseif ($m.Groups[2].Success) { $o += [string][char][int]$m.Groups[2].Value }
        else { $o += @{ 'lt' = '<'; 'gt' = '>'; 'quot' = '"'; 'apos' = "'"; 'amp' = '&' }[$m.Groups[3].Value] }
        $pos = $m.Index + $m.Length
    }
    return $o + $s.Substring($pos)
}
function BL-member([string]$file, [string]$name) {
    $b = $null
    try { $b = Read-ZipEntry -Path $file -Name $name } catch { return $null }
    if ($null -eq $b) { return $null }
    if ($b.Length -eq 0) { return '' }
    return (Zl-Utf8Dec $b 0 $b.Length)
}
function ColIndex([string]$c) { $n = 0; foreach ($ch in $c.ToUpperInvariant().ToCharArray()) { $n = $n * 26 + ([int]$ch - 64) }; return $n - 1 }
function BL-read_xlsx([string]$file, $o) {
    $wb = BL-member $file 'xl/workbook.xml'
    if ($null -eq $wb) { throw "Backlog: $file is not an .xlsx workbook (no xl/workbook.xml)`n" }
    $sheets = @(foreach ($m in [regex]::Matches($wb, '<sheet\b([^>]*)/?>')) { $a = NewH; foreach ($x in [regex]::Matches($m.Groups[1].Value, '(\w+(?::\w+)?)="([^"]*)"')) { $a[$x.Groups[1].Value] = $x.Groups[2].Value }; O 'name' (XmlUnesc $a['name']) 'rid' $a['r:id'] })
    if ($sheets.Count -eq 0) { throw "Backlog: $file has no sheets`n" }
    $want = Dor $o.sheet 'Backlog'
    $sh = First $sheets { param($s) ([string]$s.name).ToLowerInvariant() -ceq ([string]$want).ToLowerInvariant() }; if (-not $sh) { $sh = $sheets[0] }
    $rels = Dor (BL-member $file 'xl/_rels/workbook.xml.rels') ''
    $tgt = NewH; foreach ($m in [regex]::Matches($rels, '<Relationship\b([^>]*)/?>')) { $a = NewH; foreach ($x in [regex]::Matches($m.Groups[1].Value, '(\w+)="([^"]*)"')) { $a[$x.Groups[1].Value] = $x.Groups[2].Value }; $tgt[[string]$a.Id] = $a.Target }
    $t = Dor $tgt[[string](Dor $sh.rid '')] 'worksheets/sheet1.xml'
    $t = $t -creplace '^/', ''; if ($t -cnotmatch '^xl/') { $t = "xl/$t" }
    $xml = BL-member $file $t
    if ($null -eq $xml) { throw "Backlog: ${file}: no $t for sheet '$($sh.name)'`n" }
    $ss = @()
    $sst = BL-member $file 'xl/sharedStrings.xml'
    if ($null -ne $sst) { foreach ($si in [regex]::Matches($sst, '(?s)<si>(.*?)</si>')) { $x = [regex]::Replace($si.Groups[1].Value, '(?s)<rPh\b.*?</rPh>', ''); $ss += ((@(foreach ($m in [regex]::Matches($x, '(?s)<t(?:\s[^>]*)?>(.*?)</t>')) { XmlUnesc $m.Groups[1].Value })) -join '') } }
    $grid = @()
    foreach ($rm in [regex]::Matches($xml, '(?s)<row\b[^>]*?(?:/>|>(.*?)</row>)')) {
        $body = $rm.Groups[1].Value
        $r = @()
        foreach ($cm in [regex]::Matches($body, '(?s)<c\b([^>]*?)(?:/>|>(.*?)</c>)')) {
            $attr = $cm.Groups[1].Value; $in = $cm.Groups[2].Value
            $ref = $null; if ($attr -cmatch '\br="([A-Z]+)\d+"') { $ref = $matches[1] }
            $ty = $null; if ($attr -cmatch '\bt="(\w+)"') { $ty = $matches[1] }
            $v = $null
            if ($ty -ceq 'inlineStr') { $v = (@(foreach ($m in [regex]::Matches($in, '(?s)<t(?:\s[^>]*)?>(.*?)</t>')) { XmlUnesc $m.Groups[1].Value })) -join '' }
            elseif ($in -cmatch '(?s)<v>(.*?)</v>') { $v = XmlUnesc $matches[1]; if ($ty -ceq 's') { $v = Dor $ss[[int]$v] '' }; if ($ty -ceq 'b') { $v = $(if (Tru $v) { 'TRUE' } else { 'FALSE' }) } }
            if ($null -ne $v -and $null -eq $ty -and $v -cmatch '^-?\d+(?:\.\d+)?(?:[eE][-+]?\d+)?$' -and $v -cmatch '[.eE]') { $v = PStr ([double]$v) }
            $i = $(if ($null -ne $ref) { ColIndex $ref } else { $r.Count })
            while ($r.Count -le $i) { $r += , $null }
            $r[$i] = $v
        }
        $grid += , $r
    }
    return (O 'sheet' $sh.name 'grid' $grid)
}
function BL-read_file([string]$file, $o) {
    if ($null -eq $o) { $o = NewH }
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { throw "Backlog: cannot read ${file}: no such file`n" }
    if ($file -match '(?i)\.xlsx$') { $g = BL-read_xlsx $file $o }
    elseif ($file -match '(?i)\.(csv|txt)$') { $g = O 'sheet' $null 'grid' (WC-parse_csv (WC-decode_bytes (Zl-ReadBytes $file))) }
    else { throw "Backlog: ${file}: give an .xlsx or a .csv file`n" }
    $grid = L $g.grid
    $k = 0; while ($k -lt $grid.Count -and -not (@($grid[$k] | Where-Object { $null -ne $_ -and [string]$_ -cmatch '\S' }).Count)) { $k++ }
    $head = @(); if ($k -lt $grid.Count) { $head = @(foreach ($h in $grid[$k]) { ([string](Dor $h '')).Trim() }); $k++ }
    if (-not (($head -ccontains 'ID') -and ($head -ccontains 'Level') -and ($head -ccontains 'Title'))) {
        throw ("Backlog: $file" + $(if ($null -ne $g.sheet) { " (sheet $($g.sheet))" } else { '' }) + ": the header needs ID, Level and Title columns (found: " + ($head -join ' ') + ")`n")
    }
    $rows = @()
    for (; $k -lt $grid.Count; $k++) {
        $r = $grid[$k]
        $h = NewH
        for ($i = 0; $i -lt $head.Count; $i++) { $v = $(if ($i -lt $r.Count) { $r[$i] } else { $null }); $h[$head[$i]] = $(if ($null -ne $v) { ([string]$v).Trim() } else { '' }) }
        if (-not ([string](Dor $h.ID '')).Length -and -not ([string](Dor $h.Title '')).Length) { continue }
        $rows += , $h
    }
    return (O 'header' $head 'rows' $rows 'sheet' $g.sheet 'file' $file)
}
function XmlEsc($s) { $s = [string](Dor $s ''); $s = $s.Replace('&', '&amp;').Replace('<', '&lt;').Replace('>', '&gt;').Replace('"', '&quot;'); return ($s -creplace '[\x00-\x08\x0B\x0C\x0E-\x1F]', '') }
function ColName([int]$i) { $s = ''; $i++; while ($i -gt 0) { $m = ($i - 1) % 26; $s = [string][char](65 + $m) + $s; $i = [int](Trunc (($i - 1) / 26)) }; return $s }
function BL-write_xlsx([string]$file, $head, $rows) {
    $st = SortStr @($script:BL_STATE_COLOR.Keys)
    $fill = NewH; for ($i = 0; $i -lt $st.Count; $i++) { $fill[$st[$i]] = $i + 2 }
    $styles = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' + "`n" +
        '<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">' +
        '<fonts count="4"><font><sz val="11"/><name val="Calibri"/></font><font><b/><sz val="11"/><color rgb="FFFFFFFF"/><name val="Calibri"/></font>' +
        '<font><b/><sz val="11"/><color rgb="FF' + $script:BL_MARK_COLOR + '"/><name val="Calibri"/></font><font><b/><sz val="11"/><name val="Calibri"/></font></fonts>' +
        '<fills count="' + (2 + $st.Count + 1) + '"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill>' +
        ((@(foreach ($s in $st) { '<fill><patternFill patternType="solid"><fgColor rgb="FF' + $script:BL_STATE_COLOR[$s] + '"/><bgColor indexed="64"/></patternFill></fill>' })) -join '') +
        '<fill><patternFill patternType="solid"><fgColor rgb="FF1F3A5F"/><bgColor indexed="64"/></patternFill></fill></fills>' +
        '<borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders>' +
        '<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>' +
        '<cellXfs count="' + (3 + $st.Count + 1) + '"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>' +
        '<xf numFmtId="0" fontId="1" fillId="' + (2 + $st.Count) + '" borderId="0" xfId="0" applyFont="1" applyFill="1"/>' +
        '<xf numFmtId="0" fontId="2" fillId="0" borderId="0" xfId="0" applyFont="1"/>' +
        ((@(foreach ($s in $st) { '<xf numFmtId="0" fontId="1" fillId="' + $fill[$s] + '" borderId="0" xfId="0" applyFont="1" applyFill="1"/>' })) -join '') +
        '<xf numFmtId="0" fontId="3" fillId="0" borderId="0" xfId="0" applyFont="1"/>' +
        '</cellXfs><cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles></styleSheet>'
    $sx = NewH; for ($i = 0; $i -lt $st.Count; $i++) { $sx[$st[$i]] = 3 + $i }
    $bold = 3 + $st.Count
    $width = O 'ID' 18 'Level' 8 'Parent' 18 'Title' 48 'Team' 12 'Sprint' 7 'Days' 6 'Done when' 40 'Model link' 28 'Status' 8 'Marks' 10 'Iteration' 11 'Assignee' 11 'Spent (d)' 9 'GitLab' 40
    $head = L $head
    $sheet = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' + "`n" +
        '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">' +
        '<sheetViews><sheetView workbookViewId="0"><pane ySplit="1" topLeftCell="A2" activePane="bottomLeft" state="frozen"/></sheetView></sheetViews>' +
        '<cols>' + ((@(for ($i = 0; $i -lt $head.Count; $i++) { $w = Dor $width[$head[$i]] 14; '<col min="' + ($i + 1) + '" max="' + ($i + 1) + "`" width=`"$w`" customWidth=`"1`"/>" })) -join '') + '</cols><sheetData>'
    $all = @(, @(foreach ($h in $head) { O 'v' $h 's' 1 }))
    foreach ($row in (L $rows)) {
        $k = ([string](Dor $row.Level '')).ToLowerInvariant()
        $all += , @(foreach ($h in $head) {
            $v = $row[$h]
            $s = 0
            if ($h -ceq 'Status' -and $sx.ContainsKey(([string](Dor $v '')).ToUpperInvariant())) { $s = $sx[([string]$v).ToUpperInvariant()] }
            elseif ($h -ceq 'Marks' -and ([string](Dor $v '')).Length) { $s = 2 }
            elseif (($h -ceq 'Title' -or $h -ceq 'ID') -and $k -cmatch '^(tome|epic|epoch)$') { $s = $bold }
            O 'v' $v 's' $s })
    }
    $n = 0
    foreach ($r in $all) {
        $n++
        $sheet += "<row r=`"$n`">"
        for ($i = 0; $i -lt $r.Count; $i++) {
            $v = $r[$i].v; $s = $r[$i].s
            if ($null -eq $v -or ([string]$v).Length -eq 0) { continue }
            $ref = (ColName $i) + $n
            $sa = $(if ($s) { " s=`"$s`"" } else { '' })
            if ($n -gt 1 -and [string]$v -cmatch '^-?\d+(?:\.\d+)?$' -and $head[$i] -cmatch '^(Sprint|Days|Spent \(d\))$') { $sheet += "<c r=`"$ref`"$sa><v>$v</v></c>" }
            else { $sheet += "<c r=`"$ref`"$sa t=`"inlineStr`"><is><t xml:space=`"preserve`">" + (XmlEsc $v) + '</t></is></c>' }
        }
        $sheet += '</row>'
    }
    $sheet += '</sheetData><autoFilter ref="A1:' + (ColName ($head.Count - 1)) + $n + '"/></worksheet>'
    $ct = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' + "`n" +
        '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>' +
        '<Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>' +
        '<Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>' +
        '<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/></Types>'
    $rr = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' + "`n" +
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>'
    $wbx = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' + "`n" +
        '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">' +
        '<sheets><sheet name="Backlog" sheetId="1" r:id="rId1"/></sheets><definedNames><definedName name="_xlnm._FilterDatabase" localSheetId="0" hidden="1">Backlog!$A$1:$' +
        (ColName ($head.Count - 1)) + '$' + $n + '</definedName></definedNames></workbook>'
    $wr = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' + "`n" +
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>' +
        '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/></Relationships>'
    $ent = [ordered]@{}
    $ent['[Content_Types].xml'] = [byte[]](Utf8B $ct)
    $ent['_rels/.rels'] = [byte[]](Utf8B $rr)
    $ent['xl/workbook.xml'] = [byte[]](Utf8B $wbx)
    $ent['xl/_rels/workbook.xml.rels'] = [byte[]](Utf8B $wr)
    $ent['xl/styles.xml'] = [byte[]](Utf8B $styles)
    $ent['xl/worksheets/sheet1.xml'] = [byte[]](Utf8B $sheet)
    Write-Zip -Path $file -Entries $ent
}
function BL-write_file([string]$file, $rows, $o) {
    $head = BL-columns $o.levels
    $epic = $head[5]
    $out = Map-L $rows { param($r) $h = NewH; foreach ($c in $head) { $h[$c] = $(if ($c -ceq $epic) { Dor $r[$epic] (Dor $r['Epic'] $r['Epoch']) } else { $r[$c] }) }; $h }
    if ($file -match '(?i)\.xlsx$') { BL-write_xlsx $file $head $out; return }
    if ($file -notmatch '(?i)\.csv$') { throw "Backlog: ${file}: write an .xlsx or a .csv file`n" }
    $hr = NewH; foreach ($c in $head) { $hr[$c] = $c }
    $lines = @(foreach ($r in (@(, $hr) + $out)) { (@(foreach ($c in $head) { CsvCell $r[$c] })) -join ',' })
    $b = Utf8B (($lines -join "`r`n") + "`r`n")
    $all = [byte[]]::new($b.Length + 3); $all[0] = 0xEF; $all[1] = 0xBB; $all[2] = 0xBF
    for ($i = 0; $i -lt $b.Length; $i++) { $all[$i + 3] = $b[$i] }
    Zl-WriteBytes $file $all
}
function YmdEpoch($s) { if ([string](Dor $s '') -cnotmatch '^(\d{4})-(\d\d)-(\d\d)') { return $null }; return (TimeGm 0 0 12 ([long]$matches[3]) ([long]$matches[2] - 1) ([long]$matches[1])) }
function BL-sprint_of($cfg, $cell, $k) {
    if ($null -eq $cell -or [string]$cell -cnotmatch '^\s*(\d+)') { return , @() }
    $n = [long]$matches[1] + $(if ($cfg.numbering -ceq 'epic') { (PNum (Dor $k 0)) * $cfg.per_epic } else { 0 })
    $t0 = YmdEpoch (Dor $cfg.start '')
    if ($null -eq $t0) { return , @($n, $null) }
    return , @($n, (DateT ($t0 + (($n - 1) * $cfg.weeks * 7 + $cfg.weeks * 7 - 3) * 86400)))
}
function BL-split_title($t) {
    $t = [string](Dor $t '')
    if ($t -cmatch '(?s)^(\S*[\d.\-_]\S*)\s+(.*)$' -and $matches[1] -cnotmatch '[:;,]$') { return , @($matches[1], $matches[2]) }
    return , @($null, $t)
}
function BL-grab($d, $k) { foreach ($l in ([string](Dor $d '') -split "`n")) { if ($l -cmatch ('^\*\*' + [regex]::Escape($k) + ':\*\*\s*(.*)$')) { return $matches[1].Trim() } }; return '' }
function BL-days($v) { if ($null -eq $v -or ([string]$v).Length -eq 0) { return '' }; $d = (PNum $v) / 28800; if ($d -eq (Trunc $d)) { return [long](Trunc $d) }; return (PNum (FmtF $d 2)) }
function BL-import_rows($gl, $p, $rows, $cfg) {
    $g = $cfg.group; if ($null -eq $g) { throw "Backlog: no group for the epics: [backlog] group = PATH (or [project] path = group/name)`n" }
    $log = @(); $warn = @(); $made = O 'epic' 0 'issue' 0 'task' 0; $skipped = 0
    $dry = $gl.dry_run
    $byid = NewH
    $ge = $null; try { $ge = GL-work_items $gl $g (O 'kind' 'group' 'types' @('Epic')) } catch { $ge = $null }
    foreach ($e in (L $ge)) { $id = (BL-split_title $e.title)[0]; if ($null -ne $id) { $byid["e:$id"] = $e } }
    foreach ($i in (GL-work_items $gl $p (O 'kind' 'project' 'types' @('Issue', 'Task')))) { $id = (BL-split_title $i.title)[0]; if ($null -ne $id) { $byid[$(if ($i.type -ceq 'Task') { 't:' } else { 'i:' }) + $id] = $i } }
    $ms = NewH; if (-not ($dry -and -not (GL-is_local $gl))) { foreach ($m in (GL-milestones $gl $p)) { $ms[$m.title] = $m } }
    $lab = NewH; if (-not ($dry -and -not (GL-is_local $gl))) { foreach ($l in (GL-labels $gl $p)) { $lab[$l.name] = 1 } }
    $statusok = NewH; foreach ($n in (L $cfg.status_names)) { $statusok[([string]$n).ToUpperInvariant()] = $n }
    $ref = NewH; $epicindex = NewH; $odd = NewH; $ei = 0
    $epiccol = $cfg.levels[1]
    foreach ($r in (L $rows)) {
        $kind = BL-kind_of $r.Level $cfg.levels
        $id = [string](Dor $r.ID '')
        if (-not $kind) { $warn += "row ${id}: level '" + (Dor $r.Level '') + "' is not one of " + ((L $cfg.levels) -join ', ') + ': skipped'; continue }
        if (-not $id.Length) { $warn += "a $kind row without an ID ('" + (Dor $r.Title '') + "'): skipped"; continue }
        $title = "$id " + (Dor $r.Title '')
        $state = ([string](Dor $r.Status '')).ToUpperInvariant(); if (-not $state) { $state = 'TODO' }
        if (-not $script:BL_STATE_COLOR.ContainsKey($state) -and -not $statusok.ContainsKey($state)) { $odd[$r.Status] = [long](Dor $odd[$r.Status] 0) + 1; $state = 'TODO' }
        $marks = @(foreach ($m in (([string](Dor $r.Marks '')).ToUpperInvariant() -split '[\s,;]+')) { if ($script:BL_MARKS -ccontains $m) { $m } })
        $dparts = @(); if (([string](Dor $r['Done when'] '')).Length) { $dparts += "**Done when:** $($r['Done when'])" }; if (([string](Dor $r['Model link'] '')).Length) { $dparts += "**Model link:** $($r['Model link'])" }
        $desc = $dparts -join "`n`n"
        $setstate = { param($what, $it)
            if ($state -ceq 'TODO' -and $cfg.status_mode -ceq 'none') { return }
            if ($what -ceq 'epic') { if ($state -cmatch '^(DONE|DROP)$') { $null = GL-set_epic_status $gl $g $it.id $state (O 'mode' 'close') }; return }
            if ($cfg.status_mode -ceq 'none') { if ($state -cmatch '^(DONE|DROP)$') { $null = GL-update_issue $gl $p $it.iid (O 'state_event' 'close') }; return }
            if ($state -ceq 'TODO') { return }
            $name = $statusok[$state]
            if ($null -eq $name) { $script:BLWARN += "row ${id}: state '$state' is not in [statuses]: left as is"; return }
            try { $null = GL-set_item_status $gl $p $it.iid $name (O 'mode' $cfg.status_mode 'gid' $it.id) }
            catch { $script:BLWARN += "row ${id}: status $name not set (" + (([string]$_.Exception.Message -creplace '^GitLab: ', '') -replace "`n$", '') + ')' }
        }
        $script:BLWARN = @()
        if ($kind -ceq 'tome' -or $kind -ceq 'epic') {
            if ($kind -ceq 'epic') { $epicindex[$id] = $ei; $ei++ }
            $e = $byid["e:$id"]
            if ($e) { $ref[$id] = $e; $skipped++; $log += "= epic $title"; continue }
            $parent = $null
            if ($kind -ceq 'epic' -and ([string](Dor $r.Parent '')).Length) { $parent = $ref[$r.Parent] }
            if ($kind -ceq 'epic' -and ([string](Dor $r.Parent '')).Length -and -not $parent) { $warn += "row ${id}: parent $($r.Parent) not found above it: made without a parent" }
            $edp = @(); if ($desc.Length) { $edp += $desc }; if ($state -cne 'TODO') { $edp += "**State:** $state" }
            $ed = $edp -join "`n`n"
            $wo = O 'kind' 'group' 'type' 'Epic' 'title' $title; if ($ed.Length) { $wo.description = $ed }; if ($parent) { $wo.parent = $parent.id }
            $e = GL-create_work_item $gl $g $wo
            $ref[$id] = $e; $made.epic++
            $log += "+ epic $title" + $(if ($parent) { " (under $($r.Parent))" } else { '' })
            & $setstate 'epic' $e
        } elseif ($kind -ceq 'story') {
            $i = $byid["i:$id"]
            if ($i) { $ref[$id] = $i; $skipped++; $log += "= issue $title"; continue }
            $ek = [string](Dor $r[$epiccol] (Dor $r.Epic (Dor $r.Epoch '')))
            $epic = Dor $ref[$(if (([string](Dor $r.Parent '')).Length) { $r.Parent } else { $ek })] $(if ($ek.Length) { $ref[$ek] } else { $null })
            $so = BL-sprint_of $cfg $r.Sprint (Dor $epicindex[$ek] $epicindex[[string](Dor $r.Parent '')])
            $n = $(if ($so.Count) { $so[0] } else { $null }); $due = $(if ($so.Count -gt 1) { $so[1] } else { $null })
            $mt = $(if ($null -ne $n) { "$($cfg.prefix)$n" } else { $null })
            $labels = @()
            if (([string](Dor $r.Team '')).Length -and ([string]$cfg.team).Length) {
                $tl = "$($cfg.team)$($r.Team)"
                if (-not $lab.ContainsKey($tl)) { $null = GL-create_label $gl $p $tl '#2f5d8a' "Team $($r.Team)"; $lab[$tl] = 1; $log += "+ label $tl" }
                $labels += $tl
            }
            foreach ($m in $marks) { if (-not $lab.ContainsKey($m)) { $null = GL-create_label $gl $p $m '#6b7436' "Mark: $m"; $lab[$m] = 1; $log += "+ label $m" }; $labels += $m }
            $days = $r.Days
            $io = O 'title' $title 'description' $desc
            if ($labels.Count) { $io.labels = $labels -join ',' }
            if ($null -ne $days -and [string]$days -cmatch '^\d+(\.\d+)?$') { $io.weight = Trunc ((PNum $days) + 0.5) }
            if ($due) { $io.due_date = $due }
            if ($null -ne $mt -and $ms.ContainsKey($mt)) { $io.milestone = $mt }
            $i = GL-create_issue $gl $p $io
            $i = Copy-H $i; $i.id = WiGid (Dor $i.id 0)
            $ref[$id] = $i; $made.issue++
            $log += "+ issue $title" + $(if ($null -ne $n) { " (sprint $n" + $(if ($ms.ContainsKey([string](Dor $mt ''))) { '' } else { ', no milestone' }) + $(if ($null -ne $days -and ([string]$days).Length) { ", $days d" } else { '' }) + ')' } else { '' })
            if ($epic) { $null = GL-set_work_item_parent $gl $p $i.id $epic.id }
            $want = $(if ($ek) { $ek } else { [string](Dor $r.Parent '') })
            if (-not $epic -and $want.Length) { $warn += "row ${id}: epic '$want' not found above it: the issue has no epic" }
            & $setstate 'issue' $i
        } else {
            if ($byid["t:$id"]) { $skipped++; $log += "= task $title"; continue }
            $parent = $ref[[string](Dor $r.Parent '')]
            if (-not $parent) { $warn += "row ${id}: task without its story (Parent '" + (Dor $r.Parent '') + "' not above it): skipped"; continue }
            $days = $r.Days
            $wo = O 'kind' 'project' 'type' 'Task' 'title' $title 'parent' $parent.id
            if ($desc.Length) { $wo.description = $desc }
            if ($null -ne $days -and [string]$days -cmatch '^\d+(\.\d+)?$') { $wo.estimate = Trunc ((PNum $days) * 28800 + 0.5) }
            $t = GL-create_work_item $gl $p $wo
            $made.task++
            $log += "+ task $title" + $(if ($null -ne $days -and ([string]$days).Length) { " ($days d)" } else { '' })
            & $setstate 'task' $t
        }
        $warn += @($script:BLWARN)
    }
    if ($odd.Count) { $warn += ((@(foreach ($k in (SortStr @($odd.Keys))) { "'$k' ($($odd[$k]))" })) -join ', ') + ': not one of the states (' + ((SortStr @($script:BL_STATE_COLOR.Keys)) -join ' ') + '): taken as TODO' }
    return (O 'log' $log 'made' $made 'skipped' $skipped 'warnings' $warn)
}
function BL-export_rows($gl, $p, $cfg) {
    $g = $cfg.group
    $tl = $cfg.levels[0]; $el = $cfg.levels[1]; $sl = $cfg.levels[2]; $kl = $cfg.levels[3]
    $epics = @(); if ($null -ne $g) { try { $epics = L (GL-work_items $gl $g (O 'kind' 'group' 'types' @('Epic'))) } catch { $epics = @() } }
    $items = L (GL-work_items $gl $p (O 'kind' 'project' 'types' @('Issue', 'Task')))
    $ix = NewH; foreach ($x in ($epics + $items)) { $ix[[string]$x.id] = $x }
    $rid = { param($x) $id = (BL-split_title $x.title)[0]; if ($null -ne $id) { $id } else { $(if ($x.type -ceq 'Epic') { '&' } else { '#' }) + $x.iid } }
    $rtitle = { param($x) (BL-split_title $x.title)[1] }
    $state = { param($x)
        $s = $x.status
        if ($null -eq $s) { foreach ($l in (L $x.labels)) { if ([string]$l -cmatch '^state::') { $s = ([string]$l).Substring(7); break } } }
        if ($null -eq $s -and $x.type -ceq 'Epic') { $s = BL-grab $x.description 'State'; if (-not $s) { $s = $null } }
        if ($null -ne $s -and $script:BL_STATE_COLOR.ContainsKey(([string]$s).ToUpperInvariant())) { ([string]$s).ToUpperInvariant() }
        elseif ($null -ne $s -and ([string]$s).Length) { $s }
        elseif ($x.state -ceq 'closed') { 'DONE' } else { 'TODO' }
    }
    $marks = { param($x) (@(foreach ($m in $script:BL_MARKS) { if ((L $x.labels) -ccontains $m) { $m } })) -join ' ' }
    $sprint = { param($m) $m = [string](Dor $m ''); if ($m -cmatch ('^' + [regex]::Escape($cfg.prefix) + '(\d+)$')) { $matches[1] } else { '' } }
    $team = { param($x) $pre = [string](Dor $cfg.team 'team::'); $t = $null; if ($pre.Length) { foreach ($l in (L $x.labels)) { if ([string]$l -cmatch ('^' + [regex]::Escape($pre))) { $t = $l; break } } }; if ($null -ne $t) { ([string]$t).Substring($pre.Length) } else { '' } }
    $kids = NewH; $script:BLROWS = @()
    foreach ($x in (SortWith ($epics + $items) { param($a, $b) NumCmp (Dor $a.iid 0) (Dor $b.iid 0) })) { Push $kids ([string](Dor $x.parent '')) $x }
    $base = { param($x, $level, $parent)
        O 'ID' (& $rid $x) 'Level' $level 'Parent' $(if ($parent) { & $rid $parent } else { '' }) 'Title' (& $rtitle $x) 'Done when' (BL-grab $x.description 'Done when') `
          'Model link' (BL-grab $x.description 'Model link') 'Status' (& $state $x) 'Marks' (& $marks $x) 'GitLab' (Dor $x.web_url '') }
    $story = { param($s, $epic)
        $r = & $base $s $sl $epic
        $r.Team = & $team $s; $r[$el] = $(if ($epic) { & $rid $epic } else { '' }); $r.Sprint = & $sprint $s.milestone
        $r.Days = Dor $s.weight ''; $r.Iteration = Dor $s.iteration ''; $r.Assignee = (L $s.assignees) -join ' '; $r['Spent (d)'] = BL-days $s.spent
        $script:BLROWS += , $r
        foreach ($t in (Where-L $kids[[string]$s.id] { param($y) $y.type -ceq 'Task' })) {
            $q = & $base $t $kl $s
            $q.Team = & $team $s; $q[$el] = $(if ($epic) { & $rid $epic } else { '' }); $q.Days = BL-days $t.estimate
            $q.Assignee = (L $t.assignees) -join ' '; $q['Spent (d)'] = BL-days $t.spent; $q.Sprint = ''
            $script:BLROWS += , $q
        }
    }
    $script:BLEPIC = { param($e, $parent, $depth)
        $script:BLROWS += , (& $base $e $(if ($depth) { $el } else { $tl }) $parent)
        foreach ($k in (L $kids[[string]$e.id])) {
            if ($k.type -ceq 'Epic') { & $script:BLEPIC $k $e 1 }
            elseif ($k.type -ceq 'Issue') { & $story $k $e }
        }
    }
    foreach ($e in $epics) { if ($null -eq $e.parent -or -not $ix.ContainsKey([string]$e.parent)) { & $script:BLEPIC $e $null 0 } }
    $loose = Where-L $items { param($x) $x.type -ceq 'Issue' -and ($null -eq $x.parent -or -not $ix.ContainsKey([string]$x.parent)) }
    if ($loose.Count) {
        $script:BLROWS += , (O 'ID' 'UNPLANNED' 'Level' $el 'Parent' '' 'Title' 'Issues with no epic' 'Status' 'OPEN')
        $from = $script:BLROWS.Count
        foreach ($x in $loose) { & $story $x $null }
        for ($i = $from; $i -lt $script:BLROWS.Count; $i++) { if ($script:BLROWS[$i].Level -ceq $sl) { $script:BLROWS[$i].Parent = 'UNPLANNED'; $script:BLROWS[$i][$el] = 'UNPLANNED' } }
    }
    return , $script:BLROWS
}
