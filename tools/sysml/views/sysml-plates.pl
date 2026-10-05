#!/usr/bin/perl
# sysml-plates.pl : drawing plates (sheets) from the views declared in a SysML v2 model, laid
# out the way a technical drawing is: ISO 5457 sheet, frame, centring marks and grid reference,
# ISO 7200 title block, ISO 128 line widths, ISO 3098 style lettering. Core Perl 5 only.
#
#   perl sysml-plates.pl [-o DIR] [--size auto|A4|A3|A2|A1|A0] [--auto] [--color]
#                        [--owner TEXT] [--creator TEXT] [--approver TEXT] [--status TEXT]
#                        [--rev R] [--date YYYY-MM-DD] [--prefix DWG] [--min-text MM] [--source TEXT] DIR|FILE...
#
# One plate per `view` usage in the model (or, with --auto or when the model has none, one per
# top part def tree, one per def with connections, one trace plate and one package plate):
#
#   render asTreeDiagram            part decomposition (sysml-tree-svg.pl), or the trace view
#                                   when the view's filter is @SysML::RequirementUsage
#   render asInterconnectionDiagram parts, ports, connections (sysml-ibd-svg.pl)
#   render asElementTable           a table of the exposed elements that pass the filter
#   render asTextualNotation        the exposed elements' source text
#   (no render)                     by the view def's filter, else a tree
# A view def named like *Package* draws the package/marking view (sysml-pkg-svg.pl).
#
# Title block fields come from the view: drawing number = its short name (<'DWG-001'>), title =
# its doc (first sentence) or its name, classification = the highest @Marking among the view's
# package and the exposed packages. An optional @Drawing { number; revision; size; status;
# drawnBy; approvedBy; owner; } on the view overrides them (DrawingMeta.sysml declares it).
# Text and lines are black on white unless --color. --size auto (default) picks the smallest
# sheet on which diagram text is at least --min-text mm (default 2.0) high.
# The Source field shows `git describe` when run in a Git checkout (or --source TEXT).
# Writes DIR/<number>.svg per sheet and DIR/plates.html (all sheets, prints one per page).
# Exit status: 0 done, 1 warnings (a view that could not be drawn, text below the minimum), 2 usage.
use strict; use warnings;
use File::Find; use Getopt::Long; use File::Basename qw(dirname); use File::Temp qw(tempdir); use File::Path qw(make_path);
binmode STDOUT, ':encoding(UTF-8)'; binmode STDERR, ':encoding(UTF-8)';

my %O = (o => 'plates', size => 'auto', 'min-text' => 2.0, prefix => 'DWG', status => 'In preparation', rev => '-');
GetOptions(\%O, 'o=s', 'size=s', 'auto', 'color', 'owner=s', 'creator=s', 'approver=s', 'status=s', 'rev=s', 'date=s',
           'prefix=s', 'min-text=f', 'source=s') && @ARGV
    or do { print STDERR "usage: perl sysml-plates.pl [-o DIR] [--size auto|A4|A3|A2|A1|A0] [--auto] [--color] [--owner T] [--creator T] [--approver T] [--status T] [--rev R] [--date YYYY-MM-DD] [--prefix DWG] [--min-text MM] DIR|FILE...\n"; exit 2 };
my %SHEET = (A4 => [297, 210, 6, 4], A3 => [420, 297, 8, 6], A2 => [594, 420, 12, 8], A1 => [841, 594, 16, 12], A0 => [1189, 841, 24, 16]);
if ($O{size} ne 'auto' && !$SHEET{uc $O{size}}) { print STDERR "sysml-plates: --size must be auto, A4, A3, A2, A1 or A0\n"; exit 2 }
my $DATE = $O{date} // do { my @t = localtime; sprintf '%04d-%02d-%02d', $t[5] + 1900, $t[4] + 1, $t[3] };
my @files;
for my $a (@ARGV) {
    if (-d $a) { find(sub { push @files, $File::Find::name if /\.sysml$/ }, $a) }
    elsif (-f $a) { push @files, $a }
    else { print STDERR "sysml-plates: $a: no such file or directory\n"; exit 2 }
}
@files = sort @files;
my $here = dirname($0);
my $NWARN = 0;
sub warnmsg { my ($f, $l, $m) = @_; printf STDERR "%s:%s: warning: %s\n", $f, $l, $m; $NWARN++ }    # the messages: the warnmsg calls

# ------------------------------------------------------------------------------------------
# Parse: elements (kind, name, short name, package, owner, metadata, doc, source lines),
# views (render, expose, filter), markings
# ------------------------------------------------------------------------------------------
my $NAME = qr/(?:[A-Za-z_]\w*|'(?:[^'\\]|\\.)*')/;
my $REF  = qr/$NAME(?:\s*(?:::|\.)\s*$NAME)*/;
sub unq { my $n = shift; return $n unless $n =~ /^'(.*)'$/s; (my $u = $1) =~ s/\\(.)/$1/g; $u }
sub segs { my $r = shift; my @s; push @s, unq($1) while $r =~ /\G\s*($NAME)\s*(?:::|\.)?/g; @s }
my (@E, %PKG, @LEVELS, %SRC);
for my $f (@files) {
    open my $h, '<:encoding(UTF-8)', $f or die "$f: $!";
    local $/; my $t = <$h>;
    $SRC{$f} = [split /\n/, $t, -1];
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
                my $n = $stack[-1]{node} // $stack[-1]{pk}; $n->{doc} //= $body if $n; $head = '' }
            elsif ($head =~ /^\s*comment\b/) { $head = '' }
        }
        elsif ($t =~ /\G("(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*')/gc) { my $q = $1; $hline = $line if $head !~ /\S/; $head .= $q; $line += ($q =~ tr/\n//) }
        elsif ($t =~ /\G([{};])/gc) {
            my $c = $1;
            if ($c eq '}') {
                if (@stack > 1) { my $s = pop @stack; $s->{node}{endline} = $line if $s->{node}; finish($s) }
                $head = ''; next;
            }
            my $st = statement($head, $f, $hline, \@stack, $c);
            $head = '';
            if ($c eq '{') { push @stack, $st // { kind => 'other', pkg => $stack[-1]{pkg} } }
            elsif ($st && $st->{kind} eq 'meta') { finish($st) }
        }
        elsif ($t =~ m{\G([^{};"'/\n]+|/)}gc) { my $x = $1; $hline = $line if $head !~ /\S/ && $x =~ /\S/; $head .= $x }
    }
}
sub finish {
    my $s = shift;
    return unless $s->{kind} eq 'meta';
    my $tg = $s->{target} or return;
    push @{$tg->{meta}}, $s->{name};
    $tg->{attrs}{$s->{name}} = { %{$s->{attrs}} };
    $tg->{marking} = $s->{attrs}{level} if $s->{name} eq 'Marking' && defined $s->{attrs}{level};
}
sub statement {
    my ($s, $f, $line, $stack, $c) = @_;
    my $top = $stack->[-1];
    $s =~ s/\s+/ /g; $s =~ s/^ | $//g;
    return undef if $s eq '';
    my $pkg = $top->{pkg};
    my ($owner) = map { $_->{node} } grep { $_->{node} } reverse @$stack;
    my ($pk) = map { $_->{pk} } grep { $_->{pk} } reverse @$stack;
    if ($top->{kind} eq 'meta') {
        if ($s =~ /^(?::>>\s*)?(\w+)\s*=\s*("(?:[^"\\]|\\.)*"|\S+)/) { my ($k, $v) = ($1, $2); $v = $v =~ /^"(.*)"$/s ? $1 : $v; $v =~ s/^(?:\w+::)+//; $top->{attrs}{$k} = $v }
        return undef;
    }
    if ($top->{kind} eq 'levels') { push @LEVELS, unq($1) if $s =~ /^(?:enum\s+)?($NAME)$/ && !grep { $_ eq unq($1) } @LEVELS; return undef }
    if ($s =~ /^@\s*(?:\w+::)*(\w+)\s*$/ || $s =~ /^metadata\s+(?:\w+::)*(\w+)\s*$/) {
        return { kind => 'meta', name => $1, target => $owner // $pk, attrs => {}, pkg => $pkg };
    }
    $s =~ s/^(?:(?:public|private|protected|abstract|variation|individual|derived|readonly)\s+)*//;
    my @hash; push @hash, $1 while $s =~ s/^#\s*(?:\w+::)*(\w+)\s*//;
    if ($s =~ /^(?:standard\s+)?(?:library\s+)?package\s+($NAME)/) {
        my @p = (@$pkg, unq($1)); my $q = join '::', @p;
        my $p = $PKG{$q} //= { name => unq($1), qname => $q, path => \@p, parent => $pk, file => $f, line => $line, meta => [], attrs => {} };
        return { kind => 'package', pkg => \@p, pk => $p };
    }
    if ($s =~ /^enum\s+def\s+Level\b/) { return { kind => 'levels', pkg => $pkg } }
    if ($owner && $s =~ /^(connect|connection|interface|flow)\b(?!\s+def\b)/) { my $d = $owner; $d = $d->{owner} while $d && !$d->{isdef}; $d->{hasconn} = 1 if $d; return undef }
    if ($owner && $owner->{kind} eq 'view') {
        if ($s =~ /^expose\s+($REF)\s*(::\s*\*\*|::\s*\*)?/) { push @{$owner->{expose}}, { segs => [segs($1)], star => ($2 // '') =~ /\*\*/ ? '**' : $2 ? '*' : '' }; return undef }
        if ($s =~ /^render\s+(?:\w+::)*(\w+)/) { $owner->{render} = $1; return undef }
        if ($s =~ /^filter\s+(.*)$/) { push @{$owner->{filter}}, $1; return undef }
    }
    if ($s =~ /^(\w+(?:\s+def)?)\s+(?:<'((?:[^'\\]|\\.)*)'>\s*)?($NAME)(.*)$/ && $1 !~ /^(?:import|alias|dependency|doc|comment|subject|objective|return|in|out|inout|expose|render|filter|satisfy|verify|ref|end|bind|succession|first|then|send|accept|assign|assert|require|assume|frame)$/) {
        my ($kw, $id, $n, $rest) = ($1, $2 // '', unq($3), $4);
        my $isdef = $kw =~ /\sdef$/ ? 1 : 0;
        (my $k = $kw) =~ s/\s+def$//;
        my $e = { kind => $k, isdef => $isdef, name => $n, id => $id, pkg => $pkg, pk => $pk, owner => $owner, file => $f, line => $line,
                  meta => [@hash], attrs => {}, depth => scalar(grep { $_->{node} } @$stack) };
        $e->{type} = (segs($1))[-1] if $rest =~ /^\s*(?::|defined\s+by)\s*($REF)/;
        $e->{typesegs} = [segs($1)] if $rest =~ /^\s*(?::|defined\s+by)\s*($REF)/;
        push @E, $e;
        return $c eq '{' ? { kind => 'node', node => $e, pkg => $pkg } : undef;
    }
    return undef;
}
@LEVELS = qw(U CUI ITAR) unless @LEVELS;
my %RANK = map { $LEVELS[$_] => $_ } 0 .. $#LEVELS;
sub pkg_rank { my $p = shift; my $r = -1; for (my $o = $p; $o; $o = $o->{parent}) { my $m = $o->{marking}; $r = $RANK{$m} if defined $m && defined $RANK{$m} && $RANK{$m} > $r } $r }
sub elem_rank { my $e = shift; my $r = $e->{pk} ? pkg_rank($e->{pk}) : -1;
    for (my $o = $e; $o; $o = $o->{owner}) { my $m = $o->{marking}; $r = $RANK{$m} if defined $m && defined $RANK{$m} && $RANK{$m} > $r } $r }
sub qn { my $e = shift; my @n = ($e->{name}); for (my $o = $e->{owner}; $o; $o = $o->{owner}) { unshift @n, $o->{name} } join '::', @{$e->{pkg}}, @n }
my %QN; $QN{qn($_)} //= $_ for @E;

# ------------------------------------------------------------------------------------------
# Plates: from views, or automatic
# ------------------------------------------------------------------------------------------
my @views = grep { $_->{kind} eq 'view' && !$_->{isdef} } @E;
my %vdefs = map { $_->{name} => $_ } grep { $_->{kind} eq 'view' && $_->{isdef} } @E;
sub resolve_expose {        # -> list of elements and packages exposed
    my $x = shift;
    my $q = join '::', @{$x->{segs}};
    my @hit = $PKG{$q} ? ($PKG{$q}) : ();
    unless (@hit) {         # suffix match on elements and packages
        @hit = grep { my $n = $_->{qname} // qn($_); $n eq $q || $n =~ /::\Q$q\E$/ } (values %PKG), @E;
        @hit = sort { ($a->{qname} // qn($a)) cmp ($b->{qname} // qn($b)) } @hit;
        @hit = ($hit[0]) if @hit;
    }
    return () unless @hit;
    my $t = $hit[0];
    return ($t) unless $x->{star};
    if ($t->{qname} && $PKG{$t->{qname}}) {           # a package: its members (** = nested too)
        my $p = $t->{qname};
        return grep { my $ep = join '::', @{$_->{pkg}}; ($ep eq $p || ($x->{star} eq '**' && index($ep, "$p\::") == 0))
                      && ($x->{star} eq '**' || !$_->{owner}) } @E;
    }
    return grep { my $o = $_->{owner}; my $in = 0; for (; $o; $o = $o->{owner}) { if ($o == $t) { $in = 1; last } } $in && ($x->{star} eq '**' || $_->{owner} == $t) } @E;
}
my %SYSKIND = (PartUsage => ['part', 0], PartDefinition => ['part', 1], RequirementUsage => ['requirement', 0],
               RequirementDefinition => ['requirement', 1], ActionUsage => ['action', 0], ActionDefinition => ['action', 1],
               PortUsage => ['port', 0], PortDefinition => ['port', 1], InterfaceUsage => ['interface', 0],
               AttributeUsage => ['attribute', 0], ItemUsage => ['item', 0], ConstraintUsage => ['constraint', 0],
               VerificationCaseDefinition => ['verification', 1], StateUsage => ['state', 0], OccurrenceDefinition => ['occurrence', 1]);
sub pass_filter {
    my ($e, $filters) = @_;
    for my $f (@$filters) {
        my $ok = 0;
        while ($f =~ /@\s*((?:\w+::)*)(\w+)/g) {
            my ($ns, $n) = ($1, $2);
            if ($ns =~ /SysML::/ && $SYSKIND{$n}) { $ok = 1 if $e->{kind} eq $SYSKIND{$n}[0] && $e->{isdef} == $SYSKIND{$n}[1] }
            elsif (grep { $_ eq $n } @{$e->{meta}}) { $ok = 1 }
        }
        return 0 unless $ok;
    }
    return 1;
}

my @PLATES;     # { view, kind => tree|ibd|trace|pkg|table|text, roots|packages|elements, title, number, ... }
if (@views && !$O{auto}) {
    for my $v (@views) {
        my $vd = $v->{type} && $vdefs{$v->{type}};
        my @filters = (@{$v->{filter} // []}, ($vd ? @{$vd->{filter} // []} : ()));
        my $render = $v->{render} // ($vd && $vd->{render}) // '';
        my $vdn = $v->{type} // '';
        my @ex = map { resolve_expose($_) } @{$v->{expose} // []};
        for my $x (@{$v->{expose} // []}) { warnmsg($v->{file}, $v->{line}, "view '$v->{name}': expose '" . join('::', @{$x->{segs}}) . "' matches nothing") unless resolve_expose($x) }
        my @pk = grep { $_->{qname} } @ex;                  # packages exposed directly
        my @el = grep { !$_->{qname} } @ex;
        my @sel = @filters ? grep { pass_filter($_, \@filters) } @el : @el;
        my $isreq = grep { /RequirementUsage|RequirementDefinition/ } @filters;
        my %p = (view => $v, filters => \@filters, render => $render, vdef => $vdn);
        my @pkgs = sort keys %{{ map { (join('::', @{$_->{pkg}}) => 1) } @el, map { { pkg => $_->{path} } } @pk }};
        if ($vdn =~ /Package/i) { push @PLATES, { %p, kind => 'pkg' } }
        elsif ($render eq 'asTextualNotation') {
            my %in = map { ("$_" => 1) } @sel;
            my @top = grep { my $o = $_->{owner}; my $nested = 0; for (; $o; $o = $o->{owner}) { if ($in{"$o"}) { $nested = 1; last } } !$nested } @sel;
            push @PLATES, { %p, kind => 'text', elements => \@top };
        }
        elsif ($render eq 'asElementTable') { push @PLATES, { %p, kind => $isreq ? 'trace' : 'table', elements => \@sel, packages => \@pkgs } }
        elsif ($render eq 'asInterconnectionDiagram' || $vdn =~ /Interconnection/) {
            my @r = grep { $_->{kind} eq 'part' && $_->{isdef} && $_->{hasconn} } @el;
            @r = grep { $_->{kind} eq 'part' && $_->{isdef} } @el unless @r;
            push @PLATES, @r ? { %p, kind => 'ibd', roots => \@r } : ();
            warnmsg($v->{file}, $v->{line}, "view '$v->{name}': nothing to draw as an interconnection diagram") unless @r;
        }
        elsif ($isreq) { push @PLATES, { %p, kind => 'trace', packages => \@pkgs } }
        elsif ($render eq 'asTreeDiagram' || $render eq '' || $vdn =~ /General|Decomposition|Browser/) {
            my @defs = grep { $_->{kind} eq 'part' && $_->{isdef} } @el;
            my %used; for my $u (grep { $_->{kind} eq 'part' && !$_->{isdef} && $_->{type} } @E) { $used{$u->{type}}++ if $u->{owner} && grep { $_ == $u->{owner} } @defs }
            my @r = grep { !$used{$_->{name}} } @defs; @r = @defs unless @r;
            if (@r) { push @PLATES, { %p, kind => 'tree', roots => \@r } }
            elsif (@sel) { push @PLATES, { %p, kind => 'table', elements => \@sel } }
            else { warnmsg($v->{file}, $v->{line}, "view '$v->{name}': nothing to draw") }
        }
        else { warnmsg($v->{file}, $v->{line}, "view '$v->{name}': render $render is not supported; skipped") }
    }
} else {
    my @defs = grep { $_->{kind} eq 'part' && $_->{isdef} } @E;
    my %used; $used{$_->{type}}++ for grep { $_->{kind} eq 'part' && !$_->{isdef} && $_->{type} && $_->{owner} } @E;
    my %hasparts; $hasparts{$_->{owner}{name}} = 1 for grep { $_->{kind} eq 'part' && !$_->{isdef} && $_->{owner} && $_->{owner}{isdef} } @E;
    push @PLATES, { kind => 'tree', roots => [$_], auto => 1 } for grep { !$used{$_->{name}} && $hasparts{$_->{name}} } @defs;
    push @PLATES, { kind => 'ibd', roots => [$_], auto => 1 } for grep { $_->{hasconn} } @defs;
    push @PLATES, { kind => 'trace', auto => 1 } if grep { $_->{kind} eq 'requirement' && !$_->{isdef} } @E;
    push @PLATES, { kind => 'pkg', auto => 1 } if keys %PKG > 1;
}

# ------------------------------------------------------------------------------------------
# Draw each plate's content (an SVG from a renderer, or a table/text layout in mm)
# ------------------------------------------------------------------------------------------
my $TMP = tempdir('sysml-plates-XXXXXX', TMPDIR => 1, CLEANUP => 1);
my %KINDNAME = (tree => 'Part decomposition', ibd => 'Interconnection diagram', trace => 'Requirement trace',
                pkg => 'Packages and markings', table => 'Element table', text => 'Textual notation');
my $RN = 0;
sub run_renderer {
    my ($script, @args) = @_;
    my $out = "$TMP/r" . (++$RN) . ".svg";
    my $pid = open my $h, '-|', $^X, "$here/$script", '-o', $out, @args or die "$script: $!";
    my @lines = <$h>; close $h;
    return -f $out ? $out : undef;
}
my $n = 0;
for my $p (@PLATES) {
    my $v = $p->{view};
    my @sources = @files;
    if ($p->{kind} eq 'tree') { $p->{svg} = run_renderer('sysml-tree-svg.pl', (map { ('--root', join('::', @{$_->{pkg}}, $_->{name})) } @{$p->{roots}}), @sources) }
    elsif ($p->{kind} eq 'ibd') { $p->{svg} = run_renderer('sysml-ibd-svg.pl', (map { ('--root', join('::', @{$_->{pkg}}, $_->{name})) } @{$p->{roots}}), @sources) }
    elsif ($p->{kind} eq 'trace') { $p->{svg} = run_renderer('sysml-trace-svg.pl', ($O{color} ? () : '--mono'), (map { ('--package', $_) } @{$p->{packages} // []}), @sources) }
    elsif ($p->{kind} eq 'pkg') { $p->{svg} = run_renderer('sysml-pkg-svg.pl', '--hide', 'SecMeta', @sources) }
    if (grep { $p->{kind} eq $_ } qw(tree ibd trace pkg)) {
        unless ($p->{svg}) { warnmsg($v ? ($v->{file}, $v->{line}) : ('-', 0), "plate '" . ($v ? $v->{name} : $p->{kind}) . "' could not be drawn"); $p->{skip} = 1; next }
    }
    # title block data
    my $att = $v ? ($v->{attrs}{Drawing} // {}) : {};
    $p->{number} = $att->{number} // ($v && $v->{id} ne '' ? $v->{id} : sprintf('%s-%03d', $O{prefix}, ++$n));
    my $title = $v ? ($v->{doc} // '') : '';
    $title =~ s/^(.*?[.!?])(?:\s.*)?$/$1/; $title =~ s/[.]$//;
    if ($title eq '') {
        $title = $v ? join(' ', map { lc } $v->{name} =~ /([A-Z]?[a-z0-9]+|[A-Z]+(?![a-z]))/g) : $KINDNAME{$p->{kind}};
        $title = ucfirst $title;
    }
    $p->{title} = $title;
    $p->{sub} = $p->{roots} ? join(', ', map { $_->{name} } @{$p->{roots}})
              : $p->{packages} && @{$p->{packages}} ? join(', ', @{$p->{packages}})
              : $v ? join(', ', map { join('::', @{$_->{segs}}) . ($_->{star} ? "::$_->{star}" : '') } @{$v->{expose} // []}) : 'whole model';
    $p->{doctype} = $KINDNAME{$p->{kind}};
    $p->{ref} = $v ? qn($v) : "generated ($p->{kind})";
    $p->{rev} = $att->{revision} // $O{rev};
    $p->{status} = $att->{status} // $O{status};
    $p->{creator} = $att->{drawnBy} // $O{creator} // '';
    $p->{approver} = $att->{approvedBy} // $O{approver} // '';
    $p->{owner} = $att->{owner} // $O{owner} // '';
    # classification: highest marking of the view's package and everything it shows
    my $r = $v ? elem_rank($v) : -1;
    for my $e (@{$p->{roots} // []}, @{$p->{elements} // []}) { my $x = elem_rank($e); $r = $x if $x > $r }
    for my $q (@{$p->{packages} // []}) { my $x = $PKG{$q} ? pkg_rank($PKG{$q}) : -1; $r = $x if $x > $r }
    if (!$v || $p->{kind} eq 'pkg' || ($p->{kind} eq 'trace' && !@{$p->{packages} // []})) { for my $q (values %PKG) { my $x = pkg_rank($q); $r = $x if $x > $r } }
    $p->{marking} = $r >= 0 ? $LEVELS[$r] : 'UNMARKED';
    $p->{size} = uc($att->{size} // ($O{size} eq 'auto' ? 'AUTO' : $O{size}));
}
@PLATES = grep { !$_->{skip} } @PLATES;

# ------------------------------------------------------------------------------------------
# Sheet layout
# ------------------------------------------------------------------------------------------
my ($TBW, $TBH) = (180, 45);
sub frame_of { my $s = shift; my ($w, $h) = @{$SHEET{$s}}; return { x => 20, y => 10, w => $w - 30, h => $h - 20 } }
sub areas {         # candidate drawing areas inside the frame, clear of the title block
    my $s = shift; my $f = frame_of($s);
    return ([$f->{x} + 5, $f->{y} + 5, $f->{w} - 10, $f->{h} - 10 - $TBH - 4],          # above the title block
            [$f->{x} + 5, $f->{y} + 5, $f->{w} - 10 - $TBW - 4, $f->{h} - 10]);         # left of it
}
sub svg_size { my $f = shift; open my $h, '<:encoding(UTF-8)', $f or return (0, 0); local $/; my $t = <$h>;
    my ($w, $hh) = $t =~ /<svg[^>]*\bwidth="([\d.]+)"[^>]*\bheight="([\d.]+)"/; return ($w // 0, $hh // 0, $t) }
sub fit {           # best area and scale (mm per px) for a W x H px diagram on a sheet size
    my ($s, $W, $H) = @_;
    my ($best, $sc) = (undef, 0);
    for my $a (areas($s)) { next if $a->[2] <= 0 || $a->[3] <= 0; my $k = $a->[2] / $W < $a->[3] / $H ? $a->[2] / $W : $a->[3] / $H; ($best, $sc) = ($a, $k) if $k > $sc }
    $sc = 0.35 if $sc > 0.35;           # never larger than about 4 mm text
    return ($best, $sc);
}
my @OUT;
for my $p (@PLATES) {
    if ($p->{svg}) {
        my ($W, $H, $t) = svg_size($p->{svg});
        my $size = $p->{size};
        if ($size eq 'AUTO') {
            $size = 'A0';
            for my $s (qw(A4 A3 A2 A1 A0)) { my (undef, $k) = fit($s, $W, $H); if (12 * $k >= $O{'min-text'}) { $size = $s; last } }
        }
        my ($a, $k) = fit($size, $W, $H);
        warnmsg($p->{view} ? ($p->{view}{file}, $p->{view}{line}) : ('-', 0), sprintf("plate %s: diagram text is %.1f mm on %s, below %.1f mm", $p->{number}, 12 * $k, $size, $O{'min-text'}))
            if 12 * $k < $O{'min-text'} - 1e-9;
        my ($dw, $dh) = ($W * $k, $H * $k);
        my ($x, $y) = ($a->[0] + ($a->[2] - $dw) / 2, $a->[1] + ($a->[3] - $dh) / 2);
        $t =~ s/<\?xml[^>]*\?>//; $t =~ s{<script>.*?</script>}{}gs; $t =~ s/<!--.*?-->//gs;
        my ($root) = $t =~ /^\s*(<svg\b[^>]*>)/s;
        my $inherit = join ' ', grep { defined } map { $root =~ /\b($_="[^"]*")/ ? $1 : undef } qw(font-family font-size);
        $t =~ s/^\s*<svg\b[^>]*>//s; $t =~ s{</svg>\s*$}{}s;
        $t = "<g $inherit>$t</g>";       # keep the renderer's font (sizes and widths assume it)
        $t = mono($t) unless $O{color};
        push @OUT, { %$p, size => $size, body => sprintf(qq{<svg x="%.2f" y="%.2f" width="%.2f" height="%.2f" viewBox="0 0 %s %s" preserveAspectRatio="xMidYMid meet">%s</svg>}, $x, $y, $dw, $dh, $W, $H, $t),
                     scale => sprintf('NTS (%.2f mm/px)', $k) };
    } else {
        push @OUT, layout_rows($p);
    }
}

# black on white: dark colors become black, light fills become light grays (by luminance)
sub mono {
    my $t = shift;
    $t =~ s/#([0-9a-fA-F]{6})\b/gray($1)/ge;
    return $t;
}
sub gray { my $h = shift; my ($r, $g, $b) = map { hex } $h =~ /(..)(..)(..)/; my $l = 0.299 * $r + 0.587 * $g + 0.114 * $b;
    return '#000000' if $l < 185; my $v = int(255 - (255 - $l) * 0.8 + 0.5); sprintf '#%02x%02x%02x', $v, $v, $v }

# tables and source text: laid out in mm, continued on as many sheets as needed
sub layout_rows {
    my $p = shift;
    my $lh = $p->{kind} eq 'text' ? 3.6 : 5.0; my $th = 2.5;
    my $size = $p->{size};
    if ($size eq 'AUTO') {          # A4 when one sheet holds it all, else A3
        my $nrows = $p->{kind} eq 'text' ? (eval { my $c = 0; $c += ($_->{endline} // $_->{line}) - $_->{line} + 3 for @{$p->{elements}}; $c }) : @{$p->{elements}};
        my ($a4) = (areas('A4'))[0];
        $size = $nrows <= int(($a4->[3] - 10) / $lh) ? 'A4' : 'A3';
    }
    my ($a) = (areas($size))[0];
    my $cw = $th * 0.6;     # monospace advance per character
    my @rows;
    if ($p->{kind} eq 'text') {
        for my $e (sort { $a->{file} cmp $b->{file} || $a->{line} <=> $b->{line} } @{$p->{elements}}) {
            my $end = $e->{endline} // $e->{line};
            push @rows, ["// " . qn($e) . "  ($e->{file}:$e->{line})"];
            push @rows, [$SRC{$e->{file}}[$_ - 1] // ''] for $e->{line} .. $end;
            push @rows, [''];
        }
    } else {
        for my $e (sort { qn($a) cmp qn($b) } @{$p->{elements}}) {
            push @rows, [qn($e), $e->{kind} . ($e->{isdef} ? ' def' : ''), join(' ', map { "\@$_" } grep { $_ ne 'Drawing' } @{$e->{meta}}), $e->{doc} // '', "$e->{file}:$e->{line}"];
        }
    }
    my $per = int(($a->[3] - ($p->{kind} eq 'text' ? 4 : 10)) / $lh); $per = 1 if $per < 1;
    my @pages; push @pages, [splice @rows, 0, $per] while @rows;
    @pages = ([]) unless @pages;
    my @out;
    my $maxc = int($a->[2] / $cw);
    for my $i (0 .. $#pages) {
        my @b; my $y = $a->[1] + 4;
        if ($p->{kind} eq 'text') {
            for my $r (@{$pages[$i]}) { my $l = $r->[0]; $l =~ s/\t/    /g; $l = substr($l, 0, $maxc - 1) . "\x{2026}" if length $l > $maxc;
                push @b, sprintf(qq{<text x="%.2f" y="%.2f" font-family="DejaVu Sans Mono, Consolas, monospace" font-size="$th" fill="#000000" xml:space="preserve">%s</text>}, $a->[0], $y, esc($l)); $y += $lh }
        } else {
            my @w = (0.30, 0.10, 0.14, 0.31, 0.15); my @x = ($a->[0]); push @x, $x[-1] + $w[$_ - 1] * $a->[2] for 1 .. $#w;
            my @hd = ('Element', 'Kind', 'Metadata', 'Doc', 'Source');
            push @b, sprintf(qq{<rect x="%.2f" y="%.2f" width="%.2f" height="%.2f" fill="none" stroke="#000000" stroke-width="0.5"/>}, $a->[0], $y - 4, $a->[2], $lh * (@{$pages[$i]} + 1) + 1);
            push @b, sprintf(qq{<line x1="%.2f" y1="%.2f" x2="%.2f" y2="%.2f" stroke="#000000" stroke-width="0.5"/>}, $a->[0], $y + 1.5, $a->[0] + $a->[2], $y + 1.5);
            push @b, map { sprintf(qq{<text x="%.2f" y="%.2f" font-size="$th" font-weight="bold" fill="#000000">%s</text>}, $x[$_] + 1, $y, $hd[$_]) } 0 .. $#hd;
            $y += $lh;
            for my $r (@{$pages[$i]}) {
                for my $c (0 .. $#$r) { my $m = int($w[$c] * $a->[2] / ($th * 0.55)) - 1; my $s = $r->[$c]; $s = substr($s, 0, $m - 1) . "\x{2026}" if length $s > $m;
                    push @b, sprintf(qq{<text x="%.2f" y="%.2f" font-size="$th" fill="#000000">%s</text>}, $x[$c] + 1, $y, esc($s)) }
                push @b, sprintf(qq{<line x1="%.2f" y1="%.2f" x2="%.2f" y2="%.2f" stroke="#000000" stroke-width="0.18"/>}, $a->[0], $y + 1.5, $a->[0] + $a->[2], $y + 1.5);
                $y += $lh;
            }
            push @b, map { sprintf(qq{<line x1="%.2f" y1="%.2f" x2="%.2f" y2="%.2f" stroke="#000000" stroke-width="0.25"/>}, $x[$_], $a->[1], $x[$_], $y - $lh + 1.5) } 1 .. $#x;
        }
        push @out, { %$p, size => $size, body => join("\n", @b), scale => '-', cont => @pages > 1 ? ($i + 1) . ' of ' . scalar @pages : '' };
    }
    return @out;
}

# ------------------------------------------------------------------------------------------
# Sheet: ISO 5457 frame, centring marks, grid reference; ISO 7200 title block; markings
# ------------------------------------------------------------------------------------------
sub esc { my $s = shift // ''; $s =~ s/&/&amp;/g; $s =~ s/</&lt;/g; $s =~ s/>/&gt;/g; $s =~ s/"/&quot;/g; $s }
my $FONT = q{font-family="osifont, ISOCPEUR, 'DejaVu Sans', Arial, sans-serif"};
my $prov = $O{source} // '';
if ($prov eq '' && (-d '.git' || -f '.git')) { my $d = `git describe --always --dirty 2>/dev/null`; chomp $d; $prov = "git $d" if $d ne '' }
$prov ||= scalar(@files) . ' file(s)';
sub sheet_svg {
    my ($p, $no, $tot) = @_;
    my ($W, $H, $nx, $ny) = @{$SHEET{$p->{size}}};
    my $f = frame_of($p->{size});
    my @o;
    push @o, qq{<svg xmlns="http://www.w3.org/2000/svg" width="${W}mm" height="${H}mm" viewBox="0 0 $W $H" $FONT>},
      qq{<rect width="$W" height="$H" fill="#ffffff"/>},
      sprintf(qq{<rect x="%s" y="%s" width="%s" height="%s" fill="none" stroke="#000000" stroke-width="0.7"/>}, @$f{qw(x y w h)});
    # grid reference: numbers along top and bottom, letters (no I, O) down both sides
    my @L = grep { $_ ne 'I' && $_ ne 'O' } 'A' .. 'Z';
    my ($fx, $fy) = ($f->{w} / $nx, $f->{h} / $ny);
    for my $i (0 .. $nx) {
        my $x = $f->{x} + $i * $fx;
        push @o, sprintf(qq{<line x1="%.2f" y1="%.2f" x2="%.2f" y2="%.2f" stroke="#000000" stroke-width="0.35"/>}, $x, $f->{y} - 5, $x, $f->{y}),
                 sprintf(qq{<line x1="%.2f" y1="%.2f" x2="%.2f" y2="%.2f" stroke="#000000" stroke-width="0.35"/>}, $x, $f->{y} + $f->{h}, $x, $f->{y} + $f->{h} + 5) if $i > 0 && $i < $nx;
        next if $i == $nx;
        my $cx = $x + $fx / 2;
        push @o, sprintf(qq{<text x="%.2f" y="%.2f" font-size="3.5" text-anchor="middle">%d</text>}, $cx, $f->{y} - 1.3, $i + 1),
                 sprintf(qq{<text x="%.2f" y="%.2f" font-size="3.5" text-anchor="middle">%d</text>}, $cx, $f->{y} + $f->{h} + 4, $i + 1);
    }
    for my $j (0 .. $ny) {
        my $y = $f->{y} + $j * $fy;
        push @o, sprintf(qq{<line x1="%.2f" y1="%.2f" x2="%.2f" y2="%.2f" stroke="#000000" stroke-width="0.35"/>}, $f->{x} - 5, $y, $f->{x}, $y),
                 sprintf(qq{<line x1="%.2f" y1="%.2f" x2="%.2f" y2="%.2f" stroke="#000000" stroke-width="0.35"/>}, $f->{x} + $f->{w}, $y, $f->{x} + $f->{w} + 5, $y) if $j > 0 && $j < $ny;
        next if $j == $ny;
        my $cy = $y + $fy / 2 + 1.2;
        push @o, sprintf(qq{<text x="%.2f" y="%.2f" font-size="3.5" text-anchor="middle">%s</text>}, $f->{x} - 2.5, $cy, $L[$j]),
                 sprintf(qq{<text x="%.2f" y="%.2f" font-size="3.5" text-anchor="middle">%s</text>}, $f->{x} + $f->{w} + 2.5, $cy, $L[$j]);
    }
    # centring marks, from the sheet edge to 5 mm inside the frame
    my ($mx, $my) = ($f->{x} + $f->{w} / 2, $f->{y} + $f->{h} / 2);
    push @o, map { sprintf(qq{<line x1="%.2f" y1="%.2f" x2="%.2f" y2="%.2f" stroke="#000000" stroke-width="0.7"/>}, @$_) }
        [$mx, 0, $mx, $f->{y} + 5], [$mx, $H, $mx, $f->{y} + $f->{h} - 5], [0, $my, $f->{x} + 5, $my], [$W, $my, $f->{x} + $f->{w} - 5, $my];
    # security marking, top and bottom centre in the margin
    my $mw = length($p->{marking}) * 4 * 0.62 + 4;
    for my $yy ([0.3, 4.2], [$H - 4.7, $H - 0.8]) {     # in the outer 5 mm band, clear of the grid numbers
        push @o, sprintf(qq{<rect x="%.2f" y="%.2f" width="%.2f" height="4.4" fill="#ffffff"/>}, $mx - $mw / 2, $yy->[0], $mw),
                 sprintf(qq{<text x="%.2f" y="%.2f" font-size="4" font-weight="bold" text-anchor="middle">%s</text>}, $mx, $yy->[1], esc($p->{marking}));
    }
    # the drawing
    push @o, $p->{body};
    # title block (ISO 7200 fields), bottom right, 180 x 45 mm
    my ($tx, $ty) = ($f->{x} + $f->{w} - $TBW, $f->{y} + $f->{h} - $TBH);
    push @o, sprintf(qq{<rect x="%.2f" y="%.2f" width="$TBW" height="$TBH" fill="#ffffff" stroke="#000000" stroke-width="0.7"/>}, $tx, $ty);
    my @F = (   # [x, y, w, h, label, value, value size]
        [0, 0, 90, 9, 'Security class', $p->{marking}, 3.5], [90, 0, 45, 9, 'Scale', $p->{scale}, 2.5], [135, 0, 45, 9, 'Source', $prov, 2.5],
        [0, 9, 60, 9, 'Legal owner', $p->{owner}, 3.5], [60, 9, 60, 9, 'Document type', $p->{doctype}, 3.5], [120, 9, 60, 9, 'Document status', $p->{status}, 3.5],
        [0, 18, 60, 9, 'Technical reference', $p->{ref}, 2.5], [60, 18, 120, 18, 'Title', $p->{title}, 5, $p->{sub} . ($p->{cont} ? " ($p->{cont})" : '')],
        [0, 27, 60, 9, 'Created by', $p->{creator}, 3.5],
        [0, 36, 60, 9, 'Approved by', $p->{approver}, 3.5], [60, 36, 55, 9, 'Identification number', $p->{number}, 3.5],
        [115, 36, 12, 9, 'Rev.', $p->{rev}, 3.5], [127, 36, 27, 9, 'Date of issue', $DATE, 3.5], [154, 36, 10, 9, 'Lang.', 'en', 3.5],
        [164, 36, 16, 9, 'Sheet', "$no/$tot", 3.5]);
    for my $c (@F) {
        my ($x, $y, $w, $h, $lab, $val, $vs, $sub) = @$c;
        my ($X, $Y) = ($tx + $x, $ty + $y);
        push @o, sprintf(qq{<rect x="%.2f" y="%.2f" width="%.2f" height="%.2f" fill="none" stroke="#000000" stroke-width="0.35"/>}, $X, $Y, $w, $h),
                 sprintf(qq{<text x="%.2f" y="%.2f" font-size="1.8">%s</text>}, $X + 1, $Y + 2.4, esc($lab));
        my $v = $val // '';
        if ($lab eq 'Title') { my $fit = ($w - 3) / ((length($v) || 1) * 0.62); $vs = $fit < 3.5 ? 3.5 : $fit < $vs ? $fit : $vs; $vs = sprintf '%.2f', $vs }
        my $maxc = int(($w - 2) / ($vs * ($lab eq 'Title' ? 0.62 : 0.55)));
        $v = substr($v, 0, $maxc - 1) . "\x{2026}" if length $v > $maxc;
        push @o, sprintf(qq{<text x="%.2f" y="%.2f" font-size="$vs"%s>%s</text>}, $X + 1.5, $Y + ($sub ? 9 : $h - 2), $lab eq 'Title' ? ' font-weight="bold"' : '', esc($v));
        if ($sub) { my $m = int(($w - 2) / (2.5 * 0.55)); my $s2 = length $sub > $m ? substr($sub, 0, $m - 1) . "\x{2026}" : $sub;
            push @o, sprintf(qq{<text x="%.2f" y="%.2f" font-size="2.5">%s</text>}, $X + 1.5, $Y + 15, esc($s2)) }
    }
    push @o, sprintf(qq{<rect x="%.2f" y="%.2f" width="$TBW" height="$TBH" fill="none" stroke="#000000" stroke-width="0.7"/>}, $tx, $ty), '</svg>';
    return join "\n", @o;
}

make_path($O{o});
my $tot = @OUT;
my (@html, %sizes);
for my $i (0 .. $#OUT) {
    my $p = $OUT[$i];
    my $svg = sheet_svg($p, $i + 1, $tot);
    (my $fn = $p->{number} . ($p->{cont} ? '-' . ($p->{cont} =~ /^(\d+)/)[0] : '')) =~ s/[^\w.-]+/_/g;
    open my $h, '>:encoding(UTF-8)', "$O{o}/$fn.svg" or die "$O{o}/$fn.svg: $!";
    print $h qq{<?xml version="1.0" encoding="UTF-8"?>\n<!-- generated by sysml-plates.pl -->\n$svg\n};
    close $h;
    $sizes{$p->{size}} = 1;
    push @html, qq{<div class="sheet $p->{size}">$svg</div>};
    printf "%-14s %-3s %3d/%-3d %-24s %s -> %s\n", $p->{number}, $p->{size}, $i + 1, $tot, $p->{kind}, ($p->{view} ? qn($p->{view}) : 'auto'), "$O{o}/$fn.svg";
}
open my $h, '>:encoding(UTF-8)', "$O{o}/plates.html" or die "$O{o}/plates.html: $!";
print $h "<!DOCTYPE html>\n<html><head><meta charset=\"utf-8\"><title>Plates</title><style>\n",
    "body { margin: 0; background: #888; } .sheet { margin: 12px auto; width: max-content; background: #fff; }\n",
    (map { my ($w, $hh) = @{$SHEET{$_}}; "\@page $_ { size: ${w}mm ${hh}mm; margin: 0 } .sheet.$_ { page: $_ }\n" } sort keys %sizes),
    "\@media print { body { background: #fff } .sheet { margin: 0; break-after: page } }\n</style></head><body>\n",
    join("\n", @html), "\n</body></html>\n";
close $h;
printf "plates: %d view(s), %d plate(s) on %d sheet(s), %d warning(s) -> %s/plates.html\n", scalar @views, scalar @PLATES, $tot, $NWARN, $O{o};
exit($NWARN ? 1 : 0);
