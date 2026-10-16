<#
md2docx.ps1 -- Markdown -> Word .docx with portion and banner markings, in Windows PowerShell 5.1.

Runs on a locked-down laptop: no install, no Word automation, no COM, no .NET zip, no network; it works
under Constrained Language Mode (AppLocker/WDAC). The .docx is written byte by byte (a stored zip with
CRC-32 computed here), so nothing beyond PowerShell itself is needed. Word opens the result.

  powershell -ExecutionPolicy Bypass -File md2docx.ps1 in.md [-Out out.docx] [options]
  ... in.md -Html  -> in.html (Teams post / Outlook mail)      ... in.md -Text [-Clip]  -> in.txt (Teams chat)

Markings follow the kit's tools/memo/md2memo.pl exactly:
  tags        {S}phrase{/S}  {C}...{/}  {TS//SI/TK//NF}...{/}  {S//REL TO USA, GBR}...{/}  {CUI}...{/}
              \{ prints a literal brace. Classes U CUI C S TS; controls after //, separated by /;
              SCI = SI TK HCS G KDK RSV; anything else after // is a dissemination control (NF, ORCON ...).
  portions    each paragraph, heading, list item, table and code block is marked with the rollup of its
              tags plus -Default: highest class, union of SCI and dissem controls, REL TO = intersection
              (dropped if any classified portion lacks it; NF wins).
  marks       "(U) ", "(CUI) ", "(S//NF) " as a prefix: after the number of a list item, in the first
              header cell of a table, on its own line above a code block.
  banners     top and bottom of every page (Word header and footer, centered) = the document rollup, long
              form: UNCLASSIFIED, CUI, SECRET//NOFORN, TOP SECRET//SI/TK//NOFORN ...
  marking is on when any tag is present, with -Mark, or with a non-U -Default. Tags are stripped.

Options
  -Out FILE       output (default: the input name with .docx)
  -Mark           mark even with no tags (every portion (U), UNCLASSIFIED banners)
  -Default CLS    the floor for every portion, e.g. -Default 'S//NF' (default U)
  -Banner doc     md2memo's per-page banners (-Banner page) cannot be done in Word, whose header is one per
                  section: the document rollup is used, and -Banner page says so
  -Memo           md2memo's memo layout: every paragraph numbered 1. a. (1) (a) _1_ _a_, headings in capitals
                  (# centered), emphasis underlined, a blank line between portions
  -Font times     times (Times New Roman 12, default) or courier (Courier New 12)
  -Indent PTS     -Memo: indent per level in points (default 18 times, 28.8 courier)
  -Links          with -Html: [text](url) becomes a real link (md2docs uses it for a document set); without it, as below
  -Html           one self-contained .html instead (inline styles, no scripts, no links out): open it in Edge,
                  Ctrl+A, Ctrl+C, then paste into a Teams post or an Outlook mail; headings, lists, tables,
                  marks and banners survive the paste
  -Text           plain text (.txt, CRLF) for a Teams chat message: marks, banners first and last line, lists,
                  tables as | cells |; md2memo --plain's role without its 65-column wrap and pages
  -Clip           with -Text: also put the text on the clipboard

Markdown: # headings, paragraphs, **strong** *em* `code`, - * + and 1. lists with nesting, | pipe | tables |
with :--: alignment, ``` fenced code (Courier New), --- rules, [links](url) as "text <url>", > quotes as text.
Exit 0 = written, 1 = error (bad tag or option, unreadable input, output locked), 2 = usage.
#>
param(
    [Parameter(Position = 0)][string]$Path,
    [string]$Out, [switch]$Mark, [string]$Default = 'U', [string]$Banner = 'doc', [switch]$Memo,
    [string]$Font = 'times', [double]$Indent = -1, [switch]$Html, [switch]$Text, [switch]$Clip, [switch]$Links, [switch]$Help
)
$ErrorActionPreference = 'Stop'
$script:RC = 0

function Out-Err([string]$t) { foreach ($l in ($t -split "`n")) { if ($l -ne '') { Write-Host $l -ForegroundColor Yellow } } }

# ================================================================ markings (md2memo.pl tagparse/rollup/fmt)
$script:CLSSHORT = @('U', 'CUI', 'C', 'S', 'TS')
$script:CLSLONG = @('UNCLASSIFIED', 'CUI', 'CONFIDENTIAL', 'SECRET', 'TOP SECRET')
$script:RANK = @{ 'U' = 0; 'CUI' = 1; 'C' = 2; 'S' = 3; 'TS' = 4 }
$script:SCISET = @{ 'SI' = 1; 'TK' = 1; 'HCS' = 1; 'G' = 1; 'KDK' = 1; 'RSV' = 1 }
$script:DLONG = @{ 'NF' = 'NOFORN'; 'OC' = 'ORCON'; 'IMC' = 'IMCON'; 'PR' = 'PROPIN' }
$script:TAGRX = '(?<!\\)\{((?:TS|S|C|CUI|U)(?://[^{}]*)?)\}'
$script:ENDRX = '(?<!\\)\{/[^{}]*\}'

function SortOrd($xs) {                                  # Perl's sort: ordinal string order
    $a1 = @($xs)
    for ($i = 1; $i -lt $a1.Count; $i++) {
        $v = $a1[$i]; $j = $i - 1
        while ($j -ge 0 -and [string]::CompareOrdinal($a1[$j], $v) -gt 0) { $a1[$j + 1] = $a1[$j]; $j-- }
        $a1[$j + 1] = $v
    }
    , $a1
}

function TagParse([string]$s) {
    $parts = $s.ToUpperInvariant() -split '//'
    $cls = $parts[0]
    if (-not $script:RANK.ContainsKey($cls) -or $cls -cnotmatch '^(U|CUI|C|S|TS)$') { throw "bad classification '$cls'" }
    $m = @{ r = $script:RANK[$cls]; sci = @{}; dis = @{}; rel = $null }
    for ($g = 1; $g -lt $parts.Count; $g++) {
        foreach ($tok0 in ($parts[$g] -split '/')) {
            $tok = $tok0.Trim()
            if ($tok -eq '') { continue }
            if ($tok -cmatch '^REL TO\s+(.*)') {
                $rel = @{}; foreach ($c in ($Matches[1] -split '\s*,\s*')) { $rel[$c] = 1 }; $m.rel = $rel
            }
            elseif ($script:SCISET.ContainsKey($tok)) { $m.sci[$tok] = 1 }
            else { $m.dis[$tok] = 1 }
        }
    }
    $m
}

function Rollup($ms) {
    $o = @{ r = 0; sci = @{}; dis = @{}; rel = $null }
    $relok = $true; $first = $true; $rel = @{}
    foreach ($m in @($ms)) {
        if ($m.r -gt $o.r) { $o.r = $m.r }
        foreach ($k in @($m.sci.Keys)) { $o.sci[$k] = 1 }
        foreach ($k in @($m.dis.Keys)) { $o.dis[$k] = 1 }
        if ($m.r -lt $script:RANK['C']) { continue }
        if ($null -eq $m.rel) { $relok = $false; continue }
        if ($first) { $rel = @{}; foreach ($k in @($m.rel.Keys)) { $rel[$k] = 1 }; $first = $false }
        else { foreach ($k in @($rel.Keys)) { if (-not $m.rel.ContainsKey($k)) { $rel.Remove($k) } } }
    }
    if ($relok -and -not $first -and -not $o.dis.ContainsKey('NF')) {
        $other = @($rel.Keys | Where-Object { $_ -cne 'USA' })
        if ($other.Count) { $o.rel = $rel } else { $o.dis['NF'] = 1 }
    }
    $o
}

function Fmt($m, [bool]$longForm) {
    $g = @(); if ($longForm) { $g += $script:CLSLONG[$m.r] } else { $g += $script:CLSSHORT[$m.r] }
    $sciList = SortOrd @($m.sci.Keys)
    if ($sciList.Count) { $g += ($sciList -join '/') }
    $dis = @(foreach ($k in (SortOrd @($m.dis.Keys))) { if ($longForm -and $script:DLONG.ContainsKey($k)) { $script:DLONG[$k] } else { $k } })
    if ($m.rel) {
        $us = @($m.rel.Keys | Where-Object { $_ -ceq 'USA' }); $rest = SortOrd @($m.rel.Keys | Where-Object { $_ -cne 'USA' })
        $dis += ('REL TO ' + ((@($us) + @($rest)) -join ', '))
    }
    if ($dis.Count) { $g += ($dis -join '/') }
    $g -join '//'
}

# a portion: its text with tags stripped, and its marking (rollup of -Default and its tags). Malformed tags
# (md2memo would print them as text) are errors here: a marking that silently drops is worse than a stop.
function Portion([string]$t, [int]$line) {
    $opens = 0; $closes = 0
    foreach ($mm in [regex]::Matches($t, '(?<!\\)\{([^{}]*)\}')) {
        $c = $mm.Groups[1].Value
        if ($c.StartsWith('/')) { $closes++; continue }
        if ($c -cmatch ('^' + '(?:TS|S|C|CUI|U)(?://[^{}]*)?' + '$')) { $opens++; continue }
        if ($c -match '^(?:ts|s|c|cui|u)(?://.*)?$') { throw "line ${line}: marking tag {$c} must be upper case" }
        if ($c -cmatch '^(?:TOP SECRET|SECRET|CONFIDENTIAL|UNCLASSIFIED|FOUO|U//FOUO)$' -or $c -cmatch '^[A-Z][A-Z ]*//') {
            throw "line ${line}: bad marking tag {$c} (classes are U CUI C S TS, e.g. {S//NF}...{/})"
        }
    }
    if ($opens -and -not $closes) { throw "line ${line}: marking tag opened but never closed with {/} in this portion" }
    if ($closes -and -not $opens) { throw "line ${line}: {/} closes a marking tag that was never opened in this portion" }
    $ms = @($script:DEF)
    foreach ($mm in [regex]::Matches($t, $script:TAGRX)) { $ms += (TagParse $mm.Groups[1].Value) }
    @{ text = [regex]::Replace($t, ($script:TAGRX + '|' + $script:ENDRX), ''); mark = (Rollup $ms) }
}

# ================================================================ inline Markdown -> runs
$script:ESC = '\`*_{}[]()#+-.!>'
function Inline([string]$s) {
    for ($i = 0; $i -lt $script:ESC.Length; $i++) {      # \X -> a private-use placeholder, restored at the end
        $s = $s.Replace('\' + $script:ESC[$i], [string][char](0xE000 + $i))
    }
    $s = $s -creplace '`([^`]*)`', ([string][char]0x0E + '$1' + [char]0x0F)
    $s = $s -creplace '!\[([^\]]*)\]\([^)]*\)', '$1'
    if ($Links -and $Html) { $s = $s -creplace '\[([^\]]*)\]\(([^)\s]*)[^)]*\)', ([string][char]0x10 + '$2' + [char]0x11 + '$1' + [char]0x12) }   # -Html -Links: real anchors
    else { $s = $s -creplace '\[([^\]]*)\]\(([^)\s]*)[^)]*\)', '$1 <$2>' }
    $s = $s -creplace '(\*\*|__)(?=\S)(.+?)(?<=\S)\1', ([string][char]0x01 + '$2' + [char]0x02)
    $s = $s -creplace '(?<![\w*])([*_])(?=\S)(.+?)(?<=\S)\1(?![\w*])', ([string][char]0x05 + '$2' + [char]0x06)
    for ($i = 0; $i -lt $script:ESC.Length; $i++) { $s = $s.Replace([string][char](0xE000 + $i), [string]$script:ESC[$i]) }
    $b = $false; $it = $false; $cd = $false; $href = $null; $url = $null; $inUrl = $false
    foreach ($p in ($s -split '([\x01\x02\x05\x06\x0E\x0F\x10\x11\x12])')) {
        if ($p -eq '') { continue }
        if ($p.Length -eq 1) {
            $o = [int][char]$p[0]
            if ($o -eq 1) { $b = $true; continue } elseif ($o -eq 2) { $b = $false; continue }
            elseif ($o -eq 5) { $it = $true; continue } elseif ($o -eq 6) { $it = $false; continue }
            elseif ($o -eq 14) { $cd = $true; continue } elseif ($o -eq 15) { $cd = $false; continue }
            elseif ($o -eq 16) { $inUrl = $true; $url = ''; continue } elseif ($o -eq 17) { $inUrl = $false; $href = $url; continue } elseif ($o -eq 18) { $href = $null; continue }
        }
        if ($inUrl) { $url += $p; continue }
        @{ t = $p; b = $b; i = $it; code = $cd; href = $href }
    }
}

# ================================================================ WordprocessingML
function X([string]$s) {                                 # XML text: escape, drop characters XML forbids
    $s = $s -replace '[\x00-\x08\x0B\x0C\x0E-\x1F]', ''
    $s.Replace('&', '&amp;').Replace('<', '&lt;').Replace('>', '&gt;').Replace('"', '&quot;')
}
function Run([string]$t, [bool]$b, [bool]$i, [bool]$u, [bool]$code) {
    if ($t -eq '') { return '' }
    $p = ''
    if ($code) { $p += '<w:rFonts w:ascii="Courier New" w:hAnsi="Courier New" w:cs="Courier New"/>' }
    if ($b) { $p += '<w:b/>' }; if ($i) { $p += '<w:i/>' }; if ($u) { $p += '<w:u w:val="single"/>' }
    if ($p) { $p = '<w:rPr>' + $p + '</w:rPr>' }
    '<w:r>' + $p + '<w:t xml:space="preserve">' + (X $t) + '</w:t></w:r>'
}
function Runs($runs, [bool]$upper) {
    (@(foreach ($r in @($runs)) {
        $t = $r.t; if ($upper) { $t = $t.ToUpper() }
        if ($Memo) { Run $t $false $false ($r.b -or $r.i) $r.code } else { Run $t $r.b $r.i $false $r.code }
    }) -join '')
}
function MarkRun($m) { if ($script:MARKING) { Run ('(' + (Fmt $m $false) + ') ') $false $false $false $false } else { '' } }
function Para([string]$ppr, [string]$body) { '<w:p>' + $(if ($ppr) { '<w:pPr>' + $ppr + '</w:pPr>' } else { '' }) + $body + '</w:p>' }

function Label([int]$lv, [int]$n) {                        # md2memo's paragraph labels: 1. a. (1) (a) _1_ _a_
    $a = [string][char](97 + ($n - 1) % 26)
    switch (($lv - 1) % 6) { 0 { "$n." } 1 { "$a." } 2 { "($n)" } 3 { "($a)" } 4 { "_$n" } 5 { "_$a" } }
}

# ================================================================ parse (md2memo.pl's block loop)
function Tcells([string]$s) {
    $s = $s -creplace '^\s*\|', ''; $s = $s -creplace '(?<!\\)\|\s*$', ''
    @(foreach ($c in ($s -split '(?<!\\)\|')) { ($c.Trim()) -creplace '\\\|', '|' })
}
function IsDelim([string]$s) { ($s -cmatch '^\s*\|?\s*:?-+:?\s*(?:\|\s*:?-+:?\s*)*\|?\s*$') -and ($s -cmatch '[|-]') }

function Parse([string[]]$in) {
    $blocks = @(); $para = @(); $paraAt = 0; $item = $null; $stack = @(); $code = $false; $cb = @(); $cbAt = 0
    $havePara = $false
    $flush = {
        if ($item) { $script:BL += $item; Set-Variable -Name item -Value $null -Scope 1 }
        elseif ($para.Count) { $script:BL += @{ kind = 'para'; text = ($para -join ' '); at = $paraAt }; Set-Variable -Name havePara -Value $true -Scope 1; Set-Variable -Name para -Value @() -Scope 1 }
    }
    $script:BL = @()
    for ($i = 0; $i -lt $in.Count; $i++) {
        $l = $in[$i]
        if ($null -eq $l) { continue }
        $l = $l.Replace("`t", '    ')
        if ($code) {
            if ($l -cmatch '^\s*```') { $code = $false; $script:BL += @{ kind = 'code'; lines = $cb; at = $cbAt }; $cb = @(); continue }
            $cb += $l; continue
        }
        if ($l -cmatch '^\s*```') { & $flush; $code = $true; $cbAt = $i + 1; continue }
        if ($l -cmatch '\|' -and $i -lt $in.Count - 1 -and (IsDelim $in[$i + 1])) {
            & $flush
            $t = @($l); $at = $i + 1
            while ($i -lt $in.Count - 1 -and $null -ne $in[$i + 1] -and $in[$i + 1] -cmatch '\|' -and $in[$i + 1] -cnotmatch '^\s*$') {
                $i++; $t += $in[$i].Replace("`t", '    ')
            }
            $script:BL += @{ kind = 'table'; rows = $t; at = $at }
            continue
        }
        if ($l -cmatch '^\s*$') { & $flush; continue }
        if ($l -cmatch '^(#{1,6})\s+(.*?)\s*#*\s*$') {
            & $flush; $stack = @(); $havePara = $false
            $script:BL += @{ kind = 'heading'; n = $Matches[1].Length; text = $Matches[2]; at = $i + 1 }; continue
        }
        if ($l -cmatch '^\s*([-*_])(\s*\1){2,}\s*$') { & $flush; $script:BL += @{ kind = 'hr'; at = $i + 1 }; continue }
        if ($l -cmatch '^(\s*)([-*+]|\d+[.)])\s+(.*)$') {
            & $flush
            $lead = $Matches[1].Length; $mk = $Matches[2]; $txt = $Matches[3]; $ord = $mk -cmatch '^\d'
            while ($stack.Count -and $stack[$stack.Count - 1] -gt $lead) { $stack = @($stack | Select-Object -First ($stack.Count - 1)) }
            if (-not ($stack.Count -and $stack[$stack.Count - 1] -eq $lead)) { $stack += $lead }
            $depth = $stack.Count
            $lvl = $depth; if ($havePara) { $lvl++ }
            $item = @{ kind = 'item'; depth = $depth; L = $lvl; ordered = $ord; lines = @($txt); at = $i + 1 }
            continue
        }
        $l = $l -creplace '^\s+', ''; $l = $l -creplace '^>\s?', ''
        if ($item) { $item.lines += $l }
        else { $stack = @(); if (-not $para.Count) { $paraAt = $i + 1 }; $para += $l }
    }
    if ($code) { $script:BL += @{ kind = 'code'; lines = $cb; at = $cbAt } }
    & $flush
    foreach ($b in $script:BL) { if ($b.kind -eq 'item') { $b.text = ($b.lines -join ' ') } }
    , $script:BL
}

# ================================================================ render
function Render($blocks) {
    $body = @(); $marks = @(); $cnt = @(0) * 32; $listNo = 0; $ordered = @{}; $prev = ''
    $lineAfter = if ($Memo) { '240' } else { '160' }
    foreach ($b in $blocks) {
        switch ($b.kind) {
            'para' {
                $p = Portion $b.text $b.at; $marks += $p.mark
                if ($Memo) {
                    $cnt[1]++; for ($k = 2; $k -lt 32; $k++) { $cnt[$k] = 0 }
                    $body += Para "<w:spacing w:after=`"$lineAfter`"/>" ((Runs @(@{ t = (Label 1 $cnt[1]) + '  '; b = $false; i = $false; code = $false }) $false) + (MarkRun $p.mark) + (Runs (Inline $p.text) $false))
                }
                else { $body += Para "<w:spacing w:after=`"$lineAfter`"/>" ((MarkRun $p.mark) + (Runs (Inline $p.text) $false)) }
            }
            'heading' {
                $p = Portion $b.text $b.at; $marks += $p.mark
                if ($Memo) {
                    $jc = if ($b.n -eq 1) { '<w:jc w:val="center"/>' } else { '' }
                    $body += Para ("<w:keepNext/><w:spacing w:after=`"$lineAfter`"/>" + $jc) ((MarkRun $p.mark) + (Runs (Inline $p.text) $true))
                }
                else { $body += Para ('<w:pStyle w:val="Heading' + $b.n + '"/>') ((MarkRun $p.mark) + (Runs (Inline $p.text) $false)) }
            }
            'item' {
                $p = Portion $b.text $b.at; $marks += $p.mark
                if ($Memo) {
                    $lv = $b.L; $cnt[$lv]++; for ($k = $lv + 1; $k -lt 32; $k++) { $cnt[$k] = 0 }
                    $lab = Label $lv $cnt[$lv]; $u = (($lv - 1) % 6) -ge 4; if ($u) { $lab = $lab.Substring(1) }
                    $first = [int]($script:STEP * ($lv - 1))
                    $body += Para "<w:spacing w:after=`"$lineAfter`"/><w:ind w:left=`"0`" w:firstLine=`"$first`"/>" ((Run $lab $false $false $u $false) + (Run '  ' $false $false $false $false) + (MarkRun $p.mark) + (Runs (Inline $p.text) $false))
                }
                else {
                    if ($prev -ne 'item') { $listNo++ }
                    $num = 1
                    if ($b.ordered) { if (-not $ordered.ContainsKey($listNo)) { $ordered[$listNo] = 2 + $ordered.Count }; $num = $ordered[$listNo] }
                    $lv = $b.depth - 1; if ($lv -gt 8) { $lv = 8 }
                    $body += Para ('<w:numPr><w:ilvl w:val="' + $lv + '"/><w:numId w:val="' + $num + '"/></w:numPr><w:spacing w:after="60"/>') ((MarkRun $p.mark) + (Runs (Inline $p.text) $false))
                }
            }
            'code' {
                $p = Portion ($b.lines -join "`n") $b.at; $marks += $p.mark
                if ($script:MARKING) { $body += Para '<w:keepNext/><w:spacing w:after="0"/>' (MarkRun $p.mark) }
                foreach ($c in ($p.text -split "`n")) {
                    $c = $c.Replace('\{', '{').Replace('\}', '}')
                    $body += Para '<w:pStyle w:val="Code"/>' (Run $c $false $false $false $false)
                }
                $body += Para '<w:spacing w:after="0"/>' ''
            }
            'table' {
                $rows = @($b.rows)
                $hdr = @(Tcells $rows[0])
                $align = @(foreach ($c in (Tcells $rows[1])) { if ($c -cmatch '^:-+:$') { 'center' } elseif ($c -cmatch '-:$') { 'right' } else { 'left' } })
                $nc = $hdr.Count
                $raw = @(, $hdr)
                for ($r = 2; $r -lt $rows.Count; $r++) {
                    $cs = Tcells $rows[$r]; $raw += , @(for ($c = 0; $c -lt $nc; $c++) { if ($c -lt $cs.Count) { $cs[$c] } else { '' } })
                }
                $all = @(foreach ($rw in $raw) { foreach ($c in $rw) { $c } }) -join ' '
                $p = Portion $all $b.at; $marks += $p.mark
                $nat = @(0) * $nc
                foreach ($rw in $raw) { for ($c = 0; $c -lt $nc; $c++) { $n = ([regex]::Replace($rw[$c], ($script:TAGRX + '|' + $script:ENDRX), '')).Length; if ($n -gt $nat[$c]) { $nat[$c] = $n } } }
                $tot = 0; for ($c = 0; $c -lt $nc; $c++) { if ($nat[$c] -lt 4) { $nat[$c] = 4 }; $tot += $nat[$c] }
                $wd = @(for ($c = 0; $c -lt $nc; $c++) { [int](9360 * $nat[$c] / $tot) })
                $x = '<w:tbl><w:tblPr><w:tblW w:w="5000" w:type="pct"/><w:tblBorders>'
                foreach ($e in 'top', 'left', 'bottom', 'right', 'insideH', 'insideV') { $x += "<w:$e w:val=`"single`" w:sz=`"4`" w:space=`"0`" w:color=`"000000`"/>" }
                $x += '</w:tblBorders><w:tblLayout w:type="autofit"/><w:tblCellMar><w:left w:w="72" w:type="dxa"/><w:right w:w="72" w:type="dxa"/></w:tblCellMar></w:tblPr><w:tblGrid>'
                foreach ($colW in $wd) { $x += "<w:gridCol w:w=`"$colW`"/>" }
                $x += '</w:tblGrid>'
                for ($r = 0; $r -lt $raw.Count; $r++) {
                    $x += '<w:tr>' + $(if ($r -eq 0) { '<w:trPr><w:tblHeader/></w:trPr>' } else { '' })
                    for ($c = 0; $c -lt $nc; $c++) {
                        $cp = Portion $raw[$r][$c] $b.at
                        $runs = @(Inline $cp.text)
                        if ($r -eq 0) { foreach ($rr in $runs) { $rr.b = $true } }
                        $pre = if ($r -eq 0 -and $c -eq 0) { MarkRun $p.mark } else { '' }
                        $ai = $c; if ($ai -gt $align.Count - 1) { $ai = $align.Count - 1 }; $jc = $align[$ai]
                        $x += '<w:tc><w:tcPr><w:tcW w:w="' + $wd[$c] + '" w:type="dxa"/></w:tcPr>' + (Para ('<w:spacing w:after="0"/><w:jc w:val="' + $jc + '"/>') ($pre + (Runs $runs $false))) + '</w:tc>'
                    }
                    $x += '</w:tr>'
                }
                $body += $x + '</w:tbl>'
                $body += Para "<w:spacing w:after=`"$lineAfter`"/>" ''
            }
            'hr' { $body += Para '<w:pBdr><w:bottom w:val="single" w:sz="6" w:space="1" w:color="000000"/></w:pBdr>' '' }
        }
        $prev = $b.kind
    }
    @{ body = $body; marks = $marks; lists = $listNo; ordered = $ordered }
}

# ================================================================ HTML and text (same blocks, same marks)
function HEsc([string]$s) { $s = $s -replace '[\x00-\x08\x0B\x0C\x0E-\x1F]', ''; $s.Replace('&', '&amp;').Replace('<', '&lt;').Replace('>', '&gt;').Replace('"', '&quot;') }
function HtmlRuns($runs, [bool]$upper) {
    (@(foreach ($r in @($runs)) {
        $t = $r.t; if ($upper) { $t = $t.ToUpper() }; $t = HEsc $t
        if ($r.code) { $t = '<code style="font-family:''Courier New'',monospace">' + $t + '</code>' }
        if ($Memo) { if ($r.b -or $r.i) { $t = '<u>' + $t + '</u>' } }
        else { if ($r.i) { $t = '<i>' + $t + '</i>' }; if ($r.b) { $t = '<b>' + $t + '</b>' } }
        if ($r.href) { $t = '<a href="' + (HEsc $r.href) + '">' + $t + '</a>' }
        $t
    }) -join '')
}
function HMark($m) { if ($script:MARKING) { HEsc ('(' + (Fmt $m $false) + ') ') } else { '' } }
function TMark($m) { if ($script:MARKING) { '(' + (Fmt $m $false) + ') ' } else { '' } }
function TextRuns($runs, [bool]$upper) { $t = (@(foreach ($r in @($runs)) { $r.t }) -join ''); if ($upper) { $t = $t.ToUpper() }; $t }

function TableCells($b) {                                # raw rows padded to the header width, alignments, the portion
    $rows = @($b.rows); $hdr = @(Tcells $rows[0])
    $align = @(foreach ($c in (Tcells $rows[1])) { if ($c -cmatch '^:-+:$') { 'center' } elseif ($c -cmatch '-:$') { 'right' } else { 'left' } })
    $nc = $hdr.Count; $raw = @(, $hdr)
    for ($r = 2; $r -lt $rows.Count; $r++) { $cs = @(Tcells $rows[$r]); $raw += , @(for ($c = 0; $c -lt $nc; $c++) { if ($c -lt $cs.Count) { $cs[$c] } else { '' } }) }
    $p = Portion (@(foreach ($rw in $raw) { foreach ($c in $rw) { $c } }) -join ' ') $b.at
    @{ raw = $raw; align = $align; nc = $nc; mark = $p.mark }
}

# HTML for a browser, a Teams post or an Outlook mail: inline styles only (pasting drops <style> blocks), no
# scripts, no external links, tables with explicit borders, lists as real <ul>/<ol>.
function RenderHtml($blocks) {
    $o = @(); $marks = @(); $cnt = @(0) * 32; $stack = @(); $li = @()
    $pStyle = 'margin:0 0 8pt 0'
    $closeLists = { while ($stack.Count) { $o2 = '</li></' + $stack[$stack.Count - 1] + '>'; Set-Variable -Name o -Scope 1 -Value ($o + $o2); Set-Variable -Name stack -Scope 1 -Value @($stack | Select-Object -First ($stack.Count - 1)) } }
    foreach ($b in $blocks) {
        if ($b.kind -ne 'item' -or $Memo) { & $closeLists }
        switch ($b.kind) {
            'para' {
                $p = Portion $b.text $b.at; $marks += $p.mark
                $lab = ''; if ($Memo) { $cnt[1]++; for ($k = 2; $k -lt 32; $k++) { $cnt[$k] = 0 }; $lab = (Label 1 $cnt[1]) + '&nbsp;&nbsp;' }
                $o += "<p style=`"$pStyle`">" + $lab + (HMark $p.mark) + (HtmlRuns (Inline $p.text) $false) + '</p>'
            }
            'heading' {
                $p = Portion $b.text $b.at; $marks += $p.mark
                $al = if ($Memo -and $b.n -eq 1) { 'text-align:center;' } else { '' }
                $sz = @(0, 16, 14, 13, 12, 12, 12)[$b.n]
                $o += "<h$($b.n) style=`"${al}font-size:${sz}pt;margin:12pt 0 6pt 0`">" + (HMark $p.mark) + (HtmlRuns (Inline $p.text) $Memo) + "</h$($b.n)>"
            }
            'item' {
                $p = Portion $b.text $b.at; $marks += $p.mark
                if ($Memo) {
                    $lv = $b.L; $cnt[$lv]++; for ($k = $lv + 1; $k -lt 32; $k++) { $cnt[$k] = 0 }
                    $lab = Label $lv $cnt[$lv]; if ((($lv - 1) % 6) -ge 4) { $lab = '<u>' + $lab.Substring(1) + '</u>' }
                    $o += "<p style=`"$pStyle;text-indent:$(18 * ($lv - 1))pt`">" + $lab + '&nbsp;&nbsp;' + (HMark $p.mark) + (HtmlRuns (Inline $p.text) $false) + '</p>'
                }
                else {
                    $d = $b.depth; $t = if ($b.ordered) { 'ol' } else { 'ul' }
                    while ($stack.Count -gt $d) { $o += '</li></' + $stack[$stack.Count - 1] + '>'; $stack = @($stack | Select-Object -First ($stack.Count - 1)) }
                    if ($stack.Count -eq $d -and $stack[$d - 1] -ne $t) { $o += '</li></' + $stack[$d - 1] + '>'; $stack = @($stack | Select-Object -First ($d - 1)) }
                    if ($stack.Count -eq $d) { $o += '</li>' }
                    while ($stack.Count -lt $d) { $o += "<$t style=`"margin:0 0 4pt 0`">"; $stack += $t }
                    $o += '<li style="margin:0 0 2pt 0">' + (HMark $p.mark) + (HtmlRuns (Inline $p.text) $false)
                }
            }
            'code' {
                $p = Portion ($b.lines -join "`n") $b.at; $marks += $p.mark
                if ($script:MARKING) { $o += "<p style=`"margin:0`">" + (HMark $p.mark) + '</p>' }
                $o += '<pre style="font-family:''Courier New'',monospace;font-size:9pt;margin:0 0 8pt 0">' + ((HEsc ($p.text.Replace('\{', '{').Replace('\}', '}'))) -replace "`n", '<br>') + '</pre>'
            }
            'table' {
                $tc = TableCells $b; $marks += $tc.mark
                $x = '<table style="border-collapse:collapse;margin:0 0 8pt 0" border="1" cellpadding="4" cellspacing="0">'
                for ($r = 0; $r -lt $tc.raw.Count; $r++) {
                    $x += '<tr>'
                    for ($c = 0; $c -lt $tc.nc; $c++) {
                        $ai = $c; if ($ai -gt $tc.align.Count - 1) { $ai = $tc.align.Count - 1 }
                        $cell = HtmlRuns (Inline (Portion $tc.raw[$r][$c] $b.at).text) $false
                        $cellTag = if ($r -eq 0) { 'th' } else { 'td' }
                        $pre = if ($r -eq 0 -and $c -eq 0) { HMark $tc.mark } else { '' }
                        $x += "<$cellTag style=`"border:1px solid #000;padding:2pt 4pt;text-align:$($tc.align[$ai]);vertical-align:top`">" + $pre + $cell + "</$cellTag>"
                    }
                    $x += '</tr>'
                }
                $o += $x + '</table>'
            }
            'hr' { $o += '<hr style="border:0;border-top:1px solid #000">' }
        }
    }
    & $closeLists
    @{ body = ($o -join "`r`n"); marks = $marks }
}

# plain text for a Teams chat message or a mail without formatting (md2memo --plain's role; no 65-column wrap or
# pages: the chat window wraps). Headings in capitals as md2memo prints them.
function RenderText($blocks) {
    $o = @(); $marks = @(); $cnt = @(0) * 32; $ocnt = @(0) * 32; $otype = @('') * 32; $prev = ''
    foreach ($b in $blocks) {
        if ($o.Count -and -not ($b.kind -eq 'item' -and $prev -eq 'item' -and -not $Memo)) { $o += '' }
        switch ($b.kind) {
            'para' {
                $p = Portion $b.text $b.at; $marks += $p.mark
                $lab = ''; if ($Memo) { $cnt[1]++; for ($k = 2; $k -lt 32; $k++) { $cnt[$k] = 0 }; $lab = (Label 1 $cnt[1]) + '  ' }
                $o += $lab + (TMark $p.mark) + (TextRuns (Inline $p.text) $false)
            }
            'heading' { $p = Portion $b.text $b.at; $marks += $p.mark; $o += (TMark $p.mark) + (TextRuns (Inline $p.text) $true) }
            'item' {
                $p = Portion $b.text $b.at; $marks += $p.mark
                if ($Memo) {
                    $lv = $b.L; $cnt[$lv]++; for ($k = $lv + 1; $k -lt 32; $k++) { $cnt[$k] = 0 }
                    $lab = Label $lv $cnt[$lv]; if ((($lv - 1) % 6) -ge 4) { $lab = $lab.Substring(1) }
                    $o += (' ' * (4 * ($lv - 1))) + $lab + '  ' + (TMark $p.mark) + (TextRuns (Inline $p.text) $false)
                }
                else {
                    $d = $b.depth
                    if ($prev -ne 'item') { $ocnt = @(0) * 32; $otype = @('') * 32 }
                    if ($otype[$d] -ne [string]$b.ordered) { $ocnt[$d] = 0; $otype[$d] = [string]$b.ordered }
                    $ocnt[$d]++; for ($k = $d + 1; $k -lt 32; $k++) { $ocnt[$k] = 0 }
                    $lab = if ($b.ordered) { "$($ocnt[$d])." } else { '-' }
                    $o += (' ' * (3 * ($d - 1))) + $lab + ' ' + (TMark $p.mark) + (TextRuns (Inline $p.text) $false)
                }
            }
            'code' {
                $p = Portion ($b.lines -join "`n") $b.at; $marks += $p.mark
                if ($script:MARKING) { $o += (TMark $p.mark).TrimEnd() }
                foreach ($c in ($p.text -split "`n")) { $o += $c.Replace('\{', '{').Replace('\}', '}') }
            }
            'table' {
                $tc = TableCells $b; $marks += $tc.mark
                $cells = @(for ($r = 0; $r -lt $tc.raw.Count; $r++) { , @(for ($c = 0; $c -lt $tc.nc; $c++) {
                    $t = TextRuns (Inline (Portion $tc.raw[$r][$c] $b.at).text) $false
                    if ($r -eq 0 -and $c -eq 0) { $t = (TMark $tc.mark) + $t }; $t }) })
                $colW = @(for ($c = 0; $c -lt $tc.nc; $c++) { $m = 3; foreach ($rw in $cells) { if ($rw[$c].Length -gt $m) { $m = $rw[$c].Length } }; $m })
                $line = { param($rw) '| ' + (@(for ($c = 0; $c -lt $tc.nc; $c++) {
                    $ai = $c; if ($ai -gt $tc.align.Count - 1) { $ai = $tc.align.Count - 1 }
                    $sp = $colW[$c] - $rw[$c].Length; $lf = 0
                    if ($tc.align[$ai] -eq 'right') { $lf = $sp } elseif ($tc.align[$ai] -eq 'center') { $lf = [int](($sp - ($sp % 2)) / 2) }
                    (' ' * $lf) + $rw[$c] + (' ' * ($sp - $lf)) }) -join ' | ') + ' |' }
                $o += (& $line $cells[0])
                $o += '|' + (@(foreach ($x in $colW) { '-' * ($x + 2) }) -join '|') + '|'
                for ($r = 1; $r -lt $cells.Count; $r++) { $o += (& $line $cells[$r]) }
            }
            'hr' { $o += ('-' * 40) }
        }
        $prev = $b.kind
    }
    @{ body = $o; marks = $marks }
}

function DocBanner($marks) {
    if (-not $script:MARKING) { return '' }
    $m = Rollup @($marks); if (-not @($marks).Count) { $m = $script:DEF }
    if ($Banner -eq 'page') { Out-Err 'md2docx: -Banner page: one document rollup is used for the banners' }
    Fmt $m $true
}
function WriteUtf8([string]$file, [string]$s) {
    try { Set-Content -LiteralPath $file -Encoding Byte -Value (Utf8 $s) }
    catch { throw "could not write $file (open in another program? close it and run again): $($_.Exception.Message)" }
}

# ================================================================ package parts
$script:NSW = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main'
$script:NSR = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships'
$script:HEAD = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' + "`r`n"

function StylesXml {
    $f = if ($Font -eq 'courier') { 'Courier New' } else { 'Times New Roman' }
    $s = $script:HEAD + "<w:styles xmlns:w=`"$($script:NSW)`"><w:docDefaults><w:rPrDefault><w:rPr><w:rFonts w:ascii=`"$f`" w:hAnsi=`"$f`" w:eastAsia=`"$f`" w:cs=`"$f`"/><w:sz w:val=`"24`"/><w:szCs w:val=`"24`"/><w:lang w:val=`"en-US`"/></w:rPr></w:rPrDefault><w:pPrDefault><w:pPr><w:spacing w:after=`"0`" w:line=`"240`" w:lineRule=`"auto`"/></w:pPr></w:pPrDefault></w:docDefaults>"
    $s += '<w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/><w:qFormat/></w:style>'
    $sz = @(0, 32, 28, 26, 24, 24, 24)
    for ($n = 1; $n -le 6; $n++) {
        $it = if ($n -ge 5) { '<w:i/>' } else { '' }
        $s += "<w:style w:type=`"paragraph`" w:styleId=`"Heading$n`"><w:name w:val=`"heading $n`"/><w:basedOn w:val=`"Normal`"/><w:next w:val=`"Normal`"/><w:qFormat/><w:pPr><w:keepNext/><w:keepLines/><w:spacing w:before=`"240`" w:after=`"120`"/><w:outlineLvl w:val=`"$($n - 1)`"/></w:pPr><w:rPr><w:b/>$it<w:sz w:val=`"$($sz[$n])`"/><w:szCs w:val=`"$($sz[$n])`"/></w:rPr></w:style>"
    }
    $s += '<w:style w:type="paragraph" w:styleId="Code"><w:name w:val="Code"/><w:basedOn w:val="Normal"/><w:pPr><w:keepLines/><w:spacing w:after="0" w:line="240" w:lineRule="auto"/></w:pPr><w:rPr><w:rFonts w:ascii="Courier New" w:hAnsi="Courier New" w:eastAsia="Courier New" w:cs="Courier New"/><w:sz w:val="18"/><w:szCs w:val="18"/></w:rPr></w:style>'
    $s += '<w:style w:type="paragraph" w:styleId="Header"><w:name w:val="header"/><w:basedOn w:val="Normal"/></w:style><w:style w:type="paragraph" w:styleId="Footer"><w:name w:val="footer"/><w:basedOn w:val="Normal"/></w:style>'
    $s + '</w:styles>'
}

function NumberingXml($ordered) {
    $bul = @([string][char]0x2022, 'o', [string][char]0x25AA)
    $bf = @('Symbol', 'Courier New', 'Wingdings')
    $s = $script:HEAD + "<w:numbering xmlns:w=`"$($script:NSW)`"><w:abstractNum w:abstractNumId=`"0`"><w:multiLevelType w:val=`"hybridMultilevel`"/>"
    for ($l = 0; $l -lt 9; $l++) {
        $ch = $bul[$l % 3]; $fn = if ($l % 3 -eq 1) { '<w:rPr><w:rFonts w:ascii="Courier New" w:hAnsi="Courier New" w:cs="Courier New"/></w:rPr>' } else { '' }
        $s += "<w:lvl w:ilvl=`"$l`"><w:start w:val=`"1`"/><w:numFmt w:val=`"bullet`"/><w:lvlText w:val=`"$(X $ch)`"/><w:lvlJc w:val=`"left`"/><w:pPr><w:ind w:left=`"$(720 * ($l + 1))`" w:hanging=`"360`"/></w:pPr>$fn</w:lvl>"
    }
    $s += '</w:abstractNum><w:abstractNum w:abstractNumId="1"><w:multiLevelType w:val="multilevel"/>'
    $fmts = @('decimal', 'lowerLetter', 'lowerRoman')
    for ($l = 0; $l -lt 9; $l++) {
        $s += "<w:lvl w:ilvl=`"$l`"><w:start w:val=`"1`"/><w:numFmt w:val=`"$($fmts[$l % 3])`"/><w:lvlText w:val=`"%$($l + 1).`"/><w:lvlJc w:val=`"left`"/><w:pPr><w:ind w:left=`"$(720 * ($l + 1))`" w:hanging=`"360`"/></w:pPr></w:lvl>"
    }
    $s += '</w:abstractNum><w:num w:numId="1"><w:abstractNumId w:val="0"/></w:num>'
    foreach ($k in @($ordered.Values | Sort-Object)) {
        $s += "<w:num w:numId=`"$k`"><w:abstractNumId w:val=`"1`"/>"
        for ($l = 0; $l -lt 9; $l++) { $s += "<w:lvlOverride w:ilvl=`"$l`"><w:startOverride w:val=`"1`"/></w:lvlOverride>" }
        $s += '</w:num>'
    }
    $s + '</w:numbering>'
}

function HdrFtr([string]$part, [string]$line) {
    $script:HEAD + "<w:$part xmlns:w=`"$($script:NSW)`"><w:p><w:pPr><w:jc w:val=`"center`"/></w:pPr>" + (Run $line $true $false $false $false) + "</w:p></w:$part>"
}

# ================================================================ bytes, CRC-32, stored zip
function Utf8([string]$s) {                               # UTF-8 bytes without .NET encoders (CLM)
    $cs = $s.ToCharArray(); $n = $cs.Length
    $bytesOut = for ($i = 0; $i -lt $n; $i++) {
        $o = [int]$cs[$i]
        if ($o -lt 0x80) { $o; continue }
        if ($o -ge 0xD800 -and $o -le 0xDBFF -and $i + 1 -lt $n) {
            $lo = [int]$cs[$i + 1]
            if ($lo -ge 0xDC00 -and $lo -le 0xDFFF) {
                $i++; $cp = 0x10000 + (($o - 0xD800) -shl 10) + ($lo - 0xDC00)
                0xF0 -bor ($cp -shr 18); 0x80 -bor (($cp -shr 12) -band 0x3F); 0x80 -bor (($cp -shr 6) -band 0x3F); 0x80 -bor ($cp -band 0x3F)
                continue
            }
        }
        if ($o -lt 0x800) { 0xC0 -bor ($o -shr 6); 0x80 -bor ($o -band 0x3F); continue }
        0xE0 -bor ($o -shr 12); 0x80 -bor (($o -shr 6) -band 0x3F); 0x80 -bor ($o -band 0x3F)
    }
    , [byte[]]@($bytesOut)
}

$script:CRCT = @(for ($n = 0; $n -lt 256; $n++) {
    [long]$c = $n
    for ($k = 0; $k -lt 8; $k++) { if ($c -band 1) { $c = [long]3988292384 -bxor ($c -shr 1) } else { $c = $c -shr 1 } }
    $c
})
function Crc32([byte[]]$bytes) {
    [long]$c = 4294967295; $t = $script:CRCT
    foreach ($b in $bytes) { $c = $t[($c -bxor $b) -band 255] -bxor ($c -shr 8) }
    $c -bxor [long]4294967295
}
function LE16([long]$v) { [int]($v -band 255); [int](($v -shr 8) -band 255) }
function LE32([long]$v) { [int]($v -band 255); [int](($v -shr 8) -band 255); [int](($v -shr 16) -band 255); [int](($v -shr 24) -band 255) }

function ZipBytes($entries) {                            # entries: @{ name; data = [byte[]] } in order
    $d = Get-Date
    [long]$tm = ($d.Hour -shl 11) -bor ($d.Minute -shl 5) -bor ($d.Second -shr 1)
    [long]$dt = (($d.Year - 1980) -shl 9) -bor ($d.Month -shl 5) -bor $d.Day
    $local = @(); $central = @(); [long]$off = 0
    foreach ($e in $entries) {
        $nm = Utf8 $e.name; $crc = Crc32 $e.data; $len = $e.data.Length
        $h = @(LE32 0x04034b50) + @(LE16 20) + @(LE16 0) + @(LE16 0) + @(LE16 $tm) + @(LE16 $dt) + @(LE32 $crc) + @(LE32 $len) + @(LE32 $len) + @(LE16 $nm.Length) + @(LE16 0)
        $local += , ([byte[]]$h); $local += , $nm; $local += , $e.data
        $c = @(LE32 0x02014b50) + @(LE16 20) + @(LE16 20) + @(LE16 0) + @(LE16 0) + @(LE16 $tm) + @(LE16 $dt) + @(LE32 $crc) + @(LE32 $len) + @(LE32 $len) + @(LE16 $nm.Length) + @(LE16 0) + @(LE16 0) + @(LE16 0) + @(LE16 0) + @(LE32 0) + @(LE32 $off)
        $central += , ([byte[]]$c); $central += , $nm
        $off += $h.Count + $nm.Length + $len
    }
    [long]$cdSize = 0; foreach ($p in $central) { $cdSize += $p.Length }
    $endRec = [byte[]](@(LE32 0x06054b50) + @(LE16 0) + @(LE16 0) + @(LE16 $entries.Count) + @(LE16 $entries.Count) + @(LE32 $cdSize) + @(LE32 $off) + @(LE16 0))
    $all = foreach ($p in ($local + $central + @(, $endRec))) { $p }
    , [byte[]]@($all)
}

# ================================================================ main
function Main {
    if ($Path -cin @('help', '-h', '--help', '/?', '-?')) { $Help = $true }
    if ($Help -or -not $Path) {
        if (-not $PSCommandPath) { Out-Err 'md2docx in.md [-Out FILE] [-Html | -Text [-Clip]] [-Mark] [-Default CLS] [-Memo] [-Font times|courier] [-Indent PTS]'; if (-not $Help) { $script:RC = 2 }; return }
        $h = Get-Content -LiteralPath $PSCommandPath -Raw
        $i = $h.IndexOf('<#'); $j = $h.IndexOf('#>')
        Out-Err ($h.Substring($i + 3, $j - $i - 3)); if (-not $Path -and -not $Help) { $script:RC = 2 }; return
    }
    if ($Banner -cnotmatch '^(page|doc)$') { throw '-Banner must be page or doc' }
    if ($Font -cnotmatch '^(times|courier)$') { throw '-Font must be times or courier' }
    $script:DEF = TagParse $Default
    $script:STEP = if ($Indent -ge 0) { $Indent * 20 } elseif ($Font -eq 'courier') { 576 } else { 360 }
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "cannot read $Path" }
    $src = Get-Content -LiteralPath $Path -Encoding UTF8 -Raw
    if ($null -eq $src) { $src = '' }
    $in = @($src.Replace("`r`n", "`n").Replace("`r", "`n") -split "`n")
    if ($in.Count -and $in[$in.Count - 1] -eq '') { $in = @($in | Select-Object -First ($in.Count - 1)) }
    $script:MARKING = $Mark -or ($Default.ToUpper() -cne 'U') -or [bool]($src -cmatch $script:TAGRX)

    if ($Html -and $Text) { throw 'choose one of -Html and -Text' }
    $base = [regex]::Replace($Path, '\.[^.\\/]*$', '')
    if ($Html -or $Text) {
        $blocks = Parse $in
        $title = ''; foreach ($l in $in) { if ($l -cmatch '^#\s+(.*?)\s*#*\s*$') { $title = [regex]::Replace($Matches[1], ($script:TAGRX + '|' + $script:ENDRX), ''); break } }
        if ($Html) {
            $r = RenderHtml $blocks; $bt = DocBanner $r.marks
            $ban = if ($bt) { '<p style="text-align:center;font-weight:bold;margin:0 0 12pt 0">' + (HEsc $bt) + '</p>' } else { '' }
            $ff = if ($Font -eq 'courier') { "'Courier New',monospace" } else { "'Times New Roman',serif" }
            $page = "<!DOCTYPE html>`r`n<html><head><meta charset=`"utf-8`"><title>" + (HEsc $title) + "</title></head>`r`n<body style=`"font-family:$ff;font-size:12pt;max-width:7in`">`r`n" +
                $ban + "`r`n" + $r.body + "`r`n" + ($ban -replace 'margin:0 0 12pt 0', 'margin:12pt 0 0 0') + "`r`n</body></html>`r`n"
            if (-not $Out) { $Out = $base + '.html' }
            WriteUtf8 $Out $page
        }
        else {
            $r = RenderText $blocks; $bt = DocBanner $r.marks
            $lines = @($r.body); if ($bt) { $lines = @($bt, '') + $lines + @('', $bt) }
            $txt = ($lines -join "`r`n") + "`r`n"
            if (-not $Out) { $Out = $base + '.txt' }
            WriteUtf8 $Out $txt
            if ($Clip) { Set-Clipboard -Value $txt; Out-Err 'md2docx: the text is on the clipboard: paste it into the Teams chat (Ctrl+V)' }
        }
        $msg = "md2docx: wrote $Out (" + @($r.marks).Count + ' portions'
        if ($bt) { $msg += ", banner $bt" } else { $msg += ', unmarked' }
        Write-Output ($msg + ')')
        return
    }
    $doc = Render (Parse $in)
    $body = @($doc.body)
    if ($body.Count -eq 0 -or $body[$body.Count - 1].StartsWith('<w:tbl')) { $body += '<w:p/>' }
    $bannerText = ''
    if ($script:MARKING) {
        $docm = Rollup @($doc.marks)
        if (-not @($doc.marks).Count) { $docm = $script:DEF }
        $bannerText = Fmt $docm $true
        if ($Banner -eq 'page') { Out-Err 'md2docx: -Banner page: a Word header is one per section, so every page carries the document rollup' }
    }
    $sect = '<w:sectPr>'
    if ($bannerText) { $sect += '<w:headerReference w:type="default" r:id="rIdH"/><w:footerReference w:type="default" r:id="rIdF"/>' }
    $sect += '<w:pgSz w:w="12240" w:h="15840"/><w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440" w:header="720" w:footer="720" w:gutter="0"/></w:sectPr>'
    $docXml = $script:HEAD + "<w:document xmlns:w=`"$($script:NSW)`" xmlns:r=`"$($script:NSR)`"><w:body>" + ($body -join '') + $sect + '</w:body></w:document>'

    $title = ''
    foreach ($l in $in) { if ($l -cmatch '^#\s+(.*?)\s*#*\s*$') { $title = [regex]::Replace($Matches[1], ($script:TAGRX + '|' + $script:ENDRX), ''); break } }
    $ct = $script:HEAD + '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/>' +
        '<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>' +
        '<Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>' +
        '<Override PartName="/word/numbering.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.numbering+xml"/>' +
        '<Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/>'
    if ($bannerText) { $ct += '<Override PartName="/word/header1.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.header+xml"/><Override PartName="/word/footer1.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.footer+xml"/>' }
    $ct += '</Types>'
    $rels = $script:HEAD + '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/><Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/></Relationships>'
    $drels = $script:HEAD + '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/><Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/numbering" Target="numbering.xml"/>'
    if ($bannerText) { $drels += '<Relationship Id="rIdH" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/header" Target="header1.xml"/><Relationship Id="rIdF" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/footer" Target="footer1.xml"/>' }
    $drels += '</Relationships>'
    $now = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    $core = $script:HEAD + '<cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:dcterms="http://purl.org/dc/terms/" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">' +
        '<dc:title>' + (X $title) + '</dc:title>' + $(if ($bannerText) { '<cp:keywords>' + (X $bannerText) + '</cp:keywords>' } else { '' }) +
        '<dcterms:created xsi:type="dcterms:W3CDTF">' + $now + '</dcterms:created></cp:coreProperties>'

    $entries = @(
        @{ name = '[Content_Types].xml'; data = (Utf8 $ct) },
        @{ name = '_rels/.rels'; data = (Utf8 $rels) },
        @{ name = 'docProps/core.xml'; data = (Utf8 $core) },
        @{ name = 'word/_rels/document.xml.rels'; data = (Utf8 $drels) },
        @{ name = 'word/document.xml'; data = (Utf8 $docXml) },
        @{ name = 'word/styles.xml'; data = (Utf8 (StylesXml)) },
        @{ name = 'word/numbering.xml'; data = (Utf8 (NumberingXml $doc.ordered)) }
    )
    if ($bannerText) { $entries += @{ name = 'word/header1.xml'; data = (Utf8 (HdrFtr 'hdr' $bannerText)) }; $entries += @{ name = 'word/footer1.xml'; data = (Utf8 (HdrFtr 'ftr' $bannerText)) } }
    $bytes = ZipBytes $entries

    if (-not $Out) { $Out = [regex]::Replace($Path, '\.[^.\\/]*$', '') + '.docx' }
    try { Set-Content -LiteralPath $Out -Encoding Byte -Value $bytes }
    catch { throw "could not write $Out (open in Word? close it and run again): $($_.Exception.Message)" }
    $msg = "md2docx: wrote $Out (" + @($doc.marks).Count + ' portions'
    if ($bannerText) { $msg += ", banner $bannerText" } else { $msg += ', unmarked' }
    Write-Output ($msg + ')')
}

try { Main }
catch { Out-Err ('md2docx: ' + $_.Exception.Message); $script:RC = 1 }
if ($PSCommandPath) { exit $script:RC }
$global:LASTEXITCODE = $script:RC
