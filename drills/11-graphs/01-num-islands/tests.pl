+{
    fn    => 'num_islands',
    cases => [
        [ 'sample',            [ [ '11000', '11000', '00100', '00011' ] ], 3 ],
        [ 'two islands',       [ [ '11000', '11000', '00100' ] ],          2 ],
        [ 'diagonals do not join', [ [ '101', '010', '101' ] ],            5 ],
        [ 'all water',         [ ['000'] ],                                0 ],
        [ 'one big island',    [ [ '111', '101', '111' ] ],                1 ],
        [ 'empty grid',        [ [] ],                                     0 ],
    ],
}
