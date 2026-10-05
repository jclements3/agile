+{
    fn    => 'is_palindrome_alnum',
    cmp   => 'bool',
    cases => [
        [ 'sample',         ['No lemon, no melon'], 1 ],
        [ 'not one',        ['ab, c'],              0 ],
        [ 'only symbols',   [' , '],                1 ],
        [ 'empty',          [''],                   1 ],
        [ 'digits count',   ['1a2'],                0 ],
        [ 'mixed case',     ['Racecar'],            1 ],
    ],
}
