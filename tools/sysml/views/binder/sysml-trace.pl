#!/usr/bin/perl
# sysml-trace.pl DIR : every leaf requirement usage satisfied (itself or a group above it)
# and verified (itself or a group above it). Prints a matrix and GNU-format errors.
use strict; use warnings; use File::Find;
my $dir = shift // 'model'; my (@files, %req, %sat, %ver);
find(sub { push @files, $File::Find::name if /\.sysml$/ }, $dir);
for my $f (sort @files) {
    open my $h, '<:encoding(UTF-8)', $f or die; local $/; my $t = <$h>;
    $t =~ s{//[^\n]*}{}g; $t =~ s{/\*.*?\*/}{ my $c = $&; $c =~ tr/\n//cd; $c }gse;
    my (@stack, $depth); $depth = 0; my $line = 1;
    while ($t =~ /\G(?:(\n)|(\{)|(\})|requirement\s+(?!def\b)(?:<'([^']+)'>\s*)?(\w+)\b|satisfy\s+(?:requirement\s+\w+\s*:\s*)?([\w.:]+)\s+by|verify\s+(?:requirement\s+)?([\w.:]+)|.)/gs) {
        if ($1) { $line++ } elsif ($2) { $depth++ }
        elsif ($3) { pop @stack while @stack && $stack[-1][1] >= $depth; $depth-- }
        elsif (defined $5) { my $path = join '.', (map { $_->[0] } @stack), $5;
            $req{$path} = { id => $4 // '', file => $f, line => $line };
            push @stack, [$5, $depth + 1] }
        elsif ($6) { (my $p = $6) =~ s/.*:://; $sat{$p} = 1 }
        elsif ($7) { (my $p = $7) =~ s/.*:://; $ver{$p} = 1 }
    }
}
my ($bad, $n) = (0, 0);
sub covered { my ($p, $set) = @_; my @s = split /\./, $p;
    for my $i (reverse 0 .. $#s) { my $q = join '.', @s[0 .. $i]; return 1 if $set->{$q} || $set->{$s[$i]} && $i == 0 } 0 }
for my $p (sort keys %req) {
    next if grep { /^\Q$p\E\./ } keys %req;            # groups: judged by their leaves
    $n++; my $r = $req{$p}; my @miss;
    if ($r->{id} =~ /^N-/) { printf "%-16s %-45s %s\n", $r->{id}, $p, "need (traced by derivation)"; next }
    push @miss, 'not satisfied' unless covered($p, \%sat);
    push @miss, 'not verified'  unless covered($p, \%ver);
    printf "%-16s %-45s %s\n", $r->{id}, $p, @miss ? join(', ', @miss) : 'ok';
    if (@miss) { $bad++; print "$r->{file}:$r->{line}: error: requirement $p ", join(', ', @miss), "\n" }
}
print "trace: $n leaf requirement(s), $bad with gaps\n"; exit($bad ? 1 : 0);
