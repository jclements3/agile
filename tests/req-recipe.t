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

($rc, $out) = run_tool('--baseline', "$tw/tidewater.reqif");
like_('--baseline without --links', "$rc $out", qr/^2 req-recipe: --baseline and --top go with --links/);
($rc, $out) = run_tool('--links', '--top', '"["', "$tw/tidewater.reqif");
like_('bad --top', "$rc $out", qr/^2 req-recipe: --top '\[' is not a valid regular expression/);

# ---- --links: the relationship attributes, elements 19-23, from the whole input set
mkdir "$tmp/m"; mkdir "$tmp/m/needs"; mkdir "$tmp/m/sys";
tspew("$tmp/m/needs/Needs.sysml", <<'E');
package 'Stakeholder Needs' {
    requirement N_1 { doc /* Forecasters shall receive each observation within 15 minutes of its measurement. */ attribute doorsId = "N-1";
        attribute rationale = "The bulletin cycle direction from the forecast office."; attribute verificationMethod = "Demonstration"; }
    requirement N_2 { doc /* Mariners shall read the latest bulletin from a public service. */ attribute doorsId = "N-2";
        attribute rationale = "Public access is the program's purpose."; attribute verificationMethod = "Inspection"; }
}
E
tspew("$tmp/m/sys/Sys.sysml", <<'E');
package 'System Requirements' {
    requirement S_1 { doc /* The data center shall ingest each observation within 60 seconds of its arrival. */ attribute doorsId = "S-1";
        attribute rationale = "60 s allocated from the 15 minute latency budget TB-LAT-01."; attribute verificationMethod = "Test"; }
    requirement S_2 { doc /* The station shall send its observations every 10 minutes. */ attribute doorsId = "S-2";
        attribute rationale = "Engineering judgement."; attribute verificationMethod = "Test"; }
    requirement S_3 { doc /* The station shall log its operating mode. */ attribute doorsId = "S-3"; attribute verificationMethod = "Guess"; }
    requirement S_4 { doc /* The station shall stop its transmitter while a crew is aboard. [SC] */ attribute doorsId = "S-4"; attribute tags = "SC";
        attribute rationale = "Crew safety."; attribute verificationMethod = "Inspection"; attribute derivedFrom = "TRADE-007"; }
    #derivation connection { end #original ::> 'Stakeholder Needs'::N_1; end #derive ::> S_1; end #derive ::> S_2; }
    satisfy S_1 by IngestService;
    verification def TestIngest { objective { verify S_1; verify requirement S_2; } }
}
E
($rc, $out) = run_tool('--links', "$tmp/m");
check_('links: exit 0 (reports only)', $rc, 0);
like_('links: the counts line comes before the summary', $out,
    qr/^links: orphan=1 childless=1 unjustified=1 unverified=4 unsatisfied=3 unmitigated=1\nrequirements=6 findings=\d+ missing=\d+\n\z/m);
my %blk = map { /^(\S+)\s+score/ ? ($1 => $_) : () } split /\n\n/, $out;
like_('links: parent from a #derivation end (qualified name)', $blk{'S-1'}, qr/^    Parent Trace\s+N_1$/m);
like_('links: rationale, method, case and satisfier', $blk{'S-1'}, qr/Rationale\s+60 s allocated.*\n\s+Verification Method\s+Test\n\s+Verification Case\s+TestIngest\n\s+Satisfied By\s+IngestService/);
unlike_ok('links: a budget id justifies the threshold', $blk{'S-1'}, qr/unjustified/);
like_('links: a number with a sourceless rationale is unjustified', $blk{'S-2'}, qr/minor\s+unjustified threshold/);
like_('links: open satisfier is info before the baseline', $blk{'S-2'}, qr/info\s+nothing satisfies it yet/);
like_('links: orphan and missing rationale', $blk{'S-3'}, qr/missing: Parent Trace, Rationale/);
like_('links: unknown method', $blk{'S-3'}, qr/major\s+verification method 'Guess': use Test, Analysis, Demonstration or Inspection/);
like_('links: derived from a decision', $blk{'S-4'}, qr/Parent Trace\s+derived from TRADE-007[\s\S]*info\s+derived requirement \(from TRADE-007\)/);
like_('links: SC without a hazard', $blk{'S-4'}, qr/major\s+unmitigated safety tag \(SC\)/);
like_('links: needs are top level by package', $blk{'N-1'}, qr/Parent Trace\s+\(top level\)/);
like_('links: a top-level need with no children is childless', $blk{'N-2'}, qr/minor\s+childless/);
($rc, $out) = run_tool('--links', '--baseline', "$tmp/m");
%blk = map { /^(\S+)\s+score/ ? ($1 => $_) : () } split /\n\n/, $out;
like_('links --baseline: open case and satisfier are missing', $blk{'S-3'}, qr/missing: Parent Trace, Rationale, Verification Case, Satisfied By/);
($rc, $out) = run_tool('--links', '--top', '^S-3$', "$tmp/m");
%blk = map { /^(\S+)\s+score/ ? ($1 => $_) : () } split /\n\n/, $out;
like_('links --top: replaces the package default', $blk{'S-3'} . "\n" . $blk{'N-1'}, qr/S-3[\s\S]*Parent Trace\s+\(top level\)[\s\S]*N-1[\s\S]*missing: Parent Trace/);
($rc, $out) = run_tool("$tmp/m");
unlike_ok('without --links: no link parts, no counts line', $out, qr/Parent Trace|^links:/m);
($rc, $out) = run_tool('--links', '--format', 'csv', "$tmp/m");
like_('links csv: the five columns', (split /\r\n/, $out)[0], qr/,Requirement Tags,Parent Trace,Rationale,Verification Method,Verification Case,Satisfied By$/);
tspew("$tmp/t.txt", "The station shall send its observations every 10 minutes. (TW_S_9)\n\nParent: TW_N_1. Rationale: 10 minutes allocated from the latency budget TB-LAT-01. Verification: Test by VC-12. Satisfied by: DataLogger (the station logger).\n\nThe station shall log its mode. Note: verified by inspection of the log. (TW_S_10)\n");
($rc, $out) = run_tool('--links', "$tmp/t.txt");
%blk = map { /^(\S+)\s+score/ ? ($1 => $_) : () } split /\n\n/, $out;
like_('links text: fields after the statement', $blk{'TW_S_9'}, qr/Parent Trace\s+TW_N_1\n\s+Rationale\s+10 minutes allocated from the latency budget TB-LAT-01\n\s+Verification Method\s+Test\n\s+Verification Case\s+VC-12\n\s+Satisfied By\s+DataLogger/);
like_('links text: two requirements, not three', $out, qr/requirements=2 /);
like_('links text: a Note: carrying the verification', $blk{'TW_S_10'}, qr/minor\s+the Note: carries a rationale or the verification approach/);

sub unlike_ok { my ($name, $got, $re) = @_; check_($name, (($got // '') =~ $re ? 0 : 1), 1) }

print "1..$n\n";
print $bad ? "# $bad of $n FAILED\n" : "# all $n passed\n";
exit($bad ? 1 : 0);
