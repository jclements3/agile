#!/usr/bin/perl
# sysml-tree-svg.pl : draw the part decomposition of a SysML v2 model as one SVG (general view).
# Core Perl 5 only. Left to right: each part def at the root, its parts to the right, each
# expanded through its type (inherited parts included, redefinitions applied).
#
#   perl sysml-tree-svg.pl [-o tree.svg] [--title T] [--root NAME]... [--all] [--depth N]
#                          [--features] [--outline] [--hide-meta A,B] DIR|FILE...
#
#   --root NAME   start at this part def (repeatable; NAME or Pkg::Name). Default: every part
#                 def that has parts and is not the type of another def's composite part.
#   --all         with no --root, also draw part defs with no parts that nothing uses
#   --depth N     stop expanding below N levels (default 12)
#   --features    add attribute and port compartments
#   --outline     flag decomposed nodes with fewer than 2 or more than 9 parts (rule G12)
#   --hide-meta   metadata names not shown on the keyword line (default Provenance,V1Source)
#   --compare OLD diff against an older version (a directory or files; repeatable): added,
#                 changed and removed parts are colored, one line per change is printed
#   --changed     with --compare, show only changed parts (unchanged siblings are counted)
#
# Parts are matched across versions by their path of part names from the root part def.
#
# Notation: definitions are square boxes, usages rounded; ref parts dashed and not expanded
# (a reference is not owned); ^ marks an inherited part; a filled diamond marks the owner.
use strict; use warnings;
use File::Find; use Getopt::Long;
binmode STDOUT, ":encoding(UTF-8)"; binmode STDERR, ":encoding(UTF-8)";

my %O = (o => 'tree.svg', depth => 12, 'hide-meta' => 'Provenance,V1Source', root => []);
GetOptions(\%O, 'o=s', 'title=s', 'root=s@', 'all', 'depth=i', 'features', 'outline', 'hide-meta=s', 'compare=s@', 'changed', 'label=s@') && @ARGV
    or do { print STDERR "usage: perl sysml-tree-svg.pl [-o tree.svg] [--title T] [--root NAME]... [--all] [--depth N] [--features] [--outline] [--compare OLD]... [--changed] DIR|FILE...\n"; exit 2 };
if ($O{changed} && !$O{compare}) { print STDERR "sysml-tree-svg: --changed needs --compare\n"; exit 2 }
my %HIDE = map { $_ => 1 } split /,/, $O{'hide-meta'};

# --label DIR=TEXT shows files under DIR as TEXT... in messages (sysml-diff.pl uses it for git revisions)
my @LABEL = map { [split /=/, $_, 2] } @{$O{label} // []};
sub shown { my $f = shift; for my $l (@LABEL) { return $l->[1] . substr($f, length($l->[0]) + 1) if index($f, "$l->[0]/") == 0 } $f }
sub collect {
    my @f;
    for my $a (@_) {
        if (-d $a) { find(sub { push @f, $File::Find::name if /\.sysml$/ }, $a) }
        elsif (-f $a) { push @f, $a }
        else { print STDERR "sysml-tree-svg: $a: no such file or directory\n"; exit 2 }
    }
    return sort @f;
}
my $nwarn = 0; our $QUIET = 0;
sub warnat { return if $QUIET; my ($f, $l, $m) = @_; printf STDERR "%s:%s: warning: %s\n", $f, $l, $m; $nwarn++ }    # the messages: the warnat calls

# ------------------------------------------------------------------------------------------
# Parse: statements split at { ; }, comments dropped, doc kept, a scope stack for owners.
# ------------------------------------------------------------------------------------------
my $NAME = qr/(?:[A-Za-z_]\w*|'(?:[^'\\]|\\.)*')/;
my $REF  = qr/$NAME(?:\s*(?:::|\.)\s*$NAME)*/;
my (@defs, %defsByName);

sub parse_files {
for my $real (@_) {
    open my $h, '<:encoding(UTF-8)', $real or die "$real: $!";
    local $/; my $t = <$h>;
    my $f = shown($real);
    my @stack = ({ kind => 'file', pkg => [], feats => [], meta => [] });
    my ($head, $hline, $line) = ('', 1, 1);
    pos($t) = 0;
    while (pos($t) < length $t) {
        if ($t =~ /\G\n/gc) { $line++; $head .= ' ' }
        elsif ($t =~ m{\G//[^\n]*}gc) { }
        elsif ($t =~ m{\G/\*}gc) {
            my $from = pos($t); my $end = index($t, '*/', $from);
            $end = length $t if $end < 0;
            my $body = substr($t, $from, $end - $from); pos($t) = $end + 2;
            $line += ($body =~ tr/\n//);
            if ($head =~ /^\s*doc\b/) {
                $body =~ s/^\s*\*\s?//mg; $body =~ s/\s+/ /g; $body =~ s/^ | $//g;
                $stack[-1]{node}{doc} //= $body if $stack[-1]{node} && $body ne '';
                $head = '';
            } elsif ($head =~ /^\s*comment\b/) { $head = '' }
        }
        elsif ($t =~ /\G("(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*')/gc) { my $q = $1; $hline = $line if $head !~ /\S/; $head .= $q; $line += ($q =~ tr/\n//) }
        elsif ($t =~ /\G([{};])/gc) {
            my $c = $1;
            if ($c eq '}') { pop @stack if @stack > 1; $head = ''; next }
            my $st = classify($head, $f, $hline, \@stack);
            $head = '';
            if ($c eq '{') { push @stack, $st // { kind => 'other', pkg => $stack[-1]{pkg} } }
        }
        elsif ($t =~ m{\G([^{};"'/\n]+|/)}gc) { my $x = $1; $hline = $line if $head !~ /\S/ && $x =~ /\S/; $head .= $x }
    }
}

}

# A statement head -> a scope (for '{') and, for parts, defs and features, a record.
sub classify {
    my ($s, $f, $line, $stack) = @_;
    my $top = $stack->[-1];
    $s =~ s/\s+/ /g; $s =~ s/^ | $//g;
    return undef if $s eq '';
    if ($s =~ /^@\s*($REF)\s*$/ || $s =~ /^metadata\s+($REF)\s*$/) {      # @Meta; or @Meta { ... }
        my $m = (segs($1))[-1];
        push @{$top->{meta}}, $m if $top->{node} && !$HIDE{$m};
        return { kind => 'other', pkg => $top->{pkg} };
    }
    my @hash;
    $s =~ s/^(?:(?:public|private|protected|abstract|variation|individual|derived|readonly|end)\s+)*//;
    push @hash, $1 while $s =~ s/^#\s*($NAME)\s*//;
    $s =~ s/^(?:(?:public|private|protected|abstract)\s+)*//;
    if ($s =~ /^(?:standard\s+)?(?:library\s+)?package\s+($NAME)/) {
        return { kind => 'package', pkg => [@{$top->{pkg}}, unq($1)] };
    }
    if ($s =~ /^part\s+def\s+($NAME)(.*)$/) {
        my ($name, $rest) = (unq($1), $2);
        my @sup;
        if ($rest =~ /(?::>|\bspecializes\b)\s*($REF(?:\s*,\s*$REF)*)/) { @sup = map { [segs($_)] } split /\s*,\s*/, $1 }
        my $d = { kind => 'def', name => $name, pkg => $top->{pkg}, sup => \@sup, feats => [],
                  meta => [@hash], file => $f, line => $line };
        $d->{node} = $d;
        push @defs, $d; push @{$defsByName{$name}}, $d;
        return scope_of($d, $top);
    }
    return undef unless $top->{node};                     # features only inside a def or usage
    my $owner = $top->{node};
    if ($s =~ /^(?:(in|out|inout)\s+)?(ref\s+)?(part|item|attribute|port)\b(?!\s+def\b)\s*(.*)$/) {
        my ($dir, $ref, $kw, $rest) = ($1, $2, $3, $4);
        my $u = { kind => $kw, ref => $ref ? 1 : 0, dir => $dir // '', file => $f, line => $line,
                  feats => [], meta => [@hash], owner => $owner };
        (my $decl = $rest) =~ s/\s*(?::=|=|\bdefault\b).*$//;          # drop the value part
        if ($decl =~ /^($NAME)/ && $decl !~ /^(?:redefines|subsets|references)\b/) { $u->{name} = unq($1) }
        if ($decl =~ /(?::>>|\bredefines\b)\s*($REF)/) { $u->{redef} = (segs($1))[-1]; $u->{name} //= $u->{redef} }
        if ($decl =~ /(?:^|[^:>]):\s*(~?)\s*($REF)/ || $decl =~ /\bdefined\s+by\s*(~?)\s*($REF)/) {
            $u->{conj} = $1; $u->{type} = [segs($2)];
        }
        if ($decl =~ /\[\s*([^\]]+?)\s*\]/) { $u->{mult} = $1 }
        $u->{name} //= '(unnamed)';
        push @{$owner->{feats}}, $u;
        return scope_of($u, $top);
    }
    return undef;
}
sub scope_of {
    my ($n, $top) = @_;
    return { kind => 'node', node => $n, pkg => $top->{pkg}, meta => $n->{meta} };
}
sub unq { my $n = shift; return $n unless $n =~ /^'(.*)'$/s; (my $u = $1) =~ s/\\(.)/$1/g; $u }
sub segs { my $r = shift; my @s; push @s, unq($1) while $r =~ /\G\s*($NAME)\s*(?:::|\.)?/g; @s }

# ------------------------------------------------------------------------------------------
# Resolve types and effective features
# ------------------------------------------------------------------------------------------
sub find_def {
    my ($segs, $from) = @_;
    my $c = $defsByName{$segs->[-1]} or return undef;
    my @c = @$c;
    if (@$segs > 1) {
        my @q = grep { my @full = (@{$_->{pkg}}, $_->{name});
                       @full >= @$segs && join("\0", @full[$#full - $#$segs .. $#full]) eq join("\0", @$segs) } @c;
        @c = @q if @q;
    }
    if (@c > 1 && $from) {
        my $p = join '::', @{$from->{pkg} // []};
        my @near = grep { join('::', @{$_->{pkg}}) eq $p } @c;
        @c = @near if @near;
    }
    return $c[0];
}
sub resolve_all {
for my $d (@defs) {
    $d->{supdefs} = [map { my $s = find_def($_, $d); warnat($d->{file}, $d->{line}, "'$d->{name}' specializes unknown '" . join('::', @$_) . "'") unless $s; $s ? $s : () } @{$d->{sup}}];
}
sub resolve_types {
    my ($u, $ctx) = @_;
    if ($u->{type} && !exists $u->{tdef}) {
        $u->{tdef} = find_def($u->{type}, $ctx);
        warnat($u->{file}, $u->{line}, "part '$u->{name}' has type '" . join('::', @{$u->{type}}) . "' that is not a part def here")
            if !$u->{tdef} && $u->{kind} eq 'part';
    }
    resolve_types($_, $ctx) for @{$u->{feats}};
}
for my $d (@defs) { resolve_types($_, $d) for @{$d->{feats}} }
}

# Effective features of a def: inherited (marked) unless redefined by name, then own.
my %eff;
sub effective {
    my ($d, $seen) = @_;
    return $eff{$d} if $eff{$d};
    $seen //= {};
    return [] if $seen->{$d}++;
    my (@out, %pos);
    for my $s (@{$d->{supdefs}}) {
        for my $f (@{effective($s, $seen)}) {
            next if defined $pos{$f->{name}};
            $pos{$f->{name}} = @out; push @out, { %$f, inherited => 1 };
        }
    }
    for my $f (@{$d->{feats}}) {
        my $key = defined $f->{redef} && defined $pos{$f->{redef}} ? $f->{redef} : $f->{name};
        if (defined $pos{$key}) { $out[$pos{$key}] = { %$f, inherited => 0, merged => $out[$pos{$key}] } }
        else { $pos{$f->{name}} = @out; push @out, $f }
    }
    return $eff{$d} = \@out;
}
# A usage's features: its type's effective features, overridden by its own nested ones.
sub usage_feats {
    my $u = shift;
    my (@out, %pos);
    my $base = $u->{tdef} // ($u->{merged} && $u->{merged}{tdef});
    if ($base) { for my $f (@{effective($base)}) { $pos{$f->{name}} = @out; push @out, $f } }
    for my $f (@{$u->{feats}}) {
        my $key = defined $f->{redef} && defined $pos{$f->{redef}} ? $f->{redef} : $f->{name};
        if (defined $pos{$key}) { $out[$pos{$key}] = { %$f, merged => $out[$pos{$key}] } }
        else { $pos{$f->{name}} = @out; push @out, $f }
    }
    return \@out;
}
sub parts { grep { $_->{kind} eq 'part' } @{$_[0]} }

# ------------------------------------------------------------------------------------------
# Trees
# ------------------------------------------------------------------------------------------
sub pick_roots {
    my @roots;
    if (@{$O{root}}) {
        for my $r (@{$O{root}}) {
            my $d = find_def([split /::/, $r]);
            if (!$d) { next if $QUIET; print STDERR "sysml-tree-svg: no part def '$r'\n"; exit 2 }
            push @roots, $d;
        }
    } else {
        my %used;
        for my $d (@defs) { for my $f (parts(effective($d))) { my $t = $f->{tdef} // ($f->{merged} && $f->{merged}{tdef}); $used{$t} = 1 if $t && !$f->{ref} } }
        @roots = grep { !$used{$_} && ($O{all} || parts(effective($_))) } @defs;
    }
    return @roots;
}
my ($nnodes, $ncycle, $ncut) = (0, 0, 0);
sub build {
    my ($label_src, $feats, $depth, $path) = @_;
    my @kids;
    for my $p (parts($feats)) {
        my $t = $p->{tdef} // ($p->{merged} && $p->{merged}{tdef});
        my $n = { u => $p, depth => $depth, t => $t };
        $nnodes++;
        if ($p->{ref}) { $n->{note} = '' }
        elsif ($t && $path->{$t}) { $n->{note} = 'cycle'; $ncycle++; warnat($p->{file}, $p->{line}, "recursive composition: '$p->{name}' : $t->{name}") }
        elsif ($depth >= $O{depth}) { my @k = parts(usage_feats($p)); if (@k) { $n->{note} = 'cut'; $ncut++ } }
        else { $n->{kids} = build($p, usage_feats($p), $depth + 1, { %$path, ($t ? ($t => 1) : ()) }) }
        push @kids, $n;
    }
    return \@kids;
}

# ------------------------------------------------------------------------------------------
# Box text and size
# ------------------------------------------------------------------------------------------
my ($CW, $FS, $SFS, $LH, $PADX, $COLGAP, $VGAP, $TOP, $PAD) = (7.2, 12, 10.5, 15, 10, 56, 8, 70, 16);
sub tw { length($_[0]) * $CW }
sub stw { length($_[0]) * $CW * $SFS / $FS }
sub mstr { my $m = shift; defined $m ? "[$m]" : '' }
sub meta_line { my ($kw, @m) = @_; join ' ', "\x{ab}$kw\x{bb}", map { "\@$_" } @m }
sub feat_lines {
    my $feats = shift;
    my @l;
    for my $f (grep { $_->{kind} =~ /^(?:attribute|port|item)$/ } @$feats) {
        my $type = $f->{type} ? ' : ' . ($f->{conj} ? '~' : '') . join('::', @{$f->{type}}) : '';
        push @l, ($f->{inherited} ? '^' : '') . ($f->{dir} ? "$f->{dir} " : '') . ($f->{kind} eq 'attribute' ? '' : "$f->{kind} ") . "$f->{name}$type" . mstr($f->{mult});
    }
    return @l;
}
sub label_node {
    my ($n, $pkey) = @_;
    my (@lines, $kwl, @fall);
    if ($n->{def}) {
        my $d = $n->{def};
        $kwl = meta_line('part def', @{$d->{meta}});
        my $sup = @{$d->{supdefs}} ? ' :> ' . join(', ', map { $_->{name} } @{$d->{supdefs}}) : '';
        @lines = ($d->{name} . $sup);
        $n->{sub} = join('::', @{$d->{pkg}});
        @fall = feat_lines(effective($d));
        $n->{nparts} = scalar parts(effective($d));
        $n->{doc} = $d->{doc}; $n->{at} = "$d->{file}:$d->{line}";
        $n->{key} = 'def:' . join('::', @{$d->{pkg}}, $d->{name});
        $n->{show} = $d->{name};
    } else {
        my $u = $n->{u};
        my $meta = [@{$u->{meta} // []}, ($n->{t} ? @{$n->{t}{meta}} : ())];
        $kwl = meta_line($u->{ref} ? 'ref part' : 'part', @$meta);
        my $type = $u->{type} ? ' : ' . join('::', @{$u->{type}}) : ($u->{merged} && $u->{merged}{type} ? ' : ' . join('::', @{$u->{merged}{type}}) : '');
        my $redef = $u->{redef} ? ' :>> ' . $u->{redef} : '';
        my $nm = $u->{redef} && $u->{redef} eq $u->{name} ? ":>> $u->{name}" : "$u->{name}$redef";
        @lines = (($u->{inherited} ? '^' : '') . $nm . $type . mstr($u->{mult} // ($u->{merged} && $u->{merged}{mult})));
        $lines[0] .= ' (recursive)' if ($n->{note} // '') eq 'cycle';
        $lines[0] .= ' (...)' if ($n->{note} // '') eq 'cut';
        @fall = feat_lines(usage_feats($u));
        $n->{nparts} = scalar parts(usage_feats($u));
        $n->{doc} = $u->{doc} // ($n->{t} && $n->{t}{doc});
        $n->{at} = "$u->{file}:$u->{line}";
        $n->{key} = "$pkey/$u->{name}";
        $n->{show} = $u->{name};
    }
    $n->{kwl} = $kwl; $n->{lines} = \@lines; $n->{fall} = \@fall;
    $n->{feat} = [$O{features} ? @fall : ()];
    $n->{st} = 'same'; $n->{why} = [];
    $n->{bad} = $O{outline} && (($n->{def} && $n->{nparts}) || ($n->{kids} && @{$n->{kids}}))
              && ($n->{nparts} < 2 || $n->{nparts} > 9) ? 1 : 0;
    label_node($_, $n->{key}) for @{$n->{kids} // []};
}

sub analyze {
    my ($quiet, @files) = @_;
    local $QUIET = $quiet;
    @defs = (); %defsByName = (); %eff = (); ($nnodes, $ncycle, $ncut) = (0, 0, 0);
    parse_files(@files);
    resolve_all();
    my @trees = map { my $d = $_; { def => $d, depth => 0, kids => build($d, effective($d), 1, { $d => 1 }) } } pick_roots();
    label_node($_, '') for @trees;
    return { trees => \@trees, ndefs => scalar @defs, nnodes => $nnodes, ncycle => $ncycle, ncut => $ncut, nfiles => scalar @files };
}

my $new = analyze(0, collect(@ARGV));
my $old = $O{compare} ? analyze(1, collect(@{$O{compare}})) : undef;
my @trees = @{$new->{trees}};
$TOP = 86 if $old;

# ------------------------------------------------------------------------------------------
# Compare: match nodes by path, mark added / changed / removed, keep removed as ghosts.
# ------------------------------------------------------------------------------------------
sub merge_seq {
    my ($new, $old) = @_;
    my %oi; for my $i (0 .. $#$old) { $oi{$old->[$i]{key}} //= $i }
    my %nk = map { $_->{key} => 1 } @$new;
    my (@out, $p); $p = 0;
    for my $n (@$new) {
        my $i = $oi{$n->{key}};
        if (defined $i) {
            while ($p < $i) { my $o = $old->[$p++]; push @out, [$o, 'removed'] unless $nk{$o->{key}} }
            $p = $i + 1 if $i >= $p;
            push @out, [$n, 'same', $old->[$i]];
        } else { push @out, [$n, 'added'] }
    }
    while ($p < @$old) { my $o = $old->[$p++]; push @out, [$o, 'removed'] unless $nk{$o->{key}} }
    return @out;
}
sub mark { my ($n, $st) = @_; $n->{st} = $st; mark($_, $st) for @{$n->{kids} // []} }
sub merge_nodes {
    my ($new, $old) = @_;
    my @out;
    for my $m (merge_seq($new, $old)) {
        my ($n, $st, $o) = @$m;
        if ($st ne 'same') { mark($n, $st); push @out, $n; next }
        my @why;
        my $was = join ' / ', ($o->{kwl} ne $n->{kwl} ? $o->{kwl} : ()), @{$o->{lines}};
        push @why, "was $was" if $o->{kwl} ne $n->{kwl} || join("\n", @{$o->{lines}}) ne join("\n", @{$n->{lines}});
        my %of = map { $_ => 1 } @{$o->{fall}}; my %nf = map { $_ => 1 } @{$n->{fall}};
        my @add = grep { !$of{$_} } @{$n->{fall}}; my @del = grep { !$nf{$_} } @{$o->{fall}};
        push @why, 'features ' . join(', ', (map { "+$_" } @add), map { "-$_" } @del) if @add || @del;
        push @why, 'doc changed' if ($o->{doc} // '') ne ($n->{doc} // '');
        $n->{why} = \@why;
        $n->{st} = @why ? 'changed' : 'same';
        $n->{kids} = [merge_nodes($n->{kids} // [], $o->{kids} // [])] if $n->{kids} || $o->{kids};
        push @out, $n;
    }
    return @out;
}
my (@changes, %cnt);
if ($old) {
    @trees = merge_nodes(\@trees, $old->{trees});
    my $walk; $walk = sub {
        my ($n, $parent_st) = @_;
        $cnt{$n->{st}}++ unless $n->{def};
        if ($n->{st} ne 'same' && ($n->{st} eq 'changed' || $n->{st} ne $parent_st)) {
            my $below = 0; my $c; $c = sub { for (@{$_[0]{kids} // []}) { $below++; $c->($_) } }; $c->($n) if $n->{st} ne 'changed';
            (my $path = $n->{key}) =~ s{^def:(?:.*::)?}{}; $path =~ s{/}{.}g;
            push @changes, ($n->{st} eq 'removed' ? "$n->{at}" : $n->{at}) . ": note: " . ($n->{def} ? 'part def ' : 'part ') . "$path $n->{st}"
                . ($below ? " (with $below part(s) below)" : '') . (@{$n->{why}} ? ': ' . join('; ', @{$n->{why}}) : '');
        }
        $walk->($_, $n->{st}) for @{$n->{kids} // []};
    };
    $walk->($_, 'same') for @trees;
}
if ($O{changed}) {
    my $prune; $prune = sub {
        my $n = shift;
        my @k = @{$n->{kids} // []};
        return $n->{st} ne 'same' unless @k;
        my (@keep, $hidden); $hidden = 0;
        for my $c (@k) { if ($prune->($c)) { push @keep, $c } else { $hidden++ } }
        push @keep, { more => $hidden, depth => $n->{depth} + 1, st => 'same', kwl => '', lines => ["$hidden unchanged part(s)"],
                      feat => [], why => [], key => "$n->{key}/..." } if $hidden && (@keep || $n->{st} ne 'same');
        $n->{kids} = \@keep;
        return $n->{st} ne 'same' || grep { !$_->{more} } @keep;
    };
    @trees = grep { $prune->($_) } @trees;
}

sub size_node {
    my $n = shift;
    my @lines = @{$n->{lines}}; my $kwl = $n->{kwl};
    my $w = 0;
    for my $x (stw($kwl), map({ tw($_) } @lines), map({ stw($_) } @{$n->{feat}}), $n->{sub} ? stw($n->{sub}) : 0) { $w = $x if $x > $w }
    $n->{w} = $w + 2 * $PADX;
    $n->{h} = 8 + $LH * (($kwl ne '' ? 1 : 0) + @lines + ($n->{sub} ? 1 : 0)) + (@{$n->{feat}} ? 6 + $LH * @{$n->{feat}} : 0) + 2;
    size_node($_) for @{$n->{kids} // []};
}
size_node($_) for @trees;

# ------------------------------------------------------------------------------------------
# Layout: column per depth; leaves stacked; parent centered on its children.
# ------------------------------------------------------------------------------------------
my @colw;
sub widths { my $n = shift; $colw[$n->{depth}] = $n->{w} if !defined $colw[$n->{depth}] || $n->{w} > $colw[$n->{depth}]; widths($_) for @{$n->{kids} // []} }
widths($_) for @trees;
my @colx = ($PAD);
push @colx, $colx[-1] + $colw[$_ - 1] + $COLGAP for 1 .. $#colw;

my $cursor = $TOP;
sub shift_tree { my ($n, $dy) = @_; $n->{y} += $dy; shift_tree($_, $dy) for @{$n->{kids} // []} }
sub place {
    my $n = shift;
    my $start = $cursor;
    $n->{x} = $colx[$n->{depth}];
    my @k = @{$n->{kids} // []};
    if (!@k) { $n->{y} = $cursor; $cursor += $n->{h} + $VGAP; return }
    place($_) for @k;
    my $c = ($k[0]{y} + $k[0]{h} / 2 + $k[-1]{y} + $k[-1]{h} / 2) / 2;
    $n->{y} = $c - $n->{h} / 2;
    if ($n->{y} < $start) { my $dy = $start - $n->{y}; shift_tree($_, $dy) for @k; $n->{y} = $start; $cursor += $dy }
    $cursor = $n->{y} + $n->{h} + $VGAP if $n->{y} + $n->{h} + $VGAP > $cursor;
}
for my $t (@trees) { place($t); $cursor += 18 }
my $W = $colx[-1] + ($colw[-1] // 200) + $PAD;
$W = 640 if $W < 640;
my $H = $cursor + 20;

# ------------------------------------------------------------------------------------------
# Draw
# ------------------------------------------------------------------------------------------
sub esc { my $s = shift // ''; $s =~ s/&/&amp;/g; $s =~ s/</&lt;/g; $s =~ s/>/&gt;/g; $s =~ s/"/&quot;/g; $s }
my %C = (ink => '#212121', dim => '#616161', line => '#78909c', def => '#e8eaf6', defl => '#283593',
         use => '#ffffff', usel => '#455a64', ref => '#fafafa', bad => '#e65100', badbg => '#fff3e0', inh => '#7b1fa2',
         added => '#2e7d32', addedbg => '#e8f5e9', changed => '#ef6c00', changedbg => '#fff3e0',
         removed => '#c62828', removedbg => '#f5f5f5');
my @o;
push @o, qq{<?xml version="1.0" encoding="UTF-8"?>},
  qq{<svg xmlns="http://www.w3.org/2000/svg" width="$W" height="$H" viewBox="0 0 $W $H" font-family="DejaVu Sans Mono, Consolas, Menlo, monospace" font-size="$FS">},
  qq{<!-- generated by sysml-tree-svg.pl from } . (esc(join(' ', @ARGV) . ($O{compare} ? ', compared with ' . join(' ', @{$O{compare}}) : '')) =~ s/-(?=-)/- /gr) . qq{ -->},
  qq{<rect width="100%" height="100%" fill="#ffffff"/>};
my $title = $O{title} // ($old ? 'Part decomposition changes' : 'Part decomposition');
my $sum = sprintf '%d part def(s), %d tree(s), %d part node(s)%s%s', $new->{ndefs}, scalar @{$new->{trees}}, $new->{nnodes},
    $new->{ncycle} ? ", $new->{ncycle} recursive" : '', $new->{ncut} ? ", $new->{ncut} cut at depth $O{depth}" : '';
$sum .= '; changes only' if $O{changed};
my $dsum = $old ? sprintf('parts +%d -%d ~%d', $cnt{added} // 0, $cnt{removed} // 0, $cnt{changed} // 0) : '';
my $nbad = 0;
push @o, qq{<text x="$PAD" y="26" font-size="16" font-weight="bold" fill="$C{ink}">} . esc($title) . '</text>';
my $sumidx = @o; push @o, '';       # filled after drawing (needs the outline count)

my @edges; my @boxes;
sub draw {
    my $n = shift;
    my @k = @{$n->{kids} // []};
    if (@k) {
        my $x1 = $n->{x} + $n->{w}; my $y1 = $n->{y} + $n->{h} / 2;
        my $bx = $x1 + $COLGAP / 2;
        my @ys = map { $_->{y} + $_->{h} / 2 } @k;
        my $composite = grep { !($_->{u} && $_->{u}{ref}) } @k;
        push @edges, sprintf(qq{<path d="M%.1f %.1f H%.1f" stroke="$C{line}" fill="none"/>}, $x1 + ($composite ? 12 : 0), $y1, $bx);
        my ($ymin, $ymax) = (sort { $a <=> $b } @ys, $y1)[0, -1];
        push @edges, sprintf(qq{<path d="M%.1f %.1f V%.1f" stroke="$C{line}" fill="none"/>}, $bx, $ymin, $ymax);
        for my $c (@k) {
            my $dash = $c->{u} && $c->{u}{ref} || $c->{more} ? ' stroke-dasharray="4 3"' : '';
            my ($col, $w) = ($C{line}, 1);
            ($col, $w) = ($C{added}, 2) if $c->{st} eq 'added';
            ($col, $w, $dash) = ($C{removed}, 1.6, ' stroke-dasharray="3 3"') if $c->{st} eq 'removed';
            push @edges, sprintf(qq{<path d="M%.1f %.1f H%.1f" stroke="$col" stroke-width="$w" fill="none"$dash/>}, $bx, $c->{y} + $c->{h} / 2, $c->{x});
        }
        push @edges, sprintf(qq{<path d="M%.1f %.1f l6 -4.5 l6 4.5 l-6 4.5 z" fill="$C{usel}"/>}, $x1, $y1) if $composite;
    }
    my ($x, $y, $w, $h) = @$n{qw(x y w h)};
    my $isdef = $n->{def} ? 1 : 0;
    my $isref = !$isdef && $n->{u} && $n->{u}{ref};
    my $st = $n->{st} // 'same';
    my $gone = $st eq 'removed';
    my $bad = $n->{bad} && !$gone; $nbad++ if $bad;
    my $stroke = $bad ? $C{bad} : $isdef ? $C{defl} : $C{usel};
    my $fill = $bad ? $C{badbg} : $isdef ? $C{def} : $isref ? $C{ref} : $C{use};
    my $sw = $isdef ? '1.6' : '1.1';
    if ($st ne 'same') { $stroke = $C{$st}; $fill = $C{"${st}bg"}; $sw = 2.2 }
    my $rx = $isdef ? 0 : 7;
    my $dash = $isref || $gone ? ' stroke-dasharray="5 3"' : '';
    if ($n->{more}) {
        push @boxes, sprintf(qq{<g><title>%s</title><rect x="%.1f" y="%.1f" width="%.1f" height="%.1f" rx="7" fill="#ffffff" stroke="$C{line}" stroke-dasharray="2 3"/>}
            . qq{<text x="%.1f" y="%.1f" font-style="italic" fill="$C{dim}">%s</text></g>},
            esc("$n->{more} part(s) not changed"), $x, $y, $w, $h, $x + $PADX, $y + 4 + $LH - 2, esc($n->{lines}[0]));
        return;
    }
    my @tip = (join(' / ', grep { $_ ne '' } $n->{kwl}, @{$n->{lines}}));
    push @tip, uc($st) . (@{$n->{why} // []} ? ': ' . join('; ', @{$n->{why}}) : '') if $st ne 'same';
    push @tip, $n->{doc} if defined $n->{doc};
    push @tip, "$n->{nparts} part(s)" . ($bad ? ' - outside the 2 to 9 outline rule' : '') if $n->{nparts} || $bad;
    push @tip, 'reference: not owned, not expanded' if $isref;
    push @tip, ($gone ? 'was at ' : '') . $n->{at};
    my $lt = $gone ? ' text-decoration="line-through"' : '';
    my @g = (qq{<g} . ($gone ? ' opacity="0.65"' : '') . qq{><title>} . esc(join "\n", @tip) . '</title>',
             sprintf(qq{<rect x="%.1f" y="%.1f" width="%.1f" height="%.1f" rx="$rx" fill="$fill" stroke="$stroke" stroke-width="%s"$dash/>}, $x, $y, $w, $h, $sw));
    my $ty = $y + 4 + $LH - 3;
    push @g, sprintf(qq{<text x="%.1f" y="%.1f" font-size="$SFS" fill="$C{dim}">%s</text>}, $x + $PADX, $ty, esc($n->{kwl}));
    for my $l (@{$n->{lines}}) {
        $ty += $LH;
        my $col = $l =~ /^\^/ ? $C{inh} : $C{ink};
        push @g, sprintf(qq{<text x="%.1f" y="%.1f" font-weight="%s" fill="$col"$lt>%s</text>}, $x + $PADX, $ty, $isdef ? 'bold' : 'normal', esc($l));
    }
    if ($n->{sub}) { $ty += $LH; push @g, sprintf(qq{<text x="%.1f" y="%.1f" font-size="$SFS" fill="$C{dim}">%s</text>}, $x + $PADX, $ty, esc($n->{sub})) }
    if (@{$n->{feat}}) {
        $ty += 6;
        push @g, sprintf(qq{<path d="M%.1f %.1f H%.1f" stroke="$stroke" stroke-width="0.8"/>}, $x, $ty - 1, $x + $w);
        for my $l (@{$n->{feat}}) {
            $ty += $LH;
            push @g, sprintf(qq{<text x="%.1f" y="%.1f" font-size="$SFS" fill="%s">%s</text>}, $x + $PADX, $ty - 2, $l =~ /^\^/ ? $C{inh} : $C{dim}, esc($l));
        }
    }
    push @g, '</g>';
    push @boxes, @g;
    draw($_) for @k;
}
draw($_) for @trees;
$sum .= ", $nbad outside the 2-9 outline rule" if $O{outline};
$o[$sumidx] = qq{<text x="$PAD" y="46" fill="$C{dim}">} . esc($sum) . '</text>'
    . ($old ? qq{<text x="$PAD" y="62" fill="$C{ink}">} . esc($dsum) . '</text>' : '');
# legend
my $lx = $PAD + tw($sum) + 64;
push @o, qq{<g transform="translate($lx,14)" font-size="11" fill="$C{dim}">},
  qq{<rect x="0" y="0" width="22" height="13" fill="$C{def}" stroke="$C{defl}"/><text x="28" y="11">part def</text>},
  qq{<rect x="96" y="0" width="22" height="13" rx="5" fill="$C{use}" stroke="$C{usel}"/><text x="124" y="11">part</text>},
  qq{<rect x="168" y="0" width="22" height="13" rx="5" fill="$C{ref}" stroke="$C{usel}" stroke-dasharray="4 2"/><text x="196" y="11">ref part</text>},
  qq{<path d="M0 30 l6 -4.5 l6 4.5 l-6 4.5 z" fill="$C{usel}"/><path d="M12 30 H34" stroke="$C{line}"/><text x="40" y="34">owns</text>},
  qq{<text x="96" y="34" fill="$C{inh}">^inherited</text>},
  ($O{outline} ? qq{<rect x="196" y="23" width="22" height="13" fill="$C{badbg}" stroke="$C{bad}"/><text x="224" y="34">outside 2-9</text>} : ()),
  ($old ? (qq{<rect x="0" y="44" width="22" height="13" rx="5" fill="$C{addedbg}" stroke="$C{added}" stroke-width="2"/><text x="28" y="55">added</text>},
           qq{<rect x="96" y="44" width="22" height="13" rx="5" fill="$C{changedbg}" stroke="$C{changed}" stroke-width="2"/><text x="124" y="55">changed</text>},
           qq{<rect x="196" y="44" width="22" height="13" rx="5" fill="$C{removedbg}" stroke="$C{removed}" stroke-dasharray="3 2"/><text x="224" y="55" text-decoration="line-through">removed</text>}) : ()),
  '</g>';
push @o, @edges, @boxes, '</svg>';

open my $out, '>:encoding(UTF-8)', $O{o} or die "$O{o}: $!";
print $out map { "$_\n" } @o;
close $out;
print "$_\n" for sort { my @a = $a =~ /^(.*?):(\d+):/; my @b = $b =~ /^(.*?):(\d+):/; $a[0] cmp $b[0] || $a[1] <=> $b[1] || $a cmp $b } @changes;
printf "tree-svg: %d file(s), %s, %d warning(s)%s -> %s\n", $new->{nfiles}, $sum, $nwarn, ($old ? "; $dsum" : ''), $O{o};
exit 0;
