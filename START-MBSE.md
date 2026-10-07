# Start here: MBSE DevSecOps with this kit

This page is for systems engineers who have been told to move their model from documents or Cameo
(SysML v1) to SysML v2 text in GitLab, and who have never done DevSecOps. You need Git for Windows
(it brings Perl, Git Bash, curl and Vim) and access to your organization's GitLab. You install nothing
else.

Follow the steps in order. Each one takes an hour or less. Ignore the rest of this kit for now.

## 1. Get the kit

Either take the slim MBSE download (about 2 MB, only what an MBSE team needs), or clone the whole kit.
To make the slim download yourself from a clone:

```sh
perl bin/release.pl --profile mbse          # -> release/agile-mbse-<version>.zip
```

Unzip it into `C:\Users\you\projects` (it makes the folder `agile` there: `~/projects/agile` in Git
Bash, the place the primer uses). In Git Bash, point `KIT` at it:

```sh
export KIT=~/projects/agile                   # put this line in ~/.bashrc
```

## 2. Check your laptop

```sh
perl $KIT/tools/gitlab/kickoff.pl doctor
```

Every line says PASS, WARN or FAIL, and each problem comes with the exact fix. `--fix` sets the
recommended git settings for you. It never changes your name or e-mail.

## 3. Practise offline, before touching the real project

Four lessons run entirely on your laptop, against an offline stand-in for GitLab. Each takes 30 to 45
minutes and is graded by the kit, which tells you exactly what to do next.

```sh
perl $KIT/agile.pl practice 10      # your first model change, in Vim
perl $KIT/agile.pl practice 11      # your first merge request: a red pipeline, a fix, an approval
perl $KIT/agile.pl practice 12      # a prime drop with a merge conflict
perl $KIT/agile.pl practice 13      # your first baseline and release
perl $KIT/agile.pl practice check 11   # how am I doing?
```

The lesson text is also in Vim: `:help agile-practice-10`.

## 4. Read the primer

`docs/mbse-devsecops-primer.pdf` (or `.html`) is the book. It follows a fictional three-person team,
Jim, Bob and Tom, through their first twelve weeks. Start with the **Bottom line up front** and the
**Preface**. The book marks every chapter CORE (needed in the first twelve weeks) or LATER. Its study
plan says what to read in which week, by role.

## 5. Set up your own project (week zero)

```sh
perl $KIT/tools/gitlab/kickoff.pl scaffold my-model --project mygroup/model --title "My System" \
     --levels L1System,L2Segment,L3Subsystem
perl $KIT/tools/gitlab/kickoff.pl help start      # the twelve week-zero steps; nothing runs without --yes
```

Once you know where each of the prime's packages should land in your repository, write that down as a
layout map (the new repository's `.ci/layout.map.example` explains the format; Tidewater's is
`examples/tidewater-v1/layout.map`) and pass it as `--layout-map FILE` to `scaffold` or `start`.

`start` sets up the GitLab project from a project file, pushes the starter repository, creates the
`develop` branch, the sprints and the schedules, imports the first v1 drop, starts the team's journal
and opens the first stories.

## 6. The five files to change first

| File | What you decide |
|---|---|
| `.gitlab/project.conf` | members, protected branches, labels, sprints, schedules |
| `CODEOWNERS` | who approves changes to each part of the model |
| `sysml.conf` | the model's top part and top action, level names, layers |
| `.gitlab-ci.yml` (variables) | where the kit is on the runner (`KIT`), whether a Docker runner exists |
| `.gitlab/issue_templates/` | the shape of your stories, tasks and discrepancy reports |

Each one is commented. Tidewater's versions, in `tools/gitlab/templates/`, are working examples.

## Where to look when you need more

| You want | Look at |
|---|---|
| GitLab, explained for systems engineers | `docs/GITLAB.html` |
| Every command | `perl $KIT/agile.pl help`, or `:help agile` in Vim |
| An error message explained | `perl $KIT/agile.pl help error "the message"` |
| Quick reference cards for Vim, GitLab and the v1-to-v2 port | the primer's appendices |
| The worked example, end to end | the primer's Part III; in the full kit (not the slim download), `docs/TIDEWATER.html` and `docs/tidewater/` |
| A local AI assistant, and the approvals first | `docs/OLLAMA.md` |

Tidewater, its people and every number about it are fictional. The tools, templates and commands are
real and tested.
