+{
    fn    => 'second_largest',
    cases => [
        [ 'sample',        [ [ 1, 5, 3 ] ],     3 ],
        [ 'repeated max',  [ [ 5, 1, 5, 3 ] ],  3 ],
        [ 'two values',    [ [ 2, 1 ] ],        1 ],
        [ 'negatives',     [ [ -1, -5, -3 ] ],  -3 ],
        [ 'many copies',   [ [ 7, 7, 7, 2, 2 ] ], 2 ],
    ],
}
