#!/usr/bin/perl
# perl tests/ci-reports.t -- tools/gitlab/ci-reports.pl: the model checks' output as JUnit XML, Code Quality JSON and
# metrics, the report files a GitLab pipeline attaches to a merge request
use strict;
use warnings;
use FindBin;
use File::Temp qw(tempdir);
use File::Path qw(make_path);

my ($n, $bad) = (0, 0);
sub check_ { my ($name, $got, $want) = @_; $n++;
    if ($got eq $want) { print "ok $n - $name\n" }
    else { $bad++; print "not ok $n - $name\n#   got:  $got\n#   want: $want\n" } }
sub has { my ($name, $text, @res) = @_; for my $re (@res) { check_("$name: $re", ($text =~ $re ? 1 : 0), 1) } }
sub slurp { my ($p) = @_; open my $fh, '<', $p or return ''; local $/; my $t = <$fh>; close $fh; $t }
sub spew { my ($p, $t) = @_; open my $fh, '>', $p or die "$p: $!"; binmode $fh; print $fh $t; close $fh }

my $root = "$FindBin::Bin/..";
my $tool = "$root/tools/gitlab/ci-reports.pl";
my $dir  = tempdir(CLEANUP => 1);
sub run { my $out = qx("$^X" "$tool" @_ 2>&1); return ($? >> 8, $out) }

# a well-formed JSON array of flat objects (the Code Quality subset this tool writes) -> count, or -1 if malformed
sub json_count {
    my ($t) = @_;
    return -1 unless $t =~ /\A\[\s*(.*?)\s*\]\s*\z/s;
    my $body = $1; return 0 if $body eq '';
    my @objs = split /\},\n\s*\{/, $body;
    for (@objs) { return -1 unless /"description": "/ && /"fingerprint": "[0-9a-f]{32}"/ && /"severity": "(info|minor|major|critical|blocker)"/ && /"lines": \{"begin": \d+\}/ }
    return scalar @objs;
}
sub xml_balanced { my ($t) = @_; my $o = () = $t =~ /<testcase\b[^>]*[^\/]>/g; my $c = () = $t =~ /<\/testcase>/g; my $s = () = $t =~ /<testcase\b[^>]*\/>/g; ($o == $c ? 1 : 0) . ":" . ($o + $s) }

# ---- grammar: sysml.pl check output, every file checked becomes a test case
spew("$dir/g.txt", "model/a/A.sysml:6:1: error: unexpected end of file; expected '#', ':'\nsysml: 3 file(s), 1 error(s)\n");
my ($rc, $out) = run('grammar', '--junit', "$dir/g.xml", '--codequality', "$dir/g.json", "$dir/g.txt", 'model/a/A.sysml', 'model/b/B.sysml', 'model/c/C.sysml');
check_('grammar: exit 0 (the job keeps the checker\'s status)', $rc, 0);
has('grammar summary', $out, qr/3 check\(s\), 1 failed, 1 finding\(s\); grammar_files=3 grammar_errors=1/);
my $x = slurp("$dir/g.xml");
check_('grammar junit: 3 test cases, balanced', xml_balanced($x), '1:3');
has('grammar junit', $x, qr/<testsuites name="sysml-grammar" tests="3" failures="1">/, qr/<testcase classname="grammar" name="model\/a\/A.sysml" file="model\/a\/A.sysml">\n\s*<failure message="1 error\(s\), first at line 6: unexpected end of file; expected '#'/);
my $j = slurp("$dir/g.json");
check_('grammar codequality: 1 finding', json_count($j), 1);
has('grammar codequality', $j, qr/"severity": "critical"/, qr/"path": "model\/a\/A.sysml", "lines": \{"begin": 6\}/);

# ---- lint: errors and warnings, the 0/0 gate, metrics
spew("$dir/l.txt", join("\n",
    "model/s/S.sysml:3:14: error: unresolved type 'Missing'",
    "model/s/S.sysml:9:5: warning: unused import 'Types::*'",
    "model/t/T.sysml:2:1: warning: unused import 'Types::*'",
    'lint: 4 file(s), 1 error(s), 2 warning(s)', 'elements=140 errors=1 warnings=2', ''));
($rc, $out) = run('lint', '--junit', "$dir/l.xml", '--codequality', "$dir/l.json", '--metrics', "$dir/l.m", "$dir/l.txt");
check_('lint metrics', slurp("$dir/l.m"), "model_elements 140\nlint_errors 1\nlint_warnings 2\n");
$j = slurp("$dir/l.json");
check_('lint codequality: 3 findings', json_count($j), 3);
has('lint severities', $j, qr/"description": "unresolved type 'Missing'", "check_name": "sysml-lint", "fingerprint": "[0-9a-f]{32}", "severity": "major"/, qr/"severity": "minor"/);
my %fp; $fp{$_}++ for $j =~ /"fingerprint": "([0-9a-f]{32})"/g;
check_('fingerprints are unique (same message in two files)', scalar(keys %fp), 3);
$x = slurp("$dir/l.xml");
has('lint junit', $x, qr/name="lint 0\/0">\n\s*<failure message="errors=1 warnings=2"/, qr/name="model\/t\/T.sysml" file="model\/t\/T.sysml">\n\s*<system-out>/);
# fingerprint stability: the same finding on another line keeps its fingerprint
spew("$dir/l2.txt", "model/s/S.sysml:30:14: error: unresolved type 'Missing'\nelements=140 errors=1 warnings=0\n");
run('lint', '--codequality', "$dir/l2.json", "$dir/l2.txt");
my ($f1) = $j =~ /unresolved type 'Missing'", "check_name": "sysml-lint", "fingerprint": "([0-9a-f]{32})"/;
my ($f2) = slurp("$dir/l2.json") =~ /"fingerprint": "([0-9a-f]{32})"/;
check_('a finding keeps its fingerprint when its line moves', $f1 // 'none', $f2 // 'other');
($rc, $out) = run('lint', "$dir/g.txt");
check_('lint without the elements= line is an error', $rc, 2);
has('lint error message', $out, qr/no 'elements=N errors=E warnings=W' line/);

# ---- outline: model.pl check output
spew("$dir/o.txt", "\n== Level tags ==\n\@L tag mismatches         1\n  Cell: tagged L5, first reached at L6\n\n== Outline (2..9 children per parent) ==\nviolations                2\n   12  directory entries  (model/)\n    1  package Analysis: members  (model/analysis/Analysis.sysml)\n");
($rc, $out) = run('outline', '--junit', "$dir/o.xml", '--codequality', "$dir/o.json", '--metrics', "$dir/o.m", "$dir/o.txt");
check_('outline metrics', slurp("$dir/o.m"), "level_tag_mismatches 1\noutline_violations 2\n");
check_('outline codequality: 3 findings', json_count(slurp("$dir/o.json")), 3);
has('outline findings', slurp("$dir/o.json"), qr/"description": "Cell: tagged L5, first reached at L6"/, qr/"path": "model\/analysis\/Analysis.sysml"/, qr/"description": "directory entries: 12 \(outside 2..9\)", "check_name": "outline", "fingerprint": "[0-9a-f]{32}", "severity": "minor", "location": \{"path": "model"/);
has('outline junit', slurp("$dir/o.xml"), qr/name="level tags">\n\s*<failure message="1 mismatch\(es\)"/, qr/name="2..9 children per parent">\n\s*<failure message="2 violation\(s\)"/);

# ---- todo: a model directory, and grep output
make_path("$dir/model/stations", "$dir/model/network");
spew("$dir/model/stations/Stations.sysml", "package Stations {\n    part def A {\n        // TODO stereotype P:L3Station on this element (xmi:id _22_1_abc) not converted\n    }\n    // TODO uml:StateMachine 'M' (xmi:id _22_1_def): no SysML v2 mapping in this converter\n}\n");
spew("$dir/model/network/Network.sysml", "package Network {\n    // TODO uml:Include (xmi:id _22_1_123): no SysML v2 mapping in this converter\n}\n");
spew("$dir/model/network/notes.txt", "// TODO not a model file\n");
($rc, $out) = run('todo', '--metrics', "$dir/t.m", '--codequality', "$dir/t.json", "$dir/model");
check_('todo metrics from a directory', slurp("$dir/t.m"), "todo_lines 3\ntodo_lines_network 1\ntodo_lines_stations 2\n");
$j = slurp("$dir/t.json");
check_('todo codequality: 3 info findings', json_count($j) . ':' . (() = $j =~ /"severity": "info"/g), '3:3');
has('todo finding drops the xmi:id from the message', $j, qr/"description": "TODO stereotype P:L3Station on this element not converted"/);
spew("$dir/todo.txt", "model/stations/Stations.sysml:3:        // TODO stereotype P:L3Station on this element (xmi:id _22_1_abc) not converted\nmodel/network/Network.sysml:2:    // TODO uml:Include (xmi:id _22_1_123): no SysML v2 mapping\n");
run('todo', '--metrics', "$dir/t2.m", "$dir/todo.txt");
check_('todo metrics from grep -rn output', slurp("$dir/t2.m"), "todo_lines 2\ntodo_lines_network 1\ntodo_lines_stations 1\n");

# ---- trace: reqif2sysml --report --model output
spew("$dir/tr.txt", join("\n",
    'trace against model (12 .sysml files)',
    'C requirements linked (doorsId in the model)     29 of 30',
    'F orphan requirements (nothing satisfies)               2',
    'G unverified requirements (no verify)                   3',
    'I trace completeness (satisfied and verified)        66.7%',
    'text differs from DOORS                                 1',
    'not in the model: TW-SYS-016',
    'orphans: TW-SYS-012 TW-SYS-016',
    'unverified: TW-SYS-011 TW-SYS-016 TW-SEG-002',
    'drift: TW-SYS-006', ''));
($rc, $out) = run('trace', '--junit', "$dir/tr.xml", '--metrics', "$dir/tr.m", "$dir/tr.txt");
check_('trace metrics', slurp("$dir/tr.m"), "trace_linked 29\ntrace_total 30\ntrace_orphans 2\ntrace_unverified 3\ntrace_completeness_pct 66.7\ntrace_drift 1\ntrace_not_in_model 1\n");
$x = slurp("$dir/tr.xml");
check_('trace junit: one case per gap plus the linked count', xml_balanced($x), '1:8');
has('trace junit', $x, qr/<testcase classname="trace drift" name="TW-SYS-006">\n\s*<failure message="TW-SYS-006: the text differs from DOORS"/, qr/name="requirements linked">\n\s*<failure message="29 of 30 linked"/);

# ---- usage and unreadable input
($rc, $out) = run('frobnicate', 'x');
check_('unknown mode exits 2', $rc, 2);
($rc, $out) = run('lint', "$dir/does-not-exist.txt");
check_('unreadable input exits 2', $rc, 2);
has('unreadable input message', $out, qr/ci-reports: cannot read .*does-not-exist.txt/);

# ---- the real checkers' output, when the kit's SysML tools are present
my $sysml = "$root/tools/sysml/sysml.pl";
if (-f $sysml) {
    spew("$dir/model/network/Network.sysml", "package Network {\n    part def A { part b : B; }\n    part def B;\n");
    my $log = qx("$^X" "$sysml" check "$dir/model/network/Network.sysml" 2>&1);
    spew("$dir/real.txt", $log);
    ($rc, $out) = run('grammar', '--codequality', "$dir/real.json", "$dir/real.txt", "$dir/model/network/Network.sysml");
    check_('real sysml.pl check output: one finding', json_count(slurp("$dir/real.json")), 1);
} else { print "ok ", ++$n, " - real sysml.pl check output # skip tools/sysml not in this checkout\n" }

# ---- pages-index.pl: the Pages front page from what the pages job gathered
{
    my $pi = "$root/tools/gitlab/pages-index.pl";
    my $pub = "$dir/public"; make_path("$pub/views", "$pub/docs");
    spew("$pub/todo-burndown.csv", "date,todo_lines\n2026-10-06,52\n2026-10-20,40\n2026-11-03,12\n");
    spew("$pub/trace.txt", slurp("$dir/tr.txt"));
    spew("$pub/views/tree.svg", qq(<svg xmlns="http://www.w3.org/2000/svg"/>));
    spew("$pub/docs/Nouns.md", "# Nouns\n\n<b> & co\n");
    my $o = qx("$^X" "$pi" --title "Tidewater model" --commit abc123 "$pub" 2>&1);
    check_('pages-index runs', $? >> 8, 0);
    my $h = slurp("$pub/index.html");
    has('pages index', $h, qr/<title>Tidewater model<\/title>/, qr/Now <b>12<\/b>, from 52 at the start/, qr/<td>Requirements linked to the model<\/td><td>29 of 30<\/td>/,
        qr/<img src="views\/tree.svg"/, qr/<a href="docs\/Nouns.html">Nouns.md<\/a>/, qr/commit <code>abc123<\/code>/);
    check_('pages index: nothing external, no scripts', ($h =~ /<script|src="http|href="http/ ? 1 : 0), 0);
    has('generated doc page is escaped', slurp("$pub/docs/Nouns.html"), qr/&lt;b&gt; &amp; co/);
}

print "1..$n\n";
print $bad ? "# $bad of $n FAILED\n" : "# all $n passed\n";
exit($bad ? 1 : 0);
