#!/usr/bin/perl
# md2memo.pl - Markdown -> military-style memo, US Letter 8.5x11, 1" margins
#
#   --font times   (default) Times-Roman 12, ragged right wrapped with AFM widths,
#                  13.8pt leading (46 lines/page), 0.25" indent per level
#   --font courier Courier 12, 10 cpi / 6 lpi (65 cols x 54 lines), 4-space indents
#   --text/--plain monospace text, 65 cols, form feeds
#
# Numbering: 1.  a.  (1)  (a)  _1_  _a_ ; continuation lines wrap to the left margin.
#
# Markdown mapping:
#   top-level paragraph        -> level 1 (1., 2., ...)
#   list right after paragraph -> its subparagraphs (a., b., ...)
#   list with no lead-in para  -> starts at level 1
#   nested list depth          -> next level down
#   *em* / **strong** / _x_    -> underlined
#   # Heading                  -> centered, uppercase
#   ## Heading (and deeper)    -> flush left, uppercase
#   ``` fenced code            -> verbatim, Courier 9 (86 cols); box drawing U+2500-257F and
#                                 blocks (full/half/shade) drawn as vector rules
#   | pipe | table |            -> 9pt ruled grid, bold header, :--: alignment, cells
#                                 wrap; columns fit to 6.5" from measured widths
#   --text keeps box chars and draws tables with them; --plain is ASCII only
#
# Classification tags (stripped from output text):
#   {S}phrase{/S}   {C}...{/}   {TS//SI/TK//NF}...{/}   {S//REL TO USA, GBR}...{/}
#   {CUI}...{/}     \{ prints a literal brace
#   Classes: U CUI C S TS.  Controls after //, separated by / ; SCI = SI TK HCS G KDK RSV.
#   Each portion (paragraph, heading, code block) is marked in the left margin with the
#   rollup of its tags plus --default: highest class, union of SCI and dissem controls,
#   REL TO = intersection (dropped if any classified portion lacks it, NF wins).
#   Banners top and bottom of every page = rollup of that page (--banner page) or doc.
#   Marking is on when any tag is present, with --mark, or with a non-U --default.
#
# Usage:
#   perl md2memo.pl in.md > out.pdf                 # PDF (default, pure Perl)
#   perl md2memo.pl --ps    in.md > out.ps          # PostScript
#   perl md2memo.pl --text  in.md > out.txt         # text, overstrike underline
#   perl md2memo.pl --plain in.md > out.txt         # text, no underline
#   options: --font times|courier  --indent PTS  --mark  --default S//NF  --banner page|doc
use strict;
use warnings;
use Getopt::Long;
use open qw(:std :encoding(UTF-8));

my ($text, $plain, $ps, $mark, $default, $banner, $font, $indent)
  = (0, 0, 0, 0, 'U', 'page', 'times', undef);
GetOptions('text' => \$text, 'plain' => \$plain, 'ps' => \$ps, 'mark' => \$mark,
           'default=s' => \$default, 'banner=s' => \$banner, 'font=s' => \$font,
           'indent=f' => \$indent)
  or die "usage: md2memo.pl [--ps|--text|--plain] [--font times|courier] [--indent PTS]\n"
       . "                  [--mark] [--default CLS] [--banner page|doc] [file.md]\n";
$text = 1 if $plain;
die "--banner must be page or doc\n"     unless $banner =~ /^(?:page|doc)$/;
die "--font must be times or courier\n" unless $font   =~ /^(?:times|courier)$/;

# ---------------------------------------------------------------- font metrics
my @W_TR = (   # Times-Roman, WinAnsi, 1/1000 em
    0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
    0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
    250,333,408,500,500,833,778,180,333,333,500,564,250,333,250,278,
    500,500,500,500,500,500,500,500,500,500,278,278,564,564,564,444,
    921,722,667,667,722,611,556,722,722,333,389,722,611,889,722,722,
    556,722,667,556,611,722,722,944,722,722,611,333,278,333,469,500,
    333,444,500,444,500,444,333,500,500,278,278,500,278,778,500,500,
    500,500,333,389,278,500,500,722,500,500,444,480,200,480,541,761,
    500,444,333,500,444,1000,500,500,333,1000,556,333,889,444,611,444,
    444,333,333,444,444,350,500,1000,333,980,389,333,722,444,444,722,
    250,333,500,500,500,500,200,500,333,760,276,500,564,333,760,333,
    400,564,300,300,333,500,453,250,333,300,310,500,750,750,750,444,
    722,722,722,722,722,722,889,667,611,611,611,611,333,333,333,333,
    722,722,722,722,722,722,722,564,722,722,722,722,722,722,556,500,
    444,444,444,444,444,444,667,444,444,444,444,444,278,278,278,278,
    500,500,500,500,500,500,500,564,500,500,500,500,500,500,500,500,
);
my @W_TB = (   # Times-Bold, WinAnsi, 1/1000 em
    0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
    0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
    250,333,555,500,500,1000,833,278,333,333,500,570,250,333,250,278,
    500,500,500,500,500,500,500,500,500,500,333,333,570,570,570,500,
    930,722,667,722,722,667,611,778,778,389,500,778,667,944,722,778,
    611,778,722,556,667,722,722,1000,722,722,667,333,278,333,581,500,
    333,500,556,444,556,444,333,500,556,278,333,556,278,833,556,500,
    556,556,444,389,333,556,500,722,500,500,444,394,220,394,520,761,
    500,500,333,500,500,1000,500,500,333,1000,556,333,1000,500,667,500,
    500,333,333,500,500,350,500,1000,333,1000,389,333,722,500,444,722,
    250,333,500,500,500,500,220,500,333,747,300,500,570,333,747,333,
    400,570,300,300,333,556,540,250,333,300,330,500,750,750,750,500,
    722,722,722,722,722,722,1000,722,667,667,667,667,389,389,389,389,
    722,722,778,778,778,778,778,570,778,722,722,722,722,722,611,556,
    500,500,500,500,500,500,722,444,444,444,444,444,278,278,278,278,
    500,556,500,500,500,500,500,570,500,556,556,556,556,500,556,500,
);
my @W_CO = (600) x 256;

# font slots: 1 body, 2 bold (banners), 3 code
my @FN = (undef, ($font eq 'times' ? ('Times-Roman', 'Times-Bold') : ('Courier', 'Courier-Bold')), 'Courier');
my @FW = (undef, ($font eq 'times' ? (\@W_TR, \@W_TB) : (\@W_CO, \@W_CO)), \@W_CO);

# W = line width, IND = indent per level, LEAD = line pitch, ROWS = lines per page
my ($W, $IND, $LEAD, $ROWS);
if    ($text)              { ($W, $IND, $LEAD, $ROWS) = (65,  4,    1,    54) }   # characters
elsif ($font eq 'courier') { ($W, $IND, $LEAD, $ROWS) = (468, 28.8, 12,   54) }   # points
else                       { ($W, $IND, $LEAD, $ROWS) = (468, 18,   13.8, 46) }
$IND = $indent if defined $indent && !$text;

sub sw {                                   # width of string in font slot $f at size $sz
    my ($f, $sz, $s) = @_;
    $s =~ tr/\x01\x02//d;
    return length $s if $text;
    my $w = 0;
    $w += (ord($_) > 255 ? 600 : $FW[$f][ord $_]) for split //, $s;
    $w * $sz / 1000;
}
sub wid { sw(1, 12, shift) }
my $SPW = wid(' ');
my $DSC = $font eq 'times' ? 3.8 : 3;      # rule offset below baseline; cell = [y-DSC, y+LEAD-DSC]

# tables and code blocks (drawings) are set smaller
my $SZ  = 9;                               # point size
my $LS  = $text ? 1 : $LEAD * $SZ / 12;    # their line pitch (10.35 Times, 9 Courier)
my $DSS = $DSC * $SZ / 12;                 # their rule offset below baseline
my $CW  = 0.6 * $SZ;                       # Courier cell width (5.4pt)
my $CCOLS = $text ? 0 : int($W / $CW + 1e-6);   # 86 code columns in 6.5"

# ---------------------------------------------------------------- box drawing (U+2500..U+259F)
# %BOX{cp} = [up, down, left, right] weights: 0 none, 1 light, 2 heavy, 3 double; or {diag=>1|2|3}
use charnames ();
my %BOX;
for my $cp (0x2500 .. 0x257F) {
    my $nm = charnames::viacode($cp) // next;
    $nm =~ s/^BOX DRAWINGS //;
    if ($nm =~ /DIAGONAL/) {
        $BOX{$cp} = { diag => ($nm =~ /CROSS/ ? 3 : $nm =~ /UPPER RIGHT/ ? 1 : 2) };
        next;
    }
    $nm =~ s/\b(?:DOUBLE|TRIPLE|QUADRUPLE) DASH\b//g;
    $nm =~ s/\bARC\b//g;
    my %Wt = (LIGHT => 1, SINGLE => 1, HEAVY => 2, DOUBLE => 3);
    my %Dr = (UP => [0], DOWN => [1], LEFT => [2], RIGHT => [3], HORIZONTAL => [2, 3], VERTICAL => [0, 1]);
    my @a = (0, 0, 0, 0);
    my ($pw, $last, @pend) = (undef, '');
    for my $tok (split ' ', $nm) {
        if    ($Dr{$tok}) { push @pend, @{ $Dr{$tok} }; $last = 'd' }
        elsif ($Wt{$tok}) {
            if ($last eq 'd') { $a[$_] = $Wt{$tok} for @pend; @pend = () }    # "UP HEAVY"
            else              { $pw = $Wt{$tok} }                             # "HEAVY UP"
            $last = 'w';
        }
        elsif ($tok eq 'AND') { if (@pend && $pw) { $a[$_] = $pw for @pend; @pend = () } $last = 'a' }
    }
    $a[$_] = $pw // 1 for @pend;
    $BOX{$cp} = \@a if grep { $_ } @a;
}
my %BLK = (0x2588 => [0, 0, 1, 1, 0], 0x2580 => [0, .5, 1, .5, 0], 0x2584 => [0, 0, 1, .5, 0],
           0x258C => [0, 0, .5, 1, 0], 0x2590 => [.5, 0, .5, 1, 0],
           0x2591 => [0, 0, 1, 1, .75], 0x2592 => [0, 0, 1, 1, .5], 0x2593 => [0, 0, 1, 1, .25]);

my %SHP = (0x25B6 => ['r', 1], 0x25B8 => ['r', .6], 0x25C0 => ['l', 1], 0x25C2 => ['l', .6],   # triangles
           0x25B2 => ['u', 1], 0x25B4 => ['u', .6], 0x25BC => ['d', 1], 0x25BE => ['d', .6],
           0x2192 => ['r', 0], 0x2190 => ['l', 0], 0x2191 => ['u', 0], 0x2193 => ['d', 0]);     # arrows
my $GLYPH = qr/[\x{2500}-\x{259F}\x{2190}-\x{2193}\x{25B2}-\x{25C2}]/;
sub isglyph { my $o = shift; ($o >= 0x2500 && $o <= 0x259F) || exists $SHP{$o} }

sub asciibox {
    my $cp = shift;
    my $b = $BOX{$cp};
    return '#' if $BLK{$cp};
    return { r => '>', l => '<', u => '^', d => 'v' }->{ $SHP{$cp}[0] } if $SHP{$cp};
    return '?' unless $b;
    return ('/', '\\', 'X')[ $b->{diag} - 1 ] if ref $b eq 'HASH';
    my ($u, $d, $l, $r) = @$b;
    return ($l == 3 || $r == 3) ? '=' : '-' if ($l || $r) && !$u && !$d;
    return '|' if ($u || $d) && !$l && !$r;
    '+';
}

# ---------------------------------------------------------------- classification
my @SHORT = qw(U CUI C S TS);
my @LONG  = ('UNCLASSIFIED', 'CUI', 'CONFIDENTIAL', 'SECRET', 'TOP SECRET');
my %RANK;  @RANK{@SHORT} = 0 .. $#SHORT;
my %SCI   = map { $_ => 1 } qw(SI TK HCS G KDK RSV);
my %DLONG = (NF => 'NOFORN', OC => 'ORCON', IMC => 'IMCON', PR => 'PROPIN');
my $TAG   = qr{(?<!\\)\{((?:TS|S|C|CUI|U)(?://[^{}]*)?)\}};
my $END   = qr{(?<!\\)\{/[^{}]*\}};

sub tagparse {
    my ($cls, @grp) = split m{//}, uc shift;
    die "bad classification '$cls'\n" unless defined $cls && exists $RANK{$cls};
    my $m = { r => $RANK{$cls}, sci => {}, dis => {}, rel => undef };
    for my $tok (map { split m{/} } @grp) {
        $tok =~ s/^\s+|\s+$//g;
        next unless length $tok;
        if    ($tok =~ /^REL TO\s+(.*)/) { $m->{rel} = { map { $_ => 1 } split /\s*,\s*/, $1 } }
        elsif ($SCI{$tok})               { $m->{sci}{$tok} = 1 }
        else                             { $m->{dis}{$tok} = 1 }
    }
    $m;
}

sub rollup {
    my $o = { r => 0, sci => {}, dis => {}, rel => undef };
    my ($relok, $first, %rel) = (1, 1);
    for my $m (@_) {
        $o->{r} = $m->{r} if $m->{r} > $o->{r};
        $o->{sci}{$_} = 1 for keys %{ $m->{sci} };
        $o->{dis}{$_} = 1 for keys %{ $m->{dis} };
        next if $m->{r} < $RANK{C};
        if (!$m->{rel}) { $relok = 0; next }
        if ($first) { %rel = %{ $m->{rel} }; $first = 0 }
        else        { delete $rel{$_} for grep { !$m->{rel}{$_} } keys %rel }
    }
    if ($relok && !$first && !$o->{dis}{NF}) {
        if (grep { $_ ne 'USA' } keys %rel) { $o->{rel} = \%rel }
        else                                { $o->{dis}{NF} = 1 }
    }
    $o;
}

sub fmt {
    my ($m, $long) = @_;
    my @g = ($long ? $LONG[$m->{r}] : $SHORT[$m->{r}]);
    my @sci = sort keys %{ $m->{sci} };
    push @g, join '/', @sci if @sci;
    my @dis = map { $long ? ($DLONG{$_} // $_) : $_ } sort keys %{ $m->{dis} };
    if ($m->{rel}) {
        my @c = sort { ($a ne 'USA') <=> ($b ne 'USA') || $a cmp $b } keys %{ $m->{rel} };
        push @dis, 'REL TO ' . join ', ', @c;
    }
    push @g, join '/', @dis if @dis;
    join '//', @g;
}

my $DEF = tagparse($default);

sub portion {
    my $t = shift;
    my @m = ($DEF, map { tagparse($_) } $t =~ /$TAG/g);
    $t =~ s/$TAG|$END//g;
    ($t, rollup(@m));
}

# ---------------------------------------------------------------- output lines
# @out: { t => text (\x01..\x02 = underline), x => first-line offset, m => margin marking,
#         c => portion marking, pad => 1 for spacer rows, code => 1 for Courier rows }
my @out;
my @cnt = (0) x 32;
my $have_para = 0;
my $marking = 0;
my ($CM, $CMS);
my ($need, $got) = (0, 0);

sub mwrap {                                # long margin marking -> lines <= 63pt at 8pt
    my $s = shift;
    my (@l, $cur) = ();
    $cur = '';
    for my $t (split m{(?<=/)(?!/)|(?<=, )}, $s) {
        if (length $cur && sw(1, 8, $cur . $t) > 63) { push @l, $cur; $cur = '' }
        $cur .= $t;
    }
    push @l, $cur if length $cur;
    s/\s+\z// for @l;
    @l;
}
sub mrows { my $s = shift; ($text || sw(1, 12, $s) <= 63) ? 1 : scalar(mwrap($s)) }
sub mlab  { '(' . fmt($CM, 0) . ')' }
sub pad   { push @out, { t => '', x => 0, m => '', c => $CM, pad => 1, h => $need - $got } if $need - $got > 1e-6;
            ($need, $got) = (0, 0) }
sub pushl { my ($t, $x, $code) = @_;
            my $h = $code ? $LS : $LEAD;
            push @out, { t => $t, x => $x // 0, m => ($CMS ? mlab() : ''), c => $CM, code => $code, h => $h };
            $CMS = 0; $got += $h }
sub isblank { $_[0]{t} eq '' && !$_[0]{pad} && !$_[0]{tbl} }
sub blank { pad(); push @out, { t => '', x => 0, m => '', c => undef, h => $LEAD } if @out && !isblank($out[-1]) }
sub start_portion { pad(); $CM = shift; $CMS = $marking; $need = $marking ? mrows(mlab()) * $LEAD : 0 }

sub inline {
    local $_ = shift;
    s/\\([\\`*_{}\[\]()#+\-.!>])/"\x03".ord($1)."\x04"/ge;
    s/`([^`]*)`/$1/g;
    s/!\[([^\]]*)\]\([^)]*\)/$1/g;
    s/\[([^\]]*)\]\(([^)\s]*)[^)]*\)/$1 <$2>/g;
    s/(\*\*|__)(?=\S)(.+?)(?<=\S)\1/\x01$2\x02/g;
    s/(?<![\w*])([*_])(?=\S)(.+?)(?<=\S)\1(?![\w*])/\x01$2\x02/g;
    s/\x03(\d+)\x04/chr($1)/ge;
    s/($GLYPH)/asciibox(ord $1)/ge if !$text || $plain;
    $_;
}

sub hardsplit {                            # break an over-long word to fit $avail
    my ($w, $avail) = @_;
    my (@c, $cur) = ();
    $cur = '';
    for my $ch (split //, $w) {
        if (length $cur && $ch !~ /[\x01\x02]/ && wid($cur . $ch) > $avail) { push @c, $cur; $cur = '' }
        $cur .= $ch;
    }
    push @c, $cur;
    @c;
}

# ragged-right fill: first line at offset $x0 starting with $prefix, rest at the margin
sub emit {
    my ($x0, $prefix, $body) = @_;
    my ($x, $line, $len, $fresh) = ($x0, $prefix, wid($prefix), 1);
    for my $w (split ' ', $body) {
        my $ww = wid($w);
        if (!$fresh && $x + $len + $SPW + $ww > $W + 1e-6) {
            pushl($line, $x); ($x, $line, $len, $fresh) = (0, '', 0, 1);
        }
        if ($x + $len + $ww > $W + 1e-6) {
            if ($len) { pushl($line, $x); ($x, $line, $len) = (0, '', 0) }
            my @c = hardsplit($w, $W);
            pushl($_, 0) for @c[0 .. $#c - 1];
            $w = $c[-1]; $ww = wid($w);
        }
        $line .= ($fresh ? '' : ' ') . $w;
        $len  += ($fresh ? 0 : $SPW) + $ww;
        $fresh = 0;
    }
    pushl($line, $x);
}

sub label {
    my ($L, $n) = @_;
    my $a = chr(ord('a') + ($n - 1) % 26);
    ("$n.", "$a.", "($n)", "($a)", "\x01$n\x02", "\x01$a\x02")[($L - 1) % 6];
}

sub numbered {
    my ($L, $t) = @_;
    my ($s, $m) = portion($t);
    $cnt[$L]++;
    $cnt[$_] = 0 for $L + 1 .. $#cnt;
    blank();
    start_portion($m);
    emit($IND * ($L - 1), label($L, $cnt[$L]) . '  ', inline($s));
}

sub heading {
    my ($n, $t) = @_;
    my ($s, $m) = portion($t);
    $s = uc inline($s);
    blank();
    start_portion($m);
    my $w = wid($s);
    if ($n == 1 && $w <= $W) { pushl($s, $text ? int(($W - $w) / 2) : ($W - $w) / 2) }
    else                     { emit(0, '', $s) }
}

sub codeblock {
    my ($s, $m) = portion(join "\n", @_);
    start_portion($m);
    for my $c (split /\n/, $s, -1) {
        $c =~ s/\\([{}])/$1/g;
        if ($text) { pushl($c, 0, 1); next }                   # text: no cut
        do { pushl(substr($c, 0, $CCOLS, ''), 0, 1) } while length $c;
    }
}

# ---------------------------------------------------------------- parse
my @in = <>;
$marking = ($mark || uc($default) ne 'U' || grep { /$TAG/ } @in) ? 1 : 0;

my %ASC = ("\x{2018}" => "'", "\x{2019}" => "'", "\x{201C}" => '"', "\x{201D}" => '"',
           "\x{2013}" => '-', "\x{2014}" => '--', "\x{2026}" => '...', "\x{2022}" => '*');
my %WIN = ("\x{2018}" => "\x91", "\x{2019}" => "\x92", "\x{201C}" => "\x93", "\x{201D}" => "\x94",
           "\x{2013}" => "\x96", "\x{2014}" => "\x97", "\x{2026}" => "\x85", "\x{2022}" => "\x95");
my $MAP = $text ? \%ASC : \%WIN;           # PDF/PS keep typographic quotes and dashes (WinAnsi)

sub norm {
    my $c = shift;
    my $o = ord $c;
    return $plain ? asciibox($o) : $c if isglyph($o);         # box drawing, blocks, arrows
    $MAP->{$c} // (($o >= 0xA0 && $o <= 0xFF) ? $c : '?');
}

# ---------------------------------------------------------------- tables
sub tcells {
    my $s = shift;
    $s =~ s/^\s*\|//; $s =~ s/(?<!\\)\|\s*$//;
    map { s/^\s+|\s+$//g; s/\\\|/|/g; $_ } split /(?<!\\)\|/, $s, -1;
}
sub isdelim { $_[0] =~ /^\s*\|?\s*:?-+:?\s*(?:\|\s*:?-+:?\s*)*\|?\s*$/ && $_[0] =~ /[|-]/ }

sub cellwrap {                             # wrap cell text to $avail in font $f; balance underlines
    my ($f, $s, $avail) = @_;
    my $mw = sub { sw($f, $SZ, shift) };
    my $sp = $mw->(' ');
    my (@l, $line, $len) = ();
    ($line, $len) = ('', 0);
    for my $w (split ' ', $s) {
        my $ww = $mw->($w);
        if (length $line && $len + $sp + $ww > $avail + 1e-6) { push @l, $line; ($line, $len) = ('', 0) }
        if ($ww > $avail + 1e-6) {
            my $cur = '';
            for my $ch (split //, $w) {
                if (length $cur && $ch !~ /[\x01\x02]/ && $mw->($cur . $ch) > $avail) { push @l, $cur; $cur = '' }
                $cur .= $ch;
            }
            $w = $cur; $ww = $mw->($w);
        }
        $line .= (length $line ? ' ' : '') . $w;
        $len  += (length($line) > length($w) ? $sp : 0) + $ww;
    }
    push @l, $line;
    my $open = 0;
    for (@l) {
        $_ = "\x01$_" if $open;
        for my $c (/[\x01\x02]/g) { $open = $c eq "\x01" }
        $_ .= "\x02" if $open;
    }
    \@l;
}

sub colfit {                               # water-fill: narrow columns keep natural width,
    my ($nat, $min, $avail) = @_;          # wide ones share the rest, never below longest word
    my ($sn, $sm) = (0, 0);
    $sn += $_ for @$nat; $sm += $_ for @$min;
    return [@$nat] if $sn <= $avail;
    return [ map { $_ * $avail / $sm } @$min ] if $sm >= $avail;
    my %fix;
    while (1) {
        my @u = grep { !exists $fix{$_} } 0 .. $#$nat;
        last unless @u;
        my $rem = $avail; $rem -= $_ for values %fix;
        my $fair = $rem / @u;
        my @f = grep { $nat->[$_] <= $fair } @u;
        @f = grep { $min->[$_] >= $fair } @u unless @f;
        last unless @f;
        $fix{$_} = $nat->[$_] <= $fair ? $nat->[$_] : $min->[$_] for @f;
    }
    my @u = grep { !exists $fix{$_} } 0 .. $#$nat;
    my $rem = $avail; $rem -= $_ for values %fix;
    [ map { exists $fix{$_} ? $fix{$_} : $rem / @u } 0 .. $#$nat ];
}

sub table {
    my @rows = @_;                         # raw lines: header, delimiter, body...
    my @hdr   = tcells(shift @rows);
    my @align = map { /^:-+:$/ ? 'c' : /-:$/ ? 'r' : 'l' } tcells(shift @rows);
    my $nc = @hdr;
    my @raw = ([@hdr], map { [ (tcells($_))[0 .. $nc - 1] ] } @rows);
    my ($s, $m) = portion(join ' ', map { $_ // '' } map { @$_ } @raw);
    my @cell = map { [ map { inline((portion($_ // ''))[0]) } @$_ ] } @raw;

    blank();
    start_portion($m);
    my $pad = $text ? 1 : 3;
    my $avail = $W - ($text ? 3 * $nc + 1 : 2 * $pad * $nc);
    my (@nat, @min);
    for my $c (0 .. $nc - 1) {
        for my $r (0 .. $#cell) {
            my $f = $r ? 1 : 2;
            my $t = $cell[$r][$c];
            my $n = sw($f, $SZ, $t);
            $nat[$c] = $n if !defined $nat[$c] || $n > $nat[$c];
            for (split ' ', $t) { my $w = sw($f, $SZ, $_); $min[$c] = $w if !defined $min[$c] || $w > $min[$c] }
        }
        $min[$c] = ($text ? 1 : 6) if !$min[$c];
        $nat[$c] = $min[$c] if $nat[$c] < $min[$c];
    }
    my $w = colfit(\@nat, \@min, $avail);
    @$w = map { int } @$w if $text;
    $_ = $_ < 1 ? 1 : $_ for @$w;
    my @lines = map { my $r = $_; [ map { cellwrap($r ? 1 : 2, $cell[$r][$_], $w->[$_]) } 0 .. $nc - 1 ] } 0 .. $#cell;

    if ($text) {                           # character table
        my @B = $plain ? qw(- | + + + + + + + + + = + + +)
                       : ("\x{2500}", "\x{2502}", "\x{250C}", "\x{252C}", "\x{2510}", "\x{251C}", "\x{253C}",
                          "\x{2524}", "\x{2514}", "\x{2534}", "\x{2518}", "\x{2550}", "\x{255E}", "\x{256A}", "\x{2561}");
        my $rule = sub { my ($h, $a, $b, $c) = @_; $a . join($b, map { $h x ($_ + 2) } @$w) . $c };
        pushl($rule->(@B[0, 2, 3, 4]), 0, 1);
        for my $r (0 .. $#lines) {
            my $n = 0; for (@{ $lines[$r] }) { $n = @$_ if @$_ > $n }
            for my $k (0 .. $n - 1) {
                my @c;
                for my $c (0 .. $nc - 1) {
                    my $t = $lines[$r][$c][$k] // '';
                    my $sp = $w->[$c] - wid($t);
                    my $lft = $align[$c] eq 'r' ? $sp : $align[$c] eq 'c' ? int($sp / 2) : 0;
                    push @c, ' ' . (' ' x $lft) . $t . (' ' x ($sp - $lft)) . ' ';
                }
                pushl($B[1] . join($B[1], @c) . $B[1], 0, 1);
            }
            pushl($r == $#lines ? $rule->(@B[0, 8, 9, 10]) : $r == 0 ? $rule->(@B[11, 12, 13, 14]) : $rule->(@B[0, 5, 6, 7]), 0, 1);
        }
        return;
    }
    my ($x, @cols) = (0);                  # ruled table for PDF/PS
    for my $c (0 .. $nc - 1) { push @cols, { x => $x, w => $w->[$c] + 2 * $pad, a => $align[$c] }; $x += $cols[-1]{w} }
    my $T = { cols => \@cols, pad => $pad, rows => [] };
    for my $r (0 .. $#lines) {
        my $n = 0; for (@{ $lines[$r] }) { $n = @$_ if @$_ > $n }
        push @{ $T->{rows} }, { cells => $lines[$r], n => $n, hdr => !$r };
        for my $k (0 .. $n - 1) {
            push @out, { t => '', x => 0, m => ($CMS ? mlab() : ''), c => $CM, tbl => $T, r => $r, k => $k, h => $LS };
            $CMS = 0; $got += $LS;
        }
    }
}

my (@para, $item, @stack, $code, @cb);

sub flush {
    if    ($item) { numbered($item->[0], join ' ', @{ $item->[1] }); undef $item }
    elsif (@para) { $have_para = 1; numbered(1, join ' ', @para); @para = () }
}

for my $i (0 .. $#in) {
    my $l = $in[$i];
    next unless defined $l;
    $l =~ s/\r?\n\z//;
    $l =~ s/\t/    /g;
    $l =~ s/([^\x00-\x7f])/norm($1)/ge;
    local $_ = $l;

    if ($code) {
        if (/^\s*```/) { $code = 0; codeblock(@cb); @cb = (); next }
        push @cb, $_; next;
    }
    if (/^\s*```/) { flush(); blank(); $code = 1; next }
    if (/\|/ && $i < $#in && isdelim($in[$i + 1])) {          # GFM pipe table
        flush();
        my @t = ($_);
        while ($i < $#in && defined $in[$i + 1] && $in[$i + 1] =~ /\|/ && $in[$i + 1] !~ /^\s*$/) {
            my $n = $in[++$i]; $in[$i] = undef;
            $n =~ s/\r?\n\z//; $n =~ s/\t/    /g; $n =~ s/([^\x00-\x7f])/norm($1)/ge;
            push @t, $n;
        }
        table(@t);
        next;
    }
    if (/^\s*$/)   { flush(); next }
    if (/^(#{1,6})\s+(.*?)\s*#*\s*$/) {
        flush(); @stack = (); $have_para = 0; heading(length $1, $2); next;
    }
    if (/^\s*([-*_])(\s*\1){2,}\s*$/) { flush(); next }
    if (/^(\s*)(?:[-*+]|\d+[.)])\s+(.*)$/) {
        flush();
        my $ind = length $1;
        pop @stack while @stack && $stack[-1] > $ind;
        push @stack, $ind unless @stack && $stack[-1] == $ind;
        $item = [ scalar(@stack) + ($have_para ? 1 : 0), [$2] ];
        next;
    }
    s/^\s+//; s/^>\s?//;
    if ($item) { push @{ $item->[1] }, $_ }
    else       { @stack = (); push @para, $_ }
}
codeblock(@cb) if $code;
flush();
pop @out while @out && isblank($out[-1]);
pad();

# ---------------------------------------------------------------- paginate + banners
my (@pages, @pg);
my ($cap, $used) = ($ROWS * $LEAD, 0);     # page height in line units
for my $l (@out) {
    next if !@pg && isblank($l);
    if ($used + $l->{h} > $cap + 1e-6) { push @pages, [@pg]; @pg = (); $used = 0; next if isblank($l) }
    push @pg, $l;
    $used += $l->{h};
}
push @pages, [@pg] if @pg;

my $docm = rollup(map { $_->{c} // () } @out);
my @bann = map {
    my $m = ($banner eq 'doc' || $docm->{r} == $RANK{CUI}) ? $docm     # CUI doc: CUI on every page
          : rollup(map { $_->{c} // () } @$_);
    $m = { %$m, r => $RANK{U} } if $m->{r} == $RANK{CUI} && $docm->{r} >= $RANK{C};   # no CUI in classified banners
    $marking ? fmt($m, 1) : '';
} @pages;

# ---------------------------------------------------------------- text out
if ($text) {
    my $G = 0;
    if ($marking) { for (@out) { $G = length($_->{m}) + 1 if length($_->{m}) + 1 > $G } }
    my $Wt = $G + $W;
    my ($ul, $pi) = (0, 0);
    for my $p (@pages) {
        print "\f" if $pi;
        my $b = $bann[$pi++];
        print ' ' x int(($Wt - length $b) / 2), "$b\n\n" if $marking;
        for my $l (@$p) {
            my $o = ($G ? sprintf("%-${G}s", $l->{m}) : '') . (' ' x $l->{x});
            for my $c (split //, $l->{t}) {
                if ($c eq "\x01") { $ul = 1; next }
                if ($c eq "\x02") { $ul = 0; next }
                $o .= ($ul && !$plain && $c ne ' ') ? "_\b$c" : $c;
            }
            $o =~ s/\s+\z//;
            print "$o\n";
        }
        print "\n", ' ' x int(($Wt - length $b) / 2), "$b\n" if $marking;
    }
    exit 0;
}

# ---------------------------------------------------------------- page layout (PS/PDF)
# items: ['T', font slot, size, x, y, string]  ['L', x1, y1, x2, y2, width]  ['R', x, y, w, h, gray]
#        ['P', gray, x1, y1, x2, y2, ...] filled polygon
sub boxitems {                             # one box-drawing/block char in a Courier cell at (x, baseline y)
    my ($cp, $x, $y) = @_;
    my ($cw, $y0) = ($CW, $y - $DSS);
    my ($cx, $cy, $top) = ($x + $cw / 2, $y0 + $LS / 2, $y0 + $LS);
    if (my $s = $SHP{$cp}) {
        my ($d, $k) = @$s;
        my %v = (r => [1, 0], l => [-1, 0], u => [0, 1], d => [0, -1]);
        my ($ux, $uy) = @{ $v{$d} };
        my ($px, $py) = (-$uy, $ux);                       # perpendicular
        if ($k) {                                          # filled triangle
            my $h = $cw / 2 * $k;
            return ['P', 0, $cx + $ux * $h, $cy + $uy * $h,
                            $cx - $ux * $h + $px * $h, $cy - $uy * $h + $py * $h,
                            $cx - $ux * $h - $px * $h, $cy - $uy * $h - $py * $h];
        }
        my $hl = $ux ? $cw / 2 : $LS / 2;                  # arrow shaft + head
        my ($tx, $ty) = ($cx + $ux * $hl, $cy + $uy * $hl);
        return (['L', $cx - $ux * $hl, $cy - $uy * $hl, $tx, $ty, 0.6],
                ['P', 0, $tx, $ty, $tx - $ux * 2.2 + $px * 1.3, $ty - $uy * 2.2 + $py * 1.3,
                                   $tx - $ux * 2.2 - $px * 1.3, $ty - $uy * 2.2 - $py * 1.3]);
    }
    if (my $k = $BLK{$cp}) { return ['R', $x + $k->[0] * $cw, $y0 + $k->[1] * $LS, $k->[2] * $cw, $k->[3] * $LS, $k->[4]] }
    my $b = $BOX{$cp} or return ();
    if (ref $b eq 'HASH') {
        my @i;
        push @i, ['L', $x + $cw, $top, $x, $y0, 0.6] if $b->{diag} & 1;
        push @i, ['L', $x, $top, $x + $cw, $y0, 0.6] if $b->{diag} & 2;
        return @i;
    }
    my @end = ([$cx, $top], [$cx, $y0], [$x, $cy], [$x + $cw, $cy]);   # up down left right
    my @i;
    for my $a (0 .. 3) {
        my $wt = $b->[$a] or next;
        my ($ex, $ey) = @{ $end[$a] };
        if ($wt < 3) { push @i, ['L', $cx, $cy, $ex, $ey, $wt == 2 ? 1.2 : 0.5]; next }
        my ($dx, $dy) = $a < 2 ? (0.9, 0) : (0, 0.9);
        push @i, ['L', $cx - $dx, $cy - $dy, $ex - $dx, $ey - $dy, 0.4],
                 ['L', $cx + $dx, $cy + $dy, $ex + $dx, $ey + $dy, 0.4];
    }
    @i;
}

sub tblline {                              # one text line of a ruled table at baseline $y
    my ($l, $y, $page, $li) = @_;
    my ($T, $r, $k) = @$l{qw(tbl r k)};
    my $row = $T->{rows}[$r];
    my ($x0, $bot, $top) = (72, $y - $DSS, $y - $DSS + $LS);
    my $x1 = $x0 + $T->{cols}[-1]{x} + $T->{cols}[-1]{w};
    my $prev = $li > 0 ? $page->[$li - 1] : undef;
    my $next = $page->[$li + 1];
    my @i;
    push @i, ['L', $x0, $top, $x1, $top, ($r == 1 && $k == 0) ? 1.2 : 0.6]
        if $k == 0 || !$prev || !$prev->{tbl} || $prev->{tbl} != $T;
    push @i, ['L', $x0, $bot, $x1, $bot, 0.6] if !$next || !$next->{tbl} || $next->{tbl} != $T;
    push @i, ['L', $x0 + $_->{x}, $bot, $x0 + $_->{x}, $top, 0.6] for @{ $T->{cols} };
    push @i, ['L', $x1, $bot, $x1, $top, 0.6];
    my $f = $row->{hdr} ? 2 : 1;
    for my $c (0 .. $#{ $T->{cols} }) {
        my $col = $T->{cols}[$c];
        my $t = $row->{cells}[$c][$k] // next;
        my $tw = sw($f, $SZ, $t);
        my $x = $x0 + $col->{x} + ($col->{a} eq 'r' ? $col->{w} - $T->{pad} - $tw
                                 : $col->{a} eq 'c' ? ($col->{w} - $tw) / 2 : $T->{pad});
        my ($txt, $cx, $start, @segs) = ('', 0);
        for my $ch (split //, $t) {
            if ($ch eq "\x01") { $start = $cx; next }
            if ($ch eq "\x02") { push @segs, [$start, $cx] if defined $start; undef $start; next }
            $txt .= $ch; $cx += $FW[$f][ord $ch] * $SZ / 1000;
        }
        push @i, ['T', $f, $SZ, $x, $y, $txt] if length $txt;
        push @i, ['L', $x + $_->[0], $y - 1.5, $x + $_->[1], $y - 1.5, 0.5] for grep { $_->[1] > $_->[0] } @segs;
    }
    @i;
}

my @draw;
{
    my ($ul, $pn) = (0, 0);
    for my $p (@pages) {
        $pn++;
        my ($top, $li, @it) = (711 - $DSC + $LEAD, 0);   # first body baseline at 711
        for my $l (@$p) {
            my $h  = $l->{h};
            my $y  = $top - $h + $h * $DSC / $LEAD;   # baseline within this line's box
            my $f  = $l->{code} ? 3 : 1;
            my $fs = $l->{code} ? $SZ : 12;
            my $x0 = 72 + $l->{x};
            my ($txt, $cx) = ('', 0);
            my $start = $ul ? 0 : undef;
            my @segs;
            if ($l->{tbl}) { push @it, tblline($l, $y, $p, $li); $li++; $top -= $h; next }
            for my $c (split //, $l->{t}) {
                if ($c eq "\x01") { $ul = 1; $start = $cx; next }
                if ($c eq "\x02") { push @segs, [$start, $cx] if defined $start; $ul = 0; undef $start; next }
                if (ord $c > 255) { push @it, boxitems(ord $c, $x0 + $cx, $y); $c = ' ' }
                $txt .= $c;
                $cx  += (ord($c) > 255 ? 600 : $FW[$f][ord $c]) * $fs / 1000;
            }
            push @segs, [$start, $cx] if $ul && defined $start;
            push @it, ['T', $f, $fs, $x0, $y, $txt] if length $txt;
            push @it, ['L', $x0 + $_->[0], $y - 2, $x0 + $_->[1], $y - 2, 0.6] for grep { $_->[1] > $_->[0] } @segs;
            if (length $l->{m}) {                      # right-aligned in the left margin
                my ($sz, @ml) = (12, $l->{m});
                if (sw(1, 12, $l->{m}) > 63) { $sz = 8; @ml = mwrap($l->{m}) }
                my $my = $y;
                for (@ml) { push @it, ['T', 1, $sz, 64.8 - sw(1, $sz, $_), $my, $_]; $my -= $LEAD }
            }
            $top -= $h;
            $li++;
        }
        if ($pn > 1) {
            my $s = "- $pn -";
            push @it, ['T', 1, 12, 306 - sw(1, 12, $s) / 2, ($marking ? 50 : 36), $s];
        }
        if ($marking) {
            my $b = $bann[$pn - 1];
            push @it, ['T', 2, 12, 306 - sw(2, 12, $b) / 2, $_, $b] for 750, 30;
        }
        push @draw, \@it;
    }
}

# ---------------------------------------------------------------- PostScript out
if ($ps) {
    sub psq { my $s = shift; $s =~ s/([\\()])/\\$1/g; $s =~ s/([^\x20-\x7e])/sprintf '\\%03o', ord $1/ge; $s }
    print "%!PS-Adobe-3.0\n%%BoundingBox: 0 0 612 792\n%%Pages: ", scalar(@draw), "\n%%EndComments\n";
    print <<"EOP";
/WinAnsi ISOLatin1Encoding 256 array copy def
WinAnsi 39 /quotesingle put WinAnsi 45 /hyphen put WinAnsi 96 /grave put
WinAnsi 16#85 /ellipsis put WinAnsi 16#91 /quoteleft put WinAnsi 16#92 /quoteright put
WinAnsi 16#93 /quotedblleft put WinAnsi 16#94 /quotedblright put WinAnsi 16#95 /bullet put
WinAnsi 16#96 /endash put WinAnsi 16#97 /emdash put
/reenc { findfont dup length dict begin { 1 index /FID ne { def } { pop pop } ifelse } forall
         /Encoding WinAnsi def currentdict end definefont pop } bind def
/F1 /$FN[1] reenc  /F2 /$FN[2] reenc  /F3 /$FN[3] reenc
%%EndProlog
EOP
    my $pn = 0;
    for my $d (@draw) {
        $pn++;
        print "%%Page: $pn $pn\n<< /PageSize [612 792] >> setpagedevice\n2 setlinecap\n";
        for (@$d) {
            my ($k, @a) = @$_;
            if ($k eq 'T') { printf "/F%d findfont %.2f scalefont setfont %.2f %.2f moveto (%s) show\n",
                                    $a[0], $a[1], $a[2], $a[3], psq($a[4]) }
            elsif ($k eq 'L') { printf "%.2f setlinewidth newpath %.2f %.2f moveto %.2f %.2f lineto stroke\n", @a[4, 0 .. 3] }
            elsif ($k eq 'R') { printf "%.2f setgray %.2f %.2f %.2f %.2f rectfill 0 setgray\n", @a[4, 0 .. 3] }
            else { my $g = shift @a; my @p = map { sprintf '%.2f', $_ } @a;
                   print "$g setgray newpath $p[0] $p[1] moveto ",
                         join(' ', map { "$p[2*$_] $p[2*$_+1] lineto" } 1 .. $#p / 2), " closepath fill 0 setgray\n" }
        }
        print "showpage\n";
    }
    print "%%EOF\n";
    exit 0;
}

# ---------------------------------------------------------------- PDF out (default)
sub pdq { my $s = shift; $s =~ s/([\\()])/\\$1/g; $s }
my (%o, @kids);
my $n = 5;
for my $d (@draw) {
    my $c = "2 J\n";
    for (@$d) {
        my ($k, @a) = @$_;
        if ($k eq 'T') { $c .= sprintf "BT /F%d %.2f Tf 1 0 0 1 %.2f %.2f Tm (%s) Tj ET\n",
                                       $a[0], $a[1], $a[2], $a[3], pdq($a[4]) }
        elsif ($k eq 'L') { $c .= sprintf "%.2f w %.2f %.2f m %.2f %.2f l S\n", @a[4, 0 .. 3] }
        elsif ($k eq 'R') { $c .= sprintf "%.2f g %.2f %.2f %.2f %.2f re f 0 g\n", @a[4, 0 .. 3] }
        else { my $g = shift @a; my @p = map { sprintf '%.2f', $_ } @a;
               $c .= "$g g $p[0] $p[1] m " . join(' ', map { "$p[2*$_] $p[2*$_+1] l" } 1 .. $#p / 2) . " h f 0 g\n" }
    }
    my $pg = ++$n;
    my $ct = ++$n;
    $o{$pg} = "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] "
            . "/Resources << /Font << /F1 3 0 R /F2 4 0 R /F3 5 0 R >> >> /Contents $ct 0 R >>";
    $o{$ct} = "<< /Length " . length($c) . " >>\nstream\n$c\nendstream";
    push @kids, "$pg 0 R";
}
$o{1} = "<< /Type /Catalog /Pages 2 0 R >>";
$o{2} = "<< /Type /Pages /Kids [@kids] /Count " . scalar(@kids) . " >>";
$o{2 + $_} = "<< /Type /Font /Subtype /Type1 /BaseFont /$FN[$_] /Encoding /WinAnsiEncoding >>" for 1 .. 3;

my $pdf = "%PDF-1.4\n";
my @off;
for my $i (1 .. $n) { $off[$i] = length $pdf; $pdf .= "$i 0 obj\n$o{$i}\nendobj\n" }
my $xref = length $pdf;
$pdf .= "xref\n0 " . ($n + 1) . "\n0000000000 65535 f \n";
$pdf .= sprintf "%010d 00000 n \n", $off[$_] for 1 .. $n;
$pdf .= "trailer\n<< /Size " . ($n + 1) . " /Root 1 0 R >>\nstartxref\n$xref\n%%EOF\n";
binmode STDOUT, ':raw';
print $pdf;
