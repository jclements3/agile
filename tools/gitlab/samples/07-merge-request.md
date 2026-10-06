## What and why

Closes the 25 level-tag TODO lines in Stations (task #19, story #18). Each `// TODO stereotype
Tidewater_Profile:L…` line becomes the matching `@L…;` tag, in place, so the next prime drop merges around it.

Closes #19
Part of #18

## Model changes

| Package | Change |
|---|---|
| `model/stations` | 25 `@L…` tags replace the stereotype TODOs; `private import Conventions::*;` added |
| `model/gov` | none (the tags were defined in !12) |
| `docs/` | regenerated: `Nouns.md` now shows levels L2 to L6 under StationSegment |

## Checks

- [x] `gitlab.pl ci` passed locally (grammar, lint 0/0, outline, docs)
- [x] `docs/` regenerated and committed
- [x] No new `// TODO` lines (29 → 4 in this file; the 4 left are #20 and #22)
- [x] Trace job: no new orphan, unverified or drifted requirement
- [x] Commit messages carry a `Changelog:` trailer

## Review notes

Look at `PowerSystem` first: its `bind` lines sit right under the tag and are the likeliest place for a merge conflict
with the next drop. @jim, the outline check now passes for Stations; please accept the package on #27.

<details><summary>Pipeline (local run)</summary>

```text
check   grammar   success   0.8s
check   lint      success   0.7s   elements=138 errors=0 warnings=0
check   outline   success   0.1s
check   todo      success   0.0s   TODO lines remaining: 27
check   secrets   success   0.1s
trace   trace     allowed_failure  1.2s   orphans: TW-SYS-012 TW-SYS-016
docs    docs      success   0.9s
```

</details>
