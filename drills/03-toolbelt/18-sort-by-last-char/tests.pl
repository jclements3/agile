+{
    fn    => 'sort_by_last_char',
    cases => [
        [ 'sample', [ [qw(banana cherry fig)] ], [qw(banana fig cherry)] ],
        [ 'stable', [ [qw(cb ab bb)] ],          [qw(cb ab bb)] ],
        [ 'empty',  [ [] ],                      [] ],
        [ 'mixed',  [ [qw(zy xa wy va)] ],       [qw(xa va zy wy)] ],
    ],
}
