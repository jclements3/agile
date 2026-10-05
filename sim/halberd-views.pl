#!/usr/bin/perl
# Draws the Halberd model's four views into docs/img/ with tools/sysml/model.pl draw (the
# tools/sysml/views toolkit): halberd-tree.svg (part decomposition), halberd-trace.svg (requirement
# trace, --mono: status as shapes, for print), halberd-ibd.svg (interconnection by trust zone) and
# halberd-pkg.svg (packages and markings). docs/HALBERD.html links them; sim/halberd-gen.pl --pdf puts
# them, in grey, in the "Model views" section of docs/HALBERD.pdf. Deterministic: the same model gives
# the same bytes (tests/sysml-views.t checks the committed files are current).
#
# Usage:  perl sim/halberd-views.pl [--out DIR]      (default docs/img; run it after a model change)
#
# Standalone generator -- not part of the tested kit (lib/, bin/, tests/). Core Perl.
use strict;
use warnings;
use FindBin;
use Getopt::Long;
use Cwd qw(abs_path);

my $ROOT = abs_path("$FindBin::Bin/..");
my %o = (out => "$ROOT/docs/img");
GetOptions(\%o, 'out=s') or die "usage: perl sim/halberd-views.pl [--out DIR]\n";
my $out = abs_path($o{out}) // die "halberd-views: $o{out}: no such directory\n";
chdir $ROOT or die "halberd-views: cannot cd to $ROOT: $!\n";     # diagnostics and tooltips name examples/halberd/model/...
for my $v (['tree'], ['trace', '--mono'], ['ibd'], ['pkg', '--hide', 'SecMeta']) {
    my ($kind, @extra) = @$v;
    my @cmd = ($^X, 'tools/sysml/model.pl', '--root', 'examples/halberd', 'draw', $kind, '-o', "$out/halberd-$kind.svg", @extra);
    my $log = '';
    open my $h, '-|', @cmd or die "halberd-views: cannot run model.pl: $!\n";
    { local $/; $log = <$h> // '' }
    close $h;
    my $rc = $? >> 8;
    die "halberd-views: model.pl draw $kind failed (exit $rc):\n$log" if $rc > 1;    # 1 = the planted gaps, reported in the picture
    my ($sum) = $log =~ /^((?:tree-svg|trace-svg|\d+ file).* -> \S+)$/m;
    print "$kind: ", ($sum // 'drawn') =~ s/ -> .*//r, " -> halberd-$kind.svg\n";
}
