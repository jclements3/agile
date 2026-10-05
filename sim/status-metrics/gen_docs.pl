#!/usr/bin/perl
# Generate documents from the model. Usage: gen_docs.pl SRC OUT
# Writes OUT/docs/<doc> for each name in SRC/docs/enabled.txt, and OUT/params/params.h
# when SRC/model/T/params.sysml exists. Output is deterministic (no dates).
# Part of the simulated repo of sim/status-metrics-sim.pl (copied into its tools/); core Perl, self-contained.
use strict;
use warnings;
use File::Path qw(make_path remove_tree);
my ($src, $out) = @ARGV;
die "usage: gen_docs.pl SRC OUT\n" unless defined $out;
my $PAT = qr/^\s*(part|port|interface|connection|action|item)( def)?\s+(\w+)/;
my $REQ = qr/^\s*requirement\s+(\w+)\s*\{(.*)\}/;
my $SAT = qr/^\s*satisfy\s+(\w+)\b/;
my $VER = qr/^\s*verify\s+(\w+)\b/;
my $IFC = qr/^\s*interface\s+(\w+)\s*\{(.*)\}/;
my $THR = qr/^\s*metadata\s+(\w+)\s*:\s*Threat\s*\{(.*)\}/;
my $PRM = qr/^\s*attribute\s+(\w+)\s*:/;
sub attrs { my ($t) = @_; my %a; while ($t =~ /(\w+)\s*=\s*"([^"]*)"/g) { $a{$1} = $2 } return \%a }
sub walk {                                    # *.sysml under a dir, sorted by path, dot entries skipped (glob '**')
    my ($dir, $acc) = @_;
    opendir my $dh, $dir or return;
    for my $e (sort grep { !/^\./ } readdir $dh) { my $p = "$dir/$e"; if (-d $p) { walk($p, $acc) } elsif (-f $p && $e =~ /\.sysml$/) { push @$acc, $p } }
    closedir $dh;
}
sub lines { my ($p) = @_; open my $fh, '<:raw', $p or die "$p: $!\n"; local $/; my $t = <$fh> // ''; close $fh; my @l = split /\r\n|\r|\n/, $t, -1; pop @l if @l && $l[-1] eq ''; @l }
my (%els, %reqs, %sat, %ver, %ifcs, %thr, @prm);
my @files;
walk("$src/model", \@files);
for my $p (sort @files) {
    my ($seg) = substr($p, length("$src/model/")) =~ m{^([^/]+)};
    for my $line (lines($p)) {
        $els{$3} = $seg if $line =~ $PAT;
        $reqs{$1} = attrs($2)->{doorsId} // '' if $line =~ $REQ;
        $sat{$1} = 1 if $line =~ $SAT;
        $ver{$1} = 1 if $line =~ $VER;
        $ifcs{$1} = attrs($2) if $line =~ $IFC;
        $thr{$1} = attrs($2) if $line =~ $THR;
        push @prm, $1 if $seg eq 'T' && $p =~ /params\.sysml$/ && $line =~ $PRM;
    }
}
remove_tree($out);
make_path("$out/docs");
my $en = "$src/docs/enabled.txt";
my @enabled = -e $en ? grep { $_ ne '' } map { (my $l = $_) =~ s/^\s+|\s+$//g; $l } lines($en) : ();
sub w { my ($name, @l) = @_; open my $fh, '>:raw', "$out/docs/$name" or die "$out/docs/$name: $!\n"; print {$fh} join("\n", @l) . "\n"; close $fh }
for my $d (@enabled) {
    if ($d eq 'interface_table.csv') {
        w($d, 'id,from,to,secReq', map { my $v = $ifcs{$_}; "$_,$v->{fromSeg},$v->{toSeg}," . ($v->{secReq} // '') } sort keys %ifcs);
    }
    elsif ($d eq 'icd.csv') {
        w($d, 'id,from,to,fromZone,toZone,signal,rate,units',
          map { my $v = $ifcs{$_}; join ',', $_, @$v{qw(fromSeg toSeg fromZone toZone signal rate units)} } sort keys %ifcs);
    }
    elsif ($d eq 'req_trace.csv') {
        w($d, 'req,doorsId,satisfied,verified', map { "$_,$reqs{$_}," . ($sat{$_} ? 1 : 0) . ',' . ($ver{$_} ? 1 : 0) } sort keys %reqs);
    }
    elsif ($d eq 'element_index.txt') { w($d, map { "$_ $els{$_}" } sort keys %els) }
    elsif ($d eq 'threat_register.csv') {
        w($d, 'threat,mitigation', map { "$_," . ($thr{$_}{mitigation} // '') } sort keys %thr);
    }
    elsif ($d =~ /^seg_/) {
        my $s = (split /\./, substr($d, 4))[0] // '';
        w($d, sort grep { $els{$_} eq $s } keys %els);
    }
}
if (@prm) {
    make_path("$out/params");
    open my $fh, '>:raw', "$out/params/params.h" or die "$out/params/params.h: $!\n";
    print {$fh} map { '#define ' . uc($_) . " 0\n" } @prm;
    close $fh;
}
