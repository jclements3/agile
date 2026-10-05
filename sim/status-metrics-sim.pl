#!/usr/bin/perl
# status-metrics-sim.pl OUTDIR -- simulate 12 weeks of daily Halberd work and collect the status metrics every day.
#
#   perl sim/status-metrics-sim.pl [OUTDIR]          # default ./sim-out; OUTDIR is wiped first
#
# Builds OUTDIR/repo (a Git repo of SysML v2 text, merged daily), OUTDIR/exports (DOORS ReqIF, legacy XMI, gate log,
# CI jobs, tracker, legacy ICD, sim runs) and OUTDIR/metrics.json, then collects at the end of each working day into
# OUTDIR/history.jsonl (in-process StatusMetrics::cmd_collect, the code behind `status-metrics.pl collect`). The schedule
# reproduces Appendix C (week-end values) and Appendix D (daily items ported) of docs/STATUS-METRICS.html;
# tests/status_metrics.t checks that it does.
#
# A port of the Python kit's sim/simulate.py: the same repo, commits and exports, byte for byte (Python's round() is
# round-half-even, reproduced by pyround). The simulated repo carries its own tools (sim/status-metrics/lint.pl and
# gen_docs.pl, copied into repo/tools/), named in metrics.json as lint_cmd / gen_cmd. Needs git. Notional data only.
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use POSIX qw(floor);
use Time::Local qw(timegm);
use File::Path qw(make_path remove_tree);
use File::Copy qw(copy);
use File::Spec;
use StatusMetrics qw(hash_dir json_encode oh);

my $HERE    = $FindBin::Bin;
my $COLLECT = "$HERE/../bin/status-metrics.pl";
my $START   = timegm(0, 0, 0, 5, 9, 2026);                    # Mon 5 Oct 2026
my %HOLIDAYS = map { $_ => 1 } qw(2026-11-26 2026-11-27 2026-12-24 2026-12-25);
my @SEGS   = split //, 'EVBTGML';
my @WK     = (140, 160, 170, 180, 170, 160, 170, 170, 180, 180, 160, 120);
my @DAYSEG = qw(EEEEE EEEEE EEVVV VVVVV VVBBB BBBBB BBTTT TTT GGGGG MMMMM MMLLL LLL);
# week-end targets, index 0 = start (Appendix C)
my %ARR = (
    C  => [0, 0, 90, 210, 340, 480, 610, 760, 900, 1050, 1210, 1360, 1450],
    F  => [0, 0, 12, 41, 66, 58, 47, 52, 39, 28, 17, 8, 3],
    G  => [0, 0, 20, 55, 80, 74, 63, 60, 48, 35, 22, 11, 4],
    H  => [0, 0, 4, 11, 16, 25, 31, 39, 42, 46, 48, 49, 49],
    QU => [0, 0, 2, 3, 2, 4, 1, 3, 0, 1, 0, 1, 0],
    QT => [0, 0, 4, 7, 9, 13, 15, 19, 21, 23, 25, 27, 27],
    RT => [0, 0, 1, 3, 4, 6, 7, 8, 10, 12, 12, 12, 12],
    RU => [0, 0, 0, 1, 2, 3, 3, 3, 3, 2, 1, 1, 0],
    TL => [undef, undef, undef, undef, undef, undef, 47, 40, 31, 22, 14, 6, 0],
);
my @K      = (undef, undef, undef, undef, 9, 9, 8, 8, 7, 7, 6, 6, 6);
my @LEAD   = (undef, 12, 11, 10, 9, 8, 7, 6, 5, 4, 4, 3, 3);
my @MERGES = (21, 26, 24, 22, 28, 25);
my @COMMIT = (320, 360, 375, 360, 370, 280);
my %FIXFWD = ('1,2' => 0, '2,1' => 0, '3,2' => 0, '4,1' => 0, '5,2' => 0, '7,2' => 0, '9,2' => 0, '11,2' => 0);
my %GATED  = ('3,2' => 'E', '5,2' => 'V', '7,2' => 'B', '8,3' => 'T', '9,5' => 'G', '11,2' => 'M', '12,3' => 'L');
my %BASELINE = ('4,5' => 1, '8,3' => 2, '12,3' => 3);
my @DOCS   = qw(interface_table.csv icd.csv req_trace.csv element_index.txt seg_E.txt seg_V.txt
                seg_B.txt seg_T.txt seg_G.txt seg_M.txt seg_L.txt threat_register.csv);
my @DOC_ON = ('4,4', '6,3', '7,3', '8,2', '9,2', '9,4', '10,2', '10,3', '11,1', '11,4', '12,1', '12,2');
my $PARAMS_ON  = '8,2';
my %RUNS   = ('8,2' => 12, '9,3' => 3, '10,3' => 4, '11,4' => 2);
my %BLOCKED = ('5,3' => 1, '5,4' => 2, '5,5' => 3);
my $GATE_BREAK = '11,3';
my @ZONES  = qw(trusted dmz untrusted);
my @FIELDS = qw(from to fromZone toZone signal rate units);

sub pyround {                                 # Python 3 round(x): half to even
    my ($x) = @_;
    my $f = floor($x);
    my $d = $x - $f;
    return int($d > 0.5 ? $f + 1 : $d < 0.5 ? $f : ($f % 2 ? $f + 1 : $f));
}
sub ymd { my @t = gmtime $_[0]; sprintf '%04d-%02d-%02d', $t[5] + 1900, $t[4] + 1, $t[3] }
sub iso { my @t = gmtime $_[0]; sprintf '%04d-%02d-%02dT%02d:%02d:%02d+00:00', $t[5] + 1900, $t[4] + 1, $t[3], @t[2, 1, 0] }
sub sum { my $s = 0; $s += $_ for @_; $s }
sub spew { my ($p, $t, $mode) = @_; open my $fh, ($mode // '>') . ':raw', $p or die "$p: $!\n"; print {$fh} $t; close $fh or die "$p: $!\n" }
sub csv_rows { join '', map { join(',', @$_) . "\r\n" } @_ }   # csv.writer: CRLF; no field here needs quoting
sub before_eq { my ($p, $q) = @_; my ($a1, $a2) = split /,/, $p; my ($b1, $b2) = split /,/, $q; $a1 < $b1 || ($a1 == $b1 && $a2 <= $b2) }

sub sh {                                      # sh($cwd, \%env, @cmd) -> stdout; dies on a non-zero exit (check=True)
    my ($cwd, $env, @cmd) = @_;
    local @ENV{ keys %$env } = values %$env;
    my $pid = open(my $fh, '-|') // die "fork: $!\n";
    if (!$pid) {
        if (!chdir $cwd) { print STDERR "chdir $cwd: $!\n"; POSIX::_exit(127) }
        open STDERR, '>', File::Spec->devnull;
        exec { $cmd[0] } @cmd or do { print STDERR "exec $cmd[0]: $!\n"; POSIX::_exit(127) };
    }
    binmode $fh;
    local $/;
    my $out = <$fh> // '';
    close $fh;
    die "@cmd: exit " . ($? >> 8) . "\n" if $?;
    return $out;
}

sub schedule {
    my (@days, $cum);
    $cum = 0;
    for my $w (0 .. 11) {
        my $mon = $START + $w * 7 * 86400;
        my @ds = grep { !$HOLIDAYS{ ymd($_) } } map { $mon + $_ * 86400 } 0 .. 4;
        my @wts = $w == 0 ? (0, .15, .25, .3, .3) : @{ { 5 => [.18, .22, .2, .22, .18], 3 => [.32, .36, .32] }->{ scalar @ds } };
        my @cnt = map { pyround($WK[$w] * $_) } @wts;
        $cnt[-1] += $WK[$w] - sum(@cnt);
        my $done = 0;
        for my $i (0 .. $#ds) {
            my $c = $cnt[$i];
            $done += $c;
            $cum += $c;
            push @days, { w => $w + 1, d => $i + 1, date => $ds[$i], n => $c, cum => $cum, seg => substr($DAYSEG[$w], $i, 1), f => $done / $WK[$w] };
        }
    }
    for my $s (1 .. 6) {                      # merges per day, spread evenly over each sprint
        my @sd = grep { int(($_->{w} + 1) / 2) == $s } @days;
        my ($base, $rem) = (int($MERGES[ $s - 1 ] / @sd), $MERGES[ $s - 1 ] % @sd);
        $sd[$_]{merges} = $base + ($_ < $rem ? 1 : 0) for 0 .. $#sd;
    }
    return \@days;
}

sub interp {
    my ($arr, $w, $f) = @_;
    my ($lo, $hi) = ($arr->[ $w - 1 ], $arr->[$w]);
    return undef unless defined $hi;
    return $hi unless defined $lo;
    return pyround($lo + ($hi - $lo) * $f);
}

sub iface {
    my ($i) = @_;
    return oh(fromSeg => $SEGS[ $i % 7 ], toSeg => $SEGS[ ($i + 3) % 7 ], fromZone => $ZONES[ $i % 3 ], toZone => $ZONES[ ($i + 1) % 3 ],
              signal => sprintf('SIG%03d', $i), rate => '' . (10 * $i), units => 'Hz');
}

my %JC = ();
my @JC = ('-c', 'user.name=JC', '-c', 'user.email=jc@halberd.example');

sub new_sim {
    my ($out) = @_;
    my $s = { out => $out, repo => "$out/repo", ex => "$out/exports" };
    remove_tree($out);
    make_path($s->{repo}, "$s->{ex}/tracker", "$s->{ex}/runs");
    $s->{els} = { map { $_ => [] } @SEGS };                    # parts per segment
    $s->{nifc} = 0; $s->{ifc_seg} = [];                         # interfaces in porting order with their segment
    $s->{gated} = []; $s->{docs} = []; $s->{params} = 0; $s->{fixlog} = 0;
    $s->{tgt} = { C => 0, F => 0, G => 0, QU => 0, RT => 0, RU => 0 };
    $s->{nrun} = 0;
    return $s;
}

# ------------------------------------------------ files
sub setup {
    my ($s) = @_;
    my ($r, $ex) = ($s->{repo}, $s->{ex});
    sh($r, \%JC, qw(git init -q -b main));
    # repo-local settings so a Windows global config (autocrlf, signing) cannot change the bytes the baselines hash
    sh($r, \%JC, qw(git config core.autocrlf false));
    sh($r, \%JC, qw(git config commit.gpgsign false));
    sh($r, \%JC, qw(git config tag.gpgsign false));
    make_path("$r/tools");
    for my $t (qw(lint.pl gen_docs.pl)) { copy("$HERE/status-metrics/$t", "$r/tools/$t") or die "copy $t: $!\n" }
    my @types = qw(Class Port Property Connector Activity);
    spew("$ex/legacy.xmi", "<xmi:XMI>\n"
        . join('', map { sprintf qq(  <packagedElement xmi:type="uml:%s" xmi:id="v1_%04d"/>\n), $types[ $_ % 5 ], $_ } 0 .. 1959)
        . join('', map { sprintf qq(  <ownedComment xmi:type="uml:Comment" xmi:id="c_%04d"/>\n), $_ } 0 .. 299)
        . "</xmi:XMI>\n");
    spew("$ex/export.reqif", "<REQ-IF>\n" . join('', map { sprintf qq(<SPEC-OBJECT IDENTIFIER="HAL-%04d"/>\n), $_ } 1 .. 1450) . "</REQ-IF>\n");
    my $cfg = oh(repo => 'repo', exports => 'exports', start => ymd($START), sprint_weeks => 2,
        segments => 7, docs_total => 12, params_total => 64, team => 7, hours_per_doc => 3.75,
        old_regen_days => 4, old_lead_days => 19, exclude_authors => ['JC'],
        lint_cmd => [ $^X, 'tools/lint.pl', 'model' ],
        gen_cmd => [ $^X, '{src}/tools/gen_docs.pl', '{src}', '{out}' ]);
    $s->{cfg} = "$s->{out}/metrics.json";
    spew($s->{cfg}, json_encode($cfg, 2));
    sh($s->{out}, \%JC, $^X, $COLLECT, 'init', '--config', $s->{cfg}, '--xmi', "$ex/legacy.xmi", '--reqif', "$ex/export.reqif");
    spew("$ex/ci_jobs.csv", "ts,job,branch,result,minutes\n");
    spew("$ex/gate.log", '');
    spew("$r/README.md", "Halberd system model (SysML v2 text). Notional.\n");
    my $t0 = iso(timegm(0, 0, 12, 2, 9, 2026));
    sh($r, \%JC, qw(git add -A));
    sh($r, { GIT_AUTHOR_DATE => $t0, GIT_COMMITTER_DATE => $t0 }, 'git', @JC, qw(commit -q -m), 'Initial commit');
}

sub render {
    my ($s, $note) = @_;
    my $r = $s->{repo};
    my $md = "$r/model";
    remove_tree($md);
    my $tgt = $s->{tgt};
    for my $sg (@SEGS) {
        my @ifcs = grep { $s->{ifc_seg}[ $_ - 1 ] eq $sg } 1 .. @{ $s->{ifc_seg} };
        next if !@{ $s->{els}{$sg} } && !@ifcs;
        make_path("$md/$sg");
        spew("$md/$sg/structure.sysml", "package $sg {\n" . join('', map { "  part def $_;\n" } @{ $s->{els}{$sg} }) . "}\n");
        if (@ifcs) {
            my %unc = map { $_ => 1 } $s->{nifc} - $tgt->{QU} + 1 .. $s->{nifc};
            my $t = "package ${sg}_ifc {\n";
            for my $i (@ifcs) {
                my $at = iface($i);
                $at->{secReq} = $unc{$i} ? '' : sprintf('SR-%03d', $i);
                $t .= sprintf('  interface IF%03d { ', $i) . join(' ', map { qq(attribute $_ = "$at->{$_}";) } keys %$at) . " }\n";
            }
            spew("$md/$sg/interfaces.sysml", "$t}\n");
        }
    }
    if ($s->{params}) {
        make_path("$md/T");
        spew("$md/T/params.sysml", "package T_params {\n" . join('', map { sprintf "  attribute p_%02d : Real;\n", $_ } 1 .. 64) . "}\n");
    }
    my ($c, $fo, $g) = @$tgt{qw(C F G)};
    if ($c) {
        make_path("$md/_reqs");
        my $t = "package Requirements {\n";
        $t .= sprintf qq(  requirement r%04d { attribute doorsId = "HAL-%04d"; }\n), $_, $_ for 1 .. $c;
        my $both = $c - $fo - $g;
        for my $i (1 .. $c) {
            $t .= sprintf "  satisfy r%04d by E0001;\n", $i if $i <= $both || $i > $both + $fo;   # orphans (no satisfy) sit in (both, both+fo]
            $t .= sprintf "  verify r%04d;\n", $i if $i <= $both + $fo;                           # unverified sit in (both+fo, c]
        }
        spew("$md/_reqs/requirements.sysml", "$t}\n");
    }
    if ($tgt->{RT}) {
        make_path("$md/_sec");
        my $t = "package Threats {\n";
        for my $i (1 .. $tgt->{RT}) {
            my $mit = $i > $tgt->{RT} - $tgt->{RU} ? '' : sprintf('MIT-%02d', $i);
            $t .= sprintf qq(  metadata TH%02d : Threat { attribute mitigation = "%s"; }\n), $i, $mit;
        }
        spew("$md/_sec/threats.sysml", "$t}\n");
    }
    make_path("$r/docs");
    spew("$r/docs/enabled.txt", join('', map { "$_\n" } @{ $s->{docs} }));
    spew("$r/CODEOWNERS", "# segment owners\n" . join('', map { "/model/$_/ \@owner-$_\n" } @{ $s->{gated} }));
    make_path("$r/notes");
    spew("$r/notes/changes.log", "$note\n", '>>');
    if ($s->{fixlog}) {
        make_path("$md/_meta");
        spew("$md/_meta/fixlog.sysml", join('', map { "// fix-forward $_\n" } 1 .. $s->{fixlog}));
    }
    sh($r, \%JC, $^X, 'tools/gen_docs.pl', '.', 'generated');
}

# ------------------------------------------------ git
# A feature branch merged with --no-ff, built with plumbing: commit on main (parent: main), then a merge commit whose
# parents are the old main and that commit, same tree, and main moved to it. The commit objects are exactly those of
# `checkout -b; commit; checkout main; merge --no-ff -m "Merge BR"; branch -D` (simulate.py), in 4 git calls instead
# of 6 and without rewriting the working tree twice -- process starts and file writes are what is slow on Windows.
sub merge {
    my ($s, $name, $merge_ts, $lead_days, $author, $fix) = @_;
    my $r = $s->{repo};
    my $br = ($fix ? 'fix-forward/' : 'feature/') . $name;
    $s->{fixlog}++ if $fix;
    render($s, iso($merge_ts) . " $br");
    my $b_ts = iso($merge_ts - $lead_days * 86400);
    sh($r, \%JC, qw(git add -A));
    sh($r, { GIT_AUTHOR_DATE => $b_ts, GIT_COMMITTER_DATE => $b_ts }, 'git', '-c', "user.name=$author", '-c', "user.email=$author\@halberd.example",
       qw(commit -q -m), $name);
    my $m_ts = iso($merge_ts);
    my $m = sh($r, { GIT_AUTHOR_DATE => $m_ts, GIT_COMMITTER_DATE => $m_ts }, 'git', @JC, 'commit-tree', 'HEAD^{tree}', '-p', 'HEAD~1', '-p', 'HEAD', '-m', "Merge $br");
    $m =~ s/\s+\z//;
    sh($r, \%JC, qw(git update-ref refs/heads/main), $m);
}

# ------------------------------------------------ one day
sub nparts { my ($s) = @_; sum(map { scalar @{ $s->{els}{$_} } } @SEGS) }

sub day {
    my ($s, $x, $prev) = @_;
    my ($w, $d, $k, $f) = ($x->{w}, $x->{d}, "$x->{w},$x->{d}", $x->{f});
    my $day0 = $x->{date};
    my $new_ifc = interp($ARR{QT}, $w, $f) - $s->{nifc};
    my $new_parts = $x->{n} - $new_ifc;
    my $m = $x->{merges};
    my $part_base = nparts($s);
    for my $j (0 .. $m - 1) {
        my $final = $j == $m - 1;
        my $target = $part_base + ($final ? $new_parts : pyround($new_parts * ($j + 1) / $m));
        my $seg = $x->{seg};
        while ((my $n = nparts($s)) < $target) { push @{ $s->{els}{$seg} }, sprintf('E%04d', $n + 1) }
        my $author = 'JC';
        if ($final) {
            for (1 .. $new_ifc) { $s->{nifc}++; push @{ $s->{ifc_seg} }, $seg }
            $s->{tgt}{$_} = interp($ARR{$_}, $w, $f) for qw(C F G QU RT RU);
            for my $i (0 .. $#DOC_ON) { push @{ $s->{docs} }, $DOCS[$i] if $DOC_ON[$i] eq $k && !grep { $_ eq $DOCS[$i] } @{ $s->{docs} } }
            $s->{params} = 1 if $k eq $PARAMS_ON;
            if ($GATED{$k}) { push @{ $s->{gated} }, $GATED{$k}; $author = "owner-$GATED{$k}" }
        }
        my $fix = defined $FIXFWD{$k} && $FIXFWD{$k} == $j;
        merge($s, sprintf('w%02dd%dm%d', $w, $d, $j + 1), $day0 + 9 * 3600 + 45 * 60 * $j, $LEAD[$w], $author, $fix);
    }
    if ($BASELINE{$k}) {
        my $h = hash_dir("$s->{repo}/generated/docs");
        my $t = iso($day0 + 18 * 3600);
        sh($s->{repo}, { GIT_COMMITTER_DATE => $t }, 'git', @JC, qw(tag -a), "baseline-$BASELINE{$k}", '-m', "sha256=$h");
    }
    exports($s, $x, $prev, $day0);
}

sub exports {
    my ($s, $x, $prev, $day0) = @_;
    my ($w, $k, $ex) = ($x->{w}, "$x->{w},$x->{d}", $s->{ex});
    my $at = sub { my ($h, $mi) = @_; iso($day0 + $h * 3600 + ($mi // 0) * 60) };
    my $h_now = interp($ARR{H}, $w, $x->{f});
    my $h_prev = $prev ? interp($ARR{H}, $prev->{w}, $prev->{f}) : 0;
    spew("$ex/gate.log", join('', map { $at->(10, $_) . " E-IF interface mismatch caught at merge\n" } 0 .. $h_now - $h_prev - 1), '>>');
    my $ci = '';
    $ci .= $at->(8) . ",lint,main,fail,1\n" . $at->(10) . ",lint,main,pass,1\n" if $k eq $GATE_BREAK;
    $ci .= $at->(17) . ",lint,main,pass,1\n";
    $ci .= $at->(17, 10) . ",docs,main,pass,$K[$w]\n" if @{ $s->{docs} } && defined $K[$w];
    spew("$ex/ci_jobs.csv", $ci, '>>');
    my $sp = int(($w + 1) / 2);
    my @sdays = grep { int(($_->{w} + 1) / 2) == $sp && $_->{date} <= $x->{date} } @{ $s->{days} };
    my $done = sum(map { $_->{n} } @sdays);
    $done = $COMMIT[ $sp - 1 ] if $done > $COMMIT[ $sp - 1 ];
    my $bd = 0;
    for my $kk (keys %BLOCKED) { my ($kw) = split /,/, $kk; $bd = $BLOCKED{$kk} if int(($kw + 1) / 2) == $sp && before_eq($kk, $k) && $BLOCKED{$kk} > $bd }
    spew("$ex/tracker/sprint-$sp.csv", csv_rows([qw(id status blocked_days blocker)],
        map { my $bl = $_ == 0 ? $bd : 0; [ sprintf(q(S%d-%03d), $sp, $_ + 1), $_ < $done ? q(done) : q(open), $bl, $bl ? 'a shared runner' : '' ] } 0 .. $COMMIT[ $sp - 1 ] - 1));
    if (grep { $_ eq 'icd.csv' } @{ $s->{docs} }) {
        my $open = $w > 6 ? interp($ARR{TL}, $w, $x->{f}) : $ARR{TL}[6];
        my %rows = map { $_ => iface($_) } 1 .. 27;
        for my $j (0 .. $open - 1) {
            my ($i, $fld) = (1 + int($j / @FIELDS), $FIELDS[ $j % @FIELDS ]);
            my $key = { from => 'fromSeg', to => 'toSeg' }->{$fld} // $fld;
            $rows{$i}{$key} .= '_LEGACY';
        }
        spew("$ex/legacy_icd.csv", csv_rows([ 'id', @FIELDS ],
            map { my $row = $rows{$_}; [ sprintf(q(IF%03d), $_), @$row{qw(fromSeg toSeg fromZone toZone signal rate units)} ] } 1 .. 27));
    }
    for (1 .. ($RUNS{$k} // 0)) {
        $s->{nrun}++;
        my $rd = sprintf '%s/runs/run-%04d', $ex, $s->{nrun};
        make_path($rd);
        spew("$rd/provenance.txt", 'date=' . ymd($x->{date}) . "\nmodel_baseline=baseline-1\n");
    }
}

sub run_sim {
    my ($s) = @_;
    setup($s);
    $s->{days} = schedule();
    my $hist = "$s->{out}/history.jsonl";
    my $prev;
    local $| = 1;
    for my $x (@{ $s->{days} }) {
        day($s, $x, $prev);
        StatusMetrics::cmd_collect(config => $s->{cfg}, 'as-of' => ymd($x->{date}), history => $hist);   # = status-metrics.pl collect, in-process
        $prev = $x;
        printf "%s W%dD%d ported %3d left %5d\n", ymd($x->{date}), $x->{w}, $x->{d}, $x->{n}, 1960 - $x->{cum};
    }
    return $hist;
}

my $out = File::Spec->rel2abs($ARGV[0] // 'sim-out');
run_sim(new_sim($out));
