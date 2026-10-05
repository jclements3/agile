package Reqif;
# DOORS requirements -> SysML v2 requirement definitions, from ReqIF 1.0/1.2 (.reqif, or .reqifz zipped) or from a
# DOORS CSV export; plus the trace report behind status metrics C, F, G (and I) of docs/STATUS-METRICS.html.
#
#   my $d   = Reqif::load_reqif($path, %o);           # .reqif or .reqifz
#   my $d   = Reqif::load_csv($path, cols => { id => 'Object Identifier', text => 'Object Text', ... }, %o);
#   my $out = Reqif::convert($d, req_style => 'def'|'usage', layout => '{seg}/{pkg}.sysml');
#   print Reqif::report_text($out);
#   my $t   = Reqif::trace($d, $out, $model_dir);     # linked / orphan / unverified against existing SysML v2 text
#   print Reqif::trace_text($t);
#
# The loaded document, whichever the source: { source, title, objects => { oid => { oid, id, text, heading, name,
# vm, type, attrs => { long name => value } } }, order => [oid], specs => [ { name, kids => [ node ] } ] where a node
# is { oid, kids => [ node ] }, relations => [ { id, type, src, tgt } ], counts => {...} }.
#
# DOORS conventions honoured (ReqIF as DOORS / DOORS Next export it): ReqIF.ForeignID (the absolute number),
# "Object Identifier", ReqIF.Text / "Object Text" (XHTML, flattened to plain text), ReqIF.ChapterName /
# "Object Heading", ReqIF.Name (the title). An object with a heading and no text is a section -> a nested package;
# an object with text is a requirement; an object with neither is reported (a TODO line in the output).
use strict;
use warnings;
use XmlLite;
use SysmlText qw(name ident str doc requirement check);

my @ID_ATTRS   = ('Object Identifier', 'ReqIF.ForeignID', 'Absolute Number', 'ID', 'Identifier');
my @TEXT_ATTRS = ('ReqIF.Text', 'Object Text', 'Text', 'Description');
my @HEAD_ATTRS = ('ReqIF.ChapterName', 'Object Heading', 'Heading');
my @NAME_ATTRS = ('ReqIF.Name', 'Name', 'Title');

sub _first { my ($h, @k) = @_; for (@k) { return $h->{$_} if defined $h->{$_} && $h->{$_} =~ /\S/ } return undef }

# ---- XHTML -> plain text
my %BLOCK = map { $_ => 1 } qw(p div br li tr h1 h2 h3 h4 h5 h6 ul ol table pre blockquote dt dd);
sub xhtml_text {
    my ($node) = @_;
    my $out = '';
    my $walk; $walk = sub {
        my ($n) = @_;
        for my $k (@{ $n->{k} }) {
            if (!ref $k) { (my $t = $k) =~ s/\s+/ /g; $out .= $t; next }
            my $l = lc $k->{l};
            if ($l eq 'br') { $out .= "\n"; next }
            if ($l eq 'img' || $l eq 'object') { $out .= '[' . ($k->{a}{alt} || $k->{a}{name} || 'image') . ']'; next }
            $out .= "\n" if $BLOCK{$l};
            $out .= '- ' if $l eq 'li';
            $out .= ' | ' if ($l eq 'td' || $l eq 'th') && $out !~ /\n$/;
            $walk->($k);
            $out .= "\n" if $BLOCK{$l};
        }
    };
    $walk->($node);
    $out =~ s/\xC2\xA0/ /g;                   # no-break spaces (&#160;) read as spaces
    $out =~ s/[ \t]+\n/\n/g; $out =~ s/\n[ \t]+/\n/g; $out =~ s/\n{2,}/\n/g;
    $out =~ s/^\s+|\s+$//g;
    $out =~ s/ {2,}/ /g;
    return $out;
}

sub _reqif_xml {                              # the XML text of a .reqif, or of the first .reqif inside a .reqifz
    my ($path) = @_;
    return undef unless $path =~ /\.reqifz$/i;
    my $ok = eval { require IO::Uncompress::Unzip; 1 };
    die "$path: IO::Uncompress::Unzip is not available in this Perl; unzip the .reqifz and give the .reqif inside\n" unless $ok;
    my $z = IO::Uncompress::Unzip->new($path) or die "$path: not a zip (" . do { no warnings "once"; $IO::Uncompress::Unzip::UnzipError } . ")\n";
    my $status = 1;
    while ($status > 0) {
        my $name = $z->getHeaderInfo->{Name};
        if ($name =~ /\.reqif$/i) {
            my ($buf, $data) = ('', '');
            while (($status = $z->read($buf)) > 0) { $data .= $buf }
            return $data;
        }
        $status = $z->nextStream;
    }
    die "$path: no .reqif file inside the archive\n";
}

sub load_reqif {
    my ($path, %o) = @_;
    my $xml = _reqif_xml($path);
    my $keep = sub { $_[0]{l} eq 'THE-VALUE' || $_[0]{l} eq 'THE-ORIGINAL-VALUE' };
    my $root = defined $xml ? XmlLite::parse_string($xml, keep_ws => $keep) : XmlLite::parse_file($path, keep_ws => $keep);
    my (%ad, %ev, %types, %objs, @order, @rels, @specs, %count);
    # index every element carrying an IDENTIFIER: attribute definitions, enum values, types
    my $walk; $walk = sub {
        my ($n) = @_;
        my $l = $n->{l};
        if ($l =~ /^ATTRIBUTE-DEFINITION-/) { $ad{ $n->{a}{IDENTIFIER} } = $n->{a}{'LONG-NAME'} if defined $n->{a}{IDENTIFIER} }
        elsif ($l eq 'ENUM-VALUE') { $ev{ $n->{a}{IDENTIFIER} } = defined $n->{a}{'LONG-NAME'} ? $n->{a}{'LONG-NAME'} : $n->{a}{IDENTIFIER} }
        elsif ($l =~ /^(SPEC-OBJECT-TYPE|SPEC-RELATION-TYPE|SPECIFICATION-TYPE|RELATION-GROUP-TYPE)$/) { $types{ $n->{a}{IDENTIFIER} } = $n->{a}{'LONG-NAME'} }
        $walk->($_) for XmlLite::kids($n);
    };
    $walk->($root);
    my $ref = sub { my ($n, $wrap) = @_; my $w = XmlLite::kid($n, $wrap) or return undef; my ($r) = XmlLite::kids($w); return $r ? XmlLite::text($r) : undef };
    my $values = sub {                        # VALUES of an object -> { long name => value }
        my ($n) = @_;
        my %v;
        my $vs = XmlLite::kid($n, 'VALUES') or return \%v;
        for my $av (XmlLite::kids($vs)) {
            my $def = $ref->($av, 'DEFINITION');
            my $an = defined $def && defined $ad{$def} ? $ad{$def} : $def;
            next unless defined $an;
            my $val;
            if ($av->{l} eq 'ATTRIBUTE-VALUE-XHTML') {
                my $tv = XmlLite::kid($av, 'THE-VALUE');
                $val = $tv ? xhtml_text($tv) : '';
            } elsif ($av->{l} eq 'ATTRIBUTE-VALUE-ENUMERATION') {
                my $w = XmlLite::kid($av, 'VALUES');
                $val = join ', ', map { my $t = XmlLite::text($_); defined $ev{$t} ? $ev{$t} : $t } $w ? XmlLite::kids($w) : ();
            } else {
                $val = $av->{a}{'THE-VALUE'};
                if (!defined $val) { my $tv = XmlLite::kid($av, 'THE-VALUE'); $val = $tv ? XmlLite::text($tv) : '' }
            }
            $v{$an} = $val;
        }
        return \%v;
    };
    my $find; $find = sub { my ($n, $l, $acc) = @_; for (XmlLite::kids($n)) { if ($_->{l} eq $l) { push @$acc, $_ } else { $find->($_, $l, $acc) } } return $acc };
    for my $so (@{ $find->($root, 'SPEC-OBJECT', []) }) {
        my $oid = $so->{a}{IDENTIFIER};
        next unless defined $oid;
        my $v = $values->($so);
        my $t = $ref->($so, 'TYPE');
        $objs{$oid} = _object($oid, $v, defined $t && defined $types{$t} ? $types{$t} : $t, \%o);
        push @order, $oid;
    }
    for my $sr (@{ $find->($root, 'SPEC-RELATION', []) }) {
        my $t = $ref->($sr, 'TYPE');
        push @rels, { id => $sr->{a}{IDENTIFIER}, type => (defined $t && defined $types{$t} ? $types{$t} : defined $t ? $t : ''),
                      src => $ref->($sr, 'SOURCE'), tgt => $ref->($sr, 'TARGET') };
    }
    my $tree; $tree = sub {
        my ($n) = @_;
        my $c = XmlLite::kid($n, 'CHILDREN') or return [];
        return [ map { { oid => $ref->($_, 'OBJECT'), kids => $tree->($_) } } XmlLite::kids($c, 'SPEC-HIERARCHY') ];
    };
    for my $sp (@{ $find->($root, 'SPECIFICATION', []) }) {
        my $nm = $sp->{a}{'LONG-NAME'}; $nm = $sp->{a}{IDENTIFIER} unless defined $nm && $nm ne '';
        push @specs, { name => $nm, kids => $tree->($sp) };
    }
    my $title;
    for my $h (@{ $find->($root, 'TITLE', []) }) { $title = XmlLite::text($h); last }
    (my $src = $path) =~ s{.*[/\\]}{};
    return { source => $src, title => $title, objects => \%objs, order => \@order, specs => \@specs, relations => \@rels,
             spec_objects => scalar @order };
}

sub _object {
    my ($oid, $v, $type, $o) = @_;
    my $id = defined $o->{id_attr} ? $v->{ $o->{id_attr} } : _first($v, @ID_ATTRS);
    $id = $oid unless defined $id && $id ne '';
    $id = $o->{id_prefix} . $id if defined $o->{id_prefix} && $id !~ /^\Q$o->{id_prefix}\E/;
    my $vm;
    if (defined $o->{vm_attr}) { $vm = $v->{ $o->{vm_attr} } }
    else { for my $k (sort keys %$v) { if ($k =~ /verif/i && defined $v->{$k} && $v->{$k} =~ /\S/) { $vm = $v->{$k}; last } } }
    return { oid => $oid, id => $id, type => $type, attrs => $v, bare => (%$v ? 0 : 1),
             text => defined $o->{text_attr} ? $v->{ $o->{text_attr} } : _first($v, @TEXT_ATTRS),
             heading => defined $o->{heading_attr} ? $v->{ $o->{heading_attr} } : _first($v, @HEAD_ATTRS),
             name => _first($v, @NAME_ATTRS), vm => $vm };
}

# ---- CSV (RFC 4180: quoted fields, doubled quotes, newlines inside quotes; BOM; CRLF; , ; or tab, detected)
sub parse_csv {
    my ($text, $sep) = @_;
    $text =~ s/^\xEF\xBB\xBF//;
    if (!defined $sep) {
        my ($first) = $text =~ /^([^\n]*)/;
        my %c = (',' => ($first =~ tr/,//), ';' => ($first =~ tr/;//), "\t" => ($first =~ tr/\t//));
        ($sep) = sort { $c{$b} <=> $c{$a} || $a cmp $b } keys %c;
    }
    my (@rows, @row);
    my $f = '';
    my $s = quotemeta $sep;
    pos($text) = 0;
    while (pos($text) < length $text) {
        if ($text =~ /\G"((?:[^"]|"")*)"/gc) { ($f .= $1) =~ s/""/"/g; next }
        if ($text =~ /\G$s/gc) { push @row, $f; $f = ''; next }
        if ($text =~ /\G\r?\n/gc) { push @row, $f; push @rows, [@row]; @row = (); $f = ''; next }
        if ($text =~ /\G([^"\r\n$s]+|["\r])/gc) { $f .= $1; next }
    }
    push @row, $f if $f ne '' || @row;
    push @rows, [@row] if @row;
    for my $r (@rows) { s/\r\n?/\n/g for @$r }
    return [ grep { grep { /\S/ } @$_ } @rows ];
}

my %CSV_GUESS = (
    id      => qr/^(object identifier|id|identifier|absolute number|req(uirement)? ?id|doors ?id)$/i,
    text    => qr/^(object text|text|requirement|requirement text|description)$/i,
    heading => qr/^(object heading|heading|section)$/i,
    level   => qr/^(object level|level|depth)$/i,
    vm      => qr/verif/i,
    name    => qr/^(name|title|short name)$/i,
);

sub load_csv {
    my ($path, %o) = @_;
    open my $fh, '<', $path or die "$path: $!\n";
    binmode $fh;
    my $text = do { local $/; <$fh> };
    close $fh;
    my $rows = parse_csv($text, $o{sep});
    die "$path: no rows\n" unless @$rows;
    my @head = map { my $h = $_; $h =~ s/^\s+|\s+$//g; $h } @{ shift @$rows };
    my %col;
    for my $k (keys %CSV_GUESS) {
        if (defined $o{cols}{$k}) {
            my ($i) = grep { lc $head[$_] eq lc $o{cols}{$k} } 0 .. $#head;
            die "$path: no column '$o{cols}{$k}' (have: " . join(', ', @head) . ")\n" unless defined $i;
            $col{$k} = $i;
        } else {
            my ($i) = grep { $head[$_] =~ $CSV_GUESS{$k} } 0 .. $#head;
            $col{$k} = $i if defined $i;
        }
    }
    die "$path: no id column (have: " . join(', ', @head) . "); name it with --col id=NAME\n" unless defined $col{id};
    die "$path: no text column (have: " . join(', ', @head) . "); name it with --col text=NAME\n" unless defined $col{text} || defined $col{heading};
    my (%objs, @order);
    (my $base = $path) =~ s{.*[/\\]}{}; (my $src = $base) =~ s/\.[^.]+$//;
    my $root = { kids => [] };
    my @stack = ([ 0, $root ]);
    my $n = 0;
    for my $r (@$rows) {
        my $get = sub { my $i = $col{ $_[0] }; return undef unless defined $i; my $v = $r->[$i]; $v =~ s/^\s+|\s+$//g if defined $v; return $v };
        my %v = map { $head[$_] => (defined $r->[$_] ? $r->[$_] : '') } 0 .. $#head;
        my $id = $get->('id');
        my $oid = 'row' . ++$n;
        my $heading = $get->('heading');
        my $level = $get->('level');
        if ((!defined $level || $level !~ /^\d+$/) && defined $heading && $heading =~ s/^(\d+(?:\.\d+)*)\.?\s+//) { $level = ($1 =~ tr/.//) + 1 }
        $id = $o{id_prefix} . $id if defined $id && $id ne '' && defined $o{id_prefix} && $id !~ /^\Q$o{id_prefix}\E/;
        $objs{$oid} = { oid => $oid, id => (defined $id && $id ne '' ? $id : $oid), text => $get->('text'), heading => $heading,
                        name => $get->('name'), vm => $get->('vm'), attrs => \%v, type => 'csv row' };
        push @order, $oid;
        my $node = { oid => $oid, kids => [] };
        if (defined $level && $level =~ /^\d+$/) {
            pop @stack while @stack > 1 && $stack[-1][0] >= $level;
            push @{ $stack[-1][1]{kids} }, $node;
            push @stack, [ $level, $node ];
        } else { push @{ $root->{kids} }, $node }
    }
    return { source => $base, title => undef, objects => \%objs, order => \@order,
             specs => [ { name => (defined $o{name} ? $o{name} : $src), kids => $root->{kids} } ], relations => [],
             spec_objects => scalar @order };
}

# ---- conversion
sub _kind { my ($ob) = @_; return 'missing' unless $ob; return 'req' if (defined $ob->{text} && $ob->{text} =~ /\S/) || $ob->{bare}; return 'heading' if defined $ob->{heading} && $ob->{heading} =~ /\S/; return 'empty' }

sub convert {
    my ($d, %o) = @_;
    my $style = $o{req_style} || 'def';
    my $layout = $o{layout} || '{seg}/{pkg}.sysml';
    my $obj = $d->{objects};
    my (%reqtop, $cur_top);
    my (%reqname, %reqpkg, %used_req, %count, @unplaced_l, %files, %imports, %placed);
    my %vm_count;
    # requirement names: ident(doorsId), unique across the export
    for my $oid (@{ $d->{order} }) {
        next unless _kind($obj->{$oid}) eq 'req';
        my $b = ident($obj->{$oid}{id}); my $nmv = $b; my $i = 1;
        $nmv = $b . '_' . ++$i while $used_req{$nmv};
        $used_req{$nmv} = 1; $reqname{$oid} = $nmv;
    }
    my $req_lines = sub {
        my ($oid, $ind) = @_;
        my $ob = $obj->{$oid};
        $count{requirements}++;
        $count{no_text}++ unless defined $ob->{text} && $ob->{text} =~ /\S/;
        if (defined $ob->{vm} && $ob->{vm} =~ /\S/) { $count{with_vm}++; $vm_count{ $ob->{vm} }++ } else { $count{without_vm}++ }
        my @attrs = map { [ $_, $ob->{attrs}{$_} ] } grep { defined $ob->{attrs}{$_} && $ob->{attrs}{$_} ne '' } @{ $o{extra_attrs} || [] };
        return requirement({ name => $reqname{$oid}, doorsId => $ob->{id}, text => $ob->{text}, title => $ob->{name}, vm => $ob->{vm}, attrs => \@attrs }, $style, $ind);
    };
    my %headings_with_reqs;
    my $walk; $walk = sub {                   # (nodes, indent, package path, used-names) -> lines; returns reqs below
        my ($nodes, $ind, $path, $used, $below) = @_;
        my @l;
        for my $nd (@$nodes) {
            my $oid = $nd->{oid};
            my $ob = defined $oid ? $obj->{$oid} : undef;
            my $k = _kind($ob);
            $placed{$oid} = 1 if defined $oid;
            if ($k eq 'heading') {
                $count{headings}++;
                my $b = $ob->{heading}; $b =~ s/\s+/ /g; $b =~ s/^ | $//g;
                my $nmv = $b; my $i = 1; $nmv = "$b " . ++$i while $used->{$nmv}; $used->{$nmv} = 1;
                my $sub = 0;
                my @in = $walk->($nd->{kids}, "$ind    ", [ @$path, name($nmv) ], {}, \$sub);
                $count{orphan_headings}++ unless $sub;
                push @l, "${ind}package " . name($nmv) . ' {', "$ind    // DOORS heading " . $ob->{id}, @in, "$ind}";
                $$below += $sub;
                next;
            }
            if ($k eq 'req') {
                push @l, $req_lines->($oid, $ind);
                $reqpkg{$oid} = [@$path]; $reqtop{$oid} = $cur_top;
                $$below++;
            } elsif ($k eq 'empty') {
                $count{empty}++;
                push @l, "$ind// TODO DOORS object $ob->{id} has neither text nor heading";
            } else {
                $count{missing}++;
                push @l, "$ind// TODO hierarchy points at object " . (defined $oid ? $oid : '?') . ', which is not in the export';
            }
            push @l, $walk->($nd->{kids}, $ind, $path, $used, $below) if @{ $nd->{kids} };
        }
        return @l;
    };
    my %top_used;
    my @tops;
    for my $sp (@{ $d->{specs} }) {
        my $b = defined $o{name} && @{ $d->{specs} } == 1 ? $o{name} : $sp->{name};
        my $nmv = $b; my $i = 1; $nmv = "$b " . ++$i while $top_used{$nmv}; $top_used{$nmv} = 1;
        my $below = 0;
        $cur_top = scalar @tops;
        my @body = $walk->($sp->{kids}, '    ', [ name($nmv) ], {}, \$below);
        push @tops, { name => $nmv, body => \@body };
    }
    my @unplaced = grep { !$placed{$_} } @{ $d->{order} };
    if (@unplaced) {
        my $nmv = (@tops ? $tops[0]{name} : 'Requirements') . ' unplaced';
        my $below = 0;
        $cur_top = scalar @tops;
        my @body = $walk->([ map { { oid => $_, kids => [] } } @unplaced ], '    ', [ name($nmv) ], {}, \$below);
        push @tops, { name => $nmv, body => \@body };
        $count{unplaced} = scalar @unplaced;
    }
    # links: in the package of the source requirement's top-level package, at its end
    my %lc;
    my $qual = sub { my ($oid) = @_; return join '::', @{ $reqpkg{$oid} } };
    for my $r (@{ $d->{relations} }) {
        my ($s, $t) = ($r->{src}, $r->{tgt});
        my $sk = defined $s ? _kind($obj->{$s}) : 'missing'; my $tk = defined $t ? _kind($obj->{$t}) : 'missing';
        my $ty = $r->{type} || '';
        my $cls = $ty =~ /deriv|refine/i ? 'derive' : $ty =~ /satisf/i ? 'satisfy' : $ty =~ /verif|test/i ? 'verify' : 'trace';
        my $ti = $sk eq 'req' ? $reqtop{$s} : $tk eq 'req' ? $reqtop{$t} : 0;
        my $tb = $tops[$ti];
        if ($sk ne 'req' || $tk ne 'req') {
            $lc{unresolved}++;
            push @{ $tb->{links} }, "    // TODO link $r->{id} ($ty): " . (defined $s ? $obj->{$s} ? $obj->{$s}{id} : $s : '?') . ' -> '
                . (defined $t ? $obj->{$t} ? $obj->{$t}{id} : $t : '?') . ' is not between two requirements';
            next;
        }
        for my $x ($s, $t) { $imports{$ti}{ $qual->($x) } = 1 if $reqtop{$x} != $ti || @{ $reqpkg{$x} } > 1 }
        my ($S, $T) = ($reqname{$s}, $reqname{$t});
        $lc{$cls}++;
        if ($cls eq 'derive') {
            $imports{$ti}{RequirementDerivation} = 1;
            push @{ $tb->{links} }, "    #derivation connection {", "        end #original ::> $T;", "        end #derive ::> $S;", "    }";
        } else {
            push @{ $tb->{links} }, "    dependency from $S to $T; // $cls" . ($ty ne '' && lc $ty ne $cls ? " ($ty)" : '');
        }
    }
    my $src = $d->{source};
    for my $i (0 .. $#tops) {
        my $tb = $tops[$i];
        my $self = name($tb->{name});
        my @imp = map { "    private import $_\::*;" } grep { $_ ne $self } sort keys %{ $imports{$i} || {} };
        my @l = ("// generated by reqif2sysml.pl from $src -- review before committing", 'package ' . name($tb->{name}) . ' {', @imp,
                 @{ $tb->{body} }, ($tb->{links} ? ('    // links (DOORS link modules)', @{ $tb->{links} }) : ()), '}');
        (my $seg = lc $tb->{name}) =~ s/[^a-z0-9]+/-/g; $seg =~ s/^-+|-+$//g; $seg = 'requirements' if $seg eq '';
        (my $pf = $tb->{name}) =~ s/[^A-Za-z0-9_.\-]+/_/g;
        my $fn = $layout; $fn =~ s/\{seg\}/$seg/g; $fn =~ s/\{pkg\}/$pf/g;
        $files{$fn} = join("\n", @l) . "\n";
    }
    $count{$_} ||= 0 for qw(requirements no_text with_vm without_vm headings orphan_headings empty missing unplaced);
    $lc{$_} ||= 0 for qw(derive satisfy verify trace unresolved);
    return { files => \%files, problems => check(\%files), reqs => { map { $_ => $reqname{$_} } keys %reqname },
             report => { source => $src, objects => $d->{spec_objects}, counts => \%count, links => \%lc, vm => \%vm_count,
                         relations => scalar @{ $d->{relations} } } };
}

sub report_text {
    my ($out) = @_;
    my $r = $out->{report}; my $c = $r->{counts}; my $k = $r->{links};
    my @l = ("reqif2sysml report: $r->{source}", '',
        sprintf('%-44s %6d', 'DOORS objects (C total: <SPEC-OBJECT> count)', $r->{objects}),
        sprintf('%-44s %6d', 'requirements (objects with text)', $c->{requirements}),
        sprintf('%-44s %6d', '  bare objects (an identifier, no attributes)', $c->{no_text}),
        sprintf('%-44s %6d', '  with a verification method', $c->{with_vm}),
        sprintf('%-44s %6d', '  without a verification method', $c->{without_vm}),
        sprintf('%-44s %6d', 'headings (section packages)', $c->{headings}),
        sprintf('%-44s %6d', '  orphan headings (no requirement below)', $c->{orphan_headings}),
        sprintf('%-44s %6d', 'empty objects (no text, no heading)', $c->{empty}),
        sprintf('%-44s %6d', 'objects in no specification', $c->{unplaced}),
        sprintf('%-44s %6d', 'hierarchy entries naming a missing object', $c->{missing}),
        sprintf('%-44s %6d', 'links', $r->{relations}),
        sprintf('  derive %d, satisfy %d, verify %d, trace %d, not between requirements %d', map { $k->{$_} } qw(derive satisfy verify trace unresolved)));
    push @l, 'verification methods: ' . join(', ', map { "$_ $r->{vm}{$_}" } sort keys %{ $r->{vm} }) if %{ $r->{vm} };
    push @l, '', 'files: ' . join(' ', sort keys %{ $out->{files} });
    push @l, 'self-check: ' . (@{ $out->{problems} } ? scalar(@{ $out->{problems} }) . ' problem(s)' : 'ok'), map { "  $_" } @{ $out->{problems} };
    return join("\n", @l) . "\n";
}

# ---- trace against a SysML v2 model directory (metrics C, F, G, I)
sub scan_model {
    my ($dir) = @_;
    my (%req, %by_doors, %sat, %ver);
    my @files;
    my $w; $w = sub {
        my ($d) = @_;
        opendir my $dh, $d or return;
        for my $e (sort grep { !/^\./ } readdir $dh) { my $p = "$d/$e"; if (-d $p) { $w->($p) } elsif ($e =~ /\.sysml$/) { push @files, $p } }
        closedir $dh;
    };
    $w->($dir);
    for my $f (@files) {
        open my $fh, '<', $f or next;
        my $cur;
        while (my $l = <$fh>) {
            $l =~ s{//.*}{};
            if ($l =~ /^\s*requirement\s+(?:def\s+)?(\w+)/ && $1 ne 'def') { $cur = $1; $req{$cur} = 1 }
            if ($l =~ /doorsId\s*(?::\s*\w+\s*)?=\s*"([^"]*)"/ && defined $cur) { $by_doors{$1}{$cur} = 1 }
            $sat{ (split /::/, $1)[-1] } = 1 if $l =~ /^\s*satisfy\s+(?:requirement\s+)?([\w:]+)/;
            $ver{ (split /::/, $1)[-1] } = 1 if $l =~ /^\s*verify\s+(?:requirement\s+)?([\w:]+)/;
        }
        close $fh;
    }
    return { files => scalar @files, req => \%req, by_doors => \%by_doors, sat => \%sat, ver => \%ver };
}

sub trace {
    my ($d, $out, $dir) = @_;
    my $m = scan_model($dir);
    my (@linked, @orphan, @unver, @both, @missing);
    my %doors;
    for my $oid (@{ $d->{order} }) {
        my $ob = $d->{objects}{$oid};
        next unless _kind($ob) eq 'req';
        $doors{ $ob->{id} } = 1;
        my %names = %{ $m->{by_doors}{ $ob->{id} } || {} };
        my $nm = $out->{reqs}{$oid};
        $names{$nm} = 1 if $m->{req}{$nm};
        if (!%names) { push @missing, $ob->{id}; push @orphan, $ob->{id}; push @unver, $ob->{id}; next }
        push @linked, $ob->{id};
        my $s = grep { $m->{sat}{$_} } keys %names;
        my $v = grep { $m->{ver}{$_} } keys %names;
        push @orphan, $ob->{id} unless $s;
        push @unver, $ob->{id} unless $v;
        push @both, $ob->{id} if $s && $v;
    }
    my $extra = grep { !$doors{$_} } keys %{ $m->{by_doors} };
    my $total = @linked + @missing;
    return { dir => $dir, files => $m->{files}, total => $total, linked => \@linked, missing => \@missing, orphan => \@orphan,
             unverified => \@unver, complete => \@both, extra => $extra };
}

sub trace_text {
    my ($t) = @_;
    my $pct = $t->{total} ? sprintf('%.1f', 100 * @{ $t->{complete} } / $t->{total}) : '0.0';
    my @l = ('', "trace against $t->{dir} ($t->{files} .sysml files)",
        sprintf('%-44s %12s', 'C requirements linked (doorsId in the model)', scalar(@{ $t->{linked} }) . ' of ' . $t->{total}),
        sprintf('%-44s %12d', 'F orphan requirements (nothing satisfies)', scalar @{ $t->{orphan} }),
        sprintf('%-44s %12d', 'G unverified requirements (no verify)', scalar @{ $t->{unverified} }),
        sprintf('%-44s %12s', 'I trace completeness (satisfied and verified)', "$pct%"),
        sprintf('%-44s %12d', 'doorsIds in the model but not in this export', $t->{extra}));
    push @l, 'not in the model: ' . join(' ', @{ $t->{missing} }) if @{ $t->{missing} };
    push @l, 'orphans: ' . join(' ', @{ $t->{orphan} }) if @{ $t->{orphan} };
    push @l, 'unverified: ' . join(' ', @{ $t->{unverified} }) if @{ $t->{unverified} };
    return join("\n", @l) . "\n";
}

1;
