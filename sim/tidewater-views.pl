#!/usr/bin/perl
# Draws Tidewater's model views into docs/tidewater/views/ from prime drop 1, exactly as a systems engineer would:
# convert the prime's XMI (bin/xmi2sysml.pl), then tools/sysml/model.pl draw tree|trace|ibd|pkg and model.pl idef0.
# The pictures are of the raw conversion (the government has not edited it yet): the part tree, the requirement
# trace with its planted gaps, the interconnections, the package dependencies with the v1 spider web's cycles, and
# the observation cycle as IDEF0 plates (A-0 context and A0 decomposition). index.html shows them with the commands.
# Deterministic: the same drop gives the same bytes (tests/sysml-views.t checks the committed files are current).
#
# Usage:  perl sim/tidewater-views.pl [--out DIR] [--drop N]     (default docs/tidewater/views, drop 1)
#
# Standalone generator -- not part of the tested kit (lib/, bin/, tests/). Core Perl.
use strict;
use warnings;
use FindBin;
use Getopt::Long;
use Cwd qw(abs_path getcwd);
use File::Temp qw(tempdir);
use File::Path qw(make_path remove_tree);
use File::Copy qw(copy);

my $ROOT = abs_path("$FindBin::Bin/..");
my %o = (out => "$ROOT/docs/tidewater/views", drop => 1);
GetOptions(\%o, 'out=s', 'drop=i') or die "usage: perl sim/tidewater-views.pl [--out DIR] [--drop N]\n";
make_path($o{out});
my $out = abs_path($o{out}) // die "tidewater-views: $o{out}: cannot create\n";

sub run {                                       # run(cmd...) -> (output, exit); dies on exit > 1 (1 = findings, drawn in the picture)
    my @cmd = @_;
    open my $h, '-|', @cmd or die "tidewater-views: cannot run $cmd[1]: $!\n";
    my $log = do { local $/; <$h> // '' };
    close $h;
    my $rc = $? >> 8;
    die "tidewater-views: @cmd[1 .. $#cmd] failed (exit $rc):\n$log" if $rc > 1;
    ($log, $rc);
}

# the project as the team has it on day one: the converted drop in model/, and sysml.conf
my $tmp = tempdir(CLEANUP => 1);
my $proj = "$tmp/tidewater";
make_path("$proj/drop");
run($^X, "$ROOT/sim/tidewater-v1.pl", '--drop', $o{drop}, "$proj/drop");
my $here = getcwd();
chdir $proj or die "tidewater-views: cannot cd to $proj: $!\n";        # diagnostics and tooltips name model/... relative to the project
run($^X, "$ROOT/bin/xmi2sysml.pl", '--out', 'model', 'drop/tidewater.xmi');
remove_tree('drop');
open my $c, '>', 'sysml.conf' or die "tidewater-views: cannot write sysml.conf: $!\n";
print {$c} <<'CONF';
# sysml.conf -- Tidewater (notional), read by tools/sysml/model.pl
title         = Tidewater
noun_root     = ObservationNetwork
verb_root     = ObserveCoast
idef0_name    = ObserveCoast
model_letter  = O
idef0_models  = auto
level_tags    = L1Network, L2Segment, L3Station, L4Subsystem, L5Assembly, L6Component
CONF
close $c;

my $mp = "$ROOT/tools/sysml/model.pl";
my @made;
for my $v (['tree'], ['trace', '--mono'], ['ibd'], ['pkg']) {
    my ($kind, @extra) = @$v;
    my ($log) = run($^X, $mp, 'draw', $kind, '-o', "$out/tidewater-$kind.svg", @extra);
    my ($sum) = $log =~ /^((?:tree-svg|trace-svg|\d+ file).* -> \S+)$/m;
    $sum = ($sum // 'drawn') =~ s/ -> .*//r;
    print "$kind: $sum -> tidewater-$kind.svg\n";
    push @made, [$kind, "tidewater-$kind.svg", $sum];
}
my ($ilog) = run($^X, $mp, 'idef0');
for my $p (sort glob('docs/idef0/svg/plate-*.svg')) {
    (my $n = $p) =~ s{.*/plate-}{tidewater-idef0-};
    copy($p, "$out/$n") or die "tidewater-views: cannot copy $p: $!\n";
    print "idef0: $n\n";
    push @made, ['idef0', $n, $n =~ /-0\.svg$/ ? 'A-0: the whole function as one box' : 'A0: its steps'];
}
copy('docs/idef0/ObserveCoast.md', "$out/tidewater-idef0.md") or die "tidewater-views: cannot copy the IDEF0 source: $!\n";
chdir $here;

my %CAP = (tree  => ['Part tree', 'model.pl draw tree', 'The noun tree from ObservationNetwork down, with level tags where the model has them.'],
           trace => ['Requirement trace', 'model.pl draw trace --mono', 'Each requirement and what satisfies and verifies it; the planted gaps show as open shapes.'],
           ibd   => ['Interconnection', 'model.pl draw ibd', 'Parts and the connections between their ports, one diagram per part def that has connections.'],
           pkg   => ['Packages and dependencies', 'model.pl draw pkg', 'The v1 spider web: every package, its imports and references, and the dependency cycles (dashed).'],
           idef0 => ['IDEF0: Observe Coast', 'model.pl idef0', 'The observation cycle as IDEF0 plates, from the verb tree under ObserveCoast and the allocations.']);
my $html = <<'HEAD';
<!DOCTYPE html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>Tidewater model views</title>
<style>
:root{--bg:#f7f7f4;--ink:#1d2433;--dim:#5b6475;--rule:#d5d8de;--card:#fff;--accent:#1f3a5f}
@media (prefers-color-scheme: dark){:root:not([data-theme="light"]){--bg:#15181e;--ink:#e6e8ec;--dim:#a2a9b6;--rule:#333a46;--card:#1d2129;--accent:#9fb8d8}}
:root[data-theme="dark"]{--bg:#15181e;--ink:#e6e8ec;--dim:#a2a9b6;--rule:#333a46;--card:#1d2129;--accent:#9fb8d8}
body{background:var(--bg);color:var(--ink);font:15px/1.5 system-ui,-apple-system,"Segoe UI",sans-serif;margin:0;padding:24px 16px}
main{max-width:1100px;margin:0 auto}h1{color:var(--accent);font-size:24px;margin:0 0 4px}p{margin:6px 0}
.dim{color:var(--dim)}code,pre{font-family:ui-monospace,Consolas,monospace;font-size:13px}
pre{background:var(--card);border:1px solid var(--rule);padding:10px;overflow-x:auto}
figure{background:var(--card);border:1px solid var(--rule);margin:18px 0;padding:12px}
figure img{display:block;max-width:100%;height:auto;background:#fff}figcaption{margin-top:8px}
</style></head><body><main>
<h1>Tidewater model views</h1>
<p class="dim">Prime drop DROP, converted to SysML v2 text and drawn by the kit. Notional; nothing here is real.</p>
<p>Every picture below is generated from the model's text. Nobody draws or lays it out by hand, so it is never out of date.
Make them in your own project with:</p>
<pre>perl $KIT/tools/sysml/model.pl draw tree  -o tree.svg    # in Vim, from a .sysml buffer: \mw  (:SysDraw tree)
perl $KIT/tools/sysml/model.pl draw trace -o trace.svg   #                                 \mq  (:SysDraw trace)
perl $KIT/tools/sysml/model.pl draw ibd   -o ibd.svg     #                                 \mi  (:SysDraw ibd)
perl $KIT/tools/sysml/model.pl draw pkg   -o pkg.svg     #                                 \mp  (:SysDraw pkg)
perl $KIT/tools/sysml/model.pl idef0                     # docs/idef0/plates.html and svg/; in Vim  :!perl $KIT/tools/sysml/model.pl idef0
                                                          # \mW opens the live viewer (wish bin/sysml-view.tcl) beside Vim</pre>
HEAD
$html =~ s/DROP/$o{drop}/;
for my $m (@made) {
    my ($kind, $file, $sum) = @$m;
    my ($t, $cmd, $what) = @{ $CAP{$kind} };
    my $esc = sub { my $s = shift; $s =~ s/&/&amp;/g; $s =~ s/</&lt;/g; $s =~ s/>/&gt;/g; $s };
    $html .= qq{<figure><img src="$file" alt="} . $esc->("$t: $sum") . qq{"><figcaption><b>} . $esc->($t) . '</b> &middot; <code>' . $esc->($cmd)
          . '</code><br>' . $esc->($what) . ' <span class="dim">' . $esc->($sum) . "</span></figcaption></figure>\n";
}
$html .= "</main></body></html>\n";
open my $ih, '>:raw', "$out/index.html" or die "tidewater-views: cannot write $out/index.html: $!\n";
print {$ih} $html;
close $ih;
print "wrote ", scalar(@made), " views and index.html in $o{out}\n";
