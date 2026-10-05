# DESIGN.md — idef0-kit design notes

Companion to HANDOFF.md (mission, DSL spec, frozen behaviors) and
README.md (user-facing manual). This file records the *why* behind
design decisions, especially rendering rules that were arrived at by
iteration and would be easy to regress.

## First principles

- **Everything derivable is derived.** Numbering from list position,
  layout from the model tree, box height from port counts, account
  roll-ups (future ledger) from node-id prefixes. Nothing is stored
  that can be computed; the source file is the single spec.
- **One file per concern.** `idef0` (Python, stdlib only) is the
  canonical tool; `idef0.rs` (Rust, zero crates) is a byte-identical
  port; `idef0-mode.el` is the editor; `dronecorp/dronecorp.md` is
  the whole company in one literate document.
- **Plain text, GNU diagnostics, Unix wrappers, Emacs-first.**

## Plate geometry (SVG + text renderers)

Grid: CW=9, CH=18, PAD=20 px; staircase layout, hgap 12 cells,
vgap 4 rows. Box width 20–26 cells from longest name; names word-wrap
(3 lines SVG, 2 text). **Box height is per-plate dynamic**:
`bh = max(5, 2 + max same-side port count)` so port stacks always fit
(C3's five outputs, F2's four inputs forced this).

**Port distribution**: declaration order, top-down, but the stack is
*centered on the edge*: `py = boxtop + h/2 + (2k − n + 1)·CH/2`. A
single arrow touches the exact middle of the side; a full stack
reproduces the classic row positions. Inputs left, outputs right,
controls top, mechanisms share one centered stem below.

**Internal o→i flows**: filleted H-V-H elbows (7px quarter-rounds,
auto-shrinking) from the producer's true port row to the consumer's
true port row.

**Internal o→c flows** (governance chains, e.g. E1→E2→E3): enter the
consumer's TOP edge, per IDEF0 convention. Route: fork off the output
line 20+6k px after the port — *before* the 40px external stub
arrowhead, so a flow that both leaves the plate and steers a sibling
reads as one line with a fork — then a lane 22+12k px above the
consumer, then down into a drop slot with ≥15px of straight vertical
before the arrowhead.

**Planar slot ordering.** Drop slots across a box top are ordered by
where their source enters the routing channel: feed-forward internals
first (and within one producer, the LOWER output port takes the
LEFTER slot — the identity pairing provably forces a crossing by the
boundary-chord argument), then external top-margin drops, then
feedback controls (whose right-hand lanes then cross nothing).
Remaining crossings are exactly two forced classes: an upper output's
fork trunk through lower outputs' stubs, and skip-level lanes crossed
by an intermediate box's own flows. Fillets + label halos
(paint-order stroke, plate background color) keep crossings legible.

**Labels**: flow labels font-size 9 with halo; internal-control drop
labels are end-anchored 4px left of their own drop, each in a 12px
band the stagger arithmetic keeps clear. External control labels sit
at the top-margin bus row, x = leftmost drop + 5.

**Route tags**: boundary stubs carry `[> M:NODE.pN]` / `[< …]` — the
plate-local rendering of the interface table. In `idef2html` these
are drill-down hyperlinks to the plate where the target port lives
(same lookup as the p.1 interface table); plain text in standalone
`idef2svg`.

## Interaction model (idef2html)

Each plate is a pan/zoom viewport: ctrl+scroll (trackpad pinch) zooms
at the pointer, MIDDLE-drag pans (left button is reserved for
hyperlinks, drill-downs, and tooltip pinning), two-finger pinch
zooms/pans on touch while one-finger scrolling stays with the page
(touch-action: pan-x pan-y), double-click/double-tap or the nav's
⤢ reset link restores 1:1. Tooltips: hover on hover-capable devices,
tap-to-pin on touch (matchMedia gate). All state is per-plate JS
closures; CSS transform on inline SVG keeps text crisp at any zoom.

## The Rust port

`idef0.rs`: single file, zero crates, ~2000 lines. Build:
`rustc -O idef0.rs -o idef0-rs`. Byte-identical to the Python on
stdout, stderr, and exit codes — enforced by `tests/golden.sh`
(25 checks: every command × dronecorp.md, the 5-file quadfactory
project, and tests/fixtures/, including error paths and fmt modes).
The harness rebuilds from source first and aborts loudly on compile
failure, so a stale binary can never pass.

Porting notes: hand-rolled parser replicating the Python regex's
backtracking; a faithful difflib.SequenceMatcher port (queue-based
matching blocks, get_close_matches tie-break by (ratio, string));
Python float-format mimics (str(float) → "731.0", :g → "616"/"610.5")
at the exact SVG call sites; insertion-ordered maps and hand-rolled
ensure_ascii JSON for the DOCS payload.

**Workflow rule: Python first.** New features (the ledger included)
land in the Python tool; the port re-syncs afterward with the golden
harness as the acceptance test. Never let the port block or shape
Python work.

## Verification discipline

- `idef0 lint` to 0 errors / 0 warnings after every change; show the
  summary line. DroneCorp gate:
  `1 file(s): 0 error(s), 0 warning(s), 10 model(s), 264 activities, 52 link(s)`.
- `idef0 links` output diffs clean against dronecorp/INTERFACES.
- `fmt` round-trips byte-identical on canonical sources.
- tests/golden.sh green before claiming Rust parity — and claims of
  parity are made only from a harness run whose output was actually
  displayed, never inferred from a chained `&&` (this rule exists
  because it was once violated).
- Geometry changes are verified numerically from emitted SVG (port
  row positions, vertical approach lengths, segment-intersection
  counts), not by eyeball alone.

## examples/

`examples/usecase-atm.md` and `examples/sysml-views.md` map UML/SysML
v2 artifact kinds onto IDEF0 plates — the demonstration that one
notation plus decomposition covers the diagram zoo. Each is a
standalone literate document, lint-clean, exercising the full
rendering feature set (control entries, feedback transitions, forks,
cross-model route links).

## FP visualization mods (in progress)

Item 1 of the FP handoff is implemented: **variant groups** (`o/`,
`o/a`..`o/z` glued between tag and suffix -- the one grammar slot
names cannot reach). Bundle-level exclusivity, singleton-group
warning, non-output marker error, fmt/dump support, bracket render.
Item 2 is implemented: **mechanism kind** (`m/` = module means,
bare = worldly; sound-by-default polarity). Purity is derived
(`effect_clean`: all subtree mechanisms are modules), surfaced in
dump (`[pure]`) and as a tint in HTML plates. Next micro-decision:
`a/` as the purity assertion so drift becomes a lint error.
Items 3-6 (flow types, recursion back-refs,
multiplicity, activity-valued flows) layer on this; see the FP
handoff for priorities and the out-of-scope list (no polymorphism,
no composition algebra -- that is string-diagram territory).

## The ledger mission (next feature)

See HANDOFF.md §2. The structural insight: IDEF0 node ids ARE
hierarchical account codes; plate roll-ups are ledger roll-ups; the
modeled budget fan-out (E23.o1 → nine consumers) makes misrouted
postings lintable. Design decisions locked so far: ledger fences
anywhere in any document; block ledger-cli-style journal grammar;
account names = node ids with free suffixes; ISO-week-pair periods;
budgets authored as double-entry blocks; bare-number amounts.
Decision 7 resolved by delegation: extend `idef0` itself (one tool,
shared parser). Ledger core implemented Python-first: fence scan,
balance/account/period lint, variance-tree report, --forecast
run-rate. Queued: budget-flow-violation lint (E23.o1 hub check),
per-plate HTML cost panels, phased forecast, Rust re-sync of all
FP+ledger features (golden harness to be extended when re-synced). HTML output with no
ledger entries must remain byte-identical to pre-ledger output.
