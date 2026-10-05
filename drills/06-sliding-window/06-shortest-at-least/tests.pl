+{
    fn    => 'shortest_at_least',
    cases => [
        [ 'sample',       [ [ 2, 3, 1, 2, 4, 3 ], 7 ],   2 ],
        [ 'impossible',   [ [ 1, 1, 1 ], 100 ],          0 ],
        [ 'one element',  [ [10], 7 ],                   1 ],
        [ 'whole list',   [ [ 1, 2, 3 ], 6 ],            3 ],
        [ 'empty',        [ [], 1 ],                     0 ],
    ],
}
