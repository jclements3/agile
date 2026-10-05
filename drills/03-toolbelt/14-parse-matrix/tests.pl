+{
    fn    => 'parse_matrix',
    cases => [
        [ 'sample',    ["2 2\n1 2\n3 4"], [ [ 1, 2 ], [ 3, 4 ] ] ],
        [ 'one row',   ["1 3\n9 8 7"],    [ [ 9, 8, 7 ] ] ],
        [ 'one column', ["3 1\n1\n2\n3\n"], [ [1], [2], [3] ] ],
        [ 'extra spaces', ["1 2\n  4   5 "], [ [ 4, 5 ] ] ],
    ],
}
