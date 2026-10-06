# Tidewater memos (notional)

Five DoD-style memoranda from the Tidewater case study. Each was written in Markdown from a template in
`tools/gitlab/templates/memos/`, and rendered with `tools/memo/memo-build.pl`, which wraps `tools/memo/md2memo.pl`.
The `.pdf` and `.txt` files beside each `.md` are the rendered copies the primer quotes.

| Memo | From | Template |
|---|---|---|
| `2026-09-24-directive.md` | the program manager: the directive that starts the case study (primer chapter 4) | none: it predates the templates |
| `2026-10-21-request-for-enablers.md` | Jim, sprint 2: dated asks for training time, the ISSM review, a Cameo seat, a second runner and a GitLab tier decision | `request-for-enablers.md` |
| `2026-10-23-mfr-decisions.md` | Jim, sprint 2: the record of decisions D-1 to D-10 | `memorandum-for-record.md` |
| `2026-12-24-twelve-week-progress.md` | Jim, sprint 6: the twelve-week results for the December review | `progress-memo.md` |
| `2027-01-13-drop-2-disposition.md` | Jim, as chair of the model change board: drop v1.1 | `drop-disposition.md` |

Numbers come from the simulation's sprint evidence in `docs/tidewater/sprints/`. Issues the simulation has not
reached yet (the drop-2 intake, January 2027) are marked "planned". Rebuild every memo with:

    perl tools/memo/memo-build.pl docs/tidewater/memos/*.md
