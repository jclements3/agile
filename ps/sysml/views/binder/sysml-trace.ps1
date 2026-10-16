<#
sysml-trace.ps1 DIR : every leaf requirement usage satisfied (itself or a group above it) and verified (itself or a
group above it). Prints a matrix and GNU-format errors.
PowerShell port of tools/sysml/views/binder/sysml-trace.pl (Constrained Language Mode safe, pure ASCII).
#>
. (Join-Path (Split-Path $PSScriptRoot -Parent) 'views-lib.ps1')
$dir = if (@($args).Count) { [string]$args[0] } else { 'model' }
$files = @(if (IsDir $dir) { FindSysml $dir } else { PErr "Can't stat ${dir}: No such file or directory" })
$REQ = NewH; $SAT = NewH; $VER = NewH
# the Perl walks one character at a time; runs that cannot start a token are skipped whole (same tokens, same places)
$tok = Rx ("\G(?:(\n)|(\{)|(\})|requirement\s+(?!def\b)(?:<'([^']+)'>\s*)?(\w+)\b|satisfy\s+(?:requirement\s+\w+\s*:\s*)?([\w.:]+)\s+by|verify\s+(?:requirement\s+)?([\w.:]+)|[^\n{}rsv]+|.)") 's'
foreach ($f in (SortStr $files)) {
    $t = VRead $f
    $t = GSub $t '//[^\n]*' ''
    $out = ''; $pos = 0
    foreach ($m in (MS $t '/\*.*?\*/' 's')) { $out += $t.Substring($pos, $m.Index - $pos) + ($m.Value -creplace '[^\n]', ''); $pos = $m.Index + $m.Length }
    $t = $out + $t.Substring($pos)
    $stk = @{}; $sn = 0; $depth = 0; $line = 1
    foreach ($m in $tok.Matches($t)) {
        if ($m.Groups[1].Success) { $line++ }
        elseif ($m.Groups[2].Success) { $depth++ }
        elseif ($m.Groups[3].Success) {
            while ($sn -gt 0 -and $stk[$sn - 1][1] -ge $depth) { $sn-- }
            $depth--
        }
        elseif ($m.Groups[5].Success) {
            $nm = $m.Groups[5].Value
            $path = (@(for ($i = 0; $i -lt $sn; $i++) { $stk[$i][0] }) + , $nm) -join '.'
            $REQ[$path] = @{ id = (Dflt (G $m 4) ''); file = $f; line = $line }
            $stk[$sn] = @($nm, ($depth + 1)); $sn++
        }
        elseif ($m.Groups[6].Success) { $SAT[(GSub $m.Groups[6].Value '.*::' '')] = 1 }
        elseif ($m.Groups[7].Success) { $VER[(GSub $m.Groups[7].Value '.*::' '')] = 1 }
    }
}
function Covered([string]$p, $set) {
    $s = $p.Split('.')
    for ($i = $s.Count - 1; $i -ge 0; $i--) {
        $q = ($s[0..$i]) -join '.'
        if ($set.ContainsKey($q) -or ($set.ContainsKey($s[$i]) -and $i -eq 0)) { return $true }
    }
    $false
}
$bad = 0; $n = 0
$keys = SortStr @($REQ.Keys)
foreach ($p in $keys) {
    $isgroup = $false; foreach ($k in $keys) { if ($k.StartsWith("$p.")) { $isgroup = $true; break } }
    if ($isgroup) { continue }
    $n++; $r = $REQ[$p]; $miss = @()
    if ($r.id -cmatch '^N-') { PL ((PadR $r.id 16) + ' ' + (PadR $p 45) + ' need (traced by derivation)'); continue }
    if (-not (Covered $p $SAT)) { $miss += , 'not satisfied' }
    if (-not (Covered $p $VER)) { $miss += , 'not verified' }
    PL ((PadR $r.id 16) + ' ' + (PadR $p 45) + ' ' + $(if ($miss.Count) { $miss -join ', ' } else { 'ok' }))
    if ($miss.Count) { $bad++; PL ("$($r.file):$($r.line): error: requirement $p " + ($miss -join ', ')) }
}
PL "trace: $n leaf requirement(s), $bad with gaps"
VFlush
if ($bad) { exit 1 } else { exit 0 }
