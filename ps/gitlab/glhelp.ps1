# gitlab-help.ps1 -- the help texts of bin/gitlab.pl (generated; the program is named gitlab.cmd here)
$script:GLHELP = NewH
$script:GLHELP[''] = @'
usage: gitlab.cmd [--url URL [--token-env VAR] [--sudo] | --local DIR] [--project PATH] [--as USER]
                 [--now ISO] [--dry-run] [--no-cache] COMMAND ...

  setup FILE                     apply a project file: settings, members, labels, sprints, protection, approvals
  setup --diff FILE              compare the project file with the live project (read only; exit 1 on drift)
  sprints START COUNT [--weeks 2] [--prefix "Sprint "]       milestones for two-week sprints
  issue new|list|show|close|reopen|note|link|label ...       issues (templates, quick actions)
  mr new|list|show|approve|merge|note|resolve ...            merge requests
  pipeline run|list|show ...                                  pipelines and their jobs
  tag NAME REF [--message M]     an (annotated) tag; protected tags need the right role
  release TAG [--notes FILE] [--name N] [--milestone M]       a release with Markdown notes
  wiki put TITLE FILE | wiki list | wiki show TITLE           wiki pages
  export DIR [--since DATE] [--until DATE]                    CSVs: ci_jobs, mrs, issues, defects, tracker/
  package put NAME VERSION FILE | get NAME VERSION FILE [DEST] | list   the Generic Package Registry
  pages                          where the project's GitLab Pages site is (published by a `pages` job)
  env list | env deployments [NAME]                           environments and their deployments
  schedule new|list|run|delete|due|next ...                   cron pipeline schedules (gitlab.cmd help schedule)
  analytics [--since D] [--until D] [--by sprint|week|month] [--csv DIR]   value stream, DORA, CI/CD, MRs, issues
  board list                     the issue boards: lists in order and the milestone scope ([boards] in setup)
  status list | set IID NAME     the work-item statuses ([statuses] in setup; GitLab 18.2+) and an item's state
  backlog import FILE | export FILE                           a backlog workbook (.xlsx/.csv) <-> epics, issues, tasks
  iteration list [--group G]     the group's iteration cadence and its iterations ([iterations] in setup)
  insights [FILE]                the .gitlab/insights.yml setup generates from the project file (no server needed)
  terraform [FILE] [--out DIR]   the project file as Terraform/OpenTofu for the gitlab provider (no server needed)
  windchill intake FILE.csv | status [--csv FILE]            Windchill requests -> issues; progress back (help windchill)
  trigger new|list|run ...       pipeline trigger tokens: another system starts a pipeline (gitlab.cmd help trigger)
  token deploy new|list ...      deploy tokens: a scoped credential for a machine (gitlab.cmd help token)
  ci [OPTIONS]                   run .gitlab-ci.yml here, offline (gitlab.cmd help ci)
  flow init|start|publish|finish|released|vendor|sync|take   gitflow in the current clone (gitlab.cmd help flow)
  user USERNAME [--name N] [--email E]                        create a user (emulator: any; server: admin token)
  help [COMMAND]

--dry-run prints each request that would change something (METHOD /api/v4/... {json}) and sends or
changes nothing; reads still answer. It works with both backends (flow refuses it: flow pushes with git).
Backends: --local DIR is the offline emulator (state in DIR/gitlab.json); --url talks to a GitLab server
with the token in $GITLAB_TOKEN (--token-env VAR to change; --sudo acts as --as USER with an admin token).
Defaults from the environment: GITLAB_URL, GITLAB_LOCAL, GITLAB_PROJECT, GITLAB_USER.

'@
$script:GLHELP['setup'] = @'
gitlab.cmd setup FILE
  Apply a project file (tools/gitlab/templates/project.conf is the annotated example). Sections:
    [project]    path = group/name, default_branch, merge_method, squash_option,
                 only_allow_merge_if_pipeline_succeeds, only_allow_merge_if_all_discussions_are_resolved,
                 remove_source_branch_after_merge, visibility
    [members]    user = guest|reporter|developer|maintainer|owner
    [branches]   NAME = push:none|developer|maintainer merge:... force:no codeowners:yes
    [tags]       PATTERN = create:maintainer
    [labels]     NAME = #RRGGBB | description
    [milestones] sprints = START COUNT WEEKS        or  TITLE = START DUE | description
    [approvals]  RULE NAME = N user user ...
    [variables]  KEY = VALUE [| protected] [| masked]
    [schedules]  DESCRIPTION = CRON | REF | TZ | K=V ...
    [boards]     NAME = LABEL LABEL ... [| milestone=started|upcoming|none|any|TITLE] [| iteration=current]
                 [| sprint=current]  (sprint=current: milestone started, or iteration current when
                 [iterations] use = iterations)
    [iterations] group = PATH   use = milestones|iterations   TITLE = START WEEKS [IN_ADVANCE] [| automatic roll-over]
    [insights]   file = .gitlab/insights.yml   weeks = 12   (the Insights dashboard, generated)
    [statuses]   NAME = #RRGGBB | CATEGORY | description [| default-open|default-closed|default-duplicate]
                 group = PATH (top level)   mode = statuses|labels   marks = [#RRGGBB] REDO PASS SYNC
    [windchill]  the Windchill intake mapping (read by gitlab.cmd windchill, not by setup)
    [backlog]    levels = Tome, Epic, Story, Task   group = PATH   sprint = project|epic   (read by gitlab.cmd backlog)
  A section may appear more than once; its lines add up (a second [labels] adds labels).
  Boards: setup creates a missing board, adds the missing label lists, puts them in the file's order and
  scopes the board to the milestone (Premium/Ultimate; on Free it warns and the board shows every milestone).
  Iterations: GitLab keeps iteration cadences on the GROUP and changes them only through GraphQL; setup needs
  the group path (group =, default the project's namespace) and Maintainer on it. [milestones] stay the
  fallback: use = milestones (default) or iterations decides what sprint=current and analytics --by sprint use.
  Statuses: GitLab 18.2+ (GA 18.4), Premium/Ultimate, on the top-level group: setup sets the lifecycle's
  statuses and defaults through GraphQL and never removes one; a board list may be status:NAME. On older GitLab
  or Free it warns; mode = labels makes state::NAME scoped labels instead. marks are labels, not states.
  Insights: setup writes .gitlab/insights.yml when FILE is the repository's .gitlab/project.conf (or --repo
  DIR); it never commits it: commit it through a merge request, or --commit makes a branch and the MR.
  Creates the project if it does not exist. Safe to re-run: labels and protections are updated in place.
gitlab.cmd setup --diff FILE
  Read only: compare the project file with the live project and print each difference, as
  "[section] name: file X, live Y", "missing" or "live only". Exit 1 when anything differs (drift).
gitlab.cmd setup FILE [--repo DIR] [--commit]
  --repo DIR writes .gitlab/insights.yml into that clone; --commit puts it on a feature/insights-DATE
  branch with a merge request to the default branch (the file still needs a review and a merge).
gitlab.cmd --dry-run setup FILE
  Print the requests setup would send (METHOD /api/v4/... or /api/graphql {json}) and change nothing.

'@
$script:GLHELP['sprints'] = @'
gitlab.cmd sprints START COUNT [--weeks 2] [--prefix "Sprint "]
  COUNT milestones of WEEKS weeks from START (a Monday); each is due on the Friday of its last week.

'@
$script:GLHELP['issue'] = @'
gitlab.cmd issue new TITLE [--template NAME|FILE] [--description TEXT] [--label L]... [--milestone M]
                          [--assign USER]... [--type issue|task|incident] [--weight N] [--due DATE]
gitlab.cmd issue list [--state opened|closed|all] [--label L]... [--milestone M] [--type T]
gitlab.cmd issue show IID | close IID | reopen IID
gitlab.cmd issue note IID TEXT | --file FILE     a comment; /label /milestone /assign /estimate /spend /close ... run
gitlab.cmd issue link IID TARGET [--type relates_to|blocks|is_blocked_by]
gitlab.cmd issue label IID [--add L]... [--remove L]...
  --template NAME reads .gitlab/issue_templates/NAME.md of the current directory (or a file path).

'@
$script:GLHELP['mr'] = @'
gitlab.cmd mr new --source BRANCH [--target BRANCH] --title TITLE [--template NAME|FILE] [--description TEXT]
                 [--label L]... [--milestone M] [--reviewer USER]... [--keep-branch]
gitlab.cmd mr list [--state opened|merged|closed|all] | show IID | approve IID | merge IID
gitlab.cmd mr note IID TEXT [--resolvable] | resolve IID
  --target defaults to the project's default branch. merge refuses, with GitLab's reason, until the
  pipeline succeeds, the approvals (and code owners) are in and discussions are resolved.

'@
$script:GLHELP['pipeline'] = @'
gitlab.cmd pipeline run REF [--source web|push|schedule] [--var K=V]...
gitlab.cmd pipeline list [--ref REF] [--status S] | show ID
  show lists the jobs; with --local, each job's log path too.

'@
$script:GLHELP['tag'] = @'
gitlab.cmd tag NAME REF [--message M]
  An annotated tag when --message is given. On the emulator, a tag pipeline runs.

'@
$script:GLHELP['release'] = @'
gitlab.cmd release TAG [--notes FILE] [--name NAME] [--milestone M]...
  A release for an existing tag; the notes file is Markdown.

'@
$script:GLHELP['wiki'] = @'
gitlab.cmd wiki put TITLE FILE | wiki list | wiki show TITLE

'@
$script:GLHELP['export'] = @'
gitlab.cmd export DIR [--since YYYY-MM-DD] [--until YYYY-MM-DD]
  Writes DIR/ci_jobs.csv (ts,job,branch,result,minutes), mrs.csv, issues.csv, defects.csv and
  tracker/sprint-N.csv (id,status,blocked_days,blocker) -- the inputs of bin/status-metrics.pl.

'@
$script:GLHELP['ci'] = @'
gitlab.cmd ci [--file .gitlab-ci.yml] [--event push|merge_request_event|tag|schedule|web|trigger] [--branch B]
             [--target B] [--tag T] [--var K=V]... [--job NAME] [--manual] [--list]
  Runs the pipeline locally in the current directory (lib/GitLabCI.pm). --list shows the jobs it would run.

'@
$script:GLHELP['flow'] = @'
gitlab.cmd flow init                              develop from main (first commit on an empty repo)
gitlab.cmd flow start feature|release|hotfix NAME a branch from develop (hotfix: from main)
gitlab.cmd flow publish                           push the current branch (the emulator runs its pipelines)
gitlab.cmd flow finish [--title T] [--template NAME|FILE] [--description TEXT] [--label L]... [--milestone M]
                      [--reviewer U]...          push and open the MR (feature -> develop, release/hotfix -> main)
gitlab.cmd flow released IID [--notes FILE] [--tag NAME]   after a release/hotfix MR merged: tag main
                                                 (sha256 of docs/ in the message), release, back-merge MR
gitlab.cmd flow vendor DROPDIR VERSION            commit the converted prime drop on vendor/prime, then merge it
                      [--layout-map FILE]       (default: the repository's .ci/layout.map, if it has one)
                                                 into feature/drop-VERSION (conflicts are listed, not resolved);
                                                 a clean merge also raises .ci/outline-max to the drop's outline
                                                 count, in its own commit, so the allowance is reviewed with the MR
gitlab.cmd flow allowance VERSION                 the same, after you resolved a drop's conflicts and committed
gitlab.cmd flow take ours|theirs PATH...          resolve conflicted files wholesale
gitlab.cmd flow sync                              fetch; fast-forward local main and develop
  Run inside a clone of the project. Branch names: main, develop, feature/, release/, hotfix/, vendor/prime.

'@
$script:GLHELP['user'] = @'
gitlab.cmd user USERNAME [--name NAME] [--email EMAIL]

'@
$script:GLHELP['package'] = @'
gitlab.cmd package put NAME VERSION FILE        upload to the Generic Package Registry (sha256 recorded)
gitlab.cmd package get NAME VERSION FILE [DEST]  download (the emulator checks the sha256)
gitlab.cmd package list
  Names: letters, digits and . _ -; versions also +. Use it for released baselines: the docs bundle, the drop, the SBOM.

'@
$script:GLHELP['trigger'] = @'
gitlab.cmd trigger new DESCRIPTION | trigger list | trigger run TOKEN REF [--var K=V]...
  Pipeline trigger tokens: another system (the prime's Jenkins) starts a pipeline with CI_PIPELINE_SOURCE "trigger"
  and its variables (e.g. DROP_VERSION). Maintainers create them; a triggered pipeline runs as the token's owner.

'@
$script:GLHELP['token'] = @'
gitlab.cmd token deploy new NAME [--scope S]... [--expires YYYY-MM-DD] | token deploy list
  Deploy tokens: a credential for a machine outside the project, limited to its scopes (read_repository,
  read_registry, write_registry, read_package_registry, write_package_registry). Give the prime's Jenkins
  write_package_registry only, with an expiry date.

'@
$script:GLHELP['pages'] = @'
gitlab.cmd pages
  The Pages URL and, on the emulator, the folder: a job named `pages` that succeeds on the default branch
  publishes its public/ artifact there.

'@
$script:GLHELP['schedule'] = @'
gitlab.cmd schedule new DESCRIPTION --cron "MIN HOUR DOM MON DOW" --ref BRANCH [--tz ZONE] [--var K=V]... [--inactive]
gitlab.cmd schedule list                 id, cron, zone, ref, next run (UTC), owner, last pipeline
gitlab.cmd schedule run ID               run it now ("Run pipeline schedule"); the next run time does not change
gitlab.cmd schedule delete ID
gitlab.cmd schedule due --until ISO      emulator only: run every scheduled pipeline due up to ISO, in time order
gitlab.cmd schedule next "CRON" [--tz ZONE] [--from ISO] [-n N]   the next N run times (check a cron line)
  Cron: five fields; *, lists (1,15), ranges (1-5), steps (*/15), names (mon-fri, jan); @daily @weekly ...
  Zones: UTC (default), fixed offsets (+05:30, -0400), America/New_York and the other US zones with daylight
  saving. A job sees $CI_PIPELINE_SOURCE == "schedule" and the schedule's variables.

'@
$script:GLHELP['analytics'] = @'
gitlab.cmd analytics [--since YYYY-MM-DD] [--until YYYY-MM-DD] [--by sprint|week|month] [--csv DIR]
                    [--sprints-from milestones|iterations] [--group PATH]
  From the REST data every tier has (MRs with commits and notes, pipelines and jobs, issues, deployments,
  releases, milestones):
  1. value stream: issue created -> first commit -> MR opened -> first review -> merged -> issue closed
     (median and p85 hours per stage; an MR links its issues with "Closes #N")
  2. DORA for a model repo: deployments = pages deployments + releases; lead time = first commit -> merged
     on the default branch; change failure rate = MRs labelled fix-forward or titled "Revert..." / other
     merges; time to restore = default-branch pipeline red -> next green
  3. CI/CD: success rate, median and p85 duration, failures per job, the trend per period
  4. merge requests: merged per period, time to merge, review turnaround, per author
  5. issues: opened and closed per period by type:: label; open-issue age
  --by sprint uses the "Sprint N" milestones' dates, or the group's iterations (Sprint N = the sequence) when
  --sprints-from iterations or [iterations] use = iterations in .gitlab/project.conf. --csv DIR also writes
  one CSV per table.

'@
$script:GLHELP['terraform'] = @'
gitlab.cmd terraform [PROJECT FILE] [--out DIR] [--url URL] [--state NAME]
  The project file as Terraform/OpenTofu for the gitlabhq/gitlab provider (~> 19.4): versions.tf (provider pin,
  an empty backend "http" for GitLab-managed state), project.tf (the project, adopted by an import block; members,
  labels, milestones, protected branches and tags, approval rules, CI/CD variables, schedules, boards),
  variables.tf (CI/CD variable values as Terraform variables, never in the files) and backend.hcl (the state
  URLs for `tofu init -backend-config=backend.hcl`). An alternative to setup for a platform team that runs
  GitLab as code. Not in the provider, so left to setup: [iterations], [insights], [statuses]. Needs no GitLab and no
  terraform binary; without --out the files go to stdout. --url is the GitLab server (default GITLAB_URL).
  CI: tools/gitlab/terraform/gitlab-ci.tofu.yml (plan in the MR, apply on the default branch; off by default).

'@
$script:GLHELP['insights'] = @'
gitlab.cmd insights [PROJECT FILE]
  Print the .gitlab/insights.yml that setup generates from the project file's [labels], [windchill] and
  [insights] (default: .gitlab/project.conf here or above). Needs no GitLab. Analyze > Insights (Ultimate)
  reads the file from the default branch: setup writes it into the repository, you commit it by merge request
  (or setup --commit opens one).

'@
$script:GLHELP['iteration'] = @'
gitlab.cmd iteration list [--group PATH] [--conf FILE]
  The group's iteration cadences and their iterations (Sprint N = the iteration's sequence), and whether the
  kit's sprints come from milestones or iterations ([iterations] use). Cadences live on the group, not the
  project: setup makes them from [iterations] and needs Maintainer on that group.

'@
$script:GLHELP['status'] = @'
gitlab.cmd status list [--conf FILE]
gitlab.cmd status set IID NAME [--conf FILE]
  list: the lifecycle's statuses on the top-level group (name, category, color, the defaults) -- or, with
  [statuses] mode = labels, the state:: labels. set: an issue's or task's status; done and canceled ones close it
  (mode = labels: the state::NAME label, closing DONE and DROP). Statuses need GitLab 18.2+, Premium or Ultimate.

'@
$script:GLHELP['backlog'] = @'
gitlab.cmd backlog import FILE.xlsx|FILE.csv [--conf FILE] [--levels L1,L2,L3,L4] [--group PATH] [--dry-run]
  Load a backlog workbook (sheet Backlog, or the first) or CSV into GitLab, parents first: the first level
  (Tome) -> an epic on the group, the second (Epic or Epoch) -> a child epic, Story -> an issue under its epic
  (weight = Days, due = the end of its planned sprint, milestone "Sprint N", label team::Team, the Marks as
  labels), Task -> a task under its story (estimate = Days). Status sets the work-item status ([statuses]), the
  state:: label (mode = labels), or with no [statuses] closes DONE and DROP. Items are titled "ID Title"; a
  re-import skips IDs already there (it creates, never edits). Ends with:
    backlog: N rows, E epics, I issues, T tasks created, S already there, W warnings
gitlab.cmd backlog export FILE.xlsx|FILE.csv [--conf FILE] [--levels ...] [--group PATH]
  The group's epics and the project's issues and tasks, back into the same columns (ID, Level, Parent, Title,
  Team, Epic, Sprint, Days, Done when, Model link, Status, Marks, Iteration, Assignee, Spent (d), GitLab) in
  tree order, so the backlog can be rebuilt elsewhere with import. Issues with no epic go under UNPLANNED.
  [backlog] in the project file: levels, group (default the project's group), sprint = project (Sprint N counts
  from the project's sprint 1) or epic (within each epic, sprints-per-epic, default 13), team-label (team::).

'@
$script:GLHELP['board'] = @'
gitlab.cmd board list
  Each issue board: its label lists in order and its milestone scope (any, none, upcoming, started or a
  milestone title). Boards are made by setup from the [boards] section of the project file.

'@
$script:GLHELP['windchill'] = @'
gitlab.cmd windchill intake FILE.csv [--conf FILE] [--note] [--dry-run]
  One issue per new Windchill number in a Windchill report exported as CSV (comma, tab or semicolon; UTF-8,
  UTF-16 or Windows-1252; quoted cells may hold commas and line breaks). The issue is titled "NUMBER: title",
  carries the link, requester, need date (also the due date), type, state, priority and description, and the
  labels of [windchill] labels plus the priority-map label. Rows whose state is not in `accept` are skipped.
  Safe to re-run: a number that already has an issue is skipped; if Windchill changed its title, state or
  priority since, the change is printed as drift, and --note adds it to the issue as a comment.
  Ends with: windchill: N rows, C created, S skipped, D drift
gitlab.cmd windchill status [--conf FILE] [--csv FILE|-] [--since YYYY-MM-DD]
  One row per Windchill-sourced issue: number, issue, open/closed, workflow:: column, milestone, closed date,
  merge requests that close or name it, the first release (or tag) holding the merge, and the issue URL.
  --csv writes it as CSV (CRLF, UTF-8 with BOM for Excel) to paste or import into Windchill; --since keeps
  issues updated since DATE.
  --conf defaults to .gitlab/project.conf in this directory or above; the project comes from --project or its
  [project] path. The [windchill] section maps the export's column names (tools/gitlab/templates/project.conf).

'@
$script:GLHELP['env'] = @'
gitlab.cmd env list | env deployments [NAME]
  Environments come from jobs with `environment:`; every successful run of one is a deployment.

'@
