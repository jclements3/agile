+{
    fn    => 'find_min_rotated',
    cases => [
        [ 'sample',       [ [ 5, 7, 9, 1, 3 ] ],         1 ],
        [ 'not rotated',  [ [ 2, 4, 6 ] ],               2 ],
        [ 'one element',  [ [8] ],                       8 ],
        [ 'two',          [ [ 2, 1 ] ],                  1 ],
        [ 'last place',   [ [ 3, 4, 5, 6, 0 ] ],         0 ],
    ],
}
