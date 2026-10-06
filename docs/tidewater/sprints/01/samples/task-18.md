# Run the draft locally on drop 1 with gitlab.pl ci

Part of #4

## Do

- [ ] Run the draft locally on drop 1 with gitlab.pl ci
- [ ] Run `gitlab.pl ci` locally before pushing

## Done when

The result is recorded in a comment on this issue.

---- comments

**@tom** (2026-10-15T14:30:00Z) [system]:
removed ~"workflow::ready" label

**@tom** (2026-10-15T14:30:00Z) [system]:
added ~"workflow::in-progress" label

**@tom** (2026-10-16T15:00:00Z) [system]:
added 1d of time spent

**@tom** (2026-10-16T15:00:00Z) [system]:
removed ~"workflow::in-progress" label

**@tom** (2026-10-16T15:00:00Z) [system]:
added ~"workflow::done" label

**@tom** (2026-10-16T15:00:00Z) [system]:
closed

**@tom** (2026-10-16T15:00:00Z):
The draft runs locally (sh) on drop 1:

```text
grammar                  check      success             2.0s
lint                     check      success             2.4s
outline                  check      failed              0.7s
pipeline: failed (3 jobs)
logs: /tmp/gitlab-ci
```
