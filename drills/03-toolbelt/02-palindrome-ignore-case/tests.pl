+{
    fn    => 'is_palindrome',
    cmp   => 'bool',
    cases => [
        [ 'sample',     ['Noon'],  1 ],
        [ 'not',        ['hello'], 0 ],
        [ 'empty',      [''],      1 ],
        [ 'one char',   ['x'],     1 ],
        [ 'spaces count', ['a ba'], 0 ],
    ],
}
