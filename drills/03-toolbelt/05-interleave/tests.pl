+{
    fn    => 'interleave',
    cases => [
        [ 'sample', [ [ 1, 2, 3 ], [ 4, 5, 6 ] ], [ 1, 4, 2, 5, 3, 6 ] ],
        [ 'empty',  [ [], [] ],                   [] ],
        [ 'one each', [ ['x'], ['y'] ],           [qw(x y)] ],
    ],
}
