+{
    fn    => 'common_ordered',
    cases => [
        [ 'sample',       [ [ 1, 2, 3, 4 ], [ 3, 1, 5 ] ], [ 1, 3 ] ],
        [ 'repeats once', [ [ 1, 1, 2 ], [1] ],            [1] ],
        [ 'none',         [ [ 1, 2 ], [3] ],               [] ],
        [ 'empty b',      [ [ 1, 2 ], [] ],                [] ],
        [ 'words',        [ [qw(b a c a)], [qw(a b)] ],    [qw(b a)] ],
    ],
}
