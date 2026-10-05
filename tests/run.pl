#!/usr/bin/perl
# perl tests/run.pl [-j N] [--perl PATH] [-v] [TEST...] -- run the test suites in parallel and print one line per suite.
#
#   -j N        how many suites at once (default: the number of CPUs, at most 8; -j 1 runs them one after another)
#   --perl P    the Perl to run each suite with (default: this one)
#   -v          print the full output of every suite that fails
#   TEST...     the suites to run (default: tests/*.t)
#
# Every suite works in its own temporary directory, so they can run side by side. The slowest suites start first, so a
# run takes about as long as the slowest one. Each line is the suite's own summary ("# all N passed") and its time;
# a suite fails when its exit status is not 0 or its last line is not "# all ... passed". Exit status: 0 when every
# suite passed, 1 otherwise. Core Perl only; runs under Git for Windows' Perl (fork works there) and Linux Perl.
use strict;
use warnings;
use FindBin;
use Getopt::Long;
use File::Temp qw(tempdir);
use Time::HiRes qw(time);
use POSIX qw(:sys_wait_h);

my %o = (perl => $^X);
GetOptions(\%o, 'j=i', 'perl=s', 'v') or die "usage: perl tests/run.pl [-j N] [--perl PATH] [-v] [TEST...]\n";
my $root = "$FindBin::Bin/..";
chdir $root or die "cannot cd to $root: $!\n";
my @tests = @ARGV ? @ARGV : sort glob('tests/*.t');
die "no test suites found\n" unless @tests;

sub cpus {
    return $ENV{NUMBER_OF_PROCESSORS} if ($ENV{NUMBER_OF_PROCESSORS} // '') =~ /^\d+$/;
    if (open my $fh, '<', '/proc/cpuinfo') { my $n = grep { /^processor\s*:/ } <$fh>; close $fh; return $n if $n }
    4;
}
my $jobs = $o{j} // do { my $c = cpus(); $c > 8 ? 8 : $c };
$jobs = 1 if $jobs < 1;

# the slowest first (measured on the target Perl); anything new or unknown goes after these
my @slow = qw(status_metrics drills sysml-views sysml help halberd xmi2sysml reqif2sysml);
my %rank; @rank{@slow} = (1 .. @slow);
my $name = sub { (my $n = shift) =~ s{.*/|\.t$}{}g; $n };
@tests = sort { ($rank{ $name->($a) } // 99) <=> ($rank{ $name->($b) } // 99) || $a cmp $b } @tests;

my $tmp = tempdir(CLEANUP => 1);
my (%run, @queue, %res);
@queue = @tests;
my $t0 = time;
my $w = 0; $w = length($_) > $w ? length($_) : $w for @tests;
$| = 1;

while (@queue || %run) {
    while (@queue && keys(%run) < $jobs) {
        my $t = shift @queue;
        (my $log = "$tmp/$t.log") =~ s{tests/}{};
        my $pid = fork;
        die "fork failed: $!\n" unless defined $pid;
        if (!$pid) {
            open STDOUT, '>', $log or die "cannot write $log: $!\n";
            open STDERR, '>&', \*STDOUT or die "cannot redirect stderr: $!\n";
            exec $o{perl}, $t or die "cannot run $o{perl}: $!\n";
        }
        $run{$pid} = { test => $t, log => $log, start => time };
    }
    my $pid = waitpid(-1, 0);
    last if $pid <= 0;
    my $r = delete $run{$pid} or next;
    my $status = $? >> 8;
    open my $fh, '<', $r->{log} or die "cannot read $r->{log}: $!\n";
    my @lines = <$fh>; close $fh;
    my ($last) = grep { /\S/ } reverse @lines;
    $last //= '(no output)'; chomp $last;
    my $ok = $status == 0 && $last =~ /^#\s*all\b.*\bpassed/;
    $res{ $r->{test} } = { ok => $ok, last => $last, secs => time - $r->{start}, out => \@lines };
    printf "%-*s  %-32s %6.1fs%s\n", $w, $r->{test}, $last, time - $r->{start}, $ok ? '' : '   FAILED';
}

my @bad = grep { !$res{$_}{ok} } @tests;
if ($o{v}) {
    for my $t (@bad) { print "\n==== $t\n", grep { !/^ok\b/ } @{ $res{$t}{out} } }
}
printf "\n%d suites, %d failed, %.0fs with %d at a time%s\n", scalar(@tests), scalar(@bad), time - $t0, $jobs,
    @bad ? " -- failed: @bad" . ($o{v} ? '' : ' (rerun with -v for their output)') : '';
exit(@bad ? 1 : 0);
