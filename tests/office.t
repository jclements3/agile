#!/usr/bin/perl
# perl tests/office.t -- tools/office: the Excel edition of the kit (agile-workbook.pl) and its dashboard page.
# What Excel itself would reject is checked here without Excel: every part is well-formed XML, table headers match
# the table columns, formulas use only functions Excel 2007+ knows without the _xlfn. prefix (no dynamic arrays,
# no macros), the same data gives the same bytes, and the dashboard reads the labels the workbook writes.
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use File::Temp qw(tempdir);
use IO::Uncompress::Unzip qw(unzip $UnzipError);
use XmlLite;

my ($n, $bad) = (0, 0);
sub check { my ($name, $got, $want) = @_; $n++;
    if (defined $got && $got eq $want) { print "ok $n - $name\n" }
    else { $bad++; print "not ok $n - $name\n#   got:  " . ($got // 'undef') . "\n#   want: $want\n" } }
sub ok_ { my ($name, $t) = @_; check($name, $t ? 1 : 0, 1) }

my $root = "$FindBin::Bin/..";
my $tool = "$root/tools/office/agile-workbook.pl";
my $tmp = tempdir(CLEANUP => 1);
sub build { my ($out, @a) = @_; my $log = `"$^X" "$tool" @a -o "$tmp/$out" 2>&1`; return ($? >> 8, $log) }
sub part { my ($f, $name) = @_; my $x; unzip("$tmp/$f" => \$x, Name => $name) or return undef; $x }
sub sheet_named {                              # the worksheet part behind a tab name, via workbook.xml and its rels
    my ($f, $name) = @_;
    my ($rid) = part($f, 'xl/workbook.xml') =~ /<sheet name="\Q$name\E" sheetId="\d+" r:id="(rId\d+)"/ or return undef;
    my ($target) = part($f, 'xl/_rels/workbook.xml.rels') =~ /Id="$rid" Type="[^"]+" Target="([^"]+)"/;
    "xl/$target";
}
sub parts { my $f = shift; my $z = IO::Uncompress::Unzip->new("$tmp/$f") or die $UnzipError; my @p; for (my $s = 1; $s > 0; $s = $z->nextStream) { push @p, $z->getHeaderInfo->{Name} } @p }

my ($rc, $log) = build('blank.xlsx');
check('an empty workbook builds', $rc, 0);
ok_('it says what it wrote', $log =~ /0 items, 0 log rows/);
($rc, $log) = build('demo.xlsx', '--from', "$root/data/demo");
my $have_demo = -f "$root/data/demo/scrum.txt";
if ($have_demo) {
    check('the demo project converts', $rc, 0);
    my ($items, $logn, $people) = $log =~ /(\d+) items, (\d+) log rows, (\d+) people/;
    ok_("the demo's tasks, log and people are all there ($log)", ($items // 0) > 200 && ($logn // 0) > 50 && ($people // 0) > 40);
} else { ok_('the demo project converts # skip data/demo not in this checkout', 1) for 1 .. 2 }

for my $f ('blank.xlsx', ($have_demo ? 'demo.xlsx' : ())) {
    my @p = parts($f);
    ok_("$f has the workbook, styles, strings, 12 sheets, 5 tables and 2 charts",
        (grep { $_ eq 'xl/workbook.xml' } @p) && (grep { $_ eq 'xl/styles.xml' } @p) && (grep { $_ eq 'xl/sharedStrings.xml' } @p)
        && (grep { m{^xl/worksheets/sheet\d+\.xml$} } @p) == 12 && (grep { m{^xl/tables/} } @p) == 5 && (grep { m{^xl/charts/} } @p) == 2);
    my ($xmlbad, %func) = (0);
    for my $name (@p) {
        my $x = part($f, $name);
        my $okx = eval { XmlLite::parse_string($x); 1 };
        $xmlbad++, print "# $f: $name is not well-formed: $@" unless $okx;
        if ($name =~ m{^xl/worksheets/sheet}) { while ($x =~ m{<f>([^<]*)</f>}g) { my $fm = $1; $func{$1}++ while $fm =~ /\b([A-Z][A-Z0-9.]*)\(/g } }
    }
    check("$f: every part is well-formed XML", $xmlbad, 0);
    my %allowed = map { $_ => 1 } qw(IF IFERROR LOOKUP INDEX MATCH SUMIFS COUNTIFS COUNTIF COUNTA SUMPRODUCT ISNUMBER ISNA SEARCH FIND SUBSTITUTE TRIM LEFT RIGHT
                                     MID UPPER LOWER AND OR N VALUE VLOOKUP INT MAX MIN NETWORKDAYS TODAY TEXT ROUNDUP SMALL MOD ROW NA);
    my @new = grep { !$allowed{$_} } sort keys %func;
    check("$f: formulas use Excel 2007+ functions only (no _xlfn, no dynamic arrays)", "@new", '');
    # a table's header cells must equal its column names, or Excel "repairs" the file
    my @sst = map { XmlLite::decode_entities($_) } part($f, 'xl/sharedStrings.xml') =~ m{<t xml:space="preserve">([^<]*)</t>}g;
    my $hdrbad = 0;
    for my $tp (grep { m{^xl/tables/} } @p) {
        my $t = part($f, $tp);
        my ($tname, $ref) = $t =~ /name="([^"]+)" displayName="[^"]+" ref="([A-Z]+1):/;
        my @cols = map { XmlLite::decode_entities($_) } $t =~ /<tableColumn id="\d+" name="([^"]+)"/g;
        my $tfile = $tp =~ s{.*/}{}r;
        my ($sheetfile) = grep { (part($f, s{xl/worksheets/(sheet\d+)\.xml}{xl/worksheets/_rels/$1.xml.rels}r) // '') =~ m{\Q../tables/$tfile"} } grep { m{^xl/worksheets/sheet\d+\.xml$} } @p;
        my $sx = part($f, $sheetfile);
        my ($row1) = $sx =~ m{<row r="1">(.*?)</row>};
        my @hdr = map { $sst[$_] } $row1 =~ m{t="s"><v>(\d+)</v>}g;
        $hdrbad++, print "# $tname: header @hdr[0..$#cols] vs columns @cols\n" unless "@hdr[0 .. $#cols]" eq "@cols";
    }
    check("$f: every table's header row matches its columns", $hdrbad, 0);
}

# the same data gives the same bytes (a fixed zip time, sorted output)
build('blank2.xlsx');
open my $a, '<:raw', "$tmp/blank.xlsx" or die; open my $b, '<:raw', "$tmp/blank2.xlsx" or die;
{ local $/; check('the same input gives the same bytes', <$a> eq <$b> ? 1 : 0, 1) }

# the dashboard: one offline page, and it reads the labels the workbook writes on the Start sheet
my $html = do { local $/; open my $fh, '<:encoding(UTF-8)', "$root/tools/office/agile-dashboard.html" or die "dashboard: $!"; <$fh> };
my @ext = grep { !m{^http://(www\.w3\.org|schemas\.openxmlformats\.org)/} } $html =~ m{\b(https?://[^\s"'`)<]+)}g;
check('the dashboard loads nothing from the network', "@ext", '');
ok_('the dashboard has no inline event to an external script', $html !~ /<script[^>]+src=/i);
my $start = part('blank.xlsx', sheet_named('blank.xlsx', 'Start'));
my @sst = part('blank.xlsx', 'xl/sharedStrings.xml') =~ m{<t xml:space="preserve">([^<]*)</t>}g;
my @labels = map { XmlLite::decode_entities($sst[$_]) } $start =~ m{<c r="B\d+" s="\d+" t="s"><v>(\d+)</v>}g;
my ($lk) = $html =~ /const LABEL_KEY = \[(.*?)\];/s;
my @res = $lk =~ m{\[/(.*?)/i,}g;
for my $want ('Sprint 1 starts', 'Sprint length', 'As of', 'Project', 'Stand-up date', 'Blocked: red', 'Team load: high', 'Predictability') {
    my ($label) = grep { /^\Q$want/ } @labels;
    ok_("the Start sheet writes '$want' and the dashboard reads it", $label && grep { my $re = $_; $label =~ /$re/i } @res);
}
my @verbs = $html =~ /case '([a-z]+)':/g;
my $wbx = do { local $/; open my $fh, '<', $tool or die; <$fh> };
my @wverbs = $wbx =~ /\['([a-z]+)',\s+'[^']*', '[A-Z]*', '/g;
ok_('the dashboard replays every verb the workbook offers (' . scalar(@wverbs) . ')', @wverbs >= 12 && !grep { my $v = $_; $v ne 'sync' && $v ne 'note' && !grep { $_ eq $v } @verbs } @wverbs);

print "1..$n\n";
exit($bad ? 1 : 0);
