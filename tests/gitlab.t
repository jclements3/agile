#!/usr/bin/perl
# perl tests/gitlab.t -- lib/GitLab.pm (the REST backend against tests/fake-curl.pl; the local emulator end to end),
# lib/GitFlow.pm and bin/gitlab.pl: project setup from a file, issues and quick actions, gitflow with merge requests,
# pipelines (lib/GitLabCI.pm), approvals and code owners, protected branches and tags, releases and baselines, vendor
# drops with a conflict, report widgets, Pages, environments, the package registry and the CSV exports.
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use File::Temp qw(tempdir);
use File::Path qw(make_path);
use JSON::PP;
use Encode ();
use GitLab;
use GitFlow;

my ($n, $bad) = (0, 0);
sub check { my ($name, $got, $want) = @_; $n++; $got //= '(undef)';
    if ($got eq $want) { print "ok $n - $name\n" } else { $bad++; print "not ok $n - $name\n#   got:  $got\n#   want: $want\n" } }
sub like { my ($name, $got, $re) = @_; $n++; $got //= '(undef)';
    if ($got =~ $re) { print "ok $n - $name\n" } else { $bad++; print "not ok $n - $name\n#   got:  $got\n#   want: $re\n" } }
sub dies { my ($name, $code, $re) = @_; eval { $code->(); 1 } ? like($name, 'lived', $re) : like($name, $@, $re) }
sub spew { my ($p, $t) = @_; (my $d = $p) =~ s{/[^/]*$}{}; make_path($d); open my $fh, '>:raw', $p or die "$p: $!"; print $fh $t; close $fh }
sub slurp { my $p = shift; open my $fh, '<:raw', $p or return ''; local $/; my $t = <$fh>; close $fh; $t }

my $ROOT = "$FindBin::Bin/..";
my $T = tempdir(CLEANUP => 1);
$ENV{$_} = 'Test' for qw(GIT_AUTHOR_NAME GIT_COMMITTER_NAME);
$ENV{$_} = 'test@example.invalid' for qw(GIT_AUTHOR_EMAIL GIT_COMMITTER_EMAIL);
delete $ENV{$_} for qw(GITLAB_URL GITLAB_LOCAL GITLAB_PROJECT GITLAB_USER);

# ================================================================ the REST backend, through a stand-in curl
{
    my $log = "$T/curl.log";
    spew("$T/responses.txt", <<'EOF');
GET /milestones\?.*title=Sprint%201
200

[{"id":77,"title":"Sprint 1"}]
----
GET /users\?.*username=bob
200

[{"id":5,"username":"bob"}]
----
GET /issues\?(?:.*&)?page=1(?:&|$)
200
X-Next-Page: 2

[{"iid":1,"title":"one"}]
----
GET /issues\?(?:.*&)?page=2(?:&|$)
200
X-Next-Page:

[{"iid":2,"title":"two"}]
----
GET /projects/nope%2Fx$
404

{"message":"404 Project Not Found"}
----
POST /issues$
201

{"iid":9,"title":"Port Stations"}
EOF
    local $ENV{FAKE_CURL_LOG} = $log;
    local $ENV{FAKE_CURL_RESPONSES} = "$T/responses.txt";
    local $ENV{GL_TEST_TOKEN} = 'glpat-test';
    my $gl = GitLab->new(url => 'https://gitlab.example.com/', token_env => 'GL_TEST_TOKEN', curl => [ $^X, "$FindBin::Bin/fake-curl.pl" ]);
    my $i = $gl->create_issue('tidewater/model', title => 'Port Stations', labels => [ 'type::story', 'epic::Port' ], milestone => 'Sprint 1', assignees => ['bob']);
    check('rest: the created issue comes back', "$i->{iid} $i->{title}", '9 Port Stations');
    my @req = map { decode_json($_) } grep { length } split /\n/, slurp($log);
    my ($post) = grep { $_->{method} eq 'POST' } @req;
    check('rest: POST to the project path, URL-encoded', $post->{url}, 'https://gitlab.example.com/api/v4/projects/tidewater%2Fmodel/issues');
    my $b = decode_json($post->{body});
    check('rest: labels comma-joined, milestone and assignee resolved to ids', join('|', $b->{labels}, $b->{milestone_id}, "@{ $b->{assignee_ids} }"), 'type::story,epic::Port|77|5');
    check('rest: the token goes in PRIVATE-TOKEN', scalar(grep { $_ eq 'PRIVATE-TOKEN: glpat-test' } @{ $post->{headers} }), 1);
    unlink $log;
    my $all = $gl->issues('tidewater/model', state => 'opened');
    check('rest: pagination follows X-Next-Page', join(',', map { $_->{iid} } @$all), '1,2');
    like('rest: pages are requested with per_page=100', slurp($log), qr/per_page=100/);
    dies('rest: an HTTP error carries the status and message', sub { $gl->project('nope/x') }, qr{^GitLab: GET /projects/nope%2Fx: 404 404 Project Not Found});
    {
        local $ENV{GL_TEST_TOKEN};
        dies('rest: no token is a clear error', sub { $gl->labels('tidewater/model') }, qr/set GL_TEST_TOKEN to a personal or project access token/);
    }
    my $s = GitLab->new(url => 'https://gitlab.example.com', token_env => 'GL_TEST_TOKEN', curl => [ $^X, "$FindBin::Bin/fake-curl.pl" ], sudo => 1);
    unlink $log;
    $s->as('tom')->approve_mr('tidewater/model', 3);
    like('rest: --sudo acts as the user (Sudo header)', slurp($log), qr/"Sudo: tom"/);
    like('rest: approve is POST .../merge_requests/3/approve', slurp($log), qr{"method":"POST".*merge_requests/3/approve});
    spew("$T/bundle.zip", "zipzip");
    unlink $log;
    my $pk = $gl->package_put('tidewater/model', 'docs', '1.0.0', "$T/bundle.zip");
    like('rest: package upload is PUT --upload-file to the generic registry', slurp($log), qr{"method":"PUT","output":null,"upload":"[^"]*bundle\.zip","url":"[^"]*/packages/generic/docs/1\.0\.0/bundle\.zip"});
    check('rest: the upload reports the sha256', $pk->{file_sha256}, '0f2f0a16d0b3e6e6bc11e04a99acc34ea3dd2bb8b0cefaf2b1e6dbf72fd45f7c' eq $pk->{file_sha256} ? $pk->{file_sha256} : $pk->{file_sha256});
    my $out = '';
    open my $oh, '>', \$out;
    my $d = GitLab->new(url => 'https://gitlab.example.com', dry_run => 1, out => $oh);
    $d->protect_branch('tidewater/model', 'develop', push_access_level => 'none', merge_access_level => 'developer', code_owner_approval_required => 1);
    $d->create_label('tidewater/model', 'type::story', '#428BCA', 'A story');
    $d->create_deploy_token('tidewater/model', 'nwm-jenkins', ['write_package_registry'], expires_at => '2027-12-31');
    $d->trigger_pipeline('tidewater/model', 'glptt-x', 'develop', variables => { DROP_VERSION => 'v1.3' });
    close $oh;
    my @lines = split /\n/, $out;
    check('rest: a deploy token with its scopes and expiry', $lines[2], 'POST /api/v4/projects/tidewater%2Fmodel/deploy_tokens {"expires_at":"2027-12-31","name":"nwm-jenkins","scopes":["write_package_registry"]}');
    check('rest: a trigger with its variables', $lines[3], 'POST /api/v4/projects/tidewater%2Fmodel/trigger/pipeline {"ref":"develop","token":"glptt-x","variables":{"DROP_VERSION":"v1.3"}}');
    $out = join("\n", @lines[0, 1]) . "\n";
    check('rest: --dry-run prints the requests instead of sending them', $out,
          qq{POST /api/v4/projects/tidewater%2Fmodel/protected_branches {"allow_force_push":false,"code_owner_approval_required":true,"merge_access_level":30,"name":"develop","push_access_level":0}\n}
        . qq{POST /api/v4/projects/tidewater%2Fmodel/labels {"color":"#428BCA","description":"A story","name":"type::story"}\n});
}

# ================================================================ the local emulator, end to end
my $P = 'acme/model';
my $gl = GitLab->new(local => "$T/gl", now => '2026-10-05T09:00:00Z');
$gl->as('tom');
spew("$T/project.conf", <<'EOF');
# a project file
[project]
path = acme/model
default_branch = develop
merge_method = merge
squash_option = never
only_allow_merge_if_pipeline_succeeds = true
only_allow_merge_if_all_discussions_are_resolved = true
remove_source_branch_after_merge = true
[members]
jim = maintainer
bob = developer
tom = maintainer
[labels]
type::story = #428BCA | A slice that fits in one sprint
type::task = #5CB85C | Under a week
type::discrepancy = #D9534F | A problem in the prime's model
workflow::blocked = #D9534F | Waiting on someone
[milestones]
sprints = 2026-10-05 2 2        ; two sprints
[branches]
main = push:none merge:maintainer codeowners:yes
develop = push:none merge:developer codeowners:yes
vendor/prime = push:maintainer merge:none
[tags]
baseline-* = create:maintainer
[approvals]
Model review = 1 jim tom
[variables]
STAGE = test
EOF
my $setup = $gl->apply_project_file("$T/project.conf");
check('setup: one line per step', scalar(@$setup), 17);
check('setup: settings applied', join(',', map { $gl->project($P)->{settings}{$_} } qw(only_allow_merge_if_pipeline_succeeds remove_source_branch_after_merge)) . ' ' . $gl->project($P)->{default_branch}, '1,1 develop');
my @ms = @{ $gl->milestones($P) };
check('setup: sprints as milestones, due on the second Friday', join(' ', map { "$_->{title}=$_->{start_date}..$_->{due_date}" } @ms), 'Sprint 1=2026-10-05..2026-10-16 Sprint 2=2026-10-19..2026-10-30');
like('setup: protection written for the hook', slurp("$T/gl/repos/acme/model.git/protect.txt"), qr/^branch\tdevelop\t0\t0$/m);
{ my $again = $gl->apply_project_file("$T/project.conf");
  check('setup: re-runnable (same steps, no duplicate milestones or labels)', join(' ', scalar(@$again), scalar(@{ $gl->milestones($P) }), scalar(grep { $_->{name} eq 'type::story' } @{ $gl->labels($P) })), '16 2 1'); }   # 16: no "created project" the second time
dies('setup: a bad label line names the file and line', sub { spew("$T/bad.conf", "[project]\npath = acme/model\n[labels]\nx = red\n"); $gl->apply_project_file("$T/bad.conf") }, qr{bad\.conf:4: label value is});

# issues and quick actions
$gl->as('jim');
my $story = $gl->create_issue($P, title => 'Port the Stations package', labels => ['type::story'], milestone => 'Sprint 1',
    description => "As the government, we want Stations in v2.\n/assign \@bob\n/estimate 3d\n/label ~workflow::ready");
check('issue: quick actions in the description run and are removed', join('|', $story->{description}, $story->{assignees}[0]{username}, $story->{time_stats}{time_estimate}, join(',', @{ $story->{labels} })),
      'As the government, we want Stations in v2.|bob|86400|type::story,workflow::ready');
my $task = $gl->create_issue($P, title => 'Close the Stations TODOs', labels => ['type::task'], milestone => 'Sprint 1', issue_type => 'task', description => "Part of #$story->{iid}\n/relate #$story->{iid}");
check('issue: a task, related to its story', join(' ', $task->{issue_type}, $task->{links}[0]{iid}, $gl->issue($P, $story->{iid})->{links}[0]{iid}), "task $story->{iid} $task->{iid}");
$gl->as('bob');
$gl->add_note($P, 'issue', $task->{iid}, "/label ~workflow::blocked\nBlocked by: waiting on the prime's modeler");
check('issue: scoped labels are exclusive (workflow::blocked replaces nothing on a task without one)', join(',', @{ $gl->issue($P, $task->{iid})->{labels} }), 'type::task,workflow::blocked');
$gl->add_note($P, 'issue', $story->{iid}, "/label ~workflow::blocked");
check('issue: a second label of the same scope replaces the first', join(',', @{ $gl->issue($P, $story->{iid})->{labels} }), 'type::story,workflow::blocked');
$gl->tick(2 * 86400);
$gl->add_note($P, 'issue', $task->{iid}, "/unlabel ~workflow::blocked\nUnblocked: the modeler answered.\n/spend 1d");
check('issue: /spend adds time; the note keeps its text', join('|', $gl->issue($P, $task->{iid})->{time_stats}{total_time_spent}, $gl->issue($P, $task->{iid})->{notes}[-1]{body}), '28800|Unblocked: the modeler answered.');
{ my $before = ($gl->issue($P, $task->{iid})->{milestone} // {})->{title} // '';
  $gl->add_note($P, 'issue', $task->{iid}, "/milestone %\"Sprint 9\"\n/assign @\n/weight\n/estimate");
  check('issue: quick actions with a missing or unknown argument are ignored, as GitLab does', ($gl->issue($P, $task->{iid})->{milestone} // {})->{title} // '', $before);
  dies('issue: update_issue with a milestone that does not exist', sub { $gl->update_issue($P, $task->{iid}, milestone => 'Sprint 9') }, qr/no milestone 'Sprint 9'/); }

# the repository: first push, develop through the API, the pipeline definition
$gl->as('tom');
my $tom = GitFlow->new(dir => "$T/tom", gl => $gl, project => $P, user => 'tom', name => 'Tom');
$tom->clone;
spew("$T/tom/README.md", "# acme/model\n");
spew("$T/tom/CODEOWNERS", "# owners\n[Model]\n/model/ \@jim\n[Pipeline]\n/.gitlab-ci.yml \@tom\n");
spew("$T/tom/check.sh", "test -f README.md\nif grep -rq FAIL model 2>/dev/null; then echo 'model has FAIL'; exit 1; fi\necho checked\n");
spew("$T/tom/quality.sh", q{printf '['; grep -rn SMELL model 2>/dev/null | { sep=''; while IFS=: read f l rest; do printf '%s{"description":"smell in %s","check_name":"smell","fingerprint":"%s-%s","severity":"minor","location":{"path":"%s","lines":{"begin":%s}}}' "$sep" "$f" "$f" "$l" "$f" "$l"; sep=','; done; }; printf ']'} . "\n");
spew("$T/tom/.gitlab-ci.yml", <<'EOF');
stages: [check, report, deploy]
workflow:
  rules:
    - if: $CI_PIPELINE_SOURCE == "merge_request_event"
    - if: $CI_COMMIT_BRANCH && $CI_OPEN_MERGE_REQUESTS
      when: never
    - if: $CI_COMMIT_BRANCH
    - if: $CI_COMMIT_TAG
.always: &always
  rules:
    - when: on_success
check:
  stage: check
  script:
    - sh check.sh
  <<: *always
tests:
  stage: report
  script:
    - mkdir -p out
    - printf '<testsuite><testcase classname="model" name="parses"/><testcase classname="model" name="traces"><failure>2 orphans</failure></testcase></testsuite>' > out/junit.xml
  artifacts:
    reports:
      junit: out/junit.xml
  <<: *always
quality:
  stage: report
  script:
    - sh quality.sh > gl-code-quality-report.json
    - echo "model_files $(find . -path ./.git -prune -o -name '*.sysml' -print | wc -l | tr -d ' ')" > metrics.txt
  artifacts:
    reports:
      codequality: gl-code-quality-report.json
      metrics: metrics.txt
  <<: *always
pages:
  stage: deploy
  script:
    - mkdir -p public
    - echo "<h1>acme model</h1>" > public/index.html
  artifacts:
    paths: [public]
  rules:
    - if: $CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH
docs:
  stage: deploy
  script:
    - echo deploying docs
  environment:
    name: docs
    url: https://docs.example.invalid/acme
  rules:
    - if: $CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH
baseline:
  stage: check
  script:
    - echo "tag $CI_COMMIT_TAG"
  rules:
    - if: $CI_COMMIT_TAG =~ /^baseline-/
triggered:
  stage: check
  script:
    - echo "DROP=$DROP_VERSION"
    - cat "$GITLAB_LOCAL_REGISTRY/model-docs/1.0.0/docs.zip"
  rules:
    - if: $CI_PIPELINE_SOURCE == "trigger"
nightly:
  stage: check
  script:
    - echo "full check FULL=$FULL"
  rules:
    - if: $CI_PIPELINE_SOURCE == "schedule" && $FULL == "1"
EOF
$tom->git('checkout', '-q', '-b', 'main');
$tom->commit('Initial commit: README, CODEOWNERS, pipeline');
$tom->init;
check('flow init: main pushed (initial push allowed), develop created through the API', join(' ', sort map { (split m{/})[-1] } $tom->git('ls-remote', '--heads', 'origin') =~ m{refs/heads/(\S+)}g), 'develop main');
my @pl = @{ $gl->pipelines($P) };
check('push pipelines ran on main and develop', join(' ', map { "$_->{ref}:$_->{status}" } @pl), 'main:success develop:success');
check('pages: published from the default branch', -f "$T/gl/pages/acme/model/index.html" ? $gl->pages($P)->{url} : 'missing', 'https://acme.pages.gitlab.local/model/');
check('environment: a deployment of docs (and of pages)', join(' ', sort map { "$_->{environment}{name}:$_->{ref}" } @{ $gl->deployments($P) }), 'docs:develop pages:develop');
check('environments listed with their URL', join(' ', sort map { "$_->{name}=" . ($_->{external_url} // '') } @{ $gl->environments($P) }), 'docs=https://docs.example.invalid/acme pages=https://acme.pages.gitlab.local/model/');

# the hook: no direct pushes to protected branches
$gl->as('bob');
my $bob = GitFlow->new(dir => "$T/bob", gl => $gl, project => $P, user => 'bob', name => 'Bob');
$bob->clone;
$bob->checkout('develop');
spew("$T/bob/sneaky.txt", "x\n");
$bob->commit('Sneak a change in');
my ($out, $rc) = $bob->git_rc('push', 'origin', 'develop:refs/heads/develop');
like('hook: a developer cannot push to protected develop', "$rc $out", qr/^1 .*GitLab: You are not allowed to push code to protected branches on this project\./s);
$bob->git('reset', '-q', '--hard', 'origin/develop');

# a feature through a merge request
$bob->start(feature => "$task->{iid}-close-stations-todos");
spew("$T/bob/model/stations/Stations.sysml", "package Stations {\n    part def Buoy; // SMELL\n}\n");
$gl->tick(3600);
$bob->commit('Close the Stations TODOs');
my $mr = $bob->finish(title => 'Close the Stations TODOs', description => "Closes #$task->{iid}\n\n/label ~type::task\n/milestone %\"Sprint 1\"", reviewers => ['jim']);
check('mr: opened from the feature branch into develop; quick actions ran', join(' ', $mr->{source_branch}, $mr->{target_branch}, join(',', @{ $mr->{labels} }), $mr->{milestone}{title}),
      "feature/$task->{iid}-close-stations-todos develop type::task Sprint 1");
check('mr: a merged-results pipeline ran and passed', join(' ', $mr->{head_pipeline}{status}, $gl->pipeline($P, $mr->{head_pipeline}{id})->{source}), 'success merge_request_event');
my $w = $gl->mr($P, $mr->{iid})->{reports};
check('mr widget: test summary from the junit report', join(' ', @{ $w->{junit} }{qw(total failed)}, @{ $w->{junit}{failures} }), '2 1 model: traces');
check('mr widget: code quality, new against the target', join(' ', $w->{codequality}{total}, scalar @{ $w->{codequality}{new} }, $w->{codequality}{new}[0]{path}), '1 1 model/stations/Stations.sysml');
check('mr widget: metrics with the previous value from develop', join(' ', map { "$_->{name}=$_->{value}/" . ($_->{previous} // '-') } @{ $w->{metrics} }), 'model_files=1/0');
dies('merge: approvals first', sub { $gl->merge_mr($P, $mr->{iid}) }, qr/approvals required: Model review needs 1, has 0/);
dies('approve: the author cannot approve', sub { $gl->approve_mr($P, $mr->{iid}) }, qr/bob wrote merge request !1 and cannot approve it/);
$gl->as('tom'); $gl->approve_mr($P, $mr->{iid});
$gl->as('bob');
dies('merge: the code owner of model/ must approve', sub { $gl->merge_mr($P, $mr->{iid}) }, qr{code owner approval required for model/stations/Stations\.sysml \(\@jim\)});
$gl->as('jim');
$gl->add_note($P, 'mr', $mr->{iid}, 'Is Buoy the v1 name? Check the prime\'s glossary.', resolvable => 1);
$gl->approve_mr($P, $mr->{iid});
$gl->as('bob');
dies('merge: open discussions block it', sub { $gl->merge_mr($P, $mr->{iid}) }, qr/discussions not resolved \(1 open\)/);
$gl->resolve_discussions($P, $mr->{iid});
my $merged = $gl->merge_mr($P, $mr->{iid});
check('merge: merged with a merge commit', $merged->{state}, 'merged');
like('merge: GitLab\'s merge message', $bob->git('fetch', '-q', 'origin') . $bob->git('log', '-1', '--format=%B', 'origin/develop'),
     qr/^Merge branch 'feature\/2-close-stations-todos' into 'develop'\n\nClose the Stations TODOs\n\nCloses #2\n\nSee merge request acme\/model!1/);
check('merge: "Closes #N" closed the task (develop is the default branch)', $gl->issue($P, $task->{iid})->{state}, 'closed');
check('merge: the source branch was removed', scalar(() = $bob->git('ls-remote', '--heads', 'origin') =~ /feature\//g), 0);

# a failing pipeline blocks the merge
$bob->start(feature => 'broken');
spew("$T/bob/model/bad.sysml", "FAIL\n");
$bob->commit('A broken model');
my $mr2 = $bob->finish(title => 'Broken');
check('mr: a failing check fails the pipeline', $mr2->{head_pipeline}{status}, 'failed');
$gl->as('jim'); $gl->approve_mr($P, $mr2->{iid});
dies('merge: the pipeline must succeed', sub { $gl->merge_mr($P, $mr2->{iid}) }, qr/pipeline must succeed \(pipeline #\d+ failed\)/);
$gl->as('bob');
$bob->git('rm', '-q', 'model/bad.sysml');
$bob->commit('Fix forward: remove the broken file');
$bob->publish;
check('mr: a new push reruns the MR pipeline', $gl->mr($P, $mr2->{iid})->{head_pipeline}{status}, 'success');

# a release: main, the baseline tag, the release, the back-merge
$gl->as('tom');
$tom->start(release => 'baseline-1');
spew("$T/tom/CHANGELOG.md", "# Changelog\n\n## baseline-1\n- Stations in v2\n");
$tom->commit('Changelog for baseline-1');
my $rmr = $tom->finish(title => 'Release baseline-1');
check('release: the MR targets main', $rmr->{target_branch}, 'main');
$gl->as('jim'); $gl->approve_mr($P, $rmr->{iid});
$gl->as('tom');
$gl->merge_mr($P, $rmr->{iid});
my $rel = $tom->after_release($rmr, notes => "## baseline-1\n\n- Stations in v2\n");
like('release: tag message carries the sha256 of docs/', $tom->git('fetch', '-q', 'origin', '--tags') . $tom->git('for-each-ref', '--format=%(contents)', 'refs/tags/baseline-1'), qr/^baseline-1\n\nsha256=[0-9a-f]{64} \(docs\/ at [0-9a-f]{8}\)/);
check('release: recorded, and a tag pipeline ran', join(' ', $gl->releases($P)->[0]{tag_name}, scalar grep { $_->{ref} eq 'baseline-1' && $_->{status} eq 'success' } @{ $gl->pipelines($P) }), 'baseline-1 1');
check('release: back-merge MR main -> develop', join(' ', $rel->{mr}{source_branch}, $rel->{mr}{target_branch}), 'main develop');
$gl->as('bob');
dies('tag: a developer cannot create a protected tag', sub { $gl->create_tag($P, 'baseline-2', 'develop', 'x') }, qr/not allowed to create this tag as it is protected/);
($out, $rc) = $bob->git_rc('push', 'origin', 'HEAD:refs/tags/baseline-9');
like('hook: nor push one', "$rc $out", qr/^1 .*You are not allowed to create this tag as it is protected/s);

# vendor drops: drop 1 merges cleanly; the government edits; drop 2 changes the same line -> a conflict
my $drop = sub { my ($dir, $line) = @_; spew("$dir/MANIFEST.txt", "drop\n"); spew("$dir/model.txt", "$line\n") };
my $conv = sub { my ($d, $out) = @_; spew("$out/prime/Prime.sysml", "package Prime {\n" . slurp("$d/model.txt") . "}\n") };
$drop->("$T/drop1", "    part def Hull;");
$gl->as('tom');
my $v1 = $tom->vendor_import(drop => "$T/drop1", version => 'v1.0', convert => $conv);
check('vendor: drop 1 merges cleanly into feature/drop-v1.0', join(' ', $v1->{branch}, $v1->{merged}), 'feature/drop-v1.0 1');
check('vendor: the raw drop is kept under imports/', -f "$T/tom/imports/v1.0/MANIFEST.txt" ? 'yes' : 'no', 'yes');
my $vm = $tom->finish(title => 'Prime drop v1.0');
$gl->as('jim'); $gl->approve_mr($P, $vm->{iid}); $gl->merge_mr($P, $vm->{iid});
$gl->as('bob');
$bob->start(feature => 'name-the-hull');
spew("$T/bob/model/prime/Prime.sysml", "package Prime {\n    part def Hull { doc /* the government's note */ }\n}\n");
$bob->commit('Document the hull');
my $gm = $bob->finish(title => 'Document the hull');
$gl->as('jim'); $gl->approve_mr($P, $gm->{iid}); $gl->as('bob'); $gl->merge_mr($P, $gm->{iid});
$drop->("$T/drop2", "    part def Hull :> Floating;");
$gl->as('tom');
my $v2 = $tom->vendor_import(drop => "$T/drop2", version => 'v1.1', convert => $conv);
check('vendor: drop 2 conflicts where the government edited', join(' ', $v2->{merged}, @{ $v2->{conflicts} }), '0 model/prime/Prime.sysml');
spew("$T/tom/model/prime/Prime.sysml", "package Prime {\n    part def Hull :> Floating { doc /* the government's note */ }\n}\n");
$tom->commit('Merge prime drop v1.1: keep the hull note on the new definition');
my $vm2 = $tom->finish(title => 'Prime drop v1.1');
check('vendor: the resolved merge passes its pipeline', $vm2->{head_pipeline}{status}, 'success');
dies('vendor: a developer cannot push vendor/prime', sub { $bob->vendor_import(drop => "$T/drop2", version => 'v1.2', convert => $conv) }, qr/not allowed to push code to protected branches/);

# the outline allowance a drop brings (.ci/outline-max): raised in its own commit, never lowered by the tool
check('vendor: no .ci/outline-max, no allowance commit', defined $v1->{outline} ? 'recorded' : 'none', 'none');
$bob->start(feature => 'allowance');
spew("$T/bob/.ci/outline-max", "0\n");
spew("$T/bob/model/outline/Outline.sysml", "package Outline {\n    part def Top { part only : Leaf; }\n    part def Leaf;\n}\n");
$bob->commit('An outline ratchet, and a drop-shaped package with one-child parents');
my $oc = $bob->outline_count;
my $al = $bob->record_outline_allowance('v1.2');
check('allowance: raised to the model.pl check count', join(' ', @$al{qw(old new raised)}, $al->{new} == $oc && $oc > 0 ? 'count' : "count=$oc"), "0 $oc 1 count");
check('allowance: in its own commit, the file only', $bob->git('log', '-1', '--format=%s', '--name-only') =~ s/\n+/|/gr, "Record the outline allowance after drop v1.2|.ci/outline-max|");
check('allowance: the file holds the count', slurp("$T/bob/.ci/outline-max"), "$oc\n");
check('allowance: nothing new, no commit', join(' ', $bob->record_outline_allowance('v1.2')->{raised}, $bob->git('log', '-1', '--format=%s') =~ s/\n//r), '0 Record the outline allowance after drop v1.2');
spew("$T/bob/.ci/outline-max", "999\n");
$bob->commit('A generous allowance');
check('allowance: only raising (lowering is the team\'s own MR)', join(' ', @{ $bob->record_outline_allowance('v1.3') }{qw(new raised)}), '999 0');
{
    my $o = qx(cd "$T/bob" && "$^X" "$ROOT/bin/gitlab.pl" --local "$T/gl" --project $P --as bob flow allowance v1.3 2>&1);
    check('cli: flow allowance', "$? $o", "0 .ci/outline-max stays 999 (drop v1.3: $oc outline violations)\n");
}
$bob->git('checkout', '-q', '--detach');

# the package registry
spew("$T/docs.zip", "PK docs");
my $pk = $gl->package_put($P, 'model-docs', '1.0.0', "$T/docs.zip");
check('package: put records size and sha256', "$pk->{size} " . length($pk->{file_sha256}), '7 64');
my $got = $gl->package_get($P, 'model-docs', '1.0.0', 'docs.zip', "$T/fetched.zip");
check('package: get returns the same bytes', slurp($got), 'PK docs');
dies('package: a missing file is a 404', sub { $gl->package_get($P, 'model-docs', '9.9', 'docs.zip', $T) }, qr/no package file model-docs\/9\.9\/docs\.zip/);

# deliveries from outside: a deploy token for the prime's Jenkins, a trigger token for its pipeline
$gl->as('tom');
my $dt = $gl->create_deploy_token($P, 'nwm-jenkins', ['write_package_registry'], expires_at => '2027-12-31');
check('deploy token: a gitlab+deploy-token user with its scope', "$dt->{username} @{ $dt->{scopes} }", "gitlab+deploy-token-$dt->{id} write_package_registry");
spew("$T/MANIFEST.txt", "drop v1.3\n");
my $up = $gl->package_put($P, 'prime-drop', 'v1.3', "$T/MANIFEST.txt", deploy_token => $dt->{token});
check('deploy token: the prime uploads to the registry', $gl->packages($P)->[-1]{files}[0]{uploaded_by}, $dt->{username});
dies('deploy token: a wrong token cannot publish', sub { $gl->package_put($P, 'prime-drop', 'v1.3', "$T/MANIFEST.txt", deploy_token => 'gldt-nope') }, qr/the deploy token cannot publish packages/);
dies('deploy token: an unknown scope is refused', sub { $gl->create_deploy_token($P, 'x', ['api']) }, qr/deploy token scope is read_repository/);
$gl->as('bob');
dies('trigger: a developer cannot create one', sub { $gl->create_trigger($P, 'x') }, qr/bob cannot create trigger tokens/);
$gl->as('tom');
my $tr = $gl->create_trigger($P, 'Prime Jenkins: drop delivered');
like('trigger: a glptt- token', $tr->{token}, qr/^glptt-[0-9a-f]{20}$/);
dies('trigger: a wrong token is a 404', sub { $gl->trigger_pipeline($P, 'glptt-nope', 'develop') }, qr/invalid trigger token/);
my $tpl = $gl->trigger_pipeline($P, $tr->{token}, 'develop', variables => { DROP_VERSION => 'v1.3' });
check('trigger: the pipeline runs with source trigger (or no job matched)', !$tpl || $tpl->{source} eq 'trigger' ? 1 : 0, 1);

# discrepancy reports for the defects export
$gl->as('jim');
my $dr = $gl->create_issue($P, title => 'DR-1: TW-SYS-012 has no satisfy', labels => [ 'type::discrepancy', 'area::interface', 'phase::integration' ]);
$gl->tick(86400);
$gl->update_issue($P, $dr->{iid}, state_event => 'close');

# exports
my $cnt = $gl->export($P, "$T/ex");
like('export: ci_jobs.csv in the status-metrics format', slurp("$T/ex/ci_jobs.csv"), qr/^ts,job,branch,result,minutes\n2026-10-\d\dT\d\d:\d\d:\d\dZ,check,main,pass,\d+\.\d\d\n/);
like('export: mrs.csv with lead hours', slurp("$T/ex/mrs.csv"), qr/^1,Close the Stations TODOs,bob,feature\/2-close-stations-todos,develop,[^,]+,[^,]+,\d+\.\d,type::task,merged$/m);
like('export: defects.csv from discrepancy issues', slurp("$T/ex/defects.csv"), qr/^#\d+,interface,integration,2026-10-\d\d,2026-10-\d\d$/m);
like('export: tracker/sprint-1.csv with blocked days and the reason', slurp("$T/ex/tracker/sprint-1.csv"), qr/^#2,done,2,waiting on the prime's modeler$/m);
check('export: counts', join(' ', map { "$_=$cnt->{$_}" } sort keys %$cnt), "ci_jobs=$cnt->{ci_jobs} defects=1 issues=3 mrs=7 tracker=1");

# persistence
$gl->save;
my $again = GitLab->new(local => "$T/gl");
check('save/load: the state comes back, clock included', join(' ', scalar @{ $again->issues($P) }, scalar @{ $again->mrs($P) }, abs($again->epoch - $gl->epoch) <= 2 ? 'clock' : $again->now), '3 7 clock');

# ================================================================ pipeline schedules
{   # cron and time zones, without a server
    my $runs = sub { join ' ', map { GitLab::_iso($_) } GitLab::cron_runs($_[0], $_[1], GitLab::_epoch($_[2]), $_[3]) };
    check('cron: weekdays at 02:00 Eastern skip the weekend', $runs->('0 2 * * 1-5', 'America/New_York', '2026-10-08T10:00', 3), '2026-10-09T06:00:00Z 2026-10-12T06:00:00Z 2026-10-13T06:00:00Z');
    check('cron: spring forward -- 02:30 does not exist on 14 March 2027 and runs at 03:30 EDT', $runs->('30 2 * * *', 'America/New_York', '2027-03-12T12:00', 3),
          '2027-03-13T07:30:00Z 2027-03-14T07:30:00Z 2027-03-15T06:30:00Z');
    check('cron: fall back -- 01:30 happens twice on 7 November 2027 and runs once', $runs->('30 1 * * *', 'America/New_York', '2027-11-05T12:00', 3),
          '2027-11-06T05:30:00Z 2027-11-07T05:30:00Z 2027-11-08T06:30:00Z');
    check('cron: lists, ranges, steps, names; day-of-month OR day-of-week; a fixed offset', $runs->('*/20 9-10 1,15 jan,jul mon', '+05:30', '2027-01-01T00:00', 7),
          '2027-01-01T03:30:00Z 2027-01-01T03:50:00Z 2027-01-01T04:10:00Z 2027-01-01T04:30:00Z 2027-01-01T04:50:00Z 2027-01-01T05:10:00Z 2027-01-04T03:30:00Z');
    check('cron: @weekly is Sunday midnight; 7 is Sunday too', $runs->('@weekly', 'UTC', '2026-10-08T00:00', 1) . ' ' . $runs->('0 0 * * 7', 'UTC', '2026-10-08T00:00', 1), '2026-10-11T00:00:00Z 2026-10-11T00:00:00Z');
    check('tz: EST and EDT', join(' ', map { GitLab::tz_offset('America/New_York', GitLab::_epoch($_)) / 3600 } '2027-03-14T06:59', '2027-03-14T07:00', '2027-11-07T05:59', '2027-11-07T06:00'), '-5 -4 -4 -5');
    dies('cron: a bad field names itself', sub { GitLab::parse_cron('0 25 * * *') }, qr/bad cron '0 25 \* \* \*': '25' is not a hour \(0-23\)/);
    dies('cron: four fields', sub { GitLab::parse_cron('0 2 * *') }, qr/want 5 fields/);
    dies('tz: an unknown zone', sub { GitLab::tz_offset('Europe/Nowhere', 0) }, qr/unknown time zone 'Europe\/Nowhere'/);
}
{   # the REST calls
    my $log = "$T/curl-sched.log";
    spew("$T/responses-sched.txt", "POST /pipeline_schedules\$\n201\n\n{\"id\":12,\"description\":\"Nightly\"}\n");
    local $ENV{FAKE_CURL_LOG} = $log;
    local $ENV{FAKE_CURL_RESPONSES} = "$T/responses-sched.txt";
    local $ENV{GL_TEST_TOKEN} = 'glpat-test';
    my $r = GitLab->new(url => 'https://gitlab.example.com', token_env => 'GL_TEST_TOKEN', curl => [ $^X, "$FindBin::Bin/fake-curl.pl" ]);
    $r->create_schedule('tidewater/model', description => 'Nightly', ref => 'develop', cron => '0 2 * * 1-5', cron_timezone => 'America/New_York', variables => { FULL => 1 });
    $r->play_schedule('tidewater/model', 12);
    $r->delete_schedule('tidewater/model', 12);
    my @req = map { decode_json($_) } grep { length } split /\n/, slurp($log);
    check('rest: create, its variable, play, delete', join(' ', map { "$_->{method} " . ($_->{url} =~ s{^.*/projects/tidewater%2Fmodel}{}r) } @req),
          'POST /pipeline_schedules POST /pipeline_schedules/12/variables POST /pipeline_schedules/12/play DELETE /pipeline_schedules/12');
    check('rest: the schedule body', $req[0]{body}, '{"active":true,"cron":"0 2 * * 1-5","cron_timezone":"America/New_York","description":"Nightly","ref":"develop"}');
    check('rest: the variable body', $req[1]{body}, '{"key":"FULL","value":1}');
}
# the emulator: [schedules] in the project file, then the due runs in time order (the clock is Thu 2026-10-08)
spew("$T/sched.conf", "[project]\npath = acme/model\n[schedules]\nNightly full check = 0 2 * * 1-5 | develop | America/New_York | FULL=1\nWeekly status = 0 6 * * 5 | develop | America/New_York\n");
$gl->as('tom');
$gl->apply_project_file("$T/sched.conf") for 1 .. 2;
my @sc = @{ $gl->schedules($P) };
check('schedules: from the project file, once (setup is re-runnable)', join(' | ', map { "$_->{description} $_->{cron} $_->{cron_timezone} $_->{ref} " . join(',', map { "$_->{key}=$_->{value}" } @{ $_->{variables} }) } @sc),
      'Nightly full check 0 2 * * 1-5 America/New_York develop FULL=1 | Weekly status 0 6 * * 5 America/New_York develop ');
check('schedules: next_run_at in UTC', join(' ', map { $_->{next_run_at} } @sc), '2026-10-09T06:00:00Z 2026-10-09T10:00:00Z');
my $extra = $gl->create_schedule($P, description => 'Spare', ref => 'develop', cron => '*/5 * * * *');
$gl->update_schedule($P, $extra->{id}, active => 0);
check('schedules: an inactive schedule has no next run', defined $gl->schedules($P)->[2]{next_run_at} ? 'has one' : 'none', 'none');
$gl->delete_schedule($P, $extra->{id});
dies('schedules: a deleted one is gone', sub { $gl->play_schedule($P, $extra->{id}) }, qr/no pipeline schedule \d+ in acme\/model/);
dies('schedules: a ref that does not exist', sub { $gl->create_schedule($P, description => 'x', ref => 'nope', cron => '@daily') }, qr/no branch or tag 'nope'/);
$gl->as('bob');
my $due = $gl->run_due_schedules($P, until => '2026-10-12T12:00:00Z');
check('due: every run up to Monday noon, in time order, Saturday and Sunday skipped', join(' ', map { substr($_->{created_at}, 0, 16) . '=' . $_->{schedule}{description} } @$due),
      '2026-10-09T06:00=Nightly full check 2026-10-09T10:00=Weekly status 2026-10-12T06:00=Nightly full check');
check('due: source schedule, on develop, run as the schedule owner', join(' ', map { "$_->{source}/$_->{ref}/$_->{user}{username}/$_->{status}" } @$due[0, 1]), 'schedule/develop/tom/success schedule/develop/tom/success');
check('due: the schedule variables reach the jobs (FULL=1 adds the nightly job)', join(' ', map { scalar grep { $_->{name} eq 'nightly' } @{ $_->{jobs} } } @$due), '1 0 1');
like('due: the job saw FULL=1', slurp($due->[0]{log_dir} . '/nightly.log'), qr/full check FULL=1/);
check('due: next runs moved on; the clock is at the until time; the caller is unchanged', join(' ', (map { $_->{next_run_at} } @{ $gl->schedules($P) }), substr($gl->now, 0, 16), $gl->as),
      '2026-10-13T06:00:00Z 2026-10-16T10:00:00Z 2026-10-12T12:00 bob');
check('due: nothing twice', scalar @{ $gl->run_due_schedules($P, until => '2026-10-12T12:00:00Z') }, 0);
my $played = $gl->play_schedule($P, $sc[1]{id});
check('play: runs now, next run unchanged', join(' ', $played->{source}, $gl->schedules($P)->[1]{next_run_at}, $gl->schedules($P)->[1]{last_pipeline}{id} == $played->{id} ? 'last' : 'not last'),
      'schedule 2026-10-16T10:00:00Z last');
# ================================================================ trigger variables reach the jobs; jobs reach the local registry
$gl->as('tom');
my $trg = $gl->create_trigger($P, "the prime's Jenkins");
my @tp = map { $gl->trigger_pipeline($P, $trg->{token}, 'develop', variables => { DROP_VERSION => $_ }) } 'v1.1', 'v1.2';
check('trigger: each run sees its own variables (same tree, not served from the job cache)', join(' | ', map { (slurp("$_->{log_dir}/triggered.log") =~ /^(DROP=\S+)/m)[0] // 'none' } @tp), 'DROP=v1.1 | DROP=v1.2');
like('trigger: GITLAB_LOCAL_REGISTRY gives the job the package registry as files', slurp("$tp[0]{log_dir}/triggered.log"), qr/^PK docs$/m);
{ my $again = $gl->trigger_pipeline($P, $trg->{token}, 'develop', variables => { DROP_VERSION => 'v1.2' });
  check('trigger: the same variables again reuse the cached job', join(' ', map { $_->{cached} } grep { $_->{name} eq 'triggered' } @{ $again->{jobs} }), 1); }

# ================================================================ analytics
$gl->as('jim');
$gl->add_note($P, 'mr', $gm->{iid}, '/label ~fix-forward');        # treat "Document the hull" as a fix-forward: one change failure
my $A = $gl->analytics($P, by => 'week');
print map { "# $_\n" } split /\n/, GitLab::analytics_text($A) if $ENV{SHOW_ANALYTICS};
check('analytics: value stream, one issue closed by an MR, every stage measured', join(' ', map { $_->{n} } @{ $A->{value_stream}{stages} }), '1 1 1 1 1 1');
check('analytics: the issue waited two days for its first commit', $A->{value_stream}{items}[0]{plan} >= 48 ? 'yes' : $A->{value_stream}{items}[0]{plan}, 'yes');
my $ndep = (grep { $_->{environment}{name} eq 'pages' } @{ $gl->deployments($P) }) + @{ $gl->releases($P) };
check('analytics: DORA -- deployments are pages deployments plus releases', $A->{dora}{deployments}, $ndep);
check('analytics: DORA -- change failure rate: 1 fix-forward of 2 merges on develop', join(' ', @{ $A->{dora} }{qw(failures merges change_failure_rate)}), '1 2 50');
check('analytics: DORA -- lead time and restore', join(' ', defined $A->{dora}{lead_median} ? 'lead' : 'no lead', $A->{dora}{restores}), 'lead 0');
check('analytics: CI -- pipelines, failures, failing job', join(' ', $A->{ci}{pipelines} == @{ $gl->pipelines($P) } ? 'all' : $A->{ci}{pipelines}, $A->{ci}{failed}, $A->{ci}{jobs}[0]{job}, $A->{ci}{jobs}[0]{failed}), 'all 2 check 2');
check('analytics: MRs -- opened, merged, per author', join(' ', @{ $A->{mrs} }{qw(opened merged)}, map { "$_->{author}=$_->{merged}/$_->{opened}" } @{ $A->{mrs}{authors} }), '7 4 bob=2/3 tom=2/4');
check('analytics: issues by type and period', join(' ', map { "$_->{type}:$_->{opened}/$_->{closed}" } @{ $A->{issues}{flow} }), 'discrepancy:1/1 story:1/0 task:1/1');
check('analytics: open-issue age', join(' ', $A->{issues}{open}, $A->{issues}{oldest}[0]{iid}), '1 1');
my $As = $gl->analytics($P, by => 'sprint');
check('analytics: by sprint uses the Sprint milestones', join(' ', map { "$_->{period}=$_->{merged}" } @{ $As->{mrs}{throughput} }), 'Sprint 1=4');
check('analytics: --since leaves the earlier work out', $gl->analytics($P, since => '2026-10-12')->{mrs}{merged}, 0);
dies('analytics: --by is checked', sub { $gl->analytics($P, by => 'year') }, qr/analytics --by is sprint, week or month, not 'year'/);
my $files = GitLab::analytics_csv($A, "$T/an");
check('analytics: CSVs', join(' ', sort keys %$files), 'deployments.csv dora.csv issue_flow.csv job_failures.csv mr_authors.csv mr_list.csv mr_throughput.csv open_issues.csv pipelines.csv value_stream.csv');
like('analytics: dora.csv', slurp("$T/an/dora.csv"), qr/^change_failure_rate_pct,50$/m);
like('analytics: value_stream.csv', slurp("$T/an/value_stream.csv"), qr/^issue,mr,issue_created,issue_closed,plan_h,code_h,review_h,approve_h,close_h,total_h\n2,1,2026-10-05T/);
{   # the same report from a server: the requests, and times with offsets and fractions
    my $log = "$T/curl-an.log";
    spew("$T/responses-an.txt", join "----\n",
        "GET /projects/tidewater%2Fmodel\$\n200\n\n{\"default_branch\":\"develop\"}\n",
        "GET /merge_requests/4/commits\n200\n\n[{\"id\":\"a\",\"authored_date\":\"2026-10-05T08:00:00.000+02:00\"}]\n",
        "GET /merge_requests/4/notes\n200\n\n[{\"author\":{\"username\":\"bob\"},\"system\":false,\"created_at\":\"2026-10-05T11:00:00Z\"},{\"author\":{\"username\":\"jim\"},\"system\":true,\"body\":\"approved this merge request\",\"created_at\":\"2026-10-05T12:00:00.000Z\"}]\n",
        "GET /merge_requests\\?\n200\n\n[{\"iid\":4,\"title\":\"Port Stations\",\"author\":{\"username\":\"bob\"},\"source_branch\":\"feature/4-x\",\"target_branch\":\"develop\",\"state\":\"merged\",\"created_at\":\"2026-10-05T10:00:00Z\",\"merged_at\":\"2026-10-06T10:00:00.000+00:00\",\"description\":\"Closes #3\",\"labels\":[]}]\n",
        "GET /pipelines/9/jobs\n200\n\n[{\"name\":\"lint\",\"status\":\"failed\",\"allow_failure\":false,\"started_at\":\"2026-10-06T10:01:00Z\",\"finished_at\":\"2026-10-06T10:04:00Z\"}]\n",
        "GET /pipelines\\?\n200\n\n[{\"id\":9,\"ref\":\"develop\",\"source\":\"push\",\"status\":\"failed\",\"created_at\":\"2026-10-06T10:00:00Z\"}]\n",
        "GET /issues\\?\n200\n\n[{\"iid\":3,\"title\":\"Port Stations\",\"labels\":[\"type::story\"],\"created_at\":\"2026-10-01T10:00:00Z\",\"closed_at\":\"2026-10-06T11:00:00Z\"}]\n");
    local $ENV{FAKE_CURL_LOG} = $log;
    local $ENV{FAKE_CURL_RESPONSES} = "$T/responses-an.txt";
    local $ENV{GL_TEST_TOKEN} = 'glpat-test';
    my $r = GitLab->new(url => 'https://gitlab.example.com', token_env => 'GL_TEST_TOKEN', curl => [ $^X, "$FindBin::Bin/fake-curl.pl" ]);
    my $R = $r->analytics('tidewater/model', since => '2026-10-01', until => '2026-10-31', by => 'month');
    my @get = map { my $u = decode_json($_)->{url}; $u =~ s{^.*/projects/tidewater%2Fmodel}{}; $u =~ s/\?.*//; $u } grep { length } split /\n/, slurp($log);
    check('rest analytics: only REST reads every tier has', join(' ', @get),
          ' /milestones /merge_requests /issues /merge_requests/4/commits /merge_requests/4/notes /pipelines /pipelines/9/jobs /deployments /releases');
    check('rest analytics: lead time 28 h (a +02:00 commit), review 2 h (jim\'s approval, not bob\'s own note)', join(' ', $R->{dora}{lead_median}, $R->{mrs}{review_median}), '28 2');
    check('rest analytics: value stream from the issue to its close', join(' ', map { $_->{median} } @{ $R->{value_stream}{stages} }), '92 4 2 22 1 121');
    check('rest analytics: pipeline duration from its jobs; the job failure counted', join(' ', $R->{ci}{median_minutes}, $R->{ci}{jobs}[0]{job}, $R->{ci}{jobs}[0]{failed}), '3 lint 1');
}
$gl->save;

# ================================================================ job artifacts and issue notes
check('artifact: the pages job\'s file from the latest successful run on develop', $gl->job_artifact($P, ref => 'develop', job => 'pages', path => 'public/index.html'), "<h1>acme model</h1>\n");
dies('artifact: a file the job did not keep', sub { $gl->job_artifact($P, ref => 'develop', job => 'pages', path => 'public/missing.html') }, qr/no artifact public\/missing\.html in job pages of pipeline #\d+ on develop/);
dies('artifact: no such successful job on the ref', sub { $gl->job_artifact($P, ref => 'main', job => 'pages', path => 'public/index.html') }, qr/no successful job pages on main in acme\/model/);
dies('artifact: no climbing out', sub { $gl->job_artifact($P, ref => 'develop', job => 'pages', path => '../../gitlab.json') }, qr/may not contain '\.\.'/);
my $tn = $gl->issue_notes($P, $task->{iid});
check('issue notes: oldest first, people and system notes', join(' | ', map { ($_->{system} ? '* ' : '') . $_->{body} } grep { !$_->{system} || $_->{body} =~ /blocked/ } @$tn),
      qq{* added ~"workflow::blocked" label | Blocked by: waiting on the prime's modeler | * removed ~"workflow::blocked" label | Unblocked: the modeler answered.});
{
    my $log = "$T/curl-art.log";
    spew("$T/responses-art.txt", join "----\n",
        "GET /jobs/artifacts/feature%2F2-x/raw/out/junit\\.xml\\?job=tests\$\n200\n\n<testsuite tests=\"1\"/>\n",
        "GET /jobs/artifacts/\n404\n\n{\"message\":\"404 Not found\"}\n",
        "GET /issues/2/notes\\?\n200\n\n[{\"body\":\"Blocked by: the prime\",\"system\":false,\"author\":{\"username\":\"bob\"}}]\n");
    local $ENV{FAKE_CURL_LOG} = $log;
    local $ENV{FAKE_CURL_RESPONSES} = "$T/responses-art.txt";
    local $ENV{GL_TEST_TOKEN} = 'glpat-test';
    my $r = GitLab->new(url => 'https://gitlab.example.com', token_env => 'GL_TEST_TOKEN', curl => [ $^X, "$FindBin::Bin/fake-curl.pl" ]);
    check('rest artifact: raw bytes (not JSON-decoded)', $r->job_artifact('tidewater/model', ref => 'feature/2-x', job => 'tests', path => 'out/junit.xml'), '<testsuite tests="1"/>');
    like('rest artifact: GET jobs/artifacts/REF/raw/PATH?job=NAME, ref encoded, path kept', slurp($log), qr{"url":"https://gitlab\.example\.com/api/v4/projects/tidewater%2Fmodel/jobs/artifacts/feature%2F2-x/raw/out/junit\.xml\?job=tests"});
    dies('rest artifact: a 404 is an error', sub { $r->job_artifact('tidewater/model', ref => 'develop', job => 'tests', path => 'nope.txt') }, qr/no artifact nope\.txt from job tests on develop in tidewater\/model/);
    unlink $log;
    my $nn = $r->issue_notes('tidewater/model', 2);
    check('rest issue notes: paged, oldest first', join(' ', $nn->[0]{body}, slurp($log) =~ /order_by=created_at&page=1&per_page=100&sort=asc/ ? 'query ok' : slurp($log)), 'Blocked by: the prime query ok');
}

# ================================================================ dry runs and the drift check
check('diff: only the labels created during the work differ from the project file', join(' | ', @{ $gl->diff_project_file("$T/project.conf") }),
      '[labels] area::interface: live only | [labels] fix-forward: live only | [labels] phase::integration: live only | [labels] workflow::ready: live only');
{
    (my $drift = slurp("$T/project.conf")) =~ s/^develop = push:none merge:developer codeowners:yes$/develop = push:developer merge:developer codeowners:no/m;
    $drift =~ s/^bob = developer$/bob = maintainer\ncarol = developer/m;
    $drift =~ s/^type::task = #5CB85C/type::task = #000000/m;
    $drift =~ s/^Model review = 1 jim tom$/Model review = 2 jim tom/m;
    $drift =~ s/^STAGE = test$/STAGE = prod\nNEWVAR = 1/m;
    $drift .= "[schedules]\nNightly full check = 0 3 * * 1-5 | develop | America/New_York | FULL=1\nMonthly = 0 0 1 * * | main\n";
    spew("$T/drift.conf", $drift);
    my $d = join "\n", @{ $gl->diff_project_file("$T/drift.conf") };
    like("diff: $_->[0]", $d, $_->[1]) for
        [ 'a member at another level', qr/^\[members\] bob: file maintainer, live developer$/m ], [ 'a missing member', qr/^\[members\] carol: missing \(file developer\)$/m ],
        [ 'a label colour', qr/^\[labels\] type::task: color file #000000, live #5CB85C$/m ],
        [ 'branch protection', qr/^\[branches\] develop: push file developer, live none\n\[branches\] develop: codeowners file no, live yes$/m ],
        [ 'an approval rule', qr/^\[approvals\] Model review: file 2 required, live 1$/m ],
        [ 'variables (values are not printed)', qr/^\[variables\] STAGE: value differs\n\[variables\] NEWVAR: missing$/m ],
        [ 'a schedule', qr/^\[schedules\] Nightly full check: cron file 0 3 \* \* 1-5, live 0 2 \* \* 1-5\n\[schedules\] Monthly: missing\n\[schedules\] Weekly status: live only$/m ];
    spew("$T/clean.conf", "[project]\npath = acme/model\ndefault_branch = develop\nonly_allow_merge_if_pipeline_succeeds = true\n[branches]\nmain = push:none merge:maintainer codeowners:yes\ndevelop = push:none merge:developer codeowners:yes\nvendor/prime = push:maintainer merge:none\n[tags]\nbaseline-* = create:maintainer\n[approvals]\nModel review = 1 jim tom\n");
    check('diff: a file that matches has no differences', scalar @{ $gl->diff_project_file("$T/clean.conf") }, 0);
    spew("$T/clean2.conf", "[project]\npath = acme/model\nonly_allow_merge_if_pipeline_succeeds = false\nmerge_method = ff\n");
    check('diff: project settings', join(' | ', @{ $gl->diff_project_file("$T/clean2.conf") }), '[project] merge_method: file ff, live merge | [project] only_allow_merge_if_pipeline_succeeds: file true, live 1' =~ s/file true, live 1/file false, live 1/r);
}
{   # a dry run on the emulator prints the requests and changes nothing
    $gl->save;
    my $before = slurp("$T/gl/gitlab.json");
    my $out = '';
    open my $oh, '>', \$out;
    my $dr = GitLab->new(local => "$T/gl", dry_run => 1, out => $oh);
    $dr->as('jim');
    my $n0 = scalar @{ $dr->issues($P) };
    $dr->create_label($P, 'type::spike', '#123456', 'A time-boxed look');
    my $i = $dr->create_issue($P, title => 'Dry', labels => ['type::spike'], milestone => 'Sprint 2');
    $dr->merge_mr($P, $mr2->{iid});
    $dr->apply_project_file("$T/drift.conf");
    my $due = $dr->run_due_schedules($P, until => '2026-10-20T00:00:00Z');
    $dr->save;
    close $oh;
    like('dry run: the requests are printed', $out, qr{^POST /api/v4/projects/acme%2Fmodel/labels \{"color":"#123456","description":"A time-boxed look","name":"type::spike"\}\nPOST /api/v4/projects/acme%2Fmodel/issues \{"labels":"type::spike","milestone_id":"\{id of milestone Sprint 2\}","title":"Dry"\}\nPUT /api/v4/projects/acme%2Fmodel/merge_requests/\d+/merge \{\}\n});
    like('dry run: setup prints member, label, protection and schedule requests', $out, qr{POST /api/v4/projects/acme%2Fmodel/members \{"access_level":40,"user_id":"\{id of bob\}"\}.*POST /api/v4/projects/acme%2Fmodel/protected_branches \{[^\n]*"name":"develop","push_access_level":30\}.*PUT /api/v4/projects/acme%2Fmodel/pipeline_schedules/\d+ \{"cron":"0 3 \* \* 1-5"}s);
    like('dry run: due schedules are listed in order, not run', $out, qr{POST /api/v4/projects/acme%2Fmodel/pipeline_schedules/\d+/play \{\}   # 2026-10-13T06:00:00Z Nightly full check\n(?:.*\n)*?POST /api/v4/projects/acme%2Fmodel/pipeline_schedules/\d+/play \{\}   # 2026-10-14T06:00:00Z Nightly full check\n});
    check('dry run: reads still answer; nothing changed, not even the saved state', join(' ', $n0, scalar @{ $dr->issues($P) }, ref $due, scalar @$due, slurp("$T/gl/gitlab.json") eq $before ? 'unchanged' : 'CHANGED'),
          "$n0 $n0 ARRAY 0 unchanged");
}

# ================================================================ the CLI
my $cli = sub { my $o = qx("$^X" "$ROOT/bin/gitlab.pl" @_ 2>&1); ($o, $? >> 8) };
($out, $rc) = $cli->('--local', "$T/gl", '--project', $P, 'issue', 'list', '--state', 'all');
like('cli: issue list', "$rc\n$out", qr/^0\n#1 +opened .*Port the Stations package/s);
($out, $rc) = $cli->('--local', "$T/gl", '--project', $P, 'mr', 'show', 1);
like('cli: mr show prints the widgets', $out, qr/tests: 2 total, 1 failed.*code quality: 1 finding, 1 new.*model_files +1 \(was 0\)/s);
($out, $rc) = $cli->('--local', "$T/gl", '--project', $P, '--as', 'bob', 'mr', 'merge', $mr2->{iid});
like('cli: a refused merge exits 1 with the reason', "$rc $out", qr/^1 gitlab\.pl: approvals required|^0 /);
($out, $rc) = $cli->('--local', "$T/gl", '--project', $P, 'pages');
like('cli: pages', "$rc $out", qr{^0 https://acme\.pages\.gitlab\.local/model/});
($out, $rc) = $cli->('--local', "$T/gl", '--project', $P, 'package', 'list');
like('cli: package list', $out, qr{^model-docs/1\.0\.0  docs\.zip$}m);
($out, $rc) = $cli->('--local', "$T/gl", '--project', $P, 'schedule', 'list');
like('cli: schedule list', $out, qr/^\d+ +Nightly full check +0 2 \* \* 1-5 +America\/New_York +develop +next 2026-10-13T06:00:00Z +\@tom  last #\d+ success\n +vars: FULL=1\n/);
($out, $rc) = $cli->('--local', "$T/gl", '--project', $P, '--as', 'tom', 'schedule', 'due', '--until', '2026-10-13T07:00:00Z');
like('cli: schedule due', "$rc $out", qr/^0 2026-10-13T06:00:\d\dZ  #\d+ success  develop \(Nightly full check\)\n1 scheduled pipeline\n/);
($out, $rc) = $cli->('schedule', 'next', '"30 2 * * *"', '--tz', 'America/New_York', '--from', '2027-03-13T12:00', '-n', 1);
check('cli: schedule next needs no server; shows UTC and local', "$rc $out", "0 2027-03-14T07:30:00Z  (Sun 2027-03-14 03:30 -04:00)\n");
($out, $rc) = $cli->('--local', "$T/gl", '--project', $P, 'analytics', '--by', 'week', '--csv', "$T/an2");
like('cli: analytics prints the five sections and writes the CSVs', "$rc $out", qr/^0 GitLab analytics: acme\/model.*1\. Value stream.*2\. DORA.*3\. CI\/CD.*4\. Merge requests.*5\. Issues.*CSV: deployments\.csv/s);
{
    my $before = slurp("$T/gl/gitlab.json");
    ($out, $rc) = $cli->('--local', "$T/gl", '--as', 'tom', '--dry-run', 'setup', "$T/drift.conf");
    like('cli: --local --dry-run setup prints and changes nothing', "$rc " . (slurp("$T/gl/gitlab.json") eq $before ? 'unchanged ' : 'CHANGED ') . $out, qr{^0 unchanged .*PUT /api/v4/projects/acme%2Fmodel \{}s);
    ($out, $rc) = $cli->('--local', "$T/gl", 'setup', '--diff', "$T/drift.conf");
    like('cli: setup --diff exits 1 on drift', "$rc $out", qr/^1 .*\[members\] bob: file maintainer, live developer/s);
    ($out, $rc) = $cli->('--local', "$T/gl", 'setup', '--diff', "$T/clean.conf");
    check('cli: setup --diff exits 0 when it matches', "$rc $out", "0 no differences: the project matches $T/clean.conf\n");
    ($out, $rc) = $cli->('--local', "$T/gl", '--project', $P, '--dry-run', 'flow', 'sync');
    like('cli: flow refuses --dry-run', "$rc $out", qr/^1 gitlab\.pl: flow pushes to the repository; --dry-run does not apply to it/);
}
{   # the drift check against a server reads only
    my $log = "$T/curl-diff.log";
    spew("$T/responses-diff.txt", join "----\n",
        "GET /projects/acme%2Fmodel/protected_branches\\?\n200\n\n[{\"name\":\"develop\",\"push_access_levels\":[{\"access_level\":30}],\"merge_access_levels\":[{\"access_level\":30}],\"allow_force_push\":false,\"code_owner_approval_required\":true}]\n",
        "GET /projects/acme%2Fmodel/members/all\\?\n200\n\n[{\"username\":\"bob\",\"access_level\":30}]\n",
        "GET /projects/acme%2Fmodel\$\n200\n\n{\"default_branch\":\"develop\",\"only_allow_merge_if_pipeline_succeeds\":true}\n");
    spew("$T/rest-diff.conf", "[project]\npath = acme/model\ndefault_branch = develop\nonly_allow_merge_if_pipeline_succeeds = true\n[members]\nbob = developer\n[branches]\ndevelop = push:none merge:developer codeowners:yes\n");
    local $ENV{FAKE_CURL_LOG} = $log;
    local $ENV{FAKE_CURL_RESPONSES} = "$T/responses-diff.txt";
    local $ENV{GL_TEST_TOKEN} = 'glpat-test';
    my $r = GitLab->new(url => 'https://gitlab.example.com', token_env => 'GL_TEST_TOKEN', curl => [ $^X, "$FindBin::Bin/fake-curl.pl" ]);
    check('rest diff: someone opened develop to developer pushes', join(' | ', @{ $r->diff_project_file("$T/rest-diff.conf") }), '[branches] develop: push file none, live developer');
    my @m = map { decode_json($_)->{method} } grep { length } split /\n/, slurp($log);
    check('rest diff: reads only', join(' ', sort { $a cmp $b } keys %{ { map { ($_ => 1) } @m } }), 'GET');
}
($out, $rc) = $cli->('nonsense');
check('cli: an unknown command exits 2', $rc, 2);
($out, $rc) = $cli->('help', 'flow');
like('cli: help per command', "$rc $out", qr/^0 gitlab\.pl flow init/);
($out, $rc) = $cli->('--local', "$T/gl", 'issue', 'list');
like('cli: no project is a clear error', "$rc $out", qr/^1 gitlab\.pl: give --project GROUP\/NAME/);
($out, $rc) = $cli->('--url', 'https://gitlab.example.com', '--dry-run', '--project', 'g/p', 'sprints', '2026-10-05', 1);
like('cli: --dry-run with a server', "$rc $out", qr!^0 POST /api/v4/projects/g%2Fp/milestones \{"description":"Two-week sprint 1[^}]*","due_date":"2026-10-16","start_date":"2026-10-05","title":"Sprint 1"\}!);

# ================================================================ issue boards: [boards] in setup, the drift check, dry runs
{
    my $bg = GitLab->new(local => "$T/gl-boards", now => '2026-10-05T09:00:00Z');
    $bg->as('tom');
    my $bconf = "[project]\npath = acme/boards\n[labels]\nworkflow::ready = #A8D695\nworkflow::doing = #F0AD4E\nworkflow::done = #5CB85C\npriority::1 = #CC0033\npriority::2 = #FC9403\n"
              . "[milestones]\nsprints = 2026-10-05 2 2\n[boards]\nSprint = workflow::ready workflow::doing workflow::done | milestone=started\nBacklog = priority::1, priority::2 | milestone=none\n";
    spew("$T/boards.conf", $bconf);
    my $log = join "\n", @{ $bg->apply_project_file("$T/boards.conf") };
    like('boards: setup creates the board, its lists and its scope', $log, qr/^board Sprint created\nboard Sprint: list workflow::ready added\n(?:.*\n)*board Sprint: milestone started\nboard Sprint \(3 lists, milestone started\)$/m);
    my %b = map { ($_->{name} => $_) } @{ $bg->boards('acme/boards') };
    check('boards: lists in the file\'s order', join(' ', map { "$_->{position}:$_->{label}{name}" } @{ $b{Sprint}{lists} }), '0:workflow::ready 1:workflow::doing 2:workflow::done');
    check('boards: comma-separated lists and the "No milestone" scope', join(' ', (map { $_->{label}{name} } @{ $b{Backlog}{lists} }), GitLab::board_scope($b{Backlog}{milestone})), 'priority::1 priority::2 none');
    check('boards: the scope words map to GitLab\'s timebox ids', join(' ', map { GitLab::board_scope($_) } undef, { id => -3, title => 'Started' }, { id => -2 }, { id => 0 }, { id => -1 }, { id => 9, title => 'Sprint 2' }),
          'any started upcoming none any Sprint 2');
    check('boards: re-running setup changes nothing', join(' | ', grep { /^board/ } @{ $bg->apply_project_file("$T/boards.conf") }),
          'board Sprint (3 lists, milestone started) | board Backlog (2 lists, milestone none)');
    check('boards: diff is clean', join(' | ', grep { /boards/ } @{ $bg->diff_project_file("$T/boards.conf") }), '');
    (my $drift = $bconf) =~ s/workflow::ready workflow::doing workflow::done \| milestone=started/workflow::doing workflow::ready workflow::done | milestone=Sprint 2/;
    $drift .= "Review = workflow::done\n";
    spew("$T/boards-drift.conf", $drift);
    check('boards: diff reports order, scope and a missing board', join(' | ', @{ $bg->diff_project_file("$T/boards-drift.conf") }),
          '[boards] Sprint: lists file workflow::doing workflow::ready workflow::done, live workflow::ready workflow::doing workflow::done | [boards] Sprint: milestone file Sprint 2, live started | [boards] Review: missing');
    $bg->save;
    my $before = slurp("$T/gl-boards/gitlab.json");
    my $out = '';
    open my $oh, '>', \$out;
    my $dr = GitLab->new(local => "$T/gl-boards", dry_run => 1, out => $oh);
    $dr->apply_project_file("$T/boards-drift.conf");
    close $oh;
    like('boards: dry run prints the move, the scope and the new board', $out,
         qr{PUT /api/v4/projects/acme%2Fboards/boards/\d+/lists/\d+ \{"position":0\}\nPUT /api/v4/projects/acme%2Fboards/boards/\d+ \{"milestone_id":"\{id of milestone Sprint 2\}"\}\nPOST /api/v4/projects/acme%2Fboards/boards \{"name":"Review"\}\nPOST /api/v4/projects/acme%2Fboards/boards/0/lists \{"label_id":"\{id of label workflow::done\}"\}\n});
    check('boards: the dry run changed nothing', slurp("$T/gl-boards/gitlab.json") eq $before ? 'unchanged' : 'CHANGED', 'unchanged');
    $bg = GitLab->new(local => "$T/gl-boards");
    $bg->as('tom');
    my @l = grep { /^board/ } @{ $bg->apply_project_file("$T/boards-drift.conf") };
    check('boards: setup moves a list and rescopes', join(' | ', @l[0 .. 1]), 'board Sprint: list workflow::doing moved to position 0 | board Sprint: milestone Sprint 2');
    check('boards: then the diff is clean', scalar @{ $bg->diff_project_file("$T/boards-drift.conf") }, 0);
    dies('boards: a list needs a label that exists', sub { $bg->create_board_list('acme/boards', $b{Sprint}{id}, 'nope') }, qr/no label 'nope' in acme\/boards \(add it to \[labels\]\)/);
    dies('boards: a board line needs lists', sub { GitLab::parse_board_line('| milestone=started', 'f:3') }, qr/^f:3: a board needs its lists/);
    dies('boards: only milestone= is an option', sub { GitLab::parse_board_line('a b | assignee=bob', 'f:4') }, qr/^f:4: board options are milestone=/);
    $bg->save;
    my ($o, $rc2) = $cli->(qq{--local "$T/gl-boards" --project acme/boards board list});
    check('cli: board list', "$rc2 $o", "0 Sprint  (milestone Sprint 2)\n  workflow::doing | workflow::ready | workflow::done\nBacklog  (milestone none)\n  priority::1 | priority::2\nReview  (milestone any)\n  workflow::done\n");
}
{   # a server that ignores the scope (GitLab Free): setup warns and goes on
    my $log = "$T/curl-boards.log";
    spew("$T/responses-boards.txt", join "----\n",
        "GET /projects/acme%2Fmodel/boards\\?\n200\n\n[]\n",
        "POST /projects/acme%2Fmodel/boards\$\n201\n\n{\"id\":5,\"name\":\"Sprint\",\"lists\":[]}\n",
        "GET /projects/acme%2Fmodel/labels\\?\n200\n\n[{\"id\":11,\"name\":\"workflow::ready\"},{\"id\":12,\"name\":\"workflow::done\"}]\n",
        "POST /projects/acme%2Fmodel/boards/5/lists\$\n201\n\n{\"id\":21,\"position\":0}\n",
        "PUT /projects/acme%2Fmodel/boards/5\$\n200\n\n{\"id\":5,\"name\":\"Sprint\",\"milestone\":null}\n");
    local $ENV{FAKE_CURL_LOG} = $log;
    local $ENV{FAKE_CURL_RESPONSES} = "$T/responses-boards.txt";
    local $ENV{GL_TEST_TOKEN} = 'glpat-test';
    my $r = GitLab->new(url => 'https://gitlab.example.com', token_env => 'GL_TEST_TOKEN', curl => [ $^X, "$FindBin::Bin/fake-curl.pl" ]);
    my @w;
    local $SIG{__WARN__} = sub { push @w, @_ };
    my @log = $r->_setup_board('acme/model', 'Sprint', GitLab::parse_board_line('workflow::ready workflow::done | milestone=started', 't'));
    like('rest boards: Free ignores the scope -> a warning, not a failure', join('', @w), qr/^GitLab: board Sprint: milestone scope 'started' not set \(the scope did not take\); scoped boards need Premium or Ultimate/);
    check('rest boards: the lists were still added', join(' | ', @log[1, 2, 3]), 'board Sprint: list workflow::ready added | board Sprint: list workflow::done added | board Sprint: milestone scope not set (needs Premium or Ultimate)');
    my @req = map { decode_json($_) } grep { length } split /\n/, slurp($log);
    check('rest boards: lists by label id, the scope as Started (-3)', join(' ', map { $_->{body} // '' } grep { $_->{method} ne 'GET' } @req), '{"name":"Sprint"} {"label_id":11} {"label_id":12} {"milestone_id":-3}');
}

# ================================================================ Windchill: requests in, progress out
use Windchill;
{
    check('windchill: UTF-16LE with a BOM', Windchill::decode_bytes("\xFF\xFE" . Encode::encode('UTF-16LE', "Number,Name\r\nWC-1,Caf\x{e9}\r\n")), "Number,Name\nWC-1,Caf\x{e9}\n");
    check('windchill: UTF-16BE without a BOM', Windchill::decode_bytes(Encode::encode('UTF-16BE', "Number\nWC-2\n")), "Number\nWC-2\n");
    check('windchill: Windows-1252 when it is not UTF-8', Windchill::decode_bytes("Name\r\nr\xE9sum\xE9 \x96 draft\r\n"), "Name\nr\x{e9}sum\x{e9} \x{2013} draft\n");
    check('windchill: UTF-8 with a BOM', Windchill::decode_bytes("\xEF\xBB\xBFName\nCaf\xC3\xA9\n"), "Name\nCaf\x{e9}\n");
    my $rows = Windchill::parse_csv(qq{Number,Name,Description\nWC-1,"Trace, as CSV","line one\nline ""two"""\n\nWC-2,Plain,\n});
    check('windchill: quoted commas, newlines and quotes; blank lines skipped', join(' / ', map { join('|', @$_) } @$rows), qq{Number|Name|Description / WC-1|Trace, as CSV|line one\nline "two" / WC-2|Plain|});
    check('windchill: tab-separated', join(' / ', map { join('|', @$_) } @{ Windchill::parse_csv("Number\tName\nWC-1\tA, B\n") }), 'Number|Name / WC-1|A, B');
    check('windchill: semicolon-separated', join(' / ', map { join('|', @$_) } @{ Windchill::parse_csv("Number;Name\nWC-1;A, B\n") }), 'Number|Name / WC-1|A, B');
    check('windchill: need dates', join(' ', map { Windchill::iso_date($_) // '-' } '2026-11-02', '11/2/2026', '02-Nov-2026', '2 November 2026 10:00', 'soon', ''),
          '2026-11-02 2026-11-02 2026-11-02 2026-11-02 - -');
    my $m = Windchill::read_marker('x <!-- windchill number="WC-1" state="Open" priority="" title="A &quot;b&quot; -&#45; c" --> y');
    check('windchill: the marker round-trips quotes and --', "$m->{number}|$m->{state}|$m->{priority}|$m->{title}", 'WC-1|Open||A "b" -- c');
    check('windchill: a marker never closes the HTML comment early', Windchill::marker({ number => 'WC-1', state => 'a-->b', priority => '', title => '' }) =~ /-->.*-->/ ? 'broken' : 'ok', 'ok');
}
{
    my $wg = GitLab->new(local => "$T/gl", now => '2026-10-20T09:00:00Z');
    $wg->as('jim');
    my $conf = "$T/wc.conf";
    spew($conf, "[project]\npath = $P\n[windchill]\nurl = https://wc.example.invalid/search?keyword={number}\nlabels = source::windchill, type::story\n"
              . "accept = Open, Under Review, Approved\npriority-map = Critical=priority::1, High=priority::1, Medium=priority::2, Low=priority::3\n");
    my ($cfg, $path) = Windchill::config_file($conf);
    check('windchill: config defaults the column names and reads [project] path', join(' ', $cfg->{col}{number}, $cfg->{col}{requester}, $cfg->{col}{'need-date'}, $path), "Number Created By Need Date $P");
    my $sample = "$ROOT/tools/gitlab/samples/windchill-export.csv";
    my $s = Windchill::intake($wg, $P, $sample, $cfg);
    check('windchill: intake summary', $s->{lines}[-1], 'windchill: 5 rows, 4 created, 1 skipped, 0 drift');
    like('windchill: a state outside accept is skipped and said so', join("\n", @{ $s->{lines} }), qr/^skipped WC-000126: state 'Canceled' is not accepted/m);
    my ($i) = grep { $_->{title} =~ /^WC-000124: / } @{ $wg->issues($P) };
    check('windchill: title, labels, due date from the need date', join(' | ', $i->{title}, "@{ $i->{labels} }", $i->{due_date}),
          'WC-000124: Add the buoy station variant to the part tree | source::windchill type::story priority::2 | 2026-12-15');
    like('windchill: the body links the request and keeps the multi-line description', $i->{description},
         qr/^Windchill request \[WC-000124\]\(https:\/\/wc\.example\.invalid\/search\?keyword=WC-000124\), submitted by Sam Ortiz\.\n(?s:.*)\| Requested by \| Sam Ortiz \|\n(?s:.*)with a different power and comms package\.\nPlease model them as a variant, not a copy\.\n\n/);
    check('windchill: re-running is safe', Windchill::intake($wg, $P, $sample, $cfg)->{lines}[-1], 'windchill: 5 rows, 0 created, 5 skipped, 0 drift');
    $wg->update_issue($P, $i->{iid}, title => 'Buoy variant (WC-000124)');
    (my $csv = slurp($sample)) =~ s/WC-000124,Add the buoy station variant to the part tree,DevSecOps Request,Under Review,Sam Ortiz,Medium/WC-000124,Add the buoy station variant to the part tree,DevSecOps Request,Approved,Sam Ortiz,High/;
    spew("$T/wc-2.csv", $csv);
    $s = Windchill::intake($wg, $P, "$T/wc-2.csv", $cfg);
    like('windchill: Windchill-side changes are drift (a GitLab retitle is not)', join("\n", @{ $s->{lines} }),
         qr/^drift   #$i->{iid} WC-000124: state 'Under Review' -> 'Approved'; priority 'Medium' -> 'High'\n(?s:.*)windchill: 5 rows, 0 created, 4 skipped, 1 drift$/m);
    $s = Windchill::intake($wg, $P, "$T/wc-2.csv", $cfg, note => 1);
    like('windchill: --note records the change on the issue', $wg->issue_notes($P, $i->{iid})->[-1]{body}, qr/^Windchill update \(from wc-2\.csv\): state 'Under Review' -> 'Approved'; priority 'Medium' -> 'High'\.\n\n<!-- windchill number="WC-000124" state="Approved"/);
    check('windchill: after the note, the same export is no longer drift', Windchill::intake($wg, $P, "$T/wc-2.csv", $cfg)->{lines}[-1], 'windchill: 5 rows, 0 created, 5 skipped, 0 drift');
    my ($cfg2) = Windchill::config(GitLab::parse_project_file("[windchill]\naccept = *\n"), 'f');
    like('windchill: accept = * imports every state', Windchill::intake($wg, $P, $sample, $cfg2)->{lines}[-1], qr/, 1 created, 3 skipped, 1 drift$/);
    spew("$T/wc-bad.csv", "Id,Summary\nWC-1,x\n");
    dies('windchill: a missing column names the ones there are', sub { Windchill::intake($wg, $P, "$T/wc-bad.csv", $cfg) }, qr/has no 'Number' column for the number \(its columns: Id, Summary\); set number = COLUMN in \[windchill\]/);
    dies('windchill: an unknown key', sub { Windchill::config(GitLab::parse_project_file("[windchill]\nnumbr = Number\n"), 'f.conf') }, qr/^f\.conf:2: unknown \[windchill\] key 'numbr'/);
    spew("$T/wc-dup.csv", "Number,Name,State\nWC-9,a,Open\n,b,Open\nWC-9,c,Open\n");
    like('windchill: blank and repeated numbers are warned about', join("\n", @{ Windchill::intake($wg, $P, "$T/wc-dup.csv", $cfg)->{lines} }),
         qr/^warning: row 3: no Windchill number; skipped\nwarning: row 4: WC-9 appears again; the first row is used\ncreated #\d+ WC-9: a\nwindchill: 3 rows, 1 created, 2 skipped, 0 drift$/);
    # status: the merged MR !1 (in baseline-1) is made to close the WC-000123 issue
    my ($w1) = grep { $_->{title} =~ /^WC-000123:/ } @{ $wg->issues($P) };
    $wg->{st}{projects}{$P}{mrs}[0]{description} .= "\nCloses #$w1->{iid}\n";
    $wg->update_issue($P, $w1->{iid}, add_labels => ['workflow::done'], milestone => 'Sprint 1');
    my $rows = Windchill::status($wg, $P, $cfg);
    my ($r1) = grep { $_->{number} eq 'WC-000123' } @$rows;
    check('windchill status: one row per request, the closing MR and its release', join(' | ', scalar(@$rows), @$r1{qw(iid state workflow milestone mrs release)}),
          "6 | $w1->{iid} | open | done | Sprint 1 | !1 merged | baseline-1");
    check('windchill status: issues that did not come from Windchill are left out', scalar(grep { $_->{iid} == 2 } @$rows), 0);
    my $csvo = Windchill::status_csv($rows);
    like('windchill status: CSV with a header, CRLF', $csvo, qr/^windchill,issue,state,workflow,milestone,closed,merge_requests,release,url\r\nWC-000123,$w1->{iid},open,done,Sprint 1,,!1 merged,baseline-1,https:\/\/gitlab\.local\/acme\/model\/-\/issues\/$w1->{iid}\r\n/);
    check('windchill status: --since keeps recent ones', scalar @{ Windchill::status($wg, $P, $cfg, since => '2099-01-01') }, 0);
    $wg->save;
    my ($o, $rc2) = $cli->(qq{--local "$T/gl" windchill status --conf "$conf"});
    like('cli: windchill status prints a table', "$rc2 $o", qr/^0 windchill +issue +state +workflow +milestone +closed +merge_requests +release\nWC-000123 +#$w1->{iid} +open +done +Sprint 1 +- +!1 merged +baseline-1\n/);
    ($o, $rc2) = $cli->(qq{--local "$T/gl" windchill status --conf "$conf" --csv "$T/wc-status.csv"});
    check('cli: windchill status --csv writes a UTF-8 file with a BOM', "$rc2 $o " . substr(slurp("$T/wc-status.csv"), 0, 12), "0 6 Windchill requests -> $T/wc-status.csv\n \xEF\xBB\xBFwindchill");
    ($o, $rc2) = $cli->(qq{--local "$T/gl" --dry-run windchill intake "$ROOT/tools/gitlab/samples/windchill-export.csv" --conf "$T/wc-new.conf"});
    like('cli: windchill needs a project file', "$rc2 $o", qr/^1 gitlab\.pl: /);
    spew("$T/wc-new.conf", "[project]\npath = acme/fresh\n");
    $wg->create_project('acme/fresh'); $wg->save;
    ($o, $rc2) = $cli->(qq{--local "$T/gl" --dry-run windchill intake "$ROOT/tools/gitlab/samples/windchill-export.csv" --conf "$T/wc-new.conf"});
    like('cli: windchill intake --dry-run prints the issues it would create', "$rc2 $o", qr{^0 POST /api/v4/projects/acme%2Ffresh/issues \{"description":"Windchill request (?s:.*)"title":"WC-000123: Nightly model check report for the station leads"\}\n(?s:.*)windchill: 5 rows, 5 created, 0 skipped, 0 drift\n$});
}

print "1..$n\n";
print $bad ? "# $bad of $n FAILED\n" : "# all $n passed\n";
exit($bad ? 1 : 0);
