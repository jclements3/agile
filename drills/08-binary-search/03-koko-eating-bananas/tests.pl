+{
    fn    => 'min_speed',
    cases => [
        [ 'sample',         [ [ 3, 6, 7, 11 ], 8 ],             4 ],
        [ 'one per hour',   [ [10], 10 ],                       1 ],
        [ 'tight',          [ [ 30, 11, 23, 4, 20 ], 5 ],       30 ],
        [ 'some slack',     [ [ 30, 11, 23, 4, 20 ], 6 ],       23 ],
        [ 'one pile fast',  [ [9], 1 ],                         9 ],
    ],
}
