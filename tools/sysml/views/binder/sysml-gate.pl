#!/usr/bin/perl
# sysml-gate.pl DIR : text-level checks for a SysML v2 model, GNU-format diagnostics.
use strict; use warnings; use File::Find;
my $dir = shift // 'model'; my (@files, $err, $warn);
find(sub { push @files, $File::Find::name if /\.sysml$/ }, $dir);
my %KW = map { $_ => 1 } qw(frame objective analysis variant variation filter render expose
  event message then first end in out inout default meta all abstract subject actor
  stakeholder assume require return language rep);
sub diag { my ($f, $n, $sev, $msg) = @_; print "$f:$n: $sev: $msg\n";
           $sev eq 'error' ? $err++ : $warn++ }
for my $f (sort @files) {
    open my $h, '<:encoding(UTF-8)', $f or die "$f: $!";
    my ($n, $depth, $incomment, $prev) = (0, 0, 0, '');
    while (my $line = <$h>) {
        $n++;
        (my $code = $line) =~ s{//.*$}{};                 # drop // notes
        $code =~ s{"(?:[^"\\]|\\.)*"}{""}g;               # blank strings
        if ($incomment) { next unless $code =~ s{^.*?\*/}{}; $incomment = 0 }
        $code =~ s{/\*.*?\*/}{}g;
        $incomment = 1 if $code =~ s{/\*.*$}{};
        diag($f, $n, 'error', 'import without private/public')
            if $code =~ /^\s*import\s/;
        diag($f, $n, 'error', "keyword '$1' used as a name")
            if $code =~ /\b(?:part|attribute|item|port|action|state|calc)\s+(?:def\s+)?(\w+)\b/ && $KW{$1};
        diag($f, $n, 'error', 'quantity without a unit')
            if $code =~ /:\s*\w+Value\s*(?:=|default|:=)\s*-?[\d.]+(?:[eE][-+]?\d+)?\s*;/;
        diag($f, $n - 1, 'warning', 'requirement without doc')
            if $prev =~ /^\s*requirement\b(?!\s+def\b)[^;]*\{\s*$/ && $code !~ /\bdoc\b|\@/;
        $depth += () = $code =~ /\{/g; $depth -= () = $code =~ /\}/g;
        $prev = $code;
    }
    diag($f, $n, 'error', "unbalanced braces ($depth)") if $depth;
}
printf "%d file(s): %d error(s), %d warning(s)\n", scalar @files, $err // 0, $warn // 0;
exit(($err // 0) || ($warn // 0) ? 1 : 0);
