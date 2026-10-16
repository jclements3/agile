# Glossary

[[_TOC_]]

You already know how to control a configuration. You have run CCBs, audited baselines, tracked action items and
delivered CDRLs for decades. GitLab does the same jobs with different words, and it does many of them automatically.
This page translates. Read the first table once; come back to the second when a word stops you.

> [!note]
> One clash to watch: in configuration management a **CI** is a *configuration item*. In GitLab, **CI** means
> *continuous integration*, the automatic checks. This wiki writes "configuration item" in full and uses "CI" only for
> the checks.

## What you already do, and what GitLab calls it

| Systems engineering / CM term | GitLab or DevSecOps term | What is the same | What is different |
|---|---|---|---|
| Configuration item | a folder or file under `model/` (one per model package) | it is under change control; it has an owner | there are many small ones, and each change is recorded line by line |
| Master copy, controlled document | the `develop` branch | the one copy everybody works from | nobody edits it directly; changes arrive only through merge requests |
| Released baseline | a **protected tag** `baseline-N` on `main`, plus a **release** with notes | frozen; cited by analyses and reviews | the server will not let anyone move or delete it, and the pipeline proves it rebuilds |
| Engineering Change Proposal (ECP), change request (CR) | **merge request** (MR) | proposes a change, shows exactly what changes, is reviewed and approved | small (days, not months), and the exact lines changed are shown side by side |
| Configuration Control Board (CCB) approval | **approval** on the MR, by the **code owners** of the changed parts | the right authority says yes before it goes in | per change, on line; nobody waits for the monthly board |
| Redlines, markups | **review comments** on lines of the MR, and **suggestions** | comments pinned to the text | the author applies a suggestion with one click |
| Configuration audit (FCA/PCA) | the **pipeline**: automatic checks on every change | checks the configuration against its rules | runs in minutes on every change, not once at the end |
| Configuration status accounting | the Git **history**, the merge log, `gitlab.pl export` | who changed what, when, under which change | complete and exact, with no one typing it up |
| Revision (Rev A, Rev B) | **commit** | one recorded change with an author and a date | there are many, each small; the commit id is the revision number |
| Revision history block | `git log`, `CHANGELOG.md` | the list of changes | generated from the work itself |
| Working draft | **branch** (a `feature/...` branch) | your copy while you work | it lives days, and Git brings your changes back in |
| Incorporating an approved change | **merge** | the change becomes part of the master copy | Git applies it line by line; it stops only where two changes touch the same lines (a **merge conflict**) |
| CDRL delivery from the prime | a **prime drop** committed on the **vendor branch** `vendor/prime` | the contractor's deliverable, received and checked | it is converted and merged into our model, keeping our own edits |
| Discrepancy / deficiency report | an **issue** with the label `type::discrepancy` | a written finding against a deliverable | tracked on a board until the drop that fixes it closes it |
| Action item | **issue** (a task or story) | owner, due date, status | visible to all, linked to the change that closes it |
| Action item tracker (spreadsheet) | **issue board** | one row per action, a status column | the status is a label, the board updates itself |
| WBS element | **epic** and **tome** labels | groups work into a hierarchy | sized by time: an epic fits in a semester, a tome in a year |
| IMS milestone, event | a **release** / baseline | a dated program event | — |
| A two-week period of work | **milestone** `Sprint N` | a time box with a list of work | GitLab calls any dated time box a milestone; ours are sprints, not IMS events |
| Data Item Description (DID), document template | **issue template**, **merge request template** | says what goes in each section | filled in on line; GitLab offers it when you create the item |
| Systems Engineering Plan, process documents | the **wiki** | how we work | short pages, versioned, changed like the model |
| Requirements traceability matrix (RTM) | the **trace** job and `docs/Traceability.md` | which requirement is satisfied and verified by what | rebuilt on every change from the model itself |
| Verification cross-reference matrix (VCRM) | `verify` relationships in `model/requirements/Verification.sysml` + results in `verification/*.csv`, the `vcrm` job | which case verifies which requirement, and its newest verdict | built by the pipeline on every change, published on the Pages site |
| Peer review, desk check | **MR review** | a second engineer reads the change | the change is small, so the review takes minutes |
| Signature block, sign-off date | **approval**, **merged at** | who approved, and when | recorded by the server, cannot be backdated |
| Distribution list | **@mentions**, notifications | who is told | people are told about what concerns them, as it happens |
| Weekly status chart | the **status metrics** from `gitlab.pl export` | progress and problems for the program | computed from the work, not typed up on Thursday night |

## GitLab and DevSecOps words

| Word | Meaning here |
|---|---|
| **DevSecOps** | Development, security and operations done together, in small changes, with automated checks. For us: every model change is small, reviewed, checked by machine and recorded, and security checks run on every change rather than at the end. |
| **Repository** (repo) | The folder of files under version control, with its full history. Ours is `tidewater/model`. |
| **Git** | The version-control program. It records every change to every file. |
| **Clone** | Your own full copy of the repository on your laptop. |
| **Commit** | One recorded change: what changed, who, when, and a message saying why. |
| **Push / pull** | Send your commits to the server / bring others' commits to your laptop. |
| **Branch** | A line of work. `develop` is the master copy; you work on your own branch and merge it back. |
| **Default branch** | The branch GitLab shows first and closes issues on: `develop`. |
| **Merge** | Bring the changes of one branch into another. |
| **Merge conflict** | Git cannot merge on its own because both sides changed the same lines. A person picks the right text. |
| **Merge request (MR)** | A request to merge your branch into `develop`, with the changes shown, a discussion, checks and approvals. Our ECP. |
| **Approval** | A reviewer's "yes" on an MR. |
| **Code owner** | The person who must approve changes to a given folder, listed in the file `CODEOWNERS`. |
| **Protected branch** | A branch nobody can change directly; only an approved MR can. `main` and `develop` are protected. |
| **Tag** | A permanent name for one exact state of the repository. `baseline-1` is a tag. |
| **Protected tag** | A tag nobody can move or delete. |
| **Release** | A tag plus release notes, shown on GitLab's Releases page. |
| **Gitflow** | The branch scheme we use: `main` for baselines, `develop` for integration, short branches for each change. |
| **Feature branch** | A short-lived branch for one task: `feature/19-stations-level-tags`. |
| **Release branch** | A branch for preparing a baseline: `release/baseline-1`. |
| **Hotfix** | A small, urgent fix to a released baseline, on a `hotfix/...` branch. |
| **Back-merge** | Merging `main` into `develop` after a release or hotfix, so nothing is lost. |
| **Vendor branch** | `vendor/prime`: exactly what the converters make of each prime drop, never edited by hand. |
| **Prime drop** | One delivery of the prime's v1 model and DOORS data (XMI, ReqIF, CSV, MANIFEST). |
| **Pipeline** | The automatic checks GitLab runs on every change: our configuration audit. |
| **Job** | One check in the pipeline, such as `lint` or `trace`. |
| **Stage** | A group of jobs that run together; stages run in order. |
| **Runner** | The machine that runs the jobs. |
| **CI/CD** | Continuous integration / continuous delivery: checking and delivering every change automatically. |
| **`.gitlab-ci.yml`** | The file that defines the pipeline, written in YAML. |
| **YAML** | A plain-text format for settings, with indentation for structure. |
| **Artifact** | A file a job keeps after it runs (a report, a count). |
| **Lint** | An automatic check of a model's structure: names resolve, nothing dangles. |
| **Grammar check** | An automatic check that each file is valid SysML v2 text. |
| **Secrets scan** | An automatic check that no password, token or key was committed. |
| **Token** | A password for a program (a script, the pipeline) instead of a person. |
| **Issue** | A work item: an action item, a story, a task, a defect, a discrepancy report. |
| **Label** | A tag on an issue or MR that says what kind it is, where it belongs, or its status. |
| **Scoped label** | A label written `key::value`; an item has only one value per key (Premium). |
| **Milestone** | A dated time box in GitLab. Ours are the sprints. |
| **Board** | Issues shown as cards in columns, one column per status label. |
| **Quick action** | A command in a comment, such as `/label ~"workflow::done"` or `/close`. |
| **Markdown** | The plain-text formatting GitLab uses in every text field: `**bold**`, `- [ ] checklist`, tables with `|`. |
| **Wiki** | The project's pages of procedures and decisions. |
| **Sprint** | Two weeks of work with a goal, planned at the start and reviewed at the end. |
| **Task** | Work of less than a week (5 points or fewer; one point is one ideal day). |
| **Story** | Several tasks that deliver something useful within one sprint. |
| **Epic** | Several stories finished within a semester (13 sprints). |
| **Tome** | Several epics finished within a year. |
| **Project** | The whole effort, years long: here, the port and its maintenance. |
| **Point** | The size of a task, in ideal person-days. |
| **Stand-up** | A 15-minute daily meeting: what I did yesterday, what I do today, what blocks me. |
| **Definition of Done** | The checklist a task or story must meet before it counts as done. |
| **Definition of Ready** | The checklist a story must meet before a sprint takes it. |
| **SysML v2 text** | The model written as text files, readable and comparable line by line, instead of a Cameo project. |
| **TODO line** | A line the converter writes for something it could not translate; a person closes it. |
| **Delta** | What changed in the prime's v1 model between two drops. |
| **Drift** | A requirement whose text differs between DOORS and the model. |
| **Orphan requirement** | A requirement nothing satisfies. |
| **Unverified requirement** | A requirement no verification case verifies. |
| **Emulator** | The kit's offline stand-in for a GitLab server, for practice and testing. |
| **Free / Premium** | GitLab's product tiers. A few features (enforced code-owner approval, epics, iterations, scoped labels) need Premium; this wiki says which, and what to do on Free. |
