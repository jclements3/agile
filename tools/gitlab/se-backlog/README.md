# GitLab agile setup

`gitlab_agile_setup.py` sets up a GitLab Premium or Ultimate group for the tome / epoch / story / task plan and the seven work states. It can then load the SE backlog from `se-backlog-staffing.xlsx`.

## What it builds

| Step          | GitLab object                            | Detail                                                                                                                                                                                      |
|---------------|------------------------------------------|---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| 1. statuses   | Custom work-item statuses (GitLab 18.2+) | TODO, OPEN, WAIT, HOLD, PUNT, DONE, DROP with your colors. DONE and DROP close the item.                                                                                                    |
| 2. labels     | Group labels                             | REDO, PASS, SYNC marks (olive `#6b7436`) and `team::SE-*`. With `--label-states`, also `state::*` labels.                                                                                   |
| 3. cadence    | Iteration cadence                        | 2-week sprints, automatic, unfinished work rolls over                                                                                                                                       |
| 4. milestones | Group milestones                         | One per epoch, named for its review (`T1.E3 PDR`), dated to its 26 weeks                                                                                                                    |
| 5. board      | "Sprint board"                           | One list per state in label mode; a plain board when using statuses                                                                                                                         |
| 6. templates  | `.gitlab/issue_templates/`               | `story.md` (definition of done) and `hardening.md` (sprint 13)                                                                                                                              |
| 7. backlog    | Epics, issues, tasks                     | Tomes → epics; epochs → child epics with dates; stories → issues with team label, weight = days, due date = end of planned sprint, milestone, epic; tasks → child tasks with time estimates |

Stories are not assigned to iterations. That happens at sprint planning, and each issue's description records which sprint it was planned for.

## Run it

```bash
export GITLAB_URL=https://gitlab.example.invalid
export GITLAB_TOKEN=glpat-xxxxxxxx        # api scope; Owner or Maintainer of the top-level group

# preview: reads from GitLab, writes nothing
python3 gitlab_agile_setup.py --group se-team --project se-team/se-backlog \
    --start 2026-10-12 --backlog se-backlog-staffing.xlsx

# make the changes
python3 gitlab_agile_setup.py --group se-team --project se-team/se-backlog \
    --start 2026-10-12 --backlog se-backlog-staffing.xlsx --apply
```

| Option                    | Use                                                                                              |
|---------------------------|--------------------------------------------------------------------------------------------------|
| `--label-states`          | Use `state::*` scoped labels instead of custom statuses, for GitLab before 18.2 or the Free tier |
| `--skip statuses,backlog` | Skip any steps (statuses, labels, cadence, milestones, board, templates, backlog)                |
| `--branch develop`        | Branch to commit the issue templates to (default `main`)                                         |
| `--insecure`              | Skip TLS verification for a lab server with a self-signed certificate                            |

Every step is safe to rerun: existing labels, milestones, epics and issues with the same title are reused, not duplicated. Tasks are the exception, so skip `backlog` on reruns once it has loaded.

## Export, tear down, rebuild

`--export` reads the group's epics, issues and tasks and writes them back into the same spreadsheet format the importer reads. That means you can tear the group down, or move to another GitLab instance, and rebuild it exactly with `--backlog`.

```bash
# snapshot GitLab -> spreadsheet (read-only, no --apply needed)
python3 gitlab_agile_setup.py --group se-team --project se-team/se-backlog \
    --export backlog-2026-10-07.xlsx --template se-backlog-staffing.xlsx

# rebuild anywhere from the snapshot
python3 gitlab_agile_setup.py --group new-group --project new-group/se-backlog \
    --start 2027-01-04 --backlog backlog-2026-10-07.xlsx --apply
```

The export carries, per item:
- ID, level, parent, title, team, epoch, planned sprint, days (story weight or task estimate)
- done-when, model link
- **state** (custom status, or `state::*` label, or open/closed), shown with its badge color
- **marks** (REDO, PASS, SYNC)
- iteration, assignee, time spent, and the GitLab link

`--template` keeps the Teams, Staffing, Profile and Capacity sheets from your planning workbook. Because the backlog columns stay in the same order, the capacity formulas recalculate against the live data.

Items created directly in GitLab without a backlog ID in the title get one on export (`ISSUE-42`, `EPIC-7`). Issues with no epic are listed under `UNPLANNED`. Edit the spreadsheet in between (re-plan, change states, add stories) and the rebuild picks up the changes.

**Not carried across a rebuild:** comments, merge-request links, history, assignees and iterations. Assignees and iterations are exported for reference, but the rebuild leaves stories unassigned for the next sprint planning.

To run it nightly, add a scheduled pipeline job that calls `--export` and stores the file as a job artifact.

## Requirements

- Python 3.8+, standard library only. `openpyxl` is needed only for `--backlog` and `--export`.
- Epics and iterations need Premium or Ultimate. Child epics (epochs under tomes) need Ultimate.
- Custom statuses need 18.2 or later. If they can't be read, the script falls back to `state::*` labels automatically.

## Known limits

- **Epic REST API:** epics are created through the REST epics API, which GitLab has deprecated in favor of work items but still serves. If your version has removed it, run with `--skip backlog` and import epics separately.
- **Existing statuses:** the status step replaces the group's statuses with the seven states. Statuses already in use on items must be remapped in Group > Settings > Issues > Statuses before they can be removed.
- **Statuses don't cover epics yet.** Track tome and epoch progress with epic health status.
- **Test against your instance:** this script was tested against mock servers, not a live GitLab instance. A full import → export → re-import → export round trip of the 180-row backlog reproduced every ID, title, team, sprint, days, state and mark exactly. Try the dry run, then `--apply` on a scratch group, before running it on the real one.
