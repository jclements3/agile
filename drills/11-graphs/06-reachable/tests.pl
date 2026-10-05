+{
    fn    => 'reachable',
    cmp   => 'unordered',
    cases => [
        [ 'sample',    [ { a => [ 'b', 'c' ], b => ['d'], c => ['d'], d => [], e => [] }, 'a' ], [qw(a b c d)] ],
        [ 'isolated',  [ { a => [ 'b', 'c' ], b => ['d'], c => ['d'], d => [], e => [] }, 'e' ], ['e'] ],
        [ 'cycle',     [ { 1 => [2], 2 => [3], 3 => [1] }, 2 ],                               [ 1, 2, 3 ] ],
        [ 'not a key', [ { a => ['b'] }, 'a' ],                                               [qw(a b)] ],
    ],
}
