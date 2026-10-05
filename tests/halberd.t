#!/usr/bin/perl
# perl tests/halberd.t -- sim/halberd-gen.pl rebuilds the Halberd example through the kit's own pipeline, the
# sprint totals match the doc, the funding journal adds up, and docs/HALBERD.html is what the generator writes
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use File::Temp qw(tempdir);
use Scrum qw(load sprint_summary);
use Ledger ();

my ($n, $bad) = (0, 0);
sub check { my ($name, $got, $want) = @_; $n++;
    if ($got eq $want) { print "ok $n - $name\n" }
    else { $bad++; print "not ok $n - $name\n#   got:  $got\n#   want: $want\n" } }
sub slurp { my $f = shift; open my $fh, '<:raw', $f or return ''; local $/; my $t = <$fh>; close $fh; $t }

my $root = "$FindBin::Bin/..";
my $tmp  = tempdir(CLEANUP => 1);
my $dir  = "$tmp/data/halberd";
my $out  = qx("$^X" "$root/sim/halberd-gen.pl" --dir "$dir" --html "$tmp/HALBERD.html" --tex "$tmp/HALBERD.tex" 2>&1);
check 'generator runs', $?, 0;
check 'every sprint matches the doc', scalar(() = $out =~ /\(matches the doc\)/g), 6;
check '56 stand-ups, 59 tasks', ($out =~ /56 stand-ups, 59 tasks/ ? 1 : 0), 1;

my $s = load("$dir/scrum.txt", today => '2026-12-23');
check 'sprint 3 from the journal: committed/done/carried', join('/', @{ sprint_summary($s, 3)->{totals} }{qw(committed done carryover)}), '375/330/45';
my @files = glob("$dir/standups/2026-*.txt");
check 'a stand-up and an answers file per working day', scalar(@files), 112;

my $j = Ledger::read_journal("$dir/funding.ledger");
check 'funding journal balances', scalar @{ $j->{errors} }, 0;
my $e = Ledger::evm($j, status => '2026-12-24', complete => Ledger::read_complete([], "$dir/complete-2026-12-23.csv"));
check 'BAC', sprintf('%.2f', $e->{total}{bac}), '294000.00';
check 'finished: 100% done, CPI 0.98', sprintf('%.0f%% %.2f', 100 * $e->{total}{pct}, $e->{total}{cpi}), '100% 0.98';
$e = Ledger::evm($j, status => '2026-12-01', complete => Ledger::read_complete([], "$dir/complete-2026-11-30.csv"));
check 'end of November: SPI 1.00, CPI 0.99', sprintf('%.2f %.2f', $e->{total}{spi}, $e->{total}{cpi}), '1.00 0.99';
my ($left) = values %{ Ledger::account_total($j, 'Assets:Funding:Halberd') };
check 'reserve left at the finish', sprintf('%.2f', $left), '24585.00';

check 'docs/HALBERD.html is up to date (run perl sim/halberd-gen.pl)', (slurp("$tmp/HALBERD.html") eq slurp("$root/docs/HALBERD.html") ? 1 : 0), 1;
check 'docs/HALBERD.tex is up to date (run perl sim/halberd-gen.pl --pdf)', (slurp("$tmp/HALBERD.tex") eq slurp("$root/docs/HALBERD.tex") ? 1 : 0), 1;
check 'docs/HALBERD.pdf is committed', (-s "$root/docs/HALBERD.pdf" ? 1 : 0), 1;
check 'the page shows the funding section', (slurp("$tmp/HALBERD.html") =~ /<h2>Funding and earned value<\/h2>/ ? 1 : 0), 1;

print "1..$n\n";
print $bad ? "# $bad of $n FAILED\n" : "# all $n passed\n";
exit($bad ? 1 : 0);
