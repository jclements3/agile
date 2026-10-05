# Quick reference: the agile kit

This chapter is generated from the kit's own help (vim/doc/agile.txt) by `perl agile.pl help --md`; the same text is in Vim (`:help agile`), on the command line (`perl agile.pl help TOPIC`) and in docs/HELP.html. It is the part you need at the keyboard: the runbooks, the commands and keys used every day, and the errors people actually hit. A name in code type such as `agile-daily-compile` is a help topic: `perl agile.pl help agile-daily-compile` prints it.

## How do I...?

### First day after cloning the kit

You need Git for Windows (Git Bash, its Perl and its Vim). Nothing else.

1. Get the kit. From a clone:

```
mkdir -p ~/projects && cd ~/projects
git clone URL agile
```

or from a release zip (`agile-release`): unzip it, then check it:

```
sha256sum -c agile-v1.0.zip.sha256
```

2. Check that it works on this machine (each line ends "all N passed"):

```
cd ~/projects/agile
for t in tests/*.t; do perl $t | tail -1; done
```

3. Set up Vim and a shell alias (`agile-vimrc`, `agile-alias`):

```
echo 'syntax on'                               >> ~/.vimrc
echo 'source ~/projects/agile/vim/scrum.vim'   >> ~/.vimrc
echo "alias daily='perl ~/projects/agile/bin/daily.pl'" >> ~/.bashrc
source ~/.bashrc
```

Tell git who you are once, or daily.pl commit cannot commit:

```
git config --global user.name "Your Name"
git config --global user.email you@example.com
```

4. Build the demo project and look at the cockpit (`agile-demo`):

```
perl sim/training.pl --fast
perl agile.pl
```

5. Make your own project (`agile-first-project`):

```
daily.pl init ~/scrum/myprogram
cd ~/scrum/myprogram
vim scrum.conf
```

6. Do practice lesson 1 (`agile-practice-1`):

```
perl ~/projects/agile/agile.pl practice 1
```

You are done when: the tests all pass, `vim` then `:help agile` opens this file, `perl agile.pl` opens the demo cockpit in the browser, and `perl agile.pl practice check 1` says "lesson 1: done".

### Run the daily townhall

One Teams call for every team, 08:30 to 08:45; people type Y/T/B in the chat. The whole loop is in `agile-ytb`; the operating model is docs/WORKFLOW.html section 4. Times are a suggestion.

1. 08:05, five minutes of recall (`agile-daily-drill`):

```
:SDrill            (or: daily.pl drill)
```

2. 08:10, draft today's statuses from yesterday's (`agile-daily-propose`):

```
daily.pl propose
```

Paste the block into the meeting chat when it opens.

3. 08:15, cards for each member, optional (`agile-daily-cards`):

```
daily.pl cards               (--send mails them through Outlook)
```

4. 08:30, attendance from the calendar, optional (`agile-daily-attend`):

```
daily.pl attend
```

5. 08:30-08:45, lint the chat while people are still on the call:

```
:STown                       (\sw)
```

In Teams: CTRL-A CTRL-C in the meeting chat. In Vim: \\sp pastes and lints. \\sy puts the replies on the clipboard; CTRL-V them into the chat. :SSend Name opens a 1:1 chat with that person's reply filled in.

6. 08:45, download the meeting's attendance report (Teams: Attendance tab) to standups/DATE-attendance.csv, then:

```
:SJoined                     (daily.pl joined)
```

7. After the call, the two minutes at the keyboard:

```
:SAnswers                    (daily.pl answers --assume)
:STally                      only if there were #est or #vote rounds
```

Open today's stand-up file (:SNew), uncomment the suggested lines you accept (done, unblock, punt, hold, pass), add anything else, then:

```
:SDry                        (\sd) shows what compile would write
:SCompile                    (\sc)
:SReport                     (\sr)
daily.pl health
:SDraft                      or daily.pl brief, on mail days
:SCommit
```

Or all of step 7 after the edits in one go: daily.pl all --draft

You are done when: `daily.pl status` says "no pending stand-up files", the sprint line shows today's done points, and `git log -1` in the project says "standup DATE".

See also: `agile-daily-lint`, `agile-daily-answers`, `agile-ack`, `agile-howto-publish`.

### Plan a sprint (Day 1)

1. See what is ready:

```
daily.pl backlog TEAM        each team's backlog, by priority then age
daily.pl velocity            what each team has been finishing
```

2. Make today's file and write the plan, one section per team:

```
:SNew
```

Under each "== Team" line:

```
sprint 7
cap 24
commit B-13 Ann Lee
commit B-1221                last sprint's carryover comes back with commit
new! B-16 2 Spike on track fusion p:1 e:"B1 Fire Control" o:"Cy Ray"
```

The sprint number can be on the second line of the file for all teams.

3. Check the plan before you write it:

```
:SDry
daily.pl sprint 7            after compile: Load% per team
```

Load over 100% turns a team amber, over 110% red.

4. Write it and publish:

```
:SCompile
:SReport
:SCommit
```

You are done when: `daily.pl sprint` shows the new sprint with every team's Load% at or under 100%, `daily.pl members` shows no "unassigned" line, and `daily.pl status` says "sprint 7: 0/N ... done".

See also: `agile-verb-commit`, `agile-verb-cap`, `agile-verb-sprint`.

### Close a sprint: review and report (Day 14)

1. See what is still open:

```
daily.pl sprint
daily.pl blocked
```

2. After the demo, sweep every open task in today's file (:SNew), per team:

```
done B-11 B-121
carry B-1221                 not finished: to next sprint's planning
drop B-23                    out of the sprint
redo B-101 demo found the reset mail unsent
note retro: pair on the ICD next sprint
```

3. Compile and write the reports:

```
:SDry
:SCompile
daily.pl review              the sprint report, reports/sprint-N-report.*
daily.pl report
daily.pl rollup              on the first review of a month
```

4. Commit and mark the close:

```
daily.pl commit
git tag sprint-7
```

You are done when: `daily.pl sprint 7` shows Open 0 for every team, reports/sprint-7-report.html exists, and `git status` in the project is clean.

See also: `agile-daily-review`, `agile-daily-velocity`, `agile-howto-planning`.

### Refine the master backlog (Day 9)

1. Intake new work to the master backlog, in today's file:

```
== Master
new M-2 8 Cross-segment timing budget p:1 e:"E1 Engineer" t:"E Systems"
```

2. Hand tasks to teams, retire stale ones:

```
== SEI
refine M-1                   master backlog -> SEI's backlog
prune E-12223 merged into E-12222
```

3. Size them in the townhall with #est rounds (`agile-est-vote`), then:

```
:STally                      writes est lines into today's file
```

Uncomment the est lines you accept, then :SDry and :SCompile.

You are done when: `daily.pl backlog` (the master backlog) holds only what you mean to keep, and `daily.pl backlog TEAM` lists the refined tasks with sizes.

### Add a person or a team

1. A person, name exactly as Teams shows it:

```
daily.pl roster add "Lee, Ann" ann.lee@example.com Alpha Lead ACME
daily.pl roster              lists and checks against the journal
```

2. A team appears when a task is filed under it: a "== Gamma" section with a new line, compiled. Give it a capacity with cap at the next planning.

3. Add the new people to the townhall invitation:

```
daily.pl invite --dry        then without --dry to open it in Outlook
```

You are done when: `daily.pl roster` ends ", roster and journal agree".

### Write the weekly A-Z metrics report

The 26 status metrics (A to Z) of a SysML v2 model under the pipeline, collected from the model's git repository and its exports (`agile-status-metrics`; definitions in docs/STATUS-METRICS.html). To see it work first: perl sim/status-metrics-sim.pl ~/sm-demo builds the 12-week Halberd example (repo, exports, metrics.json, history.jsonl).

1. Once: write metrics.json (repo, exports, segments, totals; Appendix A of docs/STATUS-METRICS.html, or copy the one the simulation writes) and freeze the denominators from the legacy exports:

```
perl bin/status-metrics.pl init --config metrics.json --xmi legacy.xmi --reqif export.reqif
```

2. Every working day, after the day's merges (a scheduled task or by hand):

```
perl bin/status-metrics.pl collect --config metrics.json --history history.jsonl
```

One snapshot is appended to history.jsonl. --as-of DATE collects a past day.

3. Friday, the report:

```
perl bin/status-metrics.pl report --config metrics.json --history history.jsonl --out report
```

It writes report/status-weekly.md (the A-Z table), report/status-daily.csv (open in Excel) and report/dashboard.json.

4. The dashboard: open docs/STATUS-DASHBOARD.html in Edge, paste dashboard.json into the "Data (JSON)" panel and press Apply.

5. For the status memo, paste rows of status-weekly.md into memo.md (`agile-howto-memo`).

You are done when: report/status-weekly.md has this week's column, the dashboard shows today's date, and history.jsonl has one line per working day.

### Port one segment from SysML v1 to v2

The legacy model is a Cameo/MagicDraw XMI export; the target is SysML v2 text under model/SEGMENT/ in the model's git repository. The full guide is docs/SYSML-PORT.html; the tools are `agile-xmi2sysml`, `agile-sysml` and `agile-model-pl`. Practice it: `agile-practice-8`.

1. Export from Cameo: File \> Export To \> Eclipse UML2 (v5.x) XMI File, with stereotype applications included; save it as exports/DATE-legacy.xmi, outside the model repo.

2. Read the mapping report first (unmapped types, stereotypes not converted, type references not resolved):

```
perl ~/projects/agile/bin/xmi2sysml.pl --report exports/DATE-legacy.xmi
```

3. Convert into a branch, grammar-checked:

```
cd model-repo
git switch -c port/SEGMENT
perl ~/projects/agile/bin/xmi2sysml.pl --out ../scratch --check ../exports/DATE-legacy.xmi
cp -r ../scratch/SEGMENT model/
```

(Convert into a scratch directory and copy only the segment being ported: a re-run overwrites hand edits. Requirements come out as one-line requirement usages, the form status-metrics counts; --req-style def writes requirement def blocks instead.)

4. Work the TODO lines (each names the v1 type and xmi:id):

```
:vimgrep /TODO/ model/SEGMENT/**/*.sysml
:copen
```

5. Check it:

```
perl ~/projects/agile/tools/sysml/sysml.pl check model/SEGMENT/*.sysml
perl ~/projects/agile/tools/sysml/model.pl lint
perl ~/projects/agile/tools/sysml/model.pl check
```

In Vim: \\mx this file, \\ml the model, \\mk the outline (`agile-vim-sysml`).

6. Commit the segment and merge through the gate:

```
git add -p model/SEGMENT
git commit -m "port: SEGMENT from legacy.xmi DATE"
```

You are done when: sysml.pl check and model.pl lint exit 0 ("errors=0"), :vimgrep /TODO/ finds none you have not accepted, and the segment is committed.

### Import a DOORS export

DOORS requirements become SysML v2 requirements carrying their doorsId (`agile-reqif2sysml`; details in docs/SYSML-PORT.html).

1. Export from DOORS: File \> Export \> ReqIF (a .reqif or .reqifz) with Object Heading, Object Text, the absolute number and the verification method. CSV is the fallback (columns Object Identifier, Object Level, Object Heading, Object Text, Verification Method).

2. Look first:

```
perl ~/projects/agile/bin/reqif2sysml.pl --report exports/DATE-system.reqif
```

3. Convert into the model repo; DOORS drops the module prefix from the absolute number, so put it back with --id-prefix:

```
perl ~/projects/agile/bin/reqif2sysml.pl --id-prefix SYS- --out model --layout "_reqs/{pkg}.sysml" --check exports/DATE-system.reqif
```

From CSV: add --csv and --col id="ID" --col text="Requirement" for columns with other names.

4. The trace against the model (metrics C, F, G, I: linked, orphans, unverified, completeness):

```
perl ~/projects/agile/bin/reqif2sysml.pl --report --model model exports/DATE-system.reqif
```

5. Commit the requirements files. You are done when: the requirement files pass sysml.pl check, and the --report --model run lists the orphans and unverified ids you will work.

### Write a status memo

1. Gather the facts (each prints text you can paste):

```
daily.pl status
daily.pl quad
daily.pl health
```

2. Write memo.md in Vim: one paragraph per point, lists for sub-points, "# SUBJECT" for a centred heading. Mark portions if your program does: {CUI}phrase{/}. In Vim, :r !daily.pl quad pulls text into the buffer.

3. Render it (`agile-memo`):

```
perl ~/projects/agile/tools/memo/md2memo.pl memo.md > memo.pdf
perl ~/projects/agile/tools/memo/md2memo.pl --plain memo.md > memo.txt
```

From Vim: :!perl ~/projects/agile/tools/memo/md2memo.pl % \> memo.pdf

You are done when: memo.pdf opens in Edge with numbered paragraphs (1. a. (1)) and, when marked, the banner on every page.

### Publish the reports and the status mail

1. Check the marking set-up before anything leaves your desk:

```
daily.pl check
```

2. Write every report (reports/ is regenerated each time):

```
daily.pl report
perl ~/projects/agile/agile.pl ~/scrum/myprogram    the cockpit page
```

3. Mail (Outlook drafts; nothing is sent until you press Send):

```
daily.pl draft               the status mail to the leads (to/cc)
daily.pl brief               the short BLUF mail to leadership
daily.pl cards --draft       one card per member (--send sends them)
```

4. Optionally put today's metrics into the stand-up meeting body:

```
daily.pl post                (--send also updates the attendees)
```

You are done when: the drafts are open in Outlook and reports/DATE-status.html matches what you are sending. If a draft is refused, read `agile-err-marking-refused`.

### Track funding and earned value

The funding journal is a separate ledger file (not the scrum journal), read by ledger.pl (`agile-ledger`). The Halberd example has one: run perl sim/halberd-gen.pl, then look at data/halberd/funding.ledger and its complete-DATE.csv files.

1. Write funding.ledger in Vim: book the funds under Assets (so the funding side of a budget is not reported as a budget row), the time-phased budgets, and the spending, e.g. weekly labor:

```
2026-10-01 Funding received
    Assets:Funding:Halberd      $500,000.00
    Income:Contract
~ Monthly from 2026-10-01 to 2027-01-01
    Expense:Labor:Halberd        $120,000.00
    Assets:Funding:Halberd
2026-10-09 Labor week 1
    Expense:Labor:Halberd         $28,000.00
    Assets:Funding:Halberd
```

("until" works as well as "to"; a budget is prorated by day at the window edges.) Check it: perl bin/ledger.pl -f funding.ledger check

2. Spending month by month, and against the budget:

```
perl bin/ledger.pl -f funding.ledger bal -M Expense --depth 3
perl bin/ledger.pl -f funding.ledger budget -M -b 2026-10-01 -e 2027-01-01
```

3. Earned value: write the percent complete per account in a CSV (complete-DATE.csv, lines "account,pct"), then:

```
perl bin/ledger.pl -f funding.ledger evm --now 2026-10-31 --complete-file complete-2026-10-31.csv
```

or give it inline: --complete Expense:Labor:Halberd=40 (repeatable).

4. When does the money run out:

```
perl bin/ledger.pl -f funding.ledger forecast --now 2026-10-31 --months 2 Assets
```

5. Put it on the cockpit: in scrum.conf set funding = funding.ledger and complete = complete-\*.csv (`agile-conf-funding`), then perl agile.pl PROJECT and open the Funding tab.

You are done when: `ledger.pl check` prints "ok", evm shows a CPI and SPI for every account (no "without a percent complete" line), forecast gives a run-out date for the funding account, and the cockpit's Funding tab shows the chart.

See also: `agile-ledger-evm`, `agile-ledger-forecast`, `agile-ledger-monthly`.

### Recover from a bad compile

A stand-up file with a mistake is rejected whole, every error listed: nothing is half-applied. Fix the lines and compile again.

1. Before compile: :SDry (daily.pl --dry compile) is free. Use it until it prints no errors. Each error names the file and line; look the message up with:

```
perl ~/projects/agile/agile.pl help error "PASTED MESSAGE"
```

2. Compiled, but one line was wrong: never edit the journal's history. Post the correction as a verb in a new file: carry what you wrongly marked done, est to the right size, commit what you dropped.

3. Compiled, and the whole file was wrong, not yet committed:

```
git diff scrum.txt            what the compile appended
git checkout -- scrum.txt
```

then delete the "# compiled ..." first line of the stand-up file, fix it, and compile again.

4. Compiled and committed:

```
git revert HEAD
```

then as in step 3: remove the "# compiled" line, fix, compile.

5. The journal itself will not load (you edited it by hand):

```
daily.pl status               the first error, with its line number
perl ~/projects/agile/bin/ledger.pl -f scrum.txt check
```

You are done when: `daily.pl status` loads without an error and says "no pending stand-up files", and `git status` is clean after `daily.pl commit`.

See also: `agile-err-not-applied`, `agile-err-already-compiled`.

### Back up and commit the project data

Each project is its own git repository (daily.pl init made it). The kit's own repository never holds journal data: data/ is ignored.

1. Every day, after compile:

```
daily.pl commit              git add -A and commit "standup DATE"
```

2. Once: a second copy on approved storage, a bare repository on a share:

```
git init --bare //server/share/scrum/myprogram.git
git remote add origin //server/share/scrum/myprogram.git
git push -u origin HEAD
```

then after each commit: git push

3. Or a single file you can copy anywhere:

```
git bundle create ../myprogram-DATE.bundle --all
```

Restore with: git clone myprogram-DATE.bundle myprogram

4. Before a big change (a hand edit of scrum.txt):

```
git tag before-edit
```

You are done when: `git status` is clean, `git log -1` shows today, and `git push` (or the bundle) is up to date. Remember the marking: the repository is marked whenever its content is (`agile-conf-banner`).

### Find help when something is unclear

1. A command or key:

```
perl agile.pl help compile          or in Vim: :help agile-daily-compile
daily.pl help lint
```

2. A word you remember:

```
perl agile.pl help search carryover
```

3. An error: copy the message and paste it:

```
perl agile.pl help error "standups/2026-10-05.txt:7: unknown verb 'don'"
```

4. The worked example: docs/TRAINING.html replays a whole sprint. You are done when: you found the section; if nothing matched, the words you searched for are worth a note in the help source (vim/doc/agile.txt).

## The commands and keys used every day

### The most used commands

```
Every day       daily.pl new | --dry compile | compile | report | commit
                daily.pl all --draft          (compile, report, draft, commit)
Townhall        daily.pl propose | lint | lint --reply | answers --assume
                Vim: \sw (:STown)  \sp paste+lint  \sy replies  :SSend Name
Looking         daily.pl status | sprint | blocked | backlog TEAM | members
                daily.pl quad | health | velocity | roadmap | epics
Sprint          daily.pl review | rollup | csv
People          daily.pl roster | roster add "Name" email Team Role Org
Mail            daily.pl check | draft | brief | cards --draft
Cockpit         perl agile.pl PROJECT
Help            perl agile.pl help TOPIC | search WORDS | error "MESSAGE"
Practice        perl agile.pl practice N | practice check N
Ledger          perl bin/ledger.pl -f FILE bal | reg | budget | evm | forecast
IDEF0           perl tools/idef0/idef0.pl lint | html | text FILE...
Memo            perl tools/memo/md2memo.pl memo.md > memo.pdf
```

vim:tw=78:ts=8:ft=help:norl:

### 4. THE STAND-UP FILE AND ITS VERBS

standups/DATE.txt is where you type. One verb per line under a "== Team" header; ; or # starts a comment. A file with any error is rejected whole.

More files on one day are fine: DATE-b.txt. Example:

```
2026-10-05
sprint 7
== Alpha
done A-11 A-12
block A-13 waiting on the ICD from SEI
new A-14 5 Login MFA p:1 e:"A1 Access" t:"A Platform" o:"Lee, Ann"
note Bob out Friday
```

```
Verb                   Does                                  Points move
done ID...             finished (passed the Definition of Done)
                                                   Committed -> Done
carry ID...            not finished; to next sprint  Committed -> Carryover
drop ID...             out of the sprint             Committed -> Removed
commit ID [OWNER]      into this sprint     backlog/carryover -> Committed
new ID PTS TITLE [p:N e:EPIC t:TOME o:OWNER]   intake  -> Backlog:Team
new! ID PTS TITLE ...  intake straight into this sprint    -> Committed
refine ID              master (or another team's) backlog -> this team's
prune ID REASON        retire a backlog task           Backlog -> Removed
est ID PTS             re-estimate (posts the difference)
assign ID OWNER        change the owner
block ID REASON        blocked (WAIT on the quad) until unblock ID
hold ID REASON         interrupted (HOLD) until resume ID
punt ID REASON         too hard as written          Committed -> Backlog
redo ID REASON         found wrong after the demo     Done -> Committed
pass ID TEAM           another team should do it   -> TEAM's Committed
sync ID ID...          coordinated across teams; they share DONE
cap N                  the team's capacity this sprint
note TEXT  risk TEXT  absent NAME...                  report only
sprint N               the sprint (top of the file, or in a section)
```

### 7. THE CHAT: Y/T/B STATUSES, #EST AND #VOTE

People post one line in the meeting chat, capital Y T B as separators, task

ids in it:

```
Y did B-11   T doing B-12   B none
```

Also accepted: "Y: ... / T: ... / B: ..." on separate lines, yesterday:

today: blockers:, and 1/2/3. A name before the Y is ignored. Lowercase y t b work only when unambiguous. A person's last message wins, so a repost replaces the first.

What lint checks: the three fields are there, in order, not empty; Y and T each name a task id; the ids exist in the journal. ERROR means the status cannot be used; warn means it parses but says little.

The replies (lint --reply) go back into the chat, or 1:1 with --private: "Did you mean: ...?" for an error, "Got it. Add the task id next time" for a warning, and with --confirm a read-back "I read your status as: ...".

### The keys

```
\sn  :SNew        today's stand-up file
\sd  :SDry        save, show what compile would write
\sc  :SCompile    save and compile
\sa  :SAll        save, compile, report, commit
\ss  :SStatus     the status line
\sr  :SReport     write the reports
\sj  :SJournal    open the journal
\st  :STally      save, tally #est/#vote rounds
\sl  :SLint       save, lint the chat (errors to the quickfix list)
\sw  :STown       the townhall tab: chat | lint table | replies
\sp               paste the clipboard into the chat and lint
\sy               the replies to the clipboard
\sm  :SDrill      the memory-drill sheet
CTRL-X CTRL-K     complete a task id from the journal (insert mode)
```

### IDEF0 in Vim

In an IDEF0 buffer (and Markdown with ```idef0 blocks):

```
\il  :IdefLint          lint this file; errors to the quickfix list
\iL  :IdefLintProject   lint every model in this directory
\iv  :IdefPlates        the plates as text in a split
\id  :IdefDump          the numbered tree
\ik  :IdefLinks         the interface table
\in  :IdefNumber        fmt --number on this file
\iu  :IdefAuto          fmt --auto on this file
\if  :IdefFollow        jump to the target of this line's < or > link
\io                     a new sibling line below, in insert mode
za zc zo                fold a subtree (folds follow the indentation)
```

## When something goes wrong

Paste any message into `perl agile.pl help error "MESSAGE"` for the full catalog; these are the ones met most often.

### no scrum.conf found here or above (run: daily.pl init)

Pattern: no scrum.conf found here or above Pattern: has no scrum.conf (run daily.pl init there first) Pattern: no such project directory Pattern: no scrum.conf here or above Pattern: no such file: \*

```
From:    daily.pl (any command), agile.pl, the :S commands, sim/rehearsal.pl
Means:   The command looks for scrum.conf in the current directory and
         every directory above it, and found none (or -c named a file
         that does not exist, or agile.pl was given a directory that is
         not a project).
Fix:     cd into the project first (the directory daily.pl init made, or
         any directory below it), or pass -c PATH/scrum.conf. For
         agile.pl, give the project path: perl agile.pl ~/scrum/myprogram.
         No project yet: daily.pl init DIR (agile-first-project).
         In Vim, :pwd shows where you are; :cd to the project.
```

### FILE: NOT applied

Pattern: : NOT applied

```
From:    daily.pl compile (and all, :SCompile)
Means:   The stand-up file named has at least one error (listed under
         this line) and none of it went into the journal. Files after it
         were not tried either.
Fix:     Look each listed error up (they are below), fix the file, then
         daily.pl --dry compile until it prints no errors, then compile.
         Runbook: agile-howto-bad-compile.
```

### FILE: unknown task 'ID'

Pattern: unknown task '\*'

```
From:    Standup.pm
Means:   No task with that id is in the journal, nor created earlier in
         this file. Usually a typo (B-12 for B-121), or the new line for
         it is in a later file.
Fix:     daily.pl backlog TEAM or :SJournal and /ID to find the right id.
         In Vim, CTRL-X CTRL-K completes ids from the journal. To create
         it: new ID PTS TITLE in this file.
```

### FILE: 'ID' is not committed in sprint N for TEAM (at: ACCOUNTS)

Pattern: is not committed in sprint \* for \*

```
From:    Standup.pm (done, carry, drop, punt, pass)
Means:   These verbs move a task out of this sprint's Committed account
         for this team, and the task is not there. "at:" says where its
         points are: a backlog (commit it first), Done (already done),
         Carryover, another team's sprint (wrong section), or "nowhere"
         (removed). A "sprint N" line for the wrong sprint does this to
         every line.
Fix:     Put the line under the right "== Team"; check the file's sprint
         number; daily.pl sprint shows what is committed. For a task in
         a backlog use commit first; to retire it from a backlog use
         prune.
```

### FILE: 'ID' is not in a backlog or carryover for TEAM (at: ACCOUNTS)

Pattern: is not in a backlog or carryover for \* Pattern: is not in the master backlog or another team's backlog Pattern: is not in a backlog (at: \*); use drop for committed work

```
From:    Standup.pm (commit, refine, prune)
Means:   commit takes a task from the team's backlog, the master backlog
         or a past sprint's Carryover; refine from the master or another
         team's backlog; prune from a backlog. The task is elsewhere,
         shown after "at:" (already committed, done, removed).
Fix:     Already in the sprint: nothing to do. Committed work you want
         out: drop (or carry). A task of another team: refine it into
         this team's backlog first, or put the line under that team.
```

### FILE: task 'ID' already exists

Pattern: task '\*' already exists

```
From:    Standup.pm (new, new!)
Means:   A new line uses an id that is already in the journal (or twice
         in this file). Ids are never reused, even for removed tasks.
Fix:     Pick a new id. To bring an existing task into the sprint use
         commit; to resize it use est.
```

### FILE:LINE: unknown verb 'X'

Pattern: unknown verb '\*'

```
From:    Standup.pm (compile, --dry compile)
Means:   The first word of the line is not a verb: a typo (don, comit),
         a sentence typed as a line, or a status pasted without ; in
         front.
Fix:     Use a verb from agile-verbs, or put ; before free text, or
         write it as note TEXT.
```

### FILE:LINE: 'VERB' needs a team section (== Team) first

Pattern: needs a team section (== Team) first

```
From:    Standup.pm
Means:   A verb line comes before any "== Team" header (or after a bare
         "==" that ended the section). Only note and risk may stand
         outside a section.
Fix:     Add "== Team" above the line (the team's exact name, as in
         daily.pl sprint), or "== Master" for the master backlog.
```

### FILE: no sprint number (add 'sprint N')

Pattern: no sprint number (add 'sprint N')

```
From:    Standup.pm
Means:   The journal has no sprint yet and the file does not say which
         sprint it is (a new project's first file).
Fix:     Put "sprint 1" on the line after the date (agile-verb-sprint).
```

### FILE: no date (put YYYY-MM-DD in the file name or on the first line)

Pattern: no date (put YYYY-MM-DD in the file name or on the first line)

```
From:    Standup.pm
Means:   The stand-up file's name has no date and no line of the file is
         a bare date.
Fix:     Name it standups/YYYY-MM-DD.txt (daily.pl new does), or put the
         date alone on the first line.
```

### FILE:LINE: transaction does not balance (off by N)

Pattern: transaction does not balance (off by \*) Pattern: more than one posting without an amount

```
From:    Ledger.pm
Means:   The postings of an entry do not sum to zero, or two postings
         leave their amount out (only one may).
Fix:     Make the amounts sum to zero, or leave exactly one amount out
         (it balances the rest). In the scrum journal every move is a
         pair: -5 SP out of one account, 5 SP into another.
```

### FILE:LINE: unrecognised line / bad date / bad amount ...

Pattern: unexpected indented line Pattern: bad date '\*' Pattern: cannot include '\*': \* Pattern: unrecognised line: \* Pattern: bad amount '\*' Pattern: bad price '\*'

```
From:    Ledger.pm (every command that reads the journal: daily.pl
         status and all others, scrum.pl, ledger.pl)
Means:   A line of the journal (usually a hand edit) does not parse:
         a posting not under a dated transaction line, a date not
         YYYY-MM-DD, an amount that is not a number with a unit, a single
         space between account and amount (two or more are needed).
Fix:     Open the file at the line (vim +LINE scrum.txt), compare with the
         lines around it, fix it, then daily.pl status. If you did not
         edit it: git diff scrum.txt; git checkout -- scrum.txt.
```

### ERROR Name: no Y/T/B found / no B found

Pattern: no Y/T/B found Pattern: no \* found

```
From:    Answers.pm (lint, answers)
Means:   The person's message has no Y, T and B delimiters at all, or
         lacks one of them ("no B found": they left out the blockers).
Fix:     Reply with the format: Y did B-11 T doing B-12 B none. "B none"
         is data. A repost replaces the first message.
```

### ERROR Name: 'B' appears 2 times: capitalize the one that is the delimiter

Pattern: appears \* times: capitalize the one that is the delimiter

```
From:    Answers.pm
Means:   Lowercase y t b are accepted only when unambiguous; here a letter
         occurs twice ("will b in the lab"), so the kit will not guess.
         lint --reply offers its best reading as "Did you mean ...?".
Fix:     The person reposts with capital Y T B, or thumbs-up the "did you
         mean"; then daily.pl answers --guess takes that reading.
```

### ERROR Name: out of order: expected Y ... T ... B ...

Pattern: out of order: expected Y ... T ... B ...

```
From:    Answers.pm
Means:   All three delimiters are there but not in the order Y, T, B.
Fix:     Repost in order.
```

### FILE is already in JOURNAL: marked it compiled, applied nothing

Pattern: is already in \*: marked it compiled, applied nothing

```
From:    Standup.pm (compile)
Means:   An earlier compile appended this file's entries but could not
         mark the file (it was locked). The kit noticed and did not apply
         it twice. A warning, not an error.
Fix:     Nothing. To change what it did, see agile-howto-bad-compile.
```

### refusing: fix the marking errors above, or run again with --force

Pattern: refusing: fix the marking errors above Pattern: error: recipient \* is outside mail\_domains

```
From:    daily.pl draft, brief, cards --send/--draft, invite, check
Means:   scrum.conf sets mail_domains and a recipient (to, cc, an
         attendee) is outside them. Nothing was opened or sent.
Fix:     Correct the address in scrum.conf (to, cc) or roster.txt, or the
         mail_domains list; daily.pl check to confirm. --force only if
         you are sure the recipient may receive the material.
```

### powershell.exe failed (is this Windows with Outlook installed?)

Pattern: powershell.exe failed (is this Windows with Outlook installed?) Pattern: powershell failed (rc=\*) Pattern: bad JSON from PowerShell Pattern: cannot run \*: \* Pattern: create: need subject and start Pattern: post needs an event id or subject pattern Pattern: no event matching '\*' Pattern: commands: list dump attend

```
From:    daily.pl draft, brief, cards, invite, attend, post, meetings;
         scrum.pl draft; cal.pl
Means:   The Outlook steps drive classic Outlook through PowerShell COM.
         This fails when not on Windows, with "new Outlook" (it has no
         COM), with Outlook not set up, or when a policy blocks it.
Fix:     On Windows, open classic Outlook once and try again. Offline or
         elsewhere set calendar = mock and calendar_fixture = FILE.json in
         scrum.conf for the calendar steps, and send mail by pasting
         reports/DATE-status.html. docs/TEST-PLAN.html is the 30-minute
         check of this layer on a laptop.
```

### cannot write FILE: REASON

Pattern: cannot write \*: \* Pattern: cannot append \*: \* Pattern: cannot append to \*: \* Pattern: help: cannot write \*: \* Pattern: idef0: cannot write \*: \* Pattern: cannot write devsecops.html: \*

```
From:    daily.pl (report, review, rollup, csv, drill, propose, lint,
         answers, cards, init), agile.pl, scrum.pl, Roster.pm, Ai.pm,
         Attendance.pm, Calendar.pm, Standup.pm, idef0.pl fmt --write
Means:   The file could not be opened for writing. REASON is the system's
         words: "Permission denied" (read-only, or open and locked in
         another program: Excel holds a CSV open, OneDrive or antivirus is
         syncing it), "No such file or directory" (the directory is
         missing), "No space left on device".
Fix:     Close the file in Excel or the browser, wait for OneDrive, check
         the directory exists and is yours (ls -ld DIR), then run the
         command again. Reports are regenerated every time, so nothing is
         lost by re-running.
```

### not a git repository (git init first)

Pattern: not a git repository (git init first)

```
From:    daily.pl commit, all
Means:   The project directory is not a git repository (made by hand, or
         copied without .git).
Fix:     In the project: git init, git config core.autocrlf false, then
         daily.pl commit (agile-howto-backup).
```

### no chat file for DATE / no chat files for DATE / no Y/T/B answers found

Pattern: no chat file Pattern: no chat files for \* Pattern: no Y/T/B answers found Pattern: no #est / #vote markers Pattern: no answers files for \* Pattern: no attendance reports for \*

```
From:    daily.pl lint, answers, chat, ai, joined
Means:   Today's input file is not there yet, or it holds no statuses or
         rounds. The file names are standups/DATE-chat.txt (or
         DATE-TEAM-chat.txt) for the chat and
         standups/DATE[-TEAM]-attendance.csv for the attendance download.
Fix:     :SChat, paste the Teams chat (CTRL-A CTRL-C there), :w. For ai,
         run answers first. --today D if you are catching up a past day.
```

### broken link: cannot resolve 'A|B|Flow'

Pattern: broken link: cannot resolve '\*' Pattern: has no unique port for flow '\*'; add the port or use o1/i1 form Pattern: one-sided cross-model link: \* Pattern: has no producer; did you mean '\*'? Pattern: has no consumer; did you mean '\*'?

```
From:    idef0.pl lint
Means:   A link path names a model, activity or flow that is not there
         (spelling, or the other model was not linted with this one), an
         activity has two ports for the flow, a cross-model link is
         declared on one side only, or a flow is produced or consumed
         nowhere.
Fix:     Lint the whole project together (\iL, or idef0.pl lint
         model/*.txt) so cross-model links resolve; fix the spelling the
         message suggests; add the reciprocal < or > on the other side.
         \if jumps to a link's target.
```

