#requires -Version 5.1
<#
.SYNOPSIS
  ISO128Plate - ISO 128 drawing plates from 3D mesh geometry, in pure Windows PowerShell 5.1.

.DESCRIPTION
  No Add-Type, no Python, no installs. Runs under Constrained Language Mode (AppLocker / WDAC):
  no .NET method calls beyond the core types, no List/StringBuilder/[Math]/[BitConverter]/[IO.File].
  Square roots, sines and cosines are computed here and are bit-identical to [Math]::Sqrt / Sin / Cos,
  so the plates are byte-identical to the FullLanguage original of this module.

  Geometry in : binary/ASCII STL (from build123d, BRL-CAD g-stl, Creo, NX, SolidWorks ...)
                or built-in primitives (box, cylinder/tube, revolve, extrude-with-holes).
  Drawing out : SVG at true size (mm), printable 1:1 from any browser.

  Standards applied
    ISO 128-20/-24  line types and widths (line groups 0.35 / 0.5 / 0.7 / 1.0)
                    01.2 continuous wide   visible outlines
                    01.1 continuous narrow dimension/extension lines
                    02.1 dashed narrow     hidden outlines (12d dash, 3d gap)
                    04.1 long-dash dotted  centre lines   (24d, 3d, 0.5d, 3d)
    ISO 128-30 / ISO 5456-2  orthographic views, first- or third-angle, projection symbol
    ISO 5457        sheet sizes A0-A4, frame (20 mm filing margin, 10 mm others),
                    centring marks, grid reference system (letters w/o I and O)
    ISO 7200        title block, 180 mm wide
    ISO 5455        preferred scales, auto-selected to fit
    ISO 129-1       overall dimensions (optional), closed filled arrowheads
    ISO 3098        lettering heights 1.8 / 2.5 / 3.5 / 5 mm

  Hidden-line removal is exact against the triangle mesh (edge sampling + bisection to
  the occlusion boundary), using a 2D bucket grid so it stays usable in plain PowerShell.

  Primitives may touch but must not overlap in volume (no boolean engine): overlapping
  volumes draw their internal faces. For real parts, model in build123d/BRL-CAD/Creo
  and export STL.

  Lists are hashtables keyed 0..Count-1 ($l[$l.Count] = x appends): Constrained Language Mode
  cannot create List[T], ArrayList or StringBuilder.
#>

Set-StrictMode -Version 2.0
$script:IC = [System.Globalization.CultureInfo]::InvariantCulture

function N([double]$x) { return $x.ToString('0.###', $script:IC) }
function Esc([string]$s) {      # as [System.Security.SecurityElement]::Escape
    if ($null -eq $s) { return '' }
    return $s.Replace('&', '&amp;').Replace('<', '&lt;').Replace('>', '&gt;').Replace('"', '&quot;').Replace("'", '&apos;')
}

# =====================================================================================
# Arithmetic without [Math] (Constrained Language Mode refuses its methods)
# =====================================================================================

$script:U52 = 1.0 / 4503599627370496.0                # ulp of [1,2)
$script:SPLIT = 134217729.0                           # 2^27 + 1 (Veltkamp split)

function Sqrt([double]$x) {
    # correctly rounded square root, as IEEE 754 and [Math]::Sqrt give it
    if (-not ($x -gt 0)) { if ($x -eq 0) { return $x }; return [double]::NaN }
    if ($x -eq [double]::PositiveInfinity) { return $x }
    $m = $x; $k = 1.0
    while ($m -ge 1.8446744073709552E+19) { $m *= 5.4210108624275222E-20; $k *= 4294967296.0 }
    while ($m -lt 5.4210108624275222E-20) { $m *= 1.8446744073709552E+19; $k *= 2.3283064365386963E-10 }
    while ($m -ge 4.0) { $m *= 0.25; $k *= 2.0 }
    while ($m -lt 1.0) { $m *= 4.0; $k *= 0.5 }
    $y = 0.6 + 0.35 * $m
    for ($i = 0; $i -lt 5; $i++) { $y = 0.5 * ($y + $m / $y) }
    # the neighbour with the smallest exact residual m - c*c (Dekker's exact product) is the rounded root
    $best = $y; $br = 1e300
    foreach ($c in @(($y - $script:U52), $y, ($y + $script:U52))) {
        $p = $c * $c; $t = $script:SPLIT * $c; $hi = $t - ($t - $c); $lo = $c - $hi
        $e = (($hi * $hi - $p) + 2.0 * $hi * $lo) + $lo * $lo
        $r = ($m - $p) - $e; if ($r -lt 0) { $r = -$r }
        if ($r -lt $br) { $br = $r; $best = $c }
    }
    return $best * $k
}

# double-double helpers for SinCos: a value is @(hi, lo)
function DdTwoProd([double]$a, [double]$b) {
    $p = $a * $b
    $t = $script:SPLIT * $a; $ah = $t - ($t - $a); $al = $a - $ah
    $t = $script:SPLIT * $b; $bh = $t - ($t - $b); $bl = $b - $bh
    return @($p, ((($ah * $bh - $p) + $ah * $bl + $al * $bh) + $al * $bl))
}
function DdMul($a, $b) {
    $q = DdTwoProd $a[0] $b[0]; $e = $q[1] + ($a[0] * $b[1] + $a[1] * $b[0])
    $s = $q[0] + $e; return @($s, ($e - ($s - $q[0])))
}
function DdAdd($a, $b) {
    $s = $a[0] + $b[0]; $bb = $s - $a[0]; $e = ($a[0] - ($s - $bb)) + ($b[0] - $bb)
    $e += $a[1] + $b[1]
    $h = $s + $e; return @($h, ($e - ($h - $s)))
}
function DdDivInt($a, [double]$n) {
    $q1 = $a[0] / $n; $p = DdTwoProd $q1 $n
    $r = (($a[0] - $p[0]) - $p[1] + $a[1]) / $n
    $h = $q1 + $r; return @($h, ($r - ($h - $q1)))
}
# pi/2 to 66 bits: the C runtime behind [Math]::Sin/Cos reduces with the x87 pi, so cos(pi/2) is 6.1230317691118863E-17
$script:PIO2 = @(1.5707963267948966, 6.123031769111886e-17)
$script:SINCOS = @{}
function SinCos([double]$x) {
    # @(sin x, cos x) as [Math]::Sin / [Math]::Cos give them: double-double Taylor series after reduction by the
    # x87 pi/2, rounded as x87 rounds. Identical on 135,791 of 135,798 test angles; the other 7 are 1 ulp apart,
    # where fsin's own error exceeds a correctly rounded extended result.
    if ($script:SINCOS.ContainsKey($x)) { return $script:SINCOS[$x] }
    $q = [long]($x / $script:PIO2[0])
    $kp = DdTwoProd ([double]$q) $script:PIO2[0]
    $r = DdAdd @($x, 0.0) @((-$kp[0]), (-$kp[1]))
    $r = DdAdd $r @((-([double]$q * $script:PIO2[1])), 0.0)
    $r2 = DdMul $r $r
    $st = $r; $s = $r; $ct = @(1.0, 0.0); $c = @(1.0, 0.0)
    for ($n = 1; $n -le 15; $n++) {
        $ct = DdDivInt (DdMul $ct $r2) ((2 * $n - 1) * (2 * $n)); $ct = @((-$ct[0]), (-$ct[1])); $c = DdAdd $c $ct
        $st = DdDivInt (DdMul $st $r2) ((2 * $n) * (2 * $n + 1)); $st = @((-$st[0]), (-$st[1])); $s = DdAdd $s $st
    }
    $sv = X87Round $s; $cv = X87Round $c
    switch ((($q % 4) + 4) % 4) { 0 { $o = @($sv, $cv) } 1 { $o = @($cv, (-$sv)) } 2 { $o = @((-$sv), (-$cv)) } default { $o = @((-$cv), $sv) } }
    $script:SINCOS[$x] = $o
    return $o
}
function X87Round($d) {
    # A double-double rounded as the x87 fsin/fcos behind [Math]::Sin/Cos rounds: to the 64-bit extended significand,
    # then to double. The two roundings differ from one only when the first lands on a double's half-way point.
    $hi = $d[0] + $d[1]; $lo = $d[1] - ($hi - $d[0])
    if ($hi -eq 0 -or $lo -eq 0) { return $hi }
    $a = $hi; if ($a -lt 0) { $a = -$a }
    $p = 1.0; while ($a -ge 2.0 * $p) { $p *= 2.0 }; while ($a -lt $p) { $p *= 0.5 }   # p = 2^e <= a < 2^(e+1)
    $u = $p * $script:U52                                    # ulp of hi
    $mant = $a / $u                                          # hi's 53-bit integer significand
    if ($a -eq $p -and (($lo -lt 0) -eq ($hi -gt 0))) { $u *= 0.5 }   # just below a power of two the spacing halves
    $n = [long]($lo / ($u / 2048.0))                         # lo in 64-bit ulps, rounded half to even
    if (($n -eq 1024 -or $n -eq -1024) -and $a -ne $p -and ($mant % 2) -eq 1) {   # a half-way point: ties to even
        if ($n -gt 0) { return $hi + $u }
        return $hi - $u
    }
    return $hi
}

function RoundEven([double]$x) {      # [Math]::Round (half to even); a [long] cast rounds the same way
    if ($x -lt 4503599627370496.0 -and $x -gt -4503599627370496.0) { return [double][long]$x }
    return $x
}
function Floor([double]$x) {
    if ($x -lt 4503599627370496.0 -and $x -gt -4503599627370496.0) { $i = [long]$x; if ($i -gt $x) { $i-- }; return [double]$i }
    return $x
}
function Ceiling([double]$x) {
    if ($x -lt 4503599627370496.0 -and $x -gt -4503599627370496.0) { $i = [long]$x; if ($i -lt $x) { $i++ }; return [double]$i }
    return $x
}
function Sign([double]$x) { if ($x -gt 0) { return 1 }; if ($x -lt 0) { return -1 }; return 0 }
function DMax([double]$a, [double]$b) { if ($a -gt $b) { return $a }; return $b }   # [Math]::Max on doubles
function DMin([double]$a, [double]$b) { if ($a -lt $b) { return $a }; return $b }   # [Math]::Min on doubles

function ToArray($l) {             # a hashtable list (keys 0..Count-1) as object[]
    $a = New-Object 'object[]' $l.Count
    for ($i = 0; $i -lt $l.Count; $i++) { $a[$i] = $l[$i] }
    return , $a
}
function ToIntArray($l) {
    $a = New-Object int[] $l.Count
    for ($i = 0; $i -lt $l.Count; $i++) { $a[$i] = $l[$i] }
    return , $a
}

# ---- files: bytes in and out (Constrained Language Mode refuses [IO.File] and [Text.Encoding])
function FullPath([string]$Path) {     # as $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath
    $parent = Split-Path -Path $Path -Parent
    if (-not $parent) { $parent = '.' }
    $dir = (Resolve-Path -LiteralPath $parent -ErrorAction Stop).ProviderPath
    return (Join-Path $dir (Split-Path -Path $Path -Leaf))
}
function Utf8Bytes([string]$t) {
    if ($null -eq $t -or $t.Length -eq 0) { return , ([byte[]]@()) }
    if ($t -cmatch '^[\x00-\x7F]*$') { return , ([byte[]][char[]]$t) }
    $n = $t.Length; $i = 0
    $out = @(while ($i -lt $n) {
            $c = [int]$t[$i]; $i++
            if ($c -ge 0xD800 -and $c -le 0xDBFF -and $i -lt $n -and [int]$t[$i] -ge 0xDC00 -and [int]$t[$i] -le 0xDFFF) { $c = 0x10000 + (($c - 0xD800) * 0x400) + ([int]$t[$i] - 0xDC00); $i++ }
            if ($c -lt 0x80) { $c }
            elseif ($c -lt 0x800) { 0xC0 -bor ($c -shr 6); 0x80 -bor ($c -band 0x3F) }
            elseif ($c -lt 0x10000) { 0xE0 -bor ($c -shr 12); 0x80 -bor (($c -shr 6) -band 0x3F); 0x80 -bor ($c -band 0x3F) }
            else { 0xF0 -bor ($c -shr 18); 0x80 -bor (($c -shr 12) -band 0x3F); 0x80 -bor (($c -shr 6) -band 0x3F); 0x80 -bor ($c -band 0x3F) }
        })
    return , ([byte[]]$out)
}
function WriteUtf8([string]$full, [string]$text) {     # UTF-8, no byte-order mark
    $b = Utf8Bytes $text
    if ($b.Length -eq 0) { $null = New-Item -ItemType File -Path $full -Force; return }
    Set-Content -LiteralPath $full -Value $b -Encoding Byte -ErrorAction Stop
}
function Sb { return @{} }                                         # string builder: a hashtable list of pieces
function SbLine($sb, [string]$s) { $sb[$sb.Count] = $s + "`r`n" }  # as StringBuilder.AppendLine on Windows
function SbText($sb) { $parts = New-Object string[] $sb.Count; for ($i = 0; $i -lt $sb.Count; $i++) { $parts[$i] = $sb[$i] }; return (-join $parts) }

# =====================================================================================
# Mesh construction
# =====================================================================================

function New-IsoMesh {
    [CmdletBinding()] param()
    return @{ V = @{}; T = @{}; Axes = @{} }       # V: vertex double[3]; T: int[3]; Axes: centre-line hashtables
}

function AddV($m, [double]$x, [double]$y, [double]$z) {
    $V = $m.V; $n = $V.Count; $V[$n] = [double[]]@($x, $y, $z); return $n
}
function AddT($m, [int]$a, [int]$b, [int]$c) { $T = $m.T; $T[$T.Count] = [int[]]@($a, $b, $c) }

function Get-AxisFrame([string]$Axis) {
    # returns u, v, w with u x v = w
    switch ($Axis.ToUpper()) {
        'X' { return @(@(0.0, 1.0, 0.0), @(0.0, 0.0, 1.0), @(1.0, 0.0, 0.0)) }
        'Y' { return @(@(0.0, 0.0, 1.0), @(1.0, 0.0, 0.0), @(0.0, 1.0, 0.0)) }
        default { return @(@(1.0, 0.0, 0.0), @(0.0, 1.0, 0.0), @(0.0, 0.0, 1.0)) }
    }
}

function LocalPt($o, $fr, [double]$a, [double]$b, [double]$c) {
    # o + a*u + b*v + c*w
    $u = $fr[0]; $v = $fr[1]; $w = $fr[2]
    return [double[]]@(
        ($o[0] + $a * $u[0] + $b * $v[0] + $c * $w[0]),
        ($o[1] + $a * $u[1] + $b * $v[1] + $c * $w[1]),
        ($o[2] + $a * $u[2] + $b * $v[2] + $c * $w[2]))
}

function New-IsoBox {
    <# .SYNOPSIS Axis-aligned box. -Min is the minimum corner. #>
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][double[]]$Size, [double[]]$Min = @(0, 0, 0), [hashtable]$Mesh)
    if (-not $Mesh) { $Mesh = New-IsoMesh }
    $x0 = $Min[0]; $y0 = $Min[1]; $z0 = $Min[2]
    $x1 = $x0 + $Size[0]; $y1 = $y0 + $Size[1]; $z1 = $z0 + $Size[2]
    $o = $Mesh.V.Count
    $pts = @(@($x0, $y0, $z0), @($x1, $y0, $z0), @($x1, $y1, $z0), @($x0, $y1, $z0),
             @($x0, $y0, $z1), @($x1, $y0, $z1), @($x1, $y1, $z1), @($x0, $y1, $z1))
    foreach ($p in $pts) { $null = AddV $Mesh $p[0] $p[1] $p[2] }
    $f = @(0, 3, 2, 0, 2, 1, 4, 5, 6, 4, 6, 7, 0, 1, 5, 0, 5, 4, 2, 3, 7, 2, 7, 6, 3, 0, 4, 3, 4, 7, 1, 2, 6, 1, 6, 5)
    for ($i = 0; $i -lt $f.Count; $i += 3) { AddT $Mesh ($o + $f[$i]) ($o + $f[$i + 1]) ($o + $f[$i + 2]) }
    return $Mesh
}

function New-IsoRevolve {
    <#
    .SYNOPSIS Solid of revolution. -Profile is a closed polygon in the (r, z) half-plane, flat list r0,z0,r1,z1,...
              r >= 0. z runs along -Axis from -Base. Either winding is accepted.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][double[]]$Profile, [double[]]$Base = @(0, 0, 0),
          [ValidateSet('X', 'Y', 'Z')][string]$Axis = 'Z', [int]$Segments = 72, [hashtable]$Mesh)
    if (-not $Mesh) { $Mesh = New-IsoMesh }
    $fr = Get-AxisFrame $Axis
    $np = [int]($Profile.Count / 2)
    $r = New-Object double[] $np; $z = New-Object double[] $np
    for ($k = 0; $k -lt $np; $k++) { $r[$k] = DMax 0.0 $Profile[2 * $k]; $z[$k] = $Profile[2 * $k + 1] }
    # signed area in (r,z); make CCW
    $area = 0.0
    for ($k = 0; $k -lt $np; $k++) { $j = ($k + 1) % $np; $area += $r[$k] * $z[$j] - $r[$j] * $z[$k] }
    if ($area -lt 0) { [Array]::Reverse($r); [Array]::Reverse($z) }
    $n = $Segments
    $rings = New-Object 'object[]' $np
    $zmin = [double]::MaxValue; $zmax = [double]::MinValue; $rmax = 0.0
    for ($k = 0; $k -lt $np; $k++) {
        if ($z[$k] -lt $zmin) { $zmin = $z[$k] }; if ($z[$k] -gt $zmax) { $zmax = $z[$k] }; if ($r[$k] -gt $rmax) { $rmax = $r[$k] }
        $ring = New-Object int[] $n
        if ($r[$k] -le 1e-12) {
            $p = LocalPt $Base $fr 0 0 $z[$k]; $c = AddV $Mesh $p[0] $p[1] $p[2]
            for ($i = 0; $i -lt $n; $i++) { $ring[$i] = $c }
        } else {
            for ($i = 0; $i -lt $n; $i++) {
                $t = 2.0 * [Math]::PI * $i / $n
                $sc = SinCos $t
                $p = LocalPt $Base $fr ($r[$k] * $sc[1]) ($r[$k] * $sc[0]) $z[$k]
                $ring[$i] = AddV $Mesh $p[0] $p[1] $p[2]
            }
        }
        $rings[$k] = $ring
    }
    for ($k = 0; $k -lt $np; $k++) {
        $kb = ($k + 1) % $np
        if ($r[$k] -le 1e-12 -and $r[$kb] -le 1e-12) { continue }
        $A = $rings[$k]; $B = $rings[$kb]
        for ($i = 0; $i -lt $n; $i++) {
            $j = ($i + 1) % $n
            if ($r[$kb] -gt 1e-12) { AddT $Mesh $A[$i] $B[$j] $B[$i] }
            if ($r[$k] -gt 1e-12) { AddT $Mesh $A[$i] $A[$j] $B[$j] }
        }
    }
    $Mesh.Axes[$Mesh.Axes.Count] = @{ Base = $Base; Axis = $Axis; R = $rmax; Z0 = $zmin; Z1 = $zmax }
    return $Mesh
}

function New-IsoCylinder {
    <# .SYNOPSIS Cylinder, or tube when -InnerRadius > 0. -Base is the centre of the bottom face. #>
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][double]$Radius, [Parameter(Mandatory = $true)][double]$Height,
          [double[]]$Base = @(0, 0, 0), [ValidateSet('X', 'Y', 'Z')][string]$Axis = 'Z',
          [double]$InnerRadius = 0, [int]$Segments = 72, [hashtable]$Mesh)
    if ($InnerRadius -gt 0) { $prof = @($InnerRadius, 0, $Radius, 0, $Radius, $Height, $InnerRadius, $Height) }
    else { $prof = @(0, 0, $Radius, 0, $Radius, $Height, 0, $Height) }
    return (New-IsoRevolve -Profile $prof -Base $Base -Axis $Axis -Segments $Segments -Mesh $Mesh)
}

# ---- 2D polygon helpers for extrusion ------------------------------------------------
# $P is a hashtable list of 2D points (double[2]); loops are int[] of indices into it.

function PolyArea($P, $idx) {
    $a = 0.0; $c = $idx.Count
    for ($i = 0; $i -lt $c; $i++) { $pa = $P[$idx[$i]]; $pb = $P[$idx[($i + 1) % $c]]; $a += $pa[0] * $pb[1] - $pb[0] * $pa[1] }
    return $a / 2.0
}

function Near($p, $q) {           # |dx| < 1e-9 and |dy| < 1e-9
    $dx = $p[0] - $q[0]; $dy = $p[1] - $q[1]
    return ($dx -lt 1e-9 -and $dx -gt -1e-9 -and $dy -lt 1e-9 -and $dy -gt -1e-9)
}

function SegCross($a, $b, $c, $d) {
    # proper intersection of segments ab and cd (shared endpoints by position do not count)
    $eps = 1e-12
    foreach ($p in @($a, $b)) { foreach ($q in @($c, $d)) { if (Near $p $q) { return $false } } }
    $d1 = ($b[0] - $a[0]) * ($c[1] - $a[1]) - ($b[1] - $a[1]) * ($c[0] - $a[0])
    $d2 = ($b[0] - $a[0]) * ($d[1] - $a[1]) - ($b[1] - $a[1]) * ($d[0] - $a[0])
    $d3 = ($d[0] - $c[0]) * ($a[1] - $c[1]) - ($d[1] - $c[1]) * ($a[0] - $c[0])
    $d4 = ($d[0] - $c[0]) * ($b[1] - $c[1]) - ($d[1] - $c[1]) * ($b[0] - $c[0])
    return ((($d1 -gt $eps -and $d2 -lt - $eps) -or ($d1 -lt - $eps -and $d2 -gt $eps)) -and
            (($d3 -gt $eps -and $d4 -lt - $eps) -or ($d3 -lt - $eps -and $d4 -gt $eps)))
}

function Merge-Holes($P, $outer, $holes) {
    # Bridge each hole into the outer loop so a single simple polygon can be ear-clipped.
    $M = [int[]]$outer
    $order = @($holes | Sort-Object -Descending -Property { $hh = $_; $mx = -1e300; foreach ($i in $hh) { if ($P[$i][0] -gt $mx) { $mx = $P[$i][0] } }; $mx })
    $pend = @{}; foreach ($hh in $order) { $pend[$pend.Count] = $hh }
    $ph = 0
    while ($ph -lt $pend.Count) {
        $H = $pend[$ph]; $ph++
        $hi = 0; for ($i = 1; $i -lt $H.Count; $i++) { if ($P[$H[$i]][0] -gt $P[$H[$hi]][0]) { $hi = $i } }
        $hv = $P[$H[$hi]]
        $best = -1; $bestD = [double]::MaxValue
        for ($mi = 0; $mi -lt $M.Count; $mi++) {
            $mv = $P[$M[$mi]]
            $dd = ($mv[0] - $hv[0]) * ($mv[0] - $hv[0]) + ($mv[1] - $hv[1]) * ($mv[1] - $hv[1])
            if ($dd -ge $bestD) { continue }
            $ok = $true
            for ($k = 0; $k -lt $M.Count -and $ok; $k++) { if (SegCross $hv $mv $P[$M[$k]] $P[$M[($k + 1) % $M.Count]]) { $ok = $false } }
            $loops = New-Object 'object[]' (1 + $pend.Count - $ph); $loops[0] = $H
            for ($q = $ph; $q -lt $pend.Count; $q++) { $loops[1 + $q - $ph] = $pend[$q] }
            foreach ($L in $loops) { for ($k = 0; $k -lt $L.Count -and $ok; $k++) { if (SegCross $hv $mv $P[$L[$k]] $P[$L[($k + 1) % $L.Count]]) { $ok = $false } } }
            if ($ok) { $best = $mi; $bestD = $dd }
        }
        if ($best -lt 0) { throw 'Merge-Holes: no visible bridge (holes overlapping or outside outline?)' }
        $N = @{}
        for ($i = 0; $i -le $best; $i++) { $N[$N.Count] = $M[$i] }
        for ($i = 0; $i -lt $H.Count; $i++) { $N[$N.Count] = $H[($hi + $i) % $H.Count] }
        $P[$P.Count] = [double[]]@($hv[0], $hv[1]); $N[$N.Count] = $P.Count - 1                       # duplicate hole vertex
        $mvp = $P[$M[$best]]; $P[$P.Count] = [double[]]@($mvp[0], $mvp[1]); $N[$N.Count] = $P.Count - 1 # duplicate outer vertex
        for ($i = $best + 1; $i -lt $M.Count; $i++) { $N[$N.Count] = $M[$i] }
        $M = ToIntArray $N
    }
    return , $M
}

function RemoveAt([int[]]$a, [int]$i) {
    $r = New-Object int[] ($a.Length - 1)
    for ($k = 0; $k -lt $i; $k++) { $r[$k] = $a[$k] }
    for ($k = $i + 1; $k -lt $a.Length; $k++) { $r[$k - 1] = $a[$k] }
    return , $r
}

function Get-EarClip($P, $poly) {
    # poly: CCW index list. Returns a flat list (hashtable list) of index triples.
    $idx = [int[]]$poly
    $tris = @{}
    $guard = 0
    while ($idx.Count -gt 3 -and $guard -lt 100000) {
        $guard++
        $c = $idx.Count; $found = $false
        for ($i = 0; $i -lt $c; $i++) {
            $ia = $idx[($i - 1 + $c) % $c]; $ib = $idx[$i]; $ic = $idx[($i + 1) % $c]
            $a = $P[$ia]; $b = $P[$ib]; $cc = $P[$ic]
            $cr = ($b[0] - $a[0]) * ($cc[1] - $a[1]) - ($b[1] - $a[1]) * ($cc[0] - $a[0])
            if ($cr -le 1e-12) { continue }
            $ear = $true
            for ($k = 0; $k -lt $c; $k++) {
                $ik = $idx[$k]; if ($ik -eq $ia -or $ik -eq $ib -or $ik -eq $ic) { continue }
                $pt = $P[$ik]
                if ((Near $pt $a) -or (Near $pt $b) -or (Near $pt $cc)) { continue }
                $w1 = ($b[0] - $a[0]) * ($pt[1] - $a[1]) - ($b[1] - $a[1]) * ($pt[0] - $a[0])
                $w2 = ($cc[0] - $b[0]) * ($pt[1] - $b[1]) - ($cc[1] - $b[1]) * ($pt[0] - $b[0])
                $w3 = ($a[0] - $cc[0]) * ($pt[1] - $cc[1]) - ($a[1] - $cc[1]) * ($pt[0] - $cc[0])
                if ($w1 -ge -1e-12 -and $w2 -ge -1e-12 -and $w3 -ge -1e-12) { $ear = $false; break }
            }
            if ($ear) { $tris[$tris.Count] = $ia; $tris[$tris.Count] = $ib; $tris[$tris.Count] = $ic; $idx = RemoveAt $idx $i; $found = $true; break }
        }
        if (-not $found) {
            # degenerate (collinear) remainder: drop a zero-area vertex
            $removed = $false
            for ($i = 0; $i -lt $c; $i++) {
                $a = $P[$idx[($i - 1 + $c) % $c]]; $b = $P[$idx[$i]]; $cc = $P[$idx[($i + 1) % $c]]
                $cr = ($b[0] - $a[0]) * ($cc[1] - $a[1]) - ($b[1] - $a[1]) * ($cc[0] - $a[0])
                if ($cr -le 1e-12 -and $cr -ge -1e-12) { $idx = RemoveAt $idx $i; $removed = $true; break }
            }
            if (-not $removed) { throw 'Get-EarClip: polygon is not simple' }
        }
    }
    if ($idx.Count -eq 3) { $tris[$tris.Count] = $idx[0]; $tris[$tris.Count] = $idx[1]; $tris[$tris.Count] = $idx[2] }
    return , $tris
}

function New-IsoExtrude {
    <#
    .SYNOPSIS Prism from a 2D outline with optional holes, extruded along -Axis by -Height.
    .PARAMETER Outline   flat list x0,y0,x1,y1,... (either winding), in the plane's local u,v
    .PARAMETER Holes     array of @{ X=..; Y=..; D=.. } round through-holes (get centre lines)
    .PARAMETER HolePolygons array of flat point lists for non-round cut-outs
    .PARAMETER Origin    3D point of local (0,0,0)
    .PARAMETER Axis      Z: plane XY;  X: plane YZ;  Y: plane ZX
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][double[]]$Outline, [Parameter(Mandatory = $true)][double]$Height,
          [object[]]$Holes = @(), [object[]]$HolePolygons = @(), [double[]]$Origin = @(0, 0, 0),
          [ValidateSet('X', 'Y', 'Z')][string]$Axis = 'Z', [int]$Segments = 72, [hashtable]$Mesh)
    if (-not $Mesh) { $Mesh = New-IsoMesh }
    $fr = Get-AxisFrame $Axis
    $P = @{}
    $outer = New-Object int[] ([int]($Outline.Count / 2))
    for ($i = 0; $i -lt $Outline.Count; $i += 2) { $P[$P.Count] = [double[]]@($Outline[$i], $Outline[$i + 1]); $outer[$i / 2] = $P.Count - 1 }
    if ((PolyArea $P $outer) -lt 0) { [Array]::Reverse($outer) }
    $loops = @{}
    foreach ($h in $Holes) {
        $hx = [double]$h.X; $hy = [double]$h.Y; $hr = [double]$h.D / 2.0
        $L = New-Object int[] $Segments
        for ($i = 0; $i -lt $Segments; $i++) {
            $t = 2.0 * [Math]::PI * $i / $Segments
            $sc = SinCos $t
            $P[$P.Count] = [double[]]@(($hx + $hr * $sc[1]), ($hy + $hr * $sc[0])); $L[$i] = $P.Count - 1
        }
        [Array]::Reverse($L); $loops[$loops.Count] = $L
        $Mesh.Axes[$Mesh.Axes.Count] = @{ Base = (LocalPt $Origin $fr $hx $hy 0); Axis = $Axis; R = $hr; Z0 = 0.0; Z1 = $Height }
    }
    foreach ($hp in $HolePolygons) {
        $L = New-Object int[] ([int]($hp.Count / 2))
        for ($i = 0; $i -lt $hp.Count; $i += 2) { $P[$P.Count] = [double[]]@([double]$hp[$i], [double]$hp[$i + 1]); $L[$i / 2] = $P.Count - 1 }
        if ((PolyArea $P $L) -gt 0) { [Array]::Reverse($L) }
        $loops[$loops.Count] = $L
    }
    # side walls (outer CCW, holes CW -> outward normals everywhere)
    $ring0 = @{}; $ring1 = @{}
    $allLoops = New-Object 'object[]' (1 + $loops.Count); $allLoops[0] = $outer
    for ($q = 0; $q -lt $loops.Count; $q++) { $allLoops[1 + $q] = $loops[$q] }
    foreach ($L in $allLoops) {
        foreach ($i in $L) {
            $q3 = LocalPt $Origin $fr $P[$i][0] $P[$i][1] 0;       $ring0[$i] = AddV $Mesh $q3[0] $q3[1] $q3[2]
            $q3 = LocalPt $Origin $fr $P[$i][0] $P[$i][1] $Height; $ring1[$i] = AddV $Mesh $q3[0] $q3[1] $q3[2]
        }
        for ($k = 0; $k -lt $L.Count; $k++) {
            $a = $L[$k]; $b = $L[($k + 1) % $L.Count]
            AddT $Mesh $ring0[$a] $ring0[$b] $ring1[$b]
            AddT $Mesh $ring0[$a] $ring1[$b] $ring1[$a]
        }
    }
    # caps
    $nBefore = $P.Count
    $merged = Merge-Holes $P $outer (ToArray $loops)
    for ($i = $nBefore; $i -lt $P.Count; $i++) {
        # bridge duplicates: map to the original vertex at the same position
        for ($j = 0; $j -lt $nBefore; $j++) {
            if (Near $P[$i] $P[$j]) { $ring0[$i] = $ring0[$j]; $ring1[$i] = $ring1[$j]; break }
        }
    }
    $tri = Get-EarClip $P $merged
    for ($i = 0; $i -lt $tri.Count; $i += 3) {
        AddT $Mesh $ring1[$tri[$i]] $ring1[$tri[$i + 1]] $ring1[$tri[$i + 2]]
        AddT $Mesh $ring0[$tri[$i]] $ring0[$tri[$i + 2]] $ring0[$tri[$i + 1]]
    }
    return $Mesh
}

function Join-IsoMesh {
    <# .SYNOPSIS Concatenate meshes (primitives may touch, must not overlap in volume). #>
    [CmdletBinding()] param([Parameter(Mandatory = $true)][hashtable[]]$Meshes)
    $m = New-IsoMesh
    foreach ($s in $Meshes) {
        $o = $m.V.Count
        for ($i = 0; $i -lt $s.V.Count; $i++) { $m.V[$m.V.Count] = $s.V[$i] }
        for ($i = 0; $i -lt $s.T.Count; $i++) { $t = $s.T[$i]; $m.T[$m.T.Count] = [int[]]@(($t[0] + $o), ($t[1] + $o), ($t[2] + $o)) }
        for ($i = 0; $i -lt $s.Axes.Count; $i++) { $m.Axes[$m.Axes.Count] = $s.Axes[$i] }
    }
    return $m
}

# =====================================================================================
# STL I/O
# =====================================================================================

$script:P2 = New-Object double[] 256          # P2[e] = 2^(e - 150): float32 exponent e scales its 24-bit significand
$script:P2[0] = 1.0; for ($i = 0; $i -lt 150; $i++) { $script:P2[0] *= 0.5 }
for ($i = 1; $i -lt 256; $i++) { $script:P2[$i] = $script:P2[$i - 1] * 2.0 }

function F32($b, [int]$o) {         # little-endian IEEE single at b[o], as [BitConverter]::ToSingle
    $e = (([int]$b[$o + 3] -band 0x7F) * 2) + ([int]$b[$o + 2] -shr 7)
    $f = (([int]$b[$o + 2] -band 0x7F) * 65536) + ([int]$b[$o + 1] * 256) + [int]$b[$o]
    if ($e -eq 0) { $v = $f * $script:P2[1] }
    elseif ($e -eq 255) { if ($f -eq 0) { $v = [double]::PositiveInfinity } else { $v = [double]::NaN } }
    else { $v = (8388608 + $f) * $script:P2[$e] }
    if ($b[$o + 3] -ge 128) { $v = -$v }
    return [double]$v
}

function Read-IsoStl {
    <#
    .SYNOPSIS Read binary or ASCII STL into a mesh. Optional -Axes adds centre lines (array of hashtables).
              A binary file is one whose triangle count fills it exactly, or (trailing padding) whose count fits
              and whose header does not start with 'solid'.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Path, [object[]]$Axes = @())
    $bytes = Get-Content -LiteralPath $Path -Encoding Byte -ReadCount 0 -ErrorAction Stop
    if ($null -eq $bytes) { $bytes = [byte[]]@() }
    $bytes = [byte[]]$bytes
    $m = New-IsoMesh
    $binary = $false
    if ($bytes.Length -ge 84) {
        $n = [long]$bytes[80] + 256 * [long]$bytes[81] + 65536 * [long]$bytes[82] + 16777216 * [long]$bytes[83]
        $need = 84 + 50 * $n
        if ($need -eq $bytes.Length) { $binary = $true }
        elseif ($n -gt 0 -and $need -lt $bytes.Length) {
            $head = (-join ([char[]]$bytes[0..4])).ToLower()
            if ($head -cne 'solid') { $binary = $true }
        }
    }
    if ($binary) {
        for ($i = 0; $i -lt $n; $i++) {
            $off = 84 + 50 * $i + 12
            $a = AddV $m (F32 $bytes $off) (F32 $bytes ($off + 4)) (F32 $bytes ($off + 8))
            $b = AddV $m (F32 $bytes ($off + 12)) (F32 $bytes ($off + 16)) (F32 $bytes ($off + 20))
            $c = AddV $m (F32 $bytes ($off + 24)) (F32 $bytes ($off + 28)) (F32 $bytes ($off + 32))
            AddT $m $a $b $c
        }
    } else {
        $text = (-join ([char[]]$bytes)) -replace '[^\x00-\x7F]', '?'     # as [Text.Encoding]::ASCII.GetString
        $rx = [regex]'vertex\s+(\S+)\s+(\S+)\s+(\S+)'
        $ms = $rx.Matches($text)
        $ns = [System.Globalization.NumberStyles]::Float
        for ($i = 0; $i + 2 -lt $ms.Count; $i += 3) {
            $ids = @()
            for ($k = 0; $k -lt 3; $k++) {
                $g = $ms[$i + $k].Groups
                $ids += AddV $m ([double]::Parse($g[1].Value, $ns, $script:IC)) ([double]::Parse($g[2].Value, $ns, $script:IC)) ([double]::Parse($g[3].Value, $ns, $script:IC))
            }
            AddT $m $ids[0] $ids[1] $ids[2]
        }
    }
    foreach ($ax in $Axes) {
        $h = @{}; foreach ($k in @('Base', 'Axis', 'R', 'Z0', 'Z1')) { $h[$k] = $ax.$k }
        $h.Base = [double[]]@($h.Base); $m.Axes[$m.Axes.Count] = $h
    }
    if ($m.T.Count -eq 0) { throw "Read-IsoStl: no triangles in $Path" }
    return $m
}

function Export-IsoStl {
    <# .SYNOPSIS Write a mesh as ASCII STL (round-trip / hand-off), with each facet's unit normal. #>
    [CmdletBinding()] param([Parameter(Mandatory = $true)][hashtable]$Mesh, [Parameter(Mandatory = $true)][string]$Path)
    $sb = Sb
    SbLine $sb 'solid iso128'
    for ($q = 0; $q -lt $Mesh.T.Count; $q++) {
        $t = $Mesh.T[$q]
        $pa = $Mesh.V[$t[0]]; $pb = $Mesh.V[$t[1]]; $pc = $Mesh.V[$t[2]]
        $e1x = $pb[0] - $pa[0]; $e1y = $pb[1] - $pa[1]; $e1z = $pb[2] - $pa[2]
        $e2x = $pc[0] - $pa[0]; $e2y = $pc[1] - $pa[1]; $e2z = $pc[2] - $pa[2]
        $nx = $e1y * $e2z - $e1z * $e2y; $ny = $e1z * $e2x - $e1x * $e2z; $nz = $e1x * $e2y - $e1y * $e2x
        $l = Sqrt ($nx * $nx + $ny * $ny + $nz * $nz)
        if ($l -gt 0) { $nx /= $l; $ny /= $l; $nz /= $l } else { $nx = 0.0; $ny = 0.0; $nz = 0.0 }
        SbLine $sb ('facet normal {0} {1} {2}' -f $nx.ToString('R', $script:IC), $ny.ToString('R', $script:IC), $nz.ToString('R', $script:IC))
        SbLine $sb ' outer loop'
        foreach ($i in $t) { $v = $Mesh.V[$i]; SbLine $sb ('  vertex {0} {1} {2}' -f $v[0].ToString('R', $script:IC), $v[1].ToString('R', $script:IC), $v[2].ToString('R', $script:IC)) }
        SbLine $sb ' endloop'; SbLine $sb 'endfacet'
    }
    SbLine $sb 'endsolid iso128'
    WriteUtf8 (FullPath $Path) (SbText $sb)
}

# =====================================================================================
# Topology + hidden-line removal
# =====================================================================================

function Get-Topology($mesh, [double]$CreaseDeg) {
    $MV = $mesh.V; $nIn = $MV.Count
    $mn = [double[]]@([double]::MaxValue, [double]::MaxValue, [double]::MaxValue)
    $mx = [double[]]@([double]::MinValue, [double]::MinValue, [double]::MinValue)
    for ($i = 0; $i -lt $nIn; $i++) { $v = $MV[$i]; for ($k = 0; $k -lt 3; $k++) { if ($v[$k] -lt $mn[$k]) { $mn[$k] = $v[$k] }; if ($v[$k] -gt $mx[$k]) { $mx[$k] = $v[$k] } } }
    $diag = Sqrt (($mx[0] - $mn[0]) * ($mx[0] - $mn[0]) + ($mx[1] - $mn[1]) * ($mx[1] - $mn[1]) + ($mx[2] - $mn[2]) * ($mx[2] - $mn[2]))
    if ($diag -le 0) { throw 'Empty geometry' }
    $tol = $diag * 1e-6
    # weld
    $map = @{}
    $VWl = @{}
    $remap = New-Object int[] $nIn
    for ($i = 0; $i -lt $nIn; $i++) {
        $v = $MV[$i]
        $key = (RoundEven ($v[0] / $tol)).ToString($script:IC) + ',' + (RoundEven ($v[1] / $tol)).ToString($script:IC) + ',' + (RoundEven ($v[2] / $tol)).ToString($script:IC)
        $id = $map[$key]
        if ($null -ne $id) { $remap[$i] = $id } else { $id = $VWl.Count; $VWl[$id] = $v; $map[$key] = $id; $remap[$i] = $id }
    }
    $VW = ToArray $VWl
    $TWl = @{}; $Nnl = @{}
    $MT = $mesh.T
    for ($q = 0; $q -lt $MT.Count; $q++) {
        $t = $MT[$q]
        $a = $remap[$t[0]]; $b = $remap[$t[1]]; $c = $remap[$t[2]]
        if ($a -eq $b -or $b -eq $c -or $a -eq $c) { continue }
        $pa = $VW[$a]; $pb = $VW[$b]; $pc = $VW[$c]
        $e1x = $pb[0] - $pa[0]; $e1y = $pb[1] - $pa[1]; $e1z = $pb[2] - $pa[2]
        $e2x = $pc[0] - $pa[0]; $e2y = $pc[1] - $pa[1]; $e2z = $pc[2] - $pa[2]
        $nx = $e1y * $e2z - $e1z * $e2y; $ny = $e1z * $e2x - $e1x * $e2z; $nz = $e1x * $e2y - $e1y * $e2x
        $l = Sqrt ($nx * $nx + $ny * $ny + $nz * $nz)
        if ($l -le $tol * $tol) { continue }
        $TWl[$TWl.Count] = [int[]]@($a, $b, $c); $Nnl[$Nnl.Count] = [double[]]@(($nx / $l), ($ny / $l), ($nz / $l))
    }
    $TW = ToArray $TWl; $Nn = ToArray $Nnl
    # edges, in order of first appearance (as the original's Dictionary enumerates them)
    $edgeOf = @{}; $EAl = @{}; $EBl = @{}; $ETl = @{}
    $nv = [long]$VW.Count
    for ($ti = 0; $ti -lt $TW.Count; $ti++) {
        $t = $TW[$ti]
        for ($k = 0; $k -lt 3; $k++) {
            $a = $t[$k]; $b = $t[($k + 1) % 3]
            if ($a -lt $b) { $lo = $a; $hi = $b } else { $lo = $b; $hi = $a }
            $key = [long]$lo * $nv + $hi
            $e = $edgeOf[$key]
            if ($null -eq $e) { $e = $EAl.Count; $edgeOf[$key] = $e; $EAl[$e] = $lo; $EBl[$e] = $hi; $ETl[$e] = @{} }
            $lst = $ETl[$e]; $lst[$lst.Count] = $ti
        }
    }
    $cosC = (SinCos ($CreaseDeg * [Math]::PI / 180.0))[1]
    $ne = $EAl.Count
    $EA = New-Object int[] $ne; $EB = New-Object int[] $ne; $ET = New-Object 'object[]' $ne; $EC = New-Object bool[] $ne
    for ($e = 0; $e -lt $ne; $e++) {
        $ts = ToIntArray $ETl[$e]
        $crease = $true
        if ($ts.Count -eq 2) {
            $n1 = $Nn[$ts[0]]; $n2 = $Nn[$ts[1]]
            $crease = (($n1[0] * $n2[0] + $n1[1] * $n2[1] + $n1[2] * $n2[2]) -lt $cosC)
        }
        $EA[$e] = $EAl[$e]; $EB[$e] = $EBl[$e]; $ET[$e] = $ts; $EC[$e] = $crease
    }
    return @{ V = $VW; T = $TW; N = $Nn; EA = $EA; EB = $EB; ET = $ET; EC = $EC; Min = $mn; Max = $mx; Diag = $diag; Axes = (ToArray $mesh.Axes) }
}

function New-View([string]$Name, [double[]]$D, [double[]]$Up) {
    $ln = Sqrt ($D[0] * $D[0] + $D[1] * $D[1] + $D[2] * $D[2]); $D = [double[]]@(($D[0] / $ln), ($D[1] / $ln), ($D[2] / $ln))
    $dp = $Up[0] * $D[0] + $Up[1] * $D[1] + $Up[2] * $D[2]
    $W = [double[]]@(($Up[0] - $dp * $D[0]), ($Up[1] - $dp * $D[1]), ($Up[2] - $dp * $D[2]))
    $ln = Sqrt ($W[0] * $W[0] + $W[1] * $W[1] + $W[2] * $W[2]); $W = [double[]]@(($W[0] / $ln), ($W[1] / $ln), ($W[2] / $ln))
    $U = [double[]]@(($D[1] * $W[2] - $D[2] * $W[1]), ($D[2] * $W[0] - $D[0] * $W[2]), ($D[0] * $W[1] - $D[1] * $W[0]))
    return @{ Name = $Name; D = $D; U = $U; W = $W }
}

function Get-ViewLines {
    # Returns @{ Lines = list of @(u1,v1,u2,v2,hiddenFlag); Box = umin,vmin,umax,vmax }
    param($Topo, $View, [double]$Scale, [bool]$Hidden)
    $VV = $Topo.V; $TT = $Topo.T; $Nn = $Topo.N
    $Dv = $View.D; $Uv = $View.U; $Wv = $View.W
    $nv = $VV.Count; $nt = $TT.Count
    $pu = New-Object double[] $nv; $pv = New-Object double[] $nv; $pz = New-Object double[] $nv
    $umin = [double]::MaxValue; $umax = [double]::MinValue; $vmin = [double]::MaxValue; $vmax = [double]::MinValue
    for ($i = 0; $i -lt $nv; $i++) {
        $p = $VV[$i]
        $pu[$i] = $p[0] * $Uv[0] + $p[1] * $Uv[1] + $p[2] * $Uv[2]
        $pv[$i] = $p[0] * $Wv[0] + $p[1] * $Wv[1] + $p[2] * $Wv[2]
        $pz[$i] = $p[0] * $Dv[0] + $p[1] * $Dv[1] + $p[2] * $Dv[2]
        if ($pu[$i] -lt $umin) { $umin = $pu[$i] }; if ($pu[$i] -gt $umax) { $umax = $pu[$i] }
        if ($pv[$i] -lt $vmin) { $vmin = $pv[$i] }; if ($pv[$i] -gt $vmax) { $vmax = $pv[$i] }
    }
    $face = New-Object double[] $nt
    for ($i = 0; $i -lt $nt; $i++) { $n = $Nn[$i]; $face[$i] = $n[0] * $Dv[0] + $n[1] * $Dv[1] + $n[2] * $Dv[2] }
    $diag = $Topo.Diag

    # bucket grid over projected triangles
    $g = [int](DMax 8 (DMin 96 (Sqrt $nt)))
    $cw = DMax (($umax - $umin) / $g) 1e-9; $ch = DMax (($vmax - $vmin) / $g) 1e-9
    $cells = New-Object 'object[]' ($g * $g)
    $den = New-Object double[] $nt
    # depth on each triangle's plane: z = (n.a - u n.U - v n.W) / n.D  (exact for slivers)
    $plA = New-Object double[] $nt; $plU = New-Object double[] $nt; $plW = New-Object double[] $nt
    $dlim = 1e-14 * $diag * $diag
    for ($i = 0; $i -lt $nt; $i++) {
        $t = $TT[$i]; $a = $t[0]; $b = $t[1]; $c = $t[2]
        $den[$i] = ($pv[$b] - $pv[$c]) * ($pu[$a] - $pu[$c]) + ($pu[$c] - $pu[$b]) * ($pv[$a] - $pv[$c])
        if ($den[$i] -lt $dlim -and $den[$i] -gt - $dlim) { continue }   # edge-on, cannot occlude
        if ($face[$i] -lt 1e-9 -and $face[$i] -gt -1e-9) { continue }
        $n = $Nn[$i]; $q = $VV[$a]
        $plA[$i] = ($n[0] * $q[0] + $n[1] * $q[1] + $n[2] * $q[2]) / $face[$i]
        $plU[$i] = ($n[0] * $Uv[0] + $n[1] * $Uv[1] + $n[2] * $Uv[2]) / $face[$i]
        $plW[$i] = ($n[0] * $Wv[0] + $n[1] * $Wv[1] + $n[2] * $Wv[2]) / $face[$i]
        $x0 = DMin $pu[$a] (DMin $pu[$b] $pu[$c]); $x1 = DMax $pu[$a] (DMax $pu[$b] $pu[$c])
        $y0 = DMin $pv[$a] (DMin $pv[$b] $pv[$c]); $y1 = DMax $pv[$a] (DMax $pv[$b] $pv[$c])
        $i0 = [int](Floor (($x0 - $umin) / $cw)); if ($i0 -lt 0) { $i0 = 0 }
        $i1 = [int](Floor (($x1 - $umin) / $cw)); if ($i1 -gt $g - 1) { $i1 = $g - 1 }
        $j0 = [int](Floor (($y0 - $vmin) / $ch)); if ($j0 -lt 0) { $j0 = 0 }
        $j1 = [int](Floor (($y1 - $vmin) / $ch)); if ($j1 -gt $g - 1) { $j1 = $g - 1 }
        for ($gi = $i0; $gi -le $i1; $gi++) { for ($gj = $j0; $gj -le $j1; $gj++) {
            $cell = $gj * $g + $gi
            $cl = $cells[$cell]
            if ($null -eq $cl) { $cl = @{}; $cells[$cell] = $cl }
            $cl[$cl.Count] = $i
        } }
    }
    $grid = New-Object 'object[]' ($g * $g)
    for ($k = 0; $k -lt $g * $g; $k++) { if ($null -ne $cells[$k]) { $grid[$k] = ToIntArray $cells[$k] } }
    $epsZ = $diag * 2e-5
    $epsB = -1e-9   # inclusive: points on an occluder's internal edges are covered

    $occluded = {
        param([double]$u, [double]$v, [double]$z, $excl)
        $fq = ($u - $umin) / $cw; $gi = [int]$fq; if ($gi -gt $fq) { $gi-- }      # floor
        $fq = ($v - $vmin) / $ch; $gj = [int]$fq; if ($gj -gt $fq) { $gj-- }
        if ($gi -lt 0) { $gi = 0 }; if ($gi -ge $g) { $gi = $g - 1 }; if ($gj -lt 0) { $gj = 0 }; if ($gj -ge $g) { $gj = $g - 1 }
        $lst = $grid[$gj * $g + $gi]
        if ($null -eq $lst) { return $false }
        foreach ($ti in $lst) {
            if ($excl -contains $ti) { continue }
            $t = $TT[$ti]; $a = $t[0]; $b = $t[1]; $c = $t[2]
            $dd = $den[$ti]
            $l1 = (($pv[$b] - $pv[$c]) * ($u - $pu[$c]) + ($pu[$c] - $pu[$b]) * ($v - $pv[$c])) / $dd
            if ($l1 -le $epsB) { continue }
            $l2 = (($pv[$c] - $pv[$a]) * ($u - $pu[$c]) + ($pu[$a] - $pu[$c]) * ($v - $pv[$c])) / $dd
            if ($l2 -le $epsB) { continue }
            if (1.0 - $l1 - $l2 -le $epsB) { continue }
            $zt = $plA[$ti] - $u * $plU[$ti] - $v * $plW[$ti]
            if ($zt -lt $z - $epsZ) { return $true }
        }
        return $false
    }

    $lines = @{}
    $sEps = 1e-7
    for ($e = 0; $e -lt $Topo.EA.Count; $e++) {
        $ts = $Topo.ET[$e]
        $draw = $Topo.EC[$e]
        if (-not $draw -and $ts.Count -eq 2) {
            $s1 = $face[$ts[0]]; $s2 = $face[$ts[1]]
            $z1 = ($s1 -le $sEps -and $s1 -ge - $sEps); $z2 = ($s2 -le $sEps -and $s2 -ge - $sEps)
            # true limb: facing flips, or one face is exactly edge-on (flat face seen end-on
            # between tangent fillets) - such edges lie on the contour
            $draw = (($s1 -lt - $sEps -and $s2 -gt $sEps) -or ($s1 -gt $sEps -and $s2 -lt - $sEps) -or ($z1 -xor $z2))
        }
        if (-not $draw) { continue }
        $a = $Topo.EA[$e]; $b = $Topo.EB[$e]
        $ua = $pu[$a]; $va = $pv[$a]; $za = $pz[$a]; $du = $pu[$b] - $ua; $dv = $pv[$b] - $va; $dz = $pz[$b] - $za
        $len = Sqrt ($du * $du + $dv * $dv)
        if ($len -lt $diag * 1e-6) { continue }
        $ns = [int](DMax 2 (Ceiling ($len * $Scale / 0.5)))
        $vis = New-Object bool[] ($ns + 1)
        for ($k = 0; $k -le $ns; $k++) {
            $t = $k / $ns
            $vis[$k] = -not (& $occluded ($ua + $t * $du) ($va + $t * $dv) ($za + $t * $dz) $ts)
        }
        # runs with bisection-refined boundaries
        $tStart = 0.0; $state = $vis[0]
        for ($k = 1; $k -le $ns; $k++) {
            if ($vis[$k] -ne $state) {
                $lo = ($k - 1) / $ns; $hi = $k / $ns
                for ($it = 0; $it -lt 12; $it++) {
                    $mid = ($lo + $hi) / 2
                    $mv = -not (& $occluded ($ua + $mid * $du) ($va + $mid * $dv) ($za + $mid * $dz) $ts)
                    if ($mv -eq $state) { $lo = $mid } else { $hi = $mid }
                }
                $tEnd = ($lo + $hi) / 2
                if ($state -or $Hidden) { $lines[$lines.Count] = [double[]]@(($ua + $tStart * $du), ($va + $tStart * $dv), ($ua + $tEnd * $du), ($va + $tEnd * $dv), ([double][int](-not $state))) }
                $tStart = $tEnd; $state = $vis[$k]
            }
        }
        if ($state -or $Hidden) { $lines[$lines.Count] = [double[]]@(($ua + $tStart * $du), ($va + $tStart * $dv), ($ua + $du), ($va + $dv), ([double][int](-not $state))) }
    }
    return @{ Lines = (ToArray $lines); Box = [double[]]@($umin, $vmin, $umax, $vmax); View = $View }
}

function Join-Chains($segs, [double]$tol) {
    # Chain segments of one line type into polylines so dash patterns run continuously.
    $keyOf = { param($x, $y) (RoundEven ($x / $tol)).ToString($script:IC) + ':' + (RoundEven ($y / $tol)).ToString($script:IC) }
    # drop coincident duplicates (e.g. two hidden edges stacked in depth) - they would chain
    # into a there-and-back path whose dash patterns fill each other's gaps
    $seen = @{}; $uniq = @{}
    foreach ($sg in $segs) {
        $k1 = & $keyOf $sg[0] $sg[1]; $k2 = & $keyOf $sg[2] $sg[3]
        if ($k1 -eq $k2) { continue }
        if ([string]::CompareOrdinal($k1, $k2) -lt 0) { $kk = $k1 + '|' + $k2 } else { $kk = $k2 + '|' + $k1 }
        if ($seen.ContainsKey($kk)) { continue }
        $seen[$kk] = $true; $uniq[$uniq.Count] = $sg
    }
    $segs = ToArray $uniq
    $n = $segs.Count
    $used = New-Object bool[] $n
    $ends = @{}
    for ($i = 0; $i -lt $n; $i++) {
        foreach ($kk in @((& $keyOf $segs[$i][0] $segs[$i][1]), (& $keyOf $segs[$i][2] $segs[$i][3]))) {
            if (-not $ends.ContainsKey($kk)) { $ends[$kk] = @{} }
            $el = $ends[$kk]; $el[$el.Count] = $i
        }
    }
    $chains = @{}
    for ($i = 0; $i -lt $n; $i++) {
        if ($used[$i]) { continue }
        $used[$i] = $true
        $front = @{}; $back = @{}              # the chain is front (reversed) then back
        $back[0] = [double[]]@($segs[$i][0], $segs[$i][1]); $back[1] = [double[]]@($segs[$i][2], $segs[$i][3])
        foreach ($dir in @(1, 0)) {
            $grow = $true
            while ($grow) {
                $grow = $false
                if ($dir -eq 1) { $tip = $back[$back.Count - 1] } elseif ($front.Count -gt 0) { $tip = $front[$front.Count - 1] } else { $tip = $back[0] }
                $kk = & $keyOf $tip[0] $tip[1]
                $el = $ends[$kk]
                for ($q = 0; $q -lt $el.Count; $q++) {
                    $j = $el[$q]
                    if ($used[$j]) { continue }
                    $s = $segs[$j]
                    if ((& $keyOf $s[0] $s[1]) -eq $kk) { $nx = [double[]]@($s[2], $s[3]) } else { $nx = [double[]]@($s[0], $s[1]) }
                    $used[$j] = $true
                    if ($dir -eq 1) { $back[$back.Count] = $nx } else { $front[$front.Count] = $nx }
                    $grow = $true; break
                }
            }
        }
        $pts = New-Object 'object[]' ($front.Count + $back.Count)
        for ($q = 0; $q -lt $front.Count; $q++) { $pts[$q] = $front[$front.Count - 1 - $q] }
        for ($q = 0; $q -lt $back.Count; $q++) { $pts[$front.Count + $q] = $back[$q] }
        $chains[$chains.Count] = $pts
    }
    return , (ToArray $chains)
}

# =====================================================================================
# SVG drawing helpers (all coordinates in sheet millimetres, y down)
# =====================================================================================

function Add-Line($sb, [string]$cls, [double]$x1, [double]$y1, [double]$x2, [double]$y2) {
    SbLine $sb ('<line class="{0}" x1="{1}" y1="{2}" x2="{3}" y2="{4}"/>' -f $cls, (N $x1), (N $y1), (N $x2), (N $y2))
}
function Add-Rect($sb, [string]$cls, [double]$x, [double]$y, [double]$w, [double]$h) {
    SbLine $sb ('<rect class="{0}" x="{1}" y="{2}" width="{3}" height="{4}"/>' -f $cls, (N $x), (N $y), (N $w), (N $h))
}
function Add-Text($sb, [string]$s, [double]$x, [double]$y, [double]$size, [string]$anchor = 'start', [double]$rot = 0, [double]$maxW = 0) {
    if ($maxW -gt 0) {
        $est = $s.Length * 0.62 * $size
        if ($est -gt $maxW) { $size = DMax 1.8 ($size * $maxW / $est) }
    }
    $tr = ''
    if ($rot -ne 0) { $tr = (' transform="rotate({0} {1} {2})"' -f (N $rot), (N $x), (N $y)) }
    SbLine $sb ('<text x="{0}" y="{1}" font-size="{2}" text-anchor="{3}"{4}>{5}</text>' -f (N $x), (N $y), (N $size), $anchor, $tr, (Esc $s))
}
function Add-Arrow($sb, [double]$x, [double]$y, [double]$dx, [double]$dy) {
    # closed filled arrowhead, tip at (x,y), pointing along (dx,dy)
    $l = Sqrt ($dx * $dx + $dy * $dy); $dx /= $l; $dy /= $l
    $AL = 3.0; $Hw = 0.55
    $bx = $x - $dx * $AL; $by = $y - $dy * $AL
    SbLine $sb ('<path class="fill" d="M{0} {1} L{2} {3} L{4} {5} Z"/>' -f (N $x), (N $y), (N ($bx - $dy * $Hw)), (N ($by + $dx * $Hw)), (N ($bx + $dy * $Hw)), (N ($by - $dx * $Hw)))
}
function Add-DimH($sb, [double]$x1, [double]$x2, [double]$yObj, [double]$yDim, [string]$txt, [double]$th) {
    $s = Sign ($yDim - $yObj)
    Add-Line $sb 'narrow' $x1 ($yObj + $s * 1) $x1 ($yDim + $s * 2)
    Add-Line $sb 'narrow' $x2 ($yObj + $s * 1) $x2 ($yDim + $s * 2)
    Add-Line $sb 'narrow' $x1 $yDim $x2 $yDim
    Add-Arrow $sb $x1 $yDim -1 0; Add-Arrow $sb $x2 $yDim 1 0
    Add-Text $sb $txt (($x1 + $x2) / 2) ($yDim - 1) $th 'middle'
}
function Add-DimV($sb, [double]$y1, [double]$y2, [double]$xObj, [double]$xDim, [string]$txt, [double]$th) {
    $s = Sign ($xDim - $xObj)
    Add-Line $sb 'narrow' ($xObj + $s * 1) $y1 ($xDim + $s * 2) $y1
    Add-Line $sb 'narrow' ($xObj + $s * 1) $y2 ($xDim + $s * 2) $y2
    Add-Line $sb 'narrow' $xDim $y1 $xDim $y2
    Add-Arrow $sb $xDim $y1 0 -1; Add-Arrow $sb $xDim $y2 0 1
    Add-Text $sb $txt ($xDim - 1) (($y1 + $y2) / 2) $th 'middle' -90
}

function Add-ProjectionSymbol($sb, [double]$cx, [double]$cy, [string]$Projection) {
    # ISO 5456-2 truncated-cone symbol, h = 3.5 mm
    $h = 3.5; $L = 2 * $h; $gap = $h
    $total = $L + $gap + 2 * $h
    $x0 = $cx - $total / 2
    if ($Projection -eq 'First') { $tx = $x0; $ccx = $x0 + $L + $gap + $h }
    else { $ccx = $x0 + $h; $tx = $x0 + 2 * $h + $gap }
    # trapezoid: small end (dia h) on the left, large end (dia 2h) on the right
    SbLine $sb ('<path class="sym" d="M{0} {1} L{2} {3} L{4} {5} L{6} {7} Z"/>' -f (N $tx), (N ($cy - $h / 2)), (N ($tx + $L)), (N ($cy - $h)), (N ($tx + $L)), (N ($cy + $h)), (N $tx), (N ($cy + $h / 2)))
    SbLine $sb ('<circle class="sym" cx="{0}" cy="{1}" r="{2}"/>' -f (N $ccx), (N $cy), (N $h))
    SbLine $sb ('<circle class="sym" cx="{0}" cy="{1}" r="{2}"/>' -f (N $ccx), (N $cy), (N ($h / 2)))
    Add-Line $sb 'center' ($x0 - 1.5) $cy ($x0 + $total + 1.5) $cy
    Add-Line $sb 'center' $ccx ($cy - $h - 1.5) $ccx ($cy + $h + 1.5)
}

function Add-TitleBlock($sb, [double]$x, [double]$y, $tb, [string]$scaleText, [string]$sheetName, [string]$Projection) {
    # ISO 7200 layout, 180 x 36 mm, (x,y) = top-left
    $cells = @(
        @(0, 0, 35, 18, 'Projection', ''),
        @(35, 0, 35, 9, 'Scale', $scaleText),
        @(35, 9, 35, 9, 'Sheet size', $sheetName),
        @(0, 18, 35, 9, 'Created by', $tb.CreatedBy),
        @(35, 18, 35, 9, 'Approved by', $tb.ApprovedBy),
        @(0, 27, 35, 9, 'Technical reference', $tb.TechnicalReference),
        @(35, 27, 35, 9, 'Document type', $tb.DocumentType),
        @(70, 0, 80, 9, 'Legal owner', $tb.Owner),
        @(150, 0, 30, 9, 'Document status', $tb.Status),
        @(70, 9, 110, 18, 'Title, supplementary title', ''),
        @(70, 27, 40, 9, 'Identification number', $tb.DrawingNumber),
        @(110, 27, 14, 9, 'Rev.', $tb.Revision),
        @(124, 27, 24, 9, 'Date of issue', $tb.Date),
        @(148, 27, 12, 9, 'Lang.', $tb.Language),
        @(160, 27, 20, 9, 'Sheet', $tb.Sheet))
    foreach ($c in $cells) {
        Add-Rect $sb 'narrow' ($x + $c[0]) ($y + $c[1]) $c[2] $c[3]
        Add-Text $sb $c[4] ($x + $c[0] + 1) ($y + $c[1] + 2.4) 1.8
        if ($c[5]) { Add-Text $sb ([string]$c[5]) ($x + $c[0] + 1.5) ($y + $c[1] + 7.4) 3.5 'start' 0 ($c[2] - 3) }
    }
    Add-Text $sb ([string]$tb.Title) ($x + 72) ($y + 18.5) 5 'start' 0 106
    if ($tb.Subtitle) { Add-Text $sb ([string]$tb.Subtitle) ($x + 72) ($y + 24.5) 3.5 'start' 0 106 }
    Add-ProjectionSymbol $sb ($x + 17.5) ($y + 10.5) $Projection
    Add-Rect $sb 'frame' $x $y 180 36
}

function Add-Frame($sb, [double]$W, [double]$H, [double]$tbX0 = -1) {
    # ISO 5457: frame 20 mm left (filing margin), 10 mm elsewhere; grid band 5 mm outside the
    # frame; centring marks on the sheet centre lines; 50 mm grid fields counted from them.
    $fx0 = 20; $fy0 = 10; $fx1 = $W - 10; $fy1 = $H - 10
    $bx0 = $fx0 - 5; $by0 = $fy0 - 5; $bx1 = $fx1 + 5; $by1 = $fy1 + 5
    $cx = $W / 2; $cy = $H / 2
    Add-Rect $sb 'narrow' $bx0 $by0 ($bx1 - $bx0) ($by1 - $by0)
    # field boundaries along x and y (centre line plus multiples of 50 mm)
    $xs = @([double]$fx0)
    $k = Ceiling (($fx0 - $cx) / 50.0); while ($cx + 50 * $k -lt $fx1 - 1e-6) { if ($cx + 50 * $k -gt $fx0 + 1e-6) { $xs += ($cx + 50 * $k) }; $k++ }
    $xs += [double]$fx1
    $ys = @([double]$fy0)
    $k = Ceiling (($fy0 - $cy) / 50.0); while ($cy + 50 * $k -lt $fy1 - 1e-6) { if ($cy + 50 * $k -gt $fy0 + 1e-6) { $ys += ($cy + 50 * $k) }; $k++ }
    $ys += [double]$fy1
    $letters = 'ABCDEFGHJKLMNPQRSTUVWXYZ'
    for ($i = 0; $i -lt $xs.Count - 1; $i++) {
        $xa = $xs[$i]; $xb = $xs[$i + 1]
        if ($i -gt 0) { Add-Line $sb 'narrow' $xa $by0 $xa $fy0; Add-Line $sb 'narrow' $xa $fy1 $xa $by1 }
        Add-Text $sb ([string]($i + 1)) (($xa + $xb) / 2) ($by0 + 3.8) 3.5 'middle'
        Add-Text $sb ([string]($i + 1)) (($xa + $xb) / 2) ($by1 - 1.2) 3.5 'middle'
    }
    for ($j = 0; $j -lt $ys.Count - 1; $j++) {
        $ya = $ys[$j]; $yb = $ys[$j + 1]
        if ($j -gt 0) { Add-Line $sb 'narrow' $bx0 $ya $fx0 $ya; Add-Line $sb 'narrow' $fx1 $ya $bx1 $ya }
        $L = [string]$letters[$j % $letters.Length]
        Add-Text $sb $L ($bx0 + 2.5) (($ya + $yb) / 2 + 1.2) 3.5 'middle'
        Add-Text $sb $L ($bx1 - 2.5) (($ya + $yb) / 2 + 1.2) 3.5 'middle'
    }
    # centring marks (wide): trimmed edge to 5 mm inside the frame, stopping at the title block
    $inB = $fy1 - 5; if ($tbX0 -ge 0 -and $cx -ge $tbX0) { $inB = $fy1 }
    Add-Line $sb 'frame' $cx 0 $cx ($fy0 + 5)
    Add-Line $sb 'frame' $cx $H $cx $inB
    Add-Line $sb 'frame' 0 $cy ($fx0 + 5) $cy
    Add-Line $sb 'frame' $W $cy ($fx1 - 5) $cy
    Add-Rect $sb 'frame' $fx0 $fy0 ($fx1 - $fx0) ($fy1 - $fy0)
    return @{ X0 = $fx0; Y0 = $fy0; X1 = $fx1; Y1 = $fy1 }
}

# =====================================================================================
# Main entry point
# =====================================================================================

function New-IsoPlate {
    <#
    .SYNOPSIS
      Render an ISO 128 drawing plate (SVG, true size in mm) from a mesh.
    .PARAMETER Mesh        from Read-IsoStl / New-Iso* primitives / Join-IsoMesh
    .PARAMETER OutFile     .svg path
    .PARAMETER Sheet       A0..A4
    .PARAMETER Orientation Landscape | Portrait
    .PARAMETER Scale       'auto' (largest ISO 5455 scale that fits) or e.g. '1:2', '2:1'
    .PARAMETER Projection  First (ISO default) | Third
    .PARAMETER LineGroup   0.35 | 0.5 | 0.7 | 1.0 (wide line width; narrow = half)
    .PARAMETER TitleBlock  hashtable: Title Subtitle Owner DrawingNumber Revision Date CreatedBy
                           ApprovedBy TechnicalReference DocumentType Status Language Sheet
    .PARAMETER Dimensions  add overall width/height/depth dimensions (ISO 129-1)
    .PARAMETER NoIso       omit the pictorial isometric view
    .PARAMETER CreaseDeg   dihedral angle above which a mesh edge is a real edge (default 25)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][hashtable]$Mesh,
        [Parameter(Mandatory = $true)][string]$OutFile,
        [ValidateSet('A0', 'A1', 'A2', 'A3', 'A4')][string]$Sheet = 'A3',
        [ValidateSet('Landscape', 'Portrait')][string]$Orientation = 'Landscape',
        [string]$Scale = 'auto',
        [ValidateSet('First', 'Third')][string]$Projection = 'First',
        [ValidateSet('0.35', '0.5', '0.7', '1.0')][string]$LineGroup = '0.5',
        [hashtable]$TitleBlock = @{},
        [switch]$Dimensions,
        [switch]$NoIso,
        [double]$CreaseDeg = 25
    )
    $sizes = @{ A0 = @(1189, 841); A1 = @(841, 594); A2 = @(594, 420); A3 = @(420, 297); A4 = @(297, 210) }
    $SW = [double]$sizes[$Sheet][0]; $SH = [double]$sizes[$Sheet][1]
    if ($Orientation -eq 'Portrait') { $t = $SW; $SW = $SH; $SH = $t }
    $wide = [double]::Parse($LineGroup, $script:IC); $narrow = $wide / 2
    $th = 3.5; if ($wide -ge 0.7) { $th = 5 }; if ($wide -le 0.35) { $th = 2.5 }

    $tb = @{ Title = 'Untitled'; Subtitle = ''; Owner = ''; DrawingNumber = ''; Revision = 'A'; Date = (Get-Date -Format 'yyyy-MM-dd');
             CreatedBy = ''; ApprovedBy = ''; TechnicalReference = ''; DocumentType = 'Detail drawing'; Status = 'Draft'; Language = 'en'; Sheet = '1/1' }
    foreach ($k in $TitleBlock.Keys) { $tb[$k] = $TitleBlock[$k] }
    $full = FullPath $OutFile

    Write-Verbose 'Building topology'
    $topo = Get-Topology $Mesh $CreaseDeg
    $mn = $topo.Min; $mx = $topo.Max
    $dx = $mx[0] - $mn[0]; $dy = $mx[1] - $mn[1]; $dz = $mx[2] - $mn[2]

    # Views: model +Z up, front view looks along +Y.
    $vFront = New-View 'front' @(0, 1, 0) @(0, 0, 1)
    $vTop = New-View 'top' @(0, 0, -1) @(0, 1, 0)
    if ($Projection -eq 'First') { $vSide = New-View 'left' @(1, 0, 0) @(0, 0, 1) }   # seen from left, placed right
    else { $vSide = New-View 'right' @(-1, 0, 0) @(0, 0, 1) }                          # seen from right, placed right
    $vIso = New-View 'iso' @(-1, 1, -1) @(0, 0, 1)
    $isoUmin = [double]::MaxValue; $isoUmax = [double]::MinValue; $isoVmin = [double]::MaxValue; $isoVmax = [double]::MinValue
    foreach ($p in $topo.V) {
        $u = $p[0] * $vIso.U[0] + $p[1] * $vIso.U[1] + $p[2] * $vIso.U[2]; $v = $p[0] * $vIso.W[0] + $p[1] * $vIso.W[1] + $p[2] * $vIso.W[2]
        if ($u -lt $isoUmin) { $isoUmin = $u }; if ($u -gt $isoUmax) { $isoUmax = $u }; if ($v -lt $isoVmin) { $isoVmin = $v }; if ($v -gt $isoVmax) { $isoVmax = $v }
    }
    $isoW = $isoUmax - $isoUmin; $isoH = $isoVmax - $isoVmin

    # Layout: drawing area inside frame, above the title block
    $frame = @{ X0 = 20.0; Y0 = 10.0; X1 = $SW - 10; Y1 = $SH - 10 }
    $pad = 8.0; $gap = 22.0; $dm = 0.0; if ($Dimensions) { $dm = 14.0 }
    $ax0 = $frame.X0 + $pad; $ay0 = $frame.Y0 + $pad; $ax1 = $frame.X1 - $pad; $ay1 = $frame.Y1 - 36 - $pad
    $availW = $ax1 - $ax0; $availH = $ay1 - $ay0
    $fixedW = $gap + $dm; $fixedH = $gap + $dm
    $pref = @(50, 20, 10, 5, 2, 1, 0.5, 0.2, 0.1, 0.05, 0.02, 0.01, 0.005, 0.002, 0.001)
    $s = 0.0
    if ($Scale -eq 'auto') {
        foreach ($c in $pref) { if (($c * ($dx + $dy) + $fixedW) -le $availW -and ($c * ($dz + $dy) + $fixedH) -le $availH) { $s = $c; break } }
        if ($s -eq 0) { $s = $pref[$pref.Count - 1] }
    } else {
        $parts = $Scale.Split(':'); $s = [double]::Parse($parts[0], $script:IC) / [double]::Parse($parts[1], $script:IC)
    }
    if ($s -ge 1) { $scaleText = (N $s) + ':1' } else { $scaleText = '1:' + (N (1 / $s)) }

    Write-Verbose ("Scale {0}; computing hidden lines" -f $scaleText)
    $rF = Get-ViewLines $topo $vFront $s $true
    $rT = Get-ViewLines $topo $vTop $s $true
    $rS = Get-ViewLines $topo $vSide $s $true

    $fw = $dx * $s; $fh = $dz * $s; $sideW = $dy * $s; $topH = $dy * $s
    $blockW = $fw + $gap + $sideW; $blockH = $fh + $gap + $topH
    # as the original's [Math]::Max(0, x): PowerShell 5.1 binds the Int32 overload (first argument 0), so x is
    # rounded to a whole millimetre, half to even
    $q = [int](($availW - $dm - $blockW) / 2); if ($q -lt 0) { $q = 0 }; $ox = $ax0 + $dm + $q
    $q = [int](($availH - $dm - $blockH) / 2); if ($q -lt 0) { $q = 0 }; $oy = $ay0 + $dm + $q
    # placement: each view's (left, top) on the sheet
    if ($Projection -eq 'First') {
        $pF = @($ox, $oy); $pS = @(($ox + $fw + $gap), $oy); $pT = @($ox, ($oy + $fh + $gap))
        $isoCell = @(($ox + $fw + $gap), ($oy + $fh + $gap), ($ax1 - ($ox + $fw + $gap)), ($ay1 - ($oy + $fh + $gap)))
    } else {
        $pT = @($ox, $oy); $pF = @($ox, ($oy + $topH + $gap)); $pS = @(($ox + $fw + $gap), ($oy + $topH + $gap))
        $isoCell = @(($ox + $fw + $gap), $ay0, ($ax1 - ($ox + $fw + $gap)), ($oy + $topH + $gap / 2 - $ay0))
    }

    $sb = Sb
    SbLine $sb '<?xml version="1.0" encoding="UTF-8"?>'
    SbLine $sb ('<svg xmlns="http://www.w3.org/2000/svg" width="{0}mm" height="{1}mm" viewBox="0 0 {0} {1}">' -f (N $SW), (N $SH))
    SbLine $sb ('<title>{0}</title>' -f (Esc ($tb.DrawingNumber + ' ' + $tb.Title)))
    $dh = 12 * $narrow; $gh = 3 * $narrow; $cd = 24 * $narrow; $dot = 0.5 * $narrow
    SbLine $sb '<style>'
    SbLine $sb ('.wide{{stroke:#000;stroke-width:{0};fill:none;stroke-linecap:round;stroke-linejoin:round}}' -f (N $wide))
    SbLine $sb ('.frame{{stroke:#000;stroke-width:{0};fill:none}}' -f (N (DMax 0.7 $wide)))
    SbLine $sb ('.narrow{{stroke:#000;stroke-width:{0};fill:none}}' -f (N $narrow))
    SbLine $sb ('.sym{{stroke:#000;stroke-width:{0};fill:none}}' -f (N (DMax 0.35 $narrow)))
    SbLine $sb ('.hidden{{stroke:#000;stroke-width:{0};fill:none;stroke-dasharray:{1} {2};stroke-linejoin:round}}' -f (N $narrow), (N $dh), (N $gh))
    SbLine $sb ('.center{{stroke:#000;stroke-width:{0};fill:none;stroke-dasharray:{1} {2} {3} {2}}}' -f (N $narrow), (N $cd), (N $gh), (N $dot))
    SbLine $sb '.fill{fill:#000;stroke:none}'
    SbLine $sb "text{font-family:osifont,ISOCPEUR,'ISOCP',Arial,Helvetica,sans-serif;fill:#000}"
    SbLine $sb '</style>'
    SbLine $sb ('<rect x="0" y="0" width="{0}" height="{1}" fill="#fff"/>' -f (N $SW), (N $SH))

    SbLine $sb '<g id="frame">'
    $null = Add-Frame $sb $SW $SH ($SW - 10 - 180)
    SbLine $sb '</g>'

    $tol = $topo.Diag * 1e-6
    $emit = {
        param($r, $pos, [bool]$withHidden)
        $box = $r.Box
        $toX = { param($u) $pos[0] + ($u - $box[0]) * $s }
        $toY = { param($v) $pos[1] + ($box[3] - $v) * $s }
        foreach ($hid in @(1.0, 0.0)) {
            if ($hid -eq 1.0 -and -not $withHidden) { continue }
            $segl = @{}
            foreach ($l in $r.Lines) { if ($l[4] -eq $hid) { $segl[$segl.Count] = $l } }
            if ($segl.Count -eq 0) { continue }
            $chains = Join-Chains (ToArray $segl) ($tol * 10)
            $cls = 'wide'; if ($hid -eq 1.0) { $cls = 'hidden' }
            $d = Sb
            foreach ($ch in $chains) {
                $d[$d.Count] = ('M{0} {1}' -f (N (& $toX $ch[0][0])), (N (& $toY $ch[0][1])))
                for ($i = 1; $i -lt $ch.Count; $i++) { $d[$d.Count] = ('L{0} {1}' -f (N (& $toX $ch[$i][0])), (N (& $toY $ch[$i][1]))) }
            }
            SbLine $sb ('<path class="{0}" d="{1}"/>' -f $cls, (SbText $d))
        }
        # centre lines from known axes
        $view = $r.View
        foreach ($ax in $topo.Axes) {
            $fr = Get-AxisFrame $ax.Axis; $w = $fr[2]
            $al = $w[0] * $view.D[0] + $w[1] * $view.D[1] + $w[2] * $view.D[2]
            $b = $ax.Base
            $p0 = [double[]]@(($b[0] + $ax.Z0 * $w[0]), ($b[1] + $ax.Z0 * $w[1]), ($b[2] + $ax.Z0 * $w[2]))
            $p1 = [double[]]@(($b[0] + $ax.Z1 * $w[0]), ($b[1] + $ax.Z1 * $w[1]), ($b[2] + $ax.Z1 * $w[2]))
            $u0 = $p0[0] * $view.U[0] + $p0[1] * $view.U[1] + $p0[2] * $view.U[2]; $v0 = $p0[0] * $view.W[0] + $p0[1] * $view.W[1] + $p0[2] * $view.W[2]
            $u1 = $p1[0] * $view.U[0] + $p1[1] * $view.U[1] + $p1[2] * $view.U[2]; $v1 = $p1[0] * $view.W[0] + $p1[1] * $view.W[1] + $p1[2] * $view.W[2]
            $X0 = & $toX $u0; $Y0 = & $toY $v0; $X1 = & $toX $u1; $Y1 = & $toY $v1
            if ($al -gt 0.999 -or $al -lt -0.999) {
                $rr = $ax.R * $s + 3
                Add-Line $sb 'center' ($X0 - $rr) $Y0 ($X0 + $rr) $Y0
                Add-Line $sb 'center' $X0 ($Y0 - $rr) $X0 ($Y0 + $rr)
            } elseif ($al -lt 0.001 -and $al -gt -0.001) {
                $lx = $X1 - $X0; $ly = $Y1 - $Y0; $ll = Sqrt ($lx * $lx + $ly * $ly)
                if ($ll -gt 0) { $lx /= $ll; $ly /= $ll; Add-Line $sb 'center' ($X0 - 3 * $lx) ($Y0 - 3 * $ly) ($X1 + 3 * $lx) ($Y1 + 3 * $ly) }
            }
        }
    }

    SbLine $sb '<g id="view-front">'; & $emit $rF $pF $true; SbLine $sb '</g>'
    SbLine $sb '<g id="view-top">'; & $emit $rT $pT $true; SbLine $sb '</g>'
    SbLine $sb ('<g id="view-{0}">' -f $vSide.Name); & $emit $rS $pS $true; SbLine $sb '</g>'

    if (-not $NoIso) {
        $cellW = $isoCell[2] - 6; $cellH = $isoCell[3] - 6
        $isoS = $s
        if ($isoW * $isoS -gt $cellW -or $isoH * $isoS -gt $cellH) {
            $isoS = 0
            foreach ($c in $pref) { if ($c -le $s -and $isoW * $c -le $cellW -and $isoH * $c -le $cellH) { $isoS = $c; break } }
        }
        if ($isoS -gt 0) {
            Write-Verbose 'Pictorial view'
            $rI = Get-ViewLines $topo $vIso $isoS $false
            $saveS = $s; $s = $isoS
            $posI = @(($isoCell[0] + ($isoCell[2] - $isoW * $isoS) / 2), ($isoCell[1] + ($isoCell[3] - $isoH * $isoS) / 2))
            $topoAxes = $topo.Axes; $topo.Axes = @()
            SbLine $sb '<g id="view-iso">'; & $emit $rI $posI $false; SbLine $sb '</g>'
            $topo.Axes = $topoAxes
            if ($isoS -ne $saveS) {
                if ($isoS -ge 1) { $it = (N $isoS) + ':1' } else { $it = '1:' + (N (1 / $isoS)) }
                Add-Text $sb ('(' + $it + ')') ($posI[0] + $isoW * $isoS / 2) ($posI[1] + $isoH * $isoS + 6) $th 'middle'
            }
            $s = $saveS
        }
    }

    if ($Dimensions) {
        SbLine $sb '<g id="dimensions">'
        $fmt = { param($x) ((RoundEven ($x * 100.0)) / 100.0).ToString('0.##', $script:IC) }    # [Math]::Round($x, 2)
        Add-DimH $sb $pF[0] ($pF[0] + $fw) $pF[1] ($pF[1] - 10) (& $fmt $dx) $th
        Add-DimV $sb $pF[1] ($pF[1] + $fh) $pF[0] ($pF[0] - 10) (& $fmt $dz) $th
        Add-DimV $sb $pT[1] ($pT[1] + $topH) $pT[0] ($pT[0] - 10) (& $fmt $dy) $th
        SbLine $sb '</g>'
    }

    SbLine $sb '<g id="title-block">'
    Add-TitleBlock $sb ($frame.X1 - 180) ($frame.Y1 - 36) $tb $scaleText ($Sheet) $Projection
    SbLine $sb '</g>'
    SbLine $sb '</svg>'

    WriteUtf8 $full (SbText $sb)
    return (New-Object PSObject -Property ([ordered]@{ File = $full; Scale = $scaleText; Sheet = "$Sheet $Orientation"; Triangles = $topo.T.Count; Edges = $topo.EA.Count }))
}

# Imported as a module: export the cmdlets. Loaded as text (Invoke-Expression, when Group Policy blocks .psm1 files)
# the functions are simply defined in the caller's scope.
if ($ExecutionContext.SessionState.Module) {
    Export-ModuleMember -Function New-IsoMesh, New-IsoBox, New-IsoCylinder, New-IsoRevolve, New-IsoExtrude, Join-IsoMesh, Read-IsoStl, Export-IsoStl, New-IsoPlate
}
