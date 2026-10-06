# !24 Document what crosses each interface

## What and why

Document the flow properties in Interfaces (TW-115).

Closes #123
Part of #115

## Model changes

| Package | Change |
|---|---|
| `model/library/Interfaces.sysml` | changed |

## Checks

- [x] `gitlab.pl ci` passed locally
- [x] `docs/` regenerated and committed
- [x] No new `// TODO` lines
- [x] Trace job: no new orphan, unverified or drifted requirement

---- thread

**@bob** (2026-12-17T19:05:00Z):
**Request changes** -- `model/library/Interfaces.sysml`, the `health` flow:

> Sent with every transmission; the data center flags a station whose report is late.

"Late" assumes a schedule we have not written down anywhere. TW-SYS-009 does not say how late is late. Either cite where the period comes from, or say it is an assumption:

```suggestion:-0+0
        out item health : HealthReport { doc /* Sent with every transmission. Assumption (to confirm with the prime): late = two missed transmissions. */ }
```

**@jim** (2026-12-17T19:20:00Z) [system]:
approved this merge request

**@tom** (2026-12-17T19:50:00Z):
Applied the suggestion; the assumption goes in the next prime-tbd list.

**@bob** (2026-12-17T20:00:00Z) [system]:
approved this merge request

**@tom** (2026-12-17T20:10:00Z) [system]:
merged
