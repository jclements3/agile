# Model exchange agreement with the prime

[[_TOC_]]

> [!note]
> This is the working agreement between the government model team and the prime contractor's modeling team: how the
> prime's SysML v1 model and DOORS requirements reach the government, and how problems go back. It does **not**
> change the contract. Where it touches deliverables, it implements the CDRL and its DID; propose changes to those
> through the contracting officer. Fill in every `<!-- -->` with the prime's modeler and record the date below.

| | |
|---|---|
| Government lead | <!-- name, role --> |
| Prime lead | <!-- name, role --> |
| Contract data item | <!-- e.g. CDRL A003 System Model --> |
| Agreed on / last revised | <!-- date; each revision through a merge request --> |

## 1. What is delivered: one drop

A **drop** is one delivery of the model, complete and self-contained:

| File | Format | Notes |
|---|---|---|
| the model | XMI 2.5.1 from Cameo (Eclipse UML2 5.x export) | the whole model, every package; not a partial export |
| the requirements | ReqIF 1.2 (`.reqif` or `.reqifz`) from DOORS | every formal module the model traces to |
| the requirements, readable | CSV from the same DOORS view | for people without a ReqIF reader |
| test results, when there are any | JUnit XML, or CSV in the agreed results format ([ADR 0003](adr/0003-results-schema.md)) | one row per requirement and verification case |
| `MANIFEST.txt` | text, the fields in section 4 | written by the prime's build, not by hand |
| change notes | in `MANIFEST.txt` or a `CHANGES.md` | what changed since the last drop, in the prime's own words |

## 2. When

| | Agreed |
|---|---|
| Cadence | <!-- e.g. every 3 months, plus before each review --> |
| Delivery day | <!-- e.g. a Friday, so the government can take it in the next sprint --> |
| Government acknowledgment | within <!-- 2 --> working days: received, checksums verified |
| Government disposition | within <!-- one sprint -->: accepted into the government model, with any discrepancy reports |

## 3. Stable identifiers

The government's model is merged from every drop, so **identifiers must not change between drops**:

- Every element keeps its `xmi:id` from drop to drop. A renamed element keeps its id; only a new element gets a new
  one. (Cameo keeps ids as long as elements are not deleted and recreated, and the model is not re-imported.)
- Every requirement keeps its DOORS id (Object Identifier). A deleted requirement's id is never reused.
- Packages keep their names. A package rename is announced in the change notes before the drop.

When an id changes anyway, the government's tools show a delete and an add instead of a change, and the work done on
that element has to be redone by hand. So an id change is treated as a discrepancy.

## 4. The manifest

`MANIFEST.txt` in every drop holds at least:

```text
version: v1.1
delivered: 2027-01-08
cdrl: A003 System Model
prime_build: <the build system's job URL and build number>
prime_commit: <the prime's own model repository revision, if it has one>
tools: Cameo <version> + <plugins and versions>; DOORS <version>
files:
  <sha256>  tidewater.xmi
  <sha256>  tidewater.reqif
  <sha256>  tidewater.csv
changes:
  - <one line per change, in the prime's words>
```

The government checks every checksum before anything else. A mismatch means the drop is not received.

## 5. How a drop travels

Pick one, and write which one here: <!-- 1, 2 or 3 -->.

1. **File transfer.** The prime sends the files through the approved file-transfer service. The government's
   configuration manager puts them on approved storage and runs the intake. Simplest; the right start.
2. **The prime's build uploads to GitLab.** The prime's build server (for example its Jenkins) uploads the drop to
   the government project's package registry with a **deploy token** that can only write packages, then starts the
   government's intake pipeline with a **pipeline trigger token**. The prime never gets access to the model
   repository itself.
3. **GitLab fetches from the prime.** A scheduled government job downloads the prime's latest build. Usually blocked
   by the network boundary between the two organizations.

Either way, a green build on the prime's side is **evidence, not acceptance**. The government runs its own checks
(grammar, lint, trace, VCRM) on the intake merge request, and a person approves it.

Tokens: the government issues them, each with one purpose and an expiry date (<!-- 90 days -->), and rotates them.
The prime keeps them in its build server's credential store, never in a script or the model.

## 6. Discrepancy reports: the return path

When the government finds a problem in a drop (a requirement nothing satisfies, text that differs between DOORS and
the model, duplicated or unused elements, an id that changed), it does **not** edit the prime's model. It writes a
**discrepancy report (DR)**:

| | |
|---|---|
| Where the government keeps it | a GitLab issue, label `type::discrepancy`, `owner::prime` |
| What it cites | the drop version, the v1 element's `xmi:id` and name, or the DOORS id; what is wrong; what would fix it |
| How it reaches the prime | <!-- e.g. a transmittal memo through the contracting channel, monthly, or at each drop --> |
| How the prime answers | in the next drop's change notes: "DR-n: fixed" or "DR-n: not accepted, because ..." |
| When it closes | when a drop delivers the fix and the government's checks confirm it |

The transmittal memo template is `docs/memos/templates/discrepancy-report-transmittal.md`.

## 7. Markings and handling

- Each drop is marked at <!-- the level --> and travels only by channels approved for it.
- The prime marks the files, the manifest and the change notes. The government does not re-mark delivered files.
- Nothing above the repository's allowed marking ([markings.md](conventions/markings.md)) goes into a drop.

## 8. The transmittal record

For every drop, the government keeps one record, so anyone can see what was delivered and what happened to it:

| Drop | Delivered | Received (checksums OK) | Merged into the model | DRs opened | DRs closed | Intake MR |
|---|---|---|---|---|---|---|
| <!-- v1.0 --> | | | | | | |

The intake merge request and the `Prime Drop` issue hold the details. The drop itself stays in the package registry
and in `imports/<version>/`, as delivered.

## 9. Changing this agreement

Either side proposes a change. The government records it through a merge request to this file, with the prime's
concurrence quoted in the description, and keeps the history in git.
