<#
pages-index.ps1 -- the front page of the model's GitLab Pages site (tools/gitlab/pages-index.pl).

Windows PowerShell 5.1, Constrained Language Mode safe, pure ASCII; the same index.html and docs/*.html, byte for
byte, as the Perl tool.

  pages-index.cmd [--title T] [--commit SHA] [--date D] DIR

DIR is the folder the pages job publishes (public/): docs/*.md (each also written as docs/<name>.html), views/*.svg,
trace.txt (reqif2sysml --report --model output) and todo-burndown.csv (date,todo_lines). Missing inputs are left
out of the page. The page has no scripts and nothing external.
#>

$ErrorActionPreference = 'Stop'

function PiUtf8Enc([string]$s) {
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
function PiUtf8Dec([byte[]]$b) {
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
function PiDie([string]$m) { throw ('PIDIE:' + $m) }
function PiEsc($t) { if ($null -eq $t) { $t = '' }; return ([string]$t).Replace('&', '&amp;').Replace('<', '&lt;').Replace('>', '&gt;').Replace('"', '&quot;') }
function PiSlurp([string]$p) {
    if (-not (Test-Path -LiteralPath $p -PathType Leaf)) { return $null }
    $b = Get-Content -LiteralPath $p -Encoding Byte -ReadCount 0
    $t = if ($null -eq $b) { '' } else { PiUtf8Dec ([byte[]]$b) }
    return $t.Replace("`r`n", "`n")
}
function PiSpew([string]$p, [string]$t) {
    try { Set-Content -LiteralPath $p -Encoding Byte -Value (PiUtf8Enc $t) -ErrorAction Stop } catch { PiDie ("pages-index: cannot write " + $p + ": " + $_.Exception.Message + "`n") }
}
function PiLs([string]$d, [string]$re) {
    if (-not (Test-Path -LiteralPath $d -PathType Container)) { return , @() }
    $f = @(); foreach ($e in (Get-ChildItem -LiteralPath $d -Force)) { if ($e.Name -cmatch $re) { $f += $e.Name } }
    $f = [string[]]$f; if ($f.Count -gt 1) { [Array]::Sort($f, [StringComparer]::Ordinal) }
    return , $f
}
function PiF1([double]$v) {                      # Perl's %.1f: half to even (on the decimal form of the double)
    return ('{0:F1}' -f [decimal]::Round([decimal]$v, 1))
}

$script:CSS = 'body{font-family:Calibri,"Segoe UI",Arial,sans-serif;font-size:11pt;color:#1a1a1a;background:#fff;max-width:1100px;margin:2em auto;padding:0 16px;line-height:1.5}' +
    'h1{font-size:18pt;border-bottom:3px solid #27235d;padding-bottom:.2em}h2{font-size:14pt;margin-top:1.8em;border-bottom:1px solid #999}' +
    'pre{background:#f4f4f4;border:1px solid #ddd;padding:.8em 1em;overflow-x:auto;font-size:9.5pt}table{border-collapse:collapse}' +
    'th,td{border:1px solid #bbb;padding:.3em .6em;text-align:left}th{background:#e4e4e7}.muted{color:#555;font-size:9.5pt}' +
    'img{max-width:100%;border:1px solid #ddd;margin:.5em 0}a{color:#27235d}'
function PiPage([string]$title, [string]$body) {
    return "<!DOCTYPE html>`n<html lang=`"en`"><head><meta charset=`"UTF-8`"><meta name=`"viewport`" content=`"width=device-width, initial-scale=1`">`n<title>" + (PiEsc $title) + '</title><style>' + $script:CSS + "</style></head>`n<body>`n" + $body + "`n</body></html>`n"
}

$script:PIUSAGE = "usage: pages-index.cmd [--title T] [--commit SHA] [--date D] DIR`n"

function PiMain($argv) {
    $o = @{ title = 'Tidewater model'; commit = $(if ($env:CI_COMMIT_SHORT_SHA) { $env:CI_COMMIT_SHORT_SHA } else { '' }); date = $(if ($env:CI_COMMIT_TIMESTAMP) { $env:CI_COMMIT_TIMESTAMP } else { '' }) }
    $rest = @()
    for ($i = 0; $i -lt $argv.Count; $i++) {
        $a = [string]$argv[$i]
        if ($a -match '^(-h|--help|-Help|help)$') { Write-Host -NoNewline $script:PIUSAGE; return 0 }
        if ($a -cmatch '^--?(title|commit|date)(?:=(.*))?$') {
            $k = $Matches[1]; $v = $Matches[2]
            if ($null -eq $v) { if ($i + 1 -ge $argv.Count) { PiDie $script:PIUSAGE }; $i++; $v = [string]$argv[$i] }
            $o[$k] = $v; continue
        }
        if ($a -cmatch '^--?\w') { PiDie $script:PIUSAGE }
        $rest += $a
    }
    if ($rest.Count -eq 0) { PiDie $script:PIUSAGE }
    $dir = $rest[0]
    if (-not (Test-Path -LiteralPath $dir -PathType Container)) { PiDie ("pages-index: " + $dir + " is not a directory`n") }

    $body = '<h1>' + (PiEsc $o.title) + "</h1>`n<p class=muted>Built by the pipeline from the default branch" +
        $(if ($o.commit) { ' at commit <code>' + (PiEsc $o.commit) + '</code>' } else { '' }) + $(if ($o.date) { ', ' + (PiEsc $o.date) } else { '' }) +
        ". Everything here is generated from the model; nothing is typed by hand.</p>`n"

    $csv = PiSlurp "$dir/todo-burndown.csv"
    if ($null -ne $csv) {
        $pts = @()
        foreach ($l in ($csv -split "`n")) { if ($l -cmatch '^\d{4}-\d\d-\d\d,\d+$') { $pts += , ($l -split ',') } }
        if ($pts.Count) {
            $w = 760; $h = 220; $lft = 50; $bot = 30
            $max = 1; foreach ($p in $pts) { if ($max -lt [long]$p[1]) { $max = [long]$p[1] } }
            $n = $pts.Count
            $xy = @()
            for ($k = 0; $k -lt $n; $k++) {
                $x = if ($n -eq 1) { [double]$lft } else { $lft + $k * ($w - $lft - 10) / ($n - 1) }
                $y = 10 + ($h - $bot - 10) * (1 - [double]$pts[$k][1] / $max)
                $xy += , @([double]$x, [double]$y)
            }
            $hb = $h - $bot; $w10 = $w - 10; $h10 = $h - 10; $l6 = $lft - 6
            $svg = '<svg viewBox="0 0 ' + $w + ' ' + $h + '" role="img" aria-label="TODO lines remaining over time" font-family="Calibri,Arial,sans-serif" font-size="11">' +
                '<line x1="' + $lft + '" y1="10" x2="' + $lft + '" y2="' + $hb + '" stroke="#808082"/><line x1="' + $lft + '" y1="' + $hb + '" x2="' + $w10 + '" y2="' + $hb + '" stroke="#808082"/>' +
                '<text x="' + $l6 + '" y="14" text-anchor="end">' + $max + '</text><text x="' + $l6 + '" y="' + $hb + '" text-anchor="end">0</text>' +
                '<text x="' + $lft + '" y="' + $h10 + '">' + (PiEsc $pts[0][0]) + '</text><text x="' + $w10 + '" y="' + $h10 + '" text-anchor="end">' + (PiEsc $pts[$n - 1][0]) + '</text>'
            $ps = @(); foreach ($q in $xy) { $ps += ((PiF1 $q[0]) + ',' + (PiF1 $q[1])) }
            $last = $xy[$n - 1]
            $svg += '<polyline fill="none" stroke="#27235d" stroke-width="2.5" points="' + ($ps -join ' ') + '"/>' +
                '<circle cx="' + (PiNum $last[0]) + '" cy="' + (PiNum $last[1]) + '" r="4" fill="#27235d"/></svg>'
            $body += "<h2>Port burn-down</h2>`n<p>Converter TODO lines left in the model, at each merge to the default branch. " +
                'Now <b>' + $pts[$n - 1][1] + '</b>, from ' + $max + " at the start.</p>`n" + $svg + "`n"
        }
    }

    $tr = PiSlurp "$dir/trace.txt"
    if ($null -ne $tr) {
        $rows = ''
        foreach ($re in @(@('Requirements linked to the model', '(?m)^C requirements linked.*?(\d+ of \d+)'), @('Orphans (nothing satisfies them)', '(?m)^F orphan requirements.*?(\d+)\s*$'),
                          @('Unverified (nothing verifies them)', '(?m)^G unverified requirements.*?(\d+)\s*$'), @('Trace completeness', '(?m)^I trace completeness.*?([\d.]+%)'),
                          @('Text differs from DOORS', '(?m)^text differs from DOORS\s+(\d+)'))) {
            if ($tr -cmatch $re[1]) { $rows += '<tr><td>' + (PiEsc $re[0]) + '</td><td>' + (PiEsc $Matches[1]) + "</td></tr>`n" }
        }
        $body += "<h2>Requirement trace</h2>`n<p>DOORS (the prime's requirements, as delivered) against the model.</p>`n" +
            $(if ($rows) { "<table>`n<tr><th>Measure</th><th>Now</th></tr>`n" + $rows + "</table>`n" } else { '' }) +
            '<details><summary>The full report</summary><pre>' + (PiEsc $tr) + "</pre></details>`n"
    }

    $svgs = PiLs "$dir/views" '\.svg$'
    if ($svgs.Count) {
        $body += "<h2>Model views</h2>`n"
        foreach ($f in $svgs) { $t = $f -creplace '\.svg$', ''; $body += '<h3>' + (PiEsc $t) + "</h3>`n<a href=`"views/" + (PiEsc $f) + '"><img src="views/' + (PiEsc $f) + '" alt="model view: ' + (PiEsc $t) + "`"></a>`n" }
    }

    $mds = PiLs "$dir/docs" '\.md$'
    if ($mds.Count) {
        $body += "<h2>Generated model documents</h2>`n<ul>`n"
        foreach ($f in $mds) {
            $hn = $f -creplace '\.md$', '.html'
            PiSpew "$dir/docs/$hn" (PiPage ($o.title + ': ' + $f) ('<p><a href="../index.html">&larr; ' + (PiEsc $o.title) + '</a></p><pre>' + (PiEsc (PiSlurp "$dir/docs/$f")) + '</pre>'))
            $body += '<li><a href="docs/' + (PiEsc $hn) + '">' + (PiEsc $f) + "</a></li>`n"
        }
        $body += "</ul>`n"
    }
    PiSpew "$dir/index.html" (PiPage $o.title $body)
    Write-Host -NoNewline ("wrote $dir/index.html`n")
    return 0
}
function PiNum([double]$v) {                     # a number as Perl prints it in a string (up to 15 significant digits)
    $s = $v.ToString('R')
    if ($s -cmatch 'E') { return $s }
    $g = '{0:G15}' -f $v
    return $g
}

if ($args.Count -and [string]$args[0] -ceq '__lib') { return }
$rc = 1
try { $rc = PiMain @($args) }
catch { $m = [string]$_.Exception.Message; if ($m.StartsWith('PIDIE:')) { Write-Host -NoNewline $m.Substring(6) } else { Write-Host -NoNewline ("pages-index: " + $m + "`n") }; $rc = 2 }
exit $rc
