# idef0-kit — plain-text IDEF0 modeling

A tiny toolchain for authoring IDEF0 model sets as plain text: a DSL,
a validator/renderer, and an Emacs mode. No dependencies beyond Python 3.

(Rebuilt 2026-07-22 to the documented v1 specification after the original
build environment was lost; verified against the quadfactory sample and
the original diagnostic catalogue.)

## Layout

    idef0            core tool: lint | text | html | svg | dump | links | fmt
    idef0lint, idef2text, idef2html, idef2svg, idef0fmt
                     Unix-style wrappers for the same commands
    idef0-mode.el    Emacs major mode
    quadfactory/     sample project: 5 cooperating models (D F A T S)
    dronecorp/       racing drone company: 10 models (E R P T Q C L S F H)

## The language in one screen

    ; comment. First line "; -*- mode: idef0 -*-" makes .txt open in idef0-mode.
    tS Shipping                    ; t = model, S = mnemonic model letter
      a# Package Quad              ; a = activity; # = derive my number
        i# Tested Quad < T|Flight Test|Tested Quad   ; cross-model link
        c# Packaging Spec          ; i/c/o/m = ICOM port, wired by flow name
        o# Boxed Unit
      a# Dispatch
        i# Boxed Unit              ; same flow name => connected
        o# Shipped Quad

Indentation is hierarchy. Position derives all numbering (S1, S12, S12.o1).
`idef0 fmt --number` freezes numbers into the file; `--auto` strips back to #.
Links: `<` comes-from on i/c/m ports, `>` goes-to on o ports, path segments
joined by `|`, names or numbers, resolved relative-first. Anything not
produced/consumed inside a model is a boundary flow, derived automatically.
Links into a model letter not present in the loaded file set are warnings,
so single-file lint/fmt still work mid-project.

## Daily use (Emacs)

    C-c C-c  lint file        C-c C-p  lint project (directory)
    C-c C-v  page through rendered plates
    C-c C-l  interface table  C-c C-d  numbered tree
    C-c C-n  freeze numbers   C-c C-u  back to auto (#)
    C-c C-f  jump to link target (cross-file)
    M-RET    new sibling      TAB      fold / indent

## CI

    idef0 lint *.txt      # exit 1 on errors; file:line: severity: format

## Exports

    idef2text *.txt > plates.txt        # Unicode, form-feed paginated
    idef2html *.txt > plates.html       # SVG plates, print = one page each
    idef2svg  E22 *.txt > plate-E22.svg # standalone vector plate

## Vocabulary

project (directory) > model (t line, letter) > plate/diagram (S1) >
box (S12) > port (S12.o1) > flow (named arrow). Cross-model links,
declared from both sides, form the project's interface table (`idef0 links`).

## Doc comments and interactive plates (added 2026-07-24)

Comments come in Python/bash pound style (preferred) with semicolons
accepted as legacy: `#` starts a full-line comment, and a
whitespace-preceded `#` starts a trailing comment on an element line
(the auto-number suffix `a#`/`i#` never conflicts -- it is glued to
its tag with no space before it). One reservation follows: a name can
no longer contain a space-then-`#` sequence.

A line beginning with `##` (or legacy `;;`) is a **doc comment**
attached to the element line directly above it (`t`, `a`, or any
`i c o m` port line); a trailing `##` on an element line attaches the
doc to *that* element inline. Consecutive doc lines are joined with
spaces. Inside the text:

- literal `\n` breaks the comment into paragraphs; a bare `;;` line
  does the same
- inline markdown is rendered in the HTML plates: `**bold**`,
  `*italic*`, `` `code` ``, `[label](url)`

`fmt` round-trips full-line comments verbatim and re-emits trailing
comments two spaces after the element (link path included). A doc
comment with no element above it is a lint warning -- model docs go
*after* the `t` line, not before it.

`idef2html` renders doc comments as hover tooltips on the annotated
box names, flow labels, mechanism names, and title-block titles
(dotted-underlined). On touch screens tap to pin a tooltip, tap
elsewhere to dismiss. Plates whose node carries a doc comment also get
a collapsible "notes" panel. `idef2svg` emits the same docs as native
plain-text `<title>` tooltips.

Navigation in `idef2html`: every decomposed box is a click-through
link to its child plate, each plate has a sticky bar with index / up /
back / fwd / reset, and the p.1 node index and interface table link to plates.
Jumps are `#` anchors, so the browser's own history gives full
backtracking.

Each plate is also its own pan-and-zoom viewport: ctrl+scroll (or a
trackpad pinch) zooms at the pointer, dragging pans, and on touch a
two-finger pinch zooms while one-finger scrolling stays with the
page. Double-click, double-tap, or the nav's reset link restores 1:1.
Tooltips, tap-to-pin, and drill-down links keep working while zoomed.

## Literate markdown projects (added 2026-07-24)

Files ending `.md`/`.markdown` are read as **literate sources**: only
```` ```idef0 ```` fenced blocks (fence at column 0) are parsed, and
all fences in a file concatenate into one virtual source, so prose can
interleave with any part of a model — a later fence continues where
the previous one left off. Everything outside fences is ignored by the
tool and rendered by any markdown viewer; inside fences `#` is an
idef0 comment, outside it is a markdown heading, and the two never
meet. Diagnostics report the markdown file's own line numbers
(Emacs `next-error` jumps straight into the fence), `fmt` rewrites
only fenced element lines and passes prose through verbatim, and an
unclosed fence is a lint warning. Plain `.txt`/`.idef0` files and
`.md` files can be mixed freely in one invocation.

For native fence fontification in Emacs, `idef0-mode.el` registers
itself with `markdown-mode`'s `markdown-code-lang-modes` (enable
`markdown-fontify-code-blocks-natively`).

`dronecorp/dronecorp.md` is the canonical example: the whole
ten-model company as one literate document.

## Variant groups — FP mods, item 1 (added 2026-07-27)

An output port may carry a glued variant marker between tag and
suffix: `o/# Parsed Value` / `o/# Parse Failure`. All same-key `o/`
ports on one activity form an **exclusive variant group** -- exactly
one fires per invocation (a sum type / case analysis). Lettered
groups `o/a#`, `o/b#` allow the rare box returning several
independent sums; the bare `/` is the default group. Exclusivity is
a property of the output bundle, not of any incoming control -- a
pure pattern-match box has variants and no `c` port.

Lint: a group with one member is a warning; `/` on `i`/`c`/`m` (or
`t`/`a`) is an error. `fmt` round-trips markers; `dump` shows `O/`;
plates draw a bracket binding the group's arrows (`)->` in text
renders). See `examples/fp-variants.md` for a railway-oriented
pipeline.

## Mechanism kind — FP mods, item 2 (added 2026-07-27)

`m/` marks a mechanism as **module means** (library, typeclass
dictionary, pure interpreter); bare `m` stays **worldly** (crew,
machine, database, clock). The polarity is sound by default: purity
is the explicit claim, so every pre-existing model is already
correctly marked. Letters after `m/` are reserved (error).

Derived, not asserted: an activity is *effect-clean* iff every
mechanism in its subtree is `m/`. `dump` appends `[pure]`;
`idef2html` tints effect-clean boxes. The purity *assertion* (`a/`
-- lint error on drift) is the planned next step.

## FP mods 3-6 + purity assertion (added 2026-07-27; Python-first)

- `a/` **purity assertion**: lint error if the subtree uses any
  worldly mechanism -- the derived boundary becomes a checked claim.
- **Flow types**: `o# Parsed Config : Config` -- optional
  ` : Type` after a port name; same-named flows with different
  declared types are a lint error. `: @NODE` is an activity-valued
  flow; the node must exist.
- **Recursion back-refs**: `a# Retry Loop > Ancestor` -- a childless
  box referencing an ancestor (id or name); renders ↻+target in
  the id corner, drills to the ancestor's plate; no new account codes.
- **Multiplicity**: `i*#` / `o*#` / `c*#` marks a many-flow.

These and the ledger below are Python-only pending the Rust port
re-sync (workflow: Python first, port after; `tests/golden.sh`
guards the pre-FP frozen surface). Fixture: `tests/fp/`.

## Ledger core (added 2026-07-27; Python-first)

`idef0 ledger FILE... [--forecast]` reads ```` ```ledger ```` fences
in the same literate documents: `budget YYYY-Www` blocks and
`YYYY-Www Description` journal entries, indented `ACCOUNT AMOUNT`
postings. Accounts are node ids (`P321:materials`); periods are the
odd ISO week of each biweekly pair; every block must balance to zero.
Lint: unbalanced blocks, unknown accounts, malformed/even periods.
Report: budget / actual / variance rolled up the decomposition tree
(the node-id tree IS the chart of accounts); `--forecast` adds a
run-rate projection. See `dronecorp/books.md`.
