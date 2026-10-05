+{
    fn    => 'most_common_word',
    cases => [
        [ 'sample', ['the cat the dog the'], 'the' ],
        [ 'tie',    ['b a a b'],             'a' ],
        [ 'one',    ['solo'],                'solo' ],
        [ 'case matters', ['A a a B B'],     'B' ],
    ],
}
