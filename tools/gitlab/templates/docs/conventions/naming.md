# Naming

[[_TOC_]]

Names are how people find things in a text model. A consistent name is searchable with one `grep`; an inconsistent
one is found by luck. These rules hold for everything the **government** writes. Files that come from the prime
through the converter keep the prime's names. Rename those through a discrepancy report to the prime, never by hand:
a hand rename makes every later drop conflict.

## The model

| Thing | Rule | Example | Not |
|---|---|---|---|
| package | UpperCamelCase noun, the subject it holds | `Stations`, `PowerSystem` | `stations_pkg`, `Pkg1` |
| part, port, item, interface, action, state def | UpperCamelCase noun (action: verb phrase) | `MooredBuoy`, `ObservationIF`, `CheckQuality` | `moored_buoy`, `Block1` |
| usage (part, port, attribute, action) | lowerCamelCase, the role it plays | `buoys`, `obsOut`, `stateOfCharge` | `MooredBuoy1`, `p1` |
| requirement usage | the id with `-` and `.` as `_` | `TW_SYS_006` | `req6`, `Requirement 6` |
| requirement id | as DOORS has it, never reused | `TW-SYS-006` | a new number for an edited requirement |
| verification def | verb + what it shows | `TestDataFlow`, `InspectVesselAccess` | `Test1` |
| metadata def | what it marks | `Procured`, `L3Station` | `Stereo7` |
| quoted names `'like this'` | only when the source used spaces; prefer a plain name | `'Stakeholder Needs'` (from DOORS) | in new government text |

A name says what the thing **is**, not where it sits in a diagram or a document. `Copy of SensorSuite`, `Battery_old`
and `TBD Component` are the v1 model's spider web; they do not come back.

## Files and folders

- One top-level package per `.sysml` file, named after the package: `Stations.sysml` holds `package Stations`.
- The folders are layers (`.ci/layout.map` says where each prime package lands; Tidewater's is in the kit as
  `examples/tidewater-v1/layout.map`): `library/` -> `requirements/` -> `logical/` -> `physical/`
  -> `analysis/` -> `verification/`. A package may depend on its own layer or a lower one (the `complexity` job checks).
- Government-only additions go in the layer they belong to (`library/conventions/`, `logical/GovBehavior.sysml`) and
  begin with a `// Government-owned` comment that says why they exist.
- The `outline` job counts folders with fewer than 2 or more than 9 entries; the layout keeps one folder per segment,
  so some folders hold one file: those are in the ratchet's allowance (`.ci/outline-max`), not hidden. A new
  project's allowance has room for the layer folders still to come (each starts with one file); its comment lines
  say when to tighten it to the count the job prints.

## Branches, merge requests, commits and tags

| Thing | Rule | Example |
|---|---|---|
| feature branch | `feature/<issue number>-<a few words>` | `feature/41-sys006-wording` |
| release branch | `release/baseline-N` | `release/baseline-1` |
| hotfix branch | `hotfix/<what>` | `hotfix/satisfy-sys-014` |
| drop branch | made by `gitlab.pl flow vendor`: `feature/drop-<version>` | `feature/drop-v1.1` |
| merge request title | what the model gains, as a verb phrase | `Close the Stations TODO lines` |
| commit message | first line under 60 characters, imperative; then why | `Add the Storm mode to BuoyModes` |
| tag | `baseline-N`, annotated, made by `gitlab.pl flow released` | `baseline-0` |

## Issues

- A story's title is something you could show at the sprint review: `Break the Stations to DataCenter cycle`.
- A task's title is one piece of work under a week: `Move the ObservationRecord dependency to Interfaces`.
- A discrepancy report's title names the v1 element and the problem: `DR: TW-SYS-012 has no satisfy in drop 1`.
