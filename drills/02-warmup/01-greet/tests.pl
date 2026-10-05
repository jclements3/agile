+{
    fn    => 'greet',
    cases => [
        [ 'sample',      ['Grace'],        'Hello, Grace!' ],
        [ 'world',       ['world'],        'Hello, world!' ],
        [ 'empty name',  [''],             'Hello, !' ],
        [ 'with spaces', ['Ada Lovelace'], 'Hello, Ada Lovelace!' ],
    ],
}
