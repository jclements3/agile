<!-- Title: "Release baseline-N". Source: release/baseline-N. Target: main. Only Jim or Tom merges it. -->

## Baseline

| | |
|---|---|
| Baseline | baseline- |
| Built from | develop at <!-- sha --> |
| Prime drops included | v1.<!-- x --> (#<!-- intake issue -->) |
| Milestones | %"Sprint " |

## Contents

<!-- From CHANGELOG.md [Unreleased], moved under the new baseline heading in this MR. -->

## Release checklist

- [ ] Only release fixes on this branch (version strings, CHANGELOG, docs regenerated)
- [ ] Pipeline green; trace gaps listed below are accepted by @jim
- [ ] CCB concurrence recorded as a comment on this MR by the deputy PM
- [ ] After merge: `gitlab.pl flow released <this MR's number>` tags `baseline-N` on main (the tag pipeline checks the docs hash)
- [ ] Release created with these notes; back-merge MR main → develop merged

## Accepted gaps

<!-- Orphans, unverified requirements and open DRs that ship in this baseline, each with its DR or story. -->

/label ~"workflow::review"
/assign_reviewer @jim
