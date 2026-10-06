#!/usr/bin/perl
# perl tests/gitlab-ci.t -- lib/GitLabCI.pm: the YAML subset, rules:if expressions, job selection (plan) and the
# local runner (run) on a temporary git repository with real shell jobs; and `gitlab.pl ci` (GitLabCI::cli)
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use File::Temp qw(tempdir);
use File::Path qw(make_path);
use Data::Dumper;
use GitLabCI;

my ($n, $bad) = (0, 0);
sub check_ { my ($name, $got, $want) = @_; $n++;
    $got = defined $got ? $got : '(undef)'; $want = defined $want ? $want : '(undef)';
    if ($got eq $want) { print "ok $n - $name\n" }
    else { $bad++; print "not ok $n - $name\n#   got:  $got\n#   want: $want\n" } }
sub has { my ($name, $text, @res) = @_; for my $re (@res) { check_("$name: $re", ($text =~ $re ? 1 : 0), 1) } }
sub skip_ { my ($name, $why) = @_; $n++; print "ok $n - $name # skip $why\n" }
sub dump_ { local $Data::Dumper::Sortkeys = 1; local $Data::Dumper::Indent = 0; local $Data::Dumper::Terse = 1; local $Data::Dumper::Useqq = 1; Dumper($_[0]) }
sub spew { my ($p, $t) = @_; (my $d = $p) =~ s{/[^/]*$}{}; make_path($d) unless -d $d; open my $fh, '>:raw', $p or die "$p: $!"; print $fh $t; close $fh }
sub slurp { my ($p) = @_; open my $fh, '<:raw', $p or return undef; local $/; my $t = <$fh>; close $fh; $t }
sub err_of { my ($code) = @_; eval { $code->(); 1 } ? 'no error' : do { (my $e = $@) =~ s/\n$//; $e } }

my $Y = \&GitLabCI::parse_yaml;

# ---------------------------------------------------------------- YAML subset
check_('maps, lists, nesting, comments', dump_($Y->(<<'EOF')),
# a comment line
a: 1          # trailing comment
b:
  - x
  - y   # also a comment
c:
  d: e
  f: [1, 2]
g:
- same indent list
- 2
EOF
    dump_({ a => 1, b => [qw(x y)], c => { d => 'e', f => [1, 2] }, g => ['same indent list', 2] }));
check_('quoting: # inside quotes, doubled single quote, escapes, plain colon', dump_($Y->(<<'EOF')),
a: "x # y"
b: 'it''s'
c: "tab\there \"q\" \\ \u00e9"
url: http://host:80/a#frag
d: it's plain
"quoted key": 1
'k2': v
e: don't # comment
EOF
    dump_({ a => 'x # y', b => "it's", c => "tab\there \"q\" \\ \xC3\xA9", url => 'http://host:80/a#frag', d => "it's plain",
            'quoted key' => 1, k2 => 'v', e => "don't" }));
check_('null, ~ and empty values', dump_($Y->("a:\nb: ~\nc: null\nd: ''\n")), dump_({ a => undef, b => undef, c => undef, d => '' }));
check_('block scalars: literal, strip, keep, folded', dump_($Y->(<<'EOF')),
lit: |
  line 1
    indented
  line 3
strip: |-
  no newline
keep: |+
  kept

fold: >
  one
  two

  three
fdash: >-
  a
  b
next: x
EOF
    dump_({ lit => "line 1\n  indented\nline 3\n", strip => 'no newline', keep => "kept\n\n", fold => "one two\nthree\n", fdash => 'a b', next => 'x' }));
check_('flow collections: nested, quoted, spanning lines', dump_($Y->(<<'EOF')),
a: [x, "y, z", 'w', [1, 2], {k: v}]
b: {one: 1, two: [a, b], three: "3"}
c: [
  first,
  second
]
d: []
e: {}
EOF
    dump_({ a => ['x', 'y, z', 'w', [1, 2], { k => 'v' }], b => { one => 1, two => [qw(a b)], three => 3 }, c => [qw(first second)], d => [], e => {} }));
check_('anchors, aliases and merge keys', dump_($Y->(<<'EOF')),
.base: &base
  stage: check
  tags: [linux]
  variables:
    A: "1"
job:
  <<: *base
  stage: build
list: &l [1, 2]
again: *l
two:
  <<: [*base, {extra: yes}]
EOF
    dump_({ '.base' => { stage => 'check', tags => ['linux'], variables => { A => 1 } },
            job => { stage => 'build', tags => ['linux'], variables => { A => 1 } }, list => [1, 2], again => [1, 2],
            two => { stage => 'check', tags => ['linux'], variables => { A => 1 }, extra => 'yes' } }));
check_('list items that are maps, and nested lists', dump_($Y->(<<'EOF')),
rules:
  - if: $A == "x"
    when: never
  - when: always
nested:
  - - a
    - b
  -
    k: v
EOF
    dump_({ rules => [{ if => '$A == "x"', when => 'never' }, { when => 'always' }], nested => [[qw(a b)], { k => 'v' }] }));
check_('multi-line plain scalar folds with spaces', dump_($Y->("a: one\n  two\n  three\nb: 1\n")), dump_({ a => 'one two three', b => 1 }));
check_('document start marker and CRLF', dump_($Y->("---\r\na: 1\r\nb: [2]\r\n")), dump_({ a => 1, b => [2] }));
check_('error: bad indentation has a line number', err_of(sub { $Y->("a:\n  b: 1\n    c: 2\n", 'ci.yml') }), 'ci.yml:3: bad indentation');
check_('error: unterminated string', err_of(sub { $Y->("a: \"open\n", 'ci.yml') }), 'ci.yml:1: unterminated "string"');
check_('error: tab indentation', err_of(sub { $Y->("a:\n\tb: 1\n", 'ci.yml') }), 'ci.yml:2: tabs are not allowed in indentation');
check_('error: unknown alias', err_of(sub { $Y->("a: *nope\n", 'ci.yml') }), 'ci.yml:1: unknown alias *nope');
check_('error: duplicate key', err_of(sub { $Y->("a: 1\na: 2\n", 'ci.yml') }), "ci.yml:2: duplicate key 'a'");
check_('error: unclosed flow list', err_of(sub { $Y->("a: [1, 2\n", 'ci.yml') }), 'ci.yml:1: unterminated flow collection ([ or { never closed)');

# ---------------------------------------------------------------- rules:if
my %V = (CI_PIPELINE_SOURCE => 'merge_request_event', CI_COMMIT_BRANCH => 'develop', EMPTY => '', SRC => 'vendor/prime', RE => '/^feat/');
my @if = (
    ['$CI_PIPELINE_SOURCE == "merge_request_event"', 1], ['$CI_PIPELINE_SOURCE != "merge_request_event"', 0],
    ['$CI_COMMIT_BRANCH', 1], ['$UNSET', 0], ['$EMPTY', 0], ['$UNSET == null', 1], ['$EMPTY == null', 0], ['$EMPTY == ""', 1],
    ['$UNSET == ""', 0], ['$SRC =~ /^vendor\//', 1], ['$SRC =~ /^VENDOR/i', 1], ['$SRC !~ /^vendor/', 0], ['$UNSET =~ /x/', 0],
    ['$UNSET !~ /x/', 1], ['$CI_COMMIT_BRANCH == "main" || $SRC =~ /prime$/', 1], ['$CI_COMMIT_BRANCH == "main" && $SRC', 0],
    ['($CI_COMMIT_BRANCH == "main" || $CI_COMMIT_BRANCH == "develop") && $SRC', 1], ['$A || $B && $C', 0],
    ['$CI_COMMIT_BRANCH && ($UNSET || $SRC)', 1], ["\${CI_COMMIT_BRANCH} == 'develop'", 1], ['"feature/x" =~ $RE', 1],
    ['$CI_COMMIT_BRANCH == $CI_COMMIT_BRANCH', 1], ['!$UNSET', 1]);
check_("eval_if $_->[0]", GitLabCI::eval_if($_->[0], \%V), $_->[1]) for @if;
check_('eval_if: syntax error', err_of(sub { GitLabCI::eval_if('$A == ', \%V) }), "rules:if: cannot read '\$A == ' at 'the end'");
check_('eval_if: bad regex', err_of(sub { GitLabCI::eval_if('$A =~ /(/', \%V) }) =~ /^rules:if: bad regular expression/ ? 1 : 0, 1);

# ---------------------------------------------------------------- plan
my $CI = <<'EOF';
stages: [check, docs, release]
variables:
  KIT: /opt/kit
  GREETING: "hello $KIT"
include:
  - template: Security/Secret-Detection.gitlab-ci.yml
  - remote: https://example.invalid/ci.yml
default:
  before_script:
    - echo default-before
.perl: &perl
  stage: check
  variables:
    LANGX: perl
lint:
  extends: .perl
  script: perl -v
grammar:
  extends: [.perl]
  script: perl -c x
  rules:
    - if: $CI_PIPELINE_SOURCE == "merge_request_event"
    - if: $CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH
docs:
  stage: docs
  script: [make docs]
  rules:
    - changes: ["model/**/*.sysml", docs/]
delta:
  stage: docs
  script: echo delta
  rules:
    - if: $CI_MERGE_REQUEST_SOURCE_BRANCH_NAME =~ /^vendor\// || $CI_MERGE_REQUEST_SOURCE_BRANCH_NAME =~ /^feature\/drop-/
      allow_failure: true
      variables:
        MODE: drop
    - when: never
release:
  stage: release
  script: echo release
  only: [tags]
nightly:
  stage: release
  script: echo nightly
  only:
    refs: [schedules]
  except:
    variables: [$SKIP_NIGHTLY]
deploy:
  stage: release
  script: echo deploy
  when: manual
legacy:
  stage: check
  script: echo old
  only: [main, /^release\/.*$/]
  except: [tags]
.hidden:
  script: never runs
pages:
  stage: release
  trigger: other/project
EOF
my $ci = GitLabCI::load($CI, file => 'ci.yml');
check_('stages get .pre and .post', join(' ', @{ $ci->{stages} }), '.pre check docs release .post');
check_('jobs in file order, hidden jobs left out', join(' ', @{ $ci->{order} }), 'lint grammar docs delta release nightly deploy legacy pages');
check_('extends merges the template (stage, variables)', "$ci->{jobs}{lint}{stage} $ci->{jobs}{lint}{variables}{LANGX}", 'check perl');
check_('default before_script is inherited', join('|', @{ $ci->{jobs}{lint}{before} }), 'echo default-before');
check_('include recorded', join(' | ', @{ $ci->{includes} }), 'template: Security/Secret-Detection.gitlab-ci.yml | remote: https://example.invalid/ci.yml');
my $names = sub { join ' ', map { $_->{name} } @{ $_[0]{jobs} } };
my $why = sub { my ($p, $j) = @_; my ($s) = grep { $_->{name} eq $j } @{ $p->{skipped} }; $s ? $s->{reason} : 'selected' };
my $mr = GitLabCI::plan($ci, vars => { CI_PIPELINE_SOURCE => 'merge_request_event', CI_MERGE_REQUEST_SOURCE_BRANCH_NAME => 'vendor/prime', CI_DEFAULT_BRANCH => 'develop' },
                        changed => ['model/stations/Stations.sysml', 'README.md']);
check_('MR pipeline from vendor/prime', $names->($mr), 'grammar docs delta');
check_('MR pipeline: jobs without rules are left out', $why->($mr, 'lint'), 'no rules or only/except: not added to merge request pipelines');
my ($delta) = grep { $_->{name} eq 'delta' } @{ $mr->{jobs} };
check_('rule allow_failure and variables', "$delta->{allow_failure} $delta->{variables}{MODE}", 'true drop');
check_('include and trigger are skipped as GitLab-only', join(' | ', map { $_->{reason} } grep { $_->{name} =~ /^include|^pages$/ } @{ $mr->{skipped} }),
    'include: runs on GitLab only | include: runs on GitLab only | trigger: runs on GitLab only');
my $mr2 = GitLabCI::plan($ci, vars => { CI_PIPELINE_SOURCE => 'merge_request_event', CI_MERGE_REQUEST_SOURCE_BRANCH_NAME => 'feature/12-x' }, changed => ['README.md']);
check_('MR from a feature branch, docs unchanged', $names->($mr2), 'grammar');
check_('when: never rule', $why->($mr2, 'delta'), 'rules: rule 2 says when: never');
check_('changes: no match', $why->($mr2, 'docs'), 'rules: no rule matched');
my $push = GitLabCI::plan($ci, vars => { CI_PIPELINE_SOURCE => 'push', CI_COMMIT_BRANCH => 'develop', CI_COMMIT_REF_NAME => 'develop', CI_DEFAULT_BRANCH => 'develop' }, changed => ['docs/Nouns.md']);
check_('push to the default branch', $names->($push), 'lint grammar docs deploy');
check_('only: [main, /regex/] on develop', $why->($push, 'legacy'), 'only: not this pipeline');
my $rel = GitLabCI::plan($ci, vars => { CI_PIPELINE_SOURCE => 'push', CI_COMMIT_BRANCH => 'release/baseline-1', CI_COMMIT_REF_NAME => 'release/baseline-1' }, changed => []);
check_('push to a release branch: regex only matches', $names->($rel), 'lint legacy deploy');
my $tag = GitLabCI::plan($ci, vars => { CI_PIPELINE_SOURCE => 'push', CI_COMMIT_TAG => 'baseline-1', CI_COMMIT_REF_NAME => 'baseline-1', CI_DEFAULT_BRANCH => "develop" });
check_('tag pipeline (changes unknown counts as changed)', $names->($tag), 'lint docs release deploy');
check_(q{only: [main, /regex/] on a tag}, $why->($tag, q{legacy}), q{only: not this pipeline});
my $sch = GitLabCI::plan($ci, vars => { CI_PIPELINE_SOURCE => 'schedule', CI_COMMIT_BRANCH => 'develop', CI_COMMIT_REF_NAME => 'develop' });
check_('schedule pipeline', $names->($sch), 'lint docs nightly deploy');
my $sch2 = GitLabCI::plan($ci, vars => { CI_PIPELINE_SOURCE => 'schedule', CI_COMMIT_BRANCH => 'develop', SKIP_NIGHTLY => '1' });
check_('except: variables', $why->($sch2, 'nightly'), 'except: this pipeline is excluded');
my ($dep) = grep { $_->{name} eq 'deploy' } @{ $push->{jobs} };
check_('manual job: when manual, allowed to fail', "$dep->{when} $dep->{allow_failure}", 'manual true');
check_('--job selection', $names->(GitLabCI::plan($ci, vars => { CI_PIPELINE_SOURCE => 'push', CI_COMMIT_BRANCH => 'develop' }, only_jobs => ['lint'])), 'lint');

my $wf = GitLabCI::load(<<'EOF', file => 'wf.yml');
workflow:
  rules:
    - if: $CI_COMMIT_TITLE =~ /^WIP/
      when: never
    - if: $CI_PIPELINE_SOURCE == "merge_request_event"
    - if: $CI_COMMIT_BRANCH
      variables:
        FLAVOR: branch
a:
  script: echo $FLAVOR
  rules:
    - if: $FLAVOR == "branch"
EOF
check_('workflow: when never blocks the pipeline', GitLabCI::plan($wf, vars => { CI_COMMIT_TITLE => 'WIP: x', CI_COMMIT_BRANCH => 'b' })->{workflow}, 'blocked');
check_('workflow: no rule matched', GitLabCI::plan($wf, vars => { CI_PIPELINE_SOURCE => 'push' })->{skipped}[0]{reason}, 'workflow:rules: no rule matched');
check_('workflow variables reach job rules', $names->(GitLabCI::plan($wf, vars => { CI_PIPELINE_SOURCE => 'push', CI_COMMIT_BRANCH => 'b' })), 'a');

my $ref = GitLabCI::load(<<'EOF', file => 'ref.yml');
.setup:
  script:
    - echo one
    - echo two
job:
  script:
    - !reference [.setup, script]
    - echo three
EOF
check_('!reference is resolved and flattened', join('|', @{ $ref->{jobs}{job}{script} }), 'echo one|echo two|echo three');

check_('error: unknown stage', err_of(sub { GitLabCI::load("stages: [a]\nj:\n  stage: b\n  script: x\n", file => 'e.yml') }), "e.yml:2: job 'j': stage 'b' is not in stages (.pre, a, .post)");
check_('error: no script', err_of(sub { GitLabCI::load("j:\n  stage: test\n", file => 'e.yml') }), "e.yml:1: job 'j' has no script (or trigger)");
check_('error: extends unknown', err_of(sub { GitLabCI::load("j:\n  extends: .x\n  script: y\n", file => 'e.yml') }), "e.yml:1: job 'j' extends '.x', which is not defined");
check_('error: circular extends', err_of(sub { GitLabCI::load(".a:\n  extends: .b\n.b:\n  extends: .a\nj:\n  extends: .a\n  script: y\n", file => 'e.yml') }) =~ /circular chain/ ? 1 : 0, 1);
check_('error: rules with only', err_of(sub { GitLabCI::load("j:\n  script: y\n  only: [main]\n  rules:\n    - when: always\n", file => 'e.yml') }), "e.yml:1: job 'j': rules cannot be used with only/except");
check_('error: unknown when', err_of(sub { GitLabCI::load("j:\n  script: y\n  when: sometimes\n", file => 'e.yml') }), "e.yml:1: job 'j': unknown when 'sometimes'");
check_('error: a script line that YAML reads as a map', err_of(sub { GitLabCI::load("j:\n  script:\n    - echo \"a: b\"\n", file => 'e.yml') }), "e.yml:1: job 'j': a script line is a map (echo \"a: ...) -- quote a command that contains ': '");

# ---------------------------------------------------------------- local includes
{
    my $r = tempdir(CLEANUP => 1);
    spew("$r/.gitlab-ci.yml", <<'EOF');
include:
  - local: .gitlab/ci/base.yml
  - '.gitlab/ci/jobs-*.yml'
  - local: /.gitlab/ci/docker.yml
    rules:
      - if: $DOCKER == "true"
  - local: .gitlab/ci/never.yml
    rules:
      - exists: [no-such-file.txt]
  - template: Security/Secret-Detection.gitlab-ci.yml
variables:
  WHO: main
lint:
  variables:
    EXTRA: from-main
EOF
    spew("$r/.gitlab/ci/base.yml", <<'EOF');
include: .gitlab/ci/common.yml
stages: [check, docs]
variables:
  WHO: base
  BASEONLY: "1"
.model:
  stage: check
  rules:
    - if: $CI_PIPELINE_SOURCE == "push"
EOF
    spew("$r/.gitlab/ci/common.yml", <<'EOF');
.setup:
  script:
    - echo setup
EOF
    spew("$r/.gitlab/ci/jobs-check.yml", <<'EOF');
lint:
  extends: .model
  variables:
    LEVEL: strict
  script:
    - !reference [.setup, script]
    - echo lint
EOF
    spew("$r/.gitlab/ci/jobs-docs.yml", <<'EOF');
docs:
  extends: .model
  stage: docs
  script: echo docs
EOF
    spew("$r/.gitlab/ci/docker.yml", "scan:\n  stage: check\n  script: echo scan\n");
    spew("$r/.gitlab/ci/never.yml", "never:\n  stage: check\n  script: echo never\n");
    my $c = GitLabCI::load("$r/.gitlab-ci.yml", file => '.gitlab-ci.yml');
    check_('includes: jobs in order, included files first', join(' ', @{ $c->{order} }), 'lint docs');
    check_('includes: nested include, globs in sorted order, conditional left out',
        join(' ', @{ $c->{included} }), '.gitlab/ci/base.yml .gitlab/ci/common.yml .gitlab/ci/jobs-check.yml .gitlab/ci/jobs-docs.yml');
    check_('includes: stages from an included file', join(' ', @{ $c->{stages} }), '.pre check docs .post');
    check_('includes: the including file overrides global variables', "$c->{variables}{WHO} $c->{variables}{BASEONLY}", 'main 1');
    my $l = $c->{jobs}{lint};
    check_('includes: job maps deep-merge (main adds a variable, keeps the included ones)', "$l->{variables}{LEVEL} $l->{variables}{EXTRA}", 'strict from-main');
    check_('includes: extends and !reference across files', "$l->{stage} " . join('|', @{ $l->{script} }), 'check echo setup|echo lint');
    check_('includes: the file each job came from', "$l->{file} / $c->{jobs}{docs}{file}", '.gitlab/ci/jobs-check.yml + .gitlab-ci.yml / .gitlab/ci/jobs-docs.yml');
    check_('includes: template stays GitLab-only', join(' | ', @{ $c->{includes} }), 'template: Security/Secret-Detection.gitlab-ci.yml');
    my $p = GitLabCI::plan($c, vars => { CI_PIPELINE_SOURCE => 'push', CI_COMMIT_BRANCH => 'develop', DOCKER => 'true' });
    check_('includes: include:rules evaluated with the pipeline variables', $names->($p), 'lint scan docs');
    my ($sc) = grep { $_->{name} eq 'scan' } @{ $p->{jobs} };
    check_('includes: plan names the file', $sc->{file}, '.gitlab/ci/docker.yml');
    check_('includes: without the variable the include is left out', $names->(GitLabCI::plan($c, vars => { CI_PIPELINE_SOURCE => 'push', CI_COMMIT_BRANCH => 'develop' })), 'lint docs');
    spew("$r/no-such-file.txt", "x\n");
    check_('includes: rules:exists against the repository', $names->(GitLabCI::plan($c, vars => { CI_PIPELINE_SOURCE => 'push' })), 'lint never docs');
    check_('includes: text input, root option', join(' ', @{ GitLabCI::load("stages: [docs]\ninclude: .gitlab/ci/jobs-docs.yml\n.model:\n  stage: test\n  script: x\n", root => $r)->{order} }), 'docs');

    my $e = sub { my ($files, $main) = @_; my $d = tempdir(CLEANUP => 1); spew("$d/$_", $files->{$_}) for keys %$files; err_of(sub { GitLabCI::load($main, file => '.gitlab-ci.yml', root => $d) }) };
    check_('includes error: missing local file', $e->({}, "include: ci/nope.yml\nj:\n  script: x\n"),
        ".gitlab-ci.yml:1: include: local file 'ci/nope.yml' does not exist (paths start at the repository root)");
    check_('includes error: not YAML', $e->({ 'ci/a.txt' => "x\n" }, "include:\n  - local: ci/a.txt\n"), ".gitlab-ci.yml:1: include: local file 'ci/a.txt' must end in .yml or .yaml");
    check_('includes error: cycle', $e->({ 'a.yml' => "include: b.yml\n", 'b.yml' => "x: 1\ninclude: /a.yml\n" }, "include: a.yml\n"),
        'b.yml:2: include: cycle .gitlab-ci.yml -> a.yml -> b.yml -> a.yml');
    check_('includes error: the right file and line', $e->({ 'ci/j.yml' => "# jobs\n\nbroken:\n  stage: nowhere\n  script: x\n" }, "stages: [check]\ninclude: ci/j.yml\n"),
        "ci/j.yml:3: job 'broken': stage 'nowhere' is not in stages (.pre, check, .post)");
    check_('includes error: YAML error names the included file', $e->({ 'ci/bad.yml' => "a:\n  b: 1\n    c: 2\n" }, "include: ci/bad.yml\n"), 'ci/bad.yml:3: bad indentation');
    check_('includes error: !reference names its file', $e->({ 'ci/r.yml' => "j:\n  script:\n    - !reference [.nope, script]\n" }, "include: ci/r.yml\n"),
        'ci/r.yml:3: !reference [.nope, script] not found');
    my %many = map { sprintf('ci/f%03d.yml', $_) => "x$_: 1\n" } 1 .. 101;
    check_('includes error: more than 100 files', $e->(\%many, "include: 'ci/*.yml'\n"), '.gitlab-ci.yml:1: include: more than 100 included files');
    check_('includes error: rules when', $e->({ 'a.yml' => "x: 1\n" }, "include:\n  - local: a.yml\n    rules:\n      - when: manual\n"),
        ".gitlab-ci.yml:1: include: rules: when must be always or never, got 'manual'");
    check_('includes error: bad item', $e->({}, "include:\n  - [a, b]\n"), '.gitlab-ci.yml:1: include: an item must be a path or a map (local:, template:, project:, remote:, component:)');
    check_('includes: project/remote/component stay GitLab-only', join(' | ', @{ GitLabCI::load("include:\n  - project: g/p\n    file: /x.yml\n  - remote: https://e.invalid/y.yml\n  - component: e.invalid/c/d\@1\n", root => $r)->{includes} }),
        'file: /x.yml, project: g/p | remote: https://e.invalid/y.yml | component: e.invalid/c/d@1');
}

# ---------------------------------------------------------------- run: real shell jobs in a temporary git repository
my $have_git = system('git --version >' . File::Spec->devnull . ' 2>&1') == 0;
my $have_sh = system('sh -c true') == 0;
my $tmp = tempdir(CLEANUP => 1);
if ($have_git && $have_sh) {
    my $repo = "$tmp/repo";
    make_path($repo);
    spew("$repo/model/a.sysml", "package A;\n");
    spew("$repo/.gitlab-ci.yml", <<'EOF');
stages: [check, build, report]
variables:
  WHO: world
  GREET: "hello $WHO"
pass:
  stage: check
  script:
    - echo "$GREET from $CI_JOB_NAME in $CI_JOB_STAGE"
    - mkdir -p out && echo built > out/result.txt
    - echo run >> "$CI_PROJECT_DIR/../counter.txt"
  artifacts:
    paths: [out/]
soft:
  stage: check
  script: exit 3
  allow_failure:
    exit_codes: [3]
hard:
  stage: check
  script:
    - echo before-fail
    - exit 2
    - echo never-printed
  after_script:
    - 'echo "after: $CI_JOB_STATUS"'
later:
  stage: build
  script: echo should not run
cleanup:
  stage: report
  when: always
  script: echo cleanup ran
EOF
    my $q = sub { my $c = join ' ', map { "\"$_\"" } @_; system("cd \"$repo\" && $c >" . File::Spec->devnull . ' 2>&1') };
    $q->(qw(git init -q -b develop)); $q->(qw(git config user.email t@example.invalid)); $q->(qw(git config user.name T));
    $q->(qw(git config core.autocrlf false)); $q->(qw(git add -A)); $q->(qw(git commit -q -m), 'first');
    my $ci2 = GitLabCI::load("$repo/.gitlab-ci.yml");
    my %cache;
    my $t = 1_700_000_000;
    my $vars = { CI_PIPELINE_SOURCE => 'push', CI_COMMIT_BRANCH => 'develop', CI_COMMIT_REF_NAME => 'develop' };
    my $res = GitLabCI::run($ci2, dir => $repo, vars => $vars, log_dir => "$tmp/logs1", cache => \%cache, tree => 'tree1', clock => sub { $t++ });
    my %st = map { $_->{name} => $_->{status} } @{ $res->{jobs} };
    check_('pipeline failed', $res->{status}, 'failed');
    check_('job statuses', join(' ', map { "$_=$st{$_}" } qw(pass soft hard later cleanup)), 'pass=success soft=allowed_failure hard=failed later=skipped cleanup=success');
    my $plog = slurp("$tmp/logs1/pass.log") // '';
    has('pass log', $plog, qr/^\$ echo "\$GREET from \$CI_JOB_NAME in \$CI_JOB_STAGE"$/m, qr/^hello world from pass in check$/m);
    my $hlog = slurp("$tmp/logs1/hard.log") // '';
    has('hard log stops at the failure, after_script still runs', $hlog, qr/before-fail/, qr/^after: failed$/m);
    check_('hard log: nothing after the failing line', ($hlog =~ /never-printed\n/ && $hlog !~ /\$ echo never-printed/) ? 1 : 0, 0);
    check_('exit codes recorded', join(' ', map { $_->{exit} // '-' } @{ $res->{jobs} }), '0 3 2 - 0');
    check_('artifacts copied', slurp("$tmp/logs1/artifacts/pass/out/result.txt"), "built\n");
    check_('clock gives start times', $res->{jobs}[0]{started} >= 1_700_000_000 ? 1 : 0, 1);
    my $res2 = GitLabCI::run($ci2, dir => $repo, vars => $vars, log_dir => "$tmp/logs2", cache => \%cache, tree => 'tree1');
    check_('same tree: every run job comes from the cache', join(' ', map { $_->{cached} } grep { $_->{status} ne 'skipped' } @{ $res2->{jobs} }), '1 1 1 1');
    check_('cached job did not run again', slurp("$tmp/repo/../counter.txt"), "run\n");
    check_('cached log and artifacts are there', (slurp("$tmp/logs2/pass.log") // '') eq $plog && -f "$tmp/logs2/artifacts/pass/out/result.txt" ? 1 : 0, 1);
    my $res3 = GitLabCI::run($ci2, dir => $repo, vars => $vars, log_dir => "$tmp/logs3", cache => \%cache, tree => 'tree2', only_jobs => ['pass']);
    check_('another tree runs again', "$res3->{status} $res3->{jobs}[0]{cached}", 'success 0');
    check_('counter after the new run', slurp("$tmp/repo/../counter.txt"), "run\nrun\n");
    # parallel => N: the stage's jobs side by side, the same results in plan order, new cache entries merged back
    my %pcache;
    my $resp = GitLabCI::run($ci2, dir => $repo, vars => $vars, log_dir => "$tmp/logsp", cache => \%pcache, tree => 'treeP', parallel => 3);
    my %sp = map { $_->{name} => $_->{status} } @{ $resp->{jobs} };
    check_('parallel: same statuses, same order', join(' ', map { "$_->{name}=$_->{status}" } @{ $resp->{jobs} }), join(' ', map { "$_->{name}=$_->{status}" } @{ $res->{jobs} }));
    check_('parallel: same exit codes', join(' ', map { $_->{exit} // '-' } @{ $resp->{jobs} }), '0 3 2 - 0');
    check_('parallel: logs written', (slurp("$tmp/logsp/pass.log") // '') =~ /^hello world from pass in check$/m ? 1 : 0, 1);
    my $resp2 = GitLabCI::run($ci2, dir => $repo, vars => $vars, log_dir => "$tmp/logsp2", cache => \%pcache, tree => 'treeP', parallel => 3);
    check_('parallel: the children\'s cache entries reached the parent', join(' ', map { $_->{cached} } grep { $_->{status} ne 'skipped' } @{ $resp2->{jobs} }), '1 1 1 1');
    my $res4 = GitLabCI::run($ci2, dir => $repo, vars => { CI_PIPELINE_SOURCE => 'merge_request_event' }, log_dir => "$tmp/logs4");
    check_('nothing selected: skipped', $res4->{status}, 'skipped');

    # ---- gitlab.pl ci (the CLI) in the repository
    spew("$repo/.gitlab-ci.yml", <<'EOF');
stages: [check]
ok:
  stage: check
  script: echo fine
mr-only:
  stage: check
  script: echo mr
  rules:
    - if: $CI_PIPELINE_SOURCE == "merge_request_event"
fails:
  stage: check
  script: "false"
  rules:
    - if: $BREAK
EOF
    $q->(qw(git add -A)); $q->(qw(git commit -q -m), 'ci');
    my $cli = sub {
        my @args = @_;
        my $cmd = join ' ', map { "\"$_\"" } $^X, "-I$FindBin::Bin/../lib", '-MGitLabCI', '-e', 'exit GitLabCI::cli(@ARGV)', '--', @args;
        my $out = qx(cd "$repo" && $cmd 2>&1);
        return ($? >> 8, $out);
    };
    my ($rc, $out) = $cli->('--list');
    check_('cli --list exits 0', $rc, 0);
    has('cli --list', $out, qr/^ok\s+check\s+on_success\s+\.gitlab-ci\.yml\s+no rules/m, qr/^mr-only\s+-\s+skipped\s+\.gitlab-ci\.yml\s+rules: no rule matched/m, qr/^pipeline: 1 job$/m);
    ($rc, $out) = $cli->('--logs', "$tmp/cli1");
    check_('cli run exits 0', $rc, 0);
    has('cli run', $out, qr/^ok\s+check\s+success\s+[\d.]+s$/m, qr/^pipeline: success \(1 job\)$/m);
    ($rc, $out) = $cli->('--var', 'BREAK=1', '--logs', "$tmp/cli2");
    check_('cli failing pipeline exits 1', $rc, 1);
    has('cli failing run', $out, qr/^fails\s+check\s+failed/m, qr/^pipeline: failed \(2 jobs\)$/m);
    $q->(qw(git checkout -q -b feature/x));
    ($rc, $out) = $cli->('--event', 'merge_request_event', '--target', 'develop', '--list');
    has('cli MR event', $out, qr/^mr-only\s+check\s+on_success\s+\.gitlab-ci\.yml\s+rules: rule 1 matched/m, qr/^ok\s+-\s+skipped/m);
    ($rc, $out) = $cli->('--event', 'nope');
    check_('cli bad event exits 2', $rc, 2);
    has('cli bad event', $out, qr/unknown --event 'nope'/);
    ($rc, $out) = $cli->('--var', 'novalue');
    check_('cli bad --var exits 2', "$rc " . ($out =~ /--var needs KEY=VALUE/ ? 1 : 0), '2 1');
    ($rc, $out) = $cli->('--file', 'missing.yml');
    check_('cli missing file exits 2', "$rc " . ($out =~ /no missing\.yml here/ ? 1 : 0), '2 1');
    ($rc, $out) = $cli->('--event', 'tag');
    check_('cli tag event without a tag exits 2', "$rc " . ($out =~ /needs --tag/ ? 1 : 0), '2 1');
    spew("$repo/.gitlab/ci/extra.yml", "extra:\n  stage: check\n  script: echo extra\n");
    spew("$repo/.gitlab-ci.yml", "include: .gitlab/ci/extra.yml\nstages: [check]\nok:\n  stage: check\n  script: echo fine\n");
    ($rc, $out) = $cli->('--list', '--branch', 'develop');
    has('cli --list with an include', $out, qr/^extra\s+check\s+on_success\s+\.gitlab\/ci\/extra\.yml\s+no rules/m, qr/^ok\s+check\s+on_success\s+\.gitlab-ci\.yml\s/m, qr/^included: \.gitlab\/ci\/extra\.yml$/m);
    ($rc, $out) = $cli->('--branch', 'develop', '--logs', "$tmp/cli3");
    has('cli runs included jobs', $out, qr/^extra\s+check\s+success/m, qr/^pipeline: success \(2 jobs\)$/m);
    my $notrepo = tempdir(CLEANUP => 1);
    my $out2 = qx(cd "$notrepo" && "$^X" "-I$FindBin::Bin/../lib" -MGitLabCI -e "exit GitLabCI::cli()" 2>&1);
    check_('cli outside a repository exits 2', ($? >> 8) . ' ' . ($out2 =~ /not inside a git work tree/ ? 1 : 0), '2 1');
} else { skip_('run and cli', 'git or sh not available') for 1 .. 30 }

print "1..$n\n";
print $bad ? "# $bad of $n FAILED\n" : "# all $n passed\n";
exit($bad ? 1 : 0);
