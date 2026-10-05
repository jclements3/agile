+{
    fn    => 'parse_counted',
    cases => [
        [ 'sample',      ["3\n10 20 30"],    [ 10, 20, 30 ] ],
        [ 'one',         ["1\n7"],           [7] ],
        [ 'extra values', ["2\n5 6 7"],      [ 5, 6 ] ],
        [ 'trailing newline', ["2\n-1 -2\n"], [ -1, -2 ] ],
    ],
}
