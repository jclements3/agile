<#
sysml-check.ps1 : the validate gate in one command. Runs every text-level check on a SysML v2 model and prints one
summary line. PowerShell port of tools/sysml/views/sysml-check.pl (Constrained Language Mode safe, pure ASCII).

  sysml-check.ps1 [--tools DIR] [--only a,b] [--svg DIR] [--today YYYY-MM-DD] [--strict] [MODEL_DIR]

Checks, in order: text (binder sysml-gate), trace (binder sysml-trace), markings (sysml-pkg-svg), zones (sysml-ibd-svg),
threats (sysml-threats). The binder scripts are looked for in --tools DIR, next to this script, in binder/ next to
it, then in ./tools (as .ps1 files). Same output and exit status as the Perl (0 pass, 1 fail, 2 usage error); the
check names in the output keep the Perl script names so the two gates read the same.
#>
. (Join-Path $PSScriptRoot 'views-lib.ps1')
$go = GetOpts $args @('tools=s', 'only=s', 'svg=s', 'today=s', 'strict')
if (-not $go.ok) { PErr 'usage: perl sysml-check.pl [--tools DIR] [--only a,b] [--svg DIR] [--today YYYY-MM-DD] [--strict] [MODEL_DIR]'; VExit 2 }
$OPT = $go.opts; $rest = @($go.rest)
$MODEL = if ($rest.Count) { $rest[0] } else { 'model' }
if ($rest.Count -gt 1 -or -not (Test-Path -LiteralPath $MODEL)) { PErr "sysml-check: ${MODEL}: no such file or directory"; VExit 2 }
$TMPSVG = $null
if ($null -ne $OPT['svg']) { $SVGDIR = $OPT['svg'] }
else { $TMPSVG = Join-Path (Dflt $env:TEMP '.') ('sysml-check-' + (Get-Random -Maximum 999999999)); $null = New-Item -ItemType Directory -Path $TMPSVG -Force; $SVGDIR = $TMPSVG }
if ($null -ne $OPT['svg'] -and -not (IsDir $OPT['svg'])) {
    try { $null = New-Item -ItemType Directory -Path $OPT['svg'] -ErrorAction Stop } catch { PErr "sysml-check: $($OPT['svg']): $($_.Exception.Message)"; VExit 2 }
}
function FindTool([string]$plname) {
    $ps = $plname -replace '\.pl$', '.ps1'
    foreach ($d in @($OPT['tools'], $PSScriptRoot, (Join-Path $PSScriptRoot 'binder'), 'tools')) {
        if ($null -eq $d) { continue }
        $p = Join-Path $d $ps
        if (IsFile $p) { return $p }
    }
    $null
}
$CHECKS = @(
    @('text', 'sysml-gate.pl', @($MODEL)),
    @('trace', 'sysml-trace.pl', @($MODEL)),
    @('markings', 'sysml-pkg-svg.pl', @('-o', "$SVGDIR/packages.svg", $MODEL)),
    @('zones', 'sysml-ibd-svg.pl', @('-o', "$SVGDIR/ibd.svg", $MODEL)),
    @('threats', 'sysml-threats.pl', (@($(if ($OPT['today']) { '--today'; $OPT['today'] })) + @($MODEL))))
$ONLY = NewH; foreach ($x in (SplitKeep (Dflt $OPT['only'] '') ',')) { $ONLY[$x] = 1 }
if ($ONLY.Count) {
    $known = NewH; foreach ($c in $CHECKS) { $known[$c[0]] = 1 }
    foreach ($k in @($ONLY.Keys)) { if (-not $known.ContainsKey($k)) { PErr ("sysml-check: unknown check '$k' (known: " + ((@($CHECKS | ForEach-Object { $_[0] })) -join ' ') + ')'); VExit 2 } }
}
$E = 0; $W = 0; $ACC = 0; $SKIP = 0; $RAN = 0
foreach ($c in $CHECKS) {
    $name = $c[0]; $plname = $c[1]; $cargs = $c[2]
    if ($ONLY.Count -and -not $ONLY.ContainsKey($name)) { continue }
    $path = FindTool $plname
    if ($null -eq $path) { PL "== ${name}: SKIPPED ($plname not found; use --tools DIR)"; $SKIP++; continue }
    $RAN++
    PL "== $name ($plname)"
    VFlush
    $lines = @(& $path @cargs)
    $rc = $LASTEXITCODE
    $ce = 0; $cw = 0; $ca = 0; $last = ''
    foreach ($l in $lines) {
        $l = [string]$l
        if (T $l ': error: ') { $ce++; PL $l }
        elseif (T $l ': warning: ') { if ((T $l 'accepted by risk acceptance') -and -not $OPT['strict']) { $ca++ } else { $cw++ }; PL $l }
        elseif (T $l ': note: ') { PL $l }
        elseif (T $l '\S') { $last = $l }
    }
    if ($rc -eq 2 -or ($rc -and -not $ce -and -not $cw -and -not $ca -and $name -ne 'trace')) { PL "   $plname failed (exit $rc)"; $ce++ }
    if ($null -eq $OPT['svg']) { $last = Sub $last ' -> \S+$' '' }
    if ($last -ne '') { PL "   $last" }
    $E += $ce; $W += $cw; $ACC += $ca
}
if ($null -ne $OPT['svg']) {
    foreach ($v in @(@('sysml-trace-svg.pl', 'trace.svg'), @('sysml-tree-svg.pl', 'tree.svg'))) {
        $p = FindTool $v[0]; if ($null -eq $p) { continue }
        VFlush
        & $p -o "$($OPT['svg'])/$($v[1])" $MODEL
        if ($LASTEXITCODE) { $E++ }
    }
}
if ($OPT['strict']) { $W += $ACC; $E += $SKIP }
$ok = -not $E -and -not $W
PL ('check: {0} check(s) run{1}, {2} error(s), {3} warning(s){4} -> {5}' -f $RAN, $(if ($SKIP) { ", $SKIP skipped" } else { '' }), $E, $W, $(if ($ACC -and -not $OPT['strict']) { ", $ACC accepted risk(s) listed" } else { '' }), $(if ($ok) { 'PASS' } else { 'FAIL' }))
if ($null -ne $TMPSVG) { Remove-Item -LiteralPath $TMPSVG -Recurse -Force -ErrorAction SilentlyContinue }
VExit $(if ($ok) { 0 } else { 1 })
