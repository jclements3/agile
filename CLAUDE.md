# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A plain-text scrum "battle rhythm" kit for a solutions architect running several Scrum teams
under a two-week sprint tempo. Everything — backlog, sprints, stand-up notes, votes/estimates,
attendance, AI-assisted status summaries — is stored in a ledger-cli-style plain-text journal
edited in Vim, and compiled/reported by pure Core Perl (5.10+, no CPAN, no XS, runs on Git for
Windows' Perl — nothing to install, no network required except optionally for the AI backend).

The repo root *is* the kit — a standard `bin/lib/tests/docs` layout, nothing nested under a
`prelude/` wrapper. `claude.bat` launches Claude Code in WSL rooted at this directory. Prose
docs in this repo are HTML, not Markdown (`docs/README.html`, `docs/WORKFLOW.html`,
`docs/TEST-PLAN.html`) — the target environment is Windows 11 / MS Office, not a Markdown
renderer; `CLAUDE.md` itself stays Markdown only because Claude Code specifically looks for that
filename.

Read `docs/README.html` first for the command/workflow overview, and `docs/WORKFLOW.html` (the
"operating model") for the full picture: hierarchy of work (Tome < 2 years → Epic < 13 sprints
→ Task < 1 sprint, with Sprint as the 2-week timebox rather than a size), the two-week cadence
day-by-day, what each Scrum event feeds into the journal, the
metrics and their action thresholds, and the feedback loops. `docs/TEST-PLAN.html` is a manual
30-minute session for validating the one untested layer (Outlook COM) on a real Windows laptop.

## Commands

Run from the repo root:

    for t in tests/*.t; do perl $t | tail -1; done   # run every test suite, print each summary line
    perl tests/run.pl [-j N] [-v]                     # the same in parallel (~3x faster), one line per suite; -v prints failing suites in full
    perl tests/scrum.t                                # run a single suite (verbose TAP output)
    "/mnt/c/Program Files/Git/bin/bash.exe" -lc 'cd /c/Users/clementsj/projects/agile && for t in tests/*.t; do perl $t | tail -1; done'   # from WSL: the same suite under the TARGET Perl (Git for Windows, cygwin build) -- run before every commit that touches bin/ or lib/
    #   inside Git Bash, not by calling usr/bin/perl.exe from WSL: suites that shell out (perl, cp) need Git's PATH, and Git's Perl sees the repo as /c/..., not /mnt/c/...
    perl -Ilib tests/scrum.t                           # if lib isn't already resolved relative to tests/

There is no build step and no package manager — everything is `use lib` against `lib/`.

    perl bin/devsecops.pl [--quick]     # run the kit's own pipeline gates here (tests on every Perl found, syntax, secrets, marking, hygiene) -> ./devsecops.html, a DevSecOps-style status dashboard; exit 1 on a gap
    perl bin/release.pl [--tag vX]      # release/agile-<tag|sha>.zip (+ .sha256) from the committed tree, for the target laptop; refuses on a dirty tree
    perl agile.pl help [TOPIC | search WORDS | error "MSG" | errors]   # offline help from vim/doc/agile.txt + agile-errors.txt; --html / --md regenerate docs/HELP.html, docs/help/quickref.md; --check lists what the help is missing
    perl agile.pl practice [N | check N | reset N]                     # hands-on lessons in data/practice/lessonN (lib/Practice.pm)
    perl bin/daily.pl help [CMD]                                       # also scrum.pl / ledger.pl help [CMD]; works outside a project

Test suites map 1:1 to the libs: `tests/prelude.t`, `tests/ledger.t`, `tests/quad.t`,
`tests/scrum.t`, `tests/standup.t`, `tests/calendar.t`, `tests/chat.t`, `tests/answers.t`,
`tests/attendance.t`, `tests/quad.t`, `tests/roster.t`, `tests/cockpit.t`, `tests/drill.t`, `tests/metrics.t`, `tests/status_metrics.t`,
`tests/xmi2sysml.t`, `tests/reqif2sysml.t`, `tests/sysml.t`, `tests/sysml-views.t`, `tests/halberd.t`, `tests/memo.t`, `tests/help.t`, `tests/drills.t`. `tests/fake-ps.pl` is a fake `powershell.exe` stand-in used to test
`Calendar.pm`'s COM calls offline.

CLI entry points (`bin/`): `daily.pl` is the day-to-day driver; `scrum.pl`, `ledger.pl`,
`cal.pl`, `chat.pl` are lower-level single-purpose CLIs used directly for ad hoc queries. Useful
invocations while developing:

    perl bin/daily.pl status | sprint [N] | velocity | backlog [Team] | members [Team] | epics | roadmap | blocked
    perl bin/daily.pl lint [FILE|-] [--reply]        # check Y/T/B statuses in a pasted chat during the meeting; --reply = lines to paste back
    perl bin/daily.pl roster [add "Name" email Team "Role" "Org"]   # the people file (roster.txt: Name | email | Team | Role | Org); lists, checks against the journal
    perl bin/daily.pl invite [--dry]                 # recurring weekday townhall in Outlook/Teams with the roster as attendees (townhall_* keys in scrum.conf); marking gate on attendees
    perl bin/daily.pl propose [Team]                 # today's statuses drafted from yesterday's + the journal, one line per person to post; answers --assume records them for the silent
    perl bin/daily.pl quad [Team]                    # the weekly quad (Technical Priorities / Watch Items / 30-60-90 Milestones / Accomplishments) as text; report writes <date>-quad.html
    #   lint/propose --private -> reports/<date>-{lint,propose}.html: a Teams 1:1 deep link per person (message pre-filled); e-mails from meeting invitees + roster.txt
    perl bin/daily.pl drill [Team] [-n 12]           # the memory drill: recall the tree and the people as terse answers (ids, codes, initials); --sheet/--grade FILE = the Vim sheet (:SDrill), progress in drill.txt
    perl bin/daily.pl health [Team] | review [N] | rollup [YYYY-MM] | csv [TABLE]   # Metrics.pm: thresholds (exit 1 on red), sprint report, monthly roll-up, CSV for Excel (report writes all of them)
    perl bin/daily.pl --dry compile                  # show what compile would write without writing it
    perl bin/scrum.pl -f scrum.txt items committed <Team>
    perl bin/ledger.pl -f scrum.txt bal Sprint:42
    perl bin/docs2txt.pl grep -i ICD specs/*.pdf      # PDF/.docx/.doc/.odt as text via the converters Git for Windows ships (tools: which were found)

Project data (journal, stand-up files, reports) lives in `data/<project>/` — one directory per
project, each its own git repo created by `daily.pl init`, and git-ignored by this kit's repo (so
never commit journal data here). `data/demo` is the sample townhall project; `data/history` is the
two-year simulation from `sim/history-gen.pl`. `sim/` holds standalone planning/simulation tools
that are deliberately outside the tested `lib/`/`bin/`/`tests/` surface. `tools/idef0/` is the
vendored IDEF0 toolkit (core Perl) with the DroneCorp model (a notional racing-drone company, the demo) and
DroneCorp models; `sim/idef0-backlog.pl` turns an IDEF0
model into a planning stand-up file (model → tome+team, level-1 activity → epic, leaf → task,
cross-model link → interface task in the destination team) — that is how `data/demo` is built. `sim/rehearsal.pl` writes a realistic Teams-chat paste (mistakes seeded, answer key on stderr; people also say the
four-letter words -- "punting X", "X on hold", "passing X to Bravo" -- which `answers` turns into commented `punt`/`hold`/`pass`
lines) into the current project's standups/ for practising lint/answers without a team; `data/lab` is the practice project.
`sim/lab-run.pl` runs N unattended townhall days there (confirms the suggested done and four-letter-word lines, runs the quad daily,
reports findings); `sim/fuzz-chat.pl` property-tests the parsers, including that the words are only ever suggested, never applied;
`sim/drill-sim.pl` stress-tests the memory drill (property checks over real and hostile journals, then a simulated learner over weeks while the journal changes);
`sim/history-gen.pl` seeds punts, redos and sync pairs into the two-year history and HISTORY.html shows the punt rate by half-year. `sim/training.pl` is
the training replay: it wipes and rebuilds `data/demo` (guarded to that name) by really running
one sprint of `daily.pl` and `git` commands, and writes `docs/TRAINING.html` — regenerate that
file with `perl sim/training.pl --fast` after changing any command it shows.

`assets/logo.svg` (optional, not shipped) is inlined as the page logo when present;
`Scrum::logo_svg()` inlines it into the cockpit header and the report topbars so pages stay self-contained.

`:STown` in `vim/scrum.vim` is the keyboard-only meeting layout (chat buffer | lint table | replies; `\sp` paste+lint,
`\sy` replies to clipboard, `:SSend Name` opens the 1:1) -- the preferred form for the architect; `docs/ERGONOMICS.html`
has the keystroke/mouse analysis. Team members accept a proposed status with `+1` (`Answers::is_ack`, proposals persisted
by `daily.pl propose` in `standups/<date>-proposals.txt`); read-backs stop after `readback_clean_days` clean days.
`bin/townhall.tcl` is the meeting console (Tcl/Tk as shipped with Git for Windows: `wish bin/townhall.tcl PROJECT`):
a paste box that saves and lints the chat on every paste, replies, roster, and buttons that run the daily.pl
commands; it draws only, all logic stays in daily.pl. `agile.pl --today YYYY-MM-DD` sets the cockpit's date
(replays, simulations).

Flags (`Answers::flags`): a person's own queued task is never a "not in sprint" flag; "same plan N days" is info at 2,
amber from 3, red at max(3, task points); `Answers::fold_flags` groups INFO by kind for the mail/report. The cockpit's
People tab reads `roster.txt` (passed as `roster =>` by agile.pl/daily.pl) with today's answer and a clean-day streak.

`agile.pl` at the repo root is the app entry point: `perl agile.pl [PROJECT]` runs `daily.pl report`
for the project (default `data/demo`) and writes `./dashboard.html`, the cockpit (`lib/Cockpit.pm`:
a JSON snapshot embedded in one self-contained page with vanilla-JS views — daily, weekly, sprint,
monthly/semester/annual, backlog tree, roadmap, IDEF0 plates). `perl agile.pl serve` optionally
serves it on 127.0.0.1:8090, rebuilt on every load. The cockpit is the only HTML that uses
JavaScript; the reports under `reports/` stay no-JS because they are printed and mailed.

`daily.pl` locates `scrum.conf` by searching upward from the current directory, so commands work
from any subdirectory of a project created with `daily.pl init`. `calendar = mock` +
`calendar_fixture = <file.json>` in `scrum.conf` runs the whole calendar-dependent flow offline
against a JSON fixture (see `examples/cal-fixture.json`) instead of hitting real Outlook.

**Status metrics A-Z (separate tool, not the scrum journal):** `bin/status-metrics.pl init|collect|report` +
`lib/StatusMetrics.pm` collect the 26 status metrics of `docs/STATUS-METRICS.html` from a SysML v2 text model repo (git) and
its exports, and write `status-weekly.md` / `status-daily.csv` / `dashboard.json`. A core-Perl port of a Python kit
(`collect.py`): outputs must stay byte-identical to it, which is why it has its own Python-compatible JSON codec (ordered
keys, `json.dumps` spacing; `StatusMetrics::Str` keeps number-looking strings quoted) rather than JSON::PP.
`sim/status-metrics-sim.pl OUTDIR` builds the 12-week Halberd example as a real repo (its tools `sim/status-metrics/lint.pl`
and `gen_docs.pl` are copied into the simulated repo); `tests/status_metrics.t` runs sim -> collect -> report and checks
against Appendix C/D of the doc and the Python goldens in `tests/status-metrics/` (kept `-text` in .gitattributes: the CSV is CRLF).
Not to be confused with `lib/Metrics.pm` (the scrum journal's thresholds). `docs/STATUS-METRICS-QRG.pdf` is the one-sheet (duplex Letter)
quick reference, generated by `perl sim/status-metrics-qrg.pl --pdf` from the doc's Markdown and the dashboard's targets (it dies if it outgrows 2 pages).

**Model port, SysML v1 / DOORS -> SysML v2 text (separate tools):** `bin/xmi2sysml.pl` (`lib/Xmi.pm`) converts a Cameo/MagicDraw XMI
export into one `.sysml` file per top-level package; `bin/reqif2sysml.pl` (`lib/Reqif.pm`) converts DOORS ReqIF (.reqif/.reqifz) or
CSV into requirements with `doorsId`, and `--model DIR` reports metrics C/F/G/I against existing v2 text. Both share
`lib/XmlLite.pm` (a core-Perl streaming XML reader; XML::Parser is not core) and `lib/SysmlText.pm` (names, requirement shapes,
structural self-check); `--check` also runs `tools/sysml/sysml.pl check`. Unmapped elements are never dropped: each becomes a
`// TODO uml:<type> (xmi:id ...)` line and is listed by `--report`. The default `--req-style usage` writes the one-line requirement
form `bin/status-metrics.pl` counts (`def` writes `requirement def` blocks). Goldens in `tests/fixtures/{xmi2sysml,reqif2sysml}/expected/`
(regenerate with `REGEN=1 perl tests/xmi2sysml.t`). Day-to-day guide: `docs/SYSML-PORT.html`; one-sheet card `docs/SYSML-PORT-QRG.pdf` (`perl sim/sysml-port-qrg.pl --pdf`; its SysML v2 sample is grammar-checked on every build).

**SysML v2 tools:** `tools/sysml/sysml.pl check FILE...|corpus|grammar|tokens|crosscheck` is a syntax checker built at start-up from
the vendored official KerML/SysML v2 grammars (`tools/sysml/vendor/sysml-v2-release/`, EPL-2.0, plus `lib/SysML/*-errata.kebnf`);
`tools/sysml/model.pl [--root DIR] lint|check|stats|nouns|verbs|docs|idef0|trace|tags|new|rename|backlog|precommit|install-hooks|validate`
is the project tool (root = nearest dir upward holding `model/`, configured by `<root>/sysml.conf`; `idef0` calls
`tools/idef0/idef0.pl`, `backlog` calls `sim/idef0-backlog.pl`; `lint` ends with the `elements=N errors=E warnings=W` line
status-metrics.pl reads as lint_cmd; `validate` needs Java + the Pilot jar and exits 3 without). Both use `lib/Prelude.pm`.
Vim: `vim/{ftdetect,syntax,ftplugin,compiler}/sysml.vim`.

**SysML views toolkit (`tools/sysml/views/`, standalone core-Perl scripts, each runnable on its own):** `sysml-{tree,trace,ibd,pkg}-svg.pl`
(part tree; trace with S/V status, `--mono` for print; interconnection by SecMeta trust zone with the SEC-1 boundary check; packages with
@Marking and the no-write-down / leakage / cycle checks), `sysml-plates.pl` (ISO title-block plates), `sysml-diff.pl` (two versions or
`--git A..B`: colored views + a GNU change list), `sysml-threats.pl` (STRIDE + CAPEC on every threat, mitigation closure),
`sysml-check.pl` (the gate: the binder scripts in `views/binder/`, then markings, zones, threats -> PASS|FAIL). `model.pl draw
tree|trace|ibd|pkg | plates | diff | threats | gate` wrap them for the project's `model/` and pass options through (a `--root` after
those commands is the tool's). `views/library/{SecMeta,DrawingMeta}.sysml` are the vocabularies they read. Two extensions bind them to
the status-metrics line forms: ibd reads `interface x { end ::> a; end ::> b; attribute fromZone/toZone/secReq = "..."; }` (secReq
names the covering requirement; mismatched zone attributes warn) and threats reads `metadata t : Threat { asset; mitigation; stride;
capec; }` (mitigation must match the requirement's `@Mitigates`). Golden harness: `bash tools/sysml/views/tests/run.sh` (`--bless`
after a reviewed change; it also covers the fallback converters `tools/sysml/v1v2.pl` -- older Cameo XMI / .mdzip -- and
`tools/sysml/doors2v2.pl` -- DOORS CSV in UTF-16/cp1252, information objects; the main path stays xmi2sysml/reqif2sysml).
`tests/sysml-views.t` runs the harness (skips without bash) and every wrapper on Halberd; `sim/halberd-views.pl` redraws
`docs/img/halberd-{tree,trace,ibd,pkg}.svg` (deterministic, checked by the test) after a model change. `bin/sysml-view.tcl` (wish, as shipped
with Git for Windows) is a live viewer of those drawings beside Vim: `tools/sysml/views/svg2tk.pl` turns a drawer's SVG into canvas
primitives (Tk 8.6 has no SVG), it redraws on save, and talks to Vim through `~/.sysml-view/{focus,jump}` (`\mf` / `\mo`, `\mW` starts
it); `--export-ps FILE` draws once headless (tests use it under xvfb-run when present).

**Halberd, the running example (notional; nothing in it is real):** one fictional air and missile defense program, seven
organizations (G E V B T M L), used everywhere: `tools/idef0/examples/halberd/halberd.md` (the IDEF0 program model),
`examples/halberd/` (the SysML v2 model, segment folders = the seven organizations, with SecMeta markings -- U, CUI on the two verification
packages as notional labels -- trust zones and STRIDE/CAPEC threats, and planted gaps: 3 orphan and 4 unverified
requirements, 1 uncovered zone crossing, 2 open threats, exactly what `model.pl gate` fails on; its `docs/` is generated -- after a model change run
`perl tools/sysml/model.pl --root examples/halberd docs`, `tests/sysml.t` fails on stale docs), `docs/src/status-metrics.md`
(the 12-week port, Appendix C/D), and `sim/halberd-gen.pl`, which compiles that port into `data/halberd` through
Standup.pm/Scrum.pm (56 stand-ups, sprint totals checked against the doc) plus a notional FY27 `funding.ledger` and
percent-complete CSVs, and writes `docs/HALBERD.html` (`sim/halberd-render.pl`) and `docs/HALBERD.tex` (`sim/halberd-latex.pl`, black and white, with a "Model
views" section of the four docs/img SVGs, greyed and converted with rsvg-convert at build time, skipped if it is missing); `--pdf` also builds
`docs/HALBERD.pdf` with XeLaTeX + latexmk (not on the target laptop, so the PDF is committed). `tests/halberd.t` checks it and that the
committed page is current: after changing either script, rerun `perl sim/halberd-gen.pl`. Halberd must stay generic: no
real program names, no content from any private model.

**Funding and earned value (lib/Ledger.pm):** budgets can be dated (`~ Monthly from DATE to DATE`, prorated by day at the
edges; undated ones behave as before); `bin/ledger.pl` has `-M/--monthly` for bal/reg/budget, `evm` (BCWS/BCWP/ACWP, CV, SV,
CPI, SPI, EAC, VAC from dated budgets + `--complete ACCT=PCT` / `--complete-file`), and `forecast` (balance, average monthly burn
over `--months N`, run-out date); `--now DATE` sets the status date. Book funds under `Assets:` so the funding side of a budget
entry is not a budget row. `scrum.conf` keys `funding = FILE` and `complete = GLOB` add the cockpit's Funding tab
(`Cockpit::funding_snapshot`). Negative amounts print `$-1.00`, as ledger-cli does (tests rely on it).

**Help (one source, four outputs):** `vim/doc/agile.txt` and `vim/doc/agile-errors.txt` (Vim help format) are the only source.
`lib/Help.pm` renders them for `:help agile` (`vim/scrum.vim` runs :helptags; `vim/doc/tags` is git-ignored), `agile.pl help`,
`daily.pl|scrum.pl|ledger.pl help`, `docs/HELP.html` and `docs/help/quickref.md` (both generated and committed: regenerate with
`perl agile.pl help --html` / `--md`; the quickref is also a chapter of the user's binder, kept outside this repo).
`tests/help.t` derives what must be documented from the code (daily.pl's %cmds, drill.pl's %CMDS, Scrum::run and Ledger::run commands, :S/:Idef/:Sys/:Drill
commands, \s/\i/\m/\d keys, Standup verbs, scrum.conf keys) and requires every die/warn/STDERR/error-push message to match a `Pattern:`
in agile-errors.txt (or an `Internal:` line for bug-only invariants), so a new command or message needs its help entry in the same
change. `lib/Practice.pm` builds lesson sandboxes from daily.pl init, sim/halberd-gen.pl, sim/idef0-backlog.pl and sim/rehearsal.pl;
the lesson texts are the `*agile-practice-N*` sections.

**Coding drills (separate from the scrum kit):** `drills/drill.pl list|show|start|test|check|solution|log|stats|next|phased|help`
(`lib/Drills.pm`) is interview-style practice in core Perl for the binder's coding-drills chapter:
`drills/NN-SECTION/ID/{statement.txt,tests.pl,solution.pl,stub.pl}` (158 problems in 16 sections; `01-ladder` is the binder's
29-rung stdin/stdout ladder, the rest call a named sub or class), `drills/phased/{sensors,payments}/` (the four-phase drill)
and `drills/toolbelt.pl`. Learner state (ID.pl, attempts.txt, log.txt, trainer.txt) lives in the workspace (`~/drills-work`,
`$DRILLS_WORK` or `--dir`), never in the kit. Tests run in a child perl with a per-case alarm, so learner code cannot crash
drill.pl. `vim/autoload/drills.vim` + `vim/plugin/drills.vim` (sourced by `vim/scrum.vim`) are the `:DrillTrain` vanishing-cues
memory trainer (one level per section, cards from the solutions) and `:DrillOpen`/`:DrillTest`/`:DrillTestAll` (`\do \dt \da`).
Statements are the kit's own words; the `LeetCode:` line is a pointer only (tests/drills.t checks). Guide: `docs/DRILLS.html`.

**Other tools:** `tools/memo/md2memo.pl` (Markdown -> DoD-style memo as PDF/PS/text with portion and banner marking;
`tests/memo.t` pins the sample's output by SHA-256). `tools/idef0/` also carries the Halberd IDEF0 model, the parity suite
against the Python reference (`cd tools/idef0 && sh tests/parity.sh`, needs python3; html and `fmt --auto` are known,
counted divergences) and the Emacs mode; `tools/idef0-kit/` is the original Python/Rust kit with its design notes.
`docs/VIM-CHEATSHEET.html` is the one-page Vim reference for every mode; `vim/ftplugin/idef0.vim` is the Vim twin of the
Emacs IDEF0 mode. The user's 90-day binder is not in this repo (it was removed from the public history on 2026-10-05; a scrubbed copy may come back later as plain files, never as a subtree of the private binder repo). Secrets gates: `.secrets-allow` (devsecops.pl) and
`.gitleaks.toml` (CI) list the documented fake keys the binder's DevSecOps chapter uses as teaching examples -- exact values only.

## Architecture

**Everything is a ledger.** The scrum journal (`scrum.txt` + compiled stand-up files) is a
double-entry ledger-cli file (`Ledger.pm`). Task points are postings between accounts, and the
account a task's points currently sit in *is* its state:

    Backlog:Master → Backlog:<Team> → Sprint:N:<Team>:Committed → Done
                                                                 → Carryover → next sprint's Committed
                                                                 → Removed

Points are conserved and history is never rewritten — re-estimating posts a delta (`est ID N`),
it doesn't edit the past. `Ledger.pm` only knows about accounts/amounts/postings; it has no
scrum-specific knowledge (used standalone via `ledger.pl` too).

**Layering**, low to high:
- `lib/Prelude.pm` — a Haskell-flavored FP toolkit (fmap/foldl/partition/zip/Maybe/Either/
  streams/parsers) that every other module is built from. Read its header comment for the full
  convention table (tuples are arrayrefs, two-result functions return two arrayrefs, Perl-keyword
  clashes get a trailing underscore, etc.) before writing code against it.
- `lib/Ledger.pm` — generic plain-text double-entry engine over that journal format: parses
  amounts/postings, computes balances/registers, no domain knowledge.
- `lib/Scrum.pm` — the scrum domain on top of `Ledger.pm`: `load()` reads the journal into
  `$s = { j, file, items => {id => item}, teams, sprints, current, today }`, where each `item`
  carries its metadata (`prio`, `epic`, `owner`, ...), balance, and posting history. Sprint
  status, velocity, backlogs (master/team/member), the HTML dashboard, and e-mail/Outlook report
  text are all derived read-only from this structure — nothing is precomputed or cached
  separately. A new report is "a few lines of Prelude over `items($s)`" (per the README) rather
  than a new subsystem.
- `lib/Standup.pm` — parses/validates terse stand-up note files (the `done`/`new`/`est`/`block`/
  `cap`/`note` verb grammar — see the verb table in `docs/README.html`) and turns them into
  ledger-entry postings appended to the journal. A malformed stand-up file is rejected wholesale
  with every error listed, never partially applied.
- `lib/Calendar.pm` — drives classic Outlook (not "new Outlook", which lacks COM) through
  PowerShell COM via `-EncodedCommand` (no script files on disk). This is the only layer not
  unit-testable offline in the normal sense; `tests/calendar.t` covers everything above the COM
  call itself, and `tests/fake-ps.pl` substitutes for `powershell.exe`. `calendar_fixture` mocking (above)
  is the offline path for everything downstream of it.
- `lib/Chat.pm` — parses pasted Teams meeting chat for `#est`/`#vote` rounds into tallies
  (consensus/median with outliers, plurality/majority/tie) and emits `est ID N` / `note vote …`
  lines for the journal. Managed-tenant constraint: no chat API, so this is deliberately
  copy/paste-driven.
- `lib/Answers.pm` — parses the three-questions (Y/T/B) chat format per person, cross-references
  against the journal to raise deterministic flags (silent people, persistent blockers, repeated
  plans, unknown/off-sprint task ids, dubious "done" claims), and suggests `done`/`block`/
  `unblock`/`absent` lines for the architect to confirm rather than auto-apply.
- `lib/Ai.pm` — builds the prompt sent to an *approved* AI (paste-based by default, or an
  OpenAI-style endpoint via Git's bundled curl) from today's answers/metrics/flags/history, and
  parses the five fixed-section reply (HIGHLIGHTS/RISKS/STUCK/QUESTIONS FOR LEADS/PROGRESS) back
  into the status mail. Metrics themselves never come from the AI — always from the journal.
- `lib/Attendance.pm` — parses a downloaded Teams "Attendance report" CSV into join/leave/minutes
  per person, reconciled against calendar responses.
- `lib/Quad.pm` — the weekly quad, one page from the journal: Technical Priorities (this sprint's tasks tagged
  TODO/OPEN/DONE/WAIT/HOLD/PUNT/DROP with REDO/PASS/SYNC marks), Watch
  Items ((PM) blocker older than 3 days or team over 110%; (WI) fresh blockers, holds, carryover, unassigned, load),
  Schedule Milestones (epics whose ETA falls 30/60/90 days out, pushed right / pulled left against the journal as it
  stood a week ago via `load(..., until => date)`), Accomplishments (done this week, on time unless ever carried over).
  Its two metrics, Sprint Progress and On-Time Delivery, are in the header. A punt-rate table (punted / committed tasks per team, last four sprints; `Scrum` records each punt on the item as `punts`) sits under the quadrants. The owner's four-letter words: TODO = team backlog, OPEN = in a sprint (epics and tomes too), WAIT = blocked outside the team, HOLD = interrupted, PUNT = too hard as written, back to TODO (`punt ID why`), DROP = should not be done, REDO = demo found it wrong (`redo ID why`, last sprint's Done back into this one), PASS = another team should do it (`pass ID Team`), SYNC = coordinated across teams, shared DONE (`sync ID ID`). `daily.pl quad [Team]`, `report` writes
  `<date>-quad.html`/`.txt`, the cockpit has a Quad tab. `hold ID why` / `resume ID` are the stand-up verbs behind HOLD.
- `lib/Drill.pm` — the memory drill: question cards at every level (team → people as initials, initials → name/team,
  tome → epic codes, epic → tome/open task ids, person → in-sprint/next ids, task → owner/gist, blocker gist) generated
  from `items($s)` + `roster.txt` on every run; grading of terse answers (set match on ids/codes/initials where an id from
  the deck that isn't in the answer counts as wrong, all name words, half the title words); Leitner boxes and user-written hooks in
  `drill.txt` (`key | box | due | right | wrong | answer | hook`), the stored answer bringing a card back first when the journal
  changed it. Two front ends: `drill_loop` (terminal) and a sheet graded on `:w` in Vim (`:SDrill`, `\sm`).
- `lib/Metrics.pm` — every metric of WORKFLOW.html §6 against its threshold, in one place: `signals($s, %o)` ->
  `{level red|amber|info, metric, team, text}` (blocked age >3/>5 days, load >110/<70, <60% by Day 8, velocity down 2,
  predictability <80, carryover >20 twice, bus factor >40%, unassigned, on-time <80, punt rate >20 twice, sprint progress
  degrading two weeks, backlog depth <2/>8 sprints, backlog age >90d, intake > done 3 sprints, epic ETA past `target:`,
  #est consensus <50%, calendar declines rising, silent/incomplete 3 days, interrupt SP). The last three read files daily.pl
  passes in (chat tallies, attendance.csv, answers history). `table`, `sprint_report_*`, `rollup_*`, `csv` build the
  dashboard's metrics table, the Day-14 report, the monthly roll-up and the Excel CSVs. Scrum only *draws* signals
  (`health_text`, `health_mail_html`, `health_html`); it never requires Metrics except for `scrum.pl csv`. `new!` postings
  carry `interrupt: 1` so interrupts are measurable.
- `bin/daily.pl` — the umbrella CLI (`init/new/cards/attend/joined/answers/chat/ai/compile/
  report/post/draft/commit/all/status/sprint/velocity/backlog/members/epics/blocked/meetings`)
  that wires all of the above together for the daily/weekly/sprint rhythm; `bin/scrum.pl`,
  `bin/ledger.pl`, `bin/cal.pl`, `bin/chat.pl` expose the same libraries individually for
  scripting/debugging one layer at a time.
- `vim/scrum.vim` — the `:SNew :SCompile :SReport :SDraft :SAll ...` commands plus syntax
  highlighting for the stand-up and journal file formats; this is the primary editing interface
  in normal use (Vim, not the CLI directly).

**Ownership split baked into the model:** the architect (this kit's user) owns tomes/epics,
the master backlog, cross-team capacity/dependencies, and Definition of Ready/Done; each team
owns its own task breakdown, backlog order, and day-to-day task tracking (deliberately *not*
recorded in the journal — sub-tasks/hours stay in the teams' own tools). Keep that boundary in
mind when adding fields or reports: if it's task/hour-level detail, it doesn't belong in the
journal.

**Marking (optional):** `scrum.conf` configures a banner, a marking block, a subject
prefix applied to reports and mail. `reports/` is git-ignored (regenerable); the journal and
stand-up notes *are* committed, so treat the repository itself as marked when its content is, and
keep it on approved storage.
