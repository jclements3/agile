# !2 The first pipeline: grammar, lint, outline

## What and why

The configuration audit, run by the server on every change.

Closes #37
Part of #27

## Checks

- [ ] `gitlab.pl ci` passed locally (no pipeline in the project yet)
- [ ] `docs/` regenerated and committed (no docs job yet)
- [x] No new `// TODO` lines
- [ ] Trace job: no new orphan, unverified or drifted requirement (no trace job yet)

## Review notes

Ran green locally with `gitlab.pl ci`; first run on the real runner.

---- thread

**@jim** (2026-10-23T20:00:00Z) [system]:
approved this merge request

**@tom** (2026-10-23T20:10:00Z) [system]:
merged
