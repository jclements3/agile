+{
    fn    => 'adjacent_diffs',
    cases => [
        [ 'sample', [ [ 5, 3, 8 ] ], [ -2, 5 ] ],
        [ 'one',    [ [7] ],         [] ],
        [ 'empty',  [ [] ],          [] ],
        [ 'flat',   [ [ 2, 2, 2 ] ], [ 0, 0 ] ],
    ],
}
