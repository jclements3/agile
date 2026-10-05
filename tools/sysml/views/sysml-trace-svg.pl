#!/usr/bin/perl
# sysml-trace-svg.pl : draw the requirement trace of a SysML v2 model as one SVG.
# Core Perl 5 only. Three columns: satisfying features | requirement tree | verification cases.
#
#   perl sysml-trace-svg.pl [-o trace.svg] [--title T] [--gaps] [--match REGEX]
#                           [--compare OLD]... [--changed] DIR|FILE...
#
#   --gaps         show only leaf requirements with a gap (and the groups above them)
#   --match REGEX  show only requirements whose id or name matches (and the groups above them)
#   --compare OLD  diff against an older version (a directory or files; repeatable): added,
#                  changed and removed requirements, boxes and links are colored, coverage
#                  changes are counted, and one line per change is printed (GNU format)
#   --changed      with --compare, show only what changed (and the groups above it)
#   --package P    show only requirements in package P or packages nested in it (repeatable)
#   --mono         status badges as shapes (filled, crossed, half) instead of colors, for print
#
# Rules match sysml-trace.pl: a leaf is satisfied (verified) if it or a requirement group
# above it is the target of a satisfy (verify). IDs starting N- are needs: drawn, not judged.
# Requirements are matched across versions by ID, or by package and path when they have none.
use strict; use warnings;
use File::Find; use Getopt::Long;
binmode STDOUT, ":encoding(UTF-8)"; binmode STDERR, ":encoding(UTF-8)";

my %O = (o => 'trace.svg');
GetOptions(\%O, 'o=s', 'title=s', 'gaps', 'match=s', 'compare=s@', 'changed', 'label=s@', 'package=s@', 'mono') && @ARGV
    or do { print STDERR "usage: perl sysml-trace-svg.pl [-o trace.svg] [--title T] [--gaps] [--match REGEX] [--compare OLD]... [--changed] DIR|FILE...\n"; exit 2 };
if ($O{changed} && !$O{compare}) { print STDERR "sysml-trace-svg: --changed needs --compare\n"; exit 2 }

my $NAME = qr/(?:[A-Za-z_]\w*|'(?:[^'\\]|\\.)*')/;
my $REF  = qr/$NAME(?:\s*(?:::|\.)\s*$NAME)*/;
my $nwarn = 0;

# --label DIR=TEXT shows files under DIR as TEXT... in messages (sysml-diff.pl uses it for git revisions)
my @LABEL = map { [split /=/, $_, 2] } @{$O{label} // []};
sub shown { my $f = shift; for my $l (@LABEL) { return $l->[1] . substr($f, length($l->[0]) + 1) if index($f, "$l->[0]/") == 0 } $f }
sub collect {
    my @f;
    for my $a (@_) {
        if (-d $a) { find(sub { push @f, $File::Find::name if /\.sysml$/ }, $a) }
        elsif (-f $a) { push @f, $a }
        else { print STDERR "sysml-trace-svg: $a: no such file or directory\n"; exit 2 }
    }
    return sort @f;
}
sub unq { my $n = shift; return $n unless $n =~ /^'(.*)'$/s; (my $u = $1) =~ s/\\(.)/$1/g; $u }
sub segs { my $r = shift; my @s; push @s, unq($1) while $r =~ /\G\s*($NAME)\s*(?:::|\.)?/g; @s }

# ------------------------------------------------------------------------------------------
# Analyze one version: requirements, satisfy and verify links, coverage.
# ------------------------------------------------------------------------------------------
sub analyze {
    my ($quiet, @files) = @_;
    my (@req, @sat, @ver, %usage);
    for my $real (@files) {
        open my $h, '<:encoding(UTF-8)', $real or die "$real: $!";
        local $/; my $t = <$h>;
        my $f = shown($real);
        my (@stack, $pending);
        my $line = 1;
        my $pkgpath = sub { map { $_->{name} } grep { $_->{kind} eq 'package' } @stack };
        my $reqpath = sub { map { $_->{name} } grep { $_->{kind} eq 'req' } @stack };
        while ($t =~ m{\G(?:
                (\n)
              | //[^\n]*
              | doc\s*(?:<'[^']*'>\s*)?/\*(.*?)\*/
              | (/\*.*?\*/)
              | "(?:[^"\\]|\\.)*"
              | (\{) | (\}) | (;)
              | (?:library\s+|standard\s+library\s+)?package\s+($NAME)
              | requirement\s+def\b
              | requirement\s+(?:<'((?:[^'\\]|\\.)*)'>\s*)?($NAME)
              | verification\s+def\s+($NAME)
              | satisfy\s+(?:requirement\s+)?($REF)\s+by\s+($REF)
              | verify\s+(?:requirement\s+)?($REF)
              | part\s+($NAME)\s*(?::|typed\s+by)\s*($REF)
              | \w+
              | .
            )}gsx) {
            my $here = $line;
            if    (defined $1) { $line++ }
            elsif (defined $2) {
                my $doc = $2; $line += ($doc =~ tr/\n//);
                my $top = $stack[-1];
                if ($top && $top->{kind} eq 'req' && !defined $top->{rec}{doc}) {
                    $doc =~ s/^\s*\*\s?//mg; $doc =~ s/\s+/ /g; $doc =~ s/^ | $//g;
                    $top->{rec}{doc} = $doc;
                }
            }
            elsif (defined $3) { $line += ($3 =~ tr/\n//) }
            elsif (defined $4) { push @stack, $pending // { kind => 'other' }; $pending = undef }
            elsif (defined $5) { pop @stack; $pending = undef }
            elsif (defined $6) { $pending = undef }
            elsif (defined $7) { $pending = { kind => 'package', name => unq($7) } }
            elsif (defined $9) {
                my $r = { id => defined $8 ? $8 : '', name => unq($9), file => $f, line => $here,
                          pkg => [$pkgpath->()], path => [$reqpath->(), unq($9)], kids => [] };
                my ($parent) = grep { $_->{kind} eq 'req' } reverse @stack;
                $r->{up} = $parent->{rec} if $parent;
                push @{$parent->{rec}{kids}}, $r if $parent;
                push @req, $r;
                $pending = { kind => 'req', name => $r->{name}, rec => $r };
            }
            elsif (defined $10) { $pending = { kind => 'vdef', name => unq($10), pkg => [$pkgpath->()] } }
            elsif (defined $11) { push @sat, { ref => $11, by => $12, file => $f, line => $here, pkg => [$pkgpath->()] } }
            elsif (defined $13) {
                my ($v) = grep { $_->{kind} eq 'vdef' } reverse @stack;
                push @ver, { ref => $13, vdef => $v ? $v->{name} : '(anonymous)', file => $f, line => $here,
                             pkg => $v ? $v->{pkg} : [$pkgpath->()] };
            }
            elsif (defined $14) {
                $usage{join('::', $pkgpath->()) . "\0" . unq($14)} = $15
                    if @stack && $stack[-1]{kind} eq 'package';
            }
        }
    }
    my %seen;
    for my $r (@req) {          # identity across versions
        my $k = $r->{id} ne '' ? "id:$r->{id}" : 'path:' . join('::', @{$r->{pkg}}) . '::' . join('.', @{$r->{path}});
        $k .= '#' . $seen{$k} if $seen{$k}++;
        $r->{key} = $k;
        $r->{show} = $r->{id} ne '' ? $r->{id} : join('.', @{$r->{path}});
    }
    my $resolve = sub {
        my ($x, $kind) = @_;
        my @s = segs($x->{ref});
        my @hit = grep { my @full = (@{$_->{pkg}}, @{$_->{path}});
                         @full >= @s && join("\0", @full[$#full - $#s .. $#full]) eq join("\0", @s) } @req;
        if (@hit > 1) {
            my $p = join '::', @{$x->{pkg}};
            my @near = grep { join('::', @{$_->{pkg}}) eq $p } @hit;
            @hit = @near if @near;
        }
        unless (@hit) { warn "$x->{file}:$x->{line}: warning: $kind target '$x->{ref}' not found\n" unless $quiet; $nwarn++ unless $quiet; return }
        if (@hit > 1) { warn "$x->{file}:$x->{line}: warning: $kind target '$x->{ref}' is ambiguous; using the first\n" unless $quiet; $nwarn++ unless $quiet }
        return $hit[0];
    };
    my (%box, @edge);           # box key "S|pkg|label" / "V|pkg|label"
    for my $s (@sat) {
        my $r = $resolve->($s, 'satisfy') or next;
        my @b = segs($s->{by});
        my $type = $usage{join('::', @{$s->{pkg}}) . "\0" . $b[0]};
        my $label = join('.', @b) . (defined $type && @b == 1 ? " : $type" : '');
        my $key = 'S|' . join('::', @{$s->{pkg}}) . '|' . join('.', @b);
        $box{$key} //= { key => $key, side => 'S', label => $label, pkg => join('::', @{$s->{pkg}}), file => $s->{file}, line => $s->{line} };
        $r->{sat_direct} = 1;
        push @edge, [$key, $r];
    }
    for my $v (@ver) {
        my $r = $resolve->($v, 'verify') or next;
        my $key = 'V|' . join('::', @{$v->{pkg}}) . '|' . $v->{vdef};
        $box{$key} //= { key => $key, side => 'V', label => $v->{vdef}, pkg => join('::', @{$v->{pkg}}), file => $v->{file}, line => $v->{line} };
        $r->{ver_direct} = 1;
        push @edge, [$key, $r];
    }
    for my $r (@req) {
        my ($s, $v) = (0, 0);
        for (my $o = $r; $o; $o = $o->{up}) { $s ||= $o->{sat_direct}; $v ||= $o->{ver_direct} }
        $r->{leaf} = !@{$r->{kids}};
        $r->{need} = $r->{id} =~ /^N-/;
        @$r{qw(sat ver)} = ($s, $v);
        $r->{gap} = $r->{leaf} && !$r->{need} && (!$s || !$v) ? 1 : 0;
        $r->{links} = {};
    }
    for my $e (@edge) { $e->[1]{links}{$e->[0]} = 1 }
    return { req => \@req, box => \%box, edge => [map { [$_->[0], $_->[1]{key}, $_->[1]] } @edge], nfiles => scalar @files };
}

my $new = analyze(0, collect(@ARGV));
my $old = $O{compare} ? analyze(1, collect(@{$O{compare}})) : undef;

# ------------------------------------------------------------------------------------------
# Merge versions into one list of entries: { r, st => same|added|changed|removed, why => [...] }
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
            push @out, [$n, 'same'];
        } else { push @out, [$n, 'added'] }
    }
    while ($p < @$old) { my $o = $old->[$p++]; push @out, [$o, 'removed'] unless $nk{$o->{key}} }
    return @out;
}
sub lbl { my $k = shift; (split /\|/, $k, 3)[2] }

my (@E, %E, @changes, $newgaps, $closed);
($newgaps, $closed) = (0, 0);
my %oldreq = $old ? map { $_->{key} => $_ } @{$old->{req}} : ();
for my $m ($old ? merge_seq($new->{req}, $old->{req}) : map { [$_, 'same'] } @{$new->{req}}) {
    my ($r, $st) = @$m;
    my $e = { r => $r, st => $st, why => [], key => $r->{key} };
    if ($old && $st eq 'same') {
        my $o = $oldreq{$r->{key}};
        $e->{old} = $o;
        push @{$e->{why}}, "renamed from $o->{name}" if $o->{name} ne $r->{name};
        push @{$e->{why}}, 'text changed' if ($o->{doc} // '') ne ($r->{doc} // '');
        push @{$e->{why}}, 'moved from ' . ($o->{up} ? $o->{up}{show} : 'top level')
            if ($o->{up} ? $o->{up}{key} : '') ne ($r->{up} ? $r->{up}{key} : '')
            || join('::', @{$o->{pkg}}) ne join('::', @{$r->{pkg}});
        for my $side (['S', 'satisfied by'], ['V', 'verified by']) {
            my @add = sort map { lbl($_) } grep { /^$side->[0]\|/ && !$o->{links}{$_} } keys %{$r->{links}};
            my @del = sort map { lbl($_) } grep { /^$side->[0]\|/ && !$r->{links}{$_} } keys %{$o->{links}};
            push @{$e->{why}}, "$side->[1] " . join(' ', (map { "+$_" } @add), map { "-$_" } @del) if @add || @del;
        }
        if ($o->{gap} != $r->{gap}) {
            push @{$e->{why}}, $r->{gap} ? 'now a gap' : 'gap closed';
            $r->{gap} ? $newgaps++ : $closed++;
            $e->{gapnew} = $r->{gap};
        }
        $e->{st} = 'changed' if @{$e->{why}};
    }
    if ($old && $st eq 'added' && $r->{gap}) { $newgaps++; $e->{gapnew} = 1; push @{$e->{why}}, 'added as a gap' }
    push @E, $e; $E{$e->{key}} = $e;
    next unless $old && $e->{st} ne 'same';
    my $where = "$r->{file}:$r->{line}";
    my $sev = $e->{gapnew} ? 'warning' : 'note';
    push @changes, "$where: $sev: requirement $r->{show} $e->{st}" . (@{$e->{why}} ? ': ' . join('; ', @{$e->{why}}) : '');
}
my %parent = map { $_->{key} => ($_->{r}{up} ? $_->{r}{up}{key} : undef) } @E;

# Boxes: new ones, plus old-only ghosts. Edges: new (same/added) plus removed.
my (%B, @EDGES);
for my $b (values %{$new->{box}}) { $B{$b->{key}} = { %$b, st => $old && !$old->{box}{$b->{key}} ? 'added' : 'same' } }
if ($old) { for my $b (values %{$old->{box}}) { $B{$b->{key}} //= { %$b, st => 'removed' } } }
my %oldedge = $old ? map { ("$_->[0]\0$_->[1]" => 1) } @{$old->{edge}} : ();
my %newedge = map { ("$_->[0]\0$_->[1]" => 1) } @{$new->{edge}};
for my $x (@{$new->{edge}}) { push @EDGES, { b => $x->[0], r => $x->[1], st => $old && !$oldedge{"$x->[0]\0$x->[1]"} ? 'added' : 'same', leaf => $x->[2]{leaf} } }
if ($old) { for my $x (@{$old->{edge}}) { push @EDGES, { b => $x->[0], r => $x->[1], st => 'removed', leaf => $x->[2]{leaf} } unless $newedge{"$x->[0]\0$x->[1]"} } }
for my $b (sort { $a->{key} cmp $b->{key} } grep { $_->{st} ne 'same' } values %B) {
    push @changes, "$b->{file}:$b->{line}: note: " . ($b->{side} eq 'S' ? 'satisfier' : 'verification case') . " $b->{label} $b->{st}";
}
my @lines = sort { my @a = $a =~ /^(.*?):(\d+):/; my @b = $b =~ /^(.*?):(\d+):/; $a[0] cmp $b[0] || $a[1] <=> $b[1] } @changes;

# ------------------------------------------------------------------------------------------
# Filter: keep wanted entries and every group above them.
# ------------------------------------------------------------------------------------------
my %keep;
for my $e (@E) {
    my $r = $e->{r};
    my $want = 1;
    $want &&= $r->{gap} && $e->{st} ne 'removed' if $O{gaps};
    $want &&= "$r->{id} $r->{name}" =~ /$O{match}/ if defined $O{match};
    if ($O{package}) { my $p = join '::', @{$r->{pkg}}; $want &&= grep { $p eq $_ || index($p, "$_\::") == 0 } @{$O{package}} }
    $want &&= $e->{st} ne 'same' || grep { $B{$_->{b}} && $_->{st} ne 'same' && $_->{r} eq $e->{key} } @EDGES if $O{changed};
    next unless $want;
    for (my $k = $e->{key}; defined $k && $E{$k}; $k = $parent{$k}) { last if $keep{$k}++ }
}
my @shown = grep { $keep{$_->{key}} } @E;

my @leaf = grep { $_->{leaf} } @{$new->{req}};
my $ngap = grep { $_->{gap} } @{$new->{req}};

# ------------------------------------------------------------------------------------------
# Layout
# ------------------------------------------------------------------------------------------
my ($CW, $FS, $ROW, $BOXH, $GAP, $COLGAP, $TOP, $PAD) = (7.2, 12, 22, 20, 6, 150, 92, 16);
my $DOCMAX = 70;
sub tw { length($_[0]) * $CW }
sub short { my $d = shift; return '' if $d eq ''; length $d > $DOCMAX ? substr($d, 0, $DOCMAX - 1) . "\x{2026}" : $d }

my (@rows, %rowy);
my $y = $TOP; my $lastpkg = '';
for my $e (@shown) {
    my $r = $e->{r};
    my $pkg = join '::', @{$r->{pkg}};
    if ($pkg ne $lastpkg) { push @rows, { band => $pkg, y => $y }; $y += $ROW + 4; $lastpkg = $pkg }
    push @rows, { e => $e, y => $y, depth => @{$r->{path}} - 1 };
    $rowy{$e->{key}} = $y + $ROW / 2;
    $y += $ROW;
}
my $midh = $y;
my $midw = 360;
for my $row (@rows) {
    my $w;
    if ($row->{band}) { $w = tw($row->{band}) + 24 }
    else { my $r = $row->{e}{r}; $w = 56 + $row->{depth} * 16 + tw($r->{id}) + ($r->{id} ne '' ? 12 : 0) + tw($r->{name}) + 12 + tw(short($r->{doc} // '')) }
    $midw = $w if $w > $midw;
}

sub place {
    my @b = @_;
    for my $b (@b) {
        my @ys = map { $rowy{$_->{r}} } grep { $_->{b} eq $b->{key} && defined $rowy{$_->{r}} } @EDGES;
        my $sum = 0; $sum += $_ for @ys;
        $b->{want} = @ys ? $sum / @ys : undef;
    }
    @b = sort { $a->{want} <=> $b->{want} || $a->{label} cmp $b->{label} } grep { defined $_->{want} } @b;
    my $next = $TOP;
    for my $b (@b) {
        my $top = $b->{want} - $BOXH / 2;
        $top = $next if $top < $next;
        $b->{y} = $top; $next = $top + $BOXH + $GAP;
    }
    return @b;
}
my @S = place(sort { $a->{label} cmp $b->{label} } grep { $_->{side} eq 'S' } values %B);
my @V = place(sort { $a->{label} cmp $b->{label} } grep { $_->{side} eq 'V' } values %B);
my $bn = 0; $_->{n} = ++$bn for @S, @V;
my $en = 0; $_->{n} = ++$en for @E;
my ($sw) = sort { $b <=> $a } 180, map { tw($_->{label}) + 20 } @S;
my ($vw) = sort { $b <=> $a } 180, map { tw($_->{label}) + 20 } @V;
my ($xs, $xm) = ($PAD, $PAD + $sw + $COLGAP);
my $xv = $xm + $midw + $COLGAP;
my $W = $xv + $vw + $PAD;
my ($H) = sort { $b <=> $a } $midh, map({ $_->{y} + $BOXH } @S, @V);
$H += 40;

# ------------------------------------------------------------------------------------------
# Draw
# ------------------------------------------------------------------------------------------
sub esc { my $s = shift // ''; $s =~ s/&/&amp;/g; $s =~ s/</&lt;/g; $s =~ s/>/&gt;/g; $s =~ s/"/&quot;/g; $s }
my %C = (ok => '#2e7d32', bad => '#c62828', na => '#d6d6d6', grp => '#78909c', edge => '#90a4ae',
         band => '#eceff1', gapbg => '#ffebee', ink => '#212121', dim => '#616161',
         sbox => '#e3f2fd', sline => '#1565c0', vbox => '#f3e5f5', vline => '#6a1b9a',
         added => '#2e7d32', changed => '#ef6c00', removed => '#c62828',
         addedbg => '#e8f5e9', changedbg => '#fff3e0', removedbg => '#f5f5f5');
my @o;
push @o, qq{<?xml version="1.0" encoding="UTF-8"?>},
  qq{<svg xmlns="http://www.w3.org/2000/svg" width="$W" height="$H" viewBox="0 0 $W $H" font-family="DejaVu Sans Mono, Consolas, Menlo, monospace" font-size="$FS">},
  qq{<!-- generated by sysml-trace-svg.pl from } . (esc(join(' ', @ARGV) . ($O{compare} ? ', compared with ' . join(' ', @{$O{compare}}) : '')) =~ s/-(?=-)/- /gr) . qq{ -->},
  qq{<style>.e{transition:stroke .1s} .hl{stroke:#e65100 !important;stroke-width:2.6px !important} .dim{opacity:.15} [data-k]{cursor:pointer} .gone{opacity:.6} .gone text{text-decoration:line-through}</style>},
  qq{<script><![CDATA[
window.addEventListener('load', function () {
  var edges = document.querySelectorAll('.e');
  function on(k, yes) {
    edges.forEach(function (e) {
      var hit = (' ' + e.getAttribute('data-ends') + ' ').indexOf(' ' + k + ' ') >= 0;
      e.classList.toggle('hl', yes && hit); e.classList.toggle('dim', yes && !hit);
    });
  }
  document.querySelectorAll('[data-k]').forEach(function (g) {
    g.addEventListener('mouseenter', function () { on(g.getAttribute('data-k'), true) });
    g.addEventListener('mouseleave', function () { on(g.getAttribute('data-k'), false) });
  });
});
]]></script>},
  qq{<rect width="100%" height="100%" fill="#ffffff"/>};
my $title = $O{title} // ($old ? 'Requirement trace changes' : 'Requirement trace');
my $sum = sprintf '%d leaf requirement(s), %d with gaps; %d satisfy, %d verify', scalar @leaf, $ngap,
    scalar(grep { $_->{b} =~ /^S/ && $_->{st} ne 'removed' } @EDGES), scalar(grep { $_->{b} =~ /^V/ && $_->{st} ne 'removed' } @EDGES);
my $dsum = '';
if ($old) {
    my %n; $n{$_->{st}}++ for @E;
    my %l; $l{$_->{st}}++ for @EDGES;
    $dsum = sprintf 'requirements +%d -%d ~%d; links +%d -%d; %d new gap(s), %d closed',
        $n{added} // 0, $n{removed} // 0, $n{changed} // 0, $l{added} // 0, $l{removed} // 0, $newgaps, $closed;
}
my $filt = join '', ($O{gaps} ? '; gaps only' : ''), (defined $O{match} ? "; filter /$O{match}/" : ''), ($O{changed} ? '; changes only' : '');
push @o, qq{<text x="$PAD" y="26" font-size="16" font-weight="bold" fill="$C{ink}">} . esc($title) . '</text>',
  qq{<text x="$PAD" y="46" fill="$C{dim}">} . esc($sum . $filt) . '</text>';
push @o, qq{<text x="$PAD" y="64" fill="$C{ink}">} . esc($dsum) . '</text>' if $old;
push @o, map { qq{<text x="$_->[0]" y="84" font-weight="bold" fill="$C{dim}">$_->[1]</text>} }
    [$xs, 'satisfied by'], [$xm + 9, 'S'], [$xm + 25, 'V'], [$xm + 48, 'requirements'], [$xv, 'verified by'];
my $lx = $xm + 48;
for my $s ($sum . $filt, $dsum) { $lx = $PAD + tw($s) + 64 if $lx < $PAD + tw($s) + 64 }
push @o, qq{<g transform="translate($lx,16)" font-size="11" fill="$C{dim}">},
  badge(0, 0, 'ok') . qq{<text x="16" y="10">covered</text>},
  badge(84, 0, 'bad') . qq{<text x="100" y="10">gap</text>},
  badge(140, 0, 'grp') . qq{<text x="156" y="10">via a group</text>},
  badge(252, 0, 'na') . qq{<text x="268" y="10">not judged (group, need)</text>},
  qq{<line x1="0" y1="27" x2="24" y2="27" stroke="$C{edge}" stroke-width="1.5"/><text x="30" y="31">to a leaf</text>},
  qq{<line x1="110" y1="27" x2="134" y2="27" stroke="$C{edge}" stroke-width="1.5" stroke-dasharray="4 3"/><text x="140" y="31">to a group</text>},
  ($old ? (qq{<rect x="252" y="21" width="5" height="12" fill="$C{added}"/><text x="262" y="31">added</text>},
           qq{<rect x="314" y="21" width="5" height="12" fill="$C{changed}"/><text x="324" y="31">changed</text>},
           qq{<rect x="390" y="21" width="5" height="12" fill="$C{removed}"/><text x="400" y="31" text-decoration="line-through">removed</text>}) : ()),
  '</g>';

sub badge {
    my ($x, $y, $k) = @_;
    return qq{<rect x="$x" y="$y" width="12" height="12" rx="2" fill="$C{$k}"/>} unless $O{mono};
    # black on white: covered = filled, gap = open with a cross, via a group = half filled, not judged = open
    my $r = qq{<rect x="$x" y="$y" width="12" height="12" rx="2" fill="} . ($k eq 'ok' ? '#000000' : '#ffffff') . qq{" stroke="#000000" stroke-width="1"/>};
    $r .= sprintf(qq{<path d="M%d %d l12 12 M%d %d l-12 12" stroke="#000000" stroke-width="1.6"/>}, $x, $y, $x + 12, $y) if $k eq 'bad';
    $r .= sprintf(qq{<path d="M%d %d l12 -12 v12 z" fill="#000000"/>}, $x, $y + 12) if $k eq 'grp';
    return $r;
}
sub curve {
    my ($x1, $y1, $x2, $y2, $dash, $ends, $col, $w) = @_;
    my $mx = ($x1 + $x2) / 2;
    my $d = $dash ? qq{ stroke-dasharray="$dash"} : '';
    return sprintf qq{<path class="e" data-ends="$ends" d="M%.1f %.1f C%.1f %.1f %.1f %.1f %.1f %.1f" fill="none" stroke="$col" stroke-width="$w"$d/>},
        $x1, $y1, $mx, $y1, $mx, $y2, $x2, $y2;
}

# edges first, under everything
for my $x (sort { ($a->{st} ne 'same') <=> ($b->{st} ne 'same') } @EDGES) {
    my $b = $B{$x->{b}}; my $e = $E{$x->{r}};
    next unless $b && defined $b->{y} && $e && defined $rowy{$x->{r}};
    my ($col, $w, $dash) = ($C{edge}, 1.3, $x->{leaf} ? '' : '4 3');
    ($col, $w) = ($C{added}, 2) if $x->{st} eq 'added';
    ($col, $w, $dash) = ($C{removed}, 1.6, '3 3') if $x->{st} eq 'removed';
    my $ends = "r$e->{n} b$b->{n}";
    push @o, $b->{side} eq 'S'
        ? curve($xs + $sw, $b->{y} + $BOXH / 2, $xm - 4, $rowy{$x->{r}}, $dash, $ends, $col, $w)
        : curve($xm + $midw + 4, $rowy{$x->{r}}, $xv, $b->{y} + $BOXH / 2, $dash, $ends, $col, $w);
}

for my $row (@rows) {
    if (defined $row->{band}) {
        push @o, qq{<rect x="$xm" y="$row->{y}" width="$midw" height="$ROW" fill="$C{band}"/>},
          qq{<text x="} . ($xm + 8) . qq{" y="} . ($row->{y} + 15) . qq{" font-weight="bold" fill="$C{ink}">} . esc($row->{band}) . '</text>';
        next;
    }
    my $e = $row->{e}; my $r = $e->{r}; my $ry = $row->{y};
    my $gone = $e->{st} eq 'removed';
    my @tip = ("$r->{id} $r->{name}", $r->{doc} // '',
        ($r->{need} ? 'need: traced by derivation, not judged' : $r->{leaf} ? ('satisfied: ' . ($r->{sat} ? 'yes' : 'NO'), 'verified: ' . ($r->{ver} ? 'yes' : 'NO')) : 'group: judged by its leaves'));
    push @tip, uc($e->{st}) . (@{$e->{why}} ? ': ' . join('; ', @{$e->{why}}) : '') if $e->{st} ne 'same';
    push @tip, ($gone ? 'was at ' : '') . "$r->{file}:$r->{line}";
    push @o, qq{<g data-k="r$e->{n}"} . ($gone ? ' class="gone"' : '') . '><title>' . esc(join "\n", grep { $_ ne '' } @tip) . '</title>';
    push @o, qq{<rect x="$xm" y="$ry" width="$midw" height="$ROW" fill="$C{gapbg}"/>} if $r->{gap} && !$gone;
    push @o, qq{<rect x="$xm" y="$ry" width="$midw" height="$ROW" fill="$C{"$e->{st}bg"}"/>} if $e->{st} ne 'same' && (!$r->{gap} || $gone);
    push @o, qq{<rect x="$xm" y="$ry" width="4" height="$ROW" fill="$C{$e->{st}}"/>} if $e->{st} ne 'same';
    my $bx = $xm + 8;
    for my $k (qw(sat ver)) {
        my $state = $r->{need} || !$r->{leaf} ? ($r->{"${k}_direct"} ? 'ok' : 'na')
                  : !$r->{$k} ? 'bad' : $r->{"${k}_direct"} ? 'ok' : 'grp';
        $state = 'na' if $r->{need};
        push @o, badge($bx, $ry + 5, $state);
        $bx += 16;
    }
    my $tx = $xm + 48 + $row->{depth} * 16;
    my $ty = $ry + 15;
    if ($r->{id} ne '') { push @o, qq{<text x="$tx" y="$ty" fill="$C{dim}">} . esc($r->{id}) . '</text>'; $tx += tw($r->{id}) + 12 }
    my $col = $gone ? $C{dim} : $r->{gap} ? $C{bad} : $C{ink};
    push @o, qq{<text x="$tx" y="$ty" font-weight="} . ($r->{leaf} ? 'normal' : 'bold') . qq{" fill="$col">} . esc($r->{name}) . '</text>';
    $tx += tw($r->{name}) + 12;
    push @o, qq{<text x="$tx" y="$ty" fill="$C{dim}" font-style="italic">} . esc(short($r->{doc} // '')) . '</text>' if defined $r->{doc};
    push @o, '</g>';
}

for my $col ([\@S, $xs, $sw, 'sbox', 'sline'], [\@V, $xv, $vw, 'vbox', 'vline']) {
    my ($boxes, $x, $w, $fill, $line) = @$col;
    for my $b (@$boxes) {
        my @links = map { my $r = $E{$_->{r}} && $E{$_->{r}}{r};
                          $r ? ($r->{id} ne '' ? "$r->{id} " : '') . join('.', @{$r->{path}}) . ($_->{st} ne 'same' ? " ($_->{st})" : '') : () }
                    grep { $_->{b} eq $b->{key} } @EDGES;
        my @tip = ($b->{label}, "package $b->{pkg}", @links);
        push @tip, uc $b->{st} if $b->{st} ne 'same';
        push @tip, ($b->{st} eq 'removed' ? 'was at ' : '') . "$b->{file}:$b->{line}";
        my ($f, $s, $sw2, $dash) = ($C{$fill}, $C{$line}, 1, '');
        ($s, $sw2) = ($C{added}, 2.2) if $b->{st} eq 'added';
        ($f, $s, $dash) = ($C{removedbg}, $C{removed}, ' stroke-dasharray="4 3"') if $b->{st} eq 'removed';
        push @o, qq{<g data-k="b$b->{n}"} . ($b->{st} eq 'removed' ? ' class="gone"' : '') . '><title>' . esc(join "\n", @tip) . '</title>',
          qq{<rect x="$x" y="$b->{y}" width="$w" height="$BOXH" rx="4" fill="$f" stroke="$s" stroke-width="$sw2"$dash/>},
          qq{<text x="} . ($x + 10) . qq{" y="} . ($b->{y} + 14) . qq{" fill="$C{ink}">} . esc($b->{label}) . '</text></g>';
    }
}
push @o, '</svg>';

open my $out, '>:encoding(UTF-8)', $O{o} or die "$O{o}: $!";
print $out map { "$_\n" } @o;
close $out;
print "$_\n" for @lines;
printf "trace-svg: %d file(s), %d leaf requirement(s), %d with gaps, %d warning(s)%s -> %s\n",
    $new->{nfiles}, scalar @leaf, $ngap, $nwarn, ($old ? "; $dsum" : ''), $O{o};
exit 0;
