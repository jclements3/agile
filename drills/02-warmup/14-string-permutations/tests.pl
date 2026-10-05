+{
    fn    => 'string_permutations',
    cases => [
        [ 'sample',     ['abc'], [qw(abc acb bac bca cab cba)] ],
        [ 'duplicates', ['aab'], [qw(aab aba baa)] ],
        [ 'one',        ['x'],   ['x'] ],
        [ 'empty',      [''],    [''] ],
        [ 'all same',   ['zzz'], ['zzz'] ],
    ],
}
