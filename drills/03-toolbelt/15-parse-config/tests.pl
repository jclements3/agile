+{
    fn    => 'parse_config',
    cases => [
        [ 'sample',       ["a=1\nb=2"],        { a => 1, b => 2 } ],
        [ 'blank lines',  ["x=5\n\ny=6\n"],    { x => 5, y => 6 } ],
        [ 'empty',        [''],                {} ],
        [ 'spaces only line', ["k=1\n   \nm=-2"], { k => 1, m => -2 } ],
    ],
}
