<#
ci-reports.ps1 -- the kit's model checks as the report files GitLab shows on a merge request (tools/gitlab/ci-reports.pl).

Windows PowerShell 5.1, Constrained Language Mode safe, pure ASCII; the same files, byte for byte, as the Perl tool.

  ci-reports.cmd grammar [--junit F] [--codequality F] LOG [FILE...]      LOG = sysml check output; FILEs = what was checked
  ci-reports.cmd lint    [--junit F] [--codequality F] [--metrics F] LOG  LOG = model lint output
  ci-reports.cmd outline [--junit F] [--codequality F] [--metrics F] LOG  LOG = model check output
  ci-reports.cmd todo    [--junit F] [--codequality F] [--metrics F] DIR|LOG   a model directory, or grep -rn '// TODO' output
  ci-reports.cmd trace   [--junit F] [--metrics F] LOG                    LOG = reqif2sysml --report --model output
  (LOG may be - for standard input)

--junit writes JUnit XML, --codequality Code Quality JSON (fingerprint = MD5 of path, check and message, computed
here in plain PowerShell), --metrics "name value" lines. The script only reports: exit 0, or 2 when its input cannot
be read or is not the expected checker output.
#>

$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------- bytes and UTF-8
function CrUtf8Enc([string]$s) {
    $buf = [byte[]]::new($s.Length * 3 + 4); $n = 0
    for ($i = 0; $i -lt $s.Length; $i++) {
        $c = [int]$s[$i]
        if ($c -ge 0xD800 -and $c -le 0xDBFF -and $i + 1 -lt $s.Length) { $c = 0x10000 + (($c - 0xD800) -shl 10) + ([int]$s[$i + 1] - 0xDC00); $i++ }
        if ($c -lt 0x80) { $buf[$n++] = $c }
        elseif ($c -lt 0x800) { $buf[$n++] = 0xC0 -bor ($c -shr 6); $buf[$n++] = 0x80 -bor ($c -band 0x3F) }
        elseif ($c -lt 0x10000) { $buf[$n++] = 0xE0 -bor ($c -shr 12); $buf[$n++] = 0x80 -bor (($c -shr 6) -band 0x3F); $buf[$n++] = 0x80 -bor ($c -band 0x3F) }
        else { $buf[$n++] = 0xF0 -bor ($c -shr 18); $buf[$n++] = 0x80 -bor (($c -shr 12) -band 0x3F); $buf[$n++] = 0x80 -bor (($c -shr 6) -band 0x3F); $buf[$n++] = 0x80 -bor ($c -band 0x3F) }
    }
    $o = [byte[]]::new($n); if ($n) { [Array]::Copy($buf, $o, $n) }
    return , $o
}
function CrUtf8Dec([byte[]]$b) {
    $n = $b.Length; if ($n -eq 0) { return '' }
    $o = [char[]]::new($n * 2); $k = 0; $i = 0
    while ($i -lt $n) {
        $c = [int]$b[$i]
        if ($c -lt 0x80) { $o[$k++] = [char]$c; $i++; continue }
        $len = 0; $cp = 0
        if ($c -ge 0xC2 -and $c -le 0xDF) { $len = 2; $cp = $c -band 0x1F } elseif ($c -ge 0xE0 -and $c -le 0xEF) { $len = 3; $cp = $c -band 0x0F } elseif ($c -ge 0xF0 -and $c -le 0xF4) { $len = 4; $cp = $c -band 0x07 }
        $ok = $len -gt 0 -and $i + $len -le $n
        if ($ok) { for ($j = 1; $j -lt $len; $j++) { $x = [int]$b[$i + $j]; if (($x -band 0xC0) -ne 0x80) { $ok = $false; break }; $cp = ($cp -shl 6) -bor ($x -band 0x3F) } }
        if (-not $ok) { $o[$k++] = [char]$c; $i++; continue }
        if ($cp -ge 0x10000) { $cp -= 0x10000; $o[$k++] = [char](0xD800 + ($cp -shr 10)); $o[$k++] = [char](0xDC00 + ($cp -band 0x3FF)) } else { $o[$k++] = [char]$cp }
        $i += $len
    }
    return (-join $o[0..($k - 1)])
}
function CrWrite([string]$path, [string]$text) {
    try { Set-Content -LiteralPath $path -Encoding Byte -Value (CrUtf8Enc $text) -ErrorAction Stop }
    catch { CrDie ("ci-reports: cannot write " + $path + ": " + $_.Exception.Message + "`n") }
}
function CrDie([string]$m) { throw ('CRDIE:' + $m) }
function CrSlurp([string]$p) {
    if ($p -ceq '-') { $t = ((@($script:STDINLINES) -join "`n") + "`n") } else {
        if (-not (Test-Path -LiteralPath $p -PathType Leaf)) { CrDie ("ci-reports: cannot read " + $p + ": No such file or directory`n") }
        $b = Get-Content -LiteralPath $p -Encoding Byte -ReadCount 0
        $t = if ($null -eq $b) { '' } else { CrUtf8Dec ([byte[]]$b) }
    }
    return $t.Replace("`r`n", "`n")
}

# ---------------------------------------------------------------- MD5 (RFC 1321), integer arithmetic only
$script:MD5S = @(7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22, 5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20,
    4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23, 6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21)
$script:MD5K = @(0xd76aa478L, 0xe8c7b756L, 0x242070dbL, 0xc1bdceeeL, 0xf57c0fafL, 0x4787c62aL, 0xa8304613L, 0xfd469501L, 0x698098d8L, 0x8b44f7afL, 0xffff5bb1L, 0x895cd7beL,
    0x6b901122L, 0xfd987193L, 0xa679438eL, 0x49b40821L, 0xf61e2562L, 0xc040b340L, 0x265e5a51L, 0xe9b6c7aaL, 0xd62f105dL, 0x02441453L, 0xd8a1e681L, 0xe7d3fbc8L,
    0x21e1cde6L, 0xc33707d6L, 0xf4d50d87L, 0x455a14edL, 0xa9e3e905L, 0xfcefa3f8L, 0x676f02d9L, 0x8d2a4c8aL, 0xfffa3942L, 0x8771f681L, 0x6d9d6122L, 0xfde5380cL,
    0xa4beea44L, 0x4bdecfa9L, 0xf6bb4b60L, 0xbebfbc70L, 0x289b7ec6L, 0xeaa127faL, 0xd4ef3085L, 0x04881d05L, 0xd9d4d039L, 0xe6db99e5L, 0x1fa27cf8L, 0xc4ac5665L,
    0xf4292244L, 0x432aff97L, 0xab9423a7L, 0xfc93a039L, 0x655b59c3L, 0x8f0ccc92L, 0xffeff47dL, 0x85845dd1L, 0x6fa87e4fL, 0xfe2ce6e0L, 0xa3014314L, 0x4e0811a1L,
    0xf7537e82L, 0xbd3af235L, 0x2ad7d2bbL, 0xeb86d391L)
function CrMd5Hex([byte[]]$msg) {
    $M32 = 0xFFFFFFFFL
    $ml = $msg.Length
    $padLen = (56 - (($ml + 1) % 64) + 64) % 64
    $total = $ml + 1 + $padLen + 8
    $b = [byte[]]::new($total)
    if ($ml) { [Array]::Copy($msg, $b, $ml) }
    $b[$ml] = 0x80
    $bits = [long]$ml * 8
    for ($i = 0; $i -lt 8; $i++) { $b[$total - 8 + $i] = ($bits -shr (8 * $i)) -band 0xFF }
    $a0 = 0x67452301L; $b0 = 0xefcdab89L; $c0 = 0x98badcfeL; $d0 = 0x10325476L
    $w = [long[]]::new(16)
    for ($off = 0; $off -lt $total; $off += 64) {
        for ($i = 0; $i -lt 16; $i++) { $p = $off + 4 * $i; $w[$i] = [long]$b[$p] -bor ([long]$b[$p + 1] -shl 8) -bor ([long]$b[$p + 2] -shl 16) -bor ([long]$b[$p + 3] -shl 24) }
        $aa = $a0; $bb = $b0; $cc = $c0; $dd = $d0
        for ($i = 0; $i -lt 64; $i++) {
            if ($i -lt 16) { $f = ($bb -band $cc) -bor ((-bnot $bb) -band $M32 -band $dd); $g = $i }
            elseif ($i -lt 32) { $f = ($dd -band $bb) -bor ((-bnot $dd) -band $M32 -band $cc); $g = (5 * $i + 1) % 16 }
            elseif ($i -lt 48) { $f = $bb -bxor $cc -bxor $dd; $g = (3 * $i + 5) % 16 }
            else { $f = $cc -bxor ($bb -bor ((-bnot $dd) -band $M32)); $g = (7 * $i) % 16 }
            $f = ($f + $aa + $script:MD5K[$i] + $w[$g]) -band $M32
            $aa = $dd; $dd = $cc; $cc = $bb
            $s = $script:MD5S[$i]
            $rot = (($f -shl $s) -bor ($f -shr (32 - $s))) -band $M32
            $bb = ($bb + $rot) -band $M32
        }
        $a0 = ($a0 + $aa) -band $M32; $b0 = ($b0 + $bb) -band $M32; $c0 = ($c0 + $cc) -band $M32; $d0 = ($d0 + $dd) -band $M32
    }
    $hex = ''
    foreach ($v in @($a0, $b0, $c0, $d0)) { for ($i = 0; $i -lt 4; $i++) { $hex += '{0:x2}' -f (($v -shr (8 * $i)) -band 0xFF) } }
    return $hex
}
function CrMd5([string]$s) { return (CrMd5Hex (CrUtf8Enc $s)) }

# ---------------------------------------------------------------- escaping
function CrXml($t) {
    if ($null -eq $t) { $t = '' }
    $t = ([string]$t).Replace('&', '&amp;').Replace('<', '&lt;').Replace('>', '&gt;').Replace('"', '&quot;')
    return ($t -creplace '[\x00-\x08\x0b\x0c\x0e-\x1f]', '')
}
function CrJs($t) {
    if ($null -eq $t) { $t = '' }
    $t = ([string]$t).Replace('\', '\\').Replace('"', '\"').Replace("`n", '\n').Replace("`t", '\t')
    $o = ''
    foreach ($ch in $t.ToCharArray()) { $c = [int]$ch; if ($c -lt 32) { $o += '\u' + ('{0:x4}' -f $c) } else { $o += [string]$ch } }
    return '"' + $o + '"'
}

# ---------------------------------------------------------------- the reports
function CrUsage { CrDie "usage: ci-reports.cmd grammar|lint|outline|todo|trace [--junit F] [--codequality F] [--metrics F] LOG|DIR [FILE...]`n" }

function CrMain($argv) {
    if ($argv.Count -and $argv[0] -match '^(-h|--help|-Help|help)$') { Write-Host -NoNewline "usage: ci-reports.cmd grammar|lint|outline|todo|trace [--junit F] [--codequality F] [--metrics F] LOG|DIR [FILE...]`n"; return 0 }
    if ($argv.Count -eq 0) { CrUsage }
    $mode = [string]$argv[0]
    if ($mode -cnotmatch '^(grammar|lint|outline|todo|trace)$') { CrUsage }
    $o = @{}; $rest = @()
    for ($i = 1; $i -lt $argv.Count; $i++) {
        $a = [string]$argv[$i]
        if ($a -cmatch '^--?(junit|codequality|metrics)(?:=(.*))?$') {
            $k = $Matches[1]; $v = $Matches[2]
            if ($null -eq $v) { if ($i + 1 -ge $argv.Count) { CrUsage }; $i++; $v = [string]$argv[$i] }
            $o[$k] = $v; continue
        }
        if ($a -cmatch '^--?\w' -and $a -cne '-') { CrUsage }
        $rest += $a
    }
    if ($rest.Count -eq 0) { CrUsage }
    $in = $rest[0]
    $files = @(); for ($i = 1; $i -lt $rest.Count; $i++) { $files += $rest[$i] }
    $cases = @(); $findings = @(); $metrics = @()
    $DIAG = '^(\S.*?\.sysml):(\d+)(?::\d+)?: (error|warning): (.*)$'

    if ($mode -ceq 'grammar' -or $mode -ceq 'lint') {
        $log = CrSlurp $in
        $by = @{}; $order = @()
        foreach ($l in ($log -split "`n")) {
            if ($l -cnotmatch $DIAG) { continue }
            $f = $Matches[1]; $line = $Matches[2]; $sev = $Matches[3]; $msg = $Matches[4]
            if (-not $by.ContainsKey($f)) { $order += $f; $by[$f] = @() }
            $by[$f] = @($by[$f]) + , @($line, $sev, $msg)
            $svr = if ($mode -ceq 'grammar') { 'critical' } elseif ($sev -ceq 'error') { 'major' } else { 'minor' }
            $findings += , @{ check = "sysml-$mode"; path = $f; line = $line; severity = $svr; message = $msg }
        }
        $all = @(); foreach ($f in (@($files) + @($order))) { if (-not ($all -ccontains $f)) { $all += $f } }
        foreach ($f in $all) {
            $d = @(); if ($by.ContainsKey($f)) { $d = $by[$f] }
            $err = @(); foreach ($x in $d) { if ($x[1] -ceq 'error') { $err += , $x } }
            $fail = if ($err.Count) { '{0} error(s), first at line {1}: {2}' -f $err.Count, $err[0][0], $err[0][2] } else { $null }
            $det = @(); foreach ($x in $d) { $det += ($f + ':' + $x[0] + ': ' + $x[1] + ': ' + $x[2]) }
            $cases += , @{ suite = $mode; name = $f; file = $f; fail = $fail; detail = ($det -join "`n") }
        }
        if ($mode -ceq 'lint') {
            if ($log -cnotmatch '(?m)^elements=(\d+) errors=(\d+) warnings=(\d+)\s*$') { CrDie ("ci-reports: no 'elements=N errors=E warnings=W' line in " + $in + " (is it model.pl lint output?)`n") }
            $el = $Matches[1]; $e = $Matches[2]; $w = $Matches[3]
            $metrics += , @('model_elements', $el); $metrics += , @('lint_errors', $e); $metrics += , @('lint_warnings', $w)
            $fail = if ([int]$e -or [int]$w) { "errors=$e warnings=$w" } else { $null }
            $cases += , @{ suite = 'lint'; name = 'lint 0/0'; file = ''; fail = $fail; detail = '' }
        } else {
            $n = $all.Count; $e = $findings.Count
            if ($log -cmatch '(?m)^sysml: (\d+) file\(s\), (\d+) error\(s\)') { $n = $Matches[1]; $e = $Matches[2] }
            $metrics += , @('grammar_files', $n); $metrics += , @('grammar_errors', $e)
        }
    }
    elseif ($mode -ceq 'outline') {
        $log = CrSlurp $in
        $mm = $null; $viol = $null
        if ($log -cmatch '(?m)^@L tag mismatches\s+(\d+)') { $mm = $Matches[1] }
        if ($log -cmatch '(?m)^violations\s+(\d+)') { $viol = $Matches[1] }
        if ($null -eq $mm -and $null -eq $viol) { CrDie ("ci-reports: no '@L tag mismatches' or 'violations' line in " + $in + " (is it model.pl check output?)`n") }
        $tags = @(); $outl = @(); $sec = $null
        foreach ($l in ($log -split "`n")) {
            if ($l -cmatch '^== Level tags') { $sec = 'tags'; continue }
            if ($l -cmatch '^== Outline') { $sec = 'outline'; continue }
            if (-not $sec) { continue }
            if ($sec -ceq 'tags' -and $l -cmatch '^  (\S.*): tagged L(\d+), first reached at L(\d+)$') { $tags += , @($Matches[1], $Matches[2], $Matches[3]) }
            if ($sec -ceq 'outline' -and $l -cmatch '^\s+(\d+)  (.*)  \((.*)\)$') { $outl += , @($Matches[1], $Matches[2], $Matches[3]) }
        }
        foreach ($t in $tags) { $findings += , @{ check = 'level-tag'; path = 'model'; line = 1; severity = 'minor'; message = ($t[0] + ': tagged L' + $t[1] + ', first reached at L' + $t[2]) } }
        foreach ($v in $outl) { $path = $v[2] -creplace '/$', ''; $findings += , @{ check = 'outline'; path = $path; line = 1; severity = 'minor'; message = ($v[1] + ': ' + $v[0] + ' (outside 2..9)') } }
        $det = @(); foreach ($t in $tags) { $det += ($t[0] + ': tagged L' + $t[1] + ', first reached at L' + $t[2]) }
        $cases += , @{ suite = 'outline'; name = 'level tags'; file = ''; fail = $(if ($tags.Count) { [string]$tags.Count + ' mismatch(es)' } else { $null }); detail = ($det -join "`n") }
        $det = @(); foreach ($v in $outl) { $det += ($v[2] + ': ' + $v[1] + ' = ' + $v[0]) }
        $cases += , @{ suite = 'outline'; name = '2..9 children per parent'; file = ''; fail = $(if ($outl.Count) { [string]$outl.Count + ' violation(s)' } else { $null }); detail = ($det -join "`n") }
        $metrics += , @('level_tag_mismatches', $(if ($null -ne $mm) { $mm } else { 0 })); $metrics += , @('outline_violations', $(if ($null -ne $viol) { $viol } else { 0 }))
    }
    elseif ($mode -ceq 'todo') {
        $hits = @()
        if (Test-Path -LiteralPath $in -PathType Container) {
            $stack = @($in); $found = @()
            while ($stack.Count) {
                $d = $stack[0]; if ($stack.Count -gt 1) { $stack = @($stack[1..($stack.Count - 1)]) } else { $stack = @() }
                $names = @(); foreach ($e in (Get-ChildItem -LiteralPath $d -Force -ErrorAction Stop)) { if (-not $e.Name.StartsWith('.')) { $names += $e.Name } }
                $names = [string[]]$names; if ($names.Count -gt 1) { [Array]::Sort($names, [StringComparer]::Ordinal) }
                foreach ($e in $names) { $p = $d + '/' + $e; if (Test-Path -LiteralPath $p -PathType Container) { $stack += $p } elseif ($e -cmatch '\.sysml$') { $found += $p } }
            }
            $found = [string[]]$found; if ($found.Count -gt 1) { [Array]::Sort($found, [StringComparer]::Ordinal) }
            foreach ($f in $found) {
                $t = CrSlurp $f; $ln = 0
                $ls = $t -split "`n"; if ($ls.Count -and $ls[$ls.Count - 1] -ceq '') { $ls = @($ls[0..($ls.Count - 2)]) }
                foreach ($l in $ls) { $ln++; if ($l -cmatch '//\s*(TODO\b.*?)\s*$') { $hits += , @($f, $ln, $Matches[1]) } }
            }
        } else {
            foreach ($l in ((CrSlurp $in) -split "`n")) { if ($l -cmatch '^(.*?):(\d+):.*?//\s*(TODO\b.*?)\s*$') { $hits += , @($Matches[1], $Matches[2], $Matches[3]) } }
        }
        $pkg = @{}
        foreach ($h in $hits) {
            $p = 'other'; if ($h[0] -cmatch '(?:^|/)model/([^/]+)/') { $p = $Matches[1] }
            if ($pkg.ContainsKey($p)) { $pkg[$p]++ } else { $pkg[$p] = 1 }
            $msg = $h[2] -creplace '\s*\(xmi:id [^)]*\)', ''
            $findings += , @{ check = 'todo'; path = $h[0]; line = $h[1]; severity = 'info'; message = $msg }
        }
        $metrics += , @('todo_lines', $hits.Count)
        $pk = [string[]]@($pkg.Keys); if ($pk.Count -gt 1) { [Array]::Sort($pk, [StringComparer]::Ordinal) }
        foreach ($k in $pk) { $metrics += , @("todo_lines_$k", $pkg[$k]) }
        $det = @(); foreach ($k in $pk) { $det += "$k $($pkg[$k])" }
        $cases += , @{ suite = 'todo'; name = 'converter TODO lines'; file = ''; fail = $null; detail = ([string]$hits.Count + ' TODO line(s): ' + ($det -join ', ')) }
    }
    elseif ($mode -ceq 'trace') {
        $log = CrSlurp $in
        if ($log -cnotmatch '(?m)^C requirements linked.*?(\d+) of (\d+)') { CrDie ("ci-reports: no 'C requirements linked' line in " + $in + " (is it reqif2sysml.pl --report --model output?)`n") }
        $lk = $Matches[1]; $tot = $Matches[2]
        $orph = $null; $unv = $null; $comp = $null; $drift = $null
        if ($log -cmatch '(?m)^F orphan requirements.*?(\d+)\s*$') { $orph = $Matches[1] }
        if ($log -cmatch '(?m)^G unverified requirements.*?(\d+)\s*$') { $unv = $Matches[1] }
        if ($log -cmatch '(?m)^I trace completeness.*?([\d.]+)%') { $comp = $Matches[1] }
        if ($log -cmatch '(?m)^text differs from DOORS\s+(\d+)') { $drift = $Matches[1] }
        $list = @{}
        foreach ($k in @('orphans', 'unverified', 'drift', 'not in the model')) {
            $v = @(); if ($log -cmatch ('(?m)^' + [regex]::Escape($k) + ': (.*)$')) { foreach ($x in ($Matches[1] -split '\s+')) { if ($x -ne '') { $v += $x } } }
            $list[$k] = $v
        }
        $metrics += , @('trace_linked', $lk); $metrics += , @('trace_total', $tot)
        $metrics += , @('trace_orphans', $(if ($null -ne $orph) { $orph } else { @($list['orphans']).Count }))
        $metrics += , @('trace_unverified', $(if ($null -ne $unv) { $unv } else { @($list['unverified']).Count }))
        $metrics += , @('trace_completeness_pct', $(if ($null -ne $comp) { $comp } else { 0 }))
        $metrics += , @('trace_drift', $(if ($null -ne $drift) { $drift } else { @($list['drift']).Count }))
        $metrics += , @('trace_not_in_model', @($list['not in the model']).Count)
        $what = @{ orphans = 'nothing satisfies it'; unverified = 'nothing verifies it'; drift = 'the text differs from DOORS'; 'not in the model' = 'in DOORS, not in the model' }
        foreach ($k in @('not in the model', 'orphans', 'unverified', 'drift')) {
            foreach ($id in $list[$k]) { $cases += , @{ suite = "trace $k"; name = $id; file = ''; fail = "${id}: $($what[$k])"; detail = '' } }
        }
        $cases += , @{ suite = 'trace'; name = 'requirements linked'; file = ''; fail = $(if ([int]$lk -lt [int]$tot) { "$lk of $tot linked" } else { $null }); detail = '' }
    }

    if ($o.ContainsKey('junit')) {
        $suites = @{}; $sorder = @()
        foreach ($c in $cases) { if (-not $suites.ContainsKey($c.suite)) { $sorder += $c.suite; $suites[$c.suite] = @() }; $suites[$c.suite] = @($suites[$c.suite]) + , $c }
        $fails = 0; foreach ($c in $cases) { if ($null -ne $c.fail) { $fails++ } }
        $x = '<?xml version="1.0" encoding="UTF-8"?>' + "`n" + '<testsuites name="sysml-' + $mode + '" tests="' + $cases.Count + '" failures="' + $fails + '">' + "`n"
        foreach ($s in $sorder) {
            $cs = @($suites[$s]); $f = 0; foreach ($c in $cs) { if ($null -ne $c.fail) { $f++ } }
            $x += '  <testsuite name="' + (CrXml $s) + '" tests="' + $cs.Count + '" failures="' + $f + '">' + "`n"
            foreach ($c in $cs) {
                $x += '    <testcase classname="' + (CrXml $s) + '" name="' + (CrXml $c.name) + '"' + $(if ($c.file) { ' file="' + (CrXml $c.file) + '"' } else { '' })
                if ($null -ne $c.fail) { $dt = if ($c.detail) { $c.detail } else { $c.fail }; $x += ">`n      <failure message=`"" + (CrXml $c.fail) + '" type="' + (CrXml $mode) + '">' + (CrXml $dt) + "</failure>`n    </testcase>`n" }
                elseif ($c.detail) { $x += ">`n      <system-out>" + (CrXml $c.detail) + "</system-out>`n    </testcase>`n" }
                else { $x += "/>`n" }
            }
            $x += "  </testsuite>`n"
        }
        CrWrite $o['junit'] ($x + "</testsuites>`n")
    }
    if ($o.ContainsKey('codequality')) {
        $seen = @{}; $j = @()
        foreach ($f in $findings) {
            $fp = CrMd5 ($f.path + [string][char]0 + $f.check + [string][char]0 + $f.message)
            $n = 0; if ($seen.ContainsKey($fp)) { $n = $seen[$fp] }; $seen[$fp] = $n + 1
            if ($n) { $fp = CrMd5 ($fp + [string]$n) }
            $j += ('  {"description": ' + (CrJs $f.message) + ', "check_name": ' + (CrJs $f.check) + ', "fingerprint": "' + $fp + '", "severity": "' + $f.severity + '", "location": {"path": ' + (CrJs $f.path) + ', "lines": {"begin": ' + [int]$f.line + '}}}')
        }
        CrWrite $o['codequality'] $(if ($j.Count) { "[`n" + ($j -join ",`n") + "`n]`n" } else { "[]`n" })
    }
    if ($o.ContainsKey('metrics')) { $t = ''; foreach ($m in $metrics) { $t += [string]$m[0] + ' ' + [string]$m[1] + "`n" }; CrWrite $o['metrics'] $t }
    $nf = 0; foreach ($c in $cases) { if ($null -ne $c.fail) { $nf++ } }
    $ms = ''; if ($metrics.Count) { $p = @(); foreach ($m in $metrics) { $p += ([string]$m[0] + '=' + [string]$m[1]) }; $ms = '; ' + ($p -join ' ') }
    Write-Host -NoNewline ('ci-reports ' + $mode + ': ' + $cases.Count + ' check(s), ' + $nf + ' failed, ' + $findings.Count + ' finding(s)' + $ms + "`n")
    return 0
}

if ($args.Count -and [string]$args[0] -ceq '__lib') { return }
$script:STDINLINES = @(); if ($args -ccontains '-') { $script:STDINLINES = @($input | ForEach-Object { [string]$_ }) }
$rc = 2
try { $rc = CrMain @($args) }
catch { $m = [string]$_.Exception.Message; if ($m.StartsWith('CRDIE:')) { Write-Host -NoNewline $m.Substring(6) } else { Write-Host -NoNewline ($m + "`n") }; $rc = 2 }
exit $rc
