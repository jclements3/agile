+{
    fn    => 'every_other',
    cases => [
        [ 'sample', [ [ 1, 2, 3, 4, 5 ] ], [ 1, 3, 5 ] ],
        [ 'empty',  [ [] ],                [] ],
        [ 'even length', [ [qw(a b c d)] ], [qw(a c)] ],
        [ 'one',    [ [9] ],               [9] ],
    ],
}
