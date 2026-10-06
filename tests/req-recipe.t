#!/usr/bin/perl
# perl tests/req-recipe.t -- tools/sysml/req-recipe.pl: the requirement recipe's 18 parts, its findings, the input
# readers (plain text, SysML v2 text, DOORS ReqIF and CSV), the four output formats and the exit codes
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use File::Temp qw(tempdir);
use JSON::PP ();

my ($n, $bad) = (0, 0);
sub check_ { my ($name, $got, $want) = @_; $n++; $got //= '(undef)';
    if ($got eq $want) { print "ok $n - $name\n" }
    else { $bad++; print "not ok $n - $name\n#   got:  $got\n#   want: $want\n" } }
sub like_ { my ($name, $got, $re) = @_; check_($name, (($got // '') =~ $re ? 1 : 0), 1); print "#   in: $got\n" if ($got // '') !~ $re }
sub tspew { my ($p, $t) = @_; open my $fh, '>:raw', $p or die "$p: $!"; print $fh $t; close $fh }
sub run_tool { my $o = qx("$^X" "$FindBin::Bin/../tools/sysml/req-recipe.pl" @_ 2>&1); ($? >> 8, $o) }

my $root = "$FindBin::Bin/..";
my $tw = "$root/examples/tidewater-v1";
my $tmp = tempdir(CLEANUP => 1);
require "$root/tools/sysml/req-recipe.pl";          # the subs, without running main (it checks caller)

# ---- the recipe's own worked example decomposes exactly as the recipe does
my $ex = '(U//FOUO) While in normal flight mode, except during the navigational upset condition, the navigation computer '
       . 'shall send the guidance solution message to the main computer within 30 msec of the 10 Hz clock signal in '
       . 'accordance with the Navigation Computer IRS (D12340000) Section 5.1.4. Note: The 10 Hz clock signal driver is '
       . 'either directly or indirectly sampled from the main CCA clock source. (NC_112358) [MC]';
my $p = parse($ex);
my %want = ('Classification' => 'U//FOUO', 'State' => 'While in normal flight mode', 'Preconditions' => 'in normal flight mode',
    'Specification Target' => 'navigation computer', 'Operative Verb' => 'shall', 'Target Verb' => 'send',
    'Precise Object(s)' => 'the guidance solution message', 'Modifier(s)' => 'to; within',
    'Modification(s)' => 'the main computer; 30 msec of the 10 Hz clock signal', 'Specification' => 'Navigation Computer IRS',
    'Document Number' => 'D12340000', 'Section Number' => '5.1.4', 'Exception(s)' => 'during the navigational upset condition',
    'Informational Statement(s)' => 'The 10 Hz clock signal driver is either directly or indirectly sampled from the main CCA clock source',
    'Requirement ID' => 'NC_112358');
check_("recipe example: $_", $p->{$_}, $want{$_}) for sort keys %want;
check_('recipe example: tags', join(',', @{ $p->{'Requirement Tags'} }), 'MC');
my $g = grade({ text => $ex, file => 'x', line => 1 }, require_class => 1);
check_('recipe example: no findings, nothing missing, score 100', join('/', scalar @{ $g->{findings} }, scalar @{ $g->{missing} }, $g->{score}), '0/0/100');

# ---- findings, one kind at a time
sub findings { my ($t, %o) = @_; my $r = grade({ text => $t, id => $o{id}, file => 'x', line => 1 }, %o); join(' | ', (map { "missing $_" } @{ $r->{missing} }), map { "$_->{sev}: $_->{msg}" } @{ $r->{findings} }) }
like_('weak verb provide (the recipe)', findings('The network shall provide observations.', id => 'A-1'), qr/^major: weak target verb 'provide' \(the recipe\)/);
like_('weak verb support (the kit)', findings('The archive shall support queries.', id => 'A-1'), qr/^major: weak target verb 'support' \(the kit's list\)/);
like_('be able to', findings('Mariners shall be able to read the bulletin.', id => 'A-1'), qr/weak target verb 'be able to' read/);
like_('passive voice', findings('Past observations shall be kept.', id => 'A-1'), qr/^minor: passive voice 'shall be kept'/);
like_('two operative verbs', findings('Each station shall measure wind, and each buoy shall also measure waves every 10 minutes.', id => 'A-1'), qr/major: 2 operative verbs \(shall, shall\)/);
like_('two sentences', findings('The logger shall store 500 records. It shall not lose them.', id => 'A-1'), qr/major: 2 sentences/);
like_('no threshold for a performance verb', findings('The station shall transmit its observations on a fixed schedule.', id => 'A-1'), qr/^minor: 'transmit' with no measurable threshold/);
check_('a threshold satisfies it', findings('The station shall transmit its observations every 10 minutes.', id => 'A-1'), '');
like_('reference without section', findings('The unit shall format each record in accordance with the Observation ICD (TW-ICD-001), except during maintenance mode.', id => 'A-1'), qr/^minor: a reference without a section/);
like_('vague wording', findings('The publisher shall publish the bulletin every 6 hours as appropriate.', id => 'A-1'), qr/vague wording 'as appropriate'/);
like_('unknown tag', findings('The archive shall return each record within 2 s. (A-1) [XX]'), qr/unknown tag 'XX'/);
like_('must is info', findings('The archive must return each record within 2 s.', id => 'A-1'), qr/^info: 'must'/);
like_('should is info', findings('The archive should return each record within 2 s.', id => 'A-1'), qr/^info: 'should' is a design guideline/);
like_('missing ID and target', findings('Shall return each record within 2 s.'), qr/^missing Specification Target \| missing Requirement ID$/);
like_('missing operative verb', findings('The archive returns each record within 2 s.', id => 'A-1'), qr/missing Operative Verb \| missing Target Verb \| missing Precise Object/);
like_('--require classification', findings('The archive shall return each record within 2 s.', id => 'A-1', require_class => 1), qr/^missing Classification$/);
like_('no-comma state before the subject', parse('While in observing mode the station shall send the record every 10 minutes. (A-1)')->{'Specification Target'}, qr/^station$/);
check_('allocated function between subject and verb', join('|', @{ parse('The moored buoy, for the maintenance function, shall present its mast within 6 m. (A-1)') }{'Specification Target', 'Allocated Function'}), 'moored buoy|maintenance');

# ---- the five Tidewater rewrites pass with classification required, strictly
my ($rc, $out) = run_tool('--require', 'classification', '--strict', "$tw/recipe-rewrites.txt");
check_('rewrites: --strict exit 0', $rc, 0);
like_('rewrites: summary', $out, qr/^requirements=5 findings=0 missing=0$/m);

# ---- Tidewater drop 1 as DOORS delivered it (ReqIF and CSV give the same grades)
($rc, $out) = run_tool("$tw/tidewater.reqif");
check_('drop 1 ReqIF: exit 0 without --strict', $rc, 0);
like_('drop 1 ReqIF: summary', $out, qr/^requirements=30 findings=15 missing=0$/m);
like_('TW-STK-001: provide flagged', $out, qr/^TW-STK-001  score 85 .*\n(?:.*\n)*?    major  weak target verb 'provide'/m);
like_('TW-SYS-001: two operative verbs', $out, qr/^TW-SYS-001 (?:.*\n)*?    major  2 operative verbs/m);
like_('TW-SYS-012: be serviceable', $out, qr/^TW-SYS-012 (?:.*\n)*?    major  weak target verb 'be'/m);
($rc) = run_tool('--strict', "$tw/tidewater.reqif");
check_('drop 1 ReqIF: --strict exit 1', $rc, 1);
run_tool('--format', 'csv', '-o', "$tmp/a.csv", "$tw/tidewater.reqif");
run_tool('--format', 'csv', '-o', "$tmp/b.csv", "$tw/tidewater.csv");
my ($csv1, $csv2) = map { open my $fh, '<:raw', $_ or die; local $/; scalar <$fh> } "$tmp/a.csv", "$tmp/b.csv";
s/"[^"]*tidewater\.(?:reqif|csv)"/"F"/g for $csv1, $csv2;
check_('DOORS CSV export grades the same as the ReqIF', $csv2, $csv1);
like_('csv: header', $csv1, qr/^id,score,missing,findings,file,line,text,Classification,State,/);

# ---- the converted model (SysML v2 text): the same 30, and drop 1's TW-SYS-006 drift shows as a finding
my $v2 = "$tmp/v2";
qx("$^X" "$root/bin/xmi2sysml.pl" --out "$v2" "$tw/tidewater.xmi" 2>&1);
($rc, $out) = run_tool($v2);
like_('model: summary', $out, qr/^requirements=30 findings=17 missing=0$/m);
like_('model: TW-SYS-006 (the drifting text) flagged', $out, qr/^TW-SYS-006  score 92 /m);
like_('model: file and line', $out, qr/^TW-STK-001  score 85  \Q$v2\E\/requirements\/Requirements\.sysml:\d+  \(Coastal coverage\)$/m);
tspew("$tmp/one.sysml", "package P {\n    requirement def R1 {\n        doc /* The archive shall return\n         * each record within 2 s. */\n        attribute doorsId = \"P-1\";\n        attribute tags = \"MC, ZZ\";\n        \@Marking { level = Level::U; }\n    }\n}\n");
($rc, $out) = run_tool("$tmp/one.sysml");
like_('multi-line doc, doorsId, tags, marking', $out, qr/^P-1  score 92 .*:2\n  The archive shall return each record within 2 s\.\n    Classification\s+U\n(?:.*\n)*    Requirement Tags\s+MC, ZZ\n    minor  unknown tag 'ZZ'/m);

# ---- JUnit and Code Quality
($rc, $out) = run_tool('--format', 'junit', '-o', "$tmp/r.xml", "$tw/tidewater.reqif");
my $x = do { open my $fh, '<', "$tmp/r.xml" or die; local $/; <$fh> };
like_('junit: counts', $x, qr/<testsuite name="requirement recipe" tests="30" failures="13">/);
like_('junit: -o prints the summary', $out, qr/^requirements=30 findings=15 missing=0$/m);
($rc, $out) = run_tool('--format', 'codequality', '-o', "$tmp/cq.json", "$tw/tidewater.reqif");
my $cq = JSON::PP->new->decode(do { open my $fh, '<', "$tmp/cq.json" or die; local $/; <$fh> });
check_('codequality: one finding per issue', scalar @$cq, 15);
my %fp = map { $_->{fingerprint} => 1 } @$cq;
check_('codequality: fingerprints unique', scalar keys %fp, 15);
check_('codequality: fields', join(',', sort keys %{ $cq->[0] }), 'check_name,description,fingerprint,location,severity');

# ---- usage and errors
($rc, $out) = run_tool();
check_('no input: exit 2', $rc, 2);
($rc, $out) = run_tool('--format', 'pdf', "$tw/tidewater.reqif");
like_('bad --format', "$rc $out", qr/^2 req-recipe: --format is text, csv, junit or codequality, not 'pdf'/);
($rc, $out) = run_tool("$tmp/missing.reqif");
like_('unreadable input', "$rc $out", qr/^2 req-recipe: cannot read .*missing\.reqif: no such file or folder/);
($rc, $out) = run_tool('--require', 'id', "$tw/tidewater.reqif");
like_('bad --require', "$rc $out", qr/^2 req-recipe: --require takes 'classification', not 'id'/);

print "1..$n\n";
print $bad ? "# $bad of $n FAILED\n" : "# all $n passed\n";
exit($bad ? 1 : 0);
