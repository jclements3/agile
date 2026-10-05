package Xmi;
# SysML v1 XMI (Cameo Systems Modeler / MagicDraw "Eclipse UML2 (v5.x) XMI", XMI 2.5.1 / 2.1) -> SysML v2 text.
#
#   my $m   = Xmi::load($path);                         # parse + index (XmlLite tree, ids, stereotype applications)
#   my $out = Xmi::convert($m, req_style => 'def'|'usage', layout => '{seg}/{pkg}.sysml', name => 'Loose');
#   # $out = { files => { relpath => text }, report => {...}, problems => [ self-check ] }
#   print Xmi::report_text($out);
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
use SysmlText qw(name ident str doc requirement check is_keyword);

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
        return "$ind// TODO uml:$n->{t}$nmv (xmi:id $id): $why";
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
            push @l, doc($b, $ind);
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
        return "$ind$dir$kw " . $N->($id) . (defined $ty ? " : $ty" : '') . $mult->($n) . (defined $v ? " = $v" : '') . ";$cmt";
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
            return "${ind}port " . $N->($id) . $mult->($n) . " { $d $what flowValue : $ty; }$cmt";
        }
        my $note = '';
        if ($tk eq 'partdef') { $note = ' // TODO the type is a part def (also used as a part); give the port a port def' }
        return "${ind}port " . $N->($id) . (defined $ty ? ' : ' . ($conj ? '~' : '') . $ty : '') . $mult->($n) . ";$cmt$note";
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
        if ($has->($id, 'BindingConnector')) { $out{bind}++; return "${ind}bind $p[0] = $p[1];" }
        $out{connection}++;
        my $named = defined $n->{a}{name} && $n->{a}{name} ne '';
        return "${ind}connection " . ($named ? $N->($id) . ' ' : '') . "connect $p[0] to $p[1];";
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
        return @l;
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
            push @l, "$ind$d " . $N->($p->{id}) . (defined $ty ? " : $ty" : '') . $mult->($p) . ";$cmt";
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
                push @l, "${ind}action " . $N->($c->{id}) . "$bt;";
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
                push @l, "${ind}first $nodename{$s} then $nodename{$t};";
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
                if ($kind{$id} eq 'enumdef') { push @l, "${ind}enum " . $N->($cid) . ';'; $status{$cid} = 'mapped'; $out{'enum'}++; $fold->($_) for XmlLite::kids($c) }
                else { push @l, $todo->($cid, 'literal outside an enumeration', $ind) }
            }
            elsif ($k eq 'assoc')  { $fold->($c) }
            elsif ($k eq 'libtype') { $fold->($c) }
            elsif ($k eq 'comment') { push @l, "${ind}comment " . do { my $b = defined $c->{a}{body} ? $c->{a}{body} : ''; my @d = doc($b, ''); $d[0] =~ s/^doc //; "@d" }; $status{$cid} = 'mapped'; $out{comment}++ }
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
            my @l = requirement({ name => $N->($id), doorsId => $n->{doorsId}, text => $text, title => $title,
                                  vm => _sattr($app, 'verifyMethod'), attrs => \@attrs, body => [ map { (my $x = $_) =~ s/^\Q$in\E//; $x } @b ] }, $style, $ind);
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
            push @b, "${in}objective {", (map { "$in    verify " . ($ref->($id, $_) || "TODO_$_") . ';' } grep { $nm{$_} } @{ $verifies{$id} }), "$in}";
            $out{verify} += grep { $nm{$_} } @{ $verifies{$id} };
            for my $r (keys %verif_rel) { if (grep { $_ eq $id } @{ $verif_rel{$r}[0] }) { $status{$r} = 'mapped'; $fold->($_) for XmlLite::kids($el->{$r}) } }
        }
        if ($k eq 'constraintdef') { push @b, "$in// TODO constraint expression (parametrics) not converted" }
        push @b, $activity_lines->($id, $id, $in) if $n->{t} eq 'Activity';
        push @b, $emit_body->($id, $in);
        if ($k eq 'package') {                # imports go first; filled in after the whole tree is emitted
            unshift @b, "$in\x00IMPORTS $id";
        }
        return ("$ind$head;") if !@b;
        return ("$ind$head {", @b, "$ind}");
    };

    # ---- emit each top-level package
    my %files;
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
    return { files => \%text, problems => $problems,
             report => { source => $src, in => \%in, out => \%out, unmapped => \@unmapped, stereotypes => \%stc,
                         stereo_todo => \%stereo_todo, extensions => $m->{ext}, unresolved => \%unres,
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
    push @l, 'self-check: ' . (@{ $out->{problems} } ? scalar(@{ $out->{problems} }) . ' problem(s)' : 'ok'), map { "  $_" } @{ $out->{problems} };
    return join("\n", @l) . "\n";
}

1;
