#!/usr/bin/perl
# doors2v2.pl : port IBM DOORS (9.x classic) and DOORS Next requirement modules into SysML v2
# text: one package per module, headings as requirement groups, objects as requirements with
# their DOORS ID as short name, information objects as comments, DOORS links as satisfy /
# verify / dependency. Core Perl 5 only (Git for Windows).
#
#   perl doors2v2.pl -o DIR [--prefix P] [--marking LEVEL] [--tests MODULE]... [--keep ATTR]...
#                    [--map FIELD=COLUMN]... [--id-prefix PFX] [--no-provenance] EXPORT...
#
# EXPORT: a module exported as CSV or TSV (DOORS 9 "Export to spreadsheet", DOORS Next CSV;
# UTF-8, UTF-16 or Windows-1252), or ReqIF (.reqif, .reqifz) from DOORS 9 or DOORS Next.
# Several modules at once resolve links between them. A CSV module is named after its file
# (srs.csv -> SRS); a ReqIF file gives one module per specification.
#
#   --tests MODULE  objects of this module are tests: their verify links become verification
#                   defs (objects whose type says "test" are treated the same way)
#   --design MODULE objects of this module are design elements: satisfy links to them become
#                   satisfy relationships (between two requirements a satisfy link is a derivation)
#   --keep ATTR     carry this DOORS attribute (e.g. Priority) as @DoorsAttribute metadata
#   --map F=COL     name the column for a field: id heading text number level type
#   --id-prefix P   build IDs as P + Absolute Number when the export has no Object Identifier
#
# Columns and ReqIF attributes found by name (case-insensitive):
#   id       Object Identifier, ID, Identifier, ReqIF.ForeignID, Absolute Number
#   heading  Object Heading, Heading, ReqIF.ChapterName, Title
#   text     Object Text, Primary Text, ReqIF.Text, Text, Description
#   number   Object Number, Paragraph Number, Section Number, Number
#   level    Object Level, Level, Depth
#   type     Object Type, Requirement Type, Artifact Type, Type, Category
#   links    any column whose name contains link, satisf, verif, validat, deriv, refin, trace
# Writes DIR/model/requirements/*.sysml, DIR/model/library/DoorsSource.sysml, links and
# verification packages, DIR/ids.tsv and DIR/CONVERSION.txt.
# Exit status: 0 clean, 1 findings to finish by hand, 2 usage or input error.
use strict; use warnings;
use Getopt::Long; use File::Path qw(make_path); use File::Basename qw(basename); use Encode ();
binmode STDOUT, ':encoding(UTF-8)'; binmode STDERR, ':encoding(UTF-8)';

my %O = (prefix => '', provenance => 1, tests => [], keep => [], map => [], design => []);
GetOptions(\%O, 'o=s', 'prefix=s', 'marking=s', 'tests=s@', 'design=s@', 'keep=s@', 'map=s@', 'id-prefix=s', 'provenance!') && @ARGV && $O{o}
    or do { print STDERR "usage: perl doors2v2.pl -o DIR [--prefix P] [--marking LEVEL] [--tests MODULE]... [--keep ATTR]... [--map FIELD=COLUMN]... [--id-prefix PFX] [--no-provenance] EXPORT...\n"; exit 2 };
fail("--marking must be an identifier") if defined $O{marking} && $O{marking} !~ /^\w+$/;
my %MAP;
for (@{$O{map}}) { my ($k, $v) = split /=/, $_, 2; fail("--map needs FIELD=COLUMN with FIELD one of id heading text number level type") unless defined $v && $k =~ /^(?:id|heading|text|number|level|type)$/; $MAP{$k} = $v }
my %TESTS = map { lc($_) => 1 } @{$O{tests}};
my %DESIGN = map { lc($_) => 1 } @{$O{design}};
my %KEEP = map { lc($_) => $_ } @{$O{keep}};
sub fail { print STDERR "doors2v2: $_[0]\n"; exit 2 }

my %FIELD = (
    id      => [qr/^(?:object identifier|id|identifier|reqif\.foreignid|doors id|req(?:uirement)? ?id)$/i],
    heading => [qr/^(?:object heading|heading|reqif\.chaptername|title)$/i],
    text    => [qr/^(?:object text|primary text|reqif\.text|text|description|requirement text)$/i],
    number  => [qr/^(?:object number|paragraph number|section number|number|reqif\.chapternumber)$/i],
    level   => [qr/^(?:object level|level|depth|outline level)$/i],
    type    => [qr/^(?:object type|requirement type|artifact type|type|category|object class)$/i],
    absno   => [qr/^(?:absolute number|absno)$/i],
);
sub field_of {      # the field a column or attribute name stands for
    my $name = shift;
    for my $f (keys %MAP) { return $f if lc $MAP{$f} eq lc $name }
    for my $f (qw(id heading text number level type absno)) { next if $MAP{$f}; return $f if $name =~ $FIELD{$f}[0] }
    return 'link' if $name =~ /link|satisf|verif|validat|deriv|refin|trace/i;
    return undef;
}
sub link_kind { my $c = shift; return 'verify' if $c =~ /verif|validat|test/i; return 'satisfy' if $c =~ /satisf/i;
    return 'derive' if $c =~ /deriv/i; return 'refine' if $c =~ /refin/i; return 'trace' }

# ------------------------------------------------------------------------------------------
# Read: bytes -> text (UTF-16 / UTF-8 / cp1252), zip members, XML, CSV
# ------------------------------------------------------------------------------------------
sub slurp {
    my $f = shift;
    my $raw;
    if ($f =~ /\.reqifz$/i) { $raw = from_zip($f) }
    else { open my $h, '<:raw', $f or fail("$f: $!"); local $/; $raw = <$h> }
    my $t;
    if ($raw =~ /^\xFF\xFE/) { $t = Encode::decode('UTF-16LE', substr($raw, 2)) }
    elsif ($raw =~ /^\xFE\xFF/) { $t = Encode::decode('UTF-16BE', substr($raw, 2)) }
    elsif ($raw =~ /^(?:[^\0]\0){8}/) { $t = Encode::decode('UTF-16LE', $raw) }
    else { $t = eval { Encode::decode('UTF-8', $raw, Encode::FB_CROAK) } // Encode::decode('cp1252', $raw) }
    $t =~ s/^\x{FEFF}//; $t =~ s/\r\n?/\n/g;
    return $t;
}
sub from_zip {
    my $f = shift;
    eval { require IO::Uncompress::Unzip; 1 } or fail("$f: IO::Uncompress::Unzip is not available; unzip the file and pass the .reqif inside");
    my $z = IO::Uncompress::Unzip->new($f) or fail("$f: not a readable zip");
    my $best = '';
    for (my $s = 1; $s > 0; $s = $z->nextStream) {
        my ($data, $buf, $r) = ('');
        $data .= $buf while ($r = $z->read($buf)) > 0;
        $best = $data if $data =~ /<REQ-IF\b/ && length $data > length $best;
    }
    fail("$f: no ReqIF member found") unless length $best;
    return $best;
}
my %ENT = (lt => '<', gt => '>', amp => '&', quot => '"', apos => "'", nbsp => ' ');
sub unent { my $s = shift; $s =~ s/&(#[xX][0-9a-fA-F]+|#\d+|\w+);/ent1($1)/ge; $s }
sub ent1 { my $e = shift; return chr(hex substr($e, 2)) if $e =~ /^#[xX]/; return chr(substr($e, 1)) if $e =~ /^#/; $ENT{$e} // "&$e;" }
sub parse_xml {
    my ($t, $file) = @_;
    my $doc = { tag => '#doc', a => {}, kids => [], line => 1 };
    my @st = ($doc); my $line = 1;
    pos($t) = 0;
    while (pos($t) < length $t) {
        if ($t =~ /\G([^<]+)/gc) { my $s = $1; $line += ($s =~ tr/\n//); push @{$st[-1]{kids}}, { tag => '#text', text => unent($s) } if $s =~ /\S/ }
        elsif ($t =~ /\G<(!--|!\[CDATA\[|\?|!)/gc) {
            my $o = $1; my $c = $o eq '!--' ? '-->' : $o eq '?' ? '?>' : $o eq '!' ? '>' : ']]>';
            my $from = pos($t); my $end = index($t, $c, $from); die "$file:$line: error: no closing '$c'\n" if $end < 0;
            my $s = substr($t, $from, $end - $from); pos($t) = $end + length $c; $line += ($s =~ tr/\n//);
            push @{$st[-1]{kids}}, { tag => '#text', text => $s } if $o eq '![CDATA[';
        }
        elsif ($t =~ /\G<\/([^\s>]+)\s*>/gc) { die "$file:$line: error: unexpected </$1>\n" if @st < 2 || $st[-1]{tag} ne $1; pop @st }
        elsif ($t =~ /\G<([^\s\/>!?]+)((?:\s+[^\s=\/>]+\s*=\s*(?:"[^"]*"|'[^']*'))*)\s*(\/?)>/gc) {
            my ($tag, $as, $empty) = ($1, $2, $3);
            my $n = { tag => $tag, a => {}, kids => [], line => $line };
            $n->{a}{$1} = unent($2 // $3) while $as =~ /([^\s=]+)\s*=\s*(?:"([^"]*)"|'([^']*)')/g;
            $line += ($as =~ tr/\n//);
            push @{$st[-1]{kids}}, $n; push @st, $n unless $empty;
        }
        else { die "$file:$line: error: malformed XML\n" }
    }
    die "$file:$line: error: unclosed <$st[-1]{tag}>\n" if @st > 1;
    return $doc;
}
sub elems { grep { $_->{tag} ne '#text' } @{$_[0]{kids}} }
sub ltag { my $t = shift; $t =~ s/^.*://; $t }          # tag without namespace prefix
sub kid { my ($n, $t) = @_; (grep { ltag($_->{tag}) eq $t } elems($n))[0] }
sub text_of { my $n = shift; return $n->{text} if $n->{tag} eq '#text';
    my $s = join '', map { text_of($_) } @{$n->{kids}};
    $s = " $s " if ltag($n->{tag}) =~ /^(?:p|div|li|br|tr|td|th|h\d)$/i;
    return $s }
sub find_all { my ($n, $t, $out) = @_; for my $k (elems($n)) { push @$out, $k if ltag($k->{tag}) eq $t; find_all($k, $t, $out) } }
sub clean {
    my $s = shift // '';
    $s =~ s/\{\\rtf.*\}//s && do { $s = '' };       # stray RTF: let the caller warn
    $s =~ s/<[^>]+>/ /g if $s =~ /<\/?(?:p|div|span|br|b|i)\b/i;
    $s = unent($s) if $s =~ /&\w+;/;
    $s =~ s/\s+/ /g; $s =~ s/^ | $//g;
    return $s;
}

# ------------------------------------------------------------------------------------------
# Modules and objects
# ------------------------------------------------------------------------------------------
my (@MODULES, %OBJ, @NOTES, $NWARN);     # %OBJ: link key -> object
$NWARN = 0;
sub note { my ($f, $l, $sev, $m) = @_; push @NOTES, [$f, $l, scalar @NOTES, "$f:$l: $sev: $m"]; $NWARN++ if $sev eq 'warning' }

for my $f (@ARGV) {
    fail("$f: no such file") unless -f $f;
    if ($f =~ /\.reqifz?$/i) { read_reqif($f) } else { read_csv($f) }
}

sub read_csv {
    my $f = shift;
    my $t = slurp($f);
    my ($first) = $t =~ /^([^\n]*)/;
    my $sep = ($first =~ tr/\t//) > ($first =~ tr/,//) ? "\t" : ($first =~ tr/;//) > ($first =~ tr/,//) ? ';' : ',';
    my (@rows, @row); my ($field, $line, $rowline) = ('', 1, 1);
    pos($t) = 0;
    while (pos($t) < length $t) {
        if ($t =~ /\G"((?:[^"]|"")*)"/gc) { (my $v = $1) =~ s/""/"/g; $line += ($v =~ tr/\n//); $field .= $v }
        elsif ($t =~ /\G([^"\Q$sep\E\n]+)/gc) { $field .= $1 }
        elsif ($t =~ /\G\Q$sep\E/gc) { push @row, $field; $field = '' }
        elsif ($t =~ /\G\n/gc) { push @row, $field; push @rows, [$rowline, @row]; @row = (); $field = ''; $line++; $rowline = $line }
        elsif ($t =~ /\G"/gc) { $field .= '"' }
        else { fail("$f:$line: cannot read CSV") }
    }
    push @row, $field; push @rows, [$rowline, @row] if grep { length } @row;
    my $hdr = shift @rows or fail("$f: empty file");
    my (undef, @h) = @$hdr;
    s/^\s+|\s+$//g for @h;
    my (%col, @links, @keep);
    for my $i (0 .. $#h) {
        my $fd = field_of($h[$i]) // next;
        if ($fd eq 'link') { push @links, [$i, $h[$i]] } else { $col{$fd} //= $i }
    }
    for my $i (0 .. $#h) { push @keep, [$i, $KEEP{lc $h[$i]}] if $KEEP{lc $h[$i]} }
    fail("$f: no id or text column found (columns: " . join(', ', @h) . "); use --map id=COLUMN --map text=COLUMN")
        unless defined $col{id} || defined $col{absno} || defined $col{text};
    (my $mname = basename($f)) =~ s/\.[^.]+$//;
    my $mod = { name => $mname, file => $f, objs => [] };
    $mod->{tests} = 1 if $TESTS{lc $mname};
    for my $r (@rows) {
        my ($ln, @v) = @$r;
        next unless grep { /\S/ } @v;
        my %o = (file => $f, line => $ln, module => $mod);
        $o{$_} = $v[$col{$_}] // '' for grep { defined $col{$_} } keys %col;
        $o{id} = ($O{'id-prefix'} // '') . $o{absno} if (!defined $o{id} || $o{id} eq '') && defined $o{absno} && $o{absno} ne '';
        $o{id} //= '';
        $o{raw_text} = $o{text} // '';
        note($f, $ln, 'warning', "object '$o{id}': rich text or an OLE object was dropped") if $o{raw_text} =~ /\{\\rtf|\bOLE\b/;
        $o{$_} = clean($o{$_}) for grep { defined $o{$_} } qw(id heading text number level type absno);
        $o{links} = [map { [$_->[1], $v[$_->[0]] // ''] } @links];
        $o{keep} = [map { [$_->[1], clean($v[$_->[0]] // '')] } grep { defined $v[$_->[0]] && $v[$_->[0]] =~ /\S/ } @keep];
        push @{$mod->{objs}}, \%o;
    }
    # hierarchy: level column, else object numbers (1.2, 1.2-1, 1.2-1.1), else flat
    my @o = @{$mod->{objs}};
    if (defined $col{level} && grep { $_->{level} =~ /^\d+$/ } @o) {
        my @stack;
        for my $x (@o) {
            my $l = $x->{level} =~ /^(\d+)$/ ? $1 : (@stack ? $stack[-1]{lv} + 1 : 1);
            pop @stack while @stack && $stack[-1]{lv} >= $l;
            $x->{up} = @stack ? $stack[-1]{o} : undef;
            push @stack, { lv => $l, o => $x };
        }
    } elsif (defined $col{number} && grep { $_->{number} =~ /\d/ } @o) {
        my %bynum = map { ($_->{number} => $_) } grep { $_->{number} ne '' } @o;
        for my $x (@o) {
            my $n = $x->{number};
            while ($n =~ s/[.\-]\d+$//) { if ($bynum{$n} && $bynum{$n} != $x) { $x->{up} = $bynum{$n}; last } }
        }
    }
    push @MODULES, $mod;
}

sub read_reqif {
    my $f = shift;
    my $doc = eval { parse_xml(slurp($f), $f) } or do { print STDERR $@; exit 2 };
    my (%adef, %otype, %rtype, %so, @specs, @rels);
    for my $k (qw(STRING XHTML ENUMERATION INTEGER REAL DATE BOOLEAN)) {
        my @d; find_all($doc, "ATTRIBUTE-DEFINITION-$k", \@d);
        $adef{$_->{a}{IDENTIFIER}} = $_->{a}{'LONG-NAME'} // $_->{a}{IDENTIFIER} for @d;
    }
    my @ev; find_all($doc, 'ENUM-VALUE', \@ev); my %enum = map { ($_->{a}{IDENTIFIER} => $_->{a}{'LONG-NAME'} // '') } @ev;
    my @t; find_all($doc, 'SPEC-OBJECT-TYPE', \@t); $otype{$_->{a}{IDENTIFIER}} = $_->{a}{'LONG-NAME'} // '' for @t;
    my @rt; find_all($doc, 'SPEC-RELATION-TYPE', \@rt); $rtype{$_->{a}{IDENTIFIER}} = $_->{a}{'LONG-NAME'} // 'Link' for @rt;
    my @objs; find_all($doc, 'SPEC-OBJECT', \@objs);
    for my $x (@objs) {
        my %o = (file => $f, line => $x->{line}, rid => $x->{a}{IDENTIFIER}, keep => [], links => []);
        my $ty = kid($x, 'TYPE'); my ($tr) = $ty ? elems($ty) : (); $o{type} = $otype{text_of($tr) =~ s/\s//gr} // '' if $tr;
        my $vals = kid($x, 'VALUES');
        for my $v ($vals ? elems($vals) : ()) {
            my $def = kid($v, 'DEFINITION') or next; my ($dr) = elems($def) or next;
            my $an = $adef{text_of($dr) =~ s/\s//gr} // next;
            my $val;
            if (defined $v->{a}{'THE-VALUE'}) { $val = $v->{a}{'THE-VALUE'} }
            elsif (my $tv = kid($v, 'THE-VALUE')) { $val = text_of($tv) }
            elsif (my $vs = kid($v, 'VALUES')) { $val = join ', ', map { $enum{text_of($_) =~ s/\s//gr} // '' } map { elems($_) } elems($vs) }
            $val = clean($val);
            my $fd = field_of($an);
            if ($KEEP{lc $an}) { push @{$o{keep}}, [$KEEP{lc $an}, $val] if $val ne '' }
            next unless $fd && $fd ne 'link';
            $o{$fd} = $val if !defined $o{$fd} || $o{$fd} eq '';
        }
        $o{id} = ($O{'id-prefix'} // '') . $o{absno} if (!defined $o{id} || $o{id} eq '') && defined $o{absno};
        $o{id} //= '';
        $so{$o{rid}} = \%o;
    }
    find_all($doc, 'SPEC-RELATION', \@rels);
    for my $r (@rels) {
        my ($s, $t) = map { my $k = kid($r, $_); my ($ref) = $k ? elems($k) : (); $ref ? text_of($ref) =~ s/\s//gr : '' } qw(SOURCE TARGET);
        my $ty = kid($r, 'TYPE'); my ($tr) = $ty ? elems($ty) : ();
        my $name = $tr ? ($rtype{text_of($tr) =~ s/\s//gr} // 'Link') : 'Link';
        push @{$so{$s}{links}}, [$name, "rid:$t"] if $so{$s};
        note($f, $r->{line}, 'warning', "link '$name' from an object not in this file") unless $so{$s};
    }
    find_all($doc, 'SPECIFICATION', \@specs);
    my %placed;
    for my $sp (@specs) {
        my $mod = { name => $sp->{a}{'LONG-NAME'} // basename($f), file => $f, objs => [] };
        $mod->{tests} = 1 if $TESTS{lc $mod->{name}};
        my $walk; $walk = sub {
            my ($n, $up) = @_;
            for my $h (grep { ltag($_->{tag}) eq 'SPEC-HIERARCHY' } elems($n)) {
                my $ob = kid($h, 'OBJECT'); my ($ref) = $ob ? elems($ob) : ();
                my $o = $ref && $so{text_of($ref) =~ s/\s//gr};
                if ($o && !$placed{$o}++) { $o->{module} = $mod; $o->{up} = $up; push @{$mod->{objs}}, $o }
                my $ch = kid($h, 'CHILDREN'); $walk->($ch, $o // $up) if $ch;
            }
        };
        my $ch = kid($sp, 'CHILDREN'); $walk->($ch, undef) if $ch;
        push @MODULES, $mod;
    }
    my @loose = grep { !$placed{$_} } map { $so{$_} } sort keys %so;
    if (@loose) {
        (my $mn = basename($f)) =~ s/\.[^.]+$//;
        my $mod = { name => $mn, file => $f, objs => [] }; $mod->{tests} = 1 if $TESTS{lc $mn};
        $_->{module} = $mod for @loose; push @{$mod->{objs}}, @loose; push @MODULES, $mod;
    }
}

# ------------------------------------------------------------------------------------------
# Classify, name, resolve links
# ------------------------------------------------------------------------------------------
my %KEYWORD = map { $_ => 1 } qw(about abstract accept action actor after alias all allocate allocation analysis and as
    assert assign assume at attribute bind binding by calc case comment concern connect connection constant constraint
    crosses decide def default defined dependency derived do doc else end entry enum event exhibit exit expose false
    filter first flow for fork frame from hastype if implies import in include individual inout interface istype item
    join language library locale loop merge message meta metadata nonunique not null objective occurrence of or ordered
    out package parallel part perform port private protected public redefines ref references render rendering rep
    require requirement return satisfy send snapshot specializes stakeholder standard state subject subsets succession
    terminate then timeslice to transition true until use variant variation verification verify via view viewpoint when
    while xor);
my %STOP = map { $_ => 1 } qw(the a an shall be is are of to and or for with within in on at by from than that this which its
    it will should must all each any as);
sub camel { my ($s, $upper) = @_; my @w = grep { length } split /[^A-Za-z0-9]+/, $s // ''; return '' unless @w;
    my $r = join '', map { ucfirst } @w; unless ($upper) { $r =~ s/^([A-Z]+)(?=[A-Z][a-z]|\d|$)/\L$1/ or $r =~ s/^([A-Z])/\l$1/ }
    $r = "_$r" if $r =~ /^\d/; $r }
sub q_short { my $s = shift; $s =~ s/(['\\])/\\$1/g; "'$s'" }
sub sq { my $s = shift // ''; $s =~ s/(["\\])/\\$1/g; "\"$s\"" }

my %BYID;
for my $m (@MODULES) {
    my $pk = camel($O{prefix}, 1) . camel($m->{name}, 1); $pk = camel($O{prefix}, 1) . 'Module' if $pk eq '';
    $m->{pkg} = $pk;
    for my $o (@{$m->{objs}}) {
        my $ty = $o->{type} // '';
        $o->{kids} = [];
        $o->{istest} = $m->{tests} || $ty =~ /test/i;
        $o->{isdesign} = $DESIGN{lc $m->{name}} || $ty =~ /design|component|element/i;
        $o->{kind} = $ty =~ /head|title|section|chapter/i ? 'heading'
                   : $ty =~ /info|note|comment|rationale|description|figure|table/i ? 'info'
                   : (($o->{heading} // '') ne '' && ($o->{text} // '') eq '') ? 'heading'
                   : (($o->{text} // '') ne '' || ($o->{heading} // '') ne '') ? 'req' : 'empty';
        note($o->{file}, $o->{line}, 'warning', "object '$o->{id}' has no ID") if $o->{id} eq '' && $o->{kind} eq 'req';
        if ($o->{id} ne '') {
            note($o->{file}, $o->{line}, 'warning', "ID '$o->{id}' also used at $BYID{$o->{id}}{file}:$BYID{$o->{id}}{line}") if $BYID{$o->{id}};
            $BYID{$o->{id}} //= $o;
        }
        $OBJ{"rid:$o->{rid}"} = $o if defined $o->{rid};
    }
    for my $o (@{$m->{objs}}) { push @{$o->{up}{kids}}, $o if $o->{up} }
}
# a heading with no requirement below it is kept as a comment, not an empty requirement group
sub has_req { my $o = shift; return 1 if $o->{kind} eq 'req'; for (@{$o->{kids}}) { return 1 if has_req($_) } 0 }
for my $o (map { @{$_->{objs}} } @MODULES) { $o->{kind} = 'hcomment' if $o->{kind} eq 'heading' && !has_req($o) }

my %TAKEN;
sub name_for {
    my ($o, $scope) = @_;
    my $n = '';
    $n = camel($o->{heading}, 0) if ($o->{heading} // '') ne '';
    if ($n eq '') { my @w = grep { !$STOP{lc $_} } grep { length } split /[^A-Za-z0-9]+/, $o->{text} // ''; $n = camel(join(' ', @w[0 .. ($#w < 4 ? $#w : 4)]), 0) if @w }
    $n = camel('r ' . $o->{id}, 0) if $n eq '';
    $n = 'unnamed' if $n eq '';
    $n .= '_' if $KEYWORD{$n};
    my $b = $n; my $i = 1; $n = $b . ++$i while $TAKEN{"$scope\0$n"}; $TAKEN{"$scope\0$n"} = 1;
    return $n;
}

# links: each cell is split into items; an item names its target by a known ID it contains
my $ids = join '|', map { quotemeta } sort { length $b <=> length $a } keys %BYID;
my $IDRE = $ids ne '' ? qr/(?<![\w-])($ids)(?![\w-])/ : qr/(?!)/;
my (@SAT, %VER, @DEP, %unres);
for my $o (map { @{$_->{objs}} } @MODULES) {
    for my $l (@{$o->{links} // []}) {
        my ($col, $cell) = @$l;
        my $kind = link_kind($col);
        my @targets;
        if ($cell =~ /^rid:(.*)$/) { my $t = $OBJ{"rid:$1"}; if ($t) { push @targets, $t } else { $unres{"(ReqIF object $1)"} //= [0, $o->{file}, $o->{line}]; $unres{"(ReqIF object $1)"}[0]++ } }
        else {
            for my $item (grep { /\S/ } split /[\n;|]+|,\s+(?=\S)/, $cell) {
                if ($item =~ $IDRE) { push @targets, $BYID{$1} }
                else { my ($k) = $item =~ /([A-Za-z][\w]*-\d+|\b\d+\b)/; $k //= clean($item); $unres{$k} //= [0, $o->{file}, $o->{line}]; $unres{$k}[0]++ }
            }
        }
        for my $t (@targets) {
            next if $t == $o;
            my ($a, $b) = ($o, $t);
            if ($kind eq 'verify') {
                my ($test, $req) = $a->{istest} ? ($a, $b) : $b->{istest} ? ($b, $a) : (undef, undef);
                if (!$test) { note($o->{file}, $o->{line}, 'warning', "'$col' link $a->{id} -> $b->{id}: neither end is a test object (use --tests MODULE); kept as a dependency"); push @DEP, [$a, $b, $col]; next }
                push @{$VER{$test}}, $req;
            } elsif ($kind eq 'satisfy') {
                # the satisfied end is the requirement; the other is the design object
                my ($req, $by) = $col =~ /by$|ed by/i ? ($a, $b) : ($b, $a);
                if ($by->{isdesign}) { push @SAT, [$req, $by, $col] }
                else { push @DEP, [$by, $req, $col]; $o->{satdep}++ }     # requirement satisfies requirement: a derivation
            } else { push @DEP, [$a, $b, $col] }
        }
    }
}
note($unres{$_}[1], $unres{$_}[2], 'note', "link target '$_' is not in the imported modules ($unres{$_}[0] link(s); first here)") for sort keys %unres;

# ------------------------------------------------------------------------------------------
# Emit
# ------------------------------------------------------------------------------------------
my (%files, @IDS);
sub doc_lines {
    my ($text, $ind, $kw) = @_; $kw //= 'doc';
    $text =~ s{\*/}{* /}g; return () if $text eq '';
    my @w = split / /, $text; my @l = ('');
    for my $w (@w) { if (length($l[-1]) && length($l[-1]) + 1 + length($w) > 96 - length($ind) - 8) { push @l, $w } else { $l[-1] .= (length $l[-1] ? ' ' : '') . $w } }
    my @out = ("$ind$kw /* $l[0]"); push @out, "$ind     * $_" for @l[1 .. $#l]; $out[-1] .= ' */';
    return @out;
}
sub prov {
    my ($o, $ind) = @_;
    my @l;
    push @l, "$ind\@DoorsObject { module = " . sq($o->{module}{name}) . ';' . join('', map { " $_->[0] = " . sq($_->[1]) . ';' } grep { ($_->[1] // '') ne '' } ['objectNumber', $o->{number}], ['objectType', $o->{type}]) . ' }' if $O{provenance};
    push @l, "$ind\@DoorsAttribute { name = " . sq($_->[0]) . '; value = ' . sq($_->[1]) . '; }' for @{$o->{keep}};
    return @l;
}
sub path_of { my $o = shift; my @p; for (my $x = $o; $x; $x = $x->{up}) { unshift @p, $x->{v2} if $x->{v2} } join '.', @p }
sub ref_of { my $o = shift; "$o->{module}{pkg}::" . path_of($o) }
sub emit_obj {
    my ($o, $L, $ind) = @_;
    my $k = $o->{kind};
    if ($k eq 'empty') { return }
    if (($o->{istest} || $o->{isdesign}) && $k eq 'req') { emit_obj($_, $L, $ind) for @{$o->{kids}}; return }   # a verification def or a design placeholder
    if ($k eq 'info' || $k eq 'hcomment') {
        my $t = join ' - ', grep { $_ ne '' } ($o->{number} // ''), ($o->{heading} // ''), ($o->{text} // '');
        push @$L, doc_lines(($o->{id} ne '' ? "[$o->{id}] " : '') . $t, $ind, 'comment') if $t ne '';
        emit_obj($_, $L, $ind) for @{$o->{kids}};
        return;
    }
    $o->{v2} = name_for($o, $o->{up} ? "o$o->{up}" : "m$o->{module}");
    my $head = "${ind}requirement " . ($o->{id} ne '' ? '<' . q_short($o->{id}) . '> ' : '') . $o->{v2};
    my @body;
    my $docs = $k eq 'heading' ? join(' ', grep { $_ ne '' } $o->{number} // '', $o->{heading}) : ($o->{text} // '');
    $docs = $o->{heading} if $docs eq '' && ($o->{heading} // '') ne '';
    push @body, doc_lines($docs, "$ind    ");
    push @body, prov($o, "$ind    ");
    my $at = scalar @$L;
    my @sub; emit_obj($_, \@sub, "$ind    ") for @{$o->{kids}};
    push @$L, @body || @sub ? ("$head {", @body, @sub, "$ind}") : ("$head;");
    $o->{at} = $at;
    note($o->{file}, $o->{line}, 'warning', "requirement '$o->{id}' has no text") if $k eq 'req' && ($o->{text} // '') eq '';
}
my $libimp = $O{provenance} ? ['    private import DoorsSource::*;'] : [];
my $mark = $O{marking} ? ['    private import SecMeta::*;', "    \@Marking { level = Level::$O{marking}; }"] : [];
for my $m (@MODULES) {
    next unless grep { $_->{kind} eq 'req' && !$_->{istest} && !$_->{isdesign} } @{$m->{objs}};
    my @L = ("package $m->{pkg} {", doc_lines("DOORS module '$m->{name}' imported from " . basename($m->{file}) . ' by doors2v2.pl. Add a subject and, where quantitative, a require constraint to each requirement.', '    '),
             @$libimp, @$mark, '');
    emit_obj($_, \@L, '    ') for grep { !$_->{up} } @{$m->{objs}};
    push @L, '}';
    $files{"requirements/$m->{pkg}.sysml"} = \@L;
    $m->{file_out} = "requirements/$m->{pkg}.sysml";
}
my $base = camel($O{prefix}, 1) . 'Doors';
if (@SAT) {
    my @L = ("package ${base}Satisfaction {", doc_lines('DOORS satisfaction links. The satisfying DOORS objects are not design elements: replace each part below with the design element that satisfies the requirement.', '    '), @$libimp, @$mark, '');
    my %by;
    for my $s (@SAT) {
        my ($req, $by, $col) = @$s;
        next unless $req->{v2};
        my $n = $by{$by} //= do {
            my $x = camel($by->{heading} || ($by->{text} // ''), 0); $x = substr($x, 0, 40) if length $x > 40; $x = camel('by ' . ($by->{id} || 'object'), 0) if $x eq '';
            $x .= '_' if $KEYWORD{$x}; my $b = $x; my $i = 1; $x = $b . ++$i while $TAKEN{"sat\0$x"}; $TAKEN{"sat\0$x"} = 1;
            push @L, '', "    part $x; // placeholder for DOORS design object $by->{id} ($by->{module}{name})"; $by->{part} = "${base}Satisfaction::$x"; $x };
        push @L, "    satisfy " . ref_of($req) . " by $n; // DOORS '$col'";
    }
    push @L, '}';
    $files{"configurations/${base}Satisfaction.sysml"} = \@L;
    note($SAT[0][1]{file}, $SAT[0][1]{line}, 'warning', scalar(@SAT) . " satisfy link(s) from DOORS design objects: replace the placeholder parts in ${base}Satisfaction with the design elements");
}
if (%VER) {
    my @L = ("package ${base}Verification {", doc_lines('Verification cases from DOORS test objects. Each holds only its objective: the procedure stays in the test document.', '    '), @$libimp, @$mark);
    my %tk;
    my @tests = sort { $a->{file} cmp $b->{file} || $a->{line} <=> $b->{line} } grep { $VER{$_} } map { @{$_->{objs}} } @MODULES;
    for my $t (@tests) {
        my $n = camel($t->{heading} || ($t->{text} // ''), 1); $n = substr($n, 0, 40) if length $n > 40; $n = 'Test' . camel($t->{id}, 1) if $n eq '';
        $n .= 'Test' unless $n =~ /(?:Test|Inspection|Analysis|Demonstration)$/;
        my $b = $n; my $i = 1; $n = $b . ++$i while $tk{$n}; $tk{$n} = 1;
        push @L, '', "    verification def " . ($t->{id} ne '' ? '<' . q_short($t->{id}) . '> ' : '') . "$n {", doc_lines($t->{text} || $t->{heading} || '', '        '), prov($t, '        '), '        objective {';
        my %seen;
        push @L, "            verify " . ref_of($_) . ';' for grep { $_->{v2} && !$seen{$_}++ } @{$VER{$t}};
        push @L, '        }', '    }';
        $t->{vdef} = "${base}Verification::$n";
    }
    push @L, '}';
    $files{"evaluation/${base}Verification.sysml"} = \@L;
}
if (@DEP) {
    my @L = ("package ${base}Links {", doc_lines('DOORS derivation, refinement and trace links between requirements, as dependencies from source to target.', '    '), @$libimp, @$mark, '');
    for my $d (@DEP) {
        my ($a, $b, $col) = @$d;
        next unless $a->{v2} && $b->{v2};
        (my $ra = ref_of($a)) =~ s/\./::/g; (my $rb = ref_of($b)) =~ s/\./::/g;
        push @L, "    dependency from $ra to $rb; // DOORS '$col'" . ($col =~ /satisf/i ? ' (a requirement satisfying a requirement: derivation)' : '');
    }
    push @L, '}';
    $files{"requirements/${base}Links.sysml"} = \@L;
}
if ($O{provenance}) {
    $files{'library/DoorsSource.sysml'} = ['library package DoorsSource {',
        doc_lines('Where an element came from in DOORS: module, object number and type, and any carried attributes. Generated by doors2v2.pl.', '    '),
        '    private import ScalarValues::*;', @$mark, '',
        '    metadata def DoorsObject {', '        doc /* The DOORS object this element was imported from. */',
        '        attribute module : String;', '        attribute objectNumber : String;', '        attribute objectType : String;', '    }',
        '    metadata def DoorsAttribute {', '        doc /* A DOORS attribute value carried over as is. */',
        '        attribute name : String;', '        attribute value : String;', '    }', '}'];
}

# write
my $out = $O{o};
for my $f (sort keys %files) {
    my $p = "$out/model/$f"; (my $d = $p) =~ s{/[^/]+$}{}; make_path($d);
    open my $h, '>:encoding(UTF-8)', $p or fail("$p: $!");
    print $h "// Generated by doors2v2.pl from " . join(', ', map { basename($_) } @ARGV) . ". Re-run after each DOORS export and review the diff.\n";
    print $h "$_\n" for @{$files{$f}};
    close $h;
}
open my $h, '>:encoding(UTF-8)', "$out/ids.tsv" or fail("$out/ids.tsv: $!");
print $h "doors_id\tmodule\tkind\tv2_name\tsource\n";
for my $m (@MODULES) { for my $o (@{$m->{objs}}) {
    next unless $o->{id} ne '';
    my $v2 = $o->{v2} ? ref_of($o) : $o->{vdef} // $o->{part} // ($o->{kind} =~ /info|hcomment/ ? '(comment)' : '');
    print $h join("\t", $o->{id}, $m->{name}, $o->{istest} ? 'test' : $o->{isdesign} ? 'design' : $o->{kind}, $v2, "$o->{file}:$o->{line}"), "\n";
} }
close $h;
my %n; for my $o (map { @{$_->{objs}} } @MODULES) { $n{$o->{kind} eq 'req' && $o->{istest} ? 'test' : $o->{kind} eq 'req' && $o->{isdesign} ? 'design' : $o->{kind}}++ }
my $sum = sprintf 'doors2v2: %d module(s), %d requirement(s), %d heading group(s), %d comment(s), %d test(s), %d design object(s); links: %d satisfy, %d verify, %d dependency, %d unresolved; %d to finish by hand',
    scalar @MODULES, $n{req} // 0, $n{heading} // 0, ($n{info} // 0) + ($n{hcomment} // 0), $n{test} // 0, $n{design} // 0,
    scalar @SAT, scalar(map { @$_ } values %VER), scalar @DEP, scalar(keys %unres), $NWARN;
open $h, '>:encoding(UTF-8)', "$out/CONVERSION.txt" or fail("$out/CONVERSION.txt: $!");
my @sorted = map { $_->[3] } sort { $a->[0] cmp $b->[0] || $a->[1] <=> $b->[1] || $a->[2] <=> $b->[2] } @NOTES;
print $h "# doors2v2.pl " . join(' ', @ARGV) . "\n", map({ "$_\n" } @sorted), "$sum\n";
close $h;
print "$_\n" for grep { /: warning: / } @sorted;
print "$sum\n";
exit($NWARN ? 1 : 0);
