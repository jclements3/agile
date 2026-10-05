#!/usr/bin/perl
# perl tests/sysml.t -- the SysML v2 tools (tools/sysml/) on the Halberd example (examples/halberd/):
#   1. sysml.pl: every example file parses against the official grammar; known-bad snippets fail with
#      the right file:line:col diagnostic
#   2. model.pl: lint / check / stats / trace / nouns / verbs / tags / idef0 / backlog give the expected
#      counts on a copy of the example, and the committed docs/ are what docs regenerates
#   3. model.pl on copies with a planted fault fails with the right message
#   4. the status-metrics collector reads the example as intended (lib/StatusMetrics.pm, when present)
# Core Perl only; writes nothing in the repo (everything runs on copies in a temp dir).
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use File::Temp qw(tempdir);
use File::Find ();
use File::Path qw(make_path);
use File::Copy qw(copy);

my ($n, $bad) = (0, 0);
sub check { my ($name, $got, $want) = @_; $n++;
    if ($got eq $want) { print "ok $n - $name\n" }
    else { $bad++; print "not ok $n - $name\n#   got:  $got\n#   want: $want\n" } }
sub like { my ($name, $got, $re) = @_; $n++;
    if ($got =~ $re) { print "ok $n - $name\n" }
    else { $bad++; (my $g = $got) =~ s/^/#   /mg; print "not ok $n - $name\n#   want: $re\n$g\n" } }
sub slurp { my ($p) = @_; open my $fh, '<:raw', $p or die "$p: $!\n"; local $/; my $t = <$fh>; close $fh; $t // '' }
sub spew { my ($p, $t) = @_; open my $fh, '>:raw', $p or die "$p: $!\n"; print {$fh} $t; close $fh }

my $root  = "$FindBin::Bin/..";
my $SYSML = "$root/tools/sysml/sysml.pl";
my $MODEL = "$root/tools/sysml/model.pl";
my $EX    = "$root/examples/halberd";
my $tmp   = tempdir(CLEANUP => 1);

sub q_ { my $s = shift; $s =~ s/"/\\"/g; qq("$s") }
sub run {                                   # (cwd or undef, args...) -> (output with stderr, exit status)
    my ($cwd, @a) = @_;
    my $cmd = join ' ', map { q_($_) } $^X, @a;
    $cmd = 'cd ' . q_($cwd) . " && $cmd" if defined $cwd;
    my $out = `$cmd 2>&1`;
    ($out, $? >> 8);
}
sub files_under { my @f; File::Find::find({ no_chdir => 1, wanted => sub { push @f, $_ if -f $_ } }, @_); sort @f }
sub copy_tree {                             # copy_tree(src, dst): the example as a fresh project
    my ($src, $dst) = @_;
    for my $f (files_under($src)) {
        (my $rel = $f) =~ s/^\Q$src\E//;
        next if $rel =~ m{/tags\z};
        make_path("$dst" . ($rel =~ s{/[^/]*\z}{}r));
        copy($f, "$dst$rel") or die "copy $f: $!\n";
    }
}
sub fresh { my $d = "$tmp/" . shift; copy_tree($EX, $d); $d }
sub edit { my ($f, $from, $to) = @_; my $t = slurp($f); my $c = $t =~ s/\Q$from\E/$to/; die "edit $f: '$from' not found\n" unless $c; spew($f, $t) }

# ---------------------------------------------------------------- 1. sysml.pl: the grammar
my @model = grep { /\.sysml\z/ } files_under("$EX/model");
check 'the example has 29 model files in 7 segment folders', scalar(@model) . ' ' . scalar(do { my %d = map { m{/model/([^/]+)/} ? ($1 => 1) : () } @model; keys %d }), '29 7';
my ($o, $rc) = run(undef, $SYSML, 'check', @model);
check 'sysml.pl check: every example file parses', "$rc " . (split /\n/, $o)[-1], '0 sysml: 29 file(s), 0 error(s)';
($o, $rc) = run(undef, $SYSML, 'grammar');
like 'sysml.pl grammar: both grammars load (vendored release + errata), nothing undefined', $o, qr/^kerml\s+\d+ rules.*\nsysml\s+\d+ rules, \d+ keywords, \d+ symbols, start RootNamespace\n\z/;

my %snippet = (                            # name => [text, expected diagnostic]
    'missing semicolon' => [ "package P {\n    part def A {\n        attribute a : Real\n    }\n}\n",
                             qr/^\S*missing-semicolon\.sysml:4:5: error: unexpected '\}'; expected / ],
    'keyword as a name' => [ "package P {\n    part def library;\n}\n",
                             qr/^\S*keyword-as-a-name\.sysml:2:14: error: unexpected 'library'/ ],
    'attribute keyword inside a metadata body' => [ qq(package P {\n    metadata t1 : Threat { attribute mitigation = "M-1"; }\n}\n),
                             qr/^\S*attribute-keyword-inside-a-metadata-body\.sysml:2:38: error: unexpected 'mitigation'; expected 'def'/ ],
    'unclosed block' => [ "package P {\n    part def A {\n}\n",
                             qr/^\S*unclosed-block\.sysml:4:1: error: unexpected end of file/ ],
    'stray character' => [ "package P {\n    part def A ` ;\n}\n",
                             qr/^\S*stray-character\.sysml:2:16: error: unexpected character `/ ],
);
for my $name (sort keys %snippet) {
    (my $file = "$tmp/$name.sysml") =~ s/ /-/g;
    spew($file, $snippet{$name}[0]);
    ($o, $rc) = run(undef, $SYSML, 'check', $file);
    like "sysml.pl rejects: $name", "$rc $o", qr/^1 /;
    like "  ... with the right diagnostic", (split /\n/, $o)[0], $snippet{$name}[1];
}

# ---------------------------------------------------------------- 2. model.pl on a copy of the example
my $p = fresh('halberd');
($o, $rc) = run(undef, $MODEL, '--root', $p, 'lint');
check 'lint: 0 errors, 0 warnings, and the collector line', "$rc\n$o", "0\nlint: 29 file(s), 0 error(s), 0 warning(s)\nelements=226 errors=0 warnings=0\n";
($o, $rc) = run(undef, $MODEL, '--root', $p, 'check');
check 'check: no level-tag mismatches, no outline violations', $rc, 0;
like '  ... and says so', $o, qr/\@L tag mismatches\s+0\n.*violations\s+0\n\z/s;
($o, $rc) = run(undef, $MODEL, '--root', $p, 'stats');
my %stat = $o =~ /^(\S[^\n]*?)\s{2,}(\d+)\s*$/mg;
check 'stats: element counts', join(' ', map { "$_=" . ($stat{$_} // '?') } 'files', 'packages', 'part defs (nouns)', 'action defs (verbs)',
        'item defs', 'port defs', 'interface defs', 'requirements', 'verification defs', 'satisfy', 'verify', 'allocate', 'interface usages'),
    'files=29 packages=36 part defs (nouns)=65 action defs (verbs)=22 item defs=21 port defs=5 interface defs=4 requirements=66 verification defs=15 satisfy=63 verify=62 allocate=9 interface usages=10';
like 'stats: the noun tree is 6 levels from HalberdEnterprise', $o, qr/Nouns \(parts\) from HalberdEnterprise ==\ndepth\s+6 levels\n.*\ndefinitions per level\s+L1=1, L2=6, L3=13, L4=30, L5=8, L6=3\n/;
like 'stats: the verb tree is 4 levels from DefendAgainstThreat', $o, qr/Verbs \(functions\) from DefendAgainstThreat ==\ndepth\s+4 levels\n/;
($o, $rc) = run(undef, $MODEL, '--root', $p, 'trace');
like 'trace: 66 requirements, the 3 orphans and 4 unverified planted in the example', "$rc $o",
    qr/^0 trace: 66 requirements \(66 leaf\), 3 not satisfied, 4 not verified -> /;
check '  ... by DOORS id', join(' ', $o =~ /^  (\S+): not/mg), 'HAL-SYS-016 HAL-SYS-035 HAL-BMF-008 HAL-INT-006 HAL-PRD-005 HAL-SUS-005 HAL-TST-003';
($o, $rc) = run(undef, $MODEL, '--root', $p, 'trace', '--strict');
check 'trace --strict: exit 1 on the gaps', $rc, 1;
($o, $rc) = run(undef, $MODEL, '--root', $p, 'verbs', '--plain', '--ascii');
check 'verbs: the kill chain, top level', join(', ', $o =~ /^[|`]-- (\w+)/mg), 'Detect, Track, Identify, Decide, Engage, Assess';
($o, $rc) = run(undef, $MODEL, '--root', $p, 'nouns', '--plain', '--ascii');
check 'nouns: the six segments', join(', ', $o =~ /^[|`]-- ([^\n]+)/mg), 'Sensor Segment, Fire Control Segment, Interceptor Segment, Launch Segment, Support Segment, Test Segment';
($o, $rc) = run(undef, $MODEL, '--root', $p, 'tags');
like 'tags: written, with DOORS ids as tags', "$rc $o " . slurp("$p/tags"), qr/^0 tags: wrote \d+ tags.*\nHAL-SYS-001\tmodel\/engineering\/SystemRequirements\.sysml\t\d+;"\tr\n/s;
($o, $rc) = run(undef, $MODEL, '--root', $p, 'docs');
like 'docs: the IDEF0 set lints clean (agile tools/idef0/idef0.pl)', "$rc $o", qr/^0 .*0 error\(s\), 0 warning\(s\), 6 model\(s\), 15 activities, 7 link\(s\)/s;
my @gen = map { s{^\Q$EX/\E}{}r } files_under("$EX/docs");
check 'docs: the committed examples/halberd/docs/ is exactly what docs regenerates (' . scalar(@gen) . ' files)',
    join(' ', grep { slurp("$EX/$_") ne slurp("$p/$_") } @gen) || 'all equal', 'all equal';
check '  ... and nothing extra is generated', join(' ', map { s{^\Q$p/\E}{}r } files_under("$p/docs")), join(' ', @gen);
($o, $rc) = run(undef, $MODEL, '--root', $p, 'backlog');
like 'backlog: the kill chain as a planning stand-up file, one team per step', "$rc $o", qr/^0 .*== Detect\n.*new D-1 \d+ Condition Signals .*== Engage\n.*new IF-\d+ \d+ Interface: /s;
($o, $rc) = run("$p/model/interceptor", $MODEL, 'check');
check 'root discovery: model.pl finds the project upward from model/<segment>/', $rc, 0;
($o, $rc) = run($tmp, $MODEL, 'check');
like 'no project here or above: exit 2, with a hint', "$rc $o", qr/^2 model\.pl: no model\/ directory .*--root DIR/;
{   local $ENV{SYSML_JAR} = "$tmp/no-such.jar";
    local $ENV{JAVA_HOME};
    ($o, $rc) = run(undef, $MODEL, '--root', $p, 'validate');
    like 'validate without the Pilot jar: skipped cleanly (exit 3)', "$rc $o", qr/^3 validate: skipped -- needs Java/;
}

# ---------------------------------------------------------------- 3. planted faults
my $f1 = fresh('f-outline');
edit("$f1/model/firecontrol/FireControl.sysml", "        part crypto : CryptoUnit;\n", '');
($o, $rc) = run(undef, $MODEL, '--root', $f1, 'check');
like 'fault: a part with one child breaks the 2..9 rule', "$rc $o", qr/^1 .*violations\s+1\n\s+1  part def CommunicationsNode: parts  \(\S*model\/firecontrol\/FireControl\.sysml\)/s;
my $f2 = fresh('f-level');
edit("$f2/model/interceptor/SeekerComponents.sysml", 'part def Cryocooler { @L6Component;', 'part def Cryocooler { @L5Assembly;');
($o, $rc) = run(undef, $MODEL, '--root', $f2, 'check');
like 'fault: a wrong level tag', "$rc $o", qr/^1 .*\@L tag mismatches\s+1\n\s+Cryocooler: tagged L5, first reached at L6/s;
my $f3 = fresh('f-lint');
edit("$f3/model/interceptor/Interceptor.sysml", 'part motor : RocketMotor;', 'part motor : RocketMotr;');
edit("$f3/model/firecontrol/KillChain.sysml", 'in launchEvent = launch.result;', 'in launchEvent = launchEvent;');
edit("$f3/model/firecontrol/KillChain.sysml", 'action track : Track { in detections = detect.result; }', 'action track : Track { in detections = detect.result }');
($o, $rc) = run(undef, $MODEL, '--root', $f3, 'lint');
like 'fault: lint fails (exit 1) and counts 2 errors, 1 warning', "$rc $o", qr/^1 .*lint: 29 file\(s\), 2 error\(s\), 1 warning\(s\)\nelements=226 errors=2 warnings=1\n\z/s;
like '  ... a syntax error, from the grammar', $o, qr/^\S*model\/firecontrol\/KillChain\.sysml:17:\d+: error: syntax: unexpected '\}'/m;
like '  ... an unresolved type', $o, qr/^\S*model\/interceptor\/Interceptor\.sysml:\d+:\d+: error: unresolved type 'RocketMotr'/m;
like "  ... a binding that silently means the child's own parameter", $o, qr/: warning: in 'guide : GuideInterceptor', 'launchEvent' in the binding of 'launchEvent' means GuideInterceptor's own parameter/;
my $f4 = fresh('f-trace');
edit("$f4/model/program/Enterprise.sysml", "        satisfy sysF01 by sensors;\n", '');
($o, $rc) = run(undef, $MODEL, '--root', $f4, 'trace');
like 'fault: a dropped satisfy shows up in trace', $o, qr/4 not satisfied, 4 not verified.*\n  HAL-SYS-001: not satisfied\n/s;

# ---------------------------------------------------------------- 4. what the status-metrics collector reads
if (eval { require StatusMetrics; 1 }) {
    my $m = StatusMetrics::parse_model(StatusMetrics::tree_files($EX));
    my @linked = grep { $m->{reqs}{$_} ne '' } keys %{ $m->{reqs} };
    my @cross = grep { ($_->{fromZone} // "\0") ne ($_->{toZone} // "\0") } values %{ $m->{ifcs} };
    my @thr = values %{ $m->{threats} };
    check 'collector: elements, requirements with a doorsId, orphans (F), unverified (G), zone crossings (Q), threats (R)',
        join(' ', "A=$m->{elements}", 'C=' . scalar(@linked) . '/' . scalar(keys %{ $m->{reqs} }),
            'F=' . join(',', sort grep { !$m->{sat}{$_} } @linked), 'G=' . join(',', sort grep { !$m->{ver}{$_} } @linked),
            'Q=' . scalar(grep { ($_->{secReq} // '') eq '' } @cross) . '/' . scalar(@cross),
            'R=' . scalar(grep { ($_->{mitigation} // '') eq '' } @thr) . '/' . scalar(@thr)),
        'A=226 C=66/66 F=prdR05,susR05,sysX07 G=fcR08,intR06,sysL06,tstR03 Q=1/5 R=2/7';
    check 'collector: B, segments gated, from CODEOWNERS', scalar(grep { m{^/?model/} } split /\n/, slurp("$EX/CODEOWNERS")), 7;
} else { check 'collector: lib/StatusMetrics.pm not present, skipped', 1, 1 }

print "1..$n\n";
print $bad ? "# $bad of $n failed\n" : "# all $n passed\n";
exit($bad ? 1 : 0);
