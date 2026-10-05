#!/usr/bin/perl
# perl tests/reqif2sysml.t          (REGEN=1 perl tests/reqif2sysml.t rewrites the goldens under tests/fixtures/reqif2sysml/expected/)
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use File::Temp qw(tempdir);
use File::Path qw(make_path);
use Reqif;
use Xmi;

my ($n, $bad) = (0, 0);
sub check_ { my ($name, $got, $want) = @_; $n++;
    if ($got eq $want) { print "ok $n - $name\n" }
    else { $bad++; print "not ok $n - $name\n#   got:  $got\n#   want: $want\n" } }
sub has { my ($name, $text, @res) = @_; for my $re (@res) { check_("$name: $re", ($text =~ $re ? 1 : 0), 1) } }
sub skip_ { my ($name, $why) = @_; $n++; print "ok $n - $name # skip $why\n" }
sub slurp { my ($p) = @_; open my $fh, '<', $p or return undef; binmode $fh; local $/; my $t = <$fh>; close $fh; return $t }
sub spew { my ($p, $t) = @_; (my $d = $p) =~ s{/[^/]*$}{}; make_path($d) unless -d $d; open my $fh, '>', $p or die "$p: $!"; binmode $fh; print $fh $t; close $fh }

my $root = "$FindBin::Bin/..";
my $fx = "$FindBin::Bin/fixtures/reqif2sysml";
my $dir = tempdir(CLEANUP => 1);
my $regen = $ENV{REGEN};
sub golden {                                  # golden($name, $text): compare (or rewrite with REGEN=1)
    my ($name, $text) = @_;
    spew("$fx/expected/$name", $text) if $regen;
    my $want = slurp("$fx/expected/$name");
    check_("golden $name", $text, defined $want ? $want : '(missing golden)');
}

# ---- XHTML flattening and CSV parsing
my $x = XmlLite::parse_string('<THE-VALUE xmlns:h="http://www.w3.org/1999/xhtml"><h:div>A <h:b>bold</h:b>&#160;word<h:br/>next<h:ul><h:li>one</h:li><h:li>two</h:li></h:ul><h:table><h:tr><h:td>a</h:td><h:td>b</h:td></h:tr></h:table><h:img alt="fig 1"/></h:div></THE-VALUE>',
    keep_ws => sub { 1 });
check_('xhtml flattened: inline, br, list, table, image', Reqif::xhtml_text($x), "A bold word\nnext\n- one\n- two\na | b\n[fig 1]");
my $rows = Reqif::parse_csv(qq{\xEF\xBB\xBFid;text\r\n1;"two\r\nlines; ""q"""\r\n\r\n2;plain\r\n});
check_('csv: BOM, ; detected, quoted newline, doubled quotes, blank line', join('|', map { join('^', @$_) } @$rows), qq{id^text|1^two\nlines; "q"|2^plain});

# ---- ReqIF fixture (DOORS conventions): golden output, both styles
my %o = (id_prefix => 'CD-');
my $d = Reqif::load_reqif("$fx/courier.reqif", %o);
check_('objects, specifications, relations', join(' ', scalar @{ $d->{order} }, scalar @{ $d->{specs} }, scalar @{ $d->{relations} }), '11 2 3');
my $ob = $d->{objects}{'o-101'};
check_('object 101: id, title, verification method, typed values', join('|', $ob->{id}, $ob->{name}, $ob->{vm}, @{ $ob->{attrs} }{'Priority', 'Margin', 'Last Reviewed'}),
    'CD-101|Endurance|Test|1|0.15|2026-09-15T00:00:00Z');
check_('multi-valued enumeration', $d->{objects}{'o-102'}{vm}, 'Test, Analysis');
my %out;
for my $style (qw(def usage)) {
    my $out = Reqif::convert($d, req_style => $style);
    $out{$style} = $out;
    golden("reqif-$style/$_", $out->{files}{$_}) for sort keys %{ $out->{files} };
    check_("$style: self-check clean", scalar @{ $out->{problems} }, 0);
}
my $out = $out{def};
check_('files: one per DOORS module, plus unplaced objects', join(' ', sort keys %{ $out->{files} }),
    'battery-requirements/Battery_Requirements.sysml system-requirements-unplaced/System_Requirements_unplaced.sysml system-requirements/System_Requirements.sysml');
my $rep = Reqif::report_text($out);
golden('reqif-report.txt', $rep);
my $c = $out->{report}{counts};
check_('counts: requirements, with vm, without, headings, orphan headings, empty, unplaced',
    join(' ', @$c{qw(requirements with_vm without_vm headings orphan_headings empty unplaced)}), '6 3 3 4 1 1 1');
check_('links: derive, satisfy, verify, trace, unresolved', join(' ', @{ $out->{report}{links} }{qw(derive satisfy verify trace unresolved)}), '1 0 0 1 1');
my $all = join '', map { $out->{files}{$_} } sort keys %{ $out->{files} };
has 'mapping', $all,
    qr/^    package Mission \{\n        \/\/ DOORS heading CD-1\n        requirement def CD_101 \{$/m,
    qr/^                 \* at 15 m\/s & 20\xC2\xB0C\.$/m, qr/^            attribute title = "Endurance";$/m,
    qr/^            attribute verificationMethod = "Test, Analysis";$/m, qr/^                 \* - two 1 kg parcels\.$/m,
    qr/^    package 'Safety & Environment' \{$/m, qr/^                     \* Hover \| 70 dBA$/m,
    qr/^            \/\/ TODO DOORS object CD-104 has neither text nor heading$/m,
    qr/^    private import 'System Requirements'::Mission::\*;$/m,
    qr/^        end #original ::> CD_101;\n        end #derive ::> CD_210;$/m,
    qr/^    dependency from CD_211 to CD_102; \/\/ trace \(DOORS link\)$/m,
    qr/TODO link rel-3 \(satisfies\): CD-103 -> CD-2 is not between two requirements/;
has 'usage style is one line per requirement', join('', values %{ $out{usage}{files} }),
    qr/^            requirement CD_103 \{ doc \/\* Phase \| Limit Hover \| 70 dBA Measured at 10 m\. Do not use <raw> markup\. \*\/ attribute doorsId = "CD-103"; \}$/m;

# ---- .reqifz (zip) -- IO::Uncompress::Unzip is core; the archive is built with IO::Compress::Zip
if (eval { require IO::Compress::Zip; require IO::Uncompress::Unzip; 1 }) {
    my $xml = slurp("$fx/courier.reqif");
    IO::Compress::Zip::zip(\$xml => "$dir/courier.reqifz", Name => 'courier.reqif') or die "zip failed";
    my $z = Reqif::convert(Reqif::load_reqif("$dir/courier.reqifz", %o));
    (my $zt = join('', map { $z->{files}{$_} } sort keys %{ $z->{files} })) =~ s/courier\.reqifz/courier.reqif/g;
    check_('.reqifz gives the same output', $zt, $all);
} else { skip_('.reqifz', 'IO::Compress::Zip not available') }

# ---- CRLF + BOM ReqIF and a tiny read buffer: same output
(my $crlf = slurp("$fx/courier.reqif")) =~ s/\n/\r\n/g;
spew("$dir/crlf.reqif", "\xEF\xBB\xBF$crlf");
{
    local $XmlLite::CHUNK = 5;
    my $o2 = Reqif::convert(Reqif::load_reqif("$dir/crlf.reqif", %o));
    (my $want = $all) =~ s/courier\.reqif/crlf.reqif/g;
    check_('CRLF + BOM + tiny read buffer', join('', map { $o2->{files}{$_} } sort keys %{ $o2->{files} }), $want);
}

# ---- DOORS CSV: guessed columns, then named ones; CRLF + BOM
(my $csv = slurp("$fx/courier.csv")) =~ s/\n/\r\n/g;
spew("$dir/courier.csv", "\xEF\xBB\xBF$csv");
my $cd = Reqif::load_csv("$dir/courier.csv");
my $co = Reqif::convert($cd);
golden('csv-def/courier/courier.sysml', $co->{files}{'courier/courier.sysml'});
check_('csv counts: requirements, with vm, headings, orphan headings', join(' ', @{ $co->{report}{counts} }{qw(requirements with_vm headings orphan_headings)}), '3 2 4 1');
my $cn = Reqif::convert(Reqif::load_csv("$dir/courier.csv", cols => { id => 'Object Identifier', text => 'Object Text', heading => 'Object Heading', level => 'Object Level', vm => 'Verification Method' }, name => 'Courier'));
has 'csv with named columns and --name', $cn->{files}{'courier/Courier.sysml'}, qr/^package Courier \{$/m, qr/^            doc \/\* Carry a "standard" 2 kg parcel\. \*\/$/m;
eval { Reqif::load_csv("$dir/courier.csv", cols => { id => 'Nope' }) };
has 'csv: a missing named column is an error that lists the columns', $@, qr/no column 'Nope' \(have: Object Identifier, Object Level/;

# ---- trace against a model: the XMI port of the same drone (metrics C, F, G, I)
my $xo = Xmi::convert(Xmi::load("$FindBin::Bin/fixtures/xmi2sysml/courier.xmi"));
spew("$dir/model/$_", $xo->{files}{$_}) for keys %{ $xo->{files} };
my $t = Reqif::trace($d, $out, "$dir/model");
check_('trace: total, C linked, F orphan, G unverified, I complete, extra',
    join(' ', $t->{total}, scalar @{ $t->{linked} }, scalar @{ $t->{orphan} }, scalar @{ $t->{unverified} }, scalar @{ $t->{complete} }, $t->{extra}), '6 3 4 5 1 1');
check_('trace: orphans named', join(' ', @{ $t->{orphan} }), 'CD-103 CD-210 CD-211 CD-999');
(my $tt = Reqif::trace_text($t)) =~ s/\Q$dir\E/DIR/g;
golden('trace.txt', $tt);
# the one-line usage form and status-metrics' own sim shape: bare SPEC-OBJECTs carrying only an IDENTIFIER
spew("$dir/bare.reqif", "<REQ-IF>\n" . join('', map { sprintf qq(<SPEC-OBJECT IDENTIFIER="HAL-%04d"/>\n), $_ } 1 .. 5) . "</REQ-IF>\n");
spew("$dir/bm/model/_reqs/requirements.sysml", "package Requirements {\n" . join('', map { sprintf qq(  requirement r%04d { attribute doorsId = "HAL-%04d"; }\n), $_, $_ } 1 .. 4)
    . "  satisfy r0001 by E0001;\n  satisfy r0002 by E0001;\n  verify r0001;\n}\n");
my $bd = Reqif::load_reqif("$dir/bare.reqif");
my $bt = Reqif::trace($bd, Reqif::convert($bd), "$dir/bm/model");
check_('bare objects: C linked 4 of 5, F 3, G 4, complete 1', join(' ', scalar @{ $bt->{linked} }, $bt->{total}, scalar @{ $bt->{orphan} }, scalar @{ $bt->{unverified} }, scalar @{ $bt->{complete} }), '4 5 3 4 1');

# ---- the CLI
my $msg = qx("$^X" "$root/bin/reqif2sysml.pl" --req-style def --id-prefix CD- --out "$dir/cli" "$fx/courier.reqif" 2>&1);
check_('cli exit status', $? >> 8, 0);
has 'cli summary', $msg, qr/11 objects, 6 requirements \(3 with a verification method\), 4 headings, 3 links, 3 file\(s\), self-check ok/;
check_('cli wrote the golden files', join(' ', map { (slurp("$dir/cli/$_") // '') eq (slurp("$fx/expected/reqif-def/$_") // '-') ? 1 : 0 } sort keys %{ $out->{files} }), '1 1 1');
my $cr = qx("$^X" "$root/bin/reqif2sysml.pl" --id-prefix CD- --report --model "$dir/model" "$fx/courier.reqif");
(my $crn = $cr) =~ s/\Q$dir\E/DIR/g;
check_('cli --report --model', $crn, $rep . $tt);
my $cc = qx("$^X" "$root/bin/reqif2sysml.pl" --req-style def --col "id=Object Identifier" --col "level=Object Level" --stdout "$dir/courier.csv" 2>/dev/null);
has 'cli csv --col --stdout', $cc, qr{^// file: courier/courier\.sysml$}m, qr/requirement def CD_103 \{/;

# ---- the SysML v2 grammar checker, when the repo has it
my $chk = "$root/tools/sysml/sysml.pl";
if (-f $chk) {
    for my $style (qw(def usage)) {
        my $od = "$dir/chk-$style";
        spew("$od/r/$_", $out{$style}{files}{$_}) for keys %{ $out{$style}{files} };
        my $cs = Reqif::convert($cd, req_style => $style);
        spew("$od/c/$_", $cs->{files}{$_}) for keys %{ $cs->{files} };
        my @f = ((map { "$od/r/$_" } sort keys %{ $out{$style}{files} }), map { "$od/c/$_" } sort keys %{ $cs->{files} });
        my $res = qx("$^X" "$chk" check @{[ join ' ', map { qq("$_") } @f ]} 2>&1);
        check_("tools/sysml/sysml.pl check passes ($style)", $? >> 8, 0);
        print map { "#   $_\n" } split /\n/, $res if $?;
    }
} else { skip_('tools/sysml/sysml.pl check', 'tools/sysml/sysml.pl not in this checkout') for 1 .. 2 }

print "1..$n\n";
print $bad ? "# $bad of $n FAILED\n" : "# all $n passed\n";
exit($bad ? 1 : 0);
