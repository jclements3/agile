#!/usr/bin/perl
# sysml-check.pl : the validate gate in one command. Runs every text-level check on a SysML v2
# model and prints one summary line. Core Perl 5 only (Git for Windows).
#
#   perl sysml-check.pl [--tools DIR] [--only a,b] [--svg DIR] [--today YYYY-MM-DD] [--strict] [MODEL_DIR]
#
# Checks, in order (MODEL_DIR defaults to ./model):
#   text      sysml-gate.pl   bare imports, keywords as names, quantities without units,
#                             requirements without doc, unbalanced braces          (binder)
#   trace     sysml-trace.pl  leaf requirements satisfied and verified (G6)        (binder)
#   markings  sysml-pkg-svg.pl     root markings, no write-down, leakage, cycles (SEC-4)
#   zones     sysml-ibd-svg.pl     boundary coverage (SEC-1)
#   threats   sysml-threats.pl     threat completeness, mitigation closure (SEC-2, SEC-3)
# The binder's two scripts are looked for in --tools DIR, then next to this script, then in
# binder/ next to this script, then in ./tools; a check whose script is missing is reported as
# skipped (and fails with --strict).
#
#   --svg DIR   also write the pictures there (packages.svg, ibd.svg, trace.svg, tree.svg),
#               e.g. docs/ for rule G13
#   --strict    count warnings from current risk acceptances, and skipped checks, as failures
#
# The gate rule is 0 errors and 0 warnings. One exception by default: a threat warning that
# says it is "accepted by risk acceptance" is listed but does not fail the gate, because the
# binder makes a current acceptance a warning that must stay visible, not a blocker.
# Exit status: 0 pass, 1 fail, 2 usage error.
use strict; use warnings;
use Getopt::Long; use File::Basename qw(dirname); use File::Temp qw(tempdir);
binmode STDOUT, ':encoding(UTF-8)';

my %O;
GetOptions(\%O, 'tools=s', 'only=s', 'svg=s', 'today=s', 'strict')
    or do { print STDERR "usage: perl sysml-check.pl [--tools DIR] [--only a,b] [--svg DIR] [--today YYYY-MM-DD] [--strict] [MODEL_DIR]\n"; exit 2 };
my $model = shift @ARGV // 'model';
if (@ARGV || !-e $model) { print STDERR "sysml-check: $model: no such file or directory\n"; exit 2 }
my $here = dirname($0);
my $svgdir = $O{svg} // tempdir('sysml-check-XXXXXX', TMPDIR => 1, CLEANUP => 1);
if ($O{svg} && !-d $O{svg}) { mkdir $O{svg} or do { print STDERR "sysml-check: $O{svg}: $!\n"; exit 2 } }

sub find_tool {
    my $name = shift;
    for my $d (grep { defined } $O{tools}, $here, "$here/binder", 'tools') { return "$d/$name" if -f "$d/$name" }
    return undef;
}
my @CHECKS = (
    [text     => 'sysml-gate.pl',    [$model]],
    [trace    => 'sysml-trace.pl',   [$model]],
    [markings => 'sysml-pkg-svg.pl', ['-o', "$svgdir/packages.svg", $model]],
    [zones    => 'sysml-ibd-svg.pl', ['-o', "$svgdir/ibd.svg", $model]],
    [threats  => 'sysml-threats.pl', [($O{today} ? ('--today', $O{today}) : ()), $model]],
);
my %ONLY = map { $_ => 1 } split /,/, $O{only} // '';
if (%ONLY) { my %known = map { $_->[0] => 1 } @CHECKS; for (keys %ONLY) { next if $known{$_}; print STDERR "sysml-check: unknown check '$_' (known: @{[map { $_->[0] } @CHECKS]})\n"; exit 2 } }

my ($E, $W, $ACC, $SKIP, $RAN) = (0, 0, 0, 0, 0);
for my $c (@CHECKS) {
    my ($name, $script, $args) = @$c;
    next if %ONLY && !$ONLY{$name};
    my $path = find_tool($script);
    unless ($path) { print "== $name: SKIPPED ($script not found; use --tools DIR)\n"; $SKIP++; next }
    $RAN++;
    print "== $name ($script)\n";
    open my $h, '-|', $^X, $path, @$args or do { print "   cannot run $path: $!\n"; $E++; next };
    binmode $h, ':encoding(UTF-8)';
    my ($e, $w, $acc, $last) = (0, 0, 0, '');
    while (my $l = <$h>) {
        chomp $l;
        if ($l =~ /: error: /) { $e++; print "$l\n" }
        elsif ($l =~ /: warning: /) {
            if ($l =~ /accepted by risk acceptance/ && !$O{strict}) { $acc++; print "$l\n" } else { $w++; print "$l\n" }
        }
        elsif ($l =~ /: note: /) { print "$l\n" }
        elsif ($l =~ /\S/) { $last = $l }
    }
    close $h;
    my $rc = $? >> 8;
    if ($rc == 2 || ($rc && !$e && !$w && !$acc && $name ne 'trace')) { print "   $script failed (exit $rc)\n"; $e++ }
    $last =~ s/ -> \S+$// unless $O{svg};
    print "   $last\n" if $last ne '';
    ($E, $W, $ACC) = ($E + $e, $W + $w, $ACC + $acc);
}
if ($O{svg}) {      # the two pictures that are not by-products of a check
    for my $v (['sysml-trace-svg.pl', 'trace.svg'], ['sysml-tree-svg.pl', 'tree.svg']) {
        my $p = find_tool($v->[0]) or next;
        system($^X, $p, '-o', "$O{svg}/$v->[1]", $model) == 0 or $E++;
    }
}
$W += $ACC if $O{strict};
$E += $SKIP if $O{strict};
my $ok = !$E && !$W;
printf "check: %d check(s) run%s, %d error(s), %d warning(s)%s -> %s\n", $RAN, ($SKIP ? ", $SKIP skipped" : ''), $E, $W,
    ($ACC && !$O{strict} ? ", $ACC accepted risk(s) listed" : ''), $ok ? 'PASS' : 'FAIL';
exit($ok ? 0 : 1);
