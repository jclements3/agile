<!-- Story: something you can show at the sprint review, like a small deliverable.
     Story: a slice of value that fits in ONE sprint, made of tasks of less than a week each.
     Title: a verb and an object, e.g. "Close the Stations TODO lines". The journal id is TW-<this issue's number>. -->

## Why

<!-- The outcome for the program in one or two sentences: who gains what. -->

## What "done" looks like

<!-- Acceptance criteria as a checklist. Each line can be checked by someone who did not do the work. -->
- [ ] 
- [ ] The pipeline is green on the MR (grammar, lint 0/0, outline, docs current)
- [ ] The trace job shows no new orphan, unverified or drifted requirement

## Tasks

<!-- One task issue per line, each under 5 points (one point = one ideal day). Create them with the Task template
     and reference them here; they close through their merge requests. -->
| Task | Points | Who |
|---|---|---|
| # | | @ |

## Notes

<!-- Links, decisions, the v1 elements involved (xmi:id), the DOORS ids involved. -->

<details><summary>Definition of Ready (check before the sprint takes it)</summary>

- [ ] Fits in one sprint and has an epic (~"epic::...") and a tome (~"tome::...")
- [ ] Acceptance criteria above are testable
- [ ] Tasks are cut, each at most 5 points
- [ ] Dependencies on the prime or another story are linked (`/relate #N`, or "blocked by")

</details>

/label ~"type::story" ~"workflow::ready" ~"priority::2"
/milestone %"Sprint "
/assign @
/weight 
