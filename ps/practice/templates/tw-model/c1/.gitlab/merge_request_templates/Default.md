<!-- A merge request is your change request (an ECP in miniature): the exact lines you changed, the reason, the
     automated audit (the pipeline) and the owner's approval, all in one place.
     Title: what the model gains, e.g. "Close the Stations TODO lines". Prefix "Draft:" until it is ready to review. -->

## What and why

<!-- Two or three sentences. Which story or task, and what changes in the model. -->

Closes #<!-- task number -->
Part of #<!-- story number -->

## Model changes

<!-- The packages and elements touched. Name added, changed and removed definitions. -->
| Package | Change |
|---|---|
| | |

## Checks

- [ ] `gitlab.pl ci` passed locally (grammar, lint 0/0, outline, docs)
- [ ] `docs/` regenerated and committed
- [ ] No new `// TODO` lines (or each one has a task)
- [ ] Trace job: no new orphan, unverified or drifted requirement (or a DR is linked)
- [ ] Commit messages carry a `Changelog:` trailer where the change is user-visible

## Review notes

<!-- Where to look first, what you are unsure about. -->

/label ~"workflow::review"
/assign_reviewer @bob
/milestone %"Sprint "
