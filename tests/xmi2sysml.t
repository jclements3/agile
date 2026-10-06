#!/usr/bin/perl
# perl tests/xmi2sysml.t            (REGEN=1 perl tests/xmi2sysml.t rewrites the goldens under tests/fixtures/xmi2sysml/expected/)
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use File::Temp qw(tempdir);
use XmlLite;
use SysmlText qw(name ident str doc requirement check is_keyword);
use Xmi;

my ($n, $bad) = (0, 0);
sub check_ { my ($name, $got, $want) = @_; $n++;
    if ($got eq $want) { print "ok $n - $name\n" }
    else { $bad++; print "not ok $n - $name\n#   got:  $got\n#   want: $want\n" } }
sub has { my ($name, $text, @res) = @_; for my $re (@res) { check_("$name: $re", ($text =~ $re ? 1 : 0), 1) } }
sub skip_ { my ($name, $why) = @_; $n++; print "ok $n - $name # skip $why\n" }
sub slurp { my ($p) = @_; open my $fh, '<', $p or return undef; binmode $fh; local $/; my $t = <$fh>; close $fh; return $t }
sub spew { my ($p, $t) = @_; (my $d = $p) =~ s{/[^/]*$}{}; mkdir $d unless -d $d; open my $fh, '>', $p or die "$p: $!"; binmode $fh; print $fh $t; close $fh }

my $root = "$FindBin::Bin/..";
my $fx = "$FindBin::Bin/fixtures/xmi2sysml";
my $dir = tempdir(CLEANUP => 1);
my $regen = $ENV{REGEN};

# ---- XmlLite: the reader
my $x = XmlLite::parse_string(qq{\xEF\xBB\xBF<?xml version="1.0"?>\r\n<!DOCTYPE r [<!ENTITY co "ACME &amp; Co">]>\r\n<r xmlns="urn:d" xmlns:u="urn:u" a="1&#10;2\r\n3 &lt;x&gt;"><!-- skip --><?pi skip?>\r\n  <u:b c='q>"'>t &co; &#x263A;<![CDATA[<raw> & ]]>\r\nz</u:b><e/></r>});
check_('root element, default namespace', "$x->{l}|$x->{u}", 'r|urn:d');
check_('attribute normalisation: CRLF and tab -> space, &#10; kept', $x->{a}{a}, "1\n2 3 <x>");
my ($b) = XmlLite::kids($x, 'b');
check_('prefixed child: local name, prefix, URI', "$b->{l}|$b->{p}|$b->{u}", 'b|u|urn:u');
check_('quoted > and " inside an attribute', $b->{a}{c}, 'q>"');
check_('internal entity, char ref, CDATA, CRLF folded', XmlLite::text($b), "t ACME & Co \xE2\x98\xBA<raw> & \nz");
check_('empty element', scalar(XmlLite::kids($x, 'e')), 1);
check_('line numbers', $b->{line}, 5);
my @errs;
for my $bad_xml ('<a><b></a>', "<a>\n<b>", '<a x="1></a>', '<a><!-- x </a>') {
    eval { XmlLite::parse_string($bad_xml) }; (my $e = $@) =~ s/\n//; push @errs, $e;
}
check_('malformed input is an error with a line number', join(' | ', @errs),
    'input:1: end tag </a> does not match <b> | input:2: missing end tag for <b> | input:1: unterminated start tag | input:1: unterminated comment');
my $iso = XmlLite::parse_string(qq{<?xml version="1.0" encoding="ISO-8859-1"?><a n="caf\xE9">\xB5m</a>});
check_('single-byte encoding recoded to UTF-8', "$iso->{a}{n}|" . XmlLite::text($iso), "caf\xC3\xA9|\xC2\xB5m");
my $u16 = "\xFF\xFE" . join('', map { "$_\0" } split //, '<a b="1">x</a>');
check_('UTF-16LE with BOM', XmlLite::text(XmlLite::parse_string($u16)), 'x');

# ---- SysmlText
check_('names: basic, keyword, spaces, quote', join(' ', map { name($_) } 'Drone', 'return', 'serial number', "it's"), q{Drone 'return' 'serial number' 'it\'s'});
check_('ident for requirement ids', join(' ', map { ident($_) } 'CD-101', 'CD-101.1', '12', 'part'), 'CD_101 CD_101_1 R_12 part_');
check_('keywords include flow, typed, guard', join('', map { is_keyword($_) } qw(flow typed guard Drone)), '1110');
check_('string literal escapes', str(qq{say "hi" \\ now\nok}), q{"say \"hi\" \\\\ now ok"});
check_('doc: short on one line, */ defused', join('|', doc('a */ b', '')), 'doc /* a * / b */');
check_('requirement, usage style (one line, what status-metrics counts)',
    join('|', requirement({ name => 'R1', doorsId => 'X-1', text => "two\nlines", vm => 'Test' }, 'usage', '  ')),
    q{  requirement R1 { doc /* two lines */ attribute doorsId = "X-1"; attribute verificationMethod = "Test"; }});
my $p = check({ 'a.sysml' => "package P {\n  part def A :> Missing;\n  part def B { attribute y : ScalarValues::Real; port p : ~B; }\n  satisfy R by A;\n" });
check_('self-check finds unbalanced braces and undeclared names', join(' | ', @$p),
    "a.sysml:1: '{' never closed | a.sysml:2: 'Missing' is not declared in these files or the standard library | a.sysml:4: 'R' is not declared in these files or the standard library");

# ---- the Cameo-style fixture: golden output, both requirement styles
my %runs;
for my $style (qw(def usage)) {
    my $m = Xmi::load("$fx/courier.xmi");
    my $out = Xmi::convert($m, req_style => $style);
    $runs{$style} = $out;
    for my $f (sort keys %{ $out->{files} }) {
        my $g = "$fx/expected/$style/$f";
        if ($regen) { (my $d = $g) =~ s{/[^/]*$}{}; require File::Path; File::Path::make_path($d); spew($g, $out->{files}{$f}) }
        my $want = slurp($g);
        check_("golden $style/$f", $out->{files}{$f}, defined $want ? $want : '(missing golden)');
    }
    check_("$style: self-check clean", scalar @{ $out->{problems} }, 0);
}
my $out = $runs{def};
check_('files: one per top-level package, loose elements in the model package',
    join(' ', sort keys %{ $out->{files} }), 'behavior/Behavior.sysml courier/Courier.sysml requirements/Requirements.sysml structure/Structure.sysml');
my $rep = Xmi::report_text($out);
spew("$fx/expected/report.txt", $rep) if $regen;
check_('report golden', $rep, slurp("$fx/expected/report.txt") // '');
my $r = $out->{report};
check_('counts: total in, metric-A scope, ported', "$r->{total} $r->{scope} $r->{scope_done}", '94 37 37');
my %st; for my $t (values %{ $r->{in} }) { $st{$_} += $t->{$_} || 0 for qw(mapped folded todo) }
check_('counts: mapped / folded / todo', "$st{mapped} $st{folded} $st{todo}", '63 21 10');
check_('unmapped list (each is a TODO line in the output)', join(' ', map { "$_->{type}:$_->{id}" } @{ $r->{unmapped} }),
    'Operation:_op_arm Constraint:_rule_mass StateMachine:_sm_fc InstanceSpecification:_unit_kg DecisionNode:_n_dec ControlFlow:_e3');
my $all = join '', map { $out->{files}{$_} } sort keys %{ $out->{files} };
check_('every unmapped element appears as a TODO with its xmi:id', scalar(grep { $all =~ /TODO uml:$_->{type}\b[^\n]*xmi:id \Q$_->{id}\E\)/ } @{ $r->{unmapped} }), scalar @{ $r->{unmapped} });
has 'mapping', $all,
    qr/^    part def Drone \{$/m, qr/^        part motors : Motor\[4\];$/m, qr/^        ref part operator : Operator;$/m,
    qr/^        attribute mode : FlightMode = FlightMode::cruise;$/m, qr/^        attribute 'serial number' : ScalarValues::String;$/m,
    qr/^        connection power connect battery\.pwrOut to fc\.pwrIn;$/m, qr/^        bind mass = airframe\.mass;$/m,
    qr/^        port pwrIn : ~PowerIF;$/m, qr/^    port def PowerIF \{\n        out attribute current : Current;\n        in item command : Command;/m,
    qr/^        port rpmCmd \{ in attribute flowValue : ScalarValues::Real; \}$/m, qr/^    part def QuadDrone :> Drone;$/m,
    qr/^        attribute def Mass :> ScalarValues::Real \{$/m, qr/^            enum 'return';$/m,
    qr/^    satisfy CD_101 by Drone;$/m, qr/^    satisfy CD_102 by Drone::airframe;$/m, qr/^            verify CD_101_1;$/m,
    qr/^        end #original ::> CD_101;\n        end #derive ::> CD_210;$/m, qr/^    private import RequirementDerivation::\*;$/m,
    qr/^    dependency from Battery to CD_210; \/\/ trace$/m, qr/^    allocate DeliverParcel to Drone;$/m,
    qr/^        first start then 'take off';$/m, qr/^        first drop then done;$/m,
    qr/TODO stereotype Safety:Hazardous on this element \(xmi:id _s26\)/, qr/constraint: OCL: self\.mass <= 2\.5/,
    qr/^        attribute risk = "High";$/m, qr/^             \* Flies at most 40 \xC2\xB0C ambient\.$/m;

# ---- robustness: CRLF + BOM, and a 7-byte read buffer, give byte-identical output
my $src = slurp("$fx/courier.xmi");
(my $crlf = $src) =~ s/\n/\r\n/g;
spew("$dir/courier.xmi", "\xEF\xBB\xBF$crlf");
{
    local $XmlLite::CHUNK = 7;
    my $o2 = Xmi::convert(Xmi::load("$dir/courier.xmi"));
    check_('CRLF + BOM + tiny read buffer: same files', join('', map { $o2->{files}{$_} } sort keys %{ $o2->{files} }), $all);
}
my $again = Xmi::convert(Xmi::load("$fx/courier.xmi"));
check_('deterministic', join('', map { $again->{files}{$_} } sort keys %{ $again->{files} }), $all);

# ---- the simple XMI shape the status-metrics sim writes (no namespaces declared, no packages, no names)
spew("$dir/legacy.xmi", "<xmi:XMI>\n" . join('', map { sprintf qq(  <packagedElement xmi:type="uml:%s" xmi:id="v1_%04d"/>\n), (qw(Class Port Property Connector Activity))[ $_ % 5 ], $_ } 0 .. 9)
    . qq(  <ownedComment xmi:type="uml:Comment" xmi:id="c_0000"/>\n</xmi:XMI>\n));
my $so = Xmi::convert(Xmi::load("$dir/legacy.xmi"));
check_('sim-shape XMI: one package named after the file', join(' ', sort keys %{ $so->{files} }), 'legacy/legacy.sysml');
check_('sim-shape XMI: all 10 in scope ported, nothing TODO', "$so->{report}{scope_done}/$so->{report}{scope} " . scalar @{ $so->{report}{unmapped} }, '10/10 0');
has 'sim-shape XMI output', $so->{files}{'legacy/legacy.sysml'}, qr/^    part def v1_0000;\n    port v1_0001;\n    attribute v1_0002;\n    connection v1_0003;\n    action def v1_0004;$/m;

# ---- the CLI: --out writes the goldens, --report prints the report, exit 0
my $cmd = qq("$^X" "$root/bin/xmi2sysml.pl" --req-style def --out "$dir/model" "$fx/courier.xmi" 2>&1);
my $msg = qx($cmd);
check_('cli exit status', $? >> 8, 0);
has 'cli summary', $msg, qr/94 elements in, 37 of 37 in scope ported, 6 TODO, 4 file\(s\), self-check ok/;
check_('cli wrote the golden files', join(' ', map { (slurp("$dir/model/$_") // '') eq (slurp("$fx/expected/def/$_") // '-') ? 1 : 0 } sort keys %{ $out->{files} }), '1 1 1 1');
my $cr = qx("$^X" "$root/bin/xmi2sysml.pl" --req-style def --report "$fx/courier.xmi");
check_('cli --report', $cr, $rep);
qx("$^X" "$root/bin/xmi2sysml.pl" "$fx/courier.xmi" 2>&1);
check_('cli with nothing to do exits 2', $? >> 8, 2);
qx("$^X" "$root/bin/xmi2sysml.pl" --layout "{pkg}.sysml" --out "$dir/flat" "$fx/courier.xmi" 2>&1);
check_('cli --layout', join(' ', map { -f "$dir/flat/$_.sysml" ? 1 : 0 } qw(Behavior Courier Requirements Structure)), '1 1 1 1');

# ---- the SysML v2 grammar checker, when the repo has it
my $chk = "$root/tools/sysml/sysml.pl";
if (-f $chk) {
    for my $style (qw(def usage)) {
        my $d = "$dir/chk-$style";
        qx("$^X" "$root/bin/xmi2sysml.pl" --req-style $style --out "$d" "$fx/courier.xmi" 2>&1);
        my @f = map { "$d/$_" } sort keys %{ $runs{$style}{files} };
        my $o = qx("$^X" "$chk" check @{[ join ' ', map { qq("$_") } @f ]} 2>&1);
        check_("tools/sysml/sysml.pl check passes ($style)", $? >> 8, 0);
        print map { "#   $_\n" } split /\n/, $o if $?;
    }
    mkdir "$dir/legacy-out"; spew("$dir/legacy-out/legacy.sysml", $so->{files}{'legacy/legacy.sysml'});
    qx("$^X" "$chk" check "$dir/legacy-out/legacy.sysml" 2>&1);
    check_('tools/sysml/sysml.pl check passes (sim-shape XMI)', $? >> 8, 0);
} else { skip_('tools/sysml/sysml.pl check', 'tools/sysml/sysml.pl not in this checkout') for 1 .. 3 }

# ---- Tidewater (examples/tidewater-v1): the committed files are what sim/tidewater-v1.pl writes, and the port finds the planted gaps
{
    my $tw = "$root/examples/tidewater-v1"; my $g = "$dir/tw-gen";
    qx("$^X" "$root/sim/tidewater-v1.pl" "$g" 2>&1);
    check_("tidewater: $_ is current (rerun perl sim/tidewater-v1.pl)", (slurp("$g/$_") // '') eq (slurp("$tw/$_") // '-') ? 1 : 0, 1) for qw(tidewater.xmi tidewater.reqif tidewater.csv CHANGES.csv MANIFEST.txt);
    my $o = qx("$^X" "$root/bin/xmi2sysml.pl" --report --out "$dir/tw-v2" "$tw/tidewater.xmi" 2>&1);
    has('tidewater: xmi2sysml', $o, qr/206 of 206 ported, 0 remaining/, qr/unmapped \(TODO in the output\): 12\n/, qr/stereotypes not converted: L1Network 1, L2Segment 3, L3Station 10, L4Subsystem 8, L5Assembly 13, L6Component 1, Procured 3/, qr/self-check: ok/);
    for my $in (['reqif'], ['csv', '--csv']) {
        my ($ext, @flag) = @$in;
        my $t = qx("$^X" "$root/bin/reqif2sysml.pl" @flag --report --model "$dir/tw-v2" "$tw/tidewater.$ext" 2>&1);
        has("tidewater: $ext trace", $t, qr/linked \(doorsId in the model\)\s+29 of 30/, qr/not in the model: TW-SYS-016\n/, qr/orphans: TW-SYS-012 TW-SYS-016\n/,
            qr/unverified: TW-STK-001 TW-STK-002 TW-STK-003 TW-STK-004 TW-STK-005 TW-STK-006 TW-SYS-011 TW-SYS-016 TW-SEG-002\n/, qr/in the model but not in this export\s+1/,
            qr/text differs from DOORS\s+1\n/, qr/drift: TW-SYS-006\n/);
    }

    # the prime's drops: every drop converts cleanly (grammar too, when the checker is here), ids are stable across drops,
    # and --delta tells what the converter carries from what needs rework by hand
    my $chk = -f "$root/tools/sysml/sysml.pl" ? '--check' : ();
    my %xmi;
    for my $k (1 .. 7) {
        my $gd = "$dir/drop$k";
        my $g = qx("$^X" "$root/sim/tidewater-v1.pl" --drop $k "$gd" 2>&1);
        check_("drop $k: generator runs", $? >> 8, 0);
        my $c = qx("$^X" "$root/bin/xmi2sysml.pl" --out "$dir/drop$k-v2" $chk "$gd/tidewater.xmi" 2>&1);
        check_("drop $k: converts cleanly" . ($chk ? ' (grammar checked)' : ''), $? >> 8, 0);
        print map { "#   $_\n" } split /\n/, $c if $?;
        $xmi{$k} = "$gd/tidewater.xmi";
        has("drop $k: MANIFEST", slurp("$gd/MANIFEST.txt") // '', qr/^Tidewater system model -- prime drop v1\.\d \(drop $k\)$/m, qr/^CDRL: A003 System Model$/m, qr/^  [0-9a-f]{64}  tidewater\.xmi$/m);
    }
    check_('drop 1 regenerates examples/tidewater-v1 byte for byte', (slurp("$dir/drop1/tidewater.xmi") // '') eq (slurp("$tw/tidewater.xmi") // '-') ? 1 : 0, 1);
    my $ids = sub { my %h = map { $_ => 1 } (slurp($_[0]) // '') =~ /xmi:id="([^"]+)"/g; \%h };
    my ($i1, $i2, $i7) = ($ids->($xmi{1}), $ids->($xmi{2}), $ids->($xmi{7}));
    check_('ids are stable: every drop-1 id is still in drop 2', scalar(grep { !$i2->{$_} } keys %$i1), 0);
    check_('ids are stable: drop 7 lost only TW-SEG-009 (6 ids) and the Legacy Import package (26 ids)', scalar(grep { !$i7->{$_} } keys %$i1), 32);
    # the spider web the generator measures: the clutter is there in drop 1 and the prime removes it in drops 3 and 6
    my $sw = sub { scalar qx("$^X" "$root/sim/tidewater-v1.pl" --drop $_[0] "$dir/sw$_[0]" 2>&1) };
    has('drop 1 spider web', $sw->(1), qr/^spider web: 560 elements, 47 diagrams, 99 relationships over 40 blocks \(max 14 on ObservingStation, mean 1\.2\)$/m,
        qr/^  package dependency cycles: 2  \[DataCenter <-> Stations\]  \[Network <-> Operations\]$/m,
        qr/^  unused: 4 \(Battery_old, Copy of SensorSuite, TBD Component, Requirement from slide 14\)$/m,
        qr/^  duplicates: 2  \[Battery = Battery_old\]  \[Copy of SensorSuite = SensorSuite\]$/m);
    has('drop 3: Copy of SensorSuite gone', $sw->(3), qr/^  unused: 3 \(Battery_old, TBD Component, Requirement from slide 14\)$/m, qr/^  duplicates: 1  \[Battery = Battery_old\]$/m);
    has('drop 6: Legacy Import gone, the cycles stay', $sw->(6), qr/^  unused: 0$/m, qr/^  duplicates: 0$/m, qr/^  package dependency cycles: 2 /m, qr/^spider web: 573 elements, 45 diagrams/m);
    my $d12 = qx("$^X" "$root/bin/xmi2sysml.pl" --delta "$xmi{1}" "$xmi{2}" 2>&1);
    has('delta 1->2', $d12, qr/^xmi delta: tidewater\.xmi \(v1\.0\) -> tidewater\.xmi \(v1\.1\)$/m, qr/^elements 560 -> 567: 7 added, 0 removed, 1 changed$/m,
        qr/^manual \(the converter does not carry these; rework the v2 text by hand\): 0$/m,
        qr/^  \+ uml:Class +Stations::Hygrometer\n      carried: stations\/Stations\.sysml$/m,
        qr/^  \+ uml:Abstraction +Requirements::\(Satisfy ObservingStation -> Humidity\)$/m,
        qr/^  ~ uml:Class +Requirements::System Requirements::Functions::Bulletin -- stereotype functionalRequirement: Text changed$/m);
    check_('delta 1->2: no manual rework list', ($d12 =~ /manual rework list/ ? 1 : 0), 0);
    my $d23 = qx("$^X" "$root/bin/xmi2sysml.pl" --delta "$xmi{2}" "$xmi{3}" 2>&1);
    has('delta 2->3: the Storm state is manual', $d23, qr/^elements 567 -> 570: 12 added, 9 removed, 0 changed$/m,
        qr/^  \+ uml:State +Stations::MooredBuoy::BuoyModes::Storm\n      manual: inside uml:StateMachine 'BuoyModes', which the converter leaves as a TODO in stations\/Stations\.sysml/m,
        qr/^  \[ \] added uml:State Stations::MooredBuoy::BuoyModes::Storm \(xmi:id _22_1_7f3a0c1_[0-9a-f]{12}\)$/m,
        qr/^  - uml:Class +Requirements::Segment Requirements::Stations::Lowerable mast\n      carried: requirements\/Requirements\.sysml$/m,
        qr/^  \+ uml:Property +Stations::PowerSystem::fuse\n      carried:/m);
    my $d45 = qx("$^X" "$root/bin/xmi2sysml.pl" --delta "$xmi{4}" "$xmi{5}" 2>&1);
    has('delta 4->5: a rename keeps its id; the constraint expression is manual', $d45, qr/^elements 582 -> 582: 0 added, 0 removed, 2 changed$/m,
        qr/^  ~ uml:Activity +Behavior::IssueBulletin -- renamed 'PublishBulletin' -> 'IssueBulletin'\n      carried: behavior\/Behavior\.sysml$/m,
        qr/^  ~ uml:OpaqueExpression +Analysis::EnergyBalance::balance::\(OpaqueExpression\) -- properties changed\n      manual: inside uml:Constraint 'balance'/m);
    my $same = qx("$^X" "$root/bin/xmi2sysml.pl" --delta "$xmi{6}" "$xmi{6}" 2>&1);
    has('delta of a drop with itself is empty', $same, qr/^elements 573 -> 573: 0 added, 0 removed, 0 changed$/m);
    qx("$^X" "$root/bin/xmi2sysml.pl" --delta "$xmi{6}" 2>&1);
    check_('--delta needs two files (exit 2)', $? >> 8, 2);

    # --map: every v1 element and the v2 line it went to, deterministic
    my $X = sub { my $o = scalar qx("$^X" "$root/bin/xmi2sysml.pl" @_ 2>&1); return ($o, $? >> 8) };
    my ($mo, $mrc) = $X->('--out', "$dir/gov1", '--map', "$dir/map1.csv", $xmi{1});
    check_('--map with a conversion exits 0', $mrc, 0);
    my $map1 = slurp("$dir/map1.csv") // '';
    $X->('--map', "$dir/map1b.csv", $xmi{1});
    check_('--map is deterministic (and works without --out)', (slurp("$dir/map1b.csv") // '') eq $map1 ? 1 : 0, 1);
    my @mrows = split /\n/, $map1;
    check_('--map header', $mrows[0], 'xmi_id,v1_type,v1_qualified_name,v2_qualified_name,v2_kind,file,line');
    check_('--map has a row for every element but the model root and the profile application', scalar(@mrows) - 1, 557);
    has('--map rows', $map1, qr/^_22_1_7f3a0c1_[0-9a-f]{12},uml:Class,Stations::SensorSuite,Stations::SensorSuite,part def,stations\/Stations\.sysml,\d+$/m,
        qr/^_22_1_7f3a0c1_[0-9a-f]{12},uml:State,Stations::MooredBuoy::BuoyModes::Observing,Stations::MooredBuoy::\(TODO StateMachine\),todo,stations\/Stations\.sysml,\d+$/m,
        qr/^_22_1_7f3a0c1_[0-9a-f]{12},uml:Abstraction,Allocations::\(Allocate PublishBulletin -> BulletinPublisher\),Allocations,allocate,allocations\/Allocations\.sysml,\d+$/m,
        qr/^_22_1_7f3a0c1_[0-9a-f]{12},uml:Class,Legacy Import::Copy of SensorSuite,'Legacy Import'::'Copy of SensorSuite',part def,legacy-import\/Legacy_Import\.sysml,\d+$/m);
    {   # the map's line numbers point at the right lines of the written files
        my ($bad, $n) = (0, 0);
        for my $r (@mrows[1 .. $#mrows]) {
            my @c = split /,/, $r; next unless $c[4] =~ /^(part def|todo)$/; $n++;
            my @L = split /\n/, slurp("$dir/gov1/$c[5]") // '';
            my $line = $L[ $c[6] - 1 ] // '';
            $bad++ unless $c[4] eq 'todo' ? $line =~ m{// TODO} : $line =~ /part def/;
        }
        check_("--map line numbers land on the definition or TODO line ($n checked)", $bad, 0);
    }

    # --impact: the government's model is the old drop's conversion plus its own edits
    my $edit = sub { my ($f, $re, $to) = @_; my $x = slurp($f); $x =~ s/$re/$to/m or die "test edit: no match in $f\n"; spew($f, $x) };
    my ($i12) = $X->('--delta', $xmi{1}, $xmi{2}, '--impact', "$dir/gov1", '--map', "$dir/map1.csv", '--impact-csv', "$dir/imp12.csv");
    has('impact 1->2 (hygrometer)', $i12, qr/^impact on \S+gov1 \(13 \.sysml files\)$/m,
        qr/^\+ uml:Property Stations::SensorSuite::hygrometer\n    v2: Stations::SensorSuite::hygrometer \(part, stations\/Stations\.sysml:\d+\)\n    interface: Stations::ObservingStation::toLogger/m,
        qr/^\+ uml:Abstraction Requirements::\(Satisfy ObservingStation -> Humidity\)\n(?:    v2: .*\n)+    requirements: TW-SYS-017\n    verification cases: TestStationObservations$/m,
        qr/^requirements touched +3  TW-STK-001, TW-SYS-006, TW-SYS-017$/m,
        qr/^verification cases touched +2  DemonstratePublication, TestStationObservations$/m,
        qr/^interfaces touched +1  Stations::ObservingStation::toLogger$/m, qr/^hand edits to redo +0$/m);
    my $c12 = slurp("$dir/imp12.csv") // '';
    has('--impact-csv', $c12, qr/^change,xmi_id,v1_type,v1_qualified_name,category,v2_name,file,line,detail,cr_id$/m,
        qr/^added,_22_1_7f3a0c1_[0-9a-f]{12},uml:Abstraction,Verification::\(Verify TestStationObservations -> Humidity\),verification,TestStationObservations,verification\/Verification\.sysml,\d+,,NWM-CR-0013$/m,
        qr/^added,\S+,uml:Class,Requirements::System Requirements::Functions::Humidity,requirement,TW-SYS-017,requirements\/Requirements\.sysml,\d+,,NWM-CR-0013$/m);
    $X->('--out', "$dir/gov2", $xmi{2});
    $edit->("$dir/gov2/stations/Stations.sysml", qr{^\s*// TODO uml:StateMachine 'BuoyModes'.*\n}m,
        "        exhibit state buoyModes {\n            entry; then observing;\n            state observing;\n            state degraded;\n            transition observing then degraded;\n        }\n");
    my ($i23) = $X->('--delta', $xmi{2}, $xmi{3}, '--impact', "$dir/gov2");
    has('impact 2->3 (Storm: the hand-closed BuoyModes TODO)', $i23,
        qr/^\+ uml:State Stations::MooredBuoy::BuoyModes::Storm\n    v2: Stations::MooredBuoy::\(TODO StateMachine\) \(todo, stations\/Stations\.sysml:\d+\)\n    hand edit: TODO for uml:StateMachine 'BuoyModes' closed by hand in MooredBuoy/m,
        qr/^requirements touched +4  TW-SEG-009, TW-SEG-010, TW-SYS-011, TW-SYS-012$/m,
        qr/^hand edits to redo +1\n  \[ \] TODO for uml:StateMachine 'BuoyModes' closed by hand in MooredBuoy \(stations\/Stations\.sysml:\d+\)$/m);
    {   # on the drop branch after the vendor merge the model already holds drop 3 (plus the government's edits):
        # one warning instead of false hand edits
        $X->('--out', "$dir/dropbranch", $xmi{3});
        $edit->("$dir/dropbranch/stations/Stations.sysml", qr{^\s*// TODO uml:StateMachine 'BuoyModes'.*\n}m, "        exhibit state buoyModes { state observing; }\n");
        my ($o) = $X->('--delta', $xmi{2}, $xmi{3}, '--impact', "$dir/dropbranch");
        has('impact on a model that already contains the new drop', $o,
            qr/^warning: the model already contains v1\.2: run --impact against develop before the drop is merged \(\d+ changed definition\(s\) match the new drop, 0 the old one\); hand edits are not reported$/m,
            qr/^hand edits to redo +0$/m);
        check_('already merged: the warning once, no hand edit lines', join(' ', scalar(() = $o =~ /^warning:/mg), scalar(() = $o =~ /hand edit:/g)), '1 0');
        my ($n) = $X->('--delta', $xmi{4}, $xmi{5}, '--impact', "$dir/drop5-v2");
        has('impact on the plain conversion of the new drop', $n, qr/^warning: the model already contains v1\.4: /m);
    }
    my ($i23u) = $X->('--delta', $xmi{2}, $xmi{3}, '--impact', "$dir/drop2-v2");
    has('impact 2->3 on an unedited model: nothing to redo', $i23u, qr/^hand edits to redo +0$/m);
    $X->('--out', "$dir/gov4", $xmi{4});
    $edit->("$dir/gov4/behavior/Behavior.sysml", qr{^\s*// TODO uml:ForkNode.*\n}m, "        fork afterCheck;\n");
    my ($i45) = $X->('--delta', $xmi{4}, $xmi{5}, '--impact', "$dir/gov4");
    has('impact 4->5 (rename: the allocations and the government\'s ObserveCoast edit)', $i45,
        qr/^~ uml:Activity Behavior::IssueBulletin -- renamed 'PublishBulletin' -> 'IssueBulletin'\n    v2: Behavior::PublishBulletin \(action def, /m,
        qr/^    allocation: allocate PublishBulletin to BulletinPublisher \(allocations\/Allocations\.sysml:\d+\)$/m,
        qr/^    referenced by: Behavior::ObserveCoast::publish : PublishBulletin \(behavior\/Behavior\.sysml:\d+\)$/m,
        qr/^allocations touched +1  allocate PublishBulletin to BulletinPublisher$/m,
        qr/^hand edits to redo +1\n  \[ \] ObserveCoast refers to it and was edited by the government since v1\.3 \(behavior\/Behavior\.sysml:\d+\)$/m);
    # the prime's change requests: CHANGES.csv beside each drop; the impact report is grouped by CR
    has('drop 2 CHANGES.csv', slurp("$dir/drop2/CHANGES.csv") // '', qr/^cr_id,title,rationale,kind,xmi_ids,requirements\r$/m,
        qr/^NWM-CR-0012,Add hygrometer to the sensor suite,Humidity is needed to forecast fog at the shore stations\.,add,(?:_22_1_7f3a0c1_[0-9a-f]{12} ?){3},TW-SYS-017\r$/m);
    has('drop 5 MANIFEST: the rename comes without a rationale', slurp("$dir/drop5/MANIFEST.txt") // '',
        qr/^Change requests:\n  NWM-CR-0024  change  Add a reserve term to EnergyBalance -- Battery reserve was left out of the energy balance\.\n  NWM-CR-0025  rename  Rename PublishBulletin to IssueBulletin -- \(no rationale given\)$/m);
    has('drop 6 MANIFEST: the clutter removal answers the DRs', slurp("$dir/drop6/MANIFEST.txt") // '', qr/NWM-CR-0028  delete  Delete the Legacy Import package -- Answers government DR-5/);
    has('impact 1->2 grouped by CR', $i12, qr/^== NWM-CR-0012 add: Add hygrometer to the sensor suite\n   rationale: Humidity is needed to forecast fog at the shore stations\.\n   requirements: TW-SYS-017\n\n\+ uml:Property Stations::SensorSuite::hygrometer$/m,
        qr/^== NWM-CR-0014 fix: Align TW-SYS-006 text with DOORS\n/m, qr/^change requests +3  NWM-CR-0012 NWM-CR-0013 NWM-CR-0014$/m, qr/^changes no CR names +0$/m);
    has('impact 4->5 grouped by CR', $i45, qr/^== NWM-CR-0025 rename: Rename PublishBulletin to IssueBulletin\n   rationale: \(none given -- ask the prime for clarification\)\n\n~ uml:Activity Behavior::IssueBulletin/m,
        qr/^without a rationale +1  NWM-CR-0025$/m);
    for my $k (1 .. 6) {                         # every change of every delta belongs to one CR
        my ($o) = $X->('--delta', $xmi{$k}, $xmi{ $k + 1 }, '--impact', "$dir/drop$k-v2");
        check_("delta $k->" . ($k + 1) . ': every change has a CR', ($o =~ /^changes no CR names +(\d+)$/m)[0] // 'missing', 0);
    }
    {   # without CHANGES.csv the report is not grouped; a bad one is an error
        mkdir "$dir/nocr"; spew("$dir/nocr/tidewater.xmi", slurp($xmi{2}));
        my ($o) = $X->('--delta', $xmi{1}, "$dir/nocr/tidewater.xmi", '--impact', "$dir/gov1");
        check_('no CHANGES.csv: no CR groups', ($o =~ /^== |^change requests/m ? 1 : 0), 0);
        spew("$dir/nocr/CHANGES.csv", "id,title\n");
        my ($e, $rc) = $X->('--delta', $xmi{1}, "$dir/nocr/tidewater.xmi", '--impact', "$dir/gov1");
        check_('a CHANGES.csv with the wrong header', "$rc " . ($e =~ /^xmi2sysml: \S*CHANGES\.csv: not a CHANGES\.csv \(expected the header cr_id,title,rationale,kind,xmi_ids,requirements\)$/m ? 1 : 0), '2 1');
    }
    my ($e1, $r1) = $X->('--impact', "$dir/gov1", $xmi{1});
    check_('--impact without --delta is a usage error', "$r1 $e1", "2 xmi2sysml: --impact needs --delta OLD.xmi NEW.xmi\n");
    my ($e2, $r2) = $X->('--delta', $xmi{1}, $xmi{2}, '--impact', "$dir/nope");
    check_('--impact on a missing directory', "$r2 " . ($e2 =~ /: not a directory$/m ? 1 : 0), '2 1');
    spew("$dir/bad.csv", "x\n");
    my ($e3, $r3) = $X->('--delta', $xmi{1}, $xmi{2}, '--impact', "$dir/gov1", '--map', "$dir/bad.csv");
    check_('--map that is not a map', "$r3 " . ($e3 =~ /not an xmi2sysml map/ ? 1 : 0), '2 1');
    my ($e4, $r4) = $X->('--delta', '--impact-csv', "$dir/x.csv", $xmi{1}, $xmi{2});
    check_('--impact-csv needs --impact', "$r4 $e4", "2 xmi2sysml: --impact-csv needs --impact MODEL_DIR\n");

    # --layout-map: the layered repository, the same paths for every drop
    my $lm = "$tw/layout.map";
    my ($lr) = $X->('--report', '--layout-map', $lm, $xmi{1});
    has('layout map: the layers', $lr, qr/^files: analysis\/Analysis\.sysml legacy\/Legacy_Import\.sysml library\/Interfaces\.sysml library\/Tidewater\.sysml library\/Types\.sysml logical\/Behavior\.sysml physical\/allocation\/Allocations\.sysml physical\/datacenter\/DataCenter\.sysml physical\/network\/Network\.sysml physical\/operations\/Operations\.sysml physical\/stations\/Stations\.sysml requirements\/model\/Requirements\.sysml verification\/Verification\.sysml$/m);
    check_('layout map: no report line when every package is listed', ($lr =~ /^layout map:/m ? 1 : 0), 0);
    my %fs;
    for my $k (1 .. 7) { my ($r) = $X->('--report', '--layout-map', $lm, $xmi{$k}); my ($f) = $r =~ /^files: (.*)$/m; push @{ $fs{$f // ''} }, $k }
    check_('layout map: the same paths in every drop (drops 6-7 only lose legacy/)', join(' | ', sort map { join ',', @{ $fs{$_} } } keys %fs), '1,2,3,4,5 | 6,7');
    my ($lo, $lrc) = $X->('--out', "$dir/lay1", $chk, '--layout-map', $lm, '--map', "$dir/laymap.csv", $xmi{1});
    check_('layout map: converts cleanly' . ($chk ? ' (grammar checked)' : ''), $lrc, 0);
    has('layout map: --map reports the mapped paths', slurp("$dir/laymap.csv") // '', qr/,Stations::SensorSuite,part def,physical\/stations\/Stations\.sysml,\d+$/m);
    has('layout map: --delta reports the mapped paths', ($X->('--delta', '--layout-map', $lm, $xmi{2}, $xmi{3}))[0],
        qr/^      manual: inside uml:StateMachine 'BuoyModes', which the converter leaves as a TODO in physical\/stations\/Stations\.sysml;/m,
        qr/^      carried: legacy\/Legacy_Import\.sysml$/m);
    $X->('--out', "$dir/layg2", '--layout-map', $lm, $xmi{2});
    $edit->("$dir/layg2/physical/stations/Stations.sysml", qr{^\s*// TODO uml:StateMachine 'BuoyModes'.*\n}m, "        exhibit state buoyModes { state observing; }\n");
    has('layout map: --impact reports the mapped paths', ($X->('--delta', '--layout-map', $lm, $xmi{2}, $xmi{3}, '--impact', "$dir/layg2"))[0],
        qr/^  \[ \] TODO for uml:StateMachine 'BuoyModes' closed by hand in MooredBuoy \(physical\/stations\/Stations\.sysml:\d+\)$/m);
    {   # every path in the delta and impact report honours the layout map, even with a --map written without it
        my ($o) = $X->('--delta', $xmi{2}, $xmi{3}, '--impact', "$dir/layg2", '--layout-map', $lm, '--map', "$dir/map1.csv");
        my %p = map { $_ => 1 } $o =~ m{\b([a-z][\w-]*(?:/[\w-]+)*/[\w.-]+\.sysml)\b}g;
        my @layers = qw(library/ requirements/ logical/ physical/ analysis/ verification/ legacy/ unsorted/);
        my @off = grep { my $f = $_; !grep { index($f, $_) == 0 } @layers } sort keys %p;
        check_('layout map: every path in --delta --impact is a mapped one (' . scalar(keys %p) . ' paths)', "@off", '');
        has('layout map: --map rows that disagree are named', $o, qr/^--map: \d+ row\(s\) name a path the layout map puts elsewhere; the layout map's paths are used$/m);
    }
    spew("$dir/partial.map", "# only two\nStations = physical/stations/\nTypes = library/Types.sysml\n");
    my ($pr) = $X->('--report', '--layout-map', "$dir/partial.map", $xmi{1});
    has('layout map: unlisted packages fall back, with a report line', $pr, qr/\bphysical\/stations\/Stations\.sysml\b/, qr/\blibrary\/Types\.sysml\b/,
        qr/^layout map: Behavior is not listed; written to behavior\/Behavior\.sysml \(the converter's own layout\)$/m);
    spew("$dir/star.map", "Stations = physical/stations/\n* = other/\n");
    my ($sr) = $X->('--report', '--layout-map', "$dir/star.map", $xmi{1});
    has('layout map: the * default', $sr, qr/^layout map: Behavior is not listed; written to other\/Behavior\.sysml \(the \* default\)$/m, qr/\bother\/Legacy_Import\.sysml\b/);
    for my $bad (["Stations\n", 'expected PACKAGE = folder/'], ["Stations = ../x/\n", "without '..'"], ["Stations = a/\nStations = b/\n", 'Stations is mapped twice'],
                 ["Stations = a/b.txt\n", 'must end in .sysml'], ["* = a/b.sysml\n", "'*' must be a folder"], [" = a/\n", 'no package name']) {
        spew("$dir/bad.map", $bad->[0]);
        my ($be, $brc) = $X->('--report', '--layout-map', "$dir/bad.map", $xmi{1});
        check_("layout map error: $bad->[1]", "$brc " . ($be =~ /^xmi2sysml: --layout-map \S*bad\.map:\d+: .*\Q$bad->[1]\E/ ? 1 : 0), '2 1');
    }
    my ($ne, $nrc) = $X->('--report', '--layout-map', "$dir/none.map", $xmi{1});
    check_('layout map that does not exist', "$nrc " . ($ne =~ /^xmi2sysml: --layout-map \S*none\.map: / ? 1 : 0), '2 1');
}

print "1..$n\n";
print $bad ? "# $bad of $n FAILED\n" : "# all $n passed\n";
exit($bad ? 1 : 0);
