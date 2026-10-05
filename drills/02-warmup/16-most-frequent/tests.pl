+{
    fn    => 'most_frequent',
    cases => [
        [ 'sample',       [ [ 1, 2, 2, 3, 3 ] ],         2 ],
        [ 'clear winner', [ [ 5, 5, 1 ] ],               5 ],
        [ 'all tie',      [ [ 3, 1, 2 ] ],               1 ],
        [ 'words',        [ [qw(b a b a)] ],             'a' ],
        [ 'numeric order', [ [ 10, 9, 10, 9 ] ],         9 ],
        [ 'one value',    [ [42] ],                      42 ],
    ],
}
