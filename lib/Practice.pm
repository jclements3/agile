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
    print "In it:      cd $dir\n";
    print "daily.pl  = perl $ROOT/bin/daily.pl   (an alias saves typing: perl agile.pl help alias)\n";
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

1;
