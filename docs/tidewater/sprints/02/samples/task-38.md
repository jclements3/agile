# Turn on "pipelines must succeed" and the MR report widgets

Part of #27

## Do

- [ ] Turn on "pipelines must succeed" and the MR report widgets
- [ ] Run `gitlab.pl ci` locally before pushing

## Done when

The result is recorded in a comment on this issue.

---- comments

**@tom** (2026-10-23T14:30:00Z) [system]:
removed ~"workflow::ready" label

**@tom** (2026-10-23T14:30:00Z) [system]:
added ~"workflow::in-progress" label

**@tom** (2026-10-23T15:45:00Z) [system]:
added 0.5d of time spent

**@tom** (2026-10-23T15:45:00Z) [system]:
removed ~"workflow::in-progress" label

**@tom** (2026-10-23T15:45:00Z) [system]:
added ~"workflow::done" label

**@tom** (2026-10-23T15:45:00Z) [system]:
closed

**@tom** (2026-10-23T15:45:00Z):
"Pipelines must succeed" is on: an MR with a red pipeline cannot be merged. The JUnit and Code Quality reports show on every MR.
