#!/usr/bin/perl
# sysml-pkg-svg.pl : package dependencies and SecMeta markings of a SysML v2 model, as one SVG,
# with the marking checks (SEC-4) printed in GNU format. Core Perl 5 only.
#
#   perl sysml-pkg-svg.pl [-o packages.svg] [--title T] [--nested] [--levels U,CUI,ITAR] DIR|FILE...
#
#   --nested      draw nested packages as their own boxes (default: rolled up into root packages)
#   --hide P,Q    leave these packages (and their edges) out of the picture; still checked
#   --levels L    marking levels, lowest first (default: the Level enumeration found in the
#                 model, e.g. SecMeta's `enum def Level { enum U; enum CUI; enum ITAR; }`)
#
# Checks (the binder's marking rules):
#   error    root package without @Marking
#   error    no write-down: a lower-marked package imports, references or specializes a
#            higher-marked package or element (effective marking = highest of the element's
#            own and every enclosing package's or definition's)
#   warning  text leakage: a higher-marked element's name appears in a lower package's text
#   warning  package dependency cycle
# Exit status: 0 no errors, 1 errors, 2 usage error.
use strict; use warnings;
use File::Find; use Getopt::Long;
binmode STDOUT, ':encoding(UTF-8)'; binmode STDERR, ':encoding(UTF-8)';

my %O = (o => 'packages.svg');
GetOptions(\%O, 'o=s', 'title=s', 'nested', 'levels=s', 'hide=s') && @ARGV
    or do { print STDERR "usage: perl sysml-pkg-svg.pl [-o packages.svg] [--title T] [--nested] [--hide P,Q] [--levels U,CUI,ITAR] DIR|FILE...\n"; exit 2 };
my %HIDE = map { $_ => 1 } split /,/, $O{hide} // '';

my @files;
for my $a (@ARGV) {
    if (-d $a) { find(sub { push @files, $File::Find::name if /\.sysml$/ }, $a) }
    elsif (-f $a) { push @files, $a }
    else { print STDERR "sysml-pkg-svg: $a: no such file or directory\n"; exit 2 }
}
@files = sort @files;

my $NAME = qr/(?:[A-Za-z_]\w*|'(?:[^'\\]|\\.)*')/;
my $REF  = qr/$NAME(?:\s*::\s*$NAME)*/;
sub unq { my $n = shift; return $n unless $n =~ /^'(.*)'$/s; (my $u = $1) =~ s/\\(.)/$1/g; $u }
sub segs { my $r = shift; my @s; push @s, unq($1) while $r =~ /\G\s*($NAME)\s*(?:::|\.)?/g; @s }
my %KW = map { $_ => 1 } qw(about abstract accept action actor after alias all allocate allocation analysis and as
    assert assign assume at attribute bind binding by calc case comment concern connect connection constant
    constraint crosses decide def default defined dependency derived do doc else end entry enum event exhibit
    exit expose false filter first flow for fork frame from hastype if implies import in include individual
    inout interface istype item join language library locale loop merge message meta metadata nonunique not
    null objective occurrence of or ordered out package parallel part perform port private protected public
    redefines ref references render rendering rep require requirement return satisfy send snapshot specializes
    stakeholder standard state subject subsets succession terminate then timeslice to transition true until
    use variant variation verification verify via view viewpoint when while xor);
my $DECL = qr/(?:part|item|port|attribute|requirement|action|calc|constraint|enum|interface|connection|
    verification|analysis|metadata|view|viewpoint|concern|state|occurrence|flow|allocation|rendering|case|
    use\s+case|individual|connector|binding|succession)/x;

# ------------------------------------------------------------------------------------------
# Parse
# ------------------------------------------------------------------------------------------
my (%P, @porder, %E, @levels_found);     # packages by qname; elements by qname
for my $f (@files) {
    open my $h, '<:encoding(UTF-8)', $f or die "$f: $!";
    local $/; my $t = <$h>;
    my @stack = ({ kind => 'file' });
    my ($head, $hline, $line) = ('', 1, 1);
    my $pkg = sub { for (reverse @stack) { return $_->{p} if $_->{p} } undef };
    my $elem = sub { for (reverse @stack) { return $_->{e} if $_->{e}; return undef if $_->{p} } undef };
    my $text = sub {        # words of names and doc text, for the leakage check
        my ($s, $ln) = @_; my $p = $pkg->() or return;
        push @{$p->{words}}, [$1, $ln] while $s =~ /\b([A-Za-z_]\w{3,})\b/g;
    };
    pos($t) = 0;
    while (pos($t) < length $t) {
        if ($t =~ /\G\n/gc) { $line++; $head .= ' ' }
        elsif ($t =~ m{\G//([^\n]*)}gc) { $text->($1, $line) }
        elsif ($t =~ m{\G/\*}gc) {
            my $from = pos($t); my $end = index($t, '*/', $from); $end = length $t if $end < 0;
            my $body = substr($t, $from, $end - $from); pos($t) = $end + 2;
            $text->($body, $line);
            $line += ($body =~ tr/\n//);
            $head = '' if $head =~ /^\s*(?:doc|comment)\b/;
        }
        elsif ($t =~ /\G("(?:[^"\\]|\\.)*")/gc) { my $q = $1; $text->($q, $line); $hline = $line if $head !~ /\S/; $head .= '""'; $line += ($q =~ tr/\n//) }
        elsif ($t =~ /\G('(?:[^'\\]|\\.)*')/gc) { my $q = $1; $hline = $line if $head !~ /\S/; $head .= $q }
        elsif ($t =~ /\G([{};])/gc) {
            my $c = $1;
            if ($c eq '}') { pop @stack if @stack > 1; $head = ''; next }
            my $s = $head; $head = '';
            $s =~ s/\s+/ /g; $s =~ s/^ | $//g;
            my $scope = { kind => 'other' };
            my $p = $pkg->();
            if ($s =~ /^(?:(?:standard\s+)?(library)\s+)?package\s+($NAME)/) {
                my ($lib, $n) = ($1, unq($2));
                my $q = $p ? "$p->{qname}::$n" : $n;
                my $np = $P{$q} //= { name => $n, qname => $q, parent => $p, file => $f, line => $hline, lib => $lib ? 1 : 0,
                                      members => {}, imports => [], refs => [], words => [], ndef => 0, nreq => 0 };
                push @porder, $np unless $np->{seen}++;
                $p->{members}{$n} //= { name => $n, qname => $q, pkg => $p, ispkg => 1 } if $p;
                $scope = { kind => 'package', p => $np };
            }
            elsif ($s =~ /^@\s*(?:SecMeta::)?Marking\b/ || $s =~ /^metadata\s+(?:SecMeta::)?Marking\b/) {
                my $target = $elem->() // $p;
                $scope = { kind => 'marking', target => $target, file => $f, line => $hline };
                if ($s =~ /level\s*=\s*(?:\w+::)*(\w+)/) { $target->{marking} = $1; $target->{mline} = $hline if $target }
            }
            elsif ($stack[-1]{kind} eq 'marking' && $s =~ /^(?::>>\s*)?level\s*=\s*(?:\w+::)*(\w+)/) {
                my $tg = $stack[-1]{target};
                if ($tg) { $tg->{marking} = $1; $tg->{mline} = $stack[-1]{line} }
            }
            elsif ($s =~ /^enum\s+def\s+Level\b/) { $scope = { kind => 'levels' } }
            elsif ($stack[-1]{kind} eq 'levels' && $s =~ /^(?:enum\s+)?($NAME)$/) { push @levels_found, unq($1) unless grep { $_ eq unq($1) } @levels_found }
            elsif ($p && $s =~ /^(?:(public|private|protected)\s+)?import\s+(?:all\s+)?($REF)\s*(::\s*\*\*|::\s*\*)?/) {
                my ($vis, $r, $star) = ($1 // 'private', $2, $3 // '');
                push @{$p->{imports}}, { segs => [segs($r)], star => ($star =~ /\*\*/ ? '**' : $star ? '*' : ''), vis => $vis, file => $f, line => $hline, text => $s };
            }
            elsif ($p && $s ne '') {
                my $s2 = $s;
                $s2 =~ s/^(?:(?:public|private|protected|abstract|variation|individual|derived|readonly|in|out|inout|ref|end)\s+)*//;
                $s2 =~ s/^(?:#\s*$NAME\s*)+//;
                if ($s2 =~ /^($DECL)\s+(def\s+)?(?:<'[^']*'>\s*)?($NAME)/) {
                    my ($kw, $isdef, $n) = ($1, $2, unq($3));
                    my $owner = $elem->();
                    my $q = ($owner ? $owner->{qname} : $p->{qname}) . "::$n";
                    my $e = $E{$q} //= { name => $n, qname => $q, pkg => $p, owner => $owner, file => $f, line => $hline };
                    $p->{members}{$n} //= $e unless $owner;
                    $p->{ndef}++ if $isdef;
                    $p->{nreq}++ if $kw eq 'requirement' && !$isdef;
                    $scope = { kind => 'elem', e => $e } if $c eq '{';
                }
                # references: qualified names, and plain identifiers (resolved later through imports)
                (my $body = $s) =~ s/'(?:[^'\\]|\\.)*'/ /g;
                while ($s =~ /($REF)/g) {
                    my $r = $1; my @sg = segs($r);
                    if (@sg > 1) { push @{$p->{refs}}, { segs => \@sg, file => $f, line => $hline, qual => 1 } }
                    elsif (!$KW{$sg[0]}) { push @{$p->{refs}}, { segs => \@sg, file => $f, line => $hline, qual => 0 } }
                }
                $text->($s, $hline);
            }
            push @stack, $scope if $c eq '{';
        }
        elsif ($t =~ m{\G([^{};"'/\n]+|/)}gc) { my $x = $1; $hline = $line if $head !~ /\S/ && $x =~ /\S/; $head .= $x }
    }
}

# ------------------------------------------------------------------------------------------
# Levels, effective markings, resolution
# ------------------------------------------------------------------------------------------
my @LEVELS = $O{levels} ? split(/,/, $O{levels}) : @levels_found ? @levels_found : qw(U CUI ITAR);
my %RANK = map { $LEVELS[$_] => $_ } 0 .. $#LEVELS;
my ($NERR, $NWARN, @DIAG) = (0, 0);
sub diag { my ($f, $l, $sev, $m) = @_; push @DIAG, [$f, $l, scalar @DIAG, "$f:$l: $sev: $m"]; $sev eq 'error' ? $NERR++ : $NWARN++ }
for my $x (@porder, (map { $E{$_} } sort keys %E)) {
    if (defined $x->{marking} && !defined $RANK{$x->{marking}}) {
        diag($x->{file}, $x->{mline} // $x->{line}, 'error', "unknown marking level '$x->{marking}' on '$x->{qname}' (levels: @LEVELS)");
        delete $x->{marking};
    }
}
sub rank_of {           # effective rank: max over the element and everything enclosing it
    my $x = shift; my $r = -1;
    for (my $o = $x; $o; $o = $o->{owner} // $o->{parent} // ($o->{pkg} && $o->{pkg} != $o ? $o->{pkg} : undef)) {
        $r = $RANK{$o->{marking}} if defined $o->{marking} && $RANK{$o->{marking}} > $r;
    }
    return $r;
}
sub lvl { $_[0] < 0 ? 'unmarked' : $LEVELS[$_[0]] }
sub root_of { my $p = shift; $p = $p->{parent} while $p->{parent}; $p }
sub node_of { $O{nested} ? $_[0] : root_of($_[0]) }

# resolve a qualified name to a package or an element (longest package prefix, then members)
sub resolve_q {
    my @s = @{$_[0]};
    for my $i (reverse 0 .. $#s) {
        my $q = join '::', @s[0 .. $i];
        next unless $P{$q};
        return $P{$q} if $i == $#s;
        my $e = $E{join '::', @s} // $P{$q}{members}{$s[$i + 1]};
        return $e // $P{$q};
    }
    return undef;
}

for my $p (@porder) { $p->{rank} = rank_of($p) }
# root marking rule
for my $p (grep { !$_->{parent} } @porder) {
    diag($p->{file}, $p->{line}, 'error', "root package '$p->{qname}' has no \@Marking") unless defined $p->{marking};
}

# dependencies between nodes, with write-down checks
my (%DEP);              # "from\0to" => { from, to, imports => [...], refs => n, bad => [...] }
sub dep {
    my ($from, $to, $kind, $x) = @_;
    my ($a, $b) = (node_of($from), node_of($to));
    return if $a == $b;
    my $d = $DEP{"$a->{qname}\0$b->{qname}"} //= { from => $a, to => $b, imports => [], refs => 0, bad => [], at => [$x->{file}, $x->{line}] };
    $kind eq 'import' ? push(@{$d->{imports}}, "$x->{file}:$x->{line}: $x->{text}") : $d->{refs}++;
    return $d;
}
my %reported;
sub check_write_down {
    my ($p, $target, $x, $how) = @_;
    my ($pr, $tr) = ($p->{rank}, rank_of($target));
    return if $pr < 0;          # unmarked: the root-marking error already says so
    return unless $tr > $pr;
    my $what = $target->{ispkg} || $P{$target->{qname}} ? 'package' : 'element';
    my $msg = sprintf "%s package '%s' %s %s %s '%s'", lvl($pr), $p->{qname}, $how, lvl($tr), $what, $target->{qname};
    return if $reported{"$x->{file}:$x->{line}:$msg"}++;
    diag($x->{file}, $x->{line}, 'error', $msg);
    return 1;
}
my %visible;            # package qname -> { name => target } through imports
for my $p (@porder) {
    my %vis;
    for my $i (@{$p->{imports}}) {
        my $t = resolve_q($i->{segs});
        next unless $t;                                   # a library outside the model (ISQ, SI, ...)
        my $tp = $P{$t->{qname}} ? $P{$t->{qname}} : $t->{pkg};
        my $d = dep($p, $tp, 'import', $i);
        my $bad = check_write_down($p, $t, $i, 'imports');
        push @{$d->{bad}}, "imports $t->{qname}" if $bad && $d;
        if ($i->{star} && $P{$t->{qname}}) {
            my @q = ($P{$t->{qname}});
            while (my $q = shift @q) {
                $vis{$_} //= $q->{members}{$_} for keys %{$q->{members}};
                push @q, grep { $_->{parent} && $_->{parent} == $q } @porder if $i->{star} eq '**';
            }
        } elsif (!$i->{star}) { $vis{$t->{name}} //= $t }
    }
    $visible{$p->{qname}} = \%vis;
}
for my $p (@porder) {
    my $vis = $visible{$p->{qname}};
    # names visible through enclosing packages' imports too
    for (my $o = $p->{parent}; $o; $o = $o->{parent}) { my $v = $visible{$o->{qname}}; $vis->{$_} //= $v->{$_} for keys %$v }
    for my $r (@{$p->{refs}}) {
        my $t;
        if ($r->{qual}) { $t = resolve_q($r->{segs}) }
        else {
            my $n = $r->{segs}[0];
            next if $p->{members}{$n};                          # own member
            my $own = 0; for (my $o = $p->{parent}; $o; $o = $o->{parent}) { if ($o->{members}{$n}) { $own = 1; last } }
            next if $own;
            $t = $vis->{$n};
        }
        next unless $t && $t != $p;
        my $tp = $P{$t->{qname}} ? $P{$t->{qname}} : $t->{pkg};
        next if !$tp || root_of($tp) == root_of($p) && !$O{nested} && rank_of($t) <= $p->{rank};
        my $d = dep($p, $tp, 'ref', $r);
        my $bad = check_write_down($p, $t, $r, 'references');
        push @{$d->{bad}}, "references $t->{qname}" if $bad && $d;
    }
}
# text leakage
my %hiname;     # name -> [rank, qname] of marked elements
for my $e (map { $E{$_} } sort keys %E) { my $r = rank_of($e); $hiname{$e->{name}} = [$r, $e->{qname}] if $r > 0 && length $e->{name} >= 4 && (!$hiname{$e->{name}} || $hiname{$e->{name}}[0] < $r) }
for my $p (@porder) {
    my %seen;
    for my $w (@{$p->{words}}) {
        my $h = $hiname{$w->[0]} or next;
        next unless $h->[0] > $p->{rank};
        next if $p->{members}{$w->[0]} || $seen{$w->[0]}++;
        next if grep { /^\Q$p->{file}\E:\d+: error: .* '\Q$h->[1]\E'$/ } map { $_->[3] } @DIAG;
        diag($p->{file}, $w->[1], 'warning', sprintf("text in %s package '%s' names %s element '%s'", lvl($p->{rank}), $p->{qname}, lvl($h->[0]), $h->[1]));
    }
}

# ------------------------------------------------------------------------------------------
# Graph layout: cycles, layers (providers on the right), ordering by barycenter
# ------------------------------------------------------------------------------------------
my $ndep = keys %DEP;
my $wd = grep { @{$_->{bad}} } (map { $DEP{$_} } sort keys %DEP);
for my $k (keys %DEP) { delete $DEP{$k} if $HIDE{$DEP{$k}{from}{qname}} || $HIDE{$DEP{$k}{to}{qname}} }
my @N = grep { ($O{nested} || !$_->{parent}) && !$HIDE{$_->{qname}} } @porder;
my %out; push @{$out{$_->{from}{qname}}}, $_ for (map { $DEP{$_} } sort keys %DEP);
# break cycles with a DFS; back edges are drawn as such and reported
my (%state, @back);
my $dfs; $dfs = sub {
    my $n = shift; $state{$n->{qname}} = 1;
    for my $d (sort { $a->{to}{qname} cmp $b->{to}{qname} } @{$out{$n->{qname}} // []}) {
        my $s = $state{$d->{to}{qname}} // 0;
        if ($s == 1) { $d->{back} = 1; push @back, $d }
        elsif ($s == 0) { $dfs->($d->{to}) }
    }
    $state{$n->{qname}} = 2;
};
$dfs->($_) for grep { !$state{$_->{qname}} } @N;
for my $d (@back) {
    diag(@{$d->{at}}, 'warning', "package dependency cycle: '$d->{from}{qname}' depends on '$d->{to}{qname}', which depends back on it" . ' (directly or through other packages)');
}
my %layer;
my $lay; $lay = sub {
    my $n = shift;
    return $layer{$n->{qname}} if defined $layer{$n->{qname}};
    $layer{$n->{qname}} = 0;
    my $l = 0;
    for my $d (grep { !$_->{back} } @{$out{$n->{qname}} // []}) { my $x = $lay->($d->{to}) + 1; $l = $x if $x > $l }
    return $layer{$n->{qname}} = $l;
};
$lay->($_) for @N;
my ($maxl) = sort { $b <=> $a } 0, values %layer;
# dummy nodes for edges that span more than one layer
my @cols; push @{$cols[$maxl - $layer{$_->{qname}}]}, $_ for @N;
my %pos;
for my $d (grep { !$_->{back} } (map { $DEP{$_} } sort keys %DEP)) {
    my ($a, $b) = ($maxl - $layer{$d->{from}{qname}}, $maxl - $layer{$d->{to}{qname}});
    $d->{via} = [];
    for my $c ($a + 1 .. $b - 1) { my $v = { dummy => 1, qname => "~$d->{from}{qname}>$d->{to}{qname}#$c" }; push @{$cols[$c]}, $v; push @{$d->{via}}, $v }
}
@{$cols[$_]} = sort { ($a->{dummy} // 0) <=> ($b->{dummy} // 0) || $a->{qname} cmp $b->{qname} } @{$cols[$_] // []} for 0 .. $#cols;
my %nbr;       # neighbors across adjacent columns, including dummies
for my $d (grep { !$_->{back} } (map { $DEP{$_} } sort keys %DEP)) {
    my @chain = ($d->{from}, @{$d->{via}}, $d->{to});
    for my $i (0 .. $#chain - 1) { push @{$nbr{$chain[$i]{qname}}{r}}, $chain[$i + 1]; push @{$nbr{$chain[$i + 1]{qname}}{l}}, $chain[$i] }
}
sub reindex { for my $c (@cols) { $pos{$c->[$_]{qname}} = $_ for 0 .. $#$c } }
reindex();
for my $sweep (1 .. 8) {
    my @order = $sweep % 2 ? (1 .. $#cols) : reverse(0 .. $#cols - 1);
    my $side = $sweep % 2 ? 'l' : 'r';
    for my $c (@order) {
        my %bc;
        for my $n (@{$cols[$c]}) {
            my @p = map { $pos{$_->{qname}} } @{$nbr{$n->{qname}}{$side} // []};
            my $s = 0; $s += $_ for @p;
            $bc{$n->{qname}} = @p ? $s / @p : $pos{$n->{qname}};
        }
        @{$cols[$c]} = sort { $bc{$a->{qname}} <=> $bc{$b->{qname}} || $pos{$a->{qname}} <=> $pos{$b->{qname}} } @{$cols[$c]};
        reindex();
    }
}

# ------------------------------------------------------------------------------------------
# Geometry
# ------------------------------------------------------------------------------------------
my ($CW, $FS, $SFS, $LH, $PADX, $COLGAP, $VGAP, $TOP, $PAD) = (7.2, 12, 10.5, 15, 10, 110, 22, 92, 16);
sub tw { length($_[0]) * $CW }
sub stw { length($_[0]) * $CW * $SFS / $FS }
my %maxin;
for my $x ((map { $E{$_} } sort keys %E), @porder) {
    my $node = node_of($P{$x->{qname}} ? $x : $x->{pkg});
    my $r = rank_of($x);
    $maxin{$node->{qname}} = $r if $r > ($maxin{$node->{qname}} // -1);
}
for my $n (@N) {
    my $max = $maxin{$n->{qname}} // -1;
    $n->{inside} = $max > $n->{rank} ? $max : undef;
    $n->{l1} = $n->{qname};
    $n->{l2} = $n->{lib} ? "\x{ab}library\x{bb} " : '';
    $n->{l2} .= defined $n->{marking} ? "\@Marking $n->{marking}" : ($n->{parent} ? 'inherits ' . lvl($n->{rank}) : 'NO MARKING');
    $n->{l3} = ($n->{inside} ? 'contains ' . lvl($n->{inside}) . '; ' : '') . "$n->{ndef} def(s)" . ($n->{nreq} ? ", $n->{nreq} req(s)" : '');
    unless ($O{nested}) {           # rolled-up counts
        for my $q (grep { $_ != $n && root_of($_) == $n } @porder) { $n->{rdef} += $q->{ndef}; $n->{rreq} += $q->{nreq}; $n->{nsub}++ }
        $n->{l3} = ($n->{inside} ? 'contains ' . lvl($n->{inside}) . '; ' : '') . ($n->{ndef} + ($n->{rdef} // 0)) . ' def(s)'
            . (($n->{nreq} + ($n->{rreq} // 0)) ? ', ' . ($n->{nreq} + ($n->{rreq} // 0)) . ' req(s)' : '')
            . ($n->{nsub} ? ", $n->{nsub} nested pkg(s)" : '');
    }
    my ($w) = sort { $b <=> $a } tw($n->{l1}), stw($n->{l2}), stw($n->{l3});
    $n->{w} = $w + 2 * $PADX; $n->{h} = 8 + 3 * $LH + 4;
}
my @colx = ($PAD);
my @colw = map { my ($w) = sort { $b <=> $a } 0, map { $_->{w} // 0 } @{$cols[$_] // []}; $w } 0 .. $#cols;
push @colx, $colx[-1] + $colw[$_ - 1] + $COLGAP for 1 .. $#cols;
my $H = $TOP;
for my $c (0 .. $#cols) {
    my $y = $TOP;
    for my $n (@{$cols[$c]}) {
        if ($n->{dummy}) { $n->{x} = $colx[$c]; $n->{w} = $colw[$c]; $n->{y} = $y; $n->{h} = 10; $y += 10 + $VGAP / 2; next }
        $n->{x} = $colx[$c] + ($colw[$c] - $n->{w}) / 2; $n->{y} = $y; $y += $n->{h} + $VGAP;
    }
    $H = $y if $y > $H;
}
# centre short columns vertically
for my $c (0 .. $#cols) {
    my @c = @{$cols[$c] // []}; next unless @c;
    my $span = $c[-1]{y} + $c[-1]{h} - $TOP; my $dy = ($H - $VGAP - $TOP - $span) / 2;
    $_->{y} += $dy for @c;
}
my $W = $colx[-1] + $colw[-1] + $PAD; $W = 720 if $W < 720;
$H += 40 + ($#back >= 0 ? 30 : 0);

# ------------------------------------------------------------------------------------------
# Draw
# ------------------------------------------------------------------------------------------
sub esc { my $s = shift // ''; $s =~ s/&/&amp;/g; $s =~ s/</&lt;/g; $s =~ s/>/&gt;/g; $s =~ s/"/&quot;/g; $s }
my @PAL = ('#e8f5e9', '#fff8e1', '#ffe0b2', '#ffccbc', '#f8bbd0', '#e1bee7', '#d1c4e9');
my @PALL = ('#2e7d32', '#f9a825', '#ef6c00', '#d84315', '#ad1457', '#6a1b9a', '#4527a0');
my %C = (ink => '#212121', dim => '#616161', edge => '#90a4ae', bad => '#c62828', back => '#ef6c00', none => '#ffffff');
my @o;
push @o, qq{<?xml version="1.0" encoding="UTF-8"?>},
  qq{<svg xmlns="http://www.w3.org/2000/svg" width="$W" height="$H" viewBox="0 0 $W $H" font-family="DejaVu Sans Mono, Consolas, Menlo, monospace" font-size="$FS">},
  qq{<!-- generated by sysml-pkg-svg.pl from } . (esc(join ' ', @ARGV) =~ s/-(?=-)/- /gr) . qq{ -->},
  qq{<defs><marker id="ar" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse"><path d="M0 0 L10 5 L0 10 z" fill="$C{edge}"/></marker>},
  qq{<marker id="arb" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse"><path d="M0 0 L10 5 L0 10 z" fill="$C{bad}"/></marker>},
  qq{<marker id="arc" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse"><path d="M0 0 L10 5 L0 10 z" fill="$C{back}"/></marker></defs>},
  qq{<rect width="100%" height="100%" fill="#ffffff"/>};
my $sum = sprintf '%d file(s): %d error(s), %d warning(s), %d package(s), %d dependenc%s, %d write-down edge(s), %d cycle(s)',
    scalar @files, $NERR, $NWARN, scalar keys %P, $ndep, $ndep == 1 ? 'y' : 'ies', $wd, scalar @back;
push @o, qq{<text x="$PAD" y="26" font-size="16" font-weight="bold" fill="$C{ink}">} . esc($O{title} // 'Packages and markings') . '</text>',
  qq{<text x="$PAD" y="46" fill="$C{dim}">} . esc($sum . ($O{hide} ? "; not drawn: $O{hide}" : '')) . '</text>';
# legend: levels low to high, then edge kinds
my $lx = $PAD; my $ly = 60;
push @o, qq{<g font-size="11" fill="$C{dim}">};
for my $i (0 .. $#LEVELS) {
    push @o, qq{<rect x="$lx" y="$ly" width="22" height="13" fill="$PAL[$i % @PAL]" stroke="$PALL[$i % @PALL]"/><text x="} . ($lx + 28) . qq{" y="} . ($ly + 11) . '">' . esc($LEVELS[$i]) . '</text>';
    $lx += 40 + stw($LEVELS[$i]);
}
push @o, qq{<rect x="$lx" y="$ly" width="22" height="13" fill="#ffffff" stroke="$C{bad}" stroke-dasharray="3 2"/><text x="} . ($lx + 28) . qq{" y="} . ($ly + 11) . '">no marking</text>';
$lx += 120;
push @o, qq{<path d="M$lx } . ($ly + 7) . qq{ h28" stroke="$C{edge}" marker-end="url(#ar)"/><text x="} . ($lx + 34) . qq{" y="} . ($ly + 11) . '">imports</text>';
$lx += 100;
push @o, qq{<path d="M$lx } . ($ly + 7) . qq{ h28" stroke="$C{edge}" stroke-dasharray="2 3" marker-end="url(#ar)"/><text x="} . ($lx + 34) . qq{" y="} . ($ly + 11) . '">references only</text>';
$lx += 150;
push @o, qq{<path d="M$lx } . ($ly + 7) . qq{ h28" stroke="$C{bad}" stroke-width="2.4" marker-end="url(#arb)"/><text x="} . ($lx + 34) . qq{" y="} . ($ly + 11) . '">write-down</text>';
$lx += 110;
push @o, qq{<path d="M$lx } . ($ly + 7) . qq{ h28" stroke="$C{back}" stroke-dasharray="6 3" marker-end="url(#arc)"/><text x="} . ($lx + 34) . qq{" y="} . ($ly + 11) . '">cycle</text>';
push @o, '</g>';

# edges
for my $d (sort { (@{$a->{bad}} ? 1 : 0) <=> (@{$b->{bad}} ? 1 : 0) } (map { $DEP{$_} } sort keys %DEP)) {
    my ($a, $b) = ($d->{from}, $d->{to});
    my $bad = @{$d->{bad}};
    my ($col, $w, $mk) = $bad ? ($C{bad}, 2.4, 'arb') : $d->{back} ? ($C{back}, 1.4, 'arc') : ($C{edge}, 1.3, 'ar');
    my $dash = $d->{back} ? ' stroke-dasharray="6 3"' : !@{$d->{imports}} ? ' stroke-dasharray="2 3"' : '';
    my $path;
    if ($d->{back}) {       # arc under the boxes, right to left
        my ($x1, $y1) = ($a->{x} + $a->{w} / 2, $a->{y} + $a->{h});
        my ($x2, $y2) = ($b->{x} + $b->{w} / 2, $b->{y} + $b->{h});
        my $yb = ($y1 > $y2 ? $y1 : $y2) + 34;
        $path = sprintf 'M%.1f %.1f C%.1f %.1f %.1f %.1f %.1f %.1f', $x1, $y1, $x1, $yb, $x2, $yb, $x2, $y2 + 2;
    } else {
        my @pt = ([$a->{x} + $a->{w}, $a->{y} + $a->{h} / 2]);
        push @pt, map { [$_->{x} + $_->{w} / 2, $_->{y} + 5] } @{$d->{via}};
        push @pt, [$b->{x} - 2, $b->{y} + $b->{h} / 2];
        $path = sprintf 'M%.1f %.1f', @{$pt[0]};
        for my $i (1 .. $#pt) {
            my ($p, $q) = ($pt[$i - 1], $pt[$i]); my $mx = ($p->[0] + $q->[0]) / 2;
            $path .= sprintf ' C%.1f %.1f %.1f %.1f %.1f %.1f', $mx, $p->[1], $mx, $q->[1], $q->[0], $q->[1];
        }
    }
    my @tip = ("$a->{qname} -> $b->{qname}", @{$d->{imports}}, ($d->{refs} ? "$d->{refs} reference(s)" : ()),
               (map { "WRITE-DOWN: $_" } @{$d->{bad}}), ($d->{back} ? 'part of a dependency cycle' : ()));
    push @o, qq{<g><title>} . esc(join "\n", @tip) . qq{</title><path d="$path" fill="none" stroke="$col" stroke-width="$w"$dash marker-end="url(#$mk)"/>}
        . qq{<path d="$path" fill="none" stroke="transparent" stroke-width="10"/></g>};
}
# boxes
for my $n (@N) {
    my $r = $n->{rank};
    my ($fill, $stroke, $dash) = $r >= 0 ? ($PAL[$r % @PAL], $PALL[$r % @PALL], '') : ($C{none}, $C{bad}, ' stroke-dasharray="4 3"');
    $stroke = $C{bad} if !defined $n->{marking} && !$n->{parent};
    my @tip = ($n->{qname}, $n->{l2}, $n->{l3}, "$n->{file}:$n->{line}");
    push @tip, 'imports: ' . join(', ', map { join('::', @{$_->{segs}}) . ($_->{star} ? "::$_->{star}" : '') } @{$n->{imports}}) if @{$n->{imports}};
    my ($x, $y) = ($n->{x}, $n->{y});
    push @o, qq{<g><title>} . esc(join "\n", @tip) . '</title>',
      sprintf(qq{<rect x="%.1f" y="%.1f" width="%.1f" height="%.1f" rx="3" fill="$fill" stroke="$stroke" stroke-width="1.6"$dash/>}, $x, $y, $n->{w}, $n->{h}),
      ($n->{inside} ? sprintf(qq{<rect x="%.1f" y="%.1f" width="6" height="%.1f" fill="$PALL[$n->{inside} % @PALL]"/>}, $x + $n->{w} - 6, $y, $n->{h}) : ()),
      sprintf(qq{<text x="%.1f" y="%.1f" font-weight="bold" fill="$C{ink}">%s</text>}, $x + $PADX, $y + 4 + $LH - 2, esc($n->{l1})),
      sprintf(qq{<text x="%.1f" y="%.1f" font-size="$SFS" fill="%s">%s</text>}, $x + $PADX, $y + 4 + 2 * $LH - 2, (!defined $n->{marking} && !$n->{parent}) ? $C{bad} : $C{dim}, esc($n->{l2})),
      sprintf(qq{<text x="%.1f" y="%.1f" font-size="$SFS" fill="$C{dim}">%s</text>}, $x + $PADX, $y + 4 + 3 * $LH - 2, esc($n->{l3})),
      '</g>';
}
push @o, '</svg>';
open my $out, '>:encoding(UTF-8)', $O{o} or die "$O{o}: $!";
print $out map { "$_\n" } @o;
close $out;
print map { "$_->[3]\n" } sort { $a->[0] cmp $b->[0] || $a->[1] <=> $b->[1] || $a->[2] <=> $b->[2] } @DIAG;
print "$sum -> $O{o}\n";
exit($NERR ? 1 : 0);
