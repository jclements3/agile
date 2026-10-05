+{
    fn    => 'search_rotated',
    cases => [
        [ 'sample',        [ [ 4, 5, 6, 1, 2, 3 ], 2 ],         4 ],
        [ 'absent',        [ [ 4, 5, 6, 1, 2, 3 ], 7 ],         -1 ],
        [ 'one element',   [ [1], 1 ],                          0 ],
        [ 'not rotated',   [ [ 1, 3, 5, 7 ], 7 ],               3 ],
        [ 'left half',     [ [ 6, 7, 0, 1, 2, 4, 5 ], 7 ],      1 ],
        [ 'empty',         [ [], 3 ],                           -1 ],
    ],
}
