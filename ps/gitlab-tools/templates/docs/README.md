# The model repository's documents

[[_TOC_]]

These pages are the team's working agreements for this model. They are short on purpose. Change them the way you
change the model: on a branch, through a merge request that someone else approves.

> [!note]
> New to the team? Start with [onboarding.md](onboarding.md). It takes one day.

| Document | What it answers | Who keeps it current |
|---|---|---|
| [onboarding.md](onboarding.md) | What do I do on my first day, and where is everything? | the MBSE lead |
| [conventions/naming.md](conventions/naming.md) | How do I name packages, definitions, usages, requirements and branches? | the MBSE lead |
| [conventions/markings.md](conventions/markings.md) | How is the model marked, and what may go where? | the MBSE lead, with the security officer |
| [conventions/review-checklist.md](conventions/review-checklist.md) | What do I check when I review a model merge request? | everyone |
| [model-exchange-agreement.md](model-exchange-agreement.md) | What does the prime deliver, how, how often, and how do problems go back? | the MBSE lead and the prime's modeler |
| [adr/](adr/) | Why is the repository built the way it is? One decision per file. | whoever proposes the decision |
| [memos/templates/](memos/templates/) | Formal memos: memorandum for record, progress memo, drop disposition, DR transmittal, request for enablers | the MBSE lead |

## Decisions recorded so far

| ADR | Decision |
|---|---|
| [0001](adr/0001-record-decisions.md) | Record decisions in the repository |
| [0002](adr/0002-prime-boundary.md) | The prime's model enters only through the vendor branch |
| [0003](adr/0003-results-schema.md) | One results file format for every verification verdict |

## What is not here

- **Generated documents.** The pipeline writes those into `docs/` from the model (`model.pl docs`). Never edit them
  by hand: the `docs` job fails when they differ from what the model generates.
- **Meeting notes and status.** Those live in the journal (stand-ups, sprints) and in GitLab issues.
