# Tidewater model baseline-1

**Released** 2027-03-19 · **Tag** `baseline-1` · **From** prime drop v1.1 · **Milestones** %"Sprint 1" to %"Sprint 12"

> [!important]
> Cite this baseline by its tag. The tag pipeline proved it rebuilds byte for byte
> (`sha256=9d41…c07b` in the tag message).

## What is in it

| | Count |
|---|---|
| Packages | 12 + `model/doors` + `model/gov` |
| Part definitions | 41 |
| Requirements (from DOORS) | 31 |
| Satisfied and verified | 87 % |
| TODO lines left | 0 |

## Changes since the start of the port

### Added
- The full structure from drop v1.0, with level tags and the `@Procured` metadata (!4 to !21).
- Requirements from DOORS with their `doorsId`; satisfy and verify trace (!22 to !30).
- Hand-written SysML v2 for `BuoyModes`, `DailyUpload`, `EnergyBalance` and the observation-cycle fork (!31 to !38).
- Drop v1.1: the Hygrometer and TW-SYS-017 (!61).

## Prime drops included

| Version | Delivered | Intake |
|---|---|---|
| v1.0 | 2026-10-02 | #5 |
| v1.1 | 2027-01-08 | #61 |

## Known gaps (accepted)

- [ ] TW-SYS-011 not verified: DR-2 (#9), prime due in a later drop
- [ ] TW-SYS-012 not satisfied: DR-1 (#8)
- [ ] TW-SYS-016 not in the Cameo model: DR-4 (#11)

## Evidence

- Tag pipeline #301 (`baseline` job: "baseline-1 rebuilds identically")
- Trace report: the `trace` job artifact of the release MR !70
