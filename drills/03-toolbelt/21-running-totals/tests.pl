+{
    fn    => 'running_totals',
    cases => [
        [ 'sample',    [ [ 3, 1, 4 ] ],   [ 3, 4, 8 ] ],
        [ 'empty',     [ [] ],            [] ],
        [ 'negatives', [ [ 5, -5, 2 ] ],  [ 5, 0, 2 ] ],
    ],
}
