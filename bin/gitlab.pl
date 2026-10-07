#!/usr/bin/perl
# gitlab.pl -- GitLab from the command line: project setup from one file, sprints as milestones, issues and merge
# requests with templates and quick actions, pipelines, tags and releases, wiki pages, CSV exports for the status
# metrics, the .gitlab-ci.yml runner (offline), and gitflow for a model repository.
#
# Talks to a real GitLab (REST API v4 via curl; --url, token in $GITLAB_TOKEN) or to the offline emulator
# (--local DIR; lib/GitLab.pm), which is how the kit trains and tests without a server. Core Perl only.
#
#   perl bin/gitlab.pl --local data/gl --as tom setup tools/gitlab/templates/project.conf
#   perl bin/gitlab.pl --url https://gitlab.example.com --project tidewater/model issue list --label type::story
#   perl bin/gitlab.pl ci --event merge_request_event --branch feature/12-x --target develop
#   perl bin/gitlab.pl help [COMMAND]
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Cwd qw(abs_path getcwd);
use GitLab;
use GitFlow;
use POSIX ();

my $KIT = abs_path("$FindBin::Bin/..");
my %HELP = (
    '' => <<'EOF',
usage: gitlab.pl [--url URL [--token-env VAR] [--sudo] | --local DIR] [--project PATH] [--as USER]
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
  schedule new|list|run|delete|due|next ...                   cron pipeline schedules (gitlab.pl help schedule)
  analytics [--since D] [--until D] [--by sprint|week|month] [--csv DIR]   value stream, DORA, CI/CD, MRs, issues
  board list                     the issue boards: lists in order and the milestone scope ([boards] in setup)
  windchill intake FILE.csv | status [--csv FILE]            Windchill requests -> issues; progress back (help windchill)
  trigger new|list|run ...       pipeline trigger tokens: another system starts a pipeline (gitlab.pl help trigger)
  token deploy new|list ...      deploy tokens: a scoped credential for a machine (gitlab.pl help token)
  ci [OPTIONS]                   run .gitlab-ci.yml here, offline (gitlab.pl help ci)
  flow init|start|publish|finish|released|vendor|sync|take   gitflow in the current clone (gitlab.pl help flow)
  user USERNAME [--name N] [--email E]                        create a user (emulator: any; server: admin token)
  help [COMMAND]

--dry-run prints each request that would change something (METHOD /api/v4/... {json}) and sends or
changes nothing; reads still answer. It works with both backends (flow refuses it: flow pushes with git).
Backends: --local DIR is the offline emulator (state in DIR/gitlab.json); --url talks to a GitLab server
with the token in $GITLAB_TOKEN (--token-env VAR to change; --sudo acts as --as USER with an admin token).
Defaults from the environment: GITLAB_URL, GITLAB_LOCAL, GITLAB_PROJECT, GITLAB_USER.
EOF
    setup => <<'EOF',
gitlab.pl setup FILE
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
    [boards]     NAME = LABEL LABEL ... [| milestone=started|upcoming|none|any|TITLE]
    [windchill]  the Windchill intake mapping (read by gitlab.pl windchill, not by setup)
  A section may appear more than once; its lines add up (a second [labels] adds labels).
  Boards: setup creates a missing board, adds the missing label lists, puts them in the file's order and
  scopes the board to the milestone (Premium/Ultimate; on Free it warns and the board shows every milestone).
  Creates the project if it does not exist. Safe to re-run: labels and protections are updated in place.
gitlab.pl setup --diff FILE
  Read only: compare the project file with the live project and print each difference, as
  "[section] name: file X, live Y", "missing" or "live only". Exit 1 when anything differs (drift).
gitlab.pl --dry-run setup FILE
  Print the requests setup would send (METHOD /api/v4/... {json}) and change nothing.
EOF
    sprints => "gitlab.pl sprints START COUNT [--weeks 2] [--prefix \"Sprint \"]\n  COUNT milestones of WEEKS weeks from START (a Monday); each is due on the Friday of its last week.\n",
    issue => <<'EOF',
gitlab.pl issue new TITLE [--template NAME|FILE] [--description TEXT] [--label L]... [--milestone M]
                          [--assign USER]... [--type issue|task|incident] [--weight N] [--due DATE]
gitlab.pl issue list [--state opened|closed|all] [--label L]... [--milestone M] [--type T]
gitlab.pl issue show IID | close IID | reopen IID
gitlab.pl issue note IID TEXT | --file FILE     a comment; /label /milestone /assign /estimate /spend /close ... run
gitlab.pl issue link IID TARGET [--type relates_to|blocks|is_blocked_by]
gitlab.pl issue label IID [--add L]... [--remove L]...
  --template NAME reads .gitlab/issue_templates/NAME.md of the current directory (or a file path).
EOF
    mr => <<'EOF',
gitlab.pl mr new --source BRANCH [--target BRANCH] --title TITLE [--template NAME|FILE] [--description TEXT]
                 [--label L]... [--milestone M] [--reviewer USER]... [--keep-branch]
gitlab.pl mr list [--state opened|merged|closed|all] | show IID | approve IID | merge IID
gitlab.pl mr note IID TEXT [--resolvable] | resolve IID
  --target defaults to the project's default branch. merge refuses, with GitLab's reason, until the
  pipeline succeeds, the approvals (and code owners) are in and discussions are resolved.
EOF
    pipeline => "gitlab.pl pipeline run REF [--source web|push|schedule] [--var K=V]...\ngitlab.pl pipeline list [--ref REF] [--status S] | show ID\n  show lists the jobs; with --local, each job's log path too.\n",
    tag => "gitlab.pl tag NAME REF [--message M]\n  An annotated tag when --message is given. On the emulator, a tag pipeline runs.\n",
    release => "gitlab.pl release TAG [--notes FILE] [--name NAME] [--milestone M]...\n  A release for an existing tag; the notes file is Markdown.\n",
    wiki => "gitlab.pl wiki put TITLE FILE | wiki list | wiki show TITLE\n",
    export => "gitlab.pl export DIR [--since YYYY-MM-DD] [--until YYYY-MM-DD]\n  Writes DIR/ci_jobs.csv (ts,job,branch,result,minutes), mrs.csv, issues.csv, defects.csv and\n  tracker/sprint-N.csv (id,status,blocked_days,blocker) -- the inputs of bin/status-metrics.pl.\n",
    ci => "gitlab.pl ci [--file .gitlab-ci.yml] [--event push|merge_request_event|tag|schedule|web|trigger] [--branch B]\n             [--target B] [--tag T] [--var K=V]... [--job NAME] [--manual] [--list]\n  Runs the pipeline locally in the current directory (lib/GitLabCI.pm). --list shows the jobs it would run.\n",
    flow => <<'EOF',
gitlab.pl flow init                              develop from main (first commit on an empty repo)
gitlab.pl flow start feature|release|hotfix NAME a branch from develop (hotfix: from main)
gitlab.pl flow publish                           push the current branch (the emulator runs its pipelines)
gitlab.pl flow finish [--title T] [--template NAME|FILE] [--description TEXT] [--label L]... [--milestone M]
                      [--reviewer U]...          push and open the MR (feature -> develop, release/hotfix -> main)
gitlab.pl flow released IID [--notes FILE] [--tag NAME]   after a release/hotfix MR merged: tag main
                                                 (sha256 of docs/ in the message), release, back-merge MR
gitlab.pl flow vendor DROPDIR VERSION            commit the converted prime drop on vendor/prime, then merge it
                      [--layout-map FILE]       (default: the repository's .ci/layout.map, if it has one)
                                                 into feature/drop-VERSION (conflicts are listed, not resolved);
                                                 a clean merge also raises .ci/outline-max to the drop's outline
                                                 count, in its own commit, so the allowance is reviewed with the MR
gitlab.pl flow allowance VERSION                 the same, after you resolved a drop's conflicts and committed
gitlab.pl flow take ours|theirs PATH...          resolve conflicted files wholesale
gitlab.pl flow sync                              fetch; fast-forward local main and develop
  Run inside a clone of the project. Branch names: main, develop, feature/, release/, hotfix/, vendor/prime.
EOF
    user => "gitlab.pl user USERNAME [--name NAME] [--email EMAIL]\n",
    package => "gitlab.pl package put NAME VERSION FILE        upload to the Generic Package Registry (sha256 recorded)\ngitlab.pl package get NAME VERSION FILE [DEST]  download (the emulator checks the sha256)\ngitlab.pl package list\n  Names: letters, digits and . _ -; versions also +. Use it for released baselines: the docs bundle, the drop, the SBOM.\n",
    trigger => "gitlab.pl trigger new DESCRIPTION | trigger list | trigger run TOKEN REF [--var K=V]...\n  Pipeline trigger tokens: another system (the prime's Jenkins) starts a pipeline with CI_PIPELINE_SOURCE \"trigger\"\n  and its variables (e.g. DROP_VERSION). Maintainers create them; a triggered pipeline runs as the token's owner.\n",
    token => "gitlab.pl token deploy new NAME [--scope S]... [--expires YYYY-MM-DD] | token deploy list\n  Deploy tokens: a credential for a machine outside the project, limited to its scopes (read_repository,\n  read_registry, write_registry, read_package_registry, write_package_registry). Give the prime's Jenkins\n  write_package_registry only, with an expiry date.\n",
    pages => "gitlab.pl pages\n  The Pages URL and, on the emulator, the folder: a job named `pages` that succeeds on the default branch\n  publishes its public/ artifact there.\n",
    schedule => <<'EOF',
gitlab.pl schedule new DESCRIPTION --cron "MIN HOUR DOM MON DOW" --ref BRANCH [--tz ZONE] [--var K=V]... [--inactive]
gitlab.pl schedule list                 id, cron, zone, ref, next run (UTC), owner, last pipeline
gitlab.pl schedule run ID               run it now ("Run pipeline schedule"); the next run time does not change
gitlab.pl schedule delete ID
gitlab.pl schedule due --until ISO      emulator only: run every scheduled pipeline due up to ISO, in time order
gitlab.pl schedule next "CRON" [--tz ZONE] [--from ISO] [-n N]   the next N run times (check a cron line)
  Cron: five fields; *, lists (1,15), ranges (1-5), steps (*/15), names (mon-fri, jan); @daily @weekly ...
  Zones: UTC (default), fixed offsets (+05:30, -0400), America/New_York and the other US zones with daylight
  saving. A job sees $CI_PIPELINE_SOURCE == "schedule" and the schedule's variables.
EOF
    analytics => <<'EOF',
gitlab.pl analytics [--since YYYY-MM-DD] [--until YYYY-MM-DD] [--by sprint|week|month] [--csv DIR]
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
  --by sprint uses the "Sprint N" milestones' dates. --csv DIR also writes one CSV per table.
EOF
    board => "gitlab.pl board list\n  Each issue board: its label lists in order and its milestone scope (any, none, upcoming, started or a\n  milestone title). Boards are made by setup from the [boards] section of the project file.\n",
    windchill => <<'EOF',
gitlab.pl windchill intake FILE.csv [--conf FILE] [--note] [--dry-run]
  One issue per new Windchill number in a Windchill report exported as CSV (comma, tab or semicolon; UTF-8,
  UTF-16 or Windows-1252; quoted cells may hold commas and line breaks). The issue is titled "NUMBER: title",
  carries the link, requester, need date (also the due date), type, state, priority and description, and the
  labels of [windchill] labels plus the priority-map label. Rows whose state is not in `accept` are skipped.
  Safe to re-run: a number that already has an issue is skipped; if Windchill changed its title, state or
  priority since, the change is printed as drift, and --note adds it to the issue as a comment.
  Ends with: windchill: N rows, C created, S skipped, D drift
gitlab.pl windchill status [--conf FILE] [--csv FILE|-] [--since YYYY-MM-DD]
  One row per Windchill-sourced issue: number, issue, open/closed, workflow:: column, milestone, closed date,
  merge requests that close or name it, the first release (or tag) holding the merge, and the issue URL.
  --csv writes it as CSV (CRLF, UTF-8 with BOM for Excel) to paste or import into Windchill; --since keeps
  issues updated since DATE.
  --conf defaults to .gitlab/project.conf in this directory or above; the project comes from --project or its
  [project] path. The [windchill] section maps the export's column names (tools/gitlab/templates/project.conf).
EOF
    env => "gitlab.pl env list | env deployments [NAME]\n  Environments come from jobs with `environment:`; every successful run of one is a deployment.\n",
);

sub usage { my ($cmd) = @_; print STDERR $HELP{ $cmd // '' } // $HELP{''}; exit 2 }
sub opts {                                    # opts(\@args, spec) -> %o ; spec 'name=s', 'name=s@', 'flag'
    my ($args, @spec) = @_;
    my %t = map { /^([\w-]+)(=s@?)?$/ ? ($1 => $2 // '') : () } @spec;
    my (%o, @rest);
    while (@$args) {
        my $a = shift @$args;
        if ($a =~ /^--([\w-]+)(?:=(.*))?$/ && exists $t{$1}) {
            my ($k, $v) = ($1, $2);
            if ($t{$k} eq '') { $o{$k} = 1; next }
            $v //= @$args ? shift @$args : die "gitlab.pl: --$k needs a value\n";
            if ($t{$k} eq '=s@') { push @{ $o{$k} }, $v } else { $o{$k} = $v }
        } elsif ($a =~ /^--./) { die "gitlab.pl: unknown option $a\n" }
        else { push @rest, $a }
    }
    @$args = @rest;
    %o;
}
sub slurp { my $f = shift; open my $fh, '<:raw', $f or die "gitlab.pl: cannot read $f: $!\n"; local $/; my $t = <$fh>; close $fh; $t }
sub template {
    my ($name, $kind) = @_;
    return undef unless defined $name;
    return slurp($name) if -f $name;
    my $f = ".gitlab/${kind}_templates/$name.md";
    -f $f or die "gitlab.pl: no template '$name' ($f not found)\n";
    slurp($f);
}

# ---------------------------------------------------------------- global options
my %G = (url => $ENV{GITLAB_URL}, local => $ENV{GITLAB_LOCAL}, project => $ENV{GITLAB_PROJECT}, as => $ENV{GITLAB_USER}, 'token-env' => 'GITLAB_TOKEN');
while (@ARGV && $ARGV[0] =~ /^--?(.+)$/) {
    my $k = $1;
    last if $k !~ /^(url|token-env|local|project|as|now|dry-run|no-cache|sudo|help|h)$/;
    shift @ARGV;
    if ($k =~ /^(dry-run|no-cache|sudo)$/) { $G{$k} = 1; next }
    if ($k eq 'help' || $k eq 'h') { print $HELP{''}; exit 0 }
    @ARGV or do { print STDERR "gitlab.pl: --$k needs a value\n"; exit 2 };
    $G{$k} = shift @ARGV;
}
my $cmd = shift @ARGV // usage();
if ($cmd eq 'help') { my $c = shift @ARGV // ''; print $HELP{$c} // $HELP{''}; exit 0 }
if ($cmd eq 'ci') { require GitLabCI; exit GitLabCI::cli(@ARGV) }
exists $HELP{$cmd} or do { print STDERR "gitlab.pl: unknown command '$cmd' (gitlab.pl help)\n"; exit 2 };

if ($cmd eq 'schedule' && ($ARGV[0] // '') eq 'next' && !(defined $G{local} && length $G{local}) && !$G{url}) {   # no backend needed
    my @a = map { $_ eq '-n' ? '--n' : $_ } @ARGV[1 .. $#ARGV];
    my $r = eval { my %o = opts(\@a, 'tz=s', 'from=s', 'n=s'); schedule_next(\@a, \%o, defined $G{now} ? GitLab::_epoch($G{now}) : time); 1 };
    if (!$r) { (my $e = $@) =~ s/^(?:gitlab\.pl|GitLab): //; print STDERR "gitlab.pl: $e"; exit 1 }
    exit 0;
}
sub schedule_next {                           # the next N run times of a cron line, UTC and local
    my ($a, $o, $now) = @_;
    @$a or die "gitlab.pl: schedule next needs a CRON line\n";
    my $from = defined $o->{from} ? GitLab::_epoch($o->{from}) : $now;
    my $tz = $o->{tz} // 'UTC';
    for my $t (GitLab::cron_runs($a->[0], $tz, $from, $o->{n} // 5)) {
        my $off = GitLab::tz_offset($tz, $t);
        printf "%s  (%s %s%02d:%02d)\n", GitLab::_iso($t), POSIX::strftime('%a %Y-%m-%d %H:%M', gmtime($t + $off)), $off < 0 ? '-' : '+', abs($off) / 3600, abs($off) % 3600 / 60;
    }
}

my $gl;
my $rc = eval {
    $gl = defined $G{local} && length $G{local} && !$G{url}
        ? GitLab->new(local => $G{local}, cache => !$G{'no-cache'}, dry_run => $G{'dry-run'}, (defined $G{now} ? (now => $G{now}) : ()))
        : GitLab->new(url => $G{url} // die("gitlab.pl: give --url URL (or GITLAB_URL) or --local DIR (the emulator)\n"),
                      token_env => $G{'token-env'}, dry_run => $G{'dry-run'}, sudo => $G{sudo}, (defined $G{now} ? (now => $G{now}) : ()));
    $gl->as($G{as}) if defined $G{as} && length $G{as};
    my $r = main_cmd($cmd, @ARGV);
    $gl->save;
    $r;
};
if (!defined $rc) {
    my $e = $@ || "failed\n";
    eval { $gl->save if $gl };
    $e =~ s/^(?:gitlab\.pl|GitLab|GitFlow|Windchill): //;
    print STDERR "gitlab.pl: $e";
    exit 1;
}
exit $rc;

sub find_conf {                               # .gitlab/project.conf here or in a directory above
    my $d = getcwd();
    while (1) { return "$d/.gitlab/project.conf" if -f "$d/.gitlab/project.conf"; my $up = $d =~ s{/[^/]*$}{}r; last if $up eq $d || !length $up; $d = $up }
    undef;
}
sub P { $G{project} // die "gitlab.pl: give --project GROUP/NAME (or GITLAB_PROJECT)\n" }
sub need { my ($n, $what, @a) = @_; @a >= $n or die "gitlab.pl: $what\n" }
sub show_issue {
    my $i = shift;
    printf "#%d  %s  %s\n", $i->{iid}, $i->{state}, $i->{title};
    printf "  type: %s   labels: %s   milestone: %s   assignees: %s\n", $i->{issue_type} // 'issue', join(' ', map { "~$_" } @{ $i->{labels} // [] }) || '-',
        ref $i->{milestone} ? $i->{milestone}{title} : '-', join(' ', map { "\@$_->{username}" } @{ $i->{assignees} // [] }) || '-';
    print "  $i->{web_url}\n" if $i->{web_url};
    print "\n$i->{description}\n" if length($i->{description} // '');
    for my $n (@{ $i->{notes} // [] }) { printf "\n  %s %s\@%s: %s\n", $n->{created_at}, $n->{system} ? '* ' : '', $n->{author}{username}, $n->{body} =~ s/\n/\n    /gr }
}
sub main_cmd {
    my ($cmd, @a) = @_;
    if ($cmd eq 'setup') {
        my %o = opts(\@a, 'diff');
        need(1, 'setup needs a project file (tools/gitlab/templates/project.conf)', @a);
        if ($o{diff}) {                       # the drift check: read only
            my $d = $gl->diff_project_file($a[0], ($G{project} ? (project => $G{project}) : ()));
            print @$d ? join('', map { "$_\n" } @$d) : "no differences: the project matches $a[0]\n";
            return @$d ? 1 : 0;
        }
        my $log = $gl->apply_project_file($a[0], ($G{project} ? (project => $G{project}) : ()));
        print "$_\n" for @$log;
        return 0;
    }
    if ($cmd eq 'user') {
        my %o = opts(\@a, 'name=s', 'email=s');
        need(1, 'user needs a USERNAME', @a);
        my $u = $gl->create_user($a[0], name => $o{name}, email => $o{email});
        print "user $a[0]\n";
        return 0;
    }
    if ($cmd eq 'sprints') {
        my %o = opts(\@a, 'weeks=s', 'prefix=s');
        need(2, 'sprints needs START (YYYY-MM-DD) and COUNT', @a);
        $a[1] =~ /^\d+$/ or die "gitlab.pl: sprint COUNT must be a number\n";
        printf "%s  %s .. %s\n", $_->{title}, $_->{start_date} // '', $_->{due_date} // '' for $gl->sprints(P(), $a[0], $a[1], weeks => $o{weeks} // 2, prefix => $o{prefix});
        return 0;
    }
    if ($cmd eq 'issue') {
        my $sub = shift @a // usage('issue');
        my %o = opts(\@a, 'template=s', 'description=s', 'label=s@', 'milestone=s', 'assign=s@', 'type=s', 'weight=s', 'due=s', 'state=s', 'file=s', 'add=s@', 'remove=s@');
        if ($sub eq 'new') {
            need(1, 'issue new needs a TITLE', @a);
            my $d = $o{description} // template($o{template}, 'issue') // '';
            my $i = $gl->create_issue(P(), title => $a[0], description => $d, labels => $o{label}, milestone => $o{milestone}, assignees => $o{assign},
                                      issue_type => $o{type}, weight => $o{weight}, due_date => $o{due});
            print "#$i->{iid} $a[0]\n" . ($i->{web_url} ? "$i->{web_url}\n" : '');
        } elsif ($sub eq 'list') {
            for my $i (@{ $gl->issues(P(), state => $o{state} // 'opened', labels => $o{label}, milestone => $o{milestone}, issue_type => $o{type}) }) {
                printf "#%-4d %-7s %-40s %s\n", $i->{iid}, $i->{state}, join(' ', map { "~$_" } @{ $i->{labels} // [] }), $i->{title};
            }
        } elsif ($sub eq 'show') { need(1, 'issue show needs an IID', @a); show_issue($gl->issue(P(), $a[0])) }
        elsif ($sub eq 'close' || $sub eq 'reopen') { need(1, "issue $sub needs an IID", @a); my $i = $gl->update_issue(P(), $a[0], state_event => $sub); print "#$a[0] $i->{state}\n" }
        elsif ($sub eq 'note') {
            need(1, 'issue note needs an IID and TEXT (or --file F)', @a);
            my $body = defined $o{file} ? slurp($o{file}) : $a[1] // die "gitlab.pl: issue note needs TEXT or --file FILE\n";
            $gl->add_note(P(), 'issue', $a[0], $body);
            print "noted on #$a[0]\n";
        } elsif ($sub eq 'link') {
            need(2, 'issue link needs IID and TARGET', @a);
            $gl->link_issues(P(), $a[0], $a[1], $o{type} // 'relates_to');
            print "#$a[0] " . ($o{type} // 'relates_to') . " #$a[1]\n";
        } elsif ($sub eq 'label') {
            need(1, 'issue label needs an IID', @a);
            my $i = $gl->update_issue(P(), $a[0], add_labels => $o{add}, remove_labels => $o{remove});
            print "#$a[0] " . join(' ', map { "~$_" } @{ $i->{labels} // [] }) . "\n";
        } else { usage('issue') }
        return 0;
    }
    if ($cmd eq 'mr') {
        my $sub = shift @a // usage('mr');
        my %o = opts(\@a, 'source=s', 'target=s', 'title=s', 'template=s', 'description=s', 'label=s@', 'milestone=s', 'reviewer=s@', 'keep-branch', 'state=s', 'resolvable');
        if ($sub eq 'new') {
            defined $o{source} && defined $o{title} or die "gitlab.pl: mr new needs --source BRANCH and --title TITLE\n";
            my $t = $o{target} // $gl->project(P())->{default_branch};
            my $m = $gl->create_mr(P(), source_branch => $o{source}, target_branch => $t, title => $o{title}, description => $o{description} // template($o{template}, 'merge_request') // '',
                                   labels => $o{label}, milestone => $o{milestone}, reviewers => $o{reviewer}, remove_source_branch => $o{'keep-branch'} ? 0 : 1);
            print "!$m->{iid} $o{source} -> $t: $o{title}\n" . ($m->{web_url} ? "$m->{web_url}\n" : '');
            print "pipeline #$m->{head_pipeline}{id} $m->{head_pipeline}{status}\n" if $m->{head_pipeline};
        } elsif ($sub eq 'list') {
            for my $m (@{ $gl->mrs(P(), state => $o{state} // 'opened') }) {
                printf "!%-4d %-7s %s -> %s  %s%s\n", $m->{iid}, $m->{state}, $m->{source_branch}, $m->{target_branch}, $m->{title},
                    $m->{head_pipeline} ? "  (pipeline $m->{head_pipeline}{status})" : '';
            }
        } elsif ($sub eq 'show') {
            need(1, 'mr show needs an IID', @a);
            my $m = $gl->mr(P(), $a[0]);
            printf "!%d  %s  %s -> %s  %s\n", $m->{iid}, $m->{state}, $m->{source_branch}, $m->{target_branch}, $m->{title};
            printf "  author: \@%s   labels: %s   approved by: %s   pipeline: %s\n", $m->{author}{username} // '?', join(' ', map { "~$_" } @{ $m->{labels} // [] }) || '-',
                join(' ', map { "\@$_->{user}{username}" } @{ $m->{approved_by} // [] }) || '-', $m->{head_pipeline} ? "#$m->{head_pipeline}{id} $m->{head_pipeline}{status}" : '-';
            print "  merged $m->{merged_at} as " . substr($m->{merge_commit_sha} // '', 0, 8) . "\n" if $m->{merged_at};
            print_widgets($m->{reports}) if $m->{reports};
            print "\n$m->{description}\n" if length($m->{description} // '');
            for my $n (@{ $m->{notes} // [] }) { printf "\n  %s %s\@%s: %s\n", $n->{created_at}, $n->{system} ? '* ' : '', $n->{author}{username}, $n->{body} }
        } elsif ($sub eq 'approve') { need(1, 'mr approve needs an IID', @a); $gl->approve_mr(P(), $a[0]); print "!$a[0] approved by " . ($gl->as // '?') . "\n" }
        elsif ($sub eq 'merge') {
            need(1, 'mr merge needs an IID', @a);
            my $m = $gl->merge_mr(P(), $a[0]);
            print "!$a[0] merged" . ($m->{merge_commit_sha} ? ' as ' . substr($m->{merge_commit_sha}, 0, 8) : '') . "\n";
        } elsif ($sub eq 'note') {
            need(2, 'mr note needs IID and TEXT', @a);
            $gl->add_note(P(), 'mr', $a[0], $a[1], resolvable => $o{resolvable});
            print "noted on !$a[0]\n";
        } elsif ($sub eq 'resolve') { need(1, 'mr resolve needs an IID', @a); $gl->resolve_discussions(P(), $a[0]); print "!$a[0] discussions resolved\n" }
        else { usage('mr') }
        return 0;
    }
    if ($cmd eq 'pipeline') {
        my $sub = shift @a // usage('pipeline');
        my %o = opts(\@a, 'source=s', 'var=s@', 'ref=s', 'status=s');
        if ($sub eq 'run') {
            need(1, 'pipeline run needs a REF', @a);
            my %v = map { /^([^=]+)=(.*)$/ ? ($1 => $2) : die "gitlab.pl: --var is KEY=VALUE\n" } @{ $o{var} // [] };
            my $pl = $gl->run_pipeline(P(), $a[0], source => $o{source}, variables => \%v);
            print $pl ? "pipeline #$pl->{id} $pl->{status}\n" : "no pipeline: no job matched (rules)\n";
            return $pl && ($pl->{status} // '') eq 'failed' ? 1 : 0;
        } elsif ($sub eq 'list') {
            for my $pl (@{ $gl->pipelines(P(), ref => $o{ref}, status => $o{status}) }) {
                printf "#%-5d %-8s %-20s %-30s %s %s\n", $pl->{id}, $pl->{status}, $pl->{source} // '', $pl->{ref}, substr($pl->{sha} // '', 0, 8), $pl->{created_at} // '';
            }
        } elsif ($sub eq 'show') {
            need(1, 'pipeline show needs an ID', @a);
            my $pl = $gl->pipeline(P(), $a[0]);
            printf "#%d %s  %s  %s  %s\n", $pl->{id}, $pl->{status}, $pl->{source} // '', $pl->{ref}, $pl->{sha} // '';
            print "  yaml error: $pl->{yaml_errors}\n" if $pl->{yaml_errors};
            for my $j (@{ $gl->jobs(P(), $a[0]) }) {
                printf "  %-10s %-14s %-16s %6s s%s\n", $j->{stage}, $j->{name}, $j->{status} . ($j->{allow_failure} && $j->{status} eq 'failed' ? ' (allowed)' : ''),
                    defined $j->{duration} ? sprintf('%.1f', $j->{duration}) : '-', $j->{log} ? "  $j->{log}" : '';
            }
        } else { usage('pipeline') }
        return 0;
    }
    if ($cmd eq 'tag') {
        my %o = opts(\@a, 'message=s');
        need(2, 'tag needs NAME and REF', @a);
        my $t = $gl->create_tag(P(), $a[0], $a[1], $o{message});
        print "tag $a[0] at " . substr($t->{target} // $t->{commit}{id} // '', 0, 8) . "\n";
        return 0;
    }
    if ($cmd eq 'release') {
        my %o = opts(\@a, 'notes=s', 'name=s', 'milestone=s@');
        need(1, 'release needs a TAG', @a);
        my $r = $gl->create_release(P(), tag_name => $a[0], name => $o{name}, description => defined $o{notes} ? slurp($o{notes}) : '', milestones => $o{milestone});
        print "release $a[0]\n";
        return 0;
    }
    if ($cmd eq 'wiki') {
        my $sub = shift @a // usage('wiki');
        if ($sub eq 'put') { need(2, 'wiki put needs TITLE and FILE', @a); my $w = $gl->wiki_put(P(), $a[0], slurp($a[1])); print "wiki $a[0]\n" }
        elsif ($sub eq 'list') { print "$_->{slug}\t$_->{title}\n" for @{ $gl->wiki(P()) } }
        elsif ($sub eq 'show') { need(1, 'wiki show needs a TITLE', @a); (my $s = $a[0]) =~ s/\s+/-/g; my ($w) = grep { $_->{slug} eq $s } @{ $gl->wiki(P()) }; defined $w or die "gitlab.pl: no wiki page '$a[0]'\n"; print $w->{content} }
        else { usage('wiki') }
        return 0;
    }
    if ($cmd eq 'export') {
        my %o = opts(\@a, 'since=s', 'until=s');
        need(1, 'export needs a DIR', @a);
        my $n = $gl->export(P(), $a[0], since => $o{since}, until => $o{until});
        print join(', ', map { "$_ $n->{$_}" } sort keys %$n) . " -> $a[0]\n";
        return 0;
    }
    if ($cmd eq 'package') {
        my $sub = shift @a // usage('package');
        if ($sub eq 'put') { need(3, 'package put needs NAME VERSION FILE', @a); my $r = $gl->package_put(P(), @a[0 .. 2]); print "$r->{name}/$r->{version}/$r->{file_name}  $r->{size} bytes  sha256 $r->{file_sha256}\n" }
        elsif ($sub eq 'get') { need(3, 'package get needs NAME VERSION FILE [DEST]', @a); print $gl->package_get(P(), @a[0 .. 3]) . "\n" }
        elsif ($sub eq 'list') { for my $k (@{ $gl->packages(P()) }) { printf "%s/%s  %s\n", $k->{name}, $k->{version}, join(' ', map { $_->{file_name} } @{ $k->{files} // [] }) } }
        else { usage('package') }
        return 0;
    }
    if ($cmd eq 'trigger') {
        my $sub = shift @a // usage('trigger');
        if ($sub eq 'new') { need(1, 'trigger new needs a DESCRIPTION', @a); my $tr = $gl->create_trigger(P(), "@a"); print "trigger $tr->{id}: $tr->{token}  ($tr->{description})\n" }
        elsif ($sub eq 'list') { printf "%s  %s  owner %s\n", $_->{id}, $_->{description}, ($_->{owner} // {})->{username} // '' for @{ $gl->triggers(P()) } }
        elsif ($sub eq 'run') {
            my %o = opts(\@a, 'var=s@');
            need(2, 'trigger run needs TOKEN REF', @a);
            my %v = map { /^([^=]+)=(.*)$/s ? ($1 => $2) : die "gitlab.pl: --var is KEY=VALUE\n" } @{ $o{var} // [] };
            my $pl = $gl->trigger_pipeline(P(), $a[0], $a[1], variables => \%v);
            print $pl ? "pipeline $pl->{id} ($pl->{source}) $pl->{status}\n" : "no pipeline: no job matched\n";
        }
        else { usage('trigger') }
        return 0;
    }
    if ($cmd eq 'token') {
        my ($kind, $sub) = splice @a, 0, 2;
        usage('token') unless ($kind // '') eq 'deploy' && defined $sub;
        if ($sub eq 'new') {
            my %o = opts(\@a, 'scope=s@', 'expires=s');
            need(1, 'token deploy new needs a NAME', @a);
            my $dt = $gl->create_deploy_token(P(), $a[0], $o{scope} // ['read_repository'], expires_at => $o{expires});
            print "deploy token $dt->{id} $dt->{username}: $dt->{token}  scopes " . join(',', @{ $dt->{scopes} }) . ($dt->{expires_at} ? "  expires $dt->{expires_at}" : '') . "\n";
        }
        elsif ($sub eq 'list') { printf "%s  %s  %s  %s\n", $_->{id}, $_->{name}, join(',', @{ $_->{scopes} // [] }), $_->{expires_at} // 'never' for @{ $gl->deploy_tokens(P()) } }
        else { usage('token') }
        return 0;
    }
    if ($cmd eq 'pages') {
        my $pg = $gl->pages(P());
        if (!$pg || !($pg->{url} // $pg->{path})) { print "no Pages site yet (a `pages` job on the default branch publishes public/)\n"; return 1 }
        print "$pg->{url}\n" . ($pg->{path} ? "  $pg->{path}\n" : '');
        return 0;
    }
    if ($cmd eq 'schedule') {
        my $sub = shift @a // usage('schedule');
        @a = map { $_ eq '-n' ? '--n' : $_ } @a;
        my %o = opts(\@a, 'cron=s', 'ref=s', 'tz=s', 'var=s@', 'inactive', 'until=s', 'from=s', 'n=s');
        my %v = map { /^([A-Za-z_]\w*)=(.*)$/ ? ($1 => $2) : die "gitlab.pl: --var is KEY=VALUE\n" } @{ $o{var} // [] };
        if ($sub eq 'new') {
            need(1, 'schedule new needs a DESCRIPTION', @a);
            defined $o{cron} && defined $o{ref} or die "gitlab.pl: schedule new needs --cron \"MIN HOUR DOM MON DOW\" and --ref BRANCH\n";
            my $sc = $gl->create_schedule(P(), description => $a[0], ref => $o{ref}, cron => $o{cron}, cron_timezone => $o{tz} // 'UTC', active => $o{inactive} ? 0 : 1, variables => \%v);
            print "schedule " . ($sc->{id} // '?') . " $a[0]" . ($sc->{next_run_at} ? "  next run $sc->{next_run_at}" : '') . "\n";
        } elsif ($sub eq 'list') {
            for my $sc (@{ $gl->schedules(P()) }) {
                printf "%-5s %-26s %-16s %-18s %-10s next %-20s @%s%s\n", $sc->{id}, $sc->{description}, $sc->{cron}, $sc->{cron_timezone}, $sc->{ref},
                    $sc->{active} && !($sc->{active} =~ /^false$/) ? ($sc->{next_run_at} // '-') : '(inactive)', ($sc->{owner} // {})->{username} // '?',
                    $sc->{last_pipeline} ? "  last #$sc->{last_pipeline}{id} $sc->{last_pipeline}{status}" : '';
                print "      vars: " . join(' ', map { "$_->{key}=$_->{value}" } @{ $sc->{variables} }) . "\n" if @{ $sc->{variables} // [] };
            }
        } elsif ($sub eq 'run') {
            need(1, 'schedule run needs an ID', @a);
            my $pl = $gl->play_schedule(P(), $a[0]);
            print ref $pl && $pl->{id} ? "pipeline #$pl->{id} $pl->{status}\n" : "schedule $a[0] queued\n";
        } elsif ($sub eq 'delete') { need(1, 'schedule delete needs an ID', @a); $gl->delete_schedule(P(), $a[0]); print "schedule $a[0] deleted\n" }
        elsif ($sub eq 'due') {
            my $pls = $gl->run_due_schedules(P(), until => $o{until} // $gl->now);
            printf "%s  #%d %-8s %s (%s)\n", $_->{created_at}, $_->{id}, $_->{status}, $_->{ref}, $_->{schedule}{description} for @$pls;
            print scalar(@$pls) . " scheduled pipeline" . (@$pls == 1 ? '' : 's') . "\n";
            return (grep { $_->{status} eq 'failed' } @$pls) ? 1 : 0;
        } elsif ($sub eq 'next') { schedule_next(\@a, \%o, $gl->epoch) }
        else { usage('schedule') }
        return 0;
    }
    if ($cmd eq 'analytics') {
        my %o = opts(\@a, 'since=s', 'until=s', 'by=s', 'csv=s');
        my $A = $gl->analytics(P(), since => $o{since}, until => $o{until}, by => $o{by} // 'sprint');
        print GitLab::analytics_text($A);
        if (defined $o{csv}) { my $n = GitLab::analytics_csv($A, $o{csv}); print "\nCSV: " . join(', ', map { "$_ ($n->{$_})" } sort keys %$n) . " -> $o{csv}\n" }
        return 0;
    }
    if ($cmd eq 'board') {
        my $sub = shift @a // 'list';
        usage('board') unless $sub eq 'list';
        my $bs = $gl->boards(P());
        print "no issue boards (add a [boards] section to the project file and run setup)\n" unless @$bs;
        for my $bo (@$bs) {
            my @l = map { $_->{label}{name} } sort { ($a->{position} // 0) <=> ($b->{position} // 0) } grep { $_->{label} } @{ $bo->{lists} // [] };
            printf "%s  (milestone %s)\n  %s\n", $bo->{name}, GitLab::board_scope($bo->{milestone}), @l ? join(' | ', @l) : '(no lists)';
        }
        return 0;
    }
    if ($cmd eq 'windchill') {
        require Windchill;
        my $sub = shift @a // usage('windchill');
        my %o = opts(\@a, 'conf=s', 'note', 'csv=s', 'since=s');
        my $conf = $o{conf} // find_conf() // die "gitlab.pl: no project file: give --conf FILE (one with a [windchill] section) or run inside a repository with .gitlab/project.conf\n";
        my ($cfg, $path) = Windchill::config_file($conf);
        $G{project} //= $path;
        if ($sub eq 'intake') {
            need(1, 'windchill intake needs the exported CSV FILE', @a);
            my $s = Windchill::intake($gl, P(), $a[0], $cfg, note => $o{note});
            binmode STDOUT, ':encoding(UTF-8)';
            print "$_\n" for @{ $s->{lines} };
            return 0;
        }
        if ($sub eq 'status') {
            my $rows = Windchill::status($gl, P(), $cfg, since => $o{since});
            if (defined $o{csv}) {
                my $csv = Windchill::status_csv($rows);
                if ($o{csv} eq '-') { binmode STDOUT, ':raw:encoding(UTF-8)'; print $csv }
                else { open my $fh, '>:raw:encoding(UTF-8)', $o{csv} or die "gitlab.pl: cannot write $o{csv}: $!\n"; print $fh "\x{FEFF}$csv"; close $fh;
                       print scalar(@$rows) . ' Windchill request' . (@$rows == 1 ? '' : 's') . " -> $o{csv}\n" }
            } else { binmode STDOUT, ':encoding(UTF-8)'; print Windchill::status_text($rows) }
            return 0;
        }
        usage('windchill');
    }
    if ($cmd eq 'env') {
        my $sub = shift @a // 'list';
        if ($sub eq 'list') { printf "%-14s %-10s %s%s\n", $_->{name}, $_->{state} // '', $_->{external_url} // '', $_->{last_deployment} ? "  (last: $_->{last_deployment}{ref} " . substr($_->{last_deployment}{sha} // '', 0, 8) . ")" : '' for @{ $gl->environments(P()) } }
        elsif ($sub eq 'deployments') { printf "#%-4d %-12s %-20s %s %s\n", $_->{iid}, $_->{environment}{name}, $_->{ref}, substr($_->{sha} // '', 0, 8), $_->{created_at} // '' for @{ $gl->deployments(P(), environment => $a[0]) } }
        else { usage('env') }
        return 0;
    }
    if ($cmd eq 'flow') { die "gitlab.pl: flow pushes to the repository; --dry-run does not apply to it\n" if $G{'dry-run'}; return flow(@a) }
    usage();
}

sub print_widgets {                           # GitLab's MR widgets, as text
    my $w = shift;
    if (my $j = $w->{junit}) { printf "  tests: %d total, %d failed, %d skipped\n", @$j{qw(total failed skipped)}; print "    failed: $_\n" for @{ $j->{failures} } }
    if (my $c = $w->{codequality}) {
        printf "  code quality: %d finding%s, %d new, %d resolved\n", $c->{total}, $c->{total} == 1 ? '' : 's', scalar @{ $c->{new} }, scalar @{ $c->{resolved} };
        printf "    new %s: %s (%s:%s)\n", $_->{severity}, $_->{description}, $_->{path}, $_->{line} for @{ $c->{new} };
    }
    if (my $m = $w->{metrics}) {
        print "  metrics:\n";
        printf "    %-28s %s%s\n", $_->{name}, $_->{value}, defined $_->{previous} && $_->{previous} ne $_->{value} ? " (was $_->{previous})" : !defined $_->{previous} ? ' (new)' : '' for @$m;
    }
}

sub allowance_line { my ($r, $ver) = @_;
    $r->{raised} ? ".ci/outline-max: $r->{old} -> $r->{new} (drop $ver brings $r->{count} outline violations; its own commit)\n"
                 : ".ci/outline-max stays $r->{old} (drop $ver: $r->{count} outline violations)\n" }

sub flow {
    my ($sub, @a) = @_;
    defined $sub or usage('flow');
    my ($top, $rc) = GitLab::_run(undef, {}, 'git', 'rev-parse', '--show-toplevel');
    die "gitlab.pl: flow runs inside a clone of the project (no git repository here)\n" if $rc;
    chomp $top;
    my $cfg = sub { my ($o) = GitLab::_run($top, {}, 'git', 'config', $_[0]); chomp $o; $o };
    my $user = $G{as} // $ENV{GITLAB_USER} // $ENV{USER} // $ENV{USERNAME} // 'me';
    my $f = GitFlow->new(dir => $top, gl => $gl, project => P(), user => $user, name => ($cfg->('user.name') || ucfirst $user), email => ($cfg->('user.email') || "$user\@example.invalid"));
    my %o = opts(\@a, q(title=s), q(template=s), q(description=s), q(label=s@), q(milestone=s), q(reviewer=s@), q(notes=s), q(tag=s), q(layout-map=s));
    if ($sub eq 'init') { $f->init; print "develop is ready (from main)\n"; return 0 }
    if ($sub eq 'start') { need(2, 'flow start needs feature|release|hotfix and a NAME', @a); print "on " . $f->start($a[0], $a[1]) . "\n"; return 0 }
    if ($sub eq 'publish') { print "pushed " . $f->publish . "\n"; return 0 }
    if ($sub eq 'finish') {
        my $m = $f->finish(title => $o{title}, description => $o{description} // template($o{template}, 'merge_request'), labels => $o{label}, milestone => $o{milestone}, reviewers => $o{reviewer});
        print "!$m->{iid} $m->{source_branch} -> $m->{target_branch}: $m->{title}\n";
        print "pipeline #$m->{head_pipeline}{id} $m->{head_pipeline}{status}\n" if $m->{head_pipeline};
        return 0;
    }
    if ($sub eq 'released') {
        need(1, 'flow released needs the merged release MR IID', @a);
        my $r = $f->after_release($a[0], notes => defined $o{notes} ? slurp($o{notes}) : undef, tag => $o{tag});
        print "tag $r->{tag}{name} (sha256=$r->{sha256}), release, back-merge !$r->{mr}{iid}\n";
        return 0;
    }
    if ($sub eq 'vendor') {
        need(2, 'flow vendor needs DROPDIR and VERSION', @a);
        # the layout map: --layout-map FILE, else the repository's own .ci/layout.map, read now (from the branch you are
        # on) because vendor_import checks out vendor/prime before it converts
        my $mapf = $o{'layout-map'} // (-f "$top/.ci/layout.map" ? "$top/.ci/layout.map" : undef);
        my $map;
        if (defined $mapf) { require File::Temp; my ($fh, $tmp) = File::Temp::tempfile(UNLINK => 1); print $fh slurp($mapf); close $fh; $map = $tmp }
        my $r = $f->vendor_import(drop => $a[0], version => $a[1], convert => GitFlow::default_convert($KIT, layout_map => $map));
        print "vendor/prime: imported $a[1]; on $r->{branch}: " . ($r->{merged} ? "merged cleanly\n" : "conflicts:\n" . join('', map { "  $_\n" } @{ $r->{conflicts} }));
        print allowance_line($r->{outline}, $a[1]) if $r->{outline};
        print "resolve, commit, then: gitlab.pl flow allowance $a[1]\n" if !$r->{merged} && -f "$top/.ci/outline-max";
        return $r->{merged} ? 0 : 1;
    }
    if ($sub eq 'allowance') {
        need(1, 'flow allowance needs the drop VERSION', @a);
        my $r = $f->record_outline_allowance($a[0]);
        print $r ? allowance_line($r, $a[0]) : "no .ci/outline-max in this repository: no outline ratchet to update\n";
        return 0;
    }
    if ($sub eq 'take') { need(2, 'flow take needs ours|theirs and PATH...', @a); $f->take(@a); print "resolved: @a[1..$#a]\n"; return 0 }
    if ($sub eq 'sync') { $f->sync; print "main and develop are up to date\n"; return 0 }
    usage('flow');
}
