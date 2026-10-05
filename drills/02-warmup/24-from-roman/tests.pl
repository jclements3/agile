+{
    fn    => 'from_roman',
    cases => [
        [ 'sample',  ['MCMXCIV'], 1994 ],
        [ 'nine',    ['IX'],      9 ],
        [ 'adds',    ['LVIII'],   58 ],
        [ 'three',   ['III'],     3 ],
        [ 'thousands', ['MMM'],   3000 ],
        [ 'largest', ['MMMCMXCIX'], 3999 ],
    ],
}
