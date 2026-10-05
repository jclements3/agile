+{
    fn    => 'longest_consecutive',
    cases => [
        [ 'sample',      [ [ 10, 3, 20, 1, 2, 4 ] ],         4 ],
        [ 'empty',       [ [] ],                             0 ],
        [ 'one value',   [ [7] ],                            1 ],
        [ 'duplicates',  [ [ 1, 2, 2, 3 ] ],                 3 ],
        [ 'negatives',   [ [ -2, -1, 0, 5, 6 ] ],            3 ],
        [ 'lesson set',  [ [ 100, 4, 200, 1, 3, 2 ] ],       4 ],
    ],
}
