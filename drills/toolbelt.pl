#!/usr/bin/perl
# toolbelt.pl -- the Perl toolbelt for coding drills, each idiom proven on a micro-case.
#
#   perl drills/toolbelt.pl          runs every check: "toolbelt: all N idioms verified"
#
# Read a block, cover it, retype it from memory into a scratch file until it runs with `perl -c` clean.
# Every lookup you needed is a note for the drill log. Core Perl 5.10 only: List::Util's sum, max, min, first
# and reduce are old enough everywhere; sum0 and uniq are not, so they are written by hand below.
use strict;
use warnings;
use List::Util qw(sum max min first reduce);

my ($n, $bad) = (0, 0);
sub ok { my ($cond, $name) = @_; $n++; return 1 if $cond; $bad++; print "not ok $n - $name\n"; 0 }
sub same { my ($x, $y) = @_; join("\x1f", map { defined $_ ? $_ : 'undef' } @$x) eq join("\x1f", map { defined $_ ? $_ : 'undef' } @$y) }

# ---------------------------------------------------------------- the binder's block: input, counting, sorting
{
    my $text = "3 7\n5 1 5 9 1 5\n";
    open my $in, '<', \$text or die;
    chomp(my @lines = <$in>);                       # all lines, newline removed
    my ($k, $t) = split ' ', $lines[0];             # split ' ' trims and collapses runs of blanks
    my @x = split ' ', $lines[1];
    ok($k == 3 && $t == 7 && @x == 6, "split ' ' on the first two lines");
    my %count; $count{$_}++ for @x;                 # count
    ok($count{5} == 3 && $count{1} == 2, 'count with $h{$_}++');
    my @top = sort { $count{$b} <=> $count{$a} or $a <=> $b } keys %count;   # count desc, then value asc
    ok(same(\@top, [5, 1, 9]), 'two-level sort key: count desc, then value asc');
    my %seen; my @dedup = grep { !$seen{$_}++ } @x;   # de-duplicate, keep order
    ok(same(\@dedup, [5, 1, 9]), 'de-duplicate keeping first occurrences');
    my @rows = ([a => 1], [b => 2], [a => 3]);
    my %group; push @{ $group{ $_->[0] } }, $_->[1] for @rows;   # group into a hash of arrays
    ok(same($group{a}, [1, 3]) && same($group{b}, [2]), 'group into a hash of arrays');
    ok(join(' ', reverse @x) eq '5 1 9 5 1 5', 'join and reverse');
    ok(sprintf('%.1f', 4.5) eq '4.5' && sprintf('%.1f', 5) eq '5.0', 'printf with an explicit format');
    ok(same([ sort { $a <=> $b } 10, 9, 100 ], [9, 10, 100]) && same([ sort 10, 9, 100 ], [10, 100, 9]), 'sort { $a <=> $b } is numeric; bare sort is string order');
    ok(same([ split ' ', '  a  b ' ], ['a', 'b']) && same([ split / /, ' a  b' ], ['', 'a', '', 'b']), "split ' ' vs split / /");
}

# ---------------------------------------------------------------- List::Util, and the two it may not have
{
    my @x = (3, 1, 4, 1, 5);
    ok(sum(@x) == 14 && max(@x) == 5 && min(@x) == 1, 'sum max min');
    ok((first { $_ > 3 } @x) == 4, 'first { } returns the first match');
    ok((reduce { $a * $b } @x) == 60, 'reduce { $a * $b }');
    my $sum0 = sub { my $s = 0; $s += $_ for @_; $s };            # sum0: 0 for an empty list (sum gives undef)
    ok($sum0->() == 0 && !defined sum(), 'sum0 by hand: an empty list sums to 0');
    my $uniq = sub { my %s; grep { !$s{$_}++ } @_ };              # uniq by hand
    ok(same([ $uniq->(@x) ], [3, 1, 4, 5]), 'uniq by hand');
}

# ---------------------------------------------------------------- a queue and a deque: shift / push / unshift / pop
{
    my @d = (1, 2, 3);
    unshift @d, 0; push @d, 4;                       # both ends O(1) amortised
    ok(shift(@d) == 0 && pop(@d) == 4 && same(\@d, [1, 2, 3]), 'deque: unshift/push, shift/pop');
    my %adj = (a => ['b', 'c'], b => ['d'], c => ['d'], d => []);
    my @q = ('a'); my %dist = (a => 0);               # BFS: mark on enqueue
    while (@q) { my $c = shift @q; for my $nx (@{ $adj{$c} }) { next if exists $dist{$nx}; $dist{$nx} = $dist{$c} + 1; push @q, $nx } }
    ok($dist{d} == 2, 'BFS with a queue (mark seen when enqueued)');
    my @stack; push @stack, $_ for 1 .. 3;
    ok(pop(@stack) == 3, 'stack: push and pop');
    my @last3; for (1 .. 10) { push @last3, $_; shift @last3 if @last3 > 3 }   # a bounded window
    ok(same(\@last3, [8, 9, 10]), 'the last k: push, shift when too long');
}

# ---------------------------------------------------------------- a heap by hand (no heap module in core Perl)
sub heap_push {                                       # min-heap in an array: sift up
    my ($h, $v) = @_;
    push @$h, $v;
    my $i = $#$h;
    while ($i > 0) { my $p = int(($i - 1) / 2); last if $h->[$p] <= $h->[$i]; @$h[ $p, $i ] = @$h[ $i, $p ]; $i = $p }
}
sub heap_pop {                                        # remove the minimum: last to the root, sift down
    my ($h) = @_;
    return undef unless @$h;
    my $top = $h->[0];
    my $last = pop @$h;
    if (@$h) {
        $h->[0] = $last;
        my $i = 0;
        while (1) {
            my ($l, $r, $m) = (2 * $i + 1, 2 * $i + 2, $i);
            $m = $l if $l < @$h && $h->[$l] < $h->[$m];
            $m = $r if $r < @$h && $h->[$r] < $h->[$m];
            last if $m == $i;
            @$h[ $m, $i ] = @$h[ $i, $m ]; $i = $m;
        }
    }
    $top;
}
{
    my @nums = (5, 1, 8, 3, 9, 2, 7);
    my @h; heap_push(\@h, $_) for @nums;
    my @out; push @out, heap_pop(\@h) while @h;
    ok(same(\@out, [1, 2, 3, 5, 7, 8, 9]), 'heap_push / heap_pop give ascending order');
    my @k; for (@nums) { heap_push(\@k, $_); heap_pop(\@k) if @k > 3 }   # keep the 3 largest, min on top
    ok(same([ sort { $a <=> $b } @k ], [7, 8, 9]), 'the k largest with a size-k min-heap');
    my @mx; heap_push(\@mx, -$_) for @nums;                             # max-heap: store negated values
    ok(-heap_pop(\@mx) == 9, 'max-heap by negation');
}

# ---------------------------------------------------------------- binary search by hand: lower and upper bound
sub lower_bound { my ($a, $x) = @_; my ($lo, $hi) = (0, scalar @$a); while ($lo < $hi) { my $m = int(($lo + $hi) / 2); if ($a->[$m] < $x) { $lo = $m + 1 } else { $hi = $m } } $lo }
sub upper_bound { my ($a, $x) = @_; my ($lo, $hi) = (0, scalar @$a); while ($lo < $hi) { my $m = int(($lo + $hi) / 2); if ($a->[$m] <= $x) { $lo = $m + 1 } else { $hi = $m } } $lo }
{
    my @xs = (10, 20, 20, 30);
    ok(lower_bound(\@xs, 20) == 1 && upper_bound(\@xs, 20) == 3, 'lower and upper bound');
    ok(upper_bound(\@xs, 25) - lower_bound(\@xs, 15) == 2, 'count in a range with two bounds');
    splice @xs, lower_bound(\@xs, 25), 0, 25;          # sorted insert (O(n) for the splice)
    ok(same(\@xs, [10, 20, 20, 25, 30]), 'sorted insert with splice');
}

# ---------------------------------------------------------------- run-length encoding, prefix sums
{
    my $s = 'aaabbc';
    my @rle; while ($s =~ /((.)\2*)/g) { push @rle, [ $2, length $1 ] }
    ok(join(',', map { "$_->[0]$_->[1]" } @rle) eq 'a3,b2,c1', 'run-length encode with /((.)\2*)/g');
    my @x = (3, 1, 4, 1, 5);
    my @pref = (0); push @pref, $pref[-1] + $_ for @x;  # prefix sums: sum of x[i..j-1] = pref[j] - pref[i]
    ok($pref[4] - $pref[1] == 1 + 4 + 1, 'prefix sums answer range sums in O(1)');
}

# ---------------------------------------------------------------- memoization: a hash, or Memoize
{
    my %memo;
    my $ways; $ways = sub { my $k = shift; return 1 if $k <= 1; $memo{$k} //= $ways->($k - 1) + $ways->($k - 2) };
    ok($ways->(30) == 1346269, 'memoize by hand with a hash (//=)');
    require Memoize;
    no warnings 'redefine';
    eval 'sub climb { my $k = shift; $k <= 1 ? 1 : climb($k - 1) + climb($k - 2) } 1' or die $@;
    Memoize::memoize('climb');
    ok(climb(40) == 165580141, 'use Memoize; memoize("name") on a pure recursive sub');
}

# ---------------------------------------------------------------- pairs and combinations without a module
{
    my @x = (0 .. 4);
    my @pairs; for my $i (0 .. $#x) { for my $j ($i + 1 .. $#x) { push @pairs, [ $x[$i], $x[$j] ] } }
    ok(@pairs == 10, 'all pairs i < j: two nested loops');
    my @subsets = ([]); for my $v (1, 2, 3) { push @subsets, map { [ @$_, $v ] } @subsets }
    ok(@subsets == 8, 'all subsets by doubling');
    my @words = qw(bb a ccc dd);
    ok(join(' ', sort { length($b) <=> length($a) or $a cmp $b } @words) eq 'ccc bb dd a', 'sort by length desc, then alphabetically');
}

# ---------------------------------------------------------------- the five stdin shapes (from an in-memory file)
sub with_input { my ($text, $code) = @_; open my $fh, '<', \$text or die; $code->($fh) }
{
    # 1. a count, then that many lines of one integer
    my @a = with_input("3\n10\n20\n30\n", sub { my $fh = shift; my $k = <$fh>; map { scalar <$fh> + 0 } 1 .. $k });
    ok(same(\@a, [10, 20, 30]), 'shape 1: n, then n lines');
    # 2. one line of integers
    my @b = with_input("3 1 4 1 5\n", sub { my $fh = shift; split ' ', scalar <$fh> });
    ok(same(\@b, [3, 1, 4, 1, 5]), 'shape 2: one line of values');
    # 3. "R C", then an R x C matrix
    my @m = with_input("2 3\n1 2 3\n4 5 6\n", sub { my $fh = shift; my ($r, $c) = split ' ', <$fh>; map { [ split ' ', scalar <$fh> ] } 1 .. $r });
    ok(@m == 2 && same($m[1], [4, 5, 6]), 'shape 3: a matrix');
    # 4. everything as one token stream (safe under odd spacing)
    my @c = with_input("2\nalice 30\n  bob\n25\n", sub { my $fh = shift; local $/; my @t = split ' ', <$fh>; my $k = shift @t; map { [ shift @t, shift @t ] } 1 .. $k });
    ok($c[1][0] eq 'bob' && $c[1][1] == 25, 'shape 4: slurp and split into tokens');
    # 5. lines until end of input, blanks skipped
    my @d = with_input("add 3\nrm 2\n\n", sub { my $fh = shift; map { [ split ' ' ] } grep { /\S/ } <$fh> });
    ok(@d == 2 && $d[1][0] eq 'rm', 'shape 5: until EOF, skipping blank lines');
}

# ---------------------------------------------------------------- output discipline and the function + main shape
{
    my @rows = ([1, 2], [3, 4]);
    my $out = join("\n", map { join(' ', @$_) } @rows) . "\n";     # build once, print once
    ok($out eq "1 2\n3 4\n", 'build the output once with join, print once');
    my $solve = sub { my @arr = @_; max(@arr) - min(@arr) };         # all logic in a function ...
    my $main = sub { my $fh = shift; <$fh>; my @x = split ' ', <$fh>; $solve->(@x) . "\n" };   # ... and a thin stdin wrapper
    ok(with_input("5\n3 1 4 1 5\n", $main) eq "4\n", 'solve() plus a main() wrapper: both formats are one problem');
}

if ($bad) { print "toolbelt: $bad of $n FAILED\n"; exit 1 }
print "toolbelt: all $n idioms verified\n";
