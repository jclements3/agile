package SysmlText;
# SysML v2 textual-notation helpers shared by the model-port tools (Xmi.pm, Reqif.pm): names, string literals,
# doc comments, the requirement shapes, and a lightweight structural self-check of the text we write.
#
#   name($s)        -> $s as a SysML v2 name: a basic name when it is one (and not a reserved word), else an
#                      unrestricted name '...' with \' and \\ escaped
#   ident($s)       -> $s forced into a basic name ([A-Za-z_]\w*), for names the metrics grep (requirements)
#   str($s)         -> "..." string literal
#   doc($text, $ind)-> the lines of a doc comment
#   requirement({ name, doorsId, text, title, vm, attrs => [[k, v]] }, $style, $ind) -> lines
#       style 'def'  : requirement def NAME { doc; attribute doorsId = "..."; ... }  (multi-line)
#       style 'usage': requirement NAME { doc /* ... */ attribute doorsId = "..."; ... }  (one line: the form
#                      bin/status-metrics.pl's parse_model counts)
#   check({ path => text, ... }) -> [ "path:line: problem", ... ]
#       balanced braces/brackets/parens, terminated comments/strings/names, and every referenced type, specialized
#       definition, satisfy/verify target, connect/bind end head and import resolves to a name declared somewhere in
#       the file set, or to a standard-library name (ScalarValues, ISQ, SI, RequirementDerivation, ...). Name
#       resolution is by name, not by scope -- a real checker (tools/sysml/sysml.pl, when present) is stricter.
use strict;
use warnings;

our @EXPORT = qw(name ident str doc requirement check is_keyword);
sub import {
    my ($class, @want) = @_;
    my $caller = caller;
    no strict 'refs';
    for my $n (@want ? @want : @EXPORT) {
        die "SysmlText: unknown function '$n'\n" unless defined &{"SysmlText::$n"};
        *{"${caller}::$n"} = \&{"SysmlText::$n"};
    }
}

# SysML v2 reserved words (KerML + SysML textual notation, 2.0)
our %KEYWORD = map { $_ => 1 } qw(
    about abstract accept action actor after alias all allocate allocation analysis and as assert assign assume assumption at
    attribute bind binding by calc case comment concern connect connection constant constraint crosses decide def
    default defined dependency derived do doc effect else end entry enum event exhibit exit expose false filter first flow
    for fork frame from guard hastype if implies import in include individual inout interface istype item join language
    library locale loop merge message meta metadata new nonunique not null objective occurrence of or ordered out
    package parallel part perform port private protected public redefines ref references render rendering rep
    require requirement return satisfy send snapshot specializes stakeholder standard state subject subsets
    succession terminate then timeslice to transition trigger true typed until use variant variation verification verify via
    view viewpoint when while xor);

sub is_keyword { return $KEYWORD{ $_[0] } ? 1 : 0 }

sub name {
    my ($s) = @_;
    $s = '' unless defined $s;
    return $s if $s =~ /^[A-Za-z_][A-Za-z0-9_]*$/ && !$KEYWORD{$s};
    (my $q = $s) =~ s/([\\'])/\\$1/g;
    $q =~ s/\n/\\n/g; $q =~ s/\t/\\t/g; $q =~ s/\r//g;
    return "'$q'";
}

sub ident {
    my ($s) = @_;
    $s = '' unless defined $s;
    $s =~ s/[^A-Za-z0-9_]+/_/g;
    $s =~ s/^_+|_+$//g;
    $s = "R_$s" if $s eq '' || $s =~ /^[0-9]/;
    $s .= '_' if $KEYWORD{$s};
    return $s;
}

sub str {
    my ($s) = @_;
    $s = '' unless defined $s;
    $s =~ s/\s*\n\s*/ /g; $s =~ s/\r//g;
    $s =~ s/([\\"])/\\$1/g;
    return qq("$s");
}

sub _doc_body {                               # text safe inside /* ... */
    my ($t) = @_;
    $t =~ s/\r//g;
    $t =~ s{\*/}{* /}g;
    $t =~ s{/\*}{/ *}g;
    $t =~ s/[ \t]+$//mg; $t =~ s/^\s*\n//; $t =~ s/\s+$//;
    return $t;
}

sub doc {
    my ($text, $ind) = @_;
    $ind = '' unless defined $ind;
    my $t = _doc_body(defined $text ? $text : '');
    return ("${ind}doc /* $t */") if $t !~ /\n/ && length($t) <= 100;
    return ("${ind}doc", "${ind}    /*", (map { $_ eq '' ? "${ind}     *" : "${ind}     * $_" } split /\n/, $t), "${ind}     */");
}

sub _oneline { my $t = _doc_body(defined $_[0] ? $_[0] : ''); $t =~ s/\s*\n\s*/ /g; return $t }

sub requirement {
    my ($r, $style, $ind) = @_;
    $style ||= 'def'; $ind = '' unless defined $ind;
    my @attrs;
    push @attrs, [ 'doorsId', $r->{doorsId} ] if defined $r->{doorsId} && $r->{doorsId} ne '';
    push @attrs, [ 'title', $r->{title} ] if defined $r->{title} && $r->{title} ne '';
    push @attrs, [ 'verificationMethod', $r->{vm} ] if defined $r->{vm} && $r->{vm} ne '';
    push @attrs, @{ $r->{attrs} || [] };
    my @extra = @{ $r->{body} || [] };       # extra body lines (already SysML), e.g. TODO comments
    if ($style eq 'usage') {
        my @b;
        push @b, 'doc /* ' . _oneline($r->{text}) . ' */' if defined $r->{text} && $r->{text} =~ /\S/;
        push @b, 'attribute ' . ident($_->[0]) . ' = ' . str($_->[1]) . ';' for @attrs;
        my $l = "${ind}requirement $r->{name} { " . join(' ', @b) . ' }';
        $l =~ s/\{  \}/{ }/;
        return ($l, map { "$ind$_" } @extra);
    }
    my @l = ("${ind}requirement def $r->{name} {");
    push @l, doc($r->{text}, "$ind    ") if defined $r->{text} && $r->{text} =~ /\S/;
    push @l, "$ind    attribute " . ident($_->[0]) . ' = ' . str($_->[1]) . ';' for @attrs;
    push @l, map { "$ind    $_" } @extra;
    push @l, "$ind}";
    return @l;
}

# ---- the structural self-check

our %LIBPKG = map { $_ => 1 } qw(ScalarValues ISQ SI USCustomaryUnits Quantities MeasurementReferences
    RequirementDerivation Base Links Occurrences Items Parts Ports Actions Requirements VerificationCases
    Connections Interfaces Constraints Calculations Cases UseCases Metaobjects Collections SequenceFunctions
    ControlFunctions BaseFunctions NumericalFunctions Time KerML SysML ISQBase ISQSpaceTime ISQMechanics
    ISQThermodynamics ISQElectromagnetism ShapeItems SpatialItems VerdictKind VerificationMethodKind
    RiskMetadata ModelingMetadata ParametersOfInterestMetadata ImageMetadata TradeStudies AnalysisTooling);
our %LIBNAME = map { $_ => 1 } qw(Real Integer Natural Positive Boolean String Complex Rational Number
    NumericalValue ScalarValue Anything start done self that);

sub _tokens {                                 # text -> ([kind, value, line], ...) and problems; comments/strings dropped
    my ($t, $path) = @_;
    my (@tok, @bad);
    my $line = 1;
    pos($t) = 0;
    while (pos($t) < length $t) {
        if ($t =~ /\G(\s+)/gc) { $line += ($1 =~ tr/\n//); next }
        if ($t =~ m{\G//[^\n]*}gc) { next }
        if ($t =~ m{\G/\*}gc) {
            if ($t =~ m{\G(.*?)\*/}gcs) { $line += ($1 =~ tr/\n//) } else { push @bad, "$path:$line: unterminated comment"; last }
            next;
        }
        if ($t =~ /\G"((?:[^"\\\n]|\\.)*)"/gc) { push @tok, [ 'str', $1, $line ]; next }
        if ($t =~ /\G"/gc) { push @bad, "$path:$line: unterminated string"; last }
        if ($t =~ /\G'((?:[^'\\\n]|\\.)*)'/gc) { (my $v = $1) =~ s/\\(.)/$1/g; push @tok, [ 'name', $v, $line ]; next }
        if ($t =~ /\G'/gc) { push @bad, "$path:$line: unterminated name"; last }
        if ($t =~ /\G([A-Za-z_][A-Za-z0-9_]*)/gc) { push @tok, [ $KEYWORD{$1} ? 'kw' : 'name', $1, $line ]; next }
        if ($t =~ /\G([0-9][0-9.eE+\-]*)/gc) { push @tok, [ 'num', $1, $line ]; next }
        if ($t =~ /\G(::>|:>>|:>|::|\.\.|[{}()\[\];:~,.=#*<>\-+\/])/gc) { push @tok, [ 'p', $1, $line ]; next }
        $t =~ /\G(.)/gcs; push @bad, "$path:$line: unexpected character '$1'";
    }
    return (\@tok, \@bad);
}

my %DECL = map { $_ => 1 } qw(package part port attribute item action requirement enum connection interface
    verification constraint calc case use occurrence state allocation analysis metadata view viewpoint concern
    flow ref in out inout objective subject);

sub check {
    my ($files) = @_;
    my (%declared, @refs, @bad);
    for my $path (sort keys %$files) {
        my ($tok, $b) = _tokens($files->{$path}, $path);
        push @bad, @$b;
        my @stack;
        my %close = (')' => '(', ']' => '[', '}' => '{');
        for my $k (@$tok) {
            next unless $k->[0] eq 'p';
            if ($k->[1] =~ /^[(\[{]$/) { push @stack, $k }
            elsif ($close{ $k->[1] }) {
                my $o = pop @stack;
                if (!$o) { push @bad, "$path:$k->[2]: unbalanced '$k->[1]'" }
                elsif ($o->[1] ne $close{ $k->[1] }) { push @bad, "$path:$k->[2]: '$k->[1]' closes '$o->[1]' from line $o->[2]" }
            }
        }
        push @bad, map { "$path:$_->[2]: '$_->[1]' never closed" } @stack;
        my $qn = sub {                        # read a qualified name at index $i -> (name, next index)
            my ($i) = @_;
            return (undef, $i) unless $i < @$tok && $tok->[$i][0] eq 'name';
            my @seg = ($tok->[$i][1]); $i++;
            while ($i + 1 < @$tok && $tok->[$i][1] eq '::' && $tok->[$i + 1][0] eq 'name') { push @seg, $tok->[$i + 1][1]; $i += 2 }
            return (\@seg, $i);
        };
        for (my $i = 0; $i < @$tok; $i++) {
            my ($kind, $v, $ln) = @{ $tok->[$i] };
            next if $i > 0 && $tok->[$i - 1][1] eq '#';   # #derivation, #original: metadata, not declarations
            if ($kind eq 'kw' && $DECL{$v}) {
                my $j = $i + 1;
                $j++ while $j < @$tok && $tok->[$j][0] eq 'kw' && $tok->[$j][1] =~ /^(def|part|item|attribute|action|port|requirement|case|connection|ref)$/;
                $j += 3 if $j < @$tok && $tok->[$j][1] eq '<';    # short name <x>
                $declared{ $tok->[$j][1] } = 1 if $j < @$tok && $tok->[$j][0] eq 'name';
            }
            my $ref_at;
            if ($kind eq 'p' && ($v eq ':' || $v eq '::>')) { $ref_at = $i + 1; $ref_at++ if $ref_at < @$tok && $tok->[$ref_at][1] eq '~' }
            elsif ($kind eq 'kw' && $v =~ /^(satisfy|verify|by|connect|to|from|bind|allocate|specializes)$/) { $ref_at = $i + 1 }
            if ($kind eq 'p' && $v eq ':>' ) {      # :> A, B -- every one of the list
                my $j = $i + 1;
                while (1) {
                    my ($seg, $n) = $qn->($j);
                    last unless $seg;
                    push @refs, [ $seg, "$path:$tok->[$j][2]" ];
                    last unless $n < @$tok && $tok->[$n][1] eq ',';
                    $j = $n + 1;
                }
                next;
            }
            if ($kind eq 'kw' && $v eq 'import') {
                my $j = $i + 1;
                my ($seg, $n) = $qn->($j);
                push @refs, [ $seg, "$path:$ln", 'import' ] if $seg;
                next;
            }
            if (defined $ref_at) {
                my ($seg) = $qn->($ref_at);
                push @refs, [ $seg, "$path:$ln" ] if $seg;
            }
            if ($kind eq 'kw' && $v eq 'bind') {   # bind a = b: the head after '='
                my $j = $i + 1; $j++ while $j < @$tok && $tok->[$j][1] ne '=' && $tok->[$j][1] ne ';';
                if ($j < @$tok && $tok->[$j][1] eq '=') { my ($seg) = $qn->($j + 1); push @refs, [ $seg, "$path:$ln" ] if $seg }
            }
        }
    }
    for my $r (@refs) {
        my ($seg, $where, $imp) = @$r;
        my $head = $seg->[0];
        next if $LIBPKG{$head};
        next if @$seg == 1 && $LIBNAME{$head};
        my @miss = grep { !$declared{$_} } @$seg;
        push @bad, "$where: '" . join('::', @$seg) . "' is not declared in these files or the standard library" if @miss;
    }
    my %seen;
    return [ grep { !$seen{$_}++ } @bad ];
}

1;
