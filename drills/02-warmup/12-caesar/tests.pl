+{
    fn    => 'caesar',
    cases => [
        [ 'sample',      [ 'abc', 2 ],            'cde' ],
        [ 'wrap upper',  [ 'XYZ', 3 ],            'ABC' ],
        [ 'punctuation', [ 'a-b', 1 ],            'b-c' ],
        [ 'rot13',       [ 'Hello, World!', 13 ], 'Uryyb, Jbeyq!' ],
        [ 'zero',        [ 'abc', 0 ],            'abc' ],
        [ 'full turn',   [ 'Zz', 26 ],            'Zz' ],
    ],
}
