+{
    fn    => 'word_lengths',
    cases => [
        [ 'sample',    ['the quick fox'], { the => 3, quick => 5, fox => 3 } ],
        [ 'repeats',   ['go go go'],      { go => 2 } ],
        [ 'empty',     [''],              {} ],
        [ 'extra spaces', ['  a   bb  '], { a => 1, bb => 2 } ],
    ],
}
