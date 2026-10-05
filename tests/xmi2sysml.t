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

print "1..$n\n";
print $bad ? "# $bad of $n FAILED\n" : "# all $n passed\n";
exit($bad ? 1 : 0);
