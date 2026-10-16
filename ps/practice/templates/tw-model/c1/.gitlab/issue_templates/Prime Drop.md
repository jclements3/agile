<!-- Prime Drop: receiving inspection of one CDRL delivery of the prime's v1 model.
     Prime Drop: the intake of one model drop (XMI + ReqIF + CSV + MANIFEST) delivered under CDRL A003.
     Title: "Intake prime drop v1.x (YYYY-MM-DD)". This is a story: it must finish within the sprint it lands in. -->

## The drop

| | |
|---|---|
| Version | v1. |
| Delivered | <!-- date, and how: contract portal, secure transfer --> |
| CDRL | A003 System Model |
| MANIFEST sha256 | <!-- from MANIFEST.txt --> |
| Previous drop | v1. (#<!-- its intake issue -->) |

## Intake checklist

- [ ] Files received and scanned; hashes match `MANIFEST.txt`
- [ ] `gitlab.pl flow vendor <dropdir> v1.x` committed the drop on `vendor/prime` (vendor pipeline green)
- [ ] The `delta` job's report reviewed: every *manual* line has a task below
- [ ] Merge MR from `feature/drop-v1.x` opened; conflicts resolved (list them below)
- [ ] Trace re-run: discrepancy reports this drop fixes are closed, new ones opened
- [ ] Merged to `develop`; CHANGELOG updated

## Conflicts and manual rework

<!-- One line per conflicted file or manual delta line, with the task that resolves it. -->
| File / element | Why | Task |
|---|---|---|
| | | # |

## Discrepancy reports

<!-- Closed by this drop: #N. Still open: #N. New: #N. -->

/label ~"type::drop" ~"type::story" ~"workflow::ready" ~"priority::1"
/assign @tom
/milestone %"Sprint "
