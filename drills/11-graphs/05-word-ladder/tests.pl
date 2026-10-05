+{
    fn    => 'ladder_length',
    cases => [
        [ 'sample',           [ 'cold', 'warm', [qw(cord card ward warm word wore)] ], 5 ],
        [ 'end not in list',  [ 'ab', 'cd', [qw(ad)] ],                                0 ],
        [ 'one step',         [ 'hot', 'dot', [qw(dot)] ],                             2 ],
        [ 'no path',          [ 'aaa', 'bbb', [qw(aab bbb)] ],                         0 ],
        [ 'shortest of two',  [ 'hit', 'cog', [qw(hot dot dog lot log cog)] ],         5 ],
    ],
}
