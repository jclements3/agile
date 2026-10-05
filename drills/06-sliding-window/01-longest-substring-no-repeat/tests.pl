+{
    fn    => 'longest_no_repeat',
    cases => [
        [ 'sample',    ['pwwkew'],    3 ],
        [ 'empty',     [''],          0 ],
        [ 'abba trap', ['abba'],      2 ],
        [ 'all same',  ['bbbbb'],     1 ],
        [ 'all new',   ['abcdef'],    6 ],
        [ 'classic',   ['abcabcbb'],  3 ],
    ],
}
