## Discrepancy

| | |
|---|---|
| DR number | DR-6 |
| Prime tracking | (to be assigned by the prime) |
| Found in drop | v1.0, delivered 2026-10-02 |
| DOORS id | - |
| Severity | 2 |

## What we found

The requirement recipe (tools/sysml/req-recipe.pl) on the DOORS modules: requirements=30 findings=15 missing=0. Examples:

- weak target verb 'provide' (the recipe): rarely verifiable -- name the concrete action (send, store, measure, report ...)
- weak target verb 'be able to' read: state the action itself ('shall read'), with its threshold
- weak target verb 'be able to' service: state the action itself ('shall service'), with its threshold
- weak target verb 'be' (the recipe): rarely verifiable -- name the concrete action (send, store, measure, report ...)

## What we ask the prime to do

Correct it in the v1 model and say so in the next drop's MANIFEST.

## Closure

- [x] Sent to the prime on 2026-12-08 by @jim
- [ ] Fixed in drop ...
