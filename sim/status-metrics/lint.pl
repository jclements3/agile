#!/usr/bin/perl
# Minimal model lint for the simulation. Prints: elements=N errors=E warnings=W
# Part of the simulated repo of sim/status-metrics-sim.pl (copied into its tools/); core Perl, self-contained.
use strict;
use warnings;
my $PAT = qr/^\s*(part|port|interface|connection|action|item)( def)?\s+(\w+)/;
my $REQ = qr/^\s*requirement\s+(\w+)\s*\{(.*)\}/;
my $REF = qr/^\s*(satisfy|verify)\s+(\w+)\b/;
my $root = $ARGV[0] // 'model';
sub walk {
    my ($dir, $acc) = @_;
    opendir my $dh, $dir or return;
    for my $e (sort grep { !/^\./ } readdir $dh) { my $p = "$dir/$e"; if (-d $p) { walk($p, $acc) } elsif (-f $p && $e =~ /\.sysml$/) { push @$acc, $p } }
    closedir $dh;
}
my (%names, %reqs, @refs);
my ($errors, $warnings) = (0, 0);
my @files;
walk($root, \@files);
for my $p (sort @files) {
    open my $fh, '<:raw', $p or die "$p: $!\n";
    my $n = 0;
    while (my $line = <$fh>) {
        $n++;
        $line =~ s/\r?\n\z//;
        if ($line =~ $PAT) {
            if ($names{$3}) { $errors++; print "$p:$n: E-DUP duplicate element $3\n" }
            $names{$3} = 1;
        }
        if ($line =~ $REQ) {
            my ($r, $body) = ($1, $2);
            $reqs{$r} = 1;
            if (index($body, 'doorsId') < 0) { $warnings++; print "$p:$n: W-REQ requirement $r has no doorsId\n" }
        }
        push @refs, [ $p, $n, $2 ] if $line =~ $REF;
    }
    close $fh;
}
for (@refs) { my ($p, $n, $ref) = @$_; next if $reqs{$ref}; $errors++; print "$p:$n: E-REF unknown requirement $ref\n" }
printf "elements=%d errors=%d warnings=%d\n", scalar(keys %names), $errors, $warnings;
exit($errors || $warnings ? 1 : 0);
