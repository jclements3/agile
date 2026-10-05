# HANDOFF.md — integrated ledger-idef0 feature

You are picking up the **idef0-kit** project to add ledger accounting:
budget, track (actuals), forecast, and report the management of
projects modeled in IDEF0, using DroneCorp as the working example.
This document is self-sufficient: it contains the mission, the full
current state of the kit, the authoritative behaviors you must not
break, and the working process JC expects.

## 1. Context and working process

- JC works from a phone. Uploading files is unreliable; **ask JC to
  attach the idef0-kit files first**, but be prepared to rebuild from
  the spec in §3–§5 if attachment fails (this happened once before and
  the rebuild-from-spec worked).
- If an authoritative question arises about existing tool behavior
  that this document does not answer, give JC a short pasteable
  question block to relay to the previous chat ("idef0 dronecorp
  models"), and wait for the pasted answer. Do not guess and diverge.
- JC's design ethos is **ruthless minimalism**: plain text, no
  unnecessary syntax, everything derivable is derived, Unix-style
  tools, Emacs-first. Propose the most semantically reduced design
  and let JC drive decisions.
- Process rules JC has used and expects:
  1. Work in dependency order; after every change run `idef0 lint` on
     the whole project and show the summary line; fix to **0 errors,
     0 warnings** before proceeding.
  2. Never break existing diagnostics, output formats, or round-trip
     guarantees; keep a broken-input regression file and re-check it.
  3. Final deliverables staged and presented as files, HTML first.

## 2. Mission: the ledger feature

Add ledger accounting to the toolchain so an IDEF0 model set doubles
as the management accounting structure of the enterprise it models:

- **Budget**: author budgets against the model (period-based).
- **Track**: record actuals as double-entry journal entries.
- **Forecast**: project remaining periods from budget + actuals
  (at minimum: run-rate and budget-phased methods; keep pluggable).
- **Report**: variance (budget vs actuals vs forecast), roll-ups,
  and drill-down that follows the decomposition hierarchy.

### The structural insight to build on

The IDEF0 activity tree **is** the chart of accounts:

- Activity node ids (`P`, `P3`, `P32`, …, `P321211`) are hierarchical
  account codes; each digit is one decomposition level, so ledger
  roll-ups are exactly plate roll-ups. Model letters partition the
  enterprise (P = Production cost centers, F = Finance, …).
- DroneCorp already models budget distribution: `E23.o1 Approved
  Budgets` fans out to nine consumer models (hub-and-spoke). The
  ledger's budget allocation should be checkable against these
  modeled flows — money may only flow where the model says it flows
  (lintable).
- Mechanisms (`m` ports: crews, machines, labs) are natural resource/
  rate carriers; flows are natural cost drivers. Whether rates attach
  to mechanisms in v1 is an open design question for JC.

### Design directions to propose (strawman, JC decides)

- Journal syntax in the same literate markdown, in ```` ```ledger ````
  fences beside the ```` ```idef0 ```` fences — one document carries
  the system design AND its books. Beancount/ledger-cli-style
  double-entry lines, but reduced to the project's minimum; account
  names ARE node ids (e.g. `P3212:materials` or bare `P3212`).
- New subcommands on the same `idef0` entry point (or a sibling tool
  sharing the parser): `budget`, `post`/`actuals`, `forecast`,
  `report`, each reading the .md directly. Reports as text tables and
  as an HTML view integrated with plates.html (per-plate cost panel;
  the tooltip/navigation machinery in §5 is reusable).
- Lint extensions: unbalanced entries, postings to undefined node
  ids, postings that violate modeled budget flows, period gaps.
- Everything round-trips through `fmt` untouched (ledger fences are
  raw lines to the idef0 parser — verify this stays true).

### The Rust port

`idef0.rs` is a complete, zero-dependency Rust port of the Python tool
(single file; build: `rustc -O idef0.rs -o idef0-rs`). It is verified
**byte-identical** on stdout, stderr, and exit codes across every
command by `tests/golden.sh`. Workflow: the Python `idef0` is
canonical -- implement new features (including the ledger) in Python
first, then re-sync the port and use the golden harness as the
acceptance test. Do not let the port block or shape Python work.

## 3. The DSL (current, authoritative)

One element per line: `tag suffix name [< path | > path]`.

- Tags: `t` model root, `a` activity, `i c o m` ICOM ports attached
  to the activity line above. Indentation = hierarchy, 2 spaces per
  level, `t` at column 0.
- Suffix: `#` auto-number (by list position), pinned digit `1`-`9`,
  model letter (on `t` only), or assertion form like `22.` (trailing
  dot). All numbering is derived; `fmt --number` freezes to pinned
  forms, `fmt --auto` writes `#`.
- Names: free text; reserved: `|`, `<`, `>`, newline, and a
  whitespace-then-`#` sequence (starts a trailing comment).
- Same flow name within a model auto-connects producer `o` to
  consumer `i`/`c`/`m`. Cross-model links are explicit and PAIRED:
  consumer port carries `< Model|Activity|…|Flow`, producer carries
  `> …`. Fan-out is hub-and-spoke: producer declares ONE
  representative `>`, every consumer declares `<`; pairing check only
  needs the target port to carry some link. Renamed-across-boundary
  flows appear as two rows in the links table.
- Path resolution walks level by level (no descendant search):
  child activity by name → port by flow name (2+ same-name = ambiguous
  error) → port ref `[icom]N` → node number. A `<` path ending at an
  activity with exactly one output takes that output.
- Comments: `#` full-line and trailing (whitespace-preceded);
  `;` legacy accepted. Doc comments: `##` full-line attaches to the
  element line ABOVE; trailing `##` on an element line attaches to
  that element; consecutive doc lines join with spaces; literal `\n`
  (or a bare `##` line) breaks paragraphs; inline markdown rendered
  in HTML: `**bold**`, `*italic*`, `` `code` ``, `[label](url)`.
  Dangling doc comment = warning. The auto-number suffix `a#`/`i#`
  never conflicts: it is glued to its tag, comments require preceding
  whitespace.
- **Literate markdown**: `.md`/`.markdown` files are parsed by
  extracting column-0 ```` ```idef0 ```` fences; ALL fences in a file
  concatenate into one virtual source (a fence can continue
  mid-model). Prose is ignored by the tool. Diagnostics report the
  md file's own line numbers. Unclosed fence = warning. `.md` and
  plain files mix freely in one invocation.

## 4. Toolchain (current, authoritative)

`idef0` (Python 3, stdlib only) with subcommands `lint`, `dump`,
`links`, `text`, `html`, `svg NODEID`, `fmt [--auto|--number]
[--write]`; wrappers `idef0lint idef2text idef2html idef2svg
idef0fmt`; `idef0-mode.el` (Emacs: fontification incl. `#`/`##`
faces, `# ` comment-start, registers `("idef0" . idef0-mode)` in
`markdown-code-lang-modes`); `README.md`.

Behaviors that must not change:

- Diagnostics: GNU `file:line: severity: msg` (lint prints to stdout;
  fmt/text/html/svg print diagnostics to **stderr**).
- Lint summary always printed:
  `{N} file(s): {E} error(s), {W} warning(s), {M} model(s),
  {A} activities, {L} link(s)`.
- Broken link error: `broken link: cannot resolve '<full path>'` with
  ` (closest: 'NAME')` via difflib cutoff 0.75.
- Typo-split fuzzy warnings at cutoff 0.86, both directions, only
  when a flow has no exact counterpart AND its port carries no link.
- Duplicate same-name `o` ports on one activity: error
  `'Act' has no unique port for flow 'X'; add the port or use o1/i1
  form`.
- fmt refuses to rewrite files with errors; validates structure only
  (not links) so single-file fmt works mid-project; round-trips
  comments/docs/prose verbatim; re-emits trailing comments two
  spaces after the element.
- links table: `f"{src:<14} {dst:<14} {name}"`; renamed flows = two
  rows. >9 boxes per plate = error; no other size constraint.
- Plate ids: top plate = letter+`0`; pages `p.N` with index `p.1`.
- HTML (`idef2html`): inline SVG plates; `##` docs render as
  tooltips (hover on hover-capable devices, tap-to-pin on touch —
  gated by `matchMedia('(hover:hover)')`); decomposed boxes are
  `<a href="#plate-ID">` drill-downs; sticky per-plate nav
  (index/up/back/fwd); p.1 tables link into plates; hash-anchor
  jumps give browser-history backtracking; docs also shown in a
  collapsible "notes" panel on the node's own plate. `idef2svg`
  emits plain-text `<title>` tooltips. Internal-flow elbows are
  filleted (7px quarter-rounds, auto-shrinking, both flow
  directions); box corners and straight stubs stay sharp. On-plate
  outputs feeding a sibling's control enter that box from the TOP
  edge (IDEF0 convention; drop positions shared with external
  control drops via per-box control lists), incl. feedback controls
  routed against the staircase. Each plate is a pan/zoom viewport
  (ctrl+scroll / pinch / drag; double-tap or nav reset restores).

## 5. DroneCorp (the working example)

Canonical source: `dronecorp/dronecorp.md` — ONE literate markdown
document, ten models in fences with prose narrative. Verified state:
`1 file(s): 0 errors, 0 warnings, 10 models, 264 activities,
52 links`, canonical `fmt --number` form. Companions:
`dronecorp/plates.html`, `dronecorp/INTERFACES` (the 52-row table).
`quadfactory/*.txt` is the minimal plain-format sample (5 models,
0/0). Models: E Executive & Strategy, R R&D, P Production, T Testing,
Q Quality Assurance, C Contracting & Sales, L Logistics & Shipping,
S Customer Support & Feedback, F Finance, H Human Resources. Each has
a six-level spine. Five renamed boundary flows: Test Rejects→Rework
Units (T→P), Field Complaint Reports→Field Complaints (S→Q), Line
Nonconformance Reports→Line Nonconformances (P→Q), Staffed Production
Workforce→Production Crew (H→P), Certified Test Pilots→Test Pilots
(H→T). Budget hub: `E23.o1` → nine `<` consumers. The F model
(Finance) already models budget stewardship, P2P/O2C/payroll, close &
report — the ledger feature should be checked for coherence against
it.

## 6. Suggested first moves for the new chat

1. Ask JC to attach the kit (or confirm rebuild-from-spec).
2. Run the verification gates: lint dronecorp.md (expect the exact
   summary above), diff `links` output against INTERFACES, fmt
   round-trip byte-identical.
3. Present a minimal ledger DSL strawman (journal line grammar,
   account = node id rule, period syntax, budget vs actual posting
   forms) as short options for JC to choose between — one decision
   per question, phone-friendly.
4. Build incrementally with lint gates; extend `plates.html` last.
