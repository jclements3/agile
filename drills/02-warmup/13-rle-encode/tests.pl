+{
    fn    => 'rle_encode',
    cases => [
        [ 'sample',    ['aaabbc'],     'a3b2c1' ],
        [ 'no runs',   ['abc'],        'a1b1c1' ],
        [ 'one run',   ['aaaa'],       'a4' ],
        [ 'empty',     [''],           '' ],
        [ 'long run',  ['bbbbbbbbbbbbz'], 'b12z1' ],
        [ 'returns',   ['aabaa'],      'a2b1a2' ],
    ],
}
