+{
    fn    => 'count_common',
    cases => [
        [ 'sample',       [ [ 1, 2, 2, 3 ], [ 2, 3, 3, 4 ] ], 2 ],
        [ 'disjoint',     [ [1], [2] ],                       0 ],
        [ 'empty side',   [ [], [ 1, 2 ] ],                   0 ],
        [ 'all shared',   [ [ 5, 5, 6 ], [ 6, 5 ] ],          2 ],
        [ 'strings',      [ [qw(x y z)], [qw(z q x)] ],       2 ],
    ],
}
