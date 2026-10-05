#!/usr/bin/perl
# perl tests/status_metrics.t  — StatusMetrics.pm + bin/status-metrics.pl: the A-Z status metrics, end to end, offline.
#   1. simulates Halberd's 12 weeks (sim/status-metrics-sim.pl: a git repo merged daily, exports, collect every day)
#   2. builds the status tables (report)
#   3. checks the weekly table cell by cell against Appendix C of docs/STATUS-METRICS.html
#   4. checks the daily element counts against Appendix D's "Left" column
#   5. checks the three outputs byte for byte against the Python kit's (tests/status-metrics/)
#   6. checks that the collector catches a lint error (E) and a tampered baseline (S)
# plus the JSON codec, pct and the CLI. Needs git (the simulated repo is a real one).
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use File::Temp qw(tempdir);
use File::Path qw(make_path);
use File::Copy qw(copy);
use StatusMetrics qw(collect load_cfg json_encode json_decode oh);

my ($n, $bad) = (0, 0);
sub check { my ($name, $got, $want) = @_; $n++;
    if ($got eq $want) { print "ok $n - $name\n" }
    else { $bad++; print "not ok $n - $name\n#   got:  $got\n#   want: $want\n" } }
sub trim { my ($t) = @_; $t =~ s/^\s+|\s+$//g; $t }
sub slurp { my ($p) = @_; open my $fh, '<:raw', $p or die "$p: $!\n"; local $/; my $t = <$fh>; close $fh; $t // '' }

my $root = "$FindBin::Bin/..";
my $dir = tempdir(CLEANUP => 1);

# ---- the JSON codec: Python's json.dumps spacing, key order kept, number-looking strings stay strings
my $j = json_decode('{"b": 1, "a": [1, 2.5, "3", null, true], "c": {"x": 3.75, "y": 4.0, "z": "\u00e9\n"}, "e": {}, "f": []}');
check 'json round trip, compact', json_encode($j), '{"b": 1, "a": [1, 2.5, "3", null, true], "c": {"x": 3.75, "y": 4.0, "z": "\u00e9\n"}, "e": {}, "f": []}';
check 'json indent=2', json_encode(oh(a => [1], b => oh(c => 'x'), d => []), 2), qq({\n  "a": [\n    1\n  ],\n  "b": {\n    "c": "x"\n  },\n  "d": []\n});
check 'json floats as Python repr', json_encode([ map { json_decode($_) } qw(1e16 1.5e-05 0.1 123456.789 -2.0) ]), '[1e+16, 1.5e-05, 0.1, 123456.789, -2.0]';
my $num = 6; my $s = "sprint-$num.csv";                  # a number that was interpolated stays a number
check 'json: a printed number stays a number', json_encode([$num, "6"]), '[6, "6"]';
check 'pct: never 100 until complete, never 0 once started', join(',', map { StatusMetrics::pct(@$_) } [199, 200], [1, 1000], [200, 200], [0, 5], [3, 0]), '99,1,100,0,0';

# ---- the CLI's argparse behaviour
my $o = qx("$^X" "$root/bin/status-metrics.pl" 2>&1);
check 'no command: usage, exit 2', ($? >> 8) . ' ' . ($o =~ /usage: status-metrics\.pl \{init,collect,report\}/ ? 1 : 0), '2 1';
$o = qx("$^X" "$root/bin/status-metrics.pl" report --config x.json 2>&1);
check 'report without --history: exit 2', ($? >> 8) . ' ' . ($o =~ /required: --history/ ? 1 : 0), '2 1';

# ---- 1. simulate (OUTDIR is wiped by the simulator, so give it a fresh subdirectory)
my $out = "$dir/halberd";
my $log = qx("$^X" "$root/sim/status-metrics-sim.pl" "$out" 2>&1);
check 'simulator exits 0', $? >> 8, 0;
my @log = split /\n/, $log;
check 'simulator ran 56 working days', scalar(grep { /^\d{4}-\d\d-\d\d W\d+D\d ported/ } @log), 56;
check 'init froze the denominators', join(' ', map { load_cfg("$out/metrics.json")->{$_} } qw(v1_total req_total)), '1960 1450';

# ---- 2. report
my $rep = "$out/report";
$o = qx("$^X" "$root/bin/status-metrics.pl" report --config "$out/metrics.json" --history "$out/history.jsonl" --out "$rep" 2>&1);
check 'report', $o, "wrote status-weekly.md (12 weeks), status-daily.csv (56 days), dashboard.json\n";

# ---- 3. weekly table vs Appendix C (the doc is the source of truth for the expected values)
my $doc = slurp("$root/docs/STATUS-METRICS.html");
sub html_rows {
    my ($html) = @_;
    my @rows;
    for my $tr ($html =~ m{<tr[^>]*>(.*?)</tr>}gs) {
        my @c = map { (my $c = $_) =~ s/<[^>]+>//g; $c =~ s/&lt;/</g; $c =~ s/&gt;/>/g; $c =~ s/&amp;/&/g; trim($c) } $tr =~ m{<td[^>]*>(.*?)</td>}gs;
        push @rows, \@c if @c;
    }
    return @rows;
}
sub md_rows { my ($t) = @_; return map { my @f = split /\|/, $_, -1; [ map { trim($_) } @f[ 1 .. $#f - 1 ] ] } grep { /^\| [A-Z] \|/ } split /\n/, $t }
my ($snap) = $doc =~ m{id="metric-snapshot"(.*?)id="week-by-week"}s;
my %exp = map { $_->[0] => [ @$_[ 2 .. $#$_ ] ] } grep { $_->[0] =~ /^[A-Z]$/ } html_rows($snap // '');
my %got = map { $_->[0] => [ @$_[ 2 .. $#$_ ] ] } md_rows(slurp("$rep/status-weekly.md"));
check 'Appendix C found in the doc', scalar(keys %exp), 26;
check 'weekly table has 26 metrics', join('', sort keys %got), join('', 'A' .. 'Z');
my $cells = 0;
for my $L ('A' .. 'Z') {
    $cells += @{ $exp{$L} // [] };
    check "Appendix C row $L", join(' | ', @{ $got{$L} // [] }), join(' | ', @{ $exp{$L} // [] });
}
check 'Appendix C cells checked', $cells, 312;

# ---- 4. daily elements vs Appendix D
my ($appd) = $doc =~ m{(id="appendix-d.*)}s;
my @left = map { (my $l = $_->[2]) =~ s/,//g; $l } grep { $_->[0] =~ /^(?:Mon|Tue|Wed|Thu|Fri) \d\d \w{3}$/ } html_rows($appd // '');
my @hist = map { json_decode($_) } grep { /\S/ } split /\n/, slurp("$out/history.jsonl");
my @mine = map { 1960 - $_->{m}{A}{elements} } @hist;
check 'Appendix D days found', scalar @left, 56;
check 'daily items left match Appendix D', "@mine", "@left";

# ---- 5. the outputs, byte for byte, against the Python kit's
for my $f (qw(status-weekly.md status-daily.csv dashboard.json)) {
    check "$f identical to the Python kit's", (slurp("$rep/$f") eq slurp("$FindBin::Bin/status-metrics/$f") ? 1 : 0), 1;
}
my $dash = json_decode(slurp("$rep/dashboard.json"));
check 'dashboard: sprint, baseline, A', join(' ', $dash->{sprint}, $dash->{baseline}, $dash->{m}{A}{v}, $dash->{m}{A}{prev}, scalar @{ $dash->{m}{A}{hist} }), 'Sprint 6 baseline-3 100 94 12';
check 'history line keys in order', join(',', keys %{ $hist[-1] }), 'date,week,sprint,m';

# ---- 6. negative tests on a copy
sub copy_tree {
    my ($from, $to) = @_;
    make_path($to);
    opendir my $dh, $from or die "$from: $!\n";
    for my $e (grep { $_ ne '.' && $_ ne '..' } readdir $dh) {
        if (-d "$from/$e") { copy_tree("$from/$e", "$to/$e") } else { copy("$from/$e", "$to/$e") or die "copy $from/$e: $!\n" }
    }
    closedir $dh;
}
my $cfg = load_cfg("$out/metrics.json");
copy_tree($cfg->{repo}, "$dir/neg/repo");
$cfg->{repo} = "$dir/neg/repo";
my $last = $hist[-1]{date};
my $clean = collect($cfg, $last)->{m};
check 'the copy collects as the original', json_encode($clean), json_encode($hist[-1]{m});
open my $fh, '>>', "$cfg->{repo}/model/E/structure.sysml" or die;
print {$fh} "part def E0001;\n";                                   # duplicate element
close $fh;
my $e = collect($cfg, $last)->{m}{E};
check 'lint error is caught (E)', ($e->{v} && $e->{v} > 0 ? 1 : 0), 1;
{
    local $ENV{GIT_COMMITTER_DATE} = "${last}T18:00:00+00:00";
    StatusMetrics::git($cfg->{repo}, '-c', 'user.name=JC', '-c', 'user.email=jc@x', 'tag', '-f', '-a', 'baseline-3', '-m', 'sha256=deadbeef');
}
my $S = collect($cfg, $last)->{m}{S};
check 'tampered baseline is caught (S)', "$S->{v} of $S->{total}", '2 of 3';

print "1..$n\n";
print $bad ? "# $bad of $n failed\n" : "# all $n passed\n";
exit($bad ? 1 : 0);
