+{
    fn    => 'invert',
    cases => [
        [ 'sample', [ { a => 1, b => 2 } ], { 1 => 'a', 2 => 'b' } ],
        [ 'empty',  [ {} ],                 {} ],
        [ 'words',  [ { x => 'yes', y => 'no' } ], { yes => 'x', no => 'y' } ],
    ],
}
