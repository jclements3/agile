+{
    fn    => 'can_partition_k',
    cmp   => 'bool',
    cases => [
        [ 'sample',            [ [ 4, 3, 2, 3, 5, 2, 1 ], 4 ], 1 ],
        [ 'sum not divisible', [ [ 1, 2, 3, 4 ], 3 ],          0 ],
        [ 'one group',         [ [ 7, 1 ], 1 ],                1 ],
        [ 'a value too big',   [ [ 10, 1, 1 ], 2 ],            0 ],
        [ 'divisible but no',  [ [ 2, 2, 2, 2, 3, 4, 5 ], 4 ], 0 ],
        [ 'pairs',             [ [ 1, 1, 1, 1, 2, 2, 2, 2 ], 4 ], 1 ],
    ],
}
