#!/usr/bin/perl
# v1v2.pl : move a SysML v1 model exported from an older Cameo (no SysML v2 plugin) toward
# SysML v2 text. Core Perl 5 only; runs on Git for Windows' Perl.
#
#   perl v1v2.pl inventory MODEL [--tsv]
#   perl v1v2.pl check     MODEL [--typemap F]
#   perl v1v2.pl convert   MODEL -o DIR [--package V1::QN] [--prefix P] [--marking LEVEL]
#                          [--keep-names] [--no-provenance] [--typemap F]
#   perl v1v2.pl reqs      REQS -o FILE.sysml --package NAME [--marking LEVEL]
#                          [--id COL] [--name COL] [--text COL] [--parent COL]
#
# MODEL is a UML/SysML 1.x XMI export (.xmi, .uml, .xml) or a Cameo .mdzip.
# REQS is a ReqIF file (.reqif, .reqifz) or a CSV export of a requirement table.
# Diagnostics are GNU format (file:line: severity: message), then a summary line.
# Exit status: 0 clean, 1 findings, 2 usage or input error.
use strict; use warnings;
use Getopt::Long qw(GetOptionsFromArray);
use File::Path qw(make_path);
use File::Basename qw(basename);
use Encode ();

my $VERSION = '1.0';
my %O = (provenance => 1);
my $cmd = shift @ARGV // '';
GetOptionsFromArray(\@ARGV, \%O, 'o=s', 'package=s', 'prefix=s', 'marking=s', 'keep-names',
    'provenance!', 'typemap=s', 'tsv', 'id=s', 'name=s', 'text=s', 'parent=s')
    or usage();
my $IN = shift @ARGV or usage();
usage() if @ARGV;
binmode STDOUT, ':encoding(UTF-8)';
binmode STDERR, ':encoding(UTF-8)';


sub usage {
    open my $h, '<', $0; my @l = <$h>; print STDERR map { s/^# ?//r } grep { /^#  / } @l[0 .. 12];
    exit 2;
}
sub fail { print STDERR "v1v2: $_[0]\n"; exit 2 }

# --------------------------------------------------------------------------------------------
# Input: read a file (or the model member of a zip), decode, parse XML into a light tree.
# --------------------------------------------------------------------------------------------
sub slurp {
    my $f = shift;
    my $raw;
    if ($f =~ /\.(?:mdzip|reqifz|zip)$/i) { $raw = from_zip($f) }
    else { open my $h, '<:raw', $f or fail("$f: $!"); local $/; $raw = <$h> }
    my $t = eval { Encode::decode('UTF-8', $raw, Encode::FB_CROAK) }
         // Encode::decode('cp1252', $raw);
    $t =~ s/^\x{FEFF}//;
    $t =~ s/\r\n?/\n/g;
    return $t;
}

sub from_zip {
    my $f = shift;
    eval { require IO::Uncompress::Unzip; 1 }
        or fail("$f: IO::Uncompress::Unzip is not available; unzip the file and pass the model file inside it");
    my $z = IO::Uncompress::Unzip->new($f) or fail("$f: not a readable zip");
    my ($best, $name) = ('', '');
    for (my $s = 1; $s > 0; $s = $z->nextStream) {
        my $member = $z->getHeaderInfo->{Name} // '';
        my ($data, $buf, $r) = ('');
        $data .= $buf while ($r = $z->read($buf)) > 0;
        fail("$f: corrupt member $member") if $r < 0;
        ($best, $name) = ($data, $member)
            if $data =~ /<(?:xmi:XMI|uml:Model|REQ-IF)\b/ && length $data > length $best;
    }
    fail("$f: no XMI or ReqIF member found") unless length $best;
    print STDERR "v1v2: $f: using member $name\n";
    return $best;
}

my %ENT = (lt => '<', gt => '>', amp => '&', quot => '"', apos => "'");
sub unent { my $s = shift; $s =~ s/&(#[xX][0-9a-fA-F]+|#\d+|\w+);/ent1($1)/ge; return $s }
sub ent1 {
    my $e = shift;
    return chr(hex substr($e, 2)) if $e =~ /^#[xX]/;
    return chr(substr($e, 1)) if $e =~ /^#/;
    return $ENT{$e} // "&$e;";
}

# Node: { tag, a => {attrs}, kids => [...], line, up }. Text is kept as '#text' kids.
# Tags in %$skip are skipped whole (Cameo puts diagrams in xmi:Extension); returns ($doc, $nskipped).
sub parse_xml {
    my ($t, $file, $skip) = @_;
    my $doc = { tag => '#doc', a => {}, kids => [], line => 1 };
    my @st = ($doc); my $line = 1; my $len = length $t; my $skipped = 0;
    pos($t) = 0;
    while (pos($t) < $len) {
        if ($t =~ /\G([^<]+)/gc) {
            my $s = $1; $line += ($s =~ tr/\n//);
            push @{$st[-1]{kids}}, { tag => '#text', text => unent($s) } if $s =~ /\S/;
        } elsif ($t =~ /\G<(!--|!\[CDATA\[|\?|!)/gc) {     # index(), not .*?: keeps the scan linear
            my $open = $1;
            my $close = $open eq '!--' ? '-->' : $open eq '?' ? '?>' : $open eq '!' ? '>' : ']]>';
            my $from = pos($t); my $end = index($t, $close, $from);
            die "$file:$line: error: no closing '$close'\n" if $end < 0;
            my $s = substr($t, $from, $end - $from);
            pos($t) = $end + length $close;
            $line += ($s =~ tr/\n//);
            push @{$st[-1]{kids}}, { tag => '#text', text => $s } if $open eq '![CDATA[';
        } elsif ($t =~ /\G<\/([^\s>]+)\s*>/gc) {
            die "$file:$line: error: unexpected </$1>\n" if @st < 2 || $st[-1]{tag} ne $1;
            pop @st;
        } elsif ($t =~ /\G<([^\s\/>!?]+)((?:\s+[^\s=\/>]+\s*=\s*(?:"[^"]*"|'[^']*'))*)\s*(\/?)>/gc) {
            my ($tag, $as, $empty) = ($1, $2, $3);
            my $n = { tag => $tag, a => {}, kids => [], line => $line, up => $st[-1] };
            $n->{a}{$1} = unent($2 // $3) while $as =~ /([^\s=]+)\s*=\s*(?:"([^"]*)"|'([^']*)')/g;
            $line += ($as =~ tr/\n//);
            if ($skip && $skip->{$tag}) {
                $skipped++;
                next if $empty;
                my ($depth, $from) = (1, pos($t));
                while ($depth && $t =~ /\G.*?<(\/?)\Q$tag\E(?=[\s\/>])[^>]*?(\/?)>/gcs) {
                    if ($1) { $depth-- } elsif (!$2) { $depth++ }
                }
                die "$file:$n->{line}: error: unclosed <$tag>\n" if $depth;
                $line += (substr($t, $from, pos($t) - $from) =~ tr/\n//);
                next;
            }
            push @{$st[-1]{kids}}, $n;
            push @st, $n unless $empty;
        } else {
            die "$file:$line: error: malformed XML near '" . substr($t, pos($t), 30) . "'\n";
        }
    }
    die "$file:$line: error: unclosed <$st[-1]{tag}>\n" if @st > 1;
    return ($doc, $skipped);
}

sub text_of {                       # all text below a node, in document order
    my $n = shift;
    return $n->{text} if $n->{tag} eq '#text';
    return join '', map { text_of($_) } @{$n->{kids}};
}
sub elems { grep { $_->{tag} ne '#text' } @{$_[0]{kids}} }
sub kid   { my ($n, $tag) = @_; (grep { $_->{tag} eq $tag } elems($n))[0] }

# --------------------------------------------------------------------------------------------
# The v1 model: element records indexed by xmi:id, with stereotype applications attached.
# --------------------------------------------------------------------------------------------
my (%E, @ALL, %XMLNS, $MODEL, $NSKIP, %TYPEMAP);

my %SYSML_PREFIX = map { $_ => 1 } qw(sysml SysML Blocks Requirements PortsAndFlows
    ConstraintBlocks Activities Allocations ModelElements DeprecatedElements
    StandardProfile StandardProfileL2 StandardProfileL3 l2 l3
    MD_Customization_for_SysML__additional_stereotypes
    MD_Customization_for_Requirements__additional_stereotypes
    UML_Standard_Profile MagicDraw_Profile Validation_Profile DSL_Customization);

sub load_model {
    my $file = shift;
    my $doc;
    eval { ($doc, $NSKIP) = parse_xml(slurp($file), $file, { 'xmi:Extension' => 1 }); 1 }
        or do { print STDERR $@; exit 2 };
    my ($root) = elems($doc);
    fail("$file: empty document") unless $root;
    for my $k (keys %{$root->{a}}) { $XMLNS{$1} = $root->{a}{$k} if $k =~ /^xmlns:(.+)/ }
    my @stereo;
    my $walk; $walk = sub {
        my ($n, $owner) = @_;
        my $id = $n->{a}{'xmi:id'};
        my $rec = $owner;
        if (defined $id && grep { /^base_/ } keys %{$n->{a}}) {
            push @stereo, $n;                          # a stereotype application
            return;
        }
        if (defined $id) {
            my $type = $n->{a}{'xmi:type'} // ($n->{tag} =~ /^uml:/ ? $n->{tag} : '');
            $rec = { id => $id, type => $type, node => $n, owner => $owner, line => $n->{line},
                     name => name_of($n), st => [], kids => [] };
            $E{$id} = $rec; push @ALL, $rec;
            push @{$owner->{kids}}, $rec if $owner;
            $MODEL //= $rec if $type eq 'uml:Model';
        }
        $walk->($_, $rec) for elems($n);
    };
    $walk->($root, undef);
    for my $s (@stereo) {
        my ($prefix, $sname) = $s->{tag} =~ /^(?:([^:]+):)?(.+)$/;
        $prefix //= '';
        my %a = map { lc($_) => $s->{a}{$_} } keys %{$s->{a}};
        for my $k (elems($s)) {
            next if $k->{a}{'xmi:idref'} || $k->{a}{href};
            $a{lc $k->{tag}} = text_of($k);
        }
        my $uri = $XMLNS{$prefix} // '';
        my $custom = !$SYSML_PREFIX{$prefix}
                  && $uri !~ /omg\.org/i;
        for my $base (grep { /^base_/ } keys %{$s->{a}}) {
            my $t = $E{$s->{a}{$base}} or next;
            push @{$t->{st}}, { name => $sname, prefix => $prefix, a => \%a,
                                custom => $custom, line => $s->{line} };
        }
    }
    kind($_) for @ALL;
    $_->{inside} = inside($_) for @ALL;
    load_typemap($O{typemap}) if $O{typemap};
}

sub name_of {
    my $n = shift;
    return $n->{a}{name} if defined $n->{a}{name};
    my $k = kid($n, 'name');
    return $k ? text_of($k) : '';
}

sub has_st { my ($e, $re) = @_; grep { $_->{name} =~ $re } @{$e->{st}} }
sub st_attr {
    my ($e, $key) = @_;
    for my $s (@{$e->{st}}) { return $s->{a}{$key} if defined $s->{a}{$key} }
    return undef;
}
sub is_req_st { $_[0] =~ /requirement$/i || $_[0] eq 'designConstraint' }

my %TRACE_ST = (Satisfy => 'satisfy', Verify => 'verify', DeriveReqt => 'derive',
                Refine => 'refine', Trace => 'trace', Copy => 'copy', Allocate => 'allocate');

sub kind {
    my $e = shift;
    return $e->{kind} if $e->{kind};
    my $t = $e->{type};
    my %s = map { $_->{name} => 1 } @{$e->{st}};
    my ($tr) = grep { $TRACE_ST{$_} } keys %s;
    my $k =
        $t eq 'uml:Model'                                   ? 'model'
      : $t eq 'uml:Profile'                                 ? 'profile'
      : $t eq 'uml:Package'                                 ? 'package'
      : $t eq 'uml:Class' && grep({ is_req_st($_) } keys %s) ? 'requirement'
      : $t eq 'uml:Class' && $s{InterfaceBlock}             ? 'interfaceblock'
      : $t eq 'uml:Class' && $s{ConstraintBlock}            ? 'constraintblock'
      : $t eq 'uml:Class' && $s{Block}                      ? 'block'
      : $t eq 'uml:Class'                                   ? 'class'
      : $t eq 'uml:Enumeration'                             ? 'enum'
      : $t =~ /^uml:(?:DataType|PrimitiveType)$/            ? 'valuetype'
      : $t eq 'uml:EnumerationLiteral'                      ? 'literal'
      : $t eq 'uml:Port'                                    ? 'port'
      : $t eq 'uml:Property' && $e->{owner} && $e->{owner}{type} eq 'uml:Association' ? 'assocend'
      : $t eq 'uml:Property'                                ? 'property'
      : $t eq 'uml:Connector'                               ? 'connector'
      : $t =~ /^uml:(?:Abstraction|Dependency|Realization|Usage)$/ ? ($tr ? $TRACE_ST{$tr} : 'dependency')
      : $t eq 'uml:Generalization'                          ? 'generalization'
      : $t eq 'uml:Comment'                                 ? 'comment'
      : $t =~ /^uml:(?:Activity|StateMachine|Interaction|OpaqueBehavior|FunctionBehavior)$/ ? 'behavior'
      : $t =~ /^uml:(?:UseCase|Actor)$/                     ? 'usecase'
      : $t eq 'uml:Association'                             ? 'association'
      : $t eq 'uml:InformationFlow'                         ? 'itemflow'
      : $t eq 'uml:InstanceSpecification'                   ? 'instance'
      : $t eq 'uml:Constraint'                              ? 'constraint'
      : $t eq 'uml:Operation'                               ? 'operation'
      :                                                       'other';
    return $e->{kind} = $k;
}

# Elements below a behavior, instance, constraint or value specification are not counted.
sub inside {
    my $e = shift;
    for (my $o = $e->{owner}; $o; $o = $o->{owner}) {
        return 1 if $o->{kind} =~ /^(?:behavior|usecase|instance|constraint|other|profile|operation)$/;
    }
    return 0;
}

# References: a space-separated attribute, or child elements with xmi:idref or href.
sub refs {
    my ($n, $attr) = @_;
    my @r;
    push @r, split ' ', $n->{a}{$attr} if defined $n->{a}{$attr};
    for my $k (elems($n)) {
        next unless $k->{tag} eq $attr;
        if (defined $k->{a}{'xmi:idref'}) { push @r, $k->{a}{'xmi:idref'} }
        elsif (defined(my $h = $k->{a}{href})) { push @r, $h =~ /^#(.+)/ ? $1 : "href:$h" }
    }
    return @r;
}

sub qname {                         # v1 qualified name, for messages and --package
    my $e = shift; my @n;
    for (my $o = $e; $o && $o->{kind} ne 'model'; $o = $o->{owner}) { unshift @n, $o->{name} }
    return join '::', @n;
}

sub owned_comments {
    my $e = shift;
    my @c;
    for my $k (@{$e->{kids}}) {
        next unless $k->{kind} eq 'comment';
        my @ann = refs($k->{node}, 'annotatedElement');
        next if @ann && !grep { $_ eq $e->{id} } @ann;
        my $b = defined $k->{node}{a}{body} ? $k->{node}{a}{body}
              : (kid($k->{node}, 'body') ? text_of(kid($k->{node}, 'body')) : '');
        push @c, $b if $b =~ /\S/;
    }
    return join "\n", @c;
}

sub html2text {
    my $s = shift // '';
    return $s unless $s =~ /<\w|&\w+;/;
    $s =~ s{<(?:br|/p|/div|/li)\b[^>]*>}{ }gi;
    $s =~ s{<[^>]*>}{}g;
    my %h = (nbsp => ' ', lt => '<', gt => '>', amp => '&', quot => '"', apos => "'",
             ndash => '-', mdash => '-', rsquo => "'", lsquo => "'", rdquo => '"', ldquo => '"');
    $s =~ s/&(\w+);/$h{$1} \/\/ "&$1;"/ge;
    return unent($s);
}
sub squash { my $s = shift // ''; $s =~ s/\s+/ /g; $s =~ s/^ | $//g; $s }

sub req_id   { squash(st_attr($_[0], 'id')) }
sub req_text { squash(html2text(st_attr($_[0], 'text'))) }

# Trace relationships: [kind, client(s), supplier(s), record].
sub traces {
    my @t;
    for my $e (@ALL) {
        next unless $e->{kind} =~ /^(?:satisfy|verify|derive|refine|trace|copy|allocate)$/;
        push @t, [$e->{kind}, [refs($e->{node}, 'client')], [refs($e->{node}, 'supplier')], $e];
    }
    return @t;
}

# --------------------------------------------------------------------------------------------
# Types: model elements, the scalar library, ISQ quantities by name or unit, and a typemap.
# --------------------------------------------------------------------------------------------
my %PRIM = (Real => 'Real', Integer => 'Integer', Boolean => 'Boolean', String => 'String',
            UnlimitedNatural => 'Natural', Number => 'Real', Complex => 'Complex',
            double => 'Real', float => 'Real', int => 'Integer', boolean => 'Boolean',
            string => 'String');
my %ISQ = (mass => 'MassValue', length => 'LengthValue', distance => 'LengthValue',
           time => 'DurationValue', duration => 'DurationValue', speed => 'SpeedValue',
           velocity => 'SpeedValue', acceleration => 'AccelerationValue', force => 'ForceValue',
           power => 'PowerValue', energy => 'EnergyValue', area => 'AreaValue',
           volume => 'VolumeValue', frequency => 'FrequencyValue', pressure => 'PressureValue',
           'electric current' => 'ElectricCurrentValue', current => 'ElectricCurrentValue',
           'thermodynamic temperature' => 'ThermodynamicTemperatureValue',
           temperature => 'ThermodynamicTemperatureValue', 'plane angle' => 'AngularMeasureValue',
           angle => 'AngularMeasureValue', torque => 'TorqueValue');
my %UNIT = (kilogram => ['kg', 'MassValue'], gram => ['g', 'MassValue'],
            metre => ['m', 'LengthValue'], meter => ['m', 'LengthValue'],
            kilometre => ['km', 'LengthValue'], kilometer => ['km', 'LengthValue'],
            second => ['s', 'DurationValue'], newton => ['N', 'ForceValue'],
            watt => ['W', 'PowerValue'], joule => ['J', 'EnergyValue'],
            hertz => ['Hz', 'FrequencyValue'], pascal => ['Pa', 'PressureValue'],
            ampere => ['A', 'ElectricCurrentValue'], kelvin => ['K', 'ThermodynamicTemperatureValue'],
            radian => ['rad', 'AngularMeasureValue'],
            'metre per second' => ['m/s', 'SpeedValue'], 'meter per second' => ['m/s', 'SpeedValue'],
            'metre per second squared' => ['m/s^2', 'AccelerationValue'],
            'meter per second squared' => ['m/s^2', 'AccelerationValue']);

sub load_typemap {
    my $f = shift;
    open my $h, '<:encoding(UTF-8)', $f or fail("$f: $!");
    while (<$h>) {
        s/\r?\n$//; next if /^\s*(?:#|$)/;
        my ($k, $v, $unit) = split /\t/;
        fail("$f:$.: expected KEY<TAB>V2TYPE[<TAB>UNIT]") unless defined $v && length $v;
        $TYPEMAP{$k} = [$v, $unit];
    }
}

# Quantity from a "mass[kilogram]" style name, or from ValueType unit / quantityKind.
sub quantity_of {
    my $e = shift;
    if ($e->{name} =~ /^\s*([A-Za-z][\w ]*?)\s*\[\s*([^\]]+?)\s*\]\s*$/) {
        my ($q, $u) = (lc $1, lc $2);
        my $sym = $UNIT{$u} ? $UNIT{$u}[0] : undef;
        return [$ISQ{$q}, $sym] if $ISQ{$q};
        return [$UNIT{$u}[1], $sym] if $UNIT{$u};
    }
    for my $key ('unit', 'quantitykind') {
        my $r = st_attr($e, $key) // next;
        my $t = $E{$r} or next;
        my $n = lc squash($t->{name});
        return [$UNIT{$n}[1], $UNIT{$n}[0]] if $key eq 'unit' && $UNIT{$n};
        return [$ISQ{$n}, undef] if $key eq 'quantitykind' && $ISQ{$n};
    }
    return undef;
}

# Returns { el => record } | { lib => 'Real', unit => 'kg' } | { unres => text } | undef.
sub resolve_type {
    my $r = shift // return undef;
    if ($r =~ /^href:(.*)$/) {
        my $href = $1; my ($frag) = $href =~ /#(.*)$/; $frag //= $href;
        for my $k ($href, $frag) { return { lib => $TYPEMAP{$k}[0], unit => $TYPEMAP{$k}[1] } if $TYPEMAP{$k} }
        my ($tail) = $frag =~ /([A-Za-z]\w*)$/;
        return { lib => $PRIM{$tail} } if $tail && $PRIM{$tail};
        return { unres => $href };
    }
    my $e = $E{$r} or return { unres => "missing id $r" };
    for my $k ($e->{id}, $e->{name}) { return { lib => $TYPEMAP{$k}[0], unit => $TYPEMAP{$k}[1] } if $TYPEMAP{$k} }
    if ($e->{kind} eq 'valuetype') {
        return { lib => $PRIM{$e->{name}} } if $PRIM{$e->{name}};
        my $q = quantity_of($e);
        return { lib => $q->[0], unit => $q->[1], qty => 1 } if $q && $e->{name} =~ /\[/;
    }
    return { el => $e };
}

sub type_label {
    my $t = shift // return 'untyped';
    return $t->{lib} if $t->{lib};
    return $t->{unres} if $t->{unres};
    return "$t->{el}{name} ($t->{el}{kind})";
}

# --------------------------------------------------------------------------------------------
# inventory
# --------------------------------------------------------------------------------------------
my %CONVERTS = (package => 'yes', block => 'yes', class => 'yes (as part def)',
    interfaceblock => 'yes (port def)', constraintblock => 'partly (parameters; body by hand)',
    valuetype => 'yes', enum => 'yes', literal => 'yes', property => 'yes', port => 'yes',
    connector => 'yes (binary)', generalization => 'yes', requirement => 'yes',
    satisfy => 'yes', verify => 'yes', derive => 'yes (dependency)', refine => 'yes (dependency)',
    trace => 'yes (dependency)', copy => 'yes (dependency)', comment => 'yes (doc)',
    allocate => 'no (by hand)', behavior => 'no (out of scope)', usecase => 'no (out of scope)',
    itemflow => 'no (by hand)', instance => 'no (by hand)', constraint => 'no (by hand)',
    operation => 'no (by hand)', association => 'implied', assocend => 'implied',
    dependency => 'no', profile => 'no', model => '-', other => 'no');

sub cmd_inventory {
    load_model($IN);
    my (%n, %other);
    for my $e (@ALL) {
        next if $e->{inside};
        next if $e->{type} =~ /^uml:(?:Literal|OpaqueExpression|InstanceValue|ElementValue|Expression|ConnectorEnd)/;
        $n{$e->{kind}}++;
        $other{$e->{type}}++ if $e->{kind} eq 'other';
    }
    my @req = grep { $_->{kind} eq 'requirement' } @ALL;
    my %idc; $idc{req_id($_)}++ for grep { req_id($_) ne '' } @req;
    my @leaf = grep { my $r = $_; !grep { $_->{kind} eq 'requirement' } @{$r->{kids}} } @req;
    my (%sat, %ver);
    for my $t (traces()) {
        my $set = $t->[0] eq 'satisfy' ? \%sat : $t->[0] eq 'verify' ? \%ver : next;
        $set->{$_} = 1 for @{$t->[2]};
    }
    my (%ext, %cust);
    for my $e (grep { $_->{kind} =~ /^(?:property|port)$/ && !$_->{inside} } @ALL) {
        for my $r (refs($e->{node}, 'type')) {
            my $t = resolve_type($r);
            $ext{$t->{unres}}++ if $t && $t->{unres};
        }
    }
    for my $e (@ALL) { $cust{"$_->{prefix}:$_->{name}"}++ for grep { $_->{custom} } @{$e->{st}} }
    my %m = (
        'requirements' => scalar @req,
        'requirements.leaf' => scalar @leaf,
        'requirements.with_id' => scalar(grep { req_id($_) ne '' } @req),
        'requirements.with_text' => scalar(grep { req_text($_) ne '' } @req),
        'requirements.duplicate_ids' => scalar(grep { $idc{$_} > 1 } keys %idc),
        'requirements.leaf_satisfied' => scalar(grep { $sat{$_->{id}} } @leaf),
        'requirements.leaf_verified' => scalar(grep { $ver{$_->{id}} } @leaf),
        'types.unresolved_distinct' => scalar keys %ext,
        'stereotypes.custom_distinct' => scalar keys %cust,
        'extensions.skipped' => $NSKIP,
    );
    if ($O{tsv}) {
        print "metric\tvalue\n";
        print "kind.$_\t$n{$_}\n" for sort keys %n;
        print "$_\t$m{$_}\n" for sort keys %m;
        return;
    }
    printf "%-18s %6s  %s\n", 'v1 kind', 'count', 'converts';
    printf "%-18s %6d  %s\n", $_, $n{$_}, $CONVERTS{$_} // '?' for sort { $n{$b} <=> $n{$a} || $a cmp $b } keys %n;
    if (%other) { print "\nother element types (not converted):\n";
        printf "  %-34s %6d\n", $_, $other{$_} for sort { $other{$b} <=> $other{$a} } keys %other }
    print "\nrequirements: $m{requirements} ($m{'requirements.leaf'} leaf), ",
          "$m{'requirements.with_id'} with id, $m{'requirements.with_text'} with text, ",
          "$m{'requirements.duplicate_ids'} duplicate id(s)\n";
    printf "leaf coverage: %d satisfied, %d verified, of %d\n",
        $m{'requirements.leaf_satisfied'}, $m{'requirements.leaf_verified'}, $m{'requirements.leaf'};
    if (%ext) { print "\nunresolved types (add to a --typemap file; count of uses):\n";
        printf "  %5d  %s\n", $ext{$_}, $_ for sort { $ext{$b} <=> $ext{$a} || $a cmp $b } keys %ext }
    if (%cust) { print "\ncustom stereotypes (not converted; count of applications):\n";
        printf "  %5d  %s\n", $cust{$_}, $_ for sort keys %cust }
    print "\nxmi:Extension blocks skipped (diagrams, tool data): $NSKIP\n";
}

# --------------------------------------------------------------------------------------------
# check : pre-process lint of the v1 model (conformance and trace gaps before transforming)
# --------------------------------------------------------------------------------------------
my ($NERR, $NWARN, @DIAG) = (0, 0);
sub diag {
    my ($line, $sev, $msg) = @_;
    push @DIAG, [$line, scalar @DIAG, "$IN:$line: $sev: $msg"];
    $sev eq 'error' ? $NERR++ : $sev eq 'warning' ? $NWARN++ : 0;
}

sub cmd_check {
    load_model($IN);
    my @live = grep { !$_->{inside} && $_->{kind} ne 'profile' } @ALL;
    # dangling references
    for my $e (@live) {
        for my $attr (qw(type general client supplier role partWithPort redefinedProperty)) {
            for my $r (refs($e->{node}, $attr)) {
                diag($e->{line}, 'error', "$attr of '" . qname($e) . "' refers to missing id $r")
                    unless $r =~ /^href:/ || $E{$r};
            }
        }
    }
    for my $e (@live) {
        my $k = $e->{kind};
        next if $k =~ /^(?:model|comment|constraint|generalization|other|assocend|association|satisfy|verify|derive|refine|trace|copy|allocate|dependency|connector)$/;
        diag($e->{line}, 'warning', "unnamed $k (xmi:id $e->{id})") if $e->{name} !~ /\S/;
    }
    my %seen;
    for my $e (grep { $_->{owner} && $_->{name} =~ /\S/ } @live) {
        next unless $e->{kind} =~ /^(?:package|block|class|interfaceblock|constraintblock|valuetype|enum|requirement|property|port|literal)$/;
        my $k = "$e->{owner}{id}\0$e->{name}";
        if ($seen{$k}) { diag($e->{line}, 'warning', "duplicate name '$e->{name}' in '" . qname($e->{owner}) . "' (first at line $seen{$k})") }
        else { $seen{$k} = $e->{line} }
    }
    my %ids;
    my (%sat, %ver);
    for my $t (traces()) {
        my ($k, $cl, $su, $rec) = @$t;
        next unless $k =~ /^(?:satisfy|verify|derive)$/;
        for my $s (@$su) {
            my $se = $E{$s};
            diag($rec->{line}, 'warning', "$k supplier is not a requirement: " . ($se ? qname($se) . " ($se->{kind})" : $s))
                unless $se && $se->{kind} eq 'requirement';
            ($k eq 'satisfy' ? \%sat : $k eq 'verify' ? \%ver : {})->{$s} = 1;
        }
        if ($k eq 'satisfy') {
            for my $c (@$cl) { my $ce = $E{$c} or next;
                diag($rec->{line}, 'warning', "satisfy client '" . qname($ce) . "' is a $ce->{kind}; v2 needs a part or a feature")
                    unless $ce->{kind} =~ /^(?:block|class|property|port)$/ }
        }
    }
    for my $r (grep { $_->{kind} eq 'requirement' } @live) {
        my $id = req_id($r);
        if ($id eq '') { diag($r->{line}, 'warning', "requirement '" . qname($r) . "' has no id") }
        elsif ($ids{$id}) { diag($r->{line}, 'warning', "requirement id '$id' also used at line $ids{$id}") }
        else { $ids{$id} = $r->{line} }
        diag($r->{line}, 'warning', "requirement '" . qname($r) . "' has no text") if req_text($r) eq '';
        next if grep { $_->{kind} eq 'requirement' } @{$r->{kids}};      # groups judged by leaves
        next if $id =~ /^N-/;                                            # needs: traced by derivation
        my @up = ($r); for (my $o = $r->{owner}; $o && $o->{kind} eq 'requirement'; $o = $o->{owner}) { push @up, $o }
        diag($r->{line}, 'warning', "leaf requirement '" . qname($r) . "' is not satisfied") unless grep { $sat{$_->{id}} } @up;
        diag($r->{line}, 'warning', "leaf requirement '" . qname($r) . "' is not verified") unless grep { $ver{$_->{id}} } @up;
    }
    for my $e (grep { $_->{kind} =~ /^(?:property|port)$/ } @live) {
        my @t = refs($e->{node}, 'type');
        if (!@t) { diag($e->{line}, 'warning', "$e->{kind} '" . qname($e) . "' has no type"); next }
        my $t = resolve_type($t[0]);
        diag($e->{line}, 'warning', "$e->{kind} '" . qname($e) . "' has unresolved type $t->{unres}") if $t->{unres};
        diag($e->{line}, 'warning', "port '" . qname($e) . "' is typed by $t->{el}{kind} '$t->{el}{name}'; v2 ports need a port def (interface block)")
            if $e->{kind} eq 'port' && $t->{el} && $t->{el}{kind} ne 'interfaceblock';
    }
    diag($_->{line}, 'warning', "class '" . qname($_) . "' has no Block stereotype") for grep { $_->{kind} eq 'class' } @live;
    my %cs;
    for my $e (@live) { for my $s (grep { $_->{custom} } @{$e->{st}}) {
        diag($s->{line}, 'warning', "custom stereotype $s->{prefix}:$s->{name} on '" . qname($e) . "' will not convert")
            unless $cs{"$s->{prefix}:$s->{name}"}++ } }
    diag($_->{line}, 'note', "$_->{kind} '" . qname($_) . "' is out of scope for conversion")
        for grep { $_->{kind} =~ /^(?:behavior|usecase)$/ && !$_->{inside} } @ALL;
    print map { "$_->[2]\n" } sort { $a->[0] <=> $b->[0] || $a->[1] <=> $b->[1] } @DIAG;
    printf "v1v2 check: 1 file(s), %d error(s), %d warning(s)\n", $NERR, $NWARN;
    exit(($NERR || $NWARN) ? 1 : 0);
}

# --------------------------------------------------------------------------------------------
# Naming
# --------------------------------------------------------------------------------------------
my %KEYWORD = map { $_ => 1 } qw(about abstract accept action actor after alias all allocate
    allocation analysis and as assert assign assume at attribute bind binding by calc case comment
    concern connect connection constant constraint crosses decide def default defined dependency
    derived do doc else end entry enum event exhibit exit expose false filter first flow for fork
    frame from hastype if implies import in include individual inout interface istype item join
    language library locale loop merge message meta metadata nonunique not null objective occurrence
    of or ordered out package parallel part perform port private protected public redefines ref
    references render rendering rep require requirement return satisfy send snapshot specializes
    stakeholder standard state subject subsets succession terminate then timeslice to transition
    true until use variant variation verification verify via view viewpoint when while xor);

my %STOP = map { $_ => 1 } qw(the a an shall be is are of to and or for with within in on at by
    from than that this which its it will should must all each any as);
sub camel {
    my ($s, $upper) = @_;
    my @w = grep { length } split /[^A-Za-z0-9]+/, $s // '';
    return '' unless @w;
    my $r = join '', map { ucfirst } @w;
    unless ($upper) { $r =~ s/^([A-Z]+)(?=[A-Z][a-z]|\d|$)/\L$1/ or $r =~ s/^([A-Z])/\l$1/ }
    $r = "_$r" if $r =~ /^\d/;
    return $r;
}
sub ident_ok { $_[0] =~ /^[A-Za-z_]\w*$/ && !$KEYWORD{$_[0]} }
sub qid { my $n = shift; return $n if ident_ok($n); $n =~ s/(['\\])/\\$1/g; "'$n'" }
sub sq { my $s = shift // ''; $s =~ s/(["\\])/\\$1/g; $s =~ s/\n/\\n/g; "\"$s\"" }

my (@NOTES, $NCONV, $NMANUAL, %RENAMED);
sub note {                          # a finding written to CONVERSION.txt, located in the XMI
    my ($e, $sev, $msg) = @_;
    my $line = $e ? $e->{line} : 1;
    push @NOTES, [$line, scalar @NOTES, sprintf "%s:%d: %s: %s", $IN, $line, $sev, $msg];
    $NMANUAL++ if $sev eq 'warning';
}

# v2 name for one element, unique among its emitted siblings.
my %TAKEN;
sub v2name {
    my ($e, $style, $scope) = @_;       # style: 'def' | 'use'
    return $e->{v2} if defined $e->{v2};
    my $raw = $e->{name};
    my $n;
    if ($O{'keep-names'} && $e->{kind} ne 'requirement') { $n = $raw =~ /\S/ ? $raw : '' }
    else { $n = camel($raw, $style eq 'def') }
    if ($n eq '' && $e->{kind} eq 'requirement') {
        my @w = grep { !$STOP{lc $_} } grep { length } split /[^A-Za-z0-9]+/, req_text($e);
        $n = camel(join(' ', @w[0 .. ($#w < 4 ? $#w : 4)]), 0) if @w;
        $n = camel('r ' . req_id($e), 0) if $n eq '' && req_id($e) ne '';
        note($e, 'note', "unnamed requirement '" . req_id($e) . "' named '$n' from its text") if $n ne '';
    }
    if ($n eq '') {
        $n = $style eq 'def' ? 'Unnamed' . ucfirst $e->{kind} : 'unnamed' . ucfirst $e->{kind};
        note($e, 'warning', "unnamed $e->{kind} named '$n'");
    }
    if (!$O{'keep-names'} || $e->{kind} eq 'requirement') {
        if ($KEYWORD{$n}) { note($e, 'note', "'$n' is a SysML v2 keyword; named '${n}_'"); $n .= '_' }
    }
    my $key = ($scope // 'global') . "\0";
    my $base = $n; my $i = 1;
    $n = $base . ++$i while $TAKEN{$key . $n};
    $TAKEN{$key . $n} = 1;
    $RENAMED{$e->{id}} = 1 if $n ne $raw;
    return $e->{v2} = $n;
}

# --------------------------------------------------------------------------------------------
# convert
# --------------------------------------------------------------------------------------------
my (%VERIFIER, $SCOPE, %EMIT, %STUB, @STUBS, $STUBPKG, %FILEOF);
my $DEFRE = qr/^(?:block|class|interfaceblock|constraintblock|valuetype|enum)$/;

sub in_scope {
    my $e = shift;
    for (my $o = $e; $o; $o = $o->{owner}) { return 1 if $o == $SCOPE }
    return 0;
}

sub top_pkg_name {
    my $e = shift;
    my $n = camel($e->{name}, 1);
    $n = 'Model' if $n eq '';
    $n = camel($O{prefix}, 1) . $n if defined $O{prefix} && index($n, camel($O{prefix}, 1)) != 0;
    my $base = $n; my $i = 1;
    $n = $base . ++$i while $TAKEN{"top\0" . lc $n};
    $TAKEN{"top\0" . lc $n} = 1;
    return $n;
}

# Owning package record (nearest package or model) and the qualified v2 name of an element.
sub pkg_of { my $e = shift; my $o = $e->{owner}; $o = $o->{owner} while $o && $o->{kind} !~ /^(?:package|model)$/; $o }
sub qn {
    my $e = shift;
    return $e->{qn} if $e->{qn};
    my @seg;
    for (my $o = $e; $o; $o = $o->{owner}) {
        push @seg, qid($o->{v2});
        last if $o->{top};
    }
    return $e->{qn} = join '::', reverse @seg;
}

# Reference to a definition from code inside package $from.
sub tref {
    my ($t, $from) = @_;
    return $t->{lib} if $t->{lib};
    my $e = $t->{el};
    $e = stub_for($e) unless $EMIT{$e->{id}};
    return qid($e->{v2}) if $e->{stub} ? 0 : sees($from, $e);
    return qn($e);
}
sub sees {                          # is $e a direct member of $from or of a package enclosing $from?
    my ($from, $e) = @_;
    my $p = $e->{owner};
    return 0 unless $p && $p->{kind} =~ /^(?:package|model)$/;
    for (my $o = $from; $o; $o = $o->{owner}) { return 1 if $o == $p; last if $o->{top} }
    return 0;
}

# Out-of-slice definitions referenced by the slice get a stub, so the result still resolves.
sub stub_for {
    my $e = shift;
    return $STUB{$e->{id}} if $STUB{$e->{id}};
    my $s = { %$e, stub => 1, kids => [], v2 => undef, qn => undef, owner => $STUBPKG, top => 0 };
    v2name($s, 'def', 'stubs');
    $s->{lits} = [map { v2name($_, 'use', "stub$e->{id}") } grep { $_->{kind} eq 'literal' } @{$e->{kids}}] if $e->{kind} eq 'enum';
    $STUB{$e->{id}} = $s; push @STUBS, $s;
    note($e, 'note', "'" . qname($e) . "' is outside the slice; stubbed as " . qn($s));
    return $s;
}

sub doc_lines {
    my ($text, $ind) = @_;
    $text = squash($text);
    return () if $text eq '';
    $text =~ s{\*/}{* /}g;
    my $width = 96 - length($ind) - 8;
    my @w = split / /, $text; my @l = (''); 
    for my $w (@w) {
        if (length($l[-1]) && length($l[-1]) + 1 + length($w) > $width) { push @l, $w }
        else { $l[-1] .= (length $l[-1] ? ' ' : '') . $w }
    }
    my @out = ("${ind}doc /* $l[0]");
    push @out, "$ind     * $_" for @l[1 .. $#l];
    $out[-1] .= ' */';
    return @out;
}

sub mk { my $e = shift; $e->{stub} || !defined $e->{id} ? '' : "\x{1}$e->{id}\x{1}" }
sub prov_line {
    my ($e, $ind) = @_;
    return () unless $O{provenance};
    return ("$ind\@V1Source { xmiId = " . sq($e->{id}) . "; v1Name = " . sq($e->{name}) . "; }");
}

sub mult {
    my $n = shift;
    my ($lo, $up) = (kid($n, 'lowerValue'), kid($n, 'upperValue'));
    return '' unless $lo || $up;
    my $l = $lo ? ($lo->{a}{value} // 0) : 1;
    my $u = $up ? ($up->{a}{value} // 0) : 1;
    $u = '*' if $u eq '-1';
    return '' if $l eq '1' && $u eq '1';
    return "[$l]" if $l eq $u;
    return "[$l..$u]";
}

sub default_value {                 # returns (v2 text) or (undef, reason)
    my ($n, $t, $from) = @_;
    my $d = kid($n, 'defaultValue') or return ();
    my $ty = $d->{a}{'xmi:type'} // '';
    my $v = $d->{a}{value};
    my $lit;
    if ($ty eq 'uml:LiteralReal' || $ty eq 'uml:LiteralInteger' || $ty eq 'uml:LiteralUnlimitedNatural') {
        $lit = $v // 0; $lit = '*' if $lit eq '-1';
        return (undef, "default '$lit' is not a number") unless $lit =~ /^-?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?$/;
    } elsif ($ty eq 'uml:LiteralBoolean') { $lit = ($v // 'false') eq 'true' ? 'true' : 'false' }
    elsif ($ty eq 'uml:LiteralString') { $lit = sq($v // '') }
    elsif ($ty eq 'uml:InstanceValue') {
        my ($i) = refs($d, 'instance');
        my $le = $i && $E{$i};
        return (undef, 'default instance value') unless $le && $le->{kind} eq 'literal';
        my $en = tref({ el => $le->{owner} }, $from);          # stubs the enum if it is outside the slice
        return ($en . '::' . qid($le->{v2}));
    } else {
        my $body = squash(join ' ', map { text_of($_) } grep { $_->{tag} eq 'body' } elems($d));
        return (undef, "default is a $ty" . ($body ne '' ? " ($body)" : ''));
    }
    my $q = $t && $t->{el} && $t->{el}{kind} eq 'valuetype' ? quantity_of($t->{el}) : undef;
    my ($isq, $unit) = $t && $t->{lib} ? ($t->{lib} =~ /Value$/, $t->{unit}) : $q ? (1, $q->[1]) : (0, undef);
    if ($isq) {
        return ("$lit [$unit]") if $unit;
        return (undef, "default $lit has no unit SysML v2 can name");
    }
    return ($lit);
}

# One feature (property or port) of a definition.
sub feature_lines {
    my ($p, $owner, $ind, $from) = @_;
    my $n = $p->{node};
    my ($tr) = refs($n, 'type');
    my $t = resolve_type($tr);
    my $flow = has_st($p, qr/^FlowProperty$/) && $owner->{kind} eq 'interfaceblock';
    my $dir = $flow ? (st_attr($p, 'direction') // 'inout') : '';
    my ($kw, $comment) = ('', '');
    if ($t && $t->{el} && $t->{el}{kind} !~ $DEFRE) { $t = { unres => "'$t->{el}{name}' ($t->{el}{kind})" } }
    my $tk = $t && $t->{el} ? $t->{el}{kind} : '';
    if ($p->{kind} eq 'port') {
        $kw = 'port';
        if ($t && $t->{el} && $tk ne 'interfaceblock') {
            $comment = "v1 type '$t->{el}{name}' is a $tk, not an interface block";
            note($p, 'warning', "port '" . qname($p) . "': $comment; typed by nothing"); $t = undef;
        }
    } elsif ($tk =~ /^(?:block|class)$/) {
        $kw = $flow ? 'item' : ($n->{a}{aggregation} // '') eq 'composite' ? 'part' : 'ref part';
    } elsif ($tk eq 'constraintblock') { $kw = 'constraint' }
    elsif ($tk eq 'interfaceblock') { $kw = 'port'; note($p, 'warning', "property '" . qname($p) . "' typed by an interface block; made a port") }
    else { $kw = 'attribute' }
    if ($t && $t->{unres}) {
        $comment = "v1 type: $t->{unres}";
        note($p, 'warning', "'" . qname($p) . "' has unresolved type $t->{unres}; add it to a --typemap file");
        $t = undef;
    }
    note($p, 'warning', "'" . qname($p) . "' has no type") if !$tr;
    $kw = "$dir $kw" if $flow;
    my $name = qid(v2name($p, 'use', $owner->{id}));
    my @redef = grep { $E{$_} } refs($n, 'redefinedProperty');
    if (@redef) {
        my $r = $E{$redef[0]};
        my $rn = $r->{v2} // v2name($r, 'use', $r->{owner}{id});
        $name = $rn eq $p->{v2} ? ':>> ' . qid($rn) : "$name :>> " . qid($rn);
    }
    my $s = "$ind$kw $name";
    if ($t) {
        my $conj = $p->{kind} eq 'port' && ($n->{a}{isConjugated} // '') eq 'true' ? '~' : '';
        $s .= " : $conj" . tref($t, $from);
    }
    $s .= mult($n);
    my ($dv, $why) = default_value($n, $t, $from);
    if (defined $dv) { $s .= " default = $dv" }
    elsif ($why) { $comment = join '; ', grep { length } $comment, "v1 $why"; note($p, 'warning', "'" . qname($p) . "': $why") }
    $s .= ';' . mk($p);
    $s .= " // $comment" if $comment ne '';
    return ($s);
}

sub connector_line {
    my ($c, $owner, $ind) = @_;
    my @ends = grep { ($_->{a}{'xmi:type'} // '') eq 'uml:ConnectorEnd' } elems($c->{node});
    if (@ends != 2) { note($c, 'warning', "connector in '" . qname($owner) . "' has " . scalar(@ends) . " ends; not converted"); return () }
    my @path;
    for my $end (@ends) {
        my ($role) = refs($end, 'role'); my ($pwp) = refs($end, 'partWithPort');
        my $re = $role && $E{$role};
        unless ($re && $EMIT{$re->{id}}) { note($c, 'warning', "connector end in '" . qname($owner) . "' has an unknown role; not converted"); return () }
        my $pe = $pwp && $E{$pwp};
        push @path, ($pe ? qid($pe->{v2} // v2name($pe, 'use', $pe->{owner}{id})) . '.' : '')
                    . qid($re->{v2} // v2name($re, 'use', $re->{owner}{id}));
    }
    $NCONV++;
    my $label = $c->{name} =~ /\S/ ? 'connection ' . qid(v2name($c, 'use', $owner->{id})) . ' ' : '';
    return ("$ind${label}connect $path[0] to $path[1];");
}

sub general_list {
    my ($e, $from) = @_;
    my @g;
    for my $k (grep { $_->{kind} eq 'generalization' } @{$e->{kids}}) {
        my ($r) = refs($k->{node}, 'general');
        my $t = resolve_type($r);
        $t = { unres => "'$t->{el}{name}' ($t->{el}{kind})" } if $t && $t->{el} && $t->{el}{kind} !~ $DEFRE;
        if (!$t || $t->{unres}) { note($e, 'warning', "'" . qname($e) . "' specializes unresolved " . ($t ? $t->{unres} : '?')); next }
        push @g, tref($t, $from);
    }
    return @g ? ' :> ' . join(', ', @g) : '';
}

sub def_kw {
    my $k = shift->{kind};
    return { block => 'part def', class => 'part def', interfaceblock => 'port def',
             constraintblock => 'constraint def', valuetype => 'attribute def', enum => 'enum def' }->{$k};
}

sub emit_def {
    my ($e, $L, $ind, $from) = @_;
    my $kw = def_kw($e);
    my $head = "$ind$kw " . qid($e->{v2});
    if ($e->{kind} eq 'valuetype') {
        my $q = quantity_of($e);
        my $g = general_list($e, $from);
        $g = " :> $q->[0]" if $g eq '' && $q;
        $head .= $g;
    } else { $head .= general_list($e, $from) }
    my @body;
    push @body, doc_lines(owned_comments($e), "$ind    ");
    push @body, prov_line($e, "$ind    ");
    if ($e->{stub}) { push @body, "$ind    // stub: defined outside the converted slice", map { "$ind    enum " . qid($_) . ';' } @{$e->{lits} // []} }
    for my $k (@{$e->{kids}}) {
        next if $k->{stub} || $e->{stub};
        if ($k->{kind} eq 'literal') { push @body, "${ind}    enum " . qid(v2name($k, 'use', $e->{id})) . ';' . mk($k); $NCONV++ }
        elsif ($k->{kind} =~ /^(?:property|port)$/) {
            my @l = feature_lines($k, $e, "$ind    ", pkg_of($e));
            if ($e->{kind} eq 'constraintblock') { s/^(\s*)attribute /$1in / for @l }
            push @body, @l; $NCONV++;
        }
        elsif ($k->{kind} eq 'constraint') {
            my $spec = kid($k->{node}, 'specification');
            my $b = $spec ? squash(join ' ', map { text_of($_) } grep { $_->{tag} eq 'body' } elems($spec)) : '';
            push @body, "$ind    // v1 constraint" . ($k->{name} =~ /\S/ ? " $k->{name}" : '') . ": {$b} (convert by hand)";
            note($k, 'warning', "constraint in '" . qname($e) . "' needs a v2 expression: $b");
        }
        elsif ($k->{kind} =~ /^(?:behavior|operation)$/) {
            push @body, "$ind    // v1 $k->{type} '$k->{name}' not converted";
            note($k, $k->{kind} eq 'operation' ? 'warning' : 'note', "$k->{type} '" . qname($k) . "' not converted");
        }
        elsif ($k->{kind} =~ $DEFRE || $k->{kind} eq 'requirement') { }   # nested defs below
    }
    for my $k (grep { $_->{kind} eq 'connector' } @{$e->{kids}}) { push @body, connector_line($k, $e, "$ind    ") }
    for my $k (grep { $EMIT{$_->{id}} && ($_->{kind} =~ $DEFRE) } @{$e->{kids}}) {
        my @sub; emit_def($k, \@sub, "$ind    ", $from); push @body, @sub;
    }
    if (@body) { push @$L, "$head {" . mk($e), @body, "$ind}" } else { push @$L, "$head;" . mk($e) }
    $NCONV++ unless $e->{stub};
}

my %RIDSEEN;
sub emit_req {
    my ($r, $L, $ind) = @_;
    my $id = req_id($r);
    note($r, 'warning', "requirement id '$id' is also used at line $RIDSEEN{$id}") if $id ne '' && $RIDSEEN{$id};
    $RIDSEEN{$id} //= $r->{line};
    my $head = "${ind}requirement " . ($id ne '' ? "<" . q_short($id) . "> " : '') . qid($r->{v2});
    my @body = doc_lines(req_text($r), "$ind    ");
    my $c = owned_comments($r);
    push @body, map { s{^(\s*)doc /\*}{$1/* v1 comment:}r } doc_lines($c, "$ind    ") if $c ne '';
    push @body, prov_line($r, "$ind    ");
    my @sub;
    emit_req($_, \@sub, "$ind    ") for grep { $_->{kind} eq 'requirement' && $EMIT{$_->{id}} } @{$r->{kids}};
    note($r, 'warning', "requirement '" . ($r->{rid} // qname($r)) . "' has no text") if req_text($r) eq '';
    if (@body || @sub) { push @$L, "$head {" . mk($r), @body, @sub, "$ind}" } else { push @$L, "$head;" . mk($r) }
    $NCONV++;
}
sub q_short { my $s = shift; $s =~ s/(['\\])/\\$1/g; "'$s'" }

sub std_imports {
    my ($ind, @extra) = @_;
    my @l = map { "${ind}private import $_\::*;" } qw(ScalarValues ISQ SI), @extra;
    push @l, "${ind}private import SecMeta::*;" if $O{marking};
    push @l, "${ind}private import V1Provenance::*;" if $O{provenance};
    push @l, "$ind\@Marking { level = Level::$O{marking}; }" if $O{marking};
    return @l;
}

sub emit_package {
    my ($p, $L, $ind) = @_;
    my $from = $p;
    push @$L, "${ind}package " . qid($p->{v2}) . " {" . mk($p);
    my $doc = owned_comments($p);
    $doc = "Converted from SysML v1 package '" . qname($p) . "' by v1v2.pl." if $doc eq '' && $p->{top};
    push @$L, doc_lines($doc, "$ind    ");
    push @$L, std_imports("$ind    ") if $p->{top};
    push @$L, prov_line($p, "$ind    ") if $p->{kind} eq 'package';
    my @k = grep { $EMIT{$_->{id}} } @{$p->{kids}};
    my @order = ((grep { $_->{kind} =~ /^(?:valuetype|enum)$/ } @k), (grep { $_->{kind} eq 'interfaceblock' } @k),
                 (grep { $_->{kind} =~ /^(?:block|class|constraintblock)$/ } @k));
    for my $e (@order) { push @$L, ''; emit_def($e, $L, "$ind    ", $from) }
    for my $r (grep { $_->{kind} eq 'requirement' } @k) { push @$L, ''; emit_req($r, $L, "$ind    ") }
    for my $s (grep { $_->{kind} eq 'package' } @k) { push @$L, ''; emit_package($s, $L, "$ind    ") }
    for my $x (grep { !$_->{inside} && $_->{kind} =~ /^(?:behavior|usecase|instance|itemflow|allocate)$/
                      && !($_->{kind} eq 'instance' && $UNIT{lc squash($_->{name})}) } @{$p->{kids}}) {
        if ($VERIFIER{$x->{id}}) { push @$L, '', "$ind    // v1 $x->{type} '$x->{name}': its verify relationships became a verification def"; next }
        push @$L, '', "$ind    // v1 $x->{type} '$x->{name}' not converted";
        note($x, $x->{kind} =~ /^(?:behavior|usecase)$/ ? 'note' : 'warning', "$x->{type} '" . qname($x) . "' not converted");
    }
    push @$L, "$ind}";
}

# Satisfy, verify and dependency packages, generated from v1 trace relationships.
sub req_path {
    my ($r, $chain) = @_;
    my @rs; my $o = $r;
    for (; $o && $o->{kind} eq 'requirement'; $o = $o->{owner}) { unshift @rs, qid($o->{v2}) }
    return qn($o) . '::' . join($chain ? '.' : '::', @rs);
}

sub emit_trace_packages {
    my ($base, $files) = @_;
    my (@sat, %ver, @dep);
    for my $t (traces()) {
        my ($k, $cl, $su, $rec) = @$t;
        for my $s (@$su) {
            my $se = $E{$s};
            unless ($se && $se->{kind} eq 'requirement' && $EMIT{$se->{id}}) {
                note($rec, 'note', "$k to " . ($se ? "'" . qname($se) . "'" : $s) . " skipped: not a converted requirement")
                    if $se && in_scope($se) || grep { $E{$_} && $EMIT{$_} } @$cl;
                next;
            }
            for my $c (@$cl) {
                my $ce = $E{$c};
                unless ($ce) { note($rec, 'warning', "$k client $c is not in the file"); next }
                if ($k eq 'satisfy') { push @sat, [$ce, $se, $rec] }
                elsif ($k eq 'verify') { push @{$ver{$ce->{id}}}, [$ce, $se, $rec] }
                elsif ($k =~ /^(?:derive|refine|trace|copy)$/) { push @dep, [$k, $ce, $se, $rec] }
                else { note($rec, 'warning', "$k from '" . qname($ce) . "' not converted") }
            }
        }
    }
    if (@sat) {
        my $pk = { kind => 'package', v2 => "${base}Satisfaction", top => 1, id => 'sat', kids => [] };
        my @L = ("package $pk->{v2} {", doc_lines('Satisfy relationships converted from SysML v1 by v1v2.pl. One part usage per satisfying block, so that each satisfy has a feature to name.', '    '), std_imports('    '));
        my %use;
        my $usage = sub { my $b = shift;
            $b = stub_for($b) unless $EMIT{$b->{id}} || $b->{stub};
            $use{$b->{id}} //= do {
                my $n = camel($b->{v2}, 0); my $base = $n; my $i = 1;
                $n = $base . ++$i while $TAKEN{"sat\0$n"}; $TAKEN{"sat\0$n"} = 1;
                push @L, '', "    part $n : " . qn($b) . ';'; $n } };
        for my $x (@sat) {
            my ($ce, $se, $rec) = @$x;
            my $by;
            if ($ce->{kind} =~ /^(?:block|class)$/) {
                $by = $usage->($ce);
            } elsif ($ce->{kind} =~ /^(?:property|port)$/ && $EMIT{$ce->{id}} && $ce->{owner}{kind} =~ /^(?:block|class)$/) {
                $by = $usage->($ce->{owner}) . '.' . qid($ce->{v2});
            } else { note($rec, 'warning', "satisfy from $ce->{kind} '" . qname($ce) . "' not converted; needs a part or feature"); next }
            push @L, "    satisfy " . req_path($se, 1) . " by $by;"; $NCONV++;
        }
        push @L, '}';
        $files->{"configurations/$pk->{v2}.sysml"} = \@L;
    }
    if (%ver) {
        my $pk = "${base}Verification";
        my @L = ("package $pk {", doc_lines('Verification cases converted from SysML v1 verify relationships by v1v2.pl. The v1 test behavior is not converted; each case holds only its objective.', '    '), std_imports('    '));
        my %tk;
        for my $id (sort { $ver{$a}[0][0]{line} <=> $ver{$b}[0][0]{line} } keys %ver) {
            my $ce = $ver{$id}[0][0];
            my $n = camel($ce->{name}, 1); $n = 'UnnamedVerification' if $n eq '';
            $n .= 'Test' unless $n =~ /(?:Test|Inspection|Analysis|Demonstration)$/;
            my $b = $n; my $i = 1; $n = $b . ++$i while $tk{lc $n}; $tk{lc $n} = 1;
            push @L, '', "    verification def $n {",
                doc_lines("v1 verifier: '" . qname($ce) . "' ($ce->{type}).", '        '),
                prov_line($ce, '        '), '        objective {';
            push @L, "            verify " . req_path($_->[1], 1) . ';' for @{$ver{$id}};
            push @L, '        }', '    }';
            $NCONV++;
            note($ce, 'note', "verifier '" . qname($ce) . "' became verification def $pk\::$n (objective only)");
        }
        push @L, '}';
        $files->{"evaluation/$pk.sysml"} = \@L;
    }
    if (@dep) {
        my $pk = "${base}Trace";
        my @L = ("package $pk {", doc_lines('SysML v1 deriveReqt, refine, trace and copy relationships, as dependencies from client to supplier. Generated by v1v2.pl.', '    '), std_imports('    '));
        for my $x (@dep) {
            my ($k, $ce, $se, $rec) = @$x;
            my $cn = $ce->{kind} eq 'requirement' && $EMIT{$ce->{id}} ? req_path($ce, 0)
                   : ($EMIT{$ce->{id}} && $ce->{kind} =~ $DEFRE) ? qn($ce) : undef;
            unless ($cn) { note($rec, 'warning', "$k from '" . qname($ce) . "' not converted"); next }
            push @L, "    dependency from $cn to " . req_path($se, 0) . "; // v1 $k"; $NCONV++;
        }
        push @L, '}';
        $files->{"requirements/$pk.sysml"} = \@L;
    }
}

sub find_scope {
    my $qn = shift;
    return $MODEL // fail("$IN: no uml:Model element") unless defined $qn;
    my @hit = grep { $_->{kind} =~ /^(?:package|model)$/ && qname($_) eq $qn } @ALL;
    fail("$IN: no package '$qn'" . (@hit ? '' : '; packages: ' . join(', ', map { qname($_) } grep { $_->{kind} eq 'package' && $_->{owner} == $MODEL } @ALL))) unless @hit == 1;
    return $hit[0];
}

sub notes { map { $_->[2] } sort { $a->[0] <=> $b->[0] || $a->[1] <=> $b->[1] } @NOTES }
sub cmd_convert {
    fail('convert needs -o DIR') unless $O{o};
    fail("--marking must be an identifier") if defined $O{marking} && $O{marking} !~ /^\w+$/;
    load_model($IN);
    $SCOPE = find_scope($O{package});
    for my $t (traces()) { next unless $t->[0] eq 'verify'; $VERIFIER{$_} = 1 for @{$t->[1]} }
    # what gets emitted
    for my $e (grep { in_scope($_) && !$_->{inside} } @ALL) {
        $EMIT{$e->{id}} = 1 if $e->{kind} =~ /^(?:package|requirement|property|port|literal)$/ || $e->{kind} =~ $DEFRE;
    }
    for my $e (grep { $EMIT{$_->{id}} && $_->{kind} eq 'valuetype' } @ALL) {   # library look-alikes
        my $t = resolve_type($e->{id});
        if ($t->{lib}) { delete $EMIT{$e->{id}}; note($e, 'note', "value type '" . qname($e) . "' mapped to library type $t->{lib}") }
    }
    # top-level packages: the scope's child packages (or the scope itself when it is a package)
    my @tops;
    if ($SCOPE->{kind} eq 'model') {
        @tops = grep { $_->{kind} eq 'package' } @{$SCOPE->{kids}};
        if (grep { $EMIT{$_->{id}} && $_->{kind} ne 'package' } @{$SCOPE->{kids}}) { push @tops, $SCOPE }
    } else { @tops = ($SCOPE) }
    my $base = camel($O{prefix} // '', 1) . camel(($SCOPE->{name} =~ /\S/ ? $SCOPE->{name} : 'Model'), 1);
    $base = camel($O{prefix} // '', 1) . 'Model' if $base eq '';
    for my $t (@tops) { $t->{top} = 1; $t->{v2} = top_pkg_name($t) }
    if ($SCOPE->{kind} eq 'model') { delete $EMIT{$_->{id}} for grep { $_->{kind} eq 'package' && $_->{owner} == $SCOPE } @ALL; $EMIT{$_->{id}} = 1 for @tops }
    $STUBPKG = { kind => 'package', v2 => "${base}SliceStubs", top => 1, id => 'stubs', kids => [] };
    # names, depth first, so siblings get unique names in document order
    my $nm; $nm = sub {
        my $e = shift;
        for my $k (@{$e->{kids}}) {
            next unless $EMIT{$k->{id}};
            v2name($k, ($k->{kind} =~ $DEFRE || $k->{kind} eq 'package') ? 'def' : 'use', $e->{id}) unless $k->{top};
            $nm->($k);
        }
    };
    $nm->($_) for @tops;
    my %files;
    for my $t (@tops) {
        my @L;
        if ($t->{kind} eq 'model') {
            local $t->{kids} = [grep { $_->{kind} ne 'package' } @{$t->{kids}}];
            emit_package($t, \@L, '');
        } else { emit_package($t, \@L, '') }
        my $only_req = !grep { $_->{kind} =~ $DEFRE } grep { $EMIT{$_->{id}} && in_tree($_, $t) } @ALL;
        my $f = ($only_req ? 'requirements/' : 'architecture/') . "$t->{v2}.sysml";
        $files{$f} = \@L; $FILEOF{$t->{id}} = $f;
    }
    emit_trace_packages($base, \%files);
    if (@STUBS) {
        my @L = ("package $STUBPKG->{v2} {", doc_lines('Stubs for definitions outside the converted slice. Replace each with the real definition, or widen the slice.', '    '), std_imports('    '));
        for my $s (@STUBS) { push @L, ''; local $s->{kids} = []; emit_def($s, \@L, '    ', $STUBPKG) }
        push @L, '}';
        $files{"library/$STUBPKG->{v2}.sysml"} = \@L;
    }
    if ($O{provenance}) {
        $files{'library/V1Provenance.sysml'} = [
            'library package V1Provenance {',
            doc_lines('Where a converted element came from in the SysML v1 model: its XMI id and its v1 name. Generated by v1v2.pl.', '    '),
            '    private import ScalarValues::*;',
            ($O{marking} ? ('    private import SecMeta::*;', "    \@Marking { level = Level::$O{marking}; }") : ()),
            '', '    metadata def V1Source {',
            '        doc /* Provenance of an element converted from SysML v1. */',
            '        attribute xmiId : String;', '        attribute v1Name : String;', '    }', '}' ];
    }
    # write
    my $out = $O{o};
    my $stamp = "// Generated by v1v2.pl $VERSION from " . basename($IN) . '. Edit the result, not this tool output, once it is committed.';
    my %AT;
    for my $f (sort keys %files) {
        my $path = "$out/model/$f";
        (my $dir = $path) =~ s{/[^/]+$}{}; make_path($dir);
        open my $h, '>:encoding(UTF-8)', $path or fail("$path: $!");
        print $h "$stamp\n";
        my $ln = 1;
        for my $l (@{$files{$f}}) {
            $ln++;
            $AT{$1} //= "model/$f:$ln" while $l =~ s/\x{1}([^\x{1}]*)\x{1}//;
            print $h "$l\n";
        }
        close $h;
    }
    # id map: element -> v2 name and file:line (line counts the stamp)
    my @rows;
    for my $e (grep { $EMIT{$_->{id}} && defined $_->{v2} } @ALL) {
        my $at = $AT{$e->{id}} // '';
        my $q = $e->{kind} eq 'requirement' ? req_path($e, 1) : qn($e);
        push @rows, join "\t", $e->{id}, $e->{kind}, qname($e), $q, $at;
    }
    open my $h, '>:encoding(UTF-8)', "$out/ids.tsv" or fail("$out/ids.tsv: $!");
    print $h "xmi_id\tv1_kind\tv1_name\tv2_name\tat\n", map { "$_\n" } @rows; close $h;
    my $nren = grep { $RENAMED{$_} && $EMIT{$_} } keys %RENAMED;
    my $summary = sprintf "convert: %d file(s) written, %d element(s) converted, %d renamed, %d stub(s), %d to finish by hand",
        scalar(keys %files), $NCONV // 0, $nren, scalar @STUBS, $NMANUAL // 0;
    open $h, '>:encoding(UTF-8)', "$out/CONVERSION.txt" or fail("$out/CONVERSION.txt: $!");
    print $h "# v1v2.pl $VERSION convert $IN" . ($O{package} ? " --package '$O{package}'" : '') . "\n",
             "# Locations point into the v1 XMI. 'warning' = finish by hand; 'note' = information.\n",
             map({ "$_\n" } notes()), "$summary\n";
    close $h;
    print "$_\n" for grep { /: warning: / } notes();
    print "$summary\n";
    print "see $out/CONVERSION.txt and $out/ids.tsv\n";
    exit(($NMANUAL // 0) ? 1 : 0);
}
sub in_tree { my ($e, $t) = @_; for (my $o = $e; $o; $o = $o->{owner}) { return 1 if $o == $t; return 0 if $o->{top} && $o != $t } 0 }

# --------------------------------------------------------------------------------------------
# reqs : requirements from ReqIF or CSV into one requirements package
# --------------------------------------------------------------------------------------------
sub cmd_reqs {
    fail('reqs needs -o FILE.sysml') unless $O{o};
    fail('reqs needs --package NAME') unless $O{package};
    fail("--package must be an identifier") unless ident_ok($O{package});
    fail("--marking must be an identifier") if defined $O{marking} && $O{marking} !~ /^\w+$/;
    $O{provenance} = 0;
    no warnings 'redefine';
    local *req_id = sub { $_[0]{rid} // '' };
    local *req_text = sub { $_[0]{rtext} // '' };
    local *owned_comments = sub { '' };
    local *qname = sub { $_[0]{rid} // $_[0]{name} };
    my @r = $IN =~ /\.reqifz?$/i ? reqif_rows($IN) : csv_rows($IN);
    my (%byid, @roots, %warned);
    for my $r (@r) {
        $r->{kind} = 'requirement'; $r->{kids} = []; $r->{line} //= 1;
        $byid{$r->{rid}} //= $r if $r->{rid} ne '';
    }
    for my $r (@r) {
        my $p = $r->{up};
        if (!$p && defined $r->{parent} && $r->{parent} ne '') {
            $p = $byid{$r->{parent}} or note($r, 'warning', "parent '$r->{parent}' of '$r->{rid}' not found");
        }
        if (!$p && !defined $O{parent} && $IN !~ /\.reqifz?$/i && $r->{rid} =~ /^(.+)[.\-]\w+$/) { $p = $byid{$1} }
        if ($p) { push @{$p->{kids}}, $r; $r->{owner} = $p } else { push @roots, $r }
    }
    $EMIT{$_->{id}} = 1 for @r;
    my $nm; $nm = sub { my ($list, $scope) = @_;
        for my $r (@$list) { v2name($r, 'use', $scope); $nm->($r->{kids}, $r->{id}) } };
    $nm->(\@roots, 'root');
    my @L = ("package $O{package} {", doc_lines("Requirements imported from " . basename($IN) . " by v1v2.pl. Add a subject and, where quantitative, a require constraint to each.", '    '), std_imports('    '));
    for my $r (@roots) { push @L, ''; emit_req($r, \@L, '    ') }
    push @L, '}';
    open my $h, '>:encoding(UTF-8)', $O{o} or fail("$O{o}: $!");
    print $h "// Generated by v1v2.pl $VERSION from " . basename($IN) . ".\n", map { s/\x{1}[^\x{1}]*\x{1}//gr . "\n" } @L;
    close $h;
    print "$_\n" for notes();
    printf "reqs: %d requirement(s), %d top-level, %d without id, %d without text -> %s\n",
        scalar @r, scalar @roots, scalar(grep { $_->{rid} eq '' } @r), scalar(grep { $_->{rtext} eq '' } @r), $O{o};
    exit(($NMANUAL // 0) ? 1 : 0);
}

sub csv_rows {
    my $f = shift;
    my $t = slurp($f);
    my (@rows, @row); my ($field, $line, $rowline) = ('', 1, 1);
    pos($t) = 0;
    while (pos($t) < length $t) {
        if ($t =~ /\G"((?:[^"]|"")*)"/gc) { (my $v = $1) =~ s/""/"/g; $line += ($v =~ tr/\n//); $field .= $v }
        elsif ($t =~ /\G([^",\n]+)/gc) { $field .= $1 }
        elsif ($t =~ /\G,/gc) { push @row, $field; $field = '' }
        elsif ($t =~ /\G\n/gc) { push @row, $field; push @rows, [$rowline, @row]; @row = (); $field = ''; $line++; $rowline = $line }
        else { fail("$f:$line: bad CSV quoting") }
    }
    push @row, $field; push @rows, [$rowline, @row] if grep { length } @row;
    my $hdr = shift @rows or fail("$f: empty CSV");
    my (undef, @h) = @$hdr;
    my $col = sub {
        my ($opt, $re) = @_;
        for my $i (0 .. $#h) { return $i if defined $O{$opt} ? lc squash($h[$i]) eq lc $O{$opt} : $h[$i] =~ $re }
        fail("$f: no column '$O{$opt}'; columns: " . join(', ', @h)) if defined $O{$opt};
        return undef;
    };
    my ($ci, $cn, $ct, $cp) = ($col->('id', qr/^\s*(?:id|req(?:uirement)?[ _]?id|identifier)\s*$/i),
        $col->('name', qr/^\s*(?:name|title)\s*$/i), $col->('text', qr/^\s*(?:text|description|requirement text|shall)\s*$/i),
        $col->('parent', qr/^\s*(?:parent|parent id|owner)\s*$/i));
    fail("$f: need an id or a text column (use --id and --text); columns: " . join(', ', @h)) unless defined $ci || defined $ct;
    my @r; my $n = 0;
    for my $row (@rows) {
        my ($ln, @v) = @$row;
        next unless grep { /\S/ } @v;
        push @r, { id => 'csv' . ++$n, line => $ln, rid => squash(defined $ci ? $v[$ci] : ''),
                   name => squash(defined $cn ? $v[$cn] : ''), rtext => squash(html2text(defined $ct ? $v[$ct] : '')),
                   parent => defined $cp ? squash($v[$cp]) : undef };
    }
    return @r;
}

sub reqif_rows {
    my $f = shift;
    my ($doc) = eval { parse_xml(slurp($f), $f) } or do { print STDERR $@; exit 2 };
    my (%adef, %obj, @all);
    my $find; $find = sub { my ($n, $tag, $out) = @_; for my $k (elems($n)) { push @$out, $k if $k->{tag} eq $tag; $find->($k, $tag, $out) } };
    for my $tag (map { "ATTRIBUTE-DEFINITION-$_" } qw(STRING XHTML ENUMERATION INTEGER REAL DATE BOOLEAN)) {
        my @d; $find->($doc, $tag, \@d);
        $adef{$_->{a}{IDENTIFIER}} = $_->{a}{'LONG-NAME'} // $_->{a}{IDENTIFIER} for @d;
    }
    my $pick = sub { my ($opt, $re) = @_; return sub { my $n = shift; defined $O{$opt} ? lc $n eq lc $O{$opt} : $n =~ $re } };
    my $isid = $pick->('id', qr/^(?:ReqIF\.ForeignID|Id|ID|Identifier|Req(?:uirement)?\s*ID)$/i);
    my $isnm = $pick->('name', qr/^(?:ReqIF\.Name|Name|Title|ReqIF\.ChapterName)$/i);
    my $istx = $pick->('text', qr/^(?:ReqIF\.Text|Text|Description|Object Text)$/i);
    my @so; $find->($doc, 'SPEC-OBJECT', \@so);
    for my $o (@so) {
        my $r = { id => $o->{a}{IDENTIFIER}, line => $o->{line}, rid => '', name => $o->{a}{'LONG-NAME'} // '', rtext => '' };
        my $vals = kid($o, 'VALUES');
        for my $v ($vals ? elems($vals) : ()) {
            my $def = kid($v, 'DEFINITION') or next;
            my ($ref) = elems($def); next unless $ref;
            my $an = $adef{squash(text_of($ref))} // next;
            my $val = defined $v->{a}{'THE-VALUE'} ? $v->{a}{'THE-VALUE'}
                    : kid($v, 'THE-VALUE') ? text_of(kid($v, 'THE-VALUE')) : '';
            $val = squash(html2text($val));
            if ($isid->($an)) { $r->{rid} = $val } elsif ($istx->($an)) { $r->{rtext} = $val } elsif ($isnm->($an)) { $r->{name} = $val }
        }
        $r->{rid} = $o->{a}{IDENTIFIER} // '' if $r->{rid} eq '' && !defined $O{id};
        $obj{$r->{id}} = $r; push @all, $r;
    }
    # hierarchy from SPEC-HIERARCHY nesting; objects not in any hierarchy stay top level
    my @order;
    my $walk; $walk = sub { my ($n, $parent) = @_;
        for my $h (grep { $_->{tag} eq 'SPEC-HIERARCHY' } elems($n)) {
            my $ob = kid($h, 'OBJECT'); my ($ref) = $ob ? elems($ob) : ();
            my $r = $ref && $obj{squash(text_of($ref))};
            if ($r && !$r->{placed}++) { $r->{up} = $parent; push @order, $r }
            my $ch = kid($h, 'CHILDREN'); $walk->($ch, $r // $parent) if $ch;
        } };
    my @specs; $find->($doc, 'SPECIFICATION', \@specs);
    for my $s (@specs) { my $ch = kid($s, 'CHILDREN'); $walk->($ch, undef) if $ch }
    push @order, grep { !$_->{placed} } @all;
    my @rel; $find->($doc, 'SPEC-RELATION', \@rel);
    note(undef, 'note', scalar(@rel) . " SPEC-RELATION(s) not converted") if @rel;
    return @order;
}

# --------------------------------------------------------------------------------------------
# main (last, so every table above is initialized)
# --------------------------------------------------------------------------------------------
my %DISPATCH = (inventory => \&cmd_inventory, check => \&cmd_check,
                convert => \&cmd_convert, reqs => \&cmd_reqs);
($DISPATCH{$cmd} // \&usage)->();
exit 0;
