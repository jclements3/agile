#!/usr/bin/perl
# xmi2sysml.pl -- SysML v1 XMI (Cameo / MagicDraw export) -> SysML v2 text, one file per top-level package (lib/Xmi.pm)
#
#   perl bin/xmi2sysml.pl --report legacy.xmi                       # mapping summary only: in by xmi:type, out, TODO list
#   perl bin/xmi2sysml.pl --out model legacy.xmi                    # writes model/<segment>/<Package>.sysml (+ the report on stderr)
#   perl bin/xmi2sysml.pl --out model --layout '{pkg}.sysml' legacy.xmi
#   perl bin/xmi2sysml.pl --stdout legacy.xmi                       # all files to stdout, each after a "// file: path" line
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

my %o = (layout => '{seg}/{pkg}.sysml', 'req-style' => 'usage');
GetOptions(\%o, 'out=s', 'layout=s', 'report', 'stdout', 'req-style=s', 'name=s', 'check', 'help|h')
    or exit 2;
if ($o{help} || @ARGV != 1) {
    print STDERR "usage: xmi2sysml.pl [--report] [--out DIR [--layout '{seg}/{pkg}.sysml'] | --stdout]\n"
               . "                     [--req-style usage|def] [--name PKG] [--check] FILE.xmi\n";
    exit($o{help} ? 0 : 2);
}
die "xmi2sysml: --req-style is def or usage\n" unless $o{'req-style'} =~ /^(def|usage)$/;
my $m = eval { Xmi::load($ARGV[0]) };
if (!$m) { print STDERR "xmi2sysml: $@"; exit 2 }
my $out = Xmi::convert($m, req_style => $o{'req-style'}, layout => $o{layout}, name => $o{name});
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
my $rep = Xmi::report_text($out);
if ($o{report}) { print $rep }
elsif ($o{out} || $o{stdout}) {
    my $r = $out->{report};
    printf STDERR "xmi2sysml: %d elements in, %d of %d in scope ported, %d TODO, %d file(s), self-check %s\n",
        $r->{total}, $r->{scope_done}, $r->{scope}, scalar @{ $r->{unmapped} }, scalar keys %$files,
        @{ $out->{problems} } ? scalar(@{ $out->{problems} }) . ' problem(s)' : 'ok';
    print STDERR "  $_\n" for @{ $out->{problems} };
}
else { print STDERR "xmi2sysml: nothing to do: give --out DIR, --stdout or --report\n"; exit 2 }
exit $bad;
