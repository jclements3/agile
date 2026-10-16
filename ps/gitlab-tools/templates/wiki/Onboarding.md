# Onboarding

Your first day and your first week on the Tidewater model team. You do not need to have used Git, GitLab or DevSecOps
before; nobody on this team had. Every new word is in the [Glossary](Glossary).

> [!tip]
> The fastest way to learn this is one small change, start to finish, with someone beside you. Do the first task below
> with Tom or Bob on a call.

## What you already know

You have controlled configurations, reviewed changes, run audits and tracked action items. Here they are in GitLab:

| You know | Here it is |
|---|---|
| The controlled master copy | the `develop` branch of the repository `tidewater/model` |
| A change request / ECP | a **merge request** (MR): your proposed change, shown line by line |
| CCB approval | an **approval** on the MR from the owner of what you changed |
| A configuration audit | the **pipeline**: checks the server runs on every MR, in minutes |
| An action item | an **issue**, assigned to you, on the sprint board |
| A released baseline | a **tag** `baseline-N` that nobody can move |

## Day 1: accounts and the laptop

1. **GitLab account.** Jim adds you to the project `tidewater/model` (as a *developer*; *maintainer* if you cut
   baselines or manage drops).
2. **Git for Windows.** It is already on the standard laptop image. It brings Git (the version-control program), a
   terminal called Git Bash, and Perl (which runs the kit's model tools). Nothing else to install.
3. **Get your own copy of the model** (a *clone*). Open Git Bash:
   ```sh
   git clone https://gitlab.example.com/tidewater/model.git     # your copy, with all its history
   cd model
   git config core.autocrlf false                               # keep files byte for byte as they are
   export KIT=/c/Users/you/agile                                 # where the agile kit is on your laptop
   ```
4. **Check the model on your laptop**, the same way the server will:
   ```sh
   perl $KIT/tools/sysml/model.pl lint      # the structure check; it should end: errors=0 warnings=0
   perl $KIT/tools/sysml/model.pl install-hooks   # repeats that check every time you commit
   ```
5. **Look around GitLab** (the web page): *Plan > Issue boards* (the sprint board), *Code > Merge requests* (changes in
   review), *Build > Pipelines* (the audits), *Plan > Wiki* (this page).

## Days 2 to 5: your first task, start to finish

Pick a task on the board in the ~"workflow::ready" column with the label ~"type::task", and assign it to yourself.
Then:

| Step | What you do | What it is like |
|---|---|---|
| 1 | `perl $KIT/bin/gitlab.pl flow start feature 42-short-name` | check out a working copy of the master |
| 2 | Edit the `.sysml` file in Vim (or any editor) | mark up your copy |
| 3 | `perl $KIT/tools/sysml/model.pl lint` | self-check before you submit |
| 4 | `git add -A` then `git commit -m "What you changed"` | record the revision, with a reason |
| 5 | `perl $KIT/bin/gitlab.pl ci` | run the audit yourself first |
| 6 | `perl $KIT/bin/gitlab.pl flow finish --title "What you changed"` | submit the change request (the MR) |
| 7 | Answer the reviewer's comments, push fixes | respond to redlines |
| 8 | The owner approves; the MR merges | the CCB approves and the change is incorporated |

When the MR merges, your task issue closes by itself (the MR says "Closes #42").

## Read, in this order

1. [Glossary](Glossary)
2. [Definition of Ready](Definition-of-Ready) and [Definition of Done](Definition-of-Done)
3. [Gitflow](Gitflow)
4. [Drop Intake Runbook](Drop-Intake-Runbook)
5. The kit's `docs/GITLAB.html` (the long version of this wiki)

## Who to ask

| About | Ask |
|---|---|
| What to work on, priorities, the prime | @jim |
| The model, SysML v2, the converter's TODO lines | @bob |
| Git, branches, the pipeline, a red check you do not understand | @tom |

> [!note]
> A red check is not a failure on your part. It is the audit doing its job before the change reaches the master
> copy, which is exactly where we want problems found. Read the job's log, or ask Tom.
