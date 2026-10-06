# Log the CDRL delivery and check the sha256 of every file

Part of #5

## Do

- [ ] Log the CDRL delivery and check the sha256 of every file
- [ ] Run `gitlab.pl ci` locally before pushing

## Done when

The result is recorded in a comment on this issue.

---- comments

**@jim** (2026-10-09T14:30:00Z) [system]:
removed ~"workflow::ready" label

**@jim** (2026-10-09T14:30:00Z) [system]:
added ~"workflow::in-progress" label

**@jim** (2026-10-13T15:45:00Z) [system]:
added 1d of time spent

**@jim** (2026-10-13T15:45:00Z) [system]:
removed ~"workflow::in-progress" label

**@jim** (2026-10-13T15:45:00Z) [system]:
added ~"workflow::done" label

**@jim** (2026-10-13T15:45:00Z) [system]:
closed

**@jim** (2026-10-13T15:45:00Z):
Delivery logged. Every file checked against MANIFEST.txt:

| File | sha256 |
|---|---|
| `tidewater.xmi` | matches |
| `tidewater.reqif` | matches |
| `tidewater.csv` | matches |
| `CHANGES.csv` | matches |
