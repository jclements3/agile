#!/usr/bin/perl
# perl tests/primer-runs.t -- runs the primer before the team is told to follow it: every runnable code block
# (```sh run ... / ```vim run ...) of every chapter of docs/src/primer, in reading order, in the sandbox the block
# names, and checks its exit status and the expect= regex. A failure is reported as FILE:LINE.
#
#   perl tests/primer-runs.t                      every chapter
#   PRIMER_RUNS=git-from-zero perl tests/primer-runs.t     one chapter (its slug; a comma list for several)
#   PRIMER_RUNS=self-test     only the runner's own self-test
#   PRIMER_RUNS_SRC=DIR       another source directory (the self-test uses it)
#   PRIMER_RUNS_CACHE=DIR     where the tidewater sandbox is cached (default: <tmpdir>/primer-runs-cache)
#   PRIMER_RUNS_TIMEOUT=SECS  the per-block default (60; a block can set timeout=N)
#   PRIMER_RUNS_VERBOSE=1     print every block's output
#
# Sandboxes, fresh for each chapter (a chapter is one session: its blocks share the sandbox in order):
#   scratch      an empty directory                       kit          the kit itself, read-only (git status must not change)
#   practice-N   perl agile.pl practice N --dir ...       tidewater[-N]  a copy of perl sim/tidewater-sim.pl --sprints N (6)
# Every block runs with KIT=<the kit>, HOME=<a private home with a git identity>, cwd = the sandbox. A block with
# cwd=PATH (sticky, like sandbox=) runs in that folder instead: ~/practice is under the private home, a relative path
# is under the sandbox. A sandbox whose
# prerequisite is missing (sh, vim, sim/tidewater-sim.pl) skips its blocks with the reason.
use strict;
use warnings;
use FindBin;
use Cwd qw(abs_path);
use File::Temp qw(tempdir);
use File::Path qw(make_path remove_tree);
use File::Spec;

my $ROOT = abs_path("$FindBin::Bin/..");
require "$ROOT/sim/primer.pl";

my ($n, $bad) = (0, 0);
sub ok_ { my ($ok, $name, @diag) = @_; $n++; print(($ok ? 'ok' : 'not ok') . " $n - $name\n"); print map { "#   $_\n" } @diag unless $ok; $bad++ unless $ok; $ok }
sub skip_ { my ($name, $why) = @_; $n++; print "ok $n - $name # skip $why\n" }
sub which { my $p = shift; for (split /:/, $ENV{PATH} // '') { return "$_/$p" if -x "$_/$p" || -x "$_/$p.exe" } undef }
sub spew { my ($p, $t) = @_; open my $fh, '>:raw', $p or die "$p: $!\n"; print $fh $t; close $fh }

# run one command with a timeout, in its own process group so a timeout kills everything it started
sub run_cmd {
    my ($dir, $env, $timeout, @cmd) = @_;
    my $pid = open(my $out, '-|');
    die "cannot fork: $!\n" unless defined $pid;
    if (!$pid) {
        setpgrp(0, 0);
        open STDERR, '>&', \*STDOUT;
        open STDIN, '<', File::Spec->devnull;
        chdir $dir or die "cannot cd to $dir: $!\n";
        $ENV{$_} = $env->{$_} for keys %$env;
        exec @cmd or die "cannot run $cmd[0]: $!\n";
    }
    my ($text, $timed_out) = ('', 0);
    eval {
        local $SIG{ALRM} = sub { die "timeout\n" };
        alarm $timeout;
        local $/; $text = <$out> // '';
        alarm 0;
    };
    if ($@ eq "timeout\n") { $timed_out = 1; kill 'TERM', -$pid; sleep 1; kill 'KILL', -$pid }
    close $out;
    my $rc = $timed_out ? -1 : $? >> 8;
    return ($rc, $text, $timed_out);
}

my $TMP = tempdir('primer-runs-XXXXXX', TMPDIR => 1, CLEANUP => 1);
my $HOME = "$TMP/home";
make_path($HOME);
spew("$HOME/.gitconfig", "[user]\n\tname = Primer Reader\n\temail = reader\@example.invalid\n[init]\n\tdefaultBranch = main\n[core]\n\tautocrlf = false\n[commit]\n\tgpgsign = false\n");
my %ENVV = (KIT => $ROOT, HOME => $HOME, GIT_CONFIG_NOSYSTEM => 1, TZ => 'UTC', LC_ALL => 'C', PAGER => 'cat', GIT_PAGER => 'cat', EDITOR => 'true', GIT_EDITOR => 'true');
my $SH = which('sh');
my $VIM = which('vim');
my $DEFAULT_T = $ENV{PRIMER_RUNS_TIMEOUT} || 60;

# the sandbox for one chapter: (dir) or (undef, why-skipped)
my %built;
sub sandbox {
    my ($name, $chapter) = @_;
    if ($name eq 'kit') { return ($ROOT) }
    my $d = "$TMP/sb/$chapter/$name";
    return ($built{$d}) if $built{$d};
    make_path($d);
    if ($name eq 'scratch') { return ($built{$d} = $d) }
    if ($name =~ /^practice-(\d+)$/) {
        my ($rc, $out) = run_cmd($ROOT, \%ENVV, 600, $^X, "$ROOT/agile.pl", 'practice', $1, '--dir', $d);
        return (undef, "agile.pl practice $1 failed: " . (split /\n/, $out)[-1]) if $rc;
        my ($lesson) = grep { -d } glob("$d/lesson$1"), glob("$d/*");
        return ($built{$d} = $lesson // $d);
    }
    if ($name =~ /^tidewater(?:-(\d+))?$/) {
        my $sprints = $1 // 6;
        return (undef, 'sim/tidewater-sim.pl is not in this checkout yet') unless -f "$ROOT/sim/tidewater-sim.pl";
        my $cache = ($ENV{PRIMER_RUNS_CACHE} || File::Spec->tmpdir . '/primer-runs-cache') . "/tidewater-$sprints";
        my $stamp = (stat "$ROOT/sim/tidewater-sim.pl")[9];
        if (!-f "$cache/.built" || (do { open my $fh, '<', "$cache/.built"; my $s = <$fh> // ''; chomp $s; $s } ne $stamp)) {
            remove_tree($cache); make_path($cache);
            my ($rc, $out) = run_cmd($ROOT, \%ENVV, 3600, $^X, "$ROOT/sim/tidewater-sim.pl", '--sprints', $sprints, '--dir', "$cache/data/tidewater", '--force', '--quiet');
            return (undef, "sim/tidewater-sim.pl --sprints $sprints failed: " . (split /\n/, $out)[-1]) if $rc;
            spew("$cache/.built", "$stamp\n");
        }
        my ($rc, $out) = run_cmd($ROOT, \%ENVV, 600, 'cp', '-a', "$cache/data/tidewater", $d);
        return (undef, "cannot copy the cached tidewater sandbox: $out") if $rc;
        return ($built{$d} = "$d/tidewater");
    }
    return (undef, "unknown sandbox $name");
}

sub git_status { my ($rc, $o) = run_cmd($ROOT, \%ENVV, 120, 'git', 'status', '--porcelain'); $o }

# run the blocks of one book; returns the number of blocks run
sub run_book {
    my ($src, $only, $label) = @_;
    @main::ERR = ();
    my $doc = main::load_book(src => $src, root => $ROOT, draft => 1);
    my $badf = main::error_files(@main::ERR);   # a half-written chapter fails on its own; the chapters that parse still run
    for my $f (sort keys %$badf) { ok_(0, "$f: the chapter source loads", grep { index($_, "$f:") == 0 } @main::ERR) }
    ok_(0, "$label: the primer source loads", grep { !/^.+?\.txt(?::\d+)?:/ } @main::ERR) if grep { !/^.+?\.txt(?::\d+)?:/ } @main::ERR;
    my @runs = main::runs($doc, $badf);
    if ($only) { my %w = map { $_ => 1 } split /,/, $only; @runs = grep { $w{ $_->{chapter} } } @runs }
    if (!@runs) { skip_("$label: runnable blocks", $only ? "no runnable blocks in $only" : 'the primer has no runnable blocks yet'); return 0 }
    my $kit_before = git_status();
    my (%skip, $ran);
    for my $r (@runs) {
        my $name = "$r->{file}:$r->{line} ($r->{chapter} block $r->{block}, $r->{lang}, $r->{sandbox})";
        my $key = "$r->{chapter}\0$r->{sandbox}";
        if ($r->{lang} eq 'sh' && !$SH) { skip_($name, 'no sh on PATH'); next }
        if ($r->{lang} eq 'vim' && !$VIM) { skip_($name, 'no vim on PATH'); next }
        my ($dir, $why) = $skip{$key} ? (undef, $skip{$key}) : sandbox($r->{sandbox}, $r->{chapter});
        if (!$dir) { $skip{$key} = $why; skip_($name, $why); next }
        my $here = $dir;
        if (defined $r->{cwd}) {          # cwd=: where in the sandbox the block runs (~ = the private home)
            ($here = $r->{cwd}) =~ s{^~(?=/|\z)}{$ENVV{HOME}};
            $here = "$dir/$here" unless $here =~ m{^/};
            if (!-d $here) { ok_(0, $name, "$r->{file}:$r->{line}: cwd=$r->{cwd}: no such folder (an earlier block makes it)"); next }
        }
        my $script = "$TMP/block-$r->{chapter}-$r->{block}." . $r->{lang};
        my @cmd;
        if ($r->{lang} eq 'sh') { spew($script, "$r->{text}\n"); @cmd = ($SH, '-e', $script) }
        else {
            spew($script, "$r->{text}\nqa!\n");
            @cmd = ($SH // 'sh', '-c', qq{"\$0" -Es -N -u NONE -i NONE --cmd "set rtp^=\$KIT/vim" --cmd "filetype plugin on" --cmd "syntax off" < "\$1"}, $VIM, $script);
        }
        my ($rc, $out, $to) = run_cmd($here, \%ENVV, $r->{timeout} || $DEFAULT_T, @cmd);
        $ran++;
        print map { "#   | $_\n" } split /\n/, $out if $ENV{PRIMER_RUNS_VERBOSE};
        my @why;
        push @why, 'timed out after ' . ($r->{timeout} || $DEFAULT_T) . 's' if $to;
        push @why, "exit $rc, wanted $r->{exit}" if !$to && $rc != $r->{exit};
        push @why, "output does not match /$r->{expect}/" if defined $r->{expect} && $out !~ /$r->{expect}/;
        my @tail = (split /\n/, $out)[-12 .. -1];
        ok_(!@why, $name, @why ? ("$r->{file}:$r->{line}: " . join('; ', @why), map { "| $_" } grep { defined } @tail) : ());
    }
    if (grep { $_->{sandbox} eq 'kit' } @runs) {
        my $after = git_status();
        ok_($after eq $kit_before, "$label: the kit sandbox is read-only (git status unchanged)", "before:\n$kit_before", "after:\n$after");
    }
    return $ran // 0;
}

# ---- self-test: a small book with blocks that pass, one that must fail, a vim block, and sandbox carry-over
if ((!$ENV{PRIMER_RUNS} || $ENV{PRIMER_RUNS} eq 'self-test') && !$ENV{PRIMER_RUNS_SRC}) {
    my $src = "$TMP/selftest";
    make_path($src);
    spew("$src/01-part-a.txt", "= Part III: Weeks\n");
    spew("$src/02-c.txt", <<'EOF');
== Self test {#self}

```sh run sandbox=scratch expect=^hello
mkdir notes && echo hello > notes/a.txt && cat notes/a.txt
```

The next block runs in the same scratch sandbox, in the folder named by cwd=:

```sh run cwd=notes expect=a\.txt
ls
test -n "$KIT" && test -f "$KIT/sim/primer.pl"
git init -q . && git add -A && git commit -q -m first && git log --format=%an
```

```sh run sandbox=kit expect=sim/primer\.pl
ls sim/primer.pl
```

```sh run sandbox=scratch exit=3
sh -c 'exit 3'
```

```vim run sandbox=scratch
edit notes/a.txt
call setline(1, 'changed')
write
```

```sh run expect=^changed
cat notes/a.txt
```
EOF
    @main::ERR = ();
    my $doc = main::load_book(src => $src, root => $ROOT, draft => 1);
    my @r = main::runs($doc);
    ok_(join(' ', map { "$_->{block}:$_->{lang}:$_->{sandbox}:$_->{exit}" } @r) eq '1:sh:scratch:0 2:sh:scratch:0 3:sh:kit:0 4:sh:scratch:3 5:vim:scratch:0 6:sh:scratch:0',
        'self-test: blocks, languages, sandbox carry-over, exit codes', join(' ', map { "$_->{block}:$_->{lang}:$_->{sandbox}:$_->{exit}" } @r));
    my $ran = run_book($src, undef, 'self-test');
    ok_($ran == ($VIM ? 6 : 5) || !$SH, 'self-test: every block ran');

    # a failing block is reported with its file and line
    spew("$src/02-c.txt", "== Self test {#self}\n\n```sh run expect=nope\necho yes\n```\n\n```sh run timeout=1\nsleep 30\n```\n");
    my ($rc, $out) = run_cmd($ROOT, { %ENVV, PRIMER_RUNS => "", PRIMER_RUNS_SRC => $src }, 300, $^X, "$ROOT/tests/primer-runs.t");
    ok_($rc == 1 && $out =~ m{^not ok 1 - \S*02-c\.txt:3 \(self block 1, sh, scratch\)$}m && $out =~ m{#   \S*02-c\.txt:3: output does not match /nope/} && $out =~ m{#   \S*02-c\.txt:7: timed out after 1s}, 'self-test: a failing block and a timeout are reported as FILE:LINE', split /\n/, $out);

    # a half-written chapter fails on its own; the chapters that parse still run
    spew("$src/02-c.txt", "== Good {#good}\n\n```sh run expect=^fine\necho fine\n```\n");
    spew("$src/03-d.txt", "== Half written {#half}\n\n::: note\nnever closed\n");
    ($rc, $out) = run_cmd($ROOT, { %ENVV, PRIMER_RUNS => "", PRIMER_RUNS_SRC => $src }, 300, $^X, "$ROOT/tests/primer-runs.t");
    ok_($rc == 1 && $out =~ m{^not ok \d+ - \S*03-d\.txt: the chapter source loads$}m && $out =~ m{^ok \d+ - \S*02-c\.txt:3 \(good block 1, sh, scratch\)$}m,
        'self-test: a broken chapter is reported per file and the others still run', split /\n/, $out);
}

# ---- the real primer
if (($ENV{PRIMER_RUNS} // '') ne 'self-test') {
my $src = $ENV{PRIMER_RUNS_SRC} || "$ROOT/docs/src/primer";
run_book($src, $ENV{PRIMER_RUNS}, $ENV{PRIMER_RUNS_SRC} ? 'source' : 'docs/src/primer');
}

print "1..$n\n";
print $bad ? "# $bad of $n FAILED\n" : "# all $n passed\n";
exit($bad ? 1 : 0);
