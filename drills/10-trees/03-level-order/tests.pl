+{
    fn    => 'level_order',
    call  => sub { my ($f, $t) = @_; $f->(Drills::tree_from($t)) },
    cases => [
        [ 'sample',     [ [ 3, 9, 20, undef, undef, 15, 7 ] ], [ [3], [ 9, 20 ], [ 15, 7 ] ] ],
        [ 'one node',   [ [1] ],                               [ [1] ] ],
        [ 'empty',      [ [] ],                                [] ],
        [ 'lopsided',   [ [ 1, 2, undef, 3, 4 ] ],             [ [1], [2], [ 3, 4 ] ] ],
    ],
}
