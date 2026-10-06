# Tidewater evidence for the primer

Copied by `perl sim/tidewater-evidence.pl RUN_DIR` from a run of `perl sim/tidewater-sim.pl --sprints 6`. Tidewater is fictional, civilian and notional. Every file below was produced by running the kit (the GitLab emulator, the pipeline, gitflow, the converters, the journal); none was written by hand. Paths are normalized (`data/tidewater`, `$KIT`, `/tmp/...-XXXXXX`) so two runs give the same bytes; `tests/tidewater.t` checks that this copy is what the current sources produce.

`memos/` and `views/` beside this file are written by other tools (`tools/memo/memo-build.pl`, `sim/tidewater-views.pl`).

| File | What it shows |
|---|---|
| `journal/roster.txt` | the roster: Jim, Bob, Tom |
| `journal/scrum.conf` | the journal's configuration |
| `journal/scrum.txt` | the kit journal (ledger of story points) at the end of the run |
| `samples/discrepancy-report.md` | a discrepancy report to the prime (DR) (from sprints/04/samples/discrepancy-report-DR-1.md) |
| `samples/merge-request.md` | a merge request: the Default template filled in, "Closes #N", pipeline and approvals (from sprints/02/samples/mr-4.md) |
| `samples/milestone.md` | a sprint milestone description: goal, capacity, dates (from sprints/06/samples/milestone.md) |
| `samples/mr-review-thread.md` | a merge request with a review thread (line comment, request changes, resolved) (from sprints/06/samples/mr-24.md) |
| `samples/prime-drop-issue.md` | the Prime Drop issue: transmittal record, sha256 check, checklist (from the GitLab emulator state, data/tidewater/gitlab/gitlab.json) |
| `samples/release-notes.md` | the release notes of baseline-0 (from the GitLab emulator state, data/tidewater/gitlab/gitlab.json) |
| `samples/story-issue.md` | a story issue: the Story template filled in, labels, milestone, its tasks (from sprints/01/samples/story-TW-4.md) |
| `samples/task-issue.md` | a task issue: estimate, "Part of", quick actions, closed by a merge request (from sprints/01/samples/task-11.md) |
| `samples/wiki-definition-of-done.md` | the Definition of Done wiki page (from sprints/01/samples/wiki-definition-of-done.md) |
| `samples/wiki-glossary.md` | the glossary wiki page (systems engineering <-> GitLab) (from sprints/01/samples/wiki-glossary.md) |
| `samples/wiki-home.md` | the wiki Home page (from sprints/01/samples/wiki-home.md) |
| `sprints/00/week-zero.txt` | week zero (29 Sep - 2 Oct 2026): what happened before sprint 1, with hours |
| `sprints/01/analytics.txt` | gitlab.pl analytics for the sprint: value stream, DORA in model terms, pipelines, MRs, issues |
| `sprints/01/day-log.txt` | day by day: what happened in GitLab and the journal |
| `sprints/01/doctor-bob.txt` | kickoff.pl doctor on bob's laptop |
| `sprints/01/doctor-jim.txt` | kickoff.pl doctor on jim's laptop |
| `sprints/01/doctor-tom.txt` | kickoff.pl doctor on tom's laptop |
| `sprints/01/drop1-reqif2sysml-report.txt` | reqif2sysml --report on drop 1: the DOORS modules |
| `sprints/01/drop1-trace.txt` | the first trace of DOORS against the model: C/F/G/I and the drift |
| `sprints/01/drop1-xmi2sysml-report.txt` | xmi2sysml --report on prime drop 1: what converted, what is a TODO |
| `sprints/01/exports/ci_jobs.csv` | gitlab.pl export: every CI job (the status-metrics format) |
| `sprints/01/exports/defects.csv` | gitlab.pl export: defects and discrepancy reports |
| `sprints/01/exports/issues.csv` | gitlab.pl export: issues |
| `sprints/01/exports/mrs.csv` | gitlab.pl export: merge requests with lead times |
| `sprints/01/exports/tracker/sprint-1.csv` | gitlab.pl export: the sprint tracker for status metrics |
| `sprints/01/exports/tracker/sprint-2.csv` | gitlab.pl export: the sprint tracker for status metrics |
| `sprints/01/kickoff.txt` | the sprint kickoff: goal, capacity, what was committed |
| `sprints/01/local-ci-draft.txt` | the draft pipeline run locally with gitlab.pl ci before the runner existed |
| `sprints/01/meetings.csv` | evidence |
| `sprints/01/morale.json` | the pulse survey at the retrospective: five questions, each person's answers, the mean |
| `sprints/01/plan.txt` | the sprint's plan: stories, tasks, points, owners, work type |
| `sprints/01/poker-2026-10-05.txt` | planning poker rounds (#est in the meeting chat, tallied by the kit) on 2026-10-05 |
| `sprints/01/poker-2026-10-15.txt` | planning poker rounds (#est in the meeting chat, tallied by the kit) on 2026-10-15 |
| `sprints/01/protect-proof.txt` | proof that a direct push to a protected branch is refused |
| `sprints/01/quad-2026-10-09.txt` | the weekly status quad for management (daily.pl quad), 2026-10-09 |
| `sprints/01/quad-2026-10-16.txt` | the weekly status quad for management (daily.pl quad), 2026-10-16 |
| `sprints/01/quotes.txt` | things people said this sprint (dated) |
| `sprints/01/refinement.txt` | backlog refinement on day 9: new stories, Definition of Ready, estimates |
| `sprints/01/retro.txt` | the retrospective: start / stop / continue, actions |
| `sprints/01/review.txt` | the sprint review: what was shown, feedback from management |
| `sprints/01/samples/milestone.md` | the sprint's milestone description |
| `sprints/01/samples/mr-1.md` | merge request !1: description, reports, approvals, review notes |
| `sprints/01/samples/story-TW-1.md` | story TW-1 as GitLab shows it (the real issue Markdown) |
| `sprints/01/samples/story-TW-2.md` | story TW-2 as GitLab shows it (the real issue Markdown) |
| `sprints/01/samples/story-TW-3.md` | story TW-3 as GitLab shows it (the real issue Markdown) |
| `sprints/01/samples/story-TW-4.md` | story TW-4 as GitLab shows it (the real issue Markdown) |
| `sprints/01/samples/story-TW-5.md` | story TW-5 as GitLab shows it (the real issue Markdown) |
| `sprints/01/samples/story-TW-6.md` | story TW-6 as GitLab shows it (the real issue Markdown) |
| `sprints/01/samples/story-TW-7.md` | story TW-7 as GitLab shows it (the real issue Markdown) |
| `sprints/01/samples/task-10.md` | task #10 as GitLab shows it |
| `sprints/01/samples/task-11.md` | task #11 as GitLab shows it |
| `sprints/01/samples/task-12.md` | task #12 as GitLab shows it |
| `sprints/01/samples/task-13.md` | task #13 as GitLab shows it |
| `sprints/01/samples/task-14.md` | task #14 as GitLab shows it |
| `sprints/01/samples/task-15.md` | task #15 as GitLab shows it |
| `sprints/01/samples/task-16.md` | task #16 as GitLab shows it |
| `sprints/01/samples/task-17.md` | task #17 as GitLab shows it |
| `sprints/01/samples/task-18.md` | task #18 as GitLab shows it |
| `sprints/01/samples/task-19.md` | task #19 as GitLab shows it |
| `sprints/01/samples/task-20.md` | task #20 as GitLab shows it |
| `sprints/01/samples/task-21.md` | task #21 as GitLab shows it |
| `sprints/01/samples/task-22.md` | task #22 as GitLab shows it |
| `sprints/01/samples/task-23.md` | task #23 as GitLab shows it |
| `sprints/01/samples/task-24.md` | task #24 as GitLab shows it |
| `sprints/01/samples/task-8.md` | task #8 as GitLab shows it |
| `sprints/01/samples/task-9.md` | task #9 as GitLab shows it |
| `sprints/01/samples/wiki-definition-of-done.md` | the wiki page "definition-of-done" |
| `sprints/01/samples/wiki-definition-of-ready.md` | the wiki page "definition-of-ready" |
| `sprints/01/samples/wiki-drop1-todo-inventory.md` | the wiki page "drop1-todo-inventory" |
| `sprints/01/samples/wiki-glossary.md` | the wiki page "glossary" |
| `sprints/01/samples/wiki-home.md` | the wiki page "home" |
| `sprints/01/scorecard.json` | the twelve-week scorecard measures at the end of the sprint |
| `sprints/01/setup.txt` | gitlab.pl setup applying project.conf: labels, milestones, protections, schedules |
| `sprints/01/standups/2026-10-05-chat.txt` | the stand-up statuses as pasted from the meeting chat, 2026-10-05 |
| `sprints/01/standups/2026-10-05-lint.txt` | the kit's lint of that day's statuses, 2026-10-05 |
| `sprints/01/standups/2026-10-06-chat.txt` | the stand-up statuses as pasted from the meeting chat, 2026-10-06 |
| `sprints/01/standups/2026-10-06-lint.txt` | the kit's lint of that day's statuses, 2026-10-06 |
| `sprints/01/standups/2026-10-07-chat.txt` | the stand-up statuses as pasted from the meeting chat, 2026-10-07 |
| `sprints/01/standups/2026-10-07-lint.txt` | the kit's lint of that day's statuses, 2026-10-07 |
| `sprints/01/standups/2026-10-08-chat.txt` | the stand-up statuses as pasted from the meeting chat, 2026-10-08 |
| `sprints/01/standups/2026-10-08-lint.txt` | the kit's lint of that day's statuses, 2026-10-08 |
| `sprints/01/standups/2026-10-09-chat.txt` | the stand-up statuses as pasted from the meeting chat, 2026-10-09 |
| `sprints/01/standups/2026-10-09-lint.txt` | the kit's lint of that day's statuses, 2026-10-09 |
| `sprints/01/standups/2026-10-13-chat.txt` | the stand-up statuses as pasted from the meeting chat, 2026-10-13 |
| `sprints/01/standups/2026-10-13-lint.txt` | the kit's lint of that day's statuses, 2026-10-13 |
| `sprints/01/standups/2026-10-14-chat.txt` | the stand-up statuses as pasted from the meeting chat, 2026-10-14 |
| `sprints/01/standups/2026-10-14-lint.txt` | the kit's lint of that day's statuses, 2026-10-14 |
| `sprints/01/standups/2026-10-15-chat.txt` | the stand-up statuses as pasted from the meeting chat, 2026-10-15 |
| `sprints/01/standups/2026-10-15-lint.txt` | the kit's lint of that day's statuses, 2026-10-15 |
| `sprints/01/standups/2026-10-16-chat.txt` | the stand-up statuses as pasted from the meeting chat, 2026-10-16 |
| `sprints/01/standups/2026-10-16-lint.txt` | the kit's lint of that day's statuses, 2026-10-16 |
| `sprints/01/todo-at-review.txt` | evidence |
| `sprints/01/weekly-note-2026-10-09.md` | the weekly note to management (drafted with talk.pl weekly), 2026-10-09 |
| `sprints/01/weekly-note-2026-10-16.md` | the weekly note to management (drafted with talk.pl weekly), 2026-10-16 |
| `sprints/02/analytics.txt` | gitlab.pl analytics for the sprint: value stream, DORA in model terms, pipelines, MRs, issues |
| `sprints/02/day-log.txt` | day by day: what happened in GitLab and the journal |
| `sprints/02/drop1-delta.txt` | the drop delta (xmi2sysml --delta) used in the vendor-branch merge |
| `sprints/02/exports/ci_jobs.csv` | gitlab.pl export: every CI job (the status-metrics format) |
| `sprints/02/exports/defects.csv` | gitlab.pl export: defects and discrepancy reports |
| `sprints/02/exports/issues.csv` | gitlab.pl export: issues |
| `sprints/02/exports/mrs.csv` | gitlab.pl export: merge requests with lead times |
| `sprints/02/exports/tracker/sprint-1.csv` | gitlab.pl export: the sprint tracker for status metrics |
| `sprints/02/exports/tracker/sprint-2.csv` | gitlab.pl export: the sprint tracker for status metrics |
| `sprints/02/exports/tracker/sprint-3.csv` | gitlab.pl export: the sprint tracker for status metrics |
| `sprints/02/kickoff.txt` | the sprint kickoff: goal, capacity, what was committed |
| `sprints/02/meetings.csv` | evidence |
| `sprints/02/morale.json` | the pulse survey at the retrospective: five questions, each person's answers, the mean |
| `sprints/02/pipelines/mr2-first-on-powershell-1.log` | merge request !2, first-on-powershell (pipeline #1) |
| `sprints/02/pipelines/mr2-job-pl-2.log` | merge request !2, job-pl (pipeline #2) |
| `sprints/02/pipelines/mr3-first-5.log` | the first pipeline of merge request !3 (pipeline #5): every job log |
| `sprints/02/pipelines/mr4-first-8.log` | the first pipeline of merge request !4 (pipeline #8): every job log |
| `sprints/02/pipelines/mr5-first-11.log` | the first pipeline of merge request !5 (pipeline #11): every job log |
| `sprints/02/pipelines/mr6-drop1-14.log` | merge request !6, drop1 (pipeline #14) |
| `sprints/02/pipelines/mr7-first-17.log` | the first pipeline of merge request !7 (pipeline #17): every job log |
| `sprints/02/plan.txt` | the sprint's plan: stories, tasks, points, owners, work type |
| `sprints/02/poker-2026-10-28.txt` | planning poker rounds (#est in the meeting chat, tallied by the kit) on 2026-10-28 |
| `sprints/02/quad-2026-10-23.txt` | the weekly status quad for management (daily.pl quad), 2026-10-23 |
| `sprints/02/quad-2026-10-30.txt` | the weekly status quad for management (daily.pl quad), 2026-10-30 |
| `sprints/02/quotes.txt` | things people said this sprint (dated) |
| `sprints/02/refinement.txt` | backlog refinement on day 9: new stories, Definition of Ready, estimates |
| `sprints/02/retro.txt` | the retrospective: start / stop / continue, actions |
| `sprints/02/review.txt` | the sprint review: what was shown, feedback from management |
| `sprints/02/samples/milestone.md` | the sprint's milestone description |
| `sprints/02/samples/mr-2.md` | merge request !2: description, reports, approvals, review notes |
| `sprints/02/samples/mr-3.md` | merge request !3: description, reports, approvals, review notes |
| `sprints/02/samples/mr-4.md` | merge request !4: description, reports, approvals, review notes |
| `sprints/02/samples/mr-5.md` | merge request !5: description, reports, approvals, review notes |
| `sprints/02/samples/mr-6.md` | merge request !6: description, reports, approvals, review notes |
| `sprints/02/samples/mr-7.md` | merge request !7: description, reports, approvals, review notes |
| `sprints/02/samples/story-TW-26.md` | story TW-26 as GitLab shows it (the real issue Markdown) |
| `sprints/02/samples/story-TW-27.md` | story TW-27 as GitLab shows it (the real issue Markdown) |
| `sprints/02/samples/story-TW-28.md` | story TW-28 as GitLab shows it (the real issue Markdown) |
| `sprints/02/samples/story-TW-29.md` | story TW-29 as GitLab shows it (the real issue Markdown) |
| `sprints/02/samples/story-TW-30.md` | story TW-30 as GitLab shows it (the real issue Markdown) |
| `sprints/02/samples/story-TW-31.md` | story TW-31 as GitLab shows it (the real issue Markdown) |
| `sprints/02/samples/story-TW-32.md` | story TW-32 as GitLab shows it (the real issue Markdown) |
| `sprints/02/samples/task-33.md` | task #33 as GitLab shows it |
| `sprints/02/samples/task-34.md` | task #34 as GitLab shows it |
| `sprints/02/samples/task-35.md` | task #35 as GitLab shows it |
| `sprints/02/samples/task-36.md` | task #36 as GitLab shows it |
| `sprints/02/samples/task-37.md` | task #37 as GitLab shows it |
| `sprints/02/samples/task-38.md` | task #38 as GitLab shows it |
| `sprints/02/samples/task-39.md` | task #39 as GitLab shows it |
| `sprints/02/samples/task-40.md` | task #40 as GitLab shows it |
| `sprints/02/samples/task-41.md` | task #41 as GitLab shows it |
| `sprints/02/samples/task-42.md` | task #42 as GitLab shows it |
| `sprints/02/samples/task-43.md` | task #43 as GitLab shows it |
| `sprints/02/samples/task-44.md` | task #44 as GitLab shows it |
| `sprints/02/samples/task-45.md` | task #45 as GitLab shows it |
| `sprints/02/samples/task-46.md` | task #46 as GitLab shows it |
| `sprints/02/samples/task-47.md` | task #47 as GitLab shows it |
| `sprints/02/samples/task-48.md` | task #48 as GitLab shows it |
| `sprints/02/samples/task-49.md` | task #49 as GitLab shows it |
| `sprints/02/scorecard.json` | the twelve-week scorecard measures at the end of the sprint |
| `sprints/02/standups/2026-10-19-chat.txt` | the stand-up statuses as pasted from the meeting chat, 2026-10-19 |
| `sprints/02/standups/2026-10-19-lint.txt` | the kit's lint of that day's statuses, 2026-10-19 |
| `sprints/02/standups/2026-10-20-chat.txt` | the stand-up statuses as pasted from the meeting chat, 2026-10-20 |
| `sprints/02/standups/2026-10-20-lint.txt` | the kit's lint of that day's statuses, 2026-10-20 |
| `sprints/02/standups/2026-10-21-chat.txt` | the stand-up statuses as pasted from the meeting chat, 2026-10-21 |
| `sprints/02/standups/2026-10-21-lint.txt` | the kit's lint of that day's statuses, 2026-10-21 |
| `sprints/02/standups/2026-10-22-chat.txt` | the stand-up statuses as pasted from the meeting chat, 2026-10-22 |
| `sprints/02/standups/2026-10-22-lint.txt` | the kit's lint of that day's statuses, 2026-10-22 |
| `sprints/02/standups/2026-10-23-chat.txt` | the stand-up statuses as pasted from the meeting chat, 2026-10-23 |
| `sprints/02/standups/2026-10-23-lint.txt` | the kit's lint of that day's statuses, 2026-10-23 |
| `sprints/02/standups/2026-10-26-chat.txt` | the stand-up statuses as pasted from the meeting chat, 2026-10-26 |
| `sprints/02/standups/2026-10-26-lint.txt` | the kit's lint of that day's statuses, 2026-10-26 |
| `sprints/02/standups/2026-10-27-chat.txt` | the stand-up statuses as pasted from the meeting chat, 2026-10-27 |
| `sprints/02/standups/2026-10-27-lint.txt` | the kit's lint of that day's statuses, 2026-10-27 |
| `sprints/02/standups/2026-10-28-chat.txt` | the stand-up statuses as pasted from the meeting chat, 2026-10-28 |
| `sprints/02/standups/2026-10-28-lint.txt` | the kit's lint of that day's statuses, 2026-10-28 |
| `sprints/02/standups/2026-10-29-chat.txt` | the stand-up statuses as pasted from the meeting chat, 2026-10-29 |
| `sprints/02/standups/2026-10-29-lint.txt` | the kit's lint of that day's statuses, 2026-10-29 |
| `sprints/02/standups/2026-10-30-chat.txt` | the stand-up statuses as pasted from the meeting chat, 2026-10-30 |
| `sprints/02/standups/2026-10-30-lint.txt` | the kit's lint of that day's statuses, 2026-10-30 |
| `sprints/02/todo-at-review.txt` | evidence |
| `sprints/02/weekly-note-2026-10-23.md` | the weekly note to management (drafted with talk.pl weekly), 2026-10-23 |
| `sprints/02/weekly-note-2026-10-30.md` | the weekly note to management (drafted with talk.pl weekly), 2026-10-30 |
| `sprints/03/analytics.txt` | gitlab.pl analytics for the sprint: value stream, DORA in model terms, pipelines, MRs, issues |
| `sprints/03/day-log.txt` | day by day: what happened in GitLab and the journal |
| `sprints/03/drop1-delta.txt` | the drop delta (xmi2sysml --delta) used in the vendor-branch merge |
| `sprints/03/exports/ci_jobs.csv` | gitlab.pl export: every CI job (the status-metrics format) |
| `sprints/03/exports/defects.csv` | gitlab.pl export: defects and discrepancy reports |
| `sprints/03/exports/issues.csv` | gitlab.pl export: issues |
| `sprints/03/exports/mrs.csv` | gitlab.pl export: merge requests with lead times |
| `sprints/03/exports/tracker/sprint-1.csv` | gitlab.pl export: the sprint tracker for status metrics |
| `sprints/03/exports/tracker/sprint-2.csv` | gitlab.pl export: the sprint tracker for status metrics |
| `sprints/03/exports/tracker/sprint-3.csv` | gitlab.pl export: the sprint tracker for status metrics |
| `sprints/03/exports/tracker/sprint-4.csv` | gitlab.pl export: the sprint tracker for status metrics |
| `sprints/03/kickoff.txt` | the sprint kickoff: goal, capacity, what was committed |
| `sprints/03/meetings.csv` | evidence |
| `sprints/03/morale.json` | the pulse survey at the retrospective: five questions, each person's answers, the mean |
| `sprints/03/pipelines/mr10-drop1-27.log` | merge request !10, drop1 (pipeline #27) |
| `sprints/03/pipelines/mr11-first-29.log` | the first pipeline of merge request !11 (pipeline #29): every job log |
| `sprints/03/pipelines/mr8-first-20.log` | the first pipeline of merge request !8 (pipeline #20): every job log |
| `sprints/03/pipelines/mr9-first-23.log` | the first pipeline of merge request !9 (pipeline #23): every job log |
| `sprints/03/pipelines/mr9-fixed-24.log` | merge request !9 after the fix (pipeline #24) |
| `sprints/03/plan.txt` | the sprint's plan: stories, tasks, points, owners, work type |
| `sprints/03/poker-2026-11-12.txt` | planning poker rounds (#est in the meeting chat, tallied by the kit) on 2026-11-12 |
| `sprints/03/quad-2026-11-06.txt` | the weekly status quad for management (daily.pl quad), 2026-11-06 |
| `sprints/03/quad-2026-11-13.txt` | the weekly status quad for management (daily.pl quad), 2026-11-13 |
| `sprints/03/quotes.txt` | things people said this sprint (dated) |
| `sprints/03/refinement.txt` | backlog refinement on day 9: new stories, Definition of Ready, estimates |
| `sprints/03/retro.txt` | the retrospective: start / stop / continue, actions |
| `sprints/03/review-script.md` | the demo script for the sprint review (drafted with talk.pl review, then edited) |
| `sprints/03/review.txt` | the sprint review: what was shown, feedback from management |
| `sprints/03/samples/milestone.md` | the sprint's milestone description |
| `sprints/03/samples/mr-10.md` | merge request !10: description, reports, approvals, review notes |
| `sprints/03/samples/mr-11.md` | merge request !11: description, reports, approvals, review notes |
| `sprints/03/samples/mr-8.md` | merge request !8: description, reports, approvals, review notes |
| `sprints/03/samples/mr-9.md` | merge request !9: description, reports, approvals, review notes |
| `sprints/03/samples/story-TW-50.md` | story TW-50 as GitLab shows it (the real issue Markdown) |
| `sprints/03/samples/story-TW-51.md` | story TW-51 as GitLab shows it (the real issue Markdown) |
| `sprints/03/samples/story-TW-52.md` | story TW-52 as GitLab shows it (the real issue Markdown) |
| `sprints/03/samples/story-TW-53.md` | story TW-53 as GitLab shows it (the real issue Markdown) |
| `sprints/03/samples/story-TW-54.md` | story TW-54 as GitLab shows it (the real issue Markdown) |
| `sprints/03/samples/story-TW-55.md` | story TW-55 as GitLab shows it (the real issue Markdown) |
| `sprints/03/samples/task-56.md` | task #56 as GitLab shows it |
| `sprints/03/samples/task-57.md` | task #57 as GitLab shows it |
| `sprints/03/samples/task-58.md` | task #58 as GitLab shows it |
| `sprints/03/samples/task-59.md` | task #59 as GitLab shows it |
| `sprints/03/samples/task-60.md` | task #60 as GitLab shows it |
| `sprints/03/samples/task-61.md` | task #61 as GitLab shows it |
| `sprints/03/samples/task-62.md` | task #62 as GitLab shows it |
| `sprints/03/samples/task-63.md` | task #63 as GitLab shows it |
| `sprints/03/samples/task-64.md` | task #64 as GitLab shows it |
| `sprints/03/samples/task-65.md` | task #65 as GitLab shows it |
| `sprints/03/samples/wiki-administration.md` | the wiki page "administration" |
| `sprints/03/scorecard.json` | the twelve-week scorecard measures at the end of the sprint |
| `sprints/03/standups/2026-11-02-chat.txt` | the stand-up statuses as pasted from the meeting chat, 2026-11-02 |
| `sprints/03/standups/2026-11-02-lint.txt` | the kit's lint of that day's statuses, 2026-11-02 |
| `sprints/03/standups/2026-11-02-talk-drafts.txt` | talk.pl drafts of the stand-up lines (before people edited them), 2026-11-02 |
| `sprints/03/standups/2026-11-03-chat.txt` | the stand-up statuses as pasted from the meeting chat, 2026-11-03 |
| `sprints/03/standups/2026-11-03-lint.txt` | the kit's lint of that day's statuses, 2026-11-03 |
| `sprints/03/standups/2026-11-03-talk-drafts.txt` | talk.pl drafts of the stand-up lines (before people edited them), 2026-11-03 |
| `sprints/03/standups/2026-11-04-chat.txt` | the stand-up statuses as pasted from the meeting chat, 2026-11-04 |
| `sprints/03/standups/2026-11-04-lint.txt` | the kit's lint of that day's statuses, 2026-11-04 |
| `sprints/03/standups/2026-11-04-talk-drafts.txt` | talk.pl drafts of the stand-up lines (before people edited them), 2026-11-04 |
| `sprints/03/standups/2026-11-05-chat.txt` | the stand-up statuses as pasted from the meeting chat, 2026-11-05 |
| `sprints/03/standups/2026-11-05-lint.txt` | the kit's lint of that day's statuses, 2026-11-05 |
| `sprints/03/standups/2026-11-05-talk-drafts.txt` | talk.pl drafts of the stand-up lines (before people edited them), 2026-11-05 |
| `sprints/03/standups/2026-11-06-chat.txt` | the stand-up statuses as pasted from the meeting chat, 2026-11-06 |
| `sprints/03/standups/2026-11-06-lint.txt` | the kit's lint of that day's statuses, 2026-11-06 |
| `sprints/03/standups/2026-11-06-talk-drafts.txt` | talk.pl drafts of the stand-up lines (before people edited them), 2026-11-06 |
| `sprints/03/standups/2026-11-09-chat.txt` | the stand-up statuses as pasted from the meeting chat, 2026-11-09 |
| `sprints/03/standups/2026-11-09-lint.txt` | the kit's lint of that day's statuses, 2026-11-09 |
| `sprints/03/standups/2026-11-09-talk-drafts.txt` | talk.pl drafts of the stand-up lines (before people edited them), 2026-11-09 |
| `sprints/03/standups/2026-11-10-chat.txt` | the stand-up statuses as pasted from the meeting chat, 2026-11-10 |
| `sprints/03/standups/2026-11-10-lint.txt` | the kit's lint of that day's statuses, 2026-11-10 |
| `sprints/03/standups/2026-11-10-talk-drafts.txt` | talk.pl drafts of the stand-up lines (before people edited them), 2026-11-10 |
| `sprints/03/standups/2026-11-12-chat.txt` | the stand-up statuses as pasted from the meeting chat, 2026-11-12 |
| `sprints/03/standups/2026-11-12-lint.txt` | the kit's lint of that day's statuses, 2026-11-12 |
| `sprints/03/standups/2026-11-12-talk-drafts.txt` | talk.pl drafts of the stand-up lines (before people edited them), 2026-11-12 |
| `sprints/03/standups/2026-11-13-chat.txt` | the stand-up statuses as pasted from the meeting chat, 2026-11-13 |
| `sprints/03/standups/2026-11-13-lint.txt` | the kit's lint of that day's statuses, 2026-11-13 |
| `sprints/03/standups/2026-11-13-talk-drafts.txt` | talk.pl drafts of the stand-up lines (before people edited them), 2026-11-13 |
| `sprints/03/todo-at-review.txt` | evidence |
| `sprints/03/weekly-note-2026-11-06.md` | the weekly note to management (drafted with talk.pl weekly), 2026-11-06 |
| `sprints/03/weekly-note-2026-11-13.md` | the weekly note to management (drafted with talk.pl weekly), 2026-11-13 |
| `sprints/04/analytics.txt` | gitlab.pl analytics for the sprint: value stream, DORA in model terms, pipelines, MRs, issues |
| `sprints/04/day-log.txt` | day by day: what happened in GitLab and the journal |
| `sprints/04/exports/ci_jobs.csv` | gitlab.pl export: every CI job (the status-metrics format) |
| `sprints/04/exports/defects.csv` | gitlab.pl export: defects and discrepancy reports |
| `sprints/04/exports/issues.csv` | gitlab.pl export: issues |
| `sprints/04/exports/mrs.csv` | gitlab.pl export: merge requests with lead times |
| `sprints/04/exports/tracker/sprint-1.csv` | gitlab.pl export: the sprint tracker for status metrics |
| `sprints/04/exports/tracker/sprint-2.csv` | gitlab.pl export: the sprint tracker for status metrics |
| `sprints/04/exports/tracker/sprint-3.csv` | gitlab.pl export: the sprint tracker for status metrics |
| `sprints/04/exports/tracker/sprint-4.csv` | gitlab.pl export: the sprint tracker for status metrics |
| `sprints/04/exports/tracker/sprint-5.csv` | gitlab.pl export: the sprint tracker for status metrics |
| `sprints/04/kickoff.txt` | the sprint kickoff: goal, capacity, what was committed |
| `sprints/04/meetings.csv` | evidence |
| `sprints/04/morale.json` | the pulse survey at the retrospective: five questions, each person's answers, the mean |
| `sprints/04/pipelines/mr12-first-33.log` | the first pipeline of merge request !12 (pipeline #33): every job log |
| `sprints/04/pipelines/mr13-first-36.log` | the first pipeline of merge request !13 (pipeline #36): every job log |
| `sprints/04/pipelines/mr13-fixed-37.log` | merge request !13 after the fix (pipeline #37) |
| `sprints/04/pipelines/mr14-first-40.log` | the first pipeline of merge request !14 (pipeline #40): every job log |
| `sprints/04/pipelines/mr15-first-46.log` | the first pipeline of merge request !15 (pipeline #46): every job log |
| `sprints/04/plan.txt` | the sprint's plan: stories, tasks, points, owners, work type |
| `sprints/04/poker-2026-11-25.txt` | planning poker rounds (#est in the meeting chat, tallied by the kit) on 2026-11-25 |
| `sprints/04/quad-2026-11-20.txt` | the weekly status quad for management (daily.pl quad), 2026-11-20 |
| `sprints/04/quad-2026-11-27.txt` | the weekly status quad for management (daily.pl quad), 2026-11-27 |
| `sprints/04/quotes.txt` | things people said this sprint (dated) |
| `sprints/04/refinement.txt` | backlog refinement on day 9: new stories, Definition of Ready, estimates |
| `sprints/04/retro.txt` | the retrospective: start / stop / continue, actions |
| `sprints/04/review-script.md` | the demo script for the sprint review (drafted with talk.pl review, then edited) |
| `sprints/04/review.txt` | the sprint review: what was shown, feedback from management |
| `sprints/04/samples/discrepancy-report-DR-1.md` | discrepancy report DR-1 to the prime, as GitLab shows it |
| `sprints/04/samples/discrepancy-report-DR-2.md` | discrepancy report DR-2 to the prime, as GitLab shows it |
| `sprints/04/samples/discrepancy-report-DR-3.md` | discrepancy report DR-3 to the prime, as GitLab shows it |
| `sprints/04/samples/discrepancy-report-DR-4.md` | discrepancy report DR-4 to the prime, as GitLab shows it |
| `sprints/04/samples/discrepancy-report-DR-7.md` | discrepancy report DR-7 to the prime, as GitLab shows it |
| `sprints/04/samples/milestone.md` | the sprint's milestone description |
| `sprints/04/samples/mr-12.md` | merge request !12: description, reports, approvals, review notes |
| `sprints/04/samples/mr-13.md` | merge request !13: description, reports, approvals, review notes |
| `sprints/04/samples/mr-14.md` | merge request !14: description, reports, approvals, review notes |
| `sprints/04/samples/mr-15.md` | merge request !15: description, reports, approvals, review notes |
| `sprints/04/samples/story-TW-66.md` | story TW-66 as GitLab shows it (the real issue Markdown) |
| `sprints/04/samples/story-TW-67.md` | story TW-67 as GitLab shows it (the real issue Markdown) |
| `sprints/04/samples/story-TW-68.md` | story TW-68 as GitLab shows it (the real issue Markdown) |
| `sprints/04/samples/story-TW-69.md` | story TW-69 as GitLab shows it (the real issue Markdown) |
| `sprints/04/samples/story-TW-70.md` | story TW-70 as GitLab shows it (the real issue Markdown) |
| `sprints/04/samples/story-TW-71.md` | story TW-71 as GitLab shows it (the real issue Markdown) |
| `sprints/04/samples/story-TW-72.md` | story TW-72 as GitLab shows it (the real issue Markdown) |
| `sprints/04/samples/task-73.md` | task #73 as GitLab shows it |
| `sprints/04/samples/task-74.md` | task #74 as GitLab shows it |
| `sprints/04/samples/task-75.md` | task #75 as GitLab shows it |
| `sprints/04/samples/task-76.md` | task #76 as GitLab shows it |
| `sprints/04/samples/task-77.md` | task #77 as GitLab shows it |
| `sprints/04/samples/task-78.md` | task #78 as GitLab shows it |
| `sprints/04/samples/task-79.md` | task #79 as GitLab shows it |
| `sprints/04/samples/task-80.md` | task #80 as GitLab shows it |
| `sprints/04/samples/task-81.md` | task #81 as GitLab shows it |
| `sprints/04/samples/task-82.md` | task #82 as GitLab shows it |
| `sprints/04/samples/task-83.md` | task #83 as GitLab shows it |
| `sprints/04/scorecard.json` | the twelve-week scorecard measures at the end of the sprint |
| `sprints/04/standups/2026-11-16-chat.txt` | the stand-up statuses as pasted from the meeting chat, 2026-11-16 |
| `sprints/04/standups/2026-11-16-lint.txt` | the kit's lint of that day's statuses, 2026-11-16 |
| `sprints/04/standups/2026-11-16-talk-drafts.txt` | talk.pl drafts of the stand-up lines (before people edited them), 2026-11-16 |
| `sprints/04/standups/2026-11-17-chat.txt` | the stand-up statuses as pasted from the meeting chat, 2026-11-17 |
| `sprints/04/standups/2026-11-17-lint.txt` | the kit's lint of that day's statuses, 2026-11-17 |
| `sprints/04/standups/2026-11-17-talk-drafts.txt` | talk.pl drafts of the stand-up lines (before people edited them), 2026-11-17 |
| `sprints/04/standups/2026-11-18-chat.txt` | the stand-up statuses as pasted from the meeting chat, 2026-11-18 |
| `sprints/04/standups/2026-11-18-lint.txt` | the kit's lint of that day's statuses, 2026-11-18 |
| `sprints/04/standups/2026-11-18-talk-drafts.txt` | talk.pl drafts of the stand-up lines (before people edited them), 2026-11-18 |
| `sprints/04/standups/2026-11-19-chat.txt` | the stand-up statuses as pasted from the meeting chat, 2026-11-19 |
| `sprints/04/standups/2026-11-19-lint.txt` | the kit's lint of that day's statuses, 2026-11-19 |
| `sprints/04/standups/2026-11-19-talk-drafts.txt` | talk.pl drafts of the stand-up lines (before people edited them), 2026-11-19 |
| `sprints/04/standups/2026-11-20-chat.txt` | the stand-up statuses as pasted from the meeting chat, 2026-11-20 |
| `sprints/04/standups/2026-11-20-lint.txt` | the kit's lint of that day's statuses, 2026-11-20 |
| `sprints/04/standups/2026-11-20-talk-drafts.txt` | talk.pl drafts of the stand-up lines (before people edited them), 2026-11-20 |
| `sprints/04/standups/2026-11-23-chat.txt` | the stand-up statuses as pasted from the meeting chat, 2026-11-23 |
| `sprints/04/standups/2026-11-23-lint.txt` | the kit's lint of that day's statuses, 2026-11-23 |
| `sprints/04/standups/2026-11-23-talk-drafts.txt` | talk.pl drafts of the stand-up lines (before people edited them), 2026-11-23 |
| `sprints/04/standups/2026-11-24-chat.txt` | the stand-up statuses as pasted from the meeting chat, 2026-11-24 |
| `sprints/04/standups/2026-11-24-lint.txt` | the kit's lint of that day's statuses, 2026-11-24 |
| `sprints/04/standups/2026-11-24-talk-drafts.txt` | talk.pl drafts of the stand-up lines (before people edited them), 2026-11-24 |
| `sprints/04/standups/2026-11-25-chat.txt` | the stand-up statuses as pasted from the meeting chat, 2026-11-25 |
| `sprints/04/standups/2026-11-25-lint.txt` | the kit's lint of that day's statuses, 2026-11-25 |
| `sprints/04/standups/2026-11-25-talk-drafts.txt` | talk.pl drafts of the stand-up lines (before people edited them), 2026-11-25 |
| `sprints/04/standups/2026-11-27-chat.txt` | the stand-up statuses as pasted from the meeting chat, 2026-11-27 |
| `sprints/04/standups/2026-11-27-lint.txt` | the kit's lint of that day's statuses, 2026-11-27 |
| `sprints/04/standups/2026-11-27-talk-drafts.txt` | talk.pl drafts of the stand-up lines (before people edited them), 2026-11-27 |
| `sprints/04/todo-at-review.txt` | evidence |
| `sprints/04/weekly-note-2026-11-20.md` | the weekly note to management (drafted with talk.pl weekly), 2026-11-20 |
| `sprints/04/weekly-note-2026-11-27.md` | the weekly note to management (drafted with talk.pl weekly), 2026-11-27 |
| `sprints/05/analytics.txt` | gitlab.pl analytics for the sprint: value stream, DORA in model terms, pipelines, MRs, issues |
| `sprints/05/day-log.txt` | day by day: what happened in GitLab and the journal |
| `sprints/05/exports/ci_jobs.csv` | gitlab.pl export: every CI job (the status-metrics format) |
| `sprints/05/exports/defects.csv` | gitlab.pl export: defects and discrepancy reports |
| `sprints/05/exports/issues.csv` | gitlab.pl export: issues |
| `sprints/05/exports/mrs.csv` | gitlab.pl export: merge requests with lead times |
| `sprints/05/exports/tracker/sprint-1.csv` | gitlab.pl export: the sprint tracker for status metrics |
| `sprints/05/exports/tracker/sprint-2.csv` | gitlab.pl export: the sprint tracker for status metrics |
| `sprints/05/exports/tracker/sprint-3.csv` | gitlab.pl export: the sprint tracker for status metrics |
| `sprints/05/exports/tracker/sprint-4.csv` | gitlab.pl export: the sprint tracker for status metrics |
| `sprints/05/exports/tracker/sprint-5.csv` | gitlab.pl export: the sprint tracker for status metrics |
| `sprints/05/exports/tracker/sprint-6.csv` | gitlab.pl export: the sprint tracker for status metrics |
| `sprints/05/kickoff.txt` | the sprint kickoff: goal, capacity, what was committed |
| `sprints/05/meetings.csv` | evidence |
| `sprints/05/morale.json` | the pulse survey at the retrospective: five questions, each person's answers, the mean |
| `sprints/05/pipelines/mr16-first-52.log` | the first pipeline of merge request !16 (pipeline #52): every job log |
| `sprints/05/pipelines/mr17-first-57.log` | the first pipeline of merge request !17 (pipeline #57): every job log |
| `sprints/05/pipelines/mr18-first-61.log` | the first pipeline of merge request !18 (pipeline #61): every job log |
| `sprints/05/pipelines/mr19-first-66.log` | the first pipeline of merge request !19 (pipeline #66): every job log |
| `sprints/05/pipelines/mr20-first-71.log` | the first pipeline of merge request !20 (pipeline #71): every job log |
| `sprints/05/pipelines/mr20-fixed-72.log` | merge request !20 after the fix (pipeline #72) |
| `sprints/05/plan.txt` | the sprint's plan: stories, tasks, points, owners, work type |
| `sprints/05/poker-2026-12-09.txt` | planning poker rounds (#est in the meeting chat, tallied by the kit) on 2026-12-09 |
| `sprints/05/quad-2026-12-04.txt` | the weekly status quad for management (daily.pl quad), 2026-12-04 |
| `sprints/05/quad-2026-12-11.txt` | the weekly status quad for management (daily.pl quad), 2026-12-11 |
| `sprints/05/quotes.txt` | things people said this sprint (dated) |
| `sprints/05/recipe-doors.txt` | the requirements recipe (req-recipe.pl) on the DOORS text |
| `sprints/05/refinement.txt` | backlog refinement on day 9: new stories, Definition of Ready, estimates |
| `sprints/05/retro.txt` | the retrospective: start / stop / continue, actions |
| `sprints/05/review-script.md` | the demo script for the sprint review (drafted with talk.pl review, then edited) |
| `sprints/05/review.txt` | the sprint review: what was shown, feedback from management |
| `sprints/05/samples/discrepancy-report-DR-5.md` | discrepancy report DR-5 to the prime, as GitLab shows it |
| `sprints/05/samples/discrepancy-report-DR-6.md` | discrepancy report DR-6 to the prime, as GitLab shows it |
| `sprints/05/samples/milestone.md` | the sprint's milestone description |
| `sprints/05/samples/mr-16.md` | merge request !16: description, reports, approvals, review notes |
| `sprints/05/samples/mr-17.md` | merge request !17: description, reports, approvals, review notes |
| `sprints/05/samples/mr-18.md` | merge request !18: description, reports, approvals, review notes |
| `sprints/05/samples/mr-19.md` | merge request !19: description, reports, approvals, review notes |
| `sprints/05/samples/mr-20.md` | merge request !20: description, reports, approvals, review notes |
| `sprints/05/samples/story-TW-89.md` | story TW-89 as GitLab shows it (the real issue Markdown) |
| `sprints/05/samples/story-TW-90.md` | story TW-90 as GitLab shows it (the real issue Markdown) |
| `sprints/05/samples/story-TW-91.md` | story TW-91 as GitLab shows it (the real issue Markdown) |
| `sprints/05/samples/story-TW-92.md` | story TW-92 as GitLab shows it (the real issue Markdown) |
| `sprints/05/samples/story-TW-93.md` | story TW-93 as GitLab shows it (the real issue Markdown) |
| `sprints/05/samples/story-TW-94.md` | story TW-94 as GitLab shows it (the real issue Markdown) |
| `sprints/05/samples/story-TW-95.md` | story TW-95 as GitLab shows it (the real issue Markdown) |
| `sprints/05/samples/task-100.md` | task #100 as GitLab shows it |
| `sprints/05/samples/task-101.md` | task #101 as GitLab shows it |
| `sprints/05/samples/task-102.md` | task #102 as GitLab shows it |
| `sprints/05/samples/task-103.md` | task #103 as GitLab shows it |
| `sprints/05/samples/task-104.md` | task #104 as GitLab shows it |
| `sprints/05/samples/task-105.md` | task #105 as GitLab shows it |
| `sprints/05/samples/task-106.md` | task #106 as GitLab shows it |
| `sprints/05/samples/task-107.md` | task #107 as GitLab shows it |
| `sprints/05/samples/task-108.md` | task #108 as GitLab shows it |
| `sprints/05/samples/task-97.md` | task #97 as GitLab shows it |
| `sprints/05/samples/task-98.md` | task #98 as GitLab shows it |
| `sprints/05/samples/task-99.md` | task #99 as GitLab shows it |
| `sprints/05/scorecard.json` | the twelve-week scorecard measures at the end of the sprint |
| `sprints/05/standups/2026-11-30-chat.txt` | the stand-up statuses as pasted from the meeting chat, 2026-11-30 |
| `sprints/05/standups/2026-11-30-lint.txt` | the kit's lint of that day's statuses, 2026-11-30 |
| `sprints/05/standups/2026-11-30-talk-drafts.txt` | talk.pl drafts of the stand-up lines (before people edited them), 2026-11-30 |
| `sprints/05/standups/2026-12-01-chat.txt` | the stand-up statuses as pasted from the meeting chat, 2026-12-01 |
| `sprints/05/standups/2026-12-01-lint.txt` | the kit's lint of that day's statuses, 2026-12-01 |
| `sprints/05/standups/2026-12-01-talk-drafts.txt` | talk.pl drafts of the stand-up lines (before people edited them), 2026-12-01 |
| `sprints/05/standups/2026-12-02-chat.txt` | the stand-up statuses as pasted from the meeting chat, 2026-12-02 |
| `sprints/05/standups/2026-12-02-lint.txt` | the kit's lint of that day's statuses, 2026-12-02 |
| `sprints/05/standups/2026-12-02-talk-drafts.txt` | talk.pl drafts of the stand-up lines (before people edited them), 2026-12-02 |
| `sprints/05/standups/2026-12-03-chat.txt` | the stand-up statuses as pasted from the meeting chat, 2026-12-03 |
| `sprints/05/standups/2026-12-03-lint.txt` | the kit's lint of that day's statuses, 2026-12-03 |
| `sprints/05/standups/2026-12-03-talk-drafts.txt` | talk.pl drafts of the stand-up lines (before people edited them), 2026-12-03 |
| `sprints/05/standups/2026-12-04-chat.txt` | the stand-up statuses as pasted from the meeting chat, 2026-12-04 |
| `sprints/05/standups/2026-12-04-lint.txt` | the kit's lint of that day's statuses, 2026-12-04 |
| `sprints/05/standups/2026-12-04-talk-drafts.txt` | talk.pl drafts of the stand-up lines (before people edited them), 2026-12-04 |
| `sprints/05/standups/2026-12-07-chat.txt` | the stand-up statuses as pasted from the meeting chat, 2026-12-07 |
| `sprints/05/standups/2026-12-07-lint.txt` | the kit's lint of that day's statuses, 2026-12-07 |
| `sprints/05/standups/2026-12-07-talk-drafts.txt` | talk.pl drafts of the stand-up lines (before people edited them), 2026-12-07 |
| `sprints/05/standups/2026-12-08-chat.txt` | the stand-up statuses as pasted from the meeting chat, 2026-12-08 |
| `sprints/05/standups/2026-12-08-lint.txt` | the kit's lint of that day's statuses, 2026-12-08 |
| `sprints/05/standups/2026-12-08-talk-drafts.txt` | talk.pl drafts of the stand-up lines (before people edited them), 2026-12-08 |
| `sprints/05/standups/2026-12-09-chat.txt` | the stand-up statuses as pasted from the meeting chat, 2026-12-09 |
| `sprints/05/standups/2026-12-09-lint.txt` | the kit's lint of that day's statuses, 2026-12-09 |
| `sprints/05/standups/2026-12-09-talk-drafts.txt` | talk.pl drafts of the stand-up lines (before people edited them), 2026-12-09 |
| `sprints/05/standups/2026-12-10-chat.txt` | the stand-up statuses as pasted from the meeting chat, 2026-12-10 |
| `sprints/05/standups/2026-12-10-lint.txt` | the kit's lint of that day's statuses, 2026-12-10 |
| `sprints/05/standups/2026-12-10-talk-drafts.txt` | talk.pl drafts of the stand-up lines (before people edited them), 2026-12-10 |
| `sprints/05/standups/2026-12-11-chat.txt` | the stand-up statuses as pasted from the meeting chat, 2026-12-11 |
| `sprints/05/standups/2026-12-11-lint.txt` | the kit's lint of that day's statuses, 2026-12-11 |
| `sprints/05/standups/2026-12-11-talk-drafts.txt` | talk.pl drafts of the stand-up lines (before people edited them), 2026-12-11 |
| `sprints/05/todo-at-review.txt` | evidence |
| `sprints/05/weekly-note-2026-12-04.md` | the weekly note to management (drafted with talk.pl weekly), 2026-12-04 |
| `sprints/05/weekly-note-2026-12-11.md` | the weekly note to management (drafted with talk.pl weekly), 2026-12-11 |
| `sprints/06/analytics.txt` | gitlab.pl analytics for the sprint: value stream, DORA in model terms, pipelines, MRs, issues |
| `sprints/06/briefing.txt` | the twelve-week management briefing |
| `sprints/06/day-in-life/incident.md` | the failed nightly of 2026-12-17: the issue opened from it |
| `sprints/06/day-in-life/timeline.txt` | Bob's day, 2026-12-17 |
| `sprints/06/day-in-life/todo-list.txt` | Bob's GitLab To-Do list on 2026-12-17 |
| `sprints/06/day-log.txt` | day by day: what happened in GitLab and the journal |
| `sprints/06/doc-stages.txt` | the document review stages (doc:: labels) of the sprint-6 documents, day by day |
| `sprints/06/exports/ci_jobs.csv` | gitlab.pl export: every CI job (the status-metrics format) |
| `sprints/06/exports/defects.csv` | gitlab.pl export: defects and discrepancy reports |
| `sprints/06/exports/issues.csv` | gitlab.pl export: issues |
| `sprints/06/exports/mrs.csv` | gitlab.pl export: merge requests with lead times |
| `sprints/06/exports/tracker/sprint-1.csv` | gitlab.pl export: the sprint tracker for status metrics |
| `sprints/06/exports/tracker/sprint-2.csv` | gitlab.pl export: the sprint tracker for status metrics |
| `sprints/06/exports/tracker/sprint-3.csv` | gitlab.pl export: the sprint tracker for status metrics |
| `sprints/06/exports/tracker/sprint-4.csv` | gitlab.pl export: the sprint tracker for status metrics |
| `sprints/06/exports/tracker/sprint-5.csv` | gitlab.pl export: the sprint tracker for status metrics |
| `sprints/06/exports/tracker/sprint-6.csv` | gitlab.pl export: the sprint tracker for status metrics |
| `sprints/06/exports/tracker/sprint-7.csv` | gitlab.pl export: the sprint tracker for status metrics |
| `sprints/06/kickoff.txt` | the sprint kickoff: goal, capacity, what was committed |
| `sprints/06/meetings.csv` | evidence |
| `sprints/06/morale.json` | the pulse survey at the retrospective: five questions, each person's answers, the mean |
| `sprints/06/pipelines/mr21-first-77.log` | the first pipeline of merge request !21 (pipeline #77): every job log |
| `sprints/06/pipelines/mr22-first-81.log` | the first pipeline of merge request !22 (pipeline #81): every job log |
| `sprints/06/pipelines/mr23-first-86.log` | the first pipeline of merge request !23 (pipeline #86): every job log |
| `sprints/06/pipelines/mr23-fixed-87.log` | merge request !23 after the fix (pipeline #87) |
| `sprints/06/pipelines/mr24-first-90.log` | the first pipeline of merge request !24 (pipeline #90): every job log |
| `sprints/06/pipelines/mr25-first-95.log` | the first pipeline of merge request !25 (pipeline #95): every job log |
| `sprints/06/pipelines/mr25-fixed-96.log` | merge request !25 after the fix (pipeline #96) |
| `sprints/06/pipelines/mr26-first-100.log` | the first pipeline of merge request !26 (pipeline #100): every job log |
| `sprints/06/pipelines/nightly-2026-12-17-83.log` | the nightly scheduled pipeline of 2026-12-17 (pipeline #83) |
| `sprints/06/pipelines/nightly-2026-12-18-93.log` | the nightly scheduled pipeline of 2026-12-18 (pipeline #93) |
| `sprints/06/pipelines/nightly-rerun-2026-12-17-84.log` | the nightly scheduled pipeline re-run on 2026-12-17 (pipeline #84) |
| `sprints/06/pipelines/tag-baseline-0-108.log` | a pipeline log |
| `sprints/06/plan.txt` | the sprint's plan: stories, tasks, points, owners, work type |
| `sprints/06/poker-2026-12-23.txt` | planning poker rounds (#est in the meeting chat, tallied by the kit) on 2026-12-23 |
| `sprints/06/quad-2026-12-18.txt` | the weekly status quad for management (daily.pl quad), 2026-12-18 |
| `sprints/06/quotes.txt` | things people said this sprint (dated) |
| `sprints/06/refinement.txt` | backlog refinement on day 9: new stories, Definition of Ready, estimates |
| `sprints/06/release/baseline-0.json` | evidence |
| `sprints/06/retro.txt` | the retrospective: start / stop / continue, actions |
| `sprints/06/review-script.md` | the demo script for the sprint review (drafted with talk.pl review, then edited) |
| `sprints/06/review.txt` | the sprint review: what was shown, feedback from management |
| `sprints/06/samples/issue-prime-tbd.md` | the prime-tbd issue: work going ahead on an assumption about the next drop |
| `sprints/06/samples/milestone.md` | the sprint's milestone description |
| `sprints/06/samples/mr-21.md` | merge request !21: description, reports, approvals, review notes |
| `sprints/06/samples/mr-22.md` | merge request !22: description, reports, approvals, review notes |
| `sprints/06/samples/mr-23.md` | merge request !23: description, reports, approvals, review notes |
| `sprints/06/samples/mr-24.md` | merge request !24: description, reports, approvals, review notes |
| `sprints/06/samples/mr-25.md` | merge request !25: description, reports, approvals, review notes |
| `sprints/06/samples/mr-26.md` | merge request !26: description, reports, approvals, review notes |
| `sprints/06/samples/mr-27.md` | merge request !27: description, reports, approvals, review notes |
| `sprints/06/samples/story-TW-111.md` | story TW-111 as GitLab shows it (the real issue Markdown) |
| `sprints/06/samples/story-TW-112.md` | story TW-112 as GitLab shows it (the real issue Markdown) |
| `sprints/06/samples/story-TW-113.md` | story TW-113 as GitLab shows it (the real issue Markdown) |
| `sprints/06/samples/story-TW-114.md` | story TW-114 as GitLab shows it (the real issue Markdown) |
| `sprints/06/samples/story-TW-115.md` | story TW-115 as GitLab shows it (the real issue Markdown) |
| `sprints/06/samples/story-TW-116.md` | story TW-116 as GitLab shows it (the real issue Markdown) |
| `sprints/06/samples/story-TW-117.md` | story TW-117 as GitLab shows it (the real issue Markdown) |
| `sprints/06/samples/story-TW-118.md` | story TW-118 as GitLab shows it (the real issue Markdown) |
| `sprints/06/samples/task-119.md` | task #119 as GitLab shows it |
| `sprints/06/samples/task-120.md` | task #120 as GitLab shows it |
| `sprints/06/samples/task-121.md` | task #121 as GitLab shows it |
| `sprints/06/samples/task-122.md` | task #122 as GitLab shows it |
| `sprints/06/samples/task-123.md` | task #123 as GitLab shows it |
| `sprints/06/samples/task-124.md` | task #124 as GitLab shows it |
| `sprints/06/samples/task-125.md` | task #125 as GitLab shows it |
| `sprints/06/samples/task-126.md` | task #126 as GitLab shows it |
| `sprints/06/samples/task-127.md` | task #127 as GitLab shows it |
| `sprints/06/samples/task-128.md` | task #128 as GitLab shows it |
| `sprints/06/scorecard.json` | the twelve-week scorecard measures at the end of the sprint |
| `sprints/06/standups/2026-12-14-chat.txt` | the stand-up statuses as pasted from the meeting chat, 2026-12-14 |
| `sprints/06/standups/2026-12-14-lint.txt` | the kit's lint of that day's statuses, 2026-12-14 |
| `sprints/06/standups/2026-12-14-talk-drafts.txt` | talk.pl drafts of the stand-up lines (before people edited them), 2026-12-14 |
| `sprints/06/standups/2026-12-15-chat.txt` | the stand-up statuses as pasted from the meeting chat, 2026-12-15 |
| `sprints/06/standups/2026-12-15-lint.txt` | the kit's lint of that day's statuses, 2026-12-15 |
| `sprints/06/standups/2026-12-15-talk-drafts.txt` | talk.pl drafts of the stand-up lines (before people edited them), 2026-12-15 |
| `sprints/06/standups/2026-12-16-chat.txt` | the stand-up statuses as pasted from the meeting chat, 2026-12-16 |
| `sprints/06/standups/2026-12-16-lint.txt` | the kit's lint of that day's statuses, 2026-12-16 |
| `sprints/06/standups/2026-12-16-talk-drafts.txt` | talk.pl drafts of the stand-up lines (before people edited them), 2026-12-16 |
| `sprints/06/standups/2026-12-17-chat.txt` | the stand-up statuses as pasted from the meeting chat, 2026-12-17 |
| `sprints/06/standups/2026-12-17-lint.txt` | the kit's lint of that day's statuses, 2026-12-17 |
| `sprints/06/standups/2026-12-17-talk-drafts.txt` | talk.pl drafts of the stand-up lines (before people edited them), 2026-12-17 |
| `sprints/06/standups/2026-12-18-chat.txt` | the stand-up statuses as pasted from the meeting chat, 2026-12-18 |
| `sprints/06/standups/2026-12-18-lint.txt` | the kit's lint of that day's statuses, 2026-12-18 |
| `sprints/06/standups/2026-12-18-talk-drafts.txt` | talk.pl drafts of the stand-up lines (before people edited them), 2026-12-18 |
| `sprints/06/standups/2026-12-21-chat.txt` | the stand-up statuses as pasted from the meeting chat, 2026-12-21 |
| `sprints/06/standups/2026-12-21-lint.txt` | the kit's lint of that day's statuses, 2026-12-21 |
| `sprints/06/standups/2026-12-21-talk-drafts.txt` | talk.pl drafts of the stand-up lines (before people edited them), 2026-12-21 |
| `sprints/06/standups/2026-12-22-chat.txt` | the stand-up statuses as pasted from the meeting chat, 2026-12-22 |
| `sprints/06/standups/2026-12-22-lint.txt` | the kit's lint of that day's statuses, 2026-12-22 |
| `sprints/06/standups/2026-12-22-talk-drafts.txt` | talk.pl drafts of the stand-up lines (before people edited them), 2026-12-22 |
| `sprints/06/standups/2026-12-23-chat.txt` | the stand-up statuses as pasted from the meeting chat, 2026-12-23 |
| `sprints/06/standups/2026-12-23-lint.txt` | the kit's lint of that day's statuses, 2026-12-23 |
| `sprints/06/standups/2026-12-23-talk-drafts.txt` | talk.pl drafts of the stand-up lines (before people edited them), 2026-12-23 |
| `sprints/06/standups/2026-12-24-chat.txt` | the stand-up statuses as pasted from the meeting chat, 2026-12-24 |
| `sprints/06/standups/2026-12-24-lint.txt` | the kit's lint of that day's statuses, 2026-12-24 |
| `sprints/06/standups/2026-12-24-talk-drafts.txt` | talk.pl drafts of the stand-up lines (before people edited them), 2026-12-24 |
| `sprints/06/todo-at-review.txt` | evidence |
| `sprints/06/weekly-note-2026-12-18.md` | the weekly note to management (drafted with talk.pl weekly), 2026-12-18 |
| `sprints/06/weekly-note-2026-12-24.md` | the weekly note to management (drafted with talk.pl weekly), 2026-12-24 |
| `sprints/checks-s1-s6.txt` | the simulation's consistency checks over sprints 1-6 |
