#requires -Version 5.1
# Example plates (notional Halberd parts). Run:  powershell -ExecutionPolicy Bypass -File .\examples.ps1
# Writes out\bracket.svg, out\bushing.svg, out\bushing.stl, out\bushing_from_stl.svg (about 40 s).
$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot; if (-not $here) { $here = $env:ISO128_DIR }; if (-not $here) { $here = (Get-Location).Path }
$mod = Join-Path $here 'ISO128Plate.psm1'
try { Import-Module $mod -Force }
catch {
    if ($_.Exception.Message -notmatch 'running scripts is disabled|cannot be loaded|not digitally signed') { throw }
    Invoke-Expression (Get-Content -LiteralPath $mod -Raw)
}
$out = Join-Path $here 'out'
if (-not (Test-Path $out)) { $null = New-Item -ItemType Directory $out }

# 1. Angle bracket: drilled base plate + slotted upright (touching, not overlapping)
$m = New-IsoExtrude -Outline @(0,0, 120,0, 120,70, 0,70) -Height 10 `
        -Holes @(@{X=20;Y=20;D=11}, @{X=100;Y=20;D=11}, @{X=60;Y=35;D=24})
# -Axis Y extrudes along +Y; the outline plane is (u = Z, v = X), so points are (z, x)
$m = New-IsoExtrude -Outline @(0,0, 60,0, 60,120, 0,120) -Height 12 -Axis Y -Origin @(0,58,10) `
        -Holes @(@{X=30;Y=30;D=13}) `
        -HolePolygons @(, @(20,70, 40,70, 40,100, 20,100)) -Mesh $m
New-IsoPlate -Mesh $m -OutFile (Join-Path $out 'bracket.svg') -Sheet A3 -Dimensions -Verbose -TitleBlock @{
    Title = 'Angle bracket'; Subtitle = 'S235JR, 10 / 12 mm plate'; Owner = 'Halberd Program (notional)'
    DrawingNumber = 'HAL-0001'; Revision = 'A'; CreatedBy = 'Halberd SE'; ApprovedBy = '-'
    TechnicalReference = 'ISO 2768-m'; DocumentType = 'Detail drawing'; Status = 'Draft' }

# 2. Flanged bushing: one revolve profile (r, z), bore through
$b = New-IsoRevolve -Profile @(10,0, 30,0, 30,8, 18,8, 18,40, 10,40)
New-IsoPlate -Mesh $b -OutFile (Join-Path $out 'bushing.svg') -Sheet A4 -Dimensions -Projection Third -TitleBlock @{
    Title = 'Flanged bushing'; Subtitle = 'CuSn8'; Owner = 'Halberd Program (notional)'; DrawingNumber = 'HAL-0002'
    CreatedBy = 'Halberd SE'; TechnicalReference = 'ISO 2768-f' }

# 3. STL round trip (what you do with build123d / BRL-CAD / Creo exports)
Export-IsoStl -Mesh $b -Path (Join-Path $out 'bushing.stl')
$s = Read-IsoStl -Path (Join-Path $out 'bushing.stl') -Axes @(@{ Base = @(0,0,0); Axis = 'Z'; R = 30; Z0 = 0; Z1 = 40 })
New-IsoPlate -Mesh $s -OutFile (Join-Path $out 'bushing_from_stl.svg') -Sheet A4 -TitleBlock @{ Title = 'Bushing (from STL)'; DrawingNumber = 'HAL-0003' }
