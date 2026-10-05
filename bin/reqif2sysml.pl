#!/usr/bin/perl
# reqif2sysml.pl -- DOORS requirements (ReqIF .reqif/.reqifz, or a DOORS CSV export) -> SysML v2 requirement
# definitions, one file per DOORS module (SPECIFICATION), plus the trace report behind metrics C/F/G/I (lib/Reqif.pm)
#
#   perl bin/reqif2sysml.pl --report export.reqif                     # counts only
#   perl bin/reqif2sysml.pl --out model export.reqif                  # writes model/<segment>/<Module>.sysml
#   perl bin/reqif2sysml.pl --out model --layout '_reqs/{pkg}.sysml' export.reqifz
#   perl bin/reqif2sysml.pl --report --model model export.reqif       # + linked / orphan / unverified against model/
#   perl bin/reqif2sysml.pl --csv --col id='Object Identifier' --col text='Object Text' --col level='Object Level' \
#        --col vm='Verification Method' --out model module.csv
#
# Options: --req-style usage|def (default usage: the one-line form bin/status-metrics.pl counts; def = requirement def blocks),
# --id-attr NAME / --vm-attr NAME / --text-attr NAME / --heading-attr NAME (ReqIF attribute long names; defaults follow
# the DOORS conventions), --id-prefix SYS- (prepended to ids that lack it, e.g. to ReqIF.ForeignID numbers),
# --attr NAME (repeatable: copy that DOORS attribute onto each requirement), --name PKG (the package name for a CSV,
# or for a single-module ReqIF), --sep ';' (CSV separator; detected by default), --stdout, --check (also run
# tools/sysml/sysml.pl when it exists). A .csv file name implies --csv.
# Exit status: 0 ok, 1 when the self-check (or sysml.pl) finds a problem, 2 on bad usage or unreadable input.
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Getopt::Long qw(GetOptions);
use File::Path qw(make_path);
use Reqif;

my %o = (layout => '{seg}/{pkg}.sysml', 'req-style' => 'usage', col => {}, attr => []);
GetOptions(\%o, 'out=s', 'layout=s', 'report', 'stdout', 'req-style=s', 'name=s', 'check', 'csv', 'col=s%', 'sep=s',
           'id-attr=s', 'vm-attr=s', 'text-attr=s', 'heading-attr=s', 'id-prefix=s', 'attr=s@', 'model=s', 'help|h')
    or exit 2;
if ($o{help} || @ARGV != 1) {
    print STDERR "usage: reqif2sysml.pl [--report] [--model DIR] [--out DIR [--layout '{seg}/{pkg}.sysml'] | --stdout]\n"
               . "                      [--csv [--col id=NAME --col text=NAME --col heading=NAME --col level=NAME --col vm=NAME] [--sep C]]\n"
               . "                      [--req-style usage|def] [--id-attr NAME] [--vm-attr NAME] [--id-prefix P] [--attr NAME]... FILE\n";
    exit($o{help} ? 0 : 2);
}
die "reqif2sysml: --req-style is def or usage\n" unless $o{'req-style'} =~ /^(def|usage)$/;
my $file = $ARGV[0];
my %lo = (id_attr => $o{'id-attr'}, vm_attr => $o{'vm-attr'}, text_attr => $o{'text-attr'}, heading_attr => $o{'heading-attr'},
          id_prefix => $o{'id-prefix'}, name => $o{name}, sep => (defined $o{sep} && $o{sep} eq '\t' ? "\t" : $o{sep}), cols => $o{col});
my $d = eval { ($o{csv} || $file =~ /\.csv$/i) ? Reqif::load_csv($file, %lo) : Reqif::load_reqif($file, %lo) };
if (!$d) { print STDERR "reqif2sysml: $@"; exit 2 }
my $out = Reqif::convert($d, req_style => $o{'req-style'}, layout => $o{layout}, name => $o{name}, extra_attrs => $o{attr});
my $files = $out->{files};
my $bad = @{ $out->{problems} } ? 1 : 0;
if ($o{out}) {
    for my $f (sort keys %$files) {
        my $p = "$o{out}/$f";
        (my $dd = $p) =~ s{/[^/]*$}{};
        make_path($dd) unless -d $dd;
        open my $fh, '>', $p or die "reqif2sysml: $p: $!\n";
        binmode $fh;
        print $fh $files->{$f};
        close $fh;
    }
    if ($o{check}) {
        my $chk = "$FindBin::Bin/../tools/sysml/sysml.pl";
        if (-f $chk) { $bad = 1 if system($^X, $chk, 'check', map { "$o{out}/$_" } sort keys %$files) }
        else { print STDERR "reqif2sysml: tools/sysml/sysml.pl not found; structural self-check only\n" }
    }
}
if ($o{stdout}) { binmode STDOUT; print "// file: $_\n$files->{$_}" for sort keys %$files }
if ($o{report}) {
    print Reqif::report_text($out);
    print Reqif::trace_text(Reqif::trace($d, $out, $o{model})) if $o{model};
} elsif ($o{out} || $o{stdout}) {
    my $c = $out->{report}{counts};
    printf STDERR "reqif2sysml: %d objects, %d requirements (%d with a verification method), %d headings, %d links, %d file(s), self-check %s\n",
        $out->{report}{objects}, $c->{requirements}, $c->{with_vm}, $c->{headings}, $out->{report}{relations}, scalar keys %$files,
        @{ $out->{problems} } ? scalar(@{ $out->{problems} }) . ' problem(s)' : 'ok';
    print STDERR "  $_\n" for @{ $out->{problems} };
    print STDERR Reqif::trace_text(Reqif::trace($d, $out, $o{model})) if $o{model};
} elsif ($o{model}) {
    print Reqif::report_text($out), Reqif::trace_text(Reqif::trace($d, $out, $o{model}));
} else { print STDERR "reqif2sysml: nothing to do: give --out DIR, --stdout, --report or --model DIR\n"; exit 2 }
exit $bad;
