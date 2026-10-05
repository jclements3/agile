+{
    fn    => 'top_k_frequent',
    cmp   => 'unordered',
    cases => [
        [ 'sample',     [ [ 4, 4, 4, 7, 7, 9 ], 2 ],          [ 4, 7 ] ],
        [ 'one value',  [ [3], 1 ],                           [3] ],
        [ 'negatives',  [ [ -1, -1, 2, -1, 2, 5 ], 2 ],       [ -1, 2 ] ],
        [ 'all of them', [ [ 1, 2, 2 ], 2 ],                  [ 1, 2 ] ],
        [ 'top one',    [ [ 5, 6, 6, 6, 5, 7 ], 1 ],          [6] ],
    ],
}
