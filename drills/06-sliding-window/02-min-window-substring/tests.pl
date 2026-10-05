+{
    fn    => 'min_window',
    cases => [
        [ 'sample',        [ 'xaybzac', 'abc' ],          'bzac' ],
        [ 'whole string',  [ 'aa', 'aa' ],                'aa' ],
        [ 'impossible',    [ 'a', 'b' ],                  '' ],
        [ 'repeat needed', [ 'ab', 'aa' ],                '' ],
        [ 'classic',       [ 'ADOBECODEBANC', 'ABC' ],    'BANC' ],
        [ 'leftmost tie',  [ 'abxba', 'ab' ],             'ab' ],
    ],
}
