+{
    fn    => 'fix_average',
    cmp   => 'float',
    cases => [
        [ 'sample',   [ [ 1, 2, 3 ] ], 2 ],
        [ 'empty',    [ [] ],          0 ],
        [ 'negative', [ [-5] ],        -5 ],
        [ 'fraction', [ [ 1, 2 ] ],    1.5 ],
    ],
}
