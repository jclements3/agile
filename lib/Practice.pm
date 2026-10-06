package Practice;
# Practice lessons: a fresh sandbox project per lesson under data/practice/ (git-ignored), the task printed from the
# help source (vim/doc/agile.txt, *agile-practice-N*), and a check of the learner's result against the journal and files.
#
#   perl agile.pl practice                 list the lessons
#   perl agile.pl practice N               set up data/practice/lessonN (wiping an old one) and print the task
#   perl agile.pl practice check N         what is done, what is missing; exit 0 when the lesson is done
#   perl agile.pl practice reset N         remove the sandbox
#   options: --dir DIR (sandboxes there instead), --today YYYY-MM-DD (the sandbox's "today"; default the real date)
#
# The sandboxes are made by the kit's own tools: daily.pl init, sim/halberd-gen.pl (a realistic journal, shifted so
# that today falls in the middle of a sprint), sim/idef0-backlog.pl and sim/rehearsal.pl (a seeded Teams chat).
# Core Perl only.
use strict;
use warnings;
use File::Path qw(remove_tree make_path);
use File::Copy qw(copy);
use Time::Local qw(timegm);
use Help ();

our $VERSION = '1.00';
my $ROOT = Help::root();

my @TW_NEEDS;                                    # what the GitLab lessons (11-13) need from the kit
my @LESSONS = (
    { n => 1, kind => 'empty',     check => \&check_1 },
    { n => 2, kind => 'halberd',   check => \&check_2 },
    { n => 3, kind => 'halberd',   check => \&check_3 },
    { n => 4, kind => 'dronecorp', check => \&check_4, chat => 1 },
    { n => 5, kind => 'dronecorp', check => \&check_5 },
    { n => 6, kind => 'idef0',     check => \&check_6 },
    { n => 7, kind => 'halberd',   check => \&check_7, memo => 1 },
    { n => 8, kind => 'sysml',     check => \&check_8, needs => [ 'tools/sysml/sysml.pl', 'bin/xmi2sysml.pl' ] },
    { n => 9, kind => 'drills',    check => \&check_9, needs => [ 'drills/drill.pl', 'drills/01-ladder/p12-dedup/stub.pl' ] },
    # MBSE DevSecOps, Tidewater: a first model change, a first merge request, a prime drop, a first baseline
    { n => 10, kind => 'tw-model',  check => \&check_10, needs => [ q(sim/tidewater-v1.pl), q(bin/xmi2sysml.pl), q(tools/sysml/model.pl), q(tools/gitlab/kickoff.pl), q(examples/tidewater-v1/layout.map) ] },
    { n => 11, kind => 'tw-gitlab', check => \&check_11, stage => 11, needs => [ @TW_NEEDS = (q(tools/gitlab/kickoff.pl), q(examples/tidewater-v1/layout.map), q(sim/tidewater-v1.pl), 'bin/gitlab.pl', 'lib/GitLab.pm', 'lib/GitFlow.pm', 'tools/gitlab/templates/project.conf', 'tools/gitlab/templates/ci/job.pl') ] },
    { n => 12, kind => 'tw-gitlab', check => \&check_12, stage => 12, needs => [ @TW_NEEDS ] },
    { n => 13, kind => 'tw-gitlab', check => \&check_13, stage => 13, needs => [ @TW_NEEDS ] },
);
my %LESSON = map { $_->{n} => $_ } @LESSONS;

sub _today { my @t = localtime; sprintf '%04d-%02d-%02d', $t[5] + 1900, $t[4] + 1, $t[3] }
sub _d2n { my ($y, $m, $d) = split /-/, shift; int(timegm(0, 0, 12, $d, $m - 1, $y) / 86400) }
sub _n2d { my @t = gmtime(shift() * 86400 + 43200); sprintf '%04d-%02d-%02d', $t[5] + 1900, $t[4] + 1, $t[3] }
sub _slurp { my $f = shift; open my $fh, '<:raw', $f or return undef; local $/; my $t = <$fh>; close $fh; $t }
sub _spit { my ($f, $t) = @_; open my $fh, '>:raw', $f or die "practice: cannot write $f: $!\n"; print $fh $t; close $fh or die "practice: cannot write $f: $!\n" }
sub _run {                                       # (cwd, @cmd) -> (exit status, combined output); never dies
    my ($cwd, @cmd) = @_;
    require Cwd;
    my $back = Cwd::getcwd();
    chdir $cwd or return (255, "cannot chdir $cwd: $!\n");
    my $out = '';
    if (open my $ph, '-|') { local $/; $out = <$ph> // ''; close $ph }
    else { open STDERR, '>&', \*STDOUT; exec @cmd or do { print "cannot run $cmd[0]: $!\n"; require POSIX; POSIX::_exit(127) } }
    my $rc = $? >> 8;
    chdir $back;
    ($rc, $out);
}
sub _daily { my ($dir, @a) = @_; _run($dir, $^X, "$ROOT/bin/daily.pl", '--conf', "$dir/scrum.conf", @a) }
sub _git { my ($dir, @a) = @_; _run($dir, 'git', @a) }
sub _git_commit { my ($dir, $msg) = @_;
    _git($dir, '-c', 'core.safecrlf=false', 'add', '-A');
    _git($dir, '-c', 'user.name=practice', '-c', 'user.email=practice@localhost', '-c', 'core.safecrlf=false', 'commit', '-q', '-m', $msg);
    my ($rc, $h) = _git($dir, 'rev-parse', 'HEAD'); $h =~ s/\s+//g; $rc ? '' : $h }

sub lesson_text {
    my ($n) = @_;
    my $h = Help::load();
    my $s = $h->{tags}{"agile-practice-$n"} or return undef;
    Help::plain(Help::lines_of($s));
}
sub title { my $n = shift; my $h = Help::load(); my $s = $h->{tags}{"agile-practice-$n"}; $s ? $s->{title} : "Lesson $n" }
sub enabled { my $l = shift; my @miss = grep { !-f "$ROOT/$_" } @{ $l->{needs} // [] }; @miss ? "needs @miss" : '' }

# ---------------------------------------------------------------- the command line
sub cli {
    my @a = @_;
    require Getopt::Long;
    my %o;
    Getopt::Long::GetOptionsFromArray(\@a, 'dir=s' => \$o{dir}, 'today=s' => \$o{today}) or return 2;
    my $base = $o{dir} // "$ROOT/data/practice";
    require File::Spec; $base = File::Spec->rel2abs($base);   # absolute: set-ups chdir into the sandbox and hand paths to git, GitFlow and gitlab.pl
    my $today = $o{today} // _today();
    if (!@a) {
        print "Practice lessons (perl agile.pl practice N to start one; the text is also :help agile-practice-N):\n";
        for my $l (@LESSONS) {
            my $why = enabled($l);
            my $state = $why ? "  [not available: $why]" : -f "$base/lesson$l->{n}/.practice" ? '  [set up]' : '';
            printf "  %d  %s%s\n", $l->{n}, title($l->{n}), $state;
        }
        print "Sandboxes go in $base (git-ignored). practice check N checks your work; practice reset N removes it.\n";
        return 0;
    }
    my $verb = $a[0] =~ /^(?:check|reset)$/ ? shift @a : 'setup';
    my $n = shift @a;
    if (!defined $n || $n !~ /^\d+$/) { print STDERR "usage: perl agile.pl practice [N | check N | reset N] [--dir DIR]\n"; return 2 }
    my $l = $LESSON{$n} or do { print STDERR "practice: no lesson $n (perl agile.pl practice lists them)\n"; return 2 };
    my $dir = "$base/lesson$n";
    if ($verb eq 'reset') { remove_tree($dir); print "removed $dir\n"; return 0 }
    if ($verb eq 'check') {
        if (!-f "$dir/.practice") { print STDERR "practice: lesson $n is not set up (perl agile.pl practice $n)\n"; return 1 }
        return check($n, $dir);
    }
    if (my $why = enabled($l)) { print STDERR "practice: lesson $n needs " . join(' ', @{ $l->{needs} }) . " ($why)\n"; return 1 }
    my $info = eval { setup($n, $dir, $today) };
    if (!$info) { print STDERR $@ =~ /^practice:/ ? $@ : "practice: lesson $n set-up failed: $@"; return 1 }
    print lesson_text($n) // "Lesson $n\n";
    print "\nKIT       = $ROOT\nSandbox   = $dir\n";
    print "In it:      cd " . ($info->{work} // $dir) . "\n";
    print "daily.pl  = perl $ROOT/bin/daily.pl   (an alias saves typing: perl agile.pl help alias)\n" unless $l->{kind} =~ /^tw-/;
    print "$_\n" for @{ $info->{notes} // [] };
    print "When done: perl $ROOT/agile.pl practice check $n\n";
    0;
}

# ---------------------------------------------------------------- set-up
sub setup {
    my ($n, $dir, $today) = @_;
    my $l = $LESSON{$n};
    remove_tree($dir) if -e $dir;
    make_path($dir) or -d $dir or die "practice: cannot create $dir: $!\n";
    my %info = (lesson => $n, today => $today, notes => []);
    if    ($l->{kind} eq 'empty')     { _setup_empty($dir, \%info) }
    elsif ($l->{kind} eq 'halberd')   { _setup_halberd($dir, $today, \%info) }
    elsif ($l->{kind} eq 'dronecorp') { _setup_dronecorp($dir, $today, \%info, chat => $l->{chat}) }
    elsif ($l->{kind} eq 'idef0')     { _setup_idef0($dir, \%info) }
    elsif ($l->{kind} eq 'sysml')     { _setup_sysml($dir, \%info) }
    elsif ($l->{kind} eq 'drills')    { push @{ $info{notes} }, "drill.pl  = perl $ROOT/drills/drill.pl --dir $dir   (the sandbox is the drills workspace)" }
    elsif ($l->{kind} eq 'tw-model')  { _setup_tw_model($dir, \%info) }
    elsif ($l->{kind} eq 'tw-gitlab') { _setup_tw_gitlab($dir, \%info, $l->{stage}) }
    _setup_memo($dir, \%info) if $l->{memo};
    if (-d "$dir/.git") { $info{head} = _git_commit($dir, "practice lesson $n: set-up") }
    _spit("$dir/.practice", join('', map { "$_ = " . ($info{$_} // '') . "\n" } grep { !ref $info{$_} } sort keys %info));
    \%info;
}
sub _info { my $dir = shift; my %i; for (split /\n/, _slurp("$dir/.practice") // '') { $i{$1} = $2 if /^(\w+) = (.*)$/ } \%i }

sub _setup_empty { my ($dir, $info) = @_; _init_project($dir) }
sub _init_project {                              # daily.pl init + our own git settings
    my ($dir) = @_;
    my ($rc, $out) = _run($dir, $^X, "$ROOT/bin/daily.pl", 'init', $dir);
    die "practice: daily.pl init failed: $out" if $rc;
    _spit("$dir/.gitignore", "reports/\n.practice\n");
}
sub _setup_halberd {                             # a copy of data/halberd, dates shifted by whole weeks so today is day 4 of sprint 2
    my ($dir, $today, $info) = @_;
    -f "$ROOT/docs/src/status-metrics.md" or die "practice: lesson $info->{lesson} needs docs/src/status-metrics.md (sim/halberd-gen.pl reads it)\n";
    my $gen = "$dir/.gen/data/halberd";
    make_path("$dir/.gen/data");
    my ($rc, $out) = _run($dir, $^X, "$ROOT/sim/halberd-gen.pl", '--dir', $gen, '--no-html');
    die "practice: sim/halberd-gen.pl failed: $out" if $rc;
    opendir my $dh, "$gen/standups" or die "practice: no $gen/standups\n";
    my @f = sort grep { /^\d{4}-\d{2}-\d{2}(?:\.txt|-\w+-answers\.txt)$/ } readdir $dh;
    closedir $dh;
    my %sprint;
    for my $f (grep { /^\d{4}-\d{2}-\d{2}\.txt$/ } @f) { my $t = _slurp("$gen/standups/$f"); $sprint{ substr($f, 0, 10) } = $1 if $t =~ /^sprint (\d+)$/m }
    my @s2 = sort grep { $sprint{$_} == 2 } keys %sprint;
    @s2 >= 4 or die "practice: the Halberd journal has no sprint 2\n";
    my $anchor = _d2n($s2[3]);
    my $diff = _d2n($today) - $anchor;                 # whole weeks, rounded down: the anchor lands on or before today, so today is day 4-8 of sprint 2
    my $shift = 7 * (int($diff / 7) - ($diff < 0 && $diff % 7 ? 1 : 0));
    _init_project($dir);
    copy("$gen/$_", "$dir/$_") for grep { -f "$gen/$_" } qw(scrum.conf roster.txt);
    _spit("$dir/scrum.txt", "; practice copy of the Halberd journal (sim/halberd-gen.pl), dates moved so today is mid-sprint\n");
    my $last;
    for my $f (@f) {
        my $d = _n2d(_d2n(substr($f, 0, 10)) + $shift);
        next unless $d lt $today;
        my $t = _slurp("$gen/standups/$f");
        $t =~ s/\A# compiled [^\n]*\n//;
        $t =~ s/\A\d{4}-\d{2}-\d{2}/$d/;
        (my $nf = $f) =~ s/^\d{4}-\d{2}-\d{2}/$d/;
        _spit("$dir/standups/$nf", $t);
        $last = $d if $f =~ /^\d{4}-\d{2}-\d{2}\.txt$/;
    }
    defined $last or die "practice: no Halberd stand-up falls before $today\n";
    ($rc, $out) = _daily($dir, "--today=$last", 'compile');
    die "practice: compiling the Halberd copy failed: $out" if $rc;
    require Scrum;
    my $s = Scrum::load("$dir/scrum.txt", today => $today);
    $info->{sprint} = $s->{current};
    remove_tree("$dir/.gen");
    push @{ $info->{notes} }, "The journal runs to $last; today ($today) is in sprint $s->{current}.";
}
sub _prev_weekday { my $n = _d2n(shift) - 1; $n-- while (gmtime($n * 86400 + 43200))[6] =~ /^[06]$/; _n2d($n) }
sub _setup_dronecorp {                           # DroneCorp's backlog planned on the previous weekday, two people a team; a seeded chat for today
    my ($dir, $today, $info, %o) = @_;
    my $model = "$ROOT/tools/idef0/examples/dronecorp/dronecorp.md";
    -f $model or die "practice: lesson $info->{lesson} needs tools/idef0/examples/dronecorp/dronecorp.md\n";
    _init_project($dir);
    my $d0 = _prev_weekday($today);
    my ($rc, $plan) = _run($dir, $^X, "$ROOT/sim/idef0-backlog.pl", $model, '--cap', 30, '--commit', '--people', 2, '--date', $d0);
    die "practice: sim/idef0-backlog.pl failed: $plan" if $rc;
    $plan =~ s/^Wide character[^\n]*\n//mg;
    _spit("$dir/standups/$d0.txt", $plan);
    my ($rc2, $ros) = _run($dir, $^X, "$ROOT/sim/idef0-backlog.pl", $model, '--people', 2, '--roster');
    my $roster = "# Name | email | Team | Role | Org   (practice: notional people)\n";
    for (split /\n/, $ros) { next unless /^(\S+) \([^)]*\): (.+)$/; my $team = $1; for my $p (split /,\s*/, $2) { (my $e = lc $p) =~ s/\s+/./g; $roster .= "$p | $e\@example.com | $team | Member | DroneCorp\n" } }
    _spit("$dir/roster.txt", $roster);
    my $conf = _slurp("$dir/scrum.conf");
    $conf =~ s/^facilitator\s*=.*$/facilitator       = Sam Archer       # the facilitator in the rehearsal chat/m;
    $conf =~ s/^(standup_match.*)$/calendar          = mock\n$1/m;
    _spit("$dir/scrum.conf", $conf);
    ($rc, my $out) = _daily($dir, "--today=$d0", 'compile');
    die "practice: compiling the DroneCorp plan failed: $out" if $rc;
    if ($o{chat}) {
        _git_commit($dir, 'practice: the plan');
        my ($rc3, $o3) = _run($dir, $^X, '-e', 'open STDERR, ">", ".answer-key.txt" or die; exec @ARGV', $^X, "$ROOT/sim/rehearsal.pl", '--date', $today, '--mistakes', 6, '--seed', 3);
        die "practice: sim/rehearsal.pl failed: $o3" if $rc3;
        push @{ $info->{notes} }, "Today's chat: standups/$today-chat.txt (the answer key: .answer-key.txt -- read it after you try).";
    }
    push @{ $info->{notes} }, "Sprint 1 was planned on $d0 for ten teams.";
}
sub _setup_idef0 {
    my ($dir, $info) = @_;
    my $src = "$ROOT/tools/idef0/examples/quadfactory";
    -d $src or die "practice: lesson $info->{lesson} needs tools/idef0/examples/quadfactory\n";
    make_path("$dir/model");
    opendir my $dh, $src or die "practice: cannot read $src: $!\n";
    copy("$src/$_", "$dir/model/$_") for grep { /\.txt$/ } readdir $dh;
    closedir $dh;
    _spit("$dir/model/design.txt", "# -*- mode: idef0 -*-\ntD Design\n  a# Define Quad Spec\n\ti# Pilot Requirements\n    o# Quad Spec < F|Cut Frame Parts|Quad Spec\n  a# Review|Approve Spec\n");
    push @{ $info->{notes} }, "Lint: perl $ROOT/tools/idef0/idef0.pl lint model/*.txt   (in Vim: open model/design.txt, then \\iL)";
}
sub _setup_sysml {                               # a small Cameo export and an empty model repository
    my ($dir, $info) = @_;
    my $x = "$ROOT/tests/fixtures/xmi2sysml/courier.xmi";
    -f $x or die "practice: lesson $info->{lesson} needs tests/fixtures/xmi2sysml/courier.xmi\n";
    copy($x, "$dir/legacy.xmi") or die "practice: cannot copy $x: $!\n";
    my ($rc, $out) = _git($dir, 'init', '-q');
    die "practice: git init failed: $out" if $rc;
    _git($dir, 'config', 'core.autocrlf', 'false');
    _spit("$dir/.gitignore", ".practice\n");
    _spit("$dir/sysml.conf", "# sysml.conf for tools/sysml/model.pl (practice)\ntitle = Courier\n");
    push @{ $info->{notes} }, "In Vim, \\mx checks the .sysml file you are in (tools/sysml/sysml.pl check).";
}
sub _setup_memo {
    my ($dir, $info) = @_;
    _spit("$dir/memo.md", <<'MD');
# MEMORANDUM FOR THE PROGRAM MANAGER

SUBJECT: Halberd SysML v2 port, status TODO (the date)

The port is in sprint TODO (the number) of six. TODO: one sentence on where it stands.

Progress this sprint:

- TODO: items committed and done so far (daily.pl status)
- TODO: what is blocked or carried, if anything (daily.pl blocked, daily.pl quad)

Next: TODO: what the team does next.

Point of contact: TODO.
MD
    push @{ $info->{notes} }, "Edit memo.md (vim memo.md): replace every TODO.";
}

# ---------------------------------------------------------------- Tidewater: lessons 10-13 (MBSE DevSecOps)
# The sandboxes are what a real team gets in week zero: the model repository made by tools/gitlab/kickoff.pl scaffold
# (its pipeline, code owners, templates, sysml.conf with layers, .ci/outline-max, the government's level tags in
# model/library/conventions/Conventions.sysml), plus .ci/layout.map (examples/tidewater-v1/layout.map: every package of
# a drop at the same path in every drop), and drop v1.0 of the notional Tidewater model (sim/tidewater-v1.pl) converted
# with that map -- so Stations is model/physical/stations/Stations.sysml. Lesson 10 is that repository alone. Lessons
# 11-13 add the offline GitLab (lib/GitLab.pm, under SANDBOX/gitlab): the project set up from the scaffold's
# .gitlab/project.conf, develop, drop v1.0 brought in through vendor/prime by merge request (with the inherited outline
# count recorded and the docs generated, as the team does on its first import). Each lesson starts where the one before
# ends: the set-up replays the earlier solutions through merge requests, as the people would. The learner's clone is
# SANDBOX/work; SANDBOX/env.sh sets GITLAB_* and the gl shortcut.
my $TW_P = 'tidewater/model';
my $TW_ST = 'model/physical/stations/Stations.sysml';
my $TW_LEVELS = 'L1Network,L2Segment,L3Station,L4Subsystem,L5Assembly,L6Component';
my %TW_VER = (1 => 'v1.0', 2 => 'v1.1');
my %TW_NAME = (jim => 'Jim', bob => 'Bob', tom => 'Tom');
my %TW_LEARNER = (11 => 'bob', 12 => 'tom', 13 => 'tom');   # 13: Tom cuts the baseline; Jim, the systems lead, approves it (an author cannot approve)
my %TW_ROLE = (bob => 'Bob, the MBSE engineer', tom => 'Tom, who keeps the pipeline and the vendor branch', jim => 'Jim, the MBSE lead');
sub tw_paths { (stations => $TW_ST, conventions => 'model/library/conventions/Conventions.sysml', map => '.ci/layout.map') }

sub _tw_drop {                                   # (sandbox, N) -> the folder holding prime drop N (sim/tidewater-v1.pl --drop N)
    my ($dir, $n) = @_;
    my $out = "$dir/drops/$TW_VER{$n}";
    return $out if -f "$out/tidewater.xmi";
    make_path($out);
    my ($rc, $o) = _run($dir, $^X, "$ROOT/sim/tidewater-v1.pl", '--drop', $n, $out);
    die "practice: sim/tidewater-v1.pl --drop $n failed: $o" if $rc;
    $out;
}
sub _tw_identity {                               # a name and e-mail for commits, unless the learner's git already has them
    my ($dir, $user) = @_;
    my (undef, $name) = _git($dir, 'config', 'user.name');
    return '' if $name =~ /\S/;
    _git($dir, 'config', 'user.name', $TW_NAME{$user});
    _git($dir, 'config', 'user.email', "$user\@example.invalid");
    "Commits here are signed $TW_NAME{$user} <$user\@example.invalid> (your git has no user.name yet; perl agile.pl help git-identity)";
}
sub _tw_scaffold {                               # kickoff.pl scaffold DIR (its own git init and first commit), plus .ci/layout.map in that commit
    my ($c) = @_;
    require Cwd;
    my ($rc, $out) = _run(Cwd::getcwd(), $^X, "$ROOT/tools/gitlab/kickoff.pl", 'scaffold', $c, '--project', $TW_P, '--title', 'Tidewater', '--levels', $TW_LEVELS);   # roots: set on the first import, when the model has them
    die "practice: kickoff.pl scaffold failed: $out" if $rc;
    make_path("$c/.ci");
    copy("$ROOT/examples/tidewater-v1/layout.map", "$c/.ci/layout.map") or die "practice: cannot copy examples/tidewater-v1/layout.map: $!\n";
    # the scaffold's CHANGELOG shows a filled-in example baseline; a new project has none yet (lesson 13 writes the first)
    my $cl = _slurp("$c/CHANGELOG.md") // '';
    $cl =~ s{^## \[baseline-\d+\].*?(?=^## |^\[Unreleased\]:|\z)}{}msg;
    $cl =~ s{^\[baseline-\d+\]:[^\n]*\n}{}mg;
    _spit("$c/CHANGELOG.md", $cl);
    _git($c, 'config', 'core.autocrlf', 'false');
    _git($c, 'config', 'merge.conflictstyle', 'diff3');
    _git($c, 'add', '.ci/layout.map', 'CHANGELOG.md');
    ($rc, $out) = _git($c, '-c', 'user.name=Tom', '-c', 'user.email=tom@example.invalid', 'commit', '-q', '--amend', '--no-edit');
    die "practice: cannot add .ci/layout.map to the scaffold commit: $out" if $rc;
}
sub _tw_first_import {                           # in a working tree on the drop branch: the inherited outline count and the docs
    my ($w) = @_;
    # the roots of the part and function trees exist now: name them in sysml.conf, as the scaffold's comments ask
    my $conf = _slurp("$w/sysml.conf") // '';
    $conf .= "noun_root     = ObservationNetwork\nverb_root     = ObserveCoast\n" unless $conf =~ /^noun_root\s*=/m;
    _spit("$w/sysml.conf", $conf);
    my (undef, $chk) = _run($w, $^X, "$ROOT/tools/sysml/model.pl", 'check');
    my ($v) = $chk =~ /^violations\s+(\d+)/m;
    my ($m) = $chk =~ /^\@L tag mismatches\s+(\d+)/m;
    _spit("$w/.ci/outline-max", (($v // 0) + ($m // 0)) . "\n");
    _tw_docs($w);
}
sub _tw_docs { my ($w) = @_; my ($rc, $out) = _run($w, $^X, "$ROOT/tools/sysml/model.pl", 'docs'); die "practice: model.pl docs failed: $out" if $rc && $out !~ /\S/ }
sub _setup_tw_model {                            # lesson 10: the scaffold, with drop v1.0 converted by the layout map and committed
    my ($dir, $info) = @_;
    my $d1 = _tw_drop($dir, 1);
    my $tmp = "$dir/.repo";
    _tw_scaffold($tmp);
    opendir my $dh, $tmp or die "practice: cannot read $tmp: $!\n";
    for my $e (grep { !/^\.\.?$/ } readdir $dh) { rename("$tmp/$e", "$dir/$e") or die "practice: cannot move $e into the sandbox: $!\n" }
    closedir $dh; rmdir $tmp;
    my $ig = _slurp("$dir/.gitignore") // '';
    _spit("$dir/.gitignore", $ig . ($ig =~ /\n\z/ || $ig eq '' ? '' : "\n") . ".practice\ndrops/\n");
    my ($rc, $out);
    for my $c ([ 'xmi2sysml.pl', "$d1/tidewater.xmi" ], [ 'reqif2sysml.pl', "$d1/tidewater.reqif" ]) {
        ($rc, $out) = _run($dir, $^X, "$ROOT/bin/$c->[0]", '--layout-map', '.ci/layout.map', '--out', 'model', $c->[1]);
        die "practice: $c->[0] failed on drop v1.0: $out" if $rc;
    }
    make_path("$dir/imports/v1.0");
    opendir $dh, $d1 or die; copy("$d1/$_", "$dir/imports/v1.0/$_") for grep { -f "$d1/$_" } readdir $dh; closedir $dh;
    _tw_first_import($dir);
    _git($dir, 'add', '-A');
    ($rc, $out) = _git($dir, '-c', 'user.name=Tom', '-c', 'user.email=tom@example.invalid', 'commit', '-q', '-m', 'Import prime drop v1.0 (converted with .ci/layout.map; inherited outline count; docs)');
    die "practice: cannot commit drop v1.0: $out" if $rc;
    my $who = _tw_identity($dir, 'bob');
    push @{ $info->{notes} }, "The file: vim $TW_ST   (in Vim: \\ml lint, \\mx grammar, \\mk level tags, :copen the list)", ($who ? $who : ());
}

sub _tw_clone {                                  # (gl, sandbox path, user) -> a GitFlow clone of the project for that person
    my ($gl, $path, $user) = @_;
    my $f = GitFlow->new(dir => $path, gl => $gl, project => $TW_P, user => $user, name => $TW_NAME{$user}, email => "$user\@example.invalid");
    if (-d "$path/.git") { $f->sync; return $f }
    $f->clone;
    $f->git('config', 'merge.conflictstyle', 'diff3');
    $f;
}
sub _tw_edit {                                   # (clone, file, sub) -> apply one of the government's edits to a file
    my ($f, $rel, $edit) = @_;
    my $p = $f->dir . "/$rel";
    my $t = _slurp($p) // die "practice: set-up cannot read $rel\n";
    my $n = $edit->($t);
    $n ne $t or die "practice: set-up edit of $rel changed nothing (the converter's output may have changed)\n";
    _spit($p, $n);
}
sub _tw_merge {                                  # approve as each reviewer, merge as the merger; the emulator runs the pipelines
    my ($gl, $mr, %o) = @_;
    for my $u (@{ $o{approvers} }) { $gl->as($u); eval { $gl->approve_mr($TW_P, $mr->{iid}); 1 } or die "practice: set-up approval of !$mr->{iid} by $u failed: $@" }
    $gl->as($o{merger});
    my $m = eval { $gl->merge_mr($TW_P, $mr->{iid}) } or die "practice: set-up merge of !$mr->{iid} ($mr->{title}) failed: $@";
    $m;
}
sub _tw_labels { my ($gl, @l) = @_; my %have = map { $_->{name} => 1 } @{ $gl->labels($TW_P) }; [ grep { $have{$_} } @l ] }
sub _tw_vendor { my ($f, $drop, $ver) = @_;      # gl flow vendor DROP VER, as gitlab.pl does it: the map read from the branch you are on
    my $map = $f->dir . '/.ci/layout.map';
    require File::Temp;
    my (undef, $copy) = File::Temp::tempfile(UNLINK => 1);              # outside the clone: vendor_import commits all it finds
    copy($map, $copy) or die "practice: cannot read $map: $!\n";
    my $r = $f->vendor_import(drop => $drop, version => $ver, convert => GitFlow::default_convert($ROOT, layout_map => $copy));
    unlink $copy;
    $r;
}

# The government's edits, as the people make them (each lesson's solution; the next lesson's set-up replays it)
sub _tw_tag_segment {                            # lesson 11: StationSegment's level TODO -> @L2Segment; import Conventions
    my $t = shift;
    $t =~ s{(    part def StationSegment \{\n)        // TODO stereotype Tidewater_Profile:L2Segment[^\n]*\n}{$1        \@L2Segment;\n};
    $t =~ s{(package Stations \{\n)(?!    private import Conventions::\*;)}{$1    private import Conventions::*;\n};
    $t;
}
sub _tw_interim_humidity {                       # before lesson 12: Bob models a humidity sensor ahead of the prime (DR-5)
    my $t = shift;
    $t =~ s{(        part thermometer : Thermometer;\n)}{$1        part humiditySensor : HumiditySensor;   // interim, ahead of the prime's drop (DR-5)\n};
    $t =~ s{(    part def Thermometer \{\n(?:        [^\n]*\n)*?    \}\n)}{$1    part def HumiditySensor {\n        \@L5Assembly;\n        doc /* Relative humidity. Interim: modeled by the government ahead of the prime's drop (DR-5). */\n    }\n};
    $t;
}
sub _tw_tag_hygrometer {                         # lesson 12: the prime's new Hygrometer gets the government's level tag
    my $t = shift;
    $t =~ s{(    part def Hygrometer \{\n)        // TODO stereotype Tidewater_Profile:L5Assembly[^\n]*\n}{$1        \@L5Assembly;\n};
    $t;
}
sub _tw_outline_now { my ($w) = @_; my (undef, $c) = _run($w, $^X, "$ROOT/tools/sysml/model.pl", 'check');
    my ($v) = $c =~ /^violations\s+(\d+)/m; my ($m) = $c =~ /^\@L tag mismatches\s+(\d+)/m; ($v // 0) + ($m // 0) }

sub _setup_tw_gitlab {                           # lessons 11-13: the offline GitLab, the project, and the history up to lesson $stage
    my ($dir, $info, $stage) = @_;
    require GitLab; require GitFlow; require Cwd;
    my $d1 = _tw_drop($dir, 1);
    my $d2 = $stage >= 12 ? _tw_drop($dir, 2) : undef;
    my $gl = GitLab->new(local => "$dir/gitlab");
    local $ENV{GITLAB_USER_LOGIN};
    my $ok = eval {
        $gl->create_user($_, name => $TW_NAME{$_}, email => "$_\@example.invalid") for qw(jim bob tom);
        $gl->as('tom');
        $gl->create_group('tidewater');
        $gl->create_project($TW_P);
        $gl->add_member($TW_P, @$_) for [ jim => 'maintainer' ], [ bob => 'developer' ], [ tom => 'maintainer' ];
        $gl->set_variable($TW_P, q(KIT), $ROOT);              # before the first push, so its pipeline can run
        # Tom: the scaffold (kickoff.pl scaffold) pushed to main, develop from it, then the scaffold's project file
        _tw_scaffold("$dir/.setup/scaffold");
        $ENV{GITLAB_USER_LOGIN} = 'tom';
        my ($rc, $out) = _git("$dir/.setup/scaffold", 'push', '-q', $gl->project($TW_P)->{http_url_to_repo}, 'main');
        die "practice: cannot push the scaffold: $out" if $rc;
        $gl->pushed($TW_P, 'refs/heads/main');
        my $tom = _tw_clone($gl, "$dir/.setup/tom", 'tom');
        $tom->init;
        $gl->apply_project_file("$dir/.setup/scaffold/.gitlab/project.conf", project => $TW_P);
        $gl->set_variable($TW_P, 'KIT', $ROOT);              # the project file names the runner's path; here the kit is this checkout
        # Tom: drop v1.0 through the vendor branch; the first import records the inherited outline count and the docs
        $gl->as('tom');
        $tom->sync;
        my $r = _tw_vendor($tom, $d1, $TW_VER{1});
        @{ $r->{conflicts} } and die "practice: drop v1.0 did not merge cleanly: @{ $r->{conflicts} }\n";
        _tw_first_import($tom->dir);
        $tom->commit('First import: record the inherited outline count; generate docs');
        my $mr = $tom->finish(title => 'Prime drop v1.0: the first import',
            description => "The prime's drop v1.0 (CDRL A003) as delivered in imports/v1.0/, converted by xmi2sysml.pl and reqif2sysml.pl with .ci/layout.map on vendor/prime and merged here. .ci/outline-max records the outline violations the v1 structure brings with it; docs/ is generated.");
        _tw_merge($gl, $mr, approvers => [q(jim), q(bob)], merger => 'tom');
        # Jim: lesson 11's task, as an issue for Bob
        $gl->as('jim');
        my $task = $gl->create_issue($TW_P, title => 'Tag StationSegment with its level (L2Segment)', assignees => ['bob'], milestone => 'Sprint 1',
            labels => _tw_labels($gl, 'type::task', 'workflow::ready'), description => <<"MD");
The converter left a TODO where the v1 profile gave **StationSegment** its level stereotype (L2Segment).
Replace it with the government's level tag from `model/library/conventions/Conventions.sysml`.

- [ ] A branch from develop: `gl flow start feature N-tag-stationsegment` (N = this issue's number)
- [ ] In `$TW_ST`: `\@L2Segment;` in place of the TODO line inside `part def StationSegment`
- [ ] In the same file: `private import Conventions::*;` as the first line inside `package Stations`
- [ ] A merge request that says `Closes #N`; its pipeline green; approved by a code owner; merged

Acceptance: the pipeline passes, and `model.pl check` reports 0 level-tag mismatches.
MD
        $info->{task} = $task->{iid};
        if ($stage >= 12) {
            $gl->as('bob'); $ENV{GITLAB_USER_LOGIN} = 'bob';
            my $bob = _tw_clone($gl, "$dir/.setup/bob", 'bob');
            $bob->start(feature => "$task->{iid}-tag-stationsegment");
            _tw_edit($bob, $TW_ST, \&_tw_tag_segment);
            $bob->commit('Tag StationSegment with its level (L2Segment)');
            $mr = $bob->finish(title => 'Tag StationSegment with its level', description => "Closes #$task->{iid}");
            _tw_merge($gl, $mr, approvers => ['jim'], merger => 'bob');
            # Jim raises DR-5 with the prime; Bob models the sensor ahead of the drop, as an interim
            $gl->as('jim');
            my $dr = $gl->create_issue($TW_P, title => 'DR-5: the sensor suite has no humidity sensor', assignees => ['jim'],
                labels => _tw_labels($gl, 'type::discrepancy', 'owner::prime'), description => <<'MD');
Discrepancy report to the prime: TW-STK-001 needs relative humidity, but the v1 sensor suite has no humidity sensor.
The prime agreed at the CCB to add one in drop v1.1. Until then the government models an interim `HumiditySensor`.

- [x] Raised with the prime's modeler
- [ ] Closed when a drop delivers the prime's own humidity sensor (the interim is then removed)
MD
            $gl->as('bob');
            $bob->sync;
            $bob->start(feature => 'interim-humidity');
            _tw_edit($bob, $TW_ST, \&_tw_interim_humidity);
            _tw_docs($bob->dir);
            $bob->commit('Interim humidity sensor, ahead of the prime (DR-5)');
            $mr = $bob->finish(title => 'Interim humidity sensor (DR-5)', description => "An interim HumiditySensor in the sensor suite until the prime delivers its own (see #$dr->{iid}).");
            _tw_merge($gl, $mr, approvers => ['jim'], merger => 'bob');
            $gl->as('jim');
            my $drop = $gl->create_issue($TW_P, title => 'Prime drop v1.1: intake', assignees => ['tom'], milestone => 'Sprint 2',
                labels => _tw_labels($gl, 'type::drop', 'owner::gov'), description => <<"MD");
The prime delivered drop v1.1 (CDRL A003) on 2027-01-08. It is in `drops/v1.1/` of the practice sandbox.

- [ ] `gl flow vendor ../drops/v1.1 v1.1`: the drop onto vendor/prime (converted with .ci/layout.map), then merged into feature/drop-v1.1
- [ ] Read what changed: `xmi2sysml.pl --delta` of v1.0 against v1.1
- [ ] Resolve the conflicts: the prime's model wins (upstream first); re-apply the government's edits
- [ ] Regenerate docs/; a merge request that closes this issue and #$dr->{iid}; pipeline green; approved; merged
MD
            $info->{dr} = $dr->{iid};
            $info->{drop} = $drop->{iid};
        }
        if ($stage >= 13) {
            $gl->as('tom'); $ENV{GITLAB_USER_LOGIN} = 'tom';
            $tom->sync;
            my $r2 = _tw_vendor($tom, $d2, $TW_VER{2});
            my @c = @{ $r2->{conflicts} };
            $tom->take(theirs => @c) if @c;                          # the prime's side, then the government's edits again
            _tw_edit($tom, $TW_ST, sub { _tw_tag_hygrometer(_tw_tag_segment($_[0])) });
            _tw_docs($tom->dir);
            $tom->git('add', '-A');
            $tom->git('commit', '-q', '--no-edit');
            $mr = $tom->finish(title => 'Prime drop v1.1', description => "Closes #$info->{drop} and #$info->{dr}");
            _tw_merge($gl, $mr, approvers => [q(jim), q(bob)], merger => 'tom');
        }
        1;
    };
    $gl->save;
    die $@ =~ /^practice:/ ? $@ : "practice: lesson set-up failed: $@" unless $ok;
    # the learner's clone and shell settings
    my $u = $TW_LEARNER{$stage};
    my $w = _tw_clone($gl, "$dir/work", $u);
    $w->git('checkout', '-q', 'develop') if $w->branch ne 'develop';
    $gl->save;
    _spit("$dir/env.sh", <<"SH");
# Lesson $stage: run this once in each new Git Bash window, from the work folder:   source ../env.sh
export KIT='$ROOT'
export GITLAB_LOCAL='$dir/gitlab'
export GITLAB_PROJECT='$TW_P'
export GITLAB_USER='$u'
gl() { perl "\$KIT/bin/gitlab.pl" "\$@"; }
echo "Lesson $stage: you are $TW_ROLE{$u}. gl = GitLab (offline). Try: gl issue list"
SH
    $info->{work} = "$dir/work";
    $info->{learner} = $u;
    push @{ $info->{notes} }, "First: cd $dir/work, then source ../env.sh   (you are $TW_ROLE{$u}; gl is GitLab, offline)";
}

# ---------------------------------------------------------------- checks
sub check {
    my ($n, $dir) = @_;
    my $info = _info($dir);
    my @r = $LESSON{$n}{check}->($dir, $info);
    my $ok = grep { $_->[0] } @r;
    printf "  %-5s %s\n", $_->[0] ? 'ok' : 'TODO', $_->[1] for @r;
    if ($ok == @r) { print "lesson $n: done\n"; return 0 }
    printf "lesson %d: not yet (%d of %d checks pass). The task: perl agile.pl help practice-%d\n", $n, $ok, scalar @r, $n;
    1;
}
sub _load { my ($dir, $today) = @_; require Scrum; my $s = eval { Scrum::load("$dir/scrum.txt", today => $today // _today()) }; $s }
sub _pending { my $dir = shift; require Standup; my @p = eval { Standup::pending("$dir/standups") }; @p }
sub _common {                                    # nothing pending, committed after the set-up, nothing uncommitted
    my ($dir, $info) = @_;
    my @p = _pending($dir);
    my ($rc, $cnt) = _git($dir, 'rev-list', '--count', ($info->{head} ? "$info->{head}..HEAD" : 'HEAD'));
    $cnt = $rc ? 0 : ($cnt =~ /(\d+)/ ? $1 : 0);
    my (undef, $st) = _git($dir, 'status', '--porcelain');
    $st = join "\n", grep { !/\.practice$/ } split /\n/, $st;
    ([ !@p, @p ? "stand-up files not compiled yet: @p (daily.pl compile)" : 'no pending stand-up files' ],
     [ $cnt >= 1 && $st !~ /\S/, $cnt < 1 ? 'no git commit of your work yet (daily.pl commit)' : $st =~ /\S/ ? "uncommitted changes (daily.pl commit):\n" . join("\n", map { "          $_" } split /\n/, $st) : 'your work is committed' ]);
}
sub _today_blocks {                              # the journal text compiled from stand-ups dated on or after $since
    my ($dir, $since) = @_;
    my $t = _slurp("$dir/scrum.txt") // '';
    my $out = '';
    for my $b (split /(?=^; ---- standup )/m, $t) { $out .= $b if $b =~ /^; ---- standup (\d{4}-\d{2}-\d{2})/ && $1 ge $since }
    $out;
}
sub check_1 {
    my ($dir, $info) = @_;
    my $s = _load($dir);
    return ([ 0, 'the journal does not load: daily.pl status shows the error' ]) unless $s;
    my @items = values %{ $s->{items} };
    my @in1 = grep { ($_->{sprint} // '') eq '1' && ($_->{state} // '') =~ /^(?:committed|done|carryover)$/ } @items;
    require Scrum;
    my $sum = eval { Scrum::sprint_summary($s, 1) } // {};
    my ($cap) = grep { ($_->{capacity} // 0) > 0 } values %{ $sum->{teams} // {} };
    ([ @items >= 3, scalar(@items) . " task(s) in the journal (want 3 or more: new lines)" ],
     [ @in1 >= 2, scalar(@in1) . " task(s) committed in sprint 1 (want 2 or more: commit lines)" ],
     [ $cap ? 1 : 0, $cap ? 'sprint 1 has a capacity' : 'no capacity for sprint 1 (a cap N line under the team)' ],
     _common($dir, $info));
}
sub check_2 {
    my ($dir, $info) = @_;
    my $t = _today_blocks($dir, $info->{today} // _today());
    my (%blocked, %unblocked, %carried);
    for (split /\n/, $t) {
        if (/; id: ([^,\s]+), blocked: ?(.*?)\s*$/) { if ($2 ne '') { $blocked{$1} = 1 } else { $unblocked{$1} = 1 } }
        $carried{$1} = 1 if /^\s+Sprint:\d+:[^:\s]+:Carryover\s+\d[\d.]*\s.*; id: (\S+)/;
    }
    my @both = grep { $unblocked{$_} } sort keys %blocked;
    ([ scalar(keys %blocked) >= 1, %blocked ? 'blocked today: ' . join(' ', sort keys %blocked) : 'no task blocked today (block ID REASON)' ],
     [ @both >= 1, @both ? "blocked and unblocked again: @both" : 'no blocked task unblocked again today (unblock ID in a second file)' ],
     [ scalar(keys %carried) >= 1, %carried ? 'carried today: ' . join(' ', sort keys %carried) : 'nothing carried today (carry ID)' ],
     _common($dir, $info));
}
sub check_3 {
    my ($dir, $info) = @_;
    my $s = _load($dir);
    return ([ 0, 'the journal does not load: daily.pl status shows the error' ]) unless $s;
    my $n = $info->{sprint} || $s->{current};
    require Scrum;
    my $r = Scrum::sprint_summary($s, $n)->{totals} // {};
    my $since = $info->{today} // _today();
    my @status = grep { m{/(\d{4}-\d{2}-\d{2})-status\.html$} && $1 ge $since } glob("$dir/reports/*-status.html");
    ([ ($r->{open} // 1) == 0, ($r->{open} // 1) == 0 ? "nothing open in sprint $n" : ($r->{open} // '?') . " points still open in sprint $n (done or carry each one)" ],
     [ -f "$dir/reports/sprint-$n-report.txt", -f "$dir/reports/sprint-$n-report.txt" ? "reports/sprint-$n-report.txt written" : "no reports/sprint-$n-report.txt (daily.pl review)" ],
     [ scalar @status, @status ? 'the status report is written' : 'no status report from today (daily.pl report)' ],
     _common($dir, $info));
}
sub check_4 {
    my ($dir, $info) = @_;
    my $d = $info->{today} // _today();
    my ($rc, $out) = _daily($dir, "--today=$d", 'lint');
    my @err = grep { / ERROR / } split /\n/, $out;
    my @ans = glob("$dir/standups/$d-*-answers.txt");
    ([ $rc == 0 && !@err, @err ? scalar(@err) . " status(es) with an ERROR still:\n" . join("\n", map { my $x = $_; $x =~ s/^.*?: (ERROR)/$1/; "          $x" } @err) : $rc ? "lint failed: $out" : 'lint finds no ERROR in today\'s chat' ],
     [ scalar @ans, @ans ? scalar(@ans) . " answers file(s) for $d" : "no answers file for $d (daily.pl answers)" ]);
}
sub check_5 {
    my ($dir, $info) = @_;
    my ($n, $right) = (0, 0);
    for (split /\n/, _slurp("$dir/drill.txt") // '') { next if /^\s*#/; my @f = map { my $x = $_; $x =~ s/^\s+|\s+$//g; $x } split /\|/, $_, 7; next unless @f >= 5; $n++ if ($f[3] || 0) + ($f[4] || 0) > 0; $right += $f[3] || 0 }
    ([ $n >= 6, "$n card(s) graded in drill.txt (want 6 or more: drill --sheet, answer, drill --grade)" ],
     [ $right >= 1, "$right right answer(s)" ]);
}
sub check_6 {
    my ($dir, $info) = @_;
    my @m = glob("$dir/model/*.txt");
    my ($rc, $out) = _run($dir, $^X, "$ROOT/tools/idef0/idef0.pl", 'lint', @m);
    my ($sum) = $out =~ /^(\d+ file\(s\): .*)$/m;
    my $html = _slurp("$dir/plates.html") // '';
    my $newest = 0; for (@m) { my $t = (stat $_)[9]; $newest = $t if $t > $newest }
    my $fresh = -f "$dir/plates.html" && (stat "$dir/plates.html")[9] >= $newest;
    ([ $rc == 0, $rc == 0 ? 'the model lints clean' : 'lint still reports errors: ' . ($sum // $out) ],
     [ $html =~ /<svg/ && $fresh, !-f "$dir/plates.html" ? 'no plates.html (idef0.pl html model/*.txt > plates.html)' : $html !~ /<svg/ ? 'plates.html has no SVG plates' : $fresh ? 'plates.html is up to date' : 'plates.html is older than the model: render it again' ]);
}
sub check_7 {
    my ($dir, $info) = @_;
    my $md = _slurp("$dir/memo.md") // '';
    my $n = $info->{sprint} // '?';
    my $pdf = _slurp("$dir/memo.pdf") // '';
    my $fresh = -f "$dir/memo.pdf" && (stat "$dir/memo.pdf")[9] >= ((stat "$dir/memo.md")[9] // 0);
    ([ $md ne '' && $md !~ /TODO/, $md =~ /TODO/ ? 'memo.md still has TODO marks' : 'every TODO is replaced' ],
     [ $md =~ /\bsprint\s+$n\b/i, "memo.md names the current sprint (sprint $n)" ],
     [ substr($pdf, 0, 4) eq '%PDF' && $fresh, !$pdf ? 'no memo.pdf (md2memo.pl memo.md > memo.pdf)' : substr($pdf, 0, 4) ne '%PDF' ? 'memo.pdf is not a PDF' : $fresh ? 'memo.pdf is rendered from the latest memo.md' : 'memo.pdf is older than memo.md: render it again' ],
     [ -s "$dir/memo.txt" ? 1 : 0, -s "$dir/memo.txt" ? 'memo.txt written' : 'no memo.txt (md2memo.pl --plain memo.md > memo.txt)' ]);
}
sub check_8 {
    my ($dir, $info) = @_;
    my @f;
    require File::Find;
    File::Find::find({ no_chdir => 1, wanted => sub { push @f, $_ if /\.sysml$/ } }, "$dir/model") if -d "$dir/model";
    @f = sort @f;
    my ($rc, $out) = @f ? _run($dir, $^X, "$ROOT/tools/sysml/sysml.pl", 'check', @f) : (1, '');
    my ($open, $reviewed) = (0, 0);
    for my $f (@f) { for (split /\n/, _slurp($f) // '') { next unless m{//\s*TODO\b}; if (m{//\s*TODO\(reviewed\)}) { $reviewed++ } else { $open++ } } }
    my $notes = _slurp("$dir/NOTES.txt") // '';
    my ($said) = $notes =~ /^\s*TODO:\s*(\d+)/m;
    my $left = $open + $reviewed;
    my ($grc, $st) = _git($dir, 'status', '--porcelain');
    my ($crc, $cnt) = _git($dir, 'rev-list', '--count', ($info->{head} ? "$info->{head}..HEAD" : 'HEAD'));
    my $lrc = $crc || $cnt !~ /[1-9]/;
    ([ scalar @f, @f ? scalar(@f) . " .sysml file(s) under model/" : 'no .sysml files under model/ (xmi2sysml.pl --out model --check legacy.xmi)' ],
     [ @f && $rc == 0, !@f ? 'sysml.pl check: nothing to check yet' : $rc == 0 ? 'sysml.pl check passes' : 'sysml.pl check finds errors: ' . ((grep { /error/ } split /\n/, $out)[0] // $out) ],
     [ @f && $open == 0, $open ? "$open TODO line(s) neither fixed nor marked TODO(reviewed)" : "no open TODO lines ($reviewed marked reviewed)" ],
     [ defined $said && $said == $left, !defined $said ? 'NOTES.txt has no "TODO: N" line' : $said == $left ? "NOTES.txt counts $left TODO line(s) left, right" : "NOTES.txt says TODO: $said, but $left TODO line(s) are left" ],
     [ !$lrc && $st !~ /\S/, $lrc ? 'nothing committed yet (git add model NOTES.txt; git commit)' : $st =~ /\S/ ? 'uncommitted changes (git status)' : 'the port is committed' ]);
}
sub check_9 {
    my ($dir, $info) = @_;
    my $id = 'p12-dedup';
    my (@start, @pass, @log);
    for (split /\n/, _slurp("$dir/attempts.txt") // '') { my @f = split /\t/; next unless @f >= 3 && $f[2] eq $id; push @start, 1 if $f[1] eq 'start'; push @pass, 1 if $f[1] eq 'test' && ($f[3] // '') =~ /^pass/ }
    for (split /\n/, _slurp("$dir/log.txt") // '') { next if /^\s*#/; my @f = map { my $x = $_; $x =~ s/^\s+|\s+$//g; $x } split /\|/, $_, 5; push @log, \@f if @f >= 4 && $f[1] eq $id }
    my $mine = _slurp("$dir/$id.pl") // '';
    my $stub = _slurp("$ROOT/drills/01-ladder/$id/stub.pl") // '';
    ([ scalar @start, @start ? "$id started" : "$id not started (drill.pl start $id)" ],
     [ $mine ne '' && $mine ne $stub, $mine eq '' ? "no $id.pl in the sandbox" : $mine eq $stub ? "$id.pl is still the stub: write the solution" : "$id.pl holds your solution" ],
     [ scalar @pass, @pass ? "a passing test of $id is recorded" : "no passing test of $id yet (drill.pl test $id)" ],
     [ scalar(grep { $_->[3] eq 'pass' } @log), @log ? "the drill log has $id" . ((grep { $_->[3] eq 'pass' } @log) ? '' : ' but not as passed') : "no drill log entry for $id (drill.pl log $id NOTE)" ]);
}

# ---------------------------------------------------------------- Tidewater checks (10-13)
sub _tw_block {                                  # (text, part def name) -> the lines inside `part def NAME { ... }` at package level
    my ($t, $name) = @_;
    my ($b) = $t =~ /^    part def \Q$name\E\b[^\n]*\{\n(.*?)^    \}/ms;
    $b // '';
}
sub _tw_stations_checks {                        # what develop's (or the clone's) Stations.sysml must hold after lesson 11
    my ($t) = @_;
    my $seg = _tw_block($t, 'StationSegment');
    ([ $seg =~ /^\s*\@L2Segment\s*;/m && $seg !~ m{TODO stereotype Tidewater_Profile:L2Segment},
       $seg eq '' ? '$TW_ST has no part def StationSegment' : $seg =~ m{TODO stereotype Tidewater_Profile:L2Segment} ? 'StationSegment still has its level TODO line: replace it with @L2Segment;' : $seg =~ /^\s*\@L2Segment\s*;/m ? 'StationSegment carries @L2Segment;' : 'StationSegment has no "@L2Segment;" line (spelled exactly so, with the semicolon)' ],
     [ scalar($t =~ /^\s*(?:private\s+)?import\s+Conventions::\*\s*;/m), $t =~ /import\s+Conventions::\*/ ? 'package Stations imports Conventions' : 'package Stations does not import Conventions: add "private import Conventions::*;" under "package Stations {"' ]);
}
sub _tw_open {                                   # the sandbox's GitLab, read-only (nothing is saved)
    my ($dir) = @_;
    return undef unless -f "$dir/gitlab/gitlab.json";
    require GitLab;
    GitLab->new(local => "$dir/gitlab");
}
sub _tw_show {                                   # (gl, ref:path) -> file text from the project's repository, or undef
    my ($dir, $gl, $spec) = @_;
    my $bare = $gl->project($TW_P)->{http_url_to_repo};
    my ($rc, $out) = _run($dir, 'git', '--git-dir', $bare, 'show', $spec);
    $rc ? undef : $out;
}
sub _tw_git { my ($dir, $gl, @a) = @_; my ($rc, $out) = _run($dir, 'git', '--git-dir', $gl->project($TW_P)->{http_url_to_repo}, @a); $out =~ s/\s+$//; ($rc, $out) }
sub _tw_mr_checks {                              # the common checks of a merge request: green at the end, approved by another person, merged
    my ($gl, $mr, $who) = @_;
    my @st = map { my $id = $_; (eval { $gl->pipeline($TW_P, $id)->{status} } // '?') } @{ $mr->{pipelines} // [] };
    my @by = grep { $_ ne $who } map { $_->{user}{username} } @{ $mr->{approved_by} // [] };
    ([ @st && $st[-1] eq 'success', !@st ? "!$mr->{iid} has no pipeline yet" : $st[-1] eq 'success' ? "!$mr->{iid}'s latest pipeline passed" : "!$mr->{iid}'s latest pipeline is $st[-1]: gl mr show $mr->{iid}, fix, commit, gl flow publish" ],
     [ scalar @by, @by ? "!$mr->{iid} approved by @by" : "!$mr->{iid} has no approval from someone else yet (gl --as jim mr approve $mr->{iid}; gl mr merge $mr->{iid} says who is still needed)" ],
     [ $mr->{state} eq 'merged', $mr->{state} eq 'merged' ? "!$mr->{iid} is merged" : "!$mr->{iid} is $mr->{state}: gl mr merge $mr->{iid}" ]);
}
sub _tw_closes { my ($mr, @n) = @_; my $d = $mr->{description} // ''; grep { $d =~ /\b(?:[Cc]los(?:e|es|ed)|[Ff]ix(?:es|ed)?|[Rr]esolv(?:e|es|ed))\b[^\n]*#$_\b/ } @n }

sub check_10 {
    my ($dir, $info) = @_;
    my $f = "$dir/$TW_ST";
    my $t = _slurp($f);
    return ([ 0, "no $TW_ST: perl agile.pl practice 10 sets the lesson up again" ]) unless defined $t;
    my ($grc, $gout) = _run($dir, $^X, "$ROOT/tools/sysml/sysml.pl", q(check), $TW_ST);
    my (undef, $lint) = _run($dir, $^X, "$ROOT/tools/sysml/model.pl", 'lint');
    my (undef, $chk) = _run($dir, $^X, "$ROOT/tools/sysml/model.pl", 'check');
    my ($lastl) = grep { /^elements=/ } reverse split /\n/, $lint;
    my ($mis) = $chk =~ /^\@L tag mismatches\s+(\d+)/m;
    my (undef, $st) = _git($dir, 'status', '--porcelain');
    my ($crc, $cnt) = _git($dir, 'rev-list', '--count', ($info->{head} ? "$info->{head}..HEAD" : 'HEAD'));
    my $committed = !$crc && $cnt =~ /[1-9]/;
    (_tw_stations_checks($t),
     [ $grc == 0, $grc == 0 ? 'the grammar check passes' : 'the grammar check finds an error (\\mx in Vim): ' . ((grep { /error/ } split /\n/, $gout)[0] // $gout) ],
     [ ($lastl // '') =~ /errors=0 warnings=0$/, defined $lastl ? "model.pl lint: $lastl" . ($lastl =~ /errors=0 warnings=0$/ ? '' : ' (\\ml in Vim, then :copen)') : 'model.pl lint did not finish: ' . (split /\n/, $lint)[-1] ],
     [ defined $mis && $mis == 0, !defined $mis ? 'model.pl check did not run' : $mis ? "model.pl check: $mis level tag(s) at the wrong level (\\mk in Vim)" : 'every level tag sits at its level (model.pl check)' ],
     [ $committed && $st !~ /\S/, !$committed ? 'nothing committed yet (git add model; git commit -m "Tag StationSegment with its level")' : $st =~ /\S/ ? "uncommitted changes (git status):\n" . join("\n", map { "          $_" } split /\n/, $st) : 'your change is committed' ]);
}
sub check_11 {
    my ($dir, $info) = @_;
    my $gl = _tw_open($dir) or return ([ 0, 'no offline GitLab in the sandbox: perl agile.pl practice 11 sets the lesson up again' ]);
    my $n = $info->{task};
    my @mr = sort { $b->{iid} <=> $a->{iid} } grep { ($_->{author}{username} // '') eq 'bob' && $_->{target_branch} eq 'develop' && $_->{source_branch} =~ m{^feature/} } @{ $gl->mrs($TW_P) };
    my ($mr) = ((grep { _tw_closes($_, $n) } @mr), @mr);
    my @r = ([ $mr ? 1 : 0, $mr ? "your merge request: !$mr->{iid} $mr->{source_branch} -> develop" : 'no merge request from a feature branch yet (gl flow start feature ' . $n . '-tag-stationsegment; edit; git commit; gl flow finish)' ]);
    return @r unless $mr;
    my @st = map { my $id = $_; (eval { $gl->pipeline($TW_P, $id)->{status} } // '?') } @{ $mr->{pipelines} // [] };
    push @r, [ scalar(_tw_closes($mr, $n)), _tw_closes($mr, $n) ? "its description says Closes #$n" : "its description does not say \"Closes #$n\" (gl mr note can't change it: open a new one, or see :help agile-practice-11)" ],
             [ scalar(grep { $_ eq 'failed' } @st), (grep { $_ eq 'failed' } @st) ? 'you saw a red pipeline and what it said' : 'no red pipeline yet: step 4 asks you to type "@L2Segment" without its semicolon first, and push' ],
             _tw_mr_checks($gl, $mr, 'bob');
    my $issue = eval { $gl->issue($TW_P, $n) };
    push @r, [ $issue && $issue->{state} eq 'closed', !$issue ? "no issue #$n" : $issue->{state} eq 'closed' ? "issue #$n is closed" : "issue #$n is still open (it closes when an MR that says Closes #$n merges)" ];
    my $t = _tw_show($dir, $gl, "develop:$TW_ST") // '';
    push @r, map { [ $_->[0], "on develop: $_->[1]" ] } _tw_stations_checks($t);
    @r;
}
sub check_12 {
    my ($dir, $info) = @_;
    my $gl = _tw_open($dir) or return ([ 0, 'no offline GitLab in the sandbox: perl agile.pl practice 12 sets the lesson up again' ]);
    my ($drop, $dr) = @$info{qw(drop dr)};
    my $man = _tw_show($dir, $gl, 'vendor/prime:imports/v1.1/MANIFEST.txt');
    my @r = ([ defined $man, defined $man ? 'drop v1.1 is on vendor/prime' : 'drop v1.1 is not on vendor/prime yet (gl flow vendor ../drops/v1.1 v1.1)' ]);
    my @mr = sort { $b->{iid} <=> $a->{iid} } grep { $_->{source_branch} =~ m{^feature/drop-v1\.1} && $_->{target_branch} eq 'develop' } @{ $gl->mrs($TW_P) };
    my $mr = $mr[0];
    push @r, [ $mr ? 1 : 0, $mr ? "your merge request: !$mr->{iid} $mr->{source_branch} -> develop" : 'no merge request from feature/drop-v1.1 yet (resolve, git add, git commit, gl flow finish)' ];
    return @r unless $mr;
    my @c = _tw_closes($mr, $drop, $dr);
    push @r, [ @c == 2, @c == 2 ? "its description closes #$drop and #$dr" : "its description should say \"Closes #$drop and #$dr\" (the drop intake and DR-5)" ], _tw_mr_checks($gl, $mr, $mr->{author}{username} // 'tom');
    for my $i ([ $drop, 'the drop intake' ], [ $dr, 'DR-5' ]) {
        my $is = eval { $gl->issue($TW_P, $i->[0]) };
        push @r, [ $is && $is->{state} eq 'closed', "issue #$i->[0] ($i->[1]) is " . ($is ? $is->{state} : 'missing') ];
    }
    my $t = _tw_show($dir, $gl, "develop:$TW_ST") // '';
    my $hyg = _tw_block($t, 'Hygrometer');
    push @r, [ $t ne '' && $t !~ /^(?:<<<<<<<|\|\|\|\|\|\|\||=======|>>>>>>>)/m, $t =~ /^(?:<<<<<<<|>>>>>>>)/m ? "conflict markers are still in $TW_ST on develop" : 'no conflict markers left' ],
             [ $t !~ /HumiditySensor/, $t =~ /HumiditySensor/ ? 'the interim HumiditySensor is still there: the prime delivered its own Hygrometer, so the interim goes (upstream first)' : 'the interim HumiditySensor is gone' ],
             [ scalar(_tw_block($t, q(SensorSuite)) =~ /^\s*part hygrometer : Hygrometer;/m), 'the sensor suite has the prime\'s "part hygrometer : Hygrometer;"' ],
             [ $hyg =~ /^\s*\@L5Assembly\s*;/m && $hyg !~ /TODO stereotype/, $hyg eq '' ? 'no part def Hygrometer on develop' : $hyg =~ /TODO stereotype/ ? 'Hygrometer still has its level TODO: replace it with @L5Assembly; (the government edit, re-applied)' : 'Hygrometer carries @L5Assembly;' ],
             map { [ $_->[0], "kept: $_->[1]" ] } _tw_stations_checks($t);
    @r;
}
sub check_13 {
    my ($dir, $info) = @_;
    my $gl = _tw_open($dir) or return ([ 0, 'no offline GitLab in the sandbox: perl agile.pl practice 13 sets the lesson up again' ]);
    my @mr = sort { $b->{iid} <=> $a->{iid} } grep { $_->{source_branch} =~ m{^release/} && $_->{target_branch} eq 'main' } @{ $gl->mrs($TW_P) };
    my $mr = $mr[0];
    my @r = ([ $mr ? 1 : 0, $mr ? "your release merge request: !$mr->{iid} $mr->{source_branch} -> main" : 'no merge request from a release branch to main yet (gl flow start release baseline-1; the CHANGELOG; gl flow finish)' ]);
    return @r unless $mr;
    (my $name = $mr->{source_branch}) =~ s{^release/}{};
    my $tag = $name =~ /^baseline-/ ? $name : "baseline-$name";
    push @r, _tw_mr_checks($gl, $mr, $mr->{author}{username} // 'jim');
    my $cl = _tw_show($dir, $gl, "main:CHANGELOG.md") // '';
    my $sec = qr/^##\s+\[?\Q$tag\E\]?(?:\s|$)/m;
    push @r, [ scalar($cl =~ $sec), $cl =~ $sec ? "CHANGELOG.md on main has a \"## [$tag]\" section" : "CHANGELOG.md on main has no \"## [$tag] -- DATE\" section (write it on the release branch, from [Unreleased], before gl flow finish)" ];
    my (undef, $tsha) = _tw_git($dir, $gl, 'rev-parse', "refs/tags/$tag^{commit}");
    my (undef, $ttype) = _tw_git($dir, $gl, 'cat-file', '-t', "refs/tags/$tag");
    my (undef, $tmsg) = _tw_git($dir, $gl, 'cat-file', '-p', "refs/tags/$tag");
    my $at = ($mr->{merge_commit_sha} // '') ne '' && $tsha eq $mr->{merge_commit_sha};
    push @r, [ $at && $ttype eq 'tag' && $tmsg =~ /sha256=[0-9a-f]{64}/, $tsha !~ /^[0-9a-f]{40}$/ ? "no tag $tag yet (gl flow released $mr->{iid} --notes CHANGELOG.md)" : !$at ? "tag $tag is not on the release merge commit" : "tag $tag marks the baseline, with its docs checksum" ];
    my ($rel) = grep { $_->{tag_name} eq $tag } @{ $gl->releases($TW_P) };
    push @r, [ $rel ? 1 : 0, $rel ? "release $tag is published" : "no release for $tag (gl flow released $mr->{iid} makes it)" ];
    my ($back) = sort { $b->{iid} <=> $a->{iid} } grep { $_->{source_branch} eq 'main' && $_->{target_branch} eq 'develop' } @{ $gl->mrs($TW_P) };
    push @r, $back ? _tw_mr_checks($gl, $back, $back->{author}{username} // 'jim') : [ 0, 'no back-merge MR main -> develop (gl flow released makes it)' ];
    my ($arc) = _tw_git($dir, $gl, 'merge-base', '--is-ancestor', 'main', 'develop');
    push @r, [ $arc == 0, $arc == 0 ? 'develop holds everything on main' : 'develop does not hold main yet: merge the back-merge MR' ];
    my (undef, $dev) = _tw_git($dir, $gl, 'rev-parse', 'develop');
    my $pg = eval { $gl->pages($TW_P) } // {};
    push @r, [ ($pg->{sha} // '') eq $dev, ($pg->{sha} // '') eq $dev ? "the model site is rebuilt from develop: gl pages ($pg->{url})" : 'the model site is older than develop (it rebuilds when the back-merge merges: gl pipeline list)' ];
    @r;
}

1;
