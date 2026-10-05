#!/usr/bin/perl
# svg2tk.pl -- turn an SVG written by the kit's SysML drawers (sysml-*-svg.pl) into a Tcl list of drawing primitives
# for bin/sysml-view.tcl. Tk 8.6 (the Tk in Git for Windows) cannot show SVG, so the viewer draws these on a canvas.
# Core Perl only.
#
#   perl tools/sysml/views/svg2tk.pl FILE.svg > FILE.tk
#
# Handles what the drawers emit, not SVG in general: <svg> size, <g> (fill, font-size, translate) with an optional
# <title> naming the element, <rect>, <line>, <path> (M L H V C h v z, cubic curves sampled), <text>; dashes and
# end arrows. Output, one Tcl list per line:
#   size W H
#   rect  x0 y0 x1 y1 fill outline width dash group
#   line  {x y x y ...} colour width dash arrow group       (arrow: last | none)
#   poly  {x y x y ...} fill outline width group
#   text  x y anchor font-size weight slant colour group {string}
#   title group {element title}
# Colours "" mean none. Exit 2 when the file is not an SVG this tool knows.
use strict;
use warnings;

my $file = shift or die "usage: perl svg2tk.pl FILE.svg\n";
open my $fh, '<:encoding(UTF-8)', $file or die "svg2tk: cannot read $file: $!\n";
my $svg = do { local $/; <$fh> }; close $fh;
$svg =~ /<svg\b([^>]*)>/ or do { print STDERR "svg2tk: $file: no <svg> element\n"; exit 2 };
binmode STDOUT, ':encoding(UTF-8)';

sub attrs { my $s = shift; my %a; $a{$1} = $2 while $s =~ /([\w:-]+)="([^"]*)"/g; \%a }
sub ent   { my $t = shift; $t =~ s/&lt;/</g; $t =~ s/&gt;/>/g; $t =~ s/&quot;/"/g; $t =~ s/&#39;|&apos;/'/g; $t =~ s/&#(\d+);/chr $1/ge; $t =~ s/&amp;/&/g; $t }
sub tq    { my $t = shift; $t =~ s/([\\{}\[\]\$"])/\\$1/g; $t =~ s/\n/ /g; "{$t}" =~ s/^\{(.*)\}$/"$1"/r }   # a Tcl word
sub col   { my $c = shift // ''; $c eq 'none' || $c eq 'transparent' ? '' : $c }
sub dash  { my $d = shift; defined $d && $d =~ /\d/ ? '{' . join(' ', map { int($_ + 0.5) || 1 } split /[\s,]+/, $d) . '}' : '{}' }
sub fmt   { my $v = shift; $v = sprintf '%.1f', $v; $v =~ s/\.0$//; $v }

my $root = attrs($1);
my ($W, $H) = ($root->{width} // 800, $root->{height} // 600);
if (($root->{viewBox} // '') =~ /^\s*[\d.-]+[\s,]+[\d.-]+[\s,]+([\d.]+)[\s,]+([\d.]+)/) { ($W, $H) = ($1, $2) }
s/[^\d.]//g for $W, $H;
print "size ", fmt($W), " ", fmt($H), "\n";
my $font0 = $root->{'font-size'} // 12;

my @stack = ({ fill => '#000000', 'font-size' => $font0, tx => 0, ty => 0, grp => '' });
my $gid = 0;
my ($in_defs, $in_style, $in_script) = (0, 0, 0);
my %titled;                                   # groups that already got their title

# walk the tags in order
while ($svg =~ /<(\/?)([\w:]+)\b([^>]*?)(\/?)>|([^<]+)/gs) {
    my ($close, $tag, $att, $self, $txt) = ($1, $2, $3, $4, $5);
    next if defined $txt;                     # loose text is handled with its element
    if ($tag eq 'defs')   { $in_defs = !$close && !$self; next }
    if ($tag eq 'style')  { $in_style = !$close; next }
    if ($tag eq 'script') { $in_script = !$close; next }
    next if $in_defs || $in_style || $in_script;
    my $a = attrs($att // '');
    my $top = $stack[-1];
    if ($tag eq 'g') {
        if ($close) { pop @stack if @stack > 1; next }
        my %n = (%$top);
        $n{$_} = $a->{$_} for grep { defined $a->{$_} } qw(fill font-size font-weight font-style stroke);
        if (($a->{transform} // '') =~ /translate\(\s*([-\d.]+)[\s,]*([-\d.]*)\s*\)/) { $n{tx} += $1; $n{ty} += ($2 eq '' ? 0 : $2) }
        $n{grp} = 'g' . ++$gid;
        push @stack, \%n unless $self;
        next;
    }
    next if $close;
    my ($tx, $ty, $grp) = ($top->{tx}, $top->{ty}, $top->{grp} || '-');
    my $g = sub { my $k = shift; $a->{$k} // $top->{$k} };
    if ($tag eq 'title') {
        my $t = $svg =~ /\G([^<]*)<\/title>/gc ? $1 : '';
        print "title $grp ", tq(ent($t // '')), "\n" if $grp ne '-' && !$titled{$grp}++;
        next;
    }
    if ($tag eq 'rect') {
        next if ($a->{width} // '') =~ /%/;   # the white background
        my ($x, $y, $w, $h) = map { $_ // 0 } @$a{qw(x y width height)};
        print join(' ', 'rect', map({ fmt($_) } $x + $tx, $y + $ty, $x + $w + $tx, $y + $h + $ty),
            tq(col($g->('fill'))), tq(col($a->{stroke} // '')), fmt($a->{'stroke-width'} // 1), dash($a->{'stroke-dasharray'}), $grp), "\n";
        next;
    }
    if ($tag eq 'line') {
        my @p = map { fmt($_) } ($a->{x1} + $tx, $a->{y1} + $ty, $a->{x2} + $tx, $a->{y2} + $ty);
        print join(' ', 'line', "{@p}", tq(col($a->{stroke} // '#000000')), fmt($a->{'stroke-width'} // 1), dash($a->{'stroke-dasharray'}),
            ($a->{'marker-end'} ? 'last' : 'none'), $grp), "\n";
        next;
    }
    if ($tag eq 'path') {
        my @sub = path_points($a->{d} // '');
        for my $s (@sub) {
            my ($pts, $closed) = @$s;
            next if @$pts < 4;
            my @p = map { fmt($_) } map { $_ % 2 ? $pts->[$_] + $ty : $pts->[$_] + $tx } 0 .. $#$pts;
            my $fill = col($a->{fill} // ($closed ? $g->('fill') : 'none'));
            if ($closed && $fill ne '') {
                print join(' ', 'poly', "{@p}", tq($fill), tq(col($a->{stroke} // '')), fmt($a->{'stroke-width'} // 1), $grp), "\n";
            } else {
                print join(' ', 'line', "{@p}", tq(col($a->{stroke} // '#000000')), fmt($a->{'stroke-width'} // 1), dash($a->{'stroke-dasharray'}),
                    ($a->{'marker-end'} ? 'last' : 'none'), $grp), "\n";
            }
        }
        next;
    }
    if ($tag eq 'text') {
        next if $self;
        my $inner = $svg =~ /\G(.*?)<\/text>/gcs ? $1 : '';
        $inner //= '';
        $inner =~ s/<[^>]+>//g;               # tspans: keep their words
        my $anchor = { start => 'sw', middle => 's', end => 'se' }->{ $a->{'text-anchor'} // 'start' } // 'sw';
        my $size = $g->('font-size') // $font0; $size =~ s/[^\d.]//g;
        print join(' ', 'text', fmt(($a->{x} // 0) + $tx), fmt(($a->{y} // 0) + $ty + $size * 0.22), $anchor, fmt($size),
            (($g->('font-weight') // '') eq 'bold' ? 'bold' : 'normal'), (($g->('font-style') // '') eq 'italic' ? 'italic' : 'roman'),
            tq(col($g->('fill')) || '#000000'), $grp, tq(ent($inner))), "\n";
        next;
    }
}

sub path_points {                             # SVG path data -> ([ [x y x y ...], closed ], ...)
    my $d = shift;
    my @tok = $d =~ /([MLHVCZmlhvcz])|(-?\d*\.?\d+(?:e-?\d+)?)/g;
    @tok = grep { defined } @tok;
    my (@subs, $cur, $cmd, $x, $y, $sx, $sy);
    ($x, $y) = (0, 0);
    my @nums;
    my $flush = sub {
        return unless defined $cmd;
        my $rel = $cmd =~ /[a-z]/;
        my $c = uc $cmd;
        if ($c eq 'M') {
            while (@nums >= 2) {
                my ($nx, $ny) = splice @nums, 0, 2;
                ($x, $y) = $rel ? ($x + $nx, $y + $ny) : ($nx, $ny);
                if (!$cur || @{ $cur->[0] } > 2) { push @subs, $cur = [ [], 0 ] }
                @{ $cur->[0] } = ($x, $y);
                ($sx, $sy) = ($x, $y);
                $c = 'L';                     # further pairs are line-tos
            }
        } elsif ($c eq 'L') {
            while (@nums >= 2) { my ($nx, $ny) = splice @nums, 0, 2; ($x, $y) = $rel ? ($x + $nx, $y + $ny) : ($nx, $ny); push @{ $cur->[0] }, $x, $y }
        } elsif ($c eq 'H') {
            while (@nums) { my $n = shift @nums; $x = $rel ? $x + $n : $n; push @{ $cur->[0] }, $x, $y }
        } elsif ($c eq 'V') {
            while (@nums) { my $n = shift @nums; $y = $rel ? $y + $n : $n; push @{ $cur->[0] }, $x, $y }
        } elsif ($c eq 'C') {
            while (@nums >= 6) {
                my @c = splice @nums, 0, 6;
                if ($rel) { $c[$_] += ($_ % 2 ? $y : $x) for 0 .. 5 }
                my ($x0, $y0) = ($x, $y);
                for my $i (1 .. 12) {         # sample the cubic
                    my $t = $i / 12; my $u = 1 - $t;
                    push @{ $cur->[0] }, $u**3*$x0 + 3*$u*$u*$t*$c[0] + 3*$u*$t*$t*$c[2] + $t**3*$c[4],
                                         $u**3*$y0 + 3*$u*$u*$t*$c[1] + 3*$u*$t*$t*$c[3] + $t**3*$c[5];
                }
                ($x, $y) = @c[4, 5];
            }
        } elsif ($c eq 'Z') {
            if ($cur) { $cur->[1] = 1; push @{ $cur->[0] }, $sx, $sy; ($x, $y) = ($sx, $sy) }
        }
        @nums = ();
    };
    for my $t (@tok) {
        if ($t =~ /^[A-Za-z]$/) { $flush->(); $cmd = $t; $flush->() if uc $t eq 'Z' }
        else { push @nums, $t }
    }
    $flush->();
    grep { $_ && @{ $_->[0] } >= 4 } @subs;
}
