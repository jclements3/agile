#!/usr/bin/perl
# sysml-ibd-svg.pl : interconnection view (parts, ports, connections) of SysML v2 part defs, as one
# SVG, colored by SecMeta trust zone, with the boundary-coverage check (SEC-1). Core Perl 5 only.
#
#   perl sysml-ibd-svg.pl [-o ibd.svg] [--title T] [--root NAME]... DIR|FILE...
#
#   --root NAME   draw this part def (repeatable). Default: every part def that owns a
#                 connection, interface or flow, one diagram each, stacked.
#
# Inside each frame: the def's parts (inherited ones marked ^, ref parts dashed), their ports on
# the box edge, the def's own ports on the frame edge, and every connect / interface / flow
# (inherited ones included). Ends deeper than one level (a.b.p) attach to the part box and are
# labelled with the rest of the path.
#
# Ends: 'connect a.b to c.d' after the name and type, or 'end ::> a.b;' lines in the body
# (interface ifc { end ::> a.b; end ::> c.d; attribute fromZone = "x"; ... }).
#
# Zones: @TrustZone { zone = Zone::x; } on a part usage or its part def. A part with none takes
# its container's zone. A connection whose two ends sit in different zones is a boundary crossing.
#
# Checks (the binder's threat-model rules):
#   error    SEC-1 boundary coverage: a crossing not covered by a satisfied @SecurityRequirement
#            whose subject is the def that owns the crossing, or a def that contains it, or that
#            the connection names in an attribute secReq = "name" (the status-metrics line form)
#   warning  a connection whose fromZone / toZone attributes disagree with the zones of its ends
#   note     derived attack surface: every connection that touches an untrusted-zone part
# Exit status: 0 no errors, 1 errors, 2 usage error.
use strict; use warnings;
use File::Find; use Getopt::Long;
binmode STDOUT, ':encoding(UTF-8)'; binmode STDERR, ':encoding(UTF-8)';

my %O = (o => 'ibd.svg', root => []);
GetOptions(\%O, 'o=s', 'title=s', 'root=s@') && @ARGV
    or do { print STDERR "usage: perl sysml-ibd-svg.pl [-o ibd.svg] [--title T] [--root NAME]... DIR|FILE...\n"; exit 2 };
my @files;
for my $a (@ARGV) {
    if (-d $a) { find(sub { push @files, $File::Find::name if /\.sysml$/ }, $a) }
    elsif (-f $a) { push @files, $a }
    else { print STDERR "sysml-ibd-svg: $a: no such file or directory\n"; exit 2 }
}
@files = sort @files;

my $NAME  = qr/(?:[A-Za-z_]\w*|'(?:[^'\\]|\\.)*')/;
my $REF   = qr/$NAME(?:\s*(?:::|\.)\s*$NAME)*/;
my $CHAIN = qr/$NAME(?:\s*\.\s*$NAME)*/;
sub unq { my $n = shift; return $n unless $n =~ /^'(.*)'$/s; (my $u = $1) =~ s/\\(.)/$1/g; $u }
sub segs { my $r = shift; my @s; push @s, unq($1) while $r =~ /\G\s*($NAME)\s*(?:::|\.)?/g; @s }
my ($NERR, $NWARN, $NNOTE, @DIAG) = (0, 0, 0);
sub diag { my ($f, $l, $sev, $m) = @_; push @DIAG, [$f, $l, scalar @DIAG, "$f:$l: $sev: $m"]; $sev eq 'error' ? $NERR++ : $sev eq 'warning' ? $NWARN++ : $NNOTE++ }

# ------------------------------------------------------------------------------------------
# Parse
# ------------------------------------------------------------------------------------------
my (@defs, %defsByName, @reqs, %reqdefs, @sats);
for my $f (@files) {
    open my $h, '<:encoding(UTF-8)', $f or die "$f: $!";
    local $/; my $t = <$h>;
    my @stack = ({ kind => 'file', pkg => [] });
    my ($head, $hline, $line) = ('', 1, 1);
    pos($t) = 0;
    while (pos($t) < length $t) {
        if ($t =~ /\G\n/gc) { $line++; $head .= ' ' }
        elsif ($t =~ m{\G//[^\n]*}gc) { }
        elsif ($t =~ m{\G/\*}gc) {
            my $from = pos($t); my $end = index($t, '*/', $from); $end = length $t if $end < 0;
            my $body = substr($t, $from, $end - $from); pos($t) = $end + 2;
            $line += ($body =~ tr/\n//);
            if ($head =~ /^\s*doc\b/) { $body =~ s/^\s*\*\s?//mg; $body =~ s/\s+/ /g; $body =~ s/^ | $//g;
                $stack[-1]{node}{doc} //= $body if $stack[-1]{node}; $head = '' }
            elsif ($head =~ /^\s*comment\b/) { $head = '' }
        }
        elsif ($t =~ /\G("(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*')/gc) { my $q = $1; $hline = $line if $head !~ /\S/; $head .= $q; $line += ($q =~ tr/\n//) }
        elsif ($t =~ /\G([{};])/gc) {
            my $c = $1;
            if ($c eq '}') { pop @stack if @stack > 1; $head = ''; next }
            my $st = classify($head, $f, $hline, \@stack);
            $head = '';
            push @stack, $st // { kind => 'other', pkg => $stack[-1]{pkg} } if $c eq '{';
        }
        elsif ($t =~ m{\G([^{};"'/\n]+|/)}gc) { my $x = $1; $hline = $line if $head !~ /\S/ && $x =~ /\S/; $head .= $x }
    }
}

sub classify {
    my ($s, $f, $line, $stack) = @_;
    my $top = $stack->[-1];
    $s =~ s/\s+/ /g; $s =~ s/^ | $//g;
    return undef if $s eq '';
    my $pkg = $top->{pkg};
    my $node = $top->{node};
    if ($top->{kind} eq 'conn') {           # inside a connection body: its ends and its zone attributes
        my $c = $top->{conn};
        if (!$top->{done} && $s =~ /^end\b\s*(?:$NAME\s*)?(?::\s*~?\s*$REF\s*)?(?:::>|\breferences\b)\s*($CHAIN)/) {
            push @{$top->{ends}}, [@{$top->{pre}}, segs($1)];
            if (@{$top->{ends}} == 2) { $c->{ends} = $top->{ends}; push @{$c->{owner}{conns}}, $c; $top->{done} = 1 }
        } elsif ($s =~ /^attribute\s+(secReq|fromZone|toZone)\b[^=]*=\s*"((?:[^"\\]|\\.)*)"/) { $c->{attr}{$1} = $2 }
        return undef;
    }
    # metadata usages: @TrustZone { zone = Zone::x; }, @SecurityRequirement;
    if ($s =~ /^@\s*(?:SecMeta::)?TrustZone\b(.*)$/) {
        my $rest = $1;
        $node->{zone} = $1 if $node && $rest =~ /zone\s*=\s*(?:\w+::)*(\w+)/;
        return { kind => 'zone', target => $node, pkg => $pkg };
    }
    if ($top->{kind} eq 'zone' && $s =~ /^(?::>>\s*)?zone\s*=\s*(?:\w+::)*(\w+)/) { $top->{target}{zone} = $1 if $top->{target}; return undef }
    if ($s =~ /^@\s*(?:SecMeta::)?SecurityRequirement\b/) { $node->{secreq} = 1 if $node && $node->{isreq}; return { kind => 'other', pkg => $pkg } }
    if ($s =~ /^@/ || $s =~ /^metadata\s/) { return { kind => 'other', pkg => $pkg } }
    my @hash;
    $s =~ s/^(?:(?:public|private|protected|abstract|variation|individual|derived|readonly)\s+)*//;
    while ($s =~ s/^#\s*($NAME)\s*//) { push @hash, unq($1) }
    $node->{secreq} = 1 if $node && $node->{isreq} && grep { $_ eq 'SecurityRequirement' } @hash;
    if ($s =~ /^(?:standard\s+)?(?:library\s+)?package\s+($NAME)/) { return { kind => 'package', pkg => [@$pkg, unq($1)] } }
    if ($s =~ /^satisfy\s+(?:requirement\s+)?($REF)\s+by\s+($REF)/) { push @sats, { ref => [segs($1)], file => $f, line => $line }; return undef }
    if ($s =~ /^requirement\s+def\s+($NAME)/) {
        my $r = { isreq => 1, name => unq($1), pkg => $pkg, file => $f, line => $line };
        $r->{secreq} = 1 if grep { $_ eq 'SecurityRequirement' } @hash;
        $reqdefs{$r->{name}} = $r;
        return { kind => 'node', node => $r, pkg => $pkg };
    }
    if ($s =~ /^requirement\s+(?:<'[^']*'>\s*)?($NAME)(.*)$/) {
        my ($n, $rest) = (unq($1), $2);
        my @path = ((map { $_->{node}{name} } grep { $_->{node} && $_->{node}{isreq} && !$_->{node}{isdef} } @$stack), $n);
        my $r = { isreq => 1, name => $n, path => \@path, pkg => $pkg, file => $f, line => $line,
                  up => ($node && $node->{isreq} ? $node : undef) };
        $r->{type} = (segs($1))[-1] if $rest =~ /^\s*:\s*($REF)/;
        $r->{secreq} = 1 if grep { $_ eq 'SecurityRequirement' } @hash;
        push @reqs, $r;
        return { kind => 'node', node => $r, pkg => $pkg };
    }
    if ($node && $node->{isreq} && $s =~ /^subject\s+(?:$NAME\s*)?(?::|defined\s+by)\s*($REF)/) { $node->{subject} = [segs($1)]; return undef }
    if ($s =~ /^part\s+def\s+($NAME)(.*)$/) {
        my ($name, $rest) = (unq($1), $2);
        my @sup;
        if ($rest =~ /(?::>|\bspecializes\b)\s*($REF(?:\s*,\s*$REF)*)/) { @sup = map { [segs($_)] } split /\s*,\s*/, $1 }
        my $d = { isdef => 1, name => $name, pkg => $pkg, sup => \@sup, feats => [], conns => [], file => $f, line => $line };
        push @defs, $d; push @{$defsByName{$name}}, $d;
        return { kind => 'node', node => $d, pkg => $pkg };
    }
    return undef unless $node && !$node->{isreq};
    # connections, interfaces, flows owned by a def (or a usage: drawn with the def above it)
    my $owner = $node; $owner = $owner->{owner} while $owner && !$owner->{isdef};
    if ($owner && $s =~ /^(connection|interface|flow|connect)\b(?!\s+def\b)(.*)$/) {
        my ($kw, $rest) = ($1, $2);
        my %c = (kind => $kw eq 'connect' ? 'connection' : $kw, file => $f, line => $line, owner => $owner);
        if ($kw ne 'connect' && $rest =~ /^\s*($NAME)/ && $1 !~ /^(?:connect|of|from)$/) { $c{name} = unq($1) }
        if ($kw ne 'connect' && $rest =~ /^\s*(?:$NAME\s*)?:\s*($REF)/) { $c{type} = join '::', segs($1) }
        my $body = $kw eq 'connect' ? "connect$rest" : $rest;
        if ($body =~ /\bconnect\s+(?:$NAME\s*::>\s*)?($CHAIN)\s+to\s+(?:$NAME\s*::>\s*)?($CHAIN)/) { $c{ends} = [[segs($1)], [segs($2)]] }
        elsif ($kw eq 'flow' && $body =~ /(?:\bof\s+(?:$NAME\s*:\s*)?($REF)\s+)?\bfrom\s+($CHAIN)\s+to\s+($CHAIN)/) {
            $c{item} = $1 ? join('::', segs($1)) : undef; $c{ends} = [[segs($2)], [segs($3)]]; $c{directed} = 1;
        }
        # ends written inside a nested usage are relative to it: prefix the usage path
        my @pre; for (my $o = $node; $o && !$o->{isdef}; $o = $o->{owner}) { unshift @pre, $o->{name} }
        if ($c{ends}) {
            $c{ends} = [map { [@pre, @$_] } @{$c{ends}}];
            push @{$owner->{conns}}, \%c;
        }
        return { kind => 'conn', conn => \%c, pre => \@pre, ends => [], done => $c{ends} ? 1 : 0, pkg => $pkg };
    }
    if ($s =~ /^(?:(in|out|inout)\s+)?(ref\s+)?(part|item|attribute|port)\b(?!\s+def\b)\s*(.*)$/) {
        my ($dir, $ref, $kw, $rest) = ($1, $2, $3, $4);
        my $u = { kind => $kw, ref => $ref ? 1 : 0, dir => $dir // '', file => $f, line => $line, feats => [], owner => $node };
        (my $decl = $rest) =~ s/\s*(?::=|=|\bdefault\b).*$//;
        if ($decl =~ /^($NAME)/ && $decl !~ /^(?:redefines|subsets|references)\b/) { $u->{name} = unq($1) }
        if ($decl =~ /(?::>>|\bredefines\b)\s*($REF)/) { $u->{redef} = (segs($1))[-1]; $u->{name} //= $u->{redef} }
        if ($decl =~ /(?:^|[^:>]):\s*(~?)\s*($REF)/) { $u->{conj} = $1; $u->{type} = [segs($2)] }
        if ($decl =~ /\[\s*([^\]]+?)\s*\]/) { $u->{mult} = $1 }
        $u->{name} //= '(unnamed)';
        push @{$node->{feats}}, $u;
        return { kind => 'node', node => $u, pkg => $pkg };
    }
    return undef;
}

# ------------------------------------------------------------------------------------------
# Resolve: types, inheritance (features and connections), zones, containment, coverage
# ------------------------------------------------------------------------------------------
sub find_def {
    my ($segs, $from) = @_;
    my $c = $defsByName{$segs->[-1]} or return undef;
    my @c = @$c;
    if (@$segs > 1) {
        my @q = grep { my @full = (@{$_->{pkg}}, $_->{name}); @full >= @$segs && join("\0", @full[$#full - $#$segs .. $#full]) eq join("\0", @$segs) } @c;
        @c = @q if @q;
    }
    if (@c > 1 && $from) { my $p = join '::', @{$from->{pkg}}; my @near = grep { join('::', @{$_->{pkg}}) eq $p } @c; @c = @near if @near }
    return $c[0];
}
for my $d (@defs) {
    $d->{supdefs} = [grep { $_ } map { find_def($_, $d) } @{$d->{sup}}];
    my @q = @{$d->{feats}};
    while (my $u = shift @q) { $u->{tdef} = find_def($u->{type}, $d) if $u->{type} && $u->{kind} eq 'part'; push @q, @{$u->{feats}} }
}
my %eff;
sub effective {     # [features], [connections] of a def, inherited ones first and marked
    my ($d, $seen) = @_;
    return @{$eff{$d}} if $eff{$d};
    $seen //= {}; return ([], []) if $seen->{$d}++;
    my (@f, %pos, @c);
    for my $s (@{$d->{supdefs}}) {
        my ($sf, $sc) = effective($s, $seen);
        for my $x (@$sf) { next if defined $pos{$x->{name}}; $pos{$x->{name}} = @f; push @f, { %$x, inherited => 1 } }
        push @c, map { { %$_, inherited => 1 } } @$sc;
    }
    for my $x (@{$d->{feats}}) {
        my $k = defined $x->{redef} && defined $pos{$x->{redef}} ? $x->{redef} : $x->{name};
        if (defined $pos{$k}) { $f[$pos{$k}] = { %$x, base => $f[$pos{$k}] } } else { $pos{$x->{name}} = @f; push @f, $x }
    }
    push @c, @{$d->{conns}};
    $eff{$d} = [\@f, \@c];
    return (\@f, \@c);
}
sub tdef_of { my $u = shift; $u->{tdef} // ($u->{base} && tdef_of($u->{base})) }
sub zone_of_usage { my $u = shift; $u->{zone} // ($u->{base} && zone_of_usage($u->{base})) // (tdef_of($u) && tdef_of($u)->{zone}) }
sub ports_of {      # ports of a part usage: its type's effective ports, overridden by its own
    my $u = shift;
    my (@p, %pos);
    if (my $t = tdef_of($u)) { for my $x (grep { $_->{kind} eq 'port' } @{(effective($t))[0]}) { $pos{$x->{name}} = @p; push @p, $x } }
    for my $x (grep { $_->{kind} eq 'port' } @{$u->{feats}}) { if (defined $pos{$x->{name}}) { $p[$pos{$x->{name}}] = $x } else { push @p, $x } }
    return @p;
}
sub child { my ($u, $n) = @_; my $t = tdef_of($u) or return undef;
    for my $x (@{$u->{feats}}, @{(effective($t))[0]}) { return $x if $x->{name} eq $n } undef }

# contains(S, D): S is D, or D is a composite part type somewhere inside S
my %contains;
sub contains {
    my ($s, $d) = @_;
    my $k = "$s\0$d";
    return $contains{$k} if exists $contains{$k};
    $contains{$k} = 0;
    return $contains{$k} = 1 if $s == $d;
    for my $u (grep { $_->{kind} eq 'part' && !$_->{ref} } @{(effective($s))[0]}) {
        my $t = tdef_of($u) or next;
        return $contains{$k} = 1 if contains($t, $d);
    }
    return 0;
}
# satisfied security requirements and their subjects
my %satisfied;
for my $s (@sats) {
    my @sg = @{$s->{ref}};
    for my $r (@reqs) {
        my @full = (@{$r->{pkg}}, @{$r->{path}});
        $satisfied{$r} = 1 if @full >= @sg && join("\0", @full[$#full - $#sg .. $#full]) eq join("\0", @sg);
    }
}
my @secreqs;
for my $r (@reqs) {
    my $rd = $r->{type} && $reqdefs{$r->{type}};
    my $sec = $r->{secreq} || ($rd && $rd->{secreq});
    my $subj = $r->{subject} // ($rd && $rd->{subject});
    for (my $o = $r->{up}; !$subj && $o; $o = $o->{up}) { $subj = $o->{subject} // ($o->{type} && $reqdefs{$o->{type}} && $reqdefs{$o->{type}}{subject}) }
    my $sat = 0; for (my $o = $r; $o; $o = $o->{up}) { $sat ||= $satisfied{$o} }
    next unless $sec;
    push @secreqs, { r => $r, subject => $subj ? find_def($subj, $r) : undef, sat => $sat };
}

# roots
my @roots;
if (@{$O{root}}) {
    for my $n (@{$O{root}}) { my $d = find_def([split /::/, $n]) or do { print STDERR "sysml-ibd-svg: no part def '$n'\n"; exit 2 }; push @roots, $d }
} else { @roots = grep { @{(effective($_))[1]} } @defs }

# ------------------------------------------------------------------------------------------
# One diagram per root: parts, ports, ends, zones, crossings
# ------------------------------------------------------------------------------------------
my @ZCOL = (['trusted', '#e8f5e9', '#2e7d32'], ['dmz', '#fff8e1', '#f9a825'], ['untrusted', '#ffebee', '#c62828']);
my %ZFILL = map { $_->[0] => $_->[1] } @ZCOL; my %ZLINE = map { $_->[0] => $_->[2] } @ZCOL;
my @ZEXTRA = (['#e3f2fd', '#1565c0'], ['#f3e5f5', '#6a1b9a'], ['#e0f2f1', '#00695c']);
my %zones_seen;
sub zfill { my $z = shift; return '#ffffff' unless defined $z; $ZFILL{$z} // $ZEXTRA[(($zones_seen{$z} //= keys %zones_seen) - 1) % @ZEXTRA][0] }
sub zline { my $z = shift; return '#455a64' unless defined $z; $ZLINE{$z} // $ZEXTRA[(($zones_seen{$z} //= keys %zones_seen) - 1) % @ZEXTRA][1] }

my ($ncross, $nconn, @DG) = (0, 0);
for my $d (@roots) {
    my ($feats, $conns) = effective($d);
    my @parts = grep { $_->{kind} eq 'part' } @$feats;
    my @fports = grep { $_->{kind} eq 'port' } @$feats;
    my %pbyname = map { $_->{name} => $_ } @parts;
    my %fpbyname = map { $_->{name} => $_ } @fports;
    my $dzone = $d->{zone};
    my $g = { def => $d, parts => [map { { u => $_, ports => {}, zone => zone_of_usage($_) // $dzone } } @parts], fports => {}, conns => [] };
    my %P = map { $_->{u}{name} => $_ } @{$g->{parts}};
    for my $c (@$conns) {
        my @ends;
        for my $e (@{$c->{ends}}) {
            my @s = @$e;
            if ($P{$s[0]}) {
                my $p = $P{$s[0]};
                my $zone = $p->{zone};
                my $u = $p->{u};
                for my $n (@s[1 .. $#s]) { my $x = child($u, $n) or last; last if $x->{kind} ne 'part'; $zone = zone_of_usage($x) // $zone; $u = $x }
                my $label = join '.', @s[1 .. $#s];
                $p->{ports}{$label} //= { name => $label, part => $p } if $label ne '';
                push @ends, { part => $p, port => $label ne '' ? $p->{ports}{$label} : undef, zone => $zone, text => join('.', @s) };
            } elsif ($fpbyname{$s[0]} || @s == 1) {
                my $label = join '.', @s;
                $g->{fports}{$label} //= { name => $label, frame => 1 };
                push @ends, { frame => 1, port => $g->{fports}{$label}, zone => $dzone, text => $label };
            } else {
                diag($c->{file}, $c->{line}, 'warning', "connection end '" . join('.', @s) . "' is not a part or port of '$d->{name}'");
                @ends = (); last;
            }
        }
        next unless @ends == 2;
        my %cc = (%$c, e => \@ends);
        $nconn++;
        my ($z1, $z2) = map { $_->{zone} } @ends;
        my $label = $c->{name} // join(' -> ', map { $_->{text} } @ends);
        my $what = ($c->{kind} eq 'interface' ? 'interface' : $c->{kind} eq 'flow' ? 'flow' : 'connection') . " '$label'";
        if (defined $c->{attr}{fromZone} || defined $c->{attr}{toZone}) {     # the declared zones must match the drawn ones
            my ($d1, $d2) = map { $_ // '' } @{$c->{attr}}{qw(fromZone toZone)};
            my ($g1, $g2) = map { $_ // '(none)' } $z1, $z2;
            diag($c->{file}, $c->{line}, 'warning', "$what declares fromZone/toZone $d1->$d2 but its ends sit in $g1->$g2")
                if "$d1->$d2" ne "$g1->$g2" && !$c->{inherited};
        }
        if (defined $z1 && defined $z2 && $z1 ne $z2) {
            $cc{cross} = "$z1->$z2"; $ncross++;
            my @cov = grep { $_->{sat} && $_->{subject} && contains($_->{subject}, $c->{owner}) } @secreqs;
            my $named = $c->{attr}{secReq} // '';
            my @nm = $named ne '' ? grep { $_->{r}{name} eq (split /::|\./, $named)[-1] } @secreqs : ();
            push @cov, grep { my $x = $_; $x->{sat} && !grep { $_ == $x } @cov } @nm;
            if (@cov) { $cc{covered} = join ', ', map { $_->{r}{name} } @cov }
            elsif (!$c->{inherited} || 1) {
                my $why = $named ne '' && !@nm ? " (its secReq '$named' is not a \@SecurityRequirement)"
                        : $named ne '' ? " (its secReq '$named' is not satisfied)"
                        : (grep { $_->{subject} && contains($_->{subject}, $c->{owner}) } @secreqs) ? ' (a security requirement covers it but is not satisfied)' : '';
                diag($c->{file}, $c->{line}, 'error', "$what in '$c->{owner}{name}' crosses $z1->$z2 with no satisfied security requirement$why")
                    unless $cc{inherited} && grep { $_->[3] =~ /\Q$what\E in '\Q$c->{owner}{name}\E'/ } @DIAG;
            }
        }
        if (grep { ($_->{zone} // '') eq 'untrusted' } @ends) {
            diag($c->{file}, $c->{line}, 'note', "attack surface: $what in '$d->{name}' touches the untrusted zone")
                unless grep { $_->[3] =~ /attack surface: \Q$what\E in '\Q$d->{name}\E'/ } @DIAG;
        }
        push @{$g->{conns}}, \%cc;
    }
    # declared but unconnected ports are drawn too
    for my $p (@{$g->{parts}}) { for my $x (ports_of($p->{u})) { $p->{ports}{$x->{name}} //= { name => $x->{name}, part => $p, decl => $x } ; $p->{ports}{$x->{name}}{decl} //= $x } }
    for my $x (@fports) { $g->{fports}{$x->{name}} //= { name => $x->{name}, frame => 1 }; $g->{fports}{$x->{name}}{decl} = $x }
    push @DG, $g;
}

# ------------------------------------------------------------------------------------------
# Layout
# ------------------------------------------------------------------------------------------
my ($CW, $FS, $SFS, $PAD, $TOP) = (7.2, 12, 10.5, 16, 96);
sub tw { length($_[0]) * $CW }
sub stw { length($_[0]) * $CW * $SFS / $FS }
my ($PSZ, $PSTEP, $GAPX, $GAPY, $FPAD) = (10, 22, 120, 70, 60);
my $Y = $TOP;
my $W = 720;
for my $g (@DG) {
    my @P = @{$g->{parts}};
    # order parts: greedy by connection count, each next part the one most connected to those placed
    my %w; for my $c (@{$g->{conns}}) { my @p = map { $_->{part} // () } @{$c->{e}}; next unless @p == 2 && $p[0] != $p[1]; $w{"$p[0]"}{"$p[1]"}++; $w{"$p[1]"}{"$p[0]"}++ }
    my %fw; for my $c (@{$g->{conns}}) { my @e = @{$c->{e}}; for my $i (0, 1) { $fw{"$e[$i]{part}"}++ if $e[$i]{part} && $e[1 - $i]{frame} } }
    my @order; my %in;
    my $deg = sub { my $p = shift; my $s = $fw{"$p"} // 0; $s += $_ for values %{$w{"$p"} // {}}; $s };
    while (@order < @P) {
        my ($best) = sort { (my $ba = sum_to($b, \@order, \%w)) <=> (my $aa = sum_to($a, \@order, \%w)) || ($fw{"$b"} // 0) <=> ($fw{"$a"} // 0) || $deg->($b) <=> $deg->($a) } grep { !$in{"$_"} } @P;
        push @order, $best; $in{"$best"} = 1;
    }
    my $n = @order;
    my $cols = $n <= 2 ? $n : $n <= 4 ? 2 : $n <= 9 ? 3 : 4;
    $cols ||= 1;
    my $rows = int(($n + $cols - 1) / $cols) || 1;
    # start from a snake order, then improve by swapping cells (empty cells included)
    my @cell;                       # cell index -> part or undef
    for my $i (0 .. $#order) { my $r = int($i / $cols); my $c = $i % $cols; $c = $cols - 1 - $c if $r % 2; $cell[$r * $cols + $c] = $order[$i] }
    $#cell = $rows * $cols - 1;
    my @links; for my $c (@{$g->{conns}}) { my @e = @{$c->{e}}; push @links, [map { $_->{frame} ? undef : $_->{part} } @e] }
    my $cost = sub {
        my %at; for my $i (0 .. $#cell) { $at{"$cell[$i]"} = $i if $cell[$i] }
        my $s = 0;
        for my $l (@links) {
            my ($a, $b) = @$l;
            if (!$a && !$b) { next }
            if (!$a || !$b) { my $i = $at{"" . ($a // $b)}; my $c = $i % $cols; $s += ($c < $cols - 1 - $c ? $c : $cols - 1 - $c) + 1; next }
            my ($i, $j) = ($at{"$a"}, $at{"$b"});
            my ($r1, $c1, $r2, $c2) = (int($i / $cols), $i % $cols, int($j / $cols), $j % $cols);
            $s += abs($c1 - $c2) + 1.2 * abs($r1 - $r2);
            if ($r1 == $r2) { for my $c (($c1 < $c2 ? $c1 : $c2) + 1 .. ($c1 < $c2 ? $c2 : $c1) - 1) { $s += 3 if $cell[$r1 * $cols + $c] } }
            if ($c1 == $c2) { for my $r (($r1 < $r2 ? $r1 : $r2) + 1 .. ($r1 < $r2 ? $r2 : $r1) - 1) { $s += 3 if $cell[$r * $cols + $c1] } }
        }
        return $s;
    };
    my $best = $cost->();
    for my $round (1 .. 20) {
        my $improved = 0;
        for my $i (0 .. $#cell) { for my $j ($i + 1 .. $#cell) {
            next unless $cell[$i] || $cell[$j];
            @cell[$i, $j] = @cell[$j, $i];
            my $c = $cost->();
            if ($c < $best - 1e-9) { $best = $c; $improved = 1 } else { @cell[$i, $j] = @cell[$j, $i] }
        } }
        last unless $improved;
    }
    for my $i (0 .. $#cell) { next unless $cell[$i]; @{$cell[$i]}{qw(r c)} = (int($i / $cols), $i % $cols) }
    # port sides: towards the mean position of everything the port connects to
    # (frame ports first: left or right of the frame, by where their partners sit)
    my %acc;
    for my $c (@{$g->{conns}}) {
        my @e = @{$c->{e}};
        for my $i (0, 1) { my ($a, $b) = ($e[$i], $e[1 - $i]); next unless $a->{frame} && !$b->{frame}; $acc{"$a->{port}"} += $b->{part}{c} - ($cols - 1) / 2 }
    }
    for my $fp (values %{$g->{fports}}) { $fp->{side} = ($acc{"$fp"} // -1) > 0 ? 'R' : 'L' }
    my (%vx, %vy);
    for my $c (@{$g->{conns}}) {
        my @e = @{$c->{e}};
        for my $i (0, 1) {
            my ($a, $b) = ($e[$i], $e[1 - $i]);
            next if $a->{frame};
            my $k = $a->{port} ? "$a->{port}" : "$c$i";
            my ($dc, $dr) = $b->{frame} ? (($b->{port}{side} eq 'R' ? $cols : -1) - $a->{part}{c}, 0)
                                        : ($b->{part}{c} - $a->{part}{c}, $b->{part}{r} - $a->{part}{r});
            $dc = 0.1 if !$b->{frame} && $b->{part} == $a->{part};
            $vx{$k} += $dc; $vy{$k} += $dr;
        }
    }
    for my $c (@{$g->{conns}}) {
        my @e = @{$c->{e}};
        for my $i (0, 1) {
            my $a = $e[$i]; next if $a->{frame};
            my $k = $a->{port} ? "$a->{port}" : "$c$i";
            my ($dc, $dr) = ($vx{$k} // 0, $vy{$k} // 0);
            my $side = abs($dc) >= abs($dr) && $dc != 0 ? ($dc > 0 ? 'R' : 'L') : $dr > 0 ? 'B' : $dr < 0 ? 'T' : 'R';
            if ($a->{port}) { $a->{port}{side} = $side } else { $a->{side} = $side }
        }
    }
    # box sizes
    for my $p (@P) {
        my @pp = sort { $a->{name} cmp $b->{name} } values %{$p->{ports}};
        $_->{side} //= 'L' for @pp;
        my %by; push @{$by{$_->{side}}}, $_ for @pp;
        $p->{byside} = \%by;
        my $u = $p->{u};
        my $t = tdef_of($u);
        $p->{l1} = ($u->{inherited} ? '^' : '') . $u->{name} . ($u->{type} ? ' : ' . join('::', @{$u->{type}}) : '') . ($u->{mult} ? "[$u->{mult}]" : '');
        $p->{l0} = ($u->{ref} ? "\x{ab}ref part\x{bb}" : "\x{ab}part\x{bb}") . (defined $p->{zone} ? " zone $p->{zone}" : '');
        my $lw = 0; for my $s ('L', 'R') { for (@{$by{$s} // []}) { my $w = stw($_->{name}); $lw = $w if $w > $lw } }
        my ($tw) = sort { $b <=> $a } tw($p->{l1}), stw($p->{l0}), map { stw($_->{name}) * 1 } map { @{$by{$_} // []} } 'T', 'B';
        $p->{w} = $tw + 24 + 2 * ($lw ? $lw + 8 : 0);
        my $nT = @{$by{T} // []}; my $nB = @{$by{B} // []};
        my $wT = ($nT > $nB ? $nT : $nB) * 90 + 30; $p->{w} = $wT if $p->{w} < $wT;
        my $nside = @{$by{L} // []}; $nside = @{$by{R} // []} if @{$by{R} // []} > $nside;
        $p->{toff} = $nT ? 14 : 0;
        $p->{h} = 34 + ($nside ? $nside * $PSTEP : 14) + ($nT ? 14 : 0) + ($nB ? 14 : 0);
        $p->{h} = 52 if $p->{h} < 52;
    }
    my @cw = (0) x $cols; my @rh = (0) x $rows;
    for my $p (@P) { $cw[$p->{c}] = $p->{w} if $p->{w} > $cw[$p->{c}]; $rh[$p->{r}] = $p->{h} if $p->{h} > $rh[$p->{r}] }
    my $fl = 0; for (values %{$g->{fports}}) { my $w = stw($_->{name}); $fl = $w if $w > $fl }
    my $fx = $PAD; my $fy = $Y;
    my $ix = $fx + $FPAD + $fl; my $iy = $fy + 54;
    my @colx = ($ix); push @colx, $colx[-1] + $cw[$_ - 1] + $GAPX for 1 .. $cols - 1;
    my @rowy = ($iy); push @rowy, $rowy[-1] + $rh[$_ - 1] + $GAPY for 1 .. $rows - 1;
    for my $p (@P) { $p->{x} = $colx[$p->{c}] + ($cw[$p->{c}] - $p->{w}) / 2; $p->{y} = $rowy[$p->{r}] + ($rh[$p->{r}] - $p->{h}) / 2 }
    my $innerw = $colx[-1] + ($cw[-1] // 200) - $ix; my $innerh = $rowy[-1] + ($rh[-1] // 60) - $iy;
    my %fb; push @{$fb{$_->{side} // 'L'}}, $_ for sort { $a->{name} cmp $b->{name} } values %{$g->{fports}};
    my $nf = @{$fb{L} // []}; $nf = @{$fb{R} // []} if @{$fb{R} // []} > $nf;
    $innerh = $nf * 34 if $innerh < $nf * 34;
    $g->{frame} = { x => $fx, y => $fy, w => ($ix - $fx) + $innerw + $FPAD + $fl, h => ($iy - $fy) + $innerh + 40 };
    $g->{gx} = [map { $colx[$_] + $cw[$_] } 0 .. $cols - 1];       # right edge of each column
    $g->{gy} = [map { $rowy[$_] + $rh[$_] } 0 .. $rows - 1];
    $g->{colx} = \@colx; $g->{rowy} = \@rowy;
    # port coordinates
    for my $p (@P) {
        my $by = $p->{byside};
        for my $s ('L', 'R') {
            my @l = @{$by->{$s} // []}; my $y0 = $p->{y} + 34 + $p->{toff};
            for my $i (0 .. $#l) { $l[$i]{px} = $s eq 'L' ? $p->{x} : $p->{x} + $p->{w}; $l[$i]{py} = $y0 + $i * $PSTEP + $PSZ / 2 }
        }
        for my $s ('T', 'B') {
            my @l = @{$by->{$s} // []}; my $step = $p->{w} / (@l + 1);
            for my $i (0 .. $#l) { $l[$i]{px} = $p->{x} + $step * ($i + 1); $l[$i]{py} = $s eq 'T' ? $p->{y} : $p->{y} + $p->{h} }
        }
    }
    for my $s ('L', 'R') {
        my @l = @{$fb{$s} // []}; my $fr = $g->{frame};
        my $step = ($fr->{h} - 60) / (@l + 1);
        for my $i (0 .. $#l) { $l[$i]{px} = $s eq 'L' ? $fr->{x} : $fr->{x} + $fr->{w}; $l[$i]{py} = $fr->{y} + 50 + $step * ($i + 1) }
    }
    $g->{fb} = \%fb;
    $Y = $fy + $g->{frame}{h} + 48;
    $W = $g->{frame}{x} + $g->{frame}{w} + $PAD if $g->{frame}{x} + $g->{frame}{w} + $PAD > $W;
}
sub sum_to { my ($p, $placed, $w) = @_; my $s = 0; $s += $w->{"$p"}{"$_"} // 0 for @$placed; $s }
my $H = $Y + 10;

# ------------------------------------------------------------------------------------------
# Draw
# ------------------------------------------------------------------------------------------
sub esc { my $s = shift // ''; $s =~ s/&/&amp;/g; $s =~ s/</&lt;/g; $s =~ s/>/&gt;/g; $s =~ s/"/&quot;/g; $s }
my %C = (ink => '#212121', dim => '#616161', wire => '#546e7a', frame => '#283593', cov => '#ef6c00', bad => '#c62828');
my @o;
push @o, qq{<?xml version="1.0" encoding="UTF-8"?>},
  qq{<svg xmlns="http://www.w3.org/2000/svg" width="$W" height="$H" viewBox="0 0 $W $H" font-family="DejaVu Sans Mono, Consolas, Menlo, monospace" font-size="$FS">},
  qq{<!-- generated by sysml-ibd-svg.pl from } . (esc(join ' ', @ARGV) =~ s/-(?=-)/- /gr) . qq{ -->},
  qq{<defs><marker id="fa" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="8" markerHeight="8" orient="auto"><path d="M0 0 L10 5 L0 10 z" fill="$C{wire}"/></marker></defs>},
  qq{<rect width="100%" height="100%" fill="#ffffff"/>};
my $sum = sprintf '%d file(s): %d error(s), %d warning(s), %d diagram(s), %d connection(s), %d boundary crossing(s), %d on the attack surface',
    scalar @files, $NERR, $NWARN, scalar @DG, $nconn, $ncross, $NNOTE;
push @o, qq{<text x="$PAD" y="26" font-size="16" font-weight="bold" fill="$C{ink}">} . esc($O{title} // 'Interconnection') . '</text>',
  qq{<text x="$PAD" y="46" fill="$C{dim}">} . esc($sum) . '</text>';
my $lx = $PAD; my $ly = 60;
push @o, qq{<g font-size="11" fill="$C{dim}">};
for my $z ((map { $_->[0] } @ZCOL), sort grep { !$ZFILL{$_} } keys %{{ map { defined $_->{zone} ? ($_->{zone} => 1) : () } map { @{$_->{parts}} } @DG }}) {
    push @o, qq{<rect x="$lx" y="$ly" width="22" height="13" rx="3" fill="} . zfill($z) . qq{" stroke="} . zline($z) . qq{"/><text x="} . ($lx + 28) . qq{" y="} . ($ly + 11) . '">' . esc($z) . '</text>';
    $lx += 44 + stw($z);
}
push @o, qq{<rect x="$lx" y="$ly" width="22" height="13" rx="3" fill="#ffffff" stroke="#455a64"/><text x="} . ($lx + 28) . qq{" y="} . ($ly + 11) . '">no zone</text>'; $lx += 100;
push @o, qq{<path d="M$lx } . ($ly + 7) . qq{ h28" stroke="$C{wire}" stroke-width="1.6"/><text x="} . ($lx + 34) . qq{" y="} . ($ly + 11) . '">connection</text>'; $lx += 116;
push @o, qq{<path d="M$lx } . ($ly + 7) . qq{ h28" stroke="$C{cov}" stroke-width="3"/><text x="} . ($lx + 34) . qq{" y="} . ($ly + 11) . '">crossing, covered</text>'; $lx += 172;
push @o, qq{<path d="M$lx } . ($ly + 7) . qq{ h28" stroke="$C{bad}" stroke-width="3" stroke-dasharray="6 3"/><text x="} . ($lx + 34) . qq{" y="} . ($ly + 11) . '">crossing, NOT covered</text>'; $lx += 200;
push @o, qq{<path d="M$lx } . ($ly + 7) . qq{ h28" stroke="$C{wire}" stroke-width="1.6" marker-end="url(#fa)"/><text x="} . ($lx + 34) . qq{" y="} . ($ly + 11) . '">flow</text>';
push @o, '</g>';

for my $g (@DG) {
    my $d = $g->{def}; my $fr = $g->{frame};
    my @tip = ("part def $d->{name}", ($d->{doc} // ()), (defined $d->{zone} ? "zone $d->{zone}" : ()), "$d->{file}:$d->{line}");
    push @o, qq{<g><title>} . esc(join "\n", @tip) . '</title>',
      sprintf(qq{<rect x="%.1f" y="%.1f" width="%.1f" height="%.1f" fill="%s" fill-opacity="0.35" stroke="$C{frame}" stroke-width="1.8"/>}, @$fr{qw(x y w h)}, zfill($d->{zone})),
      sprintf(qq{<text x="%.1f" y="%.1f" font-size="$SFS" fill="$C{dim}">%s</text>}, $fr->{x} + 10, $fr->{y} + 16, esc("\x{ab}part def\x{bb}" . (defined $d->{zone} ? " zone $d->{zone}" : ''))),
      sprintf(qq{<text x="%.1f" y="%.1f" font-weight="bold" fill="$C{ink}">%s</text>}, $fr->{x} + 10, $fr->{y} + 33, esc(join('::', @{$d->{pkg}}, $d->{name}))), '</g>';
    # parts
    for my $p (@{$g->{parts}}) {
        my $u = $p->{u};
        my $dash = $u->{ref} ? ' stroke-dasharray="5 3"' : '';
        my @t = ($p->{l0}, $p->{l1}, (tdef_of($u) && tdef_of($u)->{doc} ? tdef_of($u)->{doc} : ()), "$u->{file}:$u->{line}");
        push @o, qq{<g><title>} . esc(join "\n", @t) . '</title>',
          sprintf(qq{<rect x="%.1f" y="%.1f" width="%.1f" height="%.1f" rx="8" fill="%s" stroke="%s" stroke-width="1.4"$dash/>}, $p->{x}, $p->{y}, $p->{w}, $p->{h}, zfill($p->{zone}), zline($p->{zone})),
          sprintf(qq{<text x="%.1f" y="%.1f" font-size="$SFS" fill="$C{dim}" text-anchor="middle">%s</text>}, $p->{x} + $p->{w} / 2, $p->{y} + 14 + $p->{toff}, esc($p->{l0})),
          sprintf(qq{<text x="%.1f" y="%.1f" fill="%s" text-anchor="middle">%s</text>}, $p->{x} + $p->{w} / 2, $p->{y} + 28 + $p->{toff}, $u->{inherited} ? '#7b1fa2' : $C{ink}, esc($p->{l1})), '</g>';
    }
}
# wires under ports
for my $g (@DG) {
    my $fr = $g->{frame};
    for my $c (@{$g->{conns}}) {
        my @pt = map { endpoint($_) } @{$c->{e}};
        my ($col, $w, $dash) = ($C{wire}, 1.6, '');
        ($col, $w) = ($C{cov}, 3) if $c->{cross} && $c->{covered};
        ($col, $w, $dash) = ($C{bad}, 3, ' stroke-dasharray="6 3"') if $c->{cross} && !$c->{covered};
        my $path = route($g, @pt);
        my $label = $c->{name} // ($c->{kind} eq 'flow' && $c->{item} ? $c->{item} : '');
        $label = '' if $path->[3] && $path->[4] < stw($label) + 12;    # too short a run: tooltip only
        my @t = (($c->{inherited} ? '^' : '') . "$c->{kind} " . ($c->{name} // '') . ($c->{type} ? " : $c->{type}" : ''),
                 join(' -> ', map { $_->{text} } @{$c->{e}}),
                 ($c->{item} ? "item $c->{item}" : ()),
                 ($c->{cross} ? "zone crossing $c->{cross}: " . ($c->{covered} ? "covered by $c->{covered}" : 'NOT covered by a satisfied security requirement') : ()),
                 "$c->{file}:$c->{line}");
        my $mk = $c->{directed} ? ' marker-end="url(#fa)"' : '';
        push @o, qq{<g><title>} . esc(join "\n", @t) . qq{</title><path d="$path->[0]" fill="none" stroke="$col" stroke-width="$w"$dash$mk/>}
          . qq{<path d="$path->[0]" fill="none" stroke="transparent" stroke-width="10"/>}
          . ($label ne '' ? sprintf(qq{<text x="%.1f" y="%.1f" font-size="$SFS" fill="%s" text-anchor="%s" font-style="italic">%s</text>},
                $path->[3] ? ($path->[1], $path->[2] - 5) : ($path->[1] + 6, $path->[2] + 4), $c->{cross} ? $col : $C{dim}, $path->[3] ? 'middle' : 'start', esc($label)) : '')
          . '</g>';
    }
}
# ports on top
for my $g (@DG) {
    for my $p (@{$g->{parts}}) {
        for my $s (sort keys %{$p->{byside}}) { for my $q (@{$p->{byside}{$s}}) { push @o, port_svg($q, $s, zline($p->{zone})) } }
    }
    for my $s (sort keys %{$g->{fb}}) { for my $q (@{$g->{fb}{$s}}) { push @o, port_svg($q, $s, $C{frame}) } }
}
push @o, '</svg>';

sub endpoint { my $e = shift; return [$e->{port}{px}, $e->{port}{py}, $e->{port}{side} // 'L', $e->{frame}] if $e->{port};
    my $p = $e->{part}; my $s = $e->{side} // 'R';
    return [$s eq 'L' ? $p->{x} : $s eq 'R' ? $p->{x} + $p->{w} : $p->{x} + $p->{w} / 2, $s eq 'T' ? $p->{y} : $s eq 'B' ? $p->{y} + $p->{h} : $p->{y} + $p->{h} / 2, $s, 0] }
sub out { my ($pt, $len) = @_; my ($x, $y, $s, $frame) = @$pt; $len = -$len if $frame;
    return $s eq 'L' ? [$x - $len, $y] : $s eq 'R' ? [$x + $len, $y] : $s eq 'T' ? [$x, $y - $len] : [$x, $y + $len] }
# orthogonal route through the gaps between grid cells
sub hits {               # does any segment of the polyline cross a part box?
    my ($g, @pts) = @_;
    for my $i (0 .. $#pts - 1) {
        my ($x1, $y1, $x2, $y2) = (@{$pts[$i]}, @{$pts[$i + 1]});
        ($x1, $x2) = ($x2, $x1) if $x1 > $x2; ($y1, $y2) = ($y2, $y1) if $y1 > $y2;
        for my $p (@{$g->{parts}}) {
            my ($l, $t, $r, $b) = ($p->{x} + 2, $p->{y} + 2, $p->{x} + $p->{w} - 2, $p->{y} + $p->{h} - 2);
            return 1 if $x2 > $l && $x1 < $r && $y2 > $t && $y1 < $b;
        }
    }
    return 0;
}
sub route {
    my ($g, $pa, $pb) = @_;
    my ($a1, $b1) = (out($pa, 16), out($pb, 16));
    my $hz = sub { $_[0] eq 'L' || $_[0] eq 'R' };
    my @mid;
    if ($hz->($pa->[2]) && $hz->($pb->[2])) {
        my $mx = channel_x($g, ($a1->[0] + $b1->[0]) / 2);
        @mid = ([$mx, $a1->[1]], [$mx, $b1->[1]]);
    } elsif (!$hz->($pa->[2]) && !$hz->($pb->[2])) {
        my $my = channel_y($g, ($a1->[1] + $b1->[1]) / 2);
        @mid = ([$a1->[0], $my], [$b1->[0], $my]);
    } elsif ($hz->($pa->[2])) { @mid = ([$b1->[0], $a1->[1]]) }
    else { @mid = ([$a1->[0], $b1->[1]]) }
    my @pts = ([$pa->[0], $pa->[1]], $a1, @mid, $b1, [$pb->[0], $pb->[1]]);
    if (hits($g, $a1, @mid, $b1)) {     # go round: out to a vertical gap, along a horizontal gap, in
        my @best;
        my @xs = (channel_x($g, $a1->[0]), channel_x($g, $b1->[0]));
        for my $hy (sort { abs($a - ($a1->[1] + $b1->[1]) / 2) <=> abs($b - ($a1->[1] + $b1->[1]) / 2) } all_channels_y($g)) {
            my @m = ([$xs[0], $a1->[1]], [$xs[0], $hy], [$xs[1], $hy], [$xs[1], $b1->[1]]);
            @m = ([$a1->[0], $hy], [$b1->[0], $hy]) if !$hz->($pa->[2]) && !$hz->($pb->[2]);
            if (!hits($g, $a1, @m, $b1)) { @best = @m; last }
        }
        @pts = ([$pa->[0], $pa->[1]], $a1, @best, $b1, [$pb->[0], $pb->[1]]) if @best;
    }
    my $d = sprintf 'M%.1f %.1f', @{$pts[0]}; $d .= sprintf ' L%.1f %.1f', @$_ for @pts[1 .. $#pts];
    my ($li, $ll) = (1, -1);            # label on the longest segment
    for my $i (1 .. $#pts - 2) { my $l = abs($pts[$i][0] - $pts[$i + 1][0]) + abs($pts[$i][1] - $pts[$i + 1][1]); ($li, $ll) = ($i, $l) if $l > $ll }
    return [$d, ($pts[$li][0] + $pts[$li + 1][0]) / 2, ($pts[$li][1] + $pts[$li + 1][1]) / 2, $pts[$li][1] == $pts[$li + 1][1], $ll];
}
sub all_channels_y { my $g = shift; ($g->{rowy}[0] - 22, map({ $g->{gy}[$_] + $GAPY / 2 } 0 .. $#{$g->{gy}} - 1), $g->{gy}[-1] + 22) }
sub channel_x {         # nearest vertical gap (between columns, or outside the grid) to x
    my ($g, $x) = @_;
    my @c = ($g->{colx}[0] - $GAPX / 2.5, map({ $g->{gx}[$_] + $GAPX / 2 } 0 .. $#{$g->{gx}} - 1), $g->{gx}[-1] + $GAPX / 2.5);
    my ($best) = sort { abs($a - $x) <=> abs($b - $x) } @c; return $best;
}
sub channel_y {
    my ($g, $y) = @_;
    my @c = ($g->{rowy}[0] - 20, map({ $g->{gy}[$_] + $GAPY / 2 } 0 .. $#{$g->{gy}} - 1), $g->{gy}[-1] + 20);
    my ($best) = sort { abs($a - $y) <=> abs($b - $y) } @c; return $best;
}
sub port_svg {
    my ($q, $s, $line) = @_;
    my ($x, $y) = ($q->{px} - $PSZ / 2, $q->{py} - $PSZ / 2);
    my $decl = $q->{decl};
    my $conj = $decl && $decl->{conj};
    my $label = ($conj ? '~' : '') . $q->{name};
    my $dir = $decl && $decl->{type} ? ' : ' . ($conj ? '~' : '') . join('::', @{$decl->{type}}) : '';
    my ($tx, $ty, $anchor) = $q->{frame}
        ? ($s eq 'L' ? ($q->{px} + 9, $q->{py} - 7, 'start') : ($q->{px} - 9, $q->{py} - 7, 'end'))
        : $s eq 'L' ? ($q->{px} + 9, $q->{py} + 4, 'start') : $s eq 'R' ? ($q->{px} - 9, $q->{py} + 4, 'end')
        : $s eq 'T' ? ($q->{px}, $q->{py} + 18, 'middle') : ($q->{px}, $q->{py} - 9, 'middle');
    return qq{<g><title>} . esc("port $q->{name}$dir" . ($decl ? "\n$decl->{file}:$decl->{line}" : "\n(path to a nested feature)")) . '</title>'
      . sprintf(qq{<rect x="%.1f" y="%.1f" width="$PSZ" height="$PSZ" fill="%s" stroke="$line" stroke-width="1.4"/>}, $x, $y, $conj ? $line : '#ffffff')
      . sprintf(qq{<text x="%.1f" y="%.1f" font-size="$SFS" fill="$C{dim}" text-anchor="$anchor">%s</text>}, $tx, $ty, esc($label)) . '</g>';
}

open my $outf, '>:encoding(UTF-8)', $O{o} or die "$O{o}: $!";
print $outf map { "$_\n" } @o;
close $outf;
print map { "$_->[3]\n" } sort { $a->[0] cmp $b->[0] || $a->[1] <=> $b->[1] || $a->[2] <=> $b->[2] } @DIAG;
print "$sum -> $O{o}\n";
exit($NERR ? 1 : 0);
