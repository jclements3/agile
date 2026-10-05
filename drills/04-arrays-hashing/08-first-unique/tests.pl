+{
    fn    => 'first_unique',
    cases => [
        [ 'sample',       ['lever'],   'l' ],
        [ 'none',         ['xxyy'],    '_' ],
        [ 'empty',        [''],        '_' ],
        [ 'middle',       ['swiss'],   'w' ],
        [ 'last',         ['aabbc'],   'c' ],
    ],
}
