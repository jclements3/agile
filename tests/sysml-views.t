#!/usr/bin/perl
# perl tests/sysml-views.t -- the SysML v2 views toolkit (tools/sysml/views/) and its model.pl wrappers:
#   1. the toolkit's own golden harness (tools/sysml/views/tests/run.sh: every view tool, the gate, the
#      converters tools/sysml/v1v2.pl and doors2v2.pl, git-mode diff) -- needs bash and git (Git for
#      Windows has both); skipped with a message when bash is missing
#   2. model.pl draw tree|trace|ibd|pkg on examples/halberd: well-formed SVG, the model's counts, and the
#      committed docs/img/halberd-*.svg are what sim/halberd-views.pl draws
#   3. model.pl threats / gate / plates / diff on Halberd: exactly the planted gaps, nothing else
#   4. planted security faults on copies: each check trips with the right message
# Core Perl only; writes nothing in the repo (outputs and copies go to a temp dir).
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use File::Temp qw(tempdir);
use File::Find ();
use File::Path qw(make_path);
use File::Copy qw(copy);
use XmlLite;

my ($n, $bad) = (0, 0);
sub check { my ($name, $got, $want) = @_; $n++;
    if ($got eq $want) { print "ok $n - $name\n" }
    else { $bad++; print "not ok $n - $name\n#   got:  $got\n#   want: $want\n" } }
sub like { my ($name, $got, $re) = @_; $n++;
    if ($got =~ $re) { print "ok $n - $name\n" }
    else { $bad++; (my $g = $got) =~ s/^/#   /mg; print "not ok $n - $name\n#   want: $re\n$g\n" } }
sub skip_ { my ($name, $why) = @_; $n++; print "ok $n - $name # skip $why\n" }
sub slurp { my ($p) = @_; open my $fh, '<:raw', $p or return ''; local $/; my $t = <$fh>; close $fh; $t // '' }
sub spew { my ($p, $t) = @_; open my $fh, '>:raw', $p or die "$p: $!\n"; print {$fh} $t; close $fh }

my $root  = "$FindBin::Bin/..";
my $MODEL = "$root/tools/sysml/model.pl";
my $VIEWS = "$root/tools/sysml/views";
my $tmp   = tempdir(CLEANUP => 1);
my $TODAY = '2026-10-05';

sub q_ { my $s = shift; $s =~ s/"/\\"/g; qq("$s") }
sub run {                                   # (cwd or undef, program args...) -> (output with stderr, exit status)
    my ($cwd, @a) = @_;
    my $cmd = join ' ', map { q_($_) } @a;
    $cmd = 'cd ' . q_($cwd) . " && $cmd" if defined $cwd;
    my $out = `$cmd 2>&1`;
    ($out, $? >> 8);
}
sub files_under { my @f; File::Find::find({ no_chdir => 1, wanted => sub { push @f, $_ if -f $_ } }, @_); sort @f }
sub fresh {                                 # a copy of the example as a project of its own
    my $dst = "$tmp/" . shift;
    for my $f (files_under("$root/examples/halberd")) {
        (my $rel = $f) =~ s/^\Q$root\/examples\/halberd\E//;
        next if $rel =~ m{/tags\z};
        make_path($dst . ($rel =~ s{/[^/]*\z}{}r));
        copy($f, "$dst$rel") or die "copy $f: $!\n";
    }
    $dst;
}
sub edit { my ($f, $from, $to) = @_; my $t = slurp($f); my $c = $t =~ s/\Q$from\E/$to/; die "edit $f: '$from' not found\n" unless $c; spew($f, $t) }
sub wellformed { my $f = shift; my $x = eval { XmlLite::parse_file($f) }; $x ? ($x->{l} eq 'svg' ? 'ok' : "root <$x->{l}>") : ($@ =~ s/\n.*//sr) }
sub has_prog { my $p = shift; my ($o, $rc) = run(undef, $p, '--version'); $rc == 0 }

# ---------------------------------------------------------------- 1. the toolkit's golden harness
if (!has_prog('bash')) { skip_('golden harness (tools/sysml/views/tests/run.sh)', 'bash not found: run it from Git Bash') }
elsif (!has_prog('git')) { skip_('golden harness (tools/sysml/views/tests/run.sh)', 'git not found') }
else {
    my ($o, $rc) = run(undef, 'bash', "$VIEWS/tests/run.sh");
    check 'golden harness: every view tool, the gate and both converters match tools/sysml/views/tests/golden.txt',
        "$rc " . ((split /\n/, $o)[-1] // ''), '0 tests: golden transcript matches';
}

# ---------------------------------------------------------------- 2. model.pl draw on Halberd (from the kit root, as sim/halberd-views.pl runs it)
my %want = (
    tree  => qr/^tree-svg: 29 file\(s\), 65 part def\(s\), 1 tree\(s\), 78 part node\(s\), 0 warning\(s\) -> /m,
    trace => qr/^trace-svg: 29 file\(s\), 66 leaf requirement\(s\), 7 with gaps, 0 warning\(s\) -> /m,
    ibd   => qr/^29 file\(s\): 1 error\(s\), 0 warning\(s\), 2 diagram\(s\), 10 connection\(s\), 8 boundary crossing\(s\), 4 on the attack surface -> /m,
    pkg   => qr/^29 file\(s\): 0 error\(s\), 0 warning\(s\), 36 package\(s\), 84 dependencies, 0 write-down edge\(s\), 0 cycle\(s\) -> /m,
);
my %rcw = (tree => 0, trace => 0, ibd => 1, pkg => 0);    # ibd exits 1: the planted uncovered crossing
for my $k (qw(tree trace ibd pkg)) {
    my ($o, $rc) = run($root, $^X, $MODEL, '--root', 'examples/halberd', 'draw', $k, '-o', "$tmp/$k.svg");
    like "draw $k: exit $rcw{$k}, and the model's counts", "$rc\n$o", qr/^$rcw{$k}\n/;
    like "  ... $k summary", $o, $want{$k};
    check "  ... $k.svg is well-formed XML with an <svg> root", wellformed("$tmp/$k.svg"), 'ok';
}
like 'draw: the default title names the project', slurp("$tmp/tree.svg"), qr/>Halberd: part decomposition</;
{
    my ($o, $rc) = run(undef, $^X, "$root/sim/halberd-views.pl", '--out', $tmp);
    check 'sim/halberd-views.pl runs', $rc, 0;
    check 'docs/img/halberd-{tree,trace,ibd,pkg}.svg are current (perl sim/halberd-views.pl)',
        join(' ', grep { slurp("$tmp/halberd-$_.svg") ne slurp("$root/docs/img/halberd-$_.svg") } qw(tree trace ibd pkg)) || 'all equal', 'all equal';
    check '  ... and each is well-formed', join(' ', map { wellformed("$tmp/halberd-$_.svg") } qw(tree trace ibd pkg)), 'ok ok ok ok';
    check '  ... the trace view is drawn for print (--mono: status as shapes, not the colored default)', (slurp("$tmp/halberd-trace.svg") ne slurp("$tmp/trace.svg") ? 1 : 0), 1;
}
my ($o, $rc) = run($root, $^X, $MODEL, '--root', 'examples/halberd', 'draw', 'tree', '--root', 'InterceptorSegment', '-o', "$tmp/t2.svg");
like "a tool's own --root after the command goes to the tool (model.pl keeps the first)", "$rc $o", qr/^0 tree-svg: 29 file\(s\), 65 part def\(s\), 1 tree\(s\), 31 part node\(s\)/;
($o, $rc) = run($root, $^X, $MODEL, '--root', 'examples/halberd', 'draw');
like 'draw with no kind: usage, exit 2', "$rc $o", qr/^2 usage: perl \S+ draw tree\|trace\|ibd\|pkg/;
($o, $rc) = run("$root/examples/halberd/model/test", $^X, $MODEL, 'draw', 'pkg', '-o', "$tmp/p.svg", '--hide', 'SecMeta');
like 'draw finds the project upward from model/<segment>/, options passed on', "$rc $o", qr/^0 29 file\(s\): 0 error\(s\).* 36 package\(s\)/;

# ---------------------------------------------------------------- 3. threats, gate, plates, diff on Halberd: the planted gaps only
($o, $rc) = run($root, $^X, $MODEL, '--root', 'examples/halberd', 'threats', '--today', $TODAY);
like 'threats: 7 threats, 5 mitigated, the 2 planted open threats are errors', "$rc $o",
    qr/^1 .*\n29 file\(s\): 2 error\(s\), 0 warning\(s\), 7 threat\(s\), 5 mitigation\(s\), 0 risk acceptance\(s\) in force\n\z/s;
check '  ... the open ones', join(' ', $o =~ /error: threat '(\w+)' is not mitigated/g), 'counterfeitPart insiderMisuse';
check '  ... every threat has a STRIDE category and a CAPEC id', scalar(() = $o =~ /^\w+\s+(?:Spoofing|Tampering|Repudiation|Information disclosure|Denial of service|Elevation of privilege)\s+CAPEC-\d+\s/mg), 7;

($o, $rc) = run($root, $^X, $MODEL, '--root', 'examples/halberd', 'gate', '--today', $TODAY);
check 'gate: FAIL on exactly the planted gaps (7 trace, 1 crossing, 2 threats), nothing else',
    "$rc " . (split /\n/, $o)[-1], '1 check: 5 check(s) run, 10 error(s), 0 warning(s) -> FAIL';
my %per; my $cur;
for (split /\n/, $o) { $cur = $1 if /^== (\w+)/; $per{$cur}++ if /: error: / }
check '  ... errors per check', join(' ', map { "$_=" . ($per{$_} // 0) } qw(text trace markings zones threats)), 'text=0 trace=7 markings=0 zones=1 threats=2';
check '  ... the trace gaps: 3 orphans, 4 unverified', join(' ', sort map { /requirement (\w+) (not \w+)/ ? "$1:$2" : () } grep { /sysml-trace|not (?:satisfied|verified)/ } split /\n/, $o),
    'fcR08:not verified intR06:not verified prdR05:not satisfied susR05:not satisfied sysL06:not verified sysX07:not satisfied tstR03:not verified';
like '  ... the uncovered crossing is the adjacent-unit link', $o, qr/Context\.sysml:\d+: error: interface 'ifcAdjacentUnit' in 'HalberdContext' crosses trusted->untrusted with no satisfied security requirement/;
my ($so, $src) = run($root, $^X, "$VIEWS/sysml-check.pl", '--today', $TODAY, 'examples/halberd/model');
check 'sysml-check.pl standalone (binder scripts found in views/binder/) says the same', "$src " . (split /\n/, $so)[-1], "$rc " . (split /\n/, $o)[-1];

($o, $rc) = run($root, $^X, $MODEL, '--root', 'examples/halberd', 'plates', '-o', "$tmp/plates", '--date', $TODAY, '--source', 'test');
like 'plates: no views in Halberd, so one plate per top tree, wired def, trace and packages', "$rc $o", qr/^0 .*plates: 0 view\(s\), 5 plate\(s\) on 5 sheet\(s\), 0 warning\(s\)/s;
my @pl = glob("$tmp/plates/*.svg");
check '  ... 5 well-formed sheets and plates.html', join(' ', (map { wellformed($_) } @pl), (-s "$tmp/plates/plates.html" ? 'html' : 'no-html')), 'ok ok ok ok ok html';

my $p = fresh('diff');
edit("$p/model/program/Enterprise.sysml", "        satisfy sysF01 by sensors;\n", '');
edit("$p/model/engineering/Threats.sysml", 'mitigation = "secR04"; stride = "Tampering"; capec = "CAPEC-511";', 'mitigation = "secR04"; stride = "Tampering";');
($o, $rc) = run($root, $^X, $MODEL, '--root', $p, 'diff', '--today', $TODAY, '-o', "$tmp/d", "$root/examples/halberd/model");
like 'diff OLD_DIR: the new side is this model; a new gap and a new error finding exit 1', "$rc $o", qr/^1 .*sysml-diff: \d+ change line\(s\), 1 new gap\(s\), 1 new error finding\(s\)/s;
like '  ... the change list names both', slurp("$tmp/d-changes.txt"), qr/sysF01.*\n(?:.*\n)*.*new finding \(threats\): threat 'tamperedSoftwareBuild': no CAPEC id/;
check '  ... all four pictures written', join(' ', map { wellformed("$tmp/d-$_.svg") } qw(tree trace packages ibd)), 'ok ok ok ok';
if (has_prog('git')) {
    my $g = fresh('git');
    my $gq = q_($g);
    my $git = "git -c user.email=t\@t -c user.name=t -c core.autocrlf=false";
    `cd $gq && git init -q && $git add -A && $git commit -qm v1 2>&1`;
    edit("$g/model/production/LaunchSegment.sysml", "        satisfy prdR04 by launcher;\n", '');
    ($o, $rc) = run($g, $^X, $MODEL, 'diff', '--today', $TODAY, '-o', "$tmp/g", '--git', 'HEAD');
    like 'diff --git HEAD: the working tree against the last commit (model/ by default)', "$rc $o", qr/^1 .*sysml-diff: \d+ change line\(s\), 1 new gap\(s\), 0 new error finding\(s\)/s;
    like '  ... locations as REV:path:line', slurp("$tmp/g-changes.txt"), qr/prdR04/;
} else { skip_('diff --git', 'git not found') }

# ---------------------------------------------------------------- 4. planted security faults
my $f = fresh('f-sec');
edit("$f/model/test/TestSegment.sysml", "    \@Marking { level = Level::U; }\n", '');                                  # a root package with no marking
edit("$f/model/engineering/Interfaces.sysml", '@Marking { level = Level::U; }', '@Marking { level = Level::CUI; }');    # U packages now import a CUI one
edit("$f/model/engineering/Context.sysml", 'attribute fromZone = "dmz"; attribute toZone = "trusted"; attribute secReq = "secR05";',
                                           'attribute fromZone = "trusted"; attribute toZone = "trusted"; attribute secReq = "secR05";');
edit("$f/model/engineering/Context.sysml", 'attribute toZone = "untrusted"; attribute secReq = "secR01";', 'attribute toZone = "untrusted"; attribute secReq = "sysX04";');
edit("$f/model/engineering/Threats.sysml", 'mitigation = "secR02"; stride = "Information disclosure"', 'mitigation = "secR03"; stride = "Disclosure"');
($o, $rc) = run($root, $^X, $MODEL, '--root', $f, 'gate', '--today', $TODAY);
like 'fault: a root package with no @Marking', $o, qr/TestSegment\.sysml:\d+: error: root package 'TestAndTraining' has no \@Marking/;
like 'fault: write-down (a U package imports a CUI one)', $o, qr/: error: U package '\w+' imports CUI package 'InterfaceDefinitions'/;
like 'fault: declared zones that disagree with the @TrustZone ones', $o, qr/: warning: interface 'ifcMaintenanceData' declares fromZone\/toZone trusted->trusted but its ends sit in dmz->trusted/;
like "fault: a crossing whose secReq is not a security requirement", $o, qr/: error: interface 'ifcHigherCommand' in 'HalberdContext' crosses trusted->untrusted with no satisfied security requirement \(its secReq 'sysX04' is not a \@SecurityRequirement\)/;
like 'fault: a STRIDE category that is not one of the six', $o, qr/: error: threat 'interceptedUplink': STRIDE category 'Disclosure' is not one of the six/;
like "fault: a threat's mitigation attribute and its \@Mitigates disagree", $o, qr/: warning: threat 'interceptedUplink': mitigation = "secR03" but no \@Mitigates on 'secR03' names it/;
check '  ... the gate fails (exit 1)', $rc, 1;

# ---------------------------------------------------------------- the live viewer: svg2tk.pl and bin/sysml-view.tcl
for my $k (qw(tree trace ibd pkg)) {
    my $svg = "$root/docs/img/halberd-$k.svg";
    my ($tk, $trc) = run(undef, $^X, "$VIEWS/svg2tk.pl", $svg);
    my $s = slurp($svg);
    my ($nr, $nt) = (scalar(() = $s =~ /<rect\b/g), scalar(() = $s =~ /<text\b/g));
    check "svg2tk.pl $k: exit 0, size line, texts = <text>s, rects = <rect>s less the background",
        join(' ', $trc, ($tk =~ /^size \d/ ? 'size' : 'no-size'), scalar(() = $tk =~ /^text /mg), scalar(() = $tk =~ /^rect /mg)),
        join(' ', 0, 'size', $nt, $nr - 1);
}
spew("$tmp/not.svg", "<html></html>\n");
($o, $rc) = run(undef, $^X, "$VIEWS/svg2tk.pl", "$tmp/not.svg");
like 'svg2tk.pl on a file with no <svg>: exit 2', "$rc $o", qr/^2 svg2tk: \S+: no <svg> element/;
{
    my @wish = has_prog('xvfb-run') ? ('xvfb-run', '-a', 'wish') : $ENV{DISPLAY} ? ('wish') : ();   # Git for Windows: no DISPLAY, so skipped
    my ($wo) = run(undef, 'sh', '-c', 'command -v wish');
    if (!@wish || $wo !~ /\S/) { skip_('sysml-view.tcl --export-ps', 'needs wish and a display (or xvfb-run); no windows are opened in tests') }
    else {
        ($o, $rc) = run($root, @wish, 'bin/sysml-view.tcl', 'examples/halberd', '--view', 'ibd', '--export-ps', "$tmp/ibd.ps");
        like 'sysml-view.tcl --export-ps: the IBD drawn headless to PostScript', "$rc $o", qr/^0 .*sysml-view: \d+ item\(s\), \d+ element\(s\) -> /s;
        like '  ... a PostScript file', substr(slurp("$tmp/ibd.ps"), 0, 4), qr/^%!PS/;
    }
}

# ---------------------------------------------------------------- the converters run standalone (their goldens are in the harness)
($o, $rc) = run(undef, $^X, "$root/tools/sysml/v1v2.pl");
like 'tools/sysml/v1v2.pl with no command: usage, exit 2', "$rc $o", qr/^2 /;
($o, $rc) = run(undef, $^X, "$root/tools/sysml/doors2v2.pl");
like 'tools/sysml/doors2v2.pl with no export: usage, exit 2', "$rc $o", qr/^2 usage: perl doors2v2\.pl -o DIR/;

print "1..$n\n";
print $bad ? "# $bad of $n failed\n" : "# all $n passed\n";
exit($bad ? 1 : 0);
