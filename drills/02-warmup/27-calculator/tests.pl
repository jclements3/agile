+{
    fn    => 'evaluate',
    cases => [
        [ 'sample',       ['2*(3+4)-5'],  9 ],
        [ 'parens',       ['2*(3+4)'],    14 ],
        [ 'left to right', ['10-2-3'],    5 ],
        [ 'precedence',   ['2+3*4'],      14 ],
        [ 'nested',       ['((1+2))*3'],  9 ],
        [ 'spaces',       [' 12 * 2 '],   24 ],
        [ 'one number',   ['42'],         42 ],
    ],
}
