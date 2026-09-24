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
    perl tests/scrum.t                                # run a single suite (verbose TAP output)
    GP="/mnt/c/Program Files/Git/usr/bin/perl.exe"; for t in tests/*.t; do "$GP" $t | tail -1; done   # from WSL: the same suite under the TARGET Perl (Git for Windows, cygwin build) -- run before every commit that touches bin/ or lib/
    perl -Ilib tests/scrum.t                           # if lib isn't already resolved relative to tests/

There is no build step and no package manager — everything is `use lib` against `lib/`.

    perl bin/devsecops.pl [--quick]     # run the kit's own pipeline gates here (tests on every Perl found, syntax, secrets, marking, hygiene) -> ./devsecops.html, a DevSecOps-style status dashboard; exit 1 on a gap
    perl bin/release.pl [--tag vX]      # release/agile-<tag|sha>.zip (+ .sha256) from the committed tree, for the target laptop; refuses on a dirty tree

Test suites map 1:1 to the libs: `tests/prelude.t`, `tests/ledger.t`, `tests/quad.t`,
`tests/scrum.t`, `tests/standup.t`, `tests/calendar.t`, `tests/chat.t`, `tests/answers.t`,
`tests/attendance.t`. `tests/fake-ps.pl` is a fake `powershell.exe` stand-in used to test
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
cross-model link → interface task in the destination team) — that is how `data/demo` is built. `sim/rehearsal.pl` writes a realistic Teams-chat paste (mistakes seeded, answer key on stderr) into the
current project's standups/ for practising lint/answers without a team; `data/lab` is the practice project. `sim/training.pl` is
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
  Its two metrics, Sprint Progress and On-Time Delivery, are in the header. The owner's four-letter words: TODO = team backlog, OPEN = in a sprint (epics and tomes too), WAIT = blocked outside the team, HOLD = interrupted, PUNT = too hard as written, back to TODO (`punt ID why`), DROP = should not be done, REDO = demo found it wrong (`redo ID why`, last sprint's Done back into this one), PASS = another team should do it (`pass ID Team`), SYNC = coordinated across teams, shared DONE (`sync ID ID`). `daily.pl quad [Team]`, `report` writes
  `<date>-quad.html`/`.txt`, the cockpit has a Quad tab. `hold ID why` / `resume ID` are the stand-up verbs behind HOLD.
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
