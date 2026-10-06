# sim/tidewater-plan.pl -- the Tidewater backlog for sim/tidewater-sim.pl: 39 sprints of stories and tasks.
#
# tw_plan() -> [ sprint ... ] where sprint = { n, goal, pulse, retro => {start, stop, continue}, quotes => [[date, who, text]],
#   stories => [ story ] } and story = { key, epic, work (engineering|platform), title, owner, why, done => [criteria],
#   area, prio, votes => [[v1, v2, v3], ...] (planning-poker rounds; the last is the consensus), carry => 1 (planned to
#   spill), tasks => [ { t, p, who, act => [NAME, %args], block => [DAY, DAYS, WHY], late => DAYS } ] }.
# A task's points are ideal person-days (at most 5); a story fits one sprint; the sim checks both.
# Sprints 1-6 (the first twelve weeks) are written out; 7-39 follow the epics with generated stories.
use strict;
use warnings;

our %TW_EPIC = (
    E1 => ['T1', 'GitLab project and gitflow'], E2 => ['T1', 'Pipeline and quality gates'], E3 => ['T1', 'Team practices and onboarding'],
    E4 => ['T1', 'Toolchain security and authorization to use'], E5 => ['T2', 'Drop 1 intake and first import'],
    E6 => ['T2', 'Structure: close the structure TODOs'], E7 => ['T2', 'Requirements and trace'], E8 => ['T2', 'Behavior and analysis'],
    E9 => ['T2', 'Drops 2 and 3 during the port'], E10 => ['T2', 'Baseline 1 and acceptance'], E11 => ['T3', 'Drop intake automation'],
    E12 => ['T3', 'Drops 4 and 5'], E13 => ['T3', 'Drops 6 and 7'], E14 => ['T3', 'Sustainment operations'], E15 => ['T3', 'Engineering with the model'],
    E16 => ['T3', 'Security engineered into Tidewater'],
);
our %TW_TOME = (T1 => 'Stand up MBSE DevSecOps', T2 => 'Port Tidewater v1 to SysML v2', T3 => 'Maintain against prime drops');
our %TW_EPIC_LABEL = (E1 => 'E1-gitlab', E2 => 'E2-pipeline', E3 => 'E3-practices', E4 => 'E4-toolchain-security', E5 => 'E5-drop-1',
    E6 => 'E6-structure', E7 => 'E7-requirements', E8 => 'E8-behavior', E9 => 'E9-drops-2-3', E10 => 'E10-baseline-1',
    E11 => 'E11-intake-automation', E12 => 'E12-drops-4-5', E13 => 'E13-drops-6-7', E14 => 'E14-sustainment', E15 => 'E15-engineering', E16 => 'E16-security');
our %TW_TOME_LABEL = (T1 => 'T1-stand-up', T2 => 'T2-port', T3 => 'T3-maintain');

sub _st { my (%s) = @_; $s{prio} //= 2; $s{votes} //= []; \%s }
sub _tk { my ($t, $p, $who, @act) = @_; my %o; %o = %{ pop @act } if @act && ref $act[-1] eq 'HASH'; { t => $t, p => $p, who => $who, (@act ? (act => \@act) : ()), %o } }

sub tw_plan {
    my @S;
    # ------------------------------------------------------------------ S1 Oct 5-16 (capacity 18.9; commit 16.5)
    push @S, { n => 1, goal => 'A GitLab project the team can work in; drop 1 received and assessed', pulse => 1.9,
        quotes => [ ['2026-10-05', 'Bob', "Why can't we just send the Word doc? It worked for twenty years."],
                    ['2026-10-06', 'Bob', 'Spent the afternoon in the practice repo. Branch, commit, merge. It is configuration management with fewer forms.'],
                    ['2026-10-08', 'Bob', 'I found the drift in two minutes. It used to take a week, and we only looked before a review.'] ],
        retro => { start => ['Writing the task id in every stand-up status', 'Running the converter report before estimating'],
                   stop => ['Estimating a story before anyone has read the drop'],
                   continue => ['Pairing at the terminal for the first git commands', 'One issue per action item'] },
        stories => [
        _st(key => 'S1-learn', epic => 'E3', work => 'learning', owner => 'jim', area => 'pipeline',
            title => 'Learn the tools: survival kit, git, Vim, the operating model',
            why => 'Nobody on the team has used git, a pipeline or SysML v2 text; the time to learn is planned, not taken from evenings.',
            done => ['Each of us finished practice lessons 10 and 11', 'Each of us read the primer\'s Part II chapters for our role'],
            votes => [[3, 5, 3], [4, 4, 4]],
            tasks => [ _tk('Practice lessons 10-11; the operating model chapter', 1, 'jim', 'note'),
                       _tk('Practice lessons 10-11; the survival kit, git and Vim chapters', 1.5, 'bob', 'note'),
                       _tk('Practice lessons 10-11; the survival kit, git and Vim chapters', 1.5, 'tom', 'note') ]),
        _st(key => 'S1-laptops', epic => 'E3', work => 'platform', owner => 'tom', area => 'pipeline',
            title => 'Laptops ready: Git for Windows, Vim, the kit',
            why => 'Three laptops, one software request, one checklist: kickoff.pl doctor says what is missing.',
            done => ['kickoff.pl doctor passes on all three laptops'],
            votes => [[3, 3, 3]],
            tasks => [ _tk('Set up Jim\'s laptop; kickoff.pl doctor', 1, 'jim', 'doctor'),
                       _tk('Set up Bob\'s laptop; kickoff.pl doctor', 1, 'bob', 'doctor', { block => [1, 2, 'the software request for Git for Windows is still with the help desk'] }),
                       _tk('Set up Tom\'s laptop; kickoff.pl doctor', 1, 'tom', 'doctor') ]),
        _st(key => 'S1-project', epic => 'E1', work => 'platform', owner => 'tom', area => 'pipeline', prio => 1,
            title => 'Create the GitLab group and model project',
            why => 'The team needs one place where the model, its history, its reviews and its action items live together.',
            done => ['The project exists with the settings in project.conf', 'A direct push to develop is refused', 'CODEOWNERS and the issue and MR templates are on develop'],
            votes => [[2, 5, 3], [3, 3, 3]],
            tasks => [ _tk('Apply project.conf with gitlab.pl setup; request the runner', 1, 'tom', 'setup'),
                       _tk('Prove a direct push to develop is refused', 1, 'tom', 'protect_proof'),
                       _tk('Commit CODEOWNERS, the templates and .gitignore', 1, 'tom', 'repo_files') ]),
        _st(key => 'S1-pipeline', epic => 'E2', work => 'platform', owner => 'tom', area => 'pipeline',
            title => 'Draft the first pipeline and run it locally',
            why => 'Every change should be checked the same way, by a machine, before anyone reviews it.',
            done => ['The draft runs grammar, lint and outline on drop 1 with gitlab.pl ci'],
            votes => [[1, 2, 2], [1.5, 1.5, 1.5]],
            tasks => [ _tk('Draft .gitlab-ci.yml: grammar, lint, outline', 0.5, 'tom', 'ci_draft'),
                       _tk('Run the draft locally on drop 1 with gitlab.pl ci', 1, 'tom', 'ci_local') ]),
        _st(key => 'S1-receive', epic => 'E5', work => 'engineering', owner => 'jim', area => 'requirements', prio => 1,
            title => 'Receive drop 1 and record it',
            why => 'The prime delivered the v1 model under CDRL A003 on 2 October; the government records exactly what it received.',
            done => ['Every file matches its MANIFEST sha256', 'The Prime Drop issue holds the checklist'],
            votes => [[1, 2, 2], [1.5, 1.5, 1.5]],
            tasks => [ _tk('Log the CDRL delivery and check the sha256 of every file', 1, 'jim', 'drop_check', drop => 1),
                       _tk('Open the Prime Drop issue with its checklist', 0.5, 'jim', 'drop_issue', drop => 1) ]),
        _st(key => 'S1-assess', epic => 'E5', work => 'engineering', owner => 'bob', area => 'requirements', prio => 1,
            title => 'Convert drop 1 and assess it',
            why => 'Before estimating the port, the team needs to know what the converter carries and what it leaves as TODO lines.',
            done => ['Both converter reports are attached', 'The TODO inventory by package is on the wiki', 'The port backlog has estimates'],
            votes => [[3, 8, 5], [3, 3, 3]],
            tasks => [ _tk('Run both converters with --report on drop 1', 1, 'bob', 'convert_report', drop => 1),
                       _tk('Write the TODO inventory by package', 1, 'bob', 'todo_inventory', drop => 1),
                       _tk('Estimate the port backlog with the team', 1, 'bob', 'note') ]),
        _st(key => 'S1-agree', epic => 'E3', work => 'platform', owner => 'jim', area => 'pipeline',
            title => 'Working agreements: Definition of Ready and Done',
            why => 'Three people agree once what "ready" and "done" mean, instead of arguing it story by story.',
            done => ['Definition of Ready and Definition of Done on the wiki'],
            votes => [[1, 0.5, 0.5], [0.5, 0.5, 0.5]],
            tasks => [ _tk('Write the Definition of Ready and Done in the wiki', 0.5, 'jim', 'wiki', pages => ['Home', 'Definition of Ready', 'Definition of Done', 'Glossary']) ]),
        ] };
    # ------------------------------------------------------------------ S2 Oct 19-30 (capacity 21; commit 18.5)
    push @S, { n => 2, goal => 'Drop 1 on develop through the vendor branch; every change gated', pulse => 2.5,
        quotes => [ ['2026-10-23', 'Tom', 'The first pipeline on the real runner died on line one. PowerShell. Nobody told me the runner speaks PowerShell.'],
                    ['2026-10-29', 'Jim', 'The model is on develop and nobody touched it with a mouse.'],
                    ['2026-10-30', 'Deputy PM', 'I did not follow the demo. What did we get for the two weeks?'] ],
        retro => { start => ['A Day-9 demo rehearsal: question, output, before and after, one live change, the ask', 'Rotating who drives the demo'],
                   stop => ['Writing shell in the YAML', 'Demoing the terminal instead of the answer'],
                   continue => ['Running gitlab.pl ci before every push', 'Small MRs: the drop-1 merge was the only big one, and it was reviewable'] },
        stories => [
        _st(key => 'S2-learn', epic => 'E3', work => 'learning', owner => 'bob', area => 'pipeline',
            title => 'Learn: practice lessons 12-13, Vim for models, the SysML v2 workbook (first half)',
            why => 'The port starts in earnest; everyone reads and edits SysML v2 text in Vim before the first model MR.',
            done => ['Lessons 12-13 done by all three', 'The workbook\'s first half done by Bob and Tom'],
            votes => [[3, 3, 3]],
            tasks => [ _tk('Practice lessons 12-13; the diagrams chapter', 0.5, 'jim', 'note'),
                       _tk('Lessons 12-13; Vim for models; workbook first half', 1.5, 'bob', 'note'),
                       _tk('Lessons 12-13; Vim for models; workbook first half', 1, 'tom', 'note') ]),
        _st(key => 'S2-runner', epic => 'E2', work => 'platform', owner => 'tom', area => 'pipeline', prio => 1,
            title => 'Runner online; the first pipeline gates every MR',
            why => 'A check that runs on the server, on every change, is the configuration audit nobody can skip.',
            done => ['A pipeline runs on every MR', '"Pipelines must succeed" is on', 'JUnit and Code Quality reports show on the MR'],
            votes => [[3, 3, 3]],
            tasks => [ _tk('Check the runner registration and tags', 0.5, 'tom', 'note'),
                       _tk('Commit the pipeline; fix it for the PowerShell runner with ci/job.pl', 2, 'tom', 'ci_first'),
                       _tk('Turn on "pipelines must succeed" and the MR report widgets', 0.5, 'tom', 'gate_on') ]),
        _st(key => 'S2-import', epic => 'E5', work => 'engineering', owner => 'bob', area => 'requirements', prio => 1,
            title => 'Import drop 1 through the vendor branch, in layers',
            why => 'The prime will deliver again; importing through vendor/prime with a fixed layout map lets git merge each later drop into our edited copy.',
            done => ['The layout map is decided and committed', 'vendor/prime holds the converter output of drop 1', 'The merge MR is on develop, outline count recorded'],
            votes => [[3, 5, 3], [4, 4, 4]],
            tasks => [ _tk('Decide the layered layout; the layout map', 1, 'bob', 'note'),
                       _tk('Import drop 1 onto vendor/prime', 1, 'tom', 'vendor', drop => 1),
                       _tk('Review and merge the drop-1 MR; record the outline count', 2, 'bob', 'drop_merge', drop => 1) ]),
        _st(key => 'S2-todo-docs', epic => 'E2', work => 'platform', owner => 'tom', area => 'pipeline',
            title => 'TODO burn-down and generated docs in the pipeline',
            why => 'The TODO count is the port progress measure; generated docs must match the model that made them.',
            done => ['The todo job counts TODO lines on every MR', 'docs/ is generated and the docs job keeps it current'],
            votes => [[2, 2, 3], [2, 2, 2]],
            tasks => [ _tk('Add the todo and docs jobs; commit docs/', 2, 'tom', 'ci_level', level => 2) ]),
        _st(key => 'S2-conventions', epic => 'E6', work => 'engineering', owner => 'bob', area => 'gov',
            title => 'Level conventions for the part tree',
            why => 'The v1 profile\'s level stereotypes become SysML v2 metadata the outline check can verify.',
            done => ['model/library/conventions/Conventions.sysml defines L1Network..L6Component and Procured', 'sysml.conf names the level tags'],
            votes => [[2, 2, 2]],
            tasks => [ _tk('Write the conventions package', 1.5, 'bob', 'model_mr', edits => [['conventions']], title => 'Add the government conventions package'),
                       _tk('Name the level tags in sysml.conf', 0.5, 'bob', 'model_mr', conf => 'levels', title => 'Name the level tags in sysml.conf') ]),
        _st(key => 'S2-enablers', epic => 'E1', work => 'platform', owner => 'jim', area => 'pipeline',
            title => 'Enablers, decisions and conventions on record',
            why => 'What the team needs from the program, what it decided in week zero, and how it names things: written once, reviewable.',
            done => ['The request for enablers is with the PM', 'docs/adr holds D-1 to D-10', 'docs/conventions and docs/onboarding are in the repo'],
            votes => [[3, 3, 5], [4, 4, 4]],
            tasks => [ _tk('Memo: request for enablers', 1, 'jim', 'note'),
                       _tk('Write docs/adr/0001..0010', 1.5, 'jim', 'adr'),
                       _tk('Conventions and onboarding docs into docs/', 1, 'jim', 'note'),
                       _tk('Toolchain security kickoff with the ISSM', 1, 'jim', 'note') ]),
        _st(key => 'S2-demo', epic => 'E3', work => 'platform', owner => 'tom', area => 'pipeline',
            title => 'Sprint 2 demo: the pipeline and the drop on develop',
            why => 'Management sees what the two weeks bought.',
            done => ['The demo is given'],
            votes => [[0.5, 0.5, 0.5]],
            tasks => [ _tk('Prepare and give the sprint 2 demo', 0.5, 'tom', 'note') ]),
        ] };
    # ------------------------------------------------------------------ S3 Nov 2-13 (capacity 18.9; commit 16)
    push @S, { n => 3, goal => 'Network closed; DOORS in the model; the trace report on every change', pulse => 2.2,
        quotes => [ ['2026-11-06', 'Bob', 'A red X on my own MR. One missing word, and the machine found it before Jim did.'],
                    ['2026-11-10', 'Tom', 'Three days waiting on a signature. The pipeline was the fast part.'] ],
        retro => { start => ['Splitting MRs before they reach 300 lines', 'Drafting the stand-up with talk.pl, then editing it'], stop => ['Waiting for the ISSM without a date'],
                   continue => ['Fixing a red pipeline on the branch, not around it', 'The Day-9 rehearsal'] },
        stories => [
        _st(key => 'S3-learn', epic => 'E3', work => 'learning', owner => 'tom', area => 'pipeline',
            title => 'Learn: the workbook second half; talking about progress',
            why => 'Statuses and demos that lead with the outcome and one number; the rest of the SysML v2 workbook.',
            done => ['Everyone drafts the stand-up with talk.pl', 'The Day-9 rehearsal held'],
            votes => [[2, 3, 3], [2.5, 2.5, 2.5]],
            tasks => [ _tk('talk.pl: draft, then edit, the stand-up', 0.5, 'jim', 'note'),
                       _tk('Workbook second half; talk.pl', 1, 'bob', 'note'),
                       _tk('talk.pl; the Day-9 demo rehearsal', 1, 'tom', 'note', { day => '2026-11-12' }) ]),
        _st(key => 'S3-network', epic => 'E6', work => 'engineering', owner => 'bob', area => 'network', prio => 1,
            title => 'Close the Network TODO lines',
            why => 'Network is the top of the part tree; its level tag and the include use case anchor everything below it.',
            done => ['No TODO lines in Network.sysml', 'The pipeline is green'],
            votes => [[2, 3, 5], [3, 3, 3]],
            tasks => [ _tk('Level tags in Network', 1, 'bob', 'model_mr', edits => [['levels', file => 'model/physical/network/Network.sysml']], title => 'Level tags in Network'),
                       _tk('The include use case in ReviewObservations', 2, 'bob', 'model_mr', edits => [['include']], title => 'Replace the Include TODO with an include use case', plant => 'grammar') ]),
        _st(key => 'S3-doors', epic => 'E7', work => 'engineering', owner => 'jim', area => 'requirements', prio => 1,
            title => 'DOORS modules into the model',
            why => 'DOORS is authoritative for requirement text (D-4); the model gets the converted copy so the trace can compare them.',
            done => ['model/requirements holds the three DOORS modules', 'The trace report runs on every change'],
            votes => [[3, 3, 3]],
            tasks => [ _tk('Re-import drop 1 with the DOORS modules on vendor/prime', 2, 'jim', 'vendor', drop => 1, doors => 1),
                       _tk('Merge the DOORS modules to develop', 1, 'bob', 'drop_merge', drop => 1, doors => 1) ]),
        _st(key => 'S3-trace', epic => 'E2', work => 'platform', owner => 'tom', area => 'pipeline',
            title => 'Trace report and secret detection in the pipeline',
            why => 'Every change shows its effect on the trace; nothing secret reaches the repository.',
            done => ['The trace job reports C/F/G/I and drift', 'The secrets job runs on every MR'],
            votes => [[3, 3, 3]],
            tasks => [ _tk('Add the trace job (report only) and the secrets job', 2.5, 'tom', 'ci_level', level => 3) ]),
        _st(key => 'S3-runner', epic => 'E4', work => 'platform', owner => 'tom', area => 'pipeline',
            title => 'Runner hardening with the ISSM',
            why => 'The runner runs code from every MR; it gets least privilege and a service account the ISSM approves.',
            done => ['The runner service account is approved', 'The hardening checklist is in the wiki'],
            votes => [[2, 2, 2]],
            tasks => [ _tk('Runner service account and hardening checklist', 2, 'tom', 'wiki', pages => ['Administration'], { block => [1, 3, 'waiting on the ISSM to approve the runner service account', 2] }) ]),
        _st(key => 'S3-drift', epic => 'E7', work => 'engineering', owner => 'jim', area => 'requirements',
            title => 'First drift and gap analysis from the trace',
            why => 'The trace shows where DOORS and the model disagree; each finding needs an owner.',
            done => ['Each gap in the trace report has a finding written up'],
            votes => [[2, 2, 2]],
            tasks => [ _tk('Write up the drift and the trace gaps', 2, 'jim', 'note') ]),
        ] };
    # ------------------------------------------------------------------ S4 Nov 16-27 (capacity 18.4; commit 15)
    push @S, { n => 4, goal => 'Stations levels and Types closed, one cycle broken, gaps reported; the model site for management', pulse => 3.1,
        quotes => [ ['2026-11-24', 'Program manager', 'I can open this on my phone? I have never seen the model without a briefing.'],
                    ['2026-11-24', 'Tom', 'The cycle was two lines. In Cameo it was a week of looking at a diagram.'] ],
        retro => { start => ['Showing the model site at every review'], stop => ['Estimating procured parts as if they were simple'],
                   continue => ['Discrepancy reports instead of fixing the prime\'s model', 'The rehearsed demo: it landed'] },
        stories => [
        _st(key => 'S4-learn', epic => 'E3', work => 'learning', owner => 'bob', area => 'pipeline',
            title => 'Learn: reviewing a model change; the rehearsed demo',
            why => 'Reviews are the new peer review: read the diff, the pipeline, the widgets, then approve or ask.',
            done => ['Each reviewer has reviewed with line comments', 'The Day-9 rehearsal held'],
            votes => [[1.5, 1.5, 1.5]],
            tasks => [ _tk('Reviewing a model change: the checklist', 0.5, 'jim', 'note'),
                       _tk('Reviewing a model change: line comments', 0.5, 'bob', 'note'),
                       _tk('The Day-9 demo rehearsal', 0.5, 'tom', 'note', { day => '2026-11-25' }) ]),
        _st(key => 'S4-stations', epic => 'E6', work => 'engineering', owner => 'bob', area => 'stations', prio => 1, carry => 1,
            title => 'Close the Stations level tags',
            why => 'Stations is the largest package: 25 members and most of the level stereotypes.',
            done => ['No level-stereotype TODO lines in Stations.sysml'],
            votes => [[3, 5, 5], [3, 3, 3]],
            tasks => [ _tk('Level tags in Stations', 3, 'bob', 'model_mr', edits => [['levels', file => 'model/physical/stations/Stations.sysml']], title => 'Level tags in Stations'),
                       _tk(q{Walk the Stations tree with the prime's modeler; record what they confirmed}, 2, 'bob') ]),
        _st(key => 'S4-types', epic => 'E6', work => 'engineering', owner => 'bob', area => 'types',
            title => 'Units and value types',
            why => 'Power and energy carry their units again, as ISQ quantity kinds.',
            done => ['No TODO lines in Types.sysml'],
            votes => [[2, 2, 2]],
            tasks => [ _tk('Value types specialize ISQ quantities', 2, 'bob', 'model_mr', edits => [['units']], title => 'Units for Power and Energy') ]),
        _st(key => 'S4-cycle-no', epic => 'E6', work => 'engineering', owner => 'tom', area => 'network',
            title => 'Break the Network <-> Operations cycle',
            why => 'A package cycle means neither side can change alone; the v1 model has two of them.',
            done => ['One cycle fewer in the package view', 'A DR asks the prime to drop the dependency'],
            votes => [[2, 2, 2]],
            tasks => [ _tk('Remove the ServiceVessel -> Technician dependency', 2, 'tom', 'model_mr', edits => [['cycles', which => 'no']], title => 'Break the Network <-> Operations cycle') ]),
        _st(key => 'S4-dr', epic => 'E7', work => 'engineering', owner => 'jim', area => 'requirements', prio => 1,
            title => 'Discrepancy reports DR-1 to DR-4 to the prime',
            why => 'The government does not edit the prime\'s model (D-6); it reports, and the prime fixes it in a later drop.',
            done => ['DR-1 to DR-4 are open, owner::prime, sent through the contract channel'],
            votes => [[2, 2, 2]],
            tasks => [ _tk('Open DR-1 to DR-4', 2, 'jim', 'drs', drs => [1, 2, 3, 4]) ]),
        _st(key => 'S4-pages', epic => 'E2', work => 'platform', owner => 'tom', area => 'pipeline',
            title => 'The model site on GitLab Pages, rebuilt nightly',
            why => 'Management and the prime see the model\'s state without a briefing and without cloning anything.',
            done => ['The pages job publishes the site on every merge to develop', 'A nightly schedule rebuilds it'],
            votes => [[3, 3, 3]],
            tasks => [ _tk('Add the pages job and the nightly schedule', 3, 'tom', 'ci_level', level => 4, schedule => 1) ]),
        _st(key => 'S4-review', epic => 'E3', work => 'engineering', owner => 'jim', area => 'pipeline',
            title => 'First sprint review with the program office; the delivery interface with the prime',
            why => 'Management sees the model site; the prime and the government agree what crosses between their pipelines.',
            done => ['The program office has seen the site', 'The pipeline ICD meeting held'],
            votes => [[1.5, 1.5, 1.5]],
            tasks => [ _tk('Sprint review with the program office', 1, 'jim', 'note'),
                       _tk('Agree the delivery interface with the prime (meeting)', 0.5, 'jim', 'note') ]),
        ] };
    # ------------------------------------------------------------------ S5 Nov 30-Dec 11 (capacity 21; commit 18.5)
    push @S, { n => 5, goal => 'Procured parts and DataCenter closed; Legacy Import untangled; trace becomes a gate', pulse => 3.7,
        quotes => [ ['2026-12-11', 'Bob', 'The ratchet stopped me. I deleted a satisfy I thought was a duplicate. It was not.'],
                    ['2026-12-09', 'Jim', 'The deputy PM asked for the trace numbers. I sent a link.'] ],
        retro => { start => ['Lowering .ci/outline-max in the same MR that fixes a violation'], stop => ['Cleaning up trace links by eye'],
                   continue => ['The ratchet: it caught a real mistake'] },
        stories => [
        _st(key => 'S5-learn', epic => 'E3', work => 'learning', owner => 'jim', area => 'requirements',
            title => 'Learn: the requirement recipe; writing memos from the model',
            why => 'Requirements the recipe can grade, and memos whose numbers come from the pipeline.',
            done => ['The recipe chapter read; one memo drafted from pipeline numbers'],
            votes => [[1, 1, 1]],
            tasks => [ _tk('The recipe chapter; a memo from pipeline numbers', 0.5, 'jim', 'note'),
                       _tk('The recipe chapter', 0.5, 'bob', 'note') ]),
        _st(key => 'S5-procured', epic => 'E6', work => 'engineering', owner => 'bob', area => 'stations', prio => 1,
            title => 'Procured parts as metadata; DataCenter level tags',
            why => 'The rest of the structure stereotypes: what is bought, and the data center\'s levels.',
            done => ['Procured parts carry @Procured', 'No level-stereotype TODO lines in DataCenter.sysml'],
            votes => [[3, 3, 5], [3.5, 3.5, 3.5]],
            tasks => [ _tk('Procured parts as metadata', 2, 'bob', 'model_mr', edits => [['procured', file => 'model/physical/stations/Stations.sysml']], title => 'Procured parts as @Procured metadata'),
                       _tk('Level tags in DataCenter', 1.5, 'bob', 'model_mr', edits => [['levels', file => 'model/physical/datacenter/DataCenter.sysml']], title => 'Level tags in DataCenter') ]),
        _st(key => 'S5-spaghetti', epic => 'E7', work => 'engineering', owner => 'bob', area => 'stations',
            title => 'Prune ObservingStation\'s trace spaghetti',
            why => 'ObservingStation has eleven trace links that repeat its satisfies; the spider web starts there.',
            done => ['The duplicate traces are gone', 'The trace job shows no new gap'],
            votes => [[2, 2, 2]],
            tasks => [ _tk('Remove the duplicate trace links', 2, 'bob', 'model_mr', edits => [['spaghetti']], title => 'Prune ObservingStation\'s trace links', plant => 'ratchet') ]),
        _st(key => 'S5-legacy', epic => 'E6', work => 'engineering', owner => 'tom', area => 'legacy',
            title => 'Untangle the Legacy Import package',
            why => 'Duplicates and a requirement from a slide, left from the document port: the government copy drops them, the prime is asked to.',
            done => ['model/legacy/Legacy_Import.sysml is gone from develop', 'A DR asks the prime to delete it upstream'],
            votes => [[3, 3, 3]],
            tasks => [ _tk('Remove the Legacy Import package from the v2 model', 2, 'tom', 'model_mr', edits => [['legacy']], title => 'Remove the Legacy Import clutter'),
                       _tk('DR-5: ask the prime to delete Legacy Import', 1, 'jim', 'drs', drs => [5]) ]),
        _st(key => 'S5-ratchet', epic => 'E2', work => 'platform', owner => 'tom', area => 'pipeline',
            title => 'The trace job becomes a gate',
            why => 'Gaps the prime must fix stay visible; a change that adds a gap stops at the MR.',
            done => ['The trace job fails an MR that adds an orphan, an unverified requirement or drift'],
            votes => [[2, 2, 2]],
            tasks => [ _tk('Trace ratchet: fail only on new gaps', 2, 'tom', 'ci_level', level => 5) ]),
        _st(key => 'S5-recipe', epic => 'E7', work => 'engineering', owner => 'jim', area => 'requirements',
            title => 'Grade our requirements with the recipe',
            why => 'Weak verbs and missing parts in the requirement text make verification impossible; the recipe finds them on every change.',
            done => ['The recipe report runs on every MR', 'Findings on DOORS text are a DR to the prime'],
            votes => [[2, 2, 3], [2, 2, 2]],
            tasks => [ _tk('Read the recipe findings for the DOORS modules', 1, 'jim', 'recipe_review'),
                       _tk('DR-6: weak verbs and missing parts in the DOORS text', 1, 'jim', 'drs', drs => [6]) ]),
        _st(key => 'S5-rehearse', epic => 'E1', work => 'platform', owner => 'tom', area => 'pipeline',
            title => 'Release rehearsal and a spillage tabletop',
            why => 'The first real baseline should not be the first time anyone cuts a release branch; Tom, as security owner, rehearses a spill.',
            done => ['A release and a hotfix went through a sandbox project', 'The spillage tabletop is written up'],
            votes => [[3, 3, 3]],
            tasks => [ _tk('Rehearse release and hotfix in tidewater/sandbox', 2, 'tom', 'rehearsal'),
                       _tk('Spillage tabletop: a marked file pushed by mistake', 1, 'tom', 'note') ]),
        ] };
    # ------------------------------------------------------------------ S6 Dec 14-25 (capacity 15.7; commit 14.5)
    push @S, { n => 6, goal => 'Behavior started; Operations closed; the data exchange table; interim baseline-0 for the program review', pulse => 4.2,
        quotes => [ ['2026-12-17', 'Bob', 'Six things happened before lunch and I knew about every one of them from GitLab, not from email.'],
                    ['2026-12-24', 'Program manager', 'Keep doing this. Show me the same numbers in March.'] ],
        retro => { start => ['Writing acceptance criteria as pipeline checks'], stop => ['Pasting tokens into scripts, even test ones'],
                   continue => ['The nightly pipeline', 'Reviews with line comments instead of red-pen PDFs'] },
        stories => [
        _st(key => 'S6-learn', epic => 'E3', work => 'learning', owner => 'jim', area => 'pipeline',
            title => 'Learn: memos and briefings from the model',
            why => 'The twelve-week briefing is built from the pipeline\'s numbers, not from a spreadsheet.',
            done => ['The memo chapter read before the briefing'],
            votes => [[0.5, 0.5, 0.5]],
            tasks => [ _tk('The memo and briefing chapters', 0.5, 'jim', 'note') ]),
        _st(key => 'S6-buoymodes', epic => 'E8', work => 'engineering', owner => 'bob', area => 'behavior', prio => 1, carry => 1,
            title => 'BuoyModes state machine by hand',
            why => 'The converter cannot carry state machines; the buoy\'s modes are written in SysML v2 by hand in logical/GovBehavior.',
            done => ['The BuoyModes TODO is replaced by an exhibit state', 'GovBehavior holds the state def'],
            votes => [[3, 3, 3]],
            tasks => [ _tk('Write the BuoyModes state def; exhibit it on MooredBuoy', 3, 'bob', 'model_mr', edits => [['statemachine']], title => 'BuoyModes state machine in SysML v2') ]),
        _st(key => 'S6-flows', epic => 'E8', work => 'engineering', owner => 'bob', area => 'behavior',
            title => 'Fork, pin and object flow in ObserveCoast',
            why => 'The observation cycle\'s fork and flows were TODO lines; the behavior reads end to end again.',
            done => ['No TODO lines in Behavior.sysml'],
            votes => [[1, 2, 1], [1, 1, 1]],
            tasks => [ _tk('Fork, pin, object and control flow by hand', 1, 'bob', 'model_mr', edits => [['flows']], title => 'Fork, pin and flows in ObserveCoast', plant => 'drift', draft => 1, { day => '2026-12-17' }) ]),
        _st(key => 'S6-operations', epic => 'E6', work => 'engineering', owner => 'tom', area => 'operations',
            title => 'Level tags in Operations',
            why => 'The last structure package with level stereotypes.',
            done => ['No level-stereotype TODO lines left in model/physical'],
            votes => [[1.5, 1.5, 1.5]],
            tasks => [ _tk('Level tags in Operations', 1.5, 'tom', 'model_mr', edits => [['levels', file => 'model/physical/operations/Operations.sysml']], title => 'Level tags in Operations') ]),
        _st(key => 'S6-exchange', epic => 'E8', work => 'engineering', owner => 'tom', area => 'interfaces',
            title => 'Data exchange table for the program review',
            why => 'Management asks what crosses each interface; the table is generated from the model, not typed.',
            done => ['docs/data-exchange.md is generated from the interface items and flow properties', 'It is shown at the briefing'],
            votes => [[3, 3, 2], [2.5, 2.5, 2.5]],
            tasks => [ _tk('Document the flow properties in Interfaces', 1, 'tom', 'model_mr', edits => [['ifdocs']], title => 'Document what crosses each interface', review => 'request_changes', { day => '2026-12-17' }),
                       _tk('Generate the data exchange table', 1, 'tom', 'exchange_table', { day => '2026-12-18' }) ]),
        _st(key => 'S6-vcrm', epic => 'E7', work => 'engineering', owner => 'jim', area => 'verification',
            title => 'VCRM: which requirements are verified, and how',
            why => '"Which requirements are unverified?" took two days of spreadsheet work; the pipeline answers it on every change.',
            done => ['The vcrm job publishes the VCRM on the site', 'Jim\'s inspection verdicts are in verification/results-gov.csv'],
            votes => [[2, 3, 3], [2, 2, 2]],
            tasks => [ _tk('Add the vcrm job', 1, 'tom', 'ci_level', level => 6),
                       _tk('Enter and sign the inspection verdicts', 1, 'jim', 'results_gov') ]),
        _st(key => 'S6-baseline', epic => 'E1', work => 'platform', owner => 'tom', area => 'pipeline',
            title => 'Interim baseline-0 for the program review',
            why => 'The program review gets a named, reproducible state of the model, not a set of screenshots.',
            done => ['baseline-0 is tagged on main and rebuilds identically', 'The CCB concurred on the release MR', 'The release notes are published'],
            votes => [[2, 2, 2]],
            tasks => [ _tk('Release branch, CCB concurrence, tag baseline-0, back-merge', 2, 'tom', 'release', name => 'baseline-0') ]),
        _st(key => 'S6-briefing', epic => 'E3', work => 'engineering', owner => 'jim', area => 'pipeline',
            title => 'Retrospective, the management briefing and the plan for next semester',
            why => 'Twelve weeks in: show management the scorecard, before and after, and plan the next semester.',
            done => ['The briefing and the memo are delivered', 'The next semester\'s epics are ready'],
            votes => [[2, 2, 2]],
            tasks => [ _tk('The twelve-week briefing and memo', 2, 'jim', 'briefing') ]),
        ] };
    push @S, _later();
    \@S;
}

# ---------------------------------------------------------------------- sprints 7-39: the epics, as generated stories
sub _later {
    my @S;
    my %drop_sprint = (8 => 2, 14 => 3, 20 => 4, 27 => 5, 34 => 6, 38 => 7);   # the sprint each drop is taken in
    my %goal = (7 => 'Behavior closed; the interaction and the constraint by hand', 8 => 'Drop 2 merged; the hygrometer in the model',
        9 => 'Complexity guardrails; the local assistant approved', 10 => 'First backup and restore test; the port\'s last structure work',
        11 => 'Requirements trace complete for Stations', 12 => 'Verification cases for every system requirement',
        13 => 'Second runner; the release runner protected', 14 => 'Drop 3: the Storm mode reworked by hand', 15 => 'Behavior epic closed',
        16 => 'Acceptance review preparation', 17 => 'Intake automation: the prime\'s Jenkins delivers', 18 => 'Independent review of the v2 model',
        19 => 'Release candidate for baseline 1', 20 => 'Drop 4 through the pipeline; baseline 1');
    for my $n (7 .. 39) {
        my @st;
        my $d = $drop_sprint{$n};
        push @st, _drop_story($n, $d) if $d;
        push @st, @{ _epic_stories($n) };
        push @S, { n => $n, goal => $goal{$n} // ($d ? "Drop $d taken in; " : '') . _theme($n), pulse => _pulse($n),
                   retro => { start => [], stop => [], continue => [] }, quotes => [], stories => \@st };
    }
    @S;
}
sub _pulse { my $n = shift; my @p = (4.1, 4.0, 4.2, 4.1, 4.3, 4.2, 3.9, 4.1, 4.3, 4.2, 4.2, 4.0, 4.3, 4.4); $p[ ($n - 7) % @p ] }
sub _theme { my $n = shift; $n <= 20 ? 'the port continues' : $n <= 33 ? 'engineering with the model' : 'sustainment' }
sub _drop_story {
    my ($n, $d) = @_;
    my $ver = 'v1.' . ($d - 1);
    my $epic = $d <= 3 ? 'E9' : $d <= 5 ? 'E12' : 'E13';
    my $jenkins = $d >= 4;
    my @t = ($jenkins ? _tk("Intake pipeline: the prime's Jenkins delivered $ver", 1, 'tom', 'intake', drop => $d)
                      : _tk("Receive $ver and check its MANIFEST", 1, 'jim', 'drop_check', drop => $d),
             _tk("Open the Prime Drop issue for $ver", 1, 'jim', 'drop_issue', drop => $d),
             _tk("Import $ver onto vendor/prime; read the delta", 1, 'tom', 'vendor', drop => $d),
             _tk("Resolve conflicts and merge $ver to develop", 2, 'bob', 'drop_merge', drop => $d),
             _tk("Rework by hand what the delta marks manual", 2, 'bob', 'drop_rework', drop => $d),
             _tk("Close the DRs $ver fixes; open new ones", 1, 'jim', 'drop_drs', drop => $d));
    _st(key => "S$n-drop$d", epic => $epic, work => 'engineering', owner => 'tom', area => 'requirements', prio => 1,
        title => "Take in prime drop $ver", why => "The prime's drop $d must be on develop within the sprint, with its manual rework done.",
        done => ["$ver merged to develop through vendor/prime", 'Every manual delta line reworked', 'DRs updated'],
        votes => [[5, 8, 8], [8, 8, 8]], tasks => \@t);
}
sub _epic_stories {
    my $n = shift;
    my %plan = (
        7 => [ ['E6', 'engineering', 'bob', 'stations', 'Break the Stations <-> DataCenter cycle', [['Remove the QualityControl -> SensorSuite dependency', 2, 'bob', 'model_mr', edits => [['cycles', which => 'sd']], title => 'Break the Stations <-> DataCenter cycle']]],
               ['E8', 'engineering', 'bob', 'behavior', 'The DailyUpload interaction by hand', [['Steps of DailyUpload as an action def', 2, 'bob', 'model_mr', edits => [['interaction']], title => 'DailyUpload in SysML v2']]],
               ['E8', 'engineering', 'jim', 'analysis', 'The EnergyBalance constraint expression', [['Write the constraint expression', 2, 'jim', 'model_mr', edits => [['constraint']], title => 'EnergyBalance expression']]],
               ['E8', 'engineering', 'tom', 'legacy', 'Retire the Tidewater Profile TODO', [['Point the profile TODO at Conventions', 1, 'tom', 'model_mr', edits => [['profile']], title => 'Replace the profile TODO']]],
               ['E2', 'platform', 'tom', 'pipeline', 'Pin the kit version', [['.kit-version and its check', 2, 'tom', 'kit_pin']]] ],
        8 => [ ['E2', 'platform', 'tom', 'pipeline', 'Split the pipeline into .gitlab/ci/*.yml includes', [['Split the pipeline file with include: local', 2, 'tom', 'note']]] ],
        9 => [ ['E2', 'platform', 'tom', 'pipeline', 'Complexity guardrails in the pipeline', [['Add the complexity job and the layers', 3, 'tom', 'ci_level', level => 7]]],
               ['E4', 'platform', 'jim', 'pipeline', 'Approval to use a local SysML assistant', [['Request under the AI policy', 1, 'jim', 'note'], ['Install Ollama and the model offline on the three laptops', 1, 'tom', 'note']]],
               ['E14', 'platform', 'tom', 'pipeline', 'Token leak rehearsal', [['Rehearse a leaked token: revoke, rotate, mask', 1, 'tom', 'note']]] ],
        10 => [ ['E14', 'platform', 'tom', 'pipeline', 'First backup and restore test', [['Restore the project export into a scratch group', 2, 'tom', 'note']]] ],
        13 => [ ['E14', 'platform', 'tom', 'pipeline', 'A second runner; the release runner protected', [['Register a second runner and protect the release runner', 2, 'tom', 'note']]] ],
        17 => [ ['E11', 'platform', 'tom', 'pipeline', 'Deliveries from the prime\'s Jenkins', [['Deploy token and trigger token for the prime', 1, 'tom', 'tokens'], ['The intake job in the pipeline', 2, 'tom', 'ci_level', level => 8]]] ],
        19 => [ ['E10', 'platform', 'tom', 'pipeline', 'Baselines as packages for downstream users', [['publish-package and the release links', 2, 'tom', 'ci_level', level => 9]]] ],
        20 => [ ['E10', 'engineering', 'tom', 'pipeline', 'Baseline 1', [['Release branch, CCB, tag baseline-1, back-merge', 2, 'tom', 'release', name => 'baseline-1']]] ],
        22 => [ ['E12', 'engineering', 'jim', 'verification', 'Run the Stations VCRM beside the prime\'s legacy test matrix (drops 4-5)', [['Reconcile the VCRM with the legacy test matrix: report', 2, 'jim', 'note']]] ],
        28 => [ ['E12', 'engineering', 'jim', 'verification', 'Retire the legacy test matrix for Stations', [['Deputy PM agreement; the VCRM is the record for Stations', 1, 'jim', 'note']]] ],
        24 => [ ['E14', 'engineering', 'bob', 'requirements', 'Hotfix: a wrong satisfy found by the program office', [['hotfix/satisfy-sys-014 to main and develop', 2, 'bob', 'hotfix', name => 'satisfy-sys-014']]] ],
        30 => [ ['E14', 'engineering', 'tom', 'pipeline', 'Baseline 2', [['Release branch, CCB, tag baseline-2, back-merge', 2, 'tom', 'release', name => 'baseline-2']]] ],
        39 => [ ['E14', 'engineering', 'tom', 'pipeline', 'Baseline 3', [['Release branch, CCB, tag baseline-3, back-merge', 2, 'tom', 'release', name => 'baseline-3']]],
                ['E14', 'engineering', 'jim', 'pipeline', 'Runbook and lessons learned', [['Write the runbook and lessons learned', 2, 'jim', 'wiki', pages => ['Drop Intake Runbook', 'Baseline Procedure']]]] ],
    );
    my %e15 = (21 => 'Energy balance per buoy mode, with a check that fails when a mode does not close', 23 => 'Observation-to-bulletin latency chain against TW-STK-002',
               25 => 'Telemetry trade study: cellular, satellite, hybrid', 27 => 'Station availability allocation',
               29 => 'Verification cases for Stations to 100% coverage', 31 => 'Retire TW-SEG-009', 33 => 'Energy balance with the drop-5 reserve term');
    my @out;
    for my $s (@{ $plan{$n} // [] }) {
        my ($epic, $work, $owner, $area, $title, $tasks) = @$s;
        push @out, _st(key => "S$n-" . lc(substr($title =~ s/\W+//gr, 0, 12)), epic => $epic, work => $work, owner => $owner, area => $area, title => $title,
                       why => "$title.", done => ["The MR's pipeline is green: grammar, lint 0/0, the outline and trace ratchets", "$title: on develop, shown on the model site"],
                       votes => [[2, 2, 2]], tasks => [ map { _tk(@$_) } @$tasks ]);
    }
    if ($e15{$n}) {
        push @out, _st(key => "S$n-e15", epic => 'E15', work => 'engineering', owner => 'bob', area => 'analysis', title => $e15{$n},
                       why => 'Engineering with the model: an answer computed from the model, checked by the pipeline (notional values).',
                       done => ['The analysis is in model/gov with notional values', 'Its check runs in the pipeline'], votes => [[3, 5, 5], [5, 5, 5]],
                       tasks => [ _tk('Model the analysis in model/gov (notional values)', 3, 'bob', 'note'), _tk('Review the result with the program office', 1, 'jim', 'note') ]);
    }
    if ($n >= 7 && $n <= 16 && !grep { $_->{epic} =~ /E[68]/ } @out) {      # the remaining port work: requirements and verification
        push @out, _st(key => "S$n-trace", epic => 'E7', work => 'engineering', owner => 'bob', area => 'requirements', title => 'Trace completeness, package by package',
                       why => 'Every requirement satisfied and verified, or a DR to the prime.', done => ['The trace report shows the package complete'],
                       votes => [[3, 3, 3]], tasks => [ _tk('Check satisfy and verify for the package; DRs for the gaps', 3, 'bob', 'note') ]);
    }
    my %e16 = (24 => ['Markings on every package; model.pl gate in the pipeline', 'tom'], 26 => ['Trust zones on the part tree', 'bob'],
               28 => ['A notional threat register', 'tom'], 30 => ['Security requirements TW-SEC through DRs to the prime', 'jim'],
               31 => ['Security verification cases in the VCRM', 'bob'], 32 => ['Signed baseline tags', 'tom']);
    if (my $e = $e16{$n}) {
        push @out, _st(key => "S$n-e16", epic => 'E16', work => 'engineering', owner => $e->[1], area => 'gov', title => $e->[0],
                       why => 'Security engineered into the model, not bolted on: civilian and notional.', done => ["$e->[0]: on develop, checked by the pipeline"],
                       votes => [[3, 3, 3]], tasks => [ _tk($e->[0], 3, $e->[1], 'note') ]);
    }
    if ($n >= 27) {                                                       # sustainment: the monthly rhythm
        push @out, _st(key => "S$n-ops", epic => 'E14', work => 'platform', owner => 'tom', area => 'pipeline', title => 'Sustainment: runners, tokens, access review',
                       why => 'The platform keeps working without anyone noticing it.', done => ['Runner patched, tokens current, access reviewed'],
                       votes => [[2, 2, 2]], tasks => [ _tk('Patch the runner; review tokens and members', 2, 'tom', 'note') ]);
    }
    push @out, _st(key => "S$n-ccb", epic => ($n <= 20 ? 'E7' : 'E15'), work => 'engineering', owner => 'jim', area => 'requirements', title => 'Monthly status and CCB items',
                   why => 'Program management gets the scorecard; the CCB sees the changes through their MRs.', done => ['The status memo is out'],
                   votes => [[2, 2, 2]], tasks => [ _tk('Status memo and CCB items', 2, 'jim', 'note') ]) if $n % 2 == 0;
    \@out;
}

1;
