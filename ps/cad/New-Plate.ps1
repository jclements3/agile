#requires -Version 5.1
<#
.SYNOPSIS
  Command-line wrapper: STL in, ISO 128 plate (SVG) out. Runs under Constrained Language Mode.

.EXAMPLE
  New-Plate.cmd -Stl part.stl -Out part.svg -Sheet A3 -Dimensions -Title "Housing" -DrawingNumber "HAL-1234" -CreatedBy "Halberd SE"

.EXAMPLE
  # title block from a JSON sidecar (e.g. emitted by the SysML v2 pipeline)
  New-Plate.cmd -Stl part.stl -TitleJson part.title.json
  # part.title.json: { "Title": "Housing", "DrawingNumber": "HAL-1234", "Revision": "B", ... }
  # optional centre lines: { "Axes": [ { "Base": [0,0,0], "Axis": "Z", "R": 15, "Z0": 0, "Z1": 40 } ] }

.NOTES
  Loads ISO128Plate.psm1 from this folder. When Group Policy refuses script files, the module is loaded as text;
  when this script itself is loaded as text, set $env:ISO128_DIR to the cad folder (or run from it).
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Stl,
    [string]$Out,
    [ValidateSet('A0', 'A1', 'A2', 'A3', 'A4')][string]$Sheet = 'A3',
    [ValidateSet('Landscape', 'Portrait')][string]$Orientation = 'Landscape',
    [string]$Scale = 'auto',
    [ValidateSet('First', 'Third')][string]$Projection = 'First',
    [ValidateSet('0.35', '0.5', '0.7', '1.0')][string]$LineGroup = '0.5',
    [string]$TitleJson,
    [string]$Title, [string]$Subtitle, [string]$Owner, [string]$DrawingNumber, [string]$Revision,
    [string]$CreatedBy, [string]$ApprovedBy, [string]$TechnicalReference, [string]$DocumentType, [string]$Status,
    [switch]$Dimensions, [switch]$NoIso, [double]$CreaseDeg = 25
)
$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot; if (-not $here) { $here = $env:ISO128_DIR }; if (-not $here) { $here = (Get-Location).Path }
$mod = Join-Path $here 'ISO128Plate.psm1'
try { Import-Module $mod -Force }
catch {
    if ($_.Exception.Message -notmatch 'running scripts is disabled|cannot be loaded|not digitally signed') { throw }
    Invoke-Expression (Get-Content -LiteralPath $mod -Raw)          # the module's text, when .psm1 files are refused
}

# [System.IO.Path]::ChangeExtension / GetFileNameWithoutExtension (refused under Constrained Language Mode)
$leaf = Split-Path -Path $Stl -Leaf
if (-not $Out) { if ($leaf -match '\.') { $Out = $Stl -replace '\.[^.\\/]*$', '.svg' } else { $Out = $Stl + '.svg' } }

$tb = @{ Title = ($leaf -replace '\.[^.]*$', '') }
$axes = @()
if ($TitleJson) {
    $j = Get-Content -Raw -Path $TitleJson | ConvertFrom-Json
    foreach ($p in $j.PSObject.Properties) {
        if ($p.Name -eq 'Axes') { $axes = @($p.Value) } else { $tb[$p.Name] = [string]$p.Value }
    }
}
$bound = @($PSBoundParameters.Keys)          # (.ContainsKey is a method call, refused under Constrained Language Mode)
foreach ($k in @('Title', 'Subtitle', 'Owner', 'DrawingNumber', 'Revision', 'CreatedBy', 'ApprovedBy', 'TechnicalReference', 'DocumentType', 'Status')) {
    if ($bound -contains $k) { $tb[$k] = Get-Variable -Name $k -ValueOnly }
}

$mesh = Read-IsoStl -Path $Stl -Axes $axes
New-IsoPlate -Mesh $mesh -OutFile $Out -Sheet $Sheet -Orientation $Orientation -Scale $Scale -Projection $Projection `
    -LineGroup $LineGroup -TitleBlock $tb -Dimensions:$Dimensions -NoIso:$NoIso -CreaseDeg $CreaseDeg
