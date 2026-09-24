package Prelude;
# Haskell-flavoured FP prelude. Pure core Perl 5.10+, no CPAN, no XS.
#
# Conventions
#   callbacks    get their arguments in @_            fmap(sub { $_[0] * 2 }, @xs)
#   lists        are flat trailing args, returned flat take(3, @xs)
#   list-of-list uses array refs                     chunksOf(2, 1..5) -> [1,2],[3,4],[5]
#   tuples       are array refs                      fst([1,2])
#   two results  come back as two array refs         my ($yes, $no) = partition(\&even, @xs)
#   2+ lists in  are passed as array refs            zip(\@a, \@b)
#   maps         are hash refs, returned as new refs (inputs never mutated)
#   Maybe        value or NOTHING (NOTHING is false and prints as NOTHING)
#   Either       Ok(v) = ['ok', v], Err(e) = ['err', e]
#   streams      iterator closures: return (x) for next value, () when done
#   parsers      sub($input) -> [value, rest] or FAIL
#   Perl-keyword clashes get a trailing underscore: last_ until_ pipe_ break_ and_ or_ not_
#
#   use Prelude;               # everything
#   use Prelude qw(fmap foldl) # just these
#   REPL: perl -Ilib -MPrelude -de0      then:  x pp(foldl(sub { $_[0] + $_[1] }, 0, 1..10))
use strict;
use warnings;
no warnings 'recursion';
our $VERSION = '1.00';
our @EXPORT;

sub import {
    my ($class, @want) = @_;
    my $caller = caller;
    no strict 'refs';
    for my $n (@want ? @want : @EXPORT) {
        die "Prelude: unknown function '$n'\n" unless defined &{"Prelude::$n"};
        *{"${caller}::$n"} = \&{"Prelude::$n"};
    }
}

# ---------------------------------------------------------------- sentinels
{
    package Prelude::Sentinel;
    use overload 'bool' => sub { 0 }, '""' => sub { ${ $_[0] } }, fallback => 1;
}
my $NOTHING = bless \(my $n1 = 'NOTHING'), 'Prelude::Sentinel';
my $FAIL    = bless \(my $n2 = 'FAIL'),    'Prelude::Sentinel';
sub NOTHING() { $NOTHING }
sub FAIL()    { $FAIL }
sub _sent     { ref($_[0]) eq 'Prelude::Sentinel' && ${ $_[0] } eq $_[1] }
sub isNothing { _sent($_[0], 'NOTHING') ? 1 : 0 }
sub isFail    { _sent($_[0], 'FAIL') ? 1 : 0 }

# ---------------------------------------------------------------- equality, ordering, show
sub _isnum {
    my $x = shift;
    defined $x && !ref $x
      && $x =~ /^\s*[-+]?(?:(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?|(?i:inf(?:inity)?|nan))\s*$/;
}

sub equal {                                   # deep structural equality
    my ($x, $y) = @_;
    return defined $y ? 0 : 1 unless defined $x;
    return 0 unless defined $y;
    my ($rx, $ry) = (ref $x, ref $y);
    return 0 if $rx ne $ry;
    if ($rx eq 'ARRAY') {
        return 0 unless @$x == @$y;
        for (0 .. $#$x) { return 0 unless equal($x->[$_], $y->[$_]) }
        return 1;
    }
    if ($rx eq 'HASH') {
        return 0 unless keys %$x == keys %$y;
        for (keys %$x) { return 0 unless exists $y->{$_} && equal($x->{$_}, $y->{$_}) }
        return 1;
    }
    return $$x eq $$y ? 1 : 0 if $rx eq 'Prelude::Sentinel';
    return $x == $y ? 1 : 0 if $rx;
    return (_isnum($x) && _isnum($y) ? $x == $y : $x eq $y) ? 1 : 0;
}

sub compare {                                 # -1/0/1; numbers numerically, arrays lexicographically
    my ($x, $y) = @_;
    return (defined $x ? 1 : 0) <=> (defined $y ? 1 : 0) unless defined $x && defined $y;
    if (ref $x eq 'ARRAY' && ref $y eq 'ARRAY') {
        my $m = $#$x < $#$y ? $#$x : $#$y;
        for (0 .. $m) { my $c = compare($x->[$_], $y->[$_]); return $c if $c }
        return @$x <=> @$y;
    }
    return _isnum($x) && _isnum($y) ? $x <=> $y : "$x" cmp "$y";
}

sub show {
    my $x = shift;
    return 'undef' unless defined $x;
    my $r = ref $x;
    return $$x if $r eq 'Prelude::Sentinel';
    return '[' . join(',', map { show($_) } @$x) . ']' if $r eq 'ARRAY';
    return '{' . join(',', map { show($_) . ':' . show($x->{$_}) } sort { compare($a, $b) } keys %$x) . '}'
      if $r eq 'HASH';
    return '<fn>' if $r eq 'CODE';
    return "$x" if $r;
    return "$x" if _isnum($x);
    (my $s = $x) =~ s/(["\\])/\\$1/g;
    $s =~ s/\n/\\n/g; $s =~ s/\t/\\t/g;
    return qq("$s");
}
sub pp { print join(' ', map { show($_) } @_), "\n"; wantarray ? @_ : $_[0] }   # trace + pass through

# ---------------------------------------------------------------- 1. functions
sub identity { $_[0] }
sub id       { $_[0] }
sub const    { my $x = shift; sub { $x } }
sub flip     { my $f = shift; sub { $f->(@_[1, 0], @_[2 .. $#_]) } }
sub curry    { my $f = shift; sub { my $x = shift; sub { $f->($x, @_) } } }
sub uncurry  { my $f = shift; sub { $f->(@{ $_[0] }) } }
sub partial  { my ($f, @a) = @_; sub { $f->(@a, @_) } }
sub compose {                                 # compose(f, g)->(x) == f(g(x))
    my @fs = reverse @_;
    return sub { my @x = @_; for my $f (@fs) { @x = $f->(@x) } wantarray ? @x : $x[0] };
}
sub o       { compose(@_) }
sub pipe_   { my $x = shift; for my $f (@_) { $x = $f->($x) } $x }
sub on      { my ($f, $g) = @_; sub { $f->($g->($_[0]), $g->($_[1])) } }
sub fix     { my $f = shift; my $g; $g = sub { $f->($g, @_) }; $g }   # fix(sub { my ($self, $n) = @_; ... })
sub memo    { my $f = shift; my %c; sub { my $k = show([@_]); exists $c{$k} ? $c{$k} : ($c{$k} = $f->(@_)) } }
sub memoFix { my $f = shift; my $m; $m = memo(sub { $f->($m, @_) }); $m }

# ---------------------------------------------------------------- 2. pairs
sub fst   { $_[0][0] }
sub snd   { $_[0][1] }
sub swap  { [ $_[0][1], $_[0][0] ] }
sub bimap { my ($f, $g, $p) = @_; [ scalar $f->($p->[0]), scalar $g->($p->[1]) ] }

# ---------------------------------------------------------------- 3. arithmetic & logic
sub div     { my ($x, $y) = @_; ($x - $x % $y) / $y }          # floor division
sub mod     { $_[0] % $_[1] }                                  # sign of divisor
sub quot    { my ($x, $y) = @_; my $q = div($x, $y); $q += 1 if $x % $y && (($x < 0) xor ($y < 0)); $q }
sub rem     { my ($x, $y) = @_; $x - $y * quot($x, $y) }
sub divMod  { [ div(@_), mod(@_) ] }
sub quotRem { [ quot(@_), rem(@_) ] }
sub even    { $_[0] % 2 == 0 ? 1 : 0 }
sub odd     { $_[0] % 2 != 0 ? 1 : 0 }
sub signum  { $_[0] > 0 ? 1 : $_[0] < 0 ? -1 : 0 }
sub negate  { -$_[0] }
sub succ    { _isnum($_[0]) ? $_[0] + 1 : chr(ord($_[0]) + 1) }
sub pred    { _isnum($_[0]) ? $_[0] - 1 : chr(ord($_[0]) - 1) }
sub gcd     { my ($x, $y) = map { abs } @_; ($x, $y) = ($y, $x % $y) while $y; $x }
sub lcm     { my ($x, $y) = @_; return 0 unless $x && $y; abs($x / gcd($x, $y) * $y) }
sub isqrt   { my $n = shift; my $r = int sqrt $n; $r-- while $r * $r > $n; $r++ while ($r + 1) * ($r + 1) <= $n; $r }
sub hypot   { sqrt($_[0]**2 + $_[1]**2) }
sub sum     { my $s = 0; $s += $_ for @_; $s }
sub product { my $p = 1; $p *= $_ for @_; $p }
sub range {                                   # inclusive, with step: range(10, 1, -3) -> 10,7,4,1
    my ($lo, $hi, $st) = @_;
    $st //= 1;
    die "range: zero step\n" unless $st;
    my @r;
    for (my $i = $lo; $st > 0 ? $i <= $hi : $i >= $hi; $i += $st) { push @r, $i }
    @r;
}
sub not_    { $_[0] ? 0 : 1 }
sub and_    { for (@_) { return 0 unless $_ } 1 }
sub or_     { for (@_) { return 1 if $_ } 0 }
sub any     { my $p = shift; for (@_) { return 1 if $p->($_) } 0 }
sub all     { my $p = shift; for (@_) { return 0 unless $p->($_) } 1 }
sub countIf { my $p = shift; scalar grep { $p->($_) } @_ }

# ---------------------------------------------------------------- 4. folds, scans, unfolds
sub foldl  { my ($f, $acc, @xs) = @_; $acc = $f->($acc, $_) for @xs; $acc }
sub foldl1 { my $f = shift; die "foldl1: empty list\n" unless @_; foldl($f, @_) }
sub foldr  { my ($f, $acc, @xs) = @_; $acc = $f->($_, $acc) for reverse @xs; $acc }
sub foldr1 { my $f = shift; die "foldr1: empty list\n" unless @_; my @xs = @_; my $z = pop @xs; foldr($f, $z, @xs) }
sub scanl  { my ($f, $acc, @xs) = @_; my @o = ($acc); push @o, ($acc = $f->($acc, $_)) for @xs; @o }
sub scanl1 { my $f = shift; @_ ? scanl($f, @_) : () }
sub scanr  { my ($f, $acc, @xs) = @_; my @o = ($acc); unshift @o, ($acc = $f->($_, $acc)) for reverse @xs; @o }
sub scanr1 { my $f = shift; return () unless @_; my @xs = @_; my $z = pop @xs; scanr($f, $z, @xs) }
sub unfoldr {                                 # f(seed) -> NOTHING | [x, seed']
    my ($f, $seed) = @_;
    my @o;
    while (1) { my $r = $f->($seed); last if isNothing($r); push @o, $r->[0]; $seed = $r->[1] }
    @o;
}
sub until_ { my ($p, $f, $x) = @_; $x = $f->($x) until $p->($x); $x }
sub replicateM {
    my ($n, @xs) = @_;
    my @acc = ([]);
    for (1 .. $n) { @acc = map { my $s = $_; map { [ @$s, $_ ] } @xs } @acc }
    @acc;
}
sub subsequences { my @acc = ([]); for my $x (@_) { push @acc, map { [ @$_, $x ] } @acc } @acc }
sub permutations {
    return ([]) unless @_;
    my @o;
    for my $i (0 .. $#_) {
        my @rest = @_[ 0 .. $i - 1, $i + 1 .. $#_ ];
        push @o, map { [ $_[$i], @$_ ] } permutations(@rest);
    }
    @o;
}

# ---------------------------------------------------------------- 5. lazy streams (iterators)
sub fromListS  { my @xs = @_; my $i = 0; sub { $i < @xs ? ($xs[ $i++ ]) : () } }
sub iterate    { my ($f, $x) = @_; my $go = 0; sub { $x = $f->($x) if $go++; ($x) } }
sub repeat     { my $x = shift; sub { ($x) } }
sub cycle      { my @xs = @_; my $i = 0; sub { @xs ? ($xs[ $i++ % @xs ]) : () } }
sub enumFrom   { my ($n, $st) = @_; $st //= 1; $n -= $st; sub { ($n += $st) } }
sub unfoldS    { my ($f, $seed) = @_; sub { my $r = $f->($seed); return () if isNothing($r); $seed = $r->[1]; ($r->[0]) } }
sub mapS       { my ($f, $it) = @_; sub { my @r = $it->(); @r ? (scalar $f->($r[0])) : () } }
sub filterS    { my ($p, $it) = @_; sub { while (my @r = $it->()) { return @r if $p->($r[0]) } () } }
sub zipWithS {
    my ($f, @its) = @_;
    sub { my @v; for my $it (@its) { my @r = $it->(); return () unless @r; push @v, $r[0] } (scalar $f->(@v)) };
}
sub scanlS {
    my ($f, $acc, $it) = @_;
    my $first = 1;
    sub { if ($first) { $first = 0; return ($acc) } my @r = $it->(); @r ? ($acc = $f->($acc, $r[0])) : () };
}
sub dropS      { my ($n, $it) = @_; sub { while ($n > 0) { $n--; my @r = $it->(); return () unless @r } $it->() } }
sub dropWhileS {
    my ($p, $it) = @_;
    my $done = 0;
    sub {
        return $it->() if $done;
        while (my @r = $it->()) { next if $p->($r[0]); $done = 1; return @r }
        ();
    };
}
sub takeS      { my ($n, $it) = @_; my @o; while ($n-- > 0) { my @r = $it->(); last unless @r; push @o, @r } @o }
sub takeWhileS { my ($p, $it) = @_; my @o; while (my @r = $it->()) { last unless $p->($r[0]); push @o, $r[0] } @o }
sub findS      { my ($p, $it) = @_; while (my @r = $it->()) { return $r[0] if $p->($r[0]) } NOTHING }
sub toListS    { my $it = shift; my @o; while (my @r = $it->()) { push @o, @r } @o }

# ---------------------------------------------------------------- 6. list basics
sub head    { die "head: empty list\n" unless @_; $_[0] }
sub tail    { die "tail: empty list\n" unless @_; @_[ 1 .. $#_ ] }
sub init    { die "init: empty list\n" unless @_; @_[ 0 .. $#_ - 1 ] }
sub last_   { die "last: empty list\n" unless @_; $_[-1] }
sub take    { my $n = shift; $n = @_ if $n > @_; $n > 0 ? @_[ 0 .. $n - 1 ] : () }
sub drop    { my $n = shift; $n = 0 if $n < 0; $n >= @_ ? () : @_[ $n .. $#_ ] }
sub splitAt { my $n = shift; ([ take($n, @_) ], [ drop($n, @_) ]) }
sub replicate { my ($n, $x) = @_; $n > 0 ? ($x) x $n : () }
sub elem    { my $x = shift; for (@_) { return 1 if equal($x, $_) } 0 }
sub notElem { elem(@_) ? 0 : 1 }
sub null    { @_ ? 0 : 1 }
sub nub     { my %seen; grep { !$seen{ show($_) }++ } @_ }
sub indexed { my $i = 0; map { [ $i++, $_ ] } @_ }
sub pairwise { map { [ $_[ $_ - 1 ], $_[$_] ] } 1 .. $#_ }
sub zip {                                     # zip(\@a, \@b, ...) -> [a0,b0], [a1,b1] ...
    my @ls = @_;
    return () unless @ls;
    my ($n) = sort { $a <=> $b } map { scalar @$_ } @ls;
    map { my $i = $_; [ map { $_->[$i] } @ls ] } 0 .. $n - 1;
}
sub unzip   { return ([], []) unless @_; my $w = @{ $_[0] }; my @ps = @_; map { my $i = $_; [ map { $_->[$i] } @ps ] } 0 .. $w - 1 }
sub isPrefixOf {                              # strings or array refs
    my ($p, $xs) = @_;
    return substr($xs, 0, length $p) eq $p ? 1 : 0 unless ref $p || ref $xs;
    return 0 if @$p > @$xs;
    for (0 .. $#$p) { return 0 unless equal($p->[$_], $xs->[$_]) }
    1;
}
sub isSuffixOf {
    my ($p, $xs) = @_;
    unless (ref $p || ref $xs) {
        return 1 if $p eq '';
        return length $p <= length $xs && substr($xs, -length $p) eq $p ? 1 : 0;
    }
    my $off = @$xs - @$p;
    return 0 if $off < 0;
    for (0 .. $#$p) { return 0 unless equal($p->[$_], $xs->[ $off + $_ ]) }
    1;
}
sub isInfixOf {
    my ($p, $xs) = @_;
    return index($xs, $p) >= 0 ? 1 : 0 unless ref $p || ref $xs;
    for my $i (0 .. @$xs - @$p) { return 1 if isPrefixOf($p, [ @$xs[ $i .. $#$xs ] ]) }
    0;
}
sub lookup {                                  # lookup($k, @pairs) or lookup($k, \%h)
    my $k = shift;
    if (@_ == 1 && ref $_[0] eq 'HASH') { return exists $_[0]{$k} ? $_[0]{$k} : NOTHING }
    for (@_) { return $_->[1] if equal($_->[0], $k) }
    NOTHING;
}
sub stripPrefix {
    my ($p, $xs) = @_;
    return NOTHING unless isPrefixOf($p, $xs);
    ref $xs ? [ @$xs[ scalar(@$p) .. $#$xs ] ] : substr($xs, length $p);
}

# ---------------------------------------------------------------- 7. higher-order lists
sub fmap      { my $f = shift; map { scalar $f->($_) } @_ }
sub filter    { my $p = shift; grep { $p->($_) } @_ }
sub concat    { map { @$_ } @_ }
sub concatMap { my $f = shift; map { $f->($_) } @_ }        # f returns a list
sub cross {                                   # cartesian product of array refs
    my @acc = ([]);
    for my $l (@_) { @acc = map { my $s = $_; map { [ @$s, $_ ] } @$l } @acc }
    @acc;
}
sub starmap   { my $f = shift; map { scalar $f->(@$_) } @_ }
sub zipWith   { my $f = shift; map { scalar $f->(@$_) } zip(@_) }
sub find      { my $p = shift; for (@_) { return $_ if $p->($_) } NOTHING }
sub findIndex { my $p = shift; for my $i (0 .. $#_) { return $i if $p->($_[$i]) } NOTHING }
sub elemIndex { my $x = shift; findIndex(sub { equal($x, $_[0]) }, @_) }
sub partition { my $p = shift; my (@y, @n); push @{ $p->($_) ? \@y : \@n }, $_ for @_; (\@y, \@n) }

# ---------------------------------------------------------------- 8. slicing & spans
sub span       { my $p = shift; my $i = 0; $i++ while $i < @_ && $p->($_[$i]); ([ @_[ 0 .. $i - 1 ] ], [ @_[ $i .. $#_ ] ]) }
sub break_     { my $p = shift; span(sub { !$p->(@_) }, @_) }
sub takeWhile  { my $p = shift; my @o; for (@_) { last unless $p->($_); push @o, $_ } @o }
sub dropWhile  { my $p = shift; my $i = 0; $i++ while $i < @_ && $p->($_[$i]); @_[ $i .. $#_ ] }
sub takeUntil  { my $p = shift; my @o; for (@_) { push @o, $_; last if $p->($_) } @o }  # inclusive
sub inits      { map { [ @_[ 0 .. $_ - 1 ] ] } 0 .. scalar(@_) }
sub tails      { map { [ @_[ $_ .. $#_ ] ] } 0 .. scalar(@_) }
sub chunksOf {
    my $n = shift;
    die "chunksOf: n must be > 0\n" if $n <= 0;
    my @o;
    for (my $i = 0; $i < @_; $i += $n) { my $j = $i + $n - 1; $j = $#_ if $j > $#_; push @o, [ @_[ $i .. $j ] ] }
    @o;
}
sub windows    { my $n = shift; map { [ @_[ $_ .. $_ + $n - 1 ] ] } 0 .. @_ - $n }
sub groupBy {
    my $eq = shift;
    my @o;
    for (@_) { if (@o && $eq->($o[-1][0], $_)) { push @{ $o[-1] }, $_ } else { push @o, [$_] } }
    @o;
}
sub group      { groupBy(\&equal, @_) }
sub transpose {                               # ragged rows allowed
    my @rows = @_;
    my @o;
    for (my $i = 0;; $i++) {
        my @c = map { $_->[$i] } grep { $i < @$_ } @rows;
        last unless @c;
        push @o, \@c;
    }
    @o;
}
sub intersperse { my $s = shift; return () unless @_; my @o = ($_[0]); push @o, $s, $_ for @_[ 1 .. $#_ ]; @o }
sub intercalate { my $s = shift; ref $s ? concat(intersperse($s, @_)) : join($s, @_) }

# ---------------------------------------------------------------- 9. sorting & searching
sub comparing { my $f = shift; sub { compare(scalar $f->($_[0]), scalar $f->($_[1])) } }
sub sorted    { sort { compare($a, $b) } @_ }
sub sortBy    { my $c = shift; sort { $c->($a, $b) } @_ }
sub sortOn    { my $f = shift; map { $_->[1] } sort { compare($a->[0], $b->[0]) } map { [ scalar $f->($_), $_ ] } @_ }
sub maximum   { die "maximum: empty list\n" unless @_; my $m = shift; for (@_) { $m = $_ if compare($_, $m) >= 0 } $m }
sub minimum   { die "minimum: empty list\n" unless @_; my $m = shift; for (@_) { $m = $_ if compare($_, $m) < 0 } $m }
sub maxOn {
    my $f = shift;
    die "maxOn: empty list\n" unless @_;
    my ($m, $k) = ($_[0], scalar $f->($_[0]));
    for (@_[ 1 .. $#_ ]) { my $kk = $f->($_); ($m, $k) = ($_, $kk) if compare($kk, $k) > 0 }
    $m;
}
sub minOn {
    my $f = shift;
    die "minOn: empty list\n" unless @_;
    my ($m, $k) = ($_[0], scalar $f->($_[0]));
    for (@_[ 1 .. $#_ ]) { my $kk = $f->($_); ($m, $k) = ($_, $kk) if compare($kk, $k) < 0 }
    $m;
}
sub merge {                                   # merge two sorted array refs, stable
    my ($x, $y) = @_;
    my ($i, $j, @o) = (0, 0);
    while ($i < @$x && $j < @$y) { push @o, compare($y->[$j], $x->[$i]) < 0 ? $y->[ $j++ ] : $x->[ $i++ ] }
    (@o, @$x[ $i .. $#$x ], @$y[ $j .. $#$y ]);
}

# ---------------------------------------------------------------- 10. strings
sub lines   { my @l = split /\r?\n/, ($_[0] // ''), -1; pop @l if @l && $l[-1] eq ''; @l }
sub unlines { join '', map { "$_\n" } @_ }
sub words   { split ' ', ($_[0] // '') }
sub unwords { join ' ', @_ }
sub chars   { split //, ($_[0] // '') }
sub strip   { my $s = shift; $s =~ s/^\s+|\s+$//g; $s }
sub splitOn { my ($sep, $s) = @_; split /\Q$sep\E/, $s, -1 }

# ---------------------------------------------------------------- 11. containers (hash refs)
sub fromList      { my %h; $h{ $_->[0] } = $_->[1] for @_; \%h }
sub toList        { my $h = shift; map { [ $_, $h->{$_} ] } sorted(keys %$h) }
sub fromListWith  { my $f = shift; my %h; for (@_) { my ($k, $v) = @$_; $h{$k} = exists $h{$k} ? $f->($v, $h{$k}) : $v } \%h }
sub insertWith    { my ($f, $k, $v, $h) = @_; my %n = %$h; $n{$k} = exists $n{$k} ? $f->($v, $n{$k}) : $v; \%n }
sub adjust        { my ($f, $k, $h) = @_; my %n = %$h; $n{$k} = $f->($n{$k}) if exists $n{$k}; \%n }
sub unionWith     { my ($f, $x, $y) = @_; my %n = %$x; for (keys %$y) { $n{$_} = exists $n{$_} ? $f->($n{$_}, $y->{$_}) : $y->{$_} } \%n }
sub mapValues     { my ($f, $h) = @_; +{ map { ($_ => scalar $f->($h->{$_})) } keys %$h } }
sub filterWithKey { my ($p, $h) = @_; +{ map { ($_ => $h->{$_}) } grep { $p->($_, $h->{$_}) } keys %$h } }
sub getpath {                                 # getpath($tree, 'a', 0, 'b') through hashes and arrays
    my ($t, @ks) = @_;
    for my $k (@ks) {
        if    (ref $t eq 'HASH' && exists $t->{$k}) { $t = $t->{$k} }
        elsif (ref $t eq 'ARRAY' && _isnum($k) && $k < @$t && $k >= -scalar(@$t)) { $t = $t->[$k] }
        else  { return NOTHING }
    }
    $t;
}
sub counter  { my %h; $h{$_}++ for @_; \%h }
sub classify { my $f = shift; my %h; push @{ $h{ $f->($_) } }, $_ for @_; \%h }     # key -> [items]
sub bagDiff  { my ($x, $y) = @_; +{ map { ($_ => $x->{$_} - ($y->{$_} // 0)) } grep { $x->{$_} > ($y->{$_} // 0) } keys %$x } }
sub bagInter { my ($x, $y) = @_; +{ map { my $v = $x->{$_} < $y->{$_} ? $x->{$_} : $y->{$_}; $v ? ($_ => $v) : () } grep { exists $y->{$_} } keys %$x } }
sub bagUnion { my ($x, $y) = @_; my %n = %$x; for (keys %$y) { $n{$_} = $y->{$_} if !exists $n{$_} || $y->{$_} > $n{$_} } \%n }
sub bagSub   { my ($x, $y) = @_; for (keys %$x) { return 0 if ($y->{$_} // 0) < $x->{$_} } 1 }   # x within y

# ---------------------------------------------------------------- 12. Maybe
sub isJust      { isNothing($_[0]) ? 0 : 1 }
sub bindM       { my ($x, $f) = @_; isNothing($x) ? NOTHING : $f->($x) }
sub pipeM       { my $x = shift; for my $f (@_) { return NOTHING if isNothing($x); $x = $f->($x) } $x }   # do-block
sub fromMaybe   { my ($d, $x) = @_; isNothing($x) ? $d : $x }
sub maybe       { my ($d, $f, $x) = @_; isNothing($x) ? $d : $f->($x) }
sub listToMaybe { @_ ? $_[0] : NOTHING }
sub maybeToList { isNothing($_[0]) ? () : ($_[0]) }
sub catMaybes   { grep { !isNothing($_) } @_ }
sub mapMaybe    { my $f = shift; grep { !isNothing($_) } map { scalar $f->($_) } @_ }
sub sequenceM   { for (@_) { return NOTHING if isNothing($_) } [@_] }
sub traverseM   { my $f = shift; sequenceM(fmap($f, @_)) }
sub maybeGet {
    my ($c, $k) = @_;
    ref $c eq 'HASH' ? (exists $c->{$k} ? $c->{$k} : NOTHING)
                     : ($k < @$c && $k >= -scalar(@$c) ? $c->[$k] : NOTHING);
}

# ---------------------------------------------------------------- 13. Either
sub Ok       { [ 'ok',  $_[0] ] }
sub Err      { [ 'err', $_[0] ] }
sub isOk     { ref $_[0] eq 'ARRAY' && $_[0][0] eq 'ok'  ? 1 : 0 }
sub isErr    { ref $_[0] eq 'ARRAY' && $_[0][0] eq 'err' ? 1 : 0 }
sub unwrap   { isErr($_[0]) ? die("unwrap: $_[0][1]\n") : $_[0][1] }
sub bindE    { my ($e, $f) = @_; isErr($e) ? $e : $f->($e->[1]) }
sub pipeE    { my $e = shift; for my $f (@_) { return $e if isErr($e); $e = $f->($e->[1]) } $e }   # do-block
sub either   { my ($fl, $fr, $e) = @_; isErr($e) ? $fl->($e->[1]) : $fr->($e->[1]) }
sub sequenceE { my @o; for (@_) { return $_ if isErr($_); push @o, $_->[1] } Ok(\@o) }
sub traverseE { my $f = shift; sequenceE(fmap($f, @_)) }
sub partitionEithers { my (@ok, @err); push @{ isErr($_) ? \@err : \@ok }, $_->[1] for @_; (\@ok, \@err) }
sub note     { my ($msg, $x) = @_; isNothing($x) ? Err($msg) : Ok($x) }
sub hush     { isErr($_[0]) ? NOTHING : $_[0][1] }
sub tryE     { my ($f, @a) = @_; my $r; eval { $r = $f->(@a); 1 } ? Ok($r) : do { chomp(my $m = $@); Err($m) } }

# ---------------------------------------------------------------- 14. parser combinators
sub pureP  { my $v = shift; sub { [ $v, $_[0] ] } }
sub failP  { sub { FAIL } }
sub mapP   { my ($f, $p) = @_; sub { my $r = $p->($_[0]); isFail($r) ? FAIL : [ scalar $f->($r->[0]), $r->[1] ] } }
sub bindP  { my ($p, $f) = @_; sub { my $r = $p->($_[0]); isFail($r) ? FAIL : $f->($r->[0])->($r->[1]) } }
sub seqP {                                    # run in order, value is [v1, v2, ...]
    my @ps = @_;
    sub {
        my $s = shift;
        my @v;
        for my $p (@ps) { my $r = $p->($s); return FAIL if isFail($r); push @v, $r->[0]; $s = $r->[1] }
        [ \@v, $s ];
    };
}
sub alt    { my @ps = @_; sub { for my $p (@ps) { my $r = $p->($_[0]); return $r unless isFail($r) } FAIL } }
sub many {
    my $p = shift;
    sub {
        my $s = shift;
        my @o;
        while (1) { my $r = $p->($s); last if isFail($r) || $r->[1] eq $s; push @o, $r->[0]; $s = $r->[1] }
        [ \@o, $s ];
    };
}
sub many1 {
    my $p = shift;
    my $m = many($p);
    sub { my $r = $p->($_[0]); return FAIL if isFail($r); my $t = $m->($r->[1]); [ [ $r->[0], @{ $t->[0] } ], $t->[1] ] };
}
sub sepBy {
    my ($p, $sep) = @_;
    my $m = many(sub { my $r = $sep->($_[0]); isFail($r) ? FAIL : $p->($r->[1]) });
    sub { my $r = $p->($_[0]); return [ [], $_[0] ] if isFail($r); my $t = $m->($r->[1]); [ [ $r->[0], @{ $t->[0] } ], $t->[1] ] };
}
sub optP    { my ($p, $d) = @_; sub { my $r = $p->($_[0]); isFail($r) ? [ $d, $_[0] ] : $r } }
sub lit     { my $c = shift; sub { (my $s = $_[0]) =~ s/^\s+//; substr($s, 0, length $c) eq $c ? [ $c, substr($s, length $c) ] : FAIL } }
sub rx {                                      # regex token, optional converter
    my ($pat, $conv) = @_;
    my $re = qr/$pat/;
    sub {
        (my $s = $_[0]) =~ s/^\s+//;
        return FAIL unless $s =~ /\A($re)/;
        my $m = $1;
        [ $conv ? $conv->($m) : $m, substr($s, length $m) ];
    };
}
sub between { my ($o, $c, $p) = @_; mapP(sub { $_[0][1] }, seqP($o, $p, $c)) }
sub lazyP   { my $thunk = shift; sub { $thunk->()->(@_) } }       # for recursive grammars
sub numberP { rx(qr/-?\d+(?:\.\d+)?(?:[eE][-+]?\d+)?/, sub { $_[0] + 0 }) }
sub identP  { rx(qr/[A-Za-z_]\w*/) }
sub chainl1 {                                 # chainl1($term, { '+' => sub {...}, '-' => sub {...} })
    my ($p, $ops) = @_;
    my $opp = alt(map { lit($_) } sort { length $b <=> length $a } keys %$ops);
    sub {
        my $vr = $p->($_[0]);
        return FAIL if isFail($vr);
        while (1) {
            my $op = $opp->($vr->[1]);
            last if isFail($op);
            my $w = $p->($op->[1]);
            last if isFail($w);
            $vr = [ $ops->{ $op->[0] }->($vr->[0], $w->[0]), $w->[1] ];
        }
        $vr;
    };
}
sub runParser {
    my ($p, $s) = @_;
    my $r = $p->($s);
    return Err('no parse: ' . show($s)) if isFail($r);
    (my $rest = $r->[1]) =~ s/^\s+|\s+$//g;
    return Err('unconsumed input: ' . show($rest)) if length $rest;
    Ok($r->[0]);
}

# ---------------------------------------------------------------- 15. monoids  [empty, op]
sub Monoid  { [ $_[0], $_[1] ] }
sub mconcat { my $m = shift; foldl($m->[1], $m->[0], @_) }
sub foldMap { my ($f, $m, @xs) = @_; mconcat($m, fmap($f, @xs)) }
sub both {
    my ($m1, $m2) = @_;
    Monoid([ $m1->[0], $m2->[0] ], sub { [ $m1->[1]->($_[0][0], $_[1][0]), $m2->[1]->($_[0][1], $_[1][1]) ] });
}
sub Sum()     { Monoid(0,  sub { $_[0] + $_[1] }) }
sub Product() { Monoid(1,  sub { $_[0] * $_[1] }) }
sub All()     { Monoid(1,  sub { $_[0] && $_[1] ? 1 : 0 }) }
sub Any()     { Monoid(0,  sub { $_[0] || $_[1] ? 1 : 0 }) }
sub MaxM()    { Monoid(-9**9**9, sub { compare($_[0], $_[1]) >= 0 ? $_[0] : $_[1] }) }
sub MinM()    { Monoid( 9**9**9, sub { compare($_[0], $_[1]) <= 0 ? $_[0] : $_[1] }) }
sub ListM()   { Monoid([], sub { [ @{ $_[0] }, @{ $_[1] } ] }) }
sub StrM()    { Monoid('', sub { $_[0] . $_[1] }) }
sub First()   { Monoid(NOTHING, sub { isNothing($_[0]) ? $_[1] : $_[0] }) }
sub Last()    { Monoid(NOTHING, sub { isNothing($_[1]) ? $_[0] : $_[1] }) }

# ---------------------------------------------------------------- export table
{
    no strict 'refs';
    @EXPORT = sort grep {
        !/^_/ && !/::$/ && !/^(?:import|BEGIN|END|INIT|CHECK|UNITCHECK|DESTROY|AUTOLOAD)$/
          && defined &{"Prelude::$_"}
    } keys %Prelude::;
}

1;

__END__

=head1 NAME

Prelude - Haskell-flavoured functional toolkit in pure core Perl

=head1 SYNOPSIS

    use Prelude;                       # import everything (215 functions)
    use Prelude qw(fmap foldl show);   # or just these

    my @sq = fmap(sub { $_[0] ** 2 }, 1 .. 5);           # 1 4 9 16 25
    my $s  = foldl(sub { $_[0] + $_[1] }, 0, @sq);        # 55
    pp(chunksOf(2, @sq));                                 # prints [[1,4],[9,16],[25]]

    # one-liners from Git Bash
    perl -Ilib -MPrelude -E 'pp sum grep { $_ % 3 == 0 || $_ % 5 == 0 } 1..999'

    # interactive session
    perl -Ilib -MPrelude -de0
      DB<1> x pp(permutations(1,2,3))

Run the test suite with C<perl t/prelude.t>; it doubles as a usage catalogue.

=head1 CONVENTIONS

=over 4

=item Callbacks receive their arguments in C<@_>.

    fmap(sub { $_[0] * 2 }, @xs);  zipWith(sub { $_[0] + $_[1] }, \@a, \@b);

=item Lists are flat trailing arguments and come back flat.

    take(3, @xs);  filter(\&even, 1 .. 10);

=item Nested results and tuples are array refs.

    chunksOf(2, 1 .. 5);       # ([1,2], [3,4], [5])
    fst([1, 2]);               # 1
    my ($yes, $no) = partition(\&even, 1 .. 5);    # two array refs

=item Functions taking two or more lists take array refs.

    zip(\@a, \@b);  merge(\@sorted1, \@sorted2);  cross([1,2], ['a','b']);

=item Maps are hash refs and are never mutated; a new ref is returned.

=item Maybe is the value itself or C<NOTHING>. C<NOTHING> is false in boolean
context and prints as C<NOTHING>. Either is C<Ok($v)> = C<['ok', $v]> or
C<Err($e)> = C<['err', $e]>.

=item Names that collide with Perl keywords get a trailing underscore:
C<last_ until_ pipe_ break_ and_ or_ not_>. Maybe-bind is C<bindM> because
C<bind> is a Perl builtin.

=item C<equal>, C<compare>, C<show> are deep: they descend array and hash refs,
so C<nub>, C<elem>, C<group>, C<sorted> work on nested data.

=back

=head1 FUNCTIONS

=head2 Functions and combinators

C<identity id const flip curry uncurry partial compose o pipe_ on fix memo memoFix>

    compose($f, $g)->($x)          # $f->($g->($x)); o() is an alias
    pipe_($x, $f, $g)              # $g->($f->($x)), left to right
    curry($add)->(5)->(10)         # 15
    partial($add, 10)->(3)         # 13
    on($add, $sq)->(3, 4)          # 9 + 16
    fix(sub { my ($self, $n) = @_; $n <= 1 ? 1 : $n * $self->($n - 1) })->(5)   # 120
    my $fib = memoFix(sub { my ($f, $n) = @_; $n < 2 ? $n : $f->($n-1) + $f->($n-2) });
    $fib->(90)                     # instant

C<memo> keys on C<show(\@args)>, so it works for reference arguments too.

=head2 Pairs

C<fst snd swap bimap>

    bimap($inc, $dbl, [1, 2])      # [2, 4]

=head2 Arithmetic and logic

C<div mod quot rem divMod quotRem even odd signum negate succ pred gcd lcm isqrt
hypot sum product range not_ and_ or_ any all countIf>

C<div>/C<mod> floor toward negative infinity (Haskell C<div>/C<mod>);
C<quot>/C<rem> truncate toward zero.

    div(-7, 2), mod(-7, 2)         # -4, 1
    quot(-7, 2), rem(-7, 2)        # -3, -1
    range(10, 1, -3)               # 10 7 4 1
    succ('a'), succ(41)            # 'b', 42
    any(\&even, 1, 3, 4)           # 1
    countIf(\&odd, 1 .. 9)         # 5

=head2 Folds, scans, unfolds

C<foldl foldl1 foldr foldr1 scanl scanl1 scanr scanr1 unfoldr until_ replicateM
subsequences permutations>

    foldl($f, $z, @xs)             # $f->($acc, $x)
    foldr($f, $z, @xs)             # $f->($x, $acc)
    scanl($add, 0, 1, 2, 3)        # 0 1 3 6
    unfoldr(sub { my $n = shift; $n > 100 ? NOTHING : [$n, $n * 2] }, 1)   # 1 2 4 ... 64
    until_(sub { $_[0] > 100 }, $dbl, 1)                                  # 128
    replicateM(2, 0, 1)            # [0,0] [0,1] [1,0] [1,1]
    subsequences(1, 2, 3)          # [] [1] [2] [1,2] [3] ...

=head2 Lazy streams

A stream is a closure returning C<($x)> for the next element and C<()> when
exhausted. Infinite streams are fine as long as you finish with a terminal
operation.

Producers: C<fromListS iterate repeat cycle enumFrom unfoldS>

Transformers (lazy): C<mapS filterS zipWithS scanlS dropS dropWhileS>

Terminals (eager): C<takeS takeWhileS findS toListS>

    takeS(5, iterate($dbl, 1))                          # 1 2 4 8 16
    takeS(4, mapS($sq, filterS(\&even, enumFrom(0))))   # 0 4 16 36
    findS(sub { $_[0] > 1000 }, iterate($dbl, 1))       # 1024
    my $fibs = unfoldS(sub { my ($a, $b) = @{$_[0]}; [$a, [$b, $a + $b]] }, [0, 1]);
    sum(filter(\&even, takeWhileS(sub { $_[0] < 4e6 }, $fibs)))   # 4613732

Pull one element by hand with C<my @r = $stream-E<gt>();>.

=head2 List basics

C<head tail init last_ take drop splitAt replicate elem notElem null nub indexed
pairwise zip unzip isPrefixOf isSuffixOf isInfixOf lookup stripPrefix>

C<head>, C<tail>, C<init>, C<last_> die on an empty list.
C<isPrefixOf> and friends accept either two strings or two array refs.

    my ($l, $r) = splitAt(2, 1 .. 4);   # [1,2], [3,4]
    zip([1,2,3], ['a','b'])             # [1,'a'] [2,'b']
    unzip([1,'a'], [2,'b'])             # [1,2] ['a','b']
    isPrefixOf('ab', 'abc')             # 1
    stripPrefix([1,2], [1,2,3])         # [3]
    lookup('k', \%h)                    # value or NOTHING
    lookup(2, [1,'a'], [2,'b'])         # 'b'

=head2 Higher-order list functions

C<fmap filter concat concatMap cross starmap zipWith find findIndex elemIndex
partition>

C<fmap> calls the callback in scalar context (one in, one out); C<concatMap>
calls it in list context and flattens.

    concatMap(sub { ($_[0]) x 2 }, 1, 2)     # 1 1 2 2
    zipWith($add, [1,2,3], [10,20])          # 11 22
    find(sub { $_[0] > 3 }, 1 .. 5)          # 4, or NOTHING
    starmap($add, [1,2], [3,4])              # 3 7

=head2 Slicing and grouping

C<span break_ takeWhile dropWhile takeUntil inits tails chunksOf windows groupBy
group transpose intersperse intercalate>

    windows(3, 1 .. 5)             # [1,2,3] [2,3,4] [3,4,5]
    group(1, 1, 2, 1)              # [1,1] [2] [1]
    transpose([1,2,3], [4,5])      # [1,4] [2,5] [3]      (ragged ok)
    intercalate(', ', @strs)       # string join
    intercalate([0], [1,2], [3])   # 1 2 0 3

=head2 Sorting and searching

C<sorted sortBy sortOn comparing compare maximum minimum maxOn minOn merge equal>

C<compare> orders numbers numerically, strings with C<cmp>, and arrays
lexicographically. Sorts are stable.

    sorted([2], [1,3], [1,2])                  # [1,2] [1,3] [2]
    sortOn(sub { length $_[0] }, @words)
    sortBy(comparing(\&snd), @pairs)
    sortBy(sub { compare($_[1], $_[0]) }, @xs) # descending
    maxOn(sub { length $_[0] }, @words)

=head2 Strings

C<lines unlines words unwords chars strip splitOn show pp>

    counter(words($text))          # word frequencies
    splitOn(',', 'a,,b')           # 'a' '' 'b'
    show([1, 'a', {k => NOTHING}]) # [1,"a",{"k":NOTHING}]
    pp($x)                         # prints show($x), returns $x

=head2 Containers (hash refs)

C<fromList toList fromListWith insertWith adjust unionWith mapValues
filterWithKey getpath counter classify bagDiff bagInter bagUnion bagSub>

    fromListWith($add, ['a',1], ['b',2], ['a',3])     # {a=>4, b=>2}
    unionWith($add, \%h1, \%h2)
    classify(sub { length $_[0] }, @words)             # {3 => [...], 5 => [...]}
    getpath($tree, 'users', 0, 'name')                 # value or NOTHING
    my $b1 = counter(chars('aabbbc'));
    bagSub(counter(chars('ab')), $b1)                  # 1: multiset containment

=head2 Maybe

C<isJust isNothing bindM pipeM fromMaybe maybe listToMaybe maybeToList catMaybes
mapMaybe sequenceM traverseM maybeGet>

C<pipeM> is the do-block: each function takes the unwrapped value and returns
a value or C<NOTHING>; the first C<NOTHING> short-circuits.

    my $recip = sub { $_[0] == 0 ? NOTHING : 1 / $_[0] };
    pipeM(4, $recip, $recip)       # 4
    pipeM(0, $recip, ...)          # NOTHING, later steps never run
    fromMaybe(0, maybeGet(\%h, 'missing'))
    mapMaybe($recip, 1, 0, 2)      # 1 0.5

=head2 Either

C<Ok Err isOk isErr unwrap bindE pipeE either sequenceE traverseE
partitionEithers note hush tryE>

    my $int = sub { $_[0] =~ /^-?\d+$/ ? Ok($_[0] + 0) : Err("bad int: $_[0]") };
    my $pos = sub { $_[0] > 0 ? Ok($_[0]) : Err("not positive") };
    pipeE(Ok('5'), $int, $pos)     # ['ok', 5]
    pipeE(Ok('x'), $int, $pos)     # ['err', 'bad int: x']
    tryE(sub { die "boom\n" })     # ['err', 'boom']   -- die becomes Err
    traverseE($int, '1', 'x')      # first Err wins
    either(sub { "E:$_[0]" }, sub { "V:$_[0]" }, $e)
    note('missing', maybeGet(\%h, 'k'))   # Maybe -> Either

=head2 Parser combinators

A parser is C<sub($input)> returning C<[$value, $rest]> or C<FAIL>. C<lit> and
C<rx> skip leading whitespace.

C<pureP failP mapP bindP seqP alt many many1 sepBy optP lit rx between lazyP
numberP identP chainl1 runParser>

    my $expr;
    my $factor = alt(numberP(), between(lit('('), lit(')'), lazyP(sub { $expr })));
    my $term   = chainl1($factor, { '*' => sub { $_[0] * $_[1] }, '/' => sub { $_[0] / $_[1] } });
    $expr      = chainl1($term,   { '+' => sub { $_[0] + $_[1] }, '-' => sub { $_[0] - $_[1] } });
    runParser($expr, '2 * (3 + 4) - 5')          # ['ok', 9]
    runParser($expr, '1 + 2 )')                  # ['err', 'unconsumed input: ")"']

    my $list = between(lit('['), lit(']'), sepBy(numberP(), lit(',')));
    runParser($list, '[1, 2, 3]')                # ['ok', [1,2,3]]

    my $str = rx(qr/"[^"]*"/, sub { substr($_[0], 1, -1) });
    my $kv  = mapP(sub { [$_[0][0], $_[0][2]] }, seqP(identP(), lit('='), alt(numberP(), $str)));
    my $cfg = mapP(sub { fromList(@{$_[0]}) }, sepBy($kv, lit(';')));
    runParser($cfg, 'port = 8080; host = "a b"') # ['ok', {port=>8080, host=>'a b'}]

C<seqP> yields an array ref of all sub-results; C<bindP> lets a later parser
depend on an earlier value.

=head2 Monoids

A monoid is C<[$empty, $op]>. C<Monoid mconcat foldMap both> plus the
constants C<Sum Product All Any MaxM MinM ListM StrM First Last>.

    mconcat(Sum, 1 .. 4)                             # 10
    foldMap($sq, Sum, 1, 2, 3)                       # 14
    mconcat(ListM, [1], [2, 3])                      # [1,2,3]
    foldMap(sub { [$_[0], $_[0]] }, both(MinM, MaxM), 4, 1, 9)   # [1, 9] in one pass
    mconcat(both(Sum, Sum), map { [$_, 1] } @xs)     # [total, count]

=head1 NOTES

Only scalar results are memoised by C<memo>. Deep recursion warnings are
disabled inside the module. C<show> prints anything that looks like a number
unquoted, so C<"42"> and C<42> render the same.

=head1 AUTHOR

Built for use on a machine with nothing but Git for Windows.

=cut
