<#
md2docs.ps1 -- a folder of Markdown -> one document set: an indexed HTML site for Edge (and, with -Word, one Word
document with every page in it). Windows PowerShell 5.1, Constrained Language Mode safe: every page goes through
md2docx.ps1 (beside this file), so headings, lists, tables, code, portion marks and banners come out as md2docx
makes them.

  md2docs DIR [-Out SITE] [-Title TEXT] [-Word] [-Mark] [-Default CLS] [-Exclude PATTERN]

  DIR           the folder of .md files (searched recursively; .git, the output folder and -Exclude are skipped)
  -Out SITE     where the site goes (default DIR\_site): SITE\index.html, one .html per .md (same folders)
  -Title TEXT   the set's title (default: the folder name)
  -Word         also SITE\<title>.docx: every page in nav order, each page's headings one level down, under the title
  -Mark         mark every portion, as md2docx -Mark;  -Default CLS: the floor class, as md2docx -Default
  -Exclude P    skip files whose path relative to DIR matches the regular expression P (for example 'drafts/')

What the site has
  index.html    every document with its title (its first # heading), the first lines of its first paragraph, and
                its marking; README.md and index.md come first in each folder, then the rest by name
  each page     HTML comments (<!-- -->) dropped, as memo-build drops them; the navigation on the left, previous/next at the foot, links between .md files rewritten to .html,
                the page banners md2docx puts at the top and bottom
  the index banner is the highest marking of any page (when marking is on)

Nothing is fetched: no scripts from outside, no fonts, no network. Open SITE\index.html in Edge.
Exit 0 = written, 1 = a page failed (the rest are still written), 2 = usage.
#>
param(
    [Parameter(Position = 0)][string]$Path,
    [string]$Out, [string]$Title, [switch]$Word, [switch]$Mark, [string]$Default = '', [string]$Exclude = '', [switch]$Help
)
$ErrorActionPreference = 'Stop'
$script:RC = 0
$script:HERE = $PSScriptRoot; if (-not $script:HERE) { $script:HERE = (Get-Location).Path }
$script:MD2DOCX = Join-Path $script:HERE 'md2docx.ps1'

function Out-Err([string]$t) { foreach ($l in ($t -split "`n")) { if ($l -ne '') { Write-Host $l -ForegroundColor Yellow } } }
function HEsc([string]$s) { $s.Replace('&', '&amp;').Replace('<', '&lt;').Replace('>', '&gt;').Replace('"', '&quot;') }
function ReadUtf8([string]$p) { $t = Get-Content -LiteralPath $p -Encoding UTF8 -Raw; if ($null -eq $t) { return '' }; return $t }
function WriteUtf8([string]$p, [string]$t) {           # UTF-8 (with a BOM: Edge and Word read it either way)
    $dir = Split-Path $p -Parent; if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    Set-Content -LiteralPath $p -Value $t -Encoding UTF8 -NoNewline
}
function QuoteArg([string]$a) { return "'" + $a.Replace("'", "''") + "'" }
function Invoke-Md2docx($h) {                         # $h: md2docx's parameters. The file when .ps1 files may run, else its text
    try { $o = & $script:MD2DOCX @h 2>&1; return @{ rc = $LASTEXITCODE; out = (@($o) -join "`n") } }
    catch {
        if ($_.Exception.Message -notmatch 'running scripts is disabled|cannot be loaded|not digitally signed') { throw }
        $al = ''; foreach ($k in $h.Keys) { if ($h[$k] -is [bool]) { if ($h[$k]) { $al += " -$k" } } else { $al += " -$k " + (QuoteArg ([string]$h[$k])) } }
        $code = Get-Content -LiteralPath $script:MD2DOCX -Raw
        $o = Invoke-Expression ('& {' + $code + "`n}" + $al) 2>&1
        return @{ rc = $LASTEXITCODE; out = (@($o) -join "`n") }
    }
}
function RelUrl([string]$fromRel, [string]$toRel) {    # a link from page fromRel to page toRel (both 'a/b.html')
    $up = ($fromRel.Split('/').Count - 1)
    return (('../' * $up) + $toRel)
}
function DocTitle([string]$md, [string]$fallback) {
    foreach ($l in ($md -split "`n")) { if ($l -cmatch '^#\s+(.*?)\s*#*\s*$') { return (StripTags $Matches[1]) } }
    return $fallback
}
function StripTags([string]$s) { return ([regex]::Replace($s, '(?<!\\)\{(?:TS|S|C|CUI|U)(?://[^{}]*)?\}|(?<!\\)\{/[^{}]*\}', '')) }
function DocSummary([string]$md) {                     # the first paragraph's text, plain, at most 160 characters
    $inCode = $false; $buf = @()
    foreach ($l in ($md -split "`n")) {
        $t = $l.TrimEnd("`r")
        if ($t -cmatch '^\s*```') { $inCode = -not $inCode; if ($buf.Count) { break }; continue }
        if ($inCode) { continue }
        if ($t.Trim() -eq '') { if ($buf.Count) { break }; continue }
        if ($t -cmatch '^\s*(#|\||[-*+]\s|\d+\.\s|>|---|===|<)') { if ($buf.Count) { break }; continue }
        $buf += $t.Trim()
    }
    $s = StripTags ($buf -join ' ')
    $s = [regex]::Replace($s, '!\[([^\]]*)\]\([^)]*\)', '$1'); $s = [regex]::Replace($s, '\[([^\]]*)\]\([^)]*\)', '$1')
    $s = $s.Replace('**', '').Replace('__', '').Replace('`', '')
    if ($s.Length -gt 160) { $s = $s.Substring(0, 157).TrimEnd() + '...' }
    return $s
}
$script:CLASSRANK = @{ 'UNCLASSIFIED' = 0; 'CUI' = 1; 'CONFIDENTIAL' = 2; 'SECRET' = 3; 'TOP SECRET' = 4 }
function BannerRank([string]$b) { if (-not $b) { return -1 }; $c = ($b -split '//')[0].Trim(); if ($script:CLASSRANK.ContainsKey($c)) { return $script:CLASSRANK[$c] }; return 0 }

$script:CSS = @'
body { margin: 0; font-family: "Segoe UI", Arial, sans-serif; color: #111; background: #fff; }
.banner { text-align: center; font-weight: bold; padding: 4px; background: #f2f2f2; border-bottom: 1px solid #ccc; }
.banner.bottom { border-top: 1px solid #ccc; border-bottom: 0; }
.wrap { display: flex; min-height: 100vh; }
nav { width: 260px; flex: none; border-right: 1px solid #ddd; padding: 12px 14px; font-size: 13px; background: #fafafa; }
nav a { color: #0b4f8a; text-decoration: none; display: block; padding: 2px 0; }
nav a.here { font-weight: bold; color: #000; }
nav .dir { margin-top: 8px; color: #555; font-size: 12px; text-transform: uppercase; letter-spacing: .04em; }
nav .set { font-weight: bold; font-size: 15px; margin-bottom: 8px; }
main { flex: 1; padding: 16px 28px; max-width: 900px; font-family: "Times New Roman", serif; font-size: 12pt; }
main a { color: #0b4f8a; }
.crumbs { font-family: "Segoe UI", Arial, sans-serif; font-size: 12px; color: #666; margin-bottom: 8px; }
.pager { font-family: "Segoe UI", Arial, sans-serif; font-size: 13px; border-top: 1px solid #ddd; margin-top: 24px; padding-top: 8px; display: flex; justify-content: space-between; }
table.index { border-collapse: collapse; width: 100%; font-family: "Segoe UI", Arial, sans-serif; font-size: 13px; }
table.index th, table.index td { border: 1px solid #ccc; padding: 4px 6px; text-align: left; vertical-align: top; }
table.index th { background: #eee; }
.foot { font-family: "Segoe UI", Arial, sans-serif; font-size: 11px; color: #777; margin-top: 16px; }
@media print { nav, .pager { display: none; } main { max-width: none; } }
'@

function Main {
    if ($Path -cin @('help', '-h', '--help', '/?', '-?')) { $Help = $true }
    if ($Help -or -not $Path) {
        if ($PSCommandPath) { $h = Get-Content -LiteralPath $PSCommandPath -Raw; $i = $h.IndexOf('<#'); $j = $h.IndexOf('#>'); Out-Err ($h.Substring($i + 3, $j - $i - 3)) }
        else { Out-Err 'md2docs DIR [-Out SITE] [-Title TEXT] [-Word] [-Mark] [-Default CLS] [-Exclude PATTERN]' }
        if (-not $Help) { $script:RC = 2 }; return
    }
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) { throw "not a folder: $Path" }
    if (-not (Test-Path -LiteralPath $script:MD2DOCX -PathType Leaf)) { throw "md2docx.ps1 is not beside md2docs.ps1 ($script:MD2DOCX)" }
    $root = (Resolve-Path -LiteralPath $Path).Path.TrimEnd('\')
    if (-not $Out) { $Out = Join-Path $root '_site' }
    if (-not (Test-Path -LiteralPath $Out)) { New-Item -ItemType Directory -Force -Path $Out | Out-Null }
    $site = (Resolve-Path -LiteralPath $Out).Path.TrimEnd('\')
    if (-not $Title) { $Title = Split-Path $root -Leaf }
    $tmp = Join-Path $site '.md2docs-tmp'; if (-not (Test-Path -LiteralPath $tmp)) { New-Item -ItemType Directory -Force -Path $tmp | Out-Null }

    # the pages, in order: each folder's README.md / index.md first, then by name; folders after their parent's files
    $files = @(Get-ChildItem -LiteralPath $root -Recurse -File -Filter '*.md' -Force | Where-Object {
        $_.FullName -notmatch '\\\.git(\\|$)' -and -not $_.FullName.StartsWith($site + '\') -and $_.FullName -ne $site
    })
    $docs = @()
    foreach ($f in $files) {
        $rel = $f.FullName.Substring($root.Length + 1).Replace('\', '/')
        if ($Exclude -and $rel -match $Exclude) { continue }
        $dir = ''; if ($rel.Contains('/')) { $dir = $rel.Substring(0, $rel.LastIndexOf('/')) }
        $leaf = $rel.Substring($rel.LastIndexOf('/') + 1)
        $first = 1; if ($leaf -match '^(readme|index)\.md$') { $first = 0 }
        $docs += @{ rel = $rel; dir = $dir; leaf = $leaf; key = ($dir + "`t" + $first + "`t" + $leaf.ToLower()); file = $f.FullName; html = ($rel.Substring(0, $rel.Length - 3) + '.html') }
    }
    if (-not $docs.Count) { throw "no .md files under $root" }
    $docs = @($docs | Sort-Object -Property @{ Expression = { $_.key } })

    # every page through md2docx -Html -Links
    $n = 0
    foreach ($d in $docs) {
        $md = [regex]::Replace((ReadUtf8 $d.file), '(?s)<!--.*?-->[ \t]*\r?\n?', '')   # HTML comments are notes to editors, not text
        $d.title = DocTitle $md ($d.leaf.Substring(0, $d.leaf.Length - 3))
        $d.summary = DocSummary $md
        $d.md = $md
        $tmpOut = Join-Path $tmp ('page' + $n + '.html'); $tmpIn = Join-Path $tmp ('page' + $n + '.md'); $n++
        WriteUtf8 $tmpIn $md
        $h = @{ Path = $tmpIn; Html = $true; Links = $true; Out = $tmpOut }; if ($Mark) { $h.Mark = $true }; if ($Default) { $h.Default = $Default }
        $r = Invoke-Md2docx $h
        if ($r.rc -ne 0 -or -not (Test-Path -LiteralPath $tmpOut)) { Out-Err ("md2docs: $($d.rel): " + $r.out); $script:RC = 1; $d.body = '<p>(this page could not be converted: ' + (HEsc $r.out) + ')</p>'; $d.banner = ''; continue }
        $page = ReadUtf8 $tmpOut
        $m = [regex]::Match($page, '(?s)<body[^>]*>(.*)</body>')
        $body = $m.Groups[1].Value
        $bm = [regex]::Match($body, '^\s*<p style="text-align:center;font-weight:bold;margin:0 0 12pt 0">(.*?)</p>')
        $d.banner = ''; if ($bm.Success) { $d.banner = $bm.Groups[1].Value; $body = $body.Substring($bm.Length) }
        $body = [regex]::Replace($body, '<p style="text-align:center;font-weight:bold;margin:12pt 0 0 0">.*?</p>\s*$', '')
        $body = [regex]::Replace($body, 'href="([^"#:]*?)\.md(#[^"]*)?"', 'href="$1.html$2"')   # links between pages
        $ids = @{}; $out = ''; $pos = 0                   # heading ids as GitHub makes them, so page.md#heading links land
        foreach ($hm in [regex]::Matches($body, '<h([1-6])( style="[^"]*")?>(.*?)</h\1>')) {
            $txt = [regex]::Replace($hm.Groups[3].Value, '<[^>]+>', ''); $txt = [regex]::Replace($txt, '^\([A-Z/ ,]+\) ', '')
            $txt = $txt.Replace('&amp;', '&').Replace('&lt;', '<').Replace('&gt;', '>').Replace('&quot;', '"')
            $slug = [regex]::Replace($txt.ToLower(), '[^a-z0-9 _-]', '').Replace(' ', '-')
            $u = $slug; $q = 1; while ($ids.ContainsKey($u)) { $u = $slug + '-' + $q; $q++ }; $ids[$u] = 1
            $out += $body.Substring($pos, $hm.Index - $pos) + '<h' + $hm.Groups[1].Value + ' id="' + $u + '"' + $hm.Groups[2].Value + '>' + $hm.Groups[3].Value + '</h' + $hm.Groups[1].Value + '>'
            $pos = $hm.Index + $hm.Length
        }
        $body = $out + $body.Substring($pos)
        $d.body = $body.Trim()
        Remove-Item -LiteralPath $tmpOut, $tmpIn -Force
    }
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue

    $top = ''; $topRank = -1; foreach ($d in $docs) { $rk = BannerRank $d.banner; if ($rk -gt $topRank) { $topRank = $rk; $top = $d.banner } }
    $stamp = Get-Date -Format 'yyyy-MM-dd HH:mm'

    # pages
    for ($k = 0; $k -lt $docs.Count; $k++) {
        $d = $docs[$k]
        $nav = '<div class="set"><a href="' + (RelUrl $d.html 'index.html') + '">' + (HEsc $Title) + '</a></div>'
        $lastDir = $null
        foreach ($x in $docs) {
            if ($x.dir -ne $lastDir) { if ($x.dir) { $nav += '<div class="dir">' + (HEsc $x.dir) + '</div>' }; $lastDir = $x.dir }
            $cls = ''; if ($x.rel -eq $d.rel) { $cls = ' class="here"' }
            $nav += '<a' + $cls + ' href="' + (RelUrl $d.html $x.html) + '">' + (HEsc $x.title) + '</a>'
        }
        $pager = '<div class="pager"><span>'
        if ($k -gt 0) { $pager += '&larr; <a href="' + (RelUrl $d.html $docs[$k - 1].html) + '">' + (HEsc $docs[$k - 1].title) + '</a>' }
        $pager += '</span><span>'
        if ($k -lt $docs.Count - 1) { $pager += '<a href="' + (RelUrl $d.html $docs[$k + 1].html) + '">' + (HEsc $docs[$k + 1].title) + '</a> &rarr;' }
        $pager += '</span></div>'
        $ban = ''; $banB = ''; if ($d.banner) { $ban = '<div class="banner">' + $d.banner + '</div>'; $banB = '<div class="banner bottom">' + $d.banner + '</div>' }
        $html = "<!DOCTYPE html>`r`n<html lang=`"en`"><head><meta charset=`"utf-8`"><title>" + (HEsc ($d.title + ' - ' + $Title)) + "</title><style>" + $script:CSS + "</style></head>`r`n<body>" + $ban +
            '<div class="wrap"><nav>' + $nav + '</nav><main><div class="crumbs"><a href="' + (RelUrl $d.html 'index.html') + '">' + (HEsc $Title) + '</a> / ' + (HEsc $d.rel) + '</div>' + "`r`n" +
            $d.body + "`r`n" + $pager + '<div class="foot">' + (HEsc $d.rel) + ', made by md2docs ' + $stamp + '</div></main></div>' + $banB + "</body></html>`r`n"
        WriteUtf8 (Join-Path $site ($d.html.Replace('/', '\'))) $html
    }

    # index
    $rows = ''; $lastDir = $null
    foreach ($d in $docs) {
        if ($d.dir -ne $lastDir) { $lastDir = $d.dir; if ($d.dir) { $rows += '<tr><th colspan="3">' + (HEsc $d.dir) + '</th></tr>' } }
        $rows += '<tr><td><a href="' + $d.html + '">' + (HEsc $d.title) + '</a><br><span style="color:#777">' + (HEsc $d.rel) + '</span></td><td>' + (HEsc $d.summary) + '</td><td>' + $d.banner + '</td></tr>'
    }
    $ban = ''; $banB = ''; if ($top) { $ban = '<div class="banner">' + $top + '</div>'; $banB = '<div class="banner bottom">' + $top + '</div>' }
    $idx = "<!DOCTYPE html>`r`n<html lang=`"en`"><head><meta charset=`"utf-8`"><title>" + (HEsc $Title) + "</title><style>" + $script:CSS + "</style></head>`r`n<body>" + $ban +
        '<main style="max-width:1100px;margin:0 auto;font-family:''Segoe UI'',Arial,sans-serif"><h1>' + (HEsc $Title) + '</h1><p>' + $docs.Count + ' documents, made by md2docs ' + $stamp + ' from ' + (HEsc $root) + '.</p>' +
        '<table class="index"><tr><th>Document</th><th>Summary</th><th>Marking</th></tr>' + $rows + '</table></main>' + $banB + "</body></html>`r`n"
    WriteUtf8 (Join-Path $site 'index.html') $idx
    Write-Output ("md2docs: wrote $site\index.html and $($docs.Count) pages" + $(if ($top) { ", highest marking $top" } else { '' }))

    if ($Word) {                                        # one Word document: the title, then every page, headings one level down
        $all = @('# ' + $Title, '')
        foreach ($d in $docs) {
            $inCode = $false
            foreach ($l in (($d.md -replace "`r", '') -split "`n")) {
                if ($l -cmatch '^\s*```') { $inCode = -not $inCode }
                if (-not $inCode -and $l -cmatch '^(#{1,5})(\s.*)$') { $l = '#' + $Matches[1] + $Matches[2] }
                $all += $l
            }
            $all += ''; $all += '---'; $all += ''
        }
        $safe = ($Title -replace '[\\/:*?"<>|]', '_')
        $mdAll = Join-Path $site ($safe + '.md'); WriteUtf8 $mdAll (($all -join "`r`n") + "`r`n")
        $h = @{ Path = $mdAll; Out = (Join-Path $site ($safe + '.docx')) }; if ($Mark) { $h.Mark = $true }; if ($Default) { $h.Default = $Default }
        $r = Invoke-Md2docx $h
        if ($r.rc -ne 0) { Out-Err ('md2docs: the Word document failed: ' + $r.out); $script:RC = 1 } else { Write-Output ('md2docs: ' + ($r.out -replace '^md2docx: ', '')) }
    }
}

try { Main }
catch { Out-Err ('md2docs: ' + $_.Exception.Message); $script:RC = 1 }
if ($PSCommandPath) { exit $script:RC }
$global:LASTEXITCODE = $script:RC
