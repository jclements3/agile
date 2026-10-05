+{
    fn    => 'to_roman',
    cases => [
        [ 'sample',  [1994], 'MCMXCIV' ],
        [ 'nine',    [9],    'IX' ],
        [ 'fifty-eight', [58], 'LVIII' ],
        [ 'thousands', [3000], 'MMM' ],
        [ 'one',     [1],    'I' ],
        [ 'largest', [3999], 'MMMCMXCIX' ],
    ],
}
