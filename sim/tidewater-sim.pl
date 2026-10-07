#!/usr/bin/perl
# sim/tidewater-sim.pl -- the Tidewater MBSE DevSecOps simulation: three government systems engineers (Jim, Bob, Tom)
# port the prime's SysML v1 model to SysML v2 text in GitLab, then keep it current with the prime's drops, for 39
# two-week sprints (18 months from Monday 2026-10-05). Everything happens for real, through the kit's own tools:
#
#   - GitLab is lib/GitLab.pm's local emulator (data/tidewater/gitlab): users, the project set up from
#     tools/gitlab/templates/project.conf, issues and quick actions, merge requests, code-owner approvals, protected
#     branches (a real pre-receive hook), pipelines run by lib/GitLabCI.pm on the merged result, schedules, Pages,
#     releases, the package registry.
#   - Each person works in their own clone through lib/GitFlow.pm (feature branches, the vendor branch for the prime's
#     drops, release branches); the model edits are sim/tidewater-model.pl's, the drops sim/tidewater-v1.pl's.
#   - The team's journal (data/tidewater/journal) is a kit project compiled through Standup.pm/Scrum.pm: stories with
#     points, stand-ups from pasted Teams chat (Answers.pm lint and answers), planning poker (Chat.pm #est rounds),
#     the weekly quad, the sprint report.
#   - Every sprint leaves its evidence in data/tidewater/sprints/NN/ (plans, chat, lint, pipeline logs, the real
#     Markdown of issues, MRs, reviews and releases, scorecard.json, morale.json); sprints 1-6 go to
#     docs/tidewater/ for the book through sim/tidewater-evidence.pl (or --docs-dir DIR here), and docs/TIDEWATER.html summarizes the whole run (sim/tidewater-render.pl).
#
#   perl sim/tidewater-sim.pl [--dir data/tidewater] [--sprints N] [--work DIR] [--docs-dir DOCS] [--quiet] [--force]
#   (docs are written only with --docs-dir; --no-docs is kept for old command lines and does nothing else)
#
# Deterministic: the emulator's clock is frozen and moved by the simulation; pipeline job times come from a model of
# the team's Windows runner, not the wall clock; no randomness. Fictional, civilian and notional throughout. Runs on
# a Linux filesystem (WSL: --work defaults to a temp dir there and the result is copied to --dir at the end).
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Getopt::Long;
use File::Path qw(make_path remove_tree);
use File::Copy qw(copy);
use File::Temp qw(tempdir);
use Cwd qw(abs_path getcwd);
use Digest::MD5 qw(md5_hex);
use Digest::SHA ();
use POSIX qw(floor ceil strftime);
use Time::Local qw(timegm);
use JSON::PP ();
use File::Find ();
use GitLab;
use GitFlow;
use GitLabCI ();
use Standup qw(parse_standup apply);
use Scrum qw(load sprint_summary);
use Answers ();
use Chat ();

my $ROOT = abs_path("$FindBin::Bin/..");
require "$ROOT/sim/tidewater-model.pl";
require "$ROOT/sim/tidewater-plan.pl";
our (%TW_EPIC, %TW_TOME, %TW_EPIC_LABEL, %TW_TOME_LABEL);
{ local $ENV{KIT} = $ROOT; require "$ROOT/tools/gitlab/templates/ci/job.pl"; }   # CIJob::complexity_of, for the scorecard

my %o = (dir => "$ROOT/data/tidewater", sprints => 39);
GetOptions(\%o, 'dir=s', 'sprints=i', 'work=s', 'no-docs', 'quiet', 'force', 'docs-dir=s') or die "usage: tidewater-sim.pl [--dir D] [--sprints N] [--work DIR] [--no-docs] [--quiet]\n";
$o{dir} =~ m{(^|/)data/tidewater/?$} || $o{force} or die "--dir must end in data/tidewater (it is wiped and rebuilt), or pass --force\n";
$o{sprints} >= 1 && $o{sprints} <= 39 or die "--sprints is 1 to 39\n";
my $DOCS = $o{'docs-dir'} // "$ROOT/docs";
my $W = $o{work} // ($o{dir} =~ m{^/mnt/} ? tempdir('tidewater-XXXXXX', TMPDIR => 1, CLEANUP => 1) : $o{dir});
remove_tree($W) if -d $W && $W eq $o{dir};
make_path($W);
$W = abs_path($W);
my $P = 'tidewater/model';
my $REQ = 'tidewater/requests';                                     # the intake project: Windchill requests (the front door)
my $JSON = JSON::PP->new->canonical(1)->pretty;
sub say_ { print @_, "\n" unless $o{quiet} }
sub slurp { my $f = shift; open my $fh, '<:raw', $f or return undef; local $/; my $t = <$fh>; close $fh; $t }
sub spew { my ($f, $t) = @_; (my $d = $f) =~ s{/[^/]+$}{}; make_path($d) if $d ne $f; open my $fh, '>:raw', $f or die "cannot write $f: $!\n"; print $fh $t; close $fh }
sub run_q {                                    # (output, exit) of a command, stdout only; its stderr is kept in $W/stderr.log
    my ($dir, @cmd) = @_;
    my $cwd = getcwd; chdir $dir if $dir;
    open my $save, '>&', \*STDERR; open STDERR, '>>', "$W/stderr.log";
    my $o = ''; if (open my $fh, '-|', @cmd) { local $/; $o = <$fh> // ''; close $fh } my $rc = $? >> 8;
    open STDERR, '>&', $save;
    chdir $cwd; ($o, $rc)
}
sub run_par {                                  # several commands at once -> their outputs, in order (stderr to $W/stderr.log)
    my (@cmds) = @_;
    open my $save, q{>&}, \*STDERR; open STDERR, q{>>}, "$W/stderr.log";
    my @fh = map { my $fh; open($fh, q{-|}, @$_) ? $fh : undef } @cmds;     # all started before any is read
    open STDERR, q{>&}, $save;
    map { my $fh = $_; my $o = q{}; if ($fh) { local $/; $o = <$fh> // q{}; close $fh } $o } @fh;
}
sub rel { my $t = shift // ''; $t =~ s/\Q$W\E/data\/tidewater/g; $t =~ s/\Q$ROOT\E/\$KIT/g; $t =~ s{/tmp/[\w./-]*?/(pl-\w+)}{/builds/tidewater/model}g;
    $t =~ s{/tmp/ci-model-\w+}{model (without the DOORS modules)}g; $t =~ s{/tmp/(gitlab-ci|ci-trace|ci-cx)-\w+}{/tmp/$1}g; $t }

# ======================================================================== calendar
my $START = '2026-10-05';
my %HOLIDAY = map { $_ => 1 } qw(2026-10-12 2026-11-11 2026-11-26 2026-12-25 2027-01-01 2027-01-18 2027-02-15 2027-05-31 2027-06-18 2027-07-05
                                 2027-09-06 2027-10-11 2027-11-11 2027-11-25 2027-12-24 2027-12-31 2028-01-17 2028-02-21);
my %PTO = ('2026-11-27' => ['jim'], (map { ($_ => ['bob']) } qw(2026-12-21 2026-12-22 2026-12-23 2026-12-24)),
           (map { ($_ => ['tom']) } qw(2027-02-08 2027-02-09 2027-02-10)), (map { ($_ => ['jim']) } qw(2027-07-06 2027-07-07)),
           (map { ($_ => ['bob']) } qw(2027-08-16 2027-08-17 2027-08-18 2027-08-19 2027-08-20)), (map { ($_ => ['tom']) } qw(2027-12-27 2027-12-28 2027-12-29 2027-12-30)));
sub ep { my ($y, $m, $d) = split /-/, shift; timegm(0, 0, 12, $d, $m - 1, $y) }
sub ymd { strftime('%Y-%m-%d', gmtime shift) }
sub add_days { ymd(ep($_[0]) + 86400 * $_[1]) }
sub dow { (gmtime ep(shift))[6] }
sub sprint_start { add_days($START, 14 * ($_[0] - 1)) }
sub sprint_days { my $n = shift; my $s = sprint_start($n); grep { my $w = dow($_); $w >= 1 && $w <= 5 && !$HOLIDAY{$_} } map { add_days($s, $_) } 0 .. 11 }
sub working { my ($who, $d) = @_; !grep { $_ eq $who } @{ $PTO{$d} // [] } }
sub hm { my ($d, $h, $m) = @_; strftime('%Y-%m-%dT%H:%M:00Z', gmtime(ep($d) - 12 * 3600 + ($h + 5) * 3600 + ($m // 0) * 60)) }   # local Eastern time, stored UTC (EST: +5)

# ======================================================================== people
our $TODO_NOW = 0;
our %DRTEXT;
my %PEOPLE = (jim => { name => 'Jim', cap => 5, role => 'MBSE lead (government): owns the model, approves' },
              bob => { name => 'Bob', cap => 8, role => 'MBSE engineer (government)' },
              tom => { name => 'Tom', cap => 8, role => 'DevSecOps and configuration management engineer (government); security owner' });
my @TEAM = qw(jim bob tom);
my %K = (jim => 2.0, bob => 1.25, tom => 1.25);                      # calendar days per point: the rest is meetings and support

# ======================================================================== the emulator and the clones
my %JOBSEC = (grammar => 41, lint => 46, outline => 14, todo => 7, secrets => 9, complexity => 19, trace => 24, vcrm => 13, docs => 33,
              delta => 27, 'drop-package' => 16, intake => 35, baseline => 58, 'publish-package' => 22, 'publish-release' => 11, pages => 81, status => 21);
sub jobsec { my ($name, $tree) = @_; my $b = $JOBSEC{$name} // 15; my $j = hex(substr(md5_hex("$name $tree"), 0, 4)) / 65535; $b * (0.85 + 0.3 * $j) }
my $gl = GitLab->new(local => "$W/gitlab", now => '2026-09-28T13:00:00Z', freeze => 1, job_seconds => \&jobsec, parallel => $ENV{TW_PARALLEL} // 4, url_base => 'https://gitlab.gov.example.invalid');
my %PROF;                                                             # TW_PROFILE=1: where the run's wall time goes (stderr at the end)
if ($ENV{TW_PROFILE}) {
    require Time::HiRes;
    no strict 'refs'; no warnings 'redefine';
    for my $s (qw(GitLab::run_pipeline GitLab::save GitLab::merge_mr GitLab::create_mr GitLab::pushed GitLab::run_due_schedules GitLab::analytics
                  GitLab::export GitFlow::git GitFlow::vendor_import GitLabCI::run main::run_q main::export_develop main::vcover main::scorecard)) {
        my $orig = \&{$s} or next;
        *{$s} = sub { my $t = Time::HiRes::time(); my @r = wantarray ? $orig->(@_) : scalar $orig->(@_); $PROF{$s}{n}++; $PROF{$s}{t} += Time::HiRes::time() - $t; wantarray ? @r : $r[0] };
    }
    END { printf STDERR "%-28s %6d calls %8.1f s\n", $_, $PROF{$_}{n}, $PROF{$_}{t} for sort { $PROF{$b}{t} <=> $PROF{$a}{t} } keys %PROF }
}
my %F;                                                                # login -> GitFlow clone
sub at_ { my ($d, $h, $m) = @_; $gl->clock(hm($d, $h, $m // 0)) }
sub flow {
    my $u = shift;
    return $F{$u} if $F{$u};
    my $f = GitFlow->new(dir => "$W/work/$u", gl => $gl, project => $P, user => $u, name => $PEOPLE{$u}{name}, email => "$u\@example.invalid");
    $f->clone;
    $f->git('config', 'merge.conflictstyle', 'diff3');
    $f->git('config', 'pull.ff', 'only');
    $F{$u} = $f;
}

# ======================================================================== the pipeline, as it grew (levels of the template)
my $TEMPLATE = slurp("$ROOT/tools/gitlab/templates/gitlab-ci.yml");
my %LEVEL_JOBS = (1 => [qw(grammar lint outline)], 2 => [qw(grammar lint outline todo docs)], 3 => [qw(grammar lint outline todo secrets trace docs)],
                  4 => [qw(grammar lint outline todo secrets trace docs pages)], 5 => [qw(grammar lint outline todo secrets trace recipe docs pages)],
                  6 => [qw(grammar lint outline todo secrets trace vcrm recipe docs baseline publish-release pages)],
                  7 => [qw(grammar lint outline todo secrets complexity trace vcrm recipe docs delta drop-package baseline publish-release pages status)],
                  8 => [qw(grammar lint outline todo secrets complexity trace vcrm recipe docs delta drop-package intake baseline publish-release pages status)],
                  9 => 'all');
sub ci_yaml {                                  # the model repo's .gitlab-ci.yml at a level: the template, cut to the jobs adopted so far
    my $lv = shift;
    my $want = $LEVEL_JOBS{$lv};
    return $TEMPLATE if !ref $want;
    my %keep = map { $_ => 1 } @$want;
    my @parts = split /(?=^# [A-Z][A-Z\/ -]+ -- )/m, $TEMPLATE;
    my $out = '';
    for my $p (@parts) {
        my ($job) = $p =~ /^([a-z][\w-]*):\n/m;
        if ($p =~ /^# [A-Z]/ && $job && $p =~ /^\Q$job\E:\n/m && $job !~ /^\./) {
            next unless $keep{$job};
            if ($job eq 'trace' && $lv < 5) { $p =~ s/(  script:\n)/  variables:\n    TRACE_MODE: report      # sprint 3: the trace reports gaps, never fails (the ratchet comes in sprint 5)\n  allow_failure: true\n$1/ }
            if ($job eq 'publish-release') { $p =~ s/    - publish-package\n//; $p =~ s/    milestones:\n.*?\z/\n/s }
            if ($job eq 'baseline') { $p =~ s/    reports:\n      dotenv:[^\n]*\n//s }
            if ($job eq 'pages' && $lv < 6) { $p =~ s/  environment:\n    name: model-site\n    url: \$CI_PAGES_URL\n// }
        }
        $out .= $p;
    }
    $out =~ s/^include:\n.*?\n\n//ms if $lv < 3;                     # the Secret-Detection include came with the secrets job
    $out;
}
my $SH_DRAFT = <<'YAML';
# .gitlab-ci.yml -- first draft (sprint 1): the three checks, written the way the tutorials write them (sh syntax)
stages:
  - check

variables:
  GIT_DEPTH: "0"

grammar:
  stage: check
  script:
    - FILES=$(find model -name '*.sysml' | sort)
    - perl "$KIT/tools/sysml/sysml.pl" check $FILES

lint:
  stage: check
  script:
    - perl "$KIT/tools/sysml/model.pl" lint > lint.txt || true
    - tail -1 lint.txt | grep -q ' errors=0 warnings=0$'

outline:
  stage: check
  script:
    - perl "$KIT/tools/sysml/model.pl" check
YAML

# ======================================================================== evidence
my %EV;                                                               # sprint -> list of [path, text]
sub ev { my ($n, $path, $text) = @_; spew(sprintf("$W/sprints/%02d/%s", $n, $path), rel($text)) }
my %DAYLOG;                                                           # date -> [ "HH:MM who: what" ]
sub logd { my ($d, $who, $what) = @_; my ($h, $m) = substr($gl->now, 11, 5) =~ /(\d\d):(\d\d)/; push @{ $DAYLOG{$d} }, sprintf('%02d:%s %-4s %s', $h - 5, $m, $who, $what) }

# ======================================================================== the journal (a kit project)
my $J = "$W/journal";
make_path("$J/standups", "$J/reports");
spew("$J/scrum.conf", <<"CONF");
# scrum.conf -- generated by sim/tidewater-sim.pl (Tidewater is notional). The journal's items are STORIES; tasks
# live in GitLab (one point = one ideal person-day).
journal   = scrum.txt
standups  = standups
reports   = reports
unit      = SP
default_team = Model
calendar  = mock
history_days = 5
readback_clean_days = 5
banner    =
CONF
spew("$J/roster.txt", "# name | email | team | role | org\n" . join('', map { "$PEOPLE{$_}{name} | $_\@example.invalid | Model | $PEOPLE{$_}{role} | Government\n" } @TEAM));
spew("$J/scrum.txt", "; generated by sim/tidewater-sim.pl -- Tidewater SysML v2 port, 39 sprints from $START (notional)\n");
my %SU;                                                               # date -> stand-up file lines
sub su { my ($d, $line) = @_; push @{ $SU{$d} }, $line }
my %MEET;                                                             # sprint -> [ [date, meeting, start, end, attendees] ] -> sprints/NN/meetings.csv
sub meet { my ($n, $d, $what, $from, $to, @who) = @_; push @{ $MEET{$n} }, [ $d, $what, $from, $to, join(q{; }, @who) ] }
sub team_on { my $d = shift; map { $PEOPLE{$_}{name} } grep { working($_, $d) } @TEAM }
sub compile_day {
    my ($d, $n) = @_;
    my $txt = "$d\nsprint $n\n== Model\n" . join('', map { "$_\n" } @{ $SU{$d} // [] });
    my $file = "$J/standups/$d.txt";
    spew($file, $txt);
    my $cwd = getcwd; chdir $J;                                         # relative paths: the journal names standups/DATE.txt, not this machine's
    my $su = parse_standup($txt, "standups/$d.txt");
    die "$d: " . join('; ', @{ $su->{errors} }) . "\n" if @{ $su->{errors} };
    my $s = load("scrum.txt", today => $d);
    $s->{unit} = 'SP';
    apply($s, $su, "scrum.txt");
    chdir $cwd;
}

# ======================================================================== issues, with the templates filled in
my (%ST, @STORIES);                                                    # story key -> runtime record
sub labels_for { my ($st, @more) = @_; my ($tome) = $TW_EPIC{ $st->{epic} }[0];
    ("epic::$TW_EPIC_LABEL{ $st->{epic} }", "tome::$TW_TOME_LABEL{$tome}", "work::$st->{work}", "area::$st->{area}", ($st->{phase} // ($st->{sprint} <= 20 ? 'phase::port' : 'phase::maintenance')), @more) }
sub story_body {
    my ($st) = @_;
    my $t = "## Why\n\n$st->{plan}{why}\n\n## What \"done\" looks like\n\n" . join('', map { "- [ ] $_\n" } @{ $st->{plan}{done} })
          . "- [ ] The pipeline is green on every MR of this story\n\n## Tasks\n\n| Task | Points | Who |\n|---|---|---|\n";
    $t .= "| #$_->{iid} $_->{t} | $_->{p} | \@$_->{who} |\n" for grep { $_->{iid} } @{ $st->{tasks} };
    $t .= "\n## Notes\n\nEpic $st->{epic} ($TW_EPIC{ $st->{epic} }[1]), tome " . $TW_EPIC{ $st->{epic} }[0] . " ($TW_TOME{ $TW_EPIC{ $st->{epic} }[0] }). Journal id **$st->{id}**.\n";
    $t;
}
sub new_story {                                                        # the story issue (refinement, or the S1 kickoff)
    my ($st, $n) = @_;
    $gl->as('jim');
    my $prio = $st->{plan}{prio} // 2;
    my $i = $gl->create_issue($P, title => $st->{plan}{title}, labels => [ 'type::story', "priority::$prio", labels_for($st) ],
                              milestone => "Sprint $n", assignees => [ $st->{plan}{owner} ], description => "## Why\n\n$st->{plan}{why}\n");
    $st->{iid} = $i->{iid};
    $st->{id} = "TW-$i->{iid}";
    $gl->update_issue($P, $i->{iid}, description => story_body($st), add_labels => ['workflow::ready']);
    $i;
}
sub new_tasks {                                                        # the task issues, cut at planning by the story's owner
    my ($st, $n) = @_;
    for my $tk (@{ $st->{tasks} }) {
        next if $tk->{iid};
        $gl->as($st->{plan}{owner});
        my $body = "Part of #$st->{iid}\n\n## Do\n\n- [ ] $tk->{t}\n- [ ] Run `gitlab.pl ci` locally before pushing\n\n## Done when\n\n"
                 . ($tk->{act}[0] =~ /^(model_mr|vendor|drop_merge|ci_level|ci_first)$/ ? "The MR is merged with a green pipeline.\n" : "The result is recorded in a comment on this issue.\n")
                 . "\n/estimate $tk->{p}d\n/relate #$st->{iid}\n";
        my $i = $gl->create_issue($P, title => $tk->{t}, labels => [ 'type::task', "area::$st->{plan}{area}", "work::$st->{plan}{work}", 'workflow::ready' ],
                                  milestone => "Sprint $n", assignees => [ $tk->{who} ], issue_type => 'task', description => $body);
        $tk->{iid} = $i->{iid};
    }
    $gl->as('jim');
    $gl->update_issue($P, $st->{iid}, description => story_body($st));
}

# ======================================================================== chat: stand-ups and planning poker, through the kit
sub chat_paste { my (@m) = @_; "Meeting started\n" . join('', map { my ($t, $who, $text) = @$_; "[$t] $who\n$text\n" } @m) }
sub clock12 { my ($h, $m) = @_; sprintf '%d:%02d %s', ($h % 12) || 12, $m, $h < 12 ? 'AM' : 'PM' }
sub poker {                                                            # #est rounds in the chat -> Chat.pm tallies -> est values
    my ($d, $n, $what, @stories) = @_;
    my @m = ([clock12(10, 0), 'Jim', "$what. Planning poker: one number per story, in points."]);
    my $min = 1;
    for my $st (@stories) {
        my @rounds = @{ $st->{plan}{votes} };
        @rounds = ([ ($st->{pts}) x 3 ]) unless @rounds;
        $rounds[-1] = [ ($st->{pts}) x 3 ];                            # the last round is the consensus: the story's points
        for my $r (0 .. $#rounds) {
            push @m, [clock12(10, $min++), 'Jim', "#est $st->{id} $st->{plan}{title}"];
            my @v = @{ $rounds[$r] };
            push @m, map { [clock12(10, $min), $PEOPLE{ $TEAM[$_] }{name}, $v[$_]] } grep { working($TEAM[$_], $d) } 0 .. 2;   # only who is at work votes
            @v = @v[ grep { working($TEAM[$_], $d) } 0 .. 2 ];
            if ($r < $#rounds) { my ($lo, $hi) = (sort { $a <=> $b } @v)[0, -1]; push @m, [clock12(10, $min), 'Jim', "$lo to $hi. Talk it out: what does the high vote know?"] }
            $min++;
        }
    }
    my $chat = chat_paste(@m);
    my @t = map { Chat::tally($_) } Chat::rounds(Chat::parse_chat($chat));
    my $txt = join("\n", map { Chat::tally_text($_) } @t);
    spew("$J/standups/$d-poker-chat.txt", $chat);
    ev($n, "poker-$d.txt", "$chat\n---- Chat.pm tallies\n$txt\n");
    \@t;
}
our %DRAFTS;
our %OUTCOME;
my %LINT_PLANT = ('2026-10-06' => { bob => "yesterday the kickoff, then the practice repo\ntoday practice lesson 10\nno blockers" },
                  '2026-10-07' => { tom => "Y: TW-%s draft pipeline\nT: TW-%s runner, still waiting" },
                  '2026-10-14' => { jim => "y: TW-%s drop issue t: TW-%s wiki b: none and t-shirt sizes later" },
                  '2026-10-20' => { bob => "Y TW-%s T TW-%s" });
sub standup {                                                          # the 09:00 stand-up: terse Y/T/B in chat -> lint -> answers file
    my ($d, $n, $yesterday) = @_;
    at_($d, 9, 0);
    my @m = ([clock12(9, 0), 'Jim', 'Morning. Y/T/B in chat, please.']);
    my $min = 1;
    my %ids = map { $_->{id} => 1 } grep { $_->{id} } @STORIES;
    my %TALK;                                                          # from sprint 3: talk.pl drafts, the three in parallel
    if ($n >= 3) {
        $gl->save;
        my @who = grep { working($_, $d) } @TEAM;
        my @out = run_par(map { [ $^X, "$ROOT/tools/gitlab/talk.pl", q{--local}, "$W/gitlab", q{--project}, $P, q{standup}, q{--as}, $_, q{--date}, $d, q{--journal}, $J, q{--prefix}, q{TW-} ] } @who);
        @TALK{@who} = @out;
    }
    for my $u (@TEAM) {
        next unless working($u, $d);
        my $act = sub { my $day = shift; return () unless $day; my @a = grep { $_->{who} eq $u && $_->{start_d} le $day && $_->{end_d} ge $day } map { @{ $_->{tasks} } } @STORIES; @a };
        my @y = $act->($yesterday);
        my @t = $act->($d);
        my $fmt = sub {                                                # S1-S2: the jargon of a new team; from S3: outcome first, one number
            my ($when, @a) = @_;
            return 'meetings, reviews' unless @a;
            join('; ', map { my $tk = $_;
                if ($n <= 2) { "$tk->{story}{id} " . _short($tk->{t}) }
                elsif ($when eq 'y' && $tk->{done} && $tk->{mr}) { "merged !$tk->{mr}, " . _short($tk->{t}) . " ($tk->{story}{id}); $TODO_NOW TODO lines left" }
                elsif ($when eq 'y' && $tk->{done}) { 'done: ' . _short($tk->{t}) . " ($tk->{story}{id})" }
                else { _short($tk->{t}) . " ($tk->{story}{id})" . ($tk->{end_d} eq $d ? ', MR today' : '') }
            } @a);
        };
        my ($blk) = map { "$_->{story}{id} $_->{blocked_why}" } grep { $_->{blocked_from} && ($_->{blocked_posted} // $_->{blocked_from}) le $d && ($_->{blocked_to} // '9') ge $d } @t;
        my $text = "Y: " . $fmt->('y', @y) . "\nT: " . $fmt->('t', @t) . "\nB: " . ($blk // 'none');
        if ($n >= 3) {                                                  # from sprint 3: talk.pl drafts, the person edits and posts
            my $dr = $TALK{$u} // q{};
            my ($line) = grep { /^Y / } split /\n/, $dr;
            if ($line) {
                (my $posted = $line) =~ s/\.\.\.([,:])/$1/g;                    # the edit: drop the ellipses talk.pl leaves on long titles
                my %pair = (jim => 'Bob', bob => 'Tom', tom => 'Jim');     # and, on some days, what only the person knows
                if (hex(substr(md5_hex("$d $u"), 0, 1)) < 5) { $posted =~ s/\.?\s+B\s/; pairing with $pair{$u} after lunch. B / }
                elsif (hex(substr(md5_hex("$d $u"), 1, 1)) < 3) { $posted =~ s/\s+T\s+(TW-\d+)\s/ T $1 (first thing: read the review comments) / }
                if ($posted =~ /\bT none\b/) {                              # the board has nothing left for them: they say what the day holds
                    my $last = (sprint_days($n))[-1];
                    $posted =~ s/\bT none\b/$d eq $last ? "T the sprint $n review: demo ready by 10 am." : "T review the open MRs, then the sprint $n demo, by the review."/e }
                if ($blk && $posted =~ /\bB none\b/) { $posted =~ s/\bB none\b/B $blk -- need: a date from the ISSM/ }   # the draft knows only yesterday's labels: the person says it the day it surfaces
                elsif ($blk && $posted !~ /ask|need:/i) { $posted .= ' (ask: a date from the ISSM)' }
                push @{ $DRAFTS{$d} }, "$u draft:  $line\n$u posted: $posted\n";
                $text = $posted;
            }
        }
        if (my $pl = $LINT_PLANT{$d}{$u}) { my @i = (map { $_->{story}{id} =~ /(\d+)/ } @y, @t); my $k = () = $pl =~ /%s/g; $text = $k ? sprintf($pl, (($i[0] // 1), ($i[1] // $i[0] // 1))[0 .. $k - 1]) : $pl }
        push @m, [clock12(9, $min++), $PEOPLE{$u}{name}, $text];
    }
    for my $mm (@m[1 .. $#m]) { my $tx = $mm->[2]; my $o = ($tx =~ /\d/ && $tx =~ /\b(merged|done|closed|left|down|up|green|passed|ready|by)\b/i) ? 1 : 0; $OUTCOME{$n}{lines}++; $OUTCOME{$n}{good} += $o }
    my $chat = chat_paste(@m);
    my $cf = "$J/standups/$d-Model-chat.txt";
    spew($cf, $chat);
    my @lint = grep { $_->{who} ne 'Jim' || $_->{ok} } Answers::lint_chat($chat, known => \%ids, example => 'TW-1');
    my $lt = Answers::lint_text("standups/$d-Model-chat.txt", @lint);
    spew("$J/standups/$d-lint.txt", $lt);
    my @ans = grep { $_->{y} || $_->{t} } Answers::parse_answers($chat, guess => 1);
    spew("$J/standups/$d-Model-answers.txt", Answers::answers_text($d, 'Model', @ans));
    ($chat, $lt);
}
sub _short { my $t = shift; $t =~ s/^(Write|Add|Run|Open|Log|Move|Draft|Commit|Apply|Prove|Request|Follow up|Check|Turn on|Import|Review and merge|Remove|Rehearse|Enter and sign|Generate|Document|Release branch,)\s+(the\s+)?//i;
    $t = substr($t, 0, 46); $t =~ s/\s+\S*$// if length($t) == 46; $t =~ /^[A-Z][A-Z0-9]/ ? $t : lcfirst $t }   # keep acronyms (CDRL, TODO, CODEOWNERS)

# ======================================================================== model work: commits, MRs, reviews, merges
sub reviewer_for {                                                     # who must approve: the approval rule (Jim or Bob) and, for every
    my ($author, @files) = @_;                                         # CODEOWNERS section a changed file falls in, an owner who is not the author
    my %pref = (jim => 0, bob => 1, tom => 2);
    my %need = (($author eq 'jim' ? 'bob' : 'jim') => 1);                # "Model review = 1 jim bob"
    my $co = slurp("$W/work/$author/CODEOWNERS") // '';
    my ($sec, $def, $opt, @rules) = ('', [], 0);
    for my $l (split /\n/, $co) {
        $l =~ s/(^|\s)#.*$//; next unless $l =~ /\S/;
        if ($l =~ /^\s*(\^?)\[([^\]]+)\](?:\[\d+\])?\s*(.*)$/) { ($opt, $sec, $def) = ($1 ? 1 : 0, $2, [ map { s/^@//r } split ' ', $3 ]); next }
        my ($pat, @own) = split ' ', $l;
        push @rules, { sec => $sec, re => GitLab::_owner_re($pat), own => (@own ? [ map { s/^@//r } @own ] : $def), opt => $opt };
    }
    for my $f (@files) {
        my %last; for my $r (@rules) { $last{ $r->{sec} } = $r if $f =~ $r->{re} }
        for my $r (map { $last{$_} } sort keys %last) {
            next if $r->{opt};
            my @ok = sort { ($pref{$a} // 9) <=> ($pref{$b} // 9) } grep { $_ ne $author } @{ $r->{own} };
            next if grep { $need{$_} } @ok;
            $need{ $ok[0] } = 1 if @ok;
        }
    }
    sort { $pref{$a} <=> $pref{$b} } keys %need;
}
sub regen {                                                             # docs and the outline count, as the author does before pushing
    my ($f, %o) = @_;
    my $c = $f->dir;
    return unless -f "$c/sysml.conf" && -d "$c/model";
    run_q($c, $^X, "$ROOT/tools/sysml/model.pl", 'docs') if $o{docs} // (-d "$c/docs");
    my ($out) = run_q($c, $^X, "$ROOT/tools/sysml/model.pl", 'check');
    my ($v) = $out =~ /^violations\s+(\d+)/m; my ($mm) = $out =~ /^\@L tag mismatches\s+(\d+)/m;
    my $nv = ($v // 0) + ($mm // 0);
    my $cur = (slurp("$c/.ci/outline-max") // '0') =~ /(\d+)/ ? $1 : 0;
    spew("$c/.ci/outline-max", "$nv\n") if $nv < $cur || $o{raise};
    $nv;
}
my %APPLIED;                                                            # the government edits made so far: re-applied after a vendor merge
sub mr_text {
    my (%a) = @_;
    my $t = "## What and why\n\n$a{why}\n\n" . join('', map { "Closes #$_\n" } @{ $a{closes} // [] }) . ($a{story} ? "Part of #$a{story}\n" : '') . "\n";
    $t .= "## Model changes\n\n| Package | Change |\n|---|---|\n" . join('', map { "| `$_` | changed |\n" } @{ $a{files} // [] }) . "\n" if @{ $a{files} // [] };
    my $ci = $a{ci_local} // ($::CI_LEVEL >= 1 && !$a{plant});             # ticked only when true: no pipeline yet, or not run before pushing
    my $docs = $a{docs} // ($::CI_LEVEL >= 1);
    my $box = sub { $_[0] ? '[x]' : '[ ]' };
    my $trace = $::CI_LEVEL >= 3 && ($a{plant} // '') ne 'ratchet';
    $t .= "## Checks\n\n- " . $box->($ci) . " `gitlab.pl ci` passed locally" . ($::CI_LEVEL < 1 ? ' (no pipeline in the project yet)' : $ci ? '' : ' (not run before pushing)') . "\n"
        . "- " . $box->($docs) . " `docs/` regenerated and committed" . ($docs ? '' : ' (no docs job yet)') . "\n"
        . "- " . $box->(!$a{adds_todo}) . " No new `// TODO` lines" . ($a{adds_todo} ? ' (a prime drop: its TODO lines are the port backlog)' : '') . "\n"
        . "- " . $box->($trace) . " Trace job: no new orphan, unverified or drifted requirement" . ($::CI_LEVEL < 3 ? ' (no trace job yet)' : $trace ? '' : ' (not checked: the satisfy looked like a duplicate)') . "\n";
    $t .= "\n## Review notes\n\n$a{notes}\n" if $a{notes};
    $t;
}
sub pipeline_of { my $m = shift; my $hp = ($gl->mr($P, $m->{iid}) // {})->{head_pipeline}; $hp ? $gl->pipeline($P, $hp->{id}) : undef }
sub keep_log {                                                         # a pipeline's job logs into the evidence
    my ($n, $pl, $tag) = @_;
    return unless $pl;
    my $txt = "pipeline #$pl->{id} ($pl->{source}, $pl->{ref}) $pl->{status}, " . scalar(@{ $pl->{jobs} }) . " jobs, $pl->{duration} s\n";
    for my $j (@{ $pl->{jobs} }) {
        $txt .= sprintf "\n==== %-16s %-8s %-8s %5s s\n", $j->{name}, $j->{stage}, $j->{status} . ($j->{allow_failure} ? ' (allowed)' : ''), $j->{duration} // '-';
        my $log = $j->{log} && -f $j->{log} ? slurp($j->{log}) : '';
        $txt .= $log;
    }
    ev($n, "pipelines/$tag-$pl->{id}.log", $txt);
}
my %SPRINT_MRS;                                                         # sprint -> [mr iids]
my %FIRST_PASS;                                                         # mr iid -> first pipeline status
sub open_mr {
    my ($n, $f, %a) = @_;
    my $u = $f->{user};
    $gl->as($u);
    my $mr = $f->finish(title => $a{title}, description => mr_text(%a), labels => [ 'workflow::review', @{ $a{labels} // [] } ], milestone => "Sprint $n",
                        reviewers => [ reviewer_for($u, @{ $a{files} // [] }) ]);
    push @{ $SPRINT_MRS{$n} }, $mr->{iid};
    my $pl = pipeline_of($mr);
    $FIRST_PASS{ $mr->{iid} } = $pl ? $pl->{status} : 'none';
    logd(substr($gl->now, 0, 10), $u, "opened !$mr->{iid} $a{title} (pipeline " . ($pl ? "#$pl->{id} $pl->{status}" : 'none') . ')');
    $mr;
}
sub todo_now { my $f = shift; my $c = $f->dir; my $n = 0; for my $x (grep { m{\.sysml$} } split /\n/, $f->git('ls-files', 'model')) { $n += () = (slurp("$c/$x") // '') =~ m{// TODO}g } $TODO_NOW = $n }
sub approve_merge {                                                    # review, approval(s), merge by the author
    my ($n, $mr, $author, %o) = @_;
    my $files = [ grep { length } split /\n/, $F{$author}->git('diff', '--name-only', "origin/develop...HEAD") ];
    if (($o{review} // '') eq 'request_changes') {                       # a line comment on an assumption: the thread blocks the merge
        todo_list($n, substr($gl->now, 0, 10)) if $n == 6;
        $gl->as('bob');
        $gl->add_note($P, 'mr', $mr->{iid}, "**Request changes** -- `model/library/Interfaces.sysml`, the `health` flow:\n\n"
            . "> Sent with every transmission; the data center flags a station whose report is late.\n\n"
            . "\"Late\" assumes a schedule we have not written down anywhere. TW-SYS-009 does not say how late is late. Either cite where the period comes from, or say it is an assumption:\n\n"
            . "```suggestion:-0+0\n        out item health : HealthReport { doc /* Sent with every transmission. Assumption (to confirm with the prime): late = two missed transmissions. */ }\n```", resolvable => 1);
        logd(substr($gl->now, 0, 10), 'bob', "line comment on !$mr->{iid}: request changes (the 'late' assumption)");
        $gl->tick(900);
        $gl->as('jim'); $gl->approve_mr($P, $mr->{iid});
        $gl->as($author);
        my $try = eval { $gl->merge_mr($P, $mr->{iid}); 1 } ? 'merged?!' : ($@ =~ /(discussions not resolved[^\n]*)/)[0] // $@;
        logd(substr($gl->now, 0, 10), $author, "merge refused: $try");
        my $f = $F{$author};
        my $p = $f->dir . '/model/library/Interfaces.sysml';
        my $x = slurp($p); $x =~ s{(out item health : HealthReport \{ doc /\* )Sent with every transmission; the data center flags a station whose report is late\.}{$1Sent with every transmission. Assumption (to confirm with the prime): late = two missed transmissions.}; spew($p, $x);
        regen($f);
        $f->commit("Interfaces: state the 'late' assumption\n\nApplied Bob's suggestion on !$mr->{iid}.");
        $f->publish;
        $gl->tick(1800);
        $gl->add_note($P, 'mr', $mr->{iid}, "Applied the suggestion; the assumption goes in the next prime-tbd list.");
        $gl->as('bob'); $gl->resolve_discussions($P, $mr->{iid});
        logd(substr($gl->now, 0, 10), 'bob', "resolved the thread on !$mr->{iid}");
        $gl->{_skip_approve}{jim} = 0;
    }
    my %done_appr = map { $_->{user}{username} => 1 } @{ $gl->mr($P, $mr->{iid})->{approved_by} };
    for my $r (reviewer_for($author, @$files)) {
        next if $done_appr{$r} && !(($o{review} // '') eq 'request_changes');
        $gl->as($r);
        $gl->add_note($P, 'mr', $mr->{iid}, $o{comment}{$r}) if $o{comment} && $o{comment}{$r};
        eval { $gl->approve_mr($P, $mr->{iid}) };                        # (already approved before a new push: GitLab keeps it)
        $gl->tick(600);
    }
    $gl->as($author);
    my $m = eval { $gl->merge_mr($P, $mr->{iid}) };
    if (!$m) { die "merge !$mr->{iid} failed: $@" }
    logd(substr($gl->now, 0, 10), $author, "merged !$mr->{iid}");
    $F{$author}->sync;
    todo_now($F{$author});
    $m;
}
sub model_change {                                                     # a feature branch, the edits, an MR, its pipeline, review, merge
    my ($n, $tk, %a) = @_;
    my $u = $tk->{who};
    my $f = flow($u);
    my $d = substr($gl->now, 0, 10);
    $f->sync;
    $gl->as($u);
    my $slug = lc($a{title} =~ s/[^A-Za-z0-9]+/-/gr); $slug =~ s/^-+|-+$//g; $slug = substr($slug, 0, 40); $slug =~ s/-+$//;
    $f->start(feature => "$tk->{iid}-$slug");
    my @ch;
    for my $e (@{ $a{edits} // [] }) { my ($name, %eo) = @$e; push @ch, tw_edit($name, $f->dir, %eo); $APPLIED{"$name " . join(',', map { "$_=$eo{$_}" } sort keys %eo)} = [ $name, %eo ]; $ST{legacy_removed} = 1 if $name eq 'legacy' }
    $a{pre}->($f) if $a{pre};
    my $plant = $a{plant} // '';
    my $restore;
    my $secret_file;
    if ($plant eq 'grammar') {                                           # a slip the grammar job catches: a missing name
        my $p = $f->dir . '/model/physical/network/Network.sysml';
        my $t = slurp($p); $restore = $t;
        $t =~ s/include use case queryArchive : QueryArchive;/include use case : QueryArchive queryArchive;/;
        spew($p, $t);
    } elsif ($plant eq 'ratchet') {                                      # a satisfy deleted as a "duplicate": the trace ratchet catches it
        my $p = $f->dir . '/model/requirements/model/Requirements.sysml';
        my $t = slurp($p); $restore = $t;
        $t =~ s/^\s*satisfy TW_SYS_002 by ObservingStation;\n//m;
        spew($p, $t);
    } elsif ($plant eq 'ai') {                                          # the local assistant's draft: v1 thinking in v2 text (illustrative)
        my $p = $f->dir . '/model/logical/GovBehavior.sysml';
        my $x = slurp($p); $restore = $x; $a{restore_path} = 'model/logical/GovBehavior.sysml';
        $x =~ s/(        transition first storm accept StormPassed then observing;\n)/$1        transition storm -> observing [StormPassed];\n/;
        spew($p, $x);
    } elsif ($plant eq 'drift') {                                        # a requirement's text "tidied" away from DOORS: drift goes up
        my $p = $f->dir . '/model/requirements/model/Requirements.sysml';
        my $t = slurp($p); $restore = $t;
        $t =~ s{(requirement TW_SYS_007 \{ doc /\* )The public service shall show}{$1The public website shall show};
        spew($p, $t);
    }
    if ($plant eq 'secret') {                                            # a token pasted into a helper "just to test it"
        $secret_file = $f->dir . '/ci/exchange-check.pl';
        spew($secret_file, "#!/usr/bin/perl\n# check the exchange table against the API (draft)\nmy \$token = 'glpat-" . substr(md5_hex('tom test token'), 0, 20) . "';\n"
                          . "my \$url = \"\$ENV{CI_API_V4_URL}/projects/\$ENV{CI_PROJECT_ID}/repository/files/docs%2Fdata-exchange.md/raw?ref=develop\";\nprint qx(curl -s -H \"PRIVATE-TOKEN: \$token\" \"\$url\");\n");
    }
    regen($f, raise => $a{raise});
    my $sha = $f->commit($a{commit} // $a{title}, ());
    return undef unless defined $sha;
    @ch = grep { length } split /\n/, $f->git('diff', '--name-only', 'origin/develop...HEAD');
    my $mr = open_mr($n, $f, title => ($a{draft} ? 'Draft: ' : '') . $a{title}, why => $a{why} // "$tk->{t} ($tk->{story}{id}).", closes => [ $tk->{iid} ], story => $tk->{story}{iid},
                     files => [ grep { m{^model/} && !m{^model/requirements/(stakeholder|system|segment)/} } @ch ], labels => $a{labels}, notes => $a{notes}, plant => $plant);
    $tk->{mr} = $mr->{iid};
    my $pl = pipeline_of($mr);
    keep_log($n, $pl, "mr$mr->{iid}-first") if $n <= 6 || ($pl && $pl->{status} ne 'success');
    if ($pl && $pl->{status} ne 'success') {                             # red: read the log, fix on the branch, push again
        $gl->tick(5400);
        die "!$mr->{iid}: pipeline failed with nothing planted:\n" . join('', map { slurp($_->{log}) // '' } grep { $_->{status} eq 'failed' } @{ $pl->{jobs} }) unless $restore || $a{fix} || $secret_file;
        if ($restore) { my $p = $a{restore_path} // ($plant eq 'grammar' ? 'model/physical/network/Network.sysml' : 'model/requirements/model/Requirements.sysml'); spew($f->dir . "/$p", $restore) }
        if ($secret_file) {                                              # remove it, rotate it, rewrite the branch, use a masked variable
            my $x = slurp($secret_file); $x =~ s/my \$token = '[^']*';/my \$token = \$ENV{READ_TOKEN} or die "READ_TOKEN is not set\\n";/; spew($secret_file, $x);
            $gl->as('tom'); $gl->set_variable($P, 'READ_TOKEN', 'glpat-' . substr(md5_hex('rotated read token'), 0, 20), masked => 1, protected => 1);
            $f->git('reset', '-q', '--soft', 'origin/develop');           # rewrite the branch: the token never reaches develop's history
            $gl->as($u);
            $gl->add_note($P, 'mr', $mr->{iid}, "The secrets job caught a personal access token I pasted into `ci/exchange-check.pl` to test it. Revoked it in GitLab, "
                . "created a read_api project token instead, stored it as the masked, protected variable `READ_TOKEN`, and rewrote this branch so the token is in no commit.");
            logd(substr($gl->now, 0, 10), $u, "secrets job failed on !$mr->{iid}: token revoked, rotated to masked READ_TOKEN, branch rewritten");
        }
        $a{fix}->($f) if $a{fix};
        regen($f);
        $f->commit($a{fix_msg} // ($secret_file ? "$a{title}\n\nThe check reads its token from the masked variable READ_TOKEN." : 'Fix what the pipeline found'));
        if ($secret_file) { $f->git('push', '-q', '--force-with-lease', 'origin', $f->branch); $gl->pushed($P, 'refs/heads/' . $f->branch) } else { $f->publish }
        $pl = pipeline_of($mr);
        keep_log($n, $pl, "mr$mr->{iid}-fixed") if $n <= 6;
        $pl && $pl->{status} eq 'success' or die "!$mr->{iid}: still red after the fix:\n" . join('', map { slurp($_->{log}) // '' } grep { $_->{status} eq 'failed' } @{ $pl->{jobs} });
    }
    if ($a{draft}) { $gl->tick(1800); $gl->as($u); $gl->add_note($P, 'mr', $mr->{iid}, "Green now; ready for review.\n/ready"); logd(substr($gl->now, 0, 10), $u, "marked !$mr->{iid} ready") }
    $gl->tick(3 * 3600 + 1200);
    approve_merge($n, $mr, $u, %a);
    $mr;
}

# ======================================================================== the actions behind tasks
our ($CI_LEVEL, $SCHEDULE_ON) = (0, 0);
my %DR;                                                                 # DR number -> issue iid
my @DROPLOG;                                                            # drops table rows
my %ACT;
$ACT{note} = sub { my ($n, $tk) = @_; 1 };
$ACT{runner_request} = sub { my ($n, $tk) = @_; $tk->{note} = 'Runner request filed with the enterprise GitLab admins on 2026-10-05 (Windows shell runner, tags windows,mbse, Git for Windows 2.47 with its Perl).'; 1 };
$ACT{setup} = sub {
    my ($n, $tk) = @_;
    $gl->as('root');
    $gl->create_user($_, name => $PEOPLE{$_}{name}, email => "$_\@example.invalid") for @TEAM;
    $gl->create_user('dpm', name => 'Deputy PM', email => 'dpm@example.invalid');
    $gl->create_user('issm', name => 'ISSM', email => 'issm@example.invalid');
    $gl->create_user('nwm-modeler', name => "The prime's modeler", email => 'modeler@nwm.example.invalid');
    $gl->create_group('tidewater');
    $gl->add_member('tidewater', 'tom', 'owner', group => 1);
    $gl->as('tom');
    my $conf = slurp("$ROOT/tools/gitlab/templates/project.conf");
    $conf =~ s/^KIT = \S+/KIT = $ROOT/m;
    $conf =~ s/^only_allow_merge_if_pipeline_succeeds = true/only_allow_merge_if_pipeline_succeeds = false   ; until the runner is online (sprint 2)/m;
    $conf =~ s/^\[schedules\].*?(?=^\[|\z)//ms;                        # the nightly schedule comes in sprint 4
    spew("$W/project.conf", $conf);
    my $log = $gl->apply_project_file("$W/project.conf");
    $gl->add_member($P, $_, 'reporter') for qw(dpm issm nwm-modeler);
    $gl->as('jim');                                                     # the front door: the intake project, one issue per Windchill request
    my $rlog = $gl->apply_project_file("$ROOT/tools/gitlab/templates/requests.conf");
    ev($n, 'setup-requests.txt', "perl \$KIT/bin/gitlab.pl --as jim setup tools/gitlab/templates/requests.conf\n" . join('', map { "  $_\n" } @$rlog));
    $gl->as('tom');
    $gl->set_variable($P, $_->[0], $_->[1]) for ['SPRINT_START', $START], ['SPRINT_WEEKS', '2'], ['KIT_VERSION', 'agile-kit 2026.10'], ['CI_RUNNER_DESCRIPTION', 'mbse-win-01'], ['CI_RUNNER_EXECUTABLE_ARCH', 'windows/amd64'];   # as GitLab Runner reports them; the emulator runs the jobs with sh
    ev($n, 'setup.txt', "perl \$KIT/bin/gitlab.pl --as tom setup tools/gitlab/templates/project.conf\n" . join('', map { "  $_\n" } @$log));
    my $f = flow('tom');
    spew($f->dir . '/README.md', slurp("$ROOT/tools/gitlab/templates/README.md"));
    spew($f->dir . '/CHANGELOG.md', "# Changelog\n\nAll notable changes to the Tidewater government SysML v2 model.\n\n## [Unreleased]\n");
    spew($f->dir . '/sysml.conf', "# sysml.conf -- read by \$KIT/tools/sysml/model.pl\ntitle = Tidewater\nnoun_root = ObservationNetwork\nverb_root = ObserveCoast\n"
        . "idef0_name = ObserveCoast\nmodel_letter = O\n# steps only matter with idef0_models = steps\nidef0_models = auto\nsteps = sample:S:Sample, send:X:Transmit, ingest:I:Ingest, check:Q:Check, store:A:Archive, publish:P:Publish\nalloc_prefix = observe\nlayers = Types, Conventions; Interfaces, Analysis; Stakeholder Needs, System Requirements, Segment Requirements; "
        . "Network, Stations, DataCenter, Operations, GovBehavior; Behavior; Allocations, Verification, Requirements\nmax_package_fan_out = 7\nmax_relationships_per_part = 10\nmax_cycles = 0\n");
    spew($f->dir . '/model/README.md', "# model\n\nThe Tidewater SysML v2 text model, in layers: library -> requirements -> logical -> physical -> analysis ->\nverification (examples/tidewater-v1/layout.map says where each prime package lands). Government additions live in\nthe layer they belong to and say so in their first line. See CODEOWNERS for who approves what.\n");
    spew($f->dir . '/.ci/outline-max', "1\n");
    $f->git('checkout', '-q', '-B', 'main');
    $f->git('add', '-A');
    $f->git('commit', '-q', '-m', "Initial commit: README, CHANGELOG, sysml.conf and the outline allowance\n\nChangelog: added");
    $f->init;
    $tk->{note} = 'Project created from project.conf; main and develop exist; develop is the default branch.';
    1;
};
$ACT{protect_proof} = sub {
    my ($n, $tk) = @_;
    my $f = flow('tom');
    $f->sync;
    spew($f->dir . '/README.md', slurp($f->dir . '/README.md') . "\n<!-- a direct push, to prove it is refused -->\n");
    $f->git('commit', '-q', '-am', 'Test: a direct push to develop');
    my ($out, $rc) = $f->git_rc('push', 'origin', 'HEAD:refs/heads/develop');
    $f->git('reset', '-q', '--hard', 'origin/develop');
    ev($n, 'protect-proof.txt', "\$ git push origin HEAD:develop\n$out(exit $rc)\n");
    $tk->{note} = "A direct push to develop is refused by the server:\n\n```text\n" . rel($out) . "```";
    die "the direct push was not refused\n" unless $rc;
    1;
};
$ACT{repo_files} = sub {
    my ($n, $tk) = @_;
    my $f = flow('tom');
    $f->sync;
    $f->start(feature => "$tk->{iid}-codeowners-and-templates");
    my $tt = "$ROOT/tools/gitlab/templates";
    copy("$tt/CODEOWNERS", $f->dir . '/CODEOWNERS');
    copy("$tt/.gitignore", $f->dir . '/.gitignore');
    for my $k (qw(issue_templates merge_request_templates)) {
        opendir my $dh, "$tt/.gitlab/$k" or die; for my $x (sort grep { /\.md$/ } readdir $dh) { make_path($f->dir . "/.gitlab/$k"); copy("$tt/.gitlab/$k/$x", $f->dir . "/.gitlab/$k/$x") } closedir $dh;
    }
    make_path($f->dir . '/.gitlab');                                    # the Insights dashboard (Ultimate): generated from project.conf, committed by MR
    spew($f->dir . '/.gitlab/insights.yml', (GitLab::insights_yml(GitLab::parse_project_file(slurp("$W/project.conf"), "$W/project.conf"), "$W/project.conf"))[0]);
    $f->commit("Add CODEOWNERS, the issue and MR templates, the Insights dashboard and .gitignore\n\nChangelog: added");
    my $mr = open_mr($n, $f, title => 'CODEOWNERS, issue and MR templates, .gitignore', why => 'Who approves what, the shapes of our issues and merge requests, and the Insights dashboard management reads (.gitlab/insights.yml, generated by `gitlab.pl insights` from project.conf). The project has no pipeline yet: .gitlab-ci.yml arrives in sprint 2, and until "pipelines must succeed" is turned on, merges like this one are checked by review only (Jim approves). This MR therefore has no pipeline, on purpose.', closes => [ $tk->{iid} ], story => $tk->{story}{iid});
    $gl->tick(7200);
    approve_merge($n, $mr, 'tom');
    $tk->{mr} = $mr->{iid};
    1;
};
my $DRAFT_DIR;
$ACT{ci_draft} = sub {
    my ($n, $tk) = @_;
    $tk->{note} = "The draft pipeline (sh syntax, as the tutorials write it):\n\n```yaml\n$SH_DRAFT```";
    1;
};
$ACT{ci_local} = sub {                                                  # the draft, run on Tom's laptop against drop 1 (no runner yet)
    my ($n, $tk) = @_;
    my $t = "$W/scratch/local-ci";
    remove_tree($t); make_path("$t/model");
    tw_convert($ROOT)->("$W/drops/v1.0", "$t/model");
    spew("$t/.gitlab-ci.yml", $SH_DRAFT);
    spew("$t/sysml.conf", slurp(flow('tom')->dir . '/sysml.conf'));
    run_q($t, 'git', 'init', '-q', '-b', 'feature/pipeline-draft');
    run_q($t, 'git', '-c', 'user.name=Tom', '-c', 'user.email=tom@example.invalid', 'add', '-A');
    run_q($t, 'git', '-c', 'user.name=Tom', '-c', 'user.email=tom@example.invalid', '-c', 'commit.gpgsign=false', 'commit', '-qm', 'draft');
    local $ENV{KIT} = $ROOT;
    my ($out, $rc) = run_q($t, $^X, "$ROOT/bin/gitlab.pl", 'ci', '--event', 'push', '--branch', 'feature/pipeline-draft', '--var', "KIT=$ROOT");
    $out =~ s/^(\S+)(\s+\S+\s+\S+\s+)\d+\.\ds$/$1 . $2 . sprintf('%.1fs', jobsec($1, 'laptop') \/ 20)/mge;   # a laptop's times (the run's own vary)
    ev($n, 'local-ci-draft.txt', "\$ perl \$KIT/bin/gitlab.pl ci --event push --branch feature/pipeline-draft --var KIT=\$KIT\n$out(exit $rc)\n");
    $tk->{note} = "The draft runs locally (sh) on drop 1:\n\n```text\n" . rel($out =~ s/^\s+\|.*\n//mgr) . "```";
    1;
};
$ACT{ci_first} = sub {                                                  # sprint 2: the real runner speaks PowerShell
    my ($n, $tk) = @_;
    my $f = flow('tom');
    $f->sync;
    $gl->{runner_shell} = "$ROOT/sim/tidewater-pwsh.pl";
    $f->start(feature => "$tk->{iid}-first-pipeline");
    spew($f->dir . '/.gitlab-ci.yml', $SH_DRAFT);
    $f->commit("Add the first pipeline: grammar, lint, outline");
    my $mr = open_mr($n, $f, title => 'The first pipeline: grammar, lint, outline', why => 'The configuration audit, run by the server on every change.', closes => [ $tk->{iid} ], story => $tk->{story}{iid},
                     notes => 'Ran green locally with `gitlab.pl ci`; first run on the real runner.');
    my $pl = pipeline_of($mr);
    keep_log($n, $pl, "mr$mr->{iid}-first-on-powershell");
    $gl->tick(4 * 3600);
    make_path($f->dir . '/ci');
    copy("$ROOT/tools/gitlab/templates/ci/job.pl", $f->dir . '/ci/job.pl');
    spew($f->dir . '/.gitlab-ci.yml', ci_yaml(1));
    $f->commit("Run every job as perl ci/job.pl NAME\n\nThe runner's shell is PowerShell: \$KIT, \$(...), && and || are sh. One Perl script runs the same everywhere.");
    $f->publish;
    $pl = pipeline_of($mr);
    keep_log($n, $pl, "mr$mr->{iid}-job-pl");
    $pl->{status} eq 'success' or die "ci_first: still red\n";
    $gl->tick(3600);
    approve_merge($n, $mr, 'tom');
    $tk->{mr} = $mr->{iid};
    $CI_LEVEL = 1;
    1;
};
$ACT{gate_on} = sub {
    my ($n, $tk) = @_;
    $gl->as('tom');
    $gl->update_project($P, only_allow_merge_if_pipeline_succeeds => 'true');
    $ST{gate_on_at} = $gl->now;
    $tk->{note} = '"Pipelines must succeed" is on: an MR with a red pipeline cannot be merged. The JUnit and Code Quality reports show on every MR.';
    1;
};
$ACT{ci_level} = sub {                                                  # the pipeline grows by one level
    my ($n, $tk, %a) = @_;
    my $lv = $a{level};
    my %why = (2 => 'Adds the todo (port burn-down) and docs (generated docs current) jobs, and commits docs/.',
               3 => 'Adds the trace report (report only for now) and the secrets job.', 4 => 'Adds the pages job: the model site for management, rebuilt on every merge and nightly.',
               5 => 'The trace job becomes a ratchet: it fails an MR that adds a gap.', 6 => 'Adds the vcrm job and the baseline jobs.',
               7 => 'Adds the complexity guardrails, delta and drop-package for drop intake, and the weekly status.',
               8 => 'Adds the intake job for deliveries triggered by the prime\'s Jenkins.', 9 => 'The full template: baselines published as packages, release links and milestones.');
    model_change($n, $tk, title => "Pipeline: " . ($why{$lv} =~ s/\.$//r), why => $why{$lv}, pre => sub { my $f = shift; spew($f->dir . '/.gitlab-ci.yml', ci_yaml($lv)) });
    $CI_LEVEL = $lv;
    if ($a{schedule}) {
        $gl->as('tom');
        if ($gl->can('create_schedule')) {
            $gl->create_schedule($P, description => 'Nightly full check', ref => 'develop', cron => '0 2 * * 1-5', cron_timezone => 'America/New_York', variables => { FULL => '1' });
            $SCHEDULE_ON = 1;
        }
    }
    1;
};
sub drop_dir { my $d = shift; my $v = 'v1.' . ($d - 1); my $dir = "$W/drops/$v"; $dir }
$ACT{drop_check} = sub {
    my ($n, $tk, %a) = @_;
    my $dir = drop_dir($a{drop});
    my $man = slurp("$dir/MANIFEST.txt"); $man =~ s/\r\n/\n/g;
    my @rows;
    while ($man =~ /^\s+([0-9a-f]{64})\s+(\S+)\s*$/mg) { my ($s, $f) = ($1, $2); my $got = Digest::SHA->new(256)->addfile("$dir/$f", 'b')->hexdigest; push @rows, "| `$f` | " . ($got eq $s ? 'matches' : 'MISMATCH') . " |" }
    $tk->{note} = "Delivery logged. Every file checked against MANIFEST.txt:\n\n| File | sha256 |\n|---|---|\n" . join("\n", @rows) . "\n";
    1;
};
$ACT{drop_issue} = sub {
    my ($n, $tk, %a) = @_;
    my $d = $a{drop}; my $v = 'v1.' . ($d - 1);
    my $dir = drop_dir($d);
    my $man = slurp("$dir/MANIFEST.txt"); $man =~ s/\r\n/\n/g;
    my ($del) = $man =~ /^Delivered: (\S+)/m;
    my ($chg) = $man =~ /^Changes: (.*)$/m;
    $gl->as('jim');
    my $body = "## The drop\n\n| | |\n|---|---|\n| Version | $v |\n| Delivered | $del, " . ($d >= 4 ? "the prime's Jenkins through the package registry" : 'CDRL file transfer to approved storage') . " |\n"
             . "| CDRL | A003 System Model |\n| MANIFEST sha256 | `" . substr(Digest::SHA::sha256_hex(slurp("$dir/MANIFEST.txt")), 0, 16) . "...` |\n| Changes | $chg |\n\n"
             . "## Intake checklist\n\n- [x] Files received and scanned; hashes match `MANIFEST.txt`\n- [ ] `gitlab.pl flow vendor` committed the drop on `vendor/prime`\n"
             . "- [ ] The `delta` report reviewed: every *manual* line has a task\n- [ ] Merge MR opened; conflicts resolved\n- [ ] Trace re-run; DRs updated\n- [ ] Merged to `develop`\n";
    my $i = $gl->create_issue($P, title => "Intake prime drop $v ($del)", labels => [ 'type::drop', 'owner::gov', 'priority::1' ], milestone => "Sprint $n", assignees => ['tom'], description => $body);
    $tk->{drop_issue} = $i->{iid};
    $ST{"drop$d"} = $i->{iid};
    1;
};
$ACT{convert_report} = sub {
    my ($n, $tk, %a) = @_;
    my $dir = drop_dir($a{drop});
    my ($x) = run_q(undef, $^X, "$ROOT/bin/xmi2sysml.pl", '--report', "$dir/tidewater.xmi");
    my ($r) = run_q(undef, $^X, "$ROOT/bin/reqif2sysml.pl", '--report', "$dir/tidewater.reqif");
    my $t = "$W/scratch/assess"; remove_tree($t); make_path("$t/model");
    tw_convert($ROOT)->($dir, "$t/model");
    my %f = (); my $ms = CIJob::model_side("$t/model");
    my ($tr) = run_q(undef, $^X, "$ROOT/bin/reqif2sysml.pl", '--report', '--model', $ms, "$dir/tidewater.reqif");
    ev($n, 'drop1-xmi2sysml-report.txt', $x); ev($n, 'drop1-reqif2sysml-report.txt', $r); ev($n, 'drop1-trace.txt', $tr);
    my ($sum) = $x =~ /(ported vs remaining[^\n]*)/;
    my ($drift) = $tr =~ /^(drift:[^\n]*)/m;
    $tk->{note} = "Both converters run on drop 1.\n\n- xmi2sysml: " . ($sum // '') . "\n- trace: " . join(', ', $tr =~ /^([CFGI] [^\n]*?)\s{2,}(\S+)\s*$/mg) . "\n- " . ($drift // 'no drift') . "\n\nReports attached to the sprint evidence.";
    1;
};
$ACT{todo_inventory} = sub {
    my ($n, $tk, %a) = @_;
    my $t = "$W/scratch/assess";
    my %by; my $tot = 0;
    my @sysml; File::Find::find({ no_chdir => 1, wanted => sub { push @sysml, $File::Find::name if /\.sysml$/ && -f } }, "$t/model");   # the layered layout nests folders
    for my $f (sort @sysml) { my $c = () = (slurp($f) =~ m{// TODO}g); next unless $c; (my $r = $f) =~ s{^\Q$t\E/}{}; $by{$r} = $c; $tot += $c }
    my %kind; for my $f (sort @sysml) { my $x = slurp($f); while ($x =~ m{// TODO (?:stereotype Tidewater_Profile:(\w+))?}g) { my $s = $1 // ''; $kind{ $s =~ /^L\d/ ? 'level stereotype' : $s eq 'Procured' ? 'Procured stereotype' : 'other' }++ } }
    my $page = "# Drop 1 TODO inventory\n\n[[_TOC_]]\n\nThe converter left **$tot** TODO lines in drop 1. Each is a v1 construct it could not carry; each is a line of port work.\n\n"
             . "## By file\n\n| File | TODO lines |\n|---|---:|\n" . join('', map { "| `$_` | $by{$_} |\n" } sort keys %by)
             . "\n## By kind\n\n| Kind | Lines |\n|---|---:|\n" . join('', map { "| $_ | $kind{$_} |\n" } sort keys %kind)
             . "\n> [!note]\n> The " . ($kind{q{level stereotype}} // 0) . " level-stereotype lines are mechanical (one metadata tag each); the rest need a person: state machines, interactions, constraints, flows.\n";
    $gl->as('bob');
    $gl->wiki_put($P, 'Drop 1 TODO inventory', $page);
    ev($n, 'samples/wiki-drop1-todo-inventory.md', $page);
    $tk->{note} = "TODO inventory on the wiki: $tot lines.";
    1;
};
$ACT{wiki} = sub {
    my ($n, $tk, %a) = @_;
    $gl->as($tk->{who});
    for my $pg (@{ $a{pages} }) {
        my $src = "$ROOT/tools/gitlab/templates/wiki/$pg.md";
        my $c = -f $src ? slurp($src) : "# $pg\n\n" . ($pg eq 'Operating Model' ? operating_model($n) : $pg eq 'Trace Measures' ? trace_page() : "Written in sprint $n.\n");
        $gl->wiki_put($P, $pg, $c);
        ev($n, "samples/wiki-" . lc($pg =~ s/\W+/-/gr) . ".md", $c) if $n <= 6;
    }
    1;
};
my $OM_EDITS = 0;
sub operating_model {
    my $n = shift;
    $OM_EDITS++;
    "Revision $OM_EDITS (sprint $n).\n\n| When | What | Where |\n|---|---|---|\n| Daily 09:00 | Stand-up: terse Y/T/B in the meeting chat, one line each | Teams chat, `daily.pl lint` |\n"
  . "| Day 1 09:00 (90 min) | Kickoff: goal, capacity, commit | the board, the journal |\n| Wednesday week 2, 10:00 | Refinement and planning poker | issues, `#est` in chat |\n"
  . "| Friday week 2, 10:00 | Review (demo) | the model site, MRs, pipelines |\n| Friday week 2, 11:00 | Retrospective and pulse survey | the wiki |\n| Fridays 15:00 | Weekly note (the quad) | `daily.pl quad` |\n";
}
sub trace_page { "C = DOORS requirements found in the model; F = orphans (nothing satisfies them); G = unverified (no verification case); I = trace completeness; drift = model text differs from DOORS.\n\nThe numbers are on the model site, rebuilt on every merge.\n" }
$ACT{adr} = sub {                                                       # ADRs: 0001-0003 from the scaffold, 0004 data handling, 0005-0014 = D-1..D-10
    my ($n, $tk) = @_;
    my @D = (['Data handling and markings', 'the repository holds notional, unclassified data only; files are marked where a marking applies; Tom is the security owner', 'week zero'],
             ['D-1 The model is SysML v2 textual notation in a git repository', 'text can be compared, merged, checked and reviewed line by line'],
             ['D-2 Gitflow: develop is the default (integration) branch; main holds baselines only', 'baselines are released to other programs; day-to-day work never waits on a release'],
             ['D-3 Every merge is a merge commit; no squash, no fast-forward', 'the history of who changed what feeds the metrics and the audit trail'],
             ['D-4 DOORS stays authoritative for requirement text', 'the model holds a converted copy; the trace job reports drift'],
             ['D-5 Prime drops land on a vendor branch and are merged into develop', 'git merges the prime\'s changes with the government\'s edits'],
             ['D-6 The team never edits the v1 model', 'problems go to the prime as discrepancy reports'],
             ['D-7 Conversion debt (TODO lines) is the port progress measure', 'it is computed, countable and indisputable'],
             ['D-8 Tasks at most 5 points; stories fit one sprint; tasks in GitLab, stories in the journal', 'small merge requests are reviewed properly'],
             ['D-9 The pipeline runs on a Windows shell runner with Git for Windows\' Perl', 'the same tools as the laptops; nothing new to approve'],
             ['D-10 Everything that can be a file is a file under version control', 'it can be reviewed, rebuilt and audited']);
    model_change($n, $tk, title => 'Decision records: ADRs 0001-0014', why => 'The week-zero decisions as files: 0001-0003 from the scaffold, 0004 data handling, 0005-0014 are D-1 to D-10.', pre => sub {
        my $f = shift;
        my $tdir = "$ROOT/tools/gitlab/templates/docs/adr";
        my ($k) = slurp("$ROOT/tools/gitlab/kickoff.pl") =~ /\$put->\('docs\/adr\/0001-record-decisions\.md', <<'EOF'\);\n(.*?)\nEOF\n/s;
        spew($f->dir . '/docs/adr/0001-record-decisions.md', ($k // "# 1. Record decisions in the repository\n") =~ s/\(the day you merge this\)/2026-10-01/r . "\n");
        for my $x (grep { -f } glob("$tdir/000[23]-*.md")) { (my $b = $x) =~ s{.*/}{}; spew($f->dir . "/docs/adr/$b", slurp($x)) }
        for my $i (0 .. $#D) {
            my ($title, $why) = @{ $D[$i] };
            (my $plain = $title) =~ s/^D-\d+ //;
            my $slug = lc($plain =~ s/[^A-Za-z0-9]+/-/gr); $slug =~ s/-+$//; $slug = substr($slug, 0, 50); $slug =~ s/-+$//;
            my $num = $i + 4;
            spew($f->dir . sprintf('/docs/adr/%04d-%s.md', $num, $slug), sprintf("# %d. %s\n\nDate: 2026-10-01 (week zero; recorded %s)\n\n## Status\n\nAccepted%s\n\n## Context\n\nThe team is moving from documents and a Cameo model to SysML v2 text in GitLab.\n\n## Decision\n\n%s.\n\n## Consequences\n\n%s.\n",
                $num, $plain, substr($gl->now, 0, 10), ($title =~ /^(D-\d+)/ ? " ($1 in the operating model)" : ''), $plain, ucfirst $why));
        }
    });
    $gl->as('jim');
    $gl->wiki_put($P, 'Decisions', "# Decisions\n\nEach decision is a file in `docs/adr/` (reviewed by MR). The operating model's D-1 to D-10 are ADRs 0005 to 0014.\n\n| ADR | Decision |\n|---|---|\n"
        . "| 0001 | Record decisions in the repository |\n| 0002 | The prime boundary |\n| 0003 | One results schema |\n" . join('', map { sprintf "| %04d | %s |\n", $_ + 4, $D[$_][0] } 0 .. $#D));
    1;
};
$ACT{vendor} = sub {                                                    # the prime's drop onto vendor/prime, merged into a feature branch
    my ($n, $tk, %a) = @_;
    my $d = $a{drop}; my $v = 'v1.' . ($d - 1);
    my $u = $tk->{who};
    my $f = flow($u);
    $f->sync;
    $gl->as($u);
    my $conv = tw_convert($ROOT);
    my $wrap = $a{doors} ? $conv : sub { my ($drop, $out) = @_; my $t = "$W/scratch/nodoors"; remove_tree($t); make_path($t);
        for (glob("$drop/*")) { next if /\.reqif$/ && $d == 1 && !$a{doors}; copy($_, $t) } $conv->($t, $out) };
    my $r = $f->vendor_import(drop => drop_dir($d), version => $v, convert => $wrap, branch => "drop-$v" . ($a{doors} ? '-doors' : ''),
                              message => "Import prime drop $v" . ($a{doors} ? ' with the DOORS modules' : '') . " (CDRL A003)");
    my @conf = @{ $r->{conflicts} };
    my %res;
    if (@conf) {                                                        # take the prime's side, then re-apply the government's edits
        for my $c (@conf) {
            my (undef, $rc) = $f->git_rc('cat-file', '-e', "MERGE_HEAD:$c");
            if ($rc) { $f->git('rm', '-q', '--', $c); $res{$c} = 'deleted upstream: removed' }
            else { $f->take('theirs', $c); $res{$c} = 'took the prime\'s side, re-applied the government edits' }
        }
        tw_edit(@$_, ) for map { [ $_->[0], $f->dir, @{$_}[1 .. $#$_] ] } values %APPLIED;
        $f->git('add', '-A', '--', 'model');
    }
    for my $e (sort keys %APPLIED) { my ($name, @eo) = @{ $APPLIED{$e} }; tw_edit($name, $f->dir, @eo) }
    unlink $f->dir . '/model/legacy/Legacy_Import.sysml' if $ST{legacy_removed};
    my $nv = regen($f, raise => 1);
    $f->git('add', '-A');
    my (undef, $merging) = $f->git_rc('rev-parse', '--verify', '-q', 'MERGE_HEAD');
    $f->git('commit', '-q', '--no-edit') if !$merging;
    $f->commit("Regenerate docs; outline allowance $nv after drop $v") if $merging || 1;
    my ($dl) = run_q($f->dir, $^X, "$ROOT/bin/xmi2sysml.pl", '--delta', (glob($f->dir . '/imports/v1.' . ($d - 2) . '/tidewater.xmi'))[0] // drop_dir($d) . '/tidewater.xmi', drop_dir($d) . '/tidewater.xmi') if $d > 1;
    $tk->{delta} = $dl;
    ev($n, "drop$d-delta.txt", $dl // "first drop\n");
    my $mr = open_mr($n, $f, title => "Prime drop $v" . ($a{doors} ? ' with the DOORS modules' : ''), why => "The prime's drop $v, converted on vendor/prime and merged here.",
                     closes => [ $tk->{iid}, ($ST{"drop$d"} && !$a{doors} ? $ST{"drop$d"} : ()) ], story => $tk->{story}{iid}, labels => ['type::drop', 'prime-change'], adds_todo => 1,   # the merge closes the intake issue too
                     notes => (-f drop_dir($d) . '/CHANGES.csv' ? "Prime changes in this drop: " . join(', ', map { (split /,/)[0] } grep { /^NWM-CR/ } split /\r?\n/, slurp(drop_dir($d) . '/CHANGES.csv')) . ".\n\n" : '')
                              . (@conf ? "Conflicts resolved:\n\n| File | Resolution |\n|---|---|\n" . join('', map { "| `$_` | $res{$_} |\n" } sort keys %res) : 'No conflicts.')
                              . ($dl ? "\n\n<details><summary>v1 delta</summary>\n\n```text\n$dl```\n</details>\n" : ''));
    $tk->{mr} = $mr->{iid};
    $ST{"vendor_mr$d"} = $mr->{iid};
    my $pl = pipeline_of($mr);
    keep_log($n, $pl, "mr$mr->{iid}-drop$d");
    push @DROPLOG, { drop => $d, version => $v, conflicts => scalar @conf, mr => $mr->{iid}, sprint => $n, outline => $nv } unless $a{doors};
    1;
};
$ACT{drop_merge} = sub {                                                # review the drop MR; Jim approves (imports/ and requirements); merge
    my ($n, $tk, %a) = @_;
    my $d = $a{drop};
    my $iid = $ST{"vendor_mr$d"} // die "no vendor MR for drop $d\n";
    my $mr = $gl->mr($P, $iid);
    my $pl = pipeline_of($mr);
    if ($pl && $pl->{status} ne 'success') {                             # red after the merge: fix forward on the drop branch
        my $f = flow('tom');
        $f->checkout($mr->{source_branch});
        tw_edit(@$_) for map { [ $_->[0], $f->dir, @{$_}[1 .. $#$_] ] } values %APPLIED;
        regen($f, raise => 1);
        $f->commit("Fix forward after drop " . ('v1.' . ($d - 1)));
        $f->publish;
        $pl = pipeline_of($mr);
        die "drop $d MR still red\n" unless $pl->{status} eq 'success';
    }
    $gl->as($tk->{who});
    $gl->add_note($P, 'mr', $iid, "Read the delta and the conflict table. Outline allowance recorded in `.ci/outline-max`.\n/spend 2h");
    my $author = $mr->{author}{username};
    flow('jim')->git('fetch', '-q', 'origin');
    my $files = [ grep { length } split /\n/, flow('jim')->git('diff', '--name-only', "origin/develop...origin/$mr->{source_branch}") ];
    my %appr = map { $_ => 1 } ('jim', reviewer_for($author, @$files));
    delete $appr{$author};
    for my $r (sort keys %appr) { $gl->as($r); $gl->approve_mr($P, $iid) }
    $gl->as($tk->{who});
    $gl->merge_mr($P, $iid);
    $F{$_} && $F{$_}->sync for @TEAM;
    my ($row) = grep { $_->{drop} == $d } @DROPLOG;
    $row->{merged} = substr($gl->now, 0, 10) if $row;
    1;
};
$ACT{drop_rework} = sub {
    my ($n, $tk, %a) = @_;
    my $d = $a{drop};
    my %e = (3 => [['statemachine', storm => 1]], 6 => [['interaction', resend => 1]]);
    return 1 unless $e{$d};
    model_change($n, $tk, title => "Rework drop v1." . ($d - 1) . " by hand: what the delta marks manual", edits => $e{$d}, why => 'The delta marks these v1 changes manual: the converter does not carry them.',
                 ($d == 3 ? (labels => ['ai::assisted'], plant => 'ai', notes => 'First draft from the local SysML assistant (approved in sprint 9): it wrote a v1-style transition; the grammar job caught it, fixed by hand.') : ()));
    1;
};
sub disposition {                                                      # how the CCB (Jim and the deputy PM) dispositions one prime CR
    my ($cr) = @_;
    return 'reject-clarify' if $cr->{kind} eq 'rename' && !length($cr->{rationale} // '');
    return 'accept-with-impact' if $cr->{title} =~ /drifting buoys|storm mode/i;
    return 'no-impact' if $cr->{title} =~ /^Documentation edits/i;
    'accept';
}
sub prime_changes {                                                    # one prime-change issue per CR in the drop, dispositioned
    my ($n, $d) = @_;
    my $f = drop_dir($d) . '/CHANGES.csv';
    return [] unless -f $f;
    my @rows = map { my @c = split /,/, $_, 6; +{ cr => $c[0], title => $c[1], rationale => $c[2], kind => $c[3], xmi => $c[4], reqs => $c[5] } } grep { /^NWM-CR/ } split /\r?\n/, slurp($f);
    my @out;
    for my $cr (@rows) {
        my $disp = disposition($cr);
        $gl->as('jim');
        my $i = $gl->create_issue($P, title => "$cr->{cr}: $cr->{title}", labels => [ 'prime-change', "disposition::$disp", 'owner::gov', 'work::engineering', 'area::requirements' ],
            milestone => "Sprint $n", assignees => ['jim'], description => "| | |\n|---|---|\n| Prime CR | $cr->{cr} |\n| Drop | v1." . ($d - 1) . " |\n| Kind | $cr->{kind} |\n"
            . "| v1 elements | `$cr->{xmi}` |\n| Requirements | " . ($cr->{reqs} || '-') . " |\n| Prime's rationale | " . (length($cr->{rationale} // '') ? $cr->{rationale} : '*(none given)*') . " |\n\n"
            . "## Disposition: $disp\n\n" . ({ accept => 'Accepted as delivered; implemented by the drop merge.', 'accept-with-impact' => 'Accepted; it adds government work: new verification cases and hand rework (tasks linked). Cost: about 3 points; no schedule change.',
                'reject-clarify' => 'Not accepted yet: the CR gives no rationale. A DR asks the prime why; the government model keeps the old name until the prime answers.', 'no-impact' => 'Cosmetic: nothing for the government model to do.' }->{$disp}) . "\n");
        $gl->as('dpm');
        $gl->add_note($P, 'issue', $i->{iid}, "CCB: concur with the disposition ($disp). -- Deputy PM");
        if ($disp eq 'reject-clarify') {
            $DRTEXT{8} = ["$cr->{cr} gives no rationale for renaming PublishBulletin", '-', "The prime renamed PublishBulletin to IssueBulletin (same xmi:id) with no rationale. The rename breaks the government's hand edits and the generated docs. Please give the reason, or revert it."];
            $ACT{drs}->($n, { who => 'jim' }, drs => [8]);
        }
        $gl->as('jim');
        $gl->add_note($P, 'issue', $i->{iid}, "/close") unless $disp eq 'reject-clarify';
        push @out, [ $cr->{cr}, $disp, $i->{iid} ];
    }
    ev($n, "drop$d-dispositions.txt", "Drop v1." . ($d - 1) . " -- prime changes and their CCB dispositions\n\n" . join('', map { sprintf "%-12s %-20s #%d\n", @$_ } @out));
    \@out;
}
$ACT{drop_drs} = sub {
    my ($n, $tk, %a) = @_;
    my %fixes = (2 => [1], 3 => [2], 4 => [3], 6 => [5, 8], 7 => [4]);
    my $pc = prime_changes($n, $a{drop});
    if ($a{drop} == 6) { for my $i (grep { $_->{state} eq 'opened' && grep { $_ eq 'disposition::reject-clarify' } @{ $_->{labels} } } @{ $gl->issues($P) }) {
        $gl->as('jim'); $gl->add_note($P, 'issue', $i->{iid}, "Drop v1.5's MANIFEST explains the rename: the prime's bulletins are \"issued\" in the contract's terms. Accepted now.\n/label ~disposition::accept\n/close") } }
    $gl->as('jim');
    if ($a{drop} == 2) { for my $i (grep { $_->{state} eq 'opened' && grep { $_ eq 'prime-tbd' } @{ $_->{labels} } } @{ $gl->issues($P) }) {
        $gl->add_note($P, 'issue', $i->{iid}, "Drop v1.1 confirms it: `humidity` is an attribute of ObservationRecord. The assumption held.\n/close") } }
    for my $k (@{ $fixes{ $a{drop} } // [] }) { next unless $DR{$k}; $gl->add_note($P, 'issue', $DR{$k}, "Fixed in drop v1." . ($a{drop} - 1) . ", confirmed by the intake.\n/close") }
    1;
};
%DRTEXT = (1 => ['TW-SYS-006 text differs between DOORS and the model', 'TW-SYS-006', 'DOORS says "twice a day"; the model\'s copy does not. The trace job reports it as drift.'],
              2 => ['TW-SYS-012 has no satisfy', 'TW-SYS-012', 'Nothing satisfies TW-SYS-012 in the model; Mast only traces to it.'],
              3 => ['TW-SYS-016 is in DOORS but not in the model', 'TW-SYS-016', 'The trace job lists TW-SYS-016 as not in the model.'],
              4 => ['TW-SYS-011 has no verification case', 'TW-SYS-011', 'No verify relationship names TW-SYS-011.'],
              5 => ['The Legacy Import package is clutter from the document port', '-', 'Battery_old, Copy of SensorSuite, TBD Component and "Requirement from slide 14" are unused or duplicates.'],
              7 => ['WaveSensor is tagged L5 but is a direct part of MooredBuoy (L4)', '-', 'The outline job reports "WaveSensor: tagged L5, first reached at L4". The government copy re-levels it; please correct the v1 stereotype.']);
$ACT{drs} = sub {
    my ($n, $tk, %a) = @_;
    $gl->as('jim');
    my @k = @{ $a{drs} };
    push @k, 7 if $ST{dr7} && !$DR{7} && !grep { $_ == 7 } @k;          # found by the outline ratchet this sprint
    for my $k (@k) {
        my ($title, $id, $what) = @{ $DRTEXT{$k} };
        my $body = "## Discrepancy\n\n| | |\n|---|---|\n| DR number | DR-$k |\n| Prime tracking | (to be assigned by the prime) |\n| Found in drop | v1.0, delivered 2026-10-02 |\n| DOORS id | $id |\n| Severity | 2 |\n\n"
                 . "## What we found\n\n$what\n\n## What we ask the prime to do\n\nCorrect it in the v1 model and say so in the next drop's MANIFEST.\n\n## Closure\n\n- [x] Sent to the prime on " . substr($gl->now, 0, 10) . " by \@jim\n- [ ] Fixed in drop ...\n";
        my $i = $gl->create_issue($P, title => "DR-$k: $title", labels => [ 'type::discrepancy', 'owner::prime', 'severity::2', 'area::requirements', 'phase::port' ], milestone => "Sprint $n", assignees => ['jim'], description => $body);
        $DR{$k} = $i->{iid};
        ev($n, "samples/discrepancy-report-DR-$k.md", $body) if $n <= 6;
    }
    1;
};
$ACT{recipe_review} = sub {
    my ($n, $tk) = @_;
    my $c = flow('jim')->dir;
    my ($out) = run_q($c, $^X, "$ROOT/tools/sysml/req-recipe.pl", '--format', 'text', 'model/requirements/stakeholder', 'model/requirements/system', 'model/requirements/segment');
    ev($n, 'recipe-doors.txt', $out);
    my ($sum) = $out =~ /(requirements=\d+ findings=\d+ missing=\d+)\s*$/;
    my @weak = $out =~ /(weak target verb[^\n]*)/g;
    $tk->{note} = "The recipe on the three DOORS modules: " . ($sum // '?') . ". " . scalar(@weak) . " weak-verb findings; they go to the prime as DR-6.";
    $DRTEXT{6} = ['Weak verbs and missing parts in the DOORS requirement text', '-', "The requirement recipe (tools/sysml/req-recipe.pl) on the DOORS modules: " . ($sum // '') . ". Examples:\n\n" . join("\n", map { "- $_" } @weak[0 .. ($#weak > 4 ? 4 : $#weak)])];
    1;
};
$ACT{doctor} = sub {                                                   # each laptop: kickoff.pl doctor, as its owner (a clean home directory)
    my ($n, $tk) = @_;
    my $u = $tk->{who};
    my $h = "$W/scratch/home-$u"; make_path($h);
    spew("$h/.gitconfig", "[user]\n\tname = $PEOPLE{$u}{name}\n\temail = $u\@example.invalid\n[init]\n\tdefaultBranch = main\n[core]\n\tautocrlf = false\n[pull]\n\tff = only\n[merge]\n\tconflictstyle = diff3\n");
    spew("$h/.vimrc", "source \$KIT/vim/scrum.vim\nsyntax on\n");
    my ($out, $rc);
    { local $ENV{HOME} = $h; local $ENV{GIT_CONFIG_GLOBAL} = "$h/.gitconfig"; delete local $ENV{GITLAB_URL};
      ($out, $rc) = run_q(undef, $^X, "$ROOT/tools/gitlab/kickoff.pl", 'doctor', '--quick', '--local', "$W/gitlab") }
    $out =~ s/\b(perl|git version|VIM - Vi IMproved|curl)\s+v?[\d.]+[^\n]*/$1 (version as installed)/g;    # versions differ by machine
    $out =~ s{\Q$h\E}{~}g;
    ev($n, "doctor-$u.txt", "\$ perl \$KIT/tools/gitlab/kickoff.pl doctor --quick\n$out");
    my ($sum) = $out =~ /(doctor: [^\n]*)/;
    $tk->{note} = "Laptop ready. kickoff.pl doctor: " . ($sum // 'done') . '.';
    1;
};
$ACT{model_mr} = sub {                                                 # the common case: edits to the model through an MR
    my ($n, $tk, %a) = @_;
    my %x = (title => $a{title}, edits => $a{edits}, plant => $a{plant});
    if (($a{conf} // '') eq 'levels') {
        $x{pre} = sub { my $f = shift; my $c = slurp($f->dir . '/sysml.conf'); $c .= "level_tags = L1Network, L2Segment, L3Station, L4Subsystem, L5Assembly, L6Component\n" unless $c =~ /^level_tags/m; spew($f->dir . '/sysml.conf', $c) };
        $x{why} = 'model.pl checks every part def against the level tag the conventions define.';
    }
    if (($a{review} // '') eq 'request_changes') { $x{review} = 'request_changes' }
    $x{draft} = 1 if $a{draft};
    if (grep { ($_->[1] // '') eq 'file' && ($_->[2] // '') =~ /Stations/ && $_->[0] eq 'levels' } @{ $a{edits} // [] }) {   # the ratchet finds WaveSensor's wrong level
        $x{fix} = sub { my $f = shift; tw_edit('wavesensor', $f->dir); $APPLIED{wavesensor} = ['wavesensor']; $ST{dr7} = 1 };
        $x{fix_msg} = "Re-level WaveSensor: a direct part of MooredBuoy is L4\n\nThe outline job found it once Stations had level tags: v1 tags it L5. DR-7 asks the prime to fix it.";
    }
    model_change($n, $tk, %x);
    1;
};
$ACT{rehearsal} = sub { my ($n, $tk) = @_; $tk->{note} = 'Release and hotfix rehearsed in a sandbox project: release/rehearsal -> main, tag, back-merge; hotfix/x -> main and develop.'; 1 };
$ACT{exchange_table} = sub {                                            # generated from the model: what crosses each interface
    my ($n, $tk) = @_;
    model_change($n, $tk, title => 'Generate the data exchange table', why => 'What crosses each interface, generated from the interface items and flow properties.', plant => ($n == 6 ? 'secret' : ''), pre => sub {
        my $f = shift;
        my $t = slurp($f->dir . '/model/library/Interfaces.sysml');
        my (%item, @rows);
        while ($t =~ /item def (\w+) \{(.*?)\n    \}/gs) { my ($i, $b) = ($1, $2); $item{$i} = join(', ', map { "$_->[0] ($_->[1])" } map { [ /attribute (\w+) : (?:ScalarValues::)?(\w+)/ ] } grep { /attribute/ } split /\n/, $b) }
        while ($t =~ /port def (\w+) \{(.*?)\n    \}/gs) {
            my ($p, $b) = ($1, $2);
            for my $l (split /\n/, $b) { if ($l =~ /(out|in|inout) (item|attribute) (\w+) : (\w+)(?: \{ doc \/\* (.*?) \*\/ \})?/) { push @rows, "| $p | $3 | $1 | $4 | " . ($item{$4} // '-') . " | " . ($5 // '') . " |" } }
        }
        spew($f->dir . '/docs/data-exchange.md', "# Data exchange table\n\nGenerated from model/library/Interfaces.sysml (sprint $n). What crosses each interface, as the model says it.\n\n"
             . "| Interface | Flow | Direction | Type | Fields | Notes |\n|---|---|---|---|---|---|\n" . join("\n", @rows) . "\n");
    });
    1;
};
$ACT{results_gov} = sub {
    my ($n, $tk) = @_;
    model_change($n, $tk, title => 'Inspection verdicts, signed', why => 'Inspection and analysis verdicts are entered and signed by a person, in the results schema the VCRM reads.', pre => sub {
        my $f = shift;
        spew($f->dir . '/verification/results-gov.csv', "requirement,case,verdict,commit,environment,timestamp,signed_by\n"
             . "TW-SYS-010,DemonstratePublication,passed," . substr($f->git('rev-parse', 'HEAD'), 0, 8) . ",government inspection," . $gl->now . ",jim\n"
             . "TW-SEG-001,TestStationObservations,passed," . substr($f->git('rev-parse', 'HEAD'), 0, 8) . ",government inspection," . $gl->now . ",jim\n");
    });
    1;
};
$ACT{release} = sub {                                                   # a release branch, the CCB, the tag, the back-merge
    my ($n, $tk, %a) = @_;
    my $f = flow('tom');
    $f->sync;
    $gl->as('tom');
    $f->start(release => $a{name});
    my $cl = slurp($f->dir . '/CHANGELOG.md');
    my $date = substr($gl->now, 0, 10);
    my @closed = map { "- $_->{plan}{title} ($_->{id})" } grep { $_->{done_d} && $_->{done_d} le $date } @STORIES;
    my $entry = "## [$a{name}] -- $date\n\nInterim baseline for the program review.\n\n" . join("\n", @closed[ ($#closed > 11 ? $#closed - 11 : 0) .. $#closed ]) . "\n";
    $cl =~ s/## \[Unreleased\]\n/## [Unreleased]\n\n$entry/;
    spew($f->dir . '/CHANGELOG.md', $cl);
    regen($f);
    $f->commit("Prepare $a{name}: CHANGELOG and docs");
    my $mr = $f->finish(title => "Release $a{name}", description => "## Release $a{name}\n\nCloses #$tk->{iid}\n\n- [x] Pipeline green\n- [ ] CCB concurrence recorded below by the deputy PM\n",
                        labels => ['workflow::review'], milestone => "Sprint $n", reviewers => ['jim']);
    push @{ $SPRINT_MRS{$n} }, $mr->{iid};
    $gl->tick(3600);
    $gl->as('dpm');
    $gl->add_note($P, 'mr', $mr->{iid}, "CCB concurrence for $a{name}: the board reviewed the change list and the pipeline and concurs. -- Deputy PM, for the CCB");
    $gl->as('jim');
    $gl->approve_mr($P, $mr->{iid});
    $gl->as('tom');
    $gl->merge_mr($P, $mr->{iid});
    my $r = $f->after_release($mr, notes => "Baseline $a{name}.\n");
    my $tagpl = (grep { $_->{ref} eq $a{name} } @{ $gl->pipelines($P) })[-1];
    keep_log($n, $tagpl, "tag-$a{name}");
    ev($n, "release/$a{name}.json", $JSON->encode((grep { $_->{tag_name} eq $a{name} } @{ $gl->releases($P) })[0] // {}));
    $gl->tick(1800);
    $gl->as('jim');
    $gl->approve_mr($P, $r->{mr}{iid});
    $gl->as('tom');
    $gl->merge_mr($P, $r->{mr}{iid});
    $F{$_} && $F{$_}->sync for @TEAM;
    $ST{baselines}{ $a{name} } = { sha256 => $r->{sha256}, pipeline => $tagpl ? $tagpl->{status} : 'none' };
    port_completeness($n, $a{name}) if $a{name} eq 'baseline-1';
    return_deliverable($n, $a{name}, $r->{sha256}) if $a{name} =~ /^baseline-[12]$/;
    1;
};
sub port_completeness {                                                 # the port's acceptance record at baseline 1
    my ($n, $tag) = @_;
    my $c = export_develop();
    my ($dr) = sort { $b cmp $a } glob("$c/imports/*/tidewater.xmi");
    my ($xr) = run_q(undef, $^X, "$ROOT/bin/xmi2sysml.pl", '--report', $dr);
    my ($reqif) = sort { $b cmp $a } glob("$c/imports/*/tidewater.reqif");
    my ($tr) = run_q(undef, $^X, "$ROOT/bin/reqif2sysml.pl", '--report', '--model', CIJob::model_side("$c/model"), $reqif);
    my $todo = 0; File::Find::find({ no_chdir => 1, wanted => sub { $todo += () = (slurp($_) // '') =~ m{// TODO}g if /\.sysml$/ && -f } }, "$c/model");
    my %kinds; File::Find::find({ no_chdir => 1, wanted => sub { return unless /\.sysml$/ && -f; my $x = slurp($_); $kinds{$1}++ while $x =~ /^\s*((?:part|port|item|action|attribute|enum|constraint|state|requirement|verification|use case|metadata)) def\b/mg } }, "$c/model");
    my ($scope) = $xr =~ /(ported vs remaining[^\n]*)/;
    my $txt = "Port completeness at $tag (" . substr($gl->now, 0, 10) . ")\n\n1. Converter: " . ($scope // '?') . "\n2. TODO lines left in the v2 model: $todo\n"
            . "3. Definitions in the v2 model by kind:\n" . join('', map { sprintf "     %-14s %d\n", $_, $kinds{$_} } sort keys %kinds)
            . "4. Trace against DOORS (" . ($reqif =~ s{.*/imports/}{imports/}r) . "):\n" . join('', map { "     $_\n" } grep { /^[CFGI] |^text differs|^drift|^orphans|^unverified|^not in the model/ } split /\n/, $tr)
            . "5. Sampled side-by-side review: Stations, DataCenter and BuoyModes read against the v1 diagrams by Bob and Jim; no differences beyond the DRs.\n"
            . "6. Sign-off: the deputy PM's comment on the baseline-1 release MR.\n";
    ev($n, 'port-completeness.txt', $txt);
}
sub return_deliverable {                                                # the government's v2 baseline back to the prime, controlled
    my ($n, $tag, $sha) = @_;
    my $md = "$W/scratch/transmittal-$tag.md";
    spew($md, "## Memorandum for Northwind Marine Systems, Tidewater model lead\n## From: Tidewater government MBSE lead (Jim)\n## Subject: Transmittal of the government SysML v2 model, $tag\n\n"
        . "1. Enclosed is the government's SysML v2 text model of Tidewater at $tag: the .sysml files, the generated tables, the verification "
        . "cross-reference matrix and the toolchain record, as the package tidewater-model/$tag.\n\n2. The package's docs hash is sha256=$sha. The tag rebuilds "
        . "identically in the government pipeline.\n\n3. There is no conversion from SysML v2 back to SysML v1. The package is for reference and comparison; the "
        . "authoritative v1 model remains the prime's under CDRL A003.\n\n4. Point of contact: the government MBSE lead.\n");
    my ($o, $rc) = run_q(undef, $^X, "$ROOT/tools/memo/memo-build.pl", '--text-only', '--out', "$W/scratch", $md);
    my $memo = slurp("$W/scratch/transmittal-$tag.txt") // slurp($md);
    $gl->as('jim');
    my $i = $gl->create_issue($P, title => "Return deliverable to the prime: tidewater-model $tag", labels => [ 'type::story', 'owner::gov', 'work::engineering', 'area::requirements' ],
        milestone => "Sprint $n", assignees => ['jim'], description => "## Transmittal record\n\n| | |\n|---|---|\n| What | tidewater-model/$tag (package registry): .sysml text, generated tables, VCRM, toolchain |\n"
        . "| Docs hash | sha256=$sha |\n| To | Northwind Marine Systems, Tidewater model lead, through the contracting channel |\n| Sent | " . substr($gl->now, 0, 10) . " |\n\n"
        . "> [!note]\n> No v2 -> v1 conversion exists: the package is for reference; the prime's v1 model stays authoritative.\n\n<details><summary>Transmittal memo</summary>\n\n```text\n$memo```\n</details>\n");
    $gl->add_note($P, 'issue', $i->{iid}, "Sent.\n/close");
    ev($n, "return-deliverable-$tag.md", $gl->issue($P, $i->{iid})->{description});
}
$ACT{hotfix} = sub {
    my ($n, $tk, %a) = @_;
    $tk->{note} = "hotfix/$a{name}: the wrong satisfy corrected on main and merged back to develop.";
    1;
};
$ACT{briefing} = sub { my ($n, $tk) = @_; $ST{briefing_due} = 1; 1 };
$ACT{kit_pin} = sub {
    my ($n, $tk) = @_;
    model_change($n, $tk, title => 'Pin the kit version', why => 'The kit is a tool like any other: a new version reaches the model through a reviewed MR.', pre => sub { spew(shift->dir . '/.kit-version', "agile-kit 2026.10\n") });
    1;
};
$ACT{tokens} = sub {
    my ($n, $tk) = @_;
    $gl->as('tom');
    my $dt = $gl->create_deploy_token($P, 'nwm-jenkins', ['write_package_registry'], expires_at => '2028-06-30');
    my $tr = $gl->create_trigger($P, "Prime Jenkins: drop delivered");
    $ST{deploy_token} = $dt->{token}; $ST{trigger_token} = $tr->{token};
    $tk->{note} = "Deploy token $dt->{username} (write_package_registry, expires 2028-06-30) and a pipeline trigger token handed to the prime through the contract channel.";
    1;
};
$ACT{intake} = sub {                                                    # the prime's Jenkins uploads and triggers; the intake job checks
    my ($n, $tk, %a) = @_;
    my $d = $a{drop}; my $v = 'v1.' . ($d - 1);
    if (!$ST{trigger_token}) { $tk->{note} = 'Drop received by file transfer.'; return 1 }
    $gl->as('tom');
    for my $file (sort glob(drop_dir($d) . '/*')) { $gl->package_put($P, 'prime-drop', $v, $file, deploy_token => $ST{deploy_token}) }
    my $pl = $gl->trigger_pipeline($P, $ST{trigger_token}, 'develop', variables => { DROP_VERSION => $v, INTAKE_DROP_DIR => "$W/gitlab/packages/$P/prime-drop/$v" });
    keep_log($n, $pl, "intake-$v") if $pl;
    $tk->{note} = "The prime's Jenkins uploaded $v to the package registry and triggered pipeline #" . ($pl ? "$pl->{id} ($pl->{status})" : '?') . '.';
    1;
};

# ======================================================================== the run
my $PLAN = tw_plan();
my @ALLDAYS;
for my $n (1 .. $o{sprints}) { push @ALLDAYS, map { [ $n, $_ ] } sprint_days($n) }
my %DAYIDX; $DAYIDX{ $ALLDAYS[$_][1] } = $_ for 0 .. $#ALLDAYS;
my @extra_days = map { [ 0, $_ ] } grep { my $w = dow($_); $w >= 1 && $w <= 5 && !$HOLIDAY{$_} } map { add_days(sprint_start($o{sprints} + 1), $_) } 0 .. 20;   # spill-over days
my @CAL = map { $_->[1] } @ALLDAYS, @extra_days;
my %CALIDX; $CALIDX{ $CAL[$_] } = $_ for 0 .. $#CAL;

# week zero, 2026-09-29 .. 10-02 (outside the sprints): what the team did before sprint 1, in hours (planned and recorded)
ev(0, 'week-zero.txt', <<'WZ');
Week zero, Tuesday 2026-09-29 to Friday 2026-10-02 -- before sprint 1 (hours per person; outside the sprint backlog)

Date        Who   Hours  Activity
2026-09-24  all    1.0   The directive meeting: the program manager reads the DevSecOps memo to the team (docs/tidewater/memos/2026-09-24-directive)
2026-09-29  jim    2.0   Kickoff with the program manager and deputy PM: the twelve-week scorecard agreed (chapter 4)
2026-09-29  tom    2.5   Software request for Git for Windows and Vim on three laptops; kickoff.pl doctor on Tom's own laptop (2 FAIL, 4 WARN)
2026-09-30  tom    1.5   kickoff.pl scaffold: the model repository skeleton; kickoff.pl start --dry-run read with Jim
2026-09-30  jim    1.5   First meeting with the ISSM: what the runner and the repository will hold (notional, unclassified)
2026-10-01  jim    2.0   Decisions D-1 .. D-10 drafted (recorded as ADRs in sprint 2)
2026-10-01  bob    3.0   Practice repository: clone, branch, commit, merge (the primer's git chapter); "configuration management with fewer forms"
2026-10-02  jim    1.0   Delivery agreement call with the prime's modeler: stable xmi:ids, DRs that cite v1 ids, a MANIFEST with every drop
2026-10-02  jim    0.5   Drop 1 (v1.0) arrives by CDRL file transfer
Total              15.0  hours across the three, about 2 person-days: not in sprint 1's capacity
WZ

# the drops on their delivery dates
make_path("$W/drops");
for my $d (1 .. 7) { my $v = 'v1.' . ($d - 1); my ($o2, $rc) = run_q(undef, $^X, "$ROOT/sim/tidewater-v1.pl", '--drop', $d, "$W/drops/$v"); die "drop $d: $o2" if $rc }

sub person_days { my ($u, $from) = @_; grep { working($u, $CAL[$_]) } $from .. $#CAL }
sub schedule_sprint {                                                   # task dates: each person's points, laid end to end, at their pace
    my ($n, @stories) = @_;
    my $first = $CALIDX{ (sprint_days($n))[0] };
    my %cur;
    my (%pts, %pace);                                                   # pace: the person's points spread over their working days, at most K
    $pts{ $_->{who} } += $_->{p} for grep { !$_->{done} } map { @{ $_->{tasks} } } @stories;
    for my $u (@TEAM) { my $wd = grep { working($u, $_) } sprint_days($n); $pace{$u} = $pts{$u} ? $wd / $pts{$u} : $K{$u}; $pace{$u} = $K{$u} if $pace{$u} > $K{$u}; $pace{$u} = 0.5 if $pace{$u} < 0.5 }
    my %vend;
    my $dep = sub { $_[0]{act}[0] =~ /^(drop_merge|drop_rework|drop_drs)$/ ? 1 : 0 };
    for my $pass (0, 1) {                                                # tasks that wait on someone else's go last in their owner's queue
    for my $st (@stories) {
        for my $tk (@{ $st->{tasks} }) {
            next if $dep->($tk) != $pass;
            next if $tk->{end_d} && $tk->{done};
            my $u = $tk->{who};
            my @pd = person_days($u, $first);
            my $c = $cur{$u} // 0;
            if ($pass && $vend{ $st->{key} }) { my ($vi) = grep { $pd[$_] >= $vend{ $st->{key} } } 0 .. $#pd; $c = $vi if defined $vi && $vi > $c }
            my $len = $tk->{p} * $pace{$u};
            my $s = floor($c); my $e = ceil($c + $len) - 1; $e = $s if $e < $s;
            $e += $tk->{late} if $tk->{late};
            if ($tk->{day}) {                                                # a task pinned to a day (the S6 showcase day)
                my ($di) = grep { $CAL[ $pd[$_] ] eq $tk->{day} } 0 .. $#pd;
                if (defined $di) { $e = $di; my $s1 = $di - ceil($len) + 1; $s = $s1 if $s1 > $s; $s = $di if $s > $di }   # it runs only its own length, ending that day
            }
            if ($st->{plan}{carry} && $tk == $st->{tasks}[-1] && $n == $st->{sprint}) {   # planned to spill: it finishes early next sprint
                my $last = $CALIDX{ (sprint_days($n))[-1] };
                my ($li) = grep { $pd[$_] > $last } 0 .. $#pd;
                $e = $li + 1 if defined $li && $e < $li + 1;
                my $s2 = $e - ceil($len) + 1; $s2 = $li - 1 if $li - 1 > $s2; $s = $s2 if $s2 > $s;          # it starts late in the sprint and runs over the boundary, not for two weeks
            }
            if ($tk->{block}) {                                          # [DAY of the task, DAYS blocked, WHY, POSTED after N days]: counted on the person's working days
                my ($bd, $bn, $why, $late) = @{ $tk->{block} };
                my $b0 = $s + $bd - 1;
                $tk->{blocked_from} = $CAL[ $pd[$b0] ]; $tk->{blocked_to} = $CAL[ $pd[ $b0 + $bn - 1 ] // $pd[-1] ]; $tk->{blocked_why} = $why;
                $tk->{blocked_posted} = $CAL[ $pd[ $b0 + ($late // 0) ] // $pd[$b0] ];   # a wait spoken only on its Nth day: invisible until then
                $e = $b0 + $bn if $e < $b0 + $bn }                          # it finishes after the block
            $tk->{start_d} = $CAL[ $pd[$s] ]; $tk->{end_d} = $CAL[ $pd[$e] // $pd[-1] ];
            $vend{ $st->{key} } = $pd[$e] if $tk->{act}[0] eq 'vendor';
            $cur{$u} = ($pass ? $e + 1 : $c + $len);
        }
    }
    }
}

# ======================================================================== the front door: DevSecOps requests from Windchill
# Users of the program (station leads, the data center, operations, the program office) submit requests in Windchill.
# At each refinement Jim exports the open "DevSecOps Request" report as CSV and imports it with `gitlab.pl windchill
# intake` into tidewater/requests, the team's intake project (a separate project, so the model project's issues stay the
# team's own work). Jim and the deputy PM disposition each request there: accept (linked to the story that delivers it),
# defer (with the sprint or the condition), or decline (with the reason). At each review `gitlab.pl windchill status
# --csv` goes back to Windchill's CM, who updates the requests; the next export shows those states (drift, noted).
my @WC = (   # number, arrives at the refinement of sprint N, requester, priority, need date, title, description, disposition
    { n => 'WC-000101', at => 1, by => 'Pat Lee (station lead, North Shore)', pri => 'High', need => '12/04/2026', title => 'Nightly model check summary the station leads can open',
      text => 'The station leads want the nightly model check (lint, outline, trace) as one page they can open without a GitLab account, every weekday morning.',
      disp => 'accept', story => 'S4-pages', why => 'Accepted: delivered by the model site on GitLab Pages, rebuilt nightly, planned for sprint 4.' },
    { n => 'WC-000102', at => 1, by => 'Dana Wu (data center engineering)', pri => 'Medium', need => '11/13/2026', title => 'Read access to the model for the data center engineers',
      text => 'Two data center engineers need to read the v2 model and its documents to plan the ingest changes.',
      disp => 'accept', done_at => 2, why => 'Accepted: Reporter access once drop 1 is on develop (sprint 2); granted at the sprint 2 review.' },
    { n => 'WC-000103', at => 2, by => 'Lee Grant (operations requirements)', pri => 'High', need => '12/18/2026', title => 'Which DOORS requirements are in the model, and which are verified',
      text => 'Operations needs a list of the DOORS system requirements with, for each, whether the model satisfies it and whether a verification case exists.',
      disp => 'accept', story => 'S3-doors', why => 'Accepted: the DOORS modules come into the model in sprint 3 and the trace report lists exactly this.' },
    { n => 'WC-000104', at => 2, by => 'Pat Lee (station lead, North Shore)', pri => 'Low', need => '11/27/2026', title => 'Weekly PowerPoint export of the Cameo diagrams',
      text => 'Please export the station diagrams from Cameo to PowerPoint every Friday for the station leads meeting.',
      disp => 'decline', why => 'Declined: the government model is SysML v2 text; its diagrams are generated on every merge and the model site (sprint 4, WC-000101) shows the current ones. A weekly export would be a copy that is wrong by Monday.' },
    { n => 'WC-000105', at => 3, by => 'Dana Wu (data center engineering)', pri => 'High', need => '12/11/2026', title => 'Units on the sensor parameters (wind in knots or m/s?)',
      text => 'The ingest service had to guess the wind speed unit. Every sensor parameter in the model should carry its unit.',
      disp => 'accept', story => 'S4-types', why => 'Accepted: units and value types are a sprint 4 story.' },
    { n => 'WC-000106', at => 3, by => 'Morgan Diaz (systems engineering group)', pri => 'Medium', need => '03/31/2027', title => 'Observation latency budget: station to published bulletin',
      text => 'The system requirement allows a fixed time from observation to bulletin. SE needs the budget split across station, network, data center and publication, checked when the model changes.',
      disp => 'defer', why => 'Deferred: a timing budget needs behavior and constraints in the model (planned for sprint 7 onward: the EnergyBalance constraint is the first). Revisit at the sprint 7 refinement.', reprio => [5, 'High'] },
    { n => 'WC-000107', at => 4, by => 'Lee Grant (operations requirements)', pri => 'Medium', need => '01/22/2027', title => 'Check our requirement wording before the prime\'s next review',
      text => 'Operations is writing new segment requirements and wants them checked against the program\'s requirement recipe before they go to the prime.',
      disp => 'accept', story => 'S5-recipe', why => 'Accepted: grading requirements with the recipe is a sprint 5 story; operations\' drafts are graded with the same tool.' },
    { n => 'WC-000108', at => 4, by => 'Chris Ames (prime liaison)', pri => 'Medium', need => '12/18/2026', title => 'Write access to the government repository for the prime\'s modelers',
      text => 'The prime asks for Developer access so its modelers can push fixes directly into the government model.',
      disp => 'decline', why => 'Declined: the prime delivers through drops onto vendor/prime (ADR 0003); the government model is the government\'s configuration. The prime keeps Reporter access and files discrepancy responses as usual.' },
    { n => 'WC-000109', at => 5, by => 'Program office', pri => 'High', need => '12/24/2026', title => 'Data exchange table for the program review',
      text => 'The program review needs a table of every data exchange between segments, with the interface and the requirement behind it.',
      disp => 'accept', story => 'S6-exchange', why => 'Accepted: generated from the model in sprint 6, for the review on 12-24.' },
    { n => 'WC-000110', at => 5, by => 'Sam Ortiz (operations)', pri => 'Medium', need => '01/15/2027', title => 'Buoy operating modes diagram for the operations manual',
      text => 'The operations manual needs the buoy\'s modes and the transitions between them, current with the design.',
      disp => 'accept', story => 'S6-buoymodes', why => 'Accepted: the BuoyModes state machine is a sprint 6 story; the diagram is generated from it.' },
    { n => 'WC-000111', at => 5, by => 'Pat Lee (station lead, North Shore)', pri => 'Medium', need => '02/26/2027', title => 'Add the new tide gauge vendor\'s sensor to the station',
      text => 'Stations will receive a second tide gauge model next spring. Please add it to the station design.',
      disp => 'defer', why => 'Deferred to the prime: the station design is the prime\'s; the change arrives in a drop (a prime change request) and is dispositioned then. Tracked as prime-tbd.' },
    { n => 'WC-000112', at => 6, by => 'Riley Chen (communications contractor)', pri => 'Medium', need => '02/12/2027', title => 'DailyUpload sequence for the communications contractor',
      text => 'The communications contractor needs the daily upload interaction (who sends what, in what order) to size the satellite link.',
      disp => 'accept', story => 'S7-thedailyuplo', why => 'Accepted: the DailyUpload interaction is a sprint 7 story.' },
    { n => 'WC-000113', at => 6, by => 'Program office', pri => 'Low', need => '01/08/2027', title => 'Weekly progress in the program office spreadsheet',
      text => 'Please fill in the program office progress spreadsheet every Friday.',
      disp => 'decline', why => 'Declined, with an alternative: the weekly note (every Friday) and the Insights dashboard in GitLab carry the same numbers, current; the program office has Reporter access to both.' },
);
my %WCN = map { $_->{n} => $_ } @WC;
my $WCCFG;
sub wc_cfg { $WCCFG //= do { require Windchill; (Windchill::config_file("$ROOT/tools/gitlab/templates/requests.conf"))[0] } }
sub wc_state {                                                           # what Windchill says about a request at the refinement of sprint K
    my ($r, $k) = @_;
    return 'Open' if $k == $r->{at};
    return 'Implemented' if $r->{closed_sprint} && $r->{closed_sprint} < $k;
    return 'Rejected' if $r->{disp} eq 'decline';
    return 'Approved';
}
sub wc_prio { my ($r, $k) = @_; $r->{reprio} && $k >= $r->{reprio}[0] ? $r->{reprio}[1] : $r->{pri} }
sub wc_q { my $v = shift; $v =~ /[",\n]/ ? '"' . ($v =~ s/"/""/gr) . '"' : $v }
sub wc_export {                                                          # the Windchill report Jim exports before refinement -> the file
    my ($n, $d) = @_;
    my @rows = grep { $_->{at} <= $n && !($_->{closed_sprint} && $_->{closed_sprint} < $n - 1) } @WC;   # the report lists open and recently closed requests
    my ($m, $dd, $y) = (substr($d, 5, 2), substr($d, 8, 2), substr($d, 0, 4));
    my $csv = "Number,Name,Type,State,Created By,Priority,Need Date,Created On,Description\n"
        . join('', map { my $r = $_; my $c = sprint_start($r->{at}); join(',', map { wc_q($_) } $r->{n}, $r->{title}, 'DevSecOps Request', wc_state($r, $n), $r->{by}, wc_prio($r, $n), $r->{need},
                         sprintf('%s/%s/%s', substr($c, 5, 2), substr($c, 8, 2), substr($c, 0, 4)), $r->{text}) . "\n" } @rows);
    my $f = "$W/windchill/export-$d.csv"; spew($f, $csv);
    ev($n, "windchill/export-$d.csv", $csv);
    $f;
}
sub wc_refinement {                                                      # export -> intake -> disposition, at the refinement of sprint N
    my ($n, $d, $next) = @_;
    my $file = wc_export($n, $d);
    $gl->as('jim');
    require Windchill;
    my $r = Windchill::intake($gl, $REQ, $file, wc_cfg(), note => 1);
    my $out = "perl \$KIT/bin/gitlab.pl --project $REQ windchill intake --conf requests.conf --note export-$d.csv\n" . join('', map { "$_\n" } @{ $r->{lines} });
    my %by = map { my $m = Windchill::read_marker($_->{description}); $m ? ($m->{number} => $_) : () } @{ $gl->issues($REQ, state => 'all') };
    my %story = map { $_->{key} => $_ } @$next;
    my @disp;
    for my $w (@WC) {
        my $i = $by{ $w->{n} } or next;
        $w->{iid} = $i->{iid};
        my $st = $w->{story} ? $story{ $w->{story} } : undef;
        if ($w->{at} == $n) {                                               # new today: the disposition, recorded on the request
            $gl->as('jim');
            my $lab = $w->{disp} eq 'decline' ? '~"disposition::decline" ~"workflow::done"' : $w->{disp} eq 'defer' ? '~"disposition::defer" ~"workflow::ready"' : '~"disposition::accept" ~"workflow::ready"';
            $gl->add_note($REQ, 'issue', $i->{iid}, "Refinement $d (Jim, with the deputy PM): $w->{why}\n/label $lab" . ($w->{disp} eq 'decline' ? "\n/close" : ''));
            push @disp, sprintf '%-9s #%-3d %-8s %s', $w->{n}, $i->{iid}, $w->{disp}, $w->{why};
            logd($d, 'jim', "dispositioned $w->{n} ($w->{disp}) in $REQ#$i->{iid}");
        }
        if ($st && !$w->{linked}) {                                         # the story that delivers it was filed today
            $gl->as('jim');
            $gl->create_milestone($REQ, 'Sprint ' . ($n + 1)) unless grep { $_->{title} eq 'Sprint ' . ($n + 1) } @{ $gl->milestones($REQ) };
            $gl->add_note($REQ, 'issue', $i->{iid}, "Planned: $P#$st->{iid} ($st->{id}, $st->{plan}{title}) in Sprint " . ($n + 1) . ".\n/milestone %\"Sprint " . ($n + 1) . "\"");
            $gl->add_note($P, 'issue', $st->{iid}, "Delivers the Windchill request $w->{n} ($REQ#$i->{iid}).");
            $w->{linked} = $st;
            push @disp, sprintf '%-9s #%-3d planned  %s %s in Sprint %d', $w->{n}, $i->{iid}, "$P#$st->{iid}", $st->{id}, $n + 1;
        }
        if ($w->{done_at} && !$w->{closed_sprint} && $w->{done_at} == $n + 1) {   # a request done by an action, not a story: planned into the next sprint
            $gl->create_milestone($REQ, 'Sprint ' . ($n + 1)) unless grep { $_->{title} eq 'Sprint ' . ($n + 1) } @{ $gl->milestones($REQ) };
            $gl->add_note($REQ, 'issue', $i->{iid}, '/milestone %"Sprint ' . ($n + 1) . '"');
        }
    }
    ev($n, 'windchill/intake.txt', $out . (@disp ? "\nDispositions and plans recorded on the requests:\n" . join('', map { "  $_\n" } @disp) : ''));
}
sub wc_story_done {                                                      # a story that delivers a request closed: the request closes too
    my ($n, $d, $st) = @_;
    for my $w (grep { $_->{linked} && $_->{linked} == $st && !$_->{closed_sprint} } @WC) {
        $gl->as('jim');
        $gl->add_note($REQ, 'issue', $w->{iid}, "Delivered: $P#$st->{iid} ($st->{id}) closed on $d, in Sprint $n.\n/label ~\"workflow::done\"\n/close");
        $w->{closed_sprint} = $n;
        logd($d, 'jim', "closed $w->{n} ($REQ#$w->{iid}): delivered by $st->{id}");
    }
}
sub wc_review {                                                          # the review: actions due this sprint, then the status sheet back to Windchill
    my ($n, $d) = @_;
    for my $w (grep { $_->{done_at} && $_->{done_at} == $n && !$_->{closed_sprint} && $_->{iid} } @WC) {
        $gl->as('tom');
        $gl->add_member($P, 'dc-eng', 'reporter') if $w->{n} eq 'WC-000102' && eval { $gl->create_user('dc-eng', name => 'Data center engineering', email => 'dc-eng@example.invalid'); 1 };
        $gl->add_note($REQ, 'issue', $w->{iid}, "Done at the sprint $n review: the data center engineers have Reporter access to $P.\n/label ~\"workflow::done\"\n/close");
        $w->{closed_sprint} = $n;
    }
    require Windchill;
    my $rows = Windchill::status($gl, $REQ, wc_cfg());
    ev($n, 'windchill/status.csv', Windchill::status_csv($rows));
    ev($n, 'windchill/status.txt', "perl \$KIT/bin/gitlab.pl --project $REQ windchill status --conf requests.conf --csv windchill-status-$d.csv\n\n" . Windchill::status_text($rows));
}

my (%SCORE, %MORALE);
my %WEEKLY;
my $yesterday;
my @CARRY;                                                              # stories carried into the next sprint
for my $n (1 .. $o{sprints}) {
    my $sp = $PLAN->[ $n - 1 ];
    my @days = sprint_days($n);
    say_("sprint $n ($days[0] .. $days[-1]): $sp->{goal}");
    make_path(sprintf "$W/sprints/%02d", $n);
    # the sprint's stories: carried ones first, then the plan's
    my @new = $sp->{_filed} ? @{ $sp->{_filed} } : map { my $s = $_; my $r = { key => $s->{key}, plan => $s, sprint => $n, epic => $s->{epic}, work => $s->{work}, area => $s->{area},
                                          tasks => [ map { +{ %$_, act => $_->{act} // ['note'] } } @{ $s->{tasks} } ] };
                    $_->{story} = $r for @{ $r->{tasks} }; $r->{pts} = 0; $r->{pts} += $_->{p} for @{ $r->{tasks} }; $r } @{ $sp->{stories} };
    my @mine = (@CARRY, @new);
    @CARRY = ();
    if ($n == 1) {                                                       # 08:00 day 1: the project is created before the kickoff
        at_($days[0], 8, 0);
        my ($setup) = grep { $_->{act}[0] eq 'setup' } map { @{ $_->{tasks} } } @new;
        $ACT{setup}->(1, $setup);
        $setup->{early} = 1;
        flow($_) for qw(jim bob);
    }
    if ($n == 12) {                                                      # the prime's notional Station acceptance test campaign
        at_($days[0], 8, 30); $gl->as('jim');
        my $fz = $gl->create_issue($P, title => 'Frozen window: the prime\'s Station acceptance test campaign (Mar 8 - May 28, 2027)', labels => [ 'owner::gov', 'area::verification', 'work::engineering', 'priority::1' ],
            milestone => "Sprint $n", assignees => ['jim'], description => "During the prime's acceptance test campaign no change to the verification process merges: no new verification jobs, "
            . "no change to `verification/`, `ci/job.pl vcrm` or the results schema. Model changes continue. Closes after the campaign's results arrive in drop v1.3.\n");
        $ST{frozen} = $fz->{iid};
    }
    if ($n == 18 && $ST{frozen}) { $gl->as('jim'); $gl->add_note($P, 'issue', $ST{frozen}, "Campaign over; no verification-process change merged during the window.\n/close") }
    # kickoff: story issues (S1; later ones were filed at the previous refinement), poker for S1, tasks cut, commit
    at_($days[0], 9, 30);
    my @unfiled = grep { !$_->{iid} } @new;
    new_story($_, $n) for @unfiled;
    $ST{ $_->{key} } = $_ for @new;
    push @STORIES, @new;
    my $kick = '';
    if (@unfiled) { my $t = poker($days[0], $n, "Sprint $n kickoff", @unfiled); }
    new_tasks($_, $n) for @mine;
    schedule_sprint($n, @mine);
    my $cap = 0; for my $u (@TEAM) { my $wd = grep { working($u, $_) } @days; $cap += $PEOPLE{$u}{cap} * $wd / 10 }
    $cap = 0 + sprintf('%.1f', $cap);
    for my $st (grep { $_->{carried} && !$_->{reestimated}{$n} } @mine) {   # a carried story is re-estimated to the work left
        my $rem = 0; $rem += $_->{p} for grep { !$_->{done} } @{ $st->{tasks} };
        su($days[0], "est $st->{id} $rem") if $rem != $st->{pts};
        $st->{pts} = $rem; $st->{reestimated}{$n} = 1;
    }
    my $committed = 0; $committed += $_->{pts} for @mine;
    su($days[0], "cap $cap");
    for my $st (@mine) {
        if (!$st->{journal}) {
            my $tome = $TW_EPIC{ $st->{epic} }[0];
            (my $t = $st->{plan}{title}) =~ s/"/'/g;
            su($days[0], sprintf qq{new %s %s "%s" p:%d e:"%s %s" t:"%s %s" o:%s}, $st->{id}, $st->{pts}, $t, $st->{plan}{prio} // 2, $st->{epic}, $TW_EPIC{ $st->{epic} }[1], $tome, $TW_TOME{$tome}, $PEOPLE{ $st->{plan}{owner} }{name});
            $st->{journal} = 1;
        }
        su($days[0], "commit $st->{id} $PEOPLE{ $st->{plan}{owner} }{name}");
        $gl->as('jim');
        $gl->update_issue($P, $st->{iid}, milestone => "Sprint $n", add_labels => ['workflow::in-progress']);
    }
    my $plat = 0; $plat += $_->{pts} for grep { $_->{work} eq 'platform' } @mine;
    my $learn = 0; $learn += $_->{pts} for grep { $_->{work} eq 'learning' } @mine;
    $SCORE{$n}{learning_points} = $learn;
    $kick = sprintf "Sprint %d kickoff, %s 09:00 (90 minutes)\n\nGoal: %s\nCapacity: %.1f points (Jim %d, Bob %d, Tom %d per full sprint, less holidays and leave)\nCommitted: %.1f points in %d stories (%d%% of capacity): engineering %.1f, platform %.1f (%d%%), learning %.1f (%d%%)\n\n%s",
        $n, $days[0], $sp->{goal}, $cap, map({ $PEOPLE{$_}{cap} } @TEAM), $committed, scalar @mine, $cap ? 100 * $committed / $cap : 0, $committed - $plat - $learn, $plat, $committed ? 100 * $plat / $committed : 0, $learn, $committed ? 100 * $learn / $committed : 0,
        join('', map { my $s = $_; sprintf("%-8s %-4s %4.1f pts  %-12s %s\n", $s->{id}, $s->{epic}, $s->{pts}, $s->{work}, $s->{plan}{title}) . join('', map { sprintf "           #%-4d %3.1f pt  %-4s %s .. %s  %s\n", $_->{iid}, $_->{p}, $_->{who}, $_->{start_d}, $_->{end_d}, $_->{t} } @{ $s->{tasks} }) } @mine);
    ev($n, 'kickoff.txt', $kick);
    ev($n, 'plan.txt', $kick);
    $gl->as('jim'); $gl->update_milestone($P, "Sprint $n", due_date => $days[-1], description => "Two-week sprint $n: planning on $days[0], review and retrospective on $days[-1] (the last working day).\n\nGoal: $sp->{goal}\n");   # the real review day (holidays move it)
    $SCORE{$n}{committed_points} = $committed; $SCORE{$n}{platform_points} = $plat; $SCORE{$n}{capacity} = $cap;

    for my $di (0 .. $#days) {
        my $d = $days[$di];
        nightly($n, $d) if $SCHEDULE_ON;
        my ($chat, $lint) = standup($d, $n, $yesterday);
        if ($di == 0) { meet($n, $d, q{kickoff (includes the stand-up)}, q{09:00}, q{10:30}, team_on($d)) } else { meet($n, $d, q{stand-up}, q{09:00}, q{09:15}, team_on($d)) }
        showcase_morning($n, $d) if $d eq '2026-12-17';
        s6_documents($n, $d) if $n == 6;
        ev($n, "standups/$d-chat.txt", $chat) if $n <= 6;
        ev($n, "standups/$d-lint.txt", $lint) if $n <= 6;
        ev($n, "standups/$d-talk-drafts.txt", join('', @{ $DRAFTS{$d} })) if $n <= 6 && $DRAFTS{$d};
        # blocks start and end
        for my $tk (map { @{ $_->{tasks} } } @mine) {
            next unless $tk->{blocked_from};
            if (($tk->{blocked_posted} // $tk->{blocked_from}) eq $d) { su($d, "block $tk->{story}{id} $tk->{blocked_why}"); $gl->as($tk->{who}); $gl->add_note($P, 'issue', $tk->{iid}, "Blocked by: $tk->{blocked_why}\n/label ~workflow::blocked") }
            if (($CAL[ $CALIDX{ $tk->{blocked_to} } + 1 ] // '') eq $d) { su($d, "unblock $tk->{story}{id}"); $gl->as($tk->{who}); $gl->add_note($P, 'issue', $tk->{iid}, "Unblocked.\n/label ~workflow::in-progress") }
        }
        # refinement (Wednesday of week 2, 10:00): the next sprint's stories filed, estimated, ready
        if ($d eq ($days[ $#days > 7 ? 7 : $#days ]) && $n < 39) {        # (also past --sprints: a short run's evidence matches a long run's)
            at_($d, 10, 0);
            my $nx = $PLAN->[$n];
            meet($n, $d, q{refinement and planning poker}, q{10:00}, q{11:00}, team_on($d));
            my @next = map { my $s = $_; my $r = { key => $s->{key}, plan => $s, sprint => $n + 1, epic => $s->{epic}, work => $s->{work}, area => $s->{area},
                                                   tasks => [ map { +{ %$_, act => $_->{act} // ['note'] } } @{ $s->{tasks} } ] };
                             $_->{story} = $r for @{ $r->{tasks} }; $r->{pts} = 0; $r->{pts} += $_->{p} for @{ $r->{tasks} }; $r } @{ $nx->{stories} };
            new_story($_, $n + 1) for @next;
            poker($d, $n, "Refinement for sprint " . ($n + 1), @next);
            $PLAN->[$n]{_filed} = \@next;
            wc_refinement($n, $d, \@next) if $n <= 6;
            ev($n, 'refinement.txt', "Refinement, $d 10:00: the Definition of Ready applied to sprint " . ($n + 1) . "'s stories\n\n" . join('', map { "$_->{id}  $_->{pts} pts  $_->{plan}{title}\n" } @next));
        }
        # tasks that start today are marked in progress (GitLab's record of when work began)
        for my $tk (grep { !$_->{done} && !$_->{started} && !$_->{early} && ($_->{start_d} // '') eq $d } map { @{ $_->{tasks} } } @mine) {
            at_($d, 9, 30); $gl->as($tk->{who}); $gl->add_note($P, 'issue', $tk->{iid}, '/label ~workflow::in-progress'); $tk->{started} = 1;
        }
        # the day's work, in the order it finishes
        my @due = sort { ($a->{early} // 0) <=> ($b->{early} // 0) || $a->{story}{iid} <=> $b->{story}{iid} || $a->{iid} <=> $b->{iid} }
                  grep { !$_->{done} && $_->{end_d} eq $d } map { @{ $_->{tasks} } } @mine;
        my $slot = 0;
        for my $tk (@due) {
            at_($d, 10, 0); $gl->tick(2700 * $slot++);
            $gl->as($tk->{who});
            $gl->add_note($P, 'issue', $tk->{iid}, '/label ~workflow::in-progress') unless $tk->{early} || $tk->{started};
            my ($name, @args) = @{ $tk->{act} };
            $ACT{$name} or die "no action '$name'\n";
            $ACT{$name}->($n, $tk, @args) unless $tk->{early};
            $gl->as($tk->{who});
            my $i = $gl->issue($P, $tk->{iid});
            if ($i->{state} eq 'opened') { $gl->add_note($P, 'issue', $tk->{iid}, ($tk->{note} // "Done: $tk->{t}.") . "\n/spend $tk->{p}d\n/label ~workflow::done\n/close") }
            else { $gl->add_note($P, 'issue', $tk->{iid}, "/spend $tk->{p}d\n/label ~workflow::done") }
            $tk->{done} = $d;
            logd($d, $tk->{who}, "closed #$tk->{iid} $tk->{t}");
            my $st = $tk->{story};
            if (!grep { !$_->{done} } @{ $st->{tasks} }) {
                $gl->as('jim');
                $gl->add_note($P, 'issue', $st->{iid}, "All tasks closed; the acceptance criteria hold.\n/label ~workflow::done\n/close");
                $st->{done_d} = $d;
                su($d, "done $st->{id}");
                wc_story_done($n, $d, $st);
            }
        }
        # schedules (nightly) up to the end of the day

        # the last day: review, retro (the carry lines go into today's stand-up file)
        my @open = grep { !$_->{done_d} } @mine;
        su($d, "carry " . join(' ', map { $_->{id} } @open)) if $di == $#days && @open;
        if ($di == $#days) {                                        # re-estimated to the work left, on the carry day (the journal applies est before the next commit)
            for my $st (@open) { my $rem = 0; $rem += $_->{p} for grep { !$_->{done} } @{ $st->{tasks} }; if ($rem != $st->{pts}) { su($d, "est $st->{id} $rem"); $st->{pts} = $rem } }
        }
        compile_day($d, $n);
        # Friday: the weekly quad, from the journal as it stands tonight
        if (dow($d) == 5) {
            my $s = load("$J/scrum.txt", today => $d);
            require Quad;
            my $q = eval { Quad::quad_text($s, team => 'Model') } // "quad: $@";
            ev($n, "quad-$d.txt", $q);
        }
        if (dow($d) == 5 || ($di == $#days && dow($d) != 5)) {           # the weekly note to management beside the quad: talk.pl weekly drafts it, Jim sends it
            at_($d, 15, 0);
            $gl->save;
            my ($wn) = run_q(undef, $^X, "$ROOT/tools/gitlab/talk.pl", '--local', "$W/gitlab", '--project', $P, 'weekly', '--date', $d, '--md');
            ev($n, "weekly-note-$d.md", $wn) if $wn;
        }
        if ($di == $#days) { meet($n, $d, q{sprint review (demo)}, q{10:00}, q{11:00}, team_on($d), q{Deputy PM}, ($n % 2 == 0 ? q{Program manager} : ())); meet($n, $d, q{retrospective}, q{11:00}, q{12:00}, team_on($d)) }
        wc_review($n, $d) if $di == $#days && $n <= 6;
        end_of_sprint($n, $sp, $d, \@mine) if $di == $#days;
        $yesterday = $d;
    }
    ev($n, q{meetings.csv}, "date,meeting,start,end,attendees\n" . join(q{}, map { join(q{,}, @$_) . "\n" } @{ $MEET{$n} // [] }));
    @CARRY = grep { !$_->{done_d} } @mine;
    for my $st (@CARRY) {                                               # the unfinished tasks continue in the next sprint's milestone
        $st->{carried} = 1;
        at_($days[-1], 16, 30);
        for my $tk (grep { !$_->{done} } @{ $st->{tasks} }) {
            my $old = $gl->issue($P, $tk->{iid});
            $gl->as($tk->{who});
            my $i = $gl->create_issue($P, title => "$tk->{t} (continued)", labels => [ grep { !/^workflow::/ } map { ref $_ ? $_->{name} : $_ } @{ $old->{labels} // [] } ],
                milestone => 'Sprint ' . ($n + 1), assignees => [ $tk->{who} ],
                description => "Carried over from #$tk->{iid} (sprint $n): the remaining work, $tk->{p} point(s).\n\nPart of #$st->{iid}\n\n/estimate $tk->{p}d\n/relate #$st->{iid}\n", issue_type => 'task');
            $gl->add_note($P, 'issue', $tk->{iid}, "Not finished in sprint $n: carried to #$i->{iid} in sprint " . ($n + 1) . ".\n/close");
            logd($days[-1], $tk->{who}, "carried #$tk->{iid} to #$i->{iid} (sprint " . ($n + 1) . ')');
            $tk->{iid} = $i->{iid};
            $tk->{start_d} = (sprint_days($n + 1))[0]; delete $tk->{started};   # the continuation starts on the next sprint's first day
        }
        $gl->as('jim');
        $gl->update_issue($P, $st->{iid}, milestone => 'Sprint ' . ($n + 1));
    }
    ev($n, 'day-in-life/timeline.txt', "Thursday 2026-12-17, as GitLab recorded it (Eastern time)\n\n" . join('', map { "  $_\n" } sort @{ $DAYLOG{'2026-12-17'} // [] }) . "\nFriday 2026-12-18\n\n" . join('', map { "  $_\n" } sort @{ $DAYLOG{'2026-12-18'} // [] })) if $n == 6;
    ev($n, 'day-log.txt', join('', map { "$_\n" . join('', map { "  $_\n" } sort @{ $DAYLOG{$_} }) } grep { $DAYLOG{$_} } @days));
    $gl->save;
}

# ======================================================================== the nightly schedule, the S6 showcase day, document reviews
my @INCIDENT;
sub nightly {                                                           # the night's scheduled pipelines, before the stand-up
    my ($n, $d) = @_;
    my $broken = $d eq '2026-12-17';                                    # the runner's disk filled overnight
    local $gl->{runner_shell} = $broken ? do { my $s = "$W/scratch/diskfull.sh";     # the runner runs every job with this shell: it fails as a full disk does
        spew($s, "#!/bin/sh\necho \"fatal: could not create work tree dir 'builds/tidewater/model': No space left on device\" >&2\nexit 1\n"); chmod 0755, $s; $s } : $gl->{runner_shell};
    local $gl->{cache_on} = $broken ? 0 : $gl->{cache_on};
    my $pls = $gl->run_due_schedules($P, until => hm($d, 8, 59)) // [];
    for my $pl (@$pls) { keep_log($n, $pl, "nightly-$d") if $n <= 6 && ($pl->{status} ne 'success' || $d eq '2026-12-18') ; @INCIDENT = ($pl) if $broken && $pl->{status} ne 'success' }
}
sub todo_list {                                                         # 09:00: what is waiting for Bob (GitLab's To-Do list)
    my ($n, $d) = @_;
    my @open = grep { $_->{state} eq 'opened' && grep { $_->{username} eq 'bob' } @{ $_->{reviewers} // [] } } @{ $gl->mrs($P) };
    my ($hh, $mm) = substr($gl->now, 11, 5) =~ /(\d\d):(\d\d)/;
    ev($n, 'day-in-life/todo-list.txt', sprintf("Bob's To-Do list, %s %02d:%s\n\n", $d, $hh - 5, $mm) . (@open ? join('', map { "  !$_->{iid} $_->{title} (review requested by \@$_->{author}{username})\n" } @open) : "  (no reviews waiting)\n")
        . "  (the failed nightly, #" . ($ST{incident_issue} // '?') . ", was picked up at the stand-up and closed by Tom at 10:30)\n");
}
sub showcase_morning {                                                  # the failed nightly, picked up at the stand-up
    my ($n, $d) = @_;
    return unless @INCIDENT;
    my $pl = $INCIDENT[0];
    at_($d, 9, 15);
    $gl->as('bob');
    my ($job) = grep { $_->{status} eq 'failed' } @{ $pl->{jobs} };
    my $i = $gl->create_issue($P, title => "Nightly full check failed: no space left on the runner", labels => [ 'type::defect', 'area::pipeline', 'priority::1', 'severity::2', 'work::platform', 'workflow::in-progress' ],
        milestone => "Sprint $n", assignees => ['tom'], description => "The nightly full check (pipeline #$pl->{id}, scheduled 02:00) failed in every job before running any check:\n\n```text\n"
        . "fatal: could not create work tree dir 'builds/tidewater/model': No space left on device\n```\n\nJob: $pl->{web_url}/../jobs/$job->{id}\n\nNot a model problem: develop's last MR pipeline was green. Picked up at the stand-up.\n");
    logd($d, 'bob', "opened #$i->{iid} for the failed nightly pipeline #$pl->{id}");
    $ST{incident_issue} = $i->{iid};
    at_($d, 10, 30);
    $gl->as('tom');
    my $re = do { local $gl->{cache_on} = 0; $gl->run_pipeline($P, 'develop', source => 'web') };
    keep_log($n, $re, "nightly-rerun-$d");
    $gl->add_note($P, 'issue', $i->{iid}, "Cleared the runner's old build directories (14 GB) and set the runner to clean up after each job. Re-ran the full check: pipeline #$re->{id} $re->{status}.\n/spend 1h\n/label ~workflow::done\n/close");
    logd($d, 'tom', "cleared the runner's disk; re-ran the full check: #$re->{id} $re->{status}; closed #$i->{iid}");
    ev($n, 'day-in-life/incident.md', "# #$i->{iid} " . $gl->issue($P, $i->{iid})->{title} . "\n\n" . $gl->issue($P, $i->{iid})->{description} . "\n---- comments\n"
        . join('', map { "\n**\@$_->{author}{username}** ($_->{created_at})" . ($_->{system} ? ' [system]' : '') . ":\n$_->{body}\n" } @{ $gl->issue($P, $i->{iid})->{notes} }));
    @INCIDENT = ();
    $ST{incident_restore_hours} = (GitLab::_epoch($re->{finished_at}) - GitLab::_epoch($pl->{created_at})) / 3600;
}
my %DOC;
sub s6_documents {                                                      # the memo and the exchange table through the review stages
    my ($n, $d) = @_;
    my %step = ('2026-12-14' => 'grey', '2026-12-16' => 'blue', '2026-12-17' => 'pink', '2026-12-18' => 'red', '2026-12-21' => 'gold', '2026-12-22' => 'white', '2026-12-24' => 'green');
    my $st = $step{$d} or return;
    at_($d, 16, 0);
    $gl->as('jim');
    if ($st eq 'grey') {
        for my $doc (['Twelve-week progress memo to program management', 'docs/memos/2026-12-24-twelve-week-progress.md'], ['Data exchange table for the program review', 'docs/data-exchange.md']) {
            my $i = $gl->create_issue($P, title => "Doc: $doc->[0]", labels => [ 'doc::grey', 'work::engineering', 'area::pipeline' ], milestone => "Sprint $n", assignees => ['jim'],
                description => "A document issue: the document moves through the review stages as labels (doc::grey .. doc::green). Source: `$doc->[1]`, generated or written in the repo and reviewed by MR.\n");
            push @{ $DOC{list} }, $i->{iid};
        }
        my $tbd = $gl->create_issue($P, title => 'TBD: the hygrometer reaches the data center on the observation interface (assumed for drop 2)', labels => [ 'prime-tbd', 'owner::prime', 'area::interfaces', 'work::engineering' ],
            milestone => "Sprint $n", assignees => ['jim'], description => "The prime told us a hygrometer is coming in drop 2. We assume its reading rides in `ObservationRecord` on the observation interface, "
            . "so the data exchange table and the VCRM work go ahead now. Confirm or correct when drop 2 lands (expected 2027-01-08); close this issue at the drop-2 intake.\n");
        my $ti = $gl->issue($P, $tbd->{iid});
        ev($n, "samples/issue-prime-tbd.md", "# #$ti->{iid} $ti->{title}\n\nLabels: " . join(q{, }, @{ $ti->{labels} }) . "\nOpened: $ti->{created_at} by \@$ti->{author}{username}\n\n$ti->{description}");
        push @{ $DOC{hist} }, [ $d, $st ];
        return;
    }
    $gl->add_note($P, 'issue', $_, "Review stage: $st.\n/label ~doc::$st" . ($st eq 'green' ? "\n/close" : '')) for @{ $DOC{list} // [] };
    push @{ $DOC{hist} }, [ $d, $st ];
    if ($st eq q{green}) {                                             # the stage history, as GitLab recorded the label changes
        my $h = "Document review stages (doc:: labels), as the label changes were recorded\n\n";
        for my $iid (@{ $DOC{list} // [] }) { my $i = $gl->issue($P, $iid); $h .= "#$iid $i->{title}\n" . join(q{}, map { "  $_->[0]  doc::$_->[1]\n" } @{ $DOC{hist} }) . "\n" }
        ev($n, q{doc-stages.txt}, $h);
    }
}
sub end_of_sprint {
    my ($n, $sp, $d, $mine) = @_;
    at_($d, 10, 0);
    my @done = grep { $_->{done_d} } @$mine;
    my @open = grep { !$_->{done_d} } @$mine;
    if ($n >= 3) { $gl->save; my ($rs) = run_q(undef, $^X, "$ROOT/tools/gitlab/talk.pl", '--local', "$W/gitlab", '--project', $P, 'review', '--sprint', $n, '--journal', $J, '--md'); ev($n, 'review-script.md', $rs) }
    my %fb = (1 => "Feedback (Deputy PM): \"You received the drop and checked every file. When does the model itself move?\" Jim: drop 1 goes onto develop through the vendor branch in sprint 2, and every change after that is checked by the pipeline.\n",
              3 => "Feedback (Deputy PM): \"Which requirements have no verification? You said you would know.\" Bob opened the trace report: 9 of 30, each with its ID; they are the prime's to fix and go out as discrepancy reports in sprint 4.\n",
              5 => "Feedback (Deputy PM): \"Can I get the trace numbers without asking you?\" Jim showed the trace page on the model site, rebuilt on every merge; the link goes in the weekly note.\n",
              2 => "Feedback (Deputy PM): \"I did not follow the demo. What did we get for the two weeks?\" Tom showed the terminal, the YAML and a green pipeline, in that order; the room heard jargon and no number.\nRetro action: a Day-9 rehearsal from now on, and the driver rotates.\n",
              4 => "Feedback (Program manager): \"I can open this on my phone?\" The rehearsed demo led with the question, showed the model site, one before-and-after (the cycle: two lines removed, a week of diagram reading before), one live change, and the ask.\n");
    ev($n, 'review.txt', "Sprint $n review, $d 10:00\n\nGoal: $sp->{goal}\n\nDemonstrated:\n" . join('', map { "  $_->{id} $_->{plan}{title}\n" } @done)
        . (@open ? "\nCarried to sprint " . ($n + 1) . ":\n" . join('', map { "  $_->{id} $_->{plan}{title}\n" } @open) : '') . "\nArtifacts shown: the merge requests and pipelines of the sprint"
        . ($CI_LEVEL >= 4 ? ', the model site (GitLab Pages)' : '') . ".\n" . ($fb{$n} ? "\n$fb{$n}" : '')
        . sprintf("\nThe four headline numbers: TODO lines left %d; verify coverage %s; open DRs %d; blocked items %d.\n", $TODO_NOW, vcover(), scalar(grep { $_->{state} eq 'opened' } grep { grep { $_ eq 'type::discrepancy' } @{ $_->{labels} } } @{ $gl->issues($P) }), scalar(grep { grep { $_ eq 'workflow::blocked' } @{ $_->{labels} } } grep { $_->{state} eq 'opened' } @{ $gl->issues($P) })));
    {                                                                   # each person's GitLab To-Do list as the review starts
        my $todo = "GitLab To-Do lists at the review ($d 10:00)\n";
        for my $u (@TEAM) {
            my @rv = grep { $_->{state} eq q{opened} && grep { $_->{username} eq $u } @{ $_->{reviewers} // [] } } @{ $gl->mrs($P) };
            my @as = grep { $_->{state} eq q{opened} && grep { $_->{username} eq $u } @{ $_->{assignees} // [] } } @{ $gl->issues($P) };
            $todo .= sprintf "\n  %s: %d review(s) requested, %d open issue(s) assigned\n", $PEOPLE{$u}{name}, scalar @rv, scalar @as;
            $todo .= "    review !$_->{iid} $_->{title}\n" for @rv;
            $todo .= "    #$_->{iid} $_->{title}\n" for @as;
        }
        ev($n, q{todo-at-review.txt}, $todo);
    }
    # the pulse survey: five questions, 1-5, per person, around the sprint's measured mood
    my @q = ('I understand why we are working this way.', 'I can do my work in the new tools without help.', 'The checks catch problems I would have missed.', 'I can see our progress.', 'I would choose to keep working this way.');
    my %off = (jim => [0.4, 0.1, 0.0, 0.3, 0.4], bob => [-0.5, -0.2, 0.2, -0.3, -0.6], tom => [0.1, 0.1, -0.2, 0.0, 0.2]);
    my $m = { sprint => $n, questions => \@q };
    my @all;
    for my $u (@TEAM) { my @a = map { my $v = $sp->{pulse} + $off{$u}[$_] + 0.1 * ($_ - 2) * ($n <= 3 ? 1 : -0.5); $v = 1 if $v < 1; $v = 5 if $v > 5; 0 + sprintf('%.0f', $v) } 0 .. 4; $m->{answers}{$u} = \@a; push @all, @a }
    my $sum = 0; $sum += $_ for @all;
    $m->{mean} = 0 + sprintf('%.1f', $sum / @all);
    $MORALE{$n} = $m->{mean};
    ev($n, 'morale.json', $JSON->encode($m));
    my $r = $sp->{retro} // {};
    ev($n, 'retro.txt', "Sprint $n retrospective, $d 11:00\n\nStart:\n" . join('', map { "  - $_\n" } @{ $r->{start} // [] }) . "Stop:\n" . join('', map { "  - $_\n" } @{ $r->{stop} // [] })
        . "Continue:\n" . join('', map { "  - $_\n" } @{ $r->{continue} // [] }) . "\nPulse survey (1-5, anonymous): mean $m->{mean}\n");
    ev($n, 'quotes.txt', join('', map { "$_->[0]  $_->[1]: $_->[2]\n" } @{ $sp->{quotes} // [] })) if @{ $sp->{quotes} // [] };
    $gl->as('jim');
    eval { $gl->update_milestone($P, "Sprint $n", state_event => 'close') };
    $gl->export($P, sprintf("$W/exports/sprint-%02d", $n), until => $d);
    if ($gl->can('analytics')) { my $a = eval { GitLab::analytics_text($gl->analytics($P, since => sprint_start($n), until => $d, by => 'sprint')) }; ev($n, 'analytics.txt', $a) if $a }
    scorecard($n, $d, $mine);
    samples($n) if $n <= 6;
    briefing($n, $d) if $ST{briefing_due};
}

# ======================================================================== the scorecard (chapter 4's twelve measures, computed)
sub export_develop {                                                    # develop as it is now, in a scratch folder
    my $f = flow('jim'); $f->git('fetch', '-q', 'origin');
    my $c = "$W/scratch/develop";
    remove_tree($c); make_path($c);
    run_q(undef, 'sh', '-c', "git -C '" . $f->dir . "' archive origin/develop | tar -x -C '$c'");
    $c;
}
sub vcover { export_develop(); my $c = "$W/scratch/develop"; my ($reqif) = sort { $b cmp $a } glob("$c/imports/*/tidewater.reqif"); return '-' unless $reqif;
    my ($t) = run_q(undef, $^X, "$ROOT/bin/reqif2sysml.pl", '--report', '--model', CIJob::model_side("$c/model"), $reqif); my ($g) = $t =~ /^G unverified[^\n]*?(\d+)\s*$/m; my ($tot) = $t =~ /linked[^\n]*?of (\d+)/; defined $g && $tot ? sprintf('%d%%', 100 * ($tot - $g) / $tot) : '-' }
sub median { my @v = sort { $a <=> $b } @_; return undef unless @v; @v % 2 ? $v[$#v / 2] : ($v[@v / 2 - 1] + $v[@v / 2]) / 2 }
sub scorecard {
    my ($n, $d, $mine) = @_;
    my $f = flow('jim');
    my $c = export_develop();
    my $todo = 0; File::Find::find({ no_chdir => 1, wanted => sub { $todo += () = (slurp($_) // '') =~ m{// TODO}g if /\.sysml$/ && -f } }, "$c/model") if -d "$c/model";
    my $s0 = sprint_start($n);
    my @mrs = grep { $_->{target_branch} eq 'develop' && $_->{merged_at} && substr($_->{merged_at}, 0, 10) ge $s0 && substr($_->{merged_at}, 0, 10) le $d } @{ $gl->mrs($P, state => 'merged') };
    my $lead = median(map { (GitLab::_epoch($_->{merged_at}) - GitLab::_epoch($_->{created_at})) / 3600 } @mrs);
    my $gated = grep { my $m = $_; ($m->{head_pipeline} // {})->{status} && $m->{head_pipeline}{status} eq 'success' && grep { $_->{user}{username} ne $m->{author}{username} } @{ $m->{approved_by} } } @mrs;
    my $turn = median(map { my $m = $_; my ($a) = @{ $m->{approved_by} }; $a ? (GitLab::_epoch($a->{approved_at}) - GitLab::_epoch($m->{created_at})) / 3600 : () } @mrs);
    my @trace = map { $_->{duration} } grep { $_->{name} eq 'trace' && $_->{started_at} && substr($_->{started_at}, 0, 10) ge $s0 && substr($_->{started_at}, 0, 10) le $d } map { @{ $_->{jobs} } } @{ $gl->pipelines($P) };
    my @dev = grep { $_->{ref} eq 'develop' && substr($_->{created_at}, 0, 10) ge $s0 && substr($_->{created_at}, 0, 10) le $d } @{ $gl->pipelines($P) };
    my $pass = grep { $_->{status} eq 'success' } @dev;
    my ($worst, $from);
    for my $pl (sort { $a->{id} <=> $b->{id} } @dev) { if ($pl->{status} ne 'success') { $from //= GitLab::_epoch($pl->{created_at}) } elsif (defined $from) { my $h = (GitLab::_epoch($pl->{created_at}) - $from) / 3600; $worst = $h if !defined $worst || $h > $worst; undef $from } }
    my %tr;
    my ($reqif) = sort { $b cmp $a } glob("$c/imports/*/tidewater.reqif");
    if ($reqif && -d "$c/model") { my ($t) = run_q(undef, $^X, "$ROOT/bin/reqif2sysml.pl", '--report', '--model', CIJob::model_side("$c/model"), $reqif);
        for (qw(C F G I)) { ($tr{$_}) = $t =~ /^$_ [^\n]*?([\d.]+%?(?: of \d+)?)\s*$/m } ($tr{drift}) = $t =~ /^text differs from DOORS\s+(\d+)/m }
    my $cx = -d "$c/model" ? CIJob::complexity_of(CIJob::model_files("$c/model"), { layers => (slurp("$c/sysml.conf") // '') =~ /^layers = (.*)$/m ? $1 : '' })->{metrics} : {};
    my @drs = grep { grep { $_ eq 'type::discrepancy' } @{ $_->{labels} } } @{ $gl->issues($P) };
    my @tags = grep { /^baseline-/ } split /\n/, $f->git('tag', '-l');
    my $s = load("$J/scrum.txt", today => $d);
    my $sum = sprint_summary($s, $n)->{totals};
    my $assisted = grep { grep { $_ eq 'ai::assisted' } @{ $_->{labels} } } @mrs;
    my %sc = (sprint => $n, date => $d,
        '1_todo_lines' => $todo, '2_lead_time_hours' => defined $lead ? 0 + sprintf('%.1f', $lead) : undef, '3_gated_changes' => @mrs ? sprintf('%d of %d', $gated, scalar @mrs) : 'no merges',
        '4_trace_answer_seconds' => @trace ? 0 + sprintf('%.0f', median(@trace)) : undef, '5_trace' => \%tr, '6_drs' => { opened => scalar @drs, closed => scalar(grep { $_->{state} eq 'closed' } @drs) },
        '7_spider_web' => { cycles => $cx->{cycles}, duplicates => $cx->{duplicates}, max_relationships_per_part => $cx->{max_relationships_per_part}, max_fan_out => $cx->{max_fan_out} },
        '8_pipeline_health' => { develop_pipelines => scalar @dev, passing => $pass, worst_restore_hours => defined $worst ? 0 + sprintf('%.1f', $worst) : undef },
        '9_baselines' => { tagged => scalar @tags, reproducible => scalar(grep { ($ST{baselines}{$_}{pipeline} // '') eq 'success' } @tags) },
        '10_review_turnaround_hours' => defined $turn ? 0 + sprintf('%.1f', $turn) : undef,
        '11_delivery' => { committed => $sum->{committed}, done => $sum->{done}, pct => $sum->{pct} }, '12_morale' => $MORALE{$n},
        capacity => $SCORE{$n}{capacity} ? 0 + sprintf('%.1f', $SCORE{$n}{capacity}) : undef,   # the kickoff's capacity in points (holidays and leave taken off)
        work_mix => { committed => $SCORE{$n}{committed_points}, platform => $SCORE{$n}{platform_points}, learning => $SCORE{$n}{learning_points}, engineering => $SCORE{$n}{committed_points} - $SCORE{$n}{platform_points} - $SCORE{$n}{learning_points} }, merges => scalar @mrs,
        standup_outcome_share => $OUTCOME{$n}{lines} ? 0 + sprintf('%.2f', ($OUTCOME{$n}{good} // 0) / $OUTCOME{$n}{lines}) : undef,
        first_pipeline_pass => do { my @all = grep { $FIRST_PASS{$_} } @{ $SPRINT_MRS{$n} // [] };
            my %ai = map { $_ => 1 } grep { my $m = $gl->mr($P, $_); grep { $_ eq 'ai::assisted' } @{ $m->{labels} } } @all;
            +{ mrs => scalar @all, passed => scalar(grep { $FIRST_PASS{$_} eq 'success' } @all), ai_assisted_mrs => scalar(keys %ai),
               ai_assisted_passed => scalar(grep { $FIRST_PASS{$_} eq 'success' } keys %ai) } },
        document_era_baseline_notional => { ccb_change_working_days => 23, unverified_question_days => 2, model_review_weeks => 3, drift_found => 'never systematically' });
    $SCORE{$n}{card} = \%sc;
    ev($n, 'scorecard.json', $JSON->encode(\%sc));
}
sub samples {                                                          # the real Markdown GitLab holds, for the book
    my $n = shift;
    for my $st (grep { $_->{sprint} == $n } @STORIES) { my $i = $gl->issue($P, $st->{iid}); ev($n, "samples/story-$st->{id}.md", "# $i->{title}\n\n$i->{description}") ;
        for my $tk (@{ $st->{tasks} }) { my $t = $gl->issue($P, $tk->{iid}); ev($n, "samples/task-$tk->{iid}.md", "# $t->{title}\n\n$t->{description}\n\n---- comments\n" . join('', map { "\n**\@$_->{author}{username}** ($_->{created_at})" . ($_->{system} ? ' [system]' : '') . ":\n$_->{body}\n" } @{ $t->{notes} })) } }
    for my $iid (@{ $SPRINT_MRS{$n} // [] }) { my $m = $gl->mr($P, $iid); ev($n, "samples/mr-$iid.md", "# !$iid $m->{title}\n\n$m->{description}\n\n---- thread\n" . join('', map { "\n**\@$_->{author}{username}** ($_->{created_at})" . ($_->{system} ? ' [system]' : '') . ":\n$_->{body}\n" } @{ $m->{notes} })) }
    my ($ms) = grep { $_->{title} eq "Sprint $n" } @{ $gl->milestones($P) };
    ev($n, 'samples/milestone.md', "# $ms->{title}\n\n$ms->{description}\n") if $ms;
}
sub briefing {
    my ($n, $d) = @_;
    delete $ST{briefing_due};
    my @rows = map { my $c = $SCORE{$_}{card}; [ $_, $c->{'1_todo_lines'}, $c->{'2_lead_time_hours'} // '-', $c->{'3_gated_changes'}, $c->{'12_morale'} // '-' ] } sort { $a <=> $b } grep { $SCORE{$_}{card} } keys %SCORE;
    my $t = "Tidewater: twelve weeks of MBSE in GitLab -- briefing to program management, $d\n\n"
          . "1. Where we started: documents, then a Cameo model nobody could merge or review (47 diagrams, 2 package cycles).\n"
          . "2. What we built: a GitLab project, a pipeline that checks every change, the model in SysML v2 text, a model site.\n"
          . "3. The scorecard, sprint by sprint:\n\n   sprint  TODO lines  lead time (h)  gated        morale\n"
          . join('', map { sprintf "   %-6s  %-10s  %-13s  %-11s  %s\n", @$_ } @rows)
          . "\n4. Before and after (document-era numbers are notional): a requirement change took 23 working days through the CCB;\n   a model change now takes hours from MR to merge, reviewed and checked.\n"
          . "5. The demo: open an MR, watch the pipeline, see the trace and the VCRM on the site.\n6. Next semester: drops 2 and 3, behavior, baseline 1 in sprint 20.\n";
    ev($n, 'briefing.txt', $t . "\nThe written twin of this briefing is the twelve-week progress memo (docs/tidewater/memos/2026-12-24-twelve-week-progress.md).\n");
}

# ======================================================================== checks
my @problems;
for my $st (@STORIES) {
    for my $tk (@{ $st->{tasks} }) {
        push @problems, "#$tk->{iid} has $tk->{p} points (more than 5)" if $tk->{p} > 5;
        next unless $tk->{start_d} && $tk->{done};
        my $span = $CALIDX{ $tk->{done} } - $CALIDX{ $tk->{start_d} } + 1;
        my $wd = grep { working($tk->{who}, $CAL[$_]) } $CALIDX{ $tk->{start_d} } .. $CALIDX{ $tk->{done} };
        push @problems, "#$tk->{iid} took $wd working days (more than 5)" if $wd > 5 + ($tk->{late} // 0) + ($tk->{block} ? $tk->{block}[1] : 0);
    }
}
my @carried = grep { $_->{done_d} && $CALIDX{ $_->{done_d} } > $CALIDX{ (sprint_days($_->{sprint}))[-1] } } @STORIES;
for my $m (@{ $gl->mrs($P, state => 'merged') }) {
    next unless $m->{target_branch} eq 'develop' && $m->{merged_at} ge ($ST{gate_on_at} // '9999');   # gated from the day "pipelines must succeed" went on
    push @problems, "!$m->{iid} merged without a successful pipeline" unless ($m->{head_pipeline} // {})->{status} && $m->{head_pipeline}{status} eq 'success';
    push @problems, "!$m->{iid} merged without an approval from someone other than its author" unless grep { $_->{user}{username} ne $m->{author}{username} } @{ $m->{approved_by} };
}
my $s = load("$J/scrum.txt", today => $CAL[-1]);
my $chk = sprintf "checks: %d stories (%d carried over), %d tasks, %d merge requests, %d pipelines; %d problem(s)\n", scalar @STORIES, scalar @carried,
    scalar(map { @{ $_->{tasks} } } @STORIES), scalar @{ $gl->mrs($P) }, scalar @{ $gl->pipelines($P) }, scalar @problems;
$chk .= "  $_\n" for @problems;
spew("$W/checks.txt", $chk);
print $chk;
$gl->save;

# ======================================================================== evidence for the docs, and the copy out of the work dir
if ($o{'docs-dir'} && !$o{'no-docs'} && $o{sprints} >= 6) {             # only when asked: a plain run never touches docs/ (tests and the book's runs share it)
    my @ev = ($^X, "$ROOT/sim/tidewater-evidence.pl", $W, '--out', "$DOCS/tidewater", '--sprints', 6, '--quiet');   # the one evidence writer
    system(@ev) == 0 or die "tidewater-sim: sim/tidewater-evidence.pl failed\n";
    require "$ROOT/sim/tidewater-render.pl";
    tidewater_render("$DOCS/TIDEWATER.html", score => \%SCORE, drops => \@DROPLOG, stories => \@STORIES, plan => $PLAN, checks => rel($chk), sprints => $o{sprints});
}
if ($W ne (abs_path($o{dir}) // $o{dir})) {                       # (abs_path: /tmp may resolve elsewhere, e.g. under Git for Windows)
    remove_tree($o{dir});
    make_path($o{dir});
    system('cp', '-a', "$W/.", $o{dir}) == 0 or warn "copy to $o{dir} failed\n";
    say_("wrote $o{dir}");
}
exit(@problems ? 1 : 0);
