# Reviewing a model merge request

[[_TOC_]]

A model review in GitLab is a peer review with the redlines in front of you. The pipeline has already checked what a
machine can check: the grammar, lint, the outline, the trace and whether the generated documents are current.
**Your job is what a machine cannot judge: is the change right?**

Read the merge request's description first, then the **Changes** tab, then the generated documents (the pipeline's
artifacts, or the Pages preview). Leave a comment on the exact line for each finding. Use **Request changes** when
something must change, and **Approve** when you would sign for it.

## Before you start

- [ ] The pipeline is green. If it is red, do not review yet: say so and wait.
- [ ] The description says what and why, and links its issue (`Closes #N`).
- [ ] The change is small enough to review in 30 minutes. If not, ask for it to be split.

## The engineering

- [ ] **It does what the issue asked**, and no more. Unrelated edits go in their own merge request.
- [ ] **Requirements**: every new or changed requirement is one testable statement, has a DOORS id (or a DR asking
      the prime for one), a verification method, and a `satisfy` from the element that really satisfies it.
- [ ] **Trace at the right level**: `satisfy` and `allocate` point at the element that does the work, not at the
      whole system and not at every component.
- [ ] **Interfaces**: a change to a port, an interface or an item that another package uses has that package's
      owner as a reviewer (CODEOWNERS asks for it).
- [ ] **Behavior**: states have a way in and a way out; every action has its inputs; the flows connect.
- [ ] **Values**: units are stated (`Power`, `Energy`), assumptions are written in a `doc` comment, numbers are
      notional or come from a cited source.
- [ ] **Names** follow [naming.md](naming.md). No `copy`, `old`, `tbd` or numbered names.
- [ ] **No new spider web**: no new package dependency cycle, no import from a higher layer, no duplicated
      definition (reuse the existing one).

## Configuration and security

- [ ] **Markings**: new packages carry a marking; nothing raises a marking without the security officer's comment
      ([markings.md](markings.md)).
- [ ] **Converter files**: lines that came from the prime are changed only to close a `// TODO` line or by an
      accepted DR. Other changes to the prime's content go back to the prime.
- [ ] **No secrets**: no tokens, passwords or keys, even in an example.
- [ ] **Generated documents** in `docs/` were regenerated, not edited by hand.

## How to write a finding

| Instead of | Write |
|---|---|
| "This is wrong." | "The battery `capacity` has no unit; `Energy` would let the energy balance check it." |
| "Why?" | "Why does `QualityControl` depend on `SensorSuite`? It creates a cycle with Stations." |
| a long thread | a suggestion block with the exact replacement text |

The author resolves each thread by changing the model or by answering it. The merge request cannot merge with an
open thread.
