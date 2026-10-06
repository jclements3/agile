# Run both converters with --report on drop 1

Part of #6

## Do

- [ ] Run both converters with --report on drop 1
- [ ] Run `gitlab.pl ci` locally before pushing

## Done when

The result is recorded in a comment on this issue.

---- comments

**@bob** (2026-10-08T14:30:00Z) [system]:
removed ~"workflow::ready" label

**@bob** (2026-10-08T14:30:00Z) [system]:
added ~"workflow::in-progress" label

**@bob** (2026-10-09T15:00:00Z) [system]:
added 1d of time spent

**@bob** (2026-10-09T15:00:00Z) [system]:
removed ~"workflow::in-progress" label

**@bob** (2026-10-09T15:00:00Z) [system]:
added ~"workflow::done" label

**@bob** (2026-10-09T15:00:00Z) [system]:
closed

**@bob** (2026-10-09T15:00:00Z):
Both converters run on drop 1.

- xmi2sysml: ported vs remaining (metric A filter uml:Class|Port|Property|Connector|Activity): 206 of 206 ported, 0 remaining
- trace: F orphan requirements (nothing satisfies), 2, G unverified requirements (no verify), 9, I trace completeness (satisfied and verified), 66.7%
- drift: TW-SYS-006

Reports attached to the sprint evidence.
