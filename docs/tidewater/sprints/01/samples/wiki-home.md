# Tidewater model wiki

[[_TOC_]]

> [!note]
> Tidewater is fictional. This wiki shows how a government model team moves from documents and a Cameo model to a
> model kept the DevSecOps way, two weeks at a time.

## Why we are doing this

For decades we did systems engineering with documents, spreadsheets and briefings. A few years ago we were told to move
into Cameo, and we ported our documents into a SysML v1 model. It became a giant spider web: every element linked to
every other, nobody could see what had changed or why, a review meant clicking through diagrams, and it did not scale.
The prime contractor now maintains that v1 model and sends us copies (drops).

This year we were directed to follow DevSecOps. None of us has done it before. That is fine: **most of it is
configuration management, which we already know, done in smaller pieces and checked by machine.** This wiki translates
every new word into the one you already use. Start with the [Glossary](Glossary).

## What changes, and what stays the same

| What stays | What changes |
|---|---|
| A master copy under configuration control | The master copy is text files (SysML v2), so every change shows line by line, like a redline |
| Change proposals reviewed and approved before they go in | A change proposal (merge request) is days of work, not months, and the approval is on line |
| Baselines that never change | A baseline is a protected tag; the server will not let anyone move it, and a machine proves it rebuilds |
| Configuration audits | The audit (the pipeline) runs automatically on every change, in minutes |
| Action items with owners and dates | Action items are issues on a board everyone sees |
| The prime delivers under a CDRL | Each delivery (drop) is converted and merged into our model automatically, keeping our own edits |
| We report status every week | The status is computed from the work itself, not typed up on Thursday night |

## Why it will not become another spider web

- **Small pieces.** The model is split into packages, one folder each, each with an owner. A change touches one or two.
- **Every change is reviewed and checked** before it reaches the master copy. Nothing goes in by accident.
- **Text, not diagrams, is the master.** Diagrams are drawn from the text on demand, so they can never disagree with it.
- **History is complete.** For any line of the model you can see who changed it, when, and under which change.
- **Rules are written once and enforced by the server**, not remembered by people.

## The team

| Who | Role | Owns |
|---|---|---|
| @jim | MBSE lead, responsible for the model | the plan (tomes, epics, the order of the backlog), baselines, discrepancy reports to the prime, approving requirement changes |
| @bob | MBSE engineer | the model content: porting, closing what the converter could not translate, reworking each drop |
| @tom | Configuration management engineer | the pipeline (our automated audit), the vendor branch where drops arrive, tags and releases |

## How we size the work

We plan by time, from the biggest to the smallest. One point is one ideal person-day.

| Level | Size | Like | In GitLab |
|---|---|---|---|
| Project | years (this one: 18 months) | the program | the group `tidewater` |
| Tome | under 1 year | a major WBS element | label ~"tome::port" |
| Epic | under a semester (13 sprints) | a WBS work package | an issue ~"type::epic" and a label ~"epic::structure" |
| Story | under one sprint (2 weeks) | a deliverable you can show at a review | an issue ~"type::story" in milestone %"Sprint 4" |
| Task | under one week (5 points or fewer) | an action item | an issue ~"type::task" that says "Part of #18" |

## The two weeks (a sprint)

| When | Event | Takes | Like |
|---|---|---|---|
| Day 1 | Planning: pick the stories that fit, cut them into tasks | 1 hour | a work-package kickoff |
| Every day | Stand-up: yesterday, today, blockers | 15 minutes | a daily tag-up |
| Mid-sprint | Refinement: get the next stories ready | 1 hour | a pre-brief |
| Day 10 | Review: show what is done, in the model | 1 hour | a design review, small and frequent |
| Day 10 | Retrospective: what to keep, what to change | 30 minutes | lessons learned, every two weeks instead of at the end |

## Pages

- [Glossary](Glossary): systems engineering and CM words, and their GitLab names
- [Onboarding](Onboarding): your first day and first week
- [Definition of Ready](Definition-of-Ready) and [Definition of Done](Definition-of-Done)
- [Gitflow](Gitflow): how changes flow between the master copy, the baselines and the drops
- [Drop Intake Runbook](Drop-Intake-Runbook): a new prime drop, from receipt to merged
- [Baseline Procedure](Baseline-Procedure): cutting `baseline-N`
- [Administration](Administration): what keeps the project running, and who does it
