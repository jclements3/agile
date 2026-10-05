+{
    fn    => 'count_by_length',
    cases => [
        [ 'sample', [ [qw(a bb cc d)] ], { 1 => 2, 2 => 2 } ],
        [ 'empty',  [ [] ],              {} ],
        [ 'one',    [ ['hello'] ],       { 5 => 1 } ],
    ],
}
