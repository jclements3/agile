# Your first day on the model team

[[_TOC_]]

You are a systems engineer. You know requirements, interfaces, baselines and change boards. This page gets you from a
fresh laptop to your first approved model change in one day. Type every command yourself; do not paste.

> [!tip]
> Every command below runs in **Git Bash**, which comes with Git for Windows. `$KIT` is where the agile kit lives on
> your laptop, for example `export KIT=~/agile`. Put that line in `~/.bashrc` so it is set in every window.

## Morning: check your laptop (30 minutes)

1. Run the doctor. It checks Perl, git, Vim, curl, a quick self-test of the kit, GitLab and your SSH key, and changes
   nothing:
   ```sh
   perl $KIT/tools/gitlab/kickoff.pl doctor
   ```
2. For every `FAIL` line, run the `fix:` command printed under it. Then let the doctor set the recommended git settings
   (it prints each one first and never touches your name or e-mail):
   ```sh
   perl $KIT/tools/gitlab/kickoff.pl doctor --fix
   ```
3. Run the doctor again until it says `0 fail`. `WARN` lines are advice; read them.

## Late morning: practice in a sandbox (2 hours)

The kit has four practice lessons on a copy of a fictional model, Tidewater. Nothing you do there can reach the real
project. Each lesson builds its own sandbox, and `check` tells you whether you got it right:

```sh
perl $KIT/agile.pl practice 10        # your first model change: a TODO line, Vim, lint, a commit
perl $KIT/agile.pl practice check 10
perl $KIT/agile.pl practice 11        # your first merge request: the pipeline fails, you fix it, it is approved
perl $KIT/agile.pl practice 12        # a prime drop: what changed, and taking it into the model
perl $KIT/agile.pl practice 13        # your first baseline: release branch, tag, release, back-merge
```

The lesson text is in Vim: `:help agile-practice-10`. If something goes wrong, `perl $KIT/agile.pl practice reset 10`
starts the lesson over.

## Afternoon: the real project (2 hours)

1. Clone the model repository (the URL is on the project's GitLab page, under **Code**):
   ```sh
   git clone git@gitlab.example.gov:group/model.git
   cd model
   ```
2. Read [README.md](../README.md), then the [conventions](conventions/) and the [review checklist](conventions/review-checklist.md).
3. Pick a task with the `workflow::ready` label that your lead marked as a good first task. Assign it to yourself.
4. Make the change the way lesson 11 taught: a branch named after the issue, a small change, `gitlab.pl ci` locally,
   then a merge request from the **Default** template. Ask a teammate to review it.

## Where things are

| You want | Look in |
|---|---|
| The model | `model/`, in layers: `library/`, `requirements/`, `logical/`, `physical/`, `analysis/`, `verification/` |
| What the prime delivered | `imports/<version>/` and the `vendor/prime` branch |
| Where each prime package lands in `model/` | `.ci/layout.map` (change it only by merge request, before a drop) |
| Why the repository is built this way | `docs/adr/` |
| How to name things | `docs/conventions/naming.md` |
| What the pipeline checks | `.gitlab-ci.yml`, and each job's logic in `ci/job.pl` |
| Who must approve what | `CODEOWNERS` |
| The work: stories, tasks, defects, discrepancy reports | GitLab **Issues** and the **Board** |
| Generated documents, diagrams, the trace and the VCRM | the project's **Pages** site (link on the project page) |
| Help on any kit command | `perl $KIT/agile.pl help TOPIC`, or `:help agile` in Vim |

## Words you will hear

| They say | You already know it as |
|---|---|
| merge request (MR) | a change request, with the redlines attached |
| pipeline | an automated configuration audit and peer-review checklist |
| code owner approval | the responsible engineer's signature |
| protected tag `baseline-N` | a baseline |
| vendor branch, prime drop | a CDRL delivery, received and logged |
| issue | an action item |

The full list is the project wiki's **Glossary** page.
