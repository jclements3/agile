package SysML::Parser;
# A recognizer compiled from the official grammar.
#
#   recognizer(Grammar) -> ([Token] -> Either Failure Ok)
#   Failure = { at => token index, expected => [what], found => Token | undef }
#
# Each grammar expression compiles to a function  Pos -> [Pos]  returning every token
# position where that expression can end when started at Pos (sorted, unique). This is
# the list-of-successes formulation of parsing: alternatives are unions, sequences are
# folds, repetition is a fixpoint, so the grammar's ambiguities and backtracking need
# no special handling. Rule applications are memoized per position (packrat style),
# which keeps it polynomial. FIRST sets (computed once from the grammar) let a rule or
# an alternative be skipped when it cannot start with the current token. The furthest
# position at which a terminal failed, with what was expected there, is the syntax
# error reported to the user.
use strict;
use warnings;
no warnings 'recursion';
use Prelude qw(fmap foldl concatMap Ok Err);
our %TOKEN_KIND;
use SysML::Grammar;

%TOKEN_KIND = %SysML::Grammar::TOKEN_RULE;         # NAME -> name, DECIMAL_VALUE -> int ...
my %KIND_TEXT = (name => 'a name', int => 'a number', exp => 'a number', string => 'a string', comment => 'a comment /* */');

sub uniq_sorted { my %s = map { $_ => 1 } @_; sort { $a <=> $b } keys %s }

# ---------------------------------------------------------------- FIRST sets
# first(Expr) = [ { key => 1 }, nullable ] where key is "t:TEXT" (keyword or symbol) or
# "k:KIND" (token class). Rule values are found as a least fixpoint over the grammar.
sub analyse {                         # Grammar -> { Rule => [firstset, nullable] }
    my $g = shift;
    my %R = map { $_ => [ {}, 0 ] } grep { !$TOKEN_KIND{$_} } keys %{ $g->{rules} };
    my $first;
    $first = sub {
        my ($k, @a) = @{ $_[0] };
        return [ { "t:$a[0]" => 1 }, 0 ] if $k eq 'lit';
        return [ { "k:$TOKEN_KIND{$a[0]}" => 1 }, 0 ] if $k eq 'ref' && $TOKEN_KIND{ $a[0] };
        return $R{ $k eq 'xref' ? 'QualifiedName' : $a[0] } // [ {}, 0 ] if $k eq 'ref' || $k eq 'xref';
        return [ {}, 1 ] if $k eq 'empty';
        my @fs = fmap($first, @a);
        return [ +{ map { %{ $_->[0] } } @fs }, (grep { $_->[1] } @fs) ? 1 : 0 ] if $k eq 'alt';
        return [ $fs[0][0], 1 ] if $k eq 'opt' || $k eq 'star';
        return $fs[0] if $k eq 'plus';
        foldl(sub { my ($acc, $f) = @_; $acc->[1] ? [ +{ %{ $acc->[0] }, %{ $f->[0] } }, $f->[1] ] : $acc }, [ {}, 1 ], @fs);
    };
    my $changed = 1;
    while ($changed) {
        $changed = 0;
        for my $r (keys %R) {
            my $n = $first->($g->{rules}{$r});
            next if $n->[1] == $R{$r}[1] && keys %{ $n->[0] } == keys %{ $R{$r}[0] };
            $R{$r} = $n;
            $changed = 1;
        }
    }
    (\%R, $first);
}

sub key_text { my $k = shift; $k =~ /^t:(.*)/s ? "'$1'" : $KIND_TEXT{ substr($k, 2) } }

sub recognizer {
    my $g = shift;
    # run-time state, private to one recognition (the compiled closures read it)
    my ($tok, $memo, $far, %expected);
    my %rule;

    my ($FIRST, $first) = analyse($g);
    my $starts = sub {                  # can a construct with FIRST set $fs begin at token $p?
        my ($p, $fs) = @_;
        my $t = $tok->[$p] or return 0;
        $fs->{"k:$t->[0]"} || ($fs->{"t:$t->[1]"} && $t->[0] ne 'string' && $t->[0] ne 'comment');
    };
    my $fail = sub {                    # record a terminal failure at $p
        my ($p, $what) = @_;
        if ($p > $far) { $far = $p; %expected = () }
        $expected{$what} = 1 if $p == $far;
        ();
    };
    my $terminal = sub {                # predicate on a token -> Pos -> [Pos]
        my ($ok, $what) = @_;
        sub { my $p = shift; my $t = $tok->[$p]; $t && $ok->($t) ? ($p + 1) : $fail->($p, $what) };
    };

    my $compile;
    $compile = sub {
        my ($k, @a) = @{ $_[0] };
        if ($k eq 'lit') {
            my $text = $a[0];
            return $terminal->(sub { $_[0][1] eq $text && $_[0][0] ne 'string' && $_[0][0] ne 'comment' }, "'$text'");
        }
        if ($k eq 'ref' && $TOKEN_KIND{ $a[0] }) {
            my $kind = $TOKEN_KIND{ $a[0] };
            return $terminal->(sub { $_[0][0] eq $kind }, $KIND_TEXT{$kind});
        }
        if ($k eq 'ref' || $k eq 'xref') {
            my $name = $k eq 'xref' ? 'QualifiedName' : $a[0];
            die "grammar: undefined rule $name\n" unless $g->{rules}{$name};
            my ($fs, $nullable) = @{ $FIRST->{$name} };
            return sub { $rule{$name}->(@_) } if $nullable;     # late bound: rules may be recursive
            my @desc = fmap(\&key_text, keys %$fs);
            return sub {
                my $p = shift;
                return $rule{$name}->($p) if $starts->($p, $fs);
                if ($p >= $far) { if ($p > $far) { $far = $p; %expected = () } @expected{@desc} = () }
                ();
            };
        }
        return sub { ($_[0]) } if $k eq 'empty';
        my @f = fmap($compile, @a);
        if ($k eq 'seq') {
            return sub { my @ps = ($_[0]); for my $f (@f) { @ps = uniq_sorted(map { $f->($_) } @ps); last unless @ps } @ps };
        }
        if ($k eq 'alt') {
            my @firsts = fmap($first, @a);
            my @alts = map { [ $f[$_], @{ $firsts[$_] }, [ fmap(\&key_text, keys %{ $firsts[$_][0] }) ] ] } 0 .. $#f;
            return sub {
                my $p = shift;
                uniq_sorted(map {
                    my ($fn, $fs, $nullable, $desc) = @$_;
                    if ($nullable || $starts->($p, $fs)) { $fn->($p) }
                    else {                       # skipped: still part of what was expected here
                        if ($p >= $far) { if ($p > $far) { $far = $p; %expected = () } @expected{@$desc} = () }
                        ();
                    }
                } @alts);
            };
        }
        my $f = $f[0];
        return sub { my $p = shift; uniq_sorted($p, $f->($p)) } if $k eq 'opt';
        my $star = sub {                # least fixpoint of positions reachable by repeating $f
            my %seen = map { $_ => 1 } @_;
            my @frontier = @_;
            while (@frontier) { @frontier = grep { !$seen{$_}++ } map { $f->($_) } @frontier }
            sort { $a <=> $b } keys %seen;
        };
        return sub { $star->($_[0]) } if $k eq 'star';
        return sub { my @once = $f->($_[0]); @once ? $star->(@once) : () } if $k eq 'plus';
        die "grammar: unknown expression kind $k\n";
    };

    # Left recursion (the published grammar has it, e.g. BracketExpression starts with a
    # PrimaryExpression) is handled by growing the seed: a rule re-entered at the same
    # position first sees its current result (initially none); if that happened, the rule
    # is re-evaluated with the larger result until the set of end positions stops growing.
    # Results memoized at the same position during an evaluation may depend on the old
    # seed, so they are dropped before each re-evaluation.
    my ($busy, $again, $made);
    for my $name (keys %{ $g->{rules} }) {
        next if $TOKEN_KIND{$name};
        my $body;                       # compiled on first use
        $rule{$name} = sub {
            my $p = shift;
            my $key = "$name\0$p";
            if (my $m = $memo->{$key}) { $again->{$key} = 1 if $busy->{$key}; return @$m }
            $memo->{$key} = [];
            $busy->{$key} = 1;
            my $mark = scalar @{ $made->{$p} //= [] };
            $body //= $compile->($g->{rules}{$name});
            my @r = $body->($p);
            while (delete $again->{$key}) {
                delete @$memo{ splice @{ $made->{$p} }, $mark };
                my %had = map { $_ => 1 } @{ $memo->{$key} };
                last unless grep { !$had{$_} } @r;      # no growth: fixpoint reached
                $memo->{$key} = [@r];
                @r = uniq_sorted(@r, $body->($p));
            }
            delete $busy->{$key};
            $memo->{$key} = \@r;
            push @{ $made->{$p} }, $key;
            @r;
        };
    }

    my $start = $g->{start};
    sub {                               # [Token] -> Either Failure 1
        ($tok, $memo, $far, %expected) = (shift, {}, -1);
        ($busy, $again, $made) = ({}, {}, {});
        my $end = scalar @$tok;
        my @ends = $rule{$start}->(0);
        return Ok(1) if grep { $_ == $end } @ends;
        my $at = $far < 0 ? 0 : $far;
        my $max = @ends ? $ends[-1] : 0;
        $at = $max if $max > $at;       # complete prefix parsed further than any failure
        Err({ at => $at, found => $tok->[$at], expected => [ sort keys %expected ] });
    };
}

1;
