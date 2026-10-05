+{
    fn    => 'largest_rotation_class',
    cases => [
        [ 'sample',       [ [qw(abcd cdab bcda abdc)] ], 3 ],
        [ 'repeats',      [ [qw(a a b)] ],               2 ],
        [ 'empty',        [ [] ],                        0 ],
        [ 'all distinct', [ [qw(ab abc abcd)] ],         1 ],
        [ 'lengths differ', [ [qw(ab abab ba)] ],        2 ],
    ],
}
