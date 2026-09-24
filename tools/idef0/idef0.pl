#!/usr/bin/env perl
# idef0.pl -- Perl 5 port of idef0 (validator, formatter, plate renderer
# for the pipe-path IDEF0 DSL). Core modules only. Output is byte-identical
# to the Python reference: diagnostics, summaries, links, dump, text, svg,
# html, and fmt. difflib.get_close_matches is reimplemented exactly
# (Ratcliff/Obershelp SequenceMatcher.ratio) so fuzzy hints match.
use strict;
use warnings;
use feature 'unicode_strings';
use Encode qw(decode encode);
use List::Util qw(max min);
use Scalar::Util qw(refaddr);

binmode STDOUT, ':encoding(UTF-8)';
binmode STDERR, ':encoding(UTF-8)';

my $USAGE = <<'EOF';
idef0 -- validator, formatter, and plate renderer for the pipe-path IDEF0 DSL.

Usage:
  idef0 lint  FILE...              validate; GNU-format diagnostics; exit 1 on errors
  idef0 text  FILE...              render plates as character art, form-feed paginated
  idef0 html  FILE...              render HTML drawing set (plates as SVG)
  idef0 svg   NODE FILE...         render one plate (e.g. E22) as standalone SVG
  idef0 dump  FILE...              print numbered model tree(s)
  idef0 links FILE...              print project interface table
  idef0 fmt [--number|--auto] [--write] FILE...
                                   rewrite tag suffixes; --write edits in place
                                   (fmt validates structure only, not links)

Grammar summary (v1):
  line := tag name [< path | > path]     tag := [taicom]( # | digit | LETTER | NUM. )
  path := segment (| segment)*           ; comment lines start with ;
Segment resolution order: child activity by name -> port by flow name
(2+ matches = ambiguous error) -> port ref [icom]N -> node number.
A '<' path ending at an activity with exactly one output takes that output.

Diagnostics use GNU format  file:line: severity: message.
Exit status: 0 clean, 1 errors found, 2 usage failure.
EOF

my $FENCE_OPEN  = qr/^(`{3,})\s*idef0\s*$/;
my $FENCE_CLOSE = qr/^`{3,}\s*$/;
my $TAG_RE = qr/^([ \t]*)([taicom])(#|[A-Za-z]?\d+\.|[A-Za-z]?\d*)(?:\s+(.*))?$/;
my $INDENT = 2;

# ------------------------------------------------------------- helpers
sub strip  { my $s = shift; $s =~ s/^\s+//; $s =~ s/\s+\z//; $s }
sub rstrip { my $s = shift; $s =~ s/\s+\z//; $s }
sub esc {
    my $s = shift;
    $s =~ s/&/&amp;/g; $s =~ s/</&lt;/g; $s =~ s/>/&gt;/g;
    $s =~ s/"/&quot;/g; $s =~ s/'/&#x27;/g;
    $s;
}
sub isdigits { my $s = shift; $s ne '' && $s =~ /^\d+\z/ }
sub lj { my ($s, $w) = @_; my $n = $w - length $s; $n > 0 ? $s . (' ' x $n) : $s }

# Python repr() of a str
sub pyrepr {
    my $s = shift;
    my $q = ($s =~ /'/ && $s !~ /"/) ? '"' : "'";
    my $o = '';
    for my $c (split //, $s) {
        my $n = ord $c;
        if    ($c eq '\\') { $o .= '\\\\' }
        elsif ($c eq $q)   { $o .= "\\$q" }
        elsif ($c eq "\t") { $o .= '\t' }
        elsif ($c eq "\n") { $o .= '\n' }
        elsif ($c eq "\r") { $o .= '\r' }
        elsif ($n < 0x20 || ($n >= 0x7f && $n <= 0xa0) || $n == 0xad) {
            $o .= sprintf('\x%02x', $n);
        }
        else { $o .= $c }
    }
    "$q$o$q";
}

# json.dumps(str) with ensure_ascii=True
sub pyjson_str {
    my $s = shift;
    my $o = '"';
    for my $c (split //, $s) {
        my $n = ord $c;
        if    ($c eq '"')  { $o .= '\\"' }
        elsif ($c eq '\\') { $o .= '\\\\' }
        elsif ($c eq "\n") { $o .= '\n' }
        elsif ($c eq "\r") { $o .= '\r' }
        elsif ($c eq "\t") { $o .= '\t' }
        elsif ($n == 8)    { $o .= '\b' }
        elsif ($n == 12)   { $o .= '\f' }
        elsif ($n >= 0x20 && $n <= 0x7e) { $o .= $c }
        elsif ($n > 0xffff) {
            my $v = $n - 0x10000;
            $o .= sprintf('\u%04x\u%04x', 0xd800 | ($v >> 10), 0xdc00 | ($v & 0x3ff));
        }
        else { $o .= sprintf('\u%04x', $n) }
    }
    $o . '"';
}

sub splitlines {
    my $t = shift;
    return () if $t eq '';
    my @l = split /\r\n|[\n\r\x0b\x0c\x1c\x1d\x1e\x85\x{2028}\x{2029}]/, $t, -1;
    pop @l if @l && $l[-1] eq '';
    @l;
}

# ------------------------------------------------ difflib (exact port)
sub _ratio {
    my ($a, $b) = @_;    # a = candidate, b = word (set_seq2)
    my @a = split //, $a;
    my @b = split //, $b;
    my %b2j;
    push @{ $b2j{ $b[$_] } }, $_ for 0 .. $#b;
    if (@b >= 200) {    # autojunk
        my $ntest = int(@b / 100) + 1;
        for my $k (keys %b2j) { delete $b2j{$k} if @{ $b2j{$k} } > $ntest }
    }
    my $flm = sub {
        my ($alo, $ahi, $blo, $bhi) = @_;
        my ($bi, $bj, $bs) = ($alo, $blo, 0);
        my %j2len;
        for my $i ($alo .. $ahi - 1) {
            my %new;
            for my $j (@{ $b2j{ $a[$i] } || [] }) {
                next if $j < $blo;
                last if $j >= $bhi;
                my $k = $new{$j} = ($j2len{ $j - 1 } // 0) + 1;
                if ($k > $bs) { ($bi, $bj, $bs) = ($i - $k + 1, $j - $k + 1, $k) }
            }
            %j2len = %new;
        }
        while ($bi > $alo && $bj > $blo && $a[$bi - 1] eq $b[$bj - 1]) {
            $bi--; $bj--; $bs++;
        }
        while ($bi + $bs < $ahi && $bj + $bs < $bhi
               && $a[$bi + $bs] eq $b[$bj + $bs]) { $bs++ }
        ($bi, $bj, $bs);
    };
    my $m = 0;
    my @q = ([0, scalar @a, 0, scalar @b]);
    while (@q) {
        my ($alo, $ahi, $blo, $bhi) = @{ pop @q };
        my ($i, $j, $k) = $flm->($alo, $ahi, $blo, $bhi);
        if ($k) {
            $m += $k;
            push @q, [$alo, $i, $blo, $j] if $alo < $i && $blo < $j;
            push @q, [$i + $k, $ahi, $j + $k, $bhi]
                if $i + $k < $ahi && $j + $k < $bhi;
        }
    }
    my $t = @a + @b;
    $t ? 2.0 * $m / $t : 1.0;
}

sub close_match {    # get_close_matches(word, poss, n=1, cutoff)
    my ($word, $poss, $cutoff) = @_;
    my ($bs, $bx);
    for my $x (@$poss) {
        my $r = _ratio($x, $word);
        next unless $r >= $cutoff;
        if (!defined $bs || $r > $bs || ($r == $bs && $x gt $bx)) {
            ($bs, $bx) = ($r, $x);
        }
    }
    $bx;
}

# ------------------------------------------------------------- nodes
sub new_node {
    my %h = @_;
    return +{ %h, doc => [], trail => undef, parent => undef, children => [],
      ports => [], number => undef, letter => undef, node_id => undef,
      asserted => undef, link_target => undef, model => undef };
}
sub is_act { $_[0]{tag} eq 't' || $_[0]{tag} eq 'a' }
sub descendants { my $n = shift; map { ($_, descendants($_)) } @{ $n->{children} } }
sub all_ports { my $n = shift; (@{ $n->{ports} }, map { all_ports($_) } @{ $n->{children} }) }
sub has_link { defined $_[0]{link_dir} && $_[0]{link_dir} ne '' }

my $DSEQ = 0;
sub err {
    my ($d, $w, $msg, $sev) = @_;
    my ($f, $l) = (ref $w eq 'HASH') ? ($w->{fname}, $w->{line}) : @$w;
    push @$d, [$f, $l, $sev // 'error', $msg, $DSEQ++];
}

# ------------------------------------------------------------- parsing
sub parse_file {
    my ($fname, $text, $diags, $doc) = @_;
    my (@roots, @stack, $last);
    my $is_md = (lc $fname) =~ /\.(?:md|markdown)\z/ ? 1 : 0;
    my $in_fence = !$is_md;
    my ($fence_len, $fence_line) = (0, 0);
    my $rec = ($doc->{$fname} //= []);
    my @lines = splitlines($text);
    for my $ix (0 .. $#lines) {
        my $lineno = $ix + 1;
        my $raw = $lines[$ix];
        if ($is_md) {
            if (!$in_fence) {
                if ($raw =~ $FENCE_OPEN) {
                    $in_fence = 1; $fence_len = length $1; $fence_line = $lineno;
                }
                push @$rec, ['raw', $raw, undef];
                next;
            }
            if ($raw =~ $FENCE_CLOSE && length(strip($raw)) >= $fence_len) {
                $in_fence = 0;
                push @$rec, ['raw', $raw, undef];
                next;
            }
        }
        my $st = strip($raw);
        if (substr($st, 0, 2) eq ';;' || substr($st, 0, 2) eq '##') {
            my $txt = strip(substr($st, 2));
            if (!defined $last) {
                err($diags, [$fname, $lineno],
                    "'" . substr($st, 0, 2) . "' doc comment has no element line "
                    . "to attach to", 'warning');
            } else {
                push @{ $last->{doc} }, ($txt ne '' ? $txt : '\n');
            }
            push @$rec, ['raw', $raw, undef];
            next;
        }
        if ($st eq '' || $st =~ /^[;#]/) {
            push @$rec, ['raw', $raw, undef];
            next;
        }
        my ($trail, $code) = (undef, $raw);
        if ($raw =~ /\s(#.*)$/) { $trail = $1; $code = substr($raw, 0, $-[0]) }
        my @m = $code =~ $TAG_RE;
        if (!@m) {
            err($diags, [$fname, $lineno], 'cannot parse line: ' . pyrepr($st));
            push @$rec, ['raw', $raw, undef];
            next;
        }
        my ($indent, $tag, $suffix, $rest) = @m;
        if ($indent =~ /\t/) {
            err($diags, [$fname, $lineno], 'tabs in indentation; use 2 spaces per level');
            $indent =~ s/\t/  /g;
        }
        if (length($indent) % $INDENT) {
            err($diags, [$fname, $lineno],
                'indentation of ' . length($indent) . " is not a multiple of $INDENT");
        }
        my $level = int(length($indent) / $INDENT);
        $suffix = '#' if !defined $suffix || $suffix eq '';
        $rest = strip($rest // '');
        my ($ldir, $lpath);
        my $name = $rest;
        if ($rest =~ /([<>])/) {
            $ldir = $1;
            $name = strip(substr($rest, 0, $-[0]));
            my $pt = strip(substr($rest, $+[0]));
            $lpath = [map { strip($_) } ($pt eq '' ? ('') : split(/\|/, $pt, -1))];
            if (grep { $_ eq '' } @$lpath) {
                err($diags, [$fname, $lineno], 'empty segment in link path');
            }
        }
        if ($name =~ /\|/) {
            err($diags, [$fname, $lineno],
                "'|' not allowed in a name (link paths follow < or >)");
            $name =~ s/\|/ /g;
        }
        err($diags, [$fname, $lineno], "'$tag' line has no name") if $name eq '';
        my $node = new_node(tag => $tag, suffix => $suffix, name => $name,
                            link_dir => $ldir, link_path => $lpath,
                            fname => $fname, line => $lineno,
                            indent => length $indent);
        $node->{trail} = $trail;
        if (defined $trail && substr($trail, 0, 2) eq '##') {
            my $dt = strip(substr($trail, 2));
            push @{ $node->{doc} }, ($dt ne '' ? $dt : '\n');
        }
        push @$rec, ['node', $raw, $node];
        $last = $node;
        if ($tag eq 't') {
            err($diags, $node, "model root 't' must be at indentation 0") if $level != 0;
            push @roots, $node;
            @stack = ([0, $node]);
            next;
        }
        pop @stack while @stack && $stack[-1][0] >= $level;
        if (!@stack) {
            err($diags, $node, "'$tag' line has no parent model/activity");
            next;
        }
        my ($plevel, $parent) = @{ $stack[-1] };
        err($diags, $node, "indentation jumps from level $plevel to $level")
            if $plevel != $level - 1;
        $node->{parent} = $parent;
        if ($tag eq 'a') {
            if (!is_act($parent)) { err($diags, $node, 'activity nested under a port') }
            else {
                push @{ $parent->{children} }, $node;
                push @stack, [$level, $node];
            }
        } else {
            if (!is_act($parent)) { err($diags, $node, 'port nested under a port') }
            else { push @{ $parent->{ports} }, $node }
        }
    }
    if ($is_md && $in_fence) {
        err($diags, [$fname, $fence_line],
            'unclosed ```idef0 fence at end of file', 'warning');
    }
    @roots;
}

# ------------------------------------------------------------- numbering
sub assign_numbers {
    my ($models, $diags) = @_;
    my %letters;
    for my $t (@$models) {
        my $s = $t->{suffix};
        my $letter;
        if ($s eq '#' || $s eq '') {
            my ($c) = $t->{name} =~ /(\p{L})/;
            $letter = defined $c ? uc $c : 'X';
        } elsif (length $s == 1 && $s =~ /^\p{L}\z/) {
            $letter = uc $s;
        } else {
            err($diags, $t, 'bad model suffix ' . pyrepr($s) . ': use a single letter or #');
            $letter = 'X';
        }
        if (exists $letters{$letter}) {
            err($diags, $t, "duplicate model letter '$letter' (also "
                . pyrepr($letters{$letter}{name}) . ')');
        }
        $letters{$letter} = $t;
        $t->{letter} = $letter;
        $t->{node_id} = $letter;
        $t->{model} = $t;
        number_children($t, $diags);
        number_ports($t, $diags);
        $_->{model} = $t for @{ $t->{ports} };
        for my $a (descendants($t)) {
            $a->{model} = $t;
            number_ports($a, $diags);
            $_->{model} = $t for @{ $a->{ports} };
        }
    }
    \%letters;
}

sub number_children {
    my ($act, $diags) = @_;
    my $kids = $act->{children};
    err($diags, $act, 'more than 9 activities on one plate') if @$kids > 9;
    my %pinned;
    for my $k (@$kids) {
        my $s = $k->{suffix};
        $k->{asserted} = undef;
        if ($s =~ /\.\z/) { $k->{asserted} = substr($s, 0, -1); next }
        if ($s ne '' && $s ne '#' && isdigits($s)) {
            if (length $s != 1 || $s eq '0') {
                err($diags, $k, 'pinned number ' . pyrepr($s) . ' must be a single digit 1-9');
                next;
            }
            my $d = int $s;
            if (exists $pinned{$d}) {
                err($diags, $k, "duplicate pinned digit $d on plate $act->{node_id} "
                    . "(also line $pinned{$d}{line})");
            } else {
                $pinned{$d} = $k;
                $k->{number} = $d;
            }
        } elsif ($s ne '#' && $s ne '' && $s !~ /\.\z/) {
            err($diags, $k, 'bad activity suffix ' . pyrepr($s));
        }
    }
    my $nxt = 1;
    for my $k (@$kids) {
        next if defined $k->{number};
        $nxt++ while exists $pinned{$nxt};
        $k->{number} = $nxt;
        $pinned{$nxt} = $k;
        $nxt++;
    }
    my $base = $act->{tag} eq 'a' ? $act->{node_id} : $act->{letter};
    for my $k (@$kids) {
        $k->{node_id} = "$base$k->{number}";
        if (defined $k->{asserted} && $k->{asserted} ne ''
            && $k->{asserted} ne $k->{node_id}) {
            err($diags, $k, "asserted number $k->{asserted} but position derives "
                . $k->{node_id});
        }
        number_children($k, $diags);
    }
}

sub number_ports {
    my ($act, $diags) = @_;
    my %counts;
    for my $p (@{ $act->{ports} }) {
        my $s = $p->{suffix};
        my $n;
        if ($s =~ /\.\z/) {
            err($diags, $p, 'asserted numbers are for activities; ports take # or a digit');
        } elsif (isdigits($s)) {
            if (length $s != 1 || $s eq '0') {
                err($diags, $p, 'pinned port number ' . pyrepr($s) . ' must be a single digit 1-9');
            } else { $n = int $s }
        } elsif ($s ne '#' && $s ne '') {
            err($diags, $p, 'bad port suffix ' . pyrepr($s));
        }
        $n //= ($counts{ $p->{tag} } // 0) + 1;
        $counts{ $p->{tag} } = max($counts{ $p->{tag} } // 0, $n);
        $p->{number} = $n;
        $p->{node_id} = "$act->{node_id}.$p->{tag}$n";
        my $ld = $p->{link_dir} // '';
        err($diags, $p, "outputs declare goes-to with '>', not '<'")
            if $ld eq '<' && $p->{tag} eq 'o';
        err($diags, $p, "'$p->{tag}' ports declare comes-from with '<', not '>'")
            if $ld eq '>' && $p->{tag} =~ /^[icm]\z/;
    }
}

# ------------------------------------------------------------- wiring
sub wire_model {
    my ($t, $diags) = @_;
    my (%prod, @pk, %cons, @ck);
    for my $p (all_ports($t)) {
        if ($p->{tag} eq 'o') { push @pk, $p->{name} unless $prod{ $p->{name} }; push @{ $prod{ $p->{name} } }, $p }
        else                  { push @ck, $p->{name} unless $cons{ $p->{name} }; push @{ $cons{ $p->{name} } }, $p }
    }
    $t->{producers} = \%prod;
    $t->{consumers} = \%cons;
    for my $name (@ck) {
        next if exists $prod{$name};
        my $c = close_match($name, \@pk, 0.86);
        for my $p (@{ $cons{$name} }) {
            next if has_link($p);
            err($diags, $p, "'$name' has no producer; did you mean '$c'?", 'warning')
                if defined $c;
        }
    }
    for my $name (@pk) {
        next if exists $cons{$name};
        my $c = close_match($name, \@ck, 0.86);
        for my $p (@{ $prod{$name} }) {
            next if has_link($p);
            err($diags, $p, "'$name' has no consumer; did you mean '$c'?", 'warning')
                if defined $c;
        }
    }
}

# ------------------------------------------------------------- links
sub walk {
    my ($scope, $segs, $want) = @_;
    my $cur = $scope;
    for my $i (0 .. $#$segs) {
        my $seg = $segs->[$i];
        my $last = $i == $#$segs;
        my @kids = grep { $_->{name} eq $seg } @{ $cur->{children} };
        if (@kids == 1) { $cur = $kids[0]; next }
        my @pm = grep { $_->{name} eq $seg } @{ $cur->{ports} };
        die { ambig => 1, act => $cur, flow => $seg } if @pm >= 2;
        return $last ? $pm[0] : undef if @pm == 1;
        if ($seg =~ /^[icom][1-9]\z/) {
            my ($tg, $nm) = (substr($seg, 0, 1), substr($seg, 1));
            my @pr = grep { $_->{tag} eq $tg && $_->{number} == $nm } @{ $cur->{ports} };
            return $last ? $pr[0] : undef if @pr;
        }
        my @nn = grep { defined $_->{node_id} && $_->{node_id} eq $seg } @{ $cur->{children} };
        if (@nn == 1) { $cur = $nn[0]; next }
        return undef;
    }
    if ($want eq '<') {
        my @outs = grep { $_->{tag} eq 'o' } @{ $cur->{ports} };
        return $outs[0] if @outs == 1;
    }
    undef;
}

sub suggest {
    my ($segs, $scope_model, $letters) = @_;
    my %names = map { $_ => 1 } keys %$letters;
    $names{ $_->{name} } = 1 for values %$letters;
    if (defined $scope_model) {
        for my $a (descendants($scope_model)) {
            $names{ $a->{name} } = 1;
            $names{ $a->{node_id} } = 1;
        }
    }
    my @n = keys %names;
    for my $seg (@$segs) {
        next if $names{$seg};
        my $c = close_match($seg, \@n, 0.75);
        return " (closest: '$c')" if defined $c;
    }
    '';
}

sub resolve_links {
    my ($models, $letters, $diags) = @_;
    my %by_name = map { $_->{name} => $_ } @$models;
    my @cross;
    for my $t (@$models) {
        for my $p (all_ports($t)) {
            next unless has_link($p);
            my $segs = $p->{link_path};
            my ($target, $addressed) = (undef, $t);
            my $ok = eval {
                my $scope = $p->{parent};
                while (defined $scope && !defined $target) {
                    $target = walk($scope, $segs, $p->{link_dir});
                    $scope = $scope->{parent};
                }
                if (!defined $target && @$segs) {
                    my $mt = $letters->{ $segs->[0] } // $by_name{ $segs->[0] };
                    if (defined $mt && @$segs > 1) {
                        $addressed = $mt;
                        $target = walk($mt, [@$segs[1 .. $#$segs]], $p->{link_dir});
                    }
                }
                1;
            };
            if (!$ok) {
                my $e = $@;
                die $e unless ref $e eq 'HASH' && $e->{ambig};
                err($diags, $p, "'$e->{act}{name}' has no unique port for flow "
                    . "'$e->{flow}'; add the port or use o1/i1 form");
                next;
            }
            if (!defined $target) {
                my $hint = suggest($segs, $addressed, $letters);
                err($diags, $p, "broken link: cannot resolve '" . join('|', @$segs) . "'$hint");
                next;
            }
            $p->{link_target} = $target;
            my ($src, $dst) = $p->{link_dir} eq '<' ? ($target, $p) : ($p, $target);
            if ($src->{tag} ne 'o' && !($src->{tag} eq 'm' && $dst->{tag} eq 'm')) {
                err($diags, $p, "link source '$src->{node_id}' is '$src->{tag}' -- "
                    . 'flows must originate at an output', 'warning');
            }
            err($diags, $p, "link destination '$dst->{node_id}' is an output", 'warning')
                if $dst->{tag} eq 'o';
            push @cross, [$src, $dst, $p] if $src->{model} != $dst->{model};
        }
    }
    for my $c (@cross) {
        my ($src, $dst, $via) = @$c;
        my $other = $via == $src ? $dst : $src;
        if (!has_link($other)) {
            err($diags, $via, "one-sided cross-model link: $other->{node_id} "
                . pyrepr($other->{name}) . ' does not declare the reciprocal '
                . ($other->{tag} eq 'o' ? '>' : '<') . ' link', 'warning');
        }
    }
    my (@rows, %seen);
    for my $c (@cross) {
        my ($src, $dst) = @$c;
        my @nm = $src->{name} eq $dst->{name} ? ($src->{name}) : ($src->{name}, $dst->{name});
        for my $name (@nm) {
            my $key = join "\0", $src->{node_id}, $dst->{node_id}, $name;
            next if $seen{$key}++;
            push @rows, [$src, $dst, $name];
        }
    }
    my $i = 0;
    $_->[3] = $i++ for @rows;
    @rows = sort {
        $a->[0]{model}{letter} cmp $b->[0]{model}{letter}
            || $a->[0]{node_id} cmp $b->[0]{node_id}
            || $a->[1]{node_id} cmp $b->[1]{node_id}
            || $a->[2] cmp $b->[2] || $a->[3] <=> $b->[3]
    } @rows;
    \@rows;
}

# ------------------------------------------------------------- project
sub load_project {
    my ($files, $diags, $links_too) = @_;
    $links_too //= 1;
    my (%doc, @models);
    for my $f (@$files) {
        my $fh;
        if (!open $fh, '<:raw', $f) {
            my $en = $! + 0;
            print STDERR "idef0: cannot read $f: [Errno $en] $!: " . pyrepr($f) . "\n";
            exit 2;
        }
        local $/;
        my $bytes = <$fh> // '';
        close $fh;
        my $text = decode('UTF-8', $bytes);
        push @models, parse_file($f, $text, $diags, \%doc);
    }
    my $letters = assign_numbers(\@models, $diags);
    my $rows = [];
    if ($links_too) {
        wire_model($_, $diags) for @models;
        $rows = resolve_links(\@models, $letters, $diags);
    }
    (\@models, $letters, $rows, \%doc);
}

sub emit_diags {
    my ($diags, $out) = @_;
    $out //= \*STDOUT;
    my $e = grep { $_->[2] eq 'error' } @$diags;
    my $w = grep { $_->[2] eq 'warning' } @$diags;
    for my $d (sort { $a->[0] cmp $b->[0] || $a->[1] <=> $b->[1] || $a->[4] <=> $b->[4] } @$diags) {
        print {$out} "$d->[0]:$d->[1]: $d->[2]: $d->[3]\n";
    }
    ($e, $w);
}

sub summary {
    my ($files, $diags, $models, $rows) = @_;
    my $e = grep { $_->[2] eq 'error' } @$diags;
    my $w = grep { $_->[2] eq 'warning' } @$diags;
    my $acts = 0;
    $acts += () = descendants($_) for @$models;
    printf "%d file(s): %d error(s), %d warning(s), %d model(s), %d activities, %d link(s)\n",
        scalar @$files, $e, $w, scalar @$models, $acts, scalar @$rows;
    $e;
}

# ------------------------------------------------------------- commands
sub cmd_lint {
    my $files = shift;
    my @diags;
    my ($models, $letters, $rows) = load_project($files, \@diags);
    emit_diags(\@diags);
    summary($files, \@diags, $models, $rows) ? 1 : 0;
}

sub cmd_dump {
    my $files = shift;
    my @diags;
    my ($models) = load_project($files, \@diags);
    my ($errs) = emit_diags(\@diags);
    my $rec;
    $rec = sub {
        my ($a, $depth) = @_;
        for my $p (@{ $a->{ports} }) {
            my $lk = has_link($p) ? "  $p->{link_dir} " . join('|', @{ $p->{link_path} }) : '';
            print '  ' x $depth, lj($p->{node_id}, 12), ' ', uc($p->{tag}), " $p->{name}$lk\n";
        }
        for my $k (@{ $a->{children} }) {
            print '  ' x $depth, lj($k->{node_id}, 12), " $k->{name}\n";
            $rec->($k, $depth + 1);
        }
    };
    for my $t (@$models) {
        print "$t->{node_id}  $t->{name}    [$t->{fname}]\n";
        $rec->($t, 1);
        print "\n";
    }
    $errs ? 1 : 0;
}

sub cmd_links {
    my $files = shift;
    my @diags;
    my ($models, $letters, $rows) = load_project($files, \@diags);
    my ($errs) = emit_diags(\@diags);
    print lj('SOURCE', 14), ' ', lj('DEST', 14), " FLOW\n";
    print lj($_->[0]{node_id}, 14), ' ', lj($_->[1]{node_id}, 14), " $_->[2]\n" for @$rows;
    $errs ? 1 : 0;
}

# ------------------------------------------------------- plate layout
my $BOX_H = 5;

sub dkey {
    my ($t, $el) = @_;
    return "$el->{letter}0" if $el->{tag} eq 't';
    return $el->{node_id} if $el->{tag} eq 'a';
    my $par = $el->{parent};
    my $pid = $par->{tag} eq 'a' ? $par->{node_id} : "$par->{letter}0";
    "$pid.$el->{tag}$el->{number}";
}

sub doc_plain { my $s = join ' ', @{ $_[0]{doc} }; $s =~ s/\\n/\n/g; $s }

sub md_inline {
    my $s = esc(shift);
    $s =~ s/`([^`]+)`/<code>$1<\/code>/g;
    $s =~ s/\*\*(.+?)\*\*/<strong>$1<\/strong>/g;
    $s =~ s/(?<!\*)\*([^*]+)\*(?!\*)/<em>$1<\/em>/g;
    $s =~ s/\[([^\]]+)\]\(([^)\s]+)\)/<a href="$2" target="_blank">$1<\/a>/g;
    $s;
}

sub doc_html {
    my $el = shift;
    my @paras = map { strip($_) } split /\\n/, join(' ', @{ $el->{doc} }), -1;
    join '', map { '<p>' . md_inline($_) . '</p>' } grep { $_ ne '' } @paras;
}

sub plates_of {
    my $t = shift;
    my @out = ([$t, $t->{children}]);
    for my $a (descendants($t)) {
        push @out, [$a, $a->{children}] if @{ $a->{children} };
    }
    @out;
}

sub plate_id { my ($t, $node) = @_; $node->{tag} eq 'a' ? $node->{node_id} : "$t->{letter}0" }

sub port_route {
    my ($p, $t) = @_;
    if (has_link($p)) {
        my $o = $p->{link_target};
        return "$p->{link_dir} " . join('|', @{ $p->{link_path} })
            if !defined $o || !defined $o->{model};
        return "$p->{link_dir} $o->{model}{letter}:$o->{node_id}";
    }
    my $tbl = $p->{tag} ne 'o' ? $t->{producers} : $t->{consumers};
    my @peers = grep { ($_->{parent} // 0) != ($p->{parent} // 0) } @{ $tbl->{ $p->{name} } || [] };
    if (@peers) {
        my %u = map { $_->{parent}{node_id} => 1 } @peers;
        return ($p->{tag} ne 'o' ? 'from ' : 'to ') . join(',', sort keys %u);
    }
    '';
}

sub layout_plate {
    my ($t, $node, $boxes) = @_;
    my $bw = min(26, max(20, max(map { length $_->{name} } @$boxes) + 4));
    my (@in_labels, @ext);
    my %box_ids = map { refaddr($_) => 1 } @$boxes;
    for my $b (@$boxes) {
        for my $p (@{ $b->{ports} }) {
            if ($p->{tag} eq 'i') {
                my $r = port_route($p, $t);
                push @in_labels, $p->{name} . ($r ne '' ? " ($r)" : '');
            }
            if ($p->{tag} eq 'c') {
                my @prod = grep { $box_ids{ refaddr($_->{parent}) } }
                    @{ $t->{producers}{ $p->{name} } || [] };
                push @ext, $p->{name} if !@prod && !grep { $_ eq $p->{name} } @ext;
            }
        }
    }
    my $left = max(8, @in_labels ? max(map { length } @in_labels) + 4 : 8);
    my $top = 2 * @ext + 2;
    my ($hgap, $vgap) = (12, 4);
    my %pos;
    for my $i (0 .. $#$boxes) {
        $pos{ refaddr($boxes->[$i]) } = [$left + $i * ($bw + $hgap), $top + $i * ($BOX_H + $vgap)];
    }
    my ($lastx, $lasty) = @{ $pos{ refaddr($boxes->[-1]) } };
    my $has_mech = grep { $_->{tag} eq 'm' } map { @{ $_->{ports} } } @$boxes;
    my $W = max($lastx + $bw + 28, 64);
    my $H = $lasty + $BOX_H + ($has_mech ? 5 : 2) + 6;
    (\%pos, $bw, $left, $top, $W, $H, \@ext);
}

sub render_text_plate {
    my ($t, $node, $boxes, $pageno) = @_;
    my ($pos, $bw, $left, $top, $W, $H, $ext) = layout_plate($t, $node, $boxes);
    my %g;
    my ($maxr, $maxc);
    my $put = sub {
        my ($r, $c, $s) = @_;
        my @ch = split //, $s;
        for my $k (0 .. $#ch) {
            next unless $c + $k >= 0;
            $g{"$r,@{[$c + $k]}"} = $ch[$k];
            $maxr = $r if !defined $maxr || $r > $maxr;
            $maxc = $c + $k if !defined $maxc || $c + $k > $maxc;
        }
    };
    for my $ci (0 .. $#$ext) {
        my $cname = $ext->[$ci];
        my $row = 2 * $ci;
        my @cons = grep { my $b = $_; grep { $_->{tag} eq 'c' && $_->{name} eq $cname } @{ $b->{ports} } } @$boxes;
        next unless @cons;
        my ($x0) = @{ $pos->{ refaddr($cons[0]) } };
        $put->($row, $x0 + 2, $cname);
        for my $b (@cons) {
            my ($x, $y) = @{ $pos->{ refaddr($b) } };
            my $cx = $x + int($bw / 2);
            for my $r ($row + 1 .. $y - 1) {
                $put->($r, $cx, '|') unless exists $g{"$r,$cx"};
            }
            $put->($y - 1, $cx, 'v');
        }
    }
    for my $b (@$boxes) {
        my ($x, $y) = @{ $pos->{ refaddr($b) } };
        $put->($y, $x, '+' . ('-' x ($bw - 2)) . '+');
        $put->($y + $_, $x, '|' . (' ' x ($bw - 2)) . '|') for 1 .. $BOX_H - 2;
        $put->($y + $BOX_H - 1, $x, '+' . ('-' x ($bw - 2)) . '+');
        my $nm = length($b->{name}) <= $bw - 4 ? $b->{name} : substr($b->{name}, 0, $bw - 7) . '...';
        $put->($y + 1, $x + 2, $nm);
        my $tagn = $b->{node_id} . (@{ $b->{children} } ? '*' : '');
        $put->($y + $BOX_H - 2, $x + $bw - 2 - length $tagn, $tagn);
        my @ins = grep { $_->{tag} eq 'i' } @{ $b->{ports} };
        for my $k (0 .. $#ins) {
            my $p = $ins[$k];
            my $r = $y + 1 + min($k, $BOX_H - 3);
            my $rt = port_route($p, $t);
            my $lab = $p->{name} . ($rt ne '' ? " ($rt)" : '');
            $put->($r, $x - length($lab) - 4, "$lab ->");
        }
        my @outs = grep { $_->{tag} eq 'o' } @{ $b->{ports} };
        for my $k (0 .. $#outs) {
            my $p = $outs[$k];
            my $r = $y + 1 + min($k, $BOX_H - 3);
            my $rt = port_route($p, $t);
            my $lab = $p->{name} . ($rt ne '' ? " ($rt)" : '');
            $put->($r, $x + $bw + 1, "-> $lab");
        }
        my @mechs = grep { $_->{tag} eq 'm' } @{ $b->{ports} };
        if (@mechs) {
            $put->($y + $BOX_H, $x + int($bw / 2), '^');
            $put->($y + $BOX_H + 1, $x + 2, join(', ', map { $_->{name} } @mechs));
        }
    }
    $maxr //= 0;
    $maxc //= 0;
    $W = max($W, $maxc + 2);
    my @lines;
    for my $r (0 .. max($H, $maxr + 1) - 1) {
        push @lines, rstrip(join '', map { $g{"$r,$_"} // ' ' } 0 .. $W - 1);
    }
    my $total = max(max(0, map { length } @lines), 64);
    my $mid = $total - 26;
    my $nid = plate_id($t, $node);
    my $title = $node->{name};
    $title = substr($title, 0, $mid - 5) . '...' if length($title) > $mid - 2;
    my $num = "p.$pageno";
    my $bar = '+' . ('-' x 11) . '+' . ('-' x $mid) . '+' . ('-' x 11) . '+';
    my @tb = ($bar,
        '|' . lj(' NODE', 11) . '|' . lj(' TITLE', $mid) . '|' . lj(' NUMBER', 11) . '|',
        '|' . lj(" $nid", 11) . '|' . lj(" $title", $mid) . '|' . lj(" $num", 11) . '|',
        $bar);
    join "\n", @lines, @tb;
}

sub all_plates { my $models = shift; map { my $t = $_; map { [$t, @$_] } plates_of($t) } @$models }

sub cmd_text {
    my $files = shift;
    my @diags;
    my ($models) = load_project($files, \@diags);
    my ($errs) = emit_diags(\@diags, \*STDERR);
    return 1 if $errs;
    my @plates = all_plates($models);
    print 'NODE INDEX', ' ' x 44, "p.1\n", '-' x 64, "\n";
    for my $i (0 .. $#plates) {
        my ($t, $node) = @{ $plates[$i] };
        print '  ', lj(plate_id($t, $node), 10), ' ', lj($node->{name}, 40), ' p.', $i + 2, "\n";
    }
    for my $i (0 .. $#plates) {
        print "\f\n";
        print render_text_plate(@{ $plates[$i] }, $i + 2), "\n";
    }
    0;
}

# ------------------------------------------------------------- svg
my ($CW, $CH, $PAD) = (9, 18, 20);
sub gfmt { sprintf '%g', $_[0] }

sub elbow {
    my ($sx, $sy, $midx, $dyy, $dxx, $r) = @_;
    $r //= 7;
    return "M$sx,$sy H$dxx" if $sy == $dyy;
    my $vy = $dyy > $sy ? 1 : -1;
    my $hx2 = $dxx >= $midx ? 1 : -1;
    my $rr = min($r, abs($midx - $sx) / 2, abs($dyy - $sy) / 2,
                 $dxx != $midx ? abs($dxx - $midx) / 2 : $r);
    return "M$sx,$sy H$midx V$dyy H$dxx" if $rr < 1;
    "M$sx,$sy H" . gfmt($midx - $rr) . ' '
        . "Q$midx,$sy $midx," . gfmt($sy + $vy * $rr) . ' '
        . 'V' . gfmt($dyy - $vy * $rr) . ' '
        . "Q$midx,$dyy " . gfmt($midx + $hx2 * $rr) . ",$dyy "
        . "H$dxx";
}

sub svg_plate {
    my ($t, $node, $boxes, $pageno, $rich) = @_;
    my ($pos, $bw, $left, $top, $W, $H, $ext) = layout_plate($t, $node, $boxes);
    my $dattr = sub {
        my $el = shift;
        return '' if !defined $el || !@{ $el->{doc} } || !$rich;
        ' class="hasdoc" data-doc="' . dkey($t, $el) . '"';
    };
    my $dtitle = sub {
        my $el = shift;
        return '' if !defined $el || !@{ $el->{doc} } || $rich;
        '<title>' . esc(doc_plain($el)) . '</title>';
    };
    my $X = sub { $_[0] * $CW + $PAD };
    my $Y = sub { $_[0] * $CH + $PAD };
    my %box_ids = map { refaddr($_) => 1 } @$boxes;
    my $width = $X->(max($W, 64)) + $PAD;
    my $height = $Y->($H + 4) + $PAD;
    my @o;
    push @o, qq{<svg xmlns="http://www.w3.org/2000/svg" width="$width" }
        . qq{height="$height" viewBox="0 0 $width $height" }
        . qq{font-family="IBM Plex Mono,monospace">};
    push @o, qq{<rect width="$width" height="$height" fill="#fdfcf8"/>};
    push @o, '<defs><marker id="arr" markerWidth="8" markerHeight="8" '
        . 'refX="7" refY="3" orient="auto"><path d="M0,0 L7,3 L0,6 z" '
        . 'fill="#222"/></marker></defs>';
    for my $ci (0 .. $#$ext) {
        my $cname = $ext->[$ci];
        my $row = 2 * $ci;
        my @cons = grep { my $b = $_; grep { $_->{tag} eq 'c' && $_->{name} eq $cname } @{ $b->{ports} } } @$boxes;
        next unless @cons;
        my ($x0) = @{ $pos->{ refaddr($cons[0]) } };
        my ($dp) = grep { $_->{tag} eq 'c' && $_->{name} eq $cname && @{ $_->{doc} } }
            map { @{ $_->{ports} } } @cons;
        push @o, '<text x="' . $X->($x0 + 2) . '" y="' . ($Y->($row) + 12) . '" font-size="11"'
            . $dattr->($dp) . '>' . esc($cname) . $dtitle->($dp) . '</text>';
        for my $b (@cons) {
            my ($x, $y) = @{ $pos->{ refaddr($b) } };
            my $cx = $X->($x + int($bw / 2));
            push @o, "<path d=\"M$cx," . ($Y->($row) + 16) . ' V' . $Y->($y) . '" fill="none" '
                . 'stroke="#222" stroke-width="1.1" marker-end="url(#arr)"/>';
        }
    }
    for my $b (@$boxes) {
        for my $p (@{ $b->{ports} }) {
            next if $p->{tag} ne 'o';
            for my $q (@{ $t->{consumers}{ $p->{name} } || [] }) {
                next if !$box_ids{ refaddr($q->{parent}) } || $q->{parent} == $b;
                next if $q->{tag} eq 'c';
                my ($sx0, $sy0) = @{ $pos->{ refaddr($b) } };
                my ($dx0, $dy0) = @{ $pos->{ refaddr($q->{parent}) } };
                my $sx = $X->($sx0 + $bw);
                my $sy = $Y->($sy0 + 2) + int($CH / 2);
                my $dxx = $X->($dx0);
                my $dyy = $Y->($dy0 + 2) + int($CH / 2);
                my $midx = $sx + 5 * $CW;
                push @o, '<path d="' . elbow($sx, $sy, $midx, $dyy, $dxx) . '" '
                    . 'fill="none" stroke="#222" stroke-width="1.1" marker-end="url(#arr)"/>';
                my $fl = @{ $p->{doc} } ? $p : $q;
                push @o, '<text x="' . ($midx + 4) . '" y="' . int(($sy + $dyy) / 2) . '" '
                    . 'font-size="9"' . $dattr->($fl) . '>' . esc($p->{name})
                    . $dtitle->($fl) . '</text>';
            }
        }
    }
    for my $b (@$boxes) {
        my ($x0, $y0) = @{ $pos->{ refaddr($b) } };
        my ($x, $y) = ($X->($x0), $Y->($y0));
        my ($w, $h) = ($bw * $CW, $BOX_H * $CH);
        my $kids = @{ $b->{children} };
        push @o, qq{<a href="#plate-$b->{node_id}">} if $rich && $kids;
        push @o, qq{<rect x="$x" y="$y" width="$w" height="$h" }
            . 'fill="#fff" stroke="#222" stroke-width="1.6"/>';
        my $nm = length($b->{name}) <= $bw - 4 ? $b->{name} : substr($b->{name}, 0, $bw - 7) . '...';
        my $cxf = ($w % 2) ? sprintf('%.1f', $x + $w / 2) : ($x + $w / 2) . '.0';
        push @o, qq{<text x="$cxf" y="} . ($y + 24) . '" font-size="12" '
            . 'text-anchor="middle"' . $dattr->($b) . '>' . esc($nm) . $dtitle->($b) . '</text>';
        push @o, '<text x="' . ($x + $w - 6) . '" y="' . ($y + $h - 8) . '" font-size="10" '
            . 'text-anchor="end" fill="#555">' . $b->{node_id} . ($kids ? '*' : '') . '</text>';
        push @o, '</a>' if $rich && $kids;
        my @ins = grep { $_->{tag} eq 'i' } @{ $b->{ports} };
        for my $k (0 .. $#ins) {
            my $p = $ins[$k];
            my $py = $y + $CH * (1 + min($k, $BOX_H - 3)) + int($CH / 2);
            my $rt = port_route($p, $t);
            next if $rt =~ /^from /;
            my $lab = $p->{name} . ($rt ne '' ? "  [$rt]" : '');
            push @o, '<path d="M' . ($x - 40) . ",$py H$x\" fill=\"none\" "
                . 'stroke="#222" stroke-width="1.1" marker-end="url(#arr)"/>';
            push @o, '<text x="' . ($x - 44) . '" y="' . ($py - 3) . '" font-size="9" '
                . 'text-anchor="end"' . $dattr->($p) . '>' . esc($lab) . $dtitle->($p) . '</text>';
        }
        my @outs = grep { $_->{tag} eq 'o' } @{ $b->{ports} };
        for my $k (0 .. $#outs) {
            my $p = $outs[$k];
            my $py = $y + $CH * (1 + min($k, $BOX_H - 3)) + int($CH / 2);
            my $rt = port_route($p, $t);
            next if $rt =~ /^to /;
            my $lab = $p->{name} . ($rt ne '' ? "  [$rt]" : '');
            push @o, '<path d="M' . ($x + $w) . ",$py H" . ($x + $w + 40) . '" fill="none" '
                . 'stroke="#222" stroke-width="1.1" marker-end="url(#arr)"/>';
            push @o, '<text x="' . ($x + $w + 44) . '" y="' . ($py - 3) . '" font-size="9"'
                . $dattr->($p) . '>' . esc($lab) . $dtitle->($p) . '</text>';
        }
        my @mechs = grep { $_->{tag} eq 'm' } @{ $b->{ports} };
        if (@mechs) {
            my $cx = $x + int($w / 2);
            push @o, "<path d=\"M$cx," . ($y + $h + 30) . " V" . ($y + $h) . '" fill="none" '
                . 'stroke="#222" stroke-width="1.1" marker-end="url(#arr)"/>';
            my @parts;
            for my $j (0 .. $#mechs) {
                my $p = $mechs[$j];
                push @parts, ($j ? ', ' : '') . '<tspan' . $dattr->($p) . '>' . esc($p->{name})
                    . $dtitle->($p) . '</tspan>';
            }
            push @o, '<text x="' . ($cx + 4) . '" y="' . ($y + $h + 28) . '" font-size="9">'
                . join('', @parts) . '</text>';
        }
    }
    my $ty = $height - 3 * $CH;
    my $nid = plate_id($t, $node);
    push @o, qq{<rect x="0" y="$ty" width="$width" height="} . (3 * $CH) . '" fill="#fff" stroke="#222"/>';
    push @o, qq{<line x1="99" y1="$ty" x2="99" y2="$height" stroke="#222"/>};
    push @o, '<line x1="' . ($width - 99) . qq{" y1="$ty" x2="} . ($width - 99) . qq{" y2="$height" stroke="#222"/>};
    push @o, '<text x="10" y="' . ($ty + 16) . '" font-size="10">NODE</text>';
    push @o, '<text x="10" y="' . ($ty + 36) . qq{" font-size="12">$nid</text>};
    push @o, '<text x="110" y="' . ($ty + 16) . '" font-size="10">TITLE</text>';
    push @o, '<text x="110" y="' . ($ty + 36) . '" font-size="12"' . $dattr->($node) . '>'
        . esc($node->{name}) . $dtitle->($node) . '</text>';
    push @o, '<text x="' . ($width - 89) . '" y="' . ($ty + 16) . '" font-size="10">NUMBER</text>';
    push @o, '<text x="' . ($width - 89) . '" y="' . ($ty + 36) . qq{" font-size="12">p.$pageno</text>};
    push @o, '</svg>';
    join "\n", @o;
}

sub cmd_svg {
    my ($nodeid, $files) = @_;
    my @diags;
    my ($models) = load_project($files, \@diags);
    my ($errs) = emit_diags(\@diags, \*STDERR);
    return 1 if $errs;
    my @plates = all_plates($models);
    for my $i (0 .. $#plates) {
        my ($t, $node, $boxes) = @{ $plates[$i] };
        if (plate_id($t, $node) eq $nodeid) {
            print svg_plate($t, $node, $boxes, $i + 2), "\n";
            return 0;
        }
    }
    print STDERR 'idef0: no plate ' . pyrepr($nodeid) . "\n";
    2;
}

sub plate_of_port {
    my ($p, $pageof) = @_;
    my $a = $p->{parent};
    return undef if !defined $a || $a->{tag} eq 't';
    my $par = $a->{parent};
    my $pid = $par->{tag} eq 'a' ? $par->{node_id} : "$par->{letter}0";
    exists $pageof->{$pid} ? $pid : undef;
}

my $HTML_CSS = <<'EOF';
body{font-family:IBM Plex Mono,monospace;background:#eee;margin:0}
.plate{background:#fff;margin:10px auto;padding:6px;box-shadow:0 1px 4px #0003;
width:max-content;max-width:calc(100vw - 20px);overflow-x:auto;scroll-margin-top:4px;
page-break-after:always}
.plate svg{display:block;width:auto;height:auto;max-width:calc(100vw - 34px);max-height:calc(100vh - 60px)}
body.one2one .plate svg{max-width:none;max-height:none}
.zoom{float:right}.zoom a{margin:0 0 0 4px}.zoom a.on{font-weight:700;color:#000;text-decoration:none;cursor:default}
@media print{.plate svg{max-width:100%;max-height:none}}
h1{font-size:16px;margin:18px}
h1 svg.logo{height:22px;width:auto;color:#eee;vertical-align:-4px;margin-right:14px}
table{border-collapse:collapse;margin:18px;background:#fff}
td,th{border:1px solid #999;padding:3px 9px;font-size:12px}
.p1{display:flex;flex-wrap:wrap;align-items:flex-start;gap:0 18px}.p1 table{margin-top:0}.p1 caption{text-align:left;font-weight:700;font-size:12px;padding:0 0 6px}
a{color:#27235d}
.nav{font-size:12px;padding:4px 8px;background:#e4e4e7;border-bottom:1px solid #ddd;
position:sticky;left:0}
.nav a{text-decoration:none;margin-right:4px}
.dim{color:#999}
details.notes{font-size:12px;max-width:640px;padding:4px 8px;background:#fdfcf2;
border-bottom:1px solid #eee}
details.notes p{margin:4px 0}
.hasdoc{text-decoration:underline dotted 1.5px #6a994e;cursor:help}
svg a text{cursor:pointer}
svg a:hover rect{fill:#f5f9ee}
#tip{position:fixed;display:none;z-index:9;max-width:340px;background:#fffbea;
border:1px solid #b7a;box-shadow:2px 3px 8px #0004;padding:2px 12px;
font-size:12.5px;line-height:1.45}
#tip p{margin:8px 0}
#tip code{background:#eee8d5;padding:0 3px}
EOF

my $HTML_JS = <<'EOF';
function zoom(one){document.body.classList.toggle('one2one',!!one);
 document.querySelectorAll('.zoom a').forEach(a=>a.classList.toggle('on',a.classList.contains(one?'one':'fit')));
 try{localStorage.setItem('idef0-zoom',one?'1':'0');}catch(e){}return false;}
try{if(localStorage.getItem('idef0-zoom')==='1')zoom(1);}catch(e){}
const tip=document.getElementById('tip');
let pin=null;
function show(k,x,y){tip.innerHTML=DOCS[k]||'';tip.style.display='block';
 const r=tip.getBoundingClientRect();
 x=Math.min(x+14,innerWidth-r.width-8);y=Math.min(y+16,innerHeight-r.height-8);
 tip.style.left=Math.max(4,x)+'px';tip.style.top=Math.max(4,y)+'px';}
function hide(){tip.style.display='none';pin=null;}
const canHover=matchMedia('(hover:hover)').matches;
document.addEventListener('mousemove',e=>{if(!canHover||pin)return;
 const t=e.target.closest?e.target.closest('.hasdoc'):null;
 if(t)show(t.dataset.doc,e.clientX,e.clientY);else hide();});
document.addEventListener('click',e=>{
 const t=e.target.closest?e.target.closest('.hasdoc'):null;
 if(t&&!t.closest('a')){
  if(pin===t.dataset.doc){hide();}
  else{pin=t.dataset.doc;show(pin,e.clientX,e.clientY);}
  e.stopPropagation();}
 else if(!e.target.closest('#tip'))hide();});
EOF

sub logo_svg {                                # html --logo FILE (default: the kit's assets/logo.svg if present) -> inline <svg> or ''
    my $file = shift;
    if (!defined $file) { (my $d = __FILE__) =~ s{[/\\][^/\\]+$}{}; $file = "$d/../../assets/logo.svg"; return '' unless -f $file }
    open my $fh, '<', $file or die "cannot read logo $file: $!\n";
    local $/; my $x = <$fh>; close $fh;
    return '' unless $x =~ m{<svg[^>]*viewBox="([^"]+)"[^>]*>(.*)</svg>}s;
    my ($vb, $body) = ($1, $2); $body =~ s/\s+/ /g; $body =~ s/ opacity="1\.000000"//g; $body =~ s/(\d+\.\d{2})\d+/$1/g;
    qq{<svg class="logo" viewBox="$vb" role="img" aria-label="logo">$body</svg>};
}
sub cmd_html {
    my $files = shift;
    my $logo;
    for (my $i = 0; $i < @$files; $i++) { if ($files->[$i] eq '--logo') { (undef, $logo) = splice @$files, $i, 2; last } }
    my @diags;
    my ($models, $letters, $rows) = load_project($files, \@diags);
    my ($errs) = emit_diags(\@diags, \*STDERR);
    return 1 if $errs;
    my @plates = all_plates($models);
    my %pageof;
    $pageof{ plate_id($plates[$_][0], $plates[$_][1]) } = $_ + 2 for 0 .. $#plates;
    my (%docs, @dk);
    my $setdoc = sub { my ($k, $v) = @_; push @dk, $k unless exists $docs{$k}; $docs{$k} = $v };
    for my $t (@$models) {
        for my $el ($t, descendants($t)) {
            $setdoc->(dkey($t, $el), doc_html($el)) if @{ $el->{doc} };
            for my $p (@{ $el->{ports} }) {
                $setdoc->(dkey($t, $p), doc_html($p)) if @{ $p->{doc} };
            }
        }
    }
    my @out = ("<!doctype html><meta charset='utf-8'>"
        . "<meta name='viewport' content='width=device-width,"
        . "initial-scale=1'><title>IDEF0 drawing set</title>"
        . "<style>$HTML_CSS</style>");
    push @out, "<h1 id='top'>" . logo_svg($logo) . 'IDEF0 drawing set &mdash; p.1: node index and '
        . 'interface table</h1>';
    push @out, "<div class='p1'>";
    push @out, '<table><caption>Node index</caption><tr><th>NODE</th><th>TITLE</th><th>NUMBER</th></tr>';
    for my $i (0 .. $#plates) {
        my ($t, $node) = @{ $plates[$i] };
        my $pid = plate_id($t, $node);
        my $k = dkey($t, $node);
        my $cls = exists $docs{$k} ? " class='hasdoc' data-doc='$k'" : '';
        push @out, "<tr><td><a href='#plate-$pid'>$pid</a></td>"
            . "<td$cls>" . esc($node->{name}) . '</td>'
            . "<td><a href='#plate-$pid'>p." . ($i + 2) . '</a></td></tr>';
    }
    push @out, '</table>';
    push @out, '<table><caption>Interface table</caption><tr><th>SOURCE</th><th>DEST</th><th>FLOW</th></tr>';
    for my $r (@$rows) {
        my ($s, $d, $name) = @$r;
        my $sp = plate_of_port($s, \%pageof);
        my $dp = plate_of_port($d, \%pageof);
        my $sc = defined $sp ? "<a href='#plate-$sp'>$s->{node_id}</a>" : $s->{node_id};
        my $dc = defined $dp ? "<a href='#plate-$dp'>$d->{node_id}</a>" : $d->{node_id};
        push @out, "<tr><td>$sc</td><td>$dc</td><td>" . esc($name) . '</td></tr>';
    }
    push @out, '</table>';
    push @out, "</div>";
    for my $i (0 .. $#plates) {
        my ($t, $node, $boxes) = @{ $plates[$i] };
        my $pid = plate_id($t, $node);
        push @out, "<div class='plate' id='plate-$pid'>";
        my @nav = ("<a href='#top'>&#8962; index</a>");
        if ($node->{tag} eq 'a') {
            my $par = $node->{parent};
            my $up = $par->{tag} eq 'a' ? $par->{node_id} : "$par->{letter}0";
            push @nav, "<a href='#plate-$up'>&#8593; $up</a>";
        } else {
            push @nav, "<span class='dim'>top plate</span>";
        }
        push @nav, "<a href='javascript:history.back()'>&#8592; back</a>";
        push @nav, "<a href='javascript:history.forward()'>fwd &#8594;</a>";
        push @nav, "<span class='dim'>$pid &middot; p." . ($i + 2) . '</span>';
        my $zoom = "<span class='zoom'><a href='#' class='fit on' onclick='return zoom(0)'>fit</a> &middot; "
            . "<a href='#' class='one' onclick='return zoom(1)'>1:1</a></span>";
        push @out, "<div class='nav'>$zoom" . join(' &middot; ', @nav) . '</div>';
        if (@{ $node->{doc} }) {
            push @out, "<details class='notes'><summary>notes: "
                . esc($node->{name}) . '</summary>' . doc_html($node) . '</details>';
        }
        push @out, svg_plate($t, $node, $boxes, $i + 2, 1);
        push @out, '</div>';
    }
    my $payload = '{' . join(', ', map { pyjson_str($_) . ': ' . pyjson_str($docs{$_}) } @dk) . '}';
    $payload =~ s{</}{<\\/}g;
    push @out, "<div id='tip'></div><script>const DOCS=$payload;\n" . $HTML_JS . '</script>';
    print join("\n", @out), "\n";
    0;
}

# ------------------------------------------------------------- fmt
sub cmd_fmt {
    my ($mode, $write, $files) = @_;
    my @diags;
    my ($models, $letters, $rows, $doc) = load_project($files, \@diags, 0);
    my ($errs) = emit_diags(\@diags, \*STDERR);
    if ($errs) {
        print STDERR "fmt: refusing to rewrite files with errors\n";
        return 1;
    }
    for my $f (@$files) {
        my @lines;
        for my $r (@{ $doc->{$f} }) {
            my ($kind, $raw, $node) = @$r;
            if ($kind eq 'raw' || !defined $node) { push @lines, $raw; next }
            my $sfx;
            if (defined $mode && $mode eq 'number') {
                $sfx = $node->{tag} eq 't' ? $node->{letter} : $node->{number};
            } elsif (defined $mode && $mode eq 'auto') {
                $sfx = '#';
            } else {
                $sfx = $node->{suffix} ne '' ? $node->{suffix} : '#';
            }
            my $line = (' ' x $node->{indent}) . $node->{tag} . $sfx . ' ' . $node->{name};
            $line .= " $node->{link_dir} " . join('|', @{ $node->{link_path} }) if has_link($node);
            $line .= '  ' . $node->{trail} if defined $node->{trail};
            push @lines, $line;
        }
        my $text = join("\n", @lines) . "\n";
        if ($write) {
            open my $fh, '>:raw', $f or die "idef0: cannot write $f: $!\n";
            print {$fh} encode('UTF-8', $text);
            close $fh;
        } else {
            print "==> $f <==\n" if @$files > 1;
            print $text;
        }
    }
    print 'fmt: rewrote ' . scalar(@$files) . ' file(s) [' . ($mode // 'normalize') . "]\n" if $write;
    0;
}

# ------------------------------------------------------------- main
sub main {
    my @argv = @_;
    if (!@argv) { print $USAGE, "\n"; return 2 }
    my ($cmd, @args) = @argv;
    return cmd_lint(\@args)  if $cmd eq 'lint';
    return cmd_dump(\@args)  if $cmd eq 'dump';
    return cmd_links(\@args) if $cmd eq 'links';
    return cmd_text(\@args)  if $cmd eq 'text';
    return cmd_html(\@args)  if $cmd eq 'html';
    if ($cmd eq 'svg') {
        if (!@args) { print STDERR "usage: idef0 svg NODE FILE...\n"; return 2 }
        my $n = shift @args;
        return cmd_svg($n, \@args);
    }
    if ($cmd eq 'fmt') {
        my ($mode, $write, @files);
        for my $a (@args) {
            if    ($a eq '--number') { $mode = 'number' }
            elsif ($a eq '--auto')   { $mode = 'auto' }
            elsif ($a eq '--write')  { $write = 1 }
            else                     { push @files, $a }
        }
        return cmd_fmt($mode, $write, \@files);
    }
    print STDERR 'idef0: unknown command ' . pyrepr($cmd) . "\n";
    print $USAGE, "\n";
    2;
}

exit main(@ARGV);
