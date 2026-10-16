# 3. One results file format for every verification verdict

Date: (the day you merge this)

## Status

Accepted

## Context

Verification verdicts come from many places: the prime's test lab, the government's own analyses, inspections done
by an engineer, and, later, simulations and lab benches. If each source keeps its own format, the verification
cross-reference matrix (VCRM) has to be assembled by hand before every review, and nobody can say which design was
tested.

## Decision

Every verdict, from any source, is a row in a CSV file under `verification/`, with these columns:

| Column | Meaning |
|---|---|
| `requirement` | the DOORS id, e.g. `TW-SYS-011` |
| `case` | the verification case (the `verification def` name) |
| `verdict` | `passed`, `failed` or `not-run` |
| `commit` | the model commit, or the baseline tag, that was verified |
| `environment` | where it ran: `prime-lab`, `analysis`, `inspection`, `sil`, `hil-lab-1` ... |
| `timestamp` | when, ISO 8601 |
| `signed_by` | for analysis and inspection, the engineer who signs for it; empty for automated results |

One file per source: `results.csv` for the government's own entries, `results-prime.csv` for the prime's (converted
from its JUnit), `results-sil.csv` and `results-hil.csv` for later harnesses. The pipeline's `vcrm` job reads them all
and builds the VCRM. The newest row for a requirement and case wins.

## Consequences

- The VCRM is regenerated on every merge request and published on the Pages site. Nobody assembles it by hand.
- A verdict always names the configuration it applies to, so a result stops counting when the model changes after it.
- Manual verdicts need a name in `signed_by`, which a reviewer checks like any other change.
- A new source of results needs only a converter to these columns, not a change to the VCRM.
