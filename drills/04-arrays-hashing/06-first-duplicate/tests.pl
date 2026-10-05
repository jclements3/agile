+{
    fn    => 'first_duplicate',
    cases => [
        [ 'sample',        [ [ 3, 8, 1, 8, 3 ] ],   8 ],
        [ 'all unique',    [ [ 1, 2, 3 ] ],         undef ],
        [ 'empty',         [ [] ],                  undef ],
        [ 'zero repeats',  [ [ 0, 5, 0 ] ],         0 ],
        [ 'lesson set',    [ [ 2, 5, 3, 5, 2 ] ],   5 ],
        [ 'strings',       [ [qw(a b b a)] ],       'b' ],
    ],
}
