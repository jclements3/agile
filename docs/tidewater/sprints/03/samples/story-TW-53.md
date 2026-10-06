# Trace report and secret detection in the pipeline

## Why

Every change shows its effect on the trace; nothing secret reaches the repository.

## What "done" looks like

- [ ] The trace job reports C/F/G/I and drift
- [ ] The secrets job runs on every MR
- [ ] The pipeline is green on every MR of this story

## Tasks

| Task | Points | Who |
|---|---|---|
| #63 Add the trace job (report only) and the secrets job | 2.5 | @tom |

## Notes

Epic E2 (Pipeline and quality gates), tome T1 (Stand up MBSE DevSecOps). Journal id **TW-53**.
