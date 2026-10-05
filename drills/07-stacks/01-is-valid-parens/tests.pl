+{
    fn    => 'is_valid_parens',
    cmp   => 'bool',
    cases => [
        [ 'sample',         ['{[()]}'],   1 ],
        [ 'wrong kind',     ['(]'],       0 ],
        [ 'left open',      ['(('],       0 ],
        [ 'empty',          [''],         1 ],
        [ 'closer first',   ['][' ],      0 ],
        [ 'interleaved',    ['([)]'],     0 ],
        [ 'side by side',   ['()[]{}'],   1 ],
    ],
}
