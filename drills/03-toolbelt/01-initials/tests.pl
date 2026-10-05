+{
    fn    => 'initials',
    cases => [
        [ 'sample',       ['ada king lovelace'], 'A.K.L.' ],
        [ 'one word',     ['grace'],             'G.' ],
        [ 'extra spaces', ['  alan   turing '],  'A.T.' ],
        [ 'already upper', ['Edsger Dijkstra'],  'E.D.' ],
    ],
}
