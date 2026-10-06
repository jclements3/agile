#!/usr/bin/perl
# xmi2sysml.pl -- SysML v1 XMI (Cameo / MagicDraw export) -> SysML v2 text, one file per top-level package (lib/Xmi.pm)
#
#   perl bin/xmi2sysml.pl --report legacy.xmi                       # mapping summary only: in by xmi:type, out, TODO list
#   perl bin/xmi2sysml.pl --out model legacy.xmi                    # writes model/<segment>/<Package>.sysml (+ the report on stderr)
#   perl bin/xmi2sysml.pl --out model --layout '{pkg}.sysml' legacy.xmi
#   perl bin/xmi2sysml.pl --out model --layout-map layout.map legacy.xmi   # each top-level package at the path the map gives
#                                                                    # (the same map for every drop keeps vendor merges 3-way)
#   perl bin/xmi2sysml.pl --stdout legacy.xmi                       # all files to stdout, each after a "// file: path" line
#   perl bin/xmi2sysml.pl --delta old.xmi new.xmi                  # two drops of the same model: what changed, carried or manual
#   perl bin/xmi2sysml.pl --out model --map map.csv legacy.xmi      # also the v1 -> v2 map: every v1 element, the v2 line it went to
#   perl bin/xmi2sysml.pl --delta old.xmi new.xmi --impact model [--map map.csv] [--impact-csv impact.csv]
#                                                                    # what the change touches in the government's v2 model: requirements,
#                                                                    # verification cases, interfaces, allocations, hand edits to redo;
#                                                                    # grouped by change request when CHANGES.csv sits beside NEW.xmi
#
# Options: --req-style usage|def (one-line requirement usages, the default and the form
# bin/status-metrics.pl counts; or requirement def blocks), --name PKG (the package for elements outside any package; default: the model's
# name, else the file name), --check (also run tools/sysml/sysml.pl over the output when it exists).
# Exit status: 0 ok, 1 when the self-check (or sysml.pl) finds a problem, 2 on bad usage or unreadable input.
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Getopt::Long qw(GetOptions);
use File::Path qw(make_path);
use Xmi;
use SysmlText ();

my %o = (layout => '{seg}/{pkg}.sysml', 'req-style' => 'usage');
GetOptions(\%o, 'out=s', 'layout=s', 'layout-map=s', 'report', 'stdout', 'req-style=s', 'name=s', 'check', 'delta', 'map=s', 'impact=s', 'impact-csv=s', 'help|h')
    or exit 2;
if ($o{help} || @ARGV != ($o{delta} ? 2 : 1)) {
    print STDERR "usage: xmi2sysml.pl [--report] [--out DIR [--layout '{seg}/{pkg}.sysml' | --layout-map FILE] | --stdout]\n"
               . "                     [--req-style usage|def] [--name PKG] [--check] FILE.xmi\n"
               . "                     [--map MAP.csv] FILE.xmi\n"
               . "       xmi2sysml.pl --delta OLD.xmi NEW.xmi [--impact MODEL_DIR [--map OLD-MAP.csv] [--impact-csv FILE]]\n";
    exit($o{help} ? 0 : 2);
}
die "xmi2sysml: --req-style is def or usage\n" unless $o{'req-style'} =~ /^(def|usage)$/;
sub usage_error { print STDERR "xmi2sysml: $_[0]\n"; exit 2 }
usage_error('--impact needs --delta OLD.xmi NEW.xmi') if defined $o{impact} && !$o{delta};
usage_error('--impact-csv needs --impact MODEL_DIR') if defined $o{'impact-csv'} && !defined $o{impact};
usage_error("--impact $o{impact}: not a directory") if defined $o{impact} && !-d $o{impact};
my $lm;                                       # --layout-map: the same top-level package -> path for every drop
if (defined $o{'layout-map'}) { $lm = eval { SysmlText::read_layout_map($o{'layout-map'}) }; usage_error("--layout-map $@" =~ s/\n\z//r) unless $lm }
if ($o{delta}) {                              # two drops of the same v1 model: what changed, and what needs hand rework
    my @m = map { my $f = $_; my $x = eval { Xmi::load($f) }; if (!$x) { print STDERR "xmi2sysml: $@"; exit 2 } $x } @ARGV;
    my $d = Xmi::delta(@m, req_style => $o{'req-style'}, layout => $o{layout}, name => $o{name}, layout_map => $lm);
    print Xmi::delta_text($d);
    if (defined $o{impact}) {
        my $map;
        if (defined $o{map}) { $map = eval { Xmi::read_map_csv($o{map}) }; if (!$map) { print STDERR "xmi2sysml: --map $@"; exit 2 } }
        (my $cdir = $ARGV[1]) =~ s{[^/\\]*$}{};         # the prime's CHANGES.csv beside NEW.xmi groups the report by change request
        my $cf = ($cdir eq '' ? '.' : $cdir) . '/CHANGES.csv'; $cf =~ s{^\./}{} if $cdir eq '';
        my $changes;
        if (-f $cf) { $changes = eval { Xmi::read_changes_csv($cf) }; if (!$changes) { print STDERR "xmi2sysml: $@"; exit 2 } }
        my $i = Xmi::impact($d, $o{impact}, map => $map, changes => $changes, layout_map => $lm);
        print Xmi::impact_text($i);
        if (defined $o{'impact-csv'}) {
            open my $fh, '>', $o{'impact-csv'} or die "xmi2sysml: $o{'impact-csv'}: $!\n";
            binmode $fh; print $fh Xmi::impact_csv($i); close $fh;
        }
    }
    exit 0;
}
my $m = eval { Xmi::load($ARGV[0]) };
if (!$m) { print STDERR "xmi2sysml: $@"; exit 2 }
my $out = Xmi::convert($m, req_style => $o{'req-style'}, layout => $o{layout}, name => $o{name}, layout_map => $lm);
my $files = $out->{files};
my $bad = @{ $out->{problems} } ? 1 : 0;
if ($o{out}) {
    for my $f (sort keys %$files) {
        my $p = "$o{out}/$f";
        (my $d = $p) =~ s{/[^/]*$}{};
        make_path($d) unless -d $d;
        open my $fh, '>', $p or die "xmi2sysml: $p: $!\n";
        binmode $fh;
        print $fh $files->{$f};
        close $fh;
    }
    if ($o{check}) {
        my $chk = "$FindBin::Bin/../tools/sysml/sysml.pl";
        if (-f $chk) {
            my $rc = system($^X, $chk, 'check', map { "$o{out}/$_" } sort keys %$files);
            $bad = 1 if $rc;
        } else { print STDERR "xmi2sysml: tools/sysml/sysml.pl not found; structural self-check only\n" }
    }
}
if ($o{stdout}) { binmode STDOUT; print "// file: $_\n$files->{$_}" for sort keys %$files }
if (defined $o{map}) {                        # the v1 -> v2 map, beside the conversion
    open my $fh, '>', $o{map} or die "xmi2sysml: $o{map}: $!\n";
    binmode $fh; print $fh Xmi::map_csv($m, $out); close $fh;
}
my $rep = Xmi::report_text($out);
if ($o{report}) { print $rep }
elsif ($o{out} || $o{stdout} || defined $o{map}) {
    my $r = $out->{report};
    printf STDERR "xmi2sysml: %d elements in, %d of %d in scope ported, %d TODO, %d file(s), self-check %s\n",
        $r->{total}, $r->{scope_done}, $r->{scope}, scalar @{ $r->{unmapped} }, scalar keys %$files,
        @{ $out->{problems} } ? scalar(@{ $out->{problems} }) . ' problem(s)' : 'ok';
    print STDERR "  $_\n" for @{ $out->{problems} };
    print STDERR "  $_\n" for @{ $r->{layout} || [] };
}
else { print STDERR "xmi2sysml: nothing to do: give --out DIR, --stdout or --report\n"; exit 2 }
exit $bad;
