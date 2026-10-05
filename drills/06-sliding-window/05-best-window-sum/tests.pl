+{
    fn    => 'best_window_sum',
    cases => [
        [ 'sample',        [ [ 1, 3, -2, 5, 4 ], 2 ],   9 ],
        [ 'all negative',  [ [ -4, -1, -7 ], 1 ],       -1 ],
        [ 'single',        [ [5], 1 ],                  5 ],
        [ 'k is n',        [ [ 2, -1, 3 ], 3 ],         4 ],
        [ 'first window',  [ [ 9, 9, 1, 1 ], 2 ],       18 ],
    ],
}
