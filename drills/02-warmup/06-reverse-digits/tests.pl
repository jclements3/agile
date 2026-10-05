+{
    fn    => 'reverse_digits',
    cases => [
        [ 'sample',        [123],  321 ],
        [ 'negative',      [-45],  -54 ],
        [ 'trailing zero', [120],  21 ],
        [ 'single',        [7],    7 ],
        [ 'zero',          [0],    0 ],
        [ 'neg zeros',     [-900], -9 ],
    ],
}
