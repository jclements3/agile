# ISO128Plate: ISO 128 drawing plates in Windows PowerShell 5.1

UNCLASSIFIED // NOTIONAL // FICTIONAL - FOR TRAINING (the example parts are notional Halberd parts)

STL in, a drawing plate out: front, top and side views with hidden lines, centre lines, an isometric
pictorial, overall dimensions, the ISO 5457 frame and an ISO 7200 title block, as an SVG at true size.
Pure Windows PowerShell 5.1: no installs, no Add-Type, no Python, and it runs under **Constrained
Language Mode** (AppLocker / WDAC), like the other tools in this kit. ASCII source, LF line endings.

## Run

```
New-Plate.cmd -Stl part.stl -Sheet A3 -Dimensions -Title "Housing" -DrawingNumber "HAL-1234" -CreatedBy "Halberd SE"
New-Plate.cmd -Stl part.stl -TitleJson part.title.json        title block and centre lines from a JSON sidecar
powershell -ExecutionPolicy Bypass -File .\examples.ps1        three example plates into out\ (about 40 s)
```

`part.title.json`: `{ "Title": "Housing", "DrawingNumber": "HAL-1234", "Revision": "B", ... }`, with optional
centre lines `"Axes": [ { "Base": [0,0,0], "Axis": "Z", "R": 15, "Z0": 0, "Z1": 40 } ]`. Without `-Out` the SVG
goes next to the STL. Print it from Edge at 100 % ("actual size") for 1:1 on paper.

Scripted:

```powershell
Import-Module .\ISO128Plate.psm1
$m = New-IsoExtrude -Outline @(0,0, 120,0, 120,70, 0,70) -Height 10 -Holes @(@{X=20;Y=20;D=11})
$m = New-IsoRevolve -Profile @(10,0, 30,0, 30,8, 18,8, 18,40, 10,40) -Base @(60,35,10) -Mesh $m
New-IsoPlate -Mesh $m -OutFile plate.svg -Sheet A3 -Projection First -Dimensions -TitleBlock @{ Title = 'Bracket' }
```

If Group Policy refuses script files ("running scripts is disabled"), load the text instead, from the cad folder:

```powershell
Invoke-Expression (Get-Content -Raw "$PWD\ISO128Plate.psm1")          # then New-IsoPlate etc. as above
$env:ISO128_DIR = "$PWD"
function New-Plate { Invoke-Expression ('& {' + (Get-Content -Raw "$PWD\New-Plate.ps1") + "`n} " + ($args -join ' ')) }
```

`New-Plate.ps1` and `examples.ps1` load the module as text themselves when the `.psm1` file is refused.

`examples-build123d\flange.py` shows the export on the engineering machine (build123d, `export_stl`);
`flange.stl` is its output, so `New-Plate.cmd -Stl examples-build123d\flange.stl -Dimensions` makes a plate here.

## What it applies

| Standard | Implemented |
|---|---|
| ISO 128-20/-24 | line types 01.1, 01.2, 02.1 hidden (12d/3d), 04.1 centre (24d/3d/0.5d/3d); line groups 0.35/0.5/0.7/1.0 |
| ISO 128-30, ISO 5456-2 | front/top/side views, first or third angle, projection symbol |
| ISO 5457 | A0-A4, 20/10 mm frame, centring marks on sheet centre, 50 mm grid fields (no I, O) |
| ISO 7200 | 180 mm title block |
| ISO 5455 | auto scale from the preferred series |
| ISO 129-1 | overall dimensions (`-Dimensions`) |

Model axes: +Z up, the front view looks along +Y.

## Cmdlets

`Read-IsoStl`, `Export-IsoStl`, `New-IsoBox`, `New-IsoCylinder` (tube with `-InnerRadius`), `New-IsoRevolve`,
`New-IsoExtrude` (outline + round holes + polygon cut-outs, along X/Y/Z), `Join-IsoMesh`, `New-IsoPlate`.

## Constrained Language Mode port

This is a port of the FullLanguage ISO128Plate module. Its plates are byte-identical to the original's, in either
language mode (checked on 11 plates: the examples, a 6,466-triangle binary and ASCII STL, primitives on A0-A4,
both projections, every line group, fixed scales, and holes tied on position). What Constrained Language Mode
refuses, and what replaces it:

| Refused | Here |
|---|---|
| `List[T]`, `Dictionary`, `ArrayList`, `StringBuilder` | hashtables used as lists (keys 0..Count-1); edges kept in order of first appearance |
| `[Math]::Sqrt` | Newton's method, then the neighbour with the smallest exact residual (Dekker's product): correctly rounded, as IEEE `sqrt` is |
| `[Math]::Sin` / `Cos` | double-double Taylor series, reduced by the x87 66-bit pi/2 and rounded to 64 then 53 bits, as the x87 `fsin` behind .NET Framework does |
| `[Math]::Floor`, `Ceiling`, `Round`, `Abs`, `Min`, `Max`, `Sign` | `[long]` casts (they round half to even) and comparisons |
| `[BitConverter]::ToSingle` / `ToUInt32` | float32 decoded from its bits with an exact power-of-two table |
| `[IO.File]`, `[Text.Encoding]` | `Get-Content` / `Set-Content -Encoding Byte`, UTF-8 without a BOM |
| `[Security.SecurityElement]::Escape`, `[IO.Path]`, `[pscustomobject]` | string replaces, `Split-Path` / `Resolve-Path`, `New-Object PSObject` |

Two behaviours of the original are kept on purpose so the plates match: `[Math]::Max(0, x)` in the view layout
binds the Int32 overload in PowerShell 5.1, so views are placed on whole millimetres; and `Export-IsoStl` numbers
use .NET's `'R'` format.

`[Math]::Sin` / `Cos` (the x87 `fsin` / `fcos`) is not always correctly rounded. On 135,798 test angles the port
matches it on all but 7, which are 1 ulp apart. A 1 ulp difference in a vertex can change a plate only if it moves a
coordinate across a 0.001 mm rounding boundary or a hidden-line tolerance; no test plate changed.

Changes from the original, both noted in the cmdlet help:

- `Export-IsoStl` writes each facet's unit normal (right-hand rule) instead of `0 0 0`. Its vertices are unchanged.
- `Read-IsoStl` reads a binary STL with trailing padding: the triangle count fits the file and the header does not
  begin with `solid`. The original read only files of exactly 84 + 50 n bytes and reported "no triangles".

## Limits

- Primitives may touch but must not overlap in volume (no boolean engine). Real parts: export STL.
- Centre lines come from primitive holes and revolves; for STL pass `Axes` in the JSON sidecar.
- Tangent edges between smooth faces are not drawn (ISO default). Raise `-CreaseDeg` if a coarse
  STL shows facet lines on curved faces.
- Speed: 7-15 s for the examples, about 35-40 s for a 6,500-triangle STL. Export very fine STLs (more than
  50k triangles) with a coarser tolerance.
- Dimensions are overall sizes only (no hole or feature dimensions, no tolerances); there are no section views.
