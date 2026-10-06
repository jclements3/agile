#!/usr/bin/perl
# ci/job.pl -- every job of the model pipeline, in core Perl, so .gitlab-ci.yml only ever says `perl ci/job.pl NAME`.
#
# Why a script and not shell lines in the YAML: GitLab Runner's Windows shell executor runs PowerShell, where $KIT is
# $env:KIT and `$(find ...)`, `[ -f ... ]`, `| xargs`, `&&` and quoting all differ from sh. One Perl script behaves the
# same under PowerShell, cmd, Git Bash, a Linux runner, the Docker image and `gitlab.pl ci` on a laptop. The YAML keeps
# what GitLab needs to know (when a job runs, what it keeps, which reports it attaches); this file keeps what it does.
#
#   perl ci/job.pl grammar | lint | outline | todo | secrets | trace | vcrm | docs | delta | drop-package | intake | baseline
#                  | publish-package | publish-release | pages | status | sil-regression | hil-test
#
# Every job needs the CI/CD variable KIT (the agile kit's checkout on the runner) and writes its log and report files
# in the project directory: NAME.txt (the checker's own output), NAME.xml (JUnit), NAME-cq.json (Code Quality),
# NAME.metrics (metrics), via $KIT/tools/gitlab/ci-reports.pl. Exit status: 0 pass, 1 the check failed, 2 the job
# cannot run (KIT missing, bad usage).
#
# Copied into the model repository as ci/job.pl (from tools/gitlab/templates/ci/job.pl). Core Perl only.
package CIJob;                                # a package, so tests can `require` this file and call its functions
use strict;
use warnings;
use File::Find ();
use File::Path qw(make_path);
use File::Copy qw(copy);
use Digest::SHA ();

my %JOBS = map { $_ => 1 } qw(grammar lint outline todo secrets trace vcrm recipe complexity docs delta drop-package intake baseline publish-package
                                publish-release pages status sil-regression hil-test);
our $KIT = $ENV{KIT} // '';
# The toolchain is pinned like the model: .kit-version names the kit release the model was checked with. A runner with a
# different kit fails every job, so a tool upgrade reaches the model only through a reviewed MR that bumps the pin.
sub kit_version { my $v = $ENV{KIT_VERSION}; return $v if defined $v && length $v;
    my $o = `git -C "$KIT" describe --tags --always 2>&1`; $o =~ s/\s+$//; $? ? 'unknown' : $o }
sub main {
    my $job = shift // '';
    if (!$JOBS{$job}) { print STDERR "usage: perl ci/job.pl " . join(' | ', sort keys %JOBS) . "\n"; return 2 }
    if ($KIT eq '') { print STDERR "KIT is not set: add it under Settings > CI/CD > Variables (the kit's path on the runner)\n"; return 2 }
    if (!-f "$KIT/tools/sysml/model.pl") { print STDERR "KIT=$KIT does not hold the agile kit (no tools/sysml/model.pl)\n"; return 2 }
    $| = 1;
    if (open my $pin, '<', '.kit-version') {
        my $want = <$pin> // ''; close $pin;
        $want =~ s/^\s+|\s+$//g;
        my $have = kit_version();
        if (length $want && $want ne $have) {
            print STDERR "the kit on this runner is $have, but .kit-version pins $want:\n"
                       . "  bump .kit-version in a merge request (toolchain changes are reviewed like model changes), or put the runner back on $want\n";
            return 2;
        }
    }
    our %run;
    $run{$job}->() ? 1 : 0;
}

# ---------------------------------------------------------------- helpers
sub slurp { my $f = shift; open my $fh, '<:raw', $f or return undef; local $/; my $t = <$fh>; close $fh; $t // '' }
sub spew { my ($f, $t) = @_; open my $fh, '>:raw', $f or die "cannot write $f: $!\n"; print $fh $t; close $fh }
our $QUIET = 0;                               # local $QUIET = 1: run() writes the log file only, not the job log
sub run {                                     # run(LOGFILE|undef, cmd...) -> exit code; output (stdout+stderr) to the log and the job log
    my ($log, @cmd) = @_;
    print '$ ', join(' ', map { /\s/ ? "\"$_\"" : $_ } @cmd), "\n" unless $QUIET;
    return system(@cmd) >> 8 unless defined $log;
    open my $save_out, '>&', \*STDOUT or die "cannot save STDOUT: $!\n";
    open my $save_err, '>&', \*STDERR or die "cannot save STDERR: $!\n";
    open STDOUT, '>', $log or die "cannot write $log: $!\n";
    open STDERR, '>&', \*STDOUT or die "cannot redirect STDERR: $!\n";
    my $rc = system(@cmd);
    open STDOUT, '>&', $save_out or die "cannot restore STDOUT: $!\n";
    open STDERR, '>&', $save_err or die "cannot restore STDERR: $!\n";
    print slurp($log) // '' unless $QUIET;
    $rc == -1 ? 127 : $rc >> 8;
}
sub out {                                     # out(cmd...) -> its standard output (a temp file, not a pipe: list-form pipes are not portable)
    my @cmd = @_;
    require File::Temp;
    my ($fh, $tmp) = File::Temp::tempfile('ci-job-XXXXXX', TMPDIR => 1, UNLINK => 1);
    close $fh;
    open my $save, '>&', \*STDOUT or die "cannot save STDOUT: $!\n";
    open STDOUT, '>', $tmp or die "cannot write $tmp: $!\n";
    system(@cmd);
    open STDOUT, '>&', $save or die "cannot restore STDOUT: $!\n";
    my $t = slurp($tmp) // '';
    unlink $tmp;
    $t;
}
sub perl_tool { my ($log, $tool, @args) = @_; run($log, $^X, "$KIT/$tool", @args) }
sub reports { my ($mode, @args) = @_; perl_tool(undef, 'tools/gitlab/ci-reports.pl', $mode, @args) }
sub sysml_files { my @f; File::Find::find({ no_chdir => 1, wanted => sub { push @f, $File::Find::name if /\.sysml$/ && -f } }, 'model') if -d 'model'; sort @f }
sub vkey { my $v = shift; join '.', map { /^\d+$/ ? sprintf('%06d', $_) : $_ } split /[.\-]/, $v }
sub imports {                                 # the imported prime drops, oldest first (imports/v1.0, imports/v1.1, ... in version order)
    opendir my $dh, 'imports' or return ();
    my @d = grep { !/^\./ && -d "imports/$_" } readdir $dh;
    closedir $dh;
    map { "imports/$_" } sort { vkey($a) cmp vkey($b) } @d;
}
sub ls { my $d = shift; opendir(my $dh, $d) or return (); my @e = sort grep { !/^\./ } readdir $dh; closedir $dh; @e }
sub docs_hash { Digest::SHA::sha256_hex(out('git', 'ls-tree', '-r', $_[0] // 'HEAD', '--', 'docs')) }   # the same text GitFlow hashes
sub sha256_file { my $f = shift; my $d = Digest::SHA->new(256); open my $fh, '<:raw', $f or return ''; $d->addfile($fh); close $fh; $d->hexdigest }
sub last_line { my $t = shift // ''; my @l = grep { /\S/ } split /\n/, $t; $l[-1] // '' }

# ---------------------------------------------------------------- the jobs
our %run;
$run{grammar} = sub {                         # every .sysml file against the SysML v2 grammar; one JUnit case per file
    my @f = sysml_files();
    if (!@f) { spew('grammar.txt', "no .sysml files under model/\n"); print "no .sysml files under model/ yet\n"; return 0 }
    my $rc = perl_tool('grammar.txt', 'tools/sysml/sysml.pl', 'check', @f);
    reports('grammar', '--junit', 'grammar.xml', '--codequality', 'grammar-cq.json', 'grammar.txt', @f);
    $rc;
};
$run{lint} = sub {                            # structure: the gate is 0 errors and 0 warnings
    perl_tool('lint.txt', 'tools/sysml/model.pl', 'lint');
    reports('lint', '--junit', 'lint.xml', '--codequality', 'lint-cq.json', '--metrics', 'lint.metrics', 'lint.txt');
    my $l = last_line(slurp('lint.txt'));
    return 0 if $l =~ / errors=0 warnings=0$/;
    print "lint is not 0/0 ($l)\n";
    1;
};
sub outline_junit_inherited {                 # findings the allowance already covers: skipped tests, not failures (a green MR shows no red)
    my $x = slurp('outline.xml') // return;
    my $n = $x =~ s{<failure message="([^"]*)"[^>]*>.*?</failure>}{<skipped message="inherited, within .ci/outline-max: $1"/>}gs;
    return unless $n;
    $x =~ s{(<testsuites?\b[^>]*?) failures="(\d+)"}{my ($h, $f) = ($1, $2); "$h failures=\"0\" skipped=\"$f\""}ge;
    spew('outline.xml', $x);
}
$run{outline} = sub {                         # the 2..9 rule and level tags, as a ratchet against .ci/outline-max
    perl_tool('outline.txt', 'tools/sysml/model.pl', 'check');
    reports('outline', '--junit', 'outline.xml', '--codequality', 'outline-cq.json', '--metrics', 'outline.metrics', 'outline.txt');
    my $t = slurp('outline.txt');
    my ($v) = $t =~ /^violations\s+(\d+)/m;
    my ($m) = $t =~ /^\@L tag mismatches\s+(\d+)/m;
    my $n = ($v // 0) + ($m // 0);
    my $max = slurp('.ci/outline-max');
    $max = defined $max && $max =~ /(\d+)/ ? $1 : 0;
    print "outline violations: $n (allowed: $max)\n";
    # vendor/prime holds the prime's structure as delivered, and a drop branch merges it: measured, not ratcheted (the
    # drop's merge request records the new count in .ci/outline-max; Discrepancy Reports ask the prime to fix the rest)
    if (($ENV{CI_COMMIT_BRANCH} // '') =~ m{^(?:vendor/prime$|feature/drop-)} || ($ENV{CI_MERGE_REQUEST_SOURCE_BRANCH_NAME} // '') =~ m{^feature/drop-}) {   # the MR and the branch's own pushes
        outline_junit_inherited();
        print "a prime drop: reported, not ratcheted\n";
        return 0;
    }
    if (($ENV{CI_MERGE_REQUEST_SOURCE_BRANCH_NAME} // '') =~ m{^release/} || ($ENV{CI_COMMIT_BRANCH} // '') =~ m{^release/}) {   # as complexity: develop already checked it
        outline_junit_inherited();
        print "a release: its changes were checked on develop; reported only\n";
        return 0;
    }
    if ($n > $max) { print "this change adds outline violations ($n > $max): fix them, do not raise .ci/outline-max\n"; return 1 }
    print "fewer violations than allowed: lower .ci/outline-max to $n in this MR\n" if $n < $max;
    outline_junit_inherited();
    0;
};
$run{todo} = sub {                            # the port burn-down: every // TODO line the converter left; never fails
    my @hits;
    for my $f (sysml_files()) { my $n = 0; for my $l (split /\n/, slurp($f)) { $n++; push @hits, "$f:$n:$l" if index($l, '// TODO') >= 0 } }
    spew('todo.txt', join('', map { "$_\n" } @hits));
    print "TODO lines remaining: " . scalar(@hits) . "\n";
    reports('todo', '--codequality', 'todo-cq.json', '--metrics', 'todo.metrics', -d 'model' ? 'model' : 'todo.txt');
    0;
};
$run{secrets} = sub {                         # tokens, cloud keys and private keys must never reach the repository
    my @pat = (qr/glpat-[0-9A-Za-z_\-]{20}/, qr/AKIA[0-9A-Z]{16}/, qr/-----BEGIN [A-Z ]*PRIVATE KEY-----/);
    my @bad;
    for my $f (grep { length } split /\n/, out('git', 'ls-files')) {
        next if $f eq '.gitlab-ci.yml' || $f eq 'ci/job.pl';
        my $t = slurp($f) // next;
        next if $t =~ /\x00/;                 # binary
        my $n = 0;
        for my $l (split /\n/, $t) { $n++; for my $p (@pat) { push @bad, "$f:$n: matches $p" if $l =~ $p } }
    }
    if (@bad) { print "$_\n" for @bad; print "possible secret committed: remove it, rotate it, then rewrite the branch before it merges\n"; return 1 }
    print "no secrets found in " . scalar(grep { length } split /\n/, out('git', 'ls-files')) . " tracked files\n";
    0;
};
sub is_doors {                                # a file reqif2sysml wrote from the DOORS export (whatever folder the layout puts it in)
    my $f = shift; open my $fh, '<', $f or return 0; my $l = <$fh> // ''; close $fh; $l =~ m{^// generated by reqif2sysml\.pl} ? 1 : 0 }
sub model_side {                              # the model without the DOORS export's own conversion (by its header): what trace
    my ($root) = @_;                          # compares DOORS against -- comparing DOORS with its own copy would always agree
    require File::Temp;
    my $d = File::Temp::tempdir('ci-model-XXXXXX', TMPDIR => 1, CLEANUP => 1);
    File::Find::find({ no_chdir => 1, wanted => sub {
        return unless -f && /\.sysml$/;
        (my $r = $File::Find::name) =~ s{^\Q$root\E/?}{};
        return if is_doors($File::Find::name);
        (my $dir = "$d/$r") =~ s{/[^/]+$}{};
        make_path($dir); copy($File::Find::name, "$d/$r");
    } }, $root) if -d $root;
    $d;
}
sub trace_counts {                            # (report text) -> { orphans, unverified, drift, linked, ids => { kind => {id=>1} } }
    my $t = shift // q{};
    my %c = (orphans => 0, unverified => 0, drift => 0, linked => 0);
    $c{orphans} = $1 if $t =~ /^F orphan requirements[^\n]*?(\d+)\s*$/m;
    $c{unverified} = $1 if $t =~ /^G unverified requirements[^\n]*?(\d+)\s*$/m;
    $c{drift} = $1 if $t =~ /^text differs from DOORS\s+(\d+)\s*$/m;
    ($c{linked}, $c{total}) = ($1, $2) if $t =~ /^C requirements linked[^\n]*?(\d+) of (\d+)\s*$/m;
    for my $k (qw(orphans unverified drift)) { my ($l) = $t =~ /^$k: ([^\n]*)$/m; $c{ids}{$k} = { map { $_ => 1 } grep { !/^(?:none|-)$/ } split q{ }, $l // q{} } }
    \%c;
}
sub trace_junit_inherited {                   # gaps this change did not add: skipped tests, not failures; $new = { orphans => [ids], ... } stays failed
    my ($why, $new) = @_;
    my $x = slurp('trace.xml') // return;
    my %keep; for my $k (keys %{ $new // {} }) { $keep{"trace $k"}{$_} = 1 for @{ $new->{$k} } }
    my %left;
    $x =~ s{(<testcase classname="([^"]*)" name="([^"]*)"[^>]*>\s*)<failure message="([^"]*)"[^>]*>.*?</failure>}{
        my ($head, $suite, $id, $msg) = ($1, $2, $3, $4);
        if ($keep{$suite}{$id}) { $left{$suite}++; $& } else { "$head<skipped message=\"$why: $msg\"/>" } }gse;
    $x =~ s{(<testsuite name="([^"]*)" tests="\d+") failures="(\d+)"}{my $f = $left{$2} // 0; "$1 failures=\"$f\" skipped=\"" . ($3 - $f) . "\""}ge;
    my $all = 0; $all += $_ for values %left;
    $x =~ s{(<testsuites name="[^"]*" tests="\d+") failures="\d+"}{$1 failures="$all"};
    spew('trace.xml', $x);
}
$run{trace} = sub {                           # DOORS against the model, from the newest imported drop; a RATCHET on merge requests
    my ($d) = reverse imports();
    my ($reqif) = $d ? grep { -f } map { "$d/$_" } grep { /\.reqifz?$/i } ls($d) : ();
    if (!$reqif) { spew('trace.txt', "no prime drop imported yet\n"); print "no prime drop imported yet\n"; return 0 }
    perl_tool('trace.txt', 'bin/reqif2sysml.pl', '--report', '--model', model_side('model'), $reqif);
    reports('trace', '--junit', 'trace.xml', '--metrics', 'trace.metrics', 'trace.txt');
    my $now = trace_counts(slurp('trace.txt'));
    printf "trace gaps: %d orphan(s), %d unverified, %d drifted\n", @$now{qw(orphans unverified drift)};
    if (($ENV{TRACE_MODE} // '') eq 'report') { trace_junit_inherited('reported, not gated (TRACE_MODE=report)'); print "TRACE_MODE=report: gaps are reported, never fatal\n"; return 0 }
    if (($ENV{CI_PIPELINE_SOURCE} // '') ne 'merge_request_event') { trace_junit_inherited('reported, not gated (not a merge request)'); print "not a merge request: reported only\n"; return 0 }
    # the ratchet: the same DOORS export against the model as it was where this branch left the target branch
    my $base = $ENV{CI_MERGE_REQUEST_DIFF_BASE_SHA} // '';
    $base = (out('git', 'merge-base', 'HEAD', "origin/$ENV{CI_MERGE_REQUEST_TARGET_BRANCH_NAME}") =~ /([0-9a-f]{40})/)[0] // '' if $base eq '' && $ENV{CI_MERGE_REQUEST_TARGET_BRANCH_NAME};
    if ($base eq '') { trace_junit_inherited('reported, not gated (no merge base)'); print "no merge base known: reported only\n"; return 0 }
    require File::Temp;
    my $wt = File::Temp::tempdir('ci-trace-XXXXXX', TMPDIR => 1, CLEANUP => 1);
    rmdir $wt;
    run(undef, 'git', 'worktree', 'add', '-q', '--detach', $wt, $base) and do { trace_junit_inherited('reported, not gated'); print "cannot check out the merge base: reported only\n"; return 0 };
    my $was = -d "$wt/model" ? do { local $QUIET = 1; perl_tool(q{trace-base.txt}, 'bin/reqif2sysml.pl', '--report', '--model', model_side("$wt/model"), $reqif) } : -1;
    run(undef, 'git', 'worktree', 'remove', '--force', $wt);
    my $old = $was == -1 ? undef : trace_counts(slurp(q{trace-base.txt}));
    # the target branch's numbers in one labelled line (its full report is the artifact trace-base.txt, not this log)
    print !$old ? "target branch: no model folder (nothing to compare)\n"
        : !$old->{linked} ? sprintf("target branch: 0 of %d linked (no model yet)\n", $old->{total} // 0)
        : sprintf("target branch: %d of %d linked; %d orphan(s), %d unverified, %d drifted (full report: trace-base.txt)\n", @$old{qw(linked total orphans unverified drift)});
    # like with like: a target branch that has no model side yet (a release MR into main before the first baseline, or a
    # branch older than the first import) has nothing to compare -- every gap would look new. Report only.
    if (!$old || !$old->{linked}) { trace_junit_inherited('reported, not gated (the target branch has no model)'); print "the target branch has no model to compare with: reported only\n"; return 0 }
    # a gap is new only if this requirement did not have it on the target branch (sets of ids, not counts)
    my %new = map { my $k = $_; ($k => [ sort grep { !$old->{ids}{$k}{$_} } keys %{ $now->{ids}{$k} } ]) } qw(orphans unverified drift);
    my @worse = grep { @{ $new{$_} } } qw(orphans unverified drift);
    trace_junit_inherited('inherited from the target branch', \%new);
    if (@worse) { print "this change adds trace gaps: " . join(q{, }, map { "$_ $old->{$_} -> $now->{$_} (new: @{ $new{$_} })" } @worse) . " (see trace.txt)\n"; return 1 }
    print "no new trace gaps (target branch: " . join(', ', map { "$_ $old->{$_}" } qw(orphans unverified drift)) . ")\n" unless $was == -1;
    0;
};
sub csv_rows {                                # a small CSV reader: quoted fields, "" escapes; -> list of hashes keyed by the header
    my $t = slurp(shift) // return ();
    my @rows;
    for my $line (grep { /\S/ } split /\r?\n/, $t) {
        my @f; while ($line =~ /\G(?:"((?:[^"]|"")*)"|([^,]*))(?:,|$)/g) { push @f, defined $1 ? $1 =~ s/""/"/gr : $2; last if pos($line) >= length $line }
        push @rows, \@f;
    }
    my $h = shift @rows or return ();
    map { my $r = $_; +{ map { ($h->[$_] => $r->[$_] // '') } 0 .. $#$h } } @rows;
}
sub vcrm_data {                               # the VCRM: every requirement, its method, its cases (verify), their latest verdicts
    my (%req, %name2id, %cases);
    for my $f (sysml_files()) {
        my $t = slurp($f);
        while ($t =~ /\brequirement\s+(?:def\s+)?(\w+)\s*\{([^{}]*)\}/g) {
            my ($name, $body) = ($1, $2);
            my ($id) = $body =~ /doorsId\s*=\s*"([^"]+)"/ or next;
            $name2id{$name} = $id;
            my ($vm) = $body =~ /verificationMethod\s*=\s*"([^"]+)"/;
            my ($doc) = $body =~ m{doc\s*/\*\s*(.*?)\s*\*/}s;
            my $r = $req{$id} //= { id => $id, method => '', text => '' };
            $r->{in_doors} = 1 if is_doors($f);
            $r->{method} = $vm if $vm && (!$r->{method} || is_doors($f));      # DOORS is authoritative (D-4)
            $r->{text} = $doc if defined $doc && (!$r->{text} || is_doors($f));
        }
    }
    for my $f (sysml_files()) {
        my $t = slurp($f);
        while ($t =~ /\bverification\s+def\s+(\w+)\s*\{/g) {
            my $case = $1;
            my $depth = 1; my $i = pos($t); my $start = $i;
            while ($depth && $i < length $t) { my $c = substr($t, $i++, 1); $depth++ if $c eq '{'; $depth-- if $c eq '}' }
            my $body = substr($t, $start, $i - $start);
            for my $n ($body =~ /\bverify\s+(?:requirement\s+)?(\w+)\s*;/g) { my $id = $name2id{$n} // next; $cases{$id}{$case} = 1 }
        }
    }
    my %res;                                  # (requirement, case) -> the newest row, from every verification/*.csv
    if (opendir my $dh, 'verification') {
        for my $f (sort grep { /\.csv$/ } readdir $dh) {
            for my $r (csv_rows("verification/$f")) {
                next unless $r->{requirement} && $r->{case};
                my $k = "$r->{requirement}\0$r->{case}";
                $res{$k} = { %$r, source => "verification/$f" } if !$res{$k} || ($r->{timestamp} // '') ge ($res{$k}{timestamp} // '');
                $cases{ $r->{requirement} }{ $r->{case} } //= 1 if $req{ $r->{requirement} };
            }
        }
        closedir $dh;
    }
    my @rows;
    my $doors = grep { $_->{in_doors} } values %req;  # with DOORS imported, the VCRM lists DOORS's requirements (the baseline, D-4)
    for my $id (sort grep { !$doors || $req{$_}{in_doors} } keys %req) {
        my @c = sort keys %{ $cases{$id} // {} };
        my @v = map { $res{"$id\0$_"} } @c;
        my $status = !@c ? 'no case'
                   : (grep { $_ && $_->{verdict} eq 'failed' } @v) ? 'failed'
                   : (@v && !grep { !$_ || $_->{verdict} ne 'passed' } @v) ? 'verified' : 'not run';
        push @rows, { %{ $req{$id} }, cases => \@c, results => \@v, status => $status };
    }
    \@rows;
}
sub xmlq { my $t = shift // ''; $t =~ s/&/&amp;/g; $t =~ s/</&lt;/g; $t =~ s/>/&gt;/g; $t =~ s/"/&quot;/g; $t }
$run{vcrm} = sub {                            # the verification cross-reference matrix, from the model and verification/*.csv
    my $rows = vcrm_data();
    my %n; $n{ $_->{status} }++ for @$rows;
    my $tot = @$rows;
    my $withres = grep { grep { $_ } @{ $_->{results} } } @$rows;
    my $csv = "requirement,method,cases,status,verdicts,evidence\n";
    my $html = "<!DOCTYPE html>\n<html lang=\"en\"><head><meta charset=\"utf-8\"><title>VCRM</title>\n<style>body{font:14px sans-serif;margin:1em}"
             . "table{border-collapse:collapse}td,th{border:1px solid #999;padding:2px 6px;text-align:left}.failed{background:#f3c6c6}.verified{background:#cfe8cf}</style></head><body>\n"
             . "<h1>Verification cross-reference matrix</h1>\n<p>" . ($ENV{CI_COMMIT_SHORT_SHA} ? "Commit $ENV{CI_COMMIT_SHORT_SHA}. " : '')
             . "$tot requirements: " . join(', ', map { "$_ " . ($n{$_} // 0) } 'verified', 'failed', 'not run', 'no case') . ".</p>\n"
             . "<table><tr><th>Requirement</th><th>Method</th><th>Cases</th><th>Status</th><th>Verdicts (newest)</th></tr>\n";
    my $junit = '';
    for my $r (@$rows) {
        my $verd = join('; ', map { my ($c, $v) = ($r->{cases}[$_], $r->{results}[$_]); $v ? "$c $v->{verdict} ($v->{environment}, $v->{timestamp}" . ($v->{signed_by} ? ", $v->{signed_by}" : '') . ')' : "$c no result" } 0 .. $#{ $r->{cases} });
        my $ev = join(' ', sort { $a cmp $b } keys %{ { map { ($_->{source} => 1) } grep { $_ } @{ $r->{results} } } });
        $csv .= join(',', map { my $x = $_; $x =~ /[",]/ ? '"' . ($x =~ s/"/""/gr) . '"' : $x } $r->{id}, $r->{method}, join(' ', @{ $r->{cases} }), $r->{status}, $verd, $ev) . "\n";
        (my $cls = $r->{status}) =~ s/\s+/-/g;
        $html .= "<tr class=\"$cls\"><td>" . xmlq($r->{id}) . "</td><td>" . xmlq($r->{method}) . "</td><td>" . xmlq(join(', ', @{ $r->{cases} })) . "</td><td>" . xmlq($r->{status}) . "</td><td>" . xmlq($verd) . "</td></tr>\n";
        $junit .= qq(  <testcase classname="vcrm" name=") . xmlq($r->{id}) . '"'
                . ($r->{status} eq 'failed' ? ">\n    <failure message=\"" . xmlq($verd) . "\"/>\n  </testcase>\n"
                 : $r->{status} eq 'verified' ? "/>\n" : ">\n    <skipped message=\"" . xmlq($r->{status} eq 'no case' ? 'no verification case' : 'no result yet') . "\"/>\n  </testcase>\n");
    }
    $html .= "</table>\n</body></html>\n";
    spew('vcrm.csv', $csv);
    spew('vcrm.html', $html);
    spew('vcrm.xml', qq(<?xml version="1.0" encoding="UTF-8"?>\n<testsuites>\n<testsuite name="vcrm" tests="$tot" failures=") . ($n{failed} // 0) . qq(" skipped=") . (($n{'not run'} // 0) + ($n{'no case'} // 0)) . qq(">\n$junit</testsuite>\n</testsuites>\n));
    spew('vcrm.metrics', sprintf("vcrm_requirements %d\nvcrm_verified %d\nvcrm_verified_pct %.1f\nvcrm_failed %d\nvcrm_cases_with_result %d\n",
                                 $tot, $n{verified} // 0, $tot ? 100 * ($n{verified} // 0) / $tot : 0, $n{failed} // 0, $withres));
    printf "VCRM: %d requirements, %d verified, %d failed, %d not run, %d without a case (vcrm.html, vcrm.csv)\n",
        $tot, map { $n{$_} // 0 } 'verified', 'failed', 'not run', 'no case';
    0;                                        # reports; the trace ratchet is the gate for missing cases
};
sub harness {                                 # sil-regression / hil-test: run the configured harness, keep its results in the one schema
    my ($kind, $var) = @_;
    my $cmd = $ENV{$var} // '';
    if ($cmd eq '') { print "$kind: no harness configured (set $var to the command that runs it; it must write results-$kind.csv\n"
                            . "with the columns requirement,case,verdict,commit,environment,timestamp,signed_by)\n"; return 0 }
    my $rc = run("$kind.txt", split ' ', $cmd);
    if (-f "results-$kind.csv") { make_path('verification'); copy("results-$kind.csv", "verification/results-$kind.csv"); $run{vcrm}->() }
    $rc;
}
$run{'sil-regression'} = sub { harness('sil', 'SIL_CMD') };
$run{'hil-test'} = sub { harness('hil', 'HIL_CMD') };
$run{intake} = sub {                          # a drop the prime's Jenkins delivered: fetch it, check it against its MANIFEST
    my $ver = $ENV{DROP_VERSION} // '';
    if ($ver !~ /^[\w.+-]+$/) { print "intake needs DROP_VERSION (the trigger's variable), got '$ver'\n"; return 1 }
    my $dir = "intake/$ver";
    make_path($dir);
    my $fetch = sub {                         # one file of prime-drop/<ver>: from the package registry, or a folder (laptop, emulator)
        my $f = shift;
        if ($ENV{INTAKE_DROP_DIR}) { return copy("$ENV{INTAKE_DROP_DIR}/$f", "$dir/$f") ? 0 : 1 }
        if ($ENV{GITLAB_LOCAL_REGISTRY}) {    # the local GitLab emulator: its Generic Package Registry is a folder, NAME/VERSION/FILE
            my $src = "$ENV{GITLAB_LOCAL_REGISTRY}/prime-drop/$ver/$f";
            return -f $src && copy($src, "$dir/$f") ? 0 : 1;
        }
        if (!$ENV{CI_API_V4_URL} || !$ENV{CI_JOB_TOKEN}) { print "no package registry and no INTAKE_DROP_DIR: nothing to fetch\n"; return 1 }
        run(undef, 'curl', '--fail', '--silent', '--show-error', '--header', "JOB-TOKEN: $ENV{CI_JOB_TOKEN}", '--output', "$dir/$f",
            "$ENV{CI_API_V4_URL}/projects/$ENV{CI_PROJECT_ID}/packages/generic/prime-drop/$ver/$f");
    };
    if ($fetch->('MANIFEST.txt')) { print "prime-drop $ver: no MANIFEST.txt\n"; return 1 }
    my $man = slurp("$dir/MANIFEST.txt"); $man =~ s/\r\n/\n/g;
    my @want = $man =~ /^\s+([0-9a-f]{64})\s+(\S+)\s*$/mg;
    my ($bad, $report) = (0, "prime-drop $ver\n");
    $report .= "$_\n" for grep { /^(Built by|Prime repository commit|Tools|Delivered):/ } split /\n/, $man;
    while (my ($sum, $f) = splice @want, 0, 2) {
        if ($fetch->($f)) { $report .= "MISSING  $f\n"; $bad++; next }
        my $got = sha256_file("$dir/$f");
        if ($got eq $sum) { $report .= "ok       $f  sha256 $sum\n" } else { $report .= "MISMATCH $f  manifest $sum, received $got\n"; $bad++ }
    }
    $report .= $bad ? "REJECTED: $bad file(s) missing or altered -- do not import; tell the prime\n"
                    : "ACCEPTED for import: the drop is exactly what the prime's build recorded\n";
    spew('intake.txt', $report);
    print $report;
    return 1 if $bad;
    if ($ENV{INTAKE_TOKEN} && $ENV{CI_SERVER_URL}) {   # open the Prime Drop issue that starts the vendor import (a project access token, masked)
        return perl_tool(undef, 'bin/gitlab.pl', '--url', $ENV{CI_SERVER_URL}, '--token-env', 'INTAKE_TOKEN', '--project', $ENV{CI_PROJECT_PATH},
                         'issue', 'new', "Prime drop $ver", '--template', 'Prime Drop', '--label', 'type::drop', '--label', 'owner::gov');
    }
    print "INTAKE_TOKEN is not set: open the Prime Drop issue by hand (the drop is verified)\n";
    0;
};
# ---------------------------------------------------------------- complexity: the spider-web guardrails
# The dependency graph of the model's root packages: an edge P -> Q when P imports Q, or names an element Q defines (a
# type, a relationship end) -- unique names only. fan-out(P) = distinct packages P depends on, fan-in(P) = distinct
# packages that depend on P, cycles = strongly connected groups of more than one package. Per part def: relationship
# ends (satisfy, verify, allocate, dependency, connect lines naming it) plus incoming type references -- the spaghetti
# measure. Layers (sysml.conf `layers = A, B; C; ...`, lowest first): a package may depend only on its own layer or below.
my $DEFKW = qr/(?:part|port|item|action|attribute|enum|interface|connection|constraint|state|calc|metadata|occurrence|verification|analysis|use\s+case|requirement|allocation|flow)\s+def/;
sub sysml_conf { my %c; for (split /\n/, slurp('sysml.conf') // '') { next if /^\s*#/; $c{$1} = $2 if /^\s*([\w.]+)\s*=\s*(.*?)\s*(?:#.*)?$/ } \%c }
sub _gov_file { my $t = shift // ''; $t =~ m{^// Government-owned} ? 1 : 0 }   # government-authored files say so in their first line
sub model_graph {                             # (\%files: path => text) -> { pkgs => {P => {file, gov}}, edges => {P => {Q => 1}}, rel => {part => n}, defs => {name => P}, wild => [[P, Q, file]] }
    my ($files) = @_;
    my (%pkg, %defs, %dup, %body);
    for my $f (sort keys %$files) {
        (my $t = $files->{$f}) =~ s{//[^\n]*}{}g;
        $t =~ s{/\*.*?\*/}{}gs;
        while ($t =~ /^(?:library\s+)?package\s+('[^']+'|\w+)\s*\{/mg) {
            (my $p = $1) =~ s/'//g;
            my $start = pos($t); my $d = 1; my $i = $start;
            while ($d && $i < length $t) { my $c = substr($t, $i++, 1); $d++ if $c eq '{'; $d-- if $c eq '}' }
            $body{$p} .= substr($t, $start, $i - $start);
            $pkg{$p} = { file => $f, gov => (_gov_file($files->{$f}) ? 1 : 0) };
            pos($t) = $i;
        }
    }
    for my $p (sort keys %body) {
        while ($body{$p} =~ /\b$DEFKW\s+(\w+)/g) { my $n = $1; if (exists $defs{$n} && $defs{$n} ne $p) { $dup{$n} = 1 } else { $defs{$n} = $p } }
        while ($body{$p} =~ /\brequirement\s+(\w+)\s*\{/g) { my $n = $1; if (exists $defs{$n} && $defs{$n} ne $p) { $dup{$n} = 1 } else { $defs{$n} = $p } }
    }
    delete $defs{$_} for keys %dup;           # ambiguous names resolve to nothing (both converters define TW_SYS_001)
    my (%edges, %rel, @wild);
    for my $p (sort keys %body) {
        my $b = $body{$p};
        while ($b =~ /\bimport\s+('[^']+'|\w+)((?:::[\w*']+)*)\s*;/g) {
            (my $q = $1) =~ s/'//g;
            my $rest = $2 // '';
            $edges{$p}{$q} = 1 if $pkg{$q} && $q ne $p;
            push @wild, [$p, $q, $pkg{$p}{file}] if $rest =~ /::\*$/;
        }
        while ($b =~ /(?::>?|~|\bby|\bverify|\bsatisfy|\bto|\bfrom|\ballocate|\bexhibit\s+state\s+\w+\s*:|\bperform\s+action\s+\w+\s*:)\s*(\w+)/g) {
            my $q = $defs{$1} // next;
            $edges{$p}{$q} = 1 if $q ne $p;
        }
        for my $l (split /\n/, $b) {          # relationship ends per part def
            next unless $l =~ /\b(satisfy|verify|allocate|dependency|connect|connection)\b/;
            $rel{$_}++ for grep { ($defs{$_} // '') ne '' } $l =~ /\b(\w+)\b/g;
        }
        while ($b =~ /:>?\s*(\w+)/g) { $rel{$1}++ if $defs{$1} }
    }
    my %parts; for my $p (sort keys %body) { $parts{$1} = 1 while $body{$p} =~ /\bpart\s+def\s+(\w+)/g }
    %rel = map { ($_ => $rel{$_} // 0) } grep { $parts{$_} } keys %parts;
    { pkgs => \%pkg, edges => \%edges, rel => \%rel, defs => \%defs, wild => \@wild, dup => [ sort keys %dup ] };
}
sub sccs {                                    # Tarjan: the strongly connected components with more than one node, each sorted
    my ($edges, @nodes) = @_;
    my ($i, %idx, %low, %on, @st, @out) = (0);
    my $visit; $visit = sub {
        my $v = shift;
        $idx{$v} = $low{$v} = $i++; push @st, $v; $on{$v} = 1;
        for my $w (sort keys %{ $edges->{$v} // {} }) {
            if (!exists $idx{$w}) { $visit->($w); $low{$v} = $low{$w} if $low{$w} < $low{$v} }
            elsif ($on{$w}) { $low{$v} = $idx{$w} if $idx{$w} < $low{$v} }
        }
        if ($low{$v} == $idx{$v}) { my @c; while (1) { my $w = pop @st; $on{$w} = 0; push @c, $w; last if $w eq $v } push @out, [ sort @c ] if @c > 1 }
    };
    $visit->($_) for grep { !exists $idx{$_} } sort @nodes;
    [ sort { $a->[0] cmp $b->[0] } @out ];
}
sub complexity_of {                           # (\%files, \%conf) -> measures and violations
    my ($files, $conf) = @_;
    my $g = model_graph($files);
    my @p = sort keys %{ $g->{pkgs} };
    my (%layer, $n);
    for my $grp (split /;/, $conf->{layers} // '') { $n++; for (split /,/, $grp) { s/^\s+|\s+$//g; s/'//g; $layer{$_} = $n if length } }
    # fan-in/fan-out leave out the first layer of `layers` (the foundation: Conventions, Types): importing the shared
    # vocabulary is what every package should do, like using ScalarValues, not a tangle. Cycles and upward
    # dependencies still see every edge.
    my (%in, %out, %fout, %fin);
    for my $a (@p) { for my $b (keys %{ $g->{edges}{$a} // {} }) { $out{$a}{$b} = 1; $in{$b}{$a} = 1;
        next if ($layer{$b} // 0) == 1; $fout{$a}{$b} = 1; $fin{$b}{$a} = 1 } }
    my %fo = map { ($_ => scalar keys %{ $fout{$_} // {} }) } @p;
    my %fi = map { ($_ => scalar keys %{ $fin{$_} // {} }) } @p;
    my $cyc = sccs($g->{edges}, @p);
    my @up = map { my $a = $_; map { [$a, $_] } grep { defined $layer{$a} && defined $layer{$_} && $layer{$_} > $layer{$a} } sort keys %{ $out{$a} // {} } } @p;
    my @gw = grep { $g->{pkgs}{ $_->[0] }{gov} } @{ $g->{wild} };
    my $mean = sub { my @v = @_; @v ? sprintf('%.1f', (eval { my $s = 0; $s += $_ for @v; $s }) / @v) : '0.0' };
    my @rel = sort { $g->{rel}{$b} <=> $g->{rel}{$a} || $a cmp $b } keys %{ $g->{rel} };
    my %m = (packages => scalar @p, max_fan_out => (sort { $b <=> $a } values %fo)[0] // 0, mean_fan_out => $mean->(values %fo),
             max_fan_in => (sort { $b <=> $a } values %fi)[0] // 0, mean_fan_in => $mean->(values %fi), cycles => scalar @$cyc,
             upward_imports => scalar @up, gov_wildcard_imports => scalar @gw, duplicates => scalar @{ $g->{dup} },
             max_relationships_per_part => @rel ? $g->{rel}{ $rel[0] } : 0, mean_relationships_per_part => $mean->(map { $g->{rel}{$_} } @rel));
    my @v;
    my $mfo = $conf->{max_package_fan_out} // 7;
    push @v, map { [ 'major', $g->{pkgs}{$_}{file}, "package $_ depends on $fo{$_} packages (max_package_fan_out $mfo)" ] } grep { $fo{$_} > $mfo } @p;
    my $mrp = $conf->{max_relationships_per_part} // 10;
    push @v, map { [ 'major', $g->{pkgs}{ $g->{defs}{$_} }{file}, "part def $_ has $g->{rel}{$_} relationship ends (max_relationships_per_part $mrp)" ] } grep { $g->{rel}{$_} > $mrp } @rel;
    push @v, map { [ 'critical', $g->{pkgs}{ $_->[0] }{file}, 'package dependency cycle: ' . join(' -> ', @$_, $_->[0]) ] } @$cyc if @$cyc > ($conf->{max_cycles} // 0);
    push @v, map { [ 'major', $g->{pkgs}{ $_->[0] }{file}, "upward-layer dependency: $_->[0] (layer $layer{$_->[0]}) -> $_->[1] (layer $layer{$_->[1]})" ] } @up;
    push @v, map { [ 'major', $_->[2], "wildcard import $_->[1]::* in government file (name what you use)" ] } @gw;
    { metrics => \%m, fan_in => \%fi, fan_out => \%fo, cycles => $cyc, upward => \@up, rel => $g->{rel}, rel_order => \@rel, violations => \@v, packages => \@p };
}
sub model_files { my $root = shift // 'model'; my %f; File::Find::find({ no_chdir => 1, wanted => sub { $f{$File::Find::name} = slurp($File::Find::name) if /\.sysml$/ && -f } }, $root) if -d $root; \%f }
$run{complexity} = sub {
    my $conf = sysml_conf();
    my $c = complexity_of(model_files('model'), $conf);
    my $txt = sprintf "%-28s %7s %7s\n", 'package', 'fan-in', 'fan-out';
    $txt .= sprintf "%-28s %7d %7d\n", $_, $c->{fan_in}{$_}, $c->{fan_out}{$_} for @{ $c->{packages} };
    $txt .= "\ncycles: " . (@{ $c->{cycles} } ? join('; ', map { join(' <-> ', @$_) } @{ $c->{cycles} }) : 'none') . "\n";
    $txt .= "upward-layer dependencies: " . (@{ $c->{upward} } ? join('; ', map { "$_->[0] -> $_->[1]" } @{ $c->{upward} }) : 'none') . "\n";
    $txt .= "\nrelationship ends per part def (top 5):\n" . join('', map { sprintf "  %-26s %d\n", $_, $c->{rel}{$_} } grep { defined } @{ $c->{rel_order} }[0 .. 4]);
    $txt .= "\n" . join('', map { "$_ $c->{metrics}{$_}\n" } sort keys %{ $c->{metrics} });
    spew('complexity.txt', $txt);
    print $txt;
    spew('complexity.metrics', join('', map { "complexity_$_ $c->{metrics}{$_}\n" } sort keys %{ $c->{metrics} }));
    spew('complexity-cq.json', "[\n" . join(",\n", map { my ($sev, $f, $msg) = @$_; (my $m = $msg) =~ s/(["\\])/\\$1/g;
        qq(  {"description":"$m","check_name":"complexity","fingerprint":") . Digest::SHA::sha1_hex("$f $msg") . qq(","severity":"$sev","location":{"path":"$f","lines":{"begin":1}}}) } @{ $c->{violations} }) . "\n]\n");
    my @hard = grep { $_->[2] =~ /^wildcard import/ } @{ $c->{violations} };
    if (@hard) { print "$_->[1]: $_->[2]\n" for @hard; return 1 }
    if (($ENV{CI_PIPELINE_SOURCE} // '') ne 'merge_request_event') { print "not a merge request: reported only\n"; return 0 }
    # A prime drop (gl flow vendor merges vendor/prime into feature/drop-VERSION) brings the prime's structure as it
    # is: the government does not edit it to pass a ratchet; what got worse goes back to the prime as a Discrepancy
    # Report. The measures above are still reported in the MR; the ratchet applies to the government's own changes.
    if (($ENV{CI_MERGE_REQUEST_SOURCE_BRANCH_NAME} // '') =~ m{^feature/drop-}) {
        print "a prime drop: measured and reported, not ratcheted (raise a Discrepancy Report for what got worse)\n";
        return 0;
    }
    # a release branch carries develop to main: every change in it was ratcheted on its way into develop, and main lags
    # (before the first baseline it has no model at all), so comparing with main would count all of it as new
    if (($ENV{CI_MERGE_REQUEST_SOURCE_BRANCH_NAME} // '') =~ m{^release/}) { print "a release: its changes were checked on develop; reported only\n"; return 0 }
    my $base = $ENV{CI_MERGE_REQUEST_DIFF_BASE_SHA} // '';
    return 0 if $base eq '';
    require File::Temp;
    my $wt = File::Temp::tempdir('ci-cx-XXXXXX', TMPDIR => 1, CLEANUP => 1); rmdir $wt;
    run(undef, 'git', 'worktree', 'add', '-q', '--detach', $wt, $base) and return 0;
    my $old = complexity_of(model_files("$wt/model"), $conf);
    run(undef, 'git', 'worktree', 'remove', '--force', $wt);
    my @worse = grep { $c->{metrics}{$_} > $old->{metrics}{$_} } qw(max_fan_out max_relationships_per_part cycles upward_imports duplicates);
    if (@worse) { print "this change makes the model more tangled: " . join(', ', map { "$_ $old->{metrics}{$_} -> $c->{metrics}{$_}" } @worse) . "\n"; return 1 }
    print "no measure got worse than on the target branch\n";
    0;
};
$run{recipe} = sub {                          # requirement statements graded against the recipe (tools/sysml/req-recipe.pl); reports only
    return do { print "the kit has no tools/sysml/req-recipe.pl: skipped\n"; 0 } unless -f "$KIT/tools/sysml/req-recipe.pl";
    my @in = grep { !is_doors($_) } sysml_files();      # the model side (the coordinator's recipe: DOORS's own conversion excluded)
    if (!@in) { print "no model yet\n"; return 0 }
    perl_tool('recipe.txt', 'tools/sysml/req-recipe.pl', '--format', 'text', @in);
    perl_tool(undef, 'tools/sysml/req-recipe.pl', '--format', 'codequality', '-o', 'recipe-cq.json', @in);
    my ($n, $f, $m) = (slurp('recipe.txt') // '') =~ /requirements=(\d+) findings=(\d+) missing=(\d+)\s*$/;
    spew('recipe.metrics', sprintf("recipe_requirements %d\nrecipe_findings %d\nrecipe_missing_parts %d\n", $n // 0, $f // 0, $m // 0));
    0;
};
$run{docs} = sub {                            # generated docs are committed with the model that made them
    my $rc = perl_tool(undef, 'tools/sysml/model.pl', 'docs');
    return $rc if $rc;
    my $st = out('git', 'status', '--porcelain', '--', 'docs');
    if ($st =~ /\S/) { print $st, "docs/ is stale: run model.pl docs and commit\n"; return 1 }
    print "docs/ is current\n";
    0;
};
$run{delta} = sub {                           # what the prime changed in v1 between the two newest drops
    my @d = imports();
    if (@d < 2) { spew('delta.txt', "first drop: nothing to compare\n"); print "first drop: nothing to compare\n"; return 0 }
    my ($old, $new) = @d[-2, -1];
    perl_tool('delta.txt', 'bin/xmi2sysml.pl', '--delta', "$old/tidewater.xmi", "$new/tidewater.xmi");
};
$run{'drop-package'} = sub {                  # the newest drop, exactly as delivered, into the Generic Package Registry
    if (!$ENV{CI_API_V4_URL} || !$ENV{CI_JOB_TOKEN}) { print "no package registry here (a local run): skipped\n"; return 0 }
    my ($d) = reverse imports() or do { print "no drop imported\n"; return 0 };
    (my $ver = $d) =~ s{^imports/}{};
    my @f = grep { -f "$d/$_" } ls($d);
    for my $f (@f) {
        print "prime-drop $ver: $f\n";
        my $rc = run(undef, 'curl', '--fail', '--silent', '--show-error', '--header', "JOB-TOKEN: $ENV{CI_JOB_TOKEN}", '--upload-file', "$d/$f",
                     "$ENV{CI_API_V4_URL}/projects/$ENV{CI_PROJECT_ID}/packages/generic/prime-drop/$ver/$f");
        return 1 if $rc;
    }
    0;
};
sub toolchain {                               # the tools that produced (and can reproduce) a baseline -- an inventory for the audit
    my $kit = kit_version();
    my ($perl) = sprintf('perl %vd', $^V);
    my ($git) = out('git', '--version') =~ /(git version \S+)/;
    join '', map { "$_\n" } "baseline: " . ($ENV{CI_COMMIT_TAG} // ''), "commit: " . (out('git', 'rev-parse', 'HEAD') =~ /([0-9a-f]{40})/)[0],
        "kit: $kit", $perl, $git // 'git: unknown', "os: " . ($ENV{CI_RUNNER_EXECUTABLE_ARCH} // $^O), "runner: " . ($ENV{CI_RUNNER_DESCRIPTION} // 'unknown'),
        "image: " . ($ENV{CI_JOB_IMAGE} ? "$ENV{CI_JOB_IMAGE}" . ($ENV{CI_JOB_IMAGE_DIGEST} ? "\@$ENV{CI_JOB_IMAGE_DIGEST}" : '') : 'none (shell runner)');
}
$run{baseline} = sub {                        # the tagged tree rebuilds its docs, and the hash matches the tag message
    my $tag = $ENV{CI_COMMIT_TAG} // '';
    if ($tag eq '') { print "baseline runs on a tag (CI_COMMIT_TAG is empty)\n"; return 1 }
    my $rc = perl_tool(undef, 'tools/sysml/model.pl', 'docs');
    return $rc if $rc;
    if (out('git', 'status', '--porcelain', '--', 'docs') =~ /\S/) { print "the tagged tree does not rebuild its docs\n"; return 1 }
    my $hash = docs_hash('HEAD');
    my $msg = out('git', 'tag', '-l', '--format=%(contents)', $tag);
    if (index($msg, "sha256=$hash") < 0) { print "docs hash $hash is not the one recorded in $tag\n"; return 1 }
    spew('toolchain.txt', toolchain() . "docs sha256: $hash\n");
    $run{vcrm}->();                            # the baseline's VCRM, kept with the baseline (expire_in: never)
    my $ms = sprint_of((out('git', 'log', '-1', '--format=%cs', 'HEAD') =~ /(\d{4}-\d\d-\d\d)/)[0]);
    spew('release.env', "RELEASE_MILESTONE=" . ($ms // '') . "\n");   # a dotenv report: the release names the sprint it closes
    print "$tag rebuilds identically (sha256=$hash)\n", slurp('toolchain.txt');
    0;
};
sub sprint_of {                               # the sprint milestone a date falls in, from SPRINT_START (a Monday) and SPRINT_WEEKS
    my $d = shift // return undef;
    my $s = $ENV{SPRINT_START} // return undef;
    require Time::Local;
    my $e = sub { my ($y, $m, $dd) = split /-/, shift; Time::Local::timegm(0, 0, 12, $dd, $m - 1, $y) };
    my $days = ($e->($d) - $e->($s)) / 86400;
    return undef if $days < 0;
    ($ENV{SPRINT_PREFIX} // 'Sprint ') . (int($days / (7 * ($ENV{SPRINT_WEEKS} || 2))) + 1);
}
$run{'publish-package'} = sub {               # the baseline as a package for downstream users: model + docs, VCRM, toolchain
    my $tag = $ENV{CI_COMMIT_TAG} // '';
    if ($tag eq '') { print "publish-package runs on a tag (CI_COMMIT_TAG is empty)\n"; return 1 }
    my $dir = "package-upload/tidewater-model/$tag";
    make_path($dir);
    my $tgz = "tidewater-model-$tag.tar.gz";
    my $rc = run(undef, 'git', 'archive', '--format=tar.gz', "--prefix=tidewater-model-$tag/", '-o', "$dir/$tgz", $tag, '--', 'model', 'docs');
    return $rc if $rc;
    for my $f (grep { -f } 'vcrm.csv', 'toolchain.txt') { copy($f, "$dir/$f") }   # from the baseline job (needs: baseline)
    my @files = grep { -f "$dir/$_" } $tgz, 'vcrm.csv', 'toolchain.txt';
    spew("$dir/SHA256SUMS", join('', map { sha256_file("$dir/$_") . "  $_\n" } @files));
    push @files, 'SHA256SUMS';
    print "tidewater-model $tag: @files\n";
    if (!$ENV{CI_API_V4_URL} || !$ENV{CI_JOB_TOKEN}) { print "no package registry here: the files are in $dir (a local run)\n"; return 0 }
    for my $f (@files) {
        my $rc2 = run(undef, 'curl', '--fail', '--silent', '--show-error', '--header', "JOB-TOKEN: $ENV{CI_JOB_TOKEN}", '--upload-file', "$dir/$f",
                      "$ENV{CI_API_V4_URL}/projects/$ENV{CI_PROJECT_ID}/packages/generic/tidewater-model/$tag/$f");
        return 1 if $rc2;
    }
    0;
};
$run{'publish-release'} = sub {               # the release notes: the tag's section of CHANGELOG.md, then the toolchain
    my $tag = $ENV{CI_COMMIT_TAG} // '';
    my ($on, $notes) = (0, '');
    (my $cl = slurp('CHANGELOG.md') // '') =~ s/\r\n/\n/g;
    $cl =~ s/<!--.*?-->//gs;                  # the scaffold's instructions are an HTML comment: never release notes
    for my $l (split /\n/, $cl) {               # exactly the `## [TAG]` section: up to the next `## ` heading or the link lines
        if ($l =~ /^## /) { $on = ($l =~ /^## \[\Q$tag\E\]/) ? 1 : 0; next }
        next if $l =~ /^\[[^\]]+\]:\s/;      # [baseline-1]: ../-/tags/baseline-1
        $notes .= "$l\n" if $on;
    }
    1 while $notes =~ s/^#{3,6} [^\n]*\n(?:[ \t]*\n)*(?=#{2,6} |\z)//m;   # headings with nothing under them (### Fixed, left empty)
    $notes =~ s/\n{3,}/\n\n/g;
    $notes =~ s/^\s+|\s+$//g;
    $notes = "No CHANGELOG section for $tag." unless length $notes;
    if (-f 'vcrm.csv') { my @r = grep { /\S/ } split /\n/, slurp('vcrm.csv'); shift @r; my $v = grep { /,verified,/ } @r;
        $notes .= "\n\n## Verification\n\n" . scalar(@r) . " requirements, $v verified (VCRM: vcrm.html and vcrm.csv, kept with this release's pipeline)." }
    my $tc = slurp('toolchain.txt');          # from the baseline job (needs: baseline)
    $notes .= "\n\n## Toolchain\n\n```text\n$tc```" if defined $tc && length $tc;
    spew('release-notes.md', "$notes\n");
    print "$notes\n";
    0;
};
$run{pages} = sub {                           # the model's web site: docs, views, trace, burn-down
    make_path('public/views', 'public/docs');
    if (-d 'docs') { File::Find::find({ no_chdir => 1, wanted => sub { return unless -f; (my $r = $File::Find::name) =~ s{^docs/?}{}; my $to = "public/docs/$r";
                                                                   (my $dir = $to) =~ s{/[^/]+$}{}; make_path($dir); copy($File::Find::name, $to) } }, 'docs') }
    for my $v (qw(tree trace ibd pkg)) {          # exit 1 = drawn, with findings (the drawing shows them); more than 1 = not drawn
        my $rc = perl_tool("view-$v.txt", 'tools/sysml/model.pl', 'draw', $v, '-o', "public/views/$v.svg");
        next if $rc <= 1 && -f "public/views/$v.svg";
        spew("public/views/$v.txt", "view $v not drawn (exit $rc): see the job log\n");
        print "view $v not drawn (exit $rc)\n";
        unlink "public/views/$v.svg";
    }
    unlink glob('view-*.txt');
    if (-d 'docs/idef0') {                         # the IDEF0 plates model.pl docs generated
        make_path('public/idef0');
        copy($_, 'public/idef0/') for grep { -f } glob('docs/idef0/svg/*.svg'), 'docs/idef0/plates.html';
    }
    my ($d) = reverse imports();
    my ($reqif) = $d ? grep { -f } "$d/tidewater.reqif" : ();
    perl_tool('public/trace.txt', 'bin/reqif2sysml.pl', '--report', '--model', model_side('model'), $reqif) if $reqif;
    if (-d 'verification' || grep { /verification\s+def/ } map { slurp($_) } sysml_files()) { $run{vcrm}->(); copy($_, "public/$_") for grep { -f } 'vcrm.html', 'vcrm.csv' }
    if (grep { /complexity/ } slurp('.gitlab-ci.yml') // '') {   # the spider-web trend: the last 12 days with a merge
        $run{complexity}->();
        copy('complexity.txt', 'public/complexity.txt');
    }
    my (%day, @order);                        # one point per day: the last first-parent commit of that day
    for my $l (grep { length } split /\n/, out('git', 'log', '--first-parent', '--reverse', '--format=%H %cs', 'HEAD')) {
        my ($sha, $date) = split ' ', $l;
        push @order, $date unless exists $day{$date};
        $day{$date} = $sha;
    }
    my $csv = "date,todo_lines\n";
    for my $date (@order) {
        my $n = 0;
        $n += (split /:/)[-1] for grep { length } split /\n/, out('git', 'grep', '-c', '// TODO', $day{$date}, '--', 'model');
        $csv .= "$date,$n\n";
    }
    spew('public/todo-burndown.csv', $csv);
    if (-f 'public/complexity.txt') {
        my $tr = "date,cycles,max_fan_out,max_relationships_per_part,upward_imports\n";
        my $conf = sysml_conf();
        for my $date (grep { defined } @order[ ($#order > 11 ? $#order - 11 : 0) .. $#order ]) {
            my %f;
            for my $path (grep { /\.sysml$/ } split /\n/, out('git', 'ls-tree', '-r', '--name-only', $day{$date}, '--', 'model')) {
                $f{$path} = out('git', 'show', "$day{$date}:$path");
            }
            my $m = complexity_of(\%f, $conf)->{metrics};
            $tr .= join(',', $date, @$m{qw(cycles max_fan_out max_relationships_per_part upward_imports)}) . "\n";
        }
        spew('public/complexity-trend.csv', $tr);
    }
    perl_tool(undef, 'tools/gitlab/pages-index.pl', '--title', 'Tidewater model', 'public');
};
$run{status} = sub {                          # weekly: what GitLab knows, in the status-metrics formats
    if (!$ENV{STATUS_TOKEN}) { print "STATUS_TOKEN is not set: nothing to export (set it under Settings > CI/CD > Variables)\n"; return 0 }
    my $rc = perl_tool(undef, 'bin/gitlab.pl', '--url', $ENV{CI_SERVER_URL}, '--token-env', 'STATUS_TOKEN', '--project', $ENV{CI_PROJECT_PATH}, 'export', 'exports');
    return $rc if $rc;
    return perl_tool(undef, 'bin/status-metrics.pl', 'collect', '--config', 'metrics.json', '--history', 'exports/history.jsonl') if -f 'metrics.json';
    0;
};

exit main(@ARGV) unless caller;   # `require` it to use the functions (tests/ci-job.t)
1;
