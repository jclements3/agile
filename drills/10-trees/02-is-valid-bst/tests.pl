+{
    fn    => 'is_valid_bst',
    cmp   => 'bool',
    call  => sub { my ($f, $t) = @_; $f->(Drills::tree_from($t)) },
    cases => [
        [ 'sample',               [ [ 2, 1, 3 ] ],                          1 ],
        [ 'deep violation',       [ [ 5, 1, 6, undef, undef, 3, 7 ] ],      0 ],
        [ 'empty',                [ [] ],                                   1 ],
        [ 'equal value is not ok',[ [ 2, 2 ] ],                             0 ],
        [ 'negatives',            [ [ 0, -5, 4, -9, -1 ] ],                 1 ],
        [ 'child check passes, range fails', [ [ 10, 5, 15, undef, undef, 6, 20 ] ], 0 ],
    ],
}
