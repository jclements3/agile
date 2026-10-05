+{
    fn    => 'by_len_then_alpha',
    cases => [
        [ 'sample', [ [qw(bb a ccc aa)] ],    [qw(a aa bb ccc)] ],
        [ 'empty',  [ [] ],                   [] ],
        [ 'same length', [ [qw(dog cat ant)] ], [qw(ant cat dog)] ],
    ],
}
