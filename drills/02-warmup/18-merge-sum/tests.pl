+{
    fn    => 'merge_sum',
    cases => [
        [ 'sample',     [ { a => 1, b => 2 }, { b => 3, c => 4 } ], { a => 1, b => 5, c => 4 } ],
        [ 'left empty', [ {}, { x => 1 } ],                         { x => 1 } ],
        [ 'right empty', [ { x => 1 }, {} ],                        { x => 1 } ],
        [ 'cancel',     [ { k => 5 }, { k => -5 } ],                { k => 0 } ],
    ],
}
