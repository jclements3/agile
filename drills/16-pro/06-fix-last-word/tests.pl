+{
    fn    => 'fix_last_word',
    cases => [
        [ 'sample, trailing blanks', [ 'hello world  ' ], 'world' ],
        [ 'one word',                [ 'one' ],           'one' ],
        [ 'runs of blanks',          [ 'a  b   c' ],      'c' ],
        [ 'punctuation',             [ 'well-known' ],    'well-known' ],
        [ 'tab and leading blanks',  [ "  fly me to the\tmoon\t" ], 'moon' ],
    ],
}
