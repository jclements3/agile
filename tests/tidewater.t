#!/usr/bin/perl
# perl tests/tidewater.t -- the Tidewater simulation (sim/tidewater-sim.pl) for the first twelve weeks:
#   (a) the committed evidence in docs/tidewater/ (sprints/, journal/, samples/, README.md) is what the current sources produce
#       (sim/tidewater-evidence.pl over a fresh run, byte for byte);
#   (b) the run keeps the project's rules: tasks <= 5 points and closed within 5 working days of starting, stories inside
#       their sprint (carryovers listed, at most 6), epics <= 13 sprints, tomes <= 26, every merged MR green with an
#       approval by a code owner other than its author, baseline tags rebuild, journal sprint totals = GitLab task points.
# A run takes several minutes, so it is cached under the temp directory, keyed by a checksum of the sources it depends
# on (TIDEWATER_CACHE=DIR to choose the place). Under Git for Windows' Perl it is skipped unless TIDEWATER_FULL=1
# (process starts are slow there; the same code is tested under WSL). TIDEWATER_SKIP=1 skips everything.
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use File::Spec;
use File::Path qw(make_path remove_tree);
use File::Temp qw(tempdir);
use File::Find ();
use Digest::SHA ();
use Time::Local qw(timegm);

my ($n, $bad) = (0, 0);
sub check { my ($name, $got, $want) = @_; $n++;
    if ($got eq $want) { print "ok $n - $name\n" }
    else { $bad++; print "not ok $n - $name\n#   got:  $got\n#   want: $want\n" } }
sub ok { my ($c, $name, @why) = @_; $n++; if ($c) { print "ok $n - $name\n" } else { $bad++; print "not ok $n - $name\n", map { "#   $_\n" } @why } $c }
sub skip_all { print "1..0 # skip $_[0]\n"; exit 0 }
sub done { print "1..$n\n"; print $bad ? "# $bad of $n FAILED\n" : "# all $n passed\n"; exit($bad ? 1 : 0) }
sub slurp { my $f = shift; open my $fh, '<:raw', $f or return undef; local $/; my $t = <$fh>; close $fh; $t // '' }
sub files_under { my $d = shift; my @f; return () unless -d $d;
    File::Find::find({ no_chdir => 1, wanted => sub { push @f, $File::Find::name if -f $_ } }, $d); sort @f }

my $ROOT = File::Spec->rel2abs("$FindBin::Bin/..");
skip_all('TIDEWATER_SKIP=1') if $ENV{TIDEWATER_SKIP};

# ---------------------------------------------------------------- fast, no run: the committed page matches the committed evidence
if (-d "$ROOT/docs/tidewater/sprints") {
    my $tmp = tempdir(CLEANUP => 1);
    my $out = qx("$^X" "$ROOT/sim/tidewater-render.pl" --evidence "$ROOT/docs/tidewater" --out "$tmp/TIDEWATER.html" --quiet 2>&1);
    check('sim/tidewater-render.pl renders the committed evidence', $?, 0);
    print map { "#   $_\n" } split /\n/, $out if $?;
    ok((slurp("$ROOT/docs/TIDEWATER.html") // '') eq (slurp("$tmp/TIDEWATER.html") // 'x'), 'docs/TIDEWATER.html is what sim/tidewater-render.pl writes from docs/tidewater', 'refresh it: perl sim/tidewater-render.pl');
    my $page = slurp("$tmp/TIDEWATER.html") // '';
    ok($page !~ /<script|src="http|href="http/i, 'the page loads nothing external and runs no script');
    my $ws = eval { require JSON::PP; JSON::PP->new->decode(slurp("$ROOT/docs/tidewater/work-split.json") // '') };
    my @miss;
    if ($ws) {
        push @miss, map { "s1_6.$_" } grep { !defined $ws->{s1_6}{$_} } qw(points engineering platform learning);
        push @miss, map { "s1_39.$_" } grep { !defined $ws->{s1_39}{$_} } qw(points engineering platform learning);
        push @miss, map { "ceremony_hours.$_" } grep { !defined $ws->{ceremony_hours}{$_} } qw(standup kickoff refinement review retro total share_of_sprint);
        push @miss, map { "time.$_" } grep { !defined $ws->{time}{$_} } qw(engineering platform learning ceremonies other);
        for my $s (1 .. 6) { push @miss, map { "sprints.$s.$_" } grep { !defined(($ws->{sprints}{$s} // {})->{$_}) } qw(points engineering platform learning overhead) }
        push @miss, 'source' unless ($ws->{source} // '') =~ /\S/;
        # units: points are sums of points; engineering/platform/learning/overhead are percent of those points
        my $sum = 0; $sum += ($ws->{sprints}{$_} // {})->{points} // 0 for 1 .. 6;
        push @miss, "s1_6.points is $ws->{s1_6}{points}, not the sum of sprints.1-6.points ($sum)" if abs(($ws->{s1_6}{points} // -1) - $sum) > 1e-6;
        my $all = 0; $all += $_->{points} // 0 for values %{ $ws->{sprints} };
        push @miss, "s1_39.points is $ws->{s1_39}{points}, not the sum of every sprints.N.points ($all)" if abs(($ws->{s1_39}{points} // -1) - $all) > 1e-6;
        for my $k ('s1_6', 's1_39', map { "sprints.$_" } sort keys %{ $ws->{sprints} }) {
            my $h = $k =~ /^sprints\.(\d+)$/ ? $ws->{sprints}{$1} : $ws->{$k};
            my $p = 0; $p += $h->{$_} // 0 for qw(engineering platform learning);
            push @miss, "$k: engineering+platform+learning = $p, not ~100 (percent)" if ($h->{points} // 0) > 0 && abs($p - 100) > 2;
            push @miss, "$k.overhead is not platform+learning" if defined $h->{overhead} && abs($h->{overhead} - ($h->{platform} // 0) - ($h->{learning} // 0)) > 2;
        }
        my $t = 0; $t += $ws->{time}{$_} // 0 for qw(engineering platform learning ceremonies other);
        push @miss, "time.* sums to $t, not 100" unless $t == 100;
    }
    ok($ws && !@miss, 'docs/tidewater/work-split.json has every key the primer\'s BLUF cites', $ws ? "@miss" : 'not readable JSON');
    my $chk = qx("$^X" "$ROOT/sim/primer.pl" --check --draft 2>&1);
    my @bluf = grep { /00-bluf\.txt/ && !/warning|not written yet/i } split /\n/, $chk;
    ok(!@bluf, 'sim/primer.pl --check --draft reports no error in 00-bluf.txt', @bluf[0 .. ($#bluf < 4 ? $#bluf : 4)]);
    my @dead = grep { !-e "$ROOT/docs/$_" } $page =~ /href="(tidewater\/[^"#]+)"/g;
    ok(!@dead, 'every evidence link on the page points at a committed file', "@dead[0 .. ($#dead < 4 ? $#dead : 4)]");
}
if ($^O =~ /^(?:cygwin|msys|MSWin32)$/ && !$ENV{TIDEWATER_FULL}) {
    print "# skip: the Tidewater run takes minutes under Git for Windows' Perl (slow process starts); it is tested under WSL -- set TIDEWATER_FULL=1 to run it here\n";
    $n ? done() : skip_all('the Tidewater run is tested under WSL (TIDEWATER_FULL=1 to run it here) and docs/tidewater/sprints is not committed yet');
}
chomp(my $git = `git --version 2>&1`); skip_all('git is not on PATH') unless $git =~ /^git version/;

# ---------------------------------------------------------------- the run, cached by the sources' checksum
my @SRC;
for my $pat ('sim/tidewater-*.pl', 'lib/*.pm', 'bin/*.pl', 'tools/gitlab/*.pl', 'tools/sysml/*.pl', 'tools/sysml/views/*.pl', 'tools/memo/*.pl',
             'tools/idef0/idef0.pl', 'examples/tidewater-v1/*') { push @SRC, glob("$ROOT/$pat") }
push @SRC, files_under("$ROOT/tools/gitlab/templates");
my $sha = Digest::SHA->new(256);
for my $f (sort @SRC) { next unless -f $f; (my $rel = $f) =~ s{^\Q$ROOT\E/}{}; $sha->add("$rel\0", slurp($f), "\0") }
my $key = substr($sha->hexdigest, 0, 16);
my $cache = $ENV{TIDEWATER_CACHE} // File::Spec->catdir(File::Spec->tmpdir, "tidewater-sim-$key");
my $RUN = "$cache/data/tidewater";
if (!-f "$cache/done") {
    remove_tree($cache); make_path("$cache/data");
    print "# running sim/tidewater-sim.pl --sprints 6 (cached in $cache) -- this takes several minutes\n";
    my $rc = system("\"$^X\" \"$ROOT/sim/tidewater-sim.pl\" --dir \"$RUN\" --sprints 6 --no-docs --quiet > \"$cache/run.log\" 2>&1");
    if ($rc) {
        my @tail = (split /\n/, slurp("$cache/run.log"))[-15 .. -1];
        ok(0, 'the simulation runs sprints 1-6', 'exit ' . ($rc >> 8) . " -- the end of $cache/run.log:", grep { defined } @tail);
        done();
    }
    open my $fh, '>', "$cache/done" or die "cannot write $cache/done: $!\n"; close $fh;
}
ok(-d "$RUN/sprints/06", 'the simulation runs sprints 1-6', "no $RUN/sprints/06");

# ---------------------------------------------------------------- (a) the committed evidence is current
{
    my $tmp = tempdir(CLEANUP => 1);
    my $out = qx("$^X" "$ROOT/sim/tidewater-evidence.pl" "$RUN" --out "$tmp/ev" --sprints 6 --quiet 2>&1);
    check('sim/tidewater-evidence.pl copies the evidence (every curated sample found)', $?, 0);
    print map { "#   $_\n" } split /\n/, $out if $?;
    my $have = "$ROOT/docs/tidewater";
    my %want = map { (my $r = $_) =~ s{^\Q$tmp/ev\E/}{}; ($r => $_) } grep { m{/ev/(?:sprints|journal|samples)/} || m{/ev/README\.md$} } files_under("$tmp/ev");
    my %got  = map { (my $r = $_) =~ s{^\Q$have\E/}{}; ($r => $_) } grep { m{/tidewater/(?:sprints|journal|samples)/} || m{/tidewater/README\.md$} } files_under($have);
    my @missing = grep { !$got{$_} } sort keys %want;
    my @extra   = grep { !$want{$_} } sort keys %got;
    my @differ  = grep { $got{$_} && slurp($got{$_}) ne slurp($want{$_}) } sort keys %want;
    my $fix = 'refresh it: perl sim/tidewater-evidence.pl RUN_DIR (RUN_DIR from perl sim/tidewater-sim.pl --sprints 6 --dir ...)';
    ok(!@missing, 'docs/tidewater has every evidence file the run produces (' . scalar(keys %want) . ')', scalar(@missing) . " missing, e.g. @missing[0 .. ($#missing < 4 ? $#missing : 4)]", $fix);
    ok(!@extra, 'docs/tidewater has no evidence file the run no longer produces', scalar(@extra) . " extra, e.g. @extra[0 .. ($#extra < 4 ? $#extra : 4)]", $fix);
    ok(!@differ, 'every committed evidence file is byte-identical to the fresh run', scalar(@differ) . " differ, e.g. @differ[0 .. ($#differ < 4 ? $#differ : 4)]", $fix);
    # the run is deterministic: a second copy of the same run gives the same bytes (normalization is complete)
    my $out2 = qx("$^X" "$ROOT/sim/tidewater-evidence.pl" "$RUN" --out "$tmp/ev2" --sprints 6 --quiet 2>&1);
    my @d2 = grep { slurp("$tmp/ev2/$_") ne slurp($want{$_}) } sort keys %want;
    ok(!@d2, 'copying the same run twice gives identical bytes', "@d2[0 .. ($#d2 < 4 ? $#d2 : 4)]");
    my @abs = grep { my $t = slurp($want{$_}); $t =~ m{/mnt/[a-z]/|\Q$ROOT\E|\Q$RUN\E} } sort keys %want;
    ok(!@abs, 'no absolute path of this machine in the evidence', "@abs[0 .. ($#abs < 4 ? $#abs : 4)]");
}

# ---------------------------------------------------------------- (b) the project's rules on the run
my $state = do { require JSON::PP; JSON::PP->new->decode(slurp("$RUN/gitlab/gitlab.json") // '{}') };
my ($P) = sort { $a->{id} <=> $b->{id} } values %{ $state->{projects} // {} };
ok($P, 'the GitLab emulator state has the model project') or done();
my %label = map { my $i = $_; ($i->{iid} => { map { $_ => 1 } @{ $i->{labels} // [] } }) } @{ $P->{issues} };
my @tasks   = grep { $label{ $_->{iid} }{'type::task'} } @{ $P->{issues} };
my @stories = grep { $label{ $_->{iid} }{'type::story'} } @{ $P->{issues} };
my %HOLIDAY = map { $_ => 1 } qw(2026-10-12 2026-11-11 2026-11-26 2026-12-25 2027-01-01 2027-01-18 2027-02-15 2027-05-31 2027-06-18 2027-07-05
    2027-09-06 2027-10-11 2027-11-11 2027-11-25 2027-12-24 2027-12-31 2028-01-17 2028-02-21);
sub day { my $t = shift // return undef; $t =~ /^(\d{4})-(\d\d)-(\d\d)/ ? timegm(0, 0, 12, $3, $2 - 1, $1) : undef }
sub ymd { my @t = gmtime shift; sprintf '%04d-%02d-%02d', $t[5] + 1900, $t[4] + 1, $t[3] }
sub working_days { my ($a, $b) = @_; my $n = 0;                     # working days from a to b, counting both ends
    for (my $d = $a; $d <= $b; $d += 86400) { my $w = (gmtime $d)[6]; $n++ if $w != 0 && $w != 6 && !$HOLIDAY{ ymd($d) } } $n }
sub sprint_of { my $m = shift // return undef; ($m->{title} // '') =~ /^Sprint (\d+)$/ ? $1 : undef }

ok(@tasks >= 40 && @stories >= 20, 'the run has stories and tasks (' . scalar(@stories) . ' stories, ' . scalar(@tasks) . ' tasks)');
my @big = map { "#$_->{iid} " . ($_->{time_stats}{time_estimate} / 28800) } grep { ($_->{time_stats}{time_estimate} // 0) > 5 * 28800 } @tasks;
ok(!@big, 'every task is at most 5 points (one point = one ideal person-day)', "@big");
my @slow;
for my $t (grep { $_->{state} eq 'closed' } @tasks) {
    my ($start) = map { $_->{created_at} } grep { $_->{system} && $_->{body} =~ /added ~"workflow::in-progress"/ } @{ $t->{notes} // [] };
    $start //= $t->{created_at};
    my $wd = working_days(day($start), day($t->{closed_at}));
    push @slow, "#$t->{iid} $wd days" if $wd > 5;
}
ok(!@slow, 'every task closed within 5 working days of being started', "@slow");
my @open_tasks = map { "#$_->{iid}" } grep { $_->{state} ne 'closed' && (sprint_of($_->{milestone}) // 99) < 6 } @tasks;
ok(!@open_tasks, 'no task of sprints 1-5 is left open', "@open_tasks");

my %due = map { (sprint_of($_) // 0) => $_->{due_date} } @{ $P->{milestones} // [] };
my @carry;
for my $s (@stories) {
    my $sp = sprint_of($s->{milestone}) // next;
    next if $sp >= 6 && $s->{state} ne 'closed';                     # the last sprint simulated may end with work in flight
    my $end = day($due{$sp}) // next; $end += 3 * 86400;              # the sprint's last Friday through the weekend
    push @carry, "#$s->{iid} (sprint $sp)" if $s->{state} ne 'closed' || day($s->{closed_at}) > $end;
}
print "# carryovers: " . (@carry ? "@carry" : 'none') . "\n";
ok(@carry <= 6, 'stories fit their sprint: at most 6 carryovers in the project (' . scalar(@carry) . ')', "@carry");

my (%epic, %tome);
for my $s (@stories) {
    my $sp = sprint_of($s->{milestone}) // next;
    for my $l (keys %{ $label{ $s->{iid} } }) {
        if ($l =~ /^epic::(E\d+)/) { my $e = $epic{$1} //= [ $sp, $sp ]; $e->[0] = $sp if $sp < $e->[0]; $e->[1] = $sp if $sp > $e->[1] }
        if ($l =~ /^tome::(T\d+)/) { my $e = $tome{$1} //= [ $sp, $sp ]; $e->[0] = $sp if $sp < $e->[0]; $e->[1] = $sp if $sp > $e->[1] }
    }
}
my @long_e = map { "$_ spans " . ($epic{$_}[1] - $epic{$_}[0] + 1) } grep { $epic{$_}[1] - $epic{$_}[0] + 1 > 13 } sort keys %epic;
my @long_t = map { "$_ spans " . ($tome{$_}[1] - $tome{$_}[0] + 1) } grep { $tome{$_}[1] - $tome{$_}[0] + 1 > 26 } sort keys %tome;
ok(%epic && !@long_e, 'every epic spans at most 13 sprints (a semester) (' . scalar(keys %epic) . ' epics)', "@long_e");
ok(%tome && !@long_t, 'every tome spans at most 26 sprints (a year) (' . scalar(keys %tome) . ' tomes)', "@long_t");

my $bare = (glob("$RUN/gitlab/repos/*/*.git"))[0];
my $codeowners = $bare ? `git --git-dir="$bare" show develop:CODEOWNERS 2>/dev/null` : '';
my %owner = map { $_ => 1 } $codeowners =~ /@([A-Za-z][\w.-]*)/g;
ok(scalar(%owner), 'CODEOWNERS on develop names its owners (' . join(', ', sort keys %owner) . ')');
my @merged = grep { $_->{merged_at} } @{ $P->{mrs} };
my ($first_pl) = sort map { $_->{created_at} // () } @{ $P->{pipelines} // [] };   # before the first pipeline there was no .gitlab-ci.yml to run
my (@red, @selfish, @pre);
for my $m (@merged) {
    my $st = ($m->{head_pipeline} // $m->{pipeline} // {})->{status} // 'none';
    if ($st eq 'none' && (!$first_pl || $m->{merged_at} lt $first_pl)) { push @pre, "!$m->{iid}" }
    elsif ($st ne 'success') { push @red, "!$m->{iid} ($st)" }
    my @by = grep { $_ ne $m->{author}{username} && $owner{$_} } map { $_->{user}{username} } @{ $m->{approved_by} // [] };
    push @selfish, "!$m->{iid}" unless @by;
}
ok(@merged >= 20, 'the run merged merge requests (' . scalar(@merged) . ')');
print "# merged before the first pipeline existed: @pre\n" if @pre;
ok(!@red, 'every merged MR had a green pipeline (once the project had one)', "@red");
ok(!@selfish, 'every merged MR was approved by a code owner other than its author', "@selfish");

my @tags = $bare ? grep { /^baseline-/ } split /\n/, `git --git-dir="$bare" tag -l 2>/dev/null` : ();
ok(scalar(@tags) >= 1, 'sprint 6 tags an interim baseline (' . join(', ', @tags) . ')');
for my $tag (@tags) {
    my $msg = `git --git-dir="$bare" tag -l --format="%(contents)" "$tag"`;
    my ($want) = $msg =~ /sha256=([0-9a-f]{64})/;
    my $tree = `git --git-dir="$bare" ls-tree -r "$tag" -- docs`;
    my @have = map { Digest::SHA::sha256_hex($_) } $tree, do { (my $c = $tree) =~ s/\n\z//; $c };
    ok($want && grep({ $_ eq $want } @have), "$tag rebuilds: the docs/ tree hashes to the sha256 in its tag message", 'tag message: ' . ($msg =~ s/\n/ /gr), 'docs/ tree: ' . $have[0]);
}

{
    require Scrum;
    my $s = Scrum::load("$RUN/journal/scrum.txt", today => '2026-12-31');
    my %gl; $gl{ sprint_of($_->{milestone}) // 0 } += ($_->{time_stats}{time_estimate} // 0) / 28800 for @tasks;
    my @diff;
    for my $sp (1 .. 6) {
        my $j = Scrum::sprint_summary($s, $sp)->{totals}{committed} // 0;
        push @diff, "sprint $sp: journal $j, GitLab " . ($gl{$sp} // 0) if abs($j - ($gl{$sp} // 0)) > 1e-6;
    }
    ok(!@diff, 'the journal commits, sprint by sprint, the points of the GitLab tasks in that sprint\'s milestone', @diff);
}

done();
