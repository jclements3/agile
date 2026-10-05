+{
    fn    => 'rect_area',
    cmp   => 'float',
    cases => [
        [ 'sample',    [ 3, 4 ],     12 ],
        [ 'decimal',   [ 2.5, 4 ],   10 ],
        [ 'zero side', [ 0, 99 ],    0 ],
        [ 'both decimals', [ 0.5, 0.5 ], 0.25 ],
    ],
}
