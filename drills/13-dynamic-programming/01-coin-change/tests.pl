+{
    fn    => 'coin_change',
    cases => [
        [ 'sample',         [ [ 1, 2, 5 ], 11 ], 3 ],
        [ 'greedy is wrong',[ [ 1, 3, 4 ], 6 ],  2 ],
        [ 'impossible',     [ [2], 3 ],          -1 ],
        [ 'zero amount',    [ [7], 0 ],          0 ],
        [ 'one coin type',  [ [3], 9 ],          3 ],
        [ 'bigger amount',  [ [ 186, 419, 83, 408 ], 6249 ], 20 ],
    ],
}
