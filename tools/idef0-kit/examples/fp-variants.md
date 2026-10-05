# Railway-oriented pipeline — variant groups (`o/`)

A functional error-handling pipeline: each stage returns **exactly
one** of its `o/` group — the sum type made visible. The bracket on
the box edge binds the exclusive set; happy path rides the top rail,
failures fall to the collector.

`Config Parser` and `Rule Engine` are marked `m/` — *module* means
(libraries, dictionaries, pure interpreters). Bare `m` stays worldly
(`Runtime`, `Logger`). The first two boxes therefore render as the
**pure core** (tinted); the effects boundary is now derived, not
asserted.

```idef0
tP Config Pipeline
## Result-style pipeline: every `o/` bundle is an exclusive variant
## group -- *exactly one fires per invocation*. Exclusivity is a
## property of the output bundle, not of any incoming control: Parse
## Config is a pure pattern-match with no `c` port at all.
  a1 Parse Config
    i1 Raw Config Text
    o/1 Parsed Config
    o/2 Parse Failure
    m/1 Config Parser
  a2 Validate Config
    i1 Parsed Config
    c1 Validation Rules
    o/1 Valid Config
    o/2 Validation Failure
    m/1 Rule Engine
  a3 Apply Config
    i1 Valid Config
    o1 Applied State
    m1 Runtime
  a4 Report Failure
    i1 Parse Failure
    i2 Validation Failure
    o1 Error Report
    m1 Logger
```
