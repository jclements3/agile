#!/usr/bin/perl
# Run from anywhere:  perl t/prelude.t      (TAP output; exit status = failures)
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Prelude;

my ($n, $bad) = (0, 0);
sub check { my ($name, $got, $want) = @_; $n++;
    if ($got eq $want) { print "ok $n - $name\n" }
    else { $bad++; print "not ok $n - $name\n#   got:  $got\n#   want: $want\n" } }
sub S { my ($name, $want, $got) = @_; check($name, show($got), $want) }     # scalar result
sub L { my ($name, $want, @got) = @_; check($name, show([@got]), $want) }   # list result
sub dies { my ($name, $code) = @_; check($name, (eval { $code->(); 1 } ? 'lived' : 'died'), 'died') }

my $add = sub { $_[0] + $_[1] };
my $sq  = sub { $_[0] * $_[0] };
my $inc = sub { $_[0] + 1 };
my $dbl = sub { $_[0] * 2 };
my $lt  = sub { my $k = shift; sub { $_[0] < $k } };

# ---- show / equal / compare
S 'show nested',    '[1,"a",[2,3],{"k":NOTHING},undef]', [1, 'a', [2, 3], { k => NOTHING }, undef];
S 'show escapes',   '"a\"b\\n"', "a\"b\n";
S 'equal deep',     1, equal([1, { a => [2] }], [1, { a => [2] }]);
S 'equal differs',  0, equal([1, 2], [1, 2, 3]);
S 'equal numeric',  1, equal(1, '1.0');
S 'compare arrays', -1, compare([1, 2], [1, 3]);
S 'compare prefix', -1, compare([1], [1, 0]);
S 'compare strings', 1, compare('b', 'a');
S 'NOTHING false',  0, (NOTHING ? 1 : 0);

# ---- functions
S 'identity',  5,  identity(5);
S 'const',     7,  const(7)->(1, 2, 3);
S 'flip',      3,  flip(sub { $_[0] - $_[1] })->(2, 5);
S 'curry',     15, curry($add)->(5)->(10);
S 'uncurry',   7,  uncurry($add)->([3, 4]);
S 'partial',   13, partial($add, 10)->(3);
S 'compose',   11, compose($inc, $dbl)->(5);
S 'o',         12, o($dbl, $inc)->(5);
S 'compose3',  121, compose($sq, $inc, $dbl)->(5);
S 'pipe_',     12, pipe_(5, $inc, $dbl);
S 'on',        25, on($add, $sq)->(3, 4);
S 'fix fact',  120, fix(sub { my ($self, $n) = @_; $n <= 1 ? 1 : $n * $self->($n - 1) })->(5);
my $calls = 0;
my $slow = memo(sub { $calls++; $_[0] * 10 });
$slow->(3) for 1 .. 5;
S 'memo caches', 1, $calls;
S 'memoFix fib', 12586269025, memoFix(sub { my ($f, $n) = @_; $n < 2 ? $n : $f->($n - 1) + $f->($n - 2) })->(50);

# ---- pairs
S 'fst',   1,       fst([1, 2]);
S 'snd',   2,       snd([1, 2]);
S 'swap',  '[2,1]', swap([1, 2]);
S 'bimap', '[2,4]', bimap($inc, $dbl, [1, 2]);

# ---- arithmetic
S 'div neg',    -4,  div(-7, 2);
S 'mod neg',    1,   mod(-7, 2);
S 'div negdiv', -4,  div(7, -2);
S 'quot neg',   -3,  quot(-7, 2);
S 'rem neg',    -1,  rem(-7, 2);
S 'divMod',     '[-4,1]',  divMod(-7, 2);
S 'quotRem',    '[-3,-1]', quotRem(-7, 2);
L 'even/odd',   '[1,0,1,0]', even(4), even(3), odd(-3), odd(2);
L 'signum',     '[-1,0,1]', signum(-5), signum(0), signum(9);
L 'succ/pred',  '["b","a",6,4]', succ('a'), pred('b'), succ(5), pred(5);
L 'gcd/lcm',    '[6,36,0]', gcd(12, -18), lcm(12, 18), lcm(0, 5);
L 'isqrt',      '[4,4,5,0]', isqrt(24), isqrt(16), isqrt(35), isqrt(0);
S 'hypot',      5,   hypot(3, 4);
L 'sum/product', '[10,24,0,1]', sum(1 .. 4), product(1 .. 4), sum(), product();
L 'range',      '[1,4,7,10]', range(1, 10, 3);
L 'range down', '[10,7,4,1]', range(10, 1, -3);
L 'range empty', '[]', range(5, 1);
L 'logic',      '[1,0,1,0,1]', and_(1, 1), and_(1, 0), or_(0, 1), or_(), not_(0);
L 'any/all',    '[1,0,1]', any(\&even, 1, 3, 4), all(\&even, 2, 3), all(\&even);
S 'countIf',    2, countIf(\&odd, 1 .. 4);

# ---- folds
S 'foldl',   -10, foldl(sub { $_[0] - $_[1] }, 0, 1 .. 4);
S 'foldr',   -2,  foldr(sub { $_[0] - $_[1] }, 0, 1 .. 4);
S 'foldl1',  24,  foldl1(sub { $_[0] * $_[1] }, 1 .. 4);
S 'foldr1',  -2,  foldr1(sub { $_[0] - $_[1] }, 1 .. 4);
dies 'foldl1 empty', sub { foldl1($add) };
L 'scanl',   '[0,1,3,6]', scanl($add, 0, 1, 2, 3);
L 'scanl1',  '[1,3,6]',   scanl1($add, 1, 2, 3);
L 'scanr',   '[6,5,3,0]', scanr($add, 0, 1, 2, 3);
L 'scanr1',  '[6,5,3]',   scanr1($add, 1, 2, 3);
L 'unfoldr collatz', '[6,3,10,5,16,8,4,2]',
  unfoldr(sub { my $n = shift; $n == 1 ? NOTHING : [ $n, even($n) ? $n / 2 : 3 * $n + 1 ] }, 6);
S 'until_',  128, until_(sub { $_[0] > 100 }, $dbl, 1);
L 'replicateM', '[[0,0],[0,1],[1,0],[1,1]]', replicateM(2, 0, 1);
L 'subsequences', '[[],[1],[2],[1,2],[3],[1,3],[2,3],[1,2,3]]', subsequences(1, 2, 3);
L 'permutations', '[[1,2,3],[1,3,2],[2,1,3],[2,3,1],[3,1,2],[3,2,1]]', permutations(1, 2, 3);

# ---- streams
L 'iterate/takeS',  '[1,2,4,8,16]', takeS(5, iterate($dbl, 1));
L 'repeat',         '["x","x","x"]', takeS(3, repeat('x'));
L 'cycle',          '[1,2,3,1,2]', takeS(5, cycle(1, 2, 3));
L 'enumFrom step',  '[10,15,20]', takeS(3, enumFrom(10, 5));
L 'mapS/filterS',   '[0,4,16,36]', takeS(4, mapS($sq, filterS(\&even, enumFrom(0))));
L 'takeWhileS',     '[1,2,3,4]', takeWhileS($lt->(5), enumFrom(1));
L 'dropS',          '[4,5,6]', takeS(3, dropS(3, enumFrom(1)));
L 'dropWhileS',     '[5,6]', takeS(2, dropWhileS($lt->(5), enumFrom(1)));
L 'zipWithS',       '[11,22,33]', takeS(3, zipWithS($add, enumFrom(1), enumFrom(10, 10)));
L 'scanlS',         '[0,1,3,6]', takeS(4, scanlS($add, 0, enumFrom(1)));
S 'findS',          1024, findS(sub { $_[0] > 1000 }, iterate($dbl, 1));
L 'unfoldS fibs',   '[0,1,1,2,3,5,8]', takeS(7, unfoldS(sub { my ($x, $y) = @{ $_[0] }; [ $x, [ $y, $x + $y ] ] }, [ 0, 1 ]));
L 'toListS finite', '[1,2,3]', toListS(fromListS(1, 2, 3));
my $fibs; $fibs = sub { my ($x, $y) = (0, 1); sub { my $r = $x; ($x, $y) = ($y, $x + $y); ($r) } };
S 'euler2', 4613732, sum(filter(\&even, takeWhileS($lt->(4_000_000), $fibs->())));

# ---- list basics
S 'head',    1, head(1, 2, 3);
L 'tail',    '[2,3]', tail(1, 2, 3);
L 'init',    '[1,2]', init(1, 2, 3);
S 'last_',   3, last_(1, 2, 3);
dies 'head empty', sub { head() };
L 'take',    '[1,2]', take(2, 1 .. 5);
L 'take big', '[1,2]', take(9, 1, 2);
L 'take neg', '[]', take(-1, 1, 2);
L 'drop',    '[4,5]', drop(3, 1 .. 5);
L 'drop big', '[]', drop(9, 1, 2);
L 'splitAt', '[[1,2],[3,4]]', splitAt(2, 1 .. 4);
L 'replicate', '["a","a","a"]', replicate(3, 'a');
L 'elem',    '[1,0,1]', elem(3, 1 .. 5), notElem(3, 1 .. 5), elem([1], [0], [1]);
L 'null',    '[1,0]', null(), null(0);
L 'nub',     '[3,1,2,[1]]', nub(3, 1, 3, 2, 1, [1], [1]);
L 'indexed', '[[0,"a"],[1,"b"]]', indexed('a', 'b');
L 'pairwise', '[[1,2],[2,3]]', pairwise(1, 2, 3);
L 'zip',     '[[1,"a",1],[2,"b",0]]', zip([1, 2, 3], ['a', 'b'], [1, 0]);
L 'unzip',   '[[1,2],["a","b"]]', unzip([1, 'a'], [2, 'b']);
L 'unzip empty', '[[],[]]', unzip();
L 'isPrefixOf', '[1,0,1,1]', isPrefixOf('ab', 'abc'), isPrefixOf('b', 'abc'), isPrefixOf([1, 2], [1, 2, 3]), isPrefixOf([], [1]);
L 'isSuffixOf', '[1,1,0,1]', isSuffixOf('bc', 'abc'), isSuffixOf('', 'abc'), isSuffixOf([1], [1, 2]), isSuffixOf([2, 3], [1, 2, 3]);
L 'isInfixOf',  '[1,1,0]', isInfixOf('bc', 'abcd'), isInfixOf([2, 3], [1, 2, 3, 4]), isInfixOf([3, 2], [1, 2, 3]);
L 'lookup',  '["b",NOTHING,9]', lookup(2, [1, 'a'], [2, 'b']), lookup(7, [1, 'a']), lookup('k', { k => 9 });
L 'stripPrefix', '["lo",NOTHING,[3]]', stripPrefix('hel', 'hello'), stripPrefix('x', 'hello'), stripPrefix([1, 2], [1, 2, 3]);

# ---- higher-order
L 'fmap',      '[1,4,9]', fmap($sq, 1, 2, 3);
L 'filter',    '[2,4]', filter(\&even, 1 .. 5);
L 'concat',    '[1,2,3]', concat([1], [], [2, 3]);
L 'concatMap', '[1,1,2,2]', concatMap(sub { ($_[0]) x 2 }, 1, 2);
L 'cross',     '[[1,"a"],[1,"b"],[2,"a"],[2,"b"]]', cross([1, 2], ['a', 'b']);
L 'starmap',   '[3,7]', starmap($add, [1, 2], [3, 4]);
L 'zipWith',   '[11,22]', zipWith($add, [1, 2, 3], [10, 20]);
L 'zipWith3',  '[111,222]', zipWith(sub { sum(@_) }, [1, 2], [10, 20], [100, 200]);
L 'find',      '[4,NOTHING]', find(sub { $_[0] > 3 }, 1 .. 5), find(sub { $_[0] > 9 }, 1 .. 5);
L 'findIndex', '[3,NOTHING]', findIndex(sub { $_[0] > 3 }, 1 .. 5), findIndex(sub { 0 }, 1);
S 'elemIndex', 1, elemIndex('b', 'a', 'b', 'c');
L 'partition', '[[2,4],[1,3,5]]', partition(\&even, 1 .. 5);

# ---- slicing
L 'span',      '[[1,2],[3,4,1]]', span($lt->(3), 1, 2, 3, 4, 1);
L 'break_',    '[[1,2],[3,4,1]]', break_(sub { $_[0] >= 3 }, 1, 2, 3, 4, 1);
L 'takeWhile', '[1,2]', takeWhile($lt->(3), 1, 2, 3, 1);
L 'dropWhile', '[3,1]', dropWhile($lt->(3), 1, 2, 3, 1);
L 'takeUntil', '[1,2,3]', takeUntil(sub { $_[0] == 3 }, 1 .. 5);
L 'inits',     '[[],[1],[1,2]]', inits(1, 2);
L 'tails',     '[[1,2],[2],[]]', tails(1, 2);
L 'chunksOf',  '[[1,2],[3,4],[5]]', chunksOf(2, 1 .. 5);
L 'windows',   '[[1,2,3],[2,3,4]]', windows(3, 1 .. 4);
L 'windows big', '[]', windows(5, 1, 2);
L 'group',     '[[1,1],[2],[1]]', group(1, 1, 2, 1);
L 'groupBy',   '[[1,3],[2,4],[5]]', groupBy(sub { odd($_[0]) == odd($_[1]) }, 1, 3, 2, 4, 5);
L 'transpose', '[[1,4],[2,5],[3]]', transpose([1, 2, 3], [4, 5]);
L 'intersperse', '[1,0,2,0,3]', intersperse(0, 1, 2, 3);
S 'intercalate str', '"a, b"', intercalate(', ', 'a', 'b');
L 'intercalate list', '[1,2,0,3]', intercalate([0], [1, 2], [3]);

# ---- sorting
L 'sorted',    '[1,2,10]', sorted(10, 2, 1);
L 'sorted mix', '["a","b"]', sorted('b', 'a');
L 'sorted arrays', '[[1,2],[1,3],[2]]', sorted([2], [1, 3], [1, 2]);
L 'sortOn',    '["a","ccc","bb"]', sortOn(sub { length $_[0] == 3 ? 2 : length $_[0] }, 'ccc', 'bb', 'a');
L 'sortOn stable', '[[1,"x"],[1,"y"],[2,"a"]]', sortOn(\&fst, [2, 'a'], [1, 'x'], [1, 'y']);
L 'sortBy desc', '[3,2,1]', sortBy(sub { compare($_[1], $_[0]) }, 1, 3, 2);
L 'comparing', '[["b",1],["a",2]]', sortBy(comparing(\&snd), ['a', 2], ['b', 1]);
L 'max/min',   '[9,-1,"z"]', maximum(3, 9, -1), minimum(3, 9, -1), maximum('a', 'z', 'q');
L 'maxOn/minOn', '["ccc","a"]', maxOn(sub { length $_[0] }, 'a', 'ccc', 'bb'), minOn(sub { length $_[0] }, 'bb', 'a', 'ccc');
L 'merge',     '[1,2,3,4,5,7]', merge([1, 4, 5], [2, 3, 7]);

# ---- strings
L 'lines',   '["a","","b"]', lines("a\n\nb\n");
L 'lines crlf', '["a","b"]', lines("a\r\nb");
L 'lines empty', '[]', lines('');
S 'unlines', '"a\nb\n"', unlines('a', 'b');
L 'words',   '["the","quick","fox"]', words("  the quick\tfox \n");
S 'unwords', '"a b"', unwords('a', 'b');
L 'chars',   '["a","b"]', chars('ab');
S 'strip',   '"x y"', strip("  x y \n");
L 'splitOn', '["a","","b"]', splitOn(',', 'a,,b');
S 'wordfreq', '{"a":2,"b":1}', counter(words('a b a'));

# ---- containers
S 'fromList',     '{"a":1,"b":2}', fromList([a => 1], [b => 2]);
L 'toList',       '[["a",1],["b",2]]', toList({ b => 2, a => 1 });
S 'fromListWith', '{"a":[3,1],"b":[2]}', fromListWith(sub { [ @{ $_[0] }, @{ $_[1] } ] }, [a => [1]], [b => [2]], [a => [3]]);
my $h = { a => 1 };
S 'insertWith new',  '{"a":1,"b":5}', insertWith($add, b => 5, $h);
S 'insertWith old',  '{"a":6}', insertWith($add, a => 5, $h);
S 'insertWith pure', '{"a":1}', $h;
S 'adjust',       '{"a":10}', adjust(sub { $_[0] * 10 }, 'a', $h);
S 'unionWith',    '{"a":3,"b":2,"c":4}', unionWith($add, { a => 1, b => 2 }, { a => 2, c => 4 });
S 'mapValues',    '{"a":2,"b":4}', mapValues($dbl, { a => 1, b => 2 });
S 'filterWithKey', '{"b":2}', filterWithKey(sub { $_[0] ne 'a' }, { a => 1, b => 2 });
my $tree = { a => [ { b => 'deep' } ] };
L 'getpath',      '["deep",NOTHING,{"b":"deep"}]', getpath($tree, 'a', 0, 'b'), getpath($tree, 'a', 5), getpath($tree, 'a', -1);
S 'counter',      '{"a":3,"b":1}', counter(chars('abaa'));
S 'classify',     '{"even":[2,4],"odd":[1,3]}', classify(sub { even($_[0]) ? 'even' : 'odd' }, 1 .. 4);
my ($ba, $bb) = (counter(chars('aabbbc')), counter(chars('abbbbd')));
S 'bagDiff',  '{"a":1,"c":1}', bagDiff($ba, $bb);
S 'bagInter', '{"a":1,"b":3}', bagInter($ba, $bb);
S 'bagUnion', '{"a":2,"b":4,"c":1,"d":1}', bagUnion($ba, $bb);
L 'bagSub',   '[1,0]', bagSub(counter(chars('ab')), $ba), bagSub(counter(chars('ad')), $ba);

# ---- Maybe
my $safeDiv  = sub { my ($x, $y) = @_; $y == 0 ? NOTHING : $x / $y };
my $safeRecip = sub { $safeDiv->(1, $_[0]) };
L 'isJust',     '[1,0,1]', isJust(0), isJust(NOTHING), isNothing(NOTHING);
S 'bindM',      0.5, bindM(2, $safeRecip);
S 'bindM none', 'NOTHING', bindM(NOTHING, $safeRecip);
S 'pipeM ok',   4, pipeM(4, $safeRecip, $safeRecip);
S 'pipeM short', 'NOTHING', pipeM(0, $safeRecip, sub { die "not reached\n" });
L 'fromMaybe',  '[0,5]', fromMaybe(0, NOTHING), fromMaybe(0, 5);
L 'maybe',      '["none",10]', maybe('none', $dbl, NOTHING), maybe('none', $dbl, 5);
L 'listToMaybe', '[1,NOTHING]', listToMaybe(1, 2), listToMaybe();
L 'maybeToList', '[5]', maybeToList(5), maybeToList(NOTHING);
L 'catMaybes',  '[1,0,3]', catMaybes(1, NOTHING, 0, 3);
L 'mapMaybe',   '[1,0.5]', mapMaybe($safeRecip, 1, 0, 2);
S 'sequenceM',  '[1,2]', sequenceM(1, 2);
S 'sequenceM none', 'NOTHING', sequenceM(1, NOTHING);
S 'traverseM',  'NOTHING', traverseM($safeRecip, 1, 0);
L 'maybeGet',   '[1,NOTHING,"b",NOTHING]', maybeGet({ a => 1 }, 'a'), maybeGet({}, 'z'), maybeGet([ 'a', 'b' ], 1), maybeGet(['a'], 3);

# ---- Either
my $parseInt = sub { $_[0] =~ /^-?\d+$/ ? Ok($_[0] + 0) : Err("bad int: $_[0]") };
my $positive = sub { $_[0] > 0 ? Ok($_[0]) : Err("not positive: $_[0]") };
L 'Ok/Err',     '[["ok",1],["err","x"]]', Ok(1), Err('x');
L 'isOk/isErr', '[1,0,1]', isOk(Ok(1)), isOk(Err(1)), isErr(Err(1));
S 'bindE',      '["ok",5]', bindE($parseInt->('5'), $positive);
S 'pipeE',      '["err","not positive: -3"]', pipeE(Ok('-3'), $parseInt, $positive, sub { die "not reached\n" });
S 'pipeE ok',   '["ok",10]', pipeE(Ok('5'), $parseInt, $positive, sub { Ok($_[0] * 2) });
S 'either',     '"E:x"', either(sub { "E:$_[0]" }, sub { "V:$_[0]" }, Err('x'));
S 'sequenceE',  '["ok",[1,2]]', sequenceE(Ok(1), Ok(2));
S 'sequenceE err', '["err","first"]', sequenceE(Ok(1), Err('first'), Err('second'));
S 'traverseE',  '["err","bad int: x"]', traverseE($parseInt, '1', 'x');
L 'partitionEithers', '[[1,3],["a"]]', partitionEithers(Ok(1), Err('a'), Ok(3));
L 'note',       '[["ok",1],["err","missing"]]', note('missing', 1), note('missing', NOTHING);
L 'hush',       '[1,NOTHING]', hush(Ok(1)), hush(Err(1));
S 'tryE ok',    '["ok",2]', tryE(sub { $_[0] / 2 }, 4);
S 'tryE die',   '["err","boom"]', tryE(sub { die "boom\n" });
S 'unwrap',     7, unwrap(Ok(7));
dies 'unwrap err', sub { unwrap(Err('bad')) };

# ---- parsers: arithmetic
my $expr;
my $factor = alt(numberP(), between(lit('('), lit(')'), lazyP(sub { $expr })));
my $term   = chainl1($factor, { '*' => sub { $_[0] * $_[1] }, '/' => sub { $_[0] / $_[1] } });
$expr      = chainl1($term,   { '+' => sub { $_[0] + $_[1] }, '-' => sub { $_[0] - $_[1] } });
S 'calc',          '["ok",9]', runParser($expr, '2 * (3 + 4) - 5');
S 'calc left-assoc', '["ok",2]', runParser($expr, '10 - 5 - 3');
S 'calc precedence', '["ok",14]', runParser($expr, '2 + 3 * 4');
S 'calc neg/float', '["ok",-1.5]', runParser($expr, '-3 / 2');
S 'calc unconsumed', '["err","unconsumed input: \")\""]', runParser($expr, '1 + 2 )');
S 'calc no parse',   '["err","no parse: \"*\""]', runParser($expr, '*');

# ---- parsers: lists, key=value
my $list = between(lit('['), lit(']'), sepBy(numberP(), lit(',')));
S 'sepBy',        '["ok",[1,2,3]]', runParser($list, '[1, 2, 3]');
S 'sepBy empty',  '["ok",[]]', runParser($list, '[]');
my $kv  = mapP(sub { [ $_[0][0], $_[0][2] ] }, seqP(identP(), lit('='), alt(numberP(), rx(qr/"[^"]*"/, sub { substr($_[0], 1, -1) }))));
my $cfg = mapP(sub { fromList(@{ $_[0] }) }, sepBy($kv, lit(';')));
S 'config',       '["ok",{"host":"a b","port":8080}]', runParser($cfg, 'port = 8080; host = "a b"');
S 'many1 fail',   'FAIL', many1(lit('x'))->('yyy');
S 'many',         '[["x","x"],"y"]', many(lit('x'))->('xxy');
S 'optP',         '[["-",5],""]', seqP(optP(lit('-'), '+'), numberP())->('-5');
S 'optP default', '[["+",5],""]', seqP(optP(lit('-'), '+'), numberP())->('5');
S 'bindP',        '["ok",[3,["a","a","a"]]]',
  runParser(bindP(numberP(), sub { my $k = shift; mapP(sub { [ $k, $_[0] ] }, seqP((lit('a')) x $k)) }), '3 a a a');
S 'pureP/failP',  '[1,FAIL]', [ pureP(1)->('x')->[0], failP()->('x') ] ;

# ---- monoids
S 'Sum',     10, mconcat(Sum, 1 .. 4);
S 'Product', 24, mconcat(Product, 1 .. 4);
L 'All/Any', '[0,1,1,0]', mconcat(All, 1, 0), mconcat(Any, 0, 1), mconcat(All), mconcat(Any);
L 'Max/Min', '[9,-2]', mconcat(MaxM, 3, 9, -2), mconcat(MinM, 3, 9, -2);
S 'ListM',   '[1,2,3]', mconcat(ListM, [1], [2, 3]);
S 'StrM',    '"abc"', mconcat(StrM, 'a', 'b', 'c');
L 'First/Last', '[2,3]', mconcat(First, NOTHING, 2, 3), mconcat(Last, 2, 3, NOTHING);
S 'foldMap', 14, foldMap($sq, Sum, 1, 2, 3);
S 'both mean', '[10,4]', mconcat(both(Sum, Sum), map { [ $_, 1 ] } 1 .. 4);
S 'both minmax', '[1,9]', foldMap(sub { [ $_[0], $_[0] ] }, both(MinM, MaxM), 4, 1, 9);

# ---- import list
{ package Sel; Prelude->import(qw(fmap sum)); main::check('selective import', (defined &Sel::fmap && !defined &Sel::foldl) ? 1 : 0, 1) }
dies 'unknown import', sub { Prelude->import('nope') };

print "1..$n\n";
print $bad ? "# $bad of $n FAILED\n" : "# all $n passed\n";
exit($bad ? 1 : 0);
