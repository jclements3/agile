+{
    fn    => 'top3_names',
    cases => [
        [ 'sample',   [ [ [ 'ada', 90 ], [ 'bob', 95 ], [ 'cy', 90 ], [ 'dee', 99 ] ] ], [qw(dee bob ada)] ],
        [ 'all tie',  [ [ [ 'b', 1 ], [ 'a', 1 ], [ 'c', 1 ] ] ],                       [qw(a b c)] ],
        [ 'fewer than three', [ [ [ 'x', 5 ] ] ],                                       ['x'] ],
        [ 'empty',    [ [] ],                                                           [] ],
    ],
}
