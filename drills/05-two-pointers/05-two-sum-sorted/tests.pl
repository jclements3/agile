+{
    fn    => 'two_sum_sorted',
    cases => [
        [ 'sample',     [ [ 1, 2, 4, 7 ], 9 ],          [ 1, 3 ] ],
        [ 'none',       [ [ 1, 2 ], 5 ],                undef ],
        [ 'empty',      [ [], 0 ],                      undef ],
        [ 'pattern set', [ [ 1, 2, 4, 7, 11 ], 9 ],     [ 1, 3 ] ],
        [ 'negatives',  [ [ -5, -1, 3, 8 ], 3 ],        [ 0, 3 ] ],
        [ 'pattern miss', [ [ 1, 2, 4, 7, 11 ], 10 ],   undef ],
    ],
}
