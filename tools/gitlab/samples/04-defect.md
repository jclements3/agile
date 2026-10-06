## What is wrong

`part def Cell` in `model/stations/Stations.sysml` has no level tag, so the outline check fails on `develop`.

## How it shows

Pipeline #214 on `develop`, job **outline**:

```text
model/stations/Stations.sysml:212: part def Cell: no level tag (@L1Network..@L6Component)
check: 1 violation
```

## Expected

`@L6Component;` on `Cell`, as in v1 (stereotype `L6Component`, drop v1.0). The tag was lost when !31 resolved a merge
conflict by taking the prime's text and did not re-apply the government edit.

## Found

| | |
|---|---|
| Found in | pipeline #214 (post-merge on `develop`) |
| Phase | ~"phase::port" |
| Drop | v1.0 |

> [!note]
> Root cause is a process slip, not the model: the Drop Intake Runbook step 5 ("re-apply the government edit") was
> skipped. Fix-forward in !33; the runbook now has a checklist line for it.

/label ~"type::defect" ~"owner::gov" ~"severity::2" ~"area::stations"
/assign @bob
/milestone %"Sprint 5"
