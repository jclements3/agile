+{
    fn    => 'is_anagram',
    cmp   => 'bool',
    cases => [
        [ 'sample',        [ 'Listen', 'Silent' ],           1 ],
        [ 'different',     [ 'hello', 'world' ],             0 ],
        [ 'with spaces',   [ 'a gentleman', 'elegant man' ], 1 ],
        [ 'count matters', [ 'ab', 'abb' ],                  0 ],
        [ 'both empty',    [ '', '' ],                       1 ],
    ],
}
