package Xmi;
# SysML v1 XMI (Cameo Systems Modeler / MagicDraw "Eclipse UML2 (v5.x) XMI", XMI 2.5.1 / 2.1) -> SysML v2 text.
#
#   my $m   = Xmi::load($path);                         # parse + index (XmlLite tree, ids, stereotype applications)
#   my $out = Xmi::convert($m, req_style => 'def'|'usage', layout => '{seg}/{pkg}.sysml', name => 'Loose');
#   # $out = { files => { relpath => text }, report => {...}, problems => [ self-check ] }
#   print Xmi::report_text($out);
#   print Xmi::delta_text(Xmi::delta(Xmi::load($old), Xmi::load($new)));   # two drops of the same model: added, removed,
#                                                                       # changed by xmi:id; carried by the converter or manual
#   print Xmi::map_csv($m, $out);                    # the v1 -> v2 map: xmi_id,v1_type,v1_qualified_name,v2_qualified_name,v2_kind,file,line
#   my $i = Xmi::impact($delta, $model_dir, map => Xmi::read_map_csv($csv));   # what a delta touches in the government's
#   print Xmi::impact_text($i); print Xmi::impact_csv($i);                     # v2 model: requirements, verification
#   impact(..., changes => Xmi::read_changes_csv('drop/CHANGES.csv'))         # grouped by the prime's change requests
#                                                                       # cases, interfaces, allocations, hand edits to redo
#
# Mapping (SysML 1.x -> v2), one line each; everything else becomes a "// TODO <xmi:type> (xmi:id ...)" comment in
# the nearest converted owner and is listed in the report -- nothing is dropped silently:
#   Package/Model -> package (one file per top-level package; loose elements go to a package named after the model)
#   Class/Block/Component/Actor -> part def; InterfaceBlock (or a Class used only as a port type) -> port def;
#   ConstraintBlock -> constraint def (parameters; the expression is a TODO); Signal -> item def;
#   DataType/ValueType/PrimitiveType -> attribute def (UML/SysML primitives map to ScalarValues::*);
#   Enumeration -> enum def; Activity -> action def (parameters, call actions, control flows as first/then);
#   UseCase -> use case def (skeleton); Requirement (and Cameo's requirement kinds) -> requirement def with doc text
#   and doorsId (the SysML/Cameo id), verificationMethod (extendedRequirement verifyMethod), title (the 1.x name);
#   TestCase -> verification def; Property: composite Block-typed -> part, other Block-typed -> ref part,
#   value-typed or untyped -> attribute, Signal-typed -> item, FlowProperty -> in/out/inout feature;
#   Port/FlowPort/ProxyPort/FullPort -> port : [~]PortDef (atomic flow ports -> port { in attribute ... });
#   Connector -> connection NAME connect a.p to b.q (BindingConnector -> bind a = b); Generalization -> :>;
#   Satisfy -> satisfy R by X; Verify -> verify R inside the test case's verification def objective;
#   DeriveReqt -> #derivation connection { end #original ::> S; end #derive ::> D; };
#   Trace/Refine/Copy/Dependency/Usage/Realization/Abstraction -> dependency from A to B; Allocate -> allocate A to B;
#   ownedComment -> doc. Diagrams and tool extensions (xmi:Extension) are counted and skipped.
use strict;
use warnings;
use XmlLite;
use SysmlText qw(name ident str doc requirement check is_keyword layout_path);

our @IN_SCOPE = qw(Class Port Property Connector Activity);   # status-metrics Appendix A, metric A's v1 filter

my %PRIM = (real => 'ScalarValues::Real', integer => 'ScalarValues::Integer', boolean => 'ScalarValues::Boolean',
            string => 'ScalarValues::String', unlimitednatural => 'ScalarValues::Natural', natural => 'ScalarValues::Natural',
            number => 'ScalarValues::NumericalValue', complex => 'ScalarValues::Complex', double => 'ScalarValues::Real',
            float => 'ScalarValues::Real', int => 'ScalarValues::Integer', long => 'ScalarValues::Integer',
            short => 'ScalarValues::Integer', char => 'ScalarValues::String', bool => 'ScalarValues::Boolean');

my %REQ_STEREO = map { lc($_) => 1 } qw(Requirement extendedRequirement functionalRequirement interfaceRequirement
    performanceRequirement physicalRequirement designConstraint businessRequirement usabilityRequirement);
# stereotypes this converter understands (anything else applied to an element is reported and noted as a TODO)
my %KNOWN_STEREO = map { lc($_) => 1 } (keys %REQ_STEREO, qw(Block InterfaceBlock ConstraintBlock ValueType FlowPort
    ProxyPort FullPort FlowProperty Satisfy Verify DeriveReqt Trace Refine Copy Allocate TestCase BindingConnector
    NestedConnectorEnd Unit QuantityKind ParticipantProperty ConstraintProperty ElementPropertyPath));

sub xtype {                                   # the element's type, unprefixed: uml:Class -> Class
    my ($n) = @_;
    my $t = $n->{a}{'xmi:type'};
    if (!defined $t) { for my $k (keys %{ $n->{a} }) { if ($k =~ /^[^:]+:type$/) { $t = $n->{a}{$k}; last } } }
    $t = $n->{n} if !defined $t && ($n->{p} eq 'uml' || $n->{u} =~ m{/UML\b}i) && $n->{l} =~ /^(Model|Package|Profile)$/;
    return undef unless defined $t;
    $t =~ s/^.*://;
    return $t;
}

sub xid {
    my ($n) = @_;
    return $n->{a}{'xmi:id'} if defined $n->{a}{'xmi:id'};
    for my $k (keys %{ $n->{a} }) { return $n->{a}{$k} if $k =~ /^[^:]+:id$/ }
    return undef;
}

sub _idrefs {                                 # ids named by an attribute (space-separated) or by child elements
    my ($n, $what) = @_;
    my @ids;
    push @ids, split ' ', $n->{a}{$what} if defined $n->{a}{$what};
    for my $c (XmlLite::kids($n, $what)) {
        my $r = $c->{a}{'xmi:idref'}; $r = $c->{a}{idref} unless defined $r;
        push @ids, $r if defined $r;
        push @ids, 'href:' . $c->{a}{href} if !defined $r && defined $c->{a}{href};
    }
    return @ids;
}

sub load {
    my ($path) = @_;
    my $root = XmlLite::parse_file($path);
    (my $base = $path) =~ s{.*[/\\]}{}; $base =~ s/\.[^.]+$//;
    my %m = (path => $path, base => $base, root => $root, el => {}, order => [], st => {}, apps => [], ext => 0,
             parent => {}, anon => 0);
    my @content;
    if ($root->{l} eq 'XMI') {
        for my $c (XmlLite::kids($root)) {
            if ($c->{l} eq 'Extension' || $c->{l} eq 'Documentation') { $m{ext}++; next }
            my @base = grep { /^base_/ } keys %{ $c->{a} };
            if (@base && !defined xtype($c)) { push @{ $m{apps} }, $c; next }
            push @content, $c;
        }
    } else { @content = ($root) }
    $m{content} = \@content;
    my $walk; $walk = sub {
        my ($n, $parent) = @_;
        if ($n->{l} eq 'Extension') { $m{ext}++; return }
        my $t = xtype($n);
        my $id;
        if (defined $t) {
            $id = xid($n);
            $id = sprintf('anon_%d', ++$m{anon}) unless defined $id;
            $n->{id} = $id; $n->{t} = $t;
            $m{el}{$id} = $n;
            $m{parent}{$id} = $parent if defined $parent;
            push @{ $m{order} }, $id;
        }
        $walk->($_, defined $id ? $id : $parent) for XmlLite::kids($n);
    };
    $walk->($_, undef) for @content;
    # stereotype applications: <sysml:Block base_Class="id"/> etc. (any prefix; matched by local name)
    for my $a (@{ $m{apps} }) {
        for my $k (grep { /^base_/ } keys %{ $a->{a} }) {
            for my $tid (split ' ', $a->{a}{$k}) { $m{st}{$tid}{ lc $a->{l} } = $a }
        }
    }
    return \%m;
}

sub _sattr {                                  # a stereotype attribute, any case, attribute or child element
    my ($app, @names) = @_;
    for my $nm (@names) {
        for my $k (keys %{ $app->{a} }) { return $app->{a}{$k} if lc $k eq lc $nm }
        for my $c (XmlLite::kids($app)) { return XmlLite::text($c) if lc $c->{l} eq lc $nm }
    }
    return undef;
}

# ---------------------------------------------------------------------------------------------------------------
sub convert {
    my ($m, %o) = @_;
    my $style = $o{req_style} || 'def';
    my $layout = $o{layout} || '{seg}/{pkg}.sysml';
    my $el = $m->{el}; my $st = $m->{st};
    my (%status, %kind, %nm, %owner, %todo, %out, @unmapped, %unres, %imports, %stereo_todo);
    my $has = sub { my ($id, $s) = @_; return $st->{$id} && $st->{$id}{ lc $s } };
    my $is_req = sub { my ($id) = @_; return 0 unless $st->{$id}; return scalar grep { $REQ_STEREO{$_} } keys %{ $st->{$id} } };
    my $req_app = sub { my ($id) = @_; for my $k (sort keys %{ $st->{$id} || {} }) { return $st->{$id}{$k} if $REQ_STEREO{$k} } return undef };

    # ---- what each typed element is used as (classes typing ports become port defs)
    my (%port_typed, %part_typed);
    for my $id (@{ $m->{order} }) {
        my $n = $el->{$id};
        next unless $n->{t} eq 'Port' || $n->{t} eq 'Property';
        my ($tid) = _idrefs($n, 'type');
        next unless defined $tid && $el->{$tid};
        if ($n->{t} eq 'Port') { $port_typed{$tid} = 1 } else { $part_typed{$tid} = 1 }
    }
    my $lib_of = sub {                        # a primitive's library name, or undef
        my ($nmv) = @_;
        return undef unless defined $nmv;
        (my $k = lc $nmv) =~ s/.*[#.\/:]//;
        return $PRIM{$k};
    };
    for my $id (@{ $m->{order} }) {
        my $n = $el->{$id}; my $t = $n->{t};
        my $k;
        if    ($t =~ /^(Model|Package)$/) { $k = 'package' }
        elsif ($t eq 'Class' || $t eq 'Component' || $t eq 'Actor') {
            $k = $is_req->($id) ? 'req'
               : $has->($id, 'TestCase') ? 'verif'
               : $has->($id, 'InterfaceBlock') ? 'portdef'
               : $has->($id, 'ConstraintBlock') ? 'constraintdef'
               : ($port_typed{$id} && !$part_typed{$id}) ? 'portdef' : 'partdef';
        }
        elsif ($t eq 'Activity') { $k = $has->($id, 'TestCase') ? 'verif' : 'actiondef' }
        elsif ($t eq 'Signal') { $k = 'itemdef' }
        elsif ($t eq 'PrimitiveType' && $lib_of->($n->{a}{name})) { $k = 'libtype' }
        elsif ($t =~ /^(DataType|PrimitiveType)$/) { $k = 'attrdef' }
        elsif ($t eq 'Enumeration') { $k = 'enumdef' }
        elsif ($t eq 'UseCase') { $k = 'usecasedef' }
        elsif ($t =~ /^(Abstraction|Dependency|Usage|Realization)$/) { $k = 'rel' }
        elsif ($t eq 'Association') { $k = 'assoc' }
        elsif ($t eq 'Property') { $k = 'prop' }
        elsif ($t eq 'Port') { $k = 'port' }
        elsif ($t eq 'Connector') { $k = 'conn' }
        elsif ($t eq 'Comment') { $k = 'comment' }
        elsif ($t eq 'EnumerationLiteral') { $k = 'literal' }
        elsif ($t eq 'Parameter') { $k = 'param' }
        else { $k = 'other' }
        $kind{$id} = $k;
    }
    my %NS = map { $_ => 1 } qw(package partdef portdef constraintdef verif actiondef itemdef attrdef enumdef req usecasedef);

    # ---- names: one per emitted element, unique within its owning namespace; requirements by their id
    my $LOOSE = '__loose__';
    my @top;                                  # top-level package ids, in order (+ $LOOSE when needed)
    my $model_name;
    my $nsowner = sub {                       # the namespace an element is emitted in
        my ($id) = @_;
        my $p = $m->{parent}{$id};
        while (defined $p) {
            my $pk = $kind{$p};
            if ($pk eq 'package' && $el->{$p}{t} eq 'Model' && !defined $m->{parent}{$p}) { return $LOOSE }
            return $p if $NS{$pk} && !($pk eq 'req' && $kind{$id} eq 'req');   # nested requirements are hoisted
            $p = $m->{parent}{$p};
        }
        return $LOOSE;
    };
    for my $id (@{ $m->{order} }) {
        my $n = $el->{$id};
        if ($kind{$id} eq 'package' && $n->{t} eq 'Model' && !defined $m->{parent}{$id}) {
            $model_name = $n->{a}{name}; $kind{$id} = 'model'; $status{$id} = 'folded'; next;
        }
        $owner{$id} = $nsowner->($id);
    }
    my %used;                                 # namespace -> { name => 1 }
    my %count_name;
    my $assign = sub {
        my ($id, $want) = @_;
        my $o = $owner{$id};
        my $b = $want; my $i = 1;
        $want = $b . '_' . ++$i while $used{$o}{$want};
        $used{$o}{$want} = 1;
        $nm{$id} = $want; $count_name{$want}++;
    };
    for my $id (@{ $m->{order} }) {
        next if $kind{$id} eq 'model';
        my $n = $el->{$id};
        my $raw = $n->{a}{name};
        if (!defined $raw || $raw eq '') { my $c = XmlLite::kid($n, 'name'); $raw = XmlLite::text($c) if $c }
        if ($kind{$id} eq 'req') {
            my $app = $req_app->($id);
            my $rid = _sattr($app, 'id');
            $n->{doorsId} = $rid;
            $assign->($id, ident(defined $rid && $rid ne '' ? $rid : defined $raw && $raw ne '' ? $raw : $id));
            $n->{raw} = $raw;
            next;
        }
        if ((!defined $raw || $raw eq '') && $kind{$id} =~ /^(prop|port)$/) {   # unnamed part: lcfirst(type name)
            my ($tid) = _idrefs($n, 'type');
            if (defined $tid && $el->{$tid} && defined $el->{$tid}{a}{name}) { ($raw = $el->{$tid}{a}{name}) =~ s/^(.)/\l$1/ }
        }
        $raw = ident($id) if !defined $raw || $raw eq '';
        $raw =~ s/^\s+|\s+$//g;
        $assign->($id, $raw);
    }
    my @tl = grep { defined $owner{$_} && $owner{$_} eq $LOOSE && $kind{$_} eq 'package' } @{ $m->{order} };
    my @loose = grep { defined $owner{$_} && $owner{$_} eq $LOOSE && $kind{$_} ne 'package' } @{ $m->{order} };
    my $loose_name = defined $o{name} ? $o{name} : defined $model_name && $model_name ne '' ? $model_name : $m->{base};
    if (grep { $nm{$_} eq $loose_name } @tl) { $loose_name .= '_loose' }
    @top = (@tl, (@loose ? ($LOOSE) : ()));
    $nm{$LOOSE} = $loose_name; $kind{$LOOSE} = 'package';

    my $N = sub { my ($id) = @_; return name($nm{$id}) };   # the printed name
    my $chain = sub {                         # [ns ids from the top-level package down to and including $id]
        my ($id) = @_;
        my @c = ($id);
        while (1) {
            my $o = $owner{ $c[0] };
            last if !defined $o || $c[0] eq $LOOSE;
            last if $o eq $LOOSE && $kind{ $c[0] } eq 'package';   # a top-level package
            unshift @c, $o;
            last if $o eq $LOOSE;
        }
        return \@c;
    };
    my $qualified = sub { my ($id) = @_; my $c = $chain->($id); return join '::', map { name($nm{$_}) } @$c };
    my $topof = sub { return $chain->($_[0])[0] };
    my %map;                                  # xmi:id -> { kind, q }: the v2 line each element is written to (for --map / --impact)
    my $tag = sub {                           # tag(id, v2 kind, v2 qualified name, lines): mark the first line with the element's id
        my ($id, $kind, $q, @l) = @_;
        return wantarray ? @l : $l[0] unless defined $id && @l;
        $map{$id} //= { kind => $kind, q => $q };
        $l[0] = "\x01$id\x01$l[0]";
        return wantarray ? @l : $l[0];
    };
    my $ref; $ref = sub {                           # ref($ctx_ns, $target) -> how to name $target from inside $ctx_ns
        my ($ctx, $tid) = @_;
        return undef unless defined $tid && defined $nm{$tid} && $kind{$tid} ne 'libtype';
        my $o = $owner{$tid};
        my %anc = map { $_ => 1 } @{ $chain->($ctx) };
        return $N->($tid) if $anc{$o};
        if ($kind{$o} ne 'package') {          # a member of a definition: Def::member, the Def named as usual
            my $d = $ref->($ctx, $o);
            return defined $d ? "$d\::" . $N->($tid) : $qualified->($tid);
        }
        if ($kind{$o} eq 'package' && $count_name{ $nm{$tid} } == 1) {
            $imports{ $topof->($ctx) }{ $qualified->($o) } = 1 if $o ne $LOOSE || $topof->($ctx) ne $LOOSE;
            return $N->($tid);
        }
        return $qualified->($tid);
    };
    my $typeref = sub {                       # ($ctx, $node) -> (typestring|undef, target id|undef, comment)
        my ($ctx, $n) = @_;
        my ($tid) = _idrefs($n, 'type');
        return (undef, undef, '') unless defined $tid;
        if ($tid =~ /^href:(.*)/) {
            my $h = $1; my $lib = $lib_of->($h);
            return ($lib, undef, '') if $lib;
            $unres{$h}++;
            return (undef, undef, " // TODO type $h not resolved");
        }
        my $t = $el->{$tid};
        return (undef, undef, " // TODO type $tid not in this file") unless $t;
        return ($lib_of->($t->{a}{name}), $tid, '') if $kind{$tid} eq 'libtype';
        return ($ref->($ctx, $tid), $tid, '');
    };
    my $mult = sub {
        my ($n) = @_;
        my ($lo, $hi) = (XmlLite::kid($n, 'lowerValue'), XmlLite::kid($n, 'upperValue'));
        return '' unless $lo || $hi;
        my $l = $lo ? (defined $lo->{a}{value} ? $lo->{a}{value} : 0) : 1;
        my $h = $hi ? (defined $hi->{a}{value} ? $hi->{a}{value} : 0) : 1;
        $h = '*' if $h eq '-1';
        return '' if $h eq '0' || ($l eq '1' && $h eq '1');
        return $l eq $h ? "[$l]" : "[$l..$h]";
    };
    my $fold = sub { my ($n) = @_; my $w; $w = sub { my $x = shift; $status{ $x->{id} } ||= 'folded' if $x->{id}; $w->($_) for XmlLite::kids($x) }; $w->($n) };
    my $value = sub {                         # a defaultValue -> SysML expression or undef
        my ($ctx, $n) = @_;
        my $d = XmlLite::kid($n, 'defaultValue') or return undef;
        $fold->($d);
        my $t = $d->{t} || '';
        my $v = $d->{a}{value};
        return str(defined $v ? $v : '') if $t eq 'LiteralString';
        return (defined $v ? $v : 0) if $t =~ /^Literal(Integer|Real|UnlimitedNatural)$/;
        return ((defined $v && $v eq 'true') ? 'true' : 'false') if $t eq 'LiteralBoolean';
        if ($t eq 'InstanceValue') { my ($i) = _idrefs($d, 'instance'); return $i && $nm{$i} ? $ref->($ctx, $i) : undef }
        return undef;
    };
    my $todo = sub {                          # a TODO line for an element that is not converted
        my ($id, $why, $ind) = @_;
        my $n = $el->{$id};
        $status{$id} = 'todo';
        my $nmv = defined $n->{a}{name} ? " '$n->{a}{name}'" : '';
        push @unmapped, { id => $id, type => $n->{t}, name => (defined $n->{a}{name} ? $n->{a}{name} : ''), why => $why };
        my $w; $w = sub { my $x = shift; $status{ $x->{id} } ||= 'todo-child' if $x->{id}; $w->($_) for XmlLite::kids($x) }; $w->($_) for XmlLite::kids($n);
        return scalar $tag->($id, 'todo', undef, "$ind// TODO uml:$n->{t}$nmv (xmi:id $id): $why");
    };
    my $stereo_notes = sub {                  # TODO lines for stereotypes we do not understand
        my ($id, $ind) = @_;
        my @l;
        for my $s (sort keys %{ $st->{$id} || {} }) {
            next if $KNOWN_STEREO{$s};
            my $app = $st->{$id}{$s};
            $stereo_todo{ $app->{l} }++;
            push @l, "$ind// TODO stereotype $app->{n} on this element (xmi:id " . (xid($app) || '?') . ') not converted';
        }
        return @l;
    };
    my $docs = sub {
        my ($n, $ind) = @_;
        my @l;
        for my $c (XmlLite::kids($n, 'ownedComment')) {
            my $b = defined $c->{a}{body} ? $c->{a}{body} : do { my $k = XmlLite::kid($c, 'body'); $k ? XmlLite::text($k) : '' };
            push @l, $tag->($c->{id}, 'doc', $n->{id} && $nm{ $n->{id} } ? $qualified->($n->{id}) : undef, doc($b, $ind));
            $status{ $c->{id} } = 'mapped' if $c->{id}; $out{doc}++;
        }
        return @l;
    };
    my $gens = sub {
        my ($ctx, $n) = @_;
        my @g;
        for my $g (XmlLite::kids($n, 'generalization')) {
            $fold->($g);
            my ($gid) = _idrefs($g, 'general');
            my $r = defined $gid && $gid =~ /^href:(.*)/ ? $lib_of->($1) : defined $gid && $kind{$gid} && $kind{$gid} eq 'libtype' ? $lib_of->($el->{$gid}{a}{name}) : $ref->($ctx, $gid);
            push @g, $r if defined $r;
        }
        return @g ? ' :> ' . join(', ', @g) : '';
    };

    # relationship pre-pass: verify lists per test case, which abstractions are folded into them
    my (%verifies, %verif_rel);
    for my $id (@{ $m->{order} }) {
        next unless $kind{$id} eq 'rel' && $has->($id, 'Verify');
        my $n = $el->{$id};
        my @c = _idrefs($n, 'client'); my @s = _idrefs($n, 'supplier');
        for my $c (@c) { push @{ $verifies{$c} }, @s }
        $verif_rel{$id} = [ \@c, \@s ];
    }

    my $emit; my $emit_body;
    my $prop_line = sub {
        my ($ctx, $id, $ind) = @_;
        my $n = $el->{$id};
        $fold->($_) for XmlLite::kids($n);
        my ($ty, $tid, $cmt) = $typeref->($ctx, $n);
        my $tk = defined $tid ? $kind{$tid} : '';
        my $dir = '';
        if (my $fp = $has->($id, 'FlowProperty')) { my $d = _sattr($fp, 'direction'); $dir = (defined $d ? $d : 'inout') . ' ' }
        my $kw;
        if ($tk =~ /^(partdef|portdef|constraintdef|usecasedef|verif)$/) {
            $kw = $dir ? 'item' : (($n->{a}{aggregation} || '') eq 'composite' ? 'part' : 'ref part');
        }
        elsif ($tk eq 'itemdef') { $kw = 'item' }
        elsif ($tk eq 'req') { $kw = 'requirement' }
        elsif ($tk eq 'actiondef') { $kw = 'action' }
        else { $kw = 'attribute' }
        $kw = "derived $kw" if ($n->{a}{isDerived} || '') eq 'true';
        my $v = $value->($ctx, $n);
        $out{$kw =~ /(\w+(?: part)?)$/ ? $1 : $kw}++;
        $status{$id} = 'mapped';
        (my $bk = $kw) =~ s/^derived //;
        return scalar $tag->($id, $bk, $qualified->($ctx) . '::' . $N->($id),
            "$ind$dir$kw " . $N->($id) . (defined $ty ? " : $ty" : '') . $mult->($n) . (defined $v ? " = $v" : '') . ";$cmt");
    };
    my $port_line = sub {
        my ($ctx, $id, $ind) = @_;
        my $n = $el->{$id};
        $fold->($_) for XmlLite::kids($n);
        my ($ty, $tid, $cmt) = $typeref->($ctx, $n);
        my $fp = $has->($id, 'FlowPort');
        my $conj = ($n->{a}{isConjugated} || '') eq 'true' || ($fp && (_sattr($fp, 'isConjugated') || '') eq 'true');
        $status{$id} = 'mapped'; $out{port}++;
        my $tk = defined $tid ? $kind{$tid} : (defined $ty ? 'lib' : '');
        if ($tk =~ /^(attrdef|enumdef|lib|itemdef)$/) {        # an atomic flow port: the flowing thing goes inside
            my $d = $fp ? (_sattr($fp, 'direction') || 'inout') : 'inout';
            my $what = $tk eq 'itemdef' ? 'item' : 'attribute';
            return scalar $tag->($id, 'port', $qualified->($ctx) . '::' . $N->($id), "${ind}port " . $N->($id) . $mult->($n) . " { $d $what flowValue : $ty; }$cmt");
        }
        my $note = '';
        if ($tk eq 'partdef') { $note = ' // TODO the type is a part def (also used as a part); give the port a port def' }
        return scalar $tag->($id, 'port', $qualified->($ctx) . '::' . $N->($id), "${ind}port " . $N->($id) . (defined $ty ? ' : ' . ($conj ? '~' : '') . $ty : '') . $mult->($n) . ";$cmt$note");
    };
    my $end_path = sub {
        my ($ctx, $e) = @_;
        my ($role) = _idrefs($e, 'role');
        return undef unless defined $role && $nm{$role};
        my @p;
        my $ne = $e->{id} ? $st->{ $e->{id} }{nestedconnectorend} : undef;
        if ($ne) { push @p, grep { defined } map { $nm{$_} ? $N->($_) : undef } _idrefs($ne, 'propertyPath') }
        elsif (my ($pwp) = _idrefs($e, 'partWithPort')) { push @p, $N->($pwp) if $nm{$pwp} }
        push @p, $N->($role);
        return join '.', @p;
    };
    my $conn_line = sub {
        my ($ctx, $id, $ind) = @_;
        my $n = $el->{$id};
        my @e = XmlLite::kids($n, 'end');
        my @p = map { $end_path->($ctx, $_) } @e;
        return $todo->($id, 'connector without two resolvable ends', $ind) if @p != 2 || grep { !defined } @p;
        $fold->($_) for XmlLite::kids($n);
        $status{$id} = 'mapped';
        if ($has->($id, 'BindingConnector')) { $out{bind}++; return scalar $tag->($id, 'bind', $qualified->($ctx), "${ind}bind $p[0] = $p[1];") }
        $out{connection}++;
        my $named = defined $n->{a}{name} && $n->{a}{name} ne '';
        return scalar $tag->($id, 'connection', $qualified->($ctx) . ($named ? '::' . $N->($id) : ''), "${ind}connection " . ($named ? $N->($id) . ' ' : '') . "connect $p[0] to $p[1];");
    };
    my $rel_lines = sub {
        my ($ctx, $id, $ind) = @_;
        my $n = $el->{$id};
        return () if $verif_rel{$id} && grep { $kind{$_} && $kind{$_} eq 'verif' } @{ $verif_rel{$id}[0] };  # emitted inside the test case
        my @c = _idrefs($n, 'client'); my @s = _idrefs($n, 'supplier');
        my @bad = grep { !defined $nm{$_} } @c, @s;
        return $todo->($id, 'client or supplier not converted (' . join(' ', @bad) . ')', $ind) if @bad || !@c || !@s;
        $fold->($_) for XmlLite::kids($n);
        $status{$id} = 'mapped';
        my @l;
        for my $c (@c) {
            for my $s (@s) {
                my ($C, $S) = ($ref->($ctx, $c), $ref->($ctx, $s));
                if ($has->($id, 'Satisfy')) { push @l, "${ind}satisfy $S by $C;"; $out{satisfy}++ }
                elsif ($has->($id, 'Verify')) {
                    my $vn = ident($nm{$c} . '_verification');
                    $vn .= '_' . ++$used{$ctx}{"$vn#"} while $used{$ctx}{$vn};
                    $used{$ctx}{$vn} = 1;
                    push @l, "${ind}verification def $vn {", "$ind    // verified by $C", "$ind    objective {", "$ind        verify $S;", "$ind    }", "$ind}";
                    $out{verify}++; $out{'verification def'}++;
                }
                elsif ($has->($id, 'DeriveReqt')) {
                    $imports{ $topof->($ctx) }{RequirementDerivation} = 1;
                    push @l, "${ind}#derivation connection {", "$ind    end #original ::> $S;", "$ind    end #derive ::> $C;", "$ind}";
                    $out{derivation}++;
                }
                elsif ($has->($id, 'Allocate')) { push @l, "${ind}allocate $C to $S;"; $out{allocate}++ }
                else {
                    my ($why) = grep { $has->($id, $_) } qw(Trace Refine Copy);
                    $why = lc($why || $n->{t});
                    my $named = defined $n->{a}{name} && $n->{a}{name} ne '';
                    push @l, "${ind}dependency " . ($named ? $N->($id) . ' ' : '') . "from $C to $S; // $why";
                    $out{dependency}++;
                }
            }
        }
        my ($rk) = grep { $has->($id, $_) } qw(Satisfy Verify DeriveReqt Allocate);
        my %rkind = (Satisfy => 'satisfy', Verify => 'verification def', DeriveReqt => 'derivation', Allocate => 'allocate');
        return $tag->($id, $rk ? $rkind{$rk} : 'dependency', $qualified->($ctx), @l);
    };
    my $activity_lines = sub {                # parameters, nodes and edges of an Activity
        my ($ctx, $id, $ind) = @_;
        my $n = $el->{$id};
        my @l;
        my %nodename;
        for my $p (XmlLite::kids($n, 'ownedParameter')) {
            $fold->($_) for XmlLite::kids($p);
            my $d = $p->{a}{direction} || 'in'; $d = 'out' if $d eq 'return';
            my ($ty, undef, $cmt) = $typeref->($ctx, $p);
            push @l, scalar $tag->($p->{id}, 'parameter', $qualified->($ctx) . '::' . $N->($p->{id}), "$ind$d " . $N->($p->{id}) . (defined $ty ? " : $ty" : '') . $mult->($p) . ";$cmt");
            $status{ $p->{id} } = 'mapped'; $out{parameter}++;
        }
        for my $c (XmlLite::kids($n, 'node')) {
            my $t = $c->{t} || '';
            if ($t =~ /^(InitialNode)$/) { $nodename{ $c->{id} } = 'start'; $status{ $c->{id} } = 'folded'; next }
            if ($t =~ /^(ActivityFinalNode|FlowFinalNode)$/) { $nodename{ $c->{id} } = 'done'; $status{ $c->{id} } = 'folded'; next }
            if ($t eq 'ActivityParameterNode') { $status{ $c->{id} } = 'folded'; next }
            if ($t =~ /^(CallBehaviorAction|OpaqueAction|CallOperationAction)$/) {
                my ($b) = _idrefs($c, 'behavior');
                my $bt = defined $b && $nm{$b} ? ' : ' . $ref->($ctx, $b) : '';
                push @l, scalar $tag->($c->{id}, 'action', $qualified->($ctx) . '::' . $N->($c->{id}), "${ind}action " . $N->($c->{id}) . "$bt;");
                $nodename{ $c->{id} } = $N->($c->{id});
                $status{ $c->{id} } = 'mapped'; $out{action}++;
                push @l, map { $todo->($_->{id}, 'pin (object flow) not converted', $ind) } grep { $_->{id} } XmlLite::kids($c);
                next;
            }
            push @l, $todo->($c->{id}, 'activity node not converted', $ind) if $c->{id};
        }
        for my $c (XmlLite::kids($n, 'edge')) {
            my ($s) = _idrefs($c, 'source'); my ($t) = _idrefs($c, 'target');
            if (($c->{t} || '') eq 'ControlFlow' && defined $s && defined $t && $nodename{$s} && $nodename{$t}) {
                $fold->($_) for XmlLite::kids($c);
                push @l, scalar $tag->($c->{id}, 'succession', $qualified->($ctx), "${ind}first $nodename{$s} then $nodename{$t};");
                $status{ $c->{id} } = 'mapped'; $out{succession}++;
                next;
            }
            push @l, $todo->($c->{id}, 'activity edge not converted (object flow, or an end that is a decision/fork/pin)', $ind) if $c->{id};
        }
        return @l;
    };
    $emit_body = sub {                        # the members of namespace $id (its child nodes, in order)
        my ($id, $ind) = @_;
        my $n = $el->{$id};
        my @l;
        for my $c (XmlLite::kids($n)) {
            next unless $c->{id};
            my $cid = $c->{id};
            next if $status{$cid};
            my $k = $kind{$cid};
            next if $k eq 'comment' && $c->{l} eq 'ownedComment';        # done by $docs
            next if $c->{l} =~ /^(generalization|ownedParameter|node|edge|lowerValue|upperValue|defaultValue)$/ && $NS{ $kind{$id} };
            if ($k eq 'req' && $owner{$cid} ne $id) { next }                 # hoisted; emitted after its parent
            if    ($k eq 'prop')   { push @l, $prop_line->($id, $cid, $ind) }
            elsif ($k eq 'port')   { push @l, $port_line->($id, $cid, $ind) }
            elsif ($k eq 'conn')   { push @l, $conn_line->($id, $cid, $ind) }
            elsif ($k eq 'rel')    { push @l, $rel_lines->($id, $cid, $ind) }
            elsif ($k eq 'literal') {
                if ($kind{$id} eq 'enumdef') { push @l, scalar $tag->($cid, 'enum', $qualified->($id) . '::' . $N->($cid), "${ind}enum " . $N->($cid) . ';'); $status{$cid} = 'mapped'; $out{'enum'}++; $fold->($_) for XmlLite::kids($c) }
                else { push @l, $todo->($cid, 'literal outside an enumeration', $ind) }
            }
            elsif ($k eq 'assoc')  { $fold->($c) }
            elsif ($k eq 'libtype') { $fold->($c) }
            elsif ($k eq 'comment') { push @l, $tag->($cid, 'comment', $qualified->($id), "${ind}comment ") . do { my $b = defined $c->{a}{body} ? $c->{a}{body} : ''; my @d = doc($b, ''); $d[0] =~ s/^doc //; "@d" }; $status{$cid} = 'mapped'; $out{comment}++ }
            elsif ($NS{$k})        { push @l, $emit->($cid, $ind) }
            elsif ($c->{t} =~ /^(PackageImport|ElementImport|ProfileApplication)$/) { $fold->($c) }   # library/profile imports
            else                   { push @l, $todo->($cid, $c->{t} eq 'Constraint' ? 'constraint: ' . _constraint($c) : 'no SysML v2 mapping in this converter', $ind) }
        }
        return @l;
    };
    $emit = sub {                             # a namespace element: package or definition
        my ($id, $ind) = @_;
        my $n = $el->{$id};
        my $k = $kind{$id};
        $status{$id} = 'mapped';
        my @b;                                # body lines (one level in)
        my $in = "$ind    ";
        push @b, $stereo_notes->($id, $in);
        if ($k eq 'req') {
            $fold->($_) for grep { !$kind{ $_->{id} || '' } || $kind{ $_->{id} } ne 'req' } XmlLite::kids($n);
            my $app = $req_app->($id);
            my $text = _sattr($app, 'text');
            my @d = map { defined $_->{a}{body} ? $_->{a}{body} : '' } XmlLite::kids($n, 'ownedComment');
            $out{doc} += @d;
            $text = join("\n\n", grep { defined && /\S/ } $text, @d);
            my %skip = map { $_ => 1 } qw(id text verifymethod);
            my @attrs = map { [ $_, $app->{a}{$_} ] } grep { !/^(xmi:|base_)/ && !$skip{ lc $_ } } sort keys %{ $app->{a} };
            my $title = $n->{raw};
            $title = undef if defined $title && $title eq $nm{$id};
            $out{ $style eq 'usage' ? 'requirement' : 'requirement def' }++;
            my @l = $tag->($id, $style eq 'usage' ? 'requirement' : 'requirement def', $qualified->($id),
                           requirement({ name => $N->($id), doorsId => $n->{doorsId}, text => $text, title => $title,
                                  vm => _sattr($app, 'verifyMethod'), attrs => \@attrs, body => [ map { (my $x = $_) =~ s/^\Q$in\E//; $x } @b ] }, $style, $ind));
            # hoisted sub-requirements follow their parent
            push @l, $emit->($_->{id}, $ind) for grep { $_->{id} && $kind{ $_->{id} } eq 'req' && !$status{ $_->{id} } } XmlLite::kids($n);
            return @l;
        }
        my %kw = (package => 'package', partdef => 'part def', portdef => 'port def', constraintdef => 'constraint def',
                  verif => 'verification def', actiondef => 'action def', itemdef => 'item def', attrdef => 'attribute def',
                  enumdef => 'enum def', usecasedef => 'use case def');
        my $head = $kw{$k} . ' ' . $N->($id);
        $head .= $gens->($id, $n) unless $k eq 'package';
        $out{ $kw{$k} }++;
        push @b, $docs->($n, $in);
        if ($k eq 'attrdef' && (my $vt = $has->($id, 'ValueType'))) {
            my ($u) = _idrefs($vt, 'unit');
            if (defined $u) {
                my $un = $el->{$u} && defined $el->{$u}{a}{name} ? $el->{$u}{a}{name} : $u;
                push @b, "$in// SysML 1.x unit: $un -- specialize an ISQ quantity value by hand";
            }
        }
        if ($k eq 'verif' && $verifies{$id}) {
            my %rel_of;                       # requirement id -> the Verify relationship that names it
            for my $r (sort keys %verif_rel) { next unless grep { $_ eq $id } @{ $verif_rel{$r}[0] }; $rel_of{$_} //= $r for @{ $verif_rel{$r}[1] } }
            push @b, "${in}objective {", (map { scalar $tag->($rel_of{$_}, 'verify', $qualified->($id), "$in    verify " . ($ref->($id, $_) || "TODO_$_") . ';') } grep { $nm{$_} } @{ $verifies{$id} }), "$in}";
            $out{verify} += grep { $nm{$_} } @{ $verifies{$id} };
            for my $r (keys %verif_rel) { if (grep { $_ eq $id } @{ $verif_rel{$r}[0] }) { $status{$r} = 'mapped'; $fold->($_) for XmlLite::kids($el->{$r}) } }
        }
        if ($k eq 'constraintdef') { push @b, "$in// TODO constraint expression (parametrics) not converted" }
        push @b, $activity_lines->($id, $id, $in) if $n->{t} eq 'Activity';
        push @b, $emit_body->($id, $in);
        if ($k eq 'package') {                # imports go first; filled in after the whole tree is emitted
            unshift @b, "$in\x00IMPORTS $id";
        }
        return ($tag->($id, $kw{$k}, $qualified->($id), "$ind$head;")) if !@b;
        return ($tag->($id, $kw{$k}, $qualified->($id), "$ind$head {"), @b, "$ind}");
    };

    # ---- emit each top-level package
    my %files; my @layout_notes;
    for my $tp (@top) {
        my @body;
        if ($tp eq $LOOSE) {
            $status{$LOOSE} = 'mapped';
            my @b = ("    \x00IMPORTS $LOOSE");
            for my $id (@loose) {
                next if $status{$id};
                my $k = $kind{$id};
                if    ($k eq 'prop') { push @b, $prop_line->($LOOSE, $id, '    ') }
                elsif ($k eq 'port') { push @b, $port_line->($LOOSE, $id, '    ') }
                elsif ($k eq 'conn') {
                    my @e = XmlLite::kids($el->{$id}, 'end');
                    if (@e) { push @b, $conn_line->($LOOSE, $id, '    ') }
                    else { $status{$id} = 'mapped'; $out{connection}++; push @b, '    connection ' . $N->($id) . ';' }
                }
                elsif ($k eq 'rel') { push @b, $rel_lines->($LOOSE, $id, '    ') }
                elsif ($k eq 'assoc' || $k eq 'libtype' || $el->{$id}{t} =~ /^(PackageImport|ElementImport|ProfileApplication)$/) { $fold->($el->{$id}) }
                elsif ($k eq 'comment') {
                    my $c = $el->{$id};
                    my $bt = defined $c->{a}{body} ? $c->{a}{body} : do { my $x = XmlLite::kid($c, 'body'); $x ? XmlLite::text($x) : '' };
                    my @d = doc($bt, ''); $d[0] =~ s/^doc //;
                    push @b, '    comment ' . ($c->{a}{name} ? $N->($id) . ' ' : '') . join("\n    ", @d);
                    $status{$id} = 'mapped'; $out{comment}++;
                }
                elsif ($NS{$k}) { push @b, $emit->($id, '    ') }
                else { push @b, $todo->($id, 'no SysML v2 mapping in this converter', '    ') }
            }
            $out{package}++;
            @body = ('package ' . name($loose_name) . ' {', @b, '}');
        } else {
            @body = $emit->($tp, '');
        }
        my $txt = join("\n", @body) . "\n";
        my $fn = $layout;
        my $pn = $nm{$tp}; (my $seg = lc $pn) =~ s/[^a-z0-9]+/-/g; $seg =~ s/^-+|-+$//g; $seg = 'model' if $seg eq '';
        (my $pf = $pn) =~ s/[^A-Za-z0-9_.\-]+/_/g;
        $fn =~ s/\{seg\}/$seg/g; $fn =~ s/\{pkg\}/$pf/g;
        my $note; ($fn, $note) = layout_path($o{layout_map}, $pn, $pf, $fn);
        push @layout_notes, $note if defined $note;
        if ($files{$fn}) { push @layout_notes, "layout map: $pn and another package both go to $fn; $pn written to " . ($fn =~ s/\.sysml$/_$pf.sysml/r); $fn =~ s/\.sysml$/_$pf.sysml/ }
        $files{$fn} = { tp => $tp, text => $txt };
    }
    # anything typed that nothing reached: a TODO at the end of the first file, never silently dropped
    my @missed = grep { !$status{$_} } @{ $m->{order} };
    if (@missed && @top) {
        my ($f0) = sort keys %files;
        my $t = $files{$f0}{text}; $t =~ s/\}\n\z//;
        $t .= "    // elements not reached by the converter (owner not converted):\n";
        $t .= $todo->($_, 'owner not converted', '    ') . "\n" for @missed;
        $files{$f0}{text} = "$t}\n";
    }
    for my $f (values %files) {               # fill in the import lines
        $f->{text} =~ s{^([ ]*)\x00IMPORTS (\S+)\n}{
            my ($i, $p) = ($1, $2);
            my $top = $topof->($p);
            $p eq $top ? join('', map { "${i}private import $_\::*;\n" } grep { $_ ne $qualified->($p) } sort keys %{ $imports{$p} || {} }) : '';
        }gme;
        $f->{text} =~ s/\{\n(\s*\n)*/{\n/g;
    }
    my $src = $m->{path}; $src =~ s{.*[/\\]}{};
    my %text = map { $_ => "// generated by xmi2sysml.pl from $src -- review before committing; TODO lines need a person\n" . $files{$_}{text} } keys %files;
    my %at;                                   # xmi:id -> [file, line]: where the tags ended up; then strip them
    for my $f (sort keys %text) {
        my @L = split /\n/, $text{$f}, -1;
        for my $i (0 .. $#L) { while ($L[$i] =~ s/\x01([^\x01]*)\x01//) { $at{$1} //= [ $f, $i + 1 ] } }
        $text{$f} = join "\n", @L;
    }
    # every element gets a row: its own line, or the line of the nearest ancestor that has one (folded into it,
    # or inside a construct that became a TODO line)
    my %DEFK = map { $_ => 1 } ('package', 'part def', 'port def', 'constraint def', 'verification def', 'action def', 'item def',
                                'attribute def', 'enum def', 'use case def', 'requirement', 'requirement def');
    my @maprows;
    for my $id (@{ $m->{order} }) {
        my ($src_id, $kind) = ($id, undef);
        $src_id = $m->{parent}{$src_id} while defined $src_id && !$at{$src_id};
        next unless defined $src_id;
        my $e = $map{$src_id};
        $kind = $src_id eq $id ? $e->{kind} : $e->{kind} eq 'todo' ? 'todo' : 'folded';
        my $def; for (my $x = $src_id; defined $x; $x = $m->{parent}{$x}) { if ($map{$x} && $DEFK{ $map{$x}{kind} } && $at{$x}) { $def = $x; last } }
        my $q = $e->{q};
        $q = ($def ? $map{$def}{q} : '') . '::(TODO ' . $el->{$src_id}{t} . ')' if !defined $q;
        $q = ($def ? $map{$def}{q} : '') if !defined $q || $q eq '';
        push @maprows, { id => $id, type => $el->{$id}{t}, q => $q, kind => $kind, file => $at{$src_id}[0], line => $at{$src_id}[1],
                         def => $def ? $map{$def}{q} : '', defkind => $def ? $map{$def}{kind} : '', todo_id => ($kind eq 'todo' ? $src_id : undef),
                         todo_name => ($kind eq 'todo' ? $el->{$src_id}{a}{name} : undef) };
    }
    @maprows = sort { $a->{file} cmp $b->{file} || $a->{line} <=> $b->{line} || $a->{id} cmp $b->{id} } @maprows;

    # ---- report
    my %in;
    for my $id (@{ $m->{order} }) {
        my $t = $el->{$id}{t};
        my $s = $status{$id} || 'todo'; $s = 'todo' if $s =~ /^todo/;
        $in{$t}{in}++; $in{$t}{$s}++;
    }
    my %stc;
    for my $a (@{ $m->{apps} }) { $stc{ $a->{l} }++ }
    my $scope = 0; my $scope_done = 0;
    for my $t (@IN_SCOPE) { $scope += $in{$t}{in} || 0; $scope_done += ($in{$t}{mapped} || 0) + ($in{$t}{folded} || 0) }
    my $problems = check(\%text);
    my %file_of = map { $files{$_}{tp} => $_ } keys %files;          # top-level package id -> output file (for delta)
    return { files => \%text, problems => $problems,
             status => \%status, file_of => \%file_of, map => \@maprows,
             report => { source => $src, in => \%in, out => \%out, unmapped => \@unmapped, stereotypes => \%stc,
                         stereo_todo => \%stereo_todo, extensions => $m->{ext}, unresolved => \%unres, layout => \@layout_notes,
                         scope => $scope, scope_done => $scope_done, total => scalar @{ $m->{order} } } };
}

sub _constraint {                             # "OCL: self.mass <= 2.5" from a uml:Constraint's specification
    my ($c) = @_;
    my $s = XmlLite::kid($c, 'specification') or return _flat(XmlLite::text($c));
    my $b = defined $s->{a}{body} ? $s->{a}{body} : do { my $k = XmlLite::kid($s, 'body'); $k ? XmlLite::text($k) : defined $s->{a}{value} ? $s->{a}{value} : '' };
    my $l = defined $s->{a}{language} ? $s->{a}{language} : do { my $k = XmlLite::kid($s, 'language'); $k ? XmlLite::text($k) : '' };
    return _flat(($l ne '' ? "$l: " : '') . $b);
}

sub _flat { my $t = shift; $t = '' unless defined $t; $t =~ s/\s+/ /g; $t =~ s/^ | $//g; return length $t > 120 ? substr($t, 0, 117) . '...' : $t }

sub report_text {
    my ($out) = @_;
    my $r = $out->{report};
    my @l = ("xmi2sysml report: $r->{source}", '', sprintf('%-28s %6s %7s %7s %6s', 'in (xmi:type)', 'in', 'mapped', 'folded', 'todo'));
    my %tot;
    for my $t (sort keys %{ $r->{in} }) {
        my $x = $r->{in}{$t};
        push @l, sprintf('%-28s %6d %7d %7d %6d', "uml:$t", map { $x->{$_} || 0 } qw(in mapped folded todo));
        $tot{$_} += $x->{$_} || 0 for qw(in mapped folded todo);
    }
    push @l, sprintf('%-28s %6d %7d %7d %6d', 'total', map { $tot{$_} } qw(in mapped folded todo));
    push @l, '', sprintf('ported vs remaining (metric A filter uml:%s): %d of %d ported, %d remaining',
        join('|', @IN_SCOPE), $r->{scope_done}, $r->{scope}, $r->{scope} - $r->{scope_done});
    push @l, '', 'stereotype applications: ' . (join(', ', map { "$_ $r->{stereotypes}{$_}" } sort keys %{ $r->{stereotypes} }) || 'none');
    push @l, 'stereotypes not converted: ' . join(', ', map { "$_ $r->{stereo_todo}{$_}" } sort keys %{ $r->{stereo_todo} }) if %{ $r->{stereo_todo} };
    push @l, "xmi:Extension and xmi:Documentation blocks skipped (diagrams, layout, exporter): $r->{extensions}";
    push @l, 'type references not resolved: ' . join(', ', map { "$_ ($r->{unresolved}{$_})" } sort keys %{ $r->{unresolved} }) if %{ $r->{unresolved} };
    push @l, '', 'out (SysML v2)';
    push @l, sprintf('  %-22s %6d', $_, $r->{out}{$_}) for sort keys %{ $r->{out} };
    my @u = @{ $r->{unmapped} };
    push @l, '', 'unmapped (TODO in the output): ' . scalar @u;
    push @l, map { sprintf('  uml:%-22s %-24s %s%s', $_->{type}, $_->{id}, ($_->{name} ne '' ? "'$_->{name}' " : ''), $_->{why}) } @u;
    push @l, '', 'files: ' . join(' ', sort keys %{ $out->{files} });
    push @l, @{ $r->{layout} || [] };
    push @l, 'self-check: ' . (@{ $out->{problems} } ? scalar(@{ $out->{problems} }) . ' problem(s)' : 'ok'), map { "  $_" } @{ $out->{problems} };
    return join("\n", @l) . "\n";
}

# ---------------------------------------------------------------------------------------------------------------
# the v1 -> v2 map: one row per v1 element, the v2 line it went to (TODO lines included, v2_kind todo; elements folded
# into an owner's line, v2_kind folded). Sorted by file, line, xmi:id.
sub _csvf { my $v = shift // ''; return $v =~ /[",\r\n]/ ? '"' . ($v =~ s/"/""/gr) . '"' : $v }
sub map_csv {
    my ($m, $out) = @_;
    my $t = "xmi_id,v1_type,v1_qualified_name,v2_qualified_name,v2_kind,file,line\n";
    $t .= join(',', map { _csvf($_) } $_->{id}, "uml:$_->{type}", _qname($m, $_->{id}), $_->{q}, $_->{kind}, $_->{file}, $_->{line}) . "\n" for @{ $out->{map} };
    return $t;
}
sub read_map_csv {                             # -> { xmi_id => { q, kind, file, line } }; dies "FILE: message"
    my ($path) = @_;
    open my $fh, '<', $path or die "$path: $!\n";
    local $/; my $text = <$fh>; close $fh;
    $text =~ s/\r//g;
    my @rows;
    my ($f, @row, $q) = ('');
    while ($text =~ /\G(?:"((?:[^"]|"")*)"|([^,\n]*))(,|\n|\z)/gc) {
        my $v = defined $1 ? $1 =~ s/""/"/gr : $2;
        push @row, $v;
        if ($3 ne ',') { push @rows, [ @row ]; @row = (); last if $3 eq '' }
    }
    my $head = shift @rows;
    die "$path: not an xmi2sysml map (expected the header xmi_id,v1_type,v1_qualified_name,v2_qualified_name,v2_kind,file,line)\n"
        unless $head && join(',', @$head) eq 'xmi_id,v1_type,v1_qualified_name,v2_qualified_name,v2_kind,file,line';
    my %m;
    for my $r (@rows) { next unless @$r >= 7 && $r->[0] ne ''; $m{ $r->[0] } = { q => $r->[3], kind => $r->[4], file => $r->[5], line => $r->[6] } }
    return \%m;
}

# ---------------------------------------------------------------------------------------------------------------
# delta: what changed between two exports of the same v1 model (the prime's drops), element by element by xmi:id.
#   my $d = Xmi::delta(Xmi::load($old), Xmi::load($new));   # { added, removed, changed => [ item ], old, new, counts }
#   print Xmi::delta_text($d);
# An item is { id, type, qname, what => [ text ], carried => 1|0, where => 'seg/Pkg.sysml' or the reason it is manual }.
# carried: the converter writes the element into v2 text, so re-converting the drop and merging carries the change;
# manual: the element is a TODO line or sits inside a construct the converter does not carry (a state machine, an
# interaction, an activity's fork or pins, a stereotype it does not know), so the v2 text must be reworked by hand.
sub _qname {
    my ($m, $id) = @_;
    my @p;
    for (my $x = $id; defined $x; $x = $m->{parent}{$x}) {
        my $n = $m->{el}{$x};
        last if $n->{t} eq 'Model' && !defined $m->{parent}{$x};
        my $nm = $n->{a}{name};
        if (!defined $nm || $nm eq '') {
            next unless $x eq $id;
            $nm = $n->{t} eq 'Comment' ? 'comment' : _anon_label($m, $x);
        }
        unshift @p, $nm;
    }
    return join '::', @p;
}
sub _anon_label {                              # a readable label for an unnamed element: a relationship by its ends
    my ($m, $id) = @_;
    my $n = $m->{el}{$id};
    my $nm = sub { my $e = $m->{el}{ $_[0] // '' }; $e && defined $e->{a}{name} ? $e->{a}{name} : '?' };
    if ($n->{t} =~ /^(Abstraction|Dependency|Usage|Realization)$/) {
        my ($st) = map { $_->{l} } sort { $a->{l} cmp $b->{l} } values %{ $m->{st}{$id} || {} };
        my ($c) = _idrefs($n, 'client'); my ($s) = _idrefs($n, 'supplier');
        return '(' . ($st // $n->{t}) . ' ' . $nm->($c) . ' -> ' . $nm->($s) . ')';
    }
    return '(Transition ' . $nm->($n->{a}{source}) . ' -> ' . $nm->($n->{a}{target}) . ')' if $n->{t} eq 'Transition';
    return "($n->{t})";
}
sub _own_sig {                                 # the element's own content: attributes plus untyped descendants, not typed ones
    my ($n) = @_;
    my $walk; $walk = sub {
        my ($x, $top) = @_;
        return '' if !$top && defined xtype($x) && defined xid($x);
        my $s = join '', map { " $_=$x->{a}{$_}" } grep { $_ ne 'xmi:id' && ($top ? $_ ne 'name' : 1) } sort keys %{ $x->{a} };
        my $k = '';
        for my $c (@{ $x->{k} || [] }) { next if ref $c && defined xtype($c) && defined xid($c); $k .= ref $c ? '<' . $c->{l} . $walk->($c, 0) . '>' : do { (my $t = $c) =~ s/\s+/ /g; $t =~ s/^ | $//g; $t } }
        return "$s$k";
    };
    return $walk->($n, 1);
}
sub _st_sig {                                  # stereotypes applied to an element and their tag values
    my ($m, $id) = @_;
    my $st = $m->{st}{$id} || {};
    my %out;
    for my $k (sort keys %$st) {
        my $a = $st->{$k};
        $out{ $a->{l} } = { map { $_ => $a->{a}{$_} } grep { $_ ne 'xmi:id' && !/^base_/ } keys %{ $a->{a} } };
    }
    return \%out;
}
sub _where {                                   # carried (and the file) or manual (and why), from a conversion's status
    my ($m, $conv, $id) = @_;
    my $s = $conv->{status}{$id} // '';
    my $top = $id; $top = $m->{parent}{$top} while defined $m->{parent}{$top} && defined $m->{parent}{ $m->{parent}{$top} };
    my $file = $conv->{file_of}{$top} // (sort keys %{ $conv->{files} })[0] // '?';
    if ($s eq 'mapped' || $s eq 'folded') { return (1, $file) }
    if ($s eq 'todo') { return (0, "manual: a TODO line in $file (the converter does not carry uml:$m->{el}{$id}{t})") }
    my $p = $m->{parent}{$id};
    $p = $m->{parent}{$p} while defined $p && ($conv->{status}{$p} // '') eq 'todo-child';
    my $o = defined $p ? $m->{el}{$p} : undef;
    my $on = $o ? "uml:$o->{t}" . (defined $o->{a}{name} ? " '$o->{a}{name}'" : '') : 'an element';
    return (0, "manual: inside $on, which the converter leaves as a TODO in $file; rework the v2 text by hand");
}
sub delta {
    my ($old, $new, %o) = @_;
    my $co = convert($old, %o);
    my $cn = convert($new, %o);
    my (@added, @removed, @changed);
    my %in_old = map { $_ => 1 } @{ $old->{order} };
    my %in_new = map { $_ => 1 } @{ $new->{order} };
    my $item = sub {
        my ($m, $conv, $id, @what) = @_;
        my ($carried, $where) = _where($m, $conv, $id);
        return { id => $id, type => $m->{el}{$id}{t}, qname => _qname($m, $id), what => \@what, carried => $carried, where => $where };
    };
    for my $id (@{ $new->{order} }) {
        next if $id =~ /^anon_/;
        if (!$in_old{$id}) { push @added, $item->($new, $cn, $id); next }
        my ($a, $b) = ($old->{el}{$id}, $new->{el}{$id});
        my @what;
        my ($na, $nb) = map { $_ // '' } $a->{a}{name}, $b->{a}{name};
        push @what, "renamed '$na' -> '$nb'" if $na ne $nb;
        my ($pa, $pb) = map { $_ // '' } $old->{parent}{$id}, $new->{parent}{$id};
        push @what, 'moved from ' . ($pa ne '' ? _qname($old, $pa) : '(top)') . ' to ' . ($pb ne '' ? _qname($new, $pb) : '(top)') if $pa ne $pb;
        push @what, 'type changed uml:' . $a->{t} . ' -> uml:' . $b->{t} if $a->{t} ne $b->{t};
        push @what, ($a->{t} eq 'Comment' ? 'text changed' : 'properties changed') if !@what && _own_sig($a) ne _own_sig($b);
        @what = grep { $_ ne 'properties changed' } @what if $a->{t} =~ /^(Package|Model)$/;   # a package's members are reported on themselves
        my ($sa, $sb) = (_st_sig($old, $id), _st_sig($new, $id));
        for my $k (sort { lc $a cmp lc $b } keys %{ { %$sa, %$sb } }) {
            if    (!defined $sa->{$k}) { push @what, "stereotype $k applied" }
            elsif (!defined $sb->{$k}) { push @what, "stereotype $k removed" }
            else {
                my ($ta, $tb) = ($sa->{$k}, $sb->{$k});
                my @tags = grep { ($ta->{$_} // '') ne ($tb->{$_} // '') } sort keys %{ { %$ta, %$tb } };
                push @what, "stereotype $k: " . join(', ', map { "$_ changed" } @tags) if @tags;
            }
        }
        push @changed, $item->($new, $cn, $id, @what) if @what;
    }
    for my $id (@{ $old->{order} }) {
        next if $id =~ /^anon_/ || $in_new{$id};
        push @removed, $item->($old, $co, $id);
    }
    my $count = sub { my $c = 0; $c += $_->{carried} ? 0 : 1 for @_; $c };
    my @all = (@added, @removed, @changed);
    return { old => $old, new => $new, added => \@added, removed => \@removed, changed => \@changed, conv_old => $co, conv_new => $cn,
             counts => { old => scalar @{ $old->{order} }, new => scalar @{ $new->{order} }, added => scalar @added,
                         removed => scalar @removed, changed => scalar @changed, manual => $count->(@all),
                         carried => @all - $count->(@all) } };
}
sub delta_text {
    my ($d) = @_;
    my $c = $d->{counts};
    my $src = sub { (my $p = $_[0]{path}) =~ s{.*[/\\]}{}; my $v = _drop_label($_[0]); $v ? "$p ($v)" : $p };
    my @l = ('xmi delta: ' . $src->($d->{old}) . ' -> ' . $src->($d->{new}),
             sprintf('elements %d -> %d: %d added, %d removed, %d changed', @$c{qw(old new added removed changed)}),
             sprintf('carried by the converter (re-convert the drop and merge it): %d', $c->{carried}),
             sprintf('manual (the converter does not carry these; rework the v2 text by hand): %d', $c->{manual}));
    for my $sec (['added', '+'], ['removed', '-'], ['changed', '~']) {
        my ($k, $mk) = @$sec;
        next unless @{ $d->{$k} };
        push @l, '', "$k:";
        for my $i (@{ $d->{$k} }) {
            push @l, sprintf('  %s %-22s %s%s', $mk, "uml:$i->{type}", $i->{qname}, @{ $i->{what} } ? ' -- ' . join('; ', @{ $i->{what} }) : '');
            push @l, '      ' . ($i->{carried} ? "carried: $i->{where}" : $i->{where});
        }
    }
    my @man = map { my $k = $_; map { [ $k, $_ ] } grep { !$_->{carried} } @{ $d->{$k} } } qw(added removed changed);
    if (@man) {
        push @l, '', 'manual rework list:';
        push @l, sprintf('  [ ] %s uml:%s %s%s (xmi:id %s)', $_->[0], $_->[1]{type}, $_->[1]{qname},
                         (@{ $_->[1]{what} } ? ' -- ' . join('; ', @{ $_->[1]{what} }) : ''), $_->[1]{id}) for @man;
    }
    return join("\n", @l) . "\n";
}
# ---------------------------------------------------------------------------------------------------------------
# impact: what a delta between two drops touches in the government's v2 model.
#   my $i = Xmi::impact($delta, $model_dir, map => $old_map);   # $old_map from read_map_csv (optional)
#   print Xmi::impact_text($i); print Xmi::impact_csv($i);
# For each added / removed / changed v1 element: the v2 elements it maps to (the new drop's conversion for added, the
# old drop's for removed, both for changed), and then, read from the SysML v2 text in $model_dir: the requirements
# they satisfy, the verification cases that verify those requirements, the connections and allocations that reference
# them, what refers to them by type (for a removal or rename), and whether the government edited the affected
# definitions since the old drop was merged (a definition that differs from the old drop's conversion, or a TODO
# line that is no longer there: closed by hand, so the change must be reworked by hand).
my $V2HEAD = qr/^\s*(?:(?:private|public|protected)\s+)?(?:abstract\s+|variation\s+|#\w+\s+)*(library\s+package|package|(?:part|port|action|item|attribute|enum|constraint|verification|use\s+case|requirement|interface|connection|state|calc|analysis|occurrence|allocation|metadata|view|viewpoint|rendering|concern|case|flow)\s+def|requirement|part|action|state|item|verification|constraint|interface|connection|exhibit\s+state|perform\s+action)\s+('[^']*'|\w+)/;
sub _v2_scan {                                  # { rel => text } -> defs, satisfies, verifies, connections, allocations, usages
    my ($files) = @_;
    my (%defs, @sat, @ver, @conn, @alloc, @use, %doors, %lines);
    for my $f (sort keys %$files) {
        my @L = split /\n/, $files->{$f}, -1;
        $lines{$f} = \@L;
        my @stack; my ($depth, $inc) = (0, 0);
        for my $i (0 .. $#L) {
            my $s = $L[$i]; my $ln = $i + 1;
            if ($inc) { if ($s =~ s{^.*?\*/}{}) { $inc = 0 } else { next } }
            my $raw = $s;
            $s =~ s{/\*.*?\*/}{}g; $inc = 1 if $s =~ s{/\*.*$}{};
            $s =~ s{//.*$}{};
            $s =~ s/"(?:[^"\\]|\\.)*"/""/g;
            my $ctx = @stack ? $stack[-1][2] : '';
            my ($vctx) = map { $_->[2] } grep { $_->[3] =~ /^verification/ } reverse @stack;
            my $opens = () = $s =~ /\{/g; my $closes = () = $s =~ /\}/g;
            if ($s =~ $V2HEAD) {
                my ($k, $nm) = ($1, $2); $k =~ s/\s+/ /g;
                my $q = $ctx ne '' ? "$ctx\::$nm" : $nm;
                $defs{$q} //= { file => $f, start => $ln, end => $ln, kind => $k, name => $nm, ctx => $ctx };
                $doors{$nm} = $1 if $k =~ /^requirement/ && $raw =~ /doorsId\s*=\s*"([^"]*)"/;
                if ($s =~ /\G\s*:\s*~?([\w:'.]+)/gc || $s =~ /^\s*[^:]*?\b\Q$nm\E\s*:\s*~?([\w:'.]+)/) {
                    push @use, { name => $nm, type => $1, ctx => $ctx, file => $f, line => $ln, kind => $k } if $k !~ / def$|package/;
                }
                push @stack, [ $nm, $depth, $q, $k ] if $opens > $closes;
            }
            elsif ($s =~ /^\s*(?:in|out|inout|subject|ref|derived|abstract)\b[^:;]*?\b(\w+|'[^']*')\s*:\s*~?([\w:'.]+)/) {
                push @use, { name => $1, type => $2, ctx => $ctx, file => $f, line => $ln, kind => 'usage' };
            }
            if (defined $ctx && @stack && $raw =~ /doorsId\s*=\s*"([^"]*)"/) { $doors{ $stack[-1][0] } //= $1 }
            push @sat, { req => $1, by => $2, ctx => $ctx, file => $f, line => $ln } if $s =~ /^\s*satisfy\s+(?:requirement\s+)?([\w:'.]+)\s+by\s+([\w:'.]+)/;
            push @ver, { req => $1, ctx => $vctx // $ctx, file => $f, line => $ln } if $s =~ /^\s*verify\s+(?:requirement\s+)?([\w:'.]+)\s*;/;
            push @alloc, { from => $1, to => $2, ctx => $ctx, file => $f, line => $ln } if $s =~ /^\s*allocate\s+([\w:'.]+)\s+to\s+([\w:'.]+)/;
            if ($s =~ /\bconnect\s+(?:\w+\s*::>\s*)?([\w:'.]+)\s+to\s+(?:\w+\s*::>\s*)?([\w:'.]+)/ || $s =~ /^\s*bind\s+([\w:'.]+)\s*=\s*([\w:'.]+)/) {
                my ($a, $b) = ($1, $2);
                my ($cn) = $s =~ /^\s*(?:connection|interface)\s+(\w+)\s*(?::\s*\w+\s*)?connect/;
                push @conn, { ends => [ $a, $b ], name => $cn, ctx => $ctx, file => $f, line => $ln, text => _trim($raw) };
            }
            $depth += $opens - $closes;
            while (@stack && $depth <= $stack[-1][1]) { my $e = pop @stack; $defs{ $e->[2] }{end} = $ln }
        }
    }
    return { defs => \%defs, sat => \@sat, ver => \@ver, conn => \@conn, alloc => \@alloc, use => \@use, doors => \%doors, lines => \%lines };
}
sub _trim { my $t = shift // ''; $t =~ s/^\s+|\s+$//g; $t =~ s/\s+/ /g; $t }
sub _last { my $p = shift // ''; my @s = split /::|\./, $p; my $l = $s[-1] // ''; $l =~ s/^'|'$//g; $l }
sub _segs { my $p = shift // ''; map { (my $x = $_) =~ s/^'|'$//g; $x } split /::|\./, $p }
sub _block {                                   # the normalized text of a definition (header to closing brace)
    my ($scan, $q) = @_;
    my $d = $scan->{defs}{$q} or return undef;
    my $L = $scan->{lines}{ $d->{file} };
    return join "\n", grep { $_ ne '' } map { _trim($_) } @{$L}[ $d->{start} - 1 .. $d->{end} - 1 ];
}
sub _read_tree {
    my ($dir) = @_;
    my %t;
    my $w; $w = sub {
        my ($d, $rel) = @_;
        opendir my $dh, $d or return;
        for my $e (sort grep { !/^\./ } readdir $dh) {
            my $p = "$d/$e"; my $r = $rel eq '' ? $e : "$rel/$e";
            if (-d $p) { $w->($p, $r) }
            elsif ($e =~ /\.sysml$/ && open my $fh, '<', $p) { binmode $fh; local $/; $t{$r} = <$fh>; $t{$r} =~ s/\r//g; close $fh }
        }
        closedir $dh;
    };
    $w->($dir, '');
    return \%t;
}
my %IMPACT_DEFK = map { $_ => 1 } ('part def', 'port def', 'constraint def', 'verification def', 'action def', 'item def',
                                    'attribute def', 'enum def', 'use case def', 'requirement', 'requirement def');
sub impact {
    my ($d, $dir, %o) = @_;
    die "$dir: not a directory\n" unless -d $dir;
    my $mtext = _read_tree($dir);
    my $model = _v2_scan($mtext);
    my ($co, $cn) = @$d{qw(conv_old conv_new)};
    my $oscan = _v2_scan($co->{files});
    my $nscan = _v2_scan($cn->{files});
    my %omap = map { $_->{id} => $_ } @{ $co->{map} };
    my %nmap = map { $_->{id} => $_ } @{ $cn->{map} };
    my @notes;
    if ($o{map}) {                             # a map written when the old drop was converted (the layout the team used)
        my $moved = 0;
        for my $id (sort keys %{ $o{map} }) {
            my $r = $o{map}{$id};
            my $cur = $omap{$id} || { def => '', defkind => '' };
            if ($o{layout_map} && $cur->{file} && $r->{file} ne $cur->{file}) {   # the layout map decides paths: keep the conversion's
                $moved++;
                $omap{$id} = { %$cur, q => $r->{q}, kind => $r->{kind}, id => $id };
                next;
            }
            $omap{$id} = { %$cur, %$r, id => $id };
        }
        push @notes, "--map: $moved row(s) name a path the layout map puts elsewhere; the layout map's paths are used" if $moved;
    }
    my $doors = { %{ $nscan->{doors} }, %{ $oscan->{doors} }, %{ $model->{doors} } };
    my $rname = sub { my $n = _last(shift); $doors->{$n} // $n };
    my (%req_all, %ver_all, %conn_all, %alloc_all, %edit_all, @items);
    for my $kind (qw(added removed changed)) {
        for my $it (@{ $d->{$kind} }) {
            my @src = $kind eq 'added' ? ([ $d->{new}, \%nmap ]) : $kind eq 'removed' ? ([ $d->{old}, \%omap ]) : ([ $d->{old}, \%omap ], [ $d->{new}, \%nmap ]);
            my (@v2, %seen);
            for my $s (@src) {
                my ($m, $map) = @$s;
                my @ids = ([ $it->{id}, 0 ]);
                if ($it->{type} =~ /^(Abstraction|Dependency|Usage|Realization)$/ && $m->{el}{ $it->{id} }) {   # a relationship: its ends too
                    push @ids, map { [ $_, 1 ] } _idrefs($m->{el}{ $it->{id} }, 'client'), _idrefs($m->{el}{ $it->{id} }, 'supplier');
                }
                for my $x (@ids) { my $r = $map->{ $x->[0] } or next; push @v2, { %$r, end => $x->[1] } unless $seen{"$r->{q}\0$r->{kind}"}++ }
            }
            my (%reqs, %vers, %conns, %allocs, @refs, @edits);
            my (%names, %defs);                # simple names to look for; definitions to compare
            for my $r (@v2) {
                if ($r->{kind} =~ /^requirement/) { $reqs{ $rname->($r->{q}) } = "$r->{file}:$r->{line}" }
                next if $r->{end};             # a relationship's other end: listed, not followed further
                if ($IMPACT_DEFK{ $r->{kind} } && $r->{kind} !~ /^requirement/) { $names{ _last($r->{q}) } = 1; $defs{ $r->{q} } = 1 }
                if ($r->{kind} =~ /^(part|port|attribute|item|ref part|action|parameter|enum)$/) { $names{ _last($r->{q}) } = 1 }
                $defs{ $r->{def} } = 1 if $r->{def} && $r->{defkind} && $IMPACT_DEFK{ $r->{defkind} } && $r->{defkind} !~ /^requirement/;
                $names{ _last($r->{def}) } = 1 if $r->{def} && $r->{defkind} && $r->{defkind} !~ /^requirement|package/ && $r->{kind} ne 'todo';
                $vers{ _last($r->{q}) } = "$r->{file}:$r->{line}" if $r->{kind} eq 'verify';
                $vers{ _last($r->{def}) } = "$r->{file}:$r->{line}" if ($r->{defkind} // '') eq 'verification def' && $r->{kind} ne 'verify';
                $vers{ _last($r->{q}) } = "$r->{file}:$r->{line}" if $r->{kind} eq 'verification def' && $r->{q} !~ /_verification(?:_\d+)?$/;
            }
            my %own = map { $_ => 1 } grep { $defs{$_} } keys %defs;
            # the government's model: what satisfies / verifies / connects / allocates / refers to these
            for my $s (@{ $model->{sat} }) {
                if (grep { $names{$_} } _segs($s->{by})) { $reqs{ $rname->($s->{req}) } //= "$s->{file}:$s->{line}" }
            }
            my %rq = map { $_ => 1 } keys %reqs;
            for my $v (@{ $model->{ver} }) { $vers{ _last($v->{ctx}) } //= "$v->{file}:$v->{line}" if $rq{ $rname->($v->{req}) } }
            my %in_model = map { $rname->($_->{name}) => 1 } grep { $_->{kind} =~ /^requirement/ } values %{ $model->{defs} };
            for my $v (@{ $nscan->{ver} }) {   # a requirement the government does not have yet: what the new drop verifies it with
                my $rn = $rname->($v->{req});
                $vers{ _last($v->{ctx}) } //= "$v->{file}:$v->{line} (new drop)" if $rq{$rn} && !$in_model{$rn};
            }
            my %usage;                         # ctx \0 usage name -> its type is one of ours
            for my $u (@{ $model->{use} }) { $usage{"$u->{ctx}\0$u->{name}"} = $u if $names{ _last($u->{type}) } }
            for my $c (@{ $model->{conn} }) {
                my $hit = 0;
                for my $e (@{ $c->{ends} }) {
                    my @sg = _segs($e);
                    $hit = 1 if $usage{"$c->{ctx}\0$sg[0]"} || (!@sg ? 0 : (@sg > 1 && $names{ $sg[-1] } && $usage{"$c->{ctx}\0$sg[0]"}));
                    $hit = 1 if $defs{ $c->{ctx} } && $names{ $sg[0] };
                }
                $conns{ $c->{name} ? "$c->{ctx}::$c->{name}" : "$c->{ctx}: $c->{text}" } = "$c->{file}:$c->{line}" if $hit;
            }
            for my $a (@{ $model->{alloc} }) {
                $allocs{"allocate $a->{from} to $a->{to}"} = "$a->{file}:$a->{line}" if grep { $names{$_} } _segs($a->{from}), _segs($a->{to});
            }
            my $breaks = $kind eq 'removed' || grep { /^renamed|^moved/ } @{ $it->{what} || [] };
            my %refctx;
            if ($breaks) {
                for my $u (@{ $model->{use} }) {
                    next unless $names{ _last($u->{type}) } && $u->{ctx} ne '';
                    push @refs, { what => "$u->{ctx}::$u->{name} : $u->{type}", at => "$u->{file}:$u->{line}" };
                    $refctx{ $u->{ctx} } = 1;
                }
            }
            # hand edits: TODO lines closed by hand, and definitions the government changed since the old drop
            my %todo_seen;
            for my $r (@v2) {
                next unless $r->{kind} eq 'todo' && $r->{todo_id} && !$todo_seen{ $r->{todo_id} }++;
                next if grep { /\(xmi:id \Q$r->{todo_id}\E\)/ } values %$mtext;
                my $in = $r->{def} || $r->{q};
                push @edits, { what => "TODO for " . _todo_label($r) . " closed by hand in " . _last($in), where => $in,
                               at => _where_in($model, $in, $r) };
            }
            my %edited = map { $_->{where} => 1 } @edits;
            for my $q (sort(keys %defs), sort keys %refctx) {
                next if $edited{$q}++;
                my ($was, $now) = (_block($oscan, $q), _block($model, $q));
                next unless defined $was;
                if (!defined $now) { push @edits, { what => _last($q) . ' was removed or moved by the government', where => $q, at => '' }; next }
                next if $was eq $now;
                push @edits, { what => _last($q) . ($refctx{$q} && !$own{$q} ? ' refers to it and' : '') . ' was edited by the government since ' . _drop_label($d->{old}),
                               where => $q, at => "$model->{defs}{$q}{file}:$model->{defs}{$q}{start}" };
            }
            $req_all{$_} //= $reqs{$_} for keys %reqs;
            $ver_all{$_} //= $vers{$_} for keys %vers;
            $conn_all{$_} //= $conns{$_} for keys %conns;
            $alloc_all{$_} //= $allocs{$_} for keys %allocs;
            $edit_all{ $_->{what} } //= $_ for @edits;
            push @items, { change => $kind, item => $it, v2 => \@v2, reqs => \%reqs, vers => \%vers, conns => \%conns,
                           allocs => \%allocs, refs => \@refs, edits => \@edits };
        }
    }
    # already merged? On a drop branch after the vendor merge the model holds the new drop's conversion: every
    # definition the delta changes matches the new drop rather than the old one, and the 'hand edits' are the drop itself
    my ($like_new, $like_old) = (0, 0);
    my %dq; for my $x (@items) { for my $r (@{ $x->{v2} }) { $dq{$_} = 1 for grep { $_ } $r->{q}, $r->{def} } }
    for my $q (sort keys %dq) {
        my ($ob, $nb, $mb) = (_block($oscan, $q), _block($nscan, $q), _block($model, $q));
        next if defined $ob && defined $nb && $ob eq $nb;
        next unless defined $mb;
        if    (defined $nb && $mb eq $nb) { $like_new++ }
        elsif (defined $ob && $mb eq $ob) { $like_old++ }
    }
    if ($like_new && $like_new > $like_old) {
        push @notes, 'warning: the model already contains ' . (_drop_label($d->{new}) || 'NEW') . ": run --impact against develop before the drop is merged"
                   . " ($like_new changed definition(s) match the new drop, $like_old the old one); hand edits are not reported";
        $_->{edits} = [] for @items;
        %edit_all = ();
    }
    my $crs = $o{changes};
    if ($crs) {                                # each change belongs to the CR naming it, or one of its owners (or a relationship's end)
        my %of; for my $c (@$crs) { $of{$_} //= $c for @{ $c->{ids} } }
        for my $x (@items) {
            my $m = $x->{change} eq 'removed' ? $d->{old} : $d->{new};
            my $id = $x->{item}{id};
            my $cr;
            for (my $p = $id; defined $p && !$cr; $p = $m->{parent}{$p}) { $cr = $of{$p} }
            $x->{cr} = $cr;
        }
    }
    return { dir => $dir, files => scalar(keys %$mtext), delta => $d, items => \@items, reqs => \%req_all, vers => \%ver_all, changes => $crs, notes => \@notes,
             conns => \%conn_all, allocs => \%alloc_all, edits => [ map { $edit_all{$_} } sort keys %edit_all ] };
}
sub read_changes_csv {                         # the prime's CHANGES.csv: cr_id,title,rationale,kind,xmi_ids,requirements
    my ($path) = @_;
    open my $fh, '<', $path or die "$path: $!\n";
    local $/; my $text = <$fh>; close $fh;
    $text =~ s/\r//g;
    my (@rows, @row);
    while ($text =~ /\G(?:"((?:[^"]|"")*)"|([^,\n]*))(,|\n|\z)/gc) {
        push @row, defined $1 ? $1 =~ s/""/"/gr : $2;
        if ($3 ne ',') { push @rows, [ @row ]; @row = (); last if $3 eq '' }
    }
    my $head = shift @rows;
    die "$path: not a CHANGES.csv (expected the header cr_id,title,rationale,kind,xmi_ids,requirements)\n"
        unless $head && join(',', @$head) eq 'cr_id,title,rationale,kind,xmi_ids,requirements';
    return [ map { { cr => $_->[0], title => $_->[1] // '', rationale => $_->[2] // '', kind => $_->[3] // '',
                     ids => [ split ' ', $_->[4] // '' ], reqs => [ split ' ', $_->[5] // '' ] } } grep { @$_ >= 4 && $_->[0] ne '' } @rows ];
}
sub _todo_label { my $r = shift; my $q = $r->{q} // ''; ($q =~ /\(TODO (\w+)\)$/ ? "uml:$1" : _last($q)) . (defined $r->{todo_name} ? " '$r->{todo_name}'" : '') }
sub _where_in { my ($scan, $q, $r) = @_; my $d = $scan->{defs}{$q}; $d ? "$d->{file}:$d->{start}" : "$r->{file}:$r->{line}" }
sub impact_text {
    my ($i) = @_;
    my $sym = { added => '+', removed => '-', changed => '~' };
    my @l = ('', "impact on $i->{dir} ($i->{files} .sysml files)", @{ $i->{notes} || [] });
    my @groups = ([ undef, $i->{items} ]);
    if ($i->{changes}) {                       # by change request, in the prime's order; changes no CR names last
        my %by; push @{ $by{ $_->{cr} ? $_->{cr}{cr} : '' } }, $_ for @{ $i->{items} };
        @groups = ((map { [ $_, $by{ $_->{cr} } || [] ] } @{ $i->{changes} }), ($by{''} ? ([ { cr => '' }, $by{''} ]) : ()));
    }
    for my $g (@groups) {
      my ($cr, $xs) = @$g;
      if ($cr) {
        if ($cr->{cr} eq '') { push @l, '', '== changes no change request names (ask the prime)' }
        else {
            push @l, '', "== $cr->{cr} $cr->{kind}: $cr->{title}" . (@$xs ? '' : ' (no change in this delta)'),
                     '   rationale: ' . ($cr->{rationale} =~ /\S/ ? $cr->{rationale} : '(none given -- ask the prime for clarification)');
            push @l, '   requirements: ' . join(' ', @{ $cr->{reqs} }) if @{ $cr->{reqs} };
        }
      }
      for my $x (@$xs) {
        my $it = $x->{item};
        push @l, '', sprintf('%s uml:%s %s%s', $sym->{ $x->{change} }, $it->{type}, $it->{qname}, @{ $it->{what} || [] } ? ' -- ' . join('; ', @{ $it->{what} }) : '');
        push @l, map { sprintf '    v2: %s (%s, %s:%d)', $_->{q}, $_->{kind}, $_->{file}, $_->{line} } @{ $x->{v2} };
        push @l, '    requirements: ' . join(', ', sort keys %{ $x->{reqs} }) if %{ $x->{reqs} };
        push @l, '    verification cases: ' . join(', ', sort keys %{ $x->{vers} }) if %{ $x->{vers} };
        push @l, map { "    interface: $_ ($x->{conns}{$_})" } sort keys %{ $x->{conns} };
        push @l, map { "    allocation: $_ ($x->{allocs}{$_})" } sort keys %{ $x->{allocs} };
        push @l, map { "    referenced by: $_->{what} ($_->{at})" } @{ $x->{refs} };
        push @l, map { "    hand edit: $_->{what}" . ($_->{at} ? " ($_->{at})" : '') } @{ $x->{edits} };
      }
    }
    my $list = sub { my $h = shift; join(', ', sort keys %$h) };
    push @l, '', 'impact summary:',
        sprintf('%-28s %3d  %s', 'requirements touched', scalar(keys %{ $i->{reqs} }), $list->($i->{reqs})),
        sprintf('%-28s %3d  %s', 'verification cases touched', scalar(keys %{ $i->{vers} }), $list->($i->{vers})),
        sprintf('%-28s %3d  %s', 'interfaces touched', scalar(keys %{ $i->{conns} }), join('; ', sort keys %{ $i->{conns} })),
        sprintf('%-28s %3d  %s', 'allocations touched', scalar(keys %{ $i->{allocs} }), join('; ', sort keys %{ $i->{allocs} })),
        sprintf('%-28s %3d', 'hand edits to redo', scalar @{ $i->{edits} });
    if ($i->{changes}) {
        my @norat = grep { $_->{rationale} !~ /\S/ } @{ $i->{changes} };
        my $loose = grep { !$_->{cr} } @{ $i->{items} };
        splice @l, -1, 0, sprintf('%-28s %3d  %s', 'change requests', scalar @{ $i->{changes} }, join(' ', map { $_->{cr} } @{ $i->{changes} })),
            sprintf('%-28s %3d  %s', 'without a rationale', scalar @norat, join(' ', map { $_->{cr} } @norat)),
            sprintf('%-28s %3d', 'changes no CR names', $loose);
    }
    push @l, map { "  [ ] $_->{what}" . ($_->{at} ? " ($_->{at})" : '') } @{ $i->{edits} };
    return join("\n", @l) . "\n";
}
sub impact_csv {
    my ($i) = @_;
    my $t = "change,xmi_id,v1_type,v1_qualified_name,category,v2_name,file,line,detail,cr_id\n";
    my $row = sub { my ($x, $cat, $name, $at, $detail) = @_; my ($f, $ln) = ($at // '') =~ /^(.*):(\d+)$/ ? ($1, $2) : ('', '');
        $t .= join(',', map { _csvf($_) } $x->{change}, $x->{item}{id}, "uml:$x->{item}{type}", $x->{item}{qname}, $cat, $name, $f, $ln, $detail // '', $x->{cr} ? $x->{cr}{cr} : '') . "\n" };
    for my $x (@{ $i->{items} }) {
        $row->($x, 'v2', $_->{q}, "$_->{file}:$_->{line}", $_->{kind}) for @{ $x->{v2} };
        $row->($x, 'requirement', $_, $x->{reqs}{$_}) for sort keys %{ $x->{reqs} };
        $row->($x, 'verification', $_, $x->{vers}{$_}) for sort keys %{ $x->{vers} };
        $row->($x, 'interface', $_, $x->{conns}{$_}) for sort keys %{ $x->{conns} };
        $row->($x, 'allocation', $_, $x->{allocs}{$_}) for sort keys %{ $x->{allocs} };
        $row->($x, 'reference', $_->{what}, $_->{at}) for @{ $x->{refs} };
        $row->($x, 'hand-edit', $_->{where}, $_->{at}, $_->{what}) for @{ $x->{edits} };
    }
    return $t;
}

sub _drop_label {                              # "v1.1" from the export's own comment, when it names a drop
    my ($m) = @_;
    open my $fh, '<', $m->{path} or return '';
    my $head = ''; read $fh, $head, 512; close $fh;
    return $head =~ /prime drop (v[\d.]+)/ ? $1 : '';
}
1;
