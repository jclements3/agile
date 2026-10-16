<#
sysml-gate.ps1 DIR : text-level checks for a SysML v2 model, GNU-format diagnostics.
PowerShell port of tools/sysml/views/binder/sysml-gate.pl (Constrained Language Mode safe, pure ASCII).
#>
. (Join-Path (Split-Path $PSScriptRoot -Parent) 'views-lib.ps1')
$dir = if (@($args).Count) { [string]$args[0] } else { 'model' }
$files = @(if (IsDir $dir) { FindSysml $dir } else { PErr "Can't stat ${dir}: No such file or directory" })
$script:ERRN = 0; $script:WARNN = 0
$KW = NewH
foreach ($k in @('frame','objective','analysis','variant','variation','filter','render','expose','event','message','then','first','end','in','out','inout','default','meta','all','abstract','subject','actor','stakeholder','assume','require','return','language','rep')) { $KW[$k] = 1 }
function Diag([string]$f, [int]$n, [string]$sev, [string]$msg) { PL "${f}:${n}: ${sev}: $msg"; if ($sev -eq 'error') { $script:ERRN++ } else { $script:WARNN++ } }
foreach ($f in (SortStr $files)) {
    $text = VRead $f
    $lines = [regex]::Split($text, '(?<=\n)')
    $n = 0; $depth = 0; $incomment = $false; $prev = ''
    foreach ($line in $lines) {
        if ($line -eq '') { continue }
        $n++
        $code = Sub $line '//.*$' ''
        $code = GSub $code '"(?:[^"\\]|\\.)*"' '""'
        if ($incomment) {
            $m = M $code '^.*?\*/'
            if (-not $m.Success) { continue }
            $code = $code.Substring($m.Length); $incomment = $false
        }
        $code = GSub $code '/\*.*?\*/' ''
        $m = M $code '/\*.*$'
        if ($m.Success) { $code = $code.Remove($m.Index, $m.Length); $incomment = $true }
        if (T $code '^\s*import\s') { Diag $f $n 'error' 'import without private/public' }
        $m = M $code '\b(?:part|attribute|item|port|action|state|calc)\s+(?:def\s+)?(\w+)\b'
        if ($m.Success -and $KW.ContainsKey($m.Groups[1].Value)) { Diag $f $n 'error' "keyword '$($m.Groups[1].Value)' used as a name" }
        if (T $code ':\s*\w+Value\s*(?:=|default|:=)\s*-?[\d.]+(?:[eE][-+]?\d+)?\s*;') { Diag $f $n 'error' 'quantity without a unit' }
        if ((T $prev '^\s*requirement\b(?!\s+def\b)[^;]*\{\s*$') -and -not (T $code '\bdoc\b|@')) { Diag $f ($n - 1) 'warning' 'requirement without doc' }
        $depth += (MS $code '\{').Count; $depth -= (MS $code '\}').Count
        $prev = $code
    }
    if ($depth) { Diag $f $n 'error' "unbalanced braces ($depth)" }
}
PL ("{0} file(s): {1} error(s), {2} warning(s)" -f @($files).Count, $script:ERRN, $script:WARNN)
VFlush
if ($script:ERRN -or $script:WARNN) { exit 1 } else { exit 0 }
