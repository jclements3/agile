## Why

The stations are half of Tidewater's structure, and every analysis of power and telemetry starts from them. Until the
converter's TODO lines in `model/stations/Stations.sysml` are closed, the part tree has no level tags and the outline
check cannot vouch for it.

## What "done" looks like

- [ ] No `// TODO stereotype` line left in `model/stations/Stations.sysml`; each became an `@L…` level tag
- [ ] The `Procured` stereotype on DataLogger, SolarPanel and Modem is carried as `@Procured { supplier; partNumber; }`
- [x] The `BuoyModes` state machine TODO has its own task (#20), not in this story
- [ ] The pipeline is green on the MR (grammar, lint 0/0, outline, docs current)
- [ ] The trace job shows no new orphan, unverified or drifted requirement

## Tasks

| Task | Points | Who |
|---|---|---|
| #19 Replace the level-tag TODOs in Stations with `@L…` tags | 2 | @bob |
| #20 Write `state def BuoyModes` from the v1 state machine | 3 | @bob |
| #22 Define `@Procured` in `model/gov/Conventions.sysml` and apply it | 2 | @tom |
| #23 Review Stations with the prime's modeler (30-minute call) | 1 | @jim |

## Notes

- v1 elements: `StationSegment` … `Cell`, 25 blocks (drop v1.0). The TODO lines carry each element's `xmi:id`.
- Decision (wiki *Decision: level tags*): the v1 profile stereotypes become metadata definitions in `model/gov`, applied
  in place, so the next drop's merge keeps them.

<details><summary>Definition of Ready</summary>

- [x] Fits in one sprint and has an epic (~"epic::structure") and a tome (~"tome::port")
- [x] Acceptance criteria above are testable
- [x] Tasks are cut, each at most 5 points
- [x] Dependencies linked: blocked by #12 (the level tags exist)

</details>
