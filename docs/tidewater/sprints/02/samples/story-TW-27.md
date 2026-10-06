# Runner online; the first pipeline gates every MR

## Why

A check that runs on the server, on every change, is the configuration audit nobody can skip.

## What "done" looks like

- [ ] A pipeline runs on every MR
- [ ] "Pipelines must succeed" is on
- [ ] JUnit and Code Quality reports show on the MR
- [ ] The pipeline is green on every MR of this story

## Tasks

| Task | Points | Who |
|---|---|---|
| #36 Check the runner registration and tags | 0.5 | @tom |
| #37 Commit the pipeline; fix it for the PowerShell runner with ci/job.pl | 2 | @tom |
| #38 Turn on "pipelines must succeed" and the MR report widgets | 0.5 | @tom |

## Notes

Epic E2 (Pipeline and quality gates), tome T1 (Stand up MBSE DevSecOps). Journal id **TW-27**.
