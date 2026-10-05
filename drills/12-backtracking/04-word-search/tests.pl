+{
    fn    => 'exist',
    cmp   => 'bool',
    cases => [
        [ 'sample',       [ [qw(ABCE SFCS ADEE)], 'ABCCED' ], 1 ],
        [ 'reuse',        [ [qw(ABCE SFCS ADEE)], 'ABCB' ],   0 ],
        [ 'turns',        [ [qw(ABCE SFCS ADEE)], 'SEE' ],    1 ],
        [ 'one cell',     [ ['a'], 'a' ],                    1 ],
        [ 'too long',     [ ['a'], 'aa' ],                   0 ],
        [ 'backtracks',   [ [qw(AAB AAC)], 'AAAAC' ],        1 ],
    ],
}
