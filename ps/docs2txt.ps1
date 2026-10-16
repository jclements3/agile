<#
docs2txt.ps1 -- read Office and PDF documents as text, in Windows PowerShell 5.1 (Constrained Language Mode safe).
The agile kit's bin/docs2txt.pl, with the converters built in: no Git for Windows, no pdftotext, no Word automation.

  docs2txt FILE...                    the text of each file (a "==> FILE <==" header when more than one)
  docs2txt -o DIR FILE...             write DIR\<name>.txt per file instead (then grep, diff or pvi them)
  docs2txt grep [-i] PATTERN FILE...  "FILE:LINE: text" for each matching line: greps a .docx or a PDF like a .txt
  docs2txt tools                      what reads each format

Formats
  .docx .docm .dotx    paragraphs as lines, tables as tab-separated rows, then footnotes, headers and footers
  .xlsx .xlsm          each sheet as "== Sheet: NAME ==" and tab-separated rows (values as Excel last saved them)
  .pptx                each slide as "== Slide N ==" with its text, then its speaker notes
  .odt .ods .odp       paragraphs and table rows
  .html .htm           tags stripped (as docs2txt.pl does)
  .txt .md .csv .log .text .xml .json .sysml .ini .conf    as they are
  .pdf                 the text operators of each page (FlateDecode streams, ToUnicode maps): enough to grep a PDF
                       that Word, Edge or LaTeX wrote; not a layout. A scanned PDF has no text to find.
  .doc .xls .ppt       the old binary formats are not read: open the file in Office and save it as .docx/.xlsx/.pptx
Wildcards work: docs2txt grep -i radar *.docx
Exit 0 = done, 2 = a file could not be read (the others are still done), as docs2txt.pl.
#>
$ErrorActionPreference = 'Stop'
$script:RC = 0
$script:HERE = $PSScriptRoot; if (-not $script:HERE) { $script:HERE = (Get-Location).Path }
$zl = Join-Path $script:HERE 'ziplib.ps1'
if (Test-Path -LiteralPath $zl) { . $zl } else { throw 'ziplib.ps1 must be beside docs2txt.ps1' }

function Out-Err([string]$t) { foreach ($l in ($t -split "`n")) { if ($l -ne '') { Write-Host $l } } }
$script:HEXD = @{}; for ($i = 0; $i -lt 16; $i++) { $script:HEXD[('{0:x}' -f $i)] = $i; $script:HEXD[('{0:X}' -f $i)] = $i }
function HexVal([string]$h) { $v = 0; foreach ($ch in $h.ToCharArray()) { $v = $v * 16 + $script:HEXD[[string]$ch] }; return $v }   # no [Convert] under CLM
function ReplaceEach([string]$s, [string]$pat, [string]$kind) {   # regex replace with computed text (CLM refuses a scriptblock evaluator)
    $o = ''; $pos = 0
    foreach ($m in [regex]::Matches($s, $pat)) {
        $o += $s.Substring($pos, $m.Index - $pos)
        switch ($kind) {
            'hexent' { $o += [string][char](HexVal $m.Groups[1].Value) }
            'decent' { $o += [string][char][int]$m.Groups[1].Value }
            'odfspace' { $n = 1; if ($m.Groups[1].Success) { $n = [int]$m.Groups[1].Value }; $o += (' ' * $n) }
            'wt' { $o += [string][char]1 + $m.Groups[1].Value + [char]2 }
        }
        $pos = $m.Index + $m.Length
    }
    return ($o + $s.Substring($pos))
}
function Latin1([byte[]]$b) { if ($null -eq $b -or $b.Length -eq 0) { return '' }; return (-join [char[]]$b) }
function Utf8Of([byte[]]$b) { if ($null -eq $b -or $b.Length -eq 0) { return '' }; $o = 0; if ($b.Length -ge 3 -and $b[0] -eq 239 -and $b[1] -eq 187 -and $b[2] -eq 191) { $o = 3 }; return (Zl-Utf8Dec $b $o ($b.Length - $o) $true) }
function Ent([string]$s) {                            # XML entities
    if ($s.IndexOf('&') -lt 0) { return $s }
    $s = ReplaceEach $s '&#x([0-9A-Fa-f]+);' 'hexent'
    $s = ReplaceEach $s '&#(\d+);' 'decent'
    return $s.Replace('&lt;', '<').Replace('&gt;', '>').Replace('&quot;', '"').Replace('&apos;', "'").Replace('&amp;', '&')
}
function ZipText([string]$f, [string]$name) { $e = @(Read-ZipEntries $f | Where-Object { $_.name -ceq $name }); if (-not $e.Count) { return $null }; return (Utf8Of (Read-ZipEntry $f $name)) }
function ZipNames([string]$f) { return @(Read-ZipEntries $f | ForEach-Object { $_.name }) }

# ---------------------------------------------------------------- WordprocessingML
function WmlText([string]$x) {                         # a document/footnotes/header part -> lines
    if (-not $x) { return '' }
    $x = [regex]::Replace($x, '(?s)<w:(instrText|delText|fldData)\b.*?</w:\1>', '')       # field codes and deleted text are not text
    $x = [regex]::Replace($x, '<w:tab/>|<w:tab [^>]*/>', "`t")
    $x = [regex]::Replace($x, '<w:(br|cr)\b[^>]*/>', "`n")
    $x = [regex]::Replace($x, '(?s)</w:p>(?=(?:(?!<w:tc[ >]).)*?</w:tc>)', ' ')   # paragraphs inside a cell: one line per row
    $x = [regex]::Replace($x, '</w:tc>', "`t")
    $x = [regex]::Replace($x, '</w:tr>', "`n")
    $x = [regex]::Replace($x, '</w:p>', "`n")
    $x = ReplaceEach $x '<w:t(?: [^>]*)?>([^<]*)</w:t>' 'wt'
    $o = ''
    foreach ($m in [regex]::Matches($x, "\x01([^\x02]*)\x02|(\t|\n)")) { if ($m.Groups[1].Success) { $o += $m.Groups[1].Value } else { $o += $m.Groups[2].Value } }
    $o = [regex]::Replace($o, " +\t", "`t"); $o = [regex]::Replace($o, "[ \t]+\n", "`n")   # a cell's last paragraph, a row's last cell
    return (Ent $o)
}
function DocxText([string]$f) {
    $names = ZipNames $f
    $o = WmlText (ZipText $f 'word/document.xml')
    foreach ($part in 'word/footnotes.xml', 'word/endnotes.xml') { if ($names -contains $part) { $t = (WmlText (ZipText $f $part)).Trim(); if ($t) { $o += "`n" + $t + "`n" } } }
    foreach ($n in ($names | Where-Object { $_ -match '^word/(header|footer)\d*\.xml$' } | Sort-Object)) { $t = (WmlText (ZipText $f $n)).Trim(); if ($t) { $o += $t + "`n" } }
    return $o
}

# ---------------------------------------------------------------- SpreadsheetML
function ColNum([string]$ref) { $c = 0; foreach ($ch in ($ref -replace '\d', '').ToCharArray()) { $c = $c * 26 + ([int]$ch - 64) }; return $c }
function XlsxDateStyles([string]$f) {                   # cell style index -> $true when its number format shows a date or time
    $st = ZipText $f 'xl/styles.xml'; $isDate = @{}; if (-not $st) { return $isDate }
    $custom = @{}; foreach ($m in [regex]::Matches($st, '<numFmt [^>]*?numFmtId="(\d+)"[^>]*?formatCode="([^"]*)"')) { $custom[[int]$m.Groups[1].Value] = Ent $m.Groups[2].Value }
    $xfs = [regex]::Match($st, '(?s)<cellXfs[^>]*>(.*?)</cellXfs>').Groups[1].Value
    $k = 0
    foreach ($x in [regex]::Matches($xfs, '<xf\b[^>]*?(?:/>|>)')) {
        $id = [int]([regex]::Match($x.Value, 'numFmtId="(\d+)"').Groups[1].Value)
        $d = ($id -ge 14 -and $id -le 22) -or ($id -ge 45 -and $id -le 47)
        if ($custom.ContainsKey($id)) { $code = [regex]::Replace($custom[$id], '"[^"]*"|\[[^\]]*\]|\\.', ''); $d = $code -match '[dmyhs]' -and $code -notmatch '^General$' }
        $isDate[$k] = $d; $k++
    }
    return $isDate
}
function XlsxDate([double]$v) {                          # an Excel serial date (1900 system) -> yyyy-MM-dd [HH:mm:ss]
    $day = [long]($v - ($v % 1)); $frac = $v - $day
    $dt = (Get-Date -Year 1899 -Month 12 -Day 30 -Hour 0 -Minute 0 -Second 0 -Millisecond 0).AddDays($day).AddSeconds([long]($frac * 86400 + 0.5))
    if ($frac -eq 0) { return $dt.ToString('yyyy-MM-dd') }; return $dt.ToString('yyyy-MM-dd HH:mm:ss')
}
function XlsxText([string]$f) {
    $ss = @(); $dates = XlsxDateStyles $f
    $sst = ZipText $f 'xl/sharedStrings.xml'
    if ($sst) { foreach ($si in [regex]::Matches($sst, '(?s)<si>(.*?)</si>')) { $t = ''; foreach ($m in [regex]::Matches($si.Groups[1].Value, '<t(?: [^>]*)?>([^<]*)</t>')) { $t += $m.Groups[1].Value }; $ss += (Ent $t) } }
    $wb = ZipText $f 'xl/workbook.xml'; $rels = ZipText $f 'xl/_rels/workbook.xml.rels'
    $target = @{}; foreach ($m in [regex]::Matches($rels, '<Relationship [^>]*?Id="([^"]+)"[^>]*?Target="([^"]+)"')) { $target[$m.Groups[1].Value] = $m.Groups[2].Value }
    foreach ($m in [regex]::Matches($rels, '<Relationship [^>]*?Target="([^"]+)"[^>]*?Id="([^"]+)"')) { $target[$m.Groups[2].Value] = $m.Groups[1].Value }
    $o = ''
    foreach ($s in [regex]::Matches($wb, '<sheet [^>]*?name="([^"]*)"[^>]*?r:id="([^"]+)"')) {
        $name = Ent $s.Groups[1].Value; $t = $target[$s.Groups[2].Value]; if (-not $t) { continue }
        $path = $t.TrimStart('/'); if (-not $path.StartsWith('xl/')) { $path = 'xl/' + $path }
        $x = ZipText $f $path; if (-not $x) { continue }
        $o += "== Sheet: $name ==`n"
        foreach ($row in [regex]::Matches($x, '(?s)<row\b[^>]*?(?:/>|>(.*?)</row>)')) {
            $cells = @{}; $max = 0; $col = 0
            foreach ($c in [regex]::Matches($row.Groups[1].Value, '(?s)<c\b([^>]*?)(?:/>|>(.*?)</c>)')) {
                $at = $c.Groups[1].Value; $body = $c.Groups[2].Value
                $r = [regex]::Match($at, 'r="([A-Z]+)\d+"'); if ($r.Success) { $col = ColNum $r.Groups[1].Value } else { $col++ }
                $ty = [regex]::Match($at, 't="([^"]+)"').Groups[1].Value
                $v = [regex]::Match($body, '<v>([^<]*)</v>').Groups[1].Value
                if ($ty -eq 's') { $v = $ss[[int]$v] } elseif ($ty -eq 'inlineStr') { $v = ''; foreach ($m in [regex]::Matches($body, '<t(?: [^>]*)?>([^<]*)</t>')) { $v += $m.Groups[1].Value }; $v = Ent $v }
                elseif ($ty -eq 'b') { if ($v -eq '1') { $v = 'TRUE' } else { $v = 'FALSE' } }
                elseif ($ty -eq '' -or $ty -eq 'n') {           # a number: as Excel shows it (5.0 -> 5; a date style -> the date)
                    if ($v -ne '') { $sm = [regex]::Match($at, '\bs="(\d+)"'); if ($sm.Success -and $dates[[int]$sm.Groups[1].Value] -and $v -match '^-?[\d.]+$') { $v = XlsxDate ([double]$v) } elseif ($v -match '^(-?\d+)\.0+$') { $v = $Matches[1] } }
                } else { $v = Ent $v }
                $cells[$col] = $v; if ($v -ne '' -and $col -gt $max) { $max = $col }   # an empty cell does not make a row
            }
            if ($max -eq 0) { continue }
            $line = @(); for ($k = 1; $k -le $max; $k++) { $line += [string]$cells[$k] }
            $o += ($line -join "`t") + "`n"
        }
    }
    return $o
}

# ---------------------------------------------------------------- PresentationML
function DmlParas([string]$x) { $o = ''; foreach ($p in [regex]::Matches($x, '(?s)<a:p>(.*?)</a:p>|<a:p/>')) { $t = ''; foreach ($m in [regex]::Matches($p.Groups[1].Value, '<a:t>([^<]*)</a:t>|<a:br/>')) { if ($m.Groups[1].Success) { $t += $m.Groups[1].Value } else { $t += "`n" } }; if ($t.Trim()) { $o += (Ent $t) + "`n" } }; return $o }
function PptxText([string]$f) {
    $names = ZipNames $f
    $slides = @($names | Where-Object { $_ -match '^ppt/slides/slide(\d+)\.xml$' } | Sort-Object { [int]([regex]::Match($_, '(\d+)\.xml$').Groups[1].Value) })
    $o = ''
    foreach ($s in $slides) {
        $n = [regex]::Match($s, '(\d+)\.xml$').Groups[1].Value
        $o += "== Slide $n ==`n" + (DmlParas (ZipText $f $s))
        $rel = ZipText $f ("ppt/slides/_rels/slide$n.xml.rels")
        if ($rel) { $nm = [regex]::Match($rel, 'Target="\.\./notesSlides/(notesSlide\d+\.xml)"'); if ($nm.Success) { $t = DmlParas (ZipText $f ('ppt/notesSlides/' + $nm.Groups[1].Value)); $t = [regex]::Replace($t, '(?m)^\d+\r?\n', ''); if ($t.Trim()) { $o += "-- notes --`n" + $t } } }
    }
    return $o
}

# ---------------------------------------------------------------- OpenDocument
function OdfText([string]$f) {
    $x = ZipText $f 'content.xml'; if (-not $x) { throw 'no content.xml' }
    $x = [regex]::Replace($x, '<text:tab/>', "`t"); $x = [regex]::Replace($x, '<text:line-break/>', "`n")
    $x = ReplaceEach $x '<text:s(?: text:c="(\d+)")?/>' 'odfspace'
    $x = [regex]::Replace($x, '(?s)</text:p>(?=(?:(?!<table:table-cell[ >]).)*?</table:table-cell>)', ' ')
    $x = [regex]::Replace($x, '</table:table-cell>', "`t"); $x = [regex]::Replace($x, '</table:table-row>', "`n")
    $x = [regex]::Replace($x, '</text:(p|h)>', "`n"); $x = [regex]::Replace($x, '<[^>]+>', '')
    $x = [regex]::Replace($x, " +\t", "`t"); return (Ent ([regex]::Replace($x, "[ \t]+\n", "`n")))
}

# ---------------------------------------------------------------- PDF (text operators; FlateDecode; ToUnicode)
function PdfLit([string]$s) {                          # a PDF literal string's body (no parentheses) -> bytes as Latin-1
    $o = ''; $i = 0
    while ($i -lt $s.Length) {
        $c = $s[$i]
        if ($c -ne '\') { $o += $c; $i++; continue }
        $i++; if ($i -ge $s.Length) { break }; $c = $s[$i]
        switch -CaseSensitive ([string]$c) { 'n' { $o += "`n"; $i++ } 'r' { $o += "`r"; $i++ } 't' { $o += "`t"; $i++ } 'b' { $i++ } 'f' { $i++ } "`r" { $i++; if ($i -lt $s.Length -and $s[$i] -eq "`n") { $i++ } } "`n" { $i++ }
            default { if ($c -match '[0-7]') { $j = $i; $v = 0; while ($j -lt $s.Length -and $j -lt $i + 3 -and $s[$j] -match '[0-7]') { $v = $v * 8 + ([int]$s[$j] - 48); $j++ }; $o += [char]($v -band 255); $i = $j } else { $o += $c; $i++ } } }
    }
    return $o
}
function PdfHex([string]$s) { $s = $s -replace '\s', ''; if ($s.Length % 2) { $s += '0' }; $o = ''; for ($i = 0; $i -lt $s.Length; $i += 2) { $o += [char](HexVal $s.Substring($i, 2)) }; return $o }
function PdfCMap([string]$t) {                          # a ToUnicode CMap -> @{ map (code string -> text); width (bytes per code) }
    $map = [hashtable]::new([StringComparer]::Ordinal); $w = 1   # codes are case-sensitive: 'a' is not 'A'
    $cs = [regex]::Match($t, '<([0-9A-Fa-f]+)>\s*<[0-9A-Fa-f]+>\s*endcodespacerange'); if ($cs.Success) { $w = [int]($cs.Groups[1].Value.Length / 2) }
    $u16 = { param([string]$h) $o = ''; for ($k = 0; $k + 3 -lt $h.Length; $k += 4) { $o += [char](HexVal $h.Substring($k, 4)) }; if ($h.Length -eq 2) { $o = [string][char](HexVal $h) }; $o }
    foreach ($b in [regex]::Matches($t, '(?s)beginbfchar(.*?)endbfchar')) { foreach ($m in [regex]::Matches($b.Groups[1].Value, '<([0-9A-Fa-f]+)>\s*<([0-9A-Fa-f]*)>')) { $map[(PdfHex $m.Groups[1].Value)] = (& $u16 $m.Groups[2].Value) } }
    foreach ($b in [regex]::Matches($t, '(?s)beginbfrange(.*?)endbfrange')) {
        foreach ($m in [regex]::Matches($b.Groups[1].Value, '<([0-9A-Fa-f]+)>\s*<([0-9A-Fa-f]+)>\s*(?:<([0-9A-Fa-f]+)>|\[([^\]]*)\])')) {
            $lo = HexVal $m.Groups[1].Value; $hi = HexVal $m.Groups[2].Value; $hl = $m.Groups[1].Value.Length
            if ($hi - $lo -gt 65535) { continue }
            if ($m.Groups[3].Success) { $dst = $m.Groups[3].Value; $base = HexVal $dst.Substring($dst.Length - 4); $pre = & $u16 ($dst.Substring(0, $dst.Length - 4))
                for ($c = $lo; $c -le $hi; $c++) { $map[(PdfHex ($c.ToString('X').PadLeft($hl, '0')))] = $pre + [char]($base + $c - $lo) } }
            else { $arr = @([regex]::Matches($m.Groups[4].Value, '<([0-9A-Fa-f]+)>') | ForEach-Object { & $u16 $_.Groups[1].Value }); for ($c = $lo; $c -le $hi -and ($c - $lo) -lt $arr.Count; $c++) { $map[(PdfHex ($c.ToString('X').PadLeft($hl, '0')))] = $arr[$c - $lo] } }
        }
    }
    return @{ map = $map; width = $w }
}
function PdfDecode([string]$s, $cm) {                   # string bytes -> text through the font's ToUnicode map (else Latin-1)
    if ($null -eq $cm) { return $s }
    $o = ''; $w = $cm.width; $i = 0
    while ($i -lt $s.Length) { $kl = $w; if ($kl -gt $s.Length - $i) { $kl = $s.Length - $i }; $k = $s.Substring($i, $kl); if ($cm.map.ContainsKey($k)) { $o += $cm.map[$k] } elseif ($w -eq 1) { $o += $k }; $i += $w }
    return $o
}
function PdfText([string]$f) {
    $raw = Latin1 (Zl-ReadBytes $f)
    if (-not $raw.StartsWith('%PDF')) { throw 'not a PDF' }
    $objs = [hashtable]::new([StringComparer]::Ordinal)
    foreach ($m in [regex]::Matches($raw, '(?s)(\d+)\s+(\d+)\s+obj\b(.*?)\bendobj')) { $objs[$m.Groups[1].Value] = $m.Groups[3].Value }
    $stream = {                                          # an object's stream, decoded when it is FlateDecode
        param([string]$body)
        $sm = [regex]::Match($body, '(?s)^(.*?)stream\r?\n'); if (-not $sm.Success) { return $null }
        $dict = $sm.Groups[1].Value; $start = $sm.Length
        $len = -1; $lm = [regex]::Match($dict, '/Length\s+(\d+)(\s+\d+\s+R)?'); if ($lm.Success) { if ($lm.Groups[2].Success) { $ref = [regex]::Match($lm.Groups[0].Value, '/Length\s+(\d+)').Groups[1].Value; $lo = $objs[$ref]; if ($lo) { $len = [int]$lo.Trim() } } else { $len = [int]$lm.Groups[1].Value } }
        if ($len -lt 0 -or $start + $len -gt $body.Length) { $e = $body.IndexOf('endstream', $start); if ($e -lt 0) { return $null }; $len = $e - $start }
        $data = $body.Substring($start, $len)
        if ($dict -match '/Filter\s*/FlateDecode|/Filter\s*\[\s*/FlateDecode\s*\]') { try { return (Latin1 (Zl-Unzlib ([byte[]][char[]]$data))) } catch { return $null } }
        if ($dict -match '/Filter') { return $null }
        return $data
    }
    # object streams (PDF 1.5) hold more objects
    foreach ($k in @($objs.Keys)) {
        if ($objs[$k] -notmatch '/Type\s*/ObjStm') { continue }
        $d = & $stream $objs[$k]; if (-not $d) { continue }
        $fm = [regex]::Match($objs[$k], '/First\s+(\d+)'); if (-not $fm.Success) { continue }; $first = [int]$fm.Groups[1].Value
        $hdr = $d.Substring(0, $first).Trim() -split '\s+'; $offs = @()
        for ($q = 0; $q + 1 -lt $hdr.Count; $q += 2) { $offs += , @($hdr[$q], [int]$hdr[$q + 1]) }
        for ($q = 0; $q -lt $offs.Count; $q++) { $a = $first + $offs[$q][1]; $b = $d.Length; if ($q + 1 -lt $offs.Count) { $b = $first + $offs[$q + 1][1] }; if (-not $objs.ContainsKey($offs[$q][0])) { $objs[$offs[$q][0]] = $d.Substring($a, $b - $a) } }
    }
    $res = { param([string]$v) $m = [regex]::Match($v, '^\s*(\d+)\s+\d+\s+R'); if ($m.Success) { return [string]$objs[$m.Groups[1].Value] }; return $v }
    # pages in order: walk the page tree from the catalog
    $pages = @()
    $cat = $null; foreach ($k in $objs.Keys) { if ($objs[$k] -match '/Type\s*/Catalog') { $cat = $objs[$k]; break } }
    $walk = { param([string]$id, [int]$depth) if ($depth -gt 50) { return }; $o = [string]$objs[$id]; if ($o -match '/Type\s*/Pages\b') { $km = [regex]::Match($o, '(?s)/Kids\s*\[(.*?)\]'); foreach ($r in [regex]::Matches($km.Groups[1].Value, '(\d+)\s+\d+\s+R')) { & $walk $r.Groups[1].Value ($depth + 1) } } elseif ($o -match '/Type\s*/Page\b') { $script:PDFPAGES += $id } }
    $script:PDFPAGES = @()
    if ($cat) { $pm = [regex]::Match($cat, '/Pages\s+(\d+)\s+\d+\s+R'); if ($pm.Success) { & $walk $pm.Groups[1].Value 0 } }
    if (-not $script:PDFPAGES.Count) { foreach ($k in ($objs.Keys | Sort-Object { [int]$_ })) { if ($objs[$k] -match '/Type\s*/Page\b') { $script:PDFPAGES += $k } } }
    $out = ''
    foreach ($pgId in $script:PDFPAGES) {
        $pg = $objs[$pgId]
        $fonts = [hashtable]::new([StringComparer]::Ordinal)
        $rs = & $res ([regex]::Match($pg, '(?s)/Resources\s*(\d+\s+\d+\s+R|<<.*)').Groups[1].Value)
        $fd = [regex]::Match($rs, '(?s)/Font\s*(\d+\s+\d+\s+R|<<(.*?)>>)'); $fdict = $fd.Groups[2].Value; if ($fd.Groups[1].Value -match '^\d') { $fdict = & $res $fd.Groups[1].Value }
        foreach ($fm in [regex]::Matches($fdict, '/([^\s/<>\[\]]+)\s+(\d+)\s+\d+\s+R')) {
            $fo = [string]$objs[$fm.Groups[2].Value]; $tu = [regex]::Match($fo, '/ToUnicode\s+(\d+)\s+\d+\s+R')
            if ($tu.Success) { $cs = & $stream ([string]$objs[$tu.Groups[1].Value]); if ($cs) { $fonts[$fm.Groups[1].Value] = PdfCMap $cs } }
        }
        $cont = [regex]::Match($pg, '(?s)/Contents\s*(\[(.*?)\]|(\d+)\s+\d+\s+R)')
        $ids = @(); if ($cont.Groups[3].Success) { $ids = @($cont.Groups[3].Value) } else { foreach ($r in [regex]::Matches($cont.Groups[2].Value, '(\d+)\s+\d+\s+R')) { $ids += $r.Groups[1].Value } }
        $cs = ''; foreach ($id in $ids) { $d = & $stream ([string]$objs[$id]); if ($d) { $cs += $d + "`n" } }
        $cur = $null; $line = ''; $lines = @(); $lastY = $null
        foreach ($t in [regex]::Matches($cs, '(?s)\((?:\\.|[^\\)])*\)|<[0-9A-Fa-f\s]*>|\[(?:\((?:\\.|[^\\)])*\)|<[0-9A-Fa-f\s]*>|[^\]])*\]|/[^\s/<>\[\]()]+|-?[\d.]+|[A-Za-z\x27\x22*]+')) {
            $v = $t.Value
            if ($v.StartsWith('/')) { $script:PDFLASTNAME = $v.Substring(1); continue }
            if ($v -eq 'Tf') { $cur = $fonts[$script:PDFLASTNAME]; continue }
            if ($v.StartsWith('(')) { $script:PDFSTR = PdfDecode (PdfLit $v.Substring(1, $v.Length - 2)) $cur; continue }
            if ($v.StartsWith('<') -and -not $v.StartsWith('<<')) { $script:PDFSTR = PdfDecode (PdfHex $v.Substring(1, $v.Length - 2)) $cur; continue }
            if ($v.StartsWith('[')) {
                $s = ''
                foreach ($e in [regex]::Matches($v, '\((?:\\.|[^\\)])*\)|<[0-9A-Fa-f\s]*>|-?[\d.]+')) { $x = $e.Value; if ($x.StartsWith('(')) { $s += PdfDecode (PdfLit $x.Substring(1, $x.Length - 2)) $cur } elseif ($x.StartsWith('<')) { $s += PdfDecode (PdfHex $x.Substring(1, $x.Length - 2)) $cur } elseif ([double]$x -lt -200) { $s += ' ' } }
                $script:PDFSTR = $s; continue
            }
            if ($v -match '^-?[\d.]+$') { $script:PDFNUMS = @($script:PDFNUMS) + @($v); if ($script:PDFNUMS.Count -gt 6) { $script:PDFNUMS = $script:PDFNUMS[-6..-1] }; continue }
            switch -CaseSensitive ($v) {
                { $_ -eq 'Tj' -or $_ -eq 'TJ' } { $line += $script:PDFSTR }
                { $_ -eq "'" -or $_ -eq '"' } { $lines += $line; $line = $script:PDFSTR }
                'T*' { $lines += $line; $line = '' }
                { $_ -eq 'Td' -or $_ -eq 'TD' } { $n = @($script:PDFNUMS); if ($n.Count -ge 2 -and [double]$n[-1] -ne 0) { $lines += $line; $line = '' } }   # a move down is a new line; a move across is not a space (the text has its spaces)
                'Tm' { $n = @($script:PDFNUMS); if ($n.Count -ge 6) { $y = [double]$n[-1]; if ($null -ne $lastY -and ($y - $lastY -gt 1 -or $lastY - $y -gt 1)) { $lines += $line; $line = '' }; $lastY = $y } }
                'ET' { }
                'BT' { }
            }
            $script:PDFNUMS = @()
        }
        $lines += $line
        $out += ((@($lines | ForEach-Object { $_.TrimEnd() }) -join "`n") -replace "\n{3,}", "`n`n").Trim() + "`n`f`n"
    }
    return $out
}

function TextOf([string]$f) {                          # -> @{ text; err }
    if (-not (Test-Path -LiteralPath $f -PathType Leaf)) { return @{ err = 'no such file' } }
    $ext = 'txt'; $m = [regex]::Match($f.ToLower(), '\.(\w+)$'); if ($m.Success) { $ext = $m.Groups[1].Value }
    try {
        switch -Regex ($ext) {
            '^(txt|md|csv|text|log|xml|json|sysml|ini|conf|tsv|yml|yaml)$' { $b = Zl-ReadBytes $f; if ($b.Length -ge 2 -and $b[0] -eq 255 -and $b[1] -eq 254) { $c = [char[]]::new(($b.Length - 2) / 2); for ($i = 2; $i + 1 -lt $b.Length; $i += 2) { $c[($i - 2) / 2] = [char]([int]$b[$i] -bor ([int]$b[$i + 1] -shl 8)) }; return @{ text = (-join $c) } }; return @{ text = (Utf8Of $b) } }
            '^html?$' {
                $t = Utf8Of (Zl-ReadBytes $f)
                $t = [regex]::Replace($t, '(?is)<(script|style)\b.*?</\1>', ''); $t = [regex]::Replace($t, '(?i)<br\s*/?>|</(p|div|tr|li|h\d)>', "`n"); $t = [regex]::Replace($t, '<[^>]+>', '')
                $t = $t.Replace('&nbsp;', ' ').Replace('&amp;', '&').Replace('&lt;', '<').Replace('&gt;', '>'); $t = ReplaceEach $t '&#(\d+);' 'decent'; $t = [regex]::Replace($t, "\n{3,}", "`n`n")
                return @{ text = $t }
            }
            '^(docx|docm|dotx|dotm)$' { return @{ text = (DocxText $f) } }
            '^(xlsx|xlsm|xltx)$' { return @{ text = (XlsxText $f) } }
            '^(pptx|pptm|ppsx|potx)$' { return @{ text = (PptxText $f) } }
            '^(odt|ods|odp)$' { return @{ text = (OdfText $f) } }
            '^pdf$' { return @{ text = (PdfText $f) } }
            '^(doc|xls|ppt|rtf)$' { return @{ err = "the old .$ext format is not read here: open it in Office and save it as .$($ext)x" } }
            default { return @{ err = "no reader for .$ext" } }
        }
    } catch { return @{ err = ('could not read it: ' + $_.Exception.Message) } }
}
function Expand($list) { $o = @(); foreach ($p in $list) { if ($p -match '[*?]' -and -not (Test-Path -LiteralPath $p)) { $hits = @(Get-ChildItem -Path $p -File -ErrorAction SilentlyContinue | Sort-Object Name); if ($hits.Count) { foreach ($h in $hits) { $o += $h.FullName.Substring((Get-Location).Path.TrimEnd('\').Length + 1) } } else { $o += $p } } else { $o += $p } }; return , $o }

$a = @($args | ForEach-Object { [string]$_ })
if (-not $a.Count -or $a[0] -cin @('-h', '--help', 'help', '-Help', '/?')) {
    if ($PSCommandPath) { $h = Get-Content -LiteralPath $PSCommandPath -Raw; $i = $h.IndexOf('<#'); $j = $h.IndexOf('#>'); Write-Output ($h.Substring($i + 3, $j - $i - 3).TrimEnd()) }
    else { Write-Output 'docs2txt FILE... | docs2txt -o DIR FILE... | docs2txt grep [-i] PATTERN FILE... | docs2txt tools' }
    if ($PSCommandPath) { exit 0 }; return
}
if ($a[0] -ceq 'tools') {
    foreach ($r in @(@('.docx', 'built in (WordprocessingML)'), @('.xlsx', 'built in (SpreadsheetML)'), @('.pptx', 'built in (PresentationML)'), @('.odt', 'built in (OpenDocument)'), @('.pdf', 'built in (text operators, FlateDecode, ToUnicode)'), @('.html', 'built in'), @('.doc', 'NOT READ: save as .docx'))) { Write-Output ($r[0].PadRight(6) + ' ' + $r[1]) }
    if ($PSCommandPath) { exit 0 }; return
}
if ($a[0] -ceq 'grep') {
    $rest = @($a | Select-Object -Skip 1); $ci = $false
    if ($rest.Count -and $rest[0] -ceq '-i') { $ci = $true; $rest = @($rest | Select-Object -Skip 1) }
    if (-not $rest.Count) { Out-Err 'usage: docs2txt grep [-i] PATTERN FILE...'; if ($PSCommandPath) { exit 2 }; return }
    $pat = $rest[0]; $rx = [regex]$pat; if ($ci) { $rx = [regex]('(?i)' + $pat) }
    foreach ($f in (Expand @($rest | Select-Object -Skip 1))) {
        $r = TextOf $f
        if ($r.err) { Out-Err "${f}: $($r.err)"; $script:RC = 2; continue }
        $n = 0; foreach ($l in ($r.text -split "`r?`n")) { $n++; if ($rx.IsMatch($l)) { Write-Output ($f + ':' + $n + ': ' + $l.TrimStart()) } }
    }
} else {
    $dir = $null; $files = $a
    if ($a[0] -ceq '-o') { if ($a.Count -lt 2) { Out-Err '-o needs a directory'; if ($PSCommandPath) { exit 2 }; return }; $dir = $a[1]; $files = @($a | Select-Object -Skip 2); if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null } }
    $files = Expand $files
    foreach ($f in $files) {
        $r = TextOf $f
        if ($r.err) { Out-Err "${f}: $($r.err)"; $script:RC = 2; continue }
        if ($dir) { $o = [regex]::Replace((Split-Path $f -Leaf), '\.\w+$', ''); $p = Join-Path $dir ($o + '.txt'); Zl-WriteBytes $p (Zl-Utf8Enc $r.text); Write-Output "wrote $p" }
        else { if ($files.Count -gt 1) { Write-Output "==> $f <==" }; $t = $r.text; if ($t.EndsWith("`n")) { $t = $t.Substring(0, $t.Length - 1) }; foreach ($l in ($t -split "`n")) { Write-Output $l.TrimEnd("`r") } }
    }
}
if ($PSCommandPath) { exit $script:RC }
$global:LASTEXITCODE = $script:RC
