<#
sysml.ps1 -- the agile kit's tools/sysml/sysml.pl in Windows PowerShell 5.1 (Constrained Language Mode safe):
SysML v2 / KerML syntax checker generated from the official grammar.

  sysml.ps1 check FILE...       syntax-check files; GNU diagnostics; exit 1 on errors
  sysml.ps1 corpus [DIR...]     check every .sysml/.kerml file under DIRs
  sysml.ps1 tokens FILE         show the token stream (debugging)
  sysml.ps1 grammar             grammar summary: rules, keywords, symbols
  sysml.ps1 crosscheck          needs Java and the SysML v2 Pilot: not run here

The grammar is read from grammar\*.kebnf beside this script (the published KerML and SysML v2 textual-notation
grammars plus the kit's errata), else from the kit's tools\sysml\vendor\sysml-v2-release\bnf.

A syntax checker, not the reference parser: it does not resolve names, imports or types. A model it passes can
still fail the OMG Pilot (the Halberd phase-2 baseline passes here and fails the Pilot with 47 errors).
--out FILE writes stdout to FILE as UTF-8 (Windows PowerShell's '>' writes UTF-16).
#>
$ErrorActionPreference = 'Stop'
$script:SYARGS = @($args)
. (Join-Path $PSScriptRoot 'sysml-lib.ps1')

$script:OB = @{}; $script:ON = 0
function P([string]$s) { $script:OB[$script:ON] = $s; $script:ON++ }
function PErr([string]$s) { if ($s.EndsWith("`n")) { $s = $s.Substring(0, $s.Length - 1) }; foreach ($l in ($s -split "`n")) { Write-Host $l } }
function Utf8([string]$s) {
    $cs = $s.ToCharArray(); $n = $cs.Length
    $out = for ($i = 0; $i -lt $n; $i++) {
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
    , [byte[]]@($out)
}
function Flush([string]$outFile) {
    $text = (@(for ($i = 0; $i -lt $script:ON; $i++) { $script:OB[$i] })) -join ''
    $script:OB = @{}; $script:ON = 0
    if ($outFile) {
        if ($text -cmatch '^[\x00-\x7F]*$') { Set-Content -LiteralPath $outFile -Value $text -Encoding ASCII -NoNewline }
        else { Set-Content -LiteralPath $outFile -Value (Utf8 $text) -Encoding Byte }
        return
    }
    if ($text -eq '') { return }
    if ($text.EndsWith("`n")) { $text = $text.Substring(0, $text.Length - 1) }
    foreach ($l in ($text -split "`n")) { Write-Output $l }
}
function Language([string]$f) { if ($f -match '\.kerml\z') { 'kerml' } else { 'sysml' } }
function PadR([string]$s, [int]$w) { if ($s.Length -lt $w) { $s + (' ' * ($w - $s.Length)) } else { $s } }
function PadL($s, [int]$w) { $s = [string]$s; if ($s.Length -lt $w) { (' ' * ($w - $s.Length)) + $s } else { $s } }
function Fixed1([double]$x) { $x.ToString('F1', [System.Globalization.CultureInfo]::InvariantCulture) }
function Fixed2([double]$x) { $x.ToString('F2', [System.Globalization.CultureInfo]::InvariantCulture) }

function CheckFile([string]$f) {                                  # @{ file; ok; tokens | diag; seconds }
    $t0 = Get-Date
    if (-not (Test-Path -LiteralPath $f -PathType Leaf)) {
        return @{ file = $f; ok = $false; diag = "${f}: error: cannot read ${f}: No such file or directory"; seconds = 0 }
    }
    $src = SL_Read $f
    $r = CheckPath $f (Language $f) $src
    $secs = ((Get-Date) - $t0).TotalSeconds
    if ($r.ok) { return @{ file = $f; ok = $true; tokens = $r.tokens; seconds = $secs } }
    $lc = LineCol $src $r.offset
    @{ file = $f; ok = $false; diag = "${f}:$($lc[0]):$($lc[1]): error: " + (FailMessage $r 8 ''); seconds = $secs }
}
function FilesUnder($dirs) {
    $out = @()
    foreach ($d in $dirs) {
        if (-not (Test-Path -LiteralPath $d)) { continue }
        $base = (Resolve-Path -LiteralPath $d).Path
        foreach ($f in @(Get-ChildItem -LiteralPath $d -Recurse -File)) {
            if ($f.Name -cnotmatch '\.(?:sysml|kerml)\z') { continue }
            $rel = $f.FullName.Substring($base.Length).Replace('\', '/')
            $out += ($d.TrimEnd('/', '\') + $rel)
        }
    }
    SL_SortOrd $out
}
function CmdCheck($files) {
    $results = @(foreach ($f in $files) { CheckFile $f })
    $bad = @($results | Where-Object { -not $_.ok })
    foreach ($b in $bad) { P "$($b.diag)`n" }
    P "sysml: $($results.Count) file(s), $($bad.Count) error(s)`n"
    if ($bad.Count) { 1 } else { 0 }
}
function CmdCorpus($dirs) {
    if (-not @($dirs).Count) { $dirs = @(Join-Path $PSScriptRoot '..\..\tools\sysml\vendor\sysml-v2-release') }
    $files = FilesUnder $dirs
    $t0 = Get-Date
    $results = @(foreach ($f in $files) { CheckFile $f })
    $bad = @($results | Where-Object { -not $_.ok })
    $ok = @($results | Where-Object { $_.ok })
    foreach ($b in $bad) { P "$($b.diag)`n" }
    $tokens = 0; foreach ($r in $ok) { $tokens += $r.tokens }
    $slow = @($results | Sort-Object -Property @{ Expression = { -$_.seconds } } | Select-Object -First 3)
    P ("corpus: $($results.Count) file(s): $($ok.Count) parsed, $($bad.Count) failed; $tokens tokens in " + (Fixed1 ((Get-Date) - $t0).TotalSeconds) + " s`n")
    foreach ($s in $slow) { P ("  slowest: $($s.file) (" + (Fixed2 $s.seconds) + " s)`n") }
    if ($bad.Count) { 1 } else { 0 }
}
function CmdTokens($argv) {
    if (-not @($argv).Count) { return Usage }
    $f = $argv[0]
    $g = GrammarLoadCached (Language $f)
    NewScanner $g
    $s = Scan (SL_Read $f)
    if (-not $s.ok) { P "lexical error at offset $($s.offset): $($s.message)`n"; return 1 }
    foreach ($t in $s.tokens) { P ((PadR $t[0] 8) + " $($t[1])`n") }
    0
}
function CmdGrammar {
    foreach ($lang in @('kerml', 'sysml')) {
        $g = GrammarLoadCached $lang
        $u = GrammarUndefined $g
        $tail = if ($u.Count) { '; undefined: ' + ($u -join ' ') } else { '' }
        P ((PadR $lang 6) + ' ' + (PadL $g.rules.Count 3) + ' rules, ' + (PadL $g.keywords.Count 3) + ' keywords, ' + (PadL $g.symbols.Count 2) + " symbols, start $($g.start)$tail`n")
    }
    0
}
function Usage { PErr 'usage: perl tools/sysml/sysml.pl check FILE... | corpus [DIR...] | tokens FILE | grammar | crosscheck [N] [SEED]'; 2 }

$argv = @(); $outFile = $null
for ($i = 0; $i -lt $script:SYARGS.Count; $i++) {
    if ($script:SYARGS[$i] -ceq '--out' -and $i + 1 -lt $script:SYARGS.Count) { $outFile = $script:SYARGS[$i + 1]; $i++ } else { $argv += , $script:SYARGS[$i] }
}
$cmd = if ($argv.Count) { $argv[0] } else { '' }
$rest = @($argv | Select-Object -Skip 1)
$rc = 2
try {
    switch -CaseSensitive ($cmd) {
        'check' { $rc = CmdCheck $rest }
        'corpus' { $rc = CmdCorpus $rest }
        'tokens' { $rc = CmdTokens $rest }
        'grammar' { $rc = CmdGrammar }
        'crosscheck' { P "crosscheck: needs Java and the Pilot jar (SYSML_JAR / SYSML_LIBRARY)`n"; $rc = 3 }
        default { $rc = Usage }
    }
} catch { PErr ("sysml: " + $_.Exception.Message); $rc = 2 }
Flush $outFile
exit $rc
