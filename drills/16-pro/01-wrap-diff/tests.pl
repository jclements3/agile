+{
    fn    => 'wrap_diff',
    cmp   => 'float',
    cases => [
        [ 'sample',        [ 350, 10 ],  20 ],
        [ 'other order',   [ 10, 350 ],  20 ],
        [ 'opposite',      [ 180, 0 ],   180 ],
        [ 'same',          [ 90, 90 ],   0 ],
        [ 'decimals',      [ 0.5, 359 ], 1.5 ],
        [ 'past a circle', [ 725, 0 ],   5 ],
    ],
}
