## The drop

| | |
|---|---|
| Version | v1.0 |
| Delivered | 2026-10-02, contract portal |
| CDRL | A003 System Model |
| MANIFEST sha256 | `4f1c…9a7e` |
| Previous drop | none: this is the port's starting point |

## Intake checklist

- [x] Files received and scanned; hashes match `MANIFEST.txt`
- [x] `gitlab.pl flow vendor /secure/drops/2026-10-02 v1.0` committed the drop on `vendor/prime` (pipeline #9 green)
- [x] The `delta` job: first drop, nothing to compare
- [x] Merge MR !4 from `feature/drop-v1.0` opened; no conflicts (first import)
- [x] Trace run: 29 of 30 DOORS requirements linked; DR-1 (TW-SYS-012 orphan), DR-2 (TW-SYS-011 unverified), DR-3
      (TW-SYS-006 drift) and DR-4 (TW-SYS-016 not in the model) opened
- [x] Merged to `develop`; CHANGELOG updated

## Conversion report

| | |
|---|---|
| v1 elements read | 521 |
| In scope ported | 194 of 194 |
| TODO lines | 52 (13 unmapped constructs, 39 stereotypes) |
| Grammar | 12 files, 0 errors |

## Conflicts and manual rework

| File / element | Why | Task |
|---|---|---|
| `BuoyModes` | state machine: not converted | #20 |
| `DailyUpload` | interaction: not converted | #29 |
| `EnergyBalance` | constraint expression: not converted | #30 |
| `ObserveCoast` fork, pin, object flow | activity nodes: not converted | #31 |

## Discrepancy reports

New: #8 (DR-1), #9 (DR-2), #10 (DR-3), #11 (DR-4).

/label ~"workflow::done"
