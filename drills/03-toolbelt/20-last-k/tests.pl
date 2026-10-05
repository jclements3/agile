+{
    fn    => 'last_k',
    cases => [
        [ 'sample',      [ [ 1, 2, 3, 4 ], 2 ], [ 3, 4 ] ],
        [ 'fewer than k', [ [1], 5 ],           [1] ],
        [ 'empty',       [ [], 3 ],             [] ],
        [ 'k equals n',  [ [qw(a b c)], 3 ],    [qw(a b c)] ],
    ],
}
