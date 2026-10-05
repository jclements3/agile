package SysML::Grammar;
# Read the official KerML / SysML v2 textual-notation grammars (KEBNF, as published in
# the Systems-Modeling/SysML-v2-Release repository) into a grammar value.
#
# A grammar is a plain hash ref:
#   { rules    => { Name => Expr, ... },     # productions
#     order    => [ Name, ... ],             # in file order
#     keywords => [ ... ],                   # RESERVED_KEYWORD
#     symbols  => [ ... ],                   # RESERVED_SYMBOL, longest first
#     start    => 'RootNamespace' }
#
# An Expr is an array ref (a small algebraic data type):
#   ['alt',  Expr...]        choice                ['seq',  Expr...]   sequence
#   ['opt',  Expr]           Expr?                 ['star', Expr]      Expr*
#   ['plus', Expr]           Expr+                 ['lit',  'text']    keyword or symbol
#   ['ref',  'Rule']         rule or token class   ['empty']           semantic action { ... }
#   ['xref', Conjugated]     cross reference [QualifiedName] (Conjugated = 1 for ~[QualifiedName]),
#                            parsed as a QualifiedName and resolved later
#
# Assignments (name = X, name += X, name ?= X) and cross references ([QualifiedName])
# are kept as their parsed element: a syntax checker does not need the metamodel names.
#
# Functional style: every function here is pure (text in, value out), built with the
# Prelude parser combinators and folds.
use strict;
use warnings;
use Prelude qw(lit rx alt many many1 seqP mapP optP lazyP pureP runParser isOk isErr unwrap
               fmap filter foldl concatMap fromList lines strip sortOn Ok Err);

# Terminal token classes: lexical rules the parser treats as single tokens.
our %TOKEN_RULE = (
    NAME              => 'name',
    DECIMAL_VALUE     => 'int',
    EXPONENTIAL_VALUE => 'exp',
    STRING_VALUE      => 'string',
    REGULAR_COMMENT   => 'comment',
);

# ---------------------------------------------------------------- expression syntax
# alternation := sequence ('|' sequence)*
# sequence    := element*
# element     := (IDENT ('+=' | '?=' | '='))? primary ('?' | '*' | '+')?
# primary     := 'literal' | '~'? '[' QualifiedName ']' | '{' action '}' | '(' alternation ')' | IDENT
my $alternation;
my $ident   = rx(qr/[A-Za-z_]\w*(?!\s*(?:\+=|\?=|=(?!=)|:\s*\w+\s*=))/);
my $literal = mapP(sub { ['lit', substr($_[0], 1, -1)] }, rx(qr/'[^']*'/));
my $xref    = mapP(sub { ['xref', 0] }, seqP(lit('['), rx(qr/[A-Za-z_]\w*/), lit(']')));
# ~[QualifiedName]: parsed as a plain QualifiedName; the ~ only changes name resolution
# (to the conjugated port definition) -- SysML-textual-bnf.kebnf, ConjugatedPortTyping, Note 2.
my $conj    = mapP(sub { ['xref', 1] }, seqP(lit('~'), $xref));
my $action  = mapP(sub { ['empty'] }, rx(qr/\{[^}]*\}/));
my $group   = mapP(sub { $_[0][1] }, seqP(lit('('), lazyP(sub { $alternation }), lit(')')));
my $ruleref = mapP(sub { ['ref', $_[0]] }, $ident);
my $primary = alt($literal, $conj, $xref, $action, $group, $ruleref);
my $assign  = optP(rx(qr/[A-Za-z_]\w*\s*(?:\+=|\?=|=)/), '');
my $element = mapP(
    sub {
        my (undef, $p, $post) = @{ $_[0] };
        $post eq '?' ? ['opt', $p] : $post eq '*' ? ['star', $p] : $post eq '+' ? ['plus', $p] : $p;
    },
    seqP($assign, $primary, optP(rx(qr/[?*+]/), '')));
my $sequence = mapP(sub { my @e = @{ $_[0] }; @e == 1 ? $e[0] : ['seq', @e] }, many($element));
$alternation = mapP(
    sub { my ($first, $rest) = @{ $_[0] }; @$rest ? ['alt', $first, map { $_->[1] } @$rest] : $first },
    seqP($sequence, many(seqP(lit('|'), $sequence))));

sub parse_expr {                      # Text -> Either Error Expr
    my $text = shift;
    runParser($alternation, $text);
}

# ---------------------------------------------------------------- file level
sub split_rules {                     # [Line] -> [[Name, Type, BodyText]]
    my @rules;
    for my $l (grep { !/^\s*\/\// } @_) {
        if ($l =~ /^([A-Za-z_]\w*)\s*(?::\s*(\w+))?\s*=(.*)$/) { push @rules, [$1, $2 // $1, $3] }
        elsif (@rules && $l =~ /\S/) { $rules[-1][2] .= " $l" }
    }
    @rules;
}

sub literals {                        # Expr -> [text] (for keyword / symbol lists)
    my $e = shift;
    my ($k, @a) = @$e;
    $k eq 'lit' ? ($a[0]) : $k eq 'ref' || $k eq 'xref' || $k eq 'empty' ? () : concatMap(\&literals, @a);
}

sub read_file {                       # Path -> Either Error {rules, order, keywords, symbols}
    my $path = shift;
    open my $fh, '<:encoding(UTF-8)', $path or return Err("cannot read $path: $!");
    my $text = do { local $/; <$fh> };
    close $fh;
    $text =~ s/\r\n?/\n/g;
    my @parsed = fmap(sub {
        my ($name, $type, $body) = @{ $_[0] };
        my $e = parse_expr(strip($body));
        isErr($e) ? Err("$path: rule $name: $e->[1]") : Ok([$name, unwrap($e)]);
    }, split_rules(lines($text)));
    my @errors = filter(\&isErr, @parsed);
    return $errors[0] if @errors;
    my @pairs = fmap(\&unwrap, @parsed);
    my $rules = fromList(@pairs);
    Ok({
        rules    => $rules,
        order    => [ fmap(sub { $_[0][0] }, @pairs) ],
        keywords => [ $rules->{RESERVED_KEYWORD} ? literals($rules->{RESERVED_KEYWORD}) : () ],
        symbols  => [ $rules->{RESERVED_SYMBOL}  ? sort { length $b <=> length $a } literals($rules->{RESERVED_SYMBOL}) : () ],
    });
}

sub merge {                           # base grammar, override grammar -> grammar (override wins)
    my ($base, $over) = @_;
    my %rules = (%{ $base->{rules} }, %{ $over->{rules} });
    my %seen;
    +{
        rules    => \%rules,
        order    => [ grep { !$seen{$_}++ } @{ $base->{order} }, @{ $over->{order} } ],
        keywords => @{ $over->{keywords} } ? $over->{keywords} : $base->{keywords},
        symbols  => @{ $over->{symbols} }  ? $over->{symbols}  : $base->{symbols},
        start    => 'RootNamespace',
    };
}

# Corrections to the published grammars live next to this module (see their headers).
my $ERRATA_DIR = do { (my $d = __FILE__) =~ s{[^/\\]+$}{}; $d };

sub load {                            # language ('sysml' | 'kerml'), bnf dir -> Either Error Grammar
    my ($lang, $dir) = @_;
    my @files = ("$dir/KerML-textual-bnf.kebnf", "${ERRATA_DIR}KerML-errata.kebnf",
                 $lang eq 'sysml' ? ("$dir/SysML-textual-bnf.kebnf", "${ERRATA_DIR}SysML-errata.kebnf") : ());
    my @read = fmap(\&read_file, @files);
    my @errors = filter(\&isErr, @read);
    return $errors[0] if @errors;
    Ok(foldl(\&merge, { rules => {}, order => [], keywords => [], symbols => [] }, fmap(\&unwrap, @read)));
}

# ---------------------------------------------------------------- analysis
sub refs {                            # Expr -> [rule names referenced]
    my $e = shift;
    my ($k, @a) = @$e;
    $k eq 'ref' ? ($a[0]) : $k eq 'xref' ? ('QualifiedName') : $k eq 'lit' || $k eq 'empty' ? () : concatMap(\&refs, @a);
}

sub undefined_refs {                  # Grammar -> [names referenced but never defined]
    my $g = shift;
    my %seen;
    grep { !$g->{rules}{$_} && !$TOKEN_RULE{$_} && !$seen{$_}++ } concatMap(\&refs, values %{ $g->{rules} });
}

1;
