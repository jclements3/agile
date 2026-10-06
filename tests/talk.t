#!/usr/bin/perl
# perl tests/talk.t -- tools/gitlab/talk.pl: stand-up line, review script, weekly note and translate, against the local
# GitLab emulator seeded with one small sprint (issues, tasks, MRs, pipelines with metrics reports, a blocked issue);
# the stand-up line must pass the kit's own lint (daily.pl lint in a journal made with daily.pl init)
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use File::Temp qw(tempdir);
use GitLab;
use JSON::PP ();

my ($n, $bad) = (0, 0);
sub ok { my ($c, $name) = @_; $n++; if ($c) { print "ok $n - $name\n" } else { $bad++; print "not ok $n - $name\n" } return $c }
sub is { my ($got, $want, $name) = @_; ok(scalar(defined $got && $got eq $want), $name) or print "#   got:  " . ($got // 'undef') . "\n#   want: $want\n" }
sub like { my ($got, $re, $name) = @_; ok(scalar(defined $got && $got =~ $re), $name) or print "#   got:  " . ($got // 'undef') . "\n#   want: $re\n" }
sub unlike { my ($got, $re, $name) = @_; ok(scalar(defined $got && $got !~ $re), $name) or print "#   got:  $got\n#   must not match: $re\n" }

my $ROOT = "$FindBin::Bin/..";
my $TALK = "$ROOT/tools/gitlab/talk.pl";
my $tmp = tempdir(CLEANUP => 1);
my $gldir = "$tmp/gl";
my $P = 'tidewater/model';

# ---------------------------------------------------------------- seed: one sprint in the emulator
my $gl = GitLab->new(local => $gldir, now => '2026-12-07T09:00:00Z', freeze => 1);
$gl->create_user($_, name => ucfirst $_, email => "$_\@example.invalid") for qw(jim bob tom);
$gl->create_group('tidewater');
$gl->create_project($P, default_branch => 'develop');
$gl->add_member($P, 'jim', 40); $gl->add_member($P, 'bob', 30); $gl->add_member($P, 'tom', 40);
$gl->create_label($P, $_, '#428BCA', '') for qw(type::story type::task type::discrepancy workflow::in-progress workflow::blocked prime-change);
$gl->create_milestone($P, 'Sprint 5', start_date => '2026-11-30', due_date => '2026-12-11', description => "Goal: DataCenter and Operations closed; release rehearsed\n");
$gl->create_milestone($P, 'Sprint 6', start_date => '2026-12-14', due_date => '2026-12-25',
                      description => "**Question:** can we show every Stations requirement has a verification?\n");
$gl->create_milestone($P, 'Sprint 4', start_date => '2026-11-16', due_date => '2026-11-27');
my $at = sub { $gl->clock($_[0]) };

$gl->as('jim');
$at->('2026-12-07T09:30:00Z');
my $s1 = $gl->create_issue($P, title => 'Close DataCenter and Operations', labels => ['type::story'], milestone => 'Sprint 5', assignees => ['bob'], weight => 4);
my $t1 = $gl->create_issue($P, title => 'Close the DataCenter level tags', labels => ['type::task'], milestone => 'Sprint 5', assignees => ['bob'], issue_type => 'task',
                           description => "Part of #$s1->{iid}");
my $t2 = $gl->create_issue($P, title => 'Close the Operations level tags', labels => ['type::task'], milestone => 'Sprint 5', assignees => ['bob'], issue_type => 'task',
                           description => "Part of #$s1->{iid}");
my $t3 = $gl->create_issue($P, title => 'Decide who owns ObservationRecord', labels => ['type::task', 'workflow::in-progress'], milestone => 'Sprint 5', assignees => ['bob'],
                           issue_type => 'task', description => "Part of #$s1->{iid}", due_date => '2026-12-10');
my $s2 = $gl->create_issue($P, title => 'Toolchain security plan to the ISSM', labels => ['type::story'], milestone => 'Sprint 5', assignees => ['tom'], weight => 3);
my $t4 = $gl->create_issue($P, title => 'Register the second runner', labels => ['type::task', 'workflow::blocked'], milestone => 'Sprint 5', assignees => ['tom'],
                           issue_type => 'task', description => "Part of #$s2->{iid}");
$gl->as('tom');
$gl->add_note($P, 'issue', $t4->{iid}, 'Blocked by: IT approval of the runner machine -- need: Jim to escalate to the IT lead today');
my $dr = $gl->create_issue($P, title => 'DR-2: TW-SYS-012 has no satisfy', labels => ['type::discrepancy'], milestone => 'Sprint 5');

# Tuesday 8 Dec: Bob closes a task, merges an MR; Jim reviews Tom's MR
$at->('2026-12-08T14:00:00Z');
$gl->as('bob');
$gl->update_issue($P, $t1->{iid}, state_event => 'close');
my $proj = $gl->_p($P);
$proj->{default_branch} = 'develop';                # gitflow: develop is the default branch
my %mrbase = (project_id => $proj->{id}, labels => [], assignees => [], reviewers => [], approved_by => [], notes => [], pipelines => [], draft => 0);
push @{ $proj->{mrs} },
    { %mrbase, id => 9001, iid => 21, title => 'Close the DataCenter level tags', description => "Closes #$t1->{iid}", state => 'merged', source_branch => 'feature/2-dc',
      target_branch => 'develop', author => { username => 'bob' }, created_at => '2026-12-08T10:00:00Z', updated_at => '2026-12-08T13:00:00Z',
      merged_at => '2026-12-08T13:00:00Z', head_pipeline => { id => 3, status => 'success' } },
    { %mrbase, id => 9002, iid => 22, title => 'Security plan draft', description => "Part of #$s2->{iid}", state => 'opened', source_branch => 'feature/5-plan',
      target_branch => 'develop', author => { username => 'tom' }, created_at => '2026-12-08T09:40:00Z', updated_at => '2026-12-08T11:00:00Z',
      notes => [ { id => 1, body => 'Which control baseline does this follow?', author => { username => 'jim' }, created_at => '2026-12-08T11:00:00Z', system => 0 } ] },
    { %mrbase, id => 9003, iid => 20, title => 'Close the Network TODOs', description => 'Closes #99', state => 'merged', source_branch => 'feature/1-net',
      target_branch => 'develop', author => { username => 'bob' }, created_at => '2026-11-24T10:00:00Z', updated_at => '2026-11-25T10:00:00Z',
      merged_at => '2026-11-25T10:00:00Z', head_pipeline => { id => 1, status => 'success' } };
my %plbase = (project_id => $proj->{id}, ref => 'develop', source => 'push', status => 'success', jobs => [ map { { name => $_, status => 'success' } } qw(grammar lint trace vcrm docs pages) ]);
push @{ $proj->{pipelines} },
    { %plbase, id => 1, created_at => '2026-11-25T10:01:00Z', finished_at => '2026-11-25T10:05:00Z', duration => 240,
      reports => { metrics => { todo_lines => 61, trace_total => 30, trace_linked => 29, trace_unverified => 9 } } },
    { %plbase, id => 2, created_at => '2026-12-04T10:01:00Z', finished_at => '2026-12-04T10:05:00Z', duration => 240,
      reports => { metrics => { todo_lines => 52, trace_total => 30, trace_linked => 29, trace_unverified => 9 } } },
    { %plbase, id => 3, created_at => '2026-12-08T13:01:00Z', finished_at => '2026-12-08T13:05:00Z', duration => 240,
      reports => { metrics => { todo_lines => 43, trace_total => 30, trace_linked => 29, trace_unverified => 8, vcrm_requirements => 30, vcrm_verified => 1, vcrm_verified_pct => 3.3 } } };
$proj->{pages} = { url => 'https://tidewater.pages.gitlab.local/model/', path => "$gldir/pages/$P" };
$at->('2026-12-09T08:00:00Z');
$gl->save;

my $run = sub { my $o = qx{"$^X" "$TALK" --local "$gldir" --project $P @_ 2>&1}; ($o, $? >> 8) };

# ---------------------------------------------------------------- standup
my ($out, $rc) = $run->('standup --as bob --date 2026-12-09 --prefix TW- --why');
is($rc, 0, 'standup exits 0');
my ($line) = $out =~ /^(Y .*)$/m;
like($line, qr/^Y TW-$s1->{iid} Close DataCenter and Operations: 9 TODOs closed, 43 left\./, 'Y: the story, outcome first, one number from the todo metrics');
like($line, qr/ T TW-$s1->{iid} decide who owns ObservationRecord, by Thu\./, 'T: the in-progress task, under its story id, with its day');
like($line, qr/ B none$/, 'B: none for Bob');
like($out, qr/^# lint: ok$/m, 'the draft passes the kit lint (self-check)');
like($out, qr/^# from: .*todo_lines on develop: 52 -> 43/m, '--why says where the number came from');
like($out, qr/edit it, then post it yourself/, 'the draft says it is a draft');

($out, $rc) = $run->('standup --as tom --date 2026-12-09 --prefix TW-');
my ($tline) = $out =~ /^(Y .*)$/m;
like($tline, qr/B TW-$s2->{iid} register the second runner blocked: IT approval of the runner machine -- need: Jim to escalate to the IT lead today$/,
     'a workflow::blocked issue becomes an ask, with the reason from its note');
like($tline, qr/^Y TW-$s2->{iid} Toolchain security plan to the ISSM: !22 up for review\. /, 'an opened MR is progress: "up for review", with its number');

($out, $rc) = $run->('standup --as jim --date 2026-12-09 --prefix TW-');
my ($jline) = $out =~ /^(Y .*)$/m;
like($jline, qr/^Y TW-$s2->{iid} Reviewed !22\./, 'a review-only day: the review, under the story it belongs to');

($out, $rc) = $run->('standup --as bob --date 2026-12-09');
like($out, qr/^Y TI-\d+ /m, 'without --prefix or a journal: a prefix from the group name');

# the kit's lint, on a chat paste made of the three lines
{
    my $proj_dir = "$tmp/journal";
    my $init = qx{"$^X" "$ROOT/bin/daily.pl" init "$proj_dir" 2>&1};
    ok(-f "$proj_dir/scrum.conf", 'daily.pl init made a journal for the lint check') or print "# $init\n";
    open my $sfh, '>', "$proj_dir/standups/2026-12-07.txt" or die;   # the stories, in the journal (TW-<story iid>)
    print $sfh "2026-12-07\nsprint 5\n== Model\nnew TW-$s1->{iid} 4 \"Close DataCenter and Operations\" o:Bob\nnew TW-$s2->{iid} 3 \"Toolchain security plan to the ISSM\" o:Tom\ncommit TW-$s1->{iid} Bob\ncommit TW-$s2->{iid} Tom\n";
    close $sfh;
    my $comp = qx{cd "$proj_dir" && "$^X" "$ROOT/bin/daily.pl" compile 2>&1};
    ok($? == 0, 'the two stories compiled into the journal') or print map { "# $_\n" } split /\n/, $comp;
    my $chat = "$proj_dir/standups/2026-12-09-chat.txt";
    open my $fh, '>', $chat or die "$chat: $!";
    print $fh "[9:01 AM] Bob\n$line\n[9:02 AM] Tom\n$tline\n[9:03 AM] Jim\n$jline\n";
    close $fh;
    my $lint = qx{cd "$proj_dir" && "$^X" "$ROOT/bin/daily.pl" lint "$chat" 2>&1};
    my $lrc = $? >> 8;
    is($lrc, 0, 'daily.pl lint: no ERROR on the drafted lines') or print map { "# $_\n" } split /\n/, $lint;
    unlike($lint, qr/\bERROR\b/, 'no ERROR lines');
    like($lint, qr/ok\s+Bob/, 'Bob ok');
    unlike($lint, qr/\bwarn\b/, 'no warnings either (ids in the journal, ids in Y and T)');
    my ($jo) = $run->("standup --as bob --date 2026-12-09 --journal \"$proj_dir\"");
    like($jo, qr/^Y TW-$s1->{iid} /m, "--journal: the story prefix comes from the journal's ids");
}

# ---------------------------------------------------------------- review
($out, $rc) = $run->('review --sprint 5');
is($rc, 0, 'review exits 0');
like($out, qr/"Did we do what we set out to do: DataCenter and Operations closed; release rehearsed\?"/, 'the question from the milestone goal');
like($out, qr/- TODO lines left: 43 \(down 18 from 61\)/, 'TODO lines with the change since the sprint started');
like($out, qr/- Requirements with a verification case: 22 of 30 \(73\.3%\) \(up 1 from 21\)\n/, 'headline: requirements with a verification case, from the trace, with change');
like($out, qr/^    \(a different measure: requirements with a passing recorded result, from the VCRM: 1 of 30\)$/m, 'the VCRM passing-results share is shown apart, under its own name');
unlike($out, qr/verify coverage/i, 'no measure is called "verify coverage" (two different measures had shared the name)');
like($out, qr/- Open discrepancy reports and prime changes: 1/, 'open DRs counted');
like($out, qr/- Blocked items: 1/, 'blocked items counted');
like($out, qr{The model site: https://tidewater\.pages\.gitlab\.local/model/}, 'the Pages site to show');
like($out, qr/!21 Close the DataCenter level tags/, 'a merged, green change to show');
like($out, qr/Delete one satisfy line on a scratch branch/, 'a safe live change, chosen because the trace job runs');
like($out, qr/Sprint 6 starts Mon Dec 14: 43 TODO lines to go/, 'what it means for the next milestone');
like($out, qr/- Need: Jim to escalate to the IT lead today \(#$t4->{iid} /, 'the ask from the blocked issue');
like($out, qr/30-SECOND VERSION\nSprint 5: 0 of 2 stories done, 43 TODO lines left \(down 18\), 22 of 30 requirements with a verification case\. We need help with 1 blocked item\./, '30-second version');
like($out, qr/1-SENTENCE VERSION\nSprint 5 moved the model forward by 0 stories and 18 TODO lines\./, '1-sentence version');

open my $bfh, '>', "$tmp/baseline.txt" or die; print $bfh "# document era\nreview_hours = 360 | a document review cycle: 3 weeks of comments on a Word file\n"; close $bfh;
($out) = $run->("review --sprint 6 --baseline \"$tmp/baseline.txt\" --md");
like($out, qr/^# Sprint 6 review/m, '--md: Markdown heading');
like($out, qr/"can we show every Stations requirement has a verification\?"/, 'the question from the milestone description');
($out) = $run->("review --sprint 5 --baseline \"$tmp/baseline.txt\"");
like($out, qr/- Before: from proposing a change to the first review took 15\.0 days \(a document review cycle: 3 weeks of comments on a Word file\)\. Now: [\d.]+ h, median this sprint\./,
     'before/after from the baseline file and analytics');

($out, $rc) = $run->('review --sprint 9');
is($rc, 2, 'an unknown sprint is an error');
like($out, qr/talk: no milestone 'Sprint 9'/, 'and says which');

# ---------------------------------------------------------------- weekly
($out, $rc) = $run->('weekly --date 2026-12-09');
is($rc, 0, 'weekly exits 0');
like($out, qr/^Weekly note, week of Dec 7 -- /m, 'weekly heading');
like($out, qr/^- 0 stories finished this week \(1 change accepted into the model\)$/m, 'the numbers: stories and changes');
like($out, qr/^- 43 TODO lines left to port by hand \(down 9 from 52\)$/m, 'the numbers: TODO lines with change');
like($out, qr/^- Requirements with a verification case: 22 of 30 \(73\.3%\) \(up 1 from 21\)$/m, 'weekly: the trace measure, named');
like($out, qr/^- Separately: 1 of 30 requirements have a passing recorded result \(VCRM\)$/m, 'weekly: the VCRM measure, apart and named');
like($out, qr/^- #$t4->{iid} Register the second runner is blocked: IT approval of the runner machine\.$/m, 'risks: the blocked issue');
like($out, qr/^- Jim to escalate to the IT lead today \(#$t4->{iid}\)$/m, 'asks');
like($out, qr/daily\.pl quad/, 'points at the quad for detail');

# ---------------------------------------------------------------- translate: never rewrites a sentence
# the sample and six realistic status lines; every output line must read as English (no doubled words, no spliced
# glossary phrases), and the plain version may differ from the input only by whole noun-for-noun swaps
my @LINES = (
    "Rebased my feature branch and fixed the lint errors so the pipeline is green.",
    "Working on the VCRM.",
    "Still working on the XMI extraction script for the prime drop.",
    "Waiting on runner approval from IT.",
    "Refactoring the library package.",
    "The nightly pipeline failed on the trace job because of 2 orphans in Stations.",
    "Opened 2 DRs against the prime drop and the MRs for TW-14 are merged.",
);
my %PLAIN = (
    0 => "Rebased my feature branch and fixed the lint errors so the pipeline is green.",
    1 => "Working on the verification matrix.",
    2 => "Still working on the XMI extraction script for the prime model update.",
    3 => "Waiting on check machine approval from IT.",
    4 => "Refactoring the library package.",
    5 => "The nightly pipeline failed on the trace job because of 2 orphans in Stations.",
    6 => "Opened 2 discrepancy reports against the prime model update and the proposed changes for TW-14 are merged.",
);
my $GARBLE = qr/\b(\w+)\s+\1\b|\b(?:the|a|an|my|our)\s+(?:the|a|an|my|our)\b|\bmy (?:brought|accepted|all)\b|\bfixed the (?:check|errors the)\b|\bthe all\b|\bfor the all\b/i;
open my $dfh, '>', "$tmp/draft.txt" or die; print $dfh join("\n", @LINES), "\n"; close $dfh;
($out, $rc) = $run->("translate \"$tmp/draft.txt\"");
is($rc, 0, 'translate exits 0');
my ($plain) = $out =~ /^Plain version[^\n]*\n(.*?)\n\n/ms;
my @pl = split /\n/, $plain // '';
is(scalar @pl, scalar @LINES, 'the plain version has one line per input line');
for my $i (0 .. $#LINES) {
    is($pl[$i], $PLAIN{$i}, "plain version, line " . ($i + 1) . ": only whole nouns swapped");
    unlike($pl[$i] // '', $GARBLE, "plain version, line " . ($i + 1) . ": no doubled or spliced phrases");
}
unlike($_, $GARBLE, "no garbled phrase: " . substr($_, 0, 50)) for grep { /\S/ } split /\n/, $out;
like($out, qr/^  "Rebased" -> brought my change up to date\. Hint: say what it achieved, or leave it out/m, 'a jargon term: plain alternative and hint, not spliced in');
like($out, qr/^  "lint errors" -> errors the automated checks found\. Hint: say how many/m, 'lint errors: listed with its hint');
like($out, qr/^  "the pipeline is green" -> all automated checks passed\./m, 'a phrase is listed whole');
unlike($out, qr/^  "pipeline" -> .*\n(?:.*\n)*?^  "pipeline" -> /m, 'each term listed once');
like($out, qr/^  1\. "Rebased my feature branch[^"]*" -- no number$/m, 'so what?: no number');
like($out, qr/^  2\. "Working on the VCRM\." -- no number; no outcome/m, 'so what?: no number, no outcome');
like($out, qr/^     SUGGESTION: Done: \[what is now true -- topic: verification matrix\] \(\[one number: how many, how much\]\)\. Next: \[outcome, by a day\]\. Need: \[an ask, or none\]\.$/m,
     'SUGGESTION: the template, topic named, everything unknown left in [brackets]');
like($out, qr/^  7\. "Opened 2 DRs[^"]*" -- passive: say who did what$/m, 'so what?: passive');
like($out, qr/SUGGESTION: Done: TW-14 \[what is now true -- topic: proposed change, discrepancy report\] \(2 discrepancy reports\)\./, "SUGGESTION: the sentence's own id and number filled in");
unlike($out, qr/^  6\. /m, 'a sentence with a number and an outcome ("failed") is not flagged');
like($out, qr/Rework the flagged sentences, then say it\.$/, 'closing line when something is flagged');

$out = qx{echo "We closed 9 TODO lines, 43 left." | "$^X" "$TALK" translate - 2>&1};
like($out, qr/none: every sentence has a number and an outcome/, 'standard input; a clean draft has nothing to rework');
like($out, qr/^We closed 9 hand-port items, 43 left\.$/m, 'plain version of a clean line: noun swap only');
like($out, qr/Ready to say\.$/, 'and is ready to say');
open my $gfh, '>', "$tmp/glossary.txt" or die; print $gfh "# ours\nTRR = test readiness review | say which test event and its date\n"; close $gfh;
$out = qx{echo "TRR moved." | "$^X" "$TALK" translate --glossary "$tmp/glossary.txt" - 2>&1};
like($out, qr/"TRR" -> test readiness review\. Hint: say which test event and its date\./, '--glossary adds a team term with its hint');
like($out, qr/^TRR moved\.$/m, 'a glossary term is listed, never spliced into the sentence');
$out = qx{echo "Working on the VCRM." | "$^X" "$TALK" translate --md - 2>&1};
like($out, qr/^## Jargon to replace\n- "VCRM" -> verification matrix\./m, '--md');

# ---------------------------------------------------------------- the REST backend (tests/fake-curl.pl): metrics from job artifacts,
# blocker reasons from issue notes, and only GET requests
{
    my $resp = "$tmp/rest-responses.txt";
    my $log = "$tmp/rest-requests.jsonl";
    my $J = sub { my $t = shift; $t =~ s/\s*\n\s*/ /g; $t };
    my @blocks = (
        [ 'GET', 'jobs/artifacts/develop/raw/todo\.metrics\?job=todo', 200, "todo_lines 43\ntodo_lines_stations 20\n" ],
        [ 'GET', 'jobs/artifacts/develop/raw/trace\.metrics\?job=trace', 200, "trace_total 30\ntrace_linked 29\ntrace_unverified 8\n" ],
        [ 'GET', 'jobs/artifacts/develop/raw/(vcrm|recipe)\.metrics', 404, '{"message":"404 Not found"}' ],
        [ 'GET', '/issues/6/notes', 200, $J->(q{[{"id":1,"body":"Blocked by: IT approval of the runner machine -- need: Jim to escalate to the IT lead today",
                                                   "author":{"username":"tom"},"created_at":"2026-12-07T10:00:00Z","system":false}]}) ],
        [ 'GET', '/issues/\d+/notes', 200, '[]' ],
        [ 'GET', '/projects/tidewater%2Fmodel/issues', 200, $J->(q{[
            {"iid":1,"title":"Close DataCenter and Operations","state":"opened","labels":["type::story"],"assignees":[{"username":"bob"}],
             "milestone":{"title":"Sprint 5"},"description":"","created_at":"2026-12-07T09:30:00Z","closed_at":null},
            {"iid":2,"title":"Close the DataCenter level tags","state":"closed","labels":["type::task"],"assignees":[{"username":"bob"}],
             "milestone":{"title":"Sprint 5"},"description":"Part of #1","created_at":"2026-12-07T09:30:00Z","closed_at":"2026-12-08T14:00:00Z"},
            {"iid":4,"title":"Decide who owns ObservationRecord","state":"opened","labels":["type::task","workflow::in-progress"],"assignees":[{"username":"bob"}],
             "milestone":{"title":"Sprint 5"},"description":"Part of #1","created_at":"2026-12-07T09:30:00Z","closed_at":null,"due_date":"2026-12-10"},
            {"iid":5,"title":"Toolchain security plan to the ISSM","state":"opened","labels":["type::story"],"assignees":[{"username":"tom"}],
             "milestone":{"title":"Sprint 5"},"description":"","created_at":"2026-12-07T09:30:00Z","closed_at":null},
            {"iid":6,"title":"Register the second runner","state":"opened","labels":["type::task","workflow::blocked"],"assignees":[{"username":"tom"}],
             "milestone":{"title":"Sprint 5"},"description":"Part of #5","created_at":"2026-12-07T09:30:00Z","closed_at":null}]}) ],
        [ 'GET', '/projects/tidewater%2Fmodel/merge_requests', 200, $J->(q{[
            {"iid":21,"title":"Close the DataCenter level tags","description":"Closes #2","state":"merged","source_branch":"feature/2-dc","target_branch":"develop",
             "author":{"username":"bob"},"created_at":"2026-12-08T10:00:00Z","merged_at":"2026-12-08T13:00:00Z","labels":[]}]}) ],
        [ 'GET', '/projects/tidewater%2Fmodel/pipelines', 200, $J->(q{[
            {"id":3,"ref":"develop","status":"success","source":"push","created_at":"2026-12-08T13:01:00Z","updated_at":"2026-12-08T13:05:00Z"}]}) ],
        [ 'GET', '/projects/tidewater%2Fmodel/milestones', 200, $J->(q{[
            {"title":"Sprint 5","start_date":"2026-11-30","due_date":"2026-12-11","description":"Goal: DataCenter and Operations closed"},
            {"title":"Sprint 6","start_date":"2026-12-14","due_date":"2026-12-25","description":""}]}) ],
        [ 'GET', '/projects/tidewater%2Fmodel/pages', 404, '{"message":"404 Not found"}' ],
        [ 'GET', '/projects/tidewater%2Fmodel(\?|$)', 200, '{"id":7,"path_with_namespace":"tidewater/model","default_branch":"develop"}' ],
    );
    open my $rf, '>', $resp or die; print $rf join("----\n", map { "$_->[0] $_->[1]\n$_->[2]\nContent-Type: application/json\n\n$_->[3]\n" } @blocks); close $rf;
    local $ENV{FAKE_CURL_RESPONSES} = $resp;
    local $ENV{FAKE_CURL_LOG} = $log;
    local $ENV{GL_TEST_TOKEN} = 'glpat-test';
    my $rest = sub { my $o = qx{"$^X" "$TALK" --url https://gitlab.example.com --token-env GL_TEST_TOKEN --curl "$^X $FindBin::Bin/fake-curl.pl" --project $P @_ 2>&1}; ($o, $? >> 8) };
    my ($o2, $rc2) = $rest->('standup --as tom --date 2026-12-09 --prefix TW-');
    is($rc2, 0, 'REST: standup exits 0');
    like($o2, qr/B TW-5 register the second runner blocked: IT approval of the runner machine -- need: Jim to escalate to the IT lead today$/m,
         'REST: the blocker reason and the ask come from the issue notes (issue_notes)');
    ($o2, $rc2) = $rest->('weekly --date 2026-12-09');
    is($rc2, 0, 'REST: weekly exits 0');
    like($o2, qr/^- 43 TODO lines left to port by hand$/m, 'REST: todo_lines from the develop pipeline\'s todo.metrics artifact (job_artifact), no --metrics');
    like($o2, qr/^- Requirements with a verification case: 22 of 30 \(73\.3%\)$/m, 'REST: requirements with a verification case, from trace.metrics');
    open my $mf, '>', "$tmp/override.metrics" or die; print $mf "todo_lines 40\n"; close $mf;
    ($o2) = $rest->("weekly --date 2026-12-09 --metrics \"$tmp/override.metrics\"");
    like($o2, qr/^- 40 TODO lines left to port by hand$/m, 'REST: --metrics still overrides the artifacts');
    open my $lf, '<', $log or die; my @req = map { JSON::PP->new->decode($_) } <$lf>; close $lf;
    ok(scalar(grep { $_->{url} =~ m{/jobs/artifacts/develop/raw/todo\.metrics\?job=todo} } @req), 'REST: the artifact was fetched through the jobs API');
    ok(scalar(grep { $_->{url} =~ m{/issues/6/notes} } @req), 'REST: the blocked issue\'s notes were fetched');
    is(join(',', sort { $a cmp $b } keys %{ { map { ($_->{method} // 'GET') => 1 } @req } }), 'GET', 'REST: every request is a GET (talk.pl never changes GitLab)');
}

# ---------------------------------------------------------------- usage and read-only
($out, $rc) = $run->('standup');
is($rc, 2, 'standup without --as is a usage error');
like($out, qr/talk: standup needs --as USER/, 'and says so');
($out, $rc) = (qx{"$^X" "$TALK" frobnicate 2>&1}, $? >> 8);
is($rc, 2, 'unknown command exits 2');
$out = qx{"$^X" "$TALK" help 2>&1};
like($out, qr/DRAFTS ONLY/, 'help prints the header');
my $before = do { open my $fh, '<', "$gldir/gitlab.json"; local $/; <$fh> };
$run->('standup --as bob --date 2026-12-09'); $run->('review --sprint 5'); $run->('weekly --date 2026-12-09');
my $after = do { open my $fh, '<', "$gldir/gitlab.json"; local $/; <$fh> };
ok($before eq $after, 'talk.pl never changes GitLab (the emulator state is untouched)');

print "1..$n\n";
print $bad ? "# $bad of $n FAILED\n" : "# all $n passed\n";
exit($bad ? 1 : 0);
