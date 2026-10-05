# the sample first, then the edge cases (two cases come from the lessons' two_sum_indices)
+{
    fn    => 'two_sum',
    cases => [
        [ 'sample',                   [ [ 4, 9, 1, 6 ], 10 ],     [ 1, 2 ] ],
        [ 'equal halves',             [ [ 5, 5 ], 10 ],           [ 0, 1 ] ],
        [ 'no pair',                  [ [ 1, 2 ], 7 ],            [] ],
        [ 'negatives',                [ [ -3, 4, 3, 90 ], 0 ],    [ 0, 2 ] ],
        [ 'earliest index of a dup',  [ [ 4, 2, 4, 4 ], 8 ],      [ 0, 2 ] ],
        [ 'classic',                  [ [ 2, 7, 11, 15 ], 9 ],    [ 0, 1 ] ],
    ],
}
