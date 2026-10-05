# tools/sysml -- SysML v2 tooling in core Perl

Two command-line tools for a SysML v2 textual model kept in Git and edited in Vim, on a laptop
with nothing but Git for Windows (its Perl 5): no Java, no Python, no `make`, no CPAN.

- **`sysml.pl`** -- a syntax checker generated at start-up from the official KerML and SysML v2
  grammars (the vendored release below). Exact to the published grammar plus a short, documented
  errata list; it parses all 404 files of the standard library and the official examples.
- **`model.pl`** -- the project tool: lint, the 2..9 outline rule, level tags, noun and verb trees,
  an IDEF0 model set of the verb tree, a requirements traceability matrix, a Vim tags file,
  scaffolding, renames, a git pre-commit hook, and an optional full compile with the SysML v2 Pilot
  engine when Java happens to be available.
- **`views/`** -- standalone drawers and checks: part tree, trace, interconnection by trust zone and
  packages by marking as SVG, drawing plates, a two-version diff, the threat checks and the validate
  gate (`views/README.txt`); `model.pl draw|plates|diff|threats|gate` run them on the project.
- **`v1v2.pl`, `doors2v2.pl`** -- fallback converters for exports the main path (`bin/xmi2sysml.pl`,
  `bin/reqif2sysml.pl`) cannot read: older Cameo XMI or `.mdzip`, DOORS CSV in UTF-16 or Windows-1252.

Both run from any directory. `examples/halberd/` is a complete example model that exercises every
command; its `README.md` shows each one with its output.

## sysml.pl

    perl tools/sysml/sysml.pl check FILE...       syntax-check files: file:line:col: error: ...; exit 1 on errors
    perl tools/sysml/sysml.pl corpus [DIR...]     every .sysml/.kerml under DIRs (default: the vendored library + examples)
    perl tools/sysml/sysml.pl tokens FILE         the token stream (debugging)
    perl tools/sysml/sysml.pl grammar             rules, keywords and symbols of both grammars
    perl tools/sysml/sysml.pl crosscheck [N] [SEED]   differential test against the Pilot engine (needs Java)

A diagnostic names the furthest token the grammar could not accept and what it expected there:

    model/firecontrol/KillChain.sysml:15:62: error: unexpected '}'; expected '!=', '!==', '#', '%', '&', '(', '*', '**', ...

`corpus` takes about 35-40 s on either Perl for the 404 vendored files.

## model.pl

    perl tools/sysml/model.pl [--root DIR] COMMAND [options]

The project is the nearest directory upward from the current one that holds a `model/` folder, or
`--root DIR`. Every `*.sysml` under `model/` is the model; generated files go to `<root>/docs/` and
the tags file to `<root>/tags`. Diagnostics name files relative to the current directory, so Vim's
quickfix list (and `:make`) can open them.

| command | what it does |
|---|---|
| `lint [--no-grammar]` | SysML checks without Java: grammar-exact syntax (sysml.pl's parser), keywords used as names, unresolved types and supertypes, imports of unknown packages, duplicate package members, bindings that silently refer to the child's own parameter. Prints `lint: N file(s), E error(s), W warning(s)` and the machine line `elements=N errors=E warnings=W` (what `bin/status-metrics.pl` reads as its `lint_cmd`). Exit 1 on errors. |
| `check` | the 2..9 outline rule (children per part def / verb / package / enum / directory) and the `@L<n>` level tags against each part's depth in the noun tree. Exit 1 on any violation. |
| `stats` | size, element counts, nesting, noun and verb depth, then `check` |
| `nouns [--plain] [--ascii]` | the part tree from `noun_root` |
| `verbs [--plain] [--ascii]` | the function tree from `verb_root`, with each function's result |
| `docs` | regenerate `docs/Nouns.md`, `docs/Verbs.md`, `docs/idef0/` and `docs/Traceability.md` |
| `idef0` | regenerate `docs/idef0/` only: `<idef0_name>.md` (literate IDEF0), `plates.html`, `INTERFACES`, `svg/plate-*.svg`, built and linted with the kit's `tools/idef0/idef0.pl` |
| `trace [--strict]` | requirement -> satisfied by -> verified by, to `docs/Traceability.md`; lists what is not satisfied / not verified (`--strict`: exit 1 on gaps) |
| `tags` | a Vim tags file: Ctrl-] on any definition, usage, requirement name or DOORS id |
| `new part NAME --in PARENT [--usage u] [--doc TEXT]` | scaffold a part def (with the next level tag) and its usage in PARENT |
| `new verb NAME --in PARENT [--takes 'x:T,y:T'] [--returns T]` | scaffold a function of PARENT's kind (calc or action) and its usage, with bindings to fill in |
| `rename OLD NEW [--write] [--any]` | rename a definition everywhere (dry run unless `--write`) |
| `backlog [--agile=DIR] [idef0-backlog options]` | the IDEF0 set through the kit's `sim/idef0-backlog.pl`: a planning stand-up file on stdout (one team per top-level step, an epic per function, interface tasks for hand-offs) |
| `precommit` | lint + check + generated docs up to date (what the hook runs) |
| `install-hooks` | install the pre-commit hook (from the `pre-commit` template here) into the project's git repository |
| `validate` | full compile with the SysML v2 Pilot engine: needs Java and the Pilot jar (`SYSML_JAR`, `SYSML_HOME`, or a `*sysml*all.jar` in this folder); the library defaults to the vendored one. Without them it prints what is missing and exits 3. |
| `libnames DIR` | refresh `sysml-library-names.txt` (the standard-library names lint resolves offline) from a `sysml.library` folder |

### Model conventions model.pl relies on

- **Nouns** are `part def`s; children are `part name : Type;` usages (inherited ones count too).
  Each part def carries a level tag `@L<n>...;` (metadata defs the model declares, e.g.
  `@L3System;`) that must equal its first depth in the noun tree.
- **Verbs** are functions: a `calc def` with `return : T`, or an `action def` with exactly one
  `out result : T`. Children are `calc`/`action` usages; inputs are bound in the usage body
  (`action track : Track { in detections = detect.result; }`), parameters of the parent qualified
  (`Parent::x`). The IDEF0 set takes the root's input record (an `item def` whose fields are
  `item`/`attribute` usages) as the external flows.
- **Allocations** `allocate <alloc_prefix>.step.sub to context.part.path;` make IDEF0 mechanisms.
- **Requirements** are `requirement name { ... }` (or `requirement <'ID'> name ...`); the id is the
  short name, else the `doorsId = "..."` attribute, else the name. `satisfy name by part;` anywhere,
  and `verify name;` inside a `verification def` (its method from `@VerificationMethod { kind = ... }`).

### sysml.conf (in the project root)

`key = value` lines, `#` comments. All optional except the two roots.

| key | meaning | default |
|---|---|---|
| `noun_root` | the part def at the top of the noun tree | `EnterpriseDef` |
| `verb_root` | the calc/action def at the top of the verb tree | `Mission` |
| `title` | used in generated document titles | the project folder's name |
| `idef0_name` | `docs/idef0/<idef0_name>.md` | `KillChain` |
| `model_letter` | IDEF0 letter reserved for the verb root itself (never given to a step) | `K` |
| `steps` | `usage:Letter:Label, ...` -- IDEF0 model letter and title per top-level step | first free capital of the usage name; label from the name |
| `control_types` | flow types drawn as IDEF0 controls (orders, rules, authorizations) | none: every parameter is an input, except ones with a default value |
| `alloc_prefix` | the feature path that stands for the verb root in `allocate` statements | none: no mechanisms beyond the enterprise |
| `acronyms` | words kept whole when names are split (`QoS, ABC`); `spell = EOIR=EO/IR` respells | none |
| `level_tags` | the `@L<n>` names `new part` writes, level 1 first | `L1Enterprise, L2Segment, L3System, L4Subsystem, L5Assembly, L6Subassembly, L7Component, L8Part, L9Piece` |
| `need_prefix` | requirement ids that start with it are needs (trace status `need`, not a gap) | `N-` |

## Vim

`vim/ftdetect/sysml.vim`, `vim/syntax/sysml.vim`, `vim/ftplugin/sysml.vim` and
`vim/compiler/sysml.vim` (loaded through `vim/scrum.vim`'s runtimepath): colouring, 4-space indent,
folds, and from any `.sysml` buffer inside a project `:make lint`, `:make check`, `:make validate`
into the quickfix list, plus `\ml` lint, `\mk` check, `\mx` this file's syntax, `\mv` validate,
`\md` docs, `\mr` trace, `\mn` nouns, `\mb` verbs, `\mt` tags (`:SysLint`, `:SysCheck`, ...).
Outside a project `:make` checks the current file with `sysml.pl check`.

## Layout

    tools/sysml/
      sysml.pl, model.pl          the two tools
      lib/SysML/Grammar.pm        KEBNF grammar files -> a grammar value
      lib/SysML/Lexer.pm          text -> tokens (keywords and symbols from the grammar)
      lib/SysML/Parser.pm         a packrat recognizer compiled from the grammar, left recursion by seed growing
      lib/SysML/*-errata.kebnf    corrections to the published grammars, each with its evidence
      sysml-library-names.txt     standard-library names, for lint's offline type resolution
      pre-commit                  the hook template install-hooks fills in
      vendor/sysml-v2-release/    the SysML v2 release (EPL-2.0, see its LICENSE and NOTICE.md):
                                  bnf/ (the grammars), sysml.library/ (1.6 MB), examples/ (1.1 MB,
                                  the corpus and crosscheck test set)

The functional helpers come from the kit's `lib/Prelude.pm`. Tests: `perl tests/sysml.t`.
