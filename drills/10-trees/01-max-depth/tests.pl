+{
    fn    => 'max_depth',
    call  => sub { my ($f, $t) = @_; $f->(Drills::tree_from($t)) },
    cases => [
        [ 'sample',     [ [ 3, 9, 20, undef, undef, 15, 7 ] ], 3 ],
        [ 'one node',   [ [1] ],                               1 ],
        [ 'empty',      [ [] ],                                0 ],
        [ 'left chain', [ [ 1, 2, undef, 3, undef, 4 ] ],      4 ],
    ],
}
