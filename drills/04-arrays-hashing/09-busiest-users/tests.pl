+{
    fn    => 'busiest_users',
    cases => [
        [ 'sample',   [ [ 'ann login', 'bo save', 'ann save' ] ], ['ann'] ],
        [ 'tie',      [ [ 'a x', 'b y' ] ],                       [ 'a', 'b' ] ],
        [ 'empty',    [ [] ],                                     [] ],
        [ 'three way', [ [ 'c q', 'b q', 'a q', 'c r', 'b r', 'a r' ] ], [ 'a', 'b', 'c' ] ],
        [ 'one line', [ ['zed ping'] ],                           ['zed'] ],
    ],
}
